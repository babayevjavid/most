--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HeroRegistry = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("HeroRegistry"))
local Theme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("HUDTheme"))

export type CharacterSelectController = {
	Gui: ScreenGui,
	Show: (self: CharacterSelectController) -> (),
	Hide: (self: CharacterSelectController) -> (),
}

local CharacterSelectUI = {}

function CharacterSelectUI.create(onSelect: (heroId: string) -> ()): CharacterSelectController
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "CharacterSelect"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui

	local container = Instance.new("Frame")
	container.Name = "ButtonContainer"
	container.AnchorPoint = Vector2.new(1, 1)
	container.BackgroundTransparency = 1
	container.Position = UDim2.fromScale(0.985, 0.985)
	container.Size = UDim2.fromScale(0.09, 0.2)
	container.Parent = screenGui

	local containerSize = Instance.new("UISizeConstraint")
	containerSize.MinSize = Vector2.new(0, 0)
	containerSize.Parent = container

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.Padding = UDim.new(0.04, 0)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = container

	local buttons: { [string]: TextButton } = {}

	for index, heroId in HeroRegistry.getHeroIds() do
		local heroDef = HeroRegistry[heroId]
		local accent = Theme.HeroAccents[heroId] or Theme.Stroke

		local button = Instance.new("TextButton")
		button.Name = heroId
		button.AutoButtonColor = false
		button.BackgroundColor3 = Theme.PanelBg
		button.BackgroundTransparency = 0.08
		button.BorderSizePixel = 0
		button.Size = UDim2.fromScale(1, 0.22)
		button.Font = Theme.FontBody
		button.TextScaled = true
		button.TextColor3 = Theme.TextPrimary
		button.Text = heroDef.DisplayName
		button.LayoutOrder = index
		button.Parent = container

		local buttonSize = Instance.new("UISizeConstraint")
		buttonSize.MinSize = Vector2.new(0, 0)
		buttonSize.Parent = button

		local textConstraint = Instance.new("UITextSizeConstraint")
		textConstraint.MaxTextSize = 14
		textConstraint.MinTextSize = 10
		textConstraint.Parent = button

		local corner = Instance.new("UICorner")
		corner.CornerRadius = Theme.CornerSmall
		corner.Parent = button

		local stroke = Instance.new("UIStroke")
		stroke.Color = Theme.Stroke
		stroke.Thickness = 1
		stroke.Transparency = 0.35
		stroke.Parent = button

		button.MouseEnter:Connect(function()
			stroke.Color = accent
			stroke.Transparency = 0.1
		end)
		button.MouseLeave:Connect(function()
			stroke.Color = Theme.Stroke
			stroke.Transparency = 0.35
		end)
		button.MouseButton1Click:Connect(function()
			onSelect(heroId)
		end)

		buttons[heroId] = button
	end

	local controller: CharacterSelectController = {
		Gui = screenGui,
		Show = function(_self)
			screenGui.Enabled = true
			for _, button in buttons do
				button.Visible = true
			end
		end,
		Hide = function(_self)
			screenGui.Enabled = false
		end,
	}

	return controller
end

return CharacterSelectUI
