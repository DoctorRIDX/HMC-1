import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app.dart';
import '../features/save/save_data.dart';
import 'game_screen.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key, required this.repo});
  final SaveRepository repo;

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> with SingleTickerProviderStateMixin {
  static const _items = ['New Game', 'Continue', 'Settings', 'Credits', 'Exit'];
  late final AnimationController _zoom;
  final PageController _pages = PageController(viewportFraction: 0.27);
  bool _hasSave = false;
  GameSettings _settings = GameSettings();
  int _sel = 0;

  @override
  void initState() {
    super.initState();
    _zoom = AnimationController(vsync: this, duration: const Duration(seconds: 16))..repeat(reverse: true);
    _refresh();
  }

  @override
  void dispose() {
    _zoom.dispose();
    _pages.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final h = await widget.repo.hasSave();
    final s = await widget.repo.loadSettings();
    if (!mounted) return;
    setState(() {
      _hasSave = h;
      _settings = s;
    });
  }

  Future<void> _play(SaveData? data) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => GameScreen(repo: widget.repo, settings: _settings, data: data)));
    await _refresh();
  }

  Future<void> _newGame() async {
    if (_hasSave) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => _ConfirmDialog(
            title: 'Start a new game?', body: 'Your current save will be replaced.', yes: 'New game', no: 'Cancel'),
      );
      if (ok != true) return;
    }
    await widget.repo.clear();
    if (!mounted) return;
    await _play(null);
  }

  Future<void> _continue() async {
    final d = await widget.repo.load();
    if (!mounted) return;
    if (d == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No valid save found.')));
      return;
    }
    await _play(d);
  }

  void _activate(int i) {
    switch (i) {
      case 0:
        _newGame();
        break;
      case 1:
        if (_hasSave) {
          _continue();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No save yet. Start a new game.')));
        }
        break;
      case 2:
        Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => SettingsScreen(repo: widget.repo, settings: _settings)));
        break;
      case 3:
        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CreditsScreen()));
        break;
      default:
        SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _zoom,
            builder: (context, child) => Transform.scale(scale: 1.0 + 0.05 * _zoom.value, child: child),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 70),
              child: Image.asset('assets/logo.png', fit: BoxFit.contain),
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                radius: 1.15,
                colors: [Colors.transparent, Colors.black.withAlpha(190)],
                stops: const [0.55, 1.0],
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 14,
          child: SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                height: 74,
                child: PageView.builder(
                  controller: _pages,
                  itemCount: _items.length,
                  onPageChanged: (i) => setState(() => _sel = i),
                  itemBuilder: (context, i) => AnimatedBuilder(
                    animation: _pages,
                    builder: (context, _) {
                      final page = _pages.hasClients ? (_pages.page ?? _sel.toDouble()) : _sel.toDouble();
                      final t = (1 - (page - i).abs()).clamp(0.0, 1.0).toDouble();
                      final dim = i == 1 && !_hasSave;
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (i == _sel) {
                            _activate(i);
                          } else {
                            _pages.animateToPage(i, duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
                          }
                        },
                        child: Center(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Text(_items[i],
                                style: TextStyle(
                                    fontFamily: kScript,
                                    fontSize: 22 + 14 * t,
                                    color: kBone.withAlpha(((dim ? 0.3 : 0.35 + 0.65 * t) * 255).round()))),
                            const SizedBox(height: 4),
                            Container(width: 46 * t, height: 2, color: kBlood.withAlpha((t * 255).round())),
                          ]),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text('swipe to choose   tap to confirm',
                  style: TextStyle(fontFamily: kScript, fontSize: 13, color: kBone.withAlpha(110))),
            ]),
          ),
        ),
        const Positioned(
          left: 12,
          bottom: 8,
          child: Text('v0.2', style: TextStyle(fontSize: 11, color: Color(0x66E9E2CF))),
        ),
      ]),
    );
  }
}

