--!strict
--[[ Top-center clock readout (12-hour AM/PM) synced to the day cycle. ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local DayCycleConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DayCycleConstants"))
local DayCycleHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DayCycleHelper"))
local HudConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("HudConstants"))

local C = DayCycleConstants

export type DayCycleHudController = {
	show: () -> (),
	hide: () -> (),
	destroy: () -> (),
}

local DayCycleHUD = {}

function DayCycleHUD.create(playerGui: PlayerGui): DayCycleHudController
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "DayCycleHUD"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = HudConstants.TOP_BAR_DISPLAY_ORDER + 2
	screenGui.Enabled = false
	screenGui.Parent = playerGui

	local root = Instance.new("Frame")
	root.Name = "ClockRoot"
	root.AnchorPoint = Vector2.new(0.5, 0)
	root.Position = UDim2.new(0.5, 0, 0, 8)
	root.Size = UDim2.fromOffset(160, 42)
	root.BackgroundColor3 = HudConstants.SURFACE_PANEL
	root.BackgroundTransparency = 0.18
	root.BorderSizePixel = 0
	root.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, HudConstants.CORNER_RADIUS_MD)
	corner.Parent = root

	local stroke = Instance.new("UIStroke")
	stroke.Color = HudConstants.COLOR_BORDER
	stroke.Transparency = 0.35
	stroke.Thickness = 1
	stroke.Parent = root

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 0)
	layout.Parent = root

	local timeLabel = Instance.new("TextLabel")
	timeLabel.Name = "Time"
	timeLabel.Size = UDim2.new(1, -16, 0, 22)
	timeLabel.BackgroundTransparency = 1
	timeLabel.Font = HudConstants.FONT_HEADING
	timeLabel.Text = "8:00 AM"
	timeLabel.TextColor3 = HudConstants.COLOR_TEXT
	timeLabel.TextSize = 18
	timeLabel.Parent = root

	local phaseLabel = Instance.new("TextLabel")
	phaseLabel.Name = "Phase"
	phaseLabel.Size = UDim2.new(1, -16, 0, 14)
	phaseLabel.BackgroundTransparency = 1
	phaseLabel.Font = HudConstants.FONT_LABEL
	phaseLabel.Text = "Day"
	phaseLabel.TextColor3 = HudConstants.COLOR_TEXT_SECONDARY
	phaseLabel.TextSize = 11
	phaseLabel.Parent = root

	local attrConns: { RBXScriptConnection } = {}

	local function refresh()
		local clock = Workspace:GetAttribute(C.WORKSPACE_CLOCK_ATTR)
		local phase = Workspace:GetAttribute(C.WORKSPACE_PHASE_ATTR)
		local hour = if typeof(clock) == "number" then clock else C.START_CLOCK_TIME
		timeLabel.Text = DayCycleHelper.formatClock12(hour)
		if phase == "night" or phase == "dawn" or phase == "day" or phase == "dusk" then
			phaseLabel.Text = DayCycleHelper.getPhaseLabel(phase)
		else
			phaseLabel.Text = DayCycleHelper.getPhaseLabel(DayCycleHelper.getPhase(hour))
		end
	end

	local function bindAttributes()
		for _, conn in attrConns do
			conn:Disconnect()
		end
		table.clear(attrConns)
		table.insert(attrConns, Workspace:GetAttributeChangedSignal(C.WORKSPACE_CLOCK_ATTR):Connect(refresh))
		table.insert(attrConns, Workspace:GetAttributeChangedSignal(C.WORKSPACE_PHASE_ATTR):Connect(refresh))
		refresh()
	end

	bindAttributes()

	return {
		show = function()
			screenGui.Enabled = true
			refresh()
		end,
		hide = function()
			screenGui.Enabled = false
		end,
		destroy = function()
			for _, conn in attrConns do
				conn:Disconnect()
			end
			screenGui:Destroy()
		end,
	}
end

return DayCycleHUD
