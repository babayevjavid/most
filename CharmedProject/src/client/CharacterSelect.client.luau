local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local shared = ReplicatedStorage:WaitForChild("Shared", 30)
if not shared then
	warn("[CharacterSelect] ReplicatedStorage.Shared missing.")
	return
end

local characterConfigModule = shared:WaitForChild("CharacterConfig", 10)
local ok, CharacterConfig = pcall(require, characterConfigModule)
if not ok or type(CharacterConfig) ~= "table" then
	warn("[CharacterSelect] Failed to require CharacterConfig.")
	return
end

local remotesFolder = ReplicatedStorage:WaitForChild(CharacterConfig.RemotesFolderName, 30)
if not remotesFolder then
	warn("[CharacterSelect] Character remotes folder missing.")
	return
end

local selectRemote = remotesFolder:WaitForChild(CharacterConfig.SelectionRemoteName, 10)
if not selectRemote or not selectRemote:IsA("RemoteEvent") then
	warn("[CharacterSelect] Selection remote missing.")
	return
end

local powerCastRemote = remotesFolder:WaitForChild(CharacterConfig.PowerCastRemoteName, 10)
if not powerCastRemote or not powerCastRemote:IsA("RemoteEvent") then
	warn("[CharacterSelect] PowerCast remote missing.")
	return
end
local powerCastRemoteEvent = powerCastRemote :: RemoteEvent

local spellCastRemote = remotesFolder:WaitForChild(CharacterConfig.SpellCastRemoteName, 10)
if not spellCastRemote or not spellCastRemote:IsA("RemoteEvent") then
	warn("[CharacterSelect] SpellCast remote missing.")
	return
end
local spellCastRemoteEvent = spellCastRemote :: RemoteEvent

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CharmedCharacterUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false
screenGui.DisplayOrder = 1000
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
screenGui.Parent = playerGui

local chooserFrame = Instance.new("Frame")
chooserFrame.Name = "ChooserFrame"
chooserFrame.AnchorPoint = Vector2.new(1, 1)
chooserFrame.Position = UDim2.new(0.985, 0, 0.98, 0)
chooserFrame.Size = UDim2.new(0.46, 0, 0.08, 0)
chooserFrame.BackgroundTransparency = 1
chooserFrame.BorderSizePixel = 0
chooserFrame.Parent = screenGui

local buttonsFrame = Instance.new("Frame")
buttonsFrame.BackgroundTransparency = 1
buttonsFrame.Size = UDim2.new(1, 0, 1, 0)
buttonsFrame.Position = UDim2.new(0, 0, 0, 0)
buttonsFrame.Parent = chooserFrame

local grid = Instance.new("UIGridLayout")
grid.CellSize = UDim2.new(0.18, 0, 0.88, 0)
grid.CellPadding = UDim2.new(0.008, 0, 0, 0)
grid.FillDirectionMaxCells = 5
grid.Parent = buttonsFrame

local statsFrame = Instance.new("Frame")
statsFrame.Name = "StatsFrame"
statsFrame.AnchorPoint = Vector2.new(0, 0)
statsFrame.Position = UDim2.new(0.015, 0, 0.02, 0)
statsFrame.Size = UDim2.new(0.22, 0, 0.14, 0)
statsFrame.BackgroundColor3 = Color3.fromRGB(10, 12, 17)
statsFrame.BackgroundTransparency = 1
statsFrame.BorderSizePixel = 0
statsFrame.Visible = false
statsFrame.Parent = screenGui

local function createBar(yScale: number, fillColor: Color3): (Frame, TextLabel)
	local barBg = Instance.new("Frame")
	barBg.AnchorPoint = Vector2.new(0, 0.5)
	barBg.Size = UDim2.new(1, 0, 0.5, 0)
	barBg.Position = UDim2.new(0, 0, yScale, 0)
	barBg.BackgroundColor3 = Color3.fromRGB(34, 38, 52)
	barBg.BorderSizePixel = 0
	barBg.Parent = statsFrame

	local bgCorner = Instance.new("UICorner")
	bgCorner.CornerRadius = UDim.new(0, 6)
	bgCorner.Parent = barBg

	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(1, 0, 0.5, 0)
	fill.Position = UDim2.new(0, 0, 0, 0)
	fill.BackgroundColor3 = fillColor
	fill.BorderSizePixel = 0
	fill.Parent = barBg

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 6)
	fillCorner.Parent = fill

	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Enum.Font.GothamBold
	text.TextSize = 10
	text.TextColor3 = Color3.fromRGB(245, 245, 245)
	text.Text = ""
	text.Parent = barBg

	return fill, text
end

local function createMiniBar(yScale: number, fillColor: Color3, heightScale: number): (Frame, TextLabel)
	local barBg = Instance.new("Frame")
	barBg.AnchorPoint = Vector2.new(0, 0.5)
	barBg.Size = UDim2.new(1, 0, heightScale, 0)
	barBg.Position = UDim2.new(0, 0, yScale, 0)
	barBg.BackgroundColor3 = Color3.fromRGB(34, 38, 52)
	barBg.BorderSizePixel = 0
	barBg.Parent = statsFrame

	local bgCorner = Instance.new("UICorner")
	bgCorner.CornerRadius = UDim.new(0, 6)
	bgCorner.Parent = barBg

	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.Position = UDim2.new(0, 0, 0, 0)
	fill.BackgroundColor3 = fillColor
	fill.BorderSizePixel = 0
	fill.Parent = barBg

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 6)
	fillCorner.Parent = fill

	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Enum.Font.GothamBold
	text.TextSize = 10
	text.TextColor3 = Color3.fromRGB(245, 245, 245)
	text.Text = ""
	text.Parent = barBg

	return fill, text
end

local healthFill, healthLabel = createBar(0.2, Color3.fromRGB(74, 197, 94))
healthLabel.TextSize = 13
local energyFill, energyLabel = createBar(0.6, Color3.fromRGB(153, 96, 255))

-- Shows Piper's Molecular Combustion "fuel" (builds from hits, decays over time).
local combustionFuelFill, combustionFuelLabel = createMiniBar(0.88, Color3.fromRGB(255, 160, 45), 0.18)
local combustionFuelBg: Frame = combustionFuelFill.Parent :: Frame

-- All playable roles use GoodEvil (witches spawn good, Belthazor spawns evil).
local MORALITY_BAR_ROLES: { [string]: boolean } = {}
for _, name in CharacterConfig.Choices do
	MORALITY_BAR_ROLES[name] = true
end

local moralityFrame = Instance.new("Frame")
moralityFrame.Name = "MoralityBar"
moralityFrame.AnchorPoint = Vector2.new(0.5, 1)
moralityFrame.Position = UDim2.fromScale(0.5, 1)
moralityFrame.Size = UDim2.new(0.5, 0, 0.05, 0)
moralityFrame.BackgroundTransparency = 1
moralityFrame.BorderSizePixel = 0
moralityFrame.Visible = false
moralityFrame.ZIndex = 5
moralityFrame.Parent = screenGui

local badEndLabel = Instance.new("TextLabel")
badEndLabel.BackgroundTransparency = 1
badEndLabel.Size = UDim2.new(0.1, 0, 1, 0)
badEndLabel.Position = UDim2.fromScale(0, 0)
badEndLabel.Font = Enum.Font.GothamBold
badEndLabel.TextScaled = true
badEndLabel.TextColor3 = Color3.new(1, 1, 1)
badEndLabel.TextXAlignment = Enum.TextXAlignment.Left
badEndLabel.Text = "Bad"
badEndLabel.Parent = moralityFrame

local goodEndLabel = Instance.new("TextLabel")
goodEndLabel.BackgroundTransparency = 1
goodEndLabel.Size = UDim2.new(0.1, 0, 1, 0)
goodEndLabel.Position = UDim2.new(0.9, 0, 0, 0)
goodEndLabel.Font = Enum.Font.GothamBold
goodEndLabel.TextScaled = true
goodEndLabel.TextColor3 = Color3.new(1, 1, 1)
goodEndLabel.TextXAlignment = Enum.TextXAlignment.Right
goodEndLabel.Text = "Good"
goodEndLabel.Parent = moralityFrame

local moralityTrackBg = Instance.new("Frame")
moralityTrackBg.Name = "Track"
moralityTrackBg.AnchorPoint = Vector2.new(0.5, 0.5)
moralityTrackBg.Position = UDim2.fromScale(0.5, 0.5)
moralityTrackBg.Size = UDim2.new(0.78, 0, 0.55, 0)
moralityTrackBg.BackgroundColor3 = Color3.new(0.5, 0.5, 0.5)
moralityTrackBg.BorderSizePixel = 0
moralityTrackBg.Parent = moralityFrame

local moralityMarker = Instance.new("Frame")
moralityMarker.Name = "Marker"
moralityMarker.AnchorPoint = Vector2.new(0.5, 0.5)
moralityMarker.Size = UDim2.new(0.008, 0, 1, 0)
moralityMarker.Position = UDim2.fromScale(0.5, 0.5)
moralityMarker.BackgroundColor3 = Color3.new(0.15, 0.15, 0.15)
moralityMarker.BorderSizePixel = 0
moralityMarker.ZIndex = 2
moralityMarker.Parent = moralityTrackBg

local function updateMoralityBarUi()
	local role = player:GetAttribute("ChosenCharacter")
	local show = type(role) == "string" and MORALITY_BAR_ROLES[role] == true
	moralityFrame.Visible = show
	if not show then
		return
	end
	local g = player:GetAttribute("GoodEvil")
	local t = if type(g) == "number" then g else 0
	t = math.clamp(t, -1, 1)
	moralityMarker.Position = UDim2.new((t + 1) / 2, 0, 0.5, 0)
