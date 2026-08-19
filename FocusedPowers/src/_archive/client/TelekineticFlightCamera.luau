--!strict
--[[
	Telekinetic Flight camera feel: FOV widens while flying, scales with speed.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local TelekineticFlightConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TelekineticFlightConstants"))

local DEFAULT_FOV = TelekineticFlightConstants.CAMERA_DEFAULT_FOV
local FLYING_FOV = TelekineticFlightConstants.CAMERA_FLYING_FOV
local FLYING_MAX_FOV = TelekineticFlightConstants.CAMERA_FLYING_MAX_FOV
local TWEEN_IN = TelekineticFlightConstants.CAMERA_TWEEN_IN
local TWEEN_OUT = TelekineticFlightConstants.CAMERA_TWEEN_OUT

local TelekineticFlightCamera = {}

local fovTween: Tween? = nil
local renderConn: RBXScriptConnection? = nil
local attributeConns: { RBXScriptConnection } = {}
local defaultFov = DEFAULT_FOV
local boundCharacter: Model? = nil
local flying = false

local function getCamera(): Camera?
	return workspace.CurrentCamera
end

local function cancelFovTween()
	if fovTween then
		fovTween:Cancel()
		fovTween = nil
	end
end

local function tweenFov(targetFov: number, duration: number)
	local cam = getCamera()
	if not cam then
		return
	end
	cancelFovTween()
	fovTween = TweenService:Create(cam, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FieldOfView = targetFov,
	})
	fovTween:Play()
end

local function captureDefaultFov()
	local cam = getCamera()
	if cam then
		defaultFov = cam.FieldOfView
	end
end

local function getSpeedAlpha(): number
	if not boundCharacter then
		return 0
	end
	local alpha = boundCharacter:GetAttribute("FlightAlphaSpeed")
	if typeof(alpha) == "number" then
		return math.clamp(alpha, 0, 1)
	end
	return 0
end

local function targetFovForFlight(): number
	return FLYING_FOV + (FLYING_MAX_FOV - FLYING_FOV) * getSpeedAlpha()
end

local function stopRenderLoop()
	if renderConn then
		renderConn:Disconnect()
		renderConn = nil
	end
end

local function startRenderLoop()
	stopRenderLoop()
	renderConn = RunService.RenderStepped:Connect(function(dt)
		if not flying then
			return
		end
		local cam = getCamera()
		if not cam then
			return
		end
		local target = targetFovForFlight()
		local alpha = math.min(1, dt * 6)
		cam.FieldOfView = cam.FieldOfView + (target - cam.FieldOfView) * alpha
	end)
end

local function onFlightStart()
	flying = true
	cancelFovTween()
	startRenderLoop()
	tweenFov(FLYING_FOV, TWEEN_IN)
end

local function onFlightEnd()
	flying = false
	stopRenderLoop()
	tweenFov(defaultFov, TWEEN_OUT)
end

local function clearConnections()
	for _, conn in attributeConns do
		conn:Disconnect()
	end
	table.clear(attributeConns)
end

local function bindCharacter(character: Model)
	clearConnections()
	stopRenderLoop()
	boundCharacter = character
	flying = false

	if character:GetAttribute("IsTelekineticFlying") == true then
		onFlightStart()
	end

	table.insert(attributeConns, character:GetAttributeChangedSignal("IsTelekineticFlying"):Connect(function()
		if character:GetAttribute("IsTelekineticFlying") == true then
			task.defer(onFlightStart)
		else
			onFlightEnd()
		end
	end))
end

function TelekineticFlightCamera.start(player: Player)
	captureDefaultFov()

	local function onCharacterAdded(character: Model)
		bindCharacter(character)
	end

	if player.Character then
		onCharacterAdded(player.Character)
	end

	player.CharacterAdded:Connect(function(character)
		captureDefaultFov()
		onCharacterAdded(character)
	end)

	player.CharacterRemoving:Connect(function()
		boundCharacter = nil
		flying = false
		clearConnections()
		stopRenderLoop()
		cancelFovTween()
		local cam = getCamera()
		if cam then
			cam.FieldOfView = defaultFov
		end
	end)
end

return TelekineticFlightCamera
