---
name: roblox-environment-art
description: Environment art direction for Roblox — art bible, palette and value structure, composition, set dressing density, edge and surface detailing, environmental storytelling, cities and streets, building facades, interiors (living rooms, kitchens, bedrooms, offices, shops), exteriors and nature, and the concrete fixes that stop a place from looking like a "basic Roblox map". Use whenever the user wants a place, scene, district, interior or map to look professional, realistic, cinematic, cohesive or memorable (direction artistique, décor, habillage, environnement réaliste, ville, rue, intérieur, storytelling), even when they only say "make it look better".
---

# Roblox Environment Art

Players read an environment in this order: **value (light/dark masses) → silhouette → colour →
material → detail**. Most "basic Roblox map" problems are fixed at the first two levels, not by
adding props. Work top-down and keep every addition answerable to the art bible.

**Boundaries.** Layout and metrics → `roblox-level-design` (finish it first). Prop/furniture
specs and the PropKit generator → `roblox-props-modeling`. Materials, PBR and textures →
`roblox-materials-textures`. Light design → `roblox-lighting-art` (API: `roblox-lighting`).
Budgets → `roblox-render-performance`.

## 1. Art bible (one page, before any dressing)

- **Three pillars** (e.g. "cold, premium, lived-in"). Every asset must serve at least one.
- **References:** 6–12 images per zone covering mood, materials, and one interior.
- **Palette:** values first — assign each zone a dominant value (dark / mid / light) and keep
  60 % dominant, 30 % secondary, 10 % accent. Reserve the most saturated accent for gameplay
  (objectives, interactables, team colours) so the world never competes with it.
- **Material library:** a short list (6–10) per biome or district, each with colour range and
  roughness intent (see `roblox-materials-textures`). Unlisted materials need a reason.
- **Shape language:** e.g. hard bevels + vertical slits for sci-fi, rounded masses for
  cartoon, layered horizontal bands for brutalist. Apply it to buildings, props and UI alike.
- **Lighting intent** per zone (time, key direction, warm/cool split).

## 2. What makes a Roblox map look basic — and the fix

| Symptom | Fix |
|---|---|
| Big flat walls of one colour and material | Break into **base / body / cap** bands; add pilasters every 8–16 studs, panel seams, window rhythms; 2–3 related materials per facade |
| Edges are razor sharp everywhere | Add trims that catch light: baseboards, cornices, door/window casings, curbs and ledges 0.2–0.5 stud proud of the surface; chamfer key edges with WedgeParts or meshes |
| Everything sits on a single flat ground plane | Layer the ground: kerbs, gutters, manholes, cracks (decals), puddles, material transitions, Terrain blending at the edges of paved areas |
| Props float, intersect badly or face random directions | Ground every prop; align to walls and grids; rotate only with intent (a chair pulled out *toward* the table) |
| Uniform density (or empty rooms next to cluttered ones) | Density follows human use: high at interaction points (desks, counters, doors), low in circulation; empty space is a design decision |
| Scale drift (giant doors, tiny chairs) | Check every room with an R15 dummy; furniture near real proportions, circulation inflated (see level design metrics) |
| Default SmoothPlastic grey and pure saturated colours | No unfinished default surfaces in shipped areas; desaturate large surfaces, keep saturation for accents |
| Flat lighting | Motivate light sources, contrast warm interiors with cool exteriors, add shadowing masses (see `roblox-lighting-art`) |
| Skyline is a flat box line | Vary roofline heights, setbacks, antennas, water tanks, signage; put a landmark on the skyline of each zone |
| Repetition is obvious | Mirror/rotate modules, swap 2–3 variants, change colour by ±3–6 % value, add unique hero details at eye level |

## 3. Composition

- **Frame the player's view**, not the editor camera. Review every area from the player's
  eye height (≈ 4.5–4.7 studs) along the critical path, at spawn, and at each reveal.
