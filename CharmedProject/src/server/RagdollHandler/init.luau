local PhysicsService = game:GetService("PhysicsService")

local module = {}
local RAGDOLL_COLLISION_GROUP = "RagdollCharacter"
local ORIGINAL_COLLISION_GROUP_ATTR = "RagdollOriginalCollisionGroup"
local ORIGINAL_CAN_COLLIDE_ATTR = "RagdollOrigCanCollide"

local function ensureRagdollCollisionGroup()
	local hasGroup = false
	local ok, result = pcall(function()
		return PhysicsService:IsCollisionGroupRegistered(RAGDOLL_COLLISION_GROUP)
	end)
	if ok then
		hasGroup = result == true
	end
	if not hasGroup then
		pcall(function()
			PhysicsService:RegisterCollisionGroup(RAGDOLL_COLLISION_GROUP)
		end)
	end
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(RAGDOLL_COLLISION_GROUP, RAGDOLL_COLLISION_GROUP, false)
	end)
end

local function clampAssemblyVelocity(part: BasePart)
	local linear = part.AssemblyLinearVelocity
	local linearMagnitude = linear.Magnitude
	if linearMagnitude > 90 then
		part.AssemblyLinearVelocity = linear.Unit * 90
	end

	local angular = part.AssemblyAngularVelocity
	local angularMagnitude = angular.Magnitude
	if angularMagnitude > 35 then
		part.AssemblyAngularVelocity = angular.Unit * 35
	end
end

local function saveOriginalCanCollide(part: BasePart)
	if part:GetAttribute(ORIGINAL_CAN_COLLIDE_ATTR) == nil then
		part:SetAttribute(ORIGINAL_CAN_COLLIDE_ATTR, part.CanCollide)
	end
end

local function restoreOriginalCanCollide(part: BasePart)
	local orig = part:GetAttribute(ORIGINAL_CAN_COLLIDE_ATTR)
	if typeof(orig) == "boolean" then
		part.CanCollide = orig
		part:SetAttribute(ORIGINAL_CAN_COLLIDE_ATTR, nil)
	end
end

type RagdollEnableOpts = {
	skipVelocityClamp: boolean?,
}

local function setRagdollEnabled(humanoid: Humanoid, isEnabled: boolean, opts: RagdollEnableOpts?)
	local character = humanoid.Parent
	if not character then
		return
	end

	local skipClamp = opts and opts.skipVelocityClamp == true
	local rootPart = character:FindFirstChild("HumanoidRootPart")

	-- Collision: only override while ragdoll is active. When disabling, restore saved values.
	-- (Previously HRP was always CanCollide=false and "off" zeroed all limbs — NPCs lost floor collision.)
	if isEnabled then
		if rootPart and rootPart:IsA("BasePart") then
			saveOriginalCanCollide(rootPart)
			rootPart.CanCollide = false
		end
		for _, inst in ipairs(character:GetDescendants()) do
			if inst:IsA("BasePart") and inst.Name ~= "HumanoidRootPart" then
				local isAccessoryHandle = inst.Parent and inst.Parent:IsA("Accessory")
				if isAccessoryHandle then
					saveOriginalCanCollide(inst)
					inst.CanCollide = false
				else
					saveOriginalCanCollide(inst)
					inst.CanCollide = true
					if inst:GetAttribute(ORIGINAL_COLLISION_GROUP_ATTR) == nil then
						inst:SetAttribute(ORIGINAL_COLLISION_GROUP_ATTR, inst.CollisionGroup)
					end
					inst.CollisionGroup = RAGDOLL_COLLISION_GROUP
					if not skipClamp then
						clampAssemblyVelocity(inst)
					end
				end
			end
		end
	else
		if rootPart and rootPart:IsA("BasePart") then
			restoreOriginalCanCollide(rootPart)
		end
		for _, inst in ipairs(character:GetDescendants()) do
			if inst:IsA("BasePart") and inst.Name ~= "HumanoidRootPart" then
				local isAccessoryHandle = inst.Parent and inst.Parent:IsA("Accessory")
				if isAccessoryHandle then
					restoreOriginalCanCollide(inst)
				else
					restoreOriginalCanCollide(inst)
					local original = inst:GetAttribute(ORIGINAL_COLLISION_GROUP_ATTR)
					if typeof(original) == "string" and original ~= "" then
						inst.CollisionGroup = original
						inst:SetAttribute(ORIGINAL_COLLISION_GROUP_ATTR, nil)
					end
				end
			end
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

