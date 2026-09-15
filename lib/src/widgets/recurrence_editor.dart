import 'package:flutter/material.dart';

class RecurrenceEditor extends StatefulWidget {
  const RecurrenceEditor({
    required this.currentRule,
    required this.anchor,
    required this.onSave,
    super.key,
  });

  final String? currentRule;
  final DateTime anchor;
  final ValueChanged<String?> onSave;

  @override
  State<RecurrenceEditor> createState() => _RecurrenceEditorState();
}

class _RecurrenceEditorState extends State<RecurrenceEditor> {
  static const _frequencies = <String>['DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY'];
  static const _weekdayCodes = <int, String>{
    DateTime.monday: 'MO',
    DateTime.tuesday: 'TU',
    DateTime.wednesday: 'WE',
    DateTime.thursday: 'TH',
    DateTime.friday: 'FR',
    DateTime.saturday: 'SA',
    DateTime.sunday: 'SU',
  };
  static const _weekdayLabels = <int, String>{
    DateTime.monday: 'M',
    DateTime.tuesday: 'T',
    DateTime.wednesday: 'W',
    DateTime.thursday: 'T',
    DateTime.friday: 'F',
    DateTime.saturday: 'S',
    DateTime.sunday: 'S',
  };

  late String _frequency;
  late final TextEditingController _intervalController;
  late final TextEditingController _countController;
  late Set<int> _weekdays;
  late bool _monthByWeekday;
  late String _endMode;
  DateTime? _until;
  bool _containsUnsupportedParts = false;
  String? _validationMessage;

  @override
  void initState() {
    super.initState();
    final values = _parseRule(widget.currentRule);
    _frequency = _frequencies.contains(values['FREQ'])
        ? values['FREQ']!
        : 'DAILY';
    _intervalController = TextEditingController(
      text: values['INTERVAL'] ?? '1',
    );
    _countController = TextEditingController(text: values['COUNT'] ?? '10');
    _weekdays = _parseWeekdays(values['BYDAY']);
    if (_weekdays.isEmpty) {
      _weekdays.add(widget.anchor.weekday);
    }
    _monthByWeekday = (values['BYDAY'] ?? '').contains(RegExp(r'[+-]?\d'));
    if (values['COUNT'] != null) {
      _endMode = 'count';
    } else if (values['UNTIL'] != null) {
      _endMode = 'until';
      _until = _parseUntil(values['UNTIL']!);
    } else {
      _endMode = 'never';
    }
    const supported = <String>{
      'FREQ',
      'INTERVAL',
      'BYDAY',
      'BYMONTHDAY',
      'BYMONTH',
      'COUNT',
      'UNTIL',
      'WKST',
    };
    _containsUnsupportedParts = values.keys.any(
      (key) => !supported.contains(key),
    );
  }

