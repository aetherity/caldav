import 'icalendar_types.dart';

/// Base class for iCalendar components shared by VEVENT, VTODO, and VJOURNAL.
///
/// Holds fields common to calendar components. Concrete subclasses
/// ([CalendarEvent], [CalendarTodo], [CalendarJournal]) add their
/// component-specific fields and implement [toIcalendar].
abstract class CalendarComponent {
  /// Unique identifier (iCalendar UID).
  final String uid;

  /// Calendar ID that this component belongs to.
  final String calendarId;

  /// Resource URL (set after creation).
  final Uri? href;

  /// Entity tag for concurrency control.
  final String? etag;

  /// Title / summary.
  final String summary;

  /// Description.
  final String? description;

  /// Location.
  final String? location;

  /// Whether this component is read-only (inherited from calendar).
  final bool isReadOnly;

  /// Raw iCalendar data (preserved from server).
  final String? rawIcalendar;

  /// Recurrence rule (RFC 5545 RRULE).
  final String? rrule;

  /// Recurrence ID for modified instances (RFC 5545 RECURRENCE-ID).
  final String? recurrenceId;

  /// Exception dates (RFC 5545 EXDATE) as raw iCalendar date/time tokens.
  final List<String>? exdate;

  /// Recurrence dates (RFC 5545 RDATE) as raw tokens.
  final List<String>? rdate;

  /// Categories / tags (RFC 5545 CATEGORIES).
  final List<String> categories;

  /// Access classification (RFC 5545 CLASS).
  final ICalClassification? classification;

  /// URL associated with the component.
  final String? url;

  /// Geographic position (RFC 5545 GEO).
  final GeoPosition? geo;

  /// Creation time (RFC 5545 CREATED).
  final DateTime? created;

  /// Last modification time (RFC 5545 LAST-MODIFIED).
  final DateTime? lastModified;

  /// Stamp time (RFC 5545 DTSTAMP).
  final DateTime? dtstamp;

  /// Revision sequence (RFC 5545 SEQUENCE).
  final int? sequence;

  /// Organizer (RFC 5545 ORGANIZER).
  final CalAddress? organizer;

  /// Attendees (RFC 5545 ATTENDEE).
  final List<CalAddress> attendees;

  /// Comments (RFC 5545 COMMENT).
  final List<String> comments;

  /// Contacts (RFC 5545 CONTACT).
  final List<String> contacts;

  /// Resources (RFC 5545 RESOURCES).
  final List<String> resources;

  /// Related component UID (RFC 5545 RELATED-TO).
  final String? relatedTo;

  /// TZID from DTSTART when present (floating/local zone id).
  final String? timeZoneId;

  /// Nested VALARM components.
  final List<CalendarAlarm> alarms;

  /// Unmodeled properties retained for best-effort round-trip.
  final List<ICalRawProperty> extraProperties;

  const CalendarComponent({
    required this.uid,
    required this.calendarId,
    this.href,
    this.etag,
    required this.summary,
    this.description,
    this.location,
    this.isReadOnly = false,
    this.rawIcalendar,
    this.rrule,
    this.recurrenceId,
    this.exdate,
    this.rdate,
    this.categories = const [],
    this.classification,
    this.url,
    this.geo,
    this.created,
    this.lastModified,
    this.dtstamp,
    this.sequence,
    this.organizer,
    this.attendees = const [],
    this.comments = const [],
    this.contacts = const [],
    this.resources = const [],
    this.relatedTo,
    this.timeZoneId,
    this.alarms = const [],
    this.extraProperties = const [],
  });

  /// Serialize this component to a complete VCALENDAR string.
  String toIcalendar();
}
