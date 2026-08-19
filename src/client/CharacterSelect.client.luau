local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local shared = ReplicatedStorage:WaitForChild("Shared", 30)
if not shared then
	warn("[CharacterSelect] ReplicatedStorage.Shared missing.")
	return
end

local characterConfigModule = shared:WaitForChild("CharacterConfig", 10)
local ok, CharacterConfig = pcall(require, characterConfigModule)
if not ok or type(CharacterConfig) ~= "table" then
	warn("[CharacterSelect] Failed to require CharacterConfig.")
	return
end

local remotesFolder = ReplicatedStorage:WaitForChild(CharacterConfig.RemotesFolderName, 30)
if not remotesFolder then
	warn("[CharacterSelect] Character remotes folder missing.")
	return
end

local selectRemote = remotesFolder:WaitForChild(CharacterConfig.SelectionRemoteName, 10)
if not selectRemote or not selectRemote:IsA("RemoteEvent") then
	warn("[CharacterSelect] Selection remote missing.")
	return
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CharmedCharacterUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local chooserFrame = Instance.new("Frame")
chooserFrame.Name = "ChooserFrame"
chooserFrame.AnchorPoint = Vector2.new(1, 1)
chooserFrame.Position = UDim2.new(1, -20, 1, -20)
chooserFrame.Size = UDim2.fromOffset(280, 210)
chooserFrame.BackgroundColor3 = Color3.fromRGB(29, 22, 45)
chooserFrame.BackgroundTransparency = 0.15
chooserFrame.BorderSizePixel = 0
chooserFrame.Parent = screenGui

local chooserCorner = Instance.new("UICorner")
chooserCorner.CornerRadius = UDim.new(0, 10)
chooserCorner.Parent = chooserFrame

local chooserStroke = Instance.new("UIStroke")
chooserStroke.Thickness = 2
chooserStroke.Color = Color3.fromRGB(183, 152, 255)
chooserStroke.Parent = chooserFrame

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Size = UDim2.new(1, -16, 0, 38)
title.Position = UDim2.fromOffset(8, 6)
title.Font = Enum.Font.GothamBold
title.TextSize = 20
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.fromRGB(255, 236, 255)
title.Text = "Choose a Charmed One"
title.Parent = chooserFrame

local buttonsFrame = Instance.new("Frame")
buttonsFrame.BackgroundTransparency = 1
buttonsFrame.Size = UDim2.new(1, -16, 1, -52)
buttonsFrame.Position = UDim2.fromOffset(8, 44)
buttonsFrame.Parent = chooserFrame

local grid = Instance.new("UIGridLayout")
grid.CellSize = UDim2.fromOffset(126, 68)
grid.CellPadding = UDim2.fromOffset(8, 8)
grid.FillDirectionMaxCells = 2
grid.Parent = buttonsFrame

local statsFrame = Instance.new("Frame")
statsFrame.Name = "StatsFrame"
statsFrame.AnchorPoint = Vector2.new(0, 1)
statsFrame.Position = UDim2.new(0, 20, 1, -20)
statsFrame.Size = UDim2.fromOffset(310, 120)
statsFrame.BackgroundColor3 = Color3.fromRGB(16, 16, 22)
statsFrame.BackgroundTransparency = 0.2
statsFrame.BorderSizePixel = 0
statsFrame.Visible = false
statsFrame.Parent = screenGui

local statsCorner = Instance.new("UICorner")
statsCorner.CornerRadius = UDim.new(0, 10)
statsCorner.Parent = statsFrame

local statsStroke = Instance.new("UIStroke")
statsStroke.Thickness = 1.5
statsStroke.Color = Color3.fromRGB(160, 160, 225)
statsStroke.Parent = statsFrame

local selectedLabel = Instance.new("TextLabel")
selectedLabel.BackgroundTransparency = 1
selectedLabel.Size = UDim2.new(1, -16, 0, 30)
selectedLabel.Position = UDim2.fromOffset(8, 6)
selectedLabel.Font = Enum.Font.GothamSemibold
selectedLabel.TextSize = 18
selectedLabel.TextColor3 = Color3.fromRGB(235, 220, 255)
selectedLabel.TextXAlignment = Enum.TextXAlignment.Left
selectedLabel.Text = "Character: -"
selectedLabel.Parent = statsFrame

