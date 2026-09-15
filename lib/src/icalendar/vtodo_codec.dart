import 'package:cloud_tasks/src/domain/cloud_task.dart';
import 'package:cloud_tasks/src/icalendar/icalendar_document.dart';

class VTodoCodec {
  const VTodoCodec();

  CloudTask decode(ICalendarDocument document, {String? calendarId}) {
    final uid = document.firstProperty('UID')?.value;
    if (uid == null || uid.isEmpty) {
      throw const FormatException('A VTODO must contain a non-empty UID.');
    }

    final summaryProperty = document.firstProperty('SUMMARY');
    final sortOrderValue = document.firstProperty('X-APPLE-SORT-ORDER')?.value;
    final descriptionProperty = document.firstProperty('DESCRIPTION');
    final priorityValue = document.firstProperty('PRIORITY')?.value;
    final percentValue = document.firstProperty('PERCENT-COMPLETE')?.value;
    final locationProperty = document.firstProperty('LOCATION');
    final urlValue = document.firstProperty('URL')?.value.trim();
    final recurrenceValue = document.firstProperty('RRULE')?.value.trim();
    final categories = <String>[];
    for (final property in document.propertiesIn('VTODO')) {
      if (property.name == 'CATEGORIES') {
        categories.addAll(_decodeTextList(property.value));
      }
    }

    String? parentUid;
    for (final relation in document.propertiesIn('VTODO')) {
      if (relation.name != 'RELATED-TO') {
        continue;
      }
      final relationType = relation.parameters['RELTYPE']?.toUpperCase();
      if (relationType == null || relationType == 'PARENT') {
        parentUid = relation.value;
        break;
      }
    }

    return CloudTask(
      uid: uid,
      summary: summaryProperty == null
          ? ''
          : decodeICalendarText(summaryProperty.value),
      calendarId: calendarId,
      parentUid: parentUid,
      sortOrder: int.tryParse(sortOrderValue ?? ''),
      status: CloudTaskStatus.fromICalendar(
        document.firstProperty('STATUS')?.value,
      ),
      description: descriptionProperty == null
          ? null
          : decodeICalendarText(descriptionProperty.value),
      start: _decodeDate(document.firstProperty('DTSTART')),
      due: _decodeDate(document.firstProperty('DUE')),
      priority: int.tryParse(priorityValue ?? ''),
      percentComplete: int.tryParse(percentValue ?? ''),
      categories: List<String>.unmodifiable(categories),
      location: locationProperty == null
          ? null
          : decodeICalendarText(locationProperty.value),
      url: urlValue == null || urlValue.isEmpty ? null : Uri.tryParse(urlValue),
      recurrenceRule: recurrenceValue == null || recurrenceValue.isEmpty
          ? null
          : recurrenceValue,
      reminders: _decodeReminders(document),
      privacy: CloudTaskPrivacy.fromICalendar(
        document.firstProperty('CLASS')?.value,
      ),
      pinned:
          document.firstProperty('X-PINNED')?.value.trim().toLowerCase() ==
          'true',
      createdAt: _decodeTimestamp(document.firstProperty('CREATED')?.value),
      lastModifiedAt: _decodeTimestamp(
        document.firstProperty('LAST-MODIFIED')?.value ??
            document.firstProperty('DTSTAMP')?.value,
      ),
      completedAt: _decodeTimestamp(document.firstProperty('COMPLETED')?.value),
    );
  }

  ICalendarDocument create({
    required String uid,
    required String summary,
    required int sortOrder,
    required DateTime now,
    String? parentUid,
  }) {
    final timestamp = formatUtcDateTime(now);
    final safeUid = uid.replaceAll(RegExp(r'[\r\n]'), '');
    final safeParent = parentUid?.replaceAll(RegExp(r'[\r\n]'), '');
    final parentLine = safeParent == null || safeParent.isEmpty
        ? ''
        : 'RELATED-TO;RELTYPE=PARENT:$safeParent\r\n';
    return ICalendarDocument.parse(
      'BEGIN:VCALENDAR\r\n'
      'VERSION:2.0\r\n'
      'PRODID:-//Cloud Tasks//EN\r\n'
      'CALSCALE:GREGORIAN\r\n'
      'BEGIN:VTODO\r\n'
      'UID:$safeUid\r\n'
      'CREATED:$timestamp\r\n'
      'DTSTAMP:$timestamp\r\n'
      'LAST-MODIFIED:$timestamp\r\n'
      'SEQUENCE:0\r\n'
      'SUMMARY:${encodeICalendarText(summary)}\r\n'
      'STATUS:NEEDS-ACTION\r\n'
      'PERCENT-COMPLETE:0\r\n'
      'X-APPLE-SORT-ORDER:$sortOrder\r\n'
      '$parentLine'
      'END:VTODO\r\n'
      'END:VCALENDAR\r\n',
    );
  }