end

player:GetAttributeChangedSignal("ChosenCharacter"):Connect(updateMoralityBarUi)
player:GetAttributeChangedSignal("GoodEvil"):Connect(updateMoralityBarUi)
task.defer(updateMoralityBarUi)

local powerFrame = Instance.new("Frame")
powerFrame.Name = "PowerFrame"
powerFrame.AnchorPoint = Vector2.new(0.5, 1)
powerFrame.Position = UDim2.new(0.5, 0, 0.925, 0)
powerFrame.Size = UDim2.new(0.88, 0, 0.1, 0)
powerFrame.BackgroundTransparency = 1
powerFrame.Visible = false
powerFrame.Parent = screenGui

local powerLayout = Instance.new("UIListLayout")
powerLayout.FillDirection = Enum.FillDirection.Horizontal
powerLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
powerLayout.VerticalAlignment = Enum.VerticalAlignment.Center
powerLayout.SortOrder = Enum.SortOrder.LayoutOrder
powerLayout.Padding = UDim.new(0, 14)
powerLayout.Parent = powerFrame

local spellsButton = Instance.new("TextButton")
spellsButton.Name = "SpellsButton"
spellsButton.AnchorPoint = Vector2.new(1, 0)
spellsButton.Position = UDim2.new(0.988, 0, 0.055, 0)
spellsButton.Size = UDim2.new(0.085, 0, 0.045, 0)
spellsButton.BackgroundColor3 = Color3.fromRGB(18, 23, 36)
spellsButton.Text = "Spells"
spellsButton.Font = Enum.Font.GothamBold
spellsButton.TextSize = 13
spellsButton.TextColor3 = Color3.fromRGB(222, 232, 248)
spellsButton.BorderSizePixel = 0
spellsButton.Parent = screenGui

local spellsCorner = Instance.new("UICorner")
spellsCorner.CornerRadius = UDim.new(0, 8)
spellsCorner.Parent = spellsButton

local spellsFrame = Instance.new("Frame")
spellsFrame.Name = "SpellsFrame"
spellsFrame.AnchorPoint = Vector2.new(1, 0)
spellsFrame.Position = UDim2.new(0.988, 0, 0.105, 0)
-- Auto-size vertically so all spell buttons are always inside the frame.
spellsFrame.Size = UDim2.new(0.26, 0, 0, 0)
spellsFrame.AutomaticSize = Enum.AutomaticSize.Y
spellsFrame.BackgroundColor3 = Color3.fromRGB(9, 12, 22)
spellsFrame.BackgroundTransparency = 0.05
spellsFrame.BorderSizePixel = 0
spellsFrame.Visible = false
spellsFrame.Parent = screenGui

local spellsCorner2 = Instance.new("UICorner")
spellsCorner2.CornerRadius = UDim.new(0, 10)
spellsCorner2.Parent = spellsFrame

local spellsStroke = Instance.new("UIStroke")
spellsStroke.Thickness = 1.5
spellsStroke.Color = Color3.fromRGB(81, 97, 130)
spellsStroke.Parent = spellsFrame

local spellsLayout = Instance.new("UIListLayout")
spellsLayout.FillDirection = Enum.FillDirection.Vertical
spellsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
spellsLayout.VerticalAlignment = Enum.VerticalAlignment.Top
spellsLayout.Padding = UDim.new(0, 6)
spellsLayout.SortOrder = Enum.SortOrder.LayoutOrder
spellsLayout.Parent = spellsFrame

local spellsPadding = Instance.new("UIPadding")
spellsPadding.PaddingTop = UDim.new(0, 8)
spellsPadding.PaddingLeft = UDim.new(0, 6)
spellsPadding.PaddingRight = UDim.new(0, 6)
spellsPadding.PaddingBottom = UDim.new(0, 6)
spellsPadding.Parent = spellsFrame

local function prefillChatPlaceholder(text: string)
	-- Try to write directly into the active chat text box so player can press Enter to send.
	for _, ui in playerGui:GetDescendants() do
		if ui:IsA("TextBox") then
			local fullName = string.lower(ui:GetFullName())
			if string.find(fullName, "chat", 1, true) then
				ui.Text = text
				ui:CaptureFocus()
				return
			end
		end
	end

	-- Fallback: set placeholder in TextChat configuration when direct input textbox is unavailable.
	local config = TextChatService:FindFirstChild("ChatInputBarConfiguration")
	if config then
		pcall(function()
			(config :: any).PlaceholderText = text
		end)
	end
end

local function sendSpellChat(text: string)
	if text == "" then
		return
	end
	local ok, _ = pcall(function()
		local channel = TextChatService.TextChannels:FindFirstChild("RBXGeneral")
		if channel then
			(channel :: any):SendAsync(text)
		end
	end)
	if not ok then
		warn("[Spells] Failed to send spell text")
	end
end

local function requestSpellCast(spellId: string)
	local witch = player:GetAttribute("ChosenCharacter")
	if type(witch) ~= "string" or witch == "" then
		return
	end
	spellCastRemoteEvent:FireServer(spellId)
end

local selectedCharacter: string? = nil
local humanoidConn: RBXScriptConnection? = nil
local energyConn: RBXScriptConnection? = nil
local fuelConn: RBXScriptConnection? = nil
local combatHealthConn: RBXScriptConnection? = nil
local combatMaxHealthConn: RBXScriptConnection? = nil
local molecularFrozenBlur: BlurEffect? = nil
local frozenAttrConn: RBXScriptConnection? = nil

local function setMolecularFrozenBlur(enabled: boolean)
	if enabled then
		if not molecularFrozenBlur or not molecularFrozenBlur.Parent then
			molecularFrozenBlur = Instance.new("BlurEffect")
			molecularFrozenBlur.Name = "MolecularFrozenBlur"
			molecularFrozenBlur.Size = 22
			molecularFrozenBlur.Parent = Lighting
		end
	else
		if molecularFrozenBlur then
			molecularFrozenBlur:Destroy()
			molecularFrozenBlur = nil
		end
	end
end
local mouse = player:GetMouse()
-- Server replicates grabbed BasePart so aim ray ignores it (mouse.Target still hits it).
local telekinesisGrabbedSubject: Instance? = nil

-- Telekinesis release trajectory preview (purely client-side VFX).
local TK_TRAJ_SEGMENTS = 18
local TK_TRAJ_MAX_T = 1.15
local trajectoryPreviewFolder: Folder? = nil
local trajectoryPreviewParts: { BasePart } = {}
local TRAJECTORY_PREVIEW_ENABLED = false

local function ensureTrajectoryPreview()
	if not TRAJECTORY_PREVIEW_ENABLED then
		-- Remove any leftover preview objects.
		if trajectoryPreviewFolder and trajectoryPreviewFolder.Parent then
			trajectoryPreviewFolder:Destroy()
		end
		trajectoryPreviewFolder = nil
		table.clear(trajectoryPreviewParts)
		return
	end
	-- If the folder exists but our cached parts list is empty/mismatched (common across mode/role
	-- changes), rebuild the parts so indexing never returns nil.
	local needsRebuild = #trajectoryPreviewParts < TK_TRAJ_SEGMENTS
	if not needsRebuild then
		return
	end

	-- Ensure folder exists.
	if not trajectoryPreviewFolder or not trajectoryPreviewFolder.Parent then
		trajectoryPreviewFolder = Instance.new("Folder")
		trajectoryPreviewFolder.Name = "TelekinesisTrajectoryPreview"
		trajectoryPreviewFolder.Parent = workspace
	else
		for _, child in trajectoryPreviewFolder:GetChildren() do
			child:Destroy()
		end
	end

	table.clear(trajectoryPreviewParts)
	for i = 1, TK_TRAJ_SEGMENTS do
		local p = Instance.new("Part")
		p.Name = "Seg_" .. i
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Size = Vector3.new(0.16, 0.16, 0.16)
		p.Material = Enum.Material.Neon
		p.Color = Color3.fromRGB(80, 200, 255)
		p.Transparency = 1
		p.Parent = trajectoryPreviewFolder
		table.insert(trajectoryPreviewParts, p)
	end
end

local function setTrajectoryPreviewVisible(visible: boolean)
	for _, p in trajectoryPreviewParts do
		if p and p.Parent then
			p.Transparency = if visible then 0.2 else 1
		end
	end
end

local POWERS_EXCHANGE_RANGE_STUDS = 12
-- Max time to pick a target; first valid click commits immediately (no wait after chat).
local POWERS_EXCHANGE_SELECT_MAX_SECONDS = 22
local powersExchangeSelectToken = 0
local powersExchangeSelecting = false
local powersExchangeInputConn: RBXScriptConnection? = nil

local function isWitchForExchange(plr: Player): boolean
	local c = plr:GetAttribute("ChosenCharacter")
	if type(c) ~= "string" or c == "" then
		return false
	end
	for _, name in CharacterConfig.Choices do
		if name == c then
			return true
		end
	end
	return false
end

local function getPlayerFromRaycastHit(inst: Instance?): Player?
	local model = inst and inst:FindFirstAncestorOfClass("Model")
	if not model then
		return nil
	end
	return Players:GetPlayerFromCharacter(model)
end

