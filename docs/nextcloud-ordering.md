# Nextcloud-compatible manual ordering

## Source of truth

The visible task order is stored in each task's iCalendar object:

```text
X-APPLE-SORT-ORDER:2097152
```

It must not exist only in local application preferences. Reordering a task is
a VTODO edit and therefore participates in normal ETag conflict handling.

Task list order is separate and is stored as the CalDAV collection property
`{http://apple.com/ns/ical/}calendar-order`.

## Sibling groups

Task order is meaningful within a tuple of:

```text
(account, calendar href, parent UID)
```

Root tasks use a null parent UID. A subtask move between parents changes both
its `RELATED-TO;RELTYPE=PARENT` relationship and its manual order in the new
sibling group.

The UI renders a reorderable list for each sibling group. A drag within one
group cannot accidentally reuse the flattened screen index of another group.
Changing a parent explicitly assigns a sparse position in the destination
group and writes the parent relationship and order in one conditional update.

## Sparse positions

Cloud Tasks initially spaces positions by 1,048,576. A move between positions
1,048,576 and 2,097,152 can normally use their midpoint, so only the moved
VTODO needs to be written. If no integer gap remains, the sibling group is
reindexed in its existing visible order.

A newly created task is assigned a sparse value that places it at the top of
the active display direction. If existing tasks have missing or duplicate
positions, that first insertion normalizes the sibling group while preserving
the exact visible order.

## Direction

The numeric order and the user's ascending/descending presentation preference
are distinct. The client exposes both directions. Nextcloud does not publish
that display preference through CalDAV, so each client selects its direction
locally while the VTODO numbers remain the cross-client source of truth.

## Compatibility invariants

- Never replace a missing manual order with a local-only index.
- Never reorder one parent group while moving a sibling in another group.
- Preserve unknown iCalendar properties and parameters on every write.
- Upload reorder edits with the task's current ETag.
- Treat HTTP 412 as a real conflict and pull the remote object before retrying.
- Do not infer hierarchy from indentation; use `RELATED-TO`.
