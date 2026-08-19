local getLastWordFromPascalCase = require(script.Parent:WaitForChild("getLastWordFromPascalCase"))

local function makeHinge(lower: number, upper: number, restitution: number): HingeConstraint
	local h = Instance.new("HingeConstraint")
	h.LimitsEnabled = true
	h.LowerAngle = lower
	h.UpperAngle = upper
	h.Restitution = restitution
	h.Radius = 0.15
	return h
end

local function makeBall(upper: number, twistLower: number, twistUpper: number): BallSocketConstraint
	local b = Instance.new("BallSocketConstraint")
	b.LimitsEnabled = true
	b.TwistLimitsEnabled = true
	b.UpperAngle = upper
	b.TwistLowerAngle = twistLower
	b.TwistUpperAngle = twistUpper
	return b
end

local function constraintTemplateForJoint(jointName: string): Constraint
	local jointType = getLastWordFromPascalCase(jointName)
	if jointType == "Ankle" then
		return makeHinge(-45, 0, 0)
	elseif jointType == "Elbow" then
		return makeHinge(0, 135, 0)
	elseif jointType == "Knee" then
		return makeHinge(-135, -10, 0)
	elseif jointType == "Wrist" then
		return makeHinge(-20, 20, 0)
	elseif jointType == "Hip" then
		return makeBall(40, -3, 3)
	elseif jointType == "Neck" then
		return makeBall(0, -45, 45)
	elseif jointType == "Shoulder" then
		return makeBall(30, -30, 30)
	elseif jointType == "Waist" then
		return makeBall(15, -1, 1)
	end
	return makeBall(20, -15, 15)
end

local function createConstraint(jointData)
	local joint = jointData.Joint
	local constraint = constraintTemplateForJoint(joint.Name)
	constraint.Attachment0 = jointData.Attachment0
	constraint.Attachment1 = jointData.Attachment1
	constraint.Name = getLastWordFromPascalCase(joint.Name) .. "RagdollConstraint"

	local rigidPointer = Instance.new("ObjectValue")
	rigidPointer.Name = "RigidJoint"
	rigidPointer.Value = joint
	rigidPointer.Parent = constraint
	return constraint
end

return function(attachmentMap)
	local ragdollConstraints = Instance.new("Folder")
	ragdollConstraints.Name = "RagdollConstraints"

	for _, jointData in pairs(attachmentMap) do
		-- R15 uses "Root"; classic R6 uses "RootJoint". Keep HRP welded so TK can lift the body.
		local jointName = jointData.Joint.Name
		if jointName ~= "Root" and jointName ~= "RootJoint" then
			createConstraint(jointData).Parent = ragdollConstraints
		end
	end
	return ragdollConstraints
end

