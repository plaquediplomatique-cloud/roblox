--!strict
--[[
	Bootstrap serveur d'AETHER STRIKE.

	1. Net.setup() crée TOUS les remotes avant qu'un client puisse se connecter.
	2. Init() de chaque service, dans l'ordre des dépendances (aucun yield, aucune
	   interaction réseau : création d'état, branchements internes).
	3. Start() dans le même ordre (connexions d'événements, boucles, chargement du hub).
	Chaque étape est protégée : un service défaillant est journalisé avec sa pile
	d'appel sans empêcher les autres de démarrer.
]]

local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Net = require(Shared.Net.Net)
local Logger = require(Shared.Util.Logger)
local ServerRole = require(script.Parent.ServerRole)

local log = Logger.new("Boot")
local started = os.clock()

Net.setup()
Workspace:SetAttribute("ServerRole", ServerRole.get())

local Services = script.Parent.Services

type Service = { Init: () -> (), Start: () -> () }

local ORDER: { { name: string, service: Service } } = {
	{ name = "DataService", service = require(Services.DataService) :: any },
	{ name = "ReplicaService", service = require(Services.ReplicaService) :: any },
	{ name = "AntiCheatService", service = require(Services.AntiCheatService) :: any },
	{ name = "ArenaService", service = require(Services.ArenaService) :: any },
	{ name = "MapService", service = require(Services.MapService) :: any },
	{ name = "LagCompensationService", service = require(Services.LagCompensationService) :: any },
	{ name = "CharacterService", service = require(Services.CharacterService) :: any },
	{ name = "PlayerService", service = require(Services.PlayerService) :: any },
	{ name = "CombatService", service = require(Services.CombatService) :: any },
	{ name = "InventoryService", service = require(Services.InventoryService) :: any },
	{ name = "LeaderboardService", service = require(Services.LeaderboardService) :: any },
	{ name = "ProgressionService", service = require(Services.ProgressionService) :: any },
	{ name = "MissionService", service = require(Services.MissionService) :: any },
	{ name = "StoreService", service = require(Services.StoreService) :: any },
	{ name = "SettingsService", service = require(Services.SettingsService) :: any },
	{ name = "PurchaseService", service = require(Services.PurchaseService) :: any },
	{ name = "MatchService", service = require(Services.MatchService) :: any },
	{ name = "PartyService", service = require(Services.PartyService) :: any },
	{ name = "MatchmakingService", service = require(Services.MatchmakingService) :: any },
	{ name = "CustomGameService", service = require(Services.CustomGameService) :: any },
	{ name = "TrainingRangeService", service = require(Services.TrainingRangeService) :: any },
}

for _, entry in ORDER do
	Logger.safe(log, entry.name .. ".Init", entry.service.Init)
end
for _, entry in ORDER do
	Logger.safe(log, entry.name .. ".Start", entry.service.Start)
end

Workspace:SetAttribute("ServerReady", true)
log:info(("serveur prêt [%s] en %.0f ms — %d services"):format(ServerRole.get(), (os.clock() - started) * 1000, #ORDER))
