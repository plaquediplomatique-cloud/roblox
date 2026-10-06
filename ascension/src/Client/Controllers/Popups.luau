--!strict
--[[
	Popups — les grands moments : LEVEL UP, NEW WEAPON, coffres, notifications.

	Chaque moment superpose plusieurs retours (cf. skill roblox-animation-audio-feedback) :
	popup animé, confettis, flash de lumière, son, secousse de caméra, nombre qui monte,
	récompense affichée. Les popups sont mis en file : jamais deux à la fois.
	Les notifications (toasts) s'empilent, durent 3,5 s et sont plafonnées à 4.
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Net = require(Shared.Net.Net)
local Theme = require(Shared.Config.Theme)
local WeaponCatalog = require(Shared.Rules.WeaponCatalog)
local Loot = require(Shared.Config.Loot)
local Sfx = require(script.Parent.Parent.Core.Sfx)
local Vfx = require(script.Parent.Parent.Core.Vfx)
local CameraFeel = require(script.Parent.Parent.Core.CameraFeel)
local UI = require(script.Parent.Parent.UI.UI)
local WeaponView = require(script.Parent.Parent.UI.WeaponView)
local Confetti = require(script.Parent.Parent.UI.Confetti)

local Popups = {}

local C = Theme.Color
local gui: ScreenGui
local queue: { () -> number } = {} -- chaque entrée affiche un popup et renvoie sa durée
local busy = false
local toasts: { Frame } = {}
local MAX_TOASTS = 4

---------------------------------------------------------------------------------------------
-- File d'attente
---------------------------------------------------------------------------------------------

local function pump()
	if busy then
		return
	end
	local nextShow = table.remove(queue, 1)
	if not nextShow then
		return
	end
	busy = true
	local duration = nextShow()
	task.delay(duration, function()
		busy = false
		pump()
	end)
end

local function enqueue(show: () -> number)
	table.insert(queue, show)
	pump()
end

local function flash(color: Color3, strength: number)
	local frame = UI.new("Frame", {
		BackgroundColor3 = color,
		BackgroundTransparency = 1 - strength,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 40,
		Parent = gui,
	})
	UI.tween(frame, { BackgroundTransparency = 1 }, 0.5).Completed:Connect(function()
		frame:Destroy()
	end)
end

local function character(): BasePart?
	local model = Players.LocalPlayer.Character
	return model and model:FindFirstChild("HumanoidRootPart") :: BasePart?
end

---------------------------------------------------------------------------------------------
-- Notifications
---------------------------------------------------------------------------------------------

local KIND_COLOR: { [string]: Color3 } = {
	Reward = C.Coins,
	Weapon = C.Accent,
	Zone = C.Good,
	Boss = C.Bad,
	Error = C.Bad,
	Info = C.Xp,
	Rare = C.Mega,
	Quest = C.Xp,
	Achievement = C.Level,
}

local function relayout()
	for i, toast in toasts do
		UI.tween(toast, { Position = UDim2.new(0.5, 0, 0, 112 + (i - 1) * 72) }, 0.2)
	end
end

function Popups.toast(kind: string, text: string, lines: { string }?)
	local color = KIND_COLOR[kind] or C.Accent
	local height = 56 + (if lines then #lines * 16 else 0)
	local toast = UI.panel({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 40),
		Size = UDim2.fromOffset(380, height),
		BackgroundTransparency = 0.05,
		Parent = gui,
	})
	local stripe = UI.new("Frame", {
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 8, 1, -14),
		Position = UDim2.fromOffset(8, 7),
		Parent = toast,
	})
	UI.corner(UDim.new(0, 4)).Parent = stripe
	UI.label({
		Text = text,
		TextSize = 20,
		Position = UDim2.fromOffset(26, 6),
		Size = UDim2.new(1, -36, 0, 28),
		Parent = toast,
	})
	local extra: { string } = lines or {}
	for i, line in extra do
		UI.label({
			Text = line,
			TextSize = 15,
			Font = Theme.Font.Body,
			TextColor3 = color,
			Position = UDim2.fromOffset(26, 30 + (i - 1) * 16),
			Size = UDim2.new(1, -36, 0, 16),
			Parent = toast,
		})
	end
	table.insert(toasts, 1, toast)
	while #toasts > MAX_TOASTS do
		local old = table.remove(toasts) :: Frame
		old:Destroy()
	end
	relayout()
	UI.pop(toast, 0.85)
	task.delay(3.5, function()
		local index = table.find(toasts, toast)
		if index then
			table.remove(toasts, index)
		end
		UI.tween(toast, { Position = toast.Position + UDim2.fromOffset(0, -30), BackgroundTransparency = 1 }, 0.25)
		task.delay(0.26, function()
			toast:Destroy()
			relayout()
		end)
	end)
end

---------------------------------------------------------------------------------------------
-- LEVEL UP
---------------------------------------------------------------------------------------------

local pendingLevel: { From: number, To: number, Power: number }? = nil

local function showLevelUp(from: number, to: number, power: number): number
	local panel = UI.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 150),
		Size = UDim2.fromOffset(560, 190),
		ZIndex = 50,
		Parent = gui,
	})
	local title = UI.label({
		Text = "LEVEL UP!",
		Font = Theme.Font.Display,
		TextSize = 72,
		TextColor3 = C.Level,
		TextStrokeTransparency = 0,
		TextStrokeColor3 = Color3.fromRGB(120, 60, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 84),
		ZIndex = 51,
		Parent = panel,
	})
	local levels = UI.label({
		Text = ("LEVEL %d → LEVEL %d"):format(from, from),
		Font = Theme.Font.Display,
		TextSize = 34,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 88),
		Size = UDim2.new(1, 0, 0, 40),
		TextStrokeTransparency = 0.3,
		ZIndex = 51,
		Parent = panel,
	})
	local powerLabel = UI.label({
		Text = "",
		TextSize = 28,
		TextColor3 = C.Power,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 134),
		Size = UDim2.new(1, 0, 0, 32),
		TextStrokeTransparency = 0.3,
		ZIndex = 51,
		Parent = panel,
	})
	UI.pop(panel, 0.4)
	Sfx.play("Level_Up")
	flash(Color3.fromRGB(255, 244, 190), 0.35)
	CameraFeel.rumble(0.7)
	Confetti.burst(gui, UDim2.new(0.5, 0, 0, 200), { C.Level, C.Xp, C.Good, C.Mega, Color3.new(1, 1, 1) }, 28)
	local root = character()
	if root then
		Vfx.burst(root.Position, C.Level, Color3.new(1, 1, 1), 40)
		Vfx.ring(root.Position - Vector3.new(0, 2.5, 0), C.Level, 26)
	end
	-- Le niveau « compte » de l'ancien au nouveau, la puissance aussi.
	UI.countTo(levels, from, to, function(value)
		return ("LEVEL %d → LEVEL %d"):format(from, math.floor(value))
	end, 0.6)
	if power > 0 then
		task.delay(0.5, function()
			UI.countTo(powerLabel, 0, power, function(value)
				return "+" .. UI.format(math.floor(value)) .. " POWER"
			end, 0.7)
			Sfx.play("Coin", { Pitch = 1.2 })
		end)
	end
	task.delay(2.4, function()
		UI.tween(title, { TextTransparency = 1, TextStrokeTransparency = 1 }, 0.4)
		UI.tween(levels, { TextTransparency = 1, TextStrokeTransparency = 1 }, 0.4)
		UI.tween(powerLabel, { TextTransparency = 1, TextStrokeTransparency = 1 }, 0.4)
		task.delay(0.45, function()
			panel:Destroy()
		end)
	end)
	return 2.8
