--!strict
--[[
	HUDController — HUD de combat (match + Training Range), lisible en une fraction de
	seconde et entièrement piloté par l'état (aucune logique de jeu ici).

	Visuel : Client/UI/HudWidgets (construction seule, prévisualisable hors Studio avec
	tools/ui_preview.luau + tools/render_ui.py) ; ce contrôleur ne fait que les alimenter.

	Disposition (référence 1080p, mise à l'échelle par UI.screen) :
	  haut-centre    : scores, timer de manche / mèche de l'uplink, survivants, boussole
	  haut-droite    : killfeed
	  centre         : réticule dynamique, hitmarker, indicateurs de dégâts directionnels,
	                   invite d'interaction, bannières, confirmation d'élimination
	  bas-gauche     : PV (barre à traînée) + bouclier
	  bas-droite     : munitions animées, arme, mode de tir, rechargement, emplacements
	  monde          : chiffres de dégâts cumulés (ScreenGui sans UIScale, pixels exacts)
	Overlays : lunette (anneau = UIStroke géant autour d'un cercle : aucun asset),
	vignette de bas PV / d'impact, tableau des scores (Tab), toasts globaux.

	Le réticule représente le VRAI cône de dispersion (Spread.cone projeté à l'écran
	selon le FOV courant) : ce que le joueur voit est ce que le serveur appliquera.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Weapons = require(Shared.Config.Weapons)
local Settings = require(Shared.Config.Settings)
local Ranks = require(Shared.Config.Ranks)
local Theme = require(Shared.Config.Theme)
local Ballistics = require(Shared.Combat.Ballistics)
local Spring = require(Shared.Util.Spring)
local Net = require(Shared.Net.Net)
local UI = require(script.Parent.Parent.UI.UI)
local HudWidgets = require(script.Parent.Parent.UI.HudWidgets)
local ClientState = require(script.Parent.Parent.Core.ClientState)
local ReplicaController = require(script.Parent.Parent.Core.ReplicaController)
local SettingsController = require(script.Parent.SettingsController)
local InputController = require(script.Parent.InputController)
local CharacterAnimator = require(script.Parent.CharacterAnimator)
local CameraController = require(script.Parent.CameraController)
local WeaponController = require(script.Parent.WeaponController)
local ViewmodelController = require(script.Parent.ViewmodelController)
local AudioController = require(script.Parent.AudioController)
local LightingController = require(script.Parent.LightingController)

local colors = Theme.colors
local LOW_HEALTH = Theme.feedback.lowHealth
local fonts = Theme.fonts
local player = Players.LocalPlayer

local HUDController = {}

local hud: ScreenGui
local root: Frame -- combat (armé, 1re personne)
local overlay: Frame -- annonces et killfeed : visibles même mort / spectateur
local worldGui: ScreenGui
local toastGui: ScreenGui
local boardGui: ScreenGui
local visibleRequested = true

local QUAD_OUT = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function guiScale(): number
	local scale = hud and hud:FindFirstChildOfClass("UIScale")
	return if scale then scale.Scale else 1
end

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

---------------------------------------------------------------------------------------------
-- Réticule
---------------------------------------------------------------------------------------------

type Crosshair = { root: Frame, lines: { Frame }, dot: Frame, circle: Frame, circleStroke: UIStroke }

local crosshair: Crosshair
local crosshairKick = Spring.number(0, 24, 0.7)

local function buildCrosshair(parent: Instance): Crosshair
	local holder = UI.frame({
		Name = "Crosshair",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(0, 0),
		ZIndex = 20,
		Parent = parent,
	})
	local lines: { Frame } = {}
	for _ = 1, 4 do
		local line = UI.frame({ AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 20, Parent = holder })
		UI.stroke(line, Color3.new(0, 0, 0), 1, 0.5)
		table.insert(lines, line)
	end
	local dot = UI.frame({ AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 21, Parent = holder })
	UI.stroke(dot, Color3.new(0, 0, 0), 1, 0.5)
	local circle = UI.frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 20,
		Parent = holder,
	})
	UI.corner(999, circle)
	local circleStroke = UI.stroke(circle, Color3.new(1, 1, 1), 1.5, 0)
	return { root = holder, lines = lines, dot = dot, circle = circle, circleStroke = circleStroke }
end

local function styleLine(frame: Frame, color: Color3, opacity: number, settings: Types.CrosshairSettings)
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = 1 - opacity
	local stroke = frame:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Enabled = settings.Outline and opacity > 0.01
		stroke.Thickness = settings.OutlineThickness
		stroke.Transparency = 1 - settings.OutlineOpacity * opacity
	end
end

local function coneToPixels(coneDegrees: number): number
	local camera = Workspace.CurrentCamera
	if not camera then
		return 0
	end
	local halfFov = math.rad(camera.FieldOfView / 2)
	local pixels = math.tan(math.rad(coneDegrees)) / math.tan(halfFov) * (camera.ViewportSize.Y / 2)
	return pixels / guiScale()
end

local function updateCrosshair(dt: number, state: WeaponController.HudState)
	local settings = SettingsController.get().Crosshair
	local def = state.def
	local fade = 1 - math.clamp((state.ads - 0.3) / 0.4, 0, 1)
	if state.scoped or def == nil then
		fade = 0
	end
	local opacity = settings.Opacity * fade
	local color = Settings.parseHex(settings.Color)
	local kick = crosshairKick:step(dt)
	local spread = if settings.Dynamic and def and def.category ~= "Melee" then coneToPixels(state.cone) else 0
	local gap = settings.Gap + spread * 0.85 + kick
	local length, thickness = settings.Length, settings.Thickness
	local style = settings.Style
	local melee = def ~= nil and def.category == "Melee"
	local showLines = (style == "Classic" or style == "TShape") and not melee
	local positions = {
		Vector2.new(0, -(gap + length / 2)),
		Vector2.new(0, gap + length / 2),
		Vector2.new(-(gap + length / 2), 0),
		Vector2.new(gap + length / 2, 0),
	}
	for index, line in crosshair.lines do
		local visible = showLines and not (style == "TShape" and index == 1)
		line.Visible = visible
		if visible then
			local vertical = index <= 2
			line.Size = if vertical then UDim2.fromOffset(thickness, length) else UDim2.fromOffset(length, thickness)
			line.Position = UDim2.fromOffset(positions[index].X, positions[index].Y)
			styleLine(line, color, opacity, settings)
		end
	end
	local showDot = settings.Dot or style == "Dot" or melee
	crosshair.dot.Visible = showDot
	if showDot then
		crosshair.dot.Size = UDim2.fromOffset(settings.DotSize, settings.DotSize)
		styleLine(crosshair.dot, color, opacity, settings)
	end
	local showCircle = style == "Circle" and not melee
	crosshair.circle.Visible = showCircle
	if showCircle then
		local diameter = math.max(gap * 2, 8)
		crosshair.circle.Size = UDim2.fromOffset(diameter, diameter)
		crosshair.circleStroke.Color = color
		crosshair.circleStroke.Thickness = math.max(thickness * 0.75, 1)
		crosshair.circleStroke.Transparency = 1 - opacity
	end
end

--[[
	Aberration chromatique SIMULÉE (Roblox n'a pas d'effet natif) : deux franges de
	bord, cyan à gauche / rouge à droite, décalées de quelques pixels, flashées 0.15 s.
	Lue par l'oeil comme une séparation RVB en périphérie, au centre l'image reste nette.
]]
local fringes: { Frame } = {}

local function buildFringes(parent: Instance)
	for _, spec in
		{
			{ color = Color3.fromRGB(40, 220, 255), anchor = 0, rotation = 0 },
			{ color = Color3.fromRGB(255, 50, 90), anchor = 1, rotation = 180 },
		}
	do
		local fringe = UI.frame({
			BackgroundColor3 = spec.color,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(spec.anchor, 0),
			Position = UDim2.fromScale(spec.anchor, 0),
			Size = UDim2.fromScale(0.12, 1),
			ZIndex = 2,
			Parent = parent,
		})
		UI.gradient(fringe, ColorSequence.new(spec.color), spec.rotation, NumberSequence.new(0.2, 1))
		table.insert(fringes, fringe)
	end
end

local function chromaticPulse(intensity: number)
	if SettingsController.get().Video.ReducedFlashes then
		return
	end
	for index, fringe in fringes do
		local side = if index == 1 then 1 else -1
		fringe.BackgroundTransparency = 1 - 0.45 * math.clamp(intensity, 0, 1)
		fringe.Position = UDim2.new(if index == 1 then 0 else 1, side * 6, 0, 0)
		UI.tween(fringe, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(if index == 1 then 0 else 1, 0),
		})
	end
end

---------------------------------------------------------------------------------------------
-- Hitmarker, chiffres de dégâts, confirmation d'élimination
---------------------------------------------------------------------------------------------

local hitmarkerLines: { Frame } = {}
local hitmarkerScale: UIScale
local hitToken = 0

local function buildHitmarker(parent: Instance)
	local holder = UI.frame({
		Name = "Hitmarker",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(40, 40),
		ZIndex = 22,
		Parent = parent,
	})
	hitmarkerScale = Instance.new("UIScale")
	hitmarkerScale.Parent = holder
	for _, corner in { Vector2.new(-1, -1), Vector2.new(1, -1), Vector2.new(-1, 1), Vector2.new(1, 1) } do
		local line = UI.frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, corner.X * 9, 0.5, corner.Y * 9),
			Size = UDim2.fromOffset(2, 10),
			Rotation = if corner.X * corner.Y > 0 then -45 else 45,
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 1,
			ZIndex = 22,
			Parent = holder,
		})
		UI.stroke(line, Color3.new(0, 0, 0), 1, 0.4)
		table.insert(hitmarkerLines, line)
	end
