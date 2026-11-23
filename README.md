# HMC: 1 - Hoross Mission Completion: 1

Offline, single-player, third-person 3D open-world city game for Android (Flutter/Dart).
You play **Hoross** of the **Gromson** gang in **New Merrci**, take jobs from **Mr. Will**,
fight, flee the police and ride around with passengers.

## BUILD STATUS (read first)
This version was written in an environment with **no Flutter SDK and no network**:
`flutter analyze`, `flutter test` and `flutter build apk` have **never been run**, and the
game has **never been run on a phone**. What *was* verified: the model converter and the
animation/skinning/shading math (a Python reference renderer was used to check every model,
pose and the left/right orientation), YAML files parse, brackets balance, and all asset paths exist.
Expect a few compile errors and some performance tuning on the first real build.
Run the GitHub workflows (below) and send the error log back.

## 3D technology
A software 3D engine in pure Dart (`lib/engine/`): triangles are transformed, flat-lit
(moving sun, sky/ground ambient, passing clouds, distance fog), depth-sorted and drawn with a
single `Canvas.drawVertices` call per frame. Skeletal animation (skinning) runs on the CPU.
Models come from `ModelHMC.zip` and are converted by `tool/convert_models.py` into small binary files
(`assets/models/`, 1.5 MB): 7 animated character meshes, 8 vehicles, 11 building models (2 LODs each), trees.
Trade-offs: no textures (colors are baked per triangle), CPU-bound. A **frame-time governor** lowers the
draw distance automatically on slow phones; Settings has Low/Medium/High (Low = blob shadows, shorter distance).

## Controls
Left stick move/steer/throttle, drag the screen to orbit the camera (up/down/left/right, tilt limited),
**Act** talk/enter/exit, **Punch**, **Jump**, **Run** (hold), **Taunt** (provoke the nearest person),
**Ride** (in a vehicle: pick up a nearby person - pillion on the motorbike, passenger in cars).
Tap the radar for the full map.

## Implemented
- GTA SA-style UI: muted palette (no neon), script typeface (TeX Gyre Chorus), round radar upper-left,
  money/health/wanted stars small at upper-right, **objective, alerts, subtitles and dialogue at the bottom**
  (nothing banner-like at the top of the screen). Main menu: logo + a swipeable menu strip at the bottom.
- App icon and name are the HMC logo (installed by the workflow, see below).
- Day/night cycle (1 game hour = 40 s), cloud dimming, projected shadows (characters animate their shadow), police lights, headlights at night.
- 10 animations: idle, walk, run, jump, punch, hit reaction, sit (riding), death, taunt (victory) + a procedural
  talking animation (head and arm gestures) during dialogue.
- Fighting: punch people, they react (flee or fight back), get knocked out and recover; taunt people;
  crimes seen by police raise a 3-star wanted level; police on foot and in cars chase you; get caught = BUSTED,
  lose all health = WASTED (respawn at the hospital). Mission characters cannot be hurt.
- Vehicles: compact car, taxi sedan, Gromson pickup, motorbike (visible riders), ambulance, delivery truck; police cars patrol.
- All 3 required missions (exactly $100 each, no duplicate rewards), mission timer on Mission 2, autosave with backup.
- Unit tests in `test/hmc_test.dart` (missions, rewards, save/load, combat, taunt, police, passengers, camera limits, lighting, asset manifest).

## Known limitations
- **No audio** (volume sliders are saved but nothing plays).
- Not compiled or run yet (see above). Performance on real phones is unknown.
- No textures, no real-time per-pixel lighting; far buildings use a low-detail model; triangles are sorted per frame (rare popping/overlap artifacts).
- Vehicles do not collide with each other; occupants of cars are not drawn (only motorbike riders are).
- `android/` is generated in CI by `flutter create`; release APK uses Flutter's default debug signing.
- Hoross's house is a simple open-top room (the pack has no interiors); no shop, no integration tests.

## GitHub Actions from a phone
1. Push the project (below). 2. GitHub -> repo -> **Actions** -> **Android Build** -> **Run workflow**.
3. When it finishes, open the run and download the artifact `hmc1-release-apk`. **Analyze** and **Test** are separate workflows.
Each workflow generates `android/`, installs the HMC launcher icon (`tool/android_icons`) and names the app "HMC: 1".

## Push from Termux
```sh
cd ~
cp /sdcard/Download/HMC-1-Android-Project.zip ~/
unzip -o HMC-1-Android-Project.zip && cd hmc-1
git init -b main && git add -A && git commit -m "HMC: 1 3D version"
git remote add origin https://github.com/DoctorRIDX/HMC-1.git
git push -u origin main
```
(Termux cannot write to `/tmp`; stay inside `~`.)

## Re-converting models
`python3 tool/convert_models.py /path/to/ModelHMC assets/models` (needs numpy and Pillow).

## Release signing (not automated)
Put the keystore in a base64 GitHub Secret, decode it in the workflow to `android/app/upload.jks`, write
`android/key.properties` from other secrets and point `signingConfigs` in `android/app/build.gradle(.kts)` at it.
Never commit keystores.
