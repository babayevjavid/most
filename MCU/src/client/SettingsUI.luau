--!strict
--[[ Settings as a full menu page or embedded panel. ]]

local ClientSettings = require(script.Parent.ClientSettings)
local CameraShakeClient = require(script.Parent.CameraShakeClient)
local ShoulderCamClient = require(script.Parent.ShoulderCamClient)

export type SettingsPage = {
	page: Frame,
	refresh: () -> (),
}

export type SettingsController = {
	root: Frame,
	refresh: () -> (),
	show: () -> (),
	hide: () -> (),
	toggle: () -> (),
}

local SettingsUI = {}

local THEME_ON = Color3.fromRGB(55, 120, 70)
local THEME_OFF = Color3.fromRGB(38, 38, 44)
local PANEL = Color3.fromRGB(14, 44, 52)
local STROKE = Color3.fromRGB(48, 110, 118)

local function addCorner(parent: GuiObject, scale: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(scale, 0)
	c.Parent = parent
end

local function makeOptionButton(parent: Frame, text: string, layoutOrder: number): TextButton
	local btn = Instance.new("TextButton")
	btn.Name = text
	btn.LayoutOrder = layoutOrder
	btn.Size = UDim2.new(0.48, 0, 0.85, 0)
	btn.BackgroundColor3 = THEME_OFF
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = true
	btn.Font = Enum.Font.GothamBold
	btn.Text = text
	btn.TextColor3 = Color3.fromRGB(240, 240, 245)
	btn.TextScaled = true
	btn.Parent = parent
	addCorner(btn, 0.2)
	return btn
end

local function makeSettingRow(parent: Frame, labelText: string, layoutOrder: number, rowHeight: number): (Frame, Frame)
	local row = Instance.new("Frame")
	row.Name = labelText
	row.LayoutOrder = layoutOrder
	row.Size = UDim2.new(1, 0, 0, rowHeight)
	row.BackgroundTransparency = 1
	row.Parent = parent

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0.42, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.Text = labelText
	label.TextColor3 = Color3.fromRGB(210, 228, 232)
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = row

	local btnHold = Instance.new("Frame")
	btnHold.Name = "Buttons"
	btnHold.Size = UDim2.new(0.56, 0, 1, 0)
	btnHold.Position = UDim2.fromScale(0.44, 0)
	btnHold.BackgroundTransparency = 1
	btnHold.Parent = row

	local btnLayout = Instance.new("UIListLayout")
	btnLayout.FillDirection = Enum.FillDirection.Horizontal
	btnLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	btnLayout.Padding = UDim.new(0.04, 0)
	btnLayout.Parent = btnHold

	return row, btnHold
end

local function buildSettingsPanel(root: Frame, opts: { compact: boolean?, showShoulderCam: boolean? }?)
	local compact = opts and opts.compact == true
	local showShoulder = not (opts and opts.showShoulderCam == false)
	local rowHeight = if compact then 26 else 40
	local rowGap = if compact then 4 else 8
	local edgePad = if compact then 8 else 14

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, rowGap)
	layout.Parent = root

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, edgePad)
	pad.PaddingBottom = UDim.new(0, edgePad)
	pad.PaddingLeft = UDim.new(0, edgePad + 2)
	pad.PaddingRight = UDim.new(0, edgePad + 2)
	pad.Parent = root

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.LayoutOrder = 0
	title.Size = UDim2.new(1, 0, 0, if compact then 20 else 32)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.Text = "SETTINGS"
	title.TextColor3 = Color3.fromRGB(236, 248, 250)
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = root

	local order = 1
	local sideRightBtn: TextButton? = nil
	local sideLeftBtn: TextButton? = nil
	local keyCtrlBtn: TextButton? = nil
	local statusLabel: TextLabel? = nil

	if showShoulder then
		local _, sideBtns = makeSettingRow(root, "Shoulder Side", order, rowHeight)
		order += 1
		sideRightBtn = makeOptionButton(sideBtns, "Right", 1)
		sideLeftBtn = makeOptionButton(sideBtns, "Left", 2)

		local _, keyBtns = makeSettingRow(root, "Shoulder Key", order, rowHeight)
		order += 1
		keyCtrlBtn = makeOptionButton(keyBtns, "Ctrl", 1)
		keyCtrlBtn.Size = UDim2.new(1, 0, 0.85, 0)

		statusLabel = Instance.new("TextLabel")
		statusLabel.LayoutOrder = order
		order += 1
		statusLabel.Size = UDim2.new(1, 0, 0, if compact then 20 else 24)
		statusLabel.BackgroundTransparency = 1
		statusLabel.Font = Enum.Font.Gotham
		statusLabel.Text = "Shoulder Cam: Off"
		statusLabel.TextColor3 = Color3.fromRGB(170, 190, 195)
		statusLabel.TextScaled = true
		statusLabel.TextXAlignment = Enum.TextXAlignment.Left
		statusLabel.Parent = root
	end

	local _, shakeBtns = makeSettingRow(root, "Screen Shake", order, rowHeight)
	order += 1
	local shakeOnBtn = makeOptionButton(shakeBtns, "On", 1)
	local shakeOffBtn = makeOptionButton(shakeBtns, "Off", 2)

	local _, vfxBtns = makeSettingRow(root, "Screen VFX", order, rowHeight)
	order += 1
	local vfxOnBtn = makeOptionButton(vfxBtns, "On", 1)
	local vfxOffBtn = makeOptionButton(vfxBtns, "Off", 2)

	local _, zoomBtns = makeSettingRow(root, "Ability Zoom", order, rowHeight)
	order += 1
	local zoomOnBtn = makeOptionButton(zoomBtns, "On", 1)
	local zoomOffBtn = makeOptionButton(zoomBtns, "Off", 2)

	local _, qualityBtns = makeSettingRow(root, "Graphics", order, rowHeight)
	order += 1
	local qualityHighBtn = makeOptionButton(qualityBtns, "High", 1)
	local qualityLowBtn = makeOptionButton(qualityBtns, "Low", 2)

	local function paint(onBtn: TextButton, offBtn: TextButton, on: boolean)
		onBtn.BackgroundColor3 = if on then THEME_ON else THEME_OFF
		offBtn.BackgroundColor3 = if on then THEME_OFF else THEME_ON
	end

	local function refresh()
		paint(shakeOnBtn, shakeOffBtn, ClientSettings.isScreenShakeEnabled())
		paint(vfxOnBtn, vfxOffBtn, ClientSettings.isScreenVfxEnabled())
		paint(zoomOnBtn, zoomOffBtn, ClientSettings.isAbilityZoomEnabled())
		paint(qualityHighBtn, qualityLowBtn, ClientSettings.getGraphicsQuality() == "High")
		if sideRightBtn and sideLeftBtn then
			local s = ShoulderCamClient.getSide()
			sideRightBtn.BackgroundColor3 = if s == "Right" then THEME_ON else THEME_OFF
			sideLeftBtn.BackgroundColor3 = if s == "Left" then THEME_ON else THEME_OFF
		end
		if keyCtrlBtn then
			ShoulderCamClient.setKeybind("Ctrl")
			keyCtrlBtn.BackgroundColor3 = THEME_ON
		end
		if statusLabel then
			statusLabel.Text = if ShoulderCamClient.isEnabled() then "Shoulder Cam: On" else "Shoulder Cam: Off"
		end
	end

	shakeOnBtn.MouseButton1Click:Connect(function()
		CameraShakeClient.setScreenShakeEnabled(true)
		refresh()
	end)
	shakeOffBtn.MouseButton1Click:Connect(function()
		CameraShakeClient.setScreenShakeEnabled(false)
		refresh()
	end)
	vfxOnBtn.MouseButton1Click:Connect(function()
		CameraShakeClient.setScreenVfxEnabled(true)
		refresh()
	end)
	vfxOffBtn.MouseButton1Click:Connect(function()
		CameraShakeClient.setScreenVfxEnabled(false)
		refresh()
	end)
	zoomOnBtn.MouseButton1Click:Connect(function()
		CameraShakeClient.setAbilityZoomEnabled(true)
		refresh()
	end)
	zoomOffBtn.MouseButton1Click:Connect(function()
		CameraShakeClient.setAbilityZoomEnabled(false)
		refresh()
	end)
	qualityHighBtn.MouseButton1Click:Connect(function()
		ClientSettings.setGraphicsQuality("High")
		refresh()
	end)
	qualityLowBtn.MouseButton1Click:Connect(function()
		ClientSettings.setGraphicsQuality("Low")
		refresh()
	end)
	if sideRightBtn and sideLeftBtn then
		sideRightBtn.MouseButton1Click:Connect(function()
			ShoulderCamClient.setSide("Right")
			refresh()
		end)
		sideLeftBtn.MouseButton1Click:Connect(function()
			ShoulderCamClient.setSide("Left")
			refresh()
		end)
	end

	ClientSettings.onChanged(refresh)
	refresh()

	return refresh
