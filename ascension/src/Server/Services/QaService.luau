--!strict
--[[
	QaService — commandes de test par chat, UNIQUEMENT dans Roblox Studio (jamais en production :
	`RunService:IsStudio()` est vérifié à chaque commande, aucun remote n'est exposé).

	  /level N   /xp N   /coins N   /weapon <Id>   /unlockall   /boss   /reset   /day

	Permet de parcourir le jeu en quelques secondes pour valider les 10 zones, les armes
	spectaculaires, l'Ascension, le quotidien, etc. (skill roblox-testing).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage").Shared
local Zones = require(Shared.Config.Zones)
local Game = require(Shared.Config.Game)
local WeaponCatalog = require(Shared.Rules.WeaponCatalog)
local GameEvents = require(script.Parent.Parent.GameEvents)
local PlayerService = require(script.Parent.PlayerService)
local ProgressionService = require(script.Parent.ProgressionService)
local WeaponService = require(script.Parent.WeaponService)

local QaService = {}

type State = PlayerService.State

local commands: { [string]: (state: State, argument: string) -> () } = {
	level = function(state, argument)
		local target = math.clamp(math.floor(tonumber(argument) or 1), 1, Game.MaxLevel)
		local old = state.Profile.Level
		state.Profile.Level = target
		state.Profile.XP = 0
		PlayerService.mark(state, "Level", "XP")
		if target > old then
			GameEvents.LevelUp:Fire(state, old, target)
		end
	end,
	xp = function(state, argument)
		ProgressionService.addXP(state, tonumber(argument) or 0)
	end,
	coins = function(state, argument)
		ProgressionService.addCoins(state, tonumber(argument) or 0)
	end,
	weapon = function(state, argument)
		if WeaponCatalog.ById[argument] then
			WeaponService.grant(state, argument, "Chest")
			WeaponService.equip(state, argument)
		end
	end,
	unlockall = function(state)
		for _, zone in Zones.List do
			state.Profile.Zones[zone.Id] = true
			GameEvents.ZoneUnlocked:Fire(state, zone.Id)
		end
		PlayerService.mark(state, "Zones")
	end,
	day = function(state)
		state.Profile.Daily.LastClaim = 0
		state.Profile.Quests.Day = 0
		state.Profile.Quests.Week = 0
		PlayerService.mark(state, "Daily", "Quests")
	end,
}

local function onChatted(player: Player, message: string)
	if not RunService:IsStudio() then
		return
	end
	local name, argument = string.match(message, "^/(%w+)%s*(.*)$")
	if not name then
		return
	end
	local command = commands[string.lower(name)]
	local state = PlayerService.get(player)
	if command and state then
		command(state, argument or "")
	end
end

function QaService.start()
	if not RunService:IsStudio() then
		return
	end
	local function watch(player: Player)
		player.Chatted:Connect(function(message)
			onChatted(player, message)
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

return QaService
