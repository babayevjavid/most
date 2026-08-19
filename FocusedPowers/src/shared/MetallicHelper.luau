--!strict
--[[
	Ferrokinesis targets: child BoolValue named "Metal" with Value == true.
	Orbital / lance shard discovery uses material + legacy marks.
]]

local METAL_MATERIALS: { [Enum.Material]: boolean } = {
	[Enum.Material.Metal] = true,
	[Enum.Material.DiamondPlate] = true,
	[Enum.Material.CorrodedMetal] = true,
}

local function hasMetalBoolValue(inst: Instance): boolean
	local metal = inst:FindFirstChild("Metal")
	return metal ~= nil and metal:IsA("BoolValue") and metal.Value == true
end

local function partUsesMetalMaterial(part: BasePart): boolean
	return METAL_MATERIALS[part.Material] == true
end

local MetallicHelper = {}

function MetallicHelper.hasMetalBoolValue(inst: Instance): boolean
	return hasMetalBoolValue(inst)
end

function MetallicHelper.partUsesMetalMaterial(part: BasePart): boolean
	return partUsesMetalMaterial(part)
end

function MetallicHelper.isFerrokinesisTarget(part: BasePart, casterChar: Model?): boolean
	if casterChar and part:IsDescendantOf(casterChar) then
		return false
	end
	if hasMetalBoolValue(part) then
		return true
	end
	local model = part:FindFirstAncestorOfClass("Model")
	if model and model ~= casterChar then
		if hasMetalBoolValue(model) then
			return true
		end
		if model:GetAttribute("MetalLanceMagnetized") == true then
			return true
		end
	end
	return false
end

function MetallicHelper.modelIsLanceMagnetized(model: Model): boolean
	return model:GetAttribute("MetalLanceMagnetized") == true
end

local function attributeTruthy(value: unknown): boolean
	if value == nil then
		return false
	end
	if typeof(value) == "boolean" then
		return value
	end
	if typeof(value) == "number" then
		return value ~= 0
	end
	if typeof(value) == "string" then
		local lower = string.lower(value)
		return lower ~= "" and lower ~= "false" and lower ~= "0"
	end
	return true
end

local function hasMetallicMark(inst: Instance): boolean
	if attributeTruthy(inst:GetAttribute("Metallic")) then
		return true
	end
	if hasMetalBoolValue(inst) then
		return true
	end
	if inst:FindFirstChild("Metallic") ~= nil then
		return true
	end
	return false
end

function MetallicHelper.hasMetallicMark(inst: Instance): boolean
	return hasMetallicMark(inst)
end

function MetallicHelper.modelIsMetallic(model: Model): boolean
	if hasMetallicMark(model) then
		return true
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and (hasMetallicMark(d) or partUsesMetalMaterial(d)) then
			return true
		end
	end
	return false
end

function MetallicHelper.modelIsMetallicProp(model: Model): boolean
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 then
		return MetallicHelper.modelIsMetallic(model)
	end
	if hasMetallicMark(model) then
		return true
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and (hasMetallicMark(d) or partUsesMetalMaterial(d)) then
			return true
		end
	end
	return false
end

function MetallicHelper.getMetallicRoot(part: BasePart): BasePart
	return part.AssemblyRootPart or part
end

function MetallicHelper.partIsMetallicTarget(part: BasePart, casterChar: Model?): boolean
	if casterChar and part:IsDescendantOf(casterChar) then
		return false
	end
	local model = part:FindFirstAncestorOfClass("Model")
	if model and model ~= casterChar then
		local hum = model:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			return MetallicHelper.modelIsMetallic(model)
		end
		return MetallicHelper.modelIsMetallicProp(model)
	end
	return hasMetallicMark(part) or partUsesMetalMaterial(part)
end

local function isLivingHumanoidModel(model: Model?): boolean
	if not model then
		return false
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0
end

function MetallicHelper.findAmbientPropRoots(
	origin: Vector3,
	casterChar: Model,
	maxRange: number,
	maxCount: number,
	excludeRoots: { [BasePart]: boolean }?
): { BasePart }
	local overlapParams = OverlapParams.new()
	overlapParams.FilterDescendantsInstances = { casterChar }
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude

	local found: { BasePart } = {}
	local seen: { [BasePart]: boolean } = excludeRoots or {}

	for _, part in workspace:GetPartBoundsInRadius(origin, maxRange, overlapParams) do
		if not part:IsA("BasePart") then
			continue
		end
		if part:IsDescendantOf(casterChar) then
			continue
		end
		if (part.Position - origin).Magnitude > maxRange then
			continue
		end
		local model = part:FindFirstAncestorOfClass("Model")
		if isLivingHumanoidModel(model) then
			continue
		end
		if not MetallicHelper.partIsMetallicTarget(part, casterChar) then
			continue
		end
		local root = MetallicHelper.getMetallicRoot(part)
		if seen[root] or root:GetAttribute("FerrokinesisHeld") == true then
			continue
		end
		seen[root] = true
		table.insert(found, root)
	end

	table.sort(found, function(a: BasePart, b: BasePart)
		return (a.Position - origin).Magnitude < (b.Position - origin).Magnitude
	end)

	while #found > maxCount do
		table.remove(found)
	end

	return found
end

return MetallicHelper
