--!strict
--[[
	Ranks — système de rang compétitif.

	Double couche (comme les meilleurs jeux compétitifs) :
	  * MMR caché (Elo à K dynamique) : mesure réelle du niveau, sert au matchmaking.
	  * Rang visible = palier + division + RR (0–100). Les gains/pertes de RR sont
	    modulés par l'écart entre le rang affiché et le rang "attendu" par le MMR :
	    un joueur sous-classé gagne plus et perd moins -> convergence rapide et juste.

	8 paliers : RECRUIT, OPERATIVE, SPECIALIST, VANGUARD, SENTINEL, PHANTOM, APEX
	(3 divisions chacun), puis AETHER (palier unique, classement global).
	rankIndex : 0 (Recruit I) … 20 (Apex III), 21 = Aether.
]]

export type Tier = {
	name: string,
	color: Color3,
	glyph: string,
}

local Ranks = {}

Ranks.tiers = {
	{ name = "RECRUIT", color = Color3.fromRGB(140, 150, 160), glyph = "◇" },
	{ name = "OPERATIVE", color = Color3.fromRGB(120, 190, 140), glyph = "◈" },
	{ name = "SPECIALIST", color = Color3.fromRGB(80, 170, 255), glyph = "⬖" },
	{ name = "VANGUARD", color = Color3.fromRGB(70, 225, 255), glyph = "⬘" },
	{ name = "SENTINEL", color = Color3.fromRGB(170, 120, 255), glyph = "⬙" },
	{ name = "PHANTOM", color = Color3.fromRGB(255, 90, 170), glyph = "⬗" },
	{ name = "APEX", color = Color3.fromRGB(255, 190, 70), glyph = "✦" },
	{ name = "AETHER", color = Color3.fromRGB(255, 255, 255), glyph = "✺" },
} :: { Tier }

Ranks.MAX_INDEX = 21
Ranks.PLACEMENT_MATCHES = 5
Ranks.START_MMR = 1000
Ranks.MMR_FLOOR = 0

local DIVISIONS = { "I", "II", "III" }

function Ranks.tierOf(rankIndex: number): (Tier, number)
	local index = math.clamp(math.floor(rankIndex), 0, Ranks.MAX_INDEX)
	if index >= Ranks.MAX_INDEX then
		return Ranks.tiers[8], 0
	end
	local tier = math.floor(index / 3) + 1
	local division = index % 3 + 1
	return Ranks.tiers[tier], division
end

function Ranks.displayName(rankIndex: number): string
	local tier, division = Ranks.tierOf(rankIndex)
	if division == 0 then
		return tier.name
	end
	return tier.name .. " " .. DIVISIONS[division]
end

--[[ Rang "attendu" pour un MMR donné (600 -> Recruit I, 1860 -> Aether). ]]
function Ranks.expectedIndex(mmr: number): number
	return math.clamp((mmr - 600) / 60, 0, Ranks.MAX_INDEX)
end

--[[ Score composite pour le classement (leaderboard) et l'affichage. ]]
function Ranks.ladderScore(rankIndex: number, rr: number): number
	return rankIndex * 100 + rr
end

return Ranks