  ICalendarDocument writeManualOrder(
    ICalendarDocument document,
    int sortOrder,
  ) {
    return document.setFirstPropertyValue(
      'X-APPLE-SORT-ORDER',
      sortOrder.toString(),
    );
  }

  ICalendarDocument createNextOccurrence(
    ICalendarDocument document, {
    required String uid,
    required CloudTaskDate? start,
    required CloudTaskDate? due,
    required String recurrenceRule,
    required DateTime now,
  }) {
    final safeUid = uid.replaceAll(RegExp(r'[\r\n]'), '');
    var updated = document
        .replaceProperty('UID', safeUid)
        .replaceProperty('CREATED', formatUtcDateTime(now))
        .replaceProperty('SEQUENCE', '0');
    updated = writeCompletion(updated, isCompleted: false, now: now);
    updated = writeTaskDateAndStamp(updated, 'DTSTART', start, now: now);
    updated = writeTaskDateAndStamp(updated, 'DUE', due, now: now);
    return writeRecurrenceAndStamp(updated, recurrenceRule, now: now);
  }

  /// Creates an independent open task while retaining supported and unknown
  /// VTODO properties from the source document.
  ICalendarDocument duplicate(
    ICalendarDocument document, {
    required String uid,
    required String? parentUid,
    required int sortOrder,
    required DateTime now,
    bool resetCompletion = true,
    bool resetCreated = true,
  }) {
    final safeUid = uid.replaceAll(RegExp(r'[\r\n]'), '');
    var updated = document.replaceProperty('UID', safeUid);
    if (resetCreated) {
      updated = updated
          .replaceProperty('CREATED', formatUtcDateTime(now))
          .replaceProperty('SEQUENCE', '0');
    }
    if (resetCompletion) {
      updated = writeCompletion(updated, isCompleted: false, now: now);
    }
    return writeParentAndOrderAndStamp(
      updated,
      parentUid: parentUid,
      sortOrder: sortOrder,
      now: now,
    );
  }

  ICalendarDocument writeManualOrderAndStamp(
    ICalendarDocument document,
    int sortOrder, {
    required DateTime now,
  }) {
    return stamp(writeManualOrder(document, sortOrder), now: now);
  }

  ICalendarDocument writeSummary(ICalendarDocument document, String summary) {
    return document.setFirstPropertyValue(
      'SUMMARY',
      encodeICalendarText(summary),
    );
  }

  ICalendarDocument writeSummaryAndStamp(
    ICalendarDocument document,
    String summary, {
    required DateTime now,
  }) {
    return stamp(writeSummary(document, summary), now: now);
  }

  ICalendarDocument writeDescriptionAndStamp(
    ICalendarDocument document,
    String description, {
    required DateTime now,
  }) {
    final normalized = description.trim();
    final updated = normalized.isEmpty
        ? document.removeProperties('DESCRIPTION')
        : document.setFirstPropertyValue(
            'DESCRIPTION',
            encodeICalendarText(normalized),
          );
    return stamp(updated, now: now);
  }

  ICalendarDocument writeDateAndStamp(
    ICalendarDocument document,
    String propertyName,
    DateTime? date, {
    required DateTime now,
  }) {
    final normalizedName = propertyName.toUpperCase();
    if (normalizedName != 'DTSTART' && normalizedName != 'DUE') {
      throw ArgumentError.value(
        propertyName,
        'propertyName',
        'Only DTSTART and DUE are supported.',
      );
    }
    final updated = date == null
        ? document.removeProperties(normalizedName)
        : document.replaceProperty(
            normalizedName,
            formatDate(date),
            parameters: const <String, String>{'VALUE': 'DATE'},
          );
    return stamp(updated, now: now);
  }

