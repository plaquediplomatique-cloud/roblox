---
name: roblox-level-design
description: Level design for Roblox — player metrics derived from the actual character controller, blockout-to-dressing workflow, critical path and flow, landmarks, sightlines and cover, spawn safety, competitive arenas, hubs, open worlds and cities, and StreamingEnabled zoning for large maps. Use whenever the user designs or reviews a map, level, arena, hub, district, dungeon, obby or quest area (carte, niveau, map, circulation du joueur, placement des bâtiments, grandes maps), even if they only ask to "build a map" — pair it with roblox-environment-art for the visual pass.
---

# Roblox Level Design

A level is a sequence of intentional experiences delivered through space. The order is always
**metrics → blockout → play → fix → dress**. Art never rescues a layout that plays badly, and
dressing a layout before it is validated multiplies rework.

**Boundaries.** This skill owns layout, flow, metrics, sightlines and world partitioning.
Construction mechanics (MCP build contract, CSG, validation scripts) → `roblox-building`.
Visual composition and set dressing → `roblox-environment-art`. Props and furniture specs →
`roblox-props-modeling`. Loops, onboarding and progression design → `roblox-game-design`.

## 1. Derive metrics from the real controller

Every gap, ledge, door and corridor is sized in units of what the character can do. Measure
once, write the numbers into the level brief, and re-derive them if movement changes.

Jump physics on Roblox: apex `h = JumpHeight`, take-off speed `v0 = √(2·g·h)`, air time
`t = 2·v0/g` with `g = Workspace.Gravity` (196.2 by default). Flat gap ≈ `speed × t`.

| Controller | Speed | Jump apex | Air time | Max flat gap | Design gap (≈ 80 %) |
|---|---|---|---|---|---|
| Roblox defaults (`CharacterWalkSpeed` 16, `CharacterJumpHeight` 7.2) | 16 | 7.2 | 0.54 s | 8.7 | ≤ 7 |
| Same, sprinting at 24 | 24 | 7.2 | 0.54 s | 13.0 | ≤ 10.5 |
| AETHER STRIKE run (this repo) | 17.5 | 4.4 | 0.42 s | 7.4 | ≤ 6 |
| AETHER STRIKE walk | 9.5 | 4.4 | 0.42 s | 4.0 | ≤ 3 |

Keep jump-up ledges at least 0.5–1 stud below the apex: players release early and arrive with
imperfect timing. Recompute when `Gravity`, `JumpHeight` or speeds change — never eyeball.

