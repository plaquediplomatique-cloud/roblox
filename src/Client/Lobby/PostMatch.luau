--!strict
--[[
	PostMatch — écran de retour de match (au QG), alimenté par profile.LastMatch.

	Séquence chorégraphiée (≈ 4 s, passable) :
	  1. résultat + score (glitch), mode et carte ;
	  2. statistiques personnelles ;
	  3. détail de l'XP ligne par ligne (compteurs), puis jauge de niveau qui se remplit
	     (et "NIVEAU SUPÉRIEUR" si un palier est franchi) ;
	  4. classé : jauge RR de l'ancien vers le nouveau total, delta signé, promotion /
	     rétrogradation mise en scène.
	"CONTINUER" signale au serveur que le résumé est vu (ProfileQuery SeenLastMatch) :
	il ne réapparaîtra pas à la prochaine connexion.
]]

local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local GameModes = require(Shared.Config.GameModes)
local Maps = require(Shared.Config.Maps)
local Progression = require(Shared.Config.Progression)
local Ranks = require(Shared.Config.Ranks)
local Theme = require(Shared.Config.Theme)
local UI = require(script.Parent.Parent.UI.UI)
local ClientState = require(script.Parent.Parent.Core.ClientState)
local Remote = require(script.Parent.Remote)

local colors = Theme.colors
local fonts = Theme.fonts

local PostMatch = {}

local showing = false

--[[
	Panneau de verre biseauté (même grammaire que le HUD) avec un cadre intérieur : les
	listes et marges vivent dans `content`, pas sur le verre (qui porte liseré et filet).
]]
local function glassPanel(
	parent: Instance,
	props: { [string]: any },
	width: number,
	height: number,
	accent: Color3
): (Frame, Frame)
	local glass = UI.glass(width, height, 16, props)
	local root = glass.root
	root.ZIndex = 41
	for _, child in root:GetChildren() do
		if child:IsA("GuiObject") then
			child.ZIndex = 42
		end
	end
	local edge = root:FindFirstChild("Edge")
	if edge and edge:IsA("Frame") then
		edge.BackgroundColor3 = accent
	end
	local content = UI.frame({
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 41,
		Parent = root,
	})
	UI.padding(content, 30, 24, 18, 16)
	root.Parent = parent
	return root, content
end

local function countUp(label: TextLabel, from: number, to: number, duration: number, format: (number) -> string)
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local t = math.clamp((os.clock() - started) / duration, 0, 1)
		local eased = 1 - (1 - t) ^ 3
		label.Text = format(math.floor(from + (to - from) * eased + 0.5))
		if t >= 1 then
			connection:Disconnect()
		end
	end)
end

function PostMatch.isShowing(): boolean
	return showing
end

