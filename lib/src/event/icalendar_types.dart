import '../utils/icalendar_utils.dart';

/// Access classification (RFC 5545 CLASS).
enum ICalClassification {
  public_,
  private_,
  confidential;

  static ICalClassification? tryParse(String? value) {
    switch (value?.toUpperCase()) {
      case 'PUBLIC':
        return ICalClassification.public_;
      case 'PRIVATE':
        return ICalClassification.private_;
      case 'CONFIDENTIAL':
        return ICalClassification.confidential;
      default:
        return null;
    }
  }

  String get icalValue => switch (this) {
        ICalClassification.public_ => 'PUBLIC',
        ICalClassification.private_ => 'PRIVATE',
        ICalClassification.confidential => 'CONFIDENTIAL',
      };
}

/// VEVENT status (RFC 5545 STATUS).
enum EventStatus {
  tentative,
  confirmed,
  cancelled;

  static EventStatus? tryParse(String? value) {
    switch (value?.toUpperCase()) {
      case 'TENTATIVE':
        return EventStatus.tentative;
      case 'CONFIRMED':
        return EventStatus.confirmed;
      case 'CANCELLED':
        return EventStatus.cancelled;
      default:
        return null;
    }
  }

  String get icalValue => switch (this) {
        EventStatus.tentative => 'TENTATIVE',
        EventStatus.confirmed => 'CONFIRMED',
        EventStatus.cancelled => 'CANCELLED',
      };
}

/// Time transparency (RFC 5545 TRANSP) — whether the event blocks busy time.
enum TimeTransparency {
  /// Blocks free/busy time (default).
  opaque,

  /// Does not block free/busy time.
  transparent;

  static TimeTransparency? tryParse(String? value) {
    switch (value?.toUpperCase()) {
      case 'OPAQUE':
        return TimeTransparency.opaque;
      case 'TRANSPARENT':
        return TimeTransparency.transparent;
      default:
        return null;
    }
  }

  String get icalValue => switch (this) {
        TimeTransparency.opaque => 'OPAQUE',
        TimeTransparency.transparent => 'TRANSPARENT',
      };
}

/// VALARM action (RFC 5545 ACTION).
enum AlarmAction {
  audio,
  display,
  email,
  procedure;

  static AlarmAction? tryParse(String? value) {
    switch (value?.toUpperCase()) {
      case 'AUDIO':
        return AlarmAction.audio;
      case 'DISPLAY':
        return AlarmAction.display;
      case 'EMAIL':
        return AlarmAction.email;
      case 'PROCEDURE':
        return AlarmAction.procedure;
      default:
        return null;
    }
  }

  String get icalValue => switch (this) {
        AlarmAction.audio => 'AUDIO',
        AlarmAction.display => 'DISPLAY',
        AlarmAction.email => 'EMAIL',
        AlarmAction.procedure => 'PROCEDURE',
      };
}

/// Calendar user address with common parameters (ORGANIZER / ATTENDEE).
class CalAddress {
  /// Address value, typically `mailto:user@example.com` or a URI.
  final String value;

  /// Common name (`CN`).
  final String? commonName;

  /// Role (`ROLE`), e.g. `REQ-PARTICIPANT`, `CHAIR`.
  final String? role;

  /// Participation status (`PARTSTAT`), e.g. `ACCEPTED`, `NEEDS-ACTION`.
  final String? partStat;

  /// RSVP expectation (`RSVP=TRUE|FALSE`).
  final bool? rsvp;

  /// Calendar user type (`CUTYPE`).
  final String? cuType;

  /// Remaining parameters not modeled above.
  final Map<String, String> extraParams;

  const CalAddress({
    required this.value,
    this.commonName,
    this.role,
    this.partStat,
    this.rsvp,
    this.cuType,
    this.extraParams = const {},
  });

  /// Email-like local part without `mailto:` prefix when applicable.
  String get address {
    final v = value.trim();
    if (v.toLowerCase().startsWith('mailto:')) return v.substring(7);
    return v;
  }

  /// Serialize to a single iCalendar property line (name provided by caller).
  String toPropertyLine(String name) {
    final params = StringBuffer();
    if (commonName != null && commonName!.isNotEmpty) {
      params.write(';CN=${_quoteIfNeeded(commonName!)}');
    }
    if (role != null && role!.isNotEmpty) {
      params.write(';ROLE=${role!.toUpperCase()}');
    }
    if (partStat != null && partStat!.isNotEmpty) {
      params.write(';PARTSTAT=${partStat!.toUpperCase()}');
    }
    if (rsvp != null) {
      params.write(';RSVP=${rsvp! ? 'TRUE' : 'FALSE'}');
    }
    if (cuType != null && cuType!.isNotEmpty) {
      params.write(';CUTYPE=${cuType!.toUpperCase()}');
    }
    extraParams.forEach((k, v) {
      params.write(';$k=${_quoteIfNeeded(v)}');
    });
    final addr = value.toLowerCase().startsWith('mailto:') || value.contains(':')
        ? value
        : 'mailto:$value';
    return '$name$params:$addr';
  }

