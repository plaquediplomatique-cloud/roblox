--!strict
--[[
	Archetypes — familles d'armes (forme du modèle 3D + comportement de frappe).
	Speed multiplie la cadence de base ; Reach = portée en studs ; Swing = style d'animation ;
	Sound = couche sonore (Config/Sounds). Les recettes 3D sont dans Assets/WeaponRecipes.
]]

export type Archetype = {
	Speed: number,
	Reach: number,
	Swing: string, -- "Overhead" | "Slash" | "Stab" | "Spin" | "Slam"
	Sound: string, -- "Light" | "Heavy" | "Magic"
}

local list: { [string]: Archetype } = {
	Stick = { Speed = 1, Reach = 6, Swing = "Overhead", Sound = "Light" },
	Club = { Speed = 0.9, Reach = 6, Swing = "Overhead", Sound = "Heavy" },
	Fork = { Speed = 1.1, Reach = 6, Swing = "Stab", Sound = "Light" },
	Knife = { Speed = 1.3, Reach = 5, Swing = "Stab", Sound = "Light" },
	Dagger = { Speed = 1.35, Reach = 5, Swing = "Slash", Sound = "Light" },
	Sword = { Speed = 1, Reach = 7, Swing = "Slash", Sound = "Light" },
	Greatsword = { Speed = 0.75, Reach = 9, Swing = "Overhead", Sound = "Heavy" },
	Katana = { Speed = 1.15, Reach = 8, Swing = "Slash", Sound = "Light" },
	Axe = { Speed = 0.9, Reach = 7, Swing = "Overhead", Sound = "Heavy" },
	Hammer = { Speed = 0.7, Reach = 8, Swing = "Slam", Sound = "Heavy" },
	Spear = { Speed = 1, Reach = 10, Swing = "Stab", Sound = "Light" },
	Trident = { Speed = 0.95, Reach = 10, Swing = "Stab", Sound = "Light" },
	DoubleBlade = { Speed = 1.3, Reach = 6.5, Swing = "Spin", Sound = "Light" },
	Scythe = { Speed = 0.85, Reach = 9, Swing = "Spin", Sound = "Heavy" },
	Mace = { Speed = 0.8, Reach = 7, Swing = "Slam", Sound = "Heavy" },
	Staff = { Speed = 1, Reach = 8, Swing = "Overhead", Sound = "Magic" },
	EnergyBlade = { Speed = 1.2, Reach = 8, Swing = "Slash", Sound = "Magic" },
}

return list
