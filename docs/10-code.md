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

```lua
-- src/Server/Net/ServerNet.luau (l. 43–60)
local function guardCall<T>(
    player: Player,
    name: string,
    limiter: RateLimiter.RateLimiter,
    parse: (...any) -> T?,
    ...: any
): T?
    if not limiter:consume(player) then
        reporter(player, "RateLimit:" .. name, 0.5)
        return nil
    end
    local ok, payload = pcall(parse, ...)
    if not ok or payload == nil then
        reporter(player, "BadPayload:" .. name, 2)
        return nil
    end
    return payload
end
```

```lua
-- src/Server/Net/ServerNet.luau (l. 62–70)
function ServerNet.onEvent<T>(name: Net.EventName, rate: RateSpec, parse: (...any) -> T?, handler: (Player, T) -> ())
    local limiter = RateLimiter.new(rate.capacity, rate.refill)
    Net.event(name).OnServerEvent:Connect(function(player: Player, ...: any)
        local payload = guardCall(player, name, limiter, parse, ...)
        if payload ~= nil then
            Logger.safe(log, name, handler, player, payload)
        end
    end)
end
```

**3. Schémas stricts** (`Shared/Util/Guard.luau`). Un paquet valide **exactement** son
schéma : aucun champ inconnu (un champ en trop = client modifié), aucune métatable, nombres
finis et bornés, chaînes UTF-8 de longueur bornée, tableaux sans trous ni clés exotiques.

```lua
-- src/Shared/Util/Guard.luau (l. 153–174)
--[[
    Table stricte : chaque champ déclaré doit valider, AUCUN champ supplémentaire n'est
    toléré (un champ inconnu = client modifié). Les champs optionnels utilisent Guard.optional.
]]
function Guard.shape(fields: { [string]: Check }): Check
    return function(value: any): boolean
        if not isPlainTable(value) then
            return false
        end
        for key in value do
            if type(key) ~= "string" or fields[key] == nil then
                return false
            end
        end
        for key, check in fields do
            if not check(value[key]) then
                return false
            end
        end
        return true
    end
end
```

Le paquet de tir est ainsi validé avant d'atteindre la moindre ligne de gameplay :

```lua
-- src/Server/Services/CombatService.luau (l. 682–690)
local isFire = Guard.shape({
    w = Guard.string(16),
    n = Guard.integer(1, 2 ^ 31),
    o = Guard.vector3(1e5),
    a = Guard.unitVector(0.02),
    s = Guard.range(0, 45),
    t = Guard.number,
    ads = Guard.boolean,
})
```

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

```lua
-- src/Client/Controllers/WeaponController.luau (l. 833–853)
if mode == "Auto" then
    if not held then
        return
    end
    -- Planning périmé (gâchette relâchée) : on repart de maintenant, jamais plus tôt.
    if nextShotAt < now - 0.1 then
        nextShotAt = now
    end
    local shots = 0
    while held and nextShotAt <= now and shots < MAX_SHOTS_PER_FRAME do
        if ammo.mag <= 0 then
            onDry(def)
            return
        end
        local scheduled = nextShotAt
        fireOnce(def, scheduled, now, frameServer)
        local rpm = Weapons.currentRpm(def, heldTime)
        heldTime += 60 / rpm
        nextShotAt = scheduled + 60 / rpm
        shots += 1
    end
```

**Paquet de tir et état prédit.** `t` est l'horloge serveur (`GetServerTimeNow`) de
l'instant planifié, jamais plus proche du tir précédent que 97 % de l'intervalle minimal :
la synchronisation d'horloge peut « sauter » de quelques millisecondes entre deux frames,
et le serveur verrait sinon une cadence impossible. Le compteur `n`, le chargeur et le bloom
avancent localement **exactement** comme le serveur les fera avancer.

```lua
-- src/Client/Controllers/WeaponController.luau (l. 466–508)
local function fireOnce(def: WeaponDef, scheduledAt: number, frameClock: number, frameServer: number)
    local ammo = slotAmmo()
    if not ammo then
        return
    end
    -- Horloge serveur du tir PLANIFIÉ, jamais plus rapprochée du tir précédent que la
    -- cadence (la synchro d'horloge peut "sauter" de quelques ms entre deux frames).
    local shotServerTime = frameServer - (frameClock - scheduledAt)
    if lastShotWeapon == def.id then
        shotServerTime = math.max(shotServerTime, lastShotServer + Weapons.minInterval(def) * 0.97)
    end
    local origin, aim = CameraController.getAim()
    local cone = Spread.cone(def.spread, {
        ads = adsAlpha,
        speedRatio = MovementController.speedRatio(),
        airborne = MovementController.isAirborne(),
        crouched = MovementController.stance() ~= "Stand",
        bloom = Spread.decayBloom(def.spread, bloom, shotServerTime - lastShotServer),
        firstShot = shotServerTime - lastShotServer >= def.spread.firstShotReset,
    })
    local shot = counter
    local packet: Types.FirePacket = {
        w = def.id,
        n = shot,
        o = origin,
        a = aim,
        s = cone,
        t = shotServerTime,
        ads = adsAlpha >= 0.75,
    }
    Net.event("Fire"):FireServer(packet)

    -- État prédit (le serveur fait exactement la même comptabilité).
    counter += 1
    ammo.mag -= 1
    bloom = Spread.bloomAfterShot(def.spread, bloom, shotServerTime - lastShotServer)
    lastShotServer = shotServerTime
    lastShotWeapon = def.id
    lastShotClock = scheduledAt

    -- Balles prédites : mêmes directions que le serveur.
    local directions =
        Spread.directions(aim, cone, Spread.seed(seedBase, shot), def.damage.pellets, def.spread.pelletCone)
```

**Dispersion déterministe** (`Shared/Combat/Spread.luau`). Une seule formule de cône pour
le client, le serveur et le réticule du HUD : base hanche/ADS, précision de 1re balle,
bonus accroupi, pénalité de mouvement **au-delà de 34 % de la vitesse de course** (le
counter-strafe est récompensé), pénalité aérienne, bloom.

```lua
-- src/Shared/Combat/Spread.luau (l. 41–59)
function Spread.cone(profile: Types.SpreadProfile, state: SpreadState): number
    local base = MathUtil.lerp(profile.hip, profile.ads, MathUtil.clamp01(state.ads))
    if state.firstShot then
        base *= profile.firstShotMultiplier
    end
    if state.crouched then
        base *= profile.crouchMultiplier
    end
    local moveFactor =
        MathUtil.clamp01((state.speedRatio - Spread.ACCURATE_SPEED_RATIO) / (1 - Spread.ACCURATE_SPEED_RATIO))
    local cone = base + profile.move * moveFactor
    if state.airborne then
        cone += profile.air
    end
    if not state.firstShot then
        cone += state.bloom
    end
    return cone
end
```

```lua
-- src/Shared/Combat/Spread.luau (l. 91–125)
--[[
    Directions finales des projectiles.
      * balle unique : décalage aléatoire dans le cône, densité plus forte au centre
        (rayon ∝ u, pas √u) — les sprays restent lisibles et "justes" ;
      * plombs : motif fixe en tournesol (angle d'or) centré sur une direction dispersée,
        légère gigue seedée : forme reconnaissable, pas de "loterie" totale.
]]
function Spread.directions(
    aim: Vector3,
    coneDegrees: number,
    seed: number,
    pellets: number,
    pelletConeDegrees: number
): { Vector3 }
    local rng = Random.new(seed)
    local right, up = basis(aim)
    local radius = math.rad(math.max(coneDegrees, 0)) * rng:NextNumber()
    local theta = rng:NextNumber() * TWO_PI
    local center = if radius > 0 then offset(aim, right, up, radius, theta) else aim
    if pellets <= 1 then
        return { center }
    end

    local directions = table.create(pellets)
    local centerRight, centerUp = basis(center)
    local rotation = rng:NextNumber() * TWO_PI
    local cone = math.rad(pelletConeDegrees)
    for index = 1, pellets do
        local fraction = math.sqrt((index - 0.5) / pellets)
        local jitter = 0.85 + rng:NextNumber() * 0.3
        directions[index] =
            offset(center, centerRight, centerUp, cone * fraction * jitter, rotation + index * GOLDEN_ANGLE)
    end
    return directions
end
```

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

