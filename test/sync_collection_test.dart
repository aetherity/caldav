import 'package:caldav/caldav.dart';
import 'package:caldav/src/carddav/contact_service.dart';
import 'package:caldav/src/event/event_service.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  group('SyncCollectionBuilder', () {
    test('initial sync emits empty sync-token element', () {
      final xml = SyncCollectionBuilder.calendar().build();
      expect(xml, contains('sync-collection'));
      expect(xml, contains('<D:sync-token/>'));
      expect(xml, contains('<D:sync-level>1</D:sync-level>'));
      expect(xml, contains('getetag'));
      expect(xml, contains('calendar-data'));
      expect(xml, contains(XmlNamespaces.caldav));
    });

    test('incremental sync escapes token', () {
      final xml = SyncCollectionBuilder.calendar(
        syncToken: 'http://x/sync/1&2',
      ).build();
      expect(xml, contains('http://x/sync/1&amp;2'));
      expect(xml, isNot(contains('<D:sync-token/>')));
    });

    test('addressbook builder uses address-data', () {
      final xml = SyncCollectionBuilder.addressbook(
        syncToken: 't1',
        limit: 25,
      ).build();
      expect(xml, contains('address-data'));
      expect(xml, contains(XmlNamespaces.carddav));
      expect(xml, contains('<D:nresults>25</D:nresults>'));
    });

    test('metadata builder omits payload props', () {
      final xml = SyncCollectionBuilder.metadata().build();
      expect(xml, contains('getcontenttype'));
      expect(xml, isNot(contains('calendar-data')));
      expect(xml, isNot(contains('address-data')));
    });

    test('infinite sync-level', () {
      final xml = SyncCollectionBuilder(
        level: SyncLevel.infinite,
        propElements: const ['<D:getetag/>'],
      ).build();
      expect(xml, contains('<D:sync-level>infinite</D:sync-level>'));
    });
  });

  group('MultiStatus sync fields', () {
    test('parses top-level sync-token and deleted members', () {
      const xml = '''<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
  <D:response>
    <D:href>/calendars/user/default/</D:href>
    <D:propstat>
      <D:prop><D:getetag>"ignored"</D:getetag></D:prop>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/calendars/user/default/a.ics</D:href>
    <D:propstat>
      <D:prop>
        <D:getetag>"e1"</D:getetag>
        <C:calendar-data>BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:a
DTSTART:20240115T100000Z
DTEND:20240115T110000Z
SUMMARY:Alpha
END:VEVENT
END:VCALENDAR</C:calendar-data>
      </D:prop>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/calendars/user/default/gone.ics</D:href>
    <D:status>HTTP/1.1 404 Not Found</D:status>
  </D:response>
  <D:response>
    <D:status>HTTP/1.1 507 Insufficient Storage</D:status>
    <D:error><D:number-of-matches-within-limits/></D:error>
  </D:response>
  <D:sync-token>http://example.com/ns/sync/1235</D:sync-token>
</D:multistatus>''';

      final multi = MultiStatus.fromXml(xml);
      expect(multi.syncToken, 'http://example.com/ns/sync/1235');
      expect(multi.isTruncated, isTrue);

      final deleted = multi.responses.where((r) => r.isDeleted).toList();
      expect(deleted, hasLength(1));
      expect(deleted.first.href, '/calendars/user/default/gone.ics');

      final truncation =
          multi.responses.where((r) => r.isTruncationMarker).toList();
      expect(truncation, hasLength(1));
    });
  });

  group('SyncService.parseSyncResponse', () {
    test('maps changes and skips collection href', () {
      const xml = '''<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
  <D:response>
    <D:href>/cal/</D:href>
    <D:propstat>
      <D:prop><D:getetag>"col"</D:getetag></D:prop>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/cal/a.ics</D:href>
    <D:propstat>
      <D:prop>
        <D:getetag>"e1"</D:getetag>
        <C:calendar-data>BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:a
DTSTART:20240115T100000Z
SUMMARY:A
END:VEVENT
END:VCALENDAR</C:calendar-data>
      </D:prop>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/cal/b.ics</D:href>
    <D:status>HTTP/1.1 404 Not Found</D:status>
  </D:response>
  <D:sync-token>tok-2</D:sync-token>
</D:multistatus>''';

      final result = SyncService.parseSyncResponse(
        xml,
        Uri.parse('https://dav.example.com/cal/'),
      );

      expect(result.syncToken, 'tok-2');
      expect(result.truncated, isFalse);
      expect(result.changes, hasLength(2));
      expect(result.changed.single.href, '/cal/a.ics');
      expect(result.changed.single.etag, '"e1"');
      expect(result.changed.single.data, contains('UID:a'));
      expect(result.deleted.single.resolvedHref.path, '/cal/b.ics');
    });

    test('throws when sync-token missing', () {
      const xml = '''<?xml version="1.0"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/x</D:href>
    <D:status>HTTP/1.1 200 OK</D:status>
  </D:response>
</D:multistatus>''';

      expect(
        () => SyncService.parseSyncResponse(
          xml,
          Uri.parse('https://example.com/'),
        ),
        throwsA(isA<ParseException>()),
      );
    });

    test('detects truncation marker', () {
      const xml = '''<?xml version="1.0"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/cal/a.ics</D:href>
    <D:propstat>
      <D:prop><D:getetag>"1"</D:getetag></D:prop>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>
  <D:response>
    <D:status>HTTP/1.1 507 Insufficient Storage</D:status>
    <D:error><D:number-of-matches-within-limits/></D:error>
  </D:response>
  <D:sync-token>page-1</D:sync-token>
</D:multistatus>''';

      final result = SyncService.parseSyncResponse(
        xml,
        Uri.parse('https://dav.example.com/cal/'),
      );
      expect(result.truncated, isTrue);
      expect(result.syncToken, 'page-1');
      expect(result.changes, hasLength(1));
    });
  });

  group('SyncService with fake client', () {
    late _FakeSyncWebDav fake;
    late SyncService service;

    setUp(() {
      fake = _FakeSyncWebDav();
      service = SyncService(fake);
    });

    test('syncCollection sends report body', () async {
      fake.reportResponse = Response(
        requestOptions: RequestOptions(path: '/cal/'),
        statusCode: 207,
        data: '''<?xml version="1.0"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/cal/x.ics</D:href>
    <D:propstat>
      <D:prop><D:getetag>"x"</D:getetag></D:prop>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>
  <D:sync-token>t1</D:sync-token>
</D:multistatus>''',
      );

      final result = await service.syncCollection(
        Uri.parse('https://dav.example.com/cal/'),
        SyncCollectionBuilder.calendar(syncToken: 'old'),
      );

      expect(result.syncToken, 't1');
      expect(fake.lastReportBody, contains('sync-collection'));
      expect(fake.lastReportBody, contains('old'));
      expect(fake.lastReportDepth, DavDepth.zero);
    });

    test('syncCollectionFully follows truncated pages', () async {
      var page = 0;
      fake.reportHandler = (path, body, depth) {
        page++;
        if (page == 1) {
          return Response(
            requestOptions: RequestOptions(path: path),
            statusCode: 207,
            data: '''<?xml version="1.0"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/cal/a.ics</D:href>
    <D:propstat>
      <D:prop><D:getetag>"a"</D:getetag></D:prop>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>
  <D:response>
    <D:status>HTTP/1.1 507 Insufficient Storage</D:status>
    <D:error><D:number-of-matches-within-limits/></D:error>
  </D:response>
  <D:sync-token>page1</D:sync-token>
</D:multistatus>''',
          );
        }
        return Response(
          requestOptions: RequestOptions(path: path),
          statusCode: 207,
          data: '''<?xml version="1.0"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/cal/b.ics</D:href>
    <D:propstat>
      <D:prop><D:getetag>"b"</D:getetag></D:prop>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>
  <D:sync-token>page2</D:sync-token>
</D:multistatus>''',
        );
      };

      final result = await service.syncCollectionFully(
        Uri.parse('https://dav.example.com/cal/'),
        rebuild: (token) => SyncCollectionBuilder.calendar(
          syncToken: token,
          limit: 1,
        ),
      );

      expect(page, 2);
      expect(result.syncToken, 'page2');
      expect(result.truncated, isFalse);
      expect(result.changes, hasLength(2));
      expect(fake.lastReportBody, contains('page1'));
    });

    test('maps valid-sync-token 403 to InvalidSyncTokenException', () async {
      fake.reportError = DioException(
        requestOptions: RequestOptions(path: '/cal/'),
        response: Response(
          requestOptions: RequestOptions(path: '/cal/'),
          statusCode: 403,
          data: '''<?xml version="1.0"?>
<D:error xmlns:D="DAV:">
  <D:valid-sync-token/>
</D:error>''',
        ),
        type: DioExceptionType.badResponse,
      );

      expect(
        () => service.syncCollection(
          Uri.parse('https://dav.example.com/cal/'),
          SyncCollectionBuilder.calendar(syncToken: 'stale'),
        ),
        throwsA(isA<InvalidSyncTokenException>()),
      );
    });
  });

  group('EventService.sync / ContactService.sync', () {
    test('parses calendar events and todos from sync payload', () async {
      final fake = _FakeSyncWebDav();
      fake.reportResponse = Response(
        requestOptions: RequestOptions(path: '/cal/'),
        statusCode: 207,
        data: '''<?xml version="1.0"?>
<D:multistatus xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
  <D:response>
    <D:href>/cal/e.ics</D:href>
    <D:propstat>
      <D:prop>
        <D:getetag>"e"</D:getetag>
        <C:calendar-data>BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:ev-1
DTSTART:20240115T100000Z
DTEND:20240115T110000Z
SUMMARY:Meeting
END:VEVENT
END:VCALENDAR</C:calendar-data>
      </D:prop>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/cal/t.ics</D:href>
    <D:propstat>
      <D:prop>
        <D:getetag>"t"</D:getetag>
        <C:calendar-data>BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VTODO
UID:td-1
SUMMARY:Buy milk
STATUS:NEEDS-ACTION
END:VTODO
END:VCALENDAR</C:calendar-data>
      </D:prop>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/cal/j.ics</D:href>
    <D:propstat>
      <D:prop>
        <D:getetag>"j"</D:getetag>
        <C:calendar-data>BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VJOURNAL
UID:jn-1
SUMMARY:Day notes
STATUS:DRAFT
END:VJOURNAL
END:VCALENDAR</C:calendar-data>
      </D:prop>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/cal/old.ics</D:href>
    <D:status>HTTP/1.1 404 Not Found</D:status>
  </D:response>
  <D:sync-token>cal-tok</D:sync-token>
</D:multistatus>''',
      );

      final events = EventService(fake);
      final calendar = Calendar(
        uid: 'cal',
        href: Uri.parse('https://dav.example.com/cal/'),
        displayName: 'Default',
      );

      final result = await events.sync(calendar);
      expect(result.syncToken, 'cal-tok');
      expect(result.events, hasLength(1));
      expect(result.events.single.summary, 'Meeting');
      expect(result.todos, hasLength(1));
      expect(result.todos.single.summary, 'Buy milk');
      expect(result.journals, hasLength(1));
      expect(result.journals.single.summary, 'Day notes');
      expect(result.deletedHrefs.single.path, '/cal/old.ics');
    });

    test('parses contacts from address book sync', () async {
      final fake = _FakeSyncWebDav();
      fake.reportResponse = Response(
        requestOptions: RequestOptions(path: '/ab/'),
        statusCode: 207,
        data: '''<?xml version="1.0"?>
<D:multistatus xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:carddav">
  <D:response>
    <D:href>/ab/c.vcf</D:href>
    <D:propstat>
      <D:prop>
        <D:getetag>"c"</D:getetag>
        <C:address-data>BEGIN:VCARD
VERSION:3.0
UID:c-1
FN:Carol
EMAIL:carol@example.com
END:VCARD</C:address-data>
      </D:prop>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/ab/gone.vcf</D:href>
    <D:status>HTTP/1.1 404 Not Found</D:status>
  </D:response>
  <D:sync-token>ab-tok</D:sync-token>
</D:multistatus>''',
      );

      final contacts = ContactService(fake);
      final book = AddressBook(
        uid: 'ab',
        href: Uri.parse('https://dav.example.com/ab/'),
        displayName: 'Personal',
      );

      final result = await contacts.sync(book);
      expect(result.syncToken, 'ab-tok');
      expect(result.contacts, hasLength(1));
      expect(result.contacts.single.formattedName, 'Carol');
      expect(result.deletedHrefs.single.path, '/ab/gone.vcf');
    });
  });

  group('PropfindBuilder includes sync-token', () {
    test('calendar and addressbook presets', () {
      expect(PropfindBuilder.calendarProperties(), contains('sync-token'));
      expect(PropfindBuilder.addressbookProperties(), contains('sync-token'));
    });
  });
}

