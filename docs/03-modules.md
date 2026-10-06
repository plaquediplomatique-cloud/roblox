# 3. Liste complète des ModuleScripts / Services et responsabilités

104 modules Luau strict. Pour chacun : responsabilité, API principale, dépendances notables.
Chemins relatifs à `src/`. « Pur » = aucune dépendance moteur, testé sous Lune.

## 3.1 Shared — partagé client/serveur (`ReplicatedStorage.Shared`)

### Contrat
| Module | Responsabilité | API |
|---|---|---|
| `Types` | Source unique de tous les types : primitives (`HitZone`, `Stance`, `TeamId`, `Side`, `ArenaKind`, `WeaponSlot`, `FireMode`, `Rarity`…), config d'armes, cosmétiques, paquets réseau, état de match, file/party, profil, cartes | types exportés |

### Util
| Module | Responsabilité | API |
|---|---|---|
| `Util/Signal` | Événement Lua pur (style GoodSignal) : aucune copie, isolation des erreurs, thread réutilisé | `new`, `Connect`, `Once`, `Fire`, `Wait`, `DisconnectAll` |
| `Util/Janitor` | Cycle de vie déterministe : connexions, instances, threads, callbacks | `new`, `Add`, `Connect`, `Cleanup` |
| `Util/Spring` | Ressorts amortis à intégration **analytique** (exacte quel que soit `dt`) | `number`, `vector`, `step`, `impulse`, `snap` |
| `Util/Logger` | Journal catégorisé, niveaux, historique circulaire, `safe` (pcall journalisé) | `new`, `debug/info/warn/error`, `safe` |
| `Util/RateLimiter` | Seau à jetons par clé (anti-spam des remotes) | `new`, `consume`, `peek`, `reset` |
| `Util/Pool` | Réutilisation d'objets coûteux (Parts d'effets, Attachments…) | `new`, `prewarm`, `get`, `release`, `active`, `destroy` |
| `Util/MathUtil` | Maths de gameplay : lerp/damp, angles, rayon/OBB, rayon/sphère, hash et graines | `rayOBB`, `raySphere`, `combineSeed`, … |
| `Util/Guard` | Validation stricte des données entrantes | `shape`, `string`, `integer`, `range`, `number`, `boolean`, `vector3`, `unitVector`, `oneOf`, `optional`, `dictionary`, `hexColor` |

### Combat (pur, partagé — même résultat client et serveur)
| Module | Responsabilité |
|---|---|
| `Combat/Stances` | Géométrie de chaque posture : hauteur, oeil, hitboxes, sphère englobante ; transformation de lean (caméra = hitbox) |
| `Combat/Hitbox` | Rayon vs OBB (broadphase sphère → narrowphase boîtes), zone touchée la plus proche, centre/tête |
| `Combat/Spread` | Cône (hanche/ADS, mouvement au-delà de 34 % de la vitesse, air, accroupi, bloom, 1re balle), directions **déterministes**, motif des plombs |
| `Combat/SpreadAudit` | Détection « no-spread » : corrélation, par fenêtres de 40 paires de tirs, entre la variation de visée et le décalage de dispersion connu d'avance |
| `Combat/Ballistics` | Dégâts (zone × chute × pénétration), bouclier (66 %), pénétration par matériau/épaisseur (2 surfaces max), tirs pour tuer |

### Config (données typées)
| Module | Contenu |
|---|---|
| `Config/Weapons` | 14 armes (13 à feu + lame), profils complets, `minInterval`, `currentRpm`, `reloadCapacity` (+1 chambrée) |
| `Config/WeaponModels` | Archétypes procéduraux (fusil, pistolet, revolver, lame), viseurs, points d'ancrage |
| `Config/RecoilPatterns` | Construction lisible des patterns (segments), total sur N tirs |
| `Config/Movement` | Paramètres du contrôleur (vitesses, friction, glissade, lean, caméra, pas) |
| `Config/GameModes` | Duel, Wingman, Squad, Clash2, Clash3 : tailles, manches, temps, Uplink, prolongations |
| `Config/Maps` | Métadonnées + `LightingProfile` des 5 cartes |
| `Config/Ranks` | 8 paliers × 3 divisions (+ AETHER), couleurs, glyphes, MMR attendu |
| `Config/Progression` | XP par action, courbe de niveaux (200), récompenses de niveau, Aether Pass (50 paliers) |
| `Config/Cosmetics` | Skins (8 lignes × 14 armes), opérateurs, effets de kill, emotes, bannières, titres ; raretés et prix |
| `Config/Missions` | Pools quotidiens/hebdomadaires, tirage déterministe, filtres |
| `Config/Settings` | Défauts, bornes, validation, actions rebindables, couleurs ennemies |
| `Config/Sounds` | Bibliothèque logique (clés → ids, volume, pitch, groupe, rolloff) |
| `Config/Theme` | Couleurs, polices, transparences, courbes de tween |
| `Config/Products` | Produits Robux (masqués tant que `productId = 0`) |

