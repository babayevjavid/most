--!strict
--[[
	Shared knockback / impulse for abilities.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local InteractableHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("InteractableHelper"))

export type PushOptions = {
	speed: number,
	upBoost: number?,
	impulseMult: number?,
}

local PushHelper = {}

function PushHelper.applyToPart(part: BasePart, direction: Vector3, options: PushOptions)
	if part.Anchored then
		return
	end
	local pushDir = if direction.Magnitude > 0.01 then direction.Unit else Vector3.new(0, 0, -1)
	local up = options.upBoost or 0
	local mult = options.impulseMult or 1
	local velocity = pushDir * options.speed + Vector3.new(0, up, 0)
	part.AssemblyLinearVelocity = velocity
	pcall(function()
		part:ApplyImpulse(pushDir * (part.AssemblyMass * options.speed * mult))
	end)
end

function PushHelper.applyToModel(model: Model, direction: Vector3, options: PushOptions)
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root and root:IsA("BasePart") then
		PushHelper.applyToPart(root, direction, options)
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		pcall(function()
			humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		end)
	end
end

function PushHelper.applyFromHit(
	hit: BasePart,
	direction: Vector3,
	options: PushOptions,
	excludeCharacter: Model?
)
	if not hit or not hit.Parent then
		return
	end
	local model = hit:FindFirstAncestorOfClass("Model")
	if excludeCharacter and model == excludeCharacter then
		return
	end

	local humanoid = if model then model:FindFirstChildOfClass("Humanoid") else nil
	if humanoid and humanoid.Health > 0 and model then
		PushHelper.applyToModel(model, direction, options)
	elseif InteractableHelper.hasInteractableMark(hit)
		or (model and InteractableHelper.modelIsInteractableProp(model))
	then
		PushHelper.applyToPart(hit, direction, options)
	elseif hit:IsA("BasePart") and not hit.Anchored then
		PushHelper.applyToPart(hit, direction, options)
	end
end

return PushHelper
