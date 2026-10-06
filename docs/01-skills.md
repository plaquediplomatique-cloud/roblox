# 1. Activation des Skills — et leur rôle exact dans AETHER STRIKE

> Règle de lecture : chaque compétence est **activée par du code qui existe** dans ce dépôt.
> Les chemins sont relatifs à `src/`. Rien ici n'est une intention : c'est une description
> de ce qui est implémenté, vérifié par l'analyse stricte (`scripts/analyze.sh`, 0 erreur sur
> 104 modules), les tests (`scripts/test.sh`, 91 tests) et le build Rojo (`scripts/build.sh`).

| # | Skill | Statut | Où ça vit |
|---|---|---|---|
| 1 | Luau strict, ModuleScripts typés | ✅ 100 % des fichiers | `Shared/Types.luau` + `--!strict` partout |
| 2 | Architecture scalable (Services, SRP, DI légère) | ✅ | `Server/Main.server.luau`, `Server/Services/*`, `Client/Main.client.luau` |
| 3 | Client-serveur impeccable | ✅ | `Shared/Net/Net.luau`, `Server/Net/ServerNet.luau`, `Shared/Util/Guard.luau` |
| 4 | DataStore + ProfileService + ReplicaService | ✅ équivalents maison | `Server/Services/DataService.luau`, `ReplicaService.luau`, `Client/Core/ReplicaController.luau` |
| 5 | CollectionService | ✅ | `Server/Maps/MapBuilder.luau` (tags), consommateurs client/serveur |
| 6 | TweenService + Spring | ✅ | `Shared/Util/Spring.luau`, `Client/UI/UI.luau` |
| 7 | Particules / Beams / Attachments optimisés | ✅ poolés | `Client/Controllers/EffectsController.luau`, `Shared/Util/Pool.luau` |
| 8 | Caméra avancée | ✅ | `Client/Controllers/CameraController.luau`, `ViewmodelController.luau` |
| 9 | SoundService + SoundGroups | ✅ | `Client/Controllers/AudioController.luau`, `Shared/Config/Sounds.luau` |
| 10 | UI responsive desktop + mobile | ✅ | `Client/UI/UI.luau`, `Client/Controllers/MobileController.luau` |
| 11 | Character controller custom | ✅ | `Client/Controllers/MovementController.luau`, `Shared/Config/Movement.luau` |
| 12 | Recul / bloom / spread / recovery | ✅ | `Shared/Combat/Spread.luau`, `Shared/Config/RecoilPatterns.luau`, `Client/Controllers/WeaponController.luau` |
| 13 | Hit detection autoritaire + lag compensation | ✅ | `Server/Services/CombatService.luau`, `LagCompensationService.luau`, `Shared/Combat/Hitbox.luau` |
| 14 | Anti-exploit | ✅ | `Server/Services/AntiCheatService.luau`, `ServerNet`, validations de `CombatService` |
| 15 | StreamingEnabled + écrans de chargement | ✅ | `default.project.json`, `MapService.luau`, `ReplicatedFirst/*` |
| 16 | Lighting + post-processing | ✅ | `Shared/Config/Maps.luau` (profils), `Client/Controllers/LightingController.luau` |
| 17 | Pathfinding | ✅ (bots du stand de tir) | `Server/Services/TrainingRangeService.luau` |
| 18 | Network ownership, mémoire, réseau | ✅ | `Ragdoll.luau`, `LookCodec.luau`, `Pool.luau`, `Janitor.luau`, LOD de `CharacterAnimator` |

---

## 1.1 Luau strict — un contrat de types unique

**Pourquoi.** Un FPS compétitif vit de contrats exacts entre client et serveur : un paquet de
tir, une config d'arme, un état de match. Une seule divergence = un bug de désynchronisation
impossible à reproduire. Le typage strict transforme ces bugs en erreurs de compilation.

**Comment.**
- **Tous** les fichiers commencent par `--!strict` ; `.luaurc` impose le mode strict.
- `Shared/Types.luau` est la **source unique** de tous les contrats : `WeaponDef` (et ses
  sous-profils `FireProfile`, `DamageProfile`, `SpreadProfile`, `RecoilProfile`…),
  paquets réseau (`FirePacket`, `ShotResult`, `HitReport`, `KillEvent`, `AmmoSyncPacket`,
  `KillcamPacket`, `MatchEventPacket`…), état répliqué (`MatchStateData`, `PartyData`,
  `QueueStatus`), profil persistant (`ProfileData`, `SettingsData`…), cartes
  (`LightingProfile`, `MapInfo`). Modifier un champ casse immédiatement l'analyse partout
  où il est utilisé.
