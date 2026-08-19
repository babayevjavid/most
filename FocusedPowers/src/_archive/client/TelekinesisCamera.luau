--!strict
--[[
	Telekinesis camera feel: FOV widen while active, punch on throw, ease back on end.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local TelekinesisConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TelekinesisConstants"))

local DEFAULT_FOV = TelekinesisConstants.CAMERA_DEFAULT_FOV
local ACTIVE_FOV = TelekinesisConstants.CAMERA_ACTIVE_FOV
local THROW_FOV = TelekinesisConstants.CAMERA_THROW_FOV
local TWEEN_IN = TelekinesisConstants.CAMERA_TWEEN_IN
local TWEEN_OUT = TelekinesisConstants.CAMERA_TWEEN_OUT
local TWEEN_THROW = TelekinesisConstants.CAMERA_TWEEN_THROW

local TelekinesisCamera = {}

local fovTween: Tween? = nil
local attributeConns: { RBXScriptConnection } = {}
local defaultFov = DEFAULT_FOV
local boundCharacter: Model? = nil

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

local function onTelekinesisStart()
	tweenFov(ACTIVE_FOV, TWEEN_IN)
end

local function onTelekinesisEnd()
	tweenFov(defaultFov, TWEEN_OUT)
end

local function onThrowPulse()
	cancelFovTween()
	local cam = getCamera()
	if not cam then
		return
	end
	local settleFov = ACTIVE_FOV
	if boundCharacter and boundCharacter:GetAttribute("IsTelekinesisActive") ~= true then
		settleFov = defaultFov
	end
	local punch = TweenService:Create(cam, TweenInfo.new(TWEEN_THROW * 0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FieldOfView = THROW_FOV,
	})
	local settle = TweenService:Create(cam, TweenInfo.new(TWEEN_THROW * 0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FieldOfView = settleFov,
	})
	punch:Play()
	punch.Completed:Connect(function()
		if cam.FieldOfView >= THROW_FOV - 0.5 then
			settle:Play()
			fovTween = settle
		end
	end)
	fovTween = punch
end

local function clearConnections()
	for _, conn in attributeConns do
		conn:Disconnect()
	end
	table.clear(attributeConns)
end

local function bindCharacter(character: Model)
	clearConnections()
	boundCharacter = character

	if character:GetAttribute("IsTelekinesisActive") == true then
		onTelekinesisStart()
	end

	table.insert(attributeConns, character:GetAttributeChangedSignal("TelekinesisThrowPulse"):Connect(function()
		onThrowPulse()
	end))

	table.insert(attributeConns, character:GetAttributeChangedSignal("IsTelekinesisActive"):Connect(function()
		if character:GetAttribute("IsTelekinesisActive") == true then
			task.defer(onTelekinesisStart)
		else
			onTelekinesisEnd()
		end
	end))
end

function TelekinesisCamera.start(player: Player)
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
		clearConnections()
		cancelFovTween()
		local cam = getCamera()
		if cam then
			cam.FieldOfView = defaultFov
		end
	end)
end

return TelekinesisCamera
