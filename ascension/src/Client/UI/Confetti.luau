--!strict
--[[
	Confetti — éclats de papier d'interface pour les grands moments (niveau, arme, coffre).
	Frames créées à la demande puis détruites ; limitées (24 par rafale) et animées par tween.
]]

local UI = require(script.Parent.UI)

local Confetti = {}

local rng = Random.new()

function Confetti.burst(gui: Instance, origin: UDim2, colors: { Color3 }, count: number?)
	local total = math.min(count or 24, 30)
	for _ = 1, total do
		local size = rng:NextInteger(8, 16)
		local piece = UI.new("Frame", {
			BackgroundColor3 = colors[rng:NextInteger(1, #colors)],
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = origin,
			Size = UDim2.fromOffset(size, math.max(4, size // 2)),
			Rotation = rng:NextInteger(0, 360),
			ZIndex = 60,
			Parent = gui,
		})
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = rng:NextNumber(120, 340)
		local target = origin + UDim2.fromOffset(math.cos(angle) * distance, math.sin(angle) * distance * 0.7 + 120)
		UI.tween(
			piece,
			{ Position = target, Rotation = piece.Rotation + rng:NextInteger(-420, 420) },
			1.1,
			Enum.EasingStyle.Quad
		)
		task.delay(0.65, function()
			UI.tween(piece, { BackgroundTransparency = 1 }, 0.45)
		end)
		task.delay(1.15, function()
			piece:Destroy()
		end)
	end
end

return Confetti
