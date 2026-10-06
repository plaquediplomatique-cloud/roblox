--!strict
--[[
	HubWorld — habillage 3D client du QG (aucune réplication nécessaire).

	  * Vitrines de l'Armurerie : chaque socle (WeaponPedestal, attribut Slot) expose
	    une arme en lévitation, avec le skin ÉQUIPÉ par le joueur, rotation lente et
	    invite "INSPECTER" qui ouvre l'Armurerie sur cette arme.
	  * Mur de classement : SurfaceGui sur LeaderboardDisplay, top 10 de la saison,
	    mis à jour par le replica "Leaderboard".
	Compatible StreamingEnabled : tout est (ré)attaché via les signaux de tags.
]]

local CollectionService = game:GetService("CollectionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Weapons = require(Shared.Config.Weapons)
local Cosmetics = require(Shared.Config.Cosmetics)
local Ranks = require(Shared.Config.Ranks)
local Progression = require(Shared.Config.Progression)
local Theme = require(Shared.Config.Theme)
local ClientState = require(script.Parent.Parent.Core.ClientState)
local ReplicaController = require(script.Parent.Parent.Core.ReplicaController)
local WeaponModelBuilder = require(script.Parent.Parent.Weapons.WeaponModelBuilder)

local colors = Theme.colors
local fonts = Theme.fonts

local HubWorld = {}

type Display = {
	pedestal: BasePart,
	def: Types.WeaponDef,
	built: WeaponModelBuilder.BuiltWeapon?,
	skinId: string,
	phase: number,
}

local displays: { [BasePart]: Display } = {}
local inspectHandler: (weaponId: string) -> () = function(_weaponId: string) end

function HubWorld.onInspect(fn: (weaponId: string) -> ())
	inspectHandler = fn
end

local function skinFor(weaponId: string): Types.ItemDef
	local data = ClientState.profileData()
	return Cosmetics.resolveSkin(if data then data.Cosmetics.WeaponSkins else {}, weaponId)
end

local function rebuild(display: Display)
	local skin = skinFor(display.def.id)
	if display.built and display.skinId == skin.id then
		return
	end
	local old = display.built
	if old then
		old:destroy()
	end
	local built = WeaponModelBuilder.build(display.def, skin, 1.15)
	for _, part in built.parts do
		part.CastShadow = true
	end
	built.model.Parent = display.pedestal
	display.built = built
	display.skinId = skin.id
end

local function addPedestal(instance: Instance)
	if not instance:IsA("BasePart") or displays[instance] then
		return
	end
	local slot = instance:GetAttribute("Slot")
	local weaponId = if type(slot) == "number" then Weapons.order[slot] else nil
	local def = if weaponId then Weapons.get(weaponId) else nil
	if not def then
		return
	end
	local display: Display = { pedestal = instance, def = def, built = nil, skinId = "", phase = math.random() * 6 }
	displays[instance] = display
	rebuild(display)

	local label = Instance.new("BillboardGui")
	label.Name = "AS_Label"
	label.Size = UDim2.fromOffset(160, 44)
	label.StudsOffsetWorldSpace = Vector3.new(0, instance.Size.Y / 2 + 4.2, 0)
	label.MaxDistance = 60
	label.LightInfluence = 0
	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, 0, 0, 24)
	name.FontFace = fonts.heading
	name.TextSize = 20
	name.TextColor3 = colors.text
	name.TextStrokeTransparency = 0.6
	name.Text = def.shortName
	name.Parent = label
	local codename = Instance.new("TextLabel")
	codename.BackgroundTransparency = 1
	codename.Position = UDim2.fromOffset(0, 24)
	codename.Size = UDim2.new(1, 0, 0, 16)
	codename.FontFace = fonts.mono
	codename.TextSize = 12
	codename.TextColor3 = colors.primary
	codename.Text = def.codename
	codename.Parent = label
	label.Parent = instance

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "AS_Inspect"
	prompt.ActionText = "INSPECTER"
	prompt.ObjectText = def.shortName
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt:SetAttribute("InspectWeapon", def.id)
	prompt.Parent = instance

	instance.AncestryChanged:Connect(function()
		if not instance:IsDescendantOf(Workspace) then
			local current = displays[instance]
			if current and current.built then
				current.built:destroy()
			end
			displays[instance] = nil
		end
	end)
end

---------------------------------------------------------------------------------------------
-- Mur de classement
---------------------------------------------------------------------------------------------

