--!strict
-- Parts named "ProjectileThrower" fire Wanda-style hex bolts forward for shield testing.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConstants = require(ReplicatedStorage.Shared.GameConstants)
local ProjectileHelper = require(ReplicatedStorage.Shared.ProjectileHelper)
local VfxHelper = require(ReplicatedStorage.Shared.VfxHelper)

local ProjectileThrowerService = {}

local tracked: { [BasePart]: number } = {} -- part → next fire time
local ownerModel: Model? = nil

local function getOrCreateOwner(): Model
	if ownerModel and ownerModel.Parent then
		return ownerModel
	end
	local model = Instance.new("Model")
	model.Name = "ProjectileThrowerOwner"
	local hum = Instance.new("Humanoid")
	hum.MaxHealth = 99999
	hum.Health = 99999
	hum.Parent = model
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(1, 1, 1)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.Parent = model
	model.PrimaryPart = root
	model.Parent = Workspace
	ownerModel = model
	return model
end

local function fireFrom(part: BasePart)
	local owner = getOrCreateOwner()
	local ownerRoot = owner:FindFirstChild("HumanoidRootPart") :: BasePart?
	if ownerRoot then
		ownerRoot.CFrame = part.CFrame
	end
	local look = part.CFrame.LookVector
	local dir = if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1)
	local origin = part.Position + dir * (part.Size.Z * 0.5 + 0.5)
	ProjectileHelper.spawn(origin, dir, {
		speed = GameConstants.HEX_BLAST_SPEED,
		damage = GameConstants.PROJECTILE_THROWER_DAMAGE,
		radius = GameConstants.HEX_BLAST_RADIUS * 0.35,
		maxDistance = GameConstants.HEX_BLAST_RANGE,
		owner = owner,
		color = VfxHelper.chaosColor(),
	})
	VfxHelper.castHandFlash(origin, VfxHelper.chaosColor())
end

local function track(part: BasePart)
	if tracked[part] then
		return
	end
	tracked[part] = os.clock() + 0.4
	part.AncestryChanged:Connect(function(_, parent)
		if not parent then
			tracked[part] = nil
		end
	end)
end

local function scan(root: Instance)
	for _, desc in root:GetDescendants() do
		if desc:IsA("BasePart") and desc.Name == "ProjectileThrower" then
			track(desc)
		end
	end
end

function ProjectileThrowerService.update(_dt: number)
	local now = os.clock()
	for part, nextFire in tracked do
		if not part.Parent then
			tracked[part] = nil
			continue
		end
		if now < nextFire then
			continue
		end
		tracked[part] = now + GameConstants.PROJECTILE_THROWER_INTERVAL
		fireFrom(part)
	end
end

function ProjectileThrowerService.init()
	scan(Workspace)
	Workspace.DescendantAdded:Connect(function(inst)
		if inst:IsA("BasePart") and inst.Name == "ProjectileThrower" then
			track(inst)
		end
	end)
end

return ProjectileThrowerService
