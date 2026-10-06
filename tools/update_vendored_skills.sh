#!/usr/bin/env bash
# Met à jour les skills tiers vendorisés (cf. .claude/THIRD_PARTY_NOTICES.md).
#
#   tools/update_vendored_skills.sh            # affiche le diff upstream (rien n'est modifié)
#   tools/update_vendored_skills.sh --apply    # copie les 29 skills roblox-brain (non modifiés)
#   BRAIN_REF=<commit> IVAR_REF=<commit> tools/update_vendored_skills.sh  # versions précises (défaut : main)
#
# Le contenu tiers est une donnée non fiable : LIRE le diff avant --apply, puis relancer
# python3 tools/check_skills.py --run-tests et mettre à jour le commit dans les notices.
# Les fichiers adaptés de roblox-dev (Ivar) sont modifiés localement : le script montre seulement
# le diff upstream pour une fusion manuelle.
set -euo pipefail
cd "$(dirname "$0")/.."

APPLY=0
[[ "${1:-}" == "--apply" ]] && APPLY=1
BRAIN_REF="${BRAIN_REF:-main}"
IVAR_REF="${IVAR_REF:-main}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

BRAIN_SKILLS=(
	roblox-architecture roblox-collaboration-mode roblox-data roblox-luau-core roblox-luau-patterns
	roblox-luau-types roblox-networking roblox-performance roblox-security roblox-server-data
	roblox-animation-vfx roblox-audio roblox-building roblox-camera roblox-gui roblox-input
	roblox-lighting roblox-localization roblox-npc-ai roblox-physics roblox-analytics
	roblox-game-design roblox-growth-design roblox-monetization roblox-player-psychology
	roblox-cloud roblox-publish-checklist roblox-studio-mcp roblox-tooling
)

fetch() { # url dest ref
	git clone --quiet --filter=blob:none "$1" "$2"
	git -C "$2" checkout --quiet "$3"
	echo "[vendor] $1 @ $(git -C "$2" rev-parse HEAD)"
}

fetch https://github.com/TabooHarmony/roblox-brain "$WORK/brain" "$BRAIN_REF"
for skill in "${BRAIN_SKILLS[@]}"; do
	# upstream range les skills par famille : skills/{core,gameplay,design,tools}/<skill>
	mapfile -t matches < <(find "$WORK/brain/skills" -mindepth 2 -maxdepth 2 -type d -name "$skill")
	if [[ ${#matches[@]} -ne 1 || ! -f "${matches[0]}/SKILL.md" ]]; then
		echo "[vendor] ATTENTION : $skill introuvable (ou ambigu) upstream"
		continue
	fi
	src="${matches[0]}"
	diff -ru ".claude/skills/$skill" "$src" || true
	if [[ $APPLY -eq 1 ]]; then
		rm -rf ".claude/skills/$skill"
		mkdir -p ".claude/skills/$skill"
		cp -R "$src/." ".claude/skills/$skill/"
	fi
done

fetch https://github.com/ivar-anon/roblox-dev "$WORK/ivar" "$IVAR_REF"
for pair in \
	"skills/roblox-testing/SKILL.md:.claude/skills/roblox-testing/SKILL.md" \
	"skills/review/SKILL.md:.claude/skills/roblox-review/SKILL.md" \
	"skills/new-system/SKILL.md:.claude/skills/roblox-new-system/SKILL.md" \
	"agents/roblox-reviewer.md:.claude/agents/roblox-reviewer.md"; do
	echo "[vendor] diff upstream (fusion manuelle) : ${pair%%:*} -> ${pair##*:}"
	diff -u "${pair##*:}" "$WORK/ivar/${pair%%:*}" || true
done

if [[ $APPLY -eq 1 ]]; then
	echo "[vendor] copié. Étapes suivantes : python3 tools/check_skills.py --run-tests, notices à jour."
else
	echo "[vendor] aperçu seulement (relancer avec --apply pour copier les skills roblox-brain)."
fi
