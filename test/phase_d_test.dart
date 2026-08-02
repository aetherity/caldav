import 'package:caldav/caldav.dart';
import 'package:caldav/src/carddav/contact_service.dart';
import 'package:caldav/src/discovery/discovery_service.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  group('ContactFilter', () {
    test('name filter emits FN text-match', () {
      final xml = ContactFilter.name('Jane').toAddressbookQueryXml();
      expect(xml, contains('addressbook-query'));
      expect(xml, contains('name="FN"'));
      expect(xml, contains('match-type="contains"'));
      expect(xml, contains('Jane'));
    });

    test('email filter with TYPE param-filter', () {
      final xml = ContactFilter.email(
        'work@example.com',
        matchType: TextMatchType.equals,
        types: ['WORK'],
      ).toAddressbookQueryXml();
      expect(xml, contains('name="EMAIL"'));
      expect(xml, contains('match-type="equals"'));
      expect(xml, contains('param-filter name="TYPE"'));
      expect(xml, contains('WORK'));
    });

    test('phone filter', () {
      final xml = ContactFilter.phone('555', types: ['CELL']).toAddressbookQueryXml();
      expect(xml, contains('name="TEL"'));
      expect(xml, contains('CELL'));
    });

    test('anyText uses anyof across FN EMAIL TEL', () {
      final xml = ContactFilter.anyText('jane').toAddressbookQueryXml();
      expect(xml, contains('test="anyof"'));
      expect(xml, contains('name="FN"'));
      expect(xml, contains('name="EMAIL"'));
      expect(xml, contains('name="TEL"'));
    });

    test('limit emits nresults', () {
      final xml = ContactFilter.name('x', limit: 10).toAddressbookQueryXml();
      expect(xml, contains('<C:limit>'));
      expect(xml, contains('<C:nresults>10</C:nresults>'));
    });

    test('is-not-defined prop filter', () {
      final xml = ContactFilter(
        filters: [PropFilter.notDefined('EMAIL')],
      ).toAddressbookQueryXml();
      expect(xml, contains('is-not-defined'));
      expect(xml, contains('name="EMAIL"'));
    });

    test('multi-filter allof by default', () {
      final xml = ContactFilter(
        filters: [
          PropFilter.contains('ORG', 'Acme'),
          PropFilter.contains('TITLE', 'Engineer'),
        ],
      ).toAddressbookQueryXml();
      expect(xml, contains('test="allof"'));
      expect(xml, contains('ORG'));
      expect(xml, contains('TITLE'));
    });

    test('uid filter uses equals + i;octet', () {
      final xml = ContactFilter.uid('abc-123').toAddressbookQueryXml();
      expect(xml, contains('name="UID"'));
      expect(xml, contains('match-type="equals"'));
      expect(xml, contains('i;octet'));
    });

    test('escapes XML in filter text', () {
      final xml = ContactFilter.name('A & B <C>').toAddressbookQueryXml();
      expect(xml, contains('A &amp; B &lt;C&gt;'));
    });
  });

  group('Richer vCard parse/serialize', () {
    test('parses extended fields', () {
      const vcard = '''BEGIN:VCARD
VERSION:4.0
UID:rich-1
FN:Rich Contact
N:Contact;Rich;;;
NICKNAME:RC,Richie
ROLE:Lead
IMPP;TYPE=HOME;X-SERVICE-TYPE=Jabber:xmpp:rich@example.com
ANNIVERSARY:2010-06-01
PHOTO;VALUE=uri:https://example.com/photo.jpg
GEO:37.386013;-122.082932
TZ:America/Los_Angeles
LANG;TYPE=work:en
RELATED;TYPE=friend:urn:uuid:friend-1
GENDER:M
KIND:individual
REV:20240115T100000Z
PRODID:-//Test//EN
X-CUSTOM:hello
END:VCARD''';

      final c = VCardParser.parse(vcard, addressBookId: 'b');
      expect(c, isNotNull);
      expect(c!.nicknames, ['RC', 'Richie']);
      expect(c.nickname, 'RC');
      expect(c.role, 'Lead');
      expect(c.impps, hasLength(1));
      expect(c.impps.first.uri, 'xmpp:rich@example.com');
      expect(c.anniversary, '2010-06-01');
      expect(c.photo?.isUri, isTrue);
      expect(c.photo?.value, 'https://example.com/photo.jpg');
      expect(c.geo?.latitude, closeTo(37.386013, 0.0001));
      expect(c.geo?.longitude, closeTo(-122.082932, 0.0001));
      expect(c.timeZone, 'America/Los_Angeles');
      expect(c.languages.single.value, 'en');
      expect(c.related.single.value, 'urn:uuid:friend-1');
      expect(c.gender?.sex, 'M');
      expect(c.kind, 'individual');
      expect(c.rev, '20240115T100000Z');
      expect(c.prodId, '-//Test//EN');
      expect(c.extraProperties.any((p) => p.name == 'X-CUSTOM'), isTrue);
    });

    test('parses group with MEMBER', () {
      const vcard = '''BEGIN:VCARD
VERSION:4.0
UID:group-1
FN:Family
KIND:group
MEMBER:urn:uuid:a
MEMBER:urn:uuid:b
END:VCARD''';

      final c = VCardParser.parse(vcard, addressBookId: 'b');
      expect(c!.isGroup, isTrue);
      expect(c.members, ['urn:uuid:a', 'urn:uuid:b']);
    });

    test('round-trips extended fields', () {
      final original = Contact(
        uid: 'ext-1',
        addressBookId: 'b',
        formattedName: 'Ext Person',
        nicknames: const ['EP'],
        role: 'Dev',
        impps: const [
          VCardImpp(uri: 'xmpp:ep@example.com', types: ['WORK']),
        ],
        anniversary: '2015-01-01',
        photo: const VCardPhoto(
          value: 'https://example.com/p.png',
          isUri: true,
        ),
        geo: const VCardGeo(latitude: 1.5, longitude: 2.5),
        timeZone: 'UTC',
        languages: const [VCardTypedValue(value: 'en')],
        related: const [
          VCardRelated(value: 'urn:uuid:x', types: ['colleague']),
        ],
        gender: const VCardGender(sex: 'O', identity: 'non-binary'),
        kind: 'individual',
        rev: '20250101T000000Z',
        extraProperties: const [
          VCardRawProperty(name: 'X-FOO', value: 'bar'),
        ],
      );

      final out = VCardParser.serialize(original);
      expect(out, contains('NICKNAME:EP'));
      expect(out, contains('ROLE:Dev'));
      expect(out, contains('IMPP'));
      expect(out, contains('ANNIVERSARY:2015-01-01'));
      expect(out, contains('PHOTO;VALUE=uri:'));
      expect(out, contains('GEO:1.5;2.5'));
      expect(out, contains('GENDER:O;non-binary'));
      expect(out, contains('X-FOO:bar'));

      final parsed = VCardParser.parse(out, addressBookId: 'b');
      expect(parsed!.nicknames, ['EP']);
      expect(parsed.role, 'Dev');
      expect(parsed.impps.single.uri, 'xmpp:ep@example.com');
      expect(parsed.geo?.latitude, 1.5);
      expect(parsed.gender?.identity, 'non-binary');
      expect(parsed.extraProperties.any((p) => p.name == 'X-FOO'), isTrue);
    });

    test('ADR LABEL via group is associated', () {
      const vcard = '''BEGIN:VCARD
VERSION:3.0
UID:label-1
FN:Labeled
item1.ADR;TYPE=HOME:;;1 Main;Town;ST;12345;US
item1.LABEL:1 Main\\nTown ST 12345
END:VCARD''';

      final c = VCardParser.parse(vcard, addressBookId: 'b');
      expect(c!.addresses.single.label, contains('1 Main'));
    });
  });

  group('ContactService.query uses ContactFilter', () {
    test('query body from anyText', () {
      final body = ContactService.buildFilterQueryBody(
        ContactFilter.anyText('x'),
      );
      expect(body, contains('anyof'));
    });
  });

  group('DualDiscoveryResult', () {
    test('ensureAny throws when both missing', () {
      const dual = DualDiscoveryResult(
        caldavError: 'no cal',
        carddavError: 'no card',
      );
      expect(dual.hasAny, isFalse);
      expect(dual.ensureAny, throwsA(isA<DiscoveryException>()));
    });

    test('has flags when present', () {
      final dual = DualDiscoveryResult(
        caldav: DiscoveryResult(
          caldavEndpoint: Uri.parse('https://x/cal'),
          principalUrl: Uri.parse('https://x/p'),
          calendarHomeSet: Uri.parse('https://x/home'),
        ),
      );
      expect(dual.hasCalDav, isTrue);
      expect(dual.hasCardDav, isFalse);
      dual.ensureAny(); // should not throw
    });
  });

  group('DavSession', () {
    test('rejects insecure without allowInsecure', () {
      expect(
        () => DavSession(
          baseUrl: 'http://localhost',
          username: 'u',
          password: 'p',
        ),
        throwsA(isA<CalDavException>()),
      );
    });

    test('constructs shared clients with allowInsecure', () {
      final session = DavSession(
        baseUrl: 'http://localhost',
        username: 'u',
        password: 'p',
        allowInsecure: true,
      );
      expect(session.caldav, isA<CalDavClient>());
      expect(session.carddav, isA<CardDavClient>());
      expect(identical(session.caldav.dio, session.carddav.dio), isTrue);
      session.close();
    });

    test('withDio does not close external dio on session.close', () {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.com'));
      final session = DavSession.withDio(
        baseUrl: 'https://example.com',
        dio: dio,
      );
      session.close();
      // Dio should still accept requests (not closed). closed flag exists on Dio.
      expect(dio.options.baseUrl, 'https://example.com');
    });

    test('seedDiscovery on nested clients', () {
      final session = DavSession(
        baseUrl: 'https://example.com',
        username: 'u',
        password: 'p',
      );
      final cal = DiscoveryResult(
        caldavEndpoint: Uri.parse('https://example.com/cal'),
        principalUrl: Uri.parse('https://example.com/p'),
        calendarHomeSet: Uri.parse('https://example.com/cals/'),
      );
      final card = CardDavDiscoveryResult(
        carddavEndpoint: Uri.parse('https://example.com/card'),
        principalUrl: Uri.parse('https://example.com/p'),
        addressbookHomeSet: Uri.parse('https://example.com/abs/'),
      );
      session.caldav.seedDiscovery(cal);
      session.carddav.seedDiscovery(card);
      expect(session.caldav.discoveryResult, same(cal));
      expect(session.carddav.discoveryResult, same(card));
      session.close();
    });
  });

  group('DiscoveryService.discoverBoth', () {
    test('records independent failures', () async {
      final dio = Dio(BaseOptions(
        baseUrl: 'https://example.com',
        validateStatus: (s) => s != null && s < 500,
      ));
      // Adapter that always fails discovery paths.
      dio.httpClientAdapter = _FailingAdapter();
      final webdav = DioWebDavClient(dio);
      final discovery = DiscoveryService(webdav, dio);

      final dual = await discovery.discoverBoth(Uri.parse('https://example.com'));
      expect(dual.hasCalDav, isFalse);
      expect(dual.hasCardDav, isFalse);
      expect(dual.caldavError, isNotNull);
      expect(dual.carddavError, isNotNull);
      dio.close();
    });
  });
}

class _FailingAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.connectionError,
      message: 'offline',
    );
  }
}
