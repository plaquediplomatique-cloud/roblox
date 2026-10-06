--!strict
--[[
	CameraFeel — secousses et « coup de FOV » sur les gros impacts (jeu à la 3e personne).

	La caméra Roblox par défaut reste maîtresse : on n'agit que sur Humanoid.CameraOffset
	(décalage local, aucun conflit avec les scripts de caméra) et sur FieldOfView. Ressorts
	amortis ; la boucle RenderStepped n'existe QUE tant que de l'énergie reste à dissiper.
]]

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Spring = require(Shared.Util.Spring)
local Store = require(script.Parent.Store)

local CameraFeel = {}

local BASE_FOV = 70
local offset = Spring.vector(Vector3.zero, 22, 0.45)
local fov = Spring.number(0, 14, 0.6)
local connection: RBXScriptConnection? = nil
local rng = Random.new()

local function humanoid(): Humanoid?
	local character = Players.LocalPlayer.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function stopIfIdle()
	if
		offset.position.Magnitude < 0.002
		and offset.velocity.Magnitude < 0.01
		and math.abs(fov.position) < 0.02
		and math.abs(fov.velocity) < 0.05
	then
		local c = connection
		if c then
			c:Disconnect()
			connection = nil
		end
		local hum = humanoid()
		if hum then
			hum.CameraOffset = Vector3.zero
		end
		local camera = workspace.CurrentCamera
		if camera then
			camera.FieldOfView = BASE_FOV
		end
	end
end

local function ensureLoop()
	if connection then
		return
	end
	connection = RunService.RenderStepped:Connect(function(dt)
		local hum = humanoid()
		if hum then
			hum.CameraOffset = offset:step(dt)
		end
		local camera = workspace.CurrentCamera
		if camera then
			camera.FieldOfView = BASE_FOV + fov:step(dt)
		end
		stopIfIdle()
	end)
end

-- strength : 0..1 (0.1 = coup léger, 1 = coup colossal).
function CameraFeel.impact(strength: number, direction: Vector3?)
	if not Store.settings().Shake then
		return
	end
	local s = math.clamp(strength, 0, 1.5)
	local dir = direction or Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.4, 1), 0)
	offset:impulse(dir * s * 14)
	fov:impulse(s * 22)
	ensureLoop()
end

-- Petite secousse (apparition d'un boss, montée de niveau).
function CameraFeel.rumble(strength: number)
	if not Store.settings().Shake then
		return
	end
	offset:impulse(Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), 0) * strength * 18)
	ensureLoop()
end

function CameraFeel.baseFov(): number
	return BASE_FOV
end

return CameraFeel
