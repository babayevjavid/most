--!strict
--[[ Top-right settings button and modal for client gameplay options. ]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local ClientSettings = require(script.Parent:WaitForChild("ClientSettings"))
local DayCycleConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DayCycleConstants"))
local DayCycleHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DayCycleHelper"))
local HudConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("HudConstants"))
local UiStyle = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UiStyle"))
export type SettingsController = {
	show: () -> (),
	hide: () -> (),
	destroy: () -> (),
}

local SettingsUI = {}

function SettingsUI.create(playerGui: PlayerGui, dayCycleAdminRemote: RemoteEvent?): SettingsController
	local player = Players.LocalPlayer
	local open = false
	local draggingTimeSlider = false
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "SettingsUI"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = HudConstants.TOP_BAR_DISPLAY_ORDER
	screenGui.Enabled = false
	screenGui.Parent = playerGui

	local settingsBtn = Instance.new("TextButton")
	settingsBtn.Name = "SettingsButton"
	settingsBtn.AnchorPoint = Vector2.new(1, 0)
	settingsBtn.Position = UDim2.new(1, -12, 0, 10)
	settingsBtn.Size = UDim2.fromOffset(88, 30)
	settingsBtn.BackgroundColor3 = HudConstants.SURFACE_PANEL
	settingsBtn.BackgroundTransparency = 1
	settingsBtn.BorderSizePixel = 0
	settingsBtn.AutoButtonColor = false
	settingsBtn.Font = HudConstants.FONT_LABEL
	settingsBtn.Text = "Settings"
	settingsBtn.TextColor3 = HudConstants.COLOR_TEXT
	settingsBtn.TextSize = 13
	settingsBtn.Parent = screenGui
	UiStyle.addCorner(settingsBtn, HudConstants.CORNER_RADIUS_MD)
	UiStyle.addStroke(settingsBtn, HudConstants.COLOR_BORDER, 1, 0)

	settingsBtn.MouseEnter:Connect(function()
		UiStyle.tween(settingsBtn, { BackgroundTransparency = 0.85, BackgroundColor3 = HudConstants.SURFACE_PANEL })
	end)
	settingsBtn.MouseLeave:Connect(function()
		UiStyle.tween(settingsBtn, { BackgroundTransparency = 1 })
	end)

	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = HudConstants.SURFACE_BACKDROP
	backdrop.BackgroundTransparency = 0.45
	backdrop.BorderSizePixel = 0
	backdrop.Visible = false
	backdrop.ZIndex = 10
	backdrop.Active = true
	backdrop.Parent = screenGui

	local panel = UiStyle.createPanel(screenGui, {
		name = "SettingsPanel",
		cornerRadius = HudConstants.CORNER_RADIUS_LG,
		bgTransparency = 0.04,
	})
	panel.Active = true
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(320, 212)	panel.Visible = false
	panel.ZIndex = 11
	UiStyle.addPadding(panel, 16)

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -32, 0, 24)
	title.BackgroundTransparency = 1
	title.Font = HudConstants.FONT_HEADING
	title.Text = "Settings"
	title.TextColor3 = HudConstants.COLOR_TEXT
	title.TextSize = 16
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = panel

	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "Close"
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.Position = UDim2.new(1, 0, 0, 0)
	closeBtn.Size = UDim2.fromOffset(28, 28)
	closeBtn.BackgroundTransparency = 1
	closeBtn.BorderSizePixel = 0
	closeBtn.Font = HudConstants.FONT_LABEL
	closeBtn.Text = "×"
	closeBtn.TextColor3 = HudConstants.COLOR_TEXT_SECONDARY
	closeBtn.TextSize = 18
	closeBtn.AutoButtonColor = false
	closeBtn.Parent = panel

	local row = Instance.new("Frame")
	row.Name = "LockOnRow"
	row.Position = UDim2.fromOffset(0, 40)
	row.Size = UDim2.new(1, 0, 0, 36)
	row.BackgroundColor3 = HudConstants.SURFACE_INSET
	row.BackgroundTransparency = 0.3
	row.BorderSizePixel = 0
	row.Parent = panel
	UiStyle.addCorner(row, HudConstants.CORNER_RADIUS_SM)
	UiStyle.addStroke(row, HudConstants.COLOR_BORDER, 1, 0.35)
	UiStyle.addPadding(row, 10)

	local rowLabel = Instance.new("TextLabel")
	rowLabel.Size = UDim2.new(1, -72, 1, 0)
	rowLabel.BackgroundTransparency = 1
	rowLabel.Font = HudConstants.FONT_LABEL
	rowLabel.Text = "Lock-on cursor"
	rowLabel.TextColor3 = HudConstants.COLOR_TEXT
	rowLabel.TextSize = 13
	rowLabel.TextXAlignment = Enum.TextXAlignment.Left
	rowLabel.Parent = row

	local toggleBtn = Instance.new("TextButton")
	toggleBtn.Name = "LockOnToggle"
	toggleBtn.AnchorPoint = Vector2.new(1, 0.5)
	toggleBtn.Position = UDim2.new(1, 0, 0.5, 0)
	toggleBtn.Size = UDim2.fromOffset(56, 24)
	toggleBtn.BorderSizePixel = 0
	toggleBtn.AutoButtonColor = false
	toggleBtn.Font = HudConstants.FONT_LABEL
	toggleBtn.TextSize = 11
	toggleBtn.Parent = row
	UiStyle.addCorner(toggleBtn, HudConstants.CORNER_RADIUS_SM)

	local function refreshToggle()
		local enabled = ClientSettings.isLockOnEnabled()
		toggleBtn.Text = if enabled then "On" else "Off"
		toggleBtn.BackgroundColor3 = if enabled then HudConstants.COLOR_ACCENT else HudConstants.SURFACE_ELEVATED
		toggleBtn.TextColor3 = if enabled then Color3.fromRGB(14, 18, 16) else HudConstants.COLOR_TEXT_SECONDARY
	end

	refreshToggle()

	toggleBtn.MouseButton1Click:Connect(function()
		ClientSettings.setLockOnEnabled(not ClientSettings.isLockOnEnabled())
		refreshToggle()
	end)

	local effectsRow = Instance.new("Frame")
	effectsRow.Name = "ScreenEffectsRow"
	effectsRow.Position = UDim2.fromOffset(0, 84)
	effectsRow.Size = UDim2.new(1, 0, 0, 36)
	effectsRow.BackgroundColor3 = HudConstants.SURFACE_INSET
	effectsRow.BackgroundTransparency = 0.3
	effectsRow.BorderSizePixel = 0
	effectsRow.Parent = panel
	UiStyle.addCorner(effectsRow, HudConstants.CORNER_RADIUS_SM)
	UiStyle.addStroke(effectsRow, HudConstants.COLOR_BORDER, 1, 0.35)
	UiStyle.addPadding(effectsRow, 10)

	local effectsLabel = Instance.new("TextLabel")
	effectsLabel.Size = UDim2.new(1, -72, 1, 0)
	effectsLabel.BackgroundTransparency = 1
	effectsLabel.Font = HudConstants.FONT_LABEL
	effectsLabel.Text = "Ability screen effects"
	effectsLabel.TextColor3 = HudConstants.COLOR_TEXT
	effectsLabel.TextSize = 13
	effectsLabel.TextXAlignment = Enum.TextXAlignment.Left
	effectsLabel.Parent = effectsRow

	local effectsToggleBtn = Instance.new("TextButton")
	effectsToggleBtn.Name = "ScreenEffectsToggle"
	effectsToggleBtn.AnchorPoint = Vector2.new(1, 0.5)
	effectsToggleBtn.Position = UDim2.new(1, 0, 0.5, 0)
	effectsToggleBtn.Size = UDim2.fromOffset(56, 24)
	effectsToggleBtn.BorderSizePixel = 0
	effectsToggleBtn.AutoButtonColor = false
	effectsToggleBtn.Font = HudConstants.FONT_LABEL
	effectsToggleBtn.TextSize = 11
	effectsToggleBtn.Parent = effectsRow
	UiStyle.addCorner(effectsToggleBtn, HudConstants.CORNER_RADIUS_SM)

	local function refreshEffectsToggle()
		local enabled = ClientSettings.isAbilityScreenEffectsEnabled()
		effectsToggleBtn.Text = if enabled then "On" else "Off"
		effectsToggleBtn.BackgroundColor3 = if enabled then HudConstants.COLOR_ACCENT else HudConstants.SURFACE_ELEVATED
		effectsToggleBtn.TextColor3 = if enabled then Color3.fromRGB(14, 18, 16) else HudConstants.COLOR_TEXT_SECONDARY
	end

	refreshEffectsToggle()

	effectsToggleBtn.MouseButton1Click:Connect(function()
		ClientSettings.setAbilityScreenEffectsEnabled(not ClientSettings.isAbilityScreenEffectsEnabled())
		refreshEffectsToggle()
	end)

	local adminHeader = Instance.new("TextLabel")
	adminHeader.Name = "AdminHeader"
	adminHeader.Position = UDim2.fromOffset(0, 128)
	adminHeader.Size = UDim2.new(1, 0, 0, 18)
	adminHeader.BackgroundTransparency = 1
	adminHeader.Font = HudConstants.FONT_LABEL
	adminHeader.Text = "Admin"
	adminHeader.TextColor3 = HudConstants.COLOR_TEXT_SECONDARY
	adminHeader.TextSize = 11
	adminHeader.TextXAlignment = Enum.TextXAlignment.Left
	adminHeader.Visible = false
	adminHeader.Parent = panel

	local pauseRow = Instance.new("Frame")
	pauseRow.Name = "PauseCycleRow"
	pauseRow.Position = UDim2.fromOffset(0, 150)
	pauseRow.Size = UDim2.new(1, 0, 0, 36)
	pauseRow.BackgroundColor3 = HudConstants.SURFACE_INSET
	pauseRow.BackgroundTransparency = 0.3
	pauseRow.BorderSizePixel = 0
	pauseRow.Visible = false
	pauseRow.Parent = panel
	UiStyle.addCorner(pauseRow, HudConstants.CORNER_RADIUS_SM)
	UiStyle.addStroke(pauseRow, HudConstants.COLOR_BORDER, 1, 0.35)
	UiStyle.addPadding(pauseRow, 10)

	local pauseLabel = Instance.new("TextLabel")
	pauseLabel.Size = UDim2.new(1, -72, 1, 0)
	pauseLabel.BackgroundTransparency = 1
	pauseLabel.Font = HudConstants.FONT_LABEL
	pauseLabel.Text = "Pause day cycle"
	pauseLabel.TextColor3 = HudConstants.COLOR_TEXT
	pauseLabel.TextSize = 13
	pauseLabel.TextXAlignment = Enum.TextXAlignment.Left
	pauseLabel.Parent = pauseRow

	local pauseToggleBtn = Instance.new("TextButton")
	pauseToggleBtn.Name = "PauseCycleToggle"
	pauseToggleBtn.AnchorPoint = Vector2.new(1, 0.5)
	pauseToggleBtn.Position = UDim2.new(1, 0, 0.5, 0)
	pauseToggleBtn.Size = UDim2.fromOffset(56, 24)
	pauseToggleBtn.BorderSizePixel = 0
	pauseToggleBtn.AutoButtonColor = false
	pauseToggleBtn.Font = HudConstants.FONT_LABEL
	pauseToggleBtn.TextSize = 11
	pauseToggleBtn.Parent = pauseRow
	UiStyle.addCorner(pauseToggleBtn, HudConstants.CORNER_RADIUS_SM)

	local timeRow = Instance.new("Frame")
	timeRow.Name = "TimeOfDayRow"
	timeRow.Position = UDim2.fromOffset(0, 194)
	timeRow.Size = UDim2.new(1, 0, 0, 72)
	timeRow.BackgroundColor3 = HudConstants.SURFACE_INSET
	timeRow.BackgroundTransparency = 0.3
	timeRow.BorderSizePixel = 0
	timeRow.Visible = false
	timeRow.Parent = panel
	UiStyle.addCorner(timeRow, HudConstants.CORNER_RADIUS_SM)
	UiStyle.addStroke(timeRow, HudConstants.COLOR_BORDER, 1, 0.35)
	UiStyle.addPadding(timeRow, 10)

	local timeTitle = Instance.new("TextLabel")
	timeTitle.Size = UDim2.new(1, 0, 0, 16)
	timeTitle.BackgroundTransparency = 1
	timeTitle.Font = HudConstants.FONT_LABEL
	timeTitle.Text = "Time of day"
	timeTitle.TextColor3 = HudConstants.COLOR_TEXT
	timeTitle.TextSize = 13
	timeTitle.TextXAlignment = Enum.TextXAlignment.Left
	timeTitle.Parent = timeRow

	local timeValue = Instance.new("TextLabel")
	timeValue.Name = "TimeValue"
	timeValue.Position = UDim2.fromOffset(0, 18)
	timeValue.Size = UDim2.new(1, 0, 0, 14)
	timeValue.BackgroundTransparency = 1
	timeValue.Font = HudConstants.FONT_BODY
	timeValue.Text = "8:00 AM"
	timeValue.TextColor3 = HudConstants.COLOR_TEXT_SECONDARY
	timeValue.TextSize = 11
	timeValue.TextXAlignment = Enum.TextXAlignment.Left
	timeValue.Parent = timeRow

	local sliderTrack = Instance.new("TextButton")
	sliderTrack.Name = "TimeSliderTrack"
	sliderTrack.Position = UDim2.fromOffset(0, 38)
	sliderTrack.Size = UDim2.new(1, 0, 0, 10)
	sliderTrack.BackgroundColor3 = HudConstants.SURFACE_ELEVATED
	sliderTrack.BorderSizePixel = 0
	sliderTrack.AutoButtonColor = false
	sliderTrack.Text = ""
	sliderTrack.Parent = timeRow
	UiStyle.addCorner(sliderTrack, 5)

	local sliderFill = Instance.new("Frame")
	sliderFill.Name = "Fill"
	sliderFill.Size = UDim2.fromScale(0.33, 1)
	sliderFill.BackgroundColor3 = HudConstants.COLOR_ACCENT
	sliderFill.BorderSizePixel = 0
	sliderFill.Parent = sliderTrack
	UiStyle.addCorner(sliderFill, 5)

	local function getWorkspaceClock(): number
		local clock = Workspace:GetAttribute(DayCycleConstants.WORKSPACE_CLOCK_ATTR)
		return if typeof(clock) == "number" then clock else DayCycleConstants.START_CLOCK_TIME
	end

	local function refreshPauseToggle()
		local paused = Workspace:GetAttribute(DayCycleConstants.WORKSPACE_PAUSED_ATTR) == true
		pauseToggleBtn.Text = if paused then "On" else "Off"
		pauseToggleBtn.BackgroundColor3 = if paused then HudConstants.COLOR_ACCENT else HudConstants.SURFACE_ELEVATED
		pauseToggleBtn.TextColor3 = if paused then Color3.fromRGB(14, 18, 16) else HudConstants.COLOR_TEXT_SECONDARY
	end

	local function refreshTimeSlider()
		local hour = getWorkspaceClock()
		local alpha = hour / 24
		sliderFill.Size = UDim2.fromScale(math.clamp(alpha, 0, 1), 1)
		timeValue.Text = DayCycleHelper.formatClock12(hour)
	end

	local function applyTimeFromTrack(inputX: number)
		local x0 = sliderTrack.AbsolutePosition.X
		local width = sliderTrack.AbsoluteSize.X
		if width <= 0 then
			return
		end
		local alpha = math.clamp((inputX - x0) / width, 0, 1)
		local hour = alpha * 24
		sliderFill.Size = UDim2.fromScale(alpha, 1)
		timeValue.Text = DayCycleHelper.formatClock12(hour)
		if dayCycleAdminRemote then
			dayCycleAdminRemote:FireServer("SetTime", hour)
		end
	end

	local function refreshAdminVisibility()
		local isAdmin = player:GetAttribute("IsAdmin") == true and dayCycleAdminRemote ~= nil
		adminHeader.Visible = isAdmin
		pauseRow.Visible = isAdmin
		timeRow.Visible = isAdmin
		panel.Size = UDim2.fromOffset(320, if isAdmin then 286 else 212)
		if isAdmin then
			refreshPauseToggle()
			refreshTimeSlider()
		end
	end

	pauseToggleBtn.MouseButton1Click:Connect(function()
		if dayCycleAdminRemote then
			local paused = Workspace:GetAttribute(DayCycleConstants.WORKSPACE_PAUSED_ATTR) == true
			dayCycleAdminRemote:FireServer("SetPaused", not paused)
		end
	end)

	sliderTrack.MouseButton1Down:Connect(function()
		draggingTimeSlider = true
		local pos = UserInputService:GetMouseLocation()
		applyTimeFromTrack(pos.X)
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			draggingTimeSlider = false
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if not draggingTimeSlider then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			applyTimeFromTrack(input.Position.X)
		end
	end)

	player:GetAttributeChangedSignal("IsAdmin"):Connect(refreshAdminVisibility)
	Workspace:GetAttributeChangedSignal(DayCycleConstants.WORKSPACE_CLOCK_ATTR):Connect(function()
		if adminHeader.Visible then
			refreshTimeSlider()
		end
	end)
	Workspace:GetAttributeChangedSignal(DayCycleConstants.WORKSPACE_PAUSED_ATTR):Connect(function()
		if adminHeader.Visible then
			refreshPauseToggle()
		end
	end)

	local function setOpen(visible: boolean)		open = visible
		backdrop.Visible = visible
		panel.Visible = visible
	end

	settingsBtn.MouseButton1Click:Connect(function()
		if open then
			setOpen(false)
		else
			setOpen(true)
			refreshToggle()
			refreshEffectsToggle()
			refreshAdminVisibility()
		end
	end)
	closeBtn.MouseButton1Click:Connect(function()
		setOpen(false)
	end)

	local function show()
		screenGui.Enabled = true
		refreshAdminVisibility()
	end
	local function hide()
		setOpen(false)
		screenGui.Enabled = false
	end

	local function destroy()
		screenGui:Destroy()
	end

	return {
		show = show,
		hide = hide,
		destroy = destroy,
	}
end

return SettingsUI
