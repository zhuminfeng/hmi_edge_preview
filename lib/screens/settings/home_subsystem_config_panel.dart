import 'dart:async';

import 'package:flutter/material.dart';
import 'package:weighing_system_elinux/weighing_system_elinux.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/app_state.dart';
import 'digital_input_settings_screen.dart'
    show getDigitalInputSignalTypeName;
import 'digital_output_settings_screen.dart' show getDigitalSignalTypeName;
import 'subsystem_config_screen.dart' show detectSlaveRole, SlaveRole;

enum _PanelCalibrationType { none, zero, span, step }

enum _PanelStepPhase {
  idle,
  weightLoaded,
  removeWaiting,
  substituteWaiting,
  nextLoad,
}

/// 首页内嵌配置面板。
/// Tab 按 subsystem_detail_config_screen 分类：基本 / 称重 / 滤波 / 配方 / 硬件 / 工艺。
/// 每个 Tab 内用「子分类信息条 + 参数行列表」组织（对齐 SVG 风格）。
class HomeSubsystemConfigPanel extends StatefulWidget {
  const HomeSubsystemConfigPanel({
    super.key,
    required this.mapping,
    this.onOpenDashboard,
    this.onClose,
  });

  final SubsystemMappingInfo mapping;
  final VoidCallback? onOpenDashboard;
  final VoidCallback? onClose;

  @override
  State<HomeSubsystemConfigPanel> createState() =>
      _HomeSubsystemConfigPanelState();
}

class _HomeSubsystemConfigPanelState extends State<HomeSubsystemConfigPanel> {
  final _platform = WeighingPlatform.instance;

  int _section = 0;
  int _loadGeneration = 0;
  int _siloProcessGeneration = 0;
  int _valueRevision = 0;
  String? _activeGroupKey;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String _searchQuery = '';

  late TextEditingController _name;
  late int _appType;
  late bool _enabled;
  String _inputMode = 'shmem';
  List<EthercatSlaveInfo> _ioSlaves = [];
  DigitalInputMapConfig _digitalInputs = const DigitalInputMapConfig();
  DigitalOutputMapConfig _digitalOutputs = const DigitalOutputMapConfig();
  bool _ioLoading = true;
  bool _ioSaving = false;
  String? _ioError;
  List<int> _siloIndices = [];
  int? _selectedSiloIndex;
  SiloSequenceConfig _siloSequence =
      const SiloSequenceConfig(subsystemId: 0);
  bool _siloSequenceLoading = true;
  bool _siloSequenceSaving = false;
  String? _siloError;
  bool _siloEditMode = false;
  bool _calibrationBusy = false;
  StreamSubscription<WeightData>? _weightSubscription;
  StreamSubscription<Map<String, dynamic>>? _calibrationSubscription;
  double _liveWeight = 0;
  WeightUnit _liveWeightUnit = WeightUnit.kilogram;
  bool _isWeightStable = false;
  String? _calibrationStatus;
  final List<TextEditingController> _spanLoads =
      List.generate(4, (_) => TextEditingController(text: '1'));
  final TextEditingController _stepLoad = TextEditingController(text: '1');
  int _linearMode = 0;
  int _calibrationState = 0;
  int _completedSpanSteps = 0;
  bool _spanWaitingHandled = false;
  bool _calibrationComplete = false;
  bool _dynamicCalibrationAccepted = false;
  _PanelCalibrationType _activeCalibration = _PanelCalibrationType.none;
  _PanelStepPhase _stepPhase = _PanelStepPhase.idle;
  int _calibrationGeneration = 0;
  int _streamGeneration = 0;

  ScaleParams _scale = const ScaleParams();
  ZeroConfig _zero = const ZeroConfig();
  TareConfig _tare = const TareConfig();
  FilterStabilityConfig _filter = const FilterStabilityConfig();

  LiwBaseConfig _liwBase = const LiwBaseConfig();
  LiwSystemConfig _liwSystem = const LiwSystemConfig();
  LiwSystemIdConfig _liwSysId = const LiwSystemIdConfig();
  LiwControllerConfig _liwCtrl = const LiwControllerConfig();
  LiwRefillConfig _liwRefill = const LiwRefillConfig();
  LiwTargetValuesConfig _liwTarget = const LiwTargetValuesConfig();
  LiwToleranceCheckConfig _liwTol = const LiwToleranceCheckConfig();
  LiwEmptyingConfig _liwEmpty = const LiwEmptyingConfig();
  LiwWarningConfig _liwWarn = const LiwWarningConfig();
  LiwFlowMonitorConfig _liwFlow = const LiwFlowMonitorConfig();
  LiwAdvancedConfig _liwAdv = const LiwAdvancedConfig();
  LiwStatsConfig _liwStats = const LiwStatsConfig();

  FillingGeneralConfig _fillGen = const FillingGeneralConfig();
  FillingSystemConfig _fillSys = const FillingSystemConfig();
  FillingTargetConfig _fillTarget = const FillingTargetConfig();
  FillingAutoTareConfig _fillAutoTare = const FillingAutoTareConfig();
  FillingToleranceConfig _fillTol = const FillingToleranceConfig();
  FillingSpillOptConfig _fillSpill = const FillingSpillOptConfig();
  FillingCutoffOptConfig _fillCutoff = const FillingCutoffOptConfig();
  FillingJogConfig _fillJog = const FillingJogConfig();
  FillingRefillConfig _fillRefill = const FillingRefillConfig();
  FillingEmptyingConfig _fillEmpty = const FillingEmptyingConfig();
  FillingEventsConfig _fillEvents = const FillingEventsConfig();
  FillingAdvancedConfig _fillAdv = const FillingAdvancedConfig();

  List<Map<String, dynamic>> _recipes = [];
  bool _recipesLoading = false;
  String? _recipesError;

  // 记录已折叠的子分类（key = groupKey）
  final Set<String> _collapsedGroups = <String>{};

  @override
  void initState() {
    super.initState();
    _collapsedGroups.add('recipe-library');
    _name = TextEditingController(text: widget.mapping.description);
    _appType = widget.mapping.appType;
    _enabled = widget.mapping.enabled;
    _load();
    _loadRecipes();
    _loadHardware();
    _loadSiloSequence();
    _subscribeScaleStreams();
  }

  void _subscribeScaleStreams() {
    final generation = ++_streamGeneration;
    _weightSubscription?.cancel();
    _calibrationSubscription?.cancel();
    _weightSubscription = _platform.weightStream.listen((data) {
      if (generation != _streamGeneration) return;
      if (!mounted || data.scaleId != widget.mapping.scaleId) return;
      setState(() {
        _liveWeight = data.grossWeight;
        _liveWeightUnit = data.unit;
        _isWeightStable = data.isStable;
      });
    });
    _calibrationSubscription = _platform.calibrationEvents.listen((event) {
      if (generation != _streamGeneration ||
          !mounted ||
          event['scaleId'] != widget.mapping.scaleId ||
          _activeCalibration == _PanelCalibrationType.none) {
        return;
      }
      final state = event['state'];
      if (state is! int) return;
      _handleCalibrationEvent(state, event['message'] as String? ?? '');
    });
  }

