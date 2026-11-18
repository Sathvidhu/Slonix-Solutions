part of '../main.dart';

extension _AssignmentScreens on _WorkspaceState {
  Widget assignments() {
    final cloud = s.cloud;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        pageHeading(
          'Assigned work',
          'Messages, files and next steps from your admin.',
        ),
        if (!cloud.connected) ...[
          Card(
            child: empty(
              Icons.assignment_outlined,
              'Connect to your company',
              'Sign in using the employee email your admin enrolled.',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: companyLogin,
            icon: const Icon(Icons.login),
            label: const Text('Company sign-in'),
          ),
        ] else ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  cloud.lastSync == null
                      ? 'Waiting for first refresh'
                      : 'Last sync: ${dateLabel(cloud.lastSync!)} ${hm(cloud.lastSync!)}',
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
              ),
              IconButton(
                onPressed: s.cloudBusy ? null : () => action(s.syncCompany),
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh work',
              ),
            ],
          ),
          if (cloud.error != null)
            info(
              'Company refresh failed. Showing the last received work. ${cloud.error}',
            ),
          const SizedBox(height: 12),
          if (cloud.assignments.isEmpty)
            Card(
              child: empty(
                Icons.task_alt,
                'No assignments yet',
                'Published work will appear here at its scheduled delivery time.',
              ),
            ),
          ...cloud.assignments.map((a) {
            final receipt = cloud.receipts
                .where((r) => r['assignment_id'] == a['id'])
                .firstOrNull;
            final due = DateTime.tryParse(
              a['due_at'] as String? ?? '',
            )?.toLocal();
            final done = receipt?['status'] == 'completed';
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(18),
                  leading: Icon(
                    done ? Icons.task_alt : Icons.assignment_outlined,
                    color: teal,
                  ),
                  title: Text(
                    a['title'] as String,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    '${a['priority']} priority - ${done
                        ? 'Completed'
                        : due != null
                        ? 'Due ${dateLabel(due)} ${hm(due)}'
                        : 'No deadline'}',
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => assignmentDetails(a),
                ),
              ),
            );
          }),
        ],
        const SizedBox(height: 18),
        info(
          'Work refreshes every 5 seconds while the app is open. Scheduled work stays hidden until delivery time. Notifications while the app is closed are not enabled.',
        ),
      ],
    );
  }

  Future<void> openCompanyResource(Map<String, dynamic> item) async {
    try {
      if (item['kind'] == 'text') {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(item['title'] as String),
            content: SingleChildScrollView(
              child: SelectableText(item['body'] as String),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      } else {
        final raw = item['kind'] == 'file'
            ? await s.cloud.signedFile(item['file_path'] as String)
            : item['body'] as String;
        final uri = Uri.parse(raw);
        if (!['https', 'http'].contains(uri.scheme)) {
          throw StateError('Unsupported resource link.');
        }
        if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          throw StateError('Could not open this resource.');
        }
      }
    } catch (e) {
      if (mounted) message(context, e.toString());
    }
  }

  Future<void> assignmentDetails(Map<String, dynamic> a) async {
    final contents = s.cloud.content
        .where((c) => (a['content_ids'] as List).contains(c['id']))
        .toList();
    if (!s.cloud.receipts.any((r) => r['assignment_id'] == a['id'])) {
      try {
        await s.cloud.acknowledge(a['id'] as String, 'read');
      } catch (e) {
        if (mounted) message(context, 'Could not mark read: $e');
      }
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                a['title'] as String,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Tag('${a['priority']} PRIORITY'),
              const SizedBox(height: 18),
              SelectableText(a['message'] as String),
              const SizedBox(height: 12),
              ...RegExp(r'https?://[^\s<>]+')
                  .allMatches(a['message'] as String)
                  .map(
                    (m) => TextButton.icon(
                      onPressed: () => openCompanyResource({
                        'kind': 'link',
                        'body': m.group(0)!,
                      }),
                      icon: const Icon(Icons.link),
                      label: Text(m.group(0)!, overflow: TextOverflow.ellipsis),
                    ),
                  ),
              ...contents.map(
                (c) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    c['kind'] == 'file'
                        ? Icons.file_download_outlined
                        : c['kind'] == 'link'
                        ? Icons.link
                        : Icons.message_outlined,
                    color: teal,
                  ),
                  title: Text(c['title'] as String),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => openCompanyResource(c),
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () async {
                  try {
                    await s.cloud.acknowledge(a['id'] as String, 'completed');
                    await s.syncCompany();
                    if (ctx.mounted) Navigator.pop(ctx);
                  } catch (e) {
                    if (ctx.mounted) message(ctx, e.toString());
                  }
                },
                icon: const Icon(Icons.check),
                label: const Text('Mark complete'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
