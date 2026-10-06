--!strict
--[[
	MatchController — l'expérience de match côté client, miroir de la machine à états
	serveur (MatchInstance) répliquée par le replica "MatchState".

	  Waiting  : vue aérienne de l'arène, "en attente des joueurs".
	  Intro    : survol cinématique (chemin de caméra exposé par la carte) + carte de
	             présentation (carte, mode, deux équipes face à face).
	  Prep     : apparition (flash), bannière de manche (pistolet, prolongation, balle de
	             match), panneau d'équipement [M].
	  Live     : combat ; invite d'objectif contextuelle (porter / armer / neutraliser).
	  Planted  : bips 3D qui s'accélèrent avec la mèche, lumière pulsante sur l'uplink.
	  Mort     : killcam (replay des 3 dernières secondes vues par le tueur, ralenti final,
	             position de la victime marquée) -> spectateur (coéquipiers vivants).
	  MatchEnd : écran VICTOIRE / DÉFAITE cinématique, MVP, tableau final.
	Toute décision reste serveur : ce contrôleur n'envoie que des intentions
	(Interact, LoadoutSelect).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local GameModes = require(Shared.Config.GameModes)
local Maps = require(Shared.Config.Maps)
local Weapons = require(Shared.Config.Weapons)
local Ranks = require(Shared.Config.Ranks)
local Theme = require(Shared.Config.Theme)
local Stances = require(Shared.Combat.Stances)
local Janitor = require(Shared.Util.Janitor)
local Net = require(Shared.Net.Net)
local UI = require(script.Parent.Parent.UI.UI)
local SettingsPanel = require(script.Parent.Parent.UI.SettingsPanel)
local ClientState = require(script.Parent.Parent.Core.ClientState)
local ReplicaController = require(script.Parent.Parent.Core.ReplicaController)
local InputController = require(script.Parent.InputController)
local SettingsController = require(script.Parent.SettingsController)
local CameraController = require(script.Parent.CameraController)
local MovementController = require(script.Parent.MovementController)
local HUDController = require(script.Parent.HUDController)
local AudioController = require(script.Parent.AudioController)
local LightingController = require(script.Parent.LightingController)
local EffectsController = require(script.Parent.EffectsController)
local TransitionController = require(script.Parent.TransitionController)

local colors = Theme.colors
local fonts = Theme.fonts
local player = Players.LocalPlayer

local MatchController = {}

local DEFUSE_RADIUS = 4.5
local REASONS: { [string]: string } = {
	Elimination = "ÉLIMINATION",
	Detonation = "UPLINK DÉTONÉ",
	Defuse = "UPLINK NEUTRALISÉ",
	Time = "TEMPS ÉCOULÉ",
	Draw = "ÉGALITÉ",
	Forfeit = "ABANDON",
}

local gui: ScreenGui
local janitor = Janitor.new()
local lastPhase = ""
local dead = false
local pendingKillcam: Types.KillcamPacket? = nil
local killcamActive = false
local spectateIndex = 1
local interacting: Types.InteractAction? = nil
local availableAction: Types.InteractAction? = nil
local beepAt = 0
local sites: { BasePart } = {}

-- Widgets
local introCard: Frame
local introMap: TextLabel
local introTagline: TextLabel
local introMode: TextLabel
local introLeft: Frame
local introRight: Frame
local spectateBar: Frame
local spectateText: TextLabel
local killcamBar: Frame
local killcamText: TextLabel
local carrierBadge: TextLabel
local loadoutPanel: Frame
local loadoutRows: Frame
local pausePanel: Frame
local endScreen: Frame
local endTitle: TextLabel
local endScore: TextLabel
local endDetail: TextLabel
local prepHint: TextLabel

---------------------------------------------------------------------------------------------
-- Contexte
---------------------------------------------------------------------------------------------

local function matchData(): Types.MatchStateData?
	return ClientState.matchData()
end

local function modeOf(data: Types.MatchStateData): GameModes.ModeDef?
	return GameModes.get(data.mode)
end

local function myEntry(data: Types.MatchStateData): Types.MatchPlayerData?
	return data.players[tostring(player.UserId)]
end

local function sideOf(data: Types.MatchStateData, team: string): string
	local sides = data.sides :: any
	return sides[team] or "Attack"
end

local function sideName(side: string): string
	return (Theme.sideNames :: any)[side] or side
end

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function arenaModel(): Model?
	local data = matchData()
	local folder = Workspace:FindFirstChild("Arenas")
	if not (data and folder) then
		return nil
	end
	for _, child in folder:GetChildren() do
		if child:IsA("Model") and child:GetAttribute("MatchId") == data.id then
			return child
		end
	end
	return nil
end

local function rootPart(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function keyFor(action: string): string
	local key = SettingsController.get().Keybinds[action] or "?"
	return if key == "MouseButton1" then "CLIC G" elseif key == "MouseButton2" then "CLIC D" else string.upper(key)
end

local function refreshSites()
	table.clear(sites)
	local model = arenaModel()
	if not model then
		return
	end
	for _, part in CollectionService:GetTagged("SiteZone") do
		if part:IsA("BasePart") and part:IsDescendantOf(model) then
			table.insert(sites, part)
			if not part:FindFirstChild("AS_SiteLabel") then
				local label = Instance.new("BillboardGui")
				label.Name = "AS_SiteLabel"
				label.Size = UDim2.fromOffset(90, 40)
				label.StudsOffsetWorldSpace = Vector3.new(0, part.Size.Y / 2 + 2, 0)
				label.MaxDistance = 160
				label.LightInfluence = 0
				local text = Instance.new("TextLabel")
				text.BackgroundTransparency = 1
				text.Size = UDim2.fromScale(1, 1)
				text.FontFace = fonts.display
				text.TextSize = 22
				text.TextColor3 = colors.warning
				text.TextStrokeTransparency = 0.5
				text.Text = "SITE " .. tostring(part:GetAttribute("Site") or "?")
				text.Parent = label
				label.Parent = part
			end
		end
	end
end

local function siteAt(position: Vector3): string?
	for _, part in sites do
		local localPoint = part.CFrame:PointToObjectSpace(position)
		local half = part.Size * 0.5
		if
			math.abs(localPoint.X) <= half.X
			and math.abs(localPoint.Y) <= half.Y
			and math.abs(localPoint.Z) <= half.Z
		then
			return tostring(part:GetAttribute("Site") or "?")
		end
	end
	return nil
end

---------------------------------------------------------------------------------------------
-- Caméra : intro, attente, fin
---------------------------------------------------------------------------------------------

local function introFrames(model: Model): { CFrame }
	local frames: { CFrame } = {}
	local count = model:GetAttribute("IntroCount")
	if type(count) == "number" then
		for index = 1, count do
			local frame = model:GetAttribute("Intro" .. index)
			if typeof(frame) == "CFrame" then
				table.insert(frames, frame)
			end
		end
	end
	return frames
end

local function overviewOf(model: Model?): CFrame?
	local value = if model then model:GetAttribute("Overview") else nil
	return if typeof(value) == "CFrame" then value else nil
end

local function rosterInto(container: Frame, data: Types.MatchStateData, team: string, color: Color3)
	for _, child in container:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	local order = 0
	for _, entry in data.players do
		if entry.team == team then
			order += 1
			local tier = Ranks.tierOf(entry.rankIndex)
			UI.text({
				Text = ('<font color="#%s">%s</font>  %s  <font color="#%s">LV %d</font>'):format(
					tier.color:ToHex(),
					tier.glyph,
					entry.name,
					colors.textDim:ToHex(),
					entry.level
				),
				FontFace = fonts.heading,
				TextSize = 22,
				TextColor3 = color,
				Size = UDim2.new(1, 0, 0, 30),
				LayoutOrder = order,
				Parent = container,
			})
		end
	end
end

local function playIntro()
	local data = matchData()
	local model = arenaModel()
	if not (data and model) then
		return
	end
	local info = Maps.get(data.map)
	local mode = modeOf(data)
	HUDController.setVisible(false)
	MovementController.setFrozen(true)
	introMap.Text = if info then string.upper(info.displayName) else string.upper(data.map)
	introTagline.Text = if info then info.tagline else ""
	introMode.Text = (if mode then mode.displayName else data.mode)
		.. (if data.ranked then "  ·  CLASSÉ" elseif data.custom then "  ·  PERSONNALISÉ" else "  ·  NON CLASSÉ")
	local myTeam = ClientState.myTeam() or "A"
	rosterInto(introLeft, data, myTeam, colors.ally)
	rosterInto(introRight, data, if myTeam == "A" then "B" else "A", colors.enemy)
	introCard.Visible = true
	introCard.BackgroundTransparency = 1
	UI.glitchText(introMap, 0.5)
	TransitionController.reveal()
	local duration = if mode then mode.introTime - 0.6 else 6
	local frames = introFrames(model)
	if #frames > 0 then
		CameraController.playPath(frames, math.max(duration, 2))
	end
	AudioController.play("UI.Whoosh")
end

local function orbitFrames(center: CFrame): { CFrame }
	local target = center.Position + center.LookVector * 80
	local frames: { CFrame } = {}
	for step = 0, 6 do
		local angle = step / 6 * math.pi * 0.6
		local offset = (center.Position - target)
		local rotated = CFrame.Angles(0, angle, 0) * offset
		table.insert(frames, CFrame.lookAt(target + rotated * 0.7, target))
	end
	return frames
end

---------------------------------------------------------------------------------------------
-- Mort : killcam puis spectateur
---------------------------------------------------------------------------------------------

local function spectateCandidates(): { Player }
	local data = matchData()
	local list: { Player } = {}
	if not data then
		return list
	end
	local myTeam = ClientState.myTeam()
	for _, entry in data.players do
		if entry.team == myTeam and entry.alive and entry.userId ~= player.UserId then
			local other = Players:GetPlayerByUserId(entry.userId)
			if other and other.Character then
				table.insert(list, other)
			end
		end
	end
	table.sort(list, function(a: Player, b: Player): boolean
		return a.UserId < b.UserId
	end)
	return list
end

local function updateSpectate()
	if not dead or killcamActive then
		spectateBar.Visible = false
		return
	end
	local candidates = spectateCandidates()
	spectateBar.Visible = true
	if #candidates == 0 then
		local overview = overviewOf(arenaModel())
		if overview and CameraController.getMode() ~= "Scripted" then
			CameraController.setScripted(overview, 60)
		end
		spectateText.Text = "AUCUN COÉQUIPIER EN VIE"
		return
	end
	spectateIndex = ((spectateIndex - 1) % #candidates) + 1
	local target = candidates[spectateIndex]
	if CameraController.spectateTarget() ~= target or CameraController.getMode() ~= "Spectate" then
		CameraController.spectate(target)
	end
	spectateText.Text = ("SPECTATEUR  ·  %s  ·  [%s] SUIVANT"):format(
		string.upper(target.DisplayName),
		keyFor("Fire")
	)
end

local function sampleTrack(track: { Types.KillcamSample }, t: number): Types.KillcamSample?
	local count = #track
	if count == 0 then
		return nil
	end
	if t <= track[1].t then
		return track[1]
	end
	for index = 2, count do
		local b = track[index]
		if t <= b.t then
			local a = track[index - 1]
			local alpha = (t - a.t) / math.max(b.t - a.t, 1e-3)
			local yaw = a.yaw + math.atan2(math.sin(b.yaw - a.yaw), math.cos(b.yaw - a.yaw)) * alpha
			return {
				t = t,
				cf = a.cf:Lerp(b.cf, alpha),
				stance = if alpha < 0.5 then a.stance else b.stance,
				yaw = yaw,
				pitch = a.pitch + (b.pitch - a.pitch) * alpha,
			}
		end
	end
	return track[count]
end

local function setCharacterHidden(target: Player?, hidden: boolean)
	local character = target and target.Character
	if not character then
		return
	end
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") or descendant:IsA("Decal") then
			(descendant :: any).LocalTransparencyModifier = if hidden then 1 else 0
		end
	end
end

local function playKillcam(packet: Types.KillcamPacket, done: () -> ())
	local track = packet.killerTrack
	if #track < 2 then
		done()
		return
	end
	killcamActive = true
	local killer = Players:GetPlayerByUserId(packet.killer)
	setCharacterHidden(killer, true)
	local def = Weapons.get(packet.weapon)
	killcamText.Text = ("KILLCAM  ·  %s  ·  %s%s  ·  PV %d  BOUCLIER %d"):format(
		string.upper(packet.killerName),
		if def then def.shortName else packet.weapon,
		if packet.headshot then "  ·  TÊTE" else "",
		math.ceil(packet.killerHealth),
		math.ceil(packet.killerArmor)
	)
	killcamBar.Visible = true
	spectateBar.Visible = false
	LightingController.setMenuBlur(false)

	-- Marqueur de la victime (vous) dans le replay.
	local marker = Instance.new("Part")
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanQuery = false
	marker.CanTouch = false
	marker.Transparency = 1
	marker.Size = Vector3.new(0.2, 0.2, 0.2)
	marker.Parent = Workspace
	local billboard = Instance.new("BillboardGui")
	billboard.AlwaysOnTop = true
	billboard.Size = UDim2.fromOffset(80, 30)
	billboard.LightInfluence = 0
	billboard.Parent = marker
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.FontFace = fonts.heading
	label.TextSize = 18
	label.TextColor3 = colors.danger
	label.TextStrokeTransparency = 0.4
	label.Text = "◆ VOUS"
	label.Parent = billboard

	local startT = track[1].t
	local endT = packet.killTime
	local span = math.clamp(endT - startT, 0.5, 3.4)
	startT = endT - span
	local slowFrom = math.max(span - 0.45, 0)
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - started
		-- Lecture temps réel puis ralenti ×0.35 sur la dernière demi-seconde.
		local played = if elapsed <= slowFrom then elapsed else slowFrom + (elapsed - slowFrom) * 0.35
		local t = startT + math.min(played, span)
		local sample = sampleTrack(track, t)
		if sample then
			local eye = Stances.eyePosition(sample.cf, sample.stance, 0)
			CameraController.setScripted(
				CFrame.new(eye) * CFrame.Angles(0, sample.yaw, 0) * CFrame.Angles(sample.pitch, 0, 0),
				SettingsController.get().Video.Fov
			)
		end
		local victim = sampleTrack(packet.victimTrack, t)
		if victim then
			marker.Position = victim.cf.Position + Vector3.new(0, 2.2, 0)
		end
		if played >= span + 0.6 then
			connection:Disconnect()
			marker:Destroy()
			setCharacterHidden(killer, false)
			killcamBar.Visible = false
			killcamActive = false
			done()
		end
	end)
end

local function onDeath()
	if ClientState.arena() ~= "Match" then
		return
	end
	dead = true
	interacting = nil
	HUDController.setInteraction(nil)
	task.delay(0.35, function()
		if not dead then
			return
		end
		local packet = pendingKillcam
		pendingKillcam = nil
		if packet and SettingsController.get().Hud.Killcam and not killcamActive then
			playKillcam(packet, updateSpectate)
		else
			task.wait(1.2)
			updateSpectate()
		end
	end)
end

---------------------------------------------------------------------------------------------
-- Objectif (Uplink)
---------------------------------------------------------------------------------------------

local function sendInteract(action: Types.InteractAction)
	Net.event("Interact"):FireServer(action)
end

local function stopInteracting()
	local current = interacting
	if current then
		interacting = nil
		sendInteract(if current == "PlantStart" then "PlantCancel" else "DefuseCancel")
	end
end

local function findCore(data: Types.MatchStateData): BasePart?
	for _, instance in CollectionService:GetTagged("UplinkCore") do
		if instance:IsA("BasePart") and instance:GetAttribute("MatchId") == data.id then
			return instance
		end
	end
	return nil
end

local function objectiveStep()
	local data = matchData()
	if not data then
		return
	end
	local mode = modeOf(data)
	local root = rootPart()
	local entry = myEntry(data)
	if not (mode and mode.objective == "Uplink" and root and entry) or dead then
		carrierBadge.Visible = false
		availableAction = nil
		HUDController.setInteraction(nil)
		return
	end
	local objective = data.objective
	local myId = player.UserId
	local side = sideOf(data, entry.team)
	local live = data.phase == "Live" or data.phase == "Planted"
	local now = serverNow()
	carrierBadge.Visible = objective.carrier == myId and not objective.planted
	local prompt: string? = nil
	local progress = 0
	local action: Types.InteractAction? = nil
	if live and side == "Attack" and objective.carrier == myId and not objective.planted then
		local site = siteAt(root.Position)
		if site then
			action = "PlantStart"
			if objective.planter == myId then
				progress = 1 - (objective.plantEndsAt - now) / math.max(mode.plantTime, 0.1)
				prompt = "Armement de l'uplink…"
			else
				-- La touche est affichée dans la pastille de l'invite (HUDController).
				prompt = ("Maintenir pour armer l'uplink  ·  site %s"):format(site)
			end
		end
	elseif live and side == "Defense" and objective.planted then
		local position = objective.position
		if position and (root.Position - position).Magnitude <= DEFUSE_RADIUS then
			action = "DefuseStart"
			if objective.defuser == myId then
				progress = 1 - (objective.defuseEndsAt - now) / math.max(mode.defuseTime, 0.1)
				prompt = "Neutralisation…"
			else
				prompt = ("Maintenir pour neutraliser%s"):format(
					if objective.halfDefused then "  ·  50 % conservés" else ""
				)
			end
		end
	end
	availableAction = action
	HUDController.setInteraction(prompt, progress)
	if interacting and action ~= interacting then
		stopInteracting()
	end

	-- Uplink armé : bips qui s'accélèrent, lumière pulsante.
	if objective.planted then
		local core = findCore(data)
		if core then
			local light = core:FindFirstChild("AS_Pulse") :: PointLight?
			if not light then
				local created = Instance.new("PointLight")
				created.Name = "AS_Pulse"
				created.Color = colors.danger
				created.Range = 14
				created.Parent = core
				light = created
			end
			local remaining = math.max(0, objective.fuseEndsAt - now)
			local fraction = math.clamp(1 - remaining / math.max(mode.fuseTime, 1), 0, 1)
			local clock = os.clock()
			if clock >= beepAt and remaining > 0 then
				beepAt = clock + (1.0 - 0.88 * fraction ^ 1.4)
				AudioController.playAt("Uplink.Beep", core.Position)
				if light then
					light.Brightness = 6
				end
			end
			if light then
				light.Brightness = math.max(0.4, light.Brightness * 0.9)
			end
		end
	end
end

---------------------------------------------------------------------------------------------
-- Événements de match
---------------------------------------------------------------------------------------------

local function teamColor(team: string?): Color3
	local myTeam = ClientState.myTeam()
	if team == nil or team == "" or myTeam == nil then
		return colors.text
	end
	return if team == myTeam then colors.ally else colors.enemy
end

local function playerName(userId: number?): string
	if not userId then
		return "?"
	end
	local other = Players:GetPlayerByUserId(userId)
	return if other then string.upper(other.DisplayName) else "?"
end

local function playerPosition(userId: number?): Vector3?
	local other = if userId then Players:GetPlayerByUserId(userId) else nil
	local character = other and other.Character
	return if character then character:GetPivot().Position else nil
end

local function onMatchEvent(packet: Types.MatchEventPacket)
	local data = matchData()
	if not data then
		return
	end
	local myTeam = ClientState.myTeam() or "A"
	local kind = packet.kind
	if kind == "RoundStart" then
		HUDController.resetRoundKills()
		local subtitle = ("%s  ·  %s"):format(
			if sideOf(data, myTeam) == "Attack" then "ATTAQUE" else "DÉFENSE",
			sideName(sideOf(data, myTeam))
		)
		local title = ("MANCHE %d"):format(packet.round or data.round)
		if packet.text == "PISTOL" then
			subtitle ..= "  ·  MANCHE PISTOLET"
		elseif packet.text == "OVERTIME" then
			subtitle ..= "  ·  PROLONGATION"
		end
		if packet.team and packet.team ~= "" then
			subtitle ..= if packet.team == myTeam then "  ·  BALLE DE MATCH" else "  ·  BALLE DE MATCH ADVERSE"
		end
		HUDController.banner(title, subtitle, colors.primary, 3)
		AudioController.play("UI.RoundStart")
	elseif kind == "Live" then
		HUDController.banner("ENGAGEZ", nil, colors.primary, 1.2)
		AudioController.play("UI.Tick")
	elseif kind == "CorePicked" then
		if packet.player == player.UserId then
			HUDController.toast("Vous portez l'uplink : rejoignez un site", "Info")
		end
	elseif kind == "CoreDropped" then
		HUDController.banner("UPLINK LÂCHÉ", nil, colors.warning, 1.6)
	elseif kind == "PlantStart" then
		local position = playerPosition(packet.player)
		if position then
			AudioController.playAt("Uplink.Plant", position, { occlusion = true })
		end
	elseif kind == "DefuseStart" then
		local position = playerPosition(packet.player)
		if position then
			AudioController.playAt("Uplink.Defuse", position, { occlusion = true })
		end
	elseif kind == "Planted" then
		local attacking = sideOf(data, myTeam) == "Attack"
		HUDController.banner(
			"UPLINK ARMÉ",
			(if attacking then "DÉFENDEZ L'UPLINK" else "NEUTRALISEZ L'UPLINK")
				.. "  ·  SITE "
				.. tostring(packet.reason or "?"),
			colors.danger,
			3
		)
		AudioController.play("Uplink.Planted")
		AudioController.duck(0.5, 1.5)
		beepAt = 0
	elseif kind == "Defused" then
		HUDController.banner("UPLINK NEUTRALISÉ", playerName(packet.player), colors.defense, 2.5)
	elseif kind == "Detonated" then
		local core = findCore(data)
		local position = if core then core.Position else data.objective.position
		if position then
			EffectsController.explosion(position)
			AudioController.playAt("Uplink.Detonate", position)
			local camera = Workspace.CurrentCamera
			local distance = if camera then (camera.CFrame.Position - position).Magnitude else 100
			CameraController.shake(math.clamp(1 - distance / 160, 0.15, 1))
		end
		LightingController.killPop()
	elseif kind == "RoundEnd" then
		stopInteracting()
		local winner = packet.team
		local reason = REASONS[packet.reason or ""] or ""
		if winner == nil or winner == "" then
			HUDController.banner("MANCHE NULLE", reason, colors.textDim, 3)
			AudioController.play("UI.RoundLose")
		elseif winner == myTeam then
			HUDController.banner("MANCHE REMPORTÉE", reason, colors.ally, 3)
			AudioController.play("UI.RoundWin")
		else
			HUDController.banner("MANCHE PERDUE", reason, colors.enemy, 3)
			AudioController.play("UI.RoundLose")
		end
	elseif kind == "SideSwapBanner" or kind == "SideSwap" then
		if kind == "SideSwapBanner" then
			HUDController.banner("CHANGEMENT DE CAMP", "MI-TEMPS", colors.secondary, 2.6)
		end
	elseif kind == "Clutch" then
		HUDController.banner("CLUTCH", playerName(packet.player), teamColor(nil), 2.4)
	elseif kind == "Ace" then
		HUDController.banner("ACE", playerName(packet.player), colors.gold, 2.4)
		AudioController.play("UI.RankUp")
	elseif kind == "FirstBlood" then
		HUDController.toast("Premier sang : " .. playerName(packet.player), "Info")
	end
end

---------------------------------------------------------------------------------------------
-- Équipement (préparation) et menu
---------------------------------------------------------------------------------------------

local function setPanel(panel: Frame, open: boolean)
	panel.Visible = open
	ClientState.setMenuOpen(loadoutPanel.Visible or pausePanel.Visible)
	LightingController.setMenuBlur(pausePanel.Visible)
end

local function renderLoadout()
	for _, child in loadoutRows:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local data = matchData()
	local entry = if data then myEntry(data) else nil
	local profile = ClientState.profileData()
	local mode = if data then modeOf(data) else nil
	local pistol = data ~= nil and mode ~= nil and not data.overtime and GameModes.isPistolRound(mode, data.round)
	for index, slot in { "Primary", "Secondary" } do
		local row = UI.frame({
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 104),
			LayoutOrder = index,
			Parent = loadoutRows,
		})
		UI.text({
			Text = (if slot == "Primary" then "PRINCIPALE" else "SECONDAIRE")
				.. (if pistol and slot == "Primary" then "  ·  INDISPONIBLE (MANCHE PISTOLET)" else ""),
			FontFace = fonts.heading,
			TextSize = 14,
			TextColor3 = colors.primary,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, 0, 0, 20),
			Parent = row,
		})
		local cards = UI.frame({
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, 24),
			Size = UDim2.new(1, 0, 0, 76),
			Parent = row,
		})
		UI.list(cards, Enum.FillDirection.Horizontal, 8)
		local selected = (if entry then entry.loadout[slot] else nil)
			or (if profile then (profile.Loadout :: any)[slot] else nil)
		for order, def in Weapons.forSlot(slot :: Types.WeaponSlot) do
			local active = def.id == selected
			local card = UI.button({
				Text = "",
				Size = UDim2.fromOffset(118, 76),
				LayoutOrder = order,
				BackgroundColor3 = if active then colors.primaryDeep else colors.panelLight,
				AutoButtonColor = false,
				Parent = cards,
			})
			UI.corner(3, card)
			UI.stroke(card, if active then colors.primary else colors.stroke, 1, 0)
			UI.text({
				Text = def.shortName,
				FontFace = fonts.heading,
				TextSize = 18,
				Position = UDim2.fromOffset(0, 10),
				Size = UDim2.new(1, 0, 0, 24),
				Parent = card,
			})
			UI.text({
				Text = def.codename,
				FontFace = fonts.mono,
				TextSize = 11,
				TextColor3 = colors.textDim,
				Position = UDim2.fromOffset(0, 36),
				Size = UDim2.new(1, 0, 0, 14),
				Parent = card,
			})
			UI.text({
				Text = ("%d RPM"):format(def.fire.rpm),
				FontFace = fonts.mono,
				TextSize = 11,
				TextColor3 = colors.textDim,
				Position = UDim2.fromOffset(0, 52),
				Size = UDim2.new(1, 0, 0, 14),
				Parent = card,
			})
			card.Activated:Connect(function()
				UI.playSound("UI.Confirm")
				Net.event("LoadoutSelect"):FireServer({ slot = slot, weapon = def.id })
				task.delay(0.25, renderLoadout)
			end)
		end
	end
