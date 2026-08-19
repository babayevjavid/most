--!strict
--[[ Player profile persistence: coins, kills, unlocks, Elite gamepass. ]]

local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
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

local PlayerDataService = {}

local STORE = DataStoreService:GetDataStore("MCU_PlayerData_v1")
local profiles: { [Player]: PlayerProfile } = {}
local loading: { [Player]: boolean } = {}

local function cloneDefault(): PlayerProfile
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

local function cloneSkinMap(source: { [string]: { string } }): { [string]: { string } }
	local out: { [string]: { string } } = {}
	for heroId, skins in source do
		out[heroId] = table.clone(skins)
	end
	return out
end

local function normalizeProfile(raw: any): PlayerProfile
	local profile = cloneDefault()
	if type(raw) ~= "table" then
		return profile
	end
	if type(raw.coins) == "number" then
		profile.coins = math.max(0, math.floor(raw.coins))
	end
	if type(raw.kills) == "number" then
		profile.kills = math.max(0, math.floor(raw.kills))
	end
	if type(raw.ownedCharacters) == "table" then
		profile.ownedCharacters = {}
		for _, id in raw.ownedCharacters do
			if type(id) == "string" then
				table.insert(profile.ownedCharacters, id)
			end
		end
	end
	if type(raw.ownedSkins) == "table" then
		profile.ownedSkins = {}
		for heroId, skins in raw.ownedSkins do
			if type(heroId) == "string" and type(skins) == "table" then
				local list: { string } = {}
				for _, skinId in skins do
					if type(skinId) == "string" then
						table.insert(list, skinId)
					end
				end
				profile.ownedSkins[heroId] = list
			end
		end
	end
	if type(raw.ownedBundles) == "table" then
		profile.ownedBundles = {}
		for _, id in raw.ownedBundles do
			if type(id) == "string" then
				table.insert(profile.ownedBundles, id)
			end
		end
	end
	if raw.hasEliteGamepass == true then
		profile.hasEliteGamepass = true
	end
	if type(raw.redeemedCodes) == "table" then
		profile.redeemedCodes = {}
		for _, code in raw.redeemedCodes do
			if type(code) == "string" then
				table.insert(profile.redeemedCodes, code)
			end
		end
	end
	for heroId, skins in ShopCatalog.DEFAULT_OWNED_SKINS do
		if not profile.ownedSkins[heroId] then
			profile.ownedSkins[heroId] = table.clone(skins)
		end
	end
	for _, heroId in ShopCatalog.FREE_CHARACTERS do
		if not table.find(profile.ownedCharacters, heroId) then
			table.insert(profile.ownedCharacters, heroId)
		end
	end
	return profile
end

local function encodeProfile(profile: PlayerProfile): { [string]: any }
	return {
		coins = profile.coins,
		kills = profile.kills,
		ownedCharacters = table.clone(profile.ownedCharacters),
		ownedSkins = cloneSkinMap(profile.ownedSkins),
		ownedBundles = table.clone(profile.ownedBundles),
		hasEliteGamepass = profile.hasEliteGamepass,
		redeemedCodes = table.clone(profile.redeemedCodes),
	}
end

function PlayerDataService.getProfile(player: Player): PlayerProfile?
	return profiles[player]
end

function PlayerDataService.waitForProfile(player: Player, timeout: number?): PlayerProfile?
	local limit = timeout or 12
	local start = os.clock()
	while not profiles[player] and os.clock() - start < limit do
		if not player.Parent then
			return nil
		end
		task.wait(0.1)
	end
	return profiles[player]
end

