import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../engine/lighting.dart';
import '../engine/skeleton.dart';
import '../features/dialogue/dialogue_data.dart';
import '../features/economy/economy.dart';
import '../features/missions/mission.dart';
import '../features/save/save_data.dart';
import 'entities.dart';
import 'world.dart';

class ActiveDialogue {
  ActiveDialogue(this.lines, {this.onDone, this.offerId, this.talkTo});
  final List<DL> lines;
  final VoidCallback? onDone;
  final String? offerId;
  final Npc? talkTo;
  int index = 0;
  DL get line => lines[index];
  bool get last => index >= lines.length - 1;
}

class MissionResult {
  const MissionResult(this.title, this.reward);
  final String title;
  final int reward;
}

/// A short line shown in the bottom subtitle area (never at the top of the screen).
class Subtitle {
  Subtitle(this.who, this.text, this.ttl);
  final String who, text;
  double ttl;
}

double _turn(double a, double b, double step) {
  var d = (b - a) % (2 * pi);
  if (d > pi) d -= 2 * pi;
  return a + max(-step, min(step, d));
}

double _dist(double ax, double az, double bx, double bz) {
  final dx = ax - bx, dz = az - bz;
  return sqrt(dx * dx + dz * dz);
}

/// Owns all gameplay state: player, vehicles, NPCs, combat, police, missions, saves.
class GameController extends ChangeNotifier {
  GameController({required this.repo, required this.settings, SaveData? data}) {
    _initWorld();
    if (data != null) {
      _restore(data);
    } else {
      _spawnNew();
    }
    _updateCamera(1);
  }

  final SaveRepository repo;
  final GameSettings settings;
  final World world = World();
  final MissionManager missions = MissionManager();
  final Wallet wallet = Wallet();
  final Inventory inventory = Inventory();
  final Set<String> unlocked = {'home', 'will'};
  final List<Vehicle> vehicles = [];
  final List<Npc> npcs = [];
  final Actor hero = Actor();
  final Lighting lighting = Lighting();
  final List<Subtitle> subtitles = [];
  final Random _rng = Random(11);

  // time
  double hour = 9.5, clock = 0;

  // player
  double px = 20, py = 0, pz = 12.5, vy = 0, yaw = 0, speedKmh = 0, hp = 100;
  double joyX = 0, joyY = 0;
  bool moving = false, sprint = false, paused = false, onGround = true;
  int wanted = 0;
  Vehicle? driving;
  double punchT = 0, punchCd = 0, tauntT = 0, deadT = 0, bannerT = 0, bustedT = 0;
  bool _hitDone = false;
  String? banner;

  // camera (orbit with pitch limits)
  double camYaw = 0, camPitch = 0.34, camX = 0, camY = 3, camZ = 0, _camDist = 7.5;
  double _dragIdle = 9;
  static const double camPitchMin = 0.06, camPitchMax = 1.15;

  // ui state
  ActiveDialogue? dialogue;
  MissionResult? completion;
  String? prompt;
  bool canRide = false, canTaunt = false;
  double _saveT = 0, _wantedClearT = 0;

