part of '../main.dart';

extension _LeadScreens on _WorkspaceState {
  Widget leadsPage() {
    final list = s.leads
        .where(
          (l) =>
              (filter == 'All' || l.status == filter) &&
              '${l.name} ${l.company} ${l.phone}'.toLowerCase().contains(
                query.toLowerCase(),
              ),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        pageHeading(
          'Good leads. Better conversations.',
          'Keep your pipeline personal and your next step clear.',
        ),
        if (s.calls.isNotEmpty)
          Card(
            child: ListTile(
              leading: const Icon(Icons.history, color: teal),
              title: const Text('Last contacted'),
              subtitle: Text(() {
                final rows = s.calls.toList()
                  ..sort((a, b) => b.at.compareTo(a.at));
                final c = rows.first;
                return '${s.leadFor(c.leadId)?.name ?? 'Lead'} - ${dateLabel(c.at)} ${hm(c.at)}';
              }()),
            ),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: () => editLead(),
              icon: const Icon(Icons.add),
              label: const Text('Add lead'),
            ),
            OutlinedButton.icon(
              onPressed: importLeads,
              icon: const Icon(Icons.playlist_add),
              label: const Text('Bulk add'),
            ),
          ],
        ),
        const SizedBox(height: 22),
        TextField(
          decoration: const InputDecoration(
            hintText: 'Search name, institution or phone',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (v) => refresh(() => query = v),
        ),
        const SizedBox(height: 14),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: ['All', ...statuses]
                .map(
                  (v) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(v),
                      selected: filter == v,
                      onSelected: (_) => refresh(() => filter = v),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          '${list.length} leads',
          style: const TextStyle(color: muted, fontSize: 12),
        ),
        const SizedBox(height: 12),
        Card(
          child: list.isEmpty
              ? empty(
                  Icons.people_outline,
                  'A fresh pipeline',
                  'Add your first lead or try another search.',
                )
              : Column(children: list.map((l) => leadTile(l)).toList()),
        ),
      ],
    );
  }

  Widget leadTile(Lead l, {bool due = false}) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
    leading: CircleAvatar(
      backgroundColor: const Color(0xFFFFF1EB),
      foregroundColor: teal,
      child: Text(l.name.isEmpty ? '?' : l.name[0].toUpperCase()),
    ),
    title: Text(
      l.name,
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
    ),
    subtitle: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${l.company} · ${l.phone}',
          style: const TextStyle(fontSize: 11, color: muted),
        ),
        const SizedBox(height: 5),
        Text(
          due
              ? '${l.followUp!.isBefore(DateTime.now()) ? 'Due' : 'Today'} · ${dateLabel(l.followUp!)} ${hm(l.followUp!)}'
              : l.status,
          style: TextStyle(
            fontSize: 11,
            color: due && l.followUp!.isBefore(DateTime.now())
                ? Colors.deepOrange
                : teal,
          ),
        ),
      ],
    ),
    trailing: IconButton.filledTonal(
      tooltip: 'Call ${l.name}',
      onPressed: () => dial(l),
      icon: const Icon(Icons.call_outlined, size: 20),
    ),
    onTap: () => leadDetails(l),
  );
  Future<void> dial(Lead l) async {
    if (s.active == null || s.active!.onBreak) {
      message(
        context,
        'Clock in and resume work before calling a business lead.',
      );
      return;
    }
    try {
      s.pendingLeadId = l.id;
      s.pendingDialAt = DateTime.now();
      await s.save();
      final opened = await launchUrl(Uri(scheme: 'tel', path: l.phone));
      if (!opened) {
        s.pendingLeadId = null;
        s.pendingDialAt = null;
        await s.save();
      }
      if (!opened && mounted) {
        message(
          context,
          'No phone dialer found. Use the Android app or record a call manually.',
        );
      }
    } catch (_) {
      s.pendingLeadId = null;
      s.pendingDialAt = null;
      await s.save();
      if (mounted) {
        message(context, 'No phone dialer is available on this device.');
      }
    }
  }

  Future<void> leadDetails(Lead l) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.name,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${l.company} · ${l.phone}',
                style: const TextStyle(color: muted),
              ),
              const SizedBox(height: 16),
              Tag(l.status.toUpperCase()),
              const SizedBox(height: 16),
              Text(l.notes.isEmpty ? 'No notes yet.' : l.notes),
              if (l.followUp != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    'Follow-up: ${dateLabel(l.followUp!)} ${hm(l.followUp!)}',
                  ),
                ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: () => dial(l),
                    icon: const Icon(Icons.call),
                    label: const Text('Call lead'),
                  ),
                  OutlinedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      editLead(l);
                    },
                    child: const Text('Edit lead'),
                  ),
                  OutlinedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      editCall(lead: l);
                    },
                    child: const Text('Log a call'),
                  ),
                  if (l.followUp != null)
                    TextButton(
                      onPressed: () async {
                        l.followUp = null;
                        await action(s.save);
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      child: const Text('Complete follow-up'),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              const Text(
                'CALL HISTORY',
                style: TextStyle(
                  color: muted,
                  fontSize: 11,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 10),
              ...s.calls
                  .where((c) => c.leadId == l.id)
                  .toList()
                  .reversed
                  .take(10)
                  .map(
                    (c) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(c.outcome),
                      subtitle: Text(
                        '${dateLabel(c.at)} ${hm(c.at)} · ${shortDuration(c.seconds)} · ${c.source}',
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> editLead([Lead? old]) async {
    final name = TextEditingController(text: old?.name),
        company = TextEditingController(text: old?.company),
        phone = TextEditingController(text: old?.phone),
        notes = TextEditingController(text: old?.notes);
    final form = GlobalKey<FormState>();
    var status = old?.status ?? 'New';
    DateTime? due = old?.followUp;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text(old == null ? 'Add a business lead' : 'Edit lead'),
          content: SizedBox(
            width: 430,
            child: SingleChildScrollView(
              child: Form(
                key: form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    field(name, 'Full name'),
                    const SizedBox(height: 12),
                    field(company, 'Institution', required: false),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone number',
                      ),
                      validator: (v) {
                        final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
                        if (s.leads.any(
                          (l) =>
                              l.id != old?.id &&
                              phoneKey(l.phone) == phoneKey(v ?? ''),
                        )) {
                          return 'This business number already has a lead';
                        }
                        if (digits.length < 7 ||
                            digits.length > 15 ||
                            !RegExp(r'^\+?[\d\s()\-]+$').hasMatch(v!.trim())) {
                          return 'Enter a valid phone number';
                        }
                        if (s.leads.any(
                          (l) =>
                              l.id != old?.id &&
                              phoneKey(l.phone) == phoneKey(v),
                        )) {
                          return 'This business number already exists';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: status,
                      decoration: const InputDecoration(labelText: 'Status'),
                      items: statuses
                          .map(
                            (x) => DropdownMenuItem(value: x, child: Text(x)),
                          )
                          .toList(),
                      onChanged: (v) => status = v!,
                    ),
                    const SizedBox(height: 12),
                    field(notes, 'Notes', required: false, lines: 3),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.event_outlined),
                      title: Text(
                        due == null
                            ? 'Schedule follow-up'
                            : '${dateLabel(due!)} · ${hm(due!)}',
                      ),
                      trailing: due == null
                          ? null
                          : IconButton(
                              onPressed: () => update(() => due = null),
                              icon: const Icon(Icons.close),
                            ),
                      onTap: () async {
                        final date = await pickFollowUp(ctx);
                        if (date != null) update(() => due = date);
                      },
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
                await action(
                  () => s.upsertLead(
                    Lead(
                      id: old?.id ?? uid(),
                      name: name.text.trim(),
                      company: company.text.trim(),
                      phone: phone.text.trim(),
                      status: status,
                      notes: notes.text.trim(),
                      followUp: due,
                    ),
                  ),
                );
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Save lead'),
            ),
          ],
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    name.dispose();
    company.dispose();
    phone.dispose();
    notes.dispose();
  }

  Future<DateTime?> pickFollowUp(BuildContext ctx) async {
    final day = await showDatePicker(
      context: ctx,
      initialDate: DateTime.now(),
      firstDate: s.today,
      lastDate: s.today.add(const Duration(days: 730)),
    );
    if (day == null || !ctx.mounted) return null;
    final time = await showTimePicker(
      context: ctx,
      initialTime: TimeOfDay.now(),
    );
    return time == null
        ? null
        : DateTime(day.year, day.month, day.day, time.hour, time.minute);
  }

  Future<void> importLeads() async {
    final text = TextEditingController();
    String? validation;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: const Text('Bulk add leads'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Paste one lead per line: Name | Phone | Company\nExample: Asha Rao | +919876543210 | Acme\nDuplicates are skipped. No header needed.',
                    style: TextStyle(color: muted, height: 1.6),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: text,
                    maxLines: 8,
                    decoration: InputDecoration(
                      hintText: 'Name | Phone | Company',
                      errorText: validation,
                    ),
                  ),
                ],
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
                final added = <Lead>[];
                final keys = s.leads.map((l) => phoneKey(l.phone)).toSet();
                for (final line
                    in const LineSplitter()
                        .convert(text.text)
                        .where((x) => x.trim().isNotEmpty)) {
                  final parts = line.split('|').map((x) => x.trim()).toList();
                  if (parts.length < 2 ||
                      parts[0].isEmpty ||
                      !RegExp(r'^\+?[\d\s()\-]+$').hasMatch(parts[1]) ||
                      parts[1].replaceAll(RegExp(r'\D'), '').length < 7 ||
                      parts[1].replaceAll(RegExp(r'\D'), '').length > 15) {
                    update(
                      () => validation =
                          'Check each row: name | valid phone | company',
                    );
                    return;
                  }
                  if (!keys.add(phoneKey(parts[1]))) continue;
                  added.add(
                    Lead(
                      id: '${uid()}-${added.length}',
                      name: parts[0],
                      phone: parts[1],
                      company: parts.length > 2 ? parts[2] : '',
                    ),
                  );
                }
                if (added.isEmpty) {
                  update(
                    () => validation =
                        'No new leads found. Check for duplicates.',
                  );
                  return;
                }
                s.leads.addAll(added);
                await action(s.save);
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) message(context, '${added.length} leads added.');
              },
              child: const Text('Add leads'),
            ),
          ],
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    text.dispose();
  }
}
