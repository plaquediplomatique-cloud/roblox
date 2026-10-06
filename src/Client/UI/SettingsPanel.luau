--!strict
--[[
	SettingsPanel — écran de réglages complet, partagé par le lobby et le menu de match.

	Onglets : CONTRÔLES · RÉTICULE (aperçu en direct) · VIDÉO · AUDIO · HUD · TOUCHES.
	Chaque contrôle écrit immédiatement via SettingsController.update (application en
	direct, sauvegarde serveur temporisée et validée par Settings.validate) : aucune
	valeur hors bornes ne peut être produite par l'interface (bornes = celles du serveur).
]]

local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Settings = require(Shared.Config.Settings)
local Theme = require(Shared.Config.Theme)
local UI = require(script.Parent.UI)
local SettingsController = require(script.Parent.Parent.Controllers.SettingsController)

local colors = Theme.colors
local fonts = Theme.fonts

local SettingsPanel = {}

local ACTION_NAMES: { [string]: string } = {
	Fire = "Tirer",
	Aim = "Viser",
	Reload = "Recharger",
	Jump = "Sauter",
	Crouch = "S'accroupir / glisser",
	Sprint = "Sprinter",
	Walk = "Marcher (silencieux)",
	LeanLeft = "Pencher à gauche",
	LeanRight = "Pencher à droite",
	Primary = "Arme principale",
	Secondary = "Arme secondaire",
	Melee = "Lame",
	Inspect = "Inspecter l'arme",
	Interact = "Interagir (uplink)",
	Scoreboard = "Tableau des scores",
	Menu = "Menu",
	Options = "Options rapides (sensibilité)",
	Emote = "Emote",
}

local CROSSHAIR_COLORS = { "#3DE1FF", "#3DFFA2", "#FFFFFF", "#FFD24A", "#FF4655", "#B04DFF", "#FF7AE0" }
local COLOR_NAMES: { [string]: string } = {
	["#3DE1FF"] = "Cyan",
	["#3DFFA2"] = "Vert",
	["#FFFFFF"] = "Blanc",
	["#FFD24A"] = "Or",
	["#FF4655"] = "Rouge",
	["#B04DFF"] = "Violet",
	["#FF7AE0"] = "Rose",
}

local function update(mutator: (Types.SettingsData) -> ())
	SettingsController.update(mutator)
end

local function percent(value: number): string
	return string.format("%d %%", math.floor(value * 100 + 0.5))
end

local function scroller(parent: Instance): ScrollingFrame
	local frame = Instance.new("ScrollingFrame")
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromScale(1, 1)
	frame.CanvasSize = UDim2.new()
	frame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	frame.ScrollBarThickness = 4
	frame.ScrollBarImageColor3 = colors.primary
	frame.Visible = false
	frame.Parent = parent
	UI.list(frame, Enum.FillDirection.Vertical, 6)
	UI.padding(frame, 4, 14, 4, 4)
	return frame
end

local function section(parent: Instance, title: string)
	UI.text({
		Text = title,
		FontFace = fonts.heading,
		TextSize = 14,
		TextColor3 = colors.primary,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 26),
		Parent = parent,
	})
end

local function add(parent: Instance, row: Frame)
	row.Parent = parent
end

---------------------------------------------------------------------------------------------
-- Onglets
---------------------------------------------------------------------------------------------

