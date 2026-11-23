import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const int kSaveVersion = 1;

class GameSettings {
  GameSettings(
      {this.music = 0.7,
      this.sfx = 0.8,
      this.camSens = 1.0,
      this.ctrlSens = 1.0,
      this.quality = 1});
  double music, sfx, camSens, ctrlSens;
  int quality; // 0 low, 1 medium, 2 high

  Map<String, dynamic> toJson() => {
        'music': music,
        'sfx': sfx,
        'camSens': camSens,
        'ctrlSens': ctrlSens,
        'quality': quality,
      };

  factory GameSettings.fromJson(Object? raw) {
    final Map j = raw is Map ? raw : const {};
    double d(String k, double def) {
      final v = j[k];
      return v is num && v.isFinite ? v.toDouble() : def;
    }

    final q = j['quality'];
    return GameSettings(
        music: d('music', 0.7),
        sfx: d('sfx', 0.8),
        camSens: d('camSens', 1.0),
        ctrlSens: d('ctrlSens', 1.0),
        quality: q is int && q >= 0 && q <= 2 ? q : 1);
  }
}

class SaveData {
  SaveData({
    this.version = kSaveVersion,
    required this.px,
    required this.pz,
    required this.yaw,
    required this.money,
    required this.inventory,
    required this.missionState,
    this.activeMission,
    this.objIndex = 0,
    this.missionTime = 0,
    required this.unlocked,
    required this.vehicles,
    this.driving,
    required this.settings,
    this.savedAt = 0,
  });

  final int version;
  final double px, pz, yaw;
  final int money;
  final Map<String, int> inventory;
  final Map<String, int> missionState; // mission id -> MissionState.index
  final String? activeMission;
  final int objIndex;
  final double missionTime;
  final List<String> unlocked;
  final Map<String, List<double>> vehicles; // id -> [x, z, yaw]
  final String? driving;
  final GameSettings settings;
  final int savedAt;

  Map<String, dynamic> toJson() => {
        'version': version,
        'px': px,
        'pz': pz,
        'yaw': yaw,
        'money': money,
        'inventory': inventory,
        'missionState': missionState,
        'activeMission': activeMission,
        'objIndex': objIndex,
        'missionTime': missionTime,
        'unlocked': unlocked,
        'vehicles': vehicles,
        'driving': driving,
        'settings': settings.toJson(),
        'savedAt': savedAt,
      };

  /// Throws [FormatException] when the data is not a valid save.
  factory SaveData.fromJson(Map<String, dynamic> j) {
    final v = j['version'];
    if (v is! int || v < 1 || v > kSaveVersion) {
      throw const FormatException('bad version');
    }
    double n(String k) {
      final x = j[k];
      if (x is num && x.isFinite && x.abs() < 10000) return x.toDouble();
      throw FormatException('bad $k');
    }

    final money = j['money'];
    if (money is! int || money < 0) throw const FormatException('bad money');
    Map<String, int> ints(Object? m) {
      if (m is! Map) throw const FormatException('bad map');
      return {for (final e in m.entries) e.key as String: (e.value as num).toInt()};
    }

    final veh = j['vehicles'];
    if (veh is! Map) throw const FormatException('bad vehicles');
    return SaveData(
      version: v,
      px: n('px'),
      pz: n('pz'),
      yaw: n('yaw'),
      money: money,
      inventory: ints(j['inventory']),
      missionState: ints(j['missionState']),
      activeMission: j['activeMission'] as String?,
      objIndex: (j['objIndex'] as num?)?.toInt() ?? 0,
      missionTime: (j['missionTime'] as num?)?.toDouble() ?? 0,
      unlocked: [for (final u in (j['unlocked'] as List)) u as String],
      vehicles: {
        for (final e in veh.entries)
          e.key as String: [for (final x in e.value as List) (x as num).toDouble()]
      },
      driving: j['driving'] as String?,
      settings: GameSettings.fromJson(j['settings']),
      savedAt: (j['savedAt'] as num?)?.toInt() ?? 0,
    );
  }
}

abstract class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
}

class PrefsStore implements KeyValueStore {
  Future<SharedPreferences> get _p => SharedPreferences.getInstance();
  @override
  Future<String?> read(String key) async => (await _p).getString(key);
  @override
  Future<void> write(String key, String value) async {
    await (await _p).setString(key, value);
  }

  @override
  Future<void> remove(String key) async {
    await (await _p).remove(key);
  }
}

class MemoryStore implements KeyValueStore {
  final Map<String, String> data = {};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
  @override
  Future<void> remove(String key) async => data.remove(key);
}

/// Versioned, checksummed saves with an automatic backup of the previous
/// valid save. [load] falls back to the backup when the main save is corrupt.
class SaveRepository {
  SaveRepository(this.store);
  final KeyValueStore store;

  static const mainKey = 'hmc1_save';
  static const backupKey = 'hmc1_save_bak';
  static const settingsKey = 'hmc1_settings';

  static int checksum(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h;
  }

  String _encode(SaveData d) {
    final body = jsonEncode(d.toJson());
    return jsonEncode({'sum': checksum(body), 'body': body});
  }

  SaveData? _decode(String? raw) {
    if (raw == null) return null;
    try {
      final o = jsonDecode(raw) as Map<String, dynamic>;
      final body = o['body'] as String;
      if (o['sum'] != checksum(body)) return null;
      return SaveData.fromJson(jsonDecode(body) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(SaveData d) async {
    final prev = await store.read(mainKey);
    if (prev != null && _decode(prev) != null) await store.write(backupKey, prev);
    await store.write(mainKey, _encode(d));
  }

  Future<SaveData?> load() async =>
      _decode(await store.read(mainKey)) ?? _decode(await store.read(backupKey));

  Future<bool> hasSave() async => (await load()) != null;

  Future<void> clear() async {
    await store.remove(mainKey);
    await store.remove(backupKey);
  }

  Future<GameSettings> loadSettings() async {
    final raw = await store.read(settingsKey);
    if (raw == null) return GameSettings();
    try {
      return GameSettings.fromJson(jsonDecode(raw));
    } catch (_) {
      return GameSettings();
    }
  }

  Future<void> saveSettings(GameSettings s) =>
      store.write(settingsKey, jsonEncode(s.toJson()));
}
