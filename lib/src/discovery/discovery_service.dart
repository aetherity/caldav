import 'package:dio/dio.dart';
import 'package:xml/xml.dart';

import '../client/dio_webdav_client.dart';
import '../exceptions/caldav_exception.dart';
import '../webdav/dav_depth.dart';
import '../webdav/multistatus.dart';
import '../webdav/propfind_builder.dart';
import '../webdav/xml_namespaces.dart';
import 'discovery_result.dart';
import 'dual_discovery_result.dart';

/// Service for discovering CalDAV and CardDAV endpoints (RFC 6764).
class DiscoveryService {
  final DioWebDavClient _client;
  final Dio _dio;

  DiscoveryService(this._client, this._dio);

  /// Discover CalDAV and CardDAV in parallel.
  ///
  /// Failures on one protocol do not cancel the other. Use
  /// [DualDiscoveryResult.ensureAny] if at least one must succeed.
  Future<DualDiscoveryResult> discoverBoth(Uri baseUrl) async {
    DiscoveryResult? caldav;
    CardDavDiscoveryResult? carddav;
    Object? caldavError;
    Object? carddavError;

    final results = await Future.wait([
      discover(baseUrl).then<Object?>((v) => v).catchError((Object e) => e),
      discoverCardDav(baseUrl)
          .then<Object?>((v) => v)
          .catchError((Object e) => e),
    ]);

    final cal = results[0];
    final card = results[1];
    if (cal is DiscoveryResult) {
      caldav = cal;
    } else {
      caldavError = cal;
    }
    if (card is CardDavDiscoveryResult) {
      carddav = card;
    } else {
      carddavError = card;
    }

    return DualDiscoveryResult(
      caldav: caldav,
      carddav: carddav,
      caldavError: caldavError,
      carddavError: carddavError,
    );
  }

  /// Discover CalDAV endpoints from base URL.
  ///
  /// Flow:
  /// 1. Try `/.well-known/caldav` for redirect
  /// 2. PROPFIND for `current-user-principal`
  /// 3. PROPFIND for `calendar-home-set` (+ free-busy / scheduling props)
  Future<DiscoveryResult> discover(Uri baseUrl) async {
    final caldavEndpoint = await _discoverWellKnown(baseUrl, 'caldav');
    final principalUrl = await _discoverPrincipal(caldavEndpoint);
    final principalProps = await _discoverCalDavPrincipalProps(principalUrl);

    return DiscoveryResult(
      caldavEndpoint: caldavEndpoint,
      principalUrl: principalUrl,
      calendarHomeSet: principalProps.calendarHomeSet,
      displayName: principalProps.displayName,
      freeBusySet: principalProps.freeBusySet,
      scheduleOutboxUrl: principalProps.scheduleOutboxUrl,
      scheduleInboxUrl: principalProps.scheduleInboxUrl,
      calendarUserAddresses: principalProps.calendarUserAddresses,
    );
  }

  /// Discover CardDAV endpoints from base URL.
  ///
  /// Flow:
  /// 1. Try `/.well-known/carddav` for redirect
  /// 2. PROPFIND for `current-user-principal`
  /// 3. PROPFIND for `addressbook-home-set`
  Future<CardDavDiscoveryResult> discoverCardDav(Uri baseUrl) async {
    final carddavEndpoint = await _discoverWellKnown(baseUrl, 'carddav');
    final principalUrl = await _discoverPrincipal(carddavEndpoint);
    final (addressbookHome, displayName) = await _discoverHomeSet(
      principalUrl,
      propertyLocalName: 'addressbook-home-set',
      propertyNamespace: XmlNamespaces.carddav,
      missingMessage: 'addressbook-home-set not found',
    );

    return CardDavDiscoveryResult(
      carddavEndpoint: carddavEndpoint,
      principalUrl: principalUrl,
      addressbookHomeSet: addressbookHome,
      displayName: displayName,
    );
  }

