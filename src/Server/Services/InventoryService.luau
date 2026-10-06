--!strict
--[[
	InventoryService — inventaire, équipement et monnaie douce (Flux).

	Toutes les validations sont serveur : on ne peut équiper que ce qu'on possède, un
	skin ne s'applique qu'à son arme, une arme qu'à son emplacement. Les écritures passent
	par le replica du profil (répliquées + sauvegardées). Les armes sont toutes
	débloquées : seuls les cosmétiques se possèdent (aucun pay-to-win).
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local Weapons = require(Shared.Config.Weapons)
local Cosmetics = require(Shared.Config.Cosmetics)
local Guard = require(Shared.Util.Guard)
local Logger = require(Shared.Util.Logger)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local DataService = require(script.Parent.DataService)
local PlayerService = require(script.Parent.PlayerService)

local log = Logger.new("Inventory")

local InventoryService = {}

function InventoryService.owns(player: Player, itemId: string): boolean
	local data = DataService.getData(player)
	return data ~= nil and data.Inventory[itemId] == true
end

--[[ Octroie un objet (récompense, achat). Renvoie false si déjà possédé ou inconnu. ]]
function InventoryService.grant(player: Player, itemId: string): boolean
	local item = Cosmetics.get(itemId)
	if not item or InventoryService.owns(player, itemId) then
		return false
	end
	PlayerService.set(player, { "Inventory", itemId }, true)
	PlayerService.notify(player, "Reward", item.displayName, { item = itemId, rarity = item.rarity })
	log:debug("grant", player.Name, itemId)
	return true
end

function InventoryService.addFlux(player: Player, amount: number)
	if amount ~= 0 then
		PlayerService.increment(player, { "Currency", "Flux" }, amount)
	end
end

function InventoryService.addCrystals(player: Player, amount: number)
	if amount ~= 0 then
		PlayerService.increment(player, { "Currency", "Crystals" }, amount)
	end
end

--[[ Achat en Flux (prix défini par la rareté ; les Mythic ne s'achètent pas). ]]
function InventoryService.purchase(player: Player, itemId: string): ServerNet.Response
	local data = DataService.getData(player)
	local item = Cosmetics.get(itemId)
	if not (data and item) then
		return ServerNet.failure("Objet inconnu")
	end
	if item.price == nil then
		return ServerNet.failure("Objet non disponible à l'achat")
	end
	if data.Inventory[itemId] then
		return ServerNet.failure("Déjà possédé")
	end
	if data.Currency.Flux < item.price then
		return ServerNet.failure("Flux insuffisants")
	end
	InventoryService.addFlux(player, -item.price)
	InventoryService.grant(player, itemId)
	return ServerNet.success({ item = itemId })
end

type InventoryAction = {
	action: string,
	slot: string?,
	weapon: string?,
	item: string?,
	index: number?,
}

local isAction = Guard.shape({
	action = Guard.oneOf({ "EquipWeapon", "EquipSkin", "EquipCosmetic", "SetEmote" }),
	slot = Guard.optional(Guard.oneOf({ "Primary", "Secondary", "Melee" })),
	weapon = Guard.optional(Guard.string(16)),
	item = Guard.optional(Guard.string(48)),
	index = Guard.optional(Guard.integer(1, 4)),
})

local function handle(player: Player, request: InventoryAction): ServerNet.Response
	local data = DataService.getData(player)
	if not data then
		return ServerNet.failure("Profil non chargé")
	end
	if request.action == "EquipWeapon" then
		local slot, weapon = request.slot, request.weapon
		if not (slot and weapon) or not Weapons.isValidForSlot(weapon, slot :: Types.WeaponSlot) then
			return ServerNet.failure("Arme invalide pour cet emplacement")
		end
		PlayerService.set(player, { "Loadout", slot }, weapon)
		return ServerNet.success()
	elseif request.action == "EquipSkin" then
		local weapon, item = request.weapon, request.item
		local skin = if item then Cosmetics.get(item) else nil
		if not (weapon and skin and skin.kind == "WeaponSkin" and skin.weaponId == weapon) then
			return ServerNet.failure("Skin invalide")
		end
		if not data.Inventory[skin.id] then
			return ServerNet.failure("Skin non possédé")
		end
		PlayerService.set(player, { "Cosmetics", "WeaponSkins", weapon }, skin.id)
		return ServerNet.success()
	elseif request.action == "EquipCosmetic" then
		local item = if request.item then Cosmetics.get(request.item) else nil
		if not item or not data.Inventory[item.id] then
			return ServerNet.failure("Objet non possédé")
		end
		local field = if item.kind == "Operator"
			then "Operator"
			elseif item.kind == "KillEffect" then "KillEffect"
			elseif item.kind == "Banner" then "Banner"
			elseif item.kind == "Title" then "Title"
			else nil
		if not field then
			return ServerNet.failure("Type d'objet non équipable ici")
		end
		PlayerService.set(player, { "Cosmetics", field }, item.id)
		PlayerService.refreshPublic(player)
		return ServerNet.success()
	elseif request.action == "SetEmote" then
		local item = if request.item then Cosmetics.get(request.item) else nil
		local index = request.index
		if not (item and index and item.kind == "Emote" and data.Inventory[item.id]) then
			return ServerNet.failure("Emote invalide")
		end
		PlayerService.set(player, { "Cosmetics", "Emotes", index }, item.id)
		return ServerNet.success()
	end
	return ServerNet.failure("Action inconnue")
end

function InventoryService.Init() end

function InventoryService.Start()
	ServerNet.onInvoke("InventoryAction", { capacity = 8, refill = 4 }, function(payload: any): InventoryAction?
		return if isAction(payload) then payload :: InventoryAction else nil
	end, handle)
end

return InventoryService
