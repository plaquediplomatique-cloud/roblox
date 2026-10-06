--!strict
--[[
	AETHER SPIRE — Hub / lobby vivant.

	          x=-110        -40          0          40          x=110
	z=90  ┌──────────────┬─────────────────────┬──────────────────┐
	      │ CUSTOM LAB   │   RANKED TERMINAL   │   CASUAL BAY      │
	z=40  ├─────┬────────┴─────────┬───────────┴────────┬─────────┤
	      │     │                  │                    │         │
	      │TRAIN│      PLAZA       ◆ AETHER CORE        │ ARMORY  │
	      │ RANGE◄═ booths         (spawn)              │ (vitrines│
	      │     │                  │                    │  armes) │
	z=-40 ├─────┴────────┬─────────┴──────────┬─────────┴─────────┤
	      │  LOUNGE W    │   HALL OF FAME     │   LOUNGE E         │
	      │              │ (leaderboard, missions, pass, réglages) │
	z=-90 └──────────────┴────────────────────┴───────────────────┘

	Chaque zone a une identité visuelle (couleur néon), un terminal interactif
	(ProximityPrompt -> panneau d'UI dédié) et une raison d'y aller : le hub n'est pas
	un menu déguisé, c'est un lieu où l'on croise les autres joueurs, où l'on s'échauffe
	(Training Range) et où l'on admire les skins (Armory).
]]

local MapKit = require(script.Parent.Parent.MapKit)
local dress = require(script.Parent.Parent.Dressing.Hub)

type Kit = MapKit.Kit

local CYAN = Color3.fromRGB(61, 225, 255)
local MAGENTA = Color3.fromRGB(220, 80, 255)
local AMBER = Color3.fromRGB(255, 190, 70)
local GREEN = Color3.fromRGB(61, 255, 162)
local RED = Color3.fromRGB(255, 70, 85)
local WHITE = Color3.fromRGB(230, 240, 255)

local function build(kit: Kit)
	kit:floor("Deck", -110, -90, 110, 90, "FloorDark", 0, 4)
	kit:bounds(-110, -90, 110, 90, 60)
	kit:wall("OuterN", -110, 90, 110, 90, 30, "Hull", 2)
	kit:wall("OuterS", -110, -90, 110, -90, 30, "Hull", 2)
	kit:wall("OuterW", -110, -90, -110, 90, 30, "Hull", 2)
	kit:wall("OuterE", 110, -90, 110, 90, 30, "Hull", 2)

	-- PLAZA + AETHER CORE ----------------------------------------------------------------
	kit:floor("PlazaFloor", -40, -40, 40, 40, "FloorTile", 0.1, 0.2)
	for _, offset in { -30, -15, 0, 15, 30 } do
		kit:trim(offset - 0.1, -40, offset + 0.1, 40, 0.12, Color3.fromRGB(30, 70, 90), 0.05)
		kit:trim(-40, offset - 0.1, 40, offset + 0.1, 0.12, Color3.fromRGB(30, 70, 90), 0.05)
	end
	kit:box("CoreBase", -6, 0, -6, 6, 1.2, 6, "HullLight")
	kit:box("AetherCore", -2.5, 1.2, -2.5, 2.5, 46, 2.5, "Monolith")
	for index, y in { 8, 18, 28, 38 } do
		local ring = kit:box("CoreRing" .. index, -3.2, y, -3.2, 3.2, y + 0.4, 3.2, "NeonCyan", "Trim")
		ring.collide = false
	end
	kit:light(0, 24, 0, CYAN, 3, 60, false)
	kit:sign("AETHER STRIKE", 0, 52, 0, 34, 6, "-Z", CYAN)
	for index = 0, 7 do
		local angle = index / 8 * math.pi * 2
		local x, z = math.cos(angle) * 14, math.sin(angle) * 14
		kit:spawn("Hub", x, z, 0, 0)
	end
	-- Bancs et bornes (lieu de vie)
	for _, sx in { 1, -1 } do
		kit:cover(sx * 22 - 4, 22, sx * 22 + 4, 24, 1.6, "HullLight")
		kit:cover(sx * 22 - 4, -24, sx * 22 + 4, -22, 1.6, "HullLight")
		kit:lamp(sx * 34, 34, 10, WHITE)
		kit:lamp(sx * 34, -34, 10, WHITE)
	end
	kit:terminal("Play", "JOUER", 0, -20, "-Z", CYAN)

	-- Séparations des zones (murs bas + portiques)
	kit:wallDoor("PlazaNorth", -40, 40, 40, 40, 12, -14, 14, 10, "HullLight", 1)
	kit:wallDoor("PlazaSouth", -40, -40, 40, -40, 12, -14, 14, 10, "HullLight", 1)
	kit:wallDoor("PlazaWest", -40, -40, -40, 40, 12, -12, 12, 10, "HullLight", 1)
	kit:wallDoor("PlazaEast", 40, -40, 40, 40, 12, -12, 12, 10, "HullLight", 1)

	-- RANKED TERMINAL (nord) ------------------------------------------------------------
	kit:floor("RankedFloor", -40, 40, 40, 90, "Marble", 0.15, 0.3)
	kit:platform("RankedDais", -24, 62, 24, 84, 2, "HullLight")
	kit:ramp("RankedSteps", -10, 54, 10, 62, 0.15, 2, "+Z", "HullLight")
	kit:terminal("Ranked", "CLASSÉ", -14, 74, "-Z", AMBER)
	kit:terminal("Ranked", "CLASSÉ", 0, 76, "-Z", AMBER)
	kit:terminal("Ranked", "CLASSÉ", 14, 74, "-Z", AMBER)
	kit:sign("RANKED", 0, 18, 89, 30, 6, "-Z", AMBER)
	kit:trim(-24, 61.8, 24, 62, 2.05, AMBER, 0.2)
	kit:light(0, 14, 72, AMBER, 2, 40, false)

	-- CUSTOM LAB (nord-ouest) ------------------------------------------------------------
	kit:wallDoor("LabEast", -40, 40, -40, 90, 12, 50, 64, 10, "HullLight", 1)
	kit:floor("LabFloor", -110, 40, -40, 90, "FloorMetal", 0.15, 0.3)
	kit:terminal("Custom", "PERSONNALISÉ", -76, 70, "-Z", MAGENTA)
	kit:box("HoloTable", -84, 0, 52, -68, 3, 60, "MetalDark")
	kit:trim(-84, 52, -68, 60, 3.05, MAGENTA, 0.1)
	kit:sign("CUSTOM LAB", -76, 16, 89, 26, 5, "-Z", MAGENTA)
	kit:light(-76, 12, 64, MAGENTA, 2, 36, false)

	-- CASUAL BAY (nord-est) --------------------------------------------------------------
	kit:wallDoor("BayWest", 40, 40, 40, 90, 12, 50, 64, 10, "HullLight", 1)
	kit:floor("BayFloor", 40, 40, 110, 90, "FloorMetal", 0.15, 0.3)
	kit:terminal("Casual", "CASUAL", 76, 70, "-Z", GREEN)
	kit:cover(62, 52, 90, 54, 1.6, "HullLight")
	kit:sign("CASUAL BAY", 76, 16, 89, 26, 5, "-Z", GREEN)
	kit:light(76, 12, 64, GREEN, 2, 36, false)

	-- ARMORY (est) ------------------------------------------------------------------------
	kit:floor("ArmoryFloor", 40, -40, 110, 40, "Marble", 0.15, 0.3)
	kit:terminal("Armory", "ARMURERIE", 60, 0, "-X", CYAN)
	for row, x in { 76, 96 } do
		for index = 0, 6 do
			local z = -30 + index * 10
			local pedestal = kit:box("Pedestal", x - 2, 0, z - 2, x + 2, 3, z + 2, "HullLight", "Props")
			table.insert(pedestal.tags, "WeaponPedestal")
			pedestal.attributes.Slot = (row - 1) * 7 + index + 1
			kit:trim(x - 2, z - 2.05, x + 2, z - 1.95, 3.05, CYAN, 0.1)
		end
	end
	kit:sign("ARMORY", 109, 16, 0, 30, 6, "-X", CYAN)
	kit:light(86, 14, 0, WHITE, 2.5, 50, true)

	-- TRAINING RANGE (ouest) ------------------------------------------------------------
	kit:floor("RangeFloor", -110, -40, -40, 40, "Floor", 0.15, 0.3)
	kit:zone("TrainingZone", "TrainingZone", -110, -2, -40, -40.5, 30, 40, nil)
	kit:terminal("Training", "ENTRAÎNEMENT", -46, 30, "+X", GREEN)
	-- Box de tir (le joueur tire vers -X)
	for index, z in { -26, -14, -2, 10 } do
		kit:cover(-50, z - 5, -48, z + 5, 3.2, "MetalDark")
		kit:trim(-50, z - 5, -48, z + 5, 3.25, GREEN, 0.1)
		local lane =
			kit:zone("BotAnchor", "LaneAnchor", -96, 0, z - 1, -94, 4, z + 1, { Kind = "Static", Lane = index })
		lane.attributes.Distances = "15,30,45"
	end
	for _, z in { -20, -8, 4 } do
		kit:wall("LaneDivider", -94, z, -50, z, 1.2, "Grate", 0.4)
	end
	for _, info in { { x = -63, label = "15" }, { x = -78, label = "30" }, { x = -93, label = "45" } } do
		kit:sign(info.label, info.x, 7, -32, 4, 2, "+Z", GREEN)
	end
	-- Arène de tracking (bots mobiles)
	kit:box("TrackWall", -108, 0, 18, -60, 10, 20, "MetalDark")
	kit:zone("BotAnchor", "StrafeAnchor", -98, 0, 26, -70, 4, 36, { Kind = "Strafe", Lane = 5 })
	kit:crate(-86, 24, 0, 4, "Crate")
	kit:crate(-74, 34)
	kit:sign("TRAINING RANGE", -109, 14, 0, 30, 5, "+X", GREEN)
	kit:light(-75, 16, -6, WHITE, 2.4, 60, true)

	-- HALL OF FAME (sud) ------------------------------------------------------------------
	kit:floor("HallFloor", -40, -90, 40, -40, "Marble", 0.15, 0.3)
	local board = kit:box("LeaderboardWall", -36, 2, -88.4, 36, 26, -87.6, "Monolith", "Props")
	table.insert(board.tags, "LeaderboardDisplay")
	kit:trim(-36, -87.5, 36, -87.4, 26.2, AMBER, 0.3)
	kit:terminal("Leaderboard", "CLASSEMENT", -18, -70, "+Z", AMBER)
	kit:terminal("Missions", "MISSIONS", 0, -66, "+Z", CYAN)
	kit:terminal("Pass", "AETHER PASS", 18, -70, "+Z", MAGENTA)
	kit:terminal("Settings", "RÉGLAGES", 30, -50, "-X", WHITE)
	kit:sign("HALL OF FAME", 0, 30, -87, 30, 4, "+Z", AMBER)
	kit:light(0, 18, -70, AMBER, 2, 46, false)

	-- LOUNGES (sud-ouest / sud-est)
	kit:wallDoor("LoungeW", -40, -90, -40, -40, 12, -70, -56, 10, "HullLight", 1)
	kit:wallDoor("LoungeE", 40, -90, 40, -40, 12, -70, -56, 10, "HullLight", 1)
	for _, sx in { 1, -1 } do
		kit:floor("LoungeFloor", sx * 40, -90, sx * 110, -40, "FloorTile", 0.15, 0.3)
		kit:cover(sx * 60, -76, sx * 90, -72, 1.6, "HullLight")
		kit:cover(sx * 60, -58, sx * 90, -54, 1.6, "HullLight")
		kit:light(sx * 75, 12, -65, if sx > 0 then CYAN else MAGENTA, 1.6, 40, false)
	end
	kit:terminal("Play", "JOUER", -75, -46, "-Z", CYAN)
	kit:terminal("Play", "JOUER", 75, -46, "-Z", CYAN)

	-- Callouts (affichés en haut de l'écran dans le hub)
	kit:callout("PLAZA", -40, -40, 40, 40)
	kit:callout("RANKED TERMINAL", -40, 40, 40, 90)
	kit:callout("CUSTOM LAB", -110, 40, -40, 90)
	kit:callout("CASUAL BAY", 40, 40, 110, 90)
	kit:callout("ARMORY", 40, -40, 110, 40)
	kit:callout("TRAINING RANGE", -110, -40, -40, 40)
	kit:callout("HALL OF FAME", -40, -90, 40, -40)
	kit:callout("LOUNGE", -110, -90, -40, -40)
	kit:callout("LOUNGE", 40, -90, 110, -40)

	-- Accent de couleur : la marque de chaque zone au plafond du portique
	kit:trim(-14, 40, 14, 40.3, 10.2, AMBER, 0.3)
	kit:trim(-40.3, -12, -40, 12, 10.2, GREEN, 0.3)
	kit:trim(40, -12, 40.3, 12, 10.2, CYAN, 0.3)
	kit:trim(-14, -40.3, 14, -40, 10.2, AMBER, 0.3)
	kit:light(0, 9, 40, AMBER, 1, 16, false)
	kit:light(-40, 9, 0, GREEN, 1, 16, false)
	kit:light(40, 9, 0, CYAN, 1, 16, false)
	kit:light(0, 9, -40, RED, 0.6, 12, false)

	-- Habillage (mégapole, charpente, salons, zones) : Maps/Dressing/Hub
	dress(kit)
end

return {
	id = "hub",
	build = build,
	intro = {
		CFrame.lookAt(Vector3.new(0, 60, -110), Vector3.new(0, 20, 0)),
		CFrame.lookAt(Vector3.new(30, 18, -20), Vector3.new(0, 30, 0)),
	},
	overview = CFrame.lookAt(Vector3.new(0, 200, -120), Vector3.new(0, 0, 0)),
}
