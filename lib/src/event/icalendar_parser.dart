import '../utils/icalendar_utils.dart';
import 'event.dart';
import 'icalendar_types.dart';
import 'journal.dart';
import 'todo.dart';

/// Properties handled structurally (not stored in [ICalRawProperty] extras).
const _handledNames = {
  'UID',
  'SUMMARY',
  'DESCRIPTION',
  'LOCATION',
  'DTSTART',
  'DTEND',
  'DUE',
  'DURATION',
  'DTSTAMP',
  'CREATED',
  'LAST-MODIFIED',
  'SEQUENCE',
  'STATUS',
  'TRANSP',
  'CLASS',
  'CATEGORIES',
  'URL',
  'GEO',
  'PRIORITY',
  'PERCENT-COMPLETE',
  'COMPLETED',
  'ORGANIZER',
  'ATTENDEE',
  'COMMENT',
  'CONTACT',
  'RESOURCES',
  'RELATED-TO',
  'RRULE',
  'RECURRENCE-ID',
  'EXDATE',
  'RDATE',
  'PRODID',
  'VERSION',
  'CALSCALE',
  'METHOD',
};

/// Parser for iCalendar (RFC 5545) data.
class ICalendarParser {
  ICalendarParser._();

  /// Parse iCalendar string to [CalendarEvent] (first VEVENT).
  static CalendarEvent? parseEvent(
    String icalendar, {
    required String calendarId,
    Uri? href,
    String? etag,
    bool isReadOnly = false,
  }) {
    final lines = unfoldLines(icalendar);
    final eventLines = extractComponentLines(lines, 'VEVENT');
    if (eventLines.isEmpty) return null;

    final bag = PropertyBag.parse(eventLines);
    final alarms = extractAlarms(eventLines);
    final shared = _parseShared(bag, eventLines);

    final uid = bag.firstValue('UID');
    if (uid == null) return null;

    final summary = bag.firstValue('SUMMARY') ?? 'Untitled';
    final dtstartEntry = bag.firstEntry('DTSTART');
    final start = parseDateTimeValue(
      dtstartEntry?.value,
      dtstartEntry?.params['VALUE'],
    );
    if (start == null) return null;

    final isAllDay = _isDateOnly(dtstartEntry);
    final timeZoneId = dtstartEntry?.params['TZID'];

    final dtendEntry = bag.firstEntry('DTEND');
    var end = parseDateTimeValue(
      dtendEntry?.value,
      dtendEntry?.params['VALUE'],
    );

    Duration? explicitDuration;
    final durationStr = bag.firstValue('DURATION');
    if (end == null && durationStr != null) {
      explicitDuration = parseDuration(durationStr);
      if (explicitDuration != null) {
        end = start.add(explicitDuration);
      }
    }

    // Convert exclusive DTEND to inclusive for all-day events (RFC 5545).
    DateTime? inclusiveEnd;
    if (isAllDay && end != null && explicitDuration == null) {
      final days = end.difference(start).inDays;
      if (days <= 1) {
        inclusiveEnd = null;
      } else {
        inclusiveEnd = end.subtract(const Duration(days: 1));
      }
    } else if (explicitDuration != null) {
      // Keep end from duration for timed events; all-day duration rare.
      inclusiveEnd = isAllDay && end != null
          ? end.subtract(const Duration(days: 1))
          : end;
      if (isAllDay && inclusiveEnd != null && !inclusiveEnd.isAfter(start)) {
        inclusiveEnd = null;
      }
    } else {
      inclusiveEnd = end;
    }

    return CalendarEvent(
      uid: uid,
      calendarId: calendarId,
      href: href,
      etag: etag,
      start: start,
      end: inclusiveEnd,
      explicitDuration: explicitDuration,
      summary: unescapeText(summary),
      description: _text(bag, 'DESCRIPTION'),
      location: _text(bag, 'LOCATION'),
      isAllDay: isAllDay,
      status: EventStatus.tryParse(bag.firstValue('STATUS')),
      transparency: TimeTransparency.tryParse(bag.firstValue('TRANSP')),
      priority: int.tryParse(bag.firstValue('PRIORITY') ?? ''),
      rawIcalendar: icalendar,
      isReadOnly: isReadOnly,
      timeZoneId: timeZoneId,
      alarms: alarms,
      rrule: shared.rrule,
      recurrenceId: shared.recurrenceId,
      exdate: shared.exdate,
      rdate: shared.rdate,
      categories: shared.categories,
      classification: shared.classification,
      url: shared.url,
      geo: shared.geo,
      created: shared.created,
      lastModified: shared.lastModified,
      dtstamp: shared.dtstamp,
      sequence: shared.sequence,
      organizer: shared.organizer,
      attendees: shared.attendees,
      comments: shared.comments,
      contacts: shared.contacts,
      resources: shared.resources,
      relatedTo: shared.relatedTo,
      extraProperties: shared.extras,
    );
  }

