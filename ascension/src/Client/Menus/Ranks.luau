--!strict
--[[
	Menu Classements — top 10 par catégorie (cache serveur, rafraîchi toutes les 2 minutes).
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Net = require(Shared.Net.Net)
local Theme = require(Shared.Config.Theme)
local Leaderboards = require(Shared.Rules.Leaderboards)
local NumberFormat = require(Shared.Rules.NumberFormat)
local UI = require(script.Parent.Parent.UI.UI)
local Menu = require(script.Parent.Parent.UI.Menu)

local C = Theme.Color

local metric = "Power"

local Module: Menu.MenuModule = {
	Title = "Leaderboards",
	Keys = {},
	build = function(content: Frame, ctx: Menu.Context)
		local tabs = {}
		for _, entry in Leaderboards.Metrics do
			table.insert(tabs, { Id = entry.Id, Text = entry.Name })
		end
		local bar = Menu.tabs(content, tabs, metric, function(id)
			metric = id
			ctx.Rebuild()
		end)
		for _, child in bar:GetChildren() do
			if child:IsA("TextButton") then
				child.Size = UDim2.fromOffset(112, 38)
				child.TextSize = 14
			end
		end
		local holder = UI.new("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, 50),
			Size = UDim2.new(1, 0, 1, -50),
			Parent = content,
		})
		local column = Menu.column(holder, 6)
		local loading =
			UI.label({ Text = "Loading…", TextColor3 = C.TextDim, Size = UDim2.new(1, 0, 0, 30), Parent = column })
		task.spawn(function()
			local ok, response = pcall(function()
				return Net.func("GetLeaderboard"):InvokeServer({ metric = metric })
			end)
			if not content.Parent then
				return
			end
			loading:Destroy()
			local rows = if ok and type(response) == "table" and response.ok then response.data else nil
			if type(rows) ~= "table" or #rows == 0 then
				UI.label({
					Text = "No scores yet — be the first!",
					TextColor3 = C.TextDim,
					Size = UDim2.new(1, 0, 0, 30),
					Parent = column,
				})
				return
			end
			for i, entry in rows do
				local row = Menu.row(column, i, 46)
				UI.label({
					Text = tostring(i),
					Font = Theme.Font.Display,
					TextSize = 24,
					TextColor3 = if i == 1 then C.Level elseif i <= 3 then C.Text else C.TextDim,
					Position = UDim2.fromOffset(14, 0),
					Size = UDim2.fromOffset(40, 46),
					Parent = row,
				})
				UI.label({
					Text = entry.n,
					TextSize = 20,
					Position = UDim2.fromOffset(64, 0),
					Size = UDim2.new(1, -240, 1, 0),
					Parent = row,
				})
				UI.label({
					Text = NumberFormat.compact(entry.v),
					Font = Theme.Font.Display,
					TextSize = 22,
					TextColor3 = C.Xp,
					TextXAlignment = Enum.TextXAlignment.Right,
					Position = UDim2.new(1, -170, 0, 0),
					Size = UDim2.fromOffset(156, 46),
					Parent = row,
				})
			end
		end)
	end,
}

return Module
