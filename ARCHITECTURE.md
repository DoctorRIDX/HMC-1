# Architecture

```
lib/
  main.dart                   landscape + immersive mode
  app/app.dart                theme, palette, font constant
  engine/
    math34.dart               3x4 affine matrices (left-handed: x right, y up, z forward)
    assets.dart               loaders for the converted .smesh/.cmesh/.anim files, ModelLibrary
    skeleton.dart             Actor (clip cross-fade), Pose, evaluatePose (skinning matrices, procedural extras)
    lighting.dart             sun/moon, ambient, sky, shadow strength from time of day + clouds
    renderer.dart             WorldRenderer (software 3D), WorldPainter
  game/
    world.dart                New Merrci layout, placements, collision, camera clipping
    entities.dart             Vehicle(+defs), Npc (extends Actor), NPC states
    game_controller.dart      gameplay: player, camera, combat, taunts, police, passengers, missions, autosave
  features/                   missions, dialogue text, economy (wallet/inventory), save (versioned, checksummed, backup)
  ui/                         menu (swipe strip), settings, credits, HUD/game screen, map painter, widgets
tool/convert_models.py        ModelHMC.zip -> compact binary assets
tool/android_icons/           launcher icons made from the HMC logo
```
- Rendering path per frame: collect draw items (buildings with LOD, props, vehicles, characters), keep the nearest within a
  triangle budget, draw far to near. Every item is transformed to view space, back-face culled, lit per face, fogged, sorted
  and appended to one vertex buffer that is drawn once. Ground, roads and shadows are polygons drawn before it.
- Gameplay logic has no dependency on assets, so it is unit-tested without loading models.
- Mission effects (guards flee, Frank follows, ...) are named strings applied by `GameController._applyEffect` and replayed from saved progress.
