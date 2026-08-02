import 'package:caldav/caldav.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  group('DavDepth', () {
    test('headerValue maps to RFC values', () {
      expect(DavDepth.zero.headerValue, '0');
      expect(DavDepth.one.headerValue, '1');
      expect(DavDepth.infinity.headerValue, 'infinity');
    });

    test('tryParse accepts case-insensitive infinity', () {
      expect(DavDepth.tryParse('0'), DavDepth.zero);
      expect(DavDepth.tryParse('1'), DavDepth.one);
      expect(DavDepth.tryParse('infinity'), DavDepth.infinity);
      expect(DavDepth.tryParse('Infinity'), DavDepth.infinity);
      expect(DavDepth.tryParse('  INFINITY  '), DavDepth.infinity);
      expect(DavDepth.tryParse('2'), isNull);
      expect(DavDepth.tryParse(null), isNull);
    });
  });

  group('PropfindBuilder', () {
    test('resourceProperties includes core DAV live properties', () {
      final xml = PropfindBuilder.resourceProperties();
      expect(xml, contains('resourcetype'));
      expect(xml, contains('displayname'));
      expect(xml, contains('getetag'));
      expect(xml, contains('getcontenttype'));
      expect(xml, contains('getcontentlength'));
      expect(xml, contains('getlastmodified'));
      expect(xml, contains('creationdate'));
      expect(xml, contains('current-user-privilege-set'));
    });

    test('addressbookHomeSet uses CardDAV namespace', () {
      final xml = PropfindBuilder.addressbookHomeSet();
      expect(xml, contains('addressbook-home-set'));
      expect(xml, contains(XmlNamespaces.carddav));
    });

    test('addressbookProperties includes CardDAV props', () {
      final xml = PropfindBuilder.addressbookProperties();
      expect(xml, contains('addressbook-description'));
      expect(xml, contains('supported-address-data'));
      expect(xml, contains('getctag'));
    });

    test('allpropWithInclude embeds extra properties', () {
      final xml = PropfindBuilder.allpropWithInclude([
        '<C:calendar-data xmlns:C="urn:ietf:params:xml:ns:caldav"/>',
      ]);
      expect(xml, contains('<D:allprop/>'));
      expect(xml, contains('<D:include>'));
      expect(xml, contains('calendar-data'));
    });

    test('addCardDavProperty declares CardDAV namespace', () {
      final xml = PropfindBuilder()
          .addCardDavProperty('addressbook-description')
          .build();
      expect(xml, contains(XmlNamespaces.carddav));
      expect(xml, contains('addressbook-description'));
    });
  });

  group('ProppatchBuilder', () {
    test('builds set-only propertyupdate', () {
      final xml = ProppatchBuilder()
          .setDavProperty('displayname', 'Work')
          .build();

      expect(xml, contains('<D:propertyupdate'));
      expect(xml, contains('<D:set>'));
      expect(xml, contains('<D:displayname>Work</D:displayname>'));
      expect(xml, isNot(contains('<D:remove>')));
    });

    test('builds remove-only propertyupdate', () {
      final xml = ProppatchBuilder()
          .removeDavProperty('displayname')
          .build();

      expect(xml, contains('<D:remove>'));
      expect(xml, contains('<D:displayname/>'));
      expect(xml, isNot(contains('<D:set>')));
    });

    test('builds combined set and remove', () {
      final xml = ProppatchBuilder()
          .setDavProperty('displayname', 'New Name')
          .setCalDavProperty('calendar-description', 'Desc')
          .removeAppleProperty('calendar-color')
          .build();

      expect(xml, contains('<D:set>'));
      expect(xml, contains('<D:remove>'));
      expect(xml, contains('New Name'));
      expect(xml, contains('calendar-description'));
      expect(xml, contains('calendar-color'));
      expect(xml, contains(XmlNamespaces.caldav));
      expect(xml, contains(XmlNamespaces.apple));
    });

    test('escapes XML special characters in set values', () {
      final xml = ProppatchBuilder()
          .setDavProperty('displayname', 'A & B <C>')
          .build();

      expect(xml, contains('A &amp; B &lt;C&gt;'));
    });

    test('setPropertyRaw does not escape inner XML', () {
      final xml = ProppatchBuilder()
          .setPropertyRaw(
            'resourcetype',
            XmlNamespaces.dav,
            'D',
            '<D:collection/>',
          )
          .build();

      expect(xml, contains('<D:resourcetype><D:collection/></D:resourcetype>'));
    });

    test('throws when empty', () {
      expect(() => ProppatchBuilder().build(), throwsStateError);
    });
  });

  group('MultiStatus', () {
    test('parses propstat success as before', () {
      const xml = '''<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/calendars/user/default/</D:href>
    <D:propstat>
      <D:prop>
        <D:displayname>Default</D:displayname>
        <D:resourcetype>
          <D:collection/>
          <C:calendar xmlns:C="urn:ietf:params:xml:ns:caldav"/>
        </D:resourcetype>
      </D:prop>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>
</D:multistatus>''';

      final multi = MultiStatus.fromXml(xml);
      expect(multi.responses, hasLength(1));
      final r = multi.responses.first;
      expect(r.isSuccess, isTrue);
      expect(r.isCollection, isTrue);
      expect(r.isCalendar, isTrue);
      expect(r.isAddressBook, isFalse);
      expect(r.getProperty('displayname', namespace: XmlNamespaces.dav), 'Default');
    });

    test('parses address book resourcetype', () {
      const xml = '''<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:carddav">
  <D:response>
    <D:href>/addressbooks/user/default/</D:href>
    <D:propstat>
      <D:prop>
        <D:resourcetype>
          <D:collection/>
          <C:addressbook/>
        </D:resourcetype>
      </D:prop>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>
</D:multistatus>''';

      final multi = MultiStatus.fromXml(xml);
      final r = multi.responses.first;
      expect(r.isAddressBook, isTrue);
      expect(r.isCollection, isTrue);
      expect(r.isCalendar, isFalse);
    });

    test('parses response-level status without propstat', () {
      const xml = '''<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/dest/file.txt</D:href>
    <D:status>HTTP/1.1 201 Created</D:status>
    <D:responsedescription>Copied</D:responsedescription>
  </D:response>
  <D:response>
    <D:href>/dest/locked.txt</D:href>
    <D:status>HTTP/1.1 423 Locked</D:status>
    <D:error><D:lock-token-submitted/></D:error>
  </D:response>
</D:multistatus>''';

      final multi = MultiStatus.fromXml(xml);
      expect(multi.responses, hasLength(2));

      final ok = multi.responses[0];
      expect(ok.statusCode, 201);
      expect(ok.isSuccess, isTrue);
      expect(ok.propStats, isEmpty);
      expect(ok.responseDescription, 'Copied');

      final locked = multi.responses[1];
      expect(locked.statusCode, 423);
      expect(locked.isSuccess, isFalse);
      expect(locked.errors, contains('lock-token-submitted'));
    });

    test('parses propstat errors and top-level responsedescription', () {
      const xml = '''<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:responsedescription>Partial failure</D:responsedescription>
  <D:response>
    <D:href>/res</D:href>
    <D:propstat>
      <D:prop><D:displayname/></D:prop>
      <D:status>HTTP/1.1 403 Forbidden</D:status>
      <D:error><D:cannot-modify-protected-property/></D:error>
      <D:responsedescription>Protected</D:responsedescription>
    </D:propstat>
  </D:response>
</D:multistatus>''';

      final multi = MultiStatus.fromXml(xml);
      expect(multi.responseDescription, 'Partial failure');
      expect(multi.isSuccess, isFalse);

      final ps = multi.responses.first.propStats.first;
      expect(ps.isSuccess, isFalse);
      expect(ps.statusCode, 403);
      expect(ps.errors, contains('cannot-modify-protected-property'));
      expect(ps.responseDescription, 'Protected');
    });

    test('parses location href', () {
      const xml = '''<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/old</D:href>
    <D:status>HTTP/1.1 201 Created</D:status>
    <D:location>
      <D:href>/new/path</D:href>
    </D:location>
  </D:response>
</D:multistatus>''';

      final r = MultiStatus.fromXml(xml).responses.first;
      expect(r.locationHref, '/new/path');
    });
  });

  group('ResourceService', () {
    late _FakeWebDavClient fake;
    late ResourceService service;

    setUp(() {
      fake = _FakeWebDavClient();
      service = ResourceService(
        fake,
        baseUri: Uri.parse('https://dav.example.com/'),
      );
    });

    test('list parses resources and resolves hrefs', () async {
      fake.propfindResponse = Response(
        requestOptions: RequestOptions(path: '/home/'),
        statusCode: 207,
        data: '''<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/home/docs/</D:href>
    <D:propstat>
      <D:prop>
        <D:displayname>Documents</D:displayname>
        <D:getetag>"abc"</D:getetag>
        <D:getcontenttype>httpd/unix-directory</D:getcontenttype>
        <D:resourcetype><D:collection/></D:resourcetype>
      </D:prop>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/home/readme.txt</D:href>
    <D:propstat>
      <D:prop>
        <D:displayname>Readme</D:displayname>
        <D:getcontentlength>42</D:getcontentlength>
        <D:getcontenttype>text/plain</D:getcontenttype>
        <D:resourcetype/>
      </D:prop>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>
</D:multistatus>''',
      );

      final resources = await service.list('/home/');
      expect(resources, hasLength(2));

      expect(resources[0].displayName, 'Documents');
      expect(resources[0].isCollection, isTrue);
      expect(resources[0].etag, '"abc"');
      expect(resources[0].href.path, '/home/docs/');

      expect(resources[1].displayName, 'Readme');
      expect(resources[1].isCollection, isFalse);
      expect(resources[1].contentLength, 42);
      expect(resources[1].contentType, 'text/plain');

      expect(fake.lastPropfindDepth, DavDepth.one);
    });

    test('updateProperties sends proppatch body', () async {
      fake.proppatchResponse = Response(
        requestOptions: RequestOptions(path: '/home/docs/'),
        statusCode: 207,
        data: '''<?xml version="1.0"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/home/docs/</D:href>
    <D:propstat>
      <D:prop><D:displayname/></D:prop>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>
</D:multistatus>''',
      );

      final result = await service.updateProperties(
        '/home/docs/',
        ProppatchBuilder().setDavProperty('displayname', 'Docs'),
      );

      expect(result.isSuccess, isTrue);
      expect(fake.lastProppatchBody, contains('Docs'));
      expect(fake.lastProppatchBody, contains('<D:set>'));
    });

    test('createCollection delegates to mkcol', () async {
      fake.mkcolResponse = Response(
        requestOptions: RequestOptions(path: '/home/new/'),
        statusCode: 201,
        data: '',
      );

      await service.createCollection('/home/new/');
      expect(fake.mkcolCalls, ['/home/new/']);
    });

    test('copy and move pass destination and overwrite', () async {
      fake.copyResponse = Response(
        requestOptions: RequestOptions(path: '/a'),
        statusCode: 201,
        data: '',
      );
      fake.moveResponse = Response(
        requestOptions: RequestOptions(path: '/a'),
        statusCode: 201,
        data: '',
      );

      await service.copy(
        '/a',
        destination: 'https://dav.example.com/b',
        overwrite: false,
        depth: DavDepth.zero,
      );
      expect(fake.lastCopyDestination, 'https://dav.example.com/b');
      expect(fake.lastCopyOverwrite, isFalse);
      expect(fake.lastCopyDepth, DavDepth.zero);

      await service.move(
        '/a',
        destination: 'https://dav.example.com/c',
      );
      expect(fake.lastMoveDestination, 'https://dav.example.com/c');
      expect(fake.lastMoveOverwrite, isTrue);
    });

    test('put returns etag and uses content type', () async {
      fake.putResponse = Response(
        requestOptions: RequestOptions(path: '/file.txt'),
        statusCode: 201,
        data: '',
        headers: Headers.fromMap({
          'etag': ['"etag-1"'],
        }),
      );

      final etag = await service.put(
        '/file.txt',
        body: 'hello',
        contentType: 'text/plain; charset=utf-8',
        ifNoneMatch: '*',
      );

      expect(etag, '"etag-1"');
      expect(fake.lastPutContentType, 'text/plain; charset=utf-8');
      expect(fake.lastPutIfNoneMatch, '*');
    });

    test('options parses Allow and DAV headers', () async {
      fake.optionsResponse = Response(
        requestOptions: RequestOptions(path: '/'),
        statusCode: 200,
        data: '',
        headers: Headers.fromMap({
          'allow': ['OPTIONS, GET, HEAD, PUT, DELETE, PROPFIND, PROPPATCH, MKCOL, COPY, MOVE'],
          'dav': ['1, 2, 3, calendar-access, addressbook'],
        }),
      );

      final caps = await service.options('/');
      expect(caps.supportsClass1, isTrue);
      expect(caps.supportsClass2, isTrue);
      expect(caps.supportsClass3, isTrue);
      expect(caps.supportsCalDav, isTrue);
      expect(caps.supportsCardDav, isTrue);
      expect(caps.allows('PROPFIND'), isTrue);
      expect(caps.allows('LOCK'), isFalse);
    });

    test('delete treats 404 as success', () async {
      fake.deleteError = DioException(
        requestOptions: RequestOptions(path: '/missing'),
        response: Response(
          requestOptions: RequestOptions(path: '/missing'),
          statusCode: 404,
        ),
        type: DioExceptionType.badResponse,
      );

      await service.delete('/missing'); // should not throw
    });

    test('maps 401 to AuthenticationException', () async {
      fake.propfindError = DioException(
        requestOptions: RequestOptions(path: '/'),
        response: Response(
          requestOptions: RequestOptions(path: '/'),
          statusCode: 401,
        ),
        type: DioExceptionType.badResponse,
      );

      expect(
        () => service.list('/'),
        throwsA(isA<AuthenticationException>()),
      );
    });
  });

  group('DavResource', () {
    test('equality is by href', () {
      final a = DavResource(href: Uri.parse('https://x/a'));
      final b = DavResource(
        href: Uri.parse('https://x/a'),
        displayName: 'A',
      );
      final c = DavResource(href: Uri.parse('https://x/b'));

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('copyWith updates selected fields', () {
      final original = DavResource(
        href: Uri.parse('https://x/a'),
        displayName: 'A',
        isCollection: true,
      );
      final copy = original.copyWith(displayName: 'B', etag: '"1"');
      expect(copy.displayName, 'B');
      expect(copy.etag, '"1"');
      expect(copy.isCollection, isTrue);
      expect(copy.href, original.href);
    });
  });
}

/// Minimal fake for [WebDavClient] used by [ResourceService] tests.
class _FakeWebDavClient implements WebDavClient {
  Response<String>? propfindResponse;
  Response<String>? proppatchResponse;
  Response<String>? mkcolResponse;
  Response<String>? copyResponse;
  Response<String>? moveResponse;
  Response<String>? putResponse;
  Response<String>? optionsResponse;
  Response<String>? headResponse;
  Response<String>? getResponse;
  Response<String>? deleteResponse;

  DioException? propfindError;
  DioException? deleteError;

  DavDepth? lastPropfindDepth;
  String? lastProppatchBody;
  final List<String> mkcolCalls = [];
  String? lastCopyDestination;
  bool? lastCopyOverwrite;
  DavDepth? lastCopyDepth;
  String? lastMoveDestination;
  bool? lastMoveOverwrite;
  String? lastPutContentType;
  String? lastPutIfNoneMatch;

  @override
  Future<Response<String>> propfind(
    String path, {
    required String body,
    DavDepth depth = DavDepth.zero,
  }) async {
    if (propfindError != null) throw propfindError!;
    lastPropfindDepth = depth;
    return propfindResponse!;
  }

  @override
  Future<Response<String>> proppatch(
    String path, {
    required String body,
  }) async {
    lastProppatchBody = body;
    return proppatchResponse!;
  }

  @override
  Future<Response<String>> mkcol(String path, {String? body}) async {
    mkcolCalls.add(path);
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
  }) {
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
  }) async {
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
  }) async {
    if (deleteError != null) throw deleteError!;
    return deleteResponse ??
        Response(
          requestOptions: RequestOptions(path: path),
          statusCode: 204,
          data: '',
        );
  }

  @override
  Future<Response<String>> get(String path) async => getResponse!;

  @override
  Future<Response<String>> post(
    String path, {
    required String body,
    String contentType = 'application/xml; charset=utf-8',
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Response<String>> head(String path) async => headResponse!;

  @override
  Future<Response<String>> copy(
    String path, {
    required String destination,
    bool overwrite = true,
    DavDepth depth = DavDepth.infinity,
    String? ifMatch,
    String? lockToken,
  }) async {
    lastCopyDestination = destination;
    lastCopyOverwrite = overwrite;
    lastCopyDepth = depth;
    return copyResponse!;
  }

  @override
  Future<Response<String>> move(
    String path, {
    required String destination,
    bool overwrite = true,
    DavDepth depth = DavDepth.infinity,
    String? ifMatch,
    String? lockToken,
  }) async {
    lastMoveDestination = destination;
    lastMoveOverwrite = overwrite;
    return moveResponse!;
  }

  @override
  Future<Response<String>> options(String path) async => optionsResponse!;
}
