import '../utils/icalendar_utils.dart';
import 'calendar_component.dart';
import 'icalendar_types.dart';

/// Represents a calendar event (VEVENT).
class CalendarEvent extends CalendarComponent {
  /// Event start time (UTC).
  final DateTime start;

  /// Event end time (UTC, inclusive for all-day events).
  final DateTime? end;

  /// Explicit duration when DTEND is absent (RFC 5545 DURATION).
  final Duration? explicitDuration;

  /// Whether this is an all-day event.
  final bool isAllDay;

  /// Event status (RFC 5545 STATUS).
  final EventStatus? status;

  /// Time transparency (RFC 5545 TRANSP).
  final TimeTransparency? transparency;

  /// Priority 0–9 (RFC 5545 PRIORITY); 0 means undefined.
  final int? priority;

  const CalendarEvent({
    required super.uid,
    required super.calendarId,
    super.href,
    super.etag,
    required this.start,
    this.end,
    this.explicitDuration,
    required super.summary,
    super.description,
    super.location,
    this.isAllDay = false,
    this.status,
    this.transparency,
    this.priority,
    super.rawIcalendar,
    super.isReadOnly = false,
    super.rrule,
    super.recurrenceId,
    super.exdate,
    super.rdate,
    super.categories,
    super.classification,
    super.url,
    super.geo,
    super.created,
    super.lastModified,
    super.dtstamp,
    super.sequence,
    super.organizer,
    super.attendees,
    super.comments,
    super.contacts,
    super.resources,
    super.relatedTo,
    super.timeZoneId,
    super.alarms,
    super.extraProperties,
  });

  /// Event duration from end − start, or [explicitDuration].
  Duration? get duration {
    if (end != null) return end!.difference(start);
    return explicitDuration;
  }

  /// Create a copy with updated fields.
  CalendarEvent copyWith({
    String? uid,
    String? calendarId,
    Uri? href,
    String? etag,
    DateTime? start,
    DateTime? end,
    Duration? explicitDuration,
    String? summary,
    String? description,
    String? location,
    bool? isAllDay,
    EventStatus? status,
    TimeTransparency? transparency,
    int? priority,
    String? rawIcalendar,
    bool? isReadOnly,
    String? rrule,
    String? recurrenceId,
    List<String>? exdate,
    List<String>? rdate,
    List<String>? categories,
    ICalClassification? classification,
    String? url,
    GeoPosition? geo,
    DateTime? created,
    DateTime? lastModified,
    DateTime? dtstamp,
    int? sequence,
    CalAddress? organizer,
    List<CalAddress>? attendees,
    List<String>? comments,
    List<String>? contacts,
    List<String>? resources,
    String? relatedTo,
    String? timeZoneId,
    List<CalendarAlarm>? alarms,
    List<ICalRawProperty>? extraProperties,
  }) {
    return CalendarEvent(
      uid: uid ?? this.uid,
      calendarId: calendarId ?? this.calendarId,
      href: href ?? this.href,
      etag: etag ?? this.etag,
      start: start ?? this.start,
      end: end ?? this.end,
      explicitDuration: explicitDuration ?? this.explicitDuration,
      summary: summary ?? this.summary,
      description: description ?? this.description,
      location: location ?? this.location,
      isAllDay: isAllDay ?? this.isAllDay,
      status: status ?? this.status,
      transparency: transparency ?? this.transparency,
      priority: priority ?? this.priority,
      rawIcalendar: rawIcalendar ?? this.rawIcalendar,
      isReadOnly: isReadOnly ?? this.isReadOnly,
      rrule: rrule ?? this.rrule,
      recurrenceId: recurrenceId ?? this.recurrenceId,
      exdate: exdate ?? this.exdate,
      rdate: rdate ?? this.rdate,
      categories: categories ?? this.categories,
      classification: classification ?? this.classification,
      url: url ?? this.url,
      geo: geo ?? this.geo,
      created: created ?? this.created,
      lastModified: lastModified ?? this.lastModified,
      dtstamp: dtstamp ?? this.dtstamp,
      sequence: sequence ?? this.sequence,
      organizer: organizer ?? this.organizer,
      attendees: attendees ?? this.attendees,
      comments: comments ?? this.comments,
      contacts: contacts ?? this.contacts,
      resources: resources ?? this.resources,
      relatedTo: relatedTo ?? this.relatedTo,
      timeZoneId: timeZoneId ?? this.timeZoneId,
      alarms: alarms ?? this.alarms,
      extraProperties: extraProperties ?? this.extraProperties,
    );
  }

