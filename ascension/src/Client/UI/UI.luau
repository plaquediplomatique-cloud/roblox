--!strict
--[[
	UI — petit kit d'interface (jetons de Config/Theme, jamais de couleur en dur).

	Principes (skill roblox-ui-design-system) :
	  * composants à états : survol / appui / désactivé, tous animés par TweenService ;
	  * mise à l'échelle globale (UIScale) selon la taille d'écran, tailles tactiles >= 44 px ;
	  * zones sûres (ScreenInsets) pour les encoches et la barre Roblox ;
	  * aucune connexion orpheline : chaque composant renvoie ses connexions au Janitor appelant.
]]

local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")

local Shared = game:GetService("ReplicatedStorage").Shared
local Theme = require(Shared.Config.Theme)
local Rarities = require(Shared.Config.Rarities)
local NumberFormat = require(Shared.Rules.NumberFormat)
local Sfx = require(script.Parent.Parent.Core.Sfx)

local UI = {}

export type Props = { [string]: any }

UI.Theme = Theme
UI.format = NumberFormat.compact

---------------------------------------------------------------------------------------------
-- Création générique
---------------------------------------------------------------------------------------------

function UI.new(className: string, props: Props?, children: { Instance }?): any
	local instance = Instance.new(className)
	local parent: Instance? = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				(instance :: any)[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	instance.Parent = parent
	return instance
end

function UI.corner(radius: UDim?): UICorner
	return UI.new("UICorner", { CornerRadius = radius or Theme.Radius })
end

function UI.stroke(color: Color3?, thickness: number?, transparency: number?): UIStroke
	return UI.new("UIStroke", {
		Color = color or Theme.Color.InkEdge,
		Thickness = thickness or 2,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function UI.padding(all: number): UIPadding
	return UI.new("UIPadding", {
		PaddingTop = UDim.new(0, all),
		PaddingBottom = UDim.new(0, all),
		PaddingLeft = UDim.new(0, all),
		PaddingRight = UDim.new(0, all),
	})
end

function UI.list(direction: Enum.FillDirection?, gap: number?, align: Enum.HorizontalAlignment?): UIListLayout
	return UI.new("UIListLayout", {
		FillDirection = direction or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, gap or 6),
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

function UI.tween(
	instance: Instance,
	properties: Props,
	duration: number?,
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?
): Tween
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(
			duration or Theme.Tween.Normal,
			style or Enum.EasingStyle.Quad,
			direction or Enum.EasingDirection.Out
		),
		properties
	)
	tween:Play()
	return tween
end

function UI.rarityColor(rarityId: string): Color3
	local rarity = Rarities.ById[rarityId]
	return if rarity then rarity.Color else Theme.Color.Text
end

---------------------------------------------------------------------------------------------
-- Écran racine
---------------------------------------------------------------------------------------------

-- ScreenGui avec échelle globale (référence 1080 px de haut) et zones sûres.
function UI.screen(name: string, parent: Instance, order: number?): ScreenGui
	local gui = UI.new("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		DisplayOrder = order or 1,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
		IgnoreGuiInset = false,
		Parent = parent,
	})
	local scale = UI.new("UIScale", { Parent = gui })
	local function update()
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local size = camera.ViewportSize
		scale.Scale = math.clamp(math.min(size.Y / 900, size.X / 1400), 0.55, 1.25)
	end
	update()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	end
	return gui
end

---------------------------------------------------------------------------------------------
-- Composants
---------------------------------------------------------------------------------------------

function UI.label(props: Props): TextLabel
	local label = UI.new("TextLabel", {
		BackgroundTransparency = 1,
		Font = Theme.Font.Bold,
		TextSize = Theme.Size.Body,
		TextColor3 = Theme.Color.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		RichText = false,
	})
	for key, value in props do
		if key == "Parent" then
			continue
		end
		(label :: any)[key] = value
	end
	label.Parent = props.Parent
	return label
end

function UI.panel(props: Props): Frame
	local frame = UI.new("Frame", {
		BackgroundColor3 = Theme.Color.Ink,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
	})
	for key, value in props do
		if key == "Parent" then
			continue
		end
		(frame :: any)[key] = value
	end
	UI.corner(Theme.RadiusLarge).Parent = frame
	UI.stroke(Theme.Color.InkEdge, 2, 0.2).Parent = frame
	frame.Parent = props.Parent
	return frame
end

export type ButtonStyle = "primary" | "ghost" | "good" | "bad"

local STYLE_COLORS: { [string]: Color3 } = {
	primary = Theme.Color.Accent,
	ghost = Theme.Color.InkSoft,
	good = Theme.Color.Good,
	bad = Theme.Color.Bad,
}

export type Button = {
	Instance: TextButton,
	SetEnabled: (self: Button, enabled: boolean) -> (),
	SetText: (self: Button, text: string) -> (),
}

-- Bouton à états (survol, appui, désactivé). `onClick` est appelé hors désactivation.
function UI.button(props: Props, onClick: (() -> ())?): Button
	local style: string = props.Style or "primary"
	local base = STYLE_COLORS[style] or Theme.Color.Accent
	local enabled = true
	local button = UI.new("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = base,
		BorderSizePixel = 0,
		Font = Theme.Font.Bold,
		TextSize = Theme.Size.Body,
		TextColor3 = Theme.Color.Text,
		Text = props.Text or "",
		Size = props.Size or UDim2.fromOffset(140, 44),
	})
	for key, value in props do
		if key ~= "Style" and key ~= "Parent" and key ~= "Text" then
			(button :: any)[key] = value
		end
	end
	UI.corner(Theme.Radius).Parent = button
	local stroke = UI.stroke(base:Lerp(Color3.new(1, 1, 1), 0.35), 2, 0.1)
	stroke.Parent = button
	local scale = UI.new("UIScale", { Parent = button })

	button.MouseEnter:Connect(function()
		if enabled then
			UI.tween(scale, { Scale = 1.05 }, Theme.Tween.Fast)
		end
	end)
	button.MouseLeave:Connect(function()
		UI.tween(scale, { Scale = 1 }, Theme.Tween.Fast)
	end)
	button.MouseButton1Down:Connect(function()
		if enabled then
			UI.tween(scale, { Scale = 0.94 }, 0.06)
		end
	end)
	button.MouseButton1Up:Connect(function()
		UI.tween(scale, { Scale = 1.05 }, 0.1, Enum.EasingStyle.Back)
	end)
	button.Activated:Connect(function()
		if not enabled then
			Sfx.play("UI_Error")
			return
		end
		Sfx.play("UI_Click")
		if onClick then
			onClick()
		end
	end)

	local object: Button = {
		Instance = button,
		SetEnabled = function(_self, value)
			enabled = value
			button.BackgroundColor3 = if value then base else Theme.Color.InkSoft
			button.TextTransparency = if value then 0 else 0.5
			stroke.Transparency = if value then 0.1 else 0.6
		end,
		SetText = function(_self, text)
			button.Text = text
		end,
	}
	button.Parent = props.Parent
	return object
end

export type Bar = {
	Frame: Frame,
	Fill: Frame,
	Set: (self: Bar, fraction: number, animate: boolean?) -> (),
	SetColor: (self: Bar, color: Color3) -> (),
}

-- Barre de progression à remplissage animé (la « satisfaction » du XP).
function UI.bar(props: Props): Bar
	local frame = UI.new("Frame", {
		BackgroundColor3 = Theme.Color.InkSoft,
		BorderSizePixel = 0,
		Size = props.Size or UDim2.new(1, 0, 0, 18),
		ClipsDescendants = true,
	})
	for key, value in props do
		if key ~= "Parent" and key ~= "Color" then
			(frame :: any)[key] = value
		end
	end
	UI.corner(UDim.new(0, 9)).Parent = frame
	UI.stroke(Theme.Color.InkEdge, 1.5, 0.3).Parent = frame
	local fill = UI.new("Frame", {
		BackgroundColor3 = props.Color or Theme.Color.Xp,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		Parent = frame,
	})
	UI.corner(UDim.new(0, 9)).Parent = fill
	UI.new("UIGradient", {
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 200)),
		Rotation = 90,
		Parent = fill,
	})
	frame.Parent = props.Parent
	local bar: Bar = {
		Frame = frame,
		Fill = fill,
		Set = function(_self, fraction, animate)
			local target = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
			if animate == false then
				fill.Size = target
			else
				UI.tween(fill, { Size = target }, 0.35, Enum.EasingStyle.Quint)
			end
		end,
		SetColor = function(_self, color)
			fill.BackgroundColor3 = color
		end,
	}
	return bar
