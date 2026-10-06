--[[
	ui_preview — construit une scène d'interface hors Studio et l'exporte en JSON.

	Les modules d'UI (Client/UI/UI, Client/UI/HudWidgets, Shared/Config/Theme) sont chargés
	avec de vraies instances (@lune/roblox) et des services simulés (tween, entrées,
	caméra) ; la scène est ensuite décrite propriété par propriété pour tools/render_ui.py.

	Usage : lune run tools/ui_preview.luau <scène> <sortie.json>
	Scènes : hud (combat en match), training (stand de tir), options (réglages rapides).
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Instance = roblox.Instance
local Enum = roblox.Enum

---------------------------------------------------------------------------------------------
-- Environnement simulé
---------------------------------------------------------------------------------------------

local fakeSignal = {
	Connect = function()
		return { Disconnect = function() end, Connected = true }
	end,
	Once = function()
		return { Disconnect = function() end, Connected = true }
	end,
}

local TweenInfoShim = {
	new = function(time, style, direction)
		return { Time = time or 1, EasingStyle = style, EasingDirection = direction }
	end,
}

local function makeNode(name, parent)
	local node = { Name = name, Parent = parent, _children = {}, _path = nil }
	return setmetatable(node, {
		__index = function(self, key)
			if key == "WaitForChild" or key == "FindFirstChild" then
				return function(this, child)
					return rawget(this, "_children")[child]
				end
			end
			local child = rawget(self, "_children")[key]
			if child == nil then
				error(("%s is not a valid member of %s"):format(tostring(key), rawget(self, "Name")), 2)
			end
			return child
		end,
	})
end

local function mount(directory, node)
	for _, entry in fs.readDir(directory) do
		local full = directory .. "/" .. entry
		if fs.isDir(full) then
			local child = makeNode(entry, node)
			rawget(node, "_children")[entry] = child
			mount(full, child)
		elseif string.sub(entry, -5) == ".luau" then
			local name = string.gsub(string.gsub(entry, "%.luau$", ""), "%.client$", "")
			rawget(node, "_children")[name] = makeNode(name, node)
			rawset(rawget(node, "_children")[name], "_path", full)
		end
	end
end

local replicatedStorage = makeNode("ReplicatedStorage", nil)
local shared = makeNode("Shared", replicatedStorage)
rawget(replicatedStorage, "_children").Shared = shared
mount("src/Shared", shared)
local client = makeNode("Client", nil)
mount("src/Client", client)

local camera = { ViewportSize = roblox.Vector2.new(1920, 1080), FieldOfView = 78 }
local services = {
	ReplicatedStorage = replicatedStorage,
	GuiService = {
		PreferredTransparency = 1,
		ReducedMotionEnabled = false,
		GetGuiInset = function()
			return roblox.Vector2.zero, roblox.Vector2.zero
		end,
	},
	-- Les animations sont appliquées immédiatement : l'aperçu montre l'état final.
	TweenService = {
		Create = function(_, instance, _info, goals)
			return {
				Play = function()
					for key, value in goals do
						instance[key] = value
					end
				end,
				Cancel = function() end,
				Completed = fakeSignal,
			}
		end,
	},
	UserInputService = {
		InputChanged = fakeSignal,
		InputEnded = fakeSignal,
		InputBegan = fakeSignal,
		TouchEnabled = false,
		KeyboardEnabled = true,
		GamepadEnabled = false,
	},
	Players = { LocalPlayer = { Name = "Preview", DisplayName = "Preview", UserId = 1 } },
	Workspace = { CurrentCamera = camera },
}

local game = {
	GetService = function(_, name)
		local service = services[name]
		if not service then
			error("service non simulé : " .. tostring(name))
		end
		return service
	end,
}

local loaded = {}
local requireNode

local taskShim = {
	delay = function(_, fn, ...)
		fn(...)
	end,
	defer = function() end,
	spawn = function() end,
	wait = function()
		return 0
	end,
}

local function environmentFor(node)
	return {
		script = node,
		require = requireNode,
		game = game,
		Instance = Instance,
		Enum = Enum,
		Color3 = roblox.Color3,
		ColorSequence = roblox.ColorSequence,
		ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		NumberRange = roblox.NumberRange,
		Font = roblox.Font,
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
		Vector2 = roblox.Vector2,
		Vector3 = roblox.Vector3,
		CFrame = roblox.CFrame,
		Rect = roblox.Rect,
		TweenInfo = TweenInfoShim,
		task = taskShim,
		warn = function(...)
			print("[warn]", ...)
		end,
	}
end

function requireNode(node)
	local cached = loaded[node]
	if cached ~= nil then
		return cached
	end
	local path = rawget(node, "_path")
	assert(path, "pas un module : " .. tostring(rawget(node, "Name")))
	local chunk = luau.load(fs.readFile(path), { debugName = path, environment = environmentFor(node) })
	local result = chunk()
	loaded[node] = result
	return result
end

local UI = requireNode(client.UI.UI)
local HudWidgets = requireNode(client.UI.HudWidgets)
local Theme = requireNode(shared.Config.Theme)
local colors = Theme.colors

---------------------------------------------------------------------------------------------
-- Scènes
---------------------------------------------------------------------------------------------

local function screen()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Preview"
	return gui
end

local function crosshair(parent)
	local holder = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = roblox.Vector2.new(0.5, 0.5),
		Position = roblox.UDim2.fromScale(0.5, 0.5),
		Size = roblox.UDim2.fromOffset(0, 0),
		ZIndex = 20,
		Parent = parent,
	})
	local color = roblox.Color3.fromRGB(61, 225, 255)
	for _, spec in
		{
			{ 0, -10, 2, 6 },
			{ 0, 10, 2, 6 },
			{ -10, 0, 6, 2 },
			{ 10, 0, 6, 2 },
		}
	do
		local line = UI.frame({
			AnchorPoint = roblox.Vector2.new(0.5, 0.5),
			Position = roblox.UDim2.fromOffset(spec[1], spec[2]),
			Size = roblox.UDim2.fromOffset(spec[3], spec[4]),
			BackgroundColor3 = color,
			ZIndex = 20,
			Parent = holder,
		})
		UI.stroke(line, roblox.Color3.new(0, 0, 0), 1, 0.5)
	end
