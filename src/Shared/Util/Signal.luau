--!strict
--[[
	Signal — événement Lua pur, sans BindableEvent.

	Pourquoi pas BindableEvent ? Les BindableEvents copient/sérialisent les tables passées
	(perte des métatables, des clés non-string) et coûtent un aller-retour moteur.
	Ce Signal :
	  * ne copie rien (on passe des références),
	  * isole les erreurs (un handler qui plante n'empêche pas les suivants),
	  * réutilise un thread "runner" (technique GoodSignal) pour éviter une allocation
	    de coroutine par handler,
	  * supporte Wait() et Once().
]]

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, callback: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, callback: (T...) -> ()) -> Connection,
	Fire: (self: Signal<T...>, T...) -> (),
	Wait: (self: Signal<T...>) -> T...,
	DisconnectAll: (self: Signal<T...>) -> (),
	Destroy: (self: Signal<T...>) -> (),
}

type Node = {
	fn: (...any) -> (),
	next: Node?,
	connected: boolean,
	signal: any,
}

local freeRunnerThread: thread? = nil

local function acquireRunnerThreadAndCall(fn: (...any) -> (), ...: any)
	local acquired = freeRunnerThread
	freeRunnerThread = nil
	fn(...)
	-- Le handler n'a pas yield : on rend le thread réutilisable.
	freeRunnerThread = acquired
end

local function runEventHandlerInFreeThread()
	while true do
		acquireRunnerThreadAndCall(coroutine.yield())
	end
end

local ConnectionClass = {}
ConnectionClass.__index = ConnectionClass

function ConnectionClass.Disconnect(self: any)
	if not self.Connected then
		return
	end
	self.Connected = false
	local node: Node = self._node
	node.connected = false
	local signal = node.signal
	if signal._head == node then
		signal._head = node.next
	else
		local prev = signal._head
		while prev and prev.next ~= node do
			prev = prev.next
		end
		if prev then
			prev.next = node.next
		end
	end
end

local SignalClass = {}
SignalClass.__index = SignalClass

local function connect(self: any, fn: (...any) -> ()): Connection
	local node: Node = {
		fn = fn,
		next = self._head,
		connected = true,
		signal = self,
	}
	self._head = node
	local connection = setmetatable({ Connected = true, _node = node }, ConnectionClass)
	return (connection :: any) :: Connection
end

function SignalClass.Connect(self: any, fn: (...any) -> ()): Connection
	return connect(self, fn)
end

function SignalClass.Once(self: any, fn: (...any) -> ()): Connection
	local connection: Connection
	connection = connect(self, function(...)
		if connection.Connected then
			connection:Disconnect()
			fn(...)
		end
	end)
	return connection
end

function SignalClass.Fire(self: any, ...: any)
	-- Les handlers sont empilés en tête : on collecte d'abord pour appeler dans l'ordre
	-- de connexion, ce qui rend l'exécution déterministe.
	local handlers: { Node } = {}
	local node: Node? = self._head
	while node do
		table.insert(handlers, node)
		node = node.next
	end
	for index = #handlers, 1, -1 do
		local item = handlers[index]
		if item.connected then
			if not freeRunnerThread then
				local runner = coroutine.create(runEventHandlerInFreeThread)
				freeRunnerThread = runner
				coroutine.resume(runner)
			end
			task.spawn(freeRunnerThread :: thread, item.fn, ...)
		end
	end
end

function SignalClass.Wait(self: any): ...any
	local thread = coroutine.running()
	local connection: Connection
	connection = connect(self, function(...)
		connection:Disconnect()
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function SignalClass.DisconnectAll(self: any)
	local node: Node? = self._head
	while node do
		node.connected = false
		node = node.next
	end
	self._head = nil
end

function SignalClass.Destroy(self: any)
	SignalClass.DisconnectAll(self)
end

local Signal = {}

function Signal.new<T...>(): Signal<T...>
	local self = setmetatable({ _head = nil }, SignalClass)
	return (self :: any) :: Signal<T...>
end

return Signal
