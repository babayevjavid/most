local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local module = {}

local RAGDOLL_STATES = {
	[Enum.HumanoidStateType.Dead] = true,
	[Enum.HumanoidStateType.Physics] = true,
}

local connections = {}

local function setRagdollEnabled(humanoid: Humanoid, isEnabled: boolean)
	local character = humanoid.Parent
	if not character then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart and rootPart:IsA("BasePart") then
		rootPart.CanCollide = false
	end

	for _, inst in ipairs(character:GetDescendants()) do
		if inst:IsA("BasePart") and inst.Name ~= "HumanoidRootPart" then
			inst.CanCollide = isEnabled
		end
	end

	local ragdollConstraints = character:FindFirstChild("RagdollConstraints")
	if ragdollConstraints then
		for _, constraint in pairs(ragdollConstraints:GetChildren()) do
			if constraint:IsA("Constraint") then
				local rigidPointer = constraint:FindFirstChild("RigidJoint")
				local rigidJoint = rigidPointer and rigidPointer:IsA("ObjectValue") and rigidPointer.Value
				if rigidJoint and rigidJoint:IsA("Motor6D") then
					local expected = (not isEnabled) and constraint.Attachment1 and constraint.Attachment1.Parent or nil
					if rigidJoint.Part1 ~= expected then
						rigidJoint.Part1 = expected
					end
				end
			end
		end
	end
end

local function hasRagdollOwnership(humanoid: Humanoid): boolean
	if RunService:IsServer() then
		return true
	end
	local player = Players:GetPlayerFromCharacter(humanoid.Parent)
	return player == Players.LocalPlayer
end

function module:ManualRagdoll(humanoid: Humanoid, isEnabled: boolean)
	if isEnabled then
		-- Prevent instant death when neck Motor6D is temporarily disconnected.
		humanoid.RequiresNeck = false
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	else
		humanoid.RequiresNeck = true
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
	setRagdollEnabled(humanoid, isEnabled)
end

function module:ragdollAdded(humanoid: Humanoid)
	if not humanoid or connections[humanoid] then
		return
	end
	connections[humanoid] = humanoid.StateChanged:Connect(function(_, newState)
		if hasRagdollOwnership(humanoid) then
			setRagdollEnabled(humanoid, RAGDOLL_STATES[newState] == true)
		end
	end)
end

function module:ragdollRemoved(humanoid: Humanoid)
	if connections[humanoid] then
		connections[humanoid]:Disconnect()
		connections[humanoid] = nil
	end
end

return module

