import 'package:caldav/caldav.dart';
import 'package:caldav/src/freebusy/free_busy_service.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  group('FreeBusyType', () {
    test('parses FBTYPE tokens', () {
      expect(FreeBusyType.parse(null), FreeBusyType.busy);
      expect(FreeBusyType.parse('FREE'), FreeBusyType.free);
      expect(FreeBusyType.parse('BUSY-UNAVAILABLE'), FreeBusyType.busyUnavailable);
      expect(FreeBusyType.parse('BUSY-TENTATIVE'), FreeBusyType.busyTentative);
      expect(FreeBusyType.parse('busy'), FreeBusyType.busy);
    });
  });

  group('FreeBusyParser', () {
    test('parses VFREEBUSY with period start/end and types', () {
      const ical = '''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VFREEBUSY
UID:fb-1
DTSTART:20260801T000000Z
DTEND:20260808T000000Z
ORGANIZER:mailto:me@example.com
ATTENDEE:mailto:you@example.com
FREEBUSY;FBTYPE=BUSY:20260802T130000Z/20260802T140000Z
FREEBUSY;FBTYPE=BUSY-TENTATIVE:20260803T090000Z/20260803T100000Z
FREEBUSY;FBTYPE=FREE:20260804T120000Z/20260804T130000Z
END:VFREEBUSY
END:VCALENDAR''';

      final fb = FreeBusyParser.parse(ical);
      expect(fb, isNotNull);
      expect(fb!.uid, 'fb-1');
      expect(fb.dtstart, DateTime.utc(2026, 8, 1));
      expect(fb.dtend, DateTime.utc(2026, 8, 8));
      expect(fb.organizer, 'me@example.com');
      expect(fb.attendees, ['you@example.com']);
      expect(fb.periods, hasLength(3));
      expect(fb.busyPeriods, hasLength(2));
      expect(fb.freePeriods, hasLength(1));
      expect(fb.periods[0].type, FreeBusyType.busy);
      expect(fb.periods[0].start, DateTime.utc(2026, 8, 2, 13));
      expect(fb.periods[0].end, DateTime.utc(2026, 8, 2, 14));
      expect(fb.isBusyAt(DateTime.utc(2026, 8, 2, 13, 30)), isTrue);
      expect(fb.isBusyAt(DateTime.utc(2026, 8, 2, 15)), isFalse);
    });

    test('parses FREEBUSY with duration form', () {
      const ical = '''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VFREEBUSY
UID:fb-d
FREEBUSY:20260802T130000Z/PT1H30M
END:VFREEBUSY
END:VCALENDAR''';

      final fb = FreeBusyParser.parse(ical)!;
      expect(fb.periods, hasLength(1));
      expect(fb.periods.single.start, DateTime.utc(2026, 8, 2, 13));
      expect(fb.periods.single.end, DateTime.utc(2026, 8, 2, 14, 30));
    });

    test('parses FREEBUSY duration with weeks and days', () {
      const ical = '''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VFREEBUSY
UID:fb-wd
FREEBUSY:20260802T130000Z/P1W1DT1H1M1S
END:VFREEBUSY
END:VCALENDAR''';

      final fb = FreeBusyParser.parse(ical)!;
      expect(fb.periods, hasLength(1));
      expect(fb.periods.single.start, DateTime.utc(2026, 8, 2, 13));
      expect(fb.periods.single.end, DateTime.utc(2026, 8, 10, 14, 1, 1));
    });

    test('parses comma-separated periods on one FREEBUSY line', () {
      const ical = '''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VFREEBUSY
UID:fb-c
FREEBUSY:20260802T100000Z/20260802T110000Z,20260802T150000Z/20260802T160000Z
END:VFREEBUSY
END:VCALENDAR''';

      final fb = FreeBusyParser.parse(ical)!;
      expect(fb.periods, hasLength(2));
    });

    test('returns null without VFREEBUSY', () {
      const ical = '''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:e
DTSTART:20260802T100000Z
SUMMARY:X
END:VEVENT
END:VCALENDAR''';
      expect(FreeBusyParser.parse(ical), isNull);
    });

    test('buildScheduleRequest includes METHOD REQUEST and attendees', () {
      final body = FreeBusyParser.buildScheduleRequest(
        start: DateTime.utc(2026, 8, 1),
        end: DateTime.utc(2026, 8, 2),
        attendees: ['a@example.com', 'mailto:b@example.com'],
        organizer: 'me@example.com',
        uid: 'req-1',
      );
      expect(body, contains('METHOD:REQUEST'));
      expect(body, contains('BEGIN:VFREEBUSY'));
      expect(body, contains('UID:req-1'));
      expect(body, contains('ATTENDEE:mailto:a@example.com'));
      expect(body, contains('ATTENDEE:mailto:b@example.com'));
      expect(body, contains('ORGANIZER:mailto:me@example.com'));
      expect(body, contains('DTSTART:20260801T000000Z'));
      expect(body, contains('DTEND:20260802T000000Z'));
    });

    test('serialize round-trips periods', () {
      final original = FreeBusy(
        uid: 's1',
        periods: [
          FreeBusyPeriod(
            start: DateTime.utc(2026, 8, 2, 10),
            end: DateTime.utc(2026, 8, 2, 11),
            type: FreeBusyType.busyUnavailable,
          ),
        ],
      );
      final ical = FreeBusyParser.serialize(original);
      final parsed = FreeBusyParser.parse(ical)!;
      expect(parsed.uid, 's1');
      expect(parsed.periods.single.type, FreeBusyType.busyUnavailable);
      expect(parsed.periods.single.start, DateTime.utc(2026, 8, 2, 10));
    });
  });

  group('FreeBusyService', () {
    test('buildFreeBusyQueryBody includes time-range', () {
      final body = FreeBusyService.buildFreeBusyQueryBody(
        start: DateTime.utc(2026, 8, 1),
        end: DateTime.utc(2026, 8, 8),
      );
      expect(body, contains('free-busy-query'));
      expect(body, contains('time-range'));
      expect(body, contains('20260801T000000Z'));
      expect(body, contains('20260808T000000Z'));
    });

    test('query parses text/calendar response', () async {
      final fake = _FakeFbWebDav();
      fake.reportResponse = Response(
        requestOptions: RequestOptions(path: '/cal/'),
        statusCode: 200,
        data: '''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VFREEBUSY
UID:r1
DTSTART:20260801T000000Z
DTEND:20260808T000000Z
FREEBUSY:20260802T130000Z/20260802T140000Z
END:VFREEBUSY
END:VCALENDAR''',
      );

      final service = FreeBusyService(fake);
      final fb = await service.query(
        Uri.parse('https://dav.example.com/cal/'),
        start: DateTime.utc(2026, 8, 1),
        end: DateTime.utc(2026, 8, 8),
      );

      expect(fake.lastReportBody, contains('free-busy-query'));
      expect(fb.periods, hasLength(1));
      expect(fb.sourceUrl!.path, '/cal/');
    });

    test('query falls back to multistatus calendar-data', () async {
      final fake = _FakeFbWebDav();
      fake.reportResponse = Response(
        requestOptions: RequestOptions(path: '/cal/'),
        statusCode: 207,
        data: '''<?xml version="1.0"?>
<D:multistatus xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
  <D:response>
    <D:href>/cal/</D:href>
    <D:propstat>
      <D:prop>
        <C:calendar-data>BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VFREEBUSY
UID:m1
FREEBUSY;FBTYPE=BUSY-TENTATIVE:20260805T100000Z/20260805T110000Z
END:VFREEBUSY
END:VCALENDAR</C:calendar-data>
      </D:prop>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>
</D:multistatus>''',
      );

      final fb = await FreeBusyService(fake).query(
        Uri.parse('https://dav.example.com/cal/'),
        start: DateTime.utc(2026, 8, 1),
        end: DateTime.utc(2026, 8, 8),
      );
      expect(fb.periods.single.type, FreeBusyType.busyTentative);
    });

    test('query rejects inverted range', () async {
      final service = FreeBusyService(_FakeFbWebDav());
      expect(
        () => service.query(
          Uri.parse('https://x/cal/'),
          start: DateTime.utc(2026, 8, 8),
          end: DateTime.utc(2026, 8, 1),
        ),
        throwsA(isA<CalDavException>()),
      );
    });

    test('requestScheduleFreeBusy posts to outbox', () async {
      final fake = _FakeFbWebDav();
      fake.postResponse = Response(
        requestOptions: RequestOptions(path: '/outbox/'),
        statusCode: 200,
        data: '''BEGIN:VCALENDAR
VERSION:2.0
METHOD:REPLY
BEGIN:VFREEBUSY
UID:reply-1
ATTENDEE:mailto:colleague@example.com
FREEBUSY:20260802T150000Z/20260802T160000Z
END:VFREEBUSY
END:VCALENDAR''',
      );

      final replies = await FreeBusyService(fake).requestScheduleFreeBusy(
        outboxUrl: Uri.parse('https://dav.example.com/outbox/'),
        start: DateTime.utc(2026, 8, 1),
        end: DateTime.utc(2026, 8, 8),
        attendees: ['colleague@example.com'],
        organizer: 'me@example.com',
      );

      expect(fake.lastPostBody, contains('METHOD:REQUEST'));
      expect(fake.lastPostContentType, contains('text/calendar'));
      expect(replies, hasLength(1));
      expect(replies.single.periods, hasLength(1));
    });
  });

  group('FreeBusy helpers', () {
    test('busyInRange filters periods', () {
      final fb = FreeBusy(
        periods: [
          FreeBusyPeriod(
            start: DateTime.utc(2026, 8, 2, 10),
            end: DateTime.utc(2026, 8, 2, 12),
          ),
          FreeBusyPeriod(
            start: DateTime.utc(2026, 8, 5, 10),
            end: DateTime.utc(2026, 8, 5, 12),
          ),
        ],
      );
      final inRange = fb.busyInRange(
        DateTime.utc(2026, 8, 2),
        DateTime.utc(2026, 8, 3),
      );
      expect(inRange, hasLength(1));
      expect(inRange.single.start.day, 2);
    });
  });
}

