---
name: roblox-props-modeling
description: Props, furniture, buildings and vehicles for Roblox — real-world-to-stud dimensions, part-built vs mesh vs CSG decisions, detailing tricks that read as high quality, modular building kits, collision proxies, pivots and naming, asset organisation, and the PropKit generator (tables, chairs, sofas, beds, bookshelves, kitchens, lamps, doors) that builds props in Studio or exports .rbxm files. Use whenever the user wants to create, detail, furnish or organise 3D assets (meubles, mobilier, maisons, bâtiments, véhicules, objets décoratifs, accessoires, props, intérieurs détaillés, cuisine, salon, chambre), even if they just say "add some furniture".
---

# Roblox Props, Furniture and Buildings

A prop is good when it has **correct scale, a readable silhouette, believable construction
(edges, gaps, materials), clean collision, and a consistent pivot**. Polygons come last.

**Boundaries.** Placement in the scene and density → `roblox-environment-art`. Materials, PBR
maps and textures → `roblox-materials-textures`. Geometry mechanics in Studio/MCP (CSG epsilon,
batches, readback) → `roblox-building`. Physics vehicles and moving doors → `roblox-physics`
and `roblox-movement-feel`. Costs → `roblox-render-performance`.

## 1. Scale

Design scale: **≈ 3 studs per metre for anything the player looks at, seat height 1.5**
(matches `roblox-building`'s player-scale table). Inflate *circulation* (doors, corridors,
stairs, ceilings) 1.2–1.5× for cameras and crowds; do not inflate furniture.
Always verify with an R15 dummy (Studio → Avatar → Rig Builder) standing and sitting.

| Item | W × D × H (studs) | Notes |
|---|---|---|
| Dining table | 6 × 3.6 × 2.5 | 4 chairs; 2.4–3 studs clearance behind chairs |
| Coffee table | 3.6 × 2 × 1.3 | knee distance (≈ 1.5) from the sofa |
| Desk | 4.5 × 2.4 × 2.5 | monitor top ≈ eye level when seated |
| Chair | 1.6 × 1.6 × 3.2 | seat 1.5; armchair 2.6 wide |
| Sofa (3 seats) | 6.6 × 2.9 × 2.6 | seat 1.4, arm 2.0 |
| Bed single / double | 3 / 4.8 × 6.6 | mattress top 1.5–1.6, headboard 3.2 |
| Nightstand | 1.5 × 1.4 × 1.8 | top just above mattress |
| Wardrobe | 3–4.5 × 1.8 × 6.6 | full height to door head |
| Bookshelf | 3.2 × 1.1 × 6 | 5 shelves |
| Kitchen worktop | depth 2 × height 3 | upper cabinets 1.1 deep, top at 6.6 |
| Service / bar counter | height 3.5–4 | this is the "counter 3.5–4" of `roblox-building` |
| Fridge | 2.1 × 2.1 × 5.4 | |
| Floor / table lamp | 5.4 tall / 1.6 tall | PointLight inside the shade |
| Interior door (opening) | 4 × 7 | casing 0.3; handle at 3.2 |
| Window sill height | 2.6–3 | head at door-head height |
| Stair step | rise 0.5–0.75, run ≥ 1 | visual only; walk on an invisible ramp |
| Car (compact) | 6 × 13 × 4.5 | wheels ≈ 2 diameter; SUV/van 7 × 15 × 6 |

## 2. Choose the construction method

| Method | Use for | Watch out |
|---|---|---|
| **Parts** (kit-bash) | blockout, furniture, architecture trims, anything you will edit often | part count — merge to a mesh once it exceeds ~30 parts and repeats a lot |
| **MeshPart** (Blender → Importer) | curved or organic shapes, hero props, repeated props (instances share one mesh) | budget triangles per asset class; set `CollisionFidelity`, `RenderFidelity` deliberately |
| **CSG** (Union/Negate) | one-off boolean cuts in architecture (window holes, arches) | each union is unique geometry — no reuse; collision can be poor; never at runtime in loops |
| **Creator Store asset** | quick filler | inspect for scripts, licence, triangle counts and style mismatch before inserting |
| **Studio generation** (MCP `generate_mesh`, `generate_procedural_model`) | concept props, variations | review scale, collision and style like any external asset |

## 3. Detailing that reads as quality

