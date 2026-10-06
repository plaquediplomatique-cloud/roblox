--!strict
--[[
	Menu Base — personnalisation : acheter du décor, le poser sur les emplacements (6 gratuits, 12 avec
	le Game Pass « Grand Base »). Chaque objet posé donne +2 % de pièces (plafond +24 %).
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Net = require(Shared.Net.Net)
local Theme = require(Shared.Config.Theme)
local Decor = require(Shared.Config.Decor)
local BaseLayout = require(Shared.Rules.BaseLayout)
local Store = require(script.Parent.Parent.Core.Store)
local UI = require(script.Parent.Parent.UI.UI)
local Menu = require(script.Parent.Parent.UI.Menu)

local C = Theme.Color

local selectedSlot = "S1"

local Module: Menu.MenuModule = {
	Title = "My Base",
	Keys = { "Base", "Coins", "Level" },
	build = function(content: Frame, ctx: Menu.Context)
		local data = Store.Data
		local base = data.Base or { Owned = {}, Slots = {} }
		local level: number = data.Level or 1
		local coins: number = data.Coins or 0
		local limit = BaseLayout.slotLimit(Store.Passes.ExtraPlot == true)

		local placed = 0
		for _ in base.Slots do
			placed += 1
		end
		UI.label({
			Text = ("Decoration bonus: +%d%% coins  (%d placed)"):format(math.min(24, placed * 2), placed),
			TextSize = 18,
			TextColor3 = C.Good,
			Size = UDim2.new(1, 0, 0, 24),
			Parent = content,
		})

		-- Emplacements.
		local slots = UI.new("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, 28),
			Size = UDim2.new(1, 0, 0, 92),
			Parent = content,
		})
		UI.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(122, 42),
			CellPadding = UDim2.fromOffset(6, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = slots,
		})
		for i, slot in BaseLayout.Slots do
			local itemId = base.Slots[slot.Id]
			local locked = i > limit
			local text = if locked then "locked (pass)" else (if itemId then Decor.ById[itemId].Name else "empty")
			local button = UI.button({
				Text = ("%s  %s"):format(slot.Id, text),
				TextSize = 12,
				Size = UDim2.fromOffset(122, 42),
				Style = if slot.Id == selectedSlot then "primary" else "ghost",
				LayoutOrder = i,
				Parent = slots,
			}, function()
				selectedSlot = slot.Id
				ctx.Rebuild()
			end)
			button:SetEnabled(not locked)
		end

		-- Catalogue.
		local holder = UI.new("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, 126),
			Size = UDim2.new(1, 0, 1, -126),
			Parent = content,
		})
		local column = Menu.column(holder)
		Menu.action(
			column,
			0,
			"Clear " .. selectedSlot,
			"Remove the object from the selected slot.",
			"CLEAR",
			"ghost",
			function()
				Net.event("PlaceDecor"):FireServer({ slot = selectedSlot })
			end
		)
		for i, item in Decor.List do
			local owned = base.Owned[item.Id] == true
			local levelOk = level >= item.MinLevel
			local subtitle = if owned
				then item.Category .. "  ·  owned"
				else (
					levelOk and ("%s  ·  %s coins"):format(item.Category, UI.format(item.Cost))
					or ("Unlocks at level %d"):format(item.MinLevel)
				)
			local _, button = Menu.action(
				column,
				i,
				item.Name,
				subtitle,
				if owned then "PLACE" else "BUY",
				if owned then "primary" else "good",
				function()
					if owned then
						Net.event("PlaceDecor"):FireServer({ slot = selectedSlot, id = item.Id })
					else
						Net.event("BuyDecor"):FireServer({ id = item.Id })
					end
				end
			)
			button:SetEnabled(owned or (levelOk and coins >= item.Cost))
		end
	end,
}

return Module
