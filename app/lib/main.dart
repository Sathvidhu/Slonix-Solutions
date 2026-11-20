import 'package:file_picker/file_picker.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'models/entities.dart';
import 'services/app_store.dart';
import 'services/call_bridge.dart';
import 'services/export_file.dart';
import 'services/device_alerts.dart';
part 'screens/workspace.dart';
part 'screens/leads.dart';
part 'screens/activity.dart';
part 'screens/settings.dart';
part 'screens/assignments.dart';
part 'screens/notifications.dart';

const ink = Color(0xFF111827),
    teal = Color(0xFFB63218),
    muted = Color(0xFF64666D),
    canvas = Color(0xFFF5F5F6);
const statuses = [
  'New',
  'Contacted',
  'Interested',
  'Follow-up',
  'Won',
  'Not interested',
];
const outcomes = [
  'Interested',
  'Follow-up',
  'No answer',
  'Busy',
  'Wrong number',
  'Not interested',
  'Converted',
];
String hm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
String dateLabel(DateTime d) =>
    '${d.day} ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]}';
String elapsed(Duration d) =>
    '${d.inHours.toString().padLeft(2, '0')}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
String shortDuration(int seconds) => '${seconds ~/ 60}m ${seconds % 60}s';
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = AppStore(await SharedPreferences.getInstance())..load();
  unawaited(store.restoreCompany());
  runApp(MontmeApp(store: store));
}

class MontmeApp extends StatelessWidget {
  const MontmeApp({super.key, required this.store});
  final AppStore store;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Montme · Employee workspace',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      fontFamily: 'Times New Roman',
      fontFamilyFallback: const ['Times', 'serif'],
      scaffoldBackgroundColor: canvas,
      colorScheme: ColorScheme.fromSeed(
        seedColor: teal,
        primary: teal,
        surface: Colors.white,
      ),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(color: ink),
        headlineMedium: TextStyle(color: ink, fontWeight: FontWeight.w800),
        titleLarge: TextStyle(color: ink, fontWeight: FontWeight.w700),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: canvas,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: canvas,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 17),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: Color(0xFFE5EBED)),
        ),
      ),
    ),
    home: ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (store.error != null) {
          return RecoveryScreen(store: store);
        }
        if (store.initializing) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return store.cloud.connected
            ? Workspace(store: store)
            : Setup(store: store);
      },
    ),
  );
}

class Setup extends StatefulWidget {
  const Setup({super.key, required this.store});
  final AppStore store;
  @override
  State<Setup> createState() => _SetupState();
}

