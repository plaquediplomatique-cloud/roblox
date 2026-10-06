--!strict
--[[
	EggTimers — minuteur flottant au-dessus de chaque œuf (tous les joueurs voient les œufs,
	mais seul le propriétaire peut éclore le sien).

	Le serveur n'envoie que des attributs (`StartedAt`, `ReadyAt`, `State`, `OwnerUserId`) ;
	l'affichage est calculé ici avec la même règle pure (Incubation) à partir du temps
	serveur. Le ProximityPrompt est masqué pour les non-propriétaires (le serveur revalide
	de toute façon).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Incubation = require(Shared.Rules.Incubation)
local Net = require(Shared.Net)
local Theme = require(Shared.Config.Theme)
local UIKit = require(script.Parent.UIKit)

type Tracked = {
	model: Model,
	timer: TextLabel,
	caption: TextLabel,
	fill: Frame,
	prompt: ProximityPrompt?,
}

local localPlayer = Players.LocalPlayer
local tracked: { [Model]: Tracked } = {}

local EggTimers = {}

local function build(model: Model, shell: BasePart): Tracked
	local gui = Instance.new("BillboardGui")
	gui.Name = "EggTimer"
	gui.Adornee = shell
	gui.Size = UDim2.fromOffset(190, 78)
	gui.StudsOffset = Vector3.new(0, 5.2, 0)
	gui.MaxDistance = 70
	gui.LightInfluence = 0
	gui.Parent = shell

	local card = UIKit.panel(gui)
	card.Size = UDim2.fromScale(1, 1)

	local caption = UIKit.label(card, "Hatching…", 18, Theme.colors.inkSoft)
	caption.Size = UDim2.new(1, 0, 0, 22)
	caption.Position = UDim2.fromOffset(0, 6)

	local timer = UIKit.label(card, "0:00", 32)
	timer.Size = UDim2.new(1, 0, 0, 34)
	timer.Position = UDim2.fromOffset(0, 26)

	local track = Instance.new("Frame")
	track.BackgroundColor3 = Theme.colors.inkSoft
	track.BackgroundTransparency = 0.7
	track.BorderSizePixel = 0
	track.Size = UDim2.new(1, -28, 0, 8)
	track.Position = UDim2.new(0, 14, 1, -16)
	track.Parent = card
	UIKit.corner(track, 4)
	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = Theme.colors.berry
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.Parent = track
	UIKit.corner(fill, 4)

	return {
		model = model,
		timer = timer,
		caption = caption,
		fill = fill,
		prompt = shell:FindFirstChildOfClass("ProximityPrompt"),
	}
end

local function track(model: Model)
	if tracked[model] then
		return
	end
	task.spawn(function()
		local shell = model:WaitForChild("Shell", 10)
		if shell and shell:IsA("BasePart") and model.Parent then
			shell:WaitForChild("ProximityPrompt", 5)
			tracked[model] = build(model, shell)
		end
	end)
end

function EggTimers.start()
	for _, model in CollectionService:GetTagged(Net.eggTag) do
		track(model :: Model)
	end
	CollectionService:GetInstanceAddedSignal(Net.eggTag):Connect(function(instance)
		track(instance :: Model)
	end)
	CollectionService:GetInstanceRemovedSignal(Net.eggTag):Connect(function(instance)
		tracked[instance :: Model] = nil
	end)

	RunService.Heartbeat:Connect(function()
		local now = workspace:GetServerTimeNow()
		for model, entry in tracked do
			if not model.Parent then
				tracked[model] = nil
				continue
			end
			local startedAt = model:GetAttribute("StartedAt")
			local readyAt = model:GetAttribute("ReadyAt")
			if type(startedAt) ~= "number" or type(readyAt) ~= "number" then
				continue
			end
			local mine = model:GetAttribute("OwnerUserId") == localPlayer.UserId
			local ready = model:GetAttribute("State") == "Ready" and Incubation.isReady(readyAt, now)

			entry.fill.Size = UDim2.fromScale(Incubation.progress(startedAt, readyAt, now), 1)
			if ready then
				entry.timer.Text = if mine then "READY!" else "Hatching soon"
				entry.caption.Text = if mine then "Hold to hatch" else ""
				entry.fill.BackgroundColor3 = Theme.colors.mint
			else
				entry.timer.Text = Incubation.formatClock(Incubation.remaining(readyAt, now))
				entry.caption.Text = if mine then "Your egg is warming…" else "Hatching…"
			end
			if entry.prompt then
				entry.prompt.Enabled = mine and ready
			end
		end
	end)
end

return EggTimers
