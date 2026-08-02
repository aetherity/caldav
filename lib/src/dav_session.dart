import 'package:dio/dio.dart';

import 'caldav_client.dart';
import 'carddav/carddav_client.dart';
import 'client/dio_webdav_client.dart';
import 'client/interceptors/auth_interceptor.dart';
import 'discovery/discovery_result.dart';
import 'discovery/discovery_service.dart';
import 'discovery/dual_discovery_result.dart';
import 'exceptions/caldav_exception.dart';
import 'webdav/resource_service.dart';

/// Shared session for CalDAV and CardDAV over one HTTP client and auth context.
///
/// Use this when an app needs calendars and contacts against the same host
/// (typical for Nextcloud, iCloud, Fastmail, etc.).
///
/// ```dart
/// final session = await DavSession.connect(
///   baseUrl: 'https://dav.example.com',
///   username: 'user',
///   password: 'pass',
/// );
///
/// try {
///   if (session.hasCalDav) {
///     final calendars = await session.caldav.getCalendars();
///   }
///   if (session.hasCardDav) {
///     final books = await session.carddav.getAddressBooks();
///   }
/// } finally {
///   session.close();
/// }
/// ```
///
/// Do **not** call [CalDavClient.close] / [CardDavClient.close] on the nested
/// clients when using a session; they share this session's Dio. Always call
/// [DavSession.close].
class DavSession {
  final Dio _dio;
  final DioWebDavClient _webdavClient;
  final DiscoveryService _discoveryService;
  final Uri baseUrl;
  final bool _ownsDio;

  final CalDavClient caldav;
  final CardDavClient carddav;

  DualDiscoveryResult? _dualDiscovery;

  DavSession._({
    required Dio dio,
    required DioWebDavClient webdavClient,
    required DiscoveryService discoveryService,
    required this.baseUrl,
    required this.caldav,
    required this.carddav,
    required bool ownsDio,
  })  : _dio = dio,
        _webdavClient = webdavClient,
        _discoveryService = discoveryService,
        _ownsDio = ownsDio;

