--!strict
--[[
	Types — contrat de types unique partagé client/serveur.

	Tous les modules (configs, réseau, réplication, services, contrôleurs) importent leurs
	types d'ici : un paquet réseau, une config d'arme ou un état de match n'a qu'UNE définition.
	Toute modification casse immédiatement l'analyse stricte partout où elle a un impact.
]]

---------------------------------------------------------------------------------------------
-- Primitives de gameplay
---------------------------------------------------------------------------------------------

export type HitZone = "Head" | "Body" | "Limb"
export type Stance = "Stand" | "Crouch" | "Slide"
export type TeamId = "A" | "B"
export type Side = "Attack" | "Defense"
export type ArenaKind = "Hub" | "Training" | "Match"
export type WeaponSlot = "Primary" | "Secondary" | "Melee"
export type WeaponCategory =
	"AssaultRifle"
	| "BurstRifle"
	| "SMG"
	| "LMG"
	| "Sniper"
	| "DMR"
	| "Shotgun"
	| "Pistol"
	| "Revolver"
	| "MachinePistol"
	| "Melee"
export type FireMode = "Auto" | "Semi" | "Burst" | "Bolt" | "Pump" | "Melee"
export type SightType = "Iron" | "RedDot" | "Holo" | "Scope2x" | "Scope4x" | "None"
export type ReloadStyle = "Magazine" | "Shell" | "Belt" | "Cylinder" | "None"
export type Rarity = "Common" | "Rare" | "Epic" | "Legendary" | "Mythic"
export type ColorRole = "Base" | "Secondary" | "Accent" | "Neon" | "Metal" | "Glass" | "Grip"
export type PieceShape = "Block" | "Cylinder" | "Wedge" | "Ball"

---------------------------------------------------------------------------------------------
-- Configuration des armes
---------------------------------------------------------------------------------------------

export type FalloffPoint = {
	range: number, -- distance (studs) à partir de laquelle `multiplier` s'applique pleinement
	multiplier: number,
}

export type DamageProfile = {
	base: number, -- dégâts "Body" à courte portée, par projectile
	headMultiplier: number,
	limbMultiplier: number,
	falloff: { FalloffPoint }, -- trié par portée croissante, interpolé linéairement
	pellets: number, -- 1 pour une balle, >1 pour les fusils à pompe
	penetration: number, -- "studs-équivalents" de matériau standard traversables
	range: number, -- longueur max du rayon
}

export type SpreadProfile = {
	-- Toutes les valeurs sont des demi-angles de cône, en degrés.
	hip: number,
	ads: number,
	firstShotMultiplier: number, -- multiplicateur de la base pour une 1re balle "fraîche"
	firstShotReset: number, -- secondes sans tirer pour retrouver la précision de 1re balle
	move: number, -- ajouté à pleine vitesse de course
	air: number, -- ajouté en l'air
	crouchMultiplier: number,
	bloomPerShot: number,
	bloomMax: number,
	bloomRecovery: number, -- degrés/seconde
	bloomRecoveryDelay: number,
	pelletCone: number, -- rayon du motif fixe des plombs (0 pour les balles)
}

export type RecoilProfile = {
	pattern: { Vector2 }, -- (yaw, pitch) en degrés par tir ; pitch > 0 = vers le haut
	loopFrom: number, -- index de reprise quand le pattern est épuisé
	randomYaw: number,
	randomPitch: number,
	adsMultiplier: number,
	crouchMultiplier: number,
	recoveryDelay: number,
	recoverySpeed: number, -- degrés/seconde de retour automatique
	recoveryRatio: number, -- part max de la dérive récupérée automatiquement (0..1)
	punch: number, -- coup de caméra visuel (degrés), purement cosmétique
	punchRoll: number,
	kickBack: number, -- recul du viewmodel (studs)
	kickUp: number, -- rotation du viewmodel (degrés)
	kickSide: number,
	shake: number, -- "trauma" ajouté à la caméra par tir (0..1)
}

export type SpinUp = {
	startRpm: number,
	endRpm: number,
	time: number,
}

export type FireProfile = {
	mode: FireMode,
	rpm: number,
	burstCount: number,
	burstRpm: number,
	burstCooldown: number,
	spinUp: SpinUp?,
}

