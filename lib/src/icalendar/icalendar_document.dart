import 'dart:convert';

/// A small preservation-oriented iCalendar document.
///
/// Unknown properties and parameters remain in the document when a known
/// property is edited. Lines are unfolded while parsing and folded to the
/// RFC 5545 75-octet limit while serializing.
class ICalendarDocument {
  ICalendarDocument._(this._lines);

  factory ICalendarDocument.parse(String source) {
    final normalized = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final physicalLines = normalized.split('\n');
    if (physicalLines.isNotEmpty && physicalLines.last.isEmpty) {
      physicalLines.removeLast();
    }

    final logicalLines = <String>[];
    for (final line in physicalLines) {
      if ((line.startsWith(' ') || line.startsWith('\t')) &&
          logicalLines.isNotEmpty) {
        logicalLines[logicalLines.length - 1] += line.substring(1);
      } else {
        logicalLines.add(line);
      }
    }

    return ICalendarDocument._(List<String>.unmodifiable(logicalLines));
  }

  final List<String> _lines;

  List<String> get logicalLines => List<String>.unmodifiable(_lines);

  List<ICalendarProperty> propertiesIn(String componentName) {
    final range = _componentRange(componentName);
    final properties = <ICalendarProperty>[];
    var nestedDepth = 0;
    for (var index = range.$1 + 1; index < range.$2; index++) {
      final line = _lines[index];
      final normalized = line.toUpperCase();
      if (normalized.startsWith('BEGIN:')) {
        nestedDepth++;
        continue;
      }
      if (normalized.startsWith('END:')) {
        nestedDepth--;
        continue;
      }
      if (nestedDepth > 0) {
        continue;
      }
      final property = ICalendarProperty.tryParse(line);
      if (property != null) {
        properties.add(property);
      }
    }
    return List<ICalendarProperty>.unmodifiable(properties);
  }

  ICalendarProperty? firstProperty(
    String name, {
    String componentName = 'VTODO',
  }) {
    final normalizedName = name.toUpperCase();
    for (final property in propertiesIn(componentName)) {
      if (property.name == normalizedName) {
        return property;
      }
    }
    return null;
  }

  ICalendarDocument setFirstPropertyValue(
    String name,
    String value, {
    String componentName = 'VTODO',
    Map<String, String>? parameters,
  }) {
    final range = _componentRange(componentName);
    final normalizedName = name.toUpperCase();
    final updated = List<String>.of(_lines);
    var nestedDepth = 0;

    for (var index = range.$1 + 1; index < range.$2; index++) {
      final normalized = updated[index].toUpperCase();
      if (normalized.startsWith('BEGIN:')) {
        nestedDepth++;
        continue;
      }
      if (normalized.startsWith('END:')) {
        nestedDepth--;
        continue;
      }
      if (nestedDepth > 0) {
        continue;
      }
      final property = ICalendarProperty.tryParse(updated[index]);
      if (property?.name == normalizedName) {
        updated[index] = property!.withValue(value).toLogicalLine();
        return ICalendarDocument._(List<String>.unmodifiable(updated));
      }
    }

    final property = ICalendarProperty(
      name: normalizedName,
      parameters: parameters ?? const <String, String>{},
      value: value,
    );
    updated.insert(
      _propertyInsertionIndex(range),
      property.toLogicalLine(),
    );
    return ICalendarDocument._(List<String>.unmodifiable(updated));
  }

  ICalendarDocument removeProperties(
    String name, {
    String componentName = 'VTODO',
  }) {
    final range = _componentRange(componentName);
    final normalizedName = name.toUpperCase();
    final updated = <String>[];
    var nestedDepth = 0;

    for (var index = 0; index < _lines.length; index++) {
      final line = _lines[index];
      if (index <= range.$1 || index >= range.$2) {
        updated.add(line);
        continue;
      }

      final normalized = line.toUpperCase();
      if (normalized.startsWith('BEGIN:')) {
        nestedDepth++;
        updated.add(line);
        continue;
      }
      if (normalized.startsWith('END:')) {
        nestedDepth--;
        updated.add(line);
        continue;
      }
      final property = nestedDepth == 0
          ? ICalendarProperty.tryParse(line)
          : null;
      if (property?.name != normalizedName) {
        updated.add(line);
      }
    }

    return ICalendarDocument._(List<String>.unmodifiable(updated));
  }

