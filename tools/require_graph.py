#!/usr/bin/env python3
"""
require_graph.py — graphe des `require` de src/ : cycles et ordre de construction.

    python3 tools/require_graph.py            # résumé + couches de dépendances
    python3 tools/require_graph.py --check    # échoue (code 1) sur un cycle ou un require non résolu
    python3 tools/require_graph.py --markdown # couches au format Markdown (docs/11-roadmap.md)

Couche d'un module = 0 s'il ne dépend d'aucun module du projet, sinon 1 + la couche
maximale de ses dépendances : construire les couches dans l'ordre garantit que chaque
module n'utilise que du code déjà écrit et testable.
"""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
REQUIRE = re.compile(r"(?<![\w.:])require\(")
ALIAS = re.compile(r"^\s*local\s+(\w+)\s*=\s*(.+?)\s*$", re.M)


def module_files() -> set[Path]:
    return {path for path in SRC.rglob("*.luau")}


def normalize(expression: str) -> str:
    expression = re.sub(r':WaitForChild\("([^"]+)"(?:,[^)]*)?\)', r".\1", expression.strip())
    expression = re.sub(r'game:GetService\("ReplicatedStorage"\)', "RS", expression)
    expression = re.sub(r'game:GetService\("ReplicatedFirst"\)', "RF", expression)
    return expression


def argument_at(text: str, start: int) -> str:
    """Argument d'un appel dont la parenthèse ouvrante précède `start` (parenthèses équilibrées)."""
    depth, index, quote = 1, start, ""
    while index < len(text) and depth > 0:
        char = text[index]
        if quote:
            if char == quote:
                quote = ""
        elif char in "\"'":
            quote = char
        elif char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
        index += 1
    return text[start : index - 1]


def aliases_of(text: str) -> dict[str, str]:
    found: dict[str, str] = {}
    for name, value in ALIAS.findall(text):
        value = normalize(value)
        head = value.split(".")[0]
        if "require(" in value or not re.fullmatch(r"[\w.]+", value):
            continue
        if head in ("script", "RS", "RF") or head in found:
            found[name] = value
    return found


def expand(expression: str, aliases: dict[str, str]) -> str:
    for _ in range(8):
        head, _, rest = expression.partition(".")
        if head in aliases:
            expression = aliases[head] + ("." + rest if rest else "")
        else:
            break
    return expression


def resolve(files: set[Path], base: Path, parts: list[str]) -> Path | None:
    path = base.joinpath(*parts) if parts else base
    for candidate in (path.with_name(path.name + ".luau"), path / "init.luau"):
        if candidate in files:
            return candidate
    # Scripts Rojo : Main.server.luau, Boot.client.luau…
    for suffix in (".server.luau", ".client.luau"):
        candidate = path.with_name(path.name + suffix)
        if candidate in files:
            return candidate
    return None


def dependencies(files: set[Path], path: Path) -> tuple[list[Path], list[str]]:
    found: list[Path] = []
    unresolved: list[str] = []
    text = path.read_text(encoding="utf-8")
    aliases = aliases_of(text)
    for match in REQUIRE.finditer(text):
        expression = expand(normalize(argument_at(text, match.end())), aliases)
        parts = expression.split(".")
        target = None
        if parts[0] == "script":
            base = path.parent  # script.Parent d'un module = son dossier
            rest = parts[1:]
            if rest and rest[0] == "Parent":
                rest = rest[1:]
                while rest and rest[0] == "Parent":
                    base = base.parent
                    rest = rest[1:]
                target = resolve(files, base, rest)
        elif parts[:2] == ["RS", "Shared"]:
            target = resolve(files, SRC / "Shared", parts[2:])
        elif parts[0] == "RF":
            target = resolve(files, SRC / "ReplicatedFirst", parts[1:])
        if target:
            found.append(target)
        else:
            unresolved.append(expression)
    return found, unresolved


def name_of(path: Path) -> str:
    relative = path.relative_to(SRC).as_posix()
    return re.sub(r"\.(server|client)?\.?luau$", "", relative).removesuffix(".")


def main() -> int:
    files = module_files()
    graph: dict[Path, list[Path]] = {}
    problems: list[str] = []
    for path in sorted(files):
        deps, unresolved = dependencies(files, path)
        graph[path] = deps
        problems += [f"require non résolu : {name_of(path)} -> {expression}" for expression in unresolved]

    state: dict[Path, int] = {}
    stack: list[Path] = []
    depth: dict[Path, int] = {}
    sys.setrecursionlimit(10000)

    def visit(node: Path) -> int:
        if state.get(node) == 2:
            return depth[node]
        if state.get(node) == 1:
            cycle = stack[stack.index(node) :] + [node]
            problems.append("cycle : " + " -> ".join(name_of(item) for item in cycle))
            return 0
        state[node] = 1
        stack.append(node)
        level = 0
        for dependency in graph[node]:
            level = max(level, visit(dependency) + 1)
        stack.pop()
        state[node] = 2
        depth[node] = level
        return level

    for node in graph:
        visit(node)

    edges = sum(len(deps) for deps in graph.values())
    if "--check" in sys.argv[1:]:
        for problem in problems:
            print(problem, file=sys.stderr)
        print(f"{len(graph)} modules, {edges} dépendances, {len(problems)} problème(s)")
        return 1 if problems else 0

    layers: dict[int, list[str]] = {}
    for node, level in depth.items():
        layers.setdefault(level, []).append(name_of(node))
    markdown = "--markdown" in sys.argv[1:]
    if markdown:
        print("| Couche | Modules |")
        print("|---|---|")
    else:
        print(f"{len(graph)} modules, {edges} dépendances, {len(problems)} problème(s)")
    for level in sorted(layers):
        names = sorted(layers[level])
        if markdown:
            print(f"| {level} | " + " · ".join(f"`{name}`" for name in names) + " |")
        else:
            print(f"couche {level:2d} ({len(names)}) : " + ", ".join(names))
    for problem in problems:
        print(problem, file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
