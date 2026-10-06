--!strict
--[[
	Spring — ressort amorti à intégration ANALYTIQUE (exacte quel que soit dt).

	Utilisé partout où le "game feel" compte : FOV d'ADS, hauteur des yeux (crouch/slide),
	sway et bob du viewmodel, kick de recul, punch caméra, animations d'UI.

	Contrairement à une intégration d'Euler, la solution analytique ne diverge jamais, même
	à 20 FPS ou lors d'un hitch de 200 ms : le ressort reste stable et le rendu identique
	quel que soit le framerate (essentiel pour un FPS compétitif).

	Paramètres :
	  speed   = pulsation propre ω (rad/s) — plus grand = plus nerveux
	  damping = ζ ; <1 rebond (overshoot), =1 critique (le plus rapide sans rebond), >1 mou

	L'état évolue linéairement : x' = pp·x + pv·v ; v' = vp·x + vv·v  (x = position − cible).
	Les 4 coefficients ne dépendent que de (ω, ζ, dt), donc la même fonction sert aux
	nombres et aux Vector3.
]]

local Spring = {}

export type Coefficients = { pp: number, pv: number, vp: number, vv: number }

local scratch: Coefficients = { pp = 1, pv = 0, vp = 0, vv = 1 }

function Spring.coefficients(omega: number, zeta: number, dt: number, out: Coefficients?): Coefficients
	local c = out or scratch
	if dt <= 0 or omega <= 0 then
		c.pp, c.pv, c.vp, c.vv = 1, 0, 0, 1
		return c
	end
	if zeta < 0.9999 then
		-- Sous-amorti
		local alpha = omega * math.sqrt(1 - zeta * zeta)
		local e = math.exp(-zeta * omega * dt)
		local cosA = math.cos(alpha * dt)
		local sinA = math.sin(alpha * dt)
		local zw = zeta * omega
		c.pp = e * (cosA + zw * sinA / alpha)
		c.pv = e * sinA / alpha
		c.vp = -e * sinA * omega * omega / alpha
		c.vv = e * (cosA - zw * sinA / alpha)
	elseif zeta <= 1.0001 then
		-- Critique
		local e = math.exp(-omega * dt)
		c.pp = e * (1 + omega * dt)
		c.pv = e * dt
		c.vp = -e * omega * omega * dt
		c.vv = e * (1 - omega * dt)
	else
		-- Sur-amorti
		local root = math.sqrt(zeta * zeta - 1)
		local r1 = -omega * (zeta - root)
		local r2 = -omega * (zeta + root)
		local e1 = math.exp(r1 * dt)
		local e2 = math.exp(r2 * dt)
		local inv = 1 / (r1 - r2)
		c.pp = (r1 * e2 - r2 * e1) * inv
		c.pv = (e1 - e2) * inv
		c.vp = r1 * r2 * (e2 - e1) * inv
		c.vv = (r1 * e1 - r2 * e2) * inv
	end
	return c
end

---------------------------------------------------------------------------------------------
-- Ressort scalaire
---------------------------------------------------------------------------------------------

export type NumberSpring = {
	position: number,
	velocity: number,
	target: number,
	speed: number,
	damping: number,
	step: (self: NumberSpring, dt: number) -> number,
	impulse: (self: NumberSpring, velocity: number) -> (),
	snap: (self: NumberSpring, value: number) -> (),
}

local NumberSpringClass = {}
NumberSpringClass.__index = NumberSpringClass

function NumberSpringClass.step(self: NumberSpring, dt: number): number
	local c = Spring.coefficients(self.speed, self.damping, dt)
	local x = self.position - self.target
	local v = self.velocity
	self.position = self.target + c.pp * x + c.pv * v
	self.velocity = c.vp * x + c.vv * v
	return self.position
end

function NumberSpringClass.impulse(self: NumberSpring, velocity: number)
	self.velocity += velocity
end

function NumberSpringClass.snap(self: NumberSpring, value: number)
	self.position = value
	self.target = value
	self.velocity = 0
end

function Spring.number(initial: number, speed: number, damping: number): NumberSpring
	local self = {
		position = initial,
		velocity = 0,
		target = initial,
		speed = speed,
		damping = damping,
	}
	return (setmetatable(self, NumberSpringClass) :: any) :: NumberSpring
end

---------------------------------------------------------------------------------------------
-- Ressort vectoriel
---------------------------------------------------------------------------------------------

export type VectorSpring = {
	position: Vector3,
	velocity: Vector3,
	target: Vector3,
	speed: number,
	damping: number,
	step: (self: VectorSpring, dt: number) -> Vector3,
	impulse: (self: VectorSpring, velocity: Vector3) -> (),
	snap: (self: VectorSpring, value: Vector3) -> (),
}

local VectorSpringClass = {}
VectorSpringClass.__index = VectorSpringClass

function VectorSpringClass.step(self: VectorSpring, dt: number): Vector3
	local c = Spring.coefficients(self.speed, self.damping, dt)
	local x = self.position - self.target
	local v = self.velocity
	self.position = self.target + x * c.pp + v * c.pv
	self.velocity = x * c.vp + v * c.vv
	return self.position
end

function VectorSpringClass.impulse(self: VectorSpring, velocity: Vector3)
	self.velocity += velocity
end

function VectorSpringClass.snap(self: VectorSpring, value: Vector3)
	self.position = value
	self.target = value
	self.velocity = Vector3.zero
end

function Spring.vector(initial: Vector3, speed: number, damping: number): VectorSpring
	local self = {
		position = initial,
		velocity = Vector3.zero,
		target = initial,
		speed = speed,
		damping = damping,
	}
	return (setmetatable(self, VectorSpringClass) :: any) :: VectorSpring
end

return Spring