  /// Create a session with Basic Authentication (does not discover yet).
  factory DavSession({
    required String baseUrl,
    required String username,
    required String password,
    Duration connectTimeout = const Duration(seconds: 30),
    Duration receiveTimeout = const Duration(seconds: 30),
    bool allowInsecure = false,
  }) {
    final uri = Uri.parse(baseUrl);
    _validateSecureConnection(uri, allowInsecure);

    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
      validateStatus: (status) => status != null && status < 400,
    ));
    dio.interceptors.add(BasicAuthInterceptor(
      username: username,
      password: password,
    ));

    return DavSession._fromDio(
      baseUrl: baseUrl,
      uri: uri,
      dio: dio,
      allowInsecure: allowInsecure,
      ownsDio: true,
    );
  }

  /// Create a session with Bearer token authentication.
  factory DavSession.withToken({
    required String baseUrl,
    required String token,
    Duration connectTimeout = const Duration(seconds: 30),
    Duration receiveTimeout = const Duration(seconds: 30),
    bool allowInsecure = false,
  }) {
    final uri = Uri.parse(baseUrl);
    _validateSecureConnection(uri, allowInsecure);

    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
      validateStatus: (status) => status != null && status < 400,
    ));
    dio.interceptors.add(BearerAuthInterceptor(token));

    return DavSession._fromDio(
      baseUrl: baseUrl,
      uri: uri,
      dio: dio,
      allowInsecure: allowInsecure,
      ownsDio: true,
    );
  }

  /// Create a session around an existing Dio instance.
  ///
  /// The session does not take ownership of [dio] (`close` will not close it).
  factory DavSession.withDio({
    required String baseUrl,
    required Dio dio,
    bool allowInsecure = false,
  }) {
    final uri = Uri.parse(baseUrl);
    _validateSecureConnection(uri, allowInsecure);
    return DavSession._fromDio(
      baseUrl: baseUrl,
      uri: uri,
      dio: dio,
      allowInsecure: allowInsecure,
      ownsDio: false,
    );
  }

  factory DavSession._fromDio({
    required String baseUrl,
    required Uri uri,
    required Dio dio,
    required bool allowInsecure,
    required bool ownsDio,
  }) {
    final webdavClient = DioWebDavClient(dio);
    final discoveryService = DiscoveryService(webdavClient, dio);

    final caldav = CalDavClient.withDio(
      baseUrl: baseUrl,
      dio: dio,
      allowInsecure: allowInsecure,
      ownsDio: false,
    );
    final carddav = CardDavClient.withDio(
      baseUrl: baseUrl,
      dio: dio,
      allowInsecure: allowInsecure,
      ownsDio: false,
    );

    return DavSession._(
      dio: dio,
      webdavClient: webdavClient,
      discoveryService: discoveryService,
      baseUrl: uri,
      caldav: caldav,
      carddav: carddav,
      ownsDio: ownsDio,
    );
  }

  /// Create, discover both protocols, and return a ready session.
  ///
  /// Throws [DiscoveryException] if neither CalDAV nor CardDAV succeeds
  /// (unless a specific protocol is required via flags).
  static Future<DavSession> connect({
    required String baseUrl,
    required String username,
    required String password,
    Duration connectTimeout = const Duration(seconds: 30),
    Duration receiveTimeout = const Duration(seconds: 30),
    bool allowInsecure = false,
    bool requireCalDav = false,
    bool requireCardDav = false,
  }) async {
    final session = DavSession(
      baseUrl: baseUrl,
      username: username,
      password: password,
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
      allowInsecure: allowInsecure,
    );
    await session.discover(
      requireCalDav: requireCalDav,
      requireCardDav: requireCardDav,
    );
    return session;
  }

  static void _validateSecureConnection(Uri uri, bool allowInsecure) {
    if (!allowInsecure && uri.scheme != 'https') {
      throw CalDavException(
        'Insecure connection not allowed. '
        'Use HTTPS or set allowInsecure: true for development. '
        'URL scheme: ${uri.scheme}',
        statusCode: null,
      );
    }
  }

  /// Discover CalDAV and CardDAV in parallel and seed nested clients.
  Future<DualDiscoveryResult> discover({
    bool requireCalDav = false,
    bool requireCardDav = false,
  }) async {
    final dual = await _discoveryService.discoverBoth(baseUrl);
    _dualDiscovery = dual;

    if (requireCalDav && !dual.hasCalDav) {
      throw DiscoveryException(
        'CalDAV discovery required but failed: ${dual.caldavError}',
      );
    }
    if (requireCardDav && !dual.hasCardDav) {
      throw DiscoveryException(
        'CardDAV discovery required but failed: ${dual.carddavError}',
      );
    }
    if (!requireCalDav && !requireCardDav) {
      dual.ensureAny();
    }

    if (dual.caldav != null) {
      caldav.seedDiscovery(dual.caldav!);
    }
    if (dual.carddav != null) {
      carddav.seedDiscovery(dual.carddav!);
    }

    return dual;
  }

  /// Last dual discovery result, if [discover] has been called.
  DualDiscoveryResult? get dualDiscovery => _dualDiscovery;

  bool get hasCalDav => _dualDiscovery?.hasCalDav ?? false;
  bool get hasCardDav => _dualDiscovery?.hasCardDav ?? false;

  DiscoveryResult? get caldavDiscovery => _dualDiscovery?.caldav;
  CardDavDiscoveryResult? get carddavDiscovery => _dualDiscovery?.carddav;

  /// Low-level WebDAV client shared by both protocols.
  DioWebDavClient get webdavClient => _webdavClient;

  /// Generic WebDAV resource helper on the shared client.
  ResourceService resourceService({Uri? baseUri}) => ResourceService(
        _webdavClient,
        baseUri: baseUri ?? baseUrl,
      );

  /// Underlying Dio instance.
  Dio get dio => _dio;

  /// Close the shared HTTP client when this session owns it.
  void close() {
    if (_ownsDio) {
      _dio.close();
    }
  }
}
