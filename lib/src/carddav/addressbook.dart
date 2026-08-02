/// Supported address-data format advertised by a CardDAV server.
class AddressDataType {
  /// MIME content type (usually `text/vcard`).
  final String contentType;

  /// Optional version string (e.g. `3.0`, `4.0`).
  final String? version;

  const AddressDataType({
    required this.contentType,
    this.version,
  });

  @override
  String toString() =>
      version == null ? contentType : '$contentType; version=$version';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AddressDataType &&
        other.contentType == contentType &&
        other.version == version;
  }

  @override
  int get hashCode => Object.hash(contentType, version);
}

/// Represents a CardDAV address book collection (RFC 6352).
class AddressBook {
  /// Unique identifier (href fallback when server has no stable id).
  final String uid;

  /// Address book resource URL.
  final Uri href;

  /// Display name.
  final String displayName;

  /// Address book description (`CARDDAV:addressbook-description`).
  final String? description;

  /// Collection tag for sync (changes when contents change).
  final String? ctag;

  /// RFC 6578 sync token when advertised by the server (`DAV:sync-token`).
  final String? syncToken;

  /// Formats the server claims to accept for address objects.
  final List<AddressDataType> supportedAddressData;

  /// Whether the address book is read-only based on ACL privileges.
  final bool isReadOnly;

  const AddressBook({
    required this.uid,
    required this.href,
    required this.displayName,
    this.description,
    this.ctag,
    this.syncToken,
    this.supportedAddressData = const [],
    this.isReadOnly = false,
  });

  AddressBook copyWith({
    String? uid,
    Uri? href,
    String? displayName,
    String? description,
    String? ctag,
    String? syncToken,
    List<AddressDataType>? supportedAddressData,
    bool? isReadOnly,
  }) {
    return AddressBook(
      uid: uid ?? this.uid,
      href: href ?? this.href,
      displayName: displayName ?? this.displayName,
      description: description ?? this.description,
      ctag: ctag ?? this.ctag,
      syncToken: syncToken ?? this.syncToken,
      supportedAddressData: supportedAddressData ?? this.supportedAddressData,
      isReadOnly: isReadOnly ?? this.isReadOnly,
    );
  }

  @override
  String toString() {
    return 'AddressBook(displayName: $displayName, href: $href)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AddressBook && other.href == href;
  }

  @override
  int get hashCode => href.hashCode;
}
