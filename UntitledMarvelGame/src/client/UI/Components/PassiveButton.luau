--!strict

local Theme = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("HUDTheme"))

export type PassiveButtonHandle = {
	Frame: Frame,
	SetAccent: (self: PassiveButtonHandle, color: Color3) -> (),
}

local PassiveButton = {}

function PassiveButton.create(parent: Instance, passiveId: string, displayName: string): PassiveButtonHandle
	local button = Instance.new("Frame")
	button.Name = passiveId
	button.BackgroundColor3 = Theme.PanelBg
	button.BackgroundTransparency = 0.1
	button.BorderSizePixel = 0
	button.Size = UDim2.fromScale(1, 1)
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.CornerMedium
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Name = "Stroke"
	stroke.Color = Theme.Stroke
	stroke.Thickness = 1
	stroke.Transparency = 0.45
	stroke.Parent = button

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Theme.FontLabel
	label.TextScaled = true
	label.TextColor3 = Theme.TextMuted
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Text = string.upper(string.sub(displayName, 1, 8))
	label.Parent = button

	local textConstraint = Instance.new("UITextSizeConstraint")
	textConstraint.MaxTextSize = 9
	textConstraint.MinTextSize = 6
	textConstraint.Parent = label

	local handle: PassiveButtonHandle = {
		Frame = button,
		SetAccent = function(self, color: Color3)
			stroke.Color = color
		end,
	}

	return handle
end

return PassiveButton
