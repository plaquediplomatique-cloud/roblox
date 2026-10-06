--!strict
--[[
	ShopService — tout ce qui se dépense ou se débloque : améliorations, zones, décor,
	coffres, Ascension, déplacements, réglages. Chaque remote ne transporte qu'un identifiant :
	prix, niveau requis et plafonds sont recalculés ici depuis la Config.
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Net = require(Shared.Net.Net)
local Upgrades = require(Shared.Rules.Upgrades)
local Ascension = require(Shared.Rules.Ascension)
local Loot = require(Shared.Rules.Loot)
local WeaponCatalog = require(Shared.Rules.WeaponCatalog)
local ZoneLayout = require(Shared.Rules.ZoneLayout)
local BaseLayout = require(Shared.Rules.BaseLayout)
local Decor = require(Shared.Config.Decor)
local Zones = require(Shared.Config.Zones)
local LootConfig = require(Shared.Config.Loot)
local NumberFormat = require(Shared.Rules.NumberFormat)
local GameEvents = require(script.Parent.Parent.GameEvents)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local PlayerService = require(script.Parent.PlayerService)
local ProgressionService = require(script.Parent.ProgressionService)
local WeaponService = require(script.Parent.WeaponService)
local BaseService = require(script.Parent.BaseService)

type State = PlayerService.State

local ShopService = {}

local SETTINGS = { Music = true, Sfx = true, Shake = true, DamageNumbers = true }
local lastTravel: { [Player]: number } = {}

local function fail(state: State, text: string)
	ProgressionService.notify(state, "Error", text)
end

function ShopService.buyUpgrade(state: State, id: string)
	local profile = state.Profile
	local level = profile.Upgrades[id]
	if level == nil then
		return
	end
	local check = Upgrades.check(id, level, profile.Coins)
	if not check.Ok then
		fail(state, check.Reason or "Cannot buy")
		return
	end
	if not ProgressionService.spendCoins(state, check.Cost :: number) then
		return
	end
	profile.Upgrades[id] = check.NewLevel :: number
	PlayerService.invalidateFighter(state)
	PlayerService.mark(state, "Upgrades")
	GameEvents.UpgradeBought:Fire(state, id, check.NewLevel :: number)
end

function ShopService.unlockZone(state: State, id: string): boolean
	local zone = Zones.ById[id]
	local profile = state.Profile
	if not zone or profile.Zones[id] then
		return profile.Zones[id] == true
	end
	if profile.Level < zone.MinLevel then
		fail(state, ("%s unlocks at level %d"):format(zone.Name, zone.MinLevel))
		return false
	end
	-- Les zones se débloquent dans l'ordre (pas de saut de contenu).
	local previous = Zones.List[zone.Index - 1]
	if previous and not profile.Zones[previous.Id] then
		fail(state, "Unlock " .. previous.Name .. " first")
		return false
	end
	if not ProgressionService.spendCoins(state, zone.UnlockCoins) then
		fail(state, ("Need %s coins"):format(NumberFormat.compact(zone.UnlockCoins)))
		return false
	end
	profile.Zones[id] = true
	PlayerService.mark(state, "Zones")
	GameEvents.ZoneUnlocked:Fire(state, id)
	ProgressionService.notify(state, "Zone", zone.Name .. " unlocked!", { id = id })
	return true
end

function ShopService.travel(state: State, id: string)
	local player = state.Player
	local now = os.clock()
	if now - (lastTravel[player] or 0) < 1.5 then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return
	end
	if id == "Home" then
		lastTravel[player] = now
		character:PivotTo(BaseService.spawnCFrame(state))
		return
	end
	local zone = Zones.ById[id]
	if not zone or not state.Profile.Zones[id] then
		fail(state, "Zone locked")
		return
	end
	lastTravel[player] = now
	character:PivotTo(ZoneLayout.spawn(zone.Index))
end

-- Portail : débloque si possible (péage), puis téléporte.
function ShopService.interact(player: Player, id: string)
	local state = PlayerService.get(player)
	if not state then
		return
	end
	if id ~= "Home" and not state.Profile.Zones[id] then
		if not ShopService.unlockZone(state, id) then
			return
		end
	end
	ShopService.travel(state, id)
end

function ShopService.ascend(state: State)
	local ok, reason = Ascension.canAscend(state.Profile)
	if not ok then
		fail(state, reason or "Cannot ascend")
		return
	end
	Ascension.apply(state.Profile)
	PlayerService.invalidateFighter(state)
	state.Combo.Count = 0
	GameEvents.Ascended:Fire(state)
	PlayerService.mark(state, "Level", "XP", "Zones", "Weapons", "Stars", "Stats", "Equipped")
	lastTravel[state.Player] = 0 -- le retour à la base n'est jamais bloqué par le délai de téléportation
	ProgressionService.notify(state, "Rare", ("ASCENSION %d!"):format(state.Profile.Stars), {
		l = { "+10% XP, +10% coins, +25% damage per star" },
	})
	ShopService.travel(state, "Home")
end

function ShopService.openChest(state: State, chestId: string)
	local chest = LootConfig.ById[chestId]
	local chests = state.Profile.Chests
	if not chest or (chests[chestId] or 0) < 1 then
		fail(state, "No chest to open")
		return
	end
	-- Tirage d'abord (sans effet de bord), débit ensuite : une erreur ne consomme jamais le coffre.
	-- Pas de butin plus puissant que la progression : palier de la meilleure arme principale + 2.
	local best = WeaponCatalog.bestOwned(state.Profile.Weapons)
	local drop = Loot.rollChest(chestId, state.Profile.Weapons, best.Tier + 2, math.random)
	chests[chestId] -= 1
	PlayerService.mark(state, "Chests")
	local payload: { [string]: any } = { id = chestId }
	if drop.Kind == "Weapon" then
		WeaponService.grant(state, drop.WeaponId, "Chest")
		payload.kind = "Weapon"
		payload.weapon = drop.WeaponId
	else
		local lines = ProgressionService.grant(state, { Coins = drop.Minutes }, chest.Name)
		payload.kind = "Coins"
		payload.text = lines[1]
	end
	Net.event("ChestResult"):FireClient(state.Player, payload)
end

function ShopService.buyDecor(state: State, id: string)
	local item = Decor.ById[id]
	local profile = state.Profile
	if not item or profile.Base.Owned[id] then
		return
	end
	if profile.Level < item.MinLevel then
		fail(state, ("Unlocks at level %d"):format(item.MinLevel))
		return
	end
	if not ProgressionService.spendCoins(state, item.Cost) then
		fail(state, ("Need %s coins"):format(NumberFormat.compact(item.Cost)))
		return
	end
	profile.Base.Owned[id] = true
	PlayerService.mark(state, "Base")
end

function ShopService.placeDecor(state: State, slotId: string, itemId: string?)
	local profile = state.Profile
	local index = BaseLayout.slotIndex(slotId)
	if not index or index > BaseLayout.slotLimit(PlayerService.hasPass(state, "ExtraPlot")) then
		fail(state, "Slot not available")
		return
	end
	if itemId ~= nil and not profile.Base.Owned[itemId] then
		return
	end
	if itemId then
		profile.Base.Slots[slotId] = itemId
	else
		profile.Base.Slots[slotId] = nil
	end
	PlayerService.mark(state, "Base")
	GameEvents.DecorChanged:Fire(state)
end

function ShopService.start()
	ServerNet.on("BuyUpgrade", function(player, payload)
		local state = PlayerService.get(player)
		if state then
			ShopService.buyUpgrade(state, payload.id)
		end
	end)
	ServerNet.on("UnlockZone", function(player, payload)
		local state = PlayerService.get(player)
		if state then
			ShopService.unlockZone(state, payload.id)
		end
	end)
	ServerNet.on("Teleport", function(player, payload)
		local state = PlayerService.get(player)
		if state then
			ShopService.travel(state, payload.id)
		end
	end)
	ServerNet.on("Equip", function(player, payload)
		local state = PlayerService.get(player)
		if state then
			WeaponService.equip(state, payload.id)
		end
	end)
	ServerNet.on("Ascend", function(player)
		local state = PlayerService.get(player)
		if state then
			ShopService.ascend(state)
		end
	end)
	ServerNet.on("OpenChest", function(player, payload)
		local state = PlayerService.get(player)
		if state then
			ShopService.openChest(state, payload.id)
		end
	end)
	ServerNet.on("BuyDecor", function(player, payload)
		local state = PlayerService.get(player)
		if state then
			ShopService.buyDecor(state, payload.id)
		end
	end)
	ServerNet.on("PlaceDecor", function(player, payload)
		local state = PlayerService.get(player)
		if state then
			ShopService.placeDecor(state, payload.slot, payload.id)
		end
	end)
	ServerNet.on("SetSetting", function(player, payload)
		local state = PlayerService.get(player)
		if state and SETTINGS[payload.key] ~= nil then
			(state.Profile.Settings :: any)[payload.key] = payload.value
			PlayerService.mark(state, "Settings")
		end
	end)
	ServerNet.on("RequestSync", function(player)
		local state = PlayerService.get(player)
		if state then
			PlayerService.fullSync(state)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastTravel[player] = nil
	end)
end

return ShopService
