--!strict
--[[
	Sounds — clés logiques → sons. Le code ne référence JAMAIS un SoundId directement.
	Sons intégrés au client Roblox (rbxasset://) : jouables sans upload ; remplacer `ids`
	par des `rbxassetid://` du sound design final suffit. `pitch` = plage aléatoire (anti-répétition).
	La montée en rareté des armes est gérée par pitch/volume dans AudioController (couches).
]]

export type Def = {
	ids: { string },
	volume: number,
	pitch: NumberRange,
	group: string,
}

local SWISH = "rbxasset://sounds/swordslash.wav"
local LUNGE = "rbxasset://sounds/swordlunge.wav"
local HIT = "rbxasset://sounds/hit.wav"
local SNAP = "rbxasset://sounds/snap.wav"
local CLICK = "rbxasset://sounds/clickfast.wav"
local BUTTON = "rbxasset://sounds/button.wav"
local PING = "rbxasset://sounds/electronicpingshort.wav"
local VICTORY = "rbxasset://sounds/victory.wav"
local BASS = "rbxasset://sounds/bass.wav"
local KERPLUNK = "rbxasset://sounds/kerplunk.wav"

local defs: { [string]: Def } = {
	Swing_Light = { ids = { SWISH }, volume = 0.5, pitch = NumberRange.new(1.15, 1.35), group = "Weapons" },
	Swing_Heavy = { ids = { LUNGE, SWISH }, volume = 0.65, pitch = NumberRange.new(0.75, 0.9), group = "Weapons" },
	Swing_Magic = { ids = { PING, SWISH }, volume = 0.45, pitch = NumberRange.new(0.9, 1.1), group = "Weapons" },
	Hit_Normal = { ids = { HIT, KERPLUNK }, volume = 0.6, pitch = NumberRange.new(0.9, 1.1), group = "Impacts" },
	Hit_Crit = { ids = { SNAP, HIT }, volume = 0.8, pitch = NumberRange.new(0.7, 0.8), group = "Impacts" },
	Hit_Mega = { ids = { BASS, SNAP }, volume = 0.95, pitch = NumberRange.new(0.6, 0.7), group = "Impacts" },
	Combo_Tick = { ids = { CLICK }, volume = 0.35, pitch = NumberRange.new(1, 1.6), group = "Feedback" },
	Combo_Milestone = { ids = { PING }, volume = 0.6, pitch = NumberRange.new(1.2, 1.6), group = "Feedback" },
	Dummy_Break = { ids = { KERPLUNK, BASS }, volume = 0.8, pitch = NumberRange.new(0.8, 1), group = "Impacts" },
	Level_Up = { ids = { VICTORY }, volume = 0.7, pitch = NumberRange.new(1, 1), group = "Feedback" },
	Weapon_Unlock = { ids = { PING, VICTORY }, volume = 0.75, pitch = NumberRange.new(1, 1.1), group = "Feedback" },
	Chest_Open = { ids = { KERPLUNK, PING }, volume = 0.7, pitch = NumberRange.new(0.9, 1), group = "Feedback" },
	Reward = { ids = { PING }, volume = 0.6, pitch = NumberRange.new(1.3, 1.5), group = "Feedback" },
	Coin = { ids = { CLICK, PING }, volume = 0.3, pitch = NumberRange.new(1.4, 1.9), group = "Feedback" },
	Zone_Unlock = { ids = { VICTORY, BASS }, volume = 0.8, pitch = NumberRange.new(0.9, 1), group = "Feedback" },
	Boss_Spawn = { ids = { BASS }, volume = 1, pitch = NumberRange.new(0.5, 0.6), group = "Feedback" },
	Rare_Event = { ids = { VICTORY, PING }, volume = 0.85, pitch = NumberRange.new(0.8, 0.9), group = "Feedback" },
	UI_Click = { ids = { BUTTON }, volume = 0.5, pitch = NumberRange.new(0.95, 1.05), group = "UI" },
	UI_Buy = { ids = { PING }, volume = 0.55, pitch = NumberRange.new(1.1, 1.2), group = "UI" },
	UI_Error = { ids = { KERPLUNK }, volume = 0.4, pitch = NumberRange.new(0.6, 0.7), group = "UI" },
}

return defs
