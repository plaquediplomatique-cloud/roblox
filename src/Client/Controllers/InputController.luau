--!strict
--[[
	InputController — actions de jeu abstraites (rebindables), clavier/souris, manette,
	tactile (via MobileController).

	Le gameplay ne lit JAMAIS une touche : il écoute des ACTIONS ("Fire", "Aim",
	"Crouch"…). Les raccourcis viennent des réglages (rebinding sans redémarrage).
	Quand un menu est ouvert, les actions de gameplay sont suspendues et relâchées
	(pas de tir fantôme en fermant un menu bouton enfoncé).
]]

local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Signal = require(Shared.Util.Signal)
local ClientState = require(script.Parent.Parent.Core.ClientState)
local SettingsController = require(script.Parent.SettingsController)

local InputController = {
	ActionBegan = Signal.new() :: Signal.Signal<string>,
	ActionEnded = Signal.new() :: Signal.Signal<string>,
	Scrolled = Signal.new() :: Signal.Signal<number>,
}

local ALWAYS_ACTIVE: { [string]: boolean } = { Menu = true, Scoreboard = true }

local GAMEPAD: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.ButtonR2] = "Fire",
	[Enum.KeyCode.ButtonL2] = "Aim",
	[Enum.KeyCode.ButtonX] = "Reload",
	[Enum.KeyCode.ButtonA] = "Jump",
	[Enum.KeyCode.ButtonB] = "Crouch",
	[Enum.KeyCode.ButtonL3] = "Walk",
	[Enum.KeyCode.ButtonY] = "Primary",
	[Enum.KeyCode.ButtonR3] = "Melee",
	[Enum.KeyCode.DPadLeft] = "LeanLeft",
	[Enum.KeyCode.DPadRight] = "LeanRight",
	[Enum.KeyCode.DPadUp] = "Inspect",
	[Enum.KeyCode.DPadDown] = "Interact",
	[Enum.KeyCode.ButtonSelect] = "Scoreboard",
	[Enum.KeyCode.ButtonStart] = "Menu",
}

local keyToAction: { [string]: string } = {}
local down: { [string]: boolean } = {}
local virtualMove = Vector2.zero
local virtualLook = Vector2.zero
local gamepadMove = Vector2.zero
local gamepadLook = Vector2.zero

local function rebuild()
	table.clear(keyToAction)
	for action, key in SettingsController.get().Keybinds do
		keyToAction[key] = action
	end
end

local function actionFor(input: InputObject): string?
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		return keyToAction.MouseButton1
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		return keyToAction.MouseButton2
	elseif input.UserInputType == Enum.UserInputType.MouseButton3 then
		return keyToAction.MouseButton3
	elseif input.UserInputType == Enum.UserInputType.Keyboard then
		return keyToAction[input.KeyCode.Name]
	elseif string.find(input.UserInputType.Name, "Gamepad") then
		return GAMEPAD[input.KeyCode]
	end
	return nil
end

local function press(action: string)
	if ClientState.menuOpen and not ALWAYS_ACTIVE[action] then
		return
	end
	if not down[action] then
		down[action] = true
		InputController.ActionBegan:Fire(action)
	end
end

local function release(action: string)
	if down[action] then
		down[action] = nil
		InputController.ActionEnded:Fire(action)
	end
end

function InputController.isDown(action: string): boolean
	return down[action] == true
end

--[[ Vecteur de déplacement local (x = droite, z = arrière ; avant = -Z). ]]
function InputController.moveVector(): Vector3
	if ClientState.menuOpen then
		return Vector3.zero
	end
	local x, z = 0, 0
	if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up) then
		z -= 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down) then
		z += 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then
		x -= 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then
		x += 1
	end
	local keyboard = Vector3.new(x, 0, z)
	local analog = Vector3.new(gamepadMove.X + virtualMove.X, 0, -(gamepadMove.Y + virtualMove.Y))
	local combined = keyboard + analog
	if combined.Magnitude > 1 then
		combined = combined.Unit
	end
	return combined
end

--[[ Delta de visée de la frame (pixels équivalents souris), consommé à la lecture. ]]
function InputController.consumeLook(dt: number): Vector2
	if ClientState.menuOpen then
		virtualLook = Vector2.zero
		return Vector2.zero
	end
	local mouse = UserInputService:GetMouseDelta()
	local stick = Vector2.new(gamepadLook.X, -gamepadLook.Y) * dt * 900
	local total = mouse + stick + virtualLook
	virtualLook = Vector2.zero
	return total
end

function InputController.setVirtual(action: string, isDown: boolean)
	if isDown then
		press(action)
	else
		release(action)
	end
end

function InputController.setVirtualMove(vector: Vector2)
	virtualMove = vector
end

function InputController.addVirtualLook(delta: Vector2)
	virtualLook += delta
end

function InputController.releaseAll()
	for action in down do
		release(action)
	end
end

function InputController.start()
	rebuild()
	SettingsController.Changed:Connect(rebuild)
	ClientState.MenuChanged:Connect(function(open: boolean)
		if open then
			for action in down do
				if not ALWAYS_ACTIVE[action] then
					release(action)
				end
			end
		end
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed and input.UserInputType == Enum.UserInputType.Keyboard then
			return
		end
		local action = actionFor(input)
		if action then
			press(action)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		local action = actionFor(input)
		if action then
			release(action)
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject, processed: boolean)
		if input.UserInputType == Enum.UserInputType.MouseWheel and not processed then
			InputController.Scrolled:Fire(input.Position.Z)
		elseif input.KeyCode == Enum.KeyCode.Thumbstick1 then
			local value = Vector2.new(input.Position.X, input.Position.Y)
			gamepadMove = if value.Magnitude > 0.15 then value else Vector2.zero
		elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
			local value = Vector2.new(input.Position.X, input.Position.Y)
			gamepadLook = if value.Magnitude > 0.12 then value * value.Magnitude else Vector2.zero
		end
	end)
	UserInputService.WindowFocusReleased:Connect(InputController.releaseAll)
end

return InputController
