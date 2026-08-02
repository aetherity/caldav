/// Free/busy period type (RFC 5545 FBTYPE).
enum FreeBusyType {
  /// Available / free time.
  free,

  /// Busy (default when FBTYPE is omitted).
  busy,

  /// Busy — unavailable (e.g. out of office).
  busyUnavailable,

  /// Busy — tentative.
  busyTentative;

  /// Parse an FBTYPE parameter value.
  static FreeBusyType parse(String? value) {
    switch (value?.toUpperCase()) {
      case 'FREE':
        return FreeBusyType.free;
      case 'BUSY-UNAVAILABLE':
        return FreeBusyType.busyUnavailable;
      case 'BUSY-TENTATIVE':
        return FreeBusyType.busyTentative;
      case 'BUSY':
      case null:
      case '':
      default:
        return FreeBusyType.busy;
    }
  }

  /// iCalendar FBTYPE token.
  String get icalValue => switch (this) {
        FreeBusyType.free => 'FREE',
        FreeBusyType.busy => 'BUSY',
        FreeBusyType.busyUnavailable => 'BUSY-UNAVAILABLE',
        FreeBusyType.busyTentative => 'BUSY-TENTATIVE',
      };

  /// True for any busy-like type (not free).
  bool get isBusy => this != FreeBusyType.free;
}

/// A single free/busy time period.
class FreeBusyPeriod {
  /// Inclusive start (UTC).
  final DateTime start;

  /// Exclusive end (UTC), per iCalendar period conventions.
  final DateTime end;

  /// Busy type for this period.
  final FreeBusyType type;

  const FreeBusyPeriod({
    required this.start,
    required this.end,
    this.type = FreeBusyType.busy,
  });

  /// Duration of the period.
  Duration get duration => end.difference(start);

  FreeBusyPeriod copyWith({
    DateTime? start,
    DateTime? end,
    FreeBusyType? type,
  }) {
    return FreeBusyPeriod(
      start: start ?? this.start,
      end: end ?? this.end,
      type: type ?? this.type,
    );
  }

  @override
  String toString() =>
      'FreeBusyPeriod($type, $start – $end)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FreeBusyPeriod &&
        other.start == start &&
        other.end == end &&
        other.type == type;
  }

  @override
  int get hashCode => Object.hash(start, end, type);
}

/// A free/busy response (RFC 5545 VFREEBUSY).
///
/// Produced by [CALDAV:free-busy-query](https://datatracker.ietf.org/doc/html/rfc4791#section-7.10)
/// or by scheduling freebusy replies (RFC 6638).
class FreeBusy {
  /// Optional UID of the VFREEBUSY component.
  final String? uid;

  /// Range start (DTSTART), if present.
  final DateTime? dtstart;

  /// Range end (DTEND), if present.
  final DateTime? dtend;

  /// Free/busy periods (typically only busy intervals are listed).
  final List<FreeBusyPeriod> periods;

  /// ORGANIZER calendar user address (e.g. `mailto:user@example.com`).
  final String? organizer;

  /// ATTENDEE addresses from the component.
  final List<String> attendees;

  /// URL of the collection this freebusy was queried from, if known.
  final Uri? sourceUrl;

  /// Raw iCalendar payload when available.
  final String? rawIcalendar;

  const FreeBusy({
    this.uid,
    this.dtstart,
    this.dtend,
    this.periods = const [],
    this.organizer,
    this.attendees = const [],
    this.sourceUrl,
    this.rawIcalendar,
  });

  /// Periods that are busy (any non-FREE type).
  List<FreeBusyPeriod> get busyPeriods =>
      periods.where((p) => p.type.isBusy).toList(growable: false);

  /// Periods explicitly marked FREE.
  List<FreeBusyPeriod> get freePeriods =>
      periods.where((p) => p.type == FreeBusyType.free).toList(growable: false);

  /// Whether [instant] falls in any busy period.
  bool isBusyAt(DateTime instant) {
    final t = instant.toUtc();
    return busyPeriods.any((p) => !t.isBefore(p.start) && t.isBefore(p.end));
  }

  /// Busy periods that overlap `[start, end)`.
  List<FreeBusyPeriod> busyInRange(DateTime start, DateTime end) {
    final s = start.toUtc();
    final e = end.toUtc();
    return busyPeriods
        .where((p) => p.start.isBefore(e) && p.end.isAfter(s))
        .toList(growable: false);
  }

  FreeBusy copyWith({
    String? uid,
    DateTime? dtstart,
    DateTime? dtend,
    List<FreeBusyPeriod>? periods,
    String? organizer,
    List<String>? attendees,
    Uri? sourceUrl,
    String? rawIcalendar,
  }) {
    return FreeBusy(
      uid: uid ?? this.uid,
      dtstart: dtstart ?? this.dtstart,
      dtend: dtend ?? this.dtend,
      periods: periods ?? this.periods,
      organizer: organizer ?? this.organizer,
      attendees: attendees ?? this.attendees,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      rawIcalendar: rawIcalendar ?? this.rawIcalendar,
    );
  }

  @override
  String toString() =>
      'FreeBusy(periods: ${periods.length}, range: $dtstart – $dtend)';
}