class _FakeFbWebDav implements WebDavClient {
  Response<String>? reportResponse;
  Response<String>? postResponse;
  String? lastReportBody;
  String? lastPostBody;
  String? lastPostContentType;

  @override
  Future<Response<String>> report(
    String path, {
    required String body,
    DavDepth depth = DavDepth.one,
  }) async {
    lastReportBody = body;
    return reportResponse!;
  }

  @override
  Future<Response<String>> post(
    String path, {
    required String body,
    String contentType = 'application/xml; charset=utf-8',
  }) async {
    lastPostBody = body;
    lastPostContentType = contentType;
    return postResponse!;
  }

  @override
  Future<Response<String>> propfind(
    String path, {
    required String body,
    DavDepth depth = DavDepth.zero,
  }) =>
      throw UnimplementedError();

  @override
  Future<Response<String>> proppatch(String path, {required String body}) =>
      throw UnimplementedError();

  @override
  Future<Response<String>> mkcol(String path, {String? body}) =>
      throw UnimplementedError();

  @override
  Future<Response<String>> mkcalendar(String path, {String? body}) =>
      throw UnimplementedError();

  @override
  Future<Response<String>> put(
    String path, {
    required String body,
    String contentType = 'application/octet-stream',
    String? ifMatch,
    String? ifNoneMatch,
    String? lockToken,
  }) =>
      throw UnimplementedError();

  @override
  Future<Response<String>> delete(
    String path, {
    String? ifMatch,
    String? lockToken,
    DavDepth? depth,
  }) =>
      throw UnimplementedError();

  @override
  Future<Response<String>> get(String path) => throw UnimplementedError();

  @override
  Future<Response<String>> head(String path) => throw UnimplementedError();

  @override
  Future<Response<String>> copy(
    String path, {
    required String destination,
    bool overwrite = true,
    DavDepth depth = DavDepth.infinity,
    String? ifMatch,
    String? lockToken,
  }) =>
      throw UnimplementedError();

  @override
  Future<Response<String>> move(
    String path, {
    required String destination,
    bool overwrite = true,
    DavDepth depth = DavDepth.infinity,
    String? ifMatch,
    String? lockToken,
  }) =>
      throw UnimplementedError();

  @override
  Future<Response<String>> options(String path) => throw UnimplementedError();
}
