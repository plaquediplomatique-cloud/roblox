--!strict
--[[
	Remote — appels de RemoteFunction du lobby, avec gestion d'erreur uniforme.

	Toutes les requêtes du lobby (party, file, inventaire, missions, boutique, salons)
	renvoient { ok, error?, data? } (ServerNet.Response). Un échec réseau ou un refus
	serveur produit un toast lisible ; l'appelant ne gère que le cas nominal.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Net.Net)

export type Response = { ok: boolean, error: string?, data: any? }

local Remote = {}

local toast: (text: string, kind: string?) -> () = function(_text: string, _kind: string?) end
local busy: { [string]: boolean } = {}

function Remote.setToast(fn: (text: string, kind: string?) -> ())
	toast = fn
end

--[[ Appel bloquant. Un même remote n'est jamais appelé deux fois en parallèle (anti double-clic). ]]
function Remote.call(name: Net.FunctionName, payload: { [string]: any }): Response
	if busy[name] then
		return { ok = false, error = nil, data = nil }
	end
	busy[name] = true
	local ok, result = pcall(function(): any
		return Net.func(name):InvokeServer(payload)
	end)
	busy[name] = nil
	if not ok or type(result) ~= "table" then
		toast("Serveur injoignable, réessayez", "Error")
		return { ok = false, error = "network", data = nil }
	end
	local response = result :: Response
	if not response.ok and type(response.error) == "string" then
		toast(response.error, "Error")
	end
	return response
end

return Remote
