--!strict
--[[
	SettingsController — réglages joueur côté client.

	Application INSTANTANÉE (le joueur voit l'effet en direct dans le menu), puis
	sauvegarde serveur regroupée (debounce 1.5 s) : un slider manipulé ne génère
	qu'un seul envoi. À la connexion, les réglages du profil remplacent les défauts.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Settings = require(Shared.Config.Settings)
local Signal = require(Shared.Util.Signal)
local Net = require(Shared.Net.Net)
local ReplicaPath = require(Shared.Replica.ReplicaPath)
local ClientState = require(script.Parent.Parent.Core.ClientState)

local SettingsController = {
	Changed = Signal.new() :: Signal.Signal<Types.SettingsData>,
}

local current: Types.SettingsData = Settings.defaults()
local saveToken = 0

function SettingsController.get(): Types.SettingsData
	return current
end

--[[ Modifie les réglages via une fonction ; applique et planifie la sauvegarde. ]]
function SettingsController.update(mutator: (Types.SettingsData) -> ())
	local copy = ReplicaPath.deepCopy(current)
	mutator(copy)
	if not Settings.validate(copy) then
		return
	end
	current = copy
	SettingsController.Changed:Fire(current)
	saveToken += 1
	local token = saveToken
	task.delay(1.5, function()
		if token == saveToken then
			Net.event("SettingsSave"):FireServer(current)
		end
	end)
end

function SettingsController.reset()
	SettingsController.update(function(settings)
		local defaults = Settings.defaults()
		settings.Controls = defaults.Controls
		settings.Crosshair = defaults.Crosshair
		settings.Video = defaults.Video
		settings.Audio = defaults.Audio
		settings.Hud = defaults.Hud
		settings.Keybinds = defaults.Keybinds
	end)
end

function SettingsController.start()
	ClientState.ProfileReady:Connect(function(replica)
		local data = replica.data :: Types.ProfileData
		if Settings.validate(data.Settings) then
			current = ReplicaPath.deepCopy(data.Settings)
			SettingsController.Changed:Fire(current)
		end
	end)
end

return SettingsController
