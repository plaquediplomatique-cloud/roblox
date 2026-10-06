--!strict
--[[
	LobbyController — le QG (hub) : orchestration de toute l'interface hors combat.

	  Barre d'identité : nom, titre, niveau + XP, rang + RR (ou placement), monnaies,
	                     party — toujours à jour via le replica de profil.
	  Menu [M]         : JOUER · ARMURERIE · CASIER · MISSIONS · PASS · CLASSEMENT ·
	                     BOUTIQUE · RÉGLAGES (onglets construits à la première ouverture).
	                     Caméra de menu : le personnage est cadré à gauche, le menu à droite.
	  Terminaux 3D     : chaque zone du hub ouvre l'onglet correspondant (ProximityPrompt).
	  File d'attente   : widget permanent (temps, estimation, joueurs en file, annuler).
	  Match trouvé     : alerte + envol caméra + transition jusqu'au chargement.
	  Social           : invitations de party et reprise de match (modales), roue d'emotes.
	  Retour de match  : résumé post-match (une seule fois par match).
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local GameModes = require(Shared.Config.GameModes)
local Maps = require(Shared.Config.Maps)
local Weapons = require(Shared.Config.Weapons)
local Cosmetics = require(Shared.Config.Cosmetics)
local Progression = require(Shared.Config.Progression)
local Ranks = require(Shared.Config.Ranks)
local Theme = require(Shared.Config.Theme)
local Onboarding = require(Shared.Rules.Onboarding)
local Net = require(Shared.Net.Net)
local UI = require(script.Parent.Parent.UI.UI)
local SettingsPanel = require(script.Parent.Parent.UI.SettingsPanel)
local ClientState = require(script.Parent.Parent.Core.ClientState)
local ReplicaController = require(script.Parent.Parent.Core.ReplicaController)
local InputController = require(script.Parent.Parent.Controllers.InputController)
local SettingsController = require(script.Parent.Parent.Controllers.SettingsController)
local CameraController = require(script.Parent.Parent.Controllers.CameraController)
local AudioController = require(script.Parent.Parent.Controllers.AudioController)
local LightingController = require(script.Parent.Parent.Controllers.LightingController)
local HUDController = require(script.Parent.Parent.Controllers.HUDController)
local TransitionController = require(script.Parent.Parent.Controllers.TransitionController)
local Remote = require(script.Parent.Remote)
local PlayTab = require(script.Parent.PlayTab)
local ArmoryTab = require(script.Parent.ArmoryTab)
local LockerTab = require(script.Parent.LockerTab)
local ProgressTabs = require(script.Parent.ProgressTabs)
local PostMatch = require(script.Parent.PostMatch)
local HubWorld = require(script.Parent.HubWorld)

local colors = Theme.colors
local fonts = Theme.fonts
local player = Players.LocalPlayer

local LobbyController = {}

type Tab = { frame: Frame, refresh: () -> (), focus: (option: string?) -> () }

local TAB_ORDER = { "Play", "Armory", "Locker", "Missions", "Pass", "Leaderboard", "Shop", "Settings" }
local TAB_LABELS: { [string]: string } = {
	Play = "JOUER",
	Armory = "ARMURERIE",
	Locker = "CASIER",
	Missions = "MISSIONS",
	Pass = "AETHER PASS",
	Leaderboard = "CLASSEMENT",
	Shop = "BOUTIQUE",
	Settings = "RÉGLAGES",
}
-- Pictogrammes de la navigation (formes géométriques : lisibles sans couleur, sans asset).
local TAB_ICONS: { [string]: string } = {
	Play = "▶",
	Armory = "◈",
	Locker = "▣",
	Missions = "◎",
	Pass = "★",
	Leaderboard = "▲",
	Shop = "◆",
	Settings = "⚙",
}
local NAV_WIDTH = 236
local NAV_ITEM_HEIGHT = 50
-- Terminal du hub -> (onglet, option)
local TERMINALS: { [string]: { tab: string, option: string? } } = {
	Play = { tab = "Play", option = nil },
	Ranked = { tab = "Play", option = "Ranked" },
	Casual = { tab = "Play", option = "Casual" },
	Custom = { tab = "Play", option = "Custom" },
	Armory = { tab = "Armory", option = nil },
	Leaderboard = { tab = "Leaderboard", option = nil },
	Missions = { tab = "Missions", option = nil },
	Pass = { tab = "Pass", option = nil },
	Settings = { tab = "Settings", option = nil },
}

local gui: ScreenGui
local topBar: Frame
local identityName: TextLabel
local levelLabel: TextLabel
local levelFill: Frame
local rankLabel: TextLabel
local walletLabel: TextLabel
local partyLabel: TextLabel
local menu: Frame
local nav: Frame
local content: Frame
local navButtons: { [string]: TextButton } = {}
local contentTitle: TextLabel? = nil
local tabs: { [string]: Tab } = {}
local currentTab: string? = nil
local queueWidget: Frame
local queueText: TextLabel
local foundOverlay: Frame
local foundTitle: TextLabel
local foundDetail: TextLabel
local modal: Frame
local modalText: TextLabel
local modalButtons: Frame
local emoteWheel: Frame
local trainingPopup: Frame
local menuCameraToken = 0

---------------------------------------------------------------------------------------------
-- Barre d'identité
---------------------------------------------------------------------------------------------

local function refreshTopBar()
	local data = ClientState.profileData()
	if not data then
		return
	end
	local title = data.Cosmetics.Title
	local titleItem = if title ~= "" then Cosmetics.get(title) else nil
	identityName.Text = player.DisplayName
		.. (
			if titleItem
				then ('  <font color="#%s">%s</font>'):format(
					colors.textDim:ToHex(),
					string.upper(titleItem.displayName)
				)
				else ""
		)
	local needed = Progression.xpForLevel(data.Level)
	levelLabel.Text = ("NIV %d"):format(data.Level)
	levelFill.Size = UDim2.fromScale(math.clamp(data.XP / needed, 0, 1), 1)
	local placed = data.Rank.Placements >= Ranks.PLACEMENT_MATCHES
	local tier = Ranks.tierOf(data.Rank.RankIndex)
	rankLabel.Text = if placed
		then ('<font color="#%s">%s %s</font>  %d RR'):format(
			tier.color:ToHex(),
			tier.glyph,
			Ranks.displayName(data.Rank.RankIndex),
			data.Rank.RR
		)
		else ("PLACEMENT %d/%d"):format(data.Rank.Placements, Ranks.PLACEMENT_MATCHES)
	walletLabel.Text = ("◈ %d   ✦ %d"):format(data.Currency.Flux, data.Currency.Crystals)
end

local function refreshParty()
	local party = ClientState.partyData()
	if not party or #party.members <= 1 then
		partyLabel.Text = "PARTY SOLO"
	else
		local names = {}
		for _, userId in party.members do
			local name = party.names[tostring(userId)] or "?"
			table.insert(names, (if userId == party.leader then "★" else "") .. name)
		end
		partyLabel.Text = ("PARTY %d  ·  %s"):format(#party.members, table.concat(names, ", "))
	end
	-- File d'attente
	local queue = party and party.queue
	local searching = queue ~= nil and queue.state ~= "Idle"
	queueWidget.Visible = searching and ClientState.arena() == "Hub"
end

local function refreshQueueText()
	local party = ClientState.partyData()
	local queue = party and party.queue
	if not (queue and queue.state ~= "Idle") then
		return
	end
	local mode = GameModes.get(queue.mode)
	queueText.Text = ("%s  ·  %s %s  ·  %s  ·  est. %s  ·  %d en file"):format(
		if queue.state == "Found" then "MATCH TROUVÉ" else "RECHERCHE",
		if mode then mode.displayName else queue.mode,
		if queue.ranked then "CLASSÉ" else "CASUAL",
		UI.formatTime(os.time() - queue.since),
		UI.formatTime(queue.estimate),
		queue.inQueue
	)
end

---------------------------------------------------------------------------------------------
-- Menu
---------------------------------------------------------------------------------------------

local function buildTab(name: string): Tab
	local holder =
		UI.frame({ BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = content })
	if name == "Play" then
		return PlayTab.build(holder) :: Tab
	elseif name == "Armory" then
		return ArmoryTab.build(holder) :: Tab
	elseif name == "Locker" then
		return LockerTab.build(holder, "Locker") :: Tab
	elseif name == "Shop" then
		return LockerTab.build(holder, "Shop") :: Tab
	elseif name == "Missions" then
		return ProgressTabs.missions(holder) :: Tab
	elseif name == "Pass" then
		return ProgressTabs.pass(holder) :: Tab
	elseif name == "Leaderboard" then
		return ProgressTabs.leaderboard(holder) :: Tab
	end
	local frame = SettingsPanel.build(holder)
	return {
		frame = frame,
		refresh = function() end,
		focus = function(_option: string?) end,
	}
end

--[[
	Entrée de la navigation : actif = verre teinté, barre cyan à gauche, texte blanc ;
	survol = fond léger ; repos = texte atténué. L'état actif ne repose pas que sur la couleur
	(barre + fond + graisse).
]]
local function styleNavItem(button: TextButton, active: boolean, hover: boolean)
	button.BackgroundColor3 = if active then colors.primaryDeep else colors.panelLight
	button.BackgroundTransparency = if active then 0.45 elseif hover then 0.6 else 1
	local bar = button:FindFirstChild("Bar")
	if bar and bar:IsA("Frame") then
		bar.Visible = active
	end
	local icon = button:FindFirstChild("Icon")
	if icon and icon:IsA("TextLabel") then
		icon.TextColor3 = if active then colors.primary else colors.textDim
	end
	local label = button:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.TextColor3 = if active or hover then colors.text else colors.textDim
		label.FontFace = if active then fonts.headingHeavy else fonts.heading
	end
end

local function selectTab(name: string, option: string?)
	local tab = tabs[name]
	if not tab then
		tab = buildTab(name)
		tabs[name] = tab
	end
	for tabName, other in tabs do
		local parent = other.frame.Parent
		if parent and parent:IsA("GuiObject") then
			parent.Visible = tabName == name
		end
		other.frame.Visible = tabName == name
	end
	for tabName, button in navButtons do
		styleNavItem(button, tabName == name, false)
	end
	if contentTitle then
		contentTitle.Text = TAB_LABELS[name] or name
	end
	currentTab = name
	tab.focus(option)
end

local function menuCamera(open: boolean)
	menuCameraToken += 1
	local token = menuCameraToken
	if not open then
		if CameraController.getMode() == "Scripted" and ClientState.arena() == "Hub" then
			CameraController.setMode("ThirdPerson")
		end
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local camera = Workspace.CurrentCamera
	if not (root and root:IsA("BasePart") and camera) then
		return
	end
	local _, yaw, _ = root.CFrame:ToEulerAnglesYXZ()
	local base = CFrame.new(root.Position) * CFrame.Angles(0, yaw, 0)
	-- Le personnage occupe le tiers gauche de l'écran, le menu le reste.
	local target =
		CFrame.lookAt((base * CFrame.new(2.6, 1.4, -8.5)).Position, (base * CFrame.new(1.9, 0.7, 0)).Position)
	local from = camera.CFrame
	local started = os.clock()
	task.spawn(function()
		while token == menuCameraToken do
			local t = math.clamp((os.clock() - started) / 0.55, 0, 1)
			local eased = t * t * (3 - 2 * t)
			CameraController.setScripted(from:Lerp(target, eased), 55)
			if t >= 1 then
				break
			end
			RunService.RenderStepped:Wait()
		end
	end)
end

function LobbyController.open(name: string, option: string?)
	if ClientState.arena() ~= "Hub" or PostMatch.isShowing() then
		return
	end
	if not menu.Visible then
		menu.Visible = true
		ClientState.setMenuOpen(true)
		LightingController.setMenuBlur(true)
		AudioController.play("UI.Whoosh")
		menuCamera(true)
	end
	selectTab(name, option)
end

function LobbyController.close()
	if not menu.Visible then
		return
	end
	menu.Visible = false
	ClientState.setMenuOpen(false)
	LightingController.setMenuBlur(false)
	AudioController.play("UI.Back")
	menuCamera(false)
end

---------------------------------------------------------------------------------------------
-- Modales, emotes, entraînement
---------------------------------------------------------------------------------------------

local function showModal(text: string, options: { { label: string, style: UI.ButtonStyle, run: () -> () } })
	modalText.Text = text
	for _, child in modalButtons:GetChildren() do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
	for order, option in options do
		local button = UI.actionButton(option.label, option.style, function()
			modal.Visible = false
			option.run()
		end, { Size = UDim2.fromOffset(180, 42), LayoutOrder = order, Parent = modalButtons })
		button.TextSize = 16
	end
	modal.Visible = true
	AudioController.play("UI.Confirm")
end

local function toggleEmoteWheel()
	if emoteWheel.Visible then
		emoteWheel.Visible = false
		ClientState.setMenuOpen(menu.Visible)
		return
	end
	if ClientState.arena() ~= "Hub" or menu.Visible then
		return
	end
	for _, child in emoteWheel:GetChildren() do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
	local data = ClientState.profileData()
	local emotes = if data then data.Cosmetics.Emotes else {}
	for index = 1, 4 do
		local id = emotes[index]
		local item = if id then Cosmetics.get(id) else nil
		local angle = math.rad(-90 + (index - 1) * 90)
		local button = UI.button({
			Text = ("%d\n%s"):format(index, if item then string.upper(item.displayName) else "—"),
			TextSize = 15,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, math.cos(angle) * 110, 0.5, math.sin(angle) * 110),
			Size = UDim2.fromOffset(130, 60),
			BackgroundColor3 = colors.panel,
			Parent = emoteWheel,
		})
		UI.corner(4, button)
		UI.stroke(button, colors.primary, 1, 0.3)
		button.Activated:Connect(function()
			emoteWheel.Visible = false
			ClientState.setMenuOpen(menu.Visible)
			if item then
				Net.event("Emote"):FireServer(index)
			end
		end)
	end
	emoteWheel.Visible = true
	ClientState.setMenuOpen(true)
end

local function showTrainingPopup()
	trainingPopup.Visible = not trainingPopup.Visible
	ClientState.setMenuOpen(trainingPopup.Visible or menu.Visible)
end

---------------------------------------------------------------------------------------------
-- Match trouvé / retour de match
---------------------------------------------------------------------------------------------

local function onMatchFound(payload: any)
	if type(payload) ~= "table" then
		return
	end
	LobbyController.close()
	local mode = GameModes.get(tostring(payload.mode))
	local map = Maps.get(tostring(payload.map))
	local countdown = tonumber(payload.countdown) or 5
	foundTitle.Text = "MATCH TROUVÉ"
	foundDetail.Text = ("%s  ·  %s"):format(
		if map then map.displayName else tostring(payload.map),
		if mode then mode.displayName else tostring(payload.mode)
	)
	foundOverlay.Visible = true
	TransitionController.prepareTeleport(
		("CONNEXION AU SERVEUR DE MATCH  ·  %s"):format(if map then map.displayName else "ARÈNE")
	)
	UI.glitchText(foundTitle, 0.4)
	AudioController.play("UI.MatchFound")
	AudioController.duck(0.6, countdown)
	-- Envol de la caméra au-dessus du QG pendant le compte à rebours.
	local camera = Workspace.CurrentCamera
	if camera then
		local start = camera.CFrame
		local up = start * CFrame.new(0, 18, 14) * CFrame.Angles(math.rad(-25), 0, 0)
		local high = start * CFrame.new(0, 60, 40) * CFrame.Angles(math.rad(-50), 0, 0)
		CameraController.playPath({ start, up, high }, math.max(countdown - 0.6, 1.5))
	end
	task.delay(math.max(countdown - 0.6, 0.5), function()
		foundOverlay.Visible = false
		TransitionController.cover(("CHARGEMENT  ·  %s"):format(if map then map.displayName else "ARÈNE"))
	end)
end

local function checkPostMatch()
	local data = ClientState.profileData()
	local summary = data and data.LastMatch
	if summary and not summary.seen and ClientState.arena() == "Hub" and not PostMatch.isShowing() then
		task.delay(1.2, function()
			if ClientState.arena() == "Hub" then
				ClientState.setMenuOpen(true)
				LightingController.setMenuBlur(true)
				PostMatch.show(gui, summary, function()
					ClientState.setMenuOpen(false)
					LightingController.setMenuBlur(false)
				end)
			end
		end)
	end
end

local function onArena(kind: Types.ArenaKind)
	local hub = kind == "Hub"
	topBar.Visible = hub
	if not hub then
		LobbyController.close()
		emoteWheel.Visible = false
		trainingPopup.Visible = false
		modal.Visible = false
	else
		LightingController.applyMap("hub")
		local info = Maps.get("hub")
		AudioController.setAmbient(if info then info.ambientSound else nil)
		TransitionController.reveal()
		checkPostMatch()
	end
	refreshParty()
end

---------------------------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------------------------

local function buildTopBar()
	topBar = UI.frame({
		Name = "TopBar",
		BackgroundColor3 = colors.void,
		BackgroundTransparency = 0.35,
		Size = UDim2.new(1, 0, 0, 58),
		Parent = gui,
	})
	UI.gradient(topBar, ColorSequence.new(colors.void), 90, NumberSequence.new(0.1, 1))
	-- Carte d'identité biseautée, posée juste après les boutons Roblox (jamais dessous).
	local identity = UI.glass(440, 50, 14, {
		Name = "Identity",
		Position = UDim2.fromOffset(160, 4),
		Parent = topBar,
	}).root
	local portraitFrame = UI.frame({
		BackgroundColor3 = colors.void,
		BackgroundTransparency = 0.25,
		Position = UDim2.fromOffset(20, 5),
		Size = UDim2.fromOffset(40, 40),
		ClipsDescendants = true,
		Parent = identity,
	})
	UI.corner(4, portraitFrame)
	UI.stroke(portraitFrame, colors.primary, 1, 0.45)
	local portrait = Instance.new("ImageLabel")
	portrait.BackgroundTransparency = 1
	portrait.Size = UDim2.fromScale(1, 1)
	portrait.Image = ("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"):format(math.max(player.UserId, 1))
	portrait.Parent = portraitFrame
	identityName = UI.text({
		Text = player.DisplayName,
		FontFace = fonts.headingHeavy,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(70, 5),
		Size = UDim2.fromOffset(200, 20),
		Parent = identity,
	})
	levelLabel = UI.text({
		Text = "NIV 1",
		FontFace = fonts.monoBold,
		TextSize = 12,
		TextColor3 = colors.primary,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(70, 27),
		Size = UDim2.fromOffset(56, 16),
		Parent = identity,
	})
	local track = UI.frame({
		BackgroundColor3 = colors.panelLight,
		Position = UDim2.fromOffset(128, 33),
		Size = UDim2.fromOffset(150, 5),
		Parent = identity,
	})
	UI.corner(2, track)
	levelFill = UI.frame({ BackgroundColor3 = colors.primary, Size = UDim2.fromScale(0, 1), Parent = track })
	UI.corner(2, levelFill)
	-- Logotype discret au centre : le coin gauche appartient à Roblox.
	UI.text({
		Text = "AETHER STRIKE",
		FontFace = fonts.brand,
		TextSize = 14,
		TextColor3 = colors.primary,
		TextTransparency = 0.25,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.fromOffset(260, 58),
		Parent = topBar,
	})
	rankLabel = UI.text({
		Text = "",
		FontFace = fonts.heading,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromOffset(426, 7),
		Size = UDim2.fromOffset(140, 18),
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = identity,
	})
	walletLabel = UI.text({
		Text = "",
		FontFace = fonts.monoBold,
		TextSize = 16,
		TextColor3 = colors.gold,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Name = "Wallet",
		Position = UDim2.new(1, -66, 0, 6),
		Size = UDim2.fromOffset(300, 22),
		Parent = topBar,
	})
	partyLabel = UI.text({
		Text = "",
		FontFace = fonts.mono,
		TextSize = 13,
		TextColor3 = colors.textDim,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Name = "Party",
		Position = UDim2.new(1, -66, 0, 32),
		Size = UDim2.fromOffset(520, 18),
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = topBar,
	})
	-- Guide « prochaine étape » (premières sessions) : une consigne, la distance au lieu visé.
	local guide = UI.glass(440, 34, 12, {
		Name = "Guide",
		Position = UDim2.fromOffset(0, 58),
		Visible = false,
		Parent = identity,
	}).root
	local guideTitle = UI.text({
		Text = "",
		FontFace = fonts.headingHeavy,
		TextSize = 11,
		TextColor3 = colors.primary,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(18, 0),
		Size = UDim2.fromOffset(90, 34),
		Parent = guide,
	})
	local guideText = UI.text({
		Text = "",
		FontFace = fonts.bodyBold,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(104, 0),
		Size = UDim2.fromOffset(268, 34),
		Parent = guide,
	})
	local guideDistance = UI.text({
		Text = "",
		FontFace = fonts.monoBold,
		TextSize = 13,
		TextColor3 = colors.primary,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -18, 0, 0),
		Size = UDim2.fromOffset(60, 34),
		Parent = guide,
	})
	local trainedThisSession = false
	local function nearestTarget(tag: string): number?
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not (root and root:IsA("BasePart")) then
			return nil
		end
		local best: number? = nil
		for _, part in CollectionService:GetTagged(tag) do
			if part:IsA("BasePart") then
				local distance = (part.Position - root.Position).Magnitude
				if not best or distance < best then
					best = distance
				end
			end
		end
		return best
	end
	task.spawn(function()
		while true do
			task.wait(0.25)
			if ClientState.arena() == "Training" then
				trainedThisSession = true
			end
			local data = ClientState.profileData()
			local step: Onboarding.Step? = nil
			if data then
				local toClaim = 0
				for _, mission in data.Missions.Daily do
					if not mission.claimed and mission.progress >= mission.target then
						toClaim += 1
					end
				end
				step = Onboarding.nextStep({
					matches = data.Stats.Matches,
					trainedThisSession = trainedThisSession,
					missionsToClaim = toClaim,
				}, SettingsController.get().Keybinds.Menu or "M")
			end
			guide.Visible = step ~= nil
			if step then
				guideTitle.Text = step.title
				guideText.Text = step.text
				local distance = if step.target then nearestTarget(step.target) else nil
				guideDistance.Text = if distance then ("%d m"):format(math.floor(distance / 3.57 + 0.5)) else ""
			end
		end
	end)
	-- Suivre la zone libre entre les boutons Roblox (gauche) et le bouton d'options (droite).
	UI.onTopbarChanged(gui, function()
		local left, right = UI.topbarClearance(gui)
		identity.Position = UDim2.fromOffset(math.max(left, 16) + 8, 4)
		local margin = right + 66 -- engrenage d'options compris
		walletLabel.Position = UDim2.new(1, -margin, 0, 6)
		partyLabel.Position = UDim2.new(1, -margin, 0, 32)
	end)
	local keysHint = UI.text({
		Text = "",
		FontFace = fonts.mono,
		TextSize = 12,
		TextColor3 = colors.textDim,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 62),
		Size = UDim2.fromOffset(760, 16),
		Parent = topBar,
	})
	-- Touches réelles du joueur (rebinding pris en compte).
	local function refreshKeysHint()
		local binds = SettingsController.get().Keybinds
		keysHint.Text = ("[%s] MENU    [%s] OPTIONS / SENSIBILITÉ    [%s] SPRINT    [%s] EMOTES    [%s] INTERAGIR"):format(
			binds.Menu or "M",
			binds.Options or "P",
			binds.Sprint or "LeftShift",
			binds.Emote or "B",
			binds.Interact or "F"
		)
	end
	refreshKeysHint()
	SettingsController.Changed:Connect(refreshKeysHint)