end

local function toggleMenu()
	if ClientState.arena() ~= "Match" or not matchData() then
		return
	end
	local data = matchData() :: Types.MatchStateData
	if loadoutPanel.Visible then
		setPanel(loadoutPanel, false)
	elseif pausePanel.Visible then
		setPanel(pausePanel, false)
	elseif data.phase == "Prep" and not dead then
		renderLoadout()
		setPanel(loadoutPanel, true)
	else
		setPanel(pausePanel, true)
	end
end

---------------------------------------------------------------------------------------------
-- Fin de match
---------------------------------------------------------------------------------------------

local function showMatchEnd()
	local data = matchData()
	if not data then
		return
	end
	stopInteracting()
	setPanel(loadoutPanel, false)
	setPanel(pausePanel, false)
	HUDController.setVisible(false)
	MovementController.setFrozen(true)
	local myTeam = ClientState.myTeam() or "A"
	local enemy = if myTeam == "A" then "B" else "A"
	local scores = data.scores :: any
	local victory = data.winner == myTeam
	local draw = data.winner == ""
	endTitle.Text = if draw then "ÉGALITÉ" elseif victory then "VICTOIRE" else "DÉFAITE"
	endTitle.TextColor3 = if draw then colors.textDim elseif victory then colors.gold else colors.enemy
	endScore.Text = ("%d  —  %d"):format(scores[myTeam] or 0, scores[enemy] or 0)
	local mvp = data.players[tostring(data.mvp)]
	local me = myEntry(data)
	local lines = {}
	if mvp then
		table.insert(
			lines,
			('<font color="#%s">★ MVP</font>  %s  ·  %d / %d / %d  ·  %d DÉGÂTS'):format(
				colors.gold:ToHex(),
				mvp.name,
				mvp.kills,
				mvp.deaths,
				mvp.assists,
				mvp.damage
			)
		)
	end
	if me then
		table.insert(
			lines,
			("VOUS  ·  %d / %d / %d  ·  %d DÉGÂTS  ·  %d TÊTES  ·  SCORE %d"):format(
				me.kills,
				me.deaths,
				me.assists,
				me.damage,
				me.headshots,
				me.score
			)
		)
	end
	table.insert(lines, "Récompenses et progression : à votre retour au QG.")
	endDetail.Text = table.concat(lines, "\n")
	endScreen.Visible = true
	endScreen.BackgroundTransparency = 1
	UI.tween(endScreen, Theme.tween.slow, { BackgroundTransparency = 0.35 })
	UI.glitchText(endTitle, 0.6)
	AudioController.play(if victory then "UI.Victory" else "UI.Defeat")
	AudioController.duck(0.6, 3)
	local overview = overviewOf(arenaModel())
	if overview then
		local mode = modeOf(data)
		CameraController.playPath(orbitFrames(overview), if mode then mode.matchEndTime else 10)
	end
	task.delay(5, function()
		if endScreen.Visible then
			UI.tween(endTitle, Theme.tween.medium, { Position = UDim2.fromScale(0.5, 0.12) })
			HUDController.setScoreboardForced(true)
		end
	end)
