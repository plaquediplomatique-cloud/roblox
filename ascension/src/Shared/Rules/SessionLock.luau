--!strict
--[[
	SessionLock — verrou de session pour le DataStore (fonctions pures, testées).

	Un profil n'est écrit que par UN serveur à la fois : sans cela, un joueur qui change de
	serveur rapidement pourrait voir deux serveurs écraser mutuellement sa progression
	(duplication/perte d'objets). Le verrou expire (`ttl`) pour qu'un serveur planté ne bloque
	pas le joueur indéfiniment.

	Format stocké : { Data = <profil>, Lock = { JobId = string, Time = number }?, Saved = number }
]]

local SessionLock = {}

export type Record = {
	Data: any?,
	Lock: { JobId: string, Time: number }?,
	Saved: number?,
}

local function lockedByOther(record: Record, jobId: string, now: number, ttl: number): boolean
	local lock = record.Lock
	return lock ~= nil and lock.JobId ~= jobId and (now - lock.Time) < ttl
end

SessionLock.lockedByOther = lockedByOther

-- À utiliser dans UpdateAsync : renvoie l'enregistrement mis à jour, ou nil pour annuler
-- (verrou détenu par un autre serveur). Le second résultat indique si le verrou est acquis.
function SessionLock.acquire(record: any, jobId: string, now: number, ttl: number): (Record?, boolean)
	local current: Record = if type(record) == "table" then record :: Record else {}
	if lockedByOther(current, jobId, now, ttl) then
		return nil, false
	end
	current.Lock = { JobId = jobId, Time = now }
	return current, true
end

-- Écriture d'un profil : refusée (nil) si un autre serveur a pris le verrou entre-temps.
-- `release` retire notre verrou (départ du joueur) ; sinon on le rafraîchit.
function SessionLock.commit(record: any, data: any, jobId: string, now: number, ttl: number, release: boolean): Record?
	local current: Record = if type(record) == "table" then record :: Record else {}
	if lockedByOther(current, jobId, now, ttl) then
		return nil
	end
	return {
		Data = data,
		Lock = if release then nil else { JobId = jobId, Time = now },
		Saved = now,
	}
end

return SessionLock
