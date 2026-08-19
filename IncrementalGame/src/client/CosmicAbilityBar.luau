local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PowerConfig = require(Shared:WaitForChild("PowerConfig"))
local WorldStyle = require(Shared:WaitForChild("WorldStyle"))

local palette = WorldStyle.Palette
local fonts = WorldStyle.Fonts

local KEYBINDS = {
	Enum.KeyCode.One,
	Enum.KeyCode.Two,
	Enum.KeyCode.Three,
	Enum.KeyCode.Four,
	Enum.KeyCode.Five,
}

local CosmicAbilityBar = {}

function CosmicAbilityBar.Start()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local remotes = ReplicatedStorage:WaitForChild("SuperpowerRemotes", 20)
	if not remotes then
		return
	end

	local activateAbility = remotes:WaitForChild("ActivateAbility", 10) :: RemoteFunction
	local powersSync = remotes:WaitForChild("PowersSync", 10) :: RemoteEvent
	local abilityUsed = remotes:WaitForChild("AbilityUsed", 10) :: RemoteEvent
	if not activateAbility or not powersSync then
		return
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "AbilityBar"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGui

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -20)
	bar.Size = UDim2.fromOffset(360, 62)
	bar.BackgroundTransparency = 1
	bar.Parent = screenGui

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.Parent = bar

	local slotFrames: { Frame } = {}
	local equipped: { string } = {}

	local function rebuildBar()
		for _, frame in slotFrames do
			frame:Destroy()
		end
		table.clear(slotFrames)

		for slotIndex = 1, PowerConfig.MaxEquipped do
			local powerId = equipped[slotIndex]
			local power = if powerId then PowerConfig.Powers[powerId] else nil

			local slot = Instance.new("Frame")
			slot.Name = ("Slot_%d"):format(slotIndex)
			slot.Size = UDim2.fromOffset(64, 58)
			slot.BackgroundColor3 = Color3.fromRGB(24, 27, 34)
			slot.BorderSizePixel = 0
			slot.Parent = bar
			table.insert(slotFrames, slot)

			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 8)
			corner.Parent = slot

			local stroke = Instance.new("UIStroke")
			stroke.Color = if power then power.Color else Color3.fromRGB(58, 62, 72)
			stroke.Thickness = 2
			stroke.Parent = slot

			local keyLabel = Instance.new("TextLabel")
			keyLabel.Size = UDim2.new(1, 0, 0, 16)
			keyLabel.BackgroundTransparency = 1
			keyLabel.Font = fonts.Label
			keyLabel.TextSize = 11
			keyLabel.TextColor3 = palette.TextMuted
			keyLabel.Text = tostring(slotIndex)
			keyLabel.Parent = slot

			local icon = Instance.new("TextLabel")
			icon.Size = UDim2.new(1, 0, 0, 24)
			icon.Position = UDim2.fromOffset(0, 14)
			icon.BackgroundTransparency = 1
			icon.Font = fonts.Display
			icon.TextSize = 20
			icon.TextColor3 = if power then power.Color else palette.TextMuted
			icon.Text = if power then power.Icon else "·"
			icon.Parent = slot

			local nameLabel = Instance.new("TextLabel")
			nameLabel.Size = UDim2.new(1, -4, 0, 16)
			nameLabel.Position = UDim2.fromOffset(2, 38)
			nameLabel.BackgroundTransparency = 1
			nameLabel.Font = fonts.Label
			nameLabel.TextSize = 9
			nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
			nameLabel.TextColor3 = palette.TextPrimary
			if power then
				if power.ActiveAbility then
					nameLabel.Text = power.ActiveAbility.DisplayAction
				else
					nameLabel.Text = "Passive"
				end
			else
				nameLabel.Text = "Empty"
			end
			nameLabel.Parent = slot
		end
	end

	powersSync.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		equipped = payload.equipped or {}
		rebuildBar()
	end)

	if abilityUsed then
		abilityUsed.OnClientEvent:Connect(function(slotIndex: number, _powerId: string)
			local slotFrame = slotFrames[slotIndex]
			if not slotFrame then
				return
			end
			slotFrame.BackgroundColor3 = Color3.fromRGB(48, 52, 62)
			task.delay(0.15, function()
				if slotFrame.Parent then
					slotFrame.BackgroundColor3 = Color3.fromRGB(24, 27, 34)
				end
			end)
		end)
	end

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end

		for slotIndex, keyCode in KEYBINDS do
			if input.KeyCode == keyCode then
				activateAbility:InvokeServer(slotIndex)
				break
			end
		end
	end)

	rebuildBar()
end

return CosmicAbilityBar
