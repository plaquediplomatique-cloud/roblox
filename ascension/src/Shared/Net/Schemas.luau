--!strict
--[[
	Schemas — validation des paquets CLIENT -> SERVEUR (Guard). Pure, testée avec des payloads
	hostiles. Un client ne transmet que des intentions : identifiants courts, jamais de montants.
]]

local Guard = require(script.Parent.Parent.Util.Guard)

local Schemas = {}

local id = Guard.string(40)

Schemas.Swing = Guard.shape({
	t = Guard.optional(Guard.string(32)), -- indice : id du mannequin visé (revérifié par le serveur)
	n = Guard.optional(Guard.integer(0, 1000000)), -- compteur de séquence (diagnostic)
})
Schemas.Equip = Guard.shape({ id = id })
Schemas.BuyUpgrade = Guard.shape({ id = Guard.string(24) })
Schemas.UnlockZone = Guard.shape({ id = Guard.string(24) })
Schemas.Teleport = Guard.shape({ id = Guard.string(24) })
Schemas.Ascend = Guard.shape({})
Schemas.ClaimDaily = Guard.shape({})
Schemas.ClaimQuest = Guard.shape({ id = id })
Schemas.ClaimAchievement = Guard.shape({ id = id })
Schemas.OpenChest = Guard.shape({ id = Guard.string(24) })
Schemas.BuyDecor = Guard.shape({ id = id })
Schemas.PlaceDecor = Guard.shape({ slot = Guard.string(12), id = Guard.optional(id) })
Schemas.SetSetting = Guard.shape({ key = Guard.string(24), value = Guard.boolean })
Schemas.RequestSync = Guard.shape({})
Schemas.GetLeaderboard = Guard.shape({ metric = Guard.string(24) })

-- Limites de débit (capacité de rafale, recharge par seconde) par remote.
Schemas.Rates = {
	Swing = { 4, 9 },
	Equip = { 4, 2 },
	BuyUpgrade = { 6, 6 }, -- achats en rafale (maintien du bouton)
	UnlockZone = { 3, 1 },
	Teleport = { 3, 1 },
	Ascend = { 2, 0.2 },
	ClaimDaily = { 2, 0.5 },
	ClaimQuest = { 4, 2 },
	ClaimAchievement = { 4, 2 },
	OpenChest = { 3, 1 },
	BuyDecor = { 4, 2 },
	PlaceDecor = { 6, 3 },
	SetSetting = { 4, 2 },
	RequestSync = { 2, 0.5 },
	GetLeaderboard = { 3, 0.5 },
} :: { [string]: { number } }

return Schemas
