--!strict
--[[
	AudioController — mixage, spatialisation et "sound design" systémique.

	Hiérarchie de SoundGroups (volumes des réglages, ducking) :
	  Master ─┬─ Music
	          ├─ SFX ─┬─ Weapons ─ Footsteps ─ Impacts ─ Feedback ─ Ambient
	          └─ UI
	* Tirs : couche "corps" (+ couches composées : attaque, grave) + "mécanique" + "tail" ;
	  la tail est réverbérée en intérieur (plafond détecté par raycast). Les tirs lointains
	  (>120 studs) jouent la version "distant" : on lit la distance d'un combat à l'oreille.
	* Mise en forme par son (Sounds : égaliseur `tone`, coupe en fondu `cut`, `layers`) et
	  compresseur sur le groupe Armes : les rafales restent pleines sans agresser l'oreille.
	* Occlusion : un son 3D dont la ligne caméra -> source traverse un mur est filtré
	  (passe-bas + atténuation) : on distingue "derrière ce mur" de "dans cette pièce".
	* Ducking : sur un kill/une détonation, musique et ambiance s'effacent brièvement.
	* Bas PV : passe-bas global sur les SFX + battement de coeur (tunnel sensoriel).
	* Pas : par matériau, volume selon l'allure (marche = silencieuse).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Sounds = require(Shared.Config.Sounds)
local Theme = require(Shared.Config.Theme)
local SettingsController = require(script.Parent.SettingsController)

export type PlayOptions = {
	volume: number?,
	pitch: number?,
	occlusion: boolean?,
	reverb: boolean?,
}

local AudioController = {}

local groups: { [string]: SoundGroup } = {}
-- Filtres "bas PV" : un par groupe concerné (armes, impacts), pilotés ensemble.
local lowpassFilters: { EqualizerSoundEffect } = {}
local heartbeat: Sound? = nil
local ambient: Sound? = nil
local rng = Random.new()
local occlusionParams = RaycastParams.new()
occlusionParams.FilterType = Enum.RaycastFilterType.Include

local DISTANT_THRESHOLD = 120
local CUT_FADE = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Ambiance de la carte courante : sons ponctuels autour de l'auditeur + réverbération
-- du lieu (intérieur / extérieur, détecté par un rayon vers le ciel).
local ambience: Types.Ambience? = nil
local spotTimers: { number } = {}
local reverbClock = 0

local function group(name: string, parent: Instance, volume: number): SoundGroup
	local soundGroup = Instance.new("SoundGroup")
	soundGroup.Name = name
	soundGroup.Volume = volume
	soundGroup.Parent = parent
	groups[name] = soundGroup
	return soundGroup
end

local function applyVolumes(settings: Types.SettingsData)
	groups.Master.Volume = settings.Audio.Master
	groups.Music.Volume = settings.Audio.Music
	groups.SFX.Volume = settings.Audio.Sfx
	groups.UI.Volume = settings.Audio.Ui
end

local function geometryRoots(): { Instance }
	local roots: { Instance } = {}
	for _, name in { "Arenas", "Hub" } do
		local folder = Workspace:FindFirstChild(name)
		if folder then
			table.insert(roots, folder)
		end
	end
	return roots
end

local function create(key: string, options: PlayOptions?): Sound?
	local def = Sounds.get(key)
	if not def then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = key
	sound.SoundId = def.ids[rng:NextInteger(1, #def.ids)]
	sound.Volume = def.volume * (if options and options.volume then options.volume else 1)
	local pitch = rng:NextNumber(def.pitch.Min, def.pitch.Max)
		* (if options and options.pitch then options.pitch else 1)
	sound.PlaybackSpeed = pitch
	sound.Looped = def.looped == true
	sound.SoundGroup = groups[def.group] or groups.SFX
	if def.rolloff then
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = def.rolloff.X
		sound.RollOffMaxDistance = def.rolloff.Y
	end
	local tone = def.tone
	if tone then
		local equalizer = Instance.new("EqualizerSoundEffect")
		equalizer.Name = "Tone"
		equalizer.LowGain = tone.low or 0
		equalizer.MidGain = tone.mid or 0
		equalizer.HighGain = tone.high or 0
		equalizer.Priority = 2
		equalizer.Parent = sound
	end
	return sound
end

--[[ Coupe en fondu (`cut`) : garde l'attaque d'un échantillon et retire sa traîne. ]]
local function scheduleCut(sound: Sound, key: string)
	local def = Sounds.get(key)
	local cut = def and def.cut
	if not cut then
		return
	end
	task.delay(cut, function()
		if sound.Parent and sound.IsPlaying then
			TweenService:Create(sound, CUT_FADE, { Volume = 0 }):Play()
			task.delay(CUT_FADE.Time, function()
				if sound.Parent then
					sound:Destroy()
				end
			end)
		end
	end)
end

local function layersOf(key: string): { string }
	local def = Sounds.get(key)
	return if def and def.layers then def.layers else {}
end

--[[ Son 2D (interface, retours de combat). ]]
function AudioController.play(key: string, options: PlayOptions?): Sound?
	local sound = create(key, options)
	if not sound then
		return nil
	end
	for _, layer in layersOf(key) do
		AudioController.play(layer, options)
	end
	sound.Parent = SoundService
	sound:Play()
	scheduleCut(sound, key)
	if not sound.Looped then
		sound.Ended:Once(function()
			sound:Destroy()
		end)
		task.delay(8, function()
			if sound.Parent then
				sound:Destroy()
			end
		end)
	end
	return sound
end

local function isOccluded(position: Vector3): boolean
	local camera = Workspace.CurrentCamera
	if not camera then
		return false
	end
	occlusionParams.FilterDescendantsInstances = geometryRoots()
	local origin = camera.CFrame.Position
	local result = Workspace:Raycast(origin, position - origin, occlusionParams)
	return result ~= nil and (result.Position - position).Magnitude > 1.5
end

--[[ Son 3D ponctuel à une position du monde (occlusion optionnelle). ]]
function AudioController.playAt(key: string, position: Vector3, options: PlayOptions?): Sound?
	local sound = create(key, options)
	if not sound then
		return nil
	end
	local occluded = options ~= nil and options.occlusion == true and isOccluded(position)
	local layers = layersOf(key)
	if #layers > 0 then
		-- Les couches héritent du résultat d'occlusion (un seul rayon par tir).
		local layerOptions: PlayOptions = {
			volume = options and options.volume,
			pitch = options and options.pitch,
			reverb = options and options.reverb,
			occlusion = false,
		}
		for _, layer in layers do
			local layered = AudioController.playAt(layer, position, layerOptions)
			if layered and occluded then
				local filter = Instance.new("EqualizerSoundEffect")
				filter.LowGain = 2
				filter.MidGain = -8
				filter.HighGain = -24
				filter.Parent = layered
				layered.Volume *= 0.7
			end
		end
	end
	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = position
	attachment.Parent = Workspace.Terrain
	if occluded then
		local filter = Instance.new("EqualizerSoundEffect")
		filter.LowGain = 2
		filter.MidGain = -8
		filter.HighGain = -24
		filter.Parent = sound
		sound.Volume *= 0.7
	end
	if options and options.reverb then
		local reverb = Instance.new("ReverbSoundEffect")
		reverb.DecayTime = 1.1
		reverb.Density = 0.8
		reverb.WetLevel = -4
		reverb.DryLevel = 0
		reverb.Parent = sound
	end
	sound.Parent = attachment
	sound:Play()
	scheduleCut(sound, key)
	sound.Ended:Once(function()
		attachment:Destroy()
	end)
	sound.Destroying:Once(function()
		task.defer(function()
			if attachment.Parent then
				attachment:Destroy()
			end
		end)
	end)
	task.delay(10, function()
		if attachment.Parent then
			attachment:Destroy()
		end
	end)
	return sound
end

function AudioController.playOn(key: string, parent: Instance, options: PlayOptions?): Sound?
	local sound = create(key, options)
	if not sound then
		return nil
	end
	sound.Parent = parent
	sound:Play()
	if not sound.Looped then
		sound.Ended:Once(function()
			sound:Destroy()
		end)
	end
	return sound
end

local function indoorAt(position: Vector3): boolean
	occlusionParams.FilterDescendantsInstances = geometryRoots()
	return Workspace:Raycast(position, Vector3.new(0, 40, 0), occlusionParams) ~= nil
end

--[[ Tir : couches proches pour le tireur local, version lointaine/occluse pour les autres. ]]
function AudioController.weaponShot(def: Types.WeaponDef, position: Vector3, isLocal: boolean)
	local audio = def.audio
	if isLocal then
		AudioController.play(audio.fire)
		AudioController.play(audio.mech, { volume = 0.8 })
		AudioController.playAt(audio.tail, position, { reverb = indoorAt(position) })
		return
	end
	local camera = Workspace.CurrentCamera
	local distance = if camera then (camera.CFrame.Position - position).Magnitude else 0
	if distance > DISTANT_THRESHOLD then
		AudioController.playAt(audio.distant, position, { occlusion = true })
	else
		AudioController.playAt(audio.fire, position, { occlusion = true })
		AudioController.playAt(audio.tail, position, { occlusion = true, reverb = indoorAt(position) })
	end
end

function AudioController.impact(material: Enum.Material, position: Vector3, isCharacter: boolean)
	local key = "Impact.Concrete"
	if isCharacter then
		key = "Impact.Flesh"
	elseif
		material == Enum.Material.Metal
		or material == Enum.Material.DiamondPlate
		or material == Enum.Material.CorrodedMetal
	then
		key = "Impact.Metal"
	elseif material == Enum.Material.Wood or material == Enum.Material.WoodPlanks then
		key = "Impact.Wood"
	elseif material == Enum.Material.Glass or material == Enum.Material.Ice then
		key = "Impact.Glass"
	end
	AudioController.playAt(key, position, { volume = 0.8 })
end

-- Famille de pas par matériau de sol : on entend OÙ marche l'adversaire (grille de la
-- passerelle, marbre de la banque, neige de la falaise…), information tactique majeure.
local STEP_BY_MATERIAL: { [Enum.Material]: string } = {
	[Enum.Material.Metal] = "Step.Metal",
	[Enum.Material.DiamondPlate] = "Step.Metal",
	[Enum.Material.CorrodedMetal] = "Step.Metal",
	[Enum.Material.Foil] = "Step.Metal",
	[Enum.Material.Snow] = "Step.Soft",
	[Enum.Material.Grass] = "Step.Soft",
	[Enum.Material.LeafyGrass] = "Step.Soft",
	[Enum.Material.Fabric] = "Step.Soft",
	[Enum.Material.Sand] = "Step.Soft",
	[Enum.Material.Mud] = "Step.Soft",
	[Enum.Material.Carpet] = "Step.Soft",
	[Enum.Material.Wood] = "Step.Wood",
	[Enum.Material.WoodPlanks] = "Step.Wood",
	[Enum.Material.Marble] = "Step.Hard",
	[Enum.Material.Granite] = "Step.Hard",
	[Enum.Material.Slate] = "Step.Hard",
	[Enum.Material.Glass] = "Step.Hard",
	[Enum.Material.Ice] = "Step.Hard",
	[Enum.Material.Glacier] = "Step.Hard",
	[Enum.Material.CeramicTiles] = "Step.Hard",
	[Enum.Material.SmoothPlastic] = "Step.Hard",
}

function AudioController.footstep(position: Vector3, material: Enum.Material, volume: number, isLocal: boolean)
	if volume <= 0.01 then
		return
	end
	local key = STEP_BY_MATERIAL[material] or "Step.Default"
	if isLocal then
		AudioController.play(key, { volume = volume * 0.55 })
	else
		AudioController.playAt(key, position, { volume = volume, occlusion = true })
	end
end

--[[ Efface momentanément musique et ambiance (kill, détonation, annonce). ]]
function AudioController.duck(amount: number, duration: number)
	for _, name in { "Music", "Ambient" } do
		local soundGroup = groups[name]
		local base = if name == "Music" then SettingsController.get().Audio.Music else 1
		soundGroup.Volume = base * (1 - amount)
		TweenService
			:Create(
				soundGroup,
				TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Volume = base }
			)
			:Play()
	end
end

--[[ fraction = PV restants / max ; sous le seuil de bas PV : étouffement progressif + battement. ]]
function AudioController.setLowHealth(fraction: number)
	local threshold = Theme.feedback.lowHealth
	local intensity = math.clamp((threshold - fraction) / threshold, 0, 1)
	for _, filter in lowpassFilters do
		filter.HighGain = -28 * intensity
		filter.MidGain = -6 * intensity
	end
	if intensity > 0 and fraction > 0 then
		if not heartbeat then
			-- Créé hors de play() : un son joué par play() est détruit au bout de 8 s.
			local created = create("Heartbeat")
			if created then
				created.Looped = true
				created.Parent = SoundService
				created:Play()
				heartbeat = created
			end
		end
		local beat = heartbeat
		if beat then
			beat.Volume = 0.25 + 0.5 * intensity
			beat.PlaybackSpeed = 0.42 + 0.2 * intensity
		end
	elseif heartbeat then
		heartbeat:Destroy()
		heartbeat = nil
	end
end

--[[ Ambiance d'une carte (Shared/Config/Maps) : nil = aucune. ]]
function AudioController.setMapAmbience(value: Types.Ambience?)
	ambience = value
	table.clear(spotTimers)
	if value then
		for index, spot in value.spots do
			spotTimers[index] = rng:NextNumber(spot.interval.Min, spot.interval.Max)
		end
	else
		SoundService.AmbientReverb = Enum.ReverbType.NoReverb
	end
	reverbClock = 0
end

local function reverbType(name: string): Enum.ReverbType
	return Enum.ReverbType:FromName(name) or Enum.ReverbType.NoReverb
end

local function updateAmbience(dt: number)
	local current = ambience
	local camera = Workspace.CurrentCamera
	if not (current and camera) then
		return
	end
	local listener = camera.CFrame.Position
	for index, spot in current.spots do
		spotTimers[index] = (spotTimers[index] or 0) - dt
		if spotTimers[index] <= 0 then
			spotTimers[index] = rng:NextNumber(spot.interval.Min, spot.interval.Max)
			local angle = rng:NextNumber(0, math.pi * 2)
			local distance = rng:NextNumber(spot.distance.Min, spot.distance.Max)
			local offset = Vector3.new(math.cos(angle) * distance, rng:NextNumber(-2, 10), math.sin(angle) * distance)
			AudioController.playAt(spot.key, listener + offset)
		end
	end
	reverbClock -= dt
	if reverbClock <= 0 then
		reverbClock = 0.3
		occlusionParams.FilterDescendantsInstances = geometryRoots()
		local indoor = Workspace:Raycast(listener, Vector3.new(0, 60, 0), occlusionParams) ~= nil
		local target = reverbType(if indoor then current.indoorReverb else current.outdoorReverb)
		if SoundService.AmbientReverb ~= target then
			SoundService.AmbientReverb = target
		end
	end
end

function AudioController.setAmbient(key: string?)
	if ambient then
		ambient:Destroy()
		ambient = nil
	end
	if key then
		ambient = AudioController.play(key)
	end
end

function AudioController.start()
	local master = group("Master", SoundService, 1)
	group("Music", master, 0.45)
	local sfx = group("SFX", master, 1)
	group("UI", master, 0.8)
	for _, name in { "Weapons", "Footsteps", "Impacts", "Feedback", "Ambient", "Voice" } do
		group(name, sfx, if name == "Weapons" then 0.85 else 1)
	end
	-- Compresseur des armes : rafales homogènes, pics écrêtés en douceur.
	local compressor = Instance.new("CompressorSoundEffect")
	compressor.Name = "WeaponBus"
	compressor.Threshold = -18
	compressor.Ratio = 3.5
	compressor.Attack = 0.004
	compressor.Release = 0.15
	compressor.GainMakeup = 0
	compressor.Priority = 0
	compressor.Parent = groups.Weapons
	-- Limiteur général : aucun cumul (explosion + rafale + impacts) ne sature.
	local limiter = Instance.new("CompressorSoundEffect")
	limiter.Name = "MasterLimiter"
	limiter.Threshold = -6
	limiter.Ratio = 10
	limiter.Attack = 0.002
	limiter.Release = 0.2
	limiter.Priority = 0
	limiter.Parent = master
	for _, name in { "Weapons", "Impacts" } do
		local filter = Instance.new("EqualizerSoundEffect")
		filter.Name = "LowHealthFilter"
		filter.LowGain = 0
		filter.MidGain = 0
		filter.HighGain = 0
		filter.Priority = 1
		filter.Parent = groups[name]
		table.insert(lowpassFilters, filter)
	end
	applyVolumes(SettingsController.get())
	SettingsController.Changed:Connect(applyVolumes)
	Players.LocalPlayer.CharacterRemoving:Connect(function()
		AudioController.setLowHealth(1)
	end)
	RunService.Heartbeat:Connect(updateAmbience)
end

return AudioController
