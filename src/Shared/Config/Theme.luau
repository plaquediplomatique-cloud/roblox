--!strict
--[[
	Theme — identité visuelle "Neo-military / Dark cyber".

	Palette froide et premium : noirs bleutés, cyan électrique comme couleur de marque,
	magenta pour le prestige, ambre pour les alertes, rouge pour l'ennemi.
	Typographie : Michroma (titres, très "aérospatial"), Sarpanch (UI militaire),
	TitilliumWeb (lisibilité), RobotoMono (chiffres : pas de "danse" des largeurs).
]]

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function weighted(font: Enum.Font, weight: Enum.FontWeight): Font
	return Font.new(Font.fromEnum(font).Family, weight)
end

local Theme = {
	colors = {
		void = rgb(5, 7, 10),
		background = rgb(8, 11, 16),
		panel = rgb(13, 17, 23),
		panelLight = rgb(19, 26, 34),
		stroke = rgb(36, 48, 62),
		strokeBright = rgb(70, 92, 116),
		text = rgb(230, 237, 243),
		textDim = rgb(125, 139, 153),
		textFaint = rgb(80, 92, 105),
		primary = rgb(61, 225, 255),
		primaryDeep = rgb(20, 120, 160),
		secondary = rgb(176, 77, 255),
		warning = rgb(255, 181, 71),
		danger = rgb(255, 70, 85),
		success = rgb(61, 255, 162),
		gold = rgb(255, 210, 74),
		ally = rgb(61, 225, 255),
		enemy = rgb(255, 70, 85),
		attack = rgb(255, 90, 54),
		defense = rgb(61, 200, 255),
		armor = rgb(110, 200, 255),
		health = rgb(235, 240, 245),
		healthLow = rgb(255, 70, 85),
	},
	fonts = {
		display = weighted(Enum.Font.Michroma, Enum.FontWeight.Regular),
		heading = weighted(Enum.Font.Sarpanch, Enum.FontWeight.Bold),
		headingHeavy = weighted(Enum.Font.Sarpanch, Enum.FontWeight.Heavy),
		body = weighted(Enum.Font.TitilliumWeb, Enum.FontWeight.Regular),
		bodyBold = weighted(Enum.Font.TitilliumWeb, Enum.FontWeight.Bold),
		mono = weighted(Enum.Font.RobotoMono, Enum.FontWeight.Medium),
		monoBold = weighted(Enum.Font.RobotoMono, Enum.FontWeight.Bold),
	},
	sideNames = {
		Attack = "ONYX",
		Defense = "HALO",
	},
	transparency = {
		panel = 0.18,
		panelSoft = 0.35,
		overlay = 0.4,
	},
	corner = UDim.new(0, 4),
	-- Seuils de retour joueur communs au HUD, à l'audio et à l'éclairage.
	feedback = {
		lowHealth = 0.35, -- fraction de PV sous laquelle tous les effets de bas PV démarrent
	},
	tween = {
		fast = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		medium = TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		slow = TweenInfo.new(0.6, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		bounce = TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	},
}

return Theme
