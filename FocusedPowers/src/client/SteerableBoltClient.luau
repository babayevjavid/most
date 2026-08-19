--!strict
--[[
	Reusable steerable bolt client input (press fire, hold steer, release).
]]

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local SteerableBoltClient = {}

local function getMouseWorldPoint(camera: Camera, character: Model): Vector3
	local mousePos = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)
	local rp = RaycastParams.new()
	rp.FilterDescendantsInstances = { character }
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local result = workspace:Raycast(ray.Origin, ray.Direction * 1000, rp)
	if result then
		return result.Position
	end
	return ray.Origin + ray.Direction * 500
end

local function getBoltOrigin(character: Model): Vector3
	local head = character:FindFirstChild("Head") :: BasePart?
	if head then
		return (head.CFrame * CFrame.new(0, 0, -2)).Position
	end
	return character:GetPivot().Position
end

local function getAimDirection(character: Model, camera: Camera): Vector3
	local origin = getBoltOrigin(character)
	local target = getMouseWorldPoint(camera, character)
	local dir = target - origin
	if dir.Magnitude < 0.01 then
		return camera.CFrame.LookVector.Unit
	end
	return dir.Unit
end

export type BoltBinding = {
	abilityId: string,
	keyCode: Enum.KeyCode,
	hudKey: string,
	aimInterval: number,
	canUse: (player: Player, character: Model) -> boolean,
	startRemote: RemoteEvent,
	aimRemote: RemoteEvent,
	releaseRemote: RemoteEvent,
	setAbilityPressed: ((key: string, pressed: boolean) -> ())?,
}

function SteerableBoltClient.bind(player: Player, binding: BoltBinding)
	local held = false
	local steering = false
	local lastAimSend = 0

	RunService.Heartbeat:Connect(function()
		local char = player.Character
		if not char or not binding.canUse(player, char) then
			held = false
			steering = false
			if binding.setAbilityPressed then
				binding.setAbilityPressed(binding.hudKey, false)
			end
			return
		end

		local cam = workspace.CurrentCamera
		if not cam then
			return
		end

		local isDown = UserInputService:IsKeyDown(binding.keyCode)
		local now = tick()

		if isDown and not held then
			if binding.canUse(player, char) then
				local aim = getAimDirection(char, cam)
				binding.startRemote:FireServer(aim.X, aim.Y, aim.Z)
				steering = true
				lastAimSend = now
				if binding.setAbilityPressed then
					binding.setAbilityPressed(binding.hudKey, true)
				end
			end
			held = true
		elseif not isDown and held then
			if steering then
				binding.releaseRemote:FireServer()
				steering = false
			end
			held = false
			if binding.setAbilityPressed then
				binding.setAbilityPressed(binding.hudKey, false)
			end
		end

		if steering and isDown and now - lastAimSend >= binding.aimInterval then
			lastAimSend = now
			local aim = getAimDirection(char, cam)
			binding.aimRemote:FireServer(aim.X, aim.Y, aim.Z)
		end
	end)
end

return SteerableBoltClient
