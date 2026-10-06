# 10. Code prioritaire — les fondations critiques

> **Extraits générés, jamais recopiés.** Chaque bloc de code ci-dessous est inséré depuis
> `src/` par `tools/doc_excerpts.py` (gabarit : `tools/templates/10-code.md`), avec son
> fichier et ses lignes. `python3 tools/doc_excerpts.py --check` échoue dès qu'un extrait ne
> correspond plus au code : ce que vous lisez est ce qui tourne.

Le dépôt contient le jeu complet (104 modules Luau strict). Ce document isole les
**fondations dont un défaut casse le jeu** : l'intégrité compétitive (réseau, tir, touche,
anti-exploit), les données des joueurs (persistance, achats), l'équité (rang, matchmaking,
règles) et la sensation (mouvement, ressorts). Interfaces, effets et cartes se reconstruisent
facilement ; ces fondations, non. L'ordre de lecture est aussi l'ordre de construction de la
roadmap ([11-roadmap.md](11-roadmap.md)).

| § | Fondation | Ce qui casse si elle est fausse | Code | Tests |
|---|---|---|---|---|
| 10.1 | Contrat réseau | un client modifié pilote le serveur | `Shared/Net/Net`, `Shared/Util/Guard`, `Server/Net/ServerNet` | Guard, RateLimiter, LookCodec |
| 10.2 | Tir prédit (client) | input « mou », cadence dépendante des FPS | `Client/Controllers/WeaponController`, `Shared/Combat/Spread` | Spread |
| 10.3 | Validation du tir (serveur) | triche à la cadence, aux munitions, à la précision | `Server/Services/CombatService` | Spread, Balistique |
| 10.4 | Détection de touche | « je l'ai touché ! » faux pour l'un des deux joueurs | `LagCompensationService`, `Shared/Combat/Hitbox`, `Shared/Combat/Ballistics` | Hitbox, Balistique |
| 10.5 | Rang : MMR et RR | classement injuste, joueurs bloqués ou propulsés | `Shared/Rules/RankMath`, `ProgressionService` | RankMath |
| 10.6 | Persistance | progression perdue, objets ou achats dupliqués | `DataService`, `PurchaseService` | Profil |
| 10.7 | Réplication d'état | interfaces désynchronisées, bande passante gaspillée | `ReplicaService`, `Shared/Net/LookCodec` | ReplicaPath, LookCodec |
| 10.8 | Règles de manche | match bloqué, mauvais vainqueur | `Shared/Rules/MatchRules`, `Server/Match/MatchInstance` | MatchRules |
| 10.9 | Matchmaking | matchs déséquilibrés, files infinies | `MatchmakingAlgorithm`, `MatchmakingService`, `MatchService` | Matchmaking |
| 10.10 | Mouvement | sensation « savon », counter-strafe impossible | `Client/Controllers/MovementController` | Hitbox (postures) |
| 10.11 | Anti-exploit | speedhack, téléportation, vol, no-spread | `AntiCheatService`, `Shared/Combat/SpreadAudit` | SpreadAudit, Guard |
| 10.12 | Infrastructure de feeling | effets instables, visée faussée par le juice | `Shared/Util/Spring`, `CameraController`, `ViewmodelController` | Spring |
| 10.13 | Démarrage | services dans le désordre, écran de chargement figé | `Server/Main`, `Client/Main`, `ReplicatedFirst/Boot` | — |
| 10.14 | Vérification | régressions silencieuses | `scripts/`, `tests/`, `tools/` | 91 tests |

## 10.1 Contrat réseau : registre unique, validation stricte, débit borné

**Règle d'or : tout ce qu'envoie un client est hostile** — types faux, NaN, ±inf, tables à
métatable, champs en trop, chaînes de plusieurs Mo, spam. Trois couches, sans exception.

**1. Registre unique** (`Shared/Net/Net.luau`). Les 33 remotes (22 `RemoteEvent`,
3 `UnreliableRemoteEvent`, 8 `RemoteFunction`) sont déclarés à un seul endroit, avec leur
type et leur dossier ; `Net.setup()` les crée tous avant le premier service. Aucune chaîne
magique dispersée : la revue de sécurité du réseau se fait sur un seul fichier. Le serveur
**n'invoque jamais** un client (les `RemoteFunction` vont du client au serveur uniquement :
un client qui ne répond pas bloquerait un thread serveur). `AdminCommand` est un **pot de
miel** : aucun client légitime ne l'appelle, son seul usage signe un exploit.

