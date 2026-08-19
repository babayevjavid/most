--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AbilityCooldownHelper = require(ReplicatedStorage.Shared.AbilityCooldownHelper)
local CharacterRegistry = require(ReplicatedStorage.Shared.CharacterRegistry)
local MonetConstants = require(ReplicatedStorage.Shared.MonetConstants)
local ViewportHelper = require(script.Parent.ViewportHelper)

export type HudController = {
	show: (heroId: string) -> (),
	hide: () -> (),
	bindCharacter: (character: Model) -> (),
	destroy: () -> (),
}

type AbilitySlot = {
	btn: TextButton,
	cooldownOverlay: Frame,
	cooldownLabel: TextLabel,
	abilityId: string?,
	cooldownSeconds: number?,
}

local BAR_COLORS = {
	Health = Color3.fromRGB(55, 175, 85),
	Energy = Color3.fromRGB(170, 195, 220),
}

local THEME = {
	Monet = {
		accent = Color3.fromRGB(200, 220, 240),
		btn = Color3.fromRGB(32, 36, 42),
		btnHover = Color3.fromRGB(42, 48, 56),
		stroke = Color3.fromRGB(160, 185, 210),
	},
	Penance = {
		accent = Color3.fromRGB(210, 55, 75),
		btn = Color3.fromRGB(52, 28, 34),
		btnHover = Color3.fromRGB(68, 34, 42),
		stroke = Color3.fromRGB(170, 45, 65),
	},
}

local TOP_EXTRA_BELOW_INSET = 58
local ABILITY_BTN_WIDTH = 108
local ABILITY_BTN_HEIGHT = 66

local function createStatBar(parent: Frame, name: string, color: Color3, layoutOrder: number): (Frame, TextLabel, Frame)
	local row = Instance.new("Frame")
	row.Name = name .. "Row"
	row.LayoutOrder = layoutOrder
	row.Size = UDim2.new(0, 200, 0, 22)
	row.BackgroundTransparency = 1
	row.Parent = parent

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Size = UDim2.fromScale(1, 1)
	track.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
	track.BorderSizePixel = 0
	track.Parent = row

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(0, 5)
	trackCorner.Parent = track

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Parent = track

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 5)
	fillCorner.Parent = fill

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.Text = name .. ": 0/0"
	label.TextColor3 = Color3.fromRGB(245, 245, 248)
	label.TextSize = 12
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.ZIndex = 2
	label.Parent = track

	return row, label, fill
end

local function addCorner(inst: GuiObject, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = inst
end

local function createKeyBadge(parent: GuiObject, keyText: string, accent: Color3): Frame
	local badge = Instance.new("Frame")
	badge.Name = "KeyBadge"
	badge.AnchorPoint = Vector2.new(1, 0)
	badge.Position = UDim2.new(1, -5, 0, 5)
	badge.Size = UDim2.fromOffset(24, 20)
	badge.BackgroundColor3 = accent
	badge.BorderSizePixel = 0
	badge.ZIndex = 6
	badge.Parent = parent
	addCorner(badge, 5)

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.Text = keyText
	label.TextColor3 = Color3.fromRGB(250, 250, 252)
	label.TextSize = 12
	label.ZIndex = 7
	label.Parent = badge

	return badge
end

local function createCooldownOverlay(parent: GuiObject): (Frame, TextLabel)
	local overlay = Instance.new("Frame")
	overlay.Name = "CooldownOverlay"
	overlay.AnchorPoint = Vector2.new(0, 1)
	overlay.Position = UDim2.fromScale(0, 1)
	overlay.Size = UDim2.fromScale(1, 0)
	overlay.BackgroundColor3 = Color3.fromRGB(8, 8, 12)
	overlay.BackgroundTransparency = 0.15
	overlay.BorderSizePixel = 0
	overlay.Visible = false
	overlay.ZIndex = 8
	overlay.ClipsDescendants = true
	overlay.Parent = parent
	addCorner(overlay, 8)

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(12, 12, 18)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(20, 20, 30)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(35, 35, 50)),
	})
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(0.6, 0.25),
		NumberSequenceKeypoint.new(1, 0.75),
	})
	gradient.Parent = overlay

	local cdLabel = Instance.new("TextLabel")
	cdLabel.Name = "CooldownText"
	cdLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	cdLabel.Position = UDim2.fromScale(0.5, 0.5)
	cdLabel.Size = UDim2.fromScale(1, 1)
	cdLabel.BackgroundTransparency = 1
	cdLabel.Font = Enum.Font.GothamBold
	cdLabel.Text = ""
	cdLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	cdLabel.TextSize = 18
	cdLabel.Visible = false
	cdLabel.ZIndex = 9
	cdLabel.Parent = parent

	return overlay, cdLabel
