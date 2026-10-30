/// Utility functions for iCalendar date/time formatting and text handling
class ICalendarUtils {
  ICalendarUtils._();

  /// Format DateTime to iCalendar UTC format (20240115T100000Z)
  static String formatUtc(DateTime dt) {
    final utc = dt.toUtc();
    return '${utc.year.toString().padLeft(4, '0')}'
        '${utc.month.toString().padLeft(2, '0')}'
        '${utc.day.toString().padLeft(2, '0')}T'
        '${utc.hour.toString().padLeft(2, '0')}'
        '${utc.minute.toString().padLeft(2, '0')}'
        '${utc.second.toString().padLeft(2, '0')}Z';
  }

  /// Format DateTime to iCalendar floating local format (20240115T100000)
  ///
  /// Uses the DateTime's year/month/day/hour/minute/second as-is so a TZID
  /// can label wall-clock time without converting to UTC.
  static String formatFloating(DateTime dt) {
    return '${dt.year.toString().padLeft(4, '0')}'
        '${dt.month.toString().padLeft(2, '0')}'
        '${dt.day.toString().padLeft(2, '0')}T'
        '${dt.hour.toString().padLeft(2, '0')}'
        '${dt.minute.toString().padLeft(2, '0')}'
        '${dt.second.toString().padLeft(2, '0')}';
  }

  /// Write a DTSTART/DUE/DTEND line, using TZID wall-clock when [tzid] is set.
  static void writeTaggedDateTime(
    StringBuffer buffer,
    String name,
    DateTime dt, {
    required bool isAllDay,
    String? tzid,
  }) {
    if (isAllDay) {
      buffer.writeln('$name;VALUE=DATE:${formatDate(dt)}');
    } else if (tzid != null && tzid.isNotEmpty) {
      buffer.writeln('$name;TZID=$tzid:${formatFloating(dt)}');
    } else {
      buffer.writeln('$name:${formatUtc(dt.toUtc())}');
    }
  }

  /// Format DateTime to iCalendar date-only format (20240115)
  static String formatDate(DateTime dt) {
    return '${dt.year.toString().padLeft(4, '0')}'
        '${dt.month.toString().padLeft(2, '0')}'
        '${dt.day.toString().padLeft(2, '0')}';
  }

  /// Escape special characters for iCalendar text values
  ///
  /// Escapes: backslash, newline, comma, semicolon
  static String escapeText(String text) {
    return text
        .replaceAll('\\', '\\\\')
        .replaceAll('\n', '\\n')
        .replaceAll(',', '\\,')
        .replaceAll(';', '\\;');
  }

  /// Unescape special characters from iCalendar text values
  static String unescapeText(String text) {
    return text
        .replaceAll('\\n', '\n')
        .replaceAll('\\N', '\n')
        .replaceAll('\\,', ',')
        .replaceAll('\\;', ';')
        .replaceAll('\\\\', '\\');
  }

  /// Escape special XML characters to prevent XML injection
  static String escapeXml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  /// Parse an ISO-8601 / RFC 5545 duration (e.g. `PT1H30M`, `P1W1DT1H1M1S`).
  ///
  /// Weeks (`W`) and days (`D`) are accepted on the date side; hours, minutes,
  /// and seconds after `T`. A leading `+` or `-` is honored.
  static Duration? parseDuration(String raw) {
    var s = raw.trim().toUpperCase();
    if (s.startsWith('+')) s = s.substring(1);
    if (s.startsWith('-')) {
      final pos = parseDuration(s.substring(1));
      return pos == null ? null : -pos;
    }
    if (!s.startsWith('P')) return null;
    s = s.substring(1);

    var days = 0, hours = 0, minutes = 0, seconds = 0;
    final t = s.indexOf('T');
    final datePart = t >= 0 ? s.substring(0, t) : s;
    final timePart = t >= 0 ? s.substring(t + 1) : '';

    final week = RegExp(r'(\d+)W').firstMatch(datePart);
    if (week != null) days += int.parse(week.group(1)!) * 7;
    final day = RegExp(r'(\d+)D').firstMatch(datePart);
    if (day != null) days += int.parse(day.group(1)!);
    final h = RegExp(r'(\d+)H').firstMatch(timePart);
    if (h != null) hours = int.parse(h.group(1)!);
    final m = RegExp(r'(\d+)M').firstMatch(timePart);
    if (m != null) minutes = int.parse(m.group(1)!);
    final sec = RegExp(r'(\d+)S').firstMatch(timePart);
    if (sec != null) seconds = int.parse(sec.group(1)!);

    return Duration(
      days: days,
      hours: hours,
      minutes: minutes,
      seconds: seconds,
    );
  }

  /// Format a [Duration] as ISO-8601 / RFC 5545 (e.g. `P1W1DT1H1M1S`).
  ///
  /// Weeks, days, hours, minutes, and seconds are all emitted when non-zero.
  /// Zero duration is `PT0S`. Negative values get a leading `-`.
  static String formatDuration(Duration d) {
    if (d.isNegative) return '-${formatDuration(d.abs())}';

    const secondsPerWeek = 7 * Duration.secondsPerDay;
    var remaining = d.inSeconds;
    final weeks = remaining ~/ secondsPerWeek;
    remaining %= secondsPerWeek;
    final days = remaining ~/ Duration.secondsPerDay;
    remaining %= Duration.secondsPerDay;
    final hours = remaining ~/ Duration.secondsPerHour;
    remaining %= Duration.secondsPerHour;
    final minutes = remaining ~/ Duration.secondsPerMinute;
    final seconds = remaining % Duration.secondsPerMinute;

    final hasDate = weeks != 0 || days != 0;
    final hasTime = hours != 0 || minutes != 0 || seconds != 0;

    final buffer = StringBuffer('P');
    if (weeks != 0) buffer.write('${weeks}W');
    if (days != 0) buffer.write('${days}D');
    if (hasTime || !hasDate) {
      buffer.write('T');
      if (hours != 0) buffer.write('${hours}H');
      if (minutes != 0) buffer.write('${minutes}M');
      if (seconds != 0 || !hasTime) buffer.write('${seconds}S');
    }
    return buffer.toString();
  }
}
