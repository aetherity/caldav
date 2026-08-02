import 'package:dio/dio.dart';

import '../client/dio_webdav_client.dart';
import '../client/interceptors/auth_interceptor.dart';
import '../discovery/discovery_result.dart';
import '../discovery/discovery_service.dart';
import '../exceptions/caldav_exception.dart';
import '../sync/contact_sync_result.dart';
import '../webdav/sync_collection.dart';
import 'addressbook.dart';
import 'addressbook_service.dart';
import 'contact.dart';
import 'contact_filter.dart';
import 'contact_service.dart';

/// CardDAV client for interacting with CardDAV servers (RFC 6352).
///
/// Example:
/// ```dart
/// final client = await CardDavClient.connect(
///   baseUrl: 'https://carddav.example.com',
///   username: 'user@example.com',
///   password: 'password',
/// );
///
/// try {
///   final books = await client.getAddressBooks();
///   for (final book in books) {
///     final contacts = await client.getContacts(book);
///     for (final c in contacts) {
///       print('${c.formattedName} <${c.primaryEmail}>');
///     }
///   }
/// } finally {
///   client.close();
/// }
/// ```
class CardDavClient {
  final Dio _dio;
  final DioWebDavClient _webdavClient;
  final DiscoveryService _discoveryService;
  final Uri _baseUrl;
  final bool _ownsDio;

  CardDavDiscoveryResult? _discoveryResult;
  AddressBookService? _addressBookService;
  ContactService? _contactService;

  CardDavClient._({
    required Dio dio,
    required DioWebDavClient webdavClient,
    required DiscoveryService discoveryService,
    required Uri baseUrl,
    bool ownsDio = true,
  })  : _dio = dio,
        _webdavClient = webdavClient,
        _discoveryService = discoveryService,
        _baseUrl = baseUrl,
        _ownsDio = ownsDio;

