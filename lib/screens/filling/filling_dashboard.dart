import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:weighing_system_elinux/weighing_system_elinux.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/app_state.dart';
import '../material_recipe_screen.dart';

class FillingDashboard extends StatefulWidget {
  const FillingDashboard({super.key});

  @override
  State<FillingDashboard> createState() => _FillingDashboardState();
}

class _FillingDashboardState extends State<FillingDashboard>
    with SingleTickerProviderStateMixin {
  static const _background = Color(0xFF0C1822);
  static const _panel = Color(0xFF102B3B);
  static const _panelBorder = Color(0xFF2C5062);
  static const _cyan = Color(0xFF62E3E5);
  static const _muted = Color(0xFF91ABBA);
  static const _bright = Color(0xFFEFFAFF);

  Timer? _statusTimer;
  StreamSubscription<dynamic>? _weightSubscription;
  late final AnimationController _animation;

  @override
  void initState() {
    super.initState();

    _animation = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _weightSubscription = WeighingPlatform.instance.weightStream.listen((_) {
      if (mounted) setState(() {});
    });

    _statusTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      AppStateProvider.of(context).refreshAppStatus();
      setState(() {});
    });
  }

  @override
  void dispose() {
    _weightSubscription?.cancel();
    _statusTimer?.cancel();
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final state = AppStateProvider.of(context);

    int scaleId = 0;
    try {
      scaleId = state.enabledSubsystems
          .firstWhere((sub) => sub.subsystemId == state.activeSubsystemId)
          .scaleId;
    } catch (_) {
      try {
        scaleId = state.subsystems
            .firstWhere((sub) => sub.subsystemId == state.activeSubsystemId)
            .scaleId;
      } catch (_) {
        scaleId = 0;
      }
    }

    final wd = state.getWeightData(scaleId);
    final status = state.getAppStatus(state.activeSubsystemId);

    final stateText = status.stateString.toLowerCase();
    final isEmptying = stateText.contains('empty') || stateText.contains('清空');
    final isFastFeed = stateText.contains('fast') || stateText.contains('粗流');
    final isFeeding = !isEmptying &&
        (stateText.contains('feed') ||
            stateText.contains('喂料') ||
            stateText.contains('fill') ||
            stateText.contains('灌装'));

    final fillPercentage = status.targetWeight > 0
        ? (wd.netWeight / status.targetWeight).clamp(0.0, 1.0).toDouble()
        : 0.0;

    final statusColor = status.isError
        ? const Color(0xFFFF8F85)
        : isEmptying
            ? const Color(0xFFF5BF68)
            : status.isRunning
                ? const Color(0xFF60E2B0)
                : _muted;

    Widget processPanel() {
      return _panelBox(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 15, 20, 13),
              child: Row(
                children: [
                  const Icon(
                    Icons.precision_manufacturing_outlined,
                    size: 20,
                    color: _cyan,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      l.filling,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _bright,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    isEmptying
                        ? l.emptyingPhase
                        : isFeeding
                            ? (isFastFeed ? l.fastFeedPhase : l.fineFeedPhase)
                            : status.stateString,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFF29495B)),
            Expanded(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _FillingProcessPainter(
                    clock: _animation,
                    isFeeding: isFeeding,
                    isFastFeed: isFastFeed,
                    isEmptying: isEmptying,
                    fillPercentage: fillPercentage,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            const Divider(height: 1, color: Color(0xFF29495B)),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 11),
              child: Row(
                children: [
                  Icon(
                    Icons.circle,
                    size: 9,
                    color: wd.isStable
                        ? const Color(0xFF60E2B0)
                        : const Color(0xFFF5BF68),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      wd.isStable ? l.stable : l.inMotion,
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Text(
                    '${(fillPercentage * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(
                      color: _cyan,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    Widget dataPanel() {
      return _panelBox(
        child: LayoutBuilder(
          builder: (context, constraints) {
            const padding = 16.0;
            const gap = 12.0;
            final contentWidth =
                math.max(0.0, constraints.maxWidth - padding * 2);
            final twoColumns = contentWidth >= 420;
            final cardWidth =
                twoColumns ? (contentWidth - gap) / 2 : contentWidth;

            // 先保证可读的最小尺寸，再将剩余高度分给卡片和计量框。
            // 空间不足由右侧面板单独滚动，不挤压底部按钮。
            final cardRows = twoColumns ? 2 : 4;
            const minCardHeight = 108.0;
            const minMeterHeight = 155.0;
            const progressHeight = 74.0;
            const titleHeight = 38.0;
            final warningReserve = status.warningActive ? 74.0 : 0.0;

            final minimumHeight = padding * 2 +
                titleHeight +
                cardRows * minCardHeight +
                (cardRows - 1) * gap +
                gap +
                minMeterHeight +
                gap +
                progressHeight +
                warningReserve;

            final extra = constraints.maxHeight.isFinite
                ? math.max(0.0, constraints.maxHeight - minimumHeight)
                : 0.0;
            final cardHeight = minCardHeight + extra * .55 / cardRows;
            final meterHeight = minMeterHeight + extra * .45;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(padding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: titleHeight,
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Text(
                        l.targetValues,
                        style: const TextStyle(
                          color: _bright,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      _metricCard(
                        width: cardWidth,
                        height: cardHeight,
                        label: l.batchTarget,
                        value: status.targetWeight.toStringAsFixed(3),
                        unit: wd.unitString,
                      ),
                      _metricCard(
                        width: cardWidth,
                        height: cardHeight,
                        label: l.weight,
                        value: wd.displayWeight.toStringAsFixed(3),
                        unit: wd.unitString,
                        highlighted: true,
                      ),
                      _metricCard(
                        width: cardWidth,
                        height: cardHeight,
                        label: l.controlRate,
                        value: status.controlRate.toStringAsFixed(1),
                        unit: '%',
                      ),
                      _metricCard(
                        width: cardWidth,
                        height: cardHeight,
                        label: l.fillProgress,
                        value: (fillPercentage * 100).toStringAsFixed(1),
                        unit: '%',
                      ),
                    ],
                  ),
                  const SizedBox(height: gap),
                  _meteringBox(
                    height: meterHeight,
                    twoColumns: twoColumns,
                    items: [
                      (
                        l.accumulatedWeight,
                        '${status.accumulatedWeight.toStringAsFixed(3)} ${wd.unitString}'
                      ),
                      (
                        l.totalAccumulated,
                        '${status.totalAccumulated.toStringAsFixed(3)} ${wd.unitString}'
                      ),
                      (
                        l.grossWeight,
                        '${wd.grossWeight.toStringAsFixed(3)} ${wd.unitString}'
                      ),
                      (
                        l.tareWeight,
                        '${wd.tareWeight.toStringAsFixed(3)} ${wd.unitString}'
                      ),
                    ],
                  ),
                  const SizedBox(height: gap),
                  Container(
                    height: progressHeight,
                    padding: const EdgeInsets.fromLTRB(15, 11, 15, 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF153748),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(
                        color: const Color(0xFF31596A),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                l.fillProgress,
                                style: const TextStyle(
                                  color: _muted,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            Text(
                              '${(fillPercentage * 100).toStringAsFixed(1)}%',
                              style: const TextStyle(
                                color: _bright,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: LinearProgressIndicator(
                            value: fillPercentage,
                            minHeight: 10,
                            backgroundColor: const Color(0xFF29495B),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              fillPercentage >= 1
                                  ? const Color(0xFF60E2B0)
                                  : _cyan,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (status.warningActive) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF453624),
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                          color: const Color(0xFFA48143),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            color: Color(0xFFF5BF68),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              status.warningMessage,
                              style: const TextStyle(
                                color: Color(0xFFFFE0A6),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      );
    }

    final actions = <Widget>[
      _actionButton(
        label: status.isRunning ? l.stop : l.start,
        icon: status.isRunning ? Icons.stop_rounded : Icons.play_arrow_rounded,
        primary: true,
        stop: status.isRunning,
        onTap: () => status.isRunning
            ? state.stopApp(state.activeSubsystemId)
            : state.startApp(state.activeSubsystemId),
      ),
      _actionButton(
        label: l.zero,
        icon: Icons.exposure_zero,
        onTap: () => state.doZero(scaleId),
      ),
      _actionButton(
        label: l.tare,
        icon: Icons.remove_circle_outline,
        onTap: () => state.doTare(scaleId),
      ),
      _actionButton(
        label: l.clearTare,
        icon: Icons.layers_clear_outlined,
        onTap: () => state.clearTare(scaleId),
      ),
      // 原文件未实现打印功能，保留占位但不伪装成已完成操作。
      _actionButton(
        label: l.eprint,
        icon: Icons.print_outlined,
        onTap: null,
      ),
      _actionButton(
        label: l.recipeBtn,
        icon: Icons.playlist_add_check,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MaterialRecipeScreen(
              appType: 1,
              subsystemId: state.activeSubsystemId,
            ),
          ),
        ),
      ),
    ];

    return ColoredBox(
      color: _background,
      child: Column(
        children: [
          // 顶栏：不虚构设备编号或当前配方名称。
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 13,
            ),
            decoration: const BoxDecoration(
              color: Color(0xFF0B1D2B),
              border: Border(
                bottom: BorderSide(color: Color(0xFF29495B)),
              ),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16,
              runSpacing: 9,
              children: [
                Wrap(
                  spacing: 18,
                  runSpacing: 5,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      l.filling,
                      style: const TextStyle(
                        color: _bright,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '子系统 #${state.activeSubsystemId}',
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 9,
                  runSpacing: 8,
                  children: [
                    _statusBadge(
                      status.stateString.isEmpty
                          ? '—'
                          : status.stateString.toUpperCase(),
                      statusColor,
                    ),
                    _statusBadge(
                      wd.isStable ? l.stable : l.inMotion,
                      wd.isStable
                          ? const Color(0xFF60E2B0)
                          : const Color(0xFFF5BF68),
                    ),
                  ],
                ),
              ],
            ),
          ),

          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= 900) {
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

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      SizedBox(
                        height: 380,
                        child: processPanel(),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 540,
                        child: dataPanel(),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 9, 20, 12),
            decoration: const BoxDecoration(
              color: Color(0xFF0B1D2B),
              border: Border(
                top: BorderSide(color: Color(0xFF315365)),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.filling,
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                LayoutBuilder(
                  builder: (context, constraints) {
                    const gap = 10.0;
                    const widths = <double>[
                      205,
                      145,
                      145,
                      182,
                      145,
                      166,
                    ];
                    final requiredWidth = widths.reduce((a, b) => a + b) +
                        gap * (actions.length - 1);

                    if (constraints.maxWidth >= requiredWidth) {
                      return Row(
                        children: [
                          for (var i = 0; i < actions.length; i++) ...[
                            if (i > 0) const SizedBox(width: gap),
                            Expanded(
                              flex: widths[i].toInt(),
                              child: actions[i],
                            ),
                          ],
                        ],
                      );
                    }

                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (var i = 0; i < actions.length; i++) ...[
                            if (i > 0) const SizedBox(width: gap),
                            SizedBox(
                              width: widths[i],
                              child: actions[i],
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

  Widget _panelBox({required Widget child}) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _panelBorder),
      ),
      child: child,
    );
  }

  Widget _statusBadge(String label, Color color) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 210),
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(.11),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(radius: 4, backgroundColor: color),
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

  Widget _metricCard({
    required double width,
    required double height,
    required String label,
    required String value,
    required String unit,
    bool highlighted = false,
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
          Container(width: 4, color: _cyan),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 14,
                    ),
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
                            color: highlighted ? _cyan : _bright,
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          unit,
                          style: const TextStyle(
                            color: _muted,
                            fontSize: 13,
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

  Widget _meteringBox({
    required double height,
    required bool twoColumns,
    required List<(String, String)> items,
  }) {
    const divider = Color(0xFF2C4E60);
    final rows = twoColumns ? 2 : 4;
    final rowHeight = math.max(
      38.0,
      (height - 44 - (rows - 1)) / rows,
    );

    Widget cell((String, String) item) {
      return SizedBox(
        height: rowHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  item.$1,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  item.$2,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: _bright,
                    fontSize: 17,
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
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: const Color(0xFF31596A)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            height: 43,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  '计量与累计',
                  style: TextStyle(
                    color: _bright,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          const Divider(height: 1, color: divider),
          if (twoColumns) ...[
            for (var row = 0; row < 2; row++) ...[
              if (row > 0) const Divider(height: 1, color: divider),
              Row(
                children: [
                  Expanded(child: cell(items[row * 2])),
                  Container(
                    width: 1,
                    height: rowHeight,
                    color: divider,
                  ),
                  Expanded(child: cell(items[row * 2 + 1])),
                ],
              ),
            ],
          ] else ...[
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: divider),
              cell(items[i]),
            ],
          ],
        ],
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required VoidCallback? onTap,
    bool primary = false,
    bool stop = false,
  }) {
    final background = primary
        ? stop
            ? const Color(0xFFAC514F)
            : const Color(0xFF19A994)
        : const Color(0xFF1B3A4C);

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 54,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: primary ? background : const Color(0xFF456A7B),
            ),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 21,
                  color: onTap == null ? _muted : Colors.white,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: onTap == null ? _muted : const Color(0xFFF4FBFC),
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
}

/// 根据提供的 SVG 绘制灌装设备。
/// 背景透明；罐内液位由实际 fillPercentage 驱动。
class _FillingProcessPainter extends CustomPainter {
  _FillingProcessPainter({
    required this.clock,
    required this.isFeeding,
    required this.isFastFeed,
    required this.isEmptying,
    required this.fillPercentage,
  }) : super(repaint: clock);

  final AnimationController clock;
  final bool isFeeding;
  final bool isFastFeed;
  final bool isEmptying;
  final double fillPercentage;

  static const _cyan = Color(0xFF62E3E5);
  static const _pale = Color(0xFFB8F6FF);
  static const _outline = Color(0xFF89A8B5);

  // 原 SVG 是 800×950；这里只适配设备实际占用的区域，
  // 避免在横向面板中因为原画布上下留白而显得过小。
  static const _deviceBounds = Rect.fromLTRB(105, 125, 735, 830);

  static const _metal = <Color>[
    Color(0xFF263B49),
    Color(0xFF58798A),
    Color(0xFF9AB9C6),
    Color(0xFFD7E7EB),
    Color(0xFFA4C0CA),
    Color(0xFF638593),
    Color(0xFF355565),
    Color(0xFF203542),
  ];

  static const _metalStops = <double>[
    0,
    .12,
    .28,
    .40,
    .55,
    .75,
    .92,
    1,
  ];

  Paint _solid(Color color) => Paint()
    ..isAntiAlias = true
    ..color = color;

  Paint _linePaint(Color color, [double width = 1]) => Paint()
    ..isAntiAlias = true
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  Paint _horizontal(Rect area, List<Color> colors, {List<double>? stops}) =>
      Paint()
        ..isAntiAlias = true
        ..shader = LinearGradient(
          colors: colors,
          stops: stops,
        ).createShader(area);

  Paint _vertical(Rect area, List<Color> colors, {List<double>? stops}) =>
      Paint()
        ..isAntiAlias = true
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
          stops: stops,
        ).createShader(area);

  Paint _metalPaint() => _horizontal(
        const Rect.fromLTWH(132, 0, 536, 1),
        _metal,
        stops: _metalStops,
      );

  void _rect(Canvas canvas, Rect rect, Paint paint) {
    canvas.drawRect(rect, paint);
  }

  void _rounded(Canvas canvas, Rect rect, double radius, Paint paint) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      paint,
    );
  }

  void _ellipse(
      Canvas canvas, double x, double y, double rx, double ry, Paint paint) {
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(x, y),
        width: rx * 2,
        height: ry * 2,
      ),
      paint,
    );
  }

  void _line(
      Canvas canvas, double x1, double y1, double x2, double y2, Color color,
      [double width = 1]) {
    canvas.drawLine(
      Offset(x1, y1),
      Offset(x2, y2),
      _linePaint(color, width),
    );
  }

  Path _polygon(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    return path..close();
  }

  double _fraction(double value) => value - value.floorToDouble();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    const padding = 14.0;
    final availableWidth = size.width - padding * 2;
    final availableHeight = size.height - padding * 2;
    if (availableWidth <= 0 || availableHeight <= 0) return;

    final scale = math.min(
      availableWidth / _deviceBounds.width,
      availableHeight / _deviceBounds.height,
    );

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(
      (size.width - _deviceBounds.width * scale) / 2 -
          _deviceBounds.left * scale,
      (size.height - _deviceBounds.height * scale) / 2 -
          _deviceBounds.top * scale,
    );
    canvas.scale(scale);

    // 不画 SVG 背景，由仪表盘左侧面板负责背景。
    _drawFrame(canvas);
    _drawHopper(canvas);
    _drawNozzle(canvas);
    _drawCan(canvas);
    _drawScaleAndBase(canvas);

    canvas.restore();
  }

  void _drawFrame(Canvas canvas) {
    // 左右立柱。
    for (final x in [132.0, 620.0]) {
      final rect = Rect.fromLTWH(x, 140, 48, 630);
      _rect(
        canvas,
        rect,
        _horizontal(
          rect,
          const [
            Color(0xFF294353),
            Color(0xFF89AAB7),
            Color(0xFF537686),
            Color(0xFF203542),
          ],
        ),
      );

      final side = _polygon([
        Offset(x + 48, 140),
        Offset(x + 60, 130),
        Offset(x + 60, 760),
        Offset(x + 48, 770),
      ]);
      canvas.drawPath(side, _solid(const Color(0xFF283E4B)));

      canvas.drawPath(
        _polygon([
          Offset(x, 140),
          Offset(x + 48, 140),
          Offset(x + 60, 130),
          Offset(x + 12, 130),
        ]),
        _solid(const Color(0xFF617E8C)),
      );
    }

    // 顶部横梁。
    _rect(
      canvas,
      const Rect.fromLTWH(132, 140, 536, 45),
      _metalPaint(),
    );
    canvas.drawPath(
      _polygon(const [
        Offset(132, 140),
        Offset(668, 140),
        Offset(680, 130),
        Offset(144, 130),
      ]),
      _solid(const Color(0xFF617E8C)),
    );
    _rect(
      canvas,
      const Rect.fromLTWH(132, 178, 536, 7),
      _solid(const Color(0x590A1219)),
    );
  }

  void _drawHopper(Canvas canvas) {
    // 料斗筒身与锥体。
    _rect(
      canvas,
      const Rect.fromLTWH(285, 200, 230, 115),
      _metalPaint(),
    );

    final cone = _polygon(const [
      Offset(285, 315),
      Offset(515, 315),
      Offset(422, 368),
      Offset(378, 368),
    ]);
    canvas.drawPath(cone, _metalPaint());

    // SVG 的 hopperClip：物料只在料斗内部出现。
    final hopperClip = _polygon(const [
      Offset(285, 200),
      Offset(515, 200),
      Offset(515, 315),
      Offset(422, 368),
      Offset(378, 368),
      Offset(285, 315),
    ]);

    canvas.save();
    canvas.clipPath(hopperClip);

    // 料斗物料随真实灌装状态缓慢变化，但仅作设备动画示意；
    // 不把罐体的净重百分比当作料斗料位。
    final hopperLevel = isFeeding ? .76 - .14 * clock.value : .72;
    final materialTop = 368 - 140 * hopperLevel;

    _rect(
      canvas,
      Rect.fromLTRB(280, materialTop, 520, 375),
      _vertical(
        Rect.fromLTRB(280, materialTop, 520, 375),
        const [
          Color(0x99B7E5EA),
          Color(0xAA438FA4),
        ],
      ),
    );
    _ellipse(
      canvas,
      400,
      materialTop,
      120,
      10,
      _solid(const Color(0x80DDF8FA)),
    );
    canvas.restore();

    // 料斗前景高光、暗边及加强环。
    _rect(
      canvas,
      const Rect.fromLTWH(360, 206, 18, 104),
      _solid(const Color(0x55FFFFFF)),
    );
    _rect(
      canvas,
      const Rect.fromLTWH(285, 200, 18, 115),
      _solid(const Color(0x440A1219)),
    );
    _rect(
      canvas,
      const Rect.fromLTWH(497, 200, 18, 115),
      _solid(const Color(0x380A1219)),
    );
    _rect(
      canvas,
      const Rect.fromLTWH(285, 300, 230, 9),
      _solid(const Color(0x88283E4B)),
    );

    // 左侧料位指示条。此处是动画示意，不是料斗测量值。
    _rounded(
      canvas,
      const Rect.fromLTWH(300, 215, 12, 130),
      3,
      _solid(const Color(0xFF081923)),
    );
    final levelHeight = 130 * hopperLevel;
    _rounded(
      canvas,
      Rect.fromLTWH(300, 345 - levelHeight, 12, levelHeight),
      3,
      _vertical(
        const Rect.fromLTWH(300, 215, 12, 130),
        const [Color(0xFF8DF2FF), Color(0xFF0F8FB0)],
      ),
    );
    for (final y in [240.0, 270.0, 300.0, 330.0]) {
      _line(canvas, 296, y, 316, y, const Color(0x995F7A8D));
    }

    // 加料管。
    const feedPipe = Rect.fromLTWH(378, 368, 44, 62);
    _rect(
      canvas,
      feedPipe,
      _horizontal(
        feedPipe,
        const [
          Color(0xFF294453),
          Color(0xFF83A6B4),
          Color(0xFFCCE2E8),
          Color(0xFF7799A8),
          Color(0xFF294453),
        ],
      ),
    );
    _rect(
      canvas,
      const Rect.fromLTWH(386, 372, 7, 54),
      _solid(const Color(0x66FFFFFF)),
    );

    canvas.drawCircle(
      const Offset(446, 390),
      6,
      _solid(
        _cyan.withOpacity(isFeeding && !isEmptying ? 1 : .25),
      ),
    );
  }

  void _drawNozzle(Canvas canvas) {
    const head = Rect.fromLTWH(352, 430, 96, 42);
    _rounded(
      canvas,
      head,
      7,
      _vertical(
        head,
        const [
          Color(0xFF203744),
          Color(0xFF8EADBA),
          Color(0xFFC6DDE3),
          Color(0xFF416575),
          Color(0xFF1B303C),
        ],
      ),
    );

    final funnel = _polygon(const [
      Offset(370, 472),
      Offset(430, 472),
      Offset(422, 488),
      Offset(378, 488),
    ]);
    canvas.drawPath(funnel, _metalPaint());
    _ellipse(
      canvas,
      400,
      488,
      22,
      6,
      _solid(const Color(0xFF0A1017)),
    );
  }

  void _drawCan(Canvas canvas) {
    const body = Rect.fromLTWH(340, 488, 120, 157);

    // 罐身背板与罐底。
    _rect(
      canvas,
      body,
      _horizontal(
        body,
        const [
          Color(0xFF263B49),
          Color(0xFF7395A4),
          Color(0xFFBDD6DF),
          Color(0xFFD7E7EB),
          Color(0xFF8EADBA),
          Color(0xFF355565),
          Color(0xFF203542),
        ],
      ),
    );
    _ellipse(
      canvas,
      400,
      645,
      60,
      16,
      _horizontal(
        body,
        const [
          Color(0xFF294453),
          Color(0xFFBDD6DF),
          Color(0xFF355565),
        ],
      ),
    );

    // 罐内深色开口。
    _ellipse(
      canvas,
      400,
      488,
      60,
      16,
      _solid(const Color(0xFF0D1A24)),
    );
    _ellipse(
      canvas,
      400,
      488,
      52,
      12,
      _solid(const Color(0xFF050D14)),
    );

    // 等价于 SVG 的 <clipPath id="canInner">。
    // 只在 340..460 / 488..645 内绘制物料。
    final level = fillPercentage.isFinite
        ? fillPercentage.clamp(0.0, 1.0).toDouble()
        : 0.0;

    // 罐体两端各预留少量边缘，顶部留出开口。
    final liquidHeight = 153 * level;
    final liquidTop = 645 - liquidHeight;

    canvas.save();
    canvas.clipRect(body);

    if (liquidHeight > 0) {
      final liquidRect = Rect.fromLTRB(340, liquidTop, 460, 645);
      _rect(
        canvas,
        liquidRect,
        _vertical(
          liquidRect,
          const [
            Color(0xFFA6F4FF),
            Color(0xFF4EC9E8),
            Color(0xFF0B5F7A),
          ],
          stops: const [0, .30, 1],
        ),
      );

      _ellipse(
        canvas,
        400,
        liquidTop,
        60,
        11,
        _solid(const Color(0x88B8F6FF)),
      );
    }

    canvas.restore();

    // 罐口描边与前景高光，保持金属容器的立体感。
    _ellipse(
      canvas,
      400,
      488,
      60,
      16,
      _linePaint(const Color(0xE6C8D7E4), 2.4),
    );
    _rounded(
      canvas,
      const Rect.fromLTWH(358, 498, 14, 138),
      7,
      _solid(const Color(0x42FFFFFF)),
    );
    _rounded(
      canvas,
      const Rect.fromLTWH(430, 498, 8, 138),
      4,
      _solid(const Color(0x330A1219)),
    );
    _rect(
      canvas,
      const Rect.fromLTWH(340, 560, 120, 16),
      _solid(const Color(0x10FFFFFF)),
    );

    // 灌装流由设备状态控制，不按 SVG 的固定周期擅自切换状态。
    if (isFeeding && !isEmptying && level < 1) {
      canvas.save();
      canvas.clipRect(body);

      for (var i = 0; i < 8; i++) {
        final phase = _fraction(
          clock.value * (isFastFeed ? 4.4 : 2.3) + i / 8,
        );
        final fade = math.sin(phase * math.pi).clamp(0.0, 1.0);

        canvas.drawCircle(
          Offset(
            386 + (i * 9 % 27).toDouble(),
            492 + phase * math.max(8.0, liquidTop - 492),
          ),
          isFastFeed ? 3.6 : 2.7,
          _solid(_pale.withOpacity(fade)),
        );
      }
      canvas.restore();
    }
  }

  void _drawScaleAndBase(Canvas canvas) {
    // 放罐秤台。
    canvas.drawPath(
      _polygon(const [
        Offset(300, 645),
        Offset(500, 645),
        Offset(520, 632),
        Offset(320, 632),
      ]),
      _horizontal(
        const Rect.fromLTWH(300, 632, 220, 13),
        const [
          Color(0xFF476A7A),
          Color(0xFF91B0BE),
          Color(0xFF304D5D),
        ],
      ),
    );
    _rect(
      canvas,
      const Rect.fromLTWH(300, 645, 200, 27),
      _vertical(
        const Rect.fromLTWH(300, 645, 200, 27),
        const [Color(0xFF2C4756), Color(0xFF142733)],
      ),
    );
    canvas.drawPath(
      _polygon(const [
        Offset(500, 645),
        Offset(520, 632),
        Offset(520, 659),
        Offset(500, 672),
      ]),
      _solid(const Color(0xFF17232C)),
    );
    _line(canvas, 300, 645, 500, 645, _cyan.withOpacity(.65), 1.6);

    // 称重传感器及基座。
    const sensor = Rect.fromLTWH(352, 674, 96, 26);
    final pulse = .55 + .45 * (1 + math.sin(clock.value * math.pi * 4)) / 2;

    _rounded(
      canvas,
      sensor,
      4,
      _vertical(
        sensor,
        [
          const Color(0xFF8DF2FF).withOpacity(pulse),
          const Color(0xFF0F8FB0).withOpacity(pulse),
        ],
      ),
    );
    _rounded(
      canvas,
      sensor,
      4,
      _linePaint(const Color(0xFF9DF6FF)),
    );

    const scaleBase = Rect.fromLTWH(344, 700, 112, 62);
    _rect(
      canvas,
      scaleBase,
      _vertical(
        scaleBase,
        const [
          Color(0xFF203744),
          Color(0xFF8EADBA),
          Color(0xFF416575),
          Color(0xFF1B303C),
        ],
      ),
    );

    // 整机底座。
    canvas.drawPath(
      _polygon(const [
        Offset(110, 762),
        Offset(690, 762),
        Offset(730, 734),
        Offset(150, 734),
      ]),
      _horizontal(
        const Rect.fromLTWH(110, 734, 620, 28),
        const [
          Color(0xFF476A7A),
          Color(0xFF304D5D),
          Color(0xFF203846),
        ],
      ),
    );
    _rect(
      canvas,
      const Rect.fromLTWH(110, 762, 580, 53),
      _vertical(
        const Rect.fromLTWH(110, 762, 580, 53),
        const [Color(0xFF2C4756), Color(0xFF142733)],
      ),
    );
    canvas.drawPath(
      _polygon(const [
        Offset(690, 762),
        Offset(730, 734),
        Offset(730, 787),
        Offset(690, 815),
      ]),
      _solid(const Color(0xFF17232C)),
    );
    _line(canvas, 110, 762, 690, 762, _cyan.withOpacity(.55), 2);

    // HMI 进度条：使用实际灌装进度，不写死 SVG 中的「1000g」。
    const screen = Rect.fromLTWH(452, 768, 176, 40);
    _rounded(
      canvas,
      screen,
      6,
      _vertical(
        screen,
        const [Color(0xFF0D3341), Color(0xFF05161D)],
      ),
    );
    _rounded(
      canvas,
      screen,
      6,
      _linePaint(const Color(0xFF2A8FB8)),
    );
    _rounded(
      canvas,
      const Rect.fromLTWH(460, 776, 160, 10),
      3,
      _solid(const Color(0xFF071A22)),
    );

    final level = fillPercentage.isFinite
        ? fillPercentage.clamp(0.0, 1.0).toDouble()
        : 0.0;
    if (level > 0) {
      _rounded(
        canvas,
        Rect.fromLTWH(460, 776, 160 * level, 10),
        3,
        _horizontal(
          const Rect.fromLTWH(460, 776, 160, 10),
          const [Color(0xFF0F8FB0), Color(0xFF8DF2FF)],
        ),
      );
    }

    final label = TextPainter(
      text: TextSpan(
        text: '${(level * 100).toStringAsFixed(1)}%',
        style: const TextStyle(
          color: Color(0xFF8DF2FF),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    label.paint(
      canvas,
      Offset(540 - label.width / 2, 788),
    );

    canvas.drawCircle(
      const Offset(640, 798),
      6,
      _solid(
        (isFeeding || isEmptying)
            ? const Color(0xFF59D3A3)
            : const Color(0xFF5E8791),
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _FillingProcessPainter oldDelegate) {
    return oldDelegate.clock != clock ||
        oldDelegate.isFeeding != isFeeding ||
        oldDelegate.isFastFeed != isFastFeed ||
        oldDelegate.isEmptying != isEmptying ||
        oldDelegate.fillPercentage != fillPercentage;
  }
}
