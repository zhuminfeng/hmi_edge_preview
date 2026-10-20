import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 使用 Flutter Canvas 绘制失重秤，不加载 SVG 或 WebView。
class LiwProcessPainter extends CustomPainter {
  LiwProcessPainter({
    required this.clock,
    required this.isRefilling,
    required this.isFeeding,
    required this.isEmptying,
    required this.refillingLabel,
    required this.feedingLabel,
    required this.emptyingLabel,
  }) : super(repaint: clock);

  final AnimationController clock;
  final bool isRefilling;
  final bool isFeeding;
  final bool isEmptying;
  final String refillingLabel;
  final String feedingLabel;
  final String emptyingLabel;

  static const double _width = 800;
  static const double _height = 950;

  static const _cyan = Color(0xFF5BCBDF);
  static const _pale = Color(0xFFB8F0F4);
  static const _green = Color(0xFF59D3A3);

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

  static const _metalStops = <double>[0, .09, .24, .36, .52, .73, .91, 1];

  Paint _fill(Color color) => Paint()..color = color;

  Paint _linear(
    Offset start,
    Offset end,
    List<Color> colors, {
    List<double>? stops,
  }) {
    // 多色渐变需要为每个颜色提供 stop；未传入时自动均匀分布。
    final resolvedStops =
        stops ??
        (colors.length > 2
            ? List<double>.generate(
              colors.length,
              (index) => index / (colors.length - 1),
            )
            : null);

    return Paint()
      ..shader = ui.Gradient.linear(start, end, colors, resolvedStops);
  }

  Paint _metalPaint() => _linear(
    const Offset(150, 0),
    const Offset(440, 0),
    _metal,
    stops: _metalStops,
  );

  void _rect(
    Canvas canvas,
    double x,
    double y,
    double width,
    double height,
    Paint paint,
  ) {
    canvas.drawRect(Rect.fromLTWH(x, y, width, height), paint);
  }