end

local function flashHitmarker(color: Color3, big: boolean)
	if not SettingsController.get().Hud.Hitmarkers then
		return
	end
	hitToken += 1
	local token = hitToken
	for _, line in hitmarkerLines do
		line.BackgroundColor3 = color
		line.BackgroundTransparency = 0
		line.Size = if big then UDim2.fromOffset(3, 13) else UDim2.fromOffset(2, 10)
	end
	hitmarkerScale.Scale = if big then 1.6 else 1.25
	UI.tween(hitmarkerScale, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Scale = if big then 1.15 else 1,
	})
	task.delay(if big then 0.32 else 0.14, function()
		if token ~= hitToken then
			return
		end
		for _, line in hitmarkerLines do
			UI.tween(line, TweenInfo.new(0.16), { BackgroundTransparency = 1 })
		end
	end)
end

type DamageNumber = {
	label: TextLabel,
	position: Vector3,
	value: number,
	born: number,
	victim: number,
	scale: UIScale,
}

local damageNumbers: { DamageNumber } = {}

local function addDamageNumber(report: Types.HitReport)
	if not SettingsController.get().Hud.DamageNumbers then
		return
	end
	local now = os.clock()
	local color = if report.zone == "Head" then colors.gold elseif report.wallbang then colors.warning else colors.text
	for _, entry in damageNumbers do
		if entry.victim == report.victim and now - entry.born < 0.75 then
			entry.value += report.damage
			entry.position = report.position
			entry.born = now
			entry.label.Text = tostring(entry.value)
			entry.label.TextColor3 = color
			entry.scale.Scale = 1.35
			UI.tween(entry.scale, QUAD_OUT, { Scale = 1 })
			return
		end
	end
	local label = UI.text({
		Text = tostring(report.damage),
		FontFace = fonts.monoBold,
		TextSize = 24,
		TextColor3 = color,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(90, 30),
		Parent = worldGui,
	})
	UI.textStroke(label, 0.25)
	local scale = Instance.new("UIScale")
	scale.Scale = 1.35
	scale.Parent = label
	UI.tween(scale, QUAD_OUT, { Scale = 1 })
	table.insert(damageNumbers, {
		label = label,
		position = report.position,
		value = report.damage,
		born = now,
		victim = report.victim,
		scale = scale,
	})
end

local function updateDamageNumbers()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local now = os.clock()
	local pixel = camera.ViewportSize.Y / 1080
	for index = #damageNumbers, 1, -1 do
		local entry = damageNumbers[index]
		local age = now - entry.born
		if age > 1.1 then
			entry.label:Destroy()
			table.remove(damageNumbers, index)
			continue
		end
		local point, onScreen = camera:WorldToViewportPoint(entry.position + Vector3.new(0, 1.2 + age * 1.4, 0))
		entry.label.Visible = onScreen
		entry.label.Position = UDim2.fromOffset(point.X, point.Y)
		entry.label.TextSize = math.floor(24 * pixel + 0.5)
		entry.label.TextTransparency = math.clamp((age - 0.65) / 0.45, 0, 1)
	end
end

local killConfirm: TextLabel
local killPips: Frame
local roundKills = 0
local QUAD_IN = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local STREAK_NAMES: { [number]: string } = {
	[2] = "DOUBLÉ",
	[3] = "TRIPLÉ",
	[4] = "QUADRUPLÉ",
	[5] = "ACE",
}

local function renderKillPips()
	for _, child in killPips:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for index = 1, math.min(roundKills, 5) do
		HudWidgets.killPip(killPips, index, if roundKills >= 5 then colors.gold else colors.primary)
	end