  /// Parse multiple VEVENT components.
  static List<CalendarEvent> parseEvents(
    String icalendar, {
    required String calendarId,
    Uri? baseHref,
    bool isReadOnly = false,
  }) {
    return _parseEach(
      icalendar,
      'VEVENT',
      (block) => parseEvent(
        block,
        calendarId: calendarId,
        isReadOnly: isReadOnly,
      ),
    );
  }

  /// Parse iCalendar string to [CalendarTodo] (first VTODO).
  static CalendarTodo? parseTodo(
    String icalendar, {
    required String calendarId,
    Uri? href,
    String? etag,
    bool isReadOnly = false,
  }) {
    final lines = unfoldLines(icalendar);
    final todoLines = extractComponentLines(lines, 'VTODO');
    if (todoLines.isEmpty) return null;

    final bag = PropertyBag.parse(todoLines);
    final alarms = extractAlarms(todoLines);
    final shared = _parseShared(bag, todoLines);

    final uid = bag.firstValue('UID');
    if (uid == null) return null;

    final dtstartEntry = bag.firstEntry('DTSTART');
    final dueEntry = bag.firstEntry('DUE');
    final dtstart = parseDateTimeValue(
      dtstartEntry?.value,
      dtstartEntry?.params['VALUE'],
    );
    final due = parseDateTimeValue(
      dueEntry?.value,
      dueEntry?.params['VALUE'],
    );

    final isAllDay = _isDateOnly(dtstartEntry) ||
        (dtstartEntry == null && _isDateOnly(dueEntry));

    return CalendarTodo(
      uid: uid,
      calendarId: calendarId,
      href: href,
      etag: etag,
      summary: unescapeText(bag.firstValue('SUMMARY') ?? 'Untitled'),
      description: _text(bag, 'DESCRIPTION'),
      location: _text(bag, 'LOCATION'),
      dtstart: dtstart,
      due: due,
      isAllDay: isAllDay,
      status: _parseTodoStatus(bag.firstValue('STATUS')),
      completed: parseDateTimeValue(bag.firstValue('COMPLETED'), null),
      percentComplete: int.tryParse(bag.firstValue('PERCENT-COMPLETE') ?? ''),
      priority: int.tryParse(bag.firstValue('PRIORITY') ?? ''),
      rawIcalendar: icalendar,
      isReadOnly: isReadOnly,
      timeZoneId: dtstartEntry?.params['TZID'] ?? dueEntry?.params['TZID'],
      alarms: alarms,
      rrule: shared.rrule,
      recurrenceId: shared.recurrenceId,
      exdate: shared.exdate,
      rdate: shared.rdate,
      categories: shared.categories,
      classification: shared.classification,
      url: shared.url,
      geo: shared.geo,
      created: shared.created,
      lastModified: shared.lastModified,
      dtstamp: shared.dtstamp,
      sequence: shared.sequence,
      organizer: shared.organizer,
      attendees: shared.attendees,
      comments: shared.comments,
      contacts: shared.contacts,
      resources: shared.resources,
      relatedTo: shared.relatedTo,
      extraProperties: shared.extras,
    );
  }

