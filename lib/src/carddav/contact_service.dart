import 'package:dio/dio.dart';

import '../client/webdav_client.dart';
import '../exceptions/caldav_exception.dart';
import '../sync/contact_sync_result.dart';
import '../webdav/dav_depth.dart';
import '../webdav/multistatus.dart';
import '../webdav/sync_collection.dart';
import '../webdav/sync_service.dart';
import '../webdav/xml_namespaces.dart';
import 'addressbook.dart';
import 'contact.dart';
import 'contact_filter.dart';
import 'vcard_parser.dart';
import 'vcard_utils.dart';

/// Service for CardDAV address object (contact) CRUD (RFC 6352).
class ContactService {
  final WebDavClient _client;
  final SyncService _syncService;

  ContactService(this._client) : _syncService = SyncService(_client);

  Contact? _parseContactFromResponse(
    DavResponse davResponse,
    AddressBook addressBook,
  ) {
    final addressData = davResponse.getProperty(
      'address-data',
      namespace: XmlNamespaces.carddav,
    );

    if (addressData == null || addressData.isEmpty) return null;

    final etag = davResponse.getProperty(
      'getetag',
      namespace: XmlNamespaces.dav,
    );

    return VCardParser.parse(
      addressData,
      addressBookId: addressBook.uid,
      href: addressBook.href.resolve(davResponse.href),
      etag: etag,
      isReadOnly: addressBook.isReadOnly,
    );
  }

  List<Contact> _parseContactsFromResponses(
    List<DavResponse> responses,
    AddressBook addressBook,
  ) {
    final contacts = <Contact>[];
    for (final davResponse in responses) {
      final contact = _parseContactFromResponse(davResponse, addressBook);
      if (contact != null) contacts.add(contact);
    }
    return contacts;
  }

  /// List contacts in an address book.
  ///
  /// Uses `addressbook-query`. If the server returns hrefs without
  /// `address-data`, falls back to `addressbook-multiget`.
  Future<List<Contact>> list(AddressBook addressBook) async {
    final body = buildAddressbookQueryBody();

    try {
      final response = await _client.report(
        addressBook.href.toString(),
        body: body,
        depth: DavDepth.one,
      );

      final multiStatus = MultiStatus.fromXml(response.data ?? '');
      if (multiStatus.responses.isEmpty) return [];

      final contacts =
          _parseContactsFromResponses(multiStatus.responses, addressBook);
      if (contacts.isNotEmpty) return contacts;

      final urlsWithoutData = multiStatus.responses
          .where((r) => r.href.toLowerCase().endsWith('.vcf'))
          .map((r) => r.href)
          .toList();

      if (urlsWithoutData.isNotEmpty) {
        return _fetchWithMultiget(addressBook, urlsWithoutData);
      }

      return [];
    } on DioException catch (e) {
      throw _mapException(e, 'Failed to list contacts');
    }
  }

  /// Batch fetch contacts using addressbook-multiget.
  Future<List<Contact>> multiGet(
    AddressBook addressBook,
    List<Uri> contactUrls,
  ) async {
    if (contactUrls.isEmpty) return [];
    final paths = contactUrls.map((u) => u.path).toList();
    return _fetchWithMultiget(addressBook, paths);
  }

  Future<List<Contact>> _fetchWithMultiget(
    AddressBook addressBook,
    List<String> contactPaths,
  ) async {
    if (contactPaths.isEmpty) return [];

    final hrefs = contactPaths
        .map((p) => '<D:href>${VCardUtils.escapeXml(p)}</D:href>')
        .join('\n');

    final body = '''<?xml version="1.0" encoding="utf-8"?>
<C:addressbook-multiget xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:carddav">
  <D:prop>
    <D:getetag/>
    <C:address-data/>
  </D:prop>
  $hrefs
</C:addressbook-multiget>''';

    try {
      final response = await _client.report(
        addressBook.href.toString(),
        body: body,
        depth: DavDepth.one,
      );

      final multiStatus = MultiStatus.fromXml(response.data ?? '');
      return _parseContactsFromResponses(multiStatus.responses, addressBook);
    } on DioException catch (e) {
      throw _mapException(e, 'Failed to fetch contacts');
    }
  }

