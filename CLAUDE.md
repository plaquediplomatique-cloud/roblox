# AETHER STRIKE — instructions projet pour Claude Code

FPS tactique compétitif Roblox (neo-military / dark cyber, « futuriste froid et premium »).
Luau **strict**, projet Rojo, logique pure testée hors moteur avec Lune. Vue d'ensemble :
`README.md` ; conception détaillée : `docs/01` → `docs/11` ; cartes : `docs/maps/`.

## Arborescence

- `src/Shared` — config (`Config/`), types, réseau (`Net/`), règles pures (`Rules/`), combat
  (`Combat/`), utilitaires (`Util/`). Répliqué.
- `src/Server` — services (`Services/`), match (`Match/`), cartes (`Maps/` : DSL `MapKit`,
  `MapBuilder`, plans `Blueprints/`), personnage, `GameEvents` (bus d'événements).
- `src/Client` — contrôleurs (`Controllers/`), lobby (`Lobby/`), kit d'UI (`UI/`), armes
  (`Weapons/`). `src/ReplicatedFirst` — boot et écran de chargement.
- `tests/specs` — tests Lune ; `tools/` — scripts de vérification et d'export ;
  `.claude/skills` — l'équipe de skills (voir plus bas).

## Commandes (portes qualité)

```bash
stylua src tests tools .claude/skills    # formatage (relancer si des fichiers changent)
./scripts/analyze.sh                     # luau-lsp strict : 0 erreur, 0 avertissement
./scripts/test.sh                        # tests unitaires Lune
./scripts/build.sh                       # build/AetherStrike.rbxl
python3 tools/require_graph.py           # requires : cycles / non résolus
python3 tools/doc_excerpts.py --check    # extraits de code des docs à jour
python3 tools/check_skills.py --run-tests
```

Tout changement de code passe ces commandes avant commit.

## Conventions

- Luau `--!strict` partout, types exportés, StyLua (tabs, 120 colonnes). Identifiants en
  anglais, commentaires et docs en français (style existant).
- Serveur autoritaire : chaque remote est déclaré dans `src/Shared/Net/Net.luau` et branché via
  `src/Server/Net/ServerNet.luau` (rate limit → schéma `Guard` → exécution protégée). Aucune
  confiance dans le client.
- Les systèmes communiquent par `src/Server/GameEvents.luau`, pas par appels croisés.
- Les règles (manches, rang, matchmaking, spread…) vivent dans des modules purs testés.
- Les nombres de design vivent dans `src/Shared/Config` (armes, mouvement, thème, sons…).
- Sons : clés logiques de `Config/Sounds.luau`, jamais de SoundId en dur. UI : jetons de
  `Config/Theme.luau` et kit `src/Client/UI/UI.luau`, jamais de couleur en dur.
- Cartes : construites par code à partir des plans (`Maps/Blueprints`) ; les tests de cartes
  (`tests/specs/maps.luau`) vérifient spawns, lignes de vue et accessibilité.

## Équipe de skills

Pour toute demande large (refonte, audit, « améliore le jeu »), commencer par
`roblox-technical-director` : il route vers les spécialistes, impose le protocole de
changement (comprendre → objectif → dépendances → risques → changer → vérifier → optimiser)
et l'ordre P0 → P5. Spécialistes principaux : `roblox-gameplay-systems`,
`roblox-level-design`, `roblox-environment-art`, `roblox-props-modeling`,
`roblox-lighting-art`, `roblox-materials-textures`, `roblox-movement-feel`,
`roblox-ui-design-system`, `roblox-sound-design`, `roblox-render-performance` ; références API
et architecture : les 29 skills `roblox-*` vendorisés (voir `.claude/THIRD_PARTY_NOTICES.md`).
Commandes : `/roblox-review` (revue), `/roblox-new-system` (nouveau système), agent
`roblox-reviewer` (revue indépendante).

## Lancer le jeu dans Studio

`rokit install`, `rojo plugin install`, puis `rojo serve` + Studio *Plugins → Rojo → Connect*
(ou ouvrir `build/AetherStrike.rbxl`). *Test → Clients and Servers* (2 à 6 joueurs) pour la
boucle complète : en Studio les matchs sont locaux et les profils utilisent un magasin en
mémoire sans « Enable Studio Access to API Services ».
