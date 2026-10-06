--!strict
--[[
	DummyService — mannequins d'entraînement (base, terrain) et boss : PV, contributions,
	régénération et réapparition.

	Performance : aucun script ni boucle par mannequin. Un seul Heartbeat parcourt la liste
	des mannequins « actifs » (blessés ou à réapparaître) ; au repos, un mannequin ne coûte rien.
	L'état visible (HP, MaxHP, Alive) est publié en attributs : le client dessine les barres de
	vie et les animations d'effondrement sans aucun remote supplémentaire.
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage").Shared
local Builder = require(Shared.Assets.Builder)
local Dummies = require(Shared.Assets.Dummies)
local Game = require(Shared.Config.Game)
local Zones = require(Shared.Config.Zones)
local Curves = require(Shared.Rules.Curves)
local Signal = require(Shared.Util.Signal)

local DummyService = {}

export type Kind = "Base" | "Field" | "Boss"

export type Dummy = {
	Id: string,
	Kind: Kind,
	Model: Model,
	ZoneIndex: number,
	Scale: number,
	HP: number,
	MaxHP: number,
	Alive: boolean,
	Owner: Player?,
	Position: Vector3, -- point d'impact (centre du torse)
	Contribution: { [Player]: number },
	LastHit: number,
	RespawnAt: number,
	AutoRespawn: boolean,
	RegenDelay: number,
	Pivot: CFrame,
}

local dummies: { [string]: Dummy } = {}
local active: { [string]: boolean } = {} -- blessés / morts : seuls ceux-là sont parcourus
local counter = 0
local folder: Folder? = nil

-- Signaux internes (consommés par CombatService et BossService).
DummyService.Killed = Signal.new() :: Signal.Signal<Dummy, { [Player]: number }>
DummyService.Revived = Signal.new() :: Signal.Signal<Dummy>

local function root(): Folder
	if folder then
		return folder
	end
	local f = Instance.new("Folder")
	f.Name = "Dummies"
	f.Parent = workspace
	folder = f
	return f
end

local function publish(dummy: Dummy)
	local model = dummy.Model
	model:SetAttribute("HP", dummy.HP)
	model:SetAttribute("MaxHP", dummy.MaxHP)
	model:SetAttribute("Alive", dummy.Alive)
end

local function build(dummy: Dummy)
	local zone = Zones.List[dummy.ZoneIndex]
	local model = Builder.model(zone.DummyName, Dummies.build(zone, dummy.Scale))
	model:SetAttribute("DummyId", dummy.Id)
	model:SetAttribute("Kind", dummy.Kind)
	model:SetAttribute("ZoneIndex", dummy.ZoneIndex)
	model:SetAttribute("Scale", dummy.Scale)
	if dummy.Owner then
		model:SetAttribute("OwnerId", dummy.Owner.UserId)
	end
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- le client reçoit le mannequin entier (barre, effondrement)
	model:PivotTo(dummy.Pivot)
	CollectionService:AddTag(model, "Dummy")
	model.Parent = root()
	dummy.Model = model
	dummy.Position = dummy.Pivot.Position + Vector3.new(0, Dummies.HitHeight * dummy.Scale, 0)
end

export type Options = {
	Kind: Kind,
	ZoneIndex: number,
	Pivot: CFrame,
	Owner: Player?,
	Scale: number?,
	MaxHP: number?,
	AutoRespawn: boolean?,
	RegenDelay: number?,
}

function DummyService.create(options: Options): Dummy
	counter += 1
	local scale = options.Scale or 1
	local maxHP = options.MaxHP
		or (if options.Kind == "Boss" then Curves.bossHP(options.ZoneIndex) else Curves.dummyHP(options.ZoneIndex))
	local dummy: Dummy = {
		Id = "d" .. tostring(counter),
		Kind = options.Kind,
		Model = nil :: any,
		ZoneIndex = options.ZoneIndex,
		Scale = scale,
		HP = maxHP,
		MaxHP = maxHP,
		Alive = true,
		Owner = options.Owner,
		Position = options.Pivot.Position,
		Contribution = {},
		LastHit = 0,
		RespawnAt = 0,
		AutoRespawn = if options.AutoRespawn == nil then true else options.AutoRespawn,
		RegenDelay = options.RegenDelay or Game.DummyRegenDelay,
		Pivot = options.Pivot,
	}
	build(dummy)
	publish(dummy)
	dummies[dummy.Id] = dummy
	return dummy
end

function DummyService.get(id: string): Dummy?
	return dummies[id]
end

function DummyService.remove(dummy: Dummy)
	dummies[dummy.Id] = nil
	active[dummy.Id] = nil
	if dummy.Model then
		dummy.Model:Destroy()
	end
end

-- Change le palier d'un mannequin (base : nouvelle zone débloquée) : modèle et PV refaits.
function DummyService.retier(dummy: Dummy, zoneIndex: number)
	if dummy.ZoneIndex == zoneIndex then
		return
	end
	dummy.ZoneIndex = zoneIndex
	dummy.MaxHP = Curves.dummyHP(zoneIndex)
	dummy.HP = dummy.MaxHP
	dummy.Alive = true
	dummy.Contribution = {}
	dummy.Model:Destroy()
	build(dummy)
	publish(dummy)
	active[dummy.Id] = nil
end

function DummyService.setMaxHP(dummy: Dummy, maxHP: number)
	dummy.MaxHP = maxHP
	dummy.HP = maxHP
	dummy.Contribution = {}
	publish(dummy)
end

-- Fait (ré)apparaître un mannequin à plein de PV.
function DummyService.revive(dummy: Dummy)
	dummy.HP = dummy.MaxHP
	dummy.Alive = true
	dummy.Contribution = {}
	active[dummy.Id] = nil
	publish(dummy)
	DummyService.Revived:Fire(dummy)
end

-- Distance horizontale entre un point et le bord du mannequin.
local function edgeDistance(dummy: Dummy, position: Vector3): number
	local dx, dz = position.X - dummy.Position.X, position.Z - dummy.Position.Z
	return math.sqrt(dx * dx + dz * dz) - Dummies.Radius * dummy.Scale
end

-- Mannequin à frapper : l'indice du client est revérifié ; sinon le plus proche à portée.
-- `canHit` impose la politique d'accès (propriétaire de base, zone débloquée…).
function DummyService.pick(position: Vector3, reach: number, hintId: string?, canHit: (Dummy) -> boolean): Dummy?
	local function valid(dummy: Dummy): boolean
		return dummy.Alive
			and math.abs(position.Y - dummy.Position.Y) < 30 * dummy.Scale
			and edgeDistance(dummy, position) <= reach + (dummy.Scale - 1) * 2
			and canHit(dummy)
	end
	if hintId then
		local hinted = dummies[hintId]
		if hinted and valid(hinted) then
			return hinted
		end
	end
	local best: Dummy? = nil
	local bestDistance = math.huge
	for _, dummy in dummies do
		if valid(dummy) then
			local distance = edgeDistance(dummy, position)
			if distance < bestDistance then
				best, bestDistance = dummy, distance
			end
		end
	end
	return best
end

-- Inflige des dégâts. Renvoie (dégâts réellement infligés, mort ?).
function DummyService.damage(dummy: Dummy, attacker: Player, amount: number): (number, boolean)
	if not dummy.Alive or amount <= 0 then
		return 0, false
	end
	local dealt = math.min(amount, dummy.HP)
	dummy.HP -= dealt
	dummy.LastHit = os.clock()
	dummy.Contribution[attacker] = (dummy.Contribution[attacker] or 0) + dealt
	active[dummy.Id] = true
	if dummy.HP <= 0 then
		dummy.HP = 0
		dummy.Alive = false
		dummy.RespawnAt = os.clock() + Game.DummyRespawn
		publish(dummy)
		DummyService.Killed:Fire(dummy, dummy.Contribution)
		return dealt, true
	end
	dummy.Model:SetAttribute("HP", dummy.HP)
	return dealt, false
end

function DummyService.start()
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		for id in active do
			local dummy = dummies[id]
			if not dummy then
				active[id] = nil
			elseif not dummy.Alive then
				if dummy.AutoRespawn and now >= dummy.RespawnAt then
					DummyService.revive(dummy)
				end
			elseif now - dummy.LastHit >= dummy.RegenDelay then
				-- Plus attaqué : les PV remontent d'un coup (pas d'avantage à « finir plus tard »).
				dummy.HP = dummy.MaxHP
				dummy.Contribution = {}
				active[id] = nil
				publish(dummy)
			end
		end
	end)
end

DummyService.Radius = Dummies.Radius

return DummyService
