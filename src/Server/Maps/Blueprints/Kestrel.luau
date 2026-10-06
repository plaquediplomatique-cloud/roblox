--!strict
--[[
	KESTREL YARD — Duel 1v1 / Clash 2v2. Symétrie MIROIR (x -> -x) : équité parfaite.

	        x=-72                         0                          x=72
	z=46  ┌───────────────────────────────────────────────────────────┐
	      │  CONTAINERS (CQB, conteneurs escaladables via caisses)    │
	z=24  ├──door──┐                                          ┌──door──┤
	      │        │ ═══ mur z=16 (connecteurs W/E) ═══       │        │
	      │ WEST   door   YARD        [TOWER]       YARD    door  EAST │
	      │ SPAWN  │  ▌bloqueur      rampe→■←rampe     bloqueur▐ │ SPAWN │
	      │        │ ═══ mur z=-16 (connecteurs + fenêtre) ═══│        │
	z=-24 ├──door──┘                                          └──door──┤
	      │  CATWALK surélevé (y=6) au-dessus de l'UNDERPASS          │
	z=-46 └───────────────────────────────────────────────────────────┘

	Philosophie :
	  * 3 voies lisibles (Containers / Yard / Catwalk), chacune avec un rythme propre :
	    angles courts au nord, duel ouvert autour de la tour au centre, long axe + hauteur au sud.
	  * La TOUR (high ground central) domine le Yard mais est exposée sur 4 faces : la
	    prendre donne l'info, la tenir coûte cher.
	  * Bloqueurs devant les portes de spawn : aucune ligne de vue tour -> spawn.
	  * Fenêtre catwalk -> yard : un joueur au sud peut contester le mid sans y entrer.
]]

local MapKit = require(script.Parent.Parent.MapKit)

type Kit = MapKit.Kit

local ORANGE = Color3.fromRGB(255, 160, 80)
local CYAN = Color3.fromRGB(61, 225, 255)
local AMBER = Color3.fromRGB(255, 190, 70)