  bool get inHome => World.homeRect.contains(px, pz);
  bool get night => lighting.day < 0.3;
  String get clockText {
    final h = hour.floor() % 24, m = ((hour - hour.floor()) * 60).floor();
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  // ---------------------------------------------------------------- setup

  void _initWorld() {
    Vehicle veh(String id, String def, double x, double z, double yaw, {bool ai = false}) =>
        Vehicle(id, kVehicleDefs[def]!, x, z, yaw, ai: ai);
    vehicles.addAll([
      veh('compact', 'compact', 26, 38.5, pi / 2),
      veh('sedan', 'sedan', 52, 122, pi / 2),
      veh('gang', 'gang', 214, 150, 0),
      veh('bike', 'bike', 31, 28, 0),
      veh('ambulance', 'ambulance', 100, 209, -pi / 2),
      veh('truck', 'truck', 222, 178, pi / 2),
      veh('police1', 'police', 146, 106, pi / 2, ai: true)
        ..route = [
          [146, 120],
          [200, 120],
          [200, 40],
          [120, 40],
          [120, 120],
        ],
      veh('police2', 'police', 176, 106, -pi / 2, ai: true)
        ..route = [
          [176, 120],
          [120, 120],
          [120, 200],
          [200, 200],
          [200, 120],
        ],
    ]);
    Map<String, int> shirt(int c) => {'Shirt': c, 'Vest': c};
    Npc n(String id, String name, NpcKind k, double x, double z,
            {String dlg = 'civ', double wander = 0, String model = 'casual2m', Map<String, int> tint = const {},
            int skin = 0xD6A07A, bool visible = true, double temper = 0.4, bool prot = false}) =>
        Npc(id, name, k, x, z,
            dlg: dlg, wander: wander, model: model, tint: tint, skin: skin, visible: visible, temper: temper, protected: prot);
    npcs.addAll([
      n('will', 'Mr. Will', NpcKind.key, 80, 108, model: 'suitm', skin: 0xB07A55, prot: true),
      n('frank', 'Mr. Frank', NpcKind.key, 167, 147,
          model: 'workerm', dlg: 'frank_idle', tint: shirt(0x7A4E9C), skin: 0xE0B08C, prot: true),
      n('guard1', 'Yellwo Guard', NpcKind.yellwo, 156, 143,
          model: 'workerm', dlg: 'yellwo', tint: shirt(0xE8C21A), temper: 0.9),
      n('guard2', 'Yellwo Guard', NpcKind.yellwo, 161, 141,
          model: 'casual2m', dlg: 'yellwo', tint: shirt(0xE8C21A), temper: 0.9, skin: 0x8A5A3C),
      n('officer', 'Officer Dale', NpcKind.police, 160, 104, model: 'copm', dlg: 'cop', temper: 0.9),
      n('cop2', 'Officer Reyes', NpcKind.police, 150, 106,
          model: 'copm', dlg: 'cop', wander: 5, temper: 0.9, skin: 0x9A6A48),
      n('ariss', 'Ariss', NpcKind.key, 166, 105,
          model: 'casual2f', dlg: 'ariss_idle', tint: shirt(0xC2557A), skin: 0xE0B08C, prot: true),
      n('g1', 'Gromson Member', NpcKind.gromson, 80, 142,
          dlg: 'gromson', wander: 4, tint: shirt(0x2E8B3E), temper: 0.7),
      n('g2', 'Gromson Member', NpcKind.gromson, 86, 146,
          model: 'workerm', dlg: 'gromson', wander: 4, tint: shirt(0x2E8B3E), temper: 0.7, skin: 0x8A5A3C),
      n('g3', 'Gromson Member', NpcKind.gromson, 73, 146,
          dlg: 'gromson', wander: 3, tint: shirt(0x2E8B3E), temper: 0.7, skin: 0xB07A55),
      n('y1', 'Yellwo Member', NpcKind.yellwo, 150, 136,
          dlg: 'yellwo', wander: 4, tint: shirt(0xE8C21A), temper: 0.9),
      n('y2', 'Yellwo Member', NpcKind.yellwo, 172, 137,
          model: 'workerm', dlg: 'yellwo', wander: 4, tint: shirt(0xE8C21A), temper: 0.9, skin: 0xB07A55),
      n('johnson', 'Johnson', NpcKind.yellwo, 158, 120,
          dlg: 'yellwo', tint: shirt(0xE8C21A), visible: false, temper: 0.9, prot: true),
    ]);
    final johnson = npcs.last;
    johnson.driving = true;
    johnson.state = NpcState.drive;
    johnson.route = [
      [158, 120],
      [200, 120],
      [200, 40],
      [120, 40],
      [120, 200],
      [200, 200],
      [200, 120],
    ];
    const civModels = ['casual2m', 'workerf', 'oldm', 'casual2f', 'workerm'];
    const civShirts = [0x5C6BC0, 0xC0504D, 0x2E9C8F, 0x8E5BA8, 0xD9733B, 0x6B7B8C];
    const civSkins = [0xD6A07A, 0xB07A55, 0x8A5A3C, 0xE0B08C];
    const spots = [
      [48.0, 36.0, 18.0], [96.0, 124.0, 20.0], [222.0, 70.0, 14.0], [230.0, 100.0, 8.0],
      [20.0, 40.0, 10.0], [210.0, 38.0, 15.0], [130.0, 36.0, 12.0], [32.0, 120.0, 10.0],
      [60.0, 118.0, 12.0], [100.0, 200.0, 14.0],
    ];
    for (var i = 0; i < spots.length; i++) {
      final c = spots[i];
      npcs.add(n('civ$i', 'Civilian', NpcKind.civilian, c[0], c[1],
          wander: c[2],
          model: civModels[i % civModels.length],
          tint: shirt(civShirts[i % civShirts.length]),
          skin: civSkins[(i * 3) % civSkins.length],
          temper: 0.25 + (i % 4) * 0.15));
    }
    for (final c in npcs) {
      c.state = c.state == NpcState.drive ? NpcState.drive : (c.wander > 0 ? NpcState.wander : NpcState.idle);
    }
  }

  void _spawnNew() {
    px = 20;
    pz = 12.5;
    yaw = 0;
    camYaw = 0;
    startDialogue(kDialogue['intro']!);
    save();
  }

  void _restore(SaveData d) {
    px = d.px;
    pz = d.pz;
    yaw = d.yaw;
    camYaw = d.yaw;
    wallet.money = d.money;
    inventory.items
      ..clear()
      ..addAll(d.inventory);
    missions.restore(d.missionState, d.activeMission, d.objIndex, d.missionTime);
    unlocked.addAll(d.unlocked);
    for (final v in vehicles) {
      final s = d.vehicles[v.id];
      if (!v.ai && s != null && s.length >= 3) {
        v.x = s[0];
        v.z = s[1];
        v.yaw = s[2];
      }
    }
    if (d.driving != null) {
      for (final v in vehicles) {
        if (v.id == d.driving) {
          driving = v;
          px = v.x;
          pz = v.z;
          _seatHero(v);
        }
      }
    }
    for (final m in missions.missions) {
      if (missions.state[m.id] == MissionState.completed) _applyEffect(m.endEffect);
    }
    final a = missions.active;
    if (a != null) {
      _applyEffect(a.startEffect);
      for (var i = 0; i < missions.objIndex && i < a.objectives.length; i++) {
        _applyEffect(a.objectives[i].effect);
      }
    }
  }

  Npc _npc(String id) => npcs.firstWhere((n) => n.id == id);

  void _applyEffect(String? e) {
    switch (e) {
      case 'guardsFlee':
        for (final n in npcs) {
          if (n.id.startsWith('guard')) {
            n.visible = false;
            n.state = NpcState.idle;
          }
        }
        break;
      case 'frankFollow':
        _npc('frank').state = NpcState.follow;
        break;
      case 'frankSafe':
        {
          final n = _npc('frank');
          final p = world.place('hq');
          n.state = NpcState.wander;
          n.wander = 3;
          n.riding = false;
          n.x = n.hx = p.x + 3;
          n.z = n.hz = p.z + 2;
        }
        break;
      case 'spawnJohnson':
        {
          final j = _npc('johnson');
          j.visible = true;
          j.driving = true;
          j.moving = true;
          j.state = NpcState.drive;
          j.routeIdx = 1;
          j.x = j.route[0][0];
          j.z = j.route[0][1];
          j.yaw = pi / 2;
        }
        break;
      case 'johnsonStop':
        _npc('johnson').moving = false;
        break;
      case 'getSupplies':
        if (!inventory.has('supplies')) inventory.add('supplies');
        break;
      case 'johnsonGone':
        {
          final j = _npc('johnson');
          j.visible = false;
          j.moving = false;
          inventory.remove('supplies');
        }
        break;
      case 'arissFollow':
        _npc('ariss').state = NpcState.follow;
        break;
      case 'arissHome':
        {
          final n = _npc('ariss');
          final p = world.place('ariss_home');
          n.state = NpcState.idle;
          n.riding = false;
          n.x = n.hx = p.x + 2;
          n.z = n.hz = p.z - 2;
        }
        break;
    }
  }

  // ----------------------------------------------------------- persistence

  SaveData snapshot() => SaveData(
        px: px,
        pz: pz,
        yaw: yaw,
        money: wallet.money,
        inventory: Map.of(inventory.items),
        missionState: {for (final e in missions.state.entries) e.key: e.value.index},
        activeMission: missions.activeId,
        objIndex: missions.objIndex,
        missionTime: missions.elapsed,
        unlocked: unlocked.toList(),
        vehicles: {
          for (final v in vehicles)
            if (!v.ai) v.id: [v.x, v.z, v.yaw]
        },
        driving: driving?.id,
        settings: settings,
        savedAt: DateTime.now().millisecondsSinceEpoch,
      );

  Future<void> save() => repo.save(snapshot());

  // ------------------------------------------------------------- queries

  P2 targetOf(String t) {
    if (t.startsWith('npc:')) {
      final n = _npc(t.substring(4));
      return P2(n.x, n.z);
    }
    final p = world.place(t);
    return P2(p.x, p.z);
  }

  P2? get waypoint {
    final o = missions.currentObjective;
    if (o != null) return targetOf(o.target);
    if (missions.active == null && missions.offerable != null) return targetOf('will');
    return null;
  }

  double? get waypointDistance {
    final w = waypoint;
    return w == null ? null : _dist(px, pz, w.x, w.z);
  }

  String get missionTitle {
    final a = missions.active;
    if (a != null) return a.title;
    final o = missions.offerable;
    if (o != null) return '${o.title} (available)';
    return missions.allCompleted ? 'All missions complete' : 'Free roam';
  }

  String get objectiveText {
    final o = missions.currentObjective;
    if (o != null) return o.text;
    if (missions.active != null) return 'Mission complete';
    if (missions.offerable != null) return "Go to Mr. Will's house and talk to him";
    return 'Explore New Merrci';
  }

  String? get timerText {
    final lim = missions.active?.timeLimit;
    if (lim == null) return null;
    final left = max(0, (lim - missions.elapsed).ceil());
    return '${left ~/ 60}:${(left % 60).toString().padLeft(2, '0')}';
  }

  // ---------------------------------------------------------------- input

  /// Horizontal drag turns the camera; vertical drag tilts it (limited, like other games).
  void rotateCamera(double dx, double dy) {
    camYaw += dx * 0.006 * settings.camSens;
    camPitch = max(camPitchMin, min(camPitchMax, camPitch + dy * 0.004 * settings.camSens));
    _dragIdle = 0;
  }

  bool get _locked => paused || dialogue != null || completion != null || deadT > 0 || bannerT > 0;

  void interact() {
    if (_locked) return;
    final v = driving;
    if (v != null) {
      _click();
      _exitVehicle(v);
      return;
    }
    final n = _nearNpc();
    if (n != null) {
      _talk(n);
      return;
    }
    final car = _nearVehicle();
    if (car != null) {
      _click();
      _enterVehicle(car);
    }
  }

  void jump() {
    if (_locked || driving != null || !onGround) return;
    vy = 7.4;
    onGround = false;
    hero.play('Jump', restart: true);
  }

  void punch() {
    if (_locked || driving != null || punchCd > 0 || tauntT > 0) return;
    punchCd = 0.7;
    punchT = 0.0001;
    _hitDone = false;
    hero.play('Punch', restart: true);
  }

  void taunt() {
    if (_locked || driving != null || tauntT > 0 || punchT > 0) return;
    final n = _nearestNpc(9, includeKey: false);
    tauntT = 1.1;
    hero.play('Victory', restart: true);
    if (n == null) {
      say('Hoross', 'Anybody wanna go?', ttl: 2);
      return;
    }
    yaw = atan2(n.x - px, n.z - pz);
    const lines = ['Hey! Yeah, you. What are you looking at?', 'Come on then, tough guy!', 'You call that a stance?'];
    say('Hoross', lines[_rng.nextInt(lines.length)], ttl: 2.4);
    _provoke(n, extra: 0.35);
    if (n.kind == NpcKind.police) crime(1, force: true);
  }

  /// Invites a nearby person onto the vehicle (motorbike pillion or car seat).
  void pickUpPassenger() {
    final v = driving;
    if (_locked || v == null) return;
    if (v.freeSeats <= 0) {
      say('', 'No free seat.', ttl: 2);
      return;
    }
    Npc? best;
    var bd = 7.0;
    for (final n in npcs) {
      if (!n.visible || n.riding || n.state == NpcState.down || n.driving || n.state == NpcState.chase) continue;
      if (n.kind == NpcKind.police) continue;
      final d = _dist(v.x, v.z, n.x, n.z);
      if (d < bd) {
        bd = d;
        best = n;
      }
    }
    if (best == null) {
      say('', 'Nobody close enough to pick up.', ttl: 2);
      return;
    }
    _board(best, v);
    say(best.name, v.isBike ? 'Alright, hold on tight!' : 'Thanks for the ride!', ttl: 2.4);
  }

  void _board(Npc n, Vehicle v) {
    n.state = n.state == NpcState.follow ? NpcState.follow : NpcState.passenger;
    n.riding = true;
    n.ride = v;
    if (!v.passengers.contains(n)) v.passengers.add(n);
    n.play('SitDown', restart: true);
    n.t = 5;
    n.blend = 1;
  }

  void _click() => SystemSound.play(SystemSoundType.click);

  Npc? _nearNpc() {
    Npc? best;
    var bd = 1e9;
    for (final n in npcs) {
      if (!n.visible || n.riding || n.state == NpcState.down) continue;
      final r = n.driving ? 5.5 : 3.0;
      final d = _dist(px, pz, n.x, n.z);
      if (d < r && d < bd) {
        bd = d;
        best = n;
      }
    }
    return best;
  }

  Npc? _nearestNpc(double maxD, {bool includeKey = true}) {
    Npc? best;
    var bd = maxD;
    for (final n in npcs) {
      if (!n.visible || n.riding || n.state == NpcState.down || n.driving) continue;
      if (!includeKey && n.kind == NpcKind.key) continue;
      final d = _dist(px, pz, n.x, n.z);
      if (d < bd) {
        bd = d;
        best = n;
      }
    }
    return best;
  }

  Vehicle? _nearVehicle() {
    Vehicle? best;
    var bd = 3.8;
    for (final v in vehicles) {
      if (!v.def.enterable) continue;
      final d = _dist(px, pz, v.x, v.z);
      if (d < bd) {
        bd = d;
        best = v;
      }
    }
    return best;
  }

  void _seatHero(Vehicle v) {
    if (v.isBike) {
      hero.play('SitDown', restart: true);
      hero.t = 5;
      hero.blend = 1;
    }
  }

  void _enterVehicle(Vehicle v) {
    driving = v;
    v.speed = 0;
    px = v.x;
    pz = v.z;
    py = 0;
    vy = 0;
    onGround = true;
    _seatHero(v);
    for (final n in npcs) {
      if (n.state == NpcState.follow && _dist(n.x, n.z, v.x, v.z) < 12 && v.freeSeats > 0) _board(n, v);
    }
    save();
  }

  void _exitVehicle(Vehicle v) {
    px = v.x + cos(v.yaw) * (v.isBike ? 1.4 : 2.6);
    pz = v.z - sin(v.yaw) * (v.isBike ? 1.4 : 2.6);
    final r = world.resolve(px, pz, 0.45);
    px = r.x;
    pz = r.z;
    v.speed = 0;
    driving = null;
    hero.play('Idle', restart: true);
    var k = 0;
    for (final n in List<Npc>.of(v.passengers)) {
      v.passengers.remove(n);
      n.riding = false;
      n.ride = null;
      final wasFollow = n.state == NpcState.follow;
      n.x = v.x - cos(v.yaw) * (1.8 + k * 0.8);
      n.z = v.z + sin(v.yaw) * (1.8 + k * 0.8);
      final rr = world.resolve(n.x, n.z, 0.45);
      n.x = rr.x;
      n.z = rr.z;
      n.hx = n.x;
      n.hz = n.z;
      n.play('Idle', restart: true);
      if (!wasFollow) {
        n.state = n.wander > 0 ? NpcState.wander : NpcState.idle;
        say(n.name, 'Thanks, Hoross. See you around!', ttl: 2.4);
      }
      k++;
    }
    save();
  }

  // ------------------------------------------------------- subtitles/dialogue

  void say(String who, String text, {double ttl = 3.2}) {
    subtitles.add(Subtitle(who, text, ttl));
    while (subtitles.length > 2) {
      subtitles.removeAt(0);
    }
  }

  void startDialogue(List<DL> lines, {VoidCallback? onDone, String? offerId, Npc? talkTo}) {
    dialogue = ActiveDialogue(lines, onDone: onDone, offerId: offerId, talkTo: talkTo);
    joyX = 0;
    joyY = 0;
    _applyDialogueActors();
    notifyListeners();
  }

  void _applyDialogueActors() {
    final d = dialogue;
    if (d == null) {
      hero.talking = false;
      return;
    }
    final heroSpeaks = d.line.speaker == 'Hoross';
    hero.talking = heroSpeaks;
    final n = d.talkTo;
    if (n != null) n.talking = !heroSpeaks;
  }

  void _endDialogueActors(ActiveDialogue d) {
    hero.talking = false;
    d.talkTo?.talking = false;
  }

  void nextDialogue() {
    final d = dialogue;
    if (d == null) return;
    if (!d.last) {
      d.index++;
      _applyDialogueActors();
      notifyListeners();
      return;
    }
    dialogue = null;
    _endDialogueActors(d);
    d.onDone?.call();
    notifyListeners();
  }

  void acceptOffer() {
    final d = dialogue;
    if (d == null || d.offerId == null) return;
    dialogue = null;
    _endDialogueActors(d);
    _acceptMission(d.offerId!);
    notifyListeners();
  }

  void declineOffer() {
    final d = dialogue;
    dialogue = null;
    if (d != null) _endDialogueActors(d);
    notifyListeners();
  }

  void dismissCompletion() {
    completion = null;
    notifyListeners();
  }

  void _talk(Npc n) {
    _click();
    if (n.id == 'will') {
      if (missions.active != null) {
        startDialogue(kDialogue['will_busy']!, talkTo: n);
        return;
      }
      final m = missions.offerable;
      if (m == null) {
        startDialogue(kDialogue['will_none']!, talkTo: n);
      } else {
        startDialogue(kDialogue[m.offerDialogue]!, offerId: m.id, talkTo: n);
      }
      return;
    }
    final o = missions.currentObjective;
    if (o != null && o.type == ObjType.talk && o.target == 'npc:${n.id}') {
      startDialogue(kDialogue[o.dialogue]!, onDone: () => _advance(o), talkTo: n);
      return;
    }
    startDialogue(kDialogue[n.dlg] ?? kDialogue['civ']!, talkTo: n);
  }

  // -------------------------------------------------------------- missions

  void _acceptMission(String id) {
    if (!missions.accept(id)) return;
    final m = missions.active!;
    _applyEffect(m.startEffect);
    _unlockTarget();
    say('', 'Mission started: ${m.title}', ttl: 3.5);
    save();
  }

  void _unlockTarget() {
    final o = missions.currentObjective;
    if (o != null && !o.target.startsWith('npc:')) unlocked.add(o.target);
  }

  void _advance(Objective o) {
    _applyEffect(o.effect);
    final done = missions.advance();
    if (done) {
      _finishMission();
    } else {
      _unlockTarget();
      say('', 'Objective: ${missions.currentObjective!.text}', ttl: 3.5);
      save();
    }
    notifyListeners();
  }

  void _finishMission() {
    final m = missions.active;
    if (m == null) return;
    startDialogue(kDialogue[m.doneDialogue]!, onDone: _complete);
  }

  void _complete() {
    final m = missions.active;
    final reward = missions.complete();
    if (m == null || reward == 0) return; // a reward can never be paid twice
    wallet.add(reward);
    _applyEffect(m.endEffect);
    completion = MissionResult(m.title, reward);
    save();
    notifyListeners();
  }

  void _failMission() {
    final m = missions.active;
    if (m == null) return;
    missions.fail();
    _applyEffect('johnsonGone');
    say('', 'Mission failed: ${m.title}. Talk to Mr. Will to retry.', ttl: 4.5);
    save();
  }

  void _updateMission(double dt) {
    final m = missions.active;
    if (m == null) return;
    missions.elapsed += dt;
    final lim = m.timeLimit;
    if (lim != null && missions.elapsed > lim) {
      _failMission();
      return;
    }
    final o = missions.currentObjective;
    if (o == null) {
      _finishMission();
      return;
    }
    final t = targetOf(o.target);
    final d = _dist(px, pz, t.x, t.z);
    switch (o.type) {
      case ObjType.reach:
        if (d <= o.radius) _advance(o);
        break;
      case ObjType.catchTarget:
        if (d <= o.radius) {
          _applyEffect(o.effect);
          startDialogue(kDialogue[o.dialogue]!, onDone: () => _advance(o), talkTo: _npc(o.target.substring(4)));
        }
        break;
      case ObjType.escort:
        final f = _npc(o.escortNpc!);
        if (d <= o.radius && _dist(f.x, f.z, t.x, t.z) <= o.radius + 6) _advance(o);
        break;
      case ObjType.talk:
        break;
    }
  }

  // ----------------------------------------------------- combat and police

  /// Registers a crime. It only counts when police can see it (or [force]).
  void crime(int amount, {bool force = false}) {
    if (!force && !_policeNear(40)) return;
    final before = wanted;
    wanted = min(3, wanted + amount);
    _wantedClearT = 0;
    if (wanted > before) say('', wanted == 1 ? 'Wanted level up. Police are after you!' : 'Wanted level: $wanted', ttl: 2.6);
  }

  bool _policeNear(double r) {
    for (final n in npcs) {
      if (n.kind == NpcKind.police && n.visible && n.alive && _dist(px, pz, n.x, n.z) < r) return true;
    }
    for (final v in vehicles) {
      if (v.ai && _dist(px, pz, v.x, v.z) < r) return true;
    }
    return false;
  }

  void _provoke(Npc n, {double extra = 0}) {
    if (n.protected || n.kind == NpcKind.key || n.state == NpcState.down) return;
    final fight = n.kind == NpcKind.police ||
        n.kind == NpcKind.yellwo ||
        n.kind == NpcKind.gromson ||
        _rng.nextDouble() < n.temper + extra;
    if (fight) {
      n.state = NpcState.chase;
      n.aggroT = 18;
      n.say(this, const ['You asked for it!', "Big mistake, pal!", "Come here!"][_rng.nextInt(3)]);
    } else {
      n.state = NpcState.flee;
      n.fleeT = 9;
      n.say(this, const ['Help! Somebody!', "Leave me alone!", 'Crazy person!'][_rng.nextInt(3)]);
    }
  }

  void _punchHit() {
    Npc? best;
    var bd = 2.1;
    final fx = sin(yaw), fz = cos(yaw);
    for (final n in npcs) {
      if (!n.visible || n.riding || n.driving || n.state == NpcState.down) continue;
      final dx = n.x - px, dz = n.z - pz;
      final d = sqrt(dx * dx + dz * dz);
      if (d > bd || d < 0.01) continue;
      if ((dx * fx + dz * fz) / d < 0.15) continue;
      bd = d;
      best = n;
    }
    if (best == null) return;
    final n = best;
    if (n.protected) {
      say(n.name, 'Hey! Easy there, Hoross!', ttl: 2.2);
      return;
    }
    n.hp -= 25;
    n.stun = 0.55;
    n.play('RecieveHit', restart: true);
    final d = max(0.3, _dist(px, pz, n.x, n.z));
    final r = world.resolve(n.x + (n.x - px) / d * 0.5, n.z + (n.z - pz) / d * 0.5, 0.4);
    n.x = r.x;
    n.z = r.z;
    if (n.kind == NpcKind.police) {
      crime(2, force: true);
    } else if (n.kind == NpcKind.civilian) {
      crime(1);
    } else {
      crime(1);
    }
    if (n.hp <= 0) {
      n.state = NpcState.down;
      n.downT = 22;
      n.play('Death', restart: true);
    } else {
      _provoke(n);
    }
  }

  void hurt(double dmg) {
    if (deadT > 0 || bannerT > 0) return;
    hp -= dmg;
    if (punchT <= 0 && driving == null) hero.play('RecieveHit', restart: true);
    if (hp <= 0) {
      hp = 0;
      deadT = 3.6;
      banner = 'WASTED';
      bannerT = 3.6;
      hero.play('Death', restart: true);
      wanted = 0;
    }
  }

  void _respawn() {
    final p = world.place('hospital');
    final v = driving;
    if (v != null) _exitVehicle(v);
    px = p.x;
    pz = p.z + 2;
    py = 0;
    hp = 100;
    deadT = 0;
    hero.play('Idle', restart: true);
    camYaw = pi;
    for (final n in npcs) {
      if (n.state == NpcState.chase || n.state == NpcState.flee) n.state = n.wander > 0 ? NpcState.wander : NpcState.idle;
    }
    save();
  }

  void _busted() {
    banner = 'BUSTED';
    bannerT = 2.8;
    final v = driving;
    if (v != null) _exitVehicle(v);
    final p = world.place('police');
    px = p.x - 4;
    pz = p.z - 1;
    wanted = 0;
    hp = max(hp, 60);
    bustedT = 0;
    for (final n in npcs) {
      if (n.kind == NpcKind.police && n.state == NpcState.chase) n.state = n.wander > 0 ? NpcState.wander : NpcState.idle;
    }
    for (final c in vehicles) {
      if (c.ai) c.speed = 0;
    }
    save();
  }

  void _updatePolice(double dt) {
    if (wanted <= 0) {
      bustedT = 0;
      _wantedClearT = 0;
      return;
    }
    var near = false;
    var contact = false;
    for (final n in npcs) {
      if (n.kind != NpcKind.police || !n.visible || !n.alive) continue;
      final d = _dist(px, pz, n.x, n.z);
      if (d < 70 && n.state != NpcState.chase && n.stun <= 0) {
        n.state = NpcState.chase;
        n.aggroT = 30;
      }
      if (d < 55) near = true;
      if (d < 1.9) contact = true;
    }
    for (final v in vehicles) {
      if (!v.ai) continue;
      final d = _dist(px, pz, v.x, v.z);
      if (d < 60) near = true;
      if (d < 4.6) contact = true;
    }
    final slow = driving == null || (driving!.speed.abs() < 6);
    if (contact && slow) {
      bustedT += dt;
      if (bustedT > 1.6) _busted();
    } else {
      bustedT = max(0, bustedT - dt * 1.5);
    }
    if (!near) {
      _wantedClearT += dt;
      if (_wantedClearT > 8) {
        _wantedClearT = 0;
        wanted--;
        say('', wanted == 0 ? 'You lost the police.' : 'Wanted level down.', ttl: 2.4);
      }
    } else {
      _wantedClearT = 0;
    }
  }

  // ------------------------------------------------------------ simulation

  void tick(double dt) {
    if (dt <= 0) return;
    if (dt > 0.05) dt = 0.05;
    _tickSubtitles(dt);
    if (paused || completion != null) return;
    if (dialogue != null) {
      _tickDialogue(dt);
      _updateCamera(dt);
      notifyListeners();
      return;
    }
    clock += dt;
    hour = (hour + dt / 40) % 24;
    lighting.update(hour, clock);
    if (bannerT > 0) {
      bannerT -= dt;
      if (bannerT <= 0) banner = null;
    }
    if (deadT > 0) {
      deadT -= dt;
      hero.advance(dt);
      if (deadT <= 0) _respawn();
    } else {
      _updatePlayer(dt);
    }
    _updateVehicles(dt);
    _updateNpcs(dt);
    _updatePolice(dt);
    _updateMission(dt);
    _updatePrompt();
    _saveT += dt;
    if (_saveT > 25) {
      _saveT = 0;
      save();
    }
    _updateCamera(dt);
    notifyListeners();
  }

  void _tickSubtitles(double dt) {
    for (final s in subtitles) {
      s.ttl -= dt;
    }
    subtitles.removeWhere((s) => s.ttl <= 0);
  }

  void _tickDialogue(double dt) {
    hero.advance(dt);
    final n = dialogue?.talkTo;
    if (n != null) {
      n.advance(dt);
      yaw = _turn(yaw, atan2(n.x - px, n.z - pz), 6 * dt);
      n.yaw = _turn(n.yaw, atan2(px - n.x, pz - n.z), 6 * dt);
    }
  }

  void _updateCamera(double dt) {
    final v = driving;
    final ty = py + (v == null ? 1.5 : (v.isBike ? 1.5 : 1.3));
    final want = v == null ? 7.2 : (v.isBike ? 8.5 : 11.0);
    final cp = cos(camPitch), sp = sin(camPitch);
    final fx = sin(camYaw) * cp, fy = -sp, fz = cos(camYaw) * cp;
    final allowed = world.camClip(px, ty, pz, -fx, -fy, -fz, want, skipHome: inHome);
    if (allowed < _camDist) {
      _camDist = allowed;
    } else {
      _camDist = min(allowed, _camDist + dt * 8);
    }
    camX = px - fx * _camDist;
    camY = max(0.7, ty - fy * _camDist);
    camZ = pz - fz * _camDist;
  }

  void _updatePlayer(double dt) {
    _dragIdle += dt;
    if (punchCd > 0) punchCd -= dt;
    if (tauntT > 0) tauntT -= dt;
    if (hp < 100 && wanted == 0) hp = min(100, hp + dt * 1.5);
    final v = driving;
    if (v == null) {
      moving = false;
      speedKmh = 0;
      final mag = min(1.0, sqrt(joyX * joyX + joyY * joyY) * settings.ctrlSens);
      var speed = 0.0;
      final busy = punchT > 0 || tauntT > 0;
      if (mag > 0.12 && !busy) {
        final sx = sin(camYaw), sz = cos(camYaw), rx = cos(camYaw), rz = -sin(camYaw);
        var dx = sx * joyY + rx * joyX, dz = sz * joyY + rz * joyX;
        final len = sqrt(dx * dx + dz * dz);
        if (len > 0) {
          dx /= len;
          dz /= len;
        }
        yaw = _turn(yaw, atan2(dx, dz), 12 * dt);
        speed = (sprint ? 6.2 : 2.6) * (mag > 0.8 ? 1.0 : 0.7 + mag * 0.3);
        final r = world.resolve(px + dx * speed * dt, pz + dz * speed * dt, 0.45);
        px = r.x;
        pz = r.z;
        moving = true;
      }
      // jumping
      if (!onGround) {
        py += vy * dt;
        vy -= 22 * dt;
        if (py <= 0) {
          py = 0;
          vy = 0;
          onGround = true;
        }
      }
      // punching
      if (punchT > 0) {
        punchT += dt;
        if (!_hitDone && punchT >= 0.25) {
          _hitDone = true;
          _punchHit();
        }
        if (punchT >= 0.72) punchT = 0;
      }
      // animation selection
      if (hp > 0) {
        if (!onGround) {
          hero.play('Jump');
        } else if (punchT > 0) {
          hero.play('Punch');
        } else if (tauntT > 0) {
          hero.play('Victory');
        } else if (hero.anim == 'RecieveHit' && hero.t < 0.6) {
          // let the hit reaction finish
        } else if (moving) {
          hero.play(sprint ? 'Run' : 'Walk');
        } else {
          hero.play('Idle');
        }
      }
      final rate = hero.anim == 'Walk' ? max(0.6, speed / 2.0) : (hero.anim == 'Run' ? max(0.7, speed / 4.6) : 1.0);
      hero.advance(dt, rate);
    } else {
      _driveHero(v, dt);
    }
    _checkLocations();
  }

  void _driveHero(Vehicle v, double dt) {
    final def = v.def;
    final th = joyY.abs() > 0.15 ? joyY : 0.0;
    if (th > 0) {
      v.speed += def.accel * th * dt * (v.speed < 0 ? 3 : 1);
    } else if (th < 0) {
      v.speed -= (v.speed > 0.5 ? def.accel * 2.4 : def.accel * 0.7) * (-th) * dt;
    } else {
      final drag = 5 * dt;
      v.speed = v.speed.abs() <= drag ? 0 : v.speed - drag * v.speed.sign;
    }
    v.speed = max(-def.maxSpeed * 0.35, min(def.maxSpeed, v.speed));
    final steer = max(-1.0, min(1.0, joyX * settings.ctrlSens));
    v.steer += (steer - v.steer) * min(1.0, dt * 8);
    final sf = v.speed.abs() / (v.speed.abs() + 4);
    v.yaw += v.steer * (v.isBike ? 2.3 : 1.8) * sf * (v.speed >= 0 ? 1 : -1) * dt;
    final r = world.resolve(v.x + sin(v.yaw) * v.speed * dt, v.z + cos(v.yaw) * v.speed * dt, def.radius);
    if (r.hit) v.speed *= 0.45;
    v.x = r.x;
    v.z = r.z;
    v.roll += v.speed * dt / 0.36;
    px = v.x;
    pz = v.z;
    yaw = v.yaw;
    moving = v.speed.abs() > 0.5;
    speedKmh = v.speed.abs() * 3.6;
    if (_dragIdle > 1.5) camYaw = _turn(camYaw, v.yaw, 1.4 * dt);
    if (v.isBike) {
      hero.play('SitDown');
      hero.t = 5;
      hero.blend = 1;
    }
    // running people over (knocks them down, is a crime)
    if (v.speed.abs() > 5) {
      for (final n in npcs) {
        if (!n.visible || n.riding || n.driving || n.state == NpcState.down || n.protected) continue;
        if (_dist(v.x, v.z, n.x, n.z) < def.radius + 0.8) {
          n.hp -= 45;
          n.stun = 0.7;
          n.play('RecieveHit', restart: true);
          if (n.hp <= 0) {
            n.state = NpcState.down;
            n.downT = 22;
            n.play('Death', restart: true);
          }
          crime(1);
        }
      }
    }
  }

  void _checkLocations() {
    for (final p in World.places) {
      if (!unlocked.contains(p.id) && _dist(px, pz, p.x, p.z) < 45) {
        unlocked.add(p.id);
        say('', 'New location: ${p.name}', ttl: 3);
        save();
      }
    }
  }

  // police cars patrol, or chase while the player is wanted
  void _updateVehicles(double dt) {
    for (final v in vehicles) {
      if (v.ai) {
        _driveAi(v, dt);
      } else if (v != driving) {
        // coasting parked cars roll to a stop
        if (v.speed.abs() > 0.1) {
          v.speed *= max(0.0, 1 - dt * 3);
        } else {
          v.speed = 0;
        }
        v.roll += v.speed * dt / 0.36;
      }
      for (final n in v.passengers) {
        n.x = v.x;
        n.z = v.z;
        n.yaw = v.yaw;
      }
    }
  }

  void _driveAi(Vehicle v, double dt) {
    double tx, tz;
    var maxV = 11.0;
    if (wanted > 0) {
      tx = px;
      tz = pz;
      maxV = 14.0 + wanted * 2.0;
      final d = _dist(v.x, v.z, tx, tz);
      if (d < 7) maxV = max(2.0, d * 0.9);
    } else {
      final w = v.route[v.routeIdx];
      tx = w[0];
      tz = w[1];
      if (_dist(v.x, v.z, tx, tz) < 6) v.routeIdx = (v.routeIdx + 1) % v.route.length;
    }
    final want = atan2(tx - v.x, tz - v.z);
    v.yaw = _turn(v.yaw, want, 1.9 * dt);
    final diff = ((want - v.yaw) % (2 * pi));
    final off = diff > pi ? 2 * pi - diff : diff;
    final target = maxV * (1 - min(0.6, off / pi));
    v.speed += (target - v.speed) * min(1.0, dt * 1.6);
    final r = world.resolve(v.x + sin(v.yaw) * v.speed * dt, v.z + cos(v.yaw) * v.speed * dt, v.def.radius);
    if (r.hit) {
      v.stuckT += dt;
      v.yaw += 1.4 * dt;
      v.speed *= 0.6;
    } else {
      v.stuckT = 0;
    }
    v.x = r.x;
    v.z = r.z;
    v.roll += v.speed * dt / 0.36;
    v.steer = (v.steer * 0.9) + (off > 0.05 ? 0.1 : 0);
  }

  void _updateNpcs(double dt) {
    for (final n in npcs) {
      if (!n.visible) continue;
      final d = _dist(px, pz, n.x, n.z);
      final important = n.state == NpcState.follow ||
          n.state == NpcState.drive ||
          n.state == NpcState.passenger ||
          n.state == NpcState.chase;
      if (!important && d > 80) {
        n.moving = false;
        continue;
      }
      if (n.attackCd > 0) n.attackCd -= dt;
      if (n.stun > 0) {
        n.stun -= dt;
        n.advance(dt);
        continue;
      }
      switch (n.state) {
        case NpcState.down:
          n.advance(dt);
          n.downT -= dt;
          if (n.downT <= 0) {
            n.hp = 60;
            n.state = n.wander > 0 ? NpcState.wander : NpcState.idle;
            n.play('Idle', restart: true);
          }
          break;
        case NpcState.drive:
          _driveNpc(n, dt);
          break;
        case NpcState.follow:
          _followNpc(n, dt);
          break;
        case NpcState.passenger:
          n.advance(dt);
          break;
        case NpcState.chase:
          _chaseNpc(n, dt);
          break;
        case NpcState.flee:
          _fleeNpc(n, dt);
          break;
        case NpcState.wander:
        case NpcState.idle:
          _wanderNpc(n, dt);
          break;
      }
    }
  }

  void _walkNpc(Npc n, double dx, double dz, double speed, double dt) {
    final d = sqrt(dx * dx + dz * dz);
    if (d < 0.01) return;
    n.yaw = _turn(n.yaw, atan2(dx, dz), 10 * dt);
    final r = world.resolve(n.x + dx / d * speed * dt, n.z + dz / d * speed * dt, 0.4);
    n.x = r.x;
    n.z = r.z;
    n.moving = true;
  }

  void _anim(Npc n, String name, double dt, [double rate = 1]) {
    n.play(name);
    n.advance(dt, rate);
  }

  void _wanderNpc(Npc n, double dt) {
    n.moving = false;
    if (n.wander <= 0) {
      _anim(n, 'Idle', dt);
      return;
    }
    if (n.wait > 0) {
      n.wait -= dt;
      _anim(n, 'Idle', dt);
      return;
    }
    final ex = n.tx - n.x, ez = n.tz - n.z;
    if (sqrt(ex * ex + ez * ez) < 0.6) {
      n.wait = 1.5 + _rng.nextDouble() * 4;
      n.tx = n.hx + (_rng.nextDouble() * 2 - 1) * n.wander;
      n.tz = n.hz + (_rng.nextDouble() * 2 - 1) * n.wander;
      _anim(n, 'Idle', dt);
      return;
    }
    _walkNpc(n, ex, ez, 1.7, dt);
    _anim(n, 'Walk', dt, 0.85);
  }

  void _fleeNpc(Npc n, double dt) {
    n.fleeT -= dt;
    final dx = n.x - px, dz = n.z - pz;
    if (n.fleeT <= 0 || sqrt(dx * dx + dz * dz) > 30) {
      n.state = n.wander > 0 ? NpcState.wander : NpcState.idle;
      return;
    }
    _walkNpc(n, dx, dz, 5.2, dt);
    _anim(n, 'Run', dt, 1.1);
  }

  void _chaseNpc(Npc n, double dt) {
    n.aggroT -= dt;
    final dx = px - n.x, dz = pz - n.z;
    final d = sqrt(dx * dx + dz * dz);
    final isCop = n.kind == NpcKind.police;
    if (driving != null && !isCop && d > 4) {
      n.state = n.wander > 0 ? NpcState.wander : NpcState.idle;
      return;
    }
    if ((n.aggroT <= 0 && !(isCop && wanted > 0)) || d > 90) {
      n.state = n.wander > 0 ? NpcState.wander : NpcState.idle;
      return;
    }
    if (n.hitPending > 0) {
      n.hitPending -= dt;
      if (n.hitPending <= 0 && d < 2.2 && driving == null) hurt(isCop ? 5 : 9);
    }
    if (d > 1.4) {
      _walkNpc(n, dx, dz, isCop ? 5.4 : 4.6, dt);
      _anim(n, 'Run', dt, 1.15);
    } else {
      n.moving = false;
      n.yaw = _turn(n.yaw, atan2(dx, dz), 10 * dt);
      if (n.attackCd <= 0 && !isCop) {
        n.attackCd = 1.4;
        n.hitPending = 0.32;
        n.play('Punch', restart: true);
      }
      if (n.anim == 'Punch' && n.t < 0.7) {
        n.advance(dt);
      } else {
        _anim(n, 'Idle', dt);
      }
    }
  }

  void _followNpc(Npc n, double dt) {
    final v = driving;
    if (v != null && n.riding) {
      n.x = px;
      n.z = pz;
      n.advance(dt);
      return;
    }
    n.riding = false;
    final ex = px - n.x, ez = pz - n.z;
    final d = sqrt(ex * ex + ez * ez);
    if (d > 2.8) {
      final s = d > 12 ? 7.0 : (sprint ? 5.8 : 3.0);
      _walkNpc(n, ex, ez, s, dt);
      _anim(n, s > 4 ? 'Run' : 'Walk', dt, s > 4 ? s / 4.6 : s / 2.0);
    } else {
      n.moving = false;
      _anim(n, 'Idle', dt);
    }
  }

  void _driveNpc(Npc n, double dt) {
    if (!n.moving) {
      n.speed = 0;
      return;
    }
    final w = n.route[n.routeIdx];
    final ex = w[0] - n.x, ez = w[1] - n.z;
    if (sqrt(ex * ex + ez * ez) < 6) {
      n.routeIdx = (n.routeIdx + 1) % n.route.length;
      return;
    }
    n.yaw = _turn(n.yaw, atan2(ex, ez), 2.6 * dt);
    n.speed = 10.5;
    n.x += sin(n.yaw) * n.speed * dt;
    n.z += cos(n.yaw) * n.speed * dt;
  }

  void _updatePrompt() {
    canTaunt = driving == null && _nearestNpc(9, includeKey: false) != null;
    canRide = false;
    final v = driving;
    if (v != null) {
      prompt = v.isBike ? 'Get off the bike' : 'Exit vehicle';
      for (final n in npcs) {
        if (!n.visible || n.riding || n.state == NpcState.down || n.driving || n.kind == NpcKind.police) continue;
        if (_dist(v.x, v.z, n.x, n.z) < 7 && v.freeSeats > 0) canRide = true;
      }
      return;
    }
    final n = _nearNpc();
    if (n != null) {
      prompt = 'Talk to ${n.name}';
      return;
    }
    final c = _nearVehicle();
    prompt = c != null ? 'Get on ${c.def.name}' : null;
  }
}

extension on Npc {
  void say(GameController g, String text) => g.say(name, text, ttl: 2.2);
}
