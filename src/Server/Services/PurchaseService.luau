--!strict
--[[
	PurchaseService — traitement des achats Robux (MarketplaceService.ProcessReceipt).

	Règles d'or (respectées ici) :
	  * IDEMPOTENCE : chaque PurchaseId traité est mémorisé dans le profil ; un reçu
	    rejoué par Roblox n'est jamais accordé deux fois.
	  * On ne renvoie PurchaseGranted qu'APRÈS une sauvegarde réussie du profil : si le
	    serveur plante entre-temps, Roblox rejouera le reçu (NotProcessedYet).
	  * Profil absent (joueur parti, chargement en cours) -> NotProcessedYet.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Products = require(Shared.Config.Products)
local Logger = require(Shared.Util.Logger)
local DataService = require(script.Parent.DataService)
local PlayerService = require(script.Parent.PlayerService)
local InventoryService = require(script.Parent.InventoryService)

local log = Logger.new("Purchase")

local MAX_RECEIPTS = 200

local PurchaseService = {}

local function pruneReceipts(purchases: { [string]: number })
	local count = 0
	local oldestKey: string? = nil
	local oldestTime = math.huge
	for receiptKey, time in purchases do
		count += 1
		if time < oldestTime then
			oldestTime = time
			oldestKey = receiptKey
		end
	end
	if count > MAX_RECEIPTS and oldestKey then
		purchases[oldestKey] = nil
	end
end

local function processReceipt(receipt: { [string]: any }): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local profile = DataService.getProfile(player)
	if not profile then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local purchaseId = tostring(receipt.PurchaseId)
	local purchases = profile.data.Purchases
	if purchases[purchaseId] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local product = Products.byProductId(receipt.ProductId)
	if not product then
		log:warn("produit inconnu", receipt.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local premiumBefore = profile.data.Pass.Premium
	if product.crystals then
		InventoryService.addCrystals(player, product.crystals)
	end
	if product.premiumPass then
		PlayerService.set(player, { "Pass", "Premium" }, true)
	end
	purchases[purchaseId] = os.time()
	pruneReceipts(purchases)
	if not DataService.saveNow(player) then
		-- Annulation COMPLÈTE (reçu + octroi) : Roblox rejouera le reçu. Rien ne doit rester
		-- accordé d'ici là, sinon l'autosave suivante persisterait un achat crédité deux fois.
		purchases[purchaseId] = nil
		if product.crystals then
			InventoryService.addCrystals(player, -product.crystals)
		end
		if product.premiumPass then
			PlayerService.set(player, { "Pass", "Premium" }, premiumBefore)
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	PlayerService.notify(player, "Purchase", product.displayName, { product = product.key })
	log:info("achat accordé", player.Name, product.key)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function PurchaseService.Init() end

function PurchaseService.Start()
	MarketplaceService.ProcessReceipt = processReceipt
end

return PurchaseService
