import '../calendar/calendar.dart';
import '../caldav_client.dart';
import '../carddav/addressbook.dart';
import '../carddav/carddav_client.dart';
import '../exceptions/caldav_exception.dart';
import '../webdav/sync_collection.dart';
import 'calendar_sync_result.dart';
import 'contact_sync_result.dart';
import 'sync_token_store.dart';

/// Loads and saves RFC 6578 sync tokens around client sync calls.
///
/// Handles [InvalidSyncTokenException] by clearing the stored token and
/// performing a full re-sync automatically.
///
/// ```dart
/// final cache = SyncTokenCache(JsonSyncTokenStore(
///   onChange: (json) => prefs.setString('dav_sync_tokens', json),
/// ));
///
/// final result = await cache.syncCalendar(client, calendar);
/// // result.syncToken is already persisted in the store
/// ```
class SyncTokenCache {
  /// Backing token persistence.
  final SyncTokenStore store;

  /// Optional key transform; defaults to [SyncTokenKeys.forHref].
  final String Function(Uri collectionHref) keyFor;

  SyncTokenCache(
    this.store, {
    String Function(Uri collectionHref)? keyFor,
  }) : keyFor = keyFor ?? SyncTokenKeys.forHref;

  /// Read the stored token for [collectionHref], if any.
  Future<String?> getToken(Uri collectionHref) =>
      store.getToken(keyFor(collectionHref));

  /// Persist [token] for [collectionHref].
  Future<void> setToken(Uri collectionHref, String token) =>
      store.setToken(keyFor(collectionHref), token);

  /// Drop the stored token for [collectionHref].
  Future<void> removeToken(Uri collectionHref) =>
      store.removeToken(keyFor(collectionHref));

  /// Drop all stored tokens.
  Future<void> clear() => store.clear();

  /// Sync a calendar, using and updating the stored token.
  ///
  /// On [InvalidSyncTokenException], clears the token and retries once with a
  /// full sync (`syncToken: null`).
  Future<CalendarSyncResult> syncCalendar(
    CalDavClient client,
    Calendar calendar, {
    int? limit,
    bool includeData = true,
    bool followTruncation = true,
    SyncLevel level = SyncLevel.members,
  }) async {
    final key = keyFor(calendar.href);
    final stored = await store.getToken(key);

    try {
      final result = await client.syncCalendar(
        calendar,
        syncToken: stored,
        limit: limit,
        includeData: includeData,
        followTruncation: followTruncation,
        level: level,
      );
      await store.setToken(key, result.syncToken);
      return result;
    } on InvalidSyncTokenException {
      await store.removeToken(key);
      final result = await client.syncCalendar(
        calendar,
        syncToken: null,
        limit: limit,
        includeData: includeData,
        followTruncation: followTruncation,
        level: level,
      );
      await store.setToken(key, result.syncToken);
      return result;
    }
  }

  /// Sync an address book, using and updating the stored token.
  ///
  /// On [InvalidSyncTokenException], clears the token and retries once with a
  /// full sync (`syncToken: null`).
  Future<ContactSyncResult> syncAddressBook(
    CardDavClient client,
    AddressBook addressBook, {
    int? limit,
    bool includeData = true,
    bool followTruncation = true,
    SyncLevel level = SyncLevel.members,
  }) async {
    final key = keyFor(addressBook.href);
    final stored = await store.getToken(key);

    try {
      final result = await client.syncAddressBook(
        addressBook,
        syncToken: stored,
        limit: limit,
        includeData: includeData,
        followTruncation: followTruncation,
        level: level,
      );
      await store.setToken(key, result.syncToken);
      return result;
    } on InvalidSyncTokenException {
      await store.removeToken(key);
      final result = await client.syncAddressBook(
        addressBook,
        syncToken: null,
        limit: limit,
        includeData: includeData,
        followTruncation: followTruncation,
        level: level,
      );
      await store.setToken(key, result.syncToken);
      return result;
    }
  }
}
