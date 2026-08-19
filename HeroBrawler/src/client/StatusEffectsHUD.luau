--!strict

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StatusEffectHelper = require(ReplicatedStorage.Shared.StatusEffectHelper)

local StatusEffectsHUD = {}

function StatusEffectsHUD.create(playerGui: PlayerGui)
	local player = Players.LocalPlayer
	local guiInset = GuiService:GetGuiInset()

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "StatusEffectsHUD"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 6
	screenGui.Parent = playerGui

	local panel = Instance.new("Frame")
	panel.Name = "EffectsPanel"
	panel.AnchorPoint = Vector2.new(1, 1)
	panel.Position = UDim2.new(1, -(guiInset.X + 16), 1, -(guiInset.Y + 24))
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.Size = UDim2.fromOffset(220, 0)
	panel.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
	panel.BackgroundTransparency = 0.18
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = panel

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = panel

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 16)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamMedium
	title.Text = "Effects"
	title.TextColor3 = Color3.fromRGB(200, 200, 210)
	title.TextSize = 12
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.LayoutOrder = 0
	title.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = panel

	local function rebuild(effects: { StatusEffectHelper.ActiveEffect })
		for _, child in panel:GetChildren() do
			if child:IsA("Frame") and child.Name == "EffectRow" then
				child:Destroy()
			end
		end
		title.Visible = #effects > 0
		panel.Visible = #effects > 0
		for i, effect in effects do
			local row = Instance.new("Frame")
			row.Name = "EffectRow"
			row.LayoutOrder = i
			row.Size = UDim2.new(1, 0, 0, 34)
			row.BackgroundColor3 = Color3.fromRGB(28, 28, 36)
			row.BackgroundTransparency = 0.2
			row.BorderSizePixel = 0
			row.Parent = panel

			local rowCorner = Instance.new("UICorner")
			rowCorner.CornerRadius = UDim.new(0, 5)
			rowCorner.Parent = row

			local nameLabel = Instance.new("TextLabel")
			nameLabel.Size = UDim2.new(1, -44, 0, 14)
			nameLabel.Position = UDim2.fromOffset(6, 4)
			nameLabel.BackgroundTransparency = 1
			nameLabel.Font = Enum.Font.GothamMedium
			nameLabel.Text = effect.name
			nameLabel.TextColor3 = Color3.fromRGB(235, 235, 240)
			nameLabel.TextSize = 11
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.Parent = row

			local descLabel = Instance.new("TextLabel")
			descLabel.Size = UDim2.new(1, -44, 0, 12)
			descLabel.Position = UDim2.fromOffset(6, 18)
			descLabel.BackgroundTransparency = 1
			descLabel.Font = Enum.Font.Gotham
			descLabel.Text = effect.description
			descLabel.TextColor3 = Color3.fromRGB(150, 150, 165)
			descLabel.TextSize = 9
			descLabel.TextTruncate = Enum.TextTruncate.AtEnd
			descLabel.TextXAlignment = Enum.TextXAlignment.Left
			descLabel.Parent = row

			local timeLabel = Instance.new("TextLabel")
			timeLabel.AnchorPoint = Vector2.new(1, 0.5)
			timeLabel.Position = UDim2.new(1, -6, 0.5, 0)
			timeLabel.Size = UDim2.fromOffset(36, 16)
			timeLabel.BackgroundTransparency = 1
			timeLabel.Font = Enum.Font.GothamBold
			timeLabel.Text = string.format("%.1fs", effect.remaining)
			timeLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
			timeLabel.TextSize = 11
			timeLabel.TextXAlignment = Enum.TextXAlignment.Right
			timeLabel.Parent = row
		end
	end

	-- Only status effects (slow, freeze, burn, ragdoll, etc.) — not ability active states
	RunService.RenderStepped:Connect(function()
		local character = player.Character
		if not character then
			panel.Visible = false
			return
		end
		rebuild(StatusEffectHelper.getActive(character))
	end)
end

return StatusEffectsHUD
