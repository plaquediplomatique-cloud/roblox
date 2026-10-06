--!strict
--[[
	InputController — l'intention d'attaquer : clic maintenu, bouton tactile, gâchette de manette.

	Le client ne décide JAMAIS d'un résultat : il lance l'animation locale (réactivité immédiate),
	choisit le mannequin le plus proche comme indice et envoie `Swing`. Le serveur impose la cadence
	réelle, la portée et l'accès ; si le client triche, rien ne se passe.
	Maintenir = enchaîner à la cadence de l'arme (boucle Heartbeat active uniquement en maintien).
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage").Shared
local Net = require(Shared.Net.Net)
local Game = require(Shared.Config.Game)
local Store = require(script.Parent.Parent.Core.Store)
local Sfx = require(script.Parent.Parent.Core.Sfx)
local Hud = require(script.Parent.Hud)
local DummyView = require(script.Parent.DummyView)
local SwingAnimator = require(script.Parent.SwingAnimator)
local HitFeedback = require(script.Parent.HitFeedback)

local InputController = {}

local player = Players.LocalPlayer
local holding = false
local enabled = true
local lastSwing = 0
local sequence = 0
local loop: RBXScriptConnection? = nil

local function character(): (Model?, BasePart?, Humanoid?)
	local model = player.Character
	if not model then
		return nil, nil, nil
	end
	return model, model:FindFirstChild("HumanoidRootPart") :: BasePart?, model:FindFirstChildOfClass("Humanoid")
end

function InputController.swing()
	if not enabled or not Store.Ready then
		return
	end
	local now = os.clock()
	local interval = Store.swingInterval()
	if now - lastSwing < interval * 0.95 then
		return
	end
	local model, root, humanoid = character()
	if not model or not root or not humanoid or humanoid.Health <= 0 then
		return
	end
	lastSwing = now
	sequence += 1
	local weapon = Store.weapon()
	local target = DummyView.nearest(root.Position, weapon.Reach + Game.ReachPadding - 1, player.UserId)

	-- Se tourner (doucement) vers la cible : les coups « touchent » visuellement, aide au tactile.
	if target then
		local pivot = target:GetPivot().Position
		local flat = Vector3.new(pivot.X - root.Position.X, 0, pivot.Z - root.Position.Z)
		if flat.Magnitude > 0.5 then
			local look = CFrame.lookAt(root.Position, root.Position + flat)
			root.CFrame = root.CFrame:Lerp(look, 0.55)
		end
	end

	local duration = SwingAnimator.duration(interval)
	HitFeedback.registerSwing(duration)
	SwingAnimator.play(model, duration, nil)
	Sfx.play("Swing_" .. weapon.ArchetypeData.Sound, nil)

	local payload: { [string]: any } = { n = sequence % 1000000 }
	if target then
		payload.t = target:GetAttribute("DummyId")
	end
	Net.event("Swing"):FireServer(payload)
end

local function stopLoop()
	local connection = loop
	if connection then
		connection:Disconnect()
		loop = nil
	end
end

local function setHolding(value: boolean)
	holding = value and enabled
	if holding and not loop then
		loop = RunService.Heartbeat:Connect(function()
			if holding then
				InputController.swing()
			else
				stopLoop()
			end
		end)
	elseif not holding then
		stopLoop()
	end
end

-- Désactive les frappes (menu ouvert).
function InputController.setEnabled(value: boolean)
	enabled = value
	if not value then
		setHolding(false)
	end
end

function InputController.start()
	ContextActionService:BindAction("Attack", function(_name, state, _input)
		if state == Enum.UserInputState.Begin then
			setHolding(true)
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			setHolding(false)
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2, Enum.KeyCode.F)

	Hud.AttackHeld:Connect(setHolding)
end

return InputController