```lua
-- src/Server/Services/CombatService.luau (l. 696–802)
local function onFire(player: Player, packet: Types.FirePacket)
    local state = states[player]
    if not state or not CharacterService.isAlive(player) or not combatAllowed(player) then
        return
    end
    local character = player.Character
    if character and character:GetAttribute("Busy") == true then
        return
    end
    local now = Workspace:GetServerTimeNow()
    local slot = state.slots[state.equipped]
    local def = Weapons.get(packet.w)
    if not (slot and def) or slot.weaponId ~= packet.w or def.category == "Melee" then
        sync(state)
        return
    end
    if packet.n ~= state.counter then
        if packet.n < state.counter then
            AntiCheatService.flag(player, "ShotReplay", 2)
        end
        sync(state)
        return
    end
    if now - state.equippedAt < def.handling.equipTime * 0.7 then
        AntiCheatService.flag(player, "FastEquip", 1)
        sync(state)
        return
    end
    if state.reload then
        if state.reload.shell then
            settleReload(state, now, true)
        elseif not settleReload(state, now, false) then
            sync(state)
            return
        end
    end
    if slot.mag <= 0 then
        sync(state)
        return
    end
    if math.abs(packet.t - now) > 1.0 then
        AntiCheatService.flag(player, "ShotClock", 1)
        sync(state)
        return
    end
    -- Cadence : entre deux tirs de la MÊME arme (un changement d'arme est déjà borné par
    -- le temps d'équipement ; sinon SMG -> sniper serait refusé à tort).
    local interval = packet.t - state.lastShotClient
    if state.lastShotWeapon == def.id and interval < Weapons.minInterval(def) * 0.9 then
        AntiCheatService.flag(player, "FireRate", 2)
        sync(state)
        return
    end
    local recent = state.recentShots
    while #recent > 0 and now - recent[1] > 1 do
        table.remove(recent, 1)
    end
    if #recent >= math.ceil(maxShotsPerSecond(def)) + 2 then
        AntiCheatService.flag(player, "FireRateWindow", 3)
        sync(state)
        return
    end
    local eye = CharacterService.eyePosition(player)
    local _, _, root = CharacterService.getCharacter(player)
    if not (eye and root) then
        return
    end
    local tolerance = 3.5 + root.AssemblyLinearVelocity.Magnitude * 0.35
    if (packet.o - eye).Magnitude > tolerance then
        AntiCheatService.flag(player, "ShotOrigin", 3)
        sync(state)
        return
    end

    local minCone = minimumCone(def, state, packet, now)
    if packet.s < minCone - 0.05 then
        AntiCheatService.flag(player, "NoSpread", 1.5)
    end
    local cone = math.max(packet.s, minCone)
    checkAimSnap(player, packet.a, now)

    -- Le tir est accepté : on le "consomme".
    slot.mag -= 1
    state.counter += 1
    if def.fire.spinUp and interval < (60 / def.fire.spinUp.startRpm) * 1.6 then
        state.held += interval
    else
        state.held = 0
    end
    state.bloom = Spread.bloomAfterShot(def.spread, state.bloom, interval)
    state.lastShotClient = packet.t
    state.lastShotWeapon = def.id
    table.insert(recent, now)

    local seed = Spread.seed(state.seedBase, packet.n)
    local directions = Spread.directions(packet.a, cone, seed, def.damage.pellets, def.spread.pelletCone)
    local audit = audits[player]
    if not audit then
        audit = SpreadAudit.new()
        audits[player] = audit
    end
    local correlation = SpreadAudit.observe(audit, def.id, packet.t, packet.a, cone, SpreadAudit.offset(cone, seed))
    if correlation and correlation <= SpreadAudit.FLAG_CORRELATION then
        AntiCheatService.flag(player, "SpreadCompensation", 4)
    end
    resolveShot(player, state, def, packet, directions)
end
```

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

```lua
-- src/Server/Services/CombatService.luau (l. 327–349)
local function minimumCone(def: WeaponDef, state: State, packet: Types.FirePacket, now: number): number
    local character, humanoid, root = CharacterService.getCharacter(state.player)
    if not (character and humanoid and root) then
        return 0
    end
    local velocity = root.AssemblyLinearVelocity
    local flatSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
    local runSpeed = Movement.runSpeed * def.handling.moveMultiplier
    local adsTrusted = packet.ads and character:GetAttribute("Ads") == true
    local airborne = state.airborneSince ~= nil and now - (state.airborneSince :: number) > 0.25
    local sinceLast = packet.t - state.lastShotClient
    local firstShot = sinceLast >= def.spread.firstShotReset
    local bloom = if firstShot then 0 else Spread.decayBloom(def.spread, state.bloom, sinceLast) * 0.5
    local cone = Spread.cone(def.spread, {
        ads = if adsTrusted then 1 else 0,
        speedRatio = flatSpeed / runSpeed * 0.75,
        airborne = airborne,
        crouched = CharacterService.stanceOf(character) ~= "Stand",
        bloom = bloom,
        firstShot = firstShot,
    })
    return cone * 0.85
end
```

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

```lua
-- src/Server/Services/LagCompensationService.luau (l. 165–169)
--[[ Borne un temps de tir client à la fenêtre de rembobinage autorisée. ]]
function LagCompensationService.rewindTime(clientShotTime: number): number
    local now = Workspace:GetServerTimeNow()
    return math.clamp(clientShotTime - INTERP_DELAY, now - MAX_REWIND, now)
end
```

```lua
-- src/Server/Services/LagCompensationService.luau (l. 130–163)
--[[ Pose d'une cible à l'instant `t` (interpolée), ou la plus proche disponible. ]]
function LagCompensationService.poseAt(target: Target, t: number): (CFrame, Types.Stance, number)
    local history = histories[target.id]
    if not history or #history == 0 then
        return target.root.CFrame, target.stance(), target.lean()
    end
    local count = #history
    if t >= history[count].t then
        local last = history[count]
        return last.cframe, last.stance, last.lean
    end
    if t <= history[1].t then
        local first = history[1]
        return first.cframe, first.stance, first.lean
    end
    -- Recherche dichotomique de l'intervalle [i, i+1] qui encadre t.
    local low, high = 1, count
    while high - low > 1 do
        local mid = (low + high) // 2
        if history[mid].t <= t then
            low = mid
        else
            high = mid
        end
    end
    local a, b = history[low], history[high]
    local span = b.t - a.t
    local alpha = if span > 0 then (t - a.t) / span else 0
    local stance: Types.Stance = a.stance
    if alpha >= 0.5 then
        stance = b.stance
    end
    return a.cframe:Lerp(b.cframe, alpha), stance, a.lean + (b.lean - a.lean) * alpha
end
```

```lua
-- src/Server/Services/LagCompensationService.luau (l. 176–203)
--[[
    Rayon contre toutes les cibles acceptées par `filter`, chacune dans sa pose
    interpolée à l'instant rembobiné `t` ; garde la touche la plus proche. La tolérance
    de désynchronisation est l'`inflate` des boîtes (pas un second test à l'instant présent).
]]
function LagCompensationService.raycast(
    origin: Vector3,
    direction: Vector3,
    maxDistance: number,
    t: number,
    filter: (Target) -> boolean,
    inflate: number
): TargetHit?
    local best: TargetHit? = nil
    local bestDistance = maxDistance
    for _, target in targets do
        if not filter(target) then
            continue
        end
        local cframe: CFrame, stance: Types.Stance, lean: number = LagCompensationService.poseAt(target, t)
        local hit = Hitbox.raycast(origin, direction, bestDistance, cframe, stance, lean, inflate)
        if hit and hit.distance < bestDistance then
            bestDistance = hit.distance
            best = { target = target, result = hit }
        end
    end
    return best
end
```

