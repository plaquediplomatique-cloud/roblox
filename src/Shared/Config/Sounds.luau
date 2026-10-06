--!strict
--[[
	Sounds — bibliothèque sonore logique.

	Le code ne référence JAMAIS un SoundId directement : il demande une clé logique
	("Weapon.Rifle.Fire", "Hit.Head"…). Ce fichier est l'unique point de branchement du
	pack audio : remplacer les `ids` par les rbxassetid:// du sound design final suffit.

	Les ids fournis sont des sons intégrés au client Roblox (rbxasset://sounds/…),
	disponibles sans upload, retravaillés par pitch, égaliseur, coupe et couches. Ils
	rendent le jeu jouable et lisible tel quel ; le pack final les remplace un à un :
	coller un `rbxassetid://…` (Creator Store → Audio, ou son propre upload) dans `ids`,
	remettre `pitch` à 1 et retirer `tone`/`cut`/`layers` si le nouveau son est déjà mixé.

	Chaque définition :
	  ids        : variations (une est tirée au hasard -> pas de répétition "mitraillette")
	  volume     : volume de base
	  pitch      : plage aléatoire (micro-variations = son vivant)
	  group      : SoundGroup cible (mix, ducking, réglages joueur)
	  rolloff    : distances min/max pour les sons 3D (nil = son 2D)
	  tone, cut, layers : égaliseur, coupe en fondu, sons joués ensemble (facultatifs)
]]

export type SoundGroupName = "Music" | "Weapons" | "Footsteps" | "Impacts" | "Feedback" | "Ambient" | "UI" | "Voice"

-- Égalisation (dB, -80 … 10) : bas < 400 Hz, médiums, aigus > 4 kHz.
export type Tone = { low: number?, mid: number?, high: number? }

export type SoundDef = {
	ids: { string },
	volume: number,
	pitch: NumberRange,
	group: SoundGroupName,
	rolloff: Vector2?,
	looped: boolean?,
	tone: Tone?, -- égaliseur appliqué au son (adoucir, épaissir)
	cut: number?, -- coupe en fondu après N secondes (garde l'attaque, retire la traîne)
	layers: { string }?, -- clés jouées en même temps (son composé)
}

local SoundPack = require(script.Parent.SoundPack)

type Shape = { tone: Tone?, cut: number?, layers: { string }? }

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

local function shape(base: SoundDef, extra: Shape): SoundDef
	base.tone = extra.tone
	base.cut = extra.cut
	base.layers = extra.layers
	return base
end

local NEAR = Vector2.new(8, 260)
local MID = Vector2.new(6, 120)
local SHORT = Vector2.new(4, 60)

local Sounds = {}

Sounds.defs = {
	-- Armes. Plus aucun son d'explosion (« Rocket shot » sonnait comme du tonnerre) : le corps
	-- est un « pop » sec (paintball grave), sans grondement ni traîne. Un tir = corps (le coup, coupé avant la traîne) + attaque (claquement) +
	-- impact grave + mécanique, puis une queue 3D discrète réverbérée en intérieur. Les
	-- autres joueurs au-delà de 120 studs entendent la version « distant » (étouffée).
	-- Volumes volontairement bas : le compresseur du groupe Armes égalise les rafales.
	["Weapon.Layer.Crack"] = def({ SNAP }, 0.16, 0.62, 0.7, "Weapons", MID),
	["Weapon.Layer.CrackLight"] = def({ SNAP }, 0.12, 0.85, 0.95, "Weapons", MID),
	["Weapon.Layer.Thump"] = shape(def({ HIT }, 0.2, 0.42, 0.48, "Weapons", MID), {
		tone = { low = 6, mid = -4, high = -24 },
	}),
	["Weapon.Layer.ThumpHeavy"] = shape(def({ HIT }, 0.26, 0.34, 0.38, "Weapons", MID), {
		tone = { low = 8, mid = -4, high = -26 },
	}),

	["Weapon.Rifle.Fire"] = shape(def({ PAINTBALL }, 0.26, 0.7, 0.75, "Weapons", NEAR), {
		tone = { low = 3, mid = -2, high = -12 },
		cut = 0.2,
		layers = { "Weapon.Layer.Crack", "Weapon.Layer.Thump" },
	}),
	["Weapon.Rifle.Suppressed"] = shape(def({ PAINTBALL }, 0.3, 0.6, 0.66, "Weapons", MID), {
		tone = { low = 2, high = -10 },
		cut = 0.25,
		layers = { "Weapon.Layer.CrackLight" },
	}),
	["Weapon.Rifle.Burst"] = shape(def({ PAINTBALL }, 0.24, 0.74, 0.78, "Weapons", NEAR), {
		tone = { low = 3, mid = -2, high = -12 },
		cut = 0.18,
		layers = { "Weapon.Layer.Crack", "Weapon.Layer.Thump" },
	}),
	["Weapon.SMG.Fire"] = shape(def({ PAINTBALL }, 0.28, 0.85, 0.92, "Weapons", MID), {
		tone = { low = 2, high = -8 },
		cut = 0.2,
		layers = { "Weapon.Layer.CrackLight" },
	}),
	["Weapon.LMG.Fire"] = shape(def({ PAINTBALL }, 0.28, 0.62, 0.66, "Weapons", NEAR), {
		tone = { low = 4, mid = -2, high = -14 },
		cut = 0.22,
		layers = { "Weapon.Layer.Crack", "Weapon.Layer.ThumpHeavy" },
	}),
	["Weapon.Sniper.Fire"] = shape(def({ PAINTBALL }, 0.32, 0.5, 0.54, "Weapons", Vector2.new(12, 400)), {
		tone = { low = 5, mid = -1, high = -10 },
		cut = 0.45,
		layers = { "Weapon.Layer.Crack", "Weapon.Layer.ThumpHeavy" },
	}),
	["Weapon.DMR.Fire"] = shape(def({ PAINTBALL }, 0.3, 0.6, 0.64, "Weapons", Vector2.new(10, 320)), {
		tone = { low = 4, mid = -2, high = -12 },
		cut = 0.3,
		layers = { "Weapon.Layer.Crack", "Weapon.Layer.Thump" },
	}),
	["Weapon.Shotgun.Fire"] = shape(def({ PAINTBALL }, 0.32, 0.5, 0.55, "Weapons", NEAR), {
		tone = { low = 6, mid = -2, high = -14 },
		cut = 0.3,
		layers = { "Weapon.Layer.Crack", "Weapon.Layer.ThumpHeavy" },
	}),
	["Weapon.Shotgun.Auto"] = shape(def({ PAINTBALL }, 0.28, 0.55, 0.6, "Weapons", NEAR), {
		tone = { low = 5, mid = -2, high = -14 },
		cut = 0.25,
		layers = { "Weapon.Layer.ThumpHeavy" },
	}),
	["Weapon.Pistol.Fire"] = shape(def({ PAINTBALL }, 0.3, 0.75, 0.8, "Weapons", MID), {
		tone = { low = 3, high = -6 },
		cut = 0.22,
		layers = { "Weapon.Layer.CrackLight", "Weapon.Layer.Thump" },
	}),
	["Weapon.Revolver.Fire"] = shape(def({ PAINTBALL }, 0.3, 0.58, 0.62, "Weapons", NEAR), {
		tone = { low = 5, mid = -2, high = -12 },
		cut = 0.3,
		layers = { "Weapon.Layer.Crack", "Weapon.Layer.ThumpHeavy" },
	}),
	["Weapon.MP.Fire"] = shape(def({ PAINTBALL }, 0.26, 0.95, 1.02, "Weapons", MID), {
		tone = { low = 2, high = -8 },
		cut = 0.2,
		layers = { "Weapon.Layer.CrackLight" },
	}),
	-- Queues : souffle grave et étouffé (plus de tonnerre), courtes.
	["Weapon.Tail.Rifle"] = shape(def({ PAINTBALL }, 0.07, 0.5, 0.55, "Weapons", NEAR), {
		tone = { low = 2, mid = -8, high = -30 },
		cut = 0.7,
	}),
	["Weapon.Tail.Light"] = shape(def({ PAINTBALL }, 0.05, 0.55, 0.6, "Weapons", MID), {
		tone = { low = 1, mid = -8, high = -30 },
		cut = 0.5,
	}),
	["Weapon.Tail.Heavy"] = shape(def({ PAINTBALL }, 0.1, 0.45, 0.5, "Weapons", NEAR), {
		tone = { low = 3, mid = -8, high = -30 },
		cut = 0.9,
	}),
	-- Lointain : coup sourd filtré (on lit la distance à l'oreille).
	["Weapon.Distant.Rifle"] = shape(def({ PAINTBALL }, 0.2, 0.5, 0.55, "Weapons", Vector2.new(40, 600)), {
		tone = { low = 3, mid = -6, high = -28 },
		cut = 0.4,
	}),
	["Weapon.Distant.Light"] = shape(def({ PAINTBALL }, 0.2, 0.6, 0.66, "Weapons", Vector2.new(30, 400)), {
		tone = { low = 2, mid = -6, high = -28 },
		cut = 0.3,
	}),
	["Weapon.Distant.Heavy"] = shape(def({ PAINTBALL }, 0.26, 0.45, 0.5, "Weapons", Vector2.new(50, 700)), {
		tone = { low = 4, mid = -6, high = -28 },
		cut = 0.5,
	}),
	["Weapon.Distant.Sniper"] = shape(def({ PAINTBALL }, 0.3, 0.42, 0.46, "Weapons", Vector2.new(60, 900)), {
		tone = { low = 4, mid = -6, high = -26 },
		cut = 0.6,
	}),
	["Weapon.Mech.Rifle"] = def({ CLICK }, 0.12, 0.75, 0.85, "Weapons", SHORT),
	["Weapon.Mech.Light"] = def({ CLICK }, 0.1, 0.95, 1.05, "Weapons", SHORT),
	["Weapon.Mech.Heavy"] = def({ CLICK }, 0.14, 0.6, 0.68, "Weapons", SHORT),
	["Weapon.Dry"] = def({ CLICK }, 0.4, 1.3, 1.4, "Weapons", SHORT),

	-- Rechargements et maniement
	["Reload.MagOut"] = def({ SNAP }, 0.3, 0.8, 0.9, "Weapons", SHORT),
	["Reload.MagIn"] = def({ SNAP }, 0.38, 1.05, 1.15, "Weapons", SHORT),
	["Reload.Rack"] = def({ CLICK }, 0.42, 0.55, 0.62, "Weapons", SHORT),
	["Reload.Bolt"] = def({ CLICK }, 0.48, 0.45, 0.5, "Weapons", SHORT),
	["Reload.Pump"] = def({ SNAP }, 0.5, 0.6, 0.66, "Weapons", SHORT),
	["Reload.Shell"] = def({ SNAP }, 0.34, 1.25, 1.4, "Weapons", SHORT),
	["Reload.Slide"] = def({ CLICK }, 0.38, 0.7, 0.78, "Weapons", SHORT),
	["Reload.BoxOut"] = def({ COLLIDE }, 0.34, 0.7, 0.8, "Weapons", SHORT),
	["Reload.BoxIn"] = def({ SNAP }, 0.42, 0.7, 0.75, "Weapons", SHORT),
	["Reload.CylinderOut"] = def({ SNAP }, 0.34, 1.4, 1.5, "Weapons", SHORT),
	["Reload.CylinderIn"] = def({ SNAP }, 0.38, 1.2, 1.3, "Weapons", SHORT),
	["Reload.Hammer"] = def({ CLICK }, 0.42, 1.1, 1.2, "Weapons", SHORT),
	["Equip.Rifle"] = def({ SNAP }, 0.28, 0.7, 0.75, "Weapons", SHORT),
	["Equip.Light"] = def({ SNAP }, 0.25, 0.9, 1.0, "Weapons", SHORT),
	["Equip.Heavy"] = def({ COLLIDE }, 0.28, 0.6, 0.65, "Weapons", SHORT),
	["Equip.Pistol"] = def({ CLICK }, 0.3, 0.9, 1.0, "Weapons", SHORT),
	["Equip.Blade"] = def({ UNSHEATH }, 0.35, 1.1, 1.2, "Weapons", SHORT),
	["Blade.Swing"] = def({ SLASH }, 0.42, 1.15, 1.3, "Weapons", SHORT),
	["Blade.Heavy"] = def({ LUNGE }, 0.5, 0.95, 1.05, "Weapons", SHORT),
	["Blade.Hit"] = def({ HIT }, 0.5, 0.8, 0.9, "Impacts", SHORT),

	-- Impacts (par matériau)
	["Impact.Concrete"] = shape(def({ COLLIDE }, 0.22, 1.6, 1.9, "Impacts", SHORT), { tone = { high = -6 } }),
	["Impact.Metal"] = shape(def({ PING }, 0.1, 2.0, 2.4, "Impacts", SHORT), { tone = { high = -8 } }),
	["Impact.Wood"] = def({ HIT }, 0.22, 1.2, 1.4, "Impacts", SHORT),
	["Impact.Glass"] = shape(def({ GLASS }, 0.28, 1.3, 1.6, "Impacts", SHORT), { tone = { high = -6 } }),
	["Impact.Flesh"] = def({ SPLAT }, 0.3, 1.1, 1.3, "Impacts", SHORT),
	["Impact.Shield"] = def({ PING }, 0.2, 1.2, 1.35, "Impacts", SHORT),

	-- Déplacement (pitchs proches du naturel : le pas reste un pas, pas un « tic »)
	["Step.Default"] = def({ STEP }, 0.45, 1.15, 1.3, "Footsteps", Vector2.new(5, 70)),
	["Step.Metal"] = shape(def({ STEP }, 0.5, 1.45, 1.6, "Footsteps", Vector2.new(5, 70)), { tone = { high = 2 } }),
	["Step.Soft"] = shape(def({ STEP }, 0.32, 0.9, 1.0, "Footsteps", Vector2.new(4, 50)), { tone = { high = -10 } }),
	["Step.Wood"] = shape(def({ STEP }, 0.45, 1.0, 1.1, "Footsteps", Vector2.new(5, 65)), {
		tone = { mid = 2, high = -4 },
	}),
	["Step.Hard"] = def({ STEP }, 0.42, 1.35, 1.5, "Footsteps", Vector2.new(5, 70)),
	["Move.Jump"] = def({ JUMP }, 0.32, 1.0, 1.1, "Footsteps", Vector2.new(5, 60)),
	["Move.Land"] = def({ LAND }, 0.45, 0.95, 1.05, "Footsteps", Vector2.new(5, 70)),
	["Move.Slide"] = def({ FALL }, 0.28, 1.6, 1.8, "Footsteps", Vector2.new(5, 60)),
	["Move.Lean"] = def({ CLICK }, 0.1, 0.5, 0.6, "Footsteps", SHORT),

	-- Feedback de combat (2D, priorité absolue dans le mix, mais jamais agressif)
	["Hit.Body"] = def({ HIT }, 0.34, 1.5, 1.6, "Feedback"),
	["Hit.Head"] = def({ PING }, 0.32, 1.9, 2.0, "Feedback"),
	["Hit.Armor"] = def({ PING }, 0.24, 1.25, 1.3, "Feedback"),
	["Hit.ArmorBreak"] = shape(def({ GLASS }, 0.24, 1.8, 2.0, "Feedback"), { tone = { high = -6 } }),
	["Hit.Kill"] = def({ PING }, 0.42, 1.35, 1.4, "Feedback"),
	["Hit.KillHead"] = def({ PING }, 0.5, 1.6, 1.65, "Feedback"),
	["Hit.KillBass"] = shape(def({ HIT }, 0.3, 0.42, 0.46, "Feedback"), { tone = { low = 6, high = -20 } }),
	["Hurt"] = shape(def({ HIT }, 0.38, 0.6, 0.7, "Feedback"), { tone = { high = -8 } }),
	["Heartbeat"] = def({ COLLIDE }, 0.45, 0.45, 0.5, "Feedback"),

	-- Objectif Uplink
	["Uplink.Beep"] = def({ PING }, 0.36, 1.0, 1.0, "Feedback", Vector2.new(10, 160)),
	["Uplink.Plant"] = def({ BUTTON }, 0.5, 0.8, 0.85, "Feedback", Vector2.new(8, 90)),
	["Uplink.Defuse"] = def({ BUTTON }, 0.5, 1.2, 1.25, "Feedback", Vector2.new(8, 90)),
	["Uplink.Planted"] = def({ PING }, 0.6, 0.7, 0.72, "Feedback"),
	["Uplink.Detonate"] = shape(def({ THUNDER }, 0.75, 0.75, 0.8, "Feedback", Vector2.new(30, 800)), {
		tone = { low = 4, high = -6 },
	}),

	-- Interface
	["UI.Hover"] = def({ CLICK }, 0.1, 2.0, 2.2, "UI"),
	["UI.Click"] = def({ BUTTON }, 0.3, 1.3, 1.35, "UI"),
	["UI.Confirm"] = def({ PING }, 0.32, 1.2, 1.2, "UI"),
	["UI.Back"] = def({ BUTTON }, 0.26, 0.9, 0.95, "UI"),
	["UI.Error"] = def({ BUTTON }, 0.34, 0.6, 0.62, "UI"),
	["UI.Tick"] = def({ CLICK }, 0.3, 1.6, 1.6, "UI"),
	["UI.MatchFound"] = def({ PING }, 0.6, 0.9, 0.9, "UI"),
	["UI.RoundStart"] = def({ PING }, 0.45, 1.05, 1.05, "UI"),
	["UI.RoundWin"] = def({ PING }, 0.5, 1.5, 1.5, "UI"),
	["UI.RoundLose"] = def({ PING }, 0.45, 0.6, 0.6, "UI"),
	-- Victoire : accord majeur (fondamentale, tierce, quinte) ; défaite : tierce mineure.
	["UI.Victory"] = shape(def({ PING }, 0.4, 1.0, 1.0, "UI"), { layers = { "UI.ChordThird", "UI.ChordFifth" } }),
	["UI.Defeat"] = shape(def({ PING }, 0.38, 0.75, 0.75, "UI"), { layers = { "UI.ChordMinorThird" } }),
	["UI.ChordThird"] = def({ PING }, 0.3, 1.26, 1.26, "UI"),
	["UI.ChordFifth"] = def({ PING }, 0.3, 1.5, 1.5, "UI"),
	["UI.ChordMinorThird"] = def({ PING }, 0.3, 0.89, 0.89, "UI"),
	["UI.LevelUp"] = def({ PING }, 0.55, 1.7, 1.7, "UI"),
	["UI.RankUp"] = def({ PING }, 0.6, 2.1, 2.1, "UI"),
	["UI.Reward"] = def({ PING }, 0.45, 1.4, 1.5, "UI"),
	["UI.Whoosh"] = def({ WHOOSH }, 0.22, 1.4, 1.6, "UI"),
	["UI.Glitch"] = def({ CLICK }, 0.22, 0.5, 2.5, "UI"),

	-- Ambiances : sons ponctuels autour de l'auditeur (AudioController, profils de cartes)
	["Ambient.Thunder"] = shape(def({ THUNDER }, 0.4, 0.45, 0.6, "Ambient", Vector2.new(60, 900)), {
		tone = { high = -10 },
	}),
	["Ambient.Creak"] = def({ COLLIDE }, 0.2, 0.35, 0.45, "Ambient", Vector2.new(10, 140)),
	["Ambient.Drip"] = def({ SNAP }, 0.15, 1.6, 2.2, "Ambient", Vector2.new(4, 40)),
	["Ambient.Traffic"] = def({ WHOOSH }, 0.18, 0.45, 0.6, "Ambient", Vector2.new(30, 300)),
	["Ambient.Announce"] = def({ PING }, 0.24, 0.75, 0.8, "Ambient", Vector2.new(10, 120)),
	["Ambient.Chime"] = def({ PING }, 0.18, 1.25, 1.3, "Ambient", Vector2.new(10, 90)),
	["Ambient.Hvac"] = def({ FALL }, 0.1, 0.25, 0.3, "Ambient", Vector2.new(8, 60)),
	["Ambient.Gust"] = def({ FALL }, 0.25, 0.5, 0.7, "Ambient", Vector2.new(20, 200)),
	["Ambient.IceCrack"] = def({ GLASS }, 0.18, 0.4, 0.55, "Ambient", Vector2.new(15, 200)),
	["Ambient.Pulse"] = def({ PING }, 0.2, 0.3, 0.34, "Ambient", Vector2.new(10, 120)),

	-- Ambiances (boucles)
	["Ambient.Industrial"] = def({ FALL }, 0.07, 0.3, 0.3, "Ambient", nil, true),
	["Ambient.Wind"] = def({ FALL }, 0.1, 0.45, 0.45, "Ambient", nil, true),
	["Ambient.Hum"] = def({ FALL }, 0.05, 0.22, 0.22, "Ambient", nil, true),
} :: { [string]: SoundDef }

-- Pack de tirs maison : une entrée dont les ids sont renseignés remplace le son de repli.
local packed: { [string]: SoundDef } = {}
for key, entry in SoundPack do
	local base = Sounds.defs[key]
	if base and #entry.ids > 0 then
		packed[key] = def(entry.ids, entry.volume, 0.97, 1.03, base.group, base.rolloff)
	end
end

function Sounds.get(key: string): SoundDef?
	return packed[key] or Sounds.defs[key]
end

return Sounds
