--!strict
--[[ Shop catalog: coin unlocks, Robux products, gamepass, and combat buffs. ]]

export type ShopCurrency = "coins" | "robux"
export type ShopItemKind = "character" | "skin" | "bundle" | "gamepass" | "devproduct"

export type ShopItem = {
	id: string,
	name: string,
	description: string,
	kind: ShopItemKind,
	currency: ShopCurrency,
	price: number,
	productId: number?,
	gamepassId: number?,
	grantCharacter: string?,
	grantSkins: { { heroId: string, skinId: string } }?,
	grantBundle: string?,
	buffLabel: string?,
}

export type CoinPack = {
	id: string,
	label: string,
	amount: number,
	productId: number,
	robuxPrice: number?,
}

local ShopCatalog = {}

-- TEMP playtest unlock: set to false to restore character/skin shop locks.
ShopCatalog.UNLOCK_ALL = true

-- Creator Dashboard gamepass IDs
ShopCatalog.ELITE_GAMEPASS_ID = 1951310371
ShopCatalog.PHOENIX_GAMEPASS_ID = 1951017728
ShopCatalog.ROGUE_GAMEPASS_ID = 1948287768

ShopCatalog.KILL_COIN_REWARD = 100
ShopCatalog.ELITE_COIN_MULT = 2

-- Creator Dashboard developer product IDs for coin packs (set each productId after publishing).
ShopCatalog.COIN_PACKS = {
	{ id = "coins_1k", label = "+1,000", amount = 1000, productId = 0, robuxPrice = 49 },
	{ id = "coins_5k", label = "+5,000", amount = 5000, productId = 0, robuxPrice = 199 },
	{ id = "coins_10k", label = "+10,000", amount = 10000, productId = 0, robuxPrice = 349 },
	{ id = "coins_50k", label = "+50,000", amount = 50000, productId = 0, robuxPrice = 1499 },
}

ShopCatalog.MARVEL_GIRL_BUFF = 1.10
ShopCatalog.MODERN_COSTUME_BUFF = 1.25

ShopCatalog.FREE_CHARACTERS = {
	"jean_grey",
	"spider_man",
	"crystal",
	"cyclops",
	"human_torch",
	"invisible_woman",
}

ShopCatalog.DEFAULT_OWNED_SKINS = {
	jean_grey = { "base" },
	human_torch = { "base" },
	invisible_woman = { "base" },
}

ShopCatalog.MODERN_BUNDLE_ID = "modern_costumes"
ShopCatalog.MODERN_BUNDLE_SKINS = {
	{ heroId = "human_torch", skinId = "modern" },
	{ heroId = "invisible_woman", skinId = "modern" },
}

local ITEMS: { ShopItem } = {
	{
		id = "marvel_girl",
		name = "Marvel Girl",
		description = "Jean Grey Marvel Girl costume. +10% outgoing damage.",
		kind = "skin",
		currency = "coins",
		price = 10000,
		grantSkins = { { heroId = "jean_grey", skinId = "marvel_girl" } },
		buffLabel = "+10% damage",
	},
	{
		id = "blue_marvel",
		name = "Blue Marvel",
		description = "Unlock Adam Brashear — anti-matter powerhouse.",
		kind = "character",
		currency = "coins",
		price = 10000,
		grantCharacter = "blue_marvel",
	},
	{
		id = "modern_costumes",
		name = "Modern Costumes Pack",
		description = "Modern skins for Human Torch and Invisible Woman. +25% outgoing damage while wearing them.",
		kind = "bundle",
		currency = "coins",
		price = 23500,
		grantBundle = ShopCatalog.MODERN_BUNDLE_ID,
		grantSkins = ShopCatalog.MODERN_BUNDLE_SKINS,
		buffLabel = "+25% damage",
	},
	{
		id = "scarlet_witch",
		name = "Scarlet Witch",
		description = "Unlock Wanda Maximoff and her full hex kit.",
		kind = "character",
		currency = "coins",
		price = 30000,
		grantCharacter = "scarlet_witch_classic",
	},
	{
		id = "storm",
		name = "Storm",
		description = "Unlock Ororo Munroe — weather manipulation.",
		kind = "character",
		currency = "coins",
		price = 25000,
		grantCharacter = "storm",
	},
	{
		id = "phoenix_force",
		name = "Phoenix Force",
		description = "Jean Grey Phoenix Force skin with revive.",
		kind = "gamepass",
		currency = "robux",
		price = 800,
		gamepassId = ShopCatalog.PHOENIX_GAMEPASS_ID,
		grantSkins = { { heroId = "jean_grey", skinId = "phoenix" } },
	},
	{
		id = "rogue",
		name = "Rogue",
		description = "Unlock Anna Marie — power absorption brawler.",
		kind = "gamepass",
		currency = "robux",
		price = 600,
		gamepassId = ShopCatalog.ROGUE_GAMEPASS_ID,
		grantCharacter = "rogue",
	},
	{
		id = "elite_gamepass",
		name = "Elite Gamepass",
		description = "2x coin rewards on kills (200 per kill) and Elite title on your nameplate.",
		kind = "gamepass",
		currency = "robux",
		price = 500,
		gamepassId = ShopCatalog.ELITE_GAMEPASS_ID,
	},
}

