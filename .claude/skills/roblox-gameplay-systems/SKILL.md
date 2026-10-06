---
name: roblox-gameplay-systems
description: Gameplay systems design and implementation patterns for Roblox — server-authoritative combat (hit validation, lag compensation, damage model), inventory and equipment, interactable objects (doors, switches, terminals, pickups) on ProximityPrompt with server validation, quests/missions and progression driven by an event bus, economy sinks and sources, NPC behaviour hooks, and in-game debug tools; ships InteractableKit (server-validated interactables with replicated state and client hinge animation). Use whenever the user adds or reworks a gameplay feature — combat, armes, inventaire, quêtes, missions, progression, interactions avec des objets, portes, coffres, terminaux, PNJ, outils de debug — even if they only describe the feature they want.
---

# Roblox Gameplay Systems

A gameplay system is good when it is **fun, authoritative, observable and decoupled**: the
server decides, clients predict and present, systems talk through events, and every rule can
be tested without a running game.

**Boundaries.** Where code lives and startup → `roblox-architecture`; remotes and
replication → `roblox-networking`; exploits → `roblox-security`; saving → `roblox-data` /
`roblox-server-data`; NPC pathfinding and perception → `roblox-npc-ai`; loops, pacing and
economy theory → `roblox-game-design`. This skill gives the system recipes.

## 1. Universal shape

1. **Pure rules module** (Shared): numbers in, decision out, no Instances. Unit-tested.
2. **Server service**: owns state, validates every client request (types, ranges, rate,
   ownership, distance, cooldown, game phase), applies rules, publishes events.
3. **Replication**: state the client needs as attributes, replicated tables or remote
   deltas — read-only on the client.
4. **Client controller**: input → request; immediate local prediction/feedback; reconcile with
   the server's answer.
5. **Event bus** between systems (kill → missions, stats, feed, audio) so features plug in
   without touching each other.

## 2. Recipes

**Combat (hitscan).** Client sends origin, direction, timestamp, weapon state; server checks
fire rate, ammo, alive, origin near the rewound character, spread seed/pattern, then raycasts
against hitboxes rewound to the shooter's view time (bounded rewind, interpolation delay). Damage
model: base × zone multiplier × distance fall-off × penetration; armor absorbs a share. Kill
credit with assists by recent damage. Client: instant tracers/impacts, server-confirmed hit
markers and kill feed.

**Inventory and equipment.** Server validates ownership and slot compatibility; equipment is a
pure function of the profile; currency changes go through one function that logs a reason;
no client-chosen prices or rewards.

**Interactables (doors, switches, lockers, terminals, pickups).** ProximityPrompt is the UI,
the server is the authority: re-check alive, distance (+ latency margin), cooldown, custom
conditions (key owned, team, phase), then change a replicated `State` attribute; clients animate
from it and late joiners snap to it. Collision and raycast blocking follow the server state.
Use `scripts/InteractableKit.luau`:

```lua
-- Server
InteractableKit.register({
	tag = "Door", states = { "Closed", "Open" }, initial = "Closed", objectText = "Door",
	actionText = function(state) return if state == "Open" then "Close" else "Open" end,
	transition = function(context) return if context.state == "Open" then "Closed" else "Open" end,
})
-- Client
InteractableKit.bindVisual("Door", InteractableKit.hingeVisual({
	parts = { "Leaf", "Handle" }, openStates = { "Open" }, angle = 100,
}))
```

It works out of the box with `PropKit.door` from `roblox-props-modeling` (hinge side read from
the leaf's `HingeSide` attribute). Tests:
`lune run .claude/skills/roblox-gameplay-systems/scripts/test_interactable.luau`.

**Quests / missions.** Definitions as data (id, event, filter, target, reward); assignment
deterministic per player and period (seeded by UserId + day) so it is identical on every server
and not farmable by rejoining; progress from the event bus; explicit claim; rerolls limited.

**Progression.** XP curve as a formula (`base × level^exponent`, exponent 1.3–1.6) with a cap
and milestone rewards; reward the behaviours you want (objectives, assists), not only kills;
show a staged post-match summary.

**NPCs.** Behaviour as a small state machine (idle → patrol → alert → engage → search), updates
at 5–10 Hz, not per frame; same hitboxes and damage rules as players; see `roblox-npc-ai`.

**Debug tools.** An admin-gated (allowlist of UserIds, server-checked) panel or chat
commands: give/reset currency, spawn bots, skip phase, toggle hitbox/raycast visualisation,
print state. Visual debugging with Adornments/Highlights on the client only. Never ship a
remote that trusts a client flag for admin.

## 3. In this repository (reference implementations)

| System | Files |
|---|---|
| Event bus | `src/Server/GameEvents.luau` (Kill, Damage, RoundEnd, MatchEnd, Objective, ShotFired…) |
| Remote safety | `src/Server/Net/ServerNet.luau` (rate limit → Guard schema → protected call), `src/Shared/Util/Guard.luau` |
| Combat | `src/Server/Services/CombatService.luau` (13 checks), `LagCompensationService.luau`, `src/Shared/Combat/*` (ballistics, hitboxes, spread, spread audit, stances) |
| Inventory / economy | `InventoryService.luau`, `StoreService.luau`, `PurchaseService.luau` |
| Missions / progression | `MissionService.luau`, `ProgressionService.luau`, `src/Shared/Config/Missions.luau`, `Progression.luau` |
| Match flow | `src/Server/Match/MatchInstance.luau` + pure rules `src/Shared/Rules/MatchRules.luau` |
| Bots | `TrainingRangeService.luau` (static and moving bots, same hitboxes/lag compensation) |
| Interactions | hub terminals: `src/Server/Maps/MapBuilder.luau` (prompts), `src/Client/Lobby/HubWorld.luau` |

New features follow the same pattern: config/rules in `src/Shared`, a server service validating
through `ServerNet`, events on `GameEvents`, a client controller for feedback, tests in
`tests/specs`. Use `roblox-new-system` to scaffold and `roblox-review` before committing.

## 4. Review checklist

- [ ] Every client request validated on the server (type, range, rate, ownership, distance, phase).
- [ ] Rules in a pure module with tests; no rules duplicated in client code.
- [ ] Systems communicate through events, not direct calls into unrelated services.
- [ ] Client feedback is immediate, server confirmation is visible, mismatches reconcile.
- [ ] Rewards and currency changes have one entry point and are logged.
- [ ] Debug tools are server-gated and stripped of any client trust.
