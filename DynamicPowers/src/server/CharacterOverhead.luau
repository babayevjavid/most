-- Server-created BillboardGui on character Head — visible to all players (replicated).
-- Mix of scale + explicit BillboardGui Size per game design.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local HEALTH_GREEN = Color3.fromRGB(72, 214, 118)
local HEALTH_GREEN_DIM = Color3.fromRGB(48, 160, 95)
local HEALTH_PANEL_BG = Color3.fromRGB(16, 28, 22)
local HEALTH_TEXT = Color3.fromRGB(220, 255, 230)

local STROKE_BY_POWER: { [string]: Color3 } = {
	Electrokinesis = Color3.fromRGB(70, 140, 255),
	Hydrokinesis = Color3.fromRGB(150, 220, 255),
	Chlorokinesis = Color3.fromRGB(80, 210, 110),
}

local BILLBOARD_SIZE = UDim2.new(5, 0, 2, 0)

local M = {}

local function strokeForPlayer(player: Player): Color3
	local p = player:GetAttribute("SelectedPower")
	if typeof(p) == "string" and STROKE_BY_POWER[p] then
		return STROKE_BY_POWER[p]
	end
	return HEALTH_GREEN_DIM
end

function M.attach(player: Player, character: Model)
	local head = character:FindFirstChild("Head") :: BasePart?
	local hum = character:FindFirstChildOfClass("Humanoid")
	if not head or not hum then
		return
	end

	local old = head:FindFirstChild("PowerStatusBillboard")
	if old then
		old:Destroy()
	end

	local displayName = (player.DisplayName ~= "" and player.DisplayName) or player.Name
	local strokeColor = strokeForPlayer(player)

	local bb = Instance.new("BillboardGui")
	bb.Name = "PowerStatusBillboard"
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 140
	bb.Size = BILLBOARD_SIZE
	bb.StudsOffset = Vector3.new(0, 2.5, 0)
	bb.Adornee = head
	bb.Parent = head

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.BackgroundColor3 = HEALTH_PANEL_BG
	root.BorderSizePixel = 0
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = bb

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.06, 0)
	corner.Parent = root

	local stroke = Instance.new("UIStroke")
	stroke.Color = strokeColor
	stroke.Thickness = 1
	stroke.Transparency = 0.35
	stroke.Parent = root

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "PlayerName"
	nameLabel.BackgroundTransparency = 1
	nameLabel.TextColor3 = HEALTH_TEXT
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextScaled = true
	nameLabel.Text = displayName
	nameLabel.Size = UDim2.fromScale(1, 0.45)
	nameLabel.Position = UDim2.fromScale(0, 0)
	nameLabel.Parent = root

	local barArea = Instance.new("Frame")
	barArea.Name = "BarArea"
	barArea.BackgroundTransparency = 1
	barArea.Size = UDim2.fromScale(0.92, 0.38)
	barArea.Position = UDim2.fromScale(0.5, 0.72)
	barArea.AnchorPoint = Vector2.new(0.5, 0.5)
	barArea.Parent = root

	local barBg = Instance.new("Frame")
	barBg.Name = "Bg"
	barBg.BackgroundColor3 = Color3.fromRGB(24, 44, 32)
	barBg.BorderSizePixel = 0
	barBg.Size = UDim2.fromScale(1, 1)
	barBg.Parent = barArea

	local bgCorner = Instance.new("UICorner")
	bgCorner.CornerRadius = UDim.new(0.25, 0)
	bgCorner.Parent = barBg

	local barFill = Instance.new("Frame")
	barFill.Name = "Fill"
	barFill.BackgroundColor3 = HEALTH_GREEN
	barFill.BorderSizePixel = 0
	barFill.Size = UDim2.fromScale(1, 1)
	barFill.Parent = barBg

	local fillC = Instance.new("UICorner")
	fillC.CornerRadius = UDim.new(0.25, 0)
	fillC.Parent = barFill

	local barTween: Tween? = nil
	local firstBar = true

	local function updateBar()
		local maxH = hum.MaxHealth
		local h = hum.Health
		if maxH <= 0 then
			return
		end
		local ratio = math.clamp(h / maxH, 0, 1)
		local target = UDim2.fromScale(ratio, 1)
		if barTween then
			barTween:Cancel()
			barTween = nil
		end
		if firstBar then
			barFill.Size = target
			firstBar = false
		else
			barTween = TweenService:Create(
				barFill,
				TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Size = target }
			)
			barTween:Play()
		end
	end

	updateBar()
	hum:GetPropertyChangedSignal("Health"):Connect(updateBar)
	hum:GetPropertyChangedSignal("MaxHealth"):Connect(updateBar)
end

function M.tryAttach(player: Player)
	if player:GetAttribute("SelectedPower") == nil then
		return
	end
	local char = player.Character
	if char then
		M.attach(player, char)
	end
end

function M.init()
	local function hookPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			if player:GetAttribute("SelectedPower") ~= nil then
				task.defer(function()
					M.attach(player, character)
				end)
			end
		end)

		player:GetAttributeChangedSignal("SelectedPower"):Connect(function()
			M.tryAttach(player)
		end)

		if player.Character and player:GetAttribute("SelectedPower") ~= nil then
			task.defer(function()
				M.tryAttach(player)
			end)
		end
	end

	for _, p in Players:GetPlayers() do
		hookPlayer(p)
	end
	Players.PlayerAdded:Connect(hookPlayer)
end

return M