end

function SettingsUI.buildPanel(parent: Frame, opts: { compact: boolean?, showShoulderCam: boolean? }?): () -> ()
	return buildSettingsPanel(parent, opts)
end

function SettingsUI.createPage(parent: Instance, opts: { showShoulderCam: boolean? }?): SettingsPage
	local page = Instance.new("Frame")
	page.Name = "SettingsPage"
	page.Size = UDim2.fromScale(1, 1)
	page.BackgroundTransparency = 1
	page.Visible = false
	page.ZIndex = 2
	page.Parent = parent

	local panel = Instance.new("Frame")
	panel.Name = "SettingsPanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.3, 0.44)
	panel.BackgroundColor3 = PANEL
	panel.BorderSizePixel = 0
	panel.ZIndex = 2
	panel.Parent = page
	addCorner(panel, 0.02)

	local stroke = Instance.new("UIStroke")
	stroke.Color = STROKE
	stroke.Thickness = 1
	stroke.Transparency = 0.3
	stroke.Parent = panel

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Scroll"
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = panel

	local refresh = buildSettingsPanel(scroll, { compact = true, showShoulderCam = if opts then opts.showShoulderCam else true })

	return {
		page = page,
		refresh = refresh,
	}
end

function SettingsUI.bindPage(page: Frame, opts: { showShoulderCam: boolean? }?): SettingsPage
	local panel = page:WaitForChild("SettingsPanel") :: Frame
	local scroll = panel:WaitForChild("Scroll") :: ScrollingFrame
	local refresh = buildSettingsPanel(scroll, { compact = true, showShoulderCam = if opts then opts.showShoulderCam else true })
	return {
		page = page,
		refresh = refresh,
	}
end

function SettingsUI.create(parent: Instance, opts: { compact: boolean?, showShoulderCam: boolean? }?): SettingsController
	local root = Instance.new("Frame")
	root.Name = "SettingsPanel"
	root.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
	root.BackgroundTransparency = 0.08
	root.BorderSizePixel = 0
	root.Visible = false
	root.Parent = parent
	addCorner(root, 0.06)

	local refresh = buildSettingsPanel(root, opts)

	return {
		root = root,
		refresh = refresh,
		show = function()
			root.Visible = true
			refresh()
		end,
		hide = function()
			root.Visible = false
		end,
		toggle = function()
			root.Visible = not root.Visible
			if root.Visible then
				refresh()
			end
		end,
	}
end

return SettingsUI
