--!strict
--[[ GameplayHUD: compact stat readout and ability hotbar. ]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AbilityCooldownHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityCooldownHelper"))
local CharacterConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CharacterConfig"))
local HudConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("HudConstants"))
local ResourceConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ResourceConstants"))
local SunspotSolarHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SunspotSolarHelper"))
local PolarisConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PolarisConstants"))
local MetallicTargetingHelper = require(script.Parent:WaitForChild("MetallicTargetingHelper"))
local UiStyle = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UiStyle"))
local ViewportHelper = require(script.Parent:WaitForChild("ViewportHelper"))

export type HudController = {
	screenGui: ScreenGui,
	show: (characterId: string?) -> (),
	hide: () -> (),
	bindCharacter: (character: Model) -> (),
	setEnergy: (current: number, max: number) -> (),
	setHealth: (current: number, max: number) -> (),
	setAbilityPressed: (key: string, pressed: boolean) -> (),
	setAbilityCharge: (key: string, ratio: number) -> (),
	setSiphonCharge: (current: number, max: number) -> (),
	isAbilityOnCooldown: (abilityId: string) -> boolean,
	refreshViewport: () -> (),
	destroy: () -> (),
}

type AbilitySlot = {
	btn: TextButton,
	stroke: UIStroke,
	pressHighlight: Frame,
	cooldownOverlay: Frame,
	chargeOverlay: Frame?,
	cooldownLabel: TextLabel,
	key: string,
	abilityId: string,
	cooldownSeconds: number?,
	baseSize: number,
	defaultStrokeTransparency: number,
	defaultStrokeThickness: number,
	isPressed: boolean,
	accent: Color3,
}

local KEY_TO_ENUM: { [string]: Enum.KeyCode } = {
	F = Enum.KeyCode.F,
	E = Enum.KeyCode.E,
	C = Enum.KeyCode.C,
	T = Enum.KeyCode.T,
	Q = Enum.KeyCode.Q,
	Z = Enum.KeyCode.Z,
}

local function keyCodeToAbilityKey(keyCode: Enum.KeyCode): string?
	for key, enumKey in KEY_TO_ENUM do
		if enumKey == keyCode then
			return key
		end
	end
	return nil
end

local GameplayHUD = {}

