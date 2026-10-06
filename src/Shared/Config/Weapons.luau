--!strict
--[[
	Weapons — l'arsenal complet d'AETHER STRIKE (14 armes).

	Philosophie d'équilibrage (eHP = 100 PV + 50 bouclier = 150) :
	  * One-tap tête : VK-12 (toutes distances), AR-9 (< 20 studs), BR-3, DM-4, RS-1, R-44.
	  * TTK corps à courte portée visé autour de 0.30–0.45 s pour les automatiques :
	    le skill (placement tête, counter-strafe) doit primer sur la cadence.
	  * Chaque classe a un rôle et une contrepartie : mobilité vs précision vs puissance.
	  * Les manches "pistolet" (sans bouclier) rendent les secondaires létales.

	Toutes les valeurs angulaires sont en degrés, les distances en studs
	(1 stud ≈ 0.28 m ; une map compétitive fait 120–220 studs de côté).
]]

local Types = require(script.Parent.Parent.Types)
local WeaponModels = require(script.Parent.WeaponModels)
local RecoilPatterns = require(script.Parent.RecoilPatterns)

type WeaponDef = Types.WeaponDef

local rad = math.rad
local build = RecoilPatterns.build

---------------------------------------------------------------------------------------------
-- Gabarits partagés
---------------------------------------------------------------------------------------------

local function viewmodel(
	hip: CFrame,
	adsDistance: number,
	inspect: Types.InspectStyle,
	bobScale: number
): Types.ViewmodelProfile
	return {
		hipOffset = hip,
		adsDistance = adsDistance,
		lowOffset = CFrame.new(0.3, -0.85, -0.85) * CFrame.Angles(rad(-28), rad(38), rad(12)),
		inspect = inspect,
		bobScale = bobScale,
	}
end

local RIFLE_HIP = CFrame.new(0.62, -0.68, -1.2)
local PISTOL_HIP = CFrame.new(0.42, -0.5, -1.38)

local WARM_TRACER = Color3.fromRGB(255, 214, 150)

local function tracer(width: number, every: number, color: Color3?): Types.TracerProfile
	return { color = color or WARM_TRACER, width = width, speed = 950, length = 9, every = every }
end

local function audio(
	fire: string,
	tail: string,
	distant: string,
	mech: string,
	reloadOut: string,
	reloadIn: string,
	rack: string,
	equip: string
): Types.WeaponAudio
	return {
		fire = fire,
		tail = tail,
		distant = distant,
		mech = mech,
		reloadOut = reloadOut,
		reloadIn = reloadIn,
		rack = rack,
		equip = equip,
		dry = "Weapon.Dry",
	}
end

local function magazineAmmo(magazine: number, reserve: number, reload: number, emptyReload: number): Types.AmmoProfile
	return {
		magazine = magazine,
		reserve = reserve,
		reloadStyle = "Magazine",
		reloadTime = reload,
		emptyReloadTime = emptyReload,
		shellStartTime = 0,
		shellInsertTime = 0,
		shellEndTime = 0,
		chamber = true,
	}
end

local function auto(rpm: number): Types.FireProfile
	return { mode = "Auto", rpm = rpm, burstCount = 1, burstRpm = rpm, burstCooldown = 0, spinUp = nil }
end

local function semi(rpm: number, mode: Types.FireMode?): Types.FireProfile
	return { mode = mode or "Semi", rpm = rpm, burstCount = 1, burstRpm = rpm, burstCooldown = 0, spinUp = nil }
end

---------------------------------------------------------------------------------------------
-- Arsenal
---------------------------------------------------------------------------------------------

local Weapons = {}

Weapons.defs = {} :: { [string]: WeaponDef }
Weapons.order = {} :: { string }

local function register(def: WeaponDef)
	assert(Weapons.defs[def.id] == nil, "duplicate weapon id " .. def.id)
	Weapons.defs[def.id] = def
	table.insert(Weapons.order, def.id)
end

-- 1. VK-12 "Vektor" — fusil d'assaut lourd, one-tap tête à toute distance -----------------
register({
	id = "vk12",
	displayName = "VK-12 Vektor",
	shortName = "VK-12",
	codename = "VEKTOR",
	category = "AssaultRifle",
	slot = "Primary",
	description = "Fusil d'assaut 7.2mm. Un tir à la tête suffit, à n'importe quelle distance.",
	feel = "Lourd, punchy, chaque balle 'claque'. Montée verticale franche puis balayage en S.",
	fire = auto(600),
	damage = {
		base = 39,
		headMultiplier = 4.0,
		limbMultiplier = 0.75,
		falloff = { { range = 200, multiplier = 1 } },
		pellets = 1,
		penetration = 1.6,
		range = 900,
	},
	spread = {
		hip = 2.0,
		ads = 0.18,
		firstShotMultiplier = 0.25,
		firstShotReset = 0.38,
		move = 4.5,
		air = 8,
		crouchMultiplier = 0.8,
		bloomPerShot = 0.32,
		bloomMax = 2.6,
		bloomRecovery = 6.5,
		bloomRecoveryDelay = 0.12,
		pelletCone = 0,
	},
	recoil = {
		pattern = build({
			{ count = 3, pitch = 0.55, pitchEnd = 0.9, yaw = 0 },
			{ count = 7, pitch = 0.85, yaw = 0.06 },
			{ count = 6, pitch = 0.35, yaw = -0.55 },
			{ count = 6, pitch = 0.3, yaw = 0.65 },
			{ count = 3, pitch = 0.25, yaw = -0.4 },
		}),
		loopFrom = 11,
		randomYaw = 0.18,
		randomPitch = 0.1,
		adsMultiplier = 0.8,
		crouchMultiplier = 0.85,
		recoveryDelay = 0.1,
		recoverySpeed = 18,
		recoveryRatio = 0.75,
		punch = 0.9,
		punchRoll = 1.2,
		kickBack = 0.13,
		kickUp = 3.2,
		kickSide = 1.0,
		shake = 0.07,
	},
	handling = {
		equipTime = 0.75,
		adsTime = 0.24,
		zoom = 1.25,
		sight = "Holo",
		scopeOverlay = false,
		moveMultiplier = 0.92,
		adsMoveMultiplier = 0.6,
		swayMultiplier = 1.1,
	},
	ammo = magazineAmmo(25, 75, 2.3, 2.7),
	melee = nil,
	audio = audio(
		"Weapon.Rifle.Fire",
		"Weapon.Tail.Rifle",
		"Weapon.Distant.Rifle",
		"Weapon.Mech.Rifle",
		"Reload.MagOut",
		"Reload.MagIn",
		"Reload.Rack",
		"Equip.Rifle"
	),
	model = WeaponModels.longGun({
		receiver = Vector3.new(0.22, 0.3, 1.05),
		handguardLength = 0.75,
		handguardHeight = 0.24,
		barrelLength = 0.55,
		barrelDiameter = 0.08,
		muzzle = "Brake",
		mag = "Curved",
		magSize = Vector3.new(0.15, 0.5, 0.24),
		stock = "Full",
		sight = "Holo",
		foregrip = false,
		bolt = "Handle",
		accentRings = 3,
	}),
	viewmodel = viewmodel(RIFLE_HIP, 0.95, "Rifle", 1),
	tracer = tracer(0.07, 1),
})