  static String _quoteIfNeeded(String value) {
    if (value.contains(',') ||
        value.contains(';') ||
        value.contains(':') ||
        value.contains(' ')) {
      return '"${value.replaceAll('"', '')}"';
    }
    return value;
  }

  @override
  String toString() => commonName != null ? '$commonName <$address>' : address;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CalAddress && other.value == value;
  }

  @override
  int get hashCode => value.hashCode;
}

/// Geographic position (RFC 5545 GEO): latitude;longitude.
class GeoPosition {
  final double latitude;
  final double longitude;

  const GeoPosition({
    required this.latitude,
    required this.longitude,
  });

  static GeoPosition? tryParse(String? value) {
    if (value == null || value.isEmpty) return null;
    final parts = value.split(';');
    if (parts.length < 2) return null;
    final lat = double.tryParse(parts[0].trim());
    final lon = double.tryParse(parts[1].trim());
    if (lat == null || lon == null) return null;
    return GeoPosition(latitude: lat, longitude: lon);
  }

  String toIcalValue() => '$latitude;$longitude';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GeoPosition &&
        other.latitude == latitude &&
        other.longitude == longitude;
  }

  @override
  int get hashCode => Object.hash(latitude, longitude);
}

/// A VALARM sub-component (RFC 5545).
class CalendarAlarm {
  /// Alarm action.
  final AlarmAction action;

  /// Trigger value as stored in iCalendar (e.g. `-PT15M` or absolute datetime).
  final String trigger;

  /// True when TRIGGER uses `VALUE=DATE-TIME` (absolute).
  final bool triggerIsAbsolute;

  /// Related end vs start for relative triggers (`RELATED=END`).
  final bool relatedToEnd;

  /// Display/email description.
  final String? description;

  /// Email summary.
  final String? summary;

  /// Audio attach URI or binary reference (raw value).
  final String? attach;

  /// Repeat count after first trigger.
  final int? repeat;

  /// Duration between repeats.
  final String? duration;

  /// Email attendees for ACTION=EMAIL.
  final List<CalAddress> attendees;

  const CalendarAlarm({
    required this.action,
    required this.trigger,
    this.triggerIsAbsolute = false,
    this.relatedToEnd = false,
    this.description,
    this.summary,
    this.attach,
    this.repeat,
    this.duration,
    this.attendees = const [],
  });

  /// Serialize this alarm as nested VALARM lines (without outer VCALENDAR).
  List<String> toIcalLines() {
    final lines = <String>[
      'BEGIN:VALARM',
      'ACTION:${action.icalValue}',
    ];
    final triggerParams = StringBuffer();
    if (triggerIsAbsolute) triggerParams.write(';VALUE=DATE-TIME');
    if (relatedToEnd) triggerParams.write(';RELATED=END');
    lines.add('TRIGGER$triggerParams:$trigger');
    if (description != null && description!.isNotEmpty) {
      lines.add(
        'DESCRIPTION:${ICalendarUtils.escapeText(description!)}',
      );
    }
    if (summary != null && summary!.isNotEmpty) {
      lines.add('SUMMARY:${ICalendarUtils.escapeText(summary!)}');
    }
    if (attach != null && attach!.isNotEmpty) {
      lines.add('ATTACH:$attach');
    }
    if (duration != null && duration!.isNotEmpty) {
      lines.add('DURATION:$duration');
    }
    if (repeat != null) {
      lines.add('REPEAT:$repeat');
    }
    for (final a in attendees) {
      lines.add(a.toPropertyLine('ATTENDEE'));
    }
    lines.add('END:VALARM');
    return lines;
  }

  @override
  String toString() => 'CalendarAlarm($action, trigger: $trigger)';
}

/// An unmodeled iCalendar property preserved for round-trip.
class ICalRawProperty {
  final String name;
  final Map<String, String> params;
  final String value;

  const ICalRawProperty({
    required this.name,
    this.params = const {},
    required this.value,
  });

  String toLine() {
    final buffer = StringBuffer(name);
    params.forEach((k, v) {
      buffer.write(';$k=$v');
    });
    buffer.write(':$value');
    return buffer.toString();
  }
}
