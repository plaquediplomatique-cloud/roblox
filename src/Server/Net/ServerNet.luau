--!strict
--[[
	ServerNet — branchement SÉCURISÉ des handlers de remotes.

	Chaque handler traverse, dans l'ordre :
	  1. rate limit (seau à jetons par joueur et par remote),
	  2. validation stricte du paquet (Guard) -> payload typé,
	  3. exécution protégée (xpcall + traceback) : une erreur n'interrompt jamais
	     l'écoute du remote ni le service.
	Les violations (spam, paquet invalide) sont remontées à l'AntiCheatService via un
	"reporter" injecté (pas de dépendance circulaire).

	Les RemoteFunctions répondent toujours une enveloppe { ok, error?, data? }.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Net = require(Shared.Net.Net)
local RateLimiter = require(Shared.Util.RateLimiter)
local Logger = require(Shared.Util.Logger)

local log = Logger.new("Net")

export type RateSpec = { capacity: number, refill: number }

export type Response = { ok: boolean, error: string?, data: any? }

type Reporter = (player: Player, reason: string, weight: number) -> ()

local ServerNet = {}

local reporter: Reporter = function(player: Player, reason: string, _weight: number)
	log:warn("violation", player.Name, reason)
end

function ServerNet.setViolationReporter(fn: Reporter)
	reporter = fn
end

function ServerNet.report(player: Player, reason: string, weight: number)
	reporter(player, reason, weight)
end

local function guardCall<T>(player: Player, name: string, limiter: RateLimiter.RateLimiter, parse: (...any) -> T?, ...: any): T?
	if not limiter:consume(player) then
		reporter(player, "RateLimit:" .. name, 0.5)
		return nil
	end
	local ok, payload = pcall(parse, ...)
	if not ok or payload == nil then
		reporter(player, "BadPayload:" .. name, 2)
		return nil
	end
	return payload
end

function ServerNet.onEvent<T>(name: Net.EventName, rate: RateSpec, parse: (...any) -> T?, handler: (Player, T) -> ())
	local limiter = RateLimiter.new(rate.capacity, rate.refill)
	Net.event(name).OnServerEvent:Connect(function(player: Player, ...: any)
		local payload = guardCall(player, name, limiter, parse, ...)
		if payload ~= nil then
			Logger.safe(log, name, handler, player, payload)
		end
	end)
end

function ServerNet.onUnreliable<T>(name: Net.UnreliableName, rate: RateSpec, parse: (...any) -> T?, handler: (Player, T) -> ())
	local limiter = RateLimiter.new(rate.capacity, rate.refill)
	Net.unreliable(name).OnServerEvent:Connect(function(player: Player, ...: any)
		local payload = guardCall(player, name, limiter, parse, ...)
		if payload ~= nil then
			Logger.safe(log, name, handler, player, payload)
		end
	end)
end

function ServerNet.onInvoke<T>(name: Net.FunctionName, rate: RateSpec, parse: (...any) -> T?, handler: (Player, T) -> Response)
	local limiter = RateLimiter.new(rate.capacity, rate.refill)
	Net.func(name).OnServerInvoke = function(player: Player, ...: any): Response
		local payload = guardCall(player, name, limiter, parse, ...)
		if payload == nil then
			return { ok = false, error = "Requête refusée" }
		end
		local ok, result = Logger.safe(log, name, handler, player, payload)
		if not ok then
			return { ok = false, error = "Erreur serveur" }
		end
		return result :: Response
	end
end

function ServerNet.success(data: any?): Response
	return { ok = true, data = data }
end

function ServerNet.failure(message: string): Response
	return { ok = false, error = message }
end

--[[ Envoi ciblé à une liste de joueurs (évite FireAllClients hors contexte). ]]
function ServerNet.fireList(remote: RemoteEvent, players: { Player }, ...: any)
	for _, player in players do
		if player.Parent then
			remote:FireClient(player, ...)
		end
	end
end

function ServerNet.fireListUnreliable(remote: UnreliableRemoteEvent, players: { Player }, ...: any)
	for _, player in players do
		if player.Parent then
			remote:FireClient(player, ...)
		end
	end
end

return ServerNet