**Hitboxes de gameplay** (`Shared/Combat/Hitbox.luau`) : des boîtes orientées (OBB) qui
dépendent **uniquement** de (CFrame, posture, lean) — jamais des Parts visuelles de l'avatar.
Un avatar miniature, une Part redimensionnée ou une animation trafiquée ne changent rien, et
le lean de la hitbox est **la même transformation** que celui de la caméra
(`Stances.leanTransform`) : on ne peut pas voir sans être visible. Test en deux phases :
sphère englobante (rejette presque toutes les cibles en une dizaine d'opérations), puis
rayon/OBB pour chaque partie, zone la plus proche retenue.

```lua
-- src/Shared/Combat/Hitbox.luau (l. 69–111)
--[[
    Lance un rayon contre une cible. `direction` doit être unitaire.
    Renvoie le résultat le plus proche ou nil.
]]
function Hitbox.raycast(
    origin: Vector3,
    direction: Vector3,
    maxDistance: number,
    rootCFrame: CFrame,
    stance: Types.Stance,
    lean: number,
    inflate: number
): HitResult?
    local profile = Stances.profiles[stance]
    local base = flatRoot(rootCFrame)
    local center = base * profile.broadphaseCenter
    local entry = MathUtil.raySphere(origin, direction, center, profile.broadphaseRadius + inflate)
    if entry == nil or entry > maxDistance then
        return nil
    end

    local leanCFrame = Stances.leanTransform(lean)
    local inflation = Vector3.new(inflate, inflate, inflate)
    local bestDistance = math.huge
    local bestPart: HitboxPart? = nil
    for _, hitPart in profile.parts do
        local local_ = if hitPart.upper then leanCFrame * hitPart.offset else hitPart.offset
        local t = MathUtil.rayOBB(origin, direction, base * local_, hitPart.size * 0.5 + inflation, maxDistance)
        if t and t < bestDistance then
            bestDistance = t
            bestPart = hitPart
        end
    end
    if bestPart == nil then
        return nil
    end
    return {
        distance = bestDistance,
        zone = bestPart.zone,
        part = bestPart.name,
        position = origin + direction * bestDistance,
    }
end
```

**Résolution** (par direction, donc par plomb) : rayon monde → rayon contre les hitboxes
rembobinées **jusqu'au premier obstacle** ; si l'obstacle est pénétrable : épaisseur mesurée
par un rayon retour, coût = épaisseur × résistance du matériau, 2 surfaces au plus. Les
plombs touchant une même cible sont **cumulés** (un seul impact, zone la plus haute).

```lua
-- src/Server/Services/CombatService.luau (l. 597–664)
local rewind = LagCompensationService.rewindTime(packet.t)
local params = worldParams()
local filter = enemyFilter(shooter)
local pending: { [number]: PendingHit } = {}
local endpoints: { Vector3 } = {}

for _, direction in directions do
    local origin = packet.o
    local remaining = def.damage.range
    local budget = def.damage.penetration
    local multiplier = 1
    local wallbang = false
    local travelled = 0
    local endpoint = origin + direction * remaining
    for pass = 0, Ballistics.MAX_PENETRATIONS do
        local world = Workspace:Raycast(origin, direction * remaining, params)
        local worldDistance = if world then world.Distance else remaining
        local hit = LagCompensationService.raycast(origin, direction, worldDistance, rewind, filter, HIT_INFLATE)
        if hit then
            local distance = travelled + hit.result.distance
            local damage = Ballistics.damage(def.damage, hit.result.zone, distance, multiplier)
            local existing = pending[hit.target.id]
            if existing then
                existing.damage += damage
                existing.wallbang = existing.wallbang or wallbang
                if ZONE_PRIORITY[hit.result.zone] > ZONE_PRIORITY[existing.zone] then
                    existing.zone = hit.result.zone
                    existing.position = hit.result.position
                end
            else
                pending[hit.target.id] = {
                    target = hit.target,
                    damage = damage,
                    zone = hit.result.zone,
                    wallbang = wallbang,
                    position = hit.result.position,
                    distance = distance,
                    direction = direction,
                }
            end
            endpoint = hit.result.position
            break
        end
        if not world then
            break
        end
        endpoint = world.Position
        if pass == Ballistics.MAX_PENETRATIONS then
            break
        end
        local thickness = measureThickness(world, direction)
        local impenetrable = world.Instance:GetAttribute("Impenetrable") == true
        local factor, left = Ballistics.penetrate(budget, thickness, world.Material, impenetrable)
        if factor == nil then
            break
        end
        multiplier *= factor
        budget = left
        wallbang = true
        travelled += worldDistance + thickness
        origin = world.Position + direction * (thickness + 0.05)
        remaining -= worldDistance + thickness
        if remaining <= 1 then
            break
        end
    end
    table.insert(endpoints, endpoint)
end
```

**Balistique** (`Shared/Combat/Ballistics.luau`) : dégâts = base × zone × chute (interpolée
entre paliers) × pénétration, arrondis à l'entier (les joueurs raisonnent en « taps ») ; le
bouclier absorbe 66 % de chaque impact tant qu'il en reste. Tableaux de dégâts, de chute et
de TTK de toutes les armes : [07-weapons.md §7.2](07-weapons.md#72-tableaux-de-référence).

```lua
-- src/Shared/Combat/Ballistics.luau (l. 84–95)
function Ballistics.damage(
    profile: Types.DamageProfile,
    zone: Types.HitZone,
    distance: number,
    penetrationMultiplier: number
): number
    local raw = profile.base
        * Ballistics.zoneMultiplier(profile, zone)
        * Ballistics.falloff(profile, distance)
        * penetrationMultiplier
    return math.max(1, math.floor(raw + 0.5))
end
```

```lua
-- src/Shared/Combat/Ballistics.luau (l. 97–104)
--[[
    Applique des dégâts à (PV, bouclier). Renvoie (PV, bouclier, perte PV, perte bouclier).
]]
function Ballistics.apply(health: number, armor: number, damage: number): (number, number, number, number)
    local armorLoss = math.min(armor, damage * Ballistics.ARMOR_ABSORB)
    local healthLoss = math.min(health, damage - armorLoss)
    return health - healthLoss, armor - armorLoss, healthLoss, armorLoss
end
```

```lua
-- src/Shared/Combat/Ballistics.luau (l. 106–125)
--[[
    Coût de pénétration d'une surface. Renvoie le multiplicateur de dégâts restant et le
    budget restant, ou nil si la balle est arrêtée.
]]
function Ballistics.penetrate(
    budget: number,
    thickness: number,
    material: Enum.Material,
    impenetrable: boolean
): (number?, number)
    if impenetrable then
        return nil, 0
    end
    local cost = thickness * Ballistics.resistance(material)
    if cost >= budget then
        return nil, 0
    end
    local multiplier = 1 - 0.6 * (cost / budget)
    return multiplier, budget - cost
end
```

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

```lua
-- src/Shared/Rules/RankMath.luau (l. 56–62)
function RankMath.kFactor(matches: number, placements: number): number
    if placements < Ranks.PLACEMENT_MATCHES then
        return 64
    end
    local t = math.clamp((matches - Ranks.PLACEMENT_MATCHES) / 30, 0, 1)
    return 48 + (24 - 48) * t
end
```

```lua
-- src/Shared/Rules/RankMath.luau (l. 64–75)
function RankMath.mmrDelta(state: RankState, outcome: Outcome): number
    local score = if outcome.won then 1 elseif outcome.draw then 0.5 else 0
    local k = RankMath.kFactor(state.Matches, state.Placements)
    local delta = k * (score - RankMath.expected(outcome.teamMMR, outcome.enemyMMR))
    local performance = math.clamp(outcome.performance, -1, 1)
    if delta >= 0 then
        delta *= 1 + 0.15 * performance
    else
        delta *= 1 - 0.15 * performance
    end
    return math.floor(delta + 0.5)
end
```

**RR.** Base 18, plus la convergence (±4 RR par division d'écart entre rang attendu et rang
affiché, plafonnée à ±10), plus la performance (±6). Bornes : victoire [8, 35], défaite
−[6, 32], égalité [−5, 5]. Promotion à 100 RR (surplus conservé), rétrogradation sous 0 (on
retombe à 75 RR au plus dans la division inférieure), jamais sous RECRUIT I.

```lua
-- src/Shared/Rules/RankMath.luau (l. 77–87)
function RankMath.rrDelta(rankIndex: number, newMMR: number, outcome: Outcome): number
    local convergence = math.clamp((Ranks.expectedIndex(newMMR) - rankIndex) * 4, -10, 10)
    local performance = math.clamp(outcome.performance, -1, 1) * 6
    if outcome.draw then
        return math.floor(math.clamp(convergence * 0.5 + performance, -5, 5) + 0.5)
    elseif outcome.won then
        return math.floor(math.clamp(18 + convergence + performance, 8, 35) + 0.5)
    else
        return -math.floor(math.clamp(18 - convergence - performance, 6, 32) + 0.5)
    end
end
```

```lua
-- src/Shared/Rules/RankMath.luau (l. 89–106)
--[[ Applique un delta de RR avec promotions/rétrogradations en cascade. ]]
function RankMath.applyRR(rankIndex: number, rr: number, delta: number): (number, number)
    local index, value = rankIndex, rr + delta
    while value >= 100 and index < Ranks.MAX_INDEX do
        value -= 100
        index += 1
    end
    while value < 0 do
        if index <= 0 then
            value = 0
            break
        end
        -- Rétrogradation : on retombe au plus à 75 RR dans la division inférieure.
        index -= 1
        value = math.min(value + 100, 75)
    end
    return index, value
end
```

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

```lua
-- src/Server/Services/ProgressionService.luau (l. 168–200)
-- 3. Rang classé
local rankBefore, rrBefore = data.Rank.RankIndex, data.Rank.RR
local rrDelta = 0
if result.ranked then
    local enemy: Types.TeamId = if entry.team == "A" then "B" else "A"
    local performance = math.clamp((stats.score - averageScore) / math.max(averageScore, 1), -1, 1)
    local outcome: RankMath.Outcome = {
        won = won,
        draw = draw,
        teamMMR = mmr[entry.team],
        enemyMMR = mmr[enemy],
        performance = performance,
    }
    local ranked = RankMath.process(data.Rank :: any, outcome)
    PlayerService.set(player, { "Rank" }, ranked.state)
    rrDelta = ranked.rrDelta
    if ranked.promoted or ranked.placed then
        PlayerService.notify(
            player,
            "RankUp",
            Ranks.displayName(ranked.state.RankIndex),
            { rankIndex = ranked.state.RankIndex }
        )
    elseif ranked.demoted then
        PlayerService.notify(
            player,
            "RankDown",
            Ranks.displayName(ranked.state.RankIndex),
            { rankIndex = ranked.state.RankIndex }
        )
    end
    LeaderboardService.submit(player)
end
```

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

```lua
-- src/Server/Services/DataService.luau (l. 134–157)
local function tryAcquire(key: string, steal: boolean): (LoadStatus, any)
    local status: LoadStatus = "Error"
    local loadedData: any = nil
    local ok, err = pcall(function()
        store.update(key, function(record: Record?): Record?
            local current: Record = record or { Data = nil, Session = nil }
            local session = current.Session
            local now = os.time()
            if session and session.JobId ~= jobId and (now - session.Time) < SESSION_TIMEOUT and not steal then
                status = "Locked"
                return nil -- annule l'écriture
            end
            current.Session = { JobId = jobId, PlaceId = game.PlaceId, Time = now }
            status = "Loaded"
            loadedData = current.Data
            return current
        end)
    end)
    if not ok then
        log:warn("acquire failed", key, err)
        return "Error", nil
    end
    return status, loadedData
end
```

```lua
-- src/Server/Services/DataService.luau (l. 177–232)
local function loadProfile(player: Player)
    local key = "Player_" .. player.UserId
    loading[player] = true
    local started = os.clock()
    local attempt = 0
    local status: LoadStatus = "Error"
    local raw: any = nil
    while player.Parent == Players do
        attempt += 1
        local steal = os.clock() - started > LOCK_STEAL_AFTER
        status, raw = tryAcquire(key, steal)
        if status == "Loaded" then
            break
        end
        if attempt >= 10 then
            break
        end
        task.wait(if status == "Locked" then 3 else math.min(2 ^ attempt, 8))
    end
    loading[player] = nil

    if status ~= "Loaded" then
        if player.Parent == Players then
            log:error("profile load failed for", player.Name, "status", status)
            player:Kick("AETHER STRIKE — Impossible de charger votre profil. Réessayez dans un instant.")
        end
        return
    end

    -- Le joueur est parti pendant le chargement : on rend le verrou immédiatement.
    if player.Parent ~= Players then
        releaseLock(key, nil)
        return
    end

    local data = ProfileTemplate.reconcile(ProfileTemplate.migrate(raw or ProfileTemplate.new()))
    local now = os.time()
    if data.Meta.FirstJoin == 0 then
        data.Meta.FirstJoin = now
    end
    data.Meta.LastJoin = now
    data.Meta.Sessions += 1

    local profile: Profile = {
        player = player,
        key = key,
        data = data,
        loadedAt = now,
        lastSave = os.clock(),
        released = false,
        saving = false,
    }
    profiles[player] = profile
    log:info("profile loaded", player.Name, ("(%.2fs)"):format(os.clock() - started))
    DataService.ProfileLoaded:Fire(player, profile)
end
```

Sauvegarde automatique toutes les 90 s (étalée), **toujours** via `UpdateAsync` qui vérifie
que la session nous appartient encore — sinon on n'écrit rien et on expulse : le serveur qui
a perdu le verrou ne peut jamais écraser des données plus récentes.

```lua
-- src/Server/Services/DataService.luau (l. 243–284)
--[[ Sauvegarde ; renvoie false si la session a été volée ou en cas d'échec. ]]
local function saveProfile(profile: Profile, release: boolean): boolean
    if profile.released then
        return false
    end
    if serializedSize(profile.data) > MAX_DATA_BYTES then
        log:error("profile too large, save refused", profile.key)
        return false
    end
    while profile.saving do
        task.wait(0.1)
    end
    profile.saving = true
    local stolen = false
    local snapshot = profile.data
    local ok = withRetries("save " .. profile.key, if release then 5 else 3, function()
        store.update(profile.key, function(record: Record?): Record?
            local current: Record = record or { Data = nil, Session = nil }
            if current.Session and current.Session.JobId ~= jobId then
                stolen = true
                return nil
            end
            current.Data = snapshot
            current.Session = if release then nil else { JobId = jobId, PlaceId = game.PlaceId, Time = os.time() }
            return current
        end)
    end)
    profile.saving = false
    profile.lastSave = os.clock()
    if release then
        profile.released = true
    end
    if stolen then
        profile.released = true
        log:warn("session stolen for", profile.key)
        if profile.player.Parent == Players then
            profile.player:Kick("AETHER STRIKE — Votre profil a été ouvert sur un autre serveur.")
        end
        return false
    end
    return ok
end
```

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

```lua
-- src/Server/Services/PurchaseService.luau (l. 45–88)
local function processReceipt(receipt: { [string]: any }): Enum.ProductPurchaseDecision
    local player = Players:GetPlayerByUserId(receipt.PlayerId)
    if not player then
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end
    local profile = DataService.getProfile(player)
    if not profile then
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end
    local purchaseId = tostring(receipt.PurchaseId)
    local purchases = profile.data.Purchases
    if purchases[purchaseId] then
        return Enum.ProductPurchaseDecision.PurchaseGranted
    end
    local product = Products.byProductId(receipt.ProductId)
    if not product then
        log:warn("produit inconnu", receipt.ProductId)
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end
    local premiumBefore = profile.data.Pass.Premium
    if product.crystals then
        InventoryService.addCrystals(player, product.crystals)
    end
    if product.premiumPass then
        PlayerService.set(player, { "Pass", "Premium" }, true)
    end
    purchases[purchaseId] = os.time()
    pruneReceipts(purchases)
    if not DataService.saveNow(player) then
        -- Annulation COMPLÈTE (reçu + octroi) : Roblox rejouera le reçu. Rien ne doit rester
        -- accordé d'ici là, sinon l'autosave suivante persisterait un achat crédité deux fois.
        purchases[purchaseId] = nil
        if product.crystals then
            InventoryService.addCrystals(player, -product.crystals)
        end
        if product.premiumPass then
            PlayerService.set(player, { "Pass", "Premium" }, premiumBefore)
        end
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end
    PlayerService.notify(player, "Purchase", product.displayName, { product = product.key })
    log:info("achat accordé", player.Name, product.key)
    return Enum.ProductPurchaseDecision.PurchaseGranted
end
```

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

```lua
-- src/Server/Services/ReplicaService.luau (l. 108–123)
local function broadcast(internal: Internal, op: number, path: Path, a: any, b: any)
    if #path > 0 and internal.private[tostring(path[1])] then
        return
    end
    if internal.all then
        for player in ready do
            updateRemote:FireClient(player, internal.id, op, path, a, b)
        end
    else
        for player in internal.subscribers do
            if ready[player] then
                updateRemote:FireClient(player, internal.id, op, path, a, b)
            end
        end
    end
end
```

```lua
-- src/Server/Services/ReplicaService.luau (l. 132–139)
function ReplicaClass.Set(self: any, path: Path, value: any)
    local internal = internalOf(self)
    if internal.destroyed then
        return
    end
    ReplicaPath.set(internal.data, path, value)
    broadcast(internal, ReplicaPath.OP_SET, path, value, nil)
end
```

Un client ne reçoit rien avant d'avoir signalé `ReplicaRequest` (tous ses écouteurs
existent : `ReplicaController` démarre en dernier), puis reçoit tous ses replicas d'un coup.

**Flux haute fréquence en binaire.** La visée de chaque joueur (poses en 3e personne,
spectateur, killcam, anti-cheat) part en `buffer` de 4 octets à 30 Hz et revient en **un seul
paquet non fiable par arène** à 20 Hz, 5 octets par joueur (précision 0.0055° en lacet,
0.0027° en tangage) : 6 joueurs = 30 octets par paquet, au lieu de ~20 octets *par joueur*
en tables Luau.

```lua
-- src/Shared/Net/LookCodec.luau (l. 56–65)
function LookCodec.encodeBatch(entries: { Entry }): buffer
    local b = buffer.create(#entries * 5)
    for index, entry in entries do
        local offset = (index - 1) * 5
        buffer.writeu8(b, offset, entry.slot)
        buffer.writeu16(b, offset + 1, quantizeYaw(entry.yaw))
        buffer.writei16(b, offset + 3, quantizePitch(entry.pitch))
    end
    return b
end
```

## 10.8 Règles de manche et machine à états du match

Toutes les décisions de règles sont **pures** (`Shared/Rules/MatchRules.luau`, aucune
dépendance au moteur, testées hors Roblox) ; `MatchInstance` ne fait que les appliquer.

```lua
-- src/Shared/Rules/MatchRules.luau (l. 45–65)
--[[ Renvoie l'équipe gagnante du match, ou nil si le match continue. ]]
function MatchRules.matchWinner(mode: ModeDef, scoreA: number, scoreB: number): Types.TeamId?
    if MatchRules.isOvertime(mode, scoreA, scoreB) then
        local played = MatchRules.overtimeRoundsPlayed(mode, scoreA, scoreB)
        local lead = scoreA - scoreB
        local suddenDeath = played > mode.overtimeMaxRounds
        local required = if suddenDeath then 1 else 2
        if lead >= required then
            return "A"
        elseif -lead >= required then
            return "B"
        end
        return nil
    end
    if scoreA >= mode.roundsToWin then
        return "A"
    elseif scoreB >= mode.roundsToWin then
        return "B"
    end
    return nil
end
```

```lua
-- src/Shared/Rules/MatchRules.luau (l. 74–82)
--[[ Faut-il changer de côté après la manche `roundPlayed` (scores APRÈS la manche) ? ]]
function MatchRules.sideSwapDue(mode: ModeDef, roundPlayed: number, scoreA: number, scoreB: number): boolean
    -- En prolongation : alternance des côtés à chaque manche jouée.
    if MatchRules.isOvertime(mode, scoreA, scoreB) and MatchRules.overtimeRoundsPlayed(mode, scoreA, scoreB) > 0 then
        return true
    end
    -- Sinon : échange unique à la mi-temps (équité des spawns, y compris en Élimination).
    return mode.halfAfter > 0 and roundPlayed == mode.halfAfter
end
```

```lua
-- src/Shared/Rules/MatchRules.luau (l. 110–159)
--[[
    Décide si la manche est terminée et pour qui. Renvoie (gagnant, raison) ou nil.
    Raisons : "Elimination", "Detonation", "Defuse", "Time", "Draw".
]]
function MatchRules.evaluateRound(s: RoundSituation): (Types.TeamId?, string?)
    if s.objective == "Elimination" then
        if s.aliveA == 0 and s.aliveB == 0 then
            return nil, "Draw"
        elseif s.aliveA == 0 then
            return "B", "Elimination"
        elseif s.aliveB == 0 then
            return "A", "Elimination"
        elseif s.timeUp then
            local winner: Types.TeamId? = MatchRules.eliminationTimeout(s.snapshotA, s.snapshotB)
            local reason: string = if winner then "Time" else "Draw"
            return winner, reason
        end
        return nil, nil
    end

    local attack: Types.TeamId = if s.sides.A == "Attack" then "A" else "B"
    local defense: Types.TeamId = MatchRules.other(attack)
    local aliveAttack = if attack == "A" then s.aliveA else s.aliveB
    local aliveDefense = if defense == "A" then s.aliveA else s.aliveB

    if s.detonated then
        return attack, "Detonation"
    end
    if s.defused then
        return defense, "Defuse"
    end
    if s.planted then
        -- Charge posée : seule la détonation ou le désamorçage terminent la manche,
        -- sauf si toute la défense est morte (victoire attaque immédiate).
        if aliveDefense == 0 then
            return attack, "Elimination"
        end
        return nil, nil
    end
    if aliveDefense == 0 then
        return attack, "Elimination"
    end
    if aliveAttack == 0 then
        return defense, "Elimination"
    end
    if s.timeUp then
        return defense, "Time"
    end
    return nil, nil
end
```

Machine à états du match, mise à jour à chaque `Heartbeat` (horloge serveur) :

```
Waiting ─► Intro ─► Prep ─► Live ─┬──────────────────────────► RoundEnd ─┬─► MatchEnd ─► Closed
   │                 ▲            └─(pose, Uplink)─► Planted ─┘          │   (XP, RR, retour)
   │                 ├────────────────── manche suivante ────────────────┤
   │                 └──── SideSwap ◄── mi-temps / prolongation ─────────┘
   └─ délai écoulé avec une équipe absente : forfait ─► MatchEnd
```

```lua
-- src/Server/Match/MatchInstance.luau (l. 913–985)
function MatchInstance.update(self: MatchInstance, t: number)
    if self.closed then
        return
    end
    local state = self.state
    local phase = state.phase
    if phase == "Waiting" then
        local ready = connectedCount(self, "A") >= 1 and connectedCount(self, "B") >= 1
        local everyone = true
        for userId in self.expected do
            local player = Players:GetPlayerByUserId(userId)
            if not (player and self.entries[player] and self.entries[player].connected) then
                everyone = false
            end
        end
        if everyone or (t >= state.phaseEndsAt and ready) then
            setPhase(self, "Intro", self.mode.introTime)
            event(self, { kind = "Intro", text = self.spec.map })
        elseif t >= state.phaseEndsAt then
            finishMatch(
                self,
                if connectedCount(self, "A") > 0 then "A" elseif connectedCount(self, "B") > 0 then "B" else nil,
                true
            )
        end
    elseif phase == "Intro" then
        if t >= state.phaseEndsAt then
            startRound(self)
        end
    elseif phase == "Prep" then
        if t >= state.phaseEndsAt then
            goLive(self)
        end
    elseif phase == "Live" or phase == "Planted" then
        local planted, defused, detonated = tickObjective(self, t)
        local aliveA, aliveB = #aliveIn(self, "A"), #aliveIn(self, "B")
        local winner: TeamId?, reason: string? = MatchRules.evaluateRound({
            objective = self.mode.objective,
            sides = state.sides,
            aliveA = aliveA,
            aliveB = aliveB,
            planted = planted,
            defused = defused,
            detonated = detonated,
            timeUp = phase == "Live" and t >= state.phaseEndsAt,
            snapshotA = teamSnapshot(self, "A"),
            snapshotB = teamSnapshot(self, "B"),
        })
        if reason then
            endRound(self, winner, reason)
        end
    elseif phase == "RoundEnd" then
        if t >= state.phaseEndsAt then
            local winner: TeamId? = MatchRules.matchWinner(self.mode, state.scores.A, state.scores.B)
            if winner then
                finishMatch(self, winner, false)
            elseif self.swapPending then
                setPhase(self, "SideSwap", 3)
                event(self, { kind = "SideSwapBanner" })
            else
                startRound(self)
            end
        end
    elseif phase == "SideSwap" then
        if t >= state.phaseEndsAt then
            startRound(self)
        end
    elseif phase == "MatchEnd" then
        if t >= state.phaseEndsAt then
            self:close()
        end
    end
end
```

## 10.9 Matchmaking : équilibre, attente bornée, inter-serveurs

**Algorithme** (`Shared/Rules/MatchmakingAlgorithm.luau`, pur et testé) : les tickets les plus
anciens servent d'ancres ; la fenêtre de MMR s'élargit avec l'attente (75 + 6 × attente,
plafond 600) et, en classé, l'écart de rang autorisé aussi (3 divisions, +1 toutes les 20 s,
plafond 9). Parmi les candidats compatibles **deux à deux**, on cherche un groupe de tickets
totalisant exactement 2 × taille d'équipe (une party n'est **jamais** séparée), puis la
partition en deux équipes qui minimise l'écart de MMR moyen (énumération exhaustive :
≤ 6 tickets → ≤ 32 partitions). Score = écart entre équipes + 0.25 × dispersion : des équipes
équilibrées **et** homogènes.

