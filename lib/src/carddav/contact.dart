import 'vcard_property.dart';

/// A typed vCard property value (EMAIL, TEL, URL, …) with optional TYPE params.
class VCardTypedValue {
  /// Property value (e.g. email address or phone number).
  final String value;

  /// TYPE parameter values (e.g. `HOME`, `WORK`, `CELL`).
  final List<String> types;

  /// Optional PREF rank (lower is more preferred when present).
  final int? pref;

  /// Additional parameters not covered by [types]/[pref] (e.g. `VALUE`).
  final Map<String, List<String>> extraParams;

  const VCardTypedValue({
    required this.value,
    this.types = const [],
    this.pref,
    this.extraParams = const {},
  });

  VCardTypedValue copyWith({
    String? value,
    List<String>? types,
    int? pref,
    Map<String, List<String>>? extraParams,
  }) {
    return VCardTypedValue(
      value: value ?? this.value,
      types: types ?? this.types,
      pref: pref ?? this.pref,
      extraParams: extraParams ?? this.extraParams,
    );
  }

  @override
  String toString() =>
      types.isEmpty ? value : '$value (${types.join(',')})';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is VCardTypedValue &&
        other.value == value &&
        _listEq(other.types, types) &&
        other.pref == pref;
  }

  @override
  int get hashCode => Object.hash(value, Object.hashAll(types), pref);
}

/// Structured name (`N`) components from vCard.
class StructuredName {
  final String? family;
  final String? given;
  final String? additional;
  final String? prefix;
  final String? suffix;

  const StructuredName({
    this.family,
    this.given,
    this.additional,
    this.prefix,
    this.suffix,
  });

  /// Serialize to the vCard `N` value form (unescaped separators).
  String toVCardValue() {
    return [
      family ?? '',
      given ?? '',
      additional ?? '',
      prefix ?? '',
      suffix ?? '',
    ].join(';');
  }

  /// Parse a vCard `N` value (components separated by unescaped `;`).
  factory StructuredName.parse(String value) {
    final parts = splitVCardComponents(value);
    String? at(int i) {
      if (i >= parts.length) return null;
      final s = parts[i];
      return s.isEmpty ? null : s;
    }

    return StructuredName(
      family: at(0),
      given: at(1),
      additional: at(2),
      prefix: at(3),
      suffix: at(4),
    );
  }

  StructuredName copyWith({
    String? family,
    String? given,
    String? additional,
    String? prefix,
    String? suffix,
  }) {
    return StructuredName(
      family: family ?? this.family,
      given: given ?? this.given,
      additional: additional ?? this.additional,
      prefix: prefix ?? this.prefix,
      suffix: suffix ?? this.suffix,
    );
  }

  @override
  String toString() => toVCardValue();

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is StructuredName &&
        other.family == family &&
        other.given == given &&
        other.additional == additional &&
        other.prefix == prefix &&
        other.suffix == suffix;
  }

  @override
  int get hashCode => Object.hash(family, given, additional, prefix, suffix);
}

/// Postal address (`ADR`) components from vCard.
class PostalAddress {
  final String? poBox;
  final String? extended;
  final String? street;
  final String? locality;
  final String? region;
  final String? postalCode;
  final String? country;
  final List<String> types;
  final String? label;

  const PostalAddress({
    this.poBox,
    this.extended,
    this.street,
    this.locality,
    this.region,
    this.postalCode,
    this.country,
    this.types = const [],
    this.label,
  });

  String toVCardValue() {
    return [
      poBox ?? '',
      extended ?? '',
      street ?? '',
      locality ?? '',
      region ?? '',
      postalCode ?? '',
      country ?? '',
    ].join(';');
  }

  factory PostalAddress.parse(
    String value, {
    List<String> types = const [],
    String? label,
  }) {
    final parts = splitVCardComponents(value);
    String? at(int i) {
      if (i >= parts.length) return null;
      final s = parts[i];
      return s.isEmpty ? null : s;
    }

    return PostalAddress(
      poBox: at(0),
      extended: at(1),
      street: at(2),
      locality: at(3),
      region: at(4),
      postalCode: at(5),
      country: at(6),
      types: types,
      label: label,
    );
  }

