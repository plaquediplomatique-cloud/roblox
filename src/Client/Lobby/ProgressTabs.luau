--!strict
--[[
	ProgressTabs — MISSIONS, AETHER PASS et CLASSEMENT.

	  Missions   : 3 quotidiennes (1 reroll/jour) + 4 hebdomadaires, progression répliquée
	               en direct (le serveur l'incrémente sur les événements de jeu), réclamation
	               explicite (XP + Flux), comptes à rebours de renouvellement (UTC).
	  Pass       : 50 paliers × 3000 XP, piste gratuite et premium, réclamation par palier ;
	               palier courant mis en avant et centré.
	  Classement : top saisonnier (OrderedDataStore, rafraîchi par le serveur) + votre
	               position de rang (palier, division, RR).
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Missions = require(Shared.Config.Missions)
local Progression = require(Shared.Config.Progression)
local Cosmetics = require(Shared.Config.Cosmetics)
local Ranks = require(Shared.Config.Ranks)
local Theme = require(Shared.Config.Theme)
local UI = require(script.Parent.Parent.UI.UI)
local ClientState = require(script.Parent.Parent.Core.ClientState)
local ReplicaController = require(script.Parent.Parent.Core.ReplicaController)
local Remote = require(script.Parent.Remote)

local colors = Theme.colors
local fonts = Theme.fonts

local ProgressTabs = {}

export type Tab = { frame: Frame, refresh: () -> (), focus: (option: string?) -> () }

local function onProfileChange(frame: Frame, render: () -> ())
	local function hook(replica: any)
		replica.Changed:Connect(function()
			if frame.Visible then
				task.defer(render)
			end
		end)
	end
	ClientState.ProfileReady:Connect(hook)
	local existing = ClientState.profile()
	if existing then
		hook(existing)
	end
end

local function clear(container: Instance)
	for _, child in container:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

---------------------------------------------------------------------------------------------
-- Missions
---------------------------------------------------------------------------------------------

function ProgressTabs.missions(parent: Instance): Tab
	local frame = UI.frame({ BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = parent })
	local body = Instance.new("ScrollingFrame")
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.Size = UDim2.fromScale(1, 1)
	body.AutomaticCanvasSize = Enum.AutomaticSize.Y
	body.CanvasSize = UDim2.new()
	body.ScrollBarThickness = 4
	body.Parent = frame
	UI.list(body, Enum.FillDirection.Vertical, 8)

	local function row(order: number, progress: Types.MissionProgress, list: string, index: number, rerolls: number)
		local def = Missions.byId[progress.id]
		local done = progress.progress >= progress.target
		local panel = UI.panel({ Size = UDim2.new(1, -8, 0, 70), LayoutOrder = order, Parent = body })
		UI.accent(
			panel,
			if progress.claimed then colors.textFaint elseif done then colors.success else colors.primary,
			3
		)
		UI.text({
			Text = if def then Missions.format(def) else progress.id,
			FontFace = fonts.bodyBold,
			TextSize = 17,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = if progress.claimed then colors.textFaint else colors.text,
			Position = UDim2.fromOffset(16, 8),
			Size = UDim2.new(1, -260, 0, 22),
			Parent = panel,
		})
		local track = UI.frame({
			BackgroundColor3 = colors.panelLight,
			Position = UDim2.fromOffset(16, 40),
			Size = UDim2.new(1, -420, 0, 8),
			Parent = panel,
		})
		UI.corner(4, track)
		local fill = UI.frame({
			BackgroundColor3 = if done then colors.success else colors.primary,
			Size = UDim2.fromScale(math.clamp(progress.progress / math.max(progress.target, 1), 0, 1), 1),
			Parent = track,
		})
		UI.corner(4, fill)
		UI.text({
			Text = ("%d / %d"):format(math.min(progress.progress, progress.target), progress.target),
			FontFace = fonts.mono,
			TextSize = 13,
			TextColor3 = colors.textDim,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.new(1, -396, 0, 34),
			Size = UDim2.fromOffset(90, 20),
			Parent = panel,
		})
		UI.text({
			Text = if def then ("+%d XP  ·  +%d ◈"):format(def.xp, def.flux) else "",
			FontFace = fonts.monoBold,
			TextSize = 14,
			TextColor3 = colors.gold,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -230, 0, 10),
			Size = UDim2.fromOffset(160, 20),
			Parent = panel,
		})
		if done and not progress.claimed then
			UI.actionButton("RÉCUPÉRER", "Primary", function()
				local response = Remote.call("MissionAction", { action = "Claim", id = progress.id })
				if response.ok then
					UI.playSound("UI.Reward")
				end
			end, {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -16, 0.5, 0),
				Size = UDim2.fromOffset(170, 40),
				Parent = panel,
			})
		elseif progress.claimed then
			UI.text({
				Text = "✓ RÉCUPÉRÉE",
				FontFace = fonts.heading,
				TextSize = 15,
				TextColor3 = colors.success,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -16, 0.5, 0),
				Size = UDim2.fromOffset(170, 40),
				Parent = panel,
			})
		elseif list == "Daily" and rerolls > 0 then
			local reroll = UI.actionButton("CHANGER", "Ghost", function()
				Remote.call("MissionAction", { action = "Reroll", index = index })
			end, {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -16, 0.5, 0),
				Size = UDim2.fromOffset(130, 36),
				Parent = panel,
			})
			reroll.TextSize = 14
		end
	end

	local function header(order: number, title: string, detail: string)
		local holder =
			UI.frame({ BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 32), LayoutOrder = order, Parent = body })
		UI.text({
			Text = title,
			FontFace = fonts.display,
			TextSize = 18,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.fromScale(0.6, 1),
			Parent = holder,
		})
		UI.text({
			Text = detail,
			FontFace = fonts.mono,
			TextSize = 13,
			TextColor3 = colors.textDim,
			TextXAlignment = Enum.TextXAlignment.Right,
			Position = UDim2.fromScale(0.6, 0),
			Size = UDim2.fromScale(0.4, 1),
			Parent = holder,
		})
	end

	local function render()
		clear(body)
		local data = ClientState.profileData()
		if not data then
			return
		end
		local now = os.time()
		local dayLeft = 86400 - now % 86400
		local weekStart = (Missions.weekIndex(now) * 7 - 3) * 86400
		local weekLeft = weekStart + 7 * 86400 - now
		header(
			1,
			"QUOTIDIENNES",
			("renouvellement dans %dh%02d  ·  %d changement restant"):format(
				dayLeft // 3600,
				(dayLeft % 3600) // 60,
				data.Missions.Rerolls
			)
		)
		local order = 1
		for index, progress in data.Missions.Daily do
			order += 1
			row(order, progress, "Daily", index, data.Missions.Rerolls)
		end
		order += 1
		header(
			order,
			"HEBDOMADAIRES",
			("renouvellement dans %dj %dh"):format(weekLeft // 86400, (weekLeft % 86400) // 3600)
		)
		for index, progress in data.Missions.Weekly do
			order += 1
			row(order, progress, "Weekly", index, 0)
		end
	end
	onProfileChange(frame, render)
	return {
		frame = frame,
		refresh = render,
		focus = function(_option: string?)
			render()
		end,
	}
end

---------------------------------------------------------------------------------------------
-- Aether Pass
---------------------------------------------------------------------------------------------

local function rewardText(item: string?, flux: number?): string
	if item then
		local def = Cosmetics.get(item)
		return if def then def.displayName else item
	elseif flux then
		return ("%d ◈"):format(flux)
	end
	return "—"
end

function ProgressTabs.pass(parent: Instance): Tab
	local frame = UI.frame({ BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = parent })
	local title = UI.text({
		Text = Progression.PASS_NAME,
		FontFace = fonts.display,
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 30),
		Parent = frame,
	})
	UI.gradient(title, ColorSequence.new(colors.secondary, colors.primary), 0)
	local summary = UI.text({
		Text = "",
		FontFace = fonts.mono,
		TextSize = 15,
		TextColor3 = colors.textDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(0, 36),
		Size = UDim2.new(1, 0, 0, 20),
		Parent = frame,
	})
	local barTrack = UI.frame({
		BackgroundColor3 = colors.panelLight,
		Position = UDim2.fromOffset(0, 62),
		Size = UDim2.new(1, 0, 0, 6),
		Parent = frame,
	})
	local barFill = UI.frame({ BackgroundColor3 = colors.secondary, Size = UDim2.fromScale(0, 1), Parent = barTrack })
	local strip = Instance.new("ScrollingFrame")
	strip.BackgroundTransparency = 1
	strip.BorderSizePixel = 0
	strip.Position = UDim2.fromOffset(0, 84)
	strip.Size = UDim2.new(1, 0, 1, -84)
	strip.AutomaticCanvasSize = Enum.AutomaticSize.X
	strip.CanvasSize = UDim2.new()
	strip.ScrollingDirection = Enum.ScrollingDirection.X
	strip.ScrollBarThickness = 5
	strip.Parent = frame
	UI.list(strip, Enum.FillDirection.Horizontal, 8)

	local function trackCell(
		parentCard: Frame,
		y: number,
		label: string,
		text: string,
		claimed: boolean,
		claimable: boolean,
		locked: boolean,
		onClaim: () -> ()
	)
		local cell = UI.button({
			Text = "",
			Position = UDim2.fromOffset(6, y),
			Size = UDim2.new(1, -12, 0, 96),
			BackgroundColor3 = if claimable then colors.primaryDeep else colors.panelLight,
			BackgroundTransparency = if locked then 0.5 else 0,
			Parent = parentCard,
		})
		UI.corner(3, cell)
		UI.text({
			Text = label,
			FontFace = fonts.mono,
			TextSize = 11,
			TextColor3 = if label == "PREMIUM" then colors.secondary else colors.textDim,
			Position = UDim2.fromOffset(0, 6),
			Size = UDim2.new(1, 0, 0, 14),
			Parent = cell,
		})
		UI.text({
			Text = text,
			FontFace = fonts.bodyBold,
			TextSize = 14,
			TextWrapped = true,
			Position = UDim2.fromOffset(6, 22),
			Size = UDim2.new(1, -12, 0, 46),
			Parent = cell,
		})
		UI.text({
			Text = if claimed then "✓" elseif claimable then "RÉCUPÉRER" elseif locked then "🔒" else "",
			FontFace = fonts.heading,
			TextSize = 13,
			TextColor3 = if claimed then colors.success else colors.text,
			Position = UDim2.new(0, 0, 1, -24),
			Size = UDim2.new(1, 0, 0, 18),
			Parent = cell,
		})
		cell.Activated:Connect(function()
			if claimable then
				onClaim()
			end
		end)
	end

	local function render()
		clear(strip)
		local data = ClientState.profileData()
		if not data then
			return
		end
		local tier = Progression.passTier(data.Pass.XP)
		local within = data.Pass.XP % Progression.PASS_TIER_XP
		summary.Text = ("PALIER %d / %d  ·  %d / %d XP%s"):format(
			tier,
			Progression.PASS_TIERS,
			if tier >= Progression.PASS_TIERS then Progression.PASS_TIER_XP else within,
			Progression.PASS_TIER_XP,
			if data.Pass.Premium then "  ·  PREMIUM ACTIF" else "  ·  piste premium verrouillée"
		)
		barFill.Size =
			UDim2.fromScale(if tier >= Progression.PASS_TIERS then 1 else within / Progression.PASS_TIER_XP, 1)
		for index = 1, Progression.PASS_TIERS do
			local reward = Progression.passRewards[index]
			local reached = index <= tier
			local card = UI.frame({
				BackgroundColor3 = if index == tier + 1 then colors.panelLight else colors.panel,
				BackgroundTransparency = 0.1,
				Size = UDim2.fromOffset(150, 250),
				LayoutOrder = index,
				Parent = strip,
			})
			UI.corner(4, card)
			UI.stroke(card, if reached then colors.secondary else colors.stroke, if index == tier + 1 then 2 else 1, 0)
			UI.text({
				Text = tostring(index),
				FontFace = fonts.display,
				TextSize = 22,
				TextColor3 = if reached then colors.secondary else colors.textDim,
				Position = UDim2.fromOffset(0, 8),
				Size = UDim2.new(1, 0, 0, 26),
				Parent = card,
			})
			local freeKey = "free:" .. index
			local premiumKey = "premium:" .. index
			local hasFree = reward.free ~= nil or reward.freeFlux ~= nil
			local hasPremium = reward.premium ~= nil or reward.premiumFlux ~= nil
			if hasFree then
				local claimed = data.Pass.Claimed[freeKey] == true
				trackCell(
					card,
					40,
					"GRATUIT",
					rewardText(reward.free, reward.freeFlux),
					claimed,
					reached and not claimed,
					not reached,
					function()
						if Remote.call("ShopAction", { action = "ClaimPass", tier = index, track = "free" }).ok then
							UI.playSound("UI.Reward")
						end
					end
				)
			end
			if hasPremium then
				local claimed = data.Pass.Claimed[premiumKey] == true
				local available = reached and data.Pass.Premium and not claimed
				trackCell(
					card,
					144,
					"PREMIUM",
					rewardText(reward.premium, reward.premiumFlux),
					claimed,
					available,
					not (reached and data.Pass.Premium),
					function()
						if Remote.call("ShopAction", { action = "ClaimPass", tier = index, track = "premium" }).ok then
							UI.playSound("UI.Reward")
						end
					end
				)
			end
		end
		task.defer(function()
			strip.CanvasPosition = Vector2.new(math.max(0, (tier - 2) * 158), 0)
		end)
	end
	onProfileChange(frame, render)
	return {
		frame = frame,
		refresh = render,
		focus = function(_option: string?)
			render()
		end,
	}
