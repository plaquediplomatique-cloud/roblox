--!strict
--[[
	MONOLITH — carte POLYVALENTE : Duel 1v1, Wingman 2v2, Squad 3v3, Clash.
	Relais orbital : un monolithe noir de 44 studs bloque toute ligne de vue au centre.

	       x=-86        -54  -40         0          40   54        x=86
	z=76  ┌──────────────────────┬─────────────┬──────────────────────┐
	      │   (coque)            │ BRIDGE (DÉF)│            (coque)   │
	z=56  ├──────────── NORTH CONCOURSE ───────┴──────────────────────┤
	z=34  ├──door──┬───▓PYLON▓──┬─ balcon N (y=7) ─┬──▓PYLON▓──┬─door─┤
	      │ SITE A │  A CONN ══ WEST GATE  ■■■  EAST GATE ══ B CONN │SITE B│
	      │ ARRAY  │            │   RING  MONOLITH │            │RELAY │
	z=-34 ├──door──┴───▓PYLON▓──┴─ balcon S (y=7) ─┴──▓PYLON▓──┴─door─┤
	z=-56 ├──────────── SOUTH CONCOURSE ──────┬───────────────────────┤
	      │   (coque)            │ HANGAR (ATT)│            (coque)   │
	z=-76 └──────────────────────┴─────────────┴──────────────────────┘

	Modes (barrières "ModeBarrier" + spawns/sites filtrés par mode) :
	  * Duel     : les 4 portes de l'anneau sont scellées -> arène centrale 80×68
	               autour du monolithe, spawns dédiés est/ouest.
	  * Wingman / Clash2 : le site A est scellé -> carte 1 site, plus compacte.
	  * Squad / Clash3   : carte complète, deux sites.
]]

local MapKit = require(script.Parent.Parent.MapKit)
local dress = require(script.Parent.Parent.Dressing.Monolith)

type Kit = MapKit.Kit

local MAGENTA = Color3.fromRGB(220, 80, 255)
local CYAN = Color3.fromRGB(61, 225, 255)
local AMBER = Color3.fromRGB(255, 190, 70)
local VIOLET = Color3.fromRGB(150, 110, 255)

