--!strict
--[[
	CharacterService — apparition des personnages (CharacterAutoLoads = false).

	* apparition dans la base du joueur, réapparition après une chute dans le vide ;
	* groupe de collision « Players » : les joueurs ne se bloquent ni ne se poussent
	  (foule autour des mannequins, pas de grief) ;
	* nettoyage : aucune connexion ne survit au personnage.
]]

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Janitor = require(Shared.Util.Janitor)
local PlayerService = require(script.Parent.PlayerService)

local CharacterService = {}

local GROUP = "Players"
local janitors: { [Player]: Janitor.Janitor } = {}

export type SpawnProvider = (state: PlayerService.State) -> CFrame
export type CharacterCallback = (state: PlayerService.State, character: Model) -> ()

local spawnProvider: SpawnProvider = function()
	return CFrame.new(0, 10, 0)
end
local onCharacter: { CharacterCallback } = {}

function CharacterService.setSpawnProvider(provider: SpawnProvider)
	spawnProvider = provider
end

-- Appelé à chaque apparition (arme, ambiance…).
function CharacterService.onCharacter(callback: CharacterCallback)
	table.insert(onCharacter, callback)
end

local function setCollisionGroup(character: Model)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = GROUP
		end
	end
end

local function setup(state: PlayerService.State, character: Model)
	local player = state.Player
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not humanoid or not root then
		return
	end
	character:PivotTo(spawnProvider(state))
	setCollisionGroup(character)
	local janitor = janitors[player]
	if janitor then
		janitor:Add(character.DescendantAdded:Connect(function(descendant)
			if descendant:IsA("BasePart") then
				descendant.CollisionGroup = GROUP
			end
		end))
		janitor:Add(humanoid.Died:Connect(function()
			task.delay(1.5, function()
				if player.Parent and PlayerService.get(player) then
					pcall(player.LoadCharacterAsync, player)
				end
			end)
		end))
	end
	for _, callback in onCharacter do
		task.spawn(callback, state, character)
	end
end

function CharacterService.spawn(state: PlayerService.State)
	local player = state.Player
	local old = janitors[player]
	if old then
		old:Cleanup()
	end
	janitors[player] = Janitor.new()
	task.spawn(function()
		pcall(player.LoadCharacterAsync, player)
	end)
end

function CharacterService.start()
	pcall(function()
		PhysicsService:RegisterCollisionGroup(GROUP)
	end)
	PhysicsService:CollisionGroupSetCollidable(GROUP, GROUP, false)

	local function track(player: Player)
		player.CharacterAdded:Connect(function(character)
			local state = PlayerService.get(player)
			if state then
				task.spawn(setup, state, character)
			end
		end)
	end
	Players.PlayerAdded:Connect(track)
	for _, player in Players:GetPlayers() do
		track(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local janitor = janitors[player]
		if janitor then
			janitor:Destroy()
			janitors[player] = nil
		end
	end)
end

return CharacterService