local function keepRagdollActiveLightweight(humanoid: Humanoid)
	local character = humanoid.Parent
	if not character or not character:IsA("Model") then
		return
	end
	local ragdollConstraints = character:FindFirstChild("RagdollConstraints")
	if ragdollConstraints then
		for _, constraint in pairs(ragdollConstraints:GetChildren()) do
			if constraint:IsA("Constraint") then
				local rigidPointer = constraint:FindFirstChild("RigidJoint")
				local rigidJoint = rigidPointer and rigidPointer:IsA("ObjectValue") and rigidPointer.Value
				if rigidJoint and rigidJoint:IsA("Motor6D") then
					if rigidJoint.Part1 ~= nil then
						rigidJoint.Part1 = nil
					end
				end
			end
		end
	end
end

--[[ True if any ragdoll Motor6D is still welded (embedded AI/scripts reconnected Part1 after physics). ]]
function module:AnyRagdollMotorWelded(humanoid: Humanoid): boolean
	local character = humanoid.Parent
	if not character or not character:IsA("Model") then
		return false
	end
	local ragdollConstraints = character:FindFirstChild("RagdollConstraints")
	if not ragdollConstraints then
		return false
	end
	for _, constraint in pairs(ragdollConstraints:GetChildren()) do
		if constraint:IsA("Constraint") then
			local rigidPointer = constraint:FindFirstChild("RigidJoint")
			local rigidJoint = rigidPointer and rigidPointer:IsA("ObjectValue") and rigidPointer.Value
			if rigidJoint and rigidJoint:IsA("Motor6D") and rigidJoint.Part1 ~= nil then
				return true
			end
		end
	end
	return false
end

--[[ After physics: only disconnect constraint motors + keep Humanoid in Physics (no full descendant scan). ]]
function module:MaintainNpcRagdollAfterPhysics(humanoid: Humanoid)
	local character = humanoid.Parent
	if not character or not character:IsA("Model") then
		return
	end
	if character:GetAttribute("Ragdolled") ~= true or humanoid.Health <= 0 then
		return
	end
	local st = humanoid:GetState()
	if st ~= Enum.HumanoidStateType.Physics and st ~= Enum.HumanoidStateType.Dead then
		pcall(function()
			humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		end)
	end
	humanoid.PlatformStand = false
	humanoid.RequiresNeck = false
	keepRagdollActiveLightweight(humanoid)
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
	setRagdollEnabled(humanoid, isEnabled, nil)
end

--[[
	While Ragdolled status is active, collisions/state can still kick the Humanoid out of Physics.
	Call from Heartbeat — skips velocity clamp so we don't damp the ragdoll every frame.
]]
function module:MaintainStatusRagdoll(humanoid: Humanoid)
	local character = humanoid.Parent
	if not character or not character:IsA("Model") then
		return
	end
	if character:GetAttribute("Ragdolled") ~= true or humanoid.Health <= 0 then
		return
	end
	local st = humanoid:GetState()
	if st ~= Enum.HumanoidStateType.Physics and st ~= Enum.HumanoidStateType.Dead then
		pcall(function()
			humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		end)
	end
	humanoid.PlatformStand = false
	humanoid.RequiresNeck = false
	keepRagdollActiveLightweight(humanoid)
end

--[[
	NPCs: embedded server Scripts / Animator can re-weld Motor6Ds after physics. Re-apply full ragdoll
	collision + joint disconnect (skip velocity clamp). Call after physics / deferred.
]]
function module:MaintainNpcRagdollHard(humanoid: Humanoid)
	local character = humanoid.Parent
	if not character or not character:IsA("Model") then
		return
	end
	if character:GetAttribute("Ragdolled") ~= true or humanoid.Health <= 0 then
		return
	end
	local st = humanoid:GetState()
	if st ~= Enum.HumanoidStateType.Physics and st ~= Enum.HumanoidStateType.Dead then
		pcall(function()
			humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		end)
	end
	humanoid.PlatformStand = false
	humanoid.RequiresNeck = false
	setRagdollEnabled(humanoid, true, { skipVelocityClamp = true })
end

function module:ragdollAdded(humanoid: Humanoid)
	if not humanoid then
		return
	end
	ensureRagdollCollisionGroup()
	-- Do NOT use Humanoid.StateChanged to drive ragdoll on/off: contact/state churn calls it with
	-- non-Physics states and was disabling constraint ragdoll while Ragdolled stayed true.
end

function module:ragdollRemoved(humanoid: Humanoid)
	-- kept for API symmetry
end

return module
