-- Client ability HUD. E slot shows Electrokinesis beam cooldown (fills bottom→top while on CD).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Powers = require(script.Parent.Powers)
local LightningEConfig = require(script.Parent.LightningEConfig)

local player = Players.LocalPlayer

-- Lightning = blue, Hydrokinesis = light blue, Chlorokinesis = green
local ACCENT: { [string]: Color3 } = {
	Electrokinesis = Color3.fromRGB(70, 140, 255),
	Hydrokinesis = Color3.fromRGB(150, 220, 255),
	Chlorokinesis = Color3.fromRGB(80, 210, 110),
}

local KEYS = { "Q", "E", "R", "F" }
local E_COOLDOWN_ATTR = "ElectrokinesisECdUntil"

local DEFAULT_TITLES = { "Ability 1", "Ability 2", "Ability 3", "Ability 4" }
local TITLES_BY_POWER: { [string]: { string } } = {
	Electrokinesis = { "Ability 1", "Beam", "Ability 3", "Ability 4" },
}

local function createAbilityHud(strokes: { UIStroke }, keyLabels: { TextLabel }, titles: { TextLabel }): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "AbilityHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Global
	gui.DisplayOrder = 1000
	gui.Enabled = false

	local strip = Instance.new("Frame")
	strip.Name = "Strip"
	strip.BackgroundTransparency = 1
	strip.BorderSizePixel = 0
	strip.AnchorPoint = Vector2.new(0.5, 1)
	strip.Position = UDim2.fromScale(0.5, 0.96)
	strip.Size = UDim2.fromScale(0.58, 0.14)
	strip.ZIndex = 10
	strip.Parent = gui

	local row = Instance.new("Frame")
	row.Name = "ButtonRow"
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0
	row.Size = UDim2.fromScale(1, 1)
	row.Position = UDim2.fromScale(0, 0)
	row.ZIndex = 10
	row.Parent = strip

	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Horizontal
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	listLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	listLayout.Padding = UDim.new(0.007, 0)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = row

	for i = 1, #KEYS do
		local key = KEYS[i]
		local cell = Instance.new("Frame")
		cell.Name = "Slot" .. key
		cell.BackgroundColor3 = Color3.fromRGB(28, 30, 36)
		cell.BackgroundTransparency = 0.08
		cell.BorderSizePixel = 0
		cell.LayoutOrder = i
		cell.Size = UDim2.fromScale(0.225, 0.9)
		cell.ZIndex = 11

		local asp = Instance.new("UIAspectRatioConstraint")
		asp.AspectRatio = 1
		asp.DominantAxis = Enum.DominantAxis.Height
		asp.Parent = cell

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.12, 0)
		corner.Parent = cell

		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Transparency = 0.12
		stroke.Parent = cell
		table.insert(strokes, stroke)

		local keyBadge = Instance.new("TextLabel")
		keyBadge.Name = "Key"
		keyBadge.BackgroundTransparency = 1
		keyBadge.Font = Enum.Font.GothamBold
		keyBadge.TextScaled = true
		keyBadge.Text = "[" .. key .. "]"
		keyBadge.Size = UDim2.fromScale(0.45, 0.34)
		keyBadge.Position = UDim2.fromScale(0.55, 0.08)
		keyBadge.ZIndex = 12
		keyBadge.Parent = cell
		table.insert(keyLabels, keyBadge)

		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.GothamMedium
		title.TextScaled = true
		title.Text = DEFAULT_TITLES[i]
		title.Size = UDim2.fromScale(0.92, 0.42)
		title.Position = UDim2.fromScale(0.5, 0.62)
		title.AnchorPoint = Vector2.new(0.5, 0.5)
		title.ZIndex = 12
		title.Parent = cell
		table.insert(titles, title)

		local tpad = Instance.new("UIPadding")
		tpad.PaddingLeft = UDim.new(0.02, 0)
		tpad.PaddingRight = UDim.new(0.02, 0)
		tpad.PaddingTop = UDim.new(0.02, 0)
		tpad.PaddingBottom = UDim.new(0.02, 0)
		tpad.Parent = title

		if key == "E" then
			local cdClip = Instance.new("Frame")
			cdClip.Name = "CooldownClip"
			cdClip.BackgroundTransparency = 1
			cdClip.BorderSizePixel = 0
			cdClip.Size = UDim2.fromScale(1, 1)
			cdClip.Position = UDim2.fromScale(0, 0)
			cdClip.ZIndex = 13
			cdClip.ClipsDescendants = true

			local cdCorner = Instance.new("UICorner")
			cdCorner.CornerRadius = corner.CornerRadius
			cdCorner.Parent = cdClip

			local cdShade = Instance.new("Frame")
			cdShade.Name = "CooldownShade"
			cdShade.BackgroundColor3 = Color3.fromRGB(12, 14, 22)
			cdShade.BackgroundTransparency = 0.35
			cdShade.BorderSizePixel = 0
			cdShade.AnchorPoint = Vector2.new(0.5, 1)
			cdShade.Position = UDim2.fromScale(0.5, 1)
			cdShade.Size = UDim2.fromScale(1, 0)
			cdShade.ZIndex = 14

			local shadeCorner = Instance.new("UICorner")
			shadeCorner.CornerRadius = corner.CornerRadius
			shadeCorner.Parent = cdShade

			cdShade.Parent = cdClip
			cdClip.Parent = cell
		end

		cell.Parent = row
	end

	return gui