local function buildControls(page: ScrollingFrame, s: Types.SettingsData)
	section(page, "SOURIS / MANETTE")
	add(
		page,
		UI.slider("Sensibilité", 0.05, 5, 0.01, s.Controls.Sensitivity, function(v)
			update(function(d)
				d.Controls.Sensitivity = v
			end)
		end, nil, { log = true, editable = true, nudge = 0.01 })
	)
	add(
		page,
		UI.slider("Multiplicateur visée", 0.2, 2, 0.01, s.Controls.AdsMultiplier, function(v)
			update(function(d)
				d.Controls.AdsMultiplier = v
			end)
		end, nil, { editable = true, nudge = 0.05 })
	)
	add(
		page,
		UI.slider("Multiplicateur lunette", 0.2, 2, 0.01, s.Controls.ScopeMultiplier, function(v)
			update(function(d)
				d.Controls.ScopeMultiplier = v
			end)
		end, nil, { editable = true, nudge = 0.05 })
	)
	add(
		page,
		UI.toggle("Inverser l'axe Y", s.Controls.InvertY, function(v)
			update(function(d)
				d.Controls.InvertY = v
			end)
		end)
	)
	section(page, "COMPORTEMENT")
	add(
		page,
		UI.toggle("Visée en bascule", s.Controls.ToggleAds, function(v)
			update(function(d)
				d.Controls.ToggleAds = v
			end)
		end)
	)
	add(
		page,
		UI.toggle("Accroupi en bascule", s.Controls.ToggleCrouch, function(v)
			update(function(d)
				d.Controls.ToggleCrouch = v
			end)
		end)
	)
	add(
		page,
		UI.toggle("Sprint en bascule", s.Controls.ToggleSprint, function(v)
			update(function(d)
				d.Controls.ToggleSprint = v
			end)
		end)
	)
	add(
		page,
		UI.toggle("Marche en bascule", s.Controls.ToggleWalk, function(v)
			update(function(d)
				d.Controls.ToggleWalk = v
			end)
		end)
	)
	add(
		page,
		UI.toggle("Lean (Q / E)", s.Controls.LeanEnabled, function(v)
			update(function(d)
				d.Controls.LeanEnabled = v
			end)
		end)
	)
	add(
		page,
		UI.toggle("Rechargement automatique", s.Controls.AutoReload, function(v)
			update(function(d)
				d.Controls.AutoReload = v
			end)
		end)
	)
end

local function buildCrosshairPreview(parent: Instance): () -> ()
	local box = UI.frame({
		BackgroundColor3 = Color3.fromRGB(70, 78, 88),
		Size = UDim2.new(1, 0, 0, 120),
		Parent = parent,
	})
	UI.corner(4, box)
	UI.gradient(box, ColorSequence.new(Color3.fromRGB(120, 130, 140), Color3.fromRGB(30, 34, 40)), 90)
	local center = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(0, 0),
		Parent = box,
	})
	local lines: { Frame } = {}
	for _ = 1, 4 do
		local line = UI.frame({ AnchorPoint = Vector2.new(0.5, 0.5), Parent = center })
		UI.stroke(line, Color3.new(0, 0, 0), 1, 0.5)
		table.insert(lines, line)
	end
	local dot = UI.frame({ AnchorPoint = Vector2.new(0.5, 0.5), Parent = center })
	UI.stroke(dot, Color3.new(0, 0, 0), 1, 0.5)
	local circle = UI.frame({ AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, Parent = center })
	UI.corner(999, circle)
	local circleStroke = UI.stroke(circle, Color3.new(1, 1, 1), 1.5, 0)
	return function()
		local c = SettingsController.get().Crosshair
		local color = Settings.parseHex(c.Color)
		local scale = 2 -- aperçu grossi pour lire les réglages au pixel près
		local gap, length, thickness = c.Gap * scale, c.Length * scale, c.Thickness * scale
		local offsets = {
			Vector2.new(0, -(gap + length / 2)),
			Vector2.new(0, gap + length / 2),
			Vector2.new(-(gap + length / 2), 0),
			Vector2.new(gap + length / 2, 0),
		}
		for index, line in lines do
			local visible = (c.Style == "Classic" or c.Style == "TShape") and not (c.Style == "TShape" and index == 1)
			line.Visible = visible
			line.Size = if index <= 2 then UDim2.fromOffset(thickness, length) else UDim2.fromOffset(length, thickness)
			line.Position = UDim2.fromOffset(offsets[index].X, offsets[index].Y)
			line.BackgroundColor3 = color
			line.BackgroundTransparency = 1 - c.Opacity
			local stroke = line:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Enabled = c.Outline
				stroke.Thickness = c.OutlineThickness * scale
				stroke.Transparency = 1 - c.OutlineOpacity
			end
		end
		dot.Visible = c.Dot or c.Style == "Dot"
		dot.Size = UDim2.fromOffset(c.DotSize * scale, c.DotSize * scale)
		dot.BackgroundColor3 = color
		dot.BackgroundTransparency = 1 - c.Opacity
		circle.Visible = c.Style == "Circle"
		circle.Size = UDim2.fromOffset(math.max(gap * 2, 12), math.max(gap * 2, 12))
		circleStroke.Color = color
		circleStroke.Thickness = math.max(thickness * 0.75, 1)
	end