end

---------------------------------------------------------------------------------------------
-- Classement
---------------------------------------------------------------------------------------------

function ProgressTabs.leaderboard(parent: Instance): Tab
	local frame = UI.frame({ BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = parent })
	local mine = UI.panel({ Size = UDim2.new(1, 0, 0, 76), Parent = frame })
	UI.accent(mine, colors.gold, 4)
	local mineText = UI.text({
		Text = "",
		FontFace = fonts.heading,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(20, 0),
		Size = UDim2.new(1, -40, 1, 0),
		Parent = mine,
	})
	local list = Instance.new("ScrollingFrame")
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(0, 90)
	list.Size = UDim2.new(1, 0, 1, -90)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ScrollBarThickness = 4
	list.Parent = frame
	UI.list(list, Enum.FillDirection.Vertical, 4)

	local function render()
		clear(list)
		local data = ClientState.profileData()
		if data then
			local placed = data.Rank.Placements >= Ranks.PLACEMENT_MATCHES
			local tier = Ranks.tierOf(data.Rank.RankIndex)
			mineText.Text = if placed
				then ('<font color="#%s">%s %s</font>   %d RR   ·   pic : %s   ·   %d V / %d D'):format(
					tier.color:ToHex(),
					tier.glyph,
					Ranks.displayName(data.Rank.RankIndex),
					data.Rank.RR,
					Ranks.displayName(data.Rank.Peak),
					data.Rank.Wins,
					data.Rank.Losses
				)
				else ("MATCHS DE PLACEMENT  %d / %d   ·   le classement apparaît après le placement"):format(
					data.Rank.Placements,
					Ranks.PLACEMENT_MATCHES
				)
		end
		local board = ReplicaController.get("Leaderboard")
		local entries = if board then board.data.entries else nil
		if type(entries) ~= "table" or #entries == 0 then
			local empty = UI.frame({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), Parent = list })
			UI.text({
				Text = "Classement indisponible (DataStores inactifs en Studio non publié, ou saison vide).",
				TextColor3 = colors.textDim,
				Size = UDim2.fromScale(1, 1),
				Parent = empty,
			})
			return
		end
		for order, entry in entries :: { any } do
			local tier = Ranks.tierOf(tonumber(entry.rankIndex) or 0)
			local isMe = tonumber(entry.userId) == Players.LocalPlayer.UserId
			local row = UI.frame({
				BackgroundColor3 = if isMe then colors.panelLight else colors.panel,
				BackgroundTransparency = 0.15,
				Size = UDim2.new(1, -8, 0, 34),
				LayoutOrder = order,
				Parent = list,
			})
			UI.text({
				Text = ("#%d"):format(tonumber(entry.rank) or order),
				FontFace = fonts.monoBold,
				TextSize = 16,
				TextColor3 = if order <= 3 then colors.gold else colors.textDim,
				Size = UDim2.fromOffset(70, 34),
				Parent = row,
			})
			UI.text({
				Text = tostring(entry.name),
				FontFace = fonts.bodyBold,
				TextSize = 16,
				TextXAlignment = Enum.TextXAlignment.Left,
				Position = UDim2.fromOffset(80, 0),
				Size = UDim2.new(0.5, -80, 1, 0),
				Parent = row,
			})
			UI.text({
				Text = ('<font color="#%s">%s %s</font>  ·  %d RR'):format(
					tier.color:ToHex(),
					tier.glyph,
					Ranks.displayName(tonumber(entry.rankIndex) or 0),
					tonumber(entry.rr) or 0
				),
				FontFace = fonts.mono,
				TextSize = 14,
				TextXAlignment = Enum.TextXAlignment.Right,
				Position = UDim2.fromScale(0.5, 0),
				Size = UDim2.new(0.5, -16, 1, 0),
				Parent = row,
			})
		end
	end
	ReplicaController.onNew("Leaderboard", function(replica: ReplicaController.ClientReplica)
		replica.Changed:Connect(function()
			if frame.Visible then
				task.defer(render)
			end
		end)
	end)
	onProfileChange(frame, render)
	return {
		frame = frame,
		refresh = render,
		focus = function(_option: string?)
			render()
		end,
	}
end

return ProgressTabs
