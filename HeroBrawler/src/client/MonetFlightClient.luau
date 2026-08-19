--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local MonetConstants = require(ReplicatedStorage.Shared.MonetConstants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local MonetFlightClient = {}

local DEFAULT_FOV = 70
local CHARGE_FOV = 46
local RELEASE_PEAK_FOV = 92
local MAX_FOV_BOOST = 16

local function getFullCameraMove(): (Vector3, Vector3)
	local camera = workspace.CurrentCamera
	if not camera then
		return Vector3.zero, Vector3.new(0, 0, -1)
	end
	local look = camera.CFrame.LookVector
	local right = camera.CFrame.RightVector
	if look.Magnitude < 0.01 then
		look = Vector3.new(0, 0, -1)
	else
		look = look.Unit
	end
	if right.Magnitude < 0.01 then
		right = Vector3.new(1, 0, 0)
	else
		right = right.Unit
	end

	local w = if UserInputService:IsKeyDown(Enum.KeyCode.W) then 1 else 0
	local s = if UserInputService:IsKeyDown(Enum.KeyCode.S) then 1 else 0
	local a = if UserInputService:IsKeyDown(Enum.KeyCode.A) then 1 else 0
	local d = if UserInputService:IsKeyDown(Enum.KeyCode.D) then 1 else 0

	local moveDir = look * (w - s) + right * (d - a)
	if moveDir.Magnitude > 1 then
		moveDir = moveDir.Unit
	end
	return moveDir, look
end

local function bindChargeCamera(character: Model)
	character:GetAttributeChangedSignal("PsychicCharging"):Connect(function()
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		if character:GetAttribute("PsychicCharging") == true then
			TweenService:Create(camera, TweenInfo.new(0.18, Enum.EasingStyle.Sine), { FieldOfView = CHARGE_FOV }):Play()
		end
	end)

	character:GetAttributeChangedSignal("PsychicRepulsionRelease"):Connect(function()
		if character:GetAttribute("PsychicRepulsionRelease") ~= true then
			return
		end
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local peak = TweenService:Create(camera, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			FieldOfView = RELEASE_PEAK_FOV,
		})
		peak:Play()
		peak.Completed:Connect(function()
			TweenService:Create(camera, TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
				FieldOfView = DEFAULT_FOV,
			}):Play()
		end)
	end)
end

function MonetFlightClient.init(player: Player)
	local flightInput = Remotes.getEvent("FlightInput")

	if player.Character then
		bindChargeCamera(player.Character)
	end
	player.CharacterAdded:Connect(bindChargeCamera)

	RunService.RenderStepped:Connect(function(dt)
		local character = player.Character
		local camera = workspace.CurrentCamera
		if not character or not camera then
			return
		end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end

		local isFlying = character:GetAttribute(MonetConstants.IS_FLYING_ATTRIBUTE) == true
		if isFlying then
			local moveDir, look = getFullCameraMove()
			local boosting = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
				or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
			flightInput:FireServer({
				moveVector = moveDir,
				lookVector = look,
				boosting = boosting,
			})

			local alpha = character:GetAttribute(MonetConstants.FLIGHT_ALPHA_ATTRIBUTE)
			local bank = character:GetAttribute(MonetConstants.FLIGHT_BANK_ATTRIBUTE)
			local speedAlpha = if type(alpha) == "number" then alpha else 0
			local bankVal = if type(bank) == "number" then bank else 0

			local targetFov = DEFAULT_FOV + speedAlpha * MAX_FOV_BOOST
			camera.FieldOfView += (targetFov - camera.FieldOfView) * math.clamp(dt * 6, 0, 1)

			local offsetTarget = Vector3.new(bankVal * 0.012, 0.3 + speedAlpha * 0.9, 0)
			humanoid.CameraOffset = humanoid.CameraOffset:Lerp(offsetTarget, math.clamp(dt * 8, 0, 1))
		elseif character:GetAttribute("PsychicCharging") ~= true then
			camera.FieldOfView += (DEFAULT_FOV - camera.FieldOfView) * math.clamp(dt * 8, 0, 1)
			if humanoid.CameraOffset.Magnitude > 0.01 then
				humanoid.CameraOffset = humanoid.CameraOffset:Lerp(Vector3.zero, math.clamp(dt * 8, 0, 1))
			end
		end
	end)
end

return MonetFlightClient
