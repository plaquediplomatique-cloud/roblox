--!strict
--[[
	SPIRE-9 — Squad 3v3 (sites A et B) / Clash 3v3. Complexe scientifique sur falaise.

	      x=-100            -30      0      30             x=100
	z=86  ┌──────────────────────┬────────┬──────────────────────┐
	      │                      │COMMAND │ (DÉF., y=5)          │
	z=64  │  ╔═ramp══ BACK ROAD (y=5) ═════════════ramp═╗        │
	z=56  │A-N    ║  ▓▓▓  ║  TERRACE (y=5, high ground) ║  ▓▓ B-N │
	      │ A REACTOR (ext.)║▓▓▓▓▓▓▓║ rampes ↓ ↓ ║▓▓▓║ B DATACORE (int.)│
	z=4   │ ↑A LONG   ║A LINK═══ PLAZA [SPIRE] ═══B LINK║ B TUNNEL↑│
	z=-24 │ │ (falaise)║▓▓▓▓▓▓║──CHOKE──║▓▓▓▓▓▓▓▓║ │ (CQB)   │
	      │ │ ═══A ALLEY═══  COURTYARD  ═══B ALLEY═══ │         │
	z=-70 │ └── A ENTRY ──┤ CABLE STATION ├── B ENTRY ──┘         │
	z=-86 └──────────────────────────────────────────────────────┘

	Philosophie :
	  * 3 routes d'attaque de natures différentes : A LONG (ouvert, longues lignes,
	    snipers), MID (plaza + liens, choix tardif du site), B TUNNEL (couloir CQB,
	    SMG/fusil à pompe).
	  * La défense arrive en ~5 s sur chaque site via la BACK ROAD surélevée, et tient
	    la TERRASSE qui domine la plaza : le mid se paie cher, mais il donne les deux sites.
	  * Toutes les zones mortes sont des volumes pleins : aucune cachette exploitable.
]]

local MapKit = require(script.Parent.Parent.MapKit)
local dress = require(script.Parent.Parent.Dressing.Spire)

type Kit = MapKit.Kit

local DUSK = Color3.fromRGB(255, 190, 150)
local CYAN = Color3.fromRGB(61, 225, 255)
local AMBER = Color3.fromRGB(255, 190, 70)
local REACTOR = Color3.fromRGB(120, 255, 210)

