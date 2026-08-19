local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameHealth: any = nil
local shared = ReplicatedStorage:WaitForChild("Shared", 30)
if shared then
	local m = shared:FindFirstChild("GameHealth")
	if m then
		local ok, gh = pcall(require, m)
		if ok and type(gh) == "table" then
			GameHealth = gh
		end
	end
end

local FIREBALL_NAME = "InteractableFireball"
local SENDER_NAME = "FireballSender"
local FIREBALL_SPEED = 90
local FIREBALL_INTERVAL = 1.1
local FIREBALL_SIZE = Vector3.new(3, 3, 3)
local FIREBALL_LIFETIME = 5

local function buildFireball(origin: CFrame): BasePart
	local ball = Instance.new("Part")
	ball.Name = FIREBALL_NAME
	ball.Shape = Enum.PartType.Ball
	ball.Size = FIREBALL_SIZE
	ball.Material = Enum.Material.Neon
	ball.Color = Color3.fromRGB(255, 124, 36)
	ball.CanCollide = false
	ball.Anchored = false
	ball.CFrame = origin
	ball:SetAttribute("IsProjectile", true)

	local interactableTag = Instance.new("BoolValue")
	interactableTag.Name = "Interactable"
	interactableTag.Value = true
	interactableTag.Parent = ball

	local attachment = Instance.new("Attachment")
	attachment.Name = "ProjectileAttachment"
	attachment.Parent = ball

	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "ProjectileLinearVelocity"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.MaxForce = math.huge
	velocity.Enabled = true
	velocity.Parent = ball

	return ball
end

local function fireFromSender(sender: BasePart)
	local spawnCf = sender.CFrame + sender.CFrame.LookVector * ((sender.Size.Z * 0.5) + 1.2)
	local fireball = buildFireball(spawnCf)
	fireball.Parent = Workspace
	local linearVelocity = fireball:FindFirstChild("ProjectileLinearVelocity")
	if linearVelocity and linearVelocity:IsA("LinearVelocity") then
		linearVelocity.VectorVelocity = sender.CFrame.LookVector * FIREBALL_SPEED
	end
	local touched = false
	fireball.Touched:Connect(function(hit: BasePart)
		if touched or not fireball.Parent then
			return
		end
		local model = hit:FindFirstAncestorOfClass("Model")
		if not model then
			return
		end
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		local root = model:FindFirstChild("HumanoidRootPart")
		if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
			return
		end
		touched = true
		if GameHealth then
			GameHealth.applyDamage(humanoid, 20)
		else
			humanoid:TakeDamage(20)
		end
		local pushDir = sender.CFrame.LookVector
		root.AssemblyLinearVelocity = pushDir * 95 + Vector3.new(0, 20, 0)
		model:SetAttribute("Ragdolled", true)
		task.delay(2.5, function()
			if model.Parent and humanoid.Health > 0 and model:GetAttribute("Ragdolled") == true then
				model:SetAttribute("Ragdolled", false)
			end
		end)
		fireball:Destroy()
	end)
	Debris:AddItem(fireball, FIREBALL_LIFETIME)
end

task.spawn(function()
	while true do
		for _, instance in Workspace:GetDescendants() do
			if instance:IsA("BasePart") and instance.Name == SENDER_NAME then
				fireFromSender(instance)
			end
		end
		task.wait(FIREBALL_INTERVAL)
	end
end)
