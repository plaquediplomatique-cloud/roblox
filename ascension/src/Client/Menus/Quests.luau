--!strict
--[[
	Menu Quêtes — rétention : récompense quotidienne (série de 7 jours), quêtes du jour et de la
	semaine, succès à paliers. Tout est calculé côté serveur ; ici on affiche et on demande « claim ».
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Net = require(Shared.Net.Net)
local Theme = require(Shared.Config.Theme)
local DailyConfig = require(Shared.Config.Daily)
local QuestConfig = require(Shared.Config.Quests)
local AchievementConfig = require(Shared.Config.Achievements)
local Daily = require(Shared.Rules.Daily)
local Achievements = require(Shared.Rules.Achievements)
local NumberFormat = require(Shared.Rules.NumberFormat)
local Store = require(script.Parent.Parent.Core.Store)
local UI = require(script.Parent.Parent.UI.UI)
local Menu = require(script.Parent.Parent.UI.Menu)

local C = Theme.Color

local tab = "Daily"

local function rewardText(reward: any): string
	local parts = {}
	if reward.Coins then
		table.insert(parts, ("%d min coins"):format(reward.Coins))
	end
	if reward.XP then
		table.insert(parts, ("%d min XP"):format(reward.XP))
	end
	if reward.Chest then
		table.insert(parts, reward.Chest .. " chest")
	end
	if reward.Weapon then
		table.insert(parts, "weapon")
	end
	return table.concat(parts, "  +  ")
end

local function progressRow(
	parent: Instance,
	order: number,
	title: string,
	subtitle: string,
	fraction: number,
	claimable: boolean,
	claimed: boolean,
	onClaim: () -> ()
)
	local row = Menu.row(parent, order, 72)
	UI.label({
		Text = title,
		TextSize = 19,
		Position = UDim2.fromOffset(14, 6),
		Size = UDim2.new(1, -200, 0, 24),
		Parent = row,
	})
	UI.label({
		Text = subtitle,
		TextSize = 13,
		Font = Theme.Font.Body,
		TextColor3 = C.TextDim,
		Position = UDim2.fromOffset(14, 30),
		Size = UDim2.new(1, -200, 0, 18),
		Parent = row,
	})
	local bar = UI.bar({
		Position = UDim2.fromOffset(14, 52),
		Size = UDim2.new(1, -210, 0, 10),
		Color = if claimed then C.Good else C.Xp,
		Parent = row,
	})
	bar:Set(fraction, false)
	local button = UI.button({
		Text = if claimed then "CLAIMED" else "CLAIM",
		Size = UDim2.fromOffset(150, 42),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Style = "good",
		Parent = row,
	}, onClaim)
	button:SetEnabled(claimable and not claimed)
end

local function buildDaily(column: Instance)
	local data = Store.Data
	local status = Daily.status(data.Daily or { Streak = 0, LastClaim = 0 }, workspace:GetServerTimeNow())
	local holder = Menu.row(column, 1, 130)
	for i, reward in DailyConfig.Days do
		local current = i == status.Day
		local done = (not status.CanClaim and i < status.Day) or (status.CanClaim and i < status.Day)
		local card = UI.new("Frame", {
			BackgroundColor3 = if current then C.Accent else C.Ink,
			BackgroundTransparency = if done then 0.6 else 0.1,
			Position = UDim2.new((i - 1) / 7, 3, 0, 8),
			Size = UDim2.new(1 / 7, -6, 1, -16),
			Parent = holder,
		})
		UI.corner(UDim.new(0, 10)).Parent = card
		UI.stroke(if current then C.Level else C.InkEdge, if current then 3 else 1.5, 0.1).Parent = card
		UI.label({
			Text = "DAY " .. i,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(0, 6),
			Size = UDim2.new(1, 0, 0, 16),
			Parent = card,
		})
		UI.label({
			Text = reward.Label,
			TextSize = 11,
			Font = Theme.Font.Body,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(4, 26),
			Size = UDim2.new(1, -8, 1, -32),
			TextYAlignment = Enum.TextYAlignment.Top,
			Parent = card,
		})
	end
	local text = if status.CanClaim
		then "Your daily reward is ready!"
		else ("Next reward in %s"):format(NumberFormat.duration(status.NextIn))
	local _, button = Menu.action(
		column,
		2,
		("Streak: %d day(s)"):format(status.Streak),
		text,
		"CLAIM",
		"good",
		function()
			Net.event("ClaimDaily"):FireServer({})
		end
	)
	button:SetEnabled(status.CanClaim)
end

local function buildQuests(column: Instance)
	local data = Store.Data
	local items = (data.Quests and data.Quests.Items) or {}
	local order = 0
	for _, weekly in { false, true } do
		order += 1
		Menu.section(column, if weekly then "Weekly" else "Today", order)
		for _, item in items do
			local def = QuestConfig.ById[item.Id]
			if def and (def.Weekly == true) == weekly then
				order += 1
				progressRow(
					column,
					order,
					(string.gsub(def.Text, "{n}", UI.format(def.Target))),
					("%s / %s  ·  %s"):format(UI.format(item.Progress), UI.format(def.Target), rewardText(def.Reward)),
					item.Progress / def.Target,
					item.Progress >= def.Target,
					item.Claimed,
					function()
						Net.event("ClaimQuest"):FireServer({ id = def.Id })
					end
				)
			end
		end
	end
end

local function buildAchievements(column: Instance)
	local data = Store.Data
	local order = 0
	for _, achievement in AchievementConfig.List do
		order += 1
		local state: number = (data.Achievements and data.Achievements[achievement.Id]) or 0
		local value = Achievements.metricValue(data, achievement.Metric)
		progressRow(
			column,
			order,
			achievement.Name,
			("%s / %s  ·  %s"):format(
				UI.format(math.min(value, achievement.Target)),
				UI.format(achievement.Target),
				rewardText(achievement.Reward)
			),
			math.min(1, value / achievement.Target),
			state == 1,
			state == 2,
			function()
				Net.event("ClaimAchievement"):FireServer({ id = achievement.Id })
			end
		)
	end
end

local Module: Menu.MenuModule = {
	Title = "Rewards & Quests",
	Keys = { "Daily", "Quests", "Achievements", "Stats", "Weapons", "Level" },
	build = function(content: Frame, ctx: Menu.Context)
		Menu.tabs(
			content,
			{
				{ Id = "Daily", Text = "Daily Reward" },
				{ Id = "Quests", Text = "Quests" },
				{ Id = "Achievements", Text = "Achievements" },
			},
			tab,
			function(id)
				tab = id
				ctx.Rebuild()
			end
		)
		local holder = UI.new("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, 50),
			Size = UDim2.new(1, 0, 1, -50),
			Parent = content,
		})
		local column = Menu.column(holder)
		if tab == "Daily" then
			buildDaily(column)
		elseif tab == "Quests" then
			buildQuests(column)
		else
			buildAchievements(column)
		end
	end,
}

return Module
