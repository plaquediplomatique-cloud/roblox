--!strict
--[[
	ServerNet — branchement SÉCURISÉ des handlers de remotes.

	Chaque handler traverse : limite de débit (seau à jetons par joueur) -> schéma Guard ->
	exécution protégée (xpcall) : une erreur n'interrompt jamais l'écoute du remote.
	Les violations s'accumulent par joueur ; au-delà du seuil, le joueur est expulsé
	(client modifié ou script d'exploit).
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Net = require(Shared.Net.Net)
local Schemas = require(Shared.Net.Schemas)
local RateLimiter = require(Shared.Util.RateLimiter)
local Logger = require(Shared.Util.Logger)
local Players = game:GetService("Players")

local log = Logger.new("Net")

local ServerNet = {}

local KICK_THRESHOLD = 120 -- poids cumulés de violations avant expulsion
local DECAY_PER_SECOND = 0.5

local violations: { [Player]: { score: number, at: number } } = {}

local function report(player: Player, reason: string, weight: number)
	local now = os.clock()
	local entry = violations[player]
	if not entry then
		entry = { score = 0, at = now }
		violations[player] = entry
	end
	entry.score = math.max(0, entry.score - (now - entry.at) * DECAY_PER_SECOND) + weight
	entry.at = now
	log:warn("violation", player.Name, reason, math.floor(entry.score))
	if entry.score >= KICK_THRESHOLD then
		player:Kick("Unexpected network activity detected.")
	end
end

ServerNet.report = report

Players.PlayerRemoving:Connect(function(player)
	violations[player] = nil
end)

local function limiterFor(name: string): RateLimiter.RateLimiter
	local rate = Schemas.Rates[name]
	assert(rate, "pas de limite de débit pour " .. name)
	return RateLimiter.new(rate[1], rate[2])
end

-- Remote asynchrone : handler(player, payload).
function ServerNet.on(name: string, handler: (player: Player, payload: any) -> ())
	local schema = Schemas[name]
	assert(schema, "pas de schéma pour " .. name)
	local limiter = limiterFor(name)
	Net.event(name).OnServerEvent:Connect(function(player: Player, payload: any)
		if not limiter:consume(player) then
			report(player, "débit " .. name, 1)
			return
		end
		if not schema(payload) then
			report(player, "paquet invalide " .. name, 12)
			return
		end
		xpcall(handler, function(err)
			log:error("handler", name, debug.traceback(tostring(err)))
		end, player, payload)
	end)
end

export type Response = { ok: boolean, error: string?, data: any? }

-- RemoteFunction : répond toujours une enveloppe { ok, error?, data? }.
function ServerNet.onInvoke(name: string, handler: (player: Player, payload: any) -> any)
	local schema = Schemas[name]
	assert(schema, "pas de schéma pour " .. name)
	local limiter = limiterFor(name)
	Net.func(name).OnServerInvoke = function(player: Player, payload: any): Response
		if not limiter:consume(player) then
			report(player, "débit " .. name, 1)
			return { ok = false, error = "rate" }
		end
		if not schema(payload) then
			report(player, "paquet invalide " .. name, 12)
			return { ok = false, error = "invalid" }
		end
		local ok, result = xpcall(handler, debug.traceback, player, payload)
		if not ok then
			log:error("invoke", name, result)
			return { ok = false, error = "server" }
		end
		return { ok = true, data = result }
	end
end

return ServerNet
