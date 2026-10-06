--!strict
--[[
	WeaponModels — modèles d'armes PROCÉDURAUX (aucun mesh ni asset requis).

	Chaque arme est décrite par un archétype paramétré (rifle, pistol, revolver, blade)
	qui produit une liste de pièces (blocs, cylindres, boules) + des points d'ancrage :
	bouche (muzzle flash / traceurs), fenêtre d'éjection (douilles), point de visée (ADS),
	mains droite/gauche (bras procéduraux), chargeur et culasse (animations procédurales).

	Repère local de l'arme : racine = poignée (main droite), avant = -Z, haut = +Y.
	Échelle "design" : un fusil d'assaut fait ~3 studs ; le ViewmodelController applique
	une échelle globale (0.6) — en perspective, un objet 2× plus petit et 2× plus proche
	paraît identique mais traverse 2× moins les murs.

	Les rôles de couleur (Base, Secondary, Accent, Neon, Metal, Glass, Grip) sont résolus
	par le skin équipé : un même modèle porte toutes les collections cosmétiques.
]]

local Types = require(script.Parent.Parent.Types)

type ModelPiece = Types.ModelPiece
type ModelSpec = Types.ModelSpec

local WeaponModels = {}

local function piece(
	name: string,
	shape: Types.PieceShape,
	size: Vector3,
	offset: CFrame,
	role: Types.ColorRole,
	animated: boolean?,
	transparency: number?,
	material: Enum.Material?
): ModelPiece
	return {
		name = name,
		shape = shape,
		size = size,
		offset = offset,
		role = role,
		animated = animated,
		transparency = transparency,
		material = material,
	}
end

local function block(
	name: string,
	size: Vector3,
	position: Vector3,
	role: Types.ColorRole,
	rotation: CFrame?
): ModelPiece
	local offset = CFrame.new(position)
	if rotation then
		offset *= rotation
	end
	return piece(name, "Block", size, offset, role)
end

local function cylinder(
	name: string,
	length: number,
	diameter: number,
	position: Vector3,
	role: Types.ColorRole
): ModelPiece
	return piece(name, "Cylinder", Vector3.new(length, diameter, diameter), CFrame.new(position), role)
end

local function rad(degrees: number): number
	return math.rad(degrees)
end

---------------------------------------------------------------------------------------------
-- Viseurs
---------------------------------------------------------------------------------------------

