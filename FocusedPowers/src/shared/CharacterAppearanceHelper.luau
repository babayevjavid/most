--!strict
--[[
	Apply hero-specific body colors to live characters.
]]

local CharacterAppearanceHelper = {}

local BODY_PART_NAMES: { [string]: boolean } = {
	Head = true,
	Torso = true,
	UpperTorso = true,
	LowerTorso = true,
	LeftArm = true,
	RightArm = true,
	LeftLeg = true,
	RightLeg = true,
	LeftUpperArm = true,
	LeftLowerArm = true,
	LeftHand = true,
	RightUpperArm = true,
	RightLowerArm = true,
	RightHand = true,
	LeftUpperLeg = true,
	LeftLowerLeg = true,
	LeftFoot = true,
	RightUpperLeg = true,
	RightLowerLeg = true,
	RightFoot = true,
}

function CharacterAppearanceHelper.applyBodyColor(character: Model, color: Color3)
	local bodyColors = character:FindFirstChildOfClass("BodyColors")
	if bodyColors then
		bodyColors.HeadColor3 = color
		bodyColors.TorsoColor3 = color
		bodyColors.LeftArmColor3 = color
		bodyColors.RightArmColor3 = color
		bodyColors.LeftLegColor3 = color
		bodyColors.RightLegColor3 = color
	end

	for _, desc in character:GetDescendants() do
		if desc:IsA("BasePart") and BODY_PART_NAMES[desc.Name] then
			desc.Color = color
		end
	end
end

function CharacterAppearanceHelper.applyHeroAppearance(_character: Model, _characterId: string)
end

return CharacterAppearanceHelper
