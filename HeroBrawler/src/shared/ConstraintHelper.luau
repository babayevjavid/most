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

function ConstraintHelper.lockHumanoidForAbility(humanoid: Humanoid)
	humanoid:SetAttribute("HeroAbilityLocked", true)
	humanoid.PlatformStand = true
	humanoid.AutoRotate = false
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Running, false)
end

function ConstraintHelper.unlockHumanoid(humanoid: Humanoid)
	humanoid:SetAttribute("HeroAbilityLocked", nil)
	humanoid.PlatformStand = false
	humanoid.AutoRotate = true
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Running, true)
	humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
end

return ConstraintHelper