local function addSight(
	pieces: { ModelPiece },
	sight: Types.SightType,
	topY: number,
	z: number,
	frontZ: number
): Vector3
	if sight == "Iron" or sight == "None" then
		table.insert(
			pieces,
			block("RearSight", Vector3.new(0.09, 0.08, 0.04), Vector3.new(0, topY + 0.04, z + 0.12), "Metal")
		)
		table.insert(
			pieces,
			block("RearNotchL", Vector3.new(0.025, 0.05, 0.04), Vector3.new(-0.035, topY + 0.1, z + 0.12), "Metal")
		)
		table.insert(
			pieces,
			block("RearNotchR", Vector3.new(0.025, 0.05, 0.04), Vector3.new(0.035, topY + 0.1, z + 0.12), "Metal")
		)
		table.insert(
			pieces,
			block("FrontPost", Vector3.new(0.022, 0.11, 0.025), Vector3.new(0, topY + 0.055, frontZ), "Metal")
		)
		table.insert(
			pieces,
			block("FrontDot", Vector3.new(0.018, 0.018, 0.01), Vector3.new(0, topY + 0.1, frontZ - 0.002), "Neon")
		)
		return Vector3.new(0, topY + 0.1, z + 0.16)
	elseif sight == "RedDot" then
		table.insert(
			pieces,
			block("SightBase", Vector3.new(0.12, 0.05, 0.18), Vector3.new(0, topY + 0.025, z), "Secondary")
		)
		table.insert(pieces, cylinder("SightTube", 0.22, 0.15, Vector3.new(0, topY + 0.13, z), "Base"))
		local lens = piece(
			"SightLens",
			"Block",
			Vector3.new(0.11, 0.11, 0.01),
			CFrame.new(0, topY + 0.13, z - 0.1),
			"Glass",
			nil,
			0.7
		)
		table.insert(pieces, lens)
		table.insert(
			pieces,
			piece("Reticle", "Ball", Vector3.new(0.014, 0.014, 0.014), CFrame.new(0, topY + 0.13, z - 0.08), "Neon")
		)
		return Vector3.new(0, topY + 0.13, z + 0.12)
	elseif sight == "Holo" then
		table.insert(
			pieces,
			block("SightBase", Vector3.new(0.15, 0.05, 0.24), Vector3.new(0, topY + 0.025, z), "Secondary")
		)
		table.insert(
			pieces,
			block("HoodL", Vector3.new(0.02, 0.15, 0.05), Vector3.new(-0.075, topY + 0.12, z - 0.07), "Base")
		)
		table.insert(
			pieces,
			block("HoodR", Vector3.new(0.02, 0.15, 0.05), Vector3.new(0.075, topY + 0.12, z - 0.07), "Base")
		)
		table.insert(
			pieces,
			block("HoodTop", Vector3.new(0.17, 0.02, 0.05), Vector3.new(0, topY + 0.2, z - 0.07), "Base")
		)
		table.insert(
			pieces,
			piece(
				"SightLens",
				"Block",
				Vector3.new(0.13, 0.13, 0.008),
				CFrame.new(0, topY + 0.12, z - 0.07),
				"Glass",
				nil,
				0.75
			)
		)
		table.insert(
			pieces,
			piece("Reticle", "Ball", Vector3.new(0.012, 0.012, 0.012), CFrame.new(0, topY + 0.12, z - 0.075), "Neon")
		)
		table.insert(
			pieces,
			block("HoloEmitter", Vector3.new(0.05, 0.03, 0.04), Vector3.new(0, topY + 0.065, z + 0.06), "Accent")
		)
		return Vector3.new(0, topY + 0.12, z + 0.14)
	else
		local long = sight == "Scope4x"
		local length = if long then 0.85 else 0.6
		local tubeY = topY + 0.15
		table.insert(
			pieces,
			block("MountF", Vector3.new(0.1, 0.12, 0.06), Vector3.new(0, topY + 0.06, z - length * 0.3), "Metal")
		)
		table.insert(
			pieces,
			block("MountR", Vector3.new(0.1, 0.12, 0.06), Vector3.new(0, topY + 0.06, z + length * 0.3), "Metal")
		)
		table.insert(pieces, cylinder("ScopeTube", length, 0.13, Vector3.new(0, tubeY, z), "Base"))
		table.insert(
			pieces,
			cylinder("ScopeBell", 0.16, 0.21, Vector3.new(0, tubeY, z - length / 2 - 0.06), "Secondary")
		)
		table.insert(
			pieces,
			cylinder("ScopeEye", 0.12, 0.17, Vector3.new(0, tubeY, z + length / 2 + 0.04), "Secondary")
		)
		table.insert(pieces, cylinder("ScopeRing", 0.04, 0.15, Vector3.new(0, tubeY, z - length * 0.1), "Neon"))
		table.insert(pieces, block("Turret", Vector3.new(0.08, 0.06, 0.08), Vector3.new(0, tubeY + 0.09, z), "Metal"))
		table.insert(
			pieces,
			piece(
				"ScopeLens",
				"Block",
				Vector3.new(0.15, 0.15, 0.01),
				CFrame.new(0, tubeY, z + length / 2 + 0.1),
				"Glass",
				nil,
				0.55
			)
		)
		return Vector3.new(0, tubeY, z + length / 2 + 0.16)
	end
end

---------------------------------------------------------------------------------------------
-- Archétype "arme d'épaule" (fusils, SMG, LMG, snipers, DMR, fusils à pompe)
---------------------------------------------------------------------------------------------

export type LongGunParams = {
	receiver: Vector3, -- (largeur, hauteur, longueur)
	handguardLength: number,
	handguardHeight: number,
	barrelLength: number,
	barrelDiameter: number,
	muzzle: "Brake" | "Suppressor" | "Flash" | "None",
	mag: "Straight" | "Curved" | "Box" | "Drum" | "Tube" | "None",
	magSize: Vector3,
	stock: "Full" | "Skeleton" | "Thumbhole" | "None",
	sight: Types.SightType,
	foregrip: boolean,
	bolt: "Handle" | "Lever" | "Pump",
	accentRings: number,
	bipod: boolean?,
}

