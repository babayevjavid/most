--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AbilityCooldownHelper = require(ReplicatedStorage.Shared.AbilityCooldownHelper)
local CharacterRegistry = require(ReplicatedStorage.Shared.CharacterRegistry)
local GameConstants = require(ReplicatedStorage.Shared.GameConstants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local AbilityInput = require(script.Parent.AbilityInput)
local ViewportHelper = require(script.Parent.ViewportHelper)
local PlayerDataClient = require(script.Parent.PlayerDataClient)
local ClientSettings = require(script.Parent.ClientSettings)
local GameplayHUDSettings = require(script.Parent.GameplayHUDSettings)
local SettingsUI = require(script.Parent.SettingsUI)
local CoinDisplayClient = require(script.Parent.CoinDisplayClient)
local CoinPurchasePopup = require(script.Parent.CoinPurchasePopup)
local StarterGuiUtil = require(script.Parent.StarterGuiUtil)

export type HudController = {
	show: (heroId: string) -> (),
	hide: () -> (),
	bindCharacter: (character: Model) -> (),
	destroy: () -> (),
}

type AbilitySlot = {
	holder: Frame,
	btn: TextButton,
	nameLabel: TextLabel,
	iconImage: ImageLabel?,
	cooldownOverlay: Frame,
	cooldownLabel: TextLabel,
	abilityId: string?,
	cooldownSeconds: number?,
	suppressActiveEllipsis: boolean?,
}

local BAR_COLORS = {
	Health = Color3.fromRGB(55, 175, 85),
	EnergyScarlet = Color3.fromRGB(200, 55, 65),
	EnergyPhoton = Color3.fromRGB(255, 210, 55),
	Stamina = Color3.fromRGB(220, 185, 55),
}

local THEME_SCARLET = {
	accent = BAR_COLORS.EnergyScarlet,
	keyText = Color3.fromRGB(250, 250, 252),
	btn = Color3.fromRGB(120, 58, 68),
	btnHover = Color3.fromRGB(155, 78, 90),
	stroke = BAR_COLORS.EnergyScarlet,
	modeOn = BAR_COLORS.EnergyScarlet,
	modeOff = Color3.fromRGB(85, 40, 48),
	panel = Color3.fromRGB(36, 18, 22),
	panelTitle = BAR_COLORS.EnergyScarlet,
	barBg = Color3.fromRGB(28, 16, 20),
	viewportBg = Color3.fromRGB(22, 14, 16),
	abilityBar = Color3.fromRGB(32, 18, 22),
	energy = BAR_COLORS.EnergyScarlet,
}

local THEME_MARVEL = {
	accent = Color3.fromRGB(255, 210, 50),
	keyText = Color3.fromRGB(20, 20, 24),
	btn = Color3.fromRGB(42, 32, 8),
	btnHover = Color3.fromRGB(70, 52, 12),
	stroke = Color3.fromRGB(255, 220, 70),
	modeOn = Color3.fromRGB(255, 200, 40),
	modeOff = Color3.fromRGB(40, 32, 10),
	panel = Color3.fromRGB(28, 22, 6),
	panelTitle = Color3.fromRGB(255, 225, 110),
	barBg = Color3.fromRGB(22, 18, 6),
	viewportBg = Color3.fromRGB(16, 14, 4),
	abilityBar = Color3.fromRGB(18, 14, 4),
	energy = BAR_COLORS.EnergyPhoton,
}

local THEME_LOKI = {
	accent = Color3.fromRGB(45, 200, 95),
	keyText = Color3.fromRGB(250, 250, 252),
	btn = Color3.fromRGB(12, 36, 22),
	btnHover = Color3.fromRGB(20, 55, 32),
	stroke = Color3.fromRGB(70, 220, 120),
	modeOn = Color3.fromRGB(40, 180, 90),
	modeOff = Color3.fromRGB(14, 32, 20),
	panel = Color3.fromRGB(10, 28, 16),
	panelTitle = Color3.fromRGB(140, 240, 170),
	barBg = Color3.fromRGB(10, 22, 14),
	viewportBg = Color3.fromRGB(8, 18, 12),
	abilityBar = Color3.fromRGB(8, 16, 12),
	energy = Color3.fromRGB(55, 200, 110),
}

local THEME_DAGGER = {
	accent = Color3.fromRGB(255, 255, 255),
	keyText = Color3.fromRGB(0, 0, 0),
	btn = Color3.fromRGB(28, 28, 32),
	btnHover = Color3.fromRGB(48, 48, 54),
	stroke = Color3.fromRGB(255, 255, 255),
	modeOn = Color3.fromRGB(240, 240, 245),
	modeOff = Color3.fromRGB(32, 32, 36),
	panel = Color3.fromRGB(22, 22, 26),
	panelTitle = Color3.fromRGB(255, 255, 255),
	barBg = Color3.fromRGB(18, 18, 22),
	viewportBg = Color3.fromRGB(14, 14, 18),
	abilityBar = Color3.fromRGB(12, 12, 16),
	energy = Color3.fromRGB(255, 255, 255),
}

local THEME_JEAN_97 = {
	accent = Color3.fromRGB(65, 81, 253),
	keyText = Color3.fromRGB(250, 250, 252),
	btn = Color3.fromRGB(16, 18, 40),
	btnHover = Color3.fromRGB(28, 32, 64),
	stroke = Color3.fromRGB(90, 105, 255),
	modeOn = Color3.fromRGB(65, 81, 253),
	modeOff = Color3.fromRGB(18, 20, 42),
	panel = Color3.fromRGB(14, 16, 36),
	panelTitle = Color3.fromRGB(160, 175, 255),
	barBg = Color3.fromRGB(12, 14, 30),
	viewportBg = Color3.fromRGB(10, 12, 26),
	abilityBar = Color3.fromRGB(10, 12, 28),
	energy = Color3.fromRGB(65, 81, 253),
}

local THEME_MARVEL_GIRL = {
	accent = Color3.fromRGB(255, 90, 185),
	keyText = Color3.fromRGB(255, 236, 246),
	btn = Color3.fromRGB(52, 16, 38),
	btnHover = Color3.fromRGB(78, 24, 56),
	stroke = Color3.fromRGB(255, 120, 200),
	modeOn = Color3.fromRGB(255, 90, 185),
	modeOff = Color3.fromRGB(40, 14, 30),
	panel = Color3.fromRGB(36, 12, 28),
	panelTitle = Color3.fromRGB(255, 170, 220),
	barBg = Color3.fromRGB(28, 10, 22),
	viewportBg = Color3.fromRGB(22, 8, 18),
	abilityBar = Color3.fromRGB(30, 10, 24),
	energy = Color3.fromRGB(255, 90, 185),
}

local THEME_PHOENIX = {
	accent = Color3.fromRGB(255, 57, 17),
	keyText = Color3.fromRGB(255, 240, 228),
	btn = Color3.fromRGB(58, 14, 7),
	btnHover = Color3.fromRGB(88, 23, 10),
	stroke = Color3.fromRGB(255, 57, 17),
	modeOn = Color3.fromRGB(255, 57, 17),
	modeOff = Color3.fromRGB(48, 12, 7),
	panel = Color3.fromRGB(42, 10, 6),
	panelTitle = Color3.fromRGB(255, 57, 17),
	barBg = Color3.fromRGB(32, 8, 5),
	viewportBg = Color3.fromRGB(26, 6, 4),
	abilityBar = Color3.fromRGB(38, 8, 5),
	energy = Color3.fromRGB(255, 57, 17),
}

local THEME_ICEMAN = {
	accent = Color3.fromRGB(129, 184, 255),
	keyText = Color3.fromRGB(230, 240, 255),
	btn = Color3.fromRGB(16, 28, 44),
	btnHover = Color3.fromRGB(24, 42, 64),
	stroke = Color3.fromRGB(129, 184, 255),
	modeOn = Color3.fromRGB(129, 184, 255),
	modeOff = Color3.fromRGB(14, 24, 38),
	panel = Color3.fromRGB(12, 22, 36),
	panelTitle = Color3.fromRGB(180, 215, 255),
	barBg = Color3.fromRGB(10, 18, 30),
	viewportBg = Color3.fromRGB(8, 16, 26),
	abilityBar = Color3.fromRGB(10, 18, 30),
	energy = Color3.fromRGB(129, 184, 255),
}

local THEME_IW = {
	accent = Color3.fromRGB(77, 71, 255),
	keyText = Color3.fromRGB(236, 234, 255),
	btn = Color3.fromRGB(22, 20, 48),
	btnHover = Color3.fromRGB(36, 32, 78),
	stroke = Color3.fromRGB(77, 71, 255),
	modeOn = Color3.fromRGB(77, 71, 255),
	modeOff = Color3.fromRGB(18, 16, 40),
	panel = Color3.fromRGB(16, 14, 38),
	panelTitle = Color3.fromRGB(168, 164, 255),
	barBg = Color3.fromRGB(14, 12, 34),
	viewportBg = Color3.fromRGB(12, 10, 32),
	abilityBar = Color3.fromRGB(14, 12, 34),
	energy = Color3.fromRGB(77, 71, 255),
}

local THEME = table.clone(THEME_SCARLET)

local KEY_ORDER: { [string]: number } = {
	Q = 1,
	E = 2,
	F = 3,
	T = 4,
	R = 5,
	C = 6,
	X = 7,
	Z = 8,
	V = 9,
	G = 10,
	B = 11,
	H = 12,
}

local function addCorner(inst: GuiObject, radiusScale: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(radiusScale, 0)
	c.Parent = inst
end

local function createStatBar(parent: Frame, name: string, color: Color3, layoutOrder: number): (TextLabel, Frame)
	local row = Instance.new("Frame")
	row.Name = name .. "Row"
	row.LayoutOrder = layoutOrder
	row.Size = UDim2.new(1, 0, 0.27, 0)
	row.BackgroundTransparency = 1
	row.Parent = parent

	local track = Instance.new("Frame")
	track.Size = UDim2.fromScale(1, 1)
	track.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
	track.BorderSizePixel = 0
	track.Parent = row
	addCorner(track, 0.2)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Parent = track
	addCorner(fill, 0.2)

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Bangers
	label.Text = name .. ": 0/0"
	label.TextColor3 = Color3.fromRGB(245, 245, 248)
	label.TextScaled = true
	label.ZIndex = 2
	label.Parent = track

	local textConstraint = Instance.new("UITextSizeConstraint")
	textConstraint.MaxTextSize = 18
	textConstraint.MinTextSize = 9
	textConstraint.Parent = label

	return label, fill
end

local function createKeyBadge(parent: GuiObject, keyText: string)
	local badge = Instance.new("Frame")
	badge.Name = "KeyBadge"
	badge.AnchorPoint = Vector2.new(1, 0)
	badge.Position = UDim2.new(1, -3, 0, 2)
	badge.Size = UDim2.fromScale(0.34, 0.26)
	badge.BackgroundTransparency = 1
	badge.BorderSizePixel = 0
	badge.ZIndex = 6
	badge.Parent = parent

	local label = Instance.new("TextLabel")
	label.Name = "KeyLabel"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Bangers
	label.Text = if type(keyText) == "string" then keyText else ""
	label.TextColor3 = Color3.fromRGB(250, 250, 252)
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Right
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.ZIndex = 7
	label.Parent = badge

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1.4
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Transparency = 0.25
	stroke.Parent = label

	local textConstraint = Instance.new("UITextSizeConstraint")
	textConstraint.MaxTextSize = 14
	textConstraint.MinTextSize = 8
	textConstraint.Parent = label
end

local function createCooldownOverlay(parent: GuiObject): (Frame, TextLabel)
	local overlay = Instance.new("Frame")
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
	addCorner(overlay, 0.12)

	local cdLabel = Instance.new("TextLabel")
	cdLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	cdLabel.Position = UDim2.fromScale(0.5, 0.5)
	cdLabel.Size = UDim2.fromScale(1, 1)
	cdLabel.BackgroundTransparency = 1
	cdLabel.Font = Enum.Font.Bangers
	cdLabel.Text = ""
	cdLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	cdLabel.TextScaled = true
	cdLabel.Visible = false
	cdLabel.ZIndex = 9
	cdLabel.Parent = parent

	local textConstraint = Instance.new("UITextSizeConstraint")
	textConstraint.MaxTextSize = 18
	textConstraint.MinTextSize = 9
	textConstraint.Parent = cdLabel

	return overlay, cdLabel
end

type HairCosmeticSlot = {
	slot: Frame,
	btn: TextButton,
	stroke: UIStroke,
	nameLabel: TextLabel,
	cooldownOverlay: Frame,
	cooldownLabel: TextLabel,
}

local function createHairCosmeticSlot(
	root: Frame,
	btnColor: Color3,
	btnHover: Color3,
	strokeColor: Color3,
	showTooltip: (string, string) -> (),
	hideTooltip: () -> (),
	onClick: () -> ()
): HairCosmeticSlot
	local hairSlot = Instance.new("Frame")
	hairSlot.Name = "HairCosmeticSlot"
	hairSlot.AnchorPoint = Vector2.new(1, 0)
	hairSlot.Position = UDim2.fromScale(0.894, 0.02)
	hairSlot.Size = UDim2.fromScale(0.036, 0.064)
	hairSlot.BackgroundTransparency = 1
	hairSlot.Visible = false
	hairSlot.ZIndex = 30
	hairSlot.Parent = root

	local hairBtn = Instance.new("TextButton")
	hairBtn.Name = "HairCosmetic"
	hairBtn.AnchorPoint = Vector2.new(0.5, 1)
	hairBtn.Position = UDim2.fromScale(0.5, 1)
	hairBtn.Size = UDim2.fromScale(1, 1)
	hairBtn.BackgroundColor3 = btnColor
	hairBtn.AutoButtonColor = false
	hairBtn.Text = ""
	hairBtn.ClipsDescendants = true
	hairBtn.ZIndex = 31
	hairBtn.Parent = hairSlot
	addCorner(hairBtn, 0.12)

	local hairAspect = Instance.new("UIAspectRatioConstraint")
	hairAspect.AspectRatio = 1
	hairAspect.Parent = hairBtn

	local hairStroke = Instance.new("UIStroke")
	hairStroke.Name = "ThemeStroke"
	hairStroke.Color = strokeColor
	hairStroke.Thickness = 1
	hairStroke.Transparency = 0.35
	hairStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	hairStroke.Parent = hairBtn

	local hairName = Instance.new("TextLabel")
	hairName.Name = "AbilityName"
	hairName.AnchorPoint = Vector2.new(0.5, 0.5)
	hairName.Position = UDim2.fromScale(0.5, 0.5)
	hairName.Size = UDim2.fromScale(0.75, 0.75)
	hairName.BackgroundTransparency = 1
	hairName.Font = Enum.Font.Bangers
	hairName.Text = "Hair"
	hairName.TextColor3 = Color3.fromRGB(238, 230, 232)
	hairName.TextScaled = true
	hairName.TextWrapped = true
	hairName.TextXAlignment = Enum.TextXAlignment.Center
	hairName.TextYAlignment = Enum.TextYAlignment.Center
	hairName.ZIndex = 32
	hairName.Parent = hairBtn

	local hairNameStroke = Instance.new("UIStroke")
	hairNameStroke.Thickness = 1.2
	hairNameStroke.Color = Color3.fromRGB(0, 0, 0)
	hairNameStroke.Transparency = 0.35
	hairNameStroke.Parent = hairName

	createKeyBadge(hairBtn, "J")

	local hairCdOverlay, hairCdLabel = createCooldownOverlay(hairBtn)
	hairCdOverlay.Name = "CooldownOverlay"
	hairCdOverlay.ZIndex = 33
	hairCdLabel.Name = "CooldownLabel"
	hairCdLabel.ZIndex = 34

	hairBtn.MouseEnter:Connect(function()
		hairBtn.BackgroundColor3 = btnHover
		showTooltip("Tie Hair", "Tie hair up to focus telepathic moves and astral projection.")
	end)
	hairBtn.MouseLeave:Connect(function()
		hairBtn.BackgroundColor3 = btnColor
		hideTooltip()
	end)
	hairBtn.MouseButton1Click:Connect(onClick)

	return {
		slot = hairSlot,
		btn = hairBtn,
		stroke = hairStroke,
		nameLabel = hairName,
		cooldownOverlay = hairCdOverlay,
		cooldownLabel = hairCdLabel,
	}
end

local GameplayHUD = {}

function GameplayHUD.create(playerGui: PlayerGui): HudController
	local player = Players.LocalPlayer
	local currentHeroId: string? = nil
	local healthConn: RBXScriptConnection? = nil
	local cooldownConn: RBXScriptConnection? = nil
	local modeConnA: RBXScriptConnection? = nil
	local modeConnB: RBXScriptConnection? = nil
	local modeConnC: RBXScriptConnection? = nil
	local modeConnD: RBXScriptConnection? = nil
	local ragdollConn: RBXScriptConnection? = nil
	local boundCharacter: Model? = nil
	local abilitySlots: { AbilitySlot } = {}
	local extraSlots: { AbilitySlot } = {}
	local blastModeButtons: { [string]: TextButton } = {}
	local tkModeButtons: { [string]: TextButton } = {}
	local ultimateModeButtons: { [string]: TextButton } = {}
	local photonFlightModeButtons: { [string]: TextButton } = {}
	local tricksterModeButtons: { [string]: TextButton } = {}
	local scarletModePanels: { Frame } = {}
	local marvelModePanels: { Frame } = {}
	local lokiModePanels: { Frame } = {}
	local lokiClonePanel: Frame
	local lokiCloneButtons: { [string]: TextButton } = {}
	local refreshLokiClonePanel: () -> () = function() end
	local refreshLokiUltPanel: () -> () = function() end
	local modeConnE: RBXScriptConnection? = nil
	local areaConn: RBXScriptConnection? = nil

	local useAbility: RemoteEvent? = nil
	local function getUseAbility(): RemoteEvent
		local existing = useAbility
		if existing then
			return existing
		end
		local created = Remotes.getEvent("UseAbility")
		useAbility = created
		return created
	end

	local screenGui = StarterGuiUtil.createFreshScreenGui(playerGui, "GameplayHUD", 25)
	local useStarterGui = false

	local root: Frame
	local topCluster: Frame
	local viewportHolder: Frame
	local viewport: ViewportFrame
	local vpClick: TextButton
	local profilePanel: Frame
	local profileStroke: UIStroke
	local profileName: TextLabel
	local profileKills: TextLabel
	local profileCoins: TextLabel
	local profileClose: TextButton
	local healthLabel: TextLabel
	local healthFill: Frame
	local energyLabel: TextLabel
	local energyFill: Frame
	local staminaLabel: TextLabel
	local staminaFill: Frame
	local statusStack: Frame
	local ragdollStatus: TextButton
	local absorbStatus: TextButton
	local binaryStatus: TextButton
	local astralStatus: TextButton
	local softLockToggle: TextButton
	local shoulderLockToggle: TextButton?
	local settingsBtn: TextButton
	local settingsPanel: Frame
	local settingsStroke: UIStroke
	local settingsBtnStroke: UIStroke
	local refreshShoulderSettingsUi: () -> () = function() end
	local setDaggerAllyArming: (boolean) -> () = function(_on: boolean) end
	local refreshDaggerAlliesPanel: () -> () = function() end
	local refreshModeButtons: () -> () = function() end
	local hoveredStatus: string? = nil
	local absorbFill: Frame
	local absorbPct: TextLabel
	local buildAbsorbTooltip: () -> (string, string) = function()
		return "Absorb Bonus", ""
	end
	local buildBinaryTooltip: () -> (string, string) = function()
		return "Binary Form", ""
	end
	local buildRagdollTooltip: () -> (string, string) = function()
		return "Ragdolled", "You are ragdolled and temporarily cannot control your character."
	end
	local extraColumn: Frame
	local absorbColumn: Frame
	local modeColumn: Frame
	local lokiUltPanel: Frame
	local daggerAlliesPanel: Frame
	local bottomRow: Frame
	local abilityBar: Frame
	local restraintBar: Frame
	local restraintFill: Frame
	local restraintLabel: TextLabel
	local abilityRow: Frame
	local tooltip: Frame
	local tooltipTitle: TextLabel
	local tooltipBody: TextLabel
	local tooltipStroke: UIStroke
	local tooltipRule: Frame
	local vpStroke: UIStroke
	local abilityStroke: UIStroke
	local restraintStroke: UIStroke
	local restraintLabelStroke: UIStroke?
	local refreshSoftLockToggle: () -> () = function() end
	local hairCosmetic: HairCosmeticSlot

	if useStarterGui then
		root = StarterGuiUtil.child(screenGui, "Root", "Frame")
		root.Visible = true
		root.Size = UDim2.fromScale(1, 1)
		topCluster = StarterGuiUtil.child(root, "TopCluster", "Frame")
		topCluster.Visible = true
		viewportHolder = StarterGuiUtil.find(topCluster, "ViewportHolder", "Frame") or StarterGuiUtil.ensureFrame(topCluster, "ViewportHolder")
		viewportHolder.Visible = true
		local existingViewport = StarterGuiUtil.find(viewportHolder, "ViewportFrame", "ViewportFrame")
		if existingViewport then
			viewport = existingViewport
		else
			viewport = Instance.new("ViewportFrame")
			viewport.Name = "ViewportFrame"
			viewport.Size = UDim2.fromScale(1, 1)
			viewport.BackgroundTransparency = 1
			viewport.Parent = viewportHolder
		end
		local existingDeco = viewportHolder:FindFirstChild("HeroIconDeco")
		if existingDeco then
			existingDeco:Destroy()
		end
		local existingClick = StarterGuiUtil.find(viewportHolder, "ViewportClick", "TextButton")
		if existingClick then
			vpClick = existingClick
		else
			vpClick = Instance.new("TextButton")
			vpClick.Name = "ViewportClick"
			vpClick.Size = UDim2.fromScale(1, 1)
			vpClick.BackgroundTransparency = 1
			vpClick.Text = ""
			vpClick.Parent = viewportHolder
		end
		profilePanel = StarterGuiUtil.ensureFrame(root, "ProfilePanel")
		local existingProfileStroke = StarterGuiUtil.find(profilePanel, "ThemeStroke", "UIStroke")
		if existingProfileStroke then
			profileStroke = existingProfileStroke
		else
			profileStroke = Instance.new("UIStroke")
			profileStroke.Name = "ThemeStroke"
			profileStroke.Parent = profilePanel
		end
		local profileBody = StarterGuiUtil.find(profilePanel, "Body", "Frame") or StarterGuiUtil.ensureFrame(profilePanel, "Body")
		local profileOverlay = StarterGuiUtil.find(profilePanel, "Overlay", "Frame") or StarterGuiUtil.ensureFrame(profilePanel, "Overlay")
		profileName = StarterGuiUtil.find(profileBody, "CharacterName", "TextLabel")
			or profileBody:FindFirstChildWhichIsA("TextLabel")
			or Instance.new("TextLabel")
		if profileName.Parent ~= profileBody then
			profileName.Name = "CharacterName"
			profileName.Size = UDim2.fromScale(1, 0.2)
			profileName.BackgroundTransparency = 1
			profileName.Text = "Character"
			profileName.Parent = profileBody
		end
		profileKills = StarterGuiUtil.find(profileBody, "Kills", "TextLabel") or profileName
		local tokensLabel = StarterGuiUtil.find(profileBody, "Tokens", "TextLabel")
			or StarterGuiUtil.find(profileBody, "Coins", "TextLabel")
		profileCoins = tokensLabel or profileKills
		local existingClose = StarterGuiUtil.find(profileOverlay, "Close", "TextButton")
		if existingClose then
			profileClose = existingClose
		else
			profileClose = Instance.new("TextButton")
			profileClose.Name = "Close"
			profileClose.Size = UDim2.fromOffset(22, 22)
			profileClose.BackgroundTransparency = 1
			profileClose.Text = "X"
			profileClose.Parent = profileOverlay
		end
		local barsColumn = StarterGuiUtil.find(topCluster, "Bars", "Frame") or StarterGuiUtil.ensureFrame(topCluster, "Bars")
		barsColumn.Visible = true
		healthLabel, healthFill = StarterGuiUtil.ensureStatBar(barsColumn, "Health")
		energyLabel, energyFill = StarterGuiUtil.ensureStatBar(barsColumn, "Energy")
		staminaLabel, staminaFill = StarterGuiUtil.ensureStatBar(barsColumn, "Stamina")
		statusStack = StarterGuiUtil.ensureFrame(root, "StatusStack")
		local function ensureStatus(name: string): TextButton
			local existing = StarterGuiUtil.find(statusStack, name, "TextButton")
			if existing then
				return existing
			end
			local btn = Instance.new("TextButton")
			btn.Name = name
			btn.Visible = false
			btn.Text = ""
			btn.Parent = statusStack
			return btn
		end
		ragdollStatus = ensureStatus("RagdolledStatus")
		absorbStatus = ensureStatus("AbsorbBonusStatus")
		binaryStatus = ensureStatus("BinaryFormStatus")
		astralStatus = ensureStatus("AstralFormStatus")
		local existingSoftLock = StarterGuiUtil.find(root, "SoftLockToggle", "TextButton")
		if existingSoftLock then
			softLockToggle = existingSoftLock
		else
			softLockToggle = Instance.new("TextButton")
			softLockToggle.Name = "SoftLockToggle"
			softLockToggle.Parent = root
		end
		local existingShoulderLock = StarterGuiUtil.find(root, "ShoulderLockToggle", "TextButton")
		shoulderLockToggle = existingShoulderLock or Instance.new("TextButton")
		shoulderLockToggle.Name = "ShoulderLockToggle"
		shoulderLockToggle.Parent = root
		shoulderLockToggle.Visible = UserInputService.TouchEnabled
		shoulderLockToggle.Position = UDim2.fromScale(0.99, 0.81)
		shoulderLockToggle.Size = UDim2.fromScale(0.132, 0.06)
		shoulderLockToggle.Text = "Shoulder Off"
		topCluster.Size = UDim2.fromScale(0.152, 0.09)
		if UserInputService.TouchEnabled then
			topCluster.Position = UDim2.fromScale(0.02, 0.065)
			softLockToggle.Position = UDim2.fromScale(0.99, 0.88)
			softLockToggle.Size = UDim2.fromScale(0.132, 0.06)
		end
		local existingSettingsBtn = StarterGuiUtil.find(root, "SettingsButton", "TextButton")
		if existingSettingsBtn then
			settingsBtn = existingSettingsBtn
		else
			settingsBtn = Instance.new("TextButton")
			settingsBtn.Name = "SettingsButton"
			settingsBtn.Text = "Settings"
			settingsBtn.Parent = root
		end
		settingsPanel = StarterGuiUtil.ensureFrame(root, "SettingsPanel")
		local existingSettingsStroke = StarterGuiUtil.find(settingsPanel, "ThemeStroke", "UIStroke")
		if existingSettingsStroke then
			settingsStroke = existingSettingsStroke
		else
			settingsStroke = Instance.new("UIStroke")
			settingsStroke.Name = "ThemeStroke"
			settingsStroke.Parent = settingsPanel
		end
		local existingBtnStroke = StarterGuiUtil.find(settingsBtn, "ThemeStroke", "UIStroke")
		if existingBtnStroke then
			settingsBtnStroke = existingBtnStroke
		else
			settingsBtnStroke = Instance.new("UIStroke")
			settingsBtnStroke.Name = "ThemeStroke"
			settingsBtnStroke.Parent = settingsBtn
		end
		local settingsScroll = settingsPanel:FindFirstChild("Scroll")
		if settingsScroll and settingsScroll:IsA("ScrollingFrame") then
			refreshShoulderSettingsUi = SettingsUI.buildPanel(settingsScroll, { compact = true, showShoulderCam = true })
		else
			refreshShoulderSettingsUi = function() end
		end
		settingsBtn.MouseButton1Click:Connect(function()
			settingsPanel.Visible = not settingsPanel.Visible
			if settingsPanel.Visible then
				refreshShoulderSettingsUi()
			end
		end)
		local SoftLockClient = require(script.Parent.SoftLockClient)
		local ShoulderCamClient = require(script.Parent.ShoulderCamClient)
		local function refreshSoftLockToggle()
			local on = SoftLockClient.isEnabled()
			softLockToggle.Text = if on then "Lock On" else "Lock Off"
			softLockToggle.BackgroundColor3 = if on then Color3.fromRGB(55, 120, 70) else Color3.fromRGB(30, 30, 34)
		end
		softLockToggle.MouseButton1Click:Connect(function()
			SoftLockClient.toggle()
			refreshSoftLockToggle()
		end)
		shoulderLockToggle.MouseButton1Click:Connect(function()
			ShoulderCamClient.toggle()
			shoulderLockToggle.Text = if ShoulderCamClient.isEnabled() then "Shoulder On" else "Shoulder Off"
		end)
		refreshSoftLockToggle()
		extraColumn = StarterGuiUtil.ensureFrame(root, "ExtraAbilities")
		absorbColumn = StarterGuiUtil.ensureFrame(root, "AbsorbCharge")
		modeColumn = StarterGuiUtil.ensureFrame(root, "ModeColumn")
		lokiClonePanel = StarterGuiUtil.ensureFrame(root, "LokiClonePanel")
		lokiUltPanel = StarterGuiUtil.ensureFrame(root, "LokiUltPanel")
		daggerAlliesPanel = StarterGuiUtil.ensureFrame(root, "DaggerAlliesPanel")
		bottomRow = StarterGuiUtil.find(screenGui, "BottomRow", "Frame")
			or StarterGuiUtil.find(root, "BottomRow", "Frame")
			or StarterGuiUtil.ensureFrame(screenGui, "BottomRow")
		bottomRow.Visible = true
		abilityBar = StarterGuiUtil.find(bottomRow, "AbilityBar", "Frame") or StarterGuiUtil.ensureFrame(bottomRow, "AbilityBar")
		abilityBar.Visible = true
		restraintBar = StarterGuiUtil.find(bottomRow, "RestraintBar", "Frame") or StarterGuiUtil.ensureFrame(bottomRow, "RestraintBar")
		restraintFill = StarterGuiUtil.find(restraintBar, "Fill", "Frame") or StarterGuiUtil.ensureFrame(restraintBar, "Fill")
		local existingRestraintLabel = StarterGuiUtil.find(restraintBar, "Label", "TextLabel")
		if existingRestraintLabel then
			restraintLabel = existingRestraintLabel
			restraintLabel.Size = UDim2.fromScale(0.75, 0.75)
			restraintLabel.TextScaled = true
		else
			restraintLabel = Instance.new("TextLabel")
			restraintLabel.Name = "Label"
			restraintLabel.Size = UDim2.fromScale(0.75, 0.75)
			restraintLabel.BackgroundTransparency = 1
			restraintLabel.Font = Enum.Font.Bangers
			restraintLabel.TextScaled = true
			restraintLabel.Text = ""
			restraintLabel.Parent = restraintBar
		end
		local existingAbilityRow = StarterGuiUtil.find(abilityBar, "AbilityRow", "Frame")
		if existingAbilityRow then
			abilityRow = existingAbilityRow
		else
			abilityRow = Instance.new("Frame")
			abilityRow.Name = "AbilityRow"
			abilityRow.Size = UDim2.fromScale(1, 1)
			abilityRow.BackgroundTransparency = 1
			abilityRow.Parent = abilityBar
			local abilityLayout = Instance.new("UIListLayout")
			abilityLayout.FillDirection = Enum.FillDirection.Horizontal
			abilityLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
			abilityLayout.VerticalAlignment = Enum.VerticalAlignment.Center
			abilityLayout.SortOrder = Enum.SortOrder.LayoutOrder
			abilityLayout.Parent = abilityRow
		end
		abilityRow.Visible = true
		if not abilityRow:FindFirstChildWhichIsA("UIListLayout") then
			local rowLayout = Instance.new("UIListLayout")
			rowLayout.FillDirection = Enum.FillDirection.Horizontal
			rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
			rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
			rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
			rowLayout.Padding = UDim.new(0.012, 0)
			rowLayout.Parent = abilityRow
		end
		if not extraColumn:FindFirstChildWhichIsA("UIListLayout") then
			local extraList = Instance.new("UIListLayout")
			extraList.FillDirection = Enum.FillDirection.Vertical
			extraList.HorizontalAlignment = Enum.HorizontalAlignment.Center
			extraList.VerticalAlignment = Enum.VerticalAlignment.Center
			extraList.SortOrder = Enum.SortOrder.LayoutOrder
			extraList.Parent = extraColumn
		end
		local existingTooltip = StarterGuiUtil.find(screenGui, "AbilityTooltip", "Frame")
		if existingTooltip then
			tooltip = existingTooltip
		else
			tooltip = Instance.new("Frame")
			tooltip.Name = "AbilityTooltip"
			tooltip.Visible = false
			tooltip.Parent = screenGui
		end
		tooltipTitle = tooltip:FindFirstChildWhichIsA("TextLabel") :: TextLabel
		if not tooltipTitle then
			tooltipTitle = Instance.new("TextLabel")
			tooltipTitle.BackgroundTransparency = 1
			tooltipTitle.Text = ""
			tooltipTitle.Parent = tooltip
		end
		tooltipBody = tooltipTitle
		for _, child in tooltip:GetChildren() do
			if child:IsA("TextLabel") and child ~= tooltipTitle then
				tooltipBody = child
				break
			end
		end
		local hairSlot = root:FindFirstChild("HairCosmeticSlot")
		if hairSlot and hairSlot:IsA("Frame") then
			local hairBtn = hairSlot:FindFirstChild("HairCosmetic")
			local hairName = if hairBtn then hairBtn:FindFirstChild("AbilityName") else nil
			local hairOverlay = if hairBtn then hairBtn:FindFirstChild("CooldownOverlay") else nil
			local hairCdLabel = if hairBtn then hairBtn:FindFirstChild("CooldownLabel") else nil
			if hairBtn and hairBtn:IsA("TextButton") and hairName and hairOverlay and hairCdLabel then
				hairCosmetic = {
					slot = hairSlot,
					btn = hairBtn,
					nameLabel = hairName :: TextLabel,
					cooldownOverlay = hairOverlay :: Frame,
					cooldownLabel = hairCdLabel :: TextLabel,
				}
			else
				hairCosmetic = createHairCosmeticSlot(root)
			end
		else
			hairCosmetic = createHairCosmeticSlot(root)
		end
		pcall(function()
			local existingToken = root:FindFirstChild("TokenDisplay") or root:FindFirstChild("CoinDisplay")
			if existingToken and existingToken:IsA("Frame") then
				local existingPopup = root:FindFirstChild("CoinPurchasePopup")
					or screenGui:FindFirstChild("CoinPurchasePopup")
				local coinPopup = if existingPopup and existingPopup:IsA("Frame")
					then CoinPurchasePopup.bind(existingPopup)
					else CoinPurchasePopup.create(root, 35)
				CoinDisplayClient.bind(existingToken, {
					onPlusClick = function(anchor)
						coinPopup.toggle(anchor)
					end,
				})
			else
				local coinPopup = CoinPurchasePopup.create(root, 35)
				local coinDisplay = CoinDisplayClient.create(root, {
					zIndex = 30,
					onPlusClick = function(anchor)
						coinPopup.toggle(anchor)
					end,
				})
				coinDisplay.setAnchor(Vector2.new(1, 0), UDim2.fromScale(0.99, 0.008), UDim2.fromScale(0.079, 0.024))
			end
		end)
		local function setProfileOpen(open: boolean)
			profilePanel.Visible = open
			if open then
				local heroId = currentHeroId
				local entry = if heroId then CharacterRegistry.getById(heroId) else nil
				profileName.Text = if entry then entry.displayName else "Character"
				profileKills.Text = string.format("Kills: %d", PlayerDataClient.getKills())
				profileCoins.Text = string.format("Tokens: %d", PlayerDataClient.getCoins())
			end
		end
		vpClick.MouseButton1Click:Connect(function()
			setProfileOpen(not profilePanel.Visible)
		end)
		profileClose.MouseButton1Click:Connect(function()
			setProfileOpen(false)
		end)
		screenGui.Enabled = false
	else
	-- Safe margins from topbar inset, expressed as scale of the viewport
	local function applySafePadding(pad: UIPadding)
		local function refresh()
			local cam = workspace.CurrentCamera
			local vs = if cam then cam.ViewportSize else Vector2.new(1920, 1080)
			if vs.X < 1 or vs.Y < 1 then
				return
			end
			local inset = GuiService:GetGuiInset()
			pad.PaddingLeft = UDim.new(math.clamp(inset.X / vs.X, 0, 0.08), 0)
			pad.PaddingTop = UDim.new(math.clamp(inset.Y / vs.Y, 0, 0.12), 0)
			pad.PaddingRight = UDim.new(math.clamp(inset.X / vs.X, 0, 0.08), 0)
			pad.PaddingBottom = UDim.new(math.clamp(inset.Y / vs.Y, 0, 0.08), 0)
		end
		task.defer(refresh)
		local cam = workspace.CurrentCamera
		if cam then
			cam:GetPropertyChangedSignal("ViewportSize"):Connect(refresh)
		end
	end

	root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Parent = screenGui

	local rootPad = Instance.new("UIPadding")
	rootPad.Parent = root
	applySafePadding(rootPad)

	-- Top-left: viewport + stat bars
	topCluster = Instance.new("Frame")
	topCluster.Name = "TopCluster"
	topCluster.AnchorPoint = Vector2.new(0, 0)
	topCluster.Position = if UserInputService.TouchEnabled
		then UDim2.fromScale(0.02, 0.065)
		else UDim2.fromScale(0.02, 0.012)
	topCluster.Size = UDim2.fromScale(0.152, 0.09)
	topCluster.BackgroundTransparency = 1
	topCluster.Parent = root

	local topLayout = Instance.new("UIListLayout")
	topLayout.FillDirection = Enum.FillDirection.Horizontal
	topLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	topLayout.SortOrder = Enum.SortOrder.LayoutOrder
	topLayout.Padding = UDim.new(0.025, 0)
	topLayout.Parent = topCluster

	viewportHolder = Instance.new("Frame")
	viewportHolder.Name = "ViewportHolder"
	viewportHolder.LayoutOrder = 1
	viewportHolder.Size = UDim2.fromScale(0, 1)
	viewportHolder.BackgroundColor3 = Color3.fromRGB(18, 12, 14)
	viewportHolder.BorderSizePixel = 0
	viewportHolder.Parent = topCluster
	addCorner(viewportHolder, 0.1)

	local vpAspect = Instance.new("UIAspectRatioConstraint")
	vpAspect.AspectRatio = 1
	vpAspect.AspectType = Enum.AspectType.ScaleWithParentSize
	vpAspect.DominantAxis = Enum.DominantAxis.Height
	vpAspect.Parent = viewportHolder

	vpStroke = Instance.new("UIStroke")
	vpStroke.Color = THEME.stroke
	vpStroke.Thickness = 1
	vpStroke.Transparency = 0.35
	vpStroke.Parent = viewportHolder

	viewport = Instance.new("ViewportFrame")
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.BackgroundColor3 = Color3.fromRGB(14, 10, 12)
	viewport.BackgroundTransparency = 0
	viewport.BorderSizePixel = 0
	viewport.Parent = viewportHolder

	vpClick = Instance.new("TextButton")
	vpClick.Name = "ViewportClick"
	vpClick.Size = UDim2.fromScale(1, 1)
	vpClick.BackgroundTransparency = 1
	vpClick.Text = ""
	vpClick.ZIndex = 6
	vpClick.AutoButtonColor = false
	vpClick.Parent = viewportHolder

	profilePanel = Instance.new("Frame")
	profilePanel.Name = "ProfilePanel"
	profilePanel.AnchorPoint = Vector2.new(0, 0)
	profilePanel.Position = UDim2.fromScale(0.02, 0.19)
	profilePanel.Size = UDim2.fromScale(0.18, 0.36)
	profilePanel.BackgroundColor3 = THEME.panel
	profilePanel.BorderSizePixel = 0
	profilePanel.Visible = false
	profilePanel.ZIndex = 25
	profilePanel.Parent = root
	addCorner(profilePanel, 0.04)

	profileStroke = Instance.new("UIStroke")
	profileStroke.Name = "ThemeStroke"
	profileStroke.Color = THEME.stroke
	profileStroke.Thickness = 1.2
	profileStroke.Transparency = 0.28
	profileStroke.Parent = profilePanel

	local profilePad = Instance.new("UIPadding")
	profilePad.PaddingTop = UDim.new(0.04, 0)
	profilePad.PaddingBottom = UDim.new(0.04, 0)
	profilePad.PaddingLeft = UDim.new(0.06, 0)
	profilePad.PaddingRight = UDim.new(0.06, 0)
	profilePad.Parent = profilePanel

	local profileBody = Instance.new("Frame")
	profileBody.Name = "Body"
	profileBody.Size = UDim2.fromScale(1, 1)
	profileBody.BackgroundTransparency = 1
	profileBody.ZIndex = 26
	profileBody.Parent = profilePanel

	local profileLayout = Instance.new("UIListLayout")
	profileLayout.FillDirection = Enum.FillDirection.Vertical
	profileLayout.SortOrder = Enum.SortOrder.LayoutOrder
	profileLayout.Padding = UDim.new(0.02, 0)
	profileLayout.Parent = profileBody

	local function profileText(name: string, text: string, order: number, sizeY: number, font: Enum.Font, maxSize: number): TextLabel
		local label = Instance.new("TextLabel")
		label.Name = name
		label.LayoutOrder = order
		label.Size = UDim2.new(1, 0, sizeY, 0)
		label.BackgroundTransparency = 1
		label.Font = font
		label.Text = text
		label.TextColor3 = Color3.fromRGB(240, 236, 232)
		label.TextScaled = true
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextYAlignment = Enum.TextYAlignment.Center
		label.ZIndex = 26
		label.Parent = profileBody
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 1.1
		stroke.Color = Color3.fromRGB(0, 0, 0)
		stroke.Transparency = 0.4
		stroke.Parent = label
		local constraint = Instance.new("UITextSizeConstraint")
		constraint.MaxTextSize = maxSize
		constraint.MinTextSize = 10
		constraint.Parent = label
		return label
	end

	profileName = profileText("CharacterName", "Character", 1, 0.12, Enum.Font.Bangers, 22)
	profileKills = profileText("Kills", "Kills: 0", 2, 0.08, Enum.Font.GothamBold, 16)
	profileCoins = profileText("Tokens", "Tokens: 0", 3, 0.08, Enum.Font.GothamBold, 16)
	profileText("QuestsTitle", "Quests", 4, 0.08, Enum.Font.Bangers, 18)
	local questA = profileText("QuestA", "Daily  Win a match  0/1", 5, 0.1, Enum.Font.Gotham, 14)
	local questB = profileText("QuestB", "Daily  Deal 500 damage  0/500", 6, 0.1, Enum.Font.Gotham, 14)
	local questC = profileText("QuestC", "Weekly  Play 10 games  0/10", 7, 0.1, Enum.Font.Gotham, 14)
	profileText("Hint", "Earn 100 tokens per kill (200 with Elite Gamepass).", 8, 0.1, Enum.Font.Gotham, 12)
	questA.TextColor3 = Color3.fromRGB(210, 210, 214)
	questB.TextColor3 = Color3.fromRGB(210, 210, 214)
	questC.TextColor3 = Color3.fromRGB(210, 210, 214)

	local profileOverlay = Instance.new("Frame")
	profileOverlay.Name = "Overlay"
	profileOverlay.Size = UDim2.fromScale(1, 1)
	profileOverlay.BackgroundTransparency = 1
	profileOverlay.ZIndex = 27
	profileOverlay.Parent = profilePanel

	profileClose = Instance.new("TextButton")
	profileClose.Name = "Close"
	profileClose.AnchorPoint = Vector2.new(1, 0)
	profileClose.Position = UDim2.new(1, -8, 0, 6)
	profileClose.Size = UDim2.fromOffset(22, 22)
	profileClose.BackgroundTransparency = 1
	profileClose.Font = Enum.Font.GothamBold
	profileClose.Text = "X"
	profileClose.TextColor3 = Color3.fromRGB(230, 230, 232)
	profileClose.TextScaled = true
	profileClose.ZIndex = 28
	profileClose.Parent = profileOverlay

	local function setProfileOpen(open: boolean)
		profilePanel.Visible = open
		if open then
			local heroId = currentHeroId
			local entry = if heroId then CharacterRegistry.getById(heroId) else nil
			profileName.Text = if entry then entry.displayName else "Character"
			profileKills.Text = string.format("Kills: %d", PlayerDataClient.getKills())
			profileCoins.Text = string.format("Tokens: %d", PlayerDataClient.getCoins())
		end
	end

	vpClick.MouseButton1Click:Connect(function()
		setProfileOpen(not profilePanel.Visible)
	end)
	profileClose.MouseButton1Click:Connect(function()
		setProfileOpen(false)
	end)

	local barsColumn = Instance.new("Frame")
	barsColumn.Name = "Bars"
	barsColumn.LayoutOrder = 2
	barsColumn.Size = UDim2.fromScale(0.72, 1)
	barsColumn.BackgroundTransparency = 1
	barsColumn.Parent = topCluster

	local barsLayout = Instance.new("UIListLayout")
	barsLayout.FillDirection = Enum.FillDirection.Vertical
	barsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	barsLayout.Padding = UDim.new(0.06, 0)
	barsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	barsLayout.Parent = barsColumn

	healthLabel, healthFill = createStatBar(barsColumn, "Health", BAR_COLORS.Health, 1)
	energyLabel, energyFill = createStatBar(barsColumn, "Energy", THEME.energy, 2)
	staminaLabel, staminaFill = createStatBar(barsColumn, "Stamina", BAR_COLORS.Stamina, 3)

	-- Bottom-right status chips (square icons)
	statusStack = Instance.new("Frame")
	statusStack.Name = "StatusStack"
	statusStack.AnchorPoint = Vector2.new(1, 1)
	statusStack.Position = UDim2.fromScale(0.99, 0.86)
	statusStack.Size = UDim2.fromScale(0.15, 0.075)
	statusStack.BackgroundTransparency = 1
	statusStack.Parent = root

	local statusList = Instance.new("UIListLayout")
	statusList.FillDirection = Enum.FillDirection.Horizontal
	statusList.HorizontalAlignment = Enum.HorizontalAlignment.Right
	statusList.VerticalAlignment = Enum.VerticalAlignment.Bottom
	statusList.SortOrder = Enum.SortOrder.LayoutOrder
	statusList.Padding = UDim.new(0.05, 0)
	statusList.Parent = statusStack

	local function makeStatusChip(
		name: string,
		layoutOrder: number,
		bg: Color3,
		strokeColor: Color3,
		text: string,
		textColor: Color3
	): TextButton
		local chip = Instance.new("TextButton")
		chip.Name = name
		chip.LayoutOrder = layoutOrder
		chip.Size = UDim2.fromScale(0.38, 1)
		chip.BackgroundColor3 = bg
		chip.BackgroundTransparency = 0.08
		chip.BorderSizePixel = 0
		chip.AutoButtonColor = false
		chip.Font = Enum.Font.Bangers
		chip.Text = text
		chip.TextColor3 = textColor
		chip.TextScaled = true
		chip.Visible = false
		chip.Parent = statusStack
		addCorner(chip, 0.22)

		local aspect = Instance.new("UIAspectRatioConstraint")
		aspect.AspectRatio = 1
		aspect.Parent = chip

		local stroke = Instance.new("UIStroke")
		stroke.Color = strokeColor
		stroke.Thickness = 1.5
		stroke.Transparency = 0.22
		stroke.Parent = chip

		local constraint = Instance.new("UITextSizeConstraint")
		constraint.MaxTextSize = 22
		constraint.MinTextSize = 8
		constraint.Parent = chip

		return chip
	end

	ragdollStatus = makeStatusChip(
		"RagdolledStatus",
		3,
		Color3.fromRGB(72, 32, 96),
		Color3.fromRGB(200, 130, 255),
		"RAG",
		Color3.fromRGB(235, 210, 255)
	)

	absorbStatus = makeStatusChip(
		"AbsorbBonusStatus",
		0,
		Color3.fromRGB(255, 200, 50),
		Color3.fromRGB(255, 230, 120),
		"+",
		Color3.fromRGB(30, 22, 4)
	)

	binaryStatus = makeStatusChip(
		"BinaryFormStatus",
		1,
		Color3.fromRGB(70, 140, 255),
		Color3.fromRGB(160, 210, 255),
		"BIN",
		Color3.fromRGB(245, 250, 255)
	)

	astralStatus = makeStatusChip(
		"AstralFormStatus",
		2,
		Color3.fromRGB(40, 48, 120),
		Color3.fromRGB(120, 140, 255),
		"30s",
		Color3.fromRGB(230, 235, 255)
	)

	buildAbsorbTooltip = function(): (string, string)
		if not boundCharacter then
			return "Absorb Bonus", ""
		end
		local charge = boundCharacter:GetAttribute(GameConstants.ABSORB_CHARGE_ATTRIBUTE)
		if type(charge) ~= "number" then
			charge = 0
		end
		local ratio = math.clamp(charge / GameConstants.ABSORB_CHARGE_MAX, 0, 1)
		local mult = 1 + ratio * (GameConstants.CM_ABSORB_OUTGOING_MULT_MAX - 1)
		local bonusPct = math.floor((mult - 1) * 100 + 0.5)
		local binaryOn = boundCharacter:GetAttribute(GameConstants.BINARY_ACTIVE_ATTRIBUTE) == true
		return "Absorb Bonus", string.format(
			"Extra damage from absorbed energy.\nCharge: %d%%\nDamage: %.2fx (+%d%%)\nMax bonus: +50%% (1.50x)\nBinary Form: absorb fills %dx faster\nDecays over time; abilities spend charge.",
			math.floor(ratio * 100 + 0.5),
			mult,
			bonusPct,
			if binaryOn then GameConstants.BINARY_ABSORB_GAIN_MULT else 1
		)
	end

	local function buildBinaryTooltip(): (string, string)
		if not boundCharacter then
			return "Binary Form", ""
		end
		local untilTime = boundCharacter:GetAttribute(GameConstants.BINARY_UNTIL_ATTRIBUTE)
		local left = 0
		if type(untilTime) == "number" then
			left = math.max(0, untilTime - AbilityCooldownHelper.getNow())
		end
		return "Binary Form", string.format(
			"Binary Form active.\nDamage: %.1fx\nEnergy cost: %.1fx\nAbsorb fill: %dx faster\nTime left: %.1fs\nMax duration: %ds",
			GameConstants.BINARY_DAMAGE_MULT,
			GameConstants.BINARY_ENERGY_MULT,
			GameConstants.BINARY_ABSORB_GAIN_MULT,
			left,
			GameConstants.BINARY_DURATION
		)
	end

	buildRagdollTooltip = function(): (string, string)
		return "Ragdolled", "You are ragdolled and temporarily cannot control your character."
	end

	-- Soft lock toggle (bottom-right)
	softLockToggle = Instance.new("TextButton")
	softLockToggle.Name = "SoftLockToggle"
	softLockToggle.AnchorPoint = Vector2.new(1, 1)
	softLockToggle.Position = UDim2.fromScale(0.99, 0.97)
	softLockToggle.Size = UDim2.fromScale(0.06, 0.03)
	softLockToggle.BackgroundColor3 = Color3.fromRGB(30, 30, 34)
	softLockToggle.BackgroundTransparency = 0.2
	softLockToggle.BorderSizePixel = 0
	softLockToggle.AutoButtonColor = true
	softLockToggle.Font = Enum.Font.Bangers
	softLockToggle.Text = "Lock Off"
	softLockToggle.TextColor3 = Color3.fromRGB(230, 230, 235)
	softLockToggle.TextScaled = true
	softLockToggle.Parent = root
	if UserInputService.TouchEnabled then
		softLockToggle.Size = UDim2.fromScale(0.132, 0.06)
		softLockToggle.Position = UDim2.fromScale(0.99, 0.88)
	end

	local softLockConstraint = Instance.new("UITextSizeConstraint")
	softLockConstraint.MaxTextSize = 16
	softLockConstraint.MinTextSize = 8
	softLockConstraint.Parent = softLockToggle

	shoulderLockToggle = Instance.new("TextButton")
	shoulderLockToggle.Name = "ShoulderLockToggle"
	shoulderLockToggle.AnchorPoint = Vector2.new(1, 1)
	shoulderLockToggle.Position = UDim2.fromScale(0.99, 0.81)
	shoulderLockToggle.Size = UDim2.fromScale(0.132, 0.06)
	shoulderLockToggle.BackgroundColor3 = Color3.fromRGB(30, 30, 34)
	shoulderLockToggle.BackgroundTransparency = 0.2
	shoulderLockToggle.BorderSizePixel = 0
	shoulderLockToggle.AutoButtonColor = true
	shoulderLockToggle.Font = Enum.Font.Bangers
	shoulderLockToggle.Text = "Shoulder Off"
	shoulderLockToggle.TextColor3 = Color3.fromRGB(230, 230, 235)
	shoulderLockToggle.TextScaled = true
	shoulderLockToggle.Visible = UserInputService.TouchEnabled
	shoulderLockToggle.Parent = root
	local shoulderLockConstraint = Instance.new("UITextSizeConstraint")
	shoulderLockConstraint.MaxTextSize = 16
	shoulderLockConstraint.MinTextSize = 8
	shoulderLockConstraint.Parent = shoulderLockToggle

	local SoftLockClient = require(script.Parent.SoftLockClient)
	local ShoulderCamClient = require(script.Parent.ShoulderCamClient)
	refreshSoftLockToggle = function()
		local on = SoftLockClient.isEnabled()
		softLockToggle.Text = if on then "Lock On" else "Lock Off"
		softLockToggle.BackgroundColor3 = if on then Color3.fromRGB(55, 120, 70) else Color3.fromRGB(30, 30, 34)
	end
	softLockToggle.MouseButton1Click:Connect(function()
		SoftLockClient.toggle()
		refreshSoftLockToggle()
	end)
	shoulderLockToggle.MouseButton1Click:Connect(function()
		ShoulderCamClient.toggle()
		shoulderLockToggle.Text = if ShoulderCamClient.isEnabled() then "Shoulder On" else "Shoulder Off"
	end)
	refreshSoftLockToggle()

	local hudSettings = GameplayHUDSettings.build(root, THEME)
	settingsBtn = hudSettings.settingsBtn
	settingsPanel = hudSettings.settingsPanel
	settingsStroke = hudSettings.settingsStroke
	settingsBtnStroke = hudSettings.settingsBtnStroke
	refreshShoulderSettingsUi = hudSettings.refreshShoulderSettingsUi

	local coinPopup = CoinPurchasePopup.create(root, 35)
	local coinDisplay = CoinDisplayClient.create(root, {
		zIndex = 30,
		onPlusClick = function(anchor)
			coinPopup.toggle(anchor)
		end,
	})
	coinDisplay.setAnchor(Vector2.new(1, 0), UDim2.fromScale(0.99, 0.008), UDim2.fromScale(0.079, 0.024))

	-- Extra abilities (vertical) — scale relative to root
	extraColumn = Instance.new("Frame")
	extraColumn.Name = "ExtraAbilities"
	extraColumn.AnchorPoint = Vector2.new(0, 0.5)
	extraColumn.Position = UDim2.fromScale(0, 0.5)
	extraColumn.Size = UDim2.fromScale(0.075, 0.4)
	extraColumn.BackgroundTransparency = 1
	extraColumn.Visible = false
	extraColumn.Parent = root

	local extraList = Instance.new("UIListLayout")
	extraList.FillDirection = Enum.FillDirection.Vertical
	extraList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	extraList.VerticalAlignment = Enum.VerticalAlignment.Center
	extraList.SortOrder = Enum.SortOrder.LayoutOrder
	extraList.Padding = UDim.new(0.02, 0)
	extraList.Parent = extraColumn

	-- Captain Marvel absorb charge (vertical, right side)
	absorbColumn = Instance.new("Frame")
	absorbColumn.Name = "AbsorbCharge"
	absorbColumn.AnchorPoint = Vector2.new(1, 0.5)
	absorbColumn.Position = UDim2.fromScale(0.985, 0.5)
	absorbColumn.Size = UDim2.fromScale(0.021, 0.315)
	absorbColumn.BackgroundTransparency = 1
	absorbColumn.Visible = false
	absorbColumn.Parent = root

	local absorbTitle = Instance.new("TextLabel")
	absorbTitle.Name = "Title"
	absorbTitle.AnchorPoint = Vector2.new(0.5, 1)
	absorbTitle.Position = UDim2.fromScale(0.5, -0.02)
	absorbTitle.Size = UDim2.fromScale(2.2, 0.1)
	absorbTitle.BackgroundTransparency = 1
	absorbTitle.Font = Enum.Font.Bangers
	absorbTitle.Text = "ABSORB"
	absorbTitle.TextColor3 = Color3.fromRGB(255, 220, 90)
	absorbTitle.TextScaled = true
	absorbTitle.Parent = absorbColumn

	local absorbTitleConstraint = Instance.new("UITextSizeConstraint")
	absorbTitleConstraint.MaxTextSize = 12
	absorbTitleConstraint.MinTextSize = 8
	absorbTitleConstraint.Parent = absorbTitle

	local absorbTrack = Instance.new("Frame")
	absorbTrack.Name = "Track"
	absorbTrack.Size = UDim2.fromScale(1, 1)
	absorbTrack.BackgroundColor3 = Color3.fromRGB(28, 22, 8)
	absorbTrack.BackgroundTransparency = 0.15
	absorbTrack.BorderSizePixel = 0
	absorbTrack.Parent = absorbColumn
	addCorner(absorbTrack, 0.25)

	local absorbStroke = Instance.new("UIStroke")
	absorbStroke.Color = Color3.fromRGB(255, 210, 70)
	absorbStroke.Thickness = 1
	absorbStroke.Transparency = 0.35
	absorbStroke.Parent = absorbTrack

	absorbFill = Instance.new("Frame")
	absorbFill.Name = "Fill"
	absorbFill.AnchorPoint = Vector2.new(0, 1)
	absorbFill.Position = UDim2.fromScale(0, 1)
	absorbFill.Size = UDim2.fromScale(1, 0)
	absorbFill.BackgroundColor3 = Color3.fromRGB(255, 210, 55)
	absorbFill.BorderSizePixel = 0
	absorbFill.Parent = absorbTrack
	addCorner(absorbFill, 0.25)

	absorbPct = Instance.new("TextLabel")
	absorbPct.Name = "Pct"
	absorbPct.AnchorPoint = Vector2.new(0.5, 0)
	absorbPct.Position = UDim2.fromScale(0.5, 1.02)
	absorbPct.Size = UDim2.fromScale(2.4, 0.1)
	absorbPct.BackgroundTransparency = 1
	absorbPct.Font = Enum.Font.Bangers
	absorbPct.Text = "0%"
	absorbPct.TextColor3 = Color3.fromRGB(255, 230, 140)
	absorbPct.TextScaled = true
	absorbPct.Parent = absorbColumn

	local absorbPctConstraint = Instance.new("UITextSizeConstraint")
	absorbPctConstraint.MaxTextSize = 12
	absorbPctConstraint.MinTextSize = 8
	absorbPctConstraint.Parent = absorbPct

	-- Mode panels — bottom-left, three panels side-by-side (matches reference layout)
	modeColumn = Instance.new("Frame")
	modeColumn.Name = "ModeColumn"
	modeColumn.AnchorPoint = Vector2.new(0, 0)
	modeColumn.Position = UDim2.fromScale(0, 0.95)
	modeColumn.Size = UDim2.fromScale(0.24, 0.105)
	modeColumn.BackgroundTransparency = 1
	modeColumn.Visible = false
	modeColumn.Parent = root

	local modeList = Instance.new("UIListLayout")
	modeList.FillDirection = Enum.FillDirection.Horizontal
	modeList.HorizontalAlignment = Enum.HorizontalAlignment.Left
	modeList.VerticalAlignment = Enum.VerticalAlignment.Bottom
	modeList.SortOrder = Enum.SortOrder.LayoutOrder
	modeList.Padding = UDim.new(0.02, 0)
	modeList.Parent = modeColumn

	local function makeModePanel(
		title: string,
		abilityId: string,
		modes: { string },
		layoutOrder: number,
		buttonMap: { [string]: TextButton }
	)
		local panel = Instance.new("Frame")
		panel.Name = abilityId .. "ModePanel"
		panel.LayoutOrder = layoutOrder
		panel.Size = UDim2.fromScale(0.32, 1)
		panel.BackgroundColor3 = THEME.panel
		panel.BackgroundTransparency = 0.12
		panel.BorderSizePixel = 0
		panel.Parent = modeColumn
		addCorner(panel, 0.08)

		local stroke = Instance.new("UIStroke")
		stroke.Name = "ThemeStroke"
		stroke.Color = THEME.stroke
		stroke.Transparency = 0.4
		stroke.Parent = panel

		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0.06, 0)
		pad.PaddingBottom = UDim.new(0.06, 0)
		pad.PaddingLeft = UDim.new(0.05, 0)
		pad.PaddingRight = UDim.new(0.05, 0)
		pad.Parent = panel

		local list = Instance.new("UIListLayout")
		list.FillDirection = Enum.FillDirection.Vertical
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Padding = UDim.new(0.05, 0)
		list.Parent = panel

		local titleLabel = Instance.new("TextLabel")
		titleLabel.Name = "Title"
		titleLabel.Size = UDim2.new(1, 0, 0.26, 0)
		titleLabel.BackgroundTransparency = 1
		titleLabel.Font = Enum.Font.Bangers
		titleLabel.Text = title
		titleLabel.TextColor3 = THEME.panelTitle
		titleLabel.TextScaled = true
		titleLabel.TextXAlignment = Enum.TextXAlignment.Left
		titleLabel.LayoutOrder = 0
		titleLabel.Parent = panel

		local titleConstraint = Instance.new("UITextSizeConstraint")
		titleConstraint.MaxTextSize = 11
		titleConstraint.MinTextSize = 7
		titleConstraint.Parent = titleLabel

		local btnRow = Instance.new("Frame")
		btnRow.LayoutOrder = 1
		btnRow.Size = UDim2.new(1, 0, 0.64, 0)
		btnRow.BackgroundTransparency = 1
		btnRow.Parent = panel

		local btnLayout = Instance.new("UIListLayout")
		btnLayout.FillDirection = Enum.FillDirection.Horizontal
		btnLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
		btnLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		btnLayout.SortOrder = Enum.SortOrder.LayoutOrder
		btnLayout.Padding = UDim.new(0.04, 0)
		btnLayout.Parent = btnRow

		local btnWidth = 1 / math.max(#modes, 1)
		for i, modeName in modes do
			local btn = Instance.new("TextButton")
			btn.Name = modeName
			btn.LayoutOrder = i
			btn.Size = UDim2.new(btnWidth - 0.03, 0, 1, 0)
			btn.BackgroundColor3 = THEME.modeOff
			btn.AutoButtonColor = false
			btn.Font = Enum.Font.Bangers
			btn.Text = modeName
			btn.TextColor3 = Color3.fromRGB(245, 230, 232)
			btn.TextScaled = true
			btn.Parent = btnRow
			addCorner(btn, 0.18)
			buttonMap[modeName] = btn

			local btnConstraint = Instance.new("UITextSizeConstraint")
			btnConstraint.MaxTextSize = 10
			btnConstraint.MinTextSize = 6
			btnConstraint.Parent = btn

			btn.MouseButton1Click:Connect(function()
				getUseAbility():FireServer({
					action = "SetMode",
					abilityId = abilityId,
					mode = modeName,
				})
				if boundCharacter then
					if abilityId == "hex_blast" then
						boundCharacter:SetAttribute(GameConstants.HEX_BLAST_MODE_ATTRIBUTE, modeName)
					elseif abilityId == "telekinesis" then
						boundCharacter:SetAttribute(GameConstants.TK_MODE_ATTRIBUTE, modeName)
					elseif abilityId == "ultimate" then
						boundCharacter:SetAttribute(GameConstants.ULTIMATE_MODE_ATTRIBUTE, modeName)
					elseif abilityId == "photon_flight" then
						boundCharacter:SetAttribute(GameConstants.PHOTON_FLIGHT_MODE_ATTRIBUTE, modeName)
					elseif abilityId == "trickster_dash" then
						boundCharacter:SetAttribute(GameConstants.LOKI_DASH_MODE_ATTRIBUTE, modeName)
					end
				end
				refreshModeButtons()
			end)
		end

		return panel
	end

	refreshModeButtons = function()
		local blastMode = if boundCharacter then boundCharacter:GetAttribute(GameConstants.HEX_BLAST_MODE_ATTRIBUTE) else "Single"
		local tkMode = if boundCharacter then boundCharacter:GetAttribute(GameConstants.TK_MODE_ATTRIBUTE) else "Single"
		local ultMode = if boundCharacter then boundCharacter:GetAttribute(GameConstants.ULTIMATE_MODE_ATTRIBUTE) else "Disintegration"
		local flightMode = if boundCharacter then boundCharacter:GetAttribute(GameConstants.PHOTON_FLIGHT_MODE_ATTRIBUTE) else "Normal"
		local dashMode = if boundCharacter then boundCharacter:GetAttribute(GameConstants.LOKI_DASH_MODE_ATTRIBUTE) else "Dash"
		if blastMode ~= "Barrage" then
			blastMode = "Single"
		end
		if tkMode ~= "Multiple" and tkMode ~= "Torture" then
			tkMode = "Single"
		end
		if ultMode ~= "Absorption" then
			ultMode = "Disintegration"
		end
		if flightMode ~= "Accelerated" then
			flightMode = "Normal"
		end
		if dashMode ~= "Teleport" then
			dashMode = "Dash"
		end
		for name, btn in blastModeButtons do
			btn.BackgroundColor3 = if name == blastMode then THEME.modeOn else THEME.modeOff
		end
		for name, btn in tkModeButtons do
			btn.BackgroundColor3 = if name == tkMode then THEME.modeOn else THEME.modeOff
		end
		for name, btn in ultimateModeButtons do
			btn.BackgroundColor3 = if name == ultMode then THEME.modeOn else THEME.modeOff
		end
		for name, btn in photonFlightModeButtons do
			btn.BackgroundColor3 = if name == flightMode then THEME.modeOn else THEME.modeOff
		end
		for name, btn in tricksterModeButtons do
			btn.BackgroundColor3 = if name == dashMode then THEME.modeOn else THEME.modeOff
		end
		local function applySlotIcon(slot: AbilitySlot, mode: string?)
			if not slot.iconImage or not slot.abilityId or not currentHeroId then
				return
			end
			local def = CharacterRegistry.getAbilityById(currentHeroId, slot.abilityId)
			if not def then
				return
			end
			local icon = CharacterRegistry.resolveAbilityIcon(def, mode)
			if icon then
				slot.iconImage.Image = icon
			end
		end
		for _, slot in abilitySlots do
			if slot.abilityId == "hex_blast" then
				slot.cooldownSeconds = if blastMode == "Barrage"
					then GameConstants.HEX_BLAST_BARRAGE_COOLDOWN
					else GameConstants.HEX_BLAST_SINGLE_COOLDOWN
				applySlotIcon(slot, blastMode)
			elseif slot.abilityId == "telekinesis" then
				applySlotIcon(slot, "Single")
			elseif slot.abilityId == "trickster_dash" then
				applySlotIcon(slot, dashMode)
			end
		end
	end

	table.insert(scarletModePanels, makeModePanel("Hex Blast", "hex_blast", { "Single", "Barrage" }, 1, blastModeButtons))
	table.insert(scarletModePanels, makeModePanel("Ultimate", "ultimate", { "Absorption", "Disintegration" }, 2, ultimateModeButtons))
	table.insert(marvelModePanels, makeModePanel("Photon Flight", "photon_flight", { "Normal", "Accelerated" }, 1, photonFlightModeButtons))
	table.insert(lokiModePanels, makeModePanel("Trickster Move", "trickster_dash", { "Dash", "Teleport" }, 1, tricksterModeButtons))
	-- Loki decoy controls (right side, only while clone alive)
	lokiClonePanel = Instance.new("Frame")
	lokiClonePanel.Name = "LokiClonePanel"
	lokiClonePanel.AnchorPoint = Vector2.new(1, 0.5)
	lokiClonePanel.Position = UDim2.fromScale(0.99, 0.42)
	lokiClonePanel.Size = UDim2.fromScale(0.098, 0.225)
	lokiClonePanel.BackgroundColor3 = THEME.panel
	lokiClonePanel.BackgroundTransparency = 0.12
	lokiClonePanel.BorderSizePixel = 0
	lokiClonePanel.Visible = false
	lokiClonePanel.Parent = root
	addCorner(lokiClonePanel, 0.1)

	local lokiCloneStroke = Instance.new("UIStroke")
	lokiCloneStroke.Name = "ThemeStroke"
	lokiCloneStroke.Color = THEME.stroke
	lokiCloneStroke.Thickness = 1
	lokiCloneStroke.Transparency = 0.35
	lokiCloneStroke.Parent = lokiClonePanel

	local lokiClonePad = Instance.new("UIPadding")
	lokiClonePad.PaddingTop = UDim.new(0.04, 0)
	lokiClonePad.PaddingBottom = UDim.new(0.04, 0)
	lokiClonePad.PaddingLeft = UDim.new(0.08, 0)
	lokiClonePad.PaddingRight = UDim.new(0.08, 0)
	lokiClonePad.Parent = lokiClonePanel

	local lokiCloneLayout = Instance.new("UIListLayout")
	lokiCloneLayout.FillDirection = Enum.FillDirection.Vertical
	lokiCloneLayout.SortOrder = Enum.SortOrder.LayoutOrder
	lokiCloneLayout.Padding = UDim.new(0.03, 0)
	lokiCloneLayout.Parent = lokiClonePanel

	local lokiCloneTitle = Instance.new("TextLabel")
	lokiCloneTitle.Name = "Title"
	lokiCloneTitle.LayoutOrder = 0
	lokiCloneTitle.Size = UDim2.new(1, 0, 0.14, 0)
	lokiCloneTitle.BackgroundTransparency = 1
	lokiCloneTitle.Font = Enum.Font.Bangers
	lokiCloneTitle.Text = "Clone"
	lokiCloneTitle.TextColor3 = THEME.panelTitle
	lokiCloneTitle.TextScaled = true
	lokiCloneTitle.Parent = lokiClonePanel

	for i, modeName in { "Punch", "Run", "Detonate", "Lie of Place" } do
		local btn = Instance.new("TextButton")
		btn.Name = modeName
		btn.LayoutOrder = i
		btn.Size = UDim2.new(1, 0, 0.18, 0)
		btn.BackgroundColor3 = THEME.modeOff
		btn.AutoButtonColor = false
		btn.Font = Enum.Font.Bangers
		btn.Text = string.format("[%d] %s", i, modeName)
		btn.TextColor3 = Color3.fromRGB(230, 255, 235)
		btn.TextScaled = true
		btn.Parent = lokiClonePanel
		addCorner(btn, 0.18)
		lokiCloneButtons[modeName] = btn
		btn.MouseButton1Click:Connect(function()
			getUseAbility():FireServer({
				action = "SetMode",
				abilityId = "illusion_decoy",
				mode = modeName,
			})
			if boundCharacter then
				boundCharacter:SetAttribute(GameConstants.LOKI_CLONE_MODE_ATTRIBUTE, modeName)
			end
			refreshLokiClonePanel()
		end)
	end

	refreshLokiClonePanel = function()
		local show = currentHeroId == "loki"
			and boundCharacter ~= nil
			and boundCharacter:GetAttribute(GameConstants.LOKI_CLONE_ACTIVE_ATTRIBUTE) == true
		lokiClonePanel.Visible = show
		if not show then
			return
		end
		local mode = boundCharacter:GetAttribute(GameConstants.LOKI_CLONE_MODE_ATTRIBUTE)
		if mode ~= "Run" and mode ~= "Detonate" and mode ~= "Lie of Place" then
			mode = "Punch"
		end
		for name, btn in lokiCloneButtons do
			btn.BackgroundColor3 = if name == mode then THEME.modeOn else THEME.modeOff
		end
	end

	-- Loki ult clone attack toggle (separate panel below decoy)
	lokiUltPanel = Instance.new("Frame")
	lokiUltPanel.Name = "LokiUltPanel"
	lokiUltPanel.AnchorPoint = Vector2.new(1, 0.5)
	lokiUltPanel.Position = UDim2.fromScale(0.99, 0.72)
	lokiUltPanel.Size = UDim2.fromScale(0.098, 0.12)
	lokiUltPanel.BackgroundColor3 = THEME.panel
	lokiUltPanel.BackgroundTransparency = 0.12
	lokiUltPanel.BorderSizePixel = 0
	lokiUltPanel.Visible = false
	lokiUltPanel.Parent = root
	addCorner(lokiUltPanel, 0.1)

	local lokiUltStroke = Instance.new("UIStroke")
	lokiUltStroke.Name = "ThemeStroke"
	lokiUltStroke.Color = THEME.stroke
	lokiUltStroke.Thickness = 1
	lokiUltStroke.Transparency = 0.35
	lokiUltStroke.Parent = lokiUltPanel

	local lokiUltPad = Instance.new("UIPadding")
	lokiUltPad.PaddingTop = UDim.new(0.06, 0)
	lokiUltPad.PaddingBottom = UDim.new(0.06, 0)
	lokiUltPad.PaddingLeft = UDim.new(0.08, 0)
	lokiUltPad.PaddingRight = UDim.new(0.08, 0)
	lokiUltPad.Parent = lokiUltPanel

	local lokiUltLayout = Instance.new("UIListLayout")
	lokiUltLayout.FillDirection = Enum.FillDirection.Vertical
	lokiUltLayout.SortOrder = Enum.SortOrder.LayoutOrder
	lokiUltLayout.Padding = UDim.new(0.05, 0)
	lokiUltLayout.Parent = lokiUltPanel

	local lokiUltTitle = Instance.new("TextLabel")
	lokiUltTitle.Name = "Title"
	lokiUltTitle.LayoutOrder = 0
	lokiUltTitle.Size = UDim2.new(1, 0, 0.28, 0)
	lokiUltTitle.BackgroundTransparency = 1
	lokiUltTitle.Font = Enum.Font.Bangers
	lokiUltTitle.Text = "Mischief"
	lokiUltTitle.TextColor3 = THEME.panelTitle
	lokiUltTitle.TextScaled = true
	lokiUltTitle.Parent = lokiUltPanel

	local lokiUltButtons: { [string]: TextButton } = {}
	for i, modeName in { "Attack", "Idle" } do
		local btn = Instance.new("TextButton")
		btn.Name = modeName
		btn.LayoutOrder = i
		btn.Size = UDim2.new(1, 0, 0.3, 0)
		btn.BackgroundColor3 = THEME.modeOff
		btn.AutoButtonColor = false
		btn.Font = Enum.Font.Bangers
		btn.Text = string.format("[%d] %s", i, modeName)
		btn.TextColor3 = Color3.fromRGB(230, 255, 235)
		btn.TextScaled = true
		btn.Parent = lokiUltPanel
		addCorner(btn, 0.18)
		lokiUltButtons[modeName] = btn
		btn.MouseButton1Click:Connect(function()
			getUseAbility():FireServer({
				action = "SetMode",
				abilityId = "god_of_mischief",
				mode = modeName,
			})
			if boundCharacter then
				boundCharacter:SetAttribute(
					GameConstants.LOKI_ULT_ATTACK_ATTRIBUTE,
					if modeName == "Attack" then true else false
				)
			end
			refreshLokiUltPanel()
		end)
	end

	refreshLokiUltPanel = function()
		local show = currentHeroId == "loki"
			and boundCharacter ~= nil
			and boundCharacter:GetAttribute(GameConstants.LOKI_ULT_ACTIVE_ATTRIBUTE) == true
		lokiUltPanel.Visible = show
		if not show then
			return
		end
		local attackOn = boundCharacter:GetAttribute(GameConstants.LOKI_ULT_ATTACK_ATTRIBUTE)
		local mode = if attackOn == false then "Idle" else "Attack"
		for name, btn in lokiUltButtons do
			btn.BackgroundColor3 = if name == mode then THEME.modeOn else THEME.modeOff
		end
	end

	-- Dagger allies list (bottom-left): click Add Ally, then Mouse1 a target
	local daggerAllies: { { key: string, name: string } } = {}
	local daggerAllyArming = false

	daggerAlliesPanel = Instance.new("Frame")
	daggerAlliesPanel.Name = "DaggerAlliesPanel"
	daggerAlliesPanel.AnchorPoint = Vector2.new(0, 1)
	daggerAlliesPanel.Position = UDim2.fromScale(0.012, 0.975)
	daggerAlliesPanel.Size = UDim2.fromScale(0.135, 0.195)
	daggerAlliesPanel.BackgroundColor3 = THEME.panel
	daggerAlliesPanel.BackgroundTransparency = 0.1
	daggerAlliesPanel.BorderSizePixel = 0
	daggerAlliesPanel.Visible = false
	daggerAlliesPanel.ZIndex = 20
	daggerAlliesPanel.Parent = root
	addCorner(daggerAlliesPanel, 0.08)

	local daggerAlliesStroke = Instance.new("UIStroke")
	daggerAlliesStroke.Name = "ThemeStroke"
	daggerAlliesStroke.Color = THEME.stroke
	daggerAlliesStroke.Thickness = 1
	daggerAlliesStroke.Transparency = 0.3
	daggerAlliesStroke.Parent = daggerAlliesPanel

	local daggerAlliesPad = Instance.new("UIPadding")
	daggerAlliesPad.PaddingTop = UDim.new(0.04, 0)
	daggerAlliesPad.PaddingBottom = UDim.new(0.04, 0)
	daggerAlliesPad.PaddingLeft = UDim.new(0.05, 0)
	daggerAlliesPad.PaddingRight = UDim.new(0.05, 0)
	daggerAlliesPad.Parent = daggerAlliesPanel

	local daggerAlliesLayout = Instance.new("UIListLayout")
	daggerAlliesLayout.FillDirection = Enum.FillDirection.Vertical
	daggerAlliesLayout.SortOrder = Enum.SortOrder.LayoutOrder
	daggerAlliesLayout.Padding = UDim.new(0.02, 0)
	daggerAlliesLayout.Parent = daggerAlliesPanel

	local daggerAlliesTitle = Instance.new("TextLabel")
	daggerAlliesTitle.Name = "Title"
	daggerAlliesTitle.LayoutOrder = 0
	daggerAlliesTitle.Size = UDim2.new(1, 0, 0.12, 0)
	daggerAlliesTitle.BackgroundTransparency = 1
	daggerAlliesTitle.Font = Enum.Font.Bangers
	daggerAlliesTitle.Text = "Allies"
	daggerAlliesTitle.TextColor3 = THEME.panelTitle
	daggerAlliesTitle.TextScaled = true
	daggerAlliesTitle.TextXAlignment = Enum.TextXAlignment.Left
	daggerAlliesTitle.Parent = daggerAlliesPanel

	local daggerAddBtn = Instance.new("TextButton")
	daggerAddBtn.Name = "AddAlly"
	daggerAddBtn.LayoutOrder = 1
	daggerAddBtn.Size = UDim2.new(1, 0, 0.12, 0)
	daggerAddBtn.BackgroundColor3 = THEME.modeOn
	daggerAddBtn.BorderSizePixel = 0
	daggerAddBtn.AutoButtonColor = true
	daggerAddBtn.Font = Enum.Font.Bangers
	daggerAddBtn.Text = "Add Ally"
			daggerAddBtn.TextColor3 = Color3.fromRGB(20, 20, 24)
	daggerAddBtn.TextScaled = true
	daggerAddBtn.Parent = daggerAlliesPanel
	addCorner(daggerAddBtn, 0.2)

	local daggerListScroll = Instance.new("ScrollingFrame")
	daggerListScroll.Name = "List"
	daggerListScroll.LayoutOrder = 2
	daggerListScroll.Size = UDim2.new(1, 0, 0.7, 0)
	daggerListScroll.BackgroundColor3 = Color3.fromRGB(16, 16, 20)
	daggerListScroll.BackgroundTransparency = 0.25
	daggerListScroll.BorderSizePixel = 0
	daggerListScroll.ScrollBarThickness = 4
	daggerListScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	daggerListScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	daggerListScroll.Parent = daggerAlliesPanel
	addCorner(daggerListScroll, 0.08)

	local daggerListLayout = Instance.new("UIListLayout")
	daggerListLayout.FillDirection = Enum.FillDirection.Vertical
	daggerListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	daggerListLayout.Padding = UDim.new(0, 4)
	daggerListLayout.Parent = daggerListScroll

	local daggerListPad = Instance.new("UIPadding")
	daggerListPad.PaddingTop = UDim.new(0, 4)
	daggerListPad.PaddingBottom = UDim.new(0, 4)
	daggerListPad.PaddingLeft = UDim.new(0, 4)
	daggerListPad.PaddingRight = UDim.new(0, 4)
	daggerListPad.Parent = daggerListScroll

	local function clearDaggerAllyRows()
		for _, child in daggerListScroll:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
	end

	refreshDaggerAlliesPanel = function()
		local show = currentHeroId == "dagger"
		daggerAlliesPanel.Visible = show
		if not show then
			return
		end
		clearDaggerAllyRows()
		for i, entry in daggerAllies do
			local row = Instance.new("Frame")
			row.Name = "Ally_" .. entry.key
			row.LayoutOrder = i
			row.Size = UDim2.new(1, 0, 0, 28)
			row.BackgroundColor3 = THEME.modeOff
			row.BorderSizePixel = 0
			row.Parent = daggerListScroll
			addCorner(row, 0.15)

			local nameLbl = Instance.new("TextLabel")
			nameLbl.Size = UDim2.new(0.72, 0, 1, 0)
			nameLbl.Position = UDim2.fromScale(0.02, 0)
			nameLbl.BackgroundTransparency = 1
			nameLbl.Font = Enum.Font.Bangers
			nameLbl.Text = entry.name
			nameLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
			nameLbl.TextScaled = true
			nameLbl.TextXAlignment = Enum.TextXAlignment.Left
			nameLbl.Parent = row

			local removeBtn = Instance.new("TextButton")
			removeBtn.Name = "Remove"
			removeBtn.AnchorPoint = Vector2.new(1, 0.5)
			removeBtn.Position = UDim2.fromScale(0.98, 0.5)
			removeBtn.Size = UDim2.fromScale(0.24, 0.78)
			removeBtn.BackgroundColor3 = Color3.fromRGB(140, 50, 50)
			removeBtn.BorderSizePixel = 0
			removeBtn.Font = Enum.Font.Bangers
			removeBtn.Text = "X"
			removeBtn.TextColor3 = Color3.fromRGB(255, 230, 230)
			removeBtn.TextScaled = true
			removeBtn.Parent = row
			addCorner(removeBtn, 0.2)
			removeBtn.MouseButton1Click:Connect(function()
				getUseAbility():FireServer({
					action = "AllyRemove",
					key = entry.key,
				})
			end)
		end
	end

	local daggerIgnoreClickUntil = 0

	setDaggerAllyArming = function(on: boolean)
		daggerAllyArming = on
		if on then
			daggerAddBtn.Text = "Click Target…"
			daggerAddBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			daggerAddBtn.TextColor3 = Color3.fromRGB(20, 20, 24)
			daggerIgnoreClickUntil = os.clock() + 0.25
		else
			daggerAddBtn.Text = "Add Ally"
			daggerAddBtn.BackgroundColor3 = THEME.modeOn
			daggerAddBtn.TextColor3 = Color3.fromRGB(20, 20, 24)
		end
	end

	daggerAddBtn.MouseButton1Click:Connect(function()
		if currentHeroId ~= "dagger" then
			return
		end
		setDaggerAllyArming(not daggerAllyArming)
	end)

	UserInputService.InputBegan:Connect(function(input, _gameProcessed)
		if not daggerAllyArming or currentHeroId ~= "dagger" then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		if os.clock() < daggerIgnoreClickUntil then
			return
		end
		local MouseHelper = require(script.Parent.MouseHelper)
		local SoftLockClient = require(script.Parent.SoftLockClient)
		local target = SoftLockClient.getLockedTarget() or MouseHelper.getHoveredCharacter(player, 90)
		setDaggerAllyArming(false)
		if not target or target == boundCharacter then
			return
		end
		getUseAbility():FireServer({
			action = "AllyAdd",
			target = target,
			direction = MouseHelper.getWorldDirection(player),
			aimPoint = MouseHelper.getHitPosition(player, 200),
		})
	end)

	Remotes.getEvent("DaggerAllies").OnClientEvent:Connect(function(list: any)
		daggerAllies = {}
		if type(list) == "table" then
			for _, item in list do
				if type(item) == "table" and type(item.key) == "string" and type(item.name) == "string" then
					table.insert(daggerAllies, { key = item.key, name = item.name })
				end
			end
		end
		refreshDaggerAlliesPanel()
	end)

	-- BottomRow hosts the ability bar (centered at bottom)
	bottomRow = Instance.new("Frame")
	bottomRow.Name = "BottomRow"
	bottomRow.AnchorPoint = Vector2.new(0.5, 1)
	bottomRow.Position = UDim2.new(0.5, 0, 1, 0)
	bottomRow.Size = UDim2.fromScale(0.48, 0.18)
	bottomRow.BackgroundTransparency = 1
	bottomRow.Parent = screenGui

	abilityBar = Instance.new("Frame")
	abilityBar.Name = "AbilityBar"
	abilityBar.AnchorPoint = Vector2.new(0.5, 0.5)
	abilityBar.Position = UDim2.fromScale(0.5, 0.5)
	abilityBar.Size = UDim2.fromScale(1, 1)
	abilityBar.BackgroundColor3 = THEME.abilityBar
	abilityBar.BackgroundTransparency = 0.12
	abilityBar.BorderSizePixel = 0
	abilityBar.ClipsDescendants = false
	abilityBar.Parent = bottomRow
	addCorner(abilityBar, 0.1)

	abilityStroke = Instance.new("UIStroke")
	abilityStroke.Name = "ThemeStroke"
	abilityStroke.Color = THEME.stroke
	abilityStroke.Thickness = 1
	abilityStroke.Transparency = 0.4
	abilityStroke.Parent = abilityBar

	local abilityPadding = Instance.new("UIPadding")
	abilityPadding.PaddingTop = UDim.new(0.06, 0)
	abilityPadding.PaddingBottom = UDim.new(0.06, 0)
	abilityPadding.PaddingLeft = UDim.new(0.02, 0)
	abilityPadding.PaddingRight = UDim.new(0.02, 0)
	abilityPadding.Parent = abilityBar

	restraintBar = Instance.new("Frame")
	restraintBar.Name = "RestraintBar"
	restraintBar.AnchorPoint = Vector2.new(0.5, 1)
	restraintBar.Position = UDim2.new(0.5, 0, 0, -18)
	restraintBar.Size = UDim2.fromScale(0.42, 0.26)
	restraintBar.BackgroundColor3 = Color3.fromRGB(10, 12, 26)
	restraintBar.BackgroundTransparency = 0.08
	restraintBar.BorderSizePixel = 0
	restraintBar.Visible = false
	restraintBar.ZIndex = 8
	restraintBar.Parent = bottomRow
	addCorner(restraintBar, 0.22)

	restraintStroke = Instance.new("UIStroke")
	restraintStroke.Color = Color3.fromRGB(90, 105, 255)
	restraintStroke.Thickness = 1.2
	restraintStroke.Transparency = 0.35
	restraintStroke.Parent = restraintBar

	restraintFill = Instance.new("Frame")
	restraintFill.Name = "Fill"
	restraintFill.Size = UDim2.fromScale(0, 1)
	restraintFill.BackgroundColor3 = GameConstants.MG_PSI_COLOR
	restraintFill.BorderSizePixel = 0
	restraintFill.Parent = restraintBar
	addCorner(restraintFill, 0.22)

	restraintLabel = Instance.new("TextLabel")
	restraintLabel.Name = "Label"
	restraintLabel.Size = UDim2.fromScale(0.75, 0.75)
	restraintLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	restraintLabel.Position = UDim2.fromScale(0.5, 0.5)
	restraintLabel.BackgroundTransparency = 1
	restraintLabel.Font = Enum.Font.Bangers
	restraintLabel.Text = "Strain"
	restraintLabel.TextColor3 = Color3.fromRGB(230, 235, 255)
	restraintLabel.TextScaled = true
	restraintLabel.ZIndex = 9
	restraintLabel.Parent = restraintBar

	restraintLabelStroke = Instance.new("UIStroke")
	restraintLabelStroke.Name = "LabelStroke"
	restraintLabelStroke.Color = Color3.fromRGB(18, 10, 12)
	restraintLabelStroke.Thickness = 1.4
	restraintLabelStroke.Transparency = 1
	restraintLabelStroke.Parent = restraintLabel

	local restraintTextConstraint = Instance.new("UITextSizeConstraint")
	restraintTextConstraint.MaxTextSize = 12
	restraintTextConstraint.MinTextSize = 9
	restraintTextConstraint.Parent = restraintLabel

	abilityRow = Instance.new("Frame")
	abilityRow.Size = UDim2.fromScale(1, 1)
	abilityRow.BackgroundTransparency = 1
	abilityRow.ClipsDescendants = false
	abilityRow.Parent = abilityBar

	local abilityLayout = Instance.new("UIListLayout")
	abilityLayout.FillDirection = Enum.FillDirection.Horizontal
	abilityLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	abilityLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	abilityLayout.SortOrder = Enum.SortOrder.LayoutOrder
	abilityLayout.Padding = UDim.new(0.012, 0)
	abilityLayout.Parent = abilityRow

	tooltip = Instance.new("Frame")
	tooltip.Name = "AbilityTooltip"
	tooltip.Size = UDim2.fromOffset(320, 0)
	tooltip.AutomaticSize = Enum.AutomaticSize.Y
	tooltip.BackgroundColor3 = THEME.panel
	tooltip.BackgroundTransparency = 0.04
	tooltip.BorderSizePixel = 0
	tooltip.Visible = false
	tooltip.ZIndex = 50
	tooltip.Parent = screenGui

	local tooltipCorner = Instance.new("UICorner")
	tooltipCorner.CornerRadius = UDim.new(0, 12)
	tooltipCorner.Parent = tooltip

	tooltipStroke = Instance.new("UIStroke")
	tooltipStroke.Name = "ThemeStroke"
	tooltipStroke.Color = THEME.stroke
	tooltipStroke.Thickness = 1.4
	tooltipStroke.Transparency = 0.28
	tooltipStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	tooltipStroke.Parent = tooltip

	local tooltipPadding = Instance.new("UIPadding")
	tooltipPadding.PaddingTop = UDim.new(0, 16)
	tooltipPadding.PaddingBottom = UDim.new(0, 16)
	tooltipPadding.PaddingLeft = UDim.new(0, 18)
	tooltipPadding.PaddingRight = UDim.new(0, 18)
	tooltipPadding.Parent = tooltip

	local tooltipList = Instance.new("UIListLayout")
	tooltipList.FillDirection = Enum.FillDirection.Vertical
	tooltipList.SortOrder = Enum.SortOrder.LayoutOrder
	tooltipList.Padding = UDim.new(0, 10)
	tooltipList.Parent = tooltip

	tooltipTitle = Instance.new("TextLabel")
	tooltipTitle.Size = UDim2.new(1, 0, 0, 0)
	tooltipTitle.AutomaticSize = Enum.AutomaticSize.Y
	tooltipTitle.BackgroundTransparency = 1
	tooltipTitle.Font = Enum.Font.Bangers
	tooltipTitle.TextColor3 = Color3.fromRGB(245, 245, 250)
	tooltipTitle.TextScaled = false
	tooltipTitle.TextSize = 20
	tooltipTitle.TextWrapped = true
	tooltipTitle.TextXAlignment = Enum.TextXAlignment.Left
	tooltipTitle.LayoutOrder = 1
	tooltipTitle.ZIndex = 51
	tooltipTitle.Parent = tooltip

	local tooltipTitleStroke = Instance.new("UIStroke")
	tooltipTitleStroke.Thickness = 1.1
	tooltipTitleStroke.Color = Color3.fromRGB(0, 0, 0)
	tooltipTitleStroke.Transparency = 0.45
	tooltipTitleStroke.Parent = tooltipTitle

	tooltipRule = Instance.new("Frame")
	tooltipRule.Name = "Rule"
	tooltipRule.Size = UDim2.new(1, 0, 0, 1)
	tooltipRule.BackgroundColor3 = THEME.stroke
	tooltipRule.BackgroundTransparency = 0.45
	tooltipRule.BorderSizePixel = 0
	tooltipRule.LayoutOrder = 2
	tooltipRule.ZIndex = 51
	tooltipRule.Parent = tooltip

	tooltipBody = Instance.new("TextLabel")
	tooltipBody.Size = UDim2.new(1, 0, 0, 0)
	tooltipBody.AutomaticSize = Enum.AutomaticSize.Y
	tooltipBody.BackgroundTransparency = 1
	tooltipBody.Font = Enum.Font.Gotham
	tooltipBody.TextColor3 = Color3.fromRGB(198, 198, 210)
	tooltipBody.TextScaled = false
	tooltipBody.TextSize = 14
	tooltipBody.LineHeight = 1.15
	tooltipBody.TextWrapped = true
	tooltipBody.TextXAlignment = Enum.TextXAlignment.Left
	tooltipBody.LayoutOrder = 3
	tooltipBody.ZIndex = 51
	tooltipBody.Parent = tooltip
	end

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
			-- Keep status tooltips live while hovered
			if hoveredStatus == "absorb" then
				local title, body = buildAbsorbTooltip()
				tooltipTitle.Text = title
				tooltipBody.Text = body
			elseif hoveredStatus == "binary" then
				local title, body = buildBinaryTooltip()
				tooltipTitle.Text = title
				tooltipBody.Text = body
			elseif hoveredStatus == "ragdoll" then
				local title, body = buildRagdollTooltip()
				tooltipTitle.Text = title
				tooltipBody.Text = body
			end
			local mouse = player:GetMouse()
			local cam = workspace.CurrentCamera
			local vs = if cam then cam.ViewportSize else Vector2.new(1920, 1080)
			tooltip.Position = UDim2.fromScale(
				math.clamp((mouse.X + 18) / vs.X, 0, 0.8),
				math.clamp((mouse.Y + 18) / vs.Y, 0, 0.8)
			)
		end)
	end

	local function clearSlots(slots: { AbilitySlot })
		for _, slot in slots do
			if slot.holder.Parent then
				slot.holder:Destroy()
			elseif slot.btn.Parent then
				slot.btn:Destroy()
			end
		end
		table.clear(slots)
	end

	local function createAbilityButton(
		parent: Frame,
		name: string,
		displayName: string,
		description: string,
		key: string,
		layoutOrder: number,
		abilityId: string?,
		cooldownSeconds: number?,
		size: UDim2?,
		suppressActiveEllipsis: boolean?,
		_iconAsset: string?
	): AbilitySlot
		-- Name lives inside the button; keybind sits on the top-right corner
		local holder = Instance.new("Frame")
		holder.Name = name .. "Slot"
		holder.LayoutOrder = layoutOrder
		holder.Size = size or UDim2.fromScale(0.118, 0.92)
		holder.BackgroundTransparency = 1
		holder.BorderSizePixel = 0
		holder.ClipsDescendants = false
		holder.Parent = parent

		local btn = Instance.new("TextButton")
		btn.Name = name
		btn.AnchorPoint = Vector2.new(0.5, 0.5)
		btn.Position = UDim2.fromScale(0.5, 0.5)
		btn.Size = UDim2.fromScale(1, 1)
		btn.BackgroundColor3 = THEME.btn
		btn.AutoButtonColor = false
		btn.Text = ""
		btn.ClipsDescendants = true
		btn.ZIndex = 2
		btn.Parent = holder
		addCorner(btn, 0.12)

		local aspect = Instance.new("UIAspectRatioConstraint")
		aspect.AspectRatio = 1
		aspect.Parent = btn

		local stroke = Instance.new("UIStroke")
		stroke.Color = THEME.stroke
		stroke.Thickness = 1
		stroke.Transparency = 0.35
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = btn

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "AbilityName"
		nameLabel.AnchorPoint = Vector2.new(0.5, 0.5)
		nameLabel.Position = UDim2.fromScale(0.5, 0.5)
		nameLabel.Size = UDim2.fromScale(0.75, 0.75)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = Enum.Font.Bangers
		nameLabel.Text = displayName
		nameLabel.TextColor3 = Color3.fromRGB(238, 230, 232)
		nameLabel.TextScaled = true
		nameLabel.TextWrapped = true
		nameLabel.TextXAlignment = Enum.TextXAlignment.Center
		nameLabel.TextYAlignment = Enum.TextYAlignment.Center
		nameLabel.ZIndex = 3
		nameLabel.Parent = btn
		nameLabel:SetAttribute("AbilityNameLabel", true)

		local nameStroke = Instance.new("UIStroke")
		nameStroke.Thickness = 1.2
		nameStroke.Color = Color3.fromRGB(0, 0, 0)
		nameStroke.Transparency = 0.35
		nameStroke.Parent = nameLabel

		if type(key) == "string" and key ~= "" then
			createKeyBadge(btn, key)
		end

		local cooldownOverlay, cooldownLabel = createCooldownOverlay(btn)

		btn.MouseEnter:Connect(function()
			btn.BackgroundColor3 = THEME.btnHover
			showTooltip(displayName, description)
		end)
		btn.MouseLeave:Connect(function()
			btn.BackgroundColor3 = THEME.btn
			hideTooltip()
		end)

		return {
			holder = holder,
			btn = btn,
			nameLabel = nameLabel,
			iconImage = nil,
			cooldownOverlay = cooldownOverlay,
			cooldownLabel = cooldownLabel,
			abilityId = abilityId,
			cooldownSeconds = cooldownSeconds,
			suppressActiveEllipsis = suppressActiveEllipsis == true,
		}
	end

	if not useStarterGui then
		hairCosmetic = createHairCosmeticSlot(
			root,
			THEME.btn,
			THEME.btnHover,
			THEME.stroke,
			showTooltip,
			hideTooltip,
			function()
				AbilityInput.triggerFromHud("J")
			end
		)
	elseif hairCosmetic.btn then
		hairCosmetic.btn.MouseButton1Click:Connect(function()
			AbilityInput.triggerFromHud("J")
		end)
		hairCosmetic.btn.MouseEnter:Connect(function()
			hairCosmetic.btn.BackgroundColor3 = THEME.btnHover
			showTooltip("Hair", "Toggle Jean Grey hair style.")
		end)
		hairCosmetic.btn.MouseLeave:Connect(function()
			hairCosmetic.btn.BackgroundColor3 = THEME.btn
			hideTooltip()
		end)
	end

	local function refreshHairSlot()
		local char = boundCharacter
		local look = if char then char:GetAttribute(GameConstants.LOOK_MODE_ATTRIBUTE) else nil
		hairCosmetic.slot.Visible = currentHeroId == "jean_grey" and look ~= "marvel_girl"
	end

	local function updateSlotCooldowns(slots: { AbilitySlot })
		local character = boundCharacter
		if not character or not character.Parent then
			return
		end
		for _, slot in slots do
			if not slot.abilityId or not slot.cooldownSeconds then
				slot.cooldownOverlay.Visible = false
				slot.cooldownLabel.Visible = false
				continue
			end
			local remaining = AbilityCooldownHelper.getRemaining(character, slot.abilityId)
			local active = AbilityCooldownHelper.isActive(character, slot.abilityId)
			local hairLocked = currentHeroId == "jean_grey"
				and character:GetAttribute(GameConstants.LOOK_MODE_ATTRIBUTE) ~= "marvel_girl"
				and character:GetAttribute(GameConstants.MG_HAIR_TIED_ATTRIBUTE) ~= true
				and (
					slot.abilityId == "mind_link"
					or slot.abilityId == "astral_projection"
				)
			local controlLocked = currentHeroId == "scarlet_witch"
				and character:GetAttribute(GameConstants.SW_CONTROL_LOCK_ATTRIBUTE) == true
			local teleportAiming = character:GetAttribute(GameConstants.TELEPORT_AIMING_ATTRIBUTE) == true
				and (slot.abilityId == "teleportation" or slot.abilityId == "trickster_dash" or slot.abilityId == "hex_displacement")
			if remaining > 0 then
				slot.cooldownOverlay.BackgroundTransparency = 0.15
				slot.cooldownOverlay.Visible = true
				slot.cooldownOverlay.Size = UDim2.fromScale(1, math.clamp(remaining / slot.cooldownSeconds, 0, 1))
				slot.cooldownLabel.Visible = true
				slot.cooldownLabel.Text = string.format("%.1f", remaining)
				slot.nameLabel.TextTransparency = 0
			elseif controlLocked then
				local untilTime = character:GetAttribute(GameConstants.SW_CONTROL_LOCK_UNTIL_ATTRIBUTE)
				local lockLeft = 0
				if type(untilTime) == "number" then
					lockLeft = math.max(0, untilTime - AbilityCooldownHelper.getNow())
				end
				slot.cooldownOverlay.BackgroundTransparency = 0.18
				slot.cooldownOverlay.Visible = true
				slot.cooldownOverlay.Size = UDim2.fromScale(1, 1)
				slot.btn.BackgroundColor3 = Color3.fromRGB(42, 36, 40)
				slot.nameLabel.TextTransparency = 0.5
				if lockLeft > 0.05 then
					slot.cooldownLabel.Visible = true
					slot.cooldownLabel.Text = string.format("%.1f", lockLeft)
				else
					slot.cooldownLabel.Visible = false
				end
			elseif hairLocked then
				slot.cooldownOverlay.BackgroundTransparency = 0.22
				slot.cooldownOverlay.Visible = true
				slot.cooldownOverlay.Size = UDim2.fromScale(1, 1)
				slot.cooldownLabel.Visible = false
				slot.btn.BackgroundColor3 = Color3.fromRGB(38, 38, 44)
				slot.nameLabel.TextTransparency = 0.45
			elseif teleportAiming then
				-- Aim-select: stronger dark fill (distinct from casting …)
				slot.cooldownOverlay.BackgroundTransparency = 0.28
				slot.cooldownOverlay.Visible = true
				slot.cooldownOverlay.Size = UDim2.fromScale(1, 1)
				slot.cooldownLabel.Visible = false
			elseif active then
				slot.cooldownOverlay.BackgroundTransparency = 0.18
				slot.cooldownOverlay.Visible = true
				slot.cooldownOverlay.Size = UDim2.fromScale(1, 1)
				slot.cooldownLabel.Visible = false
				slot.btn.BackgroundColor3 = Color3.fromRGB(42, 36, 40)
				slot.nameLabel.TextTransparency = 0.5
			else
				slot.cooldownOverlay.BackgroundTransparency = 0.15
				slot.cooldownOverlay.Visible = false
				slot.cooldownLabel.Visible = false
				slot.nameLabel.TextTransparency = 0
				slot.btn.BackgroundColor3 = THEME.btn
			end
		end
	end

	local function applyTheme(heroId: string)
		local src = THEME_SCARLET
		local character = boundCharacter
		if heroId == "captain_marvel" then
			src = THEME_MARVEL
		elseif heroId == "loki" then
			src = THEME_LOKI
		elseif heroId == "dagger" then
			src = THEME_DAGGER
		elseif heroId == "jean_grey" then
			local skinId = if character then character:GetAttribute(GameConstants.LOOK_MODE_ATTRIBUTE) else nil
			src = if skinId == "phoenix"
				then THEME_PHOENIX
				else (if skinId == "marvel_girl" then THEME_MARVEL_GIRL else THEME_JEAN_97)
		elseif heroId == "iceman" then
			src = THEME_ICEMAN
		elseif heroId == "invisible_woman" then
			src = THEME_IW
		end
		for key, value in src do
			THEME[key] = value
		end

		local function paintBg(gui: Instance?, color: Color3)
			if gui and gui:IsA("GuiObject") then
				gui.BackgroundColor3 = color
			end
		end
		local function paintStroke(stroke: UIStroke?, color: Color3)
			if stroke then
				stroke.Color = color
			end
		end
		local function paintText(label: TextLabel?, color: Color3)
			if label then
				label.TextColor3 = color
			end
		end

		paintBg(viewportHolder, THEME.barBg)
		paintBg(viewport, THEME.viewportBg)
		paintStroke(vpStroke, THEME.stroke)
		paintBg(profilePanel, THEME.panel)
		paintStroke(profileStroke, THEME.stroke)
		paintBg(abilityBar, THEME.abilityBar)
		paintStroke(abilityStroke, THEME.stroke)
		local phoenix = heroId == "jean_grey"
			and character
			and character:GetAttribute(GameConstants.LOOK_MODE_ATTRIBUTE) == "phoenix"
		if abilityBar then
			abilityBar.BackgroundTransparency = if phoenix then 1 else 0.12
		end
		if abilityStroke then
			abilityStroke.Transparency = if phoenix then 1 else 0.4
		end
		if hairCosmetic then
			hairCosmetic.btn.BackgroundColor3 = THEME.btn
			if hairCosmetic.stroke then
				hairCosmetic.stroke.Color = THEME.stroke
			end
		end
		paintBg(tooltip, THEME.panel)
		paintStroke(tooltipStroke, THEME.stroke)
		paintBg(tooltipRule, THEME.stroke)
		paintText(tooltipTitle, THEME.panelTitle)
		paintBg(energyFill, THEME.energy)
		paintBg(restraintBar, THEME.abilityBar)
		paintStroke(restraintStroke, THEME.stroke)
		paintBg(restraintFill, THEME.energy)
		paintText(restraintLabel, THEME.panelTitle)
		refreshSoftLockToggle()

		local abilityNameColor = if heroId == "dagger"
			then Color3.fromRGB(255, 255, 255)
			elseif heroId == "jean_grey" then
				(if character and character:GetAttribute(GameConstants.LOOK_MODE_ATTRIBUTE) == "phoenix"
					then Color3.fromRGB(255, 140, 95)
					else (if character and character:GetAttribute(GameConstants.LOOK_MODE_ATTRIBUTE) == "marvel_girl"
						then Color3.fromRGB(255, 170, 220)
						else Color3.fromRGB(170, 185, 255)))
			elseif heroId == "iceman" then Color3.fromRGB(200, 225, 255)
			elseif heroId == "invisible_woman" then Color3.fromRGB(77, 71, 255)
			else Color3.fromRGB(238, 230, 232)
		local keyTextColor = Color3.fromRGB(250, 250, 252)
		for _, slot in abilitySlots do
			if slot.nameLabel then
				slot.nameLabel.TextColor3 = abilityNameColor
			end
			local badge = slot.btn:FindFirstChild("KeyBadge")
			if badge then
				local keyLabel = badge:FindFirstChild("KeyLabel")
				if keyLabel and keyLabel:IsA("TextLabel") then
					keyLabel.TextColor3 = keyTextColor
				end
			end
		end
		for _, slot in extraSlots do
			if slot.nameLabel then
				slot.nameLabel.TextColor3 = abilityNameColor
			end
			local badge = slot.btn:FindFirstChild("KeyBadge")
			if badge then
				local keyLabel = badge:FindFirstChild("KeyLabel")
				if keyLabel and keyLabel:IsA("TextLabel") then
					keyLabel.TextColor3 = keyTextColor
				end
			end
		end
		if hairCosmetic then
			hairCosmetic.nameLabel.TextColor3 = abilityNameColor
			hairCosmetic.btn.BackgroundColor3 = THEME.btn
		end

		for _, panel in scarletModePanels do
			panel.BackgroundColor3 = THEME.panel
			local stroke = panel:FindFirstChild("ThemeStroke")
			if stroke and stroke:IsA("UIStroke") then
				stroke.Color = THEME.stroke
			end
			local title = panel:FindFirstChild("Title")
			if title and title:IsA("TextLabel") then
				title.TextColor3 = THEME.panelTitle
			end
		end
		for _, panel in marvelModePanels do
			panel.BackgroundColor3 = THEME.panel
			local stroke = panel:FindFirstChild("ThemeStroke")
			if stroke and stroke:IsA("UIStroke") then
				stroke.Color = THEME.stroke
			end
			local title = panel:FindFirstChild("Title")
			if title and title:IsA("TextLabel") then
				title.TextColor3 = THEME.panelTitle
			end
		end
		for _, panel in lokiModePanels do
			panel.BackgroundColor3 = THEME.panel
			local stroke = panel:FindFirstChild("ThemeStroke")
			if stroke and stroke:IsA("UIStroke") then
				stroke.Color = THEME.stroke
			end
			local title = panel:FindFirstChild("Title")
			if title and title:IsA("TextLabel") then
				title.TextColor3 = THEME.panelTitle
			end
		end
		if lokiClonePanel then
			lokiClonePanel.BackgroundColor3 = THEME.panel
			local stroke = lokiClonePanel:FindFirstChild("ThemeStroke")
			if stroke and stroke:IsA("UIStroke") then
				stroke.Color = THEME.stroke
			end
			local title = lokiClonePanel:FindFirstChild("Title")
			if title and title:IsA("TextLabel") then
				title.TextColor3 = THEME.panelTitle
			end
		end
		local lokiUltPanelInst = root:FindFirstChild("LokiUltPanel")
		if lokiUltPanelInst and lokiUltPanelInst:IsA("Frame") then
			lokiUltPanelInst.BackgroundColor3 = THEME.panel
			local stroke = lokiUltPanelInst:FindFirstChild("ThemeStroke")
			if stroke and stroke:IsA("UIStroke") then
				stroke.Color = THEME.stroke
			end
			local title = lokiUltPanelInst:FindFirstChild("Title")
			if title and title:IsA("TextLabel") then
				title.TextColor3 = THEME.panelTitle
			end
		end
		if daggerAlliesPanel then
			paintBg(daggerAlliesPanel, THEME.panel)
			local daggerStroke = daggerAlliesPanel:FindFirstChild("ThemeStroke")
			if daggerStroke and daggerStroke:IsA("UIStroke") then
				daggerStroke.Color = THEME.stroke
			end
			local daggerTitle = daggerAlliesPanel:FindFirstChild("Title")
			if daggerTitle and daggerTitle:IsA("TextLabel") then
				daggerTitle.TextColor3 = THEME.panelTitle
			end
			local daggerAdd = daggerAlliesPanel:FindFirstChild("AddAlly")
			if daggerAdd and daggerAdd:IsA("GuiObject") then
				daggerAdd.BackgroundColor3 = THEME.modeOn
			end
		end
		if settingsPanel then
			paintBg(settingsPanel, THEME.panel)
			paintStroke(settingsStroke, THEME.stroke)
			paintStroke(settingsBtnStroke, THEME.stroke)
			local settingsTitleLabel = settingsPanel:FindFirstChild("Title")
			if settingsTitleLabel and settingsTitleLabel:IsA("TextLabel") then
				settingsTitleLabel.TextColor3 = THEME.panelTitle
			end
			refreshShoulderSettingsUi()
		end
	end

	local function rebuildAbilityBar(heroId: string)
		clearSlots(abilitySlots)
		clearSlots(extraSlots)
		hideTooltip()
		applyTheme(heroId)

		local abilities = CharacterRegistry.getAbilities(heroId)
		local main: { any } = {}
		local extras: { any } = {}
		local inJeanAstral = heroId == "jean_grey"
			and boundCharacter
			and boundCharacter:GetAttribute(GameConstants.MG_ASTRAL_BODY_ATTRIBUTE) == true
		for _, ability in abilities do
			-- Show cooldown passives on the main bar (e.g. Chaos Impact)
			if ability.passive == true then
				if not inJeanAstral and ability.cooldown > 0 and type(ability.key) == "string" and ability.key ~= "" then
					table.insert(main, ability)
				end
				continue
			end
			if type(ability.key) ~= "string" or ability.key == "" then
				continue
			end
			if inJeanAstral then
				if ability.sideBar and ability.astralOnly == true then
					table.insert(extras, ability)
				end
				continue
			end
			if ability.sideBar then
				if ability.astralOnly == true then
					local inAstral = boundCharacter
						and boundCharacter:GetAttribute(GameConstants.MG_ASTRAL_BODY_ATTRIBUTE) == true
					if not inAstral then
						continue
					end
				end
				if ability.id == "forcefield_choke" or ability.id == "forcefield_protect" then
					local areaOn = boundCharacter
						and AbilityCooldownHelper.isActive(boundCharacter, "forcefield_area")
					if not areaOn then
						continue
					end
				end
				table.insert(extras, ability)
			else
				table.insert(main, ability)
			end
		end
		table.sort(main, function(a, b)
			local ka = KEY_ORDER[a.key] or (if a.passive then 90 else 99)
			local kb = KEY_ORDER[b.key] or (if b.passive then 90 else 99)
			return ka < kb
		end)

		local mainCount = #main
		local pad = 0.012
		local slotWidth = if mainCount > 0
			then math.min(0.118, (0.96 - pad * math.max(mainCount - 1, 0)) / mainCount)
			else 0.118

		local function wireAbilityButton(slot: AbilitySlot, ability: any)
			if ability.passive == true or type(ability.key) ~= "string" or ability.key == "" then
				return
			end
			local key = ability.key
			local isHold = ability.hold == true
			-- Activated works for mouse + touch (mobile)
			slot.btn.Activated:Connect(function()
				local character = player.Character
				if character and AbilityCooldownHelper.isActive(character, ability.id) and ability.id == "rune_entrapment" then
					return
				end
				if character and AbilityCooldownHelper.isOnCooldown(character, ability.id) then
					local allowCancel = (
						ability.id == "shapeshift"
						and character:GetAttribute(GameConstants.LOKI_SHAPESHIFT_ATTRIBUTE) == true
					)
						or (
							isHold
							and AbilityCooldownHelper.isActive(character, ability.id)
						)
						or (
							ability.id == "telekinesis"
							and character:GetAttribute(GameConstants.TK_ACTIVE_ATTRIBUTE) == true
						)
						or (
							(ability.id == "teleportation" or ability.id == "trickster_dash" or ability.id == "hex_displacement")
							and character:GetAttribute(GameConstants.TELEPORT_AIMING_ATTRIBUTE) == true
						)
						or (
							ability.id == "forcefield_area"
							and AbilityCooldownHelper.isActive(character, ability.id)
						)
					if not allowCancel then
						return
					end
				end
				AbilityInput.triggerFromHud(key, isHold)
			end)
		end

		for i, ability in main do
			local cd = ability.cooldown
			local mode: string? = nil
			if ability.id == "hex_blast" then
				mode = if boundCharacter then boundCharacter:GetAttribute(GameConstants.HEX_BLAST_MODE_ATTRIBUTE) else "Single"
				if mode ~= "Barrage" then
					mode = "Single"
				end
				cd = if mode == "Barrage"
					then GameConstants.HEX_BLAST_BARRAGE_COOLDOWN
					else GameConstants.HEX_BLAST_SINGLE_COOLDOWN
			elseif ability.id == "telekinesis" then
				mode = if boundCharacter then boundCharacter:GetAttribute(GameConstants.TK_MODE_ATTRIBUTE) else "Single"
				if mode ~= "Multiple" and mode ~= "Torture" then
					mode = "Single"
				end
			elseif ability.id == "trickster_dash" then
				mode = if boundCharacter then boundCharacter:GetAttribute(GameConstants.LOKI_DASH_MODE_ATTRIBUTE) else "Dash"
				if mode ~= "Teleport" then
					mode = "Dash"
				end
			end
			-- Hold / lasting abilities: no "…" while active
			local suppressEllipsis = ability.hold == true
				or ability.id == "shapeshift"
				or ability.id == "god_of_mischief"
				or ability.id == "binary_form"
				or ability.id == "illusion_decoy"
				or ability.id == "teleportation"
				or ability.id == "hex_displacement"
				or ability.id == "trickster_dash"
				or ability.id == "forcefield_area"
				or ability.id == "forcefield_choke"
				or ability.id == "forcefield_protect"
			local slot = createAbilityButton(
				abilityRow,
				ability.id,
				ability.name,
				ability.description,
				ability.key,
				i,
				ability.id,
				cd,
				UDim2.fromScale(slotWidth, 0.92),
				suppressEllipsis,
				CharacterRegistry.resolveAbilityIcon(ability, mode)
			)
			wireAbilityButton(slot, ability)
			table.insert(abilitySlots, slot)
		end

		for i, ability in extras do
			local suppressEllipsis = ability.hold == true
				or ability.id == "shapeshift"
				or ability.id == "god_of_mischief"
				or ability.id == "binary_form"
				or ability.id == "illusion_decoy"
				or ability.id == "teleportation"
				or ability.id == "hex_displacement"
				or ability.id == "trickster_dash"
				or ability.id == "forcefield_area"
				or ability.id == "forcefield_choke"
				or ability.id == "forcefield_protect"
			local displayName = ability.name
			if ability.id == "forcefield_smash" then
				local look = if boundCharacter then boundCharacter:GetAttribute(GameConstants.LOOK_MODE_ATTRIBUTE) else nil
				if look == "modern" then
					displayName = "Forcefield Bubble Smash"
				end
			end
			local extraBtnSize = if heroId == "invisible_woman"
				then UDim2.fromScale(0.96, 0.20)
				else UDim2.fromScale(0.96, 0.22)
			local slot = createAbilityButton(
				extraColumn,
				ability.id,
				displayName,
				ability.description,
				ability.key,
				i,
				ability.id,
				ability.cooldown,
				extraBtnSize,
				suppressEllipsis,
				CharacterRegistry.resolveAbilityIcon(ability, nil)
			)
			wireAbilityButton(slot, ability)
			table.insert(extraSlots, slot)
		end

		local showScarlet = heroId == "scarlet_witch"
		local showMarvel = heroId == "captain_marvel"
		local showLoki = heroId == "loki"
		local showDagger = heroId == "dagger"
		local showMarvelGirl = heroId == "jean_grey"
		local showIceman = heroId == "iceman"
		local showIw = heroId == "invisible_woman"
		modeColumn.Visible = showMarvel or showLoki
		for _, panel in scarletModePanels do
			panel.Visible = false
		end
		for _, panel in marvelModePanels do
			panel.Visible = showMarvel
		end
		for _, panel in lokiModePanels do
			panel.Visible = showLoki
		end
		extraColumn.Visible = (showScarlet or showLoki or showDagger or showMarvelGirl or showIceman or showIw) and #extras > 0
		if showIw then
			extraColumn.Size = UDim2.fromScale(0.068, 0.42)
		else
			extraColumn.Size = UDim2.fromScale(0.075, 0.4)
		end
		absorbColumn.Visible = showMarvel
		restraintBar.Visible = showMarvelGirl or showScarlet or showIw
		abilityBar.Visible = mainCount > 0
		refreshModeButtons()
		refreshLokiClonePanel()
		refreshLokiUltPanel()
	end

	local function setBar(fill: Frame, label: TextLabel, prefix: string, current: number, max: number)
		local ratio = if max > 0 then math.clamp(current / max, 0, 1) else 0
		fill.Size = UDim2.fromScale(ratio, 1)
		label.Text = string.format("%s: %d/%d", prefix, math.floor(current + 0.5), math.floor(max + 0.5))
	end

	local function refreshAbsorbCharge(character: Model)
		local charge = character:GetAttribute(GameConstants.ABSORB_CHARGE_ATTRIBUTE)
		if type(charge) ~= "number" then
			charge = 0
		end
		local ratio = math.clamp(charge / GameConstants.ABSORB_CHARGE_MAX, 0, 1)
		absorbFill.Size = UDim2.fromScale(1, ratio)
		absorbPct.Text = string.format("%d%%", math.floor(ratio * 100 + 0.5))

		local mult = 1 + ratio * (GameConstants.CM_ABSORB_OUTGOING_MULT_MAX - 1)
		local bonusPct = math.floor((mult - 1) * 100 + 0.5)
		local hasBonus = ratio > 0.01
		absorbStatus.Visible = hasBonus and currentHeroId == "captain_marvel"
		if hasBonus then
			absorbStatus.Text = string.format("+%d%%", bonusPct)
			local t = ratio
			absorbStatus.BackgroundColor3 = Color3.fromRGB(
				math.floor(220 + 35 * t),
				math.floor(160 + 50 * t),
				math.floor(40 + 20 * t)
			)
		end
		if hoveredStatus == "absorb" and tooltip.Visible then
			local title, body = buildAbsorbTooltip()
			tooltipTitle.Text = title
			tooltipBody.Text = body
		end
	end

	absorbStatus.MouseEnter:Connect(function()
		hoveredStatus = "absorb"
		local title, body = buildAbsorbTooltip()
		showTooltip(title, body)
	end)
	absorbStatus.MouseLeave:Connect(function()
		if hoveredStatus == "absorb" then
			hoveredStatus = nil
		end
		hideTooltip()
	end)

	local function refreshBinaryStatus(character: Model)
		local on = character:GetAttribute(GameConstants.BINARY_ACTIVE_ATTRIBUTE) == true
			and currentHeroId == "captain_marvel"
		binaryStatus.Visible = on
		if on then
			local untilTime = character:GetAttribute(GameConstants.BINARY_UNTIL_ATTRIBUTE)
			local left = 0
			if type(untilTime) == "number" then
				left = math.max(0, untilTime - AbilityCooldownHelper.getNow())
			end
			binaryStatus.Text = if left > 0 then string.format("%.0fs", left) else "BIN"
		end
		if hoveredStatus == "binary" and tooltip.Visible then
			local title, body = buildBinaryTooltip()
			tooltipTitle.Text = title
			tooltipBody.Text = body
		end
	end

	binaryStatus.MouseEnter:Connect(function()
		hoveredStatus = "binary"
		local title, body = buildBinaryTooltip()
		showTooltip(title, body)
	end)
	binaryStatus.MouseLeave:Connect(function()
		if hoveredStatus == "binary" then
			hoveredStatus = nil
		end
		hideTooltip()
	end)

	local function refreshAstralStatus(character: Model)
		local inAstral = currentHeroId == "jean_grey"
			and character:GetAttribute(GameConstants.MG_ASTRAL_BODY_ATTRIBUTE) == true
		astralStatus.Visible = inAstral
		if inAstral then
			local endAt = character:GetAttribute(GameConstants.MG_ASTRAL_END_AT_ATTRIBUTE)
			local left = GameConstants.MG_ASTRAL_DURATION
			if type(endAt) == "number" then
				left = math.max(0, endAt - AbilityCooldownHelper.getNow())
			end
			astralStatus.Text = string.format("%.0fs", left)
		end
		if hoveredStatus == "astral" and tooltip.Visible then
			tooltipTitle.Text = "Astral Form"
			tooltipBody.Text = "You have left your body. Return before the timer runs out."
		end
	end

	local function refreshRestraint(character: Model)
		local isJean = currentHeroId == "jean_grey"
		local isWanda = currentHeroId == "scarlet_witch"
		local isIw = currentHeroId == "invisible_woman"
		local show = isJean or isWanda or isIw
		restraintBar.Visible = show
		if not show then
			return
		end
		if isWanda then
			local current = character:GetAttribute(GameConstants.SW_CONTROL_ATTRIBUTE)
			local maxC = character:GetAttribute(GameConstants.SW_CONTROL_MAX_ATTRIBUTE)
			if type(current) ~= "number" then
				current = 0
			end
			if type(maxC) ~= "number" or maxC <= 0 then
				maxC = GameConstants.SW_CONTROL_MAX
			end
			restraintFill.Size = UDim2.fromScale(math.clamp(current / maxC, 0, 1), 1)
			restraintFill.BackgroundColor3 = THEME.energy
			restraintLabel.Text = "Control"
			restraintLabel.TextColor3 = Color3.fromRGB(255, 246, 248)
			restraintLabelStroke.Transparency = 0.05
			restraintLabelStroke.Color = Color3.fromRGB(22, 8, 10)
			return
		end
		restraintLabelStroke.Transparency = 1
		if isIw then
			local current = character:GetAttribute(GameConstants.IW_HYPERSPACE_ATTRIBUTE)
			local maxH = character:GetAttribute(GameConstants.IW_HYPERSPACE_MAX_ATTRIBUTE)
			if type(current) ~= "number" then
				current = 0
			end
			if type(maxH) ~= "number" or maxH <= 0 then
				maxH = GameConstants.IW_HYPERSPACE_MAX
			end
			restraintFill.Size = UDim2.fromScale(math.clamp(current / maxH, 0, 1), 1)
			restraintFill.BackgroundColor3 = GameConstants.IW_COLOR
			restraintLabel.Text = "Hyperspace Strain"
			return
		end
		local current = character:GetAttribute(GameConstants.MG_RESTRAINT_ATTRIBUTE)
		local maxR = character:GetAttribute(GameConstants.MG_RESTRAINT_MAX_ATTRIBUTE)
		if type(current) ~= "number" then
			current = 0
		end
		if type(maxR) ~= "number" or maxR <= 0 then
			maxR = GameConstants.MG_RESTRAINT_MAX
		end
		restraintFill.Size = UDim2.fromScale(math.clamp(current / maxR, 0, 1), 1)
		restraintFill.BackgroundColor3 = THEME.energy
		restraintLabel.Text = "Strain"
	end

	local function refreshStatus(character: Model)
		local ragdolled = character:GetAttribute(GameConstants.RAGDOLLED_ATTRIBUTE) == true
		ragdollStatus.Visible = ragdolled
		if ragdolled and hoveredStatus == "ragdoll" and tooltip.Visible then
			local title, body = buildRagdollTooltip()
			tooltipTitle.Text = title
			tooltipBody.Text = body
		elseif not ragdolled and hoveredStatus == "ragdoll" then
			hoveredStatus = nil
			hideTooltip()
		end
		refreshBinaryStatus(character)
		refreshAstralStatus(character)
		refreshRestraint(character)
	end

	ragdollStatus.MouseEnter:Connect(function()
		hoveredStatus = "ragdoll"
		local title, body = buildRagdollTooltip()
		showTooltip(title, body)
	end)
	ragdollStatus.MouseLeave:Connect(function()
		if hoveredStatus == "ragdoll" then
			hoveredStatus = nil
		end
		hideTooltip()
	end)

	astralStatus.MouseEnter:Connect(function()
		hoveredStatus = "astral"
		showTooltip("Astral Form", "You have left your body. Return before the timer runs out.")
	end)
	astralStatus.MouseLeave:Connect(function()
		if hoveredStatus == "astral" then
			hoveredStatus = nil
		end
		hideTooltip()
	end)

	local function refreshStats(character: Model)
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			setBar(healthFill, healthLabel, "Health", humanoid.Health, humanoid.MaxHealth)
		end
		local energy = character:GetAttribute(GameConstants.ENERGY_ATTRIBUTE)
		local maxEnergy = character:GetAttribute(GameConstants.MAX_ENERGY_ATTRIBUTE)
		if type(energy) == "number" and type(maxEnergy) == "number" then
			setBar(energyFill, energyLabel, "Energy", energy, maxEnergy)
		end
		local stamina = character:GetAttribute(GameConstants.STAMINA_ATTRIBUTE)
		local maxStamina = character:GetAttribute(GameConstants.MAX_STAMINA_ATTRIBUTE)
		if type(stamina) == "number" and type(maxStamina) == "number" then
			setBar(staminaFill, staminaLabel, "Stamina", stamina, maxStamina)
		end
		refreshAbsorbCharge(character)
		refreshModeButtons()
		refreshStatus(character)
		refreshLokiClonePanel()
		refreshLokiUltPanel()
	end

	local function startCooldownLoop()
		if cooldownConn then
			cooldownConn:Disconnect()
		end
		cooldownConn = RunService.RenderStepped:Connect(function()
			updateSlotCooldowns(abilitySlots)
			updateSlotCooldowns(extraSlots)
			if boundCharacter then
				local remaining = AbilityCooldownHelper.getRemaining(boundCharacter, "jean_hair")
				if remaining > 0 then
					hairCosmetic.cooldownOverlay.Visible = true
					hairCosmetic.cooldownOverlay.Size = UDim2.fromScale(1, math.clamp(remaining / GameConstants.MG_HAIR_COOLDOWN, 0, 1))
					hairCosmetic.cooldownLabel.Visible = true
					hairCosmetic.cooldownLabel.Text = string.format("%.1f", remaining)
				else
					hairCosmetic.cooldownOverlay.Visible = false
					hairCosmetic.cooldownLabel.Visible = false
				end
			end
			if boundCharacter and binaryStatus.Visible then
				refreshBinaryStatus(boundCharacter)
			end
			if boundCharacter and astralStatus.Visible then
				refreshAstralStatus(boundCharacter)
			end
			if boundCharacter and restraintBar.Visible then
				refreshRestraint(boundCharacter)
			end
		end)
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
			applyTheme(heroId)
			screenGui.ResetOnSpawn = false
			screenGui.Enabled = true
			if root then
				root.Visible = true
			end
			if topCluster then
				topCluster.Visible = true
			end
			if bottomRow then
				bottomRow.Visible = true
			end
			if abilityBar then
				abilityBar.Visible = true
			end
			if abilityRow then
				abilityRow.Visible = true
			end
			rebuildAbilityBar(heroId)
			refreshHairSlot()
			-- Ability buttons are rebuilt after theme — paint names white for Dagger
			if heroId == "dagger" then
				for _, slot in abilitySlots do
					slot.nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
				end
				for _, slot in extraSlots do
					slot.nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
				end
			end
			refreshDaggerAlliesPanel()
			if heroId == "dagger" then
				getUseAbility():FireServer({ action = "AllyRefresh" })
			end
			startCooldownLoop()
		end,
		hide = function()
			screenGui.Enabled = false
			if modeColumn then
				modeColumn.Visible = false
			end
			if extraColumn then
				extraColumn.Visible = false
			end
			if absorbColumn then
				absorbColumn.Visible = false
			end
			if lokiClonePanel then
				lokiClonePanel.Visible = false
			end
			if root then
				local ultPanel = root:FindFirstChild("LokiUltPanel")
				if ultPanel and ultPanel:IsA("GuiObject") then
					ultPanel.Visible = false
				end
			end
			if daggerAlliesPanel then
				daggerAlliesPanel.Visible = false
			end
			setDaggerAllyArming(false)
			if settingsPanel then
				settingsPanel.Visible = false
			end
			if hairCosmetic then
				hairCosmetic.slot.Visible = false
			end
			if profilePanel then
				profilePanel.Visible = false
			end
			if ragdollStatus then
				ragdollStatus.Visible = false
			end
			if absorbStatus then
				absorbStatus.Visible = false
			end
			if binaryStatus then
				binaryStatus.Visible = false
			end
			if astralStatus then
				astralStatus.Visible = false
			end
			if restraintBar then
				restraintBar.Visible = false
			end
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
			if modeConnA then
				modeConnA:Disconnect()
			end
			if modeConnB then
				modeConnB:Disconnect()
			end
			if modeConnC then
				modeConnC:Disconnect()
			end
			if modeConnD then
				modeConnD:Disconnect()
			end
			if modeConnE then
				modeConnE:Disconnect()
			end
			if areaConn then
				areaConn:Disconnect()
			end
			if ragdollConn then
				ragdollConn:Disconnect()
			end
			local humanoid = character:WaitForChild("Humanoid", 8) :: Humanoid?
			if not humanoid then
				return
			end
			-- Morph / starter swap can lag HRP; wait so viewport isn't empty
			character:WaitForChild("HumanoidRootPart", 8)
			healthConn = humanoid.HealthChanged:Connect(function()
				refreshStats(character)
			end)
			humanoid.Died:Connect(function()
				refreshStats(character)
			end)
			character:GetAttributeChangedSignal(GameConstants.ENERGY_ATTRIBUTE):Connect(function()
				refreshStats(character)
			end)
			character:GetAttributeChangedSignal(GameConstants.STAMINA_ATTRIBUTE):Connect(function()
				refreshStats(character)
			end)
			character:GetAttributeChangedSignal(GameConstants.ABSORB_CHARGE_ATTRIBUTE):Connect(function()
				refreshAbsorbCharge(character)
			end)
			character:GetAttributeChangedSignal(GameConstants.BINARY_ACTIVE_ATTRIBUTE):Connect(function()
				refreshBinaryStatus(character)
				refreshAbsorbCharge(character)
			end)
			character:GetAttributeChangedSignal(GameConstants.BINARY_UNTIL_ATTRIBUTE):Connect(function()
				refreshBinaryStatus(character)
			end)
			character:GetAttributeChangedSignal(GameConstants.LOKI_CLONE_ACTIVE_ATTRIBUTE):Connect(function()
				refreshLokiClonePanel()
			end)
			character:GetAttributeChangedSignal(GameConstants.LOKI_CLONE_MODE_ATTRIBUTE):Connect(function()
				refreshLokiClonePanel()
			end)
			character:GetAttributeChangedSignal(GameConstants.LOKI_ULT_ACTIVE_ATTRIBUTE):Connect(function()
				refreshLokiUltPanel()
			end)
			character:GetAttributeChangedSignal(GameConstants.LOKI_ULT_ATTACK_ATTRIBUTE):Connect(function()
				refreshLokiUltPanel()
			end)
			modeConnA = character:GetAttributeChangedSignal(GameConstants.HEX_BLAST_MODE_ATTRIBUTE):Connect(refreshModeButtons)
			modeConnB = character:GetAttributeChangedSignal(GameConstants.TK_MODE_ATTRIBUTE):Connect(refreshModeButtons)
			modeConnC = character:GetAttributeChangedSignal(GameConstants.ULTIMATE_MODE_ATTRIBUTE):Connect(refreshModeButtons)
			modeConnD = character:GetAttributeChangedSignal(GameConstants.PHOTON_FLIGHT_MODE_ATTRIBUTE):Connect(refreshModeButtons)
			modeConnE = character:GetAttributeChangedSignal(GameConstants.LOKI_DASH_MODE_ATTRIBUTE):Connect(refreshModeButtons)
			areaConn = character:GetAttributeChangedSignal(AbilityCooldownHelper.getActiveAttributeName("forcefield_area")):Connect(function()
				if currentHeroId then
					rebuildAbilityBar(currentHeroId)
				end
			end)
			ragdollConn = 			character:GetAttributeChangedSignal(GameConstants.RAGDOLLED_ATTRIBUTE):Connect(function()
				refreshStatus(character)
			end)
			character:GetAttributeChangedSignal(GameConstants.MG_ASTRAL_BODY_ATTRIBUTE):Connect(function()
				refreshAstralStatus(character)
				if currentHeroId then
					rebuildAbilityBar(currentHeroId)
				end
			end)
			character:GetAttributeChangedSignal(GameConstants.MG_ASTRAL_END_AT_ATTRIBUTE):Connect(function()
				refreshAstralStatus(character)
			end)
			character:GetAttributeChangedSignal(GameConstants.MG_RESTRAINT_ATTRIBUTE):Connect(function()
				refreshRestraint(character)
			end)
			character:GetAttributeChangedSignal(GameConstants.SW_CONTROL_ATTRIBUTE):Connect(function()
				refreshRestraint(character)
			end)
			character:GetAttributeChangedSignal(GameConstants.IW_HYPERSPACE_ATTRIBUTE):Connect(function()
				refreshRestraint(character)
			end)
			character:GetAttributeChangedSignal(GameConstants.MG_HAIR_TIED_ATTRIBUTE):Connect(function()
				refreshHairSlot()
			end)
			character:GetAttributeChangedSignal(GameConstants.LOOK_MODE_ATTRIBUTE):Connect(function()
				refreshHairSlot()
				if currentHeroId then
					rebuildAbilityBar(currentHeroId)
				end
				local liveSkin = character:GetAttribute(GameConstants.LOOK_MODE_ATTRIBUTE)
				local liveHero = character:GetAttribute(GameConstants.HERO_ATTRIBUTE)
				if type(liveHero) == "string" then
					local morph = CharacterRegistry.getMorphTemplate(
						liveHero,
						if type(liveSkin) == "string" then liveSkin else "base"
					)
					ViewportHelper.bindMorphIdle(viewport, morph, 0)
				end
			end)
			local skinId = character:GetAttribute(GameConstants.LOOK_MODE_ATTRIBUTE)
			local heroId = character:GetAttribute(GameConstants.HERO_ATTRIBUTE)
			if type(heroId) == "string" then
				local morph = CharacterRegistry.getMorphTemplate(
					heroId,
					if type(skinId) == "string" then skinId else "base"
				)
				ViewportHelper.bindMorphIdle(viewport, morph, 0)
			end
			if currentHeroId then
				rebuildAbilityBar(currentHeroId)
			end
			refreshHairSlot()
			refreshStats(character)
		end,
		destroy = function()
			if healthConn then
				healthConn:Disconnect()
			end
			if modeConnA then
				modeConnA:Disconnect()
			end
			if modeConnB then
				modeConnB:Disconnect()
			end
			if modeConnC then
				modeConnC:Disconnect()
			end
			if modeConnD then
				modeConnD:Disconnect()
			end
			if modeConnE then
				modeConnE:Disconnect()
			end
			if areaConn then
				areaConn:Disconnect()
			end
			if ragdollConn then
				ragdollConn:Disconnect()
			end
			stopCooldownLoop()
			hideTooltip()
			screenGui:Destroy()
		end,
	}
end

return GameplayHUD
