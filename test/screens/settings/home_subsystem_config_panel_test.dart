import 'dart:async';

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

  testWidgets('search expands with focus and clearing or closing restores rows',
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

    final search = find.byKey(const Key('config-search'));
    final toggle = find.byKey(const Key('config-search-toggle'));
    expect(search, findsNothing);
    expect(find.byTooltip('搜索参数'), findsOneWidget);
    await tester.tap(find.text('称重'));
    await tester.pump();
    final capacity = find.byType(TextFormField).first;
    await tester.enterText(capacity, '123.45');
    await tester.pump();
    final editable = tester.widget<EditableText>(
      find.descendant(of: capacity, matching: find.byType(EditableText)),
    );
    final controller = editable.controller;
    final content = find.byKey(const ValueKey('1-0'));
    final collapsedHeight = tester.getSize(content).height;

    await tester.tap(toggle);
    await tester.pump();
    await tester.pump();
    expect(search, findsOneWidget);
    expect(tester.widget<TextField>(search).focusNode!.hasFocus, isTrue);
    expect(tester.getSize(content).height, lessThan(collapsedHeight));

    await tester.enterText(search, '自动零');
    await tester.pump();
    expect(find.text('量程'), findsNothing);
    expect(find.text('自动零跟踪'), findsOneWidget);
    await tester.tap(find.byTooltip('清除搜索'));
    await tester.pump();
    expect(find.text('量程'), findsOneWidget);
    expect(tester.widget<TextField>(search).controller!.text, isEmpty);
    expect(controller.text, '123.45');

    // Preserve even an incomplete numeric edit while its row is filtered out.
    await tester.enterText(capacity, '-');
    await tester.enterText(search, '不存在的参数');
    await tester.pump();
    expect(find.text('量程'), findsNothing);
    await tester.tap(toggle);
    await tester.pump();
    expect(search, findsNothing);
    expect(find.text('量程'), findsOneWidget);
    expect(controller.text, '-');
    expect(tester.getSize(content).height, collapsedHeight);
    await tester.enterText(capacity, '123.45');
    await tester.tap(find.byKey(const Key('panel-save')));
    await tester.pump(const Duration(milliseconds: 400));
    expect((await platform.getScaleParams(1)).capacity, 123.45);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    appState.dispose();
  });

  testWidgets('category and subsystem switches clear search without hidden filters',
      (tester) async {
    final appState = AppState();
    await tester.pumpWidget(_switchingTestApp(appState, _RouteObserver()));
    await tester.pump(const Duration(milliseconds: 400));
    final search = find.byKey(const Key('config-search'));
    final toggle = find.byKey(const Key('config-search-toggle'));

    await tester.tap(toggle);
    await tester.pump();
    await tester.enterText(search, '不存在的参数');
    await tester.tap(find.text('称重'));
    await tester.pump();
    expect(search, findsNothing);
    expect(find.text('量程'), findsOneWidget);
    await tester.tap(toggle);
    await tester.pump();
    expect(tester.widget<TextField>(search).controller!.text, isEmpty);

    await tester.enterText(search, '不存在的参数');
    await tester.tap(find.byKey(const Key('switch-subsystem')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(search, findsNothing);
    await tester.tap(find.text('称重'));
    await tester.pump();
    expect(find.text('量程'), findsOneWidget);
    await tester.tap(toggle);
    await tester.pump();
    expect(tester.widget<TextField>(search).controller!.text, isEmpty);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    appState.dispose();
  });

  testWidgets('expanded search fits a narrow panel', (tester) async {
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
      width: 320,
    ));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('config-search-toggle')));
    await tester.pump();
    await tester.enterText(
        find.byKey(const Key('config-search')), 'a very long parameter query');
    await tester.pump();
    expect(tester.getSize(find.byKey(const Key('config-search'))).width,
        lessThan(320));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    appState.dispose();
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
    expect(find.text('零点跟踪 / 零点配置'), findsNothing);
    await tester.tap(find.byKey(const Key('group-nav-scale-zero')));
    await tester.pump();
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

  testWidgets('group navigation switches directly to editable parameters',
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

    await tester.tap(find.text('称重'));
    await tester.pump();
    expect(find.text('量程'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, '123.45');
    await tester.pump();

    await tester.tap(find.byKey(const Key('group-nav-scale-zero')));
    await tester.pump();
    expect(find.text('量程'), findsNothing);
    expect(find.text('自动零跟踪'), findsOneWidget);
    expect(find.text('当前分组 2/4 · 零点配置'), findsOneWidget);

    await tester.tap(find.byKey(const Key('group-nav-scale-base')));
    await tester.pump();
    final capacityField = find.descendant(
      of: find.byType(TextFormField).first,
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(capacityField).controller.text, '123.45');

    await tester.tap(find.text('滤波'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('group-nav-filter-notch')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('config-search-toggle')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('config-search')), '频率');
    await tester.pump();
    expect(find.text('频率 (Hz)'), findsOneWidget);
    expect(find.text('当前分组 2/4 · 陷波滤波'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('config-search')), '');
    await tester.pump();
    await tester.tap(find.text('配方'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('group-nav-liw-system')));
    await tester.pump();
    expect(find.text('安全限制'), findsOneWidget);
    expect(find.text('当前子系统配方'), findsOneWidget);
    expect(tester.takeException(), isNull);

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

  testWidgets('span calibration uses its own unit and waits for final result',
      (tester) async {
    final originalPlatform = platform;
    final calibrationPlatform = _CalibrationTestPlatform();
    WeighingPlatform.instance = calibrationPlatform;
    await calibrationPlatform.initialize();
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
    await tester.tap(find.text('称重'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('group-nav-scale-calibration')));
    await tester.pump();

    final unitField = tester.widget<DropdownButtonFormField<int>>(
      find.byKey(const Key('calibration-unit')),
    );
    unitField.onChanged!(2);
    final linearField = tester.widget<DropdownButtonFormField<int>>(
      find.byKey(const Key('calibration-linear-mode')),
    );
    linearField.onChanged!(1);
    await tester.pump();
    expect(find.text('第 1 点砝码重量（lb）'), findsOneWidget);
    expect(find.text('砝码标定单位'), findsOneWidget);
    calibrationPlatform.emitWeight(const WeightData(
      scaleId: 1,
      grossWeight: 1,
      isStable: true,
      unit: WeightUnit.kilogram,
    ));
    await tester.pump();
    expect(find.text('2.20 lb'), findsOneWidget);
    expect(find.text('实时毛重  稳定'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('calibration-start-span')));
    await tester.ensureVisible(
      find.byKey(const Key('calibration-span-load-1')),
    );
    await tester.enterText(
      find.byKey(const Key('calibration-span-load-1')),
      '0',
    );
    await tester.tap(find.byKey(const Key('calibration-start-span')));
    await tester.pump();
    expect(calibrationPlatform.spanLoads, isNull);
    await tester.enterText(
      find.byKey(const Key('calibration-span-load-1')),
      '1',
    );
    await tester.tap(find.byKey(const Key('calibration-start-span')));
    await tester.pump();
    expect(calibrationPlatform.spanLinearMode, 1);
    expect(calibrationPlatform.spanLoads, [1.0, 1.0]);
    expect(
      tester.widget<TextButton>(find.byKey(const Key('panel-save'))).onPressed,
      isNull,
    );
    expect(find.byKey(const Key('calibration-save')), findsNothing);

    calibrationPlatform.emitCalibrationState(1, 6);
    await tester.pump();
    expect(find.byKey(const Key('calibration-add-load')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('calibration-add-load')));
    await tester.tap(find.byKey(const Key('calibration-add-load')));
    await tester.pump();
    expect(calibrationPlatform.addLoadCount, 1);

    calibrationPlatform.emitCalibrationState(1, 2);
    await tester.pump();
    expect(find.byKey(const Key('calibration-save')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('calibration-save')));
    await tester.tap(find.byKey(const Key('calibration-save')));
    await tester.pump();
    expect(calibrationPlatform.saveCount, 1);
    expect(
      tester.widget<TextButton>(find.byKey(const Key('panel-save'))).onPressed,
      isNotNull,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    appState.dispose();
    await calibrationPlatform.shutdown();
    WeighingPlatform.instance = originalPlatform;
  });

  testWidgets('step calibration confirms removal and substitute before adding',
      (tester) async {
    final originalPlatform = platform;
    final calibrationPlatform = _CalibrationTestPlatform();
    WeighingPlatform.instance = calibrationPlatform;
    await calibrationPlatform.initialize();
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
    await tester.tap(find.text('称重'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('group-nav-scale-calibration')));
    await tester.pump();

    await tester.ensureVisible(find.byKey(const Key('calibration-start-step')));
    await tester.tap(find.byKey(const Key('calibration-start-step')));
    await tester.pump();
    expect(calibrationPlatform.stepWeight, 1);

    calibrationPlatform.emitCalibrationState(1, 2);
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const Key('calibration-prepare-remove')),
    );
    await tester.tap(find.byKey(const Key('calibration-prepare-remove')));
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const Key('calibration-remove-confirm')),
    );
    await tester.tap(find.byKey(const Key('calibration-remove-confirm')));
    await tester.pump();
    expect(calibrationPlatform.removeConfirmCount, 1);
    await tester.ensureVisible(
      find.byKey(const Key('calibration-substitute-confirm')),
    );
    await tester.tap(find.byKey(const Key('calibration-substitute-confirm')));
    await tester.pump();
    expect(calibrationPlatform.substituteWeight, 1);
    await tester.ensureVisible(find.byKey(const Key('calibration-add-load')));
    calibrationPlatform.addLoadResult = false;
    await tester.tap(find.byKey(const Key('calibration-add-load')));
    await tester.pump();
    expect(calibrationPlatform.addLoadCount, 1);
    expect(find.byKey(const Key('calibration-add-load')), findsOneWidget);
    calibrationPlatform.addLoadResult = true;
    await tester.ensureVisible(find.byKey(const Key('calibration-add-load')));
    await tester.tap(find.byKey(const Key('calibration-add-load')));
    await tester.pump();
    expect(calibrationPlatform.addLoadCount, 2);

    await tester.pumpWidget(const SizedBox.shrink());
    appState.dispose();
    await calibrationPlatform.shutdown();
    WeighingPlatform.instance = originalPlatform;
  });

  testWidgets('zero calibration requires a dynamic-result decision before save',
      (tester) async {
    final originalPlatform = platform;
    final calibrationPlatform = _CalibrationTestPlatform();
    WeighingPlatform.instance = calibrationPlatform;
    await calibrationPlatform.initialize();
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
    await tester.tap(find.text('称重'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('group-nav-scale-calibration')));
    await tester.pump();

    await tester.ensureVisible(find.byKey(const Key('calibration-start-zero')));
    await tester.tap(find.byKey(const Key('calibration-start-zero')));
    await tester.pump();
    expect(calibrationPlatform.zeroCount, 1);
    calibrationPlatform.emitCalibrationState(1, 3);
    await tester.pump();
    expect(find.text('接受动态校正'), findsOneWidget);
    expect(find.byKey(const Key('calibration-save')), findsNothing);

    await tester.ensureVisible(find.text('接受动态校正'));
    await tester.tap(find.text('接受动态校正'));
    await tester.pump();
    expect(find.byKey(const Key('calibration-save')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('calibration-save')));
    await tester.tap(find.byKey(const Key('calibration-save')));
    await tester.pump();
    expect(calibrationPlatform.acceptDynamicCount, 1);
    expect(calibrationPlatform.saveCount, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    appState.dispose();
    await calibrationPlatform.shutdown();
    WeighingPlatform.instance = originalPlatform;
  });
}