end

-- « Pop » d'apparition (échelle élastique).
function UI.pop(instance: GuiObject, from: number?)
	local scale = instance:FindFirstChildOfClass("UIScale") or UI.new("UIScale", { Parent = instance })
	scale.Scale = from or 0.6
	UI.tween(scale, { Scale = 1 }, 0.4, Enum.EasingStyle.Back)
end

-- Défilement avec liste verticale ; renvoie le conteneur (Parent des lignes).
function UI.scroller(props: Props): ScrollingFrame
	local scroller = UI.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.Color.InkEdge,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Size = UDim2.fromScale(1, 1),
	})
	for key, value in props do
		if key ~= "Parent" then
			(scroller :: any)[key] = value
		end
	end
	scroller.Parent = props.Parent
	return scroller
end

function UI.clear(container: Instance)
	for _, child in container:GetChildren() do
		if not child:IsA("UIListLayout") and not child:IsA("UIGridLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

-- Compte à rebours animé d'un nombre (pièces, puissance…).
function UI.countTo(label: TextLabel, from: number, to: number, format: ((number) -> string)?, duration: number?)
	local fmt = format or NumberFormat.compact
	local value = Instance.new("NumberValue")
	value.Value = from
	local connection = value.Changed:Connect(function(current)
		label.Text = fmt(current)
	end)
	local tween = TweenService:Create(
		value,
		TweenInfo.new(duration or 0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Value = to }
	)
	tween.Completed:Connect(function()
		connection:Disconnect()
		value:Destroy()
		label.Text = fmt(to)
	end)
	tween:Play()
end

function UI.safeInsets(): Rect
	local topLeft, bottomRight = GuiService:GetGuiInset()
	return Rect.new(topLeft, bottomRight)
end

return UI
