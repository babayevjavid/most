local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local shared = ReplicatedStorage:WaitForChild("Shared", 30)
if not shared then
	error("[CharacterSelect] ReplicatedStorage.Shared missing.")
end

local characterConfigModule = shared:WaitForChild("CharacterConfig", 10)
local ok, CharacterConfig = pcall(require, characterConfigModule)
if not ok or type(CharacterConfig) ~= "table" then
	error("[CharacterSelect] Failed to require CharacterConfig.")
end

local gameHealthModule = shared:WaitForChild("GameHealth", 10)
local okGh, GameHealth = pcall(require, gameHealthModule)
if not okGh or type(GameHealth) ~= "table" then
	error("[CharacterSelect] Failed to require GameHealth.")
end

local validChoices: { [string]: boolean } = {}
for _, name in CharacterConfig.Choices do
	validChoices[name] = true
end

local function ensureSelectionRemote(): RemoteEvent
	local folder = ReplicatedStorage:FindFirstChild(CharacterConfig.RemotesFolderName)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = CharacterConfig.RemotesFolderName
		folder.Parent = ReplicatedStorage
	end

	local ev = folder:FindFirstChild(CharacterConfig.SelectionRemoteName)
	if not ev then
		ev = Instance.new("RemoteEvent")
		ev.Name = CharacterConfig.SelectionRemoteName
		ev.Parent = folder
	elseif not ev:IsA("RemoteEvent") then
		error("[CharacterSelect] Selection event must be a RemoteEvent.")
	end

	return ev :: RemoteEvent
end

local selectRemote = ensureSelectionRemote()

local BLUE_BAR_BG = Color3.fromRGB(32, 48, 82)
local BLUE_BAR_STROKE = Color3.fromRGB(72, 118, 168)
local HEALTH_FILL = Color3.fromRGB(74, 197, 130)
local TEXT_MAIN = Color3.fromRGB(232, 240, 255)
local TEXT_SUB = Color3.fromRGB(170, 200, 235)

local function destroyLegacyBillboard(head: BasePart)
	local old = head:FindFirstChild("ChosenCharacterBillboard")
	if old then
		old:Destroy()
	end
end

