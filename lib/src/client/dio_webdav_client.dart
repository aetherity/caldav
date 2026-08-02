import 'package:dio/dio.dart';

import '../webdav/dav_depth.dart';
import 'webdav_client.dart';

/// WebDAV client implementation using Dio.
///
/// Supports custom HTTP methods required by WebDAV, CalDAV, and CardDAV.
class DioWebDavClient implements WebDavClient {
  final Dio dio;

  DioWebDavClient(this.dio);

  @override
  Future<Response<String>> propfind(
    String path, {
    required String body,
    DavDepth depth = DavDepth.zero,
  }) async {
    return dio.request<String>(
      path,
      data: body,
      options: Options(
        method: 'PROPFIND',
        headers: {
          'Depth': depth.headerValue,
          'Content-Type': 'application/xml; charset=utf-8',
        },
        responseType: ResponseType.plain,
      ),
    );
  }

  @override
  Future<Response<String>> proppatch(
    String path, {
    required String body,
  }) async {
    return dio.request<String>(
      path,
      data: body,
      options: Options(
        method: 'PROPPATCH',
        headers: {
          'Content-Type': 'application/xml; charset=utf-8',
        },
        responseType: ResponseType.plain,
      ),
    );
  }

  @override
  Future<Response<String>> mkcol(
    String path, {
    String? body,
  }) async {
    return dio.request<String>(
      path,
      data: body,
      options: Options(
        method: 'MKCOL',
        headers: body != null
            ? {'Content-Type': 'application/xml; charset=utf-8'}
            : null,
        responseType: ResponseType.plain,
      ),
    );
  }

  @override
  Future<Response<String>> mkcalendar(
    String path, {
    String? body,
  }) async {
    return dio.request<String>(
      path,
      data: body,
      options: Options(
        method: 'MKCALENDAR',
        headers: body != null
            ? {'Content-Type': 'application/xml; charset=utf-8'}
            : null,
        responseType: ResponseType.plain,
      ),
    );
  }

  @override
  Future<Response<String>> report(
    String path, {
    required String body,
    DavDepth depth = DavDepth.one,
  }) async {
    return dio.request<String>(
      path,
      data: body,
      options: Options(
        method: 'REPORT',
        headers: {
          'Depth': depth.headerValue,
          'Content-Type': 'application/xml; charset=utf-8',
        },
        responseType: ResponseType.plain,
      ),
    );
  }

  @override
  Future<Response<String>> put(
    String path, {
    required String body,
    String contentType = 'application/octet-stream',
    String? ifMatch,
    String? ifNoneMatch,
    String? lockToken,
  }) async {
    final headers = <String, String>{
      'Content-Type': contentType,
    };
    if (ifMatch != null) headers['If-Match'] = ifMatch;
    if (ifNoneMatch != null) headers['If-None-Match'] = ifNoneMatch;
    _applyLockToken(headers, lockToken);

    return dio.request<String>(
      path,
      data: body,
      options: Options(
        method: 'PUT',
        headers: headers,
        responseType: ResponseType.plain,
      ),
    );
  }

  @override
  Future<Response<String>> delete(
    String path, {
    String? ifMatch,
    String? lockToken,
    DavDepth? depth,
  }) async {
    final headers = <String, String>{};
    if (ifMatch != null) headers['If-Match'] = ifMatch;
    if (depth != null) headers['Depth'] = depth.headerValue;
    _applyLockToken(headers, lockToken);

    return dio.request<String>(
      path,
      options: Options(
        method: 'DELETE',
        headers: headers.isNotEmpty ? headers : null,
        responseType: ResponseType.plain,
      ),
    );
  }

  @override
  Future<Response<String>> get(String path) async {
    return dio.get<String>(
      path,
      options: Options(responseType: ResponseType.plain),
    );
  }

  @override
  Future<Response<String>> post(
    String path, {
    required String body,
    String contentType = 'application/xml; charset=utf-8',
  }) async {
    return dio.request<String>(
      path,
      data: body,
      options: Options(
        method: 'POST',
        headers: {
          'Content-Type': contentType,
        },
        responseType: ResponseType.plain,
      ),
    );
  }

  @override
  Future<Response<String>> head(String path) async {
    return dio.request<String>(
      path,
      options: Options(
        method: 'HEAD',
        responseType: ResponseType.plain,
      ),
    );
  }

  @override
  Future<Response<String>> copy(
    String path, {
    required String destination,
    bool overwrite = true,
    DavDepth depth = DavDepth.infinity,
    String? ifMatch,
    String? lockToken,
  }) async {
    return dio.request<String>(
      path,
      options: Options(
        method: 'COPY',
        headers: _copyMoveHeaders(
          destination: destination,
          overwrite: overwrite,
          depth: depth,
          ifMatch: ifMatch,
          lockToken: lockToken,
        ),
        responseType: ResponseType.plain,
      ),
    );
  }

  @override
  Future<Response<String>> move(
    String path, {
    required String destination,
    bool overwrite = true,
    DavDepth depth = DavDepth.infinity,
    String? ifMatch,
    String? lockToken,
  }) async {
    return dio.request<String>(
      path,
      options: Options(
        method: 'MOVE',
        headers: _copyMoveHeaders(
          destination: destination,
          overwrite: overwrite,
          depth: depth,
          ifMatch: ifMatch,
          lockToken: lockToken,
        ),
        responseType: ResponseType.plain,
      ),
    );
  }

  @override
  Future<Response<String>> options(String path) async {
    return dio.request<String>(
      path,
      options: Options(
        method: 'OPTIONS',
        responseType: ResponseType.plain,
      ),
    );
  }

  Map<String, String> _copyMoveHeaders({
    required String destination,
    required bool overwrite,
    required DavDepth depth,
    String? ifMatch,
    String? lockToken,
  }) {
    final headers = <String, String>{
      'Destination': destination,
      'Overwrite': overwrite ? 'T' : 'F',
      'Depth': depth.headerValue,
    };
    if (ifMatch != null) headers['If-Match'] = ifMatch;
    _applyLockToken(headers, lockToken);
    return headers;
  }

  /// Attach a lock token using the RFC 4918 `If` header form
  /// `(<opaquelocktoken:...>)` when a bare token is provided.
  void _applyLockToken(Map<String, String> headers, String? lockToken) {
    if (lockToken == null || lockToken.isEmpty) return;
    final token = lockToken.startsWith('(') ? lockToken : '(<$lockToken>)';
    headers['If'] = token;
  }
}
