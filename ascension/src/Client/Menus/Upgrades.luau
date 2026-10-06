--!strict
--[[
	Menu Améliorations — les « puits » de pièces permanents : Power, Speed, XP, Crit%, Crit dmg, Fortune.
	Prix et plafonds viennent des règles pures ; le serveur les revalide à l'achat.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Net = require(Shared.Net.Net)
local Theme = require(Shared.Config.Theme)
local UpgradeConfig = require(Shared.Config.Upgrades)
local Upgrades = require(Shared.Rules.Upgrades)
local NumberFormat = require(Shared.Rules.NumberFormat)
local Store = require(script.Parent.Parent.Core.Store)
local Sfx = require(script.Parent.Parent.Core.Sfx)
local UI = require(script.Parent.Parent.UI.UI)
local Menu = require(script.Parent.Parent.UI.Menu)

local C = Theme.Color

local Module: Menu.MenuModule = {
	Title = "Upgrades",
	Keys = { "Upgrades", "Coins" },
	build = function(content: Frame, _ctx: Menu.Context)
		local data = Store.Data
		local coins: number = data.Coins or 0
		UI.label({
			Text = "Coins: " .. UI.format(coins),
			TextSize = 20,
			TextColor3 = C.Coins,
			Size = UDim2.new(1, 0, 0, 28),
			Parent = content,
		})
		local column = Menu.column(UI.new("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, 32),
			Size = UDim2.new(1, 0, 1, -32),
			Parent = content,
		}))
		for i, upgrade in UpgradeConfig.List do
			local level: number = (data.Upgrades and data.Upgrades[upgrade.Id]) or 0
			local cost = Upgrades.cost(upgrade.Id, level)
			local row = Menu.row(column, i, 72)
			local badge = UI.new("Frame", {
				BackgroundColor3 = C.Accent,
				Position = UDim2.fromOffset(12, 12),
				Size = UDim2.fromOffset(48, 48),
				Parent = row,
			})
			UI.corner(UDim.new(0, 12)).Parent = badge
			UI.label({
				Text = upgrade.Icon,
				Font = Theme.Font.Display,
				TextSize = 28,
				TextXAlignment = Enum.TextXAlignment.Center,
				Size = UDim2.fromScale(1, 1),
				Parent = badge,
			})
			UI.label({
				Text = ("%s   %d / %d"):format(upgrade.Name, level, upgrade.Max),
				TextSize = 20,
				Position = UDim2.fromOffset(74, 8),
				Size = UDim2.new(1, -260, 0, 26),
				Parent = row,
			})
			UI.label({
				Text = ("%s  ·  now +%s"):format(
					upgrade.Desc,
					NumberFormat.percent(Upgrades.effect(upgrade.Id, level))
				),
				TextSize = 14,
				Font = Theme.Font.Body,
				TextColor3 = C.TextDim,
				Position = UDim2.fromOffset(74, 36),
				Size = UDim2.new(1, -260, 0, 24),
				TextTruncate = Enum.TextTruncate.AtEnd,
				Parent = row,
			})
			local button = UI.button({
				Text = if cost then ("BUY  " .. UI.format(cost)) else "MAX",
				Size = UDim2.fromOffset(170, 46),
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -12, 0.5, 0),
				Style = "good",
				Parent = row,
			}, function()
				Net.event("BuyUpgrade"):FireServer({ id = upgrade.Id })
				Sfx.play("UI_Buy")
			end)
			button:SetEnabled(cost ~= nil and coins >= cost)
		end
	end,
}

return Module
