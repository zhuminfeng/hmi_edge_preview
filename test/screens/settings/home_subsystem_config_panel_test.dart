import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weighing_system_elinux/weighing_system_elinux.dart';

import 'package:hmi_edge_preview/l10n/app_localizations.dart';
import 'package:hmi_edge_preview/providers/app_state.dart';
import 'package:hmi_edge_preview/screens/settings/home_subsystem_config_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late WebPreviewWeighingPlatform platform;
  setUpAll(() {
    registerWebPreviewPlatform();
    platform = WeighingPlatform.instance as WebPreviewWeighingPlatform;
  });
  tearDownAll(() async {
    await platform.shutdown();
  });

  testWidgets('configuration categories edit parameters without pushing routes',
      (tester) async {
    final appState = AppState();
    final observer = _RouteObserver();
    await tester.pumpWidget(_testApp(
      appState,
      observer,
      const SubsystemMappingInfo(
        subsystemId: 1,
        scaleId: 1,
        description: '1# 失重秤',
        appType: 0,
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    observer.pushes = 0;

    await tester.tap(find.text('称重'));
    await tester.pump();
    expect(find.text('量程'), findsOneWidget);
    expect(find.text('零点跟踪 / 零点配置'), findsOneWidget);

    await tester.tap(find.text('配方'));
    await tester.pump();
    expect(find.text('当前子系统配方'), findsOneWidget);
    expect(find.text('安全限制'), findsOneWidget);

    await tester.tap(find.text('硬件'));
    await tester.pump();
    expect(find.text('离散输入配置'), findsOneWidget);
    expect(find.text('数字输出映射'), findsOneWidget);
    expect(observer.pushes, 0);

    appState.dispose();
  });

  testWidgets('changing application type loads filling process inline',
      (tester) async {
    final appState = AppState();
    await tester.pumpWidget(_testApp(
      appState,
      _RouteObserver(),
      const SubsystemMappingInfo(
        subsystemId: 1,
        scaleId: 1,
        description: '1# 失重秤',
        appType: 0,
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('罐装/分装应用').first);
    await tester.pump();
    await tester.tap(find.text('罐装/分装应用').last);
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('配方'));
    await tester.pump();
    expect(find.text('工作模式'), findsOneWidget);
    expect(find.text('安全限制'), findsNothing);

    await tester.tap(find.text('工艺'));
    await tester.pump();
    expect(find.text('料仓配置'), findsOneWidget);
    expect(find.text('料仓顺序'), findsOneWidget);
    expect(find.text('添加料仓'), findsOneWidget);

    appState.dispose();
  });

  testWidgets('switching subsystem updates the scale identity in the panel',
      (tester) async {
    final appState = AppState();
    final observer = _RouteObserver();
    await tester.pumpWidget(_switchingTestApp(appState, observer));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('称重'));
    await tester.pump();
    expect(find.text('Scale 1'), findsOneWidget);
    await tester.tap(find.byKey(const Key('switch-subsystem')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('基本'));
    await tester.pump();
    expect(find.text('Scale 2'), findsOneWidget);
    expect(observer.pushes, 0);
    appState.dispose();
  });
}

Widget _testApp(
  AppState appState,
  NavigatorObserver observer,
  SubsystemMappingInfo mapping,
) {
  return AppStateProvider(
    notifier: appState,
    onLocaleChange: (_) {},
    child: MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      navigatorObservers: [observer],
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 620,
            height: 560,
            child: HomeSubsystemConfigPanel(mapping: mapping),
          ),
        ),
      ),
    ),
  );
}

Widget _switchingTestApp(AppState appState, NavigatorObserver observer) {
  return AppStateProvider(
    notifier: appState,
    onLocaleChange: (_) {},
    child: MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      navigatorObservers: [observer],
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 620,
            height: 560,
            child: const _SwitchingPanel(),
          ),
        ),
      ),
    ),
  );
}

class _SwitchingPanel extends StatefulWidget {
  const _SwitchingPanel();

  @override
  State<_SwitchingPanel> createState() => _SwitchingPanelState();
}

class _SwitchingPanelState extends State<_SwitchingPanel> {
  var mapping = const SubsystemMappingInfo(
    subsystemId: 1,
    scaleId: 1,
    description: '1# 失重秤',
    appType: 0,
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextButton(
          key: const Key('switch-subsystem'),
          onPressed: () => setState(() {
            mapping = const SubsystemMappingInfo(
              subsystemId: 2,
              scaleId: 2,
              description: '包装秤',
              appType: 1,
            );
          }),
          child: const Text('切换子系统'),
        ),
        Expanded(child: HomeSubsystemConfigPanel(mapping: mapping)),
      ],
    );
  }
}

class _RouteObserver extends NavigatorObserver {
  int pushes = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
    super.didPush(route, previousRoute);
  }
}
