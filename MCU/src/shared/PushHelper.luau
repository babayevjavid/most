--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConstants = require(ReplicatedStorage.Shared.GameConstants)

local PushHelper = {}

export type PushOptions = {
	speed: number,
	upBoost: number?,
	impulseMult: number?,
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

-- Aim from current HRP toward cursor. If the cursor is too close, use caster look.
function PushHelper.launchTowardCursor(fromPos: Vector3, aimPoint: Vector3?, fallbackLook: Vector3): Vector3
	local look = Vector3.new(fallbackLook.X, 0, fallbackLook.Z)
	if look.Magnitude < 0.05 then
		look = Vector3.new(0, 0, -1)
	else
		look = look.Unit
	end
	local cursor = aimPoint
	if typeof(cursor) ~= "Vector3" then
		cursor = fromPos + look * 90
	end
	local launchVec = cursor - fromPos
	local launch: Vector3
	if launchVec.Magnitude < 10 then
		launch = look * 0.88 + Vector3.yAxis * 0.22
	else
		launch = launchVec.Unit
	end
	if launch.Magnitude > 0.01 then
		return launch.Unit
	end
	return look
end

function PushHelper.telekineticFling(character: Model, root: BasePart, launch: Vector3, speed: number, upBoost: number)
	local function shove()
		if not character.Parent or not root.Parent then
			return
		end
		PushHelper.applyToCharacter(character, launch, {
			speed = speed,
			upBoost = upBoost,
			impulseMult = 0.94,
		})
		root.AssemblyLinearVelocity = launch * speed + Vector3.new(0, math.max(22, upBoost * 0.85), 0)
	end
	shove()
	task.defer(shove)
	task.delay(0.06, shove)
end

function PushHelper.applyToCharacter(character: Model, direction: Vector3, options: PushOptions)
	-- Shields block push / knockback CC: abilities may only damage the shield, never move the holder.
	local shieldHum = character:FindFirstChildOfClass("Humanoid")
	if shieldHum and shieldHum.Health > 0 and character:GetAttribute(GameConstants.SHIELD_ACTIVE_ATTRIBUTE) == true then
		return
	end
	local pushDir = if direction.Magnitude > 0.01 then direction.Unit else Vector3.new(0, 0, -1)
	local up = options.upBoost or 0
	local velocity = pushDir * options.speed + Vector3.new(0, up, 0)
	local impulseMult = options.impulseMult or 0.85

	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root and not root.Anchored then
		root.AssemblyLinearVelocity = velocity
		pcall(function()
			root:ApplyImpulse(pushDir * root.AssemblyMass * options.speed * impulseMult)
		end)
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		pcall(function()
			humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		end)
	end
end

return PushHelper
