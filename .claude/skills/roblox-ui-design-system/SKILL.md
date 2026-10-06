---
name: roblox-ui-design-system
description: UI/UX design system craft for Roblox — design tokens (colour roles, type scale, spacing grid, radii, elevation, motion), component states, HUD information hierarchy for action and shooter games, feedback timing (hit markers, damage direction, kill confirmation), menu flow and navigation depth, accessibility (contrast, colour-blind safety, text size, GuiService.ReducedMotionEnabled / PreferredTextSize / PreferredTransparency), touch, gamepad and safe areas, plus a contrast checker for theme tokens. Use whenever the user wants a premium, readable, coherent or modern interface, asks about HUD, menus, boutique, inventaire, écrans de fin de match, notifications, lisibilité, responsive mobile/console, accessibilité, or says the UI looks amateur, cluttered or inconsistent.
---

# Roblox UI Design System

A premium interface is a **system**: a few tokens applied everywhere, components with every
state designed, a clear hierarchy, and motion that informs instead of decorating.

**Boundaries.** GUI mechanics (ScreenGui/SurfaceGui/BillboardGui, layouts, scale vs offset,
focus navigation, lifecycle, reactive libraries) → `roblox-gui`. Input bindings →
`roblox-input`. Retention/monetisation screens → `roblox-monetization`, `roblox-growth-design`.
This skill sets the look, hierarchy, feedback and accessibility rules.

## 1. Tokens (one source of truth)

| Token family | Rule |
|---|---|
| Colour roles | background, panel, panel-raised, stroke, text, text-dim, brand, accent, success, warning, danger, ally, enemy. Semantics never change between screens. |
| Type scale | display / heading / body / mono-numbers; 4–6 sizes (e.g. 14, 16, 20, 28, 40, 64 at 1080p). Numbers in a monospace or tabular font so values do not jiggle. |
| Spacing | 4-px grid (4, 8, 12, 16, 24, 32, 48); paddings and gaps only from the grid. |
| Radius / stroke | one radius family (2–6 px for military/tech, 10–16 px for friendly), 1–2 px strokes. |
| Elevation | translucent dark panels + stroke + subtle gradient instead of drop shadows everywhere. |
| Motion | fast 0.1–0.15 s (hover, press), medium 0.2–0.3 s (panels), slow 0.5–0.7 s (screens); `Quad`/`Quint` out for entries, `Back` only for rewards. |

Code reads tokens from a theme module and never hard-codes a colour or font in a screen.

## 2. Component states

Every interactive component needs: default, hover (desktop), pressed, focused (gamepad
selection), selected/active, disabled, loading. Design them before building screens; reuse
one button and one panel component everywhere. Each state change gets a sound from the UI
family (see `roblox-sound-design`).

## 3. HUD hierarchy for action games

- **Centre** (aim zone): crosshair, hit marker, damage numbers if any — nothing else.
- **Near-centre periphery**: low ammo, reload prompt, interaction prompts.
- **Corners**: health/armor (bottom-left), weapon/ammo (bottom-right), round/score/timer
  (top-centre), minimap/radar (top-left), killfeed (top-right).
- Persistent information is small and quiet; transient information is bright and brief.
- Colour carries meaning (ally/enemy/danger) and is always backed by shape or icon.
- Feedback timing: hit marker within the frame of the confirmed hit; damage direction
  indicator 0.6–1.2 s; kill confirmation (sound + marker + feed) within 100 ms of the server
  confirm; low health = vignette + desaturation + audio, not a blinking bar.

## 4. Menus and flow

- Play is reachable in 1 click from the main screen; any feature within 3.
- One primary action per screen, visually dominant; secondary actions quieter.
- Back/close always in the same place; Escape/B closes the top layer.
- Loading and transitions mask latency (skeletons, progress, tips) instead of freezing.
- Reward screens: staged reveal (numbers count up, bars fill, then the reward), skippable.

## 5. Accessibility and platforms

- Contrast: 4.5:1 for body text, 3:1 for large text and icons. Check tokens with
  `python3 .claude/skills/roblox-ui-design-system/scripts/contrast.py <Theme.luau>`.
- Colour-blind safety: never red-vs-green alone; add icons, shapes, outlines. Offer an
  enemy-colour option in competitive games.
- Respect `GuiService.ReducedMotionEnabled` (disable shakes, parallax, large tweens),
  `GuiService.PreferredTextSize` (scale text up) and `GuiService.PreferredTransparency`
  (multiply panel transparency so translucent panels become more opaque when requested).
- Minimum text 14 px at 1080p (larger on phones); touch targets ≥ 44 px; no hover-only info.
- Safe areas: `ScreenGui.ScreenInsets = CoreUISafeInsets` (or `DeviceSafeInsets` for full-
  bleed backgrounds) and test notches; keep critical HUD out of the top bar area
  (`GuiService.TopbarInset`).
- Gamepad: every screen has an entry selection (`GuiService.SelectedObject`), directional
  navigation works, prompts show controller glyphs.
- Text grows 30–40 % when localised: no fixed-width labels for words (see
  `roblox-localization`).

```lua
--!strict
local GuiService = game:GetService("GuiService")

-- Motion and transparency preferences applied by every tween helper and panel.
local function motionScale(): number
	return if GuiService.ReducedMotionEnabled then 0 else 1
end

local function panelTransparency(base: number): number
	return base * GuiService.PreferredTransparency
end

local function textScale(): number
	local size = GuiService.PreferredTextSize
	if size == Enum.PreferredTextSize.Large then
		return 1.15
	elseif size == Enum.PreferredTextSize.Larger then
		return 1.3
	elseif size == Enum.PreferredTextSize.Largest then
		return 1.5
	end
	return 1
end

print(motionScale(), panelTransparency(0.2), textScale())
```

## 6. In this repository

- Tokens: `src/Shared/Config/Theme.luau` (colours, fonts, transparency, tween presets,
  feedback thresholds). Kit: `src/Client/UI/UI.luau` (typed constructors, glass panel,
  premium button, ghost-trail bar, slider, toggle, cycler, responsive `UIScale` from screen
  height × user HUD scale, insets).
- HUD: `src/Client/Controllers/HUDController.luau`; lobby screens in `src/Client/Lobby/`.
- `textFaint` is below 4.5:1 on every background: reserve it for disabled or decorative text.

## 7. Review checklist

- [ ] No hard-coded colours/fonts in screens; tokens only.
- [ ] Every component state designed and audible; gamepad focus visible.
- [ ] HUD centre clean; information hierarchy matches section 3.
- [ ] Contrast script passes for body text; colour never the only signal.
- [ ] ReducedMotion, PreferredTextSize and PreferredTransparency respected.
- [ ] Tested at phone, tablet, 1080p and ultrawide; safe areas respected.
- [ ] Play in one click; every screen closes the same way.
