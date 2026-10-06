--[[ Tests : recettes d'armes (budgets, bornes), pose de frappe procédurale. ]]

local WeaponRecipes = req(Shared.Assets.WeaponRecipes)
local WeaponCatalog = req(Shared.Rules.WeaponCatalog)
local Archetypes = req(Shared.Config.Archetypes)
local Spec = req(Shared.Assets.Spec)
local SwingPose = req(Shared.Rules.SwingPose)

local MAX_PARTS = 22

T.describe("WeaponRecipes", function()
	T.it("chaque archétype du catalogue a une recette (et inversement)", function()
		for name in Archetypes do
			T.expect(WeaponRecipes.Builders[name] ~= nil, "recette manquante: " .. name)
		end
		for name in WeaponRecipes.Builders do
			T.expect(Archetypes[name] ~= nil, "archétype inconnu: " .. name)
		end
	end)
	T.it("chaque arme se construit : un seul Handle, budget de pièces, tailles valides", function()
		for _, weapon in WeaponCatalog.List do
			local recipe = WeaponRecipes.build(weapon.Archetype, weapon.Colors)
			local handles = 0
			T.expect(#recipe.Parts <= MAX_PARTS, ("%s: %d pièces"):format(weapon.Id, #recipe.Parts))
			for _, part in recipe.Parts do
				if part.Name == "Handle" then
					handles += 1
				end
				T.expect(part.Size.X > 0 and part.Size.Y > 0 and part.Size.Z > 0, weapon.Id .. " taille")
				T.expect(part.Size.Magnitude < 20, weapon.Id .. " démesurée")
			end
			T.eq(handles, 1, weapon.Id .. " Handle")
		end
	end)
	T.it("le bout de l'arme est près du sommet réel du modèle", function()
		for name in WeaponRecipes.Builders do
			local recipe =
				WeaponRecipes.build(name, { Color3.new(1, 1, 1), Color3.new(0.5, 0.3, 0.1), Color3.new(1, 0.8, 0) })
			local _, max = Spec.bounds(recipe.Parts)
			T.expect(
				math.abs(max.Y - recipe.Tip.Y) < 1.3,
				("%s: tip %.2f vs max %.2f"):format(name, recipe.Tip.Y, max.Y)
			)
			T.expect(recipe.TrailBase.Y < recipe.TrailTop.Y or name == "DoubleBlade", name .. " traînée")
		end
	end)
	T.it("longueur plausible pour un personnage (3 à 11 studs)", function()
		for name in WeaponRecipes.Builders do
			local recipe = WeaponRecipes.build(name, { Color3.new(1, 1, 1), Color3.new(1, 1, 1), Color3.new(1, 1, 1) })
			local min, max = Spec.bounds(recipe.Parts)
			local extent = max.Y - min.Y
			T.expect(extent >= 3 and extent <= 11, ("%s: %.1f"):format(name, extent))
		end
	end)
	T.it("les armes plus puissantes sont (en moyenne) plus longues dans la voie principale", function()
		local function length(weapon)
			return WeaponRecipes.build(weapon.Archetype, weapon.Colors).Length
		end
		local early, late = 0, 0
		for i = 1, 10 do
			early += length(WeaponCatalog.Main[i])
			late += length(WeaponCatalog.Main[50 + i])
		end
		T.expect(late >= early * 0.9)
	end)
end)

T.describe("SwingPose", function()
	T.it("pose prête : la lame pointe vers l'avant et à ~45° vers le haut", function()
		local direction = SwingPose.bladeDirection(SwingPose.ready())
		T.near(direction.Y, 0.7071, 0.01, "haut")
		T.near(direction.Z, -0.7071, 0.01, "avant (-Z)")
		T.near(direction.X, 0, 0.01)
	end)
	T.it("chaque style commence et finit sur la pose prête", function()
		for style in SwingPose.Styles do
			local a = SwingPose.sample(style, 0)
			local b = SwingPose.sample(style, 1)
			T.near(a.Shoulder, SwingPose.ReadyShoulder, 1e-6, style)
			T.near(b.Shoulder, SwingPose.ReadyShoulder, 1e-6, style)
			T.near(a.Lunge, 0, 1e-6)
			T.near(b.Lunge, 0, 1e-6)
		end
	end)
	T.it("continuité : aucun saut brutal entre deux échantillons", function()
		for style in SwingPose.Styles do
			local previous = SwingPose.sample(style, 0)
			for i = 1, 200 do
				local pose = SwingPose.sample(style, i / 200)
				T.expect(math.abs(pose.Shoulder - previous.Shoulder) < math.rad(25), style .. " épaule")
				T.expect(math.abs(pose.Torso - previous.Torso) < math.rad(40), style .. " torse")
				previous = pose
			end
		end
	end)
	T.it("l'impact tombe au moment du coup le plus bas/avancé (frappe)", function()
		local overhead = SwingPose.sample("Overhead", SwingPose.ImpactTime)
		T.expect(overhead.Shoulder < math.rad(45), "le bras descend à l'impact")
		local stab = SwingPose.sample("Stab", SwingPose.ImpactTime)
		T.expect(stab.Lunge > 1, "la fente avance à l'impact")
	end)
	T.it("overhead : la lame passe au-dessus de la tête puis devant", function()
		local windup = SwingPose.bladeDirection(SwingPose.sample("Overhead", 0.2))
		local strike = SwingPose.bladeDirection(SwingPose.sample("Overhead", SwingPose.ImpactTime))
		T.expect(windup.Z > -0.2, "lame vers l'arrière/haut en armement")
		T.expect(strike.Z < -0.7 and strike.Y < 0, "lame vers l'avant/bas à l'impact")
	end)
	T.it("style inconnu => Overhead, t hors bornes borné", function()
		T.near(SwingPose.sample("???", 0.2).Shoulder, SwingPose.sample("Overhead", 0.2).Shoulder, 1e-9)
		T.near(SwingPose.sample("Slash", -3).Shoulder, SwingPose.ReadyShoulder, 1e-9)
		T.near(SwingPose.sample("Slash", 9).Shoulder, SwingPose.ReadyShoulder, 1e-9)
	end)
	T.it("chaque archétype utilise un style défini", function()
		for name, archetype in Archetypes do
			T.expect(SwingPose.Styles[archetype.Swing] ~= nil, name .. " -> " .. archetype.Swing)
		end
	end)
end)

local Props = req(Shared.Assets.Props)
local Decor = req(Shared.Config.Decor)
local Zones = req(Shared.Config.Zones)

T.describe("Props (bibliothèque modulaire)", function()
	T.it("au moins 40 recettes", function()
		T.expect(#Props.names() >= 40, tostring(#Props.names()))
	end)
	T.it("budget de pièces et tailles valides pour chaque prop et chaque palette de zone", function()
		local palettes = { Props.DefaultPalette }
		for _, zone in Zones.List do
			table.insert(palettes, Props.zonePalette(zone.Palette))
		end
		for _, name in Props.names() do
			for _, palette in palettes do
				local specs = Props.build(name, palette, 3)
				T.expect(#specs >= 2 and #specs <= 40, ("%s: %d pièces"):format(name, #specs))
				for _, spec in specs do
					T.expect(spec.Size.X > 0 and spec.Size.Y > 0 and spec.Size.Z > 0, name .. " taille nulle")
				end
			end
		end
	end)
	T.it("pivot au sol : rien ne s'enfonce profondément sous l'origine (hors îles et nuages)", function()
		for _, name in Props.names() do
			if name ~= "Island" and name ~= "Cloud" then
				local min = Spec.bounds(Props.build(name, Props.DefaultPalette, 1))
				T.expect(min.Y > -1.5, ("%s: min.Y = %.2f"):format(name, min.Y))
			end
		end
	end)
	T.it("toutes les recettes du catalogue de décor existent, prix croissants avec le niveau", function()
		for _, item in Decor.List do
			T.expect(Props.Recipes[item.Recipe] ~= nil, item.Id .. " -> " .. item.Recipe)
		end
		T.eq(Decor.ById.PlantPot.Cost, 0)
	end)
	T.it("recettes déterministes (même graine, même résultat)", function()
		local a = Props.build("Rock", Props.DefaultPalette, 7)
		local b = Props.build("Rock", Props.DefaultPalette, 7)
		T.eq(#a, #b)
		T.eq(a[1].CFrame, b[1].CFrame)
		local c = Props.build("Rock", Props.DefaultPalette, 8)
		T.expect(a[1].CFrame ~= c[1].CFrame)
	end)
	T.it("la collision est réservée aux grosses pièces", function()
		for _, name in Props.names() do
			for _, spec in Props.build(name, Props.DefaultPalette, 1) do
				if spec.Collide then
					T.expect(math.max(spec.Size.X, spec.Size.Y, spec.Size.Z) >= 1.5, name .. "/" .. tostring(spec.Name))
				end
			end
		end
	end)
	T.it("gabarits des meubles : assise ~1.5 stud, table ~2.5", function()
		local _, chairMax = Spec.bounds(Props.build("Chair", Props.DefaultPalette, 1))
		T.expect(chairMax.Y > 3 and chairMax.Y < 4.2)
		local _, tableMax = Spec.bounds(Props.build("Table", Props.DefaultPalette, 1))
		T.expect(tableMax.Y > 2.3 and tableMax.Y < 3)
	end)
end)
