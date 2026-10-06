--!strict
--[[
	ArmoryTab — ARMURERIE : choix du loadout, lecture des armes, skins, aperçu 3D.

	Toutes les valeurs affichées sont CALCULÉES depuis la config partagée (Weapons,
	Ballistics, RecoilPatterns) — jamais saisies à la main : l'UI ne peut pas mentir
	sur l'équilibrage. TTK = nombre de balles corps (bouclier plein, 15 studs) × cadence
	réelle (rafales et montée en cadence comprises).
	Aperçu : ViewportFrame + le MÊME constructeur procédural que le jeu (skin, néons
	animés, aura) en rotation lente.
]]

local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Weapons = require(Shared.Config.Weapons)
local Cosmetics = require(Shared.Config.Cosmetics)
local RecoilPatterns = require(Shared.Config.RecoilPatterns)
local Theme = require(Shared.Config.Theme)
local Ballistics = require(Shared.Combat.Ballistics)
local UI = require(script.Parent.Parent.UI.UI)
local ClientState = require(script.Parent.Parent.Core.ClientState)
local WeaponModelBuilder = require(script.Parent.Parent.Weapons.WeaponModelBuilder)
local Remote = require(script.Parent.Remote)

local colors = Theme.colors
local fonts = Theme.fonts

local ArmoryTab = {}

export type Tab = { frame: Frame, refresh: () -> (), focus: (option: string?) -> () }

local CATEGORY_NAMES: { [string]: string } = {
	AssaultRifle = "FUSIL D'ASSAUT",
	BurstRifle = "FUSIL À RAFALE",
	SMG = "PISTOLET-MITRAILLEUR",
	LMG = "MITRAILLEUSE",
	Sniper = "FUSIL DE PRÉCISION",
	DMR = "FUSIL DE TIREUR",
	Shotgun = "FUSIL À POMPE",
	Pistol = "PISTOLET",
	Revolver = "REVOLVER",
	MachinePistol = "PISTOLET AUTOMATIQUE",
	Melee = "LAME",
}

--[[ Temps pour tuer au corps (bouclier plein, 15 studs) — même calcul que la doc. ]]
function ArmoryTab.ttk(def: Types.WeaponDef): (number, number)
	local shots = Ballistics.shotsToKill(def.damage, "Body", 15, Ballistics.MAX_ARMOR)
	local ttk = 0
	if def.fire.mode == "Burst" then
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
	return shots, ttk
end

local function statValues(def: Types.WeaponDef): { { label: string, value: number } }
	local perShot = Ballistics.damage(def.damage, "Body", 15, 1) * def.damage.pellets
	local rpm = if def.fire.spinUp then def.fire.spinUp.endRpm else def.fire.rpm
	local recoil = RecoilPatterns.total(def.recoil.pattern, 10).Magnitude
	return {
		{ label = "DÉGÂTS", value = math.clamp(perShot / 130, 0.05, 1) },
		{ label = "CADENCE", value = math.clamp(rpm / 1100, 0.05, 1) },
		{
			label = "PORTÉE",
			value = math.clamp(Ballistics.falloff(def.damage, 60) * math.min(def.damage.range / 600, 1), 0.05, 1),
		},
		{ label = "PRÉCISION", value = math.clamp(1 - (def.spread.hip + def.spread.ads * 4) / 9, 0.05, 1) },
		{ label = "CONTRÔLE", value = math.clamp(1 - recoil / 16, 0.05, 1) },
		{ label = "MOBILITÉ", value = math.clamp((def.handling.moveMultiplier - 0.75) / 0.3, 0.05, 1) },
	}
end

