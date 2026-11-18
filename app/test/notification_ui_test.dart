import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:montme/main.dart';
import 'package:montme/services/app_store.dart';

void main() {
  testWidgets('Notifications are accessible from the main employee header', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(432, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    if (const bool.fromEnvironment('CAPTURE_PREVIEW')) {
      await tester.runAsync(() async {
        const fontDir = String.fromEnvironment('FONT_DIR');
        for (final font in {
          'Roboto': 'roboto-regular.ttf',
          'MaterialIcons': 'materialicons-regular.otf',
        }.entries) {
          final loader = FontLoader(font.key);
          loader.addFont(
            Future.value(
              ByteData.sublistView(
                await File('$fontDir/${font.value}').readAsBytes(),
              ),
            ),
          );
          await loader.load();
        }
      });
    }
    SharedPreferences.setMockInitialValues({});
    final s = AppStore(await SharedPreferences.getInstance());
    s.name = 'Employee';
    s.employeeId = 'DEMO';
    s.addLocalAlert(
      'sample',
      'Early clock-out approved',
      'Your admin approved this shift. You can now clock out.',
    );
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: teal,
            primary: teal,
            surface: Colors.white,
          ),
          scaffoldBackgroundColor: canvas,
        ),
        home: ListenableBuilder(
          listenable: s,
          builder: (context, _) => Workspace(store: s),
        ),
      ),
    );
    await tester.pump();
    expect(find.byTooltip('Notifications'), findsOneWidget);
    await tester.tap(find.byTooltip('Notifications'));
    await tester.pumpAndSettle();
    expect(find.text('Enable device alerts'), findsOneWidget);
    expect(find.text('Early clock-out approved'), findsOneWidget);
    expect(find.text('Mark as read'), findsOneWidget);
    if (const bool.fromEnvironment('CAPTURE_PREVIEW')) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../test_output/employee-notifications.png'),
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });
}