  /// Parse multiple VTODO components.
  static List<CalendarTodo> parseTodos(
    String icalendar, {
    required String calendarId,
    Uri? baseHref,
    bool isReadOnly = false,
  }) {
    return _parseEach(
      icalendar,
      'VTODO',
      (block) => parseTodo(
        block,
        calendarId: calendarId,
        isReadOnly: isReadOnly,
      ),
    );
  }

  /// Parse iCalendar string to [CalendarJournal] (first VJOURNAL).
  static CalendarJournal? parseJournal(
    String icalendar, {
    required String calendarId,
    Uri? href,
    String? etag,
    bool isReadOnly = false,
  }) {
    final lines = unfoldLines(icalendar);
    final journalLines = extractComponentLines(lines, 'VJOURNAL');
    if (journalLines.isEmpty) return null;

    final bag = PropertyBag.parse(journalLines);
    final alarms = extractAlarms(journalLines);
    final shared = _parseShared(bag, journalLines);

    final uid = bag.firstValue('UID');
    if (uid == null) return null;

    final dtstartEntry = bag.firstEntry('DTSTART');
    final dtstart = parseDateTimeValue(
      dtstartEntry?.value,
      dtstartEntry?.params['VALUE'],
    );

    return CalendarJournal(
      uid: uid,
      calendarId: calendarId,
      href: href,
      etag: etag,
      summary: unescapeText(bag.firstValue('SUMMARY') ?? 'Untitled'),
      description: _text(bag, 'DESCRIPTION'),
      location: _text(bag, 'LOCATION'),
      dtstart: dtstart,
      isAllDay: _isDateOnly(dtstartEntry),
      status: _parseJournalStatus(bag.firstValue('STATUS')),
      rawIcalendar: icalendar,
      isReadOnly: isReadOnly,
      timeZoneId: dtstartEntry?.params['TZID'],
      alarms: alarms,
      rrule: shared.rrule,
      recurrenceId: shared.recurrenceId,
      exdate: shared.exdate,
      rdate: shared.rdate,
      categories: shared.categories,
      classification: shared.classification,
      url: shared.url,
      geo: shared.geo,
      created: shared.created,
      lastModified: shared.lastModified,
      dtstamp: shared.dtstamp,
      sequence: shared.sequence,
      organizer: shared.organizer,
      attendees: shared.attendees,
      comments: shared.comments,
      contacts: shared.contacts,
      resources: shared.resources,
      relatedTo: shared.relatedTo,
      extraProperties: shared.extras,
    );
  }

  /// Parse multiple VJOURNAL components.
  static List<CalendarJournal> parseJournals(
    String icalendar, {
    required String calendarId,
    bool isReadOnly = false,
  }) {
    return _parseEach(
      icalendar,
      'VJOURNAL',
      (block) => parseJournal(
        block,
        calendarId: calendarId,
        isReadOnly: isReadOnly,
      ),
    );
  }

  /// Parse a complete VCALENDAR document into typed components.
  static ICalendarDocument parseDocument(String icalendar) {
    final lines = unfoldLines(icalendar);
    final bag = PropertyBag.parse(
      lines.where((l) => !l.startsWith('BEGIN:') && !l.startsWith('END:')).toList(),
    );

    // Prefer top-level calendar props only (before first nested component).
    final topLines = <String>[];
    for (final line in lines) {
      if (line.startsWith('BEGIN:') && line != 'BEGIN:VCALENDAR') break;
      if (line.startsWith('BEGIN:') || line.startsWith('END:')) continue;
      topLines.add(line);
    }
    final top = PropertyBag.parse(topLines);

    return ICalendarDocument(
      prodId: top.firstValue('PRODID') ?? bag.firstValue('PRODID'),
      version: top.firstValue('VERSION') ?? bag.firstValue('VERSION'),
      calscale: top.firstValue('CALSCALE') ?? bag.firstValue('CALSCALE'),
      method: top.firstValue('METHOD') ?? bag.firstValue('METHOD'),
      events: parseEvents(icalendar, calendarId: ''),
      todos: parseTodos(icalendar, calendarId: ''),
      journals: parseJournals(icalendar, calendarId: ''),
      rawIcalendar: icalendar,
    );
  }