  PostalAddress copyWith({
    String? poBox,
    String? extended,
    String? street,
    String? locality,
    String? region,
    String? postalCode,
    String? country,
    List<String>? types,
    String? label,
  }) {
    return PostalAddress(
      poBox: poBox ?? this.poBox,
      extended: extended ?? this.extended,
      street: street ?? this.street,
      locality: locality ?? this.locality,
      region: region ?? this.region,
      postalCode: postalCode ?? this.postalCode,
      country: country ?? this.country,
      types: types ?? this.types,
      label: label ?? this.label,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PostalAddress &&
        other.poBox == poBox &&
        other.extended == extended &&
        other.street == street &&
        other.locality == locality &&
        other.region == region &&
        other.postalCode == postalCode &&
        other.country == country &&
        _listEq(other.types, types) &&
        other.label == label;
  }

  @override
  int get hashCode => Object.hash(
        poBox,
        extended,
        street,
        locality,
        region,
        postalCode,
        country,
        Object.hashAll(types),
        label,
      );
}

/// Represents a CardDAV address object (vCard contact).
class Contact {
  /// Unique identifier (vCard UID).
  final String uid;

  /// Parent address book UID.
  final String addressBookId;

  /// Resource URL (set after creation / fetch).
  final Uri? href;

  /// Entity tag for concurrency control.
  final String? etag;

  /// Formatted name (`FN`) — required by vCard.
  final String formattedName;

  /// Structured name (`N`).
  final StructuredName? name;

  /// Nicknames (`NICKNAME`), possibly comma-separated values expanded to list.
  final List<String> nicknames;

  /// Email addresses.
  final List<VCardTypedValue> emails;

  /// Telephone numbers.
  final List<VCardTypedValue> phones;

  /// Postal addresses.
  final List<PostalAddress> addresses;

  /// Organization (`ORG`).
  final String? organization;

  /// Job title (`TITLE`).
  final String? title;

  /// Role (`ROLE`).
  final String? role;

  /// Free-form note (`NOTE`).
  final String? note;

  /// Primary URL (`URL`) list.
  final List<VCardTypedValue> urls;

  /// Instant messaging addresses (`IMPP`).
  final List<VCardImpp> impps;

  /// Birthday as stored in vCard (`BDAY`).
  final String? birthday;

  /// Anniversary (`ANNIVERSARY`).
  final String? anniversary;

  /// Categories / tags.
  final List<String> categories;

  /// Photo (`PHOTO`).
  final VCardPhoto? photo;

  /// Logo (`LOGO`).
  final VCardPhoto? logo;

  /// Geographic coordinates (`GEO`).
  final VCardGeo? geo;

  /// Time zone (`TZ`) raw value.
  final String? timeZone;

  /// Languages (`LANG`).
  final List<VCardTypedValue> languages;

  /// Related contacts (`RELATED`).
  final List<VCardRelated> related;

  /// Gender (`GENDER`).
  final VCardGender? gender;

  /// Kind of object (`KIND`: individual, group, org, location).
  final String? kind;

  /// Group members (`MEMBER`) for KIND=group.
  final List<String> members;

  /// Revision timestamp (`REV`) raw value.
  final String? rev;

  /// Product identifier (`PRODID`).
  final String? prodId;

  /// Whether this contact is read-only (inherited from address book).
  final bool isReadOnly;

  /// Raw vCard data preserved from the server when available.
  final String? rawVcard;

  /// Unmapped properties preserved for round-trip fidelity.
  final List<VCardRawProperty> extraProperties;

  const Contact({
    required this.uid,
    required this.addressBookId,
    this.href,
    this.etag,
    required this.formattedName,
    this.name,
    this.nicknames = const [],
    this.emails = const [],
    this.phones = const [],
    this.addresses = const [],
    this.organization,
    this.title,
    this.role,
    this.note,
    this.urls = const [],
    this.impps = const [],
    this.birthday,
    this.anniversary,
    this.categories = const [],
    this.photo,
    this.logo,
    this.geo,
    this.timeZone,
    this.languages = const [],
    this.related = const [],
    this.gender,
    this.kind,
    this.members = const [],
    this.rev,
    this.prodId,
    this.isReadOnly = false,
    this.rawVcard,
    this.extraProperties = const [],
  });

