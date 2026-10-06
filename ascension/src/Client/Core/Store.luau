--!strict
--[[
	Store — réplique client du profil, alimentée par les `Sync` du serveur.

	Lecture seule : l'interface AFFICHE ce que le serveur a décidé. Les valeurs dérivées
	(dégâts, puissance, cadence) sont recalculées avec les mêmes règles pures que le serveur
	(Rules/Fighter + Rules/Combat), donc jamais de désaccord entre l'écran et la réalité.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Net = require(Shared.Net.Net)
local Signal = require(Shared.Util.Signal)
local Fighter = require(Shared.Rules.Fighter)
local Combat = require(Shared.Rules.Combat)
local WeaponCatalog = require(Shared.Rules.WeaponCatalog)

local Store = {}

Store.Data = {} :: any
Store.Passes = {} :: { [string]: boolean }
Store.Ready = false
Store.Changed = Signal.new() :: Signal.Signal<string> -- clé du profil modifiée
Store.ReadySignal = Signal.new() :: Signal.Signal<>

local cachedFighter: Combat.Fighter? = nil
local FIGHTER_KEYS = { Equipped = true, Upgrades = true, Stars = true }

function Store.start()
	Net.event("Sync").OnClientEvent:Connect(function(payload: { [string]: any })
		local data = Store.Data
		local full = payload.Full == true
		for key, value in payload do
			if key == "Passes" then
				Store.Passes = value
			elseif key ~= "Full" then
				data[key] = value
				if FIGHTER_KEYS[key] then
					cachedFighter = nil
				end
			end
		end
		if full and not Store.Ready then
			Store.Ready = true
			Store.ReadySignal:Fire()
		end
		for key in payload do
			if key ~= "Full" then
				Store.Changed:Fire(key)
			end
		end
	end)
	Net.event("RequestSync"):FireServer({})
end

function Store.waitReady()
	if not Store.Ready then
		Store.ReadySignal:Wait()
	end
end

function Store.fighter(): Combat.Fighter
	local cached = cachedFighter
	if cached then
		return cached
	end
	local fighter = Fighter.fromProfile(Store.Data)
	cachedFighter = fighter
	return fighter
end

function Store.weapon(): WeaponCatalog.Weapon
	return Fighter.weapon(Store.Data)
end

function Store.power(): number
	return Combat.powerRating(Store.fighter())
end

function Store.damage(): number
	return Combat.baseDamage(Store.fighter())
end

function Store.swingInterval(): number
	return Combat.swingInterval(Store.fighter())
end

function Store.settings(): { Music: boolean, Sfx: boolean, Shake: boolean, DamageNumbers: boolean }
	local settings = Store.Data.Settings
	return settings or { Music = true, Sfx = true, Shake = true, DamageNumbers = true }
end

return Store
