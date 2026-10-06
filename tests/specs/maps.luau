--[[
	Tests de level design (hors moteur) : chaque blueprint est construit avec MapKit et
	vérifié contre les règles de la philosophie de level design (docs/05) :
	  * spawns des deux côtés (≥ taille d'équipe max de ses modes),
	  * sites conformes aux métadonnées de la carte,
	  * AUCUNE ligne de vue entre spawns adverses (raycast sur les OBB de la géométrie),
	  * callouts présents et nommés,
	  * limites de carte présentes.
]]

local MapKit = req(ServerMaps.MapKit)
local Maps = req(Shared.Config.Maps)
local GameModes = req(Shared.Config.GameModes)
local MathUtil = req(Shared.Util.MathUtil)

local blueprintsNode = ServerMaps.Blueprints

local function build(name)
	local blueprint = req(blueprintsNode[name])
	local kit = MapKit.new()
	blueprint.build(kit)
	return blueprint, kit.prims, kit.limits
end

-- Boîte englobante monde (axes alignés) d'une primitive orientée.
local function aabb(prim)
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	local half = prim.size * 0.5
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local corner = prim.cframe * Vector3.new(sx * half.X, sy * half.Y, sz * half.Z)
				lo = Vector3.new(math.min(lo.X, corner.X), math.min(lo.Y, corner.Y), math.min(lo.Z, corner.Z))
				hi = Vector3.new(math.max(hi.X, corner.X), math.max(hi.Y, corner.Y), math.max(hi.Z, corner.Z))
			end
		end
	end
	return lo, hi
end

local function outside(lo, hi, limits)
	return hi.X <= limits.x1 + 0.01 or lo.X >= limits.x2 - 0.01 or hi.Z <= limits.z1 + 0.01 or lo.Z >= limits.z2 - 0.01
end

--[[
	Règles d'habillage (src/Server/Maps/Decor.luau) : le décor ne bloque rien, ne crée
	aucune fausse couverture, et les volumes massifs restent hors des limites.
]]
local function decorRules(prims, limits)
	T.it("le décor ne bloque ni les déplacements ni les tirs", function()
		for _, prim in prims do
			if prim.group == "Decor" or prim.group == "Backdrop" then
				T.expect(not prim.collide and not prim.query, prim.name .. " : collision ou requête active")
			end
		end
	end)
	T.it("décor fin ou en hauteur dans l'espace de jeu, horizon hors limites", function()
		T.expect(limits ~= nil, "limites de carte (kit:bounds) absentes")
		for _, prim in prims do
			local lo, hi = aabb(prim)
			local thin = math.min(prim.size.X, prim.size.Y, prim.size.Z) <= 1.0
			if prim.group == "Decor" then
				T.expect(
					thin or lo.Y >= 12 or outside(lo, hi, limits),
					("%s (%.1f×%.1f×%.1f à y=%.1f) : ni fin, ni en hauteur"):format(
						prim.name,
						prim.size.X,
						prim.size.Y,
						prim.size.Z,
						lo.Y
					)
				)
			elseif prim.group == "Backdrop" then
				T.expect(
					outside(lo, hi, limits) or hi.Y <= -3.9,
					("%s : élément d'horizon dans les limites (%s)"):format(prim.name, tostring(prim.cframe.Position))
				)
			end
		end
	end)
	T.it("budget de scène (parts, lumières, ombres)", function()
		local lights, shadowed = 0, 0
		for _, prim in prims do
			if prim.light then
				lights += 1
				if prim.light.shadows then
					shadowed += 1
				end
			end
		end
		T.expect(#prims <= 6000, "primitives : " .. #prims)
		T.expect(lights <= 90, "lumières : " .. lights)
		T.expect(shadowed <= 10, "lumières à ombres : " .. shadowed)
	end)
end

local function hasTag(prim, tag)
	return table.find(prim.tags, tag) ~= nil
end

local function blocks(prim)
	return prim.collide and prim.transparency < 0.95 and prim.group ~= "Markers" and prim.material ~= "ForceField"
end

local function lineClear(prims, a, b)
	local offset = b - a
	local distance = offset.Magnitude
	local direction = offset.Unit
	for _, prim in prims do
		if blocks(prim) then
			local t = MathUtil.rayOBB(a, direction, prim.cframe, prim.size * 0.5, distance)
			if t and t > 0.5 and t < distance - 0.5 then
				return false
			end
		end
	end
	return true
end

for _, name in { "Kestrel", "Helix", "Spire", "Monolith" } do
	T.describe("Carte " .. name, function()
		local blueprint, prims, limits = build(name)
		local info = Maps.get(blueprint.id)
		local spawns = { Attack = {}, Defense = {} }
		local sites, callouts, bounds = {}, 0, 0
		for _, prim in prims do
			if hasTag(prim, "SpawnPoint") and prim.attributes.Modes == nil then
				table.insert(spawns[prim.attributes.Side], prim.cframe.Position)
			elseif hasTag(prim, "SiteZone") then
				sites[prim.attributes.Site] = true
			elseif hasTag(prim, "CalloutZone") then
				callouts += 1
			elseif prim.name == "Boundary" then
				bounds += 1
			end
		end

		T.it("métadonnées présentes", function()
			T.expect(info ~= nil, "Maps.defs." .. blueprint.id)
		end)
		T.it("spawns suffisants des deux côtés", function()
			local needed = 1
			for _, modeId in info.modes do
				needed = math.max(needed, GameModes.defs[modeId].teamSize)
			end
			T.expect(#spawns.Attack >= needed, "attaque : " .. #spawns.Attack)
			T.expect(#spawns.Defense >= needed, "défense : " .. #spawns.Defense)
		end)
		T.it("sites conformes", function()
			for _, site in info.sites do
				T.expect(sites[site], "site manquant " .. site)
			end
		end)
		T.it("au moins 8 callouts et des limites", function()
			T.expect(callouts >= 8, "callouts : " .. callouts)
			T.eq(bounds, 4, "murs de limite")
		end)
		T.it("aucune ligne de vue entre spawns adverses", function()
			for _, a in spawns.Attack do
				for _, d in spawns.Defense do
					local eyeA = a + Vector3.new(0, 1.7, 0)
					local eyeD = d + Vector3.new(0, 1.7, 0)
					T.expect(not lineClear(prims, eyeA, eyeD), ("LOS %s <-> %s"):format(tostring(a), tostring(d)))
				end
			end
		end)
		decorRules(prims, limits)
	end)
end

T.describe("Hub", function()
	local _, prims, limits = build("Hub")
	decorRules(prims, limits)
	local terminals, pedestals, training = {}, 0, false
	for _, prim in prims do
		if hasTag(prim, "HubTerminal") then
			terminals[prim.attributes.Action] = true
		elseif hasTag(prim, "WeaponPedestal") then
			pedestals += 1
		elseif hasTag(prim, "TrainingZone") then
			training = true
		end
	end
	T.it("tous les terminaux de zone existent", function()
		for _, action in
			{
				"Play",
				"Ranked",
				"Casual",
				"Custom",
				"Armory",
				"Training",
				"Leaderboard",
				"Missions",
				"Pass",
				"Settings",
			}
		do
			T.expect(terminals[action], "terminal " .. action)
		end
	end)
	T.it("une vitrine par arme et une zone d'entraînement", function()
		T.eq(pedestals, 14, "vitrines")
		T.expect(training, "TrainingZone")
	end)
end)

T.describe("Environnement des cartes (ciel, météo, ambiance)", function()
	local Sounds = req(Shared.Config.Sounds)
	local kinds = { None = true, Rain = true, Snow = true, Motes = true, Embers = true }
	for id, info in Maps.defs do
		T.it(id .. " : météo, réverbérations et sons ponctuels valides", function()
			T.expect(kinds[info.weather.kind], "météo inconnue " .. tostring(info.weather.kind))
			T.expect(info.weather.intensity >= 0 and info.weather.intensity <= 1, "intensité hors [0, 1]")
			for _, name in { info.ambience.outdoorReverb, info.ambience.indoorReverb } do
				local ok = pcall(function()
					return Enum.ReverbType[name]
				end)
				T.expect(ok, "réverbération inconnue " .. name)
			end
			for _, spot in info.ambience.spots do
				T.expect(Sounds.get(spot.key) ~= nil, "son inconnu " .. spot.key)
				T.expect(spot.interval.Min > 0 and spot.interval.Max >= spot.interval.Min, "intervalle " .. spot.key)
				T.expect(spot.distance.Max >= spot.distance.Min, "distance " .. spot.key)
			end
			T.expect(Sounds.get(info.ambientSound) ~= nil, "boucle d'ambiance inconnue " .. info.ambientSound)
		end)
		T.it(id .. " : profil d'éclairage complet", function()
			local p = info.lighting
			T.expect(p.shadowSoftness >= 0 and p.shadowSoftness <= 1, "ShadowSoftness")
			T.expect(p.sky.stars >= 0 and p.sky.stars <= 5000, "StarCount")
			if p.clouds then
				T.expect(p.clouds.cover >= 0 and p.clouds.cover <= 1, "Clouds.Cover")
				T.expect(p.clouds.density >= 0 and p.clouds.density <= 1, "Clouds.Density")
			end
			T.expect(p.atmosphere.density <= 0.5, "Atmosphere.Density > 0.5 : purée de pois")
		end)
	end
end)