  /// Primary email when present.
  String? get primaryEmail =>
      emails.isEmpty ? null : preferredTyped(emails).value;

  /// Primary phone when present.
  String? get primaryPhone =>
      phones.isEmpty ? null : preferredTyped(phones).value;

  /// First nickname when present.
  String? get nickname => nicknames.isEmpty ? null : nicknames.first;

  /// Whether this contact represents a group.
  bool get isGroup =>
      (kind != null && kind!.toLowerCase() == 'group') || members.isNotEmpty;

  static VCardTypedValue preferredTyped(List<VCardTypedValue> values) {
    final withPref = values.where((v) => v.pref != null).toList()
      ..sort((a, b) => a.pref!.compareTo(b.pref!));
    if (withPref.isNotEmpty) return withPref.first;
    return values.first;
  }

  Contact copyWith({
    String? uid,
    String? addressBookId,
    Uri? href,
    String? etag,
    String? formattedName,
    StructuredName? name,
    List<String>? nicknames,
    List<VCardTypedValue>? emails,
    List<VCardTypedValue>? phones,
    List<PostalAddress>? addresses,
    String? organization,
    String? title,
    String? role,
    String? note,
    List<VCardTypedValue>? urls,
    List<VCardImpp>? impps,
    String? birthday,
    String? anniversary,
    List<String>? categories,
    VCardPhoto? photo,
    VCardPhoto? logo,
    VCardGeo? geo,
    String? timeZone,
    List<VCardTypedValue>? languages,
    List<VCardRelated>? related,
    VCardGender? gender,
    String? kind,
    List<String>? members,
    String? rev,
    String? prodId,
    bool? isReadOnly,
    String? rawVcard,
    List<VCardRawProperty>? extraProperties,
  }) {
    return Contact(
      uid: uid ?? this.uid,
      addressBookId: addressBookId ?? this.addressBookId,
      href: href ?? this.href,
      etag: etag ?? this.etag,
      formattedName: formattedName ?? this.formattedName,
      name: name ?? this.name,
      nicknames: nicknames ?? this.nicknames,
      emails: emails ?? this.emails,
      phones: phones ?? this.phones,
      addresses: addresses ?? this.addresses,
      organization: organization ?? this.organization,
      title: title ?? this.title,
      role: role ?? this.role,
      note: note ?? this.note,
      urls: urls ?? this.urls,
      impps: impps ?? this.impps,
      birthday: birthday ?? this.birthday,
      anniversary: anniversary ?? this.anniversary,
      categories: categories ?? this.categories,
      photo: photo ?? this.photo,
      logo: logo ?? this.logo,
      geo: geo ?? this.geo,
      timeZone: timeZone ?? this.timeZone,
      languages: languages ?? this.languages,
      related: related ?? this.related,
      gender: gender ?? this.gender,
      kind: kind ?? this.kind,
      members: members ?? this.members,
      rev: rev ?? this.rev,
      prodId: prodId ?? this.prodId,
      isReadOnly: isReadOnly ?? this.isReadOnly,
      rawVcard: rawVcard ?? this.rawVcard,
      extraProperties: extraProperties ?? this.extraProperties,
    );
  }

  @override
  String toString() {
    return 'Contact(formattedName: $formattedName, uid: $uid)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Contact && other.uid == uid && other.href == href;
  }

  @override
  int get hashCode => Object.hash(uid, href);
}

bool _listEq(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Split a vCard structured value on unescaped `;` and unescape each part.
List<String> splitVCardComponents(String value) {
  final parts = <String>[];
  final buffer = StringBuffer();
  for (var i = 0; i < value.length; i++) {
    final ch = value[i];
    if (ch == '\\' && i + 1 < value.length) {
      final next = value[i + 1];
      switch (next) {
        case 'n':
        case 'N':
          buffer.write('\n');
        case ';':
          buffer.write(';');
        case ',':
          buffer.write(',');
        case '\\':
          buffer.write('\\');
        default:
          buffer.write(next);
      }
      i++;
      continue;
    }
    if (ch == ';') {
      parts.add(buffer.toString());
      buffer.clear();
      continue;
    }
    buffer.write(ch);
  }
  parts.add(buffer.toString());
  return parts;
}