end

---------------------------------------------------------------------------------------------
-- Cycle de vie
---------------------------------------------------------------------------------------------

local function onPhase(phase: string)
	if phase == lastPhase then
		return
	end
	lastPhase = phase
	local data = matchData()
	if phase == "Waiting" then
		local overview = overviewOf(arenaModel())
		if overview then
			CameraController.setScripted(overview, 60)
		end
		TransitionController.reveal()
		HUDController.banner("EN ATTENTE DES JOUEURS", nil, colors.textDim, 30)
	elseif phase == "Intro" then
		playIntro()
	elseif phase == "Prep" then
		introCard.Visible = false
		HUDController.setVisible(true)
		MovementController.setFrozen(false)
		prepHint.Text = ("[%s]  ÉQUIPEMENT"):format(keyFor("Menu"))
		prepHint.Visible = true
		refreshSites()
	elseif phase == "Live" then
		prepHint.Visible = false
		setPanel(loadoutPanel, false)
	elseif phase == "MatchEnd" then
		prepHint.Visible = false
		showMatchEnd()
		if Workspace:GetAttribute("ServerRole") == "Match" then
			TransitionController.prepareTeleport("RETOUR AU QG")
		end
	end
	if data and phase ~= "MatchEnd" then
		endScreen.Visible = false
	end