### Réseau, réplication, données, règles
| Module | Responsabilité |
|---|---|
| `Net/Net` | Registre de **tous** les remotes (type + dossier), création serveur, résolution client |
| `Net/LookCodec` | Visée en `buffer` : 4 octets C→S, 5 octets/joueur S→C |
| `Replica/ReplicaPath` | Opérations par chemin (`Set`, `SetValues`, `ArrayInsert`, `ArrayRemove`, `Increment`), copie profonde, préfixes |
| `Data/ProfileTemplate` | Schéma du profil, `VERSION`, migrations, réconciliation (ajout des champs et objets de départ manquants) |
| `Rules/MatchRules` | **Pur** : fin de manche (élimination, détonation, désamorçage, temps), prolongations, balle de match, vainqueur |
| `Rules/MatchmakingAlgorithm` | **Pur** : fenêtres MMR/rang qui s'élargissent, sélection de tickets, partition équilibrée |
| `Rules/RankMath` | **Pur** : Elo d'équipe, K variable, RR (base, convergence, performance), promotions |

## 3.2 Server — `ServerScriptService.Server`

### Noyau
| Module | Responsabilité |
|---|---|
| `Main.server` | Bootstrap : `Net.setup`, rôle, `Init`/`Start` des 21 services, `ServerReady` |
| `ServerRole` | Lobby / Match (serveur réservé), forçage par attribut |
| `GameEvents` | Bus : `Kill`, `Damage`, `RoundEnd`, `MatchEnd`, `Objective`, `TrainingHit`, `ShotFired` |
| `Net/ServerNet` | `onEvent` / `onUnreliable` / `onInvoke` : rate limit + parseur + exécution protégée ; `fireList` ciblé ; signalement des violations |