local boards: { [BasePart]: Frame } = {}

local function renderBoard(list: Frame)
	for _, child in list:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	local replica = ReplicaController.get("Leaderboard")
	local entries = if replica then replica.data.entries else nil
	if type(entries) ~= "table" or #entries == 0 then
		local empty = Instance.new("TextLabel")
		empty.BackgroundTransparency = 1
		empty.Size = UDim2.new(1, 0, 0, 60)
		empty.FontFace = fonts.heading
		empty.TextSize = 40
		empty.TextColor3 = colors.textDim
		empty.Text = "SAISON EN COURS — AUCUN JOUEUR CLASSÉ"
		empty.Parent = list
		return
	end
	for index, entry in entries :: { any } do
		if index > 10 then
			break
		end
		local tier = Ranks.tierOf(tonumber(entry.rankIndex) or 0)
		local row = Instance.new("TextLabel")
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 64)
		row.FontFace = fonts.heading
		row.TextSize = 46
		row.RichText = true
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextColor3 = if index <= 3 then colors.gold else colors.text
		row.LayoutOrder = index
		row.Text = ('#%d   %s   <font color="#%s">%s %s · %d RR</font>'):format(
			index,
			tostring(entry.name),
			tier.color:ToHex(),
			tier.glyph,
			Ranks.displayName(tonumber(entry.rankIndex) or 0),
			tonumber(entry.rr) or 0
		)
		row.Parent = list
	end
end

local function addBoard(instance: Instance)
	if not instance:IsA("BasePart") or boards[instance] then
		return
	end
	local surface = Instance.new("SurfaceGui")
	surface.Name = "AS_Leaderboard"
	surface.Face = Enum.NormalId.Back
	surface.CanvasSize = Vector2.new(2400, 800)
	surface.LightInfluence = 0
	surface.Brightness = 1.6
	surface.Adornee = instance
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 110)
	title.FontFace = fonts.display
	title.TextSize = 72
	title.TextColor3 = colors.gold
	title.Text = "CLASSEMENT  ·  SAISON " .. Progression.PASS_SEASON
	title.Parent = surface
	local list = Instance.new("Frame")
	list.BackgroundTransparency = 1
	list.Position = UDim2.fromOffset(120, 130)
	list.Size = UDim2.new(1, -240, 1, -150)
	list.Parent = surface
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	surface.Parent = instance
	boards[instance] = list
	renderBoard(list)
end

function HubWorld.start()
	for _, instance in CollectionService:GetTagged("WeaponPedestal") do
		task.spawn(addPedestal, instance)
	end
	CollectionService:GetInstanceAddedSignal("WeaponPedestal"):Connect(addPedestal)
	for _, instance in CollectionService:GetTagged("LeaderboardDisplay") do
		addBoard(instance)
	end
	CollectionService:GetInstanceAddedSignal("LeaderboardDisplay"):Connect(addBoard)
	ReplicaController.onNew("Leaderboard", function(replica: ReplicaController.ClientReplica)
		local function redraw()
			for part, list in boards do
				if part.Parent then
					renderBoard(list)
				end
			end
		end
		replica.Changed:Connect(redraw)
		redraw()
	end)
	ClientState.ProfileReady:Connect(function(replica: ReplicaController.ClientReplica)
		replica:listen({ "Cosmetics", "WeaponSkins" }, function()
			for _, display in displays do
				rebuild(display)
			end
		end)
		for _, display in displays do
			rebuild(display)
		end
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		local weaponId = prompt:GetAttribute("InspectWeapon")
		if type(weaponId) == "string" then
			inspectHandler(weaponId)
		end
	end)
	RunService.RenderStepped:Connect(function()
		local camera = Workspace.CurrentCamera
		if not camera or ClientState.arena() ~= "Hub" then
			return
		end
		local now = os.clock()
		for pedestal, display in displays do
			local built = display.built
			if built and (pedestal.Position - camera.CFrame.Position).Magnitude < 110 then
				local top = pedestal.CFrame
					* CFrame.new(0, pedestal.Size.Y / 2 + 1.8 + math.sin(now * 1.3 + display.phase) * 0.12, 0)
				built.model:PivotTo(CFrame.new(top.Position) * CFrame.Angles(0, now * 0.5 + display.phase, math.rad(8)))
			end
		end
	end)
end

return HubWorld
