--!strict
--[[
	Menu Zones — les 10 royaumes : déblocage (niveau + péage) et téléportation. Retour à la base.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Net = require(Shared.Net.Net)
local Theme = require(Shared.Config.Theme)
local Zones = require(Shared.Config.Zones)
local Store = require(script.Parent.Parent.Core.Store)
local UI = require(script.Parent.Parent.UI.UI)
local Menu = require(script.Parent.Parent.UI.Menu)

local C = Theme.Color

local Module: Menu.MenuModule = {
	Title = "Zones",
	Keys = { "Zones", "Level", "Coins" },
	build = function(content: Frame, ctx: Menu.Context)
		local data = Store.Data
		local column = Menu.column(content)
		Menu.action(
			column,
			0,
			"My Base",
			"Your training dummy, weapon rack and decorations.",
			"GO HOME",
			"ghost",
			function()
				Net.event("Teleport"):FireServer({ id = "Home" })
				ctx.Close()
			end
		)
		for i, zone in Zones.List do
			local unlocked = data.Zones and data.Zones[zone.Id] == true
			local level: number = data.Level or 1
			local coins: number = data.Coins or 0
			local previous = Zones.List[i - 1]
			local previousOk = previous == nil or (data.Zones and data.Zones[previous.Id] == true)
			local canUnlock = level >= zone.MinLevel and coins >= zone.UnlockCoins and previousOk
			local requirement = if zone.UnlockCoins > 0
				then ("Level %d  ·  %s coins"):format(zone.MinLevel, UI.format(zone.UnlockCoins))
				else ("Level %d"):format(zone.MinLevel)
			local row, button = Menu.action(
				column,
				i,
				("%d. %s"):format(i, zone.Name),
				if unlocked then zone.Tagline else requirement,
				if unlocked then "TELEPORT" else "UNLOCK",
				if unlocked then "primary" else "good",
				function()
					if unlocked then
						Net.event("Teleport"):FireServer({ id = zone.Id })
						ctx.Close()
					else
						Net.event("UnlockZone"):FireServer({ id = zone.Id })
					end
				end
			)
			local strip = UI.new("Frame", {
				BackgroundColor3 = zone.Palette.Glow,
				BorderSizePixel = 0,
				Size = UDim2.new(0, 6, 1, -12),
				Position = UDim2.fromOffset(4, 6),
				Parent = row,
			})
			UI.corner(UDim.new(0, 3)).Parent = strip
			if not unlocked then
				button:SetEnabled(canUnlock)
				row.BackgroundTransparency = 0.5
			end
			local _ = C
		end
	end,
}

return Module