export type HandlingProfile = {
	equipTime: number,
	adsTime: number,
	zoom: number, -- diviseur de FOV en visée complète
	sight: SightType,
	scopeOverlay: boolean, -- lunette plein écran (cache le viewmodel)
	moveMultiplier: number,
	adsMoveMultiplier: number,
	swayMultiplier: number,
}

export type AmmoProfile = {
	magazine: number,
	reserve: number,
	reloadStyle: ReloadStyle,
	reloadTime: number, -- rechargement tactique (chargeur non vide)
	emptyReloadTime: number,
	shellStartTime: number,
	shellInsertTime: number,
	shellEndTime: number,
	chamber: boolean, -- +1 dans la chambre lors d'un rechargement tactique
}

export type MeleeProfile = {
	lightDamage: number,
	heavyDamage: number,
	backstabDamage: number,
	range: number,
	coneDegrees: number,
	lightCooldown: number,
	heavyCooldown: number,
	heavyWindup: number,
}

export type TracerProfile = {
	color: Color3,
	width: number,
	speed: number, -- studs/s du segment visuel
	length: number,
	every: number, -- 1 = chaque balle a un traceur
	-- Arme suppressée : au-delà de cette distance, les AUTRES joueurs ne voient ni le
	-- traceur ni le flash de bouche (le tireur, lui, voit toujours ses traceurs).
	concealRange: number?,
}

export type WeaponAudio = {
	fire: string,
	tail: string,
	distant: string,
	mech: string,
	reloadOut: string,
	reloadIn: string,
	rack: string,
	equip: string,
	dry: string,
}

export type ModelPiece = {
	name: string,
	shape: PieceShape,
	size: Vector3, -- pour un cylindre : (longueur, diamètre, diamètre), axe le long de -Z
	offset: CFrame, -- relatif à la racine de l'arme (poignée)
	role: ColorRole,
	material: Enum.Material?,
	transparency: number?,
	animated: boolean?, -- relié par Motor6D pour l'animation procédurale (chargeur, culasse…)
}

export type ModelSpec = {
	pieces: { ModelPiece },
	muzzle: CFrame,
	ejection: CFrame,
	aimPoint: CFrame, -- centre du viseur : la caméra s'y aligne en ADS
	rightHand: CFrame,
	leftHand: CFrame,
	magPiece: string?,
	boltPiece: string?,
	worldScale: number, -- échelle du modèle tiers (dans la main des autres joueurs)
}

export type InspectStyle = "Rifle" | "Pistol" | "Blade" | "Heavy"

export type ViewmodelProfile = {
	hipOffset: CFrame,
	adsDistance: number,
	lowOffset: CFrame,
	inspect: InspectStyle,
	bobScale: number,
}

export type WeaponDef = {
	id: string,
	displayName: string,
	shortName: string,
	codename: string,
	category: WeaponCategory,
	slot: WeaponSlot,
	description: string,
	feel: string,
	fire: FireProfile,
	damage: DamageProfile,
	spread: SpreadProfile,
	recoil: RecoilProfile,
	handling: HandlingProfile,
	ammo: AmmoProfile,
	melee: MeleeProfile?,
	audio: WeaponAudio,
	model: ModelSpec,
	viewmodel: ViewmodelProfile,
	tracer: TracerProfile,
}

---------------------------------------------------------------------------------------------
-- Cosmétiques / inventaire
---------------------------------------------------------------------------------------------

export type Palette = {
	Base: Color3,
	Secondary: Color3,
	Accent: Color3,
	Neon: Color3,
	Metal: Color3,
	Glass: Color3,
	Grip: Color3,
}

export type MaterialSet = {
	Base: Enum.Material,
	Secondary: Enum.Material,
	Accent: Enum.Material,
}

export type SkinFx = {
	neonPulse: number?, -- vitesse de pulsation des parties néon (Hz)
	gradientShift: boolean?, -- teinte néon animée (arc cyan/magenta)
	aura: boolean?, -- particules permanentes sur le receiver
	tracerColor: Color3?,
	muzzleColor: Color3?,
	killEffect: string?, -- effet de kill intégré (Mythic)
	inspectFlourish: boolean?, -- animation d'inspection exclusive
}

