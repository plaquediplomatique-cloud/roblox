--[[
	Exports PropKit props as Roblox model files you can drag into Studio's Explorer.

	  lune run .claude/skills/roblox-props-modeling/scripts/export_props.luau [outDir]

	Writes <outDir>/PropKit_Showroom.rbxm (every prop in every style, laid out on a grid) and one
	<outDir>/<Kind>_<Style>.rbxm per prop. Default outDir: build/props (git-ignored).
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local LuneEnv = require("./lune_env")

local PropKit = LuneEnv.loadPropKit()
local outDir = process.args[1] or "build/props"
fs.writeDir(outDir)

local ORDER = { "DiningTable", "Chair", "Sofa", "Bed", "Bookshelf", "KitchenCounter", "FloorLamp", "Door" }
local STYLES = { "Oak", "Walnut", "Modern" }

local showroom = roblox.Instance.new("Model")
showroom.Name = "PropKit_Showroom"
local written = 0
for row, styleName in STYLES do
	local style = PropKit.styles[styleName]
	local x = 0
	for _, kind in ORDER do
		local model = PropKit.builders[kind]({ style = style, upper = true, sittable = true })
		model.Name = kind .. "_" .. styleName
		fs.writeFile(outDir .. "/" .. model.Name .. ".rbxm", roblox.serializeModel({ model }))
		written += 1
		local footprint = model:GetAttribute("Footprint")
		LuneEnv.translate(model, roblox.CFrame.new(x + footprint.X / 2, 0, (row - 1) * 14))
		model.Parent = showroom
		x += footprint.X + 4
	end
end
fs.writeFile(outDir .. "/PropKit_Showroom.rbxm", roblox.serializeModel({ showroom }))
print(("PropKit: %d props + showroom written to %s"):format(written, outDir))
