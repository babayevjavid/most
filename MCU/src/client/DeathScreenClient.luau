--!strict

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local DeathScreenClient = {}

export type DeathScreenOptions = {
	isPhoenix: boolean?,
	onRevive: (() -> ())?,
}

local DURATION = 5
local CAM_RISE = 0.9
local CAM_HEIGHT_START = 16
local CAM_HEIGHT_END = 3.5
local CAM_BIND = "MCU_DeathCam"
local activeToken = 0
local activeCleanup: ((runComplete: boolean?) -> ())? = nil
local requestStandardCountdown: (() -> ())? = nil

local function findLookTarget(character: Model): BasePart?
	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head
	end
	local upper = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	if upper and upper:IsA("BasePart") then
		return upper
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function captureFocus(character: Model): Vector3
	local lookPart = findLookTarget(character)
	if lookPart then
		return lookPart.Position
	end
	local ok, pivot = pcall(function()
		return character:GetPivot().Position
	end)
	if ok then
		return pivot
	end
	return Vector3.new(0, 6, 0)
end

function DeathScreenClient.isActive(): boolean
	return activeCleanup ~= nil
end

function DeathScreenClient.play(character: Model, onComplete: (() -> ())?, options: DeathScreenOptions?)
	if activeCleanup then
		activeToken += 1
		activeCleanup(false)
	end

	activeToken += 1
	local token = activeToken

	local player = Players.LocalPlayer
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		activeToken = 0
		if onComplete then
			onComplete()
		end
		return
	end

	local hidden: { ScreenGui } = {}
	for _, child in playerGui:GetChildren() do
		if child:IsA("ScreenGui") and child.Enabled and child.Name ~= "DeathScreen" then
			child.Enabled = false
			table.insert(hidden, child)
		end
	end

	local existing = playerGui:FindFirstChild("DeathScreen")
	if existing then
		existing:Destroy()
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "DeathScreen"
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 2000
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui

	local overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
	overlay.BackgroundTransparency = 1
	overlay.BorderSizePixel = 0
	overlay.ZIndex = 1
	overlay.Parent = screenGui

	local countdown = Instance.new("TextLabel")
	countdown.Name = "Countdown"
	countdown.AnchorPoint = Vector2.new(0.5, 0.5)
	countdown.Position = UDim2.fromScale(0.5, 0.5)
	countdown.Size = UDim2.fromOffset(220, 180)
	countdown.BackgroundTransparency = 1
	countdown.Font = Enum.Font.GothamBlack
	countdown.TextSize = 110
	countdown.TextColor3 = Color3.fromRGB(235, 235, 240)
	countdown.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	countdown.TextStrokeTransparency = 0.25
	countdown.Text = tostring(DURATION)
	countdown.Visible = options == nil or options.isPhoenix ~= true
	countdown.ZIndex = 3
	countdown.Parent = screenGui

	local reviveBtn: TextButton? = nil
	if options and options.isPhoenix then
		local btn = Instance.new("TextButton")
		btn.Name = "PhoenixRevive"
		btn.AnchorPoint = Vector2.new(0.5, 0.5)
		btn.Position = UDim2.fromScale(0.5, 0.56)
		btn.Size = UDim2.fromOffset(280, 64)
		btn.BackgroundColor3 = Color3.fromRGB(255, 57, 17)
		btn.BorderSizePixel = 0
		btn.Font = Enum.Font.GothamBold
		btn.TextSize = 28
		btn.TextColor3 = Color3.fromRGB(255, 240, 228)
		btn.Text = "COME BACK"
		btn.AutoButtonColor = true
		btn.ZIndex = 4
		btn.Parent = screenGui
		reviveBtn = btn

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = btn

		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(255, 140, 95)
		stroke.Thickness = 2
		stroke.Parent = btn
	end

	local corpse = character
	local focusPos = captureFocus(corpse)
	local cam = Workspace.CurrentCamera
	local startCf = if cam then cam.CFrame else CFrame.new(focusPos + Vector3.new(0, 16, 0))
	local riseStart = os.clock()
	local countdownStart = os.clock()
	local zoomT = 0
	local zoomGoal = 0
	local lastCamTick = os.clock()
	local savedCamSubject = if cam then cam.CameraSubject else nil

	local grey = Lighting:FindFirstChild("MCU_DeathGrey")
	if grey then
		grey:Destroy()
	end
	local colorFx = Instance.new("ColorCorrectionEffect")
	colorFx.Name = "MCU_DeathGrey"
	colorFx.Saturation = 0
	colorFx.Contrast = 0
	colorFx.Brightness = 0
	colorFx.Parent = Lighting
	TweenService:Create(colorFx, TweenInfo.new(0.85, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Saturation = -0.92,
		Contrast = -0.1,
		Brightness = -0.08,
	}):Play()

	overlay.BackgroundTransparency = 0.88
	TweenService:Create(overlay, TweenInfo.new(0.85, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0.28,
	}):Play()

	local finished = false
	local camBound = false
	local function stopDeathCam()
		if camBound then
			pcall(function()
				RunService:UnbindFromRenderStep(CAM_BIND)
			end)
			camBound = false
		end
	end
	local function cleanup(runComplete: boolean?)
		if finished then
			return
		end
		finished = true
		activeCleanup = nil
		requestStandardCountdown = nil
		stopDeathCam()
		if colorFx.Parent then
			colorFx:Destroy()
		end
		if screenGui.Parent then
			screenGui:Destroy()
		end
		for _, gui in hidden do
			if gui.Parent then
				gui.Enabled = true
			end
		end
		local liveCam = Workspace.CurrentCamera
		if liveCam then
			liveCam.CameraType = Enum.CameraType.Custom
			local subject = savedCamSubject
			local subjectHumanoid = subject and subject:IsA("Humanoid") and subject
			if subjectHumanoid and subjectHumanoid.Parent and subjectHumanoid.Health > 0 then
				liveCam.CameraSubject = subject
			else
				local spawned = Players.LocalPlayer.Character
				local hum = spawned and spawned:FindFirstChildOfClass("Humanoid")
				if hum and hum.Health > 0 then
					liveCam.CameraSubject = hum
				end
			end
		end
		local invokeComplete = runComplete ~= false and token == activeToken
		if token == activeToken then
			activeToken = 0
		end
		if onComplete and invokeComplete then
			onComplete()
		end
	end
	activeCleanup = cleanup

	local phoenixMode = options ~= nil and options.isPhoenix == true
	countdown.Visible = not phoenixMode

	pcall(function()
		RunService:UnbindFromRenderStep(CAM_BIND)
	end)
	RunService:BindToRenderStep(CAM_BIND, Enum.RenderPriority.Last.Value, function()
		if token ~= activeToken or finished then
			return
		end
		local liveCam = Workspace.CurrentCamera
		if not liveCam then
			return
		end
		if corpse.Parent then
			local lookPart = findLookTarget(corpse)
			if lookPart then
				focusPos = lookPart.Position
			end
		end
		liveCam.CameraType = Enum.CameraType.Scriptable
		local now = os.clock()
		local dt = math.clamp(now - lastCamTick, 0, 0.05)
		lastCamTick = now
		if not phoenixMode then
			zoomGoal = math.clamp((now - countdownStart) / DURATION, 0, 1)
		end
		zoomT += (zoomGoal - zoomT) * math.clamp(dt * 2.6, 0, 1)
		local height = CAM_HEIGHT_START + (CAM_HEIGHT_END - CAM_HEIGHT_START) * zoomT
		local target = CFrame.lookAt(focusPos + Vector3.new(0, height, 0), focusPos)
		local alpha = math.clamp((now - riseStart) / CAM_RISE, 0, 1)
		alpha = 1 - (1 - alpha) * (1 - alpha)
		if zoomT > 0.02 then
			liveCam.CFrame = liveCam.CFrame:Lerp(target, math.clamp(dt * 6, 0, 1))
		else
			liveCam.CFrame = startCf:Lerp(target, alpha)
		end
	end)
	camBound = true

	requestStandardCountdown = function()
		phoenixMode = false
		if reviveBtn then
			reviveBtn.Visible = false
		end
		countdown.Visible = true
	end

	if reviveBtn and options and options.onRevive then
		reviveBtn.MouseButton1Click:Connect(function()
			if finished then
				return
			end
			if options.onRevive then
				options.onRevive()
			end
			cleanup(false)
		end)
	end

	task.spawn(function()
		while phoenixMode and token == activeToken and not finished do
			task.wait(0.1)
		end
		if token ~= activeToken or finished then
			return
		end

		countdownStart = os.clock()
		zoomGoal = 0
		zoomT = 0

		local remaining = DURATION
		while remaining > 0 do
			if token ~= activeToken or finished then
				return
			end
			countdown.Text = tostring(remaining)
			task.wait(1)
			remaining -= 1
		end

		if token ~= activeToken or finished then
			return
		end

		TweenService:Create(countdown, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}):Play()
		task.wait(0.35)
		if token ~= activeToken or finished then
			return
		end
		if onComplete then
			onComplete()
		end
		task.wait(0.25)
		if token ~= activeToken or finished then
			return
		end
		TweenService:Create(overlay, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 1,
		}):Play()
		if colorFx.Parent then
			TweenService:Create(colorFx, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Saturation = 0,
				Contrast = 0,
				Brightness = 0,
			}):Play()
		end
		task.wait(0.45)
		cleanup()
	end)
end

function DeathScreenClient.notifyBodyGone()
	if requestStandardCountdown then
		requestStandardCountdown()
	end
end

function DeathScreenClient.cancel()
	local cleanupFn = activeCleanup
	if cleanupFn then
		activeToken += 1
		cleanupFn(false)
	end
end

return DeathScreenClient
