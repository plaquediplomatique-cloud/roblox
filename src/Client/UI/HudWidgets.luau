--!strict
--[[
	HudWidgets — éléments visuels du HUD de combat : construction seule, aucune logique.

	HUDController crée ces éléments puis met à jour leurs champs ; tools/ui_preview.luau les
	construit hors Studio et tools/render_ui.py en fait une image (docs/renders/hud_*.png)
	pour juger la composition sans lancer le jeu.

	Direction : verre sombre biseauté (« futuriste froid et premium »).
	  * blocs du bas en parallélogrammes « / » (UI.glass) : verre bleu nuit, liseré cyan sur
	    le bord oblique, filet lumineux au pied ; plaques d'ombre douces derrière pour la
	    lisibilité sur ciel clair ;
	  * bas-gauche : portrait de l'avatar + santé / bouclier ; bas-centre : barre d'armes ;
	    bas-droite : munitions ; tout reste dans la zone sûre, rien en haut à gauche ni en
	    haut à droite (boutons Roblox) ;
	  * icônes vectorielles en frames (croix, écusson, cartouche) : aucun asset à charger ;
	  * gros chiffres Builder Sans ExtraBold, libellés courts en capitales, gris clair ;
	  * une seule couleur d'accent (cyan) + couleurs d'équipe ; le rouge reste l'alerte ;
	  * barres fines segmentées : les paliers (25 PV, 25 bouclier) se lisent d'un coup d'oeil.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Theme = require(Shared.Config.Theme)
local UI = require(script.Parent.UI)

local colors = Theme.colors
local fonts = Theme.fonts

local HudWidgets = {}

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local TRAIL_DELAY = 0.35

---------------------------------------------------------------------------------------------
-- Briques
---------------------------------------------------------------------------------------------

--[[
	Plaque d'ombre : noir dont l'opacité décroît en diagonale depuis un coin de l'écran.
	`rotation` : direction du fondu (−45 = depuis le bas-gauche, −135 = depuis le bas-droite).
	Plaque CARRÉE : les deux autres coins tombent à mi-dégradé, totalement transparents,
	aucune arête n'est visible.
]]
function HudWidgets.shadow(parent: Instance, props: { [string]: any }, rotation: number, strength: number): Frame
	local frame = UI.frame({ BackgroundColor3 = colors.shadow, BackgroundTransparency = 0, ZIndex = 0 })
	UI.gradient(
		frame,
		ColorSequence.new(colors.shadow),
		rotation,
		NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1 - strength),
			NumberSequenceKeypoint.new(0.34, 1 - strength * 0.72),
			NumberSequenceKeypoint.new(0.5, 1),
			NumberSequenceKeypoint.new(1, 1),
		})
	)
	UI.apply(frame, props)
	frame.Parent = parent
	return frame
end

