# L'équipe de skills Claude Code du projet

Les skills sont des dossiers `.claude/skills/<nom>/SKILL.md` que Claude Code charge
automatiquement quand une demande correspond à leur description (ou à la main avec
`/<nom>`). Ils sont versionnés avec le projet : toute session Claude Code ouverte dans ce dépôt
dispose de la même équipe. Vérification : `python3 tools/check_skills.py --run-tests`.

## Skills écrits pour ce projet (outils concrets inclus)

| Skill | Rôle dans l'équipe | Outils |
|---|---|---|
| `roblox-technical-director` | Directeur technique : routage vers les spécialistes, protocole de changement, priorités P0→P5, portes qualité, lancement Rojo | — |
| `roblox-gameplay-systems` | Gameplay programmer : combat, inventaire, interactions, missions, progression, debug | `scripts/InteractableKit.luau` (objets interactifs validés serveur, portes animées) + tests Lune |
| `roblox-level-design` | Level designer : métriques, blockout, flux, repères, streaming, villes | — |
| `roblox-environment-art` | Environment artist : bible artistique, anti « map Roblox basique », passes d'habillage, recettes de pièces | — |
| `roblox-props-modeling` | Prop artist : mobilier et props modulaires, conventions de pivot/collision | `scripts/PropKit.luau` (8 générateurs, 3 styles), export `.rbxm`, 2 112 tests |
| `roblox-materials-textures` | Technical artist matériaux : PBR, MaterialVariant, répétition, budgets | — |
| `roblox-lighting-art` | Lighting artist : ambiances, températures (K), intérieur/extérieur, jour/nuit, post-process | `scripts/LightingRig.luau` (looks NoonClear, GoldenHour, Overcast, NightCity ; lumières pratiques) |
| `roblox-movement-feel` | Animator / game feel : accélérations, saut, caméra, head bob, blending, portes/ascenseurs | — |
| `roblox-ui-design-system` | UI/UX designer : jetons, états, hiérarchie HUD, accessibilité, plateformes | `scripts/contrast.py` (contraste WCAG des jetons du thème) |
| `roblox-sound-design` | Sound designer : couches, mixage, réverbération par zone, occlusion, musique adaptative | `scripts/SoundscapeKit.luau` (zones d'ambiance, sons ponctuels, stems) + tests Lune |
| `roblox-render-performance` | Performance engineer (rendu) : coûts, budgets mobile/desktop, LOD, streaming | `scripts/SceneAudit.luau` + `audit_file.luau` (audit de place/modèle) |

## Skills adaptés (roblox-dev, Ivar, MIT)

| Skill / agent | Rôle |
|---|---|
| `roblox-testing` | Stratégie de test (Lune, tests de règles pures, play-tests multi-clients) |
| `/roblox-review` | Revue de code avec les portes qualité du dépôt |
| `/roblox-new-system` | Échafaudage d'un nouveau système (config, règles, service, contrôleur, tests) |
| agent `roblox-reviewer` | Relecteur indépendant (sécurité, réseau, données, performance) |

## Références vendorisées (roblox-brain, TabooHarmony, MIT, non modifiées)

| Famille | Skills |
|---|---|
| Cœur | `roblox-architecture`, `roblox-collaboration-mode`, `roblox-data`, `roblox-luau-core`, `roblox-luau-patterns`, `roblox-luau-types`, `roblox-networking`, `roblox-performance`, `roblox-security`, `roblox-server-data` |
| Gameplay / API | `roblox-animation-vfx`, `roblox-audio`, `roblox-building`, `roblox-camera`, `roblox-gui`, `roblox-input`, `roblox-lighting`, `roblox-localization`, `roblox-npc-ai`, `roblox-physics` |
| Design | `roblox-analytics`, `roblox-game-design`, `roblox-growth-design`, `roblox-monetization`, `roblox-player-psychology` |
| Outils | `roblox-cloud`, `roblox-publish-checklist`, `roblox-studio-mcp`, `roblox-tooling` |

Mise à jour : `tools/update_vendored_skills.sh` (aperçu du diff), puis `--apply` après lecture.
Licences et versions : `.claude/THIRD_PARTY_NOTICES.md`.

## Utilisation

- Demande large (« refonte », « audit », « améliore le jeu ») : Claude commence par
  `roblox-technical-director`, qui charge les spécialistes utiles.
- Demande ciblée : décrire le besoin suffit (« les déplacements sont rigides », « habille cette
  rue ») ; la description du skill déclenche son chargement. On peut forcer : `/roblox-sound-design`.
- Les outils se lancent depuis la racine du dépôt, par exemple
  `lune run .claude/skills/roblox-render-performance/scripts/audit_file.luau build/props/PropKit_Showroom.rbxm`
  ou `python3 .claude/skills/roblox-ui-design-system/scripts/contrast.py src/Shared/Config/Theme.luau`.
- Les modules Roblox des skills (`PropKit`, `LightingRig`, `SceneAudit`, `SoundscapeKit`,
  `InteractableKit`) se copient comme ModuleScripts dans un projet, ou s'exécutent dans Studio
  via la barre de commande / le MCP de Studio (`roblox-studio-mcp`).

## Domaines sans skill dédié (limites connues)

- **Modélisation 3D maillée** (Blender, UV, baking) : aucun skill fiable n'existe ; PropKit
  produit des props en parts, et `roblox-materials-textures` couvre l'import de maillages et
  SurfaceAppearance. Les meshes finaux restent un travail d'artiste 3D.
- **Création d'animations clés** (keyframes de l'Animation Editor) : les skills couvrent la
  lecture, le blending et l'animation procédurale ; l'animation authored reste manuelle.
- **Composition musicale / enregistrement audio** : le sound design couvre le choix,
  l'intégration et le mixage, pas la production des fichiers.
