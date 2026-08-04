# caldav

A Dart/Flutter client for **CalDAV**, **CardDAV**, and **WebDAV**. Calendar and contact CRUD, RFC 6578 collection sync, dual discovery, and sync-token caching.

## Features

- **Server Discovery** (RFC 6764) — `.well-known/caldav` and `.well-known/carddav`
- **CalDAV** — calendars, VEVENT / VTODO / VJOURNAL CRUD, free/busy, calendar-query / multiget
- **CardDAV** — address books, contacts (vCard), filters, multiget
- **Collection Sync** (RFC 6578) — incremental `sync-collection` for calendars and address books
- **Sync Token Cache** — persist tokens and auto-recover from invalid tokens
- **DavSession** — one connection/auth for both CalDAV and CardDAV
- **WebDAV foundation** — PROPFIND, PROPPATCH, MKCOL, COPY, MOVE, REPORT, …
- **Authentication** — Basic, Bearer (OAuth), custom Dio
- **Conflict Detection** — ETag optimistic locking
- **Read-Only Protection** — ACL-based write guards
- **HTTPS by Default** — secure connections with opt-out for development

## Installation

```yaml
dependencies:
  caldav: ^2.4.0
```

## Quick Start (CalDAV)

```dart
import 'package:caldav/caldav.dart';

void main() async {
  final client = await CalDavClient.connect(
    baseUrl: 'https://caldav.example.com',
    username: 'user@example.com',
    password: 'password',
  );

  try {
    final calendars = await client.getCalendars();
    for (final cal in calendars) {
      print('${cal.displayName} (uid: ${cal.uid})');
    }

    final start = DateTime.utc(2024, 1, 1);
    final end = DateTime.utc(2024, 2, 1);

    for (final calendar in calendars) {
      final events = await client.getEvents(calendar, start: start, end: end);
      for (final event in events) {
        print('${event.summary} at ${event.start}');
      }
    }
  } finally {
    client.close();
  }
}
```

## Dual session (CalDAV + CardDAV)

Use [DavSession] when the same host serves both protocols (Nextcloud, Fastmail, iCloud, …):

```dart
final session = await DavSession.connect(
  baseUrl: 'https://dav.example.com',
  username: 'user',
  password: 'pass',
);

try {
  if (session.hasCalDav) {
    final calendars = await session.caldav.getCalendars();
  }
  if (session.hasCardDav) {
    final books = await session.carddav.getAddressBooks();
  }
} finally {
  session.close(); // owns the shared Dio
}
```

## Collection sync (RFC 6578)

Incremental sync returns only members that changed since the last token, plus deletions.

### Manual token handling

```dart
// Initial full sync
var result = await client.syncCalendar(calendar);
// Persist result.syncToken; apply result.events, result.todos, result.deletedHrefs

// Later incremental sync
try {
  result = await client.syncCalendar(
    calendar,
    syncToken: result.syncToken,
  );
} on InvalidSyncTokenException {
  // Server rejected the token — full re-sync required
  result = await client.syncCalendar(calendar);
}
```

CardDAV:

```dart
var ab = await card.syncAddressBook(book);
ab = await card.syncAddressBook(book, syncToken: ab.syncToken);
// ab.contacts, ab.deletedHrefs, ab.syncToken
```

Options: `limit`, `includeData`, `followTruncation` (default `true`), `SyncLevel.members` / `infinite`.

### Sync token cache (recommended)

[SyncTokenCache] loads and saves tokens for you and retries once on invalid tokens:

```dart
// In-memory (process lifetime only)
final cache = SyncTokenCache(MemorySyncTokenStore());

// Or JSON for SharedPreferences / file persistence
final store = JsonSyncTokenStore(
  initial: JsonSyncTokenStore.fromJson(prefs.getString('dav_sync') ?? '{}').snapshot,
  onChange: (json) => prefs.setString('dav_sync', json),
);
final cache = SyncTokenCache(store);

// Calendar
final calResult = await cache.syncCalendar(client, calendar);
// Token already stored; apply calResult.events / .todos / .deletedHrefs

// Address book
final abResult = await cache.syncAddressBook(cardClient, book);
```

