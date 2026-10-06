#!/usr/bin/env python3
"""Checks the Claude Code skills in .claude/skills (and agents in .claude/agents).

  python3 tools/check_skills.py              # structure, links, type-check of strict Luau
  python3 tools/check_skills.py --run-tests  # + runs every skill's scripts/test_*.luau with Lune
  python3 tools/check_skills.py --no-typecheck

Checks:
  * SKILL.md frontmatter: name (= directory, lowercase-hyphen, <= 64), description (<= 1024)
  * unique names across skills and agents
  * `roblox-*` references in backticks resolve to a skill or an agent
  * relative markdown links and `scripts/…` / `references/…` paths exist in the skill
  * repository paths (`src/…`, `tools/…`, `tests/…`, `docs/…`, `.claude/…`) exist, for skills
    authored for this repository (vendored skills carry `last_reviewed` and describe other projects)
  * Luau code blocks starting with `--!strict` and `scripts/*.luau` files starting with
    `--!strict` type-check with luau-lsp against the Roblox definitions
Exit status 1 on any problem.
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKILLS = os.path.join(ROOT, ".claude", "skills")
AGENTS = os.path.join(ROOT, ".claude", "agents")
DEFINITIONS = os.path.join(ROOT, ".cache", "globalTypes.d.luau")
NAME = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
REFERENCE = re.compile(r"`(roblox-[a-z0-9-]+)`")
LINK = re.compile(r"\]\(([^)#\s]+)(?:#[^)]*)?\)")
SKILL_PATH = re.compile(r"`((?:scripts|references|assets)/[^`\s]+)`")
REPO_PATH = re.compile(r"`((?:src|tools|tests|docs|scripts|\.claude)/[^`\s*<>…]+)`")
CODE = re.compile(r"```(?:lua|luau)\n(.*?)```", re.S)


def frontmatter(text):
    if not text.startswith("---\n"):
        return None
    end = text.find("\n---", 4)
    if end < 0:
        return None
    fields, key = {}, None
    for line in text[4:end].splitlines():
        match = re.match(r"^([A-Za-z_][\w-]*):\s*(.*)$", line)
        if match:
            key = match.group(1)
            fields[key] = match.group(2).strip()
        elif key and line.startswith((" ", "\t")):
            fields[key] = (fields[key] + " " + line.strip()).strip()
    for key, value in fields.items():
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            fields[key] = value[1:-1]
    return fields


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-tests", action="store_true")
    parser.add_argument("--no-typecheck", action="store_true")
    args = parser.parse_args()

    problems = []
    names = {}
    skills = sorted(d for d in os.listdir(SKILLS) if os.path.isdir(os.path.join(SKILLS, d)))
    agents = sorted(f[:-3] for f in os.listdir(AGENTS) if f.endswith(".md")) if os.path.isdir(AGENTS) else []
    known = set(skills) | set(agents)
    strict_files = []  # (label, path)

    for agent in agents:
        meta = frontmatter(open(os.path.join(AGENTS, agent + ".md"), encoding="utf-8").read())
        if not meta or meta.get("name") != agent or not meta.get("description"):
            problems.append(f"agent {agent}: frontmatter needs name = file name and a description")
        names[agent] = "agent"

    snippet_dir = tempfile.mkdtemp(prefix="skills-")
    for skill in skills:
        directory = os.path.join(SKILLS, skill)
        path = os.path.join(directory, "SKILL.md")
        if not os.path.isfile(path):
            problems.append(f"{skill}: missing SKILL.md")
            continue
        text = open(path, encoding="utf-8").read()
        meta = frontmatter(text)
        if meta is None:
            problems.append(f"{skill}: missing or unterminated frontmatter")
            continue
        name, description = meta.get("name", ""), meta.get("description", "")
        if name != skill:
            problems.append(f"{skill}: name '{name}' differs from the directory")
        if not NAME.match(name) or len(name) > 64:
            problems.append(f"{skill}: invalid name '{name}'")
        if not description:
            problems.append(f"{skill}: empty description")
        elif len(description) > 1024:
            problems.append(f"{skill}: description is {len(description)} chars (> 1024)")
        if name in names:
            problems.append(f"{skill}: duplicate name '{name}'")
        names[name] = "skill"
        vendored = "last_reviewed" in meta

        files = [path] + [
            os.path.join(base, f)
            for base, _, fs in os.walk(directory)
            for f in fs
            if f.endswith(".md") and os.path.join(base, f) != path
        ]
        for md in files:
            body = open(md, encoding="utf-8").read()
            rel = os.path.relpath(md, ROOT)
            for ref in sorted(set(REFERENCE.findall(body))):
                if ref not in known:
                    problems.append(f"{rel}: unknown skill/agent reference `{ref}`")
            for link in LINK.findall(body):
                if re.match(r"^[a-z]+:", link):
                    continue
                target = os.path.normpath(os.path.join(os.path.dirname(md), link))
                if not os.path.exists(target):
                    problems.append(f"{rel}: broken link ({link})")
            if md == path:
                for item in sorted(set(SKILL_PATH.findall(body))):
                    if not os.path.exists(os.path.join(directory, item)):
                        problems.append(f"{rel}: missing skill file `{item}`")
            if not vendored:
                for item in sorted(set(REPO_PATH.findall(body))):
                    candidate = item.rstrip(".,;:)")
                    if candidate.endswith("/"):
                        candidate = candidate[:-1]
                    if not any(os.path.exists(os.path.join(base, candidate)) for base in (ROOT, directory)):
                        problems.append(f"{rel}: missing repository path `{item}`")
            # Vendored snippets are upstream illustrations (fragments, lint noise): only the
            # skills authored for this repository promise type-correct strict snippets.
            for index, block in enumerate(CODE.findall(body)):
                if not vendored and block.lstrip().startswith("--!strict"):
                    snippet = os.path.join(snippet_dir, f"{skill}__{os.path.basename(md)[:-3]}__{index}.luau")
                    with open(snippet, "w", encoding="utf-8") as handle:
                        handle.write(block)
                    strict_files.append((f"{rel} block {index + 1}", snippet))
        scripts = os.path.join(directory, "scripts")
        if os.path.isdir(scripts):
            for f in sorted(os.listdir(scripts)):
                full = os.path.join(scripts, f)
                if f.endswith(".luau") and open(full, encoding="utf-8").read().lstrip().startswith("--!strict"):
                    strict_files.append((os.path.relpath(full, ROOT), full))

    if not args.no_typecheck and strict_files:
        if not shutil.which("luau-lsp") or not os.path.isfile(DEFINITIONS):
            problems.append("type-check skipped: luau-lsp or .cache/globalTypes.d.luau missing (run ./scripts/analyze.sh once)")
        else:
            result = subprocess.run(
                ["luau-lsp", "analyze", f"--definitions=@roblox={DEFINITIONS}",
                 f"--base-luaurc={os.path.join(ROOT, '.luaurc')}", "--formatter=plain"]
                + [p for _, p in strict_files],
                cwd=ROOT, capture_output=True, text=True,
            )
            labels = {p: label for label, p in strict_files}
            for line in (result.stdout + result.stderr).splitlines():
                if line.startswith("[INFO]") or not line.strip():
                    continue
                for p, label in labels.items():
                    if line.startswith(p) or line.startswith(os.path.relpath(p, ROOT)):
                        line = label + line[line.index(":", len(os.path.relpath(p, ROOT)) if line.startswith(os.path.relpath(p, ROOT)) else len(p)):]
                        break
                problems.append("type: " + line)
            print(f"type-checked {len(strict_files)} strict Luau files/snippets")

    if args.run_tests:
        if not shutil.which("lune"):
            problems.append("tests skipped: lune missing (rokit install)")
        else:
            for skill in skills:
                scripts = os.path.join(SKILLS, skill, "scripts")
                if not os.path.isdir(scripts):
                    continue
                for f in sorted(os.listdir(scripts)):
                    if f.startswith("test_") and f.endswith(".luau"):
                        rel = os.path.relpath(os.path.join(scripts, f), ROOT)
                        result = subprocess.run(["lune", "run", rel], cwd=ROOT, capture_output=True, text=True)
                        last = (result.stdout.strip().splitlines() or ["(no output)"])[-1]
                        print(f"{rel}: {last}")
                        if result.returncode != 0:
                            problems.append(f"{rel} failed:\n{result.stdout}{result.stderr}")

    shutil.rmtree(snippet_dir, ignore_errors=True)
    print(f"{len(skills)} skills, {len(agents)} agents checked")
    if problems:
        print(f"\n{len(problems)} problem(s):")
        for problem in problems:
            print("  - " + problem)
        return 1
    print("all skill checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
