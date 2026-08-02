import '../utils/icalendar_utils.dart';
import 'calendar_component.dart';

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
///
/// Journals are free-form notes associated with a date/time. Unlike events
/// they have no duration (no DTEND); [dtstart] is optional and often date-only.
class CalendarJournal extends CalendarComponent {
  /// Date/time of the journal entry (RFC 5545 DTSTART) — optional.
  final DateTime? dtstart;

  /// Whether [dtstart] is a date-only (all-day) value.
  final bool isAllDay;

  /// Journal status (RFC 5545 STATUS). Defaults to [JournalStatus.draft].
  final JournalStatus status;

  /// Access classification (RFC 5545 CLASS): PUBLIC, PRIVATE, CONFIDENTIAL.
  final String? classification;

  /// Categories / tags (RFC 5545 CATEGORIES).
  final List<String> categories;

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
    this.classification,
    this.categories = const [],
    super.rawIcalendar,
    super.isReadOnly = false,
    super.rrule,
    super.recurrenceId,
    super.exdate,
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
    String? classification,
    List<String>? categories,
    String? rawIcalendar,
    bool? isReadOnly,
    String? rrule,
    String? recurrenceId,
    List<String>? exdate,
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
      classification: classification ?? this.classification,
      categories: categories ?? this.categories,
      rawIcalendar: rawIcalendar ?? this.rawIcalendar,
      isReadOnly: isReadOnly ?? this.isReadOnly,
      rrule: rrule ?? this.rrule,
      recurrenceId: recurrenceId ?? this.recurrenceId,
      exdate: exdate ?? this.exdate,
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
      'DTSTAMP:${ICalendarUtils.formatUtc(DateTime.now().toUtc())}',
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

    if (classification != null && classification!.isNotEmpty) {
      buffer.writeln('CLASS:${classification!.toUpperCase()}');
    }

    if (categories.isNotEmpty) {
      final cats = categories.map(ICalendarUtils.escapeText).join(',');
      buffer.writeln('CATEGORIES:$cats');
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
