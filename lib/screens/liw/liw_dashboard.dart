import 'dart:async';
import 'liw_process_painter.dart';
import 'package:flutter/material.dart';
import 'package:weighing_system_elinux/weighing_system_elinux.dart';
import 'dart:math' as math;
import '../../l10n/app_localizations.dart';
import '../../providers/app_state.dart';
import '../../widgets/weight_display.dart';
import '../../widgets/status_indicator.dart';
import '../material_recipe_screen.dart';

const Color _themeBlue = Color(0xFF005C99);

class LiwDashboard extends StatefulWidget {
  const LiwDashboard({super.key});

  @override
  State<LiwDashboard> createState() => _LiwDashboardState();
}

class _LiwDashboardState extends State<LiwDashboard>
    with SingleTickerProviderStateMixin {
  Timer? _statusTimer;
  StreamSubscription? _weightSubscription; // 🚀 1. 新增：重量数据流订阅
  late AnimationController _animController;
  bool _axisTestEnabled = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    )..repeat();

    // 🚀 2. 核心优化：直接订阅底层的实时高频重量流 (20Hz)
    _weightSubscription = WeighingPlatform.instance.weightStream.listen((_) {
      if (mounted) {
        setState(() {}); // 只要底层有重量送上来，立刻触发重绘，极其丝滑
      }
    });

    // 🚀 3. 状态与流速计算属于慢变数据，依然用 200ms 定时器拉取即可
    _statusTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (mounted) {
        final state = AppStateProvider.of(context);
        state.refreshAppStatus();
        // debugPrint(
        //   '[LIW-Flow][UI] sub=${state.activeSubsystemId} '
        //   'state=${s.state}(${s.stateString}) flow=${s.currentFlow} '
        //   'target=${s.targetFlow} rate=${s.controlRate} '
        //   'weight=${s.currentWeight} acc=${s.accumulatedWeight} '
        //   'msg="${s.statusMessage}" warn=${s.warningActive}:${s.warningMessage}',
        // );
        setState(() {}); // 顺便重绘状态灯和流速等文字
      }
    });
  }

  @override
  void dispose() {
    _weightSubscription?.cancel(); // 🚀 4. 记得在销毁时取消流订阅，防止内存泄漏
    _statusTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final state = AppStateProvider.of(context);

    int currentScaleId = 0;
    try {
      currentScaleId = state.enabledSubsystems
          .firstWhere((sub) => sub.subsystemId == state.activeSubsystemId)
          .scaleId;
    } catch (_) {
      try {
        currentScaleId = state.subsystems
            .firstWhere((sub) => sub.subsystemId == state.activeSubsystemId)
            .scaleId;
      } catch (_) {
        currentScaleId = 0;
      }
    }

    final weightData = state.getWeightData(currentScaleId);
    final appStatus = state.getAppStatus(state.activeSubsystemId);

    final stateStr = appStatus.stateString.toLowerCase();
    final statusMessage = appStatus.statusMessage.toLowerCase();

    final isRefilling = stateStr.contains('refill') || stateStr.contains('补料');
    final isEmptying = stateStr.contains('empty') || stateStr.contains('清空');
    final isFeeding = ((stateStr.contains('feed') || stateStr.contains('喂料')) &&
            !isRefilling &&
            !isEmptying) ||
        statusMessage == 'feeding' ||
        statusMessage == 'startup';

    final processActive =
        isFeeding || (appStatus.isRunning && appStatus.currentFlow > 0);

    final statusColor = _getStatusColor(appStatus, isRefilling, isEmptying);

    Widget processPanel() {
      return _industrialPanel(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
              child: Row(
                children: [
                  const Icon(
                    Icons.precision_manufacturing_outlined,
                    color: Color(0xFF71D5E6),
                    size: 19,
                  ),
                  const SizedBox(width: 9),
                  const Expanded(
                    child: Text(
                      'PROCESS / LIW',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Color(0xFFD8E9F1),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ),
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    appStatus.stateString.toUpperCase(),
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .7,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFF294050)),
            Expanded(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: LiwProcessPainter(
                    clock: _animController,
                    isRefilling: isRefilling,
                    isFeeding: !isRefilling && !isEmptying && processActive,
                    isEmptying: isEmptying,
                    refillingLabel: l.refillingPhase,
                    feedingLabel: l.feedingPhase,
                    emptyingLabel: l.emptyingFlowPhase,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ],
        ),
      );
    }

    Widget meteringPanel({double rowHeight = 68}) {
      return _meteringPanel(
        rowHeight: rowHeight,
        accumulatedLabel: l.accumulatedWeight,
        accumulatedValue:
            '${appStatus.accumulatedWeight.toStringAsFixed(3)} ${weightData.unitString}',
        totalLabel: l.totalAccumulated,
        totalValue:
            '${appStatus.totalAccumulated.toStringAsFixed(3)} ${weightData.unitString}',
        grossLabel: l.grossWeight,
        grossValue:
            '${weightData.grossWeight.toStringAsFixed(3)} ${weightData.unitString}',
        tareLabel: l.tareWeight,
        tareValue:
            '${weightData.tareWeight.toStringAsFixed(3)} ${weightData.unitString}',
      );
    }

    Widget metrics(double width, {double cardHeight = 126}) {
      const gap = 12.0;
      final twoColumns = width >= 340;
      final tileWidth = twoColumns ? (width - gap) / 2 : width;

      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          _metricTile(
            width: tileWidth,
            height: cardHeight,
            icon: Icons.scale_outlined,
            label: l.netWeight,
            value: weightData.displayWeight.toStringAsFixed(3),
            unit: weightData.unitString,
          ),
          _metricTile(
            width: tileWidth,
            height: cardHeight,
            icon: Icons.speed_outlined,
            label: l.currentFlow,
            value: appStatus.currentFlow.toStringAsFixed(2),
            unit: '${weightData.unitString}/h',
            flowHighlight: true,
          ),
          _metricTile(
            width: tileWidth,
            height: cardHeight,
            icon: Icons.flag_outlined,
            label: appStatus.liwMode == 1 ? l.batchTarget : l.targetFlow,
            value: appStatus.liwMode == 1
                ? appStatus.targetWeight.toStringAsFixed(3)
                : appStatus.targetFlow.toStringAsFixed(2),
            unit: appStatus.liwMode == 1
                ? weightData.unitString
                : '${weightData.unitString}/h',
          ),
          _metricTile(
            width: tileWidth,
            height: cardHeight,
            icon: Icons.tune_outlined,
            label: l.controlRate,
            value: appStatus.controlRate.toStringAsFixed(1),
            unit: '%',
          ),
        ],
      );
    }

    Widget dataPanel() {
      return _industrialPanel(
        child: LayoutBuilder(
          builder: (context, constraints) {
            const padding = 14.0;
            const headerHeight = 32.0;
            const cardGap = 12.0;
            const sectionGap = 16.0;
            const minCardHeight = 126.0;
            const minRowHeight = 68.0;

            final contentWidth = math.max(
              0.0,
              constraints.maxWidth - padding * 2,
            );

            // 与 metrics()、_meteringPanel() 使用同样的分列阈值。
            final cardRows = contentWidth >= 340 ? 2 : 4;
            final meterRows = contentWidth >= 440 ? 2 : 4;

            // 包含标题、分隔线及边框的预留高度。
            // 略留余量；实际内容高于预估时由滚动视图兜底。
            const meterFrameHeight = 52.0;

            // 报警文字可能换行，不能假定其精确高度。
            // 这里先预留空间；超出时仍可滚动。
            final warningReserve = appStatus.warningActive ? 80.0 : 0.0;

            final minimumContentHeight = padding * 2 +
                headerHeight +
                cardRows * minCardHeight +
                (cardRows - 1) * cardGap +
                sectionGap +
                meterFrameHeight +
                meterRows * minRowHeight +
                warningReserve;

            final extraHeight = math.max(
              0.0,
              constraints.maxHeight - minimumContentHeight,
            );

            // 更多空间优先给核心数据，其次给计量行。
            final cardHeight = minCardHeight + extraHeight * .55 / cardRows;
            final rowHeight = minRowHeight + extraHeight * .45 / meterRows;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(padding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(
                    height: headerHeight,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'LIVE TELEMETRY',
                        style: TextStyle(
                          color: Color(0xFF8EA9B8),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.6,
                        ),
                      ),
                    ),
                  ),
                  metrics(
                    contentWidth,
                    cardHeight: cardHeight,
                  ),
                  const SizedBox(height: sectionGap),
                  meteringPanel(rowHeight: rowHeight),
                  if (appStatus.warningActive) ...[
                    const SizedBox(height: 14),
                    _warningBanner(appStatus.warningMessage),
                  ],
                ],
              ),
            );
          },
        ),
      );
    }

    return ColoredBox(
      color: const Color(0xFF0C1822),
      child: Column(
        children: [
          // 顶部：页面、子系统、配方和实时状态。
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            decoration: const BoxDecoration(
              color: Color(0xFF0B1D2B),
              border: Border(bottom: BorderSide(color: Color(0xFF29495B))),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final statusBadges = Wrap(
                  spacing: 9,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _headerBadge(
                      label: appStatus.stateString.isEmpty
                          ? '—'
                          : appStatus.stateString.toUpperCase(),
                      color: appStatus.isError
                          ? const Color(0xFFFF8F85)
                          : appStatus.isRunning
                              ? const Color(0xFF60E2B0)
                              : const Color(0xFF91ABBA),
                    ),
                    if (isRefilling)
                      _headerBadge(
                        label: l.refillingPhase,
                        color: const Color(0xFF62E3E5),
                      ),
                    _headerBadge(
                      label: weightData.isStable ? l.stable : l.inMotion,
                      color: weightData.isStable
                          ? const Color(0xFF60E2B0)
                          : const Color(0xFFF5BF68),
                    ),
                  ],
                );

                final identity = Wrap(
                  spacing: 18,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      l.lossInWeight,
                      style: const TextStyle(
                        color: Color(0xFFEFFAFF),
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '子系统 #${state.activeSubsystemId}',
                      style: const TextStyle(
                        color: Color(0xFF91ABBA),
                        fontSize: 14,
                      ),
                    ),
                  ],
                );

                final recipe = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${l.recipeBtn}  ',
                      style: const TextStyle(
                        color: Color(0xFF91ABBA),
                        fontSize: 14,
                      ),
                    ),
                    // 当前代码未提供已选配方名称，不能写入示例配方。
                    const Text(
                      '—',
                      style: TextStyle(
                        color: Color(0xFFEFFAFF),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                );

                if (constraints.maxWidth >= 1100) {
                  return Row(
                    children: [
                      identity,
                      const SizedBox(width: 22),
                      Container(
                        width: 1,
                        height: 28,
                        color: const Color(0xFF38596A),
                      ),
                      const SizedBox(width: 20),
                      recipe,
                      const Spacer(),
                      statusBadges,
                    ],
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    identity,
                    const SizedBox(height: 9),
                    recipe,
                    const SizedBox(height: 12),
                    statusBadges,
                  ],
                );
              },
            ),
          ),

          // 主区域：宽屏左右分栏；窄屏上下排列。
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 950;

                if (wide) {
                  return Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 42, child: processPanel()),
                        const SizedBox(width: 14),
                        Expanded(flex: 58, child: dataPanel()),
                      ],
                    ),
                  );
                }

                final processHeight = math.min(
                  460.0,
                  math.max(320.0, constraints.maxHeight * .60),
                );

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      SizedBox(height: processHeight, child: processPanel()),
                      const SizedBox(height: 12),
                      // 窄屏使用确定的内容高度，由外层统一滚动。
                      _industrialPanel(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: LayoutBuilder(
                            builder: (context, inner) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    'LIVE TELEMETRY',
                                    style: TextStyle(
                                      color: Color(0xFF8EA9B8),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.6,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  metrics(inner.maxWidth),
                                  const SizedBox(height: 16),
                                  meteringPanel(),
                                  if (appStatus.warningActive) ...[
                                    const SizedBox(height: 14),
                                    _warningBanner(appStatus.warningMessage),
                                  ],
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // 底部操作区始终可见；空间不足时仅操作区横向滚动。
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            decoration: const BoxDecoration(
              color: Color(0xFF0B1D2B),
              border: Border(top: BorderSide(color: Color(0xFF315365))),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '设备操作',
                  style: TextStyle(color: Color(0xFF91ABBA), fontSize: 12),
                ),
                const SizedBox(height: 8),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final buttons = <Widget>[
                      _commandButton(
                        label: appStatus.isRunning ? l.stop : l.start,
                        icon: appStatus.isRunning
                            ? Icons.stop_rounded
                            : Icons.play_arrow_rounded,
                        primary: true,
                        stop: appStatus.isRunning,
                        onTap: () => appStatus.isRunning
                            ? state.stopApp(state.activeSubsystemId)
                            : state.startApp(state.activeSubsystemId),
                      ),
                      _commandButton(
                        label: l.zero,
                        icon: Icons.exposure_zero,
                        onTap: () => state.doZero(currentScaleId),
                      ),
                      _commandButton(
                        label: l.tare,
                        icon: Icons.remove_circle_outline,
                        onTap: () => state.doTare(currentScaleId),
                      ),
                      _commandButton(
                        label: l.clearTare,
                        icon: Icons.layers_clear_outlined,
                        onTap: () => state.clearTare(currentScaleId),
                      ),
                      _commandButton(
                        label: l.eprint,
                        icon: Icons.print_outlined,
                        selected: _axisTestEnabled,
                        onTap: () => setState(
                          () => _axisTestEnabled = !_axisTestEnabled,
                        ),
                      ),
                      _commandButton(
                        label: l.recipeBtn,
                        icon: Icons.playlist_add_check,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => MaterialRecipeScreen(
                              appType: 0,
                              subsystemId: state.activeSubsystemId,
                            ),
                          ),
                        ),
                      ),
                    ];

                    const widths = <int>[205, 145, 145, 182, 145, 166];

                    if (constraints.maxWidth >= 1050) {
                      return Row(
                        children: [
                          for (var i = 0; i < buttons.length; i++) ...[
                            if (i > 0) const SizedBox(width: 10),
                            Expanded(flex: widths[i], child: buttons[i]),
                          ],
                        ],
                      );
                    }

                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (var i = 0; i < buttons.length; i++) ...[
                            if (i > 0) const SizedBox(width: 10),
                            SizedBox(
                              width: widths[i].toDouble(),
                              child: buttons[i],
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _industrialPanel({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF142633),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A4353)),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  Widget _headerBadge({required String label, required Color color}) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String text, Color color, bool active) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 240),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(.10),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withOpacity(.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? color : color.withOpacity(.65),
            ),
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _compactMetric({
    required double width,
    required String label,
    required String value,
  }) {
    return Container(
      width: width,
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFF182D3B),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xFF294453)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF91A9B8), fontSize: 11),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFE3F1F5),
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricTile({
    required double width,
    required IconData icon,
    required String label,
    required String value,
    required String unit,
    bool flowHighlight = false,
    double height = 126,
  }) {
    return Container(
      width: width,
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF153748),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: const Color(0xFF31596A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(width: 4, color: const Color(0xFF62E3E5)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 17, 14, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 17, color: const Color(0xFF91ABBA)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFAAC0CC),
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          value,
                          style: TextStyle(
                            color: flowHighlight
                                ? const Color(0xFF62E3E5)
                                : const Color(0xFFEFFAFF),
                            fontSize: 36,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          unit,
                          style: const TextStyle(
                            color: Color(0xFF91ABBA),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _meteringPanel({
    double rowHeight = 68,
    required String accumulatedLabel,
    required String accumulatedValue,
    required String totalLabel,
    required String totalValue,
    required String grossLabel,
    required String grossValue,
    required String tareLabel,
    required String tareValue,
  }) {
    const dividerColor = Color(0xFF2C4E60);

    Widget cell(String label, String value) {
      return SizedBox(
        height: rowHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 17),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF91ABBA),
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: Color(0xFFEFFAFF),
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF122F40),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF31596A)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final twoColumns = constraints.maxWidth >= 440;

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(
                height: 48,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '计量与累计',
                      style: TextStyle(
                        color: Color(0xFFEFFAFF),
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              const Divider(height: 1, color: dividerColor),
              if (twoColumns) ...[
                Row(
                  children: [
                    Expanded(child: cell(accumulatedLabel, accumulatedValue)),
                    Container(width: 1, height: rowHeight, color: dividerColor),
                    Expanded(child: cell(totalLabel, totalValue)),
                  ],
                ),
                const Divider(height: 1, color: dividerColor),
                Row(
                  children: [
                    Expanded(child: cell(grossLabel, grossValue)),
                    Container(width: 1, height: rowHeight, color: dividerColor),
                    Expanded(child: cell(tareLabel, tareValue)),
                  ],
                ),
              ] else ...[
                cell(accumulatedLabel, accumulatedValue),
                const Divider(height: 1, color: dividerColor),
                cell(totalLabel, totalValue),
                const Divider(height: 1, color: dividerColor),
                cell(grossLabel, grossValue),
                const Divider(height: 1, color: dividerColor),
                cell(tareLabel, tareValue),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _warningBanner(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF3D3025),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xFFAB7941)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: Color(0xFFFFBA65),
            size: 20,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFFFFDCAD), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _commandButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    bool primary = false,
    bool stop = false,
    bool selected = false,
  }) {
    final background = stop
        ? const Color(0xFFAC514F)
        : primary
            ? const Color(0xFF19A994)
            : selected
                ? const Color(0xFF23566A)
                : const Color(0xFF1B3A4C);

    final borderColor = primary
        ? background
        : selected
            ? const Color(0xFF62E3E5)
            : const Color(0xFF456A7B);

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 54,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 21, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFFF4FBFC),
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(AppStatusData status, bool refilling, bool emptying) {
    if (status.isError) return Colors.red;
    if (refilling) return _themeBlue; // 补料状态使用主题蓝
    if (emptying) return Colors.orange;
    if (status.isRunning) return Colors.green;
    return Colors.grey;
  }

  String _getModeString(AppLocalizations l, AppStatusData status) {
    switch (status.liwMode) {
      case 1:
        return l.batch;
      case 2:
        return l.systemId;
      case 0:
      default:
        return l.continuous;
    }
  }
}

class _HighlightDataRow extends StatelessWidget {
  final String label, value, unit;
  final Color color;
  const _HighlightDataRow(this.label, this.value, this.unit, this.color);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 14, color: Colors.grey)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  unit,
                  style: TextStyle(fontSize: 16, color: color.withOpacity(0.8)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DataRow extends StatelessWidget {
  final String label, value;
  const _DataRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 1,
            child: Text(
              label,
              style: const TextStyle(fontSize: 15),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 1,
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _LargeActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color? color;
  final bool isPrimary;
  final VoidCallback onPressed;

  const _LargeActionButton({
    required this.label,
    required this.icon,
    this.color,
    this.isPrimary = false,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: isPrimary ? 3 : 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            backgroundColor:
                color ?? Theme.of(context).colorScheme.surfaceVariant,
            foregroundColor: color != null
                ? Colors.white
                : Theme.of(context).colorScheme.onSurface,
            elevation: isPrimary ? 4 : 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: onPressed,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