```lua
-- src/Shared/Rules/MatchmakingAlgorithm.luau (l. 94–106)
local function compatible(config: Config, ranked: boolean, a: MatchTicket, b: MatchTicket, now: number): boolean
    local waited = math.max(now - a.enqueuedAt, now - b.enqueuedAt)
    if math.abs(a.mmr - b.mmr) > MatchmakingAlgorithm.window(config, waited) then
        return false
    end
    if ranked then
        local gap = math.max(a.maxRank, b.maxRank) - math.min(a.minRank, b.minRank)
        if gap > MatchmakingAlgorithm.rankGap(config, waited) then
            return false
        end
    end
    return true
end
```

```lua
-- src/Shared/Rules/MatchmakingAlgorithm.luau (l. 64–92)
--[[ Meilleure partition de `group` en deux équipes de `teamSize` joueurs. ]]
function MatchmakingAlgorithm.bestSplit(group: { MatchTicket }, teamSize: number): MatchProposal?
    local count = #group
    local best: MatchProposal? = nil
    local bestDiff = math.huge
    -- Le ticket 1 est toujours dans l'équipe A : évite les partitions symétriques en double.
    for mask = 0, (2 ^ (count - 1)) - 1 do
        local teamA: { MatchTicket } = { group[1] }
        local teamB: { MatchTicket } = {}
        local sizeA = #group[1].players
        for index = 2, count do
            if bit32.band(mask, 2 ^ (index - 2)) ~= 0 then
                table.insert(teamA, group[index])
                sizeA += #group[index].players
            else
                table.insert(teamB, group[index])
            end
        end
        if sizeA == teamSize then
            local mmrA, mmrB = teamAverage(teamA), teamAverage(teamB)
            local diff = math.abs(mmrA - mmrB)
            if diff < bestDiff then
                bestDiff = diff
                best = { teamA = teamA, teamB = teamB, mmrA = mmrA, mmrB = mmrB, quality = 0 }
            end
        end
    end
    return best
end
```

