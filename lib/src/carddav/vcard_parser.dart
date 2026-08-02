import 'contact.dart';
import 'vcard_property.dart';
import 'vcard_utils.dart';

/// Properties handled structurally by [VCardParser] (not stored in extras).
const _handledProperties = {
  'VERSION',
  'UID',
  'FN',
  'N',
  'NICKNAME',
  'EMAIL',
  'TEL',
  'ADR',
  'ORG',
  'TITLE',
  'ROLE',
  'NOTE',
  'URL',
  'IMPP',
  'BDAY',
  'ANNIVERSARY',
  'CATEGORIES',
  'PHOTO',
  'LOGO',
  'GEO',
  'TZ',
  'LANG',
  'RELATED',
  'GENDER',
  'KIND',
  'MEMBER',
  'REV',
  'PRODID',
  'LABEL', // v3 label often paired with ADR via group
};

/// Parse and serialize vCard 3.0 / 4.0 address objects for CardDAV.
class VCardParser {
  VCardParser._();

  /// Parse a vCard document into a [Contact].
  ///
  /// Returns null if no `BEGIN:VCARD` block is found or UID/FN cannot be resolved.
  static Contact? parse(
    String vcard, {
    required String addressBookId,
    Uri? href,
    String? etag,
    bool isReadOnly = false,
  }) {
    final unfolded = VCardUtils.unfold(vcard);
    final lines = unfolded.split('\n').map((l) => l.trimRight()).toList();

    final props = <ParsedVCardProperty>[];
    var inVcard = false;

    for (final line in lines) {
      if (line.isEmpty) continue;
      final upper = line.toUpperCase();
      if (upper == 'BEGIN:VCARD') {
        inVcard = true;
        continue;
      }
      if (upper == 'END:VCARD') {
        break;
      }
      if (!inVcard) continue;

      final prop = VCardUtils.parsePropertyLine(line);
      if (prop != null) props.add(prop);
    }

    if (props.isEmpty) return null;

    String? uid;
    String? fn;
    StructuredName? name;
    final nicknames = <String>[];
    final emails = <VCardTypedValue>[];
    final phones = <VCardTypedValue>[];
    final addresses = <PostalAddress>[];
    final urls = <VCardTypedValue>[];
    final impps = <VCardImpp>[];
    final languages = <VCardTypedValue>[];
    final related = <VCardRelated>[];
    final members = <String>[];
    final extra = <VCardRawProperty>[];
    String? organization;
    String? title;
    String? role;
    String? note;
    String? birthday;
    String? anniversary;
    final categories = <String>[];
    VCardPhoto? photo;
    VCardPhoto? logo;
    VCardGeo? geo;
    String? timeZone;
    VCardGender? gender;
    String? kind;
    String? rev;
    String? prodId;

    // Collect LABEL by group for ADR association (Apple / v3 style).
    final labelsByGroup = <String, String>{};
    for (final prop in props) {
      if (prop.name == 'LABEL' && prop.group != null) {
        labelsByGroup[prop.group!] = VCardUtils.unescapeText(prop.value);
      }
    }

    for (final prop in props) {
      switch (prop.name) {
        case 'UID':
          uid = VCardUtils.unescapeText(prop.value);
        case 'FN':
          fn = VCardUtils.unescapeText(prop.value);
        case 'N':
          name = StructuredName.parse(prop.value);
        case 'NICKNAME':
          nicknames.addAll(
            prop.value
                .split(',')
                .map((n) => VCardUtils.unescapeText(n.trim()))
                .where((n) => n.isNotEmpty),
          );
        case 'EMAIL':
          emails.add(_typed(prop));
        case 'TEL':
          phones.add(_typed(prop));
        case 'ADR':
          final label = prop.group != null ? labelsByGroup[prop.group!] : null;
          addresses.add(PostalAddress.parse(
            prop.value,
            types: prop.types,
            label: label,
          ));
        case 'ORG':
          organization = VCardUtils.unescapeText(prop.value);
        case 'TITLE':
          title = VCardUtils.unescapeText(prop.value);
        case 'ROLE':
          role = VCardUtils.unescapeText(prop.value);
        case 'NOTE':
          note = VCardUtils.unescapeText(prop.value);
        case 'URL':
          urls.add(_typed(prop));
        case 'IMPP':
          impps.add(VCardImpp(
            uri: VCardUtils.unescapeText(prop.value),
            types: prop.types,
            pref: prop.pref,
            serviceType: prop.params['X-SERVICE-TYPE']?.firstOrNull ??
                prop.params['TYPE']?.where((t) => !_isAddressType(t)).firstOrNull,
          ));
        case 'BDAY':
          birthday = prop.value.trim();
        case 'ANNIVERSARY':
          anniversary = prop.value.trim();
        case 'CATEGORIES':
          categories.addAll(
            prop.value
                .split(',')
                .map((c) => VCardUtils.unescapeText(c.trim()))
                .where((c) => c.isNotEmpty),
          );
        case 'PHOTO':
          photo = _parsePhoto(prop);
        case 'LOGO':
          logo = _parsePhoto(prop);
        case 'GEO':
          geo = VCardGeo.tryParse(prop.value);
        case 'TZ':
          timeZone = VCardUtils.unescapeText(prop.value);
        case 'LANG':
          languages.add(_typed(prop));
        case 'RELATED':
          related.add(VCardRelated(
            value: VCardUtils.unescapeText(prop.value),
            types: prop.types.isNotEmpty
                ? prop.types
                : (prop.params['TYPE'] ?? const []),
            isUri: _isUriValue(prop),
          ));
        case 'GENDER':
          gender = VCardGender.parse(prop.value);
        case 'KIND':
          kind = VCardUtils.unescapeText(prop.value).toLowerCase();
        case 'MEMBER':
          members.add(VCardUtils.unescapeText(prop.value));
        case 'REV':
          rev = prop.value.trim();
        case 'PRODID':
          prodId = VCardUtils.unescapeText(prop.value);
        case 'LABEL':
          // Handled via group association; skip standalone extras if grouped.
          if (prop.group == null) {
            extra.add(_toRaw(prop));
          }
        case 'VERSION':
          // ignored
          break;
        default:
          if (!_handledProperties.contains(prop.name)) {
            extra.add(_toRaw(prop));
          }
      }
    }

    uid ??= href != null ? _uidFromHref(href) : null;
    fn ??= name != null
        ? [name.prefix, name.given, name.additional, name.family, name.suffix]
            .whereType<String>()
            .where((s) => s.isNotEmpty)
            .join(' ')
        : null;

    if (uid == null || uid.isEmpty) return null;
    if (fn == null || fn.isEmpty) {
      fn = nicknames.isNotEmpty ? nicknames.first : uid;
    }

    return Contact(
      uid: uid,
      addressBookId: addressBookId,
      href: href,
      etag: etag,
      formattedName: fn,
      name: name,
      nicknames: nicknames,
      emails: emails,
      phones: phones,
      addresses: addresses,
      organization: organization,
      title: title,
      role: role,
      note: note,
      urls: urls,
      impps: impps,
      birthday: birthday,
      anniversary: anniversary,
      categories: categories,
      photo: photo,
      logo: logo,
      geo: geo,
      timeZone: timeZone,
      languages: languages,
      related: related,
      gender: gender,
      kind: kind,
      members: members,
      rev: rev,
      prodId: prodId,
      isReadOnly: isReadOnly,
      rawVcard: vcard,
      extraProperties: extra,
    );
  }