end

local function confirmKill(event: Types.KillEvent)
	roundKills += 1
	renderKillPips()
	local streak = STREAK_NAMES[math.min(roundKills, 5)]
	local tags = {}
	if event.headshot then
		table.insert(tags, "TÊTE")
	end
	if event.wallbang then
		table.insert(tags, "À TRAVERS")
	end
	if event.noscope then
		table.insert(tags, "NO-SCOPE")
	end
	if event.firstBlood then
		table.insert(tags, "PREMIER SANG")
	end
	local suffix = if #tags > 0 then "  ·  " .. table.concat(tags, " · ") else ""
	killConfirm.Text = ('<font color="#%s">%s</font>   ÉLIMINÉ  ·  %s%s'):format(
		(if streak then colors.gold else colors.primary):ToHex(),
		streak or "◆",
		string.upper(event.victimName),
		suffix
	)
	killConfirm.TextTransparency = 1
	UI.tween(killConfirm, QUAD_IN, { TextTransparency = 0 })
	local token = os.clock()
	killConfirm:SetAttribute("Token", token)
	task.delay(2.2, function()
		if killConfirm:GetAttribute("Token") == token then
			UI.tween(killConfirm, TweenInfo.new(0.4), { TextTransparency = 1 })
		end
	end)
end

local function onHitConfirmed(report: Types.HitReport, _def: Types.WeaponDef?)
	local audio = SettingsController.get().Audio
	if report.killed then
		flashHitmarker(colors.danger, true)
		if audio.KillSound then
			AudioController.play(if report.zone == "Head" then "Hit.KillHead" else "Hit.Kill")
			AudioController.play("Hit.KillBass")
		end
		LightingController.killPop()
		CameraController.fovPop(-1.4)
		ViewmodelController.hitStop(0.045)
		chromaticPulse(0.6)
		AudioController.duck(0.35, 0.6)
	else
		local color = if report.zone == "Head"
			then colors.gold
			elseif report.armorBroken then colors.armor
			else Color3.new(1, 1, 1)
		flashHitmarker(color, false)
		if audio.HitSound then
			AudioController.play(
				if report.armorBroken then "Hit.ArmorBreak" elseif report.zone == "Head" then "Hit.Head" else "Hit.Body"
			)
		end
	end
	addDamageNumber(report)
	CharacterAnimator.flinch(report.position, report.zone == "Head")
end

---------------------------------------------------------------------------------------------
-- Santé, bouclier, vignettes, indicateurs directionnels
---------------------------------------------------------------------------------------------

local healthBar: HudWidgets.SegmentBar
local armorBar: HudWidgets.SegmentBar
local healthText: TextLabel
local armorText: TextLabel
local vignetteEdges: { Frame } = {}
local lastHealth = Ballistics.MAX_HEALTH
local damageFlashUntil = 0

local function buildVignette(parent: Instance)
	local specs = {
		{ position = UDim2.fromScale(0, 0), size = UDim2.fromScale(1, 0.22), rotation = 90 },
		{ position = UDim2.fromScale(0, 0.78), size = UDim2.fromScale(1, 0.22), rotation = -90 },
		{ position = UDim2.fromScale(0, 0), size = UDim2.fromScale(0.16, 1), rotation = 0 },
		{ position = UDim2.fromScale(0.84, 0), size = UDim2.fromScale(0.16, 1), rotation = 180 },
	}
	for _, spec in specs do
		local edge = UI.frame({
			BackgroundColor3 = colors.danger,
			BackgroundTransparency = 1,
			Position = spec.position,
			Size = spec.size,
			ZIndex = 1,
			Parent = parent,
		})
		UI.gradient(edge, ColorSequence.new(colors.danger), spec.rotation, NumberSequence.new(0, 1))
		table.insert(vignetteEdges, edge)
	end
end

type Indicator = { holder: Frame, wedge: Frame, from: Vector3, born: number, strength: number }
local indicators: { Indicator } = {}
local indicatorLayer: Frame

local function addIndicator(from: Vector3, damage: number)
	local holder = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(300, 300),
		ZIndex = 15,
		Parent = indicatorLayer,
	})
	local wedge = UI.frame({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(86, 10),
		BackgroundColor3 = colors.danger,
		ZIndex = 15,
		Parent = holder,
	})
	UI.corner(5, wedge)
	UI.gradient(
		wedge,
		ColorSequence.new(colors.danger),
		0,
		NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
	)
	table.insert(indicators, {
		holder = holder,
		wedge = wedge,
		from = from,
		born = os.clock(),
		strength = math.clamp(damage / 60, 0.35, 1),
	})
	while #indicators > 6 do
		local oldest = table.remove(indicators, 1) :: Indicator
		oldest.holder:Destroy()
	end
end

local function updateIndicators()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local now = os.clock()
	for index = #indicators, 1, -1 do
		local indicator = indicators[index]
		local age = now - indicator.born
		if age > 1.6 then
			indicator.holder:Destroy()
			table.remove(indicators, index)
			continue
		end
		local localPoint = camera.CFrame:PointToObjectSpace(indicator.from)
		indicator.holder.Rotation = math.deg(math.atan2(localPoint.X, -localPoint.Z))
		indicator.wedge.BackgroundTransparency = 1 - indicator.strength * (1 - math.clamp((age - 0.6) / 1.0, 0, 1))
	end
end

local function onDamageTaken(packet: Types.DamageTaken)
	addIndicator(packet.from, packet.damage)
	damageFlashUntil = os.clock() + 0.18
	LightingController.damageFlash(math.clamp(packet.damage / 50, 0.25, 1))
	chromaticPulse(math.clamp(packet.damage / 60, 0.3, 1))
	CameraController.punch(Vector3.new(-1.2, (math.random() - 0.5) * 2, (math.random() - 0.5) * 3))
	CameraController.shake(math.clamp(packet.damage / 120, 0.08, 0.35))
	AudioController.play("Hurt", { volume = math.clamp(packet.damage / 60, 0.4, 1) })
	if packet.zone == "Head" then
		AudioController.play("Hit.Head", { volume = 0.5, pitch = 0.7 })
	end
end

