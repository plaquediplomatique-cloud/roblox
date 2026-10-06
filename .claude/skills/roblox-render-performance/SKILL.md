---
name: roblox-render-performance
description: Rendering and asset performance for Roblox scenes — what actually costs on the client (unique meshes and textures, part counts, unions, transparency overdraw, shadow-casting lights, particles, world GUIs, collision fidelity, Touched parts, streaming), budgets per area for mobile and desktop, LOD and streaming settings, and the SceneAudit tool that measures a place or model in Studio or from a .rbxl/.rbxm file. Use whenever a scene, map, VFX pass or art pass might cost FPS or memory, before and after visual improvements, or when the user mentions optimisation des meshes, textures, draw calls, particules, lighting, mémoire, streaming, FPS on mobile, even if they only ask to "check performance".
---

# Roblox Render and Asset Performance

Beautiful and fast is a budgeting problem: decide what each area may cost, measure, and spend
where players look. **Measure before and after every visual pass.**

**Boundaries.** Script cost, Luau hot paths, memory leaks, network, profilers (MicroProfiler,
Script Profiler, Developer Console) and Parallel Luau → `roblox-performance`. This skill
covers what the scene itself costs. Lighting design trade-offs → `roblox-lighting-art`.

## 1. What costs, and the cheaper alternative

| Cost driver | Why it costs | Cheaper alternative |
|---|---|---|
| Many unique meshes / unions | each unique geometry is its own draw and memory; unions never share geometry | a modular kit of reused MeshParts; unions only for one-off architecture |
| Thousands of tiny parts | per-part overhead (render, physics broadphase, streaming) | merge repeated detail into a mesh; drop invisible detail |
| Unique textures | download + GPU memory on every client | shared texture sets, built-in materials, `SurfaceAppearance.Color` tinting |
| Transparency (glass, fades, alpha decals) | overdraw and sorting | opaque surfaces, `Neon` for glow, transparency only where seen through |
| Shadow-casting lights | shadow maps re-rendered | `Shadows = false` on fill/bounce lights, small `Range` |
| Small parts casting shadows | shadow-map work for invisible gain | `CastShadow = false` for parts ≤ 1 stud and interior clutter |
| Particles | count × size × overdraw | `Rate × Lifetime.Max` budget, `Emit` bursts, smaller sizes, fewer textures |
| `SurfaceGui` / `BillboardGui` everywhere | per-GUI render cost | `MaxDistance`, fewer always-on GUIs, decals for static signage |
| `PreciseConvexDecomposition` collisions | physics cost and memory | `Box`/`Hull`, or invisible box colliders |
| `CanTouch = true` on scenery | touch pairs evaluated in physics | `CanTouch = false` unless a `Touched` handler needs it |
| Unanchored scenery | physics simulation and network ownership | anchor static parts |
| Humanoids on props/NPC crowds | expensive state machine per humanoid | `AnimationController` for animated props |
| No streaming on large maps | everything loaded on every device | StreamingEnabled with per-zone models (see `roblox-level-design`) |

Additional levers: `MeshPart.RenderFidelity` (`Automatic` lets distant meshes drop detail,
`Performance` for background props), `Model.LevelOfDetail = StreamingMesh` for skyline masses,
`CanQuery = false` on clutter to speed up raycasts.

## 2. Budgets

`scripts/SceneAudit.luau` ships starting budgets per streamed area (`SceneAudit.budgets.Mobile`
and `.Desktop`): BaseParts, unique meshes/textures, transparent parts, lights and shadowed
lights, particle budget, small shadow casters, unanchored/CanTouch parts, precise collisions,
unions, world GUIs. They are review triggers, not engine limits: tune them after measuring the
project on its real target devices.

## 3. Measure

**In Studio** (command bar, MCP `execute_luau`, or a plugin), with `SceneAudit.luau` in a
ModuleScript:

```lua
local SceneAudit = require(game:GetService("ServerStorage").SceneAudit)
print(SceneAudit.format(SceneAudit.run(workspace.Map.Downtown, SceneAudit.budgets.Mobile)))
```

**From files** (Lune, no Studio needed):

```text
lune run .claude/skills/roblox-render-performance/scripts/audit_file.luau build/props/PropKit_Showroom.rbxm
lune run .claude/skills/roblox-render-performance/scripts/audit_file.luau MyPlace.rbxl Desktop Workspace.Map
```

The report lists counts per category, the top materials, and one line per exceeded budget with
the recommended fix. Pair it with frame-time measurements (MicroProfiler render bands, FPS on a
real phone) described in `roblox-performance`: counts tell you *what* could cost, profiles tell
you *what does*.

In this repository maps are built at runtime by `src/Server/Maps/MapBuilder.luau`, so audit a
built map (Studio playtest, or a Lune build of the blueprints) rather than the empty
`build/AetherStrike.rbxl`.

## 4. Workflow for any visual pass

1. Audit the area and record the baseline (and FPS on the weakest target device).
2. Do the pass in small batches.
3. Re-audit; any exceeded budget needs a fix or an explicit decision.
4. Spend budget where the player looks (critical path, combat spaces); be frugal elsewhere.
5. Re-test on mobile and low graphics quality.

## 5. Review checklist

- [ ] Baseline and after-pass audits recorded for the area.
- [ ] No new budget breaches, or each one accepted explicitly with a reason.
- [ ] Decor non-colliding, non-touching, no tiny shadow casters.
- [ ] Shadowed lights within budget; particle budget within budget.
- [ ] Large maps streamed per zone; interactables `Atomic`.
- [ ] FPS checked on the weakest target device.