end

local function buildCrosshair(page: ScrollingFrame, s: Types.SettingsData)
	section(page, "APERÇU")
	local refresh = buildCrosshairPreview(page)
	local function set(mutator: (Types.CrosshairSettings) -> ())
		update(function(d)
			mutator(d.Crosshair)
		end)
		refresh()
	end
	section(page, "FORME")
	add(
		page,
		UI.cycler("Style", Settings.CROSSHAIR_STYLES, s.Crosshair.Style, function(v)
			set(function(c)
				c.Style = v
			end)
		end, function(v: string): string
			local names: { [string]: string } =
				{ Classic = "CLASSIQUE", Dot = "POINT", Circle = "CERCLE", TShape = "EN T" }
			return names[v] or v
		end)
	)
	add(
		page,
		UI.cycler("Couleur", CROSSHAIR_COLORS, s.Crosshair.Color, function(v)
			set(function(c)
				c.Color = v
			end)
		end, function(v: string): string
			return string.upper(COLOR_NAMES[v] or v)
		end)
	)
	add(
		page,
		UI.slider("Opacité", 0.1, 1, 0.05, s.Crosshair.Opacity, function(v)
			set(function(c)
				c.Opacity = v
			end)
		end, percent)
	)
	add(
		page,
		UI.slider("Épaisseur", 1, 6, 1, s.Crosshair.Thickness, function(v)
			set(function(c)
				c.Thickness = v
			end)
		end)
	)
	add(
		page,
		UI.slider("Longueur", 0, 20, 1, s.Crosshair.Length, function(v)
			set(function(c)
				c.Length = v
			end)
		end)
	)
	add(
		page,
		UI.slider("Écart", 0, 20, 1, s.Crosshair.Gap, function(v)
			set(function(c)
				c.Gap = v
			end)
		end)
	)
	add(
		page,
		UI.toggle("Point central", s.Crosshair.Dot, function(v)
			set(function(c)
				c.Dot = v
			end)
		end)
	)
	add(
		page,
		UI.slider("Taille du point", 1, 8, 1, s.Crosshair.DotSize, function(v)
			set(function(c)
				c.DotSize = v
			end)
		end)
	)
	section(page, "CONTOUR ET COMPORTEMENT")
	add(
		page,
		UI.toggle("Contour", s.Crosshair.Outline, function(v)
			set(function(c)
				c.Outline = v
			end)
		end)
	)
	add(
		page,
		UI.slider("Épaisseur du contour", 0, 3, 1, s.Crosshair.OutlineThickness, function(v)
			set(function(c)
				c.OutlineThickness = v
			end)
		end)
	)
	add(
		page,
		UI.slider("Opacité du contour", 0, 1, 0.05, s.Crosshair.OutlineOpacity, function(v)
			set(function(c)
				c.OutlineOpacity = v
			end)
		end, percent)
	)
	add(
		page,
		UI.toggle("Dynamique (dispersion réelle)", s.Crosshair.Dynamic, function(v)
			set(function(c)
				c.Dynamic = v
			end)
		end)
	)
	refresh()
end

local function buildVideo(page: ScrollingFrame, s: Types.SettingsData)
	section(page, "CAMÉRA")
	add(
		page,
		UI.slider("Champ de vision", 60, 95, 1, s.Video.Fov, function(v)
			update(function(d)
				d.Video.Fov = v
			end)
		end, function(v: number): string
			return string.format("%d°", v)
		end)
	)
	add(
		page,
		UI.slider("Secousses caméra", 0, 1.5, 0.05, s.Video.CameraShake, function(v)
			update(function(d)
				d.Video.CameraShake = v
			end)
		end, percent)
	)
	add(
		page,
		UI.slider("Balancement de tête", 0, 1.5, 0.05, s.Video.HeadBob, function(v)
			update(function(d)
				d.Video.HeadBob = v
			end)
		end, percent)
	)
	add(
		page,
		UI.slider("Balancement de l'arme", 0, 1.5, 0.05, s.Video.ViewmodelBob, function(v)
			update(function(d)
				d.Video.ViewmodelBob = v
			end)
		end, percent)
	)
	section(page, "POST-TRAITEMENT")
	add(
		page,
		UI.toggle("Bloom", s.Video.Bloom, function(v)
			update(function(d)
				d.Video.Bloom = v
			end)
		end)
	)
	add(
		page,
		UI.toggle("Profondeur de champ", s.Video.DepthOfField, function(v)
			update(function(d)
				d.Video.DepthOfField = v
			end)
		end)
	)
	add(
		page,
		UI.toggle("Rayons de soleil", s.Video.SunRays, function(v)
			update(function(d)
				d.Video.SunRays = v
			end)
		end)
	)
	add(
		page,
		UI.toggle("Flashs réduits (photosensibilité)", s.Video.ReducedFlashes, function(v)
			update(function(d)
				d.Video.ReducedFlashes = v
			end)
		end)
	)
	add(
		page,
		UI.toggle("Météo et particules d'ambiance", s.Video.Weather, function(v)
			update(function(d)
				d.Video.Weather = v
			end)
		end)
	)
	add(
		page,
		UI.toggle("Afficher les FPS", s.Video.ShowFps, function(v)
			update(function(d)
				d.Video.ShowFps = v
			end)
		end)
	)
