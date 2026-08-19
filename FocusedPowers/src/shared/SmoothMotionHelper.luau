--!strict
--[[
	Smooth motion utilities for ability travel and camera-adjacent lerps.
]]

local SmoothMotionHelper = {}

function SmoothMotionHelper.smoothstep(alpha: number): number
	alpha = math.clamp(alpha, 0, 1)
	return alpha * alpha * (3 - 2 * alpha)
end

function SmoothMotionHelper.lerpVector3(a: Vector3, b: Vector3, alpha: number): Vector3
	return a:Lerp(b, alpha)
end

function SmoothMotionHelper.lerpCFrameToward(from: CFrame, to: CFrame, alpha: number): CFrame
	return from:Lerp(to, alpha)
end

function SmoothMotionHelper.runSmoothTravel(
	root: BasePart,
	startPos: Vector3,
	endPos: Vector3,
	duration: number,
	lookDir: Vector3?
): boolean
	if duration <= 0 then
		root.CFrame = CFrame.lookAt(endPos, endPos + (lookDir or root.CFrame.LookVector))
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		return true
	end

	local flatLook = lookDir or root.CFrame.LookVector
	if flatLook.Magnitude < 0.01 then
		flatLook = Vector3.new(0, 0, -1)
	else
		flatLook = Vector3.new(flatLook.X, 0, flatLook.Z).Unit
	end

	local elapsed = 0
	while elapsed < duration do
		if not root.Parent then
			return false
		end
		local dt = task.wait()
		elapsed += dt
		local alpha = SmoothMotionHelper.smoothstep(elapsed / duration)
		local pos = startPos:Lerp(endPos, alpha)
		root.CFrame = CFrame.lookAt(pos, pos + flatLook)
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end

	if root.Parent then
		root.CFrame = CFrame.lookAt(endPos, endPos + flatLook)
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
	return true
end

return SmoothMotionHelper