export type ItemKind = "WeaponSkin" | "Operator" | "KillEffect" | "Emote" | "Banner" | "Title"

export type ItemDef = {
	id: string,
	kind: ItemKind,
	displayName: string,
	rarity: Rarity,
	price: number?, -- prix en Flux (nil = non achetable : pass, événement, niveau)
	weaponId: string?, -- pour les skins d'arme
	line: string?, -- collection
	palette: Palette?,
	materials: MaterialSet?,
	fx: SkinFx?,
	description: string,
}

---------------------------------------------------------------------------------------------
-- Réseau : paquets client <-> serveur
---------------------------------------------------------------------------------------------

export type FirePacket = {
	w: string, -- id d'arme
	n: number, -- compteur de tir (sert de graine au spread déterministe)
	o: Vector3, -- origine (oeil)
	a: Vector3, -- direction de visée (unitaire)
	s: number, -- spread (degrés) appliqué par le client
	t: number, -- horloge serveur synchronisée au moment du tir
	ads: boolean,
}

export type MeleePacket = {
	heavy: boolean,
	a: Vector3,
	t: number,
}

export type HitReport = {
	victim: number, -- UserId (>0) ou id de bot (<0)
	zone: HitZone,
	damage: number,
	killed: boolean,
	wallbang: boolean,
	armorBroken: boolean,
	position: Vector3,
}

export type ShotResult = {
	n: number,
	w: string,
	hits: { HitReport },
}

export type DamageTaken = {
	from: Vector3,
	damage: number,
	zone: HitZone,
	health: number,
	armor: number,
	attacker: number,
}

export type KillEvent = {
	killer: number,
	killerName: string,
	victim: number,
	victimName: string,
	weapon: string,
	headshot: boolean,
	wallbang: boolean,
	noscope: boolean,
	firstBlood: boolean,
	killerTeam: string,
	victimTeam: string,
	assists: { number },
	killEffect: string,
	streak: number,
}

export type SlotAmmo = {
	w: string,
	mag: number,
	reserve: number,
}

export type AmmoSyncPacket = {
	slots: { [string]: SlotAmmo }, -- "Primary" | "Secondary" | "Melee"
	equipped: string,
	seed: number,
	counter: number,
	reloading: boolean,
}

export type ShotVisualPacket = {
	s: number, -- NetSlot du tireur
	w: string,
	o: Vector3,
	e: { Vector3 },
}

export type KillcamSample = {
	t: number,
	cf: CFrame,
	stance: Stance,
	yaw: number,
	pitch: number,
}

export type KillcamPacket = {
	killer: number,
	killerName: string,
	weapon: string,
	killerTrack: { KillcamSample },
	victimTrack: { KillcamSample },
	killTime: number,
	headshot: boolean,
	killerHealth: number,
	killerArmor: number,
}

export type MatchEventPacket = {
	kind: string,
	team: string?,
	round: number?,
	reason: string?,
	player: number?,
	text: string?,
	value: number?,
}

export type InteractAction = "PlantStart" | "PlantCancel" | "DefuseStart" | "DefuseCancel"

export type StancePacket = {
	stance: Stance,
	lean: number, -- -1, 0, 1
	ads: boolean,
	walking: boolean,
}

---------------------------------------------------------------------------------------------
-- Match (état répliqué)
---------------------------------------------------------------------------------------------

export type MatchPhase =
	"Waiting"
	| "Intro"
	| "Prep"
	| "Live"
	| "Planted"
	| "RoundEnd"
	| "SideSwap"
	| "MatchEnd"
	| "Closed"

export type ObjectiveData = {
	carrier: number, -- UserId du porteur (0 = personne)
	dropped: boolean,
	position: Vector3?,
	planted: boolean,
	site: string,
	fuseEndsAt: number,
	defuser: number, -- 0 = personne
	defuseEndsAt: number,
	halfDefused: boolean,
	planter: number,
	plantEndsAt: number,
}

