--[[ Tests : verrou de session, plan des bases, mannequins. ]]

local SessionLock = req(Shared.Rules.SessionLock)
local BaseLayout = req(Shared.Rules.BaseLayout)
local Dummies = req(Shared.Assets.Dummies)
local Spec = req(Shared.Assets.Spec)
local Zones = req(Shared.Config.Zones)

T.describe("SessionLock", function()
	T.it("acquiert un profil neuf", function()
		local record, ok = SessionLock.acquire(nil, "job1", 1000, 120)
		T.eq(ok, true)
		T.eq(record.Lock.JobId, "job1")
	end)
	T.it("refuse si un autre serveur détient un verrou frais", function()
		local existing = { Data = { Level = 5 }, Lock = { JobId = "other", Time = 990 } }
		local record, ok = SessionLock.acquire(existing, "job1", 1000, 120)
		T.eq(ok, false)
		T.eq(record, nil)
	end)
	T.it("verrou périmé (serveur planté) : reprise autorisée, données conservées", function()
		local existing = { Data = { Level = 5 }, Lock = { JobId = "other", Time = 100 } }
		local record, ok = SessionLock.acquire(existing, "job1", 1000, 120)
		T.eq(ok, true)
		T.eq(record.Data.Level, 5)
		T.eq(record.Lock.JobId, "job1")
	end)
	T.it("notre propre verrou se rafraîchit", function()
		local existing = { Data = {}, Lock = { JobId = "job1", Time = 990 } }
		local _, ok = SessionLock.acquire(existing, "job1", 1000, 120)
		T.eq(ok, true)
	end)
	T.it("commit refusé si le verrou a été volé (jamais d'écrasement)", function()
		local stolen = { Data = { Level = 50 }, Lock = { JobId = "other", Time = 995 } }
		T.eq(SessionLock.commit(stolen, { Level = 1 }, "job1", 1000, 120, false), nil)
	end)
	T.it("commit : rafraîchit ou libère le verrou", function()
		local mine = { Data = { Level = 1 }, Lock = { JobId = "job1", Time = 900 } }
		local kept = SessionLock.commit(mine, { Level = 2 }, "job1", 1000, 120, false)
		T.eq(kept.Data.Level, 2)
		T.eq(kept.Lock.Time, 1000)
		local released = SessionLock.commit(mine, { Level = 3 }, "job1", 1001, 120, true)
		T.eq(released.Lock, nil)
		T.eq(released.Data.Level, 3)
	end)
end)

-- Séparation d'axes pour deux carrés orientés (même taille).
local function corners(cf, half)
	local out = {}
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			table.insert(out, cf:PointToWorldSpace(Vector3.new(sx * half, 0, sz * half)))
		end
	end
	return out
end

local function overlap(a, b, half)
	local ca, cb = corners(a, half), corners(b, half)
	local axes = { a.RightVector, a.LookVector, b.RightVector, b.LookVector }
	for _, axis in axes do
		local minA, maxA, minB, maxB = math.huge, -math.huge, math.huge, -math.huge
		for _, p in ca do
			local d = p:Dot(axis)
			minA, maxA = math.min(minA, d), math.max(maxA, d)
		end
		for _, p in cb do
			local d = p:Dot(axis)
			minB, maxB = math.min(minB, d), math.max(maxB, d)
		end
		if maxA < minB or maxB < minA then
			return false
		end
	end
	return true
end