class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({required this.title, required this.body, required this.yes, required this.no});
  final String title, body, yes, no;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF101010),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3), side: const BorderSide(color: Color(0x66E9E2CF))),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(title, style: const TextStyle(fontSize: 24, color: kBone)),
          const SizedBox(height: 8),
          Text(body, style: const TextStyle(fontSize: 16, color: Color(0xB3E9E2CF))),
          const SizedBox(height: 14),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(no, style: const TextStyle(color: kBone, fontSize: 17))),
            TextButton(onPressed: () => Navigator.pop(context, true), child: Text(yes, style: const TextStyle(color: kBloodLt, fontSize: 17))),
          ]),
        ]),
      ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.repo, required this.settings});
  final SaveRepository repo;
  final GameSettings settings;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  GameSettings get s => widget.settings;

  Widget _slider(String label, double v, double min, double max, void Function(double) set) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 2),
      child: Row(children: [
        SizedBox(width: 190, child: Text(label, style: const TextStyle(fontSize: 18, color: kBone))),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
                activeTrackColor: kBlood, inactiveTrackColor: const Color(0x33E9E2CF), thumbColor: kBone, overlayColor: Colors.transparent),
            child: Slider(
              value: v,
              min: min,
              max: max,
              onChanged: (x) => setState(() => set(x)),
              onChangeEnd: (_) => widget.repo.saveSettings(s),
            ),
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    const names = ['Low', 'Medium', 'High'];
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: Row(children: [
              IconButton(icon: const Icon(Icons.arrow_back, color: kBone), onPressed: () => Navigator.pop(context)),
              const Text('Settings', style: TextStyle(fontSize: 30, color: kBone)),
            ]),
          ),
          Expanded(
            child: ListView(children: [
              _slider('Music volume', s.music, 0, 1, (x) => s.music = x),
              _slider('Sound effects volume', s.sfx, 0, 1, (x) => s.sfx = x),
              _slider('Camera sensitivity', s.camSens, 0.4, 2, (x) => s.camSens = x),
              _slider('Control sensitivity', s.ctrlSens, 0.6, 1.5, (x) => s.ctrlSens = x),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Row(children: [
                  const SizedBox(width: 190, child: Text('Graphics quality', style: TextStyle(fontSize: 18, color: kBone))),
                  for (var i = 0; i < 3; i++)
                    GestureDetector(
                      onTap: () {
                        setState(() => s.quality = i);
                        widget.repo.saveSettings(s);
                      },
                      child: Container(
                        margin: const EdgeInsets.only(right: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          color: s.quality == i ? kBlood : Colors.transparent,
                          border: Border.all(color: s.quality == i ? kBlood : const Color(0x66E9E2CF)),
                        ),
                        child: Text(names[i], style: const TextStyle(fontSize: 17, color: kBone)),
                      ),
                    ),
                ]),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 6, 24, 0),
                child: Text('Low = blob shadows and a short draw distance. The game also lowers its draw distance by itself when the phone is struggling.',
                    style: TextStyle(fontSize: 13, color: Color(0x99E9E2CF))),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class CreditsScreen extends StatelessWidget {
  const CreditsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(children: [
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Text(
                'HMC: 1\nHoross Mission Completion: 1\n\n'
                'Game design and project owner: DoctorRIDX\n\n'
                '3D characters, vehicles and buildings: Quaternius, Lothbrok Labs (CC0 / free packs supplied by the project owner)\n'
                'Typeface: TeX Gyre Chorus (GUST Font License)\n'
                'Built with Flutter and Dart. 3D engine written in Dart.\n\n'
                'All characters, places and the city of New Merrci are fictional.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 19, height: 1.45, color: kBone),
              ),
            ),
          ),
          Positioned(
            left: 8,
            top: 4,
            child: IconButton(icon: const Icon(Icons.arrow_back, color: kBone), onPressed: () => Navigator.pop(context)),
          ),
        ]),
      ),
    );
  }
}