--[[ Ombre portée douce sous un texte (lisible sur ciel clair comme sur mur sombre). ]]
function HudWidgets.textShadow(label: TextLabel, transparency: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = BLACK
	stroke.Thickness = 1
	stroke.Transparency = transparency or 0.7
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = label
	return stroke
end

local function label(props: { [string]: any }): TextLabel
	local text = UI.text({
		FontFace = fonts.heading,
		TextSize = 13,
		TextColor3 = colors.text,
		BackgroundTransparency = 1,
	})
	UI.apply(text, props)
	return text
end

--[[ Pastille de texte (emplacement d'arme, mode de tir, touche). ]]
local function chip(props: { [string]: any }, padding: number): TextLabel
	local text = label({
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 1,
		TextSize = 12,
	})
	UI.apply(text, props)
	UI.corner(4, text)
	UI.padding(text, padding, padding, 0, 0)
	return text
end

export type SegmentBar = {
	root: Frame,
	set: (value: number, max: number) -> (),
	setColor: (color: Color3) -> (),
}

--[[
	Barre segmentée avec traînée : la partie perdue reste visible en blanc puis se résorbe.
	`segments` cases séparées de 3 px (une case = un palier).
]]
function HudWidgets.segmentBar(color: Color3, segments: number, props: { [string]: any }): SegmentBar
	local root = UI.frame({ BackgroundTransparency = 1 })
	UI.apply(root, props)
	local gap = 3
	local fills: { Frame } = {}
	local ghosts: { Frame } = {}
	for index = 1, segments do
		local cell = UI.frame({
			Name = "Segment" .. index,
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.82,
			ClipsDescendants = true,
			Position = UDim2.new((index - 1) / segments, if index == 1 then 0 else gap / 2, 0, 0),
			Size = UDim2.new(1 / segments, -(if index == 1 or index == segments then gap / 2 else gap), 1, 0),
			Parent = root,
		})
		UI.corner(1, cell)
		UI.stroke(cell, BLACK, 1, 0.7)
		local ghost = UI.frame({
			Name = "Trail",
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.25,
			Size = UDim2.fromScale(1, 1),
			Parent = cell,
		})
		local fill = UI.frame({
			Name = "Fill",
			BackgroundColor3 = color,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 2,
			Parent = cell,
		})
		table.insert(fills, fill)
		table.insert(ghosts, ghost)
	end
	local lastRatio = 1
	local token = 0
	local function ratios(ratio: number): { number }
		local list = {}
		for index = 1, segments do
			list[index] = math.clamp(ratio * segments - (index - 1), 0, 1)
		end
		return list
	end
	local function set(value: number, max: number)
		local ratio = math.clamp(if max > 0 then value / max else 0, 0, 1)
		local cells = ratios(ratio)
		for index, fill in fills do
			fill.Size = UDim2.fromScale(cells[index], 1)
		end
		token += 1
		local current = token
		if ratio < lastRatio then
			task.delay(TRAIL_DELAY, function()
				if current ~= token then
					return
				end
				for index, ghost in ghosts do
					UI.tween(
						ghost,
						TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
						{ Size = UDim2.fromScale(cells[index], 1) }
					)
				end
			end)
		else
			for index, ghost in ghosts do
				ghost.Size = UDim2.fromScale(cells[index], 1)
			end
		end
		lastRatio = ratio
	end
	local function setColor(newColor: Color3)
		for _, fill in fills do
			fill.BackgroundColor3 = newColor
		end
	end
	return { root = root, set = set, setColor = setColor }
end

---------------------------------------------------------------------------------------------
-- Icônes vectorielles (frames simples : aucun asset à charger)
---------------------------------------------------------------------------------------------

--[[ Croix de santé. ]]
local function crossIcon(parent: Instance, position: UDim2, size: number, color: Color3): Frame
	local icon = UI.frame({ Name = "CrossIcon", BackgroundTransparency = 1, Position = position, Parent = parent })
	icon.Size = UDim2.fromOffset(size, size)
	local thickness = math.max(math.floor(size * 0.32 + 0.5), 2)
	for _, bar in { UDim2.fromOffset(size, thickness), UDim2.fromOffset(thickness, size) } do
		local piece = UI.frame({
			BackgroundColor3 = color,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = bar,
			Parent = icon,
		})
		UI.corner(1, piece)
	end
	return icon
end

--[[ Écusson de bouclier : losange plein avec un coeur sombre. ]]
local function shieldIcon(parent: Instance, position: UDim2, size: number, color: Color3): Frame
	local icon = UI.frame({ Name = "ShieldIcon", BackgroundTransparency = 1, Position = position, Parent = parent })
	icon.Size = UDim2.fromOffset(size, size)
	local side = size * 0.72
	local outer = UI.frame({
		BackgroundColor3 = color,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(side, side),
		Rotation = 45,
		Parent = icon,
	})
	UI.corner(2, outer)
	UI.frame({
		BackgroundColor3 = colors.glass,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(side * 0.4, side * 0.4),
		Rotation = 45,
		Parent = icon,
	})
	return icon
end

--[[ Cartouche : douille + ogive. ]]
local function bulletIcon(parent: Instance, position: UDim2, color: Color3): Frame
	local icon = UI.frame({ Name = "BulletIcon", BackgroundTransparency = 1, Position = position, Parent = parent })
	icon.Size = UDim2.fromOffset(12, 30)
	local tip = UI.frame({
		BackgroundColor3 = color,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(6, 8),
		Size = UDim2.fromOffset(8, 8),
		Rotation = 45,
		Parent = icon,
	})
	UI.corner(2, tip)
	UI.frame({
		BackgroundColor3 = color,
		Position = UDim2.fromOffset(0, 8),
		Size = UDim2.fromOffset(12, 6),
		Parent = icon,
	})
	local case = UI.frame({
		BackgroundColor3 = color,
		BackgroundTransparency = 0.35,
		Position = UDim2.fromOffset(0, 16),
		Size = UDim2.fromOffset(12, 14),
		Parent = icon,
	})
	UI.corner(1, case)
	return icon
end

--[[ Ligne lumineuse au pied d'un panneau biseauté (fondue aux deux bouts). ]]
local function glowLine(parent: Instance, slant: number, color: Color3): Frame
	local line = UI.frame({
		Name = "Glow",
		BackgroundColor3 = color,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 2, 1, 0),
		Size = UDim2.new(1, -slant - 4, 0, 2),
		ZIndex = 3,
		Parent = parent,
	})
	UI.gradient(
		line,
		ColorSequence.new(WHITE),
		0,
		NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(0.7, 0.35),
			NumberSequenceKeypoint.new(1, 1),
		})
	)
	return line
end

---------------------------------------------------------------------------------------------
-- Santé et bouclier (bas-gauche) : portrait + deux jauges sur verre biseauté
---------------------------------------------------------------------------------------------

export type Vitals = {
	root: Frame,
	portrait: ImageLabel,
	health: TextLabel,
	armor: TextLabel,
	healthBar: SegmentBar,
	armorBar: SegmentBar,
}

local VITALS_W, VITALS_H, SLANT = 420, 96, 18

function HudWidgets.vitals(parent: Instance): Vitals
	HudWidgets.shadow(parent, {
		Name = "VitalsShadow",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, -80, 1, 80),
		Size = UDim2.fromOffset(900, 900),
	}, -45, 0.45)
	local glass = UI.glass(VITALS_W, VITALS_H, SLANT, {
		Name = "Vitals",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 28, 1, -26),
		Parent = parent,
	})
	local root = glass.root
	glowLine(root, SLANT, colors.primary)
	-- Portrait : tête de l'avatar Roblox du joueur (silhouette tant que l'image charge).
	local frame = UI.frame({
		Name = "PortraitFrame",
		BackgroundColor3 = colors.void,
		BackgroundTransparency = 0.25,
		Position = UDim2.fromOffset(24, 10),
		Size = UDim2.fromOffset(76, 76),
		ClipsDescendants = true,
		ZIndex = 2,
		Parent = root,
	})
	UI.corner(4, frame)
	UI.stroke(frame, colors.primary, 1, 0.45)
	local head = UI.frame({
		BackgroundColor3 = colors.strokeBright,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(38, 14),
		Size = UDim2.fromOffset(30, 30),
		ZIndex = 2,
		Parent = frame,
	})
	UI.corner(15, head)
	local shoulders = UI.frame({
		BackgroundColor3 = colors.strokeBright,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(38, 50),
		Size = UDim2.fromOffset(56, 40),
		ZIndex = 2,
		Parent = frame,
	})
	UI.corner(18, shoulders)
	local portrait = Instance.new("ImageLabel")
	portrait.Name = "Portrait"
	portrait.BackgroundTransparency = 1
	portrait.Size = UDim2.fromScale(1, 1)
	portrait.ScaleType = Enum.ScaleType.Crop
	portrait.ZIndex = 3
	portrait.Parent = frame

	-- Santé : croix + gros chiffre + barre en 4 paliers.
	crossIcon(root, UDim2.fromOffset(118, 26), 16, colors.text)
	local health = label({
		Name = "Health",
		Text = "100",
		FontFace = fonts.number,
		TextSize = 40,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(142, 12),
		Size = UDim2.fromOffset(78, 42),
		ZIndex = 2,
		Parent = root,
	})
	HudWidgets.textShadow(health)
	local healthBar = HudWidgets.segmentBar(colors.health, 4, {
		Name = "HealthBar",
		Position = UDim2.fromOffset(222, 28),
		Size = UDim2.fromOffset(VITALS_W - 222 - 36, 10),
		ZIndex = 2,
		Parent = root,
	})
	-- Bouclier : écusson + chiffre + barre en 2 paliers.
	shieldIcon(root, UDim2.fromOffset(117, 58), 18, colors.armor)
	local armor = label({
		Name = "Armor",
		Text = "50",
		FontFace = fonts.number,
		TextSize = 24,
		TextColor3 = colors.armor,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(142, 54),
		Size = UDim2.fromOffset(78, 26),
		ZIndex = 2,
		Parent = root,
	})
	HudWidgets.textShadow(armor)
	local armorBar = HudWidgets.segmentBar(colors.armor, 2, {
		Name = "ArmorBar",
		Position = UDim2.fromOffset(222, 64),
		Size = UDim2.fromOffset(VITALS_W - 222 - 44, 6),
		ZIndex = 2,
		Parent = root,
	})
	return {
		root = root,
		portrait = portrait,
		health = health,
		armor = armor,
		healthBar = healthBar,
		armorBar = armorBar,
	}
