local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera

local shared = ReplicatedStorage:WaitForChild("Shared")
local IncrementalConfig = require(shared:WaitForChild("IncrementalConfig"))
local remotesFolder = ReplicatedStorage:WaitForChild("IncrementalRemotes")

local trainTapRemote = remotesFolder:WaitForChild("TrainTap") :: RemoteEvent
local trainStatRemote = remotesFolder:WaitForChild("TrainStat") :: RemoteEvent
local requestRebirthRemote = remotesFolder:WaitForChild("RequestRebirth") :: RemoteEvent
local notifyRemote = remotesFolder:WaitForChild("Notify") :: RemoteEvent

local function createButton(parent: Instance, name: string, text: string, size: UDim2, color: Color3): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = size
	button.BackgroundColor3 = color
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Font = Enum.Font.GothamBold
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.TextScaled = true
	button.Text = text
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1.5
	stroke.Transparency = 0.2
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Parent = button

	button.MouseEnter:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.12), { BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.12) }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.12), { BackgroundColor3 = color }):Play()
	end)

	return button
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "IncrementalMainUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.AnchorPoint = Vector2.new(0, 1)
mainFrame.Position = UDim2.new(0, 18, 1, -18)
mainFrame.Size = UDim2.fromOffset(420, 360)
mainFrame.BackgroundColor3 = Color3.fromRGB(19, 22, 35)
mainFrame.BackgroundTransparency = 0.1
mainFrame.BorderSizePixel = 0
mainFrame.Parent = screenGui

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 14)
mainCorner.Parent = mainFrame

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(12, 8)
title.Size = UDim2.new(1, -24, 0, 30)
title.Font = Enum.Font.GothamBold
title.TextSize = 24
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.fromRGB(245, 245, 255)
title.Text = "Incremental Fighter"
title.Parent = mainFrame

local statsLabel = Instance.new("TextLabel")
statsLabel.BackgroundTransparency = 1
statsLabel.Position = UDim2.fromOffset(12, 42)
statsLabel.Size = UDim2.new(1, -24, 0, 120)
statsLabel.Font = Enum.Font.GothamSemibold
statsLabel.TextSize = 16
statsLabel.TextWrapped = true
statsLabel.TextXAlignment = Enum.TextXAlignment.Left
statsLabel.TextYAlignment = Enum.TextYAlignment.Top
statsLabel.TextColor3 = Color3.fromRGB(220, 230, 255)
statsLabel.Text = "Loading stats..."
statsLabel.Parent = mainFrame

local trainButton = createButton(
	mainFrame,
	"TrainButton",
	"Train (+coins)",
	UDim2.fromOffset(390, 56),
	Color3.fromRGB(69, 124, 255)
)
trainButton.Position = UDim2.fromOffset(15, 170)

local upgradesFrame = Instance.new("Frame")
upgradesFrame.BackgroundTransparency = 1
upgradesFrame.Position = UDim2.fromOffset(15, 234)
upgradesFrame.Size = UDim2.fromOffset(390, 96)
upgradesFrame.Parent = mainFrame

local grid = Instance.new("UIGridLayout")
grid.FillDirectionMaxCells = 2
grid.CellPadding = UDim2.fromOffset(8, 8)
grid.CellSize = UDim2.fromOffset(190, 44)
grid.Parent = upgradesFrame

local strengthButton = createButton(upgradesFrame, "StrengthButton", "Strength", UDim2.fromOffset(190, 44), Color3.fromRGB(193, 88, 88))
local durabilityButton = createButton(upgradesFrame, "DurabilityButton", "Durability", UDim2.fromOffset(190, 44), Color3.fromRGB(79, 168, 93))
local speedButton = createButton(upgradesFrame, "SpeedButton", "Speed", UDim2.fromOffset(190, 44), Color3.fromRGB(90, 127, 255))
local jumpButton = createButton(upgradesFrame, "JumpButton", "JumpPower", UDim2.fromOffset(190, 44), Color3.fromRGB(187, 123, 255))

local rebirthButton = createButton(
	mainFrame,
	"RebirthButton",
	("Rebirth (Need %d Power)"):format(IncrementalConfig.RebirthRequirement),
	UDim2.fromOffset(390, 40),
	Color3.fromRGB(255, 152, 67)
)
rebirthButton.Position = UDim2.fromOffset(15, 320)

local notification = Instance.new("TextLabel")
notification.BackgroundTransparency = 0.2
notification.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
notification.Position = UDim2.new(0.5, -150, 0, 14)
notification.Size = UDim2.fromOffset(300, 38)
notification.Font = Enum.Font.GothamBold
notification.TextSize = 18
notification.TextColor3 = Color3.fromRGB(255, 255, 255)
notification.Visible = false
notification.Parent = screenGui

local notificationCorner = Instance.new("UICorner")
notificationCorner.CornerRadius = UDim.new(0, 10)
notificationCorner.Parent = notification

local colorCorrection = Lighting:FindFirstChild("IncrementalColorCorrection")
if not colorCorrection then
	colorCorrection = Instance.new("ColorCorrectionEffect")
	colorCorrection.Name = "IncrementalColorCorrection"
	colorCorrection.Contrast = 0.02
	colorCorrection.Saturation = 0.03
	colorCorrection.Parent = Lighting