local function raycastPlayerUnderMouseForExchange(): Player?
	local cam = Workspace.CurrentCamera
	if not cam then
		return nil
	end
	local loc = UserInputService:GetMouseLocation()
	local ray = cam:ViewportPointToRay(loc.X, loc.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local filter: { Instance } = {}
	local ch = player.Character
	if ch then
		table.insert(filter, ch)
	end
	params.FilterDescendantsInstances = filter
	local res = Workspace:Raycast(ray.Origin, ray.Direction * 500, params)
	if not res then
		return nil
	end
	local hitPlr = getPlayerFromRaycastHit(res.Instance)
	if not hitPlr or hitPlr == player then
		return nil
	end
	if not isWitchForExchange(hitPlr) then
		return nil
	end
	local myRoot = ch and (ch:FindFirstChild("HumanoidRootPart") :: BasePart?)
	local theirRoot = hitPlr.Character and (hitPlr.Character:FindFirstChild("HumanoidRootPart") :: BasePart?)
	if not myRoot or not theirRoot then
		return nil
	end
	if (theirRoot.Position - myRoot.Position).Magnitude > POWERS_EXCHANGE_RANGE_STUDS then
		return nil
	end
	return hitPlr
end

local function startPowersExchangeTargetSelection()
	if powersExchangeInputConn then
		powersExchangeInputConn:Disconnect()
		powersExchangeInputConn = nil
	end
	powersExchangeSelectToken += 1
	local myToken = powersExchangeSelectToken
	powersExchangeSelecting = true
	local selectedUserId: number? = nil
	local conn: RBXScriptConnection? = nil
	conn = UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if myToken ~= powersExchangeSelectToken or not powersExchangeSelecting then
			return
		end
		if gameProcessed then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local plr = raycastPlayerUnderMouseForExchange()
		if plr then
			selectedUserId = plr.UserId
			powersExchangeSelecting = false
			if conn then
				conn:Disconnect()
			end
			if powersExchangeInputConn == conn then
				powersExchangeInputConn = nil
			end
			spellCastRemoteEvent:FireServer("powers_exchange", "commit", selectedUserId)
		end
	end)
	powersExchangeInputConn = conn
	task.delay(POWERS_EXCHANGE_SELECT_MAX_SECONDS, function()
		if myToken ~= powersExchangeSelectToken then
			return
		end
		if not powersExchangeSelecting then
			return
		end
		powersExchangeSelecting = false
		if conn then
			conn:Disconnect()
		end
		if powersExchangeInputConn == conn then
			powersExchangeInputConn = nil
		end
		spellCastRemoteEvent:FireServer("powers_exchange", "commit", selectedUserId)
	end)
end

local function getTelekinesisAimPosition(): Vector3
	local cam = Workspace.CurrentCamera
	if not cam then
		return mouse.Hit.Position
	end
	local filter: { Instance } = {}
	local ch = player.Character
	if ch then
		table.insert(filter, ch)
	end
	if telekinesisGrabbedSubject then
		if telekinesisGrabbedSubject:IsA("Model") then
			table.insert(filter, telekinesisGrabbedSubject)
		else
			local m = telekinesisGrabbedSubject:FindFirstAncestorOfClass("Model")
			table.insert(filter, if m then m else telekinesisGrabbedSubject)
		end
	end
	local loc = UserInputService:GetMouseLocation()
	local ray = cam:ViewportPointToRay(loc.X, loc.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = filter
	local res = Workspace:Raycast(ray.Origin, ray.Direction * 2200, params)
	if res then
		return res.Position
	end
	return ray.Origin + ray.Direction * 140
end

local function getTelekinesisAimDirection(): Vector3
	local cam = Workspace.CurrentCamera
	if not cam then
		return mouse.Hit.LookVector
	end
	local loc = UserInputService:GetMouseLocation()
	local ray = cam:ViewportPointToRay(loc.X, loc.Y)
	return ray.Direction
end

local levitationControlLoopRunning = false
local levitationLastMoveDir: Vector3? = nil
local levitationLastLook: Vector3? = nil
local powerButtons: { Frame } = {}
local powerButtonById: { [string]: TextButton } = {}
local cooldownOverlayById: { [string]: Frame } = {}
local cooldownLabelById: { [string]: TextLabel } = {}
local castProgressOverlayById: { [string]: Frame } = {}
local activeAbilities: { [string]: boolean } = {}

local telekinesisActive = false
local telekineticOrbingActive = false
local telekinesisHoldRequested = false
local telekineticOrbingHoldRequested = false
local telekinesisLocalMode = "dynamic"
-- Telekinesis channel style: "eye" = lower cost/damage/knockback/cd, "hand" = opposite.
local telekinesisChannelStyle: string = "hand"
local telekinesisStartModeOverride: string? = nil

-- Levitation behavior: "dynamic" (aggressive / fly) or "defensive" (hover upward + constant height).
local levitationLocalModeToken: string = "dynamic"

-- Right-bottom mode panel (Telekinesis Eye/Hand + Levitation Defensive/Aggressive).
local modePanel = Instance.new("Frame")
modePanel.Name = "ModePanelRightBottom"
modePanel.AnchorPoint = Vector2.new(1, 1)
modePanel.Position = UDim2.new(0.995, 0, 0.995, 0)
modePanel.Size = UDim2.new(0, 210, 0, 70)
modePanel.BackgroundColor3 = Color3.fromRGB(9, 12, 22)
modePanel.BackgroundTransparency = 0.12
modePanel.BorderSizePixel = 0
modePanel.ZIndex = 50
modePanel.Parent = screenGui

local modePanelCorner = Instance.new("UICorner")
modePanelCorner.CornerRadius = UDim.new(0, 12)
modePanelCorner.Parent = modePanel

local modePanelLayout = Instance.new("UIListLayout")
modePanelLayout.FillDirection = Enum.FillDirection.Vertical
modePanelLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
modePanelLayout.VerticalAlignment = Enum.VerticalAlignment.Top
modePanelLayout.SortOrder = Enum.SortOrder.LayoutOrder
modePanelLayout.Padding = UDim.new(0, 6)
modePanelLayout.Parent = modePanel

local tkRowTitle = Instance.new("TextLabel")
tkRowTitle.BackgroundTransparency = 1
tkRowTitle.Size = UDim2.new(1, -12, 0, 14)
tkRowTitle.Position = UDim2.new(0, 6, 0, 0)
tkRowTitle.Font = Enum.Font.GothamBold
tkRowTitle.TextSize = 12
tkRowTitle.TextColor3 = Color3.fromRGB(222, 232, 248)
tkRowTitle.Text = "Telekinesis"
tkRowTitle.TextXAlignment = Enum.TextXAlignment.Left
tkRowTitle.Parent = modePanel

local tkRow = Instance.new("Frame")
tkRow.BackgroundTransparency = 1
tkRow.Size = UDim2.new(1, -12, 0, 26)
tkRow.Parent = modePanel

local tkRowLayout = Instance.new("UIListLayout")
tkRowLayout.FillDirection = Enum.FillDirection.Horizontal
tkRowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
tkRowLayout.Padding = UDim.new(0, 8)
tkRowLayout.Parent = tkRow

local tkEyeButton = Instance.new("TextButton")
tkEyeButton.Name = "TelekinesisEyeButton"
tkEyeButton.Size = UDim2.new(0, 90, 0, 26)
tkEyeButton.BackgroundColor3 = Color3.fromRGB(18, 23, 36)
tkEyeButton.BorderSizePixel = 0
tkEyeButton.Font = Enum.Font.GothamBold
tkEyeButton.TextSize = 12
tkEyeButton.TextColor3 = Color3.fromRGB(230, 232, 245)
tkEyeButton.Text = "Eye"
tkEyeButton.Parent = tkRow

local tkEyeCorner = Instance.new("UICorner")
tkEyeCorner.CornerRadius = UDim.new(0, 8)
tkEyeCorner.Parent = tkEyeButton

local tkHandButton = Instance.new("TextButton")
tkHandButton.Name = "TelekinesisHandButton"
tkHandButton.Size = UDim2.new(0, 90, 0, 26)
tkHandButton.BackgroundColor3 = Color3.fromRGB(56, 86, 146)
tkHandButton.BorderSizePixel = 0
tkHandButton.Font = Enum.Font.GothamBold
tkHandButton.TextSize = 12
tkHandButton.TextColor3 = Color3.fromRGB(230, 232, 245)
tkHandButton.Text = "Hand"
tkHandButton.Parent = tkRow

local tkHandCorner = Instance.new("UICorner")
tkHandCorner.CornerRadius = UDim.new(0, 8)
tkHandCorner.Parent = tkHandButton

local levRowTitle = Instance.new("TextLabel")
levRowTitle.BackgroundTransparency = 1
levRowTitle.Size = UDim2.new(1, -12, 0, 14)
levRowTitle.Position = UDim2.new(0, 6, 0, 0)
levRowTitle.Font = Enum.Font.GothamBold
levRowTitle.TextSize = 12
levRowTitle.TextColor3 = Color3.fromRGB(222, 232, 248)
levRowTitle.Text = "Levitation"
levRowTitle.TextXAlignment = Enum.TextXAlignment.Left
levRowTitle.Parent = modePanel

local levRow = Instance.new("Frame")
levRow.BackgroundTransparency = 1
levRow.Size = UDim2.new(1, -12, 0, 26)
levRow.Parent = modePanel

local levRowLayout = Instance.new("UIListLayout")
levRowLayout.FillDirection = Enum.FillDirection.Horizontal
levRowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
levRowLayout.Padding = UDim.new(0, 8)
levRowLayout.Parent = levRow

local levDefButton = Instance.new("TextButton")
levDefButton.Name = "LevitationDefensiveButton"
levDefButton.Size = UDim2.new(0, 90, 0, 26)
levDefButton.BackgroundColor3 = Color3.fromRGB(18, 23, 36)
levDefButton.BorderSizePixel = 0
levDefButton.Font = Enum.Font.GothamBold
levDefButton.TextSize = 12
levDefButton.TextColor3 = Color3.fromRGB(230, 232, 245)
levDefButton.Text = "Def"
levDefButton.Parent = levRow

local levDefCorner = Instance.new("UICorner")
levDefCorner.CornerRadius = UDim.new(0, 8)
levDefCorner.Parent = levDefButton

local levAggButton = Instance.new("TextButton")
levAggButton.Name = "LevitationAggressiveButton"
levAggButton.Size = UDim2.new(0, 90, 0, 26)
levAggButton.BackgroundColor3 = Color3.fromRGB(56, 86, 146)
levAggButton.BorderSizePixel = 0
levAggButton.Font = Enum.Font.GothamBold
levAggButton.TextSize = 12
levAggButton.TextColor3 = Color3.fromRGB(230, 232, 245)
levAggButton.Text = "Agg"
levAggButton.Parent = levRow

local levAggCorner = Instance.new("UICorner")
levAggCorner.CornerRadius = UDim.new(0, 8)
levAggCorner.Parent = levAggButton

local function refreshModePanelUi()
	local role = player:GetAttribute("ChosenCharacter")
	local showTelekinesisModes = role == "Prue"
	local showLevitationModes = role == "Phoebe"
	modePanel.Visible = showTelekinesisModes or showLevitationModes
	tkRowTitle.Visible = showTelekinesisModes
	tkRow.Visible = showTelekinesisModes
	levRowTitle.Visible = showLevitationModes
	levRow.Visible = showLevitationModes
	combustionFuelBg.Visible = role == "Piper"

	tkEyeButton.BackgroundColor3 = if telekinesisChannelStyle == "eye" then Color3.fromRGB(56, 86, 146) else Color3.fromRGB(18, 23, 36)
	tkHandButton.BackgroundColor3 = if telekinesisChannelStyle == "hand" then Color3.fromRGB(56, 86, 146) else Color3.fromRGB(18, 23, 36)
	levDefButton.BackgroundColor3 = if levitationLocalModeToken == "defensive" then Color3.fromRGB(56, 86, 146) else Color3.fromRGB(18, 23, 36)
	levAggButton.BackgroundColor3 = if levitationLocalModeToken == "dynamic" then Color3.fromRGB(56, 86, 146) else Color3.fromRGB(18, 23, 36)
end

tkEyeButton.MouseButton1Click:Connect(function()
	if telekinesisActive or telekinesisHoldRequested then
		return
	end
	telekinesisChannelStyle = "eye"
	refreshModePanelUi()
end)

tkHandButton.MouseButton1Click:Connect(function()
	if telekinesisActive or telekinesisHoldRequested then
		return
	end
	telekinesisChannelStyle = "hand"
	refreshModePanelUi()
end)

levDefButton.MouseButton1Click:Connect(function()
	levitationLocalModeToken = "defensive"
	refreshModePanelUi()
end)

levAggButton.MouseButton1Click:Connect(function()
	levitationLocalModeToken = "dynamic"
	refreshModePanelUi()
end)

refreshModePanelUi()

-- Time window for detecting the 2nd tap (double-press) on telekinesis.
local TELEKINESIS_DOUBLE_TAP_SEC = 1
-- After switching to "deflective" mode, allow some time for the server to mark the grab active
-- before we auto-send the "push" (throw).
local TELEKINESIS_DEFLECTIVE_PUSH_WAIT_SEC = 1.0
local telekinesisTapLastClock = -1e9
local telekinesisTapLastTarget: Instance? = nil
local telekinesisDeflectivePushUntil = -1e9

local function sameTelekinesisActivateTarget(a: Instance?, b: Instance?): boolean
	if not a or not b then
		return false
	end
	if a == b then
		return true
	end
	local ma = a:FindFirstAncestorOfClass("Model")
	local mb = b:FindFirstAncestorOfClass("Model")
	return ma ~= nil and ma == mb
end

local function noteTelekinesisTargetTap(): string
	local now = os.clock()
	local t = mouse.Target
	local isDouble = (now - telekinesisTapLastClock) <= TELEKINESIS_DOUBLE_TAP_SEC
		and sameTelekinesisActivateTarget(t, telekinesisTapLastTarget)
	telekinesisTapLastClock = now
	telekinesisTapLastTarget = t
	return if isDouble then "deflective" else "dynamic"
end

-- Double-tap Molecular Combustion → Deviation for one cast (same 1s window as telekinesis double-tap).
local MOLECULAR_COMBUSTION_DOUBLE_TAP_SEC = 1
local molecularCombustionTapLastClock = -1e9
local molecularCombustionTapLastTarget: Instance? = nil
local molecularCombustionModeOverride: string? = nil

local function noteMolecularCombustionTap(): string
	local now = os.clock()
	local t = mouse.Target
	local isDouble = (now - molecularCombustionTapLastClock) <= MOLECULAR_COMBUSTION_DOUBLE_TAP_SEC
		and sameTelekinesisActivateTarget(t, molecularCombustionTapLastTarget)
	molecularCombustionTapLastClock = now
	molecularCombustionTapLastTarget = t
	return if isDouble then "deviation" else "destructive"
end

-- Fixed ability variants (mode panel removed; server reads this token per cast).
local DEFAULT_ABILITY_MODE: { [string]: string } = {
	telekinesis = "dynamic",
	molecular_combustion = "destructive",
	levitation = "dynamic",
	telekinetic_orbing = "dynamic",
}

local keybindByPowerId: { [string]: Enum.KeyCode } = {}
local powerByKeyCode: { [Enum.KeyCode]: { Id: string, Name: string } } = {}
local keybindOverrideByPowerId: { [string]: Enum.KeyCode } = {
	telekinesis = Enum.KeyCode.E,
}
local keybindOrder: { Enum.KeyCode } = {
	Enum.KeyCode.Q,
	Enum.KeyCode.E,
	Enum.KeyCode.R,
	Enum.KeyCode.F,
	Enum.KeyCode.T,
}

local function keyCodeToText(code: Enum.KeyCode): string
	return code.Name
end

local DEFAULT_CAM_FOV = 70
local ABILITY_CAM_FOV = 63
local abilityFovTween: Tween? = nil

local function syncAbilityCameraFov(premonitionEnding: boolean?)
	if activeAbilities.premonition and not premonitionEnding then
		return
	end
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local anyOther = false
	for id, on in activeAbilities do
		if on and id ~= "premonition" and id ~= "healing_target" then
			anyOther = true
			break
		end
	end
	local targetFov = if anyOther then ABILITY_CAM_FOV else DEFAULT_CAM_FOV
	if abilityFovTween then
		abilityFovTween:Cancel()
		abilityFovTween = nil
	end
	abilityFovTween = TweenService:Create(camera, TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		FieldOfView = targetFov,
	})
	abilityFovTween:Play()
