--!strict
--[[ Shared UI primitives — flat panels, consistent spacing, minimal decoration. ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local HudConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("HudConstants"))

export type PanelOpts = {
	name: string?,
	cornerRadius: number?,
	bgColor: Color3?,
	bgTransparency: number?,
	borderColor: Color3?,
	borderless: boolean?,
}

local UiStyle = {}

function UiStyle.tween(inst: Instance, props: { [string]: any }, duration: number?)
	TweenService:Create(
		inst,
		TweenInfo.new(duration or HudConstants.UI_TWEEN_DURATION, HudConstants.UI_EASING_STYLE, HudConstants.UI_EASING_DIRECTION),
		props
	):Play()
end

function UiStyle.addCorner(parent: Instance, radius: number?): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or HudConstants.CORNER_RADIUS_MD)
	corner.Parent = parent
	return corner
end

function UiStyle.addStroke(parent: Instance, color: Color3?, thickness: number?, transparency: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or HudConstants.COLOR_BORDER
	stroke.Thickness = thickness or 1
	stroke.Transparency = transparency or 0
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

function UiStyle.addPadding(parent: Instance, px: number): UIPadding
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, px)
	pad.PaddingBottom = UDim.new(0, px)
	pad.PaddingLeft = UDim.new(0, px)
	pad.PaddingRight = UDim.new(0, px)
	pad.Parent = parent
	return pad
end

function UiStyle.createPanel(parent: Instance, opts: PanelOpts?): Frame
	local o = opts or {}
	local frame = Instance.new("Frame")
	frame.Name = o.name or "Panel"
	frame.BackgroundColor3 = o.bgColor or HudConstants.SURFACE_PANEL
	frame.BackgroundTransparency = o.bgTransparency or HudConstants.PANEL_BG_TRANSPARENCY
	frame.BorderSizePixel = 0
	frame.Parent = parent
	UiStyle.addCorner(frame, o.cornerRadius or HudConstants.CORNER_RADIUS_MD)
	if not o.borderless then
		UiStyle.addStroke(frame, o.borderColor or HudConstants.COLOR_BORDER, 1, 0)
	end
	return frame
end

-- Back-compat alias
function UiStyle.createGlassPanel(parent: Instance, opts: any?): Frame
	local o = opts or {}
	return UiStyle.createPanel(parent, {
		name = o.name,
		cornerRadius = o.cornerRadius,
		bgTransparency = o.bgTransparency,
		borderColor = o.strokeColor or HudConstants.COLOR_BORDER,
		borderless = o.borderless,
	})
end

function UiStyle.createKeyCap(parent: Instance, keyText: string, accent: Color3?): Frame
	local cap = Instance.new("Frame")
	cap.Name = "KeyCap"
	cap.Size = UDim2.fromOffset(HudConstants.KEY_BADGE_W, HudConstants.KEY_BADGE_H)
	cap.BackgroundColor3 = HudConstants.SURFACE_ELEVATED
	cap.BorderSizePixel = 0
	cap.Parent = parent
	UiStyle.addCorner(cap, HudConstants.CORNER_RADIUS_SM)

	local accentBar = Instance.new("Frame")
	accentBar.Name = "Accent"
	accentBar.Size = UDim2.new(0, 2, 1, -4)
	accentBar.Position = UDim2.fromOffset(0, 2)
	accentBar.BackgroundColor3 = accent or HudConstants.COLOR_ACCENT
	accentBar.BorderSizePixel = 0
	accentBar.Parent = cap
	UiStyle.addCorner(accentBar, 1)

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -6, 1, 0)
	label.Position = UDim2.fromOffset(6, 0)
	label.BackgroundTransparency = 1
	label.Font = HudConstants.FONT_KEY
	label.Text = keyText
	label.TextColor3 = HudConstants.COLOR_TEXT
	label.TextSize = 11
	label.Parent = cap

	return cap
end

function UiStyle.createBar(
	parent: Instance,
	labelText: string,
	fillColor: Color3,
	trackColor: Color3,
	layoutOrder: number
): (Frame, Frame, TextLabel, string)
	local row = Instance.new("Frame")
	row.Name = labelText .. "Row"
	row.LayoutOrder = layoutOrder
	row.Size = UDim2.new(1, 0, 0, HudConstants.HUD_BAR_ROW_HEIGHT)
	row.BackgroundTransparency = 1
	row.Parent = parent

	local barBg = Instance.new("Frame")
	barBg.Name = "BarBg"
	barBg.Size = UDim2.fromScale(1, 1)
	barBg.BackgroundColor3 = trackColor
	barBg.BorderSizePixel = 0
	barBg.ClipsDescendants = true
	barBg.Parent = row
	UiStyle.addCorner(barBg, HudConstants.HUD_BAR_CORNER_RADIUS)

	local barFill = Instance.new("Frame")
	barFill.Name = "BarFill"
	barFill.Size = UDim2.fromScale(1, 1)
	barFill.BackgroundColor3 = fillColor
	barFill.BorderSizePixel = 0
	barFill.Parent = barBg
	UiStyle.addCorner(barFill, HudConstants.HUD_BAR_CORNER_RADIUS)

	local barText = Instance.new("TextLabel")
	barText.Name = "BarText"
	barText.Size = UDim2.fromScale(1, 1)
	barText.BackgroundTransparency = 1
	barText.Font = HudConstants.FONT_LABEL
	barText.Text = string.format("%s: 100 / 100", labelText)
	barText.TextColor3 = HudConstants.COLOR_TEXT
	barText.TextSize = 11
	barText.TextXAlignment = Enum.TextXAlignment.Left
	barText.ZIndex = 2
	barText.Parent = barBg

	local textPad = Instance.new("UIPadding")
	textPad.PaddingLeft = UDim.new(0, 8)
	textPad.Parent = barText

	return row, barFill, barText, labelText
end

function UiStyle.createDivider(parent: Instance, layoutOrder: number): Frame
	local line = Instance.new("Frame")
	line.Name = "Divider"
	line.LayoutOrder = layoutOrder
	line.Size = UDim2.new(1, 0, 0, 1)
	line.BackgroundColor3 = HudConstants.COLOR_BORDER
	line.BackgroundTransparency = 0.35
	line.BorderSizePixel = 0
	line.Parent = parent
	return line
end

function UiStyle.createPrimaryButton(parent: Instance, text: string, accent: Color3): TextButton
	local btn = Instance.new("TextButton")
	btn.Name = "PrimaryButton"
	btn.Size = UDim2.new(1, 0, 0, HudConstants.SELECTION_DEPLOY_BUTTON_H)
	btn.BackgroundColor3 = accent
	btn.BackgroundTransparency = 0
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = false
	btn.Font = HudConstants.FONT_LABEL
	btn.Text = text
	btn.TextColor3 = Color3.fromRGB(14, 18, 16)
	btn.TextSize = 14
	btn.Parent = parent
	UiStyle.addCorner(btn, HudConstants.CORNER_RADIUS_MD)
	return btn
end

return UiStyle
