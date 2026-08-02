import 'package:dio/dio.dart';
import 'package:xml/xml.dart';

import '../client/webdav_client.dart';
import '../exceptions/caldav_exception.dart';
import 'dav_depth.dart';
import 'dav_resource.dart';
import 'multistatus.dart';
import 'propfind_builder.dart';
import 'proppatch_builder.dart';
import 'xml_namespaces.dart';

/// High-level operations on generic WebDAV resources (RFC 4918).
///
/// CalDAV and CardDAV services can reuse this for listing, property updates,
/// collection creation, copy/move, and simple body GET/PUT.
class ResourceService {
  final WebDavClient _client;

  /// Optional base URI used to resolve relative hrefs from multistatus.
  final Uri? baseUri;

  ResourceService(this._client, {this.baseUri});

  /// List resources under [path] with the given [depth].
  ///
  /// By default uses [PropfindBuilder.resourceProperties]. Pass [propfindBody]
  /// to request a custom property set.
  Future<List<DavResource>> list(
    String path, {
    DavDepth depth = DavDepth.one,
    String? propfindBody,
  }) async {
    final body = propfindBody ?? PropfindBuilder.resourceProperties();

    try {
      final response = await _client.propfind(
        path,
        body: body,
        depth: depth,
      );

      final data = response.data;
      if (data == null || data.isEmpty) return [];

      final multiStatus = MultiStatus.fromXml(data);
      final resolveBase = baseUri ?? Uri.parse(path);

      return multiStatus.responses
          .map((r) => _parseResource(r, resolveBase))
          .toList();
    } on DioException catch (e) {
      throw _mapException(e, 'Failed to list resources');
    } on XmlException catch (e) {
      throw ParseException('Failed to parse resource list: $e');
    }
  }

  /// Fetch properties for a single resource ([DavDepth.zero]).
  Future<DavResource> getProperties(
    String path, {
    String? propfindBody,
  }) async {
    final resources = await list(
      path,
      depth: DavDepth.zero,
      propfindBody: propfindBody,
    );
    if (resources.isEmpty) {
      throw const NotFoundException('Resource not found');
    }
    return resources.first;
  }

  /// Apply a PROPPATCH built by [builder].
  Future<MultiStatus> updateProperties(
    String path,
    ProppatchBuilder builder,
  ) async {
    try {
      final response = await _client.proppatch(
        path,
        body: builder.build(),
      );
      final data = response.data ?? '';
      if (data.isEmpty) {
        return const MultiStatus([]);
      }
      return MultiStatus.fromXml(data);
    } on DioException catch (e) {
      throw _mapException(e, 'Failed to update properties');
    } on XmlException catch (e) {
      throw ParseException('Failed to parse proppatch response: $e');
    }
  }

  /// Create a collection with MKCOL.
  ///
  /// [body] may be an extended MKCOL document (e.g. CardDAV address book).
  Future<void> createCollection(String path, {String? body}) async {
    try {
      await _client.mkcol(path, body: body);
    } on DioException catch (e) {
      if (e.response?.statusCode == 405) {
        throw const CalDavException(
          'Collection already exists or MKCOL not allowed',
          statusCode: 405,
        );
      }
      throw _mapException(e, 'Failed to create collection');
    }
  }

  /// Delete a resource.
  Future<void> delete(
    String path, {
    String? ifMatch,
    String? lockToken,
    DavDepth? depth,
  }) async {
    try {
      await _client.delete(
        path,
        ifMatch: ifMatch,
        lockToken: lockToken,
        depth: depth,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return;
      }
      throw _mapException(e, 'Failed to delete resource');
    }
  }

  /// Copy a resource to [destination].
  Future<void> copy(
    String path, {
    required String destination,
    bool overwrite = true,
    DavDepth depth = DavDepth.infinity,
    String? ifMatch,
    String? lockToken,
  }) async {
    try {
      await _client.copy(
        path,
        destination: destination,
        overwrite: overwrite,
        depth: depth,
        ifMatch: ifMatch,
        lockToken: lockToken,
      );
    } on DioException catch (e) {
      throw _mapException(e, 'Failed to copy resource');
    }
  }

