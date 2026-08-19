--!strict

local MouseHelper = {}

function MouseHelper.getWorldDirection(player: Player, depth: number?): Vector3
	local camera = workspace.CurrentCamera
	if not camera then
		return Vector3.new(0, 0, -1)
	end
	local mouse = player:GetMouse()
	local unitRay = camera:ScreenPointToRay(mouse.X, mouse.Y)
	local dist = depth or 200
	return unitRay.Direction
end

function MouseHelper.getFlattenedDirection(player: Player): Vector3
	local dir = MouseHelper.getWorldDirection(player)
	local flat = Vector3.new(dir.X, 0, dir.Z)
	if flat.Magnitude < 0.01 then
		return Vector3.new(0, 0, -1)
	end
	return flat.Unit
end

return MouseHelper
