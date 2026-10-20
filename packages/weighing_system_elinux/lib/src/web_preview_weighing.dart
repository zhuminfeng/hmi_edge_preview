import 'dart:async';
import 'dart:math';

import 'weighing_platform.dart';
import 'models/calibration_config.dart';
import 'models/digital_input_map.dart';
import 'models/digital_output_map.dart';
import 'models/ethercat_slave_info.dart';
import 'models/filling_config.dart';
import 'models/filter_stability_config.dart';
import 'models/liw_config.dart';
import 'models/scale_params.dart';
import 'models/silo_sequence_config.dart';
import 'models/subsystem_mapping_info.dart';
import 'models/system_status.dart';
import 'models/tare_config.dart';
import 'models/weight_data.dart';
import 'models/zero_config.dart';

/// In-memory stand-in for the eLinux weighing plugin.
/// Enough for clicking through every HMI screen in a browser.
class WebPreviewWeighingPlatform extends WeighingPlatform {
  WebPreviewWeighingPlatform() {
    _timer = Timer.periodic(const Duration(milliseconds: 200), _tick);
  }

  final _random = Random(7);
  final _weights = StreamController<WeightData>.broadcast();
  final _status = StreamController<Map<String, dynamic>>.broadcast();
  final _cal = StreamController<Map<String, dynamic>>.broadcast();
  Timer? _timer;
  int _tickCount = 0;
  bool _ready = false;
  double _masterFlow = 180;
  int _batchId = 0;
  String _inputMode = 'ethercat';

  final Map<int, ScaleParams> _scaleParams = {
    1: const ScaleParams(capacity: 30, division: 0.01),
    2: const ScaleParams(capacity: 60, division: 0.02),
    3: const ScaleParams(capacity: 15, division: 0.005),
  };
  final Map<int, ZeroConfig> _zero = {};
  final Map<int, TareConfig> _tare = {};
  final Map<int, FilterStabilityConfig> _filter = {};
  final Map<int, double> _presetTare = {1: 0, 2: 1.25, 3: 0};
  final Map<String, dynamic> _configs = {};
  final List<Map<String, dynamic>> _recipes = [
    {
      'id': 1,
      'name': 'PP-粉料',
      'appType': 0,
      'subsystemId': 1,
      'targetFlow': 120.0,
    },
    {
      'id': 2,
      'name': '25kg袋',
      'appType': 1,
      'subsystemId': 2,
      'targetWeight': 25.0,
    },
    {
      'id': 3,
      'name': 'CaCO3',
      'appType': 0,
      'subsystemId': 3,
      'targetFlow': 80.0,
    },
  ];
  int _nextRecipeId = 4;

  List<SubsystemMappingInfo> subsystems = [
    const SubsystemMappingInfo(
      subsystemId: 1,
      scaleId: 1,
      description: '1# 失重秤',
      appType: 0,
      enabled: true,
      activeRecipe: 'PP-粉料',
    ),
    const SubsystemMappingInfo(
      subsystemId: 2,
      scaleId: 2,
      description: '包装秤',
      appType: 1,
      enabled: true,
      activeRecipe: '25kg袋',
    ),
    const SubsystemMappingInfo(
      subsystemId: 3,
      scaleId: 3,
      description: '2# 失重秤',
      appType: 0,
      enabled: true,
      activeRecipe: 'CaCO3',
    ),
  ];

  final Map<int, bool> _running = {1: true, 2: true, 3: false};
  final Map<int, double> _manualRate = {1: 62, 2: 48, 3: 0};

  List<EthercatSlaveInfo> outputSlaves = [
    const EthercatSlaveInfo(
      position: 1,
      alias: 1,
      vendorId: 0x000000E4,
      productCode: 0x01010101,
      description: 'DO-16 输出模块',
      userAlias: '喂料输出',
    ),
  ];
  List<EthercatSlaveInfo> inputSlaves = [
    const EthercatSlaveInfo(
      position: 2,
      alias: 2,
      vendorId: 0x000000E4,
      productCode: 0x02020202,
      description: 'DI-16 输入模块',
      userAlias: '料位输入',
    ),
  ];
  List<EthercatSlaveInfo> scannedSlaves = [
    const EthercatSlaveInfo(
      position: 1,
      alias: 1,
      vendorId: 0x000000E4,
      productCode: 0x01010101,
      description: 'DO-16 输出模块',
      userAlias: '喂料输出',
    ),
    const EthercatSlaveInfo(
      position: 2,
      alias: 2,
      vendorId: 0x000000E4,
      productCode: 0x02020202,
      description: 'DI-16 输入模块',
      userAlias: '料位输入',
    ),
    const EthercatSlaveInfo(
      position: 3,
      alias: 0,
      vendorId: 0x000000E4,
      productCode: 0x03030303,
      description: '未配置伺服驱动',
      userAlias: '',
    ),
  ];