end

function Popups.levelUp(from: number, to: number, power: number)
	-- Plusieurs niveaux en rafale : un seul popup « from → to ».
	local pending = pendingLevel
	if pending then
		pending.To = to
		pending.Power += power
		return
	end
	pendingLevel = { From = from, To = to, Power = power }
	task.delay(0.25, function()
		local data = pendingLevel
		pendingLevel = nil
		if data then
			enqueue(function()
				return showLevelUp(data.From, data.To, data.Power)
			end)
		end
	end)
end

---------------------------------------------------------------------------------------------
-- NEW WEAPON
---------------------------------------------------------------------------------------------

local function showWeapon(weapon: WeaponCatalog.Weapon, headline: string): number
	local rarity = weapon.Rarity
	local card = UI.panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.46),
		Size = UDim2.fromOffset(420, 360),
		ZIndex = 50,
		Parent = gui,
	})
	local stroke = card:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = rarity.Color
		stroke.Thickness = 4
	end
	UI.label({
		Text = headline,
		Font = Theme.Font.Display,
		TextSize = 34,
		TextColor3 = rarity.Color,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 14),
		Size = UDim2.new(1, 0, 0, 40),
		ZIndex = 51,
		Parent = card,
	})
	local view = WeaponView.create(card, weapon, UDim2.fromOffset(300, 190))
	view.Position = UDim2.fromOffset(60, 56)
	view.ZIndex = 51
	UI.label({
		Text = weapon.Name,
		Font = Theme.Font.Display,
		TextSize = 30,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 252),
		Size = UDim2.new(1, 0, 0, 36),
		ZIndex = 51,
		Parent = card,
	})
	UI.label({
		Text = rarity.Name:upper(),
		TextSize = 20,
		TextColor3 = rarity.Color,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 288),
		Size = UDim2.new(1, 0, 0, 24),
		ZIndex = 51,
		Parent = card,
	})
	local special = if weapon.Special then "  ·  " .. weapon.Special.Name else ""
	UI.label({
		Text = ("DMG %s  ·  x%.2f XP%s"):format(UI.format(weapon.Damage), weapon.XPBoost, special),
		TextSize = 16,
		Font = Theme.Font.Body,
		TextColor3 = C.TextDim,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 316),
		Size = UDim2.new(1, 0, 0, 24),
		ZIndex = 51,
		Parent = card,
	})
	UI.pop(card, 0.3)
	Sfx.play("Weapon_Unlock", { Pitch = 0.9 + rarity.Order * 0.03 })
	flash(rarity.Color, 0.28 + rarity.Order * 0.02)
	CameraFeel.rumble(0.3 + rarity.Order * 0.05)
	Confetti.burst(
		gui,
		UDim2.fromScale(0.5, 0.4),
		{ rarity.Color, rarity.Accent, Color3.new(1, 1, 1) },
		14 + rarity.Order * 2
	)
	if rarity.Order >= 7 then
		Sfx.play("Rare_Event")
	end
	local duration = if rarity.Order >= 5 then 3.6 else 2.8
	task.delay(duration, function()
		UI.tween(card, { Position = UDim2.fromScale(0.5, 0.5), BackgroundTransparency = 1 }, 0.3)
		task.delay(0.3, function()
			card:Destroy()
		end)
	end)
	return duration + 0.2
