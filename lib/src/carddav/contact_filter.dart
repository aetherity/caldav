import 'vcard_utils.dart';

/// How a text match is applied in a CardDAV prop-filter (RFC 6352).
enum TextMatchType {
  /// Substring match (default).
  contains,

  /// Exact match.
  equals,

  /// Prefix match.
  startsWith,

  /// Suffix match.
  endsWith;

  /// Value for the `match-type` XML attribute.
  String get xmlValue => switch (this) {
        TextMatchType.contains => 'contains',
        TextMatchType.equals => 'equals',
        TextMatchType.startsWith => 'starts-with',
        TextMatchType.endsWith => 'ends-with',
      };
}

/// Combination logic for multiple prop-filters inside a CardDAV filter.
enum FilterLogic {
  /// All prop-filters must match (`test="allof"`, RFC default).
  all,

  /// Any prop-filter may match (`test="anyof"`).
  any;

  String get xmlValue => switch (this) {
        FilterLogic.all => 'allof',
        FilterLogic.any => 'anyof',
      };
}

/// A single vCard property filter for addressbook-query.
class PropFilter {
  /// vCard property name (e.g. `FN`, `EMAIL`, `TEL`).
  final String propertyName;

  /// Text to match; null when only testing defined/not-defined or TYPE.
  final String? text;

  /// Text match mode when [text] is set.
  final TextMatchType matchType;

  /// Collation for text-match (default: case-insensitive unicode).
  final String collation;

  /// When true, match contacts where the property is **not** defined.
  final bool isNotDefined;

  /// Optional TYPE param filter values (e.g. `HOME`, `WORK`, `CELL`).
  ///
  /// When non-empty, a `param-filter` on `TYPE` is added. Multiple values use
  /// `anyof` so any listed TYPE matches.
  final List<String> types;

  /// When true with [types], match when TYPE is not defined.
  final bool typeNotDefined;

  const PropFilter({
    required this.propertyName,
    this.text,
    this.matchType = TextMatchType.contains,
    this.collation = 'i;unicode-casemap',
    this.isNotDefined = false,
    this.types = const [],
    this.typeNotDefined = false,
  });

  /// Convenience: contains match on [propertyName].
  factory PropFilter.contains(String propertyName, String text) => PropFilter(
        propertyName: propertyName,
        text: text,
        matchType: TextMatchType.contains,
      );

  /// Convenience: exact match on [propertyName].
  factory PropFilter.equals(String propertyName, String text) => PropFilter(
        propertyName: propertyName,
        text: text,
        matchType: TextMatchType.equals,
      );

  /// Convenience: property must be present (any value).
  factory PropFilter.isDefined(String propertyName) => PropFilter(
        propertyName: propertyName,
      );

  /// Convenience: property must be absent.
  factory PropFilter.notDefined(String propertyName) => PropFilter(
        propertyName: propertyName,
        isNotDefined: true,
      );

  /// Build the `<C:prop-filter>` XML fragment.
  String toXml() {
    final name = VCardUtils.escapeXml(propertyName.toUpperCase());
    if (isNotDefined) {
      return '    <C:prop-filter name="$name">\n'
          '      <C:is-not-defined/>\n'
          '    </C:prop-filter>';
    }

    final children = StringBuffer();

    if (text != null) {
      final escaped = VCardUtils.escapeXml(text!);
      children.writeln(
        '      <C:text-match collation="${VCardUtils.escapeXml(collation)}" '
        'match-type="${matchType.xmlValue}">$escaped</C:text-match>',
      );
    }

    if (typeNotDefined) {
      children.writeln('      <C:param-filter name="TYPE">');
      children.writeln('        <C:is-not-defined/>');
      children.writeln('      </C:param-filter>');
    } else if (types.isNotEmpty) {
      final testAttr = types.length > 1 ? ' test="anyof"' : '';
      children.writeln('      <C:param-filter name="TYPE"$testAttr>');
      for (final type in types) {
        final t = VCardUtils.escapeXml(type.toUpperCase());
        children.writeln(
          '        <C:text-match collation="i;octet">$t</C:text-match>',
        );
      }
      children.writeln('      </C:param-filter>');
    }

    if (children.isEmpty) {
      // Defined with any value — empty prop-filter matches presence.
      return '    <C:prop-filter name="$name"/>';
    }

    return '    <C:prop-filter name="$name">\n'
        '$children'
        '    </C:prop-filter>';
  }
}

