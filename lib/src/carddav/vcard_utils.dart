/// Utilities for vCard text escaping, line folding, and property parsing.
class VCardUtils {
  VCardUtils._();

  /// Escape special characters in vCard text values (RFC 6350 §3.4).
  static String escapeText(String text) {
    return text
        .replaceAll('\\', '\\\\')
        .replaceAll('\n', '\\n')
        .replaceAll(',', '\\,')
        .replaceAll(';', '\\;');
  }

  /// Unescape vCard text values.
  static String unescapeText(String text) {
    final buffer = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      if (text[i] == '\\' && i + 1 < text.length) {
        final next = text[i + 1];
        switch (next) {
          case 'n':
          case 'N':
            buffer.write('\n');
          case ',':
            buffer.write(',');
          case ';':
            buffer.write(';');
          case '\\':
            buffer.write('\\');
          default:
            buffer.write(next);
        }
        i++;
      } else {
        buffer.write(text[i]);
      }
    }
    return buffer.toString();
  }

  /// Escape XML special characters.
  static String escapeXml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  /// Unfold folded vCard lines (RFC 6350 §3.2).
  ///
  /// Continuation lines start with a single SPACE or HTAB.
  static String unfold(String input) {
    final normalized = input.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    return normalized.replaceAll(RegExp(r'\n[ \t]'), '');
  }

  /// Fold long lines at 75 octets (approx) for vCard serialization.
  static String foldLine(String line, {int maxLength = 75}) {
    if (line.length <= maxLength) return line;
    final buffer = StringBuffer();
    var remaining = line;
    var first = true;
    while (remaining.length > maxLength) {
      final take = first ? maxLength : maxLength - 1;
      buffer.writeln(remaining.substring(0, take));
      remaining = remaining.substring(take);
      if (!first || remaining.isNotEmpty) {
        // Continuation lines are prefixed with a space after the newline.
        // StringBuffer.writeln already added \n; prefix next chunk with space
        // by prepending to remaining for subsequent iterations via writing ' '.
      }
      if (remaining.isNotEmpty) {
        remaining = ' $remaining';
      }
      first = false;
      // After first fold, subsequent chunks include the leading space in length.
      maxLength = 75; // keep stable
    }
    buffer.write(remaining);
    return buffer.toString();
  }

  /// Split a property line into name, params map, and value.
  ///
  /// Input must already be unfolded. Returns null if the line is not a property.
  static ParsedVCardProperty? parsePropertyLine(String line) {
    if (line.isEmpty) return null;

    final colon = line.indexOf(':');
    if (colon <= 0) return null;

    final nameAndParams = line.substring(0, colon);
    final value = line.substring(colon + 1);

    final parts = nameAndParams.split(';');
    var name = parts.first;
    // Group prefix: "item1.EMAIL"
    final groupDot = name.lastIndexOf('.');
    String? group;
    if (groupDot > 0) {
      group = name.substring(0, groupDot);
      name = name.substring(groupDot + 1);
    }

    final params = <String, List<String>>{};
    for (var i = 1; i < parts.length; i++) {
      final p = parts[i];
      final eq = p.indexOf('=');
      if (eq <= 0) {
        // Bare TYPE-style param (vCard 2.1): WORK
        params.putIfAbsent('TYPE', () => []).add(p.toUpperCase());
        continue;
      }
      final key = p.substring(0, eq).toUpperCase();
      final rawVal = p.substring(eq + 1);
      // TYPE=HOME,WORK or quoted values
      for (final v in _splitParamValues(rawVal)) {
        params.putIfAbsent(key, () => []).add(v);
      }
    }

    return ParsedVCardProperty(
      name: name.toUpperCase(),
      group: group,
      params: params,
      value: value,
    );
  }

  static List<String> _splitParamValues(String raw) {
    // Strip surrounding quotes if present.
    if (raw.startsWith('"') && raw.endsWith('"') && raw.length >= 2) {
      return [raw.substring(1, raw.length - 1)];
    }
    return raw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  }
}

/// A single unfolded vCard property.
class ParsedVCardProperty {
  final String name;
  final String? group;
  final Map<String, List<String>> params;
  final String value;

  const ParsedVCardProperty({
    required this.name,
    this.group,
    required this.params,
    required this.value,
  });

  List<String> get types =>
      (params['TYPE'] ?? []).map((t) => t.toUpperCase()).toList();

  int? get pref {
    final values = params['PREF'];
    if (values == null || values.isEmpty) return null;
    return int.tryParse(values.first);
  }
}
