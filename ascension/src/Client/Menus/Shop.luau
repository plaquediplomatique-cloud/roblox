--!strict
--[[
	Menu Boutique — coffres gagnés en jeu (avec les CHANCES affichées), Game Passes et produits.
	Aucun achat ne vend de dégâts ni de niveaux ; l'XP payante est plafonnée (règles serveur).
	Un identifiant 0 = produit non configuré : le bouton reste inactif.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Net = require(Shared.Net.Net)
local Theme = require(Shared.Config.Theme)
local Loot = require(Shared.Config.Loot)
local Products = require(Shared.Config.Products)
local Store = require(script.Parent.Parent.Core.Store)
local UI = require(script.Parent.Parent.UI.UI)
local Menu = require(script.Parent.Parent.UI.Menu)

local C = Theme.Color

local tab = "Chests"

local function oddsText(chest: Loot.Chest): string
	local total = 0
	for _, weight in chest.Weights do
		total += weight
	end
	local parts = {}
	for rarity, weight in chest.Weights do
		table.insert(parts, ("%s %.0f%%"):format(rarity, weight / total * 100))
	end
	table.sort(parts)
	return table.concat(parts, "  ·  ")
end

local Module: Menu.MenuModule = {
	Title = "Shop",
	Keys = { "Chests", "Weapons" },
	build = function(content: Frame, ctx: Menu.Context)
		Menu.tabs(
			content,
			{
				{ Id = "Chests", Text = "My Chests" },
				{ Id = "Passes", Text = "Passes & Boosts" },
			},
			tab,
			function(id)
				tab = id
				ctx.Rebuild()
			end
		)
		local holder = UI.new("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, 50),
			Size = UDim2.new(1, 0, 1, -50),
			Parent = content,
		})
		local column = Menu.column(holder)
		local data = Store.Data
		if tab == "Chests" then
			for i, chest in Loot.Chests do
				local count: number = (data.Chests and data.Chests[chest.Id]) or 0
				local _, button = Menu.action(
					column,
					i,
					("%s  x%d"):format(chest.Name, count),
					oddsText(chest),
					"OPEN",
					"good",
					function()
						Net.event("OpenChest"):FireServer({ id = chest.Id })
						ctx.Close()
					end
				)
				button:SetEnabled(count > 0)
			end
			UI.label({
				Text = "Chests come from bosses, quests, achievements and the daily reward. They are never sold.",
				TextSize = 13,
				Font = Theme.Font.Body,
				TextColor3 = C.TextDim,
				TextWrapped = true,
				Size = UDim2.new(1, -8, 0, 36),
				LayoutOrder = 99,
				Parent = column,
			})
		else
			local order = 0
			for _, pass in Products.Passes do
				order += 1
				local owned = Store.Passes[pass.Id] == true
				local _, button = Menu.action(
					column,
					order,
					pass.Name,
					pass.Desc,
					if owned then "OWNED" else "BUY",
					"primary",
					function()
						MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, pass.PassId)
					end
				)
				button:SetEnabled(not owned and pass.PassId > 0)
			end
			for _, product in Products.Products do
				order += 1
				local _, button = Menu.action(column, order, product.Name, product.Desc, "BUY", "good", function()
					MarketplaceService:PromptProductPurchase(Players.LocalPlayer, product.ProductId)
				end)
				button:SetEnabled(product.ProductId > 0)
			end
		end
	end,
}

return Module
