--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local AbilityConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityConstants"))
local Keybinds = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Keybinds"))
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local AbilityController = require(script.Parent.Controllers.AbilityController)
local TargetingHelper = require(script.Parent.TargetingHelper)

local TelekinesisClient = {}

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local telekinesisRequest = remotesFolder:WaitForChild(Remotes.TelekinesisRequest) :: RemoteEvent
local telekinesisUpdate = remotesFolder:WaitForChild(Remotes.TelekinesisUpdate) :: RemoteEvent
local telekinesisThrow = remotesFolder:WaitForChild(Remotes.TelekinesisThrow) :: RemoteEvent
local telekinesisEnd = remotesFolder:WaitForChild(Remotes.TelekinesisEnd) :: RemoteEvent

local RAYCAST_MAX_DIST = AbilityConstants.TELEKINESIS_MAX_RANGE
local UPDATE_SEND_INTERVAL = 0.05
local TELEKINESIS_KEY = Keybinds.AbilitySlots[2]

local lastQState = false
local lastUpdateSend = 0
local throwKeyPressed = false
local targetHoldDistance = AbilityConstants.TELEKINESIS_HOLD_DISTANCE

local function getCharacter(): Model?
	local player = game:GetService("Players").LocalPlayer
	return player.Character
end

local function isTelekinesisAbility(): boolean
	return AbilityController.getAbilityIdForSlot(2) == "Telekinesis"
end

local function isActive(char: Model): boolean
	return char:GetAttribute("IsTelekinesisActive") == true
end

local function getAimDirection(): Vector3
	local cam = workspace.CurrentCamera
	if not cam then
		return Vector3.new(0, 0, -1)
	end
	local mousePos = UserInputService:GetMouseLocation()
	local ray = cam:ViewportPointToRay(mousePos.X, mousePos.Y)
	local dir = ray.Direction
	if dir.Magnitude < 0.01 then
		return Vector3.new(0, 0, -1)
	end
	return dir.Unit
end

local function getCursorWorldPos(): Vector3?
	return TargetingHelper.getCursorWorldPos(RAYCAST_MAX_DIST)
end

function TelekinesisClient.setup()
	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			local char = getCharacter()
			if not char or not isActive(char) then
				return
			end
			targetHoldDistance = math.clamp(
				targetHoldDistance - input.Position.Z * 2,
				AbilityConstants.TELEKINESIS_HOLD_DISTANCE_MIN,
				AbilityConstants.TELEKINESIS_HOLD_DISTANCE_MAX
			)
		end
	end)

	RunService.RenderStepped:Connect(function()
		if not AbilityController.hasHero() or not isTelekinesisAbility() then
			lastQState = false
			return
		end

		local char = getCharacter()
		if not char then
			return
		end

		local now = os.clock()
		local qHeld = UserInputService:IsKeyDown(TELEKINESIS_KEY)
		local active = isActive(char)

		local wantThrow = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
		if active and wantThrow and not throwKeyPressed then
			throwKeyPressed = true
			local dir = getAimDirection()
			local cursorWorldPos = getCursorWorldPos()
			local cx, cy, cz = 0, 0, 0
			if cursorWorldPos then
				cx, cy, cz = cursorWorldPos.X, cursorWorldPos.Y, cursorWorldPos.Z
			end
			telekinesisUpdate:FireServer(dir.X, dir.Y, dir.Z, cx, cy, cz, targetHoldDistance)
			telekinesisThrow:FireServer()
		elseif not wantThrow then
			throwKeyPressed = false
		end

		if qHeld then
			if not lastQState then
				if active then
					lastUpdateSend = now
				else
					local nearestPart = TargetingHelper.getTargetPartAtCursor(char, RAYCAST_MAX_DIST)
					local cursorWorldPos = getCursorWorldPos()
					local cx, cy, cz = 0, 0, 0
					if cursorWorldPos then
						cx, cy, cz = cursorWorldPos.X, cursorWorldPos.Y, cursorWorldPos.Z
					end
					if nearestPart then
						telekinesisRequest:FireServer(nearestPart, cx, cy, cz)
					end
				end
			elseif active and now - lastUpdateSend >= UPDATE_SEND_INTERVAL then
				lastUpdateSend = now
				local dir = getAimDirection()
				local cursorWorldPos = getCursorWorldPos()
				local cx, cy, cz = 0, 0, 0
				if cursorWorldPos then
					cx, cy, cz = cursorWorldPos.X, cursorWorldPos.Y, cursorWorldPos.Z
				end
				telekinesisUpdate:FireServer(dir.X, dir.Y, dir.Z, cx, cy, cz, targetHoldDistance)
			end
		else
			if lastQState and active then
				telekinesisEnd:FireServer()
				targetHoldDistance = AbilityConstants.TELEKINESIS_HOLD_DISTANCE
			end
		end

		lastQState = qHeld
	end)
end

function TelekinesisClient.isTelekinesisActive(): boolean
	local char = getCharacter()
	return char ~= nil and isActive(char)
end

return TelekinesisClient