  /// Create a CardDAV client with Basic Authentication.
  factory CardDavClient({
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

    final webdavClient = DioWebDavClient(dio);
    final discoveryService = DiscoveryService(webdavClient, dio);

    return CardDavClient._(
      dio: dio,
      webdavClient: webdavClient,
      discoveryService: discoveryService,
      baseUrl: uri,
    );
  }

  /// Create a CardDAV client with Bearer Token Authentication (OAuth).
  factory CardDavClient.withToken({
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

    final webdavClient = DioWebDavClient(dio);
    final discoveryService = DiscoveryService(webdavClient, dio);

    return CardDavClient._(
      dio: dio,
      webdavClient: webdavClient,
      discoveryService: discoveryService,
      baseUrl: uri,
    );
  }

  /// Create a CardDAV client with a custom Dio instance.
  ///
  /// When [ownsDio] is false (default), [close] will not close [dio] so it can
  /// be shared (e.g. via [DavSession]).
  factory CardDavClient.withDio({
    required String baseUrl,
    required Dio dio,
    bool allowInsecure = false,
    bool ownsDio = false,
  }) {
    final uri = Uri.parse(baseUrl);
    _validateSecureConnection(uri, allowInsecure);
    final webdavClient = DioWebDavClient(dio);
    final discoveryService = DiscoveryService(webdavClient, dio);

    return CardDavClient._(
      dio: dio,
      webdavClient: webdavClient,
      discoveryService: discoveryService,
      baseUrl: uri,
      ownsDio: ownsDio,
    );
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

  /// Create, authenticate path, and discover CardDAV endpoints.
  static Future<CardDavClient> connect({
    required String baseUrl,
    required String username,
    required String password,
    Duration connectTimeout = const Duration(seconds: 30),
    Duration receiveTimeout = const Duration(seconds: 30),
    bool allowInsecure = false,
  }) async {
    final client = CardDavClient(
      baseUrl: baseUrl,
      username: username,
      password: password,
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
      allowInsecure: allowInsecure,
    );
    await client.discover();
    return client;
  }

  /// Discover CardDAV endpoints (well-known, principal, addressbook-home).
  Future<CardDavDiscoveryResult> discover() async {
    _discoveryResult ??= await _discoveryService.discoverCardDav(_baseUrl);
    return _discoveryResult!;
  }

  /// Seed discovery from a prior [CardDavDiscoveryResult] (e.g. [DavSession]).
  void seedDiscovery(CardDavDiscoveryResult result) {
    _discoveryResult = result;
    _addressBookService = null;
    _contactService = null;
  }

  /// Get the discovery result (null if not yet discovered).
  CardDavDiscoveryResult? get discoveryResult => _discoveryResult;

  /// Clear cached discovery and service instances.
  void clearDiscoveryCache() {
    _discoveryResult = null;
    _addressBookService = null;
    _contactService = null;
  }

  // ============================================================
  // Address books
  // ============================================================

  /// Get all address books for the current user.
  Future<List<AddressBook>> getAddressBooks() async {
    await _ensureDiscovered();
    return _addressBookService!.list();
  }

  /// Get a specific address book by URL.
  Future<AddressBook> getAddressBook(Uri addressBookUrl) async {
    await _ensureDiscovered();
    return _addressBookService!.get(addressBookUrl);
  }

  /// Create a new address book.
  Future<AddressBook> createAddressBook(
    String name, {
    String? description,
  }) async {
    await _ensureDiscovered();
    return _addressBookService!.create(name, description: description);
  }

  /// Update address book properties.
  ///
  /// Throws [ForbiddenException] if the address book is read-only.
  Future<void> updateAddressBook(
    AddressBook addressBook, {
    String? displayName,
    String? description,
  }) async {
    _ensureWritable(addressBook);
    await _ensureDiscovered();
    return _addressBookService!.update(
      addressBook,
      displayName: displayName,
      description: description,
    );
  }

  /// Delete an address book and all contacts inside.
  ///
  /// Throws [ForbiddenException] if the address book is read-only.
  Future<void> deleteAddressBook(AddressBook addressBook) async {
    _ensureWritable(addressBook);
    await _ensureDiscovered();
    return _addressBookService!.delete(addressBook);
  }

  // ============================================================
  // Contacts
  // ============================================================

  /// Get contacts from an address book.
  Future<List<Contact>> getContacts(AddressBook addressBook) async {
    await _ensureDiscovered();
    return _contactService!.list(addressBook);
  }

  /// Create a new contact.
  ///
  /// Throws [ForbiddenException] if the address book is read-only.
  Future<Contact> createContact(
    AddressBook addressBook,
    Contact contact,
  ) async {
    _ensureWritable(addressBook);
    await _ensureDiscovered();
    return _contactService!.create(addressBook, contact);
  }

  /// Update an existing contact.
  ///
  /// Throws [ConflictException] on ETag mismatch.
  /// Throws [ForbiddenException] if the contact is read-only.
  Future<Contact> updateContact(Contact contact) async {
    if (contact.isReadOnly) {
      throw const ForbiddenException('Cannot update a read-only contact');
    }
    await _ensureDiscovered();
    return _contactService!.update(contact);
  }

  /// Delete a contact.
  ///
  /// Throws [ConflictException] on ETag mismatch.
  /// Throws [ForbiddenException] if the contact is read-only.
  Future<void> deleteContact(Contact contact) async {
    if (contact.isReadOnly) {
      throw const ForbiddenException('Cannot delete a read-only contact');
    }
    await _ensureDiscovered();
    return _contactService!.delete(contact);
  }

  /// Batch-fetch contacts by URL.
  Future<List<Contact>> getContactsByUrls(
    AddressBook addressBook,
    List<Uri> contactUrls,
  ) async {
    await _ensureDiscovered();
    return _contactService!.multiGet(addressBook, contactUrls);
  }

  /// Find a contact by UID across all address books (parallel search).
  Future<Contact?> getContactByUid(String uid) async {
    await _ensureDiscovered();
    final books = await getAddressBooks();

    final futures = books.map((book) async {
      final contact = await _contactService!.findByUid(book, uid);
      return contact?.copyWith(addressBookId: book.uid);
    });

    final results = await Future.wait(futures);
    return results.firstWhere(
      (c) => c != null,
      orElse: () => null,
    );
  }

  /// Search contacts in an address book by a single property text match.
  ///
  /// Prefer [queryContacts] with [ContactFilter] for multi-property searches.
  Future<List<Contact>> searchContacts(
    AddressBook addressBook, {
    required String propertyName,
    required String text,
    bool matchAll = false,
  }) async {
    await _ensureDiscovered();
    return _contactService!.search(
      addressBook,
      propertyName: propertyName,
      text: text,
      matchAll: matchAll,
    );
  }

  /// Query contacts with a structured [ContactFilter].
  ///
  /// ```dart
  /// await client.queryContacts(book, ContactFilter.anyText('jane'));
  /// await client.queryContacts(book, ContactFilter.email('work@', types: ['WORK']));
  /// ```
  Future<List<Contact>> queryContacts(
    AddressBook addressBook,
    ContactFilter filter,
  ) async {
    await _ensureDiscovered();
    return _contactService!.query(addressBook, filter);
  }

  /// Get contacts from multiple address books in parallel.
  Future<Map<String, List<Contact>>> getContactsFromAddressBooks(
    List<AddressBook> addressBooks,
  ) async {
    await _ensureDiscovered();

    final futures = addressBooks.map((book) async {
      final contacts = await _contactService!.list(book);
      return MapEntry(book.uid, contacts);
    });

    final entries = await Future.wait(futures);
    return Map.fromEntries(entries);
  }

  /// Get all contacts from all address books in parallel.
  Future<List<Contact>> getAllContacts() async {
    await _ensureDiscovered();
    final books = await getAddressBooks();
    final map = await getContactsFromAddressBooks(books);
    return map.values.expand((c) => c).toList();
  }

  // ============================================================
  // Sync (RFC 6578)
  // ============================================================

  /// Synchronize an address book with `DAV:sync-collection`.
  ///
  /// ```dart
  /// var result = await client.syncAddressBook(book);
  /// // persist result.syncToken; apply result.contacts / result.deletedHrefs
  /// result = await client.syncAddressBook(book, syncToken: result.syncToken);
  /// ```
  ///
  /// Throws [InvalidSyncTokenException] if [syncToken] is no longer valid.
  Future<ContactSyncResult> syncAddressBook(
    AddressBook addressBook, {
    String? syncToken,
    int? limit,
    bool includeData = true,
    bool followTruncation = true,
    SyncLevel level = SyncLevel.members,
  }) async {
    await _ensureDiscovered();
    return _contactService!.sync(
      addressBook,
      syncToken: syncToken,
      limit: limit,
      includeData: includeData,
      followTruncation: followTruncation,
      level: level,
    );
  }

  /// Read an address book's current `DAV:sync-token` without listing members.
  Future<String?> getAddressBookSyncToken(AddressBook addressBook) async {
    await _ensureDiscovered();
    return _contactService!.getSyncToken(addressBook);
  }

  // ============================================================
  // Lifecycle
  // ============================================================

  /// Close the client and release resources.
  ///
  /// When constructed with [CardDavClient.withDio] and `ownsDio: false`
  /// (the default), the shared Dio instance is left open.
  void close() {
    if (_ownsDio) {
      _dio.close();
    }
  }

  /// Access the underlying Dio instance.
  Dio get dio => _dio;

  /// Access the WebDAV client for low-level operations.
  DioWebDavClient get webdavClient => _webdavClient;

  static void _ensureWritable(AddressBook addressBook) {
    if (addressBook.isReadOnly) {
      throw const ForbiddenException('Cannot modify a read-only address book');
    }
  }

  Future<void> _ensureDiscovered() async {
    if (_discoveryResult == null) {
      await discover();
    }
    _addressBookService ??= AddressBookService(
      _webdavClient,
      _discoveryResult!.addressbookHomeSet,
    );
    _contactService ??= ContactService(_webdavClient);
  }
}
