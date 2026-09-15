# Nextcloud task-list sharing

Task lists are CalDAV calendar collections that advertise `VTODO` support.
Cloud Tasks discovers three separate facts for each collection:

- DAV `owner`, compared with the current-user principal;
- DAV `current-user-privilege-set`, used for task content edits;
- CalendarServer `allowed-sharing-modes`, used to expose owner sharing actions.

A list shared with the current account may still be writable. That permits task
changes, but does not make the current account the list owner. The UI therefore
does not offer rename, recolor, global list-order changes or re-sharing on a
shared list. Deleting a shared collection means leaving that share; the owner’s
collection and tasks remain intact.

## Share records

Cloud Tasks reads the current member list with a depth-zero `PROPFIND` for:

```xml
<oc:invite xmlns:oc="http://owncloud.org/ns" />
```

Each `oc:user` entry contains its DAV principal href, optional common name and
an `oc:access` element. An `oc:read-write` child grants edit access; its absence
means read-only access.

## Share changes

Adding a read-only user posts the following shape to the owned collection:

```xml
<oc:share xmlns:oc="http://owncloud.org/ns" xmlns:d="DAV:">
  <oc:set>
    <d:href>principal:principals/users/alice</d:href>
  </oc:set>
</oc:share>
```

For writable access, `oc:read-write` is added inside `oc:set`. Groups use the
`principal:principals/groups/` prefix. Permission changes repeat `oc:set` for
the existing principal. Removal posts `oc:remove` with the exact href returned
by Nextcloud.

Recipient IDs are XML escaped and may not contain a slash, preventing entered
text from changing the selected users/groups principal path. Authentication is
handled by the same app password and same-origin restriction as every other
CalDAV request. Sharing responses are never logged or stored in SQLite.
