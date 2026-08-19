--!strict

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

type PartSnapshot = {
	color: Color3,
	material: Enum.Material,
	reflectance: number,
}

local snapshots: { [Model]: { [BasePart]: PartSnapshot } } = {}

local PENANCE_COLOR = Color3.fromRGB(168, 22, 48)
local PENANCE_COLOR_DEEP = Color3.fromRGB(120, 10, 28)

local function isBodyPart(name: string): boolean
	return BODY_PART_NAMES[name] == true
end

local function getBodyParts(character: Model): { BasePart }
	local parts: { BasePart } = {}
	for _, desc in character:GetDescendants() do
		if desc:IsA("BasePart") and isBodyPart(desc.Name) then
			table.insert(parts, desc)
		end
	end
	return parts
end

function CharacterAppearanceHelper.cacheDefaults(character: Model)
	if snapshots[character] then
		return
	end
	local store: { [BasePart]: PartSnapshot } = {}
	for _, part in getBodyParts(character) do
		store[part] = {
			color = part.Color,
			material = part.Material,
			reflectance = part.Reflectance,
		}
	end
	snapshots[character] = store
end

function CharacterAppearanceHelper.clearCache(character: Model)
	snapshots[character] = nil
end

function CharacterAppearanceHelper.applyPenanceForm(character: Model)
	CharacterAppearanceHelper.cacheDefaults(character)
	local parts = getBodyParts(character)
	for index, part in parts do
		local tint = if index % 2 == 0 then PENANCE_COLOR else PENANCE_COLOR_DEEP
		part.Material = Enum.Material.Glass
		part.Color = tint
		part.Reflectance = 0.35
	end
end

function CharacterAppearanceHelper.applyMonetForm(character: Model)
	local store = snapshots[character]
	if not store then
		return
	end
	for part, snap in store do
		if part.Parent then
			part.Color = snap.color
			part.Material = snap.material
			part.Reflectance = snap.reflectance
		end
	end
end

function CharacterAppearanceHelper.applyFormAppearance(character: Model, form: "Monet" | "Penance")
	if form == "Penance" then
		CharacterAppearanceHelper.applyPenanceForm(character)
	else
		CharacterAppearanceHelper.applyMonetForm(character)
	end
end

return CharacterAppearanceHelper