end

local function cleanupMatch()
	janitor:Cleanup()
	lastPhase = ""
	dead = false
	killcamActive = false
	pendingKillcam = nil
	interacting = nil
	introCard.Visible = false
	spectateBar.Visible = false
	killcamBar.Visible = false
	carrierBadge.Visible = false
	prepHint.Visible = false
	endScreen.Visible = false
	setPanel(loadoutPanel, false)
	setPanel(pausePanel, false)
	HUDController.setInteraction(nil)
	HUDController.setScoreboardForced(false)
	HUDController.setVisible(true)
	MovementController.setFrozen(false)
end

local function bindMatch(newReplica: ReplicaController.ClientReplica?)
	cleanupMatch()
	if not newReplica then
		if ClientState.arena() == "Match" then
			TransitionController.cover("RETOUR AU QG…")
		end
		return
	end
	local data = newReplica.data :: Types.MatchStateData
	LightingController.applyMap(data.map)
	local info = Maps.get(data.map)
	AudioController.setAmbient(if info then info.ambientSound else nil)
	janitor:Add(newReplica:listen({ "phase" }, function(value: any)
		onPhase(tostring(value))
	end))
	onPhase(data.phase)
	janitor:Add(RunService.Heartbeat:Connect(function()
		objectiveStep()
		if dead and not killcamActive then
			updateSpectate()
		end
	end))
	task.delay(1, refreshSites)