end

local function getAbilityModeToken(powerId: string): string?
	if powerId == "levitation" then
		return levitationLocalModeToken
	end
	return DEFAULT_ABILITY_MODE[powerId]
end

local CHANNELED_POWER_IDS: { [string]: boolean } = {
	telekinesis = true,
	telekinetic_orbing = true,
	astral_projection = true,
	molecular_freeze = true,
	premonition = true,
	levitation = true,
	healing = true,
	-- Server sets this while you are another player's Healing target; no power button, but blocks other casts.
	healing_target = true,
	empathic_deflection = true,
}

-- Freeze: tap key/button to toggle on/off. Other channeled powers: hold key/button, release to stop.
local TOGGLE_CHANNELED_POWER_IDS: { [string]: boolean } = {
	molecular_freeze = true,
	astral_projection = true,
}

local function isHoldChanneledPowerId(powerId: string): boolean
	return CHANNELED_POWER_IDS[powerId] == true and TOGGLE_CHANNELED_POWER_IDS[powerId] ~= true
end

local function getClientChanneledPowerId(): string?
	for id, on in activeAbilities do
		if on and CHANNELED_POWER_IDS[id] then
			return id
		end
	end
	return nil
end

local function canSendPowerCast(powerId: string, castAction: string?): boolean
	local activeId = getClientChanneledPowerId()
	if not activeId then
		return true
	end
	if activeId == powerId then
		if castAction == "update" or castAction == "push" or castAction == "stop" then
			return true
		end
		return false
	end
	return false
end

local function refreshAbilityUiLock()
	local blocker = getClientChanneledPowerId()
	for id, btn in powerButtonById do
		btn.Active = if blocker then id == blocker else true
	end
end

local function fireAbility(
	powerId: string,
	target: Instance?,
	hitPosition: Vector3?,
	castAction: string?,
	cameraLook: Vector3?
)
	if not canSendPowerCast(powerId, castAction) then
		return
	end
	local modeToken = getAbilityModeToken(powerId)
	if powerId == "telekinesis" and castAction == "start" and telekinesisStartModeOverride then
		modeToken = telekinesisStartModeOverride
		telekinesisStartModeOverride = nil
	end
	if powerId == "molecular_combustion" and molecularCombustionModeOverride then
		modeToken = molecularCombustionModeOverride
		molecularCombustionModeOverride = nil
	end
	powerCastRemoteEvent:FireServer(powerId, target, hitPosition, castAction, cameraLook, modeToken)
end

local function startChanneledWithAim(powerId: string)
	if activeAbilities[powerId] then
		return
	end
	local cam = Workspace.CurrentCamera
	local targ, hitPos = mouse.Target, mouse.Hit.Position
	if powerId == "empathic_deflection" then
		targ = nil
		hitPos = nil
	elseif powerId == "healing" then
		if not targ then
			return
		end
		local healModel = targ:FindFirstAncestorOfClass("Model")
		local ch = player.Character
		if not healModel or not ch or healModel == ch or not healModel:FindFirstChildOfClass("Humanoid") then
			return
		end
	end
	fireAbility(powerId, targ, hitPos, "start", if cam then cam.CFrame.LookVector else nil)
