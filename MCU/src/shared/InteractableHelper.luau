--!strict
--[[ Interactable props: Attribute "Interactable" or a child named "Interactable". ]]

local InteractableHelper = {}

local function hasMark(inst: Instance): boolean
	if inst:GetAttribute("Interactable") then
		return true
	end
	return inst:FindFirstChild("Interactable") ~= nil
end

function InteractableHelper.hasMark(inst: Instance): boolean
	return hasMark(inst)
end

function InteractableHelper.resolveFromPart(part: BasePart, exclude: Model?): Instance?
	if exclude and part:IsDescendantOf(exclude) then
		return nil
	end
	local model = part:FindFirstAncestorOfClass("Model")
	if model and model ~= exclude then
		local hum = model:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			return nil
		end
		if hasMark(model) then
			return model
		end
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and hasMark(d) then
				return model
			end
		end
	end
	if hasMark(part) then
		return part
	end
	return nil
end

function InteractableHelper.raycast(
	origin: Vector3,
	direction: Vector3,
	range: number,
	exclude: Model?
): Instance?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if exclude then { exclude } else {}
	local result = workspace:Raycast(origin, direction.Unit * range, params)
	if not result then
		return nil
	end
	return InteractableHelper.resolveFromPart(result.Instance, exclude)
end

return InteractableHelper
