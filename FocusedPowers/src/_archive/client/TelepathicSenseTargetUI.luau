--!strict
--[[
	Side-panel intel for Telepathic Sense locked target: stats, hero, abilities, cooldowns.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local AbilityCooldownHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityCooldownHelper"))
local CharacterConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CharacterConfig"))
local EntityStatsHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("EntityStatsHelper"))
local HudConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("HudConstants"))

local TelepathicSenseTargetUI = {}

local screenGui: ScreenGui? = nil
local panel: Frame? = nil
local nameLabel: TextLabel? = nil
local heroLabel: TextLabel? = nil
local hpFill: Frame? = nil
local hpText: TextLabel? = nil
local enFill: Frame? = nil
local enText: TextLabel? = nil
local statusLabel: TextLabel? = nil
local abilityList: Frame? = nil
local noAbilitiesLabel: TextLabel? = nil

local boundModel: Model? = nil
local abilityRows: { { row: Frame, ability: any, statusLabel: TextLabel } } = {}
local updateConn: RBXScriptConnection? = nil
local attributeConns: { RBXScriptConnection } = {}
local healthConn: RBXScriptConnection? = nil

local ACTIVE_ATTRS: { [string]: string } = {
	TelekineticFlight = "IsTelekineticFlying",
	Telekinesis = "IsTelekinesisActive",
	TelepathicSense = "IsTelepathicSenseActive",
}

local function disconnectAll()
	if updateConn then
		updateConn:Disconnect()
		updateConn = nil
	end
	if healthConn then
		healthConn:Disconnect()
		healthConn = nil
	end
	for _, conn in attributeConns do
		conn:Disconnect()
	end
	table.clear(attributeConns)
end

local function updateBar(fill: Frame, textLabel: TextLabel, current: number, max: number)
	local ratio = if max > 0 then math.clamp(current / max, 0, 1) else 0
	textLabel.Text = string.format("%d / %d", math.floor(current + 0.5), math.floor(max + 0.5))
	TweenService:Create(
		fill,
		TweenInfo.new(HudConstants.BAR_TWEEN_DURATION, HudConstants.UI_EASING_STYLE, HudConstants.UI_EASING_DIRECTION),
		{ Size = UDim2.fromScale(ratio, 1) }
	):Play()
end

local function getCharacterEntry(model: Model)
	local plr = EntityStatsHelper.getPlayerForModel(model)
	local charId = if plr then plr:GetAttribute("SelectedCharacter") else model:GetAttribute("SelectedCharacter")
	if typeof(charId) == "string" and charId ~= "" then
		return CharacterConfig.getCharacter(charId)
	end
	return nil
end

local function getAbilityStatus(model: Model, ability: any): (string, Color3)
	local activeAttr = ACTIVE_ATTRS[ability.id]
	if activeAttr and model:GetAttribute(activeAttr) == true then
		return "Active", HudConstants.COLOR_PRIMARY
	end
	local remaining = AbilityCooldownHelper.getRemaining(model, ability.id)
	if remaining > 0 then
		return string.format("%.1fs", remaining), HudConstants.COLOR_TEXT_MUTED
	end
	if ability.chargeSeconds and ability.chargeSeconds > 0 then
		return "Hold to charge", HudConstants.COLOR_TEXT
	end
	return "Ready", HudConstants.COLOR_HP
end

local function getStatusLine(model: Model): string
	local parts: { string } = {}
	if model:GetAttribute("IsTelekineticFlying") == true then
		table.insert(parts, "Flying")
	end
	if model:GetAttribute("IsTelekinesisActive") == true then
		table.insert(parts, "Telekinesis")
	end
	if model:GetAttribute("IsTelepathicSenseActive") == true then
		table.insert(parts, "Telepathic Sense")
	end
	if model:GetAttribute("Ragdolled") == true then
		table.insert(parts, "Ragdolled")
	end
	if #parts == 0 then
		return "Status: Idle"
	end
	return "Status: " .. table.concat(parts, ", ")
