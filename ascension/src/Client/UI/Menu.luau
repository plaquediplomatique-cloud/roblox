--!strict
--[[
	Menu — petits assistants communs aux menus (lignes, onglets, entêtes, barres de progression).
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Theme = require(Shared.Config.Theme)
local UI = require(script.Parent.UI)

local Menu = {}

export type Context = {
	Close: () -> (),
	Rebuild: () -> (),
	Root: Frame,
}

export type MenuModule = {
	Title: string,
	Keys: { string }, -- clés du Store qui déclenchent un rafraîchissement
	build: (content: Frame, ctx: Context) -> (),
}

local C = Theme.Color

-- Ligne de liste : fond doux, hauteur fixe, coins arrondis.
function Menu.row(parent: Instance, order: number, height: number?): Frame
	local row = UI.new("Frame", {
		BackgroundColor3 = C.InkSoft,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -8, 0, height or 64),
		LayoutOrder = order,
		Parent = parent,
	})
	UI.corner(Theme.Radius).Parent = row
	return row
end

-- Barre d'onglets ; `onSelect(id)` est appelé au clic. Renvoie le Frame.
function Menu.tabs(
	parent: Instance,
	tabs: { { Id: string, Text: string } },
	selected: string,
	onSelect: (string) -> ()
): Frame
	local bar = UI.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 42),
		Parent = parent,
	})
	UI.list(Enum.FillDirection.Horizontal, 8).Parent = bar
	for i, tab in tabs do
		UI.button({
			Text = tab.Text,
			Size = UDim2.fromOffset(150, 38),
			Style = if tab.Id == selected then "primary" else "ghost",
			LayoutOrder = i,
			Parent = bar,
		}, function()
			onSelect(tab.Id)
		end)
	end
	return bar
end

-- Titre de section.
function Menu.section(parent: Instance, text: string, order: number): TextLabel
	return UI.label({
		Text = text,
		TextSize = Theme.Size.Large,
		TextColor3 = C.TextDim,
		Size = UDim2.new(1, 0, 0, 30),
		LayoutOrder = order,
		Parent = parent,
	})
end

-- Colonne défilante qui remplit `parent`.
function Menu.column(parent: Instance, gap: number?): ScrollingFrame
	local scroller = UI.scroller({
		Size = UDim2.fromScale(1, 1),
		Parent = parent,
	})
	UI.list(Enum.FillDirection.Vertical, gap or 8).Parent = scroller
	UI.padding(4).Parent = scroller
	return scroller
end

-- Ligne « titre + sous-titre à gauche, bouton à droite ». Renvoie (row, bouton).
function Menu.action(
	parent: Instance,
	order: number,
	title: string,
	subtitle: string,
	buttonText: string,
	style: UI.ButtonStyle?,
	onClick: () -> ()
): (Frame, UI.Button)
	local row = Menu.row(parent, order, 64)
	UI.label({
		Text = title,
		TextSize = 20,
		Position = UDim2.fromOffset(14, 6),
		Size = UDim2.new(1, -200, 0, 26),
		Parent = row,
	})
	UI.label({
		Text = subtitle,
		TextSize = 14,
		Font = Theme.Font.Body,
		TextColor3 = C.TextDim,
		Position = UDim2.fromOffset(14, 32),
		Size = UDim2.new(1, -200, 0, 24),
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = row,
	})
	local button = UI.button({
		Text = buttonText,
		Size = UDim2.fromOffset(160, 42),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Style = style or "primary",
		Parent = row,
	}, onClick)
	return row, button
end

return Menu