end

local function onCharacter(character: Model)
	if ClientState.arena() ~= "Match" then
		return
	end
	dead = false
	killcamActive = false
	pendingKillcam = nil
	spectateBar.Visible = false
	CameraController.spectate(nil)
	CameraController.setMode("FirstPerson")
	MovementController.setFirstPerson(true)
	TransitionController.blink()
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.Died:Connect(onDeath)
	end
end

---------------------------------------------------------------------------------------------
-- Construction de l'interface
---------------------------------------------------------------------------------------------

local function buildIntroCard()
	introCard = UI.frame({
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = gui,
	})
	local band = UI.frame({
		BackgroundColor3 = colors.void,
		BackgroundTransparency = 0.25,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 260),
		Parent = introCard,
	})
	UI.gradient(band, ColorSequence.new(colors.void), 90, NumberSequence.new(1, 0))
	introMap = UI.text({
		Text = "",
		FontFace = fonts.display,
		TextSize = 64,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, -250),
		Size = UDim2.fromOffset(900, 70),
		Parent = introCard,
	})
	UI.gradient(introMap, ColorSequence.new(colors.text, colors.primary), 0)
	introTagline = UI.text({
		Text = "",
		FontFace = fonts.body,
		TextSize = 20,
		TextColor3 = colors.textDim,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, -178),
		Size = UDim2.fromOffset(900, 26),
		Parent = introCard,
	})
	introMode = UI.text({
		Text = "",
		FontFace = fonts.heading,
		TextSize = 18,
		TextColor3 = colors.primary,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, -146),
		Size = UDim2.fromOffset(900, 24),
		Parent = introCard,
	})
	local function roster(anchorX: number): Frame
		local frame = UI.frame({
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(anchorX, 0),
			Position = UDim2.new(anchorX, if anchorX == 0 then 60 else -60, 1, -112),
			Size = UDim2.fromOffset(420, 100),
			Parent = introCard,
		})
		UI.list(
			frame,
			Enum.FillDirection.Vertical,
			2,
			if anchorX == 0 then Enum.HorizontalAlignment.Left else Enum.HorizontalAlignment.Right
		)
		return frame
	end
	introLeft = roster(0)
	introRight = roster(1)
	UI.text({
		Text = "VS",
		FontFace = fonts.display,
		TextSize = 34,
		TextColor3 = colors.textDim,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, -100),
		Size = UDim2.fromOffset(120, 40),
		Parent = introCard,
	})