--[[ Affiche le résumé dans `parent` ; `onClosed` est appelé après "CONTINUER". ]]
function PostMatch.show(parent: Instance, summary: Types.PostMatchSummary, onClosed: () -> ())
	if showing then
		return
	end
	showing = true
	local overlay = UI.frame({
		BackgroundColor3 = colors.void,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 40,
		Parent = parent,
	})
	UI.tween(overlay, Theme.tween.medium, { BackgroundTransparency = 0.15 })
	local function text(props: { [string]: any }): TextLabel
		props.ZIndex = 41
		props.Parent = props.Parent or overlay
		return UI.text(props)
	end

	local victory = summary.result == "Victory"
	local resultColor = if summary.result == "Draw" then colors.textDim elseif victory then colors.gold else colors.enemy
	local mode = GameModes.get(summary.mode)
	local map = Maps.get(summary.map)
	local title = text({
		Text = if summary.result == "Draw" then "ÉGALITÉ" elseif victory then "VICTOIRE" else "DÉFAITE",
		FontFace = fonts.display,
		TextSize = 72,
		TextColor3 = resultColor,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.07),
		Size = UDim2.fromOffset(1000, 84),
	})
	UI.glitchText(title, 0.5)
	-- Filet lumineux à la couleur du résultat, fondu aux deux bouts.
	local rule = UI.frame({
		BackgroundColor3 = resultColor,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.07, 82),
		Size = UDim2.fromOffset(560, 2),
		ZIndex = 41,
		Parent = overlay,
	})
	UI.gradient(
		rule,
		ColorSequence.new(Color3.new(1, 1, 1)),
		0,
		NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
	)
	text({
		Text = ("%d — %d   ·   %s   ·   %s%s"):format(
			summary.scoreFor,
			summary.scoreAgainst,
			if mode then mode.displayName else summary.mode,
			if map then map.displayName else summary.map,
			if summary.ranked then "   ·   CLASSÉ" else ""
		),
		FontFace = fonts.heading,
		TextSize = 20,
		TextColor3 = colors.textDim,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.07, 92),
		Size = UDim2.fromOffset(1000, 26),
	})

	-- Statistiques (gauche)
	local _, stats = glassPanel(overlay, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(0.5, -12, 0.27, 0),
	}, 440, 300, resultColor)
	UI.list(stats, Enum.FillDirection.Vertical, 6)
	local lines = {
		{ "ÉLIMINATIONS / MORTS / ASSISTS", ("%d / %d / %d"):format(summary.kills, summary.deaths, summary.assists) },
		{ "DÉGÂTS", tostring(summary.damage) },
		{ "TIRS À LA TÊTE", tostring(summary.headshots) },
		{ "SCORE DE COMBAT", tostring(summary.score) },
		{ "MANCHES JOUÉES", tostring(summary.rounds) },
	}
	if summary.mvp then
		table.insert(lines, { "DISTINCTION", "★ MVP DU MATCH" })
	end
	for order, line in lines do
		local row = UI.frame({
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 36),
			LayoutOrder = order,
			ZIndex = 41,
			Parent = stats,
		})
		text({
			Text = line[1],
			FontFace = fonts.heading,
			TextSize = 13,
			TextColor3 = colors.textDim,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.fromScale(0.6, 1),
			Parent = row,
		})
		text({
			Text = line[2],
			FontFace = fonts.monoBold,
			TextSize = 18,
			TextColor3 = if line[1] == "DISTINCTION" then colors.gold else colors.text,
			TextXAlignment = Enum.TextXAlignment.Right,
			Position = UDim2.fromScale(0.6, 0),
			Size = UDim2.fromScale(0.4, 1),
			Parent = row,
		})
	end

	-- Progression (droite)
	local _, progress = glassPanel(overlay, {
		Position = UDim2.new(0.5, 12, 0.27, 0),
	}, 480, 316, colors.primary)
	local breakdown =
		UI.frame({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 150), ZIndex = 41, Parent = progress })
	UI.list(breakdown, Enum.FillDirection.Vertical, 2)
	local total = text({
		Text = "+0 XP",
		FontFace = fonts.display,
		TextSize = 26,
		TextColor3 = colors.primary,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(0, 158),
		Size = UDim2.new(1, 0, 0, 30),
		Parent = progress,
	})
	local levelLabel = text({
		Text = ("NIVEAU %d"):format(summary.levelBefore),
		FontFace = fonts.heading,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(0, 196),
		Size = UDim2.new(1, 0, 0, 20),
		Parent = progress,
	})
	local levelTrack = UI.frame({
		BackgroundColor3 = colors.panelLight,
		Position = UDim2.fromOffset(0, 220),
		Size = UDim2.new(1, 0, 0, 8),
		ZIndex = 41,
		Parent = progress,
	})
	-- Position de la jauge avant/après, reconstruite depuis le profil et l'XP gagnée.
	local profile = ClientState.profileData()
	local xpAfter = if profile then profile.XP else 0
	local afterFraction = xpAfter / Progression.xpForLevel(summary.levelAfter)
	local remaining = summary.xpGained - xpAfter
	for level = summary.levelBefore + 1, summary.levelAfter - 1 do
		remaining -= Progression.xpForLevel(level)
	end
	local beforeFraction = if summary.levelAfter == summary.levelBefore
		then math.max(0, xpAfter - summary.xpGained) / Progression.xpForLevel(summary.levelBefore)
		else math.clamp(1 - remaining / Progression.xpForLevel(summary.levelBefore), 0, 1)
	local levelFill = UI.frame({
		BackgroundColor3 = colors.primary,
		Size = UDim2.fromScale(math.clamp(beforeFraction, 0, 1), 1),
		ZIndex = 42,
		Parent = levelTrack,
	})
	local rankLabel = text({
		Text = "",
		FontFace = fonts.heading,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(0, 240),
		Size = UDim2.new(1, 0, 0, 22),
		Parent = progress,
	})
	local rrTrack = UI.frame({
		BackgroundColor3 = colors.panelLight,
		Position = UDim2.fromOffset(0, 266),
		Size = UDim2.new(1, 0, 0, 6),
		Visible = summary.ranked,
		ZIndex = 41,
		Parent = progress,
	})
	local rrFill = UI.frame({
		BackgroundColor3 = colors.warning,
		Size = UDim2.fromScale(math.clamp(summary.rrBefore / 100, 0, 1), 1),
		ZIndex = 42,
		Parent = rrTrack,
	})

	task.spawn(function()
		task.wait(0.6)
		local running = 0
		for order, entry in summary.xpBreakdown do
			if not overlay.Parent then
				return
			end
			local row = UI.frame({
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 22),
				LayoutOrder = order,
				ZIndex = 41,
				Parent = breakdown,
			})
			text({
				Text = string.upper(entry.label),
				FontFace = fonts.body,
				TextSize = 15,
				TextColor3 = colors.textDim,
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.fromScale(0.7, 1),
				Parent = row,
			})
			local amount = text({
				Text = "+0",
				FontFace = fonts.monoBold,
				TextSize = 15,
				TextXAlignment = Enum.TextXAlignment.Right,
				Position = UDim2.fromScale(0.7, 0),
				Size = UDim2.fromScale(0.3, 1),
				Parent = row,
			})
			countUp(amount, 0, entry.amount, 0.35, function(value: number): string
				return "+" .. value
			end)
			countUp(total, running, running + entry.amount, 0.35, function(value: number): string
				return ("+%d XP"):format(value)
			end)
			running += entry.amount
			UI.playSound("UI.Tick")
			task.wait(0.3)
		end
		-- Jauge de niveau (plusieurs tours si plusieurs niveaux gagnés).
		local level = summary.levelBefore
		while level < summary.levelAfter and overlay.Parent do
			UI.tween(levelFill, TweenInfo.new(0.35), { Size = UDim2.fromScale(1, 1) })
			task.wait(0.4)
			level += 1
			levelLabel.Text = ("NIVEAU %d  ·  NIVEAU SUPÉRIEUR !"):format(level)
			levelLabel.TextColor3 = colors.gold
			UI.playSound("UI.LevelUp")
			levelFill.Size = UDim2.fromScale(0, 1)
		end
		UI.tween(levelFill, TweenInfo.new(0.5), { Size = UDim2.fromScale(math.clamp(afterFraction, 0, 1), 1) })
		if summary.ranked then
			local before = Ranks.tierOf(summary.rankBefore)
			local after = Ranks.tierOf(summary.rankAfter)
			local delta = summary.rrDelta
			rankLabel.Text = ('<font color="#%s">%s %s</font>   %s%d RR'):format(
				after.color:ToHex(),
				after.glyph,
				Ranks.displayName(summary.rankAfter),
				if delta >= 0 then "+" else "",
				delta
			)
			UI.tween(
				rrFill,
				TweenInfo.new(0.8, Enum.EasingStyle.Quint),
				{ Size = UDim2.fromScale(math.clamp(summary.rrAfter / 100, 0, 1), 1) }
			)
			if summary.rankAfter > summary.rankBefore then
				UI.playSound("UI.RankUp")
				rankLabel.Text ..= "   ·   PROMOTION"
			elseif summary.rankAfter < summary.rankBefore then
				rankLabel.Text ..= "   ·   " .. before.name .. " → " .. after.name
			end
		else
			rankLabel.Text = "Partie non classée : aucun RR en jeu."
			rankLabel.TextColor3 = colors.textDim
		end
	end)

	UI.actionButton("CONTINUER", "Primary", function()
		Remote.call("ProfileQuery", { action = "SeenLastMatch" })
		showing = false
		UI.tween(overlay, Theme.tween.medium, { BackgroundTransparency = 1 })
		overlay:Destroy()
		onClosed()
	end, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.27, 330),
		ZIndex = 42,
		Parent = overlay,
	})
	levelLabel.Text ..= ("  ·  %d / %d XP"):format(xpAfter, Progression.xpForLevel(summary.levelAfter))
end

return PostMatch