**Backend cloud.** Tickets dans un `MemoryStoreSortedMap` par file (TTL 90 s rafraîchi : un
lobby qui plante ne laisse pas de tickets fantômes) ; un **leader** unique (verrou MemoryStore
de 8 s) exécute l'algorithme toutes les 2 s, réserve un serveur
(`TeleportService:ReserveServer`), écrit la `MatchSpec` sous la clé `PrivateServerId` et une
affectation par ticket ; chaque lobby interroge les affectations de **ses** tickets, affiche
« MATCH TROUVÉ » et téléporte la party. Cinq erreurs MemoryStore d'affilée : bascule
automatique sur le matchmaking local.

```lua
-- src/Server/Services/MatchmakingService.luau (l. 353–363)
local function isLeader(): boolean
    local ok, result = cloudCall("leader", function()
        return MemoryStoreService:GetSortedMap(LOCK_MAP):UpdateAsync("leader", function(current: any): any
            if current == nil or current == game.JobId then
                return game.JobId
            end
            return nil
        end, 8)
    end)
    return ok and result == game.JobId
end
```

**Frontière de confiance.** Le serveur de match lit sa composition dans MemoryStore — jamais
dans les `TeleportData`, falsifiables par le client — et la valide comme n'importe quelle
entrée ; un joueur non attendu est expulsé.