function ArmoryTab.build(parent: Instance): Tab
	local frame = UI.frame({ BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = parent })
	local slot: Types.WeaponSlot = "Primary"
	local selected: Types.WeaponDef = Weapons.require(Weapons.DEFAULT_LOADOUT.Primary)
	local pendingBuy: string? = nil

	-- Liste (gauche)
	local slotTabs = UI.frame({ BackgroundTransparency = 1, Size = UDim2.new(0.3, 0, 0, 36), Parent = frame })
	UI.list(slotTabs, Enum.FillDirection.Horizontal, 6)
	local list = Instance.new("ScrollingFrame")
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(0, 46)
	list.Size = UDim2.new(0.3, 0, 1, -46)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ScrollBarThickness = 3
	list.Parent = frame
	UI.list(list, Enum.FillDirection.Vertical, 6)

	-- Aperçu et détails (droite)
	local detail = UI.frame({
		BackgroundTransparency = 1,
		Position = UDim2.new(0.3, 16, 0, 0),
		Size = UDim2.new(0.7, -16, 1, 0),
		Parent = frame,
	})
	local viewport = Instance.new("ViewportFrame")
	viewport.BackgroundColor3 = colors.void
	viewport.BackgroundTransparency = 0.2
	viewport.Size = UDim2.new(1, 0, 0.46, 0)
	viewport.Ambient = Color3.fromRGB(140, 150, 165)
	viewport.LightColor = Color3.fromRGB(235, 245, 255)
	viewport.LightDirection = Vector3.new(-1, -1.4, -0.6)
	viewport.Parent = detail
	UI.corner(4, viewport)
	UI.gradient(viewport, ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 170, 190)), 90)
	local viewCamera = Instance.new("Camera")
	viewCamera.FieldOfView = 30
	viewCamera.Parent = viewport
	viewport.CurrentCamera = viewCamera
	local title = UI.text({
		Text = "",
		FontFace = fonts.display,
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(18, 12),
		Size = UDim2.new(1, -36, 0, 30),
		ZIndex = 2,
		Parent = viewport,
	})
	local subtitle = UI.text({
		Text = "",
		FontFace = fonts.heading,
		TextSize = 14,
		TextColor3 = colors.primary,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(18, 44),
		Size = UDim2.new(1, -36, 0, 18),
		ZIndex = 2,
		Parent = viewport,
	})
	local info = UI.frame({
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0.46, 12),
		Size = UDim2.new(1, 0, 0.54, -12),
		Parent = detail,
	})
	local stats = UI.frame({ BackgroundTransparency = 1, Size = UDim2.new(0.5, -10, 0, 170), Parent = info })
	UI.list(stats, Enum.FillDirection.Vertical, 6)
	local facts = UI.text({
		Text = "",
		FontFace = fonts.mono,
		TextSize = 14,
		TextColor3 = colors.textDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.new(0.5, 10, 0, 0),
		Size = UDim2.new(0.5, -10, 0, 170),
		TextWrapped = true,
		Parent = info,
	})
	local equipButton = UI.actionButton("ÉQUIPER", "Primary", function() end, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 176),
		Size = UDim2.fromOffset(200, 42),
		Parent = info,
	})
	equipButton.TextSize = 17
	UI.text({
		Text = "SKINS",
		FontFace = fonts.heading,
		TextSize = 14,
		TextColor3 = colors.primary,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(0, 186),
		Size = UDim2.fromOffset(200, 20),
		Parent = info,
	})
	local skins = Instance.new("ScrollingFrame")
	skins.BackgroundTransparency = 1
	skins.BorderSizePixel = 0
	skins.Position = UDim2.fromOffset(0, 226)
	skins.Size = UDim2.new(1, 0, 1, -226)
	skins.AutomaticCanvasSize = Enum.AutomaticSize.X
	skins.CanvasSize = UDim2.new()
	skins.ScrollBarThickness = 3
	skins.ScrollingDirection = Enum.ScrollingDirection.X
	skins.Parent = info
	UI.list(skins, Enum.FillDirection.Horizontal, 8)

	local preview: WeaponModelBuilder.BuiltWeapon? = nil
	local previewKey = ""
	local spin = 0

	local function showPreview(def: Types.WeaponDef, skin: Types.ItemDef)
		local key = def.id .. "|" .. skin.id
		if key == previewKey then
			return
		end
		previewKey = key
		local old = preview
		if old then
			old:destroy()
		end
		local built = WeaponModelBuilder.build(def, skin, 1)
		built.model.Parent = viewport
		preview = built
		local _, size = built.model:GetBoundingBox()
		local distance = math.max(size.X, size.Y, size.Z) * 2.1 + 1
		viewCamera.CFrame = CFrame.lookAt(Vector3.new(distance * 0.55, distance * 0.18, distance * 0.82), Vector3.zero)
	end

	local function profile(): Types.ProfileData?
		return ClientState.profileData()
	end

	local function renderStats(def: Types.WeaponDef)
		for _, child in stats:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		if def.category == "Melee" then
			local melee = def.melee
			facts.Text = if melee
				then ("Coup rapide : %d\nCoup chargé : %d\nDans le dos (chargé) : %d\nPortée : %.1f studs\n\n%s"):format(
					melee.lightDamage,
					melee.heavyDamage,
					melee.backstabDamage,
					melee.range,
					def.feel
				)
				else def.feel
			return
		end
		for index, stat in statValues(def) do
			local row = UI.frame({
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 22),
				LayoutOrder = index,
				Parent = stats,
			})
			UI.text({
				Text = stat.label,
				FontFace = fonts.heading,
				TextSize = 13,
				TextColor3 = colors.textDim,
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.new(0.34, 0, 1, 0),
				Parent = row,
			})
			local track = UI.frame({
				BackgroundColor3 = colors.panelLight,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0.36, 0, 0.5, 0),
				Size = UDim2.new(0.64, 0, 0, 6),
				Parent = row,
			})
			local fill = UI.frame({ BackgroundColor3 = colors.primary, Size = UDim2.fromScale(0, 1), Parent = track })
			UI.tween(fill, Theme.tween.medium, { Size = UDim2.fromScale(stat.value, 1) })
		end
		local shots, ttk = ArmoryTab.ttk(def)
		local headDamage = Ballistics.damage(def.damage, "Head", 15, 1) * def.damage.pellets
		local oneTap = headDamage >= Ballistics.MAX_HEALTH + Ballistics.MAX_ARMOR
		facts.Text = table.concat({
			("TTK corps (bouclier) : %d balle%s · %.2f s"):format(shots, if shots > 1 then "s" else "", ttk),
			("Tête à 15 studs : %d%s"):format(headDamage, if oneTap then "  ·  ONE-TAP" else ""),
			("Cadence : %d coups/min%s"):format(
				if def.fire.spinUp then def.fire.spinUp.endRpm else def.fire.rpm,
				if def.fire.mode == "Burst" then (" (rafales de %d)"):format(def.fire.burstCount) else ""
			),
			("Chargeur : %d  ·  Réserve : %d"):format(def.ammo.magazine, def.ammo.reserve),
			("Rechargement : %.1f s (à vide %.1f s)"):format(def.ammo.reloadTime, def.ammo.emptyReloadTime),
			("Visée : %.2f s  ·  Zoom ×%.2f"):format(def.handling.adsTime, def.handling.zoom),
			("Pénétration : %.1f"):format(def.damage.penetration),
			"",
			def.feel,
		}, "\n")
	end

	local function renderSkins(def: Types.WeaponDef)
		for _, child in skins:GetChildren() do
			if child:IsA("GuiButton") then
				child:Destroy()
			end
		end
		local data = profile()
		local equippedSkin = Cosmetics.resolveSkin(if data then data.Cosmetics.WeaponSkins else {}, def.id)
		local items: { Types.ItemDef } = {}
		for _, id in Cosmetics.order do
			local item = Cosmetics.items[id]
			if item.kind == "WeaponSkin" and item.weaponId == def.id then
				table.insert(items, item)
			end
		end
		table.sort(items, function(a: Types.ItemDef, b: Types.ItemDef): boolean
			return Cosmetics.rarities[a.rarity].order < Cosmetics.rarities[b.rarity].order
		end)
		for order, item in items do
			local owned = data ~= nil and (data.Inventory[item.id] == true or item.line == "default")
			local equipped = item.id == equippedSkin.id
			local rarity = Cosmetics.rarities[item.rarity]
			local card = UI.button({
				Text = "",
				Size = UDim2.fromOffset(150, 70),
				LayoutOrder = order,
				BackgroundColor3 = if equipped then colors.panelLight else colors.panel,
				Parent = skins,
			})
			UI.corner(3, card)
			UI.stroke(
				card,
				if equipped then colors.primary else rarity.color,
				if equipped then 2 else 1,
				if owned then 0 else 0.5
			)
			UI.frame({ BackgroundColor3 = rarity.color, Size = UDim2.new(1, 0, 0, 3), Parent = card })
			UI.text({
				Text = item.displayName,
				FontFace = fonts.bodyBold,
				TextSize = 14,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Position = UDim2.fromOffset(8, 8),
				Size = UDim2.new(1, -16, 0, 18),
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = card,
			})
			local status = if equipped
				then "ÉQUIPÉ"
				elseif owned then "POSSÉDÉ"
				elseif item.price then (if pendingBuy == item.id then "CONFIRMER " else "") .. item.price .. " ◈"
				else "PASS / ÉVÉNEMENT"
			UI.text({
				Text = rarity.label .. "\n" .. status,
				FontFace = fonts.mono,
				TextSize = 11,
				TextColor3 = if pendingBuy == item.id then colors.warning else rarity.color,
				Position = UDim2.fromOffset(8, 30),
				Size = UDim2.new(1, -16, 0, 32),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				Parent = card,
			})
			card.MouseEnter:Connect(function()
				showPreview(def, item)
			end)
			card.MouseLeave:Connect(function()
				showPreview(def, equippedSkin)
			end)
			card.Activated:Connect(function()
				if owned and not equipped then
					UI.playSound("UI.Confirm")
					Remote.call("InventoryAction", { action = "EquipSkin", weapon = def.id, item = item.id })
				elseif not owned and item.price then
					if pendingBuy == item.id then
						pendingBuy = nil
						local response = Remote.call("ShopAction", { action = "Buy", item = item.id })
						if response.ok then
							UI.playSound("UI.Reward")
							Remote.call("InventoryAction", { action = "EquipSkin", weapon = def.id, item = item.id })
						end
					else
						pendingBuy = item.id
						UI.playSound("UI.Click")
						renderSkins(def)
					end
				end
			end)
		end
		showPreview(def, equippedSkin)
	end

	local function select(def: Types.WeaponDef)
		selected = def
		pendingBuy = nil
		title.Text = def.displayName
		subtitle.Text = ('%s  ·  "%s"'):format(CATEGORY_NAMES[def.category] or def.category, def.codename)
		renderStats(def)
		renderSkins(def)
		local data = profile()
		local equipped = data ~= nil and (data.Loadout :: any)[def.slot] == def.id
		equipButton.Text = if equipped then "ÉQUIPÉE" else "ÉQUIPER"
		equipButton.BackgroundColor3 = if equipped then colors.panelLight else colors.primary
		equipButton.TextColor3 = if equipped then colors.textDim else colors.void
	end

	local function renderList()
		for _, child in list:GetChildren() do
			if child:IsA("GuiButton") then
				child:Destroy()
			end
		end
		local data = profile()
		for order, def in Weapons.forSlot(slot) do
			local equipped = data ~= nil and (data.Loadout :: any)[slot] == def.id
			local active = def == selected
			local card = UI.button({
				Text = "",
				AutoButtonColor = false,
				Size = UDim2.new(1, -6, 0, 62),
				LayoutOrder = order,
				BackgroundColor3 = if active then colors.panelLight else colors.panel,
				Parent = list,
			})
			UI.corner(4, card)
			UI.stroke(card, if active then colors.primary else colors.stroke, if active then 2 else 1, 0)
			UI.text({
				Text = def.shortName,
				FontFace = fonts.headingHeavy,
				TextSize = 18,
				TextXAlignment = Enum.TextXAlignment.Left,
				Position = UDim2.fromOffset(14, 7),
				Size = UDim2.new(1, -110, 0, 24),
				Parent = card,
			})
			UI.text({
				Text = string.upper(CATEGORY_NAMES[def.category] or def.category),
				FontFace = fonts.heading,
				TextSize = 11,
				TextColor3 = colors.textDim,
				TextXAlignment = Enum.TextXAlignment.Left,
				Position = UDim2.fromOffset(14, 32),
				Size = UDim2.new(0.5, -14, 0, 14),
				Parent = card,
			})
			-- Mini-jauge de dégâts : comparer les armes sans ouvrir chaque fiche.
			local power = statValues(def)[1].value
			local track = UI.frame({
				Name = "Power",
				BackgroundColor3 = colors.panelLight,
				Position = UDim2.fromOffset(14, 50),
				Size = UDim2.new(0.5, -14, 0, 3),
				Parent = card,
			})
			UI.frame({
				BackgroundColor3 = if active then colors.primary else colors.textDim,
				Size = UDim2.fromScale(power, 1),
				Parent = track,
			})
			if equipped then
				local badge = UI.text({
					Name = "Equipped",
					Text = "ÉQUIPÉE",
					FontFace = fonts.headingHeavy,
					TextSize = 11,
					TextColor3 = colors.void,
					BackgroundColor3 = colors.primary,
					AutomaticSize = Enum.AutomaticSize.X,
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, -12, 0, 10),
					Size = UDim2.fromOffset(0, 18),
					Parent = card,
				})
				UI.corner(3, badge)
				UI.padding(badge, 7, 7, 0, 0)
			end
			card.MouseEnter:Connect(function()
				if not active then
					card.BackgroundColor3 = colors.panelLight
				end
			end)
			card.MouseLeave:Connect(function()
				card.BackgroundColor3 = if active then colors.panelLight else colors.panel
			end)
			card.Activated:Connect(function()
				UI.playSound("UI.Click")
				select(def)
				renderList()
			end)
		end
	end

	local function renderSlotTabs()
		for _, child in slotTabs:GetChildren() do
			if child:IsA("GuiButton") then
				child:Destroy()
			end
		end
		for index, name in { "Primary", "Secondary", "Melee" } do
			local labels: { [string]: string } = { Primary = "PRINCIPALE", Secondary = "SECONDAIRE", Melee = "LAME" }
			local active = slot == name
			local button = UI.button({
				Text = labels[name],
				TextSize = 13,
				FontFace = if active then fonts.headingHeavy else fonts.heading,
				AutoButtonColor = false,
				Size = UDim2.new(1 / 3, -4, 1, 0),
				LayoutOrder = index,
				BackgroundColor3 = colors.panelLight,
				BackgroundTransparency = if active then 0.2 else 0.7,
				TextColor3 = if active then colors.text else colors.textDim,
				Parent = slotTabs,
			})
			UI.corner(3, button)
			-- Onglet actif : soulignement cyan (pas seulement une couleur de fond).
			UI.frame({
				Name = "Underline",
				BackgroundColor3 = colors.primary,
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.fromScale(0.5, 1),
				Size = UDim2.new(1, -16, 0, 2),
				Visible = active,
				Parent = button,
			})
			button.Activated:Connect(function()
				slot = name :: Types.WeaponSlot
				local data = profile()
				local equippedId = if data then (data.Loadout :: any)[slot] else nil
				select(Weapons.get(equippedId or "") or Weapons.forSlot(slot)[1])
				renderSlotTabs()
				renderList()
			end)
		end
	end

	equipButton.Activated:Connect(function()
		local response =
			Remote.call("InventoryAction", { action = "EquipWeapon", slot = selected.slot, weapon = selected.id })
		if response.ok then
			UI.playSound("UI.Confirm")
		end
	end)

	-- Aperçu 3D : ne tourne que si l'onglet est réellement affiché (le menu fermé est
	-- seulement masqué : frame.Visible reste vrai).
	local function shown(): boolean
		local node: Instance? = frame
		while node and node:IsA("GuiObject") do
			if not node.Visible then
				return false
			end
			node = node.Parent
		end
		return true
	end
	RunService.RenderStepped:Connect(function(dt: number)
		local built = preview
		if built and shown() then
			spin += dt * 0.6
			built.model:PivotTo(CFrame.Angles(0, spin, 0) * CFrame.Angles(0, 0, math.sin(spin * 0.7) * 0.06))
		end
	end)

	local function refresh()
		renderSlotTabs()
		renderList()
		select(selected)
	end
	ClientState.ProfileReady:Connect(function(replica)
		replica.Changed:Connect(function()
			if frame.Visible then
				task.defer(refresh)
			end
		end)
	end)
	local existing = ClientState.profile()
	if existing then
		existing.Changed:Connect(function()
			if frame.Visible then
				task.defer(refresh)
			end
		end)
	end

	local function focus(option: string?)
		if option == "Primary" or option == "Secondary" or option == "Melee" then
			slot = option :: Types.WeaponSlot
		end
		local data = profile()
		local equippedId = if data then (data.Loadout :: any)[slot] else nil
		selected = Weapons.get(equippedId or "") or Weapons.forSlot(slot)[1]
		refresh()
	end

	return { frame = frame, refresh = refresh, focus = focus }
end

return ArmoryTab