end

local function stopChanneledWithAim(powerId: string)
	if not activeAbilities[powerId] then
		return
	end
	fireAbility(powerId, mouse.Target, mouse.Hit.Position, "stop", nil)
end

local startTelekinesisHold: () -> ()
local stopTelekinesisHold: () -> ()
local startTelekineticOrbingHold: () -> ()
local stopTelekineticOrbingHold: () -> ()

local SPELLS_IN_FRAME = {
	{ id = "return_to_sender", name = "Return to Sender" },
	{ id = "vanquish_belthazor", name = "Vanquish Belthazor" },
	{ id = "powers_exchange", name = "Power Exchange" },
}

local function clearPowerButtons()
	for _, slot in powerButtons do
		slot:Destroy()
	end
	table.clear(powerButtons)
	table.clear(powerButtonById)
	table.clear(cooldownOverlayById)
	table.clear(cooldownLabelById)
	table.clear(castProgressOverlayById)
	table.clear(activeAbilities)
	table.clear(keybindByPowerId)
	table.clear(powerByKeyCode)
	syncAbilityCameraFov()
	refreshAbilityUiLock()
end

local function setAbilityButtonActive(powerId: string, isActive: boolean)
	activeAbilities[powerId] = isActive
	local button = powerButtonById[powerId]
	if button then
		button.BackgroundColor3 = if isActive then Color3.fromRGB(56, 86, 146) else Color3.fromRGB(18, 23, 36)
	end

	if not isActive then
		if type(setCastProgress) == "function" then
			setCastProgress(powerId, 0, false)
		end
	else
		-- Telekinesis deflective is a short countdown window to the server "push".
		if powerId == "telekinesis" and telekinesisLocalMode == "deflective" then
			if type(setCastProgress) == "function" then
				setCastProgress(powerId, 0, true)
			end
		elseif
			powerId == "telekinetic_orbing"
			or powerId == "astral_projection"
			or powerId == "molecular_freeze"
			or powerId == "levitation"
			or powerId == "healing"
			or powerId == "empathic_deflection"
		then
			local maxEnergy = math.max(CharacterConfig.DefaultEnergy, 1)
			local energy = (player:GetAttribute("Energy") or CharacterConfig.DefaultEnergy) :: number
			if type(setCastProgress) == "function" then
				setCastProgress(powerId, energy / maxEnergy, true)
			end
		end
	end
	if powerId == "telekinesis" then
		telekinesisActive = isActive
		if not isActive then
			telekinesisGrabbedSubject = nil
			telekinesisHoldRequested = false
			telekinesisLocalMode = "dynamic"
		end
	end
	if powerId == "telekinetic_orbing" then
		telekineticOrbingActive = isActive
	end
	if powerId == "levitation" and isActive and not levitationControlLoopRunning then
		levitationControlLoopRunning = true
		task.spawn(function()
			while levitationControlLoopRunning do
				if not activeAbilities.levitation then
					break
				end
				local character = player.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
				local camera = Workspace.CurrentCamera
				if humanoid and camera then
					if selectedCharacter == "Phoebe" and root then
						-- Phoebe: full 3D toward mouse hit (includes vertical / Y).
						local delta = mouse.Hit.Position - root.Position
						local desiredMoveDir = if delta.Magnitude > 0.05 then delta.Unit else humanoid.MoveDirection
						if levitationLastMoveDir then
							desiredMoveDir = levitationLastMoveDir:Lerp(desiredMoveDir, 0.35)
						end
						levitationLastMoveDir = desiredMoveDir
						fireAbility("levitation", nil, desiredMoveDir, "update", desiredMoveDir)
					else
						local desiredMoveDir = humanoid.MoveDirection
						if levitationLastMoveDir then
							desiredMoveDir = levitationLastMoveDir:Lerp(desiredMoveDir, 0.35)
						end
						levitationLastMoveDir = desiredMoveDir

						local desiredLook = camera.CFrame.LookVector
						if levitationLastLook then
							desiredLook = levitationLastLook:Lerp(desiredLook, 0.28)
						end
						if desiredLook.Magnitude > 0.01 then
							desiredLook = desiredLook.Unit
						end
						levitationLastLook = desiredLook

						fireAbility("levitation", nil, desiredMoveDir, "update", desiredLook)
					end
				end
				task.wait(0.06)
			end
			levitationControlLoopRunning = false
		end)
	elseif powerId == "levitation" and not isActive then
		levitationControlLoopRunning = false
		levitationLastMoveDir = nil
		levitationLastLook = nil
	end
	syncAbilityCameraFov()
	refreshAbilityUiLock()
end

local function startCooldownVisual(powerId: string, cooldownSeconds: number)
	local overlay = cooldownOverlayById[powerId]
	local label = cooldownLabelById[powerId]
	if not overlay or not label then
		return
	end
	if cooldownSeconds <= 0 then
		overlay.AnchorPoint = Vector2.new(0.5, 1)
		overlay.Position = UDim2.new(0.5, 0, 1, 0)
		overlay.Size = UDim2.new(1, 0, 1, 0)
		overlay.Visible = false
		label.Text = ""
		return
	end

	overlay.Visible = true
	local startedAt = os.clock()
	task.spawn(function()
		while overlay.Parent do
			local elapsed = os.clock() - startedAt
			local left = math.max(cooldownSeconds - elapsed, 0)
			local ratio = left / cooldownSeconds
			-- Vertical sweep: dimmed band sits on bottom of clip; height shrinks so the circle clears from top → bottom.
			overlay.AnchorPoint = Vector2.new(0.5, 1)
			overlay.Position = UDim2.new(0.5, 0, 1, 0)
			overlay.Size = UDim2.new(1, 0, ratio, 0)
			label.Text = if left > 0 then string.format("%.1f", left) else ""
			if left <= 0 then
				overlay.Size = UDim2.new(1, 0, 1, 0)
				overlay.Visible = false
				break
			end
			task.wait(0.05)
		end
	end)
end

local function setCastProgress(powerId: string, ratio: number, isVisible: boolean)
	local overlay = castProgressOverlayById[powerId]
	if not overlay then
		return
	end
	local clamped = math.clamp(ratio, 0, 1)
	overlay.AnchorPoint = Vector2.new(0.5, 1)
	overlay.Position = UDim2.new(0.5, 0, 1, 0)
	overlay.Size = UDim2.new(1, 0, clamped, 0)
	overlay.Visible = isVisible
	if not isVisible then
		overlay.Visible = false
	end
end

local function updateTelekinesisTrajectoryAndCastProgress()
	if not TRAJECTORY_PREVIEW_ENABLED then
		-- No preview; hide any leftover parts immediately.
		setTrajectoryPreviewVisible(false)
		return
	end
	local shouldShow = telekinesisHoldRequested and telekinesisLocalMode ~= nil
	local subjectPos: Vector3?

	local character = player.Character
	local root = character and (character:FindFirstChild("HumanoidRootPart") :: BasePart?)

	if telekinesisGrabbedSubject and root then
		if (telekinesisGrabbedSubject :: any):IsA("BasePart") then
			subjectPos = (telekinesisGrabbedSubject :: BasePart).Position
		end
	end

	-- Trajectory preview
	local canPreview = shouldShow and root ~= nil and subjectPos ~= nil
	if canPreview then
		ensureTrajectoryPreview()
		local dir: Vector3
		local pushSpeed: number
		if telekinesisLocalMode == "deflective" then
			dir = subjectPos - root.Position
			if dir.Magnitude < 0.01 then
				dir = root.CFrame.LookVector
			end
			pushSpeed = 105
		else
			dir = getTelekinesisAimDirection()
			if dir.Magnitude < 0.01 then
				dir = root.CFrame.LookVector
			end
			pushSpeed = 88
		end
		local channelSpeedMult = if telekinesisChannelStyle == "eye" then 0.8 else 1.2
		pushSpeed *= channelSpeedMult

		local vel = dir.Unit * pushSpeed
		setTrajectoryPreviewVisible(true)
		for i = 1, TK_TRAJ_SEGMENTS do
			local a = if TK_TRAJ_SEGMENTS > 1 then (i - 1) / (TK_TRAJ_SEGMENTS - 1) else 0
			local t = a * TK_TRAJ_MAX_T
			local pos = subjectPos + vel * t + Vector3.new(0, -Workspace.Gravity * 0.5 * t * t, 0)
			local p = trajectoryPreviewParts[i]
			if p and p.Parent then
				p.Position = pos
				p.Transparency = 0.18 + 0.62 * a
			end
		end
	else
		setTrajectoryPreviewVisible(false)
	end

	-- Deflective telekinesis cast-progress countdown (until auto push window ends)
	if telekinesisHoldRequested and telekinesisLocalMode == "deflective" and telekinesisDeflectivePushUntil > -1e8 then
		local remaining = telekinesisDeflectivePushUntil - os.clock()
		local dur = TELEKINESIS_DEFLECTIVE_PUSH_WAIT_SEC
		if remaining > 0 then
			setCastProgress("telekinesis", math.clamp(1 - remaining / dur, 0, 1), true)
		else
			setCastProgress("telekinesis", 0, false)
		end
	else
		-- Hide when not in deflective countdown mode.
		setCastProgress("telekinesis", 0, false)
	end
end

RunService.RenderStepped:Connect(function()
	updateTelekinesisTrajectoryAndCastProgress()
end)

