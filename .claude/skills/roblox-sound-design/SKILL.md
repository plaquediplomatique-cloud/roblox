---
name: roblox-sound-design
description: Sound design and mixing craft for Roblox experiences — soundscape layers (ambience beds, spot sounds, foley, music, UI), mix priorities and ducking, variation against repetition, spatialisation and roll-off choices, indoor/outdoor reverb zones, occlusion, weapon layering (body, mechanics, tail, distant), footsteps per material, adaptive music by intensity, and the SoundscapeKit module that builds zone ambiences with reverb, random spot one-shots and music stems. Use whenever a scene feels silent, flat or repetitive, when adding sounds to weapons, doors, vehicles or UI, or when the user mentions ambiance sonore, immersion, musique dynamique, bruitages, mixage, réverbération, sons de pas, even if they only ask to "make it feel alive".
---

# Roblox Sound Design and Mix

Players judge quality with their ears before their eyes notice it. A credible soundscape is
**layered, varied, placed in space and mixed by importance**.

**Boundaries.** Audio API mechanics (Sound vs AudioPlayer/Wire graphs, SoundGroups, effects,
preloading) → `roblox-audio`. This skill decides *what* should sound, *how loud relative to what*
and *where*, and ships `scripts/SoundscapeKit.luau` for zone ambiences.

## 1. Layers of a soundscape

| Layer | What | How |
|---|---|---|
| Bed | continuous room tone / city hum / wind | 1 looped sound per zone, crossfaded (SoundscapeKit beds) |
| Spots | distant siren, bird, pipe knock, PA announcement | random one-shots placed around the listener, 5–30 s apart (SoundscapeKit spots) |
| Emitters | machinery, neon buzz, fountain, generator | looped point sources on attachments with short roll-off (10–40 studs) |
| Foley | footsteps, cloth, gear rattle, landing | from movement events, per material, volume by pace |
| Interactions | doors, buttons, pickups, elevators | at the object, start + loop + stop parts |
| Gameplay critical | gunfire, reloads, footsteps of enemies, objective cues | highest mix priority, never masked |
| Music | menu, tension, combat stems | 2D, ducked under critical sounds; stems by intensity |
| UI | hover, click, confirm, error, reward | short, 2D, consistent family |

An empty area with only music is the audio equivalent of a default baseplate: give every
playable zone a bed plus at least two spot families.

## 2. Mix priorities

1. **Information first**: sounds that change decisions (enemy steps, reloads, plant/defuse,
   footsteps behind you) sit on top; ambience and music duck under them.
2. Group everything in SoundGroups by role (Music, Weapons, Footsteps, Impacts, Feedback,
   Ambient, UI) so the mix and player settings act on roles.
3. Relative levels to start from (adjust by ear): critical 1.0, weapons 0.8–1.0, feedback 0.7,
   foley 0.5, ambience bed 0.2–0.35, spots 0.3–0.5, music 0.25–0.4 in gameplay.
4. Duck music/ambience by 30–60 % for 0.5–1.5 s on big events (kill, explosion, round end),
   then recover smoothly. `CompressorSoundEffect` with `SideChain` or a tween on group volume.
5. Never exceed 1.0 on a bus that already sums many sounds; clipping is a quality killer.

## 3. Variation (no machine-gun effect)

- 3–5 recordings per frequent sound, chosen randomly without immediate repetition.
- Pitch ±3–8 % and volume ±10 % on every play.
- Layer short transients with a randomised tail for weapons and impacts.
- Footsteps alternate left/right samples and follow the stride (distance travelled, not time).

## 4. Space

- Point sources on Attachments for small emitters; parts for volumetric sources (a whole
  waterfall, a crowd area).
- Set `RollOffMinDistance`/`RollOffMaxDistance` explicitly per family: steps 8/90,
  gunfire 20/400, ambience emitters 6/40, voice lines 10/120. Default max distance is far too
  large and makes everything audible everywhere.
- **Reverb by place**: `SoundService.AmbientReverb` per zone (`Room`, `Hallway`, `ParkingLot`,
  `Hangar`, `City`, `StoneCorridor`…), switched when the camera enters a zone
  (SoundscapeKit does this), or per-sound `ReverbSoundEffect` for weapon tails.
- **Occlusion**: a sound behind a wall must be muffled (low-pass + attenuation). The legacy
  approach raycasts camera → source; the new audio API exposes acoustic simulation
  (`SoundService.AcousticSimulationEnabled`, `OcclusionEnabled`, `DiffractionEnabled`,
  `ReverbEnabled`; per-`AudioEmitter`/`AudioListener` overrides of the same names typed
  `Enum.SimulationMode` = `Default`/`Enabled`/`Disabled`). Check in Studio
  that these are available for your experience before relying on them, and keep the raycast
  fallback.
- Distant versions: beyond ~120 studs play a darker, longer "distant" sample instead of a quiet
  close one; players read distance by ear.

## 5. Recipes

**Weapon shot** = body (punch, 0–80 ms) + mechanics (bolt/action) + tail (room-dependent) +
distant variant; first-person louder and drier than third-person. Reload = 3–5 foley events
timed to the animation (mag out, mag in, bolt).

**Door** = latch + hinge creak (pitch random) + close thud with low end; locked door = rattle.
**Elevator** = start clunk + motor loop + arrival ding + doors.
**Footsteps** = material table (Concrete, Metal, Wood, Grass, Glass, Fabric/Carpet, Water) and pace
(walk quiet, run loud, crouch near silent in competitive games).

**Adaptive music** = stems of identical length started together and never paused; volume of
upper stems follows an intensity value (combat nearby, objective, low time). SoundscapeKit
`stems` + `setIntensity`.

## 6. SoundscapeKit (concrete tool)

`scripts/SoundscapeKit.luau` (strict, client): zone boxes in a folder with attributes
`Ambience`, `Reverb`, `Priority` → crossfaded beds and `AmbientReverb` per zone; random spot
one-shots placed around the listener and filtered by zone; music stems by intensity. The header
shows a complete configuration. Tests: `lune run .claude/skills/roblox-sound-design/scripts/test_soundscape.luau`.

Zones are cheap invisible boxes: `Anchored`, `CanCollide`, `CanQuery` and `CanTouch` false,
`Transparency = 1`, placed when the level is blocked out (see `roblox-level-design`).

## 7. In this repository

- `src/Shared/Config/Sounds.luau`: logical sound keys → ids, variations, pitch ranges, groups,
  roll-offs. Code never references a SoundId directly; replace ids there.
- `src/Client/Controllers/AudioController.luau`: SoundGroup hierarchy and settings volumes,
  layered gunfire with distant versions, indoor tail detection by raycast, raycast occlusion,
  ducking, low-health low-pass + heartbeat, per-material footsteps, ambience.
- New sounds: add keys in `Sounds.luau`, call `AudioController.play/playAt/playOn`; add zone
  ambiences with the SoundscapeKit pattern rather than one-off loops.

## 8. Review checklist

- [ ] Every playable zone has a bed and spot sounds; silence is a deliberate choice.
- [ ] Critical gameplay sounds are audible over everything; music ducks under them.
- [ ] No repeated identical sample in quick succession (variations + pitch).
- [ ] Roll-off set per family; nothing audible map-wide by accident.
- [ ] Reverb matches the space; sounds behind walls are muffled.
- [ ] Interactions have start/loop/stop sounds at the object.
- [ ] Volumes respect player settings (groups) and nothing clips.
- [ ] Looped sounds are bounded (count them with `roblox-render-performance`'s SceneAudit).