function GameplayHUD.create(playerGui: PlayerGui): HudController
	local player = Players.LocalPlayer
	local currentCharacterId: string? = nil
	local healthConn: RBXScriptConnection? = nil
	local energyConn: RBXScriptConnection? = nil
	local maxEnergyConn: RBXScriptConnection? = nil
	local siphonConn: RBXScriptConnection? = nil
	local solarStrengthHeartbeat: RBXScriptConnection? = nil
	local solarStrengthConn: RBXScriptConnection? = nil
	local cooldownConn: RBXScriptConnection? = nil
	local viewportRetryToken = 0
	local inputBeganConn: RBXScriptConnection? = nil
	local inputEndedConn: RBXScriptConnection? = nil
	local boundCharacter: Model? = nil
	local maxEnergy = 100
	local currentEnergy = 100
	local characterAccent = HudConstants.COLOR_ACCENT

	local abilitySlots: { AbilitySlot } = {}
	local keyToSlot: { [string]: AbilitySlot } = {}
	local siphonSegments: { Frame } = {}
	local envSegments: { Frame } = {}
	local displayedSolarStrength = 0
	local targetSolarStrength = 0
	local lastEnvScan = 0

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "GameplayHUD"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = HudConstants.HUD_DISPLAY_ORDER
	screenGui.Enabled = false
	screenGui.Parent = playerGui

	local statPanel = UiStyle.createPanel(screenGui, {
		name = "StatPanel",
		cornerRadius = HudConstants.CORNER_RADIUS_MD,
		bgTransparency = 1,
		borderless = true,
	})
	statPanel.Position = UDim2.fromScale(HudConstants.HUD_TOP_LEFT_X_SCALE, HudConstants.HUD_TOP_CLUSTER_Y_SCALE)
	statPanel.Size = UDim2.fromOffset(
		HudConstants.HUD_VIEWPORT_SIZE + HudConstants.HUD_BARS_OFFSET_X + HudConstants.HUD_BARS_WIDTH + HudConstants.HUD_STAT_PANEL_PADDING * 2,
		math.max(HudConstants.HUD_VIEWPORT_SIZE, HudConstants.HUD_BARS_HEIGHT) + HudConstants.HUD_STAT_PANEL_PADDING * 2
	)
	UiStyle.addPadding(statPanel, HudConstants.HUD_STAT_PANEL_PADDING)

	local topCluster = Instance.new("Frame")
	topCluster.Name = "TopCluster"
	topCluster.Size = UDim2.fromScale(1, 1)
	topCluster.BackgroundTransparency = 1
	topCluster.Parent = statPanel

	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "CharacterViewport"
	viewport.Size = UDim2.fromOffset(HudConstants.HUD_VIEWPORT_SIZE, HudConstants.HUD_VIEWPORT_SIZE)
	viewport.BackgroundColor3 = HudConstants.SURFACE_INSET
	viewport.BackgroundTransparency = 0
	viewport.BorderSizePixel = 0
	viewport.Parent = topCluster
	ViewportHelper.applyCircularMask(viewport)

	local barsBlockHeight = HudConstants.HUD_BAR_ROW_HEIGHT * 2 + 8
	local barsYOffset = math.max(0, (HudConstants.HUD_VIEWPORT_SIZE - barsBlockHeight) * 0.5)

	local barsFrame = Instance.new("Frame")
	barsFrame.Name = "Bars"
	barsFrame.Position = UDim2.fromOffset(
		HudConstants.HUD_VIEWPORT_SIZE + HudConstants.HUD_BARS_OFFSET_X,
		barsYOffset
	)
	barsFrame.Size = UDim2.fromOffset(HudConstants.HUD_BARS_WIDTH, barsBlockHeight)
	barsFrame.BackgroundTransparency = 1
	barsFrame.Parent = topCluster

	local barsLayout = Instance.new("UIListLayout")
	barsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	barsLayout.Padding = UDim.new(0, 8)
	barsLayout.Parent = barsFrame

	local _, healthBar, healthBarText, healthLabelName = UiStyle.createBar(
		barsFrame,
		"Health",
		HudConstants.COLOR_HEALTH,
		HudConstants.COLOR_HEALTH_TRACK,
		1
	)
	local energyRow, energyBar, energyBarText, _ = UiStyle.createBar(
		barsFrame,
		"Energy",
		HudConstants.COLOR_ACCENT,
		HudConstants.COLOR_HEALTH_TRACK,
		2
	)
	local energyBarLabel = "Energy"

	local function updateResourceLabel(characterId: string?)
		local config = if characterId then ResourceConstants.CONFIGS[characterId] else nil
		if config then
			energyRow.Visible = true
			energyBarLabel = config.label
		else
			energyRow.Visible = false
		end
	end

	local function updateBar(barFill: Frame, barText: TextLabel, labelName: string, current: number, max: number, flashColor: Color3?)
		local ratio = if max > 0 then math.clamp(current / max, 0, 1) else 0
		barText.Text = string.format("%s: %d / %d", labelName, math.floor(current + 0.5), math.floor(max + 0.5))
		UiStyle.tween(barFill, { Size = UDim2.fromScale(ratio, 1) }, HudConstants.BAR_TWEEN_DURATION)
		if flashColor then
			local original = barFill.BackgroundColor3
			barFill.BackgroundColor3 = flashColor
			task.delay(HudConstants.BAR_FLASH_DAMAGE_DURATION, function()
				if barFill.Parent then
					UiStyle.tween(barFill, { BackgroundColor3 = original }, HudConstants.BAR_FLASH_DAMAGE_DURATION)
				end
			end)
		end
	end

	local abilityBar = UiStyle.createPanel(screenGui, {
		name = "AbilityBar",
		cornerRadius = HudConstants.CORNER_RADIUS_MD,
		bgTransparency = 1,
		borderless = true,
	})
	abilityBar.AnchorPoint = Vector2.new(0.5, 1)
	abilityBar.Position = UDim2.new(0.5, 0, 1, -HudConstants.ABILITY_BAR_BOTTOM_OFFSET)
	abilityBar.AutomaticSize = Enum.AutomaticSize.XY
	UiStyle.addPadding(abilityBar, 8)

	local abilityRow = Instance.new("Frame")
	abilityRow.Name = "AbilityRow"
	abilityRow.AutomaticSize = Enum.AutomaticSize.XY
	abilityRow.BackgroundTransparency = 1
	abilityRow.Parent = abilityBar

	local abilityLayout = Instance.new("UIListLayout")
	abilityLayout.FillDirection = Enum.FillDirection.Horizontal
	abilityLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	abilityLayout.Padding = UDim.new(0, HudConstants.ABILITY_BUTTON_PADDING)
	abilityLayout.Parent = abilityRow

	local siphonBar = Instance.new("Frame")
	siphonBar.Name = "SiphonChargeBar"
	siphonBar.AnchorPoint = Vector2.new(1, 0.5)
	siphonBar.Position = UDim2.new(1, -HudConstants.HUD_SIPHON_BAR_RIGHT_OFFSET, 0.5, 0)
	siphonBar.Size = UDim2.fromOffset(HudConstants.HUD_SIPHON_BAR_WIDTH, HudConstants.HUD_SIPHON_BAR_HEIGHT)
	siphonBar.BackgroundTransparency = 1
	siphonBar.Visible = false
	siphonBar.Parent = screenGui

	local siphonLabel = Instance.new("TextLabel")
	siphonLabel.Name = "Label"
	siphonLabel.Size = UDim2.new(1, 0, 0, HudConstants.HUD_SIPHON_LABEL_HEIGHT)
	siphonLabel.BackgroundTransparency = 1
	siphonLabel.Font = HudConstants.FONT_LABEL
	siphonLabel.Text = "Charge"
	siphonLabel.TextColor3 = HudConstants.COLOR_TEXT_SECONDARY
	siphonLabel.TextSize = HudConstants.HUD_SIPHON_LABEL_TEXT_SIZE
	siphonLabel.Parent = siphonBar

	local siphonStack = Instance.new("Frame")
	siphonStack.Name = "Stack"
	siphonStack.AnchorPoint = Vector2.new(0.5, 1)
	siphonStack.Position = UDim2.new(0.5, 0, 1, 0)
	siphonStack.Size = UDim2.new(1, 0, 1, -HudConstants.HUD_SIPHON_LABEL_HEIGHT)
	siphonStack.BackgroundTransparency = 1
	siphonStack.Parent = siphonBar

	local siphonLayout = Instance.new("UIListLayout")
	siphonLayout.FillDirection = Enum.FillDirection.Vertical
	siphonLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	siphonLayout.Padding = UDim.new(0, HudConstants.HUD_SIPHON_SEGMENT_GAP)
	siphonLayout.Parent = siphonStack

	for i = 1, 5 do
		local seg = Instance.new("Frame")
		seg.Name = "Segment" .. i
		seg.Size = UDim2.new(1, 0, 0.18, -HudConstants.HUD_SIPHON_SEGMENT_GAP)
		seg.BackgroundColor3 = HudConstants.HUD_SIPHON_TRACK_COLOR
		seg.BorderSizePixel = 0
		seg.LayoutOrder = i
		seg.Parent = siphonStack
		UiStyle.addCorner(seg, HudConstants.HUD_BAR_CORNER_RADIUS)
		table.insert(siphonSegments, seg)
	end

	local envBar = Instance.new("Frame")
	envBar.Name = "EnvironmentalAdvantageBar"
	envBar.AnchorPoint = Vector2.new(1, 0.5)
	envBar.Position = UDim2.new(1, -HudConstants.HUD_ENV_BAR_RIGHT_OFFSET, 0.5, 0)
	envBar.Size = UDim2.fromOffset(HudConstants.HUD_ENV_BAR_WIDTH, HudConstants.HUD_ENV_BAR_HEIGHT)
	envBar.BackgroundTransparency = 1
	envBar.Visible = false
	envBar.Parent = screenGui

	local envLabel = Instance.new("TextLabel")
	envLabel.Name = "Label"
	envLabel.Size = UDim2.new(1, 0, 0, HudConstants.HUD_ENV_LABEL_HEIGHT)
	envLabel.BackgroundTransparency = 1
	envLabel.Font = HudConstants.FONT_LABEL
	envLabel.Text = "Environmental Advantage"
	envLabel.TextWrapped = true
	envLabel.TextXAlignment = Enum.TextXAlignment.Center
	envLabel.TextYAlignment = Enum.TextYAlignment.Center
	envLabel.TextColor3 = HudConstants.COLOR_TEXT_SECONDARY
	envLabel.TextSize = HudConstants.HUD_ENV_LABEL_TEXT_SIZE
	envLabel.Parent = envBar

	local envStack = Instance.new("Frame")
	envStack.Name = "Stack"
	envStack.AnchorPoint = Vector2.new(0.5, 1)
	envStack.Position = UDim2.new(0.5, 0, 1, 0)
	envStack.Size = UDim2.fromOffset(30, HudConstants.HUD_ENV_BAR_HEIGHT - HudConstants.HUD_ENV_LABEL_HEIGHT)
	envStack.BackgroundTransparency = 1
	envStack.Parent = envBar

	local envLayout = Instance.new("UIListLayout")
	envLayout.FillDirection = Enum.FillDirection.Vertical
	envLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	envLayout.Padding = UDim.new(0, HudConstants.HUD_ENV_SEGMENT_GAP)
	envLayout.Parent = envStack

	for i = 1, PolarisConstants.Ferrokinesis.AMBIENT_MAX_ITEMS do
		local seg = Instance.new("Frame")
		seg.Name = "Segment" .. i
		seg.Size = UDim2.new(1, 0, 0.18, -HudConstants.HUD_ENV_SEGMENT_GAP)
		seg.BackgroundColor3 = HudConstants.HUD_ENV_TRACK_COLOR
		seg.BorderSizePixel = 0
		seg.LayoutOrder = i
		seg.Parent = envStack
		UiStyle.addCorner(seg, HudConstants.HUD_BAR_CORNER_RADIUS)
		table.insert(envSegments, seg)
	end

	local solarStrengthBar = Instance.new("Frame")
	solarStrengthBar.Name = "SolarStrengthBar"
	solarStrengthBar.AnchorPoint = Vector2.new(1, 0.5)
	solarStrengthBar.Position = UDim2.new(1, -HudConstants.HUD_SOLAR_BAR_RIGHT_OFFSET, 0.5, 0)
	solarStrengthBar.Size = UDim2.fromOffset(HudConstants.HUD_SOLAR_BAR_WIDTH, HudConstants.HUD_SOLAR_BAR_HEIGHT)
	solarStrengthBar.BackgroundTransparency = 1
	solarStrengthBar.Visible = false
	solarStrengthBar.Parent = screenGui

	local solarLabel = Instance.new("TextLabel")
	solarLabel.Name = "Label"
	solarLabel.Size = UDim2.new(1, 0, 0, HudConstants.HUD_SOLAR_LABEL_HEIGHT)
	solarLabel.BackgroundTransparency = 1
	solarLabel.Font = HudConstants.FONT_LABEL
	solarLabel.Text = "Solar"
	solarLabel.TextColor3 = HudConstants.COLOR_TEXT_SECONDARY
	solarLabel.TextSize = HudConstants.HUD_SOLAR_LABEL_TEXT_SIZE
	solarLabel.Parent = solarStrengthBar

	local solarTrack = Instance.new("Frame")
	solarTrack.Name = "Track"
	solarTrack.AnchorPoint = Vector2.new(0.5, 1)
	solarTrack.Position = UDim2.new(0.5, 0, 1, 0)
	solarTrack.Size = UDim2.new(1, 0, 1, -HudConstants.HUD_SOLAR_LABEL_HEIGHT)
	solarTrack.BackgroundColor3 = HudConstants.HUD_SOLAR_TRACK_COLOR
	solarTrack.BorderSizePixel = 0
	solarTrack.ClipsDescendants = true
	solarTrack.Parent = solarStrengthBar
	UiStyle.addCorner(solarTrack, HudConstants.HUD_BAR_CORNER_RADIUS)

	local solarFill = Instance.new("Frame")
	solarFill.Name = "Fill"
	solarFill.AnchorPoint = Vector2.new(0, 1)
	solarFill.Position = UDim2.fromScale(0, 1)
	solarFill.Size = UDim2.fromScale(1, 0)
	solarFill.BackgroundColor3 = HudConstants.HUD_SOLAR_FILL_COLOR
	solarFill.BorderSizePixel = 0
	solarFill.ZIndex = 2
	solarFill.Parent = solarTrack
	UiStyle.addCorner(solarFill, HudConstants.HUD_BAR_CORNER_RADIUS)

	local solarFillGradient = Instance.new("UIGradient")
	solarFillGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, HudConstants.HUD_SOLAR_FILL_DIM),
		ColorSequenceKeypoint.new(0.5, HudConstants.HUD_SOLAR_FILL_COLOR),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 230, 120)),
	})
	solarFillGradient.Rotation = 90
	solarFillGradient.Parent = solarFill

	local solarPercentLabel = Instance.new("TextLabel")
	solarPercentLabel.Name = "Percent"
	solarPercentLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	solarPercentLabel.Position = UDim2.fromScale(0.5, 0.5)
	solarPercentLabel.Size = UDim2.fromScale(1, 1)
	solarPercentLabel.BackgroundTransparency = 1
	solarPercentLabel.Font = HudConstants.FONT_LABEL
	solarPercentLabel.Text = "0%"
	solarPercentLabel.TextColor3 = HudConstants.COLOR_TEXT
	solarPercentLabel.TextSize = 11
	solarPercentLabel.ZIndex = 3
	solarPercentLabel.Parent = solarTrack

	local tooltip = UiStyle.createPanel(screenGui, {
		name = "AbilityTooltip",
		cornerRadius = HudConstants.CORNER_RADIUS_SM,
		bgTransparency = 0.04,
	})
	tooltip.AnchorPoint = Vector2.new(0.5, 1)
	tooltip.Visible = false
	tooltip.ZIndex = 20
	tooltip.AutomaticSize = Enum.AutomaticSize.Y
	tooltip.Size = UDim2.fromOffset(240, 0)
	UiStyle.addPadding(tooltip, 10)

	local tooltipLayout = Instance.new("UIListLayout")
	tooltipLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tooltipLayout.Padding = UDim.new(0, 4)
	tooltipLayout.Parent = tooltip

	local tooltipTitle = Instance.new("TextLabel")
	tooltipTitle.Name = "Title"
	tooltipTitle.LayoutOrder = 1
	tooltipTitle.Size = UDim2.new(1, 0, 0, 18)
	tooltipTitle.BackgroundTransparency = 1
	tooltipTitle.Font = HudConstants.FONT_LABEL
	tooltipTitle.TextColor3 = HudConstants.COLOR_TEXT
	tooltipTitle.TextSize = 13
	tooltipTitle.TextXAlignment = Enum.TextXAlignment.Left
	tooltipTitle.Parent = tooltip

	local tooltipBody = Instance.new("TextLabel")
	tooltipBody.Name = "Body"
	tooltipBody.LayoutOrder = 2
	tooltipBody.Size = UDim2.new(1, 0, 0, 0)
	tooltipBody.AutomaticSize = Enum.AutomaticSize.Y
	tooltipBody.BackgroundTransparency = 1
	tooltipBody.Font = HudConstants.FONT_BODY
	tooltipBody.TextColor3 = HudConstants.COLOR_TEXT_SECONDARY
	tooltipBody.TextSize = 11
	tooltipBody.TextWrapped = true
	tooltipBody.TextXAlignment = Enum.TextXAlignment.Left
	tooltipBody.Parent = tooltip

	local tooltipMeta = Instance.new("TextLabel")
	tooltipMeta.Name = "Meta"
	tooltipMeta.LayoutOrder = 3
	tooltipMeta.AutomaticSize = Enum.AutomaticSize.Y
	tooltipMeta.Size = UDim2.new(1, 0, 0, 0)
	tooltipMeta.BackgroundTransparency = 1
	tooltipMeta.Font = HudConstants.FONT_BODY
	tooltipMeta.TextColor3 = HudConstants.COLOR_TEXT_TERTIARY
	tooltipMeta.TextSize = 10
	tooltipMeta.TextXAlignment = Enum.TextXAlignment.Left
	tooltipMeta.Visible = false
	tooltipMeta.Parent = tooltip

	local function applyCharacterTheme(entry: any)
		if not entry or not entry.accentColor then
			return
		end
		characterAccent = entry.accentColor
		energyBar.BackgroundColor3 = characterAccent
	end

	local function clearAbilityButtons()
		for _, slot in abilitySlots do
			slot.btn:Destroy()
		end
		table.clear(abilitySlots)
		table.clear(keyToSlot)
	end

	local function applyAbilityPressedVisual(slot: AbilitySlot, pressed: boolean)
		slot.isPressed = pressed
		local size = slot.baseSize
		if pressed then
			UiStyle.tween(slot.btn, {
				Size = UDim2.fromOffset(math.floor(size * HudConstants.ABILITY_BUTTON_PRESSED_SCALE), math.floor(size * HudConstants.ABILITY_BUTTON_PRESSED_SCALE)),
				BackgroundColor3 = HudConstants.SURFACE_ELEVATED,
			}, HudConstants.ABILITY_PRESS_TWEEN_DURATION)
			UiStyle.tween(slot.stroke, { Color = slot.accent, Transparency = 0 }, HudConstants.ABILITY_PRESS_TWEEN_DURATION)
			slot.pressHighlight.Visible = true
		else
			UiStyle.tween(slot.btn, {
				Size = UDim2.fromOffset(size, size),
				BackgroundColor3 = HudConstants.SURFACE_ELEVATED,
			}, HudConstants.ABILITY_RELEASE_TWEEN_DURATION)
			UiStyle.tween(slot.stroke, {
				Color = HudConstants.COLOR_BORDER,
				Transparency = slot.defaultStrokeTransparency,
			}, HudConstants.ABILITY_RELEASE_TWEEN_DURATION)
			slot.pressHighlight.Visible = false
		end
	end

	local function setAbilityPressed(key: string, pressed: boolean)
		local slot = keyToSlot[key]
		if not slot then
			return
		end
		if pressed and boundCharacter and slot.abilityId ~= "" then
			if AbilityCooldownHelper.isOnCooldown(boundCharacter, slot.abilityId) then
				return
			end
		end
		if slot.isPressed == pressed then
			return
		end
		applyAbilityPressedVisual(slot, pressed)
	end

	local function setAbilityCharge(key: string, ratio: number)
		local slot = keyToSlot[key]
		if not slot or not slot.chargeOverlay then
			return
		end
		ratio = math.clamp(ratio, 0, 1)
		if ratio <= 0 then
			slot.chargeOverlay.Visible = false
			slot.chargeOverlay.Size = UDim2.fromScale(1, 0)
			return
		end
		slot.chargeOverlay.Visible = true
		slot.chargeOverlay.Size = UDim2.fromScale(1, ratio)
	end

	local function isAbilityOnCooldown(abilityId: string): boolean
		if not boundCharacter then
			return false
		end
		return AbilityCooldownHelper.isOnCooldown(boundCharacter, abilityId)
	end

	local function updateCooldownVisuals(now: number)
		if not boundCharacter then
			return
		end
		for _, slot in abilitySlots do
			local total = slot.cooldownSeconds
			if not total or total <= 0 then
				slot.cooldownOverlay.Visible = false
				slot.cooldownLabel.Visible = false
				continue
			end
			local remaining = AbilityCooldownHelper.getRemaining(boundCharacter, slot.abilityId, now)
			if remaining > 0 then
				local ratio = math.clamp(remaining / total, 0, 1)
				slot.cooldownOverlay.Visible = true
				slot.cooldownOverlay.Size = UDim2.fromScale(1, ratio)
				slot.cooldownLabel.Visible = true
				slot.cooldownLabel.Text = tostring(math.ceil(remaining))
				if slot.isPressed then
					applyAbilityPressedVisual(slot, false)
				end
			else
				slot.cooldownOverlay.Visible = false
				slot.cooldownLabel.Visible = false
			end
		end
	end

	local function disconnectAbilityInput()
		if inputBeganConn then
			inputBeganConn:Disconnect()
			inputBeganConn = nil
		end
		if inputEndedConn then
			inputEndedConn:Disconnect()
			inputEndedConn = nil
		end
	end

	local function connectAbilityInput()
		disconnectAbilityInput()
		inputBeganConn = UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
			if gameProcessed or not screenGui.Enabled then
				return
			end
			if input.UserInputType ~= Enum.UserInputType.Keyboard then
				return
			end
			local abilityKey = keyCodeToAbilityKey(input.KeyCode)
			if abilityKey then
				setAbilityPressed(abilityKey, true)
			end
		end)
		inputEndedConn = UserInputService.InputEnded:Connect(function(input: InputObject)
			if input.UserInputType ~= Enum.UserInputType.Keyboard then
				return
			end
			local abilityKey = keyCodeToAbilityKey(input.KeyCode)
			if abilityKey then
				setAbilityPressed(abilityKey, false)
			end
		end)
	end

	local function buildAbilityButtons(characterId: string)
		clearAbilityButtons()
		local entry = CharacterConfig.getCharacter(characterId)
		if not entry then
			return
		end
		applyCharacterTheme(entry)

		for index, ability in entry.abilities do
			local btnSize = HudConstants.ABILITY_BUTTON_SIZE
			local isCharged = ability.chargeSeconds ~= nil and ability.chargeSeconds > 0
			local accent = entry.accentColor

			local btn = Instance.new("TextButton")
			btn.Name = ability.name
			btn.Size = UDim2.fromOffset(btnSize, btnSize)
			btn.BackgroundColor3 = HudConstants.SURFACE_ELEVATED
			btn.BorderSizePixel = 0
			btn.AutoButtonColor = false
			btn.Text = ""
			btn.LayoutOrder = index
			btn.ClipsDescendants = true
			btn.Parent = abilityRow

			local btnAspect = Instance.new("UIAspectRatioConstraint")
			btnAspect.AspectRatio = 1
			btnAspect.Parent = btn

			UiStyle.addCorner(btn, HudConstants.ABILITY_BUTTON_CORNER_RADIUS)
			local btnStroke = UiStyle.addStroke(btn, HudConstants.COLOR_BORDER, 1, 0)

			local keyCap = UiStyle.createKeyCap(btn, ability.key, accent)
			keyCap.AnchorPoint = Vector2.new(0, 0)
			keyCap.Position = UDim2.fromOffset(5, 5)

			local nameLabel = Instance.new("TextLabel")
			nameLabel.Size = UDim2.new(1, -8, 1, -28)
			nameLabel.Position = UDim2.fromOffset(4, 26)
			nameLabel.BackgroundTransparency = 1
			nameLabel.Font = HudConstants.FONT_LABEL
			nameLabel.Text = ability.name
			nameLabel.TextColor3 = HudConstants.COLOR_TEXT
			nameLabel.TextSize = HudConstants.ABILITY_BUTTON_TEXT_SIZE
			nameLabel.TextWrapped = true
			nameLabel.TextYAlignment = Enum.TextYAlignment.Top
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.ZIndex = 2
			nameLabel.Parent = btn

			local chargeOverlay = Instance.new("Frame")
			chargeOverlay.Name = "ChargeOverlay"
			chargeOverlay.Size = UDim2.fromScale(1, 0)
			chargeOverlay.AnchorPoint = Vector2.new(0, 1)
			chargeOverlay.Position = UDim2.fromScale(0, 1)
			chargeOverlay.BackgroundColor3 = accent
			chargeOverlay.BackgroundTransparency = 0.55
			chargeOverlay.BorderSizePixel = 0
			chargeOverlay.Visible = false
			chargeOverlay.ZIndex = 3
			chargeOverlay.Parent = btn
			UiStyle.addCorner(chargeOverlay, HudConstants.ABILITY_BUTTON_CORNER_RADIUS)

			local cooldownOverlay = Instance.new("Frame")
			cooldownOverlay.Name = "CooldownOverlay"
			cooldownOverlay.Size = UDim2.fromScale(1, 0)
			cooldownOverlay.AnchorPoint = Vector2.new(0, 1)
			cooldownOverlay.Position = UDim2.fromScale(0, 1)
			cooldownOverlay.BackgroundColor3 = HudConstants.SURFACE_BACKDROP
			cooldownOverlay.BackgroundTransparency = 0.25
			cooldownOverlay.BorderSizePixel = 0
			cooldownOverlay.Visible = false
			cooldownOverlay.ZIndex = 4
			cooldownOverlay.Parent = btn
			UiStyle.addCorner(cooldownOverlay, HudConstants.ABILITY_BUTTON_CORNER_RADIUS)

			local cooldownLabel = Instance.new("TextLabel")
			cooldownLabel.AnchorPoint = Vector2.new(0.5, 0.5)
			cooldownLabel.Position = UDim2.fromScale(0.5, 0.5)
			cooldownLabel.Size = UDim2.fromScale(1, 1)
			cooldownLabel.BackgroundTransparency = 1
			cooldownLabel.Font = HudConstants.FONT_HEADING
			cooldownLabel.TextColor3 = HudConstants.COLOR_TEXT
			cooldownLabel.TextSize = 16
			cooldownLabel.Visible = false
			cooldownLabel.ZIndex = 5
			cooldownLabel.Parent = btn

			local pressHighlight = Instance.new("Frame")
			pressHighlight.Size = UDim2.fromScale(1, 1)
			pressHighlight.BackgroundColor3 = accent
			pressHighlight.BackgroundTransparency = 0.82
			pressHighlight.BorderSizePixel = 0
			pressHighlight.Visible = false
			pressHighlight.ZIndex = 1
			pressHighlight.Parent = btn
			UiStyle.addCorner(pressHighlight, HudConstants.ABILITY_BUTTON_CORNER_RADIUS)

			local slot: AbilitySlot = {
				btn = btn,
				stroke = btnStroke,
				pressHighlight = pressHighlight,
				cooldownOverlay = cooldownOverlay,
				chargeOverlay = if isCharged then chargeOverlay else nil,
				cooldownLabel = cooldownLabel,
				key = ability.key,
				abilityId = ability.id,
				cooldownSeconds = ability.cooldownSeconds,
				baseSize = btnSize,
				defaultStrokeTransparency = 0,
				defaultStrokeThickness = 1,
				isPressed = false,
				accent = accent,
			}

			btn.MouseButton1Down:Connect(function()
				setAbilityPressed(ability.key, true)
			end)
			btn.MouseButton1Up:Connect(function()
				setAbilityPressed(ability.key, false)
			end)

			btn.MouseEnter:Connect(function()
				if not slot.isPressed then
					UiStyle.tween(btn, { BackgroundColor3 = HudConstants.SURFACE_PANEL })
				end
				tooltipTitle.Text = ability.name
				tooltipBody.Text = ability.description or ""
				local meta = ""
				if isCharged then
					meta = "Hold to charge"
				end
				if ability.cooldownSeconds and ability.cooldownSeconds > 0 then
					meta = if meta ~= "" then meta .. " · " else ""
					meta ..= string.format("%gs cooldown", ability.cooldownSeconds)
				end
				meta = if meta ~= "" then meta .. " · " else ""
				meta ..= "Key " .. ability.key
				tooltipMeta.Text = meta
				tooltipMeta.Visible = meta ~= ""
				tooltip.Visible = true
				local absPos = btn.AbsolutePosition
				local absSize = btn.AbsoluteSize
				tooltip.Position = UDim2.fromOffset(absPos.X + absSize.X / 2, absPos.Y - HudConstants.TOOLTIP_GAP_ABOVE_BUTTON)
			end)

			btn.MouseLeave:Connect(function()
				if slot.isPressed then
					setAbilityPressed(ability.key, false)
				else
					UiStyle.tween(btn, { BackgroundColor3 = HudConstants.SURFACE_ELEVATED })
				end
				tooltip.Visible = false
			end)

			table.insert(abilitySlots, slot)
			keyToSlot[ability.key] = slot
		end
	end

	local function refreshViewport()
		ViewportHelper.setupAvatarViewport(viewport, player, {
			character = boundCharacter or player.Character,
			characterId = currentCharacterId,
		})
	end

	local function setSiphonCharge(current: number, max: number)
		local clampedMax = math.max(1, max)
		local filled = math.clamp(math.floor(current + 0.5), 0, clampedMax)
		for i, seg in siphonSegments do
			if i <= filled then
				seg.BackgroundColor3 = HudConstants.HUD_SIPHON_CHARGE_COLOR
				seg.BackgroundTransparency = 0.15
			else
				seg.BackgroundColor3 = HudConstants.HUD_SIPHON_TRACK_COLOR
				seg.BackgroundTransparency = 0.35
			end
		end
	end

	local function setEnvAdvantage(current: number, max: number)
		local clampedMax = math.max(1, max)
		local filled = math.clamp(math.floor(current + 0.5), 0, clampedMax)
		for i, seg in envSegments do
			if i <= filled then
				seg.BackgroundColor3 = HudConstants.HUD_ENV_FILL_COLOR
				seg.BackgroundTransparency = 0.15
			else
				seg.BackgroundColor3 = HudConstants.HUD_ENV_TRACK_COLOR
				seg.BackgroundTransparency = 0.35
			end
		end
	end

	local function applySolarBarVisual()
		local fillRatio = displayedSolarStrength
		solarFill.Size = UDim2.fromScale(1, fillRatio)
		solarFill.Visible = fillRatio > 0.01
		local pct = math.floor(fillRatio * 100 + 0.5)
		solarPercentLabel.Text = string.format("%d%%", pct)
		solarPercentLabel.TextTransparency = if fillRatio > 0.12 then 0 else 0.35
	end

	local function setSolarStrengthFill(ratio: number, immediate: boolean?)
		ratio = math.clamp(ratio, 0, 1)
		targetSolarStrength = ratio
		if immediate then
			displayedSolarStrength = ratio
		end
		applySolarBarVisual()
	end

	local function resetSolarBarState()
		displayedSolarStrength = 0
		targetSolarStrength = 0
		applySolarBarVisual()
	end

	local function tickSolarStrength(dt: number)
		if currentCharacterId ~= "Sunspot" or not boundCharacter or not boundCharacter.Parent then
			return
		end
		local live = SunspotSolarHelper.computeTargetStrength(boundCharacter)
		local stored = SunspotSolarHelper.getStoredStrength(boundCharacter)
		targetSolarStrength = math.max(live, stored)
		local alpha = 1 - math.exp(-dt / 0.28)
		displayedSolarStrength += (targetSolarStrength - displayedSolarStrength) * alpha
		applySolarBarVisual()
	end

	local function tickEnvAdvantage(now: number?)
		if currentCharacterId ~= "Polaris" or not boundCharacter or not boundCharacter.Parent then
			return
		end
		local t = now or tick()
		if t - lastEnvScan < 0.08 then
			return
		end
		lastEnvScan = t
		local ferro = PolarisConstants.Ferrokinesis
		local count = MetallicTargetingHelper.countAmbientMetallicInRange(
			boundCharacter,
			ferro.AMBIENT_SCAN_RANGE,
			ferro.AMBIENT_MAX_ITEMS
		)
		setEnvAdvantage(count, ferro.AMBIENT_MAX_ITEMS)
	end

	local function updateRightBarVisibility(characterId: string?)
		siphonBar.Visible = characterId == "Havok"
		solarStrengthBar.Visible = characterId == "Sunspot"
		envBar.Visible = characterId == "Polaris"
	end

	local function updateSiphonBarVisibility(characterId: string?)
		updateRightBarVisibility(characterId)
	end

	local function show(characterId: string?)
		if characterId then
			currentCharacterId = characterId
			buildAbilityButtons(characterId)
			updateResourceLabel(characterId)
			updateSiphonBarVisibility(characterId)
			if characterId == "Sunspot" then
				resetSolarBarState()
			elseif characterId == "Polaris" then
				tickEnvAdvantage(tick())
			end
		end
		screenGui.Enabled = true
		connectAbilityInput()
		refreshViewport()
		updateBar(healthBar, healthBarText, healthLabelName, 100, 100)
		updateBar(energyBar, energyBarText, energyBarLabel, currentEnergy, maxEnergy)
	end

	local function hide()
		screenGui.Enabled = false
		tooltip.Visible = false
		siphonBar.Visible = false
		solarStrengthBar.Visible = false
		envBar.Visible = false
		for _, slot in abilitySlots do
			if slot.isPressed then
				applyAbilityPressedVisual(slot, false)
			end
		end
	end

	local function setEnergy(current: number, max: number)
		currentEnergy = current
		maxEnergy = max
		updateBar(energyBar, energyBarText, energyBarLabel, current, max)
	end

	local function setHealth(current: number, max: number)
		updateBar(healthBar, healthBarText, healthLabelName, current, max, HudConstants.COLOR_HP_FLASH_DAMAGE)
	end

	local function bindCharacter(character: Model)
		boundCharacter = character
		resetSolarBarState()
		for _, conn in { healthConn, energyConn, maxEnergyConn, siphonConn, solarStrengthConn, cooldownConn } do
			if conn then
				conn:Disconnect()
			end
		end
		healthConn, energyConn, maxEnergyConn, siphonConn, solarStrengthConn, cooldownConn = nil, nil, nil, nil, nil, nil

		refreshViewport()
		viewportRetryToken += 1
		local retryToken = viewportRetryToken
		task.delay(0.6, function()
			if viewportRetryToken == retryToken and boundCharacter == character then
				refreshViewport()
			end
		end)

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end

		local function syncHealth()
			updateBar(healthBar, healthBarText, healthLabelName, humanoid.Health, humanoid.MaxHealth)
		end
		local function syncEnergyFromAttributes()
			local energy = character:GetAttribute("Energy")
			local maxEnergyAttr = character:GetAttribute("MaxEnergy")
			local current = if typeof(energy) == "number" then energy else maxEnergy
			local maxVal = if typeof(maxEnergyAttr) == "number" then maxEnergyAttr else 100
			setEnergy(current, maxVal)
		end

		local function syncSiphonFromAttributes()
			if currentCharacterId ~= "Havok" then
				return
			end
			local charge = character:GetAttribute("HavokCharge")
			local maxCharge = character:GetAttribute("MaxHavokCharge")
			local current = if typeof(charge) == "number" then charge else 0
			local maxVal = if typeof(maxCharge) == "number" then maxCharge else 5
			setSiphonCharge(current, maxVal)
		end

		syncHealth()
		syncEnergyFromAttributes()
		syncSiphonFromAttributes()
		if currentCharacterId == "Sunspot" then
			tickSolarStrength(0)
		end
		if currentCharacterId == "Polaris" then
			tickEnvAdvantage()
		end
		healthConn = humanoid.HealthChanged:Connect(syncHealth)
		energyConn = character:GetAttributeChangedSignal("Energy"):Connect(syncEnergyFromAttributes)
		maxEnergyConn = character:GetAttributeChangedSignal("MaxEnergy"):Connect(syncEnergyFromAttributes)
		siphonConn = character:GetAttributeChangedSignal("HavokCharge"):Connect(syncSiphonFromAttributes)
		solarStrengthConn = character:GetAttributeChangedSignal("SunspotStrength"):Connect(function()
			if currentCharacterId == "Sunspot" then
				tickSolarStrength(0)
			end
		end)
		cooldownConn = RunService.Heartbeat:Connect(function()
			updateCooldownVisuals(AbilityCooldownHelper.getNow())
		end)
	end

	solarStrengthHeartbeat = RunService.Heartbeat:Connect(function(dt)
		tickSolarStrength(dt)
	end)

	local envAdvantageHeartbeat = RunService.Heartbeat:Connect(function()
		tickEnvAdvantage(tick())
	end)

	local function destroy()
		disconnectAbilityInput()
		for _, conn in { healthConn, energyConn, maxEnergyConn, siphonConn, solarStrengthConn, solarStrengthHeartbeat, envAdvantageHeartbeat, cooldownConn } do
			if conn then
				conn:Disconnect()
			end
		end
		viewportRetryToken += 1
		screenGui:Destroy()
	end

	return {
		screenGui = screenGui,
		show = show,
		hide = hide,
		bindCharacter = bindCharacter,
		setEnergy = setEnergy,
		setHealth = setHealth,
		setAbilityPressed = setAbilityPressed,
		setAbilityCharge = setAbilityCharge,
		setSiphonCharge = setSiphonCharge,
		isAbilityOnCooldown = isAbilityOnCooldown,
		refreshViewport = refreshViewport,
		destroy = destroy,
	}
end

return GameplayHUD
