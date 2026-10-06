--!strict
--[[
	BossService — un boss par zone, apparition périodique tant que des joueurs ayant accès à
	la zone y sont présents. PV mis à l'échelle du nombre de joueurs ; récompenses pour tous
	les contributeurs significatifs (pas de vol de kill) : pièces, XP, coffre, arme du boss
	(chance de base + compteur de « pitié » pour qu'un joueur malchanceux finisse par l'obtenir).
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Curves = require(Shared.Rules.Curves)
local Economy = require(Shared.Rules.Economy)
local Loot = require(Shared.Rules.Loot)
local ZoneLayout = require(Shared.Rules.ZoneLayout)
local NumberFormat = require(Shared.Rules.NumberFormat)
local LootConfig = require(Shared.Config.Loot)
local Game = require(Shared.Config.Game)
local Zones = require(Shared.Config.Zones)
local GameEvents = require(script.Parent.Parent.GameEvents)
local PlayerService = require(script.Parent.PlayerService)
local DummyService = require(script.Parent.DummyService)
local ProgressionService = require(script.Parent.ProgressionService)
local WeaponService = require(script.Parent.WeaponService)

local BossService = {}

local BOSS_SCALE = 3.2
local MIN_SHARE = 0.02
local POLL = 5
local CORPSE_SECONDS = 6

type Slot = { Zone: Zones.Zone, Dummy: DummyService.Dummy?, NextSpawn: number }

local slots: { Slot } = {}

local function playersIn(zone: Zones.Zone): { PlayerService.State }
	local out = {}
	for _, player in Players:GetPlayers() do
		local state = PlayerService.get(player)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if state and root and state.Profile.Zones[zone.Id] and ZoneLayout.zoneAt(root.Position) == zone.Index then
			table.insert(out, state)
		end
	end
	return out
end

local function announce(zone: Zones.Zone, text: string)
	for _, player in Players:GetPlayers() do
		local state = PlayerService.get(player)
		if state and state.Profile.Zones[zone.Id] then
			ProgressionService.notify(state, "Boss", text, { id = zone.Id })
		end
	end
end

local function spawnBoss(slot: Slot, present: number)
	local zone = slot.Zone
	local arena = ZoneLayout.bossArena(zone.Index)
	local center = ZoneLayout.center(zone.Index)
	local flat = Vector3.new(center.X - arena.X, 0, center.Z - arena.Z)
	local back = if flat.Magnitude > 1 then -flat.Unit else Vector3.new(0, 0, 1)
	local cframe = CFrame.fromMatrix(arena + Vector3.new(0, 1.2, 0), Vector3.yAxis:Cross(back), Vector3.yAxis, back)
	slot.Dummy = DummyService.create({
		Kind = "Boss",
		ZoneIndex = zone.Index,
		Pivot = cframe,
		Scale = BOSS_SCALE,
		MaxHP = Curves.bossHP(zone.Index) * (1 + 0.3 * math.max(0, present - 1)),
		AutoRespawn = false,
		RegenDelay = 25,
	})
	announce(zone, zone.BossName .. " has appeared!")
end

local function reward(dummy: DummyService.Dummy, contribution: { [Player]: number })
	local zone = Zones.List[dummy.ZoneIndex]
	local bossWeapon = Loot.bossWeapon(zone.Id)
	for player, dealt in contribution do
		local state = PlayerService.get(player)
		if state and dealt >= dummy.MaxHP * MIN_SHARE then
			local ctx = PlayerService.economyContext(state, state.Combo.Count, os.time())
			local coins = math.floor(Curves.bossCoins(dummy.ZoneIndex) * Economy.coinMultiplier(ctx))
			local xp = Curves.bossXP(dummy.ZoneIndex) * Economy.xpMultiplier(ctx)
			ProgressionService.addCoins(state, coins)
			ProgressionService.addXP(state, xp)
			state.Profile.Stats.Bosses += 1
			PlayerService.mark(state, "Stats")
			GameEvents.BossDefeated:Fire(state, zone.Id)

			local lines = { "+" .. NumberFormat.compact(coins) .. " coins", "+" .. NumberFormat.compact(xp) .. " XP" }
			if math.random() < LootConfig.BossChestChance then
				ProgressionService.addChest(state, LootConfig.BossChestId, 1)
				table.insert(lines, LootConfig.ById[LootConfig.BossChestId].Name)
			end
			if bossWeapon then
				local pity = state.Profile.Pity.Boss
				if math.random() < Loot.bossWeaponChance(pity) then
					state.Profile.Pity.Boss = 0
					if WeaponService.grant(state, bossWeapon.Id, "Boss") then
						table.insert(lines, bossWeapon.Name .. "!")
					else
						-- Déjà possédée : consolation généreuse plutôt que rien.
						ProgressionService.grantCoinMinutes(state, 20)
						table.insert(lines, "Duplicate converted to coins")
					end
				else
					state.Profile.Pity.Boss = pity + 1
				end
				PlayerService.mark(state, "Pity")
			end
			ProgressionService.notify(state, "Boss", zone.BossName .. " defeated!", { l = lines })
		end
	end
end

function BossService.start()
	local now = os.clock()
	for i, zone in Zones.List do
		table.insert(slots, { Zone = zone, Dummy = nil, NextSpawn = now + 30 + i * 12 })
	end

	DummyService.Killed:Connect(function(dummy, contribution)
		if dummy.Kind ~= "Boss" then
			return
		end
		reward(dummy, table.clone(contribution))
		for _, slot in slots do
			if slot.Dummy == dummy then
				slot.NextSpawn = os.clock() + Game.BossRespawnSeconds
				task.delay(CORPSE_SECONDS, function()
					DummyService.remove(dummy)
					if slot.Dummy == dummy then
						slot.Dummy = nil
					end
				end)
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(POLL)
			local time = os.clock()
			for _, slot in slots do
				if slot.Dummy == nil and time >= slot.NextSpawn then
					local present = #playersIn(slot.Zone)
					if present >= Game.BossMinPlayers then
						spawnBoss(slot, present)
					end
				end
			end
		end
	end)
end

return BossService
