-- Custom combat health: replicated attributes + Humanoid mirror for death/ragdoll.

local ATTR_HEALTH = "CombatHealth"
local ATTR_MAX = "CombatMaxHealth"

local GameHealth = {}

local function getModel(humanoid: Humanoid): Model?
	local p = humanoid.Parent
	if p and p:IsA("Model") then
		return p
	end
	return nil
end

function GameHealth.syncHumanoid(humanoid: Humanoid)
	local model = getModel(humanoid)
	if not model then
		return
	end
	local maxV = model:GetAttribute(ATTR_MAX)
	local hV = model:GetAttribute(ATTR_HEALTH)
	if type(maxV) ~= "number" or type(hV) ~= "number" then
		return
	end
	local maxH = math.max(maxV, 1)
	local clamped = math.clamp(hV, 0, maxH)
	humanoid.MaxHealth = maxH
	if humanoid.Health ~= clamped then
		humanoid.Health = clamped
	end
end

function GameHealth.hasCustomHealth(model: Model): boolean
	return type(model:GetAttribute(ATTR_MAX)) == "number"
end

function GameHealth.initCharacter(character: Model, maxHealth: number)
	local hum = character:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	local m = math.max(maxHealth, 1)
	character:SetAttribute(ATTR_MAX, m)
	character:SetAttribute(ATTR_HEALTH, m)
	GameHealth.syncHumanoid(hum)
end

-- Optional: server sets this to attribute morality / combat logs when damage has a known attacker.
local damageAttributionHook: ((Player, Humanoid, number) -> ())? = nil

function GameHealth.setDamageAttributionHook(callback: ((Player, Humanoid, number) -> ())?)
	damageAttributionHook = callback
end

function GameHealth.applyDamage(humanoid: Humanoid, amount: number, attackerPlayer: Player?)
	if amount <= 0 then
		return
	end
	local model = getModel(humanoid)
	if not model or not GameHealth.hasCustomHealth(model) then
		humanoid:TakeDamage(amount)
		if attackerPlayer and damageAttributionHook then
			damageAttributionHook(attackerPlayer, humanoid, amount)
		end
		return
	end
	local h = (model:GetAttribute(ATTR_HEALTH) :: number) or humanoid.Health
	local newH = math.max(0, h - amount)
	model:SetAttribute(ATTR_HEALTH, newH)
	GameHealth.syncHumanoid(humanoid)
	if attackerPlayer and damageAttributionHook then
		damageAttributionHook(attackerPlayer, humanoid, amount)
	end
end

function GameHealth.heal(humanoid: Humanoid, amount: number)
	if amount <= 0 then
		return
	end
	local model = getModel(humanoid)
	if not model or not GameHealth.hasCustomHealth(model) then
		humanoid.Health = math.clamp(humanoid.Health + amount, 0, humanoid.MaxHealth)
		return
	end
	local maxH = (model:GetAttribute(ATTR_MAX) :: number) or humanoid.MaxHealth
	local h = (model:GetAttribute(ATTR_HEALTH) :: number) or humanoid.Health
	local newH = math.clamp(h + amount, 0, maxH)
	model:SetAttribute(ATTR_HEALTH, newH)
	GameHealth.syncHumanoid(humanoid)
end

function GameHealth.getHealth(humanoid: Humanoid): (number, number)
	local model = getModel(humanoid)
	if model and GameHealth.hasCustomHealth(model) then
		local h = model:GetAttribute(ATTR_HEALTH)
		local m = model:GetAttribute(ATTR_MAX)
		if type(h) == "number" and type(m) == "number" then
			return h, m
		end
	end
	return humanoid.Health, humanoid.MaxHealth
end

return GameHealth