  ICalendarDocument removePropertiesWhere(
    String name,
    bool Function(ICalendarProperty property) predicate, {
    String componentName = 'VTODO',
  }) {
    final range = _componentRange(componentName);
    final normalizedName = name.toUpperCase();
    final updated = <String>[];
    var nestedDepth = 0;

    for (var index = 0; index < _lines.length; index++) {
      final line = _lines[index];
      if (index <= range.$1 || index >= range.$2) {
        updated.add(line);
        continue;
      }
      final normalized = line.toUpperCase();
      if (normalized.startsWith('BEGIN:')) {
        nestedDepth++;
        updated.add(line);
        continue;
      }
      if (normalized.startsWith('END:')) {
        nestedDepth--;
        updated.add(line);
        continue;
      }
      final property = nestedDepth == 0
          ? ICalendarProperty.tryParse(line)
          : null;
      if (property == null ||
          property.name != normalizedName ||
          !predicate(property)) {
        updated.add(line);
      }
    }
    return ICalendarDocument._(List<String>.unmodifiable(updated));
  }

  ICalendarDocument addProperty(
    String name,
    String value, {
    String componentName = 'VTODO',
    Map<String, String> parameters = const <String, String>{},
  }) {
    final range = _componentRange(componentName);
    final property = ICalendarProperty(
      name: name.toUpperCase(),
      value: value,
      parameters: parameters,
    );
    final updated = List<String>.of(_lines)
      ..insert(
        _propertyInsertionIndex(range),
        property.toLogicalLine(),
      );
    return ICalendarDocument._(List<String>.unmodifiable(updated));
  }

  ICalendarDocument replaceChildComponents(
    String childName,
    List<String> replacementLines, {
    String parentName = 'VTODO',
  }) {
    final range = _componentRange(parentName);
    final beginChild = 'BEGIN:${childName.toUpperCase()}';
    final updated = <String>[..._lines.take(range.$1 + 1)];
    var nestedDepth = 0;

    for (var index = range.$1 + 1; index < range.$2; index++) {
      final line = _lines[index];
      final normalized = line.toUpperCase();
      if (nestedDepth == 0 && normalized == beginChild) {
        var targetDepth = 1;
        index++;
        while (index < range.$2 && targetDepth > 0) {
          final targetLine = _lines[index].toUpperCase();
          if (targetLine.startsWith('BEGIN:')) {
            targetDepth++;
          } else if (targetLine.startsWith('END:')) {
            targetDepth--;
          }
          index++;
        }
        index--;
        continue;
      }
      updated.add(line);
      if (normalized.startsWith('BEGIN:')) {
        nestedDepth++;
      } else if (normalized.startsWith('END:')) {
        nestedDepth--;
      }
    }
    updated
      ..addAll(replacementLines)
      ..addAll(_lines.skip(range.$2));
    return ICalendarDocument._(List<String>.unmodifiable(updated));
  }

  List<String> childComponentLines(
    String childName, {
    String parentName = 'VTODO',
  }) {
    final range = _componentRange(parentName);
    final beginChild = 'BEGIN:${childName.toUpperCase()}';
    final result = <String>[];
    var nestedDepth = 0;

    for (var index = range.$1 + 1; index < range.$2; index++) {
      final normalized = _lines[index].toUpperCase();
      if (nestedDepth == 0 && normalized == beginChild) {
        var targetDepth = 0;
        do {
          final line = _lines[index];
          final targetLine = line.toUpperCase();
          result.add(line);
          if (targetLine.startsWith('BEGIN:')) {
            targetDepth++;
          } else if (targetLine.startsWith('END:')) {
            targetDepth--;
          }
          index++;
        } while (index < range.$2 && targetDepth > 0);
        index--;
        continue;
      }
      if (normalized.startsWith('BEGIN:')) {
        nestedDepth++;
      } else if (normalized.startsWith('END:')) {
        nestedDepth--;
      }
    }
    return List<String>.unmodifiable(result);
  }

