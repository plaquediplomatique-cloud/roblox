--!strict
--[[
	HUDController — HUD de combat (match + Training Range), lisible en une fraction de
	seconde et entièrement piloté par l'état (aucune logique de jeu ici).

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
local ClientState = require(script.Parent.Parent.Core.ClientState)
local ReplicaController = require(script.Parent.Parent.Core.ReplicaController)
local SettingsController = require(script.Parent.SettingsController)
local InputController = require(script.Parent.InputController)
local CameraController = require(script.Parent.CameraController)
local WeaponController = require(script.Parent.WeaponController)
local ViewmodelController = require(script.Parent.ViewmodelController)
local AudioController = require(script.Parent.AudioController)
local LightingController = require(script.Parent.LightingController)

local colors = Theme.colors
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
		local pip = UI.frame({
			BackgroundColor3 = if roundKills >= 5 then colors.gold else colors.primary,
			Size = UDim2.fromOffset(14, 14),
			Rotation = 45,
			LayoutOrder = index,
			Parent = killPips,
		})
		UI.stroke(pip, Color3.new(0, 0, 0), 1, 0.4)
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
	killConfirm.Text = ('<font color="#%s">%s</font>  ÉLIMINÉ  ·  %s%s'):format(
		(if streak then colors.gold else colors.primary):ToHex(),
		streak or "◆",
		string.upper(event.victimName),
		suffix
	)
	killConfirm.TextTransparency = 0
	UI.glitchText(killConfirm, 0.18)
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
end

---------------------------------------------------------------------------------------------
-- Santé, bouclier, vignettes, indicateurs directionnels
---------------------------------------------------------------------------------------------

local healthBar: UI.Bar
local armorBar: UI.Bar
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
	healthText.TextColor3 = if fraction <= 0.35 then colors.healthLow else colors.health
	healthBar.fill.BackgroundColor3 = if fraction <= 0.35 then colors.healthLow else colors.health
	AudioController.setLowHealth(if health > 0 then fraction else 1)
	LightingController.setLowHealth(if health > 0 then fraction else 1)

	local now = os.clock()
	local low = math.clamp((0.35 - fraction) / 0.35, 0, 1)
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

local ammoMag: TextLabel
local ammoReserve: TextLabel
local ammoScale: UIScale
local weaponName: TextLabel
local fireModeLabel: TextLabel
local reloadFill: Frame
local reloadHint: TextLabel
local slotLabels: { [string]: TextLabel } = {}
local lastMag = -1
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
	if def ~= lastWeapon then
		lastWeapon = def
		weaponName.Text = string.upper(def.displayName)
		fireModeLabel.Text = FIRE_MODE_NAMES[def.fire.mode] or def.fire.mode
		UI.glitchText(weaponName, 0.15)
		local slots = WeaponController.slots()
		for slotName, label in slotLabels do
			local ammo = slots[slotName]
			local slotDef = if ammo then Weapons.get(ammo.w) else nil
			label.Text = if slotDef then slotDef.shortName else "—"
			local active = state.slot == slotName
			label.TextColor3 = if active then colors.primary else colors.textFaint
			label.FontFace = if active then fonts.monoBold else fonts.mono
		end
	end
	local melee = def.category == "Melee"
	ammoMag.Visible = not melee
	ammoReserve.Visible = not melee
	if state.mag ~= lastMag then
		if state.mag < lastMag then
			ammoScale.Scale = 1.12
			UI.tween(ammoScale, QUAD_OUT, { Scale = 1 })
		end
		lastMag = state.mag
		ammoMag.Text = tostring(state.mag)
	end
	ammoReserve.Text = "/ " .. (if state.reserve >= 999 then "∞" else tostring(state.reserve))
	local ratio = if state.capacity > 0 then state.mag / state.capacity else 1
	ammoMag.TextColor3 = if state.mag <= 0 then colors.danger elseif ratio <= 0.3 then colors.warning else colors.text
	reloadFill.Size = UDim2.fromScale(if state.reloading then state.reloadProgress else 0, 1)
	local needsReload = not melee and not state.reloading and state.mag <= 0 and state.reserve > 0
	reloadHint.Visible = needsReload
	if needsReload then
		reloadHint.TextTransparency = 0.25 + 0.25 * math.sin(os.clock() * 8)
		reloadHint.Text = ("RECHARGER  [%s]"):format(SettingsController.get().Keybinds.Reload or "R")
	end
end

---------------------------------------------------------------------------------------------
-- Barre de match, boussole, killfeed
---------------------------------------------------------------------------------------------

local matchBar: Frame
local scoreLeft: TextLabel
local scoreRight: TextLabel
local sideLeft: TextLabel
local sideRight: TextLabel
local timerLabel: TextLabel
local roundLabel: TextLabel
local pipsLeft: Frame
local pipsRight: Frame
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
	local children = {}
	for _, child in container:GetChildren() do
		if child:IsA("Frame") then
			table.insert(children, child)
		end
	end
	for index = 1, math.max(total, #children) do
		local pip = children[index]
		if index > total then
			if pip then
				pip:Destroy()
			end
			continue
		end
		if not pip then
			pip = UI.frame({ Size = UDim2.fromOffset(18, 5), LayoutOrder = index, Parent = container })
		end
		local frame = pip :: Frame
		frame.BackgroundColor3 = if index <= alive then color else colors.stroke
		frame.BackgroundTransparency = if index <= alive then 0 else 0.3
	end
end

local function updateMatchBar(data: Types.MatchStateData)
	local myTeam = ClientState.myTeam() or "A"
	local enemyTeam = if myTeam == "A" then "B" else "A"
	local scores = data.scores :: any
	scoreLeft.Text = tostring(scores[myTeam] or 0)
	scoreRight.Text = tostring(scores[enemyTeam] or 0)
	local sides = data.sides :: any
	local mySide: string = sides[myTeam] or "Attack"
	local enemySide: string = sides[enemyTeam] or "Defense"
	sideLeft.Text = (Theme.sideNames :: any)[mySide] or mySide
	sideRight.Text = (Theme.sideNames :: any)[enemySide] or enemySide
	sideLeft.TextColor3 = colors.ally
	sideRight.TextColor3 = colors.enemy
	renderPips(pipsLeft, data, myTeam, colors.ally)
	renderPips(pipsRight, data, enemyTeam, colors.enemy)
	local remaining = math.max(0, data.phaseEndsAt - serverNow())
	local planted = data.phase == "Planted"
	if planted then
		timerLabel.Text = string.format("%.1f", remaining)
		timerLabel.TextColor3 = colors.danger
		timerLabel.TextTransparency = if remaining < 10 then 0.3 * (0.5 + 0.5 * math.sin(os.clock() * 12)) else 0
	else
		timerLabel.Text = UI.formatTime(remaining)
		timerLabel.TextColor3 = if data.phase == "Live" and remaining <= 10 then colors.warning else colors.text
		timerLabel.TextTransparency = 0
	end
	local phaseName = PHASE_NAMES[data.phase] or ""
	local roundText = ("MANCHE %d%s"):format(data.round, if data.overtime then "  ·  PROLONGATION" else "")
	roundLabel.Text = if phaseName ~= "" then roundText .. "  ·  " .. phaseName else roundText
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
			FontFace = if cardinal then fonts.heading else fonts.mono,
			TextSize = if cardinal then 16 else 11,
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
		table.insert(markers, "⌖")
	end
	if event.wallbang then
		table.insert(markers, "⟂")
	end
	if event.noscope then
		table.insert(markers, "◎")
	end
	local text = ('<font color="#%s">%s</font>  <font color="#%s">[%s%s]</font>  <font color="#%s">%s</font>'):format(
		teamColor(event.killerTeam):ToHex(),
		event.killerName,
		colors.textDim:ToHex(),
		weaponText,
		if #markers > 0 then " " .. table.concat(markers, " ") else "",
		teamColor(event.victimTeam):ToHex(),
		event.victimName
	)
	local entry = UI.panel({
		Size = UDim2.fromOffset(0, 28),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = -math.floor(os.clock() * 1000),
		Parent = killfeed,
	})
	UI.padding(entry, 10, 10, 0, 0)
	if mine then
		UI.stroke(entry, if event.killer == player.UserId then colors.primary else colors.danger, 1.5, 0)
	end
	UI.text({
		Text = text,
		FontFace = fonts.bodyBold,
		TextSize = 16,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		Parent = entry,
	})
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
	UI.glitchText(bannerTitle, 0.25)
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

--[[ Notification discrète (coin droit), visible partout (hub compris). ]]
function HUDController.toast(text: string, kind: string?)
	local color = TOAST_COLORS[kind or "Info"] or colors.primary
	local toast = UI.panel({
		Size = UDim2.fromOffset(340, 52),
		LayoutOrder = -math.floor(os.clock() * 1000),
		Parent = toastList,
	})
	UI.accent(toast, color, 4)
	UI.padding(toast, 16, 10, 4, 4)
	UI.text({
		Text = string.upper(kind or "INFO"),
		FontFace = fonts.heading,
		TextSize = 12,
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 16),
		Parent = toast,
	})
	UI.text({
		Text = text,
		FontFace = fonts.bodyBold,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(0, 16),
		Size = UDim2.new(1, 0, 0, 26),
		Parent = toast,
	})
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
		interactionText.Text = text
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
local trainingText: TextLabel
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
		trainingText.Text = "Chargement…"
		return
	end
	local shots = tonumber(stats.shots) or 0
	local hits = tonumber(stats.hits) or 0
	local headshots = tonumber(stats.headshots) or 0
	trainingText.Text = table.concat({
		("TIRS          %d"):format(shots),
		("PRÉCISION     %d %%"):format(if shots > 0 then math.floor(hits / shots * 100 + 0.5) else 0),
		("TÊTE          %d %%"):format(if hits > 0 then math.floor(headshots / hits * 100 + 0.5) else 0),
		("DÉGÂTS        %d"):format(tonumber(stats.damage) or 0),
		("ÉLIMINATIONS  %d"):format(tonumber(stats.kills) or 0),
		("BOUCLIERS     %s"):format(if stats.armor then "OUI" else "NON"),
	}, "\n")
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
	local panel = UI.panel({
		Name = "Vitals",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 32, 1, -32),
		Size = UDim2.fromOffset(330, 92),
		Parent = parent,
	})
	UI.accent(panel, colors.primary, 3)
	healthText = UI.text({
		Text = "100",
		FontFace = fonts.monoBold,
		TextSize = 44,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(18, 8),
		Size = UDim2.fromOffset(110, 46),
		Parent = panel,
	})
	UI.text({
		Text = "PV",
		FontFace = fonts.heading,
		TextSize = 13,
		TextColor3 = colors.textDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(122, 14),
		Size = UDim2.fromOffset(40, 16),
		Parent = panel,
	})
	armorText = UI.text({
		Text = "50",
		FontFace = fonts.monoBold,
		TextSize = 22,
		TextColor3 = colors.armor,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.fromOffset(220, 14),
		Size = UDim2.fromOffset(60, 26),
		Parent = panel,
	})
	UI.text({
		Text = "BOUCLIER",
		FontFace = fonts.heading,
		TextSize = 12,
		TextColor3 = colors.armor,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.fromOffset(160, 38),
		Size = UDim2.fromOffset(120, 14),
		Parent = panel,
	})
	healthBar = UI.bar(colors.health, {
		Position = UDim2.fromOffset(18, 58),
		Size = UDim2.new(1, -36, 0, 10),
		Parent = panel,
	})
	armorBar = UI.bar(colors.armor, {
		Position = UDim2.fromOffset(18, 72),
		Size = UDim2.new(1, -36, 0, 5),
		Parent = panel,
	})
end

local function buildAmmo(parent: Instance)
	local panel = UI.panel({
		Name = "Ammo",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -32, 1, -32),
		Size = UDim2.fromOffset(330, 118),
		Parent = parent,
	})
	UI.accent(panel, colors.primary, 3)
	weaponName = UI.text({
		Text = "",
		FontFace = fonts.heading,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(18, 8),
		Size = UDim2.fromOffset(220, 20),
		Parent = panel,
	})
	fireModeLabel = UI.text({
		Text = "",
		FontFace = fonts.mono,
		TextSize = 12,
		TextColor3 = colors.primary,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.new(1, -96, 0, 10),
		Size = UDim2.fromOffset(80, 16),
		Parent = panel,
	})
	ammoMag = UI.text({
		Text = "0",
		FontFace = fonts.monoBold,
		TextSize = 52,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(0.55, 0, 0, 26),
		Size = UDim2.fromOffset(150, 54),
		Parent = panel,
	})
	ammoScale = Instance.new("UIScale")
	ammoScale.Parent = ammoMag
	ammoReserve = UI.text({
		Text = "/ 0",
		FontFace = fonts.mono,
		TextSize = 22,
		TextColor3 = colors.textDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.new(0.57, 0, 0, 46),
		Size = UDim2.fromOffset(110, 26),
		Parent = panel,
	})
	local reloadTrack = UI.frame({
		BackgroundColor3 = colors.panelLight,
		Position = UDim2.new(0, 18, 0, 84),
		Size = UDim2.new(1, -36, 0, 3),
		Parent = panel,
	})
	reloadFill = UI.frame({ BackgroundColor3 = colors.primary, Size = UDim2.fromScale(0, 1), Parent = reloadTrack })
	local slots = UI.frame({
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 18, 0, 92),
		Size = UDim2.new(1, -36, 0, 18),
		Parent = panel,
	})
	UI.list(slots, Enum.FillDirection.Horizontal, 16)
	for index, slotName in { "Primary", "Secondary", "Melee" } do
		slotLabels[slotName] = UI.text({
			Text = "—",
			FontFace = fonts.mono,
			TextSize = 13,
			TextColor3 = colors.textFaint,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 18),
			LayoutOrder = index,
			Parent = slots,
		})
	end
	reloadHint = UI.text({
		Text = "RECHARGER",
		FontFace = fonts.heading,
		TextSize = 18,
		TextColor3 = colors.warning,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, 60),
		Size = UDim2.fromOffset(300, 24),
		Visible = false,
		Parent = parent,
	})
	UI.textStroke(reloadHint, 0.4)
