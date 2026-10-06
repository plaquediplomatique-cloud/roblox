--[[
	Runner de tests unitaires (Lune).

	Reproduit le minimum de l'environnement Roblox nécessaire à la logique PURE :
	  * un arbre d'"instances" virtuel monté depuis src/Shared (script.Parent.X fonctionne),
	  * un `require` qui charge les ModuleScripts depuis le disque avec luau.load,
	  * les datatypes Roblox réels de @lune/roblox (Vector3, CFrame, Enum…),
	  * des shims pour Random (PCG32 déterministe), task et game:GetService.

	Usage : lune run tests/run.luau   (ou ./scripts/test.sh)
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local process = require("@lune/process")

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

services.ReplicatedStorage = replicatedStorage

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
		CFrame = roblox.CFrame,
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

---------------------------------------------------------------------------------------------
-- Mini framework de test
---------------------------------------------------------------------------------------------

local T = { passed = 0, failed = 0, failures = {}, current = "" }

function T.describe(name, fn)
	T.current = name
	fn()
end

function T.it(name, fn)
	local ok, err = pcall(fn)
	if ok then
		T.passed += 1
	else
		T.failed += 1
		table.insert(T.failures, ("[%s] %s\n    %s"):format(T.current, name, tostring(err)))
	end
end

function T.expect(condition, message)
	if not condition then
		error(message or "expectation failed", 2)
	end
end

function T.eq(actual, expected, message)
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(message or "eq", tostring(expected), tostring(actual)), 2)
	end
end

function T.near(actual, expected, epsilon, message)
	if math.abs(actual - expected) > epsilon then
		error(("%s: expected %s ± %s, got %s"):format(message or "near", tostring(expected), tostring(epsilon), tostring(actual)), 2)
	end
end

---------------------------------------------------------------------------------------------
-- Exécution
---------------------------------------------------------------------------------------------

local specs = {}
for _, entry in fs.readDir("tests/specs") do
	if string.sub(entry, -5) == ".luau" then
		table.insert(specs, entry)
	end
end
table.sort(specs)

for _, entry in specs do
	local path = "tests/specs/" .. entry
	local env = environmentFor(newNode(entry, nil, path))
	env.T = T
	env.Shared = shared
	env.req = requireNode
	local chunk = luau.load(fs.readFile(path), { debugName = path, environment = env })
	local ok, err = pcall(chunk)
	if not ok then
		T.failed += 1
		table.insert(T.failures, ("[%s] chargement\n    %s"):format(entry, tostring(err)))
	end
end

print(("\n%d tests OK, %d échec(s)"):format(T.passed, T.failed))
for _, failure in T.failures do
	print("  ✗ " .. failure)
end
process.exit(if T.failed > 0 then 1 else 0)