  /// Returns each direct child component as an independent logical document.
  ///
  /// [childComponentLines] remains useful when copying every component as one
  /// block. This method is needed when each VALARM must be decoded separately.
  List<List<String>> childComponents(
    String childName, {
    String parentName = 'VTODO',
  }) {
    final range = _componentRange(parentName);
    final beginChild = 'BEGIN:${childName.toUpperCase()}';
    final result = <List<String>>[];
    var nestedDepth = 0;

    for (var index = range.$1 + 1; index < range.$2; index++) {
      final normalized = _lines[index].toUpperCase();
      if (nestedDepth == 0 && normalized == beginChild) {
        final component = <String>[];
        var targetDepth = 0;
        do {
          final line = _lines[index];
          final targetLine = line.toUpperCase();
          component.add(line);
          if (targetLine.startsWith('BEGIN:')) {
            targetDepth++;
          } else if (targetLine.startsWith('END:')) {
            targetDepth--;
          }
          index++;
        } while (index < range.$2 && targetDepth > 0);
        index--;
        result.add(List<String>.unmodifiable(component));
        continue;
      }
      if (normalized.startsWith('BEGIN:')) {
        nestedDepth++;
      } else if (normalized.startsWith('END:')) {
        nestedDepth--;
      }
    }
    return List<List<String>>.unmodifiable(result);
  }

  ICalendarDocument copyChildComponentsFrom(
    ICalendarDocument source,
    String childName, {
    String parentName = 'VTODO',
  }) {
    return replaceChildComponents(
      childName,
      source.childComponentLines(childName, parentName: parentName),
      parentName: parentName,
    );
  }

  ICalendarDocument replaceProperty(
    String name,
    String value, {
    String componentName = 'VTODO',
    Map<String, String> parameters = const <String, String>{},
  }) {
    final withoutProperty = removeProperties(
      name,
      componentName: componentName,
    );
    return withoutProperty.setFirstPropertyValue(
      name,
      value,
      componentName: componentName,
      parameters: parameters,
    );
  }

  ICalendarDocument copyPropertyFrom(
    ICalendarDocument source,
    String name, {
    String componentName = 'VTODO',
  }) {
    final sourceProperty = source.firstProperty(
      name,
      componentName: componentName,
    );
    if (sourceProperty == null) {
      return removeProperties(name, componentName: componentName);
    }
    return replaceProperty(
      name,
      sourceProperty.value,
      componentName: componentName,
      parameters: sourceProperty.parameters,
    );
  }

  ICalendarDocument copyPropertiesFrom(
    ICalendarDocument source,
    String name, {
    String componentName = 'VTODO',
  }) {
    final normalizedName = name.toUpperCase();
    var updated = removeProperties(name, componentName: componentName);
    for (final property in source.propertiesIn(componentName)) {
      if (property.name == normalizedName) {
        updated = updated.addProperty(
          name,
          property.value,
          componentName: componentName,
          parameters: property.parameters,
        );
      }
    }
    return updated;
  }

  String serialize() {
    final output = _lines.expand(_foldLine).join('\r\n');
    return '$output\r\n';
  }

  (int, int) _componentRange(String componentName) {
    final normalizedName = componentName.toUpperCase();
    final begin = 'BEGIN:$normalizedName';
    final end = 'END:$normalizedName';
    final startIndex = _lines.indexWhere(
      (line) => line.toUpperCase() == begin,
    );
    if (startIndex < 0) {
      throw FormatException('Missing $begin component.');
    }

    for (var index = startIndex + 1; index < _lines.length; index++) {
      if (_lines[index].toUpperCase() == end) {
        return (startIndex, index);
      }
    }
    throw FormatException('Missing $end component.');
  }

  int _propertyInsertionIndex((int, int) range) {
    for (var index = range.$1 + 1; index < range.$2; index++) {
      if (_lines[index].toUpperCase().startsWith('BEGIN:')) {
        return index;
      }
    }
    return range.$2;
  }