end

local function buildMatchBar(parent: Instance)
	matchBar = UI.frame({
		Name = "MatchBar",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 16),
		Size = UDim2.fromOffset(520, 72),
		Parent = parent,
	})
	local center = UI.panel({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(150, 56),
		Parent = matchBar,
	})
	timerLabel = UI.text({
		Text = "0:00",
		FontFace = fonts.monoBold,
		TextSize = 30,
		Size = UDim2.new(1, 0, 0, 36),
		Parent = center,
	})
	roundLabel = UI.text({
		Text = "",
		FontFace = fonts.heading,
		TextSize = 11,
		TextColor3 = colors.textDim,
		Position = UDim2.fromOffset(0, 34),
		Size = UDim2.new(1, 0, 0, 16),
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = center,
	})
	local function side(anchorX: number, x: number): (TextLabel, TextLabel, Frame)
		local block = UI.panel({
			AnchorPoint = Vector2.new(anchorX, 0),
			Position = UDim2.new(0.5, x, 0, 0),
			Size = UDim2.fromOffset(170, 56),
			Parent = matchBar,
		})
		local score = UI.text({
			Text = "0",
			FontFace = fonts.display,
			TextSize = 30,
			AnchorPoint = Vector2.new(anchorX, 0),
			Position = UDim2.new(anchorX, if anchorX == 1 then -14 else 14, 0, 4),
			Size = UDim2.fromOffset(60, 34),
			TextXAlignment = if anchorX == 1 then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left,
			Parent = block,
		})
		local name = UI.text({
			Text = "",
			FontFace = fonts.heading,
			TextSize = 14,
			AnchorPoint = Vector2.new(1 - anchorX, 0),
			Position = UDim2.new(1 - anchorX, if anchorX == 1 then 14 else -14, 0, 10),
			Size = UDim2.fromOffset(80, 20),
			TextXAlignment = if anchorX == 1 then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right,
			Parent = block,
		})
		local pips = UI.frame({
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 14, 1, -14),
			Size = UDim2.new(1, -28, 0, 6),
			Parent = block,
		})
		UI.list(
			pips,
			Enum.FillDirection.Horizontal,
			4,
			if anchorX == 1 then Enum.HorizontalAlignment.Right else Enum.HorizontalAlignment.Left
		)
		return score, name, pips
	end
	scoreLeft, sideLeft, pipsLeft = side(1, -80)
	scoreRight, sideRight, pipsRight = side(0, 80)
