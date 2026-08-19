local buildConstraints = require(script.Parent:WaitForChild("buildConstraints"))
local buildCollisionFilters = require(script.Parent:WaitForChild("buildCollisionFilters"))

local function buildAttachmentMap(character: Model)
	local attachmentMap = {}
	for _, part in pairs(character:GetChildren()) do
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
						end
					end
				end
			end
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

	local attachmentMap = buildAttachmentMap(character)
	local ragdollConstraints = buildConstraints(attachmentMap)
	local collisionFilters = buildCollisionFilters(attachmentMap, character.PrimaryPart)
	collisionFilters.Parent = ragdollConstraints
	ragdollConstraints.Parent = character
end

