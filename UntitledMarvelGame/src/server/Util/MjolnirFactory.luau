--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))

local MjolnirFactory = {}

local cachedTemplate: Instance? = nil

local function getTemplate(): Instance?
	if cachedTemplate then
		return cachedTemplate
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		return nil
	end
	local thor = assets:FindFirstChild("Thor")
	if not thor then
		return nil
	end
	local mjolnir = thor:FindFirstChild("Mjolnir")
	if not mjolnir then
		return nil
	end
	cachedTemplate = mjolnir
	return mjolnir
end

local function getRightHand(character: Model): BasePart?
	return character:FindFirstChild("RightHand") :: BasePart?
		or character:FindFirstChild("Right Arm") :: BasePart?
end

function MjolnirFactory.createWieldModel(character: Model): Model?
	local template = getTemplate()
	if not template then
		warn("[MjolnirFactory] ReplicatedStorage.Assets.Thor.Mjolnir not found")
		return nil
	end

	local hand = getRightHand(character)
	if not hand then
		return nil
	end

	local model = Instance.new("Model")
	model.Name = "MjolnirWield"

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.2, 0.2, 0.2)
	handle.Transparency = 1
	handle.CanCollide = false
	handle.Massless = true
	handle.Anchored = false
	handle.CFrame = hand.CFrame * Constants.MJOLNIR_GRIP_OFFSET
	handle.Parent = model

	local meshClone = template:Clone()
	meshClone.Parent = model

	if meshClone:IsA("MeshPart") then
		meshClone.Anchored = false
		meshClone.CanCollide = false
		meshClone.Massless = true
		meshClone.CFrame = handle.CFrame * Constants.MJOLNIR_GRIP_OFFSET:Inverse()
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = meshClone
		weld.Parent = handle
		model.PrimaryPart = handle
	elseif meshClone:IsA("BasePart") then
		meshClone.Anchored = false
		meshClone.CanCollide = false
		meshClone.Massless = true
		meshClone.CFrame = handle.CFrame
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = meshClone
		weld.Parent = handle
		model.PrimaryPart = handle
	elseif meshClone:IsA("Model") then
		local part = meshClone:FindFirstChildWhichIsA("BasePart", true)
		if part then
			part.Anchored = false
			part.CanCollide = false
			for _, desc in meshClone:GetDescendants() do
				if desc:IsA("BasePart") then
					desc.Anchored = false
					desc.CanCollide = false
					desc.Massless = true
				end
			end
			handle.CFrame = hand.CFrame * Constants.MJOLNIR_GRIP_OFFSET
			part.CFrame = handle.CFrame
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = handle
			weld.Part1 = part
			weld.Parent = handle
			model.PrimaryPart = handle
		end
	end

	local handWeld = Instance.new("WeldConstraint")
	handWeld.Part0 = hand
	handWeld.Part1 = handle
	handWeld.Parent = handle

	model.Parent = character
	return model
end

function MjolnirFactory.throwAndReturn(character: Model, direction: Vector3, onComplete: (() -> ())?)
	local wield = MjolnirFactory.createWieldModel(character)
	if not wield then
		if onComplete then
			onComplete()
		end
		return
	end

	local handle = wield:FindFirstChild("Handle") :: BasePart?
	local hand = getRightHand(character)
	if not handle or not hand then
		wield:Destroy()
		if onComplete then
			onComplete()
		end
		return
	end

	for _, child in handle:GetChildren() do
		if child:IsA("WeldConstraint") and (child :: WeldConstraint).Part0 == hand then
			child:Destroy()
		end
	end

	local dir = if direction.Magnitude > 0 then direction.Unit else character:GetPivot().LookVector
	handle.AssemblyLinearVelocity = dir * 100

	task.delay(Constants.MJOLNIR_THROW_DURATION, function()
		if wield.Parent then
			wield:Destroy()
		end
		MjolnirFactory.createWieldModel(character)
		if onComplete then
			onComplete()
		end
	end)
end

function MjolnirFactory.cleanup(character: Model)
	local existing = character:FindFirstChild("MjolnirWield")
	if existing then
		existing:Destroy()
	end
end

return MjolnirFactory