local function updateHealth()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (character and humanoid) then
		return
	end
	local health = math.max(0, humanoid.Health)
	local armorValue = character:GetAttribute("Armor")
	local maxArmorValue = character:GetAttribute("MaxArmor")
	local armor = if type(armorValue) == "number" then armorValue else 0
	local maxArmor = if type(maxArmorValue) == "number" then maxArmorValue else Ballistics.MAX_ARMOR
	if math.abs(health - lastHealth) > 0.01 then
		healthBar.set(health, Ballistics.MAX_HEALTH)
		lastHealth = health
	end
	armorBar.set(armor, maxArmor)
	healthText.Text = tostring(math.ceil(health))
	armorText.Text = tostring(math.ceil(armor))
	local fraction = health / Ballistics.MAX_HEALTH
	healthText.TextColor3 = if fraction <= LOW_HEALTH then colors.healthLow else colors.health
	healthBar.setColor(if fraction <= LOW_HEALTH then colors.healthLow else colors.health)
	AudioController.setLowHealth(if health > 0 then fraction else 1)
	LightingController.setLowHealth(if health > 0 then fraction else 1)

	local now = os.clock()
	local low = math.clamp((LOW_HEALTH - fraction) / LOW_HEALTH, 0, 1)
	local pulse = if low > 0 then (0.5 + 0.5 * math.sin(now * (4 + 4 * low))) else 0
	local intensity = math.max(low * (0.45 + 0.35 * pulse), if now < damageFlashUntil then 0.55 else 0)
	if health <= 0 then
		intensity = 0
	end
	for _, edge in vignetteEdges do
		edge.BackgroundTransparency = 1 - intensity
	end
end

---------------------------------------------------------------------------------------------
-- Munitions et arme
---------------------------------------------------------------------------------------------

local ammoWidget: HudWidgets.Ammo
local ammoScale: UIScale
local lastMag = -1
local lastCapacity = -1
local lastWeapon: Types.WeaponDef? = nil

local FIRE_MODE_NAMES: { [string]: string } = {
	Auto = "AUTO",
	Semi = "SEMI",
	Burst = "RAFALE",
	Bolt = "VERROU",
	Pump = "POMPE",
	Melee = "LAME",
}

local function updateAmmo(state: WeaponController.HudState)
	local def = state.def
	if not def then
		return
	end
	local widget = ammoWidget
	if def ~= lastWeapon then
		lastWeapon = def
		widget.weaponName.Text = string.upper(def.displayName)
		widget.fireMode.Text = FIRE_MODE_NAMES[def.fire.mode] or def.fire.mode
		local slots = WeaponController.slots()
		for index, slotName in { "Primary", "Secondary", "Melee" } do
			local slot = widget.slots[slotName]
			local ammo = slots[slotName]
			local slotDef = if ammo then Weapons.get(ammo.w) else nil
			slot.key.Text = tostring(index)
			slot.name.Text = if slotDef then string.upper(slotDef.shortName) else "—"
			HudWidgets.styleSlot(slot, state.slot == slotName)
		end
		lastMag = -1
	end
	local melee = def.category == "Melee"
	widget.mag.Visible = not melee
	widget.reserve.Visible = not melee
	widget.pips.Visible = not melee
	if state.mag ~= lastMag or state.capacity ~= lastCapacity then
		if state.mag < lastMag then
			ammoScale.Scale = 1.08
			UI.tween(ammoScale, QUAD_OUT, { Scale = 1 })
		end
		lastMag = state.mag
		lastCapacity = state.capacity
		widget.mag.Text = tostring(state.mag)
		if not melee then
			HudWidgets.renderPips(widget.pips, state.mag, state.capacity)
		end
	end
	widget.reserve.Text = "/ " .. (if state.reserve >= 999 then "∞" else tostring(state.reserve))
	local ratio = if state.capacity > 0 then state.mag / state.capacity else 1
	widget.mag.TextColor3 = if state.mag <= 0 then colors.danger elseif ratio <= 0.3 then colors.warning else colors.text
	widget.reloadTrack.Visible = state.reloading
	widget.reloadFill.Size = UDim2.fromScale(if state.reloading then state.reloadProgress else 0, 1)
	local needsReload = not melee and not state.reloading and state.mag <= 0 and state.reserve > 0
	local hint = widget.reloadHint
	hint.Visible = needsReload
	if needsReload then
		hint.TextTransparency = 0.25 + 0.25 * math.sin(os.clock() * 8)
		hint.Text = ("RECHARGER  [%s]"):format(SettingsController.get().Keybinds.Reload or "R")
	end
end

---------------------------------------------------------------------------------------------
-- Barre de match, boussole, killfeed
---------------------------------------------------------------------------------------------

local matchBar: Frame
local bar: HudWidgets.MatchBar
local compass: Frame
local compassStrip: Frame
local compassLabels: { { label: TextLabel, heading: number } } = {}
local compassObjective: TextLabel
local killfeed: Frame

local PHASE_NAMES: { [string]: string } = {
	Waiting = "EN ATTENTE",
	Intro = "INTRODUCTION",
	Prep = "PRÉPARATION",
	Live = "",
	Planted = "UPLINK ARMÉ",
	RoundEnd = "FIN DE MANCHE",
	SideSwap = "CHANGEMENT DE CAMP",
	MatchEnd = "FIN DU MATCH",
	Closed = "",
}

local function renderPips(container: Frame, data: Types.MatchStateData, team: string, color: Color3)
	local alive, total = 0, 0
	for _, entry in data.players do
		if entry.team == team then
			total += 1
			if entry.alive then
				alive += 1
			end
		end
	end
	HudWidgets.renderAlive(container, alive, total, color)
end

local function updateMatchBar(data: Types.MatchStateData)
	local myTeam = ClientState.myTeam() or "A"
	local enemyTeam = if myTeam == "A" then "B" else "A"
	local scores = data.scores :: any
	bar.scoreLeft.Text = tostring(scores[myTeam] or 0)
	bar.scoreRight.Text = tostring(scores[enemyTeam] or 0)
	local sides = data.sides :: any
	local mySide: string = sides[myTeam] or "Attack"
	local enemySide: string = sides[enemyTeam] or "Defense"
	bar.sideLeft.Text = (Theme.sideNames :: any)[mySide] or mySide
	bar.sideRight.Text = (Theme.sideNames :: any)[enemySide] or enemySide
	bar.sideLeft.TextColor3 = colors.ally
	bar.sideRight.TextColor3 = colors.enemy
	bar.stripLeft.BackgroundColor3 = colors.ally
	bar.stripRight.BackgroundColor3 = colors.enemy
	renderPips(bar.pipsLeft, data, myTeam, colors.ally)
	renderPips(bar.pipsRight, data, enemyTeam, colors.enemy)
	local remaining = math.max(0, data.phaseEndsAt - serverNow())
	local planted = data.phase == "Planted"
	local timer = bar.timer
	if planted then
		timer.Text = string.format("%.1f", remaining)
		timer.TextColor3 = colors.danger
		timer.TextTransparency = if remaining < 10 then 0.3 * (0.5 + 0.5 * math.sin(os.clock() * 12)) else 0
	else
		timer.Text = UI.formatTime(remaining)
		timer.TextColor3 = if data.phase == "Live" and remaining <= 10 then colors.warning else colors.text
		timer.TextTransparency = 0
	end
	local phaseName = PHASE_NAMES[data.phase] or ""
	local roundText = ("MANCHE %d%s"):format(data.round, if data.overtime then "  ·  PROLONGATION" else "")
	bar.round.Text = if phaseName ~= "" then roundText .. "  ·  " .. phaseName else roundText
