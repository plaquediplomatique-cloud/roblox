--!strict
--[[
	Animator — animations PROCÉDURALES du viewmodel (aucun asset d'animation requis).

	Un "clip" = des pistes de keyframes normalisées (t ∈ [0, 1]) :
	  root     : offset de toute l'arme (espace caméra, appliqué après hip/ADS)
	  mag      : offset du chargeur / barillet (espace arme, échelle design)
	  bolt     : culasse, levier, pompe, culasse de pistolet, chien du revolver
	  leftHand : cible de la main gauche (espace arme)
	  events   : sons, éjection de chargeur, douilles — déclenchés au bon instant
	Interpolation smoothstep entre keyframes, durée calée sur les stats de l'arme
	(un rechargement de 2.3 s DURE 2.3 s : l'animation EST le timing de gameplay).
	Les clips sont générés par style (Rifle / Pistol / Heavy / Blade, Magazine / Shell /
	Belt / Cylinder) : 14 armes animées sans 14 jeux d'animations.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)

export type Keyframe = { t: number, cf: CFrame }
export type Track = { Keyframe }

export type Clip = {
	name: string,
	duration: number,
	root: Track?,
	mag: Track?,
	bolt: Track?,
	leftHand: Track?,
	events: { { t: number, name: string } },
	blendOut: number?,
}

export type Pose = {
	root: CFrame,
	mag: CFrame,
	bolt: CFrame,
	leftHand: CFrame?,
}

export type Player = {
	play: (self: Player, clip: Clip, onEvent: ((string) -> ())?, onDone: (() -> ())?) -> (),
	stop: (self: Player) -> (),
	isPlaying: (self: Player, name: string?) -> boolean,
	progress: (self: Player) -> number,
	evaluate: (self: Player, dt: number) -> Pose,
}

local rad = math.rad
local IDENTITY = CFrame.identity

local Animator = {}

local function key(t: number, cf: CFrame): Keyframe
	return { t = t, cf = cf }
end

function Animator.sample(track: Track, t: number): CFrame
	local count = #track
	if count == 0 then
		return IDENTITY
	end
	if t <= track[1].t then
		return track[1].cf
	end
	for index = 2, count do
		local b = track[index]
		if t <= b.t then
			local a = track[index - 1]
			local span = b.t - a.t
			local alpha = if span > 0 then (t - a.t) / span else 1
			alpha = alpha * alpha * (3 - 2 * alpha)
			return a.cf:Lerp(b.cf, alpha)
		end
	end
	return track[count].cf
end

---------------------------------------------------------------------------------------------
-- Générateurs de clips
---------------------------------------------------------------------------------------------

local function magOffset(def: Types.WeaponDef): Vector3
	local name = def.model.magPiece
	if name then
		for _, piece in def.model.pieces do
			if piece.name == name then
				return piece.offset.Position
			end
		end
	end
	return Vector3.new(0, -0.3, -0.4)
end

function Animator.reload(def: Types.WeaponDef, empty: boolean, duration: number): Clip
	local style = def.ammo.reloadStyle
	local hand = def.model.leftHand
	local mag = magOffset(def)
	local events: { { t: number, name: string } } = {}
	local clip: Clip = { name = "Reload", duration = duration, events = events }

	if style == "Cylinder" then
		clip.root = {
			key(0, IDENTITY),
			key(0.15, CFrame.new(-0.05, 0.05, 0.1) * CFrame.Angles(rad(25), rad(10), rad(35))),
			key(0.85, CFrame.new(-0.05, 0.05, 0.1) * CFrame.Angles(rad(25), rad(10), rad(35))),
			key(1, IDENTITY),
		}
		clip.mag = {
			key(0.12, IDENTITY),
			key(0.22, CFrame.new(-0.22, 0, 0) * CFrame.Angles(0, 0, rad(-60))),
			key(0.78, CFrame.new(-0.22, 0, 0) * CFrame.Angles(0, 0, rad(-60))),
			key(0.88, IDENTITY),
		}
		clip.leftHand = {
			key(0, hand),
			key(0.25, CFrame.new(-0.3, -0.05, -0.1)),
			key(0.4, CFrame.new(-0.4, -0.7, 0.1)),
			key(0.6, CFrame.new(-0.28, -0.1, -0.12)),
			key(0.88, CFrame.new(-0.28, 0, -0.12)),
			key(1, hand),
		}
		table.insert(events, { t = 0.2, name = "Sound:reloadOut" })
		table.insert(events, { t = 0.3, name = "Shells" })
		table.insert(events, { t = 0.86, name = "Sound:reloadIn" })
		return clip
	end

	if style == "Belt" then
		clip.root = {
			key(0, IDENTITY),
			key(0.12, CFrame.new(0.1, 0.1, 0.15) * CFrame.Angles(rad(18), rad(-20), rad(-15))),
			key(0.88, CFrame.new(0.1, 0.1, 0.15) * CFrame.Angles(rad(18), rad(-20), rad(-15))),
			key(1, IDENTITY),
		}
		clip.mag = {
			key(0.2, IDENTITY),
			key(0.35, CFrame.new(0.1, -1.2, 0.2)),
			key(0.55, CFrame.new(0.1, -1.2, 0.2)),
			key(0.56, CFrame.new(0, -0.9, 0)),
			key(0.75, IDENTITY),
		}
		clip.bolt = {
			key(0.82, IDENTITY),
			key(0.88, CFrame.new(0, 0, 0.25)),
			key(0.93, IDENTITY),
		}
		clip.leftHand = {
			key(0, hand),
			key(0.2, CFrame.new(mag.X, mag.Y, mag.Z)),
			key(0.4, CFrame.new(0, -1.3, -0.2)),
			key(0.6, CFrame.new(mag.X, mag.Y - 0.3, mag.Z)),
			key(0.76, CFrame.new(mag.X, mag.Y, mag.Z)),
			key(0.86, CFrame.new(0.2, 0.2, -0.1)),
			key(1, hand),
		}
		table.insert(events, { t = 0.3, name = "Sound:reloadOut" })
		table.insert(events, { t = 0.32, name = "DropMag" })
		table.insert(events, { t = 0.74, name = "Sound:reloadIn" })
		table.insert(events, { t = 0.88, name = "Sound:rack" })
		return clip
	end

	-- Chargeur classique (fusils, SMG, DMR, pistolets, AS-8)
	local pistol = def.viewmodel.inspect == "Pistol"
	local tilt = if pistol
		then CFrame.new(0, 0.05, 0.1) * CFrame.Angles(rad(20), rad(-5), rad(-20))
		else CFrame.new(0.06, -0.04, 0.08) * CFrame.Angles(rad(12), rad(-10), rad(-30))
	clip.root = {
		key(0, IDENTITY),
		key(0.14, tilt),
		key(0.72, tilt),
		key(0.8, tilt * CFrame.new(0, 0.04, -0.02)),
		key(if empty then 0.86 else 0.92, tilt * CFrame.Angles(rad(-4), 0, rad(6))),
		key(1, IDENTITY),
	}
	clip.mag = {
		key(0.18, IDENTITY),
		key(0.3, CFrame.new(0, -1.1, 0.12)),
		key(0.52, CFrame.new(0, -1.1, 0.12)),
		key(0.53, CFrame.new(0, -0.8, 0.05)),
		key(0.72, CFrame.new(0, -0.08, 0.01)),
		key(0.78, IDENTITY),
	}
	clip.leftHand = {
		key(0, hand),
		key(0.18, CFrame.new(mag.X, mag.Y - 0.05, mag.Z)),
		key(0.34, CFrame.new(mag.X - 0.1, mag.Y - 0.9, mag.Z + 0.2)),
		key(0.53, CFrame.new(mag.X, mag.Y - 0.75, mag.Z)),
		key(0.72, CFrame.new(mag.X, mag.Y - 0.1, mag.Z)),
		key(0.8, CFrame.new(mag.X, mag.Y - 0.02, mag.Z)),
		key(1, hand),
	}
	table.insert(events, { t = 0.24, name = "Sound:reloadOut" })
	table.insert(events, { t = 0.3, name = "DropMag" })
	table.insert(events, { t = 0.76, name = "Sound:reloadIn" })
	if empty then
		clip.bolt = {
			key(0.84, IDENTITY),
			key(0.89, CFrame.new(0, 0, if pistol then 0.2 else 0.18)),
			key(0.93, IDENTITY),
		}
		table.insert(events, { t = 0.88, name = "Sound:rack" })
	end
	return clip
end

--[[ Rechargement cartouche par cartouche (SG-12) : début / insertion / fin (pompe). ]]
function Animator.shellStart(def: Types.WeaponDef): Clip
	return {
		name = "ShellStart",
		duration = def.ammo.shellStartTime,
		root = { key(0, IDENTITY), key(1, CFrame.new(0, 0.05, 0.1) * CFrame.Angles(rad(15), rad(10), rad(30))) },
		events = {},
		blendOut = 0,
	}
end

function Animator.shellInsert(def: Types.WeaponDef): Clip
	local held = CFrame.new(0, 0.05, 0.1) * CFrame.Angles(rad(15), rad(10), rad(30))
	return {
		name = "ShellInsert",
		duration = def.ammo.shellInsertTime,
		root = { key(0, held), key(0.5, held * CFrame.new(0, 0.03, -0.02)), key(1, held) },
		leftHand = {
			key(0, CFrame.new(0, -0.9, -0.3)),
			key(0.45, CFrame.new(0, -0.15, -0.55)),
			key(0.6, CFrame.new(0, -0.1, -0.6)),
			key(1, CFrame.new(0, -0.9, -0.3)),
		},
		events = { { t = 0.5, name = "Sound:reloadIn" } },
		blendOut = 0,
	}
end

function Animator.shellEnd(def: Types.WeaponDef): Clip
	local held = CFrame.new(0, 0.05, 0.1) * CFrame.Angles(rad(15), rad(10), rad(30))
	return {
		name = "ShellEnd",
		duration = def.ammo.shellEndTime,
		root = { key(0, held), key(1, IDENTITY) },
		bolt = { key(0.2, IDENTITY), key(0.5, CFrame.new(0, 0, 0.35)), key(0.85, IDENTITY) },
		events = { { t = 0.45, name = "Sound:rack" } },
	}
end

--[[ Cycle de culasse / pompe après un tir (RS-1, SG-12). ]]
function Animator.cycle(def: Types.WeaponDef, duration: number): Clip
	if def.fire.mode == "Pump" then
		local hand = def.model.leftHand
		return {
			name = "Cycle",
			duration = duration,
			root = { key(0, IDENTITY), key(0.4, CFrame.Angles(rad(4), 0, rad(-3))), key(1, IDENTITY) },
			bolt = { key(0.1, IDENTITY), key(0.45, CFrame.new(0, 0, 0.38)), key(0.8, IDENTITY) },
			leftHand = { key(0.1, hand), key(0.45, hand * CFrame.new(0, 0, 0.38)), key(0.8, hand) },
			events = { { t = 0.4, name = "Sound:rack" }, { t = 0.45, name = "Shell" } },
		}
	end
	return {
		name = "Cycle",
		duration = duration,
		root = {
			key(0, IDENTITY),
			key(0.25, CFrame.new(0.05, 0, 0.05) * CFrame.Angles(rad(6), rad(-6), rad(-12))),
			key(0.75, CFrame.new(0.05, 0, 0.05) * CFrame.Angles(rad(6), rad(-6), rad(-12))),
			key(1, IDENTITY),
		},
		bolt = {
			key(0.15, IDENTITY),
			key(0.3, CFrame.Angles(0, 0, rad(75))),
			key(0.5, CFrame.new(0, 0, 0.4) * CFrame.Angles(0, 0, rad(75))),
			key(0.7, CFrame.Angles(0, 0, rad(75))),
			key(0.85, IDENTITY),
		},
		events = { { t = 0.45, name = "Sound:rack" }, { t = 0.5, name = "Shell" } },
	}
end

function Animator.equip(def: Types.WeaponDef, duration: number, first: boolean): Clip
	local events: { { t: number, name: string } } = { { t = 0.05, name = "Sound:equip" } }
	local clip: Clip = {
		name = "Equip",
		duration = duration,
		root = {
			key(0, CFrame.new(0.2, -1.1, 0.4) * CFrame.Angles(rad(-55), rad(20), rad(30))),
			key(0.75, CFrame.new(0, 0.03, 0) * CFrame.Angles(rad(3), 0, 0)),
			key(1, IDENTITY),
		},
		events = events,
	}
	if first and def.model.boltPiece and def.category ~= "Melee" then
		clip.bolt = { key(0.55, IDENTITY), key(0.7, CFrame.new(0, 0, 0.2)), key(0.82, IDENTITY) }
		table.insert(events, { t = 0.68, name = "Sound:rack" })
	end
	return clip
end

function Animator.inspect(def: Types.WeaponDef, flourish: boolean): Clip
	local style = def.viewmodel.inspect
	local sideA, sideB
	if style == "Pistol" then
		sideA = CFrame.new(-0.25, 0.2, 0.25) * CFrame.Angles(rad(10), rad(70), rad(25))
		sideB = CFrame.new(-0.1, 0.25, 0.2) * CFrame.Angles(rad(-15), rad(-50), rad(-70))
	elseif style == "Blade" then
		sideA = CFrame.new(-0.3, 0.3, 0.2) * CFrame.Angles(rad(40), rad(80), rad(10))
		sideB = CFrame.new(-0.2, 0.25, 0.1) * CFrame.Angles(rad(40), rad(-100), rad(-30))
	else
		sideA = CFrame.new(-0.3, 0.15, 0.25) * CFrame.Angles(rad(12), rad(55), rad(30))
		sideB = CFrame.new(-0.05, 0.1, 0.15) * CFrame.Angles(rad(-8), rad(-55), rad(-25))
	end
	local root: Track = {
		key(0, IDENTITY),
		key(0.15, sideA),
		key(0.42, sideA * CFrame.Angles(rad(4), 0, 0)),
	}
	if flourish then
		-- Rotation complète en 4 étapes (le lerp prend toujours le chemin le plus court).
		table.insert(root, key(0.48, sideA * CFrame.Angles(0, 0, rad(-90))))
		table.insert(root, key(0.53, sideA * CFrame.Angles(0, 0, rad(-180))))
		table.insert(root, key(0.58, sideA * CFrame.Angles(0, 0, rad(-270))))
		table.insert(root, key(0.63, sideA))
	end
	table.insert(root, key(0.72, sideB))
	table.insert(root, key(0.9, sideB * CFrame.Angles(rad(-4), 0, 0)))
	table.insert(root, key(1, IDENTITY))
	return { name = "Inspect", duration = if flourish then 4.2 else 3.2, root = root, events = {} }
end

function Animator.melee(heavy: boolean): Clip
	if heavy then
		return {
			name = "MeleeHeavy",
			duration = 0.75,
			root = {
				key(0, IDENTITY),
				key(0.3, CFrame.new(0.2, 0.25, 0.3) * CFrame.Angles(rad(30), rad(-30), rad(-40))),
				key(0.45, CFrame.new(-0.35, -0.1, -0.5) * CFrame.Angles(rad(-25), rad(40), rad(30))),
				key(0.7, CFrame.new(-0.3, -0.15, -0.3) * CFrame.Angles(rad(-15), rad(35), rad(25))),
				key(1, IDENTITY),
			},
			events = { { t = 0.33, name = "Sound:tail" }, { t = 0.38, name = "Strike" } },
		}
	end
	return {
		name = "MeleeLight",
		duration = 0.42,
		root = {
			key(0, IDENTITY),
			key(0.2, CFrame.new(0.3, 0.15, 0) * CFrame.Angles(rad(10), rad(-35), rad(-50))),
			key(0.5, CFrame.new(-0.35, -0.12, -0.25) * CFrame.Angles(rad(-10), rad(45), rad(40))),
			key(1, IDENTITY),
		},
		events = { { t = 0.15, name = "Sound:fire" }, { t = 0.3, name = "Strike" } },
	}
end

---------------------------------------------------------------------------------------------
-- Lecteur
---------------------------------------------------------------------------------------------

local PlayerClass = {}
PlayerClass.__index = PlayerClass

function PlayerClass.play(self: any, clip: Clip, onEvent: ((string) -> ())?, onDone: (() -> ())?)
	self.clip = clip
	self.time = 0
	self.firedEvents = {}
	self.onEvent = onEvent
	self.onDone = onDone
	self.blend = 1
end

function PlayerClass.stop(self: any)
	self.clip = nil
	self.onDone = nil
end

function PlayerClass.isPlaying(self: any, name: string?): boolean
	local clip = self.clip
	return clip ~= nil and (name == nil or clip.name == name)
end

function PlayerClass.progress(self: any): number
	local clip = self.clip
	if not clip then
		return 1
	end
	return math.clamp(self.time / math.max(clip.duration, 0.001), 0, 1)
end

function PlayerClass.evaluate(self: any, dt: number): Pose
	local clip: Clip? = self.clip
	local pose: Pose = { root = IDENTITY, mag = IDENTITY, bolt = IDENTITY, leftHand = nil }
	if not clip then
		return pose
	end
	self.time += dt
	local t = math.clamp(self.time / math.max(clip.duration, 0.001), 0, 1)
	for index, event in clip.events do
		if t >= event.t and not self.firedEvents[index] then
			self.firedEvents[index] = true
			local handler = self.onEvent
			if handler then
				task.spawn(handler, event.name)
			end
		end
	end
	if clip.root then
		pose.root = Animator.sample(clip.root, t)
	end
	if clip.mag then
		pose.mag = Animator.sample(clip.mag, t)
	end
	if clip.bolt then
		pose.bolt = Animator.sample(clip.bolt, t)
	end
	if clip.leftHand then
		pose.leftHand = Animator.sample(clip.leftHand, t)
	end
	if t >= 1 then
		local done = self.onDone
		self.clip = nil
		self.onDone = nil
		if done then
			task.spawn(done)
		end
	end
	return pose
end

function Animator.newPlayer(): Player
	return (setmetatable({ clip = nil, time = 0, firedEvents = {}, blend = 0 }, PlayerClass) :: any) :: Player
end

return Animator
