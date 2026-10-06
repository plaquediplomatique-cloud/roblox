--!strict
--[[
	Logger — journalisation catégorisée avec niveaux et historique circulaire.

	* Préfixe homogène : [AS][Server][Combat] message
	* Niveau global ajustable à chaud (Logger.setLevel) : Debug en Studio, Info en live.
	* Historique des 200 dernières entrées : affiché par l'overlay debug (F3) côté client,
	  et inspectable côté serveur pour diagnostiquer un incident sans relire la console.
	* Les erreurs sont aussi remontées par les wrappers `Logger.safe` (xpcall + traceback),
	  utilisés autour de chaque handler réseau et de chaque Start() de service : une erreur
	  dans un handler ne tue jamais la connexion ni le service.
]]

local RunService = game:GetService("RunService")

export type Level = "Debug" | "Info" | "Warn" | "Error"

export type Entry = {
	time: number,
	level: Level,
	category: string,
	message: string,
}

export type Logger = {
	category: string,
	debug: (self: Logger, ...any) -> (),
	info: (self: Logger, ...any) -> (),
	warn: (self: Logger, ...any) -> (),
	error: (self: Logger, ...any) -> (),
}

local LEVEL_ORDER: { [Level]: number } = { Debug = 1, Info = 2, Warn = 3, Error = 4 }
local HISTORY_SIZE = 200

local Logger = {}
Logger.history = {} :: { Entry }

local currentLevel: Level = if RunService:IsStudio() then "Debug" else "Info"

local contextTag = if RunService:IsServer() then "Server" else "Client"

local function format(...: any): string
	local parts = table.pack(...)
	local out = table.create(parts.n)
	for i = 1, parts.n do
		out[i] = tostring(parts[i])
	end
	return table.concat(out, " ")
end

local function record(level: Level, category: string, message: string)
	local history = Logger.history
	if #history >= HISTORY_SIZE then
		table.remove(history, 1)
	end
	table.insert(history, { time = os.clock(), level = level, category = category, message = message })
end

local function emit(self: Logger, level: Level, ...: any)
	if LEVEL_ORDER[level] < LEVEL_ORDER[currentLevel] then
		return
	end
	local message = format(...)
	record(level, self.category, message)
	local line = string.format("[AS][%s][%s] %s", contextTag, self.category, message)
	if level == "Warn" or level == "Error" then
		warn(line)
	else
		print(line)
	end
end

local LoggerClass = {}
LoggerClass.__index = LoggerClass

function LoggerClass.debug(self: Logger, ...: any)
	emit(self, "Debug", ...)
end
function LoggerClass.info(self: Logger, ...: any)
	emit(self, "Info", ...)
end
function LoggerClass.warn(self: Logger, ...: any)
	emit(self, "Warn", ...)
end
function LoggerClass.error(self: Logger, ...: any)
	emit(self, "Error", ...)
end

function Logger.new(category: string): Logger
	return (setmetatable({ category = category }, LoggerClass) :: any) :: Logger
end

function Logger.setLevel(level: Level)
	currentLevel = level
end

function Logger.getLevel(): Level
	return currentLevel
end

--[[
	Exécute `fn(...)` protégé ; en cas d'erreur, journalise message + traceback et renvoie false.
]]
function Logger.safe(logger: Logger, label: string, fn: (...any) -> ...any, ...: any): (boolean, ...any)
	local results = table.pack(xpcall(fn, function(err)
		return tostring(err) .. "\n" .. debug.traceback(nil, 2)
	end, ...))
	if not results[1] then
		logger:error(label, "failed:", results[2])
		return false
	end
	return table.unpack(results, 1, results.n)
end

return Logger