  // ── Shared helpers (public for testing) ──────────────────────────

  /// Unfold RFC 5545 continuation lines.
  static List<String> unfoldLines(String icalendar) {
    final unfolded = icalendar
        .replaceAll('\r\n ', '')
        .replaceAll('\r\n\t', '')
        .replaceAll('\n ', '')
        .replaceAll('\n\t', '');
    return unfolded.split(RegExp(r'\r?\n')).where((l) => l.isNotEmpty).toList();
  }

  /// Extract lines of the first [component] (excluding BEGIN/END).
  /// Nested sub-components are included in the lines.
  static List<String> extractComponentLines(
    List<String> lines,
    String component,
  ) {
    final result = <String>[];
    var depth = 0;
    var capturing = false;

    for (final line in lines) {
      if (line == 'BEGIN:$component') {
        if (!capturing) {
          capturing = true;
          depth = 1;
          continue;
        }
      }
      if (!capturing) continue;

      if (line.startsWith('BEGIN:')) {
        depth++;
        result.add(line);
      } else if (line.startsWith('END:')) {
        depth--;
        if (depth == 0) break;
        result.add(line);
      } else {
        result.add(line);
      }
    }
    return result;
  }

  /// Extract VALARM sub-components from a component's lines.
  static List<CalendarAlarm> extractAlarms(List<String> componentLines) {
    final alarms = <CalendarAlarm>[];
    var inAlarm = false;
    var alarmLines = <String>[];

    for (final line in componentLines) {
      if (line == 'BEGIN:VALARM') {
        inAlarm = true;
        alarmLines = [];
      } else if (line == 'END:VALARM') {
        inAlarm = false;
        final alarm = _parseAlarm(alarmLines);
        if (alarm != null) alarms.add(alarm);
      } else if (inAlarm) {
        alarmLines.add(line);
      }
    }
    return alarms;
  }

  static CalendarAlarm? _parseAlarm(List<String> lines) {
    final bag = PropertyBag.parse(lines);
    final action = AlarmAction.tryParse(bag.firstValue('ACTION'));
    final triggerEntry = bag.firstEntry('TRIGGER');
    if (action == null || triggerEntry == null) return null;

    final attendees = bag
        .entriesFor('ATTENDEE')
        .map(_parseCalAddress)
        .whereType<CalAddress>()
        .toList();

    return CalendarAlarm(
      action: action,
      trigger: triggerEntry.value,
      triggerIsAbsolute:
          triggerEntry.params['VALUE']?.toUpperCase() == 'DATE-TIME',
      relatedToEnd: triggerEntry.params['RELATED']?.toUpperCase() == 'END',
      description: _text(bag, 'DESCRIPTION'),
      summary: _text(bag, 'SUMMARY'),
      attach: bag.firstValue('ATTACH'),
      repeat: int.tryParse(bag.firstValue('REPEAT') ?? ''),
      duration: bag.firstValue('DURATION'),
      attendees: attendees,
    );
  }

  /// Parse date-time value (UTC / local / DATE).
  static DateTime? parseDateTimeValue(String? value, String? valueType) {
    if (value == null || value.isEmpty) return null;
    try {
      if (value.endsWith('Z')) {
        return _parseIsoBasic(value.substring(0, value.length - 1), isUtc: true);
      }
      if (value.length == 8 || valueType == 'DATE') {
        final clean = value.length > 8 ? value.substring(0, 8) : value;
        return DateTime.utc(
          int.parse(clean.substring(0, 4)),
          int.parse(clean.substring(4, 6)),
          int.parse(clean.substring(6, 8)),
        );
      }
      // Floating local time — convert to UTC of local interpretation.
      return _parseIsoBasic(value, isUtc: false)?.toUtc();
    } catch (_) {
      return null;
    }
  }