-- 2. AR-9 "Halcyon" — fusil d'assaut précis, cadence élevée --------------------------------
register({
	id = "ar9",
	displayName = "AR-9 Halcyon",
	shortName = "AR-9",
	codename = "HALCYON",
	category = "AssaultRifle",
	slot = "Primary",
	description = "Fusil d'assaut 5.5mm suppressé. One-tap tête à courte portée, recul très maîtrisable.",
	feel = "Feutré et chirurgical : rafales contrôlées, pas de traceur visible pour l'ennemi au-delà de 60 studs.",
	fire = auto(690),
	damage = {
		base = 34,
		headMultiplier = 4.5,
		limbMultiplier = 0.75,
		falloff = {
			{ range = 20, multiplier = 1 },
			{ range = 60, multiplier = 0.91 },
			{ range = 120, multiplier = 0.82 },
		},
		pellets = 1,
		penetration = 1.4,
		range = 900,
	},
	spread = {
		hip = 1.8,
		ads = 0.15,
		firstShotMultiplier = 0.3,
		firstShotReset = 0.32,
		move = 4.0,
		air = 7.5,
		crouchMultiplier = 0.8,
		bloomPerShot = 0.24,
		bloomMax = 2.0,
		bloomRecovery = 7,
		bloomRecoveryDelay = 0.1,
		pelletCone = 0,
	},
	recoil = {
		pattern = build({
			{ count = 3, pitch = 0.45, pitchEnd = 0.7, yaw = 0 },
			{ count = 9, pitch = 0.65, yaw = 0.08 },
			{ count = 8, pitch = 0.25, yaw = 0.4 },
			{ count = 10, pitch = 0.2, yaw = -0.45 },
		}),
		loopFrom = 13,
		randomYaw = 0.14,
		randomPitch = 0.08,
		adsMultiplier = 0.8,
		crouchMultiplier = 0.85,
		recoveryDelay = 0.09,
		recoverySpeed = 20,
		recoveryRatio = 0.8,
		punch = 0.6,
		punchRoll = 0.8,
		kickBack = 0.09,
		kickUp = 2.2,
		kickSide = 0.7,
		shake = 0.045,
	},
	handling = {
		equipTime = 0.72,
		adsTime = 0.22,
		zoom = 1.3,
		sight = "RedDot",
		scopeOverlay = false,
		moveMultiplier = 0.93,
		adsMoveMultiplier = 0.62,
		swayMultiplier = 1.0,
	},
	ammo = magazineAmmo(30, 90, 2.2, 2.6),
	melee = nil,
	audio = audio(
		"Weapon.Rifle.Suppressed",
		"Weapon.Tail.Light",
		"Weapon.Distant.Light",
		"Weapon.Mech.Rifle",
		"Reload.MagOut",
		"Reload.MagIn",
		"Reload.Rack",
		"Equip.Rifle"
	),
	model = WeaponModels.longGun({
		receiver = Vector3.new(0.21, 0.28, 0.95),
		handguardLength = 0.8,
		handguardHeight = 0.22,
		barrelLength = 0.3,
		barrelDiameter = 0.075,
		muzzle = "Suppressor",
		mag = "Straight",
		magSize = Vector3.new(0.14, 0.46, 0.22),
		stock = "Skeleton",
		sight = "RedDot",
		foregrip = true,
		bolt = "Handle",
		accentRings = 4,
	}),
	viewmodel = viewmodel(RIFLE_HIP, 0.95, "Rifle", 1),
	tracer = tracer(0.05, 2, Color3.fromRGB(190, 240, 255)),
})

-- 3. BR-3 "Tribune" — fusil à rafales de 3 ---------------------------------------------------
register({
	id = "br3",
	displayName = "BR-3 Tribune",
	shortName = "BR-3",
	codename = "TRIBUNE",
	category = "BurstRifle",
	slot = "Primary",
	description = "Rafales de 3 coups ultra-rapides. Une rafale bien placée = un kill.",
	feel = "Rythmé, 'tac-tac-tac' sec. Récompense le timing et les peeks courts.",
	fire = { mode = "Burst", rpm = 1050, burstCount = 3, burstRpm = 1050, burstCooldown = 0.28, spinUp = nil },
	damage = {
		base = 36,
		headMultiplier = 4.2,
		limbMultiplier = 0.75,
		falloff = { { range = 80, multiplier = 1 }, { range = 160, multiplier = 0.88 } },
		pellets = 1,
		penetration = 1.4,
		range = 900,
	},
	spread = {
		hip = 2.2,
		ads = 0.1,
		firstShotMultiplier = 0.25,
		firstShotReset = 0.3,
		move = 4.2,
		air = 8,
		crouchMultiplier = 0.8,
		bloomPerShot = 0.3,
		bloomMax = 1.8,
		bloomRecovery = 8,
		bloomRecoveryDelay = 0.08,
		pelletCone = 0,
	},
	recoil = {
		pattern = build({
			{ count = 3, pitch = 0.9, pitchEnd = 1.15, yaw = 0.1, yawEnd = -0.12 },
			{ count = 3, pitch = 1.0, pitchEnd = 1.2, yaw = -0.15, yawEnd = 0.18 },
			{ count = 3, pitch = 0.8, yaw = 0.2, yawEnd = -0.2 },
		}),
		loopFrom = 4,
		randomYaw = 0.12,
		randomPitch = 0.08,
		adsMultiplier = 0.75,
		crouchMultiplier = 0.85,
		recoveryDelay = 0.05,
		recoverySpeed = 26,
		recoveryRatio = 0.9,
		punch = 0.8,
		punchRoll = 1.0,
		kickBack = 0.11,
		kickUp = 2.8,
		kickSide = 0.6,
		shake = 0.06,
	},
	handling = {
		equipTime = 0.75,
		adsTime = 0.25,
		zoom = 1.6,
		sight = "Scope2x",
		scopeOverlay = false,
		moveMultiplier = 0.93,
		adsMoveMultiplier = 0.6,
		swayMultiplier = 1.05,
	},
	ammo = magazineAmmo(24, 72, 2.4, 2.8),
	melee = nil,
	audio = audio(
		"Weapon.Rifle.Burst",
		"Weapon.Tail.Rifle",
		"Weapon.Distant.Rifle",
		"Weapon.Mech.Rifle",
		"Reload.MagOut",
		"Reload.MagIn",
		"Reload.Rack",
		"Equip.Rifle"
	),
	model = WeaponModels.longGun({
		receiver = Vector3.new(0.23, 0.32, 1.0),
		handguardLength = 0.7,
		handguardHeight = 0.26,
		barrelLength = 0.45,
		barrelDiameter = 0.08,
		muzzle = "Flash",
		mag = "Straight",
		magSize = Vector3.new(0.15, 0.42, 0.24),
		stock = "Full",
		sight = "Scope2x",
		foregrip = false,
		bolt = "Handle",
		accentRings = 2,
	}),
	viewmodel = viewmodel(RIFLE_HIP, 0.92, "Rifle", 1),
	tracer = tracer(0.06, 1),
})

