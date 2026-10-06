--!strict
--[[
	PetService — inventaire en mémoire des pets d'un joueur et pets qui le suivent.

	* `add` enregistre le pet, met à jour l'attribut `Discovered` du joueur (lu par la
	  collection côté client) et fait apparaître le pet à ses côtés.
	* Les `maxFollowers` pets les plus récents suivent le joueur ; les autres restent en
	  collection. Les pets sont ancrés et déplacés ici (une boucle Heartbeat, ≤ 6×3 modèles).

	Les données ne sont PAS sauvegardées dans cette base (voir README : prochaine étape).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EggConfig = require(Shared.Config.Egg)
local Net = require(Shared.Net)
local PetFactory = require(Shared.PetFactory)
local Pets = require(Shared.Config.Pets)

type Follower = { model: Model, def: Pets.PetDef, slot: number, phase: number }

local FOLLOW_OFFSETS = { Vector3.new(-3.2, 0, 4), Vector3.new(3.2, 0, 4), Vector3.new(0, 0, 8) }
local GROUND_Y = 0.35

local owned: { [Player]: { [string]: number } } = {}
local followers: { [Player]: { Follower } } = {}
local folder: Folder

local PetService = {}

local function publishDiscovered(player: Player)
	local ids = {}
	for id in owned[player] do
		table.insert(ids, id)
	end
	table.sort(ids)
	player:SetAttribute(Net.discoveredAttribute, table.concat(ids, ","))
end

local function reslot(player: Player)
	local list: { Follower } = followers[player] or {}
	for index, follower in list do
		follower.slot = index
	end
end

-- Ajoute un pet (il apparaît à `origin`, là où l'œuf a éclos) ; renvoie vrai si c'est une
-- nouvelle découverte pour ce joueur.
function PetService.add(player: Player, petId: string, origin: Vector3): boolean
	local def = Pets.byId[petId]
	assert(def, "pet inconnu : " .. petId)
	local inventory = owned[player]
	if not inventory then
		return false -- le joueur est parti pendant l'éclosion
	end
	local isNew = inventory[petId] == nil
	inventory[petId] = (inventory[petId] or 0) + 1
	publishDiscovered(player)

	local list: { Follower } = followers[player] or {}
	followers[player] = list
	if #list >= EggConfig.maxFollowers then
		local oldest = table.remove(list, 1)
		if oldest then
			oldest.model:Destroy()
		end
	end
	local model = PetFactory.build(def)
	model:PivotTo(CFrame.new(origin))
	model.Parent = folder
	table.insert(list, { model = model, def = def, slot = #list + 1, phase = math.random() * 6.28 })
	reslot(player)
	return isNew
end

function PetService.playerAdded(player: Player)
	owned[player] = {}
	followers[player] = {}
end

function PetService.playerRemoving(player: Player)
	local list: { Follower } = followers[player] or {}
	for _, follower in list do
		follower.model:Destroy()
	end
	owned[player] = nil
	followers[player] = nil
end

function PetService.start()
	folder = Instance.new("Folder")
	folder.Name = "Pets"
	folder.Parent = workspace

	RunService.Heartbeat:Connect(function(dt)
		local alpha = 1 - math.exp(-dt * 7)
		local now = os.clock()
		for player, list in followers do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not (root and root:IsA("BasePart")) then
				continue
			end
			local rootCFrame = CFrame.new(root.Position)
				* CFrame.Angles(0, select(2, root.CFrame:ToEulerAnglesYXZ()), 0)
			for _, follower in list do
				local offset = FOLLOW_OFFSETS[follower.slot] or FOLLOW_OFFSETS[#FOLLOW_OFFSETS]
				local bob = math.abs(math.sin(now * 4 + follower.phase)) * 0.35
				local target = (rootCFrame * CFrame.new(offset)).Position
				local height = GROUND_Y + PetFactory.groundOffset(follower.def) + bob
				local current = follower.model:GetPivot().Position
				local flat = Vector3.new(
					current.X + (target.X - current.X) * alpha,
					height,
					current.Z + (target.Z - current.Z) * alpha
				)
				local lookTarget = Vector3.new(root.Position.X, height, root.Position.Z)
				if (lookTarget - flat).Magnitude > 0.5 then
					follower.model:PivotTo(CFrame.lookAt(flat, lookTarget))
				else
					follower.model:PivotTo(
						CFrame.new(flat) * (follower.model:GetPivot() - follower.model:GetPivot().Position)
					)
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		PetService.playerRemoving(player)
	end)
end

return PetService