export type MatchPlayerData = {
	userId: number,
	name: string,
	team: TeamId,
	alive: boolean,
	connected: boolean,
	kills: number,
	deaths: number,
	assists: number,
	damage: number,
	score: number,
	headshots: number,
	plants: number,
	defuses: number,
	firstBloods: number,
	clutches: number,
	aces: number,
	rankIndex: number,
	level: number,
	loadout: { [string]: string },
}

export type RoundRecord = {
	winner: string, -- "A" | "B" | "" (manche nulle)
	reason: string,
}

export type MatchStateData = {
	id: string,
	mode: string,
	map: string,
	ranked: boolean,
	custom: boolean,
	phase: MatchPhase,
	phaseEndsAt: number,
	round: number,
	scores: { A: number, B: number },
	sides: { A: Side, B: Side },
	overtime: boolean,
	players: { [string]: MatchPlayerData },
	objective: ObjectiveData,
	history: { RoundRecord },
	lastRoundWinner: string,
	lastRoundReason: string,
	winner: string,
	mvp: number,
}

export type PostMatchSummary = {
	matchId: string,
	mode: string,
	map: string,
	ranked: boolean,
	result: "Victory" | "Defeat" | "Draw",
	scoreFor: number,
	scoreAgainst: number,
	kills: number,
	deaths: number,
	assists: number,
	damage: number,
	headshots: number,
	score: number,
	rounds: number,
	mvp: boolean,
	xpGained: number,
	xpBreakdown: { { label: string, amount: number } },
	levelBefore: number,
	levelAfter: number,
	rrBefore: number,
	rrAfter: number,
	rankBefore: number,
	rankAfter: number,
	rrDelta: number,
	timestamp: number,
	seen: boolean,
}

---------------------------------------------------------------------------------------------
-- Lobby : party / file d'attente / matchmaking
---------------------------------------------------------------------------------------------

export type QueueState = "Idle" | "Searching" | "Found" | "Launching"

export type QueueStatus = {
	state: QueueState,
	key: string,
	mode: string,
	ranked: boolean,
	since: number,
	estimate: number,
	inQueue: number,
	searchWidth: number,
}

export type PartyData = {
	id: string,
	leader: number,
	members: { number },
	names: { [string]: string },
	ranks: { [string]: number },
	locked: boolean,
	mode: string,
	ranked: boolean,
	queue: QueueStatus,
	invites: { [string]: number }, -- UserId (string) -> expiration (os.time)
}

export type MatchTicket = {
	id: string,
	players: { number },
	mmr: number,
	minRank: number,
	maxRank: number,
	enqueuedAt: number,
	mode: string,
	ranked: boolean,
	serverId: string,
}

export type MatchProposal = {
	teamA: { MatchTicket },
	teamB: { MatchTicket },
	mmrA: number,
	mmrB: number,
	quality: number,
}

export type MatchSpec = {
	matchId: string,
	mode: string,
	map: string,
	ranked: boolean,
	custom: boolean,
	teams: { A: { number }, B: { number } },
	createdAt: number,
}

---------------------------------------------------------------------------------------------
-- Profil persistant
---------------------------------------------------------------------------------------------

export type ControlSettings = {
	Sensitivity: number,
	AdsMultiplier: number,
	ScopeMultiplier: number,
	InvertY: boolean,
	ToggleAds: boolean,
	ToggleCrouch: boolean,
	ToggleWalk: boolean,
	LeanEnabled: boolean,
	AutoReload: boolean,
}

export type CrosshairSettings = {
	Style: string, -- "Classic" | "Dot" | "Circle" | "TShape"
	Color: string, -- "#RRGGBB"
	Opacity: number,
	Thickness: number,
	Length: number,
	Gap: number,
	Outline: boolean,
	OutlineThickness: number,
	OutlineOpacity: number,
	Dot: boolean,
	DotSize: number,
	Dynamic: boolean,
}

export type VideoSettings = {
	Fov: number,
	Bloom: boolean,
	DepthOfField: boolean,
	SunRays: boolean,
	CameraShake: number,
	HeadBob: number,
	ViewmodelBob: number,
	ShowFps: boolean,
	ReducedFlashes: boolean,
	Weather: boolean,
}

export type AudioSettings = {
	Master: number,
	Music: number,
	Sfx: number,
	Ui: number,
	HitSound: boolean,
	KillSound: boolean,
}

