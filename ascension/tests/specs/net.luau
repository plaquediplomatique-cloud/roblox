--[[ Tests : schémas réseau contre des payloads d'exploiteur. ]]

local Schemas = req(Shared.Net.Schemas)
local Net = req(Shared.Net.Net)

T.describe("Schemas (anti-exploit)", function()
	T.it("accepte les intentions légitimes", function()
		T.expect(Schemas.Swing({}))
		T.expect(Schemas.Swing({ t = "d_12", n = 5 }))
		T.expect(Schemas.Equip({ id = "WoodenStick" }))
		T.expect(Schemas.BuyUpgrade({ id = "Power" }))
		T.expect(Schemas.PlaceDecor({ slot = "S1", id = "Lamp" }))
		T.expect(Schemas.PlaceDecor({ slot = "S1" }))
		T.expect(Schemas.Ascend({}))
		T.expect(Schemas.SetSetting({ key = "Music", value = false }))
	end)
	T.it("refuse les montants/valeurs injectés (champs inconnus)", function()
		T.eq(Schemas.Swing({ damage = 999999 }), false)
		T.eq(Schemas.BuyUpgrade({ id = "Power", cost = 0 }), false)
		T.eq(Schemas.Equip({ id = "VoidBlade", level = 120 }), false)
		T.eq(Schemas.ClaimQuest({ id = "D_Hits_A", amount = 1e9 }), false)
	end)
	T.it("refuse les mauvais types, NaN, inf, chaînes géantes, tables piégées", function()
		T.eq(Schemas.Swing({ t = 5 }), false)
		T.eq(Schemas.Swing({ n = 0 / 0 }), false)
		T.eq(Schemas.Swing({ n = math.huge }), false)
		T.eq(Schemas.Swing({ n = -1 }), false)
		T.eq(Schemas.Swing({ n = 1.5 }), false)
		T.eq(Schemas.Equip({ id = string.rep("A", 5000) }), false)
		T.eq(Schemas.Equip({ id = { "x" } }), false)
		T.eq(Schemas.Equip(nil), false)
		T.eq(Schemas.Equip("Fork"), false)
		T.eq(Schemas.SetSetting({ key = "Music", value = "yes" }), false)
		T.eq(
			Schemas.Swing(setmetatable({}, {
				__index = function()
					return 1
				end,
			})),
			false
		)
		T.eq(Schemas.Swing({ [1] = "x" }), false)
	end)
	T.it("chaque remote C2S validé a une limite de débit, et inversement", function()
		for name, kind in Net.Declaration do
			local isC2S = Schemas[name] ~= nil
			if isC2S then
				T.expect(Schemas.Rates[name] ~= nil, "limite manquante: " .. name)
			end
			if kind == "Function" or isC2S then
				T.expect(isC2S, "schéma manquant: " .. name)
			end
		end
		for name in Schemas.Rates do
			T.expect(Net.Declaration[name] ~= nil, "limite orpheline: " .. name)
		end
	end)
	T.it("les remotes S2C n'ont PAS de schéma client (aucun handler serveur)", function()
		for _, name in { "Sync", "HitResult", "LevelUp", "Notify", "ChestResult", "WeaponUnlocked", "SwingFx" } do
			T.eq(Schemas[name], nil, name)
		end
	end)
end)
