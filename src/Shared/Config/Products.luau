--!strict
--[[
	Products — produits Robux (Developer Products), uniquement cosmétiques/confort.

	Les identifiants sont attribués par Roblox lors de la création des produits dans le
	Creator Dashboard (Monétisation > Developer Products) : ils n'existent qu'après
	publication de l'expérience. Tant qu'un `productId` vaut 0, l'offre est simplement
	masquée dans l'UI et ignorée par le serveur — aucune autre modification de code n'est
	nécessaire pour activer la boutique.
]]

export type ProductDef = {
	key: string,
	productId: number,
	displayName: string,
	description: string,
	crystals: number?,
	premiumPass: boolean?,
}

local Products = {}

Products.list = {
	{
		key = "pass_premium",
		productId = 0,
		displayName = "AETHER PASS PREMIUM",
		description = "Débloque la piste premium de la saison en cours (cosmétiques exclusifs).",
		premiumPass = true,
	},
	{
		key = "crystals_500",
		productId = 0,
		displayName = "500 CRISTAUX",
		description = "Monnaie premium pour les offres cosmétiques de la boutique rotative.",
		crystals = 500,
	},
	{
		key = "crystals_1200",
		productId = 0,
		displayName = "1 200 CRISTAUX",
		description = "Pack avantageux (+20 %).",
		crystals = 1200,
	},
} :: { ProductDef }

function Products.byProductId(productId: number): ProductDef?
	for _, product in Products.list do
		if product.productId ~= 0 and product.productId == productId then
			return product
		end
	end
	return nil
end

return Products
