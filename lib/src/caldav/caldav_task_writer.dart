import 'dart:convert';

import 'package:cloud_tasks/src/icalendar/icalendar_document.dart';
import 'package:cloud_tasks/src/icalendar/vtodo_codec.dart';
import 'package:cloud_tasks/src/network/dav_http_client.dart';
import 'package:cloud_tasks/src/sync/sync_contracts.dart';

class CalDavTaskWriter {
  const CalDavTaskWriter(this._http, {VTodoCodec codec = const VTodoCodec()})
    : _codec = codec;

  static const _timestampProperties = <String>{'DTSTAMP', 'LAST-MODIFIED'};

  final DavHttpClient _http;
  final VTodoCodec _codec;

  Future<TaskRecord> create(TaskRecord localRecord) async {
    final response = await _http.request(
      'PUT',
      localRecord.href,
      headers: const <String, String>{
        'Accept': 'text/calendar',
        'Content-Type': 'text/calendar; charset=utf-8',
        'If-None-Match': '*',
      },
      body: localRecord.rawDocument.serialize(),
    );
    if (response.statusCode == 412) {
      final remoteRecord = await read(localRecord);
      if (remoteRecord.task.uid == localRecord.task.uid) {
        return remoteRecord;
      }
      throw const CalDavTaskWriteException(
        'Nextcloud already contains a different task at the new address.',
        statusCode: 412,
      );
    }
    if (response.statusCode != 200 &&
        response.statusCode != 201 &&
        response.statusCode != 204) {
      throw CalDavTaskWriteException(
        'Nextcloud rejected the new task (HTTP ${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
    final etag = response.headers['etag'];
    if (etag == null || etag.isEmpty) {
      return read(localRecord);
    }
    return _serverRecord(localRecord, localRecord.rawDocument, etag);
  }

  Future<TaskRecord> put(
    TaskRecord localRecord, {
    required Set<String> changedProperties,
  }) async {
    final normalizedProperties = changedProperties
        .map((property) => property.toUpperCase())
        .toSet();
    if (normalizedProperties.isEmpty) {
      throw const CalDavTaskWriteException(
        'The pending edit did not identify any changed task fields.',
      );
    }

    final etag = localRecord.etag;
    if (etag == null || etag.isEmpty) {
      final remoteRecord = await read(localRecord);
      return _resolvePrecondition(
        localRecord,
        remoteRecord,
        normalizedProperties,
      );
    }
    return _putOnce(localRecord, etag, normalizedProperties, mayRebase: true);
  }

  Future<void> delete(TaskRecord localRecord) async {
    final currentEtag = localRecord.etag;
    if (currentEtag == null || currentEtag.isEmpty) {
      final remoteRecord = await read(localRecord);
      await delete(remoteRecord);
      return;
    }
    final response = await _http.request(
      'DELETE',
      localRecord.href,
      headers: <String, String>{
        'Accept': 'text/calendar',
        'If-Match': currentEtag,
      },
    );
    if (response.statusCode == 404) {
      return;
    }
    if (response.statusCode == 412) {
      final remoteRecord = await read(localRecord);
      throw TaskWriteConflict(
        localRecord: localRecord,
        remoteRecord: remoteRecord,
        changedProperties: const <String>{'*'},
      );
    }
    if (response.statusCode != 200 &&
        response.statusCode != 202 &&
        response.statusCode != 204) {
      throw CalDavTaskWriteException(
        'Nextcloud rejected the task deletion '
        '(HTTP ${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
  }

  Future<TaskRecord> read(TaskRecord localRecord) async {
    final response = await _http.request(
      'GET',
      localRecord.href,
      headers: const <String, String>{'Accept': 'text/calendar'},
    );
    if (response.statusCode != 200) {
      throw CalDavTaskWriteException(
        'Could not reload a changed task (HTTP ${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
    final etag = response.headers['etag'];
    if (etag == null || etag.isEmpty) {
      throw const CalDavTaskWriteException(
        'Nextcloud did not return an ETag for the changed task.',
      );
    }
    try {
      return _serverRecord(
        localRecord,
        ICalendarDocument.parse(utf8.decode(response.bodyBytes)),
        etag,
      );
    } on FormatException {
      throw const CalDavTaskWriteException(
        'Nextcloud returned an invalid task after the update.',
      );
    }
  }

  Future<TaskRecord> _putOnce(
    TaskRecord record,
    String etag,
    Set<String> changedProperties, {
    required bool mayRebase,
  }) async {
    final response = await _http.request(
      'PUT',
      record.href,
      headers: <String, String>{
        'Accept': 'text/calendar',
        'Content-Type': 'text/calendar; charset=utf-8',
        'If-Match': etag,
      },
      body: record.rawDocument.serialize(),
    );
    if (response.statusCode == 412) {
      final remoteRecord = await read(record);
      if (!mayRebase) {
        throw TaskWriteConflict(
          localRecord: record,
          remoteRecord: remoteRecord,
          changedProperties: changedProperties,
        );
      }
      return _resolvePrecondition(record, remoteRecord, changedProperties);
    }
    if (response.statusCode != 200 &&
        response.statusCode != 201 &&
        response.statusCode != 204) {
      throw CalDavTaskWriteException(
        'Nextcloud rejected the task update (HTTP ${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }

    final nextEtag = response.headers['etag'];
    if (nextEtag == null || nextEtag.isEmpty) {
      return read(record);
    }
    return _serverRecord(record, record.rawDocument, nextEtag);
  }

  Future<TaskRecord> _resolvePrecondition(
    TaskRecord localRecord,
    TaskRecord remoteRecord,
    Set<String> changedProperties,
  ) async {
    final baseDocument = localRecord.baseDocument;
    if (_propertiesMatch(
      localRecord.rawDocument,
      remoteRecord.rawDocument,
      changedProperties,
    )) {
      return remoteRecord;
    }
    if (baseDocument == null ||
        _hasOverlappingConflict(
          baseDocument,
          localRecord.rawDocument,
          remoteRecord.rawDocument,
          changedProperties,
        )) {
      throw TaskWriteConflict(
        localRecord: localRecord,
        remoteRecord: remoteRecord,
        changedProperties: changedProperties,
      );
    }

    var mergedDocument = remoteRecord.rawDocument;
    for (final property in <String>{
      ...changedProperties,
      ..._timestampProperties,
    }) {
      if (property == 'VALARM') {
        mergedDocument = mergedDocument.copyChildComponentsFrom(
          localRecord.rawDocument,
          'VALARM',
        );
      } else if (property == 'RELATED-TO' || property == 'CATEGORIES') {
        mergedDocument = mergedDocument.copyPropertiesFrom(
          localRecord.rawDocument,
          property,
        );
      } else {
        mergedDocument = mergedDocument.copyPropertyFrom(
          localRecord.rawDocument,
          property,
        );
      }
    }
    final mergedRecord = TaskRecord(
      task: _codec.decode(
        mergedDocument,
        calendarId: localRecord.task.calendarId,
      ),
      href: remoteRecord.href,
      etag: remoteRecord.etag,
      rawDocument: mergedDocument,
      baseDocument: remoteRecord.rawDocument,
      isDirty: true,
    );
    final remoteEtag = remoteRecord.etag;
    if (remoteEtag == null || remoteEtag.isEmpty) {
      throw const CalDavTaskWriteException(
        'Nextcloud did not return an ETag for the changed task.',
      );
    }
    return _putOnce(
      mergedRecord,
      remoteEtag,
      changedProperties,
      mayRebase: false,
    );
  }

  TaskRecord _serverRecord(
    TaskRecord previous,
    ICalendarDocument document,
    String etag,
  ) {
    return TaskRecord(
      task: _codec.decode(document, calendarId: previous.task.calendarId),
      href: previous.href,
      etag: etag,
      rawDocument: document,
      baseDocument: document,
    );
  }

  static bool _hasOverlappingConflict(
    ICalendarDocument base,
    ICalendarDocument local,
    ICalendarDocument remote,
    Set<String> properties,
  ) {
    for (final property in properties) {
      final baseValue = _propertySignature(base, property);
      final localValue = _propertySignature(local, property);
      final remoteValue = _propertySignature(remote, property);
      final changedRemotely = remoteValue != baseValue;
      final matchesLocal = remoteValue == localValue;
      if (changedRemotely && !matchesLocal) {
        return true;
      }
    }
    return false;
  }

  static bool _propertiesMatch(
    ICalendarDocument left,
    ICalendarDocument right,
    Set<String> properties,
  ) {
    for (final property in properties) {
      if (_propertySignature(left, property) !=
          _propertySignature(right, property)) {
        return false;
      }
    }
    return true;
  }

  static String? _propertySignature(
    ICalendarDocument document,
    String property,
  ) {
    if (property == 'VALARM') {
      return document.childComponentLines('VALARM').join('\r\n');
    }
    final values = document
        .propertiesIn('VTODO')
        .where((candidate) => candidate.name == property)
        .map((candidate) => candidate.toLogicalLine())
        .toList(growable: false);
    return values.isEmpty ? null : values.join('\r\n');
  }
}

class CalDavTaskWriteException implements Exception {
  const CalDavTaskWriteException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class TaskWriteConflict implements Exception {
  TaskWriteConflict({
    required this.localRecord,
    required this.remoteRecord,
    required Set<String> changedProperties,
  }) : changedProperties = Set<String>.unmodifiable(changedProperties);

  final TaskRecord localRecord;
  final TaskRecord remoteRecord;
  final Set<String> changedProperties;

  @override
  String toString() => 'The task changed on another device in the same field.';
}
