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

local function getOrCreateBillboard(character: Model): BillboardGui?
	local head = character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return nil
	end

	local existing = head:FindFirstChild("ChosenCharacterBillboard")
	if existing and existing:IsA("BillboardGui") then
		return existing
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "ChosenCharacterBillboard"
	billboard.Size = UDim2.fromOffset(230, 80)
	billboard.StudsOffset = Vector3.new(0, 2.8, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 100
	billboard.Parent = head

	local frame = Instance.new("Frame")
	frame.Name = "Container"
	frame.BackgroundColor3 = Color3.fromRGB(30, 27, 46)
	frame.BackgroundTransparency = 0.2
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromScale(1, 1)
	frame.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1.5
	stroke.Color = Color3.fromRGB(181, 150, 255)
	stroke.Transparency = 0.15
	stroke.Parent = frame

	local label = Instance.new("TextLabel")
	label.Name = "InfoText"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextScaled = true
	label.TextWrapped = true
	label.Parent = frame

	return billboard
end

local function updateBillboardText(player: Player, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local selectedCharacter = player:GetAttribute("ChosenCharacter")
	if type(selectedCharacter) ~= "string" then
		selectedCharacter = "Unknown"
	end

	local billboard = getOrCreateBillboard(character)
	if not billboard then
		return
	end

	local container = billboard:FindFirstChild("Container")
	if not container or not container:IsA("Frame") then
		return
	end
	local label = container:FindFirstChild("InfoText")
	if not label or not label:IsA("TextLabel") then
		return
	end

	label.Text = string.format("%s\n%s\nHealth: %d", selectedCharacter, player.Name, math.floor(humanoid.Health + 0.5))
end

local healthConnections: { [Player]: RBXScriptConnection } = {}

local function clearHealthConnection(player: Player)
	local conn = healthConnections[player]
	if conn then
		conn:Disconnect()
		healthConnections[player] = nil
	end
end

local function applySelectionToCharacter(player: Player, character: Model)
	local chosen = player:GetAttribute("ChosenCharacter")
	if type(chosen) ~= "string" then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	character:SetAttribute("ChosenCharacter", chosen)
	character:SetAttribute("Energy", player:GetAttribute("Energy") or CharacterConfig.DefaultEnergy)

	updateBillboardText(player, character)
	clearHealthConnection(player)
	healthConnections[player] = humanoid.HealthChanged:Connect(function()
		updateBillboardText(player, character)
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

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		task.wait(0.2)
		applySelectionToCharacter(player, character)
	end)

	player.CharacterRemoving:Connect(function()
		clearHealthConnection(player)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	clearHealthConnection(player)
end)