-- 4. SX-5 "Wasp" — SMG agressif, cadence extrême -------------------------------------------
register({
	id = "sx5",
	displayName = "SX-5 Wasp",
	shortName = "SX-5",
	codename = "WASP",
	category = "SMG",
	slot = "Primary",
	description = "Pistolet-mitrailleur 900 cpm. Le roi du close-range et du run-and-gun.",
	feel = "Bourdonnement nerveux, recul faible mais 'vibrant'. Se manie comme un pistolet.",
	fire = auto(900),
	damage = {
		base = 24,
		headMultiplier = 2.5,
		limbMultiplier = 0.8,
		falloff = {
			{ range = 18, multiplier = 1 },
			{ range = 45, multiplier = 0.83 },
			{ range = 90, multiplier = 0.67 },
		},
		pellets = 1,
		penetration = 0.8,
		range = 500,
	},
	spread = {
		hip = 1.5,
		ads = 0.45,
		firstShotMultiplier = 0.6,
		firstShotReset = 0.25,
		move = 1.6,
		air = 4.5,
		crouchMultiplier = 0.85,
		bloomPerShot = 0.2,
		bloomMax = 2.2,
		bloomRecovery = 9,
		bloomRecoveryDelay = 0.08,
		pelletCone = 0,
	},
	recoil = {
		pattern = build({
			{ count = 5, pitch = 0.35, yaw = 0 },
			{ count = 10, pitch = 0.4, yaw = 0.12, yawEnd = -0.12 },
			{ count = 15, pitch = 0.22, yaw = -0.2, yawEnd = 0.25 },
		}),
		loopFrom = 6,
		randomYaw = 0.35,
		randomPitch = 0.12,
		adsMultiplier = 0.85,
		crouchMultiplier = 0.9,
		recoveryDelay = 0.08,
		recoverySpeed = 22,
		recoveryRatio = 0.8,
		punch = 0.45,
		punchRoll = 0.9,
		kickBack = 0.07,
		kickUp = 1.6,
		kickSide = 1.2,
		shake = 0.035,
	},
	handling = {
		equipTime = 0.55,
		adsTime = 0.17,
		zoom = 1.15,
		sight = "RedDot",
		scopeOverlay = false,
		moveMultiplier = 0.98,
		adsMoveMultiplier = 0.72,
		swayMultiplier = 0.8,
	},
	ammo = magazineAmmo(30, 120, 2.0, 2.4),
	melee = nil,
	audio = audio(
		"Weapon.SMG.Fire",
		"Weapon.Tail.Light",
		"Weapon.Distant.Light",
		"Weapon.Mech.Light",
		"Reload.MagOut",
		"Reload.MagIn",
		"Reload.Rack",
		"Equip.Light"
	),
	model = WeaponModels.longGun({
		receiver = Vector3.new(0.2, 0.3, 0.75),
		handguardLength = 0.35,
		handguardHeight = 0.22,
		barrelLength = 0.22,
		barrelDiameter = 0.07,
		muzzle = "Flash",
		mag = "Straight",
		magSize = Vector3.new(0.12, 0.5, 0.18),
		stock = "Skeleton",
		sight = "RedDot",
		foregrip = true,
		bolt = "Handle",
		accentRings = 2,
	}),
	viewmodel = viewmodel(CFrame.new(0.58, -0.64, -1.22), 0.95, "Rifle", 0.9),
	tracer = tracer(0.045, 2),
})