end

local function bar(text: string, color: Color3): (Frame, TextLabel)
	local frame = UI.panel({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -40),
		Size = UDim2.fromOffset(640, 46),
		Visible = false,
		Parent = gui,
	})
	UI.accent(frame, color, 4)
	local label = UI.text({
		Text = text,
		FontFace = fonts.heading,
		TextSize = 18,
		Size = UDim2.fromScale(1, 1),
		Parent = frame,
	})
	return frame, label
end

local function buildPanels()
	loadoutPanel = UI.panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.fromOffset(1000, 290),
		Visible = false,
		Parent = gui,
	})
	UI.padding(loadoutPanel, 20, 20, 16, 16)
	UI.text({
		Text = "ÉQUIPEMENT DE MANCHE",
		FontFace = fonts.display,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 28),
		Parent = loadoutPanel,
	})
	loadoutRows = UI.frame({
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 1, -40),
		Parent = loadoutPanel,
	})
	UI.list(loadoutRows, Enum.FillDirection.Vertical, 6)

	pausePanel = UI.panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(940, 640),
		BackgroundTransparency = 0.05,
		Visible = false,
		Parent = gui,
	})
	UI.padding(pausePanel, 24, 24, 20, 20)
	local settingsHost = UI.frame({
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -56),
		Parent = pausePanel,
	})
	SettingsPanel.build(settingsHost)
	UI.actionButton("REPRENDRE", "Primary", function()
		setPanel(pausePanel, false)
	end, {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Parent = pausePanel,
	})

	endScreen = UI.frame({
		BackgroundColor3 = colors.void,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 2,
		Parent = gui,
	})
	endTitle = UI.text({
		Text = "",
		FontFace = fonts.display,
		TextSize = 96,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36),
		Size = UDim2.fromOffset(1200, 110),
		ZIndex = 3,
		Parent = endScreen,
	})
	UI.textStroke(endTitle, 0.4)
	endScore = UI.text({
		Text = "",
		FontFace = fonts.monoBold,
		TextSize = 44,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.47),
		Size = UDim2.fromOffset(600, 50),
		ZIndex = 3,
		Parent = endScreen,
	})
	endDetail = UI.text({
		Text = "",
		FontFace = fonts.bodyBold,
		TextSize = 20,
		TextColor3 = colors.textDim,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.54),
		Size = UDim2.fromOffset(1000, 100),
		ZIndex = 3,
		Parent = endScreen,
	})

	carrierBadge = UI.text({
		Text = "◆  UPLINK EN VOTRE POSSESSION",
		FontFace = fonts.heading,
		TextSize = 15,
		TextColor3 = colors.warning,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 34, 1, -136),
		Size = UDim2.fromOffset(330, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = false,
		Parent = gui,
	})
	UI.textStroke(carrierBadge, 0.5)
	prepHint = UI.text({
		Text = "",
		FontFace = fonts.heading,
		TextSize = 16,
		TextColor3 = colors.primary,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 128),
		Size = UDim2.fromOffset(400, 22),
		Visible = false,
		Parent = gui,
	})
	UI.textStroke(prepHint, 0.5)
