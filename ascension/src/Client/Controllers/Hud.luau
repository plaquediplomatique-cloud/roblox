--!strict
--[[
	Hud — interface permanente : niveau, barre d'XP, puissance, pièces, combo, arme, objectif,
	boutons de menus, bouton d'attaque tactile, barre de boss.

	Lisibilité d'abord (skill roblox-game-ux) : chaque donnée a une place fixe, les nombres
	défilent, les barres se remplissent avec du rebond ; rien ne recouvre la zone de jeu centrale.
	Les barres/compteurs ne s'animent que sur changement (aucune boucle permanente, sauf le
	décompte du combo, actif uniquement tant qu'un combo existe).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage").Shared
local Signal = require(Shared.Util.Signal)
local Theme = require(Shared.Config.Theme)
local Progress = require(Shared.Rules.Progress)
local Curves = require(Shared.Rules.Curves)
local Combat = require(Shared.Rules.Combat)
local Daily = require(Shared.Rules.Daily)
local Game = require(Shared.Config.Game)
local WeaponCatalog = require(Shared.Rules.WeaponCatalog)
local QuestConfig = require(Shared.Config.Quests)
local Store = require(script.Parent.Parent.Core.Store)
local UI = require(script.Parent.Parent.UI.UI)

local Hud = {}

Hud.MenuRequested = Signal.new() :: Signal.Signal<string>
Hud.AttackHeld = Signal.new() :: Signal.Signal<boolean>
Hud.Gui = nil :: ScreenGui?

local C = Theme.Color
local refs: { [string]: any } = {}
local shownCoins = 0
local lastLevel = 0
local comboState: Combat.ComboState = { Count = 0, LastHit = 0 }
local comboConnection: RBXScriptConnection? = nil

local MENUS = {
	{ Id = "Weapons", Text = "WEAPONS" },
	{ Id = "Upgrades", Text = "UPGRADES" },
	{ Id = "Zones", Text = "ZONES" },
	{ Id = "Quests", Text = "QUESTS" },
	{ Id = "Base", Text = "BASE" },
	{ Id = "Shop", Text = "SHOP" },
	{ Id = "Ranks", Text = "RANKS" },
	{ Id = "Settings", Text = "···" },
}

---------------------------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------------------------

local function buildTopLeft(gui: ScreenGui)
	local card = UI.panel({
		Name = "PlayerCard",
		Position = UDim2.fromOffset(14, 10),
		Size = UDim2.fromOffset(360, 104),
		Parent = gui,
	})
	local badge = UI.new("Frame", {
		Name = "LevelBadge",
		BackgroundColor3 = C.Level,
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.fromOffset(76, 76),
		Parent = card,
	})
	UI.corner(UDim.new(1, 0)).Parent = badge
	UI.stroke(Color3.new(1, 1, 1), 3, 0.1).Parent = badge
	UI.new("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(255, 240, 150), C.Level),
		Rotation = 90,
		Parent = badge,
	})
	UI.label({
		Name = "Caption",
		Text = "LVL",
		Font = Theme.Font.Bold,
		TextSize = Theme.Size.Tiny,
		TextColor3 = C.Ink,
		Position = UDim2.fromOffset(0, 8),
		Size = UDim2.new(1, 0, 0, 14),
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = badge,
	})
	refs.Level = UI.label({
		Name = "Level",
		Text = "1",
		Font = Theme.Font.Display,
		TextSize = 38,
		TextColor3 = C.Ink,
		Position = UDim2.fromOffset(0, 20),
		Size = UDim2.new(1, 0, 0, 44),
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = badge,
	})
	refs.Stars = UI.label({
		Name = "Stars",
		Text = "",
		TextSize = 14,
		TextColor3 = C.Ink,
		Position = UDim2.new(0, 0, 1, -18),
		Size = UDim2.new(1, 0, 0, 14),
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = badge,
	})
	refs.Badge = badge

	refs.XpBar = UI.bar({
		Name = "XpBar",
		Position = UDim2.fromOffset(100, 14),
		Size = UDim2.fromOffset(246, 24),
		Color = C.Xp,
		Parent = card,
	})
	refs.XpText = UI.label({
		Name = "XpText",
		Text = "0 / 0 XP",
		TextSize = 14,
		Position = UDim2.fromOffset(100, 14),
		Size = UDim2.fromOffset(246, 24),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.4,
		ZIndex = 5,
		Parent = card,
	})
	refs.Power = UI.label({
		Name = "Power",
		Text = "POWER 0",
		TextSize = 20,
		TextColor3 = C.Power,
		Position = UDim2.fromOffset(100, 46),
		Size = UDim2.fromOffset(246, 24),
		Parent = card,
	})
	refs.Damage = UI.label({
		Name = "Damage",
		Text = "HIT 0",
		TextSize = 14,
		Font = Theme.Font.Body,
		TextColor3 = C.TextDim,
		Position = UDim2.fromOffset(100, 72),
		Size = UDim2.fromOffset(246, 20),
		Parent = card,
	})
end

local function buildCoins(gui: ScreenGui)
	local pill = UI.panel({
		Name = "Coins",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 10),
		Size = UDim2.fromOffset(210, 50),
		Parent = gui,
	})
	local icon = UI.new("Frame", {
		BackgroundColor3 = C.Coins,
		Position = UDim2.fromOffset(10, 9),
		Size = UDim2.fromOffset(32, 32),
		Parent = pill,
	})
	UI.corner(UDim.new(1, 0)).Parent = icon
	UI.stroke(Color3.fromRGB(255, 244, 170), 3, 0).Parent = icon
	UI.label({
		Text = "$",
		Font = Theme.Font.Display,
		TextSize = 22,
		TextColor3 = C.Ink,
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = icon,
	})
	refs.Coins = UI.label({
		Name = "CoinsText",
		Text = "0",
		Font = Theme.Font.Display,
		TextSize = 28,
		TextColor3 = C.Coins,
		Position = UDim2.fromOffset(52, 0),
		Size = UDim2.new(1, -60, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = pill,
	})
	refs.CoinsPill = pill

	local boost = UI.panel({
		Name = "Boost",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 66),
		Size = UDim2.fromOffset(210, 34),
		Visible = false,
		Parent = gui,
	})
	refs.Boost = UI.label({
		Text = "",
		TextSize = 16,
		TextColor3 = C.Xp,
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = boost,
	})
	refs.BoostPanel = boost

	refs.Goal = UI.label({
		Name = "Goal",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 108),
		Size = UDim2.fromOffset(300, 40),
		TextWrapped = true,
		TextSize = 14,
		Font = Theme.Font.Body,
		TextColor3 = C.TextDim,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = "",
		Parent = gui,
	})