  /// Move (or rename) a resource to [destination].
  Future<void> move(
    String path, {
    required String destination,
    bool overwrite = true,
    DavDepth depth = DavDepth.infinity,
    String? ifMatch,
    String? lockToken,
  }) async {
    try {
      await _client.move(
        path,
        destination: destination,
        overwrite: overwrite,
        depth: depth,
        ifMatch: ifMatch,
        lockToken: lockToken,
      );
    } on DioException catch (e) {
      throw _mapException(e, 'Failed to move resource');
    }
  }

  /// GET the raw body of a resource.
  Future<String> get(String path) async {
    try {
      final response = await _client.get(path);
      return response.data ?? '';
    } on DioException catch (e) {
      throw _mapException(e, 'Failed to get resource');
    }
  }

  /// PUT a resource body.
  Future<String?> put(
    String path, {
    required String body,
    String contentType = 'application/octet-stream',
    String? ifMatch,
    String? ifNoneMatch,
    String? lockToken,
  }) async {
    try {
      final response = await _client.put(
        path,
        body: body,
        contentType: contentType,
        ifMatch: ifMatch,
        ifNoneMatch: ifNoneMatch,
        lockToken: lockToken,
      );
      return response.headers.value('etag');
    } on DioException catch (e) {
      if (e.response?.statusCode == 412) {
        throw const ConflictException('Precondition failed (If-Match/If-None-Match)');
      }
      throw _mapException(e, 'Failed to put resource');
    }
  }

  /// HEAD a resource; returns response headers of interest.
  Future<Map<String, String>> head(String path) async {
    try {
      final response = await _client.head(path);
      final result = <String, String>{};
      response.headers.forEach((name, values) {
        if (values.isNotEmpty) {
          result[name.toLowerCase()] = values.first;
        }
      });
      return result;
    } on DioException catch (e) {
      throw _mapException(e, 'Failed to HEAD resource');
    }
  }

  /// OPTIONS a resource; returns parsed `Allow` and `DAV` capability hints.
  Future<DavCapabilities> options(String path) async {
    try {
      final response = await _client.options(path);
      final allowHeader = response.headers.value('allow') ?? '';
      final davHeader = response.headers.value('dav') ?? '';

      final allow = allowHeader
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toSet();

      final dav = davHeader
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toSet();

      return DavCapabilities(allow: allow, dav: dav);
    } on DioException catch (e) {
      throw _mapException(e, 'Failed to OPTIONS resource');
    }
  }

  DavResource _parseResource(DavResponse response, Uri resolveBase) {
    final displayName = response.getProperty(
      'displayname',
      namespace: XmlNamespaces.dav,
    );
    final etag = response.getProperty(
      'getetag',
      namespace: XmlNamespaces.dav,
    );
    final contentType = response.getProperty(
      'getcontenttype',
      namespace: XmlNamespaces.dav,
    );
    final contentLengthStr = response.getProperty(
      'getcontentlength',
      namespace: XmlNamespaces.dav,
    );
    final lastModifiedStr = response.getProperty(
      'getlastmodified',
      namespace: XmlNamespaces.dav,
    );
    final creationDateStr = response.getProperty(
      'creationdate',
      namespace: XmlNamespaces.dav,
    );

    final resourceTypeElement = response.getPropertyElement(
      'resourcetype',
      namespace: XmlNamespaces.dav,
    );
    final resourceTypes = resourceTypeElement?.childElements
            .map((e) => e.localName)
            .toList() ??
        const <String>[];

    return DavResource(
      href: resolveBase.resolve(response.href),
      displayName: displayName,
      etag: etag,
      contentType: contentType,
      contentLength: int.tryParse(contentLengthStr ?? ''),
      lastModified: _parseHttpDate(lastModifiedStr),
      creationDate: DateTime.tryParse(creationDateStr ?? ''),
      isCollection: response.isCollection,
      isCalendar: response.isCalendar,
      isAddressBook: response.isAddressBook,
      isReadOnly: _parseIsReadOnly(response),
      resourceTypes: resourceTypes,
    );
  }

