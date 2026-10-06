--!strict
--[[
	Movement — paramètres du contrôleur de déplacement (modèle "Source-like").

	Modèle :
	  * friction proportionnelle à la vitesse, avec plancher `stopSpeed` (arrêt net en fin),
	  * accélération = groundAccelerate × vitesse souhaitée (réactivité immédiate),
	  * counter-strafe : appuyer la direction opposée combine friction + accélération
	    inverse -> arrêt complet en ~70 ms, la précision revient (Spread.ACCURATE_SPEED_RATIO),
	  * air-control limité (airAccelerate + airWishCap) : on peut courber sa trajectoire
	    mais pas accélérer librement en l'air,
	  * bunny-hop LÉGER : sauter dans la fenêtre d'atterrissage (bhopWindow) évite la
	    friction, mais la vitesse est plafonnée à maxAirSpeedRatio × course et chaque hop
	    consécutif perd une partie de l'excédent : technique, jamais abusif,
	  * sprint (Maj) : vers l'avant uniquement, arme baissée ; tirer ou viser l'interrompt et
	    l'arme met `sprint.fireDelay` à se relever. Marche silencieuse sur Alt.
	Toutes les vitesses en studs/s, accélérations en studs/s².
]]

local Movement = {
	runSpeed = 17.5, -- allure normale (on peut tirer)
	walkSpeed = 9.5, -- marche silencieuse (Alt)
	crouchSpeed = 7.5,
	sprintSpeed = 23.5, -- sprint (Maj) : arme baissée, pas de tir ni de visée

	groundAccelerate = 11,
	friction = 7.5,
	stopSpeed = 7,
	airAccelerate = 2.2,
	airWishCap = 4.5,
	maxAirSpeedRatio = 1.12,

	jumpHeight = 4.4,
	jumpCooldown = 0.1,
	jumpBuffer = 0.12, -- un saut pressé juste avant l'atterrissage est mémorisé
	coyoteTime = 0.08, -- un saut juste après avoir quitté un rebord est toléré
	bhopWindow = 0.12,
	bhopDecay = 0.94,

	landing = {
		hardSpeed = 45, -- vitesse de chute au-delà de laquelle l'atterrissage pénalise
		slowMultiplier = 0.6,
		slowDuration = 0.25,
	},

	tagging = {
		multiplier = 0.72, -- ralentissement quand on est touché (lisibilité des duels)
		duration = 0.22,
	},

	slide = {
		minEntrySpeedRatio = 0.82, -- il faut courir pour glisser
		startSpeed = 27,
		speedCap = 30,
		friction = 14,
		frictionGrowth = 30, -- la décélération augmente pendant la glissade
		maxDuration = 1.0,
		cooldown = 0.75,
		steer = 0.35,
		slopeGain = 0.55,
		jumpCarry = 0.85, -- slide-jump : conserve 85 % de l'élan (plafonné en l'air)
		cameraTilt = 5,
		fovKick = 6,
	},

	sprint = {
		forwardMin = 0.45, -- part « avant » du déplacement nécessaire (pas de sprint latéral)
		fireDelay = 0.12, -- délai pour relever l'arme après un sprint (tir et visée)
		fovKick = 7,
		strideLength = 7.6,
	},

	lean = {
		speed = 14,
		blockedFraction = 0.25, -- si un mur bloque, lean réduit à 25 %
	},

	camera = {
		bobFrequency = 1.85, -- cycles par stud parcouru ÷ 2π (cadence de pas)
		bobVertical = 0.055,
		bobRoll = 0.35,
		landKick = 0.035, -- dip caméra par stud/s de chute
		landKickMax = 0.9,
		stairSmoothing = 22,
	},

	footsteps = {
		strideLength = 6.2, -- studs entre deux pas en course
		crouchStride = 4.4,
		runVolume = 1,
		crouchVolume = 0.25,
		walkVolume = 0, -- marche = silencieuse (fondamental en tactique), voir Rules/Footsteps
		maxHearDistance = 70,
	},
}

return Movement