end

local function buildMenu()
	menu = UI.frame({
		Name = "Menu",
		BackgroundColor3 = colors.void,
		BackgroundTransparency = 0.25,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 5,
		Parent = gui,
	})
	UI.gradient(
		menu,
		ColorSequence.new(colors.void),
		0,
		NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.3, 0.6),
			NumberSequenceKeypoint.new(1, 0),
		})
	)
	-- Navigation verticale à gauche (un clic par écran, pictogramme + libellé).
	nav = UI.frame({
		Name = "Nav",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(24, 86),
		Size = UDim2.new(0, NAV_WIDTH, 1, -114),
		Parent = menu,
	})
	UI.list(nav, Enum.FillDirection.Vertical, 4)
	for order, name in TAB_ORDER do
		local button = UI.button({
			Name = name,
			Text = "",
			AutoButtonColor = false,
			Size = UDim2.new(1, 0, 0, NAV_ITEM_HEIGHT),
			LayoutOrder = order,
			Parent = nav,
		})
		UI.corner(4, button)
		UI.frame({
			Name = "Bar",
			BackgroundColor3 = colors.primary,
			Position = UDim2.fromOffset(0, 8),
			Size = UDim2.new(0, 3, 1, -16),
			Visible = false,
			Parent = button,
		})
		UI.text({
			Name = "Icon",
			Text = TAB_ICONS[name] or "•",
			FontFace = fonts.headingHeavy,
			TextSize = 18,
			Position = UDim2.fromOffset(14, 0),
			Size = UDim2.fromOffset(28, NAV_ITEM_HEIGHT),
			Parent = button,
		})
		UI.text({
			Name = "Label",
			Text = TAB_LABELS[name],
			FontFace = fonts.heading,
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(52, 0),
			Size = UDim2.new(1, -60, 1, 0),
			Parent = button,
		})
		styleNavItem(button, false, false)
		navButtons[name] = button
		button.MouseEnter:Connect(function()
			styleNavItem(button, currentTab == name, true)
		end)
		button.MouseLeave:Connect(function()
			styleNavItem(button, currentTab == name, false)
		end)
		button.Activated:Connect(function()
			UI.playSound("UI.Click")
			selectTab(name)
		end)
	end
	-- Contenu : grand panneau de verre, titre de l'onglet en tête.
	local panel = UI.panel({
		Name = "Content",
		Position = UDim2.fromOffset(24 + NAV_WIDTH + 16, 86),
		Size = UDim2.new(1, -(24 + NAV_WIDTH + 16 + 28), 1, -114),
		BackgroundTransparency = 0.08,
		Parent = menu,
	})
	contentTitle = UI.text({
		Name = "Title",
		Text = "",
		FontFace = fonts.display,
		TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(24, 12),
		Size = UDim2.new(1, -200, 0, 36),
		Parent = panel,
	})
	UI.frame({
		Name = "Rule",
		BackgroundColor3 = colors.primary,
		BackgroundTransparency = 0.4,
		Position = UDim2.fromOffset(24, 52),
		Size = UDim2.fromOffset(48, 2),
		Parent = panel,
	})
	content = UI.frame({
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(20, 68),
		Size = UDim2.new(1, -40, 1, -88),
		Parent = panel,
	})
	local close = UI.actionButton("✕ FERMER", "Ghost", LobbyController.close, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -40, 0, 96),
		Size = UDim2.fromOffset(130, 34),
		Parent = menu,
	})
	close.TextSize = 14