function WeaponModels.longGun(p: LongGunParams): ModelSpec
	local pieces: { ModelPiece } = {}
	local w, h, l = p.receiver.X, p.receiver.Y, p.receiver.Z
	local receiverFront = 0.3 - l
	local receiverCenterZ = 0.3 - l / 2
	local topY = 0.1 + h / 2

	-- Corps
	table.insert(pieces, block("Receiver", p.receiver, Vector3.new(0, 0.1, receiverCenterZ), "Base"))
	table.insert(
		pieces,
		block(
			"TopCover",
			Vector3.new(w * 0.86, 0.05, l * 0.94),
			Vector3.new(0, topY + 0.025, receiverCenterZ),
			"Secondary"
		)
	)
	table.insert(
		pieces,
		block(
			"SideAccentL",
			Vector3.new(0.012, h * 0.22, l * 0.55),
			Vector3.new(-w / 2 - 0.004, 0.13, receiverCenterZ + 0.08),
			"Neon"
		)
	)
	table.insert(
		pieces,
		block(
			"SideAccentR",
			Vector3.new(0.012, h * 0.22, l * 0.55),
			Vector3.new(w / 2 + 0.004, 0.13, receiverCenterZ + 0.08),
			"Neon"
		)
	)

	-- Garde-main
	local hgL, hgH = p.handguardLength, p.handguardHeight
	local hgCenterZ = receiverFront - hgL / 2
	local hgY = 0.1 + (h - hgH) / 2
	if hgL > 0 then
		table.insert(
			pieces,
			block("Handguard", Vector3.new(w * 1.06, hgH, hgL), Vector3.new(0, hgY, hgCenterZ), "Base")
		)
		table.insert(
			pieces,
			block(
				"HandguardRail",
				Vector3.new(w * 0.7, 0.04, hgL * 0.9),
				Vector3.new(0, hgY + hgH / 2 + 0.02, hgCenterZ),
				"Secondary"
			)
		)
		for index = 1, p.accentRings do
			local z = receiverFront - hgL * (index / (p.accentRings + 1))
			table.insert(
				pieces,
				block("Vent" .. index, Vector3.new(w * 1.08, 0.03, 0.05), Vector3.new(0, hgY - hgH * 0.15, z), "Accent")
			)
		end
	end

	-- Canon et bouche
	local barrelStart = receiverFront - hgL + 0.1
	local barrelCenterZ = barrelStart - p.barrelLength / 2
	local barrelY = 0.1 + h * 0.18
	table.insert(
		pieces,
		cylinder("Barrel", p.barrelLength, p.barrelDiameter, Vector3.new(0, barrelY, barrelCenterZ), "Metal")
	)
	local muzzleZ = barrelStart - p.barrelLength
	if p.muzzle == "Brake" then
		table.insert(
			pieces,
			cylinder("Brake", 0.16, p.barrelDiameter * 1.8, Vector3.new(0, barrelY, muzzleZ - 0.08), "Metal")
		)
		table.insert(
			pieces,
			block(
				"BrakePortL",
				Vector3.new(0.01, 0.04, 0.06),
				Vector3.new(-p.barrelDiameter * 0.92, barrelY, muzzleZ - 0.08),
				"Neon"
			)
		)
		table.insert(
			pieces,
			block(
				"BrakePortR",
				Vector3.new(0.01, 0.04, 0.06),
				Vector3.new(p.barrelDiameter * 0.92, barrelY, muzzleZ - 0.08),
				"Neon"
			)
		)
		muzzleZ -= 0.16
	elseif p.muzzle == "Suppressor" then
		table.insert(
			pieces,
			cylinder("Suppressor", 0.52, p.barrelDiameter * 2.3, Vector3.new(0, barrelY, muzzleZ - 0.26), "Secondary")
		)
		table.insert(
			pieces,
			cylinder("SuppressorRing", 0.03, p.barrelDiameter * 2.35, Vector3.new(0, barrelY, muzzleZ - 0.12), "Neon")
		)
		muzzleZ -= 0.52
	elseif p.muzzle == "Flash" then
		table.insert(
			pieces,
			cylinder("FlashHider", 0.12, p.barrelDiameter * 1.4, Vector3.new(0, barrelY, muzzleZ - 0.06), "Metal")
		)
		muzzleZ -= 0.12
	end

	-- Chargeur
	local magName: string? = nil
	if p.mag == "Straight" or p.mag == "Curved" then
		magName = "Mag"
		local tilt = if p.mag == "Curved" then CFrame.Angles(rad(12), 0, 0) else CFrame.identity
		local magCF = CFrame.new(0, 0.1 - h / 2 - p.magSize.Y / 2 + 0.06, -0.42) * tilt
		table.insert(pieces, piece("Mag", "Block", p.magSize, magCF, "Secondary", true))
	elseif p.mag == "Box" then
		magName = "Mag"
		table.insert(
			pieces,
			piece(
				"Mag",
				"Block",
				p.magSize,
				CFrame.new(0, 0.1 - h / 2 - p.magSize.Y / 2 + 0.05, -0.38),
				"Secondary",
				true
			)
		)
		table.insert(
			pieces,
			block("Belt", Vector3.new(0.06, 0.05, 0.3), Vector3.new(w / 2 + 0.03, 0.12, -0.38), "Accent")
		)
	elseif p.mag == "Drum" then
		magName = "Mag"
		local drum = piece(
			"Mag",
			"Cylinder",
			Vector3.new(p.magSize.X, p.magSize.Y, p.magSize.Y),
			CFrame.new(0, 0.1 - h / 2 - p.magSize.Y / 2 + 0.04, -0.45) * CFrame.Angles(0, rad(90), 0),
			"Secondary",
			true
		)
		table.insert(pieces, drum)
	elseif p.mag == "Tube" then
		table.insert(
			pieces,
			cylinder(
				"MagTube",
				p.magSize.Z,
				p.magSize.Y,
				Vector3.new(0, barrelY - p.barrelDiameter - 0.02, barrelCenterZ + 0.15),
				"Metal"
			)
		)
	end

	-- Poignée pistolet, pontet, détente
	table.insert(
		pieces,
		block("Grip", Vector3.new(0.15, 0.36, 0.2), Vector3.new(0, -0.16, 0.1), "Grip", CFrame.Angles(rad(-16), 0, 0))
	)
	table.insert(pieces, block("TriggerGuard", Vector3.new(0.04, 0.025, 0.24), Vector3.new(0, -0.08, -0.1), "Metal"))
	table.insert(pieces, block("Trigger", Vector3.new(0.02, 0.07, 0.025), Vector3.new(0, -0.05, -0.08), "Metal"))

	-- Crosse
	if p.stock == "Full" then
		table.insert(pieces, block("Stock", Vector3.new(w * 0.7, h * 0.85, 0.62), Vector3.new(0, 0.06, 0.61), "Base"))
		table.insert(
			pieces,
			block("StockAccent", Vector3.new(w * 0.72, 0.03, 0.45), Vector3.new(0, 0.06 + h * 0.2, 0.6), "Neon")
		)
		table.insert(pieces, block("ButtPad", Vector3.new(w * 0.8, h * 1.05, 0.06), Vector3.new(0, 0.03, 0.94), "Grip"))
	elseif p.stock == "Skeleton" then
		table.insert(pieces, block("StockTop", Vector3.new(0.05, 0.05, 0.6), Vector3.new(0, 0.16, 0.6), "Metal"))
		table.insert(pieces, block("StockBottom", Vector3.new(0.05, 0.05, 0.55), Vector3.new(0, -0.04, 0.58), "Metal"))
		table.insert(pieces, block("ButtPad", Vector3.new(0.12, 0.3, 0.06), Vector3.new(0, 0.06, 0.9), "Grip"))
	elseif p.stock == "Thumbhole" then
		table.insert(pieces, block("StockUpper", Vector3.new(w * 0.75, 0.12, 0.7), Vector3.new(0, 0.14, 0.66), "Base"))
		table.insert(pieces, block("StockLower", Vector3.new(w * 0.75, 0.1, 0.5), Vector3.new(0, -0.12, 0.75), "Base"))
		table.insert(pieces, block("Cheek", Vector3.new(w * 0.6, 0.06, 0.3), Vector3.new(0, 0.23, 0.6), "Accent"))
		table.insert(pieces, block("ButtPad", Vector3.new(w * 0.85, 0.42, 0.07), Vector3.new(0, 0.02, 1.03), "Grip"))
	end

	-- Viseur
	local aim = addSight(pieces, p.sight, topY + 0.05, -0.3, muzzleZ + 0.08)

	-- Culasse / levier / pompe (pièce animée)
	local boltName: string
	if p.bolt == "Pump" then
		boltName = "Pump"
		table.insert(
			pieces,
			piece(
				"Pump",
				"Block",
				Vector3.new(w * 1.15, 0.16, 0.42),
				CFrame.new(0, barrelY - p.barrelDiameter - 0.05, hgCenterZ - 0.1),
				"Grip",
				true
			)
		)
	elseif p.bolt == "Lever" then
		boltName = "Bolt"
		table.insert(
			pieces,
			piece(
				"Bolt",
				"Block",
				Vector3.new(0.18, 0.04, 0.04),
				CFrame.new(w / 2 + 0.09, topY - 0.02, 0.05),
				"Metal",
				true
			)
		)
		table.insert(
			pieces,
			piece(
				"BoltKnob",
				"Ball",
				Vector3.new(0.07, 0.07, 0.07),
				CFrame.new(w / 2 + 0.18, topY - 0.02, 0.05),
				"Accent"
			)
		)
	else
		boltName = "Bolt"
		table.insert(
			pieces,
			piece(
				"Bolt",
				"Block",
				Vector3.new(0.05, 0.05, 0.12),
				CFrame.new(w / 2 + 0.03, topY - 0.04, -0.12),
				"Metal",
				true
			)
		)
	end

	if p.foregrip then
		table.insert(
			pieces,
			block(
				"Foregrip",
				Vector3.new(0.1, 0.3, 0.12),
				Vector3.new(0, hgY - hgH / 2 - 0.15, hgCenterZ + 0.05),
				"Grip"
			)
		)
	end
	if p.bipod then
		table.insert(
			pieces,
			block(
				"BipodL",
				Vector3.new(0.04, 0.04, 0.5),
				Vector3.new(-0.06, hgY - hgH / 2 - 0.03, hgCenterZ - 0.1),
				"Metal"
			)
		)
		table.insert(
			pieces,
			block(
				"BipodR",
				Vector3.new(0.04, 0.04, 0.5),
				Vector3.new(0.06, hgY - hgH / 2 - 0.03, hgCenterZ - 0.1),
				"Metal"
			)
		)
	end

	local leftHandZ = if p.bolt == "Pump" then hgCenterZ - 0.1 else hgCenterZ + 0.05
	local leftHandY = if p.foregrip then hgY - hgH / 2 - 0.12 else hgY - hgH / 2 - 0.02
	return {
		pieces = pieces,
		muzzle = CFrame.new(0, barrelY, muzzleZ),
		ejection = CFrame.new(w / 2 + 0.01, 0.16, -0.2) * CFrame.Angles(0, rad(-90), 0),
		aimPoint = CFrame.new(aim),
		rightHand = CFrame.new(0, -0.1, 0.08),
		leftHand = CFrame.new(0, leftHandY, leftHandZ),
		magPiece = magName,
		boltPiece = boltName,
		worldScale = 0.62,
	}
