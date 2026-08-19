--!strict
--[[
	Targeting for telekinesis: mouse raycast first, screen-space fallback.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local InteractableHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("InteractableHelper"))

local TargetingHelper = {}

local CURSOR_HITBOX_PIXELS = 80

local function getScreenPosition(customPos: Vector2?): Vector2
	if customPos then
		return customPos
	end
	local mouse = UserInputService:GetMouseLocation()
	return Vector2.new(mouse.X, mouse.Y)
end

local function isValidTelekinesisPart(part: BasePart, character: Model, casterRoot: BasePart, maxRange: number): BasePart?
	if part:IsDescendantOf(character) then
		return nil
	end
	if (part.Position - casterRoot.Position).Magnitude > maxRange then
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
		if InteractableHelper.modelIsInteractableProp(model) then
			return part.AssemblyRootPart or part
		end
	end

	if InteractableHelper.hasInteractableMark(part) then
		return part.AssemblyRootPart or part
	end

	return nil
end

local function findBestTargetFromScreen(
	character: Model,
	screenPos: Vector2,
	maxRange: number
): BasePart?
	local casterRoot = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not casterRoot then
		return nil
	end

	local cam = workspace.CurrentCamera
	if not cam then
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

		local resolved = isValidTelekinesisPart(part, character, casterRoot, maxRange)
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
		local screenPos2D = Vector2.new(worldPos.X, worldPos.Y)
		local screenDist = (screenPos2D - screenPos).Magnitude
		if screenDist < CURSOR_HITBOX_PIXELS and screenDist < bestScreenDist then
			bestScreenDist = screenDist
			bestPart = resolved
		end
	end

	return bestPart
end

local function findTargetFromRaycast(character: Model, maxRange: number): BasePart?
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

	return isValidTelekinesisPart(result.Instance :: BasePart, character, casterRoot, maxRange)
end

function TargetingHelper.getTargetPartAtCursor(character: Model, maxRange: number, exclude: { BasePart }?): BasePart?
	local excludeSet: { [BasePart]: boolean } = {}
	if exclude then
		for _, part in exclude do
			excludeSet[part] = true
		end
	end

	local function accept(part: BasePart?): BasePart?
		if not part or excludeSet[part] then
			return nil
		end
		return part
	end

	local rayTarget = accept(findTargetFromRaycast(character, maxRange))
	if rayTarget then
		return rayTarget
	end
	return accept(findBestTargetFromScreen(character, getScreenPosition(nil), maxRange))
end

function TargetingHelper.getHighlightAdornee(part: BasePart): Instance
	local model = part:FindFirstAncestorOfClass("Model")
	if model then
		local hum = model:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			return model
		end
		if InteractableHelper.modelIsInteractableProp(model) then
			return model
		end
	end
	return part
end

return TargetingHelper
