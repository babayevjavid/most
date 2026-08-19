--!strict

local Theme = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("HUDTheme"))

export type CurrencyRowHandle = {
	Frame: Frame,
	SetAmount: (self: CurrencyRowHandle, amount: number) -> (),
}

local CurrencyRow = {}

function CurrencyRow.create(parent: Instance, _label: string, accent: Color3): CurrencyRowHandle
	local row = Instance.new("Frame")
	row.Name = _label .. "Currency"
	row.BackgroundColor3 = Theme.PanelBg
	row.BackgroundTransparency = Theme.PanelBgTransparency
	row.BorderSizePixel = 0
	row.Size = UDim2.new(1, 0, 0.48, 0)
	row.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.CornerSmall
	corner.Parent = row

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Stroke
	stroke.Transparency = Theme.StrokeTransparency
	stroke.Thickness = 1
	stroke.Parent = row

	local icon = Instance.new("Frame")
	icon.Name = "Icon"
	icon.BackgroundColor3 = accent
	icon.BorderSizePixel = 0
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0.04, 0, 0.5, 0)
	icon.Size = UDim2.new(0.08, 0, 0.55, 0)
	icon.Parent = row

	local iconCorner = Instance.new("UICorner")
	iconCorner.CornerRadius = UDim.new(1, 0)
	iconCorner.Parent = icon

	local iconAspect = Instance.new("UIAspectRatioConstraint")
	iconAspect.AspectRatio = 1
	iconAspect.Parent = icon

	local amountLabel = Instance.new("TextLabel")
	amountLabel.Name = "Amount"
	amountLabel.BackgroundTransparency = 1
	amountLabel.Position = UDim2.new(0.16, 0, 0, 0)
	amountLabel.Size = UDim2.new(0.8, 0, 1, 0)
	amountLabel.Font = Theme.FontBody
	amountLabel.TextScaled = true
	amountLabel.TextXAlignment = Enum.TextXAlignment.Left
	amountLabel.TextColor3 = Theme.TextPrimary
	amountLabel.Text = "0"
	amountLabel.Parent = row

	local textConstraint = Instance.new("UITextSizeConstraint")
	textConstraint.MaxTextSize = 14
	textConstraint.MinTextSize = 10
	textConstraint.Parent = amountLabel

	local handle: CurrencyRowHandle = {
		Frame = row,
		SetAmount = function(_self, amount: number)
			amountLabel.Text = tostring(math.floor(amount))
		end,
	}

	return handle
end

return CurrencyRow