end

local function buildCompass(parent: Instance)
	compass = UI.frame({
		Name = "Compass",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 92),
		Size = UDim2.fromOffset(420, 26),
		ClipsDescendants = true,
		Parent = parent,
	})
	UI.gradient(
		compass,
		ColorSequence.new(Color3.new(1, 1, 1)),
		0,
		NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.2, 0),
			NumberSequenceKeypoint.new(0.8, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
	)
	compassStrip = UI.frame({ BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = compass })
	local names: { [number]: string } =
		{ [0] = "N", [45] = "NE", [90] = "E", [135] = "SE", [180] = "S", [225] = "SO", [270] = "O", [315] = "NO" }
	for heading = 0, 345, 15 do
		local cardinal = names[heading]
		local label = UI.text({
			Text = cardinal or tostring(heading),
			FontFace = if cardinal then fonts.heading else fonts.body,
			TextSize = if cardinal then 15 else 11,
			TextColor3 = if cardinal then colors.text else colors.textDim,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(36, 20),
			Parent = compassStrip,
		})
		table.insert(compassLabels, { label = label, heading = heading })
	end
	compassObjective = UI.text({
		Text = "◆",
		TextColor3 = colors.warning,
		FontFace = fonts.heading,
		TextSize = 16,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(20, 20),
		Visible = false,
		Parent = compassStrip,
	})
	UI.frame({
		BackgroundColor3 = colors.primary,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromOffset(2, 6),
		Parent = compass,
	})
end

local function updateCompass()
	local visible = SettingsController.get().Hud.Compass
	compass.Visible = visible
	if not visible then
		return
	end
	local yaw = CameraController.getYawPitch()
	local heading = (-math.deg(yaw)) % 360
	local pixelsPerDegree = 420 / 120
	for _, item in compassLabels do
		local delta = ((item.heading - heading + 180) % 360) - 180
		item.label.Position = UDim2.new(0.5, delta * pixelsPerDegree, 0.5, 0)
		item.label.Visible = math.abs(delta) < 64
	end
	local core = CollectionService:GetTagged("UplinkCore")[1]
	local camera = Workspace.CurrentCamera
	if core and core:IsA("BasePart") and camera then
		local offset = core.Position - camera.CFrame.Position
		local coreHeading = math.deg(math.atan2(offset.X, -offset.Z)) % 360
		local delta = ((coreHeading - heading + 180) % 360) - 180
		compassObjective.Position = UDim2.new(0.5, math.clamp(delta, -58, 58) * pixelsPerDegree, 0.5, 0)
		compassObjective.Visible = true
		compassObjective.TextColor3 = if core:GetAttribute("Planted") == true then colors.danger else colors.warning
	else
		compassObjective.Visible = false
	end
end

local function addKillfeedEntry(event: Types.KillEvent)
	local myTeam = ClientState.myTeam()
	local mine = event.killer == player.UserId or event.victim == player.UserId
	local function teamColor(team: string): Color3
		if myTeam == nil or team == "" then
			return colors.text
		end
		return if team == myTeam then colors.ally else colors.enemy
	end
	local def = Weapons.get(event.weapon)
	local weaponText = if def then def.shortName elseif event.weapon == "fall" then "CHUTE" else event.weapon
	local markers = {}
	if event.headshot then
		table.insert(markers, "TÊTE")
	end
	if event.wallbang then
		table.insert(markers, "À TRAVERS")
	end
	if event.noscope then
		table.insert(markers, "SANS VISÉE")
	end
	local text = ('<font color="#%s"><b>%s</b></font>   <font color="#%s">%s%s</font>   <font color="#%s"><b>%s</b></font>'):format(
		teamColor(event.killerTeam):ToHex(),
		event.killerName,
		colors.textDim:ToHex(),
		weaponText,
		if #markers > 0 then "  ·  " .. table.concat(markers, " · ") else "",
		teamColor(event.victimTeam):ToHex(),
		event.victimName
	)
	local accent = if not mine then nil elseif event.killer == player.UserId then colors.primary else colors.danger
	local entry = HudWidgets.killfeedEntry(killfeed, text, accent)
	entry.LayoutOrder = -math.floor(os.clock() * 1000)
	local children = {}
	for _, child in killfeed:GetChildren() do
		if child:IsA("Frame") then
			table.insert(children, child)
		end
	end
	if #children > 5 then
		table.sort(children, function(a: Frame, b: Frame): boolean
			return a.LayoutOrder > b.LayoutOrder
		end)
		children[1]:Destroy()
	end
	task.delay(6, function()
		if entry.Parent then
			UI.tween(entry, TweenInfo.new(0.4), { BackgroundTransparency = 1 })
			task.delay(0.4, function()
				entry:Destroy()
			end)
		end
	end)
end

local function onKill(event: Types.KillEvent)
	addKillfeedEntry(event)
	if event.killer == player.UserId then
		confirmKill(event)
	end
end

---------------------------------------------------------------------------------------------
-- Tableau des scores
---------------------------------------------------------------------------------------------

local boardOpen = false
local boardForced = false
local boardBody: Frame
local boardTitle: TextLabel

local function boardRow(parent: Instance, entry: Types.MatchPlayerData, order: number, color: Color3, mvp: boolean)
	local isMe = entry.userId == player.UserId
	local row = UI.frame({
		BackgroundColor3 = if isMe then colors.panelLight else colors.panel,
		BackgroundTransparency = if entry.alive then 0.15 else 0.5,
		Size = UDim2.new(1, 0, 0, 34),
		LayoutOrder = order,
		Parent = parent,
	})
	UI.accent(row, color, 3)
	local tier = Ranks.tierOf(entry.rankIndex)
	local function cell(
		text: string,
		x: number,
		width: number,
		align: Enum.TextXAlignment,
		font: Font?,
		textColor: Color3?
	)
		UI.text({
			Text = text,
			Position = UDim2.new(x, 0, 0, 0),
			Size = UDim2.new(width, 0, 1, 0),
			TextXAlignment = align,
			FontFace = font or fonts.mono,
			TextSize = 15,
			TextColor3 = textColor or (if entry.alive then colors.text else colors.textFaint),
			Parent = row,
		})
	end
	cell(tier.glyph, 0.015, 0.04, Enum.TextXAlignment.Center, fonts.heading, tier.color)
	cell(
		(if mvp then "★ " else "") .. entry.name .. (if entry.connected then "" else "  (déconnecté)"),
		0.06,
		0.4,
		Enum.TextXAlignment.Left,
		fonts.bodyBold
	)
	cell(tostring(entry.kills), 0.47, 0.08, Enum.TextXAlignment.Center)
	cell(tostring(entry.deaths), 0.55, 0.08, Enum.TextXAlignment.Center)
	cell(tostring(entry.assists), 0.63, 0.08, Enum.TextXAlignment.Center)
	cell(tostring(entry.damage), 0.72, 0.12, Enum.TextXAlignment.Center)
	cell(tostring(entry.score), 0.85, 0.13, Enum.TextXAlignment.Center, fonts.monoBold)
