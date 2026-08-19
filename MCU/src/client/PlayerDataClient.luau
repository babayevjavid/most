--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConstants = require(ReplicatedStorage.Shared.GameConstants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ShopCatalog = require(ReplicatedStorage.Shared.ShopCatalog)

export type PlayerProfile = {
	coins: number,
	kills: number,
	ownedCharacters: { string },
	ownedSkins: { [string]: { string } },
	ownedBundles: { string },
	hasEliteGamepass: boolean,
	redeemedCodes: { string },
}

local PlayerDataClient = {}

local profile: PlayerProfile? = nil
local listeners: { () -> () } = {}

local function defaultProfile(): PlayerProfile
	local raw = ShopCatalog.getDefaultProfile()
	return {
		coins = raw.coins,
		kills = raw.kills,
		ownedCharacters = table.clone(raw.ownedCharacters),
		ownedSkins = {},
		ownedBundles = table.clone(raw.ownedBundles),
		hasEliteGamepass = raw.hasEliteGamepass,
		redeemedCodes = table.clone(raw.redeemedCodes),
	}
end

local function notify()
	for _, fn in listeners do
		task.spawn(fn)
	end
end

function PlayerDataClient.onChanged(fn: () -> ())
	table.insert(listeners, fn)
end

function PlayerDataClient.getProfile(): PlayerProfile?
	return profile
end

function PlayerDataClient.getCoins(): number
	if profile then
		return profile.coins
	end
	local player = Players.LocalPlayer
	local attr = player:GetAttribute(GameConstants.COINS_ATTRIBUTE)
	if type(attr) == "number" then
		return attr
	end
	return 0
end

function PlayerDataClient.getKills(): number
	if profile then
		return profile.kills
	end
	local player = Players.LocalPlayer
	local attr = player:GetAttribute(GameConstants.KILLS_ATTRIBUTE)
	if type(attr) == "number" then
		return attr
	end
	return 0
end

function PlayerDataClient.isReady(): boolean
	return profile ~= nil
end

function PlayerDataClient.ownsCharacter(heroId: string): boolean
	if ShopCatalog.UNLOCK_ALL then
		return true
	end
	if profile then
		return ShopCatalog.ownsCharacter(profile, heroId)
	end
	return ShopCatalog.isFreeCharacter(heroId)
end

function PlayerDataClient.ownsSkin(heroId: string, skinId: string): boolean
	if ShopCatalog.UNLOCK_ALL then
		return true
	end
	if profile then
		return ShopCatalog.ownsSkin(profile, heroId, skinId)
	end
	return skinId == "base" and ShopCatalog.isFreeCharacter(heroId)
end

function PlayerDataClient.ownsShopItem(itemId: string): boolean
	local item = ShopCatalog.getItem(itemId)
	local p = profile
	if not item or not p then
		return false
	end
	if item.kind == "gamepass" and p.hasEliteGamepass then
		return true
	end
	if item.grantCharacter and ShopCatalog.ownsCharacter(p, item.grantCharacter) then
		if item.kind == "character" or item.kind == "devproduct" then
			return true
		end
	end
	if item.grantBundle and ShopCatalog.ownsBundle(p, item.grantBundle) then
		return true
	end
	if item.grantSkins then
		for _, pair in item.grantSkins do
			if not ShopCatalog.ownsSkin(p, pair.heroId, pair.skinId) then
				return false
			end
		end
		return true
	end
	return false
end

local function applyPayload(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local nextProfile = defaultProfile()
	if type(payload.coins) == "number" then
		nextProfile.coins = math.max(0, math.floor(payload.coins))
	end
	if type(payload.kills) == "number" then
		nextProfile.kills = math.max(0, math.floor(payload.kills))
	end
	if type(payload.ownedCharacters) == "table" then
		nextProfile.ownedCharacters = {}
		for _, id in payload.ownedCharacters do
			if type(id) == "string" then
				table.insert(nextProfile.ownedCharacters, id)
			end
		end
	end
	if type(payload.ownedSkins) == "table" then
		nextProfile.ownedSkins = {}
		for heroId, skins in payload.ownedSkins do
			if type(heroId) == "string" and type(skins) == "table" then
				local list: { string } = {}
				for _, skinId in skins do
					if type(skinId) == "string" then
						table.insert(list, skinId)
					end
				end
				nextProfile.ownedSkins[heroId] = list
			end
		end
	end
	if type(payload.ownedBundles) == "table" then
		nextProfile.ownedBundles = {}
		for _, id in payload.ownedBundles do
			if type(id) == "string" then
				table.insert(nextProfile.ownedBundles, id)
			end
		end
	end
	if payload.hasEliteGamepass == true then
		nextProfile.hasEliteGamepass = true
	end
	profile = nextProfile
	notify()
end

function PlayerDataClient.init(player: Player)
	Remotes.getEvent("PlayerDataSync").OnClientEvent:Connect(applyPayload)
	player:GetAttributeChangedSignal(GameConstants.COINS_ATTRIBUTE):Connect(notify)
	player:GetAttributeChangedSignal(GameConstants.KILLS_ATTRIBUTE):Connect(notify)
end

return PlayerDataClient
