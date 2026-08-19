--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConstants = require(script.Parent.GameConstants)

local MorphAnimationHelper = {}

local MALE_MORPH_NAMES: { [string]: boolean } = {
	SpiderMan = true,
	Cyclops = true,
	BlueMarvel = true,
	HumanTorchClassic = true,
	HumanTorchModern = true,
	Loki = true,
	Iceman = true,
}

local function assetId(id: string): string
	if string.sub(id, 1, 13) == "rbxassetid://" then
		return id
	end
	return "rbxassetid://" .. id
end

local function setAnimationId(inst: Instance, id: string)
	local full = assetId(id)
	if inst:IsA("Animation") then
		inst.AnimationId = full
	elseif inst:IsA("StringValue") then
		if inst.Value == "" or string.find(inst.Value, "asset", 1, true) or string.find(inst.Value, "%d") then
			inst.Value = full
		end
	end
end

local function categoryKind(name: string): "idle" | "walk" | "run" | nil
	local lower = string.lower(name)
	if lower == "idle" then
		return "idle"
	end
	if lower == "walk" or lower == "walkanim" then
		return "walk"
	end
	if lower == "run" or lower == "runanim" then
		return "run"
	end
	return nil
end

local function applyToAnimate(animate: Instance, idleId: string, walkId: string, runId: string)
	local function applyNode(node: Instance, kind: "idle" | "walk" | "run")
		local id = idleId
		if kind == "walk" then
			id = walkId
		elseif kind == "run" then
			id = runId
		end
		setAnimationId(node, id)
		for _, child in node:GetChildren() do
			if child:IsA("Animation") or child:IsA("StringValue") then
				setAnimationId(child, id)
			end
			for _, nested in child:GetChildren() do
				if nested:IsA("Animation") then
					setAnimationId(nested, id)
				end
			end
		end
	end

	for _, child in animate:GetChildren() do
		local kind = categoryKind(child.Name)
		if kind then
			applyNode(child, kind)
		end
	end
end

function MorphAnimationHelper.idleIdForMorphName(morphName: string): string
	if string.find(morphName, "JeanGrey", 1, true) then
		return GameConstants.JEAN_IDLE_ANIM
	end
	if string.find(morphName, "InvisibleWoman", 1, true) then
		return GameConstants.IW_IDLE_ANIM
	end
	if MALE_MORPH_NAMES[morphName] then
		return GameConstants.MALE_IDLE_ANIM
	end
	return GameConstants.BASIC_IDLE_ANIM
end

function MorphAnimationHelper.applyToModel(model: Instance, idleId: string?)
	local animate = model:FindFirstChild("Animate")
	if not animate then
		return
	end
	local idle = idleId or MorphAnimationHelper.idleIdForMorphName(model.Name)
	applyToAnimate(animate, idle, GameConstants.LOCOMOTION_ANIM, GameConstants.LOCOMOTION_ANIM)
end

function MorphAnimationHelper.patchAssets()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		return
	end
	local starter = assets:FindFirstChild("StarterCharacter")
	if starter then
		MorphAnimationHelper.applyToModel(starter, GameConstants.BASIC_IDLE_ANIM)
	end
	local morphs = assets:FindFirstChild("Morphs")
	if morphs then
		for _, child in morphs:GetChildren() do
			MorphAnimationHelper.applyToModel(child, MorphAnimationHelper.idleIdForMorphName(child.Name))
		end
	end
	local iw = assets:FindFirstChild("InvisibleWoman")
	if iw then
		local invisMorph = iw:FindFirstChild("InvisibilityMorph")
		if invisMorph then
			MorphAnimationHelper.applyToModel(invisMorph, GameConstants.IW_IDLE_ANIM)
		end
	end
end

return MorphAnimationHelper