end

local function buildCenter(parent: Instance)
	indicatorLayer = UI.frame({ BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = parent })
	crosshair = buildCrosshair(parent)
	buildHitmarker(parent)
	bannerTitle = UI.text({
		Text = "",
		FontFace = fonts.display,
		TextSize = 40,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.27),
		Size = UDim2.fromOffset(900, 50),
		TextTransparency = 1,
		Parent = overlay,
	})
	UI.textStroke(bannerTitle, 0.5)
	bannerLine = UI.frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.27, 30),
		Size = UDim2.fromOffset(0, 2),
		BackgroundTransparency = 1,
		Parent = overlay,
	})
	bannerSubtitle = UI.text({
		Text = "",
		FontFace = fonts.heading,
		TextSize = 18,
		TextColor3 = colors.textDim,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.27, 50),
		Size = UDim2.fromOffset(900, 24),
		TextTransparency = 1,
		Parent = overlay,
	})
	killConfirm = UI.text({
		Text = "",
		FontFace = fonts.heading,
		TextSize = 18,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 120),
		Size = UDim2.fromOffset(700, 24),
		TextTransparency = 1,
		Parent = parent,
	})
	UI.textStroke(killConfirm, 0.5)
	killPips = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 150),
		Size = UDim2.fromOffset(200, 18),
		Parent = parent,
	})
	UI.list(killPips, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center)
	interactionPanel = UI.panel({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, 70),
		Size = UDim2.fromOffset(360, 44),
		Visible = false,
		Parent = parent,
	})
	interactionText = UI.text({
		Text = "",
		FontFace = fonts.heading,
		TextSize = 16,
		Size = UDim2.new(1, 0, 0, 34),
		Parent = interactionPanel,
	})
	local track = UI.frame({
		BackgroundColor3 = colors.panelLight,
		Position = UDim2.new(0, 12, 1, -9),
		Size = UDim2.new(1, -24, 0, 4),
		Parent = interactionPanel,
	})
	interactionFill = UI.frame({ BackgroundColor3 = colors.warning, Size = UDim2.fromScale(0, 1), Parent = track })
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
		Position = UDim2.new(1, -24, 0, 24),
		Size = UDim2.fromOffset(460, 200),
		Parent = overlay,
	})
	UI.list(killfeed, Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Right)

	trainingPanel = UI.panel({
		Name = "Training",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 32, 0.45, 0),
		Size = UDim2.fromOffset(250, 176),
		Visible = false,
		Parent = parent,
	})
	UI.accent(trainingPanel, colors.success, 3)
	UI.text({
		Text = "TRAINING RANGE",
		FontFace = fonts.heading,
		TextSize = 15,
		TextColor3 = colors.success,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(16, 8),
		Size = UDim2.new(1, -24, 0, 20),
		Parent = trainingPanel,
	})
	trainingText = UI.text({
		Text = "",
		FontFace = fonts.mono,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(16, 34),
		Size = UDim2.new(1, -24, 1, -40),
		Parent = trainingPanel,
	})

	netStats = UI.text({
		Text = "",
		FontFace = fonts.mono,
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
	buildScope(root)
	buildVignette(root)
	buildFringes(root)
	buildCenter(root)
	buildHealth(root)
	buildAmmo(root)
	buildCompass(root)
	buildSide(root)
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