- Les unions de singletons (`"Stand" | "Crouch" | "Slide"`, `"Primary" | "Secondary" | "Melee"`)
  remplacent les chaînes libres : une faute de frappe sur un nom d'action n'existe pas.
- Analyse réelle contre l'API Roblox : `scripts/analyze.sh` génère le sourcemap Rojo et
  lance `luau-lsp analyze` avec `globalTypes.d.luau` (définitions officielles). Les
  `require(script.Parent.X)` sont résolus via le sourcemap : un module mal référencé échoue.
- Pièges de l'ancien solveur gérés explicitement (élargissement des singletons, `x or {}`
  dans les boucles, `pcall` sur une fonction typée `() -> ()`) : annotations ciblées
  (`local stance: Types.Stance = …`) plutôt que `any`.

## 1.2 Architecture scalable — Services, SRP, injection légère

**Serveur.** `Server/Main.server.luau` charge **21 services** dans un ordre déclaré
(`ORDER`) et appelle `Init()` (création d'état, aucune dépendance runtime) puis `Start()`
(branchements). Chaque service a **une** responsabilité :
`DataService` persiste, `ReplicaService` réplique, `CombatService` résout les tirs,
`MatchService` orchestre les matchs, `MatchmakingService` forme les matchs, etc.

**Injection légère.** Les dépendances circulaires sont cassées par injection de
fonctions, pas par des `require` croisés :
- `CombatService.setPhaseResolver(fn)` / `setFirstBloodResolver(fn)` : c'est `MatchService`
  qui dit au combat « le combat est-il ouvert pour ce joueur ? ». Le combat ne connaît pas
  les matchs.
- `ServerNet.setViolationReporter(fn)` : la couche réseau signale les abus à
  l'`AntiCheatService` sans en dépendre.
- `GameEvents` (bus d'événements serveur) : `Kill`, `Damage`, `ShotFired`, `TrainingHit`,
  `Objective`… Les missions, la progression et les stats **écoutent** le combat ; le combat
  ne les appelle jamais.

**Client.** `Client/Main.client.luau` démarre les contrôleurs dans l'ordre des dépendances
(état → entrées → rendu → gameplay → interfaces), `ReplicaController.start()` **en dernier**
pour que tous les écouteurs existent avant le premier état serveur. Les contrôleurs
communiquent par `Signal` (`Shared/Util/Signal.luau`, sans BindableEvent : aucune copie de
table, isolation des erreurs).

**Logique pure isolée.** Tout ce qui est décision de règles est **pur et testé** :
`Shared/Rules/MatchRules.luau` (fin de manche, prolongations, balle de match),
`MatchmakingAlgorithm.luau` (formation des équipes), `RankMath.luau` (MMR/RR),
`Shared/Combat/*` (hitbox, dispersion, balistique). Les services ne font que les appeler.

## 1.3 Client-serveur impeccable

- **Registre unique** `Shared/Net/Net.luau` : chaque remote est déclaré une fois, avec son
  type et son dossier (`Combat/`, `Movement/`, `Match/`, `Lobby/`, `Replica/`, `Admin/`).
  Trois natures :
  - `Event` (fiable, ordonné) : actions de gameplay, état.
  - `Unreliable` (`UnreliableRemoteEvent`) : flux haute fréquence où seul le dernier paquet
    compte — visée (`LookUpdate` 30 Hz client→serveur, `LookBatch` 20 Hz serveur→clients) et
    visuels des tirs des autres (`ShotVisual`).
  - `Function` : requêtes du lobby avec réponse `{ ok, error?, data? }`. **Le serveur
    n'invoque jamais un client** (un client peut ne jamais répondre).
- **Branchement sécurisé** `Server/Net/ServerNet.luau` : `onEvent`, `onUnreliable`,
  `onInvoke` imposent pour chaque remote un **seau à jetons** (`RateLimiter`), un
  **parseur** (`Guard.shape`, `Guard.unitVector`, `Guard.range`, `Guard.oneOf`…) et une
  exécution protégée (`Logger.safe`). Un paquet malformé est rejeté et signalé.
- **Pot de miel** : le remote `AdminCommand` n'est appelé par aucun client légitime ; le
  toucher est une preuve de triche.
- **Le client propose, le serveur dispose.** Le client envoie des intentions (« je tire
  avec ce cône, dans cette direction, au tir n°42 »), jamais des résultats (« j'ai tué X »).

## 1.4 DataStoreService + ProfileService + ReplicaService (équivalents maison)

**DataService** (≈ ProfileService) — `Server/Services/DataService.luau` :
- **Verrou de session** posé par `UpdateAsync` (`{ JobId, PlaceId, Time }`) : un joueur qui
  passe du lobby au serveur de match en 5 s ne peut pas avoir deux serveurs qui écrivent son
  profil. Verrou volé après 20 s ; l'ancien serveur s'en aperçoit à sa prochaine sauvegarde
  et expulse le joueur (anti-duplication).
- Autosave toutes les 90 s (étalées), libération à la déconnexion, `BindToClose` borné.
- Budget DataStore respecté, retries exponentiels, **jamais** de partie sur un profil vide.
- Migrations versionnées + réconciliation (`Shared/Data/ProfileTemplate.luau`, `VERSION = 2`).
- Studio sans API : magasin mémoire de même sémantique ; Studio avec API : clé distincte.

**ReplicaService** (≈ ReplicaService) — réplication d'état par **deltas** (opcode, chemin,
valeur) avec clés **privées** (le profil répliqué au joueur masque `Moderation` et
`Purchases`). Les opérations de chemin sont partagées (`Shared/Replica/ReplicaPath.luau`) :
le client rejoue exactement ce que le serveur a appliqué. Côté client,
`ReplicaController` expose `replica:listen(path, fn)` : le HUD écoute `{"phase"}`, le lobby
`{"Cosmetics","WeaponSkins"}`, etc. — **aucune interrogation périodique**.

Replicas en jeu : `PlayerProfile` (privé), `MatchState` (participants), `Party` (membres),
`TrainingStats`, `Leaderboard` (tous), `CustomRoom` (membres du salon).

## 1.5 CollectionService

Les cartes sont **décrites** (MapKit) puis **instanciées** (MapBuilder) avec des tags qui
sont la seule interface entre le décor et le gameplay :

| Tag | Posé par | Consommé par |
|---|---|---|
| `SpawnPoint`, `SpawnBarrier`, `ModeBarrier` | MapKit | `MapBuilder` (filtrage par mode), `MatchInstance` |
| `SiteZone`, `CalloutZone` | MapKit | `MatchInstance` (pose), `MatchController` (invite, étiquettes « SITE A ») |
| `HubTerminal` (+ attribut `Action`) | MapKit | `LobbyController` (ouvre l'onglet), ProximityPrompt généré |
| `WeaponPedestal` (+ `Slot`) | Hub | `HubWorld` (vitrine 3D) |
| `LeaderboardDisplay` | Hub | `HubWorld` (SurfaceGui) |
| `TrainingZone`, `BotAnchor` | Hub | `TrainingRangeService` |
| `Combatant` | `CharacterService` | `CharacterAnimator`, prédiction de `WeaponController`, `MobileController` |
| `TrainingBot` | `TrainingRangeService` | mêmes consommateurs |
| `UplinkCore` | `MatchInstance` | boussole du HUD, bips de `MatchController` |

Les consommateurs utilisent `GetTagged` + `GetInstanceAddedSignal` : **compatible
StreamingEnabled** (une pièce qui arrive tard est prise en charge à son arrivée).

## 1.6 TweenService + Spring

- **TweenService** pour l'UI (apparitions, barres, bannières) via `UI.tween` et les
  courbes de `Theme.tween` (`fast`, `medium`, `slow`, `bounce`).
- **Spring** (`Shared/Util/Spring.luau`) pour tout ce qui doit rester **juste quel que soit
  le framerate** : intégration **analytique** (solution exacte de l'oscillateur amorti),
  donc 30 FPS et 240 FPS produisent la même courbe. Utilisations : punch caméra
  (`Spring.vector(…, 24, 0.5)`), FOV (`16, 0.9`), recul visuel du viewmodel (position
  `22, 0.62`, rotation `20, 0.55`), sway, atterrissage, posture, lean, réticule dynamique.
  Les impulsions sont **calibrées** pour que le pic du ressort égale la valeur de config
  (`kickBack`, `kickUp` en degrés…) — voir `ViewmodelController.onShot`.

## 1.7 ParticleEmitter, Beam, Trail, Attachment — optimisés

`EffectsController` possède des **pools** (`Shared/Util/Pool.luau`) pré-construits :
flashs de bouche (24), traceurs (64), impacts (48), impacts de balle (90), douilles (48).
Principes :
- Particules en **rafales** (`Emit(n)`) au lieu de `Rate` continu : coût nul hors impact.
- Traceurs = pièces néon déplacées le long de la trajectoire (vitesse et longueur par arme),
  rendus au bout de leur course ; douilles simulées à la main (une rebond, pas de physique).
- Effets d'élimination (`ke_voltage` = Beams entre membres, `ke_disintegrate` = particules
  + fondu, `ke_shatter` = cubes néon, `ke_rift` = implosion) + flash `Highlight`.
- Sons spatiaux portés par des **Attachments** dans `Terrain` (pas de Part par son).
- Aura des skins Légendaire+ : un seul `ParticleEmitter` par arme, néons animés par une
  **unique** boucle `RenderStepped` (`WeaponModelBuilder.start`).

## 1.8 Caméra avancée

`CameraController` sépare **la visée** (yaw/pitch : ce que suivent les balles, modifiée par
la souris et le recul *réel*) du **rendu** (visée + punch à ressort + shake « trauma² ×
bruit de Perlin » + roulis de lean/glissade/bob). Les effets sont généreux sans jamais
tricher sur l'endroit où l'on tire.
- **ADS** : FOV à ressort (`Fov / zoom`), sensibilité compensée (`1/zoom × AdsMultiplier`
  ou `ScopeMultiplier`).
- **Sway procédural, bob, respiration** : dans `ViewmodelController` (l'arme), pas dans la
  caméra (la visée reste stable).
- **Modes** : `FirstPerson`, `ThirdPerson` (hub, épaule droite + `Spherecast`),
  `Cinematic` (chemins de keyframes lissés : intro de carte, envol « match trouvé »),
  `Spectate` (visée répliquée lissée d'un coéquipier), `Scripted` (killcam, caméra de menu).

## 1.9 SoundService + SoundGroups

`AudioController` construit `Master ─┬─ Music / SFX ─┬─ Weapons, Footsteps, Impacts,
Feedback, Ambient / UI`. Volumes des réglages appliqués aux groupes.
- **Couches** : tir local = corps 2D (+ attaque et grave) + mécanique + *tail* 3D ; tir distant (> 120 studs) =
  variante `distant` ; *tail* réverbérée en intérieur (plafond détecté par raycast).
- **Occlusion** : un son 3D dont la ligne caméra→source traverse la géométrie est filtré
  (passe-bas + atténuation) : on entend « derrière ce mur ».
- **Ducking** : élimination, détonation, annonce → musique et ambiance s'effacent.
- **Bas PV** : passe-bas global sur les SFX + battement de cœur.
- **Pas** : par matériau, volume selon l'allure — **la marche (Alt) est silencieuse, le sprint (Maj) s'entend**, et
  les pas des autres joueurs sont synthétisés côté client (`CharacterAnimator`).
- Le code ne référence **jamais** un SoundId : clés logiques dans `Shared/Config/Sounds.luau`.

## 1.10 UI responsive (desktop + mobile)

`Client/UI/UI.luau` : constructeurs typés, composants (panneau verre, bouton premium,
barre à traînée, slider, interrupteur, sélecteur). **Chaque ScreenGui reçoit un `UIScale`**
calculé sur la hauteur d'écran (référence 1080p ; 820p sur mobile) × l'échelle HUD des
réglages. Les éléments projetés dans le monde (chiffres de dégâts) vivent dans un
ScreenGui **sans** UIScale (pixels exacts). `MobileController` ajoute joystick flottant,
zone de visée, bouton « tir + visée », sans aucun code de gameplay spécifique.

## 1.11 Character controller custom

`MovementController` : modèle **Source-like** piloté sur un Humanoid (friction
proportionnelle, accélération, **counter-strafe** ≈ 40–50 ms, air-control plafonné,
bunny-hop léger qui s'érode, glissade avec élan/pente/steering/slide-jump, buffer de saut
120 ms, coyote time 80 ms). Postures (debout/accroupi/glissade) répliquées au serveur, qui
en déduit les hitboxes. Détails : [06-movement.md](06-movement.md).

## 1.12 Recul, bloom, spread, recovery

- **Spread déterministe** (`Shared/Combat/Spread.luau`) : graine = `hash(graine serveur, n°
  de tir)`. Le client et le serveur calculent **les mêmes** directions.
- **Recul** = pattern fixe apprenable (`RecoilPatterns.build`) + aléa léger, × ADS × accroupi,
  bouclé à partir de `loopFrom`.
- **Récupération intelligente** : après `recoveryDelay`, la visée revient vers le point de
  départ à `recoverySpeed`, **sans rendre la part de dérive que le joueur a déjà compensée**
  à la souris (pas de sur-correction vers le sol).
- **Bloom** : par tir, plafonné, décroissance après un délai ; **précision de 1re balle**
  après `firstShotReset`.

## 1.13 Hit detection autoritaire + lag compensation

Pipeline en 10 étapes dans `CombatService.onFire` (contexte, arme, séquence, munitions,
cadence, origine, cône minimal, vitesse angulaire, résolution, effets) — 13 contrôles
détaillés en [10-code.md §10.3](10-code.md#103-validation-serveur-du-tir). Les cibles sont
**rembobinées** par `LagCompensationService` : anneau de 64 instantanés par cible,
interpolation, rembobinage max 0.35 s, délai d'interpolation 0.1 s, hitboxes gonflées de
0.12 stud. Les hitboxes sont des **OBB de gameplay** (`Shared/Combat/Hitbox.luau`),
indépendantes des Parts visuelles (un avatar « miniature » ne réduit pas sa hitbox).

## 1.14 Anti-exploit

Défense en profondeur (détails : [10-code.md](10-code.md)) :
1. **Réseau** : rate limit + validation de forme de **chaque** remote, pot de miel.
2. **Combat** : rejeu de n° de tir, cadence (même arme), fenêtre glissante 1 s, origine du
   tir (≤ 3.5 + 0.35 × vitesse studs de l'oeil serveur), cône déclaré ≥ cône minimal
   plausible, vitesse angulaire > 3500°/s, équipement trop rapide, horloge du tir, audit
   statistique de pré-compensation de la dispersion (`SpreadAudit`, anti « no-spread »).
3. **Mouvement** (`AntiCheatService`, 10 Hz) : vitesse en rafale (1 s) et soutenue (3 s),
   téléportation (> 18 studs/échantillon), noclip (raycast entre positions), vol
   (montée > 55 studs/s, > 3 s en l'air), rubber-banding.
4. **Score de suspicion pondéré** qui décroît (1 point / 15 s) : avertissement à 25,
   expulsion à 60. Aucun ban automatique sur heuristique : on protège les vrais joueurs.

## 1.15 StreamingEnabled + écrans de chargement

- `default.project.json` : `StreamingEnabled = true`, `StreamingMinRadius = 96`,
  `StreamingTargetRadius = 768`, `StreamingIntegrityMode = PauseOutsideLoadedArea`.
- Arènes de match : `ModelStreamingMode = PersistentPerPlayer` +
  `AddPersistentPlayer(participant)` ; arène du serveur de match : `Persistent`.
- Tout le code client tolère les pièces qui arrivent tard (signaux de tags) ; les
  chemins de caméra des cartes sont exposés en **attributs du modèle** (répliqués même
  sans les pièces).
- `ReplicatedFirst/Boot.client.luau` + `LoadingScreen.luau` (autonome, aucun `require`) :
  écran affiché dès la 1re frame, **réutilisé pendant les téléportations**
  (`SetTeleportGui` / `GetArrivingTeleportGui`) → transition sans couture lobby ⇄ match.

## 1.16 Lighting + post-processing

`Lighting.Technology = Future`. Chaque carte a un `LightingProfile` (heure, luminosité,
ambiances, exposition, atmosphère, étalonnage, bloom, sun rays) dans `Shared/Config/Maps.luau`,
appliqué par `MapService` (serveur) et `LightingController.applyMap` (client).
`LightingController` ajoute des couches **dynamiques** : flash de dégâts, « pop » d'élimination,
désaturation bas PV, flou de menu, profondeur de champ de lunette. Aberration chromatique
**simulée** en bord d'écran (Roblox n'a pas d'effet natif) dans `HUDController`.

## 1.17 Pathfinding

Les drones mobiles du stand de tir patrouillent avec `PathfindingService` entre des points
aléatoires de leur arène, avec rafales de strafe et accroupissements aléatoires (ils imitent
les *jiggle peeks*). Ils utilisent **exactement** les mêmes hitboxes et la même compensation
de latence que les joueurs : ce qu'on apprend au stand est transférable en match.

## 1.18 Network ownership, mémoire, réseau

- **Ownership** : ragdoll et bots → serveur (`SetNetworkOwner(nil)`) : tout le monde voit la
  même chute ; aucun client ne peut téléporter un cadavre ou un bot.
- **Bande passante** : visée en **binaire** (`LookCodec` : 4 octets client→serveur,
  5 octets/joueur serveur→clients, un seul paquet par arène à 20 Hz) ; visuels de tirs en
  non fiable ; état en deltas ; aucun `FireAllClients` hors contexte (envois ciblés par arène).
- **Mémoire** : pools d'effets, `Janitor` (connexions, instances, threads) par match et par
  contrôleur, modèles d'armes du viewmodel en cache, LOD d'animation (> 150 studs : 1 frame
  sur 3 ; > 350 : figé), contours `Highlight` réservés aux ennemis (rendu `Occluded`).
