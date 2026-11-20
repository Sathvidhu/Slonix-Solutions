part of '../main.dart';

extension _ActivityScreens on _WorkspaceState {
  Widget callsPage() {
    final list = s.calls.toList()..sort((a, b) => b.at.compareTo(a.at));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        pageHeading(
          'Every conversation, accounted for.',
          'Review your business calls and capture what happens next.',
        ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: s.leads.isEmpty ? null : () => editCall(),
              icon: const Icon(Icons.add_call),
              label: const Text('Log a call'),
            ),
            OutlinedButton.icon(
              onPressed: importing ? null : () => importCalls(),
              icon: const Icon(Icons.sync),
              label: Text(importing ? 'Importing…' : 'Import Android calls'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        info(
          'Only saved business lead numbers within your recorded shifts are imported. Import runs automatically while this app is open and when you return. Manual entries are self-reported; avoid logging the same call twice.',
        ),
        const SizedBox(height: 18),
        Text(
          s.lastImport == null
              ? 'No device import yet · ${list.length} call records'
              : 'Last import: ${dateLabel(s.lastImport!)} ${hm(s.lastImport!)} · ${list.length} records',
          style: const TextStyle(color: muted, fontSize: 12),
        ),
        const SizedBox(height: 12),
        Card(
          child: list.isEmpty
              ? empty(
                  Icons.call_outlined,
                  'Your next conversation starts here',
                  'Add a lead, make a call, then import or log the outcome.',
                )
              : Column(children: list.map(callTile).toList()),
        ),
      ],
    );
  }

