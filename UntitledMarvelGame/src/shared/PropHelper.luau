--!strict

local PropHelper = {}

local function getModel(inst: Instance): Model?
	if inst:IsA("Model") then
		return inst
	end
	return inst:FindFirstAncestorOfClass("Model")
end

function PropHelper.isProp(inst: Instance): boolean
	if inst:FindFirstChild("Prop") and inst:FindFirstChild("Prop"):IsA("BoolValue") then
		return true
	end

	local model = getModel(inst)
	if not model then
		return false
	end
	local mark = model:FindFirstChild("Prop")
	return mark ~= nil and mark:IsA("BoolValue")
end

function PropHelper.getPropRoot(inst: Instance): BasePart?
	if inst:IsA("BasePart") then
		return inst
	end
	local model = getModel(inst)
	if not model then
		return nil
	end
	if model.PrimaryPart then
		return model.PrimaryPart
	end
	return model:FindFirstChildWhichIsA("BasePart", true)
end

return PropHelper