end

---------------------------------------------------------------------------------------------
-- Munitions (bas-droite) et barre d'armes (bas-centre)
---------------------------------------------------------------------------------------------

export type WeaponSlot = {
	root: Frame,
	gradient: UIGradient,
	key: TextLabel,
	name: TextLabel,
	glow: Frame,
}

export type Ammo = {
	root: Frame,
	weaponName: TextLabel,
	fireMode: TextLabel,
	mag: TextLabel,
	reserve: TextLabel,
	pips: Frame,
	reloadTrack: Frame,
	reloadFill: Frame,
	slots: { [string]: WeaponSlot },
	reloadHint: TextLabel,
}

local MAX_PIPS = 40
local PIP_AREA = 240
local PIP_HEIGHT = 6
local AMMO_W, AMMO_H = 360, 96
local SLOT_W, SLOT_H, SLOT_SLANT, SLOT_GAP = 150, 56, 12, 6
local SLOT_NAMES = { "Primary", "Secondary", "Melee" }

local function weaponSlot(parent: Instance, index: number): WeaponSlot
	local glass = UI.glass(SLOT_W, SLOT_H, SLOT_SLANT, {
		Name = SLOT_NAMES[index],
		Position = UDim2.fromOffset((index - 1) * (SLOT_W + SLOT_GAP - SLOT_SLANT / 2), 0),
		LayoutOrder = index,
		Parent = parent,
	})
	local root = glass.root
	local key = label({
		Name = "Key",
		Text = tostring(index),
		FontFace = fonts.monoBold,
		TextSize = 11,
		TextColor3 = colors.textDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(SLOT_SLANT + 6, 7),
		Size = UDim2.fromOffset(20, 12),
		ZIndex = 2,
		Parent = root,
	})
	local name = label({
		Name = "WeaponName",
		Text = "—",
		FontFace = fonts.headingHeavy,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(SLOT_SLANT + 2, 22),
		Size = UDim2.fromOffset(SLOT_W - SLOT_SLANT - 18, 24),
		ZIndex = 2,
		Parent = root,
	})
	HudWidgets.textShadow(name, 0.75)
	local glow = glowLine(root, SLOT_SLANT, colors.primary)
	return { root = root, gradient = glass.gradient, key = key, name = name, glow = glow }
