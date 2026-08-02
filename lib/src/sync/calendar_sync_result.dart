import '../event/event.dart';
import '../event/journal.dart';
import '../event/todo.dart';
import '../webdav/sync_collection.dart';

/// Result of syncing a CalDAV calendar collection (RFC 6578).
class CalendarSyncResult {
  /// Opaque token for the next incremental sync.
  final String syncToken;

  /// Events created or updated since the previous token.
  final List<CalendarEvent> events;

  /// Todos created or updated since the previous token.
  final List<CalendarTodo> todos;

  /// Journal entries created or updated since the previous token.
  final List<CalendarJournal> journals;

  /// Member hrefs that were deleted.
  final List<Uri> deletedHrefs;

  /// Raw member changes (includes etag-only rows when data was not returned).
  final List<SyncChange> rawChanges;

  /// True when more pages are available (only if followTruncation was false).
  final bool truncated;

  const CalendarSyncResult({
    required this.syncToken,
    this.events = const [],
    this.todos = const [],
    this.journals = const [],
    this.deletedHrefs = const [],
    this.rawChanges = const [],
    this.truncated = false,
  });

  /// Hrefs of changed events/todos/journals (not deletions).
  List<Uri> get changedHrefs => rawChanges
      .where((c) => c.isChanged)
      .map((c) => c.resolvedHref)
      .toList(growable: false);

  /// Changes that included no calendar-data (caller may multiget).
  List<SyncChange> get pendingDataFetches => rawChanges
      .where((c) => c.isChanged && (c.data == null || c.data!.isEmpty))
      .toList(growable: false);

  @override
  String toString() =>
      'CalendarSyncResult(events: ${events.length}, todos: ${todos.length}, '
      'journals: ${journals.length}, deleted: ${deletedHrefs.length}, '
      'truncated: $truncated)';
}