local function getOrCreateOverheadBillboard(character: Model): BillboardGui?
	local head = character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return nil
	end

	destroyLegacyBillboard(head)

	local existing = head:FindFirstChild("CharacterOverheadInfo")
	if existing and existing:IsA("BillboardGui") then
		return existing
	end

	-- Requested font. Some places don't have this enum member, so we must look it up safely.
	local accFont: Enum.Font? = nil
	do
		local okFont, fontVal = pcall(function()
			return (Enum.Font :: any).AccanthisADFStd
		end)
		if okFont and typeof(fontVal) == "EnumItem" then
			accFont = fontVal :: Enum.Font
		end
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "CharacterOverheadInfo"
	billboard.Size = UDim2.new(5, 0, 2, 0)
	billboard.StudsOffset = Vector3.new(0, 2, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 1
	billboard.MaxDistance = 100
	billboard.Parent = head

	local root = Instance.new("Frame")
	root.Name = "OverheadRoot"
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = billboard

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0.02, 0)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Top
	list.Parent = root

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.04, 0)
	pad.PaddingBottom = UDim.new(0.04, 0)
	pad.PaddingLeft = UDim.new(0.04, 0)
	pad.PaddingRight = UDim.new(0.04, 0)
	pad.Parent = root

	local namePlayer = Instance.new("TextLabel")
	namePlayer.Name = "PlayerName"
	namePlayer.BackgroundTransparency = 1
	namePlayer.Size = UDim2.new(1, 0, 0.22, 0)
	namePlayer.Font = if accFont then accFont else Enum.Font.GothamBold
	namePlayer.TextScaled = true
	namePlayer.TextColor3 = TEXT_MAIN
	namePlayer.TextXAlignment = Enum.TextXAlignment.Center
	namePlayer.TextTruncate = Enum.TextTruncate.AtEnd
	namePlayer.LayoutOrder = 1
	namePlayer.Parent = root

	local nameChar = Instance.new("TextLabel")
	nameChar.Name = "CharacterName"
	nameChar.BackgroundTransparency = 1
	nameChar.Size = UDim2.new(1, 0, 0.18, 0)
	nameChar.Font = if accFont then accFont else Enum.Font.GothamMedium
	nameChar.TextScaled = true
	nameChar.TextColor3 = TEXT_SUB
	nameChar.TextXAlignment = Enum.TextXAlignment.Center
	nameChar.TextTruncate = Enum.TextTruncate.AtEnd
	nameChar.LayoutOrder = 2
	nameChar.Parent = root

	local healthRow = Instance.new("Frame")
	healthRow.Name = "HealthRow"
	healthRow.BackgroundTransparency = 1
	healthRow.Size = UDim2.new(1, 0, 0.38, 0)
	healthRow.LayoutOrder = 3
	healthRow.Parent = root

	local barBg = Instance.new("Frame")
	barBg.Name = "HealthBarBg"
	barBg.BackgroundColor3 = BLUE_BAR_BG
	barBg.BackgroundTransparency = 0.15
	barBg.BorderSizePixel = 0
	barBg.AnchorPoint = Vector2.new(0.5, 0.5)
	barBg.Position = UDim2.new(0.5, 0, 0.5, 0)
	barBg.Size = UDim2.new(1, 0, 0.55, 0)
	barBg.Parent = healthRow

	local bgCorner = Instance.new("UICorner")
	bgCorner.CornerRadius = UDim.new(0.2, 0)
	bgCorner.Parent = barBg

	local bgStroke = Instance.new("UIStroke")
	bgStroke.Thickness = 0.5
	bgStroke.Color = BLUE_BAR_STROKE
	bgStroke.Transparency = 0.4
	bgStroke.Parent = barBg

	local barFill = Instance.new("Frame")
	barFill.Name = "HealthBarFill"
	barFill.BackgroundColor3 = HEALTH_FILL
	barFill.BorderSizePixel = 0
	barFill.Size = UDim2.new(1, 0, 1, 0)
	barFill.ZIndex = 1
	barFill.Parent = barBg

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0.2, 0)
	fillCorner.Parent = barFill

	local healthText = Instance.new("TextLabel")
	healthText.Name = "HealthText"
	healthText.BackgroundTransparency = 1
	healthText.Size = UDim2.fromScale(1, 1)
	healthText.Font = if accFont then accFont else Enum.Font.GothamBold
	healthText.TextScaled = true
	healthText.TextColor3 = TEXT_MAIN
	healthText.TextXAlignment = Enum.TextXAlignment.Center
	healthText.TextYAlignment = Enum.TextYAlignment.Center
	healthText.ZIndex = 2
	healthText.Parent = barBg

	return billboard
end

local function fullCharacterName(chosenRole: string): string
	if chosenRole == "Piper" or chosenRole == "Prue" or chosenRole == "Phoebe" then
		return chosenRole .. " Halliwell"
	end
	if chosenRole == "Paige" then
		return "Paige Matthews"
	end
	return chosenRole
end