-- 5. KR-7 "Kestrel" — SMG polyvalent, gros chargeur ---------------------------------------
register({
	id = "kr7",
	displayName = "KR-7 Kestrel",
	shortName = "KR-7",
	codename = "KESTREL",
	category = "SMG",
	slot = "Primary",
	description = "SMG stable à chargeur tambour de 40. Tient la mi-distance mieux que tout autre SMG.",
	feel = "Rond, régulier, recul en dérive douce vers la droite : facile à apprendre, dur à maîtriser.",
	fire = auto(750),
	damage = {
		base = 27,
		headMultiplier = 2.8,
		limbMultiplier = 0.8,
		falloff = {
			{ range = 25, multiplier = 1 },
			{ range = 55, multiplier = 0.89 },
			{ range = 100, multiplier = 0.74 },
		},
		pellets = 1,
		penetration = 0.9,
		range = 550,
	},
	spread = {
		hip = 1.6,
		ads = 0.35,
		firstShotMultiplier = 0.5,
		firstShotReset = 0.28,
		move = 1.9,
		air = 5,
		crouchMultiplier = 0.85,
		bloomPerShot = 0.18,
		bloomMax = 1.9,
		bloomRecovery = 8.5,
		bloomRecoveryDelay = 0.09,
		pelletCone = 0,
	},
	recoil = {
		pattern = build({
			{ count = 4, pitch = 0.4, yaw = 0 },
			{ count = 10, pitch = 0.45, yaw = 0.15 },
			{ count = 26, pitch = 0.2, yaw = -0.3, yawEnd = 0.3 },
		}),
		loopFrom = 15,
		randomYaw = 0.22,
		randomPitch = 0.1,
		adsMultiplier = 0.82,
		crouchMultiplier = 0.88,
		recoveryDelay = 0.09,
		recoverySpeed = 20,
		recoveryRatio = 0.8,
		punch = 0.5,
		punchRoll = 0.8,
		kickBack = 0.08,
		kickUp = 1.8,
		kickSide = 0.8,
		shake = 0.04,
	},
	handling = {
		equipTime = 0.58,
		adsTime = 0.18,
		zoom = 1.15,
		sight = "Holo",
		scopeOverlay = false,
		moveMultiplier = 0.97,
		adsMoveMultiplier = 0.7,
		swayMultiplier = 0.85,
	},
	ammo = magazineAmmo(40, 120, 2.1, 2.5),
	melee = nil,
	audio = audio(
		"Weapon.SMG.Fire",
		"Weapon.Tail.Light",
		"Weapon.Distant.Light",
		"Weapon.Mech.Light",
		"Reload.MagOut",
		"Reload.MagIn",
		"Reload.Rack",
		"Equip.Light"
	),
	model = WeaponModels.longGun({
		receiver = Vector3.new(0.22, 0.32, 0.8),
		handguardLength = 0.42,
		handguardHeight = 0.24,
		barrelLength = 0.26,
		barrelDiameter = 0.075,
		muzzle = "Brake",
		mag = "Drum",
		magSize = Vector3.new(0.18, 0.42, 0.42),
		stock = "Full",
		sight = "Holo",
		foregrip = false,
		bolt = "Handle",
		accentRings = 2,
	}),
	viewmodel = viewmodel(CFrame.new(0.6, -0.65, -1.2), 0.95, "Rifle", 0.9),
	tracer = tracer(0.05, 2),
})

-- 6. HMG-40 "Bastion" — mitrailleuse légère à montée en cadence ----------------------------
register({
	id = "hmg40",
	displayName = "HMG-40 Bastion",
	shortName = "HMG-40",
	codename = "BASTION",
	category = "LMG",
	slot = "Primary",
	description = "Mitrailleuse 100 coups. La cadence monte de 560 à 800 cpm en 1.2 s de tir continu.",
	feel = "Massif. Démarre lent et lourd, puis devient un mur de plomb. Idéale pour tenir un angle.",
	fire = {
		mode = "Auto",
		rpm = 560,
		burstCount = 1,
		burstRpm = 560,
		burstCooldown = 0,
		spinUp = { startRpm = 560, endRpm = 800, time = 1.2 },
	},
	damage = {
		base = 30,
		headMultiplier = 3.2,
		limbMultiplier = 0.8,
		falloff = { { range = 60, multiplier = 1 }, { range = 140, multiplier = 0.92 } },
		pellets = 1,
		penetration = 2.4,
		range = 900,
	},
	spread = {
		hip = 2.6,
		ads = 0.4,
		firstShotMultiplier = 0.6,
		firstShotReset = 0.4,
		move = 5.5,
		air = 10,
		crouchMultiplier = 0.7,
		bloomPerShot = 0.12,
		bloomMax = 2.4,
		bloomRecovery = 4.5,
		bloomRecoveryDelay = 0.18,
		pelletCone = 0,
	},
	recoil = {
		pattern = build({
			{ count = 8, pitch = 0.7, yaw = 0.05 },
			{ count = 12, pitch = 0.5, yaw = -0.1 },
			{ count = 80, pitch = 0.18, yaw = -0.35, yawEnd = 0.35 },
		}),
		loopFrom = 21,
		randomYaw = 0.25,
		randomPitch = 0.1,
		adsMultiplier = 0.75,
		crouchMultiplier = 0.7,
		recoveryDelay = 0.15,
		recoverySpeed = 14,
		recoveryRatio = 0.7,
		punch = 1.0,
		punchRoll = 1.4,
		kickBack = 0.14,
		kickUp = 2.6,
		kickSide = 1.2,
		shake = 0.08,
	},
	handling = {
		equipTime = 1.15,
		adsTime = 0.36,
		zoom = 1.2,
		sight = "Holo",
		scopeOverlay = false,
		moveMultiplier = 0.84,
		adsMoveMultiplier = 0.5,
		swayMultiplier = 1.5,
	},
	ammo = {
		magazine = 100,
		reserve = 200,
		reloadStyle = "Belt",
		reloadTime = 4.8,
		emptyReloadTime = 5.2,
		shellStartTime = 0,
		shellInsertTime = 0,
		shellEndTime = 0,
		chamber = false,
	},
	melee = nil,
	audio = audio(
		"Weapon.LMG.Fire",
		"Weapon.Tail.Heavy",
		"Weapon.Distant.Heavy",
		"Weapon.Mech.Heavy",
		"Reload.BoxOut",
		"Reload.BoxIn",
		"Reload.Rack",
		"Equip.Heavy"
	),
	model = WeaponModels.longGun({
		receiver = Vector3.new(0.28, 0.36, 1.2),
		handguardLength = 0.9,
		handguardHeight = 0.28,
		barrelLength = 0.6,
		barrelDiameter = 0.1,
		muzzle = "Brake",
		mag = "Box",
		magSize = Vector3.new(0.3, 0.3, 0.4),
		stock = "Full",
		sight = "Holo",
		foregrip = true,
		bolt = "Handle",
		accentRings = 4,
		bipod = true,
	}),
	viewmodel = viewmodel(CFrame.new(0.66, -0.74, -1.12), 1.0, "Heavy", 1.25),
	tracer = tracer(0.07, 1, Color3.fromRGB(255, 180, 120)),
})

