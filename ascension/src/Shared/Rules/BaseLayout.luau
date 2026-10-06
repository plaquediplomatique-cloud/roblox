--!strict
--[[
	BaseLayout — plan des bases (parcelles) autour du village. Pur et testé : aucune
	parcelle ne chevauche une autre, les emplacements de décor restent à l'intérieur,
	loin du mannequin, de l'établi d'armes et du point d'apparition.

	Repère local d'une parcelle : origine = centre du sol, -Z = côté place centrale (entrée),
	+Z = fond. Une parcelle est tournée pour que son -Z regarde le centre du village.
]]

local Game = require(script.Parent.Parent.Config.Game)

local BaseLayout = {}

BaseLayout.PlotSize = 56
BaseLayout.Ring = 150 -- distance centre village -> centre des parcelles
BaseLayout.Count = Game.MaxPlayersPerServer
BaseLayout.Height = 0.5

-- Éléments fixes (repère local).
BaseLayout.Dummy = Vector3.new(0, 0, -2)
BaseLayout.Rack = Vector3.new(0, 0, 22)
BaseLayout.Spawn = Vector3.new(0, 0, -20)

-- 12 emplacements : les 6 premiers sont gratuits, les 6 suivants viennent du Game Pass.
BaseLayout.Slots = {
	{ Id = "S1", Position = Vector3.new(-20, 0, -14) },
	{ Id = "S2", Position = Vector3.new(20, 0, -14) },
	{ Id = "S3", Position = Vector3.new(-21, 0, 6) },
	{ Id = "S4", Position = Vector3.new(21, 0, 6) },
	{ Id = "S5", Position = Vector3.new(-14, 0, 21) },
	{ Id = "S6", Position = Vector3.new(14, 0, 21) },
	{ Id = "S7", Position = Vector3.new(-10, 0, -22) },
	{ Id = "S8", Position = Vector3.new(10, 0, -22) },
	{ Id = "S9", Position = Vector3.new(-22, 0, -3) },
	{ Id = "S10", Position = Vector3.new(22, 0, -3) },
	{ Id = "S11", Position = Vector3.new(-23, 0, 17) },
	{ Id = "S12", Position = Vector3.new(23, 0, 17) },
} :: { { Id: string, Position: Vector3 } }

-- Position/orientation monde d'une parcelle (index 1..Count), centre du village = `center`.
function BaseLayout.plotCFrame(index: number, center: Vector3): CFrame
	local angle = (index - 1) * (2 * math.pi / BaseLayout.Count)
	local position = center + Vector3.new(math.sin(angle) * BaseLayout.Ring, 0, math.cos(angle) * BaseLayout.Ring)
	-- -Z local regarde le centre : +Z local (« arrière ») s'éloigne du centre.
	-- Repère construit à la main (fromMatrix) : identique en jeu et sous Lune.
	local back = (position - center).Unit
	local right = Vector3.yAxis:Cross(back)
	return CFrame.fromMatrix(position, right, Vector3.yAxis, back)
end

function BaseLayout.slotPosition(plot: CFrame, slotId: string): Vector3?
	for _, slot in BaseLayout.Slots do
		if slot.Id == slotId then
			return plot:PointToWorldSpace(slot.Position)
		end
	end
	return nil
end

function BaseLayout.isSlot(slotId: string): boolean
	for _, slot in BaseLayout.Slots do
		if slot.Id == slotId then
			return true
		end
	end
	return false
end

-- Nombre d'emplacements utilisables (6, ou 12 avec le pass).
function BaseLayout.slotLimit(hasExtraPlot: boolean): number
	return if hasExtraPlot then #BaseLayout.Slots else 6
end

function BaseLayout.slotIndex(slotId: string): number?
	for i, slot in BaseLayout.Slots do
		if slot.Id == slotId then
			return i
		end
	end
	return nil
end

return BaseLayout
