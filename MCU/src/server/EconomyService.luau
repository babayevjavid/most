--!strict
--[[ Kill coin rewards and humanoid death hooks. ]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConstants = require(ReplicatedStorage.Shared.GameConstants)
local ShopCatalog = require(ReplicatedStorage.Shared.ShopCatalog)
local PlayerDataService = require(script.Parent.PlayerDataService)

local EconomyService = {}

local deathHooked: { [Humanoid]: boolean } = {}

local function coinRewardFor(killer: Player): number
	local base = ShopCatalog.KILL_COIN_REWARD
	if PlayerDataService.hasElite(killer) then
		return base * ShopCatalog.ELITE_COIN_MULT
	end
	return base
end

local function resolveKiller(victim: Model): Player?
	local userId = victim:GetAttribute(GameConstants.LAST_DAMAGER_USER_ID_ATTRIBUTE)
	if type(userId) ~= "number" then
		return nil
	end
	local killer = Players:GetPlayerByUserId(userId)
	if not killer or not killer.Character then
		return nil
	end
	if killer.Character == victim then
		return nil
	end
	if killer.Character:GetAttribute(GameConstants.HERO_ATTRIBUTE) == nil then
		return nil
	end
	return killer
end

local function onHumanoidDied(victim: Model, _humanoid: Humanoid)
	local killer = resolveKiller(victim)
	if not killer then
		return
	end
	local reward = coinRewardFor(killer)
	PlayerDataService.addCoins(killer, reward)
	PlayerDataService.addKill(killer)
	victim:SetAttribute(GameConstants.LAST_DAMAGER_USER_ID_ATTRIBUTE, nil)
end

local function hookHumanoid(model: Model, humanoid: Humanoid)
	if deathHooked[humanoid] then
		return
	end
	if model.Name == "FearClone" or model:GetAttribute("FearVisual") == true then
		return
	end
	deathHooked[humanoid] = true
	humanoid.Died:Connect(function()
		onHumanoidDied(model, humanoid)
	end)
	humanoid.Destroying:Connect(function()
		deathHooked[humanoid] = nil
	end)
end

local function tryHook(model: Model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		hookHumanoid(model, humanoid)
	end
end

function EconomyService.init()
	for _, player in Players:GetPlayers() do
		player.CharacterAdded:Connect(tryHook)
		if player.Character then
			tryHook(player.Character)
		end
	end
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(tryHook)
	end)

	for _, desc in Workspace:GetDescendants() do
		if desc:IsA("Model") and desc:FindFirstChildOfClass("Humanoid") then
			tryHook(desc)
		end
	end

	Workspace.DescendantAdded:Connect(function(desc)
		if desc:IsA("Humanoid") then
			local model = desc.Parent
			if model and model:IsA("Model") then
				task.defer(function()
					tryHook(model)
				end)
			end
		end
	end)
end

return EconomyService