end

local function applyAccent(
	strokes: { UIStroke },
	keyLabels: { TextLabel },
	titles: { TextLabel },
	powerId: string
)
	local c = ACCENT[powerId]
	if not c then
		c = Color3.fromRGB(200, 200, 210)
	end
	local soft = Color3.new(
		math.clamp(c.R * 1.08, 0, 1),
		math.clamp(c.G * 1.08, 0, 1),
		math.clamp(c.B * 1.08, 0, 1)
	)
	for _, s in strokes do
		s.Color = c
	end
	for _, k in keyLabels do
		k.TextColor3 = soft
	end
	local row = TITLES_BY_POWER[powerId]
	for i = 1, #titles do
		local t = titles[i]
		if row and row[i] then
			t.Text = row[i]
		else
			t.Text = DEFAULT_TITLES[i]
		end
	end
end

local function updateElectrokinesisCooldownOverlay(cdShade: Frame)
	local power = player:GetAttribute("SelectedPower")
	if power ~= "Electrokinesis" then
		cdShade.Size = UDim2.fromScale(1, 0)
		return
	end
	local untilT = player:GetAttribute(E_COOLDOWN_ATTR)
	if typeof(untilT) ~= "number" then
		cdShade.Size = UDim2.fromScale(1, 0)
		return
	end
	local now = workspace:GetServerTimeNow()
	if now >= untilT then
		cdShade.Size = UDim2.fromScale(1, 0)
		return
	end
	local remaining = untilT - now
	local frac = math.clamp(remaining / LightningEConfig.AbilityCooldown, 0, 1)
	cdShade.Size = UDim2.new(1, 0, frac, 0)
end

local M = {}

function M.start()
	local playerGui = player:WaitForChild("PlayerGui")

	local strokes: { UIStroke } = {}
	local keyLabels: { TextLabel } = {}
	local titles: { TextLabel } = {}
	local hud = createAbilityHud(strokes, keyLabels, titles)
	hud.Parent = playerGui

	local strip = hud:WaitForChild("Strip") :: Frame
	local slotE = strip:WaitForChild("ButtonRow"):WaitForChild("SlotE") :: Frame
	local cdShade = slotE:WaitForChild("CooldownClip"):WaitForChild("CooldownShade") :: Frame

	RunService.RenderStepped:Connect(function()
		if not hud.Enabled then
			return
		end
		updateElectrokinesisCooldownOverlay(cdShade)
	end)
	player:GetAttributeChangedSignal(E_COOLDOWN_ATTR):Connect(function()
		if hud.Enabled then
			updateElectrokinesisCooldownOverlay(cdShade)
		end
	end)

	local function isPowerPickerOpen(): boolean
		local g = playerGui:FindFirstChild("PowerSelection")
		if g and g:IsA("ScreenGui") then
			return g.Enabled == true
		end
		return false
	end

	local function refresh()
		local picking = isPowerPickerOpen()
		local v = player:GetAttribute("SelectedPower")
		local hasPower = typeof(v) == "string" and Powers.isValid(v)
		local visible = hasPower and not picking
		hud.Enabled = visible
		if visible and typeof(v) == "string" then
			applyAccent(strokes, keyLabels, titles, v)
		end
	end

	local function hookPowerSelection(inst: Instance)
		if inst:IsA("ScreenGui") and inst.Name == "PowerSelection" then
			inst:GetPropertyChangedSignal("Enabled"):Connect(refresh)
			inst.Destroying:Connect(refresh)
			refresh()
		end
	end

	for _, child in playerGui:GetChildren() do
		hookPowerSelection(child)
	end
	playerGui.ChildAdded:Connect(hookPowerSelection)

	player:GetAttributeChangedSignal("SelectedPower"):Connect(function()
		task.defer(refresh)
	end)

	player.CharacterAdded:Connect(function()
		task.defer(refresh)
	end)

	task.defer(refresh)
	task.delay(0.35, refresh)
end

return M
