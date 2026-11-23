import 'package:flutter/material.dart';

import '../app/app.dart';

/// Text with a dark outline so it stays readable over the 3D view without a panel.
class OutlinedText extends StatelessWidget {
  const OutlinedText(this.text,
      {super.key, this.size = 16, this.color = kBone, this.align = TextAlign.center, this.maxLines = 3, this.who});
  final String text;
  final String? who;
  final double size;
  final Color color;
  final TextAlign align;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xFF000000);
    TextSpan span(TextStyle base, {required bool fill}) => TextSpan(
          style: base,
          children: [
            if (who != null && who!.isNotEmpty)
              TextSpan(text: '$who  ', style: fill ? TextStyle(color: kBloodLt, fontSize: size) : null),
            TextSpan(text: text),
          ],
        );
    final s0 = TextStyle(fontFamily: kScript, fontSize: size, height: 1.15, foreground: stroke);
    final s1 = TextStyle(fontFamily: kScript, fontSize: size, height: 1.15, color: color);
    return Stack(children: [
      Text.rich(span(s0, fill: false), textAlign: align, maxLines: maxLines, overflow: TextOverflow.ellipsis),
      Text.rich(span(s1, fill: true), textAlign: align, maxLines: maxLines, overflow: TextOverflow.ellipsis),
    ]);
  }
}

/// On-screen joystick. Reports x (right +) and y (up +) in -1..1.
class Joystick extends StatefulWidget {
  const Joystick({super.key, required this.onChanged});
  final void Function(double x, double y) onChanged;

  @override
  State<Joystick> createState() => _JoystickState();
}

class _JoystickState extends State<Joystick> {
  Offset _k = Offset.zero;
  static const double _r = 50;

  void _upd(Offset p) {
    var d = p - const Offset(70, 70);
    if (d.distance > _r) d = d / d.distance * _r;
    setState(() => _k = d);
    widget.onChanged(d.dx / _r, -d.dy / _r);
  }

  void _end() {
    setState(() => _k = Offset.zero);
    widget.onChanged(0, 0);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) => _upd(e.localPosition),
      onPointerMove: (e) => _upd(e.localPosition),
      onPointerUp: (_) => _end(),
      onPointerCancel: (_) => _end(),
      child: SizedBox(
        width: 140,
        height: 140,
        child: Stack(children: [
          Center(
            child: Container(
              width: 116,
              height: 116,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0x44000000),
                border: Border.all(color: const Color(0x99E9E2CF), width: 1.5),
              ),
            ),
          ),
          Positioned(
            left: 70 + _k.dx - 24,
            top: 70 + _k.dy - 24,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xCC1A1A1A),
                border: Border.all(color: kBone, width: 1.5),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Round HUD button: dark glass, bone-colored line icon, small script label.
class HudButton extends StatefulWidget {
  const HudButton(
      {super.key, required this.icon, required this.label, this.size = 64, this.onTap, this.onHold, this.enabled = true});
  final IconData icon;
  final String label;
  final double size;
  final VoidCallback? onTap;
  final void Function(bool down)? onHold;
  final bool enabled;

  @override
  State<HudButton> createState() => _HudButtonState();
}

class _HudButtonState extends State<HudButton> {
  bool _down = false;

  void _set(bool v) {
    setState(() => _down = v);
    widget.onHold?.call(v);
  }

  @override
  Widget build(BuildContext context) {
    final fg = widget.enabled ? kBone : const Color(0x66E9E2CF);
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) {
        _set(true);
        widget.onTap?.call();
      },
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: Container(
        width: widget.size,
        height: widget.size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _down ? const Color(0xE68F1A1A) : const Color(0xB3101010),
          border: Border.all(color: fg, width: 1.4),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(widget.icon, color: fg, size: widget.size * 0.36),
          Text(widget.label, style: TextStyle(color: fg, fontSize: widget.size * 0.19, height: 1.0)),
        ]),
      ),
    );
  }
}