end

local function hudScene()
	local gui = screen()
	local safe =
		UI.frame({ Name = "Safe", BackgroundTransparency = 1, Size = roblox.UDim2.fromScale(1, 1), Parent = gui })
	local vitals = HudWidgets.vitals(safe)
	vitals.health.Text = "76"
	vitals.armor.Text = "25"
	vitals.healthBar.set(76, 100)
	vitals.armorBar.set(25, 50)

	local ammo = HudWidgets.ammo(safe)
	ammo.weaponName.Text = "VK-12 VEKTOR"
	ammo.fireMode.Text = "AUTO"
	ammo.mag.Text = "23"
	ammo.reserve.Text = "/ 90"
	HudWidgets.renderPips(ammo.pips, 23, 30)
	ammo.slots.Primary.Text = "1  VK-12"
	HudWidgets.styleSlot(ammo.slots.Primary, true)
	ammo.slots.Secondary.Text = "2  P-10"
	ammo.slots.Melee.Text = "3  LAME"

	local bar = HudWidgets.matchBar(gui)
	bar.timer.Text = "1:24"
	bar.round.Text = "MANCHE 7"
	bar.scoreLeft.Text = "4"
	bar.scoreRight.Text = "2"
	bar.sideLeft.Text = "ONYX"
	bar.sideLeft.TextColor3 = colors.ally
	bar.sideRight.Text = "HALO"
	bar.sideRight.TextColor3 = colors.enemy
	HudWidgets.renderAlive(bar.pipsLeft, 3, 3, colors.ally)
	HudWidgets.renderAlive(bar.pipsRight, 1, 3, colors.enemy)

	local feed = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = roblox.Vector2.new(1, 0),
		Position = roblox.UDim2.new(1, -24, 0, 62),
		Size = roblox.UDim2.fromOffset(460, 200),
		Parent = safe,
	})
	UI.list(feed, Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Right)
	local function feedText(killer, killerColor, weapon, victim, victimColor)
		return ('<font color="#%s"><b>%s</b></font>   <font color="#%s">%s</font>   <font color="#%s"><b>%s</b></font>'):format(
			killerColor:ToHex(),
			killer,
			colors.textDim:ToHex(),
			weapon,
			victimColor:ToHex(),
			victim
		)
	end
	HudWidgets.killfeedEntry(
		feed,
		feedText("Preview", colors.ally, "VK-12  ·  TÊTE", "Vortex_77", colors.enemy),
		colors.primary
	).LayoutOrder =
		1
	HudWidgets.killfeedEntry(feed, feedText("NovaRay", colors.enemy, "RS-1", "Kaito", colors.ally), nil).LayoutOrder = 2

	crosshair(gui)
	local interaction = HudWidgets.interaction(gui)
	interaction.root.Visible = true
	interaction.text.Text = "Maintenir pour armer l'uplink"
	interaction.fill.Size = roblox.UDim2.fromScale(0.45, 1)

	local confirm = HudWidgets.killConfirm(gui)
	confirm.text.TextTransparency = 0
	confirm.text.Text = ('<font color="#%s">DOUBLÉ</font>   ÉLIMINÉ  ·  VORTEX_77  ·  TÊTE'):format(
		colors.gold:ToHex()
	)
	HudWidgets.killPip(confirm.pips, 1, colors.primary)
	HudWidgets.killPip(confirm.pips, 2, colors.primary)

	local toasts = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = roblox.Vector2.new(1, 0.5),
		Position = roblox.UDim2.new(1, -24, 0.42, 0),
		Size = roblox.UDim2.fromOffset(340, 400),
		Parent = gui,
	})
	UI.list(toasts, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Bottom)
	HudWidgets.toast(toasts, "MISSION ACCOMPLIE", "3 éliminations au fusil d'assaut  ·  +250 XP", colors.success)
	return gui
