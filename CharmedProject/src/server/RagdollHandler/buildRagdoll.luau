local buildConstraints = require(script.Parent:WaitForChild("buildConstraints"))
local buildCollisionFilters = require(script.Parent:WaitForChild("buildCollisionFilters"))
local AUTO_ATTACHMENT_PREFIX = "__RagdollAutoAttachment_"

local function clearAutoAttachments(character: Model)
	for _, inst in ipairs(character:GetDescendants()) do
		if inst:IsA("Attachment") and string.sub(inst.Name, 1, #AUTO_ATTACHMENT_PREFIX) == AUTO_ATTACHMENT_PREFIX then
			inst:Destroy()
		end
	end
end

local function buildAttachmentMap(character: Model)
	local attachmentMap = {}
	local handledJoints: { [Motor6D]: boolean } = {}

	for _, part in pairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			for _, attachment in pairs(part:GetChildren()) do
				if attachment:IsA("Attachment") then
					local jointName = attachment.Name:match("^(.+)RigAttachment$")
					local joint = jointName and attachment.Parent:FindFirstChild(jointName) or nil
					if joint and joint:IsA("Motor6D") and joint.Part0 and joint.Part1 then
						local a0 = joint.Part0:FindFirstChild(attachment.Name)
						local a1 = joint.Part1:FindFirstChild(attachment.Name)
						if a0 and a1 and a0:IsA("Attachment") and a1:IsA("Attachment") then
							attachmentMap[attachment.Name] = {
								Joint = joint,
								Attachment0 = a0,
								Attachment1 = a1,
							}
							handledJoints[joint] = true
						end
					end
				end
			end
		end
	end

	-- Fallback for NPC/custom rigs without RigAttachments: synthesize attachments from Motor6D C0/C1.
	for _, inst in ipairs(character:GetDescendants()) do
		if inst:IsA("Motor6D") and inst.Part0 and inst.Part1 and not handledJoints[inst] then
			local key = AUTO_ATTACHMENT_PREFIX .. inst:GetFullName()
			local a0Name = AUTO_ATTACHMENT_PREFIX .. inst.Name
			local a1Name = AUTO_ATTACHMENT_PREFIX .. inst.Name

			local a0 = inst.Part0:FindFirstChild(a0Name)
			if not (a0 and a0:IsA("Attachment")) then
				a0 = Instance.new("Attachment")
				a0.Name = a0Name
				a0.Parent = inst.Part0
			end
			a0.CFrame = inst.C0

			local a1 = inst.Part1:FindFirstChild(a1Name)
			if not (a1 and a1:IsA("Attachment")) then
				a1 = Instance.new("Attachment")
				a1.Name = a1Name
				a1.Parent = inst.Part1
			end
			a1.CFrame = inst.C1

			attachmentMap[key] = {
				Joint = inst,
				Attachment0 = a0,
				Attachment1 = a1,
			}
		end
	end
	return attachmentMap
end

return function(humanoid: Humanoid)
	local character = humanoid.Parent
	if not character or not character:IsA("Model") then
		return
	end

	humanoid.BreakJointsOnDeath = false

	local old = character:FindFirstChild("RagdollConstraints")
	if old then
		old:Destroy()
	end
	clearAutoAttachments(character)

	local attachmentMap = buildAttachmentMap(character)
	local ragdollConstraints = buildConstraints(attachmentMap)
	local collisionFilters = buildCollisionFilters(attachmentMap, character.PrimaryPart)
	collisionFilters.Parent = ragdollConstraints
	ragdollConstraints.Parent = character
end
