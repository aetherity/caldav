import 'package:dio/dio.dart';

import '../webdav/dav_depth.dart';

/// Abstract interface for WebDAV client operations (RFC 4918 + CalDAV extensions).
///
/// Implementations may be swapped for testing (mocks) or alternate HTTP stacks.
abstract class WebDavClient {
  /// PROPFIND — retrieve properties of a resource.
  ///
  /// [depth] defaults to [DavDepth.zero] (resource only).
  Future<Response<String>> propfind(
    String path, {
    required String body,
    DavDepth depth = DavDepth.zero,
  });

  /// PROPPATCH — create, modify, or remove properties on a resource.
  Future<Response<String>> proppatch(
    String path, {
    required String body,
  });

  /// MKCOL — create a new collection (RFC 4918 §9.3).
  ///
  /// [body] may contain an extended MKCOL property set (e.g. CardDAV addressbook).
  Future<Response<String>> mkcol(
    String path, {
    String? body,
  });

  /// MKCALENDAR — create a calendar collection (CalDAV RFC 4791).
  Future<Response<String>> mkcalendar(
    String path, {
    String? body,
  });

  /// REPORT — query resource data (CalDAV calendar-query, CardDAV, sync, etc.).
  Future<Response<String>> report(
    String path, {
    required String body,
    DavDepth depth = DavDepth.one,
  });

  /// PUT — create or update a resource body.
  ///
  /// Prefer an explicit [contentType]. The default is generic so WebDAV callers
  /// are not forced into `text/calendar`; CalDAV services should pass
  /// `text/calendar; charset=utf-8`.
  Future<Response<String>> put(
    String path, {
    required String body,
    String contentType = 'application/octet-stream',
    String? ifMatch,
    String? ifNoneMatch,
    String? lockToken,
  });

  /// DELETE — remove a resource.
  ///
  /// [depth] is honored by some servers for recursive collection delete.
  Future<Response<String>> delete(
    String path, {
    String? ifMatch,
    String? lockToken,
    DavDepth? depth,
  });

  /// GET — retrieve a resource body.
  Future<Response<String>> get(String path);

  /// POST — submit a request body (e.g. CalDAV scheduling Outbox).
  Future<Response<String>> post(
    String path, {
    required String body,
    String contentType = 'application/xml; charset=utf-8',
  });

  /// HEAD — retrieve response headers without a body.
  Future<Response<String>> head(String path);

  /// COPY — copy a resource to [destination] (RFC 4918 §9.8).
  ///
  /// [overwrite] maps to the `Overwrite` header (`T` / `F`). Default is true.
  Future<Response<String>> copy(
    String path, {
    required String destination,
    bool overwrite = true,
    DavDepth depth = DavDepth.infinity,
    String? ifMatch,
    String? lockToken,
  });

  /// MOVE — move or rename a resource to [destination] (RFC 4918 §9.9).
  Future<Response<String>> move(
    String path, {
    required String destination,
    bool overwrite = true,
    DavDepth depth = DavDepth.infinity,
    String? ifMatch,
    String? lockToken,
  });

  /// OPTIONS — discover server capabilities (`Allow`, `DAV`, etc.).
  Future<Response<String>> options(String path);
}
