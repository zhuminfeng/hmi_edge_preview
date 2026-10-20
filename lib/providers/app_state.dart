import 'dart:async';
import 'package:flutter/material.dart';
import 'package:weighing_system_elinux/weighing_system_elinux.dart';

class AppState extends ChangeNotifier {
  final WeighingPlatform _platform = WeighingPlatform.instance;

  bool _initialized = false;
  bool _initializing = false;
  bool _initAttempted = false;
  String? _initError;
  int _selectedAppType = -1; // -1=none, 0=liw, 1=filling
  int _activeSubsystemId = 0;
  final Map<int, WeightData> _weightDataMap = {};
  final Map<int, AppStatusData> _appStatusMap = {};
  Locale _locale = const Locale('zh');
  Map<String, dynamic> _configStatus = const {};
  List<SubsystemMappingInfo> _subsystems = [];
  int _newHardwareCount = 0;

  // 🚀 新增：记录每个子系统当前加载的配方名称
  final Map<int, String> _activeRecipeNames = {};

  StreamSubscription<WeightData>? _weightSub;
  StreamSubscription<Map<String, dynamic>>? _statusSub;

  bool get initialized => _initialized;
  bool get initializing => _initializing;
  bool get initAttempted => _initAttempted;
  String? get initError => _initError;
  int get selectedAppType => _selectedAppType;
  int get activeSubsystemId => _activeSubsystemId;
  Locale get locale => _locale;
  Map<String, dynamic> get configStatus => _configStatus;
  List<SubsystemMappingInfo> get subsystems => _subsystems;
  List<SubsystemMappingInfo> get enabledSubsystems =>
      _subsystems.where((s) => s.enabled).toList();

  /// 是否已配置子系统（配置文件中有显式子系统条目）
  bool get hasConfiguredSubsystems =>
      (_configStatus['subsystem_count'] as int? ?? 0) > 0 ||
      _subsystems.isNotEmpty;

  /// 是否存在可运行的已启用子系统
  bool get hasEnabledSubsystems => enabledSubsystems.isNotEmpty;

  /// 扫描到但尚未加入配置的新硬件数量
  int get newHardwareCount => _newHardwareCount;

  WeightData getWeightData(int scaleId) =>
      _weightDataMap[scaleId] ?? const WeightData();

  AppStatusData getAppStatus(int subsystemId) =>
      _appStatusMap[subsystemId] ?? const AppStatusData();

  // 🚀 新增：获取和设置当前活跃的配方名称
  String? getActiveRecipeName(int subsystemId) =>
      _activeRecipeNames[subsystemId];

  void setActiveRecipeName(int subsystemId, String? recipeName) {
    if (recipeName == null) {
      _activeRecipeNames.remove(subsystemId);
    } else {
      _activeRecipeNames[subsystemId] = recipeName;
    }
    notifyListeners();
  }

  Future<void> initialize() async {
    if (_initializing) return;
    _initializing = true;
    _initAttempted = true;
    _initError = null;
    notifyListeners();

    try {
      _initialized = await _platform.initialize().timeout(
        const Duration(seconds: 12),
      );
      if (_initialized) {
        _configStatus = await _platform.getConfigStatus();
        _subsystems = await _platform.getSubsystemMappings();
        // 🚀 【核心优化】：开机读取配置文件后，自动根据后端数据同步内存中的配方标记状态
        _activeRecipeNames.clear();
        for (var sub in _subsystems) {
          if (sub.activeRecipe.isNotEmpty) {
            _activeRecipeNames[sub.subsystemId] = sub.activeRecipe;
          }
        }
        _weightSub = _platform.weightStream.listen((data) {
          _weightDataMap[data.scaleId] = data;
          notifyListeners();
        });
        unawaited(refreshNewHardwareCount());
      } else {
        _initError = '初始化失败：底层返回未就绪状态';
      }
    } on TimeoutException {
      _initialized = false;
      _initError = '初始化超时：请检查 EtherCAT 设备与子系统配置';
    } catch (e) {
      _initialized = false;
      _initError = '初始化异常: $e';
    } finally {
      _initializing = false;
    }
    notifyListeners();
  }

  Future<void> reinitialize() async {
    try {
      await _weightSub?.cancel();
      _weightSub = null;
      await _statusSub?.cancel();
      _statusSub = null;
      _weightDataMap.clear();
      _appStatusMap.clear();
      _activeRecipeNames.clear(); // 清理配方状态
      _configStatus = const {};
      _subsystems = [];
      await _platform.shutdown();
    } catch (_) {}
    _initialized = false;
    _initializing = false;
    _initAttempted = false;
    _initError = null;
    notifyListeners();
    await initialize();
  }

  String _slaveKey(EthercatSlaveInfo s) =>
      '${s.position}-${s.vendorId}-${s.productCode}';

