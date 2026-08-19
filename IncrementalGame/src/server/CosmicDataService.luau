local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local CosmicConfig = require(Shared:WaitForChild("CosmicConfig"))

local CosmicGameService = require(script.Parent:WaitForChild("CosmicGameService"))

local CosmicDataService = {}

local DATASTORE_NAME = "SuperpowerIncremental_v1"
local playerDataStore = DataStoreService:GetDataStore(DATASTORE_NAME)
local playerLoaded: { [Player]: boolean } = {}
local dataStoreEnabled = true
local studioNoticeShown = false

type SavedData = {
	Power: number,
	LifetimePower: number,
	OwnedGenerators: { [string]: boolean },
	MultiplierLevels: { [string]: number },
	Ascensions: number,
	OwnedPowers: { [string]: boolean },
	EquippedPowers: { string },
	LastSaveUnix: number,
}

local function makeSaveKey(player: Player): string
	return ("u_%d"):format(player.UserId)
end

local function sanitizeNumber(value: any, defaultValue: number): number
	if type(value) ~= "number" then
		return defaultValue
	end
	return math.max(0, math.floor(value))
end

local function sanitizeBoolMap(value: any): { [string]: boolean }
	local result: { [string]: boolean } = {}
	if type(value) ~= "table" then
		return result
	end

	for key, owned in value do
		if type(key) == "string" and owned == true then
			result[key] = true
		end
	end
	return result
end

local function sanitizeNumberMap(value: any): { [string]: number }
	local result: { [string]: number } = {}
	if type(value) ~= "table" then
		return result
	end

	for key, level in value do
		if type(key) == "string" and type(level) == "number" then
			result[key] = math.max(0, math.floor(level))
		end
	end
	return result
end

local function sanitizeStringList(value: any): { string }
	local result: { string } = {}
	if type(value) ~= "table" then
		return result
	end
	for _, entry in value do
		if type(entry) == "string" then
			table.insert(result, entry)
		end
	end
	return result
end

local function decodeSaveData(raw: any): SavedData?
	if type(raw) ~= "table" then
		return nil
	end

	return {
		Power = sanitizeNumber(raw.Power or raw.Stardust, CosmicConfig.StartingPower),
		LifetimePower = sanitizeNumber(raw.LifetimePower or raw.LifetimeStardust, 0),
		OwnedGenerators = sanitizeBoolMap(raw.OwnedGenerators),
		MultiplierLevels = sanitizeNumberMap(raw.MultiplierLevels),
		Ascensions = sanitizeNumber(raw.Ascensions or raw.Rebirths, 0),
		OwnedPowers = sanitizeBoolMap(raw.OwnedPowers),
		EquippedPowers = sanitizeStringList(raw.EquippedPowers),
		LastSaveUnix = sanitizeNumber(raw.LastSaveUnix, os.time()),
	}
end

local function encodeSaveData(state: CosmicConfig.PlayerState): SavedData
	return {
		Power = state.Power,
		LifetimePower = state.LifetimePower,
		OwnedGenerators = state.OwnedGenerators,
		MultiplierLevels = state.MultiplierLevels,
		Ascensions = state.Ascensions,
		OwnedPowers = state.OwnedPowers,
		EquippedPowers = state.EquippedPowers,
		LastSaveUnix = os.time(),
	}
end

local function isStudioApiBlocked(err: any): boolean
	local message = string.lower(tostring(err))
	return string.find(message, "studio access", 1, true) ~= nil
		or string.find(message, "studioaccesstoapisnotallowed", 1, true) ~= nil
end

local function disableStudioDataStore(reason: string?)
	dataStoreEnabled = false
	if studioNoticeShown then
		return
	end
	studioNoticeShown = true
	print(
		"[SuperpowerData] Saves skipped in Studio"
			.. (if reason then (": " .. reason) else "")
			.. ". Enable Game Settings → Security → Studio Access to API Services to test saves."
	)
end

local function probeDataStoreAccess()
	if not RunService:IsStudio() then
		return
	end

	local ok, err = pcall(function()
		playerDataStore:GetAsync("__studio_access_probe__")
	end)

	if ok then
		return
	end

	if isStudioApiBlocked(err) then
		disableStudioDataStore(nil)
	end
end

local function readData(player: Player): SavedData?
	if not dataStoreEnabled then
		return nil
	end

	local key = makeSaveKey(player)
	local success, result = pcall(function()
		return playerDataStore:GetAsync(key)
	end)

	if not success then
		if isStudioApiBlocked(result) then
			disableStudioDataStore(nil)
			return nil
		end
		warn(("[SuperpowerData] Load failed for %s: %s"):format(player.Name, tostring(result)))
		return nil
	end

	return decodeSaveData(result)
end

local function writeData(player: Player): boolean
	if not dataStoreEnabled then
		return false
	end

	local state = CosmicGameService.GetStateForSave(player)
	if not state then
		return false
	end

	local key = makeSaveKey(player)
	local payload = encodeSaveData(state)

	local success, err = pcall(function()
		playerDataStore:SetAsync(key, payload)
	end)

	if not success then
		if isStudioApiBlocked(err) then
			disableStudioDataStore(nil)
			return false
		end
		warn(("[SuperpowerData] Save failed for %s: %s"):format(player.Name, tostring(err)))
	end

	return success
end

local function computeOfflineBonus(saved: SavedData): number
	local lastSave = saved.LastSaveUnix
	if lastSave <= 0 then
		return 0
	end

	local elapsed = math.max(0, os.time() - lastSave)
	local cappedSeconds = math.min(elapsed, CosmicConfig.OfflineCapSeconds)

	local offlineState: CosmicConfig.PlayerState = {
		Power = saved.Power,
		LifetimePower = saved.LifetimePower,
		OwnedGenerators = saved.OwnedGenerators,
		MultiplierLevels = saved.MultiplierLevels,
		Ascensions = saved.Ascensions,
		OwnedPowers = saved.OwnedPowers,
		EquippedPowers = saved.EquippedPowers,
		LastSaveUnix = saved.LastSaveUnix,
	}

	local rate = CosmicConfig.GetPowerPerSecond(offlineState)
	return math.floor(rate * cappedSeconds)
end

local function loadPlayer(player: Player)
	task.wait(0.1)

	local saved = readData(player)
	if not saved then
		playerLoaded[player] = true
		return
	end

	local offlineBonus = computeOfflineBonus(saved)
	local loadedState: CosmicConfig.PlayerState = {
		Power = saved.Power,
		LifetimePower = saved.LifetimePower,
		OwnedGenerators = saved.OwnedGenerators,
		MultiplierLevels = saved.MultiplierLevels,
		Ascensions = saved.Ascensions,
		OwnedPowers = saved.OwnedPowers,
		EquippedPowers = saved.EquippedPowers,
		LastSaveUnix = saved.LastSaveUnix,
	}

	CosmicGameService.ApplyLoadedState(player, loadedState, offlineBonus)
	playerLoaded[player] = true
end

local function onPlayerAdded(player: Player)
	playerLoaded[player] = false
	task.spawn(loadPlayer, player)
end

local function onPlayerRemoving(player: Player)
	if playerLoaded[player] then
		writeData(player)
	end
	playerLoaded[player] = nil
end

function CosmicDataService.Init()
	probeDataStoreAccess()

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	task.spawn(function()
		while true do
			task.wait(60)
			for player, loaded in playerLoaded do
				if loaded then
					writeData(player)
				end
			end
		end
	end)

	game:BindToClose(function()
		for player, loaded in playerLoaded do
			if loaded then
				writeData(player)
			end
		end
	end)
end

return CosmicDataService
