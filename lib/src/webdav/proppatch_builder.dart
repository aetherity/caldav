import 'xml_namespaces.dart';

/// Builder for PROPPATCH request XML bodies (RFC 4918 §9.2).
///
/// Supports both `<D:set>` and `<D:remove>` operations. Sets are emitted
/// before removes when both are present.
class ProppatchBuilder {
  final List<_SetProperty> _setProperties = [];
  final List<_RemoveProperty> _removeProperties = [];

  /// Set a DAV: property to a text value.
  ProppatchBuilder setDavProperty(String name, String value) {
    _setProperties.add(_SetProperty(name, XmlNamespaces.dav, 'D', value));
    return this;
  }

  /// Set a CalDAV property to a text value.
  ProppatchBuilder setCalDavProperty(String name, String value) {
    _setProperties.add(_SetProperty(name, XmlNamespaces.caldav, 'C', value));
    return this;
  }

  /// Set a CardDAV property to a text value.
  ProppatchBuilder setCardDavProperty(String name, String value) {
    _setProperties.add(_SetProperty(name, XmlNamespaces.carddav, 'CARD', value));
    return this;
  }

  /// Set an Apple namespace property to a text value.
  ProppatchBuilder setAppleProperty(String name, String value) {
    _setProperties.add(_SetProperty(name, XmlNamespaces.apple, 'A', value));
    return this;
  }

  /// Set a custom namespaced property to a text value.
  ProppatchBuilder setProperty(
    String name,
    String namespace,
    String prefix,
    String value,
  ) {
    _setProperties.add(_SetProperty(name, namespace, prefix, value));
    return this;
  }

  /// Set a property using a raw inner XML fragment (already escaped/built).
  ///
  /// Use for complex property values that are not plain text.
  ProppatchBuilder setPropertyRaw(
    String name,
    String namespace,
    String prefix,
    String innerXml,
  ) {
    _setProperties.add(
      _SetProperty(name, namespace, prefix, innerXml, rawInner: true),
    );
    return this;
  }

  /// Remove a DAV: property.
  ProppatchBuilder removeDavProperty(String name) {
    _removeProperties.add(_RemoveProperty(name, XmlNamespaces.dav, 'D'));
    return this;
  }

  /// Remove a CalDAV property.
  ProppatchBuilder removeCalDavProperty(String name) {
    _removeProperties.add(_RemoveProperty(name, XmlNamespaces.caldav, 'C'));
    return this;
  }

  /// Remove a CardDAV property.
  ProppatchBuilder removeCardDavProperty(String name) {
    _removeProperties.add(_RemoveProperty(name, XmlNamespaces.carddav, 'CARD'));
    return this;
  }

  /// Remove an Apple namespace property.
  ProppatchBuilder removeAppleProperty(String name) {
    _removeProperties.add(_RemoveProperty(name, XmlNamespaces.apple, 'A'));
    return this;
  }

  /// Remove a custom namespaced property.
  ProppatchBuilder removeProperty(String name, String namespace, String prefix) {
    _removeProperties.add(_RemoveProperty(name, namespace, prefix));
    return this;
  }

  /// Build the PROPPATCH XML body.
  ///
  /// Throws [StateError] if neither set nor remove operations were added.
  String build() {
    if (_setProperties.isEmpty && _removeProperties.isEmpty) {
      throw StateError(
        'ProppatchBuilder requires at least one set or remove operation',
      );
    }

    final namespaces = <String, String>{'D': XmlNamespaces.dav};
    final buffer = StringBuffer();

    if (_setProperties.isNotEmpty) {
      buffer.writeln('  <D:set>');
      buffer.writeln('    <D:prop>');
      for (final prop in _setProperties) {
        namespaces[prop.prefix] = prop.namespace;
        if (prop.rawInner) {
          buffer.writeln(
            '      <${prop.prefix}:${prop.name}>${prop.value}</${prop.prefix}:${prop.name}>',
          );
        } else {
          buffer.writeln(
            '      <${prop.prefix}:${prop.name}>${_escapeXml(prop.value)}</${prop.prefix}:${prop.name}>',
          );
        }
      }
      buffer.writeln('    </D:prop>');
      buffer.writeln('  </D:set>');
    }

    if (_removeProperties.isNotEmpty) {
      buffer.writeln('  <D:remove>');
      buffer.writeln('    <D:prop>');
      for (final prop in _removeProperties) {
        namespaces[prop.prefix] = prop.namespace;
        buffer.writeln('      <${prop.prefix}:${prop.name}/>');
      }
      buffer.writeln('    </D:prop>');
      buffer.writeln('  </D:remove>');
    }

    final nsDeclarations = namespaces.entries
        .map((e) => 'xmlns:${e.key}="${e.value}"')
        .join(' ');

    return '''<?xml version="1.0" encoding="utf-8"?>
<D:propertyupdate $nsDeclarations>
$buffer</D:propertyupdate>''';
  }

  static String _escapeXml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}

class _SetProperty {
  final String name;
  final String namespace;
  final String prefix;
  final String value;
  final bool rawInner;

  const _SetProperty(
    this.name,
    this.namespace,
    this.prefix,
    this.value, {
    this.rawInner = false,
  });
}

class _RemoveProperty {
  final String name;
  final String namespace;
  final String prefix;

  const _RemoveProperty(this.name, this.namespace, this.prefix);
}