end

local activeShake = 0
local shakeConnection: RBXScriptConnection? = nil

local function applyCameraShake(intensity: number, duration: number)
	if shakeConnection then
		shakeConnection:Disconnect()
	end

	activeShake = intensity
	local started = os.clock()

	shakeConnection = RunService.RenderStepped:Connect(function()
		if not camera then
			return
		end

		local elapsed = os.clock() - started
		if elapsed >= duration then
			if shakeConnection then
				shakeConnection:Disconnect()
				shakeConnection = nil
			end
			return
		end

		local damper = 1 - (elapsed / duration)
		local offset = Vector3.new(
			(math.random() - 0.5) * activeShake * damper,
			(math.random() - 0.5) * activeShake * damper,
			0
		)
		camera.CFrame *= CFrame.new(offset)
	end)
end

local function pulseFov()
	if not camera then
		return
	end

	local expand = TweenService:Create(camera, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FieldOfView = 74 })
	local contract = TweenService:Create(camera, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FieldOfView = 70 })
	expand:Play()
	expand.Completed:Wait()
	contract:Play()
end

local function showNotification(text: string, tone: string?)
	notification.Visible = true
	notification.Text = text
	notification.TextTransparency = 0

	if tone == "warn" then
		notification.TextColor3 = Color3.fromRGB(255, 186, 97)
	elseif tone == "success" then
		notification.TextColor3 = Color3.fromRGB(125, 255, 165)
	elseif tone == "gain" then
		notification.TextColor3 = Color3.fromRGB(131, 217, 255)
	else
		notification.TextColor3 = Color3.fromRGB(255, 255, 255)
	end

	TweenService:Create(notification, TweenInfo.new(0.2), { BackgroundTransparency = 0.1 }):Play()
	task.delay(1.0, function()
		local fade = TweenService:Create(notification, TweenInfo.new(0.25), { TextTransparency = 1, BackgroundTransparency = 1 })
		fade:Play()
		fade.Completed:Wait()
		notification.Visible = false
		notification.BackgroundTransparency = 0.2
	end)
end

local leaderstats = player:WaitForChild("leaderstats", 30)
if not leaderstats then
	warn("[IncrementalUI] leaderstats missing")
	return
end

local statValues = {
	Strength = leaderstats:WaitForChild("Strength") :: IntValue,
	Durability = leaderstats:WaitForChild("Durability") :: IntValue,
	Speed = leaderstats:WaitForChild("Speed") :: IntValue,
	JumpPower = leaderstats:WaitForChild("JumpPower") :: IntValue,
	Coins = leaderstats:WaitForChild("Coins") :: IntValue,
	Power = leaderstats:WaitForChild("Power") :: IntValue,
	Rebirths = leaderstats:WaitForChild("Rebirths") :: IntValue,
}

local function statCost(statName: string): number
	local value = statValues[statName]
	return IncrementalConfig.GetStatCost(statName, value.Value)
end

local function refreshUI()
	statsLabel.Text = string.format(
		"Coins: %d\nPower: %d / %d (Portal)\nRebirths: %d\nSTR %d | DUR %d | SPD %d | JMP %d",
		statValues.Coins.Value,
		statValues.Power.Value,
		IncrementalConfig.PortalRequirement,
		statValues.Rebirths.Value,
		statValues.Strength.Value,
		statValues.Durability.Value,
		statValues.Speed.Value,
		statValues.JumpPower.Value
	)

	strengthButton.Text = ("Strength (+1)\nCost: %d"):format(statCost("Strength"))
	durabilityButton.Text = ("Durability (+1)\nCost: %d"):format(statCost("Durability"))
	speedButton.Text = ("Speed (+1)\nCost: %d"):format(statCost("Speed"))
	jumpButton.Text = ("JumpPower (+1)\nCost: %d"):format(statCost("JumpPower"))
	rebirthButton.Text = ("Rebirth (Need %d Power)"):format(IncrementalConfig.RebirthRequirement)
end

for _, valueObj in statValues do
	valueObj:GetPropertyChangedSignal("Value"):Connect(refreshUI)
end
refreshUI()

trainButton.MouseButton1Click:Connect(function()
	trainTapRemote:FireServer()
end)

strengthButton.MouseButton1Click:Connect(function()
	trainStatRemote:FireServer("Strength")
end)
durabilityButton.MouseButton1Click:Connect(function()
	trainStatRemote:FireServer("Durability")
end)
speedButton.MouseButton1Click:Connect(function()
	trainStatRemote:FireServer("Speed")
end)
jumpButton.MouseButton1Click:Connect(function()
	trainStatRemote:FireServer("JumpPower")
end)
rebirthButton.MouseButton1Click:Connect(function()
	requestRebirthRemote:FireServer()
end)

notifyRemote.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end

	local text = payload.text
	if type(text) == "string" then
		showNotification(text, payload.tone)
	end

	if payload.trainPulse == true then
		task.spawn(pulseFov)
		applyCameraShake(0.2, 0.11)
	end
end)
