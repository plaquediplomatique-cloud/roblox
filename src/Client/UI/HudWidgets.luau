--!strict
--[[
	HudWidgets — éléments visuels du HUD de combat : construction seule, aucune logique.

	HUDController crée ces éléments puis met à jour leurs champs ; tools/ui_preview.luau les
	construit hors Studio et tools/render_ui.py en fait une image (docs/renders/hud_*.png)
	pour juger la composition sans lancer le jeu.

	Direction : minimal et premium (« futuriste froid »).
	  * aucune boîte cerclée : des plaques d'ombre en dégradé diagonal derrière les blocs,
	    nulles aux bords (pas d'arête visible) ;
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
-- Santé et bouclier (bas-gauche)
---------------------------------------------------------------------------------------------

export type Vitals = {
	root: Frame,
	health: TextLabel,
	armor: TextLabel,
	healthBar: SegmentBar,
	armorBar: SegmentBar,
}

function HudWidgets.vitals(parent: Instance): Vitals
	HudWidgets.shadow(parent, {
		Name = "VitalsShadow",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, -80, 1, 80),
		Size = UDim2.fromOffset(1000, 1000),
	}, -45, 0.62)
	local root = UI.frame({
		Name = "Vitals",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 40, 1, -34),
		Size = UDim2.fromOffset(360, 64),
		Parent = parent,
	})
	-- Croix de santé (deux barres) devant le chiffre.
	local cross = UI.frame({
		Name = "Cross",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 30),
		Size = UDim2.fromOffset(16, 16),
		Parent = root,
	})
	for _, size in { UDim2.fromOffset(16, 5), UDim2.fromOffset(5, 16) } do
		local bar = UI.frame({
			BackgroundColor3 = colors.text,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = size,
			Parent = cross,
		})
		UI.corner(1, bar)
	end
	local health = label({
		Name = "Health",
		Text = "100",
		FontFace = fonts.number,
		TextSize = 58,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		Position = UDim2.fromOffset(24, 0),
		Size = UDim2.fromOffset(112, 60),
		Parent = root,
	})
	HudWidgets.textShadow(health)
	local armor = label({
		Name = "Armor",
		Text = "50",
		FontFace = fonts.number,
		TextSize = 18,
		TextColor3 = colors.armor,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(160, 4),
		Size = UDim2.fromOffset(60, 20),
		Parent = root,
	})
	HudWidgets.textShadow(armor)
	local armorIcon = label({
		Name = "ArmorIcon",
		Text = "◆",
		FontFace = fonts.heading,
		TextSize = 13,
		TextColor3 = colors.armor,
		Position = UDim2.fromOffset(144, 5),
		Size = UDim2.fromOffset(14, 18),
		Parent = root,
	})
	armorIcon.TextXAlignment = Enum.TextXAlignment.Left
	local caption = label({
		Name = "Caption",
		Text = "BOUCLIER",
		FontFace = fonts.heading,
		TextSize = 11,
		TextColor3 = colors.text,
		TextTransparency = 0.3,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 8),
		Size = UDim2.fromOffset(120, 14),
		Parent = root,
	})
	HudWidgets.textShadow(caption, 0.55)
	local armorBar = HudWidgets.segmentBar(colors.armor, 2, {
		Name = "ArmorBar",
		Position = UDim2.fromOffset(144, 30),
		Size = UDim2.new(1, -144, 0, 5),
		Parent = root,
	})
	local healthBar = HudWidgets.segmentBar(colors.health, 4, {
		Name = "HealthBar",
		Position = UDim2.fromOffset(144, 40),
		Size = UDim2.new(1, -144, 0, 12),
		Parent = root,
	})
	return { root = root, health = health, armor = armor, healthBar = healthBar, armorBar = armorBar }
end

---------------------------------------------------------------------------------------------
-- Munitions et arme (bas-droite)
---------------------------------------------------------------------------------------------

export type Ammo = {
	root: Frame,
	weaponName: TextLabel,
	fireMode: TextLabel,
	mag: TextLabel,
	reserve: TextLabel,
	pips: Frame,
	reloadTrack: Frame,
	reloadFill: Frame,
	slots: { [string]: TextLabel },
	reloadHint: TextLabel,
}

local MAX_PIPS = 40
local PIP_AREA = 300

