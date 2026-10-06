--!strict
--[[
	StoreService — boutique (achats en Flux) et récupération des paliers du Pass.
	Point d'entrée unique du remote ShopAction (évite toute dépendance circulaire
	entre inventaire et progression).
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Guard = require(Shared.Util.Guard)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local InventoryService = require(script.Parent.InventoryService)
local ProgressionService = require(script.Parent.ProgressionService)

type ShopAction = { action: string, item: string?, tier: number?, track: string? }

local isAction = Guard.shape({
	action = Guard.oneOf({ "Buy", "ClaimPass" }),
	item = Guard.optional(Guard.string(48)),
	tier = Guard.optional(Guard.integer(1, 50)),
	track = Guard.optional(Guard.oneOf({ "free", "premium" })),
})

local StoreService = {}

function StoreService.Init() end

function StoreService.Start()
	ServerNet.onInvoke("ShopAction", { capacity = 6, refill = 2 }, function(payload: any): ShopAction?
		return if isAction(payload) then payload :: ShopAction else nil
	end, function(player: Player, request: ShopAction): ServerNet.Response
		if request.action == "Buy" and request.item then
			return InventoryService.purchase(player, request.item)
		elseif request.action == "ClaimPass" and request.tier and request.track then
			return ProgressionService.claimPass(player, request.tier, if request.track == "premium" then "premium" else "free")
		end
		return ServerNet.failure("Requête invalide")
	end)
end

return StoreService
