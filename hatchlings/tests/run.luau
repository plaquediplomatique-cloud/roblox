--[[
	Runner de tests Lune de Hatchlings (logique pure + intégrité des configs).
	Usage : lune run tests/run.luau   (ou ./scripts/test.sh, depuis hatchlings/)

	Les modules testés n'ont aucun `require` : on les charge un par un avec les datatypes
	Roblox de @lune/roblox (Color3…).
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

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
		error(
			("%s: expected %s ± %s, got %s"):format(
				message or "near",
				tostring(expected),
				tostring(epsilon),
				tostring(actual)
			),
			2
		)
	end
end

local cache = {}

-- Charge src/Shared/<path>.luau (ex. "Rules/Hatch").
local function load(path)
	if cache[path] then
		return cache[path]
	end
	local file = "src/Shared/" .. path .. ".luau"
	local chunk = luau.load(fs.readFile(file), {
		debugName = file,
		environment = { Color3 = roblox.Color3, Font = roblox.Font, Vector3 = roblox.Vector3 },
	})
	cache[path] = chunk()
	return cache[path]
end

local specs = {}
for _, entry in fs.readDir("tests/specs") do
	if string.sub(entry, -5) == ".luau" then
		table.insert(specs, entry)
	end
end
table.sort(specs)

for _, entry in specs do
	local path = "tests/specs/" .. entry
	local env = { T = T, load = load }
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
