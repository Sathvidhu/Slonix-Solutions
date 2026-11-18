part of '../main.dart';

class Workspace extends StatefulWidget {
  const Workspace({super.key, required this.store});
  final AppStore store;
  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> with WidgetsBindingObserver {
  int page = 0;
  late Timer timer;
  Timer? syncTimer;
  Timer? companyTimer;
  bool importing = false;
  String query = '', filter = 'All';
  DateTime reportDay = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );
  AppStore get s => widget.store;
  void refresh(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (CallBridge.supported) {
      CallBridge.listen(() {
        if (s.consent && mounted) importCalls(silent: true);
      });
      syncTimer = Timer.periodic(const Duration(seconds: 20), (_) {
        if (s.consent &&
            mounted &&
            WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed) {
          importCalls(silent: true);
        }
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (s.consent) importCalls(silent: true);
      });
    }
    companyTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (s.cloud.connected &&
          mounted &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        s.syncCompany();
      }
    });
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      s.refreshAttendanceAlerts();
      refresh(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await s.scheduleAttendanceAlerts();
      final state = await DeviceAlerts.status();
      if (mounted && state['openInbox'] == true) openNotifications();
      if (DeviceAlerts.supported &&
          !s.prefs.containsKey('montme.alert-permission.prompted')) {
        await s.prefs.setBool('montme.alert-permission.prompted', true);
        await DeviceAlerts.permission();
      }
    });
  }

  @override
  void dispose() {
    timer.cancel();
    syncTimer?.cancel();
    companyTimer?.cancel();
    CallBridge.stopListening();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      s.scheduleAttendanceAlerts();
      if (s.cloud.connected) s.syncCompany();
    }
    if (state == AppLifecycleState.resumed &&
        s.consent &&
        CallBridge.supported) {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) importCalls(silent: true);
      });
    }
  }

  Future<void> reloadWorkspace() async {
    if (s.cloudBusy) {
      message(context, 'A sync is already running. Please wait.');
      return;
    }
    if (s.consent && CallBridge.supported) {
      await importCalls(silent: true);
    }
    await s.syncCompany();
    if (mounted) {
      message(
        context,
        s.cloud.error == null
            ? 'Database checked. Records and notifications refreshed.'
            : 'Sync failed: ${s.cloud.error}',
      );
    }
  }

  Future<void> requestEarlyExit() async {
    final reason = TextEditingController();
    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Request early clock-out'),
        content: TextField(
          controller: reason,
          maxLength: 1000,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Reason for leaving early',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (reason.text.trim().isNotEmpty) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Send request'),
          ),
        ],
      ),
    );
    if (approved == true && s.active != null) {
      await action(() async {
        await s.syncCompany();
        if (s.cloud.error != null) throw StateError(s.cloud.error!);
        await s.cloud.request(
          '/rest/v1/rpc/request_early_exit',
          method: 'POST',
          body: {
            'shift_input': s.active!.id,
            'reason_input': reason.text.trim(),
          },
        );
        await s.syncCompany();
        if (mounted) {
          message(
            context,
            'Request sent. Check Notifications for the admin decision.',
          );
        }
      });
    }
    reason.dispose();
  }

  Future<void> action(Future<void> Function() fn) async {
    try {
      await fn();
      if (s.cloud.connected) {
        unawaited(s.syncCompany());
      }
    } catch (e) {
      if (mounted) message(context, e.toString());
    }
  }

  Future<void> importCalls({bool silent = false}) async {
    if (importing) return;
    refresh(() => importing = true);
    try {
      final count = await s.importCalls();
      await s.syncCompany();
      final pending = s.pendingLeadId;
      final matches =
          s.calls
              .where(
                (c) =>
                    c.leadId == pending &&
                    c.source == 'Android' &&
                    s.pendingDialAt != null &&
                    !c.at.isBefore(
                      s.pendingDialAt!.subtract(const Duration(seconds: 5)),
                    ),
              )
              .toList()
            ..sort((a, b) => b.at.compareTo(a.at));
      if (pending != null &&
          matches.isNotEmpty &&
          mounted &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        s.pendingLeadId = null;
        s.pendingDialAt = null;
        await s.save();
        if (mounted) {
          Navigator.of(context).popUntil((r) => r.isFirst);
          refresh(() {
            page = 1;
            query = '';
            filter = 'All';
          });
          await editCall(existing: matches.first);
        }
      }
      if (mounted && !silent) {
        message(context, '$count new business calls imported.');
      }
    } catch (e) {
      if (mounted && !silent) {
        message(
          context,
          e is PlatformException ? e.message ?? 'Import failed.' : e.toString(),
        );
      }
    } finally {
      refresh(() => importing = false);
    }
  }

  Future<bool> confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      ) ??
      false;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 900;
      final content = Scaffold(
        backgroundColor: canvas,
        appBar: AppBar(
          toolbarHeight: 82,
          titleSpacing: 24,
          title: wide
              ? Text(
                  const [
                    'Overview',
                    'My leads',
                    'Call activity',
                    'My reports',
                    'Settings',
                    'Work',
                  ][page],
                )
              : const FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Brand(),
                ),
          actions: [
            IconButton(
              tooltip: 'Notifications',
              onPressed: openNotifications,
              icon: Badge(
                isLabelVisible: s.notificationInbox.any(
                  (n) => n['read_at'] == null,
                ),
                child: const Icon(Icons.notifications_outlined),
              ),
            ),
            IconButton(
              tooltip: 'Reload and check sync',
              onPressed: reloadWorkspace,
              icon: const Icon(Icons.refresh),
            ),
            if (wide) const Tag('LOCAL WORKSPACE'),
            const SizedBox(width: 12),
            CircleAvatar(
              backgroundColor: const Color(0xFFFFF1EB),
              child: Text(
                s.name[0].toUpperCase(),
                style: const TextStyle(color: teal),
              ),
            ),
            const SizedBox(width: 20),
          ],
        ),
        body: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(wide ? 30 : 20, 4, wide ? 30 : 20, 30),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (s.cloud.error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: info(
                        'Sync needs attention: ${s.cloud.error}. Tap Reload to retry. Your saved records stay on this phone.',
                      ),
                    ),
                  switch (page) {
                    0 => overview(),
                    1 => leadsPage(),
                    2 => callsPage(),
                    3 => reports(),
                    4 => settings(),
                    _ => assignments(),
                  },
                ],
              ),
            ),
          ),
        ),
        bottomNavigationBar: wide
            ? null
            : NavigationBar(
                selectedIndex: page,
                onDestinationSelected: (v) => refresh(() => page = v),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.grid_view_rounded),
                    label: 'Today',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.people_outline),
                    label: 'Leads',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.call_outlined),
                    label: 'Calls',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.bar_chart_rounded),
                    label: 'Reports',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.tune_rounded),
                    label: 'Settings',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.assignment_outlined),
                    label: 'Work',
                  ),
                ],
              ),
      );
      if (!wide) return content;
      return Row(
        children: [
          Material(
            color: Colors.white,
            child: SizedBox(
              width: 238,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
                      const Brand(),
                      const SizedBox(height: 48),
                      const Text(
                        'WORKSPACE',
                        style: TextStyle(
                          color: muted,
                          fontSize: 10,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ...List.generate(
                        6,
                        (i) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            selected: page == i,
                            selectedTileColor: const Color(0xFFFFF1EB),
                            selectedColor: teal,
                            leading: Icon(
                              [
                                Icons.grid_view_rounded,
                                Icons.people_outline,
                                Icons.call_outlined,
                                Icons.bar_chart_rounded,
                                Icons.tune_rounded,
                                Icons.assignment_outlined,
                              ][i],
                            ),
                            title: Text(
                              [
                                'Overview',
                                'My leads',
                                'Call activity',
                                'My reports',
                                'Settings',
                                'Work',
                              ][i],
                              style: const TextStyle(fontSize: 14),
                            ),
                            onTap: () => refresh(() => page = i),
                          ),
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: canvas,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.shield_outlined, color: teal),
                            const SizedBox(height: 10),
                            Text(
                              s.company,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 5),
                            const Text(
                              'Your business activity.\nYour personal space stays yours.',
                              style: TextStyle(
                                fontSize: 12,
                                color: muted,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'MONTME / EMPLOYEE EDITION',
                        style: TextStyle(
                          fontSize: 9,
                          color: muted,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(child: content),
        ],
      );
    },
  );
  Widget overview() {
    final todayCalls = s.callsFor(s.today);
    final talk = todayCalls.fold(0, (v, c) => v + c.seconds);
    final follow =
        s.leads
            .where(
              (l) =>
                  l.followUp != null &&
                  l.followUp!.isBefore(s.today.add(const Duration(days: 1))),
            )
            .toList()
          ..sort((a, b) => a.followUp!.compareTo(b.followUp!));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Row(
          children: [
            const Expanded(child: Tag('MAKE EVERY CONVERSATION COUNT')),
            const SizedBox(width: 12),
            Text(
              dateLabel(DateTime.now()),
              style: const TextStyle(color: muted),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          'Hello, ${s.name.split(' ').first}',
          style: const TextStyle(
            fontSize: 32,
            color: ink,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Here’s your day at a glance. Let’s keep things moving.',
          style: TextStyle(color: muted, height: 1.5),
        ),
        const SizedBox(height: 24),
        shiftCard(),
        const SizedBox(height: 16),
        breakHistory(),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, c) => Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              metric(
                'Business calls',
                '${todayCalls.length}',
                Icons.call_outlined,
                'Logged today',
                c.maxWidth,
              ),
              metric(
                'Connected',
                '${todayCalls.where((c) => c.seconds > 0).length}',
                Icons.phone_in_talk_outlined,
                'Calls with talk time',
                c.maxWidth,
              ),
              metric(
                'Talk time',
                '${talk ~/ 60} min',
                Icons.timelapse_rounded,
                'Conversation duration',
                c.maxWidth,
              ),
              metric(
                'Follow-ups due',
                '${follow.length}',
                Icons.event_note_outlined,
                'Today + overdue',
                c.maxWidth,
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Next conversations',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            TextButton(
              onPressed: () => refresh(() => page = 1),
              child: const Text('All leads →'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Card(
          child: follow.isEmpty
              ? empty(
                  Icons.task_alt_rounded,
                  'You’re all caught up',
                  'Schedule a follow-up on a lead to see it here.',
                )
              : Column(
                  children: follow
                      .take(4)
                      .map((l) => leadTile(l, due: true))
                      .toList(),
                ),
        ),
        const SizedBox(height: 20),
        info(
          'The shift clock continues through breaks. Reports show net work time after subtracting breaks. Clock out unlocks 2 hours after clock in.',
        ),
      ],
    );
  }

  Widget shiftCard() {
    final active = s.active;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF191B20),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: active == null
                      ? Colors.grey
                      : active.onBreak
                      ? Colors.amber
                      : const Color(0xFF7BE3BE),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  active == null
                      ? 'READY WHEN YOU ARE'
                      : active.onBreak
                      ? 'TAKING A BREATHER'
                      : 'YOU’RE ON THE CLOCK',
                  style: const TextStyle(
                    color: Colors.white70,
                    letterSpacing: 1.5,
                    fontSize: 10,
                  ),
                ),
              ),
              const Icon(Icons.schedule_rounded, color: Colors.white54),
            ],
          ),
          const SizedBox(height: 18),
          FittedBox(
            child: Text(
              elapsed(active == null ? s.workFor(s.today) : s.shiftElapsed),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 44,
                height: 1.2,
                fontWeight: FontWeight.w600,
                letterSpacing: 2,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            active == null
                ? 'Work time today · Start your next shift below'
                : 'Work time today · Shift started ${dateLabel(active.start)}, ${hm(active.start)}',
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
          const SizedBox(height: 14),
          Text(
            'Net work today: ${elapsed(s.workFor(s.today))}  |  Breaks: ${elapsed(s.breakFor(s.today))}',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          if (active?.onBreak == true) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${s.breakPolicy.kind(active!.breaks.last).toUpperCase()} BREAK',
                    style: const TextStyle(
                      color: Color(0xFFFF8C42),
                      fontSize: 10,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    elapsed(s.currentBreak),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Ends by ${hm(s.breakPolicy.ist(s.breakPolicy.savedDeadline(active.breaks.last)))} IST - ${DateTime.now().isAfter(s.breakPolicy.savedDeadline(active.breaks.last)) ? 'limit exceeded' : 'timer keeps running until you resume'}',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 22),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFF8C42),
                  disabledBackgroundColor: Colors.white12,
                  disabledForegroundColor: Colors.white60,
                  foregroundColor: ink,
                ),
                onPressed: active != null && !s.canClockOut
                    ? null
                    : () async {
                        if (active != null &&
                            !await confirm(
                              'Finish your shift?',
                              'Your work time will be saved.',
                            )) {
                          return;
                        }
                        await action(s.clock);
                      },
                icon: Icon(
                  active == null
                      ? Icons.play_arrow_rounded
                      : Icons.stop_rounded,
                ),
                label: Text(
                  active == null
                      ? 'Clock in'
                      : s.canClockOut
                      ? 'Clock out'
                      : 'Clock out after 2 hours',
                ),
              ),
              if (active != null && !s.canClockOut)
                TextButton.icon(
                  onPressed: requestEarlyExit,
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  icon: const Icon(Icons.send_outlined),
                  label: const Text('Request early clock-out'),
                ),
              if (active != null)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () =>
                      active.onBreak ? action(s.toggleBreak) : chooseBreak(),
                  icon: const Icon(Icons.coffee_outlined),
                  label: Text(active.onBreak ? 'Resume work' : 'Take a break'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> chooseBreak() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Start a break'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final item in const [
                ['lunch', 'Lunch', '1:30 PM - 2:30 PM IST'],
                ['evening', 'Evening', '5:00 PM - 5:30 PM IST'],
                ['extra', 'Extra break', 'Once per day - 10 minutes'],
              ])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.coffee_outlined, color: teal),
                  title: Text(item[1]),
                  subtitle: Text(
                    s.breakPolicy.unavailable(
                          item[0],
                          DateTime.now(),
                          s.sessions,
                        ) ??
                        item[2],
                    style: const TextStyle(fontSize: 11),
                  ),
                  enabled:
                      s.breakPolicy.unavailable(
                        item[0],
                        DateTime.now(),
                        s.sessions,
                      ) ==
                      null,
                  onTap: () async {
                    Navigator.pop(ctx);
                    await action(() => s.toggleBreak(item[0]));
                  },
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Widget breakHistory() {
    final rows = <Map<String, String?>>[];
    for (final shift in s.sessions) {
      rows.addAll(
        shift.breaks.where(
          (p) =>
              s.breakPolicy.day(DateTime.parse(p['start']!)) ==
              s.breakPolicy.day(DateTime.now()),
        ),
      );
    }
    rows.sort((a, b) => b['start']!.compareTo(a['start']!));
    return Card(
      child: ExpansionTile(
        title: const Text(
          'Break history today',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${rows.length} recorded - ${elapsed(s.breakFor(s.today))} total',
          style: const TextStyle(color: muted, fontSize: 12),
        ),
        children: rows.isEmpty
            ? [
                const ListTile(
                  title: Text(
                    'No breaks recorded today.',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ),
              ]
            : rows.map((p) {
                final start = DateTime.parse(p['start']!),
                    end = DateTime.tryParse(p['end'] ?? ''),
                    duration = (end ?? DateTime.now()).difference(start);
                return ListTile(
                  leading: const Icon(Icons.coffee_outlined, color: teal),
                  title: Text(
                    '${s.breakPolicy.kind(p)} - ${elapsed(duration)}',
                    style: const TextStyle(fontSize: 13),
                  ),
                  subtitle: Text(
                    '${hm(start)} to ${end == null ? 'in progress' : hm(end)}',
                    style: const TextStyle(fontSize: 11),
                  ),
                );
              }).toList(),
      ),
    );
  }

  Widget metric(
    String label,
    String value,
    IconData icon,
    String subtitle,
    double width,
  ) => SizedBox(
    width: (width - (width < 650 ? 12 : 36)) / (width < 650 ? 2 : 4),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: teal, size: 22),
            const SizedBox(height: 18),
            FittedBox(
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 5),
            Text(subtitle, style: const TextStyle(fontSize: 10, color: muted)),
          ],
        ),
      ),
    ),
  );
}
