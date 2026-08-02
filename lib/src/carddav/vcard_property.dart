import 'vcard_utils.dart';

/// A photo or logo attached to a vCard (`PHOTO` / `LOGO`).
class VCardPhoto {
  /// URI or raw/base64 payload.
  final String value;

  /// True when the value is a URI (`VALUE=uri` or URI-looking content).
  final bool isUri;

  /// MIME type when known (e.g. `image/jpeg`), from `TYPE` or `MEDIATYPE`.
  final String? mediaType;

  /// Encoding parameter (`b` / `BASE64`) when binary.
  final String? encoding;

  const VCardPhoto({
    required this.value,
    this.isUri = false,
    this.mediaType,
    this.encoding,
  });

  VCardPhoto copyWith({
    String? value,
    bool? isUri,
    String? mediaType,
    String? encoding,
  }) {
    return VCardPhoto(
      value: value ?? this.value,
      isUri: isUri ?? this.isUri,
      mediaType: mediaType ?? this.mediaType,
      encoding: encoding ?? this.encoding,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is VCardPhoto &&
        other.value == value &&
        other.isUri == isUri &&
        other.mediaType == mediaType &&
        other.encoding == encoding;
  }

  @override
  int get hashCode => Object.hash(value, isUri, mediaType, encoding);
}

/// Instant messaging address (`IMPP`).
class VCardImpp {
  /// URI such as `xmpp:user@example.com` or `sip:...`.
  final String uri;

  /// TYPE values (e.g. `HOME`, `WORK`).
  final List<String> types;

  /// Optional preference rank.
  final int? pref;

  /// Optional service type label when present as `X-SERVICE-TYPE` etc.
  final String? serviceType;

  const VCardImpp({
    required this.uri,
    this.types = const [],
    this.pref,
    this.serviceType,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is VCardImpp &&
        other.uri == uri &&
        _eqLists(other.types, types) &&
        other.pref == pref &&
        other.serviceType == serviceType;
  }

  @override
  int get hashCode => Object.hash(uri, Object.hashAll(types), pref, serviceType);
}

/// Related contact reference (`RELATED` in vCard 4.0 / `X-ABRELATEDNAMES`).
class VCardRelated {
  /// URI or text value of the related entity.
  final String value;

  /// Relationship types (`friend`, `spouse`, `child`, …) or TYPE params.
  final List<String> types;

  /// True when the value is a URI.
  final bool isUri;

  const VCardRelated({
    required this.value,
    this.types = const [],
    this.isUri = false,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is VCardRelated &&
        other.value == value &&
        _eqLists(other.types, types) &&
        other.isUri == isUri;
  }

  @override
  int get hashCode => Object.hash(value, Object.hashAll(types), isUri);
}

/// Geographic coordinates (`GEO`).
class VCardGeo {
  final double latitude;
  final double longitude;

  const VCardGeo({
    required this.latitude,
    required this.longitude,
  });

  /// Parse `lat;lon` (v3) or `geo:lat,lon` (v4).
  static VCardGeo? tryParse(String raw) {
    var s = raw.trim();
    if (s.toLowerCase().startsWith('geo:')) {
      s = s.substring(4);
      final parts = s.split(',');
      if (parts.length >= 2) {
        final lat = double.tryParse(parts[0]);
        final lon = double.tryParse(parts[1]);
        if (lat != null && lon != null) {
          return VCardGeo(latitude: lat, longitude: lon);
        }
      }
      return null;
    }
    final parts = s.split(';');
    if (parts.length >= 2) {
      final lat = double.tryParse(parts[0]);
      final lon = double.tryParse(parts[1]);
      if (lat != null && lon != null) {
        return VCardGeo(latitude: lat, longitude: lon);
      }
    }
    return null;
  }

  String toVCard3Value() => '$latitude;$longitude';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is VCardGeo &&
        other.latitude == latitude &&
        other.longitude == longitude;
  }

  @override
  int get hashCode => Object.hash(latitude, longitude);
}

/// Opaque vCard property preserved when not mapped to a structured field.
class VCardRawProperty {
  /// Property name (uppercase), without group.
  final String name;

  /// Optional group prefix (e.g. `item1`).
  final String? group;

  /// Parameters keyed by uppercase name.
  final Map<String, List<String>> params;

  /// Raw property value (not unescaped for re-serialization fidelity).
  final String value;

  const VCardRawProperty({
    required this.name,
    this.group,
    this.params = const {},
    required this.value,
  });

  /// Serialize to a single (unfolded) vCard line.
  String toLine() {
    final buffer = StringBuffer();
    if (group != null && group!.isNotEmpty) {
      buffer.write('$group.');
    }
    buffer.write(name);
    params.forEach((key, values) {
      if (values.isEmpty) {
        buffer.write(';$key');
      } else {
        buffer.write(';$key=${values.join(',')}');
      }
    });
    buffer.write(':$value');
    return buffer.toString();
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is VCardRawProperty &&
        other.name == name &&
        other.group == group &&
        other.value == value;
  }

  @override
  int get hashCode => Object.hash(name, group, value);
}

/// Gender (`GENDER` in vCard 4.0): sex component + optional identity text.
class VCardGender {
  /// Sex: `M`, `F`, `O`, `N`, `U`, or empty.
  final String? sex;

  /// Free-form gender identity text.
  final String? identity;

  const VCardGender({this.sex, this.identity});

  factory VCardGender.parse(String value) {
    final parts = value.split(';');
    final sex = parts.isNotEmpty && parts[0].isNotEmpty ? parts[0] : null;
    final identity = parts.length > 1 && parts[1].isNotEmpty
        ? VCardUtils.unescapeText(parts[1])
        : null;
    return VCardGender(sex: sex, identity: identity);
  }

  String toVCardValue() {
    final s = sex ?? '';
    if (identity == null || identity!.isEmpty) return s;
    return '$s;${VCardUtils.escapeText(identity!)}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is VCardGender && other.sex == sex && other.identity == identity;
  }

  @override
  int get hashCode => Object.hash(sex, identity);
}

bool _eqLists(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
