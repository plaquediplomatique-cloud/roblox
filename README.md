# AETHER STRIKE

FPS tactique compétitif pour Roblox — neo-military / dark cyber, « futuriste froid et
premium ». Duels nerveux, manches à objectif, gunplay à pattern apprenable, serveur
autoritaire et compensation de latence. Code complet en **Luau strict**, organisé en
services, avec une logique de jeu pure testée hors moteur.

## Contenu

- **Modes** : DUEL 1v1 (élimination, premier à 7), WINGMAN 2v2 (Uplink, site unique, premier
  à 7), SQUAD 3v3 (Uplink, sites A/B, premier à 8), CLASH 2v2 et 3v3 (élimination rapide,
  non classés) ; prolongations à 2 manches d'écart puis mort subite ; manches pistolet.
- **Cartes** : KESTREL YARD, HELIX VAULT, SPIRE-9, MONOLITH + le hub (QG) — construites par
  code à partir de plans testés (aucune ligne de vue entre spawns adverses).
- **Arsenal** : 14 armes — 2 fusils d'assaut, fusil en rafale, 2 SMG, mitrailleuse à montée
  en cadence, sniper à verrou, DMR, fusil à pompe et pompe automatique, pistolet, revolver,
  pistolet-mitrailleur, lame ionique — recul à pattern, bloom, précision de 1re balle,
  pénétration par matériau, viewmodel procédural.
- **Compétitif** : MMR caché (Elo d'équipe) + rang visible (RECRUIT → APEX, 3 divisions, puis
  AETHER) et RR à convergence, placements, classement global ; matchmaking équilibré par
  MMR et rang, parties jamais séparées, estimation d'attente réelle, inter-serveurs.
- **Progression** : niveaux, Aether Pass (gratuit / premium), missions quotidiennes et défis
  hebdomadaires, statistiques de carrière, écran de progression au retour au hub.
- **Cosmétiques** : 112 skins d'armes (Common → Mythic, effets spéciaux), opérateurs, effets
  d'élimination, emotes, bannières, titres ; armurerie 3D et casier.
- **Hub** : 3e personne, terminaux par zone, party, file intelligente, Training Range (bots,
  statistiques), parties personnalisées, transitions cinématiques.
- **Match** : intro cinématique, killcam, spectateur, HUD complet, tableau des scores, fin de
  match orbitale, retour au hub sans coupure (écran de téléportation continu).
- **Anti-exploit** : remotes validés et limités, vérification serveur de chaque tir
  (13 contrôles), surveillance du mouvement, détection statistique du no-spread, pot de miel.
- **Plateformes** : clavier/souris, manette, tactile (stick flottant, boutons, assistance de
  visée légère) ; interface adaptative ; réglages complets (vidéo, audio, contrôles, réticule,
  touches).

## Démarrage rapide

```bash
rokit install                 # rojo 7.7.1, luau-lsp 1.70.1, StyLua 2.5.2, Lune 0.10.5
./scripts/analyze.sh          # analyse Luau stricte de src/ (télécharge les définitions Roblox)
./scripts/test.sh             # 91 tests unitaires (Lune)
./scripts/build.sh            # → build/AetherStrike.rbxl
```

Ouvrir `build/AetherStrike.rbxl` dans Roblox Studio, ou lancer `rojo serve` et se connecter
avec le plugin Rojo. En Studio, le serveur est toujours un lobby et le matchmaking lance des
matchs **locaux** sur une arène du serveur : **Test → Clients and Servers** avec 2 à 6
joueurs suffit pour jouer la boucle complète. Sans « Enable Studio Access to API Services »,
les profils utilisent un magasin en mémoire de même sémantique.

En live, une seule place joue deux rôles : les serveurs publics sont des **lobbies**, les
serveurs réservés par le matchmaker sont des **serveurs de match**
([docs/02-architecture.md](docs/02-architecture.md)).

## Vérifications

| Commande | Rôle |
|---|---|
| `./scripts/analyze.sh` | luau-lsp en mode strict avec les définitions de l'API Roblox |
| `./scripts/test.sh` | logique pure : hitboxes, dispersion, balistique, rang, matchmaking, règles, données |
| `./scripts/build.sh` | build Rojo de la place |
| `stylua --check src tests` | formatage |
| `python3 tools/require_graph.py --check` | aucun cycle ni `require` non résolu |
| `python3 tools/doc_excerpts.py --check` | extraits de code de la documentation conformes au code |

## Organisation

```
src/
├── Shared/      types, utilitaires, réseau, configuration, combat et règles purs (client + serveur)
├── Server/      services (données, combat, anti-exploit, match, matchmaking, progression…),
│                instance de match, cartes (kit + plans), rôle du serveur
├── Client/      contrôleurs (caméra, mouvement, viewmodel, armes, HUD, match, audio, effets…),
│                lobby, interface
└── ReplicatedFirst/   écran de chargement (démarrage et téléportations)
tests/           tests Lune (specs + chargeur de modules hors moteur)
tools/           tables d'armes, plans des cartes, graphe de dépendances, extraits de documentation
docs/            dossier de conception en 11 sections
```

## Documentation

Le dossier de conception complet est dans [docs/](docs/README.md) : skills, architecture,
modules, hub, level design, mouvement, armes, HUD, juice, **code prioritaire** et **roadmap**.

## État

Le code des systèmes est écrit et vérifié statiquement (analyse stricte, tests, build), mais
le jeu **n'a pas encore été joué dans Roblox Studio** : la phase suivante est l'intégration et
les play-tests ([docs/11-roadmap.md](docs/11-roadmap.md)). Contenu provisoire : sons intégrés
au client Roblox (à remplacer dans `src/Shared/Config/Sounds.luau`), pas de musique,
identifiants de produits Robux à renseigner dans `src/Shared/Config/Products.luau`.