end

function HudWidgets.ammo(parent: Instance): Ammo
	HudWidgets.shadow(parent, {
		Name = "AmmoShadow",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 80, 1, 80),
		Size = UDim2.fromOffset(900, 900),
	}, -135, 0.45)
	local glass = UI.glass(AMMO_W, AMMO_H, SLANT, {
		Name = "Ammo",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -28, 1, -26),
		Parent = parent,
	})
	local root = glass.root
	glowLine(root, SLANT, colors.primary)
	local weaponName = label({
		Name = "WeaponName",
		Text = "VK-12 VEKTOR",
		FontFace = fonts.headingHeavy,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(SLANT + 14, 9),
		Size = UDim2.fromOffset(220, 18),
		ZIndex = 2,
		Parent = root,
	})
	HudWidgets.textShadow(weaponName, 0.75)
	local fireMode = chip({
		Name = "FireMode",
		Text = "AUTO",
		TextSize = 11,
		TextColor3 = colors.primary,
		BackgroundTransparency = 0.85,
		BackgroundColor3 = colors.primary,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromOffset(AMMO_W - 26, 9),
		Size = UDim2.fromOffset(0, 18),
		ZIndex = 2,
		Parent = root,
	}, 6)
	bulletIcon(root, UDim2.fromOffset(SLANT + 14, 38), colors.primary)
	local mag = label({
		Name = "Mag",
		Text = "30",
		FontFace = fonts.number,
		TextSize = 54,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromOffset(AMMO_W - 104, 22),
		Size = UDim2.fromOffset(150, 54),
		ZIndex = 2,
		Parent = root,
	})
	HudWidgets.textShadow(mag)
	local reserve = label({
		Name = "Reserve",
		Text = "/ 90",
		FontFace = fonts.number,
		TextSize = 24,
		TextColor3 = colors.textDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		Position = UDim2.fromOffset(AMMO_W - 100, 22),
		Size = UDim2.fromOffset(76, 48),
		ZIndex = 2,
		Parent = root,
	})
	HudWidgets.textShadow(reserve, 0.75)
	local pips = UI.frame({
		Name = "Pips",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromOffset(AMMO_W - 30, 80),
		Size = UDim2.fromOffset(PIP_AREA, PIP_HEIGHT),
		ZIndex = 2,
		Parent = root,
	})
	UI.list(pips, Enum.FillDirection.Horizontal, 2, Enum.HorizontalAlignment.Right)
	local reloadTrack = UI.frame({
		Name = "Reload",
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.8,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromOffset(AMMO_W - 30, 89),
		Size = UDim2.fromOffset(PIP_AREA, 2),
		Visible = false,
		ZIndex = 2,
		Parent = root,
	})
	local reloadFill = UI.frame({
		BackgroundColor3 = colors.primary,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = reloadTrack,
	})
	reloadFill.Size = UDim2.fromScale(0, 1)
	-- Barre d'armes centrée en bas : un panneau biseauté par emplacement.
	local barWidth = #SLOT_NAMES * (SLOT_W + SLOT_GAP - SLOT_SLANT / 2) - SLOT_GAP + SLOT_SLANT / 2
	local slotBar = UI.frame({
		Name = "WeaponBar",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -26),
		Size = UDim2.fromOffset(barWidth, SLOT_H),
		Parent = parent,
	})
	local slots: { [string]: WeaponSlot } = {}
	for index, slotName in SLOT_NAMES do
		slots[slotName] = weaponSlot(slotBar, index)
		HudWidgets.styleSlot(slots[slotName], false)
	end
	local reloadHint = label({
		Name = "ReloadHint",
		Text = "RECHARGER",
		FontFace = fonts.heading,
		TextSize = 18,
		TextColor3 = colors.warning,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, 64),
		Size = UDim2.fromOffset(300, 24),
		Visible = false,
		Parent = parent,
	})
	HudWidgets.textShadow(reloadHint, 0.4)
	return {
		root = root,
		weaponName = weaponName,
		fireMode = fireMode,
		mag = mag,
		reserve = reserve,
		pips = pips,
		reloadTrack = reloadTrack,
		reloadFill = reloadFill,
		slots = slots,
		reloadHint = reloadHint,
	}
