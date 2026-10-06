--!strict
--[[
	Menu Réglages — musique, effets, secousse de caméra (accessibilité), nombres de dégâts.
	Enregistrés dans le profil (le serveur ne retient que des booléens connus).
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Net = require(Shared.Net.Net)
local Theme = require(Shared.Config.Theme)
local Store = require(script.Parent.Parent.Core.Store)
local UI = require(script.Parent.Parent.UI.UI)
local Menu = require(script.Parent.Parent.UI.Menu)

local C = Theme.Color

local OPTIONS = {
	{ Key = "Sfx", Title = "Sound effects", Desc = "Hits, rewards and interface sounds." },
	{ Key = "Music", Title = "Music", Desc = "Zone music (when available)." },
	{ Key = "Shake", Title = "Camera shake", Desc = "Screen movement on big hits. Turn off if you feel dizzy." },
	{ Key = "DamageNumbers", Title = "Damage numbers", Desc = "Floating numbers on every hit." },
}

local Module: Menu.MenuModule = {
	Title = "Settings",
	Keys = { "Settings" },
	build = function(content: Frame, _ctx: Menu.Context)
		local settings = Store.settings()
		local column = Menu.column(content)
		for i, option in OPTIONS do
			local on = (settings :: any)[option.Key] == true
			Menu.action(
				column,
				i,
				option.Title,
				option.Desc,
				if on then "ON" else "OFF",
				if on then "good" else "ghost",
				function()
					Net.event("SetSetting"):FireServer({ key = option.Key, value = not on })
				end
			)
		end
		UI.label({
			Text = "Smash Ascension  ·  hit, level up, ascend.",
			TextSize = 14,
			Font = Theme.Font.Body,
			TextColor3 = C.TextDim,
			Size = UDim2.new(1, -8, 0, 30),
			LayoutOrder = 99,
			Parent = column,
		})
	end,
}

return Module
