import 'package:xml/xml.dart';

import 'xml_namespaces.dart';

/// Represents a WebDAV multistatus response (RFC 4918 §13 / RFC 6578).
class MultiStatus {
  final List<DavResponse> responses;

  /// Optional top-level response description.
  final String? responseDescription;

  /// Opaque collection sync token when returned (RFC 6578).
  final String? syncToken;

  const MultiStatus(
    this.responses, {
    this.responseDescription,
    this.syncToken,
  });

  /// Parse multistatus XML response.
  factory MultiStatus.fromXml(String xmlString) {
    final document = XmlDocument.parse(xmlString);
    final multistatusElement = document.rootElement;

    final responses = multistatusElement
        .findElements('response', namespaceUri: XmlNamespaces.dav)
        .map(DavResponse.fromXml)
        .toList();

    final responseDescription = multistatusElement
        .findElements('responsedescription', namespaceUri: XmlNamespaces.dav)
        .firstOrNull
        ?.innerText;

    // RFC 6578: sync-token is a direct child of multistatus (not a response).
    final syncToken = multistatusElement
        .findElements('sync-token', namespaceUri: XmlNamespaces.dav)
        .firstOrNull
        ?.innerText
        .trim();

    return MultiStatus(
      responses,
      responseDescription: responseDescription,
      syncToken: (syncToken == null || syncToken.isEmpty) ? null : syncToken,
    );
  }

  /// Check if all member responses are successful (2xx status).
  ///
  /// Truncation markers (507 + number-of-matches-within-limits) are ignored
  /// so partial sync responses still report member success accurately.
  bool get isSuccess => responses
      .where((r) => !r.isTruncationMarker)
      .every((r) => r.isSuccess || r.isDeleted);

  /// True when the server indicated more results are available (RFC 6578).
  bool get isTruncated => responses.any((r) => r.isTruncationMarker);

  /// Get first response (useful for single resource requests).
  DavResponse? get first => responses.isNotEmpty ? responses.first : null;
}

/// Represents a single response in multistatus.
///
/// A response may carry property results via [propStats], a response-level
/// [status] (e.g. failed COPY of one member), or both (RFC 4918 §14.24).
class DavResponse {
  final String href;
  final List<PropStat> propStats;

  /// Response-level HTTP status line when present (without propstat).
  final String? status;

  /// Parsed response-level status code, or `null` if absent.
  final int? statusCode;

  /// Optional human-readable description for this response.
  final String? responseDescription;

  /// Optional DAV error condition element names (local names under `DAV:error`).
  final List<String> errors;

  /// Optional `DAV:location` href (e.g. after certain operations).
  final String? locationHref;

  const DavResponse({
    required this.href,
    required this.propStats,
    this.status,
    this.statusCode,
    this.responseDescription,
    this.errors = const [],
    this.locationHref,
  });

  factory DavResponse.fromXml(XmlElement element) {
    final href = element
            .findElements('href', namespaceUri: XmlNamespaces.dav)
            .firstOrNull
            ?.innerText ??
        '';

    final propStats = element
        .findElements('propstat', namespaceUri: XmlNamespaces.dav)
        .map(PropStat.fromXml)
        .toList();

    // Response-level status (sibling of propstat), not nested in propstat.
    String? status;
    int? statusCode;
    for (final child in element.childElements) {
      if (child.localName == 'status' &&
          child.namespaceUri == XmlNamespaces.dav) {
        status = child.innerText;
        statusCode = _parseStatusCode(status);
        break;
      }
    }

    final responseDescription = element
        .findElements('responsedescription', namespaceUri: XmlNamespaces.dav)
        .firstOrNull
        ?.innerText;

    final errorElement = element
        .findElements('error', namespaceUri: XmlNamespaces.dav)
        .firstOrNull;
    final errors = errorElement?.childElements
            .map((e) => e.localName)
            .toList() ??
        const <String>[];

    final locationHref = element
        .findElements('location', namespaceUri: XmlNamespaces.dav)
        .firstOrNull
        ?.findElements('href', namespaceUri: XmlNamespaces.dav)
        .firstOrNull
        ?.innerText;

    return DavResponse(
      href: href,
      propStats: propStats,
      status: status,
      statusCode: statusCode,
      responseDescription: responseDescription,
      errors: errors,
      locationHref: locationHref,
    );
  }

  /// Whether this response indicates overall success.
  ///
  /// Prefer propstat success when present; otherwise use response-level status.
  /// An empty response with neither is treated as unsuccessful.
  bool get isSuccess {
    if (propStats.isNotEmpty) {
      return propStats.any((ps) => ps.isSuccess);
    }
    final code = statusCode;
    if (code != null) {
      return code >= 200 && code < 300;
    }
    return false;
  }

