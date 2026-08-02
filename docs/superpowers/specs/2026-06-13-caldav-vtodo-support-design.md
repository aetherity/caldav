# CalDAV VTODO Support — Design Spec

**Date:** 2026-06-13  
**Status:** Approved (implementation plan pending at time of writing; VTODO later shipped in 1.5.0)  
**Scope:** Add VTODO (to-do) component support to the `caldav` library (`dart_caldav_client`)  
**Related issue:** [ssyuk/caldav#1](https://github.com/ssyuk/caldav/issues/1) — "Events (Tasks) from VTODO Calendars not supported (yet)?"

---

## 1. Background / Problem

The library currently handles only `VEVENT`. Calendars that contain only `VTODO` items (task lists) return empty results because all four of the following layers are hard-coded for VEVENT:

| Location | Problem |
|---|---|
| `lib/src/event/icalendar_parser.dart:22, 111-114` | `_extractComponent(lines, 'VEVENT')` and `parseEvents` only scan `BEGIN:VEVENT` |
| `lib/src/event/event_service.dart:315, 341` | `calendar-query` / `multiget` filters hard-code `<C:comp-filter name="VEVENT">` → the server returns an empty response for VTODO-only calendars |
| `lib/src/event/event.dart` | `CalendarEvent.start` is `required`; VTODO core properties (`DUE` / `COMPLETED` / `STATUS` / `PERCENT-COMPLETE` / `PRIORITY`) are missing |
| `lib/src/event/icalendar_parser.dart:40` | Returns `null` when `dtstart == null` → discards common VTODOs that have no `DTSTART` |

The `Calendar` model already has a `supportsTodos` getter (`lib/src/calendar/calendar.dart:46`), so the app can tell that a calendar “has tasks,” but there is no way to fetch those items.

## 2. Goals / Non-goals

**Goals**
- First-class support to parse, list, create, update, and delete VTODO
- Allow VTODOs with neither `DTSTART` nor `DUE`
- Read and write completion state (`STATUS` / `COMPLETED` / `PERCENT-COMPLETE`)
- Keep the existing `CalendarEvent` public API **non-breaking** (minor version bump)
- Structure that maps cleanly onto consumer app (dew) `Event(isTodo)` semantics

**Non-goals (out of scope for this change)**
- Integration on the dew app side (separate spec → plan cycle — see §10)
- VJOURNAL support
- Full RFC 5545 VTODO property surface (`CREATED` / `LAST-MODIFIED` / `SEQUENCE` / `CATEGORIES` / `GEO` / `URL` / `DURATION`, etc.) — limit to a practical standard set
- Mixed queries that return VEVENT + VTODO together — keep `getEvents` / `getTodos` type-separated

## 3. Decisions (locked)

Confirmed via brainstorming:
1. **Separate `CalendarTodo` model** (not a unified model; avoids a breaking change)
2. Introduce a shared **`CalendarComponent` base** (extract shared fields, polymorphism)
3. **Practical standard field set** — provide both a `status` enum and an `isCompleted` convenience getter
4. **`abstract class` base** (not sealed) — free file layout; type-separated list APIs mean exhaustive switches are unnecessary
5. Fully **non-breaking** → minor version bump

## 4. Architecture

### 4.1 Model layer

```dart
// lib/src/event/calendar_component.dart  (new)
/// Base for iCalendar components shared by VEVENT / VTODO
abstract class CalendarComponent {
  final String uid;
  final String calendarId;
  final Uri? href;
  final String? etag;
  final String summary;
  final String? description;
  final String? location;
  final bool isReadOnly;
  final String? rawIcalendar;
  // Recurrence (shared by VEVENT · VTODO)
  final String? rrule;
  final String? recurrenceId;
  final List<String>? exdate;

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
  });

  /// Subclass generates a full VCALENDAR string including
  /// a BEGIN:VEVENT / BEGIN:VTODO block
  String toIcalendar();
}
```

```dart
// lib/src/event/event.dart  (refactor — public API 100% preserved)
class CalendarEvent extends CalendarComponent {
  final DateTime start;   // remains required
  final DateTime? end;
  final bool isAllDay;

  const CalendarEvent({
    required super.uid,
    required super.calendarId,
    super.href,
    super.etag,
    required this.start,
    this.end,
    required super.summary,
    super.description,
    super.location,
    this.isAllDay = false,
    super.rawIcalendar,
    super.isReadOnly,
    super.rrule,
    super.recurrenceId,
    super.exdate,
  });
  // Keep existing members: duration, copyWith, toIcalendar, ==, hashCode, etc.
}
```

> **Non-breaking check:** Call sites such as `CalendarEvent(uid: ..., calendarId: ..., start: ..., summary: ...)` still compile. All field names, defaults, and constructor signatures stay the same. Extracting the base only moves where those declarations live.

```dart
// lib/src/event/todo.dart  (new)
enum TodoStatus { needsAction, inProcess, completed, cancelled }

class CalendarTodo extends CalendarComponent {
  final DateTime? dtstart;      // DTSTART (display start) — nullable
  final DateTime? due;          // DUE (deadline)          — nullable
  final bool isAllDay;
  final TodoStatus status;      // default needsAction
  final DateTime? completed;    // COMPLETED timestamp
  final int? percentComplete;   // 0–100
  final int? priority;          // RFC 5545 0–9 (0 = undefined)

  const CalendarTodo({
    required super.uid,
    required super.calendarId,
    super.href,
    super.etag,
    required super.summary,
    super.description,
    super.location,
    this.dtstart,
    this.due,
    this.isAllDay = false,
    this.status = TodoStatus.needsAction,
    this.completed,
    this.percentComplete,
    this.priority,
    super.rawIcalendar,
    super.isReadOnly,
    super.rrule,
    super.recurrenceId,
    super.exdate,
  });

  /// Convenience getter for simple consumers (e.g. dew)
  bool get isCompleted =>
      status == TodoStatus.completed ||
      completed != null ||
      percentComplete == 100;

  CalendarTodo copyWith({ /* all fields */ });

  @override
  String toIcalendar();

  @override
  bool operator ==(Object other) => other is CalendarTodo && other.uid == uid;
  @override
  int get hashCode => uid.hashCode;
}
```

### 4.2 Parsing (`ICalendarParser` extensions)

Reuse existing shared helpers (`_unfoldLines` / `_parseProperties` / `_parseDateTime` / `_unescapeIcalText` / `_parseExdate` / `_extractComponent`) and add methods symmetric with VEVENT:

```dart
static CalendarTodo? parseTodo(
  String icalendar, {
  required String calendarId,
  Uri? href,
  String? etag,
  bool isReadOnly = false,
});

static List<CalendarTodo> parseTodos(
  String icalendar, {
  required String calendarId,
  bool isReadOnly = false,
});
```

VTODO parsing rules (differences from VEVENT):
- Only `uid` is required (return `null` if missing). Default `summary` to `'Untitled'`
- **Valid even with neither `DTSTART` nor `DUE`** — do not apply VEVENT’s “no DTSTART → null” rule
- Parse `dtstart` / `due` as nullable (`_parseDateTime`, recognize `DTSTART;VALUE` / `DUE;VALUE`)
- `isAllDay`: true if the present time field (prefer `DTSTART`, else `DUE`) is `VALUE=DATE` or length 8
- `status`: map `STATUS` to `TodoStatus` (`NEEDS-ACTION`→needsAction, `IN-PROCESS`→inProcess, `COMPLETED`→completed, `CANCELLED`→cancelled). Missing/unknown → `needsAction`
- `completed`: `COMPLETED` timestamp (`_parseDateTime`)
- `percentComplete`: `PERCENT-COMPLETE` → `int.tryParse`
- `priority`: `PRIORITY` → `int.tryParse`
- `rrule` / `recurrenceId` / `exdate`: same helpers as VEVENT
- **Do not apply exclusive-end adjustment to all-day `DUE`** — VEVENT `DTEND` is “instant after end” so it is shifted to inclusive, but `DUE` *is* the deadline moment (aligns with dew’s `endTime` = deadline)

### 4.3 Service & client API

Add **`lib/src/event/todo_service.dart`**, symmetric with `event_service.dart`. Separate service keeps VTODO filters, parsing, and models clear. Naver-style multiget fallback, `_mapException`, and ETag optimistic locking follow the same pattern as `EventService`.

```dart
class TodoService {
  Future<List<CalendarTodo>> list(Calendar calendar, {DateTime? start, DateTime? end});
  Future<CalendarTodo> create(Calendar calendar, CalendarTodo todo);
  Future<CalendarTodo> update(CalendarTodo todo);
  Future<void> delete(CalendarTodo todo);
  Future<CalendarTodo?> findByUid(Calendar calendar, String uid);
}
```

- `calendar-query` / `calendar-multiget` use `<C:comp-filter name="VTODO">`
- **`time-range` is optional**: apply `<C:time-range>` only when both `start` and `end` are given; otherwise list all. Todos without start/due are common and would be missed by time-range, so **full list is the recommended default**
- `create`: PUT to `${todo.uid}.ics` with `If-None-Match: *`
- `update` / `delete`: `If-Match: etag` optimistic locking; 412 → `ConflictException`; 404 on delete → treat as success

Add matching public methods on `CalDavClient`:
```dart
Future<List<CalendarTodo>> getTodos(Calendar calendar, {DateTime? start, DateTime? end});
Future<CalendarTodo> createTodo(Calendar calendar, CalendarTodo todo);   // _ensureWritable guard
Future<CalendarTodo> updateTodo(CalendarTodo todo);                       // isReadOnly → ForbiddenException
Future<void> deleteTodo(CalendarTodo todo);                               // isReadOnly → ForbiddenException
Future<CalendarTodo?> getTodoByUid(String uid);
```
Lazy-init `_todoService` in `_ensureDiscovered()`. Defer `getTodosFromCalendars` / `getAllTodos` (YAGNI).

### 4.4 iCal serialization

`CalendarTodo.toIcalendar()` emits a `BEGIN:VTODO` block. Align with dew’s `ical_export.dart` (`DUE` = deadline, `DTSTART` = start), and also emit completion fields that dew currently omits.

Output order:
- `BEGIN:VCALENDAR` / `VERSION:2.0` / `PRODID:-//dart-caldav-client//EN`
- `BEGIN:VTODO`
- `UID`, `DTSTAMP` (current UTC)
- `DTSTART` (only if present; all-day uses `;VALUE=DATE`)
- `DUE` (only if present; all-day uses `;VALUE=DATE`, no exclusive-end shift)
- `SUMMARY` / `DESCRIPTION` / `LOCATION` (escape via `ICalendarUtils.escapeText`)
- `STATUS` (only when not `needsAction`; enum → uppercase token)
- `COMPLETED` (if present), `PERCENT-COMPLETE` (if present), `PRIORITY` (if non-zero / non-null)
- `RRULE` / `RECURRENCE-ID` / `EXDATE`
- `END:VTODO` / `END:VCALENDAR`

## 5. VTODO ↔ dew Event mapping (reference — next cycle)

| dew `Event` | `CalendarTodo` | iCal VTODO |
|---|---|---|
| `isTodo` | (type is CalendarTodo) | component = VTODO |
| `endTime` (deadline, anchor) | `due` | `DUE` |
| `startTime` (display start) | `dtstart` | `DTSTART` |
| `isCompleted` | `isCompleted` getter | `STATUS:COMPLETED` / `COMPLETED` / `PERCENT-COMPLETE:100` |
| `priority` (low/med/high) | `priority` (0–9) | `PRIORITY` |
| `isAllDay` | `isAllDay` | `;VALUE=DATE` |

> dew’s `Event` invariant requires `endTime` (=DUE) on todos, but RFC makes `DUE` optional. Handling VTODOs without `DUE` is a dew-side concern (§10).

## 6. Error handling

Reuse the same mapping as `EventService`:
- 401 → `AuthenticationException`
- 403 → `ForbiddenException`
- 404 → `NotFoundException` (idempotent success on delete)
- 412 → `ConflictException` (ETag conflict)
- other → `CalDavException(statusCode)`
- write on read-only calendar/item → `ForbiddenException` (`_ensureWritable` / `isReadOnly` guards)

## 7. Test strategy

Follow the pure unit-test style in `test/dart_caldav_client_test.dart` (parser / serialization / model / XML string checks; no network).

- **`parseTodo`**: full object / DTSTART only / DUE only / neither / three completion paths (`STATUS:COMPLETED`, `COMPLETED` present, `PERCENT-COMPLETE:100`) / `PRIORITY` / all-day (`VALUE=DATE`) / missing UID → null / line folding / escaping
- **`parseTodos`**: multiple VTODO components
- **`CalendarTodo.toIcalendar` round-trip**: `parseTodo(todo.toIcalendar())` preserves key fields (uid/summary/due/dtstart/status/priority/isAllDay)
- **`isCompleted` getter**: status / completed / percentComplete paths
- **Regression**: all existing `CalendarEvent` tests still pass after base extraction (non-breaking check)
- **`TodoService` XML build**: string-match `comp-filter name="VTODO"` and time-range presence/absence in query/multiget bodies

## 8. Version, exports, docs

- Add exports in `lib/caldav.dart`:
  ```dart
  export 'src/event/calendar_component.dart' show CalendarComponent;
  export 'src/event/todo.dart' show CalendarTodo, TodoStatus;
  ```
- `pubspec.yaml` version: `1.4.2+3` → **`1.5.0`** (feature, non-breaking → minor)
- `CHANGELOG.md`: VTODO support entry
- `README.md`: VTODO list/CRUD examples
- `example/main.dart`: todo list example
- Comment on issue #1 after release

## 9. Backward compatibility

- `CalendarComponent` is new; `CalendarEvent` public constructors, fields, and methods are unchanged
- Existing `getEvents` / `createEvent` / … signatures unchanged
- Only new symbols are exported → no impact on existing imports
- SemVer minor (`1.5.0`) is appropriate

## 10. Follow-up — dew integration (separate spec → plan cycle)

After publishing caldav `1.5.0`, continue in dew. Separate caldav-dependent work from independent dew work.

**Depends on caldav 1.5.0**
- In `caldav_calendar_source.dart`, map VTODO → `Event(isTodo: true, isCompleted: …)` (e.g. `DavTodoExtension`)
- Stop force-unwrapping `start: event.startTime!` in `doCreateEvent` / `doUpdateEvent` → branch to `createTodo` / `updateTodo` for todos
- Merge `getTodos` results in `fetchEvents`

**Independent of caldav (can start earlier in dew)**
- Emit completion fields in `ical_export.dart` (`STATUS` / `COMPLETED` / `PERCENT-COMPLETE`) — current round-trip drops completion
- Parse VTODO in `ical_import.dart` (regex currently matches VEVENT only)
- Policy for VTODO without `DUE` (relax `Event.endTime` required invariant or invent a virtual deadline)
