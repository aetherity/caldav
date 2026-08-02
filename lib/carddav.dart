/// CardDAV client library (RFC 6352) built on the shared WebDAV foundation.
///
/// ```dart
/// import 'package:caldav/carddav.dart';
///
/// final client = await CardDavClient.connect(
///   baseUrl: 'https://carddav.example.com',
///   username: 'user@example.com',
///   password: 'password',
/// );
///
/// final books = await client.getAddressBooks();
/// final hits = await client.queryContacts(
///   books.first,
///   ContactFilter.anyText('jane'),
/// );
/// ```
library;

export 'src/carddav/carddav_client.dart' show CardDavClient;
export 'src/carddav/addressbook.dart' show AddressBook, AddressDataType;
export 'src/carddav/contact.dart'
    show Contact, VCardTypedValue, StructuredName, PostalAddress;
export 'src/carddav/contact_filter.dart'
    show ContactFilter, PropFilter, TextMatchType, FilterLogic;
export 'src/carddav/vcard_property.dart'
    show
        VCardPhoto,
        VCardImpp,
        VCardRelated,
        VCardGeo,
        VCardGender,
        VCardRawProperty;
export 'src/carddav/vcard_parser.dart' show VCardParser;
export 'src/carddav/contact_service.dart' show ContactService;
export 'src/dav_session.dart' show DavSession;
export 'src/discovery/discovery_result.dart' show CardDavDiscoveryResult;
export 'src/discovery/dual_discovery_result.dart' show DualDiscoveryResult;
export 'src/sync/contact_sync_result.dart' show ContactSyncResult;
export 'src/sync/sync_token_store.dart'
    show SyncTokenStore, SyncTokenKeys, MemorySyncTokenStore, JsonSyncTokenStore;
export 'src/sync/sync_token_cache.dart' show SyncTokenCache;
export 'src/webdav/sync_collection.dart'
    show
        SyncLevel,
        SyncChangeType,
        SyncChange,
        CollectionSyncResult,
        SyncCollectionBuilder;
export 'src/webdav/sync_service.dart' show SyncService;
export 'src/client/webdav_client.dart' show WebDavClient;
export 'src/client/dio_webdav_client.dart' show DioWebDavClient;
export 'src/webdav/dav_depth.dart' show DavDepth;
export 'src/webdav/xml_namespaces.dart' show XmlNamespaces;
export 'src/exceptions/caldav_exception.dart'
    show
        CalDavException,
        AuthenticationException,
        ForbiddenException,
        NotFoundException,
        ConflictException,
        DiscoveryException,
        ParseException,
        InvalidSyncTokenException;
