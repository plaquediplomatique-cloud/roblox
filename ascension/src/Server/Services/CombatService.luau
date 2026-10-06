--!strict
--[[
	CombatService — validation et résolution des coups. SEUL endroit où un dégât existe.

	Le client demande « je frappe » (avec, au mieux, l'identifiant du mannequin visé). Le serveur :
	  1. impose la cadence réelle de l'arme (seau à jetons dérivé de la vitesse du joueur) ;
	  2. vérifie la portée avec la position serveur du personnage ;
	  3. vérifie l'accès (base du propriétaire, zone débloquée) ;
	  4. calcule combo, critique, dégâts, XP et pièces (règles pures testées) ;
	  5. répond à l'attaquant (HitResult) et diffuse l'animation aux joueurs proches (SwingFx).
	Un exploiteur ne peut ni frapper plus vite, ni plus loin, ni plus fort, ni hors de sa zone.
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Net = require(Shared.Net.Net)
local Combat = require(Shared.Rules.Combat)
local Economy = require(Shared.Rules.Economy)
local Game = require(Shared.Config.Game)
local Zones = require(Shared.Config.Zones)
local GameEvents = require(script.Parent.Parent.GameEvents)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local PlayerService = require(script.Parent.PlayerService)
local DummyService = require(script.Parent.DummyService)
local ProgressionService = require(script.Parent.ProgressionService)

type State = PlayerService.State

local CombatService = {}

local FIELD_BONUS = 1.25 -- les mannequins de terrain rapportent plus que celui de la base
local CONTRIBUTION_SHARE = 0.1 -- part minimale des PV pour toucher la récompense de kill

local function characterRoot(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Politique d'accès : base = propriétaire seulement ; terrain/boss = zone débloquée.
local function canHit(state: State): (DummyService.Dummy) -> boolean
	return function(dummy)
		if dummy.Kind == "Base" then
			return dummy.Owner == state.Player
		end
		local zone = Zones.List[dummy.ZoneIndex]
		return state.Profile.Zones[zone.Id] == true
	end
end

local function broadcast(origin: Player, rootPart: BasePart, payload: { [string]: any })
	local remote = Net.unreliable("SwingFx")
	local radiusSq = Game.FxBroadcastRadius * Game.FxBroadcastRadius
	for _, other in Players:GetPlayers() do
		if other ~= origin then
			local otherRoot = characterRoot(other)
			if otherRoot then
				local offset = otherRoot.Position - rootPart.Position
				if offset:Dot(offset) <= radiusSq then
					remote:FireClient(other, payload)
				end
			end
		end
	end
end

local function updateStats(state: State, damage: number, dealt: number, crit: number, combo: number, killed: boolean)
	local stats = state.Profile.Stats
	stats.Hits += 1
	stats.TotalDamage += dealt
	if damage > stats.MaxHit then
		stats.MaxHit = damage
	end
	if crit > 0 then
		stats.Crits += 1
	end
	if combo > stats.BestCombo then
		stats.BestCombo = combo
	end
	if killed then
		stats.Kills += 1
		state.WeeklyKills += 1
	end
	PlayerService.mark(state, "Stats")
end

-- Récompense de kill pour chaque contributeur significatif (les mannequins partagés profitent à tous).
local function payKill(dummy: DummyService.Dummy, contribution: { [Player]: number }, killer: State)
	local threshold = dummy.MaxHP * CONTRIBUTION_SHARE
	for player, dealt in contribution do
		local state = PlayerService.get(player)
		if state and (state == killer or dealt >= threshold) then
			local ctx = PlayerService.economyContext(state, state.Combo.Count, os.time())
			local coins = Economy.killCoins(dummy.ZoneIndex, ctx)
			ProgressionService.addCoins(state, coins)
			if state ~= killer then
				state.Profile.Stats.Kills += 1
				state.WeeklyKills += 1
				PlayerService.mark(state, "Stats")
			end
			GameEvents.Kill:Fire(state, dummy.Kind == "Boss")
		end
	end
end

function CombatService.swing(player: Player, payload: { t: string?, n: number? })
	local state = PlayerService.get(player)
	local rootPart = characterRoot(player)
	if not state or not rootPart then
		return
	end
	local now = os.clock()
	local fighter = PlayerService.fighter(state)

	-- 1. Cadence : jetons rechargés au rythme de l'arme (tolérance réseau incluse).
	local rate = Combat.swingsPerSecond(fighter) / Game.SwingTolerance
	state.Tokens = math.min(Game.SwingBurst, state.Tokens + (now - state.TokenAt) * rate)
	state.TokenAt = now
	if state.Tokens < 1 then
		return
	end
	state.Tokens -= 1
	state.Swings += 1

	local weapon = PlayerService.weapon(state)
	local fxBase = { u = player.UserId }

	-- 2-3. Cible : portée serveur + accès.
	local dummy = DummyService.pick(rootPart.Position, weapon.Reach + Game.ReachPadding, payload.t, canHit(state))
	if not dummy then
		broadcast(player, rootPart, fxBase)
		return
	end

	-- 4. Résolution.
	local combo = Combat.comboHit(state.Combo, now, Combat.comboWindow(fighter.Special))
	state.HitIndex += 1
	local result = Combat.resolveHit({
		Fighter = fighter,
		Combo = combo,
		HitIndex = state.HitIndex,
		TargetHP = dummy.HP,
		TargetMaxHP = dummy.MaxHP,
	}, math.random)
	local dealt, killed = DummyService.damage(dummy, player, result.Damage)

	local ctx = PlayerService.economyContext(state, combo, os.time())
	local xp = Economy.hitXP(dummy.ZoneIndex, dealt, dummy.MaxHP, ctx)
		* (if dummy.Kind == "Base" then 1 else FIELD_BONUS)
	local coins = 0
	if killed then
		coins = Economy.killCoins(dummy.ZoneIndex, ctx)
	end

	updateStats(state, result.Damage, dealt, result.Crit, combo, killed)
	ProgressionService.addXP(state, xp)
	if killed then
		payKill(dummy, dummy.Contribution, state)
	end
	state.LastHitAt = now
	GameEvents.Hit:Fire(state, {
		Damage = result.Damage,
		Crit = result.Crit,
		Combo = combo,
		Kill = killed,
		Boss = dummy.Kind == "Boss",
		ZoneIndex = dummy.ZoneIndex,
	})

	-- 5. Retours.
	Net.event("HitResult"):FireClient(player, {
		i = dummy.Id,
		d = result.Damage,
		c = result.Crit,
		cb = combo,
		x = xp,
		hp = dummy.HP,
		mx = dummy.MaxHP,
		k = killed,
		co = coins,
		p = dummy.Position,
		ds = result.Double,
		sg = result.Surge,
	})
	broadcast(player, rootPart, { u = player.UserId, p = dummy.Position, c = result.Crit, k = killed })
end

function CombatService.start()
	ServerNet.on("Swing", function(player, payload)
		CombatService.swing(player, payload)
	end)
end

return CombatService
