---
name: roblox-new-system
description: Generate a complete, secure client/server gameplay system for Roblox — shared types, validated server service, client controller, remote registration, QA hooks and pure-logic specs in one pass. Use when adding a feature like a shop, inventory, crafting, combat ability, quest, daily reward, door/elevator interaction, or any system that spans client and server.
---

# /roblox-new-system — Generate a Complete System

Generate a full vertical slice of a gameplay system named in `$ARGUMENTS`
(e.g. `/roblox-new-system DailyRewards`). A "system" is never one file —
it is the pieces below, generated together so nothing is left insecure
or untyped.

## Before generating

1. Read the project's existing structure: entry points, where services and
   controllers live, the remote registry, the shared types module, the data
   layer. **Match existing conventions** — if the project has a `Net`
   wrapper, a signal library, or a data layer (e.g. ProfileStore), use them
   rather than inventing parallel ones. For design questions about the system
   itself (data model, rules, edge cases) read `roblox-gameplay-systems`.
2. If the system's rules are ambiguous (costs, cooldowns, limits), ask the
   one or two questions that change the code; default the rest into config
   entries that are easy to tune.

## The pieces

### 1. Shared types

Request/response payload types and any state snapshot type the client renders.

### 2. Server module

- `--!strict`, two-phase shape (`init` wires remotes/state, `start` runs
  loops if any).
- Owns ALL state for this system in a server-side table (keyed by Player,
  cleaned on `PlayerRemoving` — see roblox-performance).
- Every remote handler: rate limit → type validation → range validation →
  permission/plausibility validation → mutate → replicate result
  (the ladder from the roblox-security and roblox-networking skills).
- Persistent state goes through the project's data layer, never direct
  DataStore calls inline (see roblox-data).
- Exposes a clean module API (`<Name>.grant(player, ...)`) so cheat commands
  and other systems reuse the same code paths (see roblox-testing).

### 3. Client controller

- Renders state received from the server; requests actions; **computes
  nothing authoritative**.
- Handles the late-join case: render from a full snapshot on join, then apply
  incremental updates.
- Optimistic UI is allowed for feel (button responds instantly) but must
  reconcile with the server result (revert on rejection).

### 4. Registration and QA

- Remote names added to the project's remote list/creation point.
- Cheat-remote entries for QA (grant/reset/trigger) gated per roblox-testing.
- If the system has pure logic (curves, drop tables, price math), extract it
  to a pure shared module and add a spec with boundary tests.

## In this repository (AETHER STRIKE)

Map the pieces onto the existing architecture instead of creating new folders:

| Piece | Location and convention |
|---|---|
| Shared types | add to `src/Shared/Types.luau` |
| Tunables | a config module in `src/Shared/Config/` |
| Pure rules | `src/Shared/Rules/<Name>.luau` + spec in `tests/specs/` (Lune runner, see roblox-testing) |
| Remotes | declare each one in `src/Shared/Net/Net.luau` (`DEFINITIONS` + the `EventName`/`FunctionName` union); handlers via `ServerNet.onEvent` / `ServerNet.onInvoke` with a `RateSpec` and a strict `Guard.shape` parser |
| Server | `src/Server/Services/<Name>Service.luau` exposing `Init()` and `Start()`; add it to `ORDER` in `src/Server/Main.server.luau` after its dependencies |
| Persistence | `PlayerService.set/increment` (replicated + saved through `DataService`), schema change in `src/Shared/Data/ProfileTemplate.luau` with a migration |
| Client | `src/Client/Controllers/<Name>Controller.luau` with `start()`, started from `src/Client/Main.client.luau`; read state from replicas (`ReplicaController`) |
| UI | the kit in `src/Client/UI/UI.luau` and tokens in `src/Shared/Config/Theme.luau` (see roblox-ui-design-system) |

Then run the quality gates: `./scripts/analyze.sh`, `./scripts/test.sh`,
`stylua src tests`, `python3 tools/require_graph.py --check`.

## Output discipline

- Deliver complete files, not fragments, for anything new; targeted edits for
  existing files (remote registry, shared types).
- After generating, summarize the security posture in 2–3 bullets: what the
  server validates, what an exploiter could try, and why it fails.
- Flag any piece intentionally left simple (e.g. "no purchase receipt
  idempotency yet — needed if you sell this for Robux") so scope cuts are
  visible, not silent.

---
*Adapted from [ivar-anon/roblox-dev](https://github.com/ivar-anon/roblox-dev) (MIT, © 2026 Ivar):
command renamed, cross-references renamed to this skill set, repository mapping added.
See `.claude/THIRD_PARTY_NOTICES.md`.*