local function build(kit: Kit)
	kit:floor("Ground", -100, -86, 100, 86, "Rock", 0, 4)
	kit:floor("SnowCover", -100, -86, -64, 4, "Snow", 0.05, 0.1)
	kit:bounds(-100, -86, 100, 86, 50)

	-- Enveloppe
	kit:wall("OuterS", -100, -86, 100, -86, 18, "WallDark", 2)
	kit:wall("OuterN", -100, 86, 100, 86, 18, "WallDark", 2)
	kit:wall("OuterE", 100, -86, 100, 86, 18, "WallDark", 2)
	kit:wall("CliffRail", -100, -86, -100, 86, 3.2, "MetalDark", 1)

	-- Volumes pleins (bâtiments) : aucune zone morte accessible
	kit:box("HydroPlantS", -64, 0, -72, -30, 14, -50, "Wall")
	kit:box("HydroPlantN", -64, 0, -40, -30, 14, 4, "Wall")
	kit:box("ALinkNorthBlock", -46, 0, 18, -30, 14, 56, "Wall")
	kit:box("LabS", 30, 0, -72, 60, 14, -50, "Wall")
	kit:box("LabN", 30, 0, -40, 60, 14, 4, "Wall")
	kit:box("BLinkNorthBlock", 30, 0, 18, 46, 14, 56, "Wall")
	kit:box("EastRock", 76, 0, -86, 100, 16, 4, "Rock")
	kit:box("CommandWest", -100, 0, 64, -16, 16, 86, "Rock")
	kit:box("CommandEast", 16, 0, 64, 100, 16, 86, "Rock")
	kit:trim(-64, -50.4, -30, -50.2, 10, CYAN)
	kit:trim(30, -50.4, 60, -50.2, 10, CYAN)

	-- CABLE STATION (spawn attaque) --------------------------------------------------------
	kit:floor("StationFloor", -22, -86, 22, -70, "FloorMetal", 0.15, 0.3)
	kit:wallDoor("StationNorth", -22, -70, 22, -70, 14, -8, 8, 10, "WallPanel", 1.4)
	kit:wallDoor("StationWest", -22, -86, -22, -70, 14, -84, -74, 10, "WallPanel", 1.4)
	kit:wallDoor("StationEast", 22, -86, 22, -70, 14, -84, -74, 10, "WallPanel", 1.4)
	kit:ceiling(-22, -86, 22, -70, 14, "MetalDark")
	kit:panelLight(-14, -84, 14, -74, 13.9, Color3.fromRGB(230, 236, 255), 2)
	for _, x in { -12, -4, 4, 12 } do
		kit:spawn("Attack", x, -80, x, 0)
	end
	kit:spawn("Attack", -16, -76, -40, -60)
	kit:spawn("Attack", 16, -76, 40, -60)
	kit:barrier("Attack", -8, -71, 8, -69, 10)
	kit:barrier("Attack", -23, -84, -21, -74, 10)
	kit:barrier("Attack", 21, -84, 23, -74, 10)
	kit:sign("CABLE STATION", 0, 12, -85, 20, 3, "+Z", DUSK)

	-- A ENTRY / A ALLEY / A LONG ---------------------------------------------------------
	kit:wall("AEntryNorth", -64, -72, -22, -72, 14, "Wall", 1.2)
	kit:crate(-44, -80)
	kit:crate(-34, -76, 0, 4, "CrateWood", 25)
	kit:wall("AAlleyS", -64, -50, -30, -50, 14, "Wall", 1.2)
	kit:wall("AAlleyN", -64, -40, -30, -40, 14, "Wall", 1.2)
	kit:crate(-48, -45)
	-- A LONG : bordure de falaise, longues lignes ponctuées de rochers
	kit:box("RockA1", -96, 0, -60, -88, 6, -52, "Rock")
	kit:box("RockA2", -78, 0, -30, -70, 5, -22, "Rock")
	kit:box("RockA3", -94, 0, -10, -86, 8, -4, "Rock")
	kit:crate(-74, -66)
	kit:crate(-80, 0, 0, 4, "Crate", 15)
	kit:lamp(-66, -40, 12, DUSK)
	kit:lamp(-66, -8, 12, DUSK)
	kit:trim(-99.5, -86, -99, 4, 3.2, AMBER)

	-- COURTYARD --------------------------------------------------------------------------
	kit:floor("CourtyardFloor", -30, -70, 30, -24, "Floor", 0.1, 0.2)
	kit:wallDoor("CourtyardWest", -30, -70, -30, -24, 14, -50, -40, 10, "Wall", 1.2)
	kit:wallDoor("CourtyardEast", 30, -70, 30, -24, 14, -50, -40, 10, "Wall", 1.2)
	kit:box("ChokeW", -30, 0, -24.6, -14, 14, -23.4, "Wall")
	kit:box("ChokeE", 14, 0, -24.6, 30, 14, -23.4, "Wall")
	kit:crate(-18, -58)
	kit:crate(-18, -58, 4)
	kit:crate(14, -52, 0, 4, "CrateWood", 10)
	kit:cover(-6, -42, 6, -40, 3.6, "WallPanel")
	kit:crate(20, -34)
	kit:crate(-22, -32, 0, 4, "Crate", 30)
	kit:lamp(0, -56, 12, DUSK)
	kit:sign("COURTYARD", 0, 12, -24.2, 14, 2.4, "-Z", DUSK)

	-- B ENTRY / B ALLEY / B TUNNEL ------------------------------------------------------
	kit:wall("BEntryNorth", 22, -72, 60, -72, 14, "Wall", 1.2)
	kit:crate(40, -80)
	kit:wall("BAlleyS", 30, -50, 60, -50, 14, "Wall", 1.2)
	kit:wall("BAlleyN", 30, -40, 60, -40, 14, "Wall", 1.2)
	kit:crate(46, -45, 0, 4, "CrateWood")
	kit:floor("TunnelFloor", 60, -86, 76, 4, "FloorMetal", 0.1, 0.2)
	kit:wallDoor("TunnelWest", 60, -72, 60, 4, 12, -50, -40, 10, "MetalDark", 1.2)
	kit:ceiling(60, -86, 76, 4, 12, "MetalDark")
	kit:box("TunnelPipe1", 60, 0, -20, 64, 6, -12, "Metal")
	kit:box("TunnelPipe2", 72, 0, -36, 76, 6, -28, "Metal")
	kit:box("Generator", 70, 0, -62, 76, 7, -54, "MetalDark")
	kit:crate(64, -4)
	kit:light(68, 10, -60, CYAN, 1.2, 22, false)
	kit:light(68, 10, -30, CYAN, 1.2, 22, false)
	kit:light(68, 10, -2, AMBER, 1.2, 22, false)
	kit:trim(60.6, -86, 60.8, 4, 1, CYAN, 0.15)
	kit:sign("B TUNNEL", 68, 9, -71.5, 10, 2, "-Z", CYAN)

	-- PLAZA (mid) ------------------------------------------------------------------------
	kit:floor("PlazaFloor", -30, -24, 30, 24, "FloorTile", 0.1, 0.2)
	kit:wallDoor("PlazaWest", -30, -24, -30, 24, 14, 6, 16, 10, "Wall", 1.2)
	kit:wallDoor("PlazaEast", 30, -24, 30, 24, 14, 6, 16, 10, "Wall", 1.2)
	kit:box("SpireBase", -6, 0, -6, 6, 1.5, 6, "Marble")
	kit:box("Spire", -3, 1.5, -3, 3, 34, 3, "Monolith")
	kit:trim(-3.1, -3.1, 3.1, -2.9, 20, REACTOR, 0.4)
	kit:light(0, 22, 0, REACTOR, 2, 40, false)
	kit:crate(-18, -14)
	kit:crate(16, -12, 0, 4, "Crate", 20)
	kit:crate(-14, 12)
	kit:crate(12, 8)
	kit:cover(-24, -4, -20, 0, 3.6, "WallPanel")
	kit:cover(20, 0, 24, 4, 3.6, "WallPanel")

	-- TERRACE + BACK ROAD (côté défense, y = 5) ------------------------------------------
	kit:platform("Terrace", -30, 24, 30, 56, 5, "FloorTile")
	kit:box("TerraceRailW", -30, 5, 24, -26, 8.4, 24.6, "MetalDark")
	kit:box("TerraceRailC", -18, 5, 24, 18, 8.4, 24.6, "MetalDark")
	kit:box("TerraceRailE", 26, 5, 24, 30, 8.4, 24.6, "MetalDark")
	kit:ramp("TerraceRampW", -26, 14, -18, 24, 0, 5, "+Z", "Grate")
	kit:ramp("TerraceRampE", 18, 14, 26, 24, 0, 5, "+Z", "Grate")
	kit:crate(-8, 40, 5)
	kit:crate(10, 46, 5, 4, "Crate", 15)
	kit:trim(-30, 24.7, 30, 24.9, 8.5, CYAN)
	kit:platform("BackRoad", -56, 56, 56, 64, 5, "FloorMetal")
	kit:ramp("BackRampW", -72, 56, -56, 64, 0, 5, "+X", "Grate")
	kit:ramp("BackRampE", 56, 56, 72, 64, 0, 5, "-X", "Grate")
	kit:wall("BackRoadNorthW", -96, 64, -16, 64, 16, "Wall", 1.2)
	kit:wall("BackRoadNorthE", 16, 64, 96, 64, 16, "Wall", 1.2)
	kit:lamp(-40, 60, 10, DUSK, 5)
	kit:lamp(40, 60, 10, DUSK, 5)

	-- COMMAND (spawn défense, y = 5) -----------------------------------------------------
	kit:platform("CommandFloor", -16, 64, 16, 86, 5, "FloorMetal")
	kit:box("CommandPillar", -6, 5, 63.4, 6, 19, 64.6, "WallPanel")
	kit:box("CommandWallW", -16.6, 5, 64, -15.4, 19, 86, "WallPanel")
	kit:box("CommandWallE", 15.4, 5, 64, 16.6, 19, 86, "WallPanel")
	kit:ceiling(-16, 64, 16, 86, 19, "MetalDark")
	kit:panelLight(-12, 70, 12, 82, 18.9, Color3.fromRGB(220, 235, 255), 2)
	for _, x in { -10, -3, 3, 10 } do
		kit:spawn("Defense", x, 78, x, 0, 5)
	end
	kit:spawn("Defense", -12, 70, -60, 60, 5)
	kit:spawn("Defense", 12, 70, 60, 60, 5)
	kit:barrier("Defense", -14, 63, -6, 65, 10, 5)
	kit:barrier("Defense", 6, 63, 14, 65, 10, 5)
	kit:sign("COMMAND", 0, 17, 85, 14, 3, "-Z", CYAN)

	-- SITE A — REACTOR (extérieur) -------------------------------------------------------
	kit:floor("AFloor", -96, 4, -46, 56, "FloorMetal", 0.1, 0.2)
	kit:wallDoor("AEast", -46, 4, -46, 56, 14, 6, 16, 10, "Wall", 1.2)
	kit:wallDoor("ANorth", -100, 56, -46, 56, 14, -86, -74, 10, "Wall", 1.2)
	kit:box("ASouthWest", -64, 0, 3.4, -46, 14, 4.6, "Wall")
	kit:box("ASouthWest2", -100, 0, 3.4, -92, 14, 4.6, "Wall")
	kit:box("ASouthMid", -76, 0, 3.4, -64, 14, 4.6, "Wall")
	kit:box("ReactorCore", -76, 0, 24, -64, 10, 36, "MetalDark")
	kit:box("ReactorCap", -74, 10, 26, -66, 13, 34, "Monolith")
	kit:trim(-76.1, 24, -63.9, 36, 6, REACTOR, 0.4)
	kit:light(-70, 15, 30, REACTOR, 2.5, 45, true)
	kit:crate(-86, 16)
	kit:crate(-86, 16, 4)
	kit:crate(-56, 14)
	kit:crate(-58, 44, 0, 4, "Crate", 20)
	kit:crate(-90, 40)
	kit:cover(-82, 30, -80, 38, 3.6, "MetalDark")
	-- Passerelle haute (high ground défense)
	kit:platform("AHeaven", -96, 48, -64, 54, 7, "Grate", 1)
	kit:pillar(-92, 51, 1.4, 6, "MetalDark")
	kit:pillar(-68, 51, 1.4, 6, "MetalDark")
	kit:ramp("AHeavenRamp", -64, 48, -52, 54, 0, 7, "-X", "Grate")
	kit:box("AHeavenRail", -96, 7, 47.6, -64, 10, 48, "MetalDark")
	kit:site("A", -92, 10, -50, 46)
	kit:sign("A", -70, 12, 55.5, 6, 6, "-Z", AMBER)
	kit:sign("REACTOR", -70, 9, 4.6, 12, 2.4, "-Z", REACTOR)

	-- SITE B — DATACORE (intérieur, CQB) -------------------------------------------------
	kit:floor("BFloor", 46, 4, 96, 52, "FloorTile", 0.1, 0.2)
	kit:wallDoor("BWest", 46, 4, 46, 52, 14, 6, 16, 10, "WallPanel", 1.2)
	kit:wallDoor("BSouth", 46, 4, 100, 4, 14, 62, 72, 10, "WallPanel", 1.2)
	kit:wallDoor("BNorth", 46, 52, 100, 52, 14, 74, 84, 10, "WallPanel", 1.2)
	kit:ceiling(46, 4, 100, 52, 14, "MetalDark")
	kit:box("BNorthPocketWall", 46, 0, 52, 56, 14, 64, "Wall")
	for index, z in { 16, 28, 40 } do
		kit:box("RackRow" .. index, 58, 0, z - 1, 70, 9, z + 1, "Server")
		kit:trim(58, z - 1.1, 70, z - 0.9, 7, CYAN, 0.15)
	end
	kit:box("CoreServer", 80, 0, 22, 88, 9, 34, "Server")
	kit:trim(79.9, 22, 80.1, 34, 5, CYAN, 0.3)
	kit:crate(76, 10)
	kit:crate(90, 44)
	kit:crate(52, 46, 0, 4, "Crate", 15)
	kit:panelLight(52, 8, 94, 48, 13.9, Color3.fromRGB(200, 230, 255), 1.6)
	kit:site("B", 50, 8, 92, 48)
	kit:sign("B", 72, 11, 51.4, 6, 6, "-Z", AMBER)
	kit:sign("DATACORE", 66, 9, 4.6, 12, 2.4, "+Z", CYAN)

	-- Callouts
	kit:callout("CABLE STATION", -22, -86, 22, -70)
	kit:callout("A ENTRY", -64, -86, -22, -72)
	kit:callout("A ALLEY", -64, -50, -30, -40)
	kit:callout("A LONG", -100, -86, -64, 4)
	kit:callout("COURTYARD", -30, -70, 30, -24)
	kit:callout("B ENTRY", 22, -86, 60, -72)
	kit:callout("B ALLEY", 30, -50, 60, -40)
	kit:callout("B TUNNEL", 60, -86, 76, 4)
	kit:callout("PLAZA", -30, -24, 30, 24)
	kit:callout("A LINK", -46, 4, -30, 18)
	kit:callout("B LINK", 30, 4, 46, 18)
	kit:callout("TERRACE", -30, 24, 30, 56, 4, 30)
	kit:callout("BACK ROAD", -72, 56, 72, 64, -4, 30)
	kit:callout("COMMAND", -16, 64, 16, 86, 4, 30)
	kit:callout("A SITE", -96, 4, -46, 56)
	kit:callout("A HEAVEN", -96, 47, -52, 55, 6.5, 30)
	kit:callout("B SITE", 46, 4, 96, 52)
	kit:callout("B NORTH", 56, 52, 96, 64)

	-- Habillage (décor non bloquant) : Maps/Dressing/Spire
	dress(kit)
end

return {
	id = "spire",
	build = build,
	intro = {
		CFrame.lookAt(Vector3.new(-90, 60, -80), Vector3.new(0, 10, 0)),
		CFrame.lookAt(Vector3.new(0, 30, -20), Vector3.new(0, 20, 0)),
		CFrame.lookAt(Vector3.new(-50, 22, 10), Vector3.new(-70, 6, 30)),
		CFrame.lookAt(Vector3.new(50, 12, 10), Vector3.new(70, 4, 30)),
	},
	overview = CFrame.lookAt(Vector3.new(0, 170, -90), Vector3.new(0, 0, 0)),
}
