--!strict
--[[
	Environmental props: Attribute "Interactable" (truthy) or child named "Interactable".
]]

local function hasInteractableMark(inst: Instance): boolean
	if inst:GetAttribute("Interactable") then
		return true
	end
	if inst:FindFirstChild("Interactable") ~= nil then
		return true
	end
	return false
end

local InteractableHelper = {}

function InteractableHelper.hasInteractableMark(inst: Instance): boolean
	return hasInteractableMark(inst)
end

function InteractableHelper.modelIsInteractableProp(model: Model?): boolean
	if not model then
		return false
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 then
		return false
	end
	if hasInteractableMark(model) then
		return true
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and hasInteractableMark(d) then
			return true
		end
	end
	return false
end

function InteractableHelper.applyDamage(inst: Instance, amount: number): boolean
	local model = if inst:IsA("Model") then inst else inst:FindFirstAncestorOfClass("Model")
	local targets: { Instance } = {}
	if model and InteractableHelper.modelIsInteractableProp(model) then
		table.insert(targets, model)
	elseif inst:IsA("BasePart") and hasInteractableMark(inst) then
		table.insert(targets, inst)
	elseif model and hasInteractableMark(model) then
		table.insert(targets, model)
	end

	for _, target in targets do
		local health = target:GetAttribute("Health")
		if typeof(health) == "number" then
			local newHealth = health - amount
			target:SetAttribute("Health", newHealth)
			if newHealth <= 0 then
				target:Destroy()
			end
			return true
		end
	end
	return false
end

return InteractableHelper
