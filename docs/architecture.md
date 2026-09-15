# Architecture

## Layer boundaries

1. **Presentation** renders locally available data and never waits for CalDAV
   before accepting a user edit.
2. **Domain** owns tasks, sibling groups, recurrence semantics and ordering.
3. **Persistence** stores server snapshots, local projections, ETags, sync
   tokens and an ordered mutation queue.
4. **Sync** discovers capabilities, pulls deltas, performs three-way merges and
   sends conditional writes.
5. **Protocol** translates WebDAV XML and iCalendar without discarding unknown
   server data.
6. **Notifications** derives Android schedules from cached standard display
   alarms; it does not maintain a second reminder model.

The presentation layer must never maintain an independent persistent order.
Its order is a projection of each task's synchronized manual-order property.

## Persistence tables

### Accounts

Account ID, normalized server URL, login name and app password are stored as a
single record in platform secure storage. Credentials never enter SQLite.

### calendars

- account ID and stable calendar href
- display name, color and calendar order
- owner principal, sharing capability and current-user privileges
- latest CalDAV sync token

### account_preferences

- account ID
- device-local default writable task-list ID

### app_preferences

- system/light/dark theme selection
- optional automatic-sync interval
- sync-on-resume preference
- last selected task list or smart view
- manual-order display direction

### tasks

- calendar ID, object href and VTODO UID
- parent UID and `X-APPLE-SORT-ORDER`
- queryable task fields
- latest ETag
- raw current iCalendar document
- raw last-synchronized base document
- dirty/deleted flags

### pending_operations

- stable operation ID per task and mutation type
- task and calendar IDs
- create/update/delete operation
- first-edit timestamp and the set of changed iCalendar properties
- optional batch ID and phase used to make destination-first moves resumable

All five tables are active in version 1.0.0. Repeated offline updates to one
task coalesce into one pending operation while retaining the unchanged server
base used for conflict detection. An update to a not-yet-uploaded task remains
a create operation; deleting that task before upload cancels both operations.

## Version 1.0.0 synchronization

1. Login Flow v2 creates a revocable app password without collecting the user's
   normal password.
2. CalDAV discovery follows the current-user principal and calendar-home-set
   properties rather than constructing a user path.
3. Only collections advertising `VTODO` support are cached.
4. The first sync uses a `calendar-query` REPORT. Later syncs use the saved DAV
   sync token with `sync-collection`, applying only changed and deleted hrefs.
   An expired token falls back to a complete query without discarding dirty
   local records.
5. The UI loads the complete calendar and projects `RELATED-TO` relationships
   into a tree. Every sibling group is sorted independently by numeric manual
   order. Orphans and cycles are promoted rather than hidden.
6. Task-field, hierarchy and reorder edits are serialized into short local
   SQLite transactions. The UI reloads from that durable projection
   immediately, then a 500 ms quiet-period debounce uploads the coalesced queue
   with `If-Match` and the last server ETag. Only records captured by an active
   upload are temporarily read-only; unrelated edits continue to queue.
7. Interrupted writes remain in the queue. The next edit or refresh reconciles
   the queued document against the current server object before retrying.
8. New tasks use `If-None-Match: *`; existing task updates and deletes use the
   latest ETag. A missing task after an interrupted delete counts as success.
9. After cached data changes, future display alarms are reconciled with the
   Android pending-notification list. Completed, cancelled and expired alarms
   are removed; stable IDs prevent duplicate notifications.
10. Completing a recurring task closes the current object, removes its active
    rule and alarms, and creates the next occurrence as a new queued object.
    Date representation, hierarchy and manual position are retained.
11. Moving a task between lists records copy and delete operations as a durable
    two-phase batch. It copies the complete subtree into the destination before
    deleting any source object, even after a restart or partial network failure.
    The moved root gets a valid destination manual position; descendants retain
    their relationships and independent sibling positions.
12. Task-list metadata is written directly to CalDAV collections with
    `MKCALENDAR`, `PROPPATCH` and `DELETE`. List order uses Apple's interoperable
    `calendar-order` property, independently from VTODO order.
13. Discovery compares each collection's DAV owner with the current-user
    principal. Task writes follow content privileges; metadata, ordering and
    sharing controls additionally require ownership. In a collection shared
    with this account, PRIVATE and CONFIDENTIAL tasks are read-only and cannot
    cross a shared-list boundary, matching Nextcloud Tasks' access-class rule.
14. The server-advertised allowed-sharing-modes property gates sharing UI.
    Current shares are read from the ownCloud `invite` DAV property, and
    permission changes use the same share POST bodies as Nextcloud's maintained
    client library.
15. Bulk creation, duplication and import are expressed as one atomic local
    edit batch before their individual conditional CalDAV writes are flushed.
    Duplicate branches receive a complete UID mapping so every parent relation
    points to the new branch. Import uses the same mapping to avoid replacing an
    existing object accidentally.
16. Export reads raw cached VTODO documents and changes only the VCALENDAR
    envelope. Markdown rendering is presentation-only; descriptions remain
    ordinary escaped iCalendar text, and image builders never fetch remote
    resources.
17. Optional Android periodic work opens the same local store and runs the same
    sync pipeline under a connected-network constraint. It introduces no relay
    service and stores no second copy of the account password.
18. Completion is derived from either STATUS:COMPLETED or the presence of a
    COMPLETED timestamp. Editing or clearing that timestamp updates STATUS and
    PERCENT-COMPLETE together, and pinning uses Nextcloud's interoperable
    X-PINNED extension.
19. Device-local presentation preferences remember the last list or smart view
    and manual-order direction. Search text and tag filters remain temporary so
    reopening the app cannot silently hide tasks behind a stale filter.
20. Restoring all completed tasks is one atomic local edit batch. It clears
    completion state without changing UID, hierarchy, recurrence metadata or
    synchronized manual positions, then uses the normal background writeback.

## Merge rule

When the ETag changed remotely while a local task is dirty, compare the local
document and remote document against the saved base document. Properties changed
only locally are copied onto the latest remote document, which preserves remote
and unknown data. If both sides changed the same property differently, version
1.0.0 keeps the server object, clears that queued operation, and tells the user
to apply the local change again instead of silently overwriting either side.
Nested `VALARM` components and multi-valued relationship/category properties
participate in the same three-way comparison instead of being treated as
unstructured text.
