import '../models/entities.dart';

class BreakPolicy {
  const BreakPolicy({
    this.lunchStart = '13:30',
    this.lunchEnd = '14:30',
    this.eveningStart = '17:00',
    this.eveningEnd = '17:30',
    this.extraMinutes = 10,
  });
  final String lunchStart, lunchEnd, eveningStart, eveningEnd;
  final int extraMinutes;
  factory BreakPolicy.fromSettings(Map<String, dynamic> value) => BreakPolicy(
    lunchStart: value['lunch_start'] as String? ?? '13:30',
    lunchEnd: value['lunch_end'] as String? ?? '14:30',
    eveningStart: value['evening_start'] as String? ?? '17:00',
    eveningEnd: value['evening_end'] as String? ?? '17:30',
    extraMinutes: (value['extra_break_minutes'] as num?)?.toInt() ?? 10,
  );
  DateTime ist(DateTime at) => at.toUtc().add(const Duration(minutes: 330));
  int _minutes(String value) {
    final p = value.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  DateTime _time(DateTime at, String value) {
    final d = ist(at);
    return DateTime.utc(
      d.year,
      d.month,
      d.day,
    ).add(Duration(minutes: _minutes(value) - 330));
  }

  String day(DateTime at) {
    final d = ist(at);
    return '${d.year}-${d.month}-${d.day}';
  }

  String kindAt(DateTime at) {
    final d = ist(at), minute = d.hour * 60 + d.minute;
    return minute >= _minutes(lunchStart) && minute < _minutes(lunchEnd)
        ? 'lunch'
        : minute >= _minutes(eveningStart) && minute < _minutes(eveningEnd)
        ? 'evening'
        : 'extra';
  }

  String kind(Map<String, String?> pause) =>
      pause['kind'] ?? kindAt(DateTime.parse(pause['start']!));
  DateTime deadline(String kind, DateTime start) => kind == 'lunch'
      ? _time(start, lunchEnd)
      : kind == 'evening'
      ? _time(start, eveningEnd)
      : start.add(Duration(minutes: extraMinutes));
  DateTime savedDeadline(Map<String, String?> pause) =>
      DateTime.tryParse(pause['deadline'] ?? '') ??
      deadline(kind(pause), DateTime.parse(pause['start']!));
  bool extraUsed(List<WorkSession> shifts, DateTime at) => shifts.any(
    (s) => s.breaks.any(
      (p) => kind(p) == 'extra' && day(DateTime.parse(p['start']!)) == day(at),
    ),
  );
  String? unavailable(String kind, DateTime at, List<WorkSession> shifts) {
    if (!['lunch', 'evening', 'extra'].contains(kind)) {
      return 'Choose a valid break type.';
    }
    if (kind == 'extra') {
      return extraUsed(shifts, at)
          ? 'Your one extra break for today has already been used.'
          : null;
    }
    final start = _time(at, kind == 'lunch' ? lunchStart : eveningStart),
        end = _time(at, kind == 'lunch' ? lunchEnd : eveningEnd);
    return at.isBefore(start) || !at.isBefore(end)
        ? '${kind == 'lunch' ? 'Lunch' : 'Evening'} break is available only during ${kind == 'lunch' ? '$lunchStart–$lunchEnd' : '$eveningStart–$eveningEnd'} IST.'
        : null;
  }

  DateTime windowStart(String kind, DateTime at) =>
      _time(at, kind == 'lunch' ? lunchStart : eveningStart);
}
