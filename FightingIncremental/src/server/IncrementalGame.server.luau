local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local DataStoreService = game:GetService("DataStoreService")

local shared = ReplicatedStorage:WaitForChild("Shared")
local IncrementalConfig = require(shared:WaitForChild("IncrementalConfig"))

type PlayerValues = {
	Strength: IntValue,
	Durability: IntValue,
	Speed: IntValue,
	JumpPower: IntValue,
	Coins: IntValue,
	Power: IntValue,
	Rebirths: IntValue,
}

local playerValueMap: { [Player]: PlayerValues } = {}
local portalDebounce: { [Player]: number } = {}
local playerLoadedData: { [Player]: boolean } = {}

local DATASTORE_NAME = "IncrementalPlayerData_v1"
local playerDataStore = DataStoreService:GetDataStore(DATASTORE_NAME)

type SavedData = {
	Strength: number,
	Durability: number,
	Speed: number,
	JumpPower: number,
	Coins: number,
	Rebirths: number,
}

local function makeSaveKey(player: Player): string
	return ("u_%d"):format(player.UserId)
end

local function sanitizeNumber(value: any, defaultValue: number): number
	if type(value) ~= "number" then
		return defaultValue
	end
	return math.max(0, math.floor(value))
end

local function extractSaveData(values: PlayerValues): SavedData
	return {
		Strength = sanitizeNumber(values.Strength.Value, 0),
		Durability = sanitizeNumber(values.Durability.Value, 0),
		Speed = sanitizeNumber(values.Speed.Value, 0),
		JumpPower = sanitizeNumber(values.JumpPower.Value, 0),
		Coins = sanitizeNumber(values.Coins.Value, IncrementalConfig.StartingCoins),
		Rebirths = sanitizeNumber(values.Rebirths.Value, 0),
	}
end

local function writeData(player: Player, values: PlayerValues): boolean
	local key = makeSaveKey(player)
	local payload = extractSaveData(values)

	local success, err = pcall(function()
		playerDataStore:SetAsync(key, payload)
	end)

	if not success then
		warn(("[IncrementalData] Save failed for %s: %s"):format(player.Name, tostring(err)))
	end

	return success
end

local function readData(player: Player): SavedData?
	local key = makeSaveKey(player)
	local success, result = pcall(function()
		return playerDataStore:GetAsync(key)
	end)

	if not success then
		warn(("[IncrementalData] Load failed for %s: %s"):format(player.Name, tostring(result)))
		return nil
	end

	if type(result) ~= "table" then
		return nil
	end

	local data = result :: { [string]: any }
	return {
		Strength = sanitizeNumber(data.Strength, 0),
		Durability = sanitizeNumber(data.Durability, 0),
		Speed = sanitizeNumber(data.Speed, 0),
		JumpPower = sanitizeNumber(data.JumpPower, 0),
		Coins = sanitizeNumber(data.Coins, IncrementalConfig.StartingCoins),
		Rebirths = sanitizeNumber(data.Rebirths, 0),
	}
end