end

---------------------------------------------------------------------------------------------
-- Archétype pistolet (P-10, MP-6)
---------------------------------------------------------------------------------------------

export type PistolParams = {
	slideLength: number,
	slideHeight: number,
	extendedMag: boolean,
	compensator: boolean,
	frontGrip: boolean,
}

function WeaponModels.pistol(p: PistolParams): ModelSpec
	local pieces: { ModelPiece } = {}
	local slideZ = -p.slideLength / 2 + 0.12
	local slideY = 0.13
	table.insert(
		pieces,
		piece(
			"Slide",
			"Block",
			Vector3.new(0.13, p.slideHeight, p.slideLength),
			CFrame.new(0, slideY, slideZ),
			"Base",
			true
		)
	)
	table.insert(
		pieces,
		block(
			"SlideAccentL",
			Vector3.new(0.01, 0.025, p.slideLength * 0.6),
			Vector3.new(-0.07, slideY + 0.01, slideZ),
			"Neon"
		)
	)
	table.insert(
		pieces,
		block(
			"SlideAccentR",
			Vector3.new(0.01, 0.025, p.slideLength * 0.6),
			Vector3.new(0.07, slideY + 0.01, slideZ),
			"Neon"
		)
	)
	table.insert(
		pieces,
		block(
			"Frame",
			Vector3.new(0.12, 0.08, p.slideLength * 0.85),
			Vector3.new(0, slideY - p.slideHeight / 2 - 0.035, slideZ + 0.04),
			"Secondary"
		)
	)
	table.insert(
		pieces,
		block("Grip", Vector3.new(0.13, 0.42, 0.21), Vector3.new(0, -0.17, 0.1), "Grip", CFrame.Angles(rad(-12), 0, 0))
	)
	table.insert(pieces, block("TriggerGuard", Vector3.new(0.035, 0.025, 0.2), Vector3.new(0, -0.06, -0.08), "Metal"))
	table.insert(pieces, block("Trigger", Vector3.new(0.02, 0.06, 0.02), Vector3.new(0, -0.03, -0.06), "Metal"))
	local muzzleZ = slideZ - p.slideLength / 2
	table.insert(pieces, cylinder("BarrelTip", 0.05, 0.06, Vector3.new(0, slideY + 0.01, muzzleZ - 0.02), "Metal"))
	muzzleZ -= 0.05
	if p.compensator then
		table.insert(
			pieces,
			block(
				"Compensator",
				Vector3.new(0.13, p.slideHeight, 0.14),
				Vector3.new(0, slideY, muzzleZ - 0.07),
				"Accent"
			)
		)
		muzzleZ -= 0.14
	end
	local magLength = if p.extendedMag then 0.62 else 0.36
	local magCF = CFrame.new(0, -0.17 - (magLength - 0.36) / 2, 0.11) * CFrame.Angles(rad(-12), 0, 0)
	table.insert(pieces, piece("Mag", "Block", Vector3.new(0.1, magLength, 0.16), magCF, "Secondary", true))
	if p.frontGrip then
		table.insert(
			pieces,
			block("FrontGrip", Vector3.new(0.09, 0.26, 0.11), Vector3.new(0, -0.14, slideZ - 0.12), "Grip")
		)
	end
	local aim = addSight(pieces, "Iron", slideY + p.slideHeight / 2, slideZ + p.slideLength / 2 - 0.16, muzzleZ + 0.06)
	return {
		pieces = pieces,
		muzzle = CFrame.new(0, slideY + 0.01, muzzleZ),
		ejection = CFrame.new(0.07, slideY + 0.04, slideZ + 0.05) * CFrame.Angles(0, rad(-90), 0),
		aimPoint = CFrame.new(aim),
		rightHand = CFrame.new(0, -0.12, 0.1),
		leftHand = if p.frontGrip then CFrame.new(0, -0.2, slideZ - 0.12) else CFrame.new(-0.06, -0.2, 0.06),
		magPiece = "Mag",
		boltPiece = "Slide",
		worldScale = 0.62,
	}