**2. Branchement sécurisé** (`Server/Net/ServerNet.luau`). Chaque handler traverse seau à
jetons → validation → exécution protégée (`xpcall` + pile d'appel : une erreur n'interrompt
jamais l'écoute du remote). Les violations sont remontées à l'anti-cheat par un rapporteur
**injecté** (aucune dépendance circulaire Net ↔ AntiCheat).

@@fn src/Server/Net/ServerNet.luau guardCall@@

@@fn src/Server/Net/ServerNet.luau ServerNet.onEvent@@

**3. Schémas stricts** (`Shared/Util/Guard.luau`). Un paquet valide **exactement** son
schéma : aucun champ inconnu (un champ en trop = client modifié), aucune métatable, nombres
finis et bornés, chaînes UTF-8 de longueur bornée, tableaux sans trous ni clés exotiques.

@@fn+doc src/Shared/Util/Guard.luau Guard.shape@@

Le paquet de tir est ainsi validé avant d'atteindre la moindre ligne de gameplay :

@@between src/Server/Services/CombatService.luau local isFire = Guard.shape({ ||| })@@

Débits par joueur et par remote (rafale / recharge par seconde) : `Fire` 24/20 · `Stance`
24/16 · `LookUpdate` 40/34 · `Equip` 10/6 · `Melee` 6/4 · `Reload` 4/2 · `Interact` 8/4 ·
`LoadoutSelect` 8/3 · `Emote` 3/0.5 · `SettingsSave` 3/0.5 · fonctions du lobby 6–8 / 1–4 ·
`ReplicaRequest` 2/0.1. Dépassement : requête ignorée et 0.5 point de suspicion ; paquet
invalide : 2 points ([§10.11](#1011-anti-exploit)). Inventaire complet :
[02-architecture.md §2.5](02-architecture.md#25-inventaire-des-remotes-sharednetnetluau).

## 10.2 Le tir côté client : prédiction exacte, cadence indépendante des FPS

Le client n'attend **jamais** le serveur pour tirer — flash, son, recul, traceur et impacts
sont immédiats — mais il ne **décide** de rien : il prédit ce que le serveur calculera, avec
les mêmes fonctions partagées (`Shared/Combat`).

**Planification sous-frame.** Les tirs ne sont pas « un par frame » : chaque tir est
planifié à `nextShotAt` et horodaté à son instant **théorique**. Si une frame dure plus
longtemps que l'intervalle entre deux tirs (hitch, très bas FPS), plusieurs tirs partent
dans la même frame avec des horodatages espacés exactement de l'intervalle : la cadence
réelle ne dépend pas du framerate (`MAX_SHOTS_PER_FRAME = 3` borne le rattrapage). Les
armes à montée en cadence (HMG-40 : 560 → 800 tirs/min en 1.2 s) recalculent l'intervalle à
chaque balle. Branche automatique de la boucle de tir (`step`) :

@@between src/Client/Controllers/WeaponController.luau if mode == "Auto" then ||< elseif mode == "Burst" then@@

**Paquet de tir et état prédit.** `t` est l'horloge serveur (`GetServerTimeNow`) de
l'instant planifié, jamais plus proche du tir précédent que 97 % de l'intervalle minimal :
la synchronisation d'horloge peut « sauter » de quelques millisecondes entre deux frames,
et le serveur verrait sinon une cadence impossible. Le compteur `n`, le chargeur et le bloom
avancent localement **exactement** comme le serveur les fera avancer.

@@between src/Client/Controllers/WeaponController.luau local function fireOnce( ||| Spread.seed(seedBase, shot)@@

**Dispersion déterministe** (`Shared/Combat/Spread.luau`). Une seule formule de cône pour
le client, le serveur et le réticule du HUD : base hanche/ADS, précision de 1re balle,
bonus accroupi, pénalité de mouvement **au-delà de 34 % de la vitesse de course** (le
counter-strafe est récompensé), pénalité aérienne, bloom.

@@fn src/Shared/Combat/Spread.luau Spread.cone@@

@@fn+doc src/Shared/Combat/Spread.luau Spread.directions@@

| Immédiat (prédit par le client) | Attend le serveur (`ShotResult`, `DamageTaken`, `Kill`) |
|---|---|
| flash, son, recul, punch caméra, douille, traceur, impacts monde, étincelles sur la cible visée, munitions | hitmarker, chiffres de dégâts, sons de touche / tête / bouclier brisé, élimination, killfeed |

**Auto-réparation.** Tout refus serveur (cadence, arme non équipée, chargeur vide côté
serveur…) renvoie un `AmmoSync` : le client reprend la vérité serveur (compteur, chargeurs,
graine) et la prédiction se recale sans intervention du joueur.

## 10.3 Validation serveur du tir

`CombatService.onFire` est le cœur de l'intégrité du jeu. Les contrôles vont du moins coûteux
au plus coûteux ; tout refus **resynchronise** le client ; seuls les comportements
impossibles pour un client légitime ajoutent des points de suspicion (un lag isolé ne coûte
rien).

@@fn src/Server/Services/CombatService.luau onFire@@

| # | Contrôle | Seuil | Réaction (points de suspicion) |
|---|---|---|---|
| 1 | contexte | vivant, armé, phase `Live`/`Planted` (ou Training Range), pas `Busy` | ignoré |
| 2 | arme | `w` = arme équipée côté serveur, hors mêlée | resync |
| 3 | séquence | `n` = compteur attendu | resync ; `n` déjà consommé → `ShotReplay` (2) |
| 4 | équipement | ≥ 70 % du temps d'équipement écoulé | `FastEquip` (1) |
| 5 | rechargement | aucun en cours (cartouche par cartouche : interrompu, cartouches insérées comptées) | resync |
| 6 | munitions | chargeur serveur > 0 | resync |
| 7 | horloge | \|t − maintenant\| ≤ 1 s | `ShotClock` (1) |
| 8 | cadence | intervalle ≥ 90 % du minimum entre deux tirs de la même arme | `FireRate` (2) |
| 9 | fenêtre glissante | ≤ ⌈tirs/s max⌉ + 2 tirs sur 1 s (horloge serveur) | `FireRateWindow` (3) |
| 10 | origine | ≤ 3.5 + 0.35 × vitesse studs de l'oeil serveur | `ShotOrigin` (3) |
| 11 | dispersion | `s` ≥ cône minimal − 0.05° (sinon le cône minimal est appliqué) | `NoSpread` (1.5) |
| 12 | visée | > 20° d'écart avec la dernière visée répliquée **et** > 3 500°/s | `AimSnap` (1.5) |
| 13 | pré-compensation | corrélation ≤ −0.6 sur 40 paires de tirs ([§10.11](#1011-anti-exploit)) | `SpreadCompensation` (4) |

Le **cône minimal plausible** est recalculé à partir de ce que le serveur observe lui-même
(vitesse du HRP, posture, ADS confirmé par l'attribut répliqué, en l'air depuis plus de
0.25 s), avec des marges qui excluent tout faux positif (vitesse × 0.75, bloom × 0.5,
résultat × 0.85). Déclarer un cône réduit ne sert donc à rien : le serveur tire avec le sien.

@@fn src/Server/Services/CombatService.luau minimumCone@@

## 10.4 Détection de touche : compensation de latence, hitboxes, pénétration

**Le problème.** Un joueur à 80 ms de ping voit ses adversaires là où ils étaient ~40 ms
plus tôt (trajet serveur → client), plus le tampon d'interpolation. Tester les positions
**actuelles** ferait « rater » des tirs parfaitement visés. **La solution** : un historique
de poses et un rembobinage **borné**.

- À chaque `Heartbeat`, le serveur enregistre pour chaque cible vivante (joueurs et bots du
  Training Range, interface commune) : temps serveur, `CFrame` du HRP, posture, lean —
  anneau de 64 échantillons (≈ 1 s à 60 Hz).
- Un tir horodaté `t` est testé contre la pose de chaque cible à `t − 0.1 s` (délai
  d'interpolation), **jamais plus de 0.35 s dans le passé** : on favorise le tireur sans
  permettre de toucher quelqu'un à couvert depuis longtemps. Rembobinage ≈ ping/2 + 0.1 s :
  jusqu'à ≈ 500 ms d'aller-retour, le tireur n'a pas à anticiper.

@@fn+doc src/Server/Services/LagCompensationService.luau LagCompensationService.rewindTime@@

@@fn+doc src/Server/Services/LagCompensationService.luau LagCompensationService.poseAt@@

@@fn+doc src/Server/Services/LagCompensationService.luau LagCompensationService.raycast@@

**Hitboxes de gameplay** (`Shared/Combat/Hitbox.luau`) : des boîtes orientées (OBB) qui
dépendent **uniquement** de (CFrame, posture, lean) — jamais des Parts visuelles de l'avatar.
Un avatar miniature, une Part redimensionnée ou une animation trafiquée ne changent rien, et
le lean de la hitbox est **la même transformation** que celui de la caméra
(`Stances.leanTransform`) : on ne peut pas voir sans être visible. Test en deux phases :
sphère englobante (rejette presque toutes les cibles en une dizaine d'opérations), puis
rayon/OBB pour chaque partie, zone la plus proche retenue.

@@fn+doc src/Shared/Combat/Hitbox.luau Hitbox.raycast@@

**Résolution** (par direction, donc par plomb) : rayon monde → rayon contre les hitboxes
rembobinées **jusqu'au premier obstacle** ; si l'obstacle est pénétrable : épaisseur mesurée
par un rayon retour, coût = épaisseur × résistance du matériau, 2 surfaces au plus. Les
plombs touchant une même cible sont **cumulés** (un seul impact, zone la plus haute).

@@between src/Server/Services/CombatService.luau local rewind = LagCompensationService.rewindTime(packet.t) ||< local noscope = def.handling.scopeOverlay@@

**Balistique** (`Shared/Combat/Ballistics.luau`) : dégâts = base × zone × chute (interpolée
entre paliers) × pénétration, arrondis à l'entier (les joueurs raisonnent en « taps ») ; le
bouclier absorbe 66 % de chaque impact tant qu'il en reste. Tableaux de dégâts, de chute et
de TTK de toutes les armes : [07-weapons.md §7.2](07-weapons.md#72-tableaux-de-référence).

@@fn src/Shared/Combat/Ballistics.luau Ballistics.damage@@

@@fn+doc src/Shared/Combat/Ballistics.luau Ballistics.apply@@

@@fn+doc src/Shared/Combat/Ballistics.luau Ballistics.penetrate@@

## 10.5 Rang : MMR et RR

Double couche, comme les références du genre :

- **MMR caché** : un Elo d'équipe, mesure du niveau réel, utilisé par le matchmaking ;
- **rang visible** : 7 paliers × 3 divisions (RECRUIT, OPERATIVE, SPECIALIST, VANGUARD,
  SENTINEL, PHANTOM, APEX) puis **AETHER** (palier unique, classement global), et des **RR**
  (0–100) gagnés ou perdus à chaque match classé.

Le lien entre les deux est la **convergence** : le RR gagné dépend de l'écart entre le rang
affiché et le rang **attendu** par le MMR (`Ranks.expectedIndex` : 60 points de MMR par
division ; 600 → RECRUIT I, 1 860 → AETHER). Un joueur sous-classé monte vite, un joueur
sur-classé redescend vite — sans que personne ne voie jamais son MMR.

**MMR.** Attendu `E = 1 / (1 + 10^((MMRadverse − MMRéquipe) / 400))` (MMR d'équipe = moyenne
de ses joueurs), `ΔMMR = K × (S − E)` avec S = 1 / 0.5 / 0, puis modulation de ±15 % par la
**performance** individuelle : (score de combat − score moyen du lobby) / score moyen, bornée
à [−1, 1]. On récompense l'impact sans transformer le jeu en course aux kills : une victoire
reste une victoire. K = 64 pendant les 5 matchs de placement, puis de 48 à 24 linéairement sur
les 30 matchs suivants (le rang se stabilise, les montagnes russes s'arrêtent).

@@fn src/Shared/Rules/RankMath.luau RankMath.kFactor@@

@@fn src/Shared/Rules/RankMath.luau RankMath.mmrDelta@@

**RR.** Base 18, plus la convergence (±4 RR par division d'écart entre rang attendu et rang
affiché, plafonnée à ±10), plus la performance (±6). Bornes : victoire [8, 35], défaite
−[6, 32], égalité [−5, 5]. Promotion à 100 RR (surplus conservé), rétrogradation sous 0 (on
retombe à 75 RR au plus dans la division inférieure), jamais sous RECRUIT I.

@@fn src/Shared/Rules/RankMath.luau RankMath.rrDelta@@

@@fn+doc src/Shared/Rules/RankMath.luau RankMath.applyRR@@

**Placements.** 5 matchs ; le rang de sortie est le rang attendu par le MMR, **bridé à
SENTINEL III** (l'élite se mérite match après match), avec 25 RR. Le pic de rang est mémorisé.
`Uncertainty` est suivie (× 0.92 par match, plancher 60) mais n'entre pas encore dans le
calcul : K dépend du nombre de matchs (évolution prévue : K et fenêtre de matchmaking
pondérés par l'incertitude).

**Exemples calculés par le module réel** (`RankMath.process`) :

| Situation | E | K | ΔMMR | ΔRR | Résultat |
|---|---|---|---|---|---|
| SPECIALIST I à 40 RR, 1er match après placement, équipe 1000 contre 1100, **victoire**, perf. +0.5 | 0.36 | 48 | +33 | +26 | SPECIALIST I · 66 RR |
| même match, **défaite**, perf. +0.5 | 0.36 | 48 | −16 | −13 | SPECIALIST I · 27 RR |
| joueur établi (40 matchs), 1000 contre 900, victoire, perf. 0 | 0.64 | 24 | +9 | +21 | SPECIALIST I · 61 RR |
| **sous-classé** : OPERATIVE I à 90 RR mais MMR 1150, victoire | 0.50 | 24 | +12 | +28 | **promotion** OPERATIVE II · 18 RR |
| sous-classé (OPERATIVE I à 10 RR), défaite | 0.50 | 24 | −12 | −8 | OPERATIVE I · 2 RR |
| **sur-classé** : SENTINEL I à 50 RR mais MMR 1000, victoire | 0.50 | 24 | +12 | +8 | SENTINEL I · 58 RR |
| sur-classé (SENTINEL I à 5 RR), défaite | 0.50 | 24 | −12 | −28 | **rétrogradation** VANGUARD III · 75 RR |
| égalité, 1000 contre 1000, SPECIALIST I à 50 RR | 0.50 | 24 | 0 | +1 | SPECIALIST I · 51 RR |

Application en fin de match (serveur de match, profil verrouillé) :

@@between src/Server/Services/ProgressionService.luau -- 3. Rang classé ||< -- 4. Résumé post-match@@

## 10.6 Persistance : verrou de session, zéro perte, zéro duplication

**Le problème.** Un joueur passe du lobby au serveur de match puis revient, en quelques
secondes. Sans verrou, deux serveurs peuvent écrire le même profil : progression perdue ou
**objets dupliqués**. `DataService` reproduit le modèle de ProfileService :

```
Lobby (JobId L)                          Serveur de match (JobId M)
 charge le profil → Session = L
 file, MATCH TROUVÉ, téléportation
 PlayerRemoving → sauvegarde + Session = nil
                                          charge le profil : Session libre → Session = M
                                          (si L n'a pas encore libéré : « Locked », nouvel
                                           essai toutes les 3 s ; au-delà de 20 s, vol du verrou)
                                          fin de match : XP, RR, stats, LastMatch écrits
                                          retour au lobby → sauvegarde + Session = nil
 charge le profil → Session = L ; LastMatch non vu → écran de progression
```

@@fn src/Server/Services/DataService.luau tryAcquire@@

@@fn src/Server/Services/DataService.luau loadProfile@@

Sauvegarde automatique toutes les 90 s (étalée), **toujours** via `UpdateAsync` qui vérifie
que la session nous appartient encore — sinon on n'écrit rien et on expulse : le serveur qui
a perdu le verrou ne peut jamais écraser des données plus récentes.

@@fn+doc src/Server/Services/DataService.luau saveProfile@@

Autres garanties : libération à la déconnexion et à la fermeture (`BindToClose`, en parallèle,
25 s max) ; migrations versionnées + réconciliation avec le gabarit à chaque chargement
(champs manquants ajoutés, types corrompus réparés, loadout invalide corrigé — testé) ;
budget DataStore respecté et nouvelles tentatives exponentielles ; garde de taille (3.8 Mo) ;
**un chargement qui échoue expulse le joueur** (on ne joue jamais sur un profil vide qui
écraserait le vrai) ; en Studio sans accès API, magasin en mémoire de même sémantique (et clé
distincte en Studio avec API : les profils live ne sont jamais touchés).

**Achats Robux** — idempotents (chaque `PurchaseId` est mémorisé dans le profil) et
`PurchaseGranted` n'est renvoyé **qu'après une sauvegarde réussie**. Si elle échoue, l'octroi
**et** le reçu sont annulés : Roblox rejouera le reçu, et rien ne peut avoir été crédité deux
fois entre-temps.

@@fn src/Server/Services/PurchaseService.luau processReceipt@@

## 10.7 Réplication d'état : deltas par chemin

Un **replica** = (jeton, données, abonnés). Toute mutation passe par son API
(`Set`, `SetValues`, `ArrayInsert`, `ArrayRemove`, `Increment`) : la table serveur est modifiée
puis l'opération `(id, op, chemin, valeur)` est envoyée aux seuls abonnés ; le client rejoue
la même opération (`Shared/Replica/ReplicaPath`, testé) — les deux copies sont identiques par
construction et seul le delta transite.

| Replica | Abonnés | Contenu |
|---|---|---|
| `PlayerProfile` | le propriétaire | le profil entier (**même table** que `DataService` : une mutation répliquée est sauvegardée), sauf les clés privées `Moderation` et `Purchases` |
| `Party` | les membres | chef, membres (noms, rangs), verrou, mode, classé, invitations, état de file (depuis, estimation, joueurs en file, largeur de recherche MMR) |
| `MatchState` | les joueurs du match | phase et échéance, manche, scores, côtés, prolongation, joueurs (K/D/A, dégâts, vivant, loadout), objectif (porteur, site, mèche, désamorçage), historique des manches, MVP |
| `Leaderboard` | tous | top classé (rang, RR) |
| `TrainingStats` | le propriétaire | tirs, touches, headshots, éliminations, dégâts, bouclier des bots (Training Range) |
| `CustomRoom` | les membres | salon de partie personnalisée |

@@fn src/Server/Services/ReplicaService.luau broadcast@@

@@fn src/Server/Services/ReplicaService.luau ReplicaClass.Set@@

Un client ne reçoit rien avant d'avoir signalé `ReplicaRequest` (tous ses écouteurs
existent : `ReplicaController` démarre en dernier), puis reçoit tous ses replicas d'un coup.

**Flux haute fréquence en binaire.** La visée de chaque joueur (poses en 3e personne,
spectateur, killcam, anti-cheat) part en `buffer` de 4 octets à 30 Hz et revient en **un seul
paquet non fiable par arène** à 20 Hz, 5 octets par joueur (précision 0.0055° en lacet,
0.0027° en tangage) : 6 joueurs = 30 octets par paquet, au lieu de ~20 octets *par joueur*
en tables Luau.

@@fn src/Shared/Net/LookCodec.luau LookCodec.encodeBatch@@

## 10.8 Règles de manche et machine à états du match

Toutes les décisions de règles sont **pures** (`Shared/Rules/MatchRules.luau`, aucune
dépendance au moteur, testées hors Roblox) ; `MatchInstance` ne fait que les appliquer.

@@fn+doc src/Shared/Rules/MatchRules.luau MatchRules.matchWinner@@

@@fn+doc src/Shared/Rules/MatchRules.luau MatchRules.sideSwapDue@@

@@fn+doc src/Shared/Rules/MatchRules.luau MatchRules.evaluateRound@@

Machine à états du match, mise à jour à chaque `Heartbeat` (horloge serveur) :

```
Waiting ─► Intro ─► Prep ─► Live ─┬──────────────────────────► RoundEnd ─┬─► MatchEnd ─► Closed
   │                 ▲            └─(pose, Uplink)─► Planted ─┘          │   (XP, RR, retour)
   │                 ├────────────────── manche suivante ────────────────┤
   │                 └──── SideSwap ◄── mi-temps / prolongation ─────────┘
   └─ délai écoulé avec une équipe absente : forfait ─► MatchEnd
```

@@fn src/Server/Match/MatchInstance.luau MatchInstance.update@@

## 10.9 Matchmaking : équilibre, attente bornée, inter-serveurs

**Algorithme** (`Shared/Rules/MatchmakingAlgorithm.luau`, pur et testé) : les tickets les plus
anciens servent d'ancres ; la fenêtre de MMR s'élargit avec l'attente (75 + 6 × attente,
plafond 600) et, en classé, l'écart de rang autorisé aussi (3 divisions, +1 toutes les 20 s,
plafond 9). Parmi les candidats compatibles **deux à deux**, on cherche un groupe de tickets
totalisant exactement 2 × taille d'équipe (une party n'est **jamais** séparée), puis la
partition en deux équipes qui minimise l'écart de MMR moyen (énumération exhaustive :
≤ 6 tickets → ≤ 32 partitions). Score = écart entre équipes + 0.25 × dispersion : des équipes
équilibrées **et** homogènes.

@@fn src/Shared/Rules/MatchmakingAlgorithm.luau compatible@@

@@fn+doc src/Shared/Rules/MatchmakingAlgorithm.luau MatchmakingAlgorithm.bestSplit@@

**Backend cloud.** Tickets dans un `MemoryStoreSortedMap` par file (TTL 90 s rafraîchi : un
lobby qui plante ne laisse pas de tickets fantômes) ; un **leader** unique (verrou MemoryStore
de 8 s) exécute l'algorithme toutes les 2 s, réserve un serveur
(`TeleportService:ReserveServer`), écrit la `MatchSpec` sous la clé `PrivateServerId` et une
affectation par ticket ; chaque lobby interroge les affectations de **ses** tickets, affiche
« MATCH TROUVÉ » et téléporte la party. Cinq erreurs MemoryStore d'affilée : bascule
automatique sur le matchmaking local.

@@fn src/Server/Services/MatchmakingService.luau isLeader@@

**Frontière de confiance.** Le serveur de match lit sa composition dans MemoryStore — jamais
dans les `TeleportData`, falsifiables par le client — et la valide comme n'importe quelle
entrée ; un joueur non attendu est expulsé.

@@fn src/Server/Services/MatchService.luau decodeSpec@@

L'estimation affichée en file est la moyenne glissante des 20 dernières attentes de la même
file (45 s par défaut) : une estimation honnête, pas un chiffre décoratif.

@@fn src/Server/Services/MatchmakingService.luau estimate@@

## 10.10 Mouvement : modèle « Source-like » piloté sur un Humanoid

Le Humanoid reste le **corps** (collisions, sol, marches, pentes) ; notre modèle décide de la
**vitesse** à chaque frame (`PreSimulation`), en partant de la vitesse réelle du HRP (murs et
collisions déjà appliqués). Friction exponentielle avec arrêt net sous `stopSpeed`, puis
accélération vers la vitesse souhaitée — le même couple de fonctions qui rend le
counter-strafe (≈ 40–50 ms) et le contrôle aérien possibles ([06-movement.md](06-movement.md)).

@@fn src/Client/Controllers/MovementController.luau applyFriction@@

@@fn src/Client/Controllers/MovementController.luau accelerate@@

@@between src/Client/Controllers/MovementController.luau -- Vitesse souhaitée ||< -- Application au Humanoid@@

Le bunny-hop existe mais s'**érode** : l'excédent au-dessus de la vitesse de course est
multiplié par 0.94ⁿ à chaque hop enchaîné, et la vitesse aérienne est plafonnée — de la
technique, jamais du chaos (les seuils serveur de [§10.11](#1011-anti-exploit) restent hors
d'atteinte avec marge).

@@between src/Client/Controllers/MovementController.luau -- Bunny-hop léger ||| airCap = math.max(@@

## 10.11 Anti-exploit

**Principe.** Le client possède la physique de son personnage (indispensable à un mouvement
réactif) : le serveur **vérifie** au lieu de faire confiance, et **décide** de tout ce qui
compte — PV, dégâts, munitions, morts, scores, inventaire, monnaies, progression, résultats,
achats, compositions d'équipes. Défense en profondeur :

| Couche | Contrôles | Points |
|---|---|---|
| Réseau (`ServerNet`) | débit par remote, schéma strict | 0.5 / 2 |
| Pot de miel | `AdminCommand` | 100 (expulsion immédiate) |
| Combat (`CombatService`) | rejeu, équipement, horloge, cadence, fenêtre, origine, cône, snap de visée, pré-compensation ([§10.3](#103-validation-serveur-du-tir)) | 1 à 4 |
| Mouvement (`AntiCheatService`, 10 Hz, 3 s d'historique) | téléportation (8), noclip (8), vol (6), vitesse verticale (5), vitesse soutenue sur 3 s (5), vitesse en rafale sur 1 s (4) — avec **rubber-band** immédiat | 4 à 8 |
| Hitboxes | OBB de gameplay indépendantes de l'avatar ([§10.4](#104-détection-de-touche--compensation-de-latence-hitboxes-pénétration)) | — |
| Économie | possession vérifiée à chaque équipement, prix serveur, réclamations idempotentes | — |

**Score de suspicion pondéré et décroissant** (1 point / 15 s) : journal + analytics à 25,
expulsion à 60 avec drapeau persistant au profil. Un lag isolé ne fait jamais expulser : il
faut une accumulation d'anomalies impossibles. Aucun bannissement automatique sur heuristique.

@@fn+doc src/Server/Services/AntiCheatService.luau AntiCheatService.flag@@

Mouvement : la vitesse est mesurée sur **deux fenêtres** — une rafale d'1 s (plafond =
vitesse maximale de glissade × 1.15 = 34.5 studs/s) et une moyenne sur 3 s (course × plafond
aérien × 1.08 × 1.15 ≈ 24.3 studs/s) qui attrape les speedhacks « discrets » (×1.3–1.5)
qu'un seuil instantané laisserait passer.

@@fn src/Server/Services/AntiCheatService.luau checkPlayer@@

**No-spread par pré-compensation.** C'est la limite connue de toute dispersion prédite
exactement : le client connaît la graine, donc un cheat peut calculer le décalage δn du tir n
et viser `cible − δn`. Ni le cône déclaré ni la vitesse de visée ne le trahissent. Sa
signature est statistique : la variation de visée entre deux tirs contient −(δn − δn−1),
alors que celle d'un joueur légitime est **indépendante** de δ. `SpreadAudit` mesure cette
corrélation par fenêtres de 40 paires de tirs consécutifs (même arme, ≤ 0.6 s d'écart, cône
≥ 1°).

@@fn+doc src/Shared/Combat/SpreadAudit.luau SpreadAudit.observe@@

@@between src/Server/Services/CombatService.luau local audit = audits[player] ||< resolveShot(player, state, def, packet, directions)@@

Mesures sur simulation (25 fenêtres par cas, visée humaine en marche aléatoire, cheat qui
compense exactement) :

| Cône | Mouvement humain entre deux tirs (par axe) | Joueur légitime : r moyen [min, max] | Tricheur : r moyen [min, max] |
|---|---|---|---|
| 1.0° | 1.0° | 0.00 [−0.15, 0.25] | −0.51 [−0.64, −0.35] |
| 1.5° | 0.5° | 0.00 [−0.15, 0.25] | −0.87 [−0.91, −0.83] |
| 2.5° | 1.0° | 0.00 [−0.15, 0.25] | −0.83 [−0.88, −0.78] |
| 2.5° | 1.5° | 0.00 [−0.15, 0.25] | −0.70 [−0.79, −0.62] |
| 4.0° | 1.0° | 0.00 [−0.15, 0.25] | −0.92 [−0.94, −0.90] |

Lecture honnête : le détecteur est fiable là où le no-spread rapporte vraiment (tir en
mouvement, au saut, spray long : cône ≥ 2°) et faible quand le cône est petit — c'est-à-dire
quand le cheat ne gagne presque rien. Le seuil −0.6 est une valeur de départ à **calibrer sur
données réelles** (le poids de 4 points et la décroissance rendent un faux positif isolé sans
effet).

**Limites assumées.** Un aimbot qui imite une visée humaine, un wallhack (lecture des
positions répliquées) ou un macro de recul ne se détectent pas par ces règles : ils relèvent
de l'analyse statistique hors ligne (précision, temps de réaction, ratio de headshots par
rapport au rang) et de la modération (signalements, revue de killcams). L'architecture
l'anticipe : chaque signalement part dans `AnalyticsService` et le profil garde un historique
de drapeaux.

## 10.12 Infrastructure de feeling : ressorts exacts, juice séparé de la visée

**Ressorts à intégration analytique** (`Shared/Util/Spring.luau`). Tout ce qui bouge « avec du
poids » — FOV d'ADS, hauteur des yeux, sway et bob, kick de recul, punch caméra, UI — utilise
la solution exacte de l'oscillateur amorti : stable quel que soit `dt` (un hitch de 2 s ne
fait rien diverger — testé) et **identique à tout framerate**, condition d'équité dans un FPS.

@@fn src/Shared/Util/Spring.luau Spring.coefficients@@

**Le juice ne ment jamais.** La caméra 1re personne compose la **visée** (lacet/tangage, ce
que suivent les balles via `getAim`) puis, par-dessus, des couches **purement visuelles** :
bob, punch, secousse (bruit de Perlin, intensité = trauma²), roulis. Aucune ne modifie la
direction des balles ; le recul *réel*, lui, passe par `addRecoil` et déplace la visée.

@@fn src/Client/Controllers/CameraController.luau firstPerson@@

**Récupération intelligente du recul** : après `recoveryDelay`, la visée revient vers son
point de départ, **sans rendre la part de dérive que le joueur a déjà compensée** à la souris
(pas de sur-correction vers le sol), et le pattern « redescend » pendant les pauses.

@@fn src/Client/Controllers/WeaponController.luau recover@@

**Kick du viewmodel** : impulsions de ressort calibrées pour que le pic corresponde aux
valeurs de configuration de chaque arme (recul arrière, montée, roulis), réduites en ADS et
accroupi.

@@fn+doc src/Client/Controllers/ViewmodelController.luau ViewmodelController.onShot@@

## 10.13 Démarrage déterministe

**Serveur.** `Net.setup()` crée tous les remotes, puis chaque service fait `Init()` (état
interne, injections, aucun yield) **dans l'ordre des dépendances**, puis `Start()` dans le même
ordre (connexions, boucles). Chaque étape est protégée : un service défaillant est journalisé
avec sa pile d'appel sans empêcher les autres de démarrer.

@@between src/Server/Main.server.luau local Services = script.Parent.Services ||| Workspace:SetAttribute("ServerReady", true)@@

**Client.** Démarrage dans l'ordre état → entrées → rendu → gameplay → interfaces ;
`ReplicaController` **en dernier**, pour que tous les écouteurs existent avant le premier état
envoyé par le serveur.

@@between src/Client/Main.client.luau -- 1. Démarrage ordonné ||| ReplicaController.start()@@

**Écran de chargement** (`ReplicatedFirst`) : remplace celui de Roblox dès la première frame —
ou reprend celui de la téléportation (`GetArrivingTeleportGui`) pour une transition sans
couture entre lobby et match — et ne s'efface que lorsque le client est **réellement prêt**
(contrôleurs démarrés + profil reçu, délai de sécurité 45 s).

@@lines src/ReplicatedFirst/Boot.client.luau 20 43@@

## 10.14 Vérification

| Commande | Vérifie |
|---|---|
| `./scripts/analyze.sh` | analyse **stricte** de tout `src/` (luau-lsp, définitions Roblox, sourcemap Rojo) : 0 erreur |
| `./scripts/test.sh` | 91 tests unitaires hors moteur (Lune) |
| `./scripts/build.sh` | build Rojo de la place complète (`build/AetherStrike.rbxl`) |
| `stylua --check src tests` | formatage |
| `python3 tools/require_graph.py --check` | aucun cycle ni `require` non résolu (104 modules, 511 dépendances) |
| `python3 tools/doc_excerpts.py --check` | les extraits de ce document correspondent au code |

| Suite | Tests | Exemples |
|---|---|---|
| Hitbox | 10 | tête/corps/membres, tête accroupie sous une caisse de 4 studs, oeil dans la boîte de tête, lean = caméra, inflation |
| Spread | 7 | déterminisme, cône respecté, motif des plombs, counter-strafe sous 34 %, bloom |
| SpreadAudit | 4 | reconstruction exacte du décalage, joueur légitime non signalé, tricheur signalé, fenêtres |
| Balistique | 9 | one-taps par arme et par distance, tirs pour tuer, armure 66 %, chute, pénétration, +1 chambrée |
| Cartes | 22 | métadonnées, spawns, sites, callouts, **aucune ligne de vue entre spawns adverses**, terminaux du hub |
| RankMath | 7 | exploit > victoire attendue, promotion avec report, rétrogradation à 75, placements bridés, bornes |
| Matchmaking | 4 | 3v3 équilibré, party jamais séparée, fenêtre de MMR, écart de rang |
| MatchRules | 9 | premier à 8, prolongation à 2 manches d'écart, mort subite, changement de côté, Uplink, temps écoulé |
| Spring, RateLimiter, Guard, LookCodec, ReplicaPath | 13 | convergence, stabilité à 2 s de dt, indépendance au framerate, NaN/inf/métatables rejetés, buffers malformés |
| Profil, progression, missions | 6 | réconciliation d'un profil corrompu, loadout invalide, XP multi-niveaux, missions sans doublon, catalogue de 112 skins |

Ce que ces vérifications **ne couvrent pas** (et que la roadmap traite explicitement) : le
ressenti réel en jeu, les performances sur appareil, le comportement réseau sous perte de
paquets et la montée en charge MemoryStore — ils exigent des sessions de test en Studio puis
en live ([11-roadmap.md](11-roadmap.md)).
