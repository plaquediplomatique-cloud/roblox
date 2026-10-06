--[[ Tests : springs, rate limiter, validation réseau, codec de visée, réplication, profil, missions. ]]

local Spring = req(Shared.Util.Spring)
local RateLimiter = req(Shared.Util.RateLimiter)
local Guard = req(Shared.Util.Guard)
local LookCodec = req(Shared.Net.LookCodec)
local ReplicaPath = req(Shared.Replica.ReplicaPath)
local ProfileTemplate = req(Shared.Data.ProfileTemplate)
local Missions = req(Shared.Config.Missions)
local Progression = req(Shared.Config.Progression)
local Cosmetics = req(Shared.Config.Cosmetics)
local Weapons = req(Shared.Config.Weapons)

T.describe("Spring", function()
	T.it("converge vers la cible (critique, sans dépassement)", function()
		local spring = Spring.number(0, 20, 1)
		spring.target = 1
		local peak = 0
		for _ = 1, 120 do
			peak = math.max(peak, spring:step(1 / 60))
		end
		T.near(spring.position, 1, 1e-3, "convergence")
		T.expect(peak <= 1 + 1e-6, "pas d'overshoot " .. peak)
	end)
	T.it("sous-amorti : dépasse la cible", function()
		local spring = Spring.number(0, 20, 0.4)
		spring.target = 1
		local peak = 0
		for _ = 1, 60 do
			peak = math.max(peak, spring:step(1 / 60))
		end
		T.expect(peak > 1.05, "overshoot " .. peak)
	end)
	T.it("stable avec un énorme dt (hitch de 2 s)", function()
		local spring = Spring.number(0, 30, 0.5)
		spring.target = 10
		spring:step(2)
		T.expect(math.abs(spring.position - 10) < 1, "stable : " .. spring.position)
	end)
	T.it("indépendant du framerate", function()
		local a, b = Spring.number(0, 15, 0.7), Spring.number(0, 15, 0.7)
		a.target, b.target = 1, 1
		for _ = 1, 30 do
			a:step(1 / 30)
		end
		for _ = 1, 240 do
			b:step(1 / 240)
		end
		T.near(a.position, b.position, 1e-6, "30 vs 240 FPS")
	end)
	T.it("sur-amorti et vectoriel", function()
		local spring = Spring.vector(Vector3.zero, 10, 2)
		spring.target = Vector3.new(1, 2, 3)
		for _ = 1, 600 do
			spring:step(1 / 60)
		end
		T.expect((spring.position - Vector3.new(1, 2, 3)).Magnitude < 1e-2, "converge")
	end)
end)

T.describe("RateLimiter", function()
	T.it("rafale puis débit soutenu", function()
		local now = 0
		local limiter = RateLimiter.new(5, 2, function()
			return now
		end)
		local key = {}
		for _ = 1, 5 do
			T.expect(limiter:consume(key), "rafale")
		end
		T.expect(not limiter:consume(key), "seau vide")
		now = 1
		T.expect(limiter:consume(key) and limiter:consume(key), "2 jetons/s")
		T.expect(not limiter:consume(key), "pas 3")
	end)
end)

T.describe("Guard", function()
	local check = Guard.shape({
		w = Guard.string(8),
		a = Guard.unitVector(0.02),
		s = Guard.range(0, 45),
		n = Guard.integer(0, 1000),
		opt = Guard.optional(Guard.boolean),
	})
	local valid = { w = "vk12", a = Vector3.new(0, 0, -1), s = 1.5, n = 3 }
	T.it("accepte un paquet valide", function()
		T.expect(check(valid))
	end)
	T.it("rejette NaN, infini, champ inconnu, métatable, type faux", function()
		T.expect(not check({ w = "vk12", a = Vector3.new(0, 0, -1), s = 0 / 0, n = 3 }), "NaN")
		T.expect(not check({ w = "vk12", a = Vector3.new(0, 0, -1), s = math.huge, n = 3 }), "inf")
		T.expect(not check({ w = "vk12", a = Vector3.new(0, 0, -1), s = 1, n = 3, hack = true }), "extra")
		T.expect(not check(setmetatable(table.clone(valid), {})), "metatable")
		T.expect(not check({ w = 5, a = Vector3.new(0, 0, -1), s = 1, n = 3 }), "type")
		T.expect(not check({ w = "vk12", a = Vector3.new(0, 0, -5), s = 1, n = 3 }), "non unitaire")
		T.expect(not check({ w = "vk12", a = Vector3.new(0, 0, -1), s = 1, n = 2.5 }), "non entier")
		T.expect(not check("string"), "pas une table")
	end)
	T.it("tableaux et dictionnaires bornés", function()
		local array = Guard.array(Guard.number, 3)
		T.expect(array({ 1, 2, 3 }))
		T.expect(not array({ 1, 2, 3, 4 }), "trop long")
		T.expect(not array({ 1, nil, 3 } :: any), "trou")
		T.expect(Guard.hexColor("#3DE1FF") and not Guard.hexColor("3DE1FF"), "hex")
	end)
end)