end

--[[
	Emplacement d'arme : actif = verre teinté cyan, liseré bas lumineux, texte blanc ;
	inactif = verre sombre et texte atténué.
]]
function HudWidgets.styleSlot(slot: WeaponSlot, active: boolean)
	slot.gradient.Color = if active
		then ColorSequence.new(colors.primaryDeep, colors.glass)
		else ColorSequence.new(colors.glassLight, colors.glass)
	slot.glow.Visible = active
	slot.name.TextTransparency = if active then 0 else 0.45
	slot.key.TextColor3 = if active then colors.primary else colors.textDim
end

--[[
	Cartouches du chargeur : une case par balle (≤ 40), sinon une barre continue. Ne
	reconstruit que si la capacité change ; ensuite seul l'état plein / vide est mis à jour.
]]
function HudWidgets.renderPips(pips: Frame, mag: number, capacity: number)
	local count = if capacity > MAX_PIPS then 1 else math.max(capacity, 0)
	local cells: { Frame } = {}
	for _, child in pips:GetChildren() do
		if child:IsA("Frame") then
			table.insert(cells, child)
		end
	end
	if #cells ~= count or pips:GetAttribute("Capacity") ~= capacity then
		for _, cell in cells do
			cell:Destroy()
		end
		table.clear(cells)
		pips:SetAttribute("Capacity", capacity)
		local width = if count <= 1
			then PIP_AREA
			else math.clamp(math.floor((PIP_AREA - 2 * (count - 1)) / count), 3, 9)
		for index = 1, count do
			local cell = UI.frame({
				BackgroundColor3 = WHITE,
				Size = UDim2.fromOffset(width, PIP_HEIGHT),
				ZIndex = 2,
				LayoutOrder = index,
				Parent = pips,
			})
			UI.corner(1, cell)
			if count == 1 then
				cell.BackgroundTransparency = 0.82
				UI.frame({
					Name = "Fill",
					BackgroundColor3 = WHITE,
					Size = UDim2.fromScale(1, 1),
					ZIndex = 2,
					Parent = cell,
				})
			end
			table.insert(cells, cell)
		end
	end
	if count == 1 and capacity > MAX_PIPS then
		local fill = cells[1]:FindFirstChild("Fill")
		if fill and fill:IsA("Frame") then
			fill.Size = UDim2.fromScale(math.clamp(mag / capacity, 0, 1), 1)
		end
		return
	end
	-- Les balles restantes sont à droite (le chargeur se vide de gauche à droite).
	for index, cell in cells do
		local loaded = index > count - mag
		cell.BackgroundTransparency = if loaded then 0.05 else 0.8
	end
end

---------------------------------------------------------------------------------------------
-- Barre de match (haut-centre)
---------------------------------------------------------------------------------------------

export type MatchBar = {
	root: Frame,
	timer: TextLabel,
	round: TextLabel,
	scoreLeft: TextLabel,
	scoreRight: TextLabel,
	sideLeft: TextLabel,
	sideRight: TextLabel,
	stripLeft: Frame,
	stripRight: Frame,
	pipsLeft: Frame,
	pipsRight: Frame,
}