end

---------------------------------------------------------------------------------------------
-- Archétype revolver (R-44)
---------------------------------------------------------------------------------------------

function WeaponModels.revolver(): ModelSpec
	local pieces: { ModelPiece } = {}
	table.insert(pieces, block("Frame", Vector3.new(0.14, 0.2, 0.42), Vector3.new(0, 0.12, -0.12), "Base"))
	table.insert(pieces, cylinder("Barrel", 0.62, 0.1, Vector3.new(0, 0.17, -0.62), "Metal"))
	table.insert(pieces, block("BarrelRib", Vector3.new(0.06, 0.05, 0.62), Vector3.new(0, 0.235, -0.62), "Secondary"))
	table.insert(pieces, block("RibAccent", Vector3.new(0.065, 0.012, 0.5), Vector3.new(0, 0.265, -0.6), "Neon"))
	table.insert(pieces, cylinder("Ejector", 0.4, 0.05, Vector3.new(0, 0.08, -0.55), "Metal"))
	table.insert(
		pieces,
		piece("Drum", "Cylinder", Vector3.new(0.24, 0.27, 0.27), CFrame.new(0, 0.12, -0.13), "Secondary", true)
	)
	table.insert(pieces, block("Hammer", Vector3.new(0.04, 0.08, 0.06), Vector3.new(0, 0.24, 0.1), "Metal"))
	table.insert(
		pieces,
		block("Grip", Vector3.new(0.14, 0.42, 0.2), Vector3.new(0, -0.15, 0.13), "Grip", CFrame.Angles(rad(-22), 0, 0))
	)
	table.insert(
		pieces,
		block(
			"GripAccent",
			Vector3.new(0.145, 0.3, 0.02),
			Vector3.new(0, -0.15, 0.04),
			"Accent",
			CFrame.Angles(rad(-22), 0, 0)
		)
	)
	table.insert(pieces, block("TriggerGuard", Vector3.new(0.035, 0.025, 0.2), Vector3.new(0, -0.04, -0.06), "Metal"))
	local aim = addSight(pieces, "Iron", 0.26, -0.05, -0.88)
	return {
		pieces = pieces,
		muzzle = CFrame.new(0, 0.17, -0.94),
		ejection = CFrame.new(0, 0.12, -0.13),
		aimPoint = CFrame.new(aim),
		rightHand = CFrame.new(0, -0.1, 0.12),
		leftHand = CFrame.new(-0.07, -0.18, 0.08),
		magPiece = "Drum",
		boltPiece = "Hammer",
		worldScale = 0.62,
	}