Widget _testApp(
  AppState appState,
  NavigatorObserver observer,
  SubsystemMappingInfo mapping, {
  double width = 620,
}) {
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
            width: width,
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

class _CalibrationTestPlatform extends WebPreviewWeighingPlatform {
  final StreamController<Map<String, dynamic>> _calibrationController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<WeightData> _weightController =
      StreamController<WeightData>.broadcast();
  int? spanLinearMode;
  List<double>? spanLoads;
  double? stepWeight;
  double? substituteWeight;
  int addLoadCount = 0;
  int removeConfirmCount = 0;
  int saveCount = 0;
  int zeroCount = 0;
  int acceptDynamicCount = 0;
  bool addLoadResult = true;

  @override
  Stream<Map<String, dynamic>> get calibrationEvents =>
      _calibrationController.stream;

  @override
  Stream<WeightData> get weightStream => _weightController.stream;

  void emitWeight(WeightData weight) {
    _weightController.add(weight);
  }

  void emitCalibrationState(int scaleId, int state) {
    _calibrationController.add({
      'scaleId': scaleId,
      'state': state,
      'message': '',
    });
  }

  @override
  Future<bool> triggerCalZero(int scaleId) async {
    zeroCount++;
    return true;
  }

  @override
  Future<bool> triggerCalSpan(
    int scaleId,
    int linearMode,
    List<double> testLoads,
  ) async {
    spanLinearMode = linearMode;
    spanLoads = testLoads;
    return true;
  }

  @override
  Future<bool> triggerStepCalibration(int scaleId, double testWeight) async {
    stepWeight = testWeight;
    return true;
  }

  @override
  Future<bool> triggerCalibrationAddLoad(int scaleId) async {
    addLoadCount++;
    return addLoadResult;
  }

  @override
  Future<bool> triggerStepRemoveConfirm(int scaleId) async {
    removeConfirmCount++;
    return true;
  }

  @override
  Future<bool> triggerStepSubstituteConfirm(
    int scaleId,
    double substituteWeight,
  ) async {
    this.substituteWeight = substituteWeight;
    return true;
  }

  @override
  Future<bool> triggerSaveCalibration(int scaleId) async {
    saveCount++;
    return true;
  }

  @override
  Future<bool> acceptDynamicCalibration(int scaleId, bool accept) async {
    acceptDynamicCount++;
    return true;
  }

  @override
  Future<void> shutdown() async {
    await _calibrationController.close();
    await _weightController.close();
    await super.shutdown();
  }
}