  static Iterable<String> _foldLine(String line) sync* {
    const firstLineLimit = 75;
    const continuationLimit = 74;
    var limit = firstLineLimit;
    var buffer = StringBuffer();
    var byteCount = 0;
    var continuation = false;

    for (final rune in line.runes) {
      final character = String.fromCharCode(rune);
      final characterBytes = utf8.encode(character).length;
      if (byteCount > 0 && byteCount + characterBytes > limit) {
        yield continuation ? ' $buffer' : buffer.toString();
        buffer = StringBuffer();
        byteCount = 0;
        limit = continuationLimit;
        continuation = true;
      }
      buffer.write(character);
      byteCount += characterBytes;
    }

    yield continuation ? ' $buffer' : buffer.toString();
  }
}

class ICalendarProperty {
  const ICalendarProperty({
    required this.name,
    required this.value,
    this.parameters = const <String, String>{},
    this.originalHeader,
  });

  static ICalendarProperty? tryParse(String line) {
    final separator = _valueSeparator(line);
    if (separator <= 0) {
      return null;
    }

    final header = line.substring(0, separator);
    final value = line.substring(separator + 1);
    final headerParts = _splitHeader(header);
    if (headerParts.isEmpty || headerParts.first.isEmpty) {
      return null;
    }

    final parameters = <String, String>{};
    for (final part in headerParts.skip(1)) {
      final equals = part.indexOf('=');
      if (equals > 0) {
        parameters[part.substring(0, equals).toUpperCase()] =
            part.substring(equals + 1);
      }
    }

    return ICalendarProperty(
      name: headerParts.first.toUpperCase(),
      value: value,
      parameters: Map<String, String>.unmodifiable(parameters),
      originalHeader: header,
    );
  }

  final String name;
  final String value;
  final Map<String, String> parameters;
  final String? originalHeader;

  ICalendarProperty withValue(String nextValue) {
    return ICalendarProperty(
      name: name,
      value: nextValue,
      parameters: parameters,
      originalHeader: originalHeader,
    );
  }

  String toLogicalLine() {
    final preservedHeader = originalHeader;
    if (preservedHeader != null) {
      return '$preservedHeader:$value';
    }

    final header = StringBuffer(name);
    for (final entry in parameters.entries) {
      header
        ..write(';')
        ..write(entry.key)
        ..write('=')
        ..write(entry.value);
    }
    return '$header:$value';
  }

  static int _valueSeparator(String line) {
    var quoted = false;
    for (var index = 0; index < line.length; index++) {
      final character = line[index];
      if (character == '"') {
        quoted = !quoted;
      } else if (character == ':' && !quoted) {
        return index;
      }
    }
    return -1;
  }

  static List<String> _splitHeader(String header) {
    final parts = <String>[];
    var quoted = false;
    var start = 0;
    for (var index = 0; index < header.length; index++) {
      final character = header[index];
      if (character == '"') {
        quoted = !quoted;
      } else if (character == ';' && !quoted) {
        parts.add(header.substring(start, index));
        start = index + 1;
      }
    }
    parts.add(header.substring(start));
    return parts;
  }
}

String decodeICalendarText(String value) {
  final result = StringBuffer();
  for (var index = 0; index < value.length; index++) {
    final character = value[index];
    if (character != r'\' || index + 1 >= value.length) {
      result.write(character);
      continue;
    }

    final escaped = value[++index];
    switch (escaped.toLowerCase()) {
      case 'n':
        result.write('\n');
        break;
      case ',':
        result.write(',');
        break;
      case ';':
        result.write(';');
        break;
      case r'\':
        result.write(r'\');
        break;
      default:
        result
          ..write(r'\')
          ..write(escaped);
        break;
    }
  }
  return result.toString();
}

String encodeICalendarText(String value) {
  return value
      .replaceAll(r'\', r'\\')
      .replaceAll(';', r'\;')
      .replaceAll(',', r'\,')
      .replaceAll('\r\n', r'\n')
      .replaceAll('\r', r'\n')
      .replaceAll('\n', r'\n');
}