end

local function buildAudio(page: ScrollingFrame, s: Types.SettingsData)
	section(page, "VOLUMES")
	for _, key in { "Master", "Music", "Sfx", "Ui" } do
		local labels: { [string]: string } =
			{ Master = "Général", Music = "Musique", Sfx = "Effets", Ui = "Interface" }
		add(
			page,
			UI.slider(labels[key], 0, 1, 0.05, (s.Audio :: any)[key], function(v)
				update(function(d)
					(d.Audio :: any)[key] = v
				end)
			end, percent)
		)
	end
	section(page, "RETOURS DE COMBAT")
	add(
		page,
		UI.toggle("Son de touche", s.Audio.HitSound, function(v)
			update(function(d)
				d.Audio.HitSound = v
			end)
		end)
	)
	add(
		page,
		UI.toggle("Son d'élimination", s.Audio.KillSound, function(v)
			update(function(d)
				d.Audio.KillSound = v
			end)
		end)
	)
end

local function buildHud(page: ScrollingFrame, s: Types.SettingsData)
	section(page, "AFFICHAGE")
	add(
		page,
		UI.slider("Échelle du HUD", 0.7, 1.3, 0.05, s.Hud.Scale, function(v)
			update(function(d)
				d.Hud.Scale = v
			end)
		end, percent)
	)
	add(
		page,
		UI.toggle("Chiffres de dégâts", s.Hud.DamageNumbers, function(v)
			update(function(d)
				d.Hud.DamageNumbers = v
			end)
		end)
	)
	add(
		page,
		UI.toggle("Hitmarkers", s.Hud.Hitmarkers, function(v)
			update(function(d)
				d.Hud.Hitmarkers = v
			end)
		end)
	)
	add(
		page,
		UI.toggle("Boussole", s.Hud.Compass, function(v)
			update(function(d)
				d.Hud.Compass = v
			end)
		end)
	)
	add(
		page,
		UI.toggle("Statistiques réseau", s.Hud.NetStats, function(v)
			update(function(d)
				d.Hud.NetStats = v
			end)
		end)
	)
	add(
		page,
		UI.toggle("Killcam", s.Hud.Killcam, function(v)
			update(function(d)
				d.Hud.Killcam = v
			end)
		end)
	)
	section(page, "ACCESSIBILITÉ")
	add(
		page,
		UI.cycler("Couleur des ennemis", Settings.ENEMY_COLORS, s.Hud.EnemyColor, function(v)
			update(function(d)
				d.Hud.EnemyColor = v
			end)
		end, function(v: string): string
			local names: { [string]: string } =
				{ Red = "ROUGE", Yellow = "JAUNE (deutéranopie)", Purple = "VIOLET (tritanopie)" }
			return names[v] or v
		end)
	)
end

local function keyName(input: InputObject): string?
	local kind = input.UserInputType
	if kind == Enum.UserInputType.MouseButton1 then
		return "MouseButton1"
	elseif kind == Enum.UserInputType.MouseButton2 then
		return "MouseButton2"
	elseif kind == Enum.UserInputType.MouseButton3 then
		return "MouseButton3"
	elseif kind == Enum.UserInputType.Keyboard and input.KeyCode.Name ~= "Unknown" then
		return input.KeyCode.Name
	end
	return nil
