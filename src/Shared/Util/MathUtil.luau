--!strict
--[[
	MathUtil — maths de gameplay partagées (client = prédiction, serveur = autorité).

	Conventions Roblox : avant = -Z, haut = +Y, droite = +X.
	yaw   : rotation autour de Y (0 = regarde vers -Z), en radians
	pitch : élévation (positive = vers le haut), en radians
]]

local MathUtil = {}

local TWO_32 = 4294967296

function MathUtil.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

function MathUtil.clamp01(x: number): number
	return if x < 0 then 0 elseif x > 1 then 1 else x
end

function MathUtil.remap(x: number, inMin: number, inMax: number, outMin: number, outMax: number): number
	if inMax == inMin then
		return outMin
	end
	local t = MathUtil.clamp01((x - inMin) / (inMax - inMin))
	return outMin + (outMax - outMin) * t
end

--[[ Lissage exponentiel indépendant du framerate. `sharpness` ~ 1/temps de réponse. ]]
function MathUtil.damp(current: number, target: number, sharpness: number, dt: number): number
	return target + (current - target) * math.exp(-sharpness * dt)
end

function MathUtil.dampVector(current: Vector3, target: Vector3, sharpness: number, dt: number): Vector3
	return target + (current - target) * math.exp(-sharpness * dt)
end

function MathUtil.wrapAngle(angle: number): number
	return (angle + math.pi) % (2 * math.pi) - math.pi
end

--[[ Angle robuste entre deux vecteurs (radians) — stable même pour des angles minuscules. ]]
function MathUtil.angleBetween(a: Vector3, b: Vector3): number
	return math.atan2(a:Cross(b).Magnitude, a:Dot(b))
end

function MathUtil.directionFromYawPitch(yaw: number, pitch: number): Vector3
	local cp = math.cos(pitch)
	return Vector3.new(-math.sin(yaw) * cp, math.sin(pitch), -math.cos(yaw) * cp)
end

function MathUtil.yawPitchFromDirection(direction: Vector3): (number, number)
	local unit = direction.Unit
	local yaw = math.atan2(-unit.X, -unit.Z)
	local pitch = math.asin(math.clamp(unit.Y, -1, 1))
	return yaw, pitch
end

function MathUtil.flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

function MathUtil.round(x: number, step: number): number
	return math.floor(x / step + 0.5) * step
end

--[[
	Intersection rayon / boîte alignée (espace local de la boîte), méthode des slabs.
	`origin` et `direction` sont en espace local ; `direction` unitaire.
	Renvoie la distance d'entrée (0 si l'origine est dans la boîte) ou nil.
]]
function MathUtil.rayBoxLocal(origin: Vector3, direction: Vector3, half: Vector3, maxDistance: number): number?
	local tMin, tMax = 0, maxDistance

	-- Axe X
	local o, d, h = origin.X, direction.X, half.X
	if math.abs(d) < 1e-9 then
		if o < -h or o > h then
			return nil
		end
	else
		local inv = 1 / d
		local t1, t2 = (-h - o) * inv, (h - o) * inv
		if t1 > t2 then
			t1, t2 = t2, t1
		end
		if t1 > tMin then
			tMin = t1
		end
		if t2 < tMax then
			tMax = t2
		end
		if tMin > tMax then
			return nil
		end
	end

	-- Axe Y
	o, d, h = origin.Y, direction.Y, half.Y
	if math.abs(d) < 1e-9 then
		if o < -h or o > h then
			return nil
		end
	else
		local inv = 1 / d
		local t1, t2 = (-h - o) * inv, (h - o) * inv
		if t1 > t2 then
			t1, t2 = t2, t1
		end
		if t1 > tMin then
			tMin = t1
		end
		if t2 < tMax then
			tMax = t2
		end
		if tMin > tMax then
			return nil
		end
	end

	-- Axe Z
	o, d, h = origin.Z, direction.Z, half.Z
	if math.abs(d) < 1e-9 then
		if o < -h or o > h then
			return nil
		end
	else
		local inv = 1 / d
		local t1, t2 = (-h - o) * inv, (h - o) * inv
		if t1 > t2 then
			t1, t2 = t2, t1
		end
		if t1 > tMin then
			tMin = t1
		end
		if t2 < tMax then
			tMax = t2
		end
		if tMin > tMax then
			return nil
		end
	end

	return tMin
end

--[[ Intersection rayon / boîte orientée (OBB) définie par un CFrame et une demi-taille. ]]
function MathUtil.rayOBB(
	origin: Vector3,
	direction: Vector3,
	cframe: CFrame,
	half: Vector3,
	maxDistance: number
): number?
	local localOrigin = cframe:PointToObjectSpace(origin)
	local localDirection = cframe:VectorToObjectSpace(direction)
	return MathUtil.rayBoxLocal(localOrigin, localDirection, half, maxDistance)
end

--[[ Test rapide rayon / sphère (broadphase avant les OBB). Renvoie la distance d'entrée. ]]
function MathUtil.raySphere(origin: Vector3, direction: Vector3, center: Vector3, radius: number): number?
	local toCenter = center - origin
	local projection = toCenter:Dot(direction)
	local distanceSq = toCenter:Dot(toCenter) - projection * projection
	local radiusSq = radius * radius
	if distanceSq > radiusSq then
		return nil
	end
	local offset = math.sqrt(radiusSq - distanceSq)
	local t0 = projection - offset
	local t1 = projection + offset
	if t1 < 0 then
		return nil
	end
	return math.max(t0, 0)
end

--[[ Multiplication 32 bits sans perte de précision (les doubles n'ont que 53 bits de mantisse). ]]
local function mul32(a: number, b: number): number
	local aLo = a % 65536
	local aHi = (a - aLo) / 65536
	return (aLo * b + ((aHi * b) % 65536) * 65536) % TWO_32
end

--[[ Hash entier 32 bits (avalanche) — graines déterministes partagées client/serveur. ]]
function MathUtil.hash32(value: number): number
	local x = math.floor(value) % TWO_32
	x = bit32.bxor(x, bit32.rshift(x, 16))
	x = mul32(x, 0x45D9F3B)
	x = bit32.bxor(x, bit32.rshift(x, 16))
	x = mul32(x, 0x45D9F3B)
	x = bit32.bxor(x, bit32.rshift(x, 16))
	return x
end

function MathUtil.combineSeed(base: number, index: number): number
	return MathUtil.hash32(bit32.bxor(math.floor(base) % TWO_32, mul32(index % TWO_32, 0x9E3779B1)))
end

return MathUtil