  /// Create a new contact. Returns the created contact with href and etag.
  Future<Contact> create(AddressBook addressBook, Contact contact) async {
    final path = addressBook.href.resolve('${contact.uid}.vcf');
    final body = VCardParser.serialize(contact);

    try {
      final response = await _client.put(
        path.toString(),
        body: body,
        contentType: 'text/vcard; charset=utf-8',
        ifNoneMatch: '*',
      );

      final etag = response.headers.value('etag');
      return contact.copyWith(
        href: path,
        etag: etag,
        addressBookId: addressBook.uid,
        rawVcard: body,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 412) {
        throw const ConflictException('Contact already exists');
      }
      throw _mapException(e, 'Failed to create contact');
    }
  }

  /// Update an existing contact (ETag optimistic locking when available).
  Future<Contact> update(Contact contact) async {
    if (contact.href == null) {
      throw const CalDavException('Contact href is required for update');
    }

    final body = VCardParser.serialize(contact);

    try {
      final response = await _client.put(
        contact.href.toString(),
        body: body,
        contentType: 'text/vcard; charset=utf-8',
        ifMatch: contact.etag,
      );

      final newEtag = response.headers.value('etag');
      return contact.copyWith(etag: newEtag, rawVcard: body);
    } on DioException catch (e) {
      if (e.response?.statusCode == 412) {
        throw const ConflictException(
          'Contact was modified by another client. Please refresh and try again.',
        );
      }
      throw _mapException(e, 'Failed to update contact');
    }
  }

  /// Delete a contact.
  Future<void> delete(Contact contact) async {
    if (contact.href == null) {
      throw const CalDavException('Contact href is required for delete');
    }

    try {
      await _client.delete(
        contact.href.toString(),
        ifMatch: contact.etag,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return;
      }
      if (e.response?.statusCode == 412) {
        throw const ConflictException(
          'Contact was modified by another client. Please refresh and try again.',
        );
      }
      throw _mapException(e, 'Failed to delete contact');
    }
  }

  /// Find a contact by UID in a specific address book.
  Future<Contact?> findByUid(AddressBook addressBook, String uid) async {
    final body = buildUidQueryBody(uid);

    try {
      final response = await _client.report(
        addressBook.href.toString(),
        body: body,
        depth: DavDepth.one,
      );

      final multiStatus = MultiStatus.fromXml(response.data ?? '');
      if (multiStatus.responses.isEmpty) return null;

      for (final davResponse in multiStatus.responses) {
        final contact = _parseContactFromResponse(davResponse, addressBook);
        if (contact != null) return contact;
      }

      final urlWithoutData = multiStatus.responses
          .where((r) => r.href.toLowerCase().endsWith('.vcf'))
          .map((r) => r.href)
          .firstOrNull;

      if (urlWithoutData != null) {
        final contacts =
            await _fetchWithMultiget(addressBook, [urlWithoutData]);
        return contacts.isNotEmpty ? contacts.first : null;
      }

      return null;
    } on DioException catch (e) {
      throw _mapException(e, 'Failed to find contact by UID');
    }
  }

  /// Search contacts by a text match on a single vCard property.
  ///
  /// Prefer [query] with a [ContactFilter] for multi-property or TYPE filters.
  Future<List<Contact>> search(
    AddressBook addressBook, {
    required String propertyName,
    required String text,
    bool matchAll = false,
  }) {
    return query(
      addressBook,
      ContactFilter(
        filters: [
          PropFilter(
            propertyName: propertyName,
            text: text,
            matchType:
                matchAll ? TextMatchType.equals : TextMatchType.contains,
          ),
        ],
      ),
    );
  }

  /// Query contacts using a structured [ContactFilter] (RFC 6352 addressbook-query).
  Future<List<Contact>> query(
    AddressBook addressBook,
    ContactFilter filter,
  ) async {
    final body = filter.toAddressbookQueryXml();

    try {
      final response = await _client.report(
        addressBook.href.toString(),
        body: body,
        depth: DavDepth.one,
      );

      final multiStatus = MultiStatus.fromXml(response.data ?? '');
      if (multiStatus.responses.isEmpty) return [];

      final contacts =
          _parseContactsFromResponses(multiStatus.responses, addressBook);
      if (contacts.isNotEmpty) return contacts;

      final urlsWithoutData = multiStatus.responses
          .where((r) => r.href.toLowerCase().endsWith('.vcf'))
          .map((r) => r.href)
          .toList();

      if (urlsWithoutData.isNotEmpty) {
        return _fetchWithMultiget(addressBook, urlsWithoutData);
      }

      return [];
    } on DioException catch (e) {
      throw _mapException(e, 'Failed to query contacts');
    }
  }

