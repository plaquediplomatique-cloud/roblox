--!strict
--[[
	ReplicaPath — opérations par chemin sur l'état répliqué (partagé client/serveur).

	Un chemin est une liste de clés : { "Rank", "RR" } ou { "players", "12345", "kills" }.
	Le serveur applique une mutation sur SA copie, puis envoie (opcode, chemin, valeur) ;
	le client rejoue exactement la même opération sur sa copie. Les deux restent
	identiques par construction, et seul le delta transite sur le réseau.

	Contrainte de sérialisation Roblox : les tables envoyées doivent être des tableaux
	purs OU des dictionnaires à clés string. Les identifiants numériques (UserId…) sont
	donc toujours convertis en string dans l'état répliqué.
]]

export type Key = string | number
export type Path = { Key }

export type Op = number

local ReplicaPath = {}

ReplicaPath.OP_SET = 1 :: Op
ReplicaPath.OP_SET_VALUES = 2 :: Op
ReplicaPath.OP_ARRAY_INSERT = 3 :: Op
ReplicaPath.OP_ARRAY_REMOVE = 4 :: Op
ReplicaPath.OP_REPLACE = 5 :: Op

function ReplicaPath.get(root: any, path: Path): any
	local node = root
	for _, key in path do
		if type(node) ~= "table" then
			return nil
		end
		node = node[key]
	end
	return node
end

--[[ Renvoie le conteneur parent du dernier segment (en créant les tables manquantes). ]]
local function parentOf(root: any, path: Path): (any, Key)
	local node = root
	for index = 1, #path - 1 do
		local key = path[index]
		local child = node[key]
		if type(child) ~= "table" then
			child = {}
			node[key] = child
		end
		node = child
	end
	return node, path[#path]
end

function ReplicaPath.set(root: any, path: Path, value: any)
	if #path == 0 then
		error("ReplicaPath.set: empty path")
	end
	local parent, key = parentOf(root, path)
	parent[key] = value
end

function ReplicaPath.setValues(root: any, path: Path, values: { [string]: any })
	local target = if #path == 0 then root else ReplicaPath.get(root, path)
	if type(target) ~= "table" then
		target = {}
		ReplicaPath.set(root, path, target)
	end
	for key, value in values do
		target[key] = value
	end
end

function ReplicaPath.arrayInsert(root: any, path: Path, value: any, index: number?): number
	local array = ReplicaPath.get(root, path)
	if type(array) ~= "table" then
		array = {}
		ReplicaPath.set(root, path, array)
	end
	local position = index or (#array + 1)
	table.insert(array, position, value)
	return position
end

function ReplicaPath.arrayRemove(root: any, path: Path, index: number): any
	local array = ReplicaPath.get(root, path)
	if type(array) ~= "table" then
		return nil
	end
	return table.remove(array, index)
end

function ReplicaPath.apply(root: any, op: Op, path: Path, a: any, b: any)
	if op == ReplicaPath.OP_SET then
		ReplicaPath.set(root, path, a)
	elseif op == ReplicaPath.OP_SET_VALUES then
		ReplicaPath.setValues(root, path, a)
	elseif op == ReplicaPath.OP_ARRAY_INSERT then
		ReplicaPath.arrayInsert(root, path, a, b)
	elseif op == ReplicaPath.OP_ARRAY_REMOVE then
		ReplicaPath.arrayRemove(root, path, a)
	end
end

function ReplicaPath.toKey(path: Path): string
	local parts = table.create(#path)
	for index, key in path do
		parts[index] = tostring(key)
	end
	return table.concat(parts, ".")
end

function ReplicaPath.deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, item in value :: any do
		copy[key] = ReplicaPath.deepCopy(item)
	end
	return (copy :: any) :: T
end

--[[ Vrai si `prefix` est un préfixe de `path` (pour notifier les écouteurs parents). ]]
function ReplicaPath.isPrefix(prefix: Path, path: Path): boolean
	if #prefix > #path then
		return false
	end
	for index, key in prefix do
		if tostring(path[index]) ~= tostring(key) then
			return false
		end
	end
	return true
end

return ReplicaPath
