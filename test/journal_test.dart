import 'package:caldav/caldav.dart';
import 'package:caldav/src/event/journal_service.dart';
import 'package:test/test.dart';

void main() {
  group('CalendarJournal', () {
    test('constructs with minimal fields (uid + summary only)', () {
      const journal = CalendarJournal(
        uid: 'j-1',
        calendarId: 'cal-1',
        summary: 'Daily notes',
      );

      expect(journal.uid, equals('j-1'));
      expect(journal.summary, equals('Daily notes'));
      expect(journal.dtstart, isNull);
      expect(journal.status, equals(JournalStatus.draft));
      expect(journal.categories, isEmpty);
    });

    test('copyWith updates fields and preserves others', () {
      const original = CalendarJournal(
        uid: 'j',
        calendarId: 'c',
        summary: 'Original',
        categories: ['work'],
      );
      final modified = original.copyWith(
        summary: 'Modified',
        status: JournalStatus.final_,
      );

      expect(modified.uid, equals('j'));
      expect(modified.summary, equals('Modified'));
      expect(modified.status, equals(JournalStatus.final_));
      expect(modified.categories, equals(['work']));
      expect(original.summary, equals('Original'));
      expect(original.status, equals(JournalStatus.draft));
    });

    test('equality is by uid', () {
      const a = CalendarJournal(uid: 'j', calendarId: 'c', summary: 'A');
      const b = CalendarJournal(uid: 'j', calendarId: 'c', summary: 'B');
      const c = CalendarJournal(uid: 'x', calendarId: 'c', summary: 'A');
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('CalendarJournal.toIcalendar', () {
    test('serializes minimal journal', () {
      const journal = CalendarJournal(
        uid: 'j-1',
        calendarId: 'c',
        summary: 'Notes',
      );
      final ical = journal.toIcalendar();

      expect(ical, contains('BEGIN:VCALENDAR'));
      expect(ical, contains('BEGIN:VJOURNAL'));
      expect(ical, contains('UID:j-1'));
      expect(ical, contains('SUMMARY:Notes'));
      expect(ical, contains('END:VJOURNAL'));
      // draft status is omitted
      expect(ical, isNot(contains('STATUS:')));
      expect(ical, isNot(contains('DTSTART')));
    });

    test('serializes all-day dtstart as VALUE=DATE', () {
      final journal = CalendarJournal(
        uid: 'j',
        calendarId: 'c',
        summary: 'Day log',
        dtstart: DateTime.utc(2026, 8, 2),
        isAllDay: true,
      );
      final ical = journal.toIcalendar();
      expect(ical, contains('DTSTART;VALUE=DATE:20260802'));
    });

    test('serializes timed dtstart, status, class, categories', () {
      final journal = CalendarJournal(
        uid: 'j',
        calendarId: 'c',
        summary: 'Meeting notes',
        description: 'Line1\nLine2',
        dtstart: DateTime.utc(2026, 8, 2, 15, 30),
        status: JournalStatus.final_,
        classification: ICalClassification.private_,
        categories: const ['work', 'team'],
      );
      final ical = journal.toIcalendar();
      expect(ical, contains('DTSTART:20260802T153000Z'));
      expect(ical, contains('STATUS:FINAL'));
      expect(ical, contains('CLASS:PRIVATE'));
      expect(ical, contains('CATEGORIES:work,team'));
      expect(ical, contains('DESCRIPTION:Line1\\nLine2'));
    });
  });

  group('ICalendarParser.parseJournal', () {
    test('parses a full journal', () {
      const icalendar = '''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VJOURNAL
UID:journal-1
DTSTART;VALUE=DATE:20260802
SUMMARY:Ship day
DESCRIPTION:Released 2.1.0
STATUS:FINAL
CLASS:PUBLIC
CATEGORIES:work,release
END:VJOURNAL
END:VCALENDAR''';

      final journal = ICalendarParser.parseJournal(
        icalendar,
        calendarId: 'cal-1',
      );

      expect(journal, isNotNull);
      expect(journal!.uid, equals('journal-1'));
      expect(journal.summary, equals('Ship day'));
      expect(journal.description, equals('Released 2.1.0'));
      expect(journal.dtstart, equals(DateTime.utc(2026, 8, 2)));
      expect(journal.isAllDay, isTrue);
      expect(journal.status, equals(JournalStatus.final_));
      expect(journal.classification, equals(ICalClassification.public_));
      expect(journal.categories, equals(['work', 'release']));
    });

    test('parses journal with only UID and SUMMARY', () {
      const icalendar = '''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VJOURNAL
UID:minimal
SUMMARY:Untitled thought
END:VJOURNAL
END:VCALENDAR''';

      final journal = ICalendarParser.parseJournal(
        icalendar,
        calendarId: 'c',
      );
      expect(journal, isNotNull);
      expect(journal!.uid, equals('minimal'));
      expect(journal.dtstart, isNull);
      expect(journal.status, equals(JournalStatus.draft));
    });

    test('returns null for missing UID', () {
      const icalendar = '''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VJOURNAL
SUMMARY:No uid
END:VJOURNAL
END:VCALENDAR''';
      expect(
        ICalendarParser.parseJournal(icalendar, calendarId: 'c'),
        isNull,
      );
    });

    test('returns null when component is not VJOURNAL', () {
      const icalendar = '''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:e
DTSTART:20240115T100000Z
SUMMARY:Event
END:VEVENT
END:VCALENDAR''';
      expect(
        ICalendarParser.parseJournal(icalendar, calendarId: 'c'),
        isNull,
      );
    });

    test('round-trip timed journal survives parse → serialize → parse', () {
      final original = CalendarJournal(
        uid: 'rt-1',
        calendarId: 'c',
        summary: 'Round trip',
        description: 'Hello; world',
        dtstart: DateTime.utc(2026, 3, 10, 9),
        status: JournalStatus.cancelled,
        categories: ['personal'],
      );
      final parsed = ICalendarParser.parseJournal(
        original.toIcalendar(),
        calendarId: 'c',
      );
      expect(parsed, isNotNull);
      expect(parsed!.uid, original.uid);
      expect(parsed.summary, original.summary);
      expect(parsed.description, original.description);
      expect(parsed.dtstart, original.dtstart);
      expect(parsed.status, JournalStatus.cancelled);
      expect(parsed.categories, ['personal']);
    });
  });

  group('JournalService query body', () {
    test('calendar-query filters on VJOURNAL', () {
      final body = JournalService.buildCalendarQueryBody();
      expect(body, contains('calendar-query'));
      expect(body, contains('name="VJOURNAL"'));
      expect(body, contains('calendar-data'));
      expect(body, isNot(contains('time-range')));
    });

    test('calendar-query includes time-range when start and end given', () {
      final body = JournalService.buildCalendarQueryBody(
        start: DateTime.utc(2026, 1, 1),
        end: DateTime.utc(2026, 2, 1),
      );
      expect(body, contains('time-range'));
      expect(body, contains('20260101T000000Z'));
      expect(body, contains('20260201T000000Z'));
    });

    test('uid query filters on UID', () {
      final body = JournalService.buildUidQueryBody('uid-<>&');
      expect(body, contains('name="VJOURNAL"'));
      expect(body, contains('prop-filter name="UID"'));
      expect(body, contains('uid-&lt;&gt;&amp;'));
    });
  });

  group('CalDavClient journal guards', () {
    test('updateJournal throws ForbiddenException for read-only', () async {
      final client = CalDavClient(
        baseUrl: 'https://example.com',
        username: 'u',
        password: 'p',
      );
      final journal = CalendarJournal(
        uid: '1',
        calendarId: 'c',
        summary: 'X',
        href: Uri.parse('https://example.com/1.ics'),
        isReadOnly: true,
      );
      expect(
        () => client.updateJournal(journal),
        throwsA(isA<ForbiddenException>()),
      );
      client.close();
    });

    test('deleteJournal throws ForbiddenException for read-only', () async {
      final client = CalDavClient(
        baseUrl: 'https://example.com',
        username: 'u',
        password: 'p',
      );
      final journal = CalendarJournal(
        uid: '1',
        calendarId: 'c',
        summary: 'X',
        href: Uri.parse('https://example.com/1.ics'),
        isReadOnly: true,
      );
      expect(
        () => client.deleteJournal(journal),
        throwsA(isA<ForbiddenException>()),
      );
      client.close();
    });
  });

  group('Calendar.supportsJournal', () {
    test('true when VJOURNAL is in supportedComponents', () {
      final cal = Calendar(
        uid: 'c',
        href: Uri.parse('https://example.com/cal/'),
        displayName: 'J',
        supportedComponents: const ['VEVENT', 'VJOURNAL'],
      );
      expect(cal.supportsJournal, isTrue);
      expect(cal.supportsEvents, isTrue);
      expect(cal.supportsTodos, isFalse);
    });
  });
}
