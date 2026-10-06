--[[
	Simulation de rythme : un joueur « moyen » (aucune amélioration, combo moyen x1.5, cadence de
	l'arme) suit la voie principale. On mesure le temps par niveau et on vérifie qu'il reste
	dans une fourchette de design : rapide au début (accroche), jamais un mur.
]]

local Curves = req(Shared.Rules.Curves)
local WeaponCatalog = req(Shared.Rules.WeaponCatalog)
local Game = req(Shared.Config.Game)
local Zones = req(Shared.Config.Zones)

local COMBO_AVG = 1.5
local RESPAWN = Game.DummyRespawn

local function secondsPerLevel(level, stars)
	local zone = Curves.zoneOfLevel(level)
	local owned = WeaponCatalog.mainUnlockedAt(level)
	local weapon = owned[#owned]
	local starsDamage = 1 + Game.AscensionStarDamage * stars
	local damage = weapon.Damage * COMBO_AVG * starsDamage
	local hp = Curves.dummyHP(zone)
	local hitsPerKill = math.max(1, math.ceil(hp / damage))
	local cadence = Game.BaseSwingsPerSecond * weapon.ArchetypeData.Speed
	local killSeconds = hitsPerKill / cadence + RESPAWN
	local xpPerKill = Curves.xpPerKill(zone) * weapon.XPBoost * COMBO_AVG * (1 + Game.AscensionStarXP * stars)
	local kills = Curves.xpToNext(level) / xpPerKill
	return kills * killSeconds, kills
end

local totalSeconds = 0
local worst, worstLevel = 0, 0
local early = 0
for level = 1, Game.MaxLevel - 1 do
	local seconds = secondsPerLevel(level, 0)
	totalSeconds += seconds
	if seconds > worst then
		worst, worstLevel = seconds, level
	end
	if level <= 5 then
		early += seconds
	end
end

local report = {}
for _, level in { 1, 2, 3, 5, 8, 12, 13, 20, 36, 37, 60, 85, 100, 119 } do
	table.insert(report, ("L%d=%.0fs"):format(level, (secondsPerLevel(level, 0))))
end
print(
	("[pacing] %s | total %.1f h | pire niveau L%d = %.0fs | 5 premiers niveaux = %.0fs"):format(
		table.concat(report, " "),
		totalSeconds / 3600,
		worstLevel,
		worst,
		early
	)
)

T.describe("Rythme de progression (simulation)", function()
	T.it("première minute : les 5 premiers niveaux en moins de 90 s", function()
		T.expect(early < 90, ("%.0fs"):format(early))
	end)
	T.it("aucun niveau n'est un mur (< 6 min sans amélioration)", function()
		T.expect(worst < 360, ("L%d = %.0fs"):format(worstLevel, worst))
	end)
	T.it("aucun niveau n'est trivial après l'accroche (> 4 s)", function()
		for level = 6, Game.MaxLevel - 1 do
			local seconds = secondsPerLevel(level, 0)
			T.expect(seconds > 4, ("L%d = %.1fs"):format(level, seconds))
		end
	end)
	T.it("niveau max sans améliorations en 4 à 14 h (le prestige prolonge)", function()
		local hours = totalSeconds / 3600
		T.expect(hours > 4 and hours < 14, ("%.1f h"):format(hours))
	end)
	T.it("une étoile d'Ascension accélère nettement la remontée", function()
		local with, without = 0, 0
		for level = 1, Game.MaxLevel - 1 do
			with += secondsPerLevel(level, 3)
			without += secondsPerLevel(level, 0)
		end
		T.expect(with < without * 0.8, ("%.1f h vs %.1f h"):format(with / 3600, without / 3600))
	end)
	T.it("chaque nouvelle zone remet un défi : plus de coups par kill qu'en fin de zone précédente", function()
		for zone = 2, Zones.Count do
			local prevLast = WeaponCatalog.Main[(zone - 1) * Zones.WeaponsPerZone]
			local newFirst = WeaponCatalog.Main[(zone - 1) * Zones.WeaponsPerZone + 1]
			local before = math.ceil(Curves.dummyHP(zone - 1) / prevLast.Damage)
			local after = math.ceil(Curves.dummyHP(zone) / newFirst.Damage)
			T.expect(after > before, "zone " .. zone)
		end
	end)
end)
