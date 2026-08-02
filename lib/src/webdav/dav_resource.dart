/// Generic WebDAV resource metadata (RFC 4918 properties).
class DavResource {
  /// Resource URL (absolute or as returned by the server, resolved by callers).
  final Uri href;

  /// Display name (`DAV:displayname`).
  final String? displayName;

  /// Entity tag (`DAV:getetag`).
  final String? etag;

  /// Content type (`DAV:getcontenttype`).
  final String? contentType;

  /// Content length in bytes (`DAV:getcontentlength`), if known.
  final int? contentLength;

  /// Last modification time (`DAV:getlastmodified`), if parseable.
  final DateTime? lastModified;

  /// Creation time (`DAV:creationdate`), if parseable.
  final DateTime? creationDate;

  /// Whether the resource is a collection (`DAV:collection` resourcetype).
  final bool isCollection;

  /// Whether the resource is a CalDAV calendar.
  final bool isCalendar;

  /// Whether the resource is a CardDAV address book.
  final bool isAddressBook;

  /// Whether the resource appears read-only based on privilege-set (if present).
  final bool isReadOnly;

  /// Local names of resourcetype child elements (e.g. `collection`, `calendar`).
  final List<String> resourceTypes;

  const DavResource({
    required this.href,
    this.displayName,
    this.etag,
    this.contentType,
    this.contentLength,
    this.lastModified,
    this.creationDate,
    this.isCollection = false,
    this.isCalendar = false,
    this.isAddressBook = false,
    this.isReadOnly = false,
    this.resourceTypes = const [],
  });

  DavResource copyWith({
    Uri? href,
    String? displayName,
    String? etag,
    String? contentType,
    int? contentLength,
    DateTime? lastModified,
    DateTime? creationDate,
    bool? isCollection,
    bool? isCalendar,
    bool? isAddressBook,
    bool? isReadOnly,
    List<String>? resourceTypes,
  }) {
    return DavResource(
      href: href ?? this.href,
      displayName: displayName ?? this.displayName,
      etag: etag ?? this.etag,
      contentType: contentType ?? this.contentType,
      contentLength: contentLength ?? this.contentLength,
      lastModified: lastModified ?? this.lastModified,
      creationDate: creationDate ?? this.creationDate,
      isCollection: isCollection ?? this.isCollection,
      isCalendar: isCalendar ?? this.isCalendar,
      isAddressBook: isAddressBook ?? this.isAddressBook,
      isReadOnly: isReadOnly ?? this.isReadOnly,
      resourceTypes: resourceTypes ?? this.resourceTypes,
    );
  }

  @override
  String toString() {
    return 'DavResource(href: $href, displayName: $displayName, '
        'isCollection: $isCollection)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DavResource && other.href == href;
  }

  @override
  int get hashCode => href.hashCode;
}
