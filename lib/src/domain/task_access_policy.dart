import 'package:cloud_tasks/src/domain/cloud_task.dart';

/// Nextcloud Tasks' access-class rules for CalDAV collections shared with the
/// current user.
class TaskAccessPolicy {
  const TaskAccessPolicy();

  bool canEdit({
    required bool calendarReadOnly,
    required bool calendarSharedWithMe,
    required CloudTaskPrivacy? privacy,
  }) {
    if (calendarReadOnly) {
      return false;
    }
    return !calendarSharedWithMe || _isPublic(privacy);
  }

  bool canEditPrivacy({required bool calendarSharedWithMe}) =>
      !calendarSharedWithMe;

  bool canMove({
    required bool sourceSharedWithMe,
    required bool destinationReadOnly,
    required bool destinationSharedWithMe,
    required CloudTaskPrivacy? privacy,
  }) {
    if (destinationReadOnly) {
      return false;
    }
    return _isPublic(privacy) ||
        (!sourceSharedWithMe && !destinationSharedWithMe);
  }

  static bool _isPublic(CloudTaskPrivacy? privacy) =>
      privacy == null || privacy == CloudTaskPrivacy.public;
}
