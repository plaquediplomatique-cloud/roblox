--!strict
--[[
	LeaderboardService — classements (Power, Level, Best Hit, Playtime, Best Combo, Weekly Kills).

	Les scores sont calculés par le SERVEUR depuis le profil (Rules/Leaderboards) : aucun remote
	n'accepte un score. Écritures étalées (un joueur à la fois, toutes les 90 s), lectures du
	top 10 mises en cache (120 s) et affichées sur les panneaux du village. En Studio sans
	accès API, le classement se rabat sur les joueurs présents.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Leaderboards = require(Shared.Rules.Leaderboards)
local Quests = require(Shared.Rules.Quests)
local NumberFormat = require(Shared.Rules.NumberFormat)
local Game = require(Shared.Config.Game)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local PlayerService = require(script.Parent.PlayerService)

local LeaderboardService = {}

export type Row = { Name: string, UserId: number, Value: number }

local WRITE_INTERVAL = 90
local READ_INTERVAL = 120
local TOP = 10

local cache: { [string]: { Row } } = {}
local names: { [number]: string } = {}
local boards: { [string]: { Labels: { TextLabel } } } = {}

local function storeFor(metric: Leaderboards.Metric): OrderedDataStore?
	local name = Game.LeaderboardPrefix .. metric.Id
	if metric.Weekly then
		name ..= "_" .. tostring(Quests.weekNumber(os.time()))
	end
	local ok, store = pcall(function()
		return DataStoreService:GetOrderedDataStore(name)
	end)
	return if ok then store else nil
end

local function nameOf(userId: number): string
	local cached = names[userId]
	if cached then
		return cached
	end
	local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	names[userId] = if ok then name else "Player"
	return names[userId]
end

local function localRows(metric: Leaderboards.Metric): { Row }
	local rows: { Row } = {}
	for player, state in PlayerService.all() do
		local fighter = PlayerService.fighter(state)
		local value = Leaderboards.clampScore(Leaderboards.value(metric.Id, state.Profile, fighter, state.WeeklyKills))
		table.insert(rows, { Name = player.DisplayName, UserId = player.UserId, Value = value })
	end
	table.sort(rows, function(a, b)
		return a.Value > b.Value
	end)
	return rows
end

local function render(metricId: string)
	local board = boards[metricId]
	if not board then
		return
	end
	local rows = cache[metricId] or {}
	for i, label in board.Labels do
		local row = rows[i]
		label.Text = if row
			then ("%d.  %s   %s"):format(i, row.Name, NumberFormat.compact(row.Value))
			else ("%d.  —"):format(i)
	end
end

local function writeScores()
	for _, player in Players:GetPlayers() do
		local state = PlayerService.get(player)
		if state then
			local fighter = PlayerService.fighter(state)
			for _, metric in Leaderboards.Metrics do
				local store = storeFor(metric)
				if store then
					local value = Leaderboards.clampScore(
						Leaderboards.value(metric.Id, state.Profile, fighter, state.WeeklyKills)
					)
					pcall(function()
						store:SetAsync(tostring(player.UserId), value)
					end)
				end
			end
			task.wait(1)
		end
	end
end

local function readTop()
	for _, metric in Leaderboards.Metrics do
		local rows: { Row } = {}
		local store = storeFor(metric)
		local ok = false
		if store then
			ok = pcall(function()
				local pages = (store :: OrderedDataStore):GetSortedAsync(false, TOP)
				for _, entry in pages:GetCurrentPage() do
					local userId = tonumber(entry.key) or 0
					table.insert(rows, { Name = nameOf(userId), UserId = userId, Value = entry.value :: number })
				end
			end)
		end
		if not ok or #rows == 0 then
			rows = localRows(metric)
		end
		cache[metric.Id] = rows
		render(metric.Id)
		task.wait(2)
	end
end

-- Panneau physique : 10 lignes de texte sur un SurfaceGui.
function LeaderboardService.buildBoard(metricId: string, title: string, cframe: CFrame, parent: Instance)
	local board = Instance.new("Part")
	board.Name = "Board_" .. metricId
	board.Anchored = true
	board.Size = Vector3.new(18, 12, 0.8)
	board.Color = Color3.fromRGB(28, 30, 48)
	board.Material = Enum.Material.SmoothPlastic
	board.CFrame = cframe * CFrame.new(0, 8, 0)
	board.Parent = parent
	for _, x in { -7, 7 } do
		local post = Instance.new("Part")
		post.Anchored = true
		post.Size = Vector3.new(0.8, 8, 0.8)
		post.Color = Color3.fromRGB(80, 84, 120)
		post.CFrame = cframe * CFrame.new(x, 4, 0)
		post.Parent = parent
	end
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(720, 480)
	gui.LightInfluence = 0
	gui.Parent = board
	local header = Instance.new("TextLabel")
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0.12, 0)
	header.Font = Enum.Font.FredokaOne
	header.TextScaled = true
	header.TextColor3 = Color3.fromRGB(255, 214, 90)
	header.Text = title
	header.Parent = gui
	local labels: { TextLabel } = {}
	for i = 1, TOP do
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Position = UDim2.new(0.06, 0, 0.13 + (i - 1) * 0.085, 0)
		label.Size = UDim2.new(0.88, 0, 0.08, 0)
		label.Font = Enum.Font.GothamMedium
		label.TextScaled = true
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextColor3 = if i <= 3 then Color3.fromRGB(255, 240, 170) else Color3.new(1, 1, 1)
		label.Text = ("%d.  —"):format(i)
		label.Parent = gui
		table.insert(labels, label)
	end
	boards[metricId] = { Labels = labels }
end

function LeaderboardService.start()
	ServerNet.onInvoke("GetLeaderboard", function(_player, payload)
		local rows = cache[payload.metric]
		if not rows then
			return {}
		end
		local out = {}
		for _, row in rows do
			table.insert(out, { n = row.Name, v = row.Value })
		end
		return out
	end)

	task.spawn(function()
		task.wait(10)
		while true do
			readTop()
			task.wait(READ_INTERVAL)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(WRITE_INTERVAL)
			writeScores()
		end
	end)
end

return LeaderboardService
