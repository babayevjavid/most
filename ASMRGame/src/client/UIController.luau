local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UIController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Palette = {
	surface = Color3.fromRGB(255, 255, 255),
	ink = Color3.fromRGB(48, 44, 52),
	muted = Color3.fromRGB(118, 112, 122),
	accent = Color3.fromRGB(108, 158, 138),
	accentSoft = Color3.fromRGB(186, 218, 202),
	stroke = Color3.fromRGB(220, 214, 228),
}

local satisfactionValue: TextLabel
local hintLabel: TextLabel

local function glassFrame(name: string, size: UDim2, pos: UDim2, parent: Instance): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = size
	frame.Position = pos
	frame.BackgroundColor3 = Palette.surface
	frame.BackgroundTransparency = 0.22
	frame.BorderSizePixel = 0
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Palette.stroke
	stroke.Thickness = 1
	stroke.Transparency = 0.45
	stroke.Parent = frame

	return frame
end

local function buildTopBar(parent: Instance)
	local bar = glassFrame("TopBar", UDim2.new(0, 210, 0, 40), UDim2.new(0.5, -105, 0, 12), parent)

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(0, 110, 1, 0)
	title.Position = UDim2.fromOffset(14, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 13
	title.TextColor3 = Palette.ink
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "asmr studio"
	title.Parent = bar

	local divider = Instance.new("Frame")
	divider.Size = UDim2.fromOffset(1, 18)
	divider.Position = UDim2.new(0, 128, 0.5, -9)
	divider.BackgroundColor3 = Palette.stroke
	divider.BackgroundTransparency = 0.3
	divider.BorderSizePixel = 0
	divider.Parent = bar

	local calmLabel = Instance.new("TextLabel")
	calmLabel.Size = UDim2.fromOffset(36, 1)
	calmLabel.Position = UDim2.fromOffset(138, 0)
	calmLabel.BackgroundTransparency = 1
	calmLabel.Font = Enum.Font.GothamMedium
	calmLabel.TextSize = 11
	calmLabel.TextColor3 = Palette.muted
	calmLabel.TextXAlignment = Enum.TextXAlignment.Left
	calmLabel.Text = "calm"
	calmLabel.Parent = bar

	satisfactionValue = Instance.new("TextLabel")
	satisfactionValue.Name = "Score"
	satisfactionValue.Size = UDim2.new(1, -150, 1, 0)
	satisfactionValue.Position = UDim2.fromOffset(172, 0)
	satisfactionValue.BackgroundTransparency = 1
	satisfactionValue.Font = Enum.Font.Code
	satisfactionValue.TextSize = 15
	satisfactionValue.TextColor3 = Palette.accent
	satisfactionValue.TextXAlignment = Enum.TextXAlignment.Left
	satisfactionValue.Text = "0"
	satisfactionValue.Parent = bar
end

local function buildHint(parent: Instance)
	hintLabel = Instance.new("TextLabel")
	hintLabel.Name = "Hint"
	hintLabel.Size = UDim2.fromOffset(260, 20)
	hintLabel.Position = UDim2.new(0.5, -130, 1, -36)
	hintLabel.BackgroundTransparency = 1
	hintLabel.Font = Enum.Font.GothamMedium
	hintLabel.TextSize = 12
	hintLabel.TextColor3 = Palette.muted
	hintLabel.TextTransparency = 0.15
	hintLabel.TextXAlignment = Enum.TextXAlignment.Center
	hintLabel.Text = "walk near objects — sounds play automatically"
	hintLabel.Parent = parent

	task.delay(6, function()
		if not hintLabel then
			return
		end
		TweenService:Create(
			hintLabel,
			TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ TextTransparency = 1 }
		):Play()
	end)
end

local function buildHud()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ASMRHud"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui

	buildTopBar(screenGui)
	buildHint(screenGui)
end

local function animateSatisfaction(count: number)
	if not satisfactionValue then
		return
	end
	satisfactionValue.Text = tostring(count)
	TweenService:Create(
		satisfactionValue,
		TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ TextColor3 = Palette.accentSoft }
	):Play()
	task.delay(0.12, function()
		if satisfactionValue then
			TweenService:Create(
				satisfactionValue,
				TweenInfo.new(0.2),
				{ TextColor3 = Palette.accent }
			):Play()
		end
	end)
end

function UIController.Start()
	buildHud()

	local remotes = ReplicatedStorage:WaitForChild("ASMRRemotes", 30)
	if not remotes then
		return
	end

	local satisfactionRemote = remotes:WaitForChild("SatisfactionUpdate") :: RemoteEvent
	satisfactionRemote.OnClientEvent:Connect(function(count: number)
		animateSatisfaction(count)
	end)
end

return UIController
