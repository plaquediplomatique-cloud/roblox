--!strict
--[[
	AudioController — mixage, spatialisation et "sound design" systémique.

	Hiérarchie de SoundGroups (volumes des réglages, ducking) :
	  Master ─┬─ Music
	          ├─ SFX ─┬─ Weapons ─ Footsteps ─ Impacts ─ Feedback ─ Ambient
	          └─ UI
	* Tirs : couche "corps" + "mécanique" + "tail" ; la tail est réverbérée en
	  intérieur (plafond détecté par raycast). Les tirs lointains (>120 studs) jouent
	  la version "distant" : on lit la distance d'un combat à l'oreille.
	* Occlusion : un son 3D dont la ligne caméra -> source traverse un mur est filtré
	  (passe-bas + atténuation) : on distingue "derrière ce mur" de "dans cette pièce".
	* Ducking : sur un kill/une détonation, musique et ambiance s'effacent brièvement.
	* Bas PV : passe-bas global sur les SFX + battement de coeur (tunnel sensoriel).
	* Pas : par matériau, volume selon l'allure (marche = silencieuse).
]]

local Players = game:GetService("Players")
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
local lowpass: EqualizerSoundEffect
local heartbeat: Sound? = nil
local ambient: Sound? = nil
local rng = Random.new()
local occlusionParams = RaycastParams.new()
occlusionParams.FilterType = Enum.RaycastFilterType.Include

local DISTANT_THRESHOLD = 120

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
	return sound
end

--[[ Son 2D (interface, retours de combat). ]]
function AudioController.play(key: string, options: PlayOptions?): Sound?
	local sound = create(key, options)
	if not sound then
		return nil
	end
	sound.Parent = SoundService
	sound:Play()
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
	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = position
	attachment.Parent = Workspace.Terrain
	if options and options.occlusion and isOccluded(position) then
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
	sound.Ended:Once(function()
		attachment:Destroy()
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

function AudioController.footstep(position: Vector3, material: Enum.Material, volume: number, isLocal: boolean)
	if volume <= 0.01 then
		return
	end
	local key = "Step.Default"
	if
		material == Enum.Material.Metal
		or material == Enum.Material.DiamondPlate
		or material == Enum.Material.CorrodedMetal
	then
		key = "Step.Metal"
	elseif
		material == Enum.Material.Snow
		or material == Enum.Material.Grass
		or material == Enum.Material.Fabric
		or material == Enum.Material.Sand
	then
		key = "Step.Soft"
	end
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
	lowpass.HighGain = -28 * intensity
	lowpass.MidGain = -6 * intensity
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
		group(name, sfx, 1)
	end
	lowpass = Instance.new("EqualizerSoundEffect")
	lowpass.Name = "LowHealthFilter"
	lowpass.LowGain = 0
	lowpass.MidGain = 0
	lowpass.HighGain = 0
	lowpass.Priority = 1
	lowpass.Parent = groups.Weapons
	local secondary = lowpass:Clone()
	secondary.Parent = groups.Impacts
	applyVolumes(SettingsController.get())
	SettingsController.Changed:Connect(applyVolumes)
	Players.LocalPlayer.CharacterRemoving:Connect(function()
		AudioController.setLowHealth(1)
	end)
end

return AudioController
