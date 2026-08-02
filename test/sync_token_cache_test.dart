import 'package:caldav/caldav.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  group('SyncTokenKeys', () {
    test('normalizes collection hrefs with trailing slash', () {
      expect(
        SyncTokenKeys.forHref(Uri.parse('https://x/cal')),
        'https://x/cal/',
      );
      expect(
        SyncTokenKeys.forHref(Uri.parse('https://x/cal/')),
        'https://x/cal/',
      );
    });
  });

  group('MemorySyncTokenStore', () {
    test('get/set/remove/clear', () async {
      final store = MemorySyncTokenStore();
      expect(await store.getToken('a'), isNull);

      await store.setToken('a', 'tok-1');
      expect(await store.getToken('a'), 'tok-1');
      expect(await store.keys(), ['a']);

      await store.removeToken('a');
      expect(await store.getToken('a'), isNull);

      await store.setToken('b', 't');
      await store.clear();
      expect(await store.keys(), isEmpty);
    });
  });

  group('JsonSyncTokenStore', () {
    test('round-trips JSON and notifies onChange', () async {
      String? lastJson;
      final store = JsonSyncTokenStore(
        onChange: (json) => lastJson = json,
      );

      await store.setToken('https://x/cal/', 'tok-a');
      expect(lastJson, isNotNull);
      expect(lastJson, contains('tok-a'));

      final restored = JsonSyncTokenStore.fromJson(store.toJson());
      expect(await restored.getToken('https://x/cal/'), 'tok-a');

      await store.removeToken('https://x/cal/');
      expect(store.toJson(), '{}');
    });

    test('fromJson ignores non-string values', () {
      final store = JsonSyncTokenStore.fromJson('{"a":"1","b":2}');
      expect(store.snapshot, {'a': '1'});
    });
  });

  group('SyncTokenCache', () {
    late _FakeDav fake;
    late MemorySyncTokenStore store;
    late SyncTokenCache cache;
    late CalDavClient calClient;
    late CardDavClient cardClient;
    late Calendar calendar;
    late AddressBook book;

    setUp(() {
      fake = _FakeDav();
      store = MemorySyncTokenStore();
      cache = SyncTokenCache(store);

      calendar = Calendar(
        uid: 'c1',
        href: Uri.parse('https://dav.example.com/cal/'),
        displayName: 'Cal',
      );
      book = AddressBook(
        uid: 'ab1',
        href: Uri.parse('https://dav.example.com/ab/'),
        displayName: 'AB',
      );

      final dio = Dio(BaseOptions(
        baseUrl: 'https://dav.example.com',
        validateStatus: (s) => s != null && s < 500,
      ));
      dio.httpClientAdapter = fake;

      calClient = CalDavClient.withDio(
        baseUrl: 'https://dav.example.com',
        dio: dio,
        allowInsecure: false,
      );
      calClient.seedDiscovery(DiscoveryResult(
        caldavEndpoint: Uri.parse('https://dav.example.com/'),
        principalUrl: Uri.parse('https://dav.example.com/p/'),
        calendarHomeSet: Uri.parse('https://dav.example.com/cals/'),
      ));

      cardClient = CardDavClient.withDio(
        baseUrl: 'https://dav.example.com',
        dio: dio,
        allowInsecure: false,
      );
      cardClient.seedDiscovery(CardDavDiscoveryResult(
        carddavEndpoint: Uri.parse('https://dav.example.com/'),
        principalUrl: Uri.parse('https://dav.example.com/p/'),
        addressbookHomeSet: Uri.parse('https://dav.example.com/abs/'),
      ));
    });

    tearDown(() {
      calClient.close();
      cardClient.close();
    });

    test('syncCalendar stores token after success', () async {
      fake.syncBodies
        ..clear()
        ..add(_calendarSyncXml(token: 'tok-1', summary: 'Meet'));

      final result = await cache.syncCalendar(calClient, calendar);
      expect(result.syncToken, 'tok-1');
      expect(result.events, hasLength(1));
      expect(
        await store.getToken(SyncTokenKeys.forHref(calendar.href)),
        'tok-1',
      );
    });

    test('syncCalendar sends stored token on next call', () async {
      await store.setToken(SyncTokenKeys.forHref(calendar.href), 'prev');
      fake.syncBodies
        ..clear()
        ..add(_calendarSyncXml(token: 'tok-2', summary: 'Next'));

      await cache.syncCalendar(calClient, calendar);
      expect(fake.lastRequestBodies.last, contains('prev'));
      expect(
        await store.getToken(SyncTokenKeys.forHref(calendar.href)),
        'tok-2',
      );
    });

    test('syncCalendar recovers from InvalidSyncTokenException', () async {
      await store.setToken(SyncTokenKeys.forHref(calendar.href), 'stale');
      fake.failOnceWithValidSyncToken = true;
      fake.syncBodies
        ..clear()
        ..add(_calendarSyncXml(token: 'fresh', summary: 'Resync'));

      final result = await cache.syncCalendar(calClient, calendar);
      expect(result.syncToken, 'fresh');
      expect(result.events.single.summary, 'Resync');
      expect(
        await store.getToken(SyncTokenKeys.forHref(calendar.href)),
        'fresh',
      );
      // First attempt with stale, second full sync
      expect(fake.requestCount, 2);
    });

    test('syncAddressBook stores and reuses token', () async {
      fake.syncBodies
        ..clear()
        ..addAll([
          _contactSyncXml(token: 'ab-1', fn: 'Ada'),
          _contactSyncXml(token: 'ab-2', fn: 'Bob'),
        ]);

      final first = await cache.syncAddressBook(cardClient, book);
      expect(first.contacts.single.formattedName, 'Ada');
      expect(await store.getToken(SyncTokenKeys.forHref(book.href)), 'ab-1');

      final second = await cache.syncAddressBook(cardClient, book);
      expect(second.syncToken, 'ab-2');
      expect(fake.lastRequestBodies.last, contains('ab-1'));
    });
  });
}

