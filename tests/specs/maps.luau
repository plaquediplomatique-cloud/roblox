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
	return blueprint, kit.prims
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
		local blueprint, prims = build(name)
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
	end)
end

T.describe("Hub", function()
	local _, prims = build("Hub")
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
