--!strict
--[[
	UI — kit d'interface déclaratif et typé (aucune dépendance externe).

	* Constructeurs typés (frame, text, button…) + `apply` générique des propriétés.
	* Composants maison : panneau "verre" (fond sombre translucide, liseré, dégradé),
	  bouton premium (survol/clic animés + sons), barre à traînée "fantôme" (santé),
	  slider, interrupteur, sélecteur cyclique — utilisés par le HUD et le lobby.
	* Responsive : chaque ScreenGui reçoit un UIScale piloté par la hauteur d'écran
	  (référence 1080p) × l'échelle HUD des réglages ; ancres et UIAspectRatioConstraint
	  pour un rendu identique sur desktop, tablette et mobile.
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Theme = require(Shared.Config.Theme)

local UI = {}
UI.Theme = Theme

type Props = { [string]: any }

local soundPlayer: (key: string) -> () = function(_key: string) end
local scales: { UIScale } = {}
local userScale = 1

function UI.setSoundPlayer(fn: (key: string) -> ())
	soundPlayer = fn
end

function UI.playSound(key: string)
	soundPlayer(key)
end

function UI.apply(instance: Instance, props: Props?): Instance
	if props then
		local parent = props.Parent
		for key, value in props do
			if key == "Children" then
				for _, child in value :: { Instance } do
					child.Parent = instance
				end
			elseif key ~= "Parent" then
				(instance :: any)[key] = value
			end
		end
		if parent then
			instance.Parent = parent
		end
	end
	return instance
end

function UI.new(className: string, props: Props?): Instance
	return UI.apply(Instance.new(className), props)
end

function UI.frame(props: Props?): Frame
	local frame = Instance.new("Frame")
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = Theme.colors.panel
	UI.apply(frame, props)
	return frame
end

function UI.text(props: Props?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.FontFace = Theme.fonts.body
	label.TextColor3 = Theme.colors.text
	label.TextSize = 16
	label.RichText = true
	UI.apply(label, props)
	return label
end

function UI.button(props: Props?): TextButton
	local button = Instance.new("TextButton")
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.FontFace = Theme.fonts.heading
	button.TextColor3 = Theme.colors.text
	button.TextSize = 16
	button.BackgroundColor3 = Theme.colors.panelLight
	UI.apply(button, props)
	return button
end

function UI.image(props: Props?): ImageLabel
	local image = Instance.new("ImageLabel")
	image.BackgroundTransparency = 1
	image.BorderSizePixel = 0
	UI.apply(image, props)
	return image
end

function UI.corner(radius: number, parent: Instance): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
	return corner
end

function UI.stroke(parent: Instance, color: Color3, thickness: number, transparency: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Transparency = transparency or 0
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

function UI.textStroke(parent: Instance, transparency: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Thickness = 1.5
	stroke.Transparency = transparency or 0.35
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = parent
	return stroke
end

function UI.gradient(
	parent: Instance,
	colors: ColorSequence,
	rotation: number,
	transparency: NumberSequence?
): UIGradient
	local gradient = Instance.new("UIGradient")
	gradient.Color = colors
	gradient.Rotation = rotation
	if transparency then
		gradient.Transparency = transparency
	end
	gradient.Parent = parent
	return gradient
end

function UI.padding(parent: Instance, left: number, right: number?, top: number?, bottom: number?): UIPadding
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, left)
	padding.PaddingRight = UDim.new(0, right or left)
	padding.PaddingTop = UDim.new(0, top or left)
	padding.PaddingBottom = UDim.new(0, bottom or top or left)
	padding.Parent = parent
	return padding
end

function UI.list(
	parent: Instance,
	direction: Enum.FillDirection,
	spacing: number,
	horizontal: Enum.HorizontalAlignment?,
	vertical: Enum.VerticalAlignment?
): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = direction
	layout.Padding = UDim.new(0, spacing)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = horizontal or Enum.HorizontalAlignment.Left
	layout.VerticalAlignment = vertical or Enum.VerticalAlignment.Top
	layout.Parent = parent
	return layout
end

function UI.aspect(parent: Instance, ratio: number): UIAspectRatioConstraint
	local constraint = Instance.new("UIAspectRatioConstraint")
	constraint.AspectRatio = ratio
	constraint.Parent = parent
	return constraint
end

--[[
	Tween d'interface. Respecte GuiService.ReducedMotionEnabled (préférence système
	d'accessibilité) : le mouvement devient instantané, l'état final est identique.
]]
function UI.tween(instance: Instance, info: TweenInfo, goals: Props): Tween
	local effective = if GuiService.ReducedMotionEnabled then TweenInfo.new(0) else info
	local tween = TweenService:Create(instance, effective, goals)
	tween:Play()
	return tween
end

--[[ Transparence d'un fond selon la préférence système (PreferredTransparency : 0 = opaque). ]]
function UI.backgroundTransparency(base: number): number
	return base * GuiService.PreferredTransparency
end

--[[
	Marges de la zone sûre de l'appareil (encoches, coins arrondis), en pixels :
	gauche, haut, droite, bas. Nulles sur ordinateur. Mesurées par deux ScreenGui sondes
	(cède une frame : appeler depuis un thread qui peut attendre).
]]
function UI.safeInsets(): (number, number, number, number)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local full = Instance.new("ScreenGui")
	full.Name = "AS_InsetProbe"
	full.ScreenInsets = Enum.ScreenInsets.None
	full.Parent = playerGui
	local safe = Instance.new("ScreenGui")
	safe.Name = "AS_InsetProbe"
	safe.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	safe.Parent = playerGui
	task.wait() -- tailles absolues calculées au rendu suivant
	local fp, fs = full.AbsolutePosition, full.AbsoluteSize
	local sp, ss = safe.AbsolutePosition, safe.AbsoluteSize
	full:Destroy()
	safe:Destroy()
	return math.max(sp.X - fp.X, 0),
		math.max(sp.Y - fp.Y, 0),
		math.max((fp.X + fs.X) - (sp.X + ss.X), 0),
		math.max((fp.Y + fs.Y) - (sp.Y + ss.Y), 0)
end

--[[ ScreenGui standard + UIScale responsive (référence 1080p). ]]
function UI.screen(name: string, displayOrder: number, ignoreInset: boolean?): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = if ignoreInset == nil then true else ignoreInset
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = displayOrder
	local scale = Instance.new("UIScale")
	scale.Parent = gui
	table.insert(scales, scale)
	UI.refreshScales()
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return gui
end

function UI.isMobile(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

function UI.setUserScale(value: number)
	userScale = value
	UI.refreshScales()
end

function UI.refreshScales()
	local camera = Workspace.CurrentCamera
	local height = if camera then camera.ViewportSize.Y else 1080
	local base = math.clamp(height / 1080, 0.55, 1.25)
	if UI.isMobile() then
		base = math.clamp(height / 820, 0.5, 1.1)
	end
	for _, scale in scales do
		scale.Scale = base * userScale
	end
end

function UI.insets(): (Vector2, Vector2)
	return GuiService:GetGuiInset()
end

---------------------------------------------------------------------------------------------
-- Composants
---------------------------------------------------------------------------------------------

--[[ Panneau "verre" : fond sombre translucide, liseré lumineux et dégradé vertical. ]]
function UI.panel(props: Props?): Frame
	local panel = UI.frame({
		BackgroundColor3 = Theme.colors.panel,
		BackgroundTransparency = UI.backgroundTransparency(Theme.transparency.panel),
	})
	UI.corner(4, panel)
	UI.stroke(panel, Theme.colors.stroke, 1, 0.2)
	UI.gradient(
		panel,
		ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(190, 200, 215)),
		90,
		NumberSequence.new(0, 0.05)
	)
	UI.apply(panel, props)
	return panel
end

--[[ Liseré d'accent sur le bord gauche d'un élément (signature visuelle). ]]
function UI.accent(parent: Instance, color: Color3, width: number?): Frame
	return UI.frame({
		Name = "Accent",
		BackgroundColor3 = color,
		Size = UDim2.new(0, width or 3, 1, 0),
		Position = UDim2.fromScale(0, 0),
		ZIndex = 3,
		Parent = parent,
	})
end

export type ButtonStyle = "Primary" | "Secondary" | "Danger" | "Ghost"

--[[ Bouton premium : survol (glow + translation), clic (compression), sons. ]]
function UI.actionButton(text: string, style: ButtonStyle, onClick: () -> (), props: Props?): TextButton
	local base = if style == "Primary"
		then Theme.colors.primary
		elseif style == "Danger" then Theme.colors.danger
		elseif style == "Secondary" then Theme.colors.panelLight
		else Theme.colors.panel
	local textColor = if style == "Primary" then Theme.colors.void else Theme.colors.text
	local button = UI.button({
		Text = text,
		BackgroundColor3 = base,
		BackgroundTransparency = if style == "Ghost" then 0.6 else 0,
		TextColor3 = textColor,
		FontFace = Theme.fonts.heading,
		TextSize = 18,
		Size = UDim2.fromOffset(220, 46),
	})
	UI.corner(3, button)
	local stroke =
		UI.stroke(button, if style == "Primary" then Color3.new(1, 1, 1) else Theme.colors.strokeBright, 1, 0.6)
	local scale = Instance.new("UIScale")
	scale.Parent = button
	button.MouseEnter:Connect(function()
		UI.playSound("UI.Hover")
		UI.tween(stroke, Theme.tween.fast, { Transparency = 0 })
		UI.tween(scale, Theme.tween.fast, { Scale = 1.03 })
	end)
	button.MouseLeave:Connect(function()
		UI.tween(stroke, Theme.tween.fast, { Transparency = 0.6 })
		UI.tween(scale, Theme.tween.fast, { Scale = 1 })
	end)
	button.MouseButton1Down:Connect(function()
		UI.tween(scale, Theme.tween.fast, { Scale = 0.97 })
	end)
	button.MouseButton1Up:Connect(function()
		UI.tween(scale, Theme.tween.fast, { Scale = 1.03 })
	end)
	button.Activated:Connect(function()
		UI.playSound(if style == "Danger" then "UI.Back" else "UI.Click")
		onClick()
	end)
	UI.apply(button, props)
	return button
end

export type Bar = {
	root: Frame,
	fill: Frame,
	ghost: Frame,
	set: (value: number, max: number) -> (),
}

--[[ Barre avec traînée : la partie perdue reste visible en blanc puis se résorbe. ]]
function UI.bar(color: Color3, props: Props?): Bar
	local root = UI.frame({
		BackgroundColor3 = Color3.fromRGB(20, 24, 30),
		BackgroundTransparency = 0.25,
		ClipsDescendants = true,
	})
	UI.corner(2, root)
	local ghost = UI.frame({
		Name = "Ghost",
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 0.35,
		Size = UDim2.fromScale(1, 1),
		Parent = root,
	})
	local fill = UI.frame({
		Name = "Fill",
		BackgroundColor3 = color,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = root,
	})
	UI.gradient(fill, ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 200, 210)), 90)
	local lastRatio = 1
	local token = 0
	local function set(value: number, max: number)
		local ratio = math.clamp(if max > 0 then value / max else 0, 0, 1)
		fill.Size = UDim2.fromScale(ratio, 1)
		token += 1
		local current = token
		if ratio < lastRatio then
			task.delay(0.35, function()
				if current == token then
					UI.tween(
						ghost,
						TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
						{ Size = UDim2.fromScale(ratio, 1) }
					)
				end
			end)
		else
			ghost.Size = UDim2.fromScale(ratio, 1)
		end
		lastRatio = ratio
	end
	UI.apply(root, props)
	return { root = root, fill = fill, ghost = ghost, set = set }
end

--[[ Ligne de réglage : libellé à gauche, contrôle à droite. ]]
local function settingRow(label: string): (Frame, Frame)
	local row = UI.frame({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 38) })
	UI.text({
		Text = label,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(0.45, 0, 1, 0),
		TextColor3 = Theme.colors.textDim,
		FontFace = Theme.fonts.bodyBold,
		TextSize = 16,
		Parent = row,
	})
	local control = UI.frame({
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.47, 0),
		Size = UDim2.new(0.53, 0, 1, 0),
		Parent = row,
	})
	return row, control
end

export type SliderOptions = {
	log: boolean?, -- échelle logarithmique (sensibilité : précision fine aux petites valeurs)
	editable: boolean?, -- valeur saisissable au clavier (Entrée pour valider)
	nudge: number?, -- boutons − / + d'un pas fin
}

function UI.slider(
	label: string,
	min: number,
	max: number,
	step: number,
	value: number,
	onChange: (number) -> (),
	format: ((number) -> string)?,
	options: SliderOptions?
): Frame
	local opts: SliderOptions = options or {}
	local logScale = opts.log == true and min > 0
	local nudge = opts.nudge
	local row, control = settingRow(label)
	local readoutWidth = if opts.editable then 66 else 60
	local nudgeWidth = if nudge then 60 else 0
	local track = UI.frame({
		BackgroundColor3 = Theme.colors.panelLight,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(1, -(readoutWidth + nudgeWidth + 10), 0, 6),
		Parent = control,
	})
	UI.corner(3, track)
	local fill = UI.frame({ BackgroundColor3 = Theme.colors.primary, Size = UDim2.fromScale(0, 1), Parent = track })
	UI.corner(3, fill)
	local knob = UI.frame({
		BackgroundColor3 = Color3.new(1, 1, 1),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(14, 14),
		ZIndex = 2,
		Parent = track,
	})
	UI.corner(7, knob)
	local readout: TextLabel? = nil
	local box: TextBox? = nil
	if opts.editable then
		local input = Instance.new("TextBox")
		input.AnchorPoint = Vector2.new(1, 0.5)
		input.Position = UDim2.fromScale(1, 0.5)
		input.Size = UDim2.fromOffset(readoutWidth, 28)
		input.BackgroundColor3 = Theme.colors.panelLight
		input.BorderSizePixel = 0
		input.ClearTextOnFocus = false
		input.FontFace = Theme.fonts.monoBold
		input.TextSize = 15
		input.TextColor3 = Theme.colors.text
		input.PlaceholderColor3 = Theme.colors.textDim
		input.Parent = control
		UI.corner(4, input)
		UI.stroke(input, Theme.colors.stroke, 1, 0.1)
		box = input
	else
		readout = UI.text({
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(1, 0.5),
			Size = UDim2.fromOffset(readoutWidth, 24),
			TextXAlignment = Enum.TextXAlignment.Right,
			FontFace = Theme.fonts.monoBold,
			TextSize = 15,
			Parent = control,
		})
	end
	local function toRatio(v: number): number
		if logScale then
			return math.log(v / min) / math.log(max / min)
		end
		return (v - min) / (max - min)
	end
	local function fromRatio(ratio: number): number
		if logScale then
			return min * (max / min) ^ ratio
		end
		return min + (max - min) * ratio
	end
	local function snap(raw: number): number
		return math.clamp(math.floor(raw / step + 0.5) * step, min, max)
	end
	local current = value
	local function render()
		local ratio = math.clamp(toRatio(current), 0, 1)
		fill.Size = UDim2.fromScale(ratio, 1)
		knob.Position = UDim2.fromScale(ratio, 0.5)
		local text = if format then format(current) else string.format(if step < 1 then "%.2f" else "%d", current)
		if readout then
			readout.Text = text
		end
		if box and not box:IsFocused() then
			box.Text = text
		end
	end
	local function set(newValue: number)
		if newValue ~= current then
			current = newValue
			render()
			onChange(current)
		else
			render()
		end
	end
	render()
	local function updateFrom(x: number)
		local ratio = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
		set(snap(fromRatio(ratio)))
	end
	local hit = UI.button({
		BackgroundTransparency = 1,
		Text = "",
		Size = UDim2.new(1, 0, 0, 24),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		ZIndex = 3,
		Parent = track,
	})
	-- Glisser : connexions ouvertes le temps du geste seulement (aucune fuite par curseur).
	local moveConnection: RBXScriptConnection? = nil
	local endConnection: RBXScriptConnection? = nil
	local function stopDrag()
		if moveConnection then
			moveConnection:Disconnect()
			moveConnection = nil
		end
		if endConnection then
			endConnection:Disconnect()
			endConnection = nil
		end
	end
	hit.MouseButton1Down:Connect(function(x: number)
		stopDrag()
		updateFrom(x)
		moveConnection = UserInputService.InputChanged:Connect(function(input: InputObject)
			if
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			then
				updateFrom(input.Position.X)
			end
		end)
		endConnection = UserInputService.InputEnded:Connect(function(input: InputObject)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				stopDrag()
			end
		end)
	end)
	row.Destroying:Connect(stopDrag)
	if box then
		box.FocusLost:Connect(function()
			local parsed = tonumber((string.gsub(box.Text, ",", ".")))
			if parsed and parsed == parsed then
				set(snap(parsed))
			else
				render()
			end
		end)
	end
	if nudge then
		for index, spec in { { text = "−", delta = -nudge }, { text = "+", delta = nudge } } do
			local button = UI.button({
				Text = spec.text,
				FontFace = Theme.fonts.monoBold,
				TextSize = 18,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -(readoutWidth + 6 + (2 - index) * 30), 0.5, 0),
				Size = UDim2.fromOffset(26, 26),
				Parent = control,
			})
			UI.corner(4, button)
			button.Activated:Connect(function()
				UI.playSound("UI.Click")
				set(snap(current + spec.delta))
			end)
		end
	end
	return row
end

function UI.toggle(label: string, value: boolean, onChange: (boolean) -> ()): Frame
	local row, control = settingRow(label)
	local current = value
	local button = UI.button({
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(120, 28),
		FontFace = Theme.fonts.heading,
		TextSize = 15,
		Parent = control,
	})
	UI.corner(3, button)
	local function render()
		button.Text = if current then "ACTIVÉ" else "DÉSACTIVÉ"
		button.BackgroundColor3 = if current then Theme.colors.primaryDeep else Theme.colors.panelLight
		button.TextColor3 = if current then Theme.colors.text else Theme.colors.textDim
	end
	render()
	button.Activated:Connect(function()
		current = not current
		render()
		UI.playSound("UI.Click")
		onChange(current)
	end)
	return row
end

function UI.cycler(
	label: string,
	options: { string },
	value: string,
	onChange: (string) -> (),
	display: ((string) -> string)?
): Frame
	local row, control = settingRow(label)
	local index = math.max(table.find(options, value) or 1, 1)
	local labelText = UI.text({
		Position = UDim2.fromOffset(34, 0),
		Size = UDim2.new(1, -68, 1, 0),
		FontFace = Theme.fonts.heading,
		TextSize = 16,
		Parent = control,
	})
	local function render()
		local option = options[index]
		labelText.Text = if display then display(option) else option
	end
	local function arrow(text: string, x: number, delta: number)
		local button = UI.button({
			Text = text,
			Position = UDim2.new(x, if x > 0 then -30 else 0, 0.5, -14),
			Size = UDim2.fromOffset(30, 28),
			Parent = control,
		})
		UI.corner(3, button)
		button.Activated:Connect(function()
			index = ((index - 1 + delta) % #options) + 1
			render()
			UI.playSound("UI.Click")
			onChange(options[index])
		end)
	end
	arrow("‹", 0, -1)
	arrow("›", 1, 1)
	render()
	return row
end

--[[ Effet "glitch" ponctuel sur un texte (titres, bannières). ]]
function UI.glitchText(label: TextLabel, duration: number)
	local original = label.Position
	local deadline = os.clock() + duration
	task.spawn(function()
		while os.clock() < deadline and label.Parent do
			label.Position = original + UDim2.fromOffset(math.random(-4, 4), math.random(-2, 2))
			label.TextTransparency = if math.random() < 0.2 then 0.5 else 0
			task.wait(0.03)
		end
		label.Position = original
		label.TextTransparency = 0
	end)
end

function UI.formatTime(seconds: number): string
	local s = math.max(0, math.floor(seconds + 0.5))
	return string.format("%d:%02d", s // 60, s % 60)
end

return UI