local function createBar(yOffset: number, labelText: string, fillColor: Color3): (Frame, TextLabel)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -16, 0, 20)
	label.Position = UDim2.fromOffset(8, yOffset)
	label.Font = Enum.Font.Gotham
	label.TextSize = 16
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Text = labelText
	label.Parent = statsFrame

	local barBg = Instance.new("Frame")
	barBg.Size = UDim2.new(1, -16, 0, 16)
	barBg.Position = UDim2.fromOffset(8, yOffset + 22)
	barBg.BackgroundColor3 = Color3.fromRGB(55, 55, 70)
	barBg.BorderSizePixel = 0
	barBg.Parent = statsFrame

	local bgCorner = Instance.new("UICorner")
	bgCorner.CornerRadius = UDim.new(0, 8)
	bgCorner.Parent = barBg

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = fillColor
	fill.BorderSizePixel = 0
	fill.Parent = barBg

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 8)
	fillCorner.Parent = fill

	return fill, label
end

local healthFill, healthLabel = createBar(36, "Health: 100 / 100", Color3.fromRGB(255, 90, 110))
local energyFill, energyLabel = createBar(74, "Energy: 100 / 100", Color3.fromRGB(110, 180, 255))

local selectedCharacter: string? = nil
local humanoidConn: RBXScriptConnection? = nil
local energyConn: RBXScriptConnection? = nil

local function updateBar(fillFrame: Frame, ratio: number)
	fillFrame.Size = UDim2.fromScale(math.clamp(ratio, 0, 1), 1)
end

local function updateHealthUi(humanoid: Humanoid)
	local maxHealth = math.max(humanoid.MaxHealth, 1)
	local health = math.clamp(humanoid.Health, 0, maxHealth)
	healthLabel.Text = string.format("Health: %d / %d", math.floor(health + 0.5), math.floor(maxHealth + 0.5))
	updateBar(healthFill, health / maxHealth)
end

local function updateEnergyUi(energyValue: number)
	local maxEnergy = math.max(CharacterConfig.DefaultEnergy, 1)
	local current = math.clamp(energyValue, 0, maxEnergy)
	energyLabel.Text = string.format("Energy: %d / %d", math.floor(current + 0.5), maxEnergy)
	updateBar(energyFill, current / maxEnergy)
end

local function hookCharacter(character: Model)
	if humanoidConn then
		humanoidConn:Disconnect()
		humanoidConn = nil
	end
	if energyConn then
		energyConn:Disconnect()
		energyConn = nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	updateHealthUi(humanoid)
	humanoidConn = humanoid.HealthChanged:Connect(function()
		updateHealthUi(humanoid)
	end)

	updateEnergyUi((player:GetAttribute("Energy") or CharacterConfig.DefaultEnergy) :: number)
	energyConn = player:GetAttributeChangedSignal("Energy"):Connect(function()
		local energy = player:GetAttribute("Energy")
		if type(energy) == "number" then
			updateEnergyUi(energy)
		end
	end)
end

for _, characterName in CharacterConfig.Choices do
	local button = Instance.new("TextButton")
	button.Text = characterName
	button.Font = Enum.Font.GothamBold
	button.TextSize = 20
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.BackgroundColor3 = Color3.fromRGB(80, 53, 117)
	button.AutoButtonColor = true
	button.BorderSizePixel = 0
	button.Parent = buttonsFrame

	local buttonCorner = Instance.new("UICorner")
	buttonCorner.CornerRadius = UDim.new(0, 8)
	buttonCorner.Parent = button

	button.MouseButton1Click:Connect(function()
		selectedCharacter = characterName
		selectedLabel.Text = "Character: " .. characterName
		statsFrame.Visible = true
		chooserFrame.Visible = false
		(selectRemote :: RemoteEvent):FireServer(characterName)

		local character = player.Character
		if character then
			hookCharacter(character)
		end
	end)
end

player.CharacterAdded:Connect(function(character)
	if selectedCharacter then
		statsFrame.Visible = true
		hookCharacter(character)
	end
end)
