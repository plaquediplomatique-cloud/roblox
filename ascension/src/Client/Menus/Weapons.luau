--!strict
--[[
	Menu Armes — collection complète (voie principale + armes de chasse), aperçu 3D de l'arme
	sélectionnée, équipement, et l'ASCENSION (prestige) en bas de page.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Net = require(Shared.Net.Net)
local Theme = require(Shared.Config.Theme)
local Game = require(Shared.Config.Game)
local WeaponCatalog = require(Shared.Rules.WeaponCatalog)
local Combat = require(Shared.Rules.Combat)
local Ascension = require(Shared.Rules.Ascension)
local Store = require(script.Parent.Parent.Core.Store)
local UI = require(script.Parent.Parent.UI.UI)
local Menu = require(script.Parent.Parent.UI.Menu)
local WeaponView = require(script.Parent.Parent.UI.WeaponView)

local C = Theme.Color

local selected: string? = nil

local function sourceText(weapon: WeaponCatalog.Weapon): string
	if weapon.Main then
		return ("Unlocks at level %d"):format(weapon.Level :: number)
	elseif weapon.Source == "Boss" then
		return "Boss drop"
	elseif weapon.Source == "Chest" then
		return "Found in chests"
	elseif weapon.Source == "Achievement" then
		return "Achievement reward"
	end
	return "Event reward"
end

local function buildDetail(parent: Frame, weapon: WeaponCatalog.Weapon, owned: boolean)
	local rarity = weapon.Rarity
	local detail = UI.panel({ Size = UDim2.new(0, 290, 1, 0), Position = UDim2.new(1, -290, 0, 0), Parent = parent })
	UI.label({
		Text = weapon.Name,
		Font = Theme.Font.Display,
		TextSize = 26,
		Position = UDim2.fromOffset(14, 8),
		Size = UDim2.new(1, -28, 0, 32),
		Parent = detail,
	})
	UI.label({
		Text = rarity.Name:upper(),
		TextSize = 16,
		TextColor3 = rarity.Color,
		Position = UDim2.fromOffset(14, 38),
		Size = UDim2.new(1, -28, 0, 20),
		Parent = detail,
	})
	WeaponView.create(detail, weapon, UDim2.new(1, -20, 0, 150)).Position = UDim2.fromOffset(10, 60)
	local fighter = Store.fighter()
	local mine = Combat.baseDamage(fighter)
	local lines = {
		("Damage   %s"):format(UI.format(weapon.Damage)),
		("Speed     %.1f hits/s"):format(weapon.AttackSpeed),
		("Reach      %.0f studs"):format(weapon.Reach),
		("XP bonus  x%.2f"):format(weapon.XPBoost),
	}
	if weapon.Special then
		table.insert(lines, "Ability   " .. weapon.Special.Name)
	end
	table.insert(lines, if owned then "Owned" else sourceText(weapon))
	for i, line in lines do
		UI.label({
			Text = line,
			TextSize = 16,
			Font = Theme.Font.Body,
			TextColor3 = if i == #lines then (if owned then C.Good else C.TextDim) else C.Text,
			Position = UDim2.fromOffset(16, 214 + (i - 1) * 22),
			Size = UDim2.new(1, -32, 0, 22),
			Parent = detail,
		})
	end
	local equipped = Store.Data.Equipped == weapon.Id
	local button = UI.button({
		Text = if equipped then "EQUIPPED" else (if owned then "EQUIP" else "LOCKED"),
		Size = UDim2.new(1, -28, 0, 44),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Style = if owned and not equipped then "good" else "ghost",
		Parent = detail,
	}, function()
		if owned and not equipped then
			Net.event("Equip"):FireServer({ id = weapon.Id })
		end
	end)
	button:SetEnabled(owned and not equipped)
	local _ = mine
end

local function buildAscension(parent: Frame)
	local data = Store.Data
	local ok, reason = Ascension.canAscend(data)
	local stars: number = data.Stars or 0
	local bar = UI.panel({
		Size = UDim2.new(1, -306, 0, 74),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Parent = parent,
	})
	UI.label({
		Text = ("ASCENSION  ★ %d"):format(stars),
		Font = Theme.Font.Display,
		TextSize = 22,
		TextColor3 = C.Level,
		Position = UDim2.fromOffset(14, 6),
		Size = UDim2.new(1, -200, 0, 28),
		Parent = bar,
	})
	UI.label({
		Text = if ok then "Reset level & weapons. Keep coins, upgrades & hunted weapons. +1 star." else (reason or ""),
		TextSize = 13,
		Font = Theme.Font.Body,
		TextColor3 = C.TextDim,
		TextWrapped = true,
		Position = UDim2.fromOffset(14, 34),
		Size = UDim2.new(1, -200, 0, 36),
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = bar,
	})
	local button = UI.button({
		Text = "ASCEND",
		Size = UDim2.fromOffset(150, 46),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Style = "bad",
		Parent = bar,
	}, function()
		Net.event("Ascend"):FireServer({})
	end)
	button:SetEnabled(ok)
end

local Weapons: Menu.MenuModule = {
	Title = "Weapons",
	Keys = { "Weapons", "Equipped", "Level", "Stars", "Upgrades", "Collection" },
	build = function(content: Frame, _ctx: Menu.Context)
		local data = Store.Data
		local owned: { [string]: boolean } = data.Weapons or {}
		local collection: { [string]: boolean } = data.Collection or {}
		local count = 0
		for _ in collection do
			count += 1
		end

		local sel = selected or data.Equipped
		local weapon = WeaponCatalog.ById[sel] or WeaponCatalog.Main[1]
		selected = weapon.Id

		UI.label({
			Text = ("Collection  %d / %d"):format(count, #WeaponCatalog.List),
			TextSize = 16,
			TextColor3 = C.TextDim,
			Size = UDim2.new(1, -306, 0, 22),
			Parent = content,
		})
		local gridHolder = UI.new("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, 26),
			Size = UDim2.new(1, -306, 1, -26 - 82),
			Parent = content,
		})
		local scroller = UI.scroller({ Parent = gridHolder })
		UI.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(104, 76),
			CellPadding = UDim2.fromOffset(6, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = scroller,
		})
		UI.padding(2).Parent = scroller
		for i, entry in WeaponCatalog.List do
			local isOwned = owned[entry.Id] == true
			local card = UI.new("TextButton", {
				AutoButtonColor = false,
				Text = "",
				BackgroundColor3 = C.InkSoft,
				BackgroundTransparency = if isOwned then 0.1 else 0.55,
				LayoutOrder = i,
				Parent = scroller,
			})
			UI.corner(UDim.new(0, 10)).Parent = card
			local stroke =
				UI.stroke(entry.Rarity.Color, if entry.Id == selected then 4 else 1.5, if isOwned then 0 else 0.6)
			stroke.Parent = card
			UI.new("Frame", {
				BackgroundColor3 = entry.Rarity.Color,
				BackgroundTransparency = if isOwned then 0 else 0.6,
				BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 0, 6),
				Parent = card,
			})
			UI.label({
				Text = entry.Name,
				TextSize = 12,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextTransparency = if isOwned then 0 else 0.4,
				Position = UDim2.fromOffset(2, 10),
				Size = UDim2.new(1, -4, 0, 34),
				Parent = card,
			})
			UI.label({
				Text = if isOwned
					then ("DMG " .. UI.format(entry.Damage))
					else (if entry.Main then ("Lv " .. tostring(entry.Level)) else "???"),
				TextSize = 13,
				Font = Theme.Font.Body,
				TextColor3 = if isOwned then C.Xp else C.TextDim,
				TextXAlignment = Enum.TextXAlignment.Center,
				Position = UDim2.fromOffset(2, 48),
				Size = UDim2.new(1, -4, 0, 20),
				Parent = card,
			})
			if data.Equipped == entry.Id then
				UI.label({
					Text = "E",
					TextSize = 14,
					TextColor3 = C.Good,
					Position = UDim2.new(1, -16, 0, 8),
					Size = UDim2.fromOffset(14, 14),
					Parent = card,
				})
			end
			card.Activated:Connect(function()
				selected = entry.Id
				Store.Changed:Fire("Weapons") -- redessine avec la nouvelle sélection
			end)
		end

		buildDetail(content, weapon, owned[weapon.Id] == true)
		buildAscension(content)
		local _ = Game
	end,
}

return Weapons