-- 7. RS-1 "Longbow" — sniper à verrou -------------------------------------------------------
register({
	id = "rs1",
	displayName = "RS-1 Longbow",
	shortName = "RS-1",
	codename = "LONGBOW",
	category = "Sniper",
	slot = "Primary",
	description = "Fusil de précision à verrou. 150 au corps : un tir, un kill (sauf jambes).",
	feel = "Silence, respiration, puis le tonnerre. Le verrou qui claque après chaque tir est une promesse.",
	fire = semi(40, "Bolt"),
	damage = {
		base = 150,
		headMultiplier = 2.0,
		limbMultiplier = 0.85,
		falloff = { { range = 1000, multiplier = 1 } },
		pellets = 1,
		penetration = 3.0,
		range = 1500,
	},
	spread = {
		hip = 7.5,
		ads = 0.0,
		firstShotMultiplier = 1,
		firstShotReset = 1.2,
		move = 12,
		air = 15,
		crouchMultiplier = 0.85,
		bloomPerShot = 0,
		bloomMax = 0,
		bloomRecovery = 10,
		bloomRecoveryDelay = 0,
		pelletCone = 0,
	},
	recoil = {
		pattern = { Vector2.new(0, 3.8) },
		loopFrom = 1,
		randomYaw = 0.6,
		randomPitch = 0.4,
		adsMultiplier = 1,
		crouchMultiplier = 0.9,
		recoveryDelay = 0.12,
		recoverySpeed = 14,
		recoveryRatio = 1,
		punch = 3.2,
		punchRoll = 3,
		kickBack = 0.32,
		kickUp = 8,
		kickSide = 2,
		shake = 0.22,
	},
	handling = {
		equipTime = 1.0,
		adsTime = 0.36,
		zoom = 3.5,
		sight = "Scope4x",
		scopeOverlay = true,
		moveMultiplier = 0.86,
		adsMoveMultiplier = 0.4,
		swayMultiplier = 1.4,
	},
	ammo = magazineAmmo(5, 20, 3.0, 3.6),
	melee = nil,
	audio = audio(
		"Weapon.Sniper.Fire",
		"Weapon.Tail.Heavy",
		"Weapon.Distant.Sniper",
		"Weapon.Mech.Heavy",
		"Reload.MagOut",
		"Reload.MagIn",
		"Reload.Bolt",
		"Equip.Heavy"
	),
	model = WeaponModels.longGun({
		receiver = Vector3.new(0.22, 0.3, 1.1),
		handguardLength = 0.85,
		handguardHeight = 0.22,
		barrelLength = 0.95,
		barrelDiameter = 0.085,
		muzzle = "Brake",
		mag = "Straight",
		magSize = Vector3.new(0.13, 0.26, 0.3),
		stock = "Thumbhole",
		sight = "Scope4x",
		foregrip = false,
		bolt = "Lever",
		accentRings = 3,
		bipod = true,
	}),
	viewmodel = viewmodel(CFrame.new(0.62, -0.66, -1.12), 0.8, "Heavy", 1.15),
	tracer = tracer(0.09, 1, Color3.fromRGB(200, 235, 255)),
})

-- 8. DM-4 "Marshal" — DMR semi-auto ---------------------------------------------------------
register({
	id = "dm4",
	displayName = "DM-4 Marshal",
	shortName = "DM-4",
	codename = "MARSHAL",
	category = "DMR",
	slot = "Primary",
	description = "Fusil de tireur d'élite semi-automatique. 2 balles au corps, 1 à la tête.",
	feel = "Chaque pression de détente est une décision. Recul vertical net qui revient presque seul.",
	fire = semi(200),
	damage = {
		base = 76,
		headMultiplier = 2.3,
		limbMultiplier = 0.8,
		falloff = { { range = 500, multiplier = 1 } },
		pellets = 1,
		penetration = 2.0,
		range = 1200,
	},
	spread = {
		hip = 4.0,
		ads = 0.08,
		firstShotMultiplier = 1,
		firstShotReset = 0.45,
		move = 6,
		air = 10,
		crouchMultiplier = 0.85,
		bloomPerShot = 0.55,
		bloomMax = 2.5,
		bloomRecovery = 5,
		bloomRecoveryDelay = 0.2,
		pelletCone = 0,
	},
	recoil = {
		pattern = build({
			{ count = 1, pitch = 1.6, yaw = 0.2 },
			{ count = 4, pitch = 1.75, yaw = -0.25, yawEnd = 0.3 },
		}),
		loopFrom = 2,
		randomYaw = 0.3,
		randomPitch = 0.15,
		adsMultiplier = 0.85,
		crouchMultiplier = 0.85,
		recoveryDelay = 0.08,
		recoverySpeed = 16,
		recoveryRatio = 0.9,
		punch = 1.6,
		punchRoll = 1.6,
		kickBack = 0.18,
		kickUp = 4.2,
		kickSide = 1.0,
		shake = 0.11,
	},
	handling = {
		equipTime = 0.85,
		adsTime = 0.28,
		zoom = 2.0,
		sight = "Scope2x",
		scopeOverlay = false,
		moveMultiplier = 0.9,
		adsMoveMultiplier = 0.55,
		swayMultiplier = 1.2,
	},
	ammo = magazineAmmo(10, 40, 2.6, 3.0),
	melee = nil,
	audio = audio(
		"Weapon.DMR.Fire",
		"Weapon.Tail.Rifle",
		"Weapon.Distant.Sniper",
		"Weapon.Mech.Rifle",
		"Reload.MagOut",
		"Reload.MagIn",
		"Reload.Rack",
		"Equip.Rifle"
	),
	model = WeaponModels.longGun({
		receiver = Vector3.new(0.22, 0.3, 1.05),
		handguardLength = 0.95,
		handguardHeight = 0.22,
		barrelLength = 0.55,
		barrelDiameter = 0.08,
		muzzle = "Brake",
		mag = "Straight",
		magSize = Vector3.new(0.14, 0.3, 0.26),
		stock = "Full",
		sight = "Scope2x",
		foregrip = false,
		bolt = "Handle",
		accentRings = 3,
	}),
	viewmodel = viewmodel(RIFLE_HIP, 0.85, "Rifle", 1.05),
	tracer = tracer(0.07, 1),
})