  ICalendarDocument writeTaskDateAndStamp(
    ICalendarDocument document,
    String propertyName,
    CloudTaskDate? date, {
    required DateTime now,
  }) {
    final normalizedName = propertyName.toUpperCase();
    if (normalizedName != 'DTSTART' && normalizedName != 'DUE') {
      throw ArgumentError.value(
        propertyName,
        'propertyName',
        'Only DTSTART and DUE are supported.',
      );
    }
    if (date == null) {
      return stamp(document.removeProperties(normalizedName), now: now);
    }

    final String value;
    final Map<String, String> parameters;
    if (date.isAllDay) {
      value = formatDate(date.value);
      parameters = const <String, String>{'VALUE': 'DATE'};
    } else {
      value = date.value.isUtc
          ? formatUtcDateTime(date.value)
          : formatFloatingDateTime(date.value);
      final timeZoneId = date.timeZoneId?.trim();
      parameters = date.value.isUtc || timeZoneId == null || timeZoneId.isEmpty
          ? const <String, String>{}
          : <String, String>{'TZID': timeZoneId};
    }
    return stamp(
      document.replaceProperty(normalizedName, value, parameters: parameters),
      now: now,
    );
  }

  ICalendarDocument writePriorityAndStamp(
    ICalendarDocument document,
    int? priority, {
    required DateTime now,
  }) {
    if (priority != null && (priority < 1 || priority > 9)) {
      throw RangeError.range(priority, 1, 9, 'priority');
    }
    final updated = priority == null
        ? document.removeProperties('PRIORITY')
        : document.setFirstPropertyValue('PRIORITY', priority.toString());
    return stamp(updated, now: now);
  }

  ICalendarDocument writeParentAndOrderAndStamp(
    ICalendarDocument document, {
    required String? parentUid,
    required int sortOrder,
    required DateTime now,
  }) {
    var updated = document.removePropertiesWhere('RELATED-TO', (property) {
      final relationType = property.parameters['RELTYPE']?.toUpperCase();
      return relationType == null || relationType == 'PARENT';
    });
    final normalizedParent = parentUid
        ?.replaceAll(RegExp(r'[\r\n]'), '')
        .trim();
    if (normalizedParent != null && normalizedParent.isNotEmpty) {
      updated = updated.addProperty(
        'RELATED-TO',
        normalizedParent,
        parameters: const <String, String>{'RELTYPE': 'PARENT'},
      );
    }
    updated = writeManualOrder(updated, sortOrder);
    return stamp(updated, now: now);
  }

