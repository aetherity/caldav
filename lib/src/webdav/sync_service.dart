import 'package:dio/dio.dart';

import '../exceptions/caldav_exception.dart';
import '../client/webdav_client.dart';
import 'dav_depth.dart';
import 'multistatus.dart';
import 'propfind_builder.dart';
import 'sync_collection.dart';
import 'xml_namespaces.dart';

/// Generic WebDAV collection synchronization (RFC 6578).
class SyncService {
  final WebDavClient _client;

  SyncService(this._client);

  /// Run a single `sync-collection` REPORT against [collectionUrl].
  ///
  /// Pass a previous token via [builder] (null/empty for the initial sync).
  /// When the result is [CollectionSyncResult.truncated], call again with the
  /// returned token, or use [syncCollectionFully].
  Future<CollectionSyncResult> syncCollection(
    Uri collectionUrl,
    SyncCollectionBuilder builder,
  ) async {
    try {
      final response = await _client.report(
        collectionUrl.toString(),
        body: builder.build(),
        depth: DavDepth.zero, // sync-level is carried in the body (RFC 6578)
      );

      final data = response.data ?? '';
      final status = response.statusCode;

      // When validateStatus accepts 4xx, map known failures here.
      if (status != null && status >= 400) {
        throw _mapStatus(status, data);
      }

      if (data.isEmpty) {
        throw const ParseException('Empty sync-collection response');
      }

      return parseSyncResponse(data, collectionUrl);
    } on DioException catch (e) {
      throw _mapException(e);
    }
  }

  /// Sync until the server reports no truncation, merging all pages.
  ///
  /// [rebuild] is called with the latest token for each page after the first
  /// (so limit/level/props stay consistent).
  Future<CollectionSyncResult> syncCollectionFully(
    Uri collectionUrl, {
    required SyncCollectionBuilder Function(String? syncToken) rebuild,
    int maxPages = 100,
  }) async {
    final allChanges = <SyncChange>[];
    String? token;
    var truncated = true;
    String? lastToken;
    String? description;

    for (var page = 0; page < maxPages && truncated; page++) {
      final result = await syncCollection(collectionUrl, rebuild(token));
      allChanges.addAll(result.changes);
      lastToken = result.syncToken;
      token = result.syncToken;
      truncated = result.truncated;
      description = result.responseDescription ?? description;
    }

    if (truncated) {
      throw CalDavException(
        'sync-collection still truncated after $maxPages pages',
      );
    }

    return CollectionSyncResult(
      syncToken: lastToken!,
      changes: allChanges,
      truncated: false,
      responseDescription: description,
    );
  }

  /// PROPFIND the collection for its current `DAV:sync-token` (if supported).
  ///
  /// Returns null when the server does not expose the property.
  Future<String?> getSyncToken(Uri collectionUrl) async {
    final body = PropfindBuilder().addDavProperty('sync-token').build();

    try {
      final response = await _client.propfind(
        collectionUrl.toString(),
        body: body,
        depth: DavDepth.zero,
      );
      final multi = MultiStatus.fromXml(response.data ?? '');
      final token = multi.first?.getProperty(
        'sync-token',
        namespace: XmlNamespaces.dav,
      );
      if (token == null || token.trim().isEmpty) return null;
      return token.trim();
    } on DioException catch (e) {
      // Some servers omit the property or return 404 for unknown live props.
      if (e.response?.statusCode == 404) return null;
      throw _mapException(e);
    }
  }

  /// Parse a multistatus body from a sync-collection REPORT.
  static CollectionSyncResult parseSyncResponse(
    String xml,
    Uri collectionUrl,
  ) {
    final multi = MultiStatus.fromXml(xml);

    final changes = <SyncChange>[];
    for (final response in multi.responses) {
      if (response.isTruncationMarker) continue;
      // Skip empty hrefs
      if (response.href.isEmpty) continue;

      // Collection itself sometimes appears; skip exact collection path matches
      // when there is no useful member data — still include if deleted/changed
      // with member-like path.
      final resolved = collectionUrl.resolve(response.href);
      if (_isSameCollection(collectionUrl, resolved)) {
        // Skip the collection resource itself when present.
        continue;
      }

      if (response.isDeleted) {
        changes.add(SyncChange(
          href: response.href,
          resolvedHref: resolved,
          type: SyncChangeType.deleted,
        ));
        continue;
      }

      if (!response.isSuccess) {
        // Other error statuses are ignored for member list.
        continue;
      }

      final etag = response.getProperty(
        'getetag',
        namespace: XmlNamespaces.dav,
      );
      final calendarData = response.getProperty(
        'calendar-data',
        namespace: XmlNamespaces.caldav,
      );
      final addressData = response.getProperty(
        'address-data',
        namespace: XmlNamespaces.carddav,
      );
      final contentType = response.getProperty(
        'getcontenttype',
        namespace: XmlNamespaces.dav,
      );

      final data = calendarData ?? addressData;
      String? dataType = contentType;
      if (dataType == null) {
        if (calendarData != null) dataType = 'text/calendar';
        if (addressData != null) dataType = 'text/vcard';
      }

      changes.add(SyncChange(
        href: response.href,
        resolvedHref: resolved,
        type: SyncChangeType.changed,
        etag: etag,
        data: data,
        contentType: dataType,
      ));
    }

    final token = multi.syncToken;
    if (token == null || token.isEmpty) {
      throw const ParseException(
        'sync-collection response missing DAV:sync-token',
      );
    }

    return CollectionSyncResult(
      syncToken: token,
      changes: changes,
      truncated: multi.isTruncated,
      responseDescription: multi.responseDescription,
    );
  }

  static bool _isSameCollection(Uri collection, Uri candidate) {
    String norm(Uri u) {
      var p = u.path;
      if (p.length > 1 && p.endsWith('/')) {
        p = p.substring(0, p.length - 1);
      }
      return p;
    }

    return norm(collection) == norm(candidate);
  }

  static CalDavException _mapException(DioException e) {
    final status = e.response?.statusCode;
    final body = e.response?.data?.toString() ?? '';
    return _mapStatus(status, body, fallbackMessage: e.message);
  }

  static CalDavException _mapStatus(
    int? status,
    String body, {
    String? fallbackMessage,
  }) {
    if (status == 403 && body.contains('valid-sync-token')) {
      return const InvalidSyncTokenException();
    }

    return switch (status) {
      401 => const AuthenticationException(),
      403 => const ForbiddenException(),
      404 => const NotFoundException(),
      409 || 412 => const ConflictException(),
      _ => CalDavException(
          'sync-collection failed: ${fallbackMessage ?? 'HTTP $status'}',
          statusCode: status,
          responseBody: body.isEmpty ? null : body,
        ),
    };
  }
}