class _SetupState extends State<Setup> {
  final form = GlobalKey<FormState>();
  final id = TextEditingController(), password = TextEditingController();
  bool accepted = false, busy = false, obscure = true;
  String? error;
  @override
  void dispose() {
    id.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Brand(),
              const SizedBox(height: 42),
              const Tag('YOUR TEAM. YOUR WORKSPACE.'),
              const SizedBox(height: 18),
              const Text(
                'Welcome to Montme.',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: ink,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Sign in with the employee ID and password provided by your admin.',
                style: TextStyle(color: muted, height: 1.6),
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Form(
                    key: form,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: id,
                          autofillHints: const [AutofillHints.username],
                          decoration: const InputDecoration(
                            labelText: 'Employee ID',
                          ),
                          validator: (v) => v == null || v.trim().isEmpty
                              ? 'Enter your employee ID'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: password,
                          obscureText: obscure,
                          autofillHints: const [AutofillHints.password],
                          decoration: InputDecoration(
                            labelText: 'Password',
                            suffixIcon: IconButton(
                              onPressed: () =>
                                  setState(() => obscure = !obscure),
                              icon: Icon(
                                obscure
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          validator: (v) => v == null || v.isEmpty
                              ? 'Enter your password'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: accepted,
                          onChanged: busy
                              ? null
                              : (v) => setState(() => accepted = v!),
                          title: const Text(
                            'Sync my work shifts, breaks, company call records and notification read status to my admin.',
                            style: TextStyle(fontSize: 12, height: 1.5),
                          ),
                        ),
                        if (error != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              error!,
                              style: const TextStyle(color: teal, fontSize: 12),
                            ),
                          ),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: busy || !accepted
                                ? null
                                : () async {
                                    if (!form.currentState!.validate()) return;
                                    setState(() {
                                      busy = true;
                                      error = null;
                                    });
                                    try {
                                      await widget.store.connectCompany(
                                        id.text.trim(),
                                        password.text,
                                      );
                                    } catch (e) {
                                      if (mounted) {
                                        setState(() => error = e.toString());
                                      }
                                    } finally {
                                      if (mounted) setState(() => busy = false);
                                    }
                                  },
                            icon: const Icon(Icons.login),
                            label: Text(busy ? 'Signing in...' : 'Sign in'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Your admin creates and resets your account. The signed-in session is stored securely on this device. Sign out on shared devices.',
                style: TextStyle(color: muted, fontSize: 11, height: 1.6),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Widget field(
  TextEditingController controller,
  String label, {
  bool required = true,
  TextInputType? keyboard,
  int lines = 1,
}) => TextFormField(
  controller: controller,
  keyboardType: keyboard,
  maxLines: lines,
  decoration: InputDecoration(labelText: label),
  validator: (v) =>
      required && (v == null || v.trim().isEmpty) ? 'Enter $label' : null,
);
void message(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
Widget pageHeading(String title, String subtitle) => Padding(
  padding: const EdgeInsets.only(top: 20, bottom: 26),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          fontSize: 28,
          color: ink,
          fontWeight: FontWeight.w800,
          height: 1.2,
        ),
      ),
      const SizedBox(height: 10),
      Text(subtitle, style: const TextStyle(color: muted, height: 1.5)),
    ],
  ),
);
Widget info(String text) => Container(
  padding: const EdgeInsets.all(16),
  decoration: BoxDecoration(
    color: const Color(0xFFFFF1EB),
    borderRadius: BorderRadius.circular(14),
  ),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Icon(Icons.info_outline, color: teal, size: 18),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(fontSize: 12, color: muted, height: 1.6),
        ),
      ),
    ],
  ),
);
Widget empty(IconData icon, String title, String subtitle) => Padding(
  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
  child: Center(
    child: Column(
      children: [
        Icon(icon, color: teal, size: 32),
        const SizedBox(height: 14),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(color: muted, fontSize: 12, height: 1.6),
        ),
      ],
    ),
  ),
);

class Tag extends StatelessWidget {
  const Tag(this.label, {super.key});
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF1EB),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 8,
        fontWeight: FontWeight.w700,
        letterSpacing: 1,
        color: teal,
      ),
    ),
  );
}

class Brand extends StatelessWidget {
  const Brand({super.key});
  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/montme_logo.png',
    width: 154,
    height: 32,
    fit: BoxFit.contain,
    semanticLabel: 'Montme',
  );
}

class RecoveryScreen extends StatefulWidget {
  const RecoveryScreen({super.key, required this.store});
  final AppStore store;
  @override
  State<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<RecoveryScreen> {
  final backup = TextEditingController();
  String? status;
  @override
  void dispose() {
    backup.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Brand(),
              const SizedBox(height: 32),
              const Text(
                'Let’s recover your workspace',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Text(widget.store.error!),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(
                      text: widget.store.prefs.getString('montme.v1') ?? '',
                    ),
                  );
                  if (context.mounted) {
                    message(context, 'Original storage copied for recovery.');
                  }
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copy original data'),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: backup,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: 'Paste a valid Montme JSON backup',
                ),
              ),
              const SizedBox(height: 14),
              if (status != null)
                Text(status!, style: const TextStyle(color: Colors.deepOrange)),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: () async {
                  try {
                    await widget.store.restore(backup.text);
                  } catch (_) {
                    setState(
                      () => status =
                          'The backup is invalid. Original storage has been kept.',
                    );
                  }
                },
                child: const Text('Restore workspace'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
