--!strict
--[[
	MonetizationService — Game Passes et Developer Products, sans pay-to-win.

	* possession des passes vérifiée côté serveur à l'arrivée et à l'achat ;
	* ProcessReceipt idempotent : l'identifiant d'achat est inscrit dans le profil AVANT de
	  considérer la transaction terminée, puis le profil est sauvegardé immédiatement ;
	* l'XP issue de l'argent réel est plafonnée par les règles (Economy.paidXPMultiplier) ;
	* les cosmétiques n'affectent aucune statistique.
	Les identifiants Roblox sont dans Config/Products (0 = non configuré, achat inactif).
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Products = require(Shared.Config.Products)
local Profile = require(Shared.Rules.Profile)
local Logger = require(Shared.Util.Logger)
local GameEvents = require(script.Parent.Parent.GameEvents)
local PlayerService = require(script.Parent.PlayerService)
local ProgressionService = require(script.Parent.ProgressionService)
local DataService = require(script.Parent.DataService)
local BaseService = require(script.Parent.BaseService)
local CharacterService = require(script.Parent.CharacterService)

local log = Logger.new("Monetization")

local MonetizationService = {}

local function applyPass(state: PlayerService.State, passId: string)
	state.Passes[passId] = true
	local character = state.Player.Character
	if character and passId == "AuraPack" then
		character:SetAttribute("Aura", true)
	end
	if passId == "ExtraPlot" then
		BaseService.refreshDecor(state)
	end
end

function MonetizationService.refreshPasses(state: PlayerService.State)
	for _, pass in Products.Passes do
		if pass.PassId > 0 and not state.Passes[pass.Id] then
			for attempt = 1, 3 do
				local ok, owns = pcall(function()
					return MarketplaceService:UserOwnsGamePassAsync(state.Player.UserId, pass.PassId)
				end)
				if ok then
					if owns then
						applyPass(state, pass.Id)
					end
					break
				end
				task.wait(attempt)
			end
		end
	end
end

local function processReceipt(info: { [string]: any }): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local state = PlayerService.get(player)
	if not state then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local product: Products.DevProduct? = nil
	for _, candidate in Products.Products do
		if candidate.ProductId > 0 and candidate.ProductId == info.ProductId then
			product = candidate
		end
	end
	if not product then
		log:warn("produit inconnu", info.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local receiptId = tostring(info.PurchaseId)
	if not Profile.recordPurchase(state.Profile, receiptId) then
		-- Déjà accordé en mémoire : on ne confirme à Roblox qu'une fois le profil réellement écrit.
		PlayerService.mark(state, "Boosts", "Coins")
		return if DataService.save(player)
			then Enum.ProductPurchaseDecision.PurchaseGranted
			else Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local grant = product.Grant
	if grant.Kind == "XPBoostMinutes" then
		ProgressionService.addXPBoost(state, grant.Value)
	elseif grant.Kind == "CoinMinutes" then
		ProgressionService.grantCoinMinutes(state, grant.Value)
	end
	ProgressionService.notify(state, "Reward", "Thank you!", { l = { product.Name } })
	-- Le reçu n'est considéré comme traité qu'une fois le profil écrit.
	PlayerService.mark(state, "Boosts", "Coins")
	if not DataService.save(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function MonetizationService.start()
	MarketplaceService.ProcessReceipt = processReceipt

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, purchased)
		if not purchased then
			return
		end
		local state = PlayerService.get(player)
		if not state then
			return
		end
		for _, pass in Products.Passes do
			if pass.PassId == gamePassId then
				applyPass(state, pass.Id)
				PlayerService.fullSync(state)
			end
		end
	end)

	-- L'aura (cosmétique) est réappliquée à chaque apparition du personnage.
	CharacterService.onCharacter(function(state, character)
		if state.Passes.AuraPack then
			character:SetAttribute("Aura", true)
		end
	end)

	GameEvents.ProfileLoaded:Connect(function(state)
		task.spawn(function()
			MonetizationService.refreshPasses(state)
			PlayerService.fullSync(state)
		end)
	end)
end

return MonetizationService
