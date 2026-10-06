#!/usr/bin/env python3
"""
doc_excerpts.py — génère les documents à extraits de code depuis leurs gabarits.

Les extraits de docs/10-code.md ne sont JAMAIS recopiés à la main : le gabarit
(tools/templates/10-code.md) contient des directives, remplacées ici par le code exact
de src/. Ainsi la documentation ne peut pas diverger silencieusement du code :

    python3 tools/doc_excerpts.py            # régénère les documents
    python3 tools/doc_excerpts.py --check    # échoue (code 1) si un document est périmé

Directives (seules sur leur ligne) :

    @@fn <fichier> <nom>@@          fonction de premier niveau (`local function nom` ou
                                    `function X.nom`) jusqu'à son `end` en colonne 0
    @@fn+doc <fichier> <nom>@@      idem, avec le commentaire qui la précède
    @@between <fichier> <début> ||| <fin>@@
                                    de la 1re ligne contenant <début> à la 1re ligne
                                    suivante contenant <fin> (incluses)
    @@between <fichier> <début> ||< <fin>@@
                                    idem, la ligne <fin> exclue (lignes vides finales
                                    retirées) : pour arrêter un extrait juste avant un bloc
    @@lines <fichier> <a> <b>@@     lignes a..b (incluses)

Chaque extrait est rendu dans un bloc ```lua précédé du chemin et des lignes sources ;
l'indentation commune est retirée et les tabulations deviennent 4 espaces.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TEMPLATES = {
    ROOT / "tools" / "templates" / "10-code.md": ROOT / "docs" / "10-code.md",
}
DIRECTIVE = re.compile(r"^@@(fn\+doc|fn|between|lines) (\S+) (.+)@@$")


class ExcerptError(Exception):
    pass


def read_lines(relative: str) -> list[str]:
    path = ROOT / relative
    if not path.is_file():
        raise ExcerptError(f"fichier introuvable : {relative}")
    return path.read_text(encoding="utf-8").splitlines()


def find_function(lines: list[str], name: str, relative: str) -> tuple[int, int]:
    escaped = re.escape(name)
    pattern = re.compile(rf"^(local )?function {escaped}\s*[(<]")
    starts = [index for index, line in enumerate(lines) if pattern.match(line)]
    if len(starts) != 1:
        raise ExcerptError(f"{relative} : fonction '{name}' trouvée {len(starts)} fois")
    start = starts[0]
    for index in range(start + 1, len(lines)):
        if lines[index] == "end":
            return start, index
    raise ExcerptError(f"{relative} : fin de '{name}' introuvable")


def with_doc_comment(lines: list[str], start: int) -> int:
    index = start - 1
    if index >= 0 and lines[index].strip().endswith("]]"):
        while index >= 0 and "--[[" not in lines[index]:
            index -= 1
        return max(index, 0)
    while index >= 0 and lines[index].lstrip().startswith("--"):
        index -= 1
    return index + 1


def find_between(lines: list[str], begin: str, finish: str, relative: str) -> tuple[int, int]:
    for start, line in enumerate(lines):
        if begin in line:
            for end in range(start, len(lines)):
                if finish in lines[end] and (end > start or begin == finish):
                    return start, end
            raise ExcerptError(f"{relative} : fin '{finish}' introuvable après '{begin}'")
    raise ExcerptError(f"{relative} : début '{begin}' introuvable")


def detab(line: str, common: int) -> str:
    stripped = line.lstrip("\t")
    depth = len(line) - len(stripped)
    return "    " * max(depth - common, 0) + stripped


def render(relative: str, lines: list[str], start: int, end: int) -> str:
    excerpt = lines[start : end + 1]
    depths = [len(line) - len(line.lstrip("\t")) for line in excerpt if line.strip()]
    common = min(depths) if depths else 0
    body = [detab(line, common) if line.strip() else "" for line in excerpt]
    header = f"-- {relative} (l. {start + 1}–{end + 1})"
    return "\n".join(["```lua", header, *body, "```"])


def expand(template: str) -> str:
    output: list[str] = []
    for number, line in enumerate(template.splitlines(), start=1):
        match = DIRECTIVE.match(line)
        if not match:
            output.append(line)
            continue
        kind, relative, argument = match.groups()
        try:
            lines = read_lines(relative)
            if kind in ("fn", "fn+doc"):
                start, end = find_function(lines, argument.strip(), relative)
                if kind == "fn+doc":
                    start = with_doc_comment(lines, start)
            elif kind == "between":
                exclusive = " ||< " in argument
                parts = argument.split(" ||< " if exclusive else " ||| ")
                if len(parts) != 2:
                    raise ExcerptError("syntaxe : @@between <fichier> <début> ||| <fin>@@ (ou ||<)")
                start, end = find_between(lines, parts[0], parts[1], relative)
                if exclusive:
                    end -= 1
                    while end > start and not lines[end].strip():
                        end -= 1
            else:
                a, b = (int(value) for value in argument.split())
                if not (1 <= a <= b <= len(lines)):
                    raise ExcerptError(f"{relative} : plage {a}-{b} hors du fichier")
                start, end = a - 1, b - 1
        except (ExcerptError, ValueError) as error:
            raise ExcerptError(f"gabarit ligne {number} : {error}") from error
        output.append(render(relative, lines, start, end))
    return "\n".join(output) + "\n"


def main() -> int:
    check = "--check" in sys.argv[1:]
    stale: list[str] = []
    for template_path, target in TEMPLATES.items():
        try:
            generated = expand(template_path.read_text(encoding="utf-8"))
        except ExcerptError as error:
            print(f"ERREUR {template_path.relative_to(ROOT)} : {error}", file=sys.stderr)
            return 2
        current = target.read_text(encoding="utf-8") if target.exists() else None
        if check:
            if generated != current:
                stale.append(str(target.relative_to(ROOT)))
        else:
            target.write_text(generated, encoding="utf-8")
            print(f"écrit : {target.relative_to(ROOT)}")
    if stale:
        print("Documents périmés (relancer tools/doc_excerpts.py) : " + ", ".join(stale), file=sys.stderr)
        return 1
    if check:
        print("Extraits de code à jour.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
