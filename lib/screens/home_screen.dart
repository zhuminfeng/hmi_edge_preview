import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:weighing_system_elinux/weighing_system_elinux.dart';
import 'dart:math' as math;
import '../l10n/app_localizations.dart';
import '../providers/app_state.dart';
import 'liw/liw_dashboard.dart';
import 'liw/liw_detail_screen.dart';
import 'filling/filling_dashboard.dart';
import 'filling/filling_detail_screen.dart';
import 'settings/settings_screen.dart';
import 'settings/subsystem_config_screen.dart';
import 'settings/home_subsystem_config_panel.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  bool _setupBannerDismissed = false;
  Timer? _statusTimer;
  int? _selectedSubsystemId;
  late final AnimationController _selectionPulse;
  bool _batchMode = false;
  bool _batchPanelOpen = false;
  final Set<int> _batchSelectedIds = <int>{};

  @override
  void initState() {
    super.initState();
    _selectionPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppStateProvider.of(context).initialize();
    });
    // 定期刷新所有子系统状态
    _statusTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      final state = AppStateProvider.of(context);
      for (final sub in state.enabledSubsystems) {
        state.refreshAppStatusForSubsystem(sub.subsystemId);
      }
    });
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _selectionPulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final state = AppStateProvider.of(context);
    final enabledSubsystems = state.enabledSubsystems;

    // 没有已启用子系统时显示提示横幅
    final noSubsystems = state.initialized && enabledSubsystems.isEmpty;
    final showNoSubBanner = noSubsystems && !_setupBannerDismissed;

    return Scaffold(
      backgroundColor: const Color(0xFF091B2A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B1D2B),
        foregroundColor: const Color(0xFFEFFAFF),
        elevation: 0,
        title: Text(l.appTitle),
        actions: [
          // Language toggle
          PopupMenuButton<Locale>(
            icon: const Icon(Icons.language),
            onSelected: (locale) {
              AppStateProvider.localeChanger(context)(locale);
              state.setLocale(locale);
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(value: const Locale('zh'), child: Text(l.chinese)),
              PopupMenuItem(value: const Locale('en'), child: Text(l.english)),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── 未配置子系统提示横幅 ──────────────────────────────────────────
          if (showNoSubBanner)
            MaterialBanner(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: Icon(
                Icons.warning_amber_rounded,
                color: Theme.of(context).colorScheme.error,
              ),
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.noSubsystemsSetupTitle,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(l.noSubsystemsSetupHint),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => setState(() => _setupBannerDismissed = true),
                  child: Text(l.dismiss),
                ),
                FilledButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SubsystemConfigScreen(),
                    ),
                  ).then((_) {
                    // 返回后刷新子系统列表
                    AppStateProvider.of(context).refreshSubsystems();
                  }),
                  child: Text(l.configureSubsystems),
                ),
              ],
            ),
          Expanded(
            child: state.initializing || !state.initAttempted
                ? const Center(child: CircularProgressIndicator())
                : !state.initialized
                    ? _buildInitFailedPlaceholder(l, state)
                    : noSubsystems
                        ? _buildNoSubsystemsPlaceholder(l)
                        : _buildStation(state, enabledSubsystems, l),
          ),
        ],
      ),
    );
  }

  Widget _buildInitFailedPlaceholder(AppLocalizations l, AppState state) {
    final errorText = state.initError ?? '系统初始化失败';
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              l.loadFailed,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              errorText,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => state.initialize(),
              icon: const Icon(Icons.refresh),
              label: Text(l.refresh),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SubsystemConfigScreen(),
                ),
              ),
              icon: const Icon(Icons.settings),
              label: Text(l.configureSubsystems),
            ),
          ],
        ),
      ),
    );
  }

  /// 未配置子系统时的空状态提示
  Widget _buildNoSubsystemsPlaceholder(AppLocalizations l) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.widgets_outlined,
            size: 80,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 24),
          Text(
            l.noSubsystemsSetupTitle,
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            l.noSubsystemsSetupHint,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            icon: const Icon(Icons.settings),
            label: Text(l.configureSubsystems),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SubsystemConfigScreen()),
            ).then((_) => AppStateProvider.of(context).refreshSubsystems()),
          ),
        ],
      ),
    );
  }

  void _open(AppState state, SubsystemMappingInfo sub) {
    state.setActiveSubsystem(sub.subsystemId);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => sub.appType == 1
            ? FillingDetailScreen(subsystemName: sub.description)
            : LiwDetailScreen(subsystemName: sub.description),
      ),
    );
  }

  void _syncSelectionPulse() {
    final hasSelection = _batchMode
        ? _batchSelectedIds.isNotEmpty
        : _selectedSubsystemId != null;

    if (hasSelection) {
      if (!_selectionPulse.isAnimating) _selectionPulse.repeat();
    } else {
      _selectionPulse.stop();
      _selectionPulse.reset();
    }
  }

  void _toggleBatchMode() {
    if (!_batchMode && _selectedSubsystemId != null) {
      _switchSingleToBatch();
      return;
    }
    setState(() {
      _batchMode = !_batchMode;
      _batchPanelOpen = false;
      _selectedSubsystemId = null;
      _batchSelectedIds.clear();
    });
    _syncSelectionPulse();
  }

  void _select(AppState state, SubsystemMappingInfo sub) {
    if (_batchMode) {
      setState(() {
        if (!_batchSelectedIds.add(sub.subsystemId)) {
          _batchSelectedIds.remove(sub.subsystemId);
        }
        if (_batchSelectedIds.isEmpty) _batchPanelOpen = false;
      });
    } else {
      final nextId =
          _selectedSubsystemId == sub.subsystemId ? null : sub.subsystemId;

      if (nextId != null) state.setActiveSubsystem(nextId);
      setState(() {
        _selectedSubsystemId = nextId;
      });
    }
    _syncSelectionPulse();
  }

  void _switchSingleToBatch() {
    final id = _selectedSubsystemId;
    if (id == null) return;

    setState(() {
      _batchMode = true;
      _batchPanelOpen = false; // 先选设备，不弹右侧批量面板
      _selectedSubsystemId = null;
      _batchSelectedIds
        ..clear()
        ..add(id); // 刚才点击的秤仍处于选中状态
    });
    _syncSelectionPulse();
  }

  void _closeConfigPanel() {
    setState(() {
      if (_batchMode) {
        _batchPanelOpen = false; // 保留批量已选设备
      } else {
        _selectedSubsystemId = null;
      }
    });
    _syncSelectionPulse();
  }

  Widget _batchSelectionBar(List<SubsystemMappingInfo> selected) {
    final names = selected.map((sub) {
      return sub.description.trim().isEmpty
          ? 'Sub ${sub.subsystemId}'
          : sub.description;
    }).join(' · ');

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 560),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF102B3B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF62E3E5)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x6600050B),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: const Color(0xFF1F5C68),
            child: Text(
              '${selected.length}',
              style: const TextStyle(
                color: Color(0xFFEFFAFF),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '已选 ${selected.length} 台设备',
                  style: const TextStyle(
                    color: Color(0xFFEFFAFF),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  selected.isEmpty ? '点击上方的秤进行选择' : names,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF91ABBA),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: selected.isEmpty
                ? null
                : () => setState(() => _batchPanelOpen = true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1F728A),
              foregroundColor: const Color(0xFFEFFAFF),
            ),
            child: const Text('开始配置'),
          ),
        ],
      ),
    );
  }

  Widget _buildStation(
    AppState state,
    List<SubsystemMappingInfo> subs,
    AppLocalizations l,
  ) {
    SubsystemMappingInfo? singleSelection;
    for (final sub in subs) {
      if (sub.subsystemId == _selectedSubsystemId) {
        singleSelection = sub;
        break;
      }
    }

    final batchSelection = subs
        .where((sub) => _batchSelectedIds.contains(sub.subsystemId))
        .toList();

    final panelOpen = _batchMode
        ? _batchPanelOpen && batchSelection.isNotEmpty
        : singleSelection != null;

    return Row(
      children: [
        _sideRail(state, l),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final availableWidth = constraints.maxWidth;
              final compact = availableWidth < 760;
              final panelWidth = compact
                  ? math.max(0.0, availableWidth - 24)
                  : math.min(620.0, availableWidth * 0.56);

              return Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Expanded(
                      child: TweenAnimationBuilder<double>(
                        tween: Tween<double>(
                            begin: 0, end: panelOpen ? 1 : 0),
                        duration: const Duration(milliseconds: 480),
                        curve: Curves.easeOutCubic,
                        builder: (context, progress, _) {
                          final visibleWidth = panelWidth * progress;
                          return Row(
                            children: [
                              // 宽屏保留可交互的秤；窄屏先关闭面板再选设备。
                              Expanded(
                                child: compact && progress > 0
                                    ? const SizedBox.shrink()
                                    : _scaleCards(state, subs, l),
                              ),
                              SizedBox(width: compact ? 0 : 12 * progress),
                              SizedBox(
                                width: visibleWidth,
                                child: ClipRect(
                                  child: OverflowBox(
                                    alignment: Alignment.centerRight,
                                    minWidth: panelWidth,
                                    maxWidth: panelWidth,
                                    child: SizedBox(
                                      width: panelWidth,
                                      child: IgnorePointer(
                                        ignoring: !panelOpen,
                                        child: _sideConfigPanel(
                                          state: state,
                                          singleSelection: singleSelection,
                                          batchSelection: batchSelection,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    if (_batchMode && !panelOpen) ...[
                      const SizedBox(height: 12),
                      _batchSelectionBar(batchSelection),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _sideConfigPanel({
    required AppState state,
    required SubsystemMappingInfo? singleSelection,
    required List<SubsystemMappingInfo> batchSelection,
  }) {
    final isBatch = _batchMode;

    return Material(
      color: const Color(0xFF0D2535),
      elevation: 18,
      shadowColor: const Color(0xAA000914),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF39738A)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          if (isBatch)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
              child: Row(
                children: [
                  const Icon(Icons.tune, color: Color(0xFF62E3E5), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '批量配置 · ${batchSelection.length} 台',
                      style: const TextStyle(
                        color: Color(0xFFEFFAFF),
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: _closeConfigPanel,
                    icon: const Icon(Icons.close, color: Color(0xFFB8CDD7)),
                  ),
                ],
              ),
            ),
          if (isBatch && batchSelection.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final sub in batchSelection)
                      InputChip(
                        label: Text(
                          sub.description.isEmpty
                              ? 'Sub ${sub.subsystemId}'
                              : sub.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onDeleted: () => _select(state, sub),
                        backgroundColor: const Color(0xFF153748),
                        labelStyle: const TextStyle(color: Color(0xFFE2F8FF)),
                        deleteIconColor: const Color(0xFF9BE5FF),
                        side: const BorderSide(color: Color(0xFF39738A)),
                      ),
                  ],
                ),
              ),
            ),
          if (isBatch) const Divider(height: 1, color: Color(0xFF29495B)),
          Expanded(
            child: isBatch
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        '已选择设备。批量参数编辑及“本机／全部”保存逻辑'
                        '需要接入现有配置面板的参数加载、校验和保存方法。',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFFB8CDD7)),
                      ),
                    ),
                  )
                : singleSelection == null
                    ? const SizedBox.shrink()
                    : HomeSubsystemConfigPanel(
                        key: ValueKey(singleSelection.subsystemId),
                        mapping: singleSelection,
                        onOpenDashboard: () => _open(state, singleSelection),
                        onClose: _closeConfigPanel,
                      ),
          ),
        ],
      ),
    );
  }

  Widget _sideRail(AppState state, AppLocalizations l) {
    return Container(
      width: 72,
      decoration: const BoxDecoration(
        color: Color(0xFF0B1D2B),
        border: Border(
          right: BorderSide(color: Color(0xFF29495B)),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 15),
          const Icon(
            Icons.hexagon_outlined,
            color: Color(0xFF62E3E5),
            size: 29,
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: IconButton(
              key: const Key('batch-mode-toggle'),
              tooltip: _batchMode
                  ? '退出批量配置'
                  : '批量配置（切换前请先保存当前修改）',
              onPressed: _toggleBatchMode,
              style: IconButton.styleFrom(
                minimumSize: const Size(48, 48),
                backgroundColor: _batchMode
                    ? const Color(0xFF1F728A)
                    : const Color(0xFF153748),
                foregroundColor: const Color(0xFF62E3E5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
              icon: Icon(_batchMode
                  ? Icons.close
                  : Icons.library_add_check_outlined),
            ),
          ),
          _railButton(Icons.language, () {
            final next = Localizations.localeOf(context).languageCode == 'zh'
                ? const Locale('en')
                : const Locale('zh');
            AppStateProvider.localeChanger(context)(next);
            state.setLocale(next);
          }),
          _railButton(
            Icons.tune,
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const SubsystemConfigScreen(),
              ),
            ).then((_) => state.refreshSubsystems()),
          ),
          _railButton(
            Icons.settings_outlined,
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const SettingsScreen(),
              ),
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: Text(
              l.appTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF91ABBA),
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _railButton(IconData icon, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Material(
        color: const Color(0xFF153748),
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(
              icon,
              color: const Color(0xFFB8D9E4),
              size: 22,
            ),
          ),
        ),
      ),
    );
  }

  Widget _scaleCards(
    AppState state,
    List<SubsystemMappingInfo> subs,
    AppLocalizations l,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (subs.isEmpty) return const SizedBox.shrink();

        const gap = 16.0;

        // 使用导航栏和页面内边距扣除后的实际宽度。
        // 工位可以随窗口缩小；不再低于 1100px 就直接变为两列。
        final width = constraints.maxWidth;
        final columns = width >= 800
            ? 4
            : width >= 525
                ? 3
                : width >= 340
                    ? 2
                    : 1;

        final rows = (subs.length / columns).ceil();
        final fittedHeight = (constraints.maxHeight - gap * (rows - 1)) / rows;

        // 高度不足时滚动；空间变大时，让工位和其中的秤一起变大。
        final tileHeight = math.max(175.0, fittedHeight);

        return GridView.builder(
          padding: EdgeInsets.zero,
          itemCount: subs.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: gap,
            mainAxisSpacing: gap,
            mainAxisExtent: tileHeight,
          ),
          itemBuilder: (context, index) {
            final sub = subs[index];
            return _ScalePanel(
              index: index + 1,
              mapping: sub,
              selected: _batchMode
                  ? _batchSelectedIds.contains(sub.subsystemId)
                  : sub.subsystemId == _selectedSubsystemId,
              pulse: _selectionPulse,
              onSelect: () => _select(state, sub),
              onOpen: () => _open(state, sub),
            );
          },
        );
      },
    );
  }

  Widget _bottomPanel(
    AppState state,
    List<SubsystemMappingInfo> subs,
    AppLocalizations l,
  ) {
    SubsystemMappingInfo? selected;
    for (final sub in subs) {
      if (sub.subsystemId == _selectedSubsystemId) selected = sub;
    }
    if (selected == null) return _paramTable(state, subs, l);
    return HomeSubsystemConfigPanel(
      mapping: selected,
      onOpenDashboard: () => _open(state, selected!),
      onClose: () {
        _selectionPulse.stop();
        _selectionPulse.reset();
        setState(() => _selectedSubsystemId = null);
      },
    );
  }

  Widget _paramTable(
    AppState state,
    List<SubsystemMappingInfo> subs,
    AppLocalizations l,
  ) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF102B3B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2C5062)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 9, 14, 8),
            child: Text(
              l.targetValues,
              style: const TextStyle(
                color: Color(0xFFEFFAFF),
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Divider(height: 1, color: Color(0xFF29495B)),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                const labelWidth = 140.0;
                const minValueWidth = 125.0;

                final tableWidth = math.max(
                  constraints.maxWidth,
                  labelWidth + subs.length * minValueWidth,
                );
                final valueWidth = (tableWidth - labelWidth) / subs.length;

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: tableWidth,
                    child: SingleChildScrollView(
                      child: Table(
                        defaultVerticalAlignment:
                            TableCellVerticalAlignment.middle,
                        border: TableBorder(
                          horizontalInside: const BorderSide(
                            color: Color(0xFF29495B),
                          ),
                          verticalInside: const BorderSide(
                            color: Color(0xFF29495B),
                          ),
                        ),
                        columnWidths: {
                          0: const FixedColumnWidth(labelWidth),
                          for (var i = 1; i <= subs.length; i++)
                            i: FixedColumnWidth(valueWidth),
                        },
                        children: [
                          TableRow(
                            decoration: const BoxDecoration(
                              color: Color(0xFF153748),
                            ),
                            children: [
                              _cell(l.appTitle, bold: true),
                              for (final sub in subs)
                                _cell(
                                  sub.description.isEmpty
                                      ? 'Sub ${sub.subsystemId}'
                                      : sub.description,
                                  bold: true,
                                ),
                            ],
                          ),
                          _row(l.netWeight, subs, (sub) {
                            final weight = state.getWeightData(sub.scaleId);
                            return '${weight.netWeight.toStringAsFixed(3)} '
                                '${weight.unitString}';
                          }),
                          _row(
                            l.currentFlow,
                            subs,
                            (sub) => state
                                .getAppStatus(sub.subsystemId)
                                .currentFlow
                                .toStringAsFixed(2),
                          ),
                          _row(
                            l.controlRate,
                            subs,
                            (sub) =>
                                '${state.getAppStatus(sub.subsystemId).controlRate.toStringAsFixed(1)} %',
                          ),
                          _row(
                            l.running,
                            subs,
                            (sub) =>
                                state.getAppStatus(sub.subsystemId).isRunning
                                    ? l.running
                                    : l.idle,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  TableRow _row(
    String name,
    List<SubsystemMappingInfo> subs,
    String Function(SubsystemMappingInfo) value, {
    bool accent = false,
  }) {
    return TableRow(
      children: [
        _cell(name),
        for (final s in subs) _cell(value(s), accent: accent),
      ],
    );
  }

  Widget _cell(
    String text, {
    bool bold = false,
    bool accent = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 12,
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: accent
              ? const Color(0xFF62E3E5)
              : bold
                  ? const Color(0xFFEFFAFF)
                  : const Color(0xFFB8CDD7),
          fontSize: bold ? 14 : 13,
          fontWeight: bold || accent ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
    );
  }

  /// 单子系统：直接嵌入对应 Dashboard
  Widget _buildSingleSubsystem(
    AppState state,
    List<SubsystemMappingInfo> enabledSubsystems,
  ) {
    final sub = enabledSubsystems.first;
    state.setActiveSubsystem(sub.subsystemId);
    if (sub.appType == 1) {
      return const FillingDashboard();
    }
    return const LiwDashboard();
  }

  /// 多子系统：网格展示每个子系统的概要卡片
  Widget _buildMultiSubsystemGrid(
    AppState state,
    List<SubsystemMappingInfo> enabledSubsystems,
  ) {
    final subsystems = enabledSubsystems;
    final crossCount = subsystems.length <= 2 ? subsystems.length : 2;
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossCount,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.3,
      ),
      itemCount: subsystems.length,
      itemBuilder: (ctx, i) {
        final sub = subsystems[i];
        return _SubsystemSummaryCard(
          mapping: sub,
          onExpand: () {
            state.setActiveSubsystem(sub.subsystemId);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => sub.appType == 1
                    ? FillingDetailScreen(subsystemName: sub.description)
                    : LiwDetailScreen(subsystemName: sub.description),
              ),
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Subsystem Summary Card
// ---------------------------------------------------------------------------

class _SubsystemSummaryCard extends StatelessWidget {
  final SubsystemMappingInfo mapping;
  final VoidCallback onExpand;

  const _SubsystemSummaryCard({required this.mapping, required this.onExpand});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final state = AppStateProvider.of(context);
    final cs = Theme.of(context).colorScheme;

    final weightData = state.getWeightData(mapping.scaleId);
    final appStatus = state.getAppStatus(mapping.subsystemId);

    final isLiw = mapping.appType == 0;
    final typeColor = isLiw ? Colors.blue : Colors.green;
    final typeIcon = isLiw ? Icons.trending_down : Icons.local_drink;
    final typeName = isLiw ? l.lossInWeight : l.filling;

    return Card(
      elevation: 3,
      clipBehavior: Clip.antiAlias, // 🚀 1. 确保点击的水波纹不会超出卡片圆角
      child: InkWell(
        // 🚀 2. 核心修复：用 InkWell 包裹，让整张卡片都可以点击！
        onTap: onExpand,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 顶部：类型图标 + 名称 + 展开按钮 ──────────────────────────
              Row(
                children: [
                  Icon(typeIcon, color: typeColor, size: 20),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          mapping.description.isNotEmpty
                              ? mapping.description
                              : 'Sub ${mapping.subsystemId}',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          typeName,
                          style: Theme.of(
                            context,
                          ).textTheme.labelSmall?.copyWith(color: typeColor),
                        ),
                      ],
                    ),
                  ),
                  // 🚀 3. 移除之前限制热区的苛刻条件，恢复标准的 48x48 触摸热区
                  IconButton(
                    icon: const Icon(Icons.open_in_full, size: 20),
                    tooltip: l.expandDetail,
                    onPressed: onExpand,
                  ),
                ],
              ),
              const Divider(height: 10),
              // ── 重量数据 ────────────────────────────────────────────────────
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          l.netWeight,
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(color: cs.outline),
                        ),
                        Text(
                          '${weightData.netWeight.toStringAsFixed(2)} ${weightData.unitString}',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          l.running,
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(color: cs.outline),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: appStatus.isRunning
                                ? Colors.green.shade100
                                : cs.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            appStatus.isRunning ? l.running : l.idle,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: appStatus.isRunning
                                      ? Colors.green.shade700
                                      : cs.outline,
                                ),
                          ),
                        ),
                      ],
                    ),
                    if (appStatus.stateString.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        appStatus.stateString,
                        style: Theme.of(
                          context,
                        ).textTheme.labelSmall?.copyWith(color: cs.outline),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              // ── 底部：是否启用 ───────────────────────────────────────────────
              if (!mapping.enabled)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.errorContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    l.disabled,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: cs.onErrorContainer,
                        ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScalePanel extends StatelessWidget {
  const _ScalePanel({
    required this.index,
    required this.mapping,
    required this.selected,
    required this.pulse,
    required this.onSelect,
    required this.onOpen,
  });

  final int index;
  final SubsystemMappingInfo mapping;
  final bool selected;
  final AnimationController pulse;
  final VoidCallback onSelect;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final state = AppStateProvider.of(context);
    final weight = state.getWeightData(mapping.scaleId);
    final status = state.getAppStatus(mapping.subsystemId);
    final isFilling = mapping.appType == 1;

    final accent = status.isError
        ? const Color(0xFFEF806F)
        : status.isRunning
            ? const Color(0xFF2BD98A)
            : const Color(0xFFF1B95F);

    final platformColor = selected ? const Color(0xFF62E3E5) : accent;

    final statusText = status.isError
        ? status.stateString
        : status.isRunning
            ? l.running
            : l.idle;

    final name = mapping.description.trim().isEmpty
        ? '${isFilling ? l.filling : l.lossInWeight} #${mapping.subsystemId}'
        : mapping.description;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onSelect,
        // InkWell 只提供点击区域，不绘制卡片底色或边框。
        child: Stack(
          children: [
            Positioned.fill(
              top: 72,
              bottom: 12,
              child: RepaintBoundary(
                child: Transform.scale(
                  scale: 0.88,
                  alignment: Alignment.center,
                  child: CustomPaint(
                    painter: _FeederPainter(
                      isFilling: isFilling,
                      selected: selected,
                      pulse: pulse,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),

            // 只有信息胶囊有自己的底色；模型四周没有卡片背景。
            Positioned(
              left: 16,
              right: 16,
              top: 36,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(23),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x5500050B),
                      blurRadius: 16,
                      offset: Offset(0, 5),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(23),
                  child: Container(
                    height: 46,
                    padding: const EdgeInsets.fromLTRB(9, 3, 3, 3),
                    decoration: BoxDecoration(
                      // 顶部略亮、底部略暗，避免整块胶囊都染成蓝色。
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x55D6F4FF),
                          Color(0x3896C5D5),
                          Color(0x45203346),
                        ],
                        stops: [0, .38, 1],
                      ),
                      borderRadius: BorderRadius.circular(23),
                      border: Border.all(
                        color: selected
                            ? const Color(0xCC9BE5FF)
                            : const Color(0x77D7F3FF),
                        width: selected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 4,
                          height: 18,
                          decoration: BoxDecoration(
                            color: accent,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Color(0xFFD8FFF4),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        height: 1.1,
                                      ),
                                    ),
                                  ),
                                  if (selected) ...[
                                    const SizedBox(width: 4),
                                    const Icon(
                                      Icons.check_circle,
                                      size: 13,
                                      color: Color(0xFF9BE5FF),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      statusText.isEmpty ? '—' : statusText,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: accent,
                                        fontSize: 10,
                                        height: 1.1,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Flexible(
                                    flex: 2,
                                    child: Text(
                                      '${weight.netWeight.toStringAsFixed(2)} '
                                      '${weight.unitString}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Color(0xFFC9F9FF),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        height: 1.1,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: l.expandDetail,
                          onPressed: onOpen,
                          icon: const Icon(
                            Icons.open_in_full,
                            size: 15,
                            color: Color(0xFF9DBDB4),
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 40,
                          ),
                          padding: EdgeInsets.zero,
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
    );
  }
}

/// 原生 Canvas 版本的总览设备模型。
/// 保留 SVG 的主要零件与相对位置；透明背景由卡片负责。
class _FeederPainter extends CustomPainter {
  _FeederPainter({
    required this.isFilling,
    this.selected = false,
    required this.pulse,
  }) : super(repaint: selected ? pulse : null);

  final bool isFilling;
  final bool selected;
  final Animation<double> pulse;

  static const _cyan = Color(0xFF62E3E5);
  static const _edge = Color(0xFFB8D0D9);
  static const _dark = Color(0xFF294D62);

  static const _front = <Color>[
    Color(0xFF8BA1B5),
    Color(0xFFC8D6E2),
    Color(0xFFDAE6F2),
    Color(0xFF9FB3C6),
    Color(0xFF5A7085),
  ];
  static const _frontStops = <double>[0, .20, .45, .75, 1];

  static const _cylinder = <Color>[
    Color(0xFF4A5C6E),
    Color(0xFF8BA1B5),
    Color(0xFFDAE6F2),
    Color(0xFFEAF3FA),
    Color(0xFF9FB3C6),
    Color(0xFF5A7085),
    Color(0xFF334453),
  ];
  static const _cylinderStops = <double>[
    0,
    .15,
    .35,
    .50,
    .70,
    .85,
    1,
  ];

  Paint _solid(Color color) => Paint()
    ..color = color
    ..isAntiAlias = true;

  Paint _stroke(Color color, [double width = 1]) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..isAntiAlias = true;

  Paint _gradient(
    Rect bounds,
    List<Color> colors, {
    bool vertical = false,
    List<double>? stops,
  }) {
    return Paint()
      ..isAntiAlias = true
      ..shader = LinearGradient(
        begin: vertical ? Alignment.topCenter : Alignment.centerLeft,
        end: vertical ? Alignment.bottomCenter : Alignment.centerRight,
        colors: colors,
        stops: stops,
      ).createShader(bounds);
  }

  Path _path(List<Offset> points) {
    final result = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      result.lineTo(point.dx, point.dy);
    }
    return result..close();
  }

  void _poly(Canvas canvas, List<Offset> points, Paint paint) {
    canvas.drawPath(_path(points), paint);
  }

  void _line(
    Canvas canvas,
    Offset from,
    Offset to,
    Color color, [
    double width = 1,
  ]) {
    canvas.drawLine(from, to, _stroke(color, width));
  }

  void _oval(
    Canvas canvas,
    double x,
    double y,
    double rx,
    double ry,
    Paint paint,
  ) {
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(x, y),
        width: rx * 2,
        height: ry * 2,
      ),
      paint,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    // 原 SVG 的左模型约位于 x=140..642、y=166..834；
    // 右模型约位于 x=774..1228、y=192..844。
    final model = const Rect.fromLTRB(70, 166, 750, 960);

    const inset = 8.0;
    final scale = math.min(
      (size.width - inset * 2) / model.width,
      (size.height - inset * 2) / model.height,
    );

    if (scale <= 0) return;

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(
      (size.width - model.width * scale) / 2 - model.left * scale,
      (size.height - model.height * scale) / 2 - model.top * scale,
    );
    canvas.scale(scale);

    if (isFilling) {
      // 两种底座的中心分别约为 (1001, 844) 和 (411, 834)。
      // 灌装秤底座宽 454，失重秤底座宽 422：
      // 以底座中心等比缩小灌装秤，再对齐两个中心。
      canvas.translate(-590, -10);
      canvas.translate(1001, 844);
      canvas.scale(422 / 454);
      canvas.translate(-1001, -844);
    }

    // 光圈与设备使用同一套 canvas.translate / canvas.scale。
    // 先画光晕，再画设备，最后补画圆环前半段。
    _drawBaseGlow(canvas);

    if (isFilling) {
      _drawFilling(canvas);
    } else {
      _drawLiw(canvas);
    }

    _drawFrontRing(canvas);
    canvas.restore();
  }

  Rect get _baseRing => Rect.fromCenter(
        center: isFilling ? const Offset(1001, 874) : const Offset(411, 864),
        width: isFilling ? 560 : 530,
        height: 120,
      );

  void _drawBaseGlow(Canvas canvas) {
    final ring = _baseRing;
    final inner = Rect.fromCenter(
      center: ring.center,
      width: ring.width * (80 / 95),
      height: ring.height * (25 / 30),
    );
    final glow = ring.inflate(18);

    // 原有柔和背景光保持不变，不额外强化中心。
    canvas.drawOval(
      glow,
      Paint()
        ..shader = const RadialGradient(
          colors: [
            Color(0x5556C8FF),
            Color(0x243B96D6),
            Color(0x002B79C1),
          ],
          stops: [0, .60, 1],
        ).createShader(glow),
    );

    if (selected) {
      // 与 SVG 的 1.8 秒呼吸周期对应：0 → 1 → 0。
      final phase = (1 - math.cos(pulse.value * 2 * math.pi)) / 2;

      // SVG 中 opacity="0.08" 的浅绿色椭圆底色。
      canvas.drawOval(
        ring,
        Paint()
          ..color = const Color(0x2856C8FF)
          ..isAntiAlias = true,
      );

      // 内环：透明度在 0.9 与 0.35 之间呼吸。
      canvas.drawOval(
        ring,
        _stroke(
          Color.fromRGBO(155, 229, 255, 1.0 - 0.25 * phase),
          3,
        ),
      );

      // 外环：按 SVG 的 rx/ry 比例向外扩散，同时逐渐淡出。
      final outer = Rect.fromCenter(
        center: ring.center,
        width: ring.width * (115 + 15 * phase) / 105,
        height: ring.height * (38 + 6 * phase) / 34,
      );
      canvas.drawOval(
        outer,
        _stroke(
          Color.fromRGBO(86, 200, 255, 0.85 - 0.50 * phase),
          2,
        ),
      );
    } else {
      // 未选中时保留当前蓝色外圈和虚线内圈。
      canvas.drawOval(
        ring,
        _stroke(const Color(0x8057B8EF), 1.6),
      );

      final dashPaint = _stroke(const Color(0x4057B8EF));
      for (double angle = 0; angle < math.pi * 2; angle += .22) {
        canvas.drawArc(inner, angle, .09, false, dashPaint);
      }
    }
  }

  void _drawFrontRing(Canvas canvas) {
    // 设备之后补画前半圈，维持底座处于光圈中的层次。
    final phase = (1 - math.cos(pulse.value * 2 * math.pi)) / 2;
    canvas.drawArc(
      _baseRing,
      0,
      math.pi,
      false,
      _stroke(
        selected
            ? Color.fromRGBO(155, 229, 255, 1.0 - 0.25 * phase)
            : const Color(0x8057B8EF),
        selected ? 3 : 1.6,
      ),
    );
  }

  void _drawLiw(Canvas canvas) {
    // 底座：顶面、侧面、正面。
    _poly(
      canvas,
      const [
        Offset(200, 780),
        Offset(600, 780),
        Offset(622, 764),
        Offset(222, 764),
      ],
      _solid(const Color(0xFFC2D3E1)),
    );
    _poly(
      canvas,
      const [
        Offset(600, 780),
        Offset(622, 764),
        Offset(622, 818),
        Offset(600, 834),
      ],
      _solid(const Color(0xFF40576A)),
    );
    canvas.drawRect(
      const Rect.fromLTWH(200, 780, 400, 54),
      _gradient(
        const Rect.fromLTWH(200, 780, 400, 54),
        _front,
        vertical: true,
        stops: _frontStops,
      ),
    );
    _line(
      canvas,
      const Offset(230, 803),
      const Offset(570, 803),
      _cyan.withOpacity(.55),
      4,
    );
    _oval(
      canvas,
      570,
      815,
      5,
      5,
      _solid(const Color(0xFF59D3A3)),
    );

    for (final x in [250.0, 510.0]) {
      canvas.drawRect(
        Rect.fromLTWH(x, 630, 40, 150),
        _gradient(
          Rect.fromLTWH(x, 630, 40, 150),
          const [
            Color(0xFF5A7085),
            Color(0xFF7E94A8),
            Color(0xFF3A4C5E),
          ],
          vertical: true,
        ),
      );
      _poly(
        canvas,
        [
          Offset(x + 40, 630),
          Offset(x + 58, 614),
          Offset(x + 58, 764),
          Offset(x + 40, 780),
        ],
        _solid(const Color(0xFF3A4C5E)),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x + 2, 690, 36, 14),
          const Radius.circular(3),
        ),
        _solid(const Color(0xFF1CB9DA)),
      );
    }

    // 输送管与左端盖。
    const pipe = Rect.fromLTWH(160, 537, 380, 96);
    canvas.drawRect(
      pipe,
      _gradient(
        pipe,
        const [
          Color(0xFF3A4C5E),
          Color(0xFF8BA1B5),
          Color(0xFFC8D6E2),
          Color(0xFFDAE6F2),
          Color(0xFF8BA1B5),
          Color(0xFF3A4C5E),
        ],
        vertical: true,
        stops: const [0, .2, .4, .55, .75, 1],
      ),
    );
    canvas.drawRect(
      const Rect.fromLTWH(180, 558, 340, 14),
      _solid(const Color(0x24FFFFFF)),
    );
    _oval(
      canvas,
      160,
      585,
      20,
      48,
      _solid(const Color(0xFF3A4C5E)),
    );
    _oval(
      canvas,
      160,
      585,
      10,
      26,
      _solid(const Color(0xFF1F2B36)),
    );

    // 电机。
    _poly(
      canvas,
      const [
        Offset(540, 552),
        Offset(620, 552),
        Offset(642, 536),
        Offset(562, 536),
      ],
      _solid(const Color(0xFFD0DFE8)),
    );
    canvas.drawRect(
      const Rect.fromLTWH(540, 552, 80, 62),
      _gradient(
        const Rect.fromLTWH(540, 552, 80, 62),
        _front,
        vertical: true,
        stops: _frontStops,
      ),
    );
    _poly(
      canvas,
      const [
        Offset(620, 552),
        Offset(642, 536),
        Offset(642, 598),
        Offset(620, 614),
      ],
      _solid(const Color(0xFF40576A)),
    );
    for (final x in [560.0, 578.0, 596.0]) {
      _line(
        canvas,
        Offset(x, 556),
        Offset(x, 610),
        const Color(0x77334453),
        2.5,
      );
    }
    _oval(
      canvas,
      620,
      583,
      12,
      30,
      _solid(const Color(0xFF3A4C5E)),
    );
    _oval(
      canvas,
      620,
      583,
      5,
      14,
      _solid(const Color(0xFF22303C)),
    );

    // 料斗锥体、筒身和顶盖。
    _poly(
      canvas,
      const [
        Offset(230, 420),
        Offset(450, 420),
        Offset(392, 540),
        Offset(308, 540),
      ],
      _gradient(
        const Rect.fromLTWH(230, 420, 220, 120),
        _cylinder,
        stops: _cylinderStops,
      ),
    );
    canvas.drawRect(
      const Rect.fromLTWH(230, 250, 220, 170),
      _gradient(
        const Rect.fromLTWH(230, 250, 220, 170),
        _cylinder,
        stops: _cylinderStops,
      ),
    );
    canvas.drawRect(
      const Rect.fromLTWH(255, 256, 20, 160),
      _solid(const Color(0x24FFFFFF)),
    );
    _oval(
      canvas,
      340,
      250,
      120,
      33,
      _gradient(
        const Rect.fromLTWH(220, 217, 240, 66),
        const [
          Color(0xFFEAF3FA),
          Color(0xFFC2D3E1),
          Color(0xFF9FB3C6),
        ],
      ),
    );

// 圆柱与锥体接缝：一条略深的灰色过渡带。
    canvas.drawRect(
      const Rect.fromLTWH(230, 416, 220, 2),
      _solid(const Color.fromARGB(255, 128, 133, 137)),
    );

    const inlet = Rect.fromLTWH(308, 178, 64, 72);
    canvas.drawRect(
      inlet,
      _gradient(
        inlet,
        _cylinder,
        stops: _cylinderStops,
      ),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(298, 168, 84, 18),
        const Radius.circular(5),
      ),
      _solid(const Color(0xFF4A5C6E)),
    );
    _oval(canvas, 400, 220, 5, 5, _solid(_cyan));

    // 出料口。
    _poly(
      canvas,
      const [
        Offset(168, 630),
        Offset(212, 630),
        Offset(200, 700),
        Offset(180, 700),
      ],
      _gradient(
        const Rect.fromLTWH(168, 630, 44, 70),
        _cylinder,
        stops: _cylinderStops,
      ),
    );
    _oval(
      canvas,
      190,
      700,
      12,
      4,
      _solid(const Color(0xFF0A1017)),
    );
  }

  void _drawFilling(Canvas canvas) {
    // 加宽底座。
    _poly(
      canvas,
      const [
        Offset(774, 790),
        Offset(1206, 790),
        Offset(1228, 774),
        Offset(796, 774),
      ],
      _solid(const Color(0xFFC2D3E1)),
    );
    _poly(
      canvas,
      const [
        Offset(1206, 790),
        Offset(1228, 774),
        Offset(1228, 828),
        Offset(1206, 844),
      ],
      _solid(const Color(0xFF40576A)),
    );
    canvas.drawRect(
      const Rect.fromLTWH(774, 790, 432, 54),
      _gradient(
        const Rect.fromLTWH(774, 790, 432, 54),
        _front,
        vertical: true,
        stops: _frontStops,
      ),
    );
    _line(
      canvas,
      const Offset(804, 814),
      const Offset(1176, 814),
      _cyan.withOpacity(.55),
      4,
    );

    // 两侧立柱及传感器。
    for (final x in [826.0, 1114.0]) {
      canvas.drawRect(
        Rect.fromLTWH(x, 500, 40, 290),
        _gradient(
          Rect.fromLTWH(x, 500, 40, 290),
          const [
            Color(0xFF5A7085),
            Color(0xFF7E94A8),
            Color(0xFF3A4C5E),
          ],
          vertical: true,
        ),
      );
      _poly(
        canvas,
        [
          Offset(x + 40, 500),
          Offset(x + 58, 484),
          Offset(x + 58, 774),
          Offset(x + 40, 790),
        ],
        _solid(const Color(0xFF3A4C5E)),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x + 2, 700, 36, 16),
          const Radius.circular(3),
        ),
        _solid(const Color(0xFF1CB9DA)),
      );
    }

    // 秤台。
    _poly(
      canvas,
      const [
        Offset(906, 750),
        Offset(1074, 750),
        Offset(1094, 736),
        Offset(926, 736),
      ],
      _solid(const Color(0xFFC2D3E1)),
    );
    canvas.drawRect(
      const Rect.fromLTWH(906, 750, 168, 32),
      _gradient(
        const Rect.fromLTWH(906, 750, 168, 32),
        _front,
        vertical: true,
        stops: _frontStops,
      ),
    );

    // 金属罐：先画底壳和罐口，物料裁剪在内腔。
    // 金属罐：罐身宽度为 x=930..1070，底部用弧线收口。
    const can = Rect.fromLTWH(930, 560, 140, 200);
    final canShape = Path()
      ..moveTo(930, 560)
      ..lineTo(1070, 560)
      ..lineTo(1070, 740)
      ..quadraticBezierTo(1000, 780, 930, 740)
      ..close();

    canvas.drawPath(
      canShape,
      _gradient(
        can,
        const [
          Color(0xFF2A3844),
          Color(0xFF6B8098),
          Color(0xFFC2D3E1),
          Color(0xFFEAF3FA),
          Color(0xFFA4B8C9),
          Color(0xFF5C7085),
          Color(0xFF1F2B36),
        ],
        stops: const [0, .12, .28, .42, .58, .80, 1],
      ),
    );

// 保留原来的罐底与罐口层次。
    _oval(
      canvas,
      1000,
      740,
      70,
      20,
      _stroke(const Color(0x888FA5B8)),
    );
    _oval(
      canvas,
      1000,
      560,
      70,
      20,
      _solid(const Color(0xFF0D1A24)),
    );
    _oval(
      canvas,
      1000,
      560,
      60,
      15,
      _solid(const Color(0xFF050D14)),
    );

// 物料铺满 x=930..1070，由罐身外形裁掉底部多余部分。
    canvas.save();
    canvas.clipPath(canShape);

    const product = Rect.fromLTWH(930, 650, 140, 110);
    canvas.drawRect(
      product,
      _gradient(
        product,
        const [
          Color(0xFFA6F4FF),
          Color(0xFF4EC9E8),
          Color(0xFF0B5F7A),
        ],
        vertical: true,
        stops: const [0, .3, 1],
      ),
    );
    _oval(
      canvas,
      1000,
      650,
      70,
      16,
      _solid(const Color(0x55B8F6FF)),
    );

    canvas.restore();
    _oval(
      canvas,
      1000,
      560,
      70,
      20,
      _stroke(const Color(0xE0C8D7E4), 2.2),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(948, 572, 14, 158),
        const Radius.circular(7),
      ),
      _solid(const Color(0x38FFFFFF)),
    );

    // 料斗：圆柱与锥体连续的外形。
    final hopper = Path()
      ..moveTo(868, 220)
      ..lineTo(868, 356)
      ..quadraticBezierTo(868, 368, 882, 378)
      ..lineTo(938, 438)
      ..quadraticBezierTo(944, 444, 952, 444)
      ..lineTo(1048, 444)
      ..quadraticBezierTo(1056, 444, 1062, 438)
      ..lineTo(1118, 378)
      ..quadraticBezierTo(1132, 368, 1132, 356)
      ..lineTo(1132, 220)
      ..close();

    canvas.drawPath(
      hopper,
      _gradient(
        const Rect.fromLTWH(868, 220, 264, 224),
        _cylinder,
        stops: _cylinderStops,
      ),
    );

    // 内部物料限制在料斗轮廓内。
    canvas.save();
    canvas.clipPath(hopper);
    const fill = Rect.fromLTWH(870, 290, 260, 156);
    canvas.drawRect(
      fill,
      _gradient(
        fill,
        const [
          Color(0xFFBFEEF8),
          Color(0xFF4FB8D6),
        ],
        vertical: true,
      ),
    );
    _oval(
      canvas,
      1000,
      290,
      125,
      16,
      _solid(const Color(0x80E8FBFF)),
    );
    canvas.restore();

    canvas.drawPath(
      hopper,
      _stroke(const Color(0x998BA1B5), 1.2),
    );
    _oval(
      canvas,
      1000,
      220,
      132,
      28,
      _solid(const Color(0xFF3A4C5E)),
    );
    _oval(
      canvas,
      1000,
      220,
      113,
      22,
      _solid(const Color(0xFF1A2630)),
    );

    // 料位条。
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(880, 235, 12, 115),
        const Radius.circular(3),
      ),
      _solid(const Color(0xFF08131B)),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(880, 235, 12, 115),
        const Radius.circular(3),
      ),
      _gradient(
        const Rect.fromLTWH(880, 235, 12, 115),
        const [
          Color(0xFF8DF2FF),
          Color(0xFF0F8FB0),
        ],
        vertical: true,
      ),
    );

    // 灌装头及喷嘴。
    canvas.drawRect(
      const Rect.fromLTWH(940, 444, 120, 52),
      _gradient(
        const Rect.fromLTWH(940, 444, 120, 52),
        _front,
        vertical: true,
        stops: _frontStops,
      ),
    );
    _poly(
      canvas,
      const [
        Offset(970, 496),
        Offset(1030, 496),
        Offset(1022, 522),
        Offset(978, 522),
      ],
      _gradient(
        const Rect.fromLTWH(970, 496, 60, 26),
        _cylinder,
        stops: _cylinderStops,
      ),
    );
    _oval(
      canvas,
      1000,
      522,
      22,
      6,
      _solid(const Color(0xFF0A1017)),
    );
  }

  @override
  bool shouldRepaint(covariant _FeederPainter oldDelegate) =>
      oldDelegate.isFilling != isFilling || oldDelegate.selected != selected;
}