local MATCH_SIDE_W, MATCH_TIMER_W, MATCH_H = 200, 112, 54

function HudWidgets.matchBar(parent: Instance): MatchBar
	-- Chrono au centre, équipes de part et d'autre en verre biseauté symétrique (« \ » à
	-- gauche, « / » à droite) : la barre se lit comme un seul bloc, pas trois boîtes.
	local root = UI.frame({
		Name = "MatchBar",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.fromOffset(MATCH_SIDE_W * 2 + MATCH_TIMER_W, 76),
		Parent = parent,
	})
	local center = UI.glass(MATCH_TIMER_W, MATCH_H, 1, {
		Name = "Timer",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		ZIndex = 2,
		Parent = root,
	}).root
	local edge = center:FindFirstChild("Edge")
	if edge then
		edge:Destroy()
	end
	glowLine(center, 0, WHITE).BackgroundTransparency = 0.6
	local timer = label({
		Name = "Time",
		Text = "1:40",
		FontFace = fonts.number,
		TextSize = 32,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = center,
	})
	HudWidgets.textShadow(timer, 0.6)
	local round = label({
		Name = "Round",
		Text = "MANCHE 1",
		FontFace = fonts.heading,
		TextSize = 11,
		TextColor3 = colors.textDim,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, MATCH_H + 4),
		Size = UDim2.fromOffset(420, 14),
		Parent = root,
	})
	HudWidgets.textShadow(round, 0.5)
	local function side(direction: number): (TextLabel, TextLabel, Frame, Frame)
		local left = direction < 0
		local plate = UI.glass(MATCH_SIDE_W, MATCH_H - 6, 14, {
			Name = if left then "Ally" else "Enemy",
			AnchorPoint = Vector2.new(if left then 1 else 0, 0),
			Position = UDim2.new(0.5, direction * (MATCH_TIMER_W / 2 - 1), 0, 3),
			Parent = root,
		}, left)
		local box = plate.root
		local strip = UI.frame({
			Name = "Strip",
			BackgroundColor3 = if left then colors.ally else colors.enemy,
			AnchorPoint = Vector2.new(if left then 1 else 0, 1),
			Position = UDim2.fromScale(if left then 1 else 0, 1),
			Size = UDim2.new(1, -16, 0, 3),
			ZIndex = 3,
			Parent = box,
		})
		local score = label({
			Name = "Score",
			Text = "0",
			FontFace = fonts.number,
			TextSize = 32,
			TextXAlignment = if left then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left,
			AnchorPoint = Vector2.new(if left then 1 else 0, 0),
			Position = UDim2.new(if left then 1 else 0, if left then -14 else 14, 0, 0),
			Size = UDim2.fromOffset(52, MATCH_H - 8),
			ZIndex = 2,
			Parent = box,
		})
		HudWidgets.textShadow(score, 0.6)
		local name = label({
			Name = "Side",
			Text = "",
			FontFace = fonts.headingHeavy,
			TextSize = 13,
			TextXAlignment = if left then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left,
			AnchorPoint = Vector2.new(if left then 1 else 0, 0),
			Position = UDim2.new(if left then 1 else 0, if left then -74 else 74, 0, 7),
			Size = UDim2.fromOffset(MATCH_SIDE_W - 100, 16),
			ZIndex = 2,
			Parent = box,
		})
		local pips = UI.frame({
			Name = "Alive",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(if left then 1 else 0, 0),
			Position = UDim2.new(if left then 1 else 0, if left then -74 else 74, 0, 29),
			Size = UDim2.fromOffset(MATCH_SIDE_W - 100, 6),
			ZIndex = 2,
			Parent = box,
		})
		UI.list(
			pips,
			Enum.FillDirection.Horizontal,
			4,
			if left then Enum.HorizontalAlignment.Right else Enum.HorizontalAlignment.Left
		)
		return score, name, strip, pips
	end
	local scoreLeft, sideLeft, stripLeft, pipsLeft = side(-1)
	local scoreRight, sideRight, stripRight, pipsRight = side(1)
	return {
		root = root,
		timer = timer,
		round = round,
		scoreLeft = scoreLeft,
		scoreRight = scoreRight,
		sideLeft = sideLeft,
		sideRight = sideRight,
		stripLeft = stripLeft,
		stripRight = stripRight,
		pipsLeft = pipsLeft,
		pipsRight = pipsRight,
	}
end

