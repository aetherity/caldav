import 'package:caldav/caldav.dart';

/// Example: CalDAV calendars/events and CardDAV contacts via [DavSession].
void main() async {
  DavSession? session;

  try {
    print('Connecting to DAV server (CalDAV + CardDAV)...');
    session = await DavSession.connect(
      baseUrl: 'https://...',
      username: '...',
      password: '...',
    );
    print(
      'Connected! caldav=${session.hasCalDav} carddav=${session.hasCardDav}\n',
    );

    if (session.hasCalDav) {
      await _printCalendars(session.caldav);
    }

    if (session.hasCardDav) {
      await _printContacts(session.carddav);
    }
  } on CalDavException catch (e) {
    print('DAV Error: ${e.message}');
  } finally {
    session?.close();
  }
}

Future<void> _printCalendars(CalDavClient client) async {
  final calendars = await client.getCalendars();
  print('Found ${calendars.length} calendar(s):');
  for (final cal in calendars) {
    print('  - ${cal.displayName} (uid: ${cal.uid})');
  }

  final start = DateTime.utc(2026, 1, 1);
  final end = DateTime.utc(2026, 2, 1);

  print('\n${'=' * 40}');
  print('Calendar sync / events');
  print('=' * 40);

  for (final calendar in calendars) {
    print('\n[${calendar.displayName}]');
    if (calendar.syncToken != null) {
      print('  advertised sync-token: ${calendar.syncToken}');
    }

    try {
      final sync = await client.syncCalendar(calendar, limit: 50);
      print(
        '  sync: +${sync.events.length} events, '
        '+${sync.todos.length} todos, '
        '-${sync.deletedHrefs.length} deleted, '
        'token=${sync.syncToken}',
      );
      for (final event in sync.events.take(10)) {
        print('    ${_formatDate(event.start)} - ${event.summary}');
      }
    } on InvalidSyncTokenException {
      print('  sync token invalid — full re-sync required');
    } on CalDavException catch (e) {
      print('  sync not available: ${e.message}');
      final events = await client.getEvents(calendar, start: start, end: end);
      if (events.isEmpty) {
        print('  No events');
      } else {
        events.sort((a, b) => a.start.compareTo(b.start));
        for (final event in events) {
          print('  ${_formatDate(event.start)} - ${event.summary}');
        }
      }
    }

    final todos = await client.getTodos(calendar);
    for (final todo in todos) {
      print('  Todo: ${todo.summary} (done: ${todo.isCompleted})');
    }
  }
}

Future<void> _printContacts(CardDavClient client) async {
  final books = await client.getAddressBooks();
  print('\n${'=' * 40}');
  print('Address books: ${books.length}');
  print('=' * 40);

  for (final book in books) {
    print('\n[${book.displayName}]');
    if (book.syncToken != null) {
      print('  advertised sync-token: ${book.syncToken}');
    }

    try {
      final sync = await client.syncAddressBook(book, limit: 50);
      print(
        '  sync: +${sync.contacts.length} contacts, '
        '-${sync.deletedHrefs.length} deleted, '
        'token=${sync.syncToken}',
      );
      for (final c in sync.contacts.take(10)) {
        print('    ${c.formattedName} <${c.primaryEmail ?? '-'}>');
      }
    } on InvalidSyncTokenException {
      print('  sync token invalid — full re-sync required');
    } on CalDavException catch (e) {
      print('  sync not available: ${e.message}');
      final contacts = await client.getContacts(book);
      for (final c in contacts.take(10)) {
        print('  ${c.formattedName} <${c.primaryEmail ?? '-'}>');
      }
    }

    final hits = await client.queryContacts(
      book,
      ContactFilter.anyText('a', limit: 5),
    );
    print('  Sample anyText("a") hits: ${hits.length}');
  }
}

String _formatDate(DateTime dt) {
  final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final weekday = weekdays[dt.weekday - 1];

  if (dt.hour == 0 && dt.minute == 0) {
    return '${dt.month}/${dt.day} ($weekday) All day';
  }

  return '${dt.month}/${dt.day} ($weekday) '
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';
}
