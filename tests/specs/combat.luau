--[[ Tests : hitboxes, postures, spread déterministe, balistique (et tableau de TTK). ]]

local Hitbox = req(Shared.Combat.Hitbox)
local Stances = req(Shared.Combat.Stances)
local Spread = req(Shared.Combat.Spread)
local SpreadAudit = req(Shared.Combat.SpreadAudit)
local Ballistics = req(Shared.Combat.Ballistics)
local Weapons = req(Shared.Config.Weapons)
local MathUtil = req(Shared.Util.MathUtil)

local STAND_ROOT = CFrame.new(0, 3, 0)
local CROUCH_ROOT = CFrame.new(0, 1.6, 0)

local function shootAt(target, root, stance, lean)
	local origin = Vector3.new(target.X, target.Y, -40)
	local direction = (target - origin).Unit
	return Hitbox.raycast(origin, direction, 200, root, stance, lean or 0, 0)
end

T.describe("Hitbox", function()
	T.it("un tir à hauteur de tête touche la tête", function()
		local hit = shootAt(Vector3.new(0, 4.65, 0), STAND_ROOT, "Stand")
		T.expect(hit ~= nil, "doit toucher")
		T.eq(hit.zone, "Head")
	end)
	T.it("un tir au torse touche le corps", function()
		local hit = shootAt(Vector3.new(0, 3.6, 0), STAND_ROOT, "Stand")
		T.eq(hit and hit.zone, "Body")
	end)
	T.it("un tir aux jambes touche un membre", function()
		local hit = shootAt(Vector3.new(0.45, 1.2, 0), STAND_ROOT, "Stand")
		T.eq(hit and hit.zone, "Limb")
	end)
	T.it("au-dessus de la tête : raté", function()
		T.eq(shootAt(Vector3.new(0, 5.6, 0), STAND_ROOT, "Stand"), nil)
	end)
	T.it("la tête d'un joueur accroupi est entièrement sous 4 studs (caisse standard)", function()
		local head = Hitbox.headOf(CROUCH_ROOT, "Crouch", 0)
		local top = head.Y + 0.55
		T.expect(top < 4.0, "sommet de tête accroupi = " .. top)
	end)
	T.it("l'oeil debout voit au-dessus d'une caisse de 4 studs, pas l'oeil accroupi", function()
		local standEye = Stances.eyePosition(STAND_ROOT, "Stand", 0)
		local crouchEye = Stances.eyePosition(CROUCH_ROOT, "Crouch", 0)
		T.expect(standEye.Y > 4.0, "oeil debout " .. standEye.Y)
		T.expect(crouchEye.Y < 4.0, "oeil accroupi " .. crouchEye.Y)
	end)
	T.it("l'oeil est à l'intérieur de la boîte de tête (toutes postures)", function()
		for _, stance in { "Stand", "Crouch", "Slide" } do
			local root = if stance == "Stand" then STAND_ROOT else CROUCH_ROOT
			local eye = Stances.eyePosition(root, stance, 0)
			local profile = Stances.profiles[stance]
			local head = profile.parts[1]
			local localEye = (root * head.offset):PointToObjectSpace(eye)
			local half = head.size * 0.5
			T.expect(
				math.abs(localEye.X) <= half.X and math.abs(localEye.Y) <= half.Y and math.abs(localEye.Z) <= half.Z,
				stance
			)
		end
	end)
	T.it("le lean décale la tête latéralement comme la caméra", function()
		local head = Hitbox.headOf(STAND_ROOT, "Stand", 1)
		local eye = Stances.eyePosition(STAND_ROOT, "Stand", 1)
		T.expect(head.X > 0.7, "tête x=" .. head.X)
		T.near(eye.X, head.X, 0.3, "oeil et tête alignés")
	end)
	T.it("les hitboxes suivent le yaw du joueur", function()
		local rotated = CFrame.new(0, 3, 0) * CFrame.Angles(0, math.rad(90), 0)
		local hit = Hitbox.raycast(Vector3.new(-40, 4.65, 0), Vector3.new(1, 0, 0), 200, rotated, "Stand", 0, 0)
		T.eq(hit and hit.zone, "Head")
	end)
	T.it("l'inflation élargit la tolérance", function()
		T.eq(shootAt(Vector3.new(0, 5.27, 0), STAND_ROOT, "Stand"), nil)
		local origin = Vector3.new(0, 5.27, -40)
		local hit = Hitbox.raycast(origin, Vector3.new(0, 0, 1), 200, STAND_ROOT, "Stand", 0, 0.2)
		T.eq(hit and hit.zone, "Head")
	end)
end)