end

local function clearAbilityRows()
	for _, entry in abilityRows do
		entry.row:Destroy()
	end
	table.clear(abilityRows)
	if noAbilitiesLabel then
		noAbilitiesLabel.Visible = false
	end
end

local function makeBar(parent: Instance, color: Color3, layoutOrder: number): (Frame, TextLabel)
	local bg = Instance.new("Frame")
	bg.Name = "Bar"
	bg.Size = UDim2.new(1, 0, 0, 16)
	bg.BackgroundColor3 = HudConstants.COLOR_BAR_BG
	bg.BorderSizePixel = 0
	bg.ClipsDescendants = true
	bg.LayoutOrder = layoutOrder
	bg.Parent = parent

	local bgCorner = Instance.new("UICorner")
	bgCorner.CornerRadius = UDim.new(0, 6)
	bgCorner.Parent = bg

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.ZIndex = 1
	fill.Parent = bg

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 6)
	fillCorner.Parent = fill

	local value = Instance.new("TextLabel")
	value.Size = UDim2.fromScale(1, 1)
	value.BackgroundTransparency = 1
	value.Font = Enum.Font.GothamBold
	value.TextSize = 9
	value.TextColor3 = Color3.new(1, 1, 1)
	value.TextStrokeTransparency = 0.35
	value.ZIndex = 2
	value.Parent = bg

	return fill, value
end

local function rebuildAbilityRows(model: Model, entry: any)
	clearAbilityRows()
	local list = abilityList
	if not list then
		return
	end

	if not entry or #entry.abilities == 0 then
		if noAbilitiesLabel then
			noAbilitiesLabel.Visible = true
		end
		return
	end

	for index, ability in entry.abilities do
		local row = Instance.new("Frame")
		row.Name = ability.id
		row.Size = UDim2.new(1, 0, 0, 24)
		row.BackgroundColor3 = HudConstants.COLOR_PANEL_FRAME
		row.BackgroundTransparency = 0.25
		row.BorderSizePixel = 0
		row.LayoutOrder = index
		row.Parent = list

		local rowCorner = Instance.new("UICorner")
		rowCorner.CornerRadius = UDim.new(0, 6)
		rowCorner.Parent = row

		local rowPadding = Instance.new("UIPadding")
		rowPadding.PaddingLeft = UDim.new(0, 6)
		rowPadding.PaddingRight = UDim.new(0, 6)
		rowPadding.PaddingTop = UDim.new(0, 2)
		rowPadding.PaddingBottom = UDim.new(0, 2)
		rowPadding.Parent = row

		local abilityName = Instance.new("TextLabel")
		abilityName.Size = UDim2.new(1, -36, 0, 11)
		abilityName.BackgroundTransparency = 1
		abilityName.Font = Enum.Font.GothamMedium
		abilityName.TextSize = 9
		abilityName.TextXAlignment = Enum.TextXAlignment.Left
		abilityName.TextColor3 = HudConstants.COLOR_TEXT
		abilityName.Text = ability.name
		abilityName.Parent = row

		local keyBadge = Instance.new("TextLabel")
		keyBadge.AnchorPoint = Vector2.new(1, 0)
		keyBadge.Position = UDim2.new(1, 0, 0, 0)
		keyBadge.Size = UDim2.fromOffset(14, 11)
		keyBadge.BackgroundColor3 = entry.accentColor
		keyBadge.BackgroundTransparency = 0.2
		keyBadge.Font = Enum.Font.GothamBold
		keyBadge.TextSize = 8
		keyBadge.TextColor3 = Color3.new(1, 1, 1)
		keyBadge.Text = ability.key
		keyBadge.Parent = row

		local keyCorner = Instance.new("UICorner")
		keyCorner.CornerRadius = UDim.new(0, 4)
		keyCorner.Parent = keyBadge

		local abilityStatus = Instance.new("TextLabel")
		abilityStatus.Position = UDim2.fromOffset(0, 12)
		abilityStatus.Size = UDim2.new(1, 0, 0, 10)
		abilityStatus.BackgroundTransparency = 1
		abilityStatus.Font = Enum.Font.Gotham
		abilityStatus.TextSize = 8
		abilityStatus.TextXAlignment = Enum.TextXAlignment.Left
		abilityStatus.Parent = row

		table.insert(abilityRows, { row = row, ability = ability, statusLabel = abilityStatus })
	end
