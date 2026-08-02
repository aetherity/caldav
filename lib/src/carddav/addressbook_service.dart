import 'package:dio/dio.dart';

import '../client/webdav_client.dart';
import '../exceptions/caldav_exception.dart';
import '../webdav/dav_depth.dart';
import '../webdav/multistatus.dart';
import '../webdav/propfind_builder.dart';
import '../webdav/xml_namespaces.dart';
import 'addressbook.dart';
import 'vcard_utils.dart';

/// Service for CardDAV address book collection CRUD (RFC 6352).
class AddressBookService {
  final WebDavClient _client;
  final Uri _addressbookHome;

  AddressBookService(this._client, this._addressbookHome);

  /// List all address books in the addressbook home.
  Future<List<AddressBook>> list() async {
    final body = PropfindBuilder.addressbookProperties();

    try {
      final response = await _client.propfind(
        _addressbookHome.toString(),
        body: body,
        depth: DavDepth.one,
      );

      final responseData = response.data;
      if (responseData == null || responseData.isEmpty) {
        return [];
      }

      final multiStatus = MultiStatus.fromXml(responseData);

      return multiStatus.responses
          .where((r) => r.isAddressBook && r.href != _addressbookHome.path)
          .map(_parseAddressBook)
          .toList();
    } on DioException catch (e) {
      throw _mapException(e, 'Failed to list address books');
    } on Exception catch (e) {
      throw CalDavException('Failed to parse address book list: $e');
    }
  }

  /// Get a specific address book by URL.
  Future<AddressBook> get(Uri addressBookUrl) async {
    final body = PropfindBuilder.addressbookProperties();

    try {
      final response = await _client.propfind(
        addressBookUrl.toString(),
        body: body,
        depth: DavDepth.zero,
      );

      final multiStatus = MultiStatus.fromXml(response.data ?? '');
      final davResponse = multiStatus.first;

      if (davResponse == null || !davResponse.isAddressBook) {
        throw const NotFoundException('Address book not found');
      }

      return _parseAddressBook(davResponse);
    } on DioException catch (e) {
      throw _mapException(e, 'Failed to get address book');
    }
  }

  /// Create a new address book collection via extended MKCOL.
  Future<AddressBook> create(
    String name, {
    String? description,
  }) async {
    final path = _addressbookHome.resolve('${_sanitizeName(name)}/');
    final body = _buildMkcolBody(name: name, description: description);

    try {
      await _client.mkcol(path.toString(), body: body);
      return await get(path);
    } on DioException catch (e) {
      if (e.response?.statusCode == 405) {
        throw const CalDavException(
          'Address book already exists or creation not allowed',
          statusCode: 405,
        );
      }
      throw _mapException(e, 'Failed to create address book');
    }
  }

  /// Update address book properties.
  Future<void> update(
    AddressBook addressBook, {
    String? displayName,
    String? description,
  }) async {
    final body = _buildProppatchBody(
      displayName: displayName,
      description: description,
    );

    try {
      await _client.proppatch(addressBook.href.toString(), body: body);
    } on DioException catch (e) {
      throw _mapException(e, 'Failed to update address book');
    }
  }

  /// Delete an address book (and all contacts inside).
  Future<void> delete(AddressBook addressBook) async {
    try {
      await _client.delete(addressBook.href.toString());
    } on DioException catch (e) {
      throw _mapException(e, 'Failed to delete address book');
    }
  }

  AddressBook _parseAddressBook(DavResponse response) {
    final displayName = response.getProperty(
          'displayname',
          namespace: XmlNamespaces.dav,
        ) ??
        'Untitled';

    final description = response.getProperty(
      'addressbook-description',
      namespace: XmlNamespaces.carddav,
    );

    final ctag = response.getProperty(
      'getctag',
      namespace: XmlNamespaces.calendarServer,
    );

    final syncToken = response.getProperty(
      'sync-token',
      namespace: XmlNamespaces.dav,
    );

    final supported = _parseSupportedAddressData(response);
    final isReadOnly = _parseIsReadOnly(response);

    final href = _addressbookHome.resolve(response.href);

    return AddressBook(
      uid: response.href,
      href: href,
      displayName: displayName,
      description: description,
      ctag: ctag,
      syncToken: syncToken,
      supportedAddressData: supported,
      isReadOnly: isReadOnly,
    );
  }

  List<AddressDataType> _parseSupportedAddressData(DavResponse response) {
    final element = response.getPropertyElement(
      'supported-address-data',
      namespace: XmlNamespaces.carddav,
    );
    if (element == null) return const [];

    final result = <AddressDataType>[];
    for (final child in element.childElements) {
      if (child.localName != 'address-data-type' &&
          child.localName != 'address-data') {
        // Some servers nest <C:address-data content-type="..." version="..."/>
        continue;
      }
      final contentType = child.getAttribute('content-type') ??
          child.getAttribute('contenttype') ??
          'text/vcard';
      final version = child.getAttribute('version');
      result.add(AddressDataType(contentType: contentType, version: version));
    }

    // Also accept bare address-data-type-like children named differently
    if (result.isEmpty) {
      for (final child in element.childElements) {
        final contentType = child.getAttribute('content-type');
        if (contentType != null) {
          result.add(AddressDataType(
            contentType: contentType,
            version: child.getAttribute('version'),
          ));
        }
      }
    }

    return result;
  }

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

  String _sanitizeName(String name) {
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9-]'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }

  String _buildMkcolBody({
    required String name,
    String? description,
  }) {
    final props = StringBuffer();
    props.writeln(
      '        <D:resourcetype>\n'
      '          <D:collection/>\n'
      '          <C:addressbook/>\n'
      '        </D:resourcetype>',
    );
    props.writeln(
      '        <D:displayname>${VCardUtils.escapeXml(name)}</D:displayname>',
    );
    if (description != null) {
      props.writeln(
        '        <C:addressbook-description>${VCardUtils.escapeXml(description)}</C:addressbook-description>',
      );
    }

    return '''<?xml version="1.0" encoding="utf-8"?>
<D:mkcol xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:carddav">
  <D:set>
    <D:prop>
$props    </D:prop>
  </D:set>
</D:mkcol>''';
  }

  String _buildProppatchBody({
    String? displayName,
    String? description,
  }) {
    final props = StringBuffer();
    if (displayName != null) {
      props.writeln(
        '        <D:displayname>${VCardUtils.escapeXml(displayName)}</D:displayname>',
      );
    }
    if (description != null) {
      props.writeln(
        '        <C:addressbook-description>${VCardUtils.escapeXml(description)}</C:addressbook-description>',
      );
    }

    return '''<?xml version="1.0" encoding="utf-8"?>
<D:propertyupdate xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:carddav">
  <D:set>
    <D:prop>
$props    </D:prop>
  </D:set>
</D:propertyupdate>''';
  }

  static CalDavException _mapException(DioException e, String context) {
    return switch (e.response?.statusCode) {
      401 => const AuthenticationException(),
      403 => const ForbiddenException(),
      404 => const NotFoundException(),
      _ => CalDavException(
          '$context: ${e.message}',
          statusCode: e.response?.statusCode,
        ),
    };
  }
}