end

local function trainingScene()
	local gui = screen()
	local safe =
		UI.frame({ Name = "Safe", BackgroundTransparency = 1, Size = roblox.UDim2.fromScale(1, 1), Parent = gui })
	local vitals = HudWidgets.vitals(safe)
	vitals.healthBar.set(100, 100)
	vitals.armorBar.set(50, 50)
	local ammo = HudWidgets.ammo(safe)
	ammo.weaponName.Text = "HMG-40 BASTION"
	ammo.mag.Text = "71"
	ammo.reserve.Text = "/ ∞"
	HudWidgets.renderPips(ammo.pips, 71, 100)
	ammo.slots.Primary.Text = "1  HMG-40"
	HudWidgets.styleSlot(ammo.slots.Primary, true)
	ammo.slots.Secondary.Text = "2  R-44"
	ammo.slots.Melee.Text = "3  LAME"
	local stats = HudWidgets.statPanel(safe, "STAND DE TIR", colors.success, {
		{ "Shots", "Tirs" },
		{ "Accuracy", "Précision" },
		{ "Head", "Tête" },
		{ "Damage", "Dégâts" },
		{ "Kills", "Éliminations" },
	})
	stats.values.Shots.Text = "214"
	stats.values.Accuracy.Text = "38 %"
	stats.values.Head.Text = "21 %"
	stats.values.Damage.Text = "4 870"
	stats.values.Kills.Text = "17"
	crosshair(gui)
	local banner = HudWidgets.banner(gui)
	banner.title.Text = "MANCHE GAGNÉE"
	banner.title.TextTransparency = 0
	banner.title.TextColor3 = colors.primary
	banner.subtitle.Text = "Uplink désamorcé  ·  4 – 2"
	banner.subtitle.TextTransparency = 0
	banner.line.BackgroundTransparency = 0
	banner.line.BackgroundColor3 = colors.primary
	banner.line.Size = roblox.UDim2.fromOffset(520, 2)
	return gui