### Services (ordre de démarrage)
| Service | Responsabilité | API publique |
|---|---|---|
| `DataService` | Profils à verrou de session, autosave, migrations, magasin mémoire en Studio | `getProfile`, `getData`, `waitForProfile`, `saveNow`, `ProfileLoaded`, `ProfileReleasing` |
| `ReplicaService` | Réplication par deltas, clés privées, listes de destinataires | `new`, `Set`, `SetValues`, `ArrayInsert/Remove`, `Increment`, `AddPlayer/RemovePlayer`, `SetReplication`, `Destroy` |
| `AntiCheatService` | Échantillonnage 10 Hz : vitesse (rafale/soutenue), téléportation, noclip, vol, rubber-band ; score de suspicion pondéré | `flag`, `allowTeleport`, `getScore` |
| `ArenaService` | « Où est ce joueur ? » (Hub / Training / match précis), attributs `Arena` et `ArenaKind` | `set`, `get`, `idOf`, `sameArena`, `playersIn`, `Changed` |
| `MapService` | Construit le hub et les arènes (slots de 1600 studs), streaming persistant, éclairage | `hub`, `createArena`, `addArenaPlayer`, `releaseArena`, `applyLighting` |
| `LagCompensationService` | Historique des poses (64), rembobinage interpolé, raycast multi-cibles | `register`, `unregister`, `poseAt`, `rewindTime`, `raycast`, `history` |
| `CharacterService` | Spawn standardisé (HumanoidDescription, tenue), santé/bouclier autoritaires, postures et visée répliquées (LookBatch 20 Hz), assists, chute hors carte, emotes | `spawn`, `applyDamage`, `kill`, `despawn`, `eyePosition`, `getLook`, `lookHistory`, `assisters`, `health`, `Spawned`, `Died` |
| `PlayerService` | Cycle de vie joueur : replica de profil, attributs publics, toasts, retour au hub | `getReplica`, `set`, `increment`, `refreshPublic`, `notify`, `returnToHub`, `Ready` |
| `CombatService` | Gunplay autoritaire (pipeline 10 étapes), rechargements, équipement, mêlée, killcam | `arm`, `disarm`, `isArmed`, `setPhaseResolver`, `setFirstBloodResolver` |
| `InventoryService` | Inventaire, équipement, monnaie douce (Flux), achats | `owns`, `grant`, `addFlux`, `addCrystals`, `purchase` |
| `LeaderboardService` | Classement saisonnier (OrderedDataStore), replica `Leaderboard` | `submit` |
| `ProgressionService` | XP, niveaux, Pass, MMR/RR (RankMath), résumé post-match | `awardXP`, `claimPass`, `processMatch` |
| `MissionService` | Missions quotidiennes/hebdo : tirage, progression sur `GameEvents`, réclamation, reroll | (remote `MissionAction`) |
| `StoreService` | Achats en Flux, paliers du Pass | (remote `ShopAction`) |
| `SettingsService` | Sauvegarde validée des réglages | (remote `SettingsSave`) |
| `PurchaseService` | Robux : `ProcessReceipt` **idempotent** ; `PurchaseGranted` seulement après sauvegarde réussie, sinon annulation complète (reçu + octroi) | — |
| `MatchService` | Orchestration des `MatchInstance` (locale ou serveur réservé), remotes `Interact`/`LoadoutSelect`, retour au hub / téléportation | `startLocal`, `forPlayer`, `isInMatch` |
| `PartyService` | Parties de 1 à 3 : invitations (TTL), exclusion, promotion, verrou, mode | `ensure`, `get`, `byId`, `setQueue`, `Changed` |
| `MatchmakingService` | Files classées/casual, backend MemoryStore (cloud) ou local (Studio), estimation, réservation de serveur, reprise de match | (remote `QueueAction`) |
| `CustomGameService` | Salons personnalisés (code, équipes, mode, carte, lancement local) | (remote `CustomAction`) |
| `TrainingRangeService` | Stand de tir : zone, armement à réserve infinie, bots statiques/mobiles (Pathfinding), stats | (remote `TrainingAction`) |

### Cartes, match, personnage
| Module | Responsabilité |
|---|---|
| `Maps/MapKit` | **DSL déclaratif** de blockout jouable : `floor`, `wall`, `wallDoor`, `window`, `crate`, `cover`, `platform`, `ramp`, `pillar`, `spawn`, `barrier`, `modeBarrier`, `site`, `callout`, `zone`, `terminal`, `light`, `sign`, `bounds`… avec styles de matériaux |
| `Maps/MapBuilder` | Blueprint → `Model` : pièces, tags, attributs, panneaux, lumières, invites, filtrage par mode ; expose spawns/sites/callouts/barrières/intro ; validation (aucune ligne de vue entre spawns ennemis) en Studio |
| `Maps/Blueprints/*` | Hub (AETHER SPIRE), Kestrel, Helix, Spire, Monolith |
| `Match/MatchInstance` | Machine à états du match (Waiting → Intro → Prep → Live/Planted → RoundEnd → SideSwap → MatchEnd → Closed), Uplink (porteur, pose 4 s, désamorçage 7 s avec point de sauvegarde à 50 %, mèche 40 s), stats, clutch/ace/premier sang, forfait | 
| `Character/OperatorGear` | Équipement procédural de l'opérateur (casque, visière néon, gilet, épaulières, module dorsal) sans grossir la silhouette |
| `Character/Ragdoll` | Motor6D → BallSocketConstraints bornées, collisions dédiées, ownership serveur |

## 3.3 Client — `StarterPlayerScripts.Client`

### Noyau
| Module | Responsabilité |
|---|---|
| `Main.client` | Ordre de démarrage, audio des déplacements, mode caméra par arène, `ClientBooted` |
| `Core/ReplicaController` | Miroir des replicas, `listen(path)`, `onNew(token)`, `wait` |
| `Core/ClientState` | Arène courante, profil/match/party, équipe, menu ouvert ; signaux `ArenaChanged`, `ProfileReady`, `MatchChanged`, `PartyChanged`, `MenuChanged` |