local function build(kit: Kit)
	kit:floor("Ground", -72, -46, 72, 46, "Floor", 0, 4)
	kit:bounds(-72, -46, 72, 46, 40)

	-- Murs extérieurs
	kit:wall("OuterN", -72, 46, 72, 46, 20, "WallDark", 2)
	kit:wall("OuterS", -72, -46, 72, -46, 20, "WallDark", 2)
	kit:wall("OuterW", -72, -46, -72, 46, 20, "WallDark", 2)
	kit:wall("OuterE", 72, -46, 72, 46, 20, "WallDark", 2)

	-- Tour centrale (high ground, y = 7)
	kit:platform("Tower", -7, -7, 7, 7, 7, "Metal")
	kit:box("TowerRailN", -7, 7, 6.4, 7, 10.4, 7, "MetalDark")
	kit:box("TowerRailS", -7, 7, -7, 7, 10.4, -6.4, "MetalDark")
	kit:crate(0, -3, 7, 4, "Crate")
	kit:trim(-7, -7.1, 7, -6.9, 7.05, CYAN)
	kit:trim(-7, 6.9, 7, 7.1, 7.05, CYAN)
	kit:light(0, 14, 0, ORANGE, 1.6, 30, true)

	-- Conteneur central nord + double caisse anti-ligne-longue (pièces centrales)
	kit:box("ContainerCenter", -8, 0, 36, 8, 8, 44, "ContainerOrange")
	kit:crate(0, 33, 0, 4, "CrateWood")
	kit:crate(0, 33, 4, 4, "CrateWood")
	-- Caisse centrale sud
	kit:crate(0, -36, 0, 4, "Crate")

	-- Mur de séparation nord (z = 16) et sud (z = -16), pièces centrales des deux moitiés
	kit:box("WindowSill", -6, 0, -16.6, 6, 7, -15.4, "Wall")
	kit:box("WindowTop", -6, 11, -16.6, 6, 14, -15.4, "Wall")

	-- Moitiés miroir : sx = 1 -> ouest (Attaque / équipe A), sx = -1 -> est
	for _, sx in { 1, -1 } do
		local function X(x: number): number
			return x * sx
		end
		local side = if sx == 1 then "Attack" else "Defense"
		local rampDir = if sx == 1 then "+X" else "-X"
		local inward = if sx == 1 then "+X" else "-X"

		-- Spawn (dock)
		kit:floor("SpawnFloor", X(-72), -24, X(-56), 24, "FloorMetal", 0.2, 0.4)
		kit:wallDoor("SpawnInner", X(-56), -24, X(-56), 24, 14, -4, 4, 10, "WallPanel", 1.4)
		kit:wallDoor("SpawnNorth", X(-72), 24, X(-56), 24, 14, X(-67), X(-61), 10, "WallPanel", 1.4)
		kit:wallDoor("SpawnSouth", X(-72), -24, X(-56), -24, 14, X(-67), X(-61), 10, "WallPanel", 1.4)
		kit:ceiling(X(-72), -24, X(-56), 24, 14, "MetalDark")
		kit:panelLight(X(-68), -10, X(-60), 10, 13.9, Color3.fromRGB(220, 235, 255), 2)
		for index, z in { -8, 0, 8 } do
			kit:spawn(side, X(-66), z, 0, z)
			if index < 3 then
				kit:spawn(side, X(-61), z + 4, 0, z + 4)
			end
		end
		kit:barrier(side, X(-56.8), -4, X(-55.2), 4, 10)
		kit:barrier(side, X(-67), 23.2, X(-61), 24.8, 10)
		kit:barrier(side, X(-67), -24.8, X(-61), -23.2, 10)
		kit:sign(if sx == 1 then "WEST DOCK" else "EAST DOCK", X(-55.2), 12, 9, 8, 2.2, inward, CYAN)

		-- Bloqueur de spawn
		kit:cover(X(-50), -7, X(-48), 7, 10, "WallPanel")
		kit:trim(X(-50), -7, X(-48), 7, 10.05, ORANGE, 0.2)

		-- Murs Yard / voies
		kit:wallDoor("MidWallN", X(-56), 16, X(0), 16, 14, X(-34), X(-27), 10, "Wall", 1.2)
		kit:box("MidWallS1", X(-56), 0, -16.6, X(-26), 14, -15.4, "Wall")
		kit:box("MidWallS2", X(-19), 0, -16.6, X(-6), 14, -15.4, "Wall")
		kit:box("MidWallSLintel", X(-26), 10, -16.6, X(-19), 14, -15.4, "Wall")

		-- Rampe de la tour
		kit:ramp("TowerRamp", X(-23), 0.5, X(-7), 6, 0, 7, rampDir, "Grate")

		-- Couvertures du Yard
		kit:crate(X(-36), 8)
		kit:crate(X(-36), 8, 4)
		kit:crate(X(-30), -8)
		kit:crate(X(-22), 11, 0, 4, "CrateWood", 15)
		kit:crate(X(-15), -11)
		kit:cover(X(-42), -13, X(-38), -11, 3.6)
		kit:lamp(X(-26), 0, 12, ORANGE)

		-- CONTAINERS (voie nord)
		kit:box("ContainerA", X(-50), 0, 36, X(-30), 8, 44, "ContainerRust")
		kit:box("ContainerStack", X(-50), 8, 36, X(-40), 16, 44, "ContainerTeal")
		kit:box("ContainerB", X(-22), 0, 22, X(-6), 8, 30, "ContainerTeal")
		kit:crate(X(-28), 40, 0, 4, "CrateWood")
		kit:crate(X(-24), 30, 0, 4, "CrateWood")
		kit:crate(X(-44), 24)
		kit:lamp(X(-38), 28, 12, ORANGE)
		kit:trim(X(-72), 45, X(-8), 45.2, 6, ORANGE)

		-- CATWALK (voie sud)
		kit:platform("Catwalk", X(-40), -25, X(0), -20, 6, "Grate", 1)
		kit:box("CatwalkRail1", X(-40), 6, -25.4, X(-28), 9, -25, "MetalDark")
		kit:box("CatwalkRail2", X(-16), 6, -25.4, X(0), 9, -25, "MetalDark")
		kit:pillar(X(-36), -22.5, 1.6, 5, "MetalDark")
		kit:pillar(X(-20), -22.5, 1.6, 5, "MetalDark")
		kit:pillar(X(-6), -22.5, 1.6, 5, "MetalDark")
		kit:ramp("CatwalkRamp", X(-56), -25, X(-40), -20, 0, 6, rampDir, "Grate")
		kit:trim(X(-40), -25.5, X(0), -25.3, 5.2, CYAN)
		kit:crate(X(-30), -36)
		kit:crate(X(-30), -36, 4)
		kit:crate(X(-14), -40)
		kit:crate(X(-8), -30, 0, 4, "CrateWood", 20)
		kit:cover(X(-48), -40, X(-44), -32, 3.6)
		kit:lamp(X(-24), -32, 12, ORANGE)
		kit:trim(X(-72), -45.2, X(-8), -45, 6, ORANGE)

		-- Callouts
		kit:callout(if sx == 1 then "WEST DOCK" else "EAST DOCK", X(-72), -24, X(-56), 24)
		kit:callout(if sx == 1 then "WEST RAMP" else "EAST RAMP", X(-23), 0.5, X(-7), 6, -4, 7)
		kit:callout(if sx == 1 then "W CONNECTOR" else "E CONNECTOR", X(-36), 12, X(-25), 20)
		kit:callout(if sx == 1 then "STACKS W" else "STACKS E", X(-52), 34, X(-28), 46)
	end

	kit:callout("YARD", -56, -16, 56, 16, -4, 6.5)
	kit:callout("TOWER", -7, -7, 7, 7, 6.5, 30)
	kit:callout("CONTAINERS", -72, 16, 72, 46, -4, 7.5)
	kit:callout("CONTAINER TOP", -56, 16, 56, 46, 7.5, 30)
	kit:callout("CATWALK", -40, -25.5, 40, -19.5, 5.5, 30)
	kit:callout("WINDOW", -6, -26, 6, -15, 5.5, 30)
	kit:callout("UNDERPASS", -40, -26, 40, -19, -4, 5.5)
	kit:callout("SOUTH LANE", -72, -46, 72, -16, -4, 30)

	kit:sign("KESTREL YARD", 0, 16, 45, 30, 4, "-Z", ORANGE)
	kit:sign("SECTOR 7 — FREIGHT", 0, 12, -45, 26, 3, "+Z", AMBER)
end

return {
	id = "kestrel",
	build = build,
	intro = {
		CFrame.lookAt(Vector3.new(70, 45, 60), Vector3.new(0, 6, 0)),
		CFrame.lookAt(Vector3.new(0, 30, 70), Vector3.new(0, 6, 10)),
		CFrame.lookAt(Vector3.new(-60, 20, 20), Vector3.new(0, 8, 0)),
		CFrame.lookAt(Vector3.new(-30, 14, -30), Vector3.new(0, 9, 0)),
	},
	overview = CFrame.lookAt(Vector3.new(0, 110, -70), Vector3.new(0, 0, 0)),
}