  DigitalOutputMapConfig _doMap = DigitalOutputMapConfig.fromMap({});
  DigitalInputMapConfig _diMap = DigitalInputMapConfig.fromMap({});

  void _tick(Timer _) {
    if (!_ready) return;
    _tickCount++;
    final now = DateTime.now().microsecondsSinceEpoch * 1000;
    for (final sub in subsystems) {
      final base = sub.appType == 1 ? 18.4 : 12.6;
      final wave = sin(_tickCount / 8 + sub.subsystemId) * (sub.appType == 1 ? 0.35 : 0.08);
      final noise = (_random.nextDouble() - 0.5) * 0.02;
      final gross = base + wave + noise + (_presetTare[sub.scaleId] ?? 0);
      final tare = _presetTare[sub.scaleId] ?? 0;
      _weights.add(WeightData(
        scaleId: sub.scaleId,
        grossWeight: gross,
        netWeight: gross - tare,
        tareWeight: tare,
        isStable: _tickCount % 15 > 2,
        isZero: false,
        isNetMode: tare > 0,
        unit: WeightUnit.kilogram,
        timestampNs: now,
      ));
    }
    _status.add({
      'tick': _tickCount,
      'ready': true,
      'preview': true,
    });
  }

  AppStatusData _statusFor(int subsystemId) {
    SubsystemMappingInfo? sub;
    for (final item in subsystems) {
      if (item.subsystemId == subsystemId) sub = item;
    }
    final running = _running[subsystemId] ?? false;
    final appType = sub?.appType ?? 0;
    final targetFlow = appType == 0 ? (subsystemId == 3 ? 80.0 : 120.0) : 0.0;
    final targetWeight = appType == 1 ? 25.0 : 0.0;
    final rate = _manualRate[subsystemId] ?? 0;
    final flow = running ? targetFlow * (0.92 + 0.06 * sin(_tickCount / 6)) : 0.0;
    return AppStatusData(
      state: running ? 2 : 0,
      appType: appType,
      liwMode: running ? 1 : 0,
      currentWeight: appType == 1 ? 18.6 + sin(_tickCount / 5) : 12.4,
      currentFlow: flow,
      controlRate: running ? rate : 0,
      targetFlow: targetFlow,
      targetWeight: targetWeight,
      accumulatedWeight: running ? 42.8 + _tickCount * 0.01 : 12.4,
      totalAccumulated: 1280 + _tickCount * 0.02,
      remainingTime: running ? 36 : 0,
      stepNumber: running ? 2 : 0,
      statusMessage: running ? '预览：运行中' : '预览：停止',
      warningMessage: '',
      warningActive: false,
    );
  }

  T _stored<T>(String key, T Function() create) {
    final existing = _configs[key];
    if (existing is T) return existing;
    final created = create();
    _configs[key] = created;
    return created;
  }

  @override
  Future<bool> initialize({
    String dbPath = '/data/weighing_system.db',
    String inputConfigPath = '/etc/weighing/input_mode.json',
  }) async {
    _ready = true;
    return true;
  }

  @override
  Future<void> shutdown() async {
    _ready = false;
  }

  @override
  Stream<WeightData> get weightStream => _weights.stream;

  @override
  Stream<Map<String, dynamic>> get statusStream => _status.stream;

  @override
  Stream<Map<String, dynamic>> get calibrationEvents => _cal.stream;

  @override
  Future<bool> updateScaleParams(int scaleId, ScaleParams params) async {
    _scaleParams[scaleId] = params;
    return true;
  }

  @override
  Future<ScaleParams> getScaleParams(int scaleId) async =>
      _scaleParams[scaleId] ?? const ScaleParams();

  @override
  Future<bool> updateZeroConfig(int scaleId, ZeroConfig config) async {
    _zero[scaleId] = config;
    return true;
  }