- **Edges catch light.** Add a chamfer illusion (a 0.06-stud darker slab inset under a top,
  WedgeParts on visible corners) or real bevels in meshes. Razor-sharp boxes read as blockout.
- **Gaps and seams** of 0.03–0.05 studs between cushions, drawers and doors; handles proud of
  the surface by 0.05–0.1.
- **Taper and steps:** legs in two segments, plinths and kick plates recessed, cornices
  stepping out. Silhouette changes every 0.5–1 stud on hero props.
- **Material contrast within one prop:** wood + metal + fabric, or two tones of the same
  material (±10 % value).
- **No z-fighting:** never coplanar faces with different colours; offset overlays by ≥ 0.01.
- **Wear where hands go:** darker edges on handles and corners, scuffs on floors in front of
  furniture (decals, see `roblox-materials-textures`).

## 4. Collision, pivot, naming, organisation

- Visual parts: `Anchored = true`, `CanCollide = false`, `CanTouch = false`; `CastShadow`
  off for parts ≤ 1 stud; `CanQuery = false` for tiny clutter (raycasts get cheaper).
- Collision: one or two invisible box parts named `Collider` (`Transparency = 1`,
  `CanCollide = true`). Meshes use `CollisionFidelity = Box` for decor, `Hull` for props
  players bump into, `PreciseConvexDecomposition` only when the shape truly matters.
- **Pivot** at bottom-centre of the footprint, front facing −Z (the pivot's `LookVector`),
  so `model:PivotTo(CFrame.new(position) * CFrame.Angles(0, yaw, 0))` works for every prop.
- Names: `Category_Object_Variant` for assets (`Furniture_Chair_OakA`), semantic part names
  inside (`Seat`, `BackRest`, `Leg`, `Collider`, `Leaf`). Attributes for metadata
  (`PropKit`, `Footprint`), CollectionService tags for behaviour (`Sittable`, `Interactable`).
- Store reusable props as **Packages** (auto-update everywhere) or in a dedicated
  `ServerStorage/Assets` (server-cloned) / `ReplicatedStorage/Assets` (client-cloned) folder.
- **Modular kits:** wall modules on a 4-stud grid (4, 8, 16 wide; height = floor-to-floor),
  pivots on grid corners, trims as separate pieces, 2–3 variants per module to break repetition.
- **Vehicles:** a static parked car is one anchored Model (body, glass, wheels, lights);
  a driveable one is a physics assembly (`VehicleSeat`, constraints) — see `roblox-physics`.

## 5. PropKit — generate furniture now

`scripts/PropKit.luau` builds detailed, collision-clean props from Parts with the conventions
above. Builders: `diningTable`, `chair` (`sittable = true` adds a Seat), `sofa`, `bed`,
`bookshelf` (seeded books), `kitchenCounter` (`upper = true` adds cabinets + backsplash),
`floorLamp` (warm PointLight, shadows off by default), `door` (separate `Leaf` part with a
`HingeSide` attribute). Styles: `Oak`, `Walnut`, `Modern` — add your own `Style` table to
match the art bible.

**In Studio** (command bar, MCP `execute_luau`, or a plugin): put `PropKit.luau` in a
ModuleScript, then

```lua
local PropKit = require(game:GetService("ServerStorage").PropKit)
local sofa = PropKit.sofa({ style = PropKit.styles.Walnut, seats = 3 })
sofa:PivotTo(CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(180), 0))
sofa.Parent = workspace
```

**Without Studio** (Lune):

```text
lune run .claude/skills/roblox-props-modeling/scripts/test_propkit.luau    # 2 000+ checks
lune run .claude/skills/roblox-props-modeling/scripts/export_props.luau    # → build/props/*.rbxm
```

Drag a `.rbxm` from `build/props/` into Studio's Explorer to use the props directly.
Extend PropKit with new builders following the same contract, then add them to
`PropKit.builders` so the test covers them automatically.

## 6. Review checklist

- [ ] Checked against an R15 dummy (standing, sitting, walking past).
- [ ] Silhouette readable at 30 studs; edges/gaps/material contrast present.
- [ ] Pivot bottom-centre, front −Z; named parts; attributes set.
- [ ] Collision through simple colliders; visual parts non-colliding; tiny parts no shadow.
- [ ] Reused via Package/asset folder rather than copy-pasted variants.
- [ ] Counted in the area's budget (`roblox-render-performance`).