  @override
  void dispose() {
    _intervalController.dispose();
    _countController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Repeat task',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _frequency,
                decoration: const InputDecoration(
                  labelText: 'Frequency',
                  border: OutlineInputBorder(),
                ),
                items: <DropdownMenuItem<String>>[
                  for (final frequency in _frequencies)
                    DropdownMenuItem<String>(
                      value: frequency,
                      child: Text(_frequencyLabel(frequency)),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => _frequency = value ?? _frequency),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _intervalController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Repeat every',
                  suffixText: _intervalUnit(_frequency),
                  border: const OutlineInputBorder(),
                ),
              ),
              if (_frequency == 'WEEKLY') ...<Widget>[
                const SizedBox(height: 16),
                Text(
                  'Days of the week',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: <Widget>[
                    for (final weekday in _weekdayCodes.keys)
                      FilterChip(
                        label: Text(_weekdayLabels[weekday]!),
                        selected: _weekdays.contains(weekday),
                        onSelected: (selected) => setState(() {
                          if (selected) {
                            _weekdays.add(weekday);
                          } else if (_weekdays.length > 1) {
                            _weekdays.remove(weekday);
                          }
                        }),
                      ),
                  ],
                ),
              ],
              if (_frequency == 'MONTHLY') ...<Widget>[
                const SizedBox(height: 12),
                SegmentedButton<bool>(
                  segments: <ButtonSegment<bool>>[
                    ButtonSegment<bool>(
                      value: false,
                      label: Text('Day ${widget.anchor.day}'),
                    ),
                    ButtonSegment<bool>(
                      value: true,
                      label: Text(_monthlyWeekdayLabel(widget.anchor)),
                    ),
                  ],
                  selected: <bool>{_monthByWeekday},
                  onSelectionChanged: (value) =>
                      setState(() => _monthByWeekday = value.first),
                ),
              ],
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _endMode,
                decoration: const InputDecoration(
                  labelText: 'Ends',
                  border: OutlineInputBorder(),
                ),
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(value: 'never', child: Text('Never')),
                  DropdownMenuItem(
                    value: 'count',
                    child: Text('After a number of occurrences'),
                  ),
                  DropdownMenuItem(value: 'until', child: Text('On a date')),
                ],
                onChanged: (value) =>
                    setState(() => _endMode = value ?? _endMode),
              ),
              if (_endMode == 'count') ...<Widget>[
                const SizedBox(height: 12),
                TextField(
                  controller: _countController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Occurrences',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              if (_endMode == 'until') ...<Widget>[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _chooseUntilDate,
                  icon: const Icon(Icons.event_outlined),
                  label: Text(
                    _until == null
                        ? 'Choose final date'
                        : MaterialLocalizations.of(
                            context,
                          ).formatMediumDate(_until!),
                  ),
                ),
              ],
              if (_containsUnsupportedParts)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'This rule contains options created by another client. '
                    'They remain untouched unless you save this editor.',
                  ),
                ),
              if (_validationMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _validationMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _save,
                child: const Text('Save repeat rule'),
              ),
              if (widget.currentRule != null)
                TextButton(
                  onPressed: () {
                    widget.onSave(null);
                    Navigator.pop(context);
                  },
                  child: const Text('Does not repeat'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _chooseUntilDate() async {
    final firstDate = DateTime(
      widget.anchor.year,
      widget.anchor.month,
      widget.anchor.day,
    );
    final requestedInitialDate = _until ?? firstDate;
    final selected = await showDatePicker(
      context: context,
      initialDate: requestedInitialDate.isBefore(firstDate)
          ? firstDate
          : requestedInitialDate,
      firstDate: firstDate,
      lastDate: DateTime(2200, 12, 31),
    );
    if (selected != null) {
      setState(() => _until = selected);
    }
  }

  void _save() {
    final interval = int.tryParse(_intervalController.text.trim());
    final count = int.tryParse(_countController.text.trim());
    if (interval == null || interval < 1 || interval > 999) {
      setState(() => _validationMessage = 'Use an interval from 1 to 999.');
      return;
    }
    if (_endMode == 'count' && (count == null || count < 1 || count > 9999)) {
      setState(() => _validationMessage = 'Use 1 to 9999 occurrences.');
      return;
    }
    if (_endMode == 'until' && _until == null) {
      setState(() => _validationMessage = 'Choose the final date.');
      return;
    }

    final parts = <String>['FREQ=$_frequency'];
    if (interval > 1) {
      parts.add('INTERVAL=$interval');
    }
    if (_frequency == 'WEEKLY') {
      final ordered = _weekdays.toList()..sort();
      parts.add('BYDAY=${ordered.map((day) => _weekdayCodes[day]).join(',')}');
    } else if (_frequency == 'MONTHLY') {
      if (_monthByWeekday) {
        parts.add(
          'BYDAY=${_weekdayOrdinal(widget.anchor)}'
          '${_weekdayCodes[widget.anchor.weekday]}',
        );
      } else {
        parts.add('BYMONTHDAY=${widget.anchor.day}');
      }
    } else if (_frequency == 'YEARLY') {
      parts
        ..add('BYMONTH=${widget.anchor.month}')
        ..add('BYMONTHDAY=${widget.anchor.day}');
    }
    if (_endMode == 'count') {
      parts.add('COUNT=$count');
    } else if (_endMode == 'until') {
      parts.add('UNTIL=${_formatUntil(_until!)}');
    }
    widget.onSave(parts.join(';'));
    Navigator.pop(context);
  }

  static Map<String, String> _parseRule(String? source) {
    final result = <String, String>{};
    final normalized = (source ?? '').replaceFirst(RegExp(r'^RRULE:'), '');
    for (final part in normalized.split(';')) {
      final separator = part.indexOf('=');
      if (separator <= 0 || separator == part.length - 1) {
        continue;
      }
      result[part.substring(0, separator).toUpperCase()] = part
          .substring(separator + 1)
          .toUpperCase();
    }
    return result;
  }

  static Set<int> _parseWeekdays(String? source) {
    final result = <int>{};
    for (final part in (source ?? '').split(',')) {
      final code = part.replaceAll(RegExp(r'[+-]?\d+'), '');
      for (final entry in _weekdayCodes.entries) {
        if (entry.value == code) {
          result.add(entry.key);
        }
      }
    }
    return result;
  }

  static DateTime? _parseUntil(String value) {
    if (value.length < 8) {
      return null;
    }
    try {
      return DateTime(
        int.parse(value.substring(0, 4)),
        int.parse(value.substring(4, 6)),
        int.parse(value.substring(6, 8)),
      );
    } on FormatException {
      return null;
    }
  }

  static String _formatUntil(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}'
      '${value.month.toString().padLeft(2, '0')}'
      '${value.day.toString().padLeft(2, '0')}T235959Z';

  static int _weekdayOrdinal(DateTime value) {
    final nextWeek = value.add(const Duration(days: 7));
    if (nextWeek.month != value.month) {
      return -1;
    }
    return ((value.day - 1) ~/ 7) + 1;
  }

  static String _monthlyWeekdayLabel(DateTime value) {
    final ordinal = _weekdayOrdinal(value);
    final ordinalLabel = ordinal == -1
        ? 'last'
        : <int, String>{
                1: 'first',
                2: 'second',
                3: 'third',
                4: 'fourth',
              }[ordinal] ??
              '${ordinal}th';
    return '$ordinalLabel ${_longWeekday(value.weekday)}';
  }

  static String _longWeekday(int weekday) => const <int, String>{
    DateTime.monday: 'Monday',
    DateTime.tuesday: 'Tuesday',
    DateTime.wednesday: 'Wednesday',
    DateTime.thursday: 'Thursday',
    DateTime.friday: 'Friday',
    DateTime.saturday: 'Saturday',
    DateTime.sunday: 'Sunday',
  }[weekday]!;

  static String _frequencyLabel(String frequency) => switch (frequency) {
    'DAILY' => 'Daily',
    'WEEKLY' => 'Weekly',
    'MONTHLY' => 'Monthly',
    'YEARLY' => 'Yearly',
    _ => frequency,
  };

  static String _intervalUnit(String frequency) => switch (frequency) {
    'DAILY' => 'days',
    'WEEKLY' => 'weeks',
    'MONTHLY' => 'months',
    'YEARLY' => 'years',
    _ => '',
  };
}