end

local function buildOverlays()
	queueWidget = UI.panel({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 86),
		Size = UDim2.fromOffset(620, 44),
		Visible = false,
		Parent = gui,
	})
	UI.accent(queueWidget, colors.warning, 4)
	queueText = UI.text({
		Text = "",
		FontFace = fonts.mono,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(18, 0),
		Size = UDim2.new(1, -140, 1, 0),
		Parent = queueWidget,
	})
	local cancel = UI.actionButton("ANNULER", "Danger", function()
		Remote.call("QueueAction", { action = "Leave" })
	end, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(110, 32),
		Parent = queueWidget,
	})
	cancel.TextSize = 13

	foundOverlay = UI.frame({
		BackgroundColor3 = colors.void,
		BackgroundTransparency = 0.45,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 20,
		Parent = gui,
	})
	foundTitle = UI.text({
		Text = "",
		FontFace = fonts.display,
		TextSize = 72,
		TextColor3 = colors.primary,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(1000, 84),
		ZIndex = 21,
		Parent = foundOverlay,
	})
	foundDetail = UI.text({
		Text = "",
		FontFace = fonts.heading,
		TextSize = 24,
		TextColor3 = colors.text,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.42, 66),
		Size = UDim2.fromOffset(1000, 30),
		ZIndex = 21,
		Parent = foundOverlay,
	})

	modal = UI.panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(520, 170),
		Visible = false,
		ZIndex = 30,
		Parent = gui,
	})
	UI.accent(modal, colors.primary, 4)
	modalText = UI.text({
		Text = "",
		FontFace = fonts.heading,
		TextSize = 19,
		TextWrapped = true,
		Position = UDim2.fromOffset(20, 16),
		Size = UDim2.new(1, -40, 0, 70),
		ZIndex = 31,
		Parent = modal,
	})
	modalButtons = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.new(1, -40, 0, 44),
		ZIndex = 31,
		Parent = modal,
	})
	UI.list(modalButtons, Enum.FillDirection.Horizontal, 12, Enum.HorizontalAlignment.Center)

	emoteWheel = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(400, 320),
		Visible = false,
		Parent = gui,
	})
	UI.text({
		Text = "EMOTES",
		FontFace = fonts.display,
		TextSize = 18,
		TextColor3 = colors.textDim,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(160, 30),
		Parent = emoteWheel,
	})

	trainingPopup = UI.panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.fromOffset(420, 250),
		Visible = false,
		Parent = gui,
	})
	UI.padding(trainingPopup, 20, 20, 16, 16)
	UI.list(trainingPopup, Enum.FillDirection.Vertical, 10, Enum.HorizontalAlignment.Center)
	UI.text({
		Text = "STAND DE TIR",
		FontFace = fonts.display,
		TextSize = 20,
		Size = UDim2.new(1, 0, 0, 28),
		Parent = trainingPopup,
	})
	for order, entry in
		{
			{ label = "RÉINITIALISER LES STATS", action = "ResetStats" },
			{ label = "BOUCLIERS DES DRONES", action = "ToggleArmor" },
			{ label = "RECHARGER LES MUNITIONS", action = "Refill" },
		}
	do
		local button = UI.actionButton(entry.label, "Secondary", function()
			if Remote.call("TrainingAction", { action = entry.action }).ok then
				HUDController.toast(entry.label, "Info")
			end
		end, { Size = UDim2.fromOffset(340, 40), LayoutOrder = order, Parent = trainingPopup })
		button.TextSize = 15
	end
	UI.actionButton("FERMER", "Ghost", showTrainingPopup, {
		Size = UDim2.fromOffset(160, 36),
		LayoutOrder = 10,
		Parent = trainingPopup,
	})