```lua
-- src/Server/Services/MatchService.luau (l. 130–148)
local function decodeSpec(value: any): Types.MatchSpec?
    if type(value) ~= "string" then
        return nil
    end
    local ok, decoded = pcall(HttpService.JSONDecode, HttpService, value)
    if not ok or type(decoded) ~= "table" then
        return nil
    end
    local valid = Guard.shape({
        matchId = Guard.string(64),
        mode = Guard.string(16),
        map = Guard.string(16),
        ranked = Guard.boolean,
        custom = Guard.boolean,
        teams = Guard.shape({ A = Guard.array(Guard.number, 3), B = Guard.array(Guard.number, 3) }),
        createdAt = Guard.number,
    })
    return if valid(decoded) then decoded :: Types.MatchSpec else nil
end
```

L'estimation affichée en file est la moyenne glissante des 20 dernières attentes de la même
file (45 s par défaut) : une estimation honnête, pas un chiffre décoratif.

```lua
-- src/Server/Services/MatchmakingService.luau (l. 94–104)
local function estimate(key: string): number
    local samples = waitSamples[key]
    if not samples or #samples == 0 then
        return 45
    end
    local total = 0
    for _, value in samples do
        total += value
    end
    return math.floor(total / #samples + 0.5)
end
```

## 10.10 Mouvement : modèle « Source-like » piloté sur un Humanoid

Le Humanoid reste le **corps** (collisions, sol, marches, pentes) ; notre modèle décide de la
**vitesse** à chaque frame (`PreSimulation`), en partant de la vitesse réelle du HRP (murs et
collisions déjà appliqués). Friction exponentielle avec arrêt net sous `stopSpeed`, puis
accélération vers la vitesse souhaitée — le même couple de fonctions qui rend le
counter-strafe (≈ 40–50 ms) et le contrôle aérien possibles ([06-movement.md](06-movement.md)).

```lua
-- src/Client/Controllers/MovementController.luau (l. 99–107)
local function applyFriction(velocity: Vector3, dt: number): Vector3
    local speed = velocity.Magnitude
    if speed < 0.05 then
        return Vector3.zero
    end
    local control = math.max(speed, Movement.stopSpeed)
    local newSpeed = math.max(speed - control * Movement.friction * dt, 0)
    return velocity * (newSpeed / speed)
end
```

```lua
-- src/Client/Controllers/MovementController.luau (l. 109–128)
local function accelerate(
    velocity: Vector3,
    wishDir: Vector3,
    wishSpeed: number,
    accel: number,
    dt: number,
    cap: number?
): Vector3
    if wishSpeed <= 0 then
        return velocity
    end
    local current = velocity:Dot(wishDir)
    local limit = if cap then math.min(wishSpeed, cap) else wishSpeed
    local add = limit - current
    if add <= 0 then
        return velocity
    end
    local accelSpeed = math.min(accel * dt * wishSpeed, add)
    return velocity + wishDir * accelSpeed
end
```

```lua
-- src/Client/Controllers/MovementController.luau (l. 321–367)
-- Vitesse souhaitée
local base = if stance == "Crouch"
    then Movement.crouchSpeed
    elseif walking then Movement.walkSpeed
    else Movement.runSpeed
local multiplier = weaponMove * (if adsActive then adsMove else 1)
if now < landingSlowUntil then
    multiplier *= Movement.landing.slowMultiplier
end
local tagged = character and character:GetAttribute("TaggedUntil")
if type(tagged) == "number" and Workspace:GetServerTimeNow() < tagged then
    multiplier *= Movement.tagging.multiplier
end
local wishSpeed = base * multiplier * analog

if stance == "Slide" then
    slideTime += dt
    local normal = floorNormal()
    local downhill = normal:Dot(slideDir)
    local decel = Movement.slide.friction + Movement.slide.frictionGrowth * slideTime
    slideSpeed = math.clamp(
        slideSpeed - decel * dt + Workspace.Gravity * downhill * Movement.slide.slopeGain * dt,
        0,
        Movement.slide.speedCap
    )
    if wishDir.Magnitude > 0 then
        local steered = slideDir + wishDir * Movement.slide.steer * dt * 4
        slideDir = MathUtil.flat(steered).Unit
    end
    flat = slideDir * slideSpeed
    local airborneTooLong = not grounded and now - airborneSince > 0.15
    if slideSpeed < Movement.crouchSpeed + 0.5 or slideTime > Movement.slide.maxDuration or airborneTooLong then
        endSlide(wantsCrouch())
    end
elseif grounded then
    local hopping = now - lastLandAt <= Movement.bhopWindow and jumpBufferedAt ~= nil
    if not hopping then
        flat = applyFriction(flat, dt)
    end
    flat = accelerate(flat, wishDir, wishSpeed, Movement.groundAccelerate, dt, nil)
    airCap = Movement.runSpeed * Movement.maxAirSpeedRatio
else
    flat = accelerate(flat, wishDir, wishSpeed, Movement.airAccelerate, dt, Movement.airWishCap)
    if flat.Magnitude > airCap then
        flat = flat.Unit * airCap
    end
end
```

