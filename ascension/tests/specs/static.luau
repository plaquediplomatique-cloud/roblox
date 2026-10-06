--[[
	Contrôles STATIQUES sur le code source (ce qu'on ne peut pas vérifier sans lancer Studio) :
	clés de sons utilisées, remotes déclarés, aucune couleur / SoundId en dur, aucun `while true` nu.
]]

local fs = req("@lune/fs")
local Sounds = req(Shared.Config.Sounds)
local Net = req(Shared.Net.Net)
local Schemas = req(Shared.Net.Schemas)
local Archetypes = req(Shared.Config.Archetypes)

local function walk(dir, out)
	for _, entry in fs.readDir(dir) do
		local path = dir .. "/" .. entry
		if fs.isDir(path) then
			walk(path, out)
		elseif string.sub(entry, -5) == ".luau" then
			table.insert(out, path)
		end
	end
	return out
end

local files = walk("ascension/src", {})
local function sources(prefix)
	local list = {}
	for _, path in files do
		if string.sub(path, 1, #prefix) == prefix then
			table.insert(list, { path = path, text = fs.readFile(path) })
		end
	end
	return list
end

T.describe("Contrôles statiques", function()
	T.it('toute clé Sfx.play("X") existe dans Config/Sounds', function()
		for _, file in sources("ascension/src/Client") do
			for key in string.gmatch(file.text, 'Sfx%.play%("([%w_]+)"') do
				if key ~= "Swing_" then
					T.expect(Sounds[key] ~= nil, file.path .. ": clé inconnue " .. key)
				end
			end
		end
	end)
	T.it("les clés dynamiques (Swing_<classe>) existent pour chaque classe d'archétype", function()
		for name, archetype in Archetypes do
			T.expect(Sounds["Swing_" .. archetype.Sound] ~= nil, name)
		end
	end)
	T.it("chaque remote utilisé dans le code est déclaré dans Net", function()
		for _, file in files do
			local text = fs.readFile(file)
			for _, pattern in { 'Net%.event%("(%w+)"%)', 'Net%.unreliable%("(%w+)"%)', 'Net%.func%("(%w+)"%)' } do
				for name in string.gmatch(text, pattern) do
					T.expect(Net.Declaration[name] ~= nil, file .. ": remote non déclaré " .. name)
				end
			end
			for name in string.gmatch(text, 'ServerNet%.on%("(%w+)"') do
				T.expect(Schemas[name] ~= nil, file .. ": ServerNet.on sans schéma " .. name)
			end
		end
	end)
	T.it("chaque remote C2S déclaré a un handler serveur (aucun remote mort)", function()
		local serverText = ""
		for _, file in sources("ascension/src/Server") do
			serverText ..= file.text
		end
		for name in Schemas.Rates do
			local handled = string.find(serverText, 'ServerNet%.on%("' .. name .. '"')
				or string.find(serverText, 'ServerNet%.onInvoke%("' .. name .. '"')
			T.expect(handled ~= nil, "pas de handler pour " .. name)
		end
	end)
	T.it("aucun SoundId en dur hors Config/Sounds", function()
		for _, file in files do
			if not string.find(file, "Config/Sounds") then
				local text = fs.readFile(file)
				T.expect(not string.find(text, "rbxassetid://", 1, true), file .. " : SoundId en dur")
				T.expect(not string.find(text, 'SoundId%s*=%s*"'), file .. " : SoundId en dur")
			end
		end
	end)
	T.it("l'UI n'utilise pas de couleur en dur (hors Theme) : pas de Color3.fromRGB dans Client/Menus", function()
		for _, file in sources("ascension/src/Client/Menus") do
			T.expect(not string.find(file.text, "Color3%.fromRGB"), file.path)
		end
	end)
	T.it("aucun `while true do` sans task.wait dans le client", function()
		for _, file in sources("ascension/src/Client") do
			for body in string.gmatch(file.text, "while true do(.-)\nend") do
				T.expect(string.find(body, "task%.wait") ~= nil, file.path .. " : while true sans attente")
			end
		end
	end)
end)
