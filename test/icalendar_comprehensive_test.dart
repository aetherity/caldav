import 'package:caldav/caldav.dart';
import 'package:test/test.dart';

void main() {
  group('ICalendarParser comprehensive RFC 5545', () {
    test('parses event with attendees, organizer, categories, class, status', () {
      const ical = '''BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Test//EN
METHOD:REQUEST
BEGIN:VEVENT
UID:rich-event-1
DTSTAMP:20260804T120000Z
CREATED:20260801T080000Z
LAST-MODIFIED:20260803T090000Z
SEQUENCE:2
DTSTART:20260810T140000Z
DTEND:20260810T150000Z
SUMMARY:Planning meeting
DESCRIPTION:Quarterly planning
LOCATION:Room A
STATUS:CONFIRMED
TRANSP:OPAQUE
CLASS:PRIVATE
CATEGORIES:Work,Planning
URL:https://example.com/meet
GEO:37.386013;-122.082932
PRIORITY:5
ORGANIZER;CN=Ada Lovelace:mailto:ada@example.com
ATTENDEE;CN=Bob;ROLE=REQ-PARTICIPANT;PARTSTAT=ACCEPTED;RSVP=TRUE:mailto:bob@example.com
ATTENDEE;CUTYPE=GROUP:mailto:team@example.com
COMMENT:Bring slides
CONTACT:Ada Lovelace\\\\, +1-555-0100
RESOURCES:Projector,Whiteboard
RELATED-TO:parent-uid-1
RRULE:FREQ=WEEKLY;COUNT=4
BEGIN:VALARM
ACTION:DISPLAY
TRIGGER:-PT15M
DESCRIPTION:Reminder
END:VALARM
END:VEVENT
END:VCALENDAR''';

      final event = ICalendarParser.parseEvent(ical, calendarId: 'cal');
      expect(event, isNotNull);
      expect(event!.uid, 'rich-event-1');
      expect(event.status, EventStatus.confirmed);
      expect(event.transparency, TimeTransparency.opaque);
      expect(event.classification, ICalClassification.private_);
      expect(event.categories, ['Work', 'Planning']);
      expect(event.url, 'https://example.com/meet');
      expect(event.geo?.latitude, closeTo(37.386013, 0.0001));
      expect(event.priority, 5);
      expect(event.sequence, 2);
      expect(event.created, DateTime.utc(2026, 8, 1, 8));
      expect(event.lastModified, DateTime.utc(2026, 8, 3, 9));
      expect(event.organizer?.commonName, 'Ada Lovelace');
      expect(event.organizer?.address, 'ada@example.com');
      expect(event.attendees, hasLength(2));
      expect(event.attendees.first.partStat, 'ACCEPTED');
      expect(event.attendees.first.rsvp, isTrue);
      expect(event.comments, ['Bring slides']);
      expect(event.resources, ['Projector', 'Whiteboard']);
      expect(event.relatedTo, 'parent-uid-1');
      expect(event.rrule, 'FREQ=WEEKLY;COUNT=4');
      expect(event.alarms, hasLength(1));
      expect(event.alarms.single.action, AlarmAction.display);
      expect(event.alarms.single.trigger, '-PT15M');
    });

    test('parses DURATION when DTEND absent', () {
      const ical = '''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:dur-1
DTSTART:20260810T140000Z
DURATION:PT1H30M
SUMMARY:Timed
END:VEVENT
END:VCALENDAR''';

      final event = ICalendarParser.parseEvent(ical, calendarId: 'c')!;
      expect(event.explicitDuration, const Duration(hours: 1, minutes: 30));
      expect(event.end, DateTime.utc(2026, 8, 10, 15, 30));
      expect(event.duration, const Duration(hours: 1, minutes: 30));
    });

    test('parses DURATION with weeks and days', () {
      const ical = '''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:dur-week-1
DTSTART:20260810T140000Z
DURATION:P1W1DT1H1M1S
SUMMARY:Long
END:VEVENT
END:VCALENDAR''';

      final event = ICalendarParser.parseEvent(ical, calendarId: 'c')!;
      expect(
        event.explicitDuration,
        const Duration(days: 8, hours: 1, minutes: 1, seconds: 1),
      );
      expect(event.end, DateTime.utc(2026, 8, 18, 15, 1, 1));
    });

    test('parses TZID on DTSTART', () {
      const ical = '''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:tz-1
DTSTART;TZID=America/New_York:20260810T100000
DTEND;TZID=America/New_York:20260810T110000
SUMMARY:Local
END:VEVENT
END:VCALENDAR''';

      final event = ICalendarParser.parseEvent(ical, calendarId: 'c')!;
      expect(event.timeZoneId, 'America/New_York');
      // Floating interpreted as local then converted to UTC — just ensure parse succeeds
      expect(event.start, isNotNull);
    });

    test('parses RDATE and multiple EXDATE', () {
      const ical = '''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:rec-1
DTSTART:20260810T140000Z
DTEND:20260810T150000Z
SUMMARY:Recur
RRULE:FREQ=DAILY;COUNT=5
EXDATE:20260811T140000Z,20260812T140000Z
EXDATE:20260813T140000Z
RDATE:20260820T140000Z
END:VEVENT
END:VCALENDAR''';

      final event = ICalendarParser.parseEvent(ical, calendarId: 'c')!;
      expect(event.exdate, hasLength(3));
      expect(event.rdate, ['20260820T140000Z']);
    });

    test('parseDocument returns calendar metadata and components', () {
      const ical = '''BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Test//EN
CALSCALE:GREGORIAN
METHOD:PUBLISH
BEGIN:VEVENT
UID:e1
DTSTART:20260810T100000Z
SUMMARY:E
END:VEVENT
BEGIN:VTODO
UID:t1
SUMMARY:T
END:VTODO
BEGIN:VJOURNAL
UID:j1
SUMMARY:J
END:VJOURNAL
END:VCALENDAR''';

      final doc = ICalendarParser.parseDocument(ical);
      expect(doc.version, '2.0');
      expect(doc.prodId, '-//Test//EN');
      expect(doc.calscale, 'GREGORIAN');
      expect(doc.method, 'PUBLISH');
      expect(doc.events, hasLength(1));
      expect(doc.todos, hasLength(1));
      expect(doc.journals, hasLength(1));
    });

    test('round-trips rich event fields through serialize', () {
      final original = CalendarEvent(
        uid: 'rt-rich',
        calendarId: 'c',
        start: DateTime.utc(2026, 8, 10, 14),
        end: DateTime.utc(2026, 8, 10, 15),
        summary: 'Rich',
        status: EventStatus.tentative,
        transparency: TimeTransparency.transparent,
        classification: ICalClassification.confidential,
        categories: const ['A', 'B'],
        url: 'https://example.com',
        geo: const GeoPosition(latitude: 1.5, longitude: 2.5),
        sequence: 1,
        organizer: const CalAddress(
          value: 'mailto:org@example.com',
          commonName: 'Org',
        ),
        attendees: const [
          CalAddress(
            value: 'mailto:a@example.com',
            partStat: 'NEEDS-ACTION',
            rsvp: true,
          ),
        ],
        comments: const ['Hi'],
        priority: 3,
        alarms: const [
          CalendarAlarm(
            action: AlarmAction.display,
            trigger: '-PT10M',
            description: 'Soon',
          ),
        ],
      );

      final parsed = ICalendarParser.parseEvent(
        original.toIcalendar(),
        calendarId: 'c',
      )!;

      expect(parsed.uid, 'rt-rich');
      expect(parsed.status, EventStatus.tentative);
      expect(parsed.transparency, TimeTransparency.transparent);
      expect(parsed.classification, ICalClassification.confidential);
      expect(parsed.categories, ['A', 'B']);
      expect(parsed.url, 'https://example.com');
      expect(parsed.geo?.latitude, 1.5);
      expect(parsed.sequence, 1);
      expect(parsed.organizer?.address, 'org@example.com');
      expect(parsed.attendees.single.address, 'a@example.com');
      expect(parsed.comments, ['Hi']);
      expect(parsed.priority, 3);
      expect(parsed.alarms.single.trigger, '-PT10M');
    });

    test('todo parses shared properties and alarms', () {
      const ical = '''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VTODO
UID:todo-rich
SUMMARY:Ship
DUE:20260815T170000Z
STATUS:IN-PROCESS
PERCENT-COMPLETE:40
PRIORITY:1
CATEGORIES:Dev
CLASS:PUBLIC
ORGANIZER:mailto:lead@example.com
BEGIN:VALARM
ACTION:EMAIL
TRIGGER:-P1D
SUMMARY:Due soon
DESCRIPTION:Todo due tomorrow
ATTENDEE:mailto:lead@example.com
END:VALARM
END:VTODO
END:VCALENDAR''';

      final todo = ICalendarParser.parseTodo(ical, calendarId: 'c')!;
      expect(todo.categories, ['Dev']);
      expect(todo.classification, ICalClassification.public_);
      expect(todo.organizer?.address, 'lead@example.com');
      expect(todo.alarms.single.action, AlarmAction.email);
      expect(todo.alarms.single.attendees.single.address, 'lead@example.com');
    });

    test('journal uses shared classification enum', () {
      const ical = '''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VJOURNAL
UID:j-rich
SUMMARY:Note
CLASS:CONFIDENTIAL
CATEGORIES:Personal
URL:https://notes.example.com/1
END:VJOURNAL
END:VCALENDAR''';

      final j = ICalendarParser.parseJournal(ical, calendarId: 'c')!;
      expect(j.classification, ICalClassification.confidential);
      expect(j.categories, ['Personal']);
      expect(j.url, 'https://notes.example.com/1');
    });

    test('PropertyEntry handles quoted CN parameters', () {
      final entry = PropertyEntry.tryParse(
        'ORGANIZER;CN="Doe, Jane":mailto:jane@example.com',
      );
      expect(entry, isNotNull);
      expect(entry!.params['CN'], 'Doe, Jane');
      expect(entry.value, 'mailto:jane@example.com');
    });

    test('parseDuration and formatDuration support weeks and days', () {
      const mixed = Duration(days: 8, hours: 1, minutes: 1, seconds: 1);
      expect(
        ICalendarParser.parseDuration('P1W1DT1H1M1S'),
        mixed,
      );
      expect(ICalendarParser.formatDuration(mixed), 'P1W1DT1H1M1S');
      expect(
        ICalendarParser.parseDuration('P1W2DT3H4M5S'),
        const Duration(days: 9, hours: 3, minutes: 4, seconds: 5),
      );
      expect(
        ICalendarParser.formatDuration(
          const Duration(days: 9, hours: 3, minutes: 4, seconds: 5),
        ),
        'P1W2DT3H4M5S',
      );
      expect(
        ICalendarParser.parseDuration('-PT15M'),
        const Duration(minutes: -15),
      );
      expect(
        ICalendarParser.formatDuration(const Duration(minutes: -15)),
        '-PT15M',
      );
      expect(
        ICalendarParser.formatDuration(const Duration(hours: 1, minutes: 30)),
        'PT1H30M',
      );
      expect(ICalendarParser.formatDuration(const Duration(days: 1)), 'P1D');
      expect(ICalendarParser.formatDuration(const Duration(days: 7)), 'P1W');
      expect(ICalendarParser.formatDuration(Duration.zero), 'PT0S');
    });

    test('serializes DURATION with weeks and days', () {
      final event = CalendarEvent(
        uid: 'dur-week',
        calendarId: 'c',
        start: DateTime.utc(2026, 8, 10, 14),
        explicitDuration: const Duration(days: 8, hours: 1, minutes: 1, seconds: 1),
        summary: 'Long',
      );
      expect(event.toIcalendar(), contains('DURATION:P1W1DT1H1M1S'));
    });
  });
}