  void _rounded(Canvas canvas, Rect rect, double radius, Paint paint) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      paint,
    );
  }

  void _ellipse(
    Canvas canvas,
    double x,
    double y,
    double rx,
    double ry,
    Paint paint,
  ) {
    canvas.drawOval(
      Rect.fromCenter(center: Offset(x, y), width: rx * 2, height: ry * 2),
      paint,
    );
  }

  void _stroke(Canvas canvas, Path path, Color color, {double width = 1}) {
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );
  }

  Path _polygon(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);

    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }

    return path..close();
  }

  double _smooth(double value) {
    final x = value.clamp(0.0, 1.0);
    return x * x * (3 - 2 * x);
  }

  double _cycle(double value) => value - value.floorToDouble();

  double _level() {
    final t = clock.value;

    if (isRefilling) {
      return .24 + .76 * _smooth(t);
    }

    if (isEmptying || isFeeding) {
      return 1 - .76 * _smooth(t);
    }

    return .7;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    // 覆盖设备主体及下方状态徽标；不再按原始 800×950 画布适配。
    // 固定边界可以避免运行状态切换时整台设备突然改变大小。
    const deviceBounds = Rect.fromLTRB(105, 14, 680, 872);
    const horizontalPadding = 18.0;
    const verticalPadding = 12.0;

    final availableWidth = size.width - horizontalPadding * 2;
    final availableHeight = size.height - verticalPadding * 2;
    if (availableWidth <= 0 || availableHeight <= 0) return;

    final fitScale = math.min(
      availableWidth / deviceBounds.width,
      availableHeight / deviceBounds.height,
    );

    // 留一点边距，但不再叠加此前的 .82 缩小系数。
    final scale = fitScale * .96;

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(
      (size.width - deviceBounds.width * scale) / 2 - deviceBounds.left * scale,
      (size.height - deviceBounds.height * scale) / 2 -
          deviceBounds.top * scale,
    );
    canvas.scale(scale);

    // 保持透明背景，由左侧面板提供底色。
    _drawBase(canvas);
    _drawColumns(canvas);
    _drawPipe(canvas);
    _drawOutlet(canvas);
    _drawMotor(canvas);
    _drawHopper(canvas);
    _drawFeedPipe(canvas);
    _drawBadge(canvas);

    canvas.restore();
  }

  // void _drawBackground(Canvas canvas) {
  //   final background = Rect.fromLTWH(0, 0, _width, _height);

  //   canvas.drawRect(
  //     background,
  //     Paint()
  //       ..shader = ui.Gradient.radial(
  //         const Offset(400, 360),
  //         650,
  //         const [Color(0xFF1D3948), Color(0xFF142633), Color(0xFF0C1822)],
  //         const [0, .5, 1],
  //       ),
  //   );

  //   _ellipse(
  //     canvas,
  //     400,
  //     790,
  //     300,
  //     75,
  //     Paint()
  //       ..color = const Color(0x552A8FB8)
  //       ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 35),
  //   );
  // }

  void _drawBase(Canvas canvas) {
    canvas.drawPath(
      _polygon(const [
        Offset(155, 765),
        Offset(625, 765),
        Offset(675, 735),
        Offset(205, 735),
      ]),
      _linear(const Offset(155, 735), const Offset(675, 765), const [
        Color(0xFF476A7A),
        Color(0xFF304D5D),
        Color(0xFF203846),
      ]),
    );

    _rect(
      canvas,
      155,
      765,
      470,
      47,
      _linear(const Offset(155, 765), const Offset(155, 812), const [
        Color(0xFF2C4756),
        Color(0xFF142733),
      ]),
    );

    canvas.drawPath(
      _polygon(const [
        Offset(625, 765),
        Offset(675, 735),
        Offset(675, 782),
        Offset(625, 812),
      ]),
      _fill(const Color(0xFF17232C)),
    );

    _rounded(
      canvas,
      const Rect.fromLTWH(205, 780, 370, 7),
      3.5,
      _fill(const Color(0x6612ACCD)),
    );

    final brightness =
        .35 + .65 * (1 + math.sin(clock.value * math.pi * 9)) / 2;

    canvas.drawCircle(
      const Offset(600, 795),
      6,
      _fill(_green.withOpacity(brightness)),
    );
  }

  void _drawColumns(Canvas canvas) {
    for (final x in [225.0, 460.0]) {
      _rect(
        canvas,
        x,
        668,
        60,
        94,
        _linear(Offset(x, 668), Offset(x + 60, 668), const [
          Color(0xFF294353),
          Color(0xFF89AAB7),
          Color(0xFF537686),
          Color(0xFF203542),
        ]),
      );

      canvas.drawPath(
        _polygon([
          Offset(x, 668),
          Offset(x + 60, 668),
          Offset(x + 72, 658),
          Offset(x + 12, 658),
        ]),
        _fill(const Color(0xFF617690)),
      );

      final phase = x == 225 ? 0.0 : math.pi;
      final alpha =
          .45 + .55 * (1 + math.sin(clock.value * math.pi * 9 + phase)) / 2;

      final sensor = Rect.fromLTWH(x, 698, 60, 20);

      canvas.drawRect(
        sensor,
        _linear(Offset(x, 698), Offset(x, 718), [
          const Color(0xFF7EF4FF).withOpacity(alpha),
          const Color(0xFF0A6277).withOpacity(alpha),
        ]),
      );

      _stroke(canvas, Path()..addRect(sensor), const Color(0xFF9DF6FF));
    }
  }

  void _drawPipe(Canvas canvas) {
    _rect(
      canvas,
      135,
      560,
      420,
      110,
      _linear(
        const Offset(0, 560),
        const Offset(0, 670),
        const [
          Color(0xFF253E4D),
          Color(0xFF5D8292),
          Color(0xFFA5C3CE),
          Color(0xFFD5E8EC),
          Color(0xFF93B3C0),
          Color(0xFF496D7D),
          Color(0xFF203542),
        ],
        stops: const [0, .11, .26, .38, .55, .78, 1],
      ),
    );

    _rect(canvas, 140, 645, 410, 18, _fill(const Color(0x590C141B)));

    canvas.save();
    canvas.clipRect(const Rect.fromLTWH(150, 572, 405, 86));

    final shift = _cycle(clock.value * 9) * 40;
    final screw = Path()..moveTo(120 + shift, 615);

    for (var index = 0; index < 14; index++) {
      final x = 120 + shift + index * 40;

      screw.quadraticBezierTo(x + 20, index.isEven ? 583 : 647, x + 40, 615);
    }

    _stroke(canvas, screw, const Color(0xFFDBE8F3), width: 2.6);

    canvas.restore();

    _ellipse(canvas, 135, 615, 26, 55, _fill(const Color(0xFF38495A)));

    _ellipse(canvas, 135, 615, 14, 30, _fill(const Color(0xFF212D38)));

    _rounded(
      canvas,
      const Rect.fromLTWH(240, 546, 110, 18),
      4,
      _fill(const Color(0xFF4A5C6E)),
    );
  }

  void _drawOutlet(Canvas canvas) {
    final outlet = _polygon(const [
      Offset(152, 668),
      Offset(218, 668),
      Offset(200, 752),
      Offset(170, 752),
    ]);

    canvas.drawPath(outlet, _metalPaint());
    canvas.drawPath(outlet, _fill(const Color(0x400A1219)));

    _ellipse(canvas, 185, 752, 15, 5, _fill(const Color(0xFF0A1017)));
  }

  void _drawMotor(Canvas canvas) {
    _rounded(canvas, const Rect.fromLTWH(540, 552, 24, 126), 5, _metalPaint());

    _rect(
      canvas,
      562,
      575,
      90,
      80,
      _linear(
        const Offset(0, 575),
        const Offset(0, 655),
        const [
          Color(0xFF203744),
          Color(0xFF4E7485),
          Color(0xFF9AB9C6),
          Color(0xFFC6DDE3),
          Color(0xFF8EADBA),
          Color(0xFF416575),
          Color(0xFF1B303C),
        ],
        stops: const [0, .14, .30, .42, .60, .82, 1],
      ),
    );

    for (final x in [585.0, 600.0, 615.0, 630.0]) {
      canvas.drawLine(
        Offset(x, 578),
        Offset(x, 652),
        Paint()
          ..color = const Color(0x591D2A34)
          ..strokeWidth = 3,
      );
    }

    _ellipse(canvas, 652, 615, 20, 40, _fill(const Color(0xFF3A4A5A)));

    _ellipse(canvas, 652, 615, 9, 18, _fill(const Color(0xFF22303C)));

    if (isRefilling || isFeeding || isEmptying) {
      canvas.save();
      canvas.translate(652, 615);
      canvas.rotate(clock.value * 9 * math.pi * 2 / 1.1);

      final rotorPaint =
          Paint()
            ..color = const Color(0xFF7EF4FF)
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round;

      canvas.drawLine(const Offset(0, -31), const Offset(0, -16), rotorPaint);

      canvas.drawLine(const Offset(0, 16), const Offset(0, 31), rotorPaint);

      canvas.restore();
    }

    _rounded(
      canvas,
      const Rect.fromLTWH(596, 556, 34, 20),
      4,
      _fill(const Color(0xFF42576A)),
    );
  }

  void _drawHopper(Canvas canvas) {
    final cone =
        Path()
          ..moveTo(150, 400)
          ..lineTo(440, 400)
          ..lineTo(345, 562)
          ..quadraticBezierTo(295, 582, 245, 562)
          ..close();

    canvas.drawPath(cone, _metalPaint());

    _rect(canvas, 150, 180, 290, 220, _metalPaint());

    _rect(canvas, 150, 298, 290, 11, _fill(const Color(0x8C28363F)));

    _rect(
      canvas,
      238,
      186,
      24,
      204,
      _linear(const Offset(238, 186), const Offset(262, 186), const [
        Color(0x00FFFFFF),
        Color(0x80FFFFFF),
        Color(0x00FFFFFF),
      ]),
    );

    // 料层高度为动画示意，不代表实时测得的料位。
    final level = _level();
    final top = 400 - 115 * level;

    canvas.save();
    canvas.clipRect(const Rect.fromLTWH(150, 180, 290, 220));

    _rect(
      canvas,
      150,
      top,
      290,
      400 - top,
      _linear(Offset(150, top), const Offset(150, 400), const [
        Color(0x88BFEEF8),
        Color(0x994FB8D6),
      ]),
    );

    canvas.restore();

    _rounded(
      canvas,
      const Rect.fromLTWH(182, 220, 12, 150),
      3,
      _fill(const Color(0xFF08131B)),
    );

    final barHeight = 150 * level;

    _rounded(
      canvas,
      Rect.fromLTWH(182, 370 - barHeight, 12, barHeight),
      3,
      _linear(const Offset(182, 220), const Offset(182, 370), const [
        Color(0xFF8DF2FF),
        Color(0xFF0F8FB0),
      ]),
    );

    for (final y in [244.0, 284.0, 324.0, 364.0]) {
      canvas.drawLine(
        Offset(176, y),
        Offset(200, y),
        _fill(const Color(0xB35F7A8D)),
      );
    }

    _ellipse(
      canvas,
      295,
      145,
      152,
      50,
      _linear(const Offset(143, 95), const Offset(447, 195), const [
        Color(0xFFCEE2E8),
        Color(0xFF91B0BE),
        Color(0xFF4F7384),
      ]),
    );

    _rect(canvas, 143, 145, 304, 38, _metalPaint());

    _rect(canvas, 143, 172, 304, 11, _fill(const Color(0x590A1219)));
  }

  void _drawFeedPipe(Canvas canvas) {
    if (isRefilling) {
      _rect(
        canvas,
        262,
        40,
        74,
        80,
        Paint()
          ..color = _cyan.withOpacity(.45)
          ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 6),
      );
    }

    _rect(
      canvas,
      268,
      30,
      62,
      86,
      _linear(const Offset(268, 30), const Offset(330, 30), const [
        Color(0xFF294453),
        Color(0xFF83A6B4),
        Color(0xFFCCE2E8),
        Color(0xFF7799A8),
        Color(0xFF294453),
      ]),
    );

    _rect(canvas, 280, 34, 8, 78, _fill(const Color(0x73FFFFFF)));

    _rounded(
      canvas,
      const Rect.fromLTWH(258, 18, 82, 20),
      4,
      _fill(const Color(0xFF4A5C6E)),
    );

    if (isRefilling) {
      canvas.save();
      canvas.clipRect(const Rect.fromLTWH(268, 46, 62, 72));

      for (var i = 0; i < 8; i++) {
        final p = _cycle(clock.value * 9 + i * .12);

        canvas.drawCircle(
          Offset(276 + (i * 13 % 38).toDouble(), 42 + 70 * p),
          4.2,
          _fill(_pale),
        );
      }

      canvas.restore();

      for (var i = 0; i < 6; i++) {
        final p = _cycle(clock.value * 10 + i / 6);

        canvas.drawCircle(
          Offset(282 + (i * 9 % 26).toDouble(), 134 + 80 * p),
          3.2,
          _fill(_pale.withOpacity(1 - p)),
        );
      }
    }

    _rounded(
      canvas,
      Rect.fromLTWH(isRefilling ? 293 : 262, 112, isRefilling ? 12 : 74, 12),
      3,
      _linear(const Offset(262, 112), const Offset(262, 124), const [
        Color(0xFF5FE4FF),
        Color(0xFF0E7F9E),
      ]),
    );

    _rounded(
      canvas,
      const Rect.fromLTWH(256, 122, 86, 8),
      2,
      _fill(const Color(0xFF4A5C6E)),
    );

    canvas.drawCircle(
      const Offset(352, 72),
      6,
      _fill(_cyan.withOpacity(isRefilling ? 1 : .2)),
    );

    // 进料口置于加料管前方，保持原有绘制层次。
    _rect(canvas, 240, 100, 110, 48, _metalPaint());

    _ellipse(canvas, 295, 100, 55, 18, _fill(const Color(0xFFC3D3E2)));

    _ellipse(canvas, 295, 100, 41, 12, _fill(const Color(0xFF22303C)));

    _ellipse(canvas, 295, 99, 34, 8, _fill(const Color(0xFF0A1219)));
  }

  void _drawBadge(Canvas canvas) {
    final String label;
    final Color color;

    if (isRefilling) {
      label = refillingLabel;
      color = _cyan;
    } else if (isEmptying) {
      label = emptyingLabel;
      color = const Color(0xFFE5A24A);
    } else if (isFeeding) {
      label = feedingLabel;
      color = _green;
    } else {
      return;
    }

    _rounded(
      canvas,
      const Rect.fromLTWH(282, 826, 236, 40),
      10,
      _fill(const Color(0xDD0D1A24)),
    );

    canvas.drawCircle(const Offset(316, 846), 5, _fill(color));

    final text = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Color(0xFFC9F9FF),
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: 175);

    text.paint(canvas, const Offset(330, 836));
  }

  @override
  bool shouldRepaint(covariant LiwProcessPainter oldDelegate) {
    return oldDelegate.clock != clock ||
        oldDelegate.isRefilling != isRefilling ||
        oldDelegate.isFeeding != isFeeding ||
        oldDelegate.isEmptying != isEmptying ||
        oldDelegate.refillingLabel != refillingLabel ||
        oldDelegate.feedingLabel != feedingLabel ||
        oldDelegate.emptyingLabel != emptyingLabel;
  }
}