  ICalendarDocument writeCategoriesAndStamp(
    ICalendarDocument document,
    Iterable<String> categories, {
    required DateTime now,
  }) {
    final normalized = categories
        .map((category) => category.trim())
        .where((category) => category.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final updated = normalized.isEmpty
        ? document.removeProperties('CATEGORIES')
        : document.replaceProperty(
            'CATEGORIES',
            normalized.map(encodeICalendarText).join(','),
          );
    return stamp(updated, now: now);
  }

  ICalendarDocument writePrivacyAndStamp(
    ICalendarDocument document,
    CloudTaskPrivacy? privacy, {
    required DateTime now,
  }) {
    final updated = privacy == null
        ? document.removeProperties('CLASS')
        : document.setFirstPropertyValue('CLASS', privacy.icalendarValue);
    return stamp(updated, now: now);
  }

  ICalendarDocument writePinnedAndStamp(
    ICalendarDocument document,
    bool pinned, {
    required DateTime now,
  }) {
    final updated = pinned
        ? document.setFirstPropertyValue('X-PINNED', 'true')
        : document.removeProperties('X-PINNED');
    return stamp(updated, now: now);
  }

  ICalendarDocument writeTextPropertyAndStamp(
    ICalendarDocument document,
    String propertyName,
    String value, {
    required DateTime now,
  }) {
    final normalizedName = propertyName.toUpperCase();
    if (normalizedName != 'LOCATION') {
      throw ArgumentError.value(
        propertyName,
        'propertyName',
        'Only LOCATION is supported as an editable text property.',
      );
    }
    final normalized = value.trim();
    final updated = normalized.isEmpty
        ? document.removeProperties(normalizedName)
        : document.setFirstPropertyValue(
            normalizedName,
            encodeICalendarText(normalized),
          );
    return stamp(updated, now: now);
  }

  ICalendarDocument writeUrlAndStamp(
    ICalendarDocument document,
    String value, {
    required DateTime now,
  }) {
    final normalized = value.replaceAll(RegExp(r'[\r\n]'), '').trim();
    final updated = normalized.isEmpty
        ? document.removeProperties('URL')
        : document.setFirstPropertyValue('URL', normalized);
    return stamp(updated, now: now);
  }

  ICalendarDocument writeRecurrenceAndStamp(
    ICalendarDocument document,
    String? rule, {
    required DateTime now,
  }) {
    final normalized = rule
        ?.replaceAll(RegExp(r'[\r\n]'), '')
        .trim()
        .toUpperCase();
    final updated = normalized == null || normalized.isEmpty
        ? document.removeProperties('RRULE')
        : document.replaceProperty('RRULE', normalized);
    return stamp(updated, now: now);
  }

  ICalendarDocument writeReminderAndStamp(
    ICalendarDocument document,
    Duration? beforeDue, {
    required DateTime now,
  }) {
    final replacement = beforeDue == null
        ? const <String>[]
        : <String>[
            'BEGIN:VALARM',
            'ACTION:DISPLAY',
            'TRIGGER;RELATED=END:${_formatNegativeDuration(beforeDue)}',
            'DESCRIPTION:Task reminder',
            'END:VALARM',
          ];
    return stamp(
      document.replaceChildComponents('VALARM', replacement),
      now: now,
    );
  }

  ICalendarDocument writeRemindersAndStamp(
    ICalendarDocument document,
    Iterable<CloudTaskReminder> reminders, {
    required DateTime now,
  }) {
    final replacement = <String>[];
    for (final reminder in reminders) {
      if (reminder.rawLines.isNotEmpty) {
        replacement.addAll(reminder.rawLines);
        continue;
      }
      final trigger = reminder.trigger.replaceAll(RegExp(r'[\r\n]'), '').trim();
      if (trigger.isEmpty) {
        continue;
      }
      final action = reminder.action
          .replaceAll(RegExp(r'[\r\n]'), '')
          .trim()
          .toUpperCase();
      final description = (reminder.description ?? 'Task reminder').trim();
      final isAbsolute = RegExp(
        r'^\d{8}T\d{6}Z?$',
        caseSensitive: false,
      ).hasMatch(trigger);
      final triggerParameters = isAbsolute
          ? ';VALUE=DATE-TIME'
          : reminder.relatedToEnd
          ? ';RELATED=END'
          : '';
      replacement.addAll(<String>[
        'BEGIN:VALARM',
        'ACTION:${action.isEmpty ? 'DISPLAY' : action}',
        'TRIGGER$triggerParameters:$trigger',
        if (description.isNotEmpty)
          'DESCRIPTION:${encodeICalendarText(description)}',
        'END:VALARM',
      ]);
    }
    return stamp(
      document.replaceChildComponents('VALARM', replacement),
      now: now,
    );
  }

  ICalendarDocument writeStatusAndProgress(
    ICalendarDocument document, {
    required CloudTaskStatus? status,
    required int percentComplete,
    required DateTime now,
  }) {
    if (percentComplete < 0 || percentComplete > 100) {
      throw RangeError.range(percentComplete, 0, 100, 'percentComplete');
    }
    if (status == CloudTaskStatus.completed) {
      return writeCompletion(document, isCompleted: true, now: now);
    }
    var adjustedPercent = percentComplete;
    if (status == null && adjustedPercent == 100) {
      adjustedPercent = 99;
    } else if (status == CloudTaskStatus.needsAction &&
        adjustedPercent == 100) {
      adjustedPercent = 0;
    } else if (status == CloudTaskStatus.inProcess &&
        (adjustedPercent == 0 || adjustedPercent == 100)) {
      adjustedPercent = 1;
    }
    var updated = status == null
        ? document.removeProperties('STATUS')
        : document.setFirstPropertyValue('STATUS', status.icalendarValue);
    updated = updated
        .setFirstPropertyValue('PERCENT-COMPLETE', adjustedPercent.toString())
        .removeProperties('COMPLETED');
    return stamp(updated, now: now);
  }

  ICalendarDocument writeCompletedAtAndStamp(
    ICalendarDocument document,
    DateTime? completedAt, {
    required DateTime now,
  }) {
    if (completedAt != null && completedAt.isAfter(now)) {
      throw ArgumentError.value(
        completedAt,
        'completedAt',
        'A completion date cannot be in the future.',
      );
    }
    if (completedAt != null) {
      final updated = document
          .setFirstPropertyValue('STATUS', 'COMPLETED')
          .setFirstPropertyValue('PERCENT-COMPLETE', '100')
          .setFirstPropertyValue('COMPLETED', formatUtcDateTime(completedAt));
      return stamp(updated, now: now);
    }
    final updated = document
        .setFirstPropertyValue('STATUS', 'IN-PROCESS')
        .setFirstPropertyValue('PERCENT-COMPLETE', '99')
        .removeProperties('COMPLETED');
    return stamp(updated, now: now);
  }

  ICalendarDocument writeProgressAndStamp(
    ICalendarDocument document,
    int percentComplete, {
    required DateTime now,
  }) {
    final status = percentComplete == 100
        ? CloudTaskStatus.completed
        : percentComplete == 0
        ? CloudTaskStatus.needsAction
        : CloudTaskStatus.inProcess;
    return writeStatusAndProgress(
      document,
      status: status,
      percentComplete: percentComplete,
      now: now,
    );
  }

  ICalendarDocument writeCompletion(
    ICalendarDocument document, {
    required bool isCompleted,
    required DateTime now,
  }) {
    var updated = document;
    if (isCompleted) {
      updated = updated
          .setFirstPropertyValue('STATUS', 'COMPLETED')
          .setFirstPropertyValue('PERCENT-COMPLETE', '100')
          .setFirstPropertyValue('COMPLETED', formatUtcDateTime(now));
    } else {
      updated = updated
          .setFirstPropertyValue('STATUS', 'NEEDS-ACTION')
          .setFirstPropertyValue('PERCENT-COMPLETE', '0')
          .removeProperties('COMPLETED');
    }
    return stamp(updated, now: now);
  }

  ICalendarDocument stamp(ICalendarDocument document, {required DateTime now}) {
    final value = formatUtcDateTime(now);
    return document
        .setFirstPropertyValue('LAST-MODIFIED', value)
        .setFirstPropertyValue('DTSTAMP', value);
  }

  static String formatUtcDateTime(DateTime value) {
    final utc = value.toUtc();
    String twoDigits(int part) => part.toString().padLeft(2, '0');
    return '${utc.year.toString().padLeft(4, '0')}'
        '${twoDigits(utc.month)}'
        '${twoDigits(utc.day)}T'
        '${twoDigits(utc.hour)}'
        '${twoDigits(utc.minute)}'
        '${twoDigits(utc.second)}Z';
  }

  static String formatDate(DateTime value) {
    String twoDigits(int part) => part.toString().padLeft(2, '0');
    return '${value.year.toString().padLeft(4, '0')}'
        '${twoDigits(value.month)}'
        '${twoDigits(value.day)}';
  }

  static String formatFloatingDateTime(DateTime value) {
    String twoDigits(int part) => part.toString().padLeft(2, '0');
    return '${value.year.toString().padLeft(4, '0')}'
        '${twoDigits(value.month)}'
        '${twoDigits(value.day)}T'
        '${twoDigits(value.hour)}'
        '${twoDigits(value.minute)}'
        '${twoDigits(value.second)}';
  }

  static CloudTaskDate? _decodeDate(ICalendarProperty? property) {
    if (property == null) {
      return null;
    }
    final value = property.value.trim();
    final valueType = property.parameters['VALUE']
        ?.replaceAll('"', '')
        .toUpperCase();
    final isAllDay =
        valueType == 'DATE' || (value.length == 8 && !value.contains('T'));
    try {
      if (isAllDay) {
        return CloudTaskDate(
          value: DateTime(
            int.parse(value.substring(0, 4)),
            int.parse(value.substring(4, 6)),
            int.parse(value.substring(6, 8)),
          ),
          isAllDay: true,
        );
      }
      if (value.length < 15 || value[8] != 'T') {
        return null;
      }
      final parts = <int>[
        int.parse(value.substring(0, 4)),
        int.parse(value.substring(4, 6)),
        int.parse(value.substring(6, 8)),
        int.parse(value.substring(9, 11)),
        int.parse(value.substring(11, 13)),
        int.parse(value.substring(13, 15)),
      ];
      final dateTime = value.endsWith('Z')
          ? DateTime.utc(
              parts[0],
              parts[1],
              parts[2],
              parts[3],
              parts[4],
              parts[5],
            )
          : DateTime(
              parts[0],
              parts[1],
              parts[2],
              parts[3],
              parts[4],
              parts[5],
            );
      return CloudTaskDate(
        value: dateTime,
        isAllDay: false,
        timeZoneId: property.parameters['TZID']?.replaceAll('"', ''),
      );
    } on FormatException {
      return null;
    } on RangeError {
      return null;
    }
  }

  static DateTime? _decodeTimestamp(String? rawValue) {
    final value = rawValue?.trim();
    if (value == null || value.length < 15 || value[8] != 'T') {
      return null;
    }
    try {
      final parts = <int>[
        int.parse(value.substring(0, 4)),
        int.parse(value.substring(4, 6)),
        int.parse(value.substring(6, 8)),
        int.parse(value.substring(9, 11)),
        int.parse(value.substring(11, 13)),
        int.parse(value.substring(13, 15)),
      ];
      return value.endsWith('Z')
          ? DateTime.utc(
              parts[0],
              parts[1],
              parts[2],
              parts[3],
              parts[4],
              parts[5],
            )
          : DateTime(
              parts[0],
              parts[1],
              parts[2],
              parts[3],
              parts[4],
              parts[5],
            );
    } on FormatException {
      return null;
    } on RangeError {
      return null;
    }
  }

  static List<String> _decodeTextList(String value) {
    final encodedValues = <String>[];
    var start = 0;
    var escaped = false;
    for (var index = 0; index < value.length; index++) {
      final character = value[index];
      if (character == ',' && !escaped) {
        encodedValues.add(value.substring(start, index));
        start = index + 1;
      }
      if (character == r'\' && !escaped) {
        escaped = true;
      } else {
        escaped = false;
      }
    }
    encodedValues.add(value.substring(start));
    return encodedValues
        .map(decodeICalendarText)
        .where((category) => category.isNotEmpty)
        .toList(growable: false);
  }

  static List<CloudTaskReminder> _decodeReminders(ICalendarDocument document) {
    final reminders = <CloudTaskReminder>[];
    for (final lines in document.childComponents('VALARM')) {
      try {
        final alarm = ICalendarDocument.parse(lines.join('\r\n'));
        final trigger = alarm.firstProperty('TRIGGER', componentName: 'VALARM');
        if (trigger == null || trigger.value.trim().isEmpty) {
          continue;
        }
        final action =
            alarm
                .firstProperty('ACTION', componentName: 'VALARM')
                ?.value
                .trim()
                .toUpperCase() ??
            'DISPLAY';
        final description = alarm.firstProperty(
          'DESCRIPTION',
          componentName: 'VALARM',
        );
        reminders.add(
          CloudTaskReminder(
            trigger: trigger.value.trim(),
            relatedToEnd: trigger.parameters['RELATED']?.toUpperCase() == 'END',
            action: action,
            description: description == null
                ? null
                : decodeICalendarText(description.value),
            rawLines: lines,
          ),
        );
      } on FormatException {
        // A malformed alarm must not prevent the task itself from loading.
      }
    }
    return List<CloudTaskReminder>.unmodifiable(reminders);
  }

  static String _formatNegativeDuration(Duration value) {
    final duration = value.abs();
    if (duration == Duration.zero) {
      return 'PT0S';
    }
    var seconds = duration.inSeconds;
    final days = seconds ~/ Duration.secondsPerDay;
    seconds %= Duration.secondsPerDay;
    final hours = seconds ~/ Duration.secondsPerHour;
    seconds %= Duration.secondsPerHour;
    final minutes = seconds ~/ Duration.secondsPerMinute;
    seconds %= Duration.secondsPerMinute;
    final result = StringBuffer('-P');
    if (days > 0) {
      result.write('${days}D');
    }
    if (hours > 0 || minutes > 0 || seconds > 0) {
      result.write('T');
      if (hours > 0) {
        result.write('${hours}H');
      }
      if (minutes > 0) {
        result.write('${minutes}M');
      }
      if (seconds > 0) {
        result.write('${seconds}S');
      }
    }
    return result.toString();
  }
}
