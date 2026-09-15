import 'package:cloud_tasks/src/caldav/caldav_task_writer.dart';
import 'package:cloud_tasks/src/icalendar/icalendar_document.dart';
import 'package:cloud_tasks/src/icalendar/vtodo_codec.dart';
import 'package:cloud_tasks/src/network/dav_http_client.dart';
import 'package:cloud_tasks/src/sync/sync_contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('creates a task with If-None-Match', () async {
    final base = _document(summary: 'New title', description: 'New task');
    final client = MockClient((request) async {
      expect(request.method, 'PUT');
      expect(request.headers['If-None-Match'], '*');
      expect(request.body, contains('UID:task'));
      return http.Response('', 201, headers: <String, String>{
        'etag': '"created"',
      });
    });
    final writer = CalDavTaskWriter(DavHttpClient(client));

    final result = await writer.create(
      _record(base, baseDocument: base, etag: ''),
    );

    expect(result.etag, '"created"');
    expect(result.isDirty, isFalse);
  });

  test('writes with If-Match and preserves unknown task data', () async {
    var requestCount = 0;
    final client = MockClient((request) async {
      requestCount++;
      expect(request.method, 'PUT');
      expect(request.headers['If-Match'], '"base"');
      expect(request.headers['Content-Type'],
          'text/calendar; charset=utf-8');
      expect(request.body, contains('SUMMARY:Local title'));
      expect(request.body, contains('X-UNKNOWN:keep-local'));
      return http.Response('', 204, headers: <String, String>{
        'etag': '"written"',
      });
    });
    final writer = CalDavTaskWriter(DavHttpClient(client));
    final base = _document(summary: 'Old title', description: 'Base');
    final local = const VTodoCodec().writeSummary(base, 'Local title');

    final result = await writer.put(
      _record(local, baseDocument: base, etag: '"base"'),
      changedProperties: const <String>{'SUMMARY'},
    );

    expect(requestCount, 1);
    expect(result.etag, '"written"');
    expect(result.isDirty, isFalse);
    expect(result.baseDocument?.serialize(), result.rawDocument.serialize());
  });

  test('rebases a local field over an unrelated server change', () async {
    var requestCount = 0;
    final base = _document(summary: 'Old title', description: 'Base');
    final local = const VTodoCodec().writeSummary(base, 'Local title');
    final remote = _document(
      summary: 'Old title',
      description: 'Changed remotely',
      unknownValue: 'keep-remote',
    );
    final client = MockClient((request) async {
      requestCount++;
      if (requestCount == 1) {
        expect(request.method, 'PUT');
        expect(request.headers['If-Match'], '"base"');
        return http.Response('', 412);
      }
      if (requestCount == 2) {
        expect(request.method, 'GET');
        return http.Response(
          remote.serialize(),
          200,
          headers: <String, String>{'etag': '"remote"'},
        );
      }
      expect(request.method, 'PUT');
      expect(request.headers['If-Match'], '"remote"');
      expect(request.body, contains('SUMMARY:Local title'));
      expect(request.body, contains('DESCRIPTION:Changed remotely'));
      expect(request.body, contains('X-UNKNOWN:keep-remote'));
      return http.Response('', 204, headers: <String, String>{
        'etag': '"merged"',
      });
    });
    final writer = CalDavTaskWriter(DavHttpClient(client));

    final result = await writer.put(
      _record(local, baseDocument: base, etag: '"base"'),
      changedProperties: const <String>{'SUMMARY'},
    );

    expect(requestCount, 3);
    expect(result.etag, '"merged"');
    expect(result.task.summary, 'Local title');
    expect(
      result.rawDocument.firstProperty('DESCRIPTION')?.value,
      'Changed remotely',
    );
  });

  test('does not overwrite a server change to the same field', () async {
    var requestCount = 0;
    final base = _document(summary: 'Old title', description: 'Base');
    final local = const VTodoCodec().writeSummary(base, 'Local title');
    final remote = _document(summary: 'Remote title', description: 'Base');
    final client = MockClient((request) async {
      requestCount++;
      if (request.method == 'PUT') {
        return http.Response('', 412);
      }
      return http.Response(
        remote.serialize(),
        200,
        headers: <String, String>{'etag': '"remote"'},
      );
    });
    final writer = CalDavTaskWriter(DavHttpClient(client));

    await expectLater(
      writer.put(
        _record(local, baseDocument: base, etag: '"base"'),
        changedProperties: const <String>{'SUMMARY'},
      ),
      throwsA(
        isA<TaskWriteConflict>().having(
          (error) => error.remoteRecord.task.summary,
          'remote title',
          'Remote title',
        ),
      ),
    );
    expect(requestCount, 2);
  });

  test('recognizes an update that already reached the server', () async {
    var requestCount = 0;
    final base = _document(summary: 'Old title', description: 'Base');
    final local = const VTodoCodec().writeSummary(base, 'Local title');
    final client = MockClient((request) async {
      requestCount++;
      if (request.method == 'PUT') {
        return http.Response('', 412);
      }
      return http.Response(
        local.serialize(),
        200,
        headers: <String, String>{'etag': '"already-written"'},
      );
    });
    final writer = CalDavTaskWriter(DavHttpClient(client));

    final result = await writer.put(
      _record(local, baseDocument: base, etag: '"stale"'),
      changedProperties: const <String>{'SUMMARY'},
    );

    expect(requestCount, 2);
    expect(result.etag, '"already-written"');
    expect(result.task.summary, 'Local title');
    expect(result.isDirty, isFalse);
  });

  test('deletes with If-Match and accepts an already missing task', () async {
    var requestCount = 0;
    final document = _document(summary: 'Delete me', description: 'Base');
    final client = MockClient((request) async {
      requestCount++;
      expect(request.method, 'DELETE');
      expect(request.headers['If-Match'], '"current"');
      return http.Response('', requestCount == 1 ? 204 : 404);
    });
    final writer = CalDavTaskWriter(DavHttpClient(client));
    final record = _record(
      document,
      baseDocument: document,
      etag: '"current"',
    );

    await writer.delete(record);
    await writer.delete(record);

    expect(requestCount, 2);
  });

  test('rebases a nested reminder over an unrelated server change', () async {
    var requestCount = 0;
    final base = _document(summary: 'Task', description: 'Base');
    final local = const VTodoCodec().writeReminderAndStamp(
      base,
      const Duration(minutes: 15),
      now: DateTime.utc(2026, 9, 15),
    );
    final remote = _document(
      summary: 'Task',
      description: 'Changed remotely',
    );
    final client = MockClient((request) async {
      requestCount++;
      if (requestCount == 1) {
        return http.Response('', 412);
      }
      if (requestCount == 2) {
        return http.Response(
          remote.serialize(),
          200,
          headers: <String, String>{'etag': '"remote"'},
        );
      }
      expect(request.body, contains('DESCRIPTION:Changed remotely'));
      expect(request.body, contains('TRIGGER;RELATED=END:-PT15M'));
      return http.Response('', 204, headers: <String, String>{
        'etag': '"merged"',
      });
    });
    final writer = CalDavTaskWriter(DavHttpClient(client));

    final result = await writer.put(
      _record(local, baseDocument: base, etag: '"base"'),
      changedProperties: const <String>{'VALARM'},
    );

    expect(requestCount, 3);
    expect(result.etag, '"merged"');
    expect(result.task.reminder?.trigger, '-PT15M');
  });
}

ICalendarDocument _document({
  required String summary,
  required String description,
  String unknownValue = 'keep-local',
}) {
  return ICalendarDocument.parse('''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VTODO
UID:task
SUMMARY:$summary
DESCRIPTION:$description
X-APPLE-SORT-ORDER:1048576
X-UNKNOWN:$unknownValue
END:VTODO
END:VCALENDAR
''');
}

TaskRecord _record(
  ICalendarDocument document, {
  required ICalendarDocument baseDocument,
  required String etag,
}) {
  return TaskRecord(
    task: const VTodoCodec().decode(document, calendarId: 'personal'),
    href: Uri.parse('https://cloud.example/calendars/alice/personal/task.ics'),
    etag: etag,
    rawDocument: document,
    baseDocument: baseDocument,
    isDirty: true,
  );
}