local function buildPowerButtons(characterName: string)
	clearPowerButtons()
	local powers = CharacterConfig.PowersByCharacter[characterName]
	if type(powers) ~= "table" then
		powerFrame.Visible = false
		return
	end

	local usedKeys: { [Enum.KeyCode]: boolean } = {}
	for index, power in powers do
		local keyCode = keybindOverrideByPowerId[power.Id]
		if keyCode then
			usedKeys[keyCode] = true
		else
			for _, candidate in keybindOrder do
				if not usedKeys[candidate] then
					keyCode = candidate
					usedKeys[candidate] = true
					break
				end
			end
		end
		if keyCode then
			keybindByPowerId[power.Id] = keyCode
			powerByKeyCode[keyCode] = { Id = power.Id, Name = power.Name }
		end

		local CIRCLE_PX = 56
		local slot = Instance.new("Frame")
		slot.Name = "PowerSlot_" .. power.Id
		slot.BackgroundTransparency = 1
		slot.BorderSizePixel = 0
		slot.Size = UDim2.new(0, 72, 0, 88)
		slot.LayoutOrder = index
		slot.Parent = powerFrame

		local button = Instance.new("TextButton")
		button.Name = "PowerButton"
		button.AnchorPoint = Vector2.new(0.5, 0)
		button.Position = UDim2.new(0.5, 0, 0, 0)
		button.Size = UDim2.new(0, CIRCLE_PX, 0, CIRCLE_PX)
		button.BackgroundColor3 = Color3.fromRGB(18, 23, 36)
		button.BorderSizePixel = 0
		button.Text = if keyCode then keyCodeToText(keyCode) else "—"
		button.TextColor3 = Color3.fromRGB(230, 232, 245)
		button.TextSize = 22
		button.TextWrapped = false
		button.Font = Enum.Font.GothamBold
		button.AutoButtonColor = true
		button.Parent = slot

		powerButtonById[power.Id] = button

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = button

		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(85, 106, 140)
		stroke.Thickness = 1.2
		stroke.Parent = button

		local mask = Instance.new("Frame")
		mask.Name = "CooldownMask"
		mask.BackgroundTransparency = 1
		mask.BorderSizePixel = 0
		mask.ClipsDescendants = true
		mask.AnchorPoint = Vector2.new(0.5, 0.5)
		mask.Position = UDim2.new(0.5, 0, 0.5, 0)
		-- Inset so the sweep stays inside the rounded fill (not under the stroke).
		mask.Size = UDim2.new(1, -6, 1, -6)
		mask.ZIndex = button.ZIndex + 2
		mask.Parent = button

		local maskCorner = Instance.new("UICorner")
		maskCorner.CornerRadius = UDim.new(1, 0)
		maskCorner.Parent = mask

		local overlay = Instance.new("Frame")
		overlay.Name = "CooldownBar"
		overlay.BackgroundColor3 = Color3.fromRGB(4, 6, 11)
		overlay.BackgroundTransparency = 0.35
		overlay.BorderSizePixel = 0
		overlay.AnchorPoint = Vector2.new(0.5, 1)
		overlay.Position = UDim2.new(0.5, 0, 1, 0)
		overlay.Size = UDim2.new(1, 0, 1, 0)
		overlay.Visible = false
		overlay.ZIndex = mask.ZIndex + 1
		overlay.Parent = mask

		local castOverlay = Instance.new("Frame")
		castOverlay.Name = "CastProgressBar"
		castOverlay.BackgroundColor3 = Color3.fromRGB(40, 120, 220)
		castOverlay.BackgroundTransparency = 0.55
		castOverlay.BorderSizePixel = 0
		castOverlay.AnchorPoint = Vector2.new(0.5, 1)
		castOverlay.Position = UDim2.new(0.5, 0, 1, 0)
		castOverlay.Size = UDim2.new(1, 0, 1, 0)
		castOverlay.Visible = false
		castOverlay.ZIndex = mask.ZIndex + 2
		castOverlay.Parent = mask

		local cooldownLabel = Instance.new("TextLabel")
		cooldownLabel.Name = "CooldownLabel"
		cooldownLabel.BackgroundTransparency = 1
		cooldownLabel.Size = UDim2.new(1, 0, 1, 0)
		cooldownLabel.Position = UDim2.new(0, 0, 0, 0)
		cooldownLabel.Font = Enum.Font.GothamBold
		cooldownLabel.TextSize = 16
		cooldownLabel.TextColor3 = Color3.fromRGB(240, 240, 248)
		cooldownLabel.Text = ""
		cooldownLabel.ZIndex = mask.ZIndex + 3
		cooldownLabel.Parent = mask
		cooldownOverlayById[power.Id] = overlay
		cooldownLabelById[power.Id] = cooldownLabel
		castProgressOverlayById[power.Id] = castOverlay

		local nameUnder = Instance.new("TextLabel")
		nameUnder.Name = "PowerNameLabel"
		nameUnder.BackgroundTransparency = 1
		nameUnder.AnchorPoint = Vector2.new(0.5, 0)
		nameUnder.Position = UDim2.new(0.5, 0, 0, CIRCLE_PX + 4)
		nameUnder.Size = UDim2.new(1, -2, 0, 26)
		nameUnder.Font = Enum.Font.Merriweather
		nameUnder.TextSize = 10
		nameUnder.TextColor3 = Color3.fromRGB(160, 168, 195)
		nameUnder.TextXAlignment = Enum.TextXAlignment.Center
		nameUnder.TextYAlignment = Enum.TextYAlignment.Top
		nameUnder.TextWrapped = true
		nameUnder.TextTruncate = Enum.TextTruncate.AtEnd
		nameUnder.Text = power.Name
		nameUnder.Parent = slot

		if power.Id == "molecular_freeze" then
			button.MouseButton1Click:Connect(function()
				if activeAbilities.molecular_freeze then
					fireAbility("molecular_freeze", mouse.Target, mouse.Hit.Position, "stop", nil)
				else
					local cam = Workspace.CurrentCamera
					fireAbility(
						"molecular_freeze",
						mouse.Target,
						mouse.Hit.Position,
						"start",
						if cam then cam.CFrame.LookVector else nil
					)
				end
			end)
		elseif power.Id == "astral_projection" then
			-- Toggle (click): do not stop on mouse-up.
			button.MouseButton1Click:Connect(function()
				if activeAbilities.astral_projection then
					stopChanneledWithAim("astral_projection")
				else
					startChanneledWithAim("astral_projection")
				end
			end)
		elseif power.Id == "premonition" then
			-- Fixed duration on server (5s); tap only — not a hold channel.
			button.MouseButton1Click:Connect(function()
				local cam = Workspace.CurrentCamera
				fireAbility("premonition", nil, nil, "start", if cam then cam.CFrame.LookVector else nil)
			end)
		elseif isHoldChanneledPowerId(power.Id) then
			button.MouseButton1Down:Connect(function()
				if power.Id == "telekinesis" then
					startTelekinesisHold()
					return
				end
				if power.Id == "telekinetic_orbing" then
					startTelekineticOrbingHold()
					return
				end
				startChanneledWithAim(power.Id)
			end)
			button.MouseButton1Up:Connect(function()
				if power.Id == "telekinesis" then
					stopTelekinesisHold()
					return
				end
				if power.Id == "telekinetic_orbing" then
					stopTelekineticOrbingHold()
					return
				end
				stopChanneledWithAim(power.Id)
			end)
		else
			if power.Id == "molecular_combustion" then
				button.MouseButton1Click:Connect(function()
					fireAbility(power.Id, mouse.Target, mouse.Hit.Position, nil, nil)
				end)
			else
				button.MouseButton1Click:Connect(function()
					fireAbility(power.Id, mouse.Target, mouse.Hit.Position, nil, nil)
				end)
			end
		end

		table.insert(powerButtons, slot)
	end

	refreshAbilityUiLock()
	powerFrame.Visible = #powerButtons > 0
end

local function updatePowersUiForChosenCharacter()
	local role = player:GetAttribute("ChosenCharacter")
	if type(role) ~= "string" or role == "" then
		return
	end
	-- Only rebuild if this role exists in config (guards against nil during respawn).
	if type(CharacterConfig.PowersByCharacter[role]) ~= "table" then
		return
	end
	selectedCharacter = role
	statsFrame.Visible = true
	powerFrame.Visible = true
	buildPowerButtons(role)
	refreshModePanelUi()
end

player:GetAttributeChangedSignal("ChosenCharacter"):Connect(function()
	updatePowersUiForChosenCharacter()
end)
task.defer(updatePowersUiForChosenCharacter)

spellsButton.MouseButton1Click:Connect(function()
	spellsFrame.Visible = not spellsFrame.Visible
end)

for _, spell in SPELLS_IN_FRAME do
	local button = Instance.new("TextButton")
	button.Name = "Spell_" .. spell.id
	button:SetAttribute("SpellId", spell.id)
	button.LayoutOrder = 1
	button.AutoButtonColor = true
	button.BackgroundColor3 = Color3.fromRGB(17, 22, 32)
	button.BorderSizePixel = 0
	button.Size = UDim2.new(1, -12, 0, 24)
	button.TextXAlignment = Enum.TextXAlignment.Left
	button.Font = Enum.Font.Gotham
	button.TextSize = 14
	button.TextColor3 = Color3.fromRGB(220, 225, 240)
	button.Text = spell.name
	button.Parent = spellsFrame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = button

	button.MouseButton1Click:Connect(function()
		requestSpellCast(spell.id)
	end)
end

local function updateBar(fillFrame: Frame, ratio: number)
	local yScale = fillFrame.Size.Y.Scale
	if typeof(yScale) ~= "number" or yScale <= 0 then
		yScale = 0.5
	end
	fillFrame.Size = UDim2.new(math.clamp(ratio, 0, 1), 0, yScale, 0)
