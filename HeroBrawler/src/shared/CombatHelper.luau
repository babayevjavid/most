--!strict

local CombatHelper = {}

function CombatHelper.getCharacterFromPart(part: BasePart?): Model?
	if not part then
		return nil
	end
	local model = part:FindFirstAncestorOfClass("Model")
	if not model then
		return nil
	end
	if model:FindFirstChildOfClass("Humanoid") then
		return model
	end
	return nil
end

function CombatHelper.getHumanoid(model: Model?): Humanoid?
	if not model then
		return nil
	end
	return model:FindFirstChildOfClass("Humanoid")
end

function CombatHelper.dealDamage(attacker: Model, target: Model, amount: number)
	local humanoid = CombatHelper.getHumanoid(target)
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	if target == attacker then
		return
	end
	humanoid:TakeDamage(amount)
end

function CombatHelper.overlapCharacters(origin: Vector3, radius: number, exclude: Model?): { Model }
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if exclude then { exclude } else {}
	local parts = workspace:GetPartBoundsInRadius(origin, radius, params)
	local seen: { [Model]: boolean } = {}
	local results: { Model } = {}
	for _, part in parts do
		local character = CombatHelper.getCharacterFromPart(part)
		if character and not seen[character] then
			seen[character] = true
			local humanoid = CombatHelper.getHumanoid(character)
			if humanoid and humanoid.Health > 0 then
				table.insert(results, character)
			end
		end
	end
	return results
end

function CombatHelper.raycastCharacter(
	origin: Vector3,
	direction: Vector3,
	range: number,
	exclude: Model?
): Model?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if exclude then { exclude } else {}
	local result = workspace:Raycast(origin, direction.Unit * range, params)
	if not result then
		return nil
	end
	return CombatHelper.getCharacterFromPart(result.Instance)
end

return CombatHelper
