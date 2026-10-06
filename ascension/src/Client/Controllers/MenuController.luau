--!strict
--[[
	MenuController — fenêtre modale unique qui héberge tous les menus (Weapons, Upgrades, Zones,
	Quests, Base, Shop, Ranks, Settings). Un seul menu ouvert à la fois ; l'attaque est suspendue
	pendant ce temps ; le contenu se reconstruit (avec debounce) quand les données du Store changent.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage").Shared
local Theme = require(Shared.Config.Theme)
local Store = require(script.Parent.Parent.Core.Store)
local UI = require(script.Parent.Parent.UI.UI)
local Menu = require(script.Parent.Parent.UI.Menu)
local Hud = require(script.Parent.Hud)
local InputController = require(script.Parent.InputController)

local MenuController = {}

local modules: { [string]: Menu.MenuModule } = {}
local current: string? = nil
local gui: ScreenGui
local window: Frame
local titleLabel: TextLabel
local content: Frame
local rebuildQueued = false

local function build()
	local id = current
	if not id then
		return
	end
	local module = modules[id]
	UI.clear(content)
	local context: Menu.Context = {
		Close = MenuController.close,
		Rebuild = function()
			MenuController.refresh()
		end,
		Root = content,
	}
	module.build(content, context)
end

function MenuController.refresh()
	if not current or rebuildQueued then
		return
	end
	rebuildQueued = true
	task.delay(0.12, function()
		rebuildQueued = false
		build()
	end)
end

function MenuController.close()
	if not current then
		return
	end
	current = nil
	UI.tween(window, { Position = UDim2.fromScale(0.5, 0.52) }, 0.15)
	window.Visible = false
	InputController.setEnabled(true)
end

function MenuController.open(id: string)
	local module = modules[id]
	if not module then
		return
	end
	current = id
	titleLabel.Text = module.Title
	window.Visible = true
	window.Position = UDim2.fromScale(0.5, 0.5)
	UI.pop(window, 0.92)
	InputController.setEnabled(false)
	build()
end

function MenuController.toggle(id: string)
	if current == id then
		MenuController.close()
	else
		MenuController.open(id)
	end
end

function MenuController.register(id: string, module: Menu.MenuModule)
	modules[id] = module
end

function MenuController.start()
	gui = UI.screen("Menus", Players.LocalPlayer:WaitForChild("PlayerGui"), 5)
	window = UI.panel({
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(820, 520),
		BackgroundTransparency = 0.02,
		Visible = false,
		Active = true,
		Parent = gui,
	})
	UI.new("UISizeConstraint", { MaxSize = Vector2.new(900, 600), Parent = window })
	titleLabel = UI.label({
		Text = "",
		Font = Theme.Font.Display,
		TextSize = 32,
		Position = UDim2.fromOffset(20, 10),
		Size = UDim2.new(1, -120, 0, 44),
		Parent = window,
	})
	UI.button({
		Text = "X",
		Size = UDim2.fromOffset(46, 40),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 12),
		Style = "bad",
		Parent = window,
	}, MenuController.close)
	content = UI.new("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 62),
		Size = UDim2.new(1, -32, 1, -78),
		Parent = window,
	})

	local menus = script.Parent.Parent.Menus
	MenuController.register("Weapons", require(menus.Weapons))
	MenuController.register("Upgrades", require(menus.Upgrades))
	MenuController.register("Zones", require(menus.Zones))
	MenuController.register("Quests", require(menus.Quests))
	MenuController.register("Base", require(menus.Base))
	MenuController.register("Shop", require(menus.Shop))
	MenuController.register("Ranks", require(menus.Ranks))
	MenuController.register("Settings", require(menus.Settings))

	Hud.MenuRequested:Connect(MenuController.toggle)
	Store.Changed:Connect(function(key)
		local id = current
		if id and table.find(modules[id].Keys, key) then
			MenuController.refresh()
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.Escape and current then
			MenuController.close()
		end
	end)
end

return MenuController
