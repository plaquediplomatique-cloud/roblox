--!strict
--[[
	Theme — jetons de design (jouet / brique, premium). L'UI ne contient JAMAIS de couleur
	ni de taille de police en dur : tout vient d'ici (cf. skill roblox-ui-design-system).
]]

local Theme = {
	Color = {
		Ink = Color3.fromRGB(28, 30, 48), -- fond des panneaux
		InkSoft = Color3.fromRGB(44, 48, 74),
		InkEdge = Color3.fromRGB(78, 84, 128),
		Text = Color3.fromRGB(255, 255, 255),
		TextDim = Color3.fromRGB(184, 192, 224),
		Xp = Color3.fromRGB(88, 214, 255),
		Level = Color3.fromRGB(255, 205, 70),
		Power = Color3.fromRGB(255, 110, 90),
		Coins = Color3.fromRGB(255, 214, 64),
		Combo = Color3.fromRGB(255, 150, 60),
		Good = Color3.fromRGB(96, 224, 128),
		Bad = Color3.fromRGB(255, 92, 100),
		Crit = Color3.fromRGB(255, 226, 90),
		Mega = Color3.fromRGB(255, 90, 200),
		Accent = Color3.fromRGB(120, 112, 255),
	},
	Font = {
		Display = Enum.Font.FredokaOne,
		Body = Enum.Font.GothamMedium,
		Bold = Enum.Font.GothamBold,
	},
	Size = {
		Tiny = 12,
		Small = 14,
		Body = 18,
		Large = 24,
		Huge = 40,
		Giant = 64,
	},
	Radius = UDim.new(0, 12),
	RadiusLarge = UDim.new(0, 18),
	Pad = 10,
	Tween = {
		Fast = 0.12,
		Normal = 0.22,
		Slow = 0.45,
	},
	-- Couleurs du combo selon le palier atteint (10, 25, 50, 100).
	ComboTiers = {
		{ At = 0, Color = Color3.fromRGB(255, 255, 255) },
		{ At = 10, Color = Color3.fromRGB(120, 230, 255) },
		{ At = 25, Color = Color3.fromRGB(255, 214, 64) },
		{ At = 50, Color = Color3.fromRGB(255, 130, 60) },
		{ At = 100, Color = Color3.fromRGB(255, 80, 200) },
	},
}

return Theme
