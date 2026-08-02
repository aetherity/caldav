import '../utils/icalendar_utils.dart';
import 'free_busy.dart';

/// Parse and build VFREEBUSY iCalendar data (RFC 5545).
class FreeBusyParser {
  FreeBusyParser._();

  /// Parse the first VFREEBUSY component from an iCalendar document.
  static FreeBusy? parse(
    String icalendar, {
    Uri? sourceUrl,
  }) {
    final lines = _unfoldLines(icalendar);
    final component = _extractComponent(lines, 'VFREEBUSY');
    if (component.isEmpty) return null;

    final props = _parsePropertyLines(component);

    final uid = props.singleValue('UID');
    final dtstart = _parseDateTime(props.singleValue('DTSTART'));
    final dtend = _parseDateTime(props.singleValue('DTEND'));
    final organizer = _stripMailto(props.singleValue('ORGANIZER'));

    final attendees = <String>[];
    for (final value in props.valuesFor('ATTENDEE')) {
      final addr = _stripMailto(value);
      if (addr != null) attendees.add(addr);
    }

    final periods = <FreeBusyPeriod>[];
    for (final entry in props.entriesFor('FREEBUSY')) {
      final type = FreeBusyType.parse(entry.params['FBTYPE']);
      for (final periodStr in entry.value.split(',')) {
        final period = _parsePeriod(periodStr.trim(), type);
        if (period != null) periods.add(period);
      }
    }

    periods.sort((a, b) => a.start.compareTo(b.start));

    return FreeBusy(
      uid: uid,
      dtstart: dtstart,
      dtend: dtend,
      periods: periods,
      organizer: organizer,
      attendees: attendees,
      sourceUrl: sourceUrl,
      rawIcalendar: icalendar,
    );
  }

  /// Build a scheduling freebusy REQUEST (RFC 6638 / RFC 5546).
  ///
  /// Used with POST to a scheduling Outbox collection.
  static String buildScheduleRequest({
    required DateTime start,
    required DateTime end,
    required List<String> attendees,
    String? organizer,
    String? uid,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('BEGIN:VCALENDAR');
    buffer.writeln('VERSION:2.0');
    buffer.writeln('PRODID:-//dart-caldav-client//EN');
    buffer.writeln('METHOD:REQUEST');
    buffer.writeln('BEGIN:VFREEBUSY');
    buffer.writeln(
      'UID:${uid ?? 'freebusy-${DateTime.now().millisecondsSinceEpoch}'}',
    );
    buffer.writeln(
      'DTSTAMP:${ICalendarUtils.formatUtc(DateTime.now().toUtc())}',
    );
    buffer.writeln('DTSTART:${ICalendarUtils.formatUtc(start.toUtc())}');
    buffer.writeln('DTEND:${ICalendarUtils.formatUtc(end.toUtc())}');
    if (organizer != null && organizer.isNotEmpty) {
      buffer.writeln('ORGANIZER:${_ensureMailto(organizer)}');
    }
    for (final attendee in attendees) {
      if (attendee.isEmpty) continue;
      buffer.writeln('ATTENDEE:${_ensureMailto(attendee)}');
    }
    buffer.writeln('END:VFREEBUSY');
    buffer.writeln('END:VCALENDAR');
    return buffer.toString();
  }

  /// Serialize a [FreeBusy] to a VFREEBUSY document (METHOD optional).
  static String serialize(
    FreeBusy freeBusy, {
    String? method,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('BEGIN:VCALENDAR');
    buffer.writeln('VERSION:2.0');
    buffer.writeln('PRODID:-//dart-caldav-client//EN');
    if (method != null) buffer.writeln('METHOD:$method');
    buffer.writeln('BEGIN:VFREEBUSY');
    if (freeBusy.uid != null) {
      buffer.writeln('UID:${freeBusy.uid}');
    }
    buffer.writeln(
      'DTSTAMP:${ICalendarUtils.formatUtc(DateTime.now().toUtc())}',
    );
    if (freeBusy.dtstart != null) {
      buffer.writeln(
        'DTSTART:${ICalendarUtils.formatUtc(freeBusy.dtstart!.toUtc())}',
      );
    }
    if (freeBusy.dtend != null) {
      buffer.writeln(
        'DTEND:${ICalendarUtils.formatUtc(freeBusy.dtend!.toUtc())}',
      );
    }
    if (freeBusy.organizer != null) {
      buffer.writeln('ORGANIZER:${_ensureMailto(freeBusy.organizer!)}');
    }
    for (final a in freeBusy.attendees) {
      buffer.writeln('ATTENDEE:${_ensureMailto(a)}');
    }
    for (final p in freeBusy.periods) {
      final typeParam =
          p.type == FreeBusyType.busy ? '' : ';FBTYPE=${p.type.icalValue}';
      buffer.writeln(
        'FREEBUSY$typeParam:${ICalendarUtils.formatUtc(p.start.toUtc())}/'
        '${ICalendarUtils.formatUtc(p.end.toUtc())}',
      );
    }
    buffer.writeln('END:VFREEBUSY');
    buffer.writeln('END:VCALENDAR');
    return buffer.toString();
  }

  static FreeBusyPeriod? _parsePeriod(String value, FreeBusyType type) {
    if (value.isEmpty) return null;
    final slash = value.indexOf('/');
    if (slash <= 0) return null;

    final startStr = value.substring(0, slash);
    final endOrDuration = value.substring(slash + 1);
    final start = _parseDateTime(startStr);
    if (start == null) return null;

    DateTime? end;
    if (endOrDuration.startsWith('P') || endOrDuration.startsWith('+P')) {
      final duration = _parseDuration(endOrDuration);
      if (duration == null) return null;
      end = start.add(duration);
    } else {
      end = _parseDateTime(endOrDuration);
    }
    if (end == null) return null;

    return FreeBusyPeriod(start: start, end: end, type: type);
  }

  /// Parse ISO-8601 duration used in FREEBUSY (e.g. `PT1H30M`, `P1DT2H`).
  static Duration? _parseDuration(String raw) {
    var s = raw.trim().toUpperCase();
    if (s.startsWith('+')) s = s.substring(1);
    if (s.startsWith('-')) {
      // Negative durations are rare for FREEBUSY; reject for simplicity.
      return null;
    }
    if (!s.startsWith('P')) return null;
    s = s.substring(1);

    var days = 0;
    var hours = 0;
    var minutes = 0;
    var seconds = 0;

    final timeIndex = s.indexOf('T');
    final datePart = timeIndex >= 0 ? s.substring(0, timeIndex) : s;
    final timePart = timeIndex >= 0 ? s.substring(timeIndex + 1) : '';

    final dayMatch = RegExp(r'(\d+)D').firstMatch(datePart);
    if (dayMatch != null) days = int.parse(dayMatch.group(1)!);
    final weekMatch = RegExp(r'(\d+)W').firstMatch(datePart);
    if (weekMatch != null) days += int.parse(weekMatch.group(1)!) * 7;

    final hourMatch = RegExp(r'(\d+)H').firstMatch(timePart);
    if (hourMatch != null) hours = int.parse(hourMatch.group(1)!);
    final minMatch = RegExp(r'(\d+)M').firstMatch(timePart);
    if (minMatch != null) minutes = int.parse(minMatch.group(1)!);
    final secMatch = RegExp(r'(\d+)S').firstMatch(timePart);
    if (secMatch != null) seconds = int.parse(secMatch.group(1)!);

    return Duration(
      days: days,
      hours: hours,
      minutes: minutes,
      seconds: seconds,
    );
  }

  static DateTime? _parseDateTime(String? value) {
    if (value == null || value.isEmpty) return null;
    // 20240115T100000Z or 20240115T100000 or 20240115
    final v = value.trim();
    if (v.length == 8 && RegExp(r'^\d{8}$').hasMatch(v)) {
      final y = int.parse(v.substring(0, 4));
      final m = int.parse(v.substring(4, 6));
      final d = int.parse(v.substring(6, 8));
      return DateTime.utc(y, m, d);
    }
    final match = RegExp(
      r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})(Z)?$',
    ).firstMatch(v);
    if (match == null) return DateTime.tryParse(v)?.toUtc();
    final y = int.parse(match.group(1)!);
    final m = int.parse(match.group(2)!);
    final d = int.parse(match.group(3)!);
    final h = int.parse(match.group(4)!);
    final min = int.parse(match.group(5)!);
    final s = int.parse(match.group(6)!);
    // Treat as UTC when Z present or always for freebusy server data
    return DateTime.utc(y, m, d, h, min, s);
  }