end

local function renderBoard()
	local data = ClientState.matchData()
	for _, child in boardBody:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	if not data then
		return
	end
	local myTeam = ClientState.myTeam() or "A"
	local scores = data.scores :: any
	boardTitle.Text = ("%s  ·  %s  ·  MANCHE %d"):format(string.upper(data.map), string.upper(data.mode), data.round)
	local order = 0
	for _, team in { myTeam, if myTeam == "A" then "B" else "A" } do
		local color = if team == myTeam then colors.ally else colors.enemy
		order += 1
		local header = UI.frame({
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 30),
			LayoutOrder = order,
			Parent = boardBody,
		})
		local sides = data.sides :: any
		UI.text({
			Text = ("%s  %d"):format((Theme.sideNames :: any)[sides[team]] or team, scores[team] or 0),
			FontFace = fonts.display,
			TextSize = 18,
			TextColor3 = color,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.fromScale(0.5, 1),
			Parent = header,
		})
		UI.text({
			Text = "K          D          A          DÉGÂTS          SCORE",
			FontFace = fonts.mono,
			TextSize = 12,
			TextColor3 = colors.textDim,
			TextXAlignment = Enum.TextXAlignment.Right,
			Position = UDim2.fromScale(0.45, 0),
			Size = UDim2.fromScale(0.53, 1),
			Parent = header,
		})
		local list: { Types.MatchPlayerData } = {}
		for _, entry in data.players do
			if entry.team == team then
				table.insert(list, entry)
			end
		end
		table.sort(list, function(a: Types.MatchPlayerData, b: Types.MatchPlayerData): boolean
			return a.score > b.score
		end)
		for _, entry in list do
			order += 1
			boardRow(boardBody, entry, order, color, data.mvp == entry.userId)
		end
	end
end

local function setBoardVisible(open: boolean)
	local show = open and ClientState.matchData() ~= nil
	boardGui.Enabled = show
	if show then
		renderBoard()
	end
end

---------------------------------------------------------------------------------------------
-- Bannières, toasts, interaction
---------------------------------------------------------------------------------------------

local bannerTitle: TextLabel
local bannerSubtitle: TextLabel
local bannerLine: Frame
local bannerToken = 0
local toastList: Frame
local interactionPanel: Frame
local interactionKey: TextLabel
local interactionText: TextLabel
local interactionFill: Frame

--[[ Grande annonce centrale (manche, uplink, clutch…). ]]
function HUDController.banner(title: string, subtitle: string?, color: Color3?, duration: number?)
	bannerToken += 1
	local token = bannerToken
	local tint = color or colors.primary
	bannerTitle.Text = title
	bannerTitle.TextColor3 = tint
	bannerSubtitle.Text = subtitle or ""
	bannerLine.BackgroundColor3 = tint
	bannerTitle.TextTransparency = 0
	bannerSubtitle.TextTransparency = 0
	bannerLine.BackgroundTransparency = 0
	bannerLine.Size = UDim2.fromOffset(0, 2)
	UI.tween(bannerLine, Theme.tween.slow, { Size = UDim2.fromOffset(520, 2) })
	task.delay(duration or 2.6, function()
		if token ~= bannerToken then
			return
		end
		UI.tween(bannerTitle, TweenInfo.new(0.35), { TextTransparency = 1 })
		UI.tween(bannerSubtitle, TweenInfo.new(0.35), { TextTransparency = 1 })
		UI.tween(bannerLine, TweenInfo.new(0.35), { BackgroundTransparency = 1 })
	end)
end

local TOAST_COLORS: { [string]: Color3 } = {
	Reward = colors.secondary,
	LevelUp = colors.gold,
	RankUp = colors.gold,
	RankDown = colors.textDim,
	MissionComplete = colors.success,
	PassTier = colors.secondary,
	Purchase = colors.success,
	Error = colors.danger,
	Info = colors.primary,
	PartyInvite = colors.primary,
	RejoinAvailable = colors.warning,
}

local TOAST_TITLES: { [string]: string } = {
	Reward = "RÉCOMPENSE",
	LevelUp = "NIVEAU SUPÉRIEUR",
	RankUp = "PROMOTION",
	RankDown = "RANG",
	MissionComplete = "MISSION ACCOMPLIE",
	PassTier = "PASSE DE COMBAT",
	Purchase = "ACHAT",
	Error = "ERREUR",
	Info = "INFO",
	PartyInvite = "ESCOUADE",
	RejoinAvailable = "MATCH EN COURS",
}

--[[ Notification discrète (coin droit), visible partout (hub compris). ]]
function HUDController.toast(text: string, kind: string?)
	local color = TOAST_COLORS[kind or "Info"] or colors.primary
	local toast = HudWidgets.toast(toastList, TOAST_TITLES[kind or "Info"] or "INFO", text, color)
	toast.LayoutOrder = -math.floor(os.clock() * 1000)
	local scale = Instance.new("UIScale")
	scale.Scale = 0.85
	scale.Parent = toast
	UI.tween(scale, Theme.tween.bounce, { Scale = 1 })
	AudioController.play(if kind == "Error" then "UI.Error" else "UI.Confirm")
	task.delay(4.5, function()
		if toast.Parent then
			UI.tween(toast, TweenInfo.new(0.35), { BackgroundTransparency = 1 })
			task.delay(0.35, function()
				toast:Destroy()
			end)
		end
	end)
end