end

local function syncPanel()
	local model = boundModel
	if not model or not model.Parent then
		return
	end

	local stats = EntityStatsHelper.getStats(model)
	if not stats then
		return
	end

	if nameLabel then
		nameLabel.Text = stats.displayName
	end

	local entry = getCharacterEntry(model)
	if heroLabel then
		if entry then
			heroLabel.Text = entry.displayName .. " · " .. entry.subtitle
			heroLabel.TextColor3 = entry.accentColor
		else
			heroLabel.Text = "Unknown hero"
			heroLabel.TextColor3 = HudConstants.COLOR_TEXT_MUTED
		end
	end

	if hpFill and hpText then
		updateBar(hpFill, hpText, stats.health, stats.maxHealth)
	end
	if enFill and enText then
		updateBar(enFill, enText, stats.energy, stats.maxEnergy)
	end
	if statusLabel then
		statusLabel.Text = getStatusLine(model)
	end

	for _, rowEntry in abilityRows do
		local text, color = getAbilityStatus(model, rowEntry.ability)
		rowEntry.statusLabel.Text = text
		rowEntry.statusLabel.TextColor3 = color
	end
end

function TelepathicSenseTargetUI.init(playerGui: PlayerGui)
	if screenGui then
		return
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "TelepathicSenseIntel"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = HudConstants.HUD_DISPLAY_ORDER + 5
	gui.Enabled = true
	gui.Parent = playerGui
	screenGui = gui

	local frame = Instance.new("Frame")
	frame.Name = "IntelPanel"
	frame.AnchorPoint = Vector2.new(1, 0.5)
	frame.Position = UDim2.new(1, -10, 0.5, 0)
	frame.Size = UDim2.fromOffset(148, 240)
	frame.BackgroundColor3 = HudConstants.COLOR_PANEL_BG
	frame.BackgroundTransparency = 0.08
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = gui
	panel = frame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = HudConstants.COLOR_STROKE
	stroke.Thickness = 1
	stroke.Transparency = 0.35
	stroke.Parent = frame

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 5)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 12)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 9
	title.TextColor3 = HudConstants.COLOR_TEXT_MUTED
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "TELEPATHIC INTEL"
	title.LayoutOrder = 0
	title.Parent = frame

	nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "TargetName"
	nameLabel.Size = UDim2.new(1, 0, 0, 16)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 13
	nameLabel.TextColor3 = HudConstants.COLOR_TEXT
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextWrapped = true
	nameLabel.LayoutOrder = 1
	nameLabel.Parent = frame

	heroLabel = Instance.new("TextLabel")
	heroLabel.Name = "Hero"
	heroLabel.Size = UDim2.new(1, 0, 0, 12)
	heroLabel.BackgroundTransparency = 1
	heroLabel.Font = Enum.Font.GothamMedium
	heroLabel.TextSize = 9
	heroLabel.TextXAlignment = Enum.TextXAlignment.Left
	heroLabel.TextWrapped = true
	heroLabel.LayoutOrder = 2
	heroLabel.Parent = frame

	hpFill, hpText = makeBar(frame, HudConstants.COLOR_HP, 3)
	enFill, enText = makeBar(frame, HudConstants.COLOR_PRIMARY, 4)

	statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "Status"
	statusLabel.Size = UDim2.new(1, 0, 0, 11)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Font = Enum.Font.Gotham
	statusLabel.TextSize = 8
	statusLabel.TextColor3 = HudConstants.COLOR_TEXT_MUTED
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.LayoutOrder = 5
	statusLabel.Parent = frame

	local abilitiesHeader = Instance.new("TextLabel")
	abilitiesHeader.Name = "AbilitiesHeader"
	abilitiesHeader.Size = UDim2.new(1, 0, 0, 12)
	abilitiesHeader.BackgroundTransparency = 1
	abilitiesHeader.Font = Enum.Font.GothamBold
	abilitiesHeader.TextSize = 9
	abilitiesHeader.TextColor3 = HudConstants.COLOR_TEXT_MUTED
	abilitiesHeader.TextXAlignment = Enum.TextXAlignment.Left
	abilitiesHeader.Text = "ABILITIES"
	abilitiesHeader.LayoutOrder = 6
	abilitiesHeader.Parent = frame

	abilityList = Instance.new("Frame")
	abilityList.Name = "AbilityList"
	abilityList.Size = UDim2.new(1, 0, 0, 0)
	abilityList.AutomaticSize = Enum.AutomaticSize.Y
	abilityList.BackgroundTransparency = 1
	abilityList.LayoutOrder = 7
	abilityList.Parent = frame

	local abilityLayout = Instance.new("UIListLayout")
	abilityLayout.Padding = UDim.new(0, 4)
	abilityLayout.SortOrder = Enum.SortOrder.LayoutOrder
	abilityLayout.Parent = abilityList

	noAbilitiesLabel = Instance.new("TextLabel")
	noAbilitiesLabel.Name = "NoAbilities"
	noAbilitiesLabel.Size = UDim2.new(1, 0, 0, 14)
	noAbilitiesLabel.BackgroundTransparency = 1
	noAbilitiesLabel.Font = Enum.Font.Gotham
	noAbilitiesLabel.TextSize = 10
	noAbilitiesLabel.TextColor3 = HudConstants.COLOR_TEXT_MUTED
	noAbilitiesLabel.TextXAlignment = Enum.TextXAlignment.Left
	noAbilitiesLabel.Text = "No abilities detected"
	noAbilitiesLabel.Visible = false
	noAbilitiesLabel.LayoutOrder = 8
	noAbilitiesLabel.Parent = frame