  /// Parse ISO-8601 duration (e.g. `PT1H30M`, `P1W1DT1H1M1S`).
  static Duration? parseDuration(String raw) =>
      ICalendarUtils.parseDuration(raw);

  /// Format a [Duration] as ISO-8601 (e.g. `PT1H30M`, `P1W1DT1H1M1S`).
  static String formatDuration(Duration d) => ICalendarUtils.formatDuration(d);

  static String unescapeText(String text) {
    return text
        .replaceAll('\\n', '\n')
        .replaceAll('\\N', '\n')
        .replaceAll('\\,', ',')
        .replaceAll('\\;', ';')
        .replaceAll('\\\\', '\\');
  }

  // ── private ──────────────────────────────────────────────────

  static List<T> _parseEach<T>(
    String icalendar,
    String component,
    T? Function(String block) parseOne,
  ) {
    final lines = unfoldLines(icalendar);
    final results = <T>[];
    var inComp = false;
    var depth = 0;
    var body = <String>[];

    for (final line in lines) {
      if (line == 'BEGIN:$component' && !inComp) {
        inComp = true;
        depth = 1;
        body = [];
        continue;
      }
      if (!inComp) continue;
      if (line.startsWith('BEGIN:')) {
        depth++;
        body.add(line);
      } else if (line.startsWith('END:')) {
        depth--;
        if (depth == 0) {
          inComp = false;
          final block =
              'BEGIN:VCALENDAR\nVERSION:2.0\nBEGIN:$component\n${body.join('\n')}\nEND:$component\nEND:VCALENDAR';
          final parsed = parseOne(block);
          if (parsed != null) results.add(parsed);
        } else {
          body.add(line);
        }
      } else {
        body.add(line);
      }
    }
    return results;
  }

  static _SharedProps _parseShared(PropertyBag bag, List<String> lines) {
    final categories = <String>[];
    for (final v in bag.valuesFor('CATEGORIES')) {
      categories.addAll(
        v
            .split(',')
            .map((c) => unescapeText(c.trim()))
            .where((c) => c.isNotEmpty),
      );
    }

    final resources = <String>[];
    for (final v in bag.valuesFor('RESOURCES')) {
      resources.addAll(
        v
            .split(',')
            .map((c) => unescapeText(c.trim()))
            .where((c) => c.isNotEmpty),
      );
    }

    final comments = bag
        .valuesFor('COMMENT')
        .map(unescapeText)
        .toList();
    final contacts = bag
        .valuesFor('CONTACT')
        .map(unescapeText)
        .toList();

    final organizer = bag.firstEntry('ORGANIZER') != null
        ? _parseCalAddress(bag.firstEntry('ORGANIZER')!)
        : null;
    final attendees = bag
        .entriesFor('ATTENDEE')
        .map(_parseCalAddress)
        .whereType<CalAddress>()
        .toList();

    final exdate = _collectMultiDate(lines, 'EXDATE');
    final rdate = _collectMultiDate(lines, 'RDATE');

    final extras = <ICalRawProperty>[];
    for (final e in bag.entries) {
      if (_handledNames.contains(e.name)) continue;
      // Skip nested component markers already stripped
      extras.add(ICalRawProperty(
        name: e.name,
        params: e.params,
        value: e.value,
      ));
    }

    return _SharedProps(
      rrule: bag.firstValue('RRULE'),
      recurrenceId: bag.firstValue('RECURRENCE-ID'),
      exdate: exdate,
      rdate: rdate,
      categories: categories,
      classification: ICalClassification.tryParse(bag.firstValue('CLASS')),
      url: bag.firstValue('URL'),
      geo: GeoPosition.tryParse(bag.firstValue('GEO')),
      created: parseDateTimeValue(bag.firstValue('CREATED'), null),
      lastModified: parseDateTimeValue(bag.firstValue('LAST-MODIFIED'), null),
      dtstamp: parseDateTimeValue(bag.firstValue('DTSTAMP'), null),
      sequence: int.tryParse(bag.firstValue('SEQUENCE') ?? ''),
      organizer: organizer,
      attendees: attendees,
      comments: comments,
      contacts: contacts,
      resources: resources,
      relatedTo: bag.firstValue('RELATED-TO'),
      extras: extras,
    );
  }