String _calendarSyncXml({required String token, required String summary}) {
  return '''<?xml version="1.0"?>
<D:multistatus xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
  <D:response>
    <D:href>/cal/e.ics</D:href>
    <D:propstat>
      <D:prop>
        <D:getetag>"e"</D:getetag>
        <C:calendar-data>BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:e-1
DTSTART:20240115T100000Z
DTEND:20240115T110000Z
SUMMARY:$summary
END:VEVENT
END:VCALENDAR</C:calendar-data>
      </D:prop>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>
  <D:sync-token>$token</D:sync-token>
</D:multistatus>''';
}

String _contactSyncXml({required String token, required String fn}) {
  return '''<?xml version="1.0"?>
<D:multistatus xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:carddav">
  <D:response>
    <D:href>/ab/c.vcf</D:href>
    <D:propstat>
      <D:prop>
        <D:getetag>"c"</D:getetag>
        <C:address-data>BEGIN:VCARD
VERSION:3.0
UID:c-1
FN:$fn
END:VCARD</C:address-data>
      </D:prop>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>
  <D:sync-token>$token</D:sync-token>
</D:multistatus>''';
}

/// Dio adapter that serves canned sync-collection REPORT responses.
class _FakeDav implements HttpClientAdapter {
  final List<String> syncBodies = [];
  final List<String> lastRequestBodies = [];
  int requestCount = 0;
  bool failOnceWithValidSyncToken = false;
  bool _failedOnce = false;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestCount++;
    final body = await _readBody(requestStream);
    lastRequestBodies.add(body);

    if (failOnceWithValidSyncToken && !_failedOnce) {
      _failedOnce = true;
      return ResponseBody.fromString(
        '<?xml version="1.0"?><D:error xmlns:D="DAV:"><D:valid-sync-token/></D:error>',
        403,
        headers: {
          Headers.contentTypeHeader: ['application/xml'],
        },
      );
    }

    if (syncBodies.isEmpty) {
      return ResponseBody.fromString('no more fixtures', 500);
    }
    final xml = syncBodies.removeAt(0);
    return ResponseBody.fromString(
      xml,
      207,
      headers: {
        Headers.contentTypeHeader: ['application/xml'],
      },
    );
  }

  Future<String> _readBody(Stream<List<int>>? stream) async {
    if (stream == null) return '';
    final chunks = await stream.toList();
    final bytes = chunks.expand((c) => c).toList();
    return String.fromCharCodes(bytes);
  }
}
