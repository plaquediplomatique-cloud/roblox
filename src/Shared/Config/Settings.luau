--!strict
--[[
	Settings — valeurs par défaut, bornes et validation des paramètres joueur.

	Les réglages sont stockés dans le profil (DataService) et sauvegardés côté serveur :
	ils suivent le joueur sur tous les appareils. Le client applique immédiatement
	(aucune latence perçue), puis envoie une sauvegarde throttlée ; le serveur revalide
	CHAQUE champ (Guard) avant écriture : impossible d'injecter des valeurs hors bornes.
]]

local Types = require(script.Parent.Parent.Types)
local Guard = require(script.Parent.Parent.Util.Guard)

local Settings = {}

Settings.CROSSHAIR_STYLES = { "Classic", "Dot", "Circle", "TShape" }
Settings.ENEMY_COLORS = { "Red", "Yellow", "Purple" }
Settings.ACTIONS = {
	"Fire",
	"Aim",
	"Reload",
	"Jump",
	"Crouch",
	"Sprint",
	"Walk",
	"LeanLeft",
	"LeanRight",
	"Primary",
	"Secondary",
	"Melee",
	"Inspect",
	"Interact",
	"Scoreboard",
	"Menu",
	"Options",
	"Emote",
}

function Settings.defaults(): Types.SettingsData
	return {
		Controls = {
			Sensitivity = 0.4,
			AdsMultiplier = 1.0,
			ScopeMultiplier = 1.0,
			InvertY = false,
			ToggleAds = false,
			ToggleCrouch = false,
			ToggleWalk = false,
			ToggleSprint = false,
			LeanEnabled = true,
			AutoReload = true,
		},
		Crosshair = {
			Style = "Classic",
			Color = "#3DE1FF",
			Opacity = 1,
			Thickness = 2,
			Length = 6,
			Gap = 4,
			Outline = true,
			OutlineThickness = 1,
			OutlineOpacity = 0.6,
			Dot = false,
			DotSize = 2,
			Dynamic = true,
		},
		Video = {
			Fov = 78,
			Bloom = true,
			DepthOfField = true,
			SunRays = true,
			CameraShake = 1,
			HeadBob = 1,
			ViewmodelBob = 1,
			ShowFps = false,
			ReducedFlashes = false,
			Weather = true,
		},
		Audio = {
			Master = 0.7,
			Music = 0.45,
			Sfx = 1,
			Ui = 0.8,
			HitSound = true,
			KillSound = true,
		},
		Hud = {
			Scale = 1,
			DamageNumbers = true,
			Hitmarkers = true,
			Compass = true,
			NetStats = false,
			EnemyColor = "Red",
			Killcam = true,
		},
		Keybinds = {
			Fire = "MouseButton1",
			Aim = "MouseButton2",
			Reload = "R",
			Jump = "Space",
			Crouch = "LeftControl",
			Sprint = "LeftShift",
			Walk = "LeftAlt",
			LeanLeft = "Q",
			LeanRight = "E",
			Primary = "One",
			Secondary = "Two",
			Melee = "Three",
			Inspect = "Y",
			Interact = "F",
			Scoreboard = "Tab",
			Menu = "M",
			Options = "P",
			Emote = "B",
		},
	}
end

local validKey = function(value: any): boolean
	if type(value) ~= "string" or #value > 24 then
		return false
	end
	if value == "MouseButton1" or value == "MouseButton2" or value == "MouseButton3" then
		return true
	end
	local ok, result = pcall(function()
		return (Enum.KeyCode :: any)[value]
	end)
	return ok and result ~= nil
end

local actionCheck = Guard.oneOf(Settings.ACTIONS)

Settings.validate = Guard.shape({
	Controls = Guard.shape({
		Sensitivity = Guard.range(0.02, 5),
		AdsMultiplier = Guard.range(0.2, 2),
		ScopeMultiplier = Guard.range(0.2, 2),
		InvertY = Guard.boolean,
		ToggleAds = Guard.boolean,
		ToggleCrouch = Guard.boolean,
		ToggleWalk = Guard.boolean,
		ToggleSprint = Guard.boolean,
		LeanEnabled = Guard.boolean,
		AutoReload = Guard.boolean,
	}),
	Crosshair = Guard.shape({
		Style = Guard.oneOf(Settings.CROSSHAIR_STYLES),
		Color = Guard.hexColor,
		Opacity = Guard.range(0.1, 1),
		Thickness = Guard.range(1, 6),
		Length = Guard.range(0, 20),
		Gap = Guard.range(0, 20),
		Outline = Guard.boolean,
		OutlineThickness = Guard.range(0, 3),
		OutlineOpacity = Guard.range(0, 1),
		Dot = Guard.boolean,
		DotSize = Guard.range(1, 8),
		Dynamic = Guard.boolean,
	}),
	Video = Guard.shape({
		Fov = Guard.range(60, 95),
		Bloom = Guard.boolean,
		DepthOfField = Guard.boolean,
		SunRays = Guard.boolean,
		CameraShake = Guard.range(0, 1.5),
		HeadBob = Guard.range(0, 1.5),
		ViewmodelBob = Guard.range(0, 1.5),
		ShowFps = Guard.boolean,
		ReducedFlashes = Guard.boolean,
		Weather = Guard.boolean,
	}),
	Audio = Guard.shape({
		Master = Guard.range(0, 1),
		Music = Guard.range(0, 1),
		Sfx = Guard.range(0, 1),
		Ui = Guard.range(0, 1),
		HitSound = Guard.boolean,
		KillSound = Guard.boolean,
	}),
	Hud = Guard.shape({
		Scale = Guard.range(0.7, 1.3),
		DamageNumbers = Guard.boolean,
		Hitmarkers = Guard.boolean,
		Compass = Guard.boolean,
		NetStats = Guard.boolean,
		EnemyColor = Guard.oneOf(Settings.ENEMY_COLORS),
		Killcam = Guard.boolean,
	}),
	Keybinds = Guard.dictionary(actionCheck, validKey, #Settings.ACTIONS),
})

function Settings.parseHex(hex: string): Color3
	local r = tonumber(string.sub(hex, 2, 3), 16) or 255
	local g = tonumber(string.sub(hex, 4, 5), 16) or 255
	local b = tonumber(string.sub(hex, 6, 7), 16) or 255
	return Color3.fromRGB(r, g, b)
end

function Settings.toHex(color: Color3): string
	return string.format(
		"#%02X%02X%02X",
		math.floor(color.R * 255 + 0.5),
		math.floor(color.G * 255 + 0.5),
		math.floor(color.B * 255 + 0.5)
	)
end

function Settings.enemyColor(name: string): Color3
	if name == "Yellow" then
		return Color3.fromRGB(255, 225, 60)
	elseif name == "Purple" then
		return Color3.fromRGB(200, 90, 255)
	end
	return Color3.fromRGB(255, 70, 85)
end

return Settings
