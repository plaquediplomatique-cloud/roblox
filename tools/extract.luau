--!strict
-- Extrait tous les scripts d'un fichier .rbxl/.rbxlx vers une arborescence compatible Rojo.
-- Usage : lune run tools/extract.luau -- <place.rbxl> <dossier de sortie>

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local placePath, outDir = process.args[1], process.args[2]
if not placePath or not outDir then
	error("usage : extract.luau <place.rbxl> <sortie>")
end

local SUFFIX: { [string]: string } = {
	Script = ".server.luau",
	LocalScript = ".client.luau",
	ModuleScript = ".luau",
}

local function clean(name: string): string
	return (name:gsub('[<>:"/\\|?*%c]', "_"))
end

local game = roblox.deserializePlace(fs.readFile(placePath))
local count = 0
local seen: { [string]: boolean } = {}

local function pathOf(inst: roblox.Instance): string
	local parts = {}
	local cur: roblox.Instance? = inst
	while cur and cur ~= game do
		table.insert(parts, 1, clean(cur.Name))
		cur = cur.Parent
	end
	return table.concat(parts, "/")
end

for _, inst in game:GetDescendants() do
	local suffix = SUFFIX[inst.ClassName]
	if suffix then
		local rel = pathOf(inst)
		local file = `{outDir}/{rel}{suffix}`
		-- Doublons de noms frères : on suffixe pour ne rien écraser.
		local n = 1
		while seen[file] do
			n += 1
			file = `{outDir}/{rel}_{n}{suffix}`
		end
		seen[file] = true
		fs.writeDir(file:match("^(.*)/[^/]*$") :: string)
		fs.writeFile(file, (inst :: any).Source)
		count += 1
	end
end

print(`{count} scripts`)
