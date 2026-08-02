import 'package:dio/dio.dart';

import '../calendar/calendar.dart';
import '../client/webdav_client.dart';
import '../exceptions/caldav_exception.dart';
import '../sync/calendar_sync_result.dart';
import '../utils/icalendar_utils.dart';
import '../webdav/dav_depth.dart';
import '../webdav/multistatus.dart';
import '../webdav/sync_collection.dart';
import '../webdav/sync_service.dart';
import '../webdav/xml_namespaces.dart';
import 'event.dart';
import 'icalendar_parser.dart';
import 'journal.dart';
import 'todo.dart';

/// Service for event CRUD operations
class EventService {
  final WebDavClient _client;
  final SyncService _syncService;

  EventService(this._client) : _syncService = SyncService(_client);

  /// Parse a single DavResponse into CalendarEvent
  CalendarEvent? _parseEventFromResponse(
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

    return ICalendarParser.parseEvent(
      calendarData,
      calendarId: calendar.uid,
      href: calendar.href.resolve(davResponse.href),
      etag: etag,
      isReadOnly: calendar.isReadOnly,
    );
  }

  /// Parse multiple DavResponses into CalendarEvents
  List<CalendarEvent> _parseEventsFromResponses(
    List<DavResponse> responses,
    Calendar calendar,
  ) {
    final events = <CalendarEvent>[];
    for (final davResponse in responses) {
      final event = _parseEventFromResponse(davResponse, calendar);
      if (event != null) events.add(event);
    }
    return events;
  }

  /// List events in a calendar
  ///
  /// Uses calendar-query with time-range filter for server-side filtering.
  /// If server doesn't return calendar-data (like Naver), uses the filtered
  /// URLs with calendar-multiget to fetch actual event data.
  ///
  /// [calendar] Target calendar
  /// [start] Filter start date (optional, UTC)
  /// [end] Filter end date (optional, UTC)
  Future<List<CalendarEvent>> list(
    Calendar calendar, {
    DateTime? start,
    DateTime? end,
  }) async {
    final body = _buildCalendarQueryBody(start: start, end: end);

    try {
      final response = await _client.report(
        calendar.href.toString(),
        body: body,
        depth: DavDepth.one,
      );

      final multiStatus = MultiStatus.fromXml(response.data ?? '');
      if (multiStatus.responses.isEmpty) return [];

      // Try to parse events directly from response
      final events = _parseEventsFromResponses(multiStatus.responses, calendar);
      if (events.isNotEmpty) return events;

      // Collect URLs without calendar-data (Naver-style servers)
      final urlsWithoutData = multiStatus.responses
          .where((r) => r.href.endsWith('.ics'))
          .map((r) => r.href)
          .toList();

      // Fetch via multiget if we have URLs but no calendar-data
      if (urlsWithoutData.isNotEmpty) {
        return _fetchWithMultiget(calendar, urlsWithoutData);
      }

      return [];
    } on DioException catch (e) {
      throw _mapException(e, 'Failed to list events');
    }
  }

