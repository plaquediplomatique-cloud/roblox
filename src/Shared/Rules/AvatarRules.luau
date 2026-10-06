--!strict
--[[
	AvatarRules — ce que l'avatar Roblox du joueur garde en combat.

	Les hitboxes sont fixes (Shared/Combat/Hitbox) ; l'avatar n'est qu'une apparence. Pour
	que l'apparence ne mente pas sur la hitbox ni ne trahisse un joueur derrière un couvert,
	les accessoires volumineux sont retirés en match et au stand de tir (le hub garde tout) :
	  * emplacements retirés : dos, taille, épaules, devant (ailes, épées, capes…),
	  * accessoires conservés : chapeau, cheveux, visage, cou, s'ils restent compacts.
]]

local AvatarRules = {}

AvatarRules.DEFAULT_OPERATOR = "op_standard"

-- Champs de HumanoidDescription vidés hors hub.
AvatarRules.MATCH_REMOVED_SLOTS = {
	"BackAccessory",
	"WaistAccessory",
	"ShouldersAccessory",
	"FrontAccessory",
}

-- Types d'accessoires retirés hors hub (Accessory.AccessoryType.Name).
AvatarRules.BULKY_TYPES = { Back = true, Waist = true, Shoulder = true, Front = true }

-- Taille maximale de la poignée d'un accessoire conservé en combat (studs).
AvatarRules.MAX_ACCESSORY_EXTENT = 2.6
AvatarRules.MAX_ACCESSORY_VOLUME = 6

function AvatarRules.oversized(size: Vector3): boolean
	local extent = math.max(size.X, size.Y, size.Z)
	return extent > AvatarRules.MAX_ACCESSORY_EXTENT or size.X * size.Y * size.Z > AvatarRules.MAX_ACCESSORY_VOLUME
end

return AvatarRules