  /// Serialize a [Contact] to a vCard document (default 3.0).
  ///
  /// Pass [version] `'4.0'` to emit KIND/GENDER/ANNIVERSARY-friendly output.
  static String serialize(Contact contact, {String version = '3.0'}) {
    final buffer = StringBuffer();
    buffer.writeln('BEGIN:VCARD');
    buffer.writeln('VERSION:$version');
    if (contact.prodId != null && contact.prodId!.isNotEmpty) {
      buffer.writeln('PRODID:${VCardUtils.escapeText(contact.prodId!)}');
    }
    buffer.writeln('UID:${VCardUtils.escapeText(contact.uid)}');
    buffer.writeln('FN:${VCardUtils.escapeText(contact.formattedName)}');

    if (contact.name != null) {
      final n = contact.name!;
      buffer.writeln(
        'N:${[
          n.family,
          n.given,
          n.additional,
          n.prefix,
          n.suffix,
        ].map((p) => VCardUtils.escapeText(p ?? '')).join(';')}',
      );
    }

    if (contact.nicknames.isNotEmpty) {
      buffer.writeln(
        'NICKNAME:${contact.nicknames.map(VCardUtils.escapeText).join(',')}',
      );
    }

    for (final email in contact.emails) {
      buffer.writeln(_typedProperty('EMAIL', email));
    }
    for (final phone in contact.phones) {
      buffer.writeln(_typedProperty('TEL', phone));
    }

    var adrIndex = 0;
    for (final adr in contact.addresses) {
      adrIndex++;
      final group = adr.label != null ? 'item$adrIndex' : null;
      final typeParam = adr.types.isEmpty
          ? ''
          : ';TYPE=${adr.types.map((t) => t.toUpperCase()).join(',')}';
      final value = [
        adr.poBox,
        adr.extended,
        adr.street,
        adr.locality,
        adr.region,
        adr.postalCode,
        adr.country,
      ].map((p) => VCardUtils.escapeText(p ?? '')).join(';');
      final prefix = group != null ? '$group.' : '';
      buffer.writeln('${prefix}ADR$typeParam:$value');
      if (adr.label != null) {
        buffer.writeln(
          '${prefix}LABEL:${VCardUtils.escapeText(adr.label!)}',
        );
      }
    }

    if (contact.organization != null && contact.organization!.isNotEmpty) {
      buffer.writeln('ORG:${VCardUtils.escapeText(contact.organization!)}');
    }
    if (contact.title != null && contact.title!.isNotEmpty) {
      buffer.writeln('TITLE:${VCardUtils.escapeText(contact.title!)}');
    }
    if (contact.role != null && contact.role!.isNotEmpty) {
      buffer.writeln('ROLE:${VCardUtils.escapeText(contact.role!)}');
    }
    if (contact.note != null && contact.note!.isNotEmpty) {
      buffer.writeln('NOTE:${VCardUtils.escapeText(contact.note!)}');
    }
    for (final url in contact.urls) {
      buffer.writeln(_typedProperty('URL', url));
    }
    for (final impp in contact.impps) {
      final params = StringBuffer();
      if (impp.types.isNotEmpty) {
        params.write(
          ';TYPE=${impp.types.map((t) => t.toUpperCase()).join(',')}',
        );
      }
      if (impp.pref != null) params.write(';PREF=${impp.pref}');
      if (impp.serviceType != null) {
        params.write(
          ';X-SERVICE-TYPE=${VCardUtils.escapeText(impp.serviceType!)}',
        );
      }
      buffer.writeln('IMPP$params:${VCardUtils.escapeText(impp.uri)}');
    }
    if (contact.birthday != null && contact.birthday!.isNotEmpty) {
      buffer.writeln('BDAY:${contact.birthday}');
    }
    if (contact.anniversary != null && contact.anniversary!.isNotEmpty) {
      buffer.writeln('ANNIVERSARY:${contact.anniversary}');
    }
    if (contact.categories.isNotEmpty) {
      buffer.writeln(
        'CATEGORIES:${contact.categories.map(VCardUtils.escapeText).join(',')}',
      );
    }
    if (contact.photo != null) {
      buffer.writeln(_photoLine('PHOTO', contact.photo!));
    }
    if (contact.logo != null) {
      buffer.writeln(_photoLine('LOGO', contact.logo!));
    }
    if (contact.geo != null) {
      buffer.writeln('GEO:${contact.geo!.toVCard3Value()}');
    }
    if (contact.timeZone != null && contact.timeZone!.isNotEmpty) {
      buffer.writeln('TZ:${VCardUtils.escapeText(contact.timeZone!)}');
    }
    for (final lang in contact.languages) {
      buffer.writeln(_typedProperty('LANG', lang));
    }
    for (final rel in contact.related) {
      final typeParam = rel.types.isEmpty
          ? ''
          : ';TYPE=${rel.types.map((t) => t.toUpperCase()).join(',')}';
      final valueParam = rel.isUri ? ';VALUE=uri' : '';
      buffer.writeln(
        'RELATED$typeParam$valueParam:${VCardUtils.escapeText(rel.value)}',
      );
    }
    if (contact.gender != null) {
      buffer.writeln('GENDER:${contact.gender!.toVCardValue()}');
    }
    if (contact.kind != null && contact.kind!.isNotEmpty) {
      buffer.writeln('KIND:${VCardUtils.escapeText(contact.kind!)}');
    }
    for (final member in contact.members) {
      buffer.writeln('MEMBER:${VCardUtils.escapeText(member)}');
    }
    if (contact.rev != null && contact.rev!.isNotEmpty) {
      buffer.writeln('REV:${contact.rev}');
    }

    for (final extra in contact.extraProperties) {
      buffer.writeln(extra.toLine());
    }

    buffer.writeln('END:VCARD');
    return buffer.toString();
  }

  static VCardTypedValue _typed(ParsedVCardProperty prop) {
    final extra = Map<String, List<String>>.from(prop.params)
      ..remove('TYPE')
      ..remove('PREF');
    return VCardTypedValue(
      value: VCardUtils.unescapeText(prop.value),
      types: prop.types,
      pref: prop.pref,
      extraParams: extra,
    );
  }

  static VCardPhoto _parsePhoto(ParsedVCardProperty prop) {
    final mediaType = prop.params['MEDIATYPE']?.firstOrNull ??
        prop.types.where((t) => t.contains('/') || t.startsWith('IMAGE')).firstOrNull;
    final encoding = prop.params['ENCODING']?.firstOrNull;
    final isUri = _isUriValue(prop) ||
        prop.value.startsWith('http://') ||
        prop.value.startsWith('https://') ||
        prop.value.startsWith('data:');
    return VCardPhoto(
      value: prop.value.trim(),
      isUri: isUri,
      mediaType: mediaType,
      encoding: encoding,
    );
  }

  static bool _isUriValue(ParsedVCardProperty prop) {
    final valueParam = prop.params['VALUE']?.firstOrNull?.toUpperCase();
    return valueParam == 'URI';
  }

  static bool _isAddressType(String t) {
    const known = {
      'HOME',
      'WORK',
      'PREF',
      'VOICE',
      'FAX',
      'CELL',
      'MSG',
      'PAGER',
      'BBS',
      'MODEM',
      'CAR',
      'ISDN',
      'VIDEO',
      'TEXT',
      'TEXTPHONE',
      'MAIN',
      'OTHER',
      'INTERNET',
    };
    return known.contains(t.toUpperCase());
  }

  static VCardRawProperty _toRaw(ParsedVCardProperty prop) {
    return VCardRawProperty(
      name: prop.name,
      group: prop.group,
      params: prop.params,
      value: prop.value,
    );
  }

  static String _typedProperty(String name, VCardTypedValue value) {
    final params = StringBuffer();
    if (value.types.isNotEmpty) {
      params.write(
        ';TYPE=${value.types.map((t) => t.toUpperCase()).join(',')}',
      );
    }
    if (value.pref != null) {
      params.write(';PREF=${value.pref}');
    }
    value.extraParams.forEach((key, values) {
      if (values.isEmpty) {
        params.write(';$key');
      } else {
        params.write(';$key=${values.join(',')}');
      }
    });
    return '$name$params:${VCardUtils.escapeText(value.value)}';
  }

  static String _photoLine(String name, VCardPhoto photo) {
    final params = StringBuffer();
    if (photo.isUri) {
      params.write(';VALUE=uri');
    }
    if (photo.mediaType != null && photo.mediaType!.isNotEmpty) {
      if (photo.mediaType!.contains('/')) {
        params.write(';MEDIATYPE=${photo.mediaType}');
      } else {
        params.write(';TYPE=${photo.mediaType}');
      }
    }
    if (photo.encoding != null && photo.encoding!.isNotEmpty) {
      params.write(';ENCODING=${photo.encoding}');
    }
    // Binary PHOTO values are typically already base64; do not escape.
    if (photo.isUri) {
      return '$name$params:${photo.value}';
    }
    return '$name$params:${photo.value}';
  }

  static String _uidFromHref(Uri href) {
    final segment =
        href.pathSegments.isEmpty ? href.path : href.pathSegments.last;
    return segment.replaceAll(RegExp(r'\.vcf$', caseSensitive: false), '');
  }
}
