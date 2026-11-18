part of '../main.dart';

extension _SettingsScreens on _WorkspaceState {
  Widget settings() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      pageHeading(
        'Your workspace, your controls.',
        'Manage your profile, privacy and device data.',
      ),
      Card(
        child: Column(
          children: [
            ListTile(
              contentPadding: const EdgeInsets.all(20),
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFFFF1EB),
                child: Icon(Icons.person_outline, color: teal),
              ),
              title: Text(
                s.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text('${s.employeeId} · ${s.company}'),
              trailing: IconButton(
                tooltip: 'Edit profile',
                onPressed: editProfile,
                icon: const Icon(Icons.edit_outlined),
              ),
            ),
            const Divider(height: 1),
            const ListTile(
              leading: Icon(Icons.cloud_off_outlined),
              title: Text('Saved on this device'),
              subtitle: Text(
                'Company sync is available after employee sign-in and consent below.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      Card(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.cloud_outlined, color: teal),
              title: Text(
                s.cloud.connected
                    ? 'Connected to company'
                    : 'Connect to company',
              ),
              subtitle: Text(
                s.cloud.connected
                    ? '${s.cloud.employee!['email']} - ${s.cloud.error ?? (s.cloud.lastSync == null ? 'Waiting for first sync' : 'Last sync ${hm(s.cloud.lastSync!)}')}'
                    : 'Sign in with your invited employee email. Work records will sync to your admin.',
              ),
              onTap: s.cloud.connected
                  ? () => action(s.syncCompany)
                  : companyLogin,
            ),
            if (s.cloud.connected)
              TextButton(
                onPressed: () async {
                  await s.disconnectCompany();
                },
                child: const Text('Disconnect company account'),
              ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Card(
        child: ListTile(
          leading: const Icon(Icons.notifications_outlined, color: teal),
          title: const Text('Notifications and break alerts'),
          subtitle: const Text(
            'Enable device alerts and view your read/unread inbox.',
          ),
          onTap: openNotifications,
        ),
      ),
      const SizedBox(height: 24),
      const Text(
        'Business call import',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 12),
      Card(
        child: Column(
          children: [
            SwitchListTile(
              contentPadding: const EdgeInsets.all(20),
              value: s.consent,
              title: const Text(
                'Import matching business calls',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'With Android permission, the app reads call metadata to find saved business lead numbers during recorded shifts. Only matching records are saved. No audio recording.',
                  style: TextStyle(fontSize: 12, height: 1.6),
                ),
              ),
              onChanged: (v) async {
                if (v &&
                    !await confirm(
                      'Allow business call matching?',
                      'Android will separately ask for call-log access on first import. The app reads call metadata to find matching leads, but saves only business matches within recorded shifts. You can turn this off at any time. Company sync is separate and requires employee sign-in.',
                    )) {
                  return;
                }
                s.consent = v;
                await action(s.save);
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.android_outlined, color: teal),
              title: Text(
                CallBridge.supported
                    ? 'Android call import available'
                    : 'Preview mode',
              ),
              subtitle: Text(
                CallBridge.supported
                    ? 'Return to the app to trigger import. Device permissions are required.'
                    : 'Use the Android app for call-log import. Manual logging works here.',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      info(
        'Follow-up reminders appear inside this app. Background notifications and unattended background call collection are not enabled in this version.',
      ),
      const SizedBox(height: 24),
      Card(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.folder_open, color: teal),
              title: const Text('Call recording folder'),
              subtitle: Text(
                s.recordingFolder == null
                    ? 'Choose the folder where your phone saves recordings'
                    : 'Folder selected - Admin password required to change',
              ),
              onTap: CallBridge.supported ? recordingSettings : null,
            ),
            if (s.recordingFolder != null)
              ListTile(
                leading: const Icon(Icons.audio_file_outlined),
                title: const Text('Read saved recording files'),
                onTap: inspectRecordings,
              ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      const Text(
        'Your data',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 12),
      Card(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.file_download_outlined),
              title: const Text('Export call report'),
              subtitle: const Text('Excel workbook (.xlsx)'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => exportExcel(),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.backup_outlined),
              title: const Text('Create a full backup'),
              subtitle: const Text('Profile, leads, shifts and calls as JSON'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showExport(
                'Workspace backup · JSON',
                const JsonEncoder.withIndent('  ').convert(s.toJson()),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.restore_outlined),
              title: const Text('Restore a backup'),
              subtitle: const Text(
                'Replace this device’s records from a Montme backup',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: restore,
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      info(
        'Local storage is not a company backup or secure sign-in. Uninstalling the app or clearing browser data can remove records. Export a backup before switching devices. Use company-managed devices for the pilot.',
      ),
      const SizedBox(height: 28),
      const Center(
        child: Text(
          'MONTME  0.4.0 · EMPLOYEE EDITION',
          style: TextStyle(fontSize: 10, color: muted, letterSpacing: 1.5),
        ),
      ),
    ],
  );
  Future<void> companyLogin() async {
    await s.disconnectCompany();
  }

  Future<void> exportExcel() async {
    try {
      final saved = await saveExport(
        'montme-calls-${DateTime.now().millisecondsSinceEpoch}.xlsx',
        base64Encode(s.excel()),
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      if (mounted && saved) message(context, 'Excel report saved.');
    } catch (e) {
      if (mounted) message(context, 'Could not save Excel report: $e');
    }
  }

  Future<void> recordingSettings() async {
    final password = TextEditingController();
    final repeat = TextEditingController();
    final setup = !s.hasAdminPassword;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(setup ? 'Set admin password' : 'Admin authorization'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Android will ask you to select the recording folder. Changing it later requires this admin password.',
            ),
            TextField(
              controller: password,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Admin password (8+ characters)',
              ),
            ),
            if (setup)
              TextField(
                controller: repeat,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm password',
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                if (setup) {
                  if (password.text != repeat.text) {
                    throw StateError('Passwords do not match.');
                  }
                  await s.setAdminPassword(password.text);
                }
                await s.selectRecordingFolder(password.text);
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (e) {
                if (ctx.mounted) message(ctx, e.toString());
              }
            },
            child: const Text('Choose folder'),
          ),
        ],
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    password.dispose();
    repeat.dispose();
  }

  Future<void> inspectRecordings() async {
    try {
      final rows = await CallBridge.recordings();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Saved recordings'),
          content: SizedBox(
            width: 480,
            height: 360,
            child: rows.isEmpty
                ? const Text('No recording files found in this folder.')
                : ListView(
                    children: rows
                        .map(
                          (r) => ListTile(
                            title: Text(r['name'] as String),
                            subtitle: Text(
                              'Modified: ${DateTime.fromMillisecondsSinceEpoch((r['modified'] as num).toInt())} - ${r['duration'] == null ? 'Duration unavailable' : '${r['duration']} ms'}',
                            ),
                          ),
                        )
                        .toList(),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) message(context, 'Could not read recordings: $e');
    }
  }

  Future<void> editProfile() async {
    final name = TextEditingController(text: s.name),
        id = TextEditingController(text: s.employeeId),
        company = TextEditingController(text: s.company);
    final form = GlobalKey<FormState>();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit local profile'),
        content: SizedBox(
          width: 400,
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                field(name, 'Your name'),
                const SizedBox(height: 12),
                field(id, 'Employee ID'),
                const SizedBox(height: 12),
                field(company, 'Company name'),
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
              if (!form.currentState!.validate()) return;
              await action(() => s.profile(name.text, id.text, company.text));
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    name.dispose();
    id.dispose();
    company.dispose();
  }

  Future<void> showExport(String title, String data) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 600,
          height: 330,
          child: SingleChildScrollView(
            child: SelectableText(
              data,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () async {
              final json = title.contains('JSON');
              try {
                final saved = await saveExport(
                  'montme-${json ? 'backup' : 'calls'}-${DateTime.now().millisecondsSinceEpoch}.${json ? 'json' : 'csv'}',
                  data,
                  json ? 'application/json' : 'text/csv',
                );
                if (ctx.mounted && saved) {
                  message(ctx, 'Export saved or download started.');
                }
              } catch (_) {
                if (ctx.mounted) {
                  message(ctx, 'Could not save file. Use Copy export instead.');
                }
              }
            },
            icon: const Icon(Icons.save_alt),
            label: const Text('Save file'),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: data));
              if (ctx.mounted) {
                message(ctx, 'Copied. Paste into a file and save it securely.');
              }
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copy export'),
          ),
        ],
      ),
    );
  }

  Future<void> restore() async {
    final controller = TextEditingController();
    String? error;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: const Text('Restore workspace'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'This replaces your local records. Export a backup first. Call import consent is reset after restoring.',
                    style: TextStyle(color: muted, height: 1.5),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: controller,
                    maxLines: 8,
                    decoration: InputDecoration(
                      labelText: 'Paste Montme JSON backup',
                      errorText: error,
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
                if (!await confirm(
                  'Replace local records?',
                  'Current leads, shifts and calls on this device will be replaced by the backup.',
                )) {
                  return;
                }
                try {
                  await s.restore(controller.text);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) message(context, 'Backup restored.');
                } catch (_) {
                  update(
                    () => error = 'Invalid backup. No records were replaced.',
                  );
                }
              },
              child: const Text('Restore'),
            ),
          ],
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
  }
}
