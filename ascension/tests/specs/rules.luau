--[[ Tests : formatage, courbes, catalogue d'armes, améliorations, combat, économie. ]]

local NumberFormat = req(Shared.Rules.NumberFormat)
local Curves = req(Shared.Rules.Curves)
local WeaponCatalog = req(Shared.Rules.WeaponCatalog)
local Upgrades = req(Shared.Rules.Upgrades)
local Combat = req(Shared.Rules.Combat)
local Economy = req(Shared.Rules.Economy)
local Progress = req(Shared.Rules.Progress)
local Game = req(Shared.Config.Game)
local Zones = req(Shared.Config.Zones)

local function fighterFor(weaponId, overrides)
	local weapon = WeaponCatalog.ById[weaponId]
	local fighter = {
		Damage = weapon.Damage,
		AttackSpeed = weapon.AttackSpeed,
		PowerLevel = 0,
		SpeedLevel = 0,
		CritChanceLevel = 0,
		CritDamageLevel = 0,
		Stars = 0,
		Special = weapon.Special,
	}
	for key, value in overrides or {} do
		fighter[key] = value
	end
	return fighter
end

T.describe("NumberFormat", function()
	T.it("nombres compacts", function()
		T.eq(NumberFormat.compact(0), "0")
		T.eq(NumberFormat.compact(999), "999")
		T.eq(NumberFormat.compact(1234), "1.23K")
		T.eq(NumberFormat.compact(1500000), "1.5M")
		T.eq(NumberFormat.compact(999999), "1M")
		T.eq(NumberFormat.compact(2.5e15), "2.5Qa")
		T.eq(NumberFormat.compact(-1500), "-1.5K")
	end)
	T.it("durées et pourcentages", function()
		T.eq(NumberFormat.duration(9), "9s")
		T.eq(NumberFormat.duration(75), "1m 15s")
		T.eq(NumberFormat.duration(3725), "1h 02m")
		T.eq(NumberFormat.percent(0.153), "15.3%")
		T.eq(NumberFormat.percent(0.5), "50%")
	end)
	T.it("NaN et infini ne cassent pas l'affichage", function()
		T.eq(NumberFormat.compact(0 / 0), "0")
		T.expect(type(NumberFormat.compact(math.huge)) == "string")
	end)
end)

T.describe("Curves", function()
	T.it("dégâts d'armes : début lisible et strictement croissants", function()
		T.eq(Curves.weaponDamage(1), 1)
		T.eq(Curves.weaponDamage(2), 2)
		T.eq(Curves.weaponDamage(3), 4)
		for tier = 2, 70 do
			T.expect(Curves.weaponDamage(tier) > Curves.weaponDamage(tier - 1), "tier " .. tier)
		end
	end)
	T.it("XP : niveaux de départ rapides puis croissance exponentielle", function()
		T.expect(Curves.xpToNext(1) <= 10)
		for level = 2, Game.MaxLevel do
			T.expect(Curves.xpToNext(level) > Curves.xpToNext(level - 1), "level " .. level)
		end
	end)
	T.it("zone d'un niveau", function()
		T.eq(Curves.zoneOfLevel(1), 1)
		T.eq(Curves.zoneOfLevel(13), 2)
		T.eq(Curves.zoneOfLevel(120), 10)
	end)
	T.it("PV d'un mannequin = N coups de la première arme de la zone", function()
		for zone = 1, Zones.Count do
			local first = WeaponCatalog.Main[(zone - 1) * Zones.WeaponsPerZone + 1]
			T.eq(Curves.dummyHP(zone) / first.Damage, Game.DummyHitsToKillAtZoneStart)
		end
	end)
end)

T.describe("WeaponCatalog", function()
	T.it("catalogue cohérent (aucune erreur de validation)", function()
		local errors = WeaponCatalog.validate()
		T.eq(#errors, 0, table.concat(errors, "; "))
	end)
	T.it("60 armes principales + armes de chasse", function()
		T.eq(#WeaponCatalog.Main, 60)
		T.expect(#WeaponCatalog.Hunted >= 20)
		T.eq(WeaponCatalog.StarterId, "WoodenStick")
	end)
	T.it("progression de départ : bâton niv.1, bâton renforcé niv.2, fourchette niv.3, couteau niv.4", function()
		T.eq(WeaponCatalog.Main[1].Level, 1)
		T.eq(WeaponCatalog.Main[2].Level, 2)
		T.eq(WeaponCatalog.Main[3].Level, 3)
		T.eq(WeaponCatalog.Main[4].Level, 4)
		T.eq(WeaponCatalog.Main[1].Damage, 1)
	end)
	T.it("chaque zone débloque ses armes avant le niveau de la zone suivante", function()
		for zone = 1, Zones.Count - 1 do
			local lastOfZone = WeaponCatalog.Main[zone * Zones.WeaponsPerZone]
			T.expect(lastOfZone.Level < Zones.List[zone + 1].MinLevel, "zone " .. zone)
		end
	end)
	T.it("armes de chasse : plus rares que la voie principale équivalente", function()
		local void = WeaponCatalog.ById.VoidBlade
		T.eq(void.Rarity.Id, "Secret")
		T.expect(not void.Main)
	end)
	T.it("bestOwned choisit les dégâts max", function()
		local best = WeaponCatalog.bestOwned({ WoodenStick = true, Fork = true, KitchenKnife = true })
		T.eq(best.Id, "KitchenKnife")
	end)
end)

T.describe("Upgrades", function()
	T.it("coût croissant, nil au maximum", function()
		local c0 = Upgrades.cost("Power", 0) :: number
		local c1 = Upgrades.cost("Power", 1) :: number
		T.expect(c1 > c0)
		T.eq(Upgrades.cost("Power", Upgrades.maxLevel("Power")), nil)
	end)
	T.it("effet additif plafonné", function()
		T.near(Upgrades.effect("Power", 10), 1.0, 1e-9)
		T.near(Upgrades.effect("Power", 9999), Upgrades.maxLevel("Power") * 0.1, 1e-9)
	end)
	T.it("achat refusé sans pièces / inconnu", function()
		T.eq(Upgrades.check("Power", 0, 0).Ok, false)
		T.eq(Upgrades.check("Nope", 0, 1e9).Ok, false)
		T.eq(Upgrades.check("Power", 0, 1e9).Ok, true)
	end)
end)

T.describe("Combat", function()
	T.it("combo : monte, plafonne, décroît après la fenêtre", function()
		local state = { Count = 0, LastHit = 0 }
		local window = Game.ComboWindow
		for i = 1, 5 do
			Combat.comboHit(state, i * 0.5, window)
		end
		T.eq(state.Count, 5)
		T.eq(Combat.comboAt(state, 2.5 + window - 0.1, window), 5)
		T.expect(Combat.comboAt(state, 2.5 + window + 1.5, window) < 5)
		T.eq(Combat.comboAt(state, 1000, window), 0)
		for i = 1, 300 do
			Combat.comboHit(state, 1000 + i * 0.2, window)
		end
		T.eq(state.Count, Game.ComboMax)
	end)
	T.it("multiplicateur de combo x1 -> x2", function()
		T.eq(Combat.comboMultiplier(0), 1)
		T.near(Combat.comboMultiplier(100), 2, 1e-9)
		T.near(Combat.comboMultiplier(1000), 2, 1e-9)
	end)
	T.it("cadence : plus rapide avec Speed, jamais sous l'intervalle minimum", function()
		local slow = Combat.swingInterval(fighterFor("WoodenStick"))
		local fast = Combat.swingInterval(fighterFor("WoodenStick", { SpeedLevel = 40 }))
		T.expect(fast < slow)
		local insane = Combat.swingInterval(fighterFor("WoodenStick", { AttackSpeed = 1000, SpeedLevel = 40 }))
		T.near(insane, Game.MinSwingInterval, 1e-9)
	end)
	T.it("dégâts de base : arme x puissance x étoiles", function()
		local base = Combat.baseDamage(fighterFor("IronSword"))
		local boosted = Combat.baseDamage(fighterFor("IronSword", { PowerLevel = 10, Stars = 2 }))
		T.near(boosted, base * 2 * 1.5, 1e-6)
	end)
	T.it("coup normal sans critique", function()
		local hit = Combat.resolveHit({
			Fighter = fighterFor("WoodenStick"),
			Combo = 0,
			HitIndex = 1,
			TargetHP = 100,
			TargetMaxHP = 100,
		}, function()
			return 0.99
		end)
		T.eq(hit.Crit, 0)
		T.eq(hit.Damage, 1)
	end)
	T.it("critique et méga critique", function()
		local input = {
			Fighter = fighterFor("Fork"),
			Combo = 0,
			HitIndex = 1,
			TargetHP = 100,
			TargetMaxHP = 100,
		}
		local crit = Combat.resolveHit(input, T.script({ 0.0, 0.99 }))
		T.eq(crit.Crit, 1)
		local mega = Combat.resolveHit(input, T.script({ 0.0, 0.0 }))
		T.eq(mega.Crit, 2)
		T.expect(mega.Damage > crit.Damage)
	end)
	T.it("spéciaux : Surge (n-ième coup), Executioner (PV bas), Cleave (double)", function()
		local function hit(weaponId, hitIndex, hp, roll)
			return Combat.resolveHit({
				Fighter = fighterFor(weaponId),
				Combo = 0,
				HitIndex = hitIndex,
				TargetHP = hp,
				TargetMaxHP = 100,
			}, function()
				return roll
			end)
		end
		T.eq(hit("BlizzardGreatsword", 5, 100, 0.99).Surge, true)
		T.eq(hit("BlizzardGreatsword", 4, 100, 0.99).Surge, false)
		T.expect(hit("GlacierHammer", 1, 20, 0.99).Damage > hit("GlacierHammer", 1, 90, 0.99).Damage)
		T.eq(hit("MirageBlades", 1, 100, 0.0).Double, true)
		T.eq(hit("MirageBlades", 1, 100, 0.99).Double, false)
	end)
	T.it("chance de critique plafonnée", function()
		T.expect(Combat.critChance(fighterFor("Fork", { CritChanceLevel = 9999 })) <= Game.CritChanceCap)
	end)
	T.it("Power (classement) croît avec l'arme", function()
		local a = Combat.powerRating(fighterFor("WoodenStick"))
		local b = Combat.powerRating(fighterFor("KitchenKnife"))
		T.expect(b > a)
	end)
end)

T.describe("Economy / Progress", function()
	local ctx = {
		WeaponXPBoost = 1,
		XPUpgradeLevel = 0,
		FortuneLevel = 0,
		Stars = 0,
		Combo = 0,
		PassXP = false,
		BoostXP = false,
		PassCoins = false,
		SpecialXP = 0,
		SpecialCoins = 0,
	}
	T.it("le plafond d'XP payante empêche l'empilement infini", function()
		T.eq(Economy.paidXPMultiplier(false, false), 1)
		T.eq(Economy.paidXPMultiplier(true, false), 2)
		T.eq(Economy.paidXPMultiplier(true, true), 3)
		T.expect(Economy.paidXPMultiplier(true, true) <= Game.PaidXPMultiplierCap)
	end)
	T.it("XP d'un coup proportionnelle aux dégâts, bornée par les PV", function()
		local half = Economy.hitXP(1, 5, 10, ctx)
		local full = Economy.hitXP(1, 10, 10, ctx)
		local over = Economy.hitXP(1, 1000, 10, ctx)
		T.near(half * 2, full, 1e-9)
		T.near(over, full, 1e-9)
	end)
	T.it("addXP : multi-niveaux, plafond, jamais d'XP négative", function()
		local r = Progress.addXP(1, 0, 8)
		T.eq(r.Level, 2)
		T.eq(r.LevelsGained, 1)
		local big = Progress.addXP(1, 0, 1e30)
		T.eq(big.Level, Game.MaxLevel)
		T.eq(big.XP, 0)
		local none = Progress.addXP(5, 3, -50)
		T.eq(none.Level, 5)
		T.eq(none.XP, 3)
		local nan = Progress.addXP(5, 3, 0 / 0)
		T.eq(nan.Level, 5)
	end)
	T.it("récompenses en minutes de revenu croissent avec la zone", function()
		T.expect(Economy.minutesToCoins(5, 5) > Economy.minutesToCoins(5, 1))
	end)
end)
