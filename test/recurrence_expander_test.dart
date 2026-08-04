import 'package:caldav/caldav.dart';
import 'package:test/test.dart';

void main() {
  group('RecurrenceExpander', () {
    test('non-recurring event returns DTSTART if in range', () {
      final dates = RecurrenceExpander.expand(
        dtstart: DateTime.utc(2026, 8, 10, 14),
        rangeStart: DateTime.utc(2026, 8, 1),
        rangeEnd: DateTime.utc(2026, 8, 31),
      );
      expect(dates, [DateTime.utc(2026, 8, 10, 14)]);
    });

    test('non-recurring outside range returns empty', () {
      final dates = RecurrenceExpander.expand(
        dtstart: DateTime.utc(2026, 7, 10, 14),
        rangeStart: DateTime.utc(2026, 8, 1),
        rangeEnd: DateTime.utc(2026, 8, 31),
      );
      expect(dates, isEmpty);
    });

    test('daily RRULE limited to range', () {
      final dates = RecurrenceExpander.expand(
        dtstart: DateTime.utc(2026, 8, 1, 9),
        rrule: 'FREQ=DAILY;COUNT=10',
        rangeStart: DateTime.utc(2026, 8, 3),
        rangeEnd: DateTime.utc(2026, 8, 7),
      );
      expect(dates, [
        DateTime.utc(2026, 8, 3, 9),
        DateTime.utc(2026, 8, 4, 9),
        DateTime.utc(2026, 8, 5, 9),
        DateTime.utc(2026, 8, 6, 9),
      ]);
    });

    test('accepts RRULE: prefix', () {
      final dates = RecurrenceExpander.expand(
        dtstart: DateTime.utc(2026, 8, 1),
        rrule: 'RRULE:FREQ=DAILY;COUNT=3',
        rangeStart: DateTime.utc(2026, 8, 1),
        rangeEnd: DateTime.utc(2026, 8, 10),
        isAllDay: true,
      );
      expect(dates, hasLength(3));
      expect(dates.first, DateTime.utc(2026, 8, 1));
    });

    test('EXDATE removes occurrences', () {
      final dates = RecurrenceExpander.expand(
        dtstart: DateTime.utc(2026, 8, 1, 10),
        rrule: 'FREQ=DAILY;COUNT=5',
        exdate: ['20260802T100000Z', '20260804T100000Z'],
        rangeStart: DateTime.utc(2026, 8, 1),
        rangeEnd: DateTime.utc(2026, 8, 10),
      );
      expect(dates, [
        DateTime.utc(2026, 8, 1, 10),
        DateTime.utc(2026, 8, 3, 10),
        DateTime.utc(2026, 8, 5, 10),
      ]);
    });

    test('RDATE adds extra occurrences', () {
      final dates = RecurrenceExpander.expand(
        dtstart: DateTime.utc(2026, 8, 1, 10),
        rrule: 'FREQ=DAILY;COUNT=2',
        rdate: ['20260810T100000Z'],
        rangeStart: DateTime.utc(2026, 8, 1),
        rangeEnd: DateTime.utc(2026, 8, 15),
      );
      expect(dates, [
        DateTime.utc(2026, 8, 1, 10),
        DateTime.utc(2026, 8, 2, 10),
        DateTime.utc(2026, 8, 10, 10),
      ]);
    });

    test('RDATE-only without RRULE', () {
      final dates = RecurrenceExpander.expand(
        dtstart: DateTime.utc(2026, 8, 1, 10),
        rdate: ['20260805T100000Z', '20260807T100000Z'],
        rangeStart: DateTime.utc(2026, 8, 1),
        rangeEnd: DateTime.utc(2026, 8, 10),
      );
      // DTSTART in range + RDATEs
      expect(dates, [
        DateTime.utc(2026, 8, 1, 10),
        DateTime.utc(2026, 8, 5, 10),
        DateTime.utc(2026, 8, 7, 10),
      ]);
    });

    test('all-day EXDATE matches by date', () {
      final dates = RecurrenceExpander.expand(
        dtstart: DateTime.utc(2026, 8, 1),
        rrule: 'FREQ=DAILY;COUNT=4',
        exdate: ['20260803'],
        rangeStart: DateTime.utc(2026, 8, 1),
        rangeEnd: DateTime.utc(2026, 8, 10),
        isAllDay: true,
      );
      expect(dates, [
        DateTime.utc(2026, 8, 1),
        DateTime.utc(2026, 8, 2),
        DateTime.utc(2026, 8, 4),
      ]);
    });

    test('RECURRENCE-ID instance returns only that occurrence', () {
      final dates = RecurrenceExpander.expand(
        dtstart: DateTime.utc(2026, 8, 5, 16), // modified time
        rrule: 'FREQ=DAILY;COUNT=100', // ignored for exception instances
        recurrenceId: '20260805T140000Z',
        rangeStart: DateTime.utc(2026, 8, 1),
        rangeEnd: DateTime.utc(2026, 8, 10),
      );
      expect(dates, [DateTime.utc(2026, 8, 5, 16)]);
    });

    test('RECURRENCE-ID outside range is empty', () {
      final dates = RecurrenceExpander.expand(
        dtstart: DateTime.utc(2026, 9, 1),
        recurrenceId: '20260901T000000Z',
        rangeStart: DateTime.utc(2026, 8, 1),
        rangeEnd: DateTime.utc(2026, 8, 10),
      );
      expect(dates, isEmpty);
    });

    test('maxOccurrences caps result', () {
      final dates = RecurrenceExpander.expand(
        dtstart: DateTime.utc(2026, 1, 1),
        rrule: 'FREQ=DAILY',
        rangeStart: DateTime.utc(2026, 1, 1),
        rangeEnd: DateTime.utc(2027, 1, 1),
        maxOccurrences: 5,
      );
      expect(dates, hasLength(5));
    });

    test('empty range returns empty', () {
      expect(
        RecurrenceExpander.expand(
          dtstart: DateTime.utc(2026, 8, 1),
          rrule: 'FREQ=DAILY;COUNT=3',
          rangeStart: DateTime.utc(2026, 8, 5),
          rangeEnd: DateTime.utc(2026, 8, 5),
        ),
        isEmpty,
      );
    });

    test('invalid RRULE yields empty (or only RDATE)', () {
      final dates = RecurrenceExpander.expand(
        dtstart: DateTime.utc(2026, 8, 1),
        rrule: 'FREQ=NOT_A_FREQ',
        rdate: ['20260802T000000Z'],
        rangeStart: DateTime.utc(2026, 8, 1),
        rangeEnd: DateTime.utc(2026, 8, 10),
      );
      expect(dates, [DateTime.utc(2026, 8, 2)]);
    });
  });

  group('CalendarEvent.expandOccurrences', () {
    test('weekly rule via extension', () {
      final event = CalendarEvent(
        uid: 'e1',
        calendarId: 'c',
        start: DateTime.utc(2026, 8, 3, 15), // Monday
        end: DateTime.utc(2026, 8, 3, 16),
        summary: 'Standup',
        rrule: 'FREQ=WEEKLY;BYDAY=MO;COUNT=4',
      );

      final dates = event.expandOccurrences(
        rangeStart: DateTime.utc(2026, 8, 1),
        rangeEnd: DateTime.utc(2026, 9, 1),
      );
      expect(dates, hasLength(4));
      expect(dates.every((d) => d.weekday == DateTime.monday), isTrue);
    });
  });

  group('CalendarTodo.expandOccurrences', () {
    test('uses due as anchor when dtstart missing', () {
      final todo = CalendarTodo(
        uid: 't1',
        calendarId: 'c',
        summary: 'Weekly chore',
        due: DateTime.utc(2026, 8, 1, 18),
        rrule: 'FREQ=WEEKLY;COUNT=3',
      );
      final dates = todo.expandOccurrences(
        rangeStart: DateTime.utc(2026, 8, 1),
        rangeEnd: DateTime.utc(2026, 9, 1),
      );
      expect(dates, hasLength(3));
      expect(dates.first, DateTime.utc(2026, 8, 1, 18));
    });

    test('empty without anchor date', () {
      const todo = CalendarTodo(
        uid: 't',
        calendarId: 'c',
        summary: 'No date',
        rrule: 'FREQ=DAILY;COUNT=5',
      );
      expect(
        todo.expandOccurrences(
          rangeStart: DateTime.utc(2026, 8, 1),
          rangeEnd: DateTime.utc(2026, 8, 10),
        ),
        isEmpty,
      );
    });
  });

  group('CalendarJournal.expandOccurrences', () {
    test('expands daily journal', () {
      final journal = CalendarJournal(
        uid: 'j1',
        calendarId: 'c',
        summary: 'Log',
        dtstart: DateTime.utc(2026, 8, 1),
        isAllDay: true,
        rrule: 'FREQ=DAILY;COUNT=3',
      );
      final dates = journal.expandOccurrences(
        rangeStart: DateTime.utc(2026, 8, 1),
        rangeEnd: DateTime.utc(2026, 8, 10),
      );
      expect(dates, [
        DateTime.utc(2026, 8, 1),
        DateTime.utc(2026, 8, 2),
        DateTime.utc(2026, 8, 3),
      ]);
    });
  });
}
