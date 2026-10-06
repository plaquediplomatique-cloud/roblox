--!strict
--[[
	Main — point d'entrée serveur de Smash Ascension. Ordre de démarrage explicite :
	remotes -> services de base -> monde -> systèmes de jeu -> joueurs.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Net = require(Shared.Net.Net)
local ZoneLayout = require(Shared.Rules.ZoneLayout)

local Services = script.Parent.Services

Net.init()

local DataService = require(Services.DataService)
local PlayerService = require(Services.PlayerService)
local CharacterService = require(Services.CharacterService)
local WeaponService = require(Services.WeaponService)
local DummyService = require(Services.DummyService)
local WorldService = require(Services.WorldService)
local BaseService = require(Services.BaseService)
local CombatService = require(Services.CombatService)
local ShopService = require(Services.ShopService)
local QuestService = require(Services.QuestService)
local BossService = require(Services.BossService)
local LeaderboardService = require(Services.LeaderboardService)
local MonetizationService = require(Services.MonetizationService)
local SessionService = require(Services.SessionService)

DataService.start()
PlayerService.start()
CharacterService.setSpawnProvider(BaseService.spawnCFrame)
CharacterService.start()
WeaponService.start()
DummyService.start()

WorldService.build(ShopService.interact)
BaseService.start()

-- Tableaux d'affichage des classements, face à la fontaine du village.
local boards = Instance.new("Folder")
boards.Name = "Leaderboards"
local center = ZoneLayout.center(1)
local layout = {
	{ Id = "Power", Title = "POWER", Offset = Vector3.new(-48, 0, -34) },
	{ Id = "Level", Title = "LEVEL", Offset = Vector3.new(-16, 0, -52) },
	{ Id = "BestCombo", Title = "BEST COMBO", Offset = Vector3.new(16, 0, -52) },
	{ Id = "Damage", Title = "BEST HIT", Offset = Vector3.new(48, 0, -34) },
}
for _, entry in layout do
	local position = center + entry.Offset
	LeaderboardService.buildBoard(entry.Id, entry.Title, WorldService.facing(position, center), boards)
end
boards.Parent = workspace

CombatService.start()
ShopService.start()
QuestService.start()
BossService.start()
LeaderboardService.start()
MonetizationService.start()
SessionService.start()
