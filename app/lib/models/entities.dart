import 'dart:convert';

String uid() => DateTime.now().microsecondsSinceEpoch.toString();
String phoneKey(String phone) {
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  // Match an international number to its local 10-digit representation.
  return digits.length > 10 ? digits.substring(digits.length - 10) : digits;
}

class Lead {
  Lead({
    required this.id,
    required this.name,
    required this.company,
    required this.phone,
    this.status = 'New',
    this.notes = '',
    this.followUp,
  });
  final String id;
  String name, company, phone, status, notes;
  DateTime? followUp;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'company': company,
    'phone': phone,
    'status': status,
    'notes': notes,
    'followUp': followUp?.toIso8601String(),
  };
  factory Lead.fromJson(Map<String, dynamic> j) => Lead(
    id: j['id'],
    name: j['name'],
    company: j['company'],
    phone: j['phone'],
    status: j['status'],
    notes: j['notes'] ?? '',
    followUp: j['followUp'] == null ? null : DateTime.parse(j['followUp']),
  );
}

class WorkSession {
  WorkSession({
    required this.id,
    required this.start,
    this.end,
    List<Map<String, String?>>? breaks,
  }) : breaks = breaks ?? [];
  final String id;
  final DateTime start;
  DateTime? end;
  final List<Map<String, String?>> breaks;
  bool get onBreak => breaks.isNotEmpty && breaks.last['end'] == null;
  Duration workBetween(DateTime from, DateTime to) {
    final upper = end ?? DateTime.now();
    final a = start.isAfter(from) ? start : from;
    final b = upper.isBefore(to) ? upper : to;
    if (!b.isAfter(a)) return Duration.zero;
    var seconds = b.difference(a).inSeconds;
    for (final pause in breaks) {
      final s = DateTime.parse(pause['start']!);
      final e = pause['end'] == null
          ? DateTime.now()
          : DateTime.parse(pause['end']!);
      final x = s.isAfter(a) ? s : a;
      final y = e.isBefore(b) ? e : b;
      if (y.isAfter(x)) seconds -= y.difference(x).inSeconds;
    }
    return Duration(seconds: seconds < 0 ? 0 : seconds);
  }

  Duration breakBetween(DateTime from, DateTime to, {DateTime? now}) {
    final upper = end ?? now ?? DateTime.now();
    final a = start.isAfter(from) ? start : from,
        b = upper.isBefore(to) ? upper : to;
    if (!b.isAfter(a)) return Duration.zero;
    var total = Duration.zero;
    for (final pause in breaks) {
      final start = DateTime.parse(pause['start']!),
          end = DateTime.tryParse(pause['end'] ?? '') ?? now ?? DateTime.now();
      final x = start.isAfter(a) ? start : a, y = end.isBefore(b) ? end : b;
      if (y.isAfter(x)) total += y.difference(x);
    }
    return total;
  }

  bool contains(DateTime date) =>
      !date.isBefore(start) && !date.isAfter(end ?? DateTime.now());
  Map<String, dynamic> toJson() => {
    'id': id,
    'start': start.toIso8601String(),
    'end': end?.toIso8601String(),
    'breaks': breaks,
  };
  factory WorkSession.fromJson(Map<String, dynamic> j) => WorkSession(
    id: j['id'],
    start: DateTime.parse(j['start']),
    end: j['end'] == null ? null : DateTime.parse(j['end']),
    breaks: (j['breaks'] as List)
        .map((b) => Map<String, String?>.from(b))
        .toList(),
  );
}

class CallEntry {
  CallEntry({
    required this.id,
    required this.leadId,
    required this.at,
    required this.seconds,
    this.direction = 'Outgoing',
    this.outcome = 'Not reviewed',
    this.note = '',
    this.source = 'Manual',
  });
  final String id, leadId, direction, source;
  final DateTime at;
  final int seconds;
  String outcome, note;
  Map<String, dynamic> toJson() => {
    'id': id,
    'leadId': leadId,
    'at': at.toIso8601String(),
    'seconds': seconds,
    'direction': direction,
    'outcome': outcome,
    'note': note,
    'source': source,
  };
  factory CallEntry.fromJson(Map<String, dynamic> j) => CallEntry(
    id: j['id'],
    leadId: j['leadId'],
    at: DateTime.parse(j['at']),
    seconds: j['seconds'],
    direction: j['direction'],
    outcome: j['outcome'],
    note: j['note'],
    source: j['source'],
  );
}

String encodeState(Map<String, dynamic> state) => jsonEncode(state);
