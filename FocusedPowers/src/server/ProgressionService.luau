--!strict
--[[
	Player level, XP, and coins. DataStore-backed with in-session cache.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProgressionConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ProgressionConstants"))

export type PlayerProgress = {
	Level: number,
	XP: number,
	Coins: number,
}

local DATA_STORE_NAME = "FocusedPowersProgression_v1"

type CachedProgress = PlayerProgress & {
	redeemedCodes: { [string]: boolean },
}

local ProgressionService = {}

local store = DataStoreService:GetDataStore(DATA_STORE_NAME)
local cache: { [Player]: CachedProgress } = {}
local holdXpTimers: { [Player]: number } = {}
local loadedPlayers: { [Player]: boolean } = {}

local REDEEM_CODES: { [string]: number } = {
	PSIONIC = 250,
	FOCUSED = 100,
}

local function defaultProgress(): CachedProgress
	return {
		Level = ProgressionConstants.STARTING_LEVEL,
		XP = ProgressionConstants.STARTING_XP,
		Coins = ProgressionConstants.STARTING_COINS,
		redeemedCodes = {},
	}
end

local function syncAttributes(plr: Player, data: CachedProgress)
	plr:SetAttribute("Level", data.Level)
	plr:SetAttribute("XP", data.XP)
	plr:SetAttribute("XpToNextLevel", ProgressionConstants.xpToNextLevel(data.Level))
	plr:SetAttribute("Coins", data.Coins)
end

local function loadProgress(plr: Player): CachedProgress
	local key = "p_" .. plr.UserId
	local ok, saved = pcall(function()
		return store:GetAsync(key)
	end)

	local data = defaultProgress()
	if ok and typeof(saved) == "table" then
		if typeof(saved.Level) == "number" then
			data.Level = math.max(1, math.floor(saved.Level))
		end
		if typeof(saved.XP) == "number" then
			data.XP = math.max(0, math.floor(saved.XP))
		end
		if typeof(saved.Coins) == "number" then
			data.Coins = math.max(0, math.floor(saved.Coins))
		end
		if typeof(saved.redeemedCodes) == "table" then
			data.redeemedCodes = saved.redeemedCodes
		end
	end

	while data.XP >= ProgressionConstants.xpToNextLevel(data.Level) do
		data.XP -= ProgressionConstants.xpToNextLevel(data.Level)
		data.Level += 1
	end

	return data
end

local function ensureLoaded(plr: Player)
	if loadedPlayers[plr] then
		return
	end
	loadedPlayers[plr] = true
	cache[plr] = loadProgress(plr)
	syncAttributes(plr, cache[plr])
end

local function saveProgress(plr: Player)
	local data = cache[plr]
	if not data then
		return
	end
	local key = "p_" .. plr.UserId
	pcall(function()
		store:SetAsync(key, {
			Level = data.Level,
			XP = data.XP,
			Coins = data.Coins,
			redeemedCodes = data.redeemedCodes,
		})
	end)
end

function ProgressionService.grantXp(plr: Player, amount: number)
	if amount <= 0 then
		return
	end
	local data = cache[plr]
	if not data then
		return
	end

	data.XP += amount
	while data.XP >= ProgressionConstants.xpToNextLevel(data.Level) do
		data.XP -= ProgressionConstants.xpToNextLevel(data.Level)
		data.Level += 1
	end
	syncAttributes(plr, data)
end

function ProgressionService.grantAbilityXp(plr: Player, abilityId: string, action: string)
	local rewards = ProgressionConstants.ABILITY_XP[abilityId]
	if not rewards then
		return
	end
	local amount = rewards[action]
	if typeof(amount) == "number" and amount > 0 then
		ProgressionService.grantXp(plr, amount)
	end
end

function ProgressionService.tickAbilityHold(plr: Player, abilityId: string, dt: number)
	local rewards = ProgressionConstants.ABILITY_XP[abilityId]
	if not rewards or typeof(rewards.holdPerSecond) ~= "number" then
		return
	end
	local perSec = rewards.holdPerSecond
	local acc = (holdXpTimers[plr] or 0) + dt
	if acc >= 1 then
		local whole = math.floor(acc)
		holdXpTimers[plr] = acc - whole
		ProgressionService.grantXp(plr, whole * perSec)
	else
		holdXpTimers[plr] = acc
	end
end

function ProgressionService.clearHoldTimer(plr: Player)
	holdXpTimers[plr] = nil
end

function ProgressionService.redeemCode(plr: Player, rawCode: unknown): (boolean, string)
	if typeof(rawCode) ~= "string" then
		return false, "Invalid code."
	end
	local code = string.upper(string.gsub(rawCode, "%s+", ""))
	if code == "" then
		return false, "Enter a code."
	end

	local reward = REDEEM_CODES[code]
	if not reward then
		return false, "Code not found."
	end

	local data = cache[plr]
	if not data then
		return false, "Progress not loaded."
	end
	if data.redeemedCodes[code] then
		return false, "Code already redeemed."
	end

	data.redeemedCodes[code] = true
	data.Coins += reward
	syncAttributes(plr, data)
	return true, string.format("Redeemed! +%d coins.", reward)
end

function ProgressionService.setup(redeemCodeRemote: RemoteEvent)
	redeemCodeRemote.OnServerEvent:Connect(function(plr: Player, code: unknown)
		local ok, message = ProgressionService.redeemCode(plr, code)
		redeemCodeRemote:FireClient(plr, ok, message)
	end)

	Players.PlayerAdded:Connect(function(plr)
		ensureLoaded(plr)
	end)

	Players.PlayerRemoving:Connect(function(plr)
		saveProgress(plr)
		cache[plr] = nil
		holdXpTimers[plr] = nil
		loadedPlayers[plr] = nil
	end)

	for _, plr in Players:GetPlayers() do
		ensureLoaded(plr)
	end

	game:BindToClose(function()
		for plr in pairs(cache) do
			saveProgress(plr)
		end
	end)
end

return ProgressionService
