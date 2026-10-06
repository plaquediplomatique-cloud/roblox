--[[
	Chargeur de modules hors moteur (Lune) pour Smash Ascension.

	Monte ascension/src/Shared (+ les utilitaires génériques de src/Shared/Util, comme le fait
	ascension.project.json) dans un arbre d'« instances » virtuel pour que
	`require(script.Parent.X)` fonctionne, et fournit les datatypes Roblox de @lune/roblox.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

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
			local child = rawget(node, "_children")[entry] or newNode(entry, node, nil)
			rawget(node, "_children")[entry] = child
			mount(full, child)
		elseif string.sub(entry, -5) == ".luau" then
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
mount("ascension/src/Shared", shared)
local util = newNode("Util", shared, nil)
rawget(shared, "_children").Util = util
mount("src/Shared/Util", util)

local game = {
	GetService = function(_, name)
		if name == "ReplicatedStorage" then
			return replicatedStorage
		end
		error("service not available in tests: " .. tostring(name))
	end,
}

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
		warn = function(...)
			print("[warn]", ...)
		end,
	}
end

function requireNode(node)
	local cached = loaded[node]
	if cached ~= nil then
		return cached
	end
	local path = rawget(node, "_path")
	assert(path, "not a module: " .. tostring(node))
	local chunk = luau.load(fs.readFile(path), { debugName = path, environment = environmentFor(node) })
	local result = chunk()
	loaded[node] = result
	return result
end

return {
	shared = shared,
	require = requireNode,
	environmentFor = environmentFor,
	newNode = newNode,
}
