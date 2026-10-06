# 2. Architecture globale et structure de dossiers

## 2.1 Vue d'ensemble

```
                    ┌──────────────────────── ROBLOX CLOUD ─────────────────────────┐
                    │  DataStore "AetherStrike_Profiles_v1"   (profils, verrou)      │
                    │  OrderedDataStore "AetherStrike_Ladder_S1" (classement)        │
                    │  MemoryStore : AS_MMQ_<file> (SortedMap, tickets TTL 90 s)     │
                    │                AS_MMLock (leader 8 s) · AS_MMAssign            │
                    │                AS_MatchSpecs (spec par PrivateServerId)        │
                    │                AS_ActiveMatch (reprise de match)               │
                    └──────────────▲───────────────────────────────▲─────────────────┘
                                   │                               │
   ┌───────────────────────────────┴──────┐        ┌───────────────┴──────────────────┐
   │ SERVEUR LOBBY (public)               │ Telep. │ SERVEUR MATCH (réservé)           │
   │  Hub "AETHER HQ"  , party, file,    │──────► │  lit sa MatchSpec dans MemoryStore│
   │  Training Range, salons perso,       │◄────── │  1 MatchInstance, arène persist.  │
   │  progression, boutique, classement   │ retour │  combat, manches, récompenses     │
   └──────────────▲───────────────────────┘        └───────────────▲──────────────────┘
                  │ remotes (Net)                                  │ remotes (Net)
          ┌───────┴────────┐                               ┌───────┴────────┐
          │ CLIENT (hub)   │                               │ CLIENT (match) │
          └────────────────┘                               └────────────────┘
```

**Une seule place, deux rôles** (`Server/ServerRole.luau`) :
- **Lobby** = serveurs publics. Hub, parties, matchmaking, Training Range, salons
  personnalisés (joués *localement* sur une arène du serveur lobby).
- **Match** = serveurs **réservés** (`TeleportService:ReserveServer`) créés par le
  matchmaker. Détection : `game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0`.
  Ils lisent leur `MatchSpec` dans MemoryStore (clé = `PrivateServerId`) — **jamais** dans
  les TeleportData, falsifiables par le client.
- **Studio** : toujours Lobby ; le matchmaker lance des matchs **locaux** (même serveur,
  arène dédiée décalée de 1600 studs). Toute la boucle se teste avec
  *Test → Start (Server + 2 Players)*. `Workspace:SetAttribute("ForceRole", "Match")`
  permet de forcer un rôle.

Avantages : une seule codebase, un seul déploiement, **aucune divergence de version**
entre lobby et match ; la même logique de match tourne en local (Studio, salons perso) et
sur serveur réservé (production).

## 2.2 Démarrage

**Serveur** (`Server/Main.server.luau`) :
1. `Net.setup()` crée tous les remotes (`ReplicatedStorage.Remotes/<Dossier>/<Nom>`).
2. `Workspace:SetAttribute("ServerRole", …)`.
3. `Init()` des 21 services dans l'ordre `ORDER` (aucun appel croisé), puis `Start()`
   dans le même ordre. Chaque appel est protégé (`Logger.safe`) : un service en échec est
   journalisé sans bloquer les autres.
4. `Workspace:SetAttribute("ServerReady", true)`.

Ordre : Data → Replica → AntiCheat → Arena → Map → LagCompensation → Character → Player →
Combat → Inventory → Leaderboard → Progression → Mission → Store → Settings → Purchase →
Match → Party → Matchmaking → CustomGame → TrainingRange.

**Client** :
1. `ReplicatedFirst/Boot.client.luau` (1re frame) : `RemoveDefaultLoadingScreen`, écran du
   jeu (ou reprise de l'écran de téléportation), attente de `game.Loaded` puis de l'attribut
   `ClientBooted`.
2. `StarterPlayerScripts/Client/Main.client.luau` : désactive l'UI Roblox superflue (garde le
   chat), démarre les contrôleurs, câble l'audio des déplacements, applique le mode de
   caméra de l'arène, pose `ClientBooted` quand le profil est reçu (ou après 30 s).
