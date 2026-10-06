--!strict
--[[
	Janitor — gestion déterministe du cycle de vie (connexions, instances, threads, callbacks).

	Chaque contrôleur/objet de gameplay possède un Janitor ; tout ce qui est créé pour lui
	y est enregistré, et un unique :Cleanup() libère tout. C'est la première défense contre
	les fuites mémoire (connexions orphelines sur des personnages détruits, effets jamais
	nettoyés, threads qui survivent à un round…).
]]

export type Janitor = {
	Add: <T>(self: Janitor, object: T, method: string?) -> T,
	Connect: (self: Janitor, signal: RBXScriptSignal, callback: (...any) -> ()) -> RBXScriptConnection,
	Cleanup: (self: Janitor) -> (),
	Destroy: (self: Janitor) -> (),
}

type Entry = { object: any, method: string? }

local JanitorClass = {}
JanitorClass.__index = JanitorClass

local function cleanupObject(object: any, method: string?)
	local kind = typeof(object)
	if method then
		local fn = object[method]
		if type(fn) == "function" then
			fn(object)
		end
	elseif kind == "Instance" then
		(object :: Instance):Destroy()
	elseif kind == "RBXScriptConnection" then
		(object :: RBXScriptConnection):Disconnect()
	elseif kind == "function" then
		object()
	elseif kind == "thread" then
		local thread = object :: thread
		if coroutine.status(thread) ~= "dead" and thread ~= coroutine.running() then
			pcall(task.cancel, thread)
		end
	elseif kind == "table" then
		if type(object.Destroy) == "function" then
			object:Destroy()
		elseif type(object.Disconnect) == "function" then
			object:Disconnect()
		end
	end
end

function JanitorClass.Add(self: any, object: any, method: string?): any
	table.insert(self._entries, { object = object, method = method })
	return object
end

function JanitorClass.Connect(self: any, signal: RBXScriptSignal, callback: (...any) -> ()): RBXScriptConnection
	local connection = signal:Connect(callback)
	table.insert(self._entries, { object = connection })
	return connection
end

function JanitorClass.Cleanup(self: any)
	local entries: { Entry } = self._entries
	self._entries = {}
	-- Ordre inverse : on détruit d'abord ce qui a été créé en dernier (dépend du reste).
	for index = #entries, 1, -1 do
		local entry = entries[index]
		local ok, err = pcall(cleanupObject :: any, entry.object, entry.method)
		if not ok then
			warn("[Janitor] cleanup error:", err)
		end
	end
end

function JanitorClass.Destroy(self: any)
	JanitorClass.Cleanup(self)
end

local Janitor = {}

function Janitor.new(): Janitor
	return (setmetatable({ _entries = {} }, JanitorClass) :: any) :: Janitor
end

return Janitor
