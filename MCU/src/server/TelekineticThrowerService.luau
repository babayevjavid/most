--!strict
--[[
	Parts named "TelekineticThrower" on Workspace:
	On touch → TK particles on the character, then throw after 1s.
	Used to test Loki Reflect Shield against telekinesis-style attacks.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConstants = require(ReplicatedStorage.Shared.GameConstants)
local PushHelper = require(ReplicatedStorage.Shared.PushHelper)
local RagdollStatus = require(ReplicatedStorage.Shared.RagdollStatus)
local VfxHelper = require(ReplicatedStorage.Shared.VfxHelper)
local LokiService = require(script.Parent.LokiService)

local TelekineticThrowerService = {}

local tracked: { [BasePart]: boolean } = {}
local busy: { [Model]: boolean } = {}
local ownerModel: Model? = nil

local function getOrCreateOwner(): Model
	if ownerModel and ownerModel.Parent then
		return ownerModel
	end
	local model = Instance.new("Model")
	model.Name = "TelekineticThrowerOwner"
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

local function getCharacterFromPart(part: BasePart): Model?
	local current: Instance? = part
	while current do
		if current:IsA("Model") then
			local hum = current:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				return current
			end
		end
		current = current.Parent
	end
	return nil
end

local function processVictim(thrower: BasePart, victim: Model)
	if busy[victim] then
		return
	end
	if victim:GetAttribute("LokiUltClone") == true or victim:GetAttribute("LokiDecoy") == true then
		return
	end
	local hum = victim:FindFirstChildOfClass("Humanoid")
	local root = victim:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or not root or hum.Health <= 0 then
		return
	end

	busy[victim] = true
	local owner = getOrCreateOwner()
	local ownerRoot = owner:FindFirstChild("HumanoidRootPart") :: BasePart?
	if ownerRoot then
		ownerRoot.CFrame = thrower.CFrame
	end

	-- Reflect test: Loki shield reflects telekinesis onto the thrower owner
	if LokiService.tryReflect(owner, victim, "telekinesis") then
		busy[victim] = nil
		return
	end

	local particles = VfxHelper.attachTelekinesisParticles(victim)
	victim:SetAttribute("TelekinesisHeld", true)

	-- Light lift while held
	local liftAtt = Instance.new("Attachment")
	liftAtt.Name = "TKThrowerLiftAtt"
	liftAtt.Parent = root
	local align = Instance.new("AlignPosition")
	align.Name = "TKThrowerAlign"
	align.Mode = Enum.PositionAlignmentMode.OneAttachment
	align.Attachment0 = liftAtt
	align.Position = root.Position + Vector3.new(0, 4, 0)
	align.Responsiveness = 25
	align.MaxForce = 1e5
	align.MaxVelocity = 40
	align.Parent = root

	task.delay(1, function()
		if align.Parent then
			align:Destroy()
		end
		if liftAtt.Parent then
			liftAtt:Destroy()
		end
		victim:SetAttribute("TelekinesisHeld", nil)
		VfxHelper.fadeOutAndDestroyParticles(particles, 0.35, 3)

		if not victim.Parent or not root.Parent or hum.Health <= 0 then
			busy[victim] = nil
			return
		end

		-- Second chance reflect at throw time
		if LokiService.tryReflect(owner, victim, "telekinesis") then
			busy[victim] = nil
			return
		end

		local away = root.Position - thrower.Position
		local dir = if away.Magnitude > 0.05 then away.Unit else thrower.CFrame.LookVector
		RagdollStatus.applyTimed(victim, GameConstants.RAGDOLL_TK_THROW_DURATION)
		PushHelper.applyToCharacter(victim, dir, {
			speed = GameConstants.TK_THROW_SPEED,
			upBoost = GameConstants.TK_THROW_UP,
		})
		busy[victim] = nil
	end)
end

local function track(part: BasePart)
	if tracked[part] then
		return
	end
	tracked[part] = true
	part.Touched:Connect(function(other)
		if not other:IsA("BasePart") then
			return
		end
		local victim = getCharacterFromPart(other)
		if victim then
			processVictim(part, victim)
		end
	end)
	part.AncestryChanged:Connect(function(_, parent)
		if not parent then
			tracked[part] = nil
		end
	end)
end

local function scan(root: Instance)
	for _, desc in root:GetDescendants() do
		if desc:IsA("BasePart") and desc.Name == "TelekineticThrower" then
			track(desc)
		end
	end
end

function TelekineticThrowerService.update(_dt: number)
	-- Touch-driven; nothing per-frame
end

function TelekineticThrowerService.init()
	scan(Workspace)
	Workspace.DescendantAdded:Connect(function(inst)
		if inst:IsA("BasePart") and inst.Name == "TelekineticThrower" then
			track(inst)
		end
	end)
end

return TelekineticThrowerService
