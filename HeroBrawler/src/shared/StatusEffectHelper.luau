--!strict

local Workspace = game:GetService("Workspace")

local StatusEffectHelper = {}

export type ActiveEffect = {
	id: string,
	name: string,
	description: string,
	remaining: number,
}

local function now(): number
	return Workspace:GetServerTimeNow()
end

function StatusEffectHelper.apply(character: Model, effectId: string, displayName: string, description: string, duration: number)
	character:SetAttribute("Status_" .. effectId .. "_Until", now() + duration)
	character:SetAttribute("Status_" .. effectId .. "_Name", displayName)
	character:SetAttribute("Status_" .. effectId .. "_Desc", description)
end

function StatusEffectHelper.clear(character: Model, effectId: string)
	character:SetAttribute("Status_" .. effectId .. "_Until", nil)
	character:SetAttribute("Status_" .. effectId .. "_Name", nil)
	character:SetAttribute("Status_" .. effectId .. "_Desc", nil)
end

function StatusEffectHelper.refresh(character: Model, effectId: string, displayName: string, description: string, duration: number)
	StatusEffectHelper.apply(character, effectId, displayName, description, duration)
end

function StatusEffectHelper.getActive(character: Model): { ActiveEffect }
	local results: { ActiveEffect } = {}
	local t = now()
	for name, value in character:GetAttributes() do
		if string.sub(name, 1, 7) == "Status_" and string.sub(name, -6) == "_Until" and type(value) == "number" and t < value then
			local id = string.sub(name, 8, -7)
			local displayName = character:GetAttribute("Status_" .. id .. "_Name")
			local description = character:GetAttribute("Status_" .. id .. "_Desc")
			table.insert(results, {
				id = id,
				name = if type(displayName) == "string" then displayName else id,
				description = if type(description) == "string" then description else "",
				remaining = value - t,
			})
		end
	end
	table.sort(results, function(a, b)
		return a.remaining < b.remaining
	end)
	return results
end

function StatusEffectHelper.isActive(character: Model, effectId: string): boolean
	local untilTime = character:GetAttribute("Status_" .. effectId .. "_Until")
	return type(untilTime) == "number" and now() < untilTime
end

return StatusEffectHelper
