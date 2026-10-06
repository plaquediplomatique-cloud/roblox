--!strict
--[[
	SoundscapeKit — zone-based ambience beds, random spot one-shots around the listener and
	intensity-driven music stems, on the legacy Sound API (available in every experience).

	Client only. Copy this ModuleScript into the client code and start it once:

		local SoundscapeKit = require(path.to.SoundscapeKit)
		local soundscape = SoundscapeKit.start({
			zonesFolder = workspace.Map.AudioZones,
			defaultAmbience = "Street",
			beds = {
				Street = { id = "rbxassetid://…", volume = 0.35 },
				Interior = { id = "rbxassetid://…", volume = 0.25 },
			},
			spots = {
				{ ids = { "rbxassetid://…" }, volume = 0.4, interval = NumberRange.new(8, 20),
				  distance = NumberRange.new(40, 90), zones = { "Street" } },
			},
			stems = {
				{ id = "rbxassetid://…", volume = 0.3, threshold = 0 },   -- base layer
				{ id = "rbxassetid://…", volume = 0.3, threshold = 0.6 }, -- combat layer
			},
		})
		soundscape.setIntensity(0.8) -- e.g. while enemies are near

	Zones are invisible boxes (Anchored, CanCollide/CanQuery/CanTouch false) inside
	`zonesFolder`, with attributes:
		Ambience (string)  key into `beds`
		Reverb   (string)  Enum.ReverbType name, e.g. "Room", "Hallway", "ParkingLot"
		Priority (number)  highest wins where zones overlap (a room inside a street block)
]]

local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

export type Bed = { id: string, volume: number }

export type Spot = {
	ids: { string },
	volume: number,
	interval: NumberRange, -- seconds between two plays of this spot
	distance: NumberRange, -- horizontal distance from the listener, studs
	height: NumberRange?, -- height above the listener, studs
	pitch: NumberRange?,
	zones: { string }?, -- only while one of these ambience keys is active (nil = everywhere)
}

export type Stem = { id: string, volume: number, threshold: number }

export type Config = {
	zonesFolder: Instance?,
	defaultAmbience: string?,
	defaultReverb: Enum.ReverbType?,
	beds: { [string]: Bed },
	spots: { Spot }?,
	stems: { Stem }?,
	soundGroup: SoundGroup?,
	musicGroup: SoundGroup?,
	fade: number?, -- bed crossfade time in seconds (default 2)
}

export type Handle = {
	setIntensity: (value: number) -> (),
	current: () -> string?,
	stop: () -> (),
}

local SoundscapeKit = {}

local ZONE_INTERVAL = 0.25 -- zone lookups per second are cheap but need not run every frame
local STEM_EDGE = 0.2 -- intensity range over which a stem fades in below its threshold

local function inside(part: BasePart, point: Vector3): boolean
	local relative = part.CFrame:PointToObjectSpace(point)
	local half = part.Size * 0.5
	return math.abs(relative.X) <= half.X and math.abs(relative.Y) <= half.Y and math.abs(relative.Z) <= half.Z
end

-- Highest-priority zone box containing `point`, or nil.
function SoundscapeKit.zoneAt(folder: Instance, point: Vector3): BasePart?
	local best: BasePart? = nil
	local bestPriority = -math.huge
	for _, child in folder:GetChildren() do
		if child:IsA("BasePart") and inside(child, point) then
			local priority = child:GetAttribute("Priority")
			local value = if typeof(priority) == "number" then priority else 0
			if value > bestPriority then
				best, bestPriority = child, value
			end
		end
	end
	return best
end

-- Stem weight: 0 well below the threshold, 1 from the threshold upward.
function SoundscapeKit.stemWeight(intensity: number, threshold: number): number
	return math.clamp((intensity - threshold) / STEM_EDGE + 1, 0, 1)
end

local function approach(current: number, target: number, rate: number, dt: number): number
	return current + (target - current) * (1 - math.exp(-rate * dt))
end

local function makeLoop(id: string, group: SoundGroup?, parent: Instance): Sound
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Looped = true
	sound.Volume = 0
	sound.SoundGroup = group
	sound.Parent = parent
	return sound
end

