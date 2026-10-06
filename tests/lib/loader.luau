--[[
	Chargeur de modules Roblox hors moteur (Lune).

	Monte des dossiers de src/ dans un arbre d'"instances" virtuel pour que les
	`require(script.Parent.X)` fonctionnent, fournit les datatypes Roblox de @lune/roblox
	et des shims (Random PCG32 déterministe, task, game:GetService minimal).
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

---------------------------------------------------------------------------------------------
-- Shims
---------------------------------------------------------------------------------------------

-- PCG32 (64 bits d'état émulés sur deux mots de 32 bits) : déterministe et reproductible.
local RandomShim = {}
RandomShim.__index = RandomShim

local function mul64(aHi, aLo, bHi, bLo)
	-- (aHi:aLo * bHi:bLo) mod 2^64, en morceaux de 16 bits pour rester exact en double.
	local a0, a1, a2, a3 = aLo % 65536, aLo // 65536, aHi % 65536, aHi // 65536
	local b0, b1, b2, b3 = bLo % 65536, bLo // 65536, bHi % 65536, bHi // 65536
	local r0 = a0 * b0
	local r1 = a1 * b0 + a0 * b1 + r0 // 65536
	local r2 = a2 * b0 + a1 * b1 + a0 * b2 + r1 // 65536
	local r3 = a3 * b0 + a2 * b1 + a1 * b2 + a0 * b3 + r2 // 65536
	local lo = (r0 % 65536) + (r1 % 65536) * 65536
	local hi = (r2 % 65536) + (r3 % 65536) * 65536
	return hi, lo
end

local function add64(aHi, aLo, bHi, bLo)
	local lo = aLo + bLo
	local carry = lo // 4294967296
	return (aHi + bHi + carry) % 4294967296, lo % 4294967296
end

function RandomShim.new(seed)
	local s = math.floor(seed or os.clock() * 1e6) % 4294967296
	local self = setmetatable({ hi = 0, lo = 0 }, RandomShim)
	self.hi, self.lo = add64(0, s, 0x853C49E6, 0x748FEA9B)
	self:_next()
	return self
end

function RandomShim:_next()
	local oldHi, oldLo = self.hi, self.lo
	local mHi, mLo = mul64(oldHi, oldLo, 0x5851F42D, 0x4C957F2D)
	self.hi, self.lo = add64(mHi, mLo, 0x14057B7E, 0xF767814F)
	-- xorshifted = ((old >> 18) ^ old) >> 27 ; rot = old >> 59
	local shiftedHi = bit32.rshift(oldHi, 18)
	local shiftedLo = bit32.bor(bit32.rshift(oldLo, 18), bit32.lshift(bit32.band(oldHi, 0x3FFFF), 14))
	local xHi, xLo = bit32.bxor(shiftedHi, oldHi), bit32.bxor(shiftedLo, oldLo)
	local xorshifted = bit32.bor(bit32.rshift(xLo, 27), bit32.lshift(bit32.band(xHi, 0x7FFFFFF), 5))
	local rot = bit32.rshift(oldHi, 27)
	return bit32.rrotate(xorshifted, rot)
end

function RandomShim:NextNumber(min, max)
	local value = self:_next() / 4294967296
	if min then
		return min + (max - min) * value
	end
	return value
end

function RandomShim:NextInteger(min, max)
	return min + (self:_next() % (max - min + 1))
end

local taskShim = {
	spawn = function(fn, ...)
		local thread = if type(fn) == "thread" then fn else coroutine.create(fn)
		coroutine.resume(thread, ...)
		return thread
	end,
	defer = function(fn, ...)
		local thread = coroutine.create(fn)
		coroutine.resume(thread, ...)
		return thread
	end,
	delay = function() end,
	wait = function()
		return 0
	end,
	cancel = function() end,
}

-- Lune 0.10 : CFrame.lookAt (et CFrame.new(pos, cible)) renvoient une rotation erronée
-- (axe Z inversé). Les modules chargés reçoivent un CFrame dont lookAt est reconstruit
-- par fromMatrix, conforme au moteur : rampes, murs en biais et caméras d'intro exacts.
local function lookAt(at, target, up)
	local look = (target - at).Unit
	local right = look:Cross(up or roblox.Vector3.yAxis)
	if right.Magnitude < 1e-6 then
		right = look:Cross(roblox.Vector3.zAxis)
	end
	right = right.Unit
	return roblox.CFrame.fromMatrix(at, right, right:Cross(look), -look)
end

local CFrameShim = setmetatable({ lookAt = lookAt }, { __index = roblox.CFrame })

local fakeSignal = {
	Connect = function()
		return { Disconnect = function() end, Connected = true }
	end,
}

local services = {
	RunService = {
		IsStudio = function()
			return false
		end,
		IsServer = function()
			return true
		end,
		IsClient = function()
			return false
		end,
		Heartbeat = fakeSignal,
	},
}

---------------------------------------------------------------------------------------------
-- Arbre d'instances virtuel
---------------------------------------------------------------------------------------------

local NodeMethods = {}

local function newNode(name, parent, path)
	local node = { Name = name, Parent = parent, _children = {}, _path = path }
	return setmetatable(node, {
		__index = function(self, key)
			local method = NodeMethods[key]
			if method then
				return method
			end
			local child = rawget(self, "_children")[key]
			if child == nil then
				error(("%s is not a valid member of %s"):format(tostring(key), rawget(self, "Name")), 2)
			end
			return child
		end,
		__tostring = function(self)
			return rawget(self, "Name")
		end,
	})
end

function NodeMethods.FindFirstChild(self, name)
	return rawget(self, "_children")[name]
end

function NodeMethods.WaitForChild(self, name)
	return rawget(self, "_children")[name]
end

local function mount(directory, node)
	for _, entry in fs.readDir(directory) do
		local full = directory .. "/" .. entry
		if fs.isDir(full) then
			local child = newNode(entry, node, nil)
			rawget(node, "_children")[entry] = child
			mount(full, child)
		elseif string.sub(entry, -5) == ".luau" and not string.find(entry, "%.spec%.luau$") then
			local name = string.gsub(entry, "%.luau$", "")
			if name == "init" then
				rawset(node, "_path", full)
			else
				rawget(node, "_children")[name] = newNode(name, node, full)
			end
		end
	end
end

local replicatedStorage = newNode("ReplicatedStorage", nil, nil)
local shared = newNode("Shared", replicatedStorage, nil)
rawget(replicatedStorage, "_children").Shared = shared
mount("src/Shared", shared)

local serverScriptService = newNode("ServerScriptService", nil, nil)
local server = newNode("Server", serverScriptService, nil)
rawget(serverScriptService, "_children").Server = server
local maps = newNode("Maps", server, nil)
rawget(server, "_children").Maps = maps
mount("src/Server/Maps", maps)

services.ReplicatedStorage = replicatedStorage
services.ServerScriptService = serverScriptService

local game = {
	GetService = function(_, name)
		local service = services[name]
		if not service then
			error("service not available in tests: " .. tostring(name))
		end
		return service
	end,
}

---------------------------------------------------------------------------------------------
-- Chargeur de modules
---------------------------------------------------------------------------------------------

local loaded = {}
local requireNode

local function environmentFor(node)
	return {
		script = node,
		require = requireNode,
		game = game,
		Vector3 = roblox.Vector3,
		Vector2 = roblox.Vector2,
		CFrame = CFrameShim,
		Color3 = roblox.Color3,
		NumberRange = roblox.NumberRange,
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
		Enum = roblox.Enum,
		Font = roblox.Font,
		Random = RandomShim,
		task = taskShim,
		warn = function(...)
			print("[warn]", ...)
		end,
	}
end

function requireNode(node)
	if type(node) == "string" then
		return require(node)
	end
	local cached = loaded[node]
	if cached ~= nil then
		return cached
	end
	local path = rawget(node, "_path")
	assert(path, "not a module: " .. tostring(node))
	local source = fs.readFile(path)
	local chunk = luau.load(source, { debugName = path, environment = environmentFor(node) })
	local result = chunk()
	loaded[node] = result
	return result
end

return {
	shared = shared,
	maps = maps,
	require = requireNode,
	environmentFor = environmentFor,
	newNode = newNode,
	Random = RandomShim,
	CFrame = CFrameShim,
}
