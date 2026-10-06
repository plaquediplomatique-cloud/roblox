--!strict
--[[
	WeaponService — possession, équipement et affichage des armes.

	* débloque automatiquement les armes de la voie principale au passage de niveau et équipe
	  la nouvelle si elle est plus puissante (« NEW WEAPON UNLOCKED! ») ;
	* `grant` : armes de chasse (boss, coffres, succès) — idempotent ;
	* `equip` : le client ne fait que demander ; possession revérifiée ici ;
	* le modèle 3D est construit depuis la recette (Assets/Builder) et soudé à la main du
	  personnage ; le style de frappe est publié en attribut pour l'animation côté client.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Net = require(Shared.Net.Net)
local Builder = require(Shared.Assets.Builder)
local WeaponCatalog = require(Shared.Rules.WeaponCatalog)
local GameEvents = require(script.Parent.Parent.GameEvents)
local PlayerService = require(script.Parent.PlayerService)
local CharacterService = require(script.Parent.CharacterService)
local ProgressionService = require(script.Parent.ProgressionService)

type State = PlayerService.State

local WeaponService = {}

local MODEL_NAME = "WeaponModel"

local function applyToCharacter(state: State, character: Model)
	local old = character:FindFirstChild(MODEL_NAME)
	if old then
		old:Destroy()
	end
	local weapon = PlayerService.weapon(state)
	local hand = character:WaitForChild("RightHand", 5) :: BasePart?
	if not hand then
		return
	end
	local model = Builder.weapon(weapon)
	model.Name = MODEL_NAME
	Builder.attach(model, hand)
	model.Parent = character
	character:SetAttribute("Weapon", weapon.Id)
	character:SetAttribute("Swing", weapon.ArchetypeData.Swing)
end

function WeaponService.refreshCharacter(state: State)
	local character = state.Player.Character
	if character then
		applyToCharacter(state, character)
	end
end

function WeaponService.equip(state: State, id: string): boolean
	local profile = state.Profile
	if not profile.Weapons[id] or not WeaponCatalog.ById[id] then
		return false
	end
	if profile.Equipped == id then
		return true
	end
	profile.Equipped = id
	PlayerService.invalidateFighter(state)
	PlayerService.mark(state, "Equipped")
	WeaponService.refreshCharacter(state)
	return true
end

-- Accorde une arme (idempotent). Renvoie true si elle est NOUVELLE.
function WeaponService.grant(state: State, id: string, source: string): boolean
	local weapon = WeaponCatalog.ById[id]
	local profile = state.Profile
	if not weapon or profile.Weapons[id] then
		return false
	end
	profile.Weapons[id] = true
	profile.Collection[id] = true
	PlayerService.mark(state, "Weapons", "Collection")
	GameEvents.WeaponAcquired:Fire(state, id, source)
	Net.event("WeaponUnlocked"):FireClient(state.Player, { id = id, s = source })
	return true
end

function WeaponService.start()
	Net.init() -- idempotent : les remotes existent avant tout handler
	CharacterService.onCharacter(applyToCharacter)

	GameEvents.LevelUp:Connect(function(state, _old, new)
		local current = PlayerService.weapon(state)
		local best = current
		for _, weapon in WeaponCatalog.mainUnlockedAt(new) do
			if WeaponService.grant(state, weapon.Id, "Level") and weapon.Damage > best.Damage then
				best = weapon
			end
		end
		if best ~= current then
			WeaponService.equip(state, best.Id)
		end
	end)

	GameEvents.Ascended:Connect(function(state)
		PlayerService.invalidateFighter(state)
		local profile = state.Profile
		PlayerService.mark(state, "Weapons", "Equipped", "Level", "XP", "Zones", "Stars", "Stats")
		profile.Equipped = WeaponCatalog.bestOwned(profile.Weapons).Id
		WeaponService.refreshCharacter(state)
		for _, weapon in WeaponCatalog.mainUnlockedAt(profile.Level) do
			WeaponService.grant(state, weapon.Id, "Level")
		end
	end)
end

WeaponService.notify = ProgressionService.notify

return WeaponService
