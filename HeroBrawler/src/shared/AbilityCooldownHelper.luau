--!strict

local Workspace = game:GetService("Workspace")

local AbilityCooldownHelper = {}

function AbilityCooldownHelper.getNow(): number
	return Workspace:GetServerTimeNow()
end

function AbilityCooldownHelper.getAttributeName(abilityId: string): string
	return "CooldownEnd_" .. abilityId
end

function AbilityCooldownHelper.getActiveAttributeName(abilityId: string): string
	return "AbilityActive_" .. abilityId
end

function AbilityCooldownHelper.isOnCooldown(character: Model, abilityId: string, now: number?): boolean
	local t = now or AbilityCooldownHelper.getNow()
	local endTime = character:GetAttribute(AbilityCooldownHelper.getAttributeName(abilityId))
	return type(endTime) == "number" and t < endTime
end

function AbilityCooldownHelper.isActive(character: Model, abilityId: string): boolean
	return character:GetAttribute(AbilityCooldownHelper.getActiveAttributeName(abilityId)) == true
end

function AbilityCooldownHelper.getRemaining(character: Model, abilityId: string, now: number?): number
	local t = now or AbilityCooldownHelper.getNow()
	local endTime = character:GetAttribute(AbilityCooldownHelper.getAttributeName(abilityId))
	if type(endTime) ~= "number" then
		return 0
	end
	return math.max(0, endTime - t)
end

function AbilityCooldownHelper.setActive(character: Model, abilityId: string, active: boolean)
	character:SetAttribute(AbilityCooldownHelper.getActiveAttributeName(abilityId), if active then true else nil)
end

function AbilityCooldownHelper.applyAfterUse(character: Model, abilityId: string, seconds: number)
	character:SetAttribute(
		AbilityCooldownHelper.getAttributeName(abilityId),
		AbilityCooldownHelper.getNow() + seconds
	)
end

function AbilityCooldownHelper.clear(character: Model, abilityId: string)
	character:SetAttribute(AbilityCooldownHelper.getAttributeName(abilityId), nil)
	character:SetAttribute(AbilityCooldownHelper.getActiveAttributeName(abilityId), nil)
end

return AbilityCooldownHelper