  @override
  Future<ZeroConfig> getZeroConfig(int scaleId) async =>
      _zero[scaleId] ?? ZeroConfig.fromMap({});

  @override
  Future<bool> updateTareConfig(int scaleId, TareConfig config) async {
    _tare[scaleId] = config;
    return true;
  }

  @override
  Future<TareConfig> getTareConfig(int scaleId) async =>
      _tare[scaleId] ?? TareConfig.fromMap({});

  @override
  Future<bool> updateFilterStability(
      int scaleId, FilterStabilityConfig config) async {
    _filter[scaleId] = config;
    return true;
  }

  @override
  Future<FilterStabilityConfig> getFilterStability(int scaleId) async =>
      _filter[scaleId] ?? FilterStabilityConfig.fromMap({});

  @override
  Future<bool> doZero(int scaleId) async {
    _presetTare[scaleId] = 0;
    _cal.add({'scaleId': scaleId, 'event': 'zero', 'ok': true});
    return true;
  }

  @override
  Future<bool> doTare(int scaleId) async {
    _presetTare[scaleId] = 1.2;
    return true;
  }

  @override
  Future<bool> clearTare(int scaleId) async {
    _presetTare[scaleId] = 0;
    return true;
  }

  @override
  Future<bool> setPresetTare(int scaleId, double value) async {
    _presetTare[scaleId] = value;
    return true;
  }

  @override
  Future<bool> triggerCalZero(int scaleId) async {
    _cal.add({'scaleId': scaleId, 'event': 'calZero', 'ok': true});
    return true;
  }

  @override
  Future<bool> triggerCalSpan(
      int scaleId, int linearMode, List<double> testLoads) async {
    _cal.add({
      'scaleId': scaleId,
      'event': 'calSpan',
      'linearMode': linearMode,
      'testLoads': testLoads,
    });
    return true;
  }

  @override
  Future<bool> triggerCalibrationAddLoad(int scaleId) async => true;

  @override
  Future<bool> triggerSaveCalibration(int scaleId) async => true;

  @override
  Future<bool> triggerAbortCalibration(int scaleId) async => true;

  @override
  Future<bool> triggerStepCalibration(int scaleId, double testWeight) async =>
      true;

  @override
  Future<bool> acceptDynamicCalibration(int scaleId, bool accept) async => true;

  @override
  Future<bool> triggerStepRemoveConfirm(int scaleId) async => true;

  @override
  Future<bool> triggerStepSubstituteConfirm(
          int scaleId, double substituteWeight) async =>
      true;

  @override
  Future<bool> updateLiwBaseConfig(int subsystemId, LiwBaseConfig config) async {
    _configs['liw-base-$subsystemId'] = config;
    return true;
  }

  @override
  Future<LiwBaseConfig> getLiwBaseConfig(int subsystemId) async =>
      _stored('liw-base-$subsystemId', () => LiwBaseConfig.fromMap({}));

  @override
  Future<bool> updateLiwSystemConfig(
      int subsystemId, LiwSystemConfig config) async {
    _configs['liw-system-$subsystemId'] = config;
    return true;
  }

  @override
  Future<LiwSystemConfig> getLiwSystemConfig(int subsystemId) async =>
      _stored('liw-system-$subsystemId', () => LiwSystemConfig.fromMap({}));

  @override
  Future<bool> updateLiwSystemIdConfig(
      int subsystemId, LiwSystemIdConfig config) async {
    _configs['liw-sysid-$subsystemId'] = config;
    return true;
  }

  @override
  Future<LiwSystemIdConfig> getLiwSystemIdConfig(int subsystemId) async =>
      _stored('liw-sysid-$subsystemId', () => LiwSystemIdConfig.fromMap({}));

  @override
  Future<bool> updateLiwControllerConfig(
      int subsystemId, LiwControllerConfig config) async {
    _configs['liw-ctrl-$subsystemId'] = config;
    return true;
  }

  @override
  Future<LiwControllerConfig> getLiwControllerConfig(int subsystemId) async =>
      _stored('liw-ctrl-$subsystemId', () => LiwControllerConfig.fromMap({}));

  @override
  Future<bool> updateLiwRefillConfig(
      int subsystemId, LiwRefillConfig config) async {
    _configs['liw-refill-$subsystemId'] = config;
    return true;
  }

