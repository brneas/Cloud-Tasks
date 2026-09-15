class TaskCalendar {
  const TaskCalendar({
    required this.id,
    required this.accountId,
    required this.href,
    required this.displayName,
    required this.isReadOnly,
    this.color,
    this.sortOrder,
    this.syncToken,
    this.ownerHref,
    this.isSharedWithMe = false,
    this.canBeShared = false,
  });

  final String id;
  final String accountId;
  final Uri href;
  final String displayName;
  final String? color;

  /// The synchronized CalDAV collection order, separate from task ordering.
  final int? sortOrder;
  final bool isReadOnly;
  final String? syncToken;
  final String? ownerHref;

  /// True when this collection is owned by a different principal.
  final bool isSharedWithMe;

  /// Whether Nextcloud advertises the collection as shareable by this user.
  final bool canBeShared;
}

class CalDavDiscoveryResult {
  const CalDavDiscoveryResult({
    required this.principalUrl,
    required this.calendarHomeUrl,
    required this.calendars,
  });

  final Uri principalUrl;
  final Uri calendarHomeUrl;
  final List<TaskCalendar> calendars;
}