  /// Batch fetch events using calendar-multiget
  Future<List<CalendarEvent>> _fetchWithMultiget(
    Calendar calendar,
    List<String> eventPaths,
  ) async {
    if (eventPaths.isEmpty) return [];

    // Build href elements for multiget (escape XML special characters)
    final hrefs = eventPaths
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
      return _parseEventsFromResponses(multiStatus.responses, calendar);
    } on DioException catch (e) {
      throw _mapException(e, 'Failed to fetch events');
    }
  }

  /// Create a new event
  ///
  /// Returns the created event with href and etag
  Future<CalendarEvent> create(Calendar calendar, CalendarEvent event) async {
    final eventPath = calendar.href.resolve('${event.uid}.ics');

    try {
      final response = await _client.put(
        eventPath.toString(),
        body: event.toIcalendar(),
        contentType: 'text/calendar; charset=utf-8',
        ifNoneMatch: '*', // Only create if not exists
      );

      final etag = response.headers.value('etag');

      return event.copyWith(
        href: eventPath,
        etag: etag,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 412) {
        throw const ConflictException('Event already exists');
      }
      throw _mapException(e, 'Failed to create event');
    }
  }

  /// Update an existing event
  ///
  /// Uses ETag for optimistic locking if available
  Future<CalendarEvent> update(CalendarEvent event) async {
    if (event.href == null) {
      throw const CalDavException('Event href is required for update');
    }

    try {
      final response = await _client.put(
        event.href.toString(),
        body: event.toIcalendar(),
        contentType: 'text/calendar; charset=utf-8',
        ifMatch: event.etag, // Optimistic locking
      );

      final newEtag = response.headers.value('etag');

      return event.copyWith(etag: newEtag);
    } on DioException catch (e) {
      if (e.response?.statusCode == 412) {
        throw const ConflictException(
            'Event was modified by another client. Please refresh and try again.');
      }
      throw _mapException(e, 'Failed to update event');
    }
  }

  /// Delete an event
  Future<void> delete(CalendarEvent event) async {
    if (event.href == null) {
      throw const CalDavException('Event href is required for delete');
    }

    try {
      await _client.delete(
        event.href.toString(),
        ifMatch: event.etag,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        // Already deleted, consider success
        return;
      }
      if (e.response?.statusCode == 412) {
        throw const ConflictException(
            'Event was modified by another client. Please refresh and try again.');
      }
      throw _mapException(e, 'Failed to delete event');
    }
  }

  /// Get multiple events by URLs (multiget)
  Future<List<CalendarEvent>> multiGet(
    Calendar calendar,
    List<Uri> eventUrls,
  ) async {
    if (eventUrls.isEmpty) return [];

    final hrefs = eventUrls
        .map((u) => '<D:href>${ICalendarUtils.escapeXml(u.path)}</D:href>')
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
      return _parseEventsFromResponses(multiStatus.responses, calendar);
    } on DioException catch (e) {
      throw _mapException(e, 'Failed to get events');
    }
  }

  /// Find an event by UID in a specific calendar
  ///
  /// Uses server-side filtering via calendar-query for efficiency.
  /// If server doesn't return calendar-data (like Naver), uses multiget fallback.
  /// Returns null if no event is found.
  Future<CalendarEvent?> findByUid(Calendar calendar, String uid) async {
    final body = _buildUidQueryBody(uid);

    try {
      final response = await _client.report(
        calendar.href.toString(),
        body: body,
        depth: DavDepth.one,
      );

      final multiStatus = MultiStatus.fromXml(response.data ?? '');
      if (multiStatus.responses.isEmpty) return null;

      // Try to parse event directly
      for (final davResponse in multiStatus.responses) {
        final event = _parseEventFromResponse(davResponse, calendar);
        if (event != null) return event;
      }

      // Fallback: get URL and fetch via multiget (Naver-style)
      final urlWithoutData = multiStatus.responses
          .where((r) => r.href.endsWith('.ics'))
          .map((r) => r.href)
          .firstOrNull;

      if (urlWithoutData != null) {
        final events = await _fetchWithMultiget(calendar, [urlWithoutData]);
        return events.isNotEmpty ? events.first : null;
      }

      return null;
    } on DioException catch (e) {
      throw _mapException(e, 'Failed to find event by UID');
    }
  }

  /// Synchronize calendar members via RFC 6578 `sync-collection`.
  ///
  /// Pass [syncToken] from a previous [CalendarSyncResult] for an incremental
  /// sync; omit (or pass null/empty) for a full baseline.
  ///
  /// When [followTruncation] is true (default), pages are followed until the
  /// server stops reporting `number-of-matches-within-limits`.
  ///
  /// Throws [InvalidSyncTokenException] when the token is no longer valid —
  /// discard local state and re-sync with a null token.
  Future<CalendarSyncResult> sync(
    Calendar calendar, {
    String? syncToken,
    int? limit,
    bool includeData = true,
    bool followTruncation = true,
    SyncLevel level = SyncLevel.members,
  }) async {
    final CollectionSyncResult raw;
    if (followTruncation) {
      raw = await _syncService.syncCollectionFully(
        calendar.href,
        rebuild: (token) => SyncCollectionBuilder.calendar(
          syncToken: token ?? syncToken,
          level: level,
          limit: limit,
          includeData: includeData,
        ),
      );
    } else {
      raw = await _syncService.syncCollection(
        calendar.href,
        SyncCollectionBuilder.calendar(
          syncToken: syncToken,
          level: level,
          limit: limit,
          includeData: includeData,
        ),
      );
    }

    return _toCalendarSyncResult(raw, calendar);
  }

  /// Read the collection's current `DAV:sync-token` without listing members.
  Future<String?> getSyncToken(Calendar calendar) =>
      _syncService.getSyncToken(calendar.href);

  CalendarSyncResult _toCalendarSyncResult(
    CollectionSyncResult raw,
    Calendar calendar,
  ) {
    final events = <CalendarEvent>[];
    final todos = <CalendarTodo>[];
    final journals = <CalendarJournal>[];
    final deleted = <Uri>[];

    for (final change in raw.changes) {
      if (change.isDeleted) {
        deleted.add(change.resolvedHref);
        continue;
      }
      final data = change.data;
      if (data == null || data.isEmpty) continue;

      final event = ICalendarParser.parseEvent(
        data,
        calendarId: calendar.uid,
        href: change.resolvedHref,
        etag: change.etag,
        isReadOnly: calendar.isReadOnly,
      );
      if (event != null) {
        events.add(event);
        continue;
      }

      final todo = ICalendarParser.parseTodo(
        data,
        calendarId: calendar.uid,
        href: change.resolvedHref,
        etag: change.etag,
        isReadOnly: calendar.isReadOnly,
      );
      if (todo != null) {
        todos.add(todo);
        continue;
      }

      final journal = ICalendarParser.parseJournal(
        data,
        calendarId: calendar.uid,
        href: change.resolvedHref,
        etag: change.etag,
        isReadOnly: calendar.isReadOnly,
      );
      if (journal != null) {
        journals.add(journal);
      }
    }

    return CalendarSyncResult(
      syncToken: raw.syncToken,
      events: events,
      todos: todos,
      journals: journals,
      deletedHrefs: deleted,
      rawChanges: raw.changes,
      truncated: raw.truncated,
    );
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

  String _buildUidQueryBody(String uid) {
    final escapedUid = ICalendarUtils.escapeXml(uid);

    return '''<?xml version="1.0" encoding="utf-8"?>
<C:calendar-query xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
  <D:prop>
    <D:getetag/>
    <C:calendar-data/>
  </D:prop>
  <C:filter>
    <C:comp-filter name="VCALENDAR">
      <C:comp-filter name="VEVENT">
        <C:prop-filter name="UID">
          <C:text-match collation="i;octet">$escapedUid</C:text-match>
        </C:prop-filter>
      </C:comp-filter>
    </C:comp-filter>
  </C:filter>
</C:calendar-query>''';
  }

  String _buildCalendarQueryBody({
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
      <C:comp-filter name="VEVENT">
        $timeRange
      </C:comp-filter>
    </C:comp-filter>
  </C:filter>
</C:calendar-query>''';
  }
}
