import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weighing_system_elinux/weighing_system_elinux.dart';

import 'package:hmi_edge_preview/l10n/app_localizations.dart';
import 'package:hmi_edge_preview/providers/app_state.dart';
import 'package:hmi_edge_preview/screens/home_screen.dart';
import 'package:hmi_edge_preview/screens/settings/home_subsystem_config_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late WebPreviewWeighingPlatform platform;
  late AppState appState;

  setUp(() {
    registerWebPreviewPlatform();
    platform = WeighingPlatform.instance as WebPreviewWeighingPlatform;
    appState = AppState();
  });

  tearDown(() async {
    appState.dispose();
    await platform.shutdown();
  });

  Future<void> pumpHome(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(AppStateProvider(
      notifier: appState,
      onLocaleChange: (_) {},
      child: const MaterialApp(
        locale: Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: HomeScreen(),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('rail batch entry leaves single panel full height and unobstructed',
      (tester) async {
    await pumpHome(tester, const Size(1280, 800));
    await tester.tap(find.text('1# 失重秤'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    final panel = tester.getRect(find.byType(HomeSubsystemConfigPanel));
    final entry = tester.getRect(find.byKey(const Key('batch-mode-toggle')));
    expect(panel.top, tester.getRect(find.byType(AppBar)).bottom + 12);
    expect(panel.bottom, 800 - 12);
    expect(entry.right, lessThan(panel.left));
    expect(entry.width, greaterThanOrEqualTo(48));
    expect(entry.height, greaterThanOrEqualTo(48));
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.text('想同时配置多台秤？'), findsNothing);
    await tester.tap(find.byKey(const Key('config-search-toggle')));
    await tester.pump();
    expect(find.byKey(const Key('config-search')), findsOneWidget);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(HomeSubsystemConfigPanel), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final width in [1280.0, 480.0]) {
    testWidgets('batch selection, close and exit work at width $width',
        (tester) async {
      await pumpHome(tester, Size(width, 800));
      final entry = find.byKey(const Key('batch-mode-toggle'));
      await tester.tap(find.text('1# 失重秤'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(HomeSubsystemConfigPanel), findsOneWidget);
      if (width == 480) {
        expect(tester.getSize(find.byType(HomeSubsystemConfigPanel)).width,
            width - 72 - 24);
        await tester.tap(find.byKey(const Key('config-search-toggle')));
        await tester.pump();
        expect(find.byKey(const Key('config-search')), findsOneWidget);
        expect(tester.takeException(), isNull);
      }

      await tester.tap(entry);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('已选 1 台设备'), findsOneWidget);
      expect(find.byTooltip('退出批量配置'), findsOneWidget);
      expect(find.byType(HomeSubsystemConfigPanel), findsNothing);
      await tester.tap(find.text('包装秤'));
      await tester.pump();
      expect(find.text('已选 2 台设备'), findsOneWidget);
      await tester.tap(find.text('开始配置'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(InputChip), findsNWidgets(2));
      expect(find.text('批量配置 · 2 台'), findsOneWidget);
      await tester.tap(find.byTooltip('关闭'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('已选 2 台设备'), findsOneWidget);
      await tester.tap(find.text('包装秤'));
      await tester.pump();
      expect(find.text('已选 1 台设备'), findsOneWidget);
      await tester.tap(entry);
      await tester.pump();
      expect(find.text('开始配置'), findsNothing);
      expect(find.byTooltip('退出批量配置'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
