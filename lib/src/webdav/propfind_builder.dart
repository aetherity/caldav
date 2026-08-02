import 'xml_namespaces.dart';

/// Builder for PROPFIND request XML bodies (RFC 4918 §9.1).
class PropfindBuilder {
  final List<_Property> _properties = [];

  /// Add a DAV property.
  PropfindBuilder addDavProperty(String name) {
    _properties.add(_Property(name, XmlNamespaces.dav, 'D'));
    return this;
  }

  /// Add a CalDAV property.
  PropfindBuilder addCalDavProperty(String name) {
    _properties.add(_Property(name, XmlNamespaces.caldav, 'C'));
    return this;
  }

  /// Add a CardDAV property.
  PropfindBuilder addCardDavProperty(String name) {
    _properties.add(_Property(name, XmlNamespaces.carddav, 'CARD'));
    return this;
  }

  /// Add an Apple namespace property.
  PropfindBuilder addAppleProperty(String name) {
    _properties.add(_Property(name, XmlNamespaces.apple, 'A'));
    return this;
  }

  /// Add a CalendarServer namespace property.
  PropfindBuilder addCalendarServerProperty(String name) {
    _properties.add(_Property(name, XmlNamespaces.calendarServer, 'CS'));
    return this;
  }

  /// Add a custom property with namespace.
  PropfindBuilder addProperty(String name, String namespace, String prefix) {
    _properties.add(_Property(name, namespace, prefix));
    return this;
  }

  /// Build the PROPFIND XML body with an explicit property list.
  String build() {
    final namespaces = <String, String>{};
    final props = StringBuffer();

    // Always include DAV namespace
    namespaces['D'] = XmlNamespaces.dav;

    for (final prop in _properties) {
      namespaces[prop.prefix] = prop.namespace;
      props.writeln('      <${prop.prefix}:${prop.name}/>');
    }

    final nsDeclarations = namespaces.entries
        .map((e) => 'xmlns:${e.key}="${e.value}"')
        .join(' ');

    return '''<?xml version="1.0" encoding="utf-8"?>
<D:propfind $nsDeclarations>
  <D:prop>
$props  </D:prop>
</D:propfind>''';
  }

  /// Build allprop request.
  static String allprop() {
    return '''<?xml version="1.0" encoding="utf-8"?>
<D:propfind xmlns:D="DAV:">
  <D:allprop/>
</D:propfind>''';
  }

  /// Build allprop request that also includes live properties not in allprop.
  ///
  /// [extraProperties] is a list of fully-formed property elements, e.g.
  /// `['<C:calendar-data xmlns:C="urn:ietf:params:xml:ns:caldav"/>']`.
  static String allpropWithInclude(List<String> extraProperties) {
    final include = extraProperties.map((p) => '    $p').join('\n');
    return '''<?xml version="1.0" encoding="utf-8"?>
<D:propfind xmlns:D="DAV:">
  <D:allprop/>
  <D:include>
$include
  </D:include>
</D:propfind>''';
  }

  /// Build propname request (list available property names).
  static String propname() {
    return '''<?xml version="1.0" encoding="utf-8"?>
<D:propfind xmlns:D="DAV:">
  <D:propname/>
</D:propfind>''';
  }

  /// Preset: current-user-principal discovery.
  static String currentUserPrincipal() {
    return PropfindBuilder()
        .addDavProperty('current-user-principal')
        .build();
  }

  /// Preset: calendar-home-set discovery.
  static String calendarHomeSet() {
    return PropfindBuilder()
        .addCalDavProperty('calendar-home-set')
        .build();
  }

  /// Preset: addressbook-home-set discovery (CardDAV).
  static String addressbookHomeSet() {
    return PropfindBuilder()
        .addCardDavProperty('addressbook-home-set')
        .build();
  }

  /// Preset: generic WebDAV resource properties.
  static String resourceProperties() {
    return PropfindBuilder()
        .addDavProperty('resourcetype')
        .addDavProperty('displayname')
        .addDavProperty('getetag')
        .addDavProperty('getcontenttype')
        .addDavProperty('getcontentlength')
        .addDavProperty('getlastmodified')
        .addDavProperty('creationdate')
        .addDavProperty('current-user-privilege-set')
        .build();
  }

  /// Preset: calendar collection properties.
  static String calendarProperties() {
    return PropfindBuilder()
        .addDavProperty('resourcetype')
        .addDavProperty('displayname')
        .addDavProperty('geteuid')
        .addDavProperty('current-user-privilege-set')
        .addDavProperty('sync-token')
        .addCalDavProperty('calendar-description')
        .addCalDavProperty('calendar-timezone')
        .addCalDavProperty('supported-calendar-component-set')
        .addAppleProperty('calendar-color')
        .addCalendarServerProperty('getctag')
        .build();
  }

  /// Preset: address book collection properties (CardDAV).
  static String addressbookProperties() {
    return PropfindBuilder()
        .addDavProperty('resourcetype')
        .addDavProperty('displayname')
        .addDavProperty('getetag')
        .addDavProperty('current-user-privilege-set')
        .addDavProperty('sync-token')
        .addCardDavProperty('addressbook-description')
        .addCardDavProperty('supported-address-data')
        .addCalendarServerProperty('getctag')
        .build();
  }
}

class _Property {
  final String name;
  final String namespace;
  final String prefix;

  const _Property(this.name, this.namespace, this.prefix);
}
