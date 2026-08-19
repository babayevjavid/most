--!strict
--[[
	Shared client helpers for ability aiming.
]]

local UserInputService = game:GetService("UserInputService")

local AbilityInputHelper = {}

function AbilityInputHelper.getMouseWorldPoint(camera: Camera, character: Model): Vector3
	local mousePos = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { character }
	params.FilterType = Enum.RaycastFilterType.Exclude
	local result = workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
	if result then
		return result.Position
	end
	return ray.Origin + ray.Direction * 500
end

function AbilityInputHelper.getAimDirection(character: Model, camera: Camera): Vector3
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local origin = if root then root.Position else character:GetPivot().Position
	local target = AbilityInputHelper.getMouseWorldPoint(camera, character)
	local dir = target - origin
	if dir.Magnitude < 0.01 then
		return camera.CFrame.LookVector.Unit
	end
	return dir.Unit
end

function AbilityInputHelper.getPlayerUnderMouse(excludeCharacter: Model, mouse: Mouse): Player?
	local unitRay = mouse.UnitRay
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { excludeCharacter }
	local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 500, params)
	if not result then
		return nil
	end
	local model = result.Instance:FindFirstAncestorOfClass("Model")
	if not model then
		return nil
	end
	local Players = game:GetService("Players")
	for _, plr in Players:GetPlayers() do
		if plr.Character == model then
			return plr
		end
	end
	return nil
end

return AbilityInputHelper
