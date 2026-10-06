--!strict
--[[
	DummyView — présentation des mannequins : barres de vie, réaction aux coups, effondrement et
	réapparition. Tout est piloté par les ATTRIBUTS publiés par le serveur (HP, MaxHP, Alive) :
	aucun remote, et le streaming de Workspace est géré par les signaux de tag.

	Une seule boucle Heartbeat, active uniquement tant qu'un mannequin bouge.
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage").Shared
local Janitor = require(Shared.Util.Janitor)
local Signal = require(Shared.Util.Signal)
local Spring = require(Shared.Util.Spring)
local NumberFormat = require(Shared.Rules.NumberFormat)
local Theme = require(Shared.Config.Theme)
local UI = require(script.Parent.Parent.UI.UI)

local DummyView = {}

type View = {
	Model: Model,
	Id: string,
	Kind: string,
	Scale: number,
	BasePivot: CFrame,
	Tilt: Spring.NumberSpring,
	TiltAxis: Vector3,
	Janitor: Janitor.Janitor,
	Bar: Frame?,
	Fill: Frame?,
	Gui: BillboardGui?,
	Label: TextLabel?,
	Transparencies: { [BasePart]: number },
	Alive: boolean,
	CollapseT: number,
}

local views: { [Model]: View } = {}
local byId: { [string]: View } = {}
local moving: { [Model]: boolean } = {}
local loop: RBXScriptConnection? = nil

DummyView.BossSeen = Signal.new() :: Signal.Signal<Model?>

local function head(view: View): BasePart?
	return view.Model:FindFirstChild("Head") :: BasePart?
end

local function buildBar(view: View)
	local anchor = head(view)
	if not anchor then
		return
	end
	local isBoss = view.Kind == "Boss"
	local gui = UI.new("BillboardGui", {
		Name = "HealthBar",
		Adornee = anchor,
		Size = UDim2.fromOffset(if isBoss then 260 else 130, if isBoss then 34 else 22),
		StudsOffset = Vector3.new(0, 2.4 * view.Scale, 0),
		AlwaysOnTop = false,
		MaxDistance = if isBoss then 200 else 70,
		LightInfluence = 0,
		Enabled = false,
	})
	local bar = UI.new("Frame", {
		BackgroundColor3 = Theme.Color.Ink,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = gui,
	})
	UI.corner(UDim.new(0, 8)).Parent = bar
	UI.stroke(Color3.new(1, 1, 1), 1.5, 0.35).Parent = bar
	local fill = UI.new("Frame", {
		BackgroundColor3 = if isBoss then Theme.Color.Bad else Theme.Color.Good,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = bar,
	})
	UI.corner(UDim.new(0, 8)).Parent = fill
	local label = UI.label({
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = if isBoss then 18 else 13,
		Text = "",
		TextStrokeTransparency = 0.4,
		ZIndex = 3,
		Parent = bar,
	})
	gui.Parent = anchor
	view.Gui = gui
	view.Bar = bar
	view.Fill = fill
	view.Label = label
end

local function refreshBar(view: View)
	local gui, fill, label = view.Gui, view.Fill, view.Label
	if not gui or not fill or not label then
		return
	end
	local hp = view.Model:GetAttribute("HP")
	local maxHP = view.Model:GetAttribute("MaxHP")
	local alive = view.Model:GetAttribute("Alive")
	if type(hp) ~= "number" or type(maxHP) ~= "number" or maxHP <= 0 then
		return
	end
	local fraction = math.clamp(hp / maxHP, 0, 1)
	-- Barre visible seulement quand le mannequin est blessé (boss : toujours).
	gui.Enabled = alive == true and (fraction < 0.999 or view.Kind == "Boss")
	UI.tween(fill, { Size = UDim2.fromScale(fraction, 1) }, 0.15)
	label.Text = if view.Kind == "Boss"
		then ("%s  %s / %s"):format(view.Model.Name, NumberFormat.compact(hp), NumberFormat.compact(maxHP))
		else NumberFormat.compact(hp)
end

local function stopLoopIfIdle()
	if next(moving) == nil and loop then
		loop:Disconnect()
		loop = nil
	end
end

local function applyTilt(view: View, angle: number)
	local axis = view.TiltAxis
	view.Model:PivotTo(view.BasePivot * CFrame.fromAxisAngle(axis, angle))
end

local function step(dt: number)
	for model in moving do
		local view = views[model]
		if not view or not model.Parent then
			moving[model] = nil
		elseif view.CollapseT > 0 then
			-- Effondrement : bascule puis fondu.
			view.CollapseT = math.max(0, view.CollapseT - dt)
			local t = 1 - view.CollapseT / 0.55
			applyTilt(view, math.rad(82) * math.min(1, t * 2.2))
			local fade = math.clamp((t - 0.45) / 0.55, 0, 1)
			for part, original in view.Transparencies do
				part.Transparency = original + (1 - original) * fade
			end
			if view.CollapseT <= 0 then
				moving[model] = nil
			end
		else
			local angle = view.Tilt:step(dt)
			applyTilt(view, angle)
			if math.abs(angle) < 0.002 and math.abs(view.Tilt.velocity) < 0.01 then
				applyTilt(view, 0)
				moving[model] = nil
			end
		end
	end
	stopLoopIfIdle()
end

local function wake(view: View)
	moving[view.Model] = true
	if not loop then
		loop = RunService.Heartbeat:Connect(step)
	end
end

local function onAlive(view: View)
	local alive = view.Model:GetAttribute("Alive") == true
	if alive == view.Alive then
		return
	end
	view.Alive = alive
	if alive then
		-- Réapparition : on remet tout en place avec un petit rebond.
		for part, original in view.Transparencies do
			part.Transparency = original
		end
		view.CollapseT = 0
		view.Tilt:snap(0)
		view.Model:PivotTo(view.BasePivot)
		view.Tilt.velocity = 0
		view.Tilt:impulse(-6)
		wake(view)
	else
		view.CollapseT = 0.55
		if view.Gui then
			view.Gui.Enabled = false
		end
		wake(view)
	end
end

local function add(model: Model)
	if views[model] then
		return
	end
	local id = model:GetAttribute("DummyId")
	if type(id) ~= "string" then
		return
	end
	local transparencies: { [BasePart]: number } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			transparencies[descendant] = descendant.Transparency
		end
	end
	local scale = model:GetAttribute("Scale")
	local kind = model:GetAttribute("Kind")
	local view: View = {
		Model = model,
		Id = id,
		Kind = if type(kind) == "string" then kind else "Field",
		Scale = if type(scale) == "number" then scale else 1,
		BasePivot = model:GetPivot(),
		Tilt = Spring.number(0, 22, 0.28),
		TiltAxis = Vector3.xAxis,
		Janitor = Janitor.new(),
		Bar = nil,
		Fill = nil,
		Gui = nil,
		Label = nil,
		Transparencies = transparencies,
		Alive = model:GetAttribute("Alive") ~= false,
		CollapseT = 0,
	}
	views[model] = view
	byId[id] = view
	buildBar(view)
	refreshBar(view)
	view.Janitor:Add(model:GetAttributeChangedSignal("HP"):Connect(function()
		refreshBar(view)
	end))
	view.Janitor:Add(model:GetAttributeChangedSignal("MaxHP"):Connect(function()
		refreshBar(view)
	end))
	view.Janitor:Add(model:GetAttributeChangedSignal("Alive"):Connect(function()
		onAlive(view)
		refreshBar(view)
	end))
	if view.Kind == "Boss" then
		DummyView.BossSeen:Fire(model)
	end
end

local function remove(model: Model)
	local view = views[model]
	if not view then
		return
	end
	views[model] = nil
	byId[view.Id] = nil
	moving[model] = nil
	view.Janitor:Destroy()
	if view.Kind == "Boss" then
		DummyView.BossSeen:Fire(nil)
	end
end

function DummyView.find(id: string): Model?
	local view = byId[id]
	return if view then view.Model else nil
end

-- Mannequin vivant le plus proche (indice de ciblage envoyé au serveur, revérifié là-bas).
function DummyView.nearest(position: Vector3, maxDistance: number, localUserId: number): (Model?, number)
	local best: Model? = nil
	local bestDistance = maxDistance
	for model, view in views do
		if view.Alive and (view.Kind ~= "Base" or model:GetAttribute("OwnerId") == localUserId) then
			local pivot = view.BasePivot.Position
			local flat = Vector3.new(position.X - pivot.X, 0, position.Z - pivot.Z).Magnitude - 2.2 * view.Scale
			if flat < bestDistance and math.abs(position.Y - pivot.Y) < 30 * view.Scale then
				best, bestDistance = model, flat
			end
		end
	end
	return best, bestDistance
end

-- Réaction à un coup : bascule vers l'avant, proportionnelle à la force du coup.
function DummyView.react(model: Model, from: Vector3, strength: number)
	local view = views[model]
	if not view or not view.Alive then
		return
	end
	local flat = Vector3.new(view.BasePivot.Position.X - from.X, 0, view.BasePivot.Position.Z - from.Z)
	local direction = if flat.Magnitude > 0.01 then flat.Unit else Vector3.zAxis
	view.TiltAxis = Vector3.yAxis:Cross(direction)
	view.Tilt:impulse(math.clamp(strength, 0.2, 3) * 5)
	wake(view)
end

function DummyView.start()
	for _, model in CollectionService:GetTagged("Dummy") do
		if model:IsA("Model") then
			add(model)
		end
	end
	CollectionService:GetInstanceAddedSignal("Dummy"):Connect(function(instance)
		if instance:IsA("Model") then
			task.defer(add, instance)
		end
	end)
	CollectionService:GetInstanceRemovedSignal("Dummy"):Connect(function(instance)
		if instance:IsA("Model") then
			remove(instance)
		end
	end)
end

return DummyView