local function build(kit: Kit)
	kit:floor("Deck", -86, -76, 86, 76, "Hull", 0, 4)
	kit:bounds(-86, -76, 86, 76, 50)
	kit:wall("OuterS", -86, -76, 86, -76, 20, "Hull", 2)
	kit:wall("OuterN", -86, 76, 86, 76, 20, "Hull", 2)
	kit:wall("OuterW", -86, -76, -86, 76, 20, "Hull", 2)
	kit:wall("OuterE", 86, -76, 86, 76, 20, "Hull", 2)

	-- MONOLITHE + ANNEAU -----------------------------------------------------------------
	kit:floor("RingFloor", -40, -34, 40, 34, "FloorDark", 0.1, 0.2)
	kit:box("Monolith", -8, 0, -8, 8, 44, 8, "Monolith")
	kit:box("MonolithBase", -11, 0, -11, 11, 1, 11, "HullLight")
	kit:trim(-11, -11.2, 11, -11, 1.1, MAGENTA, 0.3)
	kit:trim(-11, 11, 11, 11.2, 1.1, MAGENTA, 0.3)
	kit:trim(-11.2, -11, -11, 11, 1.1, MAGENTA, 0.3)
	kit:trim(11, -11, 11.2, 11, 1.1, MAGENTA, 0.3)
	kit:light(0, 30, 0, MAGENTA, 2, 60, false)

	-- Murs de l'anneau avec portes (W/E/S/N)
	kit:wallDoor("RingWest", -40, -34, -40, 34, 16, -6, 6, 10, "HullLight", 1.4)
	kit:wallDoor("RingEast", 40, -34, 40, 34, 16, -6, 6, 10, "HullLight", 1.4)
	kit:wallDoor("RingSouth", -40, -34, 40, -34, 16, -8, 8, 10, "HullLight", 1.4)
	kit:wallDoor("RingNorth", -40, 34, 40, 34, 16, -8, 8, 10, "HullLight", 1.4)

	-- Balcons (y = 7) + rampes
	for _, sz in { 1, -1 } do
		local function Z(z: number): number
			return z * sz
		end
		kit:platform("Balcony", -30, Z(26), 30, Z(33.3), 7, "Grate", 1)
		kit:box("BalconyRail", -30, 7, Z(25.6), -10, 10.2, Z(26), "MetalDark")
		kit:box("BalconyRail", 10, 7, Z(25.6), 30, 10.2, Z(26), "MetalDark")
		kit:pillar(-20, Z(29.6), 1.4, 6, "MetalDark")
		kit:pillar(20, Z(29.6), 1.4, 6, "MetalDark")
		kit:ramp("BalconyRampW", -38, Z(26), -30, Z(33.3), 0, 7, "+X", "Grate")
		kit:ramp("BalconyRampE", 30, Z(26), 38, Z(33.3), 0, 7, "-X", "Grate")
		kit:trim(-30, Z(25.5), 30, Z(25.4), 6.8, VIOLET, 0.2)
		-- Couvertures de l'anneau
		kit:box("PylonCluster", -24, 0, Z(14), -20, 10, Z(18), "HullLight")
		kit:box("PylonCluster", 20, 0, Z(14), 24, 10, Z(18), "HullLight")
		kit:crate(-30, Z(6))
		kit:crate(30, Z(-6), 0, 4, "Crate", 25)
		kit:cover(-6, Z(18), 6, Z(20), 3.6, "HullLight")
		kit:crate(-14, Z(22), 0, 4, "Crate")
	end

	-- Volumes pleins entre anneau et sites (pylônes)
	for _, sx in { 1, -1 } do
		local function X(x: number): number
			return x * sx
		end
		kit:box("Pylon", X(-54), 0, -34, X(-40), 16, -6, "Hull")
		kit:box("Pylon", X(-54), 0, 6, X(-40), 16, 34, "Hull")
		kit:trim(X(-54), -6.2, X(-40), -6, 9, CYAN, 0.2)
		kit:trim(X(-54), 6, X(-40), 6.2, 9, CYAN, 0.2)
	end

	-- Connecteurs d'anneau vers les sites
	kit:floor("AConnFloor", -54, -6, -40, 6, "FloorMetal", 0.1, 0.2)
	kit:floor("BConnFloor", 40, -6, 54, 6, "FloorMetal", 0.1, 0.2)
	kit:ceiling(-54, -6, -40, 6, 12, "Hull")
	kit:ceiling(40, -6, 54, 6, 12, "Hull")

	-- SITE A — ARRAY (ouest) -------------------------------------------------------------
	kit:floor("AFloor", -86, -34, -54, 34, "FloorMetal", 0.1, 0.2)
	kit:wallDoor("AEast", -54, -34, -54, 34, 16, -5, 5, 10, "HullLight", 1.4)
	kit:wallDoor("ASouth", -86, -34, -54, -34, 16, -78, -66, 10, "HullLight", 1.4)
	kit:wallDoor("ANorth", -86, 34, -54, 34, 16, -78, -66, 10, "HullLight", 1.4)
	kit:box("ArrayDish", -76, 0, -6, -64, 6, 6, "MetalDark")
	kit:box("ArrayMast", -71.5, 6, -1.5, -68.5, 18, 1.5, "Metal")
	kit:trim(-76.1, -6, -63.9, 6, 4, CYAN, 0.3)
	kit:light(-70, 20, 0, CYAN, 2, 40, true)
	kit:crate(-80, -20)
	kit:crate(-80, -20, 4)
	kit:crate(-60, -24, 0, 4, "Crate", 15)
	kit:crate(-62, 22)
	kit:crate(-82, 18, 0, 4, "Crate", 30)
	kit:cover(-70, 14, -66, 18, 3.6, "HullLight")
	kit:cover(-70, -18, -66, -14, 3.6, "HullLight")
	kit:zone("SiteZone", "Site_A", -84, -1, -30, -56, 12, 30, { Site = "A", Modes = "Squad,Clash3" })
	kit:trim(-84, -30, -56, -29.6, 0.2, AMBER, 0.2)
	kit:trim(-84, 29.6, -56, 30, 0.2, AMBER, 0.2)
	kit:trim(-84, -30, -83.6, 30, 0.2, AMBER, 0.2)
	kit:trim(-56.4, -30, -56, 30, 0.2, AMBER, 0.2)
	kit:sign("A — ARRAY", -85, 12, 0, 16, 3, "+X", AMBER)

	-- SITE B — RELAY (est) ---------------------------------------------------------------
	kit:floor("BFloor", 54, -34, 86, 34, "FloorMetal", 0.1, 0.2)
	kit:wallDoor("BWest", 54, -34, 54, 34, 16, -5, 5, 10, "HullLight", 1.4)
	kit:wallDoor("BSouth", 54, -34, 86, -34, 16, 66, 78, 10, "HullLight", 1.4)
	kit:wallDoor("BNorth", 54, 34, 86, 34, 16, 66, 78, 10, "HullLight", 1.4)
	kit:box("RelayCore", 66, 0, -5, 74, 9, 5, "Monolith")
	kit:trim(65.9, -5, 66.1, 5, 6, MAGENTA, 0.3)
	kit:light(70, 14, 0, MAGENTA, 2, 40, true)
	kit:crate(80, 20)
	kit:crate(80, 20, 4)
	kit:crate(60, 24, 0, 4, "Crate", 20)
	kit:crate(62, -22)
	kit:crate(82, -18, 0, 4, "Crate", 10)
	kit:cover(66, 14, 70, 18, 3.6, "HullLight")
	kit:cover(66, -18, 70, -14, 3.6, "HullLight")
	kit:site("B", 56, -30, 84, 30)
	kit:sign("B — RELAY", 85, 12, 0, 16, 3, "-X", AMBER)

	-- CONCOURSES -------------------------------------------------------------------------
	for _, sz in { 1, -1 } do
		local function Z(z: number): number
			return z * sz
		end
		kit:floor("ConcourseFloor", -86, Z(34), 86, Z(56), "FloorTile", 0.1, 0.2)
		kit:ceiling(-86, Z(34), 86, Z(56), 16, "Hull")
		kit:cover(-46, Z(42), -42, Z(48), 3.6, "HullLight")
		kit:cover(42, Z(42), 46, Z(48), 3.6, "HullLight")
		kit:crate(-24, Z(44))
		kit:crate(24, Z(48), 0, 4, "Crate", 20)
		kit:crate(0, Z(40), 0, 4, "Crate")
		kit:box("Partition", -64, 0, Z(44), -58, 8, Z(46), "HullLight")
		kit:box("Partition", 58, 0, Z(44), 64, 8, Z(46), "HullLight")
		kit:panelLight(-60, Z(42), 60, Z(48), 15.9, Color3.fromRGB(210, 200, 255), 1.4)
		kit:trim(-86, Z(55.4), 86, Z(55.6), 4, VIOLET, 0.2)
		-- Coque pleine de part et d'autre des spawns
		kit:box("HullFill", -86, 0, Z(56), -24, 18, Z(76), "Hull")
		kit:box("HullFill", 24, 0, Z(56), 86, 18, Z(76), "Hull")
	end

	-- HANGAR (spawn attaque) / BRIDGE (spawn défense) -----------------------------------
	for _, info in
		{
			{ sz = -1, side = "Attack", name = "HANGAR" },
			{ sz = 1, side = "Defense", name = "BRIDGE" },
		}
	do
		local sz = info.sz
		local function Z(z: number): number
			return z * sz
		end
		kit:floor(info.name .. "Floor", -24, Z(56), 24, Z(76), "FloorMetal", 0.15, 0.3)
		kit:box(info.name .. "Wall1", -24, 0, Z(55.4), -20, 16, Z(56.6), "HullLight")
		kit:box(info.name .. "Wall2", -10, 0, Z(55.4), 10, 16, Z(56.6), "HullLight")
		kit:box(info.name .. "Wall3", 20, 0, Z(55.4), 24, 16, Z(56.6), "HullLight")
		kit:box(info.name .. "Lintel1", -20, 10, Z(55.4), -10, 16, Z(56.6), "HullLight")
		kit:box(info.name .. "Lintel2", 10, 10, Z(55.4), 20, 16, Z(56.6), "HullLight")
		kit:ceiling(-24, Z(56), 24, Z(76), 16, "Hull")
		kit:panelLight(-16, Z(62), 16, Z(72), 15.9, Color3.fromRGB(225, 225, 255), 2)
		for _, x in { -14, -5, 5, 14 } do
			kit:spawn(info.side, x, Z(68), x, 0)
		end
		kit:spawn(info.side, 0, Z(62), 0, 0)
		kit:barrier(info.side, -20, Z(55), -10, Z(57), 10)
		kit:barrier(info.side, 10, Z(55), 20, Z(57), 10)
		kit:sign(info.name, 0, 12, Z(75), 14, 3, if sz > 0 then "-Z" else "+Z", CYAN)
	end

	-- Spawns DUEL (dans l'anneau, de part et d'autre du monolithe)
	for _, z in { -4, 4 } do
		local west = kit:spawn("Attack", -34, z, 0, z)
		west.attributes.Modes = "Duel"
		local east = kit:spawn("Defense", 34, z, 0, z)
		east.attributes.Modes = "Duel"
	end

	-- Barrières de mode
	kit:modeBarrier({ "Duel" }, -40.8, -6, -39.2, 6, 10)
	kit:modeBarrier({ "Duel" }, 39.2, -6, 40.8, 6, 10)
	kit:modeBarrier({ "Duel" }, -8, -34.8, 8, -33.2, 10)
	kit:modeBarrier({ "Duel" }, -8, 33.2, 8, 34.8, 10)
	kit:modeBarrier({ "Wingman", "Clash2" }, -54.8, -5, -53.2, 5, 10)
	kit:modeBarrier({ "Wingman", "Clash2" }, -78, -34.8, -66, -33.2, 10)
	kit:modeBarrier({ "Wingman", "Clash2" }, -78, 33.2, -66, 34.8, 10)

	-- Callouts
	kit:callout("RING", -40, -34, 40, 34)
	kit:callout("MONOLITH", -11, -11, 11, 11)
	kit:callout("NORTH BALCONY", -38, 25, 38, 34, 6.5, 30)
	kit:callout("SOUTH BALCONY", -38, -34, 38, -25, 6.5, 30)
	kit:callout("A CONNECTOR", -54, -6, -40, 6)
	kit:callout("B CONNECTOR", 40, -6, 54, 6)
	kit:callout("A SITE", -86, -34, -54, 34)
	kit:callout("B SITE", 54, -34, 86, 34)
	kit:callout("SOUTH CONCOURSE", -86, -56, 86, -34)
	kit:callout("NORTH CONCOURSE", -86, 34, 86, 56)
	kit:callout("HANGAR", -24, -76, 24, -56)
	kit:callout("BRIDGE", -24, 56, 24, 76)

	-- Habillage (décor non bloquant) : Maps/Dressing/Monolith
	dress(kit)
end

return {
	id = "monolith",
	build = build,
	intro = {
		CFrame.lookAt(Vector3.new(0, 70, -70), Vector3.new(0, 30, 0)),
		CFrame.lookAt(Vector3.new(-30, 20, -20), Vector3.new(0, 30, 0)),
		CFrame.lookAt(Vector3.new(-60, 14, -20), Vector3.new(-70, 6, 0)),
		CFrame.lookAt(Vector3.new(36, 12, 10), Vector3.new(70, 5, 0)),
	},
	overview = CFrame.lookAt(Vector3.new(0, 170, -60), Vector3.new(0, 0, 0)),
}
