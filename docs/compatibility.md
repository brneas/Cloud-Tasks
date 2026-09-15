# Nextcloud compatibility matrix

Cloud Tasks does not hard-code a Nextcloud version or DAV path. Version 1.0 is
designed for supported Nextcloud releases that expose a CalDAV calendar home
and task calendars containing `VTODO` objects. The task behavior in build 19
was re-audited against Nextcloud Tasks 0.18.1 (released 2026-06-29) and its
current 0.18.1 source tree.

| Area | 1.0 automated coverage | Compatibility behavior |
| --- | --- | --- |
| Discovery | principal, calendar home, VTODO support, privileges | Follows advertised DAV hrefs and ignores non-task calendars |
| Initial read | `calendar-query`, ETag, calendar data | Skips one malformed object without hiding valid objects |
| Incremental read | `sync-collection`, changes, deletions, next token | Falls back to a full query for an expired/invalid token |
| Writes | conditional create/update/delete | Uses `If-None-Match`/`If-Match`; retains interrupted writes locally |
| Conflicts | same-field and unrelated-field changes | Refuses same-field overwrite; rebases unrelated changes |
| Ordering | root/subtask sibling groups, both directions | Persists exact integer `X-APPLE-SORT-ORDER` values |
| Hierarchy | parent changes, subtree moves, orphans/cycles | Uses `RELATED-TO;RELTYPE=PARENT`; promotes malformed structures visibly |
| Preservation | unknown properties, parameters, nested components | Round-trips data not edited by Cloud Tasks |
| Lists/sharing | collection metadata, owner and invitation records | Shows controls only when server privileges advertise support |
| Task state | status, progress, completion timestamp, priority, pin | Uses the same iCalendar fields and valid-state transitions as Nextcloud Tasks |
| Smart views | Important, Current, Today, Week, Completed | Applies Nextcloud's portable priority and start/due-date predicates locally |
| Shared privacy | PUBLIC/default, PRIVATE, CONFIDENTIAL | Non-public tasks received through a share are read-only and cannot cross a shared-list boundary |

## Audit boundary

The parity target is task and list behavior that a standalone CalDAV client can
carry between devices. Manual order remains the default because it is the only
Nextcloud sort mode whose position is synchronized in each task. Other web sort
choices are presentation preferences and do not alter `VTODO` data.

Nextcloud-web integrations such as Dashboard, Talk, unified search, Deck and
Calendar links intentionally remain in the server UI. Calendar trash restore
and permanent deletion also remain there because the CalDAV task collections
do not expose the trash contents. Sharing is functional with an exact username
or group ID; the web app's sharee autocomplete uses a Nextcloud-specific HTTP
search endpoint rather than CalDAV.

Before tagging a release, run the manual account checks in the
[release checklist](release-checklist.md) against the oldest and newest
supported server available to the maintainer. Server-specific behavior should
be captured as a redacted test fixture before adding a workaround.