class _FakeSyncWebDav implements WebDavClient {
  Response<String>? reportResponse;
  Response<String>? propfindResponse;
  DioException? reportError;

  Response<String> Function(String path, String body, DavDepth depth)?
      reportHandler;

  String? lastReportBody;
  DavDepth? lastReportDepth;

  @override
  Future<Response<String>> report(
    String path, {
    required String body,
    DavDepth depth = DavDepth.one,
  }) async {
    lastReportBody = body;
    lastReportDepth = depth;
    if (reportError != null) throw reportError!;
    if (reportHandler != null) return reportHandler!(path, body, depth);
    return reportResponse!;
  }

  @override
  Future<Response<String>> propfind(
    String path, {
    required String body,
    DavDepth depth = DavDepth.zero,
  }) async =>
      propfindResponse!;

  @override
  Future<Response<String>> proppatch(String path, {required String body}) {
    throw UnimplementedError();
  }

  @override
  Future<Response<String>> mkcol(String path, {String? body}) {
    throw UnimplementedError();
  }

  @override
  Future<Response<String>> mkcalendar(String path, {String? body}) {
    throw UnimplementedError();
  }

  @override
  Future<Response<String>> put(
    String path, {
    required String body,
    String contentType = 'application/octet-stream',
    String? ifMatch,
    String? ifNoneMatch,
    String? lockToken,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Response<String>> delete(
    String path, {
    String? ifMatch,
    String? lockToken,
    DavDepth? depth,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Response<String>> get(String path) {
    throw UnimplementedError();
  }

  @override
  Future<Response<String>> post(
    String path, {
    required String body,
    String contentType = 'application/xml; charset=utf-8',
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Response<String>> head(String path) {
    throw UnimplementedError();
  }

  @override
  Future<Response<String>> copy(
    String path, {
    required String destination,
    bool overwrite = true,
    DavDepth depth = DavDepth.infinity,
    String? ifMatch,
    String? lockToken,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Response<String>> move(
    String path, {
    required String destination,
    bool overwrite = true,
    DavDepth depth = DavDepth.infinity,
    String? ifMatch,
    String? lockToken,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Response<String>> options(String path) {
    throw UnimplementedError();
  }
}