- **Focal points** at path ends and corridor exits: a lit sign, a landmark, an objective.
- **Leading lines:** kerbs, cables, light rows, floor markings that point toward goals.
- **Foreground / midground / background:** every important view needs all three layers;
  atmosphere (fog) separates them (see `roblox-lighting-art`).
- **Reveal moments:** compress (low ceiling, narrow) then release (open vista) before key spaces.
- **Rule of thirds and silhouette:** landmarks read as clean silhouettes against a lighter or
  darker background — check by squinting at a screen capture.

## 4. Set dressing method

Dress in passes, each reviewed before the next:

1. **Kit pass** — modular walls, floors, trims replacing blockout pieces (same footprint).
2. **Hero pass** — one or two unique assets per space that define it (a bar counter, a
   reactor, a fountain). Place them where the composition points.
3. **Secondary pass** — furniture and large props that support the function of the space.
4. **Clutter pass** — small props clustered in groups of 3–5 with size variety (one large,
   one medium, a few small) at interaction points. Never sprinkle evenly.
5. **Surface pass** — decals for wear, stains, posters, signage, floor markings; edge wear on
   high-traffic corners.
6. **Life pass** — motion and sound: fans, flickering signs, steam, swaying cables, ambient
   emitters (see `roblox-sound-design`).

**Environmental storytelling:** decide *who uses this space and what just happened*, then
leave evidence: a half-eaten meal, chairs pushed back in a hurry, a barricade of desks,
footprints in dust, a light left on. One clear story per room beats ten random props.

## 5. Recipes

**Street (per 100 studs of frontage):** sidewalk with kerb and gutter · 3–4 street lamps on a
regular rhythm · 1–2 bins, 1 bench, 1 hydrant or utility box · signage at corners · trees or
planters every 16–24 studs · crosswalk markings at intersections · manholes and cracks as
decals · parked vehicles in groups · overhead cables or signs for vertical interest.

**Facade (base / body / cap):** ground floor = transparency and activity (storefronts, doors,
awnings, signs, lit windows); body = rhythm (repeated windows with sills and frames, balconies,
AC units, variation every 2–3 bays); cap = cornice, parapet, roof clutter (vents, tanks,
antennas). Corners get the richest detail; that is where players look.

**Living room:** sofa facing a focal wall (TV or fireplace) with 3–4 studs of walkway around
it · coffee table at knee distance · rug anchoring the group · side table + lamp per seat
end · wall art at eye height · bookshelf or plants to break walls · one window with curtains ·
warm practical lights (see `roblox-lighting-art`).

**Kitchen:** work triangle sink–stove–fridge, each leg 4–9 studs · continuous worktop with
upper cabinets above · backsplash material change · small appliances clustered near outlets ·
pendant or strip light over work areas · fruit bowl, kettle, cutting board as clutter.

**Bedroom:** bed head against a wall, nightstands both sides, walkway on at least two sides ·
wardrobe/dresser on the wall opposite the window · rug under the lower two thirds of the bed ·
reading lamp per nightstand · personal items that tell who lives there.

**Office / shop:** desks in clusters with cable trays and monitors · reception or counter
facing the entrance · signage and branding consistent with the district palette · back-room
door slightly open for depth.

**Nature edge:** Terrain for ground masses; rocks in clusters (one big anchor, two medium,
scatter of small), partially buried; vegetation densest at path edges and thinning outward;
paths follow terrain contours.

## 6. Review

Capture the same 4–6 views (spawn, two path midpoints, each reveal, one interior) at day and
night, at player height, before and after each pass (MCP `screen_capture` where available — see
`roblox-studio-mcp`). Critique with this checklist:

- [ ] Value structure reads in greyscale; focal points are the lightest or most contrasting.
- [ ] Every zone has a landmark, a palette and a story.
- [ ] Interactables and gameplay accents are louder than decoration.
- [ ] No default/unfinished surfaces, floating props or z-fighting in shipped areas.
- [ ] Repetition broken within one screen of view.
- [ ] Density matches use; circulation stays clear (≥ level-design widths).
- [ ] Budgets respected (`roblox-render-performance` audit run on the area).
