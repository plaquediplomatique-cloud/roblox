--[[ Tests : profil (migrations, assainissement), quotidien, quêtes, succès, butin, ascension. ]]

local Profile = req(Shared.Rules.Profile)
local Daily = req(Shared.Rules.Daily)
local Quests = req(Shared.Rules.Quests)
local Achievements = req(Shared.Rules.Achievements)
local Loot = req(Shared.Rules.Loot)
local Ascension = req(Shared.Rules.Ascension)
local Leaderboards = req(Shared.Rules.Leaderboards)
local WeaponCatalog = req(Shared.Rules.WeaponCatalog)
local QuestConfig = req(Shared.Config.Quests)
local DailyConfig = req(Shared.Config.Daily)
local Game = req(Shared.Config.Game)

local NOW = 1_700_000_000

T.describe("Profile", function()
	T.it("profil par défaut jouable", function()
		local p = Profile.default(NOW)
		T.eq(p.Level, 1)
		T.eq(p.Equipped, "WoodenStick")
		T.eq(p.Weapons.WoodenStick, true)
		T.eq(p.Zones.Village, true)
		T.eq(p.Upgrades.Power, 0)
	end)
	T.it("données nil ou non-table => défaut", function()
		T.eq(Profile.load(nil, NOW).Level, 1)
		T.eq(Profile.load("corrompu", NOW).Level, 1)
		T.eq(Profile.load(42, NOW).Level, 1)
	end)
	T.it("assainit les nombres fous", function()
		local p = Profile.load({
			Level = 9999,
			XP = 0 / 0,
			Coins = -50,
			Stars = 1e9,
			Upgrades = { Power = 1e9, Speed = -5, Fake = 3 },
			Stats = { Hits = math.huge, Kills = "beaucoup" },
		}, NOW)
		T.eq(p.Level, Game.MaxLevel)
		T.eq(p.XP, 0)
		T.eq(p.Coins, 0)
		T.eq(p.Stars, Game.AscensionMaxStars)
		T.eq(p.Upgrades.Power, 100)
		T.eq(p.Upgrades.Speed, 0)
		T.eq(p.Upgrades.Fake, nil)
		T.expect(p.Stats.Hits < 1e19 and p.Stats.Hits == p.Stats.Hits)
		T.eq(p.Stats.Kills, 0)
	end)
	T.it("armes inconnues retirées, arme équipée non possédée corrigée", function()
		local p = Profile.load({ Weapons = { Fork = true, Ghost = true }, Equipped = "VoidBlade" }, NOW)
		T.eq(p.Weapons.Ghost, nil)
		T.eq(p.Weapons.Fork, true)
		T.eq(p.Equipped, "Fork")
	end)
	T.it("armes principales dues au niveau restaurées", function()
		local p = Profile.load({ Level = 5, Weapons = {} }, NOW)
		T.eq(p.Weapons.IronSword, nil) -- niveau 6
		T.eq(p.Weapons.KitchenKnife, true)
		local q = Profile.load({ Level = 30, Weapons = {} }, NOW)
		T.eq(q.Weapons.SunSpear, true)
	end)
	T.it("slots de base : seulement des objets possédés", function()
		local p = Profile.load({
			Base = { Owned = { Lamp = true, Ghost = true }, Slots = { S1 = "Lamp", S2 = "Statue", S3 = 7 } },
		}, NOW)
		T.eq(p.Base.Slots.S1, "Lamp")
		T.eq(p.Base.Slots.S2, nil)
		T.eq(p.Base.Slots.S3, nil)
	end)
	T.it("migrations appliquées dans l'ordre", function()
		local calls = {}
		local data = { Version = 0, Value = 1 }
		Profile.migrate(data, {
			[0] = function(d)
				table.insert(calls, 0)
				d.Value = d.Value + 10
			end,
			[1] = function(d)
				table.insert(calls, 1)
				d.Value = d.Value * 2
			end,
		}, 2)
		T.eq(data.Value, 22)
		T.eq(data.Version, 2)
		T.eq(table.concat(calls, ","), "0,1")
	end)
	T.it("reçus : idempotence et anneau borné", function()
		local p = Profile.default(NOW)
		T.eq(Profile.recordPurchase(p, "r1"), true)
		T.eq(Profile.recordPurchase(p, "r1"), false)
		for i = 1, 100 do
			Profile.recordPurchase(p, "x" .. i)
		end
		T.eq(#p.Purchases, 60)
		T.eq(Profile.recordPurchase(p, "x100"), false)
	end)
	T.it("sanitize est idempotent", function()
		local once = Profile.load({ Level = 40, Coins = 1234.9, Equipped = "Fork" }, NOW)
		local twice = Profile.load(once, NOW)
		T.eq(twice.Level, once.Level)
		T.eq(twice.Coins, once.Coins)
		T.eq(twice.Equipped, once.Equipped)
	end)
end)

T.describe("Daily", function()
	T.it("première réclamation immédiate : jour 1", function()
		local state = { Streak = 0, LastClaim = 0 }
		local day, reward = Daily.claim(state, NOW)
		T.eq(day, 1)
		T.expect(reward ~= nil)
		T.eq(state.Streak, 1)
	end)
	T.it("cooldown : pas de double réclamation", function()
		local state = { Streak = 1, LastClaim = NOW }
		T.eq(Daily.status(state, NOW + 3600).CanClaim, false)
		T.eq((Daily.claim(state, NOW + 3600)), nil)
		T.eq(state.Streak, 1)
	end)
	T.it("série continue le jour suivant, cycle de 7 jours", function()
		local state = { Streak = 0, LastClaim = 0 }
		local t = NOW
		for expected = 1, 7 do
			local day = Daily.claim(state, t)
			T.eq(day, expected)
			t += 24 * 3600
		end
		T.eq((Daily.claim(state, t)), 1) -- recommence
		T.eq(state.Streak, 8)
	end)
	T.it("série cassée après 48 h", function()
		local state = { Streak = 5, LastClaim = NOW }
		local status = Daily.status(state, NOW + 49 * 3600)
		T.eq(status.CanClaim, true)
		T.eq(status.Day, 1)
		T.eq(status.Broken, true)
	end)
	T.it("horloge qui recule : jamais de réclamation", function()
		local state = { Streak = 2, LastClaim = NOW }
		T.eq(Daily.status(state, NOW - 99999).CanClaim, false)
	end)
	T.it("7 récompenses définies", function()
		T.eq(#DailyConfig.Days, 7)
	end)
end)

T.describe("Quests", function()
	T.it("sélection déterministe, métriques distinctes", function()
		local a = Quests.pickDaily(1234, 19000, 3)
		local b = Quests.pickDaily(1234, 19000, 3)
		T.eq(table.concat(a, ","), table.concat(b, ","))
		T.eq(#a, 3)
		local metrics = {}
		for _, id in a do
			local metric = QuestConfig.ById[id].Metric
			T.expect(not metrics[metric], "métrique dupliquée")
			metrics[metric] = true
		end
	end)
	T.it("ensure : crée 3 quotidiennes + hebdos, puis ne change plus le même jour", function()
		local state = { Day = 0, Week = 0, Items = {} }
		T.eq(Quests.ensure(state, NOW, 7), true)
		T.eq(#state.Items, 3 + #QuestConfig.Weekly)
		T.eq(Quests.ensure(state, NOW + 3600, 7), false)
	end)
	T.it("changement de jour : quotidiennes renouvelées, hebdos conservées", function()
		local state = { Day = 0, Week = 0, Items = {} }
		Quests.ensure(state, NOW, 7)
		local weeklyId = QuestConfig.Weekly[1].Id
		for _, item in state.Items do
			if item.Id == weeklyId then
				item.Progress = 3
			end
		end
		-- lendemain, même semaine (le lundi suivant est à >= 1 jour ; on prend +1 jour et on vérifie la semaine)
		local sameWeek = Quests.weekNumber(NOW) == Quests.weekNumber(NOW + 86400)
		Quests.ensure(state, NOW + 86400, 7)
		if sameWeek then
			for _, item in state.Items do
				if item.Id == weeklyId then
					T.eq(item.Progress, 3)
				end
			end
		end
		T.eq(#state.Items, 3 + #QuestConfig.Weekly)
	end)
	T.it("progression, plafond, réclamation idempotente", function()
		local state = { Day = 0, Week = 0, Items = { { Id = "D_Hits_A", Progress = 0, Claimed = false } } }
		T.eq(#Quests.record(state, "Hits", 100), 0)
		T.eq(Quests.claim(state, "D_Hits_A"), nil) -- pas terminée
		local done = Quests.record(state, "Hits", 500)
		T.eq(done[1], "D_Hits_A")
		T.eq(state.Items[1].Progress, 150)
		T.expect(Quests.claim(state, "D_Hits_A") ~= nil)
		T.eq(Quests.claim(state, "D_Hits_A"), nil) -- déjà prise
	end)
	T.it("métrique 'max' (combo) retient le meilleur", function()
		local state = { Day = 0, Week = 0, Items = { { Id = "D_Combo_A", Progress = 0, Claimed = false } } }
		Quests.record(state, "Combo", 8)
		Quests.record(state, "Combo", 3)
		T.eq(state.Items[1].Progress, 8)
	end)
	T.it("semaine : démarre le lundi", function()
		-- 2023-11-13 (lundi) 00:00 UTC = 1699833600
		local monday = 1699833600
		T.eq(Quests.weekNumber(monday), Quests.weekNumber(monday + 6 * 86400))
		T.expect(Quests.weekNumber(monday) ~= Quests.weekNumber(monday - 1))
	end)
end)

T.describe("Achievements", function()
	T.it("évaluation + réclamation idempotente", function()
		local p = Profile.default(NOW)
		p.Stats.Hits = 1500
		p.Level = 12
		local fresh = Achievements.evaluate(p)
		local ids = {}
		for _, a in fresh do
			ids[a.Id] = true
		end
		T.eq(ids.Hits_100, true)
		T.eq(ids.Hits_1000, true)
		T.eq(ids.Level_10, true)
		T.eq(#Achievements.evaluate(p), 0) -- rien de neuf
		T.expect(Achievements.claim(p, "Hits_1000") ~= nil)
		T.eq(Achievements.claim(p, "Hits_1000"), nil)
		T.eq(Achievements.claim(p, "Hits_10000"), nil) -- non atteint
	end)
	T.it("les armes de récompense existent", function()
		for _, a in req(Shared.Config.Achievements).List do
			if a.Reward.Weapon then
				T.expect(WeaponCatalog.ById[a.Reward.Weapon] ~= nil, a.Id)
			end
			if a.Reward.Chest then
				T.expect(req(Shared.Config.Loot).ById[a.Reward.Chest] ~= nil, a.Id)
			end
		end
	end)
end)

T.describe("Loot", function()
	T.it("tirage déterministe pour un RNG donné", function()
		local a = Loot.rollChest("Golden", {}, 60, T.rng(5))
		local b = Loot.rollChest("Golden", {}, 60, T.rng(5))
		T.eq(a.Kind, b.Kind)
	end)
	T.it("jamais une arme possédée ni au-dessus du palier autorisé", function()
		for seed = 1, 300 do
			local drop = Loot.rollChest("Golden", { GildedFork = true }, 6, T.rng(seed))
			if drop.Kind == "Weapon" then
				T.expect(drop.WeaponId ~= "GildedFork")
				T.expect(WeaponCatalog.ById[drop.WeaponId].Tier <= 6)
			end
		end
	end)
	T.it("repli en pièces si rien d'éligible", function()
		local drop = Loot.rollChest("Bronze", {}, 0, T.rng(1))
		T.eq(drop.Kind, "Coins")
	end)
	T.it("pitié du boss : monte puis plafonne", function()
		T.expect(Loot.bossWeaponChance(5) > Loot.bossWeaponChance(0))
		T.eq(Loot.bossWeaponChance(10000), req(Shared.Config.Loot).BossWeaponPityCap)
	end)
	T.it("chaque zone a une arme de boss", function()
		for _, zone in req(Shared.Config.Zones).List do
			T.expect(Loot.bossWeapon(zone.Id) ~= nil, zone.Id)
		end
	end)
	T.it("distribution : les raretés hautes sont rares", function()
		local rng = T.rng(99)
		local counts = {}
		for _ = 1, 4000 do
			local r = Loot.pickWeighted({ Rare = 40, Epic = 40, Legendary = 17, Mythic = 3 }, rng)
			counts[r] = (counts[r] or 0) + 1
		end
		T.expect(counts.Mythic < counts.Legendary and counts.Legendary < counts.Epic + 400)
		T.near(counts.Mythic / 4000, 0.03, 0.015)
	end)
end)

T.describe("Ascension", function()
	T.it("refusée sous le niveau minimum, acceptée au niveau requis", function()
		local p = Profile.default(NOW)
		T.eq((Ascension.canAscend(p)), false)
		p.Level = Game.AscensionMinLevel
		T.eq((Ascension.canAscend(p)), true)
	end)
	T.it("réinitialise la voie principale, garde pièces/améliorations/armes de chasse", function()
		local p = Profile.load({
			Level = 110,
			Coins = 5000,
			Upgrades = { Power = 7 },
			Weapons = { VoidBlade = true },
			Equipped = "VoidBlade",
		}, NOW)
		T.eq(Ascension.apply(p), 1)
		T.eq(p.Level, 1)
		T.eq(p.XP, 0)
		T.eq(p.Stars, 1)
		T.eq(p.Coins, 5000)
		T.eq(p.Upgrades.Power, 7)
		T.eq(p.Weapons.VoidBlade, true)
		T.eq(p.Weapons.IronSword, nil)
		T.eq(p.Weapons.WoodenStick, true)
		T.eq(p.Equipped, "VoidBlade")
		T.eq(p.Stats.Ascensions, 1)
		T.eq(p.Collection.IronSword, true) -- la collection survit
	end)
end)

T.describe("Leaderboards", function()
	T.it("scores entiers sûrs", function()
		T.eq(Leaderboards.clampScore(0 / 0), 0)
		T.eq(Leaderboards.clampScore(-5), 0)
		T.expect(Leaderboards.clampScore(1e300) <= 9e15)
		T.eq(Leaderboards.clampScore(12.9), 12)
	end)
end)
