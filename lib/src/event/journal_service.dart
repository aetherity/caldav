import 'package:dio/dio.dart';

import '../calendar/calendar.dart';
import '../client/webdav_client.dart';
import '../exceptions/caldav_exception.dart';
import '../utils/icalendar_utils.dart';
import '../webdav/dav_depth.dart';
import '../webdav/multistatus.dart';
import '../webdav/xml_namespaces.dart';
import 'icalendar_parser.dart';
import 'journal.dart';

/// Service for VJOURNAL (journal entry) CRUD operations.
///
/// Mirrors [TodoService] / [EventService] but targets VJOURNAL components.
class JournalService {
  final WebDavClient _client;

  JournalService(this._client);

  CalendarJournal? _parseJournalFromResponse(
    DavResponse davResponse,
    Calendar calendar,
  ) {
    final calendarData = davResponse.getProperty(
      'calendar-data',
      namespace: XmlNamespaces.caldav,
    );

    if (calendarData == null || calendarData.isEmpty) return null;

    final etag = davResponse.getProperty(
      'getetag',
      namespace: XmlNamespaces.dav,
    );

    return ICalendarParser.parseJournal(
      calendarData,
      calendarId: calendar.uid,
      href: calendar.href.resolve(davResponse.href),
      etag: etag,
      isReadOnly: calendar.isReadOnly,
    );
  }

  List<CalendarJournal> _parseJournalsFromResponses(
    List<DavResponse> responses,
    Calendar calendar,
  ) {
    final journals = <CalendarJournal>[];
    for (final davResponse in responses) {
      final journal = _parseJournalFromResponse(davResponse, calendar);
      if (journal != null) journals.add(journal);
    }
    return journals;
  }

  /// List journals in a calendar.
  ///
  /// [start]/[end] apply a server-side time-range filter when both are given;
  /// otherwise all journals are returned (recommended, since many journals
  /// have no DTSTART and would be missed by a time-range filter).
  Future<List<CalendarJournal>> list(
    Calendar calendar, {
    DateTime? start,
    DateTime? end,
  }) async {
    final body = buildCalendarQueryBody(start: start, end: end);

    try {
      final response = await _client.report(
        calendar.href.toString(),
        body: body,
        depth: DavDepth.one,
      );

      final multiStatus = MultiStatus.fromXml(response.data ?? '');
      if (multiStatus.responses.isEmpty) return [];

      final journals =
          _parseJournalsFromResponses(multiStatus.responses, calendar);
      if (journals.isNotEmpty) return journals;

      final urlsWithoutData = multiStatus.responses
          .where((r) => r.href.endsWith('.ics'))
          .map((r) => r.href)
          .toList();

      if (urlsWithoutData.isNotEmpty) {
        return await _fetchWithMultiget(calendar, urlsWithoutData);
      }

      return [];
    } on DioException catch (e) {
      throw _mapException(e, 'Failed to list journals');
    }
  }

  Future<List<CalendarJournal>> _fetchWithMultiget(
    Calendar calendar,
    List<String> journalPaths,
  ) async {
    if (journalPaths.isEmpty) return [];

    final hrefs = journalPaths
        .map((p) => '<D:href>${ICalendarUtils.escapeXml(p)}</D:href>')
        .join('\n');

    final body = '''<?xml version="1.0" encoding="utf-8"?>
<C:calendar-multiget xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
  <D:prop>
    <D:getetag/>
    <C:calendar-data/>
  </D:prop>
  $hrefs
</C:calendar-multiget>''';

    try {
      final response = await _client.report(
        calendar.href.toString(),
        body: body,
        depth: DavDepth.one,
      );

      final multiStatus = MultiStatus.fromXml(response.data ?? '');
      return _parseJournalsFromResponses(multiStatus.responses, calendar);
    } on DioException catch (e) {
      throw _mapException(e, 'Failed to fetch journals');
    }
  }

  /// Create a new journal. Returns the created journal with href and etag.
  Future<CalendarJournal> create(
    Calendar calendar,
    CalendarJournal journal,
  ) async {
    final path = calendar.href.resolve('${journal.uid}.ics');

    try {
      final response = await _client.put(
        path.toString(),
        body: journal.toIcalendar(),
        contentType: 'text/calendar; charset=utf-8',
        ifNoneMatch: '*',
      );

      final etag = response.headers.value('etag');
      return journal.copyWith(href: path, etag: etag);
    } on DioException catch (e) {
      if (e.response?.statusCode == 412) {
        throw const ConflictException('Journal already exists');
      }
      throw _mapException(e, 'Failed to create journal');
    }
  }

