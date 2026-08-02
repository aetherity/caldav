/// Result of CalDAV endpoint discovery (RFC 6764 / RFC 4791).
class DiscoveryResult {
  /// CalDAV endpoint URL (from well-known or base URL).
  final Uri caldavEndpoint;

  /// Current user's principal URL.
  final Uri principalUrl;

  /// Calendar home set URL (where calendars are stored).
  final Uri calendarHomeSet;

  /// User's display name (if available).
  final String? displayName;

  /// URLs from `CALDAV:calendar-free-busy-set` (if advertised).
  final List<Uri> freeBusySet;

  /// Scheduling Outbox URL (`CALDAV:schedule-outbox-URL`), if available.
  final Uri? scheduleOutboxUrl;

  /// Scheduling Inbox URL (`CALDAV:schedule-inbox-URL`), if available.
  final Uri? scheduleInboxUrl;

  /// Calendar user addresses (`CALDAV:calendar-user-address-set`), e.g. mailto:.
  final List<String> calendarUserAddresses;

  const DiscoveryResult({
    required this.caldavEndpoint,
    required this.principalUrl,
    required this.calendarHomeSet,
    this.displayName,
    this.freeBusySet = const [],
    this.scheduleOutboxUrl,
    this.scheduleInboxUrl,
    this.calendarUserAddresses = const [],
  });

  @override
  String toString() {
    return 'DiscoveryResult('
        'caldavEndpoint: $caldavEndpoint, '
        'principalUrl: $principalUrl, '
        'calendarHomeSet: $calendarHomeSet, '
        'displayName: $displayName, '
        'freeBusySet: ${freeBusySet.length}, '
        'scheduleOutboxUrl: $scheduleOutboxUrl)';
  }
}

/// Result of CardDAV endpoint discovery (RFC 6764 / RFC 6352).
class CardDavDiscoveryResult {
  /// CardDAV endpoint URL (from well-known or base URL).
  final Uri carddavEndpoint;

  /// Current user's principal URL.
  final Uri principalUrl;

  /// Address book home set URL (where address books are stored).
  final Uri addressbookHomeSet;

  /// User's display name (if available).
  final String? displayName;

  const CardDavDiscoveryResult({
    required this.carddavEndpoint,
    required this.principalUrl,
    required this.addressbookHomeSet,
    this.displayName,
  });

  @override
  String toString() {
    return 'CardDavDiscoveryResult('
        'carddavEndpoint: $carddavEndpoint, '
        'principalUrl: $principalUrl, '
        'addressbookHomeSet: $addressbookHomeSet, '
        'displayName: $displayName)';
  }
}
