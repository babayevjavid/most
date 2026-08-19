--!strict

local ConstraintHelper = {}

export type MoverBundle = {
	attachment: Attachment,
	linearVelocity: LinearVelocity,
	vectorForce: VectorForce?,
	alignOrientation: AlignOrientation?,
}

local function getOrCreateAttachment(root: BasePart): Attachment
	local att = root:FindFirstChild("HeroMoverAttachment")
	if att and att:IsA("Attachment") then
		return att
	end
	local created = Instance.new("Attachment")
	created.Name = "HeroMoverAttachment"
	created.Parent = root
	return created
end

function ConstraintHelper.createMover(root: BasePart, withAlign: boolean?, withGravityCancel: boolean?): MoverBundle
	local att = getOrCreateAttachment(root)

	local linearVel = Instance.new("LinearVelocity")
	linearVel.Name = "HeroLinearVelocity"
	linearVel.Attachment0 = att
	linearVel.MaxForce = math.huge
	linearVel.RelativeTo = Enum.ActuatorRelativeTo.World
	linearVel.VectorVelocity = Vector3.zero
	linearVel.Parent = root

	local vectorForce: VectorForce? = nil
	if withGravityCancel then
		vectorForce = Instance.new("VectorForce")
		vectorForce.Name = "HeroGravityCancel"
		vectorForce.Attachment0 = att
		vectorForce.Force = Vector3.new(0, root.AssemblyMass * workspace.Gravity, 0)
		vectorForce.RelativeTo = Enum.ActuatorRelativeTo.World
		vectorForce.Parent = root
	end

	local align: AlignOrientation? = nil
	if withAlign then
		align = Instance.new("AlignOrientation")
		align.Name = "HeroAlignOrientation"
		align.Attachment0 = att
		align.Mode = Enum.OrientationAlignmentMode.OneAttachment
		align.MaxTorque = math.huge
		align.Responsiveness = 18
		align.CFrame = root.CFrame
		align.Parent = root
	end

	return {
		attachment = att,
		linearVelocity = linearVel,
		vectorForce = vectorForce,
		alignOrientation = align,
	}
end

function ConstraintHelper.destroyMover(bundle: MoverBundle?)
	if not bundle then
		return
	end
	for _, inst in { bundle.linearVelocity, bundle.vectorForce, bundle.alignOrientation } do
		if inst and inst.Parent then
			inst:Destroy()
		end
	end
end

local function muteLocomotionSounds(character: Model?, muted: boolean)
	if not character then
		return
	end
	for _, desc in character:GetDescendants() do
		if desc:IsA("Sound") then
			local name = string.lower(desc.Name)
			if name == "running" or name == "climbing" or name == "freesound" or name:find("run", 1, true) then
				if muted then
					if desc:GetAttribute("HeroOrigVolume") == nil then
						desc:SetAttribute("HeroOrigVolume", desc.Volume)
					end
					desc:Stop()
					desc.Volume = 0
					desc.Playing = false
				else
					local orig = desc:GetAttribute("HeroOrigVolume")
					if type(orig) == "number" then
						desc.Volume = orig
						desc:SetAttribute("HeroOrigVolume", nil)
					end
				end
			end
		end
	end
end

function ConstraintHelper.lockHumanoidForAbility(humanoid: Humanoid)
	humanoid:SetAttribute("HeroAbilityLocked", true)
	if humanoid:GetAttribute("HeroOrigWalkSpeed") == nil then
		humanoid:SetAttribute("HeroOrigWalkSpeed", humanoid.WalkSpeed)
	end
	humanoid.PlatformStand = true
	humanoid.AutoRotate = false
	humanoid.WalkSpeed = 0
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Running, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, true)
	muteLocomotionSounds(humanoid.Parent :: Model?, true)
end

function ConstraintHelper.unlockHumanoid(humanoid: Humanoid)
	humanoid:SetAttribute("HeroAbilityLocked", nil)
	humanoid.PlatformStand = false
	humanoid.AutoRotate = true
	local origSpeed = humanoid:GetAttribute("HeroOrigWalkSpeed")
	if type(origSpeed) == "number" then
		humanoid.WalkSpeed = origSpeed
		humanoid:SetAttribute("HeroOrigWalkSpeed", nil)
	end
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Running, true)
	muteLocomotionSounds(humanoid.Parent :: Model?, false)
	-- Don't force Freefall on a dead body (breaks death ragdoll / reset cleanup)
	if humanoid.Health > 0 then
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	end
end

function ConstraintHelper.muteLocomotionSounds(character: Model, muted: boolean)
	muteLocomotionSounds(character, muted)
end

return ConstraintHelper