end

function MatchController.start()
	gui = UI.screen("AS_Match", 15)
	buildIntroCard()
	spectateBar, spectateText = bar("", colors.primary)
	killcamBar, killcamText = bar("", colors.danger)
	buildPanels()

	ClientState.MatchChanged:Connect(bindMatch)
	local existing = ClientState.match()
	if existing then
		bindMatch(existing)
	end
	Net.event("MatchEvent").OnClientEvent:Connect(onMatchEvent)
	Net.event("Killcam").OnClientEvent:Connect(function(packet: Types.KillcamPacket)
		pendingKillcam = packet
	end)
	InputController.ActionBegan:Connect(function(action: string)
		if ClientState.arena() ~= "Match" then
			return
		end
		if action == "Interact" then
			local available: Types.InteractAction? = availableAction
			if available and not interacting then
				interacting = available
				sendInteract(available)
			end
		elseif action == "Menu" then
			if not ClientState.isOverlayOpen("Options") then
				toggleMenu()
			end
		elseif dead and not killcamActive and (action == "Fire" or action == "Aim") then
			spectateIndex += if action == "Fire" then 1 else -1
			local candidates = spectateCandidates()
			if #candidates > 0 then
				spectateIndex = ((spectateIndex - 1) % #candidates) + 1
				CameraController.spectate(candidates[spectateIndex])
			end
		end
	end)
	InputController.ActionEnded:Connect(function(action: string)
		if action == "Interact" then
			stopInteracting()
		end
	end)
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
end

return MatchController