/// High-level CardDAV addressbook-query filter.
///
/// Examples:
/// ```dart
/// // Name contains "Jane"
/// ContactFilter.name('Jane')
///
/// // Email equals
/// ContactFilter.email('jane@example.com', matchType: TextMatchType.equals)
///
/// // FN or EMAIL or TEL contains text (common "search box" filter)
/// ContactFilter.anyText('jane')
///
/// // Custom multi-filter
/// ContactFilter(
///   filters: [
///     PropFilter.contains('ORG', 'Acme'),
///     PropFilter(propertyName: 'EMAIL', types: ['WORK']),
///   ],
///   logic: FilterLogic.all,
/// )
/// ```
class ContactFilter {
  /// Individual property filters.
  final List<PropFilter> filters;

  /// How [filters] are combined.
  final FilterLogic logic;

  /// Optional result limit (`limit` / `nresults` in addressbook-query).
  final int? limit;

  const ContactFilter({
    required this.filters,
    this.logic = FilterLogic.all,
    this.limit,
  });

  /// Search formatted name (`FN`).
  factory ContactFilter.name(
    String text, {
    TextMatchType matchType = TextMatchType.contains,
    int? limit,
  }) =>
      ContactFilter(
        filters: [
          PropFilter(
            propertyName: 'FN',
            text: text,
            matchType: matchType,
          ),
        ],
        limit: limit,
      );

  /// Search email (`EMAIL`).
  factory ContactFilter.email(
    String text, {
    TextMatchType matchType = TextMatchType.contains,
    List<String> types = const [],
    int? limit,
  }) =>
      ContactFilter(
        filters: [
          PropFilter(
            propertyName: 'EMAIL',
            text: text,
            matchType: matchType,
            types: types,
          ),
        ],
        limit: limit,
      );

  /// Search telephone (`TEL`).
  factory ContactFilter.phone(
    String text, {
    TextMatchType matchType = TextMatchType.contains,
    List<String> types = const [],
    int? limit,
  }) =>
      ContactFilter(
        filters: [
          PropFilter(
            propertyName: 'TEL',
            text: text,
            matchType: matchType,
            types: types,
          ),
        ],
        limit: limit,
      );

  /// Search organization (`ORG`).
  factory ContactFilter.organization(
    String text, {
    TextMatchType matchType = TextMatchType.contains,
    int? limit,
  }) =>
      ContactFilter(
        filters: [
          PropFilter(
            propertyName: 'ORG',
            text: text,
            matchType: matchType,
          ),
        ],
        limit: limit,
      );

  /// Search categories (`CATEGORIES`).
  factory ContactFilter.category(
    String text, {
    TextMatchType matchType = TextMatchType.contains,
    int? limit,
  }) =>
      ContactFilter(
        filters: [
          PropFilter(
            propertyName: 'CATEGORIES',
            text: text,
            matchType: matchType,
          ),
        ],
        limit: limit,
      );

  /// Common “search box” filter: match [text] against FN, EMAIL, or TEL.
  factory ContactFilter.anyText(
    String text, {
    TextMatchType matchType = TextMatchType.contains,
    int? limit,
  }) =>
      ContactFilter(
        filters: [
          PropFilter(propertyName: 'FN', text: text, matchType: matchType),
          PropFilter(propertyName: 'EMAIL', text: text, matchType: matchType),
          PropFilter(propertyName: 'TEL', text: text, matchType: matchType),
        ],
        logic: FilterLogic.any,
        limit: limit,
      );

  /// Match by vCard UID (exact).
  factory ContactFilter.uid(String uid) => ContactFilter(
        filters: [
          PropFilter(
            propertyName: 'UID',
            text: uid,
            matchType: TextMatchType.equals,
            collation: 'i;octet',
          ),
        ],
      );

  /// Build a full `addressbook-query` REPORT body.
  String toAddressbookQueryXml() {
    final filterBody = filters.map((f) => f.toXml()).join('\n');
    final testAttr =
        filters.length > 1 ? ' test="${logic.xmlValue}"' : '';
    final limitXml = limit != null
        ? '  <C:limit>\n    <C:nresults>$limit</C:nresults>\n  </C:limit>\n'
        : '';

    return '''<?xml version="1.0" encoding="utf-8"?>
<C:addressbook-query xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:carddav">
  <D:prop>
    <D:getetag/>
    <C:address-data/>
  </D:prop>
  <C:filter$testAttr>
$filterBody
  </C:filter>
$limitXml</C:addressbook-query>''';
  }
}