end

---------------------------------------------------------------------------------------------
-- Archétype lame (Ion Blade)
---------------------------------------------------------------------------------------------

function WeaponModels.blade(): ModelSpec
	local pieces: { ModelPiece } = {}
	table.insert(pieces, cylinder("Handle", 0.34, 0.11, Vector3.new(0, 0, 0.02), "Grip"))
	table.insert(pieces, block("Pommel", Vector3.new(0.12, 0.12, 0.06), Vector3.new(0, 0, 0.2), "Metal"))
	table.insert(pieces, block("Guard", Vector3.new(0.26, 0.06, 0.05), Vector3.new(0, 0, -0.17), "Metal"))
	table.insert(pieces, block("GuardCore", Vector3.new(0.08, 0.07, 0.055), Vector3.new(0, 0, -0.17), "Neon"))
	table.insert(pieces, block("Blade", Vector3.new(0.03, 0.15, 0.62), Vector3.new(0, 0.02, -0.5), "Metal"))
	table.insert(pieces, block("Edge", Vector3.new(0.034, 0.025, 0.56), Vector3.new(0, -0.06, -0.48), "Neon"))
	table.insert(pieces, block("Spine", Vector3.new(0.036, 0.03, 0.4), Vector3.new(0, 0.09, -0.4), "Accent"))
	table.insert(
		pieces,
		piece(
			"Tip",
			"Wedge",
			Vector3.new(0.03, 0.15, 0.16),
			CFrame.new(0, 0.02, -0.89) * CFrame.Angles(0, math.pi, 0),
			"Metal"
		)
	)
	return {
		pieces = pieces,
		muzzle = CFrame.new(0, 0, -0.95),
		ejection = CFrame.new(0, 0, 0),
		aimPoint = CFrame.new(0, 0.1, 0.4),
		rightHand = CFrame.new(0, 0, 0.02),
		leftHand = CFrame.new(-0.35, -0.3, 0.4),
		magPiece = nil,
		boltPiece = nil,
		worldScale = 0.7,
	}
end

return WeaponModels
