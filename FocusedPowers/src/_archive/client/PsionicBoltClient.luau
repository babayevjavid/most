--!strict
--[[
	Psionic Bolt (Q): instant fire on press; hold steers in-flight bolt.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local AbilityGateHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityGateHelper"))
local PsionicBoltConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PsionicBoltConstants"))

local ABILITY_ID = PsionicBoltConstants.ABILITY_ID
local AIM_INTERVAL = PsionicBoltConstants.AIM_SEND_INTERVAL

local PsionicBoltClient = {}

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

function PsionicBoltClient.start(
	boltStart: RemoteEvent,
	boltAim: RemoteEvent,
	boltRelease: RemoteEvent,
	player: Player,
	setAbilityPressed: ((key: string, pressed: boolean) -> ())?
)
	local qHeld = false
	local steering = false
	local lastAimSend = 0

	RunService.Heartbeat:Connect(function()
		if not AbilityGateHelper.isJeanGrey(player) then
			qHeld = false
			steering = false
			if setAbilityPressed then
				setAbilityPressed("Q", false)
			end
			return
		end

		local char = player.Character
		local cam = workspace.CurrentCamera
		if not char or not cam then
			return
		end

		local isDown = UserInputService:IsKeyDown(Enum.KeyCode.Q)
		local now = tick()

		if isDown and not qHeld then
			if AbilityGateHelper.canUse(player, char, ABILITY_ID) then
				local aim = getAimDirection(char, cam)
				boltStart:FireServer(aim.X, aim.Y, aim.Z)
				steering = true
				lastAimSend = now
				if setAbilityPressed then
					setAbilityPressed("Q", true)
				end
			end
			qHeld = true
		elseif not isDown and qHeld then
			if steering then
				boltRelease:FireServer()
				steering = false
			end
			qHeld = false
			if setAbilityPressed then
				setAbilityPressed("Q", false)
			end
		end

		if steering and isDown and now - lastAimSend >= AIM_INTERVAL then
			lastAimSend = now
			local aim = getAimDirection(char, cam)
			boltAim:FireServer(aim.X, aim.Y, aim.Z)
		end
	end)
end

return PsionicBoltClient