  static List<String>? _collectMultiDate(List<String> lines, String name) {
    final values = <String>[];
    var skipDepth = 0;
    for (final line in lines) {
      if (line.startsWith('BEGIN:')) {
        skipDepth++;
        continue;
      }
      if (line.startsWith('END:')) {
        if (skipDepth > 0) skipDepth--;
        continue;
      }
      if (skipDepth > 0) continue;

      if (line == name ||
          line.startsWith('$name;') ||
          line.startsWith('$name:')) {
        final colon = line.indexOf(':');
        if (colon > 0) {
          values.addAll(
            line
                .substring(colon + 1)
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty),
          );
        }
      }
    }
    return values.isEmpty ? null : values;
  }

  static CalAddress? _parseCalAddress(PropertyEntry entry) {
    final rsvpRaw = entry.params['RSVP']?.toUpperCase();
    bool? rsvp;
    if (rsvpRaw == 'TRUE') rsvp = true;
    if (rsvpRaw == 'FALSE') rsvp = false;

    final known = {'CN', 'ROLE', 'PARTSTAT', 'RSVP', 'CUTYPE'};
    final extra = <String, String>{};
    entry.params.forEach((k, v) {
      if (!known.contains(k)) extra[k] = v;
    });

    return CalAddress(
      value: entry.value,
      commonName: entry.params['CN'],
      role: entry.params['ROLE'],
      partStat: entry.params['PARTSTAT'],
      rsvp: rsvp,
      cuType: entry.params['CUTYPE'],
      extraParams: extra,
    );
  }

  static bool _isDateOnly(PropertyEntry? entry) {
    if (entry == null) return false;
    if (entry.params['VALUE']?.toUpperCase() == 'DATE') return true;
    return entry.value.length == 8 && !entry.value.contains('T');
  }

  static String? _text(PropertyBag bag, String name) {
    final v = bag.firstValue(name);
    return v == null ? null : unescapeText(v);
  }

  static TodoStatus _parseTodoStatus(String? value) {
    switch (value?.toUpperCase()) {
      case 'COMPLETED':
        return TodoStatus.completed;
      case 'IN-PROCESS':
        return TodoStatus.inProcess;
      case 'CANCELLED':
        return TodoStatus.cancelled;
      case 'NEEDS-ACTION':
      default:
        return TodoStatus.needsAction;
    }
  }

  static JournalStatus _parseJournalStatus(String? value) {
    switch (value?.toUpperCase()) {
      case 'FINAL':
        return JournalStatus.final_;
      case 'CANCELLED':
        return JournalStatus.cancelled;
      case 'DRAFT':
      default:
        return JournalStatus.draft;
    }
  }

  static DateTime? _parseIsoBasic(String value, {bool isUtc = false}) {
    try {
      final year = int.parse(value.substring(0, 4));
      final month = int.parse(value.substring(4, 6));
      final day = int.parse(value.substring(6, 8));
      if (value.length > 8 && value.contains('T')) {
        final t = value.indexOf('T') + 1;
        final hour = int.parse(value.substring(t, t + 2));
        final minute = int.parse(value.substring(t + 2, t + 4));
        final second = value.length >= t + 6
            ? int.parse(value.substring(t + 4, t + 6))
            : 0;
        return isUtc
            ? DateTime.utc(year, month, day, hour, minute, second)
            : DateTime(year, month, day, hour, minute, second);
      }
      return isUtc
          ? DateTime.utc(year, month, day)
          : DateTime(year, month, day);
    } catch (_) {
      return null;
    }
  }
}

/// Parsed top-level VCALENDAR document.
class ICalendarDocument {
  final String? prodId;
  final String? version;
  final String? calscale;
  final String? method;
  final List<CalendarEvent> events;
  final List<CalendarTodo> todos;
  final List<CalendarJournal> journals;
  final String? rawIcalendar;