local function pushToClient(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	player:SetAttribute(GameConstants.COINS_ATTRIBUTE, profile.coins)
	player:SetAttribute(GameConstants.KILLS_ATTRIBUTE, profile.kills)
	player:SetAttribute(GameConstants.ELITE_TITLE_ATTRIBUTE, if profile.hasEliteGamepass then true else nil)
	Remotes.getEvent("PlayerDataSync"):FireClient(player, encodeProfile(profile))
end

function PlayerDataService.sync(player: Player)
	pushToClient(player)
end

function PlayerDataService.addCoins(player: Player, amount: number)
	local profile = profiles[player]
	if not profile or amount <= 0 then
		return
	end
	profile.coins += math.floor(amount)
	pushToClient(player)
end

function PlayerDataService.grantCoinPack(player: Player, productId: number): boolean
	local pack = ShopCatalog.getCoinPackByProductId(productId)
	if not pack then
		return false
	end
	PlayerDataService.addCoins(player, pack.amount)
	return true
end

function PlayerDataService.addKill(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	profile.kills += 1
	pushToClient(player)
end

function PlayerDataService.ownsCharacter(player: Player, heroId: string): boolean
	if ShopCatalog.UNLOCK_ALL then
		return true
	end
	local profile = profiles[player]
	if not profile then
		return ShopCatalog.isFreeCharacter(heroId)
	end
	return ShopCatalog.ownsCharacter(profile, heroId)
end

function PlayerDataService.ownsSkin(player: Player, heroId: string, skinId: string): boolean
	if ShopCatalog.UNLOCK_ALL then
		return true
	end
	local profile = profiles[player]
	if not profile then
		return skinId == "base" and ShopCatalog.isFreeCharacter(heroId)
	end
	return ShopCatalog.ownsSkin(profile, heroId, skinId)
end

function PlayerDataService.canDeploy(player: Player, heroId: string, skinId: string): boolean
	if ShopCatalog.UNLOCK_ALL then
		return true
	end
	local profile = profiles[player]
	if not profile then
		return false
	end
	return ShopCatalog.canDeploy(profile, heroId, skinId)
end

function PlayerDataService.getDamageBuff(player: Player, heroId: string, skinId: string): number
	local profile = profiles[player]
	if not profile then
		return 1
	end
	return ShopCatalog.getDamageBuffMultiplier(profile, heroId, skinId)
end

function PlayerDataService.hasElite(player: Player): boolean
	local profile = profiles[player]
	return profile ~= nil and profile.hasEliteGamepass == true
end

local function grantSkin(profile: PlayerProfile, heroId: string, skinId: string)
	if not profile.ownedSkins[heroId] then
		profile.ownedSkins[heroId] = {}
	end
	if not table.find(profile.ownedSkins[heroId], skinId) then
		table.insert(profile.ownedSkins[heroId], skinId)
	end
end

local function grantShopItem(profile: PlayerProfile, itemId: string): boolean
	local item = ShopCatalog.getItem(itemId)
	if not item then
		return false
	end
	if item.grantCharacter and not table.find(profile.ownedCharacters, item.grantCharacter) then
		table.insert(profile.ownedCharacters, item.grantCharacter)
	end
	if item.grantSkins then
		for _, pair in item.grantSkins do
			grantSkin(profile, pair.heroId, pair.skinId)
		end
	end
	if item.grantBundle and not table.find(profile.ownedBundles, item.grantBundle) then
		table.insert(profile.ownedBundles, item.grantBundle)
	end
	if item.kind == "gamepass" and item.id == "elite_gamepass" then
		profile.hasEliteGamepass = true
	end
	return true
end

function PlayerDataService.alreadyOwnsItem(player: Player, itemId: string): boolean
	local profile = profiles[player]
	local item = ShopCatalog.getItem(itemId)
	if not profile or not item then
		return false
	end
	if item.kind == "gamepass" and profile.hasEliteGamepass then
		return true
	end
	if item.grantCharacter and ShopCatalog.ownsCharacter(profile, item.grantCharacter) then
		return true
	end
	if item.grantBundle and ShopCatalog.ownsBundle(profile, item.grantBundle) then
		return true
	end
	if item.grantSkins then
		local allOwned = true
		for _, pair in item.grantSkins do
			if not ShopCatalog.ownsSkin(profile, pair.heroId, pair.skinId) then
				allOwned = false
				break
			end
		end
		if allOwned then
			return true
		end
	end
	return false
end

function PlayerDataService.tryPurchaseCoins(player: Player, itemId: string): (boolean, string?)
	local profile = profiles[player]
	local item = ShopCatalog.getItem(itemId)
	if not profile or not item then
		return false, "Unknown item"
	end
	if item.currency ~= "coins" then
		return false, "Use Robux purchase"
	end
	if PlayerDataService.alreadyOwnsItem(player, itemId) then
		return false, "Already owned"
	end
	if profile.coins < item.price then
		return false, "Not enough tokens"
	end
	profile.coins -= item.price
	grantShopItem(profile, itemId)
	pushToClient(player)
	return true, nil
end

function PlayerDataService.grantDevProduct(player: Player, itemId: string): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end
	if PlayerDataService.alreadyOwnsItem(player, itemId) then
		return true
	end
	grantShopItem(profile, itemId)
	pushToClient(player)
	return true
end

function PlayerDataService.refreshEliteGamepass(player: Player)
	PlayerDataService.refreshGamepasses(player)
end

function PlayerDataService.refreshGamepasses(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	local changed = false
	local function ownsPass(passId: number): boolean
		if passId <= 0 then
			return false
		end
		local ok, owns = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
		end)
		return ok and owns == true
	end
	if ownsPass(ShopCatalog.ELITE_GAMEPASS_ID) and not profile.hasEliteGamepass then
		profile.hasEliteGamepass = true
		changed = true
	end
	if ownsPass(ShopCatalog.PHOENIX_GAMEPASS_ID) then
		if not ShopCatalog.ownsSkin(profile, "jean_grey", "phoenix") then
			if not profile.ownedSkins["jean_grey"] then
				profile.ownedSkins["jean_grey"] = { "base" }
			end
			if not table.find(profile.ownedSkins["jean_grey"], "phoenix") then
				table.insert(profile.ownedSkins["jean_grey"], "phoenix")
				changed = true
			end
		end
	end
	if ownsPass(ShopCatalog.ROGUE_GAMEPASS_ID) then
		if not table.find(profile.ownedCharacters, "rogue") then
			table.insert(profile.ownedCharacters, "rogue")
			changed = true
		end
	end
	if changed then
		pushToClient(player)
	end
end

local function loadProfile(player: Player)
	if loading[player] then
		return
	end
	loading[player] = true
	local profile = cloneDefault()
	local ok, data = pcall(function()
		return STORE:GetAsync(tostring(player.UserId))
	end)
	if ok then
		profile = normalizeProfile(data)
	else
		warn("[PlayerDataService] Load failed for", player.Name, data)
	end
	profiles[player] = profile
	loading[player] = nil
	PlayerDataService.refreshEliteGamepass(player)
	pushToClient(player)
end

local function saveProfile(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	local payload = encodeProfile(profile)
	local ok, err = pcall(function()
		STORE:SetAsync(tostring(player.UserId), payload)
	end)
	if not ok then
		warn("[PlayerDataService] Save failed for", player.Name, err)
	end
end

function PlayerDataService.init()
	MarketplaceService.ProcessReceipt = function(receiptInfo)
		local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
		if not player then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		local ok = PlayerDataService.grantCoinPack(player, receiptInfo.ProductId)
		if ok then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	Remotes.getEvent("PurchaseShopItem").OnServerEvent:Connect(function(player: Player, itemId: any)
		if type(itemId) ~= "string" then
			return
		end
		local item = ShopCatalog.getItem(itemId)
		if not item then
			return
		end
		if item.currency == "coins" then
			local ok, err = PlayerDataService.tryPurchaseCoins(player, itemId)
			Remotes.getEvent("ShopPurchaseResult"):FireClient(player, {
				itemId = itemId,
				success = ok,
				error = err,
			})
		end
	end)

	Remotes.getEvent("RefreshPlayerData").OnServerEvent:Connect(function(player: Player)
		PlayerDataService.refreshGamepasses(player)
		pushToClient(player)
	end)

	Players.PlayerAdded:Connect(function(player)
		task.spawn(loadProfile, player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		saveProfile(player)
		profiles[player] = nil
		loading[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(loadProfile, player)
	end
	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			saveProfile(player)
		end
	end)
end

return PlayerDataService
