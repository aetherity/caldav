import '../utils/icalendar_utils.dart';
import 'calendar_component.dart';
import 'icalendar_types.dart';

/// RFC 5545 VJOURNAL status values.
enum JournalStatus {
  /// Draft entry (default).
  draft,

  /// Finalized entry.
  final_,

  /// Cancelled entry.
  cancelled,
}

/// Represents a calendar journal entry (VJOURNAL).
class CalendarJournal extends CalendarComponent {
  /// Date/time of the journal entry (RFC 5545 DTSTART) — optional.
  final DateTime? dtstart;

  /// Whether [dtstart] is a date-only (all-day) value.
  final bool isAllDay;

  /// Journal status (RFC 5545 STATUS). Defaults to [JournalStatus.draft].
  final JournalStatus status;

  const CalendarJournal({
    required super.uid,
    required super.calendarId,
    super.href,
    super.etag,
    required super.summary,
    super.description,
    super.location,
    this.dtstart,
    this.isAllDay = false,
    this.status = JournalStatus.draft,
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

  /// Create a copy with updated fields.
  CalendarJournal copyWith({
    String? uid,
    String? calendarId,
    Uri? href,
    String? etag,
    String? summary,
    String? description,
    String? location,
    DateTime? dtstart,
    bool? isAllDay,
    JournalStatus? status,
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
    return CalendarJournal(
      uid: uid ?? this.uid,
      calendarId: calendarId ?? this.calendarId,
      href: href ?? this.href,
      etag: etag ?? this.etag,
      summary: summary ?? this.summary,
      description: description ?? this.description,
      location: location ?? this.location,
      dtstart: dtstart ?? this.dtstart,
      isAllDay: isAllDay ?? this.isAllDay,
      status: status ?? this.status,
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

  @override
  String toIcalendar() {
    final buffer = StringBuffer();
    buffer.writeln('BEGIN:VCALENDAR');
    buffer.writeln('VERSION:2.0');
    buffer.writeln('PRODID:-//dart-caldav-client//EN');

    buffer.writeln('BEGIN:VJOURNAL');
    buffer.writeln('UID:$uid');
    buffer.writeln(
      'DTSTAMP:${ICalendarUtils.formatUtc((dtstamp ?? DateTime.now()).toUtc())}',
    );

    if (dtstart != null) {
      if (isAllDay) {
        buffer.writeln(
          'DTSTART;VALUE=DATE:${ICalendarUtils.formatDate(dtstart!)}',
        );
      } else {
        buffer.writeln(
          'DTSTART:${ICalendarUtils.formatUtc(dtstart!.toUtc())}',
        );
      }
    }

    buffer.writeln('SUMMARY:${ICalendarUtils.escapeText(summary)}');

    if (description != null && description!.isNotEmpty) {
      buffer.writeln(
        'DESCRIPTION:${ICalendarUtils.escapeText(description!)}',
      );
    }
    if (location != null && location!.isNotEmpty) {
      buffer.writeln('LOCATION:${ICalendarUtils.escapeText(location!)}');
    }
    if (status != JournalStatus.draft) {
      buffer.writeln('STATUS:${_statusToIcal(status)}');
    }
    if (classification != null) {
      buffer.writeln('CLASS:${classification!.icalValue}');
    }
    if (categories.isNotEmpty) {
      buffer.writeln(
        'CATEGORIES:${categories.map(ICalendarUtils.escapeText).join(',')}',
      );
    }
    if (url != null && url!.isNotEmpty) buffer.writeln('URL:$url');
    if (geo != null) buffer.writeln('GEO:${geo!.toIcalValue()}');
    if (created != null) {
      buffer.writeln('CREATED:${ICalendarUtils.formatUtc(created!.toUtc())}');
    }
    if (lastModified != null) {
      buffer.writeln(
        'LAST-MODIFIED:${ICalendarUtils.formatUtc(lastModified!.toUtc())}',
      );
    }
    if (sequence != null) buffer.writeln('SEQUENCE:$sequence');
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
    if (relatedTo != null && relatedTo!.isNotEmpty) {
      buffer.writeln('RELATED-TO:$relatedTo');
    }
    if (rrule != null && rrule!.isNotEmpty) buffer.writeln('RRULE:$rrule');
    if (recurrenceId != null && recurrenceId!.isNotEmpty) {
      buffer.writeln('RECURRENCE-ID:$recurrenceId');
    }
    if (exdate != null && exdate!.isNotEmpty) {
      buffer.writeln('EXDATE:${exdate!.join(',')}');
    }
    if (rdate != null && rdate!.isNotEmpty) {
      buffer.writeln('RDATE:${rdate!.join(',')}');
    }

    for (final alarm in alarms) {
      for (final line in alarm.toIcalLines()) {
        buffer.writeln(line);
      }
    }
    for (final extra in extraProperties) {
      buffer.writeln(extra.toLine());
    }

    buffer.writeln('END:VJOURNAL');
    buffer.writeln('END:VCALENDAR');

    return buffer.toString();
  }

  static String _statusToIcal(JournalStatus status) => switch (status) {
        JournalStatus.draft => 'DRAFT',
        JournalStatus.final_ => 'FINAL',
        JournalStatus.cancelled => 'CANCELLED',
      };

  @override
  String toString() =>
      'CalendarJournal(uid: $uid, summary: $summary, dtstart: $dtstart, '
      'status: $status)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CalendarJournal && other.uid == uid;
  }

  @override
  int get hashCode => uid.hashCode;
}