Implement [SyncTokenStore] for custom backends (SQLite, secure storage, …). Keys default to normalized collection hrefs via [SyncTokenKeys.forHref].

## CardDAV contacts

```dart
import 'package:caldav/carddav.dart'; // or package:caldav/caldav.dart

final card = await CardDavClient.connect(
  baseUrl: 'https://carddav.example.com',
  username: 'user@example.com',
  password: 'password',
);

try {
  final books = await card.getAddressBooks();
  final contacts = await card.getContacts(books.first);

  final created = await card.createContact(
    books.first,
    Contact(
      uid: 'contact-${DateTime.now().millisecondsSinceEpoch}',
      addressBookId: books.first.uid,
      formattedName: 'Jane Doe',
      emails: [
        VCardTypedValue(value: 'jane@example.com', types: ['WORK']),
      ],
    ),
  );

  // Structured search
  final hits = await card.queryContacts(
    books.first,
    ContactFilter.anyText('jane'),
  );
} finally {
  card.close();
}
```

## Security

By default only HTTPS is allowed. For local development:

```dart
final client = await CalDavClient.connect(
  baseUrl: 'http://localhost:8080',
  username: 'test',
  password: 'test',
  allowInsecure: true, // development only
);
```

> **Warning**: HTTP transmits credentials in plain text. Only use `allowInsecure: true` for local development.

## Authentication Methods

### Basic Authentication

```dart
final client = await CalDavClient.connect(
  baseUrl: 'https://caldav.example.com',
  username: 'user@example.com',
  password: 'password',
);
```

### Bearer Token (OAuth)

```dart
final client = CalDavClient.withToken(
  baseUrl: 'https://caldav.example.com',
  token: 'your_oauth_access_token',
);
await client.discover();
```

### Custom Dio Instance

```dart
final dio = Dio(BaseOptions(
  baseUrl: 'https://caldav.example.com',
  headers: {'Authorization': 'Custom scheme'},
));

final client = CalDavClient.withDio(
  baseUrl: 'https://caldav.example.com',
  dio: dio,
);
await client.discover();
// close() does not close dio by default (ownsDio: false)
```

## Calendar Operations

### List Calendars

```dart
final calendars = await client.getCalendars();
for (final cal in calendars) {
  print('${cal.displayName} (uid: ${cal.uid})');
  print('  URL: ${cal.href}');
  print('  Color: ${cal.color}');
  print('  Read-only: ${cal.isReadOnly}');
  print('  Sync token: ${cal.syncToken}'); // if advertised
}
```

### Create / Update / Delete Calendar

```dart
final calendar = await client.createCalendar(
  'Work Calendar',
  description: 'Work-related events',
  color: '#3366CC',
  timezone: 'Asia/Seoul',
);

await client.updateCalendar(
  calendar,
  displayName: 'Updated Name',
  color: '#FF5733',
);

await client.deleteCalendar(calendar);
```

### Read-Only Calendars

Write operations throw `ForbiddenException` on read-only calendars.

## Event Operations

### Query Events

```dart
final events = await client.getEvents(
  calendar,
  start: DateTime.utc(2024, 1, 1),
  end: DateTime.utc(2024, 12, 31),
);
```

### Parallel Fetch

```dart
final allEvents = await client.getAllEvents(
  start: DateTime.utc(2024, 1, 1),
  end: DateTime.utc(2024, 12, 31),
);

final eventsMap = await client.getEventsFromCalendars(
  [calendar1, calendar2],
  start: start,
  end: end,
);
```

### Find by UID

```dart
final event = await client.getEventByUid('unique-event-id');
```

### Create / Update / Delete

```dart
final event = CalendarEvent(
  uid: 'unique-event-id-${DateTime.now().millisecondsSinceEpoch}',
  calendarId: calendar.uid,
  start: DateTime.utc(2024, 6, 15, 14, 0),
  end: DateTime.utc(2024, 6, 15, 15, 0),
  summary: 'Team Meeting',
);

final created = await client.createEvent(calendar, event);

try {
  await client.updateEvent(created.copyWith(summary: 'Updated'));
} on ConflictException {
  print('Conflict — refresh and retry');
}

await client.deleteEvent(created);
```