end

function LobbyController.start()
	gui = UI.screen("AS_Lobby", 30)
	buildTopBar()
	buildMenu()
	buildOverlays()
	Remote.setToast(HUDController.toast)
	HubWorld.start()
	HubWorld.onInspect(function(weaponId: string)
		local def = Weapons.get(weaponId)
		LobbyController.open("Armory", if def then def.slot else nil)
	end)

	ClientState.ProfileReady:Connect(function(replica: ReplicaController.ClientReplica)
		replica.Changed:Connect(refreshTopBar)
		replica:listen({ "LastMatch" }, function()
			checkPostMatch()
		end)
		refreshTopBar()
		checkPostMatch()
	end)
	local profile = ClientState.profile()
	if profile then
		profile.Changed:Connect(refreshTopBar)
		refreshTopBar()
	end
	ClientState.PartyChanged:Connect(refreshParty)
	ClientState.ArenaChanged:Connect(onArena)
	onArena((ClientState.arena()))

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		local holder = prompt.Parent
		local action = if holder then holder:GetAttribute("Action") else nil
		if type(action) ~= "string" then
			return
		end
		if action == "Training" then
			showTrainingPopup()
			return
		end
		local target = TERMINALS[action]
		if target then
			LobbyController.open(target.tab, target.option)
		end
	end)
	InputController.ActionBegan:Connect(function(action: string)
		if ClientState.arena() ~= "Hub" then
			return
		end
		if action == "Menu" then
			if ClientState.isOverlayOpen("Options") then
				return
			end
			if menu.Visible then
				LobbyController.close()
			elseif not PostMatch.isShowing() then
				LobbyController.open(currentTab or "Play")
			end
		elseif action == "Emote" then
			toggleEmoteWheel()
		end
	end)

	Net.event("MatchFound").OnClientEvent:Connect(onMatchFound)
	Net.event("Notify").OnClientEvent:Connect(function(payload: any)
		if type(payload) ~= "table" then
			return
		end
		if payload.kind == "PartyInvite" and type(payload.partyId) == "string" then
			local partyId = payload.partyId :: string
			showModal(tostring(payload.text), {
				{
					label = "ACCEPTER",
					style = "Primary",
					run = function()
						Remote.call("PartyAction", { action = "Accept", partyId = partyId })
					end,
				},
				{
					label = "REFUSER",
					style = "Ghost",
					run = function()
						Remote.call("PartyAction", { action = "Decline", partyId = partyId })
					end,
				},
			})
		elseif payload.kind == "RejoinAvailable" then
			showModal(tostring(payload.text), {
				{
					label = "REJOINDRE",
					style = "Primary",
					run = function()
						Remote.call("QueueAction", { action = "Rejoin" })
					end,
				},
				{ label = "PLUS TARD", style = "Ghost", run = function() end },
			})
		end
	end)

	task.spawn(function()
		while true do
			task.wait(1)
			refreshQueueText()
		end
	end)
end

return LobbyController
