--!strict
--[[ Cursor targeting for metallic props and metallic humanoids. ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local MetallicHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MetallicHelper"))

local MetallicTargetingHelper = {}

local CURSOR_HITBOX_PIXELS = 80

local function isValidMetallicPart(part: BasePart, character: Model, casterRoot: BasePart, maxRange: number): BasePart?
	if part:IsDescendantOf(character) then
		return nil
	end
	if (part.Position - casterRoot.Position).Magnitude > maxRange then
		return nil
	end
	if not MetallicHelper.isFerrokinesisTarget(part, character) then
		return nil
	end
	local model = part:FindFirstAncestorOfClass("Model")
	if model and model ~= character then
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				return root
			end
		end
	end
	return MetallicHelper.getMetallicRoot(part)
end

local function findBestFromScreen(character: Model, screenPos: Vector2, maxRange: number): BasePart?
	local casterRoot = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local cam = workspace.CurrentCamera
	if not casterRoot or not cam then
		return nil
	end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterDescendantsInstances = { character }
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude

	local partsInRange = workspace:GetPartBoundsInRadius(casterRoot.Position, maxRange, overlapParams)
	local bestPart: BasePart? = nil
	local bestScreenDist = math.huge
	local checkedModels: { [Model]: boolean } = {}

	for _, part in partsInRange do
		if not part:IsA("BasePart") then
			continue
		end
		local resolved = isValidMetallicPart(part, character, casterRoot, maxRange)
		if not resolved then
			continue
		end
		local model = resolved:FindFirstAncestorOfClass("Model")
		if model and model ~= character then
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				if checkedModels[model] then
					continue
				end
				checkedModels[model] = true
			end
		end
		local worldPos, onScreen = cam:WorldToScreenPoint(resolved.Position)
		if not onScreen then
			continue
		end
		local screenDist = (Vector2.new(worldPos.X, worldPos.Y) - screenPos).Magnitude
		if screenDist < CURSOR_HITBOX_PIXELS and screenDist < bestScreenDist then
			bestScreenDist = screenDist
			bestPart = resolved
		end
	end
	return bestPart
end

local function findFromRaycast(character: Model, maxRange: number): BasePart?
	local casterRoot = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local cam = workspace.CurrentCamera
	if not casterRoot or not cam then
		return nil
	end
	local mousePos = UserInputService:GetMouseLocation()
	local ray = cam:ViewportPointToRay(mousePos.X, mousePos.Y)
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { character }
	params.FilterType = Enum.RaycastFilterType.Exclude
	local result = workspace:Raycast(ray.Origin, ray.Direction.Unit * maxRange, params)
	if not result or not result.Instance:IsA("BasePart") then
		return nil
	end
	return isValidMetallicPart(result.Instance :: BasePart, character, casterRoot, maxRange)
end

local function findAmbientFromCharacter(character: Model, maxRange: number, maxCount: number): { BasePart }
	local casterRoot = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not casterRoot then
		return {}
	end
	return MetallicHelper.findAmbientPropRoots(casterRoot.Position, character, maxRange, maxCount, nil)
end

function MetallicTargetingHelper.countAmbientMetallicInRange(character: Model, maxRange: number, maxCount: number): number
	return #findAmbientFromCharacter(character, maxRange, maxCount)
end

function MetallicTargetingHelper.findAmbientMetallicRoots(character: Model, maxRange: number, maxCount: number): { BasePart }
	return findAmbientFromCharacter(character, maxRange, maxCount)
end

function MetallicTargetingHelper.getTargetPartAtCursor(character: Model, maxRange: number): BasePart?
	local rayTarget = findFromRaycast(character, maxRange)
	if rayTarget then
		return rayTarget
	end
	local mouse = UserInputService:GetMouseLocation()
	return findBestFromScreen(character, Vector2.new(mouse.X, mouse.Y), maxRange)
end

function MetallicTargetingHelper.getHighlightAdornee(part: BasePart): Instance
	local model = part:FindFirstAncestorOfClass("Model")
	if model then
		local hum = model:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			return model
		end
		if MetallicHelper.modelIsMetallicProp(model) then
			return model
		end
	end
	return part
end

function MetallicTargetingHelper.getHumanoidTargetAtCursor(character: Model, maxRange: number): Model?
	local casterRoot = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local cam = workspace.CurrentCamera
	if not casterRoot or not cam then
		return nil
	end

	local function isValidHumanoidModel(model: Model): Model?
		if model == character then
			return nil
		end
		local hum = model:FindFirstChildOfClass("Humanoid")
		local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hum or hum.Health <= 0 or not root then
			return nil
		end
		if (root.Position - casterRoot.Position).Magnitude > maxRange then
			return nil
		end
		return model
	end

	local mousePos = UserInputService:GetMouseLocation()
	local ray = cam:ViewportPointToRay(mousePos.X, mousePos.Y)
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { character }
	params.FilterType = Enum.RaycastFilterType.Exclude
	local result = workspace:Raycast(ray.Origin, ray.Direction.Unit * maxRange, params)
	if result and result.Instance:IsA("BasePart") then
		local model = (result.Instance :: BasePart):FindFirstAncestorOfClass("Model")
		if model then
			local valid = isValidHumanoidModel(model)
			if valid then
				return valid
			end
		end
	end

	local bestModel: Model? = nil
	local bestScreenDist = math.huge
	local checked: { [Model]: boolean } = {}

	local overlapParams = OverlapParams.new()
	overlapParams.FilterDescendantsInstances = { character }
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude

	for _, part in workspace:GetPartBoundsInRadius(casterRoot.Position, maxRange, overlapParams) do
		if not part:IsA("BasePart") then
			continue
		end
		local model = part:FindFirstAncestorOfClass("Model")
		if not model or checked[model] then
			continue
		end
		checked[model] = true
		local valid = isValidHumanoidModel(model)
		if not valid then
			continue
		end
		local root = valid:FindFirstChild("HumanoidRootPart") :: BasePart
		local worldPos, onScreen = cam:WorldToScreenPoint(root.Position)
		if not onScreen then
			continue
		end
		local screenDist = (Vector2.new(worldPos.X, worldPos.Y) - mousePos).Magnitude
		if screenDist < CURSOR_HITBOX_PIXELS and screenDist < bestScreenDist then
			bestScreenDist = screenDist
			bestModel = valid
		end
	end

	return bestModel
end

return MetallicTargetingHelper
