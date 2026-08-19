local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local shared = ReplicatedStorage:WaitForChild("Shared", 30)
if not shared then
	error("[Belthazor] Shared missing.")
end

local configModule = shared:WaitForChild("CharacterConfig", 10)
local ok, CharacterConfig = pcall(require, configModule)
if not ok or type(CharacterConfig) ~= "table" then
	error("[Belthazor] CharacterConfig required.")
end

local ghMod = shared:WaitForChild("GameHealth", 10)
local ghOk, GameHealth = pcall(require, ghMod)
if not ghOk or type(GameHealth) ~= "table" then
	error("[Belthazor] GameHealth required.")
end

local coreMod = shared:WaitForChild("BelthazorVanquishCore", 10)
local okCore, VanquishCore = pcall(require, coreMod)
if not okCore or type(VanquishCore) ~= "table" or type(VanquishCore.tryVanquishFromWitchPlayer) ~= "function" then
	error("[Belthazor] BelthazorVanquishCore required.")
end

local PHRASE = string.lower(CharacterConfig.BelthazorVanquishSubstring or "vanquish belthazor")
local BELTH_MAX = (CharacterConfig :: any).BelthazorCombatHealth
if type(BELTH_MAX) ~= "number" then
	BELTH_MAX = 400
end

local validWitch: { [string]: boolean } = {}
for _, name in CharacterConfig.Choices do
	validWitch[name] = true
end

local TAG = CharacterConfig.BelthazorTagName or "Belthazor"

local function initBelthazorInstance(inst: Instance)
	if not inst:IsA("Model") then
		return
	end
	local hum = inst:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	GameHealth.initCharacter(inst, BELTH_MAX)
end

local function bindChatter(player: Player)
	player.Chatted:Connect(function(message: string)
		if type(message) ~= "string" then
			return
		end
		local chosen = player:GetAttribute("ChosenCharacter")
		if type(chosen) ~= "string" or chosen == "" or not validWitch[chosen] then
			return
		end
		if chosen == "Belthazor" then
			return
		end
		local lower = string.lower(message)
		if not string.find(lower, PHRASE, 1, true) then
			return
		end

		VanquishCore.tryVanquishFromWitchPlayer(player, CharacterConfig, GameHealth)
	end)
end

for _, inst in CollectionService:GetTagged(TAG) do
	initBelthazorInstance(inst)
end

CollectionService:GetInstanceAddedSignal(TAG):Connect(function(inst)
	initBelthazorInstance(inst)
end)

Players.PlayerAdded:Connect(bindChatter)
for _, plr in Players:GetPlayers() do
	bindChatter(plr)
end
