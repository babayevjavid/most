local DataStoreService = game:GetService("DataStoreService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Elements = require(Shared:WaitForChild("Elements"))
local TycoonConfig = require(Shared:WaitForChild("TycoonConfig"))

local playerDataStore = DataStoreService:GetDataStore("ElementalTycoonPlayerData_v2")

local worldFolder = Workspace:FindFirstChild(TycoonConfig.WorldName)
if not worldFolder then
	worldFolder = Instance.new("Folder")
	worldFolder.Name = TycoonConfig.WorldName
	worldFolder.Parent = Workspace
end

local plotsFolder = worldFolder:FindFirstChild(TycoonConfig.PlotsFolderName)
if not plotsFolder then
	plotsFolder = Instance.new("Folder")
	plotsFolder.Name = TycoonConfig.PlotsFolderName
	plotsFolder.Parent = worldFolder
end

local lobbyFolder = worldFolder:FindFirstChild(TycoonConfig.LobbyFolderName)
if not lobbyFolder then
	lobbyFolder = Instance.new("Folder")
	lobbyFolder.Name = TycoonConfig.LobbyFolderName
	lobbyFolder.Parent = worldFolder
end

local function darken(color, amount)
	return color:Lerp(Color3.new(0, 0, 0), math.clamp(amount, 0, 1))
end

local function createPart(parent, name, size, cframe, color, material)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function createSurfaceText(part, face, text, textSize, textColor)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 28
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.Text = text
	label.TextColor3 = textColor
	label.TextSize = textSize
	label.TextWrapped = true
	label.Parent = gui

	return label
end

local worldFloor = worldFolder:FindFirstChild("WorldFloor")
if not worldFloor then
	worldFloor = Instance.new("Part")
	worldFloor.Name = "WorldFloor"
	worldFloor.Anchored = true
	worldFloor.Material = Enum.Material.Slate
	worldFloor.Color = Color3.fromRGB(42, 44, 52)
	worldFloor.Parent = worldFolder
end
worldFloor.Size = TycoonConfig.WorldFloorSize
worldFloor.CFrame = CFrame.new(0, -10, 0)

local lobbyPad = lobbyFolder:FindFirstChild("LobbyPad")
if not lobbyPad then
	lobbyPad = createPart(
		lobbyFolder,
		"LobbyPad",
		Vector3.new(100, 2, 100),
		CFrame.new(TycoonConfig.LobbyOrigin + Vector3.new(0, 1, 0)),
		Color3.fromRGB(26, 33, 44),
		Enum.Material.SmoothPlastic
	)
	createSurfaceText(
		lobbyPad,
		Enum.NormalId.Top,
		"Tutorial:\n1) Claim a tycoon wall\n2) Buy Basic Dropper\n3) Drops reach NEON collector for money",
		32,
		Color3.fromRGB(238, 243, 255)
	)
end

local lobbySpawn = lobbyFolder:FindFirstChild("LobbySpawn")
if not lobbySpawn then
	lobbySpawn = Instance.new("SpawnLocation")
	lobbySpawn.Name = "LobbySpawn"
	lobbySpawn.Anchored = true
	lobbySpawn.Size = Vector3.new(16, 1, 16)
	lobbySpawn.Position = TycoonConfig.LobbyOrigin + Vector3.new(0, 4, 0)
	lobbySpawn.Color = Color3.fromRGB(96, 176, 255)
	lobbySpawn.Material = Enum.Material.Neon
	lobbySpawn.Neutral = true
	lobbySpawn.Transparency = 0.12
	lobbySpawn.Parent = lobbyFolder
end

local plotStates = {}
local playerPlots = {}
local playerProfiles = {}

local function profileKey(userId)
	return string.format("player_%d", userId)
end

local function getEssence(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	return leaderstats and leaderstats:FindFirstChild("Essence") or nil
end

local function getPlayerPlotState(player)
	local plotIndex = playerPlots[player]
	return plotIndex and plotStates[plotIndex] or nil
end

local function createDefaultProfile()
	return {
		essence = 0,
		progression = {},
	}
end

local function getOrCreateElementProfile(profile, elementName)
	local state = profile.progression[elementName]
	if not state then
		state = { tier = 1, amplify = 1, purchased = {} }
		profile.progression[elementName] = state
	end
	state.tier = math.max(1, tonumber(state.tier) or 1)
	state.amplify = math.max(1, tonumber(state.amplify) or 1)
	if type(state.purchased) ~= "table" then
		state.purchased = {}
	end
	return state
end

local function loadPlayerData(player)
	local success, payload = pcall(function()
		return playerDataStore:GetAsync(profileKey(player.UserId))
	end)
	if not success or type(payload) ~= "table" then
		return createDefaultProfile()
	end

	local profile = createDefaultProfile()
	profile.essence = math.max(0, tonumber(payload.essence) or 0)
	if type(payload.progression) == "table" then
		for elementName, elementState in pairs(payload.progression) do
			if type(elementName) == "string" and type(elementState) == "table" then
				local clean = {
					tier = math.max(1, tonumber(elementState.tier) or 1),
					amplify = math.max(1, tonumber(elementState.amplify) or 1),
					purchased = {},
				}
				if type(elementState.purchased) == "table" then
					for itemId, purchased in pairs(elementState.purchased) do
						if type(itemId) == "string" and purchased == true then
							clean.purchased[itemId] = true
						end
					end
				end
				profile.progression[elementName] = clean
			end
		end
	end

	return profile
end

local function saveCurrentPlotToProfile(player, profile)
	local plotState = getPlayerPlotState(player)
	if not plotState then
		return
	end

	local elementProfile = getOrCreateElementProfile(profile, plotState.element.Name)
	elementProfile.tier = plotState.tier
	elementProfile.amplify = plotState.amplify
	elementProfile.purchased = {}
	for itemId, shopState in pairs(plotState.shopItems) do
		elementProfile.purchased[itemId] = shopState.purchased == true
	end
end

local function savePlayerData(player)
	local profile = playerProfiles[player]
	if not profile then
		return
	end

	local essence = getEssence(player)
	if essence then
		profile.essence = math.max(0, essence.Value)
	end
	saveCurrentPlotToProfile(player, profile)

	local payload = {
		essence = profile.essence,
		progression = profile.progression,
	}

	local success, saveError = pcall(function()
		playerDataStore:UpdateAsync(profileKey(player.UserId), function()
			return payload
		end)
	end)
	if not success then
		warn(string.format("Failed to save %s (%d): %s", player.Name, player.UserId, tostring(saveError)))
	end
end

local function createLeaderstats(player, profile)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		leaderstats.Parent = player
	end

	local essence = leaderstats:FindFirstChild("Essence")
	if not essence then
		essence = Instance.new("IntValue")
		essence.Name = "Essence"
		essence.Parent = leaderstats
	end
	essence.Value = profile.essence

	local tierValue = leaderstats:FindFirstChild("Tier")
	if not tierValue then
		tierValue = Instance.new("IntValue")
		tierValue.Name = "Tier"
		tierValue.Parent = leaderstats
	end
	tierValue.Value = 0

	local incomeValue = leaderstats:FindFirstChild("IncomePerSecond")
	if not incomeValue then
		incomeValue = Instance.new("IntValue")
		incomeValue.Name = "IncomePerSecond"
		incomeValue.Parent = leaderstats
	end
	incomeValue.Value = 0
end

local function sendPlayerToPlot(player, plotState)
	local character = player.Character or player.CharacterAdded:Wait()
	local rootPart = character:WaitForChild("HumanoidRootPart", 10)
	if rootPart then
		rootPart.CFrame = plotState.spawnPad.CFrame + Vector3.new(0, TycoonConfig.SpawnHeight, 0)
	end
end

local function sendPlayerToLobby(player)
	local character = player.Character or player.CharacterAdded:Wait()
	local rootPart = character:WaitForChild("HumanoidRootPart", 10)
	if rootPart then
		rootPart.CFrame = lobbySpawn.CFrame + Vector3.new(0, TycoonConfig.SpawnHeight, 0)
	end
end

local function hasAtLeastOneDropper(plotState)
	for _, shopState in pairs(plotState.shopItems) do
		if shopState.item.Type == "Dropper" and shopState.purchased then
			return true
		end
	end
	return false
end

local function syncPlayerAttributes(player, plotState)
	if not plotState then
		player:SetAttribute("ElementName", "Unclaimed")
		player:SetAttribute("ElementColor", Color3.fromRGB(160, 160, 160))
		player:SetAttribute("ElementAccent", Color3.fromRGB(235, 235, 235))
		player:SetAttribute("PlotIndex", 0)
		player:SetAttribute("PlotTier", 0)
		player:SetAttribute("PlotAmplify", 1)
		player:SetAttribute("IncomePerSecond", 0)
		player:SetAttribute("UpgradeCost", 0)
		player:SetAttribute("AmplifyCost", 0)
		player:SetAttribute("ElementTrait", "Claim a tycoon to start.")
		player:SetAttribute("ElementDescription", "Buy your first dropper to begin earning.")
		return
	end

	player:SetAttribute("ElementName", plotState.element.Name)
	player:SetAttribute("ElementColor", plotState.element.Color)
	player:SetAttribute("ElementAccent", plotState.element.Accent)
	player:SetAttribute("PlotIndex", plotState.index)
	player:SetAttribute("PlotTier", plotState.tier)
	player:SetAttribute("PlotAmplify", plotState.amplify)
	player:SetAttribute("IncomePerSecond", plotState.incomePerSecond)
	player:SetAttribute("UpgradeCost", plotState.upgradeCost)
	player:SetAttribute("AmplifyCost", plotState.amplifyCost)
	player:SetAttribute("ElementTrait", plotState.element.Trait)
	player:SetAttribute("ElementDescription", plotState.element.Description)
end

local function updatePlotWallText(plotState)
	local ownerName = plotState.owner and plotState.owner.DisplayName or "UNCLAIMED"
	plotState.wallTitle.Text = string.format("%s TYCOON  |  %s", string.upper(plotState.element.Name), ownerName)

	if not plotState.owner then
		plotState.wallBody.Text = "Step 1: Hold E here to claim\nStep 2: Buy BASIC DROPPER\nStep 3: Drops hit NEON collector for cash"
		return
	end

	if not hasAtLeastOneDropper(plotState) then
		plotState.wallBody.Text = string.format(
			"Welcome %s\nBuy BASIC DROPPER to start money flow\nTier %d | Amplify %d",
			plotState.owner.DisplayName,
			plotState.tier,
			plotState.amplify
		)
		return
	end

	plotState.wallBody.Text = string.format(
		"Income/s: %d\nTier %d  Amplify %d\nAscend %d | Amplify %d",
		plotState.incomePerSecond,
		plotState.tier,
		plotState.amplify,
		plotState.upgradeCost,
		plotState.amplifyCost
	)
end

local function computeDropMultiplier(plotState)
	local multiplier = 1 + plotState.element.IncomeBonus
	multiplier *= 1 + ((plotState.tier - 1) * 0.12)
	multiplier *= 1 + ((plotState.amplify - 1) * 0.2)

	for _, shopState in pairs(plotState.shopItems) do
		if shopState.item.Type == "Upgrade" and shopState.purchased then
			multiplier *= 1 + (shopState.item.MultiplierBonus or 0)
		end
	end

	return multiplier
end

local function recomputePlotEconomy(plotState)
	local dropMultiplier = computeDropMultiplier(plotState)
	local income = 0
	for _, shopState in pairs(plotState.shopItems) do
		if shopState.item.Type == "Dropper" then
			if shopState.purchased then
				local perSecond = ((shopState.item.DropValue or 0) * dropMultiplier) / math.max(0.2, shopState.item.DropInterval or 1)
				income += perSecond
				shopState.dropperBody.Transparency = 0
				shopState.dropperBody.Material = Enum.Material.Metal
				shopState.dropperSpout.Transparency = 0
			else
				shopState.dropperBody.Transparency = 0.45
				shopState.dropperBody.Material = Enum.Material.SmoothPlastic
				shopState.dropperSpout.Transparency = 0.45
			end
		end
	end

	plotState.dropMultiplier = dropMultiplier
	plotState.incomePerSecond = math.floor(income)
	plotState.upgradeCost = math.floor(TycoonConfig.BaseUpgradeCost * math.pow(TycoonConfig.UpgradeCostGrowth, plotState.tier - 1))
	plotState.amplifyCost = math.floor(TycoonConfig.BaseAmplifyCost * math.pow(TycoonConfig.AmplifyCostGrowth, plotState.amplify - 1))

	plotState.model:SetAttribute("PlotTier", plotState.tier)
	plotState.model:SetAttribute("PlotAmplify", plotState.amplify)
	plotState.model:SetAttribute("IncomePerSecond", plotState.incomePerSecond)
	plotState.model:SetAttribute("UpgradeCost", plotState.upgradeCost)
	plotState.model:SetAttribute("AmplifyCost", plotState.amplifyCost)

	local canProgress = plotState.owner ~= nil and hasAtLeastOneDropper(plotState)
	plotState.upgradePrompt.Enabled = canProgress
	plotState.amplifyPrompt.Enabled = canProgress

	for _, shopState in pairs(plotState.shopItems) do
		shopState.prompt.Enabled = plotState.owner ~= nil and not shopState.purchased
		shopState.pad.Material = shopState.purchased and Enum.Material.Neon or Enum.Material.SmoothPlastic
		shopState.pad.Transparency = shopState.purchased and 0.15 or 0
	end

	updatePlotWallText(plotState)
end

local function setPlotOwnedState(plotState, owner)
	plotState.owner = owner
	local owned = owner ~= nil

	plotState.model:SetAttribute("Owned", owned)
	plotState.model:SetAttribute("OwnerUserId", owned and owner.UserId or 0)
	plotState.model:SetAttribute("OwnerName", owned and owner.DisplayName or "Open Plot")

	plotState.claimPrompt.Enabled = not owned
	plotState.model.Name = owned
		and string.format("Plot_%02d_%s_%s", plotState.index, plotState.element.Name, owner.Name)
		or string.format("Plot_%02d_%s", plotState.index, plotState.element.Name)

	recomputePlotEconomy(plotState)
end

local function spawnDrop(plotState, shopState)
	local drop = Instance.new("Part")
	drop.Name = "EssenceDrop"
	drop.Shape = Enum.PartType.Ball
	drop.Size = Vector3.new(1.8, 1.8, 1.8)
	drop.Color = plotState.element.Accent
	drop.Material = Enum.Material.Neon
	drop.Anchored = false
	drop.CanCollide = true
	drop.CFrame = shopState.dropperSpout.CFrame * CFrame.new(0, -1.4, 0)
	drop:SetAttribute("DropOwnerUserId", plotState.owner.UserId)
	drop:SetAttribute("DropValue", math.max(1, math.floor((shopState.item.DropValue or 1) * plotState.dropMultiplier)))
	drop.Parent = worldFolder

	Debris:AddItem(drop, TycoonConfig.DropperLifetime)
end

local function tryUpgrade(player, plotState)
	if plotState.owner ~= player or not hasAtLeastOneDropper(plotState) then
		return
	end
	local essence = getEssence(player)
	if not essence or essence.Value < plotState.upgradeCost then
		return
	end
	essence.Value -= plotState.upgradeCost
	plotState.tier += 1
	recomputePlotEconomy(plotState)
	syncPlayerAttributes(player, plotState)
	local profile = playerProfiles[player]
	if profile then
		saveCurrentPlotToProfile(player, profile)
	end
end

local function tryAmplify(player, plotState)
	if plotState.owner ~= player or not hasAtLeastOneDropper(plotState) then
		return
	end
	local essence = getEssence(player)
	if not essence or essence.Value < plotState.amplifyCost then
		return
	end
	essence.Value -= plotState.amplifyCost
	plotState.amplify += 1
	recomputePlotEconomy(plotState)
	syncPlayerAttributes(player, plotState)
	local profile = playerProfiles[player]
	if profile then
		saveCurrentPlotToProfile(player, profile)
	end
end

local function tryBuyShopItem(player, plotState, itemId)
	if plotState.owner ~= player then
		return
	end
	local shopState = plotState.shopItems[itemId]
	if not shopState or shopState.purchased then
		return
	end
	local essence = getEssence(player)
	if not essence or essence.Value < shopState.item.Cost then
		return
	end

	essence.Value -= shopState.item.Cost
	shopState.purchased = true
	recomputePlotEconomy(plotState)
	syncPlayerAttributes(player, plotState)
	local profile = playerProfiles[player]
	if profile then
		saveCurrentPlotToProfile(player, profile)
	end
end

local function claimPlot(player, plotState)
	if plotState.owner ~= nil or playerPlots[player] ~= nil then
		return
	end
	local profile = playerProfiles[player]
	if not profile then
		return
	end

	local elementProfile = getOrCreateElementProfile(profile, plotState.element.Name)
	plotState.tier = elementProfile.tier
	plotState.amplify = elementProfile.amplify
	for itemId, shopState in pairs(plotState.shopItems) do
		shopState.purchased = elementProfile.purchased[itemId] == true
		shopState.nextDropAt = 0
	end

	setPlotOwnedState(plotState, player)
	playerPlots[player] = plotState.index
	syncPlayerAttributes(player, plotState)
	sendPlayerToPlot(player, plotState)
end

local function resetPlotProgress(plotState)
	plotState.tier = 1
	plotState.amplify = 1
	for _, shopState in pairs(plotState.shopItems) do
		shopState.purchased = false
		shopState.nextDropAt = 0
	end
	recomputePlotEconomy(plotState)
end

local function releasePlot(player)
	local plotIndex = playerPlots[player]
	if not plotIndex then
		return
	end
	local plotState = plotStates[plotIndex]
	if plotState then
		local profile = playerProfiles[player]
		if profile then
			saveCurrentPlotToProfile(player, profile)
		end
		resetPlotProgress(plotState)
		setPlotOwnedState(plotState, nil)
	end
	playerPlots[player] = nil
end

local function connectConveyor(conveyor)
	conveyor.Touched:Connect(function(hit)
		if not hit or hit.Name ~= "EssenceDrop" then
			return
		end
		local pushDirection = conveyor.CFrame.LookVector
		hit.AssemblyLinearVelocity = (pushDirection * 24) + Vector3.new(0, 2, 0)
	end)
end

local function buildPlot(index, element)
	local angle = ((index - 1) / TycoonConfig.PlotCount) * (math.pi * 2)
	local radius = TycoonConfig.PlotRingRadius
	local origin = TycoonConfig.LobbyOrigin + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
	local basePosition = origin + TycoonConfig.PlotGroundOffset
	local faceTarget = TycoonConfig.LobbyOrigin + Vector3.new(0, basePosition.Y, 0)
	local plotCFrame = CFrame.lookAt(basePosition, faceTarget)

	local model = Instance.new("Model")
	model.Name = string.format("Plot_%02d_%s", index, element.Name)
	model.Parent = plotsFolder
	model:SetAttribute("PlotIndex", index)
	model:SetAttribute("ElementName", element.Name)
	model:SetAttribute("Owned", false)
	model:SetAttribute("OwnerUserId", 0)
	model:SetAttribute("OwnerName", "Open Plot")

	createPart(model, "Base", TycoonConfig.PlotSize, plotCFrame, darken(element.Color, 0.2), Enum.Material.SmoothPlastic)
	local claimWall = createPart(model, "ClaimWall", Vector3.new(62, 20, 3), plotCFrame * CFrame.new(0, 11, -54), darken(element.Color, 0.45), Enum.Material.SmoothPlastic)
	local wallTitle = createSurfaceText(claimWall, Enum.NormalId.Front, "", 50, Color3.fromRGB(255, 255, 255))
	local wallBody = createSurfaceText(claimWall, Enum.NormalId.Back, "", 32, Color3.fromRGB(240, 246, 255))

	local claimPrompt = Instance.new("ProximityPrompt")
	claimPrompt.ActionText = "Claim Tycoon"
	claimPrompt.ObjectText = element.Name
	claimPrompt.HoldDuration = 0.2
	claimPrompt.RequiresLineOfSight = false
	claimPrompt.MaxActivationDistance = TycoonConfig.ClaimDistance
	claimPrompt.KeyboardKeyCode = Enum.KeyCode.E
	claimPrompt.Parent = claimWall

	local spawnPad = createPart(model, "SpawnPad", Vector3.new(14, 1.5, 14), plotCFrame * CFrame.new(0, 3.5, 40), darken(element.Accent, 0.15), Enum.Material.Neon)
	spawnPad.Transparency = 0.14

	local upgradePad = createPart(model, "UpgradePad", Vector3.new(12, 2, 12), plotCFrame * CFrame.new(-24, 2, -36), darken(element.Color, 0.35), Enum.Material.SmoothPlastic)
	local amplifyPad = createPart(model, "AmplifyPad", Vector3.new(12, 2, 12), plotCFrame * CFrame.new(24, 2, -36), darken(element.Accent, 0.6), Enum.Material.SmoothPlastic)

	local conveyor = createPart(model, "Conveyor", Vector3.new(16, 1, 70), plotCFrame * CFrame.new(0, 2.5, -3), Color3.fromRGB(45, 52, 64), Enum.Material.Metal)
	local leftRail = createPart(model, "RailLeft", Vector3.new(1, 3, 70), plotCFrame * CFrame.new(-8.5, 3.5, -3), Color3.fromRGB(85, 92, 108), Enum.Material.Metal)
	local rightRail = createPart(model, "RailRight", Vector3.new(1, 3, 70), plotCFrame * CFrame.new(8.5, 3.5, -3), Color3.fromRGB(85, 92, 108), Enum.Material.Metal)
	leftRail.CanCollide = true
	rightRail.CanCollide = true
	connectConveyor(conveyor)

	local collector = createPart(model, "Collector", Vector3.new(18, 2, 12), plotCFrame * CFrame.new(0, 2.5, -38), element.Accent, Enum.Material.Neon)
	createSurfaceText(collector, Enum.NormalId.Top, "NEON COLLECTOR", 28, Color3.fromRGB(255, 255, 255))

	local upgradePrompt = Instance.new("ProximityPrompt")
	upgradePrompt.ActionText = "Ascend"
	upgradePrompt.ObjectText = "Tier Up"
	upgradePrompt.HoldDuration = 0.2
	upgradePrompt.RequiresLineOfSight = false
	upgradePrompt.MaxActivationDistance = TycoonConfig.ClaimDistance
	upgradePrompt.KeyboardKeyCode = Enum.KeyCode.R
	upgradePrompt.Parent = upgradePad

	local amplifyPrompt = Instance.new("ProximityPrompt")
	amplifyPrompt.ActionText = "Amplify"
	amplifyPrompt.ObjectText = "Multiplier Up"
	amplifyPrompt.HoldDuration = 0.2
	amplifyPrompt.RequiresLineOfSight = false
	amplifyPrompt.MaxActivationDistance = TycoonConfig.ClaimDistance
	amplifyPrompt.KeyboardKeyCode = Enum.KeyCode.F
	amplifyPrompt.Parent = amplifyPad

	local shopItems = {}
	for _, item in ipairs(TycoonConfig.ShopItems) do
		local pad = createPart(
			model,
			"ShopPad_" .. item.Id,
			Vector3.new(11, 2, 11),
			plotCFrame * CFrame.new(item.Offset),
			darken(element.Accent, 0.5),
			Enum.Material.SmoothPlastic
		)
		createSurfaceText(pad, Enum.NormalId.Top, string.format("%s\n$%d", item.Name, item.Cost), 20, Color3.fromRGB(255, 255, 255))

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Buy " .. item.Name
		prompt.ObjectText = tostring(item.Cost) .. " Essence"
		prompt.HoldDuration = 0.15
		prompt.RequiresLineOfSight = false
		prompt.MaxActivationDistance = TycoonConfig.ClaimDistance
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.Parent = pad

		local dropperBody = nil
		local dropperSpout = nil
		if item.Type == "Dropper" then
			dropperBody = createPart(
				model,
				"DropperBody_" .. item.Id,
				Vector3.new(8, 10, 8),
				plotCFrame * CFrame.new(item.DropperOffset),
				darken(element.Color, 0.1),
				Enum.Material.SmoothPlastic
			)
			dropperSpout = createPart(
				model,
				"DropperSpout_" .. item.Id,
				Vector3.new(2, 2, 2),
				plotCFrame * CFrame.new(item.DropperOffset + Vector3.new(0, 3, -6)),
				element.Accent,
				Enum.Material.Neon
			)
		end

		shopItems[item.Id] = {
			item = item,
			pad = pad,
			prompt = prompt,
			purchased = false,
			nextDropAt = 0,
			dropperBody = dropperBody,
			dropperSpout = dropperSpout,
		}

		prompt.Triggered:Connect(function(player)
			local targetPlot = plotStates[index]
			if targetPlot then
				tryBuyShopItem(player, targetPlot, item.Id)
			end
		end)
	end

	local plotState = {
		model = model,
		index = index,
		element = element,
		owner = nil,
		tier = 1,
		amplify = 1,
		dropMultiplier = 1,
		incomePerSecond = 0,
		upgradeCost = TycoonConfig.BaseUpgradeCost,
		amplifyCost = TycoonConfig.BaseAmplifyCost,
		wallTitle = wallTitle,
		wallBody = wallBody,
		claimPrompt = claimPrompt,
		upgradePrompt = upgradePrompt,
		amplifyPrompt = amplifyPrompt,
		spawnPad = spawnPad,
		collector = collector,
		shopItems = shopItems,
	}

	claimPrompt.Triggered:Connect(function(player)
		claimPlot(player, plotState)
	end)
	upgradePrompt.Triggered:Connect(function(player)
		tryUpgrade(player, plotState)
	end)
	amplifyPrompt.Triggered:Connect(function(player)
		tryAmplify(player, plotState)
	end)

	collector.Touched:Connect(function(hit)
		if not hit or hit.Name ~= "EssenceDrop" then
			return
		end
		if hit:GetAttribute("Collected") == true then
			return
		end
		if plotState.owner == nil then
			return
		end

		local ownerId = hit:GetAttribute("DropOwnerUserId")
		if ownerId ~= plotState.owner.UserId then
			return
		end

		hit:SetAttribute("Collected", true)
		local essence = getEssence(plotState.owner)
		if essence then
			essence.Value += math.max(1, tonumber(hit:GetAttribute("DropValue")) or 1)
			local leaderstats = plotState.owner:FindFirstChild("leaderstats")
			local tierValue = leaderstats and leaderstats:FindFirstChild("Tier")
			local incomeValue = leaderstats and leaderstats:FindFirstChild("IncomePerSecond")
			if tierValue then
				tierValue.Value = plotState.tier
			end
			if incomeValue then
				incomeValue.Value = plotState.incomePerSecond
			end
		end
		hit:Destroy()
	end)

	recomputePlotEconomy(plotState)
	setPlotOwnedState(plotState, nil)
	plotStates[index] = plotState
end

for index = 1, TycoonConfig.PlotCount do
	buildPlot(index, Elements.GetByIndex(index))
end

task.spawn(function()
	while true do
		task.wait(TycoonConfig.DropperTickRate)
		local now = os.clock()
		for _, plotState in pairs(plotStates) do
			if plotState.owner then
				for _, shopState in pairs(plotState.shopItems) do
					if shopState.purchased and shopState.item.Type == "Dropper" then
						if now >= shopState.nextDropAt then
							spawnDrop(plotState, shopState)
							shopState.nextDropAt = now + math.max(0.2, shopState.item.DropInterval or 1)
						end
					end
				end
			end
		end
	end
end)

Players.PlayerAdded:Connect(function(player)
	local profile = loadPlayerData(player)
	playerProfiles[player] = profile
	createLeaderstats(player, profile)
	syncPlayerAttributes(player, nil)

	player.CharacterAdded:Connect(function()
		local plotState = getPlayerPlotState(player)
		if plotState then
			task.defer(sendPlayerToPlot, player, plotState)
		else
			task.defer(sendPlayerToLobby, player)
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	savePlayerData(player)
	releasePlot(player)
	playerProfiles[player] = nil
end)

task.spawn(function()
	while true do
		task.wait(60)
		for _, player in ipairs(Players:GetPlayers()) do
			savePlayerData(player)
		end
	end
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		savePlayerData(player)
	end
	task.wait(2)
end)
