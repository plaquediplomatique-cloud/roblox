---
name: roblox-materials-textures
description: Materials and textures for Roblox — choosing built-in materials, MaterialService and MaterialVariant (PBR maps, StudsPerTile, MaterialPattern, emissive), SurfaceAppearance on MeshParts, Decal/Texture tiling and PBR decals, colour and roughness ranges for wood, metal, concrete, glass, fabric, stone, breaking up repetition, wear and grime, texture memory budgets. Use whenever the user asks about matériaux, textures, PBR, surfaces, realism of a surface, a "plastic" look, tiling, wear, or material consistency across a game, even if they only say "it looks too plastic" or "make the walls look real".
---

# Roblox Materials and Textures

Surfaces sell realism through **value and roughness first, colour second, texture third**.
A consistent, small material library beats many unique textures — for looks and for memory.

**Boundaries.** Where props and surfaces go → `roblox-environment-art`. Asset construction →
`roblox-props-modeling`. Light response tuning → `roblox-lighting-art`. Memory and draw-call
costs → `roblox-render-performance`.

## 1. The toolbox (verify current properties in Studio; APIs evolve)

| Tool | Applies to | Use for |
|---|---|---|
| Built-in `Enum.Material` | any BasePart, Terrain | the default library: free (no download), consistent, tiled automatically |
| `MaterialVariant` in `MaterialService` | any part (`part.MaterialVariant = "Name"`) or as a base-material override (Material Manager → set as override) | project-specific PBR materials: `BaseMaterial`, colour/normal/roughness/metalness maps (`*Content` properties), `StudsPerTile`, `MaterialPattern` (`Regular` / `Organic` to hide tiling), optional emissive mask/strength/tint |
| `SurfaceAppearance` | MeshParts only (child of the mesh) | unique PBR for hero props on their own UVs; `AlphaMode` (`Overlay`, `Transparency`, `TintMask`), `Color` tint for recolouring one texture set |
| `Texture` | a face of a part | tiled overlays (`StudsPerTileU/V`, `OffsetStudsU/V`): tiles, panels, signage strips |
| `Decal` | a face of a part | one-off images; modern decals also carry PBR maps, `UVOffset`/`UVScale`, `Rotation`, emissive — ideal for grime, stains, cracks, posters |

Built-in materials available today include `Asphalt`, `Basalt`, `Brick`, `Cardboard`,
`Carpet`, `CeramicTiles`, `ClayRoofTiles`, `Cobblestone`, `Concrete`, `CorrodedMetal`,
`DiamondPlate`, `Fabric`, `Foil`, `Glass`, `Granite`, `Ice`, `Leather`, `Limestone`, `Marble`,
`Metal`, `Neon`, `Pavement`, `Pebble`, `Plaster`, `Plastic`, `Rock`, `RoofShingles`, `Rubber`,
`Sand`, `Sandstone`, `Slate`, `SmoothPlastic`, `Snow`, `Wood`, `WoodPlanks` (plus terrain
materials). Check `MaterialService.Use2022Materials` when a place looks older than expected.

## 2. Material library per art bible

Pick 6–10 materials per district/biome, document colour and intent, and use only those.
Starting ranges (RGB; adjust to the palette):

| Family | Material | Colour range | Notes |
|---|---|---|---|
| Painted walls | `Plaster`, `SmoothPlastic` | value 150–220, low saturation | never pure white: max ~235 |
| Raw concrete | `Concrete` | 110–160 grey, slight warm or cool bias | two tones for panels; decals for leaks |
| Brick | `Brick` | 120–160 red-brown, or desaturated | trims in `Concrete`/`Limestone` |
| Wood (furniture) | `Wood` | 90–180 warm | floors: `WoodPlanks`, rotate grain with the room |
| Metal (painted) | `Metal` | dark 30–70 or industrial colours | edges lighter (wear) via thin trim parts |
| Metal (raw/steel) | `Metal`, `DiamondPlate` | 120–170 neutral | `CorrodedMetal` for neglect, sparingly |
| Glass | `Glass` | tinted 150–200 | `Transparency` 0.3–0.6; frames make glass read |
| Fabric | `Fabric`, `Carpet`, `Leather` | mid values, richest saturation of a room | cushions one tone lighter than the frame |
| Stone | `Slate`, `Granite`, `Marble`, `Limestone` | per biome | `Organic` pattern variants to hide repeats |
| Ground | `Asphalt`, `Pavement`, `Cobblestone`, terrain | low value outdoors | kerbs/edges in a different material |
| Light sources | `Neon` | the light's colour | only for emitting surfaces: bulbs, signs, strips |

Rules: large surfaces are desaturated and mid-value; saturation and contrast live on small
accents and gameplay elements; metal never pure black; no two adjacent large surfaces with the
same material *and* colour unless they are the same surface.

## 3. Breaking repetition and adding age

1. **Scale:** set `StudsPerTile` on variants so tiles match real size (bricks ≈ 0.75 × 0.25
   studs per brick at 3 studs/m); avoid obvious 4-stud tiling on large walls.
2. **Pattern:** `MaterialPattern = Organic` for natural surfaces.
3. **Value jitter:** vary `Color` by ±3–6 % value between neighbouring panels.
4. **Layering:** base material + decals (dirt at the floor line, streaks under windows, cracks
   near corners, oil under vehicles) + trims. Wear follows physics and use.
5. **Transitions:** where two ground materials meet, add a kerb, a seam strip or terrain blend
   instead of a hard cut.

## 4. Creating a MaterialVariant from code (prototyping)

Author variants in Studio's Material Manager for production. For tools or tests:

```lua
--!strict
local MaterialService = game:GetService("MaterialService")

local function makeVariant(name: string, base: Enum.Material, studsPerTile: number, color: string?, normal: string?)
	local variant = Instance.new("MaterialVariant")
	variant.Name = name
	variant.BaseMaterial = base
	variant.StudsPerTile = studsPerTile
	variant.MaterialPattern = Enum.MaterialPattern.Organic
	if color then
		variant.ColorMap = color -- an uploaded image asset id ("rbxassetid://…")
	end
	if normal then
		variant.NormalMap = normal
	end
	variant.Parent = MaterialService
	return variant
end

local concrete = makeVariant("Concrete_Weathered", Enum.Material.Concrete, 12)
local wall = Instance.new("Part")
wall.Material = Enum.Material.Concrete
wall.MaterialVariant = concrete.Name
```

## 5. Budgets

- Prefer built-in materials and a few variants: every unique texture costs download time and
  memory on every client, mobile first.
- Texture sizes: hero props 1024², standard props 512², small or distant 256². Reuse one
  texture set across variants with `SurfaceAppearance.Color` tinting instead of new textures.
- Transparent surfaces (`Glass`, `Transparency` > 0, alpha decals) cost overdraw; keep them
  to windows and effects, not stacked layers.
- Count unique textures, decals and variants per area with the scene audit in
  `roblox-render-performance` before and after a material pass.

## 6. Review checklist

- [ ] Every surface uses a library material; no default grey/unfinished parts in shipped areas.
- [ ] Values read correctly in greyscale; saturation reserved for accents.
- [ ] Tiling scale plausible; no visible repetition within one screen.
- [ ] Wear/grime decals placed where use and weather would put them.
- [ ] Glass framed; Neon only on light sources.
- [ ] Unique texture count within budget.
