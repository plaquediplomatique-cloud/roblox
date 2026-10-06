--!strict
--[[
	HitFeedback — le « jus » d'un coup. Reçoit les résultats AUTORITAIRES du serveur et les met en scène :
	nombre de dégâts, marqueur, particules de la rareté de l'arme, son qui monte avec le combo,
	secousse de caméra, réaction du mannequin, textes de critique / capacités.

	La mise en scène est calée sur l'instant du contact de l'animation locale (ImpactTime) : si
	la réponse du serveur arrive avant, on attend ; si elle arrive après, on joue tout de suite.
	Pools de nombres de dégâts (aucune création par coup).
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Net = require(Shared.Net.Net)
local Theme = require(Shared.Config.Theme)
local Combat = require(Shared.Rules.Combat)
local NumberFormat = require(Shared.Rules.NumberFormat)
local WeaponCatalog = require(Shared.Rules.WeaponCatalog)
local Store = require(script.Parent.Parent.Core.Store)
local Sfx = require(script.Parent.Parent.Core.Sfx)
local Vfx = require(script.Parent.Parent.Core.Vfx)
local CameraFeel = require(script.Parent.Parent.Core.CameraFeel)
local UI = require(script.Parent.Parent.UI.UI)
local Hud = require(script.Parent.Hud)
local DummyView = require(script.Parent.DummyView)
local SwingAnimator = require(script.Parent.SwingAnimator)

local HitFeedback = {}

local C = Theme.Color
local NUMBER_POOL = 18
local MILESTONES: { [number]: boolean } = { [10] = true, [25] = true, [50] = true, [75] = true, [100] = true }

type NumberSlot = { Anchor: Part, Gui: BillboardGui, Label: TextLabel, FreeAt: number, Gen: number }

local numbers: { NumberSlot } = {}
local impactAt = 0 -- instant (os.clock) du contact de la frappe locale en cours
local rng = Random.new()

---------------------------------------------------------------------------------------------
-- Nombres de dégâts (pool)
---------------------------------------------------------------------------------------------

local function buildNumber(parent: Folder): NumberSlot
	local anchor = Instance.new("Part")
	anchor.Name = "DamageAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.2
	anchor.CFrame = CFrame.new(0, -500, 0)
	anchor.Parent = parent
	local gui = UI.new("BillboardGui", {
		Adornee = anchor,
		Size = UDim2.fromOffset(240, 70),
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = 140,
		Enabled = false,
		Parent = anchor,
	})
	local label = UI.label({
		Font = Theme.Font.Display,
		TextSize = 34,
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.15,
		TextStrokeColor3 = Color3.new(0, 0, 0),
		Text = "",
		Parent = gui,
	})
	return { Anchor = anchor, Gui = gui, Label = label, FreeAt = 0, Gen = 0 }
end

local function acquireNumber(): NumberSlot
	local now = os.clock()
	local oldest = numbers[1]
	for _, slot in numbers do
		if slot.FreeAt <= now then
			return slot
		end
		if slot.FreeAt < oldest.FreeAt then
			oldest = slot
		end
	end
	return oldest
end

local function showNumber(position: Vector3, text: string, color: Color3, size: number, rise: number)
	local slot = acquireNumber()
	slot.Gen += 1
	local generation = slot.Gen
	slot.FreeAt = os.clock() + 0.85
	local start = position + Vector3.new(rng:NextNumber(-1.2, 1.2), rng:NextNumber(0, 1), rng:NextNumber(-1.2, 1.2))
	slot.Anchor.Position = start
	slot.Gui.Enabled = true
	local label = slot.Label
	label.Text = text
	label.TextColor3 = color
	label.TextSize = size
	label.TextTransparency = 0
	label.TextStrokeTransparency = 0.15
	label.Rotation = rng:NextNumber(-8, 8)
	UI.tween(slot.Anchor, { Position = start + Vector3.new(0, rise, 0) }, 0.8, Enum.EasingStyle.Quint)
	task.delay(0.45, function()
		if slot.Gen == generation then
			UI.tween(label, { TextTransparency = 1, TextStrokeTransparency = 1 }, 0.35)
		end
	end)
	task.delay(0.85, function()
		if slot.Gen == generation then
			slot.Gui.Enabled = false
		end
	end)
end

---------------------------------------------------------------------------------------------
-- Mise en scène d'un résultat
---------------------------------------------------------------------------------------------

local function show(result: { [string]: any })
	local settings = Store.settings()
	local weapon = Store.weapon()
	local fx = weapon.Rarity.Fx
	local position: Vector3 = result.p
	local crit: number = result.c
	local combo: number = result.cb
	local damage: number = result.d
	local rootPart = Players.LocalPlayer.Character
		and Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local comboTier = Combat.comboTier(combo)

	-- Particules (budget de la rareté) + anneau de choc sur critique.
	Vfx.impact(position, weapon.Rarity.Color, weapon.Rarity.Accent, fx.Emit, crit, true)
	if crit > 0 then
		Vfx.ring(position - Vector3.new(0, 1.5, 0), if crit == 2 then C.Mega else C.Crit, if crit == 2 then 22 else 14)
	end

	-- Sons : timbre de l'impact + hauteur qui monte avec le combo.
	local pitch = 1 + comboTier * 0.06
	Sfx.play(if crit == 2 then "Hit_Mega" elseif crit == 1 then "Hit_Crit" else "Hit_Normal", { Pitch = pitch })
	if combo > 1 then
		Sfx.play("Combo_Tick", { Pitch = 0.8 + math.min(combo, 60) * 0.025, Volume = 0.6 })
	end
	local milestone = MILESTONES[combo] == true
	if milestone then
		Sfx.play("Combo_Milestone", { Pitch = 0.9 + comboTier * 0.1 })
		CameraFeel.rumble(0.25)
	end

	-- Nombre de dégâts.
	if settings.DamageNumbers then
		local color = if crit == 2 then C.Mega elseif crit == 1 then C.Crit else Color3.new(1, 1, 1)
		local size = if crit == 2 then 54 elseif crit == 1 then 44 else 32
		local text = NumberFormat.compact(damage)
		if crit == 2 then
			text = "CRITICAL!! " .. text
		elseif crit == 1 then
			text = "CRITICAL! " .. text
		end
		showNumber(position + Vector3.new(0, 2, 0), text, color, size, if crit > 0 then 6 else 4)
		if result.sg then
			showNumber(position + Vector3.new(1.5, 4.5, 0), "SURGE!", weapon.Rarity.Color, 28, 5)
		end
		if result.ds then
			showNumber(position + Vector3.new(-1.5, 4.5, 0), "CLEAVE!", weapon.Rarity.Color, 28, 5)
		end
	end

	-- Marqueur à l'écran, secousse, réaction du mannequin.
	local camera = workspace.CurrentCamera
	local screen: Vector2? = nil
	if camera then
		local point, onScreen = camera:WorldToViewportPoint(position)
		if onScreen then
			screen = Vector2.new(point.X, point.Y)
		end
	end
	Hud.hitMarker(screen, crit)
	local strength = fx.Shake * (if crit == 2 then 1.7 elseif crit == 1 then 1.2 else 0.5)
	CameraFeel.impact(strength * 0.5)
	local model = DummyView.find(result.i)
	if model and rootPart then
		DummyView.react(model, rootPart.Position, (if crit > 0 then 1.4 else 0.7) + fx.Shake)
	end

	Hud.setCombo(combo, milestone)
	Hud.popXP(result.x)

	if result.k then
		Sfx.play("Dummy_Break")
		Vfx.burst(position, weapon.Rarity.Color, weapon.Rarity.Accent, 24)
		Vfx.ring(position - Vector3.new(0, 3, 0), weapon.Rarity.Accent, 18)
		CameraFeel.impact(0.5 + fx.Shake * 0.5)
		if result.co and result.co > 0 then
			Sfx.play("Coin")
			Hud.popCoins(result.co)
			showNumber(position + Vector3.new(0, 5, 0), "+" .. NumberFormat.compact(result.co) .. " $", C.Coins, 34, 6)
		end
	end
end

-- Appelé par InputController au début d'une frappe locale : fixe l'instant du contact.
function HitFeedback.registerSwing(duration: number)
	impactAt = os.clock() + duration * 0.42
end

local function onResult(result: { [string]: any })
	local delay = impactAt - os.clock()
	if delay > 0.005 and delay < 0.5 then
		task.delay(delay, show, result)
	else
		show(result)
	end
end

-- Frappes des AUTRES joueurs : animation + petit impact (budget réduit), sons 3D.
local function onRemoteSwing(payload: { [string]: any })
	local userId: number = payload.u
	local player = Players:GetPlayerByUserId(userId)
	local character = player and player.Character
	if not player or not character or player == Players.LocalPlayer then
		return
	end
	local position: Vector3? = payload.p
	local crit: number = payload.c or 0
	local weaponId = character:GetAttribute("Weapon")
	local weapon = if type(weaponId) == "string" then WeaponCatalog.ById[weaponId] else nil
	local root = character:FindFirstChild("HumanoidRootPart")
	SwingAnimator.play(character, 0.32, function()
		if position and weapon then
			Vfx.impact(
				position,
				weapon.Rarity.Color,
				weapon.Rarity.Accent,
				math.max(2, weapon.Rarity.Fx.Emit // 2),
				crit,
				false
			)
			Sfx.play(if crit > 0 then "Hit_Crit" else "Hit_Normal", { Parent = root, Volume = 0.6 })
		end
	end)
	if weapon then
		Sfx.play("Swing_" .. weapon.ArchetypeData.Sound, { Parent = root, Volume = 0.5 })
	end
end

function HitFeedback.start()
	local folder = Instance.new("Folder")
	folder.Name = "DamageNumbers"
	folder.Parent = workspace
	for _ = 1, NUMBER_POOL do
		table.insert(numbers, buildNumber(folder))
	end
	Net.event("HitResult").OnClientEvent:Connect(onResult)
	Net.unreliable("SwingFx").OnClientEvent:Connect(onRemoteSwing)
end

return HitFeedback
