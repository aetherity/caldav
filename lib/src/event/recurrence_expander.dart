import 'package:rrule/rrule.dart';

import 'calendar_component.dart';
import 'event.dart';
import 'icalendar_parser.dart';
import 'journal.dart';
import 'todo.dart';

/// Expands RFC 5545 recurrence (RRULE, RDATE, EXDATE, RECURRENCE-ID)
/// into concrete occurrence start times within a range.
///
/// Uses the [rrule](https://pub.dev/packages/rrule) package for RRULE
/// evaluation. All returned [DateTime]s are UTC.
///
/// ## Range
/// Occurrences are included when
/// `rangeStart <= occurrence < rangeEnd` (half-open interval).
///
/// ## RECURRENCE-ID
/// Components with a [CalendarComponent.recurrenceId] are treated as a single
/// modified instance: the expansion is just the component's start (if it falls
/// in range). Masters (no recurrence-id) expand RRULE/RDATE and subtract EXDATE.
class RecurrenceExpander {
  RecurrenceExpander._();

  /// Expand recurrence into occurrence start times.
  ///
  /// [dtstart] is the series anchor (VEVENT DTSTART / VTODO DTSTART).
  /// [rrule] may be a bare value (`FREQ=DAILY`) or include the `RRULE:` prefix.
  /// [rdate] / [exdate] are raw iCalendar date or date-time tokens.
  /// [recurrenceId] when non-null marks an exception instance (no series expand).
  ///
  /// [maxOccurrences] caps the result size (safety for open-ended rules).
  static List<DateTime> expand({
    required DateTime dtstart,
    String? rrule,
    List<String>? rdate,
    List<String>? exdate,
    String? recurrenceId,
    required DateTime rangeStart,
    required DateTime rangeEnd,
    bool isAllDay = false,
    int maxOccurrences = 10000,
  }) {
    if (!rangeEnd.isAfter(rangeStart)) {
      return const [];
    }
    if (maxOccurrences <= 0) return const [];

    final start = _asUtc(dtstart, isAllDay: isAllDay);
    final rangeStartUtc = _asUtc(rangeStart, isAllDay: isAllDay);
    final rangeEndUtc = _asUtc(rangeEnd, isAllDay: isAllDay);

    // Modified instance of a series: only this occurrence.
    if (recurrenceId != null && recurrenceId.isNotEmpty) {
      if (_inRange(start, rangeStartUtc, rangeEndUtc)) {
        return [start];
      }
      return const [];
    }

    final excluded = _parseDateSet(exdate, isAllDay: isAllDay);
    final added = _parseDateSet(rdate, isAllDay: isAllDay);

    final candidates = <DateTime>{};

    final hasRule = rrule != null && rrule.trim().isNotEmpty;
    if (hasRule) {
      candidates.addAll(
        _expandRrule(
          rrule: rrule.trim(),
          dtstart: start,
          rangeStart: rangeStartUtc,
          rangeEnd: rangeEndUtc,
          maxOccurrences: maxOccurrences,
        ),
      );
    } else {
      // Non-recurring (or RDATE-only): include DTSTART if in range.
      if (_inRange(start, rangeStartUtc, rangeEndUtc)) {
        candidates.add(start);
      }
    }

    // RDATE additions (only those in range).
    for (final d in added) {
      if (_inRange(d, rangeStartUtc, rangeEndUtc)) {
        candidates.add(d);
      }
    }

    // EXDATE removals (match by date for all-day, exact instant otherwise).
    candidates.removeWhere((d) => _isExcluded(d, excluded, isAllDay: isAllDay));

    final sorted = candidates.toList()..sort();
    if (sorted.length > maxOccurrences) {
      return sorted.sublist(0, maxOccurrences);
    }
    return sorted;
  }

  /// Expand a [CalendarEvent] within [rangeStart] / [rangeEnd].
  static List<DateTime> expandEvent(
    CalendarEvent event, {
    required DateTime rangeStart,
    required DateTime rangeEnd,
    int maxOccurrences = 10000,
  }) {
    return expand(
      dtstart: event.start,
      rrule: event.rrule,
      rdate: event.rdate,
      exdate: event.exdate,
      recurrenceId: event.recurrenceId,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      isAllDay: event.isAllDay,
      maxOccurrences: maxOccurrences,
    );
  }

  /// Expand a [CalendarTodo] within range.
  ///
  /// Uses [CalendarTodo.dtstart], falling back to [CalendarTodo.due] as the
  /// recurrence anchor when DTSTART is absent. Returns an empty list when no
  /// anchor date is available.
  static List<DateTime> expandTodo(
    CalendarTodo todo, {
    required DateTime rangeStart,
    required DateTime rangeEnd,
    int maxOccurrences = 10000,
  }) {
    final anchor = todo.dtstart ?? todo.due;
    if (anchor == null) return const [];
    return expand(
      dtstart: anchor,
      rrule: todo.rrule,
      rdate: todo.rdate,
      exdate: todo.exdate,
      recurrenceId: todo.recurrenceId,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      isAllDay: todo.isAllDay,
      maxOccurrences: maxOccurrences,
    );
  }