### Contrôleurs
| Contrôleur | Responsabilité |
|---|---|
| `InputController` | Actions abstraites rebindables (clavier/souris, manette, virtuel tactile), suspension en menu |
| `SettingsController` | Réglages appliqués en direct, sauvegarde temporisée (1.5 s), validation |
| `CameraController` | Visée vs rendu, 5 modes, punch/shake/FOV, zoom et sensibilité ADS |
| `MovementController` | Déplacement Source-like, postures, lean, glissade, sauts, pas, envoi `Stance`/`LookUpdate` |
| `ViewmodelController` | Arme + bras IK en 1re personne, hanche↔visée, sway/bob/respiration/kick, mur, lunette, hit-stop |
| `WeaponController` | Planification des tirs, prédiction déterministe, recul + récupération, rechargements, équipement, inspection, mêlée, contrat `AmmoSync`/`ShotResult` |
| `CharacterAnimator` | Personnages 3e personne procéduraux (IK jambes/bras), visée répliquée, armes 3e personne, contours ennemis, plaques, tirs et pas des autres, effets de kill |
| `AudioController` | SoundGroups, couches de tir, occlusion, réverbération, ducking, bas PV, pas |
| `LightingController` | Profil de carte + couches dynamiques (dégâts, kill, bas PV, menu, lunette) |
| `EffectsController` | Pools : flashs, traceurs, impacts, trous, douilles, chargeurs, explosion, effets de kill |
| `HUDController` | Réticule dynamique, hitmarkers, chiffres de dégâts, vitals, munitions, killfeed, boussole, barre de match, scoreboard, bannières, toasts, indicateurs de dégâts, vignettes, lunette, stats d'entraînement |
| `MatchController` | Intro, préparation/équipement, bannières, objectif, killcam, spectateur, fin de match |
| `TransitionController` | Volets plein écran, flash, écran de téléportation |
| `MobileController` | Joystick, visée tactile, boutons, friction de visée |

### Armes, lobby, UI
| Module | Responsabilité |
|---|---|
| `Weapons/WeaponModelBuilder` | Construit un modèle d'arme + skin (palette, matériaux, néons animés, aura), pièces animées par Motor6D |
| `Weapons/Animator` | Clips procéduraux (équipement, rechargements par style, cartouches, culasse/pompe, inspection, mêlée) + lecteur à événements |
| `Lobby/LobbyController` | Barre d'identité, menu à onglets, terminaux, file, match trouvé, modales, emotes, caméra de menu, post-match |
| `Lobby/PlayTab` | Modes, classé/casual, party, invitations, recherche, salons personnalisés |
| `Lobby/ArmoryTab` | Loadout, stats calculées, TTK, skins, aperçu 3D |
| `Lobby/LockerTab` | Casier (équiper) et Boutique (acheter), emplacements d'emotes, produits Robux |
| `Lobby/ProgressTabs` | Missions, Aether Pass, Classement |
| `Lobby/PostMatch` | Résumé de match chorégraphié (XP, niveau, RR, rang) |
| `Lobby/HubWorld` | Vitrines d'armes 3D (skins équipés), mur de classement |
| `Lobby/Remote` | Appels de RemoteFunction avec toasts d'erreur et anti double-clic |
| `UI/UI` | Kit d'UI typé et responsive |
| `UI/SettingsPanel` | Écran de réglages complet (6 onglets, aperçu du réticule, rebinding) |

## 3.4 ReplicatedFirst
| Module | Responsabilité |
|---|---|
| `Boot.client` | 1re frame : écran de chargement (ou reprise après téléportation), attente du client prêt |
| `LoadingScreen` | Écran autonome (aucun `require`), animation, astuces, réutilisé pour `SetTeleportGui` |

## 3.5 Graphe de dépendances

Vérifié automatiquement (`python3 tools/require_graph.py --check`) : **aucun cycle de `require`** et aucun `require` non résolu sur les 104 modules (513 dépendances).
Couches (une couche ne dépend que des couches inférieures) :

```
Shared/Util ─► Shared/Combat, Config, Net, Replica, Data, Rules ─► Server/* et Client/*
Client : Core ─► Input/Settings ─► Camera ─► Movement ─► Audio/Lighting/Effects
        ─► Viewmodel ─► Weapon ─► CharacterAnimator ─► HUD ─► Match ─► Lobby
Server : ServerNet/GameEvents ─► Data/Replica/AntiCheat/Arena/Map/LagComp ─► Character
        ─► Player ─► Combat ─► Inventory/Progression/Missions/Store ─► Match ─► Party
        ─► Matchmaking/CustomGame/TrainingRange
```
