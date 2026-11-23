import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../app/app.dart';
import '../engine/assets.dart';
import '../engine/renderer.dart';
import '../features/save/save_data.dart';
import '../game/game_controller.dart';
import 'map_painter.dart';
import 'widgets.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.repo, required this.settings, this.data});
  final SaveRepository repo;
  final GameSettings settings;
  final SaveData? data;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  GameController? _g;
  WorldRenderer? _renderer;
  Ticker? _ticker;
  Duration _last = Duration.zero;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  Future<void> _load() async {
    try {
      final lib = await ModelLibrary.load();
      if (!mounted) return;
      final g = GameController(repo: widget.repo, settings: widget.settings, data: widget.data);
      setState(() {
        _g = g;
        _renderer = WorldRenderer(lib);
      });
      _ticker = createTicker((d) {
        final dt = (d - _last).inMicroseconds / 1e6;
        _last = d;
        g.tick(dt);
      })
        ..start();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) _g?.save();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.dispose();
    _g?.save();
    _g?.dispose();
    super.dispose();
  }

  Future<void> _pause() async {
    final g = _g;
    if (g == null || g.paused) return;
    g.paused = true;
    final quit = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (c) => Dialog(
        backgroundColor: const Color(0xFF101010),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3), side: const BorderSide(color: Color(0x66E9E2CF))),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Paused', style: TextStyle(fontSize: 28, color: kBone)),
            const SizedBox(height: 6),
            const Text('Progress is saved automatically.', style: TextStyle(fontSize: 15, color: Color(0xB3E9E2CF))),
            const SizedBox(height: 12),
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Resume', style: TextStyle(fontSize: 20, color: kBone))),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save and quit to menu', style: TextStyle(fontSize: 18, color: kBloodLt))),
          ]),
        ),
      ),
    );
    g.paused = false;
    if (quit == true) {
      await g.save();
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _openMap() async {
    final g = _g;
    if (g == null || g.paused) return;
    g.paused = true;
    await showDialog<void>(
      context: context,
      builder: (c) => Dialog.fullscreen(
        backgroundColor: const Color(0xFF0E0E10),
        child: Stack(children: [
          Positioned.fill(child: Padding(padding: const EdgeInsets.all(10), child: CustomPaint(painter: MapPainter(g, full: true)))),
          Positioned(right: 6, top: 6, child: IconButton(icon: const Icon(Icons.close, color: kBone), onPressed: () => Navigator.pop(c))),
        ]),
      ),
    );
    g.paused = false;
  }

  @override
  Widget build(BuildContext context) {
    final g = _g;
    final r = _renderer;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          if (g == null) {
            Navigator.of(context).pop();
          } else {
            _pause();
          }
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: _error != null
            ? Center(child: Text('Could not load models:\n$_error', textAlign: TextAlign.center, style: const TextStyle(color: kBone)))
            : (g == null || r == null)
                ? const _Loading()
                : LayoutBuilder(
                    builder: (context, c) => ListenableBuilder(listenable: g, builder: (context, _) => _layout(g, r, c.biggest)),
                  ),
      ),
    );
  }

  Widget _layout(GameController g, WorldRenderer r, Size size) {
    final d = g.dialogue;
    final comp = g.completion;
    final driving = g.driving != null;
    final infoW = max(180.0, size.width - 160 - 270);
    return Stack(children: [
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (e) => g.rotateCamera(e.delta.dx, e.delta.dy),
          child: CustomPaint(painter: WorldPainter(r, g), size: Size.infinite),
        ),
      ),
      SafeArea(
        minimum: const EdgeInsets.all(8),
        child: Stack(children: [
          // radar, upper-left
          Positioned(
            left: 0,
            top: 0,
            child: GestureDetector(
              onTap: _openMap,
              child: Container(
                width: 122,
                height: 122,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF050505), width: 3.5),
                  boxShadow: const [BoxShadow(color: Color(0x88000000), blurRadius: 6)],
                ),
                child: ClipOval(child: CustomPaint(painter: MapPainter(g))),
              ),
            ),
          ),
          // status, upper-right (small, out of the way)
          Positioned(right: 0, top: 0, child: _status(g, driving)),
          // controls
          Positioned(
            left: 6,
            bottom: 4,
            child: Joystick(onChanged: (x, y) {
              g.joyX = x;
              g.joyY = y;
            }),
          ),
          Positioned(right: 4, bottom: 4, child: _actions(g, driving)),
          // objective, prompts, subtitles and dialogue live at the bottom center
          Positioned(
            left: 156,
            right: 266,
            bottom: 2,
            child: Center(child: SizedBox(width: infoW, child: d != null ? _dialogue(g, d) : _bottomInfo(g))),
          ),
          if (g.banner != null)
            Align(
              alignment: const Alignment(0, 0.35),
              child: OutlinedText(g.banner!.toUpperCase(), size: 70, color: g.banner == 'WASTED' ? kBloodLt : const Color(0xFF9DB2D6)),
            ),
        ]),
      ),
      if (comp != null) Align(alignment: const Alignment(0, 0.5), child: _completion(g, comp)),
    ]);
  }

  Widget _status(GameController g, bool driving) {
    return Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        _iconBtn(Icons.map_outlined, _openMap),
        const SizedBox(width: 6),
        _iconBtn(Icons.pause, _pause),
      ]),
      const SizedBox(height: 4),
      OutlinedText(g.clockText, size: 15, align: TextAlign.right),
      OutlinedText('\$${g.wallet.money}', size: 30, color: kMoney, align: TextAlign.right),
      Container(
        width: 104,
        height: 8,
        margin: const EdgeInsets.only(top: 2, bottom: 3),
        decoration: BoxDecoration(color: const Color(0x99000000), border: Border.all(color: const Color(0xFF050505), width: 1.5)),
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: (g.hp / 100).clamp(0.0, 1.0).toDouble(),
          child: Container(color: const Color(0xFFA32626)),
        ),
      ),
      Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < 3; i++)
          Icon(Icons.star, size: 20, color: i < g.wanted ? const Color(0xFFF1E9C8) : const Color(0x44E9E2CF)),
      ]),
      if (driving) OutlinedText('${g.speedKmh.round()} km/h', size: 18, align: TextAlign.right),
    ]);
  }

  Widget _iconBtn(IconData i, VoidCallback f) => GestureDetector(
        onTap: f,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xB3101010), border: Border.all(color: const Color(0x99E9E2CF))),
          child: Icon(i, size: 18, color: kBone),
        ),
      );

  Widget _actions(GameController g, bool driving) {
    return SizedBox(
      width: 262,
      height: 190,
      child: Stack(children: [
        Positioned(right: 6, bottom: 4, child: HudButton(icon: Icons.touch_app, label: 'Act', size: 82, onTap: g.interact)),
        if (!driving) ...[
          Positioned(right: 100, bottom: 14, child: HudButton(icon: Icons.sports_mma, label: 'Punch', size: 68, onTap: g.punch)),
          Positioned(right: 14, bottom: 94, child: HudButton(icon: Icons.keyboard_double_arrow_up, label: 'Jump', size: 62, onTap: g.jump)),
          Positioned(right: 96, bottom: 92, child: HudButton(icon: Icons.directions_run, label: 'Run', size: 56, onHold: (v) => g.sprint = v)),
          Positioned(right: 170, bottom: 8, child: HudButton(icon: Icons.campaign_outlined, label: 'Taunt', size: 54, enabled: g.canTaunt, onTap: g.taunt)),
        ] else
          Positioned(right: 100, bottom: 14, child: HudButton(icon: Icons.person_add_alt_1, label: 'Ride', size: 68, enabled: g.canRide, onTap: g.pickUpPassenger)),
      ]),
    );
  }

  Widget _bottomInfo(GameController g) {
    final dist = g.waypointDistance;
    final timer = g.timerText;
    final extra = [if (dist != null) '${dist.round()} m', if (timer != null) 'time $timer'].join('  ');
    return Column(mainAxisSize: MainAxisSize.min, children: [
      for (final s in g.subtitles) Padding(padding: const EdgeInsets.only(top: 2), child: OutlinedText(s.text, who: s.who.isEmpty ? null : s.who, size: 16)),
      if (g.prompt != null && g.subtitles.isEmpty) OutlinedText(g.prompt!, size: 16, color: const Color(0xFFF2D9A0)),
      const SizedBox(height: 2),
      OutlinedText('${g.missionTitle}${extra.isEmpty ? '' : '   $extra'}', size: 13, color: kBloodLt, maxLines: 1),
      OutlinedText(g.objectiveText, size: 15, maxLines: 2),
    ]);
  }

  Widget _dialogue(GameController g, ActiveDialogue d) {
    final offer = d.last && d.offerId != null;
    final style = TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2), minimumSize: const Size(10, 28));
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 10, 4),
      decoration: BoxDecoration(
        color: const Color(0xDD0C0C0C),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: const Color(0x66E9E2CF)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(d.line.speaker, style: const TextStyle(color: kBloodLt, fontSize: 17)),
        Text(d.line.text, maxLines: 4, style: const TextStyle(fontSize: 17, height: 1.15, color: kBone)),
        Align(
          alignment: Alignment.centerRight,
          child: offer
              ? Row(mainAxisSize: MainAxisSize.min, children: [
                  TextButton(style: style, onPressed: g.declineOffer, child: const Text('Later', style: TextStyle(color: kBone, fontSize: 17))),
                  TextButton(style: style, onPressed: g.acceptOffer, child: const Text('Accept mission', style: TextStyle(color: kBloodLt, fontSize: 18))),
                ])
              : TextButton(style: style, onPressed: g.nextDialogue, child: Text(d.last ? 'Close' : 'Next', style: const TextStyle(color: kBloodLt, fontSize: 18))),
        ),
      ]),
    );
  }

  Widget _completion(GameController g, MissionResult r) {
    return Container(
      width: 330,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      decoration: BoxDecoration(
        color: const Color(0xE6090909),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: const Color(0x99E9E2CF)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Mission passed', style: TextStyle(color: kBloodLt, fontSize: 32)),
        Text(r.title, style: const TextStyle(fontSize: 19, color: kBone)),
        const SizedBox(height: 2),
        Text('Reward  \$${r.reward}', style: const TextStyle(color: kMoney, fontSize: 24)),
        TextButton(onPressed: g.dismissCompletion, child: const Text('Continue', style: TextStyle(color: kBone, fontSize: 19))),
      ]),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(height: 120, child: Image.asset('assets/logo.png')),
        const SizedBox(height: 10),
        const Text('Loading New Merrci...', style: TextStyle(fontSize: 20, color: kBone)),
        const SizedBox(height: 10),
        const SizedBox(width: 140, child: LinearProgressIndicator(color: kBlood, backgroundColor: Color(0x33E9E2CF), minHeight: 2)),
      ]),
    );
  }
}