function SoundscapeKit.start(config: Config): Handle
	local container = Instance.new("Folder")
	container.Name = "Soundscape"
	container.Parent = SoundService

	local rate = 3 / (config.fade or 2) -- ~95 % of a crossfade done after `fade` seconds
	local rng = Random.new()
	local previousReverb = SoundService.AmbientReverb
	local reverb = previousReverb
	local currentKey: string? = config.defaultAmbience
	local intensity = 0
	local zoneClock = 0

	local beds: { [string]: Sound } = {}
	for key, bed in config.beds do
		beds[key] = makeLoop(bed.id, config.soundGroup, container)
	end

	-- Stems start together and never pause, so they stay in sync (same loop length).
	local stemDefs: { Stem } = config.stems or {}
	local stems: { Sound } = {}
	for _, stem in stemDefs do
		table.insert(stems, makeLoop(stem.id, config.musicGroup, container))
	end
	for _, sound in stems do
		sound:Play()
	end

	local spots: { Spot } = config.spots or {}
	local timers: { number } = {}
	for index, spot in spots do
		timers[index] = rng:NextNumber(spot.interval.Min, spot.interval.Max)
	end

	local function spotAllowed(spot: Spot): boolean
		local zones = spot.zones
		if not zones then
			return true
		end
		return currentKey ~= nil and table.find(zones, currentKey) ~= nil
	end

	local function playSpot(spot: Spot, origin: Vector3)
		local angle = rng:NextNumber(0, 2 * math.pi)
		local distance = rng:NextNumber(spot.distance.Min, spot.distance.Max)
		local height = if spot.height then rng:NextNumber(spot.height.Min, spot.height.Max) else 0
		local attachment = Instance.new("Attachment")
		attachment.Name = "SoundscapeSpot"
		attachment.Position = origin + Vector3.new(math.cos(angle) * distance, height, math.sin(angle) * distance)
		attachment.Parent = Workspace.Terrain
		local sound = Instance.new("Sound")
		sound.SoundId = spot.ids[rng:NextInteger(1, #spot.ids)]
		sound.Volume = spot.volume
		sound.PlaybackSpeed = if spot.pitch then rng:NextNumber(spot.pitch.Min, spot.pitch.Max) else 1
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = spot.distance.Min * 0.5
		sound.RollOffMaxDistance = spot.distance.Max * 2
		sound.SoundGroup = config.soundGroup
		sound.Parent = attachment
		sound.Ended:Once(function()
			attachment:Destroy()
		end)
		sound:Play()
		task.delay(30, function() -- safety net if the asset never loads or never ends
			if attachment.Parent then
				attachment:Destroy()
			end
		end)
	end

	local function updateZone(position: Vector3)
		local key = config.defaultAmbience
		local target = config.defaultReverb or previousReverb
		local folder = config.zonesFolder
		local zone = if folder then SoundscapeKit.zoneAt(folder, position) else nil
		if zone then
			local ambience = zone:GetAttribute("Ambience")
			if typeof(ambience) == "string" and beds[ambience] then
				key = ambience
			end
			local reverbName = zone:GetAttribute("Reverb")
			if typeof(reverbName) == "string" then
				target = Enum.ReverbType:FromName(reverbName) or target
			end
		end
		currentKey = key
		if target ~= reverb then
			reverb = target
			SoundService.AmbientReverb = target
		end
	end

	local connection = RunService.Heartbeat:Connect(function(dt: number)
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local position = camera.CFrame.Position

		zoneClock -= dt
		if zoneClock <= 0 then
			zoneClock = ZONE_INTERVAL
			updateZone(position)
		end

		for key, sound in beds do
			local target = if key == currentKey then config.beds[key].volume else 0
			local volume = approach(sound.Volume, target, rate, dt)
			if target == 0 and volume < 0.005 then
				sound.Volume = 0
				if sound.IsPlaying then
					sound:Pause() -- paused beds keep their position and cost no voice
				end
			else
				sound.Volume = volume
				if not sound.IsPlaying then
					if sound.IsPaused then
						sound:Resume()
					else
						sound:Play()
					end
				end
			end
		end

		for index, sound in stems do
			local stem = stemDefs[index]
			local target = stem.volume * SoundscapeKit.stemWeight(intensity, stem.threshold)
			sound.Volume = approach(sound.Volume, target, 1.5, dt)
		end

		for index, spot in spots do
			timers[index] -= dt
			if timers[index] <= 0 then
				timers[index] = rng:NextNumber(spot.interval.Min, spot.interval.Max)
				if spotAllowed(spot) then
					playSpot(spot, position)
				end
			end
		end
	end)

	local handle: Handle = {
		setIntensity = function(value: number)
			intensity = math.clamp(value, 0, 1)
		end,
		current = function(): string?
			return currentKey
		end,
		stop = function()
			connection:Disconnect()
			container:Destroy()
			SoundService.AmbientReverb = previousReverb
		end,
	}
	return handle
end

return SoundscapeKit
