---
name: roblox-technical-director
description: Technical direction for a whole Roblox project — routes any request to the right specialist skills (gameplay, Luau, level design, environment, props, lighting, materials, animation/feel, UI/UX, audio, performance, security, data, publishing), runs the change protocol (understand, goal, dependencies, risks, change, verify, optimise), applies the P0–P5 priority order, enforces quality gates and the definition of done, and explains how to run the project in Studio with Rojo. Use at the start of any broad request such as "improve my game", "refonte", "audit the project", "make it AAA", "plan the next steps", for multi-domain work, or when unsure which skill applies.
---

# Roblox Technical Director

You lead a full Roblox team made of skills. Your job: pick the right specialists, keep the
project coherent, and refuse to ship anything unverified.

## 1. Team roster (role → skills to load)

| Role | Primary skills | Supporting |
|---|---|---|
| Technical director | `roblox-technical-director`, `roblox-architecture` | `roblox-review`, `roblox-testing`, `roblox-publish-checklist` |
| Gameplay programmer | `roblox-gameplay-systems` | `roblox-networking`, `roblox-security`, `roblox-npc-ai`, `roblox-physics`, `roblox-input` |
| Luau developer | `roblox-luau-core`, `roblox-luau-patterns`, `roblox-luau-types` | `roblox-new-system`, `roblox-tooling` |
| Data / backend | `roblox-data`, `roblox-server-data` | `roblox-cloud`, `roblox-security` |
| Level designer | `roblox-level-design` | `roblox-game-design`, `roblox-building` |
| Environment artist | `roblox-environment-art` | `roblox-building`, `roblox-materials-textures` |
| 3D / prop artist | `roblox-props-modeling` | `roblox-building`, `roblox-materials-textures` |
| Lighting artist | `roblox-lighting-art` | `roblox-lighting` |
| Technical artist | `roblox-materials-textures`, `roblox-render-performance` | `roblox-animation-vfx` |
| Animator / feel | `roblox-movement-feel` | `roblox-animation-vfx`, `roblox-camera`, `roblox-input` |
| UI/UX designer | `roblox-ui-design-system` | `roblox-gui`, `roblox-localization`, `roblox-input` |
| Sound designer | `roblox-sound-design` | `roblox-audio` |
| Performance engineer | `roblox-render-performance`, `roblox-performance` | `roblox-networking` |
| Game designer / producer | `roblox-game-design`, `roblox-player-psychology` | `roblox-monetization`, `roblox-growth-design`, `roblox-analytics` |
| Studio operator | `roblox-studio-mcp` | `roblox-collaboration-mode`, `roblox-tooling` |

Load only what the task needs; a request touching three domains loads three primaries.
The `roblox-reviewer` agent (`.claude/agents/roblox-reviewer.md`) gives an independent review.

## 2. Change protocol (every significant change)

1. **Understand** the existing system: read the code and its docs before proposing anything.
2. **Goal**: state what the change must improve and how it will be measured.
3. **Dependencies**: who requires it, which remotes/data/config it touches
   (`python3 tools/require_graph.py` maps requires in this repository).
4. **Risks**: what can break (saves, networking, competitive fairness, performance, mobile).
5. **Change** in small steps; keep working systems — refactor only with a concrete gain, never
   for taste.
6. **Verify** with the quality gates below; play-test in Studio when behaviour changed.
7. **Optimise** if the measurement says so (SceneAudit, profilers), not by reflex.

## 3. Priorities

P0 critical (bugs, errors, security holes, broken systems, major performance problems) →
P1 gameplay (combat, weapons, movement, feel) → P2 world (maps, level design, dressing) →
P3 visual (lighting, materials, VFX) → P4 immersion (audio, ambience, weather) → P5 polish.
Never start a lower priority while a higher one is known broken.

## 4. Pipelines

**Feature**: design note (goal, rules, data, remotes) → pure rules + tests → server service →
client feedback → review (`roblox-review`) → docs.

**Map / area**: metrics and flow (`roblox-level-design`) → blockout and play-test →
architecture pass (`roblox-building`) → dressing passes (`roblox-environment-art`, PropKit) →
materials (`roblox-materials-textures`) → lighting (`roblox-lighting-art`) → audio zones
(`roblox-sound-design`) → SceneAudit before/after (`roblox-render-performance`) → play-test.

**Visual pass**: baseline screenshots + SceneAudit → change → same shots + audit → keep only
what is better at equal or acceptable cost.

## 5. Quality gates (this repository)

```text
stylua src tests tools .claude/skills          # format (run twice if it changes files)
./scripts/analyze.sh                           # luau-lsp strict, 0 errors/warnings
./scripts/test.sh                              # Lune unit tests (pure rules, maps)
./scripts/build.sh                             # Rojo build → build/AetherStrike.rbxl
python3 tools/require_graph.py                 # require cycles / unresolved requires
python3 tools/doc_excerpts.py --check          # docs code excerpts up to date
python3 tools/check_skills.py                  # skills: frontmatter, links, snippets type-check
lune run .claude/skills/roblox-props-modeling/scripts/test_propkit.luau
lune run .claude/skills/roblox-sound-design/scripts/test_soundscape.luau
lune run .claude/skills/roblox-gameplay-systems/scripts/test_interactable.luau
```

Visual work adds: SceneAudit report before/after, and screenshots or map renders
(`tools/export_maps.luau`, `tools/render_maps.py`).

## 6. Definition of done

- [ ] All quality gates green; no new warnings.
- [ ] Behaviour verified in Studio (Test → Clients and Servers for multiplayer logic).
- [ ] Server authority and validation intact (`roblox-security` checklist for new remotes).
- [ ] Performance measured for visual or per-frame changes.
- [ ] Docs and comments updated where behaviour changed; commit message explains why.

## 7. Running the project in Studio with Rojo

1. Install the toolchain: `rokit install` (reads `rokit.toml`: rojo, luau-lsp, stylua, lune).
2. Install the Studio plugin once: `rojo plugin install`.
3. Either build a place file: `rojo build default.project.json -o build/AetherStrike.rbxl` and
   open it in Studio; or live-sync: `rojo serve` (port 34872), then in Studio
   *Plugins → Rojo → Connect* and accept the changes.
4. Play: *Test → Play* for one player, *Test → Clients and Servers* (2–6 players) for
   matchmaking and matches. DataStores need *Game Settings → Security → Enable Studio Access to
   API Services* (otherwise the game uses its in-memory fallback).
5. For live scene work through an AI agent, connect Studio's MCP server (`roblox-studio-mcp`).
