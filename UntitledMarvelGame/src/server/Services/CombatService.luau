--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))

local CombatService = {}

function CombatService.getDamageMultiplier(player: Player, heroId: string?): number
	if heroId ~= "Wanda" then
		return 1
	end

	local character = player.Character
	if not character then
		return 1
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.MaxHealth <= 0 then
		return 1
	end

	local hpRatio = humanoid.Health / humanoid.MaxHealth
	if hpRatio <= Constants.UNDONE_GRIEF_HP_THRESHOLD then
		return Constants.UNDONE_GRIEF_DAMAGE_MULTIPLIER
	end
	return 1
end

function CombatService.applyDamage(attacker: Player, targetHumanoid: Humanoid, baseDamage: number, heroId: string?)
	local damage = CombatService.computeDamage(attacker, heroId, baseDamage)
	targetHumanoid:TakeDamage(damage)
end

function CombatService.computeDamage(attacker: Player, heroId: string?, baseDamage: number): number
	return baseDamage * CombatService.getDamageMultiplier(attacker, heroId)
end

return CombatService