end

local function buildCombo(gui: ScreenGui)
	local holder = UI.new("Frame", {
		Name = "Combo",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -130),
		Size = UDim2.fromOffset(300, 120),
		Visible = false,
		Parent = gui,
	})
	refs.ComboScale = UI.new("UIScale", { Parent = holder })
	refs.ComboCount = UI.label({
		Text = "x0",
		Font = Theme.Font.Display,
		TextSize = Theme.Size.Giant,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 72),
		TextStrokeTransparency = 0.2,
		Parent = holder,
	})
	UI.label({
		Text = "COMBO",
		TextSize = Theme.Size.Large,
		Position = UDim2.fromOffset(0, 68),
		Size = UDim2.new(1, 0, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.3,
		Parent = holder,
	})
	refs.ComboBar = UI.bar({
		Position = UDim2.new(0.2, 0, 0, 98),
		Size = UDim2.new(0.6, 0, 0, 8),
		Color = C.Combo,
		Parent = holder,
	})
	refs.ComboHolder = holder
end

local function buildWeaponCard(gui: ScreenGui)
	local card = UI.panel({
		Name = "WeaponCard",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 14, 1, -10),
		Size = UDim2.fromOffset(250, 84),
		Parent = gui,
	})
	refs.WeaponStripe = UI.new("Frame", {
		BackgroundColor3 = C.Accent,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 8, 1, -16),
		Position = UDim2.fromOffset(8, 8),
		Parent = card,
	})
	UI.corner(UDim.new(0, 4)).Parent = refs.WeaponStripe
	refs.WeaponName = UI.label({
		Text = "Wooden Stick",
		TextSize = 20,
		Position = UDim2.fromOffset(26, 8),
		Size = UDim2.new(1, -34, 0, 24),
		Parent = card,
	})
	refs.WeaponRarity = UI.label({
		Text = "Common",
		TextSize = 14,
		Position = UDim2.fromOffset(26, 32),
		Size = UDim2.new(1, -34, 0, 18),
		Parent = card,
	})
	refs.WeaponStats = UI.label({
		Text = "",
		TextSize = 14,
		Font = Theme.Font.Body,
		TextColor3 = C.TextDim,
		Position = UDim2.fromOffset(26, 52),
		Size = UDim2.new(1, -34, 0, 22),
		Parent = card,
	})
