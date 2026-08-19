--!strict

local Theme = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("HUDTheme"))

export type StatBarHandle = {
	Frame: Frame,
	SetValue: (self: StatBarHandle, current: number, max: number) -> (),
}

local StatBar = {}

function StatBar.create(
	parent: Instance,
	label: string,
	fillColor: Color3,
	fillDark: Color3,
	textColor: Color3
): StatBarHandle
	local displayName = label:sub(1, 1):upper() .. label:sub(2):lower()

	local container = Instance.new("Frame")
	container.Name = label .. "Bar"
	container.BackgroundTransparency = 1
	container.Size = Theme.StatBarSize
	container.Parent = parent

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.BackgroundColor3 = Theme.BarTrack
	track.BorderSizePixel = 0
	track.Size = UDim2.fromScale(1, 1)
	track.ClipsDescendants = true
	track.Parent = container

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = Theme.CornerSmall
	trackCorner.Parent = track

	local trackStroke = Instance.new("UIStroke")
	trackStroke.Color = Theme.BarTrackStroke
	trackStroke.Transparency = 0.2
	trackStroke.Thickness = 1
	trackStroke.Parent = track

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = fillColor
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(1, 1)
	fill.ZIndex = 1
	fill.Parent = track

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = Theme.CornerSmall
	fillCorner.Parent = fill

	local fillGradient = Instance.new("UIGradient")
	fillGradient.Rotation = 90
	fillGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, fillColor),
		ColorSequenceKeypoint.new(0.45, fillColor),
		ColorSequenceKeypoint.new(1, fillDark),
	})
	fillGradient.Parent = fill

	local fillGlow = Instance.new("Frame")
	fillGlow.Name = "FillGlow"
	fillGlow.BackgroundColor3 = Color3.new(1, 1, 1)
	fillGlow.BackgroundTransparency = 0.88
	fillGlow.BorderSizePixel = 0
	fillGlow.Size = UDim2.new(0.96, 0, 0.42, 0)
	fillGlow.Position = UDim2.new(0.02, 0, 0.08, 0)
	fillGlow.ZIndex = 2
	fillGlow.Parent = fill

	local fillGlowCorner = Instance.new("UICorner")
	fillGlowCorner.CornerRadius = Theme.CornerSmall
	fillGlowCorner.Parent = fillGlow

	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "BarText"
	textLabel.BackgroundTransparency = 1
	textLabel.Size = UDim2.fromScale(1, 1)
	textLabel.Font = Theme.FontLabel
	textLabel.TextXAlignment = Enum.TextXAlignment.Center
	textLabel.TextYAlignment = Enum.TextYAlignment.Center
	textLabel.TextColor3 = textColor
	textLabel.TextScaled = true
	textLabel.Text = `{displayName}: 0/0`
	textLabel.ZIndex = 5
	textLabel.Parent = track

	local textStroke = Instance.new("UIStroke")
	textStroke.Color = Color3.fromRGB(6, 8, 12)
	textStroke.Thickness = 1.4
	textStroke.Transparency = 0.2
	textStroke.Parent = textLabel

	local textConstraint = Instance.new("UITextSizeConstraint")
	textConstraint.MaxTextSize = 13
	textConstraint.MinTextSize = 8
	textConstraint.Parent = textLabel

	local handle: StatBarHandle = {
		Frame = container,
		SetValue = function(_self, current: number, max: number)
			local ratio = if max > 0 then math.clamp(current / max, 0, 1) else 0
			fill.Size = UDim2.fromScale(ratio, 1)
			local currentInt = math.floor(current + 0.5)
			local maxInt = math.floor(max + 0.5)
			textLabel.Text = `{displayName}: {currentInt}/{maxInt}`
		end,
	}

	return handle
end

return StatBar
