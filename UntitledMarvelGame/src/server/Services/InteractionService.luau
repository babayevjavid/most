--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))
local InteractionConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("InteractionConfig"))
local PropHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PropHelper"))

local InteractionService = {}

local function getHumanoidRoot(model: Model): BasePart?
	return model:FindFirstChild("HumanoidRootPart") :: BasePart?
		or model:FindFirstChild("Torso") :: BasePart?
		or model:FindFirstChild("UpperTorso") :: BasePart?
end

local function unanchorIfNeeded(part: BasePart)
	if part.Anchored then
		part.Anchored = false
	end
	local model = part:FindFirstAncestorOfClass("Model")
	if model then
		for _, desc in model:GetDescendants() do
			if desc:IsA("BasePart") and desc.Anchored then
				desc.Anchored = false
			end
		end
	end
end

function InteractionService.getTargetFromRay(origin: Vector3, direction: Vector3, maxDistance: number, exclude: { Instance }?): Instance?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude or {}
	local result = workspace:Raycast(origin, direction.Unit * maxDistance, params)
	if not result then
		return nil
	end
	return result.Instance
end

function InteractionService.isValidPushTarget(inst: Instance): boolean
	if inst:IsA("BasePart") then
		local model = inst:FindFirstAncestorOfClass("Model")
		if model then
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				return true
			end
			if PropHelper.isProp(inst) then
				return true
			end
		end
		if PropHelper.isProp(inst) then
			return true
		end
	end
	return false
end

function InteractionService.pushTarget(target: Instance, direction: Vector3, abilityId: string, attacker: Player?)
	local profile = InteractionConfig[abilityId]
	if not profile then
		return
	end

	local model = if target:IsA("Model") then target else target:FindFirstAncestorOfClass("Model")
	if not model then
		if target:IsA("BasePart") and PropHelper.isProp(target) then
			model = target:FindFirstAncestorOfClass("Model") or target
		else
			return
		end
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		local root = getHumanoidRoot(model)
		if root then
			root.AssemblyLinearVelocity = direction.Unit * profile.humanoidForce
		end
		return
	end

	if PropHelper.isProp(model) or PropHelper.isProp(target) then
		local root = PropHelper.getPropRoot(model) or PropHelper.getPropRoot(target)
		if root then
			unanchorIfNeeded(root)
			root.AssemblyLinearVelocity = direction.Unit * profile.propForce
		end
	end
end

function InteractionService.pushCone(attackerCharacter: Model, abilityId: string, range: number, halfAngle: number)
	local root = getHumanoidRoot(attackerCharacter)
	if not root then
		return
	end

	local origin = root.Position
	local look = root.CFrame.LookVector

	for _, player in game:GetService("Players"):GetPlayers() do
		local char = player.Character
		if char and char ~= attackerCharacter then
			local targetRoot = getHumanoidRoot(char)
			if targetRoot then
				local offset = targetRoot.Position - origin
				local dist = offset.Magnitude
				if dist <= range and dist > 0 then
					local dot = look:Dot(offset.Unit)
					if dot >= math.cos(math.rad(halfAngle)) then
						InteractionService.pushTarget(char, look, abilityId, nil)
					end
				end
			end
		end
	end

	for _, model in workspace:GetDescendants() do
		if model:IsA("Model") and PropHelper.isProp(model) then
			local part = PropHelper.getPropRoot(model)
			if part then
				local offset = part.Position - origin
				local dist = offset.Magnitude
				if dist <= range and dist > 0 then
					local dot = look:Dot(offset.Unit)
					if dot >= math.cos(math.rad(halfAngle)) then
						InteractionService.pushTarget(model, look, abilityId, nil)
					end
				end
			end
		end
	end
end

function InteractionService.telekinesisThrow(attackerCharacter: Model, target: Instance, aimDirection: Vector3)
	local profile = InteractionConfig.Telekinesis
	if not profile then
		return
	end

	local model = if target:IsA("Model") then target else target:FindFirstAncestorOfClass("Model")
	if not model then
		return
	end

	local direction = if aimDirection.Magnitude > 0 then aimDirection.Unit else attackerCharacter:GetPivot().LookVector
	local humanoid = model:FindFirstChildOfClass("Humanoid")

	if humanoid and humanoid.Health > 0 then
		local root = getHumanoidRoot(model)
		if root then
			root.AssemblyLinearVelocity = direction * Constants.TELEKINESIS_THROW_FORCE
		end
		return
	end

	if PropHelper.isProp(model) or PropHelper.isProp(target) then
		local root = PropHelper.getPropRoot(model)
		if root then
			unanchorIfNeeded(root)
			root.AssemblyLinearVelocity = direction * Constants.TELEKINESIS_THROW_FORCE
		end
	end
end

return InteractionService