3. `StarterCharacterScripts/Animate` joue les animations Roblox standard (ou le pack de
   l'avatar) : repos, marche, course, saut, chute ; en combat, `CharacterAnimator` réécrit
   les articulations par-dessus. `Health` et `StarterPlayerScripts/RbxCharacterSounds` sont
   **neutralisés** : santé autoritaire, sons de pas maison.

## 2.3 Flux d'un tir, de la souris au killfeed

```
CLIENT (0 ms)                                         SERVEUR (≈ ping/2)
───────────────────────────────────────────────       ──────────────────────────────────────────
WeaponController.step (RenderStep Camera+3)
 ├ cadence (planning exact, rafale, spin-up)
 ├ cône = Spread.cone(état local)
 ├ FirePacket {w, n, o, a, s, t, ads} ──────────────► CombatService.onFire
 ├ directions = Spread.directions(a, s,                ├ 1 contexte (vivant, phase ouverte, pas Busy)
 │      seed(graine, n))  ← mêmes que serveur          ├ 2 arme équipée = w, équipement écoulé
 ├ trace() : monde + Hitbox des cibles visibles        ├ 3 n == compteur attendu (sinon resync)
 │   + pénétration (miroir serveur)                    ├ 4 munitions (rechargement en cours ?)
 ├ effets prédits : flash, douille, traceur,           ├ 5 cadence (même arme) + fenêtre 1 s
 │   impacts, impact sur cible (sans hitmarker)        ├ 6 origine ≤ 3.5 + 0.35·v de l'oeil serveur
 ├ recul réel (CameraController.addRecoil)             ├ 7 cône ≥ cône minimal plausible
 └ recul visuel (Viewmodel), punch, shake              ├ 8 vitesse angulaire implicite
                                                       ├ 9 directions recalculées (même graine),
                                                       │   raycast monde + hitboxes REMBOBINÉES
                                                       │   (LagCompensationService), pénétration
                                                       └ 10 dégâts (bouclier 66 %), kill, assists
                                       ◄──────────────── ShotResult {n, w, hits[]} (tireur)
HUDController : hitmarker CONFIRMÉ,                    ── DamageTaken (victime : indicateur)
 chiffres de dégâts cumulés, sons de touche/kill       ── Kill (toute l'arène : killfeed, effet)
                                                       ── Killcam (victime : 3 s de pistes)
CharacterAnimator (autres clients) ◄────────────────── ShotVisual (non fiable : traceur, son 3D)
```

Propriétés clés :
- **Zéro faux hitmarker** : le hitmarker attend `ShotResult`. Ce qui est immédiat (flash,
  son, recul, impact sur la cible prédite) ne promet pas de dégâts.
- **Même balle des deux côtés** : `Spread.seed(seedBase, n)` — `seedBase` est attribué par le
  serveur (`AmmoSync`), `n` est séquentiel. Un client ne peut ni choisir sa graine, ni
  déclarer un cône nul (rejeté au profit du cône minimal + signalement) ; s'il exploite sa
  connaissance de la graine pour pré-compenser la dispersion, `SpreadAudit` le détecte.
- **Auto-réparation** : tout refus serveur renvoie `AmmoSync` ; le client repart de la
  vérité serveur (compteur, chargeurs, graine).

## 2.4 Réplication d'état

| Replica | Contenu | Destinataires | Écrit par |
|---|---|---|---|
| `PlayerProfile` | `ProfileData` (sauf `Moderation`, `Purchases`) | le joueur | `PlayerService.set/increment` |
| `MatchState` | `MatchStateData` (phase, timer, scores, côtés, joueurs, objectif, historique) | participants | `MatchInstance` |
| `Party` | `PartyData` (membres, leader, mode, verrou, file, invitations) | membres | `PartyService`, `MatchmakingService` |
| `TrainingStats` | tirs, touches, têtes, kills, dégâts, boucliers | le joueur | `TrainingRangeService` |
| `Leaderboard` | top saison | tous | `LeaderboardService` |
| `CustomRoom` | code, hôte, mode, carte, membres/équipes | membres | `CustomGameService` |

Attributs publics (lus par tous, peu fréquents) : `Player.Arena/ArenaKind/NetSlot/Level/
RankIndex/Placed/Title/Operator/Banner`, `Character.Team/Side/Stance/Lean/Ads/Walking/
Alive/Armor/Weapon/Skin/Busy/Emote`.

## 2.5 Inventaire des remotes (`Shared/Net/Net.luau`)

| Dossier | Remote | Type | Sens | Débit max (jetons / recharge par s) |
|---|---|---|---|---|
| Combat | `Fire` | Event | C→S | 24 / 20 |
| Combat | `Reload` | Event | C→S | 4 / 2 |
| Combat | `Equip` | Event | C→S | 10 / 6 |
| Combat | `Melee` | Event | C→S | 6 / 4 |
| Combat | `ShotResult`, `DamageTaken`, `Kill`, `AmmoSync` | Event | S→C | — |
| Combat | `ShotVisual` | Unreliable | S→C | — |
| Movement | `Stance` | Event | C→S | 24 / 16 |
| Movement | `LookUpdate` | Unreliable | C→S | 40 / 34 |
| Movement | `LookBatch` | Unreliable | S→C | 20 Hz |
| Match | `Interact` | Event | C→S | 8 / 4 |
| Match | `LoadoutSelect` | Event | C→S | 8 / 3 |
| Match | `MatchEvent`, `Killcam` | Event | S→C | — |
| Lobby | `Notify`, `MatchFound` | Event | S→C | — |
| Lobby | `SettingsSave` | Event | C→S | 3 / 0.5 (+ validation complète `Settings.validate`) |
| Lobby | `Emote` | Event | C→S | 3 / 0.5 |
| Lobby | `PartyAction`, `QueueAction`, `InventoryAction`, `MissionAction`, `ShopAction`, `TrainingAction`, `CustomAction`, `ProfileQuery` | Function | C→S | 6–8 / 1–4 |
| Replica | `ReplicaCreate/Update/Destroy` | Event | S→C | — |
| Replica | `ReplicaRequest` | Event | C→S | 1 au démarrage |
| Admin | `AdminCommand` | Event | — | **pot de miel** |

## 2.6 Structure de dossiers (détaillée)

```
roblox/
├── default.project.json        Projet Rojo : services, propriétés (streaming, éclairage, starter)
├── rokit.toml                  Versions d'outils épinglées (rojo, luau-lsp, stylua, lune)
├── .luaurc · stylua.toml       Mode strict, style de code
├── scripts/
│   ├── analyze.sh              Analyse stricte luau-lsp contre l'API Roblox réelle
│   ├── build.sh                Construit build/AetherStrike.rbxl
│   └── test.sh                 Lance les tests Lune
├── tests/
│   ├── run.luau                Runner (describe/it/expect/eq/near)
│   ├── lib/loader.luau         Arbre d'instances virtuel + shims (Random PCG32, task, game)
│   └── specs/                  combat · rules · util · maps (91 tests)
├── tools/
│   ├── export_maps.luau        Blueprints -> build/maps/*.json
│   ├── render_maps.py          JSON -> vues de dessus PNG (docs/maps)
│   └── weapon_table.luau       Config -> tableaux Markdown de docs/07
├── docs/                       Ce dossier (11 sections + rendus de cartes)
└── src/
    ├── ReplicatedFirst/        Boot (1re frame) + LoadingScreen (autonome, téléportations)
    ├── Shared/                 -> ReplicatedStorage.Shared (client + serveur)
    │   ├── Types.luau          Contrat de types unique
    │   ├── Util/               Signal · Janitor · Spring · Logger · RateLimiter · Pool · MathUtil · Guard
    │   ├── Combat/             Stances · Hitbox · Spread · Ballistics (géométrie et maths partagées)
    │   ├── Config/             Weapons · WeaponModels · RecoilPatterns · Movement · GameModes · Maps
    │   │                       Ranks · Progression · Cosmetics · Missions · Settings · Sounds · Theme · Products
    │   ├── Net/                Net (registre des remotes) · LookCodec (visée binaire)
    │   ├── Replica/            ReplicaPath (opérations par chemin)
    │   ├── Data/               ProfileTemplate (schéma, migrations, réconciliation)
    │   └── Rules/              MatchRules · MatchmakingAlgorithm · RankMath (purs, testés)
    ├── Server/                 -> ServerScriptService.Server
    │   ├── Main.server.luau    Bootstrap (ordre des services)
    │   ├── ServerRole.luau     Lobby / Match
    │   ├── GameEvents.luau     Bus d'événements de gameplay
    │   ├── Net/ServerNet.luau  Branchement sécurisé des remotes
    │   ├── Character/          OperatorGear (tenues) · Ragdoll
    │   ├── Maps/               MapKit (DSL) · MapBuilder · Blueprints/{Hub, Kestrel, Helix, Spire, Monolith}
    │   ├── Match/              MatchInstance (machine à états + Uplink)
    │   └── Services/           21 services (voir 03-modules.md)
    ├── Client/                 -> StarterPlayerScripts.Client
    │   ├── Main.client.luau    Point d'entrée
    │   ├── Core/               ReplicaController · ClientState
    │   ├── Controllers/        Input · Settings · Camera · Movement · Viewmodel · Weapon · CharacterAnimator
    │   │                       Audio · Lighting · Effects · HUD · Match · Transition · Mobile
    │   ├── Weapons/            WeaponModelBuilder · Animator (clips procéduraux)
    │   ├── Lobby/              LobbyController · PlayTab · ArmoryTab · LockerTab · ProgressTabs
    │   │                       PostMatch · HubWorld · Remote
    │   └── UI/                 UI (kit) · SettingsPanel
    ├── StarterPlayerScripts/   RbxCharacterSounds neutralisé
    └── StarterCharacterScripts/ Animate (locomotion standard), Health neutralisé
```

## 2.7 Conventions

- **Un module = une responsabilité**, un en-tête qui explique le *pourquoi*.
- **Données = config** : armes, cartes, modes, rangs, missions, cosmétiques, sons sont des
  tables typées ; le code ne contient pas de valeurs de gameplay en dur.
- **Pur d'abord** : toute règle testable vit dans `Shared/Rules` ou `Shared/Combat`.
- **Autorité** : le serveur décide (santé, munitions, morts, progression, inventaire,
  monnaie) ; le client prédit et présente.
- **Cycle de vie** : `Janitor` par objet de vie (match, contrôleur), `Signal` pour le
  découplage, aucun `while true` sans condition de sortie dans le gameplay.
- **Chaînes de l'interface en français**, code et identifiants en anglais.