  /// Convert to iCalendar format.
  @override
  String toIcalendar() {
    final buffer = StringBuffer();
    buffer.writeln('BEGIN:VCALENDAR');
    buffer.writeln('VERSION:2.0');
    buffer.writeln('PRODID:-//dart-caldav-client//EN');

    buffer.writeln('BEGIN:VEVENT');
    buffer.writeln('UID:$uid');
    buffer.writeln(
      'DTSTAMP:${ICalendarUtils.formatUtc((dtstamp ?? DateTime.now()).toUtc())}',
    );

    _writeDateTime(buffer, 'DTSTART', start, isAllDay: isAllDay, tzid: timeZoneId);

    if (isAllDay) {
      // Always emit exclusive DTEND for all-day events (RFC 5545).
      final exclusiveEnd = (end == null || end == start)
          ? start.add(const Duration(days: 1))
          : end!.add(const Duration(days: 1));
      _writeDateTime(
        buffer,
        'DTEND',
        exclusiveEnd,
        isAllDay: true,
        tzid: timeZoneId,
      );
    } else if (explicitDuration != null && end == null) {
      buffer.writeln(
        'DURATION:${ICalendarUtils.formatDuration(explicitDuration!)}',
      );
    } else if (end != null) {
      _writeDateTime(buffer, 'DTEND', end!, isAllDay: false, tzid: timeZoneId);
    }

    buffer.writeln('SUMMARY:${ICalendarUtils.escapeText(summary)}');
    _writeCommonProperties(buffer);

    if (status != null) {
      buffer.writeln('STATUS:${status!.icalValue}');
    }
    if (transparency != null) {
      buffer.writeln('TRANSP:${transparency!.icalValue}');
    }
    if (priority != null && priority != 0) {
      buffer.writeln('PRIORITY:$priority');
    }

    for (final alarm in alarms) {
      for (final line in alarm.toIcalLines()) {
        buffer.writeln(line);
      }
    }
    for (final extra in extraProperties) {
      buffer.writeln(extra.toLine());
    }

    buffer.writeln('END:VEVENT');
    buffer.writeln('END:VCALENDAR');

    return buffer.toString();
  }

  void _writeCommonProperties(StringBuffer buffer) {
    if (description != null && description!.isNotEmpty) {
      buffer.writeln(
        'DESCRIPTION:${ICalendarUtils.escapeText(description!)}',
      );
    }
    if (location != null && location!.isNotEmpty) {
      buffer.writeln('LOCATION:${ICalendarUtils.escapeText(location!)}');
    }
    if (categories.isNotEmpty) {
      buffer.writeln(
        'CATEGORIES:${categories.map(ICalendarUtils.escapeText).join(',')}',
      );
    }
    if (classification != null) {
      buffer.writeln('CLASS:${classification!.icalValue}');
    }
    if (url != null && url!.isNotEmpty) {
      buffer.writeln('URL:$url');
    }
    if (geo != null) {
      buffer.writeln('GEO:${geo!.toIcalValue()}');
    }
    if (created != null) {
      buffer.writeln('CREATED:${ICalendarUtils.formatUtc(created!.toUtc())}');
    }
    if (lastModified != null) {
      buffer.writeln(
        'LAST-MODIFIED:${ICalendarUtils.formatUtc(lastModified!.toUtc())}',
      );
    }
    if (sequence != null) {
      buffer.writeln('SEQUENCE:$sequence');
    }
    if (organizer != null) {
      buffer.writeln(organizer!.toPropertyLine('ORGANIZER'));
    }
    for (final a in attendees) {
      buffer.writeln(a.toPropertyLine('ATTENDEE'));
    }
    for (final c in comments) {
      buffer.writeln('COMMENT:${ICalendarUtils.escapeText(c)}');
    }
    for (final c in contacts) {
      buffer.writeln('CONTACT:${ICalendarUtils.escapeText(c)}');
    }
    if (resources.isNotEmpty) {
      buffer.writeln(
        'RESOURCES:${resources.map(ICalendarUtils.escapeText).join(',')}',
      );
    }
    if (relatedTo != null && relatedTo!.isNotEmpty) {
      buffer.writeln('RELATED-TO:$relatedTo');
    }
    if (rrule != null && rrule!.isNotEmpty) {
      buffer.writeln('RRULE:$rrule');
    }
    if (recurrenceId != null && recurrenceId!.isNotEmpty) {
      buffer.writeln('RECURRENCE-ID:$recurrenceId');
    }
    if (exdate != null && exdate!.isNotEmpty) {
      buffer.writeln('EXDATE:${exdate!.join(',')}');
    }
    if (rdate != null && rdate!.isNotEmpty) {
      buffer.writeln('RDATE:${rdate!.join(',')}');
    }
  }

  static void _writeDateTime(
    StringBuffer buffer,
    String name,
    DateTime dt, {
    required bool isAllDay,
    String? tzid,
  }) {
    if (isAllDay) {
      buffer.writeln('$name;VALUE=DATE:${ICalendarUtils.formatDate(dt)}');
    } else if (tzid != null && tzid.isNotEmpty) {
      buffer.writeln(
        '$name;TZID=$tzid:${ICalendarUtils.formatUtc(dt).replaceAll('Z', '')}',
      );
    } else {
      buffer.writeln('$name:${ICalendarUtils.formatUtc(dt.toUtc())}');
    }
  }

  @override
  String toString() {
    return 'CalendarEvent(uid: $uid, summary: $summary, start: $start)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CalendarEvent && other.uid == uid;
  }

  @override
  int get hashCode => uid.hashCode;
}