end

local function updateHealthUi(humanoid: Humanoid)
	local ch = humanoid.Parent
	local maxHealth: number? = nil
	local health: number? = nil
	if ch and ch:IsA("Model") then
		local cm = ch:GetAttribute("CombatMaxHealth")
		local cv = ch:GetAttribute("CombatHealth")
		if type(cm) == "number" and type(cv) == "number" then
			local m = math.max(cm, 1)
			maxHealth = m
			health = math.clamp(cv, 0, m)
		end
	end
	if maxHealth == nil or health == nil then
		maxHealth = math.max(humanoid.MaxHealth, 1)
		health = math.clamp(humanoid.Health, 0, maxHealth)
	end
	local h = math.floor(health + 0.5)
	local mh = math.floor(maxHealth + 0.5)
	healthLabel.Text = string.format("HP  %d  /  %d", h, mh)
	updateBar(healthFill, health / maxHealth)
end

local function updateEnergyUi(energyValue: number)
	local maxEnergy = math.max(CharacterConfig.DefaultEnergy, 1)
	local current = math.clamp(energyValue, 0, maxEnergy)
	local ratio = current / maxEnergy
	energyLabel.Text = string.format("ENERGY %d/%d", math.floor(current + 0.5), maxEnergy)
	updateBar(energyFill, ratio)

	-- Cast progress: for energy-draining channel powers, show remaining energy as a fill.
	if activeAbilities.telekinetic_orbing then
		setCastProgress("telekinetic_orbing", ratio, true)
	end
	if activeAbilities.astral_projection then
		setCastProgress("astral_projection", ratio, true)
	end
	if activeAbilities.molecular_freeze then
		setCastProgress("molecular_freeze", ratio, true)
	end
	if activeAbilities.levitation then
		setCastProgress("levitation", ratio, true)
	end
	if activeAbilities.healing then
		setCastProgress("healing", ratio, true)
	end
	if activeAbilities.empathic_deflection then
		setCastProgress("empathic_deflection", ratio, true)
	end
end

local COMBUSTION_FUEL_MAX = 100
local function updateCombustionFuelUi(fuelValue: number)
	local cur = math.clamp(fuelValue or 0, 0, COMBUSTION_FUEL_MAX)
	combustionFuelLabel.Text = string.format("%d/%d", math.floor(cur + 0.5), COMBUSTION_FUEL_MAX)
	updateBar(combustionFuelFill, cur / COMBUSTION_FUEL_MAX)
end

local premonitionColorEffect: ColorCorrectionEffect? = nil
local premonitionFovTween: Tween? = nil
local premonitionResetToken = 0
-- This asset is an Animation, not a Sound; loading it on Sound caused "Asset type does not match".
local PREMONITION_GESTURE_ANIM_ID = "rbxassetid://102777154728277"
local premonitionGestureTrack: AnimationTrack? = nil

local function stopPremonitionGesture()
	if premonitionGestureTrack then
		premonitionGestureTrack:Stop(0.15)
		premonitionGestureTrack:Destroy()
		premonitionGestureTrack = nil
	end
end

local function playPremonitionGesture()
	stopPremonitionGesture()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = PREMONITION_GESTURE_ANIM_ID
	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	if not ok or not track then
		anim:Destroy()
		return
	end
	premonitionGestureTrack = track
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = false
	track:Play(0.12, 1, 1)
	track.Stopped:Once(function()
		if premonitionGestureTrack == track then
			premonitionGestureTrack = nil
		end
		anim:Destroy()
	end)
end

local function startTelekinesisHoldWithMode(mode: string)
	if telekinesisActive or telekinesisHoldRequested then
		return
	end
	if not canSendPowerCast("telekinesis", "start") then
		return
	end
	telekinesisGrabbedSubject = nil
	-- Mode token encodes both direction ("dynamic"/"deflective") and channel style ("eye"/"hand").
	telekinesisStartModeOverride = mode .. "_" .. telekinesisChannelStyle
	telekinesisLocalMode = mode
	fireAbility("telekinesis", mouse.Target, mouse.Hit.Position, "start", getTelekinesisAimDirection())
	telekinesisHoldRequested = true
	task.spawn(function()
		while telekinesisHoldRequested do
			if activeAbilities.telekinesis and telekinesisLocalMode ~= "deflective" then
				fireAbility("telekinesis", mouse.Target, getTelekinesisAimPosition(), "update", getTelekinesisAimDirection())
			end
			task.wait(0.016)
		end
	end)
	-- Double-tap E (deflective): as soon as the grab is active, throw — no separate click / release needed.
	if mode == "deflective" then
		telekinesisDeflectivePushUntil = os.clock() + TELEKINESIS_DEFLECTIVE_PUSH_WAIT_SEC
		task.spawn(function()
			local t0 = os.clock()
			while telekinesisHoldRequested and os.clock() - t0 < TELEKINESIS_DEFLECTIVE_PUSH_WAIT_SEC do
				if activeAbilities.telekinesis and telekinesisLocalMode == "deflective" then
					fireAbility("telekinesis", mouse.Target, getTelekinesisAimPosition(), "push", getTelekinesisAimDirection())
					return
				end
				task.wait(0.02)
			end
		end)
	end
end

function startTelekinesisHold()
	if telekinesisActive then
		return
	end
	local mode = noteTelekinesisTargetTap()
	if telekinesisHoldRequested and not telekinesisActive then
		if mode == "deflective" then
			telekinesisHoldRequested = false
			fireAbility("telekinesis", mouse.Target, getTelekinesisAimPosition(), "stop", getTelekinesisAimDirection())
			task.defer(function()
				startTelekinesisHoldWithMode("deflective")
			end)
		end
		return
	end
	if not canSendPowerCast("telekinesis", "start") then
		return
	end
	startTelekinesisHoldWithMode(mode)
end

function stopTelekinesisHold()
	if not telekinesisActive and not telekinesisHoldRequested then
		return
	end
	-- If we are currently trying to auto-send a deflective "push",
	-- do not cancel on key release (otherwise the queued push never fires).
	if telekinesisLocalMode == "deflective" and os.clock() < telekinesisDeflectivePushUntil then
		return
	end
	telekinesisHoldRequested = false
	telekinesisActive = false
	telekinesisLocalMode = "dynamic"
	telekinesisGrabbedSubject = nil
	setAbilityButtonActive("telekinesis", false)
	-- Deflective throw is sent when grab becomes active (see startTelekinesisHoldWithMode). Release only cancels/drops.
	fireAbility("telekinesis", mouse.Target, getTelekinesisAimPosition(), "stop", getTelekinesisAimDirection())
end

function startTelekineticOrbingHold()
	if telekineticOrbingActive then
		return
	end
	if not canSendPowerCast("telekinetic_orbing", "start") then
		return
	end
	fireAbility("telekinetic_orbing", mouse.Target, mouse.Hit.Position, "start", nil)
	-- Wait for server "ability_state" confirmation before marking active.
	telekineticOrbingHoldRequested = true
	task.spawn(function()
		while telekineticOrbingHoldRequested do
			if telekineticOrbingActive then
				fireAbility("telekinetic_orbing", mouse.Target, mouse.Hit.Position, "update", nil)
			end
			task.wait(0.06)
		end
	end)
end

function stopTelekineticOrbingHold()
	if not telekineticOrbingActive and not telekineticOrbingHoldRequested then
		return
	end
	telekineticOrbingHoldRequested = false
	telekineticOrbingActive = false
	setAbilityButtonActive("telekinetic_orbing", false)
	fireAbility("telekinetic_orbing", mouse.Target, mouse.Hit.Position, "stop", nil)
end

local function hookCharacter(character: Model)
	if humanoidConn then
		humanoidConn:Disconnect()
		humanoidConn = nil
	end
	if energyConn then
		energyConn:Disconnect()
		energyConn = nil
	end
	if fuelConn then
		fuelConn:Disconnect()
		fuelConn = nil
	end
	if combatHealthConn then
		combatHealthConn:Disconnect()
		combatHealthConn = nil
	end
	if combatMaxHealthConn then
		combatMaxHealthConn:Disconnect()
		combatMaxHealthConn = nil
	end
	if frozenAttrConn then
		frozenAttrConn:Disconnect()
		frozenAttrConn = nil
	end
	setMolecularFrozenBlur(false)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local function syncFrozenVisual()
		setMolecularFrozenBlur(character:GetAttribute("MolecularFrozen") == true)
	end
	syncFrozenVisual()
	frozenAttrConn = character:GetAttributeChangedSignal("MolecularFrozen"):Connect(syncFrozenVisual)
	character.Destroying:Once(function()
		if frozenAttrConn then
			frozenAttrConn:Disconnect()
			frozenAttrConn = nil
		end
		setMolecularFrozenBlur(false)
	end)

	updateHealthUi(humanoid)
	humanoidConn = humanoid.HealthChanged:Connect(function()
		updateHealthUi(humanoid)
	end)
	humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
		updateHealthUi(humanoid)
	end)
	combatHealthConn = character:GetAttributeChangedSignal("CombatHealth"):Connect(function()
		updateHealthUi(humanoid)
	end)
	combatMaxHealthConn = character:GetAttributeChangedSignal("CombatMaxHealth"):Connect(function()
		updateHealthUi(humanoid)
	end)

	updateEnergyUi((player:GetAttribute("Energy") or CharacterConfig.DefaultEnergy) :: number)
	energyConn = player:GetAttributeChangedSignal("Energy"):Connect(function()
		local energy = player:GetAttribute("Energy")
		if type(energy) == "number" then
			updateEnergyUi(energy)
		end
	end)

	updateCombustionFuelUi((player:GetAttribute("MolecularCombustionFuel") or 0) :: number)
	fuelConn = player:GetAttributeChangedSignal("MolecularCombustionFuel"):Connect(function()
		local fuel = player:GetAttribute("MolecularCombustionFuel")
		if type(fuel) == "number" then
			updateCombustionFuelUi(fuel)
		end
	end)