-- 9. SG-12 "Breacher" — fusil à pompe --------------------------------------------------------
register({
	id = "sg12",
	displayName = "SG-12 Breacher",
	shortName = "SG-12",
	codename = "BREACHER",
	category = "Shotgun",
	slot = "Primary",
	description = "Fusil à pompe 8 plombs. Dévastateur sous 12 studs, rechargement cartouche par cartouche.",
	feel = "BOOM, puis le 'shk-shk' de la pompe. Le motif fixe récompense le placement du réticule.",
	fire = semi(68, "Pump"),
	damage = {
		base = 20,
		headMultiplier = 2.0,
		limbMultiplier = 0.8,
		falloff = {
			{ range = 10, multiplier = 1 },
			{ range = 20, multiplier = 0.65 },
			{ range = 35, multiplier = 0.35 },
		},
		pellets = 8,
		penetration = 0.4,
		range = 220,
	},
	spread = {
		hip = 1.0,
		ads = 0.5,
		firstShotMultiplier = 1,
		firstShotReset = 0.5,
		move = 1.5,
		air = 3,
		crouchMultiplier = 0.9,
		bloomPerShot = 0,
		bloomMax = 0,
		bloomRecovery = 10,
		bloomRecoveryDelay = 0,
		pelletCone = 4.5,
	},
	recoil = {
		pattern = { Vector2.new(0, 3.2) },
		loopFrom = 1,
		randomYaw = 0.6,
		randomPitch = 0.3,
		adsMultiplier = 0.9,
		crouchMultiplier = 0.9,
		recoveryDelay = 0.1,
		recoverySpeed = 16,
		recoveryRatio = 1,
		punch = 2.6,
		punchRoll = 2.4,
		kickBack = 0.26,
		kickUp = 7,
		kickSide = 1.5,
		shake = 0.18,
	},
	handling = {
		equipTime = 0.8,
		adsTime = 0.2,
		zoom = 1.1,
		sight = "Iron",
		scopeOverlay = false,
		moveMultiplier = 0.95,
		adsMoveMultiplier = 0.7,
		swayMultiplier = 1.15,
	},
	ammo = {
		magazine = 6,
		reserve = 24,
		reloadStyle = "Shell",
		reloadTime = 0,
		emptyReloadTime = 0,
		shellStartTime = 0.35,
		shellInsertTime = 0.42,
		shellEndTime = 0.45,
		chamber = false,
	},
	melee = nil,
	audio = audio(
		"Weapon.Shotgun.Fire",
		"Weapon.Tail.Heavy",
		"Weapon.Distant.Heavy",
		"Weapon.Mech.Heavy",
		"Reload.Shell",
		"Reload.Shell",
		"Reload.Pump",
		"Equip.Heavy"
	),
	model = WeaponModels.longGun({
		receiver = Vector3.new(0.24, 0.32, 0.9),
		handguardLength = 0.0,
		handguardHeight = 0.2,
		barrelLength = 1.05,
		barrelDiameter = 0.11,
		muzzle = "None",
		mag = "Tube",
		magSize = Vector3.new(0.09, 0.09, 0.9),
		stock = "Full",
		sight = "Iron",
		foregrip = false,
		bolt = "Pump",
		accentRings = 0,
	}),
	viewmodel = viewmodel(CFrame.new(0.6, -0.66, -1.18), 1.05, "Heavy", 1.1),
	tracer = tracer(0.035, 2),
})

-- 10. AS-8 "Tempest" — fusil à pompe automatique --------------------------------------------
register({
	id = "as8",
	displayName = "AS-8 Tempest",
	shortName = "AS-8",
	codename = "TEMPEST",
	category = "Shotgun",
	slot = "Primary",
	description = "Fusil automatique à chargeur. Moins de dégâts par tir, mais 5 coups/s pour nettoyer une salle.",
	feel = "Une tempête de plombs. Recul qui grimpe vite : 3-4 tirs puis on repositionne.",
	fire = auto(300),
	damage = {
		base = 13,
		headMultiplier = 2.0,
		limbMultiplier = 0.8,
		falloff = { { range = 8, multiplier = 1 }, { range = 16, multiplier = 0.7 }, { range = 28, multiplier = 0.38 } },
		pellets = 7,
		penetration = 0.4,
		range = 180,
	},
	spread = {
		hip = 1.2,
		ads = 0.7,
		firstShotMultiplier = 1,
		firstShotReset = 0.4,
		move = 1.4,
		air = 3,
		crouchMultiplier = 0.9,
		bloomPerShot = 0.4,
		bloomMax = 2.0,
		bloomRecovery = 6,
		bloomRecoveryDelay = 0.1,
		pelletCone = 5.5,
	},
	recoil = {
		pattern = build({ { count = 8, pitch = 2.0, pitchEnd = 2.5, yaw = 0.3, yawEnd = -0.4 } }),
		loopFrom = 1,
		randomYaw = 0.5,
		randomPitch = 0.25,
		adsMultiplier = 0.9,
		crouchMultiplier = 0.9,
		recoveryDelay = 0.08,
		recoverySpeed = 20,
		recoveryRatio = 0.9,
		punch = 1.8,
		punchRoll = 1.8,
		kickBack = 0.2,
		kickUp = 5,
		kickSide = 1.4,
		shake = 0.12,
	},
	handling = {
		equipTime = 0.82,
		adsTime = 0.22,
		zoom = 1.1,
		sight = "RedDot",
		scopeOverlay = false,
		moveMultiplier = 0.94,
		adsMoveMultiplier = 0.68,
		swayMultiplier = 1.1,
	},
	ammo = magazineAmmo(8, 32, 2.4, 2.8),
	melee = nil,
	audio = audio(
		"Weapon.Shotgun.Auto",
		"Weapon.Tail.Heavy",
		"Weapon.Distant.Heavy",
		"Weapon.Mech.Heavy",
		"Reload.MagOut",
		"Reload.MagIn",
		"Reload.Rack",
		"Equip.Heavy"
	),
	model = WeaponModels.longGun({
		receiver = Vector3.new(0.26, 0.34, 0.85),
		handguardLength = 0.5,
		handguardHeight = 0.26,
		barrelLength = 0.5,
		barrelDiameter = 0.12,
		muzzle = "Brake",
		mag = "Drum",
		magSize = Vector3.new(0.2, 0.4, 0.4),
		stock = "Skeleton",
		sight = "RedDot",
		foregrip = true,
		bolt = "Handle",
		accentRings = 2,
	}),
	viewmodel = viewmodel(CFrame.new(0.62, -0.68, -1.16), 1.0, "Heavy", 1.1),
	tracer = tracer(0.035, 2),
})

