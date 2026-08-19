--!strict

local Theme = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("HUDTheme"))

export type AbilityButtonHandle = {
	Frame: Frame,
	AbilityId: string,
	SetCooldown: (self: AbilityButtonHandle, remaining: number, total: number) -> (),
	SetReady: (self: AbilityButtonHandle) -> (),
	SetAccent: (self: AbilityButtonHandle, color: Color3) -> (),
}

local AbilityButton = {}

function AbilityButton.create(parent: Instance, abilityId: string, displayName: string, keybind: string): AbilityButtonHandle
	local button = Instance.new("ImageButton")
	button.Name = abilityId
	button.AutoButtonColor = false
	button.Active = false
	button.Selectable = false
	button.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
	button.BackgroundTransparency = 0.08
	button.BorderSizePixel = 0
	button.Size = UDim2.new(Theme.AbilityButtonWidthScale, 0, Theme.AbilityButtonHeightScale, 0)
	button.ClipsDescendants = true
	button.Parent = parent

	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.DominantAxis = Enum.DominantAxis.Height
	aspect.Parent = button

	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.CornerAbility
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Name = "Stroke"
	stroke.Color = Color3.fromRGB(52, 58, 68)
	stroke.Thickness = 1
	stroke.Transparency = 0.15
	stroke.Parent = button

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.BackgroundTransparency = 1
	nameLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	nameLabel.Position = UDim2.fromScale(0.5, 0.52)
	nameLabel.Size = UDim2.new(0.88, 0, 0.72, 0)
	nameLabel.Font = Theme.FontLabel
	nameLabel.TextColor3 = Theme.TextPrimary
	nameLabel.Text = displayName
	nameLabel.TextWrapped = true
	nameLabel.TextScaled = true
	nameLabel.TextXAlignment = Enum.TextXAlignment.Center
	nameLabel.TextYAlignment = Enum.TextYAlignment.Center
	nameLabel.ZIndex = 1
	nameLabel.Parent = button

	local nameConstraint = Instance.new("UITextSizeConstraint")
	nameConstraint.MaxTextSize = 13
	nameConstraint.MinTextSize = 8
	nameConstraint.Parent = nameLabel

	if keybind ~= "" and keybind ~= "LMB" then
		local keyLabel = Instance.new("TextLabel")
		keyLabel.Name = "Keybind"
		keyLabel.BackgroundColor3 = Color3.fromRGB(8, 10, 14)
		keyLabel.BackgroundTransparency = 0.2
		keyLabel.AnchorPoint = Vector2.new(1, 0)
		keyLabel.Position = UDim2.new(0.96, 0, 0.06, 0)
		keyLabel.Size = UDim2.new(0.34, 0, 0.22, 0)
		keyLabel.Font = Theme.FontLabel
		keyLabel.TextScaled = true
		keyLabel.TextColor3 = Theme.TextMuted
		keyLabel.Text = keybind
		keyLabel.ZIndex = 2
		keyLabel.Parent = button

		local keyConstraint = Instance.new("UITextSizeConstraint")
		keyConstraint.MaxTextSize = 10
		keyConstraint.MinTextSize = 7
		keyConstraint.Parent = keyLabel

		local keyCorner = Instance.new("UICorner")
		keyCorner.CornerRadius = Theme.CornerSmall
		keyCorner.Parent = keyLabel
	end

	local overlay = Instance.new("Frame")
	overlay.Name = "CooldownOverlay"
	overlay.BackgroundTransparency = 1
	overlay.ClipsDescendants = true
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.Visible = false
	overlay.ZIndex = 4
	overlay.Parent = button

	local overlayCorner = Instance.new("UICorner")
	overlayCorner.CornerRadius = Theme.CornerAbility
	overlayCorner.Parent = overlay

	local fill = Instance.new("Frame")
	fill.Name = "CooldownFill"
	fill.BackgroundColor3 = Theme.CooldownOverlay
	fill.BackgroundTransparency = Theme.CooldownOverlayTransparency
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(1, 0)
	fill.ZIndex = 1
	fill.Parent = overlay

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.12),
		NumberSequenceKeypoint.new(1, 0.8),
	})
	gradient.Parent = fill

	local handle: AbilityButtonHandle = {
		Frame = button,
		AbilityId = abilityId,
		SetCooldown = function(self, remaining: number, total: number)
			if total <= 0 or remaining <= 0 then
				self:SetReady()
				return
			end
			local ratio = math.clamp(remaining / total, 0, 1)
			overlay.Visible = true
			fill.Size = UDim2.fromScale(1, ratio)
		end,
		SetReady = function(self)
			overlay.Visible = false
			fill.Size = UDim2.fromScale(1, 0)
		end,
		SetAccent = function(self, color: Color3)
			stroke.Color = color
			stroke.Transparency = 0.05
		end,
	}

	return handle
end

return AbilityButton