end

for _, characterName in CharacterConfig.Choices do
	local button = Instance.new("TextButton")
	button.Text = characterName
	button.Font = Enum.Font.GothamBold
	-- Long names (e.g. Belthazor) must not spill out of the grid cell.
	button.TextScaled = true
	button.TextTruncate = Enum.TextTruncate.AtEnd
	button.TextWrapped = false
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.BackgroundColor3 = Color3.fromRGB(21, 28, 41)
	button.AutoButtonColor = true
	button.BorderSizePixel = 0
	button.Parent = buttonsFrame

	local buttonCorner = Instance.new("UICorner")
	buttonCorner.CornerRadius = UDim.new(0, 8)
	buttonCorner.Parent = button

	button.MouseButton1Click:Connect(function()
		selectedCharacter = characterName
		statsFrame.Visible = true
		powerFrame.Visible = true
		chooserFrame.Visible = false
		(selectRemote :: RemoteEvent):FireServer(characterName)
		buildPowerButtons(characterName)
		refreshModePanelUi()

		local character = player.Character
		if character then
			hookCharacter(character)
		end
	end)
end

player.CharacterAdded:Connect(function(character)
	selectedCharacter = nil
	chooserFrame.Visible = true
	statsFrame.Visible = false
	powerFrame.Visible = false
	clearPowerButtons()
	player:SetAttribute("ChosenCharacter", nil)
	telekinesisGrabbedSubject = nil
	stopTelekinesisHold()
	stopTelekineticOrbingHold()
	levitationControlLoopRunning = false
	refreshModePanelUi()
	hookCharacter(character)
end)

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	if not selectedCharacter then
		return
	end
	local powerData = powerByKeyCode[input.KeyCode]
	if not powerData then
		return
	end
	if powerData.Id == "telekinesis" then
		startTelekinesisHold()
	elseif powerData.Id == "telekinetic_orbing" then
		startTelekineticOrbingHold()
	elseif powerData.Id == "molecular_freeze" then
		if activeAbilities.molecular_freeze then
			fireAbility("molecular_freeze", mouse.Target, mouse.Hit.Position, "stop", nil)
		else
			local cam = Workspace.CurrentCamera
			fireAbility(
				"molecular_freeze",
				mouse.Target,
				mouse.Hit.Position,
				"start",
				if cam then cam.CFrame.LookVector else nil
			)
		end
	elseif powerData.Id == "astral_projection" then
		-- Toggle (key): do not stop on key-up.
		if activeAbilities.astral_projection then
			stopChanneledWithAim("astral_projection")
		else
			startChanneledWithAim("astral_projection")
		end
		elseif powerData.Id == "premonition" then
		local cam = Workspace.CurrentCamera
		fireAbility("premonition", nil, nil, "start", if cam then cam.CFrame.LookVector else nil)
	elseif powerData.Id == "molecular_combustion" then
		fireAbility("molecular_combustion", mouse.Target, mouse.Hit.Position, nil, nil)
	elseif
		powerData.Id == "levitation"
		or powerData.Id == "healing"
		or powerData.Id == "empathic_deflection"
	then
		startChanneledWithAim(powerData.Id)
	else
		fireAbility(powerData.Id, mouse.Target, mouse.Hit.Position, nil, nil)
	end
end)

UserInputService.InputEnded:Connect(function(input: InputObject, _gameProcessed: boolean)
	local teleKey = keybindByPowerId.telekinesis
	if teleKey and input.KeyCode == teleKey then
		stopTelekinesisHold()
	end
	local tkOrbKey = keybindByPowerId.telekinetic_orbing
	if tkOrbKey and input.KeyCode == tkOrbKey then
		stopTelekineticOrbingHold()
	end

	local powerData = powerByKeyCode[input.KeyCode]
	if not powerData or not selectedCharacter then
		return
	end
	if powerData.Id == "molecular_freeze" then
		return
	end
	if
		powerData.Id == "levitation"
		or powerData.Id == "healing"
		or powerData.Id == "empathic_deflection"
	then
		stopChanneledWithAim(powerData.Id)
	end
end)

mouse.Button1Down:Connect(function()
	if telekineticOrbingActive and selectedCharacter then
		fireAbility("telekinetic_orbing", mouse.Target, mouse.Hit.Position, "push", nil)
	end
end)

powerCastRemoteEvent.OnClientEvent:Connect(function(action: any, targetHumanoid: any, duration: any)
	if typeof(action) ~= "string" then
		return
	end
	if action == "spell_chat_ok" then
		local chatText = targetHumanoid
		local spellId = duration
		if typeof(chatText) ~= "string" or typeof(spellId) ~= "string" then
			return
		end
		sendSpellChat(chatText)
		if spellId == "powers_exchange" then
			startPowersExchangeTargetSelection()
			return
		end
		if spellId ~= "" then
			task.delay(0.25, function()
				spellCastRemoteEvent:FireServer(spellId, "commit")
			end)
		end
		return
	end
	if action == "ability_cooldown" then
		if typeof(targetHumanoid) == "string" and type(duration) == "number" then
			startCooldownVisual(targetHumanoid, duration)
		end
		return
	end
	if action == "ability_state" then
		if typeof(targetHumanoid) == "string" and type(duration) == "boolean" then
			setAbilityButtonActive(targetHumanoid, duration)
		end
		return
	end
	if action == "telekinesis_grab" then
		telekinesisGrabbedSubject = if typeof(targetHumanoid) == "Instance" then targetHumanoid else nil
		return
	end
	if action == "premonition_stop" then
		stopPremonitionGesture()
		local camera = Workspace.CurrentCamera
		local localCharacter = player.Character
		local localHumanoid = localCharacter and localCharacter:FindFirstChildOfClass("Humanoid")
		if camera and localHumanoid then
			camera.CameraSubject = localHumanoid
		end
		premonitionResetToken += 1
		if premonitionFovTween then
			premonitionFovTween:Cancel()
			premonitionFovTween = nil
		end
		if abilityFovTween then
			abilityFovTween:Cancel()
			abilityFovTween = nil
		end
		if camera then
			syncAbilityCameraFov(true)
		end
		if premonitionColorEffect and premonitionColorEffect.Parent then
			local fadeOut = TweenService:Create(
				premonitionColorEffect,
				TweenInfo.new(0.28, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
				{ Saturation = 0, Contrast = 0, Brightness = 0 }
			)
			fadeOut:Play()
			fadeOut.Completed:Connect(function()
				if premonitionColorEffect and premonitionColorEffect.Parent then
					premonitionColorEffect:Destroy()
				end
				premonitionColorEffect = nil
			end)
		end
		return
	end
	if action ~= "premonition_view" then
		return
	end
	if typeof(targetHumanoid) ~= "Instance" or not targetHumanoid:IsA("Humanoid") then
		return
	end

	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	local previousSubject = camera.CameraSubject
	camera.CameraSubject = targetHumanoid
	premonitionResetToken += 1
	local thisToken = premonitionResetToken
	if abilityFovTween then
		abilityFovTween:Cancel()
		abilityFovTween = nil
	end
	if premonitionFovTween then
		premonitionFovTween:Cancel()
	end
	premonitionFovTween = TweenService:Create(camera, TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		FieldOfView = 84,
	})
	premonitionFovTween:Play()
	playPremonitionGesture()
	if premonitionColorEffect and premonitionColorEffect.Parent then
		premonitionColorEffect:Destroy()
	end
	premonitionColorEffect = Instance.new("ColorCorrectionEffect")
	premonitionColorEffect.Name = "PremonitionGray"
	premonitionColorEffect.Saturation = 0
	premonitionColorEffect.Contrast = 0
	premonitionColorEffect.Brightness = 0
	premonitionColorEffect.Parent = Lighting
	TweenService:Create(
		premonitionColorEffect,
		TweenInfo.new(0.28, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{ Saturation = -1, Contrast = 0.2, Brightness = -0.05 }
	):Play()

	task.delay(type(duration) == "number" and duration or 5, function()
		if thisToken ~= premonitionResetToken then
			return
		end
		stopPremonitionGesture()
		if not camera.Parent then
			return
		end
		local localCharacter = player.Character
		local localHumanoid = localCharacter and localCharacter:FindFirstChildOfClass("Humanoid")
		if localHumanoid then
			camera.CameraSubject = localHumanoid
		elseif previousSubject then
			camera.CameraSubject = previousSubject
		end
		if premonitionFovTween then
			premonitionFovTween:Cancel()
			premonitionFovTween = nil
		end
		if abilityFovTween then
			abilityFovTween:Cancel()
			abilityFovTween = nil
		end
		syncAbilityCameraFov(true)
		if premonitionColorEffect and premonitionColorEffect.Parent then
			local fadeOut = TweenService:Create(
				premonitionColorEffect,
				TweenInfo.new(0.28, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
				{ Saturation = 0, Contrast = 0, Brightness = 0 }
			)
			fadeOut:Play()
			fadeOut.Completed:Connect(function()
				if premonitionColorEffect and premonitionColorEffect.Parent then
					premonitionColorEffect:Destroy()
				end
				premonitionColorEffect = nil
			end)
		end
	end)
end)