function HudWidgets.aliveCell(container: Frame, index: number): Frame
	local frame = UI.frame({ Size = UDim2.fromOffset(16, 5), LayoutOrder = index, Parent = container })
	UI.corner(1, frame)
	UI.stroke(frame, BLACK, 1, 0.6)
	return frame
end

--[[ Joueurs en vie d'une équipe : une barrette par joueur, pleine si vivant. ]]
function HudWidgets.renderAlive(container: Frame, alive: number, total: number, color: Color3)
	local cells: { Frame } = {}
	for _, child in container:GetChildren() do
		if child:IsA("Frame") then
			table.insert(cells, child)
		end
	end
	for index = 1, math.max(total, #cells) do
		local cell = cells[index]
		if index > total then
			if cell then
				cell:Destroy()
			end
			continue
		end
		local frame = cell or HudWidgets.aliveCell(container, index)
		frame.BackgroundColor3 = if index <= alive then color else WHITE
		frame.BackgroundTransparency = if index <= alive then 0 else 0.75
	end
end

---------------------------------------------------------------------------------------------
-- Killfeed, toasts, interaction, bannière, confirmation d'élimination
---------------------------------------------------------------------------------------------

--[[ Ligne du killfeed (texte riche déjà coloré) ; `mine` : liseré pour mes kills / ma mort. ]]
function HudWidgets.killfeedEntry(parent: Instance, richText: string, mine: Color3?): Frame
	-- Bande de verre fondue vers la gauche (le killfeed est aligné à droite) : pas de boîte.
	local entry = UI.frame({
		Name = "Kill",
		BackgroundColor3 = if mine then colors.glassLight else colors.glass,
		BackgroundTransparency = 0,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 28),
		Parent = parent,
	})
	UI.gradient(
		entry,
		ColorSequence.new(WHITE),
		0,
		NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.25, if mine then 0.3 else 0.5),
			NumberSequenceKeypoint.new(1, if mine then 0.15 else 0.35),
		})
	)
	UI.padding(entry, 26, if mine then 14 else 10, 0, 0)
	if mine then
		UI.frame({
			Name = "Accent",
			BackgroundColor3 = mine,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 14, 0, 0),
			Size = UDim2.new(0, 3, 1, 0),
			Parent = entry,
		})
	end
	label({
		Name = "Text",
		Text = richText,
		FontFace = fonts.bodyBold,
		TextSize = 15,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		Parent = entry,
	})
	return entry
end

function HudWidgets.toast(parent: Instance, title: string, text: string, color: Color3): Frame
	local glass = UI.glass(360, 58, 12, { Name = "Toast" })
	local toast = glass.root
	local edge = toast:FindFirstChild("Edge")
	if edge and edge:IsA("Frame") then
		edge.BackgroundColor3 = color
	end
	glowLine(toast, 12, color)
	label({
		Name = "Title",
		Text = title,
		FontFace = fonts.headingHeavy,
		TextSize = 11,
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(22, 9),
		Size = UDim2.new(1, -40, 0, 14),
		ZIndex = 2,
		Parent = toast,
	})
	label({
		Name = "Body",
		Text = text,
		FontFace = fonts.bodyBold,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(18, 25),
		Size = UDim2.new(1, -40, 0, 24),
		ZIndex = 2,
		Parent = toast,
	})
	toast.Parent = parent
	return toast
end

export type Interaction = { root: Frame, key: TextLabel, text: TextLabel, fill: Frame }

--[[ Invite contextuelle : touche en pastille + action + progression. ]]
function HudWidgets.interaction(parent: Instance): Interaction
	local root = UI.frame({
		Name = "Interaction",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, 64),
		Size = UDim2.fromOffset(460, 44),
		Visible = false,
		Parent = parent,
	})
	local row = UI.frame({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), Parent = root })
	UI.list(row, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	local key = label({
		Name = "Key",
		Text = "F",
		FontFace = fonts.bodyBold,
		TextSize = 15,
		BackgroundColor3 = colors.shadow,
		BackgroundTransparency = 0.25,
		Size = UDim2.fromOffset(28, 28),
		LayoutOrder = 1,
		Parent = row,
	})
	UI.corner(5, key)
	UI.stroke(key, WHITE, 1, 0.45)
	local text = label({
		Name = "Action",
		Text = "",
		TextSize = 16,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 28),
		LayoutOrder = 2,
		Parent = row,
	})
	HudWidgets.textShadow(text, 0.5)
	local track = UI.frame({
		Name = "Progress",
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.8,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 38),
		Size = UDim2.fromOffset(240, 3),
		Parent = root,
	})
	local fill = UI.frame({ BackgroundColor3 = colors.warning, Size = UDim2.fromScale(0, 1), Parent = track })
	return { root = root, key = key, text = text, fill = fill }