-- 11. P-10 "Sidewinder" — pistol standard ---------------------------------------------------
register({
	id = "p10",
	displayName = "P-10 Sidewinder",
	shortName = "P-10",
	codename = "SIDEWINDER",
	category = "Pistol",
	slot = "Secondary",
	description = "Pistolet semi-auto fiable. Sans bouclier, un tir à la tête suffit à courte portée.",
	feel = "Vif et précis au premier tir ; le spam est puni par le bloom. Rechargement éclair.",
	fire = semi(400),
	damage = {
		base = 26,
		headMultiplier = 4.0,
		limbMultiplier = 0.8,
		falloff = { { range = 25, multiplier = 1 }, { range = 70, multiplier = 0.85 } },
		pellets = 1,
		penetration = 0.6,
		range = 450,
	},
	spread = {
		hip = 1.1,
		ads = 0.4,
		firstShotMultiplier = 0.2,
		firstShotReset = 0.3,
		move = 2.2,
		air = 5,
		crouchMultiplier = 0.85,
		bloomPerShot = 0.55,
		bloomMax = 3.0,
		bloomRecovery = 8,
		bloomRecoveryDelay = 0.1,
		pelletCone = 0,
	},
	recoil = {
		pattern = build({ { count = 1, pitch = 1.3, yaw = 0 }, { count = 4, pitch = 1.5, yaw = 0.2, yawEnd = -0.2 } }),
		loopFrom = 2,
		randomYaw = 0.25,
		randomPitch = 0.12,
		adsMultiplier = 0.85,
		crouchMultiplier = 0.9,
		recoveryDelay = 0.06,
		recoverySpeed = 22,
		recoveryRatio = 0.95,
		punch = 0.9,
		punchRoll = 1.2,
		kickBack = 0.12,
		kickUp = 5.5,
		kickSide = 1.0,
		shake = 0.05,
	},
	handling = {
		equipTime = 0.4,
		adsTime = 0.14,
		zoom = 1.1,
		sight = "Iron",
		scopeOverlay = false,
		moveMultiplier = 1.0,
		adsMoveMultiplier = 0.8,
		swayMultiplier = 0.7,
	},
	ammo = magazineAmmo(12, 48, 1.4, 1.7),
	melee = nil,
	audio = audio(
		"Weapon.Pistol.Fire",
		"Weapon.Tail.Light",
		"Weapon.Distant.Light",
		"Weapon.Mech.Light",
		"Reload.MagOut",
		"Reload.MagIn",
		"Reload.Slide",
		"Equip.Pistol"
	),
	model = WeaponModels.pistol({
		slideLength = 0.72,
		slideHeight = 0.15,
		extendedMag = false,
		compensator = false,
		frontGrip = false,
	}),
	viewmodel = viewmodel(PISTOL_HIP, 1.35, "Pistol", 0.8),
	tracer = tracer(0.045, 1),
})

-- 12. R-44 "Judge" — revolver lourd ---------------------------------------------------------
register({
	id = "r44",
	displayName = "R-44 Judge",
	shortName = "R-44",
	codename = "JUDGE",
	category = "Revolver",
	slot = "Secondary",
	description = "Revolver .50 à 6 coups. One-tap tête même contre un bouclier plein.",
	feel = "Lent, théâtral, définitif. Le recul relève l'arme haut : chaque tir doit être le bon.",
	fire = semi(110),
	damage = {
		base = 55,
		headMultiplier = 3.0,
		limbMultiplier = 0.85,
		falloff = { { range = 40, multiplier = 1 }, { range = 100, multiplier = 0.87 } },
		pellets = 1,
		penetration = 1.4,
		range = 550,
	},
	spread = {
		hip = 1.6,
		ads = 0.2,
		firstShotMultiplier = 0.1,
		firstShotReset = 0.5,
		move = 4.5,
		air = 8,
		crouchMultiplier = 0.85,
		bloomPerShot = 1.2,
		bloomMax = 3.5,
		bloomRecovery = 6,
		bloomRecoveryDelay = 0.25,
		pelletCone = 0,
	},
	recoil = {
		pattern = { Vector2.new(0.4, 5.0) },
		loopFrom = 1,
		randomYaw = 0.6,
		randomPitch = 0.3,
		adsMultiplier = 0.9,
		crouchMultiplier = 0.9,
		recoveryDelay = 0.1,
		recoverySpeed = 18,
		recoveryRatio = 0.85,
		punch = 2.4,
		punchRoll = 3.5,
		kickBack = 0.22,
		kickUp = 14,
		kickSide = 2.0,
		shake = 0.14,
	},
	handling = {
		equipTime = 0.55,
		adsTime = 0.17,
		zoom = 1.15,
		sight = "Iron",
		scopeOverlay = false,
		moveMultiplier = 0.98,
		adsMoveMultiplier = 0.75,
		swayMultiplier = 0.9,
	},
	ammo = {
		magazine = 6,
		reserve = 24,
		reloadStyle = "Cylinder",
		reloadTime = 2.6,
		emptyReloadTime = 2.6,
		shellStartTime = 0,
		shellInsertTime = 0,
		shellEndTime = 0,
		chamber = false,
	},
	melee = nil,
	audio = audio(
		"Weapon.Revolver.Fire",
		"Weapon.Tail.Heavy",
		"Weapon.Distant.Heavy",
		"Weapon.Mech.Light",
		"Reload.CylinderOut",
		"Reload.CylinderIn",
		"Reload.Hammer",
		"Equip.Pistol"
	),
	model = WeaponModels.revolver(),
	viewmodel = viewmodel(CFrame.new(0.42, -0.52, -1.4), 1.4, "Pistol", 0.85),
	tracer = tracer(0.06, 1),
})

