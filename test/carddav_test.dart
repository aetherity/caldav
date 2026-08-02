import 'package:caldav/caldav.dart';
import 'package:caldav/src/carddav/addressbook_service.dart';
import 'package:caldav/src/carddav/contact_service.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  group('VCardUtils / VCardParser', () {
    test('parses basic vCard 3.0 contact', () {
      const vcard = '''BEGIN:VCARD
VERSION:3.0
UID:contact-1
FN:Jane Doe
N:Doe;Jane;Q.;Dr.;Jr.
EMAIL;TYPE=WORK:jane@example.com
EMAIL;TYPE=HOME;PREF=1:jane.home@example.com
TEL;TYPE=CELL:+1-555-0100
ORG:Acme Inc.
TITLE:Engineer
NOTE:Met at conference
URL:https://example.com
BDAY:1990-05-15
CATEGORIES:Work,Friends
END:VCARD''';

      final contact = VCardParser.parse(
        vcard,
        addressBookId: 'book-1',
        href: Uri.parse('https://dav.example.com/ab/contact-1.vcf'),
        etag: '"e1"',
      );

      expect(contact, isNotNull);
      expect(contact!.uid, 'contact-1');
      expect(contact.formattedName, 'Jane Doe');
      expect(contact.name?.family, 'Doe');
      expect(contact.name?.given, 'Jane');
      expect(contact.name?.additional, 'Q.');
      expect(contact.name?.prefix, 'Dr.');
      expect(contact.name?.suffix, 'Jr.');
      expect(contact.emails, hasLength(2));
      expect(contact.primaryEmail, 'jane.home@example.com'); // PREF=1
      expect(contact.phones.single.value, '+1-555-0100');
      expect(contact.phones.single.types, contains('CELL'));
      expect(contact.organization, 'Acme Inc.');
      expect(contact.title, 'Engineer');
      expect(contact.note, 'Met at conference');
      expect(contact.urls.single.value, 'https://example.com');
      expect(contact.birthday, '1990-05-15');
      expect(contact.categories, ['Work', 'Friends']);
      expect(contact.etag, '"e1"');
      expect(contact.rawVcard, isNotNull);
    });

    test('parses folded lines', () {
      const vcard = 'BEGIN:VCARD\n'
          'VERSION:3.0\n'
          'UID:fold-1\n'
          'FN:Long Name That Continues\n'
          'NOTE:This is a long note that is folded\n'
          '  across multiple lines with a leading space\n'
          'END:VCARD\n';

      final contact = VCardParser.parse(vcard, addressBookId: 'b');
      expect(contact, isNotNull);
      expect(
        contact!.note,
        'This is a long note that is folded across multiple lines with a leading space',
      );
    });

    test('parses ADR components', () {
      const vcard = '''BEGIN:VCARD
VERSION:3.0
UID:adr-1
FN:Postal Person
ADR;TYPE=HOME:;;123 Main St;Springfield;IL;62701;USA
END:VCARD''';

      final contact = VCardParser.parse(vcard, addressBookId: 'b');
      expect(contact!.addresses, hasLength(1));
      final adr = contact.addresses.first;
      expect(adr.street, '123 Main St');
      expect(adr.locality, 'Springfield');
      expect(adr.region, 'IL');
      expect(adr.postalCode, '62701');
      expect(adr.country, 'USA');
      expect(adr.types, contains('HOME'));
    });

    test('round-trip structured fields through serialize → parse', () {
      final original = Contact(
        uid: 'rt-1',
        addressBookId: 'book',
        formattedName: 'Alex Smith',
        name: const StructuredName(family: 'Smith', given: 'Alex'),
        emails: const [
          VCardTypedValue(value: 'alex@example.com', types: ['WORK']),
        ],
        phones: const [
          VCardTypedValue(value: '+1-555-9999', types: ['HOME']),
        ],
        addresses: const [
          PostalAddress(
            street: '1 Infinite Loop',
            locality: 'Cupertino',
            region: 'CA',
            postalCode: '95014',
            country: 'USA',
            types: ['WORK'],
          ),
        ],
        organization: 'Example Corp',
        title: 'CEO',
        note: 'Line1\nLine2',
        categories: const ['VIP'],
      );

      final serialized = VCardParser.serialize(original);
      expect(serialized, contains('BEGIN:VCARD'));
      expect(serialized, contains('VERSION:3.0'));
      expect(serialized, contains('FN:Alex Smith'));
      expect(serialized, contains('NOTE:Line1\\nLine2'));

      final parsed = VCardParser.parse(serialized, addressBookId: 'book');
      expect(parsed, isNotNull);
      expect(parsed!.uid, original.uid);
      expect(parsed.formattedName, original.formattedName);
      expect(parsed.name?.family, 'Smith');
      expect(parsed.name?.given, 'Alex');
      expect(parsed.emails.single.value, 'alex@example.com');
      expect(parsed.phones.single.value, '+1-555-9999');
      expect(parsed.addresses.single.street, '1 Infinite Loop');
      expect(parsed.organization, 'Example Corp');
      expect(parsed.note, 'Line1\nLine2');
      expect(parsed.categories, ['VIP']);
    });

    test('returns null without UID and without href fallback', () {
      const vcard = '''BEGIN:VCARD
VERSION:3.0
FN:No UID
END:VCARD''';
      expect(VCardParser.parse(vcard, addressBookId: 'b'), isNull);
    });

    test('escapes special characters in property values', () {
      final contact = Contact(
        uid: 'esc-1',
        addressBookId: 'b',
        formattedName: 'A;B,C',
      );
      final out = VCardParser.serialize(contact);
      expect(out, contains('FN:A\\;B\\,C'));
    });
  });

  group('Contact model', () {
    test('copyWith and primary helpers', () {
      const c = Contact(
        uid: '1',
        addressBookId: 'ab',
        formattedName: 'Test',
        emails: [
          VCardTypedValue(value: 'a@x.com', types: ['WORK']),
          VCardTypedValue(value: 'b@x.com', types: ['HOME'], pref: 1),
        ],
        phones: [
          VCardTypedValue(value: '111'),
          VCardTypedValue(value: '222', pref: 2),
        ],
      );

      expect(c.primaryEmail, 'b@x.com');
      expect(c.primaryPhone, '222');

      final copy = c.copyWith(formattedName: 'Updated');
      expect(copy.formattedName, 'Updated');
      expect(copy.uid, '1');
    });

    test('StructuredName / PostalAddress equality', () {
      const a = StructuredName(family: 'Doe', given: 'Jane');
      const b = StructuredName(family: 'Doe', given: 'Jane');
      const c = StructuredName(family: 'Doe', given: 'John');
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  group('ContactService query bodies', () {
    test('addressbook-query lists address-data', () {
      final body = ContactService.buildAddressbookQueryBody();
      expect(body, contains('addressbook-query'));
      expect(body, contains('address-data'));
      expect(body, contains('getetag'));
    });

    test('uid query filters on UID', () {
      final body = ContactService.buildUidQueryBody('uid-<>&');
      expect(body, contains('prop-filter name="UID"'));
      expect(body, contains('uid-&lt;&gt;&amp;'));
    });

    test('prop filter query includes match-type', () {
      final body = ContactService.buildPropFilterQueryBody(
        propertyName: 'email',
        text: 'jane',
      );
      expect(body, contains('name="EMAIL"'));
      expect(body, contains('match-type="contains"'));
      expect(body, contains('jane'));
    });
  });

  group('CardDavClient guards', () {
    test('rejects insecure HTTP without allowInsecure', () {
      expect(
        () => CardDavClient(
          baseUrl: 'http://localhost',
          username: 'u',
          password: 'p',
        ),
        throwsA(isA<CalDavException>()),
      );
    });

    test('allows HTTP with allowInsecure', () {
      final client = CardDavClient(
        baseUrl: 'http://localhost',
        username: 'u',
        password: 'p',
        allowInsecure: true,
      );
      client.close();
    });

    test('updateContact throws ForbiddenException for read-only', () async {
      final client = CardDavClient(
        baseUrl: 'https://example.com',
        username: 'u',
        password: 'p',
      );
      final contact = Contact(
        uid: '1',
        addressBookId: 'ab',
        formattedName: 'X',
        href: Uri.parse('https://example.com/1.vcf'),
        isReadOnly: true,
      );
      expect(
        () => client.updateContact(contact),
        throwsA(isA<ForbiddenException>()),
      );
      client.close();
    });

    test('deleteContact throws ForbiddenException for read-only', () async {
      final client = CardDavClient(
        baseUrl: 'https://example.com',
        username: 'u',
        password: 'p',
      );
      final contact = Contact(
        uid: '1',
        addressBookId: 'ab',
        formattedName: 'X',
        href: Uri.parse('https://example.com/1.vcf'),
        isReadOnly: true,
      );
      expect(
        () => client.deleteContact(contact),
        throwsA(isA<ForbiddenException>()),
      );
      client.close();
    });
  });

  group('ContactService with fake client', () {
    late _FakeCardDavWebDav fake;
    late ContactService service;
    late AddressBook book;

    setUp(() {
      fake = _FakeCardDavWebDav();
      service = ContactService(fake);
      book = AddressBook(
        uid: 'ab-1',
        href: Uri.parse('https://dav.example.com/ab/default/'),
        displayName: 'Default',
      );
    });

    test('list parses address-data from report', () async {
      fake.reportResponse = Response(
        requestOptions: RequestOptions(path: book.href.path),
        statusCode: 207,
        data: '''<?xml version="1.0"?>
<D:multistatus xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:carddav">
  <D:response>
    <D:href>/ab/default/c1.vcf</D:href>
    <D:propstat>
      <D:prop>
        <D:getetag>"t1"</D:getetag>
        <C:address-data>BEGIN:VCARD
VERSION:3.0
UID:c1
FN:Alice
EMAIL:alice@example.com
END:VCARD</C:address-data>
      </D:prop>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>
</D:multistatus>''',
      );

      final contacts = await service.list(book);
      expect(contacts, hasLength(1));
      expect(contacts.first.uid, 'c1');
      expect(contacts.first.formattedName, 'Alice');
      expect(contacts.first.primaryEmail, 'alice@example.com');
      expect(contacts.first.etag, '"t1"');
      expect(fake.lastReportBody, contains('addressbook-query'));
    });

    test('create PUTs vcard with text/vcard content type', () async {
      fake.putResponse = Response(
        requestOptions: RequestOptions(path: '/ab/default/new.vcf'),
        statusCode: 201,
        data: '',
        headers: Headers.fromMap({
          'etag': ['"new"'],
        }),
      );

      final created = await service.create(
        book,
        const Contact(
          uid: 'new',
          addressBookId: 'ab-1',
          formattedName: 'Bob',
          emails: [VCardTypedValue(value: 'bob@example.com')],
        ),
      );

      expect(created.href!.path, endsWith('new.vcf'));
      expect(created.etag, '"new"');
      expect(fake.lastPutContentType, 'text/vcard; charset=utf-8');
      expect(fake.lastPutBody, contains('FN:Bob'));
      expect(fake.lastPutIfNoneMatch, '*');
    });

    test('findByUid uses UID prop-filter', () async {
      fake.reportResponse = Response(
        requestOptions: RequestOptions(path: book.href.path),
        statusCode: 207,
        data: '''<?xml version="1.0"?>
<D:multistatus xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:carddav">
  <D:response>
    <D:href>/ab/default/find-me.vcf</D:href>
    <D:propstat>
      <D:prop>
        <D:getetag>"x"</D:getetag>
        <C:address-data>BEGIN:VCARD
VERSION:3.0
UID:find-me
FN:Found
END:VCARD</C:address-data>
      </D:prop>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>
</D:multistatus>''',
      );

      final found = await service.findByUid(book, 'find-me');
      expect(found, isNotNull);
      expect(found!.formattedName, 'Found');
      expect(fake.lastReportBody, contains('find-me'));
      expect(fake.lastReportBody, contains('prop-filter name="UID"'));
    });

    test('falls back to multiget when address-data missing', () async {
      var reportCount = 0;
      fake.reportHandler = (path, body, depth) {
        reportCount++;
        if (reportCount == 1) {
          return Response(
            requestOptions: RequestOptions(path: path),
            statusCode: 207,
            data: '''<?xml version="1.0"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/ab/default/only-href.vcf</D:href>
    <D:propstat>
      <D:prop><D:getetag>"z"</D:getetag></D:prop>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>
</D:multistatus>''',
          );
        }
        return Response(
          requestOptions: RequestOptions(path: path),
          statusCode: 207,
          data: '''<?xml version="1.0"?>
<D:multistatus xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:carddav">
  <D:response>
    <D:href>/ab/default/only-href.vcf</D:href>
    <D:propstat>
      <D:prop>
        <D:getetag>"z"</D:getetag>
        <C:address-data>BEGIN:VCARD
VERSION:3.0
UID:only-href
FN:From Multiget
END:VCARD</C:address-data>
      </D:prop>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>
</D:multistatus>''',
        );
      };

      final contacts = await service.list(book);
      expect(contacts, hasLength(1));
      expect(contacts.first.formattedName, 'From Multiget');
      expect(reportCount, 2);
      expect(fake.lastReportBody, contains('addressbook-multiget'));
    });
  });

  group('AddressBookService with fake client', () {
    test('list filters to addressbook resources', () async {
      final fake = _FakeCardDavWebDav();
      final home = Uri.parse('https://dav.example.com/ab/');
      final service = AddressBookService(fake, home);

      fake.propfindResponse = Response(
        requestOptions: RequestOptions(path: home.path),
        statusCode: 207,
        data: '''<?xml version="1.0"?>
<D:multistatus xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:carddav" xmlns:CS="http://calendarserver.org/ns/">
  <D:response>
    <D:href>/ab/</D:href>
    <D:propstat>
      <D:prop>
        <D:resourcetype><D:collection/></D:resourcetype>
        <D:displayname>Home</D:displayname>
      </D:prop>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/ab/personal/</D:href>
    <D:propstat>
      <D:prop>
        <D:resourcetype>
          <D:collection/>
          <C:addressbook/>
        </D:resourcetype>
        <D:displayname>Personal</D:displayname>
        <C:addressbook-description>My contacts</C:addressbook-description>
        <CS:getctag>42</CS:getctag>
      </D:prop>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>
</D:multistatus>''',
      );

      final books = await service.list();
      expect(books, hasLength(1));
      expect(books.first.displayName, 'Personal');
      expect(books.first.description, 'My contacts');
      expect(books.first.ctag, '42');
      expect(books.first.href.path, '/ab/personal/');
    });

    test('create uses extended MKCOL body', () async {
      final fake = _FakeCardDavWebDav();
      final home = Uri.parse('https://dav.example.com/ab/');
      final service = AddressBookService(fake, home);

      fake.mkcolResponse = Response(
        requestOptions: RequestOptions(path: '/ab/work/'),
        statusCode: 201,
        data: '',
      );
      fake.propfindResponse = Response(
        requestOptions: RequestOptions(path: '/ab/work/'),
        statusCode: 207,
        data: '''<?xml version="1.0"?>
<D:multistatus xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:carddav">
  <D:response>
    <D:href>/ab/work/</D:href>
    <D:propstat>
      <D:prop>
        <D:resourcetype>
          <D:collection/>
          <C:addressbook/>
        </D:resourcetype>
        <D:displayname>Work</D:displayname>
      </D:prop>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>
</D:multistatus>''',
      );

      final book = await service.create('Work', description: 'Office');
      expect(book.displayName, 'Work');
      expect(fake.lastMkcolBody, contains('addressbook'));
      expect(fake.lastMkcolBody, contains('Office'));
      expect(fake.lastMkcolBody, contains('mkcol'));
    });
  });
}

/// Fake WebDAV client for CardDAV unit tests.
class _FakeCardDavWebDav implements WebDavClient {
  Response<String>? propfindResponse;
  Response<String>? proppatchResponse;
  Response<String>? mkcolResponse;
  Response<String>? putResponse;
  Response<String>? reportResponse;
  Response<String>? deleteResponse;

  Response<String> Function(String path, String body, DavDepth depth)?
      reportHandler;

  String? lastReportBody;
  String? lastPutBody;
  String? lastPutContentType;
  String? lastPutIfNoneMatch;
  String? lastMkcolBody;

  @override
  Future<Response<String>> propfind(
    String path, {
    required String body,
    DavDepth depth = DavDepth.zero,
  }) async =>
      propfindResponse!;

  @override
  Future<Response<String>> proppatch(
    String path, {
    required String body,
  }) async =>
      proppatchResponse!;

  @override
  Future<Response<String>> mkcol(String path, {String? body}) async {
    lastMkcolBody = body;
    return mkcolResponse!;
  }

  @override
  Future<Response<String>> mkcalendar(String path, {String? body}) {
    throw UnimplementedError();
  }

  @override
  Future<Response<String>> report(
    String path, {
    required String body,
    DavDepth depth = DavDepth.one,
  }) async {
    lastReportBody = body;
    if (reportHandler != null) {
      return reportHandler!(path, body, depth);
    }
    return reportResponse!;
  }

  @override
  Future<Response<String>> put(
    String path, {
    required String body,
    String contentType = 'application/octet-stream',
    String? ifMatch,
    String? ifNoneMatch,
    String? lockToken,
  }) async {
    lastPutBody = body;
    lastPutContentType = contentType;
    lastPutIfNoneMatch = ifNoneMatch;
    return putResponse!;
  }

  @override
  Future<Response<String>> delete(
    String path, {
    String? ifMatch,
    String? lockToken,
    DavDepth? depth,
  }) async =>
      deleteResponse ??
      Response(
        requestOptions: RequestOptions(path: path),
        statusCode: 204,
        data: '',
      );

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
