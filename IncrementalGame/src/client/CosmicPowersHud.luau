local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PowerConfig = require(Shared:WaitForChild("PowerConfig"))
local CosmicFormat = require(Shared:WaitForChild("CosmicFormat"))
local WorldStyle = require(Shared:WaitForChild("WorldStyle"))

local palette = WorldStyle.Palette
local fonts = WorldStyle.Fonts

local CosmicPowersHud = {}

type PowerPayload = {
	owned: { [string]: boolean },
	equipped: { string },
	maxEquipped: number,
}

function CosmicPowersHud.Start()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local remotes = ReplicatedStorage:WaitForChild("SuperpowerRemotes", 20)
	if not remotes then
		return
	end

	local powersSync = remotes:WaitForChild("PowersSync", 10) :: RemoteEvent
	local buyPower = remotes:WaitForChild("BuyPower", 10) :: RemoteFunction
	local equipPower = remotes:WaitForChild("EquipPower", 10) :: RemoteFunction
	local unequipPower = remotes:WaitForChild("UnequipPower", 10) :: RemoteFunction
	if not powersSync or not buyPower or not equipPower or not unequipPower then
		return
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "PowersHud"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGui

	local openButton = Instance.new("TextButton")
	openButton.Name = "OpenPowers"
	openButton.AnchorPoint = Vector2.new(1, 0.5)
	openButton.Position = UDim2.new(1, -18, 0.5, 0)
	openButton.Size = UDim2.fromOffset(54, 140)
	openButton.BackgroundColor3 = Color3.fromRGB(28, 32, 42)
	openButton.BorderSizePixel = 0
	openButton.Font = fonts.Display
	openButton.TextSize = 15
	openButton.TextColor3 = palette.TextPrimary
	openButton.Text = "POWERS"
	openButton.AutoButtonColor = true
	openButton.Parent = screenGui

	local openStroke = Instance.new("UIStroke")
	openStroke.Color = palette.LaneStripe
	openStroke.Thickness = 2
	openStroke.Parent = openButton

	local openCorner = Instance.new("UICorner")
	openCorner.CornerRadius = UDim.new(0, 8)
	openCorner.Parent = openButton

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(1, 0.5)
	panel.Position = UDim2.new(1, -82, 0.5, 0)
	panel.Size = UDim2.fromOffset(360, 460)
	panel.BackgroundColor3 = Color3.fromRGB(22, 25, 32)
	panel.Visible = false
	panel.Parent = screenGui

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = Color3.fromRGB(58, 62, 72)
	panelStroke.Parent = panel

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 10)
	panelCorner.Parent = panel

	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, 0, 0, 44)
	header.BackgroundColor3 = Color3.fromRGB(32, 36, 46)
	header.BorderSizePixel = 0
	header.Parent = panel

	local headerStripe = Instance.new("Frame")
	headerStripe.Size = UDim2.new(1, 0, 0, 3)
	headerStripe.BackgroundColor3 = palette.LaneStripe
	headerStripe.BorderSizePixel = 0
	headerStripe.Parent = header

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(14, 10)
	title.Size = UDim2.new(1, -60, 0, 24)
	title.Font = fonts.Display
	title.TextSize = 18
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = palette.TextPrimary
	title.Text = "SUPERPOWERS"
	title.Parent = header

	local equippedLabel = Instance.new("TextLabel")
	equippedLabel.Name = "EquippedCount"
	equippedLabel.BackgroundTransparency = 1
	equippedLabel.Position = UDim2.fromOffset(14, 30)
	equippedLabel.Size = UDim2.new(1, -60, 0, 14)
	equippedLabel.Font = fonts.Label
	equippedLabel.TextSize = 11
	equippedLabel.TextXAlignment = Enum.TextXAlignment.Left
	equippedLabel.TextColor3 = palette.TextMuted
	equippedLabel.Text = "Equipped 0/5"
	equippedLabel.Parent = header

	local closeButton = Instance.new("TextButton")
	closeButton.Size = UDim2.fromOffset(28, 28)
	closeButton.Position = UDim2.new(1, -36, 0, 8)
	closeButton.BackgroundColor3 = Color3.fromRGB(48, 52, 62)
	closeButton.Font = fonts.Label
	closeButton.TextSize = 16
	closeButton.TextColor3 = palette.TextPrimary
	closeButton.Text = "×"
	closeButton.Parent = header

	local hint = Instance.new("TextLabel")
	hint.BackgroundTransparency = 1
	hint.Position = UDim2.fromOffset(14, 48)
	hint.Size = UDim2.new(1, -28, 0, 28)
	hint.Font = fonts.Label
	hint.TextSize = 11
	hint.TextWrapped = true
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.TextColor3 = palette.TextMuted
	hint.Text = "Buy & equip up to 5 powers. Press 1-5 to activate abilities."
	hint.Parent = panel

	local list = Instance.new("ScrollingFrame")
	list.Name = "PowerList"
	list.Position = UDim2.fromOffset(10, 82)
	list.Size = UDim2.new(1, -20, 1, -92)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 4
	list.CanvasSize = UDim2.fromOffset(0, 0)
	list.Parent = panel

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 8)
	listLayout.Parent = list

	local currentPayload: PowerPayload = {
		owned = {},
		equipped = {},
		maxEquipped = PowerConfig.MaxEquipped,
	}

	local function isEquipped(powerId: string): boolean
		for _, equippedId in currentPayload.equipped do
			if equippedId == powerId then
				return true
			end
		end
		return false
	end

	local function rebuildList()
		for _, child in list:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end

		equippedLabel.Text = ("Equipped %d/%d"):format(#currentPayload.equipped, currentPayload.maxEquipped)

		for _, powerId in PowerConfig.PowerOrder do
			local power = PowerConfig.Powers[powerId]
			if not power then
				continue
			end

			local owned = currentPayload.owned[powerId] == true
			local equipped = isEquipped(powerId)

			local card = Instance.new("Frame")
			card.Name = powerId
			card.Size = UDim2.new(1, -4, 0, 92)
			card.BackgroundColor3 = Color3.fromRGB(30, 34, 44)
			card.BorderSizePixel = 0
			card.Parent = list

			local cardCorner = Instance.new("UICorner")
			cardCorner.CornerRadius = UDim.new(0, 8)
			cardCorner.Parent = card

			local accent = Instance.new("Frame")
			accent.Size = UDim2.new(0, 4, 1, -8)
			accent.Position = UDim2.fromOffset(6, 4)
			accent.BackgroundColor3 = power.Color
			accent.BorderSizePixel = 0
			accent.Parent = card

			local icon = Instance.new("TextLabel")
			icon.BackgroundTransparency = 1
			icon.Position = UDim2.fromOffset(16, 8)
			icon.Size = UDim2.fromOffset(28, 28)
			icon.Font = fonts.Display
			icon.TextSize = 22
			icon.TextColor3 = power.Color
			icon.Text = power.Icon
			icon.Parent = card

			local nameLabel = Instance.new("TextLabel")
			nameLabel.BackgroundTransparency = 1
			nameLabel.Position = UDim2.fromOffset(48, 8)
			nameLabel.Size = UDim2.new(1, -130, 0, 18)
			nameLabel.Font = fonts.Board
			nameLabel.TextSize = 15
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.TextColor3 = palette.TextPrimary
			nameLabel.Text = power.DisplayName
			nameLabel.Parent = card

			local categoryLabel = Instance.new("TextLabel")
			categoryLabel.BackgroundTransparency = 1
			categoryLabel.Position = UDim2.fromOffset(48, 26)
			categoryLabel.Size = UDim2.new(1, -130, 0, 14)
			categoryLabel.Font = fonts.Label
			categoryLabel.TextSize = 11
			categoryLabel.TextXAlignment = Enum.TextXAlignment.Left
			categoryLabel.TextColor3 = palette.TextMuted
			categoryLabel.Text = power.Category
			categoryLabel.Parent = card

			local descLabel = Instance.new("TextLabel")
			descLabel.BackgroundTransparency = 1
			descLabel.Position = UDim2.fromOffset(16, 44)
			descLabel.Size = UDim2.new(1, -24, 0, 28)
			descLabel.Font = fonts.Label
			descLabel.TextSize = 11
			descLabel.TextWrapped = true
			descLabel.TextXAlignment = Enum.TextXAlignment.Left
			descLabel.TextYAlignment = Enum.TextYAlignment.Top
			descLabel.TextColor3 = palette.TextPrimary
			descLabel.Text = power.Description
			descLabel.Parent = card

			local action = Instance.new("TextButton")
			action.Size = UDim2.fromOffset(88, 30)
			action.Position = UDim2.new(1, -98, 0, 10)
			action.Font = fonts.Label
			action.TextSize = 12
			action.BorderSizePixel = 0
			action.Parent = card

			local actionCorner = Instance.new("UICorner")
			actionCorner.CornerRadius = UDim.new(0, 6)
			actionCorner.Parent = action

			if not owned then
				action.BackgroundColor3 = palette.Accent
				action.TextColor3 = palette.TextPrimary
				action.Text = CosmicFormat.Number(power.Cost)
				action.MouseButton1Click:Connect(function()
					buyPower:InvokeServer(powerId)
				end)
			elseif equipped then
				action.BackgroundColor3 = Color3.fromRGB(58, 62, 72)
				action.TextColor3 = palette.Success
				action.Text = "Equipped"
				action.MouseButton1Click:Connect(function()
					unequipPower:InvokeServer(powerId)
				end)
			else
				action.BackgroundColor3 = power.Color:Lerp(Color3.fromRGB(255, 255, 255), 0.15)
				action.TextColor3 = palette.TextPrimary
				action.Text = "Equip"
				action.MouseButton1Click:Connect(function()
					equipPower:InvokeServer(powerId)
				end)
			end
		end

		list.CanvasSize = UDim2.fromOffset(0, listLayout.AbsoluteContentSize.Y + 8)
	end

	listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		list.CanvasSize = UDim2.fromOffset(0, listLayout.AbsoluteContentSize.Y + 8)
	end)

	openButton.MouseButton1Click:Connect(function()
		panel.Visible = not panel.Visible
	end)

	closeButton.MouseButton1Click:Connect(function()
		panel.Visible = false
	end)

	powersSync.OnClientEvent:Connect(function(payload: PowerPayload)
		if type(payload) ~= "table" then
			return
		end
		currentPayload.owned = payload.owned or {}
		currentPayload.equipped = payload.equipped or {}
		currentPayload.maxEquipped = payload.maxEquipped or PowerConfig.MaxEquipped
		rebuildList()
	end)

	rebuildList()
end

return CosmicPowersHud