  const ICalendarDocument({
    this.prodId,
    this.version,
    this.calscale,
    this.method,
    this.events = const [],
    this.todos = const [],
    this.journals = const [],
    this.rawIcalendar,
  });
}

/// Multi-value aware property bag for iCalendar content lines.
class PropertyBag {
  final List<PropertyEntry> entries;

  const PropertyBag(this.entries);

  factory PropertyBag.parse(List<String> lines) {
    final entries = <PropertyEntry>[];
    var skipDepth = 0;

    for (final line in lines) {
      if (line.startsWith('BEGIN:')) {
        skipDepth++;
        continue;
      }
      if (line.startsWith('END:')) {
        if (skipDepth > 0) skipDepth--;
        continue;
      }
      if (skipDepth > 0) continue;

      final parsed = PropertyEntry.tryParse(line);
      if (parsed != null) entries.add(parsed);
    }
    return PropertyBag(entries);
  }

  PropertyEntry? firstEntry(String name) {
    final upper = name.toUpperCase();
    for (final e in entries) {
      if (e.name == upper) return e;
    }
    return null;
  }

  String? firstValue(String name) => firstEntry(name)?.value;

  List<String> valuesFor(String name) {
    final upper = name.toUpperCase();
    return entries.where((e) => e.name == upper).map((e) => e.value).toList();
  }

  List<PropertyEntry> entriesFor(String name) {
    final upper = name.toUpperCase();
    return entries.where((e) => e.name == upper).toList();
  }
}

/// A single iCalendar content line (name, params, value).
class PropertyEntry {
  final String name;
  final Map<String, String> params;
  final String value;

  const PropertyEntry({
    required this.name,
    this.params = const {},
    required this.value,
  });

  static PropertyEntry? tryParse(String line) {
    if (line.isEmpty) return null;
    final colon = _findUnquoted(line, ':');
    if (colon <= 0) return null;

    final nameAndParams = line.substring(0, colon);
    final value = line.substring(colon + 1);
    final parts = _splitParams(nameAndParams);
    if (parts.isEmpty) return null;

    final name = parts.first.toUpperCase();
    final params = <String, String>{};
    for (var i = 1; i < parts.length; i++) {
      final p = parts[i];
      final eq = p.indexOf('=');
      if (eq > 0) {
        final key = p.substring(0, eq).toUpperCase();
        var val = p.substring(eq + 1);
        if (val.startsWith('"') && val.endsWith('"') && val.length >= 2) {
          val = val.substring(1, val.length - 1);
        }
        params[key] = val;
      }
    }
    return PropertyEntry(name: name, params: params, value: value);
  }

  static int _findUnquoted(String s, String ch) {
    var inQuote = false;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (c == '"') inQuote = !inQuote;
      if (!inQuote && c == ch) return i;
    }
    return -1;
  }

  static List<String> _splitParams(String s) {
    final parts = <String>[];
    final buffer = StringBuffer();
    var inQuote = false;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (c == '"') {
        inQuote = !inQuote;
        buffer.write(c);
      } else if (c == ';' && !inQuote) {
        parts.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(c);
      }
    }
    if (buffer.isNotEmpty) parts.add(buffer.toString());
    return parts;
  }
}

class _SharedProps {
  final String? rrule;
  final String? recurrenceId;
  final List<String>? exdate;
  final List<String>? rdate;
  final List<String> categories;
  final ICalClassification? classification;
  final String? url;
  final GeoPosition? geo;
  final DateTime? created;
  final DateTime? lastModified;
  final DateTime? dtstamp;
  final int? sequence;
  final CalAddress? organizer;
  final List<CalAddress> attendees;
  final List<String> comments;
  final List<String> contacts;
  final List<String> resources;
  final String? relatedTo;
  final List<ICalRawProperty> extras;

  const _SharedProps({
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
    this.extras = const [],
  });
}