  @override
  Future<LiwRefillConfig> getLiwRefillConfig(int subsystemId) async =>
      _stored('liw-refill-$subsystemId', () => LiwRefillConfig.fromMap({}));

  @override
  Future<bool> updateLiwTargetValuesConfig(
      int subsystemId, LiwTargetValuesConfig config) async {
    _configs['liw-target-$subsystemId'] = config;
    return true;
  }

  @override
  Future<LiwTargetValuesConfig> getLiwTargetValuesConfig(int subsystemId) async =>
      _stored('liw-target-$subsystemId', () => LiwTargetValuesConfig.fromMap({}));

  @override
  Future<bool> updateLiwToleranceCheckConfig(
      int subsystemId, LiwToleranceCheckConfig config) async {
    _configs['liw-tol-$subsystemId'] = config;
    return true;
  }

  @override
  Future<LiwToleranceCheckConfig> getLiwToleranceCheckConfig(
          int subsystemId) async =>
      _stored('liw-tol-$subsystemId', () => LiwToleranceCheckConfig.fromMap({}));

  @override
  Future<bool> updateLiwEmptyingConfig(
      int subsystemId, LiwEmptyingConfig config) async {
    _configs['liw-empty-$subsystemId'] = config;
    return true;
  }

  @override
  Future<LiwEmptyingConfig> getLiwEmptyingConfig(int subsystemId) async =>
      _stored('liw-empty-$subsystemId', () => LiwEmptyingConfig.fromMap({}));

  @override
  Future<bool> updateLiwWarningConfig(
      int subsystemId, LiwWarningConfig config) async {
    _configs['liw-warn-$subsystemId'] = config;
    return true;
  }

  @override
  Future<LiwWarningConfig> getLiwWarningConfig(int subsystemId) async =>
      _stored('liw-warn-$subsystemId', () => LiwWarningConfig.fromMap({}));

  @override
  Future<bool> updateLiwFlowMonitorConfig(
      int subsystemId, LiwFlowMonitorConfig config) async {
    _configs['liw-flow-$subsystemId'] = config;
    return true;
  }

  @override
  Future<LiwFlowMonitorConfig> getLiwFlowMonitorConfig(int subsystemId) async =>
      _stored('liw-flow-$subsystemId', () => LiwFlowMonitorConfig.fromMap({}));

  @override
  Future<bool> updateLiwAdvancedConfig(
      int subsystemId, LiwAdvancedConfig config) async {
    _configs['liw-adv-$subsystemId'] = config;
    return true;
  }

  @override
  Future<LiwAdvancedConfig> getLiwAdvancedConfig(int subsystemId) async =>
      _stored('liw-adv-$subsystemId', () => LiwAdvancedConfig.fromMap({}));

  @override
  Future<bool> updateLiwStatsConfig(int subsystemId, LiwStatsConfig config) async {
    _configs['liw-stats-$subsystemId'] = config;
    return true;
  }

  @override
  Future<LiwStatsConfig> getLiwStatsConfig(int subsystemId) async =>
      _stored('liw-stats-$subsystemId', () => LiwStatsConfig.fromMap({}));

  @override
  Future<bool> updateFillingGeneralConfig(
      int subsystemId, FillingGeneralConfig config) async {
    _configs['fill-gen-$subsystemId'] = config;
    return true;
  }

  @override
  Future<FillingGeneralConfig> getFillingGeneralConfig(int subsystemId) async =>
      _stored('fill-gen-$subsystemId', () => FillingGeneralConfig.fromMap({}));

  @override
  Future<bool> updateFillingSystemConfig(
      int subsystemId, FillingSystemConfig config) async {
    _configs['fill-sys-$subsystemId'] = config;
    return true;
  }

  @override
  Future<FillingSystemConfig> getFillingSystemConfig(int subsystemId) async =>
      _stored('fill-sys-$subsystemId', () => FillingSystemConfig.fromMap({}));

  @override
  Future<bool> updateFillingTargetConfig(
      int subsystemId, FillingTargetConfig config) async {
    _configs['fill-target-$subsystemId'] = config;
    return true;
  }

  @override
  Future<FillingTargetConfig> getFillingTargetConfig(int subsystemId) async =>
      _stored('fill-target-$subsystemId', () => FillingTargetConfig.fromMap({}));