  /// Build an addressbook-query that returns all contacts with address-data.
  static String buildAddressbookQueryBody() {
    return '''<?xml version="1.0" encoding="utf-8"?>
<C:addressbook-query xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:carddav">
  <D:prop>
    <D:getetag/>
    <C:address-data/>
  </D:prop>
</C:addressbook-query>''';
  }

  /// Build an addressbook-query matching a contact UID.
  static String buildUidQueryBody(String uid) {
    final escaped = VCardUtils.escapeXml(uid);
    return '''<?xml version="1.0" encoding="utf-8"?>
<C:addressbook-query xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:carddav">
  <D:prop>
    <D:getetag/>
    <C:address-data/>
  </D:prop>
  <C:filter>
    <C:prop-filter name="UID">
      <C:text-match collation="i;octet">$escaped</C:text-match>
    </C:prop-filter>
  </C:filter>
</C:addressbook-query>''';
  }

  /// Build an addressbook-query with a prop-filter text-match.
  static String buildPropFilterQueryBody({
    required String propertyName,
    required String text,
    bool matchAll = false,
  }) {
    return ContactFilter(
      filters: [
        PropFilter(
          propertyName: propertyName,
          text: text,
          matchType: matchAll ? TextMatchType.equals : TextMatchType.contains,
        ),
      ],
    ).toAddressbookQueryXml();
  }

  /// Build an addressbook-query from a [ContactFilter].
  static String buildFilterQueryBody(ContactFilter filter) =>
      filter.toAddressbookQueryXml();

  /// Synchronize address book members via RFC 6578 `sync-collection`.
  ///
  /// Pass [syncToken] from a previous [ContactSyncResult] for an incremental
  /// sync; omit for a full baseline.
  ///
  /// Throws [InvalidSyncTokenException] when the token is no longer valid.
  Future<ContactSyncResult> sync(
    AddressBook addressBook, {
    String? syncToken,
    int? limit,
    bool includeData = true,
    bool followTruncation = true,
    SyncLevel level = SyncLevel.members,
  }) async {
    final CollectionSyncResult raw;
    if (followTruncation) {
      raw = await _syncService.syncCollectionFully(
        addressBook.href,
        rebuild: (token) => SyncCollectionBuilder.addressbook(
          syncToken: token ?? syncToken,
          level: level,
          limit: limit,
          includeData: includeData,
        ),
      );
    } else {
      raw = await _syncService.syncCollection(
        addressBook.href,
        SyncCollectionBuilder.addressbook(
          syncToken: syncToken,
          level: level,
          limit: limit,
          includeData: includeData,
        ),
      );
    }

    return _toContactSyncResult(raw, addressBook);
  }

  /// Read the collection's current `DAV:sync-token` without listing members.
  Future<String?> getSyncToken(AddressBook addressBook) =>
      _syncService.getSyncToken(addressBook.href);

  ContactSyncResult _toContactSyncResult(
    CollectionSyncResult raw,
    AddressBook addressBook,
  ) {
    final contacts = <Contact>[];
    final deleted = <Uri>[];

    for (final change in raw.changes) {
      if (change.isDeleted) {
        deleted.add(change.resolvedHref);
        continue;
      }
      final data = change.data;
      if (data == null || data.isEmpty) continue;

      final contact = VCardParser.parse(
        data,
        addressBookId: addressBook.uid,
        href: change.resolvedHref,
        etag: change.etag,
        isReadOnly: addressBook.isReadOnly,
      );
      if (contact != null) {
        contacts.add(contact);
      }
    }

    return ContactSyncResult(
      syncToken: raw.syncToken,
      contacts: contacts,
      deletedHrefs: deleted,
      rawChanges: raw.changes,
      truncated: raw.truncated,
    );
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
