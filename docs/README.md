# AETHER STRIKE — dossier de conception technique

FPS tactique compétitif pour Roblox, direction artistique neo-military / dark cyber
(« futuriste froid et premium »). Ce dossier suit, dans l'ordre, les onze sections demandées ;
chaque affirmation renvoie au code de `src/`, et la section 10 en contient des extraits
**générés depuis le code** (vérifiables par `python3 tools/doc_excerpts.py --check`).

| § | Document | Contenu |
|---|---|---|
| 1 | [Activation des skills](01-skills.md) | Les 18 compétences techniques exigées et l'endroit exact où chacune est appliquée |
| 2 | [Architecture globale](02-architecture.md) | « Une place, deux rôles » (lobby / match), cycle de vie des services, pipeline d'un tir, réplication, inventaire des remotes, arborescence détaillée |
| 3 | [Modules et services](03-modules.md) | Les 104 modules : responsabilité, API, dépendances notables |
| 4 | [Hub : logique et flux](04-hub.md) | Zones et terminaux, party, file intelligente avec estimation, « match trouvé », retour au hub et écran de progression, missions, armurerie 3D |
| 5 | [Level design + 4 cartes](05-level-design.md) | Philosophie, pipeline, KESTREL YARD, HELIX VAULT, SPIRE-9, MONOLITH (plans en [maps/](maps/)), éclairage, streaming |
| 6 | [Movement system](06-movement.md) | Modèle « Source-like », counter-strafe chiffré, postures, glissade, lean, garde-fous serveur |
| 7 | [Weapon system & gunplay](07-weapons.md) | 14 armes (tableaux générés), modèle de tir, dégâts, dispersion, recul, ADS, animations, sons, skins |
| 8 | [HUD ultra-premium](08-hud.md) | Disposition 1080p, réticule dynamique, munitions, santé, dégâts directionnels, hitmarkers, killfeed, boussole, scores, lunette, spectateur ; responsive desktop / tablette / mobile ; réglages |
| 9 | [Effets, juice, caméra, son](09-juice.md) | Chargements, intro, punch/secousse/FOV, hit-stop, killcam, post-processing, mixage |
| 10 | [Code prioritaire](10-code.md) | Les fondations critiques, code réel commenté : réseau, tir prédit, validation, compensation de latence, rang MMR/RR, persistance, réplication, règles, matchmaking, mouvement, anti-exploit |
| 11 | [Roadmap d'implémentation](11-roadmap.md) | Phases dans l'ordre exact, critères de sortie, état, prochaine étape (play-tests), risques, ordre de construction fichier par fichier |
| 12 | [Audit et refonte](12-audit-refonte.md) | Diagnostic complet avant modification, corrections P0, habillage des cartes, éclairage, météo, ambiance sonore, accessibilité, budgets, avant/après |
| — | [Skills Claude Code](skills-claude-code.md) | L'équipe de skills installée dans `.claude/skills` : rôles, outils, utilisation, limites |

## Plans des cartes

| KESTREL YARD | HELIX VAULT | SPIRE-9 | MONOLITH | Hub |
|---|---|---|---|---|
| ![Kestrel](maps/kestrel.png) | ![Helix](maps/helix.png) | ![Spire](maps/spire.png) | ![Monolith](maps/monolith.png) | ![Hub](maps/hub.png) |

Rendus générés depuis les plans de `src/Server/Maps/Blueprints/` (`tools/export_maps.luau`
puis `tools/render_maps.py`).

## Ce qui est vérifié, et ce qui ne l'est pas encore

- **Vérifié automatiquement** : analyse Luau **stricte** de tout `src/` (0 erreur), 116 tests
  unitaires hors moteur, build Rojo de la place complète, graphe de dépendances sans cycle,
  extraits de la section 10 conformes au code.
- **Pas encore vérifié** : le jeu n'a pas été exécuté dans Roblox Studio. Le ressenti, les
  performances sur appareil, l'alignement fin du viewmodel procédural et le comportement
  inter-serveurs en live sont l'objet de la phase 9 de la roadmap.
- **Contenu provisoire assumé** : sons intégrés au client Roblox (pack final à brancher dans
  `Shared/Config/Sounds.luau`), aucune piste musicale, `productId` des achats Robux à 0 (offres
  masquées tant qu'ils ne sont pas créés), aberration chromatique simulée (pas d'effet natif),
  hit-stop purement visuel (multijoueur), boussole à la place d'une minimap (choix de design).
