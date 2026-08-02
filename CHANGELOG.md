## 2.2.0

### Free / busy (RFC 4791 + RFC 6638)
- `CALDAV:free-busy-query` REPORT via `CalDavClient.getFreeBusy` / `getFreeBusyAt` / `getFreeBusySet`.
- VFREEBUSY parsing and serialization (`FreeBusy`, `FreeBusyPeriod`, `FreeBusyType`, `FreeBusyParser`).
- Discovery of `calendar-free-busy-set`, `schedule-outbox-URL`, `schedule-inbox-URL`, and `calendar-user-address-set`.
- Optional scheduling freebusy request: `requestScheduleFreeBusy` (POST to Outbox).
- `WebDavClient.post` for scheduling Outbox submissions.

## 2.1.0

### VJOURNAL (journal entries)
- New `CalendarJournal` model and `JournalStatus` enum (`draft`, `final_`, `cancelled`).
- `ICalendarParser.parseJournal` / `parseJournals` for VJOURNAL parsing.
- `CalDavClient.getJournals`, `createJournal`, `updateJournal`, `deleteJournal`, `getJournalByUid`.
- RFC 6578 calendar sync includes journals in `CalendarSyncResult.journals`.

## 2.0.0

Major release: full WebDAV foundation, CardDAV, dual discovery, and RFC 6578 collection sync.

### Breaking changes
- `WebDavClient` / `DioWebDavClient` now use `DavDepth` instead of `int` for Depth headers (`0` / `1` / `infinity`).
- `PUT` default `contentType` is `application/octet-stream` (CalDAV/CardDAV services pass calendar/vcard types explicitly).
- `CalDavClient.withDio` / `CardDavClient.withDio` default to `ownsDio: false` (calling `close()` does not close a shared Dio).

### WebDAV (RFC 4918)
- New methods: `MKCOL`, `COPY`, `MOVE`, `HEAD`; lock-token header hooks on writes.
- `ProppatchBuilder` with set **and** remove; richer `PropfindBuilder` presets.
- Multistatus: response-level status, errors, location, truncation markers, `isAddressBook`.
- `ResourceService` + `DavResource` for generic collection/resource operations.
- `DavCapabilities` from OPTIONS (`Allow` / `DAV` headers).

### CardDAV (RFC 6352)
- New `CardDavClient` with address book and contact CRUD.
- Discovery via `/.well-known/carddav` and `addressbook-home-set`.
- `addressbook-query` / `addressbook-multiget`, structured `ContactFilter` search.
- Richer vCard model (NICKNAME, PHOTO, IMPP, RELATED, GENDER, KIND/MEMBER, extras, …).
- Focused import: `package:caldav/carddav.dart`.

### Dual discovery
- `DavSession` shares one Dio/auth for CalDAV + CardDAV with parallel discovery.
- `DualDiscoveryResult` for partial success; `seedDiscovery` on nested clients.

### Collection sync (RFC 6578)
- `CalDavClient.syncCalendar` / `getCalendarSyncToken`.
- `CardDavClient.syncAddressBook` / `getAddressBookSyncToken`.
- `CalendarSyncResult` / `ContactSyncResult` with changed members, deletions, and next token.
- Automatic truncation paging (`followTruncation`).
- `InvalidSyncTokenException` when a stored token is rejected by the server.
- `Calendar.syncToken` / `AddressBook.syncToken` when advertised via PROPFIND.

### Sync token cache
- `SyncTokenStore` interface with `MemorySyncTokenStore` and `JsonSyncTokenStore`.
- `SyncTokenCache` wraps client sync, persists tokens, and auto re-syncs on invalid tokens.

### Other
- VTODO support retained from 1.5.0 (`CalendarTodo`, todo CRUD).

## 1.5.0
- VTODO (task) support. Calendars containing `VTODO` items can now be read and managed (issue #1).
  - New `CalendarTodo` model and `TodoStatus` enum, sharing a new `CalendarComponent` base with `CalendarEvent`.
  - `ICalendarParser.parseTodo` / `parseTodos` for VTODO parsing (DTSTART/DUE optional; STATUS/COMPLETED/PERCENT-COMPLETE/PRIORITY supported).
  - `CalDavClient.getTodos`, `createTodo`, `updateTodo`, `deleteTodo`, `getTodoByUid`.

## 1.4.2+3
- Removed debug print statements

## 1.4.2+2
- Removed unnecessary files

## 1.4.2
- Added `ForbiddenException` for HTTP 403 (insufficient permissions)
- Added read-only calendar/event guard on write operations (`createEvent`, `updateEvent`, `deleteEvent`, `updateCalendar`, `deleteCalendar`)
- Fixed `validateStatus` to properly reject HTTP 4xx responses (previously treated as success)
- Added consistent HTTP status code error mapping (401, 403, 404) across all services

## 1.4.1
- Fixed all-day event DTEND exclusive date handling per RFC 5545
  - Parsing (server → app): Converts exclusive DTEND to inclusive end date
  - Serialization (app → server): Converts inclusive end date to exclusive DTEND
  - Single-day events (DTEND = DTSTART + 1) now correctly set `end` to `null`
  - Multi-day events subtract 1 day from DTEND for inclusive representation
  - App consumers always work with inclusive end dates

## 1.4.0
- Added HTTPS enforcement by default with `allowInsecure` parameter for development
- Added `getEventsFromCalendars()` for parallel event fetching across multiple calendars
- Added `getAllEvents()` convenience method for fetching all events in parallel
- Optimized `getEventByUid()` to search all calendars in parallel
- Added `WebDavClient` abstract interface for better testability
- Created `ICalendarUtils` utility class to consolidate shared formatting functions
- Refactored `EventService` with helper methods to reduce code duplication
- Added comprehensive unit tests (27 test cases)

## 1.3.0
- Added recurrence support to `CalendarEvent`:
  - `rrule`: RFC 5545 RRULE for recurring events (e.g., "FREQ=DAILY;INTERVAL=1;COUNT=10")
  - `recurrenceId`: RECURRENCE-ID for modified instances of recurring events
  - `exdate`: Exception dates excluded from the recurrence set
- Updated `ICalendarParser` to extract RRULE, RECURRENCE-ID, and EXDATE from iCalendar data
- Updated `CalendarEvent.toIcalendar()` to serialize recurrence fields

## 1.2.2+3
- Added missing changelog

## 1.2.2+2
- Updated README.md dependency reference

## 1.2.2
- Added `isReadOnly` field to `Calendar` and `CalendarEvent` models
- Implemented privilege parsing for read-only calendar detection

## 1.2.1
- Made `uid` field required in `Calendar` class
- Made `calendarId` field required in `CalendarEvent` class
- Removed unused `getEvent` method

## 1.2.0
- Refactored date handling to use `DateTime` instead of `TZDateTime`
- Renamed `CaldavClient` to `CalDavClient` for consistency
- Renamed `CaldavException` to `CalDavException` for consistency
- Removed `timezone` dependency

## 1.1.0
- Added unique identifier (`uid`) field to `Calendar` model

## 1.0.0+2
- Added MIT License
- Simplified caldav dependency specification in README.md

## 1.0.0
- Initial release