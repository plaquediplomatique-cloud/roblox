--!strict
--[[
	MatchService — orchestration des matchs.

	* Lobby : matchs LOCAUX (Studio, parties personnalisées, repli si MemoryStore
	  indisponible) : arène construite sur un slot du serveur, retour au hub en fin.
	* Match (serveur réservé) : lit sa MatchSpec dans MemoryStore (clé = PrivateServerId,
	  écrite par le matchmaker : source de confiance), construit l'arène, accueille les
	  joueurs attendus (les autres sont expulsés), puis renvoie tout le monde au lobby.
	* Fournit au CombatService le "combat ouvert ?" (phase Live/Planted) et le first blood.
	* Route les remotes Interact (pose/désamorçage) et LoadoutSelect (préparation).
]]

local HttpService = game:GetService("HttpService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local GameModes = require(Shared.Config.GameModes)
local Maps = require(Shared.Config.Maps)
local Guard = require(Shared.Util.Guard)
local Logger = require(Shared.Util.Logger)
local ServerRole = require(script.Parent.Parent.ServerRole)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local MatchInstance = require(script.Parent.Parent.Match.MatchInstance)
local DataService = require(script.Parent.DataService)
local MapService = require(script.Parent.MapService)
local PlayerService = require(script.Parent.PlayerService)
local CombatService = require(script.Parent.CombatService)
local ProgressionService = require(script.Parent.ProgressionService)

local log = Logger.new("MatchService")

local SPEC_MAP = "AS_MatchSpecs"

local MatchService = {}

local matches: { [string]: MatchInstance.MatchInstance } = {}
local playerMatch: { [Player]: MatchInstance.MatchInstance } = {}

function MatchService.forPlayer(player: Player): MatchInstance.MatchInstance?
	return playerMatch[player]
end

function MatchService.isInMatch(player: Player): boolean
	return playerMatch[player] ~= nil
end

local function teleportToLobby(players: { Player })
	local list = {}
	for _, player in players do
		if player.Parent == Players then
			table.insert(list, player)
		end
	end
	if #list == 0 then
		return
	end
	for attempt = 1, 3 do
		local ok, err = pcall(function()
			TeleportService:TeleportAsync(game.PlaceId, list)
		end)
		if ok then
			return
		end
		log:warn("retour lobby échoué (tentative " .. attempt .. ")", err)
		task.wait(2)
	end
	for _, player in list do
		player:Kick("AETHER STRIKE — Match terminé. Reconnectez-vous pour retrouver le hub.")
	end
end

local function hooks(isLocal: boolean): MatchInstance.Hooks
	return {
		onFinished = function(_match: MatchInstance.MatchInstance, result: MatchInstance.MatchResult)
			ProgressionService.processMatch(result)
		end,
		onClosed = function(match: MatchInstance.MatchInstance, players: { Player })
			matches[match.id] = nil
			for player, current in playerMatch do
				if current == match then
					playerMatch[player] = nil
				end
			end
			if isLocal then
				for _, player in players do
					PlayerService.returnToHub(player)
				end
				MapService.releaseArena(match.arena)
			else
				-- Le match est terminé : plus rien à "rejoindre".
				task.spawn(function()
					pcall(function()
						local active = MemoryStoreService:GetHashMap("AS_ActiveMatch")
						for userId in match.expected do
							active:RemoveAsync(tostring(userId))
						end
					end)
				end)
				teleportToLobby(players)
			end
		end,
	}
end

--[[ Lance un match sur ce serveur (arène locale). ]]
function MatchService.startLocal(spec: Types.MatchSpec, players: { Player }): MatchInstance.MatchInstance?
	local mode = GameModes.get(spec.mode)
	if not mode or not Maps.supports(spec.map, spec.mode) then
		log:warn("spec invalide", spec.mode, spec.map)
		return nil
	end
	local arena = MapService.createArena(spec.map, spec.mode, players)
	local match = MatchInstance.new(spec, arena, hooks(true))
	matches[spec.matchId] = match
	for _, player in players do
		if match:addPlayer(player) then
			playerMatch[player] = match
		end
	end
	log:info("match local", spec.matchId, spec.mode, spec.map, #players, "joueurs")
	return match
end

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

local function fetchSpec(): Types.MatchSpec?
	local ok, map = pcall(function()
		return MemoryStoreService:GetHashMap(SPEC_MAP)
	end)
	if not ok or not map then
		return nil
	end
	for _ = 1, 15 do
		local success, value = pcall(function()
			return (map :: MemoryStoreHashMap):GetAsync(game.PrivateServerId)
		end)
		local spec = if success then decodeSpec(value) else nil
		if spec then
			return spec
		end
		task.wait(2)
	end
	return nil
end

local function startRemoteMatch()
	local spec = fetchSpec()
	if not spec then
		log:warn("MatchSpec introuvable : repli en partie non classée")
		task.wait(10)
		local teams = { A = {}, B = {} }
		for index, player in Players:GetPlayers() do
			table.insert(if index % 2 == 1 then teams.A else teams.B, player.UserId)
		end
		spec = {
			matchId = HttpService:GenerateGUID(false),
			mode = "Clash2",
			map = "monolith",
			ranked = false,
			custom = true,
			teams = teams,
			createdAt = os.time(),
		}
	end
	local finalSpec = spec :: Types.MatchSpec
	local arena = MapService.createArena(finalSpec.map, finalSpec.mode, nil)
	local match = MatchInstance.new(finalSpec, arena, hooks(false))
	matches[finalSpec.matchId] = match
	local function admit(player: Player)
		DataService.waitForProfile(player, 30)
		if player.Parent ~= Players then
			return
		end
		if match:addPlayer(player) then
			playerMatch[player] = match
		else
			player:Kick("AETHER STRIKE — Ce serveur est réservé à un match en cours.")
		end
	end
	Players.PlayerAdded:Connect(function(player)
		task.spawn(admit, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(admit, player)
	end
end

function MatchService.Init()
	CombatService.setPhaseResolver(function(player: Player): boolean
		local match = playerMatch[player]
		return match ~= nil and match:isCombatLive()
	end)
	CombatService.setFirstBloodResolver(function(player: Player): boolean
		local match = playerMatch[player]
		return match ~= nil and match:isFirstBlood()
	end)
end

function MatchService.Start()
	ServerNet.onEvent("Interact", { capacity = 8, refill = 4 }, function(action: any): Types.InteractAction?
		local valid = Guard.oneOf({ "PlantStart", "PlantCancel", "DefuseStart", "DefuseCancel" })
		return if valid(action) then action :: Types.InteractAction else nil
	end, function(player: Player, action: Types.InteractAction)
		local match = playerMatch[player]
		if match then
			match:interact(player, action)
		end
	end)

	ServerNet.onEvent("LoadoutSelect", { capacity = 8, refill = 3 }, function(payload: any): { slot: Types.WeaponSlot, weapon: string }?
		local valid = Guard.shape({ slot = Guard.oneOf({ "Primary", "Secondary", "Melee" }), weapon = Guard.string(16) })
		return if valid(payload) then payload :: { slot: Types.WeaponSlot, weapon: string } else nil
	end, function(player: Player, payload: { slot: Types.WeaponSlot, weapon: string })
		local match = playerMatch[player]
		if match then
			match:selectLoadout(player, payload.slot, payload.weapon)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		local match = playerMatch[player]
		if match then
			match:removePlayer(player)
			playerMatch[player] = nil
		end
	end)

	RunService.Heartbeat:Connect(function()
		local now = Workspace:GetServerTimeNow()
		for _, match in matches do
			Logger.safe(log, "match update", match.update, match, now)
		end
	end)

	if ServerRole.isMatch() then
		task.spawn(startRemoteMatch)
	end
end

return MatchService
