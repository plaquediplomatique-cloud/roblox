---
name: roblox-lighting-art
description: Lighting art direction for Roblox scenes — key/fill/accent design, time of day and sun angle, colour temperature (Kelvin to Color3), warm/cool contrast, interiors lit by motivated practicals and fake bounce lights, exterior moods, fog layering for depth, restrained post-processing, per-zone and day/night blending, shadow and light budgets that stay fast on mobile, plus the LightingRig tool (looks, blending, Kelvin, practical lights). Use whenever the user wants better lighting, shadows, atmosphere, mood, depth, cinematic or realistic light, an interior that looks flat, night scenes, or a day/night cycle (éclairage, ombres, atmosphère, ambiance, brouillard, jour/nuit, post-processing), even if they only say "it looks flat".
---

# Roblox Lighting Art

Lighting decides what players see first. Design it like a cinematographer: **one key, a
controlled fill, deliberate accents, and darkness where you want it** — then make it cheap.

**Boundaries.** Property reference, mood presets and engine options (including the newer
`Lighting.LightingStyle` / `PrioritizeLightingQuality` that supersede `Technology`) →
`roblox-lighting`. Light response of surfaces → `roblox-materials-textures`. Costs →
`roblox-render-performance`. Scene composition → `roblox-environment-art`.

## 1. Method (per zone)

1. **Intent:** one sentence — time, weather, emotion ("cold dawn after rain, hope at the end
   of the street").
2. **Key light:** the sun or moon. `ClockTime` sets elevation, `GeographicLatitude` the arc.
   Low sun (≈ 7–8 h or 16.5–18 h) gives long shadows and form; noon flattens everything.
3. **Fill:** `Ambient` (inside/shadowed areas) and `OutdoorAmbient` (sky fill outdoors). Never
   black: shadows need a hue (cool blue outdoors at night, warm brown in a lamp-lit room).
4. **Accents:** practical lights the player can see (lamps, signs, screens, windows) placed
   where gameplay or composition needs attention.
5. **Depth:** `Atmosphere` density/haze separates foreground, midground and background; colour
   the far `Decay` toward the sky so silhouettes stack.
6. **Grade last:** `ColorCorrection` for small global shifts only; bloom only on true emitters.
7. **Review** (§6) at player eye height, then measure (§5).

## 2. Colour temperature

Contrast temperature, not just brightness: **warm interiors against cool exteriors** (or the
reverse at noon) is the cheapest way to make a scene look designed.

| Kelvin | Source | Color3.fromRGB |
|---|---|---|
| 1900 | candle, embers | 255, 132, 0 |
| 2200 | sodium street lamp | 255, 146, 39 |
| 2700 | incandescent / warm LED | 255, 167, 87 |
| 3000 | warm white | 255, 177, 110 |
| 3500 | halogen, office warm | 255, 193, 141 |
| 4000 | neutral white | 255, 206, 166 |
| 5000 | cool white, overcast sun | 255, 228, 206 |
| 5500 | noon sun | 255, 237, 222 |
| 6500 | daylight / screens | 255, 254, 250 |
| 7500 | shade, open sky | 230, 235, 255 |
| 9000 | deep blue hour | 210, 223, 255 |

`LightingRig.kelvin(k)` computes any value. Neon and coloured sci-fi lights sit outside this
scale; give each district one signature hue and keep it consistent.

## 3. Interiors

Roblox has no baked global illumination, so interiors look flat unless you design the bounce:

- **Motivate every light:** a lamp, ceiling fixture, screen or window. The emitter part uses
  `Neon` in the light's colour; the light itself (`PointLight`/`SpotLight`) sits inside it.
- **Key practicals cast shadows; everything else does not.** One or two shadowed lights per
  room, the rest `Shadows = false`.
- **Fake bounce:** a large, dim (`Brightness` 0.2–0.5), shadowless `PointLight` with long
  `Range` near bright floors or below windows, tinted by the surface colour, lifts the room
  the way real bounce light would.
- **Windows:** a `SurfaceLight` facing inward on the window frame (cool 6500–7500 K by day,
  warm city spill at night) sells outdoor light entering.
- **Ceilings and corners stay darker** than work surfaces: light pools on tables and counters
  guide the eye and gameplay.
- Typical values: lamp `Brightness` 0.8–1.5, `Range` 10–16; ceiling fixture 1–2, 14–20;
  screen glow 0.3–0.8, 6–10.

## 4. Exteriors, moods and time

- Start from a look (`LightingRig.looks`: `NoonClear`, `GoldenHour`, `Overcast`, `NightCity`,
  or the mood presets in `roblox-lighting`) and tune: sun angle → fill → fog → grade.
- **Night:** the moon is a weak key; streets are lit by practicals in pools with dark gaps
  between them; `Bloom` threshold high so only emitters glow.
- **Fog for depth, not soup:** `Atmosphere.Density` 0.25–0.45 typical; `Haze` adds colour
  scattering near the horizon; `Offset` lifts fog off the ground for silhouettes.
- **Post:** contrast 0.05–0.15; saturation −0.2 … +0.1; `SunRaysEffect` only when the sun is
  on screen; `DepthOfFieldEffect` for menus and cinematics, not for gameplay readability.
- **Per-zone moods:** blend looks on the client when the player changes zone
  (`LightingRig.apply(look, 1.5)`); this repository does the same per map in
  `src/Client/Controllers/LightingController.luau` from profiles in `src/Shared/Config/Maps.luau`.
- **Day/night:** the server owns time (`Lighting.ClockTime`, replicated); move it in
  coarse steps (e.g. every few seconds) and let clients smooth visuals; switch practical
  lights on at dusk with tags, not per-frame loops.

## 5. Performance

- Shadow-casting local lights are the expensive ones: budget ~4–6 visible at once, prefer
  `Shadows = false` and small `Range`.
- `Neon` parts give glow without light cost; use them for distant windows and signs.
- Few post effects (one grade, one bloom, sun rays when relevant); no stacked
  `ColorCorrectionEffect`s fighting each other.
- `CastShadow = false` on small or interior-only parts reduces shadow-map work.
- Test on a phone and at low graphics quality: the scene must still read when shadows and
  fog are reduced. Measure with the tools in `roblox-performance` and the light counts from
  the scene audit in `roblox-render-performance`.

## 6. Review checklist

- [ ] Greyscale screenshot reads: focal points brightest/most contrasted, no muddy mid-grey.
- [ ] Every visible light has a visible source; no unexplained glows.
- [ ] Warm/cool contrast is intentional; each district has its signature hue.
- [ ] No pitch-black playable corners unless designed; enemies stay readable against
      backgrounds (light or dark backing behind common angles).
- [ ] Bloom only on emitters; no blown-out white surfaces.
- [ ] Shadowed lights within budget; checked on mobile / low quality.