function HudWidgets.ammo(parent: Instance): Ammo
	HudWidgets.shadow(parent, {
		Name = "AmmoShadow",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 80, 1, 80),
		Size = UDim2.fromOffset(1000, 1000),
	}, -135, 0.62)
	local root = UI.frame({
		Name = "Ammo",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -40, 1, -30),
		Size = UDim2.fromOffset(380, 126),
		Parent = parent,
	})
	local header = UI.frame({
		Name = "Header",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 20),
		Parent = root,
	})
	UI.list(header, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)
	local fireMode = chip({
		Name = "FireMode",
		Text = "AUTO",
		TextSize = 11,
		TextColor3 = colors.primary,
		BackgroundTransparency = 0.88,
		BackgroundColor3 = colors.primary,
		Size = UDim2.fromOffset(0, 18),
		LayoutOrder = 1,
		Parent = header,
	}, 6)
	local weaponName = label({
		Name = "WeaponName",
		Text = "VK-12 VEKTOR",
		TextSize = 15,
		TextColor3 = colors.text,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 20),
		LayoutOrder = 2,
		Parent = header,
	})
	HudWidgets.textShadow(weaponName, 0.75)
	local mag = label({
		Name = "Mag",
		Text = "30",
		FontFace = fonts.number,
		TextSize = 62,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -78, 0, 18),
		Size = UDim2.fromOffset(170, 62),
		Parent = root,
	})
	HudWidgets.textShadow(mag)
	local reserve = label({
		Name = "Reserve",
		Text = "/ 90",
		FontFace = fonts.number,
		TextSize = 24,
		TextColor3 = colors.text,
		TextTransparency = 0.4,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 18),
		Size = UDim2.fromOffset(72, 56),
		Parent = root,
	})
	HudWidgets.textShadow(reserve, 0.75)
	local pips = UI.frame({
		Name = "Pips",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 84),
		Size = UDim2.fromOffset(PIP_AREA, 10),
		Parent = root,
	})
	UI.list(pips, Enum.FillDirection.Horizontal, 2, Enum.HorizontalAlignment.Right)
	local reloadTrack = UI.frame({
		Name = "Reload",
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.8,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 97),
		Size = UDim2.fromOffset(PIP_AREA, 2),
		Visible = false,
		Parent = root,
	})
	local reloadFill = UI.frame({
		BackgroundColor3 = colors.primary,
		Size = UDim2.fromScale(0, 1),
		Parent = reloadTrack,
	})
	local slotRow = UI.frame({
		Name = "Slots",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.new(1, 0, 0, 22),
		Parent = root,
	})
	UI.list(slotRow, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)
	local slots: { [string]: TextLabel } = {}
	for index, slotName in { "Primary", "Secondary", "Melee" } do
		slots[slotName] = chip({
			Name = slotName,
			Text = tostring(index) .. "  —",
			TextSize = 12,
			BackgroundColor3 = colors.shadow,
			Size = UDim2.fromOffset(0, 22),
			LayoutOrder = index,
			Parent = slotRow,
		}, 8)
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

--[[ Emplacement d'arme : actif = pastille sombre et texte blanc, sinon atténué. ]]
function HudWidgets.styleSlot(slot: TextLabel, active: boolean)
	slot.BackgroundColor3 = colors.shadow
	slot.BackgroundTransparency = if active then 0.2 else 0.55
	slot.TextColor3 = colors.text
	slot.TextTransparency = if active then 0 else 0.45
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
				Size = UDim2.fromOffset(width, 10),
				LayoutOrder = index,
				Parent = pips,
			})
			UI.corner(1, cell)
			if count == 1 then
				cell.BackgroundTransparency = 0.82
				UI.frame({ Name = "Fill", BackgroundColor3 = WHITE, Size = UDim2.fromScale(1, 1), Parent = cell })
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