T.describe("LookCodec", function()
	T.it("aller-retour local précis", function()
		local yaw, pitch = LookCodec.decodeLocal(LookCodec.encodeLocal(-2.5, 0.7))
		T.near(yaw, -2.5, 1e-3, "yaw")
		T.near(pitch, 0.7, 1e-3, "pitch")
	end)
	T.it("lot multi-joueurs", function()
		local entries = { { slot = 1, yaw = 0.1, pitch = -0.2 }, { slot = 7, yaw = 3.0, pitch = 1.2 } }
		local decoded = {}
		LookCodec.decodeBatch(LookCodec.encodeBatch(entries), function(slot, yaw, pitch)
			table.insert(decoded, { slot = slot, yaw = yaw, pitch = pitch })
		end)
		T.eq(#decoded, 2)
		T.eq(decoded[2].slot, 7)
		T.near(decoded[2].yaw, 3.0, 1e-3, "yaw")
	end)
	T.it("rejette les buffers malformés", function()
		T.eq((LookCodec.decodeLocal(buffer.create(3))), nil)
		T.eq((LookCodec.decodeLocal("nope")), nil)
	end)
end)

T.describe("ReplicaPath", function()
	T.it("set / insert / remove par chemin", function()
		local data = { players = {} }
		ReplicaPath.set(data, { "players", "42", "kills" }, 3)
		T.eq(data.players["42"].kills, 3)
		ReplicaPath.arrayInsert(data, { "history" }, "a")
		ReplicaPath.arrayInsert(data, { "history" }, "b")
		T.eq(ReplicaPath.arrayRemove(data, { "history" }, 1), "a")
		T.eq(data.history[1], "b")
		T.expect(ReplicaPath.isPrefix({ "players" }, { "players", "42" }), "préfixe")
	end)
end)

T.describe("Profil", function()
	T.it("réconcilie un vieux profil incomplet et corrompu", function()
		local old = { Version = 1, Level = 12, XP = 40, Settings = { Controls = "corrompu" }, Cosmetics = { Emotes = { "em_salute" } } }
		local data = ProfileTemplate.reconcile(ProfileTemplate.migrate(old))
		T.eq(data.Version, ProfileTemplate.VERSION)
		T.eq(data.Level, 12, "niveau conservé")
		T.eq(#data.Cosmetics.Emotes, 4, "migration emotes")
		T.eq(data.Settings.Controls.Sensitivity, 0.4, "réglages réparés")
		T.expect(data.Inventory["skin_default_vk12"], "inventaire de départ")
		T.eq(data.Loadout.Primary, "vk12")
	end)
	T.it("corrige un loadout invalide", function()
		local data = ProfileTemplate.new()
		data.Loadout.Primary = "p10"
		data = ProfileTemplate.reconcile(data)
		T.eq(data.Loadout.Primary, Weapons.DEFAULT_LOADOUT.Primary)
	end)
end)

T.describe("Progression & missions", function()
	T.it("XP multi-niveaux", function()
		local level, xp, gained = Progression.addXP(1, 0, 1500 + 1625 + 10)
		T.eq(level, 3)
		T.eq(xp, 10)
		T.eq(gained, 2)
	end)
	T.it("tirage des missions déterministe et sans doublon", function()
		local a = Missions.roll(Missions.daily, 3, 777)
		local b = Missions.roll(Missions.daily, 3, 777)
		T.eq(#a, 3)
		local seen = {}
		for index, def in a do
			T.eq(def.id, b[index].id, "déterministe")
			T.expect(not seen[def.id], "doublon")
			seen[def.id] = true
		end
	end)
	T.it("toutes les récompenses référencées existent", function()
		for level, itemId in Progression.levelRewards do
			T.expect(Cosmetics.get(itemId) ~= nil, "niveau " .. level .. " -> " .. itemId)
		end
		for tier, reward in Progression.passRewards do
			for _, itemId in { reward.free, reward.premium } do
				if itemId then
					T.expect(Cosmetics.get(itemId) ~= nil, "pass " .. tier .. " -> " .. itemId)
				end
			end
		end
	end)
	T.it("catalogue : 112 skins d'armes générés", function()
		local count = 0
		for _, item in Cosmetics.items do
			if item.kind == "WeaponSkin" then
				count += 1
			end
		end
		T.eq(count, 8 * #Weapons.order)
	end)
end)
