# 11. Roadmap d'implémentation — l'ordre exact

> Principe : **de l'intérieur vers l'extérieur.** Contrat → vérité serveur → ressenti →
> boucle de match → méta → habillage → live. Une phase ne commence que lorsque la précédente
> passe ses **critères de sortie** ; aucune ne dépend d'une couche supérieure (l'ordre est
> celui du graphe de `require` réel, [annexe A](#annexe-a--ordre-de-construction-fichier-par-fichier)).

**État du dépôt.** Les phases 0 à 8 sont **écrites** : 104 modules Luau strict, 0 erreur
d'analyse, 91 tests unitaires verts, build Rojo de la place complète, 0 cycle de dépendances.
Elles n'ont **pas encore été jouées en Studio** : leurs critères « en jeu » (marqués 🔶) sont
précisément l'objet de la phase 9, la prochaine étape.

| Légende | Signification |
|---|---|
| ✅ | fait et vérifié automatiquement (analyse stricte, tests, build) |
| 🔶 | fait, critère à valider en jeu (Studio puis serveurs live) |
| ⬜ | à faire |

## Vue d'ensemble

| Phase | Contenu | État | Dépend de |
|---|---|---|---|
| 0 | Outillage, conventions, CI locale | ✅ | — |
| 1 | Socle partagé : types, utilitaires, contrat réseau | ✅ | 0 |
| 2 | Données joueur : profil, persistance, réplication | ✅ 🔶 | 1 |
| 3 | Combat pur : postures, hitboxes, dispersion, balistique, arsenal | ✅ | 1 |
| 4 | Vérité serveur : personnages, compensation de latence, combat, anti-exploit | ✅ 🔶 | 2, 3 |
| 5 | Ressenti client : entrées, caméra, mouvement, viewmodel, tir, effets, son | ✅ 🔶 | 3, 4 |
| 6 | Cartes : kit, constructeur, 4 cartes de match + hub | ✅ 🔶 | 1 |
| 7 | Boucle de match : règles, objectif, killcam, spectateur, HUD, transitions | ✅ 🔶 | 4, 5, 6 |
| 8 | Méta et hub : progression, rang, missions, inventaire, party, matchmaking, lobby | ✅ 🔶 | 2, 7 |
| 9 | **Intégration Studio et premiers play-tests** | ⬜ **prochaine étape** | 0–8 |
| 10 | Production audio et visuelle | ⬜ | 9 |
| 11 | Équilibrage piloté par la télémétrie (bêta fermée) | ⬜ | 9 |
| 12 | Performance, réseau, mobile | ⬜ | 9 |
| 13 | Sécurité : test d'intrusion autorisé | ⬜ | 9 |
| 14 | Lancement et live ops (saison 1) | ⬜ | 10–13 |

---

## Phase 0 — Outillage et conventions ✅

**Pourquoi d'abord :** sans analyse stricte ni tests hors moteur, chaque phase suivante
accumule des erreurs invisibles jusqu'au play-test.

- Projet Rojo (`default.project.json`) : services, `StreamingEnabled`, éclairage, scripts de
  démarrage ; toolchain épinglée (`rokit.toml` : rojo 7.7.1, luau-lsp 1.70.1, StyLua 2.5.2,
  Lune 0.10.5).
- `scripts/analyze.sh` (luau-lsp strict + définitions Roblox + sourcemap),
  `scripts/test.sh` (Lune), `scripts/build.sh` (place `.rbxl`) ; StyLua.
- Outils : `tools/require_graph.py` (cycles, ordre), `tools/doc_excerpts.py` (extraits de
  documentation vérifiés), `tools/weapon_table.luau` (tables d'armes), `tools/export_maps.luau`
  + `tools/render_maps.py` (plans des cartes).

**Critères de sortie :** analyse 0 erreur ; tests exécutables ; build produisant une place.

## Phase 1 — Socle partagé et contrat réseau ✅

- `Shared/Types` (tous les types échangés), `Shared/Util/*` (Signal, Janitor, Spring, Pool,
  RateLimiter, Guard, Logger, MathUtil).
- `Shared/Net/Net` (registre des 33 remotes), `Server/Net/ServerNet` (débit → schéma →
  exécution protégée), `Shared/Net/LookCodec` (visée binaire), `Shared/Replica/ReplicaPath`.

**Critères de sortie :** chaque remote client → serveur a un débit et un schéma strict ;
pot de miel branché ; tests Guard (NaN, inf, métatables, champs inconnus), RateLimiter,
LookCodec, ReplicaPath, Spring (stabilité à 2 s de `dt`, indépendance au framerate).

## Phase 2 — Données joueur ✅ 🔶

- `Shared/Data/ProfileTemplate` (version, migrations, réconciliation), `DataService` (verrou de
  session, autosave, `BindToClose`, magasin mémoire en Studio), `ReplicaService` +
  `Client/Core/ReplicaController`, `PlayerService` (écritures répliquées, notifications,
  attributs publics).

**Critères de sortie :** ✅ tests de réconciliation (profil ancien, corrompu, loadout
invalide) ; 🔶 en live, aller-retour lobby → match → lobby **sans perte ni double écriture**
(verrou transmis, `LastMatch` présent à l'arrivée), coupure brutale d'un serveur sans perte
au-delà de la dernière autosave.

## Phase 3 — Combat pur ✅

- `Shared/Combat/Stances` (géométrie des postures, lean = caméra = hitbox), `Hitbox` (OBB),
  `Spread` (cône unique, directions déterministes), `Ballistics` (zones, chute, bouclier,
  pénétration), `SpreadAudit`.
- `Shared/Config/Weapons` (14 armes, 13 à feu + lame : tir, dégâts, recul, maniement,
  munitions, sons, traceurs), `RecoilPatterns`, `WeaponModels`, `Movement`.

**Critères de sortie :** ✅ tests : zones touchées, tête accroupie sous une caisse de
4 studs, déterminisme et respect du cône, one-taps attendus par arme et par distance, tirs
pour tuer, pénétration ; table de TTK régénérée (`tools/weapon_table.luau`).

## Phase 4 — Vérité serveur ✅ 🔶

- `CharacterService` (apparition, PV/bouclier, postures, historique de visée, assists),
  `LagCompensationService`, `CombatService` (13 contrôles par tir, rechargements, mêlée,
  killcam), `AntiCheatService` (mouvement, score de suspicion), `ArenaService`,
  `Server/GameEvents`.

**Critères de sortie :** 🔶 Studio, 2 joueurs, latence simulée de 0, 100 puis 200 ms : tirs
enregistrés là où le tireur visait (headshots compris, cibles en mouvement, lean, accroupi) ;
**aucun signalement** anti-exploit pendant 30 min de jeu normal (score < 10 dans les
journaux `[AntiCheat]`) ; un client modifié (Studio, script de test) qui tire trop vite, de
trop loin, ou se téléporte est neutralisé.

## Phase 5 — Ressenti client ✅ 🔶

- `InputController` (actions remappables, manette, tactile), `CameraController` (visée
  séparée du juice), `MovementController` (modèle « Source-like »), `ViewmodelController` +
  `Client/Weapons/*` (bras IK, armes procédurales, clips), `WeaponController` (prédiction),
  `EffectsController` (poolé), `AudioController` (groupes, occlusion, ducking),
  `LightingController`, `CharacterAnimator` (3e personne procédurale).

**Critères de sortie :** 🔶 60 FPS stables sur PC de milieu de gamme en match ; counter-strafe
mesurable en ≤ 3 frames ; patterns de recul reproductibles d'un spray à l'autre ; aucune
couche de juice ne décale les impacts (test : tir sur cible fixe avec secousse maximale) ;
revue de sensation par 3 joueurs FPS confirmés (grille : réactivité, lisibilité, poids des
armes, audio).

## Phase 6 — Cartes ✅ 🔶

- `Server/Maps/MapKit` (primitives, matériaux, couvertures), `MapBuilder` (instanciation,
  zones, spawns, intro), plans `Kestrel`, `Helix`, `Spire`, `Monolith`, `Hub` ;
  `Shared/Config/Maps` (modes, ambiances, astuces).

**Critères de sortie :** ✅ tests : spawns, sites, callouts, limites, **aucune ligne de vue
entre spawns adverses** ; 🔶 parcours de chaque carte : aucun point de blocage, aucun angle
« pixel » exploitable, temps de rotation attaque/défense mesurés (écart ≤ 2 s entre les deux
sites d'une carte Squad).

## Phase 7 — Boucle de match ✅ 🔶

- `Shared/Rules/MatchRules`, `Server/Match/MatchInstance` (phases, Uplink, prolongations,
  changements de côté, clutchs/aces), `MatchService` (local + serveur réservé),
  `MatchController` (intro, killcam, spectateur, chargements, fin de match), `HUDController`,
  `TransitionController`, `MobileController`.

**Critères de sortie :** ✅ tests de règles (premier à N, prolongation, mort subite, Uplink,
temps écoulé, manches pistolet) ; 🔶 matchs complets dans **chaque mode** (Duel 1v1, Wingman
2v2, Squad 3v3, Clash) avec 2 à 6 joueurs ; déconnexion et retour en cours de match ; forfait ;
prolongation jouée jusqu'à la mort subite.

## Phase 8 — Méta et hub ✅ 🔶

- `ProgressionService` (XP, niveaux, Pass, MMR/RR), `MissionService`, `InventoryService`,
  `StoreService`, `PurchaseService`, `LeaderboardService`, `PartyService`,
  `MatchmakingService` (local + MemoryStore), `CustomGameService`, `TrainingRangeService`,
  `SettingsService` ; lobby client (`LobbyController`, onglets Play / Armory / Locker /
  Progress, `PostMatch`, `HubWorld`), `SettingsPanel`.

**Critères de sortie :** ✅ tests RankMath, matchmaking (équilibre, party non séparée, fenêtres),
missions, catalogue ; 🔶 en live (expérience publiée, comptes de test) : party de 3 → file
classée → match sur serveur réservé → retour au hub avec écran de progression exact (XP, RR,
niveau) ; rejoin après déconnexion ; estimation de file cohérente avec l'attente réelle.

---

## Phase 9 — Intégration Studio et premiers play-tests ⬜ (prochaine étape)

L'ordre exact de la première session :

1. **Outils** : `rokit install`, puis `./scripts/analyze.sh && ./scripts/test.sh &&
   ./scripts/build.sh` (tout doit être vert).
2. **Ouvrir** `build/AetherStrike.rbxl` dans Studio, ou `rojo serve` + plugin Rojo pour la
   synchronisation en direct.
3. *(Optionnel)* Game Settings → Security → **Enable Studio Access to API Services** :
   DataStore réel sur une clé dédiée à Studio. Sinon, magasin en mémoire (même sémantique).
4. **Solo** (Play) : hub en 3e personne, terminaux, armurerie, casier, réglages ; Training
   Range en 1re personne (cibles, statistiques, rechargements, toutes les armes).
5. **Test → Clients and Servers, 2 joueurs** : file Duel → match **local** (en Studio, le
   matchmaking lance les matchs sur une arène du serveur) → match complet → retour au hub et
   écran de progression.
6. **4 puis 6 joueurs** : Wingman (site unique), Squad (sites A/B, Uplink, désamorçage),
   Clash ; killcam, spectateur, changement de côté, prolongation.
7. **Réseau** : latence simulée (Studio Settings → Network → *Incoming Replication Lag*,
   0.1 puis 0.2 s) ; vérifier l'enregistrement des tirs et l'absence de signalements
   anti-exploit.
8. **Mobile** : émulateur d'appareils (téléphone 16:9 et 20:9, tablette) : contrôles tactiles,
   échelle de l'interface, assistance de visée.
9. **Live privé** : publier l'expérience, renseigner les `productId` réels si la boutique doit
   être testée, puis valider téléportations, serveurs réservés, matchmaking MemoryStore,
   transmission du verrou de session et rejoin, avec au moins 6 comptes.

**Classes de défauts attendues** (code jamais exécuté dans le moteur) : alignements du
viewmodel procédural (offsets d'armes, de bras, de visée), chevauchements d'interface à
certains ratios, équilibre des volumes (sons intégrés provisoires), accrochages de collision
sur les cartes, cas limites du Humanoid (marches, pentes, plafonds bas) dans le modèle de
mouvement, ordres d'arrivée d'attributs au spawn. Chacun se corrige dans un module isolé ;
aucun ne remet en cause l'architecture.

**Critères de sortie :** tous les critères 🔶 des phases 2 à 8 validés ; liste de défauts
priorisée et vide de bloquants.

## Phase 10 — Production audio et visuelle ⬜

- **Son** : pack d'armes (corps, mécanique, queues intérieures/extérieures, variantes
  lointaines), Foley (pas par matériau, équipement), interface, annonces, **musique** (le
  groupe `Music` est câblé : volume, ducking). Intégration = remplacer les `ids` des clés de
  `Shared/Config/Sounds.luau`, **sans toucher au code**.
- **Visuel** : textures de particules et de décalques dédiées, icônes d'interface, éventuels
  modèles d'armes en mesh (le système actuel est procédural : `WeaponModels` décrit les pièces),
  tenues d'opérateurs supplémentaires, illustrations de cartes pour le lobby.
- **Boutique** : création des Developer Products et report des `productId` dans
  `Shared/Config/Products.luau` (une offre à 0 reste masquée).

**Critères de sortie :** plus aucun son provisoire ; revue de cohérence de la direction
artistique « futuriste froid et premium » sur toutes les cartes et menus.

## Phase 11 — Équilibrage piloté par la télémétrie ⬜

- Événements `AnalyticsService` : taux de choix et de victoire par arme, TTK observé,
  précision par arme, victoires attaque/défense par carte et par site, durée des manches,
  temps de file par mode et par rang, distribution du MMR, distribution des corrélations
  `SpreadAudit` et des signalements anti-exploit.
- Bêta fermée (joueurs FPS confirmés + nouveaux joueurs) ; boucle : mesure → modification de
  **configuration uniquement** (`Weapons.luau`, `Movement.luau`, `GameModes.luau`) →
  `./scripts/test.sh` (les one-taps et tirs pour tuer sont des contrats testés) →
  `tools/weapon_table.luau` → déploiement.

**Critères de sortie :** victoires attaque/défense entre 45 et 55 % sur chaque carte ; aucune
arme dominante hors de son rôle ; temps de file médian < 60 s aux heures creuses ; seuil
`SpreadAudit` calibré sur la distribution réelle des joueurs légitimes.

## Phase 12 — Performance, réseau, mobile ⬜

- Budgets (MicroProfiler) : client < 16.6 ms par frame sur PC de référence, < 33 ms sur
  mobile de référence ; serveur de match < 8 ms par `Heartbeat` à 6 joueurs ; lobby à pleine
  capacité sans dégradation.
- Réseau : débit par client mesuré (console développeur) en match, objectif < 50 Ko/s ;
  vérifier les paquets non fiables (`LookBatch`, `ShotVisual`) sous perte simulée.
- Mobile : mémoire, `StreamingEnabled` (rayons par carte), qualité graphique adaptative
  (bloom, profondeur de champ, rayons, flashs réduits déjà réglables).

**Critères de sortie :** budgets tenus sur les appareils de référence ; aucune fuite de
mémoire sur 10 matchs consécutifs dans le même serveur lobby.

## Phase 13 — Sécurité : test d'intrusion autorisé ⬜

Sur une expérience de test privée, avec des outils d'exploitation utilisés **par l'équipe
uniquement** : fuzzing de chaque remote (types, tailles, fréquences), speedhack, téléportation,
noclip, vol, cadence de tir, origine de tir déportée, no-spread par pré-compensation,
rejeu de paquets, manipulation des achats et de l'inventaire.

**Critères de sortie :** chaque attaque est **neutralisée** (sans effet) ou **détectée**
(signalement puis expulsion) ; aucune n'affecte un autre joueur ou une donnée persistée ;
procédure de modération (signalements, revue de killcams, sanctions, appels) documentée.

## Phase 14 — Lancement et live ops ⬜

- Lancement progressif (serveurs limités), surveillance des journaux, des quotas DataStore et
  MemoryStore, du taux d'erreurs et des temps de file.
- Saison 1 : contenu du Pass, rotation de missions, boutique rotative, événements ; saison
  suivante = nouvelle valeur de `PASS_SEASON` + migration de profil testée.
- Rituels : rapport hebdomadaire d'équilibrage, revue mensuelle anti-exploit, sondage de
  sensation après chaque patch d'armes.

---

## Estimation indicative des phases restantes

Hypothèse d'équipe : 2 programmeurs gameplay, 1 technical designer, 1 artiste 3D/VFX, 1 sound
designer à temps partiel, testeurs communautaires. Estimation **à réviser après la phase 9**.

| Phase | Durée indicative | Parallélisable avec |
|---|---|---|
| 9 — Intégration et play-tests | 1 à 2 semaines | — |
| 10 — Production audio/visuelle | 4 à 8 semaines | 11, 12 |
| 11 — Équilibrage (bêta fermée) | 3 à 4 semaines | 10, 12 |
| 12 — Performance et mobile | 2 à 3 semaines | 10, 11 |
| 13 — Test d'intrusion | 1 à 2 semaines | fin de 11–12 |
| 14 — Lancement, saison 1 | 8 semaines par saison | — |

## Risques et parades

| Risque | Conséquence | Parade |
|---|---|---|
| Quotas MemoryStore (proportionnels au nombre de joueurs) | file bloquée à forte charge | un seul leader, TTL des tickets, repli automatique sur le matchmaking local ; mesurer le coût du polling (1 lecture par ticket et par seconde) en phase 12 |
| Limitation DataStore | sauvegardes retardées | budget vérifié avant chaque écriture, autosave étalée, nouvelles tentatives, sauvegarde finale bornée à 25 s |
| Triche côté client (aimbot, ESP) | intégrité compétitive | serveur autoritaire, heuristiques pondérées, télémétrie, modération ; aucune solution parfaite sur Roblox : l'objectif est de rendre la triche coûteuse et détectable |
| Sensation non validée en jeu | rétention | phase 9 dédiée ; tous les réglages de feeling centralisés en configuration |
| Coût mobile (effets, viewmodel, interface) | FPS insuffisants | pools, LOD de la 3e personne, options graphiques ; mesures en phase 12 |
| Évolutions de l'API Roblox (contrôleurs de personnage, remotes) | régressions | couches isolées, analyse stricte sur définitions à jour, logique pure testée hors moteur |
| Contenu provisoire (sons intégrés, `productId` à 0) | qualité perçue, revenus | phase 10 ; tout est centralisé en configuration |

## Définition de « terminé » pour chaque modification de code

1. `./scripts/analyze.sh` : 0 erreur en mode strict.
2. `./scripts/test.sh` : tous les tests verts ; un test ajouté pour toute règle pure modifiée.
3. `stylua src tests` appliqué.
4. `python3 tools/require_graph.py --check` : aucun cycle ni `require` non résolu.
5. `python3 tools/doc_excerpts.py` relancé si un extrait documenté a changé (`--check` vert).
6. `./scripts/build.sh` : place construite.
7. Pour toute modification de gameplay : vérification en Studio (2 clients) avant fusion.

---

## Annexe A — Ordre de construction fichier par fichier

Généré par `python3 tools/require_graph.py --markdown` à partir du graphe de `require` réel
(104 modules, 511 dépendances). La couche d'un module vaut 1 + la couche maximale de ses
dépendances : en construisant les couches dans l'ordre, chaque module n'utilise que du code
déjà écrit et testable. Au sein d'une couche, l'ordre est libre (travail parallélisable).

| Couche | Modules |
|---|---|
| 0 | `ReplicatedFirst/LoadingScreen` · `Server/Character/Ragdoll` · `Server/Maps/MapKit` · `Server/ServerRole` · `Shared/Combat/SpreadAudit` · `Shared/Config/GameModes` · `Shared/Config/Missions` · `Shared/Config/Movement` · `Shared/Config/Products` · `Shared/Config/Progression` · `Shared/Config/Ranks` · `Shared/Config/RecoilPatterns` · `Shared/Config/Sounds` · `Shared/Config/Theme` · `Shared/Net/LookCodec` · `Shared/Net/Net` · `Shared/Replica/ReplicaPath` · `Shared/Types` · `Shared/Util/Guard` · `Shared/Util/Janitor` · `Shared/Util/Logger` · `Shared/Util/MathUtil` · `Shared/Util/Pool` · `Shared/Util/RateLimiter` · `Shared/Util/Signal` · `Shared/Util/Spring` · `StarterCharacterScripts/Animate` · `StarterCharacterScripts/Health` · `StarterPlayerScripts/RbxCharacterSounds` |
| 1 | `Client/Controllers/EffectsController` · `Client/Core/ReplicaController` · `Client/Lobby/Remote` · `Client/UI/UI` · `Client/Weapons/Animator` · `Client/Weapons/WeaponModelBuilder` · `ReplicatedFirst/Boot` · `Server/Character/OperatorGear` · `Server/GameEvents` · `Server/Maps/Blueprints/Helix` · `Server/Maps/Blueprints/Hub` · `Server/Maps/Blueprints/Kestrel` · `Server/Maps/Blueprints/Monolith` · `Server/Maps/Blueprints/Spire` · `Server/Maps/MapBuilder` · `Server/Net/ServerNet` · `Server/Services/ArenaService` · `Shared/Combat/Ballistics` · `Shared/Combat/Spread` · `Shared/Combat/Stances` · `Shared/Config/Maps` · `Shared/Config/Settings` · `Shared/Config/WeaponModels` · `Shared/Rules/MatchRules` · `Shared/Rules/MatchmakingAlgorithm` · `Shared/Rules/RankMath` |
| 2 | `Client/Controllers/TransitionController` · `Client/Core/ClientState` · `Server/Services/MapService` · `Server/Services/ReplicaService` · `Shared/Combat/Hitbox` · `Shared/Config/Weapons` |
| 3 | `Client/Controllers/SettingsController` · `Client/Lobby/PlayTab` · `Client/Lobby/PostMatch` · `Server/Services/LagCompensationService` · `Shared/Config/Cosmetics` |
| 4 | `Client/Controllers/AudioController` · `Client/Controllers/InputController` · `Client/Controllers/LightingController` · `Client/Lobby/ArmoryTab` · `Client/Lobby/HubWorld` · `Client/Lobby/LockerTab` · `Client/Lobby/ProgressTabs` · `Client/UI/SettingsPanel` · `Shared/Data/ProfileTemplate` |
| 5 | `Client/Controllers/CameraController` · `Server/Services/DataService` |
| 6 | `Client/Controllers/CharacterAnimator` · `Client/Controllers/MovementController` · `Server/Services/AntiCheatService` · `Server/Services/LeaderboardService` |
| 7 | `Client/Controllers/ViewmodelController` · `Server/Services/CharacterService` |
| 8 | `Client/Controllers/WeaponController` · `Server/Services/CombatService` · `Server/Services/PlayerService` |
| 9 | `Client/Controllers/HUDController` · `Client/Controllers/MobileController` · `Server/Match/MatchInstance` · `Server/Services/InventoryService` · `Server/Services/PartyService` · `Server/Services/SettingsService` · `Server/Services/TrainingRangeService` |
| 10 | `Client/Controllers/MatchController` · `Client/Lobby/LobbyController` · `Server/Services/ProgressionService` · `Server/Services/PurchaseService` |
| 11 | `Client/Main` · `Server/Services/MatchService` · `Server/Services/MissionService` · `Server/Services/StoreService` |
| 12 | `Server/Services/CustomGameService` · `Server/Services/MatchmakingService` |
| 13 | `Server/Main` |

Lecture : les fondations critiques de [10-code.md](10-code.md) occupent les couches 0 à 8 —
c'est pour cela qu'elles se construisent, se testent et se valident **avant** le HUD, le
lobby et la méta, qui ne font que les consommer.