end

---------------------------------------------------------------------------------------------
-- Export
---------------------------------------------------------------------------------------------

local function rgb(color)
	return { color.R, color.G, color.B }
end

local function udim2(value)
	return { value.X.Scale, value.X.Offset, value.Y.Scale, value.Y.Offset }
end

local function udim(value)
	return { value.Scale, value.Offset }
end

local function enumName(item)
	return item.Name
end

local function export(instance)
	local class = instance.ClassName
	local node = { class = class, name = instance.Name, children = {} }
	if instance:IsA("GuiObject") then
		node.size = udim2(instance.Size)
		node.pos = udim2(instance.Position)
		node.anchor = { instance.AnchorPoint.X, instance.AnchorPoint.Y }
		node.rot = instance.Rotation
		node.bg = rgb(instance.BackgroundColor3)
		node.bgT = instance.BackgroundTransparency
		node.visible = instance.Visible
		node.z = instance.ZIndex
		node.order = instance.LayoutOrder
		node.clip = instance.ClipsDescendants
		node.autoSize = enumName(instance.AutomaticSize)
		if instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
			node.text = instance.Text
			node.textSize = instance.TextSize
			node.font = { family = instance.FontFace.Family, weight = enumName(instance.FontFace.Weight) }
			node.textColor = rgb(instance.TextColor3)
			node.textT = instance.TextTransparency
			node.xAlign = enumName(instance.TextXAlignment)
			node.yAlign = enumName(instance.TextYAlignment)
			node.wrapped = instance.TextWrapped
			node.rich = instance.RichText
			node.truncate = enumName(instance.TextTruncate)
		end
	elseif class == "UICorner" then
		node.radius = udim(instance.CornerRadius)
	elseif class == "UIStroke" then
		node.color = rgb(instance.Color)
		node.thickness = instance.Thickness
		node.t = instance.Transparency
		node.mode = enumName(instance.ApplyStrokeMode)
		node.enabled = instance.Enabled
	elseif class == "UIGradient" then
		local colorKeys = {}
		for _, key in instance.Color.Keypoints do
			table.insert(colorKeys, { key.Time, key.Value.R, key.Value.G, key.Value.B })
		end
		local transparencyKeys = {}
		for _, key in instance.Transparency.Keypoints do
			table.insert(transparencyKeys, { key.Time, key.Value })
		end
		node.colors = colorKeys
		node.transparency = transparencyKeys
		node.rotation = instance.Rotation
		node.offset = { instance.Offset.X, instance.Offset.Y }
		node.enabled = instance.Enabled
	elseif class == "UIPadding" then
		node.padding = {
			udim(instance.PaddingLeft),
			udim(instance.PaddingRight),
			udim(instance.PaddingTop),
			udim(instance.PaddingBottom),
		}
	elseif class == "UIListLayout" then
		node.direction = enumName(instance.FillDirection)
		node.padding = udim(instance.Padding)
		node.h = enumName(instance.HorizontalAlignment)
		node.v = enumName(instance.VerticalAlignment)
		node.sort = enumName(instance.SortOrder)
	elseif class == "UIScale" then
		node.scale = instance.Scale
	end
	for _, child in instance:GetChildren() do
		table.insert(node.children, export(child))
	end
	return node
end

local scenes = { hud = hudScene, training = trainingScene }
local args = process.args
local sceneName = args[1] or "hud"
local output = args[2] or "ui_preview.json"
local build = scenes[sceneName]
if not build then
	error("scène inconnue : " .. sceneName)
end
local root = build()
fs.writeFile(output, serde.encode("json", { width = 1920, height = 1080, root = export(root) }))
print("écrit : " .. output)