end

local GameplayHUD = {}

function GameplayHUD.create(playerGui: PlayerGui): HudController
	local player = Players.LocalPlayer
	local currentHeroId: string? = nil
	local currentForm: string? = nil
	local healthConn: RBXScriptConnection? = nil
	local cooldownConn: RBXScriptConnection? = nil
	local boundCharacter: Model? = nil
	local abilitySlots: { AbilitySlot } = {}

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "GameplayHUD"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 10
	screenGui.Enabled = false
	screenGui.Parent = playerGui

	local guiInset = GuiService:GetGuiInset()

	local topCluster = Instance.new("Frame")
	topCluster.Name = "TopCluster"
	topCluster.Position = UDim2.fromOffset(guiInset.X + 12, guiInset.Y + TOP_EXTRA_BELOW_INSET)
	topCluster.Size = UDim2.fromOffset(292, 62)
	topCluster.BackgroundTransparency = 1
	topCluster.Parent = screenGui

	local viewportHolder = Instance.new("Frame")
	viewportHolder.Name = "ViewportHolder"
	viewportHolder.Size = UDim2.fromOffset(88, 88)
	viewportHolder.BackgroundColor3 = Color3.fromRGB(16, 16, 20)
	viewportHolder.BorderSizePixel = 0
	viewportHolder.Parent = topCluster
	addCorner(viewportHolder, 8)

	local vpStroke = Instance.new("UIStroke")
	vpStroke.Color = Color3.fromRGB(60, 60, 72)
	vpStroke.Thickness = 1
	vpStroke.Transparency = 0.35
	vpStroke.Parent = viewportHolder

	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "CharacterViewport"
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.BackgroundTransparency = 1
	viewport.BorderSizePixel = 0
	viewport.Parent = viewportHolder

	local barsColumn = Instance.new("Frame")
	barsColumn.Name = "Bars"
	barsColumn.Position = UDim2.fromOffset(98, 0)
	barsColumn.Size = UDim2.fromOffset(200, 62)
	barsColumn.BackgroundTransparency = 1
	barsColumn.Parent = topCluster

	local barsLayout = Instance.new("UIListLayout")
	barsLayout.FillDirection = Enum.FillDirection.Vertical
	barsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	barsLayout.Padding = UDim.new(0, 6)
	barsLayout.Parent = barsColumn

	local _, healthLabel, healthFill = createStatBar(barsColumn, "Health", BAR_COLORS.Health, 1)
	local _, energyLabel, energyFill = createStatBar(barsColumn, "Energy", BAR_COLORS.Energy, 2)

	local function setBar(fill: Frame, label: TextLabel, prefix: string, current: number, max: number)
		local ratio = if max > 0 then math.clamp(current / max, 0, 1) else 0
		fill.Size = UDim2.fromScale(ratio, 1)
		label.Text = string.format("%s: %d/%d", prefix, math.floor(current + 0.5), math.floor(max + 0.5))
	end

	local abilityBar = Instance.new("Frame")
	abilityBar.Name = "AbilityBar"
	abilityBar.AnchorPoint = Vector2.new(0.5, 1)
	abilityBar.Position = UDim2.new(0.5, 0, 1, -(guiInset.Y + 18))
	abilityBar.AutomaticSize = Enum.AutomaticSize.XY
	abilityBar.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
	abilityBar.BackgroundTransparency = 0.12
	abilityBar.BorderSizePixel = 0
	abilityBar.Parent = screenGui
	addCorner(abilityBar, 12)

	local abilityStroke = Instance.new("UIStroke")
	abilityStroke.Color = Color3.fromRGB(55, 55, 68)
	abilityStroke.Thickness = 1
	abilityStroke.Transparency = 0.4
	abilityStroke.Parent = abilityBar

	local abilityPadding = Instance.new("UIPadding")
	abilityPadding.PaddingTop = UDim.new(0, 10)
	abilityPadding.PaddingBottom = UDim.new(0, 10)
	abilityPadding.PaddingLeft = UDim.new(0, 12)
	abilityPadding.PaddingRight = UDim.new(0, 12)
	abilityPadding.Parent = abilityBar

	local abilityRow = Instance.new("Frame")
	abilityRow.Name = "AbilityRow"
	abilityRow.AutomaticSize = Enum.AutomaticSize.XY
	abilityRow.BackgroundTransparency = 1
	abilityRow.Parent = abilityBar

	local abilityLayout = Instance.new("UIListLayout")
	abilityLayout.FillDirection = Enum.FillDirection.Horizontal
	abilityLayout.SortOrder = Enum.SortOrder.LayoutOrder
	abilityLayout.Padding = UDim.new(0, 10)
	abilityLayout.Parent = abilityRow

	local tooltip = Instance.new("Frame")
	tooltip.Name = "AbilityTooltip"
	tooltip.Size = UDim2.fromOffset(280, 0)
	tooltip.AutomaticSize = Enum.AutomaticSize.Y
	tooltip.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
	tooltip.BackgroundTransparency = 0.06
	tooltip.BorderSizePixel = 0
	tooltip.Visible = false
	tooltip.ZIndex = 50
	tooltip.Parent = screenGui
	addCorner(tooltip, 8)

	local tooltipStroke = Instance.new("UIStroke")
	tooltipStroke.Color = Color3.fromRGB(70, 70, 88)
	tooltipStroke.Thickness = 1
	tooltipStroke.Transparency = 0.45
	tooltipStroke.Parent = tooltip

	local tooltipPadding = Instance.new("UIPadding")
	tooltipPadding.PaddingTop = UDim.new(0, 10)
	tooltipPadding.PaddingBottom = UDim.new(0, 10)
	tooltipPadding.PaddingLeft = UDim.new(0, 12)
	tooltipPadding.PaddingRight = UDim.new(0, 12)
	tooltipPadding.Parent = tooltip

	local tooltipTitle = Instance.new("TextLabel")
	tooltipTitle.Name = "Title"
	tooltipTitle.Size = UDim2.new(1, 0, 0, 18)
	tooltipTitle.BackgroundTransparency = 1
	tooltipTitle.Font = Enum.Font.GothamMedium
	tooltipTitle.TextColor3 = Color3.fromRGB(240, 240, 245)
	tooltipTitle.TextSize = 14
	tooltipTitle.TextXAlignment = Enum.TextXAlignment.Left
	tooltipTitle.TextWrapped = true
	tooltipTitle.Parent = tooltip

	local tooltipBody = Instance.new("TextLabel")
	tooltipBody.Name = "Body"
	tooltipBody.Position = UDim2.fromOffset(0, 22)
	tooltipBody.Size = UDim2.new(1, 0, 0, 0)
	tooltipBody.AutomaticSize = Enum.AutomaticSize.Y
	tooltipBody.BackgroundTransparency = 1
	tooltipBody.Font = Enum.Font.Gotham
	tooltipBody.TextColor3 = Color3.fromRGB(165, 165, 178)
	tooltipBody.TextSize = 12
	tooltipBody.TextWrapped = true
	tooltipBody.TextXAlignment = Enum.TextXAlignment.Left
	tooltipBody.Parent = tooltip

	local tooltipConn: RBXScriptConnection? = nil

	local function hideTooltip()
		tooltip.Visible = false
		if tooltipConn then
			tooltipConn:Disconnect()
			tooltipConn = nil
		end
	end

	local function showTooltip(abilityName: string, description: string)
		tooltipTitle.Text = abilityName
		tooltipBody.Text = description
		tooltip.Visible = true
		if tooltipConn then
			tooltipConn:Disconnect()
		end
		tooltipConn = RunService.RenderStepped:Connect(function()
			local mouse = player:GetMouse()
			tooltip.Position = UDim2.fromOffset(mouse.X + 18, mouse.Y + 18)
		end)
	end

	local function clearAbilitySlots()
		for _, slot in abilitySlots do
			slot.btn:Destroy()
		end
		table.clear(abilitySlots)
		hideTooltip()
	end

	local function getTheme(form: string)
		if form == "Penance" then
			return THEME.Penance
		end
		return THEME.Monet
	end

	local function createAbilityButton(
		name: string,
		displayName: string,
		description: string,
		key: string,
		layoutOrder: number,
		theme: typeof(THEME.Monet),
		abilityId: string?,
		cooldownSeconds: number?
	): AbilitySlot
		local btn = Instance.new("TextButton")
		btn.Name = name
		btn.LayoutOrder = layoutOrder
		btn.Size = UDim2.fromOffset(ABILITY_BTN_WIDTH, ABILITY_BTN_HEIGHT)
		btn.BackgroundColor3 = theme.btn
		btn.AutoButtonColor = false
		btn.Text = ""
		btn.ClipsDescendants = true
		btn.Parent = abilityRow
		addCorner(btn, 8)

		local stroke = Instance.new("UIStroke")
		stroke.Color = theme.stroke
		stroke.Thickness = 1
		stroke.Transparency = 0.35
		stroke.Parent = btn

		createKeyBadge(btn, key, theme.accent)

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "AbilityName"
		nameLabel.Position = UDim2.fromOffset(8, 10)
		nameLabel.Size = UDim2.new(1, -16, 1, -14)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = Enum.Font.GothamMedium
		nameLabel.Text = displayName
		nameLabel.TextColor3 = Color3.fromRGB(238, 238, 242)
		nameLabel.TextSize = 11
		nameLabel.TextWrapped = true
		nameLabel.TextYAlignment = Enum.TextYAlignment.Center
		nameLabel.TextXAlignment = Enum.TextXAlignment.Center
		nameLabel.ZIndex = 3
		nameLabel.Parent = btn

		local cooldownOverlay, cooldownLabel = createCooldownOverlay(btn)

		btn.MouseEnter:Connect(function()
			btn.BackgroundColor3 = theme.btnHover
			showTooltip(displayName, description)
		end)
		btn.MouseLeave:Connect(function()
			btn.BackgroundColor3 = theme.btn
			hideTooltip()
		end)

		return {
			btn = btn,
			cooldownOverlay = cooldownOverlay,
			cooldownLabel = cooldownLabel,
			abilityId = abilityId,
			cooldownSeconds = cooldownSeconds,
		}
	end

	local function updateCooldowns()
		local character = boundCharacter
		if not character or not character.Parent then
			return
		end
		for _, slot in abilitySlots do
			if not slot.abilityId or not slot.cooldownSeconds then
				slot.cooldownOverlay.Visible = false
				slot.cooldownLabel.Visible = false
				continue
			end
			local remaining = AbilityCooldownHelper.getRemaining(character, slot.abilityId)
			if remaining > 0 then
				local ratio = math.clamp(remaining / slot.cooldownSeconds, 0, 1)
				slot.cooldownOverlay.Visible = true
				slot.cooldownOverlay.Size = UDim2.fromScale(1, ratio)
				slot.cooldownLabel.Visible = true
				slot.cooldownLabel.Text = string.format("%.1f", remaining)
			else
				slot.cooldownOverlay.Visible = false
				slot.cooldownLabel.Visible = false
			end
		end
	end

	local function rebuildAbilityBar(heroId: string, form: string)
		clearAbilitySlots()
		local formTyped = if form == "Penance" then "Penance" else "Monet"
		local theme = getTheme(formTyped)
		local abilities = CharacterRegistry.getAbilitiesForForm(heroId, formTyped)
		table.sort(abilities, function(a, b)
			local order = { Q = 1, F = 2, R = 3, T = 4 }
			return (order[a.key] or 99) < (order[b.key] or 99)
		end)

		local formDesc = if formTyped == "Monet"
			then "Switch to Penance — red diamond skin, 350 HP, melee kit."
			else "Switch to Monet — restore appearance, 280 HP, psychic kit."

		table.insert(
			abilitySlots,
			createAbilityButton("FormSwap", "Form Swap", formDesc, "E", 0, theme, nil, nil)
		)

		for i, ability in abilities do
			table.insert(
				abilitySlots,
				createAbilityButton(
					ability.id,
					ability.name,
					ability.description,
					ability.key,
					i,
					theme,
					ability.id,
					ability.cooldown
				)
			)
		end

		abilityStroke.Color = theme.stroke
	end

	local function refreshStats(character: Model)
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			setBar(healthFill, healthLabel, "Health", humanoid.Health, humanoid.MaxHealth)
		end
		local energy = character:GetAttribute(MonetConstants.ENERGY_ATTRIBUTE)
		local maxEnergy = character:GetAttribute(MonetConstants.MAX_ENERGY_ATTRIBUTE)
		if type(energy) == "number" and type(maxEnergy) == "number" then
			setBar(energyFill, energyLabel, "Energy", energy, maxEnergy)
		end

		if currentHeroId then
			local form = tostring(character:GetAttribute(MonetConstants.FORM_ATTRIBUTE) or "Monet")
			if form ~= currentForm then
				currentForm = form
				rebuildAbilityBar(currentHeroId, form)
			end
		end
	end

	local function startCooldownLoop()
		if cooldownConn then
			cooldownConn:Disconnect()
		end
		cooldownConn = RunService.RenderStepped:Connect(updateCooldowns)
	end

	local function stopCooldownLoop()
		if cooldownConn then
			cooldownConn:Disconnect()
			cooldownConn = nil
		end
	end

	return {
		show = function(heroId: string)
			currentHeroId = heroId
			currentForm = nil
			screenGui.Enabled = true
			startCooldownLoop()
		end,
		hide = function()
			screenGui.Enabled = false
			stopCooldownLoop()
			hideTooltip()
		end,
		bindCharacter = function(character: Model)
			if not character or not character.Parent then
				return
			end
			boundCharacter = character
			if healthConn then
				healthConn:Disconnect()
			end
			local humanoid = character:WaitForChild("Humanoid") :: Humanoid
			healthConn = humanoid.HealthChanged:Connect(function()
				refreshStats(character)
			end)
			character:GetAttributeChangedSignal(MonetConstants.ENERGY_ATTRIBUTE):Connect(function()
				refreshStats(character)
			end)
			character:GetAttributeChangedSignal(MonetConstants.FORM_ATTRIBUTE):Connect(function()
				refreshStats(character)
				ViewportHelper.bindCharacter(viewport, character)
			end)
			ViewportHelper.bindCharacter(viewport, character)
			refreshStats(character)
		end,
		destroy = function()
			if healthConn then
				healthConn:Disconnect()
			end
			stopCooldownLoop()
			hideTooltip()
			screenGui:Destroy()
		end,
	}
end

return GameplayHUD
