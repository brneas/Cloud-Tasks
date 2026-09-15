# Task portability and deletion

Cloud Tasks 1.0 imports RFC 5545 `VTODO` data through the platform document
picker and exports through the Android share sheet. Selecting Files or
Nextcloud in that sheet provides a normal save destination. The app does not
upload files to an intermediary service. Imported tasks receive fresh UIDs so
importing a backup cannot replace an existing server object accidentally.
Parent UIDs are rewritten together,
which retains hierarchy within the imported file, and manual positions remain
scoped to each sibling group.

Export combines the selected list's current cached `VTODO` components into one
`VCALENDAR`. Unknown task properties, parameters and nested components remain in
their original component. Account credentials and local retry metadata are not
included.

Deleting through CalDAV sends the normal conditional `DELETE` request. A
Nextcloud server with Calendar trash enabled retains the deleted object for its
configured retention period. Nextcloud intentionally does not expose Calendar
trash contents to connected CalDAV applications, so Cloud Tasks cannot list,
restore, permanently delete or empty that server-side trash. Those operations
are available in the Nextcloud Calendar web app.

Markdown note previews never load image URLs. This prevents merely opening a
task from contacting a third-party image host. HTTP and HTTPS links open only
after the user taps them and are handed to the system browser.
