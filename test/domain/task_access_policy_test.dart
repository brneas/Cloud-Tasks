import 'package:cloud_tasks/src/domain/cloud_task.dart';
import 'package:cloud_tasks/src/domain/task_access_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const policy = TaskAccessPolicy();

  test('only public tasks are editable in a writable shared list', () {
    expect(
      policy.canEdit(
        calendarReadOnly: false,
        calendarSharedWithMe: true,
        privacy: null,
      ),
      isTrue,
    );
    expect(
      policy.canEdit(
        calendarReadOnly: false,
        calendarSharedWithMe: true,
        privacy: CloudTaskPrivacy.private,
      ),
      isFalse,
    );
    expect(
      policy.canEdit(
        calendarReadOnly: false,
        calendarSharedWithMe: true,
        privacy: CloudTaskPrivacy.confidential,
      ),
      isFalse,
    );
  });

  test('non-public tasks cannot move from or into shared lists', () {
    expect(
      policy.canMove(
        sourceSharedWithMe: false,
        destinationReadOnly: false,
        destinationSharedWithMe: true,
        privacy: CloudTaskPrivacy.private,
      ),
      isFalse,
    );
    expect(
      policy.canMove(
        sourceSharedWithMe: true,
        destinationReadOnly: false,
        destinationSharedWithMe: false,
        privacy: CloudTaskPrivacy.confidential,
      ),
      isFalse,
    );
    expect(
      policy.canMove(
        sourceSharedWithMe: true,
        destinationReadOnly: false,
        destinationSharedWithMe: false,
        privacy: CloudTaskPrivacy.public,
      ),
      isTrue,
    );
  });

  test('shared recipients cannot change task classification', () {
    expect(policy.canEditPrivacy(calendarSharedWithMe: true), isFalse);
    expect(policy.canEditPrivacy(calendarSharedWithMe: false), isTrue);
  });
}