  /// Same privilege heuristic as [CalendarService]: missing privilege-set means writable.
  bool _parseIsReadOnly(DavResponse response) {
    final privilegeSetElement = response.getPropertyElement(
      'current-user-privilege-set',
      namespace: XmlNamespaces.dav,
    );
    if (privilegeSetElement == null) return false;

    const writePrivileges = {'write', 'write-content', 'bind', 'unbind', 'all'};

    for (final privilegeElement in privilegeSetElement.childElements) {
      if (privilegeElement.localName != 'privilege' ||
          privilegeElement.namespaceUri != XmlNamespaces.dav) {
        continue;
      }
      for (final privilege in privilegeElement.childElements) {
        if (privilege.namespaceUri == XmlNamespaces.dav &&
            writePrivileges.contains(privilege.localName)) {
          return false;
        }
      }
    }
    return true;
  }

  static DateTime? _parseHttpDate(String? value) {
    if (value == null || value.isEmpty) return null;
    // RFC 1123 / HTTP-date — Dart's HttpDate is not available in pure Dart VM
    // packages without dart:io in all targets; try common forms.
    final iso = DateTime.tryParse(value);
    if (iso != null) return iso;

    // e.g. Mon, 15 Jan 2024 10:00:00 GMT
    try {
      // Use a minimal regex for HTTP-date without importing dart:io.
      final match = RegExp(
        r'\d{1,2}\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d{4}\s+\d{2}:\d{2}:\d{2}',
        caseSensitive: false,
      ).firstMatch(value);
      if (match == null) return null;

      const months = {
        'jan': 1,
        'feb': 2,
        'mar': 3,
        'apr': 4,
        'may': 5,
        'jun': 6,
        'jul': 7,
        'aug': 8,
        'sep': 9,
        'oct': 10,
        'nov': 11,
        'dec': 12,
      };
      final parts = match.group(0)!.split(RegExp(r'\s+'));
      // day mon year time
      final day = int.parse(parts[0]);
      final month = months[parts[1].toLowerCase()]!;
      final year = int.parse(parts[2]);
      final time = parts[3].split(':');
      return DateTime.utc(
        year,
        month,
        day,
        int.parse(time[0]),
        int.parse(time[1]),
        int.parse(time[2]),
      );
    } catch (_) {
      return null;
    }
  }

  static CalDavException _mapException(DioException e, String context) {
    return switch (e.response?.statusCode) {
      401 => const AuthenticationException(),
      403 => const ForbiddenException(),
      404 => const NotFoundException(),
      409 || 412 => ConflictException(
          e.response?.statusCode == 412
              ? 'Precondition failed'
              : 'Resource conflict',
        ),
      _ => CalDavException(
          '$context: ${e.message}',
          statusCode: e.response?.statusCode,
        ),
    };
  }
}

/// Capability hints from an OPTIONS response.
class DavCapabilities {
  /// Methods listed in the `Allow` header.
  final Set<String> allow;

  /// Compliance classes from the `DAV` header (e.g. `1`, `2`, `3`,
  /// `calendar-access`, `addressbook`).
  final Set<String> dav;

  const DavCapabilities({
    this.allow = const {},
    this.dav = const {},
  });

  bool get supportsClass1 => dav.contains('1');
  bool get supportsClass2 => dav.contains('2');
  bool get supportsClass3 => dav.contains('3');
  bool get supportsCalDav => dav.contains('calendar-access');
  bool get supportsCardDav => dav.contains('addressbook');

  bool allows(String method) =>
      allow.map((m) => m.toUpperCase()).contains(method.toUpperCase());
}
