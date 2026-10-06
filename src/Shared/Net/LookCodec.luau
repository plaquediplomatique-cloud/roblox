--!strict
--[[
	LookCodec — encodage binaire compact de la direction de visée (type `buffer`).

	La visée de chaque joueur est diffusée ~20 fois/s à tous les autres (pose du haut
	du corps en 3e personne, spectateur, killcam, anti-cheat). En tables Luau, un
	(yaw, pitch) coûte ~20+ octets sérialisés ; ici :
	  client -> serveur : 4 octets  (yaw u16, pitch i16)
	  serveur -> clients : 5 octets / joueur (slot u8, yaw u16, pitch i16), un seul
	  paquet UnreliableRemoteEvent par tick pour TOUS les joueurs.
	Précision : 0.0055° en yaw, 0.0027° en pitch — invisible.
]]

local LookCodec = {}

local TWO_PI = math.pi * 2
local HALF_PI = math.pi / 2

local function quantizeYaw(yaw: number): number
	local wrapped = yaw % TWO_PI
	return math.clamp(math.floor(wrapped / TWO_PI * 65535 + 0.5), 0, 65535)
end

local function dequantizeYaw(value: number): number
	local yaw = value / 65535 * TWO_PI
	if yaw > math.pi then
		yaw -= TWO_PI
	end
	return yaw
end

local function quantizePitch(pitch: number): number
	return math.clamp(math.floor(math.clamp(pitch, -HALF_PI, HALF_PI) / HALF_PI * 32767 + 0.5), -32767, 32767)
end

local function dequantizePitch(value: number): number
	return value / 32767 * HALF_PI
end

function LookCodec.encodeLocal(yaw: number, pitch: number): buffer
	local b = buffer.create(4)
	buffer.writeu16(b, 0, quantizeYaw(yaw))
	buffer.writei16(b, 2, quantizePitch(pitch))
	return b
end

function LookCodec.decodeLocal(value: any): (number?, number?)
	if typeof(value) ~= "buffer" or buffer.len(value) ~= 4 then
		return nil, nil
	end
	return dequantizeYaw(buffer.readu16(value, 0)), dequantizePitch(buffer.readi16(value, 2))
end

export type Entry = { slot: number, yaw: number, pitch: number }

function LookCodec.encodeBatch(entries: { Entry }): buffer
	local b = buffer.create(#entries * 5)
	for index, entry in entries do
		local offset = (index - 1) * 5
		buffer.writeu8(b, offset, entry.slot)
		buffer.writeu16(b, offset + 1, quantizeYaw(entry.yaw))
		buffer.writei16(b, offset + 3, quantizePitch(entry.pitch))
	end
	return b
end

function LookCodec.decodeBatch(value: any, callback: (slot: number, yaw: number, pitch: number) -> ())
	if typeof(value) ~= "buffer" then
		return
	end
	local length = buffer.len(value)
	if length % 5 ~= 0 then
		return
	end
	for offset = 0, length - 5, 5 do
		callback(
			buffer.readu8(value, offset),
			dequantizeYaw(buffer.readu16(value, offset + 1)),
			dequantizePitch(buffer.readi16(value, offset + 3))
		)
	end
end

return LookCodec