  /// 扫描 EtherCAT 从站并与已保存配置比对，更新新硬件数量
  Future<void> refreshNewHardwareCount() async {
    try {
      final cfg = await _platform.getEthercatHardwareConfig();
      final configured = <String>{
        ...List<EthercatSlaveInfo>.from(
          cfg['outputSlaves'] ?? const [],
        ).map(_slaveKey),
        ...List<EthercatSlaveInfo>.from(
          cfg['inputSlaves'] ?? const [],
        ).map(_slaveKey),
      };
      final scanned = await _platform.scanEthercatSlaves();
      final count = scanned
          .where((s) => !configured.contains(_slaveKey(s)))
          .length;
      if (_newHardwareCount != count) {
        _newHardwareCount = count;
        notifyListeners();
      }
    } catch (_) {}
  }

  /// 用户已查看新硬件提示（如已进入硬件配置页面）后清除角标
  void clearNewHardwareCount() {
    if (_newHardwareCount != 0) {
      _newHardwareCount = 0;
      notifyListeners();
    }
  }

  Future<void> refreshSubsystems() async {
    try {
      _subsystems = await _platform.getSubsystemMappings();
      _configStatus = await _platform.getConfigStatus();
      final hasActiveEnabled = _subsystems.any(
        (sub) => sub.subsystemId == _activeSubsystemId && sub.enabled,
      );
      if (!hasActiveEnabled) {
        final firstEnabled = _subsystems.where((sub) => sub.enabled);
        _activeSubsystemId = firstEnabled.isNotEmpty
            ? firstEnabled.first.subsystemId
            : 0;
      }
      notifyListeners();
    } catch (_) {}
  }

  void selectAppType(int type) {
    _selectedAppType = type;
    notifyListeners();
  }

  void setActiveSubsystem(int id) {
    _activeSubsystemId = id;
    notifyListeners();
  }

  void setLocale(Locale locale) {
    _locale = locale;
    notifyListeners();
  }

  Future<void> startApp(int subsystemId) => _platform.startApp(subsystemId);
  Future<void> stopApp(int subsystemId) => _platform.stopApp(subsystemId);

  Future<void> doZero(int scaleId) => _platform.doZero(scaleId);
  Future<void> doTare(int scaleId) => _platform.doTare(scaleId);
  Future<void> clearTare(int scaleId) => _platform.clearTare(scaleId);

  Future<void> refreshAppStatus() async {
    try {
      final status = await _platform.getAppStatus(_activeSubsystemId);
      _appStatusMap[_activeSubsystemId] = status;
      notifyListeners();
    } catch (e) {
      // 静默失败会让 UI 一直读到全 0 的默认状态，无法与"真的是 0"区分
      debugPrint('[LIW-Flow][UI] getAppStatus($_activeSubsystemId) failed: $e');
    }
  }

  Future<void> refreshAppStatusForSubsystem(int subsystemId) async {
    try {
      final status = await _platform.getAppStatus(subsystemId);
      _appStatusMap[subsystemId] = status;
      notifyListeners();
    } catch (_) {}
  }

  // ============ Material Recipe API ============

  // 修改：只保存到数据库，不自动激活
  Future<bool> saveMaterialRecipe(
    int subsystemId,
    String name,
    int appType,
  ) async {
    return await _platform.saveMaterialRecipe(subsystemId, name, appType);
  }

  // 新增：专门用于激活配方，并触发 C++ 写入 input_mode.json
  Future<bool> setSubsystemActiveRecipe(
    int subsystemId,
    String recipeName,
  ) async {
    final ok = await _platform.setSubsystemActiveRecipe(
      subsystemId,
      recipeName,
    );
    if (ok) {
      setActiveRecipeName(subsystemId, recipeName); // 更新内存和UI
    }
    return ok;
  }

  /// 将物料配方参数载入子系统
  Future<bool> loadMaterialRecipe(
    int subsystemId,
    int recipeId,
    String recipeName,
    int appType,
  ) async {
    // 这里底层接口只需要 recipeId，我们传入 recipeName 是为了在 UI 层显示
    final ok = await _platform.loadMaterialRecipe(
      subsystemId,
      recipeId,
      recipeName,
      appType,
    );
    if (ok) {
      setActiveRecipeName(subsystemId, recipeName); // 加载成功后更新活跃名称
    }
    return ok;
  }

  /// 获取指定应用类型的所有物料配方
  Future<List<Map<String, dynamic>>> getAllMaterialRecipes(int appType) =>
      _platform.getAllMaterialRecipes(appType);

  /// 删除物料配方
  Future<bool> deleteMaterialRecipe(int recipeId, int appType) =>
      _platform.deleteMaterialRecipe(recipeId, appType);

  @override
  void dispose() {
    _weightSub?.cancel();
    _statusSub?.cancel();
    super.dispose();
  }
}

class AppStateProvider extends InheritedNotifier<AppState> {
  final void Function(Locale) onLocaleChange;

  const AppStateProvider({
    super.key,
    required AppState notifier, // 👈 接收外部传入的实例
    required this.onLocaleChange,
    required super.child,
  }) : super(notifier: notifier);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppStateProvider>()!.notifier!;

  static AppState read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppStateProvider>()!.notifier!;

  static void Function(Locale) localeChanger(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<AppStateProvider>()!
      .onLocaleChange;
}