Le bunny-hop existe mais s'**érode** : l'excédent au-dessus de la vitesse de course est
multiplié par 0.94ⁿ à chaque hop enchaîné, et la vitesse aérienne est plafonnée — de la
technique, jamais du chaos (les seuils serveur de [§10.11](#1011-anti-exploit) restent hors
d'atteinte avec marge).

```lua
-- src/Client/Controllers/MovementController.luau (l. 237–245)
-- Bunny-hop léger : l'excédent au-dessus de la vitesse de course s'érode à chaque hop.
if now - lastLandAt <= Movement.bhopWindow then
    hopChain += 1
    local excess = math.max(carry - Movement.runSpeed, 0)
    carry = Movement.runSpeed + excess * (Movement.bhopDecay ^ hopChain)
else
    hopChain = 0
end
airCap = math.max(Movement.runSpeed * Movement.maxAirSpeedRatio, math.min(carry, Movement.slide.speedCap))
```

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

```lua
-- src/Server/Services/AntiCheatService.luau (l. 99–125)
--[[ Signale une violation. `weight` : 0.5 (spam) … 100 (pot de miel). ]]
function AntiCheatService.flag(player: Player, reason: string, weight: number)
    if player.Parent ~= Players then
        return
    end
    local state = getState(player)
    state.score += weight
    log:debug(player.Name, "flag", reason, ("+%.1f -> %.1f"):format(weight, state.score))

    if state.score >= WARN_SCORE and not state.warned then
        state.warned = true
        log:warn("suspicion élevée", player.Name, player.UserId, reason, state.score)
        pcall(function()
            AnalyticsService:LogCustomEvent(player, "AntiCheatWarning", state.score, { reason = reason })
        end)
    end

    if state.score >= KICK_SCORE then
        local data = DataService.getData(player)
        if data then
            data.Moderation.Suspicion += 1
            data.Moderation.Flags[reason] = (data.Moderation.Flags[reason] or 0) + 1
        end
        log:warn("expulsion", player.Name, player.UserId, reason)
        player:Kick("AETHER STRIKE — Activité anormale détectée (" .. reason .. ").")
    end
end
```

Mouvement : la vitesse est mesurée sur **deux fenêtres** — une rafale d'1 s (plafond =
vitesse maximale de glissade × 1.15 = 34.5 studs/s) et une moyenne sur 3 s (course × plafond
aérien × 1.08 × 1.15 ≈ 24.3 studs/s) qui attrape les speedhacks « discrets » (×1.3–1.5)
qu'un seuil instantané laisserait passer.

```lua
-- src/Server/Services/AntiCheatService.luau (l. 146–237)
local function checkPlayer(player: Player, state: State, now: number)
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not (root and root:IsA("BasePart") and humanoid and humanoid.Health > 0) then
        state.samples = {}
        state.lastValid = nil
        return
    end
    local position = root.Position
    if now < state.graceUntil then
        state.samples = { { t = now, position = position } }
        state.lastValid = position
        return
    end

    local samples = state.samples
    local previous = samples[#samples]
    table.insert(samples, { t = now, position = position })
    while #samples > 0 and now - samples[1].t > HISTORY_SECONDS do
        table.remove(samples, 1)
    end

    local violation: string? = nil
    local weight = 0

    if previous then
        local step = position - previous.position
        local flatStep = Vector3.new(step.X, 0, step.Z).Magnitude
        local dt = math.max(now - previous.t, 1 / 60)
        if flatStep > TELEPORT_DISTANCE + BURST_MAX_SPEED * dt then
            violation, weight = "Teleport", 8
        elseif step.Y / dt > MAX_UPWARD_SPEED then
            violation, weight = "VerticalSpeed", 5
        elseif flatStep > 2 and state.lastValid then
            -- Noclip : la ligne entre la dernière position valide et l'actuelle traverse-t-elle un mur ?
            rayParams.FilterDescendantsInstances = geometryRoots()
            local origin = state.lastValid + Vector3.new(0, 1, 0)
            local result = Workspace:Raycast(origin, (position + Vector3.new(0, 1, 0)) - origin, rayParams)
            if result and result.Instance.CanCollide and result.Instance.Transparency < 1 then
                violation, weight = "Noclip", 8
            end
        end
    end

    if not violation then
        -- Fenêtre burst (1 s) et fenêtre soutenue (3 s)
        local burstStart: Sample? = nil
        for _, sample in samples do
            if now - sample.t <= 1.05 then
                burstStart = sample
                break
            end
        end
        if burstStart and now - burstStart.t >= 0.5 then
            local d = position - burstStart.position
            local speed = Vector3.new(d.X, 0, d.Z).Magnitude / (now - burstStart.t)
            if speed > BURST_MAX_SPEED then
                violation, weight = "SpeedBurst", 4
            end
        end
        local oldest = samples[1]
        if not violation and oldest and now - oldest.t >= HISTORY_SECONDS - 0.2 then
            local d = position - oldest.position
            local speed = Vector3.new(d.X, 0, d.Z).Magnitude / (now - oldest.t)
            if speed > SUSTAINED_MAX_SPEED then
                violation, weight = "SpeedSustained", 5
            end
        end
    end

    -- Fly : pas de sol pendant longtemps sans tomber.
    if humanoid.FloorMaterial == Enum.Material.Air then
        state.airSince = state.airSince or now
        if now - (state.airSince :: number) > FLY_TIME and root.AssemblyLinearVelocity.Y > -4 then
            violation, weight = "Fly", 6
            state.airSince = now
        end
    else
        state.airSince = nil
    end

    if violation then
        if state.lastValid then
            rubberBand(root, state.lastValid)
        end
        state.samples = {}
        AntiCheatService.flag(player, violation, weight)
    else
        state.lastValid = position
    end
end
```

**No-spread par pré-compensation.** C'est la limite connue de toute dispersion prédite
exactement : le client connaît la graine, donc un cheat peut calculer le décalage δn du tir n
et viser `cible − δn`. Ni le cône déclaré ni la vitesse de visée ne le trahissent. Sa
signature est statistique : la variation de visée entre deux tirs contient −(δn − δn−1),
alors que celle d'un joueur légitime est **indépendante** de δ. `SpreadAudit` mesure cette
corrélation par fenêtres de 40 paires de tirs consécutifs (même arme, ≤ 0.6 s d'écart, cône
≥ 1°).

```lua
-- src/Shared/Combat/SpreadAudit.luau (l. 81–121)
--[[
    Observe un tir accepté. Renvoie la corrélation quand une fenêtre est complète, sinon nil.
]]
function SpreadAudit.observe(
    audit: Audit,
    weaponId: string,
    t: number,
    aim: Vector3,
    coneDegrees: number,
    offset: Vector2
): number?
    local previousAim, previousOffset = audit.lastAim, audit.lastOffset
    local chained = audit.weapon == weaponId and t > audit.lastT and t - audit.lastT <= SpreadAudit.MAX_GAP
    audit.weapon = weaponId
    audit.lastT = t
    if coneDegrees < SpreadAudit.MIN_CONE then
        audit.lastAim = nil
        audit.lastOffset = nil
        return nil
    end
    audit.lastAim = aim
    audit.lastOffset = offset
    if not (chained and previousAim and previousOffset) then
        return nil
    end
    local right, up = basis(previousAim)
    local change = aim - previousAim
    local e = Vector2.new(change:Dot(right), change:Dot(up))
    local delta = offset - previousOffset
    audit.dot += e:Dot(delta)
    audit.errorSq += e:Dot(e)
    audit.deltaSq += delta:Dot(delta)
    audit.count += 1
    if audit.count < SpreadAudit.WINDOW then
        return nil
    end
    local denominator = math.sqrt(audit.errorSq * audit.deltaSq)
    local correlation = if denominator > 1e-12 then audit.dot / denominator else 0
    audit.dot, audit.errorSq, audit.deltaSq, audit.count = 0, 0, 0, 0
    return correlation
end
```

```lua
-- src/Server/Services/CombatService.luau (l. 792–800)
local audit = audits[player]
if not audit then
    audit = SpreadAudit.new()
    audits[player] = audit
end
local correlation = SpreadAudit.observe(audit, def.id, packet.t, packet.a, cone, SpreadAudit.offset(cone, seed))
if correlation and correlation <= SpreadAudit.FLAG_CORRELATION then
    AntiCheatService.flag(player, "SpreadCompensation", 4)
end
```

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

```lua
-- src/Shared/Util/Spring.luau (l. 27–65)
function Spring.coefficients(omega: number, zeta: number, dt: number, out: Coefficients?): Coefficients
    local c = out or scratch
    if dt <= 0 or omega <= 0 then
        c.pp, c.pv, c.vp, c.vv = 1, 0, 0, 1
        return c
    end
    if zeta < 0.9999 then
        -- Sous-amorti
        local alpha = omega * math.sqrt(1 - zeta * zeta)
        local e = math.exp(-zeta * omega * dt)
        local cosA = math.cos(alpha * dt)
        local sinA = math.sin(alpha * dt)
        local zw = zeta * omega
        c.pp = e * (cosA + zw * sinA / alpha)
        c.pv = e * sinA / alpha
        c.vp = -e * sinA * omega * omega / alpha
        c.vv = e * (cosA - zw * sinA / alpha)
    elseif zeta <= 1.0001 then
        -- Critique
        local e = math.exp(-omega * dt)
        c.pp = e * (1 + omega * dt)
        c.pv = e * dt
        c.vp = -e * omega * omega * dt
        c.vv = e * (1 - omega * dt)
    else
        -- Sur-amorti
        local root = math.sqrt(zeta * zeta - 1)
        local r1 = -omega * (zeta - root)
        local r2 = -omega * (zeta + root)
        local e1 = math.exp(r1 * dt)
        local e2 = math.exp(r2 * dt)
        local inv = 1 / (r1 - r2)
        c.pp = (r1 * e2 - r2 * e1) * inv
        c.pv = (e1 - e2) * inv
        c.vp = r1 * r2 * (e2 - e1) * inv
        c.vv = (r1 * e1 - r2 * e2) * inv
    end
    return c
end
```

**Le juice ne ment jamais.** La caméra 1re personne compose la **visée** (lacet/tangage, ce
que suivent les balles via `getAim`) puis, par-dessus, des couches **purement visuelles** :
bob, punch, secousse (bruit de Perlin, intensité = trauma²), roulis. Aucune ne modifie la
direction des balles ; le recul *réel*, lui, passe par `addRecoil` et déplace la visée.

```lua
-- src/Client/Controllers/CameraController.luau (l. 232–262)
local function firstPerson(camera: Camera, dt: number, now: number)
    local body = bodyProvider()
    local root = body.root
    if not root then
        return
    end
    local base = CFrame.new(root.Position) * CFrame.Angles(0, yaw, 0)
    local eye = base * body.eye
    lastAimOrigin = eye
    local y = eye.Y
    local current = smoothY
    if current and body.grounded and math.abs(current - y) < 2.5 then
        y = MathUtil.damp(current, y, 22, dt)
    end
    smoothY = y
    local video = SettingsController.get().Video
    local punchAngles = punch:step(dt)
    local shake = shakeAngles(now)
    local roll = math.rad(body.bobRoll * video.HeadBob + body.tilt)
    local aim = CFrame.new(eye.X, y, eye.Z) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
    camera.CFrame = aim
        * CFrame.new(body.bobOffset * video.HeadBob)
        * CFrame.Angles(
            math.rad(punchAngles.X) + shake.X,
            math.rad(punchAngles.Y) + shake.Y,
            roll + math.rad(punchAngles.Z) + shake.Z
        )
    local baseFov = video.Fov
    fovSpring.target = baseFov / zoom + fovKick
    camera.FieldOfView = math.clamp(fovSpring:step(dt) + popSpring:step(dt), 20, 110)
end
```

**Récupération intelligente du recul** : après `recoveryDelay`, la visée revient vers son
point de départ, **sans rendre la part de dérive que le joueur a déjà compensée** à la souris
(pas de sur-correction vers le sol), et le pattern « redescend » pendant les pauses.

```lua
-- src/Client/Controllers/WeaponController.luau (l. 416–450)
local function recover(def: WeaponDef, dt: number, now: number)
    -- Compensation du joueur : elle "consomme" la dérive à récupérer.
    local yawInput, pitchInput = CameraController.lastInput()
    local pool = recoveryPool
    if pool.Magnitude > 1e-4 then
        local inputPitch = math.deg(pitchInput) -- négatif = vers le bas
        local inputYaw = -math.deg(yawInput) -- positif = vers la droite
        local y = pool.Y
        if y > 0 and inputPitch < 0 then
            y = math.max(0, y + inputPitch)
        end
        local x = pool.X
        if x > 0 and inputYaw < 0 then
            x = math.max(0, x + inputYaw)
        elseif x < 0 and inputYaw > 0 then
            x = math.min(0, x + inputYaw)
        end
        pool = Vector2.new(x, y)
    end
    local recoil = def.recoil
    local idle = now - lastShotClock
    if idle > recoil.recoveryDelay then
        local magnitude = pool.Magnitude
        if magnitude > 1e-4 then
            local step = math.min(magnitude, recoil.recoverySpeed * dt)
            local delta = pool.Unit * step
            CameraController.addRecoil(-delta.X, -delta.Y)
            pool -= delta
        end
        -- Le pattern "redescend" : un tir après une pause repart plus bas dans le motif.
        local shotsPerSecond = Weapons.currentRpm(def, 0) / 60
        sprayIndex = math.max(0, sprayIndex - dt * shotsPerSecond * 1.6)
    end
    recoveryPool = pool
end
```

**Kick du viewmodel** : impulsions de ressort calibrées pour que le pic corresponde aux
valeurs de configuration de chaque arme (recul arrière, montée, roulis), réduites en ADS et
accroupi.

```lua
-- src/Client/Controllers/ViewmodelController.luau (l. 416–444)
--[[ Retour visuel d'un tir : recul du modèle, flash, douille. ]]
function ViewmodelController.onShot(def: WeaponDef, crouched: boolean)
    local state = current
    if not state then
        return
    end
    local recoil = def.recoil
    local adsFactor = MathUtil.lerp(1, 0.5, adsAlpha)
    local stanceFactor = if crouched then 0.85 else 1
    local side = rng:NextNumber(-1, 1) * recoil.kickSide
    -- Impulsions calibrées pour que le pic du ressort ≈ la valeur de config
    -- (kickBack en unités design, kickUp/kickSide en degrés).
    kickPos:impulse(Vector3.new(side * 0.4, recoil.kickUp * 0.35 * adsFactor, recoil.kickBack * 45) * stanceFactor)
    kickRot:impulse(Vector3.new(recoil.kickUp * 38 * adsFactor, side * 26 * adsFactor, side * 40) * stanceFactor)

    local muzzle = state.built.attachments.Muzzle
    if muzzle and not scoped then
        local skin = state.built.skin
        local fx = skin and skin.fx
        local color = (fx and fx.muzzleColor) or Color3.fromRGB(255, 200, 120)
        local reduced = SettingsController.get().Video.ReducedFlashes
        local scale = flashScale(def) * (if reduced then 0.55 else 1)
        EffectsController.muzzleFlash(muzzle.WorldCFrame, color, scale, def.category ~= "Pistol")
    end
    local mode = def.fire.mode
    if mode ~= "Bolt" and mode ~= "Pump" and mode ~= "Melee" and def.ammo.reloadStyle ~= "Cylinder" then
        ejectShell(state)
    end
end
```

## 10.13 Démarrage déterministe

**Serveur.** `Net.setup()` crée tous les remotes, puis chaque service fait `Init()` (état
interne, injections, aucun yield) **dans l'ordre des dépendances**, puis `Start()` dans le même
ordre (connexions, boucles). Chaque étape est protégée : un service défaillant est journalisé
avec sa pile d'appel sans empêcher les autres de démarrer.

```lua
-- src/Server/Main.server.luau (l. 26–61)
local Services = script.Parent.Services

type Service = { Init: () -> (), Start: () -> () }

local ORDER: { { name: string, service: Service } } = {
    { name = "DataService", service = require(Services.DataService) :: any },
    { name = "ReplicaService", service = require(Services.ReplicaService) :: any },
    { name = "AntiCheatService", service = require(Services.AntiCheatService) :: any },
    { name = "ArenaService", service = require(Services.ArenaService) :: any },
    { name = "MapService", service = require(Services.MapService) :: any },
    { name = "LagCompensationService", service = require(Services.LagCompensationService) :: any },
    { name = "CharacterService", service = require(Services.CharacterService) :: any },
    { name = "PlayerService", service = require(Services.PlayerService) :: any },
    { name = "CombatService", service = require(Services.CombatService) :: any },
    { name = "InventoryService", service = require(Services.InventoryService) :: any },
    { name = "LeaderboardService", service = require(Services.LeaderboardService) :: any },
    { name = "ProgressionService", service = require(Services.ProgressionService) :: any },
    { name = "MissionService", service = require(Services.MissionService) :: any },
    { name = "StoreService", service = require(Services.StoreService) :: any },
    { name = "SettingsService", service = require(Services.SettingsService) :: any },
    { name = "PurchaseService", service = require(Services.PurchaseService) :: any },
    { name = "MatchService", service = require(Services.MatchService) :: any },
    { name = "PartyService", service = require(Services.PartyService) :: any },
    { name = "MatchmakingService", service = require(Services.MatchmakingService) :: any },
    { name = "CustomGameService", service = require(Services.CustomGameService) :: any },
    { name = "TrainingRangeService", service = require(Services.TrainingRangeService) :: any },
}

for _, entry in ORDER do
    Logger.safe(log, entry.name .. ".Init", entry.service.Init)
end
for _, entry in ORDER do
    Logger.safe(log, entry.name .. ".Start", entry.service.Start)
end

Workspace:SetAttribute("ServerReady", true)
```

**Client.** Démarrage dans l'ordre état → entrées → rendu → gameplay → interfaces ;
`ReplicaController` **en dernier**, pour que tous les écouteurs existent avant le premier état
envoyé par le serveur.

```lua
-- src/Client/Main.client.luau (l. 60–81)
-- 1. Démarrage ordonné
ClientState.start()
SettingsController.start()
InputController.start()
AudioController.start()
UI.setSoundPlayer(function(key: string)
    AudioController.play(key)
end)
LightingController.start()
EffectsController.start()
WeaponModelBuilder.start()
CameraController.start()
MovementController.start()
ViewmodelController.start()
WeaponController.start()
CharacterAnimator.start()
TransitionController.start()
HUDController.start()
MatchController.start()
LobbyController.start()
MobileController.start()
ReplicaController.start()
```

**Écran de chargement** (`ReplicatedFirst`) : remplace celui de Roblox dès la première frame —
ou reprend celui de la téléportation (`GetArrivingTeleportGui`) pour une transition sans
couture entre lobby et match — et ne s'efface que lorsque le client est **réellement prêt**
(contrôleurs démarrés + profil reçu, délai de sécurité 45 s).

```lua
-- src/ReplicatedFirst/Boot.client.luau (l. 20–43)
local arriving = TeleportService:GetArrivingTeleportGui()
local gui: ScreenGui = if arriving and arriving:IsA("ScreenGui") then arriving else LoadingScreen.create()
gui.Parent = playerGui
ReplicatedFirst:RemoveDefaultLoadingScreen()

local screen = LoadingScreen.animate(gui)
screen.setStatus("CHARGEMENT DU MONDE")
screen.setProgress(0.15)

if not game:IsLoaded() then
    game.Loaded:Wait()
end
screen.setStatus("SYNCHRONISATION AVEC LE SERVEUR")
screen.setProgress(0.55)

local deadline = os.clock() + 45
while player:GetAttribute("ClientBooted") ~= true and os.clock() < deadline do
    task.wait(0.1)
end
local profileStatus = player:GetAttribute("ClientBooted") == true
screen.setStatus(if profileStatus then "PRÊT" else "CONNEXION LENTE — POURSUITE DU CHARGEMENT")
screen.setProgress(1)
task.wait(0.4)
screen.finish()
```

## 10.14 Vérification

| Commande | Vérifie |
|---|---|
| `./scripts/analyze.sh` | analyse **stricte** de tout `src/` (luau-lsp, définitions Roblox, sourcemap Rojo) : 0 erreur |
| `./scripts/test.sh` | 91 tests unitaires hors moteur (Lune) |
| `./scripts/build.sh` | build Rojo de la place complète (`build/AetherStrike.rbxl`) |
| `stylua --check src tests` | formatage |
| `python3 tools/require_graph.py --check` | aucun cycle ni `require` non résolu (104 modules, 513 dépendances) |
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