  @override
  Future<bool> updateFillingAutoTareConfig(
      int subsystemId, FillingAutoTareConfig config) async {
    _configs['fill-tare-$subsystemId'] = config;
    return true;
  }

  @override
  Future<FillingAutoTareConfig> getFillingAutoTareConfig(int subsystemId) async =>
      _stored('fill-tare-$subsystemId', () => FillingAutoTareConfig.fromMap({}));

  @override
  Future<bool> updateFillingToleranceConfig(
      int subsystemId, FillingToleranceConfig config) async {
    _configs['fill-tol-$subsystemId'] = config;
    return true;
  }

  @override
  Future<FillingToleranceConfig> getFillingToleranceConfig(
          int subsystemId) async =>
      _stored('fill-tol-$subsystemId', () => FillingToleranceConfig.fromMap({}));

  @override
  Future<bool> updateFillingSpillOptConfig(
      int subsystemId, FillingSpillOptConfig config) async {
    _configs['fill-spill-$subsystemId'] = config;
    return true;
  }

  @override
  Future<FillingSpillOptConfig> getFillingSpillOptConfig(int subsystemId) async =>
      _stored('fill-spill-$subsystemId', () => FillingSpillOptConfig.fromMap({}));

  @override
  Future<bool> updateFillingCutoffOptConfig(
      int subsystemId, FillingCutoffOptConfig config) async {
    _configs['fill-cut-$subsystemId'] = config;
    return true;
  }

  @override
  Future<FillingCutoffOptConfig> getFillingCutoffOptConfig(
          int subsystemId) async =>
      _stored('fill-cut-$subsystemId', () => FillingCutoffOptConfig.fromMap({}));

  @override
  Future<bool> updateFillingJogConfig(int subsystemId, FillingJogConfig config) async {
    _configs['fill-jog-$subsystemId'] = config;
    return true;
  }

  @override
  Future<FillingJogConfig> getFillingJogConfig(int subsystemId) async =>
      _stored('fill-jog-$subsystemId', () => FillingJogConfig.fromMap({}));

  @override
  Future<bool> updateFillingRefillConfig(
      int subsystemId, FillingRefillConfig config) async {
    _configs['fill-refill-$subsystemId'] = config;
    return true;
  }

  @override
  Future<FillingRefillConfig> getFillingRefillConfig(int subsystemId) async =>
      _stored('fill-refill-$subsystemId', () => FillingRefillConfig.fromMap({}));

  @override
  Future<bool> updateFillingEmptyingConfig(
      int subsystemId, FillingEmptyingConfig config) async {
    _configs['fill-empty-$subsystemId'] = config;
    return true;
  }

  @override
  Future<FillingEmptyingConfig> getFillingEmptyingConfig(int subsystemId) async =>
      _stored('fill-empty-$subsystemId', () => FillingEmptyingConfig.fromMap({}));

  @override
  Future<bool> updateFillingEventsConfig(
      int subsystemId, FillingEventsConfig config) async {
    _configs['fill-events-$subsystemId'] = config;
    return true;
  }

  @override
  Future<FillingEventsConfig> getFillingEventsConfig(int subsystemId) async =>
      _stored('fill-events-$subsystemId', () => FillingEventsConfig.fromMap({}));

  @override
  Future<bool> updateFillingAdvancedConfig(
      int subsystemId, FillingAdvancedConfig config) async {
    _configs['fill-adv-$subsystemId'] = config;
    return true;
  }

  @override
  Future<FillingAdvancedConfig> getFillingAdvancedConfig(int subsystemId) async =>
      _stored('fill-adv-$subsystemId', () => FillingAdvancedConfig.fromMap({}));

  @override
  Future<bool> setFillingSiloSequenceConfig(
      int subsystemId, SiloSequenceConfig config) async {
    _configs['silo-$subsystemId'] = config;
    return true;
  }

  @override
  Future<SiloSequenceConfig> getFillingSiloSequenceConfig(int subsystemId) async =>
      _stored('silo-$subsystemId', () => SiloSequenceConfig.fromMap({
            'subsystemId': subsystemId,
          }));

  final Map<String, Map<String, dynamic>> _siloProcess = {};

  @override
  Future<bool> loadFillingSiloProcessConfig(int subsystemId, int siloIndex) async =>
      true;

