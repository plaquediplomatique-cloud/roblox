--!strict
--[[
	MapService — cycle de vie des cartes : hub (lobby) et arènes de match.

	* Lobby : le hub est construit à l'origine au démarrage du serveur.
	* Match (serveur réservé) : l'arène du match est construite à l'origine.
	* Matchs LOCAUX (Studio, parties personnalisées) : chaque arène reçoit un "slot"
	  décalé de 1600 studs — bien au-delà du rayon de streaming (768) : les joueurs du
	  hub ne téléchargent pas les arènes, et inversement. L'arène est
	  PersistentPerPlayer pour ses seuls participants.
	* L'éclairage global du serveur suit la carte en mode Match ; en local, chaque
	  client applique le profil de SON arène (LightingController).
]]

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Maps = require(Shared.Config.Maps)
local Logger = require(Shared.Util.Logger)
local Types = require(Shared.Types)
local ServerRole = require(script.Parent.Parent.ServerRole)
local MapBuilder = require(script.Parent.Parent.Maps.MapBuilder)

local Blueprints = script.Parent.Parent.Maps.Blueprints

local log = Logger.new("Maps")

local BLUEPRINTS: { [string]: MapBuilder.Blueprint } = {
	hub = require(Blueprints.Hub) :: MapBuilder.Blueprint,
	kestrel = require(Blueprints.Kestrel) :: MapBuilder.Blueprint,
	helix = require(Blueprints.Helix) :: MapBuilder.Blueprint,
	spire = require(Blueprints.Spire) :: MapBuilder.Blueprint,
	monolith = require(Blueprints.Monolith) :: MapBuilder.Blueprint,
}

local SLOT_SPACING = 1600

local MapService = {}

local hubInstance: MapBuilder.MapInstance? = nil
local arenasFolder: Folder
local hubFolder: Folder
local usedSlots: { [number]: boolean } = {}
local slotOf: { [MapBuilder.MapInstance]: number } = {}

function MapService.blueprint(mapId: string): MapBuilder.Blueprint?
	return BLUEPRINTS[mapId]
end

function MapService.hub(): MapBuilder.MapInstance?
	return hubInstance
end

function MapService.applyLighting(profile: Types.LightingProfile)
	Lighting.ClockTime = profile.clockTime
	Lighting.Brightness = profile.brightness
	Lighting.Ambient = profile.ambient
	Lighting.OutdoorAmbient = profile.outdoorAmbient
	Lighting.ExposureCompensation = profile.exposure
	Lighting.ColorShift_Top = profile.colorShiftTop
	Lighting.EnvironmentDiffuseScale = profile.diffuseScale
	Lighting.EnvironmentSpecularScale = profile.specularScale
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Density = profile.atmosphere.density
	atmosphere.Offset = profile.atmosphere.offset
	atmosphere.Color = profile.atmosphere.color
	atmosphere.Decay = profile.atmosphere.decay
	atmosphere.Glare = profile.atmosphere.glare
	atmosphere.Haze = profile.atmosphere.haze
	atmosphere.Parent = Lighting
end

--[[ Construit une arène pour un match. `participants` : streaming persistant par joueur. ]]
function MapService.createArena(mapId: string, modeId: string, participants: { Player }?): MapBuilder.MapInstance
	local blueprint = BLUEPRINTS[mapId]
	assert(blueprint, "unknown map " .. mapId)
	local slot = 0
	if ServerRole.isLobby() then
		slot = 1
		while usedSlots[slot] do
			slot += 1
		end
	end
	usedSlots[slot] = true
	local origin = CFrame.new(slot * SLOT_SPACING, 0, 0)
	local instance = MapBuilder.build(blueprint, origin, arenasFolder, modeId)
	slotOf[instance] = slot
	if slot == 0 then
		instance.model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
		local info = Maps.get(mapId)
		if info then
			MapService.applyLighting(info.lighting)
		end
	else
		instance.model.ModelStreamingMode = Enum.ModelStreamingMode.PersistentPerPlayer
		local list: { Player } = participants or {}
		for _, player in list do
			instance.model:AddPersistentPlayer(player)
		end
	end
	log:info("arène", mapId, "mode", modeId, "slot", slot)
	return instance
end

function MapService.addArenaPlayer(instance: MapBuilder.MapInstance, player: Player)
	if instance.model.ModelStreamingMode == Enum.ModelStreamingMode.PersistentPerPlayer then
		instance.model:AddPersistentPlayer(player)
	end
end

function MapService.releaseArena(instance: MapBuilder.MapInstance)
	local slot = slotOf[instance]
	if slot then
		usedSlots[slot] = nil
		slotOf[instance] = nil
	end
	instance.model:Destroy()
end

function MapService.Init()
	arenasFolder = Instance.new("Folder")
	arenasFolder.Name = "Arenas"
	arenasFolder.Parent = Workspace
	hubFolder = Instance.new("Folder")
	hubFolder.Name = "Hub"
	hubFolder.Parent = Workspace
end

function MapService.Start()
	if ServerRole.isLobby() then
		hubInstance = MapBuilder.build(BLUEPRINTS.hub, CFrame.identity, hubFolder, nil)
		local info = Maps.get("hub")
		if info then
			MapService.applyLighting(info.lighting)
		end
	end
end

return MapService