end

local function buildKeybinds(page: ScrollingFrame)
	section(page, "CLAVIER / SOURIS — cliquez puis appuyez sur une touche (Échap : annuler)")
	local buttons: { [string]: TextButton } = {}
	local listening: string? = nil
	local function render()
		local binds = SettingsController.get().Keybinds
		for action, button in buttons do
			button.Text = if listening == action then "…" else (binds[action] or "—")
			button.TextColor3 = if listening == action then colors.warning else colors.text
		end
	end
	for _, action in Settings.ACTIONS do
		local row = UI.frame({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 38), Parent = page })
		UI.text({
			Text = ACTION_NAMES[action] or action,
			TextXAlignment = Enum.TextXAlignment.Left,
			FontFace = fonts.bodyBold,
			TextSize = 16,
			TextColor3 = colors.textDim,
			Size = UDim2.fromScale(0.55, 1),
			Parent = row,
		})
		local button = UI.button({
			Text = "",
			FontFace = fonts.monoBold,
			TextSize = 15,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(1, 0.5),
			Size = UDim2.fromOffset(190, 30),
			Parent = row,
		})
		UI.corner(3, button)
		UI.stroke(button, colors.stroke, 1, 0.2)
		buttons[action] = button
		button.Activated:Connect(function()
			listening = action
			UI.playSound("UI.Click")
			render()
		end)
	end
	UserInputService.InputBegan:Connect(function(input: InputObject)
		local action = listening
		if not action then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape then
			listening = nil
			render()
			return
		end
		local name = keyName(input)
		if not name then
			return
		end
		listening = nil
		update(function(d)
			-- Conflit : la touche passe à cette action, l'ancienne action récupère l'ancienne touche.
			local previous = d.Keybinds[action]
			for other, key in d.Keybinds do
				if key == name and other ~= action then
					d.Keybinds[other] = previous
				end
			end
			d.Keybinds[action] = name
		end)
		UI.playSound("UI.Confirm")
		render()
	end)
	render()
end

---------------------------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------------------------

--[[ Construit le panneau complet dans `parent` (qui fixe la taille). ]]
function SettingsPanel.build(parent: Instance): Frame
	local s = SettingsController.get()
	local root = UI.frame({ BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = parent })
	local tabs = UI.frame({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), Parent = root })
	UI.list(tabs, Enum.FillDirection.Horizontal, 6)
	local body = UI.frame({
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 52),
		Size = UDim2.new(1, 0, 1, -110),
		Parent = root,
	})
	local pages: { [string]: ScrollingFrame } = {}
	local tabButtons: { [string]: TextButton } = {}
	local order = { "CONTRÔLES", "RÉTICULE", "VIDÉO", "AUDIO", "HUD", "TOUCHES" }
	local function select(name: string)
		for pageName, page in pages do
			page.Visible = pageName == name
		end
		for tabName, button in tabButtons do
			local active = tabName == name
			button.BackgroundColor3 = if active then colors.primary else colors.panelLight
			button.TextColor3 = if active then colors.void else colors.textDim
		end
	end
	for index, name in order do
		local page = scroller(body)
		pages[name] = page
		local button = UI.button({
			Text = name,
			FontFace = fonts.heading,
			TextSize = 15,
			Size = UDim2.fromOffset(128, 36),
			LayoutOrder = index,
			Parent = tabs,
		})
		UI.corner(3, button)
		tabButtons[name] = button
		button.Activated:Connect(function()
			UI.playSound("UI.Click")
			select(name)
		end)
	end
	buildControls(pages["CONTRÔLES"], s)
	buildCrosshair(pages["RÉTICULE"], s)
	buildVideo(pages["VIDÉO"], s)
	buildAudio(pages["AUDIO"], s)
	buildHud(pages["HUD"], s)
	buildKeybinds(pages["TOUCHES"])
	local reset = UI.actionButton("RÉINITIALISER", "Ghost", function()
		SettingsController.reset()
		-- Reconstruction pour refléter les valeurs par défaut.
		local host = root.Parent
		root:Destroy()
		if host then
			SettingsPanel.build(host)
		end
	end, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromOffset(200, 42),
		Parent = root,
	})
	reset.TextSize = 15
	select("CONTRÔLES")
	return root
end

return SettingsPanel