**Body and camera metrics (starting values — verify with an R15 dummy from Studio's Rig Builder):**

| Element | Default avatar game | This repo (FPS) | Why |
|---|---|---|---|
| Character height | ≈ 5–5.5 | head top 5.17 | scale reference for everything |
| Eye height | ≈ 4.5 | 4.7 standing / 3.3 crouched | sightlines and cover |
| Low cover (hides torso) | 2.5–3 | 3.2 | readable "shoot over it" |
| Full cover (hides crouched) | 4 | 4 (standard crate) | choose between "see" and "be seen" |
| Wall that blocks all info | ≥ 7 | ≥ 7 | nothing visible above |
| Door (W × H) | 4 × 7 min, 5–6 × 8 for traffic | 4 × 7 | width for collisions + camera |
| Corridor | ≥ 6 (two players: 8–10) | 8–12 combat lanes | third-person cameras clip in narrow spaces |
| Interior ceiling | 10–14 (third person: ≥ 12) | 10–14 | camera boom + jumping |
| Stairs | visual steps + invisible collision ramp | ramps | smooth movement, no camera jitter |
| Slope | ≤ `CharacterMaxSlopeAngle` minus 10° | max 50° project | climbable without sliding |

The stairs rule is a production habit worth enforcing: model the steps for the eye, set their
`CanCollide = false`, and put one invisible `CanCollide` wedge underneath as the walking surface.

## 2. Blockout

- Build the whole level from untextured primitives at exact metric sizes: neutral materials,
  one colour per function (walkable, cover, out-of-bounds, objective, spawn).
- Snap to 0.5/1/2/4-stud grids; module sizes that are multiples of 4 make kits easy later.
- Name zones and callouts **in the blockout**: they become part names, tags and HUD strings.
- Prefer a declarative description (a blueprint table, a Rojo-synced model, or MCP batches
  per `roblox-building`) over hand-placed parts: it can be regenerated, diffed and tested.

**Reference implementation in this repo:** maps are data. `src/Server/Maps/MapKit.luau` is a
small DSL (`floor`, `wall`, `wallDoor`, `ramp`, `crate`, `cover`, `spawn`, `site`, `callout`,
`zone`, `light`…), `src/Server/Maps/Blueprints/*.luau` describe each map, `MapBuilder.luau`
instantiates them with tags and attributes, `lune run tools/export_maps.luau` +
`python3 tools/render_maps.py` render dimensioned top-down plans to `docs/maps/*.png`, and
`tests/specs/maps.luau` asserts spawn counts, sites, callouts, bounds and **no line of sight
between enemy spawns**. Reuse this pipeline instead of reinventing one.

## 3. Flow and structure

1. **Critical path first.** Draw start → goal. Then the golden path most players will take.
   Optional and secret routes branch off it, never block it.
2. **Three readable routes** for competitive maps (short angles / open duel / long axis),
   joined by a mid that is expensive to hold but gives information and rotations.
3. **Pacing curve.** Alternate tension and rest; teach a mechanic in a safe space, practice it,
   then test it under pressure (sawtooth difficulty, not a straight ramp).
4. **First action within 10–30 s** of spawning in non-competitive games; spawn facing the first
   objective or landmark.
5. **Loops, not dead ends.** Paths return to hubs, shops or objectives; a dead end needs a reward.
6. **Gating with intent.** Locks, abilities, one-way drops and story beats control order; guide
   with light, colour, shape and landmarks before walls or arrows.

## 4. Landmarks, sightlines, cover

- Each zone gets a **silhouette landmark** visible from its entrances (tower, crane, monolith,
  neon sign). Players orient by landmarks, not minimaps.
- **Sightline budget.** Long lines (> 80 studs) belong to one route only; break the others
  with jogs, pillars and elevation. Every long line needs cover at both ends.
- **High ground is never free:** exposed on several faces, reachable by a noisy ramp, or
  counter-able from a flank.
- **Spawns:** no line of sight from enemy spawns or from any sniper position into a spawn
  exit; spawn barriers during preparation; multiple exits. Automate the check (see §2).
- **Cover grammar** must follow the hitbox and eye heights of §1 so "what I can see" equals
  "what can hit me" (in this repo lean and crouch use the same transform for camera and hitbox).
- **Wallbangs and sound** are level-design tools: thin materials create intentional
  penetration; floor materials change footsteps (see `roblox-sound-design`).

## 5. Large worlds, cities and streaming

- **Partition into zones** that load and unload as units: one `Model` (or Folder of Models) per
  district, interior, or set piece. Name them after the zone and tag them.
- `Workspace.StreamingEnabled` on for big maps. Tune `StreamingMinRadius` (always-loaded
  around the player) and `StreamingTargetRadius` (desired) to the longest *meaningful*
  sightline, not the map size; `StreamingIntegrityMode = PauseOutsideLoadedArea` prevents
  walking into unloaded geometry.
- Per model `ModelStreamingMode`: `Atomic` for interactables that must arrive whole (doors,
  vehicles, machines), `Persistent` only for the few things every client always needs
  (it costs memory everywhere), `PersistentPerPlayer` + `Model:AddPersistentPlayer(player)` for
  per-player arenas, `Default`/`Nonatomic` for scenery.
- `Model.LevelOfDetail = StreamingMesh` gives distant skyline buildings a low-cost imposter when
  streamed out — use it on large exterior masses so the skyline survives streaming.
- Client code must tolerate missing instances (tags + `GetInstanceAddedSignal`, never
  `workspace.City.Block12.Door` chains). Before teleporting a player far away, call
  `Player:RequestStreamAroundAsync(position)` on the server.
- **City grid starting values:** major street 2 lanes × 12–14 studs + 8–12-stud sidewalks;
  blocks 120–200 studs on a side; alleys 10–14; building ground floors 14–16 studs tall,
  upper floors 12–14. Inflate public circulation ~1.2–1.5× over real-world scale so cameras
  and crowds fit; keep props near real proportions (see `roblox-props-modeling`).

## 6. Deliverables

**Level brief** (write it before building):
purpose and modes · target session length · metrics table · critical path sketch · zones and
callouts · landmarks · spawn logic · objective placement · streaming partition · budgets
(parts, unique meshes, lights, emitters — see `roblox-render-performance`) · risks.

**Review checklist**
- [ ] Metrics measured from the real controller; every jump/gap tested in play mode.
- [ ] Critical path readable without UI; first action reachable in the target time.
- [ ] Each zone has a landmark and a callout name; no ambiguous names.
- [ ] No line of sight from enemy spawns; spawn exits ≥ 2; barriers during preparation.
- [ ] Long sightlines limited and covered at both ends; high ground has counter-play.
- [ ] Doors, corridors and ceilings fit the camera; no camera clipping in tight rooms.
- [ ] Streaming partition defined; interactables `Atomic`; client code streaming-safe.
- [ ] Out-of-bounds sealed (invisible walls only where unavoidable, `FallenPartsDestroyHeight`).
- [ ] Playtested at the intended player count and on mobile.

For MCP-driven layout work, measurements and evidence: `roblox-studio-mcp` and
`roblox-building`. Reference layouts with full write-ups: `docs/05-level-design.md`.