### All-Day Events

Use **inclusive** dates. The library converts to/from RFC 5545 exclusive DTEND.

```dart
final singleDay = CalendarEvent(
  uid: 'single-day-event',
  calendarId: calendar.uid,
  start: DateTime.utc(2024, 6, 15),
  summary: 'Company Holiday',
  isAllDay: true,
);
```

## Todo Operations (VTODO)

```dart
final todos = await client.getTodos(calendar);

final created = await client.createTodo(
  calendar,
  CalendarTodo(
    uid: 'todo-${DateTime.now().millisecondsSinceEpoch}',
    calendarId: calendar.uid,
    summary: 'Buy groceries',
    due: DateTime.utc(2026, 6, 20),
    priority: 5,
  ),
);

await client.updateTodo(
  created.copyWith(status: TodoStatus.completed, percentComplete: 100),
);

await client.deleteTodo(created);
```

## Recurrence expansion

Expand `RRULE` / `RDATE` / `EXDATE` into occurrence start times within a date range:

```dart
final event = CalendarEvent(
  uid: 'standup',
  calendarId: calendar.uid,
  start: DateTime.utc(2026, 8, 3, 15),
  end: DateTime.utc(2026, 8, 3, 15, 30),
  summary: 'Standup',
  rrule: 'FREQ=WEEKLY;BYDAY=MO;COUNT=12',
  exdate: ['20260817T150000Z'], // skip one week
);

final dates = event.expandOccurrences(
  rangeStart: DateTime.utc(2026, 8, 1),
  rangeEnd: DateTime.utc(2026, 10, 1),
);
// List<DateTime> of occurrence starts in [rangeStart, rangeEnd)

// Or via the expander directly:
final dates2 = RecurrenceExpander.expand(
  dtstart: event.start,
  rrule: event.rrule,
  rdate: event.rdate,
  exdate: event.exdate,
  recurrenceId: event.recurrenceId,
  rangeStart: DateTime.utc(2026, 8, 1),
  rangeEnd: DateTime.utc(2026, 10, 1),
  isAllDay: event.isAllDay,
);
```

- **Range** is half-open: `rangeStart ≤ occurrence < rangeEnd` (UTC).
- **RECURRENCE-ID** components are treated as a single modified instance (not re-expanded).
- **Todos** use `dtstart`, falling back to `due`. **Journals** require `dtstart`.
- Open-ended rules are capped with `maxOccurrences` (default 10 000).

## Free / Busy

Query busy time for a calendar with `CALDAV:free-busy-query` (RFC 4791):

```dart
final freeBusy = await client.getFreeBusy(
  calendar,
  start: DateTime.utc(2026, 8, 1),
  end: DateTime.utc(2026, 8, 8),
);

for (final period in freeBusy.busyPeriods) {
  print('${period.type.icalValue}: ${period.start} → ${period.end}');
}

if (freeBusy.isBusyAt(DateTime.utc(2026, 8, 3, 15))) {
  print('Busy at 15:00 UTC');
}
```

Query every collection in the principal free-busy-set (falls back to all calendars):

```dart
final list = await client.getFreeBusySet(
  start: DateTime.utc(2026, 8, 1),
  end: DateTime.utc(2026, 8, 8),
);
```

Scheduling freebusy via Outbox (RFC 6638), when the server advertises `schedule-outbox-URL`:

```dart
final replies = await client.requestScheduleFreeBusy(
  start: DateTime.utc(2026, 8, 1),
  end: DateTime.utc(2026, 8, 8),
  attendees: ['colleague@example.com'],
);
```

## Journal Operations (VJOURNAL)

```dart
// Prefer calendars with supportsJournal == true
final journals = await client.getJournals(calendar);

final entry = await client.createJournal(
  calendar,
  CalendarJournal(
    uid: 'journal-${DateTime.now().millisecondsSinceEpoch}',
    calendarId: calendar.uid,
    summary: 'Daily notes',
    description: 'Met with the team. Shipped the beta.',
    dtstart: DateTime.utc(2026, 8, 2),
    isAllDay: true,
    categories: ['work'],
  ),
);

await client.updateJournal(
  entry.copyWith(status: JournalStatus.final_),
);

await client.deleteJournal(entry);
```

