--!strict
--[[
	Sounds — bibliothèque sonore logique.

	Le code ne référence JAMAIS un SoundId directement : il demande une clé logique
	("Weapon.Rifle.Fire", "Hit.Head"…). Ce fichier est l'unique point de branchement du
	pack audio : remplacer les `ids` par les rbxassetid:// du sound design final suffit.

	Les ids fournis sont des sons intégrés au client Roblox (rbxasset://sounds/…),
	disponibles sans upload, retravaillés par pitch/volume/couches. Ils rendent le jeu
	jouable et lisible tel quel ; le pack final (voir docs/09) les remplace un à un.

	Chaque définition :
	  ids        : variations (une est tirée au hasard -> pas de répétition "mitraillette")
	  volume     : volume de base
	  pitch      : plage aléatoire (micro-variations = son vivant)
	  group      : SoundGroup cible (mix, ducking, réglages joueur)
	  rolloff    : distances min/max pour les sons 3D (nil = son 2D)
]]

export type SoundGroupName = "Music" | "Weapons" | "Footsteps" | "Impacts" | "Feedback" | "Ambient" | "UI" | "Voice"

export type SoundDef = {
	ids: { string },
	volume: number,
	pitch: NumberRange,
	group: SoundGroupName,
	rolloff: Vector2?,
	looped: boolean?,
}

local ROCKET = "rbxasset://sounds/Rocket shot.wav"
local PAINTBALL = "rbxasset://sounds/paintball.wav"
local CLICK = "rbxasset://sounds/clickfast.wav"
local BUTTON = "rbxasset://sounds/button.wav"
local PING = "rbxasset://sounds/electronicpingshort.wav"
local SNAP = "rbxasset://sounds/snap.wav"
local HIT = "rbxasset://sounds/hit.wav"
local COLLIDE = "rbxasset://sounds/collide.wav"
local GLASS = "rbxasset://sounds/glassbreak.wav"
local THUNDER = "rbxasset://sounds/HalloweenThunder.wav"
local SLASH = "rbxasset://sounds/swordslash.wav"
local LUNGE = "rbxasset://sounds/swordlunge.wav"
local UNSHEATH = "rbxasset://sounds/unsheath.wav"
local STEP = "rbxasset://sounds/action_footsteps_plastic.mp3"
local JUMP = "rbxasset://sounds/action_jump.mp3"
local LAND = "rbxasset://sounds/action_jump_land.mp3"
local FALL = "rbxasset://sounds/action_falling.mp3"
local WHOOSH = "rbxasset://sounds/Rocket whoosh.wav"
local SPLAT = "rbxasset://sounds/splat.wav"

local function def(
	ids: { string },
	volume: number,
	pitchMin: number,
	pitchMax: number,
	group: SoundGroupName,
	rolloff: Vector2?,
	looped: boolean?
): SoundDef
	return {
		ids = ids,
		volume = volume,
		pitch = NumberRange.new(pitchMin, pitchMax),
		group = group,
		rolloff = rolloff,
		looped = looped,
	}
end

local NEAR = Vector2.new(8, 260)
local MID = Vector2.new(6, 120)
local SHORT = Vector2.new(4, 60)

local Sounds = {}

Sounds.defs = {
	-- Armes : couche "corps" (le coup), "tail" (réverbération selon intérieur/extérieur),
	-- "distant" (version lointaine entendue par les autres joueurs), "mech" (mécanique)
	["Weapon.Rifle.Fire"] = def({ ROCKET }, 0.55, 1.9, 2.05, "Weapons", NEAR),
	["Weapon.Rifle.Suppressed"] = def({ PAINTBALL }, 0.7, 0.62, 0.7, "Weapons", MID),
	["Weapon.Rifle.Burst"] = def({ ROCKET }, 0.5, 2.15, 2.3, "Weapons", NEAR),
	["Weapon.SMG.Fire"] = def({ PAINTBALL }, 0.75, 0.82, 0.92, "Weapons", MID),
	["Weapon.LMG.Fire"] = def({ ROCKET }, 0.6, 1.6, 1.72, "Weapons", NEAR),
	["Weapon.Sniper.Fire"] = def({ ROCKET }, 0.9, 1.05, 1.12, "Weapons", Vector2.new(12, 400)),
	["Weapon.DMR.Fire"] = def({ ROCKET }, 0.75, 1.4, 1.5, "Weapons", Vector2.new(10, 320)),
	["Weapon.Shotgun.Fire"] = def({ ROCKET }, 0.85, 1.2, 1.3, "Weapons", NEAR),
	["Weapon.Shotgun.Auto"] = def({ ROCKET }, 0.7, 1.45, 1.55, "Weapons", NEAR),
	["Weapon.Pistol.Fire"] = def({ PAINTBALL }, 0.8, 0.7, 0.78, "Weapons", MID),
	["Weapon.Revolver.Fire"] = def({ ROCKET }, 0.85, 1.3, 1.38, "Weapons", NEAR),
	["Weapon.MP.Fire"] = def({ PAINTBALL }, 0.7, 0.95, 1.05, "Weapons", MID),
	["Weapon.Tail.Rifle"] = def({ THUNDER }, 0.18, 2.6, 2.9, "Weapons", NEAR),
	["Weapon.Tail.Light"] = def({ THUNDER }, 0.1, 3.2, 3.5, "Weapons", MID),
	["Weapon.Tail.Heavy"] = def({ THUNDER }, 0.25, 2.1, 2.3, "Weapons", NEAR),
	["Weapon.Distant.Rifle"] = def({ THUNDER }, 0.35, 3.0, 3.3, "Weapons", Vector2.new(40, 600)),
	["Weapon.Distant.Light"] = def({ THUNDER }, 0.25, 3.6, 3.9, "Weapons", Vector2.new(30, 400)),
	["Weapon.Distant.Heavy"] = def({ THUNDER }, 0.45, 2.4, 2.6, "Weapons", Vector2.new(50, 700)),
	["Weapon.Distant.Sniper"] = def({ THUNDER }, 0.6, 1.8, 2.0, "Weapons", Vector2.new(60, 900)),
	["Weapon.Mech.Rifle"] = def({ CLICK }, 0.25, 0.75, 0.85, "Weapons", SHORT),
	["Weapon.Mech.Light"] = def({ CLICK }, 0.2, 0.95, 1.05, "Weapons", SHORT),
	["Weapon.Mech.Heavy"] = def({ CLICK }, 0.3, 0.6, 0.68, "Weapons", SHORT),
	["Weapon.Dry"] = def({ CLICK }, 0.6, 1.3, 1.4, "Weapons", SHORT),

	-- Rechargements et maniement
	["Reload.MagOut"] = def({ SNAP }, 0.45, 0.8, 0.9, "Weapons", SHORT),
	["Reload.MagIn"] = def({ SNAP }, 0.55, 1.05, 1.15, "Weapons", SHORT),
	["Reload.Rack"] = def({ CLICK }, 0.6, 0.55, 0.62, "Weapons", SHORT),
	["Reload.Bolt"] = def({ CLICK }, 0.7, 0.45, 0.5, "Weapons", SHORT),
	["Reload.Pump"] = def({ SNAP }, 0.75, 0.6, 0.66, "Weapons", SHORT),
	["Reload.Shell"] = def({ SNAP }, 0.5, 1.25, 1.4, "Weapons", SHORT),
	["Reload.Slide"] = def({ CLICK }, 0.55, 0.7, 0.78, "Weapons", SHORT),
	["Reload.BoxOut"] = def({ COLLIDE }, 0.5, 0.7, 0.8, "Weapons", SHORT),
	["Reload.BoxIn"] = def({ SNAP }, 0.6, 0.7, 0.75, "Weapons", SHORT),
	["Reload.CylinderOut"] = def({ SNAP }, 0.5, 1.4, 1.5, "Weapons", SHORT),
	["Reload.CylinderIn"] = def({ SNAP }, 0.55, 1.2, 1.3, "Weapons", SHORT),
	["Reload.Hammer"] = def({ CLICK }, 0.6, 1.1, 1.2, "Weapons", SHORT),
	["Equip.Rifle"] = def({ SNAP }, 0.4, 0.7, 0.75, "Weapons", SHORT),
	["Equip.Light"] = def({ SNAP }, 0.35, 0.9, 1.0, "Weapons", SHORT),
	["Equip.Heavy"] = def({ COLLIDE }, 0.4, 0.6, 0.65, "Weapons", SHORT),
	["Equip.Pistol"] = def({ CLICK }, 0.45, 0.9, 1.0, "Weapons", SHORT),
	["Equip.Blade"] = def({ UNSHEATH }, 0.5, 1.1, 1.2, "Weapons", SHORT),
	["Blade.Swing"] = def({ SLASH }, 0.6, 1.15, 1.3, "Weapons", SHORT),
	["Blade.Heavy"] = def({ LUNGE }, 0.7, 0.95, 1.05, "Weapons", SHORT),
	["Blade.Hit"] = def({ HIT }, 0.7, 0.8, 0.9, "Impacts", SHORT),

	-- Impacts (par matériau)
	["Impact.Concrete"] = def({ COLLIDE }, 0.35, 1.6, 1.9, "Impacts", SHORT),
	["Impact.Metal"] = def({ PING }, 0.18, 1.8, 2.2, "Impacts", SHORT),
	["Impact.Wood"] = def({ HIT }, 0.3, 1.2, 1.4, "Impacts", SHORT),
	["Impact.Glass"] = def({ GLASS }, 0.4, 1.3, 1.6, "Impacts", SHORT),
	["Impact.Flesh"] = def({ SPLAT }, 0.45, 1.1, 1.3, "Impacts", SHORT),
	["Impact.Shield"] = def({ PING }, 0.3, 1.2, 1.35, "Impacts", SHORT),

	-- Déplacement
	["Step.Default"] = def({ STEP }, 0.5, 1.75, 2.0, "Footsteps", Vector2.new(5, 70)),
	["Step.Metal"] = def({ STEP }, 0.55, 2.2, 2.45, "Footsteps", Vector2.new(5, 70)),
	["Step.Soft"] = def({ STEP }, 0.35, 1.5, 1.65, "Footsteps", Vector2.new(4, 50)),
	["Move.Jump"] = def({ JUMP }, 0.4, 1.0, 1.1, "Footsteps", Vector2.new(5, 60)),
	["Move.Land"] = def({ LAND }, 0.55, 0.95, 1.05, "Footsteps", Vector2.new(5, 70)),
	["Move.Slide"] = def({ FALL }, 0.35, 1.6, 1.8, "Footsteps", Vector2.new(5, 60)),
	["Move.Lean"] = def({ CLICK }, 0.12, 0.5, 0.6, "Footsteps", SHORT),

	-- Feedback de combat (2D, priorité absolue dans le mix)
	["Hit.Body"] = def({ HIT }, 0.55, 1.5, 1.6, "Feedback"),
	["Hit.Head"] = def({ PING }, 0.5, 1.9, 2.0, "Feedback"),
	["Hit.Armor"] = def({ PING }, 0.35, 1.25, 1.3, "Feedback"),
	["Hit.ArmorBreak"] = def({ GLASS }, 0.35, 1.8, 2.0, "Feedback"),
	["Hit.Kill"] = def({ PING }, 0.7, 1.35, 1.4, "Feedback"),
	["Hit.KillHead"] = def({ PING }, 0.8, 1.6, 1.65, "Feedback"),
	["Hit.KillBass"] = def({ THUNDER }, 0.35, 3.8, 4.0, "Feedback"),
	["Hurt"] = def({ HIT }, 0.5, 0.6, 0.7, "Feedback"),
	["Heartbeat"] = def({ COLLIDE }, 0.5, 0.45, 0.5, "Feedback"),

	-- Objectif Uplink
	["Uplink.Beep"] = def({ PING }, 0.45, 1.0, 1.0, "Feedback", Vector2.new(10, 160)),
	["Uplink.Plant"] = def({ BUTTON }, 0.6, 0.8, 0.85, "Feedback", Vector2.new(8, 90)),
	["Uplink.Defuse"] = def({ BUTTON }, 0.6, 1.2, 1.25, "Feedback", Vector2.new(8, 90)),
	["Uplink.Planted"] = def({ PING }, 0.8, 0.7, 0.72, "Feedback"),
	["Uplink.Detonate"] = def({ THUNDER }, 1, 0.8, 0.85, "Feedback", Vector2.new(30, 800)),

	-- Interface
	["UI.Hover"] = def({ CLICK }, 0.12, 2.0, 2.2, "UI"),
	["UI.Click"] = def({ BUTTON }, 0.35, 1.3, 1.35, "UI"),
	["UI.Confirm"] = def({ PING }, 0.4, 1.2, 1.2, "UI"),
	["UI.Back"] = def({ BUTTON }, 0.3, 0.9, 0.95, "UI"),
	["UI.Error"] = def({ BUTTON }, 0.4, 0.6, 0.62, "UI"),
	["UI.Tick"] = def({ CLICK }, 0.35, 1.6, 1.6, "UI"),
	["UI.MatchFound"] = def({ PING }, 0.8, 0.9, 0.9, "UI"),
	["UI.RoundStart"] = def({ PING }, 0.6, 1.05, 1.05, "UI"),
	["UI.RoundWin"] = def({ PING }, 0.7, 1.5, 1.5, "UI"),
	["UI.RoundLose"] = def({ PING }, 0.6, 0.6, 0.6, "UI"),
	["UI.Victory"] = def({ THUNDER }, 0.5, 1.6, 1.6, "UI"),
	["UI.Defeat"] = def({ THUNDER }, 0.45, 0.9, 0.9, "UI"),
	["UI.LevelUp"] = def({ PING }, 0.7, 1.7, 1.7, "UI"),
	["UI.RankUp"] = def({ PING }, 0.8, 2.1, 2.1, "UI"),
	["UI.Reward"] = def({ PING }, 0.6, 1.4, 1.5, "UI"),
	["UI.Whoosh"] = def({ WHOOSH }, 0.3, 1.4, 1.6, "UI"),
	["UI.Glitch"] = def({ CLICK }, 0.3, 0.5, 2.5, "UI"),

	-- Ambiances (boucles)
	["Ambient.Industrial"] = def({ FALL }, 0.08, 0.3, 0.3, "Ambient", nil, true),
	["Ambient.Wind"] = def({ FALL }, 0.12, 0.45, 0.45, "Ambient", nil, true),
	["Ambient.Hum"] = def({ FALL }, 0.06, 0.22, 0.22, "Ambient", nil, true),
} :: { [string]: SoundDef }

function Sounds.get(key: string): SoundDef?
	return Sounds.defs[key]
end

return Sounds
