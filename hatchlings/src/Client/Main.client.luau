--!strict
--[[ Hatchlings — point d'entrée client : UI (collection, révélation) et minuteurs d'œuf. ]]

local Players = game:GetService("Players")

local Collection = require(script.Parent.Collection)
local EggTimers = require(script.Parent.EggTimers)
local Reveal = require(script.Parent.Reveal)

local gui = Instance.new("ScreenGui")
gui.Name = "Hatchlings"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 5
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

Collection.start(gui)
Reveal.start(gui)
EggTimers.start()