function ShopCatalog.getPreviewMorph(itemId: string): (string?, string?)
	if itemId == "marvel_girl" then
		return "jean_grey", "marvel_girl"
	elseif itemId == "blue_marvel" then
		return "blue_marvel", "base"
	elseif itemId == "modern_costumes" then
		return "invisible_woman", "modern"
	elseif itemId == "scarlet_witch" then
		return "scarlet_witch_classic", "base"
	elseif itemId == "storm" then
		return "storm", "base"
	elseif itemId == "phoenix_force" then
		return "jean_grey", "phoenix"
	elseif itemId == "rogue" then
		return "rogue", "base"
	elseif itemId == "elite_gamepass" then
		return "jean_grey", "phoenix"
	end
	local item = ShopCatalog.getItem(itemId)
	if not item then
		return nil, nil
	end
	if item.grantCharacter then
		return item.grantCharacter, "base"
	end
	if item.grantSkins and item.grantSkins[1] then
		local pair = item.grantSkins[1]
		return pair.heroId, pair.skinId
	end
	return nil, nil
end

function ShopCatalog.getItems(): { ShopItem }
	return ITEMS
end

function ShopCatalog.getItem(id: string): ShopItem?
	for _, item in ITEMS do
		if item.id == id then
			return item
		end
	end
	return nil
end

function ShopCatalog.getCoinPacks(): { CoinPack }
	return ShopCatalog.COIN_PACKS
end

function ShopCatalog.getCoinPackByProductId(productId: number): CoinPack?
	for _, pack in ShopCatalog.COIN_PACKS do
		if pack.productId == productId then
			return pack
		end
	end
	return nil
end

function ShopCatalog.isFreeCharacter(heroId: string): boolean
	for _, id in ShopCatalog.FREE_CHARACTERS do
		if id == heroId then
			return true
		end
	end
	return false
end

function ShopCatalog.getDefaultProfile(): { [string]: any }
	local ownedCharacters: { string } = {}
	for _, id in ShopCatalog.FREE_CHARACTERS do
		table.insert(ownedCharacters, id)
	end
	local ownedSkins: { [string]: { string } } = {}
	for heroId, skins in ShopCatalog.DEFAULT_OWNED_SKINS do
		ownedSkins[heroId] = table.clone(skins)
	end
	return {
		coins = 0,
		kills = 0,
		ownedCharacters = ownedCharacters,
		ownedSkins = ownedSkins,
		ownedBundles = {},
		hasEliteGamepass = false,
		redeemedCodes = {},
	}
end

function ShopCatalog.ownsCharacter(profile: { [string]: any }, heroId: string): boolean
	if ShopCatalog.UNLOCK_ALL then
		return true
	end
	if ShopCatalog.isFreeCharacter(heroId) then
		return true
	end
	local owned = profile.ownedCharacters
	if type(owned) ~= "table" then
		return false
	end
	for _, id in owned do
		if id == heroId then
			return true
		end
	end
	return false
end

function ShopCatalog.ownsBundle(profile: { [string]: any }, bundleId: string): boolean
	local owned = profile.ownedBundles
	if type(owned) ~= "table" then
		return false
	end
	for _, id in owned do
		if id == bundleId then
			return true
		end
	end
	return false
end

function ShopCatalog.ownsSkin(profile: { [string]: any }, heroId: string, skinId: string): boolean
	if ShopCatalog.UNLOCK_ALL then
		return true
	end
	if skinId == "base" then
		return ShopCatalog.ownsCharacter(profile, heroId)
	end
	local ownedSkins = profile.ownedSkins
	if type(ownedSkins) == "table" then
		local list = ownedSkins[heroId]
		if type(list) == "table" then
			for _, id in list do
				if id == skinId then
					return true
				end
			end
		end
	end
	if ShopCatalog.ownsBundle(profile, ShopCatalog.MODERN_BUNDLE_ID) then
		for _, pair in ShopCatalog.MODERN_BUNDLE_SKINS do
			if pair.heroId == heroId and pair.skinId == skinId then
				return true
			end
		end
	end
	return false
end

function ShopCatalog.canDeploy(profile: { [string]: any }, heroId: string, skinId: string): boolean
	if not ShopCatalog.ownsCharacter(profile, heroId) then
		return false
	end
	return ShopCatalog.ownsSkin(profile, heroId, skinId)
end

function ShopCatalog.getDamageBuffMultiplier(profile: { [string]: any }, heroId: string, skinId: string): number
	local mult = 1
	if heroId == "jean_grey" and skinId == "marvel_girl" and ShopCatalog.ownsSkin(profile, heroId, skinId) then
		mult *= ShopCatalog.MARVEL_GIRL_BUFF
	end
	if skinId == "modern" and ShopCatalog.ownsSkin(profile, heroId, skinId) then
		if heroId == "human_torch" or heroId == "invisible_woman" then
			mult *= ShopCatalog.MODERN_COSTUME_BUFF
		end
	end
	return mult
end

return ShopCatalog
