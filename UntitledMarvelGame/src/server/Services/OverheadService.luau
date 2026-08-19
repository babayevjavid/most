--!strict

local Players = game:GetService("Players")

local OverheadService = {}

local PLATE_NAME = "OverheadPlate"
local HEALTH_COLOR = Color3.fromRGB(72, 188, 96)
local HEALTH_DARK = Color3.fromRGB(42, 118, 56)

local function getAdornee(character: Model): BasePart?
	return character:FindFirstChild("Head") :: BasePart?
		or character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function styleTextLabel(label: TextLabel, size: number, bold: boolean)
	label.BackgroundTransparency = 1
	label.Font = if bold then Enum.Font.GothamBold else Enum.Font.GothamMedium
	label.TextSize = size
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.TextColor3 = Color3.fromRGB(245, 247, 250)
	label.TextStrokeTransparency = 0.55
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
end

local function createPlate(character: Model, title: string, subtitle: string?, showSubtitle: boolean): BillboardGui?
	local adornee = getAdornee(character)
	if not adornee then
		return nil
	end

	local existing = adornee:FindFirstChild(PLATE_NAME)
	if existing then
		existing:Destroy()
	end

	local plateHeight = if showSubtitle then 82 else 62
	local billboard = Instance.new("BillboardGui")
	billboard.Name = PLATE_NAME
	billboard.Adornee = adornee
	billboard.AlwaysOnTop = false
	billboard.LightInfluence = 0
	billboard.MaxDistance = 90
	billboard.Size = UDim2.fromOffset(220, plateHeight)
	billboard.StudsOffset = Vector3.new(0, 2.8, 0)
	billboard.Parent = adornee

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Size = UDim2.fromOffset(220, plateHeight)
	root.Parent = billboard

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = root

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Title"
	nameLabel.Size = UDim2.fromOffset(210, 20)
	nameLabel.Text = title
	nameLabel.LayoutOrder = 1
	styleTextLabel(nameLabel, 17, true)
	nameLabel.Parent = root

	local subLabel = Instance.new("TextLabel")
	subLabel.Name = "Subtitle"
	subLabel.Size = UDim2.fromOffset(210, 16)
	subLabel.Text = subtitle or ""
	subLabel.Visible = showSubtitle and subtitle ~= nil and subtitle ~= ""
	subLabel.LayoutOrder = 2
	styleTextLabel(subLabel, 14, false)
	subLabel.TextColor3 = Color3.fromRGB(190, 198, 210)
	subLabel.Parent = root

	local healthRow = Instance.new("Frame")
	healthRow.Name = "HealthRow"
	healthRow.BackgroundTransparency = 1
	healthRow.Size = UDim2.fromOffset(150, 22)
	healthRow.LayoutOrder = 3
	healthRow.Parent = root

	local healthTrack = Instance.new("Frame")
	healthTrack.Name = "Track"
	healthTrack.AnchorPoint = Vector2.new(0.5, 0)
	healthTrack.BackgroundColor3 = Color3.fromRGB(22, 26, 32)
	healthTrack.BackgroundTransparency = 0.35
	healthTrack.BorderSizePixel = 0
	healthTrack.Position = UDim2.new(0.5, 0, 0, 0)
	healthTrack.Size = UDim2.fromOffset(130, 8)
	healthTrack.ClipsDescendants = true
	healthTrack.Parent = healthRow

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(1, 0)
	trackCorner.Parent = healthTrack

	local healthFill = Instance.new("Frame")
	healthFill.Name = "Fill"
	healthFill.BackgroundColor3 = HEALTH_COLOR
	healthFill.BorderSizePixel = 0
	healthFill.Size = UDim2.fromScale(1, 1)
	healthFill.Parent = healthTrack

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = healthFill

	local fillGradient = Instance.new("UIGradient")
	fillGradient.Rotation = 90
	fillGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, HEALTH_COLOR),
		ColorSequenceKeypoint.new(1, HEALTH_DARK),
	})
	fillGradient.Parent = healthFill

	local hpText = Instance.new("TextLabel")
	hpText.Name = "HpText"
	hpText.BackgroundTransparency = 1
	hpText.Size = UDim2.fromOffset(150, 14)
	hpText.Position = UDim2.fromOffset(0, 10)
	hpText.Text = "100 HP"
	hpText.LayoutOrder = 4
	styleTextLabel(hpText, 13, false)
	hpText.TextColor3 = Color3.fromRGB(210, 216, 224)
	hpText.Parent = healthRow

	return billboard