end

local function buildMenuBar(gui: ScreenGui)
	local bar = UI.new("Frame", {
		Name = "MenuBar",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.fromOffset(#MENUS * 88, 56),
		Parent = gui,
	})
	UI.list(Enum.FillDirection.Horizontal, 6).Parent = bar
	refs.MenuButtons = {}
	for i, menu in MENUS do
		local button = UI.button({
			Text = menu.Text,
			TextSize = if #menu.Text > 6 then 12 else 14,
			Size = UDim2.fromOffset(82, 50),
			Style = "ghost",
			LayoutOrder = i,
			Parent = bar,
		}, function()
			Hud.MenuRequested:Fire(menu.Id)
		end)
		refs.MenuButtons[menu.Id] = button.Instance
	end
	-- Pastille de notification sur QUESTS.
	local dot = UI.new("Frame", {
		Name = "Dot",
		BackgroundColor3 = C.Bad,
		Position = UDim2.new(1, -12, 0, -4),
		Size = UDim2.fromOffset(16, 16),
		Visible = false,
		ZIndex = 10,
		Parent = refs.MenuButtons.Quests,
	})
	UI.corner(UDim.new(1, 0)).Parent = dot
	UI.stroke(Color3.new(1, 1, 1), 2, 0).Parent = dot
	refs.QuestDot = dot
end

local function buildAttackButton(gui: ScreenGui)
	if not (UserInputService.TouchEnabled or UserInputService.GamepadEnabled) then
		return
	end
	local button = UI.new("TextButton", {
		Name = "AttackButton",
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -30, 1, -90),
		Size = UDim2.fromOffset(132, 132),
		BackgroundColor3 = C.Power,
		Text = "HIT",
		Font = Theme.Font.Display,
		TextSize = 34,
		TextColor3 = C.Text,
		Parent = gui,
	})
	UI.corner(UDim.new(1, 0)).Parent = button
	UI.stroke(Color3.new(1, 1, 1), 4, 0.2).Parent = button
	local scale = UI.new("UIScale", { Parent = button })
	button.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			UI.tween(scale, { Scale = 0.9 }, 0.06)
			Hud.AttackHeld:Fire(true)
		end
	end)
	button.InputEnded:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			UI.tween(scale, { Scale = 1 }, 0.1, Enum.EasingStyle.Back)
			Hud.AttackHeld:Fire(false)
		end
	end)
end

