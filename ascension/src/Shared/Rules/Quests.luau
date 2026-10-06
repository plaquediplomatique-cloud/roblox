--!strict
--[[
	Quests (règles) — sélection déterministe, progression et réclamation idempotente.
	Pure : le serveur fournit le temps et la graine ; aucun état global.
]]

local Config = require(script.Parent.Parent.Config.Quests)

local Quests = {}

export type Item = { Id: string, Progress: number, Claimed: boolean }
export type State = { Day: number, Week: number, Items: { Item } }

-- Métriques « maximum » (on retient la meilleure valeur) plutôt que cumulatives.
local MAX_METRICS: { [string]: boolean } = { Combo = true, BestCombo = true }

function Quests.dayNumber(now: number): number
	return math.floor(now / 86400)
end

-- Semaine commençant le lundi (le 1er janvier 1970 était un jeudi).
function Quests.weekNumber(now: number): number
	return math.floor((Quests.dayNumber(now) + 3) / 7)
end

local function lcg(seed: number): () -> number
	local state = (seed * 2654435761 + 12345) % 4294967296
	return function()
		state = (state * 1664525 + 1013904223) % 4294967296
		return state / 4294967296
	end
end

-- Choisit `count` quêtes aux métriques distinctes (déterministe pour (graine, jour)).
function Quests.pickDaily(seed: number, day: number, count: number): { string }
	local random = lcg(seed + day * 7919)
	local pool = table.clone(Config.Daily)
	local picked: { string } = {}
	local usedMetrics: { [string]: boolean } = {}
	local attempts = 0
	while #picked < count and #pool > 0 and attempts < 200 do
		attempts += 1
		local index = math.floor(random() * #pool) + 1
		local quest = pool[index]
		if not usedMetrics[quest.Metric] then
			usedMetrics[quest.Metric] = true
			table.insert(picked, quest.Id)
			table.remove(pool, index)
		end
	end
	return picked
end

local function find(state: State, id: string): Item?
	for _, item in state.Items do
		if item.Id == id then
			return item
		end
	end
	return nil
end

-- Renouvelle les quêtes expirées. Renvoie true si quelque chose a changé.
function Quests.ensure(state: State, now: number, seed: number): boolean
	local day = Quests.dayNumber(now)
	local week = Quests.weekNumber(now)
	local changed = false
	if state.Day ~= day then
		-- Retire les quêtes quotidiennes, garde les hebdomadaires.
		local kept: { Item } = {}
		for _, item in state.Items do
			local def = Config.ById[item.Id]
			if def and def.Weekly then
				table.insert(kept, item)
			end
		end
		state.Items = kept
		for _, id in Quests.pickDaily(seed, day, Config.DailyCount) do
			table.insert(state.Items, { Id = id, Progress = 0, Claimed = false })
		end
		state.Day = day
		changed = true
	end
	if state.Week ~= week then
		local kept: { Item } = {}
		for _, item in state.Items do
			local def = Config.ById[item.Id]
			if not (def and def.Weekly) then
				table.insert(kept, item)
			end
		end
		state.Items = kept
		for _, quest in Config.Weekly do
			table.insert(state.Items, { Id = quest.Id, Progress = 0, Claimed = false })
		end
		state.Week = week
		changed = true
	end
	return changed
end

-- Enregistre `amount` pour une métrique. Renvoie les identifiants de quêtes TERMINÉES par cet appel.
function Quests.record(state: State, metric: string, amount: number): { string }
	local completed: { string } = {}
	for _, item in state.Items do
		local def = Config.ById[item.Id]
		if def and def.Metric == metric and item.Progress < def.Target then
			if MAX_METRICS[metric] then
				item.Progress = math.min(def.Target, math.max(item.Progress, amount))
			else
				item.Progress = math.min(def.Target, item.Progress + amount)
			end
			if item.Progress >= def.Target then
				table.insert(completed, item.Id)
			end
		end
	end
	return completed
end

-- Réclamation idempotente : renvoie la récompense la première fois seulement.
function Quests.claim(state: State, id: string): Config.Quest?
	local item = find(state, id)
	local def = Config.ById[id]
	if not item or not def or item.Claimed or item.Progress < def.Target then
		return nil
	end
	item.Claimed = true
	return def
end

return Quests