  static String? _stripMailto(String? value) {
    if (value == null) return null;
    var v = value.trim();
    // ORGANIZER;CN=Name:mailto:user@example.com — value already split at :
    if (v.toLowerCase().startsWith('mailto:')) {
      v = v.substring(7);
    }
    return v.isEmpty ? null : v;
  }

  static String _ensureMailto(String address) {
    final a = address.trim();
    if (a.toLowerCase().startsWith('mailto:')) return a;
    return 'mailto:$a';
  }

  static List<String> _unfoldLines(String icalendar) {
    final unfolded = icalendar
        .replaceAll('\r\n ', '')
        .replaceAll('\r\n\t', '')
        .replaceAll('\n ', '')
        .replaceAll('\n\t', '');
    return unfolded.split(RegExp(r'\r?\n')).where((l) => l.isNotEmpty).toList();
  }

  static List<String> _extractComponent(List<String> lines, String component) {
    final result = <String>[];
    var inComponent = false;
    for (final line in lines) {
      if (line == 'BEGIN:$component') {
        inComponent = true;
      } else if (line == 'END:$component') {
        break;
      } else if (inComponent) {
        result.add(line);
      }
    }
    return result;
  }

  static _PropBag _parsePropertyLines(List<String> lines) {
    final bag = _PropBag();
    for (final line in lines) {
      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      final nameAndParams = line.substring(0, colon);
      final value = line.substring(colon + 1);
      final parts = nameAndParams.split(';');
      final name = parts.first.toUpperCase();
      final params = <String, String>{};
      for (var i = 1; i < parts.length; i++) {
        final eq = parts[i].indexOf('=');
        if (eq > 0) {
          params[parts[i].substring(0, eq).toUpperCase()] =
              parts[i].substring(eq + 1);
        }
      }
      bag.add(name, value, params);
    }
    return bag;
  }
}

class _PropBag {
  final List<_PropEntry> _entries = [];

  void add(String name, String value, Map<String, String> params) {
    _entries.add(_PropEntry(name, value, params));
  }

  String? singleValue(String name) {
    for (final e in _entries) {
      if (e.name == name) return e.value;
    }
    return null;
  }

  List<String> valuesFor(String name) =>
      _entries.where((e) => e.name == name).map((e) => e.value).toList();

  List<_PropEntry> entriesFor(String name) =>
      _entries.where((e) => e.name == name).toList();
}

class _PropEntry {
  final String name;
  final String value;
  final Map<String, String> params;

  _PropEntry(this.name, this.value, this.params);
}
