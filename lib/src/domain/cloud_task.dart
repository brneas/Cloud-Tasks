enum CloudTaskStatus {
  needsAction('NEEDS-ACTION'),
  inProcess('IN-PROCESS'),
  completed('COMPLETED'),
  cancelled('CANCELLED');

  const CloudTaskStatus(this.icalendarValue);

  final String icalendarValue;

  static CloudTaskStatus? fromICalendar(String? value) {
    if (value == null) {
      return null;
    }

    final normalized = value.toUpperCase();
    for (final status in values) {
      if (status.icalendarValue == normalized) {
        return status;
      }
    }
    return null;
  }
}

enum CloudTaskPrivacy {
  public('PUBLIC'),
  private('PRIVATE'),
  confidential('CONFIDENTIAL');

  const CloudTaskPrivacy(this.icalendarValue);

  final String icalendarValue;

  static CloudTaskPrivacy? fromICalendar(String? value) {
    final normalized = value?.trim().toUpperCase();
    for (final privacy in values) {
      if (privacy.icalendarValue == normalized) {
        return privacy;
      }
    }
    return null;
  }
}

class CloudTask {
  const CloudTask({
    required this.uid,
    required this.summary,
    this.calendarId,
    this.parentUid,
    this.sortOrder,
    this.status,
    this.description,
    this.start,
    this.due,
    this.priority,
    this.percentComplete,
    this.categories = const <String>[],
    this.location,
    this.url,
    this.recurrenceRule,
    this.reminders = const <CloudTaskReminder>[],
    this.privacy,
    this.pinned = false,
    this.createdAt,
    this.lastModifiedAt,
    this.completedAt,
  });

  final String uid;
  final String summary;
  final String? calendarId;
  final String? parentUid;
  final int? sortOrder;
  final CloudTaskStatus? status;
  final String? description;
  final CloudTaskDate? start;
  final CloudTaskDate? due;
  final int? priority;
  final int? percentComplete;
  final List<String> categories;
  final String? location;
  final Uri? url;
  final String? recurrenceRule;
  final List<CloudTaskReminder> reminders;
  final CloudTaskPrivacy? privacy;
  final bool pinned;
  final DateTime? createdAt;
  final DateTime? lastModifiedAt;
  final DateTime? completedAt;

  /// Nextcloud treats a task as completed when either STATUS is COMPLETED or
  /// a COMPLETED timestamp is present.
  bool get isCompleted =>
      status == CloudTaskStatus.completed || completedAt != null;

  bool get isClosed => isCompleted || status == CloudTaskStatus.cancelled;

  /// Compatibility convenience for callers that only display one alarm.
  CloudTaskReminder? get reminder => reminders.isEmpty ? null : reminders.first;

  CloudTask copyWith({
    String? uid,
    String? summary,
    String? calendarId,
    String? parentUid,
    int? sortOrder,
    CloudTaskStatus? status,
    String? description,
    CloudTaskDate? start,
    CloudTaskDate? due,
    int? priority,
    int? percentComplete,
    List<String>? categories,
    String? location,
    Uri? url,
    String? recurrenceRule,
    List<CloudTaskReminder>? reminders,
    CloudTaskPrivacy? privacy,
    bool? pinned,
    DateTime? createdAt,
    DateTime? lastModifiedAt,
    DateTime? completedAt,
    bool clearParentUid = false,
    bool clearLocation = false,
    bool clearUrl = false,
    bool clearRecurrenceRule = false,
    bool clearReminder = false,
    bool clearPrivacy = false,
    bool clearStatus = false,
    bool clearCompletedAt = false,
  }) {
    return CloudTask(
      uid: uid ?? this.uid,
      summary: summary ?? this.summary,
      calendarId: calendarId ?? this.calendarId,
      parentUid: clearParentUid ? null : parentUid ?? this.parentUid,
      sortOrder: sortOrder ?? this.sortOrder,
      status: clearStatus ? null : status ?? this.status,
      description: description ?? this.description,
      start: start ?? this.start,
      due: due ?? this.due,
      priority: priority ?? this.priority,
      percentComplete: percentComplete ?? this.percentComplete,
      categories: categories ?? this.categories,
      location: clearLocation ? null : location ?? this.location,
      url: clearUrl ? null : url ?? this.url,
      recurrenceRule: clearRecurrenceRule
          ? null
          : recurrenceRule ?? this.recurrenceRule,
      reminders: clearReminder
          ? const <CloudTaskReminder>[]
          : reminders ?? this.reminders,
      privacy: clearPrivacy ? null : privacy ?? this.privacy,
      pinned: pinned ?? this.pinned,
      createdAt: createdAt ?? this.createdAt,
      lastModifiedAt: lastModifiedAt ?? this.lastModifiedAt,
      completedAt: clearCompletedAt ? null : completedAt ?? this.completedAt,
    );
  }
}

class CloudTaskDate {
  const CloudTaskDate({
    required this.value,
    required this.isAllDay,
    this.timeZoneId,
  });

  final DateTime value;
  final bool isAllDay;

  /// The RFC 5545 TZID when the server supplied a zoned local date-time.
  ///
  /// A null value means either an all-day value, UTC (when [value.isUtc]), or
  /// a floating local date-time. Keeping this separately avoids silently
  /// shifting a server value when it is edited on a device in another zone.
  final String? timeZoneId;
}

class CloudTaskReminder {
  const CloudTaskReminder({
    required this.trigger,
    required this.relatedToEnd,
    this.action = 'DISPLAY',
    this.description,
    this.rawLines = const <String>[],
  });

  /// The RFC 5545 TRIGGER value, such as `-PT15M` or `20260915T120000Z`.
  final String trigger;
  final bool relatedToEnd;
  final String action;
  final String? description;

  /// Original VALARM lines. These are reused when the alarm is retained so
  /// unsupported properties such as REPEAT, DURATION and ATTENDEE survive.
  final List<String> rawLines;
}
