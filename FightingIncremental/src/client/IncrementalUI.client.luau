local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera

local shared = ReplicatedStorage:WaitForChild("Shared")
local IncrementalConfig = require(shared:WaitForChild("IncrementalConfig"))
local remotesFolder = ReplicatedStorage:WaitForChild("IncrementalRemotes")
local notifyRemote = remotesFolder:WaitForChild("Notify") :: RemoteEvent

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "IncrementalMinimalUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local hudFrame = Instance.new("Frame")
hudFrame.Name = "Hud"
hudFrame.AnchorPoint = Vector2.new(0, 0)
hudFrame.Position = UDim2.fromOffset(20, 20)
hudFrame.Size = UDim2.fromOffset(300, 160)
hudFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
hudFrame.BackgroundTransparency = 0.18
hudFrame.BorderSizePixel = 0
hudFrame.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = hudFrame

local stroke = Instance.new("UIStroke")
stroke.Thickness = 1
stroke.Color = Color3.fromRGB(85, 85, 95)
stroke.Transparency = 0.25
stroke.Parent = hudFrame

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Size = UDim2.new(1, -20, 0, 24)
title.Position = UDim2.fromOffset(10, 8)
title.Font = Enum.Font.GothamSemibold
title.TextSize = 16
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.fromRGB(240, 240, 245)
title.Text = "Fighting Incremental"
title.Parent = hudFrame

local statsText = Instance.new("TextLabel")
statsText.BackgroundTransparency = 1
statsText.Size = UDim2.new(1, -20, 1, -62)
statsText.Position = UDim2.fromOffset(10, 34)
statsText.Font = Enum.Font.Code
statsText.TextSize = 15
statsText.TextXAlignment = Enum.TextXAlignment.Left
statsText.TextYAlignment = Enum.TextYAlignment.Top
statsText.TextWrapped = true
statsText.TextColor3 = Color3.fromRGB(210, 220, 235)
statsText.Text = "Loading..."
statsText.Parent = hudFrame

local hint = Instance.new("TextLabel")
hint.BackgroundTransparency = 1
hint.Size = UDim2.new(1, -20, 0, 22)
hint.Position = UDim2.new(0, 10, 1, -26)
hint.Font = Enum.Font.Gotham
hint.TextSize = 12
hint.TextXAlignment = Enum.TextXAlignment.Left
hint.TextColor3 = Color3.fromRGB(170, 175, 190)
hint.Text = "Use the physical ground buttons to train."
hint.Parent = hudFrame

local toast = Instance.new("TextLabel")
toast.BackgroundTransparency = 0.25
toast.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
toast.Size = UDim2.fromOffset(280, 36)
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.Position = UDim2.new(0.5, 0, 0, 18)
toast.BorderSizePixel = 0
toast.Visible = false
toast.Font = Enum.Font.GothamSemibold
toast.TextSize = 16
toast.TextColor3 = Color3.fromRGB(240, 240, 245)
toast.Parent = screenGui

local toastCorner = Instance.new("UICorner")
toastCorner.CornerRadius = UDim.new(0, 8)
toastCorner.Parent = toast

local leaderstats = player:WaitForChild("leaderstats", 30)
if not leaderstats then
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

local function getCost(statName: string): number
	local value = statValues[statName]
	return IncrementalConfig.GetStatCost(statName, value.Value)
end

local function refreshHud()
	statsText.Text = string.format(
		"Coins: %d    Power: %d\nRebirths: %d\nSTR %d (C:%d)\nDUR %d (C:%d)\nSPD %d (C:%d)   JMP %d (C:%d)",
		statValues.Coins.Value,
		statValues.Power.Value,
		statValues.Rebirths.Value,
		statValues.Strength.Value,
		getCost("Strength"),
		statValues.Durability.Value,
		getCost("Durability"),
		statValues.Speed.Value,
		getCost("Speed"),
		statValues.JumpPower.Value,
		getCost("JumpPower")
	)
end

for _, stat in statValues do
	stat:GetPropertyChangedSignal("Value"):Connect(refreshHud)
end
refreshHud()

local function showToast(message: string, tone: string?)
	toast.Visible = true
	toast.TextTransparency = 0
	toast.Text = message

	if tone == "warn" then
		toast.TextColor3 = Color3.fromRGB(255, 197, 122)
	elseif tone == "success" then
		toast.TextColor3 = Color3.fromRGB(163, 255, 163)
	elseif tone == "gain" then
		toast.TextColor3 = Color3.fromRGB(153, 216, 255)
	else
		toast.TextColor3 = Color3.fromRGB(240, 240, 245)
	end

	task.delay(1.1, function()
		local tween = TweenService:Create(toast, TweenInfo.new(0.25), { TextTransparency = 1 })
		tween:Play()
		tween.Completed:Wait()
		toast.Visible = false
	end)
end

notifyRemote.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end

	if type(payload.text) == "string" then
		showToast(payload.text, payload.tone)
	end

	if payload.trainPulse and camera then
		local expand = TweenService:Create(camera, TweenInfo.new(0.06), { FieldOfView = 72 })
		local settle = TweenService:Create(camera, TweenInfo.new(0.1), { FieldOfView = 70 })
		expand:Play()
		expand.Completed:Wait()
		settle:Play()
	end
end)
