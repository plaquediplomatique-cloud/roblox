--!strict
--[[
	HELIX VAULT — Wingman 2v2 (site unique VAULT) / Clash. Carte intérieure, asymétrique.

	     x=-42                    0                         x=52
	z=62 ┌────────────────────┬──────────────────────────────┐
	     │  SECURITY (DÉF.)   │   (noyau technique)          │
	z=46 │──┤door├────────────┤door═════ VAULT CORRIDOR ══╗  │
	     │BACK │   ▓▓ noyau ▓▓│ SERVICE ┃     VAULT (site) ┃  │
	     │HALL │              │   ═door═┃   [SAFE]        ┃  │
	z=16 │─door┴──────────────┴─door────┴───┤MAIN├─────────┘  │
	     │      ATRIUM (mid, verre)       │LINK│ MAIN HALL    │
	z=-20│──┤opening├─────────────────────┤    │ (portiques)  │
	     │  ESCALATORS     │              │    │              │
	z=-44│──┤door├─────────┴── LOBBY (ATTAQUE) ─┤ opening ├───│
	z=-62└──────────────────────────────────────────────────────┘

	Routes attaque : MAIN HALL (directe, contrôlée par les portiques) / ATRIUM -> SERVICE
	-> porte ouest du vault / ATRIUM -> LINK -> MAIN (flanc). Défense : accès nord direct
	au site (≈ 3 s), ou BACK HALL -> ATRIUM pour contester le mid et prendre l'info.
	Le verre (vitrines de l'atrium) est pénétrable : wallbangs et lecture au son.
]]

local MapKit = require(script.Parent.Parent.MapKit)

type Kit = MapKit.Kit

local WHITE = Color3.fromRGB(225, 235, 255)
local CYAN = Color3.fromRGB(61, 225, 255)
local GOLD = Color3.fromRGB(255, 200, 90)

local H = 16 -- hauteur sous plafond

local function build(kit: Kit)
	kit:floor("Ground", -42, -62, 52, 62, "Marble", 0, 4)
	kit:bounds(-42, -62, 52, 62, 30)

	-- Enveloppe extérieure
	kit:wall("OuterS", -42, -62, 52, -62, H, "WallDark", 2)
	kit:wall("OuterN", -42, 62, 52, 62, H, "WallDark", 2)
	kit:wall("OuterW", -42, -62, -42, 62, H, "WallDark", 2)
	kit:wall("OuterE", 52, -62, 52, 62, H, "WallDark", 2)

	-- LOBBY (spawn attaque) ----------------------------------------------------------------
	kit:floor("LobbyFloor", -34, -62, 46, -44, "MarbleWhite", 0.15, 0.3)
	kit:box("LobbyWallW", -42, 0, -62, -34, H, -44, "WallDark")
	kit:box("LobbyWallE", 46, 0, -62, 52, H, -44, "WallDark")
	kit:box("LobbyNorth1", -34, 0, -44.6, -30, H, -43.4, "WallPanel")
	kit:box("LobbyNorth2", -20, 0, -44.6, 26, H, -43.4, "WallPanel")
	kit:box("LobbyNorthLintel", -30, 10, -44.6, -20, H, -43.4, "WallPanel")
	kit:box("LobbyNorthLintel2", 26, 12, -44.6, 42, H, -43.4, "WallPanel")
	kit:box("LobbyNorth3", 42, 0, -44.6, 46, H, -43.4, "WallPanel")
	kit:cover(-4, -50, 12, -48, 4, "MarbleWhite")
	kit:ceiling(-34, -62, 46, -44, H, "WallPanel")
	kit:panelLight(-20, -58, 30, -48, H - 0.1, WHITE, 2.4)
	for _, x in { -12, -4, 4, 12 } do
		kit:spawn("Attack", x, -56, x, 0)
	end
	kit:spawn("Attack", 20, -56, 30, 0)
	kit:barrier("Attack", -30, -45, -20, -43, 10)
	kit:barrier("Attack", 26, -45, 42, -43, 12)
	kit:sign("HELIX BANK", 6, 12, -61, 24, 3.5, "+Z", GOLD)

	-- MAIN HALL ----------------------------------------------------------------------------
	kit:floor("MainHallFloor", 24, -44, 46, 16, "FloorTile", 0.1, 0.2)
	kit:wallDoor("MainHallWest", 24, -44, 24, 16, H, -8, 0, 10, "WallPanel", 1.4)
	kit:wall("MainHallEast", 46, -44, 46, 16, H, "WallPanel", 1.4)
	kit:ceiling(24, -44, 46, 16, H, "WallPanel")
	kit:panelLight(30, -40, 40, -26, H - 0.1, WHITE, 2)
	kit:panelLight(30, -6, 40, 10, H - 0.1, WHITE, 2)
	-- Portiques de sécurité : coupent la ligne de vue vault -> lobby
	kit:box("GateL", 26, 0, -17, 32, 8, -15, "MetalDark")
	kit:box("GateR", 38, 0, -17, 44, 8, -15, "MetalDark")
	kit:trim(32, -16.2, 38, -15.8, 8.2, CYAN)
	kit:pillar(30, -32, 2.4, H, "MarbleWhite")
	kit:pillar(40, -26, 2.4, H, "MarbleWhite")
	kit:pillar(30, 2, 2.4, H, "MarbleWhite")
	kit:crate(41, 6, 0, 4, "Crate")
	kit:cover(27, -38, 31, -36, 3.6, "MarbleWhite")
	kit:sign("MAIN", 35, 12, -43, 8, 2.2, "+Z", WHITE)

	-- Volume technique plein entre ESCALATORS et MAIN HALL (aucun espace mort accessible)
	kit:box("ServiceCoreSouth", -12, 0, -44, 24, H, -20, "WallDark")

	-- ESCALATORS ---------------------------------------------------------------------------
	kit:floor("EscFloor", -40, -44, -12, -20, "FloorTile", 0.1, 0.2)
	kit:wall("EscEast", -12, -44, -12, -20, H, "WallPanel", 1.4)
	kit:ceiling(-40, -44, -12, -20, H, "WallPanel")
	kit:platform("Landing", -24, -40, -12, -26, 4, "MarbleWhite")
	kit:ramp("EscRamp", -24, -26, -16, -20, 0, 4, "-Z", "Grate")
	kit:ramp("EscStair", -34, -40, -24, -34, 0, 4, "+X", "Grate")
	kit:box("LandingRail", -24, 4, -40.4, -12, 7.2, -40, "Glass")
	kit:cover(-38, -30, -34, -28, 3.6, "MarbleWhite")
	kit:panelLight(-34, -40, -18, -24, H - 0.1, WHITE, 1.6)

	-- ATRIUM (mid) -------------------------------------------------------------------------
	kit:floor("AtriumFloor", -40, -20, 24, 16, "MarbleWhite", 0.1, 0.2)
	kit:box("AtriumSouthWall", -16, 0, -20.6, 24, H, -19.4, "WallPanel")
	kit:box("AtriumSouthPost", -40, 0, -20.6, -36, H, -19.4, "WallPanel")
	kit:box("AtriumSouthLintel", -36, 11, -20.6, -16, H, -19.4, "WallPanel")
	local skylight = kit:box("AtriumSkylight", -40, H, -20, 24, H + 0.5, 16, "Glass")
	skylight.group = "Ceiling"
	-- Fontaine centrale (couverture basse)
	kit:box("Fountain", -12, 0, -6, -4, 3.6, 2, "Marble")
	kit:box("FountainCore", -9.5, 3.6, -3.5, -6.5, 9, -0.5, "Glass")
	kit:light(-8, 10, -2, CYAN, 1.5, 22, false)
	-- Vitrine (verre pénétrable)
	kit:box("ShowroomW", 2, 0, -14, 2.6, 8, 0, "Glass")
	kit:box("ShowroomN", 2, 0, 0, 14, 8, 0.6, "Glass")
	kit:box("ShowroomE", 13.4, 0, -14, 14, 8, -6, "Glass")
	kit:crate(8, -8, 0, 3, "Gold")
	kit:cover(-30, 4, -26, 8, 3.6, "Marble")
	kit:cover(-34, -12, -30, -8, 3.6, "Marble")
	kit:crate(16, 8)
	kit:crate(18, -14, 0, 4, "Crate", 20)
	kit:pillar(-20, 8, 2.4, H, "MarbleWhite")
	kit:pillar(-20, -12, 2.4, H, "MarbleWhite")
	kit:trim(-40, 15.2, 24, 15.6, 12, CYAN)
	kit:sign("ATRIUM", -8, 13, 15.2, 12, 2.4, "-Z", WHITE)

	-- Mur nord de l'atrium : porte BACK (ouest) et porte SERVICE (centre)
	kit:box("AtriumNorth1", -40, 0, 15.4, -36, H, 16.6, "WallPanel")
	kit:box("AtriumNorth2", -28, 0, 15.4, -4, H, 16.6, "WallPanel")
	kit:box("AtriumNorth3", 4, 0, 15.4, 24, H, 16.6, "WallPanel")
	kit:box("AtriumNorthL1", -36, 10, 15.4, -28, H, 16.6, "WallPanel")
	kit:box("AtriumNorthL2", -4, 10, 15.4, 4, H, 16.6, "WallPanel")

	-- Noyau technique plein (entre BACK HALL et SERVICE)
	kit:box("CoreBlock", -20, 0, 16, -6, H, 46, "WallDark")

	-- BACK HALL (défense -> atrium) ------------------------------------------------------
	kit:floor("BackFloor", -40, 16, -20, 46, "FloorTile", 0.1, 0.2)
	kit:ceiling(-40, 16, -20, 46, H, "WallPanel")
	kit:crate(-24, 30)
	kit:cover(-38, 22, -34, 24, 3.6, "Marble")
	kit:panelLight(-34, 22, -26, 40, H - 0.1, WHITE, 1.4)

	-- SERVICE (atrium -> porte ouest du vault) -------------------------------------------
	kit:floor("ServiceFloor", -6, 16, 10, 38, "FloorMetal", 0.1, 0.2)
	kit:box("ServiceNorth", -6, 0, 38, 10, H, 46, "WallDark")
	kit:ceiling(-6, 16, 10, 38, H, "MetalDark")
	kit:crate(-2, 32, 0, 4, "Crate")
	kit:cover(4, 20, 8, 22, 3.6, "MetalDark")
	kit:light(2, 12, 27, CYAN, 1.2, 20, false)

	-- VAULT (site) -------------------------------------------------------------------------
	kit:floor("VaultFloor", 10, 16, 50, 46, "FloorMetal", 0.15, 0.3)
	kit:wallDoor("VaultSouth", 10, 16, 52, 16, H, 30, 40, 10, "Metal", 1.6)
	kit:wallDoor("VaultWest", 10, 16, 10, 46, H, 28, 36, 10, "Metal", 1.6)
	kit:wallDoor("VaultNorth", 10, 46, 52, 46, H, 16, 24, 10, "Metal", 1.6)
	kit:ceiling(10, 16, 52, 46, H, "MetalDark")
	kit:panelLight(14, 20, 46, 42, H - 0.1, Color3.fromRGB(255, 236, 200), 2)
	-- Coffre central (bloque les lignes)
	kit:box("Safe", 26, 0, 26, 34, 8, 34, "Metal")
	kit:trim(26, 25.9, 34, 26.1, 8.1, GOLD)
	kit:crate(18, 22, 0, 4, "Gold")
	kit:crate(18, 40, 0, 4, "Gold")
	kit:crate(42, 22, 0, 4, "Gold")
	kit:crate(38, 40, 0, 4, "Gold")
	kit:crate(38, 40, 4, 4, "Gold")
	kit:box("RackE1", 47, 0, 20, 49, 10, 28, "Server")
	kit:box("RackE2", 47, 0, 34, 49, 10, 42, "Server")
	kit:trim(46.9, 20, 47, 28, 6, CYAN, 0.15)
	kit:trim(46.9, 34, 47, 42, 6, CYAN, 0.15)
	kit:cover(28, 19, 32, 21, 3.6, "MetalDark")
	kit:site("VAULT", 12, 18, 48, 44)
	kit:sign("VAULT", 31, 13, 45, 10, 3, "-Z", GOLD)
	-- Porte de coffre géante (décor)
	kit:block("VaultDoorProp", Vector3.new(44, 6, 13), Vector3.new(1.2, 12, 12), "Metal", "Props")

	-- VAULT CORRIDOR (défense -> accès nord du vault) -----------------------------------
	kit:floor("CorridorFloor", -8, 46, 30, 54, "FloorTile", 0.1, 0.2)
	kit:box("CorridorNorth", -8, 0, 54, 52, H, 62, "WallDark")
	kit:box("CorridorEast", 30, 0, 46, 52, H, 54, "WallDark")
	kit:ceiling(-8, 46, 30, 54, H, "WallPanel")
	kit:cover(2, 47, 6, 49, 3.6, "Marble")
	kit:panelLight(0, 48, 24, 52, H - 0.1, WHITE, 1.4)

	-- SECURITY (spawn défense) -------------------------------------------------------------
	kit:floor("SecurityFloor", -40, 46, -8, 62, "FloorMetal", 0.15, 0.3)
	kit:box("SecurityEast1", -8.6, 0, 54, -7.4, H, 62, "WallPanel")
	kit:box("SecurityEastL", -8.6, 10, 46, -7.4, H, 54, "WallPanel")
	kit:box("SecuritySouth1", -40, 0, 45.4, -36, H, 46.6, "WallPanel")
	kit:box("SecuritySouth2", -28, 0, 45.4, -20, H, 46.6, "WallPanel")
	kit:box("SecuritySouthL", -36, 10, 45.4, -28, H, 46.6, "WallPanel")
	kit:ceiling(-40, 46, -8, 62, H, "MetalDark")
	kit:panelLight(-36, 50, -12, 58, H - 0.1, WHITE, 2)
	for _, x in { -34, -26, -18 } do
		kit:spawn("Defense", x, 57, x, 30)
	end
	kit:spawn("Defense", -13, 51, 20, 50)
	kit:barrier("Defense", -9, 46, -7, 54, 10)
	kit:barrier("Defense", -36, 45, -28, 47, 10)
	kit:sign("SECURITY", -24, 12, 61, 14, 2.6, "-Z", CYAN)

	-- Callouts
	kit:callout("LOBBY", -34, -62, 46, -44)
	kit:callout("MAIN", 24, -44, 46, 16)
	kit:callout("GATES", 24, -20, 46, -12)
	kit:callout("ESCALATORS", -40, -44, -12, -20)
	kit:callout("LANDING", -24, -40, -12, -26, 3.5, 20)
	kit:callout("ATRIUM", -40, -20, 24, 16)
	kit:callout("SHOWROOM", 2, -14, 14, 0)
	kit:callout("LINK", 20, -8, 28, 0)
	kit:callout("BACK HALL", -40, 16, -20, 46)
	kit:callout("SERVICE", -6, 16, 10, 38)
	kit:callout("VAULT", 10, 16, 50, 46)
	kit:callout("SAFE", 24, 24, 36, 36)
	kit:callout("CORRIDOR", -8, 46, 30, 54)
	kit:callout("SECURITY", -40, 46, -8, 62)
end

return {
	id = "helix",
	build = build,
	intro = {
		CFrame.lookAt(Vector3.new(30, 26, -58), Vector3.new(34, 6, 0)),
		CFrame.lookAt(Vector3.new(35, 10, -10), Vector3.new(30, 5, 30)),
		CFrame.lookAt(Vector3.new(-30, 14, -16), Vector3.new(0, 4, 10)),
		CFrame.lookAt(Vector3.new(14, 12, 20), Vector3.new(30, 4, 30)),
	},
	overview = CFrame.lookAt(Vector3.new(5, 140, -40), Vector3.new(5, 0, 0)),
}
