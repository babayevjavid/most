--!strict
--[[
	Shared ragdoll status API. On the server, RagdollService.bindServer hooks these
	into constraint ragdoll physics. Attribute-only fallback for clients / before bind.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AbilityCooldownHelper = require(ReplicatedStorage.Shared.AbilityCooldownHelper)
local GameConstants = require(ReplicatedStorage.Shared.GameConstants)

local RagdollStatus = {}

local clearTokenByModel: { [Model]: number } = {}

type ServerHandlers = {
	apply: (Model) -> (),
	clear: (Model) -> (),
	applyTimed: (Model, number) -> (),
	clearAfter: (Model, number) -> (),
}

local server: ServerHandlers? = nil

local function nextToken(model: Model): number
	local token = (clearTokenByModel[model] or 0) + 1
	clearTokenByModel[model] = token
	return token
end

-- Shields block all ragdoll CC from abilities (damage still flows into the shield).
local function isShieldBlocked(character: Model): boolean
	if character:GetAttribute(GameConstants.SHIELD_ACTIVE_ATTRIBUTE) ~= true then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

function RagdollStatus.bindServer(handlers: ServerHandlers)
	server = handlers
end

function RagdollStatus.isRagdolled(character: Model): boolean
	return character:GetAttribute(GameConstants.RAGDOLLED_ATTRIBUTE) == true
end

function RagdollStatus.apply(character: Model)
	if isShieldBlocked(character) then
		return
	end
	if server then
		server.apply(character)
		return
	end
	character:SetAttribute(GameConstants.RAGDOLLED_ATTRIBUTE, true)
	character:SetAttribute(GameConstants.RAGDOLL_END_ATTRIBUTE, nil)
	nextToken(character)
end

function RagdollStatus.clear(character: Model)
	if server then
		server.clear(character)
		return
	end
	nextToken(character)
	character:SetAttribute(GameConstants.RAGDOLLED_ATTRIBUTE, nil)
	character:SetAttribute(GameConstants.RAGDOLL_END_ATTRIBUTE, nil)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Parent then
		humanoid.PlatformStand = false
	end
end

function RagdollStatus.applyTimed(character: Model, duration: number)
	if isShieldBlocked(character) then
		return
	end
	if character:GetAttribute("TelekinesisHeld") == true then
		RagdollStatus.apply(character)
		return
	end
	if server then
		server.applyTimed(character, duration)
		return
	end

	local endTime = AbilityCooldownHelper.getNow() + duration
	local currentEnd = character:GetAttribute(GameConstants.RAGDOLL_END_ATTRIBUTE)
	if type(currentEnd) == "number" and currentEnd > endTime then
		character:SetAttribute(GameConstants.RAGDOLLED_ATTRIBUTE, true)
		return
	end

	character:SetAttribute(GameConstants.RAGDOLLED_ATTRIBUTE, true)
	character:SetAttribute(GameConstants.RAGDOLL_END_ATTRIBUTE, endTime)
	local token = nextToken(character)
	task.delay(duration, function()
		if not character.Parent then
			return
		end
		if clearTokenByModel[character] ~= token then
			return
		end
		if character:GetAttribute("TelekinesisHeld") == true then
			return
		end
		local scheduled = character:GetAttribute(GameConstants.RAGDOLL_END_ATTRIBUTE)
		if type(scheduled) == "number" and AbilityCooldownHelper.getNow() + 0.05 < scheduled then
			return
		end
		RagdollStatus.clear(character)
	end)
end

function RagdollStatus.clearAfter(character: Model, delaySec: number)
	if isShieldBlocked(character) then
		return
	end
	if server then
		server.clearAfter(character, delaySec)
		return
	end
	local token = nextToken(character)
	local endTime = AbilityCooldownHelper.getNow() + delaySec
	character:SetAttribute(GameConstants.RAGDOLLED_ATTRIBUTE, true)
	character:SetAttribute(GameConstants.RAGDOLL_END_ATTRIBUTE, endTime)
	task.delay(delaySec, function()
		if not character.Parent then
			return
		end
		if clearTokenByModel[character] ~= token then
			return
		end
		if character:GetAttribute("TelekinesisHeld") == true then
			return
		end
		RagdollStatus.clear(character)
	end)
end

return RagdollStatus
