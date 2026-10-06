--!strict
--[[
	ClientState — état client centralisé et observable.

	Expose les replicas clés (profil, match, party, entraînement, classement, salon perso)
	et le contexte d'arène (Hub / Training / Match) publié par le serveur en attributs.
	Les contrôleurs réagissent aux signaux au lieu de s'interroger mutuellement.
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Signal = require(Shared.Util.Signal)
local ReplicaController = require(script.Parent.ReplicaController)

local player = Players.LocalPlayer

export type ArenaKind = Types.ArenaKind

local ClientState = {
	ArenaChanged = Signal.new() :: Signal.Signal<ArenaKind, string>,
	ProfileReady = Signal.new() :: Signal.Signal<ReplicaController.ClientReplica>,
	MatchChanged = Signal.new() :: Signal.Signal<ReplicaController.ClientReplica?>,
	PartyChanged = Signal.new() :: Signal.Signal<ReplicaController.ClientReplica?>,
	menuOpen = false,
	MenuChanged = Signal.new() :: Signal.Signal<boolean>,
}

local profile: ReplicaController.ClientReplica? = nil
local match: ReplicaController.ClientReplica? = nil
local party: ReplicaController.ClientReplica? = nil

function ClientState.arena(): (ArenaKind, string)
	local kind = player:GetAttribute("ArenaKind")
	local id = player:GetAttribute("Arena")
	local typed: ArenaKind = if kind == "Training" then "Training" elseif kind == "Match" then "Match" else "Hub"
	return typed, if type(id) == "string" then id else "Hub"
end

function ClientState.profile(): ReplicaController.ClientReplica?
	return profile
end

function ClientState.profileData(): Types.ProfileData?
	return if profile then profile.data :: Types.ProfileData else nil
end

function ClientState.match(): ReplicaController.ClientReplica?
	return match
end

function ClientState.matchData(): Types.MatchStateData?
	return if match then match.data :: Types.MatchStateData else nil
end

function ClientState.party(): ReplicaController.ClientReplica?
	return party
end

function ClientState.partyData(): Types.PartyData?
	return if party then party.data :: Types.PartyData else nil
end

--[[ Équipe du joueur local dans le match courant ("A"/"B") ou nil. ]]
function ClientState.myTeam(): string?
	local data = ClientState.matchData()
	if not data then
		return nil
	end
	local entry = data.players[tostring(player.UserId)]
	return if entry then entry.team else nil
end

-- Menus « de base » (lobby, menu de match) et fenêtres superposées (options rapides) :
-- la souris reste libre tant que l'un d'eux est ouvert, quel que soit l'ordre de fermeture.
local baseMenuOpen = false
local overlays: { [string]: boolean } = {}

local function publishMenu()
	local open = baseMenuOpen or next(overlays) ~= nil
	if ClientState.menuOpen ~= open then
		ClientState.menuOpen = open
		ClientState.MenuChanged:Fire(open)
	end
end

function ClientState.setMenuOpen(open: boolean)
	baseMenuOpen = open
	publishMenu()
end

function ClientState.setOverlay(name: string, open: boolean)
	if open then
		overlays[name] = true
	else
		overlays[name] = nil
	end
	publishMenu()
end

function ClientState.isOverlayOpen(name: string): boolean
	return overlays[name] == true
end

function ClientState.start()
	-- Arena et ArenaKind sont deux attributs : on ne publie qu'un changement effectif.
	local lastKind, lastId = "", ""
	local function publishArena()
		local kind: ArenaKind, id: string = ClientState.arena()
		if kind ~= lastKind or id ~= lastId then
			lastKind, lastId = kind, id
			ClientState.ArenaChanged:Fire(kind, id)
		end
	end
	player:GetAttributeChangedSignal("Arena"):Connect(publishArena)
	player:GetAttributeChangedSignal("ArenaKind"):Connect(publishArena)
	local initialKind: ArenaKind, initialId: string = ClientState.arena()
	lastKind, lastId = initialKind, initialId
	ReplicaController.onNew("PlayerProfile", function(replica)
		profile = replica
		ClientState.ProfileReady:Fire(replica)
	end)
	ReplicaController.onNew("MatchState", function(replica)
		match = replica
		ClientState.MatchChanged:Fire(replica)
		replica.Destroyed:Connect(function()
			if match == replica then
				match = nil
				ClientState.MatchChanged:Fire(nil)
			end
		end)
	end)
	ReplicaController.onNew("Party", function(replica)
		party = replica
		ClientState.PartyChanged:Fire(replica)
		replica.Changed:Connect(function()
			ClientState.PartyChanged:Fire(replica)
		end)
		replica.Destroyed:Connect(function()
			if party == replica then
				party = nil
				ClientState.PartyChanged:Fire(nil)
			end
		end)
	end)
end

return ClientState