## Data Models

### Calendar

| Property | Type | Description |
|----------|------|-------------|
| `uid` | `String` | Unique identifier (DAV:geteuid or href fallback) |
| `href` | `Uri` | Calendar resource URL |
| `displayName` | `String` | Display name |
| `description` | `String?` | Calendar description |
| `color` | `String?` | Color (#RRGGBB or #RRGGBBAA) |
| `timezone` | `String?` | Default timezone (IANA format) |
| `ctag` | `String?` | Collection tag (weak change indicator) |
| `syncToken` | `String?` | RFC 6578 sync token when advertised |
| `supportedComponents` | `List<String>` | VEVENT, VTODO, … |
| `isReadOnly` | `bool` | ACL-based read-only flag |

### CalendarEvent

| Property | Type | Description |
|----------|------|-------------|
| `uid` | `String` | iCalendar UID |
| `calendarId` | `String` | Parent calendar UID |
| `href` | `Uri?` | Event resource URL |
| `etag` | `String?` | Entity tag |
| `start` / `end` | `DateTime` | UTC (inclusive end for all-day) |
| `summary` | `String` | Title |
| `description` / `location` | `String?` | Optional fields |
| `isAllDay` | `bool` | All-day flag |
| `rrule` / `recurrenceId` / `exdate` | recurrence | Raw RFC 5545 fields |
| `isReadOnly` | `bool` | Inherited from calendar |

### CalendarSyncResult / ContactSyncResult

| Property | Description |
|----------|-------------|
| `syncToken` | Token for the next incremental sync |
| `events` / `todos` / `journals` / `contacts` | Created or updated members |
| `deletedHrefs` | Members removed since the previous token |
| `rawChanges` | Low-level `SyncChange` list (etags, optional payloads) |
| `truncated` | True if more pages exist (`followTruncation: false` only) |

## Error Handling

```dart
try {
  final calendars = await client.getCalendars();
} on AuthenticationException catch (e) {
  print('Authentication failed: ${e.message}');
} on ForbiddenException catch (e) {
  print('Insufficient permissions: ${e.message}');
} on NotFoundException catch (e) {
  print('Resource not found: ${e.message}');
} on ConflictException catch (e) {
  print('Concurrent modification: ${e.message}');
} on InvalidSyncTokenException catch (e) {
  print('Sync token expired — full re-sync: ${e.message}');
} on DiscoveryException catch (e) {
  print('Server discovery failed: ${e.message}');
} on CalDavException catch (e) {
  print('DAV error: ${e.statusCode} - ${e.message}');
}
```

## Exception Types

| Exception | Status Code | Description |
|-----------|-------------|-------------|
| `CalDavException` | Various | Base exception |
| `AuthenticationException` | 401 | Authentication failed |
| `ForbiddenException` | 403 | Insufficient permissions |
| `NotFoundException` | 404 | Resource not found |
| `ConflictException` | 409, 412 | ETag / resource conflict |
| `InvalidSyncTokenException` | 403 | Sync token no longer valid (RFC 6578) |
| `DiscoveryException` | - | Endpoint discovery failed |
| `ParseException` | - | XML / iCalendar / vCard parse failed |

## Protocol Support

| RFC | Standard | Coverage |
|-----|----------|----------|
| 4791 | CalDAV | Core calendar, VTODO/VJOURNAL, free-busy-query |
| 6638 | CalDAV Scheduling | Outbox freebusy request (subset) |
| 6352 | CardDAV | Address books + contacts + filters |
| 4918 | WebDAV | PROPFIND, PROPPATCH, MKCOL, COPY, MOVE, REPORT, … |
| 6578 | Collection Sync | `sync-collection` for calendars and address books |
| 6764 | Service Discovery | CalDAV and CardDAV well-known |
| 5545 | iCalendar | VEVENT / VTODO / VJOURNAL + VALARM, attendees, DURATION, shared props |
| 6350 | vCard | Core + extended fields (3.0/4.0 subset) |

## License

MIT — see [LICENSE](LICENSE).