function HudWidgets.matchBar(parent: Instance): MatchBar
	local root = UI.frame({
		Name = "MatchBar",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 14),
		Size = UDim2.fromOffset(520, 86),
		Parent = parent,
	})
	local center = UI.frame({
		Name = "Timer",
		BackgroundColor3 = colors.shadow,
		BackgroundTransparency = 0.3,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(108, 48),
		Parent = root,
	})
	UI.corner(6, center)
	local timer = label({
		Name = "Time",
		Text = "1:40",
		FontFace = fonts.number,
		TextSize = 30,
		Size = UDim2.fromScale(1, 1),
		Parent = center,
	})
	local round = label({
		Name = "Round",
		Text = "MANCHE 1",
		FontFace = fonts.heading,
		TextSize = 11,
		TextColor3 = colors.text,
		TextTransparency = 0.15,
		BackgroundColor3 = colors.shadow,
		BackgroundTransparency = 0.45,
		AutomaticSize = Enum.AutomaticSize.X,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 53),
		Size = UDim2.fromOffset(0, 18),
		Parent = root,
	})
	UI.corner(9, round)
	UI.padding(round, 10, 10, 0, 0)
	local function side(direction: number): (TextLabel, TextLabel, Frame, Frame)
		local anchorX = if direction < 0 then 1 else 0
		local box = UI.frame({
			Name = if direction < 0 then "Ally" else "Enemy",
			BackgroundColor3 = colors.shadow,
			BackgroundTransparency = 0.3,
			AnchorPoint = Vector2.new(anchorX, 0),
			Position = UDim2.new(0.5, direction * 60, 0, 0),
			Size = UDim2.fromOffset(68, 48),
			ClipsDescendants = true,
			Parent = root,
		})
		UI.corner(6, box)
		local score = label({
			Name = "Score",
			Text = "0",
			FontFace = fonts.number,
			TextSize = 30,
			Size = UDim2.new(1, 0, 1, -3),
			Parent = box,
		})
		local strip = UI.frame({
			Name = "Strip",
			BackgroundColor3 = colors.ally,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, 3),
			Parent = box,
		})
		local name = label({
			Name = "Side",
			Text = "",
			FontFace = fonts.heading,
			TextSize = 12,
			TextXAlignment = if direction < 0 then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left,
			AnchorPoint = Vector2.new(anchorX, 0),
			Position = UDim2.new(0.5, direction * 136, 0, 8),
			Size = UDim2.fromOffset(110, 16),
			Parent = root,
		})
		HudWidgets.textShadow(name, 0.6)
		local pips = UI.frame({
			Name = "Alive",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(anchorX, 0),
			Position = UDim2.new(0.5, direction * 136, 0, 30),
			Size = UDim2.fromOffset(110, 6),
			Parent = root,
		})
		UI.list(
			pips,
			Enum.FillDirection.Horizontal,
			4,
			if direction < 0 then Enum.HorizontalAlignment.Right else Enum.HorizontalAlignment.Left
		)
		return score, name, strip, pips
	end
	local scoreLeft, sideLeft, stripLeft, pipsLeft = side(-1)
	local scoreRight, sideRight, stripRight, pipsRight = side(1)
	stripRight.BackgroundColor3 = colors.enemy
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
	local entry = UI.frame({
		Name = "Kill",
		BackgroundColor3 = colors.shadow,
		BackgroundTransparency = if mine then 0.25 else 0.45,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 28),
		Parent = parent,
	})
	UI.corner(4, entry)
	UI.padding(entry, if mine then 14 else 10, 10, 0, 0)
	if mine then
		local accent = UI.frame({
			Name = "Accent",
			BackgroundColor3 = mine,
			Position = UDim2.fromOffset(-14, 4),
			Size = UDim2.new(0, 3, 1, -8),
			Parent = entry,
		})
		UI.corner(1, accent)
	end
	label({
		Name = "Text",
		Text = richText,
		FontFace = fonts.body,
		TextSize = 15,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		Parent = entry,
	})
	return entry
end

function HudWidgets.toast(parent: Instance, title: string, text: string, color: Color3): Frame
	local toast = UI.frame({
		Name = "Toast",
		BackgroundColor3 = colors.shadow,
		BackgroundTransparency = 0.18,
		Size = UDim2.fromOffset(340, 56),
		Parent = parent,
	})
	UI.corner(6, toast)
	local accent = UI.frame({
		BackgroundColor3 = color,
		Position = UDim2.fromOffset(0, 10),
		Size = UDim2.new(0, 3, 1, -20),
		Parent = toast,
	})
	UI.corner(1, accent)
	label({
		Name = "Title",
		Text = title,
		TextSize = 11,
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(16, 8),
		Size = UDim2.new(1, -28, 0, 14),
		Parent = toast,
	})
	label({
		Name = "Body",
		Text = text,
		FontFace = fonts.body,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(16, 24),
		Size = UDim2.new(1, -28, 0, 24),
		Parent = toast,
	})
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
	local root = UI.frame({
		Name = "Stats",
		BackgroundColor3 = colors.shadow,
		BackgroundTransparency = 0.3,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 40, 0.45, 0),
		Size = UDim2.fromOffset(250, 44 + #rows * 24),
		Parent = parent,
	})
	UI.corner(8, root)
	UI.padding(root, 16, 16, 12, 12)
	label({
		Name = "Title",
		Text = title,
		TextSize = 12,
		TextColor3 = accent,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 16),
		Parent = root,
	})
	local values: { [string]: TextLabel } = {}
	for index, row in rows do
		local y = 26 + (index - 1) * 24
		label({
			Name = row[1],
			Text = row[2],
			FontFace = fonts.body,
			TextSize = 14,
			TextColor3 = colors.textDim,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(0, y),
			Size = UDim2.new(0.6, 0, 0, 22),
			Parent = root,
		})
		values[row[1]] = label({
			Name = row[1] .. "Value",
			Text = "0",
			FontFace = fonts.number,
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, y),
			Size = UDim2.new(0.4, 0, 0, 22),
			Parent = root,
		})
	end
	return { root = root, values = values }
end

return HudWidgets
