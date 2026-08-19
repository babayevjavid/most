--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local PropHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PropHelper"))

local TargetingHelper = {}

local CURSOR_HITBOX_PIXELS = 80

local function getScreenPosition(customPos: Vector2?): Vector2
	if customPos then
		return customPos
	end
	local mouse = UserInputService:GetMouseLocation()
	return Vector2.new(mouse.X, mouse.Y)
end

local function findBestTargetFromScreen(
	character: Model,
	screenPos: Vector2,
	maxRange: number,
	includeObjects: boolean,
	filterFunc: ((Model) -> boolean)?
): (BasePart?, Model?)
	local casterRoot = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not casterRoot then
		return nil, nil
	end

	local cam = workspace.CurrentCamera
	if not cam then
		return nil, nil
	end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterDescendantsInstances = { character }
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude

	local partsInRange = workspace:GetPartBoundsInRadius(casterRoot.Position, maxRange, overlapParams)

	local bestPart: BasePart? = nil
	local bestModel: Model? = nil
	local bestScreenDist = math.huge
	local checkedModels: { [Model]: boolean } = {}

	for _, part in partsInRange do
		if not part:IsA("BasePart") then
			continue
		end

		local model = part:FindFirstAncestorOfClass("Model")
		if model and model ~= character then
			if not checkedModels[model] then
				checkedModels[model] = true
				local humanoid = model:FindFirstChildOfClass("Humanoid")
				if humanoid and humanoid.Health > 0 then
					local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
					if root then
						if filterFunc and not filterFunc(model) then
							continue
						end
						local worldPos, onScreen = cam:WorldToScreenPoint(root.Position)
						if onScreen then
							local screenPos2D = Vector2.new(worldPos.X, worldPos.Y)
							local screenDist = (screenPos2D - screenPos).Magnitude
							if screenDist < CURSOR_HITBOX_PIXELS and screenDist < bestScreenDist then
								bestScreenDist = screenDist
								bestPart = root
								bestModel = model
							end
						end
						continue
					end
				end
			else
				continue
			end
		end

		if includeObjects and PropHelper.isProp(part) then
			local worldPos, onScreen = cam:WorldToScreenPoint(part.Position)
			if onScreen then
				local screenPos2D = Vector2.new(worldPos.X, worldPos.Y)
				local screenDist = (screenPos2D - screenPos).Magnitude
				if screenDist < CURSOR_HITBOX_PIXELS and screenDist < bestScreenDist then
					bestScreenDist = screenDist
					bestPart = part
					bestModel = nil
				end
			end
		end
	end

	return bestPart, bestModel
end

function TargetingHelper.getTargetPartAtCursor(character: Model, maxRange: number, filterFunc: ((Model) -> boolean)?): BasePart?
	local screenPos = getScreenPosition(nil)
	local part, _ = findBestTargetFromScreen(character, screenPos, maxRange, true, filterFunc)
	return part
end

function TargetingHelper.getCursorWorldPos(maxRange: number): Vector3?
	local cam = workspace.CurrentCamera
	if not cam then
		return nil
	end
	local mousePos = UserInputService:GetMouseLocation()
	local ray = cam:ViewportPointToRay(mousePos.X, mousePos.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local character = cam.CameraSubject
	if character and character:IsA("Humanoid") then
		local charModel = character.Parent
		if charModel and charModel:IsA("Model") then
			params.FilterDescendantsInstances = { charModel }
		end
	end
	local result = workspace:Raycast(ray.Origin, ray.Direction * maxRange, params)
	if result then
		return result.Position
	end
	return ray.Origin + ray.Direction * maxRange
end

return TargetingHelper
