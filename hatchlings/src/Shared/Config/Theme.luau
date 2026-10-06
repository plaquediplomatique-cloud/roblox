--!strict
--[[
	Theme — direction artistique « Mochi Meadow » : île flottante pastel, heure dorée,
	formes rondes et douces, contours sombres violets plutôt que noirs.
]]

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

return {
	colors = {
		ink = rgb(72, 60, 108), -- texte et contours (violet profond, jamais noir pur)
		inkSoft = rgb(130, 118, 164),
		cream = rgb(255, 247, 232),
		white = rgb(255, 255, 255),
		panel = rgb(255, 250, 240),
		berry = rgb(255, 140, 180),
		mint = rgb(150, 220, 170),
		sky = rgb(150, 205, 255),
		sun = rgb(255, 214, 120),
	},
	font = Font.new("rbxasset://fonts/families/FredokaOne.json"),
	slotPastels = {
		rgb(255, 183, 213),
		rgb(190, 225, 255),
		rgb(255, 226, 150),
		rgb(190, 240, 200),
		rgb(214, 190, 255),
		rgb(255, 205, 170),
	},
}