  /// Update an existing journal (ETag optimistic locking when available).
  Future<CalendarJournal> update(CalendarJournal journal) async {
    if (journal.href == null) {
      throw const CalDavException('Journal href is required for update');
    }

    try {
      final response = await _client.put(
        journal.href.toString(),
        body: journal.toIcalendar(),
        contentType: 'text/calendar; charset=utf-8',
        ifMatch: journal.etag,
      );

      final newEtag = response.headers.value('etag');
      return journal.copyWith(etag: newEtag);
    } on DioException catch (e) {
      if (e.response?.statusCode == 412) {
        throw const ConflictException(
          'Journal was modified by another client. Please refresh and try again.',
        );
      }
      throw _mapException(e, 'Failed to update journal');
    }
  }

  /// Delete a journal.
  Future<void> delete(CalendarJournal journal) async {
    if (journal.href == null) {
      throw const CalDavException('Journal href is required for delete');
    }

    try {
      await _client.delete(
        journal.href.toString(),
        ifMatch: journal.etag,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return;
      }
      if (e.response?.statusCode == 412) {
        throw const ConflictException(
          'Journal was modified by another client. Please refresh and try again.',
        );
      }
      throw _mapException(e, 'Failed to delete journal');
    }
  }

  /// Find a journal by UID in a specific calendar. Returns null if not found.
  Future<CalendarJournal?> findByUid(Calendar calendar, String uid) async {
    final body = buildUidQueryBody(uid);

    try {
      final response = await _client.report(
        calendar.href.toString(),
        body: body,
        depth: DavDepth.one,
      );

      final multiStatus = MultiStatus.fromXml(response.data ?? '');
      if (multiStatus.responses.isEmpty) return null;

      for (final davResponse in multiStatus.responses) {
        final journal = _parseJournalFromResponse(davResponse, calendar);
        if (journal != null) return journal;
      }

      final urlWithoutData = multiStatus.responses
          .where((r) => r.href.endsWith('.ics'))
          .map((r) => r.href)
          .firstOrNull;

      if (urlWithoutData != null) {
        final journals =
            await _fetchWithMultiget(calendar, [urlWithoutData]);
        return journals.isNotEmpty ? journals.first : null;
      }

      return null;
    } on DioException catch (e) {
      throw _mapException(e, 'Failed to find journal by UID');
    }
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

  /// Build a calendar-query REPORT body filtering on VJOURNAL.
  static String buildCalendarQueryBody({
    DateTime? start,
    DateTime? end,
  }) {
    final timeRange = (start != null && end != null)
        ? '<C:time-range start="${ICalendarUtils.formatUtc(start)}" end="${ICalendarUtils.formatUtc(end)}"/>'
        : '';

    return '''<?xml version="1.0" encoding="utf-8"?>
<C:calendar-query xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
  <D:prop>
    <D:getetag/>
    <C:calendar-data/>
  </D:prop>
  <C:filter>
    <C:comp-filter name="VCALENDAR">
      <C:comp-filter name="VJOURNAL">
        $timeRange
      </C:comp-filter>
    </C:comp-filter>
  </C:filter>
</C:calendar-query>''';
  }

  /// Build a calendar-query REPORT body matching a VJOURNAL by UID.
  static String buildUidQueryBody(String uid) {
    final escapedUid = ICalendarUtils.escapeXml(uid);

    return '''<?xml version="1.0" encoding="utf-8"?>
<C:calendar-query xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
  <D:prop>
    <D:getetag/>
    <C:calendar-data/>
  </D:prop>
  <C:filter>
    <C:comp-filter name="VCALENDAR">
      <C:comp-filter name="VJOURNAL">
        <C:prop-filter name="UID">
          <C:text-match collation="i;octet">$escapedUid</C:text-match>
        </C:prop-filter>
      </C:comp-filter>
    </C:comp-filter>
  </C:filter>
</C:calendar-query>''';
  }
}
