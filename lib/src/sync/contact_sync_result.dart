import '../carddav/contact.dart';
import '../webdav/sync_collection.dart';

/// Result of syncing a CardDAV address book (RFC 6578).
class ContactSyncResult {
  /// Opaque token for the next incremental sync.
  final String syncToken;

  /// Contacts created or updated since the previous token.
  final List<Contact> contacts;

  /// Member hrefs that were deleted.
  final List<Uri> deletedHrefs;

  /// Raw member changes (includes etag-only rows when data was not returned).
  final List<SyncChange> rawChanges;

  /// True when more pages are available (only if followTruncation was false).
  final bool truncated;

  const ContactSyncResult({
    required this.syncToken,
    this.contacts = const [],
    this.deletedHrefs = const [],
    this.rawChanges = const [],
    this.truncated = false,
  });

  List<Uri> get changedHrefs => rawChanges
      .where((c) => c.isChanged)
      .map((c) => c.resolvedHref)
      .toList(growable: false);

  List<SyncChange> get pendingDataFetches => rawChanges
      .where((c) => c.isChanged && (c.data == null || c.data!.isEmpty))
      .toList(growable: false);

  @override
  String toString() =>
      'ContactSyncResult(contacts: ${contacts.length}, '
      'deleted: ${deletedHrefs.length}, truncated: $truncated)';
}
