import 'package:dio/dio.dart';

import '../calendar/calendar.dart';
import '../client/webdav_client.dart';
import '../exceptions/caldav_exception.dart';
import '../utils/icalendar_utils.dart';
import '../webdav/dav_depth.dart';
import '../webdav/multistatus.dart';
import '../webdav/xml_namespaces.dart';
import 'free_busy.dart';
import 'free_busy_parser.dart';

/// CalDAV free/busy operations (RFC 4791 §7.10, RFC 6638 scheduling).
class FreeBusyService {
  final WebDavClient _client;

  FreeBusyService(this._client);

  /// Run `CALDAV:free-busy-query` against a calendar (or free-busy) collection.
  ///
  /// [start] / [end] define the query range (UTC recommended).
  /// The response is typically `text/calendar` containing a VFREEBUSY component.
  Future<FreeBusy> query(
    Uri collectionUrl, {
    required DateTime start,
    required DateTime end,
  }) async {
    if (!end.isAfter(start)) {
      throw const CalDavException(
        'Free/busy query end must be after start',
      );
    }

    final body = buildFreeBusyQueryBody(start: start, end: end);

    try {
      final response = await _client.report(
        collectionUrl.toString(),
        body: body,
        depth: DavDepth.zero,
      );

      final data = response.data ?? '';
      if (data.isEmpty) {
        return FreeBusy(
          dtstart: start.toUtc(),
          dtend: end.toUtc(),
          sourceUrl: collectionUrl,
        );
      }

      // Prefer direct VFREEBUSY body (common for free-busy-query).
      final direct = FreeBusyParser.parse(data, sourceUrl: collectionUrl);
      if (direct != null) {
        return direct.copyWith(
          dtstart: direct.dtstart ?? start.toUtc(),
          dtend: direct.dtend ?? end.toUtc(),
          sourceUrl: collectionUrl,
        );
      }

      // Some servers wrap calendar-data in multistatus.
      if (data.contains('multistatus') || data.contains('calendar-data')) {
        try {
          final multi = MultiStatus.fromXml(data);
          for (final r in multi.responses) {
            final calData = r.getProperty(
              'calendar-data',
              namespace: XmlNamespaces.caldav,
            );
            if (calData == null || calData.isEmpty) continue;
            final parsed =
                FreeBusyParser.parse(calData, sourceUrl: collectionUrl);
            if (parsed != null) {
              return parsed.copyWith(
                dtstart: parsed.dtstart ?? start.toUtc(),
                dtend: parsed.dtend ?? end.toUtc(),
                sourceUrl: collectionUrl,
              );
            }
          }
        } catch (_) {
          // Fall through to empty result if multistatus is malformed.
        }
      }

      return FreeBusy(
        dtstart: start.toUtc(),
        dtend: end.toUtc(),
        sourceUrl: collectionUrl,
        rawIcalendar: data,
      );
    } on DioException catch (e) {
      throw _mapException(e, 'Failed to query free/busy');
    }
  }

  /// Query free/busy for a [Calendar] collection.
  Future<FreeBusy> queryCalendar(
    Calendar calendar, {
    required DateTime start,
    required DateTime end,
  }) {
    return query(calendar.href, start: start, end: end);
  }

  /// Query free/busy for each URL in [collectionUrls] (e.g. free-busy-set).
  ///
  /// Failures on individual URLs are skipped when [skipErrors] is true
  /// (default); otherwise the first error is rethrown.
  Future<List<FreeBusy>> queryMany(
    List<Uri> collectionUrls, {
    required DateTime start,
    required DateTime end,
    bool skipErrors = true,
  }) async {
    final results = <FreeBusy>[];
    for (final url in collectionUrls) {
      try {
        results.add(await query(url, start: start, end: end));
      } catch (e) {
        if (!skipErrors) rethrow;
      }
    }
    return results;
  }

  /// Request free/busy via a scheduling Outbox (RFC 6638).
  ///
  /// Posts a `METHOD:REQUEST` VFREEBUSY to [outboxUrl]. Many servers return
  /// `text/calendar` with one or more freebusy replies; some return 200 with
  /// empty body and deliver replies to the Inbox instead.
  Future<List<FreeBusy>> requestScheduleFreeBusy({
    required Uri outboxUrl,
    required DateTime start,
    required DateTime end,
    required List<String> attendees,
    String? organizer,
    String? uid,
  }) async {
    if (attendees.isEmpty) {
      throw const CalDavException(
        'At least one attendee is required for schedule free/busy',
      );
    }
    if (!end.isAfter(start)) {
      throw const CalDavException(
        'Free/busy query end must be after start',
      );
    }

    final body = FreeBusyParser.buildScheduleRequest(
      start: start,
      end: end,
      attendees: attendees,
      organizer: organizer,
      uid: uid,
    );

    try {
      final response = await _client.post(
        outboxUrl.toString(),
        body: body,
        contentType: 'text/calendar; charset=utf-8',
      );
      final data = response.data ?? '';
      return _parsePossiblyMultipleFreeBusy(data);
    } on DioException catch (e) {
      throw _mapException(e, 'Failed to request schedule free/busy');
    }
  }

  List<FreeBusy> _parsePossiblyMultipleFreeBusy(String data) {
    if (data.isEmpty) return const [];
    final single = FreeBusyParser.parse(data);
    if (single != null) return [single];
    // Multiple VFREEBUSY in one document
    final results = <FreeBusy>[];
    final parts = data.split(RegExp(r'(?=BEGIN:VFREEBUSY)'));
    for (final part in parts) {
      if (!part.contains('BEGIN:VFREEBUSY')) continue;
      final wrapped = part.contains('BEGIN:VCALENDAR')
          ? part
          : 'BEGIN:VCALENDAR\nVERSION:2.0\n$part\nEND:VCALENDAR';
      final parsed = FreeBusyParser.parse(wrapped);
      if (parsed != null) results.add(parsed);
    }
    return results;
  }

  /// Build a free-busy-query REPORT body (RFC 4791).
  static String buildFreeBusyQueryBody({
    required DateTime start,
    required DateTime end,
  }) {
    final s = ICalendarUtils.formatUtc(start.toUtc());
    final e = ICalendarUtils.formatUtc(end.toUtc());
    return '''<?xml version="1.0" encoding="utf-8"?>
<C:free-busy-query xmlns:C="urn:ietf:params:xml:ns:caldav">
  <C:time-range start="$s" end="$e"/>
</C:free-busy-query>''';
  }

  static CalDavException _mapException(DioException e, String context) {
    return switch (e.response?.statusCode) {
      401 => const AuthenticationException(),
      403 => const ForbiddenException(),
      404 => const NotFoundException(),
      _ => CalDavException(
          '$context: ${e.message}',
          statusCode: e.response?.statusCode,
        ),
    };
  }
}