  Widget callTile(CallEntry c) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
    leading: CircleAvatar(
      backgroundColor: c.seconds > 0
          ? const Color(0xFFFFF1EB)
          : const Color(0xFFFFF1EB),
      child: Icon(
        c.direction == 'Incoming'
            ? Icons.call_received
            : c.direction == 'Missed'
            ? Icons.call_missed
            : Icons.call_made,
        size: 20,
        color: c.seconds > 0 ? teal : Colors.deepOrange,
      ),
    ),
    title: Text(
      s.leadFor(c.leadId)?.name ?? 'Business lead',
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
    subtitle: Text(
      '${dateLabel(c.at)} ${hm(c.at)} · ${c.outcome}\n${c.source} · ${c.direction}',
      style: const TextStyle(fontSize: 11, color: muted),
    ),
    isThreeLine: true,
    trailing: Text(
      shortDuration(c.seconds),
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    ),
    onTap: () => editCall(existing: c),
  );
  Future<void> editCall({Lead? lead, CallEntry? existing}) async {
    if (s.leads.isEmpty) {
      message(context, 'Add a business lead first.');
      return;
    }
    var leadId = existing?.leadId ?? lead?.id ?? s.leads.first.id;
    var outcome = existing?.outcome == 'Not reviewed'
        ? 'Follow-up'
        : existing?.outcome ?? 'Follow-up';
    var direction = existing?.direction ?? 'Outgoing';
    final duration = TextEditingController(
          text: (existing?.seconds ?? 0).toString(),
        ),
        notes = TextEditingController(text: existing?.note);
    final form = GlobalKey<FormState>();
    DateTime at = existing?.at ?? DateTime.now();
    DateTime? due;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text(
            existing == null ? 'Log a conversation' : 'Review conversation',
          ),
          content: SizedBox(
            width: 430,
            child: SingleChildScrollView(
              child: Form(
                key: form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (existing == null)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 14),
                        child: Text(
                          'Manual records are self-reported. Enter actual connected talk time; use 0 for unanswered calls.',
                          style: TextStyle(color: muted, fontSize: 12),
                        ),
                      ),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: leadId,
                      decoration: const InputDecoration(
                        labelText: 'Business lead',
                      ),
                      items: s.leads
                          .map(
                            (l) => DropdownMenuItem(
                              value: l.id,
                              child: Text(l.name),
                            ),
                          )
                          .toList(),
                      onChanged: existing != null ? null : (v) => leadId = v!,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: direction,
                      decoration: const InputDecoration(labelText: 'Direction'),
                      items: ['Outgoing', 'Incoming', 'Missed', 'Rejected']
                          .map(
                            (v) => DropdownMenuItem(value: v, child: Text(v)),
                          )
                          .toList(),
                      onChanged: existing != null
                          ? null
                          : (v) => direction = v!,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: duration,
                      enabled: existing == null,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Talk time in seconds',
                      ),
                      validator: (v) =>
                          int.tryParse(v ?? '') == null ||
                              int.parse(v!) < 0 ||
                              int.parse(v) > 86400
                          ? 'Enter 0–86400 seconds'
                          : null,
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${dateLabel(at)} · ${hm(at)}'),
                      trailing: existing == null
                          ? const Icon(Icons.edit_calendar)
                          : null,
                      onTap: existing != null
                          ? null
                          : () async {
                              final day = await showDatePicker(
                                context: ctx,
                                initialDate: at,
                                firstDate: s.today.subtract(
                                  const Duration(days: 365),
                                ),
                                lastDate: s.today,
                              );
                              if (day == null || !ctx.mounted) return;
                              final time = await showTimePicker(
                                context: ctx,
                                initialTime: TimeOfDay.fromDateTime(at),
                              );
                              if (time != null) {
                                update(
                                  () => at = DateTime(
                                    day.year,
                                    day.month,
                                    day.day,
                                    time.hour,
                                    time.minute,
                                  ),
                                );
                              }
                            },
                    ),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: outcome,
                      decoration: const InputDecoration(labelText: 'Outcome'),
                      items: outcomes
                          .map(
                            (x) => DropdownMenuItem(value: x, child: Text(x)),
                          )
                          .toList(),
                      onChanged: (v) => outcome = v!,
                    ),
                    const SizedBox(height: 12),
                    field(
                      notes,
                      'Conversation notes',
                      required: false,
                      lines: 3,
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        final value = await pickFollowUp(ctx);
                        if (value != null) update(() => due = value);
                      },
                      icon: const Icon(Icons.event_outlined),
                      label: Text(
                        due == null
                            ? 'Schedule next follow-up'
                            : '${dateLabel(due!)} ${hm(due!)}',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (!form.currentState!.validate()) return;
                if (at.isAfter(DateTime.now())) {
                  message(context, 'A call cannot be logged in the future.');
                  return;
                }
                if (existing == null &&
                    (direction == 'Missed' || direction == 'Rejected') &&
                    int.parse(duration.text) > 0) {
                  message(
                    context,
                    'Missed or rejected calls must have zero talk time.',
                  );
                  return;
                }
                if (existing == null) {
                  s.calls.add(
                    CallEntry(
                      id: uid(),
                      leadId: leadId,
                      at: at,
                      seconds: int.parse(duration.text),
                      direction: direction,
                      outcome: outcome,
                      note: notes.text.trim(),
                    ),
                  );
                } else {
                  try {
                    await s.reviewCall(
                      existing,
                      outcome,
                      notes.text.trim(),
                      due,
                    );
                  } catch (error) {
                    if (ctx.mounted) message(ctx, error.toString());
                    return;
                  }
                }
                final selectedLead = s.leadFor(leadId)!;
                selectedLead.status = switch (outcome) {
                  'Converted' => 'Won',
                  'Interested' => 'Interested',
                  'Not interested' => 'Not interested',
                  'Follow-up' => 'Follow-up',
                  _ => 'Contacted',
                };
                if (due != null) selectedLead.followUp = due;
                if (outcome == 'Converted' || outcome == 'Not interested') {
                  selectedLead.followUp = null;
                }
                await s.queueContactUpdate(selectedLead);
                await action(s.save);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Save outcome'),
            ),
          ],
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    duration.dispose();
    notes.dispose();
  }

  Widget reports() {
    final entries = s.callsFor(reportDay),
        connected = s.callsFor(reportDay).where((c) => c.seconds > 0).length;
    final seconds = entries.fold(0, (v, c) => v + c.seconds);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        pageHeading(
          'See the work behind the numbers.',
          'An honest view of your time and conversations.',
        ),
        OutlinedButton.icon(
          onPressed: () async {
            final day = await showDatePicker(
              context: context,
              initialDate: reportDay,
              firstDate: s.today.subtract(const Duration(days: 730)),
              lastDate: s.today,
            );
            if (day != null) refresh(() => reportDay = day);
          },
          icon: const Icon(Icons.calendar_today_outlined),
          label: Text('${dateLabel(reportDay)} ${reportDay.year}'),
        ),
        const SizedBox(height: 22),
        LayoutBuilder(
          builder: (ctx, c) => Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              metric(
                'Work time',
                '${s.workFor(reportDay).inHours}h ${s.workFor(reportDay).inMinutes % 60}m',
                Icons.schedule,
                'Shift time minus breaks',
                c.maxWidth,
              ),
              metric(
                'Calls logged',
                '${entries.length}',
                Icons.call_outlined,
                '$connected connected',
                c.maxWidth,
              ),
              metric(
                'Talk time',
                '${seconds ~/ 60} min',
                Icons.timelapse,
                'Actual conversation time',
                c.maxWidth,
              ),
              metric(
                'Connection rate',
                '${entries.isEmpty ? 0 : (connected / entries.length * 100).round()}%',
                Icons.insights,
                'Duration greater than zero',
                c.maxWidth,
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        const Text(
          'Recorded days - last 7 days',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              children: s.reportDays(reportDay).map((d) {
                final work = s.workFor(d).inMinutes;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 60,
                        child: Text(
                          dateLabel(d),
                          style: const TextStyle(fontSize: 12, color: muted),
                        ),
                      ),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: (work / 480).clamp(0, 1),
                            minHeight: 12,
                            backgroundColor: canvas,
                            color: teal,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      SizedBox(
                        width: 54,
                        child: Text(
                          '${work ~/ 60}h ${work % 60}m',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Bar scale: 8 hours. Exact totals are shown beside each day.',
          style: TextStyle(color: muted, fontSize: 11),
        ),
        const SizedBox(height: 26),
        const Text(
          'Shift history',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Card(
          child: s.sessions.isEmpty
              ? empty(
                  Icons.schedule_outlined,
                  'No shifts yet',
                  'Clock in to start your work history.',
                )
              : Column(
                  children: s.sessions.reversed
                      .map(
                        (shift) => ListTile(
                          leading: const Icon(Icons.schedule, color: teal),
                          title: Text(
                            '${dateLabel(shift.start)} · ${hm(shift.start)} → ${shift.end == null ? 'Active' : '${dateLabel(shift.end!)} ${hm(shift.end!)}'}',
                            style: const TextStyle(fontSize: 13),
                          ),
                          subtitle: Text(
                            '${shift.breaks.length} breaks · ${elapsed(shift.workBetween(shift.start, shift.end ?? DateTime.now()))} worked',
                            style: const TextStyle(color: muted, fontSize: 12),
                          ),
                        ),
                      )
                      .toList(),
                ),
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: () => exportExcel(),
          icon: const Icon(Icons.file_download_outlined),
          label: const Text('Export all call records'),
        ),
      ],
    );
  }
}