end

export type Banner = { title: TextLabel, subtitle: TextLabel, line: Frame }

function HudWidgets.banner(parent: Instance): Banner
	local title = label({
		Name = "BannerTitle",
		Text = "",
		FontFace = fonts.display,
		TextSize = 46,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.27),
		Size = UDim2.fromOffset(900, 52),
		TextTransparency = 1,
		Parent = parent,
	})
	HudWidgets.textShadow(title, 0.55)
	local line = UI.frame({
		Name = "BannerLine",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.27, 32),
		Size = UDim2.fromOffset(0, 2),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	UI.gradient(
		line,
		ColorSequence.new(WHITE),
		0,
		NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.25, 0),
			NumberSequenceKeypoint.new(0.75, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
	)
	local subtitle = label({
		Name = "BannerSubtitle",
		Text = "",
		FontFace = fonts.body,
		TextSize = 19,
		TextColor3 = colors.text,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.27, 54),
		Size = UDim2.fromOffset(900, 24),
		TextTransparency = 1,
		Parent = parent,
	})
	HudWidgets.textShadow(subtitle, 0.6)
	return { title = title, subtitle = subtitle, line = line }
end

export type KillConfirm = { text: TextLabel, pips: Frame }

function HudWidgets.killConfirm(parent: Instance): KillConfirm
	local text = label({
		Name = "KillConfirm",
		Text = "",
		FontFace = fonts.bodyBold,
		TextSize = 18,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 122),
		Size = UDim2.fromOffset(700, 24),
		TextTransparency = 1,
		Parent = parent,
	})
	HudWidgets.textShadow(text, 0.45)
	local pips = UI.frame({
		Name = "KillPips",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 150),
		Size = UDim2.fromOffset(200, 16),
		Parent = parent,
	})
	UI.list(pips, Enum.FillDirection.Horizontal, 9, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	return { text = text, pips = pips }
end

function HudWidgets.killPip(parent: Instance, index: number, color: Color3): Frame
	local pip = UI.frame({
		BackgroundColor3 = color,
		Size = UDim2.fromOffset(11, 11),
		Rotation = 45,
		LayoutOrder = index,
		Parent = parent,
	})
	UI.corner(2, pip)
	return pip
end

---------------------------------------------------------------------------------------------
-- Stand de tir
---------------------------------------------------------------------------------------------

export type StatPanel = { root: Frame, values: { [string]: TextLabel } }

function HudWidgets.statPanel(parent: Instance, title: string, accent: Color3, rows: { { string } }): StatPanel
	local width, rowHeight = 270, 26
	local glass = UI.glass(width, 50 + #rows * rowHeight, 14, {
		Name = "Stats",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 28, 0.45, 0),
		Parent = parent,
	})
	local root = glass.root
	local edge = root:FindFirstChild("Edge")
	if edge and edge:IsA("Frame") then
		edge.BackgroundColor3 = accent
	end
	glowLine(root, 14, accent)
	label({
		Name = "Title",
		Text = title,
		FontFace = fonts.headingHeavy,
		TextSize = 13,
		TextColor3 = accent,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(26, 12),
		Size = UDim2.new(1, -44, 0, 16),
		ZIndex = 2,
		Parent = root,
	})
	local values: { [string]: TextLabel } = {}
	for index, row in rows do
		local y = 38 + (index - 1) * rowHeight
		-- Décalage de chaque ligne vers la droite : elles suivent le biseau du panneau.
		local inset = 22 - (y / (50 + #rows * rowHeight)) * 14
		if index > 1 then
			UI.frame({
				Name = "Rule",
				BackgroundColor3 = WHITE,
				BackgroundTransparency = 0.93,
				Position = UDim2.fromOffset(inset, y - 1),
				Size = UDim2.new(1, -inset - 22, 0, 1),
				ZIndex = 2,
				Parent = root,
			})
		end
		label({
			Name = row[1],
			Text = row[2],
			FontFace = fonts.heading,
			TextSize = 12,
			TextColor3 = colors.textDim,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(inset + 4, y),
			Size = UDim2.new(0.6, 0, 0, rowHeight),
			ZIndex = 2,
			Parent = root,
		})
		values[row[1]] = label({
			Name = row[1] .. "Value",
			Text = "0",
			FontFace = fonts.number,
			TextSize = 18,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -24, 0, y),
			Size = UDim2.new(0.4, 0, 0, rowHeight),
			ZIndex = 2,
			Parent = root,
		})
	end
	return { root = root, values = values }
end

return HudWidgets
