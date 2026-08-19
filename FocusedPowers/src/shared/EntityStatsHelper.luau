--!strict
--[[
	Resolve display name and stats for players and NPC humanoids.
]]

local Players = game:GetService("Players")

export type EntityStats = {
	displayName: string,
	health: number,
	maxHealth: number,
	energy: number,
	maxEnergy: number,
}

local EntityStatsHelper = {}

function EntityStatsHelper.getModelFromPart(part: BasePart?): Model?
	if not part then
		return nil
	end
	local model = part:FindFirstAncestorOfClass("Model")
	if not model then
		return nil
	end
	if not model:FindFirstChildOfClass("Humanoid") then
		return nil
	end
	return model
end

function EntityStatsHelper.getPlayerForModel(model: Model): Player?
	return Players:GetPlayerFromCharacter(model)
end

function EntityStatsHelper.getDisplayName(model: Model): string
	local plr = EntityStatsHelper.getPlayerForModel(model)
	if plr then
		if plr.DisplayName ~= "" then
			return plr.DisplayName
		end
		return plr.Name
	end

	local attr = model:GetAttribute("DisplayName")
	if typeof(attr) == "string" and attr ~= "" then
		return attr
	end

	return model.Name
end

function EntityStatsHelper.getStats(model: Model): EntityStats?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end

	local energy = model:GetAttribute("Energy")
	local maxEnergy = model:GetAttribute("MaxEnergy")
	local currentEnergy = if typeof(energy) == "number" then energy else 100
	local energyMax = if typeof(maxEnergy) == "number" then maxEnergy else 100

	return {
		displayName = EntityStatsHelper.getDisplayName(model),
		health = humanoid.Health,
		maxHealth = humanoid.MaxHealth,
		energy = currentEnergy,
		maxEnergy = energyMax,
	}
end

function EntityStatsHelper.getHeadPart(model: Model): BasePart?
	return model:FindFirstChild("Head") :: BasePart?
		or model:FindFirstChild("HumanoidRootPart") :: BasePart?
		or model.PrimaryPart
end

return EntityStatsHelper