T.describe("BaseLayout", function()
	local center = Vector3.new(0, 0, 0)
	T.it("aucune parcelle ne chevauche une autre (marge de 4 studs)", function()
		local half = BaseLayout.PlotSize / 2 + 2
		for i = 1, BaseLayout.Count do
			for j = i + 1, BaseLayout.Count do
				T.expect(
					not overlap(BaseLayout.plotCFrame(i, center), BaseLayout.plotCFrame(j, center), half),
					("%d/%d"):format(i, j)
				)
			end
		end
	end)
	T.it("l'entrée (-Z local) regarde le centre du village", function()
		for i = 1, BaseLayout.Count do
			local plot = BaseLayout.plotCFrame(i, center)
			local entrance = plot:PointToWorldSpace(Vector3.new(0, 0, -20))
			T.expect(entrance.Magnitude < plot.Position.Magnitude, "entrée plus proche du centre : " .. i)
		end
	end)
	T.it("emplacements : dans la parcelle, espacés, loin du mannequin, de l'établi et du spawn", function()
		local limit = BaseLayout.PlotSize / 2 - 3
		for i, a in BaseLayout.Slots do
			T.expect(math.abs(a.Position.X) <= limit and math.abs(a.Position.Z) <= limit, a.Id .. " hors parcelle")
			T.expect((a.Position - BaseLayout.Dummy).Magnitude >= 12, a.Id .. " trop près du mannequin")
			T.expect((a.Position - BaseLayout.Rack).Magnitude >= 8, a.Id .. " trop près de l'établi")
			T.expect((a.Position - BaseLayout.Spawn).Magnitude >= 8, a.Id .. " trop près du spawn")
			for j = i + 1, #BaseLayout.Slots do
				T.expect(
					(a.Position - BaseLayout.Slots[j].Position).Magnitude >= 8,
					a.Id .. "/" .. BaseLayout.Slots[j].Id
				)
			end
		end
	end)
	T.it("limite d'emplacements 6 / 12 selon le pass", function()
		T.eq(BaseLayout.slotLimit(false), 6)
		T.eq(BaseLayout.slotLimit(true), 12)
		T.eq(BaseLayout.isSlot("S7"), true)
		T.eq(BaseLayout.isSlot("S13"), false)
		T.eq(BaseLayout.slotIndex("S3"), 3)
	end)
end)

T.describe("Dummies", function()
	T.it("un mannequin par zone, gabarit et budget corrects", function()
		for _, zone in Zones.List do
			local specs = Dummies.build(zone)
			T.expect(#specs >= 12 and #specs <= 24, ("%s: %d pièces"):format(zone.Id, #specs))
			local _, max = Spec.bounds(specs)
			T.expect(max.Y > 7 and max.Y < 11, ("%s: hauteur %.1f"):format(zone.Id, max.Y))
		end
	end)
	T.it("le boss est une version agrandie du mannequin", function()
		local zone = Zones.List[1]
		local _, small = Spec.bounds(Dummies.build(zone))
		local _, big = Spec.bounds(Dummies.build(zone, 3))
		T.near(big.Y / small.Y, 3, 0.05)
	end)
end)

local ZoneLayout = req(Shared.Rules.ZoneLayout)

T.describe("ZoneLayout", function()
	T.it("10 zones, centres distincts, zoneAt retrouve chaque centre", function()
		for i = 1, Zones.Count do
			T.eq(ZoneLayout.zoneAt(ZoneLayout.center(i) + Vector3.new(0, 4, 5)), i)
		end
	end)
	T.it("les zones ne se chevauchent pas", function()
		for i = 1, Zones.Count do
			for j = i + 1, Zones.Count do
				local a, b = ZoneLayout.center(i), ZoneLayout.center(j)
				local flat = Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
				local gap = flat - ZoneLayout.radius(i) - ZoneLayout.radius(j)
				T.expect(gap > 60 or math.abs(a.Y - b.Y) > 150, ("%d/%d gap %.0f"):format(i, j, gap))
			end
		end
	end)
	T.it("les plans de bases tiennent dans le village", function()
		local BaseLayout = req(Shared.Rules.BaseLayout)
		T.expect(BaseLayout.Ring + BaseLayout.PlotSize * 0.75 < ZoneLayout.VillageRadius)
	end)
	T.it("mannequins et arène de boss à l'intérieur du sol de la zone, sans se chevaucher", function()
		for i = 1, Zones.Count do
			local center = ZoneLayout.center(i)
			local arena = ZoneLayout.bossArena(i)
			T.expect((arena - center).Magnitude < ZoneLayout.radius(i), "arène " .. i)
			for _, p in ZoneLayout.dummyPositions(i) do
				T.expect((p - center).Magnitude < ZoneLayout.radius(i) * 0.6, "mannequin " .. i)
				T.expect((p - arena).Magnitude > 40, "mannequin trop près de l'arène " .. i)
			end
		end
	end)
	T.it("spawn de zone : au-dessus du sol, regarde vers le centre", function()
		for i = 2, Zones.Count do
			local spawn = ZoneLayout.spawn(i)
			local toCenter = (ZoneLayout.center(i) - spawn.Position) * Vector3.new(1, 0, 1)
			T.expect(spawn.LookVector:Dot(toCenter.Unit) > 0.95, "orientation " .. i)
		end
	end)
	T.it("loin de tout : aucune zone", function()
		T.eq(ZoneLayout.zoneAt(Vector3.new(5000, 0, 5000)), nil)
	end)
end)
