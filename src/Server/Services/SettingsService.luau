--!strict
--[[
	SettingsService — sauvegarde des réglages joueur.

	Le client applique ses réglages instantanément puis envoie le bloc complet (throttlé
	côté client, rate-limité côté serveur). Le serveur valide CHAQUE champ (bornes,
	énumérations, couleurs hex, touches valides) via Settings.validate avant d'écrire :
	un client modifié ne peut pas corrompre un profil.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local Settings = require(Shared.Config.Settings)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local PlayerService = require(script.Parent.PlayerService)

local SettingsService = {}

function SettingsService.Init() end

function SettingsService.Start()
	ServerNet.onEvent("SettingsSave", { capacity = 3, refill = 0.5 }, function(payload: any): Types.SettingsData?
		return if Settings.validate(payload) then payload :: Types.SettingsData else nil
	end, function(player: Player, settings: Types.SettingsData)
		PlayerService.set(player, { "Settings" }, settings)
	end)
end

return SettingsService
