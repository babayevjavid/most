-- Client: Electrokinesis [E] twin beam — aim feedback + screen shake on impact.
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage.Shared.LightningEConfig)

local shakeConn: RBXScriptConnection? = nil
local shakeSerial = 0
local fovTweenIn: Tween? = nil
local fovTweenOut: Tween? = nil

local function getHands(character: Model): (BasePart?, BasePart?)
	local r = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	local l = character:FindFirstChild("LeftHand") or character:FindFirstChild("Left Arm")
	return r and r :: BasePart?, l and l :: BasePart?
end

local function getAimWorldPosition(character: Model): Vector3
	local cam = workspace.CurrentCamera
	if not cam then
		return character:GetPivot().Position + character:GetPivot().LookVector * 8
	end
	local mousePos = UserInputService:GetMouseLocation()
	local ray = cam:ViewportPointToRay(mousePos.X, mousePos.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local maxDist = 500
	local result = workspace:Raycast(ray.Origin, ray.Direction * maxDist, params)
	if result then
		return result.Position
	end
	return ray.Origin + ray.Direction * 80
end

local function burstHandSparksImmediate(hand: BasePart)
	local att = Instance.new("Attachment")
	att.Parent = hand
	local pe = Instance.new("ParticleEmitter")
	pe.Name = "LightningEInstantBurst"
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Color = ColorSequence.new(Color3.fromRGB(220, 240, 255), Color3.fromRGB(140, 200, 255))
	pe.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.14),
		NumberSequenceKeypoint.new(0.5, 0.06),
		NumberSequenceKeypoint.new(1, 0.02),
	})
	pe.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	pe.Lifetime = NumberRange.new(0.12, 0.28)
	pe.Speed = NumberRange.new(3, 9)
	pe.SpreadAngle = Vector2.new(42, 42)
	pe.Drag = 4
	pe.Rate = 0
	pe.Rotation = NumberRange.new(0, 360)
	pe.RotSpeed = NumberRange.new(-180, 180)
	pe.LightEmission = 0.85
	pe.Parent = att
	pe:Emit(22)
	Debris:AddItem(att, 0.55)
end

local function smoothRotateToward(character: Model, worldTarget: Vector3)
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = character:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum then
		return
	end
	local flatTarget = Vector3.new(worldTarget.X, hrp.Position.Y, worldTarget.Z)
	local delta = flatTarget - hrp.Position
	if delta.Magnitude < 0.15 then
		return
	end
	local goal = CFrame.new(hrp.Position, flatTarget)
	local wasAuto = hum.AutoRotate
	hum.AutoRotate = false
	local tween = TweenService:Create(
		hrp,
		TweenInfo.new(Config.AimRotateDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = goal }
	)
	tween.Completed:Connect(function()
		if hum.Parent then
			hum.AutoRotate = wasAuto
		end
	end)
	tween:Play()
end

local function fovPunch()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	if fovTweenIn then
		fovTweenIn:Cancel()
		fovTweenIn = nil
	end
	if fovTweenOut then
		fovTweenOut:Cancel()
		fovTweenOut = nil
	end
	local base = cam.FieldOfView
	local peak = base + Config.FovAdd
	fovTweenIn = TweenService:Create(cam, TweenInfo.new(Config.FovInDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FieldOfView = peak,
	})
	fovTweenOut = TweenService:Create(cam, TweenInfo.new(Config.FovOutDuration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
		FieldOfView = base,
	})
	fovTweenIn.Completed:Connect(function()
		if not cam.Parent then
			return
		end
		task.delay(Config.FovOutDelay, function()
			if cam.Parent and fovTweenOut then
				fovTweenOut:Play()
			end
		end)
	end)
	fovTweenIn:Play()
end

local function playCameraShake(magnitude: number, duration: number)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	shakeSerial += 1
	local token = shakeSerial
	if shakeConn then
		shakeConn:Disconnect()
		shakeConn = nil
	end
	local rng = Random.new()
	local t0 = os.clock()
	shakeConn = RunService.RenderStepped:Connect(function()
		if token ~= shakeSerial then
			return
		end
		if not hum.Parent then
			hum.CameraOffset = Vector3.zero
			shakeConn:Disconnect()
			shakeConn = nil
			return
		end
		local elapsed = os.clock() - t0
		if elapsed >= duration then
			hum.CameraOffset = Vector3.zero
			shakeConn:Disconnect()
			shakeConn = nil
			return
		end
		local decay = (1 - elapsed / duration) ^ 1.35
		hum.CameraOffset = Vector3.new(
			(rng:NextNumber() - 0.5) * 2 * magnitude * decay,
			(rng:NextNumber() - 0.5) * 2 * magnitude * decay * 0.75,
			(rng:NextNumber() - 0.5) * 2 * magnitude * decay * 0.4
		)
	end)
end

local M = {}

function M.start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local ev = remotes:WaitForChild("LightningTwinBeam") :: RemoteEvent
	local impactEv = remotes:WaitForChild("LightningBeamImpact") :: RemoteEvent

	impactEv.OnClientEvent:Connect(function(worldPos: unknown)
		if typeof(worldPos) ~= "Vector3" then
			return
		end
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart
		if not root then
			return
		end
		local dist = (root.Position - (worldPos :: Vector3)).Magnitude
		if dist > Config.CameraShakeRadius then
			return
		end
		local falloff = 1 - (dist / Config.CameraShakeRadius)
		local mag = Config.CameraShakeMagnitude * (0.35 + 0.65 * falloff)
		playCameraShake(mag, Config.CameraShakeDuration)
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		if input.KeyCode ~= Enum.KeyCode.E then
			return
		end
		if player:GetAttribute("SelectedPower") ~= "Electrokinesis" then
			return
		end
		local cdUntil = player:GetAttribute("ElectrokinesisECdUntil")
		if typeof(cdUntil) == "number" and workspace:GetServerTimeNow() < cdUntil then
			return
		end
		local char = player.Character
		if not char then
			return
		end
		local hum = char:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then
			return
		end
		local pos = getAimWorldPosition(char)
		local r, l = getHands(char)
		if r then
			burstHandSparksImmediate(r)
		end
		if l then
			burstHandSparksImmediate(l)
		end
		smoothRotateToward(char, pos)
		fovPunch()
		ev:FireServer(pos)
	end)
end

return M
