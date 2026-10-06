--[[
	Runner de tests unitaires (Lune).

	Reproduit le minimum de l'environnement Roblox nécessaire à la logique PURE
	(voir tests/lib/loader.luau) puis exécute tests/specs/*.luau.

	Usage : lune run tests/run.luau   (ou ./scripts/test.sh)
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local loader = require("./lib/loader")

local shared = loader.shared
local requireNode = loader.require
local environmentFor = loader.environmentFor
local newNode = loader.newNode

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
	env.ServerMaps = loader.maps
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