end

function Popups.weapon(weaponId: string, source: string)
	local weapon = WeaponCatalog.ById[weaponId]
	if not weapon then
		return
	end
	local headline = if source == "Level" then "NEW WEAPON UNLOCKED!" else (weapon.Rarity.Name:upper() .. " FOUND!")
	enqueue(function()
		return showWeapon(weapon, headline)
	end)
end

---------------------------------------------------------------------------------------------
-- Coffre
---------------------------------------------------------------------------------------------

function Popups.chest(payload: { [string]: any })
	local chest = Loot.ById[payload.id]
	if not chest then
		return
	end
	enqueue(function()
		Sfx.play("Chest_Open")
		if payload.kind == "Weapon" then
			local weapon = WeaponCatalog.ById[payload.weapon]
			if weapon then
				task.delay(0.9, function()
					Sfx.play("Rare_Event", { Volume = 0.6 })
				end)
				return showWeapon(weapon, chest.Name:upper() .. " REWARD!") + 0.3
			end
		end
		Popups.toast("Reward", chest.Name, { payload.text or "Coins" })
		flash(chest.Color, 0.2)
		return 1.2
	end)
end

---------------------------------------------------------------------------------------------
-- Démarrage
---------------------------------------------------------------------------------------------

function Popups.start()
	gui = UI.screen("Popups", Players.LocalPlayer:WaitForChild("PlayerGui"), 10)

	Net.event("LevelUp").OnClientEvent:Connect(function(payload: { From: number, To: number, PowerGain: number })
		Popups.levelUp(payload.From, payload.To, payload.PowerGain)
	end)
	Net.event("WeaponUnlocked").OnClientEvent:Connect(function(payload: { id: string, s: string })
		Popups.weapon(payload.id, payload.s)
	end)
	Net.event("ChestResult").OnClientEvent:Connect(Popups.chest)
	Net.event("Notify").OnClientEvent:Connect(function(payload: { k: string, t: string, l: { string }? })
		Popups.toast(payload.k, payload.t, payload.l)
		if payload.k == "Error" then
			Sfx.play("UI_Error")
		elseif payload.k == "Zone" then
			Sfx.play("Zone_Unlock")
		elseif payload.k == "Boss" then
			Sfx.play("Boss_Spawn", { Volume = 0.7 })
			CameraFeel.rumble(0.4)
		elseif payload.k == "Rare" then
			Sfx.play("Rare_Event")
		elseif payload.k == "Reward" or payload.k == "Quest" or payload.k == "Achievement" then
			Sfx.play("Reward")
		end
	end)
end

return Popups
