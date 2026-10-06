--!strict
--[[
	Guard — validation stricte des données entrantes (remotes client -> serveur).

	Règle d'or : TOUT argument reçu d'un client est hostile jusqu'à preuve du contraire.
	Un exploiteur peut envoyer n'importe quel type, NaN, ±inf, des tables avec métatables,
	des tables géantes, des chaînes de 4 Mo, des vecteurs de magnitude 1e308…

	Chaque remote déclare un "schéma" composé de checks. Un paquet qui ne valide pas est
	rejeté AVANT d'atteindre la logique de jeu, et l'AntiCheatService est notifié.

	Exemple :
		local isFire = Guard.shape({
			w = Guard.string(24),
			a = Guard.unitVector(0.02),
			s = Guard.range(0, 45),
		})
		if not isFire(payload) then return end
]]

export type Check = (value: any) -> boolean

local Guard = {}

local function isFinite(x: number): boolean
	return x == x and x ~= math.huge and x ~= -math.huge
end

Guard.isFinite = isFinite

function Guard.any(_value: any): boolean
	return true
end

function Guard.boolean(value: any): boolean
	return type(value) == "boolean"
end

function Guard.number(value: any): boolean
	return type(value) == "number" and isFinite(value)
end

function Guard.range(min: number, max: number): Check
	return function(value: any): boolean
		return type(value) == "number" and isFinite(value) and value >= min and value <= max
	end
end

function Guard.integer(min: number, max: number): Check
	return function(value: any): boolean
		return type(value) == "number" and value == math.floor(value) and value >= min and value <= max
	end
end

function Guard.string(maxLength: number): Check
	return function(value: any): boolean
		return type(value) == "string" and #value <= maxLength and utf8.len(value) ~= nil
	end
end

function Guard.literal(...: string): Check
	local allowed: { [string]: boolean } = {}
	for _, item in { ... } do
		allowed[item] = true
	end
	return function(value: any): boolean
		return type(value) == "string" and allowed[value] == true
	end
end

function Guard.oneOf(list: { string }): Check
	local allowed: { [string]: boolean } = {}
	for _, item in list do
		allowed[item] = true
	end
	return function(value: any): boolean
		return type(value) == "string" and allowed[value] == true
	end
end

function Guard.vector3(maxMagnitude: number): Check
	return function(value: any): boolean
		if typeof(value) ~= "Vector3" then
			return false
		end
		local v = value :: Vector3
		return isFinite(v.X) and isFinite(v.Y) and isFinite(v.Z) and v.Magnitude <= maxMagnitude
	end
end

function Guard.unitVector(tolerance: number): Check
	return function(value: any): boolean
		if typeof(value) ~= "Vector3" then
			return false
		end
		local v = value :: Vector3
		if not (isFinite(v.X) and isFinite(v.Y) and isFinite(v.Z)) then
			return false
		end
		return math.abs(v.Magnitude - 1) <= tolerance
	end
end

function Guard.hexColor(value: any): boolean
	return type(value) == "string" and string.match(value, "^#%x%x%x%x%x%x$") ~= nil
end

function Guard.optional(check: Check): Check
	return function(value: any): boolean
		return value == nil or check(value)
	end
end

local function isPlainTable(value: any): boolean
	return type(value) == "table" and getmetatable(value) == nil
end

function Guard.array(check: Check, maxLength: number): Check
	return function(value: any): boolean
		if not isPlainTable(value) then
			return false
		end
		local count = 0
		for key, item in value do
			count += 1
			if count > maxLength or type(key) ~= "number" or key ~= math.floor(key) or key < 1 then
				return false
			end
			if not check(item) then
				return false
			end
		end
		return count == #value
	end
end

function Guard.dictionary(keyCheck: Check, valueCheck: Check, maxEntries: number): Check
	return function(value: any): boolean
		if not isPlainTable(value) then
			return false
		end
		local count = 0
		for key, item in value do
			count += 1
			if count > maxEntries or not keyCheck(key) or not valueCheck(item) then
				return false
			end
		end
		return true
	end
end

--[[
	Table stricte : chaque champ déclaré doit valider, AUCUN champ supplémentaire n'est
	toléré (un champ inconnu = client modifié). Les champs optionnels utilisent Guard.optional.
]]
function Guard.shape(fields: { [string]: Check }): Check
	return function(value: any): boolean
		if not isPlainTable(value) then
			return false
		end
		for key in value do
			if type(key) ~= "string" or fields[key] == nil then
				return false
			end
		end
		for key, check in fields do
			if not check(value[key]) then
				return false
			end
		end
		return true
	end
end

function Guard.player(value: any): boolean
	return typeof(value) == "Instance" and (value :: Instance):IsA("Player")
end

return Guard
