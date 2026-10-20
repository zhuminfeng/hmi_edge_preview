import 'package:flutter/material.dart';
import 'package:weighing_system_elinux/weighing_system_elinux.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/app_state.dart';
import '../material_recipe_screen.dart';
import 'calibration_screen.dart';
import 'digital_input_settings_screen.dart';
import 'digital_output_settings_screen.dart';
import 'silo_config_screen.dart';
import 'silo_sequence_config_screen.dart';

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
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String _searchQuery = '';

  late TextEditingController _name;
  late int _appType;
  late bool _enabled;
  String _inputMode = 'shmem';

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
    _name = TextEditingController(text: widget.mapping.description);
    _appType = widget.mapping.appType;
    _enabled = widget.mapping.enabled;
    _load();
    _loadRecipes();
  }

  @override
  void didUpdateWidget(covariant HomeSubsystemConfigPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mapping.subsystemId != widget.mapping.subsystemId) {
      _name.text = widget.mapping.description;
      _appType = widget.mapping.appType;
      _enabled = widget.mapping.enabled;
      _section = 0;
      _collapsedGroups.clear();
      _load();
      _loadRecipes();
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  // ── 数据加载 / 保存 ─────────────────────────────────────────────

  Future<void> _loadRecipes() async {
    final subsystemId = widget.mapping.subsystemId;
    final appType = widget.mapping.appType;
    setState(() {
      _recipesLoading = true;
      _recipesError = null;
    });
    try {
      final all =
          await AppStateProvider.read(context).getAllMaterialRecipes(appType);
      if (!mounted ||
          widget.mapping.subsystemId != subsystemId ||
          widget.mapping.appType != appType) return;
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
      if (!mounted || widget.mapping.subsystemId != subsystemId) return;
      setState(() {
        _recipesError = '$error';
        _recipesLoading = false;
      });
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _inputMode = await _platform.getInputMode();
      final id = widget.mapping.subsystemId;
      final scaleId = widget.mapping.scaleId;

      _scale = await _platform.getScaleParams(scaleId);
      _zero = await _platform.getZeroConfig(scaleId);
      _tare = await _platform.getTareConfig(scaleId);
      _filter = await _platform.getFilterStability(scaleId);

      if (_appType == 1) {
        _fillGen = await _platform.getFillingGeneralConfig(id);
        _fillSys = await _platform.getFillingSystemConfig(id);
        _fillTarget = await _platform.getFillingTargetConfig(id);
        _fillAutoTare = await _platform.getFillingAutoTareConfig(id);
        _fillTol = await _platform.getFillingToleranceConfig(id);
        _fillSpill = await _platform.getFillingSpillOptConfig(id);
        _fillCutoff = await _platform.getFillingCutoffOptConfig(id);
        _fillJog = await _platform.getFillingJogConfig(id);
        _fillRefill = await _platform.getFillingRefillConfig(id);
        _fillEmpty = await _platform.getFillingEmptyingConfig(id);
        _fillEvents = await _platform.getFillingEventsConfig(id);
        _fillAdv = await _platform.getFillingAdvancedConfig(id);
      } else {
        _liwBase = await _platform.getLiwBaseConfig(id);
        _liwSystem = await _platform.getLiwSystemConfig(id);
        _liwSysId = await _platform.getLiwSystemIdConfig(id);
        _liwCtrl = await _platform.getLiwControllerConfig(id);
        _liwRefill = await _platform.getLiwRefillConfig(id);
        _liwTarget = await _platform.getLiwTargetValuesConfig(id);
        _liwTol = await _platform.getLiwToleranceCheckConfig(id);
        _liwEmpty = await _platform.getLiwEmptyingConfig(id);
        _liwWarn = await _platform.getLiwWarningConfig(id);
        _liwFlow = await _platform.getLiwFlowMonitorConfig(id);
        _liwAdv = await _platform.getLiwAdvancedConfig(id);
        _liwStats = await _platform.getLiwStatsConfig(id);
      }
      if (!mounted || widget.mapping.subsystemId != id) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context)!;
    setState(() => _saving = true);
    final id = widget.mapping.subsystemId;
    final scaleId = widget.mapping.scaleId;
    var ok = true;
    try {
      ok = await _platform.updateScaleParams(scaleId, _scale) && ok;
      ok = await _platform.updateZeroConfig(scaleId, _zero) && ok;
      ok = await _platform.updateTareConfig(scaleId, _tare) && ok;
      ok = await _platform.updateFilterStability(scaleId, _filter) && ok;

      if (_appType == 1) {
        ok = await _platform.updateFillingGeneralConfig(id, _fillGen) && ok;
        ok = await _platform.updateFillingSystemConfig(id, _fillSys) && ok;
        ok = await _platform.updateFillingTargetConfig(id, _fillTarget) && ok;
        ok = await _platform.updateFillingAutoTareConfig(id, _fillAutoTare) &&
            ok;
        ok = await _platform.updateFillingToleranceConfig(id, _fillTol) && ok;
        ok = await _platform.updateFillingSpillOptConfig(id, _fillSpill) && ok;
        ok =
            await _platform.updateFillingCutoffOptConfig(id, _fillCutoff) && ok;
        ok = await _platform.updateFillingJogConfig(id, _fillJog) && ok;
        ok = await _platform.updateFillingRefillConfig(id, _fillRefill) && ok;
        ok = await _platform.updateFillingEmptyingConfig(id, _fillEmpty) && ok;
        ok = await _platform.updateFillingEventsConfig(id, _fillEvents) && ok;
        ok = await _platform.updateFillingAdvancedConfig(id, _fillAdv) && ok;
      } else {
        ok = await _platform.updateLiwBaseConfig(id, _liwBase) && ok;
        ok = await _platform.updateLiwSystemConfig(id, _liwSystem) && ok;
        ok = await _platform.updateLiwSystemIdConfig(id, _liwSysId) && ok;
        ok = await _platform.updateLiwControllerConfig(id, _liwCtrl) && ok;
        ok = await _platform.updateLiwRefillConfig(id, _liwRefill) && ok;
        ok = await _platform.updateLiwTargetValuesConfig(id, _liwTarget) && ok;
        ok = await _platform.updateLiwToleranceCheckConfig(id, _liwTol) && ok;
        ok = await _platform.updateLiwEmptyingConfig(id, _liwEmpty) && ok;
        ok = await _platform.updateLiwWarningConfig(id, _liwWarn) && ok;
        ok = await _platform.updateLiwFlowMonitorConfig(id, _liwFlow) && ok;
        ok = await _platform.updateLiwAdvancedConfig(id, _liwAdv) && ok;
        ok = await _platform.updateLiwStatsConfig(id, _liwStats) && ok;
      }
      final name = _name.text.trim();
      if (name.isNotEmpty && name != widget.mapping.description) {
        ok = await _platform.addSubsystemMapping(
              id,
              name,
              scaleId: scaleId,
              appType: _appType,
            ) &&
            ok;
      }
      if (_appType != widget.mapping.appType) {
        ok = await _platform.setSubsystemAppType(id, _appType) && ok;
      }
      if (_enabled != widget.mapping.enabled) {
        ok = await _platform.setSubsystemEnabled(id, _enabled) && ok;
      }
      if (mounted) await AppStateProvider.of(context).refreshSubsystems();
    } catch (e) {
      ok = false;
      _error = '$e';
    }
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? l.saveSuccess : l.saveFailedMsg)),
    );
  }

  // ── 配方操作 ────────────────────────────────────────────────

  Future<void> _activateRecipe(
    Map<String, dynamic> recipe, {
    required bool editAfterLoad,
  }) async {
    final id = recipe['recipeId'];
    if (id is! int) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('配方 ID 无效，无法加载')),
      );
      return;
    }
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
    if (confirmed != true || !mounted) return;

    final subsystemId = widget.mapping.subsystemId;
    final appType = widget.mapping.appType;
    try {
      final ok = await AppStateProvider.read(context).loadMaterialRecipe(
        subsystemId,
        id,
        name,
        appType,
      );
      if (!mounted || widget.mapping.subsystemId != subsystemId) return;
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
    if (confirmed != true || !mounted) return;

    final state = AppStateProvider.read(context);
    final ok = await state.deleteMaterialRecipe(
      recipe['recipeId'] as int,
      _appType,
    );
    if (!mounted) return;
    if (ok) {
      if (state.getActiveRecipeName(widget.mapping.subsystemId) == name) {
        state.setActiveRecipeName(widget.mapping.subsystemId, null);
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
    final activeName = AppStateProvider.read(context)
            .getActiveRecipeName(widget.mapping.subsystemId) ??
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
    if (name == null || !mounted) return;

    await _save();
    if (!mounted) return;

    final state = AppStateProvider.read(context);
    final ok = await state.saveMaterialRecipe(
      widget.mapping.subsystemId,
      name,
      _appType,
    );
    if (!mounted) return;

    if (ok) {
      await state.setSubsystemActiveRecipe(widget.mapping.subsystemId, name);
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
    final activeName = AppStateProvider.read(context).getActiveRecipeName(
          widget.mapping.subsystemId,
        ) ??
        widget.mapping.activeRecipe;
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
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MaterialRecipeScreen(
                    appType: _appType,
                    subsystemId: widget.mapping.subsystemId,
                  ),
                ),
              ).then((_) => _loadRecipes());
            },
            child: const Text('配方库'),
          ),
        ],
      ),
    );
    if (picked != null && mounted) {
      await _activateRecipe(picked, editAfterLoad: false);
    }
  }

  // ── 主构建 ──────────────────────────────────────────────────

  bool _matches(String label) =>
      _searchQuery.isEmpty ||
      label.toLowerCase().contains(_searchQuery.toLowerCase());

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
                    : SingleChildScrollView(
                        key: ValueKey('$_section-$_appType'),
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                        child: _sectionBody(l),
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
            onPressed: _saving || _loading ? null : _save,
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
    final activeName = AppStateProvider.read(context)
            .getActiveRecipeName(widget.mapping.subsystemId) ??
        widget.mapping.activeRecipe;
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
                        onTap: () => setState(() => _section = i),
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
        _dropRow<int>(
          '应用类型',
          _appType,
          [
            DropdownMenuItem(value: 0, child: Text(l.lossInWeight)),
            DropdownMenuItem(value: 1, child: Text(l.filling)),
          ],
          (v) => setState(() => _appType = v ?? 0),
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
              _scale.primaryUnit.clamp(0, units.length - 1),
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
              _zero.autoZeroMode.clamp(0, autoZeroLabels.length - 1),
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
              _zero.powerUpZero.clamp(0, powerUpLabels.length - 1),
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
        _EntryCard(
          icon: Icons.tune,
          title: l.calibration,
          subtitle: '${l.calZero} / ${l.calSpan} / ${l.calStep}',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CalibrationScreen(
                subsystemId: widget.mapping.subsystemId,
                scaleId: widget.mapping.scaleId,
              ),
            ),
          ),
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
              _filter.lowPassLevel.clamp(0, 3),
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

  Widget _hardwareTab(AppLocalizations l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _EntryCard(
          icon: Icons.input,
          title: l.digitalInputMapping,
          subtitle: '配置离散输入信号与硬件引脚的对应关系',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DigitalInputSettingsScreen(
                subsystemId: widget.mapping.subsystemId,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _EntryCard(
          icon: Icons.power,
          title: l.digitalOutputMapping,
          subtitle: '配置离散输出 / 伺服输出信号映射',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const DigitalOutputSettingsScreen(),
            ),
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
        _EntryCard(
          icon: Icons.storage_outlined,
          title: '料仓配置',
          subtitle: '添加、编辑料仓及其独立工艺参数',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  SiloConfigScreen(subsystemId: widget.mapping.subsystemId),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _EntryCard(
          icon: Icons.format_list_numbered,
          title: '料仓顺序',
          subtitle: '配置多料仓配方的执行顺序与目标值',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SiloSequenceConfigScreen(
                subsystemId: widget.mapping.subsystemId,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _EntryCard(
          icon: Icons.science_outlined,
          title: '配方库管理',
          subtitle: '管理该子系统的全部配方',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MaterialRecipeScreen(
                appType: _appType,
                subsystemId: widget.mapping.subsystemId,
              ),
            ),
          ).then((_) => _loadRecipes()),
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
    // 用折叠状态（而非 initiallyExpanded）——initState 时的 initiallyExpanded 只用于初始状态
    return Container(
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
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
        key: ValueKey('$label-${widget.mapping.subsystemId}-$value-$digits'),
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

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF153748),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF31596A)),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF1F4A58),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: const Color(0xFF62E3E5), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFFEFFAFF),
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          color: Color(0xFF91ABBA),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (badge != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D2535),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    badge!,
                    style: const TextStyle(
                      color: Color(0xFF62E3E5),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right,
                color: Color(0xFF91ABBA),
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