  @override
  Future<bool> saveFillingSiloProcessConfig(
      int subsystemId, int siloIndex, Map<String, dynamic> config) async {
    _siloProcess['$subsystemId-$siloIndex'] = Map<String, dynamic>.from(config);
    return true;
  }

  @override
  Future<List<int>> getFillingSiloProcessIndices(int subsystemId) async =>
      [1, 2, 3];

  @override
  Future<bool> updateDigitalOutputMap(DigitalOutputMapConfig config) async {
    _doMap = config;
    return true;
  }

  @override
  Future<DigitalOutputMapConfig> getDigitalOutputMap() async => _doMap;

  @override
  Future<Map<String, dynamic>> validateDigitalOutputMap(
          DigitalOutputMapConfig config) async =>
      {'valid': true, 'errors': <String>[]};

  @override
  Future<bool> updateDigitalInputMap(DigitalInputMapConfig config) async {
    _diMap = config;
    return true;
  }

  @override
  Future<DigitalInputMapConfig> getDigitalInputMap() async => _diMap;

  @override
  Future<Map<String, dynamic>> validateDigitalInputMap(
          DigitalInputMapConfig config) async =>
      {'valid': true, 'errors': <String>[]};

  @override
  Future<bool> startApp(int subsystemId) async {
    _running[subsystemId] = true;
    _manualRate[subsystemId] = _manualRate[subsystemId] == 0
        ? 55
        : _manualRate[subsystemId]!;
    return true;
  }

  @override
  Future<bool> stopApp(int subsystemId) async {
    _running[subsystemId] = false;
    return true;
  }

  @override
  Future<bool> setManualControlRate(
      int subsystemId, int signalType, double ratePct) async {
    _manualRate[subsystemId] = ratePct;
    return true;
  }

  @override
  Future<AppStatusData> getAppStatus(int subsystemId) async =>
      _statusFor(subsystemId);

  @override
  Future<bool> loadRecipe(int recipeId) async =>
      _recipes.any((r) => r['id'] == recipeId);

  @override
  Future<bool> saveRecipe(Map<String, dynamic> recipe) async {
    final id = recipe['id'];
    if (id == null) {
      _recipes.add({...recipe, 'id': _nextRecipeId++});
    } else {
      final index = _recipes.indexWhere((r) => r['id'] == id);
      if (index >= 0) {
        _recipes[index] = {..._recipes[index], ...recipe};
      } else {
        _recipes.add(recipe);
      }
    }
    return true;
  }

  @override
  Future<List<Map<String, dynamic>>> getAllRecipes() async =>
      _recipes.map((r) => Map<String, dynamic>.from(r)).toList();

  @override
  Future<bool> deleteRecipe(int recipeId) async {
    _recipes.removeWhere((r) => r['id'] == recipeId);
    return true;
  }

  @override
  Future<bool> setMasterFlow(double flow) async {
    _masterFlow = flow;
    return true;
  }

  @override
  Future<double> getMasterFlow() async => _masterFlow;

  @override
  Future<double> getTotalActualFlow() async {
    var total = 0.0;
    for (final sub in subsystems) {
      if (_running[sub.subsystemId] == true && sub.appType == 0) {
        total += _statusFor(sub.subsystemId).currentFlow;
      }
    }
    return total;
  }

  @override
  Future<Map<String, dynamic>?> getSubsystemStatus(int subsystemId) async {
    final status = _statusFor(subsystemId);
    return {
      'subsystemId': subsystemId,
      'state': status.state,
      'currentFlow': status.currentFlow,
      'currentWeight': status.currentWeight,
      'controlRate': status.controlRate,
    };
  }

  @override
  Future<Map<int, Map<String, dynamic>>> getAllSubsystemStatuses() async {
    final out = <int, Map<String, dynamic>>{};
    for (final sub in subsystems) {
      out[sub.subsystemId] = (await getSubsystemStatus(sub.subsystemId))!;
    }
    return out;
  }

  @override
  Future<int> startBatch(String operatorName) async {
    _batchId += 1;
    return _batchId;
  }

  @override
  Future<bool> endBatch() async => true;

  @override
  Future<int> getCurrentBatchId() async => _batchId;

  @override
  Future<List<EthercatSlaveInfo>> scanEthercatSlaves() async => scannedSlaves;

  @override
  Future<String> getInputMode() async => _inputMode;

