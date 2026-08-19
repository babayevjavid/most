--!strict

local SettingsUI = require(script.Parent.SettingsUI)

export type HudTheme = {
	panel: Color3,
	panelTitle: Color3,
	stroke: Color3,
	modeOn: Color3,
	modeOff: Color3,
}

export type HudSettingsBundle = {
	settingsBtn: TextButton,
	settingsPanel: Frame,
	settingsStroke: UIStroke,
	settingsBtnStroke: UIStroke,
	refreshShoulderSettingsUi: () -> (),
}

local GameplayHUDSettings = {}

local function addCorner(inst: GuiObject, radiusScale: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(radiusScale, 0)
	c.Parent = inst
end

function GameplayHUDSettings.build(root: Frame, theme: HudTheme): HudSettingsBundle
	local settingsBtn = Instance.new("TextButton")
	settingsBtn.Name = "SettingsButton"
	settingsBtn.AnchorPoint = Vector2.new(1, 0)
	settingsBtn.Position = UDim2.fromScale(0.99, 0.038)
	settingsBtn.Size = UDim2.fromScale(0.062, 0.032)
	if game:GetService("UserInputService").TouchEnabled then
		settingsBtn.Size = UDim2.fromScale(0.068, 0.035)
	end
	settingsBtn.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
	settingsBtn.BackgroundTransparency = 0.15
	settingsBtn.BorderSizePixel = 0
	settingsBtn.AutoButtonColor = true
	settingsBtn.Font = Enum.Font.Bangers
	settingsBtn.Text = "Settings"
	settingsBtn.TextColor3 = Color3.fromRGB(235, 235, 240)
	settingsBtn.TextScaled = true
	settingsBtn.ZIndex = 30
	settingsBtn.Parent = root
	addCorner(settingsBtn, 0.2)

	local settingsBtnConstraint = Instance.new("UITextSizeConstraint")
	settingsBtnConstraint.MaxTextSize = 16
	settingsBtnConstraint.MinTextSize = 9
	settingsBtnConstraint.Parent = settingsBtn

	local settingsBtnStroke = Instance.new("UIStroke")
	settingsBtnStroke.Name = "ThemeStroke"
	settingsBtnStroke.Color = theme.stroke
	settingsBtnStroke.Thickness = 1
	settingsBtnStroke.Transparency = 0.35
	settingsBtnStroke.Parent = settingsBtn

	local settingsPanel = Instance.new("Frame")
	settingsPanel.Name = "SettingsPanel"
	settingsPanel.AnchorPoint = Vector2.new(1, 0)
	settingsPanel.Position = UDim2.fromScale(0.99, 0.078)
	settingsPanel.Size = UDim2.fromScale(0.14, 0.34)
	settingsPanel.BackgroundColor3 = theme.panel
	settingsPanel.BackgroundTransparency = 0.08
	settingsPanel.BorderSizePixel = 0
	settingsPanel.Visible = false
	settingsPanel.ZIndex = 31
	settingsPanel.Parent = root
	addCorner(settingsPanel, 0.08)

	local settingsStroke = Instance.new("UIStroke")
	settingsStroke.Name = "ThemeStroke"
	settingsStroke.Color = theme.stroke
	settingsStroke.Thickness = 1.2
	settingsStroke.Transparency = 0.3
	settingsStroke.Parent = settingsPanel

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Scroll"
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ZIndex = 32
	scroll.Parent = settingsPanel

	local refreshShoulderSettingsUi = SettingsUI.buildPanel(scroll, { compact = true, showShoulderCam = true })

	settingsBtn.MouseButton1Click:Connect(function()
		settingsPanel.Visible = not settingsPanel.Visible
		if settingsPanel.Visible then
			refreshShoulderSettingsUi()
		end
	end)

	return {
		settingsBtn = settingsBtn,
		settingsPanel = settingsPanel,
		settingsStroke = settingsStroke,
		settingsBtnStroke = settingsBtnStroke,
		refreshShoulderSettingsUi = refreshShoulderSettingsUi,
	}
end

return GameplayHUDSettings
