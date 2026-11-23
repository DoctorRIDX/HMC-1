const int kMissionReward = 100;

enum MissionState { locked, available, active, completed, failed }

enum ObjType { reach, talk, catchTarget, escort }

class Objective {
  const Objective(this.text, this.type, this.target,
      {this.radius = 4, this.dialogue, this.effect, this.escortNpc});
  final String text;
  final ObjType type;

  /// A place id ("hq") or an NPC ("npc:johnson").
  final String target;
  final double radius;
  final String? dialogue;
  final String? effect;
  final String? escortNpc;
}

class Mission {
  const Mission({
    required this.id,
    required this.title,
    required this.description,
    required this.objectives,
    required this.offerDialogue,
    required this.doneDialogue,
    this.giver = 'Mr. Will',
    this.reward = kMissionReward,
    this.startEffect,
    this.endEffect,
    this.timeLimit,
  });
  final String id, title, description, giver, offerDialogue, doneDialogue;
  final List<Objective> objectives;
  final int reward;
  final String? startEffect, endEffect;
  final double? timeLimit; // seconds; failure condition when exceeded
}

const List<Mission> kMissions = [
  Mission(
    id: 'saving_frank',
    title: 'Saving Mr. Frank',
    description: 'Yellwo kidnapped Mr. Frank. Find him and bring him safely to Gromson HQ.',
    offerDialogue: 'm1_offer',
    doneDialogue: 'm1_done',
    endEffect: 'frankSafe',
    objectives: [
      Objective('Travel to the Yellwo warehouse', ObjType.reach, 'yellwo', radius: 14),
      Objective('Confront the Yellwo guards', ObjType.talk, 'npc:guard1',
          dialogue: 'm1_guard', effect: 'guardsFlee'),
      Objective('Find Mr. Frank', ObjType.talk, 'npc:frank',
          dialogue: 'm1_frank', effect: 'frankFollow'),
      Objective('Escort Mr. Frank to Gromson HQ', ObjType.escort, 'hq',
          radius: 12, escortNpc: 'frank'),
    ],
  ),
  Mission(
    id: 'chasing_johnson',
    title: 'Chasing Johnson',
    description: 'Johnson from Yellwo stole Gromson supplies. Catch his van and bring them back.',
    offerDialogue: 'm2_offer',
    doneDialogue: 'm2_done',
    startEffect: 'spawnJohnson',
    endEffect: 'johnsonGone',
    timeLimit: 420,
    objectives: [
      Objective('Find Johnson (follow the map marker)', ObjType.reach, 'npc:johnson', radius: 45),
      Objective("Catch up to Johnson's van and stop it", ObjType.catchTarget, 'npc:johnson',
          radius: 7, dialogue: 'm2_catch', effect: 'johnsonStop'),
      Objective('Recover the stolen supplies', ObjType.talk, 'npc:johnson',
          dialogue: 'm2_supplies', effect: 'getSupplies'),
      Objective('Return the supplies to Gromson HQ', ObjType.reach, 'hq', radius: 12),
    ],
  ),
  Mission(
    id: 'picking_up_ariss',
    title: 'Picking Up Ariss',
    description: 'Ariss is waiting at the police station. Pick her up and take her home.',
    offerDialogue: 'm3_offer',
    doneDialogue: 'm3_done',
    endEffect: 'arissHome',
    objectives: [
      Objective('Travel to the police station', ObjType.reach, 'police', radius: 12),
      Objective('Speak with Officer Dale', ObjType.talk, 'npc:officer', dialogue: 'm3_officer'),
      Objective('Meet Ariss', ObjType.talk, 'npc:ariss',
          dialogue: 'm3_ariss', effect: 'arissFollow'),
      Objective("Escort Ariss to her house", ObjType.escort, 'ariss_home',
          radius: 10, escortNpc: 'ariss'),
    ],
  ),
];

/// Pure-Dart mission state machine (no Flutter), covered by unit tests.
class MissionManager {
  MissionManager([List<Mission>? list]) : missions = list ?? kMissions {
    for (final m in missions) {
      state[m.id] = MissionState.locked;
    }
    if (missions.isNotEmpty) state[missions.first.id] = MissionState.available;
  }

  final List<Mission> missions;
  final Map<String, MissionState> state = {};
  String? activeId;
  int objIndex = 0;
  double elapsed = 0;

  Mission? byId(String id) {
    for (final m in missions) {
      if (m.id == id) return m;
    }
    return null;
  }

  Mission? get active => activeId == null ? null : byId(activeId!);

  /// The mission Mr. Will can currently offer (available, or failed for retry).
  Mission? get offerable {
    for (final m in missions) {
      final s = state[m.id];
      if (s == MissionState.available || s == MissionState.failed) return m;
    }
    return null;
  }

  Objective? get currentObjective {
    final m = active;
    if (m == null || objIndex >= m.objectives.length) return null;
    return m.objectives[objIndex];
  }

  bool accept(String id) {
    if (activeId != null) return false;
    final m = byId(id);
    final s = state[id];
    if (m == null || (s != MissionState.available && s != MissionState.failed)) {
      return false;
    }
    state[id] = MissionState.active;
    activeId = id;
    objIndex = 0;
    elapsed = 0;
    return true;
  }

  /// Moves to the next objective. Returns true when all objectives are done.
  bool advance() {
    final m = active;
    if (m == null) return false;
    objIndex++;
    return objIndex >= m.objectives.length;
  }

  /// Completes the active mission and returns the reward. Returns 0 if there
  /// is no active mission, so a reward can never be granted twice.
  int complete() {
    final m = active;
    if (m == null || state[m.id] != MissionState.active) return 0;
    state[m.id] = MissionState.completed;
    activeId = null;
    objIndex = 0;
    elapsed = 0;
    final i = missions.indexOf(m);
    if (i + 1 < missions.length && state[missions[i + 1].id] == MissionState.locked) {
      state[missions[i + 1].id] = MissionState.available;
    }
    return m.reward;
  }

  void fail() {
    final m = active;
    if (m == null) return;
    state[m.id] = MissionState.failed;
    activeId = null;
    objIndex = 0;
    elapsed = 0;
  }

  bool get allCompleted => state.values.every((s) => s == MissionState.completed);

  void restore(Map<String, int> saved, String? activeMission, int index, double time) {
    for (final m in missions) {
      final i = saved[m.id];
      state[m.id] = (i != null && i >= 0 && i < MissionState.values.length)
          ? MissionState.values[i]
          : state[m.id]!;
    }
    activeId = null;
    for (final m in missions) {
      if (state[m.id] == MissionState.active) {
        if (activeId == null && (activeMission == null || activeMission == m.id)) {
          activeId = m.id;
        } else {
          state[m.id] = MissionState.available;
        }
      }
    }
    final a = active;
    objIndex = a == null ? 0 : (index < 0 ? 0 : (index > a.objectives.length ? a.objectives.length : index));
    elapsed = a == null ? 0 : time;
  }
}