local function buildBossBar(gui: ScreenGui)
	local holder = UI.panel({
		Name = "BossBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(460, 60),
		Visible = false,
		Parent = gui,
	})
	refs.BossName = UI.label({
		Text = "BOSS",
		Font = Theme.Font.Display,
		TextSize = 22,
		TextColor3 = C.Bad,
		Position = UDim2.fromOffset(14, 4),
		Size = UDim2.new(1, -28, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = holder,
	})
	refs.BossBarFill = UI.bar({
		Position = UDim2.fromOffset(14, 34),
		Size = UDim2.new(1, -28, 0, 16),
		Color = C.Bad,
		Parent = holder,
	})
	refs.BossHolder = holder
end

---------------------------------------------------------------------------------------------
-- Rafraîchissements
---------------------------------------------------------------------------------------------

local function refreshLevel(animate: boolean)
	local data = Store.Data
	local level: number = data.Level or 1
	local xp: number = data.XP or 0
	refs.Level.Text = tostring(level)
	local stars: number = data.Stars or 0
	refs.Stars.Text = if stars > 0 then ("★ %d"):format(stars) else ""
	local fraction = Progress.fraction(level, xp)
	local bar = refs.XpBar
	if level >= Game.MaxLevel then
		refs.XpText.Text = "MAX LEVEL — ASCEND!"
	else
		refs.XpText.Text = ("%s / %s XP"):format(UI.format(math.floor(xp)), UI.format(Curves.xpToNext(level)))
	end
	if animate and lastLevel > 0 and level > lastLevel then
		-- Montée de niveau : la barre se remplit, puis repart de zéro.
		bar:Set(1)
		task.delay(0.4, function()
			bar:Set(0, false)
			bar:Set(fraction)
		end)
		UI.tween(refs.Badge, { Size = UDim2.fromOffset(92, 92), Position = UDim2.fromOffset(4, 4) }, 0.15)
		task.delay(0.16, function()
			UI.tween(
				refs.Badge,
				{ Size = UDim2.fromOffset(76, 76), Position = UDim2.fromOffset(12, 12) },
				0.3,
				Enum.EasingStyle.Back
			)
		end)
	else
		bar:Set(fraction, animate)
	end
	lastLevel = level
end

local function refreshCoins()
	local coins: number = Store.Data.Coins or 0
	if coins ~= shownCoins then
		UI.countTo(refs.Coins, shownCoins, coins, UI.format, 0.45)
		if coins > shownCoins then
			UI.tween(refs.CoinsPill, { Size = UDim2.fromOffset(222, 54) }, 0.08)
			task.delay(0.09, function()
				UI.tween(refs.CoinsPill, { Size = UDim2.fromOffset(210, 50) }, 0.25, Enum.EasingStyle.Back)
			end)
		end
		shownCoins = coins
	end
end

local function refreshStats()
	refs.Power.Text = "POWER " .. UI.format(Store.power())
	refs.Damage.Text = "HIT "
		.. UI.format(Store.damage())
		.. "   ·   "
		.. ("%.1f/s"):format(Combat.swingsPerSecond(Store.fighter()))
end

local function refreshWeapon()
	local weapon = Store.weapon()
	refs.WeaponName.Text = weapon.Name
	refs.WeaponRarity.Text = weapon.Rarity.Name
	refs.WeaponRarity.TextColor3 = weapon.Rarity.Color
	refs.WeaponStripe.BackgroundColor3 = weapon.Rarity.Color
	local special = if weapon.Special then "  ·  " .. weapon.Special.Name else ""
	refs.WeaponStats.Text = ("DMG %s%s"):format(UI.format(weapon.Damage), special)
end

local function refreshGoal()
	local data = Store.Data
	local level: number = data.Level or 1
	local nextWeapon = WeaponCatalog.nextMain(data.Weapons or {})
	if level >= Game.AscensionMinLevel then
		refs.Goal.Text = if level >= Game.MaxLevel
			then "Max level! Open WEAPONS → Ascend for permanent bonuses."
			else "Ascension available at this level!"
	elseif nextWeapon and nextWeapon.Level then
		refs.Goal.Text = ("Next weapon: %s  (Level %d)"):format(nextWeapon.Name, nextWeapon.Level)
	else
		refs.Goal.Text = ""
	end
end

local function refreshBoost()
	local expires: number = (Store.Data.Boosts and Store.Data.Boosts.XP) or 0
	local remaining = expires - workspace:GetServerTimeNow()
	refs.BoostPanel.Visible = remaining > 0
	if remaining > 0 then
		refs.Boost.Text = ("XP BOOST  %d:%02d"):format(remaining // 60, remaining % 60)
	end
end

local function refreshQuestDot()
	local data = Store.Data
	if not data.Daily then
		return
	end
	local now = workspace:GetServerTimeNow()
	local show = Daily.status(data.Daily, now).CanClaim
	if not show and data.Quests then
		for _, item in data.Quests.Items or {} do
			local def = QuestConfig.ById[item.Id]
			if def and not item.Claimed and item.Progress >= def.Target then
				show = true
			end
		end
	end
	if not show and data.Achievements then
		for _, state in data.Achievements do
			if state == 1 then
				show = true
			end
		end
	end
	refs.QuestDot.Visible = show
end

---------------------------------------------------------------------------------------------
-- Combo
---------------------------------------------------------------------------------------------

local function comboColor(count: number): Color3
	local color = Theme.ComboTiers[1].Color
	for _, tier in Theme.ComboTiers do
		if count >= tier.At then
			color = tier.Color
		end
	end
	return color
end

local function stopComboLoop()
	local connection = comboConnection
	if connection then
		connection:Disconnect()
		comboConnection = nil
	end
end

local function comboStep()
	local window = Combat.comboWindow(Store.fighter().Special)
	local now = os.clock()
	local current = Combat.comboAt(comboState, now, window)
	local idle = now - comboState.LastHit
	refs.ComboBar:Set(if idle <= window then 1 - idle / window else 0, false)
	if current <= 0 then
		refs.ComboHolder.Visible = false
		comboState.Count = 0
		stopComboLoop()
		return
	end
	if current ~= tonumber(string.match(refs.ComboCount.Text, "%d+")) then
		refs.ComboCount.Text = "x" .. current
		refs.ComboCount.TextColor3 = comboColor(current)
	end
end

-- Appelé par HitFeedback à chaque coup confirmé (combo = valeur serveur).
function Hud.setCombo(count: number, milestone: boolean)
	comboState.Count = count
	comboState.LastHit = os.clock()
	refs.ComboHolder.Visible = true
	refs.ComboCount.Text = "x" .. count
	local color = comboColor(count)
	refs.ComboCount.TextColor3 = color
	refs.ComboBar:SetColor(color)
	local scale: UIScale = refs.ComboScale
	scale.Scale = if milestone then 1.5 else 1.22
	UI.tween(scale, { Scale = 1 }, 0.25, Enum.EasingStyle.Back)
	if not comboConnection then
		local accumulated = 0
		comboConnection = RunService.Heartbeat:Connect(function(dt)
			accumulated += dt
			if accumulated >= 0.1 then
				accumulated = 0
				comboStep()
			end
		end)
	end
end

---------------------------------------------------------------------------------------------
-- Boss
---------------------------------------------------------------------------------------------

local bossModel: Model? = nil
local bossConnections: { RBXScriptConnection } = {}

local function refreshBoss()
	local model = bossModel
	if not model or not model.Parent then
		refs.BossHolder.Visible = false
		return
	end
	local hp = model:GetAttribute("HP")
	local maxHP = model:GetAttribute("MaxHP")
	local alive = model:GetAttribute("Alive")
	if type(hp) ~= "number" or type(maxHP) ~= "number" or maxHP <= 0 or alive == false then
		refs.BossHolder.Visible = false
		return
	end
	refs.BossHolder.Visible = true
	refs.BossName.Text = model.Name:upper()
	refs.BossBarFill:Set(hp / maxHP)
end

function Hud.setBoss(model: Model?)
	for _, connection in bossConnections do
		connection:Disconnect()
	end
	table.clear(bossConnections)
	bossModel = model
	if model then
		table.insert(bossConnections, model:GetAttributeChangedSignal("HP"):Connect(refreshBoss))
		table.insert(bossConnections, model:GetAttributeChangedSignal("Alive"):Connect(refreshBoss))
	end
	refreshBoss()
end

---------------------------------------------------------------------------------------------
-- Petits retours (XP / pièces flottants, marqueur de coup)
---------------------------------------------------------------------------------------------

local function floatText(text: string, color: Color3, anchor: UDim2, rise: number)
	local gui = Hud.Gui
	if not gui then
		return
	end
	local label = UI.label({
		Text = text,
		Font = Theme.Font.Display,
		TextSize = 22,
		TextColor3 = color,
		TextStrokeTransparency = 0.3,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = anchor,
		Size = UDim2.fromOffset(200, 30),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 20,
		Parent = gui,
	})
	UI.tween(
		label,
		{ Position = anchor + UDim2.fromOffset(0, -rise), TextTransparency = 1, TextStrokeTransparency = 1 },
		0.9,
		Enum.EasingStyle.Quad
	)
	task.delay(1, function()
		label:Destroy()
	end)
end

function Hud.popXP(amount: number)
	if amount >= 1 then
		floatText("+" .. UI.format(math.floor(amount)) .. " XP", C.Xp, UDim2.fromOffset(240, 128), 18)
	end
end

function Hud.popCoins(amount: number)
	if amount >= 1 then
		floatText("+" .. UI.format(amount), C.Coins, UDim2.new(1, -120, 0, 76), 16)
	end
end

local marker: Frame? = nil

-- Marqueur de coup au point de l'écran où le mannequin a été touché.
function Hud.hitMarker(screenPosition: Vector2?, crit: number)
	local gui = Hud.Gui
	if not gui then
		return
	end
	local frame = marker
	if not frame then
		frame = UI.new("Frame", {
			Name = "HitMarker",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(40, 40),
			Visible = false,
			ZIndex = 30,
			Parent = gui,
		})
		for _, rotation in { 45, -45 } do
			UI.new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.new(1, 0, 0, 5),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BorderSizePixel = 0,
				Rotation = rotation,
				ZIndex = 30,
				Parent = frame,
			})
		end
		marker = frame
	end
	local m = frame :: Frame
	local viewport = (workspace.CurrentCamera :: Camera).ViewportSize
	local position = screenPosition or (viewport / 2)
	m.Position = UDim2.fromOffset(position.X, position.Y)
	m.Size = UDim2.fromOffset(if crit > 0 then 56 else 40, if crit > 0 then 56 else 40)
	for _, bar in m:GetChildren() do
		if bar:IsA("Frame") then
			bar.BackgroundColor3 = if crit == 2 then C.Mega elseif crit == 1 then C.Crit else Color3.new(1, 1, 1)
		end
	end
	m.Visible = true
	UI.tween(m, { Size = UDim2.fromOffset(if crit > 0 then 36 else 26, if crit > 0 then 36 else 26) }, 0.12)
	task.delay(0.14, function()
		if m.Size.X.Offset <= 40 then
			m.Visible = false
		end
	end)
