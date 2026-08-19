--!strict
--[[ Tracks combat from any health loss (players + NPCs) and clears the InCombat flag. ]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatHelper = require(ReplicatedStorage.Shared.CombatHelper)

local CombatService = {}

local hooked: { [Humanoid]: RBXScriptConnection } = {}
local lastHealth: { [Humanoid]: number } = {}

local function hookHumanoid(model: Model, humanoid: Humanoid)
	if hooked[humanoid] then
		return
	end
	if model.Name == "FearClone" or model:GetAttribute("FearVisual") == true then
		return
	end

	lastHealth[humanoid] = humanoid.Health
	hooked[humanoid] = humanoid.HealthChanged:Connect(function(hp)
		local prev = lastHealth[humanoid]
		if prev == nil then
			lastHealth[humanoid] = hp
			return
		end
		-- Any real damage taken puts the victim in combat
		if hp < prev - 0.05 then
			CombatHelper.markInCombat(model)
		end
		lastHealth[humanoid] = hp
	end)

	humanoid.Destroying:Connect(function()
		local conn = hooked[humanoid]
		if conn then
			conn:Disconnect()
		end
		hooked[humanoid] = nil
		lastHealth[humanoid] = nil
	end)
end

local function tryHook(model: Model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		hookHumanoid(model, humanoid)
	end
end

function CombatService.update()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character then
			CombatHelper.refreshCombatFlag(character)
		end
	end
end

function CombatService.init()
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

return CombatService
