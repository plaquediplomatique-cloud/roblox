--!strict
--[[
	Hatchlings — point d'entrée serveur.

	Ordre : ambiance → île → services → joueurs. Chaque joueur reçoit un emplacement (plot
	d'apparition + nid) ; son premier œuf est déjà dans le nid, à côté de lui.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SlotAllocator = require(Shared.Rules.SlotAllocator)

local EggService = require(script.Parent.EggService)
local Environment = require(script.Parent.Environment)
local IslandBuilder = require(script.Parent.IslandBuilder)
local PetService = require(script.Parent.PetService)

Environment.apply()
local spots = IslandBuilder.build()
EggService.start()
PetService.start()

local taken: { [number]: Player } = {}
local assigned: { [Player]: number } = {}

local RESPAWN_DELAY = 2

local function spawnCharacter(player: Player)
	local index = assigned[player]
	if not index then
		return
	end
	player.CharacterAdded:Once(function(character)
		character:PivotTo(spots[index].spawnCFrame)
		local humanoid = character:WaitForChild("Humanoid", 5) :: Humanoid?
		if humanoid then
			humanoid.Died:Once(function()
				task.delay(RESPAWN_DELAY, function()
					if player.Parent then
						spawnCharacter(player)
					end
				end)
			end)
		end
	end)
	task.spawn(function()
		player:LoadCharacterAsync()
	end)
end

local function onPlayerAdded(player: Player)
	local index = SlotAllocator.acquire(taken, IslandBuilder.slotCount)
	if not index then
		player:Kick("This island is full — please join another server.")
		return
	end
	taken[index] = player
	assigned[player] = index
	PetService.playerAdded(player)
	EggService.give(player, spots[index].nestCFrame)
	spawnCharacter(player)
end

local function onPlayerRemoving(player: Player)
	local index = assigned[player]
	if index then
		taken[index] = nil
	end
	assigned[player] = nil
	EggService.remove(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end
