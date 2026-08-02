/// A Dart client library for CalDAV, CardDAV, and WebDAV.
///
/// ## CalDAV
///
/// ```dart
/// import 'package:caldav/caldav.dart';
///
/// final client = await CalDavClient.connect(
///   baseUrl: 'https://caldav.example.com',
///   username: 'user@example.com',
///   password: 'password',
/// );
/// ```
///
/// ## CardDAV
///
/// ```dart
/// final card = await CardDavClient.connect(
///   baseUrl: 'https://carddav.example.com',
///   username: 'user@example.com',
///   password: 'password',
/// );
/// ```
///
/// ## Shared session (both protocols)
///
/// ```dart
/// final session = await DavSession.connect(
///   baseUrl: 'https://dav.example.com',
///   username: 'user',
///   password: 'pass',
/// );
/// final calendars = await session.caldav.getCalendars();
/// final books = await session.carddav.getAddressBooks();
/// ```
library;

// Main clients
export 'src/caldav_client.dart' show CalDavClient;
export 'src/carddav/carddav_client.dart' show CardDavClient;
export 'src/dav_session.dart' show DavSession;
// Client interfaces
export 'src/client/webdav_client.dart' show WebDavClient;
export 'src/client/dio_webdav_client.dart' show DioWebDavClient;
// Models
export 'src/calendar/calendar.dart' show Calendar;
export 'src/discovery/discovery_result.dart'
    show DiscoveryResult, CardDavDiscoveryResult;
export 'src/discovery/dual_discovery_result.dart' show DualDiscoveryResult;
export 'src/event/event.dart' show CalendarEvent;
export 'src/event/calendar_component.dart' show CalendarComponent;
export 'src/event/todo.dart' show CalendarTodo, TodoStatus;
export 'src/event/journal.dart' show CalendarJournal, JournalStatus;
// Free/busy
export 'src/freebusy/free_busy.dart'
    show FreeBusy, FreeBusyPeriod, FreeBusyType;
export 'src/freebusy/free_busy_parser.dart' show FreeBusyParser;
// CardDAV models
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
// Sync (RFC 6578)
export 'src/sync/calendar_sync_result.dart' show CalendarSyncResult;
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
// WebDAV foundation (RFC 4918)
export 'src/webdav/dav_depth.dart' show DavDepth;
export 'src/webdav/dav_resource.dart' show DavResource;
export 'src/webdav/resource_service.dart' show ResourceService, DavCapabilities;
export 'src/webdav/propfind_builder.dart' show PropfindBuilder;
export 'src/webdav/proppatch_builder.dart' show ProppatchBuilder;
export 'src/webdav/multistatus.dart' show MultiStatus, DavResponse, PropStat;
export 'src/webdav/xml_namespaces.dart' show XmlNamespaces;
// Exceptions
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
