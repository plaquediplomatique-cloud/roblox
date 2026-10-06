--!strict
--[[
	LockerTab — CASIER (équiper ce que l'on possède) et BOUTIQUE (acheter en Flux).

	Catégories : opérateurs (tenue 3e personne + bras du viewmodel), effets
	d'élimination, emotes (4 emplacements de la roue), bannières, titres — et, en
	boutique, les skins d'armes achetables. Rareté Commun → Mythique (couleur, prix).
	Les produits Robux (Products) n'apparaissent que lorsqu'un productId est configuré :
	un jeu non publié n'affiche jamais de bouton d'achat mort.
	Tout passe par le serveur (InventoryAction / ShopAction) : le client n'affiche que
	l'état répliqué du profil.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Cosmetics = require(Shared.Config.Cosmetics)
local Products = require(Shared.Config.Products)
local Theme = require(Shared.Config.Theme)
local UI = require(script.Parent.Parent.UI.UI)
local ClientState = require(script.Parent.Parent.Core.ClientState)
local Remote = require(script.Parent.Remote)

local colors = Theme.colors
local fonts = Theme.fonts

local LockerTab = {}

export type Tab = { frame: Frame, refresh: () -> (), focus: (option: string?) -> () }
export type Mode = "Locker" | "Shop"

local KINDS: { Types.ItemKind } = { "Operator", "KillEffect", "Emote", "Banner", "Title", "WeaponSkin" }
local KIND_NAMES: { [string]: string } = {
	Operator = "OPÉRATEURS",
	KillEffect = "ÉLIMINATIONS",
	Emote = "EMOTES",
	Banner = "BANNIÈRES",
	Title = "TITRES",
	WeaponSkin = "SKINS D'ARMES",
}

local function equippedId(data: Types.ProfileData, kind: string): string?
	if kind == "Operator" then
		return data.Cosmetics.Operator
	elseif kind == "KillEffect" then
		return data.Cosmetics.KillEffect
	elseif kind == "Banner" then
		return data.Cosmetics.Banner
	elseif kind == "Title" then
		return data.Cosmetics.Title
	end
	return nil
end

function LockerTab.build(parent: Instance, mode: Mode): Tab
	local frame = UI.frame({ BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = parent })
	local kind: string = if mode == "Shop" then "WeaponSkin" else "Operator"
	local pendingBuy: string? = nil
	local selectedEmoteSlot = 1

	local filters = UI.frame({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36), Parent = frame })
	UI.list(filters, Enum.FillDirection.Horizontal, 6)
	local wallet = UI.text({
		Text = "",
		FontFace = fonts.monoBold,
		TextSize = 16,
		TextColor3 = colors.gold,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(300, 36),
		Parent = frame,
	})
	local emoteSlots = UI.frame({
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 44),
		Size = UDim2.new(1, 0, 0, 40),
		Visible = false,
		Parent = frame,
	})
	UI.list(emoteSlots, Enum.FillDirection.Horizontal, 6)
	local grid = Instance.new("ScrollingFrame")
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.Position = UDim2.fromOffset(0, 92)
	grid.Size = UDim2.new(1, 0, 1, -92)
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.CanvasSize = UDim2.new()
	grid.ScrollBarThickness = 4
	grid.Parent = frame
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(196, 112)
	layout.CellPadding = UDim2.fromOffset(10, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	local render: () -> ()

	local function card(order: number, item: Types.ItemDef, data: Types.ProfileData)
		local owned = data.Inventory[item.id] == true or item.line == "default"
		local rarity = Cosmetics.rarities[item.rarity]
		local equipped = equippedId(data, item.kind) == item.id
		if item.kind == "Emote" then
			equipped = data.Cosmetics.Emotes[selectedEmoteSlot] == item.id
		end
		local button = UI.button({
			Text = "",
			LayoutOrder = order,
			BackgroundColor3 = if equipped then colors.panelLight else colors.panel,
			Parent = grid,
		})
		UI.corner(4, button)
		UI.stroke(
			button,
			if equipped then colors.primary else rarity.color,
			if equipped then 2 else 1,
			if owned then 0.1 else 0.55
		)
		UI.gradient(button, ColorSequence.new(rarity.color:Lerp(colors.panel, 0.82), colors.panel), 90)
		UI.frame({ BackgroundColor3 = rarity.color, Size = UDim2.new(1, 0, 0, 3), Parent = button })
		UI.text({
			Text = item.displayName,
			FontFace = fonts.heading,
			TextSize = 17,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.fromOffset(12, 10),
			Size = UDim2.new(1, -24, 0, 22),
			Parent = button,
		})
		UI.text({
			Text = item.description,
			FontFace = fonts.body,
			TextSize = 13,
			TextColor3 = colors.textDim,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextWrapped = true,
			Position = UDim2.fromOffset(12, 34),
			Size = UDim2.new(1, -24, 0, 38),
			Parent = button,
		})
		local status = if equipped
			then "ÉQUIPÉ"
			elseif owned then (if mode == "Shop" then "POSSÉDÉ" else "ÉQUIPER")
			elseif item.price then (if pendingBuy == item.id then "CONFIRMER · " else "") .. item.price .. " ◈ FLUX"
			else "PASS · NIVEAU · ÉVÉNEMENT"
		UI.text({
			Text = rarity.label .. "   " .. status,
			FontFace = fonts.mono,
			TextSize = 12,
			TextColor3 = if pendingBuy == item.id then colors.warning else rarity.color,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.new(0, 12, 1, -26),
			Size = UDim2.new(1, -24, 0, 18),
			Parent = button,
		})
		button.Activated:Connect(function()
			if owned and not equipped then
				UI.playSound("UI.Confirm")
				if item.kind == "Emote" then
					Remote.call("InventoryAction", { action = "SetEmote", item = item.id, index = selectedEmoteSlot })
				elseif item.kind == "WeaponSkin" then
					Remote.call("InventoryAction", { action = "EquipSkin", weapon = item.weaponId, item = item.id })
				else
					Remote.call("InventoryAction", { action = "EquipCosmetic", item = item.id })
				end
			elseif not owned and item.price then
				if pendingBuy == item.id then
					pendingBuy = nil
					local response = Remote.call("ShopAction", { action = "Buy", item = item.id })
					if response.ok then
						UI.playSound("UI.Reward")
					end
				else
					pendingBuy = item.id
					UI.playSound("UI.Click")
					render()
				end
			end
		end)
	end

	local function robuxCard(order: number, product: Products.ProductDef)
		local button = UI.button({
			Text = "",
			LayoutOrder = order,
			BackgroundColor3 = colors.panel,
			Parent = grid,
		})
		UI.corner(4, button)
		UI.stroke(button, colors.secondary, 1.5, 0)
		UI.text({
			Text = product.displayName,
			FontFace = fonts.heading,
			TextSize = 17,
			TextColor3 = colors.secondary,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(12, 10),
			Size = UDim2.new(1, -24, 0, 22),
			Parent = button,
		})
		UI.text({
			Text = product.description,
			FontFace = fonts.body,
			TextSize = 13,
			TextColor3 = colors.textDim,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Position = UDim2.fromOffset(12, 34),
			Size = UDim2.new(1, -24, 0, 50),
			Parent = button,
		})
		button.Activated:Connect(function()
			UI.playSound("UI.Click")
			MarketplaceService:PromptProductPurchase(Players.LocalPlayer, product.productId)
		end)
	end

	local function renderEmoteSlots(data: Types.ProfileData)
		for _, child in emoteSlots:GetChildren() do
			if child:IsA("GuiButton") then
				child:Destroy()
			end
		end
		emoteSlots.Visible = kind == "Emote"
		if kind ~= "Emote" then
			return
		end
		for index = 1, 4 do
			local current = data.Cosmetics.Emotes[index]
			local item = if current then Cosmetics.get(current) else nil
			local active = index == selectedEmoteSlot
			local button = UI.button({
				Text = ("%d · %s"):format(index, if item then item.displayName else "VIDE"),
				TextSize = 13,
				Size = UDim2.fromOffset(180, 34),
				LayoutOrder = index,
				BackgroundColor3 = if active then colors.primaryDeep else colors.panelLight,
				Parent = emoteSlots,
			})
			UI.corner(3, button)
			button.Activated:Connect(function()
				selectedEmoteSlot = index
				UI.playSound("UI.Click")
				render()
			end)
		end
	end

	render = function()
		for _, child in grid:GetChildren() do
			if child:IsA("GuiButton") then
				child:Destroy()
			end
		end
		for _, child in filters:GetChildren() do
			if child:IsA("GuiButton") then
				child:Destroy()
			end
		end
		local data = ClientState.profileData()
		if not data then
			return
		end
		wallet.Text = ("◈ %d FLUX    ✦ %d CRISTAUX"):format(data.Currency.Flux, data.Currency.Crystals)
		for index, name in KINDS do
			if mode == "Locker" and name == "WeaponSkin" then
				continue
			end
			local active = name == kind
			local button = UI.button({
				Text = KIND_NAMES[name],
				TextSize = 13,
				Size = UDim2.fromOffset(130, 34),
				LayoutOrder = index,
				BackgroundColor3 = if active then colors.primary else colors.panelLight,
				TextColor3 = if active then colors.void else colors.textDim,
				Parent = filters,
			})
			UI.corner(3, button)
			button.Activated:Connect(function()
				kind = name
				pendingBuy = nil
				UI.playSound("UI.Click")
				render()
			end)
		end
		renderEmoteSlots(data)
		local items: { Types.ItemDef } = {}
		for _, id in Cosmetics.order do
			local item = Cosmetics.items[id]
			if item.kind ~= kind then
				continue
			end
			local owned = data.Inventory[item.id] == true or item.line == "default"
			if mode == "Locker" and not owned then
				continue
			end
			if mode == "Shop" and (owned or item.price == nil) then
				continue
			end
			table.insert(items, item)
		end
		table.sort(items, function(a: Types.ItemDef, b: Types.ItemDef): boolean
			local ra, rb = Cosmetics.rarities[a.rarity].order, Cosmetics.rarities[b.rarity].order
			if ra ~= rb then
				return ra > rb
			end
			return a.displayName < b.displayName
		end)
		local order = 0
		if mode == "Shop" then
			for _, product in Products.list do
				if product.productId ~= 0 then
					order += 1
					robuxCard(order, product)
				end
			end
		end
		for _, item in items do
			order += 1
			card(order, item, data)
		end
		if order == 0 then
			local empty = UI.button({ Text = "", BackgroundTransparency = 1, LayoutOrder = 1, Parent = grid })
			UI.text({
				Text = if mode == "Shop" then "Tout est déjà à vous." else "Rien ici pour l'instant.",
				TextColor3 = colors.textFaint,
				Size = UDim2.fromScale(1, 1),
				Parent = empty,
			})
		end
	end

	local function hook(replica: any)
		replica.Changed:Connect(function()
			if frame.Visible then
				task.defer(render)
			end
		end)
	end
	ClientState.ProfileReady:Connect(hook)
	local existing = ClientState.profile()
	if existing then
		hook(existing)
	end

	local function focus(option: string?)
		if option and KIND_NAMES[option] then
			kind = option
		end
		pendingBuy = nil
		render()
	end

	return { frame = frame, refresh = render, focus = focus }
end

return LockerTab