  @override
  void didUpdateWidget(covariant HomeSubsystemConfigPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mapping.subsystemId != widget.mapping.subsystemId ||
        oldWidget.mapping.scaleId != widget.mapping.scaleId ||
        oldWidget.mapping.appType != widget.mapping.appType) {
      _resetCalibration();
      _liveWeight = 0;
      _isWeightStable = false;
      _subscribeScaleStreams();
      if (oldWidget.mapping.subsystemId == widget.mapping.subsystemId &&
          oldWidget.mapping.appType != widget.mapping.appType) {
        AppStateProvider.read(context)
            .setActiveRecipeName(widget.mapping.subsystemId, null);
      }
      _name.text = widget.mapping.description;
      _appType = widget.mapping.appType;
      _enabled = widget.mapping.enabled;
      _saving = false;
      _section = 0;
      _siloSequenceSaving = false;
      _collapsedGroups.clear();
      _collapsedGroups.add('recipe-library');
      _load();
      _loadRecipes();
      _loadHardware();
      _loadSiloSequence();
    }
  }

  @override
  void dispose() {
    _name.dispose();
    for (final controller in _spanLoads) {
      controller.dispose();
    }
    _stepLoad.dispose();
    _weightSubscription?.cancel();
    _calibrationSubscription?.cancel();
    super.dispose();
  }

  // ── 数据加载 / 保存 ─────────────────────────────────────────────

  Future<void> _loadRecipes() async {
    final subsystemId = widget.mapping.subsystemId;
    final appType = _appType;
    setState(() {
      _recipesLoading = true;
      _recipesError = null;
      _recipes = [];
    });
    try {
      final all =
          await AppStateProvider.read(context).getAllMaterialRecipes(appType);
      if (!mounted ||
          widget.mapping.subsystemId != subsystemId ||
          _appType != appType) return;
      setState(() {
        _recipes = all.where((recipe) {
          final value = recipe['subsystemId'];
          return value is int
              ? value == subsystemId
              : int.tryParse('$value') == subsystemId;
        }).toList();
        _recipesLoading = false;
      });
    } catch (error) {
      if (!mounted ||
          widget.mapping.subsystemId != subsystemId ||
          _appType != appType) return;
      setState(() {
        _recipesError = '$error';
        _recipesLoading = false;
      });
    }
  }

  Future<void> _loadHardware() async {
    final subsystemId = widget.mapping.subsystemId;
    setState(() {
      _ioLoading = true;
      _ioError = null;
    });
    try {
      final values = await Future.wait<Object>([
        _platform.getDigitalInputMap(),
        _platform.getDigitalOutputMap(),
        _platform.scanEthercatSlaves(),
      ]);
      if (!mounted || widget.mapping.subsystemId != subsystemId) return;
      setState(() {
        _digitalInputs = values[0] as DigitalInputMapConfig;
        _digitalOutputs = values[1] as DigitalOutputMapConfig;
        _ioSlaves = values[2] as List<EthercatSlaveInfo>;
        _ioLoading = false;
      });
    } catch (error) {
      if (!mounted || widget.mapping.subsystemId != subsystemId) return;
      setState(() {
        _ioLoading = false;
        _ioError = '$error';
      });
    }
  }

  Future<void> _loadSiloSequence() async {
    final subsystemId = widget.mapping.subsystemId;
    if (_appType != 1) {
      setState(() {
        _siloSequenceLoading = false;
        _siloError = null;
        _siloIndices = [];
        _selectedSiloIndex = null;
        _siloEditMode = false;
      });
      return;
    }
    setState(() {
      _siloSequenceLoading = true;
      _siloError = null;
      _siloIndices = [];
      _selectedSiloIndex = null;
      _siloEditMode = false;
    });
    try {
      final results = await Future.wait<Object>([
        _platform.getFillingSiloProcessIndices(subsystemId),
        _platform.getFillingSiloSequenceConfig(subsystemId),
      ]);
      if (!mounted || widget.mapping.subsystemId != subsystemId) return;
      final indices = results[0] as List<int>;
      final loadedSequence = results[1] as SiloSequenceConfig;
      setState(() {
        _siloIndices = indices;
        _selectedSiloIndex = indices.isEmpty ? null : indices.first;
        _siloSequence = SiloSequenceConfig(
          subsystemId: subsystemId,
          enabled: loadedSequence.enabled,
          steps: List<SiloStep>.from(loadedSequence.steps)
            ..sort((a, b) => a.order.compareTo(b.order)),
        );
        _siloSequenceLoading = false;
      });
    } catch (error) {
      if (!mounted || widget.mapping.subsystemId != subsystemId) return;
      setState(() {
        _siloSequenceLoading = false;
        _siloError = '$error';
      });
    }
  }

  Future<void> _changeAppType(int appType) async {
    if (appType == _appType || _saving) return;
    setState(() {
      _appType = appType;
      _siloEditMode = false;
      _siloSequenceSaving = false;
      _section = 0;
    });
    await Future.wait([
      _load(),
      _loadRecipes(),
      if (appType == 1) _loadSiloSequence(),
    ]);
  }

  Future<void> _loadSiloProcess(int siloIndex) async {
    final generation = ++_siloProcessGeneration;
    final subsystemId = widget.mapping.subsystemId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final loaded = await _platform.loadFillingSiloProcessConfig(
        subsystemId,
        siloIndex,
      );
      if (!loaded) throw StateError('料仓 $siloIndex 参数加载失败');
      final values = await Future.wait<Object>([
        _platform.getFillingTargetConfig(subsystemId),
        _platform.getFillingAutoTareConfig(subsystemId),
        _platform.getFillingToleranceConfig(subsystemId),
        _platform.getFillingSpillOptConfig(subsystemId),
        _platform.getFillingCutoffOptConfig(subsystemId),
        _platform.getFillingJogConfig(subsystemId),
        _platform.getFillingRefillConfig(subsystemId),
        _platform.getFillingEmptyingConfig(subsystemId),
        _platform.getFillingEventsConfig(subsystemId),
        _platform.getFillingAdvancedConfig(subsystemId),
      ]);
      if (!mounted ||
          generation != _siloProcessGeneration ||
          widget.mapping.subsystemId != subsystemId) return;
      setState(() {
        _selectedSiloIndex = siloIndex;
        _valueRevision++;
        _fillTarget = values[0] as FillingTargetConfig;
        _fillAutoTare = values[1] as FillingAutoTareConfig;
        _fillTol = values[2] as FillingToleranceConfig;
        _fillSpill = values[3] as FillingSpillOptConfig;
        _fillCutoff = values[4] as FillingCutoffOptConfig;
        _fillJog = values[5] as FillingJogConfig;
        _fillRefill = values[6] as FillingRefillConfig;
        _fillEmpty = values[7] as FillingEmptyingConfig;
        _fillEvents = values[8] as FillingEventsConfig;
        _fillAdv = values[9] as FillingAdvancedConfig;
        _siloEditMode = true;
        _loading = false;
      });
    } catch (error) {
      if (!mounted ||
          generation != _siloProcessGeneration ||
          widget.mapping.subsystemId != subsystemId) return;
      setState(() {
        _loading = false;
        _error = '加载料仓参数失败：$error';
      });
    }
  }

  Future<void> _addSilo() async {
    final subsystemId = widget.mapping.subsystemId;
    final controller = TextEditingController();
    final siloIndex = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('添加料仓'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '料仓编号'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(controller.text);
              if (value != null && value >= 0) {
                Navigator.pop(dialogContext, value);
              }
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (siloIndex == null ||
        !mounted ||
        widget.mapping.subsystemId != subsystemId) return;
    if (_siloIndices.contains(siloIndex)) {
      await _loadSiloProcess(siloIndex);
      return;
    }
    final defaults = {
      'target': const FillingTargetConfig().toMap(),
      'autoTare': const FillingAutoTareConfig().toMap(),
      'tolerance': const FillingToleranceConfig().toMap(),
      'spillOpt': const FillingSpillOptConfig().toMap(),
      'cutoffOpt': const FillingCutoffOptConfig().toMap(),
      'jog': const FillingJogConfig().toMap(),
      'refill': const FillingRefillConfig().toMap(),
      'emptying': const FillingEmptyingConfig().toMap(),
      'events': const FillingEventsConfig().toMap(),
      'advanced': const FillingAdvancedConfig().toMap(),
    };
    try {
      final ok = await _platform.saveFillingSiloProcessConfig(
        subsystemId,
        siloIndex,
        defaults,
      );
      if (!mounted || widget.mapping.subsystemId != subsystemId) return;
      if (!ok) throw StateError('料仓创建失败');
      setState(() => _siloIndices = [..._siloIndices, siloIndex]..sort());
      await _loadSiloProcess(siloIndex);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('添加料仓失败：$error')),
      );
    }
  }

  Map<String, dynamic> _buildSiloProcessConfig() => {
        'target': _fillTarget.toMap(),
        'autoTare': _fillAutoTare.toMap(),
        'tolerance': _fillTol.toMap(),
        'spillOpt': _fillSpill.toMap(),
        'cutoffOpt': _fillCutoff.toMap(),
        'jog': _fillJog.toMap(),
        'refill': _fillRefill.toMap(),
        'emptying': _fillEmpty.toMap(),
        'events': _fillEvents.toMap(),
        'advanced': _fillAdv.toMap(),
      };

  Future<void> _saveHardware() async {
    if (_ioLoading || _ioSaving) return;
    setState(() => _ioSaving = true);
    var ok = false;
    try {
      final inputs = await _platform.updateDigitalInputMap(_digitalInputs);
      final outputs = await _platform.updateDigitalOutputMap(_digitalOutputs);
      ok = inputs && outputs;
      if (!ok) {
        await _loadHardware();
      }
    } catch (error) {
      _ioError = '$error';
    }
    if (!mounted) return;
    setState(() => _ioSaving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? AppLocalizations.of(context)!.saveSuccess
            : AppLocalizations.of(context)!.saveFailedMsg),
        backgroundColor: ok ? Colors.green : Colors.red,
      ),
    );
  }

  Future<void> _saveSiloSequence() async {
    if (_siloSequenceLoading || _siloSequenceSaving) return;
    final subsystemId = widget.mapping.subsystemId;
    final config = _siloSequence;
    setState(() => _siloSequenceSaving = true);
    var ok = false;
    try {
      ok = await _platform.setFillingSiloSequenceConfig(
        subsystemId,
        config,
      );
    } catch (error) {
      _siloError = '$error';
    }
    if (!mounted) return;
    setState(() => _siloSequenceSaving = false);
    if (widget.mapping.subsystemId != subsystemId) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? '料仓顺序配置已保存' : '料仓顺序配置保存失败'),
        backgroundColor: ok ? Colors.green : Colors.red,
      ),
    );
  }

  Future<void> _editSiloStep({SiloStep? current, int? index}) async {
    final subsystemId = widget.mapping.subsystemId;
    final target = TextEditingController(
      text: current?.targetValue.toString() ?? '0',
    );
    final material = TextEditingController(text: current?.materialName ?? '');
    final materialId = TextEditingController(text: current?.materialId ?? '');
    var siloIndex = current?.siloIndex ??
        (_siloIndices.isEmpty ? 0 : _siloIndices.first);
    var enabled = current?.enabled ?? true;
    final result = await showDialog<SiloStep>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(current == null ? '添加料仓步骤' : '编辑料仓步骤'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  value: siloIndex,
                  decoration: const InputDecoration(labelText: '料仓编号'),
                  items: [
                    for (final value in _siloIndices)
                      DropdownMenuItem(value: value, child: Text('料仓 $value')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => siloIndex = value);
                    }
                  },
                ),
                TextField(
                  controller: target,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: '目标值 (kg)'),
                ),
                TextField(
                  controller: material,
                  decoration: const InputDecoration(labelText: '物料名称'),
                ),
                TextField(
                  controller: materialId,
                  decoration: const InputDecoration(labelText: '物料 ID'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('启用该步骤'),
                  value: enabled,
                  onChanged: (value) =>
                      setDialogState(() => enabled = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final targetValue = double.tryParse(target.text);
                if (targetValue == null || targetValue < 0) return;
                Navigator.pop(
                  dialogContext,
                  SiloStep(
                    siloIndex: siloIndex,
                    order: index ?? _siloSequence.steps.length,
                    targetValue: targetValue,
                    materialName: material.text.trim(),
                    materialId: materialId.text.trim(),
                    enabled: enabled,
                  ),
                );
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
    target.dispose();
    material.dispose();
    materialId.dispose();
    if (result == null ||
        !mounted ||
        widget.mapping.subsystemId != subsystemId) return;
    final steps = List<SiloStep>.from(_siloSequence.steps);
    if (index == null) {
      steps.add(result);
    } else {
      steps[index] = result;
    }
    setState(() {
      _siloSequence = SiloSequenceConfig(
        subsystemId: widget.mapping.subsystemId,
        enabled: _siloSequence.enabled,
        steps: steps,
      );
    });
  }

  void _resetCalibration() {
    _calibrationGeneration++;
    _calibrationBusy = false;
    _calibrationStatus = null;
    _calibrationState = 0;
    _completedSpanSteps = 0;
    _spanWaitingHandled = false;
    _calibrationComplete = false;
    _dynamicCalibrationAccepted = false;
    _activeCalibration = _PanelCalibrationType.none;
    _stepPhase = _PanelStepPhase.idle;
  }

  bool _isCurrentCalibration(int generation, int scaleId, int subsystemId) =>
      mounted &&
      generation == _calibrationGeneration &&
      widget.mapping.scaleId == scaleId &&
      widget.mapping.subsystemId == subsystemId;

  void _handleCalibrationEvent(int state, String message) {
    setState(() {
      _calibrationState = state;
      switch (state) {
        case 1:
          _calibrationComplete = false;
          _dynamicCalibrationAccepted = false;
          _calibrationStatus = switch (_activeCalibration) {
            _PanelCalibrationType.zero => '正在采集零点，请保持秤台空载且稳定。',
            _PanelCalibrationType.span =>
              '正在采集第 ${_completedSpanSteps + 1} 个量程点，请按提示加载砝码。',
            _PanelCalibrationType.step => '正在采集砝码重量，请保持稳定。',
            _ => message,
          };
          break;
        case 2:
          _calibrationComplete = true;
          _dynamicCalibrationAccepted = false;
          if (_activeCalibration == _PanelCalibrationType.zero) {
            _calibrationStatus = '零点校正完成，可保存或中止。';
          } else if (_activeCalibration == _PanelCalibrationType.span) {
            _completedSpanSteps = _linearMode + 1;
            _calibrationStatus = '量程校正完成，可保存或中止。';
          } else if (_activeCalibration == _PanelCalibrationType.step) {
            _stepPhase = _PanelStepPhase.weightLoaded;
            _calibrationStatus = '当前砝码点校正完成，可保存或继续逐步法。';
          } else {
            _calibrationStatus = message;
          }
          break;
        case 3:
          _calibrationComplete = true;
          _dynamicCalibrationAccepted = false;
          if (_activeCalibration == _PanelCalibrationType.span) {
            _completedSpanSteps = _linearMode + 1;
          }
          _calibrationStatus = '检测到动态校正结果，请确认接受后保存，或拒绝。';
          break;
        case 4:
          _calibrationComplete = false;
          _dynamicCalibrationAccepted = false;
          _activeCalibration = _PanelCalibrationType.none;
          _stepPhase = _PanelStepPhase.idle;
          _calibrationStatus =
              message.isEmpty ? '校正失败，请检查秤台后重试。' : '校正失败：$message';
          break;
        case 6:
          if (_activeCalibration == _PanelCalibrationType.span) {
            if (!_spanWaitingHandled &&
                _completedSpanSteps < _linearMode + 1) {
              _completedSpanSteps++;
              _spanWaitingHandled = true;
            }
            final hasNext = _completedSpanSteps < _linearMode + 1;
            final nextLoad = hasNext
                ? _spanLoads[_completedSpanSteps].text
                : '';
            _calibrationComplete = false;
            _dynamicCalibrationAccepted = false;
            _calibrationStatus = hasNext
                ? '第 $_completedSpanSteps 个量程点完成，请加载第 ${_completedSpanSteps + 1} 点（$nextLoad ${_calibrationUnit}）后继续。'
                : '量程点采集完成，等待最终结果。';
          } else {
            _calibrationStatus =
                message.isEmpty ? '等待下一步操作。' : message;
          }
          break;
      }
    });
  }

  String get _calibrationUnit {
    const units = ['g', 'kg', 'lb', 't', 'ton'];
    return units[_scale.calibrationUnit.clamp(0, units.length - 1).toInt()];
  }

  double _convertWeight(double value, WeightUnit from, int to) {
    const factorsToKg = [0.001, 1.0, 0.45359237, 1000.0, 907.18474];
    final fromIndex = from.index.clamp(0, factorsToKg.length - 1).toInt();
    final toIndex = to.clamp(0, factorsToKg.length - 1).toInt();
    return value * factorsToKg[fromIndex] / factorsToKg[toIndex];
  }

  Future<void> _runCalibration({
    required _PanelCalibrationType type,
  }) async {
    if (_calibrationBusy || _loading || _saving ||
        _activeCalibration != _PanelCalibrationType.none) return;

    final scaleId = widget.mapping.scaleId;
    final subsystemId = widget.mapping.subsystemId;
    final generation = ++_calibrationGeneration;
    final loads = <double>[];
    if (type == _PanelCalibrationType.span) {
      for (var i = 0; i <= _linearMode; i++) {
        final load = double.tryParse(_spanLoads[i].text);
        if (load == null || !load.isFinite || load <= 0) {
          setState(() => _calibrationStatus =
              '请输入大于零的第 ${i + 1} 个砝码重量（$_calibrationUnit）。');
          return;
        }
        loads.add(load);
      }
    } else if (type == _PanelCalibrationType.step) {
      final load = double.tryParse(_stepLoad.text);
      if (load == null || !load.isFinite || load <= 0) {
        setState(() => _calibrationStatus =
            '请输入大于零的砝码重量（$_calibrationUnit）。');
        return;
      }
      loads.add(load);
    }

    setState(() {
      _activeCalibration = type;
      _calibrationState = 1;
      _calibrationComplete = false;
      _completedSpanSteps = 0;
      _spanWaitingHandled = false;
      _stepPhase = _PanelStepPhase.idle;
      _calibrationStatus = type == _PanelCalibrationType.zero
          ? '正在进行零点校正，请确认秤台空载。'
          : type == _PanelCalibrationType.span
              ? '正在进行量程校正，请加载第 1 点（${loads.first} $_calibrationUnit）。'
              : '正在开始逐步法校正，请放置 ${loads.first} $_calibrationUnit 砝码。';
      _calibrationBusy = true;
    });

    try {
      final ok = switch (type) {
        _PanelCalibrationType.zero => await _platform.triggerCalZero(scaleId),
        _PanelCalibrationType.span =>
          await _platform.triggerCalSpan(scaleId, _linearMode, loads),
        _PanelCalibrationType.step =>
          await _platform.triggerStepCalibration(scaleId, loads.single),
        _PanelCalibrationType.none => false,
      };
      if (!_isCurrentCalibration(generation, scaleId, subsystemId)) return;
      if (!ok) {
        setState(() {
          _activeCalibration = _PanelCalibrationType.none;
          _calibrationComplete = false;
          _calibrationStatus = '启动校正失败。';
        });
      }
    } catch (error) {
      if (_isCurrentCalibration(generation, scaleId, subsystemId)) {
        setState(() {
          _activeCalibration = _PanelCalibrationType.none;
          _calibrationComplete = false;
          _calibrationStatus = '$error';
        });
      }
    } finally {
      if (_isCurrentCalibration(generation, scaleId, subsystemId)) {
        setState(() => _calibrationBusy = false);
      }
    }
  }

  Future<void> _saveCalibration() async {
    if (_calibrationBusy ||
        _loading ||
        !_calibrationComplete ||
        (_calibrationState != 2 && _calibrationState != 3)) {
      return;
    }
    if (_calibrationState == 3 && !_dynamicCalibrationAccepted) return;
    final scaleId = widget.mapping.scaleId;
    final subsystemId = widget.mapping.subsystemId;
    final generation = _calibrationGeneration;
    final l = AppLocalizations.of(context)!;
    setState(() => _calibrationBusy = true);
    try {
      final saved = await _platform.updateScaleParams(scaleId, _scale);
      final ok = saved && await _platform.triggerSaveCalibration(scaleId);
      if (!_isCurrentCalibration(generation, scaleId, subsystemId)) return;
      setState(() {
        _calibrationStatus = ok ? l.calSavedSuccess : l.calSaveFailed;
        if (ok) {
          _activeCalibration = _PanelCalibrationType.none;
          _calibrationState = 0;
          _calibrationComplete = false;
          _dynamicCalibrationAccepted = false;
          _stepPhase = _PanelStepPhase.idle;
        }
      });
    } catch (error) {
      if (_isCurrentCalibration(generation, scaleId, subsystemId)) {
        setState(() => _calibrationStatus = '$error');
      }
    } finally {
      if (_isCurrentCalibration(generation, scaleId, subsystemId)) {
        setState(() => _calibrationBusy = false);
      }
    }
  }

  Future<void> _addCalibrationLoad() async {
    if (_calibrationBusy || _loading) return;
    final canContinueSpan = _activeCalibration == _PanelCalibrationType.span &&
        _calibrationState == 6 &&
        _completedSpanSteps < _linearMode + 1;
    final canContinueStep = _activeCalibration == _PanelCalibrationType.step &&
        _stepPhase == _PanelStepPhase.nextLoad;
    if (!canContinueSpan && !canContinueStep) return;
    final scaleId = widget.mapping.scaleId;
    final subsystemId = widget.mapping.subsystemId;
    final generation = _calibrationGeneration;
    setState(() {
      _calibrationBusy = true;
      _calibrationComplete = false;
      _calibrationStatus = canContinueSpan
          ? '正在采集第 ${_completedSpanSteps + 1} 个量程点。'
          : '已确认替代物料，请继续加码并开始下一点。';
      if (canContinueSpan) _spanWaitingHandled = false;
      if (canContinueStep) _stepPhase = _PanelStepPhase.idle;
      _calibrationState = 1;
    });
    try {
      final ok = await _platform.triggerCalibrationAddLoad(scaleId);
      if (!_isCurrentCalibration(generation, scaleId, subsystemId)) return;
      if (!ok) setState(() => _calibrationStatus = '确认加载失败。');
    } catch (error) {
      if (_isCurrentCalibration(generation, scaleId, subsystemId)) {
        setState(() => _calibrationStatus = '$error');
      }
    } finally {
      if (_isCurrentCalibration(generation, scaleId, subsystemId)) {
        setState(() => _calibrationBusy = false);
      }
    }
  }

  Future<void> _acceptDynamicCalibration(bool accept) async {
    if (_calibrationBusy || _loading || _calibrationState != 3) return;
    final scaleId = widget.mapping.scaleId;
    final subsystemId = widget.mapping.subsystemId;
    final generation = _calibrationGeneration;
    setState(() => _calibrationBusy = true);
    try {
      final ok = await _platform.acceptDynamicCalibration(scaleId, accept);
      if (!_isCurrentCalibration(generation, scaleId, subsystemId)) return;
      if (!ok) {
        setState(() => _calibrationStatus = '动态校正确认失败。');
      } else if (!accept) {
        setState(() {
          _activeCalibration = _PanelCalibrationType.none;
          _calibrationComplete = false;
          _calibrationState = 0;
          _calibrationStatus = '已拒绝动态校正结果。';
        });
      } else {
        setState(() {
          _dynamicCalibrationAccepted = true;
          _calibrationStatus = '已接受动态校正结果，请保存完成。';
        });
      }
    } catch (error) {
      if (_isCurrentCalibration(generation, scaleId, subsystemId)) {
        setState(() => _calibrationStatus = '$error');
      }
    } finally {
      if (_isCurrentCalibration(generation, scaleId, subsystemId)) {
        setState(() => _calibrationBusy = false);
      }
    }
  }

  Future<void> _abortCalibration() async {
    if (_calibrationBusy || _loading ||
        _activeCalibration == _PanelCalibrationType.none) return;
    final scaleId = widget.mapping.scaleId;
    final subsystemId = widget.mapping.subsystemId;
    final generation = _calibrationGeneration;
    setState(() => _calibrationBusy = true);
    try {
      final ok = await _platform.triggerAbortCalibration(scaleId);
      if (!_isCurrentCalibration(generation, scaleId, subsystemId)) return;
      if (ok) {
        setState(() {
          _activeCalibration = _PanelCalibrationType.none;
          _calibrationState = 0;
          _calibrationComplete = false;
          _dynamicCalibrationAccepted = false;
          _stepPhase = _PanelStepPhase.idle;
          _calibrationStatus = AppLocalizations.of(context)!.calAbortedMsg;
        });
      } else {
        setState(() => _calibrationStatus = '中止校正失败。');
      }
    } catch (error) {
      if (_isCurrentCalibration(generation, scaleId, subsystemId)) {
        setState(() => _calibrationStatus = '$error');
      }
    } finally {
      if (_isCurrentCalibration(generation, scaleId, subsystemId)) {
        setState(() => _calibrationBusy = false);
      }
    }
  }

  Future<void> _confirmStepRemoval() async {
    if (_calibrationBusy ||
        _activeCalibration != _PanelCalibrationType.step ||
        _stepPhase != _PanelStepPhase.removeWaiting) return;
    final scaleId = widget.mapping.scaleId;
    final subsystemId = widget.mapping.subsystemId;
    final generation = _calibrationGeneration;
    setState(() => _calibrationBusy = true);
    try {
      final ok = await _platform.triggerStepRemoveConfirm(scaleId);
      if (!_isCurrentCalibration(generation, scaleId, subsystemId)) return;
      setState(() {
        _calibrationBusy = false;
        if (ok) {
          _stepPhase = _PanelStepPhase.substituteWaiting;
          _calibrationStatus = '已确认移除砝码，请加入替代物料后确认。';
        } else {
          _calibrationStatus = '移除砝码确认失败。';
        }
      });
    } catch (error) {
      if (_isCurrentCalibration(generation, scaleId, subsystemId)) {
        setState(() {
          _calibrationBusy = false;
          _calibrationStatus = '$error';
        });
      }
    }
  }

  Future<void> _confirmStepSubstitute() async {
    final weight = double.tryParse(_stepLoad.text);
    if (weight == null || !weight.isFinite || weight <= 0) {
      setState(() => _calibrationStatus =
          '请输入大于零的替代物料重量（$_calibrationUnit）。');
      return;
    }
    if (_calibrationBusy ||
        _activeCalibration != _PanelCalibrationType.step ||
        _stepPhase != _PanelStepPhase.substituteWaiting) return;
    final scaleId = widget.mapping.scaleId;
    final subsystemId = widget.mapping.subsystemId;
    final generation = _calibrationGeneration;
    setState(() => _calibrationBusy = true);
    try {
      final ok =
          await _platform.triggerStepSubstituteConfirm(scaleId, weight);
      if (!_isCurrentCalibration(generation, scaleId, subsystemId)) return;
      setState(() {
        _calibrationBusy = false;
        if (ok) {
          _stepPhase = _PanelStepPhase.nextLoad;
          _calibrationStatus = '替代物料已确认，请继续加码并开始下一点。';
        } else {
          _calibrationStatus = '替代物料确认失败。';
        }
      });
    } catch (error) {
      if (_isCurrentCalibration(generation, scaleId, subsystemId)) {
        setState(() {
          _calibrationBusy = false;
          _calibrationStatus = '$error';
        });
      }
    }
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    _siloProcessGeneration++;
    final id = widget.mapping.subsystemId;
    final scaleId = widget.mapping.scaleId;
    final appType = _appType;
    setState(() {
      _loading = true;
      _error = null;
      _siloEditMode = false;
    });
    try {
      final inputMode = await _platform.getInputMode();
      final scale = await _platform.getScaleParams(scaleId);
      final zero = await _platform.getZeroConfig(scaleId);
      final tare = await _platform.getTareConfig(scaleId);
      final filter = await _platform.getFilterStability(scaleId);

      if (appType == 1) {
        final fillGen = await _platform.getFillingGeneralConfig(id);
        final fillSys = await _platform.getFillingSystemConfig(id);
        final fillTarget = await _platform.getFillingTargetConfig(id);
        final fillAutoTare = await _platform.getFillingAutoTareConfig(id);
        final fillTol = await _platform.getFillingToleranceConfig(id);
        final fillSpill = await _platform.getFillingSpillOptConfig(id);
        final fillCutoff = await _platform.getFillingCutoffOptConfig(id);
        final fillJog = await _platform.getFillingJogConfig(id);
        final fillRefill = await _platform.getFillingRefillConfig(id);
        final fillEmpty = await _platform.getFillingEmptyingConfig(id);
        final fillEvents = await _platform.getFillingEventsConfig(id);
        final fillAdv = await _platform.getFillingAdvancedConfig(id);
        if (!mounted ||
            generation != _loadGeneration ||
            widget.mapping.subsystemId != id ||
            widget.mapping.scaleId != scaleId ||
            _appType != appType) {
          return;
        }
        _inputMode = inputMode;
        _scale = scale;
        _zero = zero;
        _tare = tare;
        _filter = filter;
        _fillGen = fillGen;
        _fillSys = fillSys;
        _fillTarget = fillTarget;
        _fillAutoTare = fillAutoTare;
        _fillTol = fillTol;
        _fillSpill = fillSpill;
        _fillCutoff = fillCutoff;
        _fillJog = fillJog;
        _fillRefill = fillRefill;
        _fillEmpty = fillEmpty;
        _fillEvents = fillEvents;
        _fillAdv = fillAdv;
      } else {
        final liwBase = await _platform.getLiwBaseConfig(id);
        final liwSystem = await _platform.getLiwSystemConfig(id);
        final liwSysId = await _platform.getLiwSystemIdConfig(id);
        final liwCtrl = await _platform.getLiwControllerConfig(id);
        final liwRefill = await _platform.getLiwRefillConfig(id);
        final liwTarget = await _platform.getLiwTargetValuesConfig(id);
        final liwTol = await _platform.getLiwToleranceCheckConfig(id);
        final liwEmpty = await _platform.getLiwEmptyingConfig(id);
        final liwWarn = await _platform.getLiwWarningConfig(id);
        final liwFlow = await _platform.getLiwFlowMonitorConfig(id);
        final liwAdv = await _platform.getLiwAdvancedConfig(id);
        final liwStats = await _platform.getLiwStatsConfig(id);
        if (!mounted ||
            generation != _loadGeneration ||
            widget.mapping.subsystemId != id ||
            widget.mapping.scaleId != scaleId ||
            _appType != appType) {
          return;
        }
        _inputMode = inputMode;
        _scale = scale;
        _zero = zero;
        _tare = tare;
        _filter = filter;
        _liwBase = liwBase;
        _liwSystem = liwSystem;
        _liwSysId = liwSysId;
        _liwCtrl = liwCtrl;
        _liwRefill = liwRefill;
        _liwTarget = liwTarget;
        _liwTol = liwTol;
        _liwEmpty = liwEmpty;
        _liwWarn = liwWarn;
        _liwFlow = liwFlow;
        _liwAdv = liwAdv;
        _liwStats = liwStats;
      }
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _valueRevision++;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<bool> _save() async {
    final l = AppLocalizations.of(context)!;
    if (_loading ||
        _saving ||
        _error != null ||
        _calibrationBusy ||
        _activeCalibration != _PanelCalibrationType.none) {
      return false;
    }
    setState(() => _saving = true);
    final id = widget.mapping.subsystemId;
    final scaleId = widget.mapping.scaleId;
    final appType = _appType;
    final name = _name.text.trim();
    final enabled = _enabled;
    final scale = _scale;
    final zero = _zero;
    final tare = _tare;
    final filter = _filter;
    final siloEditMode = _siloEditMode;
    final siloIndex = _selectedSiloIndex;
    final siloProcessConfig =
        siloEditMode ? _buildSiloProcessConfig() : null;
    final fillingConfigs = (
      general: _fillGen,
      system: _fillSys,
      target: _fillTarget,
      autoTare: _fillAutoTare,
      tolerance: _fillTol,
      spill: _fillSpill,
      cutoff: _fillCutoff,
      jog: _fillJog,
      refill: _fillRefill,
      emptying: _fillEmpty,
      events: _fillEvents,
      advanced: _fillAdv,
    );
    final liwConfigs = (
      base: _liwBase,
      system: _liwSystem,
      systemId: _liwSysId,
      controller: _liwCtrl,
      refill: _liwRefill,
      target: _liwTarget,
      tolerance: _liwTol,
      emptying: _liwEmpty,
      warning: _liwWarn,
      flow: _liwFlow,
      advanced: _liwAdv,
      stats: _liwStats,
    );
    var ok = true;
    try {
      ok = await _platform.updateScaleParams(scaleId, scale) && ok;
      ok = await _platform.updateZeroConfig(scaleId, zero) && ok;
      ok = await _platform.updateTareConfig(scaleId, tare) && ok;
      ok = await _platform.updateFilterStability(scaleId, filter) && ok;

      if (appType == 1 && siloEditMode && siloIndex != null) {
        ok = await _platform.saveFillingSiloProcessConfig(
              id,
              siloIndex,
              siloProcessConfig!,
            ) &&
            ok;
      } else if (appType == 1) {
        ok = await _platform.updateFillingGeneralConfig(id, fillingConfigs.general) && ok;
        ok = await _platform.updateFillingSystemConfig(id, fillingConfigs.system) && ok;
        ok = await _platform.updateFillingTargetConfig(id, fillingConfigs.target) && ok;
        ok = await _platform.updateFillingAutoTareConfig(id, fillingConfigs.autoTare) &&
            ok;
        ok = await _platform.updateFillingToleranceConfig(id, fillingConfigs.tolerance) && ok;
        ok = await _platform.updateFillingSpillOptConfig(id, fillingConfigs.spill) && ok;
        ok =
            await _platform.updateFillingCutoffOptConfig(id, fillingConfigs.cutoff) && ok;
        ok = await _platform.updateFillingJogConfig(id, fillingConfigs.jog) && ok;
        ok = await _platform.updateFillingRefillConfig(id, fillingConfigs.refill) && ok;
        ok = await _platform.updateFillingEmptyingConfig(id, fillingConfigs.emptying) && ok;
        ok = await _platform.updateFillingEventsConfig(id, fillingConfigs.events) && ok;
        ok = await _platform.updateFillingAdvancedConfig(id, fillingConfigs.advanced) && ok;
      } else {
        ok = await _platform.updateLiwBaseConfig(id, liwConfigs.base) && ok;
        ok = await _platform.updateLiwSystemConfig(id, liwConfigs.system) && ok;
        ok = await _platform.updateLiwSystemIdConfig(id, liwConfigs.systemId) && ok;
        ok = await _platform.updateLiwControllerConfig(id, liwConfigs.controller) && ok;
        ok = await _platform.updateLiwRefillConfig(id, liwConfigs.refill) && ok;
        ok = await _platform.updateLiwTargetValuesConfig(id, liwConfigs.target) && ok;
        ok = await _platform.updateLiwToleranceCheckConfig(id, liwConfigs.tolerance) && ok;
        ok = await _platform.updateLiwEmptyingConfig(id, liwConfigs.emptying) && ok;
        ok = await _platform.updateLiwWarningConfig(id, liwConfigs.warning) && ok;
        ok = await _platform.updateLiwFlowMonitorConfig(id, liwConfigs.flow) && ok;
        ok = await _platform.updateLiwAdvancedConfig(id, liwConfigs.advanced) && ok;
        ok = await _platform.updateLiwStatsConfig(id, liwConfigs.stats) && ok;
      }
      if (ok &&
          name.isNotEmpty &&
          name != widget.mapping.description) {
        ok = await _platform.addSubsystemMapping(
              id,
              name,
              scaleId: scaleId,
              appType: appType,
            ) &&
            ok;
      }
      if (ok && appType != widget.mapping.appType) {
        ok = await _platform.setSubsystemAppType(id, appType) && ok;
        if (ok && mounted) {
          AppStateProvider.read(context).setActiveRecipeName(id, null);
        }
      }
      if (ok && enabled != widget.mapping.enabled) {
        ok = await _platform.setSubsystemEnabled(id, enabled) && ok;
      }
      if (ok && mounted) await AppStateProvider.of(context).refreshSubsystems();
    } catch (e) {
      ok = false;
      _error = '$e';
    }
    if (!mounted) return false;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? l.saveSuccess : l.saveFailedMsg)),
    );
    if (ok && appType != widget.mapping.appType) {
      await Future.wait([_load(), _loadRecipes()]);
    }
    return ok;
  }

  // ── 配方操作 ────────────────────────────────────────────────

  Future<void> _activateRecipe(
    Map<String, dynamic> recipe, {
    required bool editAfterLoad,
  }) async {
    final id = recipe['recipeId'] ?? recipe['id'];
    if (id is! int) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('配方 ID 无效，无法加载')),
      );
      return;
    }
    final subsystemId = widget.mapping.subsystemId;
    final appType = _appType;
    final name = recipe['name'] as String? ?? '未命名';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(editAfterLoad ? '加载并编辑配方' : '加载配方'),
        content: Text(
          '将「$name」加载到子系统 ${widget.mapping.subsystemId}，'
          '这会改变当前运行参数。是否继续？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确认加载'),
          ),
        ],
      ),
    );
    if (confirmed != true ||
        !mounted ||
        widget.mapping.subsystemId != subsystemId ||
        _appType != appType) return;
    try {
      final ok = await AppStateProvider.read(context).loadMaterialRecipe(
        subsystemId,
        id,
        name,
        appType,
      );
      if (!mounted ||
          widget.mapping.subsystemId != subsystemId ||
          _appType != appType) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载配方「$name」失败')),
        );
        return;
      }
      await _load();
      if (!mounted) return;
      setState(() => _section = 3);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已加载配方「$name」')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加载配方失败：$error')),
      );
    }
  }

  Future<void> _deleteRecipe(Map<String, dynamic> recipe) async {
    final subsystemId = widget.mapping.subsystemId;
    final appType = _appType;
    final name = recipe['name'] as String? ?? '未命名';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除配方'),
        content: Text('确定删除配方「$name」？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true ||
        !mounted ||
        widget.mapping.subsystemId != subsystemId ||
        _appType != appType) return;

    final state = AppStateProvider.read(context);
    final ok = await state.deleteMaterialRecipe(
      (recipe['recipeId'] ?? recipe['id']) as int,
      appType,
    );
    if (!mounted ||
        widget.mapping.subsystemId != subsystemId ||
        _appType != appType) return;
    if (ok) {
      if (state.getActiveRecipeName(subsystemId) == name) {
        state.setActiveRecipeName(subsystemId, null);
      }
      await _loadRecipes();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('配方「$name」已删除')),
        );
      }
    }
  }

  Future<void> _saveAsRecipeDialog() async {
    final subsystemId = widget.mapping.subsystemId;
    final appType = _appType;
    final activeName = AppStateProvider.read(context)
            .getActiveRecipeName(subsystemId) ??
        '';
    final controller = TextEditingController(text: activeName);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('保存当前参数为配方'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '配方名称',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final v = controller.text.trim();
              if (v.isEmpty) return;
              Navigator.pop(ctx, v);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null ||
        !mounted ||
        widget.mapping.subsystemId != subsystemId ||
        _appType != appType) return;
    if (!await _save() ||
        !mounted ||
        widget.mapping.subsystemId != subsystemId ||
        _appType != appType) {
      return;
    }
    if (!mounted) return;

    final state = AppStateProvider.read(context);
    final ok = await state.saveMaterialRecipe(
      subsystemId,
      name,
      appType,
    );
    if (!mounted ||
        widget.mapping.subsystemId != subsystemId ||
        _appType != appType) return;

    if (ok) {
      final activated = await state.setSubsystemActiveRecipe(subsystemId, name);
      if (!activated) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('配方已保存，但激活失败')),
        );
        return;
      }
      await _loadRecipes();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('配方「$name」已保存并激活')),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('保存配方失败')),
      );
    }
  }

  Future<void> _showRecipePicker() async {
    if (_recipesLoading) return;
    final subsystemId = widget.mapping.subsystemId;
    final appType = _appType;
    final activeName =
        AppStateProvider.read(context).getActiveRecipeName(subsystemId) ?? '';
    if (_recipes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前子系统暂无配方，调整参数后点「另存为」创建')),
      );
      return;
    }
    final picked = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选择配方'),
        content: SizedBox(
          width: 320,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _recipes.length,
            itemBuilder: (ctx, i) {
              final r = _recipes[i];
              final name = r['name'] as String? ?? '未命名';
              final isActive = name == activeName;
              return ListTile(
                title: Text(name),
                subtitle: Text(isActive ? '使用中' : '未加载'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isActive)
                      const Icon(Icons.check, color: Color(0xFF2BD98A))
                    else
                      const Icon(Icons.arrow_forward_ios, size: 12),
                    const SizedBox(width: 6),
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          size: 18, color: Color(0xFFFF8F85)),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _deleteRecipe(r);
                      },
                    ),
                  ],
                ),
                onTap: isActive ? null : () => Navigator.pop(ctx, r),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
    if (picked != null &&
        mounted &&
        widget.mapping.subsystemId == subsystemId &&
        _appType == appType) {
      await _activateRecipe(picked, editAfterLoad: false);
    }
  }

  // ── 主构建 ──────────────────────────────────────────────────

  bool _matches(String label) =>
      _searchQuery.isEmpty ||
      label.toLowerCase().contains(_searchQuery.toLowerCase());

  List<_ConfigGroupOption> _groupOptions(AppLocalizations l, [int? section]) {
    switch (section ?? _section) {
      case 1:
        return [
          _ConfigGroupOption('scale-base', '秤台参数'),
          _ConfigGroupOption('scale-zero', '零点配置'),
          _ConfigGroupOption('scale-tare', '皮重配置'),
          _ConfigGroupOption('scale-calibration', l.calibration),
        ];
      case 2:
        return const [
          _ConfigGroupOption('filter-lp', '低通滤波'),
          _ConfigGroupOption('filter-notch', '陷波滤波'),
          _ConfigGroupOption('filter-adaptive', '自适应滤波'),
          _ConfigGroupOption('filter-stability', '稳定性检测'),
        ];
      case 3:
        final groups = <_ConfigGroupOption>[];
        if (_appType == 1) {
          groups.addAll(const [
            _ConfigGroupOption('fill-general', '通用'),
            _ConfigGroupOption('fill-target', '目标'),
            _ConfigGroupOption('fill-autotare', '自动去皮'),
            _ConfigGroupOption('fill-tol', '公差'),
            _ConfigGroupOption('fill-spill', '溢出优化'),
            _ConfigGroupOption('fill-cutoff', '截止优化'),
            _ConfigGroupOption('fill-jog', '点动'),
            _ConfigGroupOption('fill-refill', '回填'),
            _ConfigGroupOption('fill-empty', '排空'),
            _ConfigGroupOption('fill-events', '事件'),
            _ConfigGroupOption('fill-adv', '高级配置'),
          ]);
        } else {
          groups.addAll(const [
            _ConfigGroupOption('liw-base', '基础'),
            _ConfigGroupOption('liw-system', '系统'),
            _ConfigGroupOption('liw-sysid', '系统辨识'),
            _ConfigGroupOption('liw-pid', '控制器 PID'),
            _ConfigGroupOption('liw-refill', '回填'),
            _ConfigGroupOption('liw-target', '目标值'),
            _ConfigGroupOption('liw-tol', '公差检查'),
            _ConfigGroupOption('liw-empty', '排空'),
            _ConfigGroupOption('liw-warn', '报警配置'),
            _ConfigGroupOption('liw-flow', '流量监控'),
            _ConfigGroupOption('liw-adv', '高级配置'),
            _ConfigGroupOption('liw-stats', '统计'),
          ]);
        }
        return groups;
      default:
        return const [];
    }
  }

  Widget _buildGroupNavigation(AppLocalizations l) {
    final groups = _groupOptions(l);
    if (groups.isEmpty) return const SizedBox.shrink();
    final selectedIndex =
        groups.indexWhere((group) => group.key == _activeGroupKey);
    final index = selectedIndex < 0 ? 0 : selectedIndex;
    final selected = groups[index];
    return Container(
      color: const Color(0xFF0D2535),
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '当前分组 ${index + 1}/${groups.length} · ${selected.title}',
            key: const Key('config-group-position'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF91ABBA),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 5),
          SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: groups.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, i) {
                final group = groups[i];
                final isSelected = i == index;
                return ChoiceChip(
                  key: Key('group-nav-${group.key}'),
                  label: Text(group.title),
                  selected: isSelected,
                  onSelected: (_) => setState(() => _activeGroupKey = group.key),
                  labelStyle: TextStyle(
                    color: isSelected
                        ? const Color(0xFFEFFAFF)
                        : const Color(0xFF91ABBA),
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  backgroundColor: const Color(0xFF153748),
                  selectedColor: const Color(0xFF1F728A),
                  side: BorderSide(
                    color: isSelected
                        ? const Color(0xFF62E3E5)
                        : const Color(0xFF29495B),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final sections = <String>[
      '基本',
      '称重',
      '滤波',
      '配方',
      '硬件',
      if (_appType == 1) '工艺',
    ];
    if (_section >= sections.length) _section = 0;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF102B3B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2C5062)),
      ),
      child: Column(
        children: [
          _buildHeader(l, sections[_section]),
          _buildSearchBar(),
          _buildBasicInfoBar(l),
          _buildTabBar(sections),
          _buildGroupNavigation(l),
          const Divider(height: 1, color: Color(0xFF29495B)),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF62E3E5)),
                  )
                : _error != null
                    ? Center(
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Color(0xFFFF8F85)),
                        ),
                      )
                    : IgnorePointer(
                        ignoring: _saving,
                        child: SingleChildScrollView(
                          key: ValueKey('$_section-$_appType'),
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                          child: _sectionBody(l),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(AppLocalizations l, String tabName) {
    final title = _name.text.trim().isEmpty
        ? 'Sub ${widget.mapping.subsystemId}'
        : _name.text.trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 8),
      child: Row(
        children: [
          const Icon(Icons.tune, color: Color(0xFF62E3E5), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$title  /  $tabName',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFEFFAFF),
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (widget.onOpenDashboard != null)
            IconButton(
              tooltip: '打开看板',
              onPressed: widget.onOpenDashboard,
              icon: const Icon(Icons.open_in_full,
                  color: Color(0xFF91ABBA), size: 18),
            ),
          TextButton.icon(
              key: const Key('panel-save'),
              onPressed: _saving ||
                    _loading ||
                    _error != null ||
                    _calibrationBusy ||
                    _activeCalibration != _PanelCalibrationType.none
                ? null
                : _save,
            icon: _saving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined, size: 18),
            label: Text(l.save),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF62E3E5),
            ),
          ),
          if (widget.onClose != null)
            IconButton(
              tooltip: '关闭',
              onPressed: widget.onClose,
              icon: const Icon(Icons.close, color: Color(0xFFEFFAFF), size: 20),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
      child: TextField(
        key: const Key('config-search'),
        style: const TextStyle(color: Color(0xFFEFFAFF)),
        decoration: InputDecoration(
          prefixIcon:
              const Icon(Icons.search, color: Color(0xFF62E3E5), size: 18),
          hintText: '搜索参数',
          hintStyle: const TextStyle(color: Color(0xFF91ABBA)),
          isDense: true,
          filled: true,
          fillColor: const Color(0xFF153748),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(9)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        ),
        onChanged: (value) => setState(() => _searchQuery = value.trim()),
      ),
    );
  }

  // 顶部当前配方栏（对齐 SVG 的配方栏：当前配方 + 另存为 + 新建）
  Widget _buildBasicInfoBar(AppLocalizations l) {
    final activeName = _appType == widget.mapping.appType
        ? AppStateProvider.read(context)
                .getActiveRecipeName(widget.mapping.subsystemId) ??
            ''
        : '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF0D2535),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: const Color(0xFF31596A)),
        ),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 30,
              decoration: BoxDecoration(
                color: const Color(0xFF62E3E5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            const Icon(Icons.menu_book_outlined,
                size: 16, color: Color(0xFF62E3E5)),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('当前配方',
                      style: TextStyle(color: Color(0xFF91ABBA), fontSize: 10)),
                  Text(
                    activeName.isEmpty ? '未选择配方' : activeName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFEFFAFF),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: _recipesLoading ? null : _showRecipePicker,
              icon: const Icon(Icons.swap_horiz, size: 16),
              label: const Text('切换'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF62E3E5),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
              ),
            ),
            const SizedBox(width: 4),
            TextButton.icon(
              onPressed: _saving ? null : _saveAsRecipeDialog,
              icon: const Icon(Icons.save_as, size: 14),
              label: const Text('另存为'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF62E3E5),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBar(List<String> sections) {
    return Container(
      height: 44,
      color: const Color(0xFF0D2535),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: sections.length * 88.0,
          child: Stack(
            children: [
              Row(
                children: [
                  for (var i = 0; i < sections.length; i++)
                    SizedBox(
                      width: 88,
                      height: 44,
                      child: InkWell(
                        onTap: () => setState(() {
                          _section = i;
                          final groups =
                              _groupOptions(AppLocalizations.of(context)!, i);
                          _activeGroupKey = groups.isEmpty
                              ? null
                              : i == 3
                                  ? (_appType == 1
                                      ? 'fill-general'
                                      : 'liw-system')
                                  : groups.first.key;
                        }),
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 220),
                            style: TextStyle(
                              color: i == _section
                                  ? const Color(0xFFEFFAFF)
                                  : const Color(0xFF91ABBA),
                              fontSize: 12,
                              fontWeight: i == _section
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                            child: Text(
                              sections[i],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeInOutCubic,
                left: _section * 88.0 + 8,
                bottom: 0,
                width: 72,
                height: 3,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0xFF62E3E5),
                    borderRadius: BorderRadius.all(Radius.circular(2)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionBody(AppLocalizations l) {
    switch (_section) {
      case 0:
        return _basicTab(l);
      case 1:
        return _scaleTab(l);
      case 2:
        return _filterTab(l);
      case 3:
        return _recipeTab(l);
      case 4:
        return _hardwareTab(l);
      default:
        return _processTab(l);
    }
  }

  // ── 0. 基本 ────────────────────────────────────────────────

  Widget _basicTab(AppLocalizations l) {
    return _group(
      title: '基本参数',
      subtitle: '子系统标识与应用类型',
      count: 5,
      groupKey: 'basic',
      initiallyExpanded: true,
      children: [
        _paramRow(
          label: '名称',
          control: TextField(
            controller: _name,
            style: const TextStyle(color: Color(0xFFEFFAFF), fontSize: 13),
            decoration: _deco(),
            onChanged: (_) => setState(() {}),
          ),
        ),
        _paramRow(
          label: '应用类型',
          control: DropdownButtonFormField<int>(
            value: _appType,
            dropdownColor: const Color(0xFF153748),
            style: const TextStyle(color: Color(0xFFEFFAFF), fontSize: 13),
            decoration: _deco(),
            items: [
              DropdownMenuItem(value: 0, child: Text(l.lossInWeight)),
              DropdownMenuItem(value: 1, child: Text(l.filling)),
            ],
            onChanged: _saving || _loading
                ? null
                : (value) {
                    if (value != null) _changeAppType(value);
                  },
          ),
        ),
        _paramRow(
          label: l.inputModeLabel,
          control: _readonly(
            _inputMode == 'ethercat' ? l.ethercatMode : l.shmemMode,
          ),
          showScope: false,
        ),
        _paramRow(
          label: '秤台位置',
          control: _readonly('Scale ${widget.mapping.scaleId}'),
          showScope: false,
        ),
        _boolRow(
          '启用',
          _enabled,
          (v) => setState(() => _enabled = v),
        ),
      ],
    );
  }

  // ── 1. 称重 ────────────────────────────────────────────────

  Widget _scaleTab(AppLocalizations l) {
    const units = ['g', 'kg', 'lb', 't', 'ton'];
    final autoZeroLabels = [l.off, l.grossText, l.grossNet];
    final powerUpLabels = [l.lastVal, l.calibrated, l.newVal];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _group(
          title: '秤台参数',
          subtitle: '单位 / 容量 / 分度 / 过载',
          count: 4,
          groupKey: 'scale-base',
          initiallyExpanded: true,
          children: [
            _dropRow<int>(
              l.unit,
              _scale.primaryUnit.clamp(0, units.length - 1).toInt(),
              [
                for (var i = 0; i < units.length; i++)
                  DropdownMenuItem(value: i, child: Text(units[i])),
              ],
              (v) =>
                  setState(() => _scale = _scale.copyWith(primaryUnit: v ?? 0)),
            ),
            _numRow(l.capacity, _scale.capacity, (v) {
              setState(() => _scale = _scale.copyWith(capacity: v));
            }),
            _numRow(l.division, _scale.division, (v) {
              setState(() => _scale = _scale.copyWith(division: v));
            }, digits: 4),
            _numRow(l.overloadRange, _scale.overloadRange.toDouble(), (v) {
              setState(
                  () => _scale = _scale.copyWith(overloadRange: v.round()));
            }, digits: 0),
          ],
        ),
        _group(
          title: '零点跟踪 / 零点配置',
          subtitle: '自动零点追踪与上电清零',
          count: 5,
          groupKey: 'scale-zero',
          initiallyExpanded: true,
          children: [
            _dropRow<int>(
              l.autoZeroTracking,
              _zero.autoZeroMode.clamp(0, autoZeroLabels.length - 1).toInt(),
              [
                for (var i = 0; i < autoZeroLabels.length; i++)
                  DropdownMenuItem(value: i, child: Text(autoZeroLabels[i])),
              ],
              (v) => setState(() => _zero = _withZero(autoZeroMode: v ?? 0)),
            ),
            _numRow(l.autoZeroTrackingD, _zero.autoZeroRangeD, (v) {
              setState(() => _zero = _withZero(autoZeroRangeD: v));
            }),
            _numRow(l.underloadD, _zero.underloadRangeD, (v) {
              setState(() => _zero = _withZero(underloadRangeD: v));
            }),
            _dropRow<int>(
              l.powerUpZero,
              _zero.powerUpZero.clamp(0, powerUpLabels.length - 1).toInt(),
              [
                for (var i = 0; i < powerUpLabels.length; i++)
                  DropdownMenuItem(value: i, child: Text(powerUpLabels[i])),
              ],
              (v) => setState(() => _zero = _withZero(powerUpZero: v ?? 0)),
            ),
            _boolRow(
              l.pushbuttonZero,
              _zero.pushbuttonZeroEnabled,
              (v) =>
                  setState(() => _zero = _withZero(pushbuttonZeroEnabled: v)),
            ),
          ],
        ),
        _group(
          title: '皮重配置',
          subtitle: '按键去皮 / 预置皮重',
          count: 2,
          groupKey: 'scale-tare',
          initiallyExpanded: true,
          children: [
            _boolRow(
              l.pushbuttonTare,
              _tare.pushbuttonTareEnabled,
              (v) =>
                  setState(() => _tare = _withTare(pushbuttonTareEnabled: v)),
            ),
            _boolRow(
              l.presetTare,
              _tare.presetTareEnabled,
              (v) => setState(() => _tare = _withTare(presetTareEnabled: v)),
            ),
          ],
        ),
        _group(
          title: l.calibration,
          subtitle: '物理砝码单位 / 零点 / 多点量程 / 逐步法',
          count: 8,
          groupKey: 'scale-calibration',
          initiallyExpanded: false,
          children: [
            _paramRow(
              label: '砝码标定单位',
              control: DropdownButtonFormField<int>(
                key: const Key('calibration-unit'),
                value: _scale.calibrationUnit
                    .clamp(0, units.length - 1)
                    .toInt(),
                decoration: _deco(),
                items: [
                  for (var i = 0; i < units.length; i++)
                    DropdownMenuItem(value: i, child: Text(units[i])),
                ],
                onChanged: _activeCalibration != _PanelCalibrationType.none
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => _scale = _scale.copyWith(
                                calibrationUnit: value,
                              ));
                        }
                      },
              ),
              showScope: false,
            ),
            _paramRow(
              label:
                  '实时毛重  ${_isWeightStable ? '稳定' : '未稳定'}',
              control: _readonly(
                '${_convertWeight(_liveWeight, _liveWeightUnit, _scale.calibrationUnit).toStringAsFixed(2)} $_calibrationUnit',
              ),
              showScope: false,
            ),
            _paramRow(
              label: '量程线性模式',
              control: DropdownButtonFormField<int>(
                key: const Key('calibration-linear-mode'),
                value: _linearMode,
                decoration: _deco(),
                items: [
                  DropdownMenuItem(value: 0, child: Text(l.linearDisabled)),
                  DropdownMenuItem(value: 1, child: Text(l.linear3Point)),
                  DropdownMenuItem(value: 2, child: Text(l.linear4Point)),
                  DropdownMenuItem(value: 3, child: Text(l.linear5Point)),
                ],
                onChanged: _activeCalibration != _PanelCalibrationType.none
                    ? null
                    : (value) {
                        if (value != null) setState(() => _linearMode = value);
                      },
              ),
              showScope: false,
            ),
            for (var i = 0; i <= _linearMode; i++)
              _paramRow(
                label: '第 ${i + 1} 点砝码重量（$_calibrationUnit）',
                control: TextFormField(
                  key: Key('calibration-span-load-${i + 1}'),
                  controller: _spanLoads[i],
                  readOnly: _activeCalibration != _PanelCalibrationType.none,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: Color(0xFFEFFAFF), fontSize: 13),
                  decoration: _deco(),
                ),
                showScope: false,
              ),
            _paramRow(
              label: '逐步法砝码/替代物料重量（$_calibrationUnit）',
              control: TextFormField(
                key: const Key('calibration-step-load'),
                controller: _stepLoad,
                readOnly: _activeCalibration != _PanelCalibrationType.none &&
                    _activeCalibration != _PanelCalibrationType.step,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Color(0xFFEFFAFF), fontSize: 13),
                decoration: _deco(),
              ),
              showScope: false,
            ),
            if (_calibrationStatus?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  _calibrationStatus!,
                  style: const TextStyle(color: Color(0xFF62E3E5)),
                ),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (_activeCalibration == _PanelCalibrationType.none) ...[
                  OutlinedButton(
                    key: const Key('calibration-start-zero'),
                    onPressed: _calibrationBusy
                        ? null
                        : () => _runCalibration(
                              type: _PanelCalibrationType.zero,
                            ),
                    child: Text(l.calZero),
                  ),
                  OutlinedButton(
                    key: const Key('calibration-start-span'),
                    onPressed: _calibrationBusy
                        ? null
                        : () => _runCalibration(
                              type: _PanelCalibrationType.span,
                            ),
                    child: Text(l.calSpan),
                  ),
                  OutlinedButton(
                    key: const Key('calibration-start-step'),
                    onPressed: _calibrationBusy
                        ? null
                        : () => _runCalibration(
                              type: _PanelCalibrationType.step,
                            ),
                    child: const Text('开始逐步法'),
                  ),
                ],
                if (_activeCalibration == _PanelCalibrationType.span &&
                        _calibrationState == 6 &&
                        _completedSpanSteps < _linearMode + 1 ||
                    _activeCalibration == _PanelCalibrationType.step &&
                        _stepPhase == _PanelStepPhase.nextLoad)
                  OutlinedButton(
                    key: const Key('calibration-add-load'),
                    onPressed: _calibrationBusy ? null : _addCalibrationLoad,
                    child: Text(_activeCalibration == _PanelCalibrationType.step
                        ? '继续加码并开始下一点'
                        : '确认加载下一点'),
                  ),
                if (_activeCalibration == _PanelCalibrationType.step &&
                    _stepPhase == _PanelStepPhase.weightLoaded &&
                    _calibrationState == 2)
                  OutlinedButton(
                    key: const Key('calibration-prepare-remove'),
                    onPressed: () => setState(() {
                      _stepPhase = _PanelStepPhase.removeWaiting;
                      _calibrationComplete = false;
                      _calibrationStatus = '请移除砝码，然后确认移除。';
                    }),
                    child: const Text('移除砝码'),
                  ),
                if (_activeCalibration == _PanelCalibrationType.step &&
                    _stepPhase == _PanelStepPhase.removeWaiting)
                  OutlinedButton(
                    key: const Key('calibration-remove-confirm'),
                    onPressed: _calibrationBusy ? null : _confirmStepRemoval,
                    child: const Text('确认已移除砝码'),
                  ),
                if (_activeCalibration == _PanelCalibrationType.step &&
                    _stepPhase == _PanelStepPhase.substituteWaiting)
                  OutlinedButton(
                    key: const Key('calibration-substitute-confirm'),
                    onPressed:
                        _calibrationBusy ? null : _confirmStepSubstitute,
                    child: const Text('确认替代物料'),
                  ),
                if (_calibrationState == 3 &&
                    _activeCalibration != _PanelCalibrationType.none) ...[
                  OutlinedButton(
                    onPressed: _calibrationBusy
                        ? null
                        : () => _acceptDynamicCalibration(true),
                    child: const Text('接受动态校正'),
                  ),
                  OutlinedButton(
                    onPressed: _calibrationBusy
                        ? null
                        : () => _acceptDynamicCalibration(false),
                    child: const Text('拒绝动态校正'),
                  ),
                ],
                if (_calibrationComplete &&
                    (_calibrationState == 2 ||
                        _calibrationState == 3 &&
                            _dynamicCalibrationAccepted))
                  FilledButton(
                    key: const Key('calibration-save'),
                    onPressed: _calibrationBusy ? null : _saveCalibration,
                    child: Text(l.save),
                  ),
                if (_activeCalibration != _PanelCalibrationType.none)
                  OutlinedButton(
                    key: const Key('calibration-abort'),
                    onPressed: _calibrationBusy ? null : _abortCalibration,
                    child: Text(l.cancel),
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  ZeroConfig _withZero({
    int? autoZeroMode,
    double? autoZeroRangeD,
    double? underloadRangeD,
    int? powerUpZero,
    double? powerUpZeroPosPct,
    double? powerUpZeroNegPct,
    bool? pushbuttonZeroEnabled,
    double? pushbuttonZeroPosPct,
    double? pushbuttonZeroNegPct,
  }) =>
      ZeroConfig(
        autoZeroMode: autoZeroMode ?? _zero.autoZeroMode,
        autoZeroRangeD: autoZeroRangeD ?? _zero.autoZeroRangeD,
        underloadRangeD: underloadRangeD ?? _zero.underloadRangeD,
        powerUpZero: powerUpZero ?? _zero.powerUpZero,
        powerUpZeroPosPct: powerUpZeroPosPct ?? _zero.powerUpZeroPosPct,
        powerUpZeroNegPct: powerUpZeroNegPct ?? _zero.powerUpZeroNegPct,
        pushbuttonZeroEnabled:
            pushbuttonZeroEnabled ?? _zero.pushbuttonZeroEnabled,
        pushbuttonZeroPosPct:
            pushbuttonZeroPosPct ?? _zero.pushbuttonZeroPosPct,
        pushbuttonZeroNegPct:
            pushbuttonZeroNegPct ?? _zero.pushbuttonZeroNegPct,
      );

  TareConfig _withTare(
          {bool? pushbuttonTareEnabled, bool? presetTareEnabled}) =>
      TareConfig(
        pushbuttonTareEnabled:
            pushbuttonTareEnabled ?? _tare.pushbuttonTareEnabled,
        presetTareEnabled: presetTareEnabled ?? _tare.presetTareEnabled,
      );

  // ── 2. 滤波 ────────────────────────────────────────────────

  Widget _filterTab(AppLocalizations l) {
    final lpLabels = [l.veryLight, l.light, l.medium, l.heavy];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _group(
          title: '低通滤波',
          subtitle: '抑制高频噪声',
          count: 1,
          groupKey: 'filter-lp',
          initiallyExpanded: true,
          children: [
            _dropRow<int>(
              l.lowPassFilter,
              _filter.lowPassLevel.clamp(0, 3).toInt(),
              [
                for (var i = 0; i < lpLabels.length; i++)
                  DropdownMenuItem(value: i, child: Text(lpLabels[i])),
              ],
              (v) =>
                  setState(() => _filter = _withFilter(lowPassLevel: v ?? 0)),
            ),
          ],
        ),
        _group(
          title: '陷波滤波',
          subtitle: '消除固定频率干扰',
          count: 2,
          groupKey: 'filter-notch',
          initiallyExpanded: true,
          children: [
            _boolRow(
              '陷波启用',
              _filter.notchEnabled,
              (v) => setState(() => _filter = _withFilter(notchEnabled: v)),
            ),
            _numRow(l.frequencyHz, _filter.notchFrequency, (v) {
              setState(() => _filter = _withFilter(notchFrequency: v));
            }),
          ],
        ),
        _group(
          title: '自适应滤波',
          subtitle: '根据信号动态调整',
          count: 2,
          groupKey: 'filter-adaptive',
          initiallyExpanded: true,
          children: [
            _boolRow(
              '自适应启用',
              _filter.adaptiveEnabled,
              (v) => setState(() => _filter = _withFilter(adaptiveEnabled: v)),
            ),
            _numRow(l.rangeD, _filter.adaptiveRangeD, (v) {
              setState(() => _filter = _withFilter(adaptiveRangeD: v));
            }),
          ],
        ),
        _group(
          title: '稳定性检测',
          subtitle: '判定稳定 / 判定超时',
          count: 3,
          groupKey: 'filter-stability',
          initiallyExpanded: true,
          children: [
            _numRow('${l.motionRange} (d)', _filter.motionRangeD, (v) {
              setState(() => _filter = _withFilter(motionRangeD: v));
            }),
            _numRow('${l.motionDetectTime} (s)', _filter.motionDetectTime, (v) {
              setState(() => _filter = _withFilter(motionDetectTime: v));
            }),
            _numRow('${l.stabilityTimeout} (s)', _filter.stabilityTimeout, (v) {
              setState(() => _filter = _withFilter(stabilityTimeout: v));
            }),
          ],
        ),
      ],
    );
  }

  FilterStabilityConfig _withFilter({
    int? lowPassLevel,
    bool? notchEnabled,
    double? notchFrequency,
    bool? adaptiveEnabled,
    double? adaptiveRangeD,
    double? motionRangeD,
    double? motionDetectTime,
    double? stabilityTimeout,
  }) =>
      FilterStabilityConfig(
        lowPassLevel: lowPassLevel ?? _filter.lowPassLevel,
        notchEnabled: notchEnabled ?? _filter.notchEnabled,
        notchFrequency: notchFrequency ?? _filter.notchFrequency,
        adaptiveEnabled: adaptiveEnabled ?? _filter.adaptiveEnabled,
        adaptiveRangeD: adaptiveRangeD ?? _filter.adaptiveRangeD,
        motionRangeD: motionRangeD ?? _filter.motionRangeD,
        motionDetectTime: motionDetectTime ?? _filter.motionDetectTime,
        stabilityTimeout: stabilityTimeout ?? _filter.stabilityTimeout,
      );

  // ── 3. 配方 ────────────────────────────────────────────────

  Widget _recipeTab(AppLocalizations l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 顶部：小信息条提示当前作用
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF0D2535),
            border: const Border(
              left: BorderSide(color: Color(0xFF2BD98A), width: 4),
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, size: 14, color: Color(0xFF2BD98A)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '配方参数 · 随配方切换整体替换',
                  style: TextStyle(
                    color: Color(0xFF2BD98A),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _group(
          title: '当前子系统配方',
          subtitle: '加载后在下方直接编辑参数，保存可另存为新配方',
          count: _recipes.length,
          groupKey: 'recipe-library',
          initiallyExpanded: true,
          children: [
            if (_recipesLoading)
              const Center(child: CircularProgressIndicator())
            else if (_recipesError != null)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _recipesError!,
                      style: const TextStyle(color: Color(0xFFFF8F85)),
                    ),
                  ),
                  IconButton(
                    tooltip: l.refresh,
                    onPressed: _loadRecipes,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              )
            else if (_recipes.isEmpty)
              _readonly('当前子系统暂无配方，可调整参数后使用“另存为”创建')
            else
              for (final recipe in _recipes)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    recipe['name'] as String? ?? '未命名',
                    style: const TextStyle(color: Color(0xFFEFFAFF)),
                  ),
                  subtitle: Text(
                    AppStateProvider.read(context)
                                .getActiveRecipeName(widget.mapping.subsystemId) ==
                            recipe['name']
                        ? '使用中'
                        : '未加载',
                    style: const TextStyle(color: Color(0xFF91ABBA)),
                  ),
                  trailing: Wrap(
                    children: [
                      IconButton(
                        tooltip: '加载配方',
                        onPressed: () =>
                            _activateRecipe(recipe, editAfterLoad: true),
                        icon: const Icon(Icons.download_outlined, size: 18),
                      ),
                      IconButton(
                        tooltip: l.delete,
                        onPressed: () => _deleteRecipe(recipe),
                        icon: const Icon(Icons.delete_outline, size: 18),
                      ),
                    ],
                  ),
                ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _recipesLoading ? null : _showRecipePicker,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('从配方列表加载'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_appType == 1)
          ..._fillingRecipeGroups(l)
        else
          ..._liwRecipeGroups(l),
      ],
    );
  }

  List<Widget> _liwRecipeGroups(AppLocalizations l) {
    final modeLabels = [l.continuous, l.batch, l.systemId];
    final subModeLabels = [l.flowControl, l.fixedFrequency];
    return [
      _group(
        title: '基础',
        subtitle: '运行模式',
        count: 1,
        groupKey: 'liw-base',
        initiallyExpanded: true,
        children: [
          _dropRow<int>(
            l.mode,
            _liwBase.mode,
            [
              for (var i = 0; i < modeLabels.length; i++)
                DropdownMenuItem(value: i, child: Text(modeLabels[i])),
            ],
            (v) => setState(() => _liwBase =
                LiwBaseConfig(mode: v ?? 0, subMode: _liwBase.subMode)),
          ),
          if (_liwBase.mode == 0)
            _dropRow<int>(
              l.subMode,
              _liwBase.subMode,
              [
                for (var i = 0; i < subModeLabels.length; i++)
                  DropdownMenuItem(value: i, child: Text(subModeLabels[i])),
              ],
              (v) => setState(() => _liwBase =
                  LiwBaseConfig(mode: _liwBase.mode, subMode: v ?? 0)),
            ),
        ],
      ),
      _group(
        title: '系统',
        subtitle: '安全限 / 料斗 / 目标流量',
        count: 6,
        groupKey: 'liw-system',
        initiallyExpanded: true,
        children: [
          _numRow(l.safetyLimit, _liwSystem.safetyLimit, (v) {
            setState(() => _liwSystem = LiwSystemConfig(
                  safetyLimit: v,
                  hopperMin: _liwSystem.hopperMin,
                  hopperMax: _liwSystem.hopperMax,
                  targetFlow: _liwSystem.targetFlow,
                  targetControlRate: _liwSystem.targetControlRate,
                  preRefill: _liwSystem.preRefill,
                ));
          }),
          _numRow(l.hopperMin, _liwSystem.hopperMin, (v) {
            setState(() => _liwSystem = LiwSystemConfig(
                  safetyLimit: _liwSystem.safetyLimit,
                  hopperMin: v,
                  hopperMax: _liwSystem.hopperMax,
                  targetFlow: _liwSystem.targetFlow,
                  targetControlRate: _liwSystem.targetControlRate,
                  preRefill: _liwSystem.preRefill,
                ));
          }),
          _numRow(l.hopperMax, _liwSystem.hopperMax, (v) {
            setState(() => _liwSystem = LiwSystemConfig(
                  safetyLimit: _liwSystem.safetyLimit,
                  hopperMin: _liwSystem.hopperMin,
                  hopperMax: v,
                  targetFlow: _liwSystem.targetFlow,
                  targetControlRate: _liwSystem.targetControlRate,
                  preRefill: _liwSystem.preRefill,
                ));
          }),
          _numRow(l.targetFlow, _liwSystem.targetFlow, (v) {
            setState(() => _liwSystem = LiwSystemConfig(
                  safetyLimit: _liwSystem.safetyLimit,
                  hopperMin: _liwSystem.hopperMin,
                  hopperMax: _liwSystem.hopperMax,
                  targetFlow: v,
                  targetControlRate: _liwSystem.targetControlRate,
                  preRefill: _liwSystem.preRefill,
                ));
          }),
          _numRow(l.targetControlRate, _liwSystem.targetControlRate, (v) {
            setState(() => _liwSystem = LiwSystemConfig(
                  safetyLimit: _liwSystem.safetyLimit,
                  hopperMin: _liwSystem.hopperMin,
                  hopperMax: _liwSystem.hopperMax,
                  targetFlow: _liwSystem.targetFlow,
                  targetControlRate: v,
                  preRefill: _liwSystem.preRefill,
                ));
          }),
          _boolRow(
            l.preRefill,
            _liwSystem.preRefill,
            (v) => setState(() => _liwSystem = LiwSystemConfig(
                  safetyLimit: _liwSystem.safetyLimit,
                  hopperMin: _liwSystem.hopperMin,
                  hopperMax: _liwSystem.hopperMax,
                  targetFlow: _liwSystem.targetFlow,
                  targetControlRate: _liwSystem.targetControlRate,
                  preRefill: v,
                )),
          ),
        ],
      ),
      _group(
        title: '系统辨识',
        subtitle: '调整范围 / 智能步进',
        count: 5,
        groupKey: 'liw-sysid',
        initiallyExpanded: false,
        children: [
          _numRow(l.adjustRangeLower, _liwSysId.adjustRangeLower, (v) {
            setState(() => _liwSysId = LiwSystemIdConfig(
                  adjustRangeLower: v,
                  adjustRangeUpper: _liwSysId.adjustRangeUpper,
                  smartStepControl: _liwSysId.smartStepControl,
                  stepDuration: _liwSysId.stepDuration,
                  filterWindow: _liwSysId.filterWindow,
                ));
          }),
          _numRow(l.adjustRangeUpper, _liwSysId.adjustRangeUpper, (v) {
            setState(() => _liwSysId = LiwSystemIdConfig(
                  adjustRangeLower: _liwSysId.adjustRangeLower,
                  adjustRangeUpper: v,
                  smartStepControl: _liwSysId.smartStepControl,
                  stepDuration: _liwSysId.stepDuration,
                  filterWindow: _liwSysId.filterWindow,
                ));
          }),
          _boolRow(
            l.smartStepControl,
            _liwSysId.smartStepControl,
            (v) => setState(() => _liwSysId = LiwSystemIdConfig(
                  adjustRangeLower: _liwSysId.adjustRangeLower,
                  adjustRangeUpper: _liwSysId.adjustRangeUpper,
                  smartStepControl: v,
                  stepDuration: _liwSysId.stepDuration,
                  filterWindow: _liwSysId.filterWindow,
                )),
          ),
          _numRow(l.stepDuration, _liwSysId.stepDuration, (v) {
            setState(() => _liwSysId = LiwSystemIdConfig(
                  adjustRangeLower: _liwSysId.adjustRangeLower,
                  adjustRangeUpper: _liwSysId.adjustRangeUpper,
                  smartStepControl: _liwSysId.smartStepControl,
                  stepDuration: v,
                  filterWindow: _liwSysId.filterWindow,
                ));
          }),
          _numRow(l.filterWindowSysId, _liwSysId.filterWindow, (v) {
            setState(() => _liwSysId = LiwSystemIdConfig(
                  adjustRangeLower: _liwSysId.adjustRangeLower,
                  adjustRangeUpper: _liwSysId.adjustRangeUpper,
                  smartStepControl: _liwSysId.smartStepControl,
                  stepDuration: _liwSysId.stepDuration,
                  filterWindow: v,
                ));
          }),
        ],
      ),
      _group(
        title: '控制器 PID',
        subtitle: '调参模式 / 增益 / 最大流量',
        count: 7,
        groupKey: 'liw-pid',
        initiallyExpanded: false,
        children: [
          _dropRow<int>(
            l.tuningMode,
            _liwCtrl.tuningMode,
            [
              DropdownMenuItem(value: 0, child: Text(l.auto)),
              DropdownMenuItem(value: 1, child: Text(l.manual)),
            ],
            (v) => setState(() => _liwCtrl = LiwControllerConfig(
                  tuningMode: v ?? 0,
                  filterWindow: _liwCtrl.filterWindow,
                  kp: _liwCtrl.kp,
                  ki: _liwCtrl.ki,
                  kd: _liwCtrl.kd,
                  maxFlow: _liwCtrl.maxFlow,
                  startupTime: _liwCtrl.startupTime,
                )),
          ),
          _numRow(l.filterWindowCtrl, _liwCtrl.filterWindow, (v) {
            setState(() => _liwCtrl = LiwControllerConfig(
                  tuningMode: _liwCtrl.tuningMode,
                  filterWindow: v,
                  kp: _liwCtrl.kp,
                  ki: _liwCtrl.ki,
                  kd: _liwCtrl.kd,
                  maxFlow: _liwCtrl.maxFlow,
                  startupTime: _liwCtrl.startupTime,
                ));
          }),
          _numRow('Kp', _liwCtrl.kp, (v) {
            setState(() => _liwCtrl = LiwControllerConfig(
                  tuningMode: _liwCtrl.tuningMode,
                  filterWindow: _liwCtrl.filterWindow,
                  kp: v,
                  ki: _liwCtrl.ki,
                  kd: _liwCtrl.kd,
                  maxFlow: _liwCtrl.maxFlow,
                  startupTime: _liwCtrl.startupTime,
                ));
          }),
          _numRow('Ki', _liwCtrl.ki, (v) {
            setState(() => _liwCtrl = LiwControllerConfig(
                  tuningMode: _liwCtrl.tuningMode,
                  filterWindow: _liwCtrl.filterWindow,
                  kp: _liwCtrl.kp,
                  ki: v,
                  kd: _liwCtrl.kd,
                  maxFlow: _liwCtrl.maxFlow,
                  startupTime: _liwCtrl.startupTime,
                ));
          }),
          _numRow('Kd', _liwCtrl.kd, (v) {
            setState(() => _liwCtrl = LiwControllerConfig(
                  tuningMode: _liwCtrl.tuningMode,
                  filterWindow: _liwCtrl.filterWindow,
                  kp: _liwCtrl.kp,
                  ki: _liwCtrl.ki,
                  kd: v,
                  maxFlow: _liwCtrl.maxFlow,
                  startupTime: _liwCtrl.startupTime,
                ));
          }),
          _numRow(l.maxFlow, _liwCtrl.maxFlow, (v) {
            setState(() => _liwCtrl = LiwControllerConfig(
                  tuningMode: _liwCtrl.tuningMode,
                  filterWindow: _liwCtrl.filterWindow,
                  kp: _liwCtrl.kp,
                  ki: _liwCtrl.ki,
                  kd: _liwCtrl.kd,
                  maxFlow: v,
                  startupTime: _liwCtrl.startupTime,
                ));
          }),
          _numRow(l.startupTime, _liwCtrl.startupTime, (v) {
            setState(() => _liwCtrl = LiwControllerConfig(
                  tuningMode: _liwCtrl.tuningMode,
                  filterWindow: _liwCtrl.filterWindow,
                  kp: _liwCtrl.kp,
                  ki: _liwCtrl.ki,
                  kd: _liwCtrl.kd,
                  maxFlow: _liwCtrl.maxFlow,
                  startupTime: v,
                ));
          }),
        ],
      ),
      _group(
        title: '回填',
        subtitle: '上下限 / 控制模式',
        count: 6,
        groupKey: 'liw-refill',
        initiallyExpanded: false,
        children: [
          _dropRow<int>(
            l.mode,
            _liwRefill.mode,
            [
              DropdownMenuItem(value: 0, child: Text(l.auto)),
              DropdownMenuItem(value: 1, child: Text(l.manual)),
            ],
            (v) => setState(() => _liwRefill = LiwRefillConfig(
                  mode: v ?? 0,
                  lowerLimit: _liwRefill.lowerLimit,
                  upperLimit: _liwRefill.upperLimit,
                  controlMode: _liwRefill.controlMode,
                  controlSetpoint: _liwRefill.controlSetpoint,
                  stabilizeTime: _liwRefill.stabilizeTime,
                )),
          ),
          _numRow(l.lowerLimit, _liwRefill.lowerLimit, (v) {
            setState(() => _liwRefill = LiwRefillConfig(
                  mode: _liwRefill.mode,
                  lowerLimit: v,
                  upperLimit: _liwRefill.upperLimit,
                  controlMode: _liwRefill.controlMode,
                  controlSetpoint: _liwRefill.controlSetpoint,
                  stabilizeTime: _liwRefill.stabilizeTime,
                ));
          }),
          _numRow(l.upperLimit, _liwRefill.upperLimit, (v) {
            setState(() => _liwRefill = LiwRefillConfig(
                  mode: _liwRefill.mode,
                  lowerLimit: _liwRefill.lowerLimit,
                  upperLimit: v,
                  controlMode: _liwRefill.controlMode,
                  controlSetpoint: _liwRefill.controlSetpoint,
                  stabilizeTime: _liwRefill.stabilizeTime,
                ));
          }),
          _dropRow<int>(
            l.controlMode,
            _liwRefill.controlMode,
            [
              DropdownMenuItem(value: 0, child: Text(l.fixed)),
              DropdownMenuItem(value: 1, child: Text(l.lastFreq)),
              DropdownMenuItem(value: 2, child: Text(l.smart)),
            ],
            (v) => setState(() => _liwRefill = LiwRefillConfig(
                  mode: _liwRefill.mode,
                  lowerLimit: _liwRefill.lowerLimit,
                  upperLimit: _liwRefill.upperLimit,
                  controlMode: v ?? 0,
                  controlSetpoint: _liwRefill.controlSetpoint,
                  stabilizeTime: _liwRefill.stabilizeTime,
                )),
          ),
          _numRow(l.controlSetpoint, _liwRefill.controlSetpoint, (v) {
            setState(() => _liwRefill = LiwRefillConfig(
                  mode: _liwRefill.mode,
                  lowerLimit: _liwRefill.lowerLimit,
                  upperLimit: _liwRefill.upperLimit,
                  controlMode: _liwRefill.controlMode,
                  controlSetpoint: v,
                  stabilizeTime: _liwRefill.stabilizeTime,
                ));
          }),
          _numRow(l.stabilizeTime, _liwRefill.stabilizeTime, (v) {
            setState(() => _liwRefill = LiwRefillConfig(
                  mode: _liwRefill.mode,
                  lowerLimit: _liwRefill.lowerLimit,
                  upperLimit: _liwRefill.upperLimit,
                  controlMode: _liwRefill.controlMode,
                  controlSetpoint: _liwRefill.controlSetpoint,
                  stabilizeTime: v,
                ));
          }),
        ],
      ),
      _group(
        title: '目标值',
        subtitle: '批次目标 / 在途量 / 细加料',
        count: 4,
        groupKey: 'liw-target',
        initiallyExpanded: false,
        children: [
          _numRow(l.batchTarget, _liwTarget.batchTarget, (v) {
            setState(() => _liwTarget = LiwTargetValuesConfig(
                  batchTarget: v,
                  inFlight: _liwTarget.inFlight,
                  fineFeedThreshold: _liwTarget.fineFeedThreshold,
                  fineFeedFlow: _liwTarget.fineFeedFlow,
                ));
          }),
          _numRow(l.inFlight, _liwTarget.inFlight, (v) {
            setState(() => _liwTarget = LiwTargetValuesConfig(
                  batchTarget: _liwTarget.batchTarget,
                  inFlight: v,
                  fineFeedThreshold: _liwTarget.fineFeedThreshold,
                  fineFeedFlow: _liwTarget.fineFeedFlow,
                ));
          }),
          _numRow(l.fineFeedThreshold, _liwTarget.fineFeedThreshold, (v) {
            setState(() => _liwTarget = LiwTargetValuesConfig(
                  batchTarget: _liwTarget.batchTarget,
                  inFlight: _liwTarget.inFlight,
                  fineFeedThreshold: v,
                  fineFeedFlow: _liwTarget.fineFeedFlow,
                ));
          }),
          _numRow(l.fineFeedFlow, _liwTarget.fineFeedFlow, (v) {
            setState(() => _liwTarget = LiwTargetValuesConfig(
                  batchTarget: _liwTarget.batchTarget,
                  inFlight: _liwTarget.inFlight,
                  fineFeedThreshold: _liwTarget.fineFeedThreshold,
                  fineFeedFlow: v,
                ));
          }),
        ],
      ),
      _group(
        title: '公差检查',
        subtitle: '预检延时 / 稳定超时 / 公差',
        count: 3,
        groupKey: 'liw-tol',
        initiallyExpanded: false,
        children: [
          _numRow(l.preCheckDelay, _liwTol.preCheckDelay, (v) {
            setState(() => _liwTol = LiwToleranceCheckConfig(
                  preCheckDelay: v,
                  stabilityTimeout: _liwTol.stabilityTimeout,
                  tolerance: _liwTol.tolerance,
                ));
          }),
          _numRow(l.stabilityTimeout, _liwTol.stabilityTimeout, (v) {
            setState(() => _liwTol = LiwToleranceCheckConfig(
                  preCheckDelay: _liwTol.preCheckDelay,
                  stabilityTimeout: v,
                  tolerance: _liwTol.tolerance,
                ));
          }),
          _numRow(l.tolerance, _liwTol.tolerance, (v) {
            setState(() => _liwTol = LiwToleranceCheckConfig(
                  preCheckDelay: _liwTol.preCheckDelay,
                  stabilityTimeout: _liwTol.stabilityTimeout,
                  tolerance: v,
                ));
          }),
        ],
      ),
      _group(
        title: '排空',
        subtitle: '报警自动停止 / 控制设定点',
        count: 2,
        groupKey: 'liw-empty',
        initiallyExpanded: false,
        children: [
          _boolRow(
            l.autoStopAtAlarm,
            _liwEmpty.autoStopAtAlarm,
            (v) => setState(() => _liwEmpty = LiwEmptyingConfig(
                  autoStopAtAlarm: v,
                  controlSetpoint: _liwEmpty.controlSetpoint,
                )),
          ),
          _numRow(l.controlSetpoint, _liwEmpty.controlSetpoint, (v) {
            setState(() => _liwEmpty = LiwEmptyingConfig(
                  autoStopAtAlarm: _liwEmpty.autoStopAtAlarm,
                  controlSetpoint: v,
                ));
          }),
        ],
      ),
      _group(
        title: '报警配置',
        subtitle: '控制率上下限 / 回填超时',
        count: 4,
        groupKey: 'liw-warn',
        initiallyExpanded: false,
        children: [
          _numRow(l.controlRateLower, _liwWarn.controlRateLower, (v) {
            setState(() => _liwWarn = LiwWarningConfig(
                  controlRateLower: v,
                  controlRateUpper: _liwWarn.controlRateUpper,
                  refillTimeout: _liwWarn.refillTimeout,
                  stopOnError: _liwWarn.stopOnError,
                ));
          }),
          _numRow(l.controlRateUpper, _liwWarn.controlRateUpper, (v) {
            setState(() => _liwWarn = LiwWarningConfig(
                  controlRateLower: _liwWarn.controlRateLower,
                  controlRateUpper: v,
                  refillTimeout: _liwWarn.refillTimeout,
                  stopOnError: _liwWarn.stopOnError,
                ));
          }),
          _numRow(l.refillTimeout, _liwWarn.refillTimeout, (v) {
            setState(() => _liwWarn = LiwWarningConfig(
                  controlRateLower: _liwWarn.controlRateLower,
                  controlRateUpper: _liwWarn.controlRateUpper,
                  refillTimeout: v,
                  stopOnError: _liwWarn.stopOnError,
                ));
          }),
          _boolRow(
            l.stopOnError,
            _liwWarn.stopOnError,
            (v) => setState(() => _liwWarn = LiwWarningConfig(
                  controlRateLower: _liwWarn.controlRateLower,
                  controlRateUpper: _liwWarn.controlRateUpper,
                  refillTimeout: _liwWarn.refillTimeout,
                  stopOnError: v,
                )),
          ),
        ],
      ),
      _group(
        title: '流量监控',
        subtitle: '评估窗口 / 偏差 / 突变阈值',
        count: 3,
        groupKey: 'liw-flow',
        initiallyExpanded: false,
        children: [
          _numRow(l.evaluationWindow, _liwFlow.evaluationWindow, (v) {
            setState(() => _liwFlow = LiwFlowMonitorConfig(
                  evaluationWindow: v,
                  deviationThreshold: _liwFlow.deviationThreshold,
                  surgeThreshold: _liwFlow.surgeThreshold,
                ));
          }),
          _numRow(l.deviationThreshold, _liwFlow.deviationThreshold, (v) {
            setState(() => _liwFlow = LiwFlowMonitorConfig(
                  evaluationWindow: _liwFlow.evaluationWindow,
                  deviationThreshold: v,
                  surgeThreshold: _liwFlow.surgeThreshold,
                ));
          }),
          _numRow(l.surgeThreshold, _liwFlow.surgeThreshold, (v) {
            setState(() => _liwFlow = LiwFlowMonitorConfig(
                  evaluationWindow: _liwFlow.evaluationWindow,
                  deviationThreshold: _liwFlow.deviationThreshold,
                  surgeThreshold: v,
                ));
          }),
        ],
      ),
      _group(
        title: '高级配置',
        subtitle: '互锁',
        count: 2,
        groupKey: 'liw-adv',
        initiallyExpanded: false,
        children: [
          _boolRow(
            l.interlockEnabled,
            _liwAdv.interlockEnabled,
            (v) => setState(() => _liwAdv = LiwAdvancedConfig(
                  interlockEnabled: v,
                  interlockDelay: _liwAdv.interlockDelay,
                )),
          ),
          _numRow(l.interlockDelay, _liwAdv.interlockDelay, (v) {
            setState(() => _liwAdv = LiwAdvancedConfig(
                  interlockEnabled: _liwAdv.interlockEnabled,
                  interlockDelay: v,
                ));
          }),
        ],
      ),
      _group(
        title: '统计',
        subtitle: '采样周期 / 采样公差',
        count: 2,
        groupKey: 'liw-stats',
        initiallyExpanded: false,
        children: [
          _numRow(l.samplePeriod, _liwStats.samplePeriod, (v) {
            setState(() => _liwStats = LiwStatsConfig(
                  samplePeriod: v,
                  sampleTolerance: _liwStats.sampleTolerance,
                ));
          }),
          _numRow(l.sampleTolerance, _liwStats.sampleTolerance, (v) {
            setState(() => _liwStats = LiwStatsConfig(
                  samplePeriod: _liwStats.samplePeriod,
                  sampleTolerance: v,
                ));
          }),
        ],
      ),
    ];
  }

  List<Widget> _fillingRecipeGroups(AppLocalizations l) {
    final workModeLabels = [
      l.fill,
      l.fillEmpty,
      l.dispense,
      l.refillDispense,
      l.absoluteValue,
    ];
    final powerFailLabels = [l.idle, l.pause];
    final startDelayLabels = [l.disabled, l.min5, l.min15, l.min30];
    return [
      _group(
        title: '通用',
        subtitle: '工作模式 / 掉电恢复 / 启动延时',
        count: 5,
        groupKey: 'fill-general',
        initiallyExpanded: true,
        children: [
          _dropRow<int>(
            l.workMode,
            _fillSys.workMode,
            [
              for (var i = 0; i < workModeLabels.length; i++)
                DropdownMenuItem(value: i, child: Text(workModeLabels[i])),
            ],
            (v) => setState(() => _fillSys = FillingSystemConfig(
                  workMode: v ?? 0,
                  feedSpeed: _fillSys.feedSpeed,
                  outputType: _fillSys.outputType,
                )),
          ),
          _dropRow<int>(
            l.powerFailRecovery,
            _fillGen.powerFailRecovery,
            [
              for (var i = 0; i < powerFailLabels.length; i++)
                DropdownMenuItem(value: i, child: Text(powerFailLabels[i])),
            ],
            (v) => setState(() => _fillGen = FillingGeneralConfig(
                  powerFailRecovery: v ?? 0,
                  startDelay: _fillGen.startDelay,
                )),
          ),
          _dropRow<int>(
            l.startDelay,
            _fillGen.startDelay,
            [
              for (var i = 0; i < startDelayLabels.length; i++)
                DropdownMenuItem(value: i, child: Text(startDelayLabels[i])),
            ],
            (v) => setState(() => _fillGen = FillingGeneralConfig(
                  powerFailRecovery: _fillGen.powerFailRecovery,
                  startDelay: v ?? 0,
                )),
          ),
          _dropRow<int>(
            l.feedSpeed,
            _fillSys.feedSpeed,
            [
              DropdownMenuItem(value: 0, child: Text(l.single)),
              DropdownMenuItem(value: 1, child: Text(l.dual)),
            ],
            (v) => setState(() => _fillSys = FillingSystemConfig(
                  workMode: _fillSys.workMode,
                  feedSpeed: v ?? 0,
                  outputType: _fillSys.outputType,
                )),
          ),
          _dropRow<int>(
            '输出方式',
            _fillSys.outputType,
            const [
              DropdownMenuItem(value: 0, child: Text('并行输出')),
              DropdownMenuItem(value: 1, child: Text('独立输出')),
            ],
            (v) => setState(() => _fillSys = FillingSystemConfig(
                  workMode: _fillSys.workMode,
                  feedSpeed: _fillSys.feedSpeed,
                  outputType: v ?? 0,
                )),
          ),
        ],
      ),
      _group(
        title: '目标',
        subtitle: '在途量 / 加料 / 禁止时间',
        count: 4,
        groupKey: 'fill-target',
        initiallyExpanded: true,
        children: [
          _numRow(l.inFlight, _fillTarget.inFlight, (v) {
            setState(() => _fillTarget = FillingTargetConfig(
                  inFlight: v,
                  feed: _fillTarget.feed,
                  feedInhibitTime: _fillTarget.feedInhibitTime,
                  fastFeedInhibitTime: _fillTarget.fastFeedInhibitTime,
                ));
          }),
          _numRow(l.feed, _fillTarget.feed, (v) {
            setState(() => _fillTarget = FillingTargetConfig(
                  inFlight: _fillTarget.inFlight,
                  feed: v,
                  feedInhibitTime: _fillTarget.feedInhibitTime,
                  fastFeedInhibitTime: _fillTarget.fastFeedInhibitTime,
                ));
          }),
          _numRow(l.feedInhibitTime, _fillTarget.feedInhibitTime, (v) {
            setState(() => _fillTarget = FillingTargetConfig(
                  inFlight: _fillTarget.inFlight,
                  feed: _fillTarget.feed,
                  feedInhibitTime: v,
                  fastFeedInhibitTime: _fillTarget.fastFeedInhibitTime,
                ));
          }),
          _numRow(l.fastFeedInhibitTime, _fillTarget.fastFeedInhibitTime, (v) {
            setState(() => _fillTarget = FillingTargetConfig(
                  inFlight: _fillTarget.inFlight,
                  feed: _fillTarget.feed,
                  feedInhibitTime: _fillTarget.feedInhibitTime,
                  fastFeedInhibitTime: v,
                ));
          }),
        ],
      ),
      _group(
        title: '自动去皮',
        subtitle: '启用 / 上下限',
        count: 3,
        groupKey: 'fill-autotare',
        initiallyExpanded: false,
        children: [
          _boolRow(
            l.autoTareEnabled,
            _fillAutoTare.autoTareEnabled,
            (v) => setState(() => _fillAutoTare = FillingAutoTareConfig(
                  autoTareEnabled: v,
                  containerTareUpper: _fillAutoTare.containerTareUpper,
                  containerTareLower: _fillAutoTare.containerTareLower,
                )),
          ),
          _numRow(l.containerTareUpper, _fillAutoTare.containerTareUpper, (v) {
            setState(() => _fillAutoTare = FillingAutoTareConfig(
                  autoTareEnabled: _fillAutoTare.autoTareEnabled,
                  containerTareUpper: v,
                  containerTareLower: _fillAutoTare.containerTareLower,
                ));
          }),
          _numRow(l.containerTareLower, _fillAutoTare.containerTareLower, (v) {
            setState(() => _fillAutoTare = FillingAutoTareConfig(
                  autoTareEnabled: _fillAutoTare.autoTareEnabled,
                  containerTareUpper: _fillAutoTare.containerTareUpper,
                  containerTareLower: v,
                ));
          }),
        ],
      ),
      _group(
        title: '公差',
        subtitle: '预检延时 / 稳定超时 / 正负公差',
        count: 4,
        groupKey: 'fill-tol',
        initiallyExpanded: false,
        children: [
          _numRow(l.preCheckDelay, _fillTol.preCheckDelay, (v) {
            setState(() => _fillTol = FillingToleranceConfig(
                  preCheckDelay: v,
                  stabilityTimeout: _fillTol.stabilityTimeout,
                  positiveTolerance: _fillTol.positiveTolerance,
                  negativeTolerance: _fillTol.negativeTolerance,
                ));
          }),
          _numRow(l.stabilityTimeout, _fillTol.stabilityTimeout, (v) {
            setState(() => _fillTol = FillingToleranceConfig(
                  preCheckDelay: _fillTol.preCheckDelay,
                  stabilityTimeout: v,
                  positiveTolerance: _fillTol.positiveTolerance,
                  negativeTolerance: _fillTol.negativeTolerance,
                ));
          }),
          _numRow(l.positiveTolerance, _fillTol.positiveTolerance, (v) {
            setState(() => _fillTol = FillingToleranceConfig(
                  preCheckDelay: _fillTol.preCheckDelay,
                  stabilityTimeout: _fillTol.stabilityTimeout,
                  positiveTolerance: v,
                  negativeTolerance: _fillTol.negativeTolerance,
                ));
          }),
          _numRow(l.negativeTolerance, _fillTol.negativeTolerance, (v) {
            setState(() => _fillTol = FillingToleranceConfig(
                  preCheckDelay: _fillTol.preCheckDelay,
                  stabilityTimeout: _fillTol.stabilityTimeout,
                  positiveTolerance: _fillTol.positiveTolerance,
                  negativeTolerance: v,
                ));
          }),
        ],
      ),
      _group(
        title: '溢出优化',
        subtitle: '模式 / 调整范围 / 样本数',
        count: 4,
        groupKey: 'fill-spill',
        initiallyExpanded: false,
        children: [
          _dropRow<int>(
            l.mode,
            _fillSpill.mode,
            [
              DropdownMenuItem(value: 0, child: Text(l.disabled)),
              DropdownMenuItem(value: 1, child: Text(l.auto)),
              DropdownMenuItem(value: 2, child: Text(l.manual)),
            ],
            (v) => setState(() => _fillSpill = FillingSpillOptConfig(
                  mode: v ?? 0,
                  adjustRange: _fillSpill.adjustRange,
                  adjustSamples: _fillSpill.adjustSamples,
                  adjustFactor: _fillSpill.adjustFactor,
                )),
          ),
          _numRow(l.adjustRange, _fillSpill.adjustRange, (v) {
            setState(() => _fillSpill = FillingSpillOptConfig(
                  mode: _fillSpill.mode,
                  adjustRange: v,
                  adjustSamples: _fillSpill.adjustSamples,
                  adjustFactor: _fillSpill.adjustFactor,
                ));
          }),
          _numRow(l.adjustSamples, _fillSpill.adjustSamples.toDouble(), (v) {
            setState(() => _fillSpill = FillingSpillOptConfig(
                  mode: _fillSpill.mode,
                  adjustRange: _fillSpill.adjustRange,
                  adjustSamples: v.round(),
                  adjustFactor: _fillSpill.adjustFactor,
                ));
          }, digits: 0),
          _numRow(l.adjustFactor, _fillSpill.adjustFactor, (v) {
            setState(() => _fillSpill = FillingSpillOptConfig(
                  mode: _fillSpill.mode,
                  adjustRange: _fillSpill.adjustRange,
                  adjustSamples: _fillSpill.adjustSamples,
                  adjustFactor: v,
                ));
          }),
        ],
      ),
      _group(
        title: '截止优化',
        subtitle: '模式 / 可靠性范围 / 周期',
        count: 4,
        groupKey: 'fill-cutoff',
        initiallyExpanded: false,
        children: [
          _dropRow<int>(
            l.mode,
            _fillCutoff.mode,
            [
              DropdownMenuItem(value: 0, child: Text(l.disabled)),
              DropdownMenuItem(value: 1, child: Text(l.auto)),
              DropdownMenuItem(value: 2, child: Text(l.manual)),
            ],
            (v) => setState(() => _fillCutoff = FillingCutoffOptConfig(
                  mode: v ?? 0,
                  controlReliabilityRange: _fillCutoff.controlReliabilityRange,
                  adjustCycles: _fillCutoff.adjustCycles,
                  adjustFactor: _fillCutoff.adjustFactor,
                )),
          ),
          _numRow(
              l.controlReliabilityRange, _fillCutoff.controlReliabilityRange,
              (v) {
            setState(() => _fillCutoff = FillingCutoffOptConfig(
                  mode: _fillCutoff.mode,
                  controlReliabilityRange: v,
                  adjustCycles: _fillCutoff.adjustCycles,
                  adjustFactor: _fillCutoff.adjustFactor,
                ));
          }),
          _numRow(l.adjustCycles, _fillCutoff.adjustCycles.toDouble(), (v) {
            setState(() => _fillCutoff = FillingCutoffOptConfig(
                  mode: _fillCutoff.mode,
                  controlReliabilityRange: _fillCutoff.controlReliabilityRange,
                  adjustCycles: v.round(),
                  adjustFactor: _fillCutoff.adjustFactor,
                ));
          }, digits: 0),
          _numRow(l.adjustFactor, _fillCutoff.adjustFactor, (v) {
            setState(() => _fillCutoff = FillingCutoffOptConfig(
                  mode: _fillCutoff.mode,
                  controlReliabilityRange: _fillCutoff.controlReliabilityRange,
                  adjustCycles: _fillCutoff.adjustCycles,
                  adjustFactor: v,
                ));
          }),
        ],
      ),
      _group(
        title: '点动',
        subtitle: '模式 / 时长 / 周期',
        count: 4,
        groupKey: 'fill-jog',
        initiallyExpanded: false,
        children: [
          _dropRow<int>(
            l.mode,
            _fillJog.mode,
            [
              DropdownMenuItem(value: 0, child: Text(l.disabled)),
              DropdownMenuItem(value: 1, child: Text(l.auto)),
              DropdownMenuItem(value: 2, child: Text(l.singlePulse)),
              DropdownMenuItem(value: 3, child: Text(l.manual)),
            ],
            (v) => setState(() => _fillJog = FillingJogConfig(
                  mode: v ?? 0,
                  jogDuration: _fillJog.jogDuration,
                  jogPauseTime: _fillJog.jogPauseTime,
                  maxCycles: _fillJog.maxCycles,
                )),
          ),
          _numRow(l.jogDuration, _fillJog.jogDuration, (v) {
            setState(() => _fillJog = FillingJogConfig(
                  mode: _fillJog.mode,
                  jogDuration: v,
                  jogPauseTime: _fillJog.jogPauseTime,
                  maxCycles: _fillJog.maxCycles,
                ));
          }),
          _numRow(l.jogPauseTime, _fillJog.jogPauseTime, (v) {
            setState(() => _fillJog = FillingJogConfig(
                  mode: _fillJog.mode,
                  jogDuration: _fillJog.jogDuration,
                  jogPauseTime: v,
                  maxCycles: _fillJog.maxCycles,
                ));
          }),
          _numRow(l.maxCycles, _fillJog.maxCycles.toDouble(), (v) {
            setState(() => _fillJog = FillingJogConfig(
                  mode: _fillJog.mode,
                  jogDuration: _fillJog.jogDuration,
                  jogPauseTime: _fillJog.jogPauseTime,
                  maxCycles: v.round(),
                ));
          }, digits: 0),
        ],
      ),
      _group(
        title: '回填',
        subtitle: '上下限',
        count: 2,
        groupKey: 'fill-refill',
        initiallyExpanded: false,
        children: [
          _numRow(l.upperLimit, _fillRefill.upperLimit, (v) {
            setState(() => _fillRefill = FillingRefillConfig(
                  upperLimit: v,
                  lowerLimit: _fillRefill.lowerLimit,
                ));
          }),
          _numRow(l.lowerLimit, _fillRefill.lowerLimit, (v) {
            setState(() => _fillRefill = FillingRefillConfig(
                  upperLimit: _fillRefill.upperLimit,
                  lowerLimit: v,
                ));
          }),
        ],
      ),
      _group(
        title: '排空',
        subtitle: '完成模式 / 残余重量 / 完成时间',
        count: 3,
        groupKey: 'fill-empty',
        initiallyExpanded: false,
        children: [
          _dropRow<int>(
            l.completeMode,
            _fillEmpty.completeMode,
            [
              DropdownMenuItem(value: 0, child: Text(l.residualWeight)),
              DropdownMenuItem(value: 1, child: Text(l.time)),
            ],
            (v) => setState(() => _fillEmpty = FillingEmptyingConfig(
                  completeMode: v ?? 0,
                  residualWeight: _fillEmpty.residualWeight,
                  completionTime: _fillEmpty.completionTime,
                )),
          ),
          _numRow(l.residualWeight, _fillEmpty.residualWeight, (v) {
            setState(() => _fillEmpty = FillingEmptyingConfig(
                  completeMode: _fillEmpty.completeMode,
                  residualWeight: v,
                  completionTime: _fillEmpty.completionTime,
                ));
          }),
          _numRow(l.completionTime, _fillEmpty.completionTime, (v) {
            setState(() => _fillEmpty = FillingEmptyingConfig(
                  completeMode: _fillEmpty.completeMode,
                  residualWeight: _fillEmpty.residualWeight,
                  completionTime: v,
                ));
          }),
        ],
      ),
      _group(
        title: '事件',
        subtitle: '各阶段超时',
        count: 4,
        groupKey: 'fill-events',
        initiallyExpanded: false,
        children: [
          _numRow(l.initialFeedTimeout, _fillEvents.initialFeedTimeout, (v) {
            setState(() => _fillEvents = FillingEventsConfig(
                  initialFeedTimeout: v,
                  emptyingTimeout: _fillEvents.emptyingTimeout,
                  refillTimeout: _fillEvents.refillTimeout,
                  processTimeout: _fillEvents.processTimeout,
                ));
          }),
          _numRow(l.emptyingTimeout, _fillEvents.emptyingTimeout, (v) {
            setState(() => _fillEvents = FillingEventsConfig(
                  initialFeedTimeout: _fillEvents.initialFeedTimeout,
                  emptyingTimeout: v,
                  refillTimeout: _fillEvents.refillTimeout,
                  processTimeout: _fillEvents.processTimeout,
                ));
          }),
          _numRow(l.refillTimeout, _fillEvents.refillTimeout, (v) {
            setState(() => _fillEvents = FillingEventsConfig(
                  initialFeedTimeout: _fillEvents.initialFeedTimeout,
                  emptyingTimeout: _fillEvents.emptyingTimeout,
                  refillTimeout: v,
                  processTimeout: _fillEvents.processTimeout,
                ));
          }),
          _numRow(l.processTimeout, _fillEvents.processTimeout, (v) {
            setState(() => _fillEvents = FillingEventsConfig(
                  initialFeedTimeout: _fillEvents.initialFeedTimeout,
                  emptyingTimeout: _fillEvents.emptyingTimeout,
                  refillTimeout: _fillEvents.refillTimeout,
                  processTimeout: v,
                ));
          }),
        ],
      ),
      _group(
        title: '高级配置',
        subtitle: '周期确认 / 快速恢复 / 互锁',
        count: 5,
        groupKey: 'fill-adv',
        initiallyExpanded: false,
        children: [
          _dropRow<int>(
            l.cycleConfirm,
            _fillAdv.cycleConfirm,
            [
              DropdownMenuItem(value: 0, child: Text(l.disabled)),
              DropdownMenuItem(value: 1, child: Text(l.every)),
              DropdownMenuItem(value: 2, child: Text(l.outOfTolerance)),
            ],
            (v) => setState(() => _fillAdv = FillingAdvancedConfig(
                  cycleConfirm: v ?? 0,
                  fastRecovery: _fillAdv.fastRecovery,
                  interlockEnabled: _fillAdv.interlockEnabled,
                  fastFeedSpeed: _fillAdv.fastFeedSpeed,
                  fineFeedSpeed: _fillAdv.fineFeedSpeed,
                )),
          ),
          _dropRow<int>(
            l.fastRecovery,
            _fillAdv.fastRecovery,
            [
              DropdownMenuItem(value: 0, child: Text(l.auto)),
              DropdownMenuItem(value: 1, child: Text(l.staticVal)),
              DropdownMenuItem(value: 2, child: Text(l.disabled)),
            ],
            (v) => setState(() => _fillAdv = FillingAdvancedConfig(
                  cycleConfirm: _fillAdv.cycleConfirm,
                  fastRecovery: v ?? 0,
                  interlockEnabled: _fillAdv.interlockEnabled,
                  fastFeedSpeed: _fillAdv.fastFeedSpeed,
                  fineFeedSpeed: _fillAdv.fineFeedSpeed,
                )),
          ),
          _boolRow(
            l.interlockEnabled,
            _fillAdv.interlockEnabled,
            (v) => setState(() => _fillAdv = FillingAdvancedConfig(
                  cycleConfirm: _fillAdv.cycleConfirm,
                  fastRecovery: _fillAdv.fastRecovery,
                  interlockEnabled: v,
                  fastFeedSpeed: _fillAdv.fastFeedSpeed,
                  fineFeedSpeed: _fillAdv.fineFeedSpeed,
                )),
          ),
          _numRow(l.fastFeedSpeed, _fillAdv.fastFeedSpeed, (v) {
            setState(() => _fillAdv = FillingAdvancedConfig(
                  cycleConfirm: _fillAdv.cycleConfirm,
                  fastRecovery: _fillAdv.fastRecovery,
                  interlockEnabled: _fillAdv.interlockEnabled,
                  fastFeedSpeed: v,
                  fineFeedSpeed: _fillAdv.fineFeedSpeed,
                ));
          }),
          _numRow(l.fineFeedSpeed, _fillAdv.fineFeedSpeed, (v) {
            setState(() => _fillAdv = FillingAdvancedConfig(
                  cycleConfirm: _fillAdv.cycleConfirm,
                  fastRecovery: _fillAdv.fastRecovery,
                  interlockEnabled: _fillAdv.interlockEnabled,
                  fastFeedSpeed: _fillAdv.fastFeedSpeed,
                  fineFeedSpeed: v,
                ));
          }),
        ],
      ),
    ];
  }

  // ── 4. 硬件 ────────────────────────────────────────────────

  List<DigitalInputBinding> get _subsystemInputBindings => _digitalInputs
      .bindings
      .where((binding) => binding.subsystemId == widget.mapping.subsystemId)
      .toList();

  List<DigitalOutputBinding> get _subsystemOutputBindings => _digitalOutputs
      .bindings
      .where((binding) => binding.subsystemId == widget.mapping.subsystemId)
      .toList();

  List<ServoOutputBinding> get _subsystemServoBindings => _digitalOutputs
      .servoBindings
      .where((binding) => binding.subsystemId == widget.mapping.subsystemId)
      .toList();

  List<int> _devicePositions(int selected, {required bool servo}) {
    final role = servo ? SlaveRole.servo : SlaveRole.digitalIo;
    final positions = _ioSlaves
        .where((slave) =>
            detectSlaveRole(slave.vendorId, slave.productCode) == role)
        .map((slave) => slave.position)
        .toSet();
    positions.add(selected);
    return positions.toList()..sort();
  }

  void _replaceInput(
    DigitalInputBinding previous,
    DigitalInputBinding replacement,
  ) {
    final bindings = List<DigitalInputBinding>.from(_digitalInputs.bindings);
    final index = bindings.indexOf(previous);
    if (index < 0) return;
    bindings[index] = replacement;
    setState(() => _digitalInputs = DigitalInputMapConfig(
          version: _digitalInputs.version,
          bindings: bindings,
        ));
  }

  void _replaceOutput(
    DigitalOutputBinding previous,
    DigitalOutputBinding replacement,
  ) {
    final bindings = List<DigitalOutputBinding>.from(_digitalOutputs.bindings);
    final index = bindings.indexOf(previous);
    if (index < 0) return;
    bindings[index] = replacement;
    setState(() => _digitalOutputs = DigitalOutputMapConfig(
          version: _digitalOutputs.version,
          bindings: bindings,
          servoBindings: _digitalOutputs.servoBindings,
        ));
  }

  void _replaceServo(
    ServoOutputBinding previous,
    ServoOutputBinding replacement,
  ) {
    final bindings = List<ServoOutputBinding>.from(
      _digitalOutputs.servoBindings,
    );
    final index = bindings.indexOf(previous);
    if (index < 0) return;
    bindings[index] = replacement;
    setState(() => _digitalOutputs = DigitalOutputMapConfig(
          version: _digitalOutputs.version,
          bindings: _digitalOutputs.bindings,
          servoBindings: bindings,
        ));
  }

  void _addInputBinding() {
    final positions = _ioSlaves
        .where((slave) =>
            detectSlaveRole(slave.vendorId, slave.productCode) ==
            SlaveRole.digitalIo)
        .map((slave) => slave.position)
        .toList();
    if (positions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.noDevicesFound)),
      );
      return;
    }
    final position = positions.first;
    setState(() => _digitalInputs = DigitalInputMapConfig(
          version: _digitalInputs.version,
          bindings: [
            ..._digitalInputs.bindings,
            DigitalInputBinding(
              subsystemId: widget.mapping.subsystemId,
              ioPos: position,
              bitIndex: 0,
              signal: DigitalInputSignalType.startSignal,
            ),
          ],
        ));
  }

  void _addOutputBinding() {
    final positions = _ioSlaves
        .where((slave) =>
            detectSlaveRole(slave.vendorId, slave.productCode) ==
            SlaveRole.digitalIo)
        .map((slave) => slave.position)
        .toList();
    if (positions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.noDevicesFound)),
      );
      return;
    }
    final position = positions.first;
    setState(() => _digitalOutputs = DigitalOutputMapConfig(
          version: _digitalOutputs.version,
          bindings: [
            ..._digitalOutputs.bindings,
            DigitalOutputBinding(
              subsystemId: widget.mapping.subsystemId,
              ioPos: position,
              bitIndex: 0,
              signal: DigitalSignalType.feedFast,
            ),
          ],
          servoBindings: _digitalOutputs.servoBindings,
        ));
  }

  void _addServoBinding() {
    final positions = _ioSlaves
        .where((slave) =>
            detectSlaveRole(slave.vendorId, slave.productCode) ==
            SlaveRole.servo)
        .map((slave) => slave.position)
        .toList();
    if (positions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.noDevicesFound)),
      );
      return;
    }
    final position = positions.first;
    setState(() => _digitalOutputs = DigitalOutputMapConfig(
          version: _digitalOutputs.version,
          bindings: _digitalOutputs.bindings,
          servoBindings: [
            ..._digitalOutputs.servoBindings,
            ServoOutputBinding(
              subsystemId: widget.mapping.subsystemId,
              servoPos: position,
              signal: DigitalSignalType.feedFast,
            ),
          ],
        ));
  }

  Widget _inputBindingEditor(DigitalInputBinding binding) {
    final l = AppLocalizations.of(context)!;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF153748),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Text(getDigitalInputSignalTypeName(context, binding.signal))),
              IconButton(
                tooltip: l.delete,
                onPressed: () => setState(() => _digitalInputs =
                    DigitalInputMapConfig(
                      version: _digitalInputs.version,
                      bindings: List<DigitalInputBinding>.from(
                        _digitalInputs.bindings,
                      )..remove(binding),
                    )),
                icon: const Icon(Icons.delete_outline, size: 18),
              ),
            ],
          ),
          _dropRow<DigitalInputSignalType>(
            l.signal,
            binding.signal,
            [
              for (final signal in DigitalInputSignalType.values)
                DropdownMenuItem(
                  value: signal,
                  child: Text(getDigitalInputSignalTypeName(context, signal)),
                ),
            ],
            (value) {
              if (value != null) {
                _replaceInput(binding, binding.copyWith(signal: value));
              }
            },
          ),
          _dropRow<int>(
            l.hardwarePin,
            binding.ioPos,
            [
              for (final position
                  in _devicePositions(binding.ioPos, servo: false))
                DropdownMenuItem(
                  value: position,
                  child: Text('IO $position'),
                ),
            ],
            (value) {
              if (value != null) {
                _replaceInput(binding, binding.copyWith(ioPos: value));
              }
            },
          ),
          _numRow('Bit', binding.bitIndex.toDouble(), (value) {
            _replaceInput(binding, binding.copyWith(bitIndex: value.round()));
          }, digits: 0),
          _dropRow<int>(
            l.appScope,
            binding.appScope,
            const [
              DropdownMenuItem(value: -1, child: Text('全部应用')),
              DropdownMenuItem(value: 0, child: Text('失重秤')),
              DropdownMenuItem(value: 1, child: Text('灌装')),
            ],
            (value) {
              if (value != null) {
                _replaceInput(binding, binding.copyWith(appScope: value));
              }
            },
          ),
          _boolRow('高电平有效', binding.activeHigh, (value) {
            _replaceInput(binding, binding.copyWith(activeHigh: value));
          }),
          _boolRow(l.enabled, binding.enabled, (value) {
            _replaceInput(binding, binding.copyWith(enabled: value));
          }),
        ],
      ),
    );
  }

  Widget _outputBindingEditor(DigitalOutputBinding binding) {
    final l = AppLocalizations.of(context)!;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF153748),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Text(getDigitalSignalTypeName(context, binding.signal))),
              IconButton(
                tooltip: l.delete,
                onPressed: () => setState(() => _digitalOutputs =
                    DigitalOutputMapConfig(
                      version: _digitalOutputs.version,
                      bindings: List<DigitalOutputBinding>.from(
                        _digitalOutputs.bindings,
                      )..remove(binding),
                      servoBindings: _digitalOutputs.servoBindings,
                    )),
                icon: const Icon(Icons.delete_outline, size: 18),
              ),
            ],
          ),
          _dropRow<DigitalSignalType>(
            l.signal,
            binding.signal,
            [
              for (final signal in DigitalSignalType.values)
                DropdownMenuItem(
                  value: signal,
                  child: Text(getDigitalSignalTypeName(context, signal)),
                ),
            ],
            (value) {
              if (value != null) {
                _replaceOutput(
                  binding,
                  DigitalOutputBinding(
                    subsystemId: binding.subsystemId,
                    ioPos: binding.ioPos,
                    bitIndex: binding.bitIndex,
                    signal: value,
                    activeHigh: binding.activeHigh,
                    enabled: binding.enabled,
                    appScope: binding.appScope,
                    siloIndex: binding.siloIndex,
                  ),
                );
              }
            },
          ),
          _dropRow<int>(
            l.hardwarePin,
            binding.ioPos,
            [
              for (final position
                  in _devicePositions(binding.ioPos, servo: false))
                DropdownMenuItem(value: position, child: Text('IO $position')),
            ],
            (value) {
              if (value != null) {
                _replaceOutput(
                  binding,
                  DigitalOutputBinding(
                    subsystemId: binding.subsystemId,
                    ioPos: value,
                    bitIndex: binding.bitIndex,
                    signal: binding.signal,
                    activeHigh: binding.activeHigh,
                    enabled: binding.enabled,
                    appScope: binding.appScope,
                    siloIndex: binding.siloIndex,
                  ),
                );
              }
            },
          ),
          _numRow('Bit', binding.bitIndex.toDouble(), (value) {
            _replaceOutput(
              binding,
              DigitalOutputBinding(
                subsystemId: binding.subsystemId,
                ioPos: binding.ioPos,
                bitIndex: value.round(),
                signal: binding.signal,
                activeHigh: binding.activeHigh,
                enabled: binding.enabled,
                appScope: binding.appScope,
                siloIndex: binding.siloIndex,
              ),
            );
          }, digits: 0),
          _dropRow<int>(
            l.appScope,
            binding.appScope,
            const [
              DropdownMenuItem(value: -1, child: Text('全部应用')),
              DropdownMenuItem(value: 0, child: Text('失重秤')),
              DropdownMenuItem(value: 1, child: Text('灌装')),
            ],
            (value) {
              if (value == null) return;
              _replaceOutput(
                binding,
                DigitalOutputBinding(
                  subsystemId: binding.subsystemId,
                  ioPos: binding.ioPos,
                  bitIndex: binding.bitIndex,
                  signal: binding.signal,
                  activeHigh: binding.activeHigh,
                  enabled: binding.enabled,
                  appScope: value,
                  siloIndex: binding.siloIndex,
                ),
              );
            },
          ),
          _numRow('料仓编号 (-1=全部)', binding.siloIndex.toDouble(), (value) {
            _replaceOutput(
              binding,
              DigitalOutputBinding(
                subsystemId: binding.subsystemId,
                ioPos: binding.ioPos,
                bitIndex: binding.bitIndex,
                signal: binding.signal,
                activeHigh: binding.activeHigh,
                enabled: binding.enabled,
                appScope: binding.appScope,
                siloIndex: value.round(),
              ),
            );
          }, digits: 0),
          _boolRow('高电平有效', binding.activeHigh, (value) {
            _replaceOutput(
              binding,
              DigitalOutputBinding(
                subsystemId: binding.subsystemId,
                ioPos: binding.ioPos,
                bitIndex: binding.bitIndex,
                signal: binding.signal,
                activeHigh: value,
                enabled: binding.enabled,
                appScope: binding.appScope,
                siloIndex: binding.siloIndex,
              ),
            );
          }),
          _boolRow(l.enabled, binding.enabled, (value) {
            _replaceOutput(
              binding,
              DigitalOutputBinding(
                subsystemId: binding.subsystemId,
                ioPos: binding.ioPos,
                bitIndex: binding.bitIndex,
                signal: binding.signal,
                activeHigh: binding.activeHigh,
                enabled: value,
                appScope: binding.appScope,
                siloIndex: binding.siloIndex,
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _servoBindingEditor(ServoOutputBinding binding) {
    final l = AppLocalizations.of(context)!;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF153748),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Text('伺服 · ${getDigitalSignalTypeName(context, binding.signal)}')),
              IconButton(
                tooltip: l.delete,
                onPressed: () => setState(() => _digitalOutputs =
                    DigitalOutputMapConfig(
                      version: _digitalOutputs.version,
                      bindings: _digitalOutputs.bindings,
                      servoBindings: List<ServoOutputBinding>.from(
                        _digitalOutputs.servoBindings,
                      )..remove(binding),
                    )),
                icon: const Icon(Icons.delete_outline, size: 18),
              ),
            ],
          ),
          _dropRow<int>(
            '伺服设备',
            binding.servoPos,
            [
              for (final position
                  in _devicePositions(binding.servoPos, servo: true))
                DropdownMenuItem(
                  value: position,
                  child: Text('Servo $position'),
                ),
            ],
            (value) {
              if (value != null) {
                _replaceServo(
                  binding,
                  ServoOutputBinding(
                    subsystemId: binding.subsystemId,
                    servoPos: value,
                    signal: binding.signal,
                    enabled: binding.enabled,
                    appScope: binding.appScope,
                    siloIndex: binding.siloIndex,
                  ),
                );
              }
            },
          ),
          _dropRow<DigitalSignalType>(
            l.signal,
            binding.signal,
            [
              for (final signal in DigitalSignalType.values)
                DropdownMenuItem(
                  value: signal,
                  child: Text(getDigitalSignalTypeName(context, signal)),
                ),
            ],
            (value) {
              if (value != null) {
                _replaceServo(
                  binding,
                  ServoOutputBinding(
                    subsystemId: binding.subsystemId,
                    servoPos: binding.servoPos,
                    signal: value,
                    enabled: binding.enabled,
                    appScope: binding.appScope,
                    siloIndex: binding.siloIndex,
                  ),
                );
              }
            },
          ),
          _dropRow<int>(
            l.appScope,
            binding.appScope,
            const [
              DropdownMenuItem(value: -1, child: Text('全部应用')),
              DropdownMenuItem(value: 0, child: Text('失重秤')),
              DropdownMenuItem(value: 1, child: Text('灌装')),
            ],
            (value) {
              if (value != null) {
                _replaceServo(
                  binding,
                  ServoOutputBinding(
                    subsystemId: binding.subsystemId,
                    servoPos: binding.servoPos,
                    signal: binding.signal,
                    enabled: binding.enabled,
                    appScope: value,
                    siloIndex: binding.siloIndex,
                  ),
                );
              }
            },
          ),
          _numRow('料仓编号 (-1=全部)', binding.siloIndex.toDouble(), (value) {
            _replaceServo(
              binding,
              ServoOutputBinding(
                subsystemId: binding.subsystemId,
                servoPos: binding.servoPos,
                signal: binding.signal,
                enabled: binding.enabled,
                appScope: binding.appScope,
                siloIndex: value.round(),
              ),
            );
          }, digits: 0),
          _boolRow(l.enabled, binding.enabled, (value) {
            _replaceServo(
              binding,
              ServoOutputBinding(
                subsystemId: binding.subsystemId,
                servoPos: binding.servoPos,
                signal: binding.signal,
                enabled: value,
                appScope: binding.appScope,
                siloIndex: binding.siloIndex,
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _hardwareTab(AppLocalizations l) {
    if (_ioLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_ioError != null) {
      return Column(
        children: [
          Text(_ioError!, style: const TextStyle(color: Color(0xFFFF8F85))),
          TextButton(onPressed: _loadHardware, child: Text(l.refresh)),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _group(
          title: l.digitalInputMapping,
          subtitle: '当前子系统的输入信号与硬件引脚映射',
          count: _subsystemInputBindings.length,
          groupKey: 'hardware-inputs',
          initiallyExpanded: true,
          children: [
            if (_subsystemInputBindings.isEmpty)
              _readonly('暂无输入映射')
            else
              for (final binding in _subsystemInputBindings)
                _inputBindingEditor(binding),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _addInputBinding,
                icon: const Icon(Icons.add),
                label: Text(l.addConfig),
              ),
            ),
          ],
        ),
        _group(
          title: l.digitalOutputMapping,
          subtitle: '当前子系统的离散输出与伺服输出映射',
          count: _subsystemOutputBindings.length +
              _subsystemServoBindings.length,
          groupKey: 'hardware-outputs',
          initiallyExpanded: true,
          children: [
            if (_subsystemOutputBindings.isEmpty &&
                _subsystemServoBindings.isEmpty)
              _readonly('暂无输出映射')
            else ...[
              for (final binding in _subsystemOutputBindings)
                _outputBindingEditor(binding),
              for (final binding in _subsystemServoBindings)
                _servoBindingEditor(binding),
            ],
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: _addOutputBinding,
                  icon: const Icon(Icons.add),
                  label: const Text('添加离散输出'),
                ),
                TextButton.icon(
                  onPressed: _addServoBinding,
                  icon: const Icon(Icons.add),
                  label: const Text('添加伺服输出'),
                ),
              ],
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _ioSaving ? null : _saveHardware,
            icon: _ioSaving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined, size: 16),
            label: Text(l.save),
          ),
        ),
      ],
    );
  }

  // ── 5. 工艺 ────────────────────────────────────────────────

  Widget _processTab(AppLocalizations l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_siloSequenceLoading)
          const Center(child: CircularProgressIndicator())
        else if (_siloError != null)
          Text(_siloError!, style: const TextStyle(color: Color(0xFFFF8F85))),
        _group(
          title: '料仓配置',
          subtitle: '选择料仓并直接编辑独立工艺参数',
          count: _siloIndices.length,
          groupKey: 'silo-process',
          initiallyExpanded: true,
          children: [
            if (_siloIndices.isEmpty)
              _readonly('暂无已配置料仓')
            else
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: _selectedSiloIndex,
                      decoration: _deco().copyWith(labelText: '料仓编号'),
                      dropdownColor: const Color(0xFF153748),
                      style: const TextStyle(
                        color: Color(0xFFEFFAFF),
                        fontSize: 13,
                      ),
                      items: [
                        for (final index in _siloIndices)
                          DropdownMenuItem(
                            value: index,
                            child: Text('料仓 $index'),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) _loadSiloProcess(value);
                      },
                    ),
                  ),
                ],
              ),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                children: [
                  TextButton.icon(
                    onPressed: _siloSequenceLoading ? null : _loadSiloSequence,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: Text(l.refresh),
                  ),
                  TextButton.icon(
                    onPressed: _addSilo,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('添加料仓'),
                  ),
                ],
              ),
            ),
            if (_siloEditMode) ..._fillingRecipeGroups(l).skip(1),
            if (_siloEditMode)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text('保存料仓参数'),
                ),
              ),
          ],
        ),
        _group(
          title: '料仓顺序',
          subtitle: '多料仓配方的执行顺序与目标值',
          count: _siloSequence.steps.length,
          groupKey: 'silo-sequence',
          initiallyExpanded: true,
          children: [
            _boolRow(
              '启用料仓顺序',
              _siloSequence.enabled,
              (value) => setState(() {
                _siloSequence = SiloSequenceConfig(
                  subsystemId: widget.mapping.subsystemId,
                  enabled: value,
                  steps: _siloSequence.steps,
                );
              }),
            ),
            if (_siloSequence.steps.isEmpty)
              _readonly('暂无料仓步骤')
            else
              for (var index = 0;
                  index < _siloSequence.steps.length;
                  index++)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${index + 1}. 料仓 ${_siloSequence.steps[index].siloIndex}',
                    style: const TextStyle(color: Color(0xFFEFFAFF)),
                  ),
                  subtitle: Text(
                    '${_siloSequence.steps[index].materialName} · '
                    '${_siloSequence.steps[index].targetValue} kg',
                    style: const TextStyle(color: Color(0xFF91ABBA)),
                  ),
                  trailing: Wrap(
                    children: [
                      IconButton(
                        tooltip: '编辑',
                        onPressed: _siloIndices.isEmpty
                            ? null
                            : () => _editSiloStep(
                                  current: _siloSequence.steps[index],
                                  index: index,
                                ),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                      ),
                      IconButton(
                        tooltip: l.delete,
                        onPressed: () => setState(() {
                          final steps =
                              List<SiloStep>.from(_siloSequence.steps)
                                ..removeAt(index);
                          _siloSequence = SiloSequenceConfig(
                            subsystemId: widget.mapping.subsystemId,
                            enabled: _siloSequence.enabled,
                            steps: steps,
                          );
                        }),
                        icon: const Icon(Icons.delete_outline, size: 18),
                      ),
                    ],
                  ),
                ),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed:
                      _siloIndices.isEmpty ? null : () => _editSiloStep(),
                  icon: const Icon(Icons.add),
                  label: const Text('添加步骤'),
                ),
                FilledButton(
                  onPressed:
                      _siloSequenceSaving ? null : _saveSiloSequence,
                  child: _siloSequenceSaving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l.save),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  // ── 通用组件 ──────────────────────────────────────────────

  /// 子分类分组（对齐 SVG：左彩色竖条信息条 + 参数行）。
  Widget _group({
    required String title,
    String? subtitle,
    int? count,
    required String groupKey,
    required List<Widget> children,
    bool initiallyExpanded = false,
  }) {
    final isExpanded = !_collapsedGroups.contains(groupKey);
    final options = _groupOptions(AppLocalizations.of(context)!);
    final isNavigable = options.any((group) => group.key == groupKey);
    final selectedGroupKey =
        options.any((group) => group.key == _activeGroupKey)
            ? _activeGroupKey
            : options.isEmpty
                ? null
                : options.first.key;
    final isHidden = isNavigable &&
        _searchQuery.isEmpty &&
        groupKey != selectedGroupKey;
    // 用折叠状态（而非 initiallyExpanded）——initState 时的 initiallyExpanded 只用于初始状态
    return Offstage(
      offstage: isHidden,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF0D2535),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF29495B)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 头：左彩色竖条 + 标题 + 副标题 + 项数 + 折叠图标
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                setState(() {
                  if (_collapsedGroups.contains(groupKey)) {
                    _collapsedGroups.remove(groupKey);
                  } else {
                    _collapsedGroups.add(groupKey);
                  }
                });
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: const Color(0xFF62E3E5),
                      width: 4,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: Color(0xFF62E3E5),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (subtitle != null)
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF91ABBA),
                                fontSize: 10,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (count != null)
                      Text(
                        '$count 项',
                        style: const TextStyle(
                          color: Color(0xFF91ABBA),
                          fontSize: 11,
                        ),
                      ),
                    const SizedBox(width: 6),
                    Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 18,
                      color: const Color(0xFF91ABBA),
                    ),
                  ],
                ),
              ),
            ),
            if (isExpanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _paramRow({
    required String label,
    required Widget control,
    bool showScope = true,
  }) {
    if (!_matches(label)) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFC8E8DE),
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(child: control),
          if (showScope) ...[
            const SizedBox(width: 6),
            const _ScopeBadge(),
          ],
        ],
      ),
    );
  }

  Widget _numRow(
    String label,
    double value,
    ValueChanged<double> onChanged, {
    int digits = 3,
  }) {
    return _paramRow(
      label: label,
      control: TextFormField(
        key: ValueKey(
          '$label-${widget.mapping.subsystemId}-$_valueRevision-$digits',
        ),
        initialValue: value.toStringAsFixed(digits),
        style: const TextStyle(color: Color(0xFFEFFAFF), fontSize: 13),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: _deco(),
        onChanged: (text) {
          final parsed = double.tryParse(text);
          if (parsed != null) setState(() => onChanged(parsed));
        },
      ),
    );
  }

  Widget _dropRow<T>(
    String label,
    T value,
    List<DropdownMenuItem<T>> items,
    ValueChanged<T?> onChanged,
  ) {
    return _paramRow(
      label: label,
      control: DropdownButtonFormField<T>(
        value: value,
        dropdownColor: const Color(0xFF153748),
        style: const TextStyle(color: Color(0xFFEFFAFF), fontSize: 13),
        decoration: _deco(),
        items: items,
        onChanged: (v) {
          if (v != null) setState(() => onChanged(v));
        },
      ),
    );
  }

  Widget _boolRow(
    String label,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return _paramRow(
      label: label,
      control: Align(
        alignment: Alignment.centerLeft,
        child: Transform.scale(
          scale: 0.85,
          alignment: Alignment.centerLeft,
          child: Switch(
            value: value,
            activeColor: const Color(0xFF62E3E5),
            onChanged: onChanged,
          ),
        ),
      ),
      showScope: false,
    );
  }

  Widget _readonly(String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0D2535),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF29495B)),
      ),
      child: Text(
        value,
        style: const TextStyle(color: Color(0xFFEFFAFF), fontSize: 13),
      ),
    );
  }

  InputDecoration _deco() {
    return InputDecoration(
      isDense: true,
      filled: true,
      fillColor: const Color(0xFF0D2535),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      hintStyle: const TextStyle(color: Color(0xFF6E8B99)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: Color(0xFF29495B)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: Color(0xFF62E3E5)),
      ),
    );
  }
}

// ── 通用小部件 ────────────────────────────────────────────────

class _ConfigGroupOption {
  const _ConfigGroupOption(this.key, this.title);

  final String key;
  final String title;
}

class _ScopeBadge extends StatelessWidget {
  const _ScopeBadge({this.isAll = false});
  final bool isAll;
  @override
  Widget build(BuildContext context) {
    final active = isAll;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: active ? const Color(0xFF1F728A) : const Color(0xFF1A3A48),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: active ? const Color(0xFF62E3E5) : const Color(0xFF2A4A58),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            active ? Icons.public : Icons.smartphone,
            size: 10,
            color: active ? const Color(0xFFEFFAFF) : const Color(0xFF91ABBA),
          ),
          const SizedBox(width: 3),
          Text(
            active ? '全部' : '本机',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: active ? const Color(0xFFEFFAFF) : const Color(0xFF91ABBA),
            ),
          ),
        ],
      ),
    );
  }
}