T.describe("Spread", function()
	local aim = Vector3.new(0, 0, -1)
	T.it("déterministe pour une même graine", function()
		local a = Spread.directions(aim, 2, 12345, 1, 0)[1]
		local b = Spread.directions(aim, 2, 12345, 1, 0)[1]
		T.expect((a - b).Magnitude < 1e-9, "même direction")
	end)
	T.it("graines différentes -> directions différentes", function()
		local a = Spread.directions(aim, 2, Spread.seed(99, 1), 1, 0)[1]
		local b = Spread.directions(aim, 2, Spread.seed(99, 2), 1, 0)[1]
		T.expect((a - b).Magnitude > 1e-6, "directions distinctes")
	end)
	T.it("toujours dans le cône", function()
		for seed = 1, 300 do
			local direction = Spread.directions(aim, 3, Spread.seed(7, seed), 1, 0)[1]
			local angle = math.deg(MathUtil.angleBetween(aim, direction))
			T.expect(angle <= 3.0001, "angle " .. angle)
		end
	end)
	T.it("cône nul = visée parfaite", function()
		local direction = Spread.directions(aim, 0, 42, 1, 0)[1]
		T.expect((direction - aim).Magnitude < 1e-9, "parfait")
	end)
	T.it("fusil à pompe : 8 plombs dans cône + motif", function()
		local def = Weapons.require("sg12")
		local dirs = Spread.directions(aim, 1.0, 555, def.damage.pellets, def.spread.pelletCone)
		T.eq(#dirs, 8)
		for _, direction in dirs do
			local angle = math.deg(MathUtil.angleBetween(aim, direction))
			T.expect(angle <= 1.0 + def.spread.pelletCone * 1.15 + 1e-6, "plomb à " .. angle)
		end
	end)
	T.it("counter-strafe : sous 34% de la vitesse, aucune pénalité de mouvement", function()
		local profile = Weapons.require("vk12").spread
		local still = Spread.cone(
			profile,
			{ ads = 1, speedRatio = 0, airborne = false, crouched = false, bloom = 0, firstShot = false }
		)
		local slow = Spread.cone(
			profile,
			{ ads = 1, speedRatio = 0.3, airborne = false, crouched = false, bloom = 0, firstShot = false }
		)
		local running = Spread.cone(
			profile,
			{ ads = 1, speedRatio = 1, airborne = false, crouched = false, bloom = 0, firstShot = false }
		)
		T.near(still, slow, 1e-9, "pas de pénalité")
		T.near(running, still + profile.move, 1e-9, "pénalité pleine")
	end)
	T.it("le bloom monte puis récupère", function()
		local profile = Weapons.require("vk12").spread
		local bloom = 0
		for _ = 1, 20 do
			bloom = Spread.bloomAfterShot(profile, bloom, 0.1)
		end
		T.near(bloom, profile.bloomMax, 1e-9, "plafond")
		T.near(Spread.decayBloom(profile, bloom, 10), 0, 1e-9, "récupéré")
	end)
end)

T.describe("SpreadAudit (anti no-spread)", function()
	local aim = Vector3.new(0.3, -0.1, -1).Unit
	T.it("reproduit exactement le centre de Spread.directions", function()
		for shot = 1, 200 do
			local cone = 0.5 + shot % 7
			local seed = Spread.seed(31, shot)
			local expected = Spread.directions(aim, cone, seed, 1, 0)[1]
			local rebuilt = SpreadAudit.apply(aim, SpreadAudit.offset(cone, seed))
			T.expect(MathUtil.angleBetween(expected, rebuilt) < 1e-6, "tir " .. shot)
		end
	end)

	-- Le tricheur résout a tel que la balle (a + δ) parte exactement vers la cible.
	local function compensate(target, offset)
		local sent = target
		for _ = 1, 4 do
			sent = (sent + (target - SpreadAudit.apply(sent, offset))).Unit
		end
		return sent
	end

	-- 10 fenêtres de tirs en rafale (cône 2.5°, 10 tirs/s) ; visée humaine = marche
	-- aléatoire d'environ 1° par tir et par axe.
	local function simulate(cheater)
		local noise = Random.new(2024)
		local audit = SpreadAudit.new()
		local target = aim
		local cone = 2.5
		local results = {}
		for shot = 1, SpreadAudit.WINDOW * 10 + 1 do
			local step = Vector2.new(noise:NextNumber(-1, 1), noise:NextNumber(-1, 1)) * math.rad(1.7)
			target = SpreadAudit.apply(target, step)
			local seed = Spread.seed(4242, shot)
			local offset = SpreadAudit.offset(cone, seed)
			local sent = if cheater then compensate(target, offset) else target
			if cheater then
				local bullet = Spread.directions(sent, cone, seed, 1, 0)[1]
				T.expect(math.deg(MathUtil.angleBetween(bullet, target)) < 0.01, "balle parfaite")
			end
			local correlation = SpreadAudit.observe(audit, "vk12", shot * 0.1, sent, cone, offset)
			if correlation then
				table.insert(results, correlation)
			end
		end
		return results
	end

	T.it("joueur légitime : aucune fenêtre signalée", function()
		local results = simulate(false)
		T.eq(#results, 10, "fenêtres")
		for _, correlation in results do
			T.expect(correlation > SpreadAudit.FLAG_CORRELATION, "r = " .. correlation)
		end
	end)
	T.it("tricheur no-spread : signalé", function()
		local flagged = 0
		for _, correlation in simulate(true) do
			if correlation <= SpreadAudit.FLAG_CORRELATION then
				flagged += 1
			end
		end
		T.expect(flagged >= 9, "fenêtres signalées : " .. flagged)
	end)
	T.it("aucune paire entre armes différentes, après une pause ou sous le cône minimal", function()
		local audit = SpreadAudit.new()
		local offset = SpreadAudit.offset(3, 1)
		for shot = 1, 100 do
			local weapon = if shot % 2 == 0 then "vk12" else "sx5"
			T.eq(SpreadAudit.observe(audit, weapon, shot * 0.1, aim, 3, offset), nil)
		end
		for shot = 1, 100 do
			T.eq(SpreadAudit.observe(audit, "vk12", 100 + shot * 0.7, aim, 3, offset), nil)
		end
		for shot = 1, 100 do
			T.eq(SpreadAudit.observe(audit, "vk12", 500 + shot * 0.1, aim, 0.5, offset), nil)
		end
		T.eq(audit.count, 0, "paires comptées")
	end)
end)

T.describe("Balistique", function()
	local function headshotKills(id, distance, armor)
		local def = Weapons.require(id)
		local damage = Ballistics.damage(def.damage, "Head", distance, 1)
		local health = Ballistics.apply(100, armor, damage)
		return health <= 0, damage
	end
	T.it("VK-12 : one-tap tête bouclier plein à 150 studs", function()
		local kills, damage = headshotKills("vk12", 150, 50)
		T.expect(kills, "dégâts " .. damage)
	end)
	T.it("AR-9 : one-tap tête à 15 studs mais pas à 60", function()
		T.expect((headshotKills("ar9", 15, 50)), "proche")
		T.expect(not (headshotKills("ar9", 60, 50)), "loin")
	end)
	T.it("R-44 / DM-4 / BR-3 : one-tap tête bouclier plein", function()
		T.expect((headshotKills("r44", 20, 50)), "R-44")
		T.expect((headshotKills("dm4", 80, 50)), "DM-4")
		T.expect((headshotKills("br3", 50, 50)), "BR-3")
	end)
	T.it("P-10 : one-tap tête uniquement sans bouclier (manche pistolet)", function()
		T.expect((headshotKills("p10", 10, 0)), "sans bouclier")
		T.expect(not (headshotKills("p10", 10, 50)), "avec bouclier")
	end)
	T.it("tirs pour tuer au corps (bouclier plein)", function()
		T.eq(Ballistics.shotsToKill(Weapons.require("vk12").damage, "Body", 10, 50), 4, "VK-12")
		T.eq(Ballistics.shotsToKill(Weapons.require("dm4").damage, "Body", 10, 50), 2, "DM-4")
		T.eq(Ballistics.shotsToKill(Weapons.require("rs1").damage, "Body", 10, 50), 1, "RS-1")
		T.eq(Ballistics.shotsToKill(Weapons.require("rs1").damage, "Limb", 10, 50), 2, "RS-1 jambes")
	end)
	T.it("l'armure absorbe 66% sans changer le total", function()
		local health, armor, healthLoss, armorLoss = Ballistics.apply(100, 50, 30)
		T.near(armorLoss, 19.8, 1e-9, "armure")
		T.near(healthLoss + armorLoss, 30, 1e-9, "total")
		T.near(health, 89.8, 1e-9, "PV")
		T.near(armor, 30.2, 1e-9, "bouclier restant")
	end)
	T.it("chute de dégâts interpolée", function()
		local profile = Weapons.require("sx5").damage
		T.near(Ballistics.falloff(profile, 10), 1, 1e-9, "plateau")
		T.near(Ballistics.falloff(profile, 31.5), (1 + 0.83) / 2, 1e-6, "milieu")
		T.near(Ballistics.falloff(profile, 500), 0.67, 1e-9, "plancher")
	end)
	T.it("pénétration : verre et bois oui, 2 studs de métal non", function()
		local budget = Weapons.require("vk12").damage.penetration
		T.expect((Ballistics.penetrate(budget, 0.3, Enum.Material.Glass, false)) ~= nil, "verre")
		local multiplier = Ballistics.penetrate(budget, 1, Enum.Material.Wood, false)
		T.near(multiplier, 1 - 0.6 * (0.6 / 1.6), 1e-9, "bois")
		T.eq((Ballistics.penetrate(budget, 2, Enum.Material.Metal, false)), nil, "métal")
		T.eq((Ballistics.penetrate(budget, 0.1, Enum.Material.Glass, true)), nil, "impénétrable")
	end)

	T.it("rechargement tactique : +1 chambrée seulement si le chargeur n'est pas vide", function()
		local rifle = Weapons.require("vk12")
		T.eq(Weapons.reloadCapacity(rifle, 0), rifle.ammo.magazine, "à sec")
		T.eq(Weapons.reloadCapacity(rifle, 7), rifle.ammo.magazine + 1, "tactique")
		local shotgun = Weapons.require("sg12")
		T.eq(Weapons.reloadCapacity(shotgun, 3), shotgun.ammo.magazine, "tube : pas de chambre")
	end)

	-- Tableau de référence (utilisé par docs/07) : TTK corps à 15 studs, bouclier plein.
	local lines = { "\n  Arme      | tirs corps | TTK corps (s) | dégâts tête" }
	for _, id in Weapons.order do
		local def = Weapons.defs[id]
		if def.category ~= "Melee" then
			local shots = Ballistics.shotsToKill(def.damage, "Body", 15, 50)
			local ttk = 0
			if def.fire.mode == "Burst" then
				-- Rafales : intervalle intra-rafale + pause entre rafales.
				local intra = 60 / def.fire.burstRpm
				for shot = 2, shots do
					ttk += if (shot - 1) % def.fire.burstCount == 0 then intra + def.fire.burstCooldown else intra
				end
			elseif def.fire.spinUp then
				local held = 0
				for _ = 2, shots do
					local interval = 60 / Weapons.currentRpm(def, held)
					held += interval
					ttk += interval
				end
			else
				ttk = (shots - 1) * 60 / def.fire.rpm
			end
			local head = Ballistics.damage(def.damage, "Head", 15, 1) * def.damage.pellets
			table.insert(lines, ("  %-9s | %10d | %13.3f | %d"):format(def.shortName, shots, ttk, head))
		end
	end
	print(table.concat(lines, "\n"))
end)

T.describe("Audio des armes", function()
	local Sounds = req(Shared.Config.Sounds)
	T.it("toutes les clés et couches existent, sans cycle", function()
		for _, def in Weapons.defs do
			for field, key in def.audio :: any do
				T.expect(Sounds.get(key) ~= nil, def.id .. "." .. field .. " -> " .. key)
			end
		end
		for key, sound in Sounds.defs do
			for _, layer in sound.layers or {} do
				local child = Sounds.get(layer)
				T.expect(child ~= nil, key .. " couche inconnue " .. layer)
				T.expect(child == nil or child.layers == nil, key .. " : couches imbriquées")
			end
		end
	end)
	T.it("mix des tirs : volumes bas, pas de tonnerre derrière chaque coup", function()
		for _, def in Weapons.defs do
			if def.category ~= "Melee" then
				for _, key in { def.audio.fire, def.audio.tail, def.audio.mech } do
					local sound = Sounds.get(key) :: any
					local total = sound.volume
					for _, layer in sound.layers or {} do
						total += (Sounds.get(layer) :: any).volume
					end
					T.expect(total <= 0.75, ("%s : volume cumulé %.2f"):format(key, total))
					for _, id in sound.ids do
						T.expect(not string.find(id, "Thunder"), key .. " utilise encore le tonnerre")
					end
				end
			end
		end
	end)
end)