--[[ Invite contextuelle (« Maintenir [F] pour armer l'uplink ») + progression. ]]
function HUDController.setInteraction(text: string?, progress: number?)
	interactionPanel.Visible = text ~= nil
	if text then
		-- « Maintenir [F] pour … » : la touche passe dans la pastille, le reste en clair.
		local key = SettingsController.get().Keybinds.Interact or "F"
		interactionKey.Text = key
		local cleaned = string.gsub(string.gsub(text, "%s*%[" .. key .. "%]%s*", " "), "%s+", " ")
		interactionText.Text = cleaned
		interactionFill.Size = UDim2.fromScale(math.clamp(progress or 0, 0, 1), 1)
	end
end

function HUDController.setVisible(visible: boolean)
	visibleRequested = visible
end

function HUDController.setScoreboardForced(open: boolean)
	boardForced = open
	setBoardVisible(boardOpen or boardForced)
end

function HUDController.resetRoundKills()
	roundKills = 0
	renderKillPips()
end

---------------------------------------------------------------------------------------------
-- Lunette, Training, statistiques réseau
---------------------------------------------------------------------------------------------

local scopeOverlay: Frame
local wasScoped = false
local trainingPanel: Frame
local trainingValues: { [string]: TextLabel } = {}
local TRAINING_ROWS = {
	{ "Shots", "Tirs" },
	{ "Accuracy", "Précision" },
	{ "Head", "Tête" },
	{ "Damage", "Dégâts" },
	{ "Kills", "Éliminations" },
	{ "Armor", "Boucliers" },
}
local netStats: TextLabel
local fpsAverage = 60

local function buildScope(parent: Instance)
	scopeOverlay = UI.frame({
		Name = "Scope",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 5,
		Parent = parent,
	})
	local lens = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.82, 0.82),
		ZIndex = 5,
		Parent = scopeOverlay,
	})
	-- Lentille carrée calée sur la HAUTEUR de l'écran (sinon elle déborde en 16:9).
	UI.aspect(lens, 1).DominantAxis = Enum.DominantAxis.Height
	UI.corner(9999, lens)
	-- L'anneau noir épais masque les coins entre le cercle et son carré englobant ;
	-- quatre caches couvrent le reste de l'écran quelle que soit la résolution.
	UI.stroke(lens, Color3.new(0, 0, 0), 600, 0)
	for _, spec in
		{
			{ anchor = Vector2.new(1, 0.5), position = UDim2.fromScale(0, 0.5), size = UDim2.new(0, 4000, 0, 8000) },
			{ anchor = Vector2.new(0, 0.5), position = UDim2.fromScale(1, 0.5), size = UDim2.new(0, 4000, 0, 8000) },
			{ anchor = Vector2.new(0.5, 1), position = UDim2.fromScale(0.5, 0), size = UDim2.new(0, 8000, 0, 4000) },
			{ anchor = Vector2.new(0.5, 0), position = UDim2.fromScale(0.5, 1), size = UDim2.new(0, 8000, 0, 4000) },
		}
	do
		UI.frame({
			BackgroundColor3 = Color3.new(0, 0, 0),
			AnchorPoint = spec.anchor,
			Position = spec.position,
			Size = spec.size,
			ZIndex = 5,
			Parent = lens,
		})
	end
	local inner = UI.frame({
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
		Parent = lens,
	})
	UI.corner(9999, inner)
	UI.stroke(inner, Color3.fromRGB(10, 14, 20), 26, 0.35)
	for _, spec in
		{
			{ size = UDim2.new(1, 0, 0, 2), position = UDim2.fromScale(0, 0.5) },
			{ size = UDim2.new(0, 2, 1, 0), position = UDim2.fromScale(0.5, 0) },
		}
	do
		UI.frame({
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.1,
			AnchorPoint = Vector2.new(0, 0),
			Position = spec.position,
			Size = spec.size,
			ZIndex = 6,
			Parent = lens,
		})
	end
	local dot = UI.frame({
		BackgroundColor3 = colors.danger,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(4, 4),
		ZIndex = 7,
		Parent = lens,
	})
	UI.corner(2, dot)
end

local function trainingStats(): { [string]: any }?
	local replica = ReplicaController.get("TrainingStats")
	return if replica then replica.data else nil
end

local function updateTraining()
	local kind = ClientState.arena()
	local show = kind == "Training"
	trainingPanel.Visible = show
	if not show then
		return
	end
	local stats = trainingStats()
	if not stats then
		for _, value in trainingValues do
			value.Text = "…"
		end
		return
	end
	local shots = tonumber(stats.shots) or 0
	local hits = tonumber(stats.hits) or 0
	local headshots = tonumber(stats.headshots) or 0
	trainingValues.Shots.Text = tostring(shots)
	trainingValues.Accuracy.Text = ("%d %%"):format(if shots > 0 then math.floor(hits / shots * 100 + 0.5) else 0)
	trainingValues.Head.Text = ("%d %%"):format(if hits > 0 then math.floor(headshots / hits * 100 + 0.5) else 0)
	trainingValues.Damage.Text = tostring(tonumber(stats.damage) or 0)
	trainingValues.Kills.Text = tostring(tonumber(stats.kills) or 0)
	trainingValues.Armor.Text = if stats.armor then "OUI" else "NON"
end

local function updateNetStats(dt: number)
	local video = SettingsController.get().Video
	local hudSettings = SettingsController.get().Hud
	local show = video.ShowFps or hudSettings.NetStats
	netStats.Visible = show
	if not show then
		return
	end
	fpsAverage = fpsAverage + (1 / math.max(dt, 1e-3) - fpsAverage) * math.min(1, dt * 4)
	local parts = {}
	if video.ShowFps then
		table.insert(parts, ("%d FPS"):format(math.floor(fpsAverage + 0.5)))
	end
	if hudSettings.NetStats then
		table.insert(parts, ("%d ms"):format(math.floor(player:GetNetworkPing() * 1000 + 0.5)))
	end
	netStats.Text = table.concat(parts, "  ·  ")
end

---------------------------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------------------------

local function buildHealth(parent: Instance)
	local vitals = HudWidgets.vitals(parent)
	healthText = vitals.health
	armorText = vitals.armor
	healthBar = vitals.healthBar
	armorBar = vitals.armorBar
	-- Portrait : la tête de l'avatar Roblox du joueur (miniature servie par Roblox).
	vitals.portrait.Image = ("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"):format(math.max(player.UserId, 1))
end

local function buildAmmo(parent: Instance)
	ammoWidget = HudWidgets.ammo(parent)
	ammoScale = Instance.new("UIScale")
	ammoScale.Parent = ammoWidget.mag
end

local function buildMatchBar(parent: Instance)
	bar = HudWidgets.matchBar(parent)
	matchBar = bar.root
end

local function buildCenter(parent: Instance)
	indicatorLayer = UI.frame({ BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = parent })
	crosshair = buildCrosshair(parent)
	buildHitmarker(parent)
	local banner = HudWidgets.banner(overlay)
	bannerTitle = banner.title
	bannerSubtitle = banner.subtitle
	bannerLine = banner.line
	local confirm = HudWidgets.killConfirm(parent)
	killConfirm = confirm.text
	killPips = confirm.pips
	local interaction = HudWidgets.interaction(parent)
	interactionPanel = interaction.root
	interactionKey = interaction.key
	interactionText = interaction.text
	interactionFill = interaction.fill
