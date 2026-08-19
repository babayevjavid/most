--!strict

local PushHelper = {}

export type PushOptions = {
	speed: number,
	upBoost: number?,
}

function PushHelper.applyToPart(part: BasePart, direction: Vector3, options: PushOptions)
	if part.Anchored then
		return
	end
	local pushDir = if direction.Magnitude > 0.01 then direction.Unit else Vector3.new(0, 0, -1)
	local up = options.upBoost or 0
	part.AssemblyLinearVelocity = pushDir * options.speed + Vector3.new(0, up, 0)
	pcall(function()
		part:ApplyImpulse(pushDir * part.AssemblyMass * options.speed * 0.5)
	end)
end

function PushHelper.applyToCharacter(character: Model, direction: Vector3, options: PushOptions)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		PushHelper.applyToPart(root, direction, options)
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	end
end

return PushHelper