  /// Try well-known URL for a DAV service (`caldav` or `carddav`).
  Future<Uri> _discoverWellKnown(Uri baseUrl, String service) async {
    final wellKnownUrl = baseUrl.resolve('/.well-known/$service');

    try {
      final response = await _dio.get<String>(
        wellKnownUrl.toString(),
        options: Options(
          followRedirects: false,
          validateStatus: (status) => status != null && status < 400,
        ),
      );

      if (response.statusCode == 301 ||
          response.statusCode == 302 ||
          response.statusCode == 307 ||
          response.statusCode == 308) {
        final location = response.headers.value('location');
        if (location != null) {
          return baseUrl.resolve(location);
        }
      }

      return wellKnownUrl;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404 || e.response?.statusCode == 401) {
        return baseUrl;
      }
      rethrow;
    }
  }

  /// Discover current user's principal URL.
  Future<Uri> _discoverPrincipal(Uri endpoint) async {
    final body = PropfindBuilder.currentUserPrincipal();

    try {
      final response = await _client.propfind(
        endpoint.toString(),
        body: body,
        depth: DavDepth.zero,
      );

      final multiStatus = MultiStatus.fromXml(response.data ?? '');
      final davResponse = multiStatus.first;

      if (davResponse == null) {
        throw const DiscoveryException('No response from server');
      }

      final principalElement = davResponse.getPropertyElement(
        'current-user-principal',
        namespace: XmlNamespaces.dav,
      );

      final href = principalElement
          ?.findElements('href', namespaceUri: XmlNamespaces.dav)
          .firstOrNull
          ?.innerText;

      if (href == null || href.isEmpty) {
        throw const DiscoveryException('current-user-principal not found');
      }

      return endpoint.resolve(href);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw const AuthenticationException();
      }
      if (e.response?.statusCode == 403) {
        throw const ForbiddenException();
      }
      throw DiscoveryException(
        'Failed to discover principal: ${e.message}',
      );
    }
  }

  /// Discover a home-set property from the principal.
  Future<(Uri, String?)> _discoverHomeSet(
    Uri principalUrl, {
    required String propertyLocalName,
    required String propertyNamespace,
    required String missingMessage,
  }) async {
    final body = PropfindBuilder()
        .addProperty(
          propertyLocalName,
          propertyNamespace,
          _prefixFor(propertyNamespace),
        )
        .addDavProperty('displayname')
        .build();

    try {
      final response = await _client.propfind(
        principalUrl.toString(),
        body: body,
        depth: DavDepth.zero,
      );

      final multiStatus = MultiStatus.fromXml(response.data ?? '');
      final davResponse = multiStatus.first;

      if (davResponse == null) {
        throw const DiscoveryException('No response from server');
      }

      final homeSetElement = davResponse.getPropertyElement(
        propertyLocalName,
        namespace: propertyNamespace,
      );

      final href = homeSetElement
          ?.findElements('href', namespaceUri: XmlNamespaces.dav)
          .firstOrNull
          ?.innerText;

      if (href == null || href.isEmpty) {
        throw DiscoveryException(missingMessage);
      }

      final displayName = davResponse.getProperty(
        'displayname',
        namespace: XmlNamespaces.dav,
      );

      return (principalUrl.resolve(href), displayName);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw const AuthenticationException();
      }
      if (e.response?.statusCode == 403) {
        throw const ForbiddenException();
      }
      throw DiscoveryException(
        'Failed to discover home set ($propertyLocalName): ${e.message}',
      );
    }
  }

  /// Discover calendar-home-set plus free-busy / scheduling properties.
  Future<_CalDavPrincipalProps> _discoverCalDavPrincipalProps(
    Uri principalUrl,
  ) async {
    final body = PropfindBuilder()
        .addCalDavProperty('calendar-home-set')
        .addCalDavProperty('calendar-free-busy-set')
        .addCalDavProperty('schedule-outbox-URL')
        .addCalDavProperty('schedule-inbox-URL')
        .addCalDavProperty('calendar-user-address-set')
        .addDavProperty('displayname')
        .build();

    try {
      final response = await _client.propfind(
        principalUrl.toString(),
        body: body,
        depth: DavDepth.zero,
      );

      final multiStatus = MultiStatus.fromXml(response.data ?? '');
      final davResponse = multiStatus.first;

      if (davResponse == null) {
        throw const DiscoveryException('No response from server');
      }

      final homeSetElement = davResponse.getPropertyElement(
        'calendar-home-set',
        namespace: XmlNamespaces.caldav,
      );
      final homeHref = homeSetElement
          ?.findElements('href', namespaceUri: XmlNamespaces.dav)
          .firstOrNull
          ?.innerText;

      if (homeHref == null || homeHref.isEmpty) {
        throw const DiscoveryException('calendar-home-set not found');
      }

      final freeBusySet = _hrefsFromProperty(
        davResponse,
        'calendar-free-busy-set',
        XmlNamespaces.caldav,
        principalUrl,
      );

      final outbox = _singleHrefFromProperty(
        davResponse,
        'schedule-outbox-URL',
        XmlNamespaces.caldav,
        principalUrl,
      );
      final inbox = _singleHrefFromProperty(
        davResponse,
        'schedule-inbox-URL',
        XmlNamespaces.caldav,
        principalUrl,
      );

      final addresses = <String>[];
      final addressElement = davResponse.getPropertyElement(
        'calendar-user-address-set',
        namespace: XmlNamespaces.caldav,
      );
      if (addressElement != null) {
        for (final href in addressElement.findElements(
          'href',
          namespaceUri: XmlNamespaces.dav,
        )) {
          final text = href.innerText.trim();
          if (text.isNotEmpty) addresses.add(text);
        }
      }

      final displayName = davResponse.getProperty(
        'displayname',
        namespace: XmlNamespaces.dav,
      );

      return _CalDavPrincipalProps(
        calendarHomeSet: principalUrl.resolve(homeHref),
        displayName: displayName,
        freeBusySet: freeBusySet,
        scheduleOutboxUrl: outbox,
        scheduleInboxUrl: inbox,
        calendarUserAddresses: addresses,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw const AuthenticationException();
      }
      if (e.response?.statusCode == 403) {
        throw const ForbiddenException();
      }
      throw DiscoveryException(
        'Failed to discover calendar principal properties: ${e.message}',
      );
    }
  }

  static List<Uri> _hrefsFromProperty(
    DavResponse response,
    String localName,
    String namespace,
    Uri base,
  ) {
    final element = response.getPropertyElement(
      localName,
      namespace: namespace,
    );
    if (element == null) return const [];
    final result = <Uri>[];
    for (final href in element.findElements(
      'href',
      namespaceUri: XmlNamespaces.dav,
    )) {
      final text = href.innerText.trim();
      if (text.isNotEmpty) result.add(base.resolve(text));
    }
    return result;
  }

  static Uri? _singleHrefFromProperty(
    DavResponse response,
    String localName,
    String namespace,
    Uri base,
  ) {
    final hrefs = _hrefsFromProperty(response, localName, namespace, base);
    return hrefs.isEmpty ? null : hrefs.first;
  }

  static String _prefixFor(String namespace) {
    if (namespace == XmlNamespaces.caldav) return 'C';
    if (namespace == XmlNamespaces.carddav) return 'CARD';
    return 'X';
  }
}

class _CalDavPrincipalProps {
  final Uri calendarHomeSet;
  final String? displayName;
  final List<Uri> freeBusySet;
  final Uri? scheduleOutboxUrl;
  final Uri? scheduleInboxUrl;
  final List<String> calendarUserAddresses;

  const _CalDavPrincipalProps({
    required this.calendarHomeSet,
    this.displayName,
    this.freeBusySet = const [],
    this.scheduleOutboxUrl,
    this.scheduleInboxUrl,
    this.calendarUserAddresses = const [],
  });
}
