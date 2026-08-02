import '../utils/icalendar_utils.dart';
import 'xml_namespaces.dart';

/// Depth of a collection sync (RFC 6578 `sync-level`).
enum SyncLevel {
  /// Immediate children only (`1`).
  members,

  /// Entire subtree (`infinite`).
  infinite;

  String get xmlValue => switch (this) {
        SyncLevel.members => '1',
        SyncLevel.infinite => 'infinite',
      };
}

/// Kind of change reported by a sync-collection REPORT.
enum SyncChangeType {
  /// Resource was created or modified (successful propstat).
  changed,

  /// Resource was deleted (typically response-level 404).
  deleted,
}

/// A single member change from a sync-collection response.
class SyncChange {
  /// Member href as returned by the server (may be relative).
  final String href;

  /// Absolute href when resolved against the collection base.
  final Uri resolvedHref;

  /// Change classification.
  final SyncChangeType type;

  /// Entity tag when present (changed members only).
  final String? etag;

  /// Raw calendar-data / address-data body when requested and returned.
  final String? data;

  /// Content type of [data] when known (`text/calendar`, `text/vcard`, …).
  final String? contentType;

  const SyncChange({
    required this.href,
    required this.resolvedHref,
    required this.type,
    this.etag,
    this.data,
    this.contentType,
  });

  bool get isDeleted => type == SyncChangeType.deleted;
  bool get isChanged => type == SyncChangeType.changed;

  @override
  String toString() => 'SyncChange($type, $href)';
}

/// Result of a generic WebDAV collection sync (RFC 6578).
class CollectionSyncResult {
  /// Opaque token to pass to the next sync request.
  final String syncToken;

  /// Member changes since the previous token (or full set on initial sync).
  final List<SyncChange> changes;

  /// True when the server truncated results (`number-of-matches-within-limits`).
  ///
  /// Client should repeat the REPORT with the returned [syncToken] until
  /// [truncated] is false.
  final bool truncated;

  /// Optional server description.
  final String? responseDescription;

  const CollectionSyncResult({
    required this.syncToken,
    required this.changes,
    this.truncated = false,
    this.responseDescription,
  });

  List<SyncChange> get changed =>
      changes.where((c) => c.isChanged).toList(growable: false);

  List<SyncChange> get deleted =>
      changes.where((c) => c.isDeleted).toList(growable: false);

  List<Uri> get deletedHrefs =>
      deleted.map((c) => c.resolvedHref).toList(growable: false);

  @override
  String toString() =>
      'CollectionSyncResult(token: $syncToken, changes: ${changes.length}, '
      'truncated: $truncated)';
}

/// Builder for `DAV:sync-collection` REPORT bodies (RFC 6578).
class SyncCollectionBuilder {
  /// Previous sync token; empty/null starts an initial sync.
  final String? syncToken;

  /// Sync depth.
  final SyncLevel level;

  /// Optional result limit (`DAV:nresults`).
  final int? limit;

  /// Fully-formed property elements inside `<D:prop>`, e.g.
  /// `['<D:getetag/>', '<C:calendar-data xmlns:C="..."/>']`.
  final List<String> propElements;

  /// Extra namespace declarations on the root element (`prefix` → uri).
  final Map<String, String> extraNamespaces;

  const SyncCollectionBuilder({
    this.syncToken,
    this.level = SyncLevel.members,
    this.limit,
    this.propElements = const ['<D:getetag/>'],
    this.extraNamespaces = const {},
  });

  /// Calendar member sync requesting etag + calendar-data.
  factory SyncCollectionBuilder.calendar({
    String? syncToken,
    SyncLevel level = SyncLevel.members,
    int? limit,
    bool includeData = true,
  }) {
    final props = <String>['<D:getetag/>'];
    if (includeData) {
      props.add(
        '<C:calendar-data xmlns:C="${XmlNamespaces.caldav}"/>',
      );
    }
    return SyncCollectionBuilder(
      syncToken: syncToken,
      level: level,
      limit: limit,
      propElements: props,
      extraNamespaces: const {'C': XmlNamespaces.caldav},
    );
  }

  /// Address book member sync requesting etag + address-data.
  factory SyncCollectionBuilder.addressbook({
    String? syncToken,
    SyncLevel level = SyncLevel.members,
    int? limit,
    bool includeData = true,
  }) {
    final props = <String>['<D:getetag/>'];
    if (includeData) {
      props.add(
        '<C:address-data xmlns:C="${XmlNamespaces.carddav}"/>',
      );
    }
    return SyncCollectionBuilder(
      syncToken: syncToken,
      level: level,
      limit: limit,
      propElements: props,
      extraNamespaces: const {'C': XmlNamespaces.carddav},
    );
  }

  /// Metadata-only sync (etag + content type).
  factory SyncCollectionBuilder.metadata({
    String? syncToken,
    SyncLevel level = SyncLevel.members,
    int? limit,
  }) {
    return SyncCollectionBuilder(
      syncToken: syncToken,
      level: level,
      limit: limit,
      propElements: const [
        '<D:getetag/>',
        '<D:getcontenttype/>',
      ],
    );
  }

  String build() {
    final ns = StringBuffer('xmlns:D="${XmlNamespaces.dav}"');
    extraNamespaces.forEach((prefix, uri) {
      ns.write(' xmlns:$prefix="$uri"');
    });

    final tokenXml = (syncToken == null || syncToken!.isEmpty)
        ? '  <D:sync-token/>'
        : '  <D:sync-token>${ICalendarUtils.escapeXml(syncToken!)}</D:sync-token>';

    final props = propElements.map((p) => '    $p').join('\n');

    final limitXml = limit != null
        ? '  <D:limit>\n    <D:nresults>$limit</D:nresults>\n  </D:limit>\n'
        : '';

    return '''<?xml version="1.0" encoding="utf-8"?>
<D:sync-collection $ns>
$tokenXml
  <D:sync-level>${level.xmlValue}</D:sync-level>
  <D:prop>
$props
  </D:prop>
$limitXml</D:sync-collection>''';
  }
}
