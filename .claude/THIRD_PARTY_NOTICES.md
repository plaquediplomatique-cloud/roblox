# Third-party notices — vendored skills

Some skills in `.claude/skills/` and one agent in `.claude/agents/` come from open-source
projects. They are vendored (copied into this repository) so that every Claude Code session on
this project gets the same, reviewed versions. Update them with `tools/update_vendored_skills.sh`.

## roblox-brain — TabooHarmony

- Source: https://github.com/TabooHarmony/roblox-brain
- Version: commit `38826be57ee37bcf023e9c2b85681bea3909281c` (2026-10-02, v2.2 release notes)
- Files: the 29 skill directories listed below, copied **unmodified**
  (`SKILL.md` + `references/full.md` each).
  - Core: `roblox-architecture`, `roblox-collaboration-mode`, `roblox-data`, `roblox-luau-core`,
    `roblox-luau-patterns`, `roblox-luau-types`, `roblox-networking`, `roblox-performance`,
    `roblox-security`, `roblox-server-data`
  - Gameplay: `roblox-animation-vfx`, `roblox-audio`, `roblox-building`, `roblox-camera`,
    `roblox-gui`, `roblox-input`, `roblox-lighting`, `roblox-localization`, `roblox-npc-ai`,
    `roblox-physics`
  - Design: `roblox-analytics`, `roblox-game-design`, `roblox-growth-design`,
    `roblox-monetization`, `roblox-player-psychology`
  - Tools: `roblox-cloud`, `roblox-publish-checklist`, `roblox-studio-mcp`, `roblox-tooling`

```
MIT License

Copyright (c) 2026 TabooHarmony

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## roblox-dev — Ivar

- Source: https://github.com/ivar-anon/roblox-dev
- Version: commit `c73640a28e014411d146b86ace88edef8c8b4142` (2026-09-10)
- Files (**modified**):
  - `.claude/skills/roblox-testing/SKILL.md` ← `skills/roblox-testing/SKILL.md` — `name` added,
    cross-references renamed (`roblox-datastores` → `roblox-data`), repository section added,
    debug-command snippet completed so that it type-checks in strict mode.
  - `.claude/skills/roblox-review/SKILL.md` ← `skills/review/SKILL.md` — renamed to
    `/roblox-review`, repository quality gates and related skills added.
  - `.claude/skills/roblox-new-system/SKILL.md` ← `skills/new-system/SKILL.md` — renamed to
    `/roblox-new-system`, cross-references renamed, repository mapping table added.
  - `.claude/agents/roblox-reviewer.md` ← `agents/roblox-reviewer.md` — purchase check and
    repository context added.

```
MIT License

Copyright (c) 2026 Ivar

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
