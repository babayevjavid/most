--!strict
--[[ Simple bottom-left character picker shown on respawn ]]

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterRegistry = require(ReplicatedStorage.Shared.CharacterRegistry)

export type SelectionController = {
	show: () -> (),
	hide: () -> (),
	destroy: () -> (),
}

local CharacterSelectUI = {}

function CharacterSelectUI.create(playerGui: PlayerGui, onSelect: (string) -> ()): SelectionController
	local roster = CharacterRegistry.getRoster()

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "CharacterSelect"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 5
	screenGui.Enabled = false
	screenGui.Parent = playerGui

	local guiInset = GuiService:GetGuiInset()

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0, 1)
	panel.Position = UDim2.new(0, guiInset.X + 16, 1, -(guiInset.Y + 16))
	panel.AutomaticSize = Enum.AutomaticSize.XY
	panel.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
	panel.BackgroundTransparency = 0.15
	panel.BorderSizePixel = 0
	panel.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = panel

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(55, 55, 65)
	stroke.Thickness = 1
	stroke.Transparency = 0.4
	stroke.Parent = panel

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = panel

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.LayoutOrder = 0
	title.Size = UDim2.new(0, 180, 0, 18)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamMedium
	title.Text = "Choose hero"
	title.TextColor3 = Color3.fromRGB(210, 210, 220)
	title.TextSize = 13
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = panel

	for index, entry in roster do
		local btn = Instance.new("TextButton")
		btn.Name = entry.id
		btn.LayoutOrder = index
		btn.Size = UDim2.new(0, 180, 0, 34)
		btn.BackgroundColor3 = Color3.fromRGB(32, 32, 40)
		btn.AutoButtonColor = true
		btn.Font = Enum.Font.Gotham
		btn.Text = entry.displayName
		btn.TextColor3 = Color3.fromRGB(235, 235, 240)
		btn.TextSize = 14
		btn.Parent = panel

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 6)
		btnCorner.Parent = btn

		btn.MouseButton1Click:Connect(function()
			onSelect(entry.id)
			screenGui.Enabled = false
		end)
	end

	return {
		show = function()
			screenGui.Enabled = true
		end,
		hide = function()
			screenGui.Enabled = false
		end,
		destroy = function()
			screenGui:Destroy()
		end,
	}
end

return CharacterSelectUI
