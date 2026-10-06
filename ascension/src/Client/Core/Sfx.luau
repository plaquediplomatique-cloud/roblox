--!strict
--[[
	Sfx — lecteur de sons par CLÉS LOGIQUES (Config/Sounds). Aucun SoundId dans le code de jeu.

	* Sounds poolés par clé (pas de création/destruction à chaque coup) ;
	* variation de hauteur aléatoire (anti « mitraillette ») ;
	* SoundGroups (Weapons, Impacts, Feedback, UI) : réglage des effets sonores en un point ;
	* sons 3D pour les autres joueurs (attachés à leur HumanoidRootPart).
]]

local SoundService = game:GetService("SoundService")

local Shared = game:GetService("ReplicatedStorage").Shared
local Sounds = require(Shared.Config.Sounds)
local Store = require(script.Parent.Store)

local Sfx = {}

local POOL_SIZE = 4
local pools: { [string]: { Sound } } = {}
local cursor: { [string]: number } = {}
local groups: { [string]: SoundGroup } = {}
local rng = Random.new()

local GROUP_NAMES = { "Weapons", "Impacts", "Feedback", "UI", "Music" }

local function group(name: string): SoundGroup
	local existing = groups[name]
	if existing then
		return existing
	end
	local created = Instance.new("SoundGroup")
	created.Name = name
	created.Parent = SoundService
	groups[name] = created
	return created
end

function Sfx.applySettings()
	local settings = Store.settings()
	for _, name in GROUP_NAMES do
		local g = group(name)
		if name == "Music" then
			g.Volume = if settings.Music then 0.5 else 0
		else
			g.Volume = if settings.Sfx then 1 else 0
		end
	end
end

function Sfx.start()
	for _, name in GROUP_NAMES do
		group(name)
	end
	Sfx.applySettings()
	Store.Changed:Connect(function(key)
		if key == "Settings" then
			Sfx.applySettings()
		end
	end)
end

export type Options = { Pitch: number?, Volume: number?, Parent: Instance? }

-- Joue une clé logique. `Parent` (ex. HumanoidRootPart) rend le son 3D.
function Sfx.play(key: string, options: Options?)
	local def = Sounds[key]
	if not def then
		return
	end
	local opts: Options = options or {}
	local pool = pools[key]
	if not pool then
		local created: { Sound } = {}
		for _ = 1, POOL_SIZE do
			local sound = Instance.new("Sound")
			sound.RollOffMaxDistance = 90
			sound.RollOffMinDistance = 12
			table.insert(created, sound)
		end
		pools[key] = created
		cursor[key] = 0
		pool = created
	end
	local index = (cursor[key] % POOL_SIZE) + 1
	cursor[key] = index
	local sound = pool[index]
	sound.SoundId = def.ids[rng:NextInteger(1, #def.ids)]
	sound.Volume = def.volume * (opts.Volume or 1)
	sound.PlaybackSpeed = rng:NextNumber(def.pitch.Min, def.pitch.Max) * (opts.Pitch or 1)
	sound.SoundGroup = group(def.group)
	local parent = opts.Parent or SoundService
	if sound.Parent ~= parent then
		sound.Parent = parent
	end
	sound.TimePosition = 0
	sound:Play()
end

return Sfx
