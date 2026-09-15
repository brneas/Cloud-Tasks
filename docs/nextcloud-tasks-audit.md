# Nextcloud Tasks 0.18.1 functional audit

This audit compares Cloud Tasks 1.0.0+19 with the portable behavior in
Nextcloud Tasks 0.18.1 and the current 0.18.1 source tree reviewed on
2026-09-15.

| Nextcloud capability | Cloud Tasks result |
| --- | --- |
| Title and Markdown description | Supported; remote Markdown images stay blocked for privacy |
| Start, due and all-day dates | Supported with DATE, floating, UTC and TZID preservation |
| Priority, progress and status | Supported, including an absent STATUS value |
| Completion date | Supported and editable; future values are rejected |
| Important, Current, Today, Week and Completed collections | Supported with Nextcloud-compatible predicates |
| Categories/tags, location and URL | Supported |
| Public/private/confidential classification | Supported with shared-list access restrictions |
| Pinning | Supported through `X-PINNED` |
| Subtasks | Supported through `RELATED-TO;RELTYPE=PARENT` |
| Manual order | Supported through exact `X-APPLE-SORT-ORDER` values per sibling group |
| Reminders | Supported as multiple relative or absolute display `VALARM` components |
| Repeating tasks | Supported for daily, weekly, monthly and yearly rules; unfamiliar rule parts are preserved until explicitly replaced |
| Duplication and multi-task entry | Supported |
| Task-list creation, metadata, order and sharing | Supported when DAV privileges advertise the operation |
| Import/export | Supported for complete task-list `.ics` archives |
| Offline changes and conflicts | Supported through a durable queue, ETags and three-way field merging |

## Intentional standalone-client differences

- Relevance, alphabetical, date and tag sorting are local web presentation
  preferences. Cloud Tasks defaults to synchronized manual order and offers
  both numeric directions so ordering remains consistent across clients.
- The Nextcloud web app can autocomplete share recipients using a private
  server endpoint. Cloud Tasks accepts an exact username or group ID instead.
- Dashboard, Talk, unified-search, Deck and Calendar links are integrations
  between Nextcloud web apps, not CalDAV task properties.
- Recently deleted item restoration and permanent deletion remain in the
  Nextcloud Calendar web trash because those objects are not exposed through
  the task-list CalDAV interface.

## Primary references

- [Nextcloud Tasks 0.18.1 release](https://github.com/nextcloud/tasks/releases/tag/v0.18.1)
- [Nextcloud Tasks changelog](https://github.com/nextcloud/tasks/blob/main/CHANGELOG.md)
- [Task field and transition model](https://github.com/nextcloud/tasks/blob/main/src/models/task.js)
- [Smart-collection and sorting predicates](https://github.com/nextcloud/tasks/blob/main/src/store/storeHelper.js)
- [Shared-list task policy](https://github.com/nextcloud/tasks/blob/main/src/store/tasks.js)