end

local function updateHealth(character: Model, humanoid: Humanoid)
	local adornee = getAdornee(character)
	if not adornee then
		return
	end
	local billboard = adornee:FindFirstChild(PLATE_NAME) :: BillboardGui?
	if not billboard then
		return
	end
	local root = billboard:FindFirstChild("Root")
	if not root then
		return
	end
	local healthRow = root:FindFirstChild("HealthRow")
	if not healthRow then
		return
	end
	local track = healthRow:FindFirstChild("Track")
	local hpText = healthRow:FindFirstChild("HpText") :: TextLabel?
	local fill = track and track:FindFirstChild("Fill") :: Frame?
	if not fill or not hpText then
		return
	end

	local hp = math.floor(humanoid.Health + 0.5)
	local ratio = if humanoid.MaxHealth > 0 then math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1) else 0
	fill.Size = UDim2.fromScale(ratio, 1)
	hpText.Text = `{hp} HP`
end

local function bindHealth(character: Model, humanoid: Humanoid)
	updateHealth(character, humanoid)
	humanoid.HealthChanged:Connect(function()
		updateHealth(character, humanoid)
	end)
end

function OverheadService.attachNpc(character: Model)
	local player = Players:GetPlayerFromCharacter(character)
	if player then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local adornee = getAdornee(character)
	if adornee and adornee:FindFirstChild(PLATE_NAME) then
		return
	end

	createPlate(character, character.Name, nil, false)
	bindHealth(character, humanoid)
end

function OverheadService.attachPlayer(character: Model, player: Player)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local adornee = getAdornee(character)
	if adornee and adornee:FindFirstChild(PLATE_NAME) then
		return
	end

	local billboard = createPlate(character, player.DisplayName, nil, false)
	if billboard then
		billboard.Enabled = false
	end
	bindHealth(character, humanoid)
end

function OverheadService.setPlayerHero(character: Model, player: Player, heroDisplayName: string, accent: Color3?)
	local adornee = getAdornee(character)
	if not adornee then
		return
	end

	local existing = adornee:FindFirstChild(PLATE_NAME)
	if existing then
		existing:Destroy()
	end

	local billboard = createPlate(character, player.DisplayName, heroDisplayName, true)
	if not billboard then
		return
	end

	billboard.Enabled = true

	local root = billboard:FindFirstChild("Root")
	local subtitle = root and root:FindFirstChild("Subtitle") :: TextLabel?
	if subtitle and accent then
		subtitle.TextColor3 = accent
	end
end

function OverheadService.hidePlayerPlate(character: Model)
	local adornee = getAdornee(character)
	if not adornee then
		return
	end
	local billboard = adornee:FindFirstChild(PLATE_NAME) :: BillboardGui?
	if billboard then
		billboard.Enabled = false
	end
end

function OverheadService.bindCharacter(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local player = Players:GetPlayerFromCharacter(character)
	if player then
		OverheadService.attachPlayer(character, player)
	else
		OverheadService.attachNpc(character)
	end
end

function OverheadService.init()
	for _, desc in workspace:GetDescendants() do
		if desc:IsA("Model") and desc:FindFirstChildOfClass("Humanoid") then
			OverheadService.bindCharacter(desc)
		end
	end

	workspace.DescendantAdded:Connect(function(desc)
		if desc:IsA("Humanoid") then
			local character = desc.Parent
			if character and character:IsA("Model") then
				task.defer(function()
					OverheadService.bindCharacter(character)
				end)
			end
		end
	end)
end

return OverheadService