local function ensureRemotes()
	local remotes = ReplicatedStorage:FindFirstChild("IncrementalRemotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "IncrementalRemotes"
		remotes.Parent = ReplicatedStorage
	end

	local function getOrCreateRemote(name: string): RemoteEvent
		local existing = remotes:FindFirstChild(name)
		if existing and existing:IsA("RemoteEvent") then
			return existing
		end

		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = remotes
		return remote
	end

	return {
		TrainTap = getOrCreateRemote("TrainTap"),
		TrainStat = getOrCreateRemote("TrainStat"),
		RequestRebirth = getOrCreateRemote("RequestRebirth"),
		Notify = getOrCreateRemote("Notify"),
	}
end

local Remotes = ensureRemotes()

local function createStatValue(parent: Instance, name: string, initial: number): IntValue
	local value = Instance.new("IntValue")
	value.Name = name
	value.Value = initial
	value.Parent = parent
	return value
end

local function getPower(values: PlayerValues): number
	return IncrementalConfig.GetPower(
		values.Strength.Value,
		values.Durability.Value,
		values.Speed.Value,
		values.JumpPower.Value
	)
end

local function syncPower(values: PlayerValues)
	values.Power.Value = getPower(values)
end

local function applyCharacterStats(player: Player)
	local values = playerValueMap[player]
	if not values then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local walkSpeed = IncrementalConfig.BaseWalkSpeed + (values.Speed.Value * IncrementalConfig.SpeedPerPoint)
	humanoid.WalkSpeed = math.max(IncrementalConfig.StartingWalkSpeed, walkSpeed)
	humanoid.UseJumpPower = true
	humanoid.JumpPower = if values.JumpPower.Value > 0 then (IncrementalConfig.BaseJumpPower + values.JumpPower.Value * IncrementalConfig.JumpPerPoint) else 0

	local maxHealth = IncrementalConfig.BaseHealth + (values.Durability.Value * IncrementalConfig.HealthPerDurability)
	local previousHealthRatio = if humanoid.MaxHealth > 0 then humanoid.Health / humanoid.MaxHealth else 1
	humanoid.MaxHealth = maxHealth
	humanoid.Health = math.clamp(maxHealth * previousHealthRatio, 1, maxHealth)
end

local function notify(player: Player, message: string, tone: string?)
	Remotes.Notify:FireClient(player, {
		text = message,
		tone = tone or "info",
	})
end

local function getRebirthMultiplier(rebirths: number): number
	return 1 + (rebirths * IncrementalConfig.RebirthCoinBonus)
end

local function performTrainTap(player: Player)
	local values = playerValueMap[player]
	if not values then
		return
	end

	local baseGain = IncrementalConfig.CoinClickBase + (values.Strength.Value * IncrementalConfig.CoinClickFromStrength)
	local rebirthMultiplier = getRebirthMultiplier(values.Rebirths.Value)
	local gainedCoins = math.max(1, math.floor((baseGain * rebirthMultiplier) + 0.5))

	values.Coins.Value += gainedCoins

	Remotes.Notify:FireClient(player, {
		text = ("+%d coins"):format(gainedCoins),
		tone = "gain",
		trainPulse = true,
	})
end

local function performTrainStat(player: Player, statName: string)
	local values = playerValueMap[player]
	if not values then
		return
	end

	local statValue = values[statName]
	if not statValue then
		return
	end

	local cost = IncrementalConfig.GetStatCost(statName, statValue.Value)
	if values.Coins.Value < cost then
		notify(player, ("Not enough coins for %s"):format(statName), "warn")
		return
	end

	values.Coins.Value -= cost
	statValue.Value += 1
	syncPower(values)
	applyCharacterStats(player)

	notify(player, ("%s increased to %d"):format(statName, statValue.Value), "success")
end

local function performRebirth(player: Player)
	local values = playerValueMap[player]
	if not values then
		return
	end

	if values.Power.Value < IncrementalConfig.RebirthRequirement then
		notify(player, ("Need %d power to rebirth"):format(IncrementalConfig.RebirthRequirement), "warn")
		return
	end

	values.Rebirths.Value += 1
	values.Strength.Value = 0
	values.Durability.Value = 0
	values.Speed.Value = 0
	values.JumpPower.Value = 0
	values.Coins.Value = IncrementalConfig.StartingCoins
	syncPower(values)
	applyCharacterStats(player)

	notify(player, ("Rebirth #%d complete! Permanent coin bonus increased."):format(values.Rebirths.Value), "success")
end

local function ensureArenaObjects()
	local arenaSpawn = Workspace:FindFirstChild("ArenaSpawn")
	if not arenaSpawn then
		arenaSpawn = Instance.new("SpawnLocation")
		arenaSpawn.Name = "ArenaSpawn"
		arenaSpawn.Size = Vector3.new(10, 1, 10)
		arenaSpawn.Position = Vector3.new(0, 3, 220)
		arenaSpawn.Anchored = true
		arenaSpawn.Neutral = true
		arenaSpawn.Parent = Workspace
	end

	local mainSpawn = Workspace:FindFirstChild("MainSpawn")
	if not mainSpawn then
		mainSpawn = Instance.new("SpawnLocation")
		mainSpawn.Name = "MainSpawn"
		mainSpawn.Size = Vector3.new(10, 1, 10)
		mainSpawn.Position = Vector3.new(0, 3, 0)
		mainSpawn.Anchored = true
		mainSpawn.Neutral = true
		mainSpawn.Parent = Workspace
	end

	local portalPart = Workspace:FindFirstChild("PowerPortal")
	if not portalPart then
		portalPart = Instance.new("Part")
		portalPart.Name = "PowerPortal"
		portalPart.Shape = Enum.PartType.Cylinder
		portalPart.Material = Enum.Material.Neon
		portalPart.Color = Color3.fromRGB(89, 51, 255)
		portalPart.Size = Vector3.new(6, 1, 6)
		portalPart.CFrame = CFrame.new(20, 3, 0) * CFrame.Angles(0, 0, math.rad(90))
		portalPart.Anchored = true
		portalPart.Parent = Workspace
	end

	local billboard = portalPart:FindFirstChild("PortalBillboard")
	if not billboard then
		billboard = Instance.new("BillboardGui")
		billboard.Name = "PortalBillboard"
		billboard.AlwaysOnTop = true
		billboard.Size = UDim2.fromOffset(230, 60)
		billboard.StudsOffset = Vector3.new(0, 4.3, 0)
		billboard.Parent = portalPart

		local label = Instance.new("TextLabel")
		label.Name = "PortalText"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 0.3
		label.BackgroundColor3 = Color3.fromRGB(20, 12, 55)
		label.TextColor3 = Color3.fromRGB(245, 245, 255)
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.Text = ("Arena Portal\nNeed %d Power"):format(IncrementalConfig.PortalRequirement)
		label.Parent = billboard

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = label
	end

	return portalPart, arenaSpawn
end

local portalPart, arenaSpawn = ensureArenaObjects()

local function createGroundButton(parent: Instance, buttonName: string, position: Vector3, color: Color3, promptText: string, callback: (Player) -> ())
	local buttonPart = parent:FindFirstChild(buttonName)
	if not buttonPart or not buttonPart:IsA("Part") then
		if buttonPart then
			buttonPart:Destroy()
		end
		buttonPart = Instance.new("Part")
		buttonPart.Name = buttonName
		buttonPart.Size = Vector3.new(10, 1, 10)
		buttonPart.Anchored = true
		buttonPart.Material = Enum.Material.SmoothPlastic
		buttonPart.TopSurface = Enum.SurfaceType.Smooth
		buttonPart.BottomSurface = Enum.SurfaceType.Smooth
		buttonPart.Parent = parent
	end

	buttonPart.Position = position
	buttonPart.Color = color

	local prompt = buttonPart:FindFirstChild("UsePrompt")
	if not prompt or not prompt:IsA("ProximityPrompt") then
		if prompt then
			prompt:Destroy()
		end
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "UsePrompt"
		prompt.RequiresLineOfSight = false
		prompt.MaxActivationDistance = 12
		prompt.HoldDuration = 0
		prompt.Parent = buttonPart
	end

	prompt.ObjectText = buttonName
	prompt.ActionText = promptText

	local billboard = buttonPart:FindFirstChild("ButtonBillboard")
	if not billboard or not billboard:IsA("BillboardGui") then
		if billboard then
			billboard:Destroy()
		end
		billboard = Instance.new("BillboardGui")
		billboard.Name = "ButtonBillboard"
		billboard.AlwaysOnTop = true
		billboard.Size = UDim2.fromOffset(220, 52)
		billboard.StudsOffset = Vector3.new(0, 3.5, 0)
		billboard.Parent = buttonPart

		local text = Instance.new("TextLabel")
		text.Name = "Label"
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 0.2
		text.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
		text.TextColor3 = Color3.fromRGB(248, 248, 248)
		text.Font = Enum.Font.GothamSemibold
		text.TextScaled = true
		text.Parent = billboard

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = text
	end

	local label = billboard:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.Text = buttonName
	end

	prompt.Triggered:Connect(callback)
end

local function ensureTrainingButtons()
	local folder = Workspace:FindFirstChild("TrainingButtons")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "TrainingButtons"
		folder.Parent = Workspace
	end

	local base = Vector3.new(-24, 2.5, 0)
	createGroundButton(folder, "Train", base + Vector3.new(0, 0, 0), Color3.fromRGB(40, 110, 240), "Train Coins", function(player)
		performTrainTap(player)
	end)
	createGroundButton(folder, "Strength", base + Vector3.new(12, 0, 0), Color3.fromRGB(188, 82, 82), "Upgrade Strength", function(player)
		performTrainStat(player, "Strength")
	end)
	createGroundButton(folder, "Durability", base + Vector3.new(24, 0, 0), Color3.fromRGB(75, 164, 90), "Upgrade Durability", function(player)
		performTrainStat(player, "Durability")
	end)
	createGroundButton(folder, "Speed", base + Vector3.new(36, 0, 0), Color3.fromRGB(90, 120, 240), "Upgrade Speed", function(player)
		performTrainStat(player, "Speed")
	end)
	createGroundButton(folder, "JumpPower", base + Vector3.new(48, 0, 0), Color3.fromRGB(172, 113, 246), "Upgrade Jump", function(player)
		performTrainStat(player, "JumpPower")
	end)
	createGroundButton(folder, "Rebirth", base + Vector3.new(60, 0, 0), Color3.fromRGB(235, 143, 57), "Attempt Rebirth", function(player)
		performRebirth(player)
	end)
end

ensureTrainingButtons()

portalPart.Touched:Connect(function(hit: BasePart)
	local character = hit.Parent
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end

	local now = os.clock()
	local lastTouch = portalDebounce[player]
	if lastTouch and now - lastTouch < 1 then
		return
	end
	portalDebounce[player] = now

	local values = playerValueMap[player]
	if not values then
		return
	end

	if values.Power.Value < IncrementalConfig.PortalRequirement then
		notify(player, ("Need %d power to enter arena"):format(IncrementalConfig.PortalRequirement), "warn")
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if root and arenaSpawn then
		root.CFrame = arenaSpawn.CFrame + Vector3.new(0, 4, 0)
		notify(player, "Teleported to arena. Fight!", "success")
	end
end)

local function buildPlayerValues(player: Player): PlayerValues
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local values: PlayerValues = {
		Strength = createStatValue(leaderstats, "Strength", 0),
		Durability = createStatValue(leaderstats, "Durability", 0),
		Speed = createStatValue(leaderstats, "Speed", 0),
		JumpPower = createStatValue(leaderstats, "JumpPower", 0),
		Coins = createStatValue(leaderstats, "Coins", IncrementalConfig.StartingCoins),
		Power = createStatValue(leaderstats, "Power", 0),
		Rebirths = createStatValue(leaderstats, "Rebirths", 0),
	}

	syncPower(values)
	return values
end

local function onPlayerAdded(player: Player)
	local values = buildPlayerValues(player)
	playerValueMap[player] = values
	playerLoadedData[player] = false

	local loadedData = readData(player)
	if loadedData then
		values.Strength.Value = loadedData.Strength
		values.Durability.Value = loadedData.Durability
		values.Speed.Value = loadedData.Speed
		values.JumpPower.Value = loadedData.JumpPower
		values.Coins.Value = loadedData.Coins
		values.Rebirths.Value = loadedData.Rebirths
		syncPower(values)
	end
	playerLoadedData[player] = true

	player.CharacterAdded:Connect(function()
		task.wait(0.15)
		applyCharacterStats(player)
	end)
end

local function onPlayerRemoving(player: Player)
	local values = playerValueMap[player]
	if values and playerLoadedData[player] then
		writeData(player, values)
	end
	playerValueMap[player] = nil
	portalDebounce[player] = nil
	playerLoadedData[player] = nil
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

task.spawn(function()
	while true do
		task.wait(60)
		for player, values in playerValueMap do
			if playerLoadedData[player] then
				writeData(player, values)
			end
		end
	end
end)

game:BindToClose(function()
	for player, values in playerValueMap do
		if playerLoadedData[player] then
			writeData(player, values)
		end
	end
end)

Remotes.TrainTap.OnServerEvent:Connect(function(player: Player)
	performTrainTap(player)
end)

Remotes.TrainStat.OnServerEvent:Connect(function(player: Player, statName: string)
	if type(statName) ~= "string" then
		return
	end
	performTrainStat(player, statName)
end)

Remotes.RequestRebirth.OnServerEvent:Connect(function(player: Player)
	performRebirth(player)
end)