local function updateOverheadBillboard(player: Player, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local billboard = getOrCreateOverheadBillboard(character)
	if not billboard then
		return
	end

	local root = billboard:FindFirstChild("OverheadRoot")
	if not root or not root:IsA("Frame") then
		return
	end

	local displayName = player.DisplayName
	if displayName == "" then
		displayName = player.Name
	end

	local chosen = player:GetAttribute("ChosenCharacter")
	local charLine: string
	if type(chosen) == "string" and chosen ~= "" then
		charLine = fullCharacterName(chosen)
	else
		charLine = "—"
	end

	local namePlayer = root:FindFirstChild("PlayerName")
	if namePlayer and namePlayer:IsA("TextLabel") then
		namePlayer.Text = displayName
	end
	local nameChar = root:FindFirstChild("CharacterName")
	if nameChar and nameChar:IsA("TextLabel") then
		nameChar.Text = charLine
	end

	local maxHealth: number
	local health: number
	local chAttr = character:GetAttribute("CombatMaxHealth")
	local hAttr = character:GetAttribute("CombatHealth")
	if type(chAttr) == "number" and type(hAttr) == "number" then
		maxHealth = math.max(chAttr, 1)
		health = math.clamp(hAttr, 0, maxHealth)
	else
		maxHealth = math.max(humanoid.MaxHealth, 1)
		health = math.clamp(humanoid.Health, 0, maxHealth)
	end
	local h = math.floor(health + 0.5)
	local mh = math.floor(maxHealth + 0.5)
	local ratio = health / maxHealth

	local healthRow = root:FindFirstChild("HealthRow")
	if healthRow and healthRow:IsA("Frame") then
		local barBg = healthRow:FindFirstChild("HealthBarBg")
		if barBg and barBg:IsA("Frame") then
			local barFill = barBg:FindFirstChild("HealthBarFill")
			if barFill and barFill:IsA("Frame") then
				barFill.Size = UDim2.new(ratio, 0, 1, 0)
			end
			local healthText = barBg:FindFirstChild("HealthText")
			if healthText and healthText:IsA("TextLabel") then
				healthText.Text = string.format("Health: %d / %d", h, mh)
			end
		end
	end
end

local healthConnections: { [Player]: { RBXScriptConnection } } = {}
local chosenAttrConnections: { [Player]: RBXScriptConnection } = {}

local function clearHealthConnections(player: Player)
	local list = healthConnections[player]
	if list then
		for _, c in list do
			c:Disconnect()
		end
		healthConnections[player] = nil
	end
end

local function clearChosenAttrConnection(player: Player)
	local c = chosenAttrConnections[player]
	if c then
		c:Disconnect()
		chosenAttrConnections[player] = nil
	end
end

local function cleanupCharacterUi(character: Model)
	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		local billboard = head:FindFirstChild("CharacterOverheadInfo")
		if billboard then
			billboard:Destroy()
		end
		local legacy = head:FindFirstChild("ChosenCharacterBillboard")
		if legacy then
			legacy:Destroy()
		end
	end
end

local function applySelectionToCharacter(player: Player, character: Model)
	local chosen = player:GetAttribute("ChosenCharacter")
	if type(chosen) == "string" and chosen ~= "" then
		character:SetAttribute("ChosenCharacter", chosen)
		player:SetAttribute("Energy", CharacterConfig.DefaultEnergy)
		character:SetAttribute("Energy", CharacterConfig.DefaultEnergy)
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local maxH = (CharacterConfig :: any).CombatMaxHealth
	if type(maxH) ~= "number" then
		maxH = 100
	end
	if chosen == "Belthazor" then
		local bMax = (CharacterConfig :: any).BelthazorCombatHealth
		if type(bMax) == "number" then
			maxH = bMax
		end
	end
	GameHealth.initCharacter(character, maxH)

	clearHealthConnections(player)
	updateOverheadBillboard(player, character)

	local conns: { RBXScriptConnection } = {}
	table.insert(conns, humanoid.HealthChanged:Connect(function()
		updateOverheadBillboard(player, character)
	end))
	table.insert(conns, humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
		updateOverheadBillboard(player, character)
	end))
	table.insert(conns, character:GetAttributeChangedSignal("CombatHealth"):Connect(function()
		updateOverheadBillboard(player, character)
	end))
	table.insert(conns, character:GetAttributeChangedSignal("CombatMaxHealth"):Connect(function()
		updateOverheadBillboard(player, character)
	end))
	healthConnections[player] = conns
end

local function bindChosenAttribute(player: Player)
	clearChosenAttrConnection(player)
	chosenAttrConnections[player] = player:GetAttributeChangedSignal("ChosenCharacter"):Connect(function()
		local character = player.Character
		if character then
			updateOverheadBillboard(player, character)
		end
	end)
end

selectRemote.OnServerEvent:Connect(function(player: Player, characterName: string)
	if type(characterName) ~= "string" or not validChoices[characterName] then
		return
	end

	player:SetAttribute("ChosenCharacter", characterName)
	if player:GetAttribute("Energy") == nil then
		player:SetAttribute("Energy", CharacterConfig.DefaultEnergy)
	end

	local character = player.Character
	if character then
		applySelectionToCharacter(player, character)
	end
end)

local function onPlayerAdded(player: Player)
	bindChosenAttribute(player)

	player.CharacterAdded:Connect(function(character)
		task.wait(0.2)
		applySelectionToCharacter(player, character)
	end)

	player.CharacterRemoving:Connect(function(character)
		clearHealthConnections(player)
		cleanupCharacterUi(character)
		player:SetAttribute("ChosenCharacter", nil)
		player:SetAttribute("Energy", CharacterConfig.DefaultEnergy)
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)

for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
	local char = player.Character
	if char then
		task.defer(function()
			applySelectionToCharacter(player, char)
		end)
	end
end

Players.PlayerRemoving:Connect(function(player)
	clearHealthConnections(player)
	clearChosenAttrConnection(player)
end)