-- 13. MP-6 "Hornet" — pistolet-mitrailleur (secondaire automatique) -----------------------
register({
	id = "mp6",
	displayName = "MP-6 Hornet",
	shortName = "MP-6",
	codename = "HORNET",
	category = "MachinePistol",
	slot = "Secondary",
	description = "Pistolet automatique 1000 cpm. Le meilleur ami des manches pistolet à courte portée.",
	feel = "Hystérique : une rafale qui arrache tout sous 15 studs, inutile au-delà.",
	fire = auto(1000),
	damage = {
		base = 18,
		headMultiplier = 2.6,
		limbMultiplier = 0.8,
		falloff = {
			{ range = 12, multiplier = 1 },
			{ range = 30, multiplier = 0.8 },
			{ range = 60, multiplier = 0.65 },
		},
		pellets = 1,
		penetration = 0.4,
		range = 320,
	},
	spread = {
		hip = 1.8,
		ads = 0.9,
		firstShotMultiplier = 0.7,
		firstShotReset = 0.2,
		move = 1.4,
		air = 4,
		crouchMultiplier = 0.9,
		bloomPerShot = 0.25,
		bloomMax = 3.2,
		bloomRecovery = 9,
		bloomRecoveryDelay = 0.07,
		pelletCone = 0,
	},
	recoil = {
		pattern = build({
			{ count = 4, pitch = 0.5, yaw = 0.2 },
			{ count = 16, pitch = 0.5, yaw = -0.3, yawEnd = 0.3 },
		}),
		loopFrom = 5,
		randomYaw = 0.5,
		randomPitch = 0.15,
		adsMultiplier = 0.9,
		crouchMultiplier = 0.9,
		recoveryDelay = 0.06,
		recoverySpeed = 24,
		recoveryRatio = 0.85,
		punch = 0.5,
		punchRoll = 1.2,
		kickBack = 0.07,
		kickUp = 2.5,
		kickSide = 1.6,
		shake = 0.035,
	},
	handling = {
		equipTime = 0.45,
		adsTime = 0.15,
		zoom = 1.1,
		sight = "Iron",
		scopeOverlay = false,
		moveMultiplier = 1.0,
		adsMoveMultiplier = 0.8,
		swayMultiplier = 0.75,
	},
	ammo = magazineAmmo(20, 80, 1.6, 1.9),
	melee = nil,
	audio = audio(
		"Weapon.MP.Fire",
		"Weapon.Tail.Light",
		"Weapon.Distant.Light",
		"Weapon.Mech.Light",
		"Reload.MagOut",
		"Reload.MagIn",
		"Reload.Slide",
		"Equip.Pistol"
	),
	model = WeaponModels.pistol({
		slideLength = 0.8,
		slideHeight = 0.16,
		extendedMag = true,
		compensator = true,
		frontGrip = true,
	}),
	viewmodel = viewmodel(CFrame.new(0.44, -0.52, -1.32), 1.3, "Pistol", 0.85),
	tracer = tracer(0.04, 2),
})

-- 14. Ion Blade — couteau de combat ---------------------------------------------------------
register({
	id = "ionblade",
	displayName = "Ion Blade",
	shortName = "ION",
	codename = "ION",
	category = "Melee",
	slot = "Melee",
	description = "Lame à fil ionisé. Coup rapide 50, coup lourd 75, coup lourd dans le dos : élimination.",
	feel = "Vitesse de déplacement maximale, frappes nettes avec un sifflement électrique.",
	fire = semi(133, "Melee"),
	damage = {
		base = 50,
		headMultiplier = 1,
		limbMultiplier = 1,
		falloff = {},
		pellets = 1,
		penetration = 0,
		range = 6.5,
	},
	spread = {
		hip = 0,
		ads = 0,
		firstShotMultiplier = 1,
		firstShotReset = 0,
		move = 0,
		air = 0,
		crouchMultiplier = 1,
		bloomPerShot = 0,
		bloomMax = 0,
		bloomRecovery = 0,
		bloomRecoveryDelay = 0,
		pelletCone = 0,
	},
	recoil = {
		pattern = { Vector2.zero },
		loopFrom = 1,
		randomYaw = 0,
		randomPitch = 0,
		adsMultiplier = 1,
		crouchMultiplier = 1,
		recoveryDelay = 0,
		recoverySpeed = 0,
		recoveryRatio = 1,
		punch = 1.2,
		punchRoll = 4,
		kickBack = 0,
		kickUp = 0,
		kickSide = 0,
		shake = 0.04,
	},
	handling = {
		equipTime = 0.35,
		adsTime = 0.1,
		zoom = 1,
		sight = "None",
		scopeOverlay = false,
		moveMultiplier = 1.08,
		adsMoveMultiplier = 1.08,
		swayMultiplier = 0.6,
	},
	ammo = {
		magazine = 0,
		reserve = 0,
		reloadStyle = "None",
		reloadTime = 0,
		emptyReloadTime = 0,
		shellStartTime = 0,
		shellInsertTime = 0,
		shellEndTime = 0,
		chamber = false,
	},
	melee = {
		lightDamage = 50,
		heavyDamage = 75,
		backstabDamage = 150,
		range = 6.5,
		coneDegrees = 38,
		lightCooldown = 0.45,
		heavyCooldown = 1.0,
		heavyWindup = 0.25,
	},
	audio = audio(
		"Blade.Swing",
		"Blade.Heavy",
		"Blade.Hit",
		"Blade.Hit",
		"Equip.Blade",
		"Equip.Blade",
		"Equip.Blade",
		"Equip.Blade"
	),
	model = WeaponModels.blade(),
	viewmodel = viewmodel(
		CFrame.new(0.55, -0.6, -1.05) * CFrame.Angles(rad(10), rad(-20), rad(-30)),
		1.0,
		"Blade",
		0.7
	),
	tracer = tracer(0, 0),
})

---------------------------------------------------------------------------------------------
-- Accès
---------------------------------------------------------------------------------------------

Weapons.DEFAULT_LOADOUT = { Primary = "vk12", Secondary = "p10", Melee = "ionblade" }
Weapons.PISTOL_ROUND_LOADOUT_SLOTS = { "Secondary", "Melee" } :: { Types.WeaponSlot }

function Weapons.get(id: string): WeaponDef?
	return Weapons.defs[id]
end

function Weapons.require(id: string): WeaponDef
	local def = Weapons.defs[id]
	assert(def, "unknown weapon " .. tostring(id))
	return def
end

function Weapons.isValidForSlot(id: string, slot: Types.WeaponSlot): boolean
	local def = Weapons.defs[id]
	return def ~= nil and def.slot == slot
end

function Weapons.forSlot(slot: Types.WeaponSlot): { WeaponDef }
	local list = {}
	for _, id in Weapons.order do
		local def = Weapons.defs[id]
		if def.slot == slot then
			table.insert(list, def)
		end
	end
	return list
end

--[[ Intervalle minimal entre deux tirs (s). Pour une arme à spin-up, cadence max. ]]
function Weapons.minInterval(def: WeaponDef): number
	local rpm = def.fire.rpm
	if def.fire.spinUp then
		rpm = def.fire.spinUp.endRpm
	end
	if def.fire.mode == "Burst" then
		rpm = def.fire.burstRpm
	end
	return 60 / rpm
end

--[[ Cadence effective d'une arme à spin-up après `heldTime` secondes de tir continu. ]]
function Weapons.currentRpm(def: WeaponDef, heldTime: number): number
	local spin = def.fire.spinUp
	if not spin then
		return def.fire.rpm
	end
	local t = math.clamp(heldTime / spin.time, 0, 1)
	return spin.startRpm + (spin.endRpm - spin.startRpm) * t
end

return Weapons