end

local function buildScoreboard()
	boardGui = UI.screen("AS_Scoreboard", 20)
	boardGui.Enabled = false
	local panel = UI.panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(860, 560),
		BackgroundTransparency = 0.08,
		Parent = boardGui,
	})
	UI.padding(panel, 24, 24, 18, 18)
	boardTitle = UI.text({
		Text = "",
		FontFace = fonts.display,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 30),
		Parent = panel,
	})
	boardBody = UI.frame({
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 1, -40),
		Parent = panel,
	})
	UI.list(boardBody, Enum.FillDirection.Vertical, 4)
end

local function buildSide(parent: Instance)
	killfeed = UI.frame({
		Name = "Killfeed",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -24, 0, 62),
		Size = UDim2.fromOffset(460, 200),
		Parent = overlay,
	})
	UI.list(killfeed, Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Right)

	local stats = HudWidgets.statPanel(parent, "STAND DE TIR", colors.success, TRAINING_ROWS)
	trainingPanel = stats.root
	trainingPanel.Visible = false
	trainingValues = stats.values

	netStats = UI.text({
		Text = "",
		FontFace = fonts.bodyBold,
		TextSize = 13,
		TextColor3 = colors.textDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(12, 6),
		Size = UDim2.fromOffset(240, 18),
		Parent = hud,
	})
end

---------------------------------------------------------------------------------------------
-- Boucle
---------------------------------------------------------------------------------------------

local function update(dt: number)
	local state = WeaponController.hudState()
	local kind = ClientState.arena()
	local data = ClientState.matchData()
	local cameraMode = CameraController.getMode()
	local combat = WeaponController.isArmed() and cameraMode == "FirstPerson"
	root.Visible = visibleRequested and combat
	overlay.Visible = visibleRequested
	matchBar.Visible = visibleRequested and kind == "Match" and data ~= nil and cameraMode ~= "Cinematic"
	updateNetStats(dt)
	updateDamageNumbers()
	if matchBar.Visible and data then
		updateMatchBar(data)
	end
	if boardGui.Enabled and math.floor(os.clock() * 2) ~= math.floor((os.clock() - dt) * 2) then
		renderBoard()
	end
	if not root.Visible then
		if wasScoped then
			wasScoped = false
			LightingController.setScope(false)
		end
		scopeOverlay.Visible = false
		return
	end
	updateCrosshair(dt, state)
	updateAmmo(state)
	updateHealth()
	updateIndicators()
	updateCompass()
	updateTraining()
	compass.Visible = compass.Visible and kind == "Match"
	scopeOverlay.Visible = state.scoped
	if state.scoped ~= wasScoped then
		wasScoped = state.scoped
		LightingController.setScope(state.scoped)
	end
end

function HUDController.start()
	hud = UI.screen("AS_HUD", 10)
	worldGui = Instance.new("ScreenGui")
	worldGui.Name = "AS_World"
	worldGui.ResetOnSpawn = false
	worldGui.IgnoreGuiInset = true
	worldGui.DisplayOrder = 9
	worldGui.Parent = player:WaitForChild("PlayerGui")
	toastGui = UI.screen("AS_Toasts", 50)
	toastList = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -24, 0.42, 0),
		Size = UDim2.fromOffset(340, 400),
		Parent = toastGui,
	})
	UI.list(toastList, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Bottom)

	root = UI.frame({ Name = "Combat", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = hud })
	overlay = UI.frame({
		Name = "Overlay",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 30,
		Parent = hud,
	})
	-- Les éléments ancrés aux bords (santé, munitions, boussole, killfeed) vivent dans une
	-- zone sûre : sur téléphone, ni encoche ni coin arrondi ne les mangent. Les overlays
	-- plein écran (lunette, vignette) restent sur tout l'écran.
	-- ZIndex 3 : au-dessus de la vignette (1) et des franges (2), sous la lunette (5+),
	-- comme lorsque ces éléments étaient directement enfants de `root`.
	local safe = UI.frame({
		Name = "SafeArea",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
		Parent = root,
	})
	local safePadding = Instance.new("UIPadding")
	safePadding.Parent = safe
	local function refreshSafeArea()
		local left, top, right, bottom = UI.safeInsets()
		local scale = hud:FindFirstChildOfClass("UIScale")
		local factor = if scale and scale.Scale > 0 then 1 / scale.Scale else 1
		safePadding.PaddingLeft = UDim.new(0, left * factor)
		safePadding.PaddingTop = UDim.new(0, top * factor)
		safePadding.PaddingRight = UDim.new(0, right * factor)
		safePadding.PaddingBottom = UDim.new(0, bottom * factor)
	end
	buildScope(root)
	buildVignette(root)
	buildFringes(root)
	buildCenter(root)
	buildHealth(safe)
	buildAmmo(safe)
	buildCompass(safe)
	buildSide(safe)
	task.defer(refreshSafeArea)
	local viewportCamera = Workspace.CurrentCamera
	if viewportCamera then
		viewportCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			task.defer(refreshSafeArea)
		end)
	end
	buildMatchBar(hud)
	buildScoreboard()

	WeaponController.HitConfirmed:Connect(onHitConfirmed)
	WeaponController.Fired:Connect(function(def: Types.WeaponDef)
		crosshairKick:impulse(def.recoil.kickUp * 30 + 20)
	end)
	Net.event("Kill").OnClientEvent:Connect(onKill)
	Net.event("DamageTaken").OnClientEvent:Connect(onDamageTaken)
	Net.event("Notify").OnClientEvent:Connect(function(payload: any)
		if type(payload) == "table" and type(payload.text) == "string" then
			local kind = if type(payload.kind) == "string" then payload.kind else "Info"
			if kind ~= "PartyInvite" and kind ~= "RejoinAvailable" then
				HUDController.toast(payload.text, kind)
			end
		end
	end)
	InputController.ActionBegan:Connect(function(action: string)
		if action == "Scoreboard" then
			boardOpen = true
			setBoardVisible(true)
		end
	end)
	InputController.ActionEnded:Connect(function(action: string)
		if action == "Scoreboard" then
			boardOpen = false
			setBoardVisible(boardForced)
		end
	end)
	SettingsController.Changed:Connect(function(settings: Types.SettingsData)
		UI.setUserScale(settings.Hud.Scale)
	end)
	UI.setUserScale(SettingsController.get().Hud.Scale)
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(UI.refreshScales)
	end
	player.CharacterAdded:Connect(function()
		lastHealth = Ballistics.MAX_HEALTH
		healthBar.set(Ballistics.MAX_HEALTH, Ballistics.MAX_HEALTH)
	end)
	RunService.RenderStepped:Connect(update)
end

return HUDController
