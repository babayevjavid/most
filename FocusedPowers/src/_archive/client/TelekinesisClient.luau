--!strict
--[[
	Telekinesis (E): hold to grab/maintain, release to drop, click to throw.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local AbilityGateHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityGateHelper"))
local TelekinesisConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TelekinesisConstants"))
local TargetingHelper = require(script.Parent:WaitForChild("TargetingHelper"))
local TelekinesisHighlight = require(script.Parent:WaitForChild("TelekinesisHighlight"))

local RAYCAST_MAX_DIST = TelekinesisConstants.RAYCAST_MAX_DIST
local UPDATE_SEND_INTERVAL = TelekinesisConstants.UPDATE_SEND_INTERVAL
local HOLD_DISTANCE_MIN = TelekinesisConstants.HOLD_DISTANCE_MIN
local HOLD_DISTANCE_MAX = TelekinesisConstants.HOLD_DISTANCE_MAX
local SCROLL_STEP = TelekinesisConstants.SCROLL_STEP
local CASTER_ROTATE_SPEED = TelekinesisConstants.CASTER_ROTATE_SPEED
local FLIGHT_MAX_TARGETS = TelekinesisConstants.FLIGHT_MAX_TARGETS
local FLIGHT_HOLD_DISTANCE_MIN = TelekinesisConstants.FLIGHT_HOLD_DISTANCE_MIN
local FLIGHT_HOLD_DISTANCE_MAX = TelekinesisConstants.FLIGHT_HOLD_DISTANCE_MAX
local TELEKINESIS_ABILITY_ID = "Telekinesis"

local TelekinesisClient = {}

local function isCtrlDown(): boolean
	return UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
end

local function clampHoldDistance(dist: number): number
	return math.clamp(dist, HOLD_DISTANCE_MIN, HOLD_DISTANCE_MAX)
end

local function getHeldTargetPart(char: Model): BasePart?
	local heldRef = char:FindFirstChild("TelekinesisHeldRoot")
	if heldRef and heldRef:IsA("ObjectValue") and heldRef.Value and heldRef.Value:IsA("BasePart") then
		return heldRef.Value
	end
	return nil
end

local function getCameraAimDirection(cam: Camera): Vector3
	local mousePos = UserInputService:GetMouseLocation()
	local ray = cam:ViewportPointToRay(mousePos.X, mousePos.Y)
	local dir = ray.Direction
	if dir.Magnitude < 0.01 then
		return Vector3.new(0, 0, -1)
	end
	return dir.Unit
end

function TelekinesisClient.start(
	telekinesisRequest: RemoteEvent,
	telekinesisUpdate: RemoteEvent,
	telekinesisThrow: RemoteEvent,
	telekinesisEnd: RemoteEvent,
	player: Player,
	setAbilityPressed: ((key: string, pressed: boolean) -> ())?
)
	local lastUpdateSend = 0
	local lastEState = false
	local throwKeyPressed = false
	local targetHoldDistance = HOLD_DISTANCE_MAX * 0.5
	local wasTelekinesisActive = false
	local savedAutoRotate: boolean? = nil
	local holdDistConn: RBXScriptConnection? = nil
	local lastAimDirection = Vector3.new(0, 0, -1)
	local flightHeldTargets: { BasePart } = {}
	local ctrlClickWas = false

	local function clearFlightHeld()
		table.clear(flightHeldTargets)
	end

	local function addFlightHeld(part: BasePart)
		for _, existing in flightHeldTargets do
			if existing == part then
				return
			end
		end
		if #flightHeldTargets >= FLIGHT_MAX_TARGETS then
			return
		end
		table.insert(flightHeldTargets, part)
	end

	local function getTelekinesisCursorWorldPos(char: Model, cam: Camera): Vector3
		local mousePos = UserInputService:GetMouseLocation()
		local ray = cam:ViewportPointToRay(mousePos.X, mousePos.Y)
		local rp = RaycastParams.new()
		rp.FilterDescendantsInstances = { char }
		rp.FilterType = Enum.RaycastFilterType.Exclude
		local result = workspace:Raycast(ray.Origin, ray.Direction.Unit * 500, rp)
		if result then
			return result.Position
		end
		return ray.Origin + ray.Direction
	end

	local function restoreAutoRotate(char: Model)
		local humanoid = char:FindFirstChildOfClass("Humanoid")
		if humanoid and savedAutoRotate ~= nil then
			humanoid.AutoRotate = savedAutoRotate
		end
		savedAutoRotate = nil
	end

	local function updateCasterRotation(char: Model, cam: Camera, dt: number)
		local humanoid = char:FindFirstChildOfClass("Humanoid")
		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not humanoid or not root then
			return
		end

		if savedAutoRotate == nil then
			savedAutoRotate = humanoid.AutoRotate
			humanoid.AutoRotate = false
		end

		local aimDir = getCameraAimDirection(cam)
		lastAimDirection = aimDir
		local flat = Vector3.new(aimDir.X, 0, aimDir.Z)
		if flat.Magnitude < 0.01 then
			return
		end
		flat = flat.Unit

		local targetCF = CFrame.lookAt(root.Position, root.Position + flat)
		local alpha = math.min(1, dt * CASTER_ROTATE_SPEED)
		root.CFrame = root.CFrame:Lerp(targetCF, alpha)
	end

	UserInputService.InputChanged:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseWheel then
			return
		end
		local char = player.Character
		if not char or char:GetAttribute("IsTelekinesisActive") ~= true then
			return
		end
		local scroll = input.Position.Z
		if math.abs(scroll) < 0.01 then
			return
		end
		targetHoldDistance = clampHoldDistance(targetHoldDistance + scroll * SCROLL_STEP)
		char:SetAttribute("TelekinesisHoldDistance", targetHoldDistance)
	end)

	RunService.RenderStepped:Connect(function(dt)
		if not AbilityGateHelper.isJeanGrey(player) then
			return
		end
		local char = player.Character
		local cam = workspace.CurrentCamera
		if not char or not cam then
			return
		end
		if char:GetAttribute("IsTelekinesisActive") == true
			and char:GetAttribute("TelekinesisFlightMode") ~= true
		then
			updateCasterRotation(char, cam, dt)
		elseif savedAutoRotate ~= nil then
			restoreAutoRotate(char)
		end
	end)

	RunService.Heartbeat:Connect(function()
		if not AbilityGateHelper.isJeanGrey(player) then
			TelekinesisHighlight.clearAll()
			lastEState = false
			wasTelekinesisActive = false
			if setAbilityPressed then
				setAbilityPressed("E", false)
			end
			return
		end

		local now = tick()
		local char = player.Character
		local cam = workspace.CurrentCamera
		if not char or not cam then
			TelekinesisHighlight.clearAll()
			lastEState = false
			wasTelekinesisActive = false
			return
		end

		local eHeld = UserInputService:IsKeyDown(Enum.KeyCode.E)
		local ctrlHeld = isCtrlDown()
		local flying = char:GetAttribute("IsTelekineticFlying") == true
		local isActive = char:GetAttribute("IsTelekinesisActive") == true
		local isFlightTk = char:GetAttribute("TelekinesisFlightMode") == true

		if setAbilityPressed then
			setAbilityPressed(
				"E",
				eHeld and (isActive or not AbilityGateHelper.canUse(player, char, TELEKINESIS_ABILITY_ID))
			)
		end

		if isActive and not wasTelekinesisActive then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
			if holdDistConn then
				holdDistConn:Disconnect()
			end
			holdDistConn = char:GetAttributeChangedSignal("TelekinesisHoldDistance"):Connect(function()
				local dist = char:GetAttribute("TelekinesisHoldDistance")
				if type(dist) == "number" then
					targetHoldDistance = clampHoldDistance(dist)
				end
			end)
			local dist = char:GetAttribute("TelekinesisHoldDistance")
			if type(dist) == "number" then
				targetHoldDistance = clampHoldDistance(dist)
			end
		end
		if not isActive and wasTelekinesisActive then
			restoreAutoRotate(char)
			clearFlightHeld()
			if holdDistConn then
				holdDistConn:Disconnect()
				holdDistConn = nil
			end
		end
		wasTelekinesisActive = isActive

		if isActive then
			if isFlightTk then
				local liveHeld: { BasePart } = {}
				for _, part in flightHeldTargets do
					if part.Parent and part:GetAttribute("TelekinesisHeld") == true then
						table.insert(liveHeld, part)
					end
				end
				flightHeldTargets = liveHeld
				TelekinesisHighlight.setHeldMany(liveHeld)
			else
				local held = getHeldTargetPart(char)
				if held and held:GetAttribute("TelekinesisHeld") == true then
					TelekinesisHighlight.setHeld(held)
				else
					TelekinesisHighlight.clearAll()
				end
			end
		else
			TelekinesisHighlight.clearAll()
		end

		local wantThrow = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)

		if isActive and isFlightTk then
			if wantThrow and ctrlHeld and not ctrlClickWas then
				if #flightHeldTargets < FLIGHT_MAX_TARGETS then
					local nearestPart = TargetingHelper.getTargetPartAtCursor(char, RAYCAST_MAX_DIST, flightHeldTargets)
					if nearestPart then
						telekinesisRequest:FireServer(nearestPart, getTelekinesisCursorWorldPos(char, cam), true)
						addFlightHeld(nearestPart)
					end
				end
				ctrlClickWas = true
			elseif wantThrow and not ctrlHeld and not throwKeyPressed then
				throwKeyPressed = true
				clearFlightHeld()
				TelekinesisHighlight.clearAll()
				telekinesisThrow:FireServer()
			elseif not wantThrow then
				throwKeyPressed = false
				ctrlClickWas = false
			end
		elseif wantThrow and not throwKeyPressed and isActive then
			throwKeyPressed = true
			clearFlightHeld()
			TelekinesisHighlight.clearAll()
			telekinesisThrow:FireServer()
		elseif not wantThrow then
			throwKeyPressed = false
		end

		if eHeld then
			if not isActive and not lastEState and AbilityGateHelper.canUse(player, char, TELEKINESIS_ABILITY_ID) then
				local nearestPart = TargetingHelper.getTargetPartAtCursor(char, RAYCAST_MAX_DIST, flightHeldTargets)
				if nearestPart then
					telekinesisRequest:FireServer(nearestPart, getTelekinesisCursorWorldPos(char, cam), flying)
					if flying then
						addFlightHeld(nearestPart)
						targetHoldDistance = math.clamp(
							(FLIGHT_HOLD_DISTANCE_MIN + FLIGHT_HOLD_DISTANCE_MAX) * 0.5,
							FLIGHT_HOLD_DISTANCE_MIN,
							FLIGHT_HOLD_DISTANCE_MAX
						)
					end
					lastUpdateSend = now
				end
			elseif isActive and now - lastUpdateSend >= UPDATE_SEND_INTERVAL then
				lastUpdateSend = now
				local dir = getCameraAimDirection(cam)
				telekinesisUpdate:FireServer(
					dir.X,
					dir.Y,
					dir.Z,
					getTelekinesisCursorWorldPos(char, cam),
					targetHoldDistance
				)
			end
		elseif lastEState and isActive then
			telekinesisEnd:FireServer()
			TelekinesisHighlight.clearAll()
			clearFlightHeld()
			restoreAutoRotate(char)
		end

		lastEState = eHeld
	end)

	player:GetAttributeChangedSignal("SelectedCharacter"):Connect(function()
		if not AbilityGateHelper.isJeanGrey(player) then
			TelekinesisHighlight.clearAll()
		end
	end)
end

return TelekinesisClient
