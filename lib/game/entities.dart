import 'dart:typed_data';

import '../engine/skeleton.dart';

enum NpcKind { civilian, gromson, yellwo, police, key }

enum NpcState { idle, wander, flee, chase, down, follow, drive, passenger }

class VehicleDef {
  const VehicleDef(this.id, this.name, this.model, this.len, this.wid, this.maxSpeed, this.accel,
      {this.seats = 3, this.bike = false, this.enterable = true, this.radius = 1.4});
  final String id, name, model;
  final double len, wid, maxSpeed, accel, radius;
  final int seats;
  final bool bike, enterable;
}

const Map<String, VehicleDef> kVehicleDefs = {
  'compact': VehicleDef('compact', 'Compact Car', 'compact', 4.6, 2.0, 19, 7.5),
  'sedan': VehicleDef('sedan', 'Sedan', 'sedan', 4.7, 2.0, 23, 7.0),
  'gang': VehicleDef('gang', 'Gromson Pickup', 'gromson', 5.4, 2.2, 21, 6.5),
  'bike': VehicleDef('bike', 'Motorbike', 'bike', 2.3, 0.7, 26, 10, seats: 1, bike: true, radius: 0.8),
  'ambulance': VehicleDef('ambulance', 'Ambulance', 'ambulance', 5.5, 2.3, 20, 6),
  'truck': VehicleDef('truck', 'Delivery Truck', 'truck', 7.4, 2.6, 16, 4.5, radius: 1.8),
  'police': VehicleDef('police', 'Police Car', 'police', 4.7, 2.0, 24, 9, enterable: false),
  'racer': VehicleDef('racer', "Yellwo Racer", 'yellwo', 4.8, 2.1, 25, 9, enterable: false),
};

class Vehicle {
  Vehicle(this.id, this.def, this.x, this.z, this.yaw, {this.ai = false});
  final String id;
  final VehicleDef def;
  final bool ai; // police patrol cars
  double x, z, yaw;
  double speed = 0, steer = 0, roll = 0, stuckT = 0, ramT = 0;
  int routeIdx = 0;
  List<List<double>> route = const [];
  final List<Npc> passengers = [];
  bool get isBike => def.bike;
  int get freeSeats => def.seats - passengers.length;
}

class Npc extends Actor {
  Npc(this.id, this.name, this.kind, double x, double z,
      {this.dlg = 'civ',
      this.wander = 0,
      this.model = 'casual2m',
      Map<String, int> tint = const {},
      int skin = 0xD6A07A,
      this.visible = true,
      this.temper = 0.4,
      this.protected = false})
      : x = x,
        z = z,
        hx = x,
        hz = z,
        tx = x,
        tz = z,
        tint = {'Skin': skin, ...tint};

  final String id, name, dlg, model;
  final NpcKind kind;
  final Map<String, int> tint;
  final double temper;
  final bool protected; // mission characters cannot be hurt
  double wander;
  bool visible;
  double x, z, hx, hz, tx, tz;
  double yaw = 0, wait = 0, speed = 0;
  double hp = 100, stun = 0, downT = 0, attackCd = 0, aggroT = 0, fleeT = 0, hitPending = 0;
  bool moving = false, driving = false, riding = false;
  NpcState state = NpcState.idle;
  Vehicle? ride;
  List<List<double>> route = const [];
  int routeIdx = 0;
  Uint8List? matRgb; // cached recolored materials (renderer)

  bool get alive => state != NpcState.down;
  bool get follow => state == NpcState.follow;
}
