import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hmc1/engine/lighting.dart';
import 'package:hmc1/features/economy/economy.dart';
import 'package:hmc1/features/missions/mission.dart';
import 'package:hmc1/features/save/save_data.dart';
import 'package:hmc1/game/entities.dart';
import 'package:hmc1/game/game_controller.dart';
import 'package:hmc1/game/world.dart';

SaveData sample({int money = 100, double px = 70}) => SaveData(
      px: px,
      pz: 90,
      yaw: 1.5,
      money: money,
      inventory: {'supplies': 1},
      missionState: {'saving_frank': MissionState.completed.index},
      unlocked: ['home', 'will', 'hq'],
      vehicles: {
        'compact': [30.0, 40.0, 0.5]
      },
      settings: GameSettings(quality: 2),
    );

GameController newController([SaveData? d]) =>
    GameController(repo: SaveRepository(MemoryStore()), settings: GameSettings(), data: d);

/// A started game with the intro dialogue dismissed and the player on the street.
GameController street() {
  final g = newController();
  g.dialogue = null;
  g.px = 60;
  g.pz = 40;
  g.yaw = 0;
  for (final n in g.npcs) {
    n.wander = 0;
    if (n.state == NpcState.wander) n.state = NpcState.idle;
    if (n.id != 'johnson') {
      n.x = 200;
      n.z = 200;
    }
  }
  return g;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('missions', () {
    test('progression and unlocking', () {
      final m = MissionManager();
      expect(m.state['saving_frank'], MissionState.available);
      expect(m.state['chasing_johnson'], MissionState.locked);
      expect(m.accept('chasing_johnson'), isFalse);
      expect(m.accept('saving_frank'), isTrue);
      expect(m.active!.objectives.length, 4);
      for (var i = 0; i < 3; i++) {
        expect(m.advance(), isFalse);
      }
      expect(m.advance(), isTrue);
      expect(m.complete(), 100);
      expect(m.state['saving_frank'], MissionState.completed);
      expect(m.state['chasing_johnson'], MissionState.available);
    });

    test('every main mission pays exactly 100 and rewards are never duplicated', () {
      final m = MissionManager();
      final wallet = Wallet();
      for (final mission in kMissions) {
        expect(mission.reward, 100);
        expect(m.accept(mission.id), isTrue);
        wallet.add(m.complete());
        wallet.add(m.complete());
      }
      expect(wallet.money, 300);
      expect(m.allCompleted, isTrue);
    });

    test('failed missions can be retried', () {
      final m = MissionManager()..accept('saving_frank');
      m.fail();
      expect(m.state['saving_frank'], MissionState.failed);
      expect(m.accept('saving_frank'), isTrue);
    });
  });

  group('economy', () {
    test('wallet', () {
      final w = Wallet();
      expect(w.money, 0);
      w.add(100);
      expect(w.spend(30), isTrue);
      expect(w.spend(500), isFalse);
      expect(w.money, 70);
    });
    test('inventory', () {
      final i = Inventory()..add('supplies');
      expect(i.has('supplies'), isTrue);
      expect(i.remove('supplies', 2), isFalse);
      expect(i.remove('supplies'), isTrue);
      expect(i.has('supplies'), isFalse);
    });
  });

  group('save', () {
    test('round trip', () async {
      final repo = SaveRepository(MemoryStore());
      await repo.save(sample());
      final d = (await repo.load())!;
      expect(d.money, 100);
      expect(d.px, 70);
      expect(d.inventory['supplies'], 1);
      expect(d.vehicles['compact'], [30.0, 40.0, 0.5]);
      expect(d.settings.quality, 2);
    });

    test('corrupt main save falls back to backup', () async {
      final store = MemoryStore();
      final repo = SaveRepository(store);
      await repo.save(sample(money: 100));
      await repo.save(sample(money: 200));
      store.data[SaveRepository.mainKey] = '{broken';
      expect((await repo.load())!.money, 100);
    });

    test('tampered save is rejected', () async {
      final store = MemoryStore();
      final repo = SaveRepository(store);
      await repo.save(sample());
      store.data[SaveRepository.mainKey] = store.data[SaveRepository.mainKey]!.replaceAll('"money', '"mon3y');
      expect(await repo.load(), isNull);
    });
  });

  group('game controller', () {
    test('new game starts inside the house with \$0, mission 1 available and a talking Hoross', () {
      final g = newController();
      expect(g.world.inHome(g.px, g.pz), isTrue);
      expect(g.wallet.money, 0);
      expect(g.missions.state['saving_frank'], MissionState.available);
      expect(g.missions.active, isNull);
      expect(g.hero.talking, isTrue); // intro line is spoken by Hoross
    });

    test('player state is restored from a save', () {
      final g = newController(sample());
      expect(g.px, 70);
      expect(g.pz, 90);
      expect(g.wallet.money, 100);
      expect(g.inventory.has('supplies'), isTrue);
      expect(g.vehicles.firstWhere((v) => v.id == 'compact').x, 30);
      expect(g.missions.state['saving_frank'], MissionState.completed);
    });

    test('missions only start by talking to Mr. Will', () {
      final g = newController();
      g.dialogue = null;
      g.tick(0.016);
      expect(g.missions.active, isNull);
      final will = g.world.place('will');
      g.px = will.x;
      g.pz = will.z;
      g.interact();
      expect(g.dialogue!.offerId, 'saving_frank');
      g.acceptOffer();
      expect(g.missions.activeId, 'saving_frank');
    });

    test('walls block the player', () {
      expect(World().resolve(16, 21.9, 0.45).hit, isTrue);
    });

    test('buildings block the player', () {
      final bank = World.footprint(World.placements.firstWhere((p) => p.model == 'bank'));
      final r = World().resolve((bank.x0 + bank.x1) / 2, (bank.z0 + bank.z1) / 2, 0.45);
      expect(r.hit, isTrue);
    });
  });

  group('camera', () {
    test('pitch is limited so the camera never flips or goes underground', () {
      final g = street();
      g.rotateCamera(0, 100000);
      expect(g.camPitch, GameController.camPitchMax);
      g.rotateCamera(0, -100000);
      expect(g.camPitch, GameController.camPitchMin);
      g.tick(0.02);
      expect(g.camY, greaterThanOrEqualTo(0.7));
    });
  });

  group('combat, taunts and police', () {
    test('punching hurts a person and a police witness raises the wanted level', () {
      final g = street();
      final victim = g.npcs.firstWhere((n) => n.id == 'civ0');
      victim.x = g.px;
      victim.z = g.pz + 1.2;
      final cop = g.npcs.firstWhere((n) => n.id == 'cop2');
      cop.x = g.px + 6;
      cop.z = g.pz + 6;
      g.punch();
      for (var i = 0; i < 30; i++) {
        g.tick(0.03);
      }
      expect(victim.hp, lessThan(100));
      expect(g.wanted, greaterThan(0));
    });

    test('mission characters cannot be hurt', () {
      final g = street();
      final will = g.npcs.firstWhere((n) => n.id == 'will');
      will.x = g.px;
      will.z = g.pz + 1.2;
      g.punch();
      for (var i = 0; i < 30; i++) {
        g.tick(0.03);
      }
      expect(will.hp, 100);
    });

    test('taunting a gang member makes him chase you', () {
      final g = street();
      final y = g.npcs.firstWhere((n) => n.id == 'y1');
      y.x = g.px;
      y.z = g.pz + 5;
      g.taunt();
      expect(y.state, NpcState.chase);
    });

    test('police chase a wanted player', () {
      final g = street();
      final cop = g.npcs.firstWhere((n) => n.id == 'officer');
      cop.x = g.px + 20;
      cop.z = g.pz + 20;
      g.crime(2, force: true);
      g.tick(0.02);
      expect(g.wanted, 2);
      expect(cop.state, NpcState.chase);
    });

    test('wanted level is capped at 3', () {
      final g = street();
      g.crime(5, force: true);
      expect(g.wanted, 3);
    });
  });

  group('vehicles and passengers', () {
    test('a pillion passenger can ride the bike and gets off with the rider', () {
      final g = street();
      final bike = g.vehicles.firstWhere((v) => v.id == 'bike');
      bike.x = g.px + 1;
      bike.z = g.pz;
      g.interact();
      expect(g.driving, same(bike));
      final p = g.npcs.firstWhere((n) => n.id == 'civ1');
      p.x = bike.x + 2;
      p.z = bike.z + 2;
      g.pickUpPassenger();
      expect(p.riding, isTrue);
      expect(bike.passengers.length, 1);
      expect(bike.freeSeats, 0);
      g.interact();
      expect(g.driving, isNull);
      expect(p.riding, isFalse);
      expect(bike.passengers, isEmpty);
    });
  });

  group('lighting', () {
    test('noon is brighter than midnight and shadows fade at night', () {
      final l = Lighting()..update(12, 0);
      final noon = l.sunInt;
      final noonShadow = l.shadowAlpha;
      l.update(0, 0);
      expect(noon, greaterThan(l.sunInt));
      expect(noonShadow, greaterThan(l.shadowAlpha));
      expect(l.shadowAlpha, lessThan(0.02));
    });
  });

  group('assets', () {
    final man = jsonDecode(File('assets/models/manifest.json').readAsStringSync()) as Map<String, dynamic>;

    test('every model used by the game exists in the manifest', () {
      for (final d in kVehicleDefs.values) {
        expect((man['vehicles'] as Map).containsKey(d.model), isTrue, reason: d.model);
        expect(File('assets/models/${(man['vehicles'] as Map)[d.model]['file']}').existsSync(), isTrue);
      }
      for (final p in World.placements) {
        expect((man['buildings'] as Map).containsKey(p.model), isTrue, reason: p.model);
      }
      final g = newController();
      for (final n in g.npcs) {
        expect((man['characters'] as Map).containsKey(n.model), isTrue, reason: n.model);
      }
      expect((man['props'] as Map).containsKey('pine'), isTrue);
      expect(File('assets/models/${man['anims']}').existsSync(), isTrue);
    });

    test('collision footprints match the converted building sizes', () {
      for (final e in kModelSize.entries) {
        final b = (man['buildings'] as Map)[e.key] as Map;
        final mn = (b['min'] as List).cast<num>(), mx = (b['max'] as List).cast<num>();
        expect((mx[0] - mn[0]).toDouble(), closeTo(e.value[0], 0.15), reason: e.key);
        expect((mx[1] - mn[1]).toDouble(), closeTo(e.value[1], 0.15), reason: e.key);
        expect((mx[2] - mn[2]).toDouble(), closeTo(e.value[2], 0.15), reason: e.key);
      }
    });

    test('there are at least five animation clips for the character rig', () {
      final f = File('assets/models/char.anim').readAsBytesSync();
      final text = String.fromCharCodes(f);
      for (final n in ['Idle', 'Walk', 'Run', 'Jump', 'Punch']) {
        expect(text.contains(n), isTrue, reason: n);
      }
    });
  });
}