export type HudSettings = {
	Scale: number,
	DamageNumbers: boolean,
	Hitmarkers: boolean,
	Compass: boolean,
	NetStats: boolean,
	EnemyColor: string, -- "Red" | "Yellow" | "Purple"
	Killcam: boolean,
}

export type SettingsData = {
	Controls: ControlSettings,
	Crosshair: CrosshairSettings,
	Video: VideoSettings,
	Audio: AudioSettings,
	Hud: HudSettings,
	Keybinds: { [string]: string },
}

export type MissionProgress = {
	id: string,
	progress: number,
	target: number,
	claimed: boolean,
}

export type ProfileData = {
	Version: number,
	Level: number,
	XP: number,
	Currency: { Flux: number, Crystals: number },
	Rank: {
		MMR: number,
		Uncertainty: number,
		RankIndex: number,
		RR: number,
		Placements: number,
		Wins: number,
		Losses: number,
		Peak: number,
		Season: number,
		Matches: number,
	},
	Stats: {
		Kills: number,
		Deaths: number,
		Assists: number,
		Headshots: number,
		Matches: number,
		Wins: number,
		Damage: number,
		ShotsFired: number,
		ShotsHit: number,
		Plants: number,
		Defuses: number,
		Aces: number,
		Clutches: number,
		PlayTime: number,
	},
	Loadout: { Primary: string, Secondary: string, Melee: string },
	Cosmetics: {
		WeaponSkins: { [string]: string },
		Operator: string,
		KillEffect: string,
		Emotes: { string },
		Banner: string,
		Title: string,
	},
	Inventory: { [string]: boolean },
	Pass: {
		Season: number,
		XP: number,
		Premium: boolean,
		Claimed: { [string]: boolean },
	},
	Missions: {
		Day: number,
		Daily: { MissionProgress },
		Rerolls: number,
		Week: number,
		Weekly: { MissionProgress },
	},
	Settings: SettingsData,
	Purchases: { [string]: number },
	LastMatch: PostMatchSummary?,
	Moderation: { Suspicion: number, Flags: { [string]: number } },
	Meta: { FirstJoin: number, LastJoin: number, Sessions: number },
}

---------------------------------------------------------------------------------------------
-- Cartes
---------------------------------------------------------------------------------------------

export type LightingProfile = {
	clockTime: number,
	brightness: number,
	ambient: Color3,
	outdoorAmbient: Color3,
	exposure: number,
	colorShiftTop: Color3,
	diffuseScale: number,
	specularScale: number,
	atmosphere: {
		density: number,
		offset: number,
		color: Color3,
		decay: Color3,
		glare: number,
		haze: number,
	},
	colorCorrection: {
		brightness: number,
		contrast: number,
		saturation: number,
		tint: Color3,
	},
	bloom: { intensity: number, size: number, threshold: number },
	sunRays: { intensity: number, spread: number },
	shadowSoftness: number,
	sky: { stars: number, sunSize: number, moonSize: number, celestial: boolean },
	clouds: { cover: number, density: number, color: Color3 }?, -- nil = aucun nuage
}

-- Météo et particules d'ambiance (côté client, désactivables dans les réglages vidéo).
export type WeatherKind = "None" | "Rain" | "Snow" | "Motes" | "Embers"

export type Weather = {
	kind: WeatherKind,
	intensity: number, -- 0..1
	lightning: boolean, -- éclairs lointains (désactivés par « flashs réduits »)
}

-- Son d'ambiance d'une carte : réverbération extérieure/intérieure et sons ponctuels.
export type AmbienceSpot = {
	key: string,
	interval: NumberRange, -- secondes entre deux occurrences
	distance: NumberRange, -- studs autour de l'auditeur
}

export type Ambience = {
	outdoorReverb: string, -- nom d'Enum.ReverbType
	indoorReverb: string,
	spots: { AmbienceSpot },
}

export type MapInfo = {
	id: string,
	displayName: string,
	tagline: string,
	theme: string,
	modes: { string },
	sites: { string },
	lighting: LightingProfile,
	size: Vector2,
	ambientSound: string,
	tips: { string },
	weather: Weather,
	ambience: Ambience,
}

return {}