end

function TelepathicSenseTargetUI.show(model: Model)
	if not panel then
		return
	end

	disconnectAll()
	boundModel = model
	panel.Visible = true

	rebuildAbilityRows(model, getCharacterEntry(model))
	syncPanel()

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		healthConn = humanoid.HealthChanged:Connect(syncPanel)
	end

	local watchAttrs = {
		"Energy",
		"MaxEnergy",
		"IsTelekineticFlying",
		"IsTelekinesisActive",
		"IsTelepathicSenseActive",
		"Ragdolled",
		"SelectedCharacter",
	}
	for _, attrName in watchAttrs do
		table.insert(attributeConns, model:GetAttributeChangedSignal(attrName):Connect(syncPanel))
	end

	local entry = getCharacterEntry(model)
	if entry then
		for _, ability in entry.abilities do
			table.insert(
				attributeConns,
				model:GetAttributeChangedSignal(AbilityCooldownHelper.getAttributeName(ability.id)):Connect(syncPanel)
			)
		end
	end

	local plr = EntityStatsHelper.getPlayerForModel(model)
	if plr then
		table.insert(attributeConns, plr:GetAttributeChangedSignal("SelectedCharacter"):Connect(function()
			rebuildAbilityRows(model, getCharacterEntry(model))
			syncPanel()
		end))
	end

	updateConn = RunService.Heartbeat:Connect(syncPanel)
end

function TelepathicSenseTargetUI.hide()
	disconnectAll()
	boundModel = nil
	clearAbilityRows()
	if panel then
		panel.Visible = false
	end
end

return TelepathicSenseTargetUI
