--!strict
--[[
	ArenaService — "où est ce joueur ?" : Hub, Training ou un match précis.

	Toute logique de combat/caméra/HUD dépend du contexte :
	  * Hub      : armes rangées, aucun dégât, caméra 3e personne.
	  * Training : armes actives contre les bots uniquement, caméra 1re personne.
	  * Match    : combat entre équipes du MÊME match uniquement.
	Le contexte est publié en attributs du Player (répliqués) : Arena = id, ArenaKind.
	Plusieurs matchs locaux (parties personnalisées) peuvent coexister sur un serveur :
	l'id d'arène isole totalement leurs joueurs.
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local Signal = require(Shared.Util.Signal)

local ArenaService = {
	Changed = Signal.new() :: Signal.Signal<Player, Types.ArenaKind, string>,
}

local current: { [Player]: { kind: Types.ArenaKind, id: string } } = {}

function ArenaService.set(player: Player, kind: Types.ArenaKind, id: string?)
	local arenaId = id or kind
	local previous = current[player]
	if previous and previous.kind == kind and previous.id == arenaId then
		return
	end
	current[player] = { kind = kind, id = arenaId }
	player:SetAttribute("ArenaKind", kind)
	player:SetAttribute("Arena", arenaId)
	ArenaService.Changed:Fire(player, kind, arenaId)
end

function ArenaService.get(player: Player): (Types.ArenaKind, string)
	local entry = current[player]
	if entry then
		return entry.kind, entry.id
	end
	return "Hub", "Hub"
end

function ArenaService.idOf(player: Player): string
	local _, id = ArenaService.get(player)
	return id
end

function ArenaService.sameArena(a: Player, b: Player): boolean
	return ArenaService.idOf(a) == ArenaService.idOf(b)
end

function ArenaService.playersIn(id: string): { Player }
	local list = {}
	for player, entry in current do
		if entry.id == id and player.Parent then
			table.insert(list, player)
		end
	end
	return list
end

function ArenaService.Init() end

function ArenaService.Start()
	Players.PlayerRemoving:Connect(function(player)
		current[player] = nil
	end)
end

return ArenaService
