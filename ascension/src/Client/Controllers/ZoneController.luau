--!strict
--[[
	ZoneController — ambiance par royaume : éclairage, brouillard, étalonnage, bannière d'entrée.

	La zone du joueur se déduit de sa position (Rules/ZoneLayout, les mêmes fonctions que le
	serveur). Contrôle toutes les 0,5 s (pas par frame) ; la transition d'ambiance est un tween
	de 2 s, jamais un saut. Effets post-traitement sobres (skill roblox-lighting-art) : léger bloom,
	atmosphère, teinte — adaptés par zone depuis Config/Zones.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Signal = require(Shared.Util.Signal)
local Zones = require(Shared.Config.Zones)
local Theme = require(Shared.Config.Theme)
local ZoneLayout = require(Shared.Rules.ZoneLayout)
local UI = require(script.Parent.Parent.UI.UI)

local ZoneController = {}

ZoneController.Changed = Signal.new() :: Signal.Signal<number>
ZoneController.Current = 1

local atmosphere: Atmosphere
local correction: ColorCorrectionEffect
local bloom: BloomEffect
local banner: Frame
local bannerTitle: TextLabel
local bannerSub: TextLabel

local function applyLighting(zone: Zones.Zone, instant: boolean)
	local l = zone.Lighting
	local info = if instant then 0.01 else 2
	UI.tween(Lighting, {
		ClockTime = l.ClockTime,
		Brightness = l.Brightness,
		Ambient = l.Ambient,
		OutdoorAmbient = l.OutdoorAmbient,
		FogColor = l.FogColor,
		FogEnd = l.FogEnd,
		ColorShift_Top = l.Tint,
	}, info, Enum.EasingStyle.Sine)
	UI.tween(atmosphere, {
		Color = zone.Palette.Sky,
		Decay = l.FogColor,
		Density = if zone.Index == 8 or zone.Index == 10 then 0.42 else 0.3,
		Haze = if zone.Index == 7 or zone.Index == 8 then 2.2 else 1.2,
	}, info)
	UI.tween(correction, { TintColor = l.Tint:Lerp(Color3.new(1, 1, 1), 0.6) }, info)
	UI.tween(bloom, { Intensity = if zone.Index >= 7 then 0.9 else 0.35 }, info)
end

local function showBanner(zone: Zones.Zone)
	bannerTitle.Text = zone.Name:upper()
	bannerTitle.TextColor3 = zone.Palette.Glow
	bannerSub.Text = zone.Tagline
	banner.Visible = true
	banner.Position = UDim2.new(0.5, 0, 0, 90)
	UI.pop(banner, 0.85)
	bannerTitle.TextTransparency = 0
	bannerSub.TextTransparency = 0
	task.delay(2.6, function()
		UI.tween(bannerTitle, { TextTransparency = 1, TextStrokeTransparency = 1 }, 0.5)
		UI.tween(bannerSub, { TextTransparency = 1, TextStrokeTransparency = 1 }, 0.5)
	end)
end

function ZoneController.start()
	atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or UI.new("Atmosphere", { Parent = Lighting })
	correction = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
		or UI.new("ColorCorrectionEffect", { Contrast = 0.06, Saturation = 0.12, Parent = Lighting })
	bloom = Lighting:FindFirstChildOfClass("BloomEffect")
		or UI.new("BloomEffect", { Intensity = 0.35, Size = 22, Threshold = 1.1, Parent = Lighting })

	local gui = UI.screen("Zone", Players.LocalPlayer:WaitForChild("PlayerGui"), 3)
	banner = UI.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 90),
		Size = UDim2.fromOffset(640, 100),
		Visible = false,
		Parent = gui,
	})
	bannerTitle = UI.label({
		Font = Theme.Font.Display,
		TextSize = 54,
		TextStrokeTransparency = 0.1,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 62),
		Parent = banner,
	})
	bannerSub = UI.label({
		Font = Theme.Font.Body,
		TextSize = 20,
		TextStrokeTransparency = 0.3,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 62),
		Size = UDim2.new(1, 0, 0, 26),
		Parent = banner,
	})

	applyLighting(Zones.List[1], true)
	task.spawn(function()
		while gui.Parent do
			task.wait(0.5)
			local character = Players.LocalPlayer.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				local index = ZoneLayout.zoneAt(root.Position)
				if index and index ~= ZoneController.Current then
					ZoneController.Current = index
					applyLighting(Zones.List[index], false)
					showBanner(Zones.List[index])
					ZoneController.Changed:Fire(index)
				end
			end
		end
	end)
end

return ZoneController
