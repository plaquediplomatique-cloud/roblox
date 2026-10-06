--!strict
--[[
	PlayTab — JOUER : modes, file d'attente, party et salons personnalisés.

	  Modes        : cartes Duel / Wingman / Squad / Clash ; bascule CLASSÉ / CASUAL
	                 (le serveur refuse un mode non classable). Le choix est celui de la
	                 party (SetMode) : tous les membres le voient.
	  Recherche    : bouton unique RECHERCHER / ANNULER (leader) ; l'état de file vit
	                 dans le replica de party (temps écoulé, estimation, joueurs en file).
	  Party        : membres (leader, rang), inviter les joueurs du serveur, exclure,
	                 promouvoir, verrouiller, quitter.
	  Personnalisé : créer un salon (code à 5 caractères), rejoindre par code, équipes,
	                 mode/carte (hôte), lancer — replica "CustomRoom".
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local GameModes = require(Shared.Config.GameModes)
local Maps = require(Shared.Config.Maps)
local Ranks = require(Shared.Config.Ranks)
local Theme = require(Shared.Config.Theme)
local UI = require(script.Parent.Parent.UI.UI)
local ClientState = require(script.Parent.Parent.Core.ClientState)
local ReplicaController = require(script.Parent.Parent.Core.ReplicaController)
local Remote = require(script.Parent.Remote)

local colors = Theme.colors
local fonts = Theme.fonts
local player = Players.LocalPlayer

local PlayTab = {}

export type Tab = { frame: Frame, refresh: () -> (), focus: (option: string?) -> () }

-- Titre de section : filet d'accent + capitales (même grammaire que le HUD).
local function heading(parent: Instance, text: string, order: number): TextLabel
	local label = UI.text({
		Text = text,
		FontFace = fonts.headingHeavy,
		TextSize = 14,
		TextColor3 = colors.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 22),
		LayoutOrder = order,
		Parent = parent,
	})
	UI.padding(label, 12, 0, 0, 0)
	UI.frame({
		Name = "Accent",
		BackgroundColor3 = colors.primary,
		Position = UDim2.new(0, -12, 0.5, -7),
		Size = UDim2.fromOffset(3, 14),
		Parent = label,
	})
	return label
end

-- Couleur d'ambiance de chaque mode (visuel de la carte) : jetons du thème uniquement.
local MODE_ACCENTS: { [string]: Color3 } = {
	Duel = colors.gold,
	Wingman = colors.secondary,
	Squad = colors.primary,
	Clash2 = colors.attack,
	Clash3 = colors.danger,
}

-- « 3v3 — Attaque/Défense… » -> « Attaque/Défense… » (le format est déjà dans l'étiquette).
local function shortTagline(tagline: string): string
	return (string.gsub(tagline, "^%d+v%d+%s*—%s*", ""))
end

local function isLeader(party: Types.PartyData?): boolean
	return party ~= nil and party.leader == player.UserId
end

function PlayTab.build(parent: Instance): Tab
	local frame = UI.frame({ BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = parent })

	-- Colonne gauche : modes + recherche
	local left = UI.frame({ BackgroundTransparency = 1, Size = UDim2.new(0.62, -10, 1, 0), Parent = frame })
	UI.list(left, Enum.FillDirection.Vertical, 10)
	heading(left, "MODE DE JEU", 1)
	local rankedRow =
		UI.frame({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 2, Parent = left })
	UI.list(rankedRow, Enum.FillDirection.Horizontal, 8)
	local cards =
		UI.frame({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 380), LayoutOrder = 3, Parent = left })
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0.5, -6, 0, 118)
	grid.CellPadding = UDim2.fromOffset(10, 10)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = cards
	local queueRow =
		UI.frame({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 60), LayoutOrder = 4, Parent = left })
	local queueStatus = UI.text({
		Text = "",
		FontFace = fonts.mono,
		TextSize = 15,
		TextColor3 = colors.textDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(300, 0),
		Size = UDim2.new(1, -300, 1, 0),
		TextWrapped = true,
		Parent = queueRow,
	})

	-- Colonne droite : party + personnalisé
	local right = UI.frame({
		BackgroundTransparency = 1,
		Position = UDim2.new(0.62, 10, 0, 0),
		Size = UDim2.new(0.38, -10, 1, 0),
		Parent = frame,
	})
	UI.list(right, Enum.FillDirection.Vertical, 8)
	heading(right, "PARTY", 1)
	local members =
		UI.frame({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 140), LayoutOrder = 2, Parent = right })
	UI.list(members, Enum.FillDirection.Vertical, 4)
	local partyButtons =
		UI.frame({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36), LayoutOrder = 3, Parent = right })
	UI.list(partyButtons, Enum.FillDirection.Horizontal, 6)
	heading(right, "INVITER", 4)
	local invites = Instance.new("ScrollingFrame")
	invites.BackgroundTransparency = 1
	invites.BorderSizePixel = 0
	invites.Size = UDim2.new(1, 0, 0, 120)
	invites.AutomaticCanvasSize = Enum.AutomaticSize.Y
	invites.CanvasSize = UDim2.new()
	invites.ScrollBarThickness = 3
	invites.LayoutOrder = 5
	invites.Parent = right
	UI.list(invites, Enum.FillDirection.Vertical, 4)
	heading(right, "PARTIE PERSONNALISÉE", 6)
	local custom =
		UI.frame({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 230), LayoutOrder = 7, Parent = right })
	UI.list(custom, Enum.FillDirection.Vertical, 6)

	local selectedRanked = true

	local function refreshModes()
		for _, child in cards:GetChildren() do
			if child:IsA("GuiButton") then
				child:Destroy()
			end
		end
		for _, child in rankedRow:GetChildren() do
			if child:IsA("GuiButton") then
				child:Destroy()
			end
		end
		local party = ClientState.partyData()
		local leader = isLeader(party)
		local currentMode = if party then party.mode else "Squad"
		if party then
			selectedRanked = party.ranked
		end
		for index, label in { "CLASSÉ", "CASUAL" } do
			local ranked = index == 1
			local active = ranked == selectedRanked
			local button = UI.button({
				Text = label,
				Size = UDim2.fromOffset(150, 36),
				LayoutOrder = index,
				BackgroundColor3 = if active
					then (if ranked then colors.warning else colors.success)
					else colors.panelLight,
				TextColor3 = if active then colors.void else colors.textDim,
				Parent = rankedRow,
			})
			UI.corner(3, button)
			button.Activated:Connect(function()
				if not leader then
					return
				end
				UI.playSound("UI.Click")
				Remote.call("PartyAction", { action = "SetMode", mode = currentMode, value = ranked })
			end)
		end
		for order, modeId in GameModes.order do
			local mode = GameModes.get(modeId)
			if not mode then
				continue
			end
			local available = if selectedRanked then mode.ranked else mode.casual
			local active = modeId == currentMode
			local accent = MODE_ACCENTS[modeId] or colors.primary
			local card = UI.button({
				Text = "",
				AutoButtonColor = false,
				ClipsDescendants = true,
				LayoutOrder = order,
				BackgroundColor3 = colors.panel,
				BackgroundTransparency = if available then 0.05 else 0.5,
				Parent = cards,
			})
			UI.corner(4, card)
			UI.stroke(card, if active then colors.primary else colors.stroke, if active then 2 else 1, 0)
			-- Visuel : lumière de la couleur du mode venue du coin haut-droit.
			local art = UI.frame({
				Name = "Art",
				BackgroundColor3 = accent,
				Size = UDim2.fromScale(1, 1),
				Parent = card,
			})
			UI.gradient(
				art,
				ColorSequence.new(accent),
				155,
				NumberSequence.new({
					NumberSequenceKeypoint.new(0, if available then 0.55 else 0.85),
					NumberSequenceKeypoint.new(0.55, 0.92),
					NumberSequenceKeypoint.new(1, 1),
				})
			)
			local format = ("%dv%d"):format(mode.teamSize, mode.teamSize)
			UI.text({
				Name = "Watermark",
				Text = format,
				FontFace = fonts.display,
				TextSize = 76,
				TextColor3 = colors.text,
				TextTransparency = 0.9,
				TextXAlignment = Enum.TextXAlignment.Right,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, 10, 0.5, 6),
				Size = UDim2.fromOffset(220, 80),
				Parent = card,
			})
			UI.text({
				Text = mode.displayName,
				FontFace = fonts.display,
				TextSize = 22,
				TextXAlignment = Enum.TextXAlignment.Left,
				Position = UDim2.fromOffset(16, 12),
				Size = UDim2.new(1, -110, 0, 26),
				TextColor3 = if available then colors.text else colors.textFaint,
				Parent = card,
			})
			local tag = UI.text({
				Name = "Format",
				Text = format,
				FontFace = fonts.monoBold,
				TextSize = 12,
				TextColor3 = colors.void,
				BackgroundColor3 = accent,
				BackgroundTransparency = if available then 0 else 0.6,
				AutomaticSize = Enum.AutomaticSize.X,
				Position = UDim2.fromOffset(16, 42),
				Size = UDim2.fromOffset(0, 18),
				Parent = card,
			})
			UI.corner(3, tag)
			UI.padding(tag, 6, 6, 0, 0)
			UI.text({
				Text = shortTagline(mode.tagline),
				FontFace = fonts.body,
				TextSize = 14,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextColor3 = colors.textDim,
				Position = UDim2.fromOffset(62, 42),
				Size = UDim2.new(1, -78, 0, 18),
				Parent = card,
			})
			-- Cartes jouables : une pastille par carte.
			local chips = UI.frame({
				Name = "Maps",
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(16, 76),
				Size = UDim2.new(1, -32, 0, 22),
				Parent = card,
			})
			UI.list(
				chips,
				Enum.FillDirection.Horizontal,
				6,
				Enum.HorizontalAlignment.Left,
				Enum.VerticalAlignment.Center
			)
			if available then
				for index, mapId in mode.maps do
					local info = Maps.get(mapId)
					local chip = UI.text({
						Text = string.upper(if info then info.displayName else mapId),
						FontFace = fonts.heading,
						TextSize = 11,
						TextColor3 = colors.text,
						BackgroundColor3 = colors.void,
						BackgroundTransparency = 0.45,
						AutomaticSize = Enum.AutomaticSize.X,
						Size = UDim2.fromOffset(0, 20),
						LayoutOrder = index,
						Parent = chips,
					})
					UI.corner(3, chip)
					UI.padding(chip, 8, 8, 0, 0)
				end
			else
				UI.text({
					Text = "INDISPONIBLE EN " .. (if selectedRanked then "CLASSÉ" else "CASUAL"),
					FontFace = fonts.heading,
					TextSize = 11,
					TextColor3 = colors.danger,
					AutomaticSize = Enum.AutomaticSize.X,
					Size = UDim2.fromOffset(0, 20),
					Parent = chips,
				})
			end
			-- Sélection : coche dans le coin (la sélection ne repose pas que sur la couleur).
			if active then
				local check = UI.text({
					Name = "Check",
					Text = "✓",
					FontFace = fonts.headingHeavy,
					TextSize = 14,
					TextColor3 = colors.void,
					BackgroundColor3 = colors.primary,
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, -10, 0, 10),
					Size = UDim2.fromOffset(22, 22),
					Parent = card,
				})
				UI.corner(11, check)
			end
			card.MouseEnter:Connect(function()
				if available then
					card.BackgroundColor3 = colors.panelLight
				end
			end)
			card.MouseLeave:Connect(function()
				card.BackgroundColor3 = colors.panel
			end)
			card.Activated:Connect(function()
				if not (leader and available) then
					return
				end
				UI.playSound("UI.Click")
				Remote.call("PartyAction", { action = "SetMode", mode = modeId, value = selectedRanked })
			end)
		end
	end

	local queueButton = UI.actionButton("RECHERCHER", "Primary", function() end, {
		Size = UDim2.fromOffset(280, 58),
		Parent = queueRow,
	})
	queueButton.TextSize = 24
	queueButton.FontFace = fonts.display
	queueButton.Activated:Connect(function()
		local party = ClientState.partyData()
		if not party then
			return
		end
		if party.queue.state == "Idle" then
			Remote.call("QueueAction", { action = "Join", mode = party.mode, ranked = party.ranked })
		else
			Remote.call("QueueAction", { action = "Leave" })
		end
	end)

	local function refreshQueue()
		local party = ClientState.partyData()
		local leader = isLeader(party)
		local queue = if party then party.queue else nil
		local searching = queue ~= nil and queue.state ~= "Idle"
		queueButton.Text = if searching then "ANNULER" else "RECHERCHER"
		queueButton.BackgroundColor3 = if searching then colors.danger else colors.primary
		queueButton.Active = leader
		queueButton.AutoButtonColor = false
		queueButton.BackgroundTransparency = if leader then 0 else 0.5
		if queue and searching then
			queueStatus.Text = ("%s  ·  %s\nestimation %s  ·  %d en file"):format(
				if queue.state == "Found" then "MATCH TROUVÉ" else "RECHERCHE",
				UI.formatTime(os.time() - queue.since),
				UI.formatTime(queue.estimate),
				queue.inQueue
			)
		elseif not leader then
			queueStatus.Text = "Seul le leader de la party lance la recherche."
		else
			queueStatus.Text = "ⓘ  Adversaires choisis selon ton rang ; la recherche s'élargit avec l'attente."
		end
	end

	local function memberRow(userId: number, party: Types.PartyData, order: number)
		local key = tostring(userId)
		local leaderId = party.leader
		local row = UI.panel({ Size = UDim2.new(1, 0, 0, 30), LayoutOrder = order, Parent = members })
		local rankIndex = party.ranks[key] or 0
		local tier = Ranks.tierOf(rankIndex)
		UI.text({
			Text = ('<font color="#%s">%s</font>  %s%s'):format(
				tier.color:ToHex(),
				tier.glyph,
				party.names[key] or "?",
				if userId == leaderId then "  ★" else ""
			),
			FontFace = fonts.bodyBold,
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(10, 0),
			Size = UDim2.new(1, -120, 1, 0),
			Parent = row,
		})
		if isLeader(party) and userId ~= player.UserId then
			local function small(text: string, x: number, onClick: () -> ())
				local button = UI.button({
					Text = text,
					TextSize = 12,
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, x, 0.5, 0),
					Size = UDim2.fromOffset(52, 22),
					Parent = row,
				})
				UI.corner(3, button)
				button.Activated:Connect(onClick)
			end
			small("EXCLURE", -6, function()
				Remote.call("PartyAction", { action = "Kick", target = userId })
			end)
			small("LEADER", -62, function()
				Remote.call("PartyAction", { action = "Promote", target = userId })
			end)
		end
	end

	local function refreshParty()
		for _, child in members:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		for _, child in partyButtons:GetChildren() do
			if child:IsA("GuiButton") then
				child:Destroy()
			end
		end
		for _, child in invites:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		local party = ClientState.partyData()
		if not party then
			return
		end
		for order, userId in party.members do
			memberRow(userId, party, order)
		end
		local leader = isLeader(party)
		if leader then
			local lock = UI.actionButton(
				if party.locked then "DÉVERROUILLER" else "VERROUILLER",
				"Secondary",
				function()
					Remote.call("PartyAction", { action = "Lock", value = not party.locked })
				end,
				{ Size = UDim2.fromOffset(150, 34), LayoutOrder = 1, Parent = partyButtons }
			)
			lock.TextSize = 14
		end
		if #party.members > 1 then
			local leave = UI.actionButton("QUITTER", "Danger", function()
				Remote.call("PartyAction", { action = "Leave" })
			end, { Size = UDim2.fromOffset(120, 34), LayoutOrder = 2, Parent = partyButtons })
			leave.TextSize = 14
		end
		local inParty: { [number]: boolean } = {}
		for _, userId in party.members do
			inParty[userId] = true
		end
		local order = 0
		for _, other in Players:GetPlayers() do
			if inParty[other.UserId] then
				continue
			end
			order += 1
			local row = UI.frame({
				BackgroundColor3 = colors.panel,
				BackgroundTransparency = 0.3,
				Size = UDim2.new(1, -6, 0, 30),
				LayoutOrder = order,
				Parent = invites,
			})
			UI.text({
				Text = other.DisplayName,
				FontFace = fonts.body,
				TextSize = 15,
				TextXAlignment = Enum.TextXAlignment.Left,
				Position = UDim2.fromOffset(10, 0),
				Size = UDim2.new(1, -100, 1, 0),
				Parent = row,
			})
			local pending = party.invites[tostring(other.UserId)] ~= nil
			local button = UI.button({
				Text = if pending then "ENVOYÉE" else "INVITER",
				TextSize = 12,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -6, 0.5, 0),
				Size = UDim2.fromOffset(80, 22),
				BackgroundColor3 = if pending then colors.panelLight else colors.primaryDeep,
				Parent = row,
			})
			UI.corner(3, button)
			button.Activated:Connect(function()
				if leader and not pending then
					UI.playSound("UI.Confirm")
					Remote.call("PartyAction", { action = "Invite", target = other.UserId })
				end
			end)
		end
		if order == 0 then
			local row = UI.frame({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), Parent = invites })
			UI.text({
				Text = "Aucun autre joueur sur ce serveur.",
				TextSize = 14,
				TextColor3 = colors.textDim,
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.fromScale(1, 1),
				Parent = row,
			})
		end
	end

	-- Salons personnalisés
	local codeBox = Instance.new("TextBox")
	local function refreshCustom()
		for _, child in custom:GetChildren() do
			if not child:IsA("UIListLayout") then
				child:Destroy()
			end
		end
		local room = ReplicaController.get("CustomRoom")
		local data = room and room.data
		if not (data and data.code) then
			local createRow = UI.frame({
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 40),
				LayoutOrder = 1,
				Parent = custom,
			})
			UI.list(createRow, Enum.FillDirection.Horizontal, 8)
			local create = UI.actionButton("CRÉER UN SALON", "Secondary", function()
				local party = ClientState.partyData()
				Remote.call("CustomAction", { action = "Create", mode = if party then party.mode else "Clash3" })
				task.delay(0.3, refreshCustom)
			end, { Size = UDim2.fromOffset(190, 38), Parent = createRow })
			create.TextSize = 15
			local joinRow = UI.frame({
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 40),
				LayoutOrder = 2,
				Parent = custom,
			})
			UI.list(joinRow, Enum.FillDirection.Horizontal, 8)
			codeBox = Instance.new("TextBox")
			codeBox.PlaceholderText = "CODE"
			codeBox.Text = ""
			codeBox.FontFace = fonts.monoBold
			codeBox.TextSize = 18
			codeBox.TextColor3 = colors.text
			codeBox.PlaceholderColor3 = colors.textDim
			codeBox.BackgroundColor3 = colors.panelLight
			codeBox.Size = UDim2.fromOffset(120, 38)
			codeBox.ClearTextOnFocus = false
			codeBox.Parent = joinRow
			UI.corner(3, codeBox)
			local join = UI.actionButton("REJOINDRE", "Ghost", function()
				Remote.call("CustomAction", { action = "Join", code = string.upper(codeBox.Text) })
				task.delay(0.3, refreshCustom)
			end, { Size = UDim2.fromOffset(140, 38), Parent = joinRow })
			join.TextSize = 15
			return
		end
		local host = data.host == player.UserId
		local mode = GameModes.get(tostring(data.mode))
		local info = Maps.get(tostring(data.map))
		UI.text({
			Text = ("SALON  %s   ·   %s   ·   %s"):format(
				tostring(data.code),
				if mode then mode.displayName else tostring(data.mode),
				if info then info.displayName else tostring(data.map)
			),
			FontFace = fonts.monoBold,
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, 0, 0, 22),
			LayoutOrder = 1,
			Parent = custom,
		})
		local teams: { [string]: { string } } = { A = {}, B = {}, Spectator = {} }
		for _, member in (data.members or {}) :: { [string]: any } do
			local list = teams[tostring(member.team)]
			if list then
				table.insert(list, tostring(member.name))
			end
		end
		for index, team in { "A", "B", "Spectator" } do
			local row = UI.frame({
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 30),
				LayoutOrder = 1 + index,
				Parent = custom,
			})
			local button = UI.button({
				Text = if team == "Spectator" then "SPECT." else "ÉQUIPE " .. team,
				TextSize = 12,
				Size = UDim2.fromOffset(78, 26),
				BackgroundColor3 = if team == "A"
					then colors.attack
					elseif team == "B" then colors.defense
					else colors.panelLight,
				Parent = row,
			})
			UI.corner(3, button)
			button.Activated:Connect(function()
				Remote.call("CustomAction", { action = "SetTeam", team = team })
			end)
			UI.text({
				Text = table.concat(teams[team], ", "),
				TextSize = 14,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Position = UDim2.fromOffset(86, 0),
				Size = UDim2.new(1, -86, 1, 0),
				Parent = row,
			})
		end
		local actions =
			UI.frame({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 38), LayoutOrder = 6, Parent = custom })
		UI.list(actions, Enum.FillDirection.Horizontal, 6)
		if host then
			local function cycle(list: { string }, current: string, step: number): string
				local index = table.find(list, current) or 1
				return list[((index - 1 + step) % #list) + 1]
			end
			local modeButton = UI.actionButton("MODE ›", "Ghost", function()
				Remote.call(
					"CustomAction",
					{ action = "SetMode", mode = cycle(GameModes.order, tostring(data.mode), 1) }
				)
			end, { Size = UDim2.fromOffset(96, 34), Parent = actions })
			modeButton.TextSize = 13
			local mapButton = UI.actionButton("CARTE ›", "Ghost", function()
				local maps = if mode then mode.maps else { tostring(data.map) }
				Remote.call("CustomAction", { action = "SetMap", map = cycle(maps, tostring(data.map), 1) })
			end, { Size = UDim2.fromOffset(96, 34), Parent = actions })
			mapButton.TextSize = 13
			local start = UI.actionButton("LANCER", "Primary", function()
				Remote.call("CustomAction", { action = "Start" })
			end, { Size = UDim2.fromOffset(110, 34), Parent = actions })
			start.TextSize = 14
		end
		local leave = UI.actionButton("QUITTER", "Danger", function()
			Remote.call("CustomAction", { action = "Leave" })
			task.delay(0.3, refreshCustom)
		end, { Size = UDim2.fromOffset(100, 34), Parent = actions })
		leave.TextSize = 13
	end

	ReplicaController.onNew("CustomRoom", function(room: ReplicaController.ClientReplica)
		room.Changed:Connect(refreshCustom)
		room.Destroyed:Connect(function()
			task.defer(refreshCustom)
		end)
		refreshCustom()
	end)

	local function refresh()
		refreshModes()
		refreshQueue()
		refreshParty()
		refreshCustom()
	end
	ClientState.PartyChanged:Connect(function()
		if frame.Visible then
			refreshModes()
			refreshParty()
			refreshQueue()
		end
	end)
	Players.PlayerAdded:Connect(function()
		if frame.Visible then
			refreshParty()
		end
	end)
	Players.PlayerRemoving:Connect(function()
		if frame.Visible then
			task.defer(refreshParty)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			if frame.Visible then
				refreshQueue()
			end
		end
	end)

	local function focus(option: string?)
		local party = ClientState.partyData()
		if option == "Ranked" or option == "Casual" then
			local ranked = option == "Ranked"
			if party and isLeader(party) and party.ranked ~= ranked then
				local mode = GameModes.get(party.mode)
				local target = party.mode
				if mode and ranked and not mode.ranked then
					target = "Squad"
				end
				Remote.call("PartyAction", { action = "SetMode", mode = target, value = ranked })
			end
		end
		refresh()
	end

	return { frame = frame, refresh = refresh, focus = focus }
end

return PlayTab
