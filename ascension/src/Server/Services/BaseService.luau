--!strict
--[[
	BaseService — la base de chaque joueur : parcelle, mannequin personnel, présentoir d'armes,
	emplacements de décor personnalisables.

	* 12 parcelles statiques construites une fois (sol, clôture, portail) ;
	* à l'arrivée d'un joueur : mannequin (au palier de sa meilleure zone), présentoir (ses 8 meilleures
	  armes en miniature), décor posé, panneau à son nom ;
	* à son départ : tout ce qui est dynamique est détruit, la parcelle redevient libre ;
	* personnalisation : PlaceDecor valide possession et emplacement (6, ou 12 avec le Game Pass).
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Builder = require(Shared.Assets.Builder)
local Props = require(Shared.Assets.Props)
local Spec = require(Shared.Assets.Spec)
local BaseLayout = require(Shared.Rules.BaseLayout)
local WeaponCatalog = require(Shared.Rules.WeaponCatalog)
local Decor = require(Shared.Config.Decor)
local GameEvents = require(script.Parent.Parent.GameEvents)
local PlayerService = require(script.Parent.PlayerService)
local DummyService = require(script.Parent.DummyService)

type State = PlayerService.State

local BaseService = {}

type Plot = {
	Index: number,
	CFrame: CFrame,
	Folder: Folder,
	Owner: Player?,
	Dynamic: Folder?,
	Dummy: DummyService.Dummy?,
	DecorModels: { [string]: Model },
	Sign: BasePart?,
}

local plots: { Plot } = {}
local byPlayer: { [Player]: Plot } = {}
local palette = Props.DefaultPalette
local RACK_DISPLAY = 8

---------------------------------------------------------------------------------------------
-- Construction statique
---------------------------------------------------------------------------------------------

local function cframeAt(plot: Plot, local_: Vector3, yaw: number?): CFrame
	return plot.CFrame * CFrame.new(local_) * CFrame.Angles(0, yaw or 0, 0)
end

local function buildStatic(index: number, parent: Instance): Plot
	local cframe = BaseLayout.plotCFrame(index, Vector3.zero)
	local folder = Instance.new("Folder")
	folder.Name = "Plot" .. index
	local plot: Plot = {
		Index = index,
		CFrame = cframe,
		Folder = folder,
		Owner = nil,
		Dynamic = nil,
		Dummy = nil,
		DecorModels = {},
		Sign = nil,
	}
	local size = BaseLayout.PlotSize
	local half = size / 2
	local specs: { Spec.Spec } = {}
	local function add(spec: Spec.Spec)
		spec.CFrame = cframe * spec.CFrame
		table.insert(specs, spec)
	end
	add(Spec.block(Vector3.new(size, 1, size), Vector3.new(0, 0, 0), Color3.fromRGB(120, 200, 110), {
		Name = "Floor",
		Material = Enum.Material.Grass,
		Collide = true,
		Shadow = false,
	}))
	add(Spec.block(Vector3.new(size + 2, 0.6, size + 2), Vector3.new(0, -0.4, 0), palette.Dark, {
		Name = "Frame",
		Material = Enum.Material.Wood,
		Collide = true,
		Shadow = false,
	}))
	-- Dalles de la zone d'entraînement + sentier vers l'entrée.
	add(Spec.cyl(0.15, 22, Vector3.new(0, 0.55, BaseLayout.Dummy.Z), palette.Primary, {
		Name = "TrainingPad",
		Material = Enum.Material.Cobblestone,
		Shadow = false,
	}))
	add(Spec.block(Vector3.new(6, 0.15, 24), Vector3.new(0, 0.55, -12), palette.Primary:Lerp(palette.Light, 0.2), {
		Name = "Path",
		Material = Enum.Material.Cobblestone,
		Shadow = false,
	}))
	-- Clôture : 4 côtés ; l'entrée (-Z) est ouverte au centre.
	local function rail(length: number, position: Vector3, yaw: number)
		add(Spec.block(Vector3.new(length, 0.35, 0.35), position + Vector3.new(0, 2.4, 0), palette.Secondary, {
			Name = "RailTop",
			Material = Enum.Material.Wood,
			Rot = CFrame.Angles(0, yaw, 0),
			Shadow = false,
		}))
		add(Spec.block(Vector3.new(length, 0.35, 0.35), position + Vector3.new(0, 1.2, 0), palette.Secondary, {
			Name = "RailLow",
			Material = Enum.Material.Wood,
			Rot = CFrame.Angles(0, yaw, 0),
			Shadow = false,
		}))
	end
	rail(size, Vector3.new(0, 0, half), 0) -- fond
	rail(size, Vector3.new(-half, 0, 0), math.pi / 2)
	rail(size, Vector3.new(half, 0, 0), math.pi / 2)
	rail(half - 4, Vector3.new(-(half + 4) / 2, 0, -half), 0) -- avant, deux segments
	rail(half - 4, Vector3.new((half + 4) / 2, 0, -half), 0)
	for i = 0, 7 do
		local t = -half + i * (size / 7)
		for _, post in
			{
				Vector3.new(t, 0, half),
				Vector3.new(-half, 0, t),
				Vector3.new(half, 0, t),
			}
		do
			add(Spec.block(Vector3.new(0.7, 3.3, 0.7), post + Vector3.new(0, 1.65, 0), palette.Primary, {
				Name = "Post",
				Material = Enum.Material.Wood,
				Shadow = false,
			}))
		end
		if math.abs(t) > 4 then
			add(Spec.block(Vector3.new(0.7, 3.3, 0.7), Vector3.new(t, 1.65, -half), palette.Primary, {
				Name = "Post",
				Material = Enum.Material.Wood,
				Shadow = false,
			}))
		end
	end
	for _, spec in specs do
		Builder.part(spec).Parent = folder
	end
	-- Portail d'entrée + éclairage.
	local gate = Builder.model("EntranceGate", Props.build("Gate", palette, 1))
	gate:ScaleTo(0.55)
	gate:PivotTo(cframeAt(plot, Vector3.new(0, 0.5, -half)))
	gate.Parent = folder
	for _, corner in { Vector3.new(-half + 2, 0.5, -half + 2), Vector3.new(half - 2, 0.5, -half + 2) } do
		local lamp = Builder.model("Lamp", Props.build("FloorLamp", palette, 1))
		lamp:PivotTo(cframeAt(plot, corner))
		lamp.Parent = folder
	end
	-- Établi d'armes (fixe) au fond.
	local rack = Builder.model("WeaponRack", Props.build("WeaponRack", palette, 1))
	rack:ScaleTo(1.3)
	rack:PivotTo(cframeAt(plot, BaseLayout.Rack + Vector3.new(0, 0.5, 4)))
	rack.Parent = folder
	folder.Parent = parent
	return plot
end

---------------------------------------------------------------------------------------------
-- Éléments dynamiques
---------------------------------------------------------------------------------------------

local function dynamicFolder(plot: Plot): Folder
	local existing = plot.Dynamic
	if existing then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "Dynamic"
	folder.Parent = plot.Folder
	plot.Dynamic = folder
	return folder
end

local function refreshSign(plot: Plot, state: State)
	local dynamic = dynamicFolder(plot)
	local old = dynamic:FindFirstChild("SignPost")
	if old then
		old:Destroy()
	end
	local anchor = Instance.new("Part")
	anchor.Name = "SignPost"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.CFrame = cframeAt(plot, BaseLayout.Rack + Vector3.new(0, 11, 4))
	anchor.Parent = dynamic
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(280, 64)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 140
	gui.LightInfluence = 0
	gui.Adornee = anchor
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 30)
	title.Font = Enum.Font.FredokaOne
	title.TextSize = 26
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextStrokeTransparency = 0.25
	title.Text = state.Player.DisplayName .. "'s Base"
	title.Parent = gui
	local sub = Instance.new("TextLabel")
	sub.BackgroundTransparency = 1
	sub.Position = UDim2.fromOffset(0, 30)
	sub.Size = UDim2.new(1, 0, 0, 22)
	sub.Font = Enum.Font.GothamMedium
	sub.TextSize = 16
	sub.TextColor3 = Color3.fromRGB(255, 214, 90)
	sub.TextStrokeTransparency = 0.3
	local stars = state.Profile.Stars
	sub.Text = ("Level %d%s"):format(
		state.Profile.Level,
		if stars > 0 then ("  ·  Ascension %d"):format(stars) else ""
	)
	sub.Parent = gui
	gui.Parent = anchor
	plot.Sign = anchor
end

function BaseService.refreshRack(state: State)
	local plot = byPlayer[state.Player]
	if not plot then
		return
	end
	local dynamic = dynamicFolder(plot)
	local old = dynamic:FindFirstChild("RackDisplay")
	if old then
		old:Destroy()
	end
	local display = Instance.new("Folder")
	display.Name = "RackDisplay"
	local owned: { WeaponCatalog.Weapon } = {}
	for _, weapon in WeaponCatalog.List do
		if state.Profile.Weapons[weapon.Id] then
			table.insert(owned, weapon)
		end
	end
	table.sort(owned, function(a, b)
		return a.Tier > b.Tier
	end)
	local base = cframeAt(plot, BaseLayout.Rack + Vector3.new(0, 0.5, 4))
	for i = 1, math.min(RACK_DISPLAY, #owned) do
		local weapon = owned[i]
		local model = Builder.weapon(weapon, { Fx = false, Anchored = true })
		local column = (i - 1) % 4
		local row = (i - 1) // 4
		model:ScaleTo(0.42)
		local offset = CFrame.new(-2.8 + column * 1.9, 2 + row * 1.75, -0.9) * CFrame.Angles(0, 0, math.rad(-8))
		model:PivotTo(base * offset)
		model.Parent = display
	end
	display.Parent = dynamic
end

function BaseService.refreshDecor(state: State)
	local plot = byPlayer[state.Player]
	if not plot then
		return
	end
	local dynamic = dynamicFolder(plot)
	local slots = state.Profile.Base.Slots
	local limit = BaseLayout.slotLimit(PlayerService.hasPass(state, "ExtraPlot"))
	-- Retire ce qui n'est plus placé ou a changé.
	for slotId, model in plot.DecorModels do
		if slots[slotId] == nil or model:GetAttribute("ItemId") ~= slots[slotId] then
			model:Destroy()
			plot.DecorModels[slotId] = nil
		end
	end
	for index, slot in BaseLayout.Slots do
		local itemId = slots[slot.Id]
		if itemId and index <= limit and not plot.DecorModels[slot.Id] then
			local item = Decor.ById[itemId]
			if item then
				local model = Builder.model(item.Name, Props.build(item.Recipe, palette, index))
				model:SetAttribute("ItemId", itemId)
				-- Les objets regardent l'entrée de la parcelle (-Z).
				model:PivotTo(cframeAt(plot, slot.Position + Vector3.new(0, 0.5, 0)))
				model.Parent = dynamic
				plot.DecorModels[slot.Id] = model
			end
		end
	end
end

function BaseService.refreshDummy(state: State)
	local plot = byPlayer[state.Player]
	if plot and plot.Dummy then
		DummyService.retier(plot.Dummy, PlayerService.bestZone(state))
	end
end

---------------------------------------------------------------------------------------------
-- Attribution
---------------------------------------------------------------------------------------------

function BaseService.assign(state: State): boolean
	local player = state.Player
	if byPlayer[player] then
		return true
	end
	for _, plot in plots do
		if plot.Owner == nil then
			plot.Owner = player
			byPlayer[player] = plot
			state.PlotIndex = plot.Index
			plot.Folder:SetAttribute("OwnerId", player.UserId)
			plot.Dummy = DummyService.create({
				Kind = "Base",
				ZoneIndex = PlayerService.bestZone(state),
				Pivot = plot.CFrame * CFrame.new(BaseLayout.Dummy + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, 0, 0),
				Owner = player,
			})
			refreshSign(plot, state)
			BaseService.refreshRack(state)
			BaseService.refreshDecor(state)
			return true
		end
	end
	return false
end

function BaseService.release(player: Player)
	local plot = byPlayer[player]
	if not plot then
		return
	end
	byPlayer[player] = nil
	plot.Owner = nil
	plot.Folder:SetAttribute("OwnerId", nil)
	if plot.Dummy then
		DummyService.remove(plot.Dummy)
		plot.Dummy = nil
	end
	if plot.Dynamic then
		plot.Dynamic:Destroy()
		plot.Dynamic = nil
	end
	plot.DecorModels = {}
	plot.Sign = nil
end

-- Point d'apparition dans la base du joueur (devant l'entrée, face au mannequin).
function BaseService.spawnCFrame(state: State): CFrame
	local plot = byPlayer[state.Player]
	if not plot then
		return CFrame.new(0, 6, 30)
	end
	return plot.CFrame * CFrame.new(BaseLayout.Spawn + Vector3.new(0, 4, 0))
end

function BaseService.start()
	local parent = Instance.new("Folder")
	parent.Name = "Bases"
	for index = 1, BaseLayout.Count do
		table.insert(plots, buildStatic(index, parent))
	end
	parent.Parent = workspace

	GameEvents.DecorChanged:Connect(BaseService.refreshDecor)
	GameEvents.WeaponAcquired:Connect(function(state)
		BaseService.refreshRack(state)
	end)
	GameEvents.ZoneUnlocked:Connect(BaseService.refreshDummy)
	GameEvents.Ascended:Connect(function(state)
		BaseService.refreshDummy(state)
		BaseService.refreshRack(state)
		local plot = byPlayer[state.Player]
		if plot then
			refreshSign(plot, state)
		end
	end)
	GameEvents.LevelUp:Connect(function(state)
		local plot = byPlayer[state.Player]
		if plot then
			refreshSign(plot, state)
		end
	end)
	Players.PlayerRemoving:Connect(BaseService.release)
end

return BaseService
