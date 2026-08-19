--!strict

local MovementHelper = {}

function MovementHelper.flattenDirection(direction: Vector3): Vector3
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 0.01 then
		return Vector3.new(0, 0, -1)
	end
	return flat.Unit
end

function MovementHelper.getWASDDirection(character: Model, moveVector: Vector3): Vector3
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return Vector3.zero
	end
	if moveVector.Magnitude < 0.05 then
		return Vector3.zero
	end
	local camRelative = root.CFrame:VectorToWorldSpace(Vector3.new(moveVector.X, 0, moveVector.Z))
	return MovementHelper.flattenDirection(camRelative)
end

function MovementHelper.smoothFaceDirection(root: BasePart, direction: Vector3, alpha: number)
	local flat = MovementHelper.flattenDirection(direction)
	local target = CFrame.lookAt(root.Position, root.Position + flat)
	root.CFrame = root.CFrame:Lerp(target, math.clamp(alpha, 0, 1))
end

function MovementHelper.applyVelocity(root: BasePart, direction: Vector3, speed: number)
	local flat = MovementHelper.flattenDirection(direction)
	root.AssemblyLinearVelocity = flat * speed + Vector3.new(0, root.AssemblyLinearVelocity.Y * 0.5, 0)
end

function MovementHelper.lerpHorizontalVelocity(root: BasePart, direction: Vector3, targetSpeed: number, blend: number)
	local flat = MovementHelper.flattenDirection(direction)
	local current = root.AssemblyLinearVelocity
	local target = flat * targetSpeed
	local horizontal = Vector3.new(current.X, 0, current.Z):Lerp(target, math.clamp(blend, 0, 1))
	root.AssemblyLinearVelocity = Vector3.new(horizontal.X, current.Y, horizontal.Z)
end

function MovementHelper.addVelocity(root: BasePart, direction: Vector3, speed: number)
	local flat = MovementHelper.flattenDirection(direction)
	local current = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = Vector3.new(current.X, current.Y, current.Z) + flat * speed
end

function MovementHelper.buildMomentum(
	currentVelocity: Vector3,
	inputDirection: Vector3,
	acceleration: number,
	maxSpeed: number,
	drag: number,
	dt: number
): Vector3
	local horizontal = Vector3.new(currentVelocity.X, 0, currentVelocity.Z)
	if inputDirection.Magnitude > 0.05 then
		horizontal += inputDirection.Unit * acceleration * dt
	end
	horizontal *= drag
	if horizontal.Magnitude > maxSpeed then
		horizontal = horizontal.Unit * maxSpeed
	end
	return Vector3.new(horizontal.X, currentVelocity.Y, horizontal.Z)
end

return MovementHelper
