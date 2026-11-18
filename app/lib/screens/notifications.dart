part of '../main.dart';

extension _NotificationScreens on _WorkspaceState {
  void openNotifications() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => Scaffold(
          appBar: AppBar(title: const Text('Notifications')),
          body: ListenableBuilder(
            listenable: s,
            builder: (ctx, _) => ListView(
              padding: const EdgeInsets.all(20),
              children: [
                info(
                  'Your admin can see the read/unread status of company notifications. Device alert permissions do not affect your inbox.',
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: () async {
                    await DeviceAlerts.permission();
                    await s.scheduleAttendanceAlerts();
                    if (ctx.mounted) {
                      message(
                        ctx,
                        'Device notification permission requested. You can also change it in Android settings.',
                      );
                    }
                  },
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: const Text('Enable device alerts'),
                ),
                const SizedBox(height: 18),
                if (s.notificationInbox.isEmpty)
                  empty(
                    Icons.notifications_none,
                    'No notifications yet',
                    'Assignments and break alerts will appear here.',
                  ),
                ...s.notificationInbox.map(
                  (n) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  n['read_at'] == null
                                      ? Icons.mark_email_unread_outlined
                                      : Icons.drafts_outlined,
                                  color: teal,
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    n['title'] as String,
                                    style: TextStyle(
                                      fontWeight: n['read_at'] == null
                                          ? FontWeight.bold
                                          : FontWeight.w500,
                                    ),
                                  ),
                                ),
                                Text(
                                  n['read_at'] == null ? 'Unread' : 'Read',
                                  style: const TextStyle(
                                    color: muted,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 9),
                            Text(
                              n['body'] as String,
                              style: const TextStyle(fontSize: 12, height: 1.5),
                            ),
                            const SizedBox(height: 9),
                            Text(
                              '${dateLabel(DateTime.parse(n['at'] as String).toLocal())} ${hm(DateTime.parse(n['at'] as String).toLocal())} - ${n['remote'] == true ? 'Company' : 'Device'}',
                              style: const TextStyle(
                                color: muted,
                                fontSize: 10,
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () => action(
                                  () => s.setNotificationRead(
                                    n,
                                    n['read_at'] == null,
                                  ),
                                ),
                                child: Text(
                                  n['read_at'] == null
                                      ? 'Mark as read'
                                      : 'Mark as unread',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