  @override
  Future<List<SubsystemMappingInfo>> getSubsystemMappings() async =>
      List<SubsystemMappingInfo>.from(subsystems);

  @override
  Future<bool> updateSubsystemMapping(int subsystemId, int scaleId) async {
    subsystems = [
      for (final sub in subsystems)
        if (sub.subsystemId == subsystemId) sub.copyWith(scaleId: scaleId) else sub,
    ];
    return true;
  }

  @override
  Future<bool> updateSlaveAlias(int position, String alias) async {
    EthercatSlaveInfo rewrite(EthercatSlaveInfo s) => s.position == position
        ? s.copyWith(userAlias: alias)
        : s;
    outputSlaves = outputSlaves.map(rewrite).toList();
    inputSlaves = inputSlaves.map(rewrite).toList();
    scannedSlaves = scannedSlaves.map(rewrite).toList();
    return true;
  }

  @override
  Future<bool> addSubsystemMapping(int subsystemId, String description,
      {int scaleId = 0, int ioPosition = 0, int appType = 0}) async {
    subsystems = [
      ...subsystems.where((s) => s.subsystemId != subsystemId),
      SubsystemMappingInfo(
        subsystemId: subsystemId,
        scaleId: scaleId,
        description: description,
        appType: appType,
        enabled: true,
      ),
    ];
    return true;
  }

  @override
  Future<bool> setSubsystemAppType(int subsystemId, int appType) async {
    subsystems = [
      for (final sub in subsystems)
        if (sub.subsystemId == subsystemId)
          sub.copyWith(appType: appType)
        else
          sub,
    ];
    return true;
  }

  @override
  Future<bool> setSubsystemEnabled(int subsystemId, bool enabled) async {
    subsystems = [
      for (final sub in subsystems)
        if (sub.subsystemId == subsystemId)
          sub.copyWith(enabled: enabled)
        else
          sub,
    ];
    return true;
  }

  @override
  Future<bool> removeSubsystemMapping(int subsystemId) async {
    subsystems = subsystems.where((s) => s.subsystemId != subsystemId).toList();
    return true;
  }

  @override
  Future<Map<String, dynamic>> getConfigStatus() async => {
        'subsystem_count': subsystems.length,
        'input_mode': _inputMode,
        'preview': true,
        'hardware_ready': true,
      };

  @override
  Future<bool> saveEthercatHardwareConfig(List<EthercatSlaveInfo> output,
      List<EthercatSlaveInfo> input) async {
    outputSlaves = output;
    inputSlaves = input;
    return true;
  }

  @override
  Future<Map<String, List<EthercatSlaveInfo>>> getEthercatHardwareConfig() async =>
      {
        'outputSlaves': outputSlaves,
        'inputSlaves': inputSlaves,
      };

  @override
  Future<bool> saveMaterialRecipe(
      int subsystemId, String name, int appType) async {
    _recipes.add({
      'id': _nextRecipeId++,
      'name': name,
      'appType': appType,
      'subsystemId': subsystemId,
    });
    return true;
  }

  @override
  Future<bool> loadMaterialRecipe(
      int subsystemId, int recipeId, String recipeName, int appType) async {
    subsystems = [
      for (final sub in subsystems)
        if (sub.subsystemId == subsystemId)
          sub.copyWith(activeRecipe: recipeName, appType: appType)
        else
          sub,
    ];
    return true;
  }

  @override
  Future<List<Map<String, dynamic>>> getAllMaterialRecipes(int appType) async =>
      _recipes.where((r) => r['appType'] == appType).map(Map<String, dynamic>.from).toList();

  @override
  Future<bool> deleteMaterialRecipe(int recipeId, int appType) async {
    _recipes.removeWhere((r) => r['id'] == recipeId && r['appType'] == appType);
    return true;
  }

  @override
  Future<bool> setSubsystemActiveRecipe(int subsystemId, String recipeName) async {
    subsystems = [
      for (final sub in subsystems)
        if (sub.subsystemId == subsystemId)
          sub.copyWith(activeRecipe: recipeName)
        else
          sub,
    ];
    return true;
  }

  Future<void> dispose() async {
    _timer?.cancel();
    await _weights.close();
    await _status.close();
    await _cal.close();
  }
}

void registerWebPreviewPlatform() {
  WeighingPlatform.instance = WebPreviewWeighingPlatform();
}