end

---------------------------------------------------------------------------------------------
-- Démarrage
---------------------------------------------------------------------------------------------

function Hud.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = UI.screen("Hud", playerGui, 2)
	Hud.Gui = gui
	buildTopLeft(gui)
	buildCoins(gui)
	buildCombo(gui)
	buildWeaponCard(gui)
	buildMenuBar(gui)
	buildAttackButton(gui)
	buildBossBar(gui)

	Store.waitReady()
	shownCoins = Store.Data.Coins or 0
	refs.Coins.Text = UI.format(shownCoins)
	refreshLevel(false)
	refreshStats()
	refreshWeapon()
	refreshGoal()
	refreshBoost()
	refreshQuestDot()

	Store.Changed:Connect(function(key)
		if key == "Level" or key == "XP" or key == "Stars" then
			refreshLevel(true)
			refreshGoal()
			refreshStats()
		elseif key == "Coins" then
			refreshCoins()
		elseif key == "Equipped" then
			refreshWeapon()
			refreshStats()
		elseif key == "Upgrades" then
			refreshStats()
		elseif key == "Weapons" then
			refreshGoal()
		elseif key == "Boosts" then
			refreshBoost()
		end
		if key == "Daily" or key == "Quests" or key == "Achievements" then
			refreshQuestDot()
		end
	end)

	-- Un tick par seconde : boost XP, pastille de quêtes (la quotidienne se libère avec le temps).
	task.spawn(function()
		while gui.Parent do
			task.wait(1)
			refreshBoost()
			refreshQuestDot()
		end
	end)
end

return Hud
