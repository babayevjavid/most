--!strict
--[[ CharacterOverheadUI: compact nameplate above character head (server-replicated). ]]

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CharacterConfig"))
local HudConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("HudConstants"))

export type OverheadController = {
	bind: (character: Model, owner: Player, characterId: string) -> (),
	unbind: (character: Model) -> (),
	unbindAll: () -> (),
}

type Entry = {
	healthConn: RBXScriptConnection?,
}

local active: { [Model]: Entry } = {}

local CharacterOverheadUI = {} :: OverheadController & { create: () -> OverheadController }

local function tween(inst: Instance, props: { [string]: any }, duration: number?)
	TweenService:Create(
		inst,
		TweenInfo.new(duration or HudConstants.BAR_TWEEN_DURATION, HudConstants.UI_EASING_STYLE, HudConstants.UI_EASING_DIRECTION),
		props
	):Play()
end

local function getAttachPart(character: Model): BasePart?
	return character:FindFirstChild("Head") :: BasePart?
		or character:FindFirstChild("HumanoidRootPart") :: BasePart?
		or character.PrimaryPart
end

local function getDisplayName(owner: Player): string
	if owner.DisplayName ~= "" then
		return owner.DisplayName
	end
	return owner.Name
end

local function updateHealthBar(fill: Frame, textLabel: TextLabel, current: number, max: number)
	local ratio = if max > 0 then math.clamp(current / max, 0, 1) else 0
	textLabel.Text = string.format("%d / %d", math.floor(current + 0.5), math.floor(max + 0.5))
	tween(fill, { Size = UDim2.fromScale(ratio, 1) }, HudConstants.BAR_TWEEN_DURATION)
end

local function createBillboard(character: Model, owner: Player, characterId: string): BillboardGui?
	local attach = getAttachPart(character)
	if not attach then
		return nil
	end

	local existing = attach:FindFirstChild("CharacterOverhead")
	if existing then
		existing:Destroy()
	end

	local entry = CharacterConfig.getCharacter(characterId)
	local heroName = if entry then entry.displayName else characterId
	local accent = if entry then entry.accentColor else HudConstants.COLOR_TEXT_SECONDARY

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "CharacterOverhead"
	billboard.Adornee = attach
	billboard.AlwaysOnTop = false
	billboard.LightInfluence = 0
	billboard.MaxDistance = HudConstants.OVERHEAD_MAX_DISTANCE
	billboard.Size = HudConstants.OVERHEAD_SIZE
	billboard.StudsOffset = HudConstants.OVERHEAD_STUDS_OFFSET
	billboard.ResetOnSpawn = false
	billboard.Parent = attach

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Parent = billboard

	local rootPad = Instance.new("UIPadding")
	rootPad.PaddingTop = UDim.new(0, 6)
	rootPad.PaddingBottom = UDim.new(0, 6)
	rootPad.PaddingLeft = UDim.new(0, 8)
	rootPad.PaddingRight = UDim.new(0, 8)
	rootPad.Parent = root

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 2)
	layout.Parent = root

	local usernameLabel = Instance.new("TextLabel")
	usernameLabel.Name = "Username"
	usernameLabel.LayoutOrder = 1
	usernameLabel.Size = UDim2.new(1, 0, 0.28, 0)
	usernameLabel.BackgroundTransparency = 1
	usernameLabel.Font = HudConstants.FONT_LABEL
	usernameLabel.Text = getDisplayName(owner)
	usernameLabel.TextColor3 = HudConstants.COLOR_TEXT
	usernameLabel.TextScaled = true
	usernameLabel.Parent = root

	local usernameConstraint = Instance.new("UITextSizeConstraint")
	usernameConstraint.MaxTextSize = 20
	usernameConstraint.MinTextSize = 12
	usernameConstraint.Parent = usernameLabel

	local heroLabel = Instance.new("TextLabel")
	heroLabel.Name = "HeroName"
	heroLabel.LayoutOrder = 2
	heroLabel.Size = UDim2.new(1, 0, 0.22, 0)
	heroLabel.BackgroundTransparency = 1
	heroLabel.Font = HudConstants.FONT_BODY
	heroLabel.Text = heroName
	heroLabel.TextColor3 = accent
	heroLabel.TextScaled = true
	heroLabel.Parent = root

	local heroConstraint = Instance.new("UITextSizeConstraint")
	heroConstraint.MaxTextSize = 16
	heroConstraint.MinTextSize = 11
	heroConstraint.Parent = heroLabel

	local barHolder = Instance.new("Frame")
	barHolder.Name = "HealthBar"
	barHolder.LayoutOrder = 3
	barHolder.Size = UDim2.new(0.92, 0, 0.3, 0)
	barHolder.BackgroundColor3 = HudConstants.COLOR_HEALTH_TRACK
	barHolder.BorderSizePixel = 0
	barHolder.ClipsDescendants = true
	barHolder.Parent = root

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 3)
	barCorner.Parent = barHolder

	local barFill = Instance.new("Frame")
	barFill.Name = "Fill"
	barFill.Size = UDim2.fromScale(1, 1)
	barFill.BackgroundColor3 = HudConstants.COLOR_HEALTH
	barFill.BorderSizePixel = 0
	barFill.ZIndex = 1
	barFill.Parent = barHolder

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 3)
	fillCorner.Parent = barFill

	local healthText = Instance.new("TextLabel")
	healthText.Name = "HealthText"
	healthText.Size = UDim2.fromScale(1, 1)
	healthText.BackgroundTransparency = 1
	healthText.Font = HudConstants.FONT_LABEL
	healthText.Text = "100 / 100"
	healthText.TextColor3 = HudConstants.COLOR_TEXT
	healthText.TextScaled = true
	healthText.ZIndex = 2
	healthText.Parent = barHolder

	local healthTextConstraint = Instance.new("UITextSizeConstraint")
	healthTextConstraint.MaxTextSize = 14
	healthTextConstraint.MinTextSize = 10
	healthTextConstraint.Parent = healthText

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local function sync()
			updateHealthBar(barFill, healthText, humanoid.Health, humanoid.MaxHealth)
		end
		sync()
		local conn = humanoid.HealthChanged:Connect(sync)
		active[character] = { healthConn = conn }
	else
		active[character] = {}
	end

	character.Destroying:Connect(function()
		CharacterOverheadUI.unbind(character)
	end)

	return billboard
end

function CharacterOverheadUI.unbind(character: Model)
	local entry = active[character]
	if entry then
		if entry.healthConn then
			entry.healthConn:Disconnect()
		end
		active[character] = nil
	end
	local attach = getAttachPart(character)
	if attach then
		local gui = attach:FindFirstChild("CharacterOverhead")
		if gui then
			gui:Destroy()
		end
	end
end

function CharacterOverheadUI.unbindAll()
	for character in active do
		CharacterOverheadUI.unbind(character)
	end
end

function CharacterOverheadUI.bind(character: Model, owner: Player, characterId: string)
	local entry = CharacterConfig.getCharacter(characterId)
	if not entry or entry.locked then
		return
	end
	CharacterOverheadUI.unbind(character)
	createBillboard(character, owner, characterId)
end

function CharacterOverheadUI.create(): OverheadController
	return CharacterOverheadUI
end

return CharacterOverheadUI