  /// Whether this reports a deleted collection member (RFC 6578).
  ///
  /// Deleted members are typically response-level `404 Not Found` without
  /// successful propstats (sometimes with empty propstat 404).
  bool get isDeleted {
    if (statusCode == 404) return true;
    if (propStats.isNotEmpty &&
        propStats.every((ps) => ps.statusCode == 404) &&
        !propStats.any((ps) => ps.isSuccess)) {
      return true;
    }
    return false;
  }

  /// Whether this is the RFC 6578 truncation marker response
  /// (`507` + `number-of-matches-within-limits`).
  bool get isTruncationMarker {
    final code = statusCode;
    final hasError = errors.contains('number-of-matches-within-limits') ||
        propStats.any(
          (ps) => ps.errors.contains('number-of-matches-within-limits'),
        );
    if (hasError) return true;
    return code == 507;
  }

  /// Get first successful propstat.
  PropStat? get successPropStat =>
      propStats.where((ps) => ps.isSuccess).firstOrNull;

  /// Get property value by local name and namespace.
  String? getProperty(String localName, {String? namespace}) {
    for (final propStat in propStats) {
      if (!propStat.isSuccess) continue;
      final value = propStat.getProperty(localName, namespace: namespace);
      if (value != null) return value;
    }
    return null;
  }

  /// Get property element by local name and namespace.
  XmlElement? getPropertyElement(String localName, {String? namespace}) {
    for (final propStat in propStats) {
      if (!propStat.isSuccess) continue;
      final element = propStat.getPropertyElement(localName, namespace: namespace);
      if (element != null) return element;
    }
    return null;
  }

  /// Check if resource has a specific resourcetype child element.
  bool hasResourceType(String typeName, {String? namespace}) {
    final resourceType =
        getPropertyElement('resourcetype', namespace: XmlNamespaces.dav);
    if (resourceType == null) return false;

    return resourceType.childElements.any((e) =>
        e.localName == typeName &&
        (namespace == null || e.namespaceUri == namespace));
  }

  /// Whether this is a calendar collection (CalDAV).
  bool get isCalendar =>
      hasResourceType('calendar', namespace: XmlNamespaces.caldav);

  /// Whether this is an address book collection (CardDAV).
  bool get isAddressBook =>
      hasResourceType('addressbook', namespace: XmlNamespaces.carddav);

  /// Whether this is a collection (directory).
  bool get isCollection =>
      hasResourceType('collection', namespace: XmlNamespaces.dav);
}

/// Represents propstat (property + status) in a response.
class PropStat {
  final XmlElement? propElement;
  final String status;
  final int statusCode;

  /// Optional description for this propstat.
  final String? responseDescription;

  /// Optional DAV error condition local names.
  final List<String> errors;

  const PropStat({
    this.propElement,
    required this.status,
    required this.statusCode,
    this.responseDescription,
    this.errors = const [],
  });

  factory PropStat.fromXml(XmlElement element) {
    final propElement =
        element.findElements('prop', namespaceUri: XmlNamespaces.dav).firstOrNull;

    final status = element
            .findElements('status', namespaceUri: XmlNamespaces.dav)
            .firstOrNull
            ?.innerText ??
        '';

    final statusCode = _parseStatusCode(status);

    final responseDescription = element
        .findElements('responsedescription', namespaceUri: XmlNamespaces.dav)
        .firstOrNull
        ?.innerText;

    final errorElement =
        element.findElements('error', namespaceUri: XmlNamespaces.dav).firstOrNull;
    final errors = errorElement?.childElements
            .map((e) => e.localName)
            .toList() ??
        const <String>[];

    return PropStat(
      propElement: propElement,
      status: status,
      statusCode: statusCode,
      responseDescription: responseDescription,
      errors: errors,
    );
  }

  /// Whether status is successful (2xx).
  bool get isSuccess => statusCode >= 200 && statusCode < 300;

  /// Get property text value by local name.
  String? getProperty(String localName, {String? namespace}) {
    return getPropertyElement(localName, namespace: namespace)?.innerText;
  }

  /// Get property element by local name.
  XmlElement? getPropertyElement(String localName, {String? namespace}) {
    if (propElement == null) return null;

    for (final child in propElement!.childElements) {
      if (child.localName == localName) {
        if (namespace == null || child.namespaceUri == namespace) {
          return child;
        }
      }
    }
    return null;
  }
}

int _parseStatusCode(String status) {
  // "HTTP/1.1 200 OK" -> 200
  final match = RegExp(r'HTTP/\d\.\d\s+(\d+)').firstMatch(status);
  if (match != null) {
    return int.tryParse(match.group(1)!) ?? 0;
  }
  return 0;
}
