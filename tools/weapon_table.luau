--[[
	Génère les tableaux de référence des armes (Markdown) DEPUIS la config réelle :
	`lune run tools/weapon_table.luau > build/weapons.md`
	La documentation (docs/07) cite ces valeurs : aucun chiffre n'est saisi à la main.
]]

local loader = require("../tests/lib/loader")

local Weapons = loader.require(loader.shared.Config.Weapons)
local Ballistics = loader.require(loader.shared.Combat.Ballistics)
local RecoilPatterns = loader.require(loader.shared.Config.RecoilPatterns)

local MODE_NAMES =
	{ Auto = "Auto", Semi = "Semi", Burst = "Rafale", Bolt = "Verrou", Pump = "Pompe", Melee = "Mêlée" }

local function ttk(def)
	local shots = Ballistics.shotsToKill(def.damage, "Body", 15, Ballistics.MAX_ARMOR)
	local total = 0
	if def.fire.mode == "Burst" then
		local intra = 60 / def.fire.burstRpm
		for shot = 2, shots do
			total += if (shot - 1) % def.fire.burstCount == 0 then intra + def.fire.burstCooldown else intra
		end
	elseif def.fire.spinUp then
		local held = 0
		for _ = 2, shots do
			local interval = 60 / Weapons.currentRpm(def, held)
			held += interval
			total += interval
		end
	else
		total = (shots - 1) * 60 / def.fire.rpm
	end
	return shots, total
end

local function falloffText(def)
	local parts = {}
	for _, point in def.damage.falloff do
		table.insert(parts, ("%d→×%.2f"):format(point.range, point.multiplier))
	end
	return table.concat(parts, " ")
end

print("### Tableau 1 — Dégâts, cadence et TTK (bouclier plein, 15 studs)\n")
print(
	"| Arme | Catégorie | Mode | Cadence | Corps | Tête | Membre | Plombs | Chute de dégâts | Pénétration | Balles corps | TTK corps |"
)
print("|---|---|---|---|---|---|---|---|---|---|---|---|")
for _, id in Weapons.order do
	local def = Weapons.defs[id]
	if def.category ~= "Melee" then
		local body = Ballistics.damage(def.damage, "Body", 15, 1)
		local head = Ballistics.damage(def.damage, "Head", 15, 1)
		local limb = Ballistics.damage(def.damage, "Limb", 15, 1)
		local shots, time = ttk(def)
		local rpm = if def.fire.spinUp
			then ("%d→%d"):format(def.fire.spinUp.startRpm, def.fire.spinUp.endRpm)
			elseif def.fire.mode == "Burst" then ("%d×%d (%.2fs)"):format(
				def.fire.burstCount,
				def.fire.burstRpm,
				def.fire.burstCooldown
			)
			else tostring(def.fire.rpm)
		print(
			("| **%s** %s | %s | %s | %s | %d | %d | %d | %d | %s | %.1f | %d | %.3f s |"):format(
				def.shortName,
				def.codename,
				def.category,
				MODE_NAMES[def.fire.mode] or def.fire.mode,
				rpm,
				body,
				head,
				limb,
				def.damage.pellets,
				falloffText(def),
				def.damage.penetration,
				shots,
				time
			)
		)
	end
end

print("\n### Tableau 2 — Maniement, munitions, dispersion et recul\n")
print(
	"| Arme | Équiper | Visée (ADS) | Zoom | Viseur | Mobilité | Mob. ADS | Chargeur | Réserve | Recharg. | À vide | Disp. hanche | Disp. ADS | 1re balle | Bloom/tir | Recul 10 tirs (°) |"
)
print("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
for _, id in Weapons.order do
	local def = Weapons.defs[id]
	if def.category ~= "Melee" then
		local recoil = RecoilPatterns.total(def.recoil.pattern, 10)
		print(
			("| **%s** | %.2f s | %.2f s | ×%.2f | %s | %d %% | %d %% | %d | %d | %.2f s | %.2f s | %.2f° | %.2f° | ×%.2f | %.2f° | ↑%.1f ↔%.1f |"):format(
				def.shortName,
				def.handling.equipTime,
				def.handling.adsTime,
				def.handling.zoom,
				def.handling.sight,
				math.floor(def.handling.moveMultiplier * 100 + 0.5),
				math.floor(def.handling.moveMultiplier * def.handling.adsMoveMultiplier * 100 + 0.5),
				def.ammo.magazine,
				def.ammo.reserve,
				def.ammo.reloadTime,
				def.ammo.emptyReloadTime,
				def.spread.hip,
				def.spread.ads,
				def.spread.firstShotMultiplier,
				def.spread.bloomPerShot,
				recoil.Y,
				recoil.X
			)
		)
	end
end

print("\n### Tableau 3 — Identité de chaque arme\n")
print("| Arme | Rôle | Sensation recherchée |")
print("|---|---|---|")
for _, id in Weapons.order do
	local def = Weapons.defs[id]
	print(("| **%s** (%s) | %s | %s |"):format(def.displayName, def.slot, def.description, def.feel))
end