  /// Expand a [CalendarJournal] within range.
  ///
  /// Requires [CalendarJournal.dtstart]; returns empty when missing.
  static List<DateTime> expandJournal(
    CalendarJournal journal, {
    required DateTime rangeStart,
    required DateTime rangeEnd,
    int maxOccurrences = 10000,
  }) {
    if (journal.dtstart == null) return const [];
    return expand(
      dtstart: journal.dtstart!,
      rrule: journal.rrule,
      rdate: journal.rdate,
      exdate: journal.exdate,
      recurrenceId: journal.recurrenceId,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      isAllDay: journal.isAllDay,
      maxOccurrences: maxOccurrences,
    );
  }

  static Iterable<DateTime> _expandRrule({
    required String rrule,
    required DateTime dtstart,
    required DateTime rangeStart,
    required DateTime rangeEnd,
    required int maxOccurrences,
  }) {
    final rule = _parseRrule(rrule);
    if (rule == null) return const [];

    // rrule package requires isUtc == true and ignores the actual zone.
    final startUtc = DateTime.utc(
      dtstart.year,
      dtstart.month,
      dtstart.day,
      dtstart.hour,
      dtstart.minute,
      dtstart.second,
      dtstart.millisecond,
      dtstart.microsecond,
    );

    try {
      final instances = rule.getInstances(start: startUtc);
      final out = <DateTime>[];
      for (final instance in instances) {
        if (!instance.isBefore(rangeEnd)) break;
        if (!instance.isBefore(rangeStart) || instance.isAtSameMomentAs(rangeStart)) {
          // half-open: include if rangeStart <= instance < rangeEnd
          if (!instance.isBefore(rangeStart) && instance.isBefore(rangeEnd)) {
            out.add(instance);
            if (out.length >= maxOccurrences) break;
          }
        }
        // Still before rangeStart — keep iterating until we enter the range.
      }
      return out;
    } catch (_) {
      // Malformed or unsupported RRULE parts: treat as non-expandable.
      return const [];
    }
  }

  static RecurrenceRule? _parseRrule(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    // Strip property name if present.
    if (s.toUpperCase().startsWith('RRULE:')) {
      s = s.substring(6);
    }
    // RecurrenceRule.fromString expects "RRULE:..." form.
    final withPrefix = s.toUpperCase().startsWith('RRULE:') ? s : 'RRULE:$s';
    try {
      return RecurrenceRule.fromString(withPrefix);
    } catch (_) {
      return null;
    }
  }

  static Set<DateTime> _parseDateSet(
    List<String>? tokens, {
    required bool isAllDay,
  }) {
    if (tokens == null || tokens.isEmpty) return {};
    final set = <DateTime>{};
    for (final token in tokens) {
      final t = token.trim();
      if (t.isEmpty) continue;
      // PERIOD form RDATE;VALUE=PERIOD:start/end — use start only.
      final slash = t.indexOf('/');
      final value = slash > 0 ? t.substring(0, slash) : t;
      final valueType = value.length == 8 && !value.contains('T') ? 'DATE' : null;
      final parsed = ICalendarParser.parseDateTimeValue(value, valueType);
      if (parsed != null) {
        set.add(_asUtc(parsed, isAllDay: isAllDay || valueType == 'DATE'));
      }
    }
    return set;
  }

  static bool _isExcluded(
    DateTime candidate,
    Set<DateTime> excluded, {
    required bool isAllDay,
  }) {
    if (excluded.isEmpty) return false;
    if (isAllDay) {
      final c = DateTime.utc(candidate.year, candidate.month, candidate.day);
      for (final e in excluded) {
        final d = DateTime.utc(e.year, e.month, e.day);
        if (d == c) return true;
      }
      return false;
    }
    return excluded.contains(candidate) ||
        excluded.any((e) => e.isAtSameMomentAs(candidate));
  }

  static bool _inRange(DateTime d, DateTime rangeStart, DateTime rangeEnd) {
    return !d.isBefore(rangeStart) && d.isBefore(rangeEnd);
  }

  static DateTime _asUtc(DateTime dt, {required bool isAllDay}) {
    if (isAllDay) {
      return DateTime.utc(dt.year, dt.month, dt.day);
    }
    if (dt.isUtc) return dt;
    return dt.toUtc();
  }
}

/// Convenience recurrence expansion on calendar components.
extension CalendarEventRecurrence on CalendarEvent {
  /// Occurrence start times in `[rangeStart, rangeEnd)`.
  ///
  /// See [RecurrenceExpander.expandEvent].
  List<DateTime> expandOccurrences({
    required DateTime rangeStart,
    required DateTime rangeEnd,
    int maxOccurrences = 10000,
  }) {
    return RecurrenceExpander.expandEvent(
      this,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      maxOccurrences: maxOccurrences,
    );
  }
}

/// Convenience recurrence expansion for todos.
extension CalendarTodoRecurrence on CalendarTodo {
  /// Occurrence start times in `[rangeStart, rangeEnd)`.
  List<DateTime> expandOccurrences({
    required DateTime rangeStart,
    required DateTime rangeEnd,
    int maxOccurrences = 10000,
  }) {
    return RecurrenceExpander.expandTodo(
      this,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      maxOccurrences: maxOccurrences,
    );
  }
}

/// Convenience recurrence expansion for journals.
extension CalendarJournalRecurrence on CalendarJournal {
  /// Occurrence start times in `[rangeStart, rangeEnd)`.
  List<DateTime> expandOccurrences({
    required DateTime rangeStart,
    required DateTime rangeEnd,
    int maxOccurrences = 10000,
  }) {
    return RecurrenceExpander.expandJournal(
      this,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      maxOccurrences: maxOccurrences,
    );
  }
}