class _FactoryGridPainter extends CustomPainter {
  const _FactoryGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final area = Offset.zero & size;
    canvas.save();
    canvas.clipRect(area);

    // 深蓝绿底色：中心略亮，边缘较暗。
    canvas.drawRect(
      area,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -0.25),
          radius: 1.25,
          colors: [
            Color(0xFF173C3D),
            Color(0xFF0B2529),
            Color(0xFF040E15),
          ],
          stops: [0, .52, 1],
        ).createShader(area),
    );

    void ambientGlow({
      required Offset center,
      required double width,
      required double height,
      required Color color,
    }) {
      final rect = Rect.fromCenter(
        center: center,
        width: width,
        height: height,
      );
      canvas.drawOval(
        rect,
        Paint()
          ..shader = RadialGradient(
            colors: [color, color.withAlpha(0)],
          ).createShader(rect),
      );
    }

    // 不规则环境光：给画面纵深，不对应单个秤位。
    ambientGlow(
      center: Offset(size.width * .20, size.height * .28),
      width: size.width * .65,
      height: size.height * .70,
      color: const Color(0x2632A9A6),
    );
    ambientGlow(
      center: Offset(size.width * .83, size.height * .67),
      width: size.width * .62,
      height: size.height * .82,
      color: const Color(0x202D78BA),
    );
    ambientGlow(
      center: Offset(size.width * .50, size.height * 1.02),
      width: size.width * 1.10,
      height: size.height * .46,
      color: const Color(0x2024A9C3),
    );

    // 极淡的斜向漫射光；不是网格线，也不围住设备。
    void lightBeam(double startX, double endX, Color color) {
      final beam = Path()
        ..moveTo(size.width * startX, 0)
        ..lineTo(size.width * (startX + .12), 0)
        ..lineTo(size.width * (endX + .24), size.height)
        ..lineTo(size.width * endX, size.height)
        ..close();
      canvas.drawPath(beam, Paint()..color = color);
    }

    lightBeam(.08, .28, const Color(0x0C77DFDB));
    lightBeam(.62, .75, const Color(0x096BB8EA));

    // 轻微暗角，将注意力收回设备区域。
    canvas.drawRect(
      area,
      Paint()
        ..shader = const RadialGradient(
          radius: 1.15,
          colors: [
            Color(0x00000000),
            Color(0x00000000),
            Color(0x9901080C),
          ],
          stops: [0, .58, 1],
        ).createShader(area),
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FactoryGridPainter oldDelegate) => false;
}
