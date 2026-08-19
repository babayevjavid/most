local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PowerConfig = require(Shared:WaitForChild("PowerConfig"))

local CosmicGameService = require(script.Parent:WaitForChild("CosmicGameService"))

export type ZoneInfo = {
	type: "hub" | "home" | "wilderness",
	slot: number?,
	ownerUserId: number?,
	part: BasePart?,
}

local CosmicBaseService = {}

local MAX_SLOTS = 8
local BASE_RADIUS = 148
local BASE_SIZE = Vector3.new(58, 1, 58)

local zones: { ZoneInfo } = {}
local slotOwners: { [number]: Player? } = {}
local playerSlots: { [Player]: number } = {}
local slotSpawnCFrames: { [number]: CFrame } = {}

local function getEquipped(player: Player): { string }
	local state = CosmicGameService.GetState(player)
	if not state then
		return {}
	end
	return state.EquippedPowers or {}
end

function CosmicBaseService.GetPlayerSlot(player: Player): number?
	return playerSlots[player]
end

function CosmicBaseService.GetSlotSpawnCFrame(slot: number): CFrame?
	return slotSpawnCFrames[slot]
end

function CosmicBaseService.RegisterZone(part: BasePart, zoneType: "hub" | "home", slot: number?, ownerUserId: number?)
	table.insert(zones, {
		type = zoneType,
		slot = slot,
		ownerUserId = ownerUserId,
		part = part,
	})
end

function CosmicBaseService.GetZoneAtPosition(position: Vector3): ZoneInfo
	for _, zone in zones do
		local part = zone.part
		if part then
			local localPos = part.CFrame:PointToObjectSpace(position)
			local half = part.Size * 0.5
			if math.abs(localPos.X) <= half.X
				and math.abs(localPos.Y) <= half.Y + 6
				and math.abs(localPos.Z) <= half.Z
			then
				return zone
			end
		end
	end

	return {
		type = "wilderness",
		slot = nil,
		ownerUserId = nil,
		part = nil,
	}
end

local function assignSlot(player: Player): number?
	for slot = 1, MAX_SLOTS do
		if slotOwners[slot] == nil then
			slotOwners[slot] = player
			playerSlots[player] = slot
			return slot
		end
	end
	return nil
end

local function releaseSlot(player: Player)
	local slot = playerSlots[player]
	if not slot then
		return
	end
	slotOwners[slot] = nil
	playerSlots[player] = nil
end

local function teleportToBase(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	local slot = playerSlots[player]
	if not slot then
		return
	end

	local spawnCFrame = slotSpawnCFrames[slot]
	if spawnCFrame then
		root.CFrame = spawnCFrame + Vector3.new(0, 3, 0)
	end
end

local function applyDamage(player: Player, amount: number)
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid:TakeDamage(amount)
	end
end

local function scaleDamage(baseDamage: number, equipped: { string }): number
	local reduction = PowerConfig.GetOutOfBaseReduction(equipped)
	if reduction >= 1 then
		return 0
	end
	return math.max(1, math.floor(baseDamage * (1 - reduction) + 0.5))
end

local function processTerritoryPerks(owner: Player, intruder: Player)
	local ownerState = CosmicGameService.GetState(owner)
	if not ownerState then
		return
	end

	local territoryDamage = PowerConfig.GetTerritoryDamage(ownerState.EquippedPowers)
	local powerLeech = PowerConfig.GetPowerLeech(ownerState.EquippedPowers)

	if territoryDamage > 0 then
		applyDamage(intruder, territoryDamage)
	end

	if powerLeech > 0 then
		local intruderState = CosmicGameService.GetState(intruder)
		if intruderState and intruderState.Power > 0 then
			local stolen = math.min(powerLeech, intruderState.Power)
			intruderState.Power -= stolen
			ownerState.Power += stolen
			CosmicGameService.SyncState(owner)
			CosmicGameService.SyncState(intruder)
		end
	end
end

local function tickPlayerZone(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	local slot = playerSlots[player]
	if not slot then
		return
	end

	local zone = CosmicBaseService.GetZoneAtPosition(root.Position)
	local equipped = getEquipped(player)
	local hasTravel = PowerConfig.PlayerHasTravel(equipped)

	if zone.type == "hub" then
		return
	end

	if zone.type == "home" then
		if zone.slot == slot then
			local heal = PowerConfig.GetHomeHeal(equipped)
			if heal > 0 then
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				if humanoid then
					humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + heal)
				end
			end
			return
		end

		if not hasTravel then
			applyDamage(player, scaleDamage(PowerConfig.ForeignBaseDamage, equipped))
		end

		local owner = zone.ownerUserId and Players:GetPlayerByUserId(zone.ownerUserId)
		if owner and owner ~= player then
			processTerritoryPerks(owner, player)
		end
		return
	end

	-- Wilderness between bases is safe; travel powers unlock other heroes' baseplates.
end

function CosmicBaseService.CreateBaseRing(parent: Instance)
	local basesFolder = Instance.new("Folder")
	basesFolder.Name = "PlayerBases"
	basesFolder.Parent = parent

	for slot = 1, MAX_SLOTS do
		local angle = (slot - 1) * (math.pi * 2 / MAX_SLOTS)
		local position = Vector3.new(math.cos(angle) * BASE_RADIUS, 0.55, math.sin(angle) * BASE_RADIUS)
		local faceCenter = CFrame.lookAt(position + Vector3.new(0, 0.5, 0), Vector3.new(0, 0.5, 0))

		local baseModel = Instance.new("Model")
		baseModel.Name = ("BaseSlot_%d"):format(slot)
		baseModel.Parent = basesFolder

		local platform = Instance.new("Part")
		platform.Name = "Platform"
		platform.Size = BASE_SIZE
		platform.CFrame = faceCenter
		platform.Anchored = true
		platform.Color = Color3.fromRGB(72, 76, 84)
		platform.Material = Enum.Material.Concrete
		platform.Parent = baseModel

		local rim = Instance.new("Part")
		rim.Name = "Rim"
		rim.Size = BASE_SIZE + Vector3.new(1.2, 0.15, 1.2)
		rim.CFrame = platform.CFrame * CFrame.new(0, -0.35, 0)
		rim.Anchored = true
		rim.Color = Color3.fromRGB(255, 196, 58)
		rim.Material = Enum.Material.SmoothPlastic
		rim.CanCollide = false
		rim.Parent = baseModel

		local zone = Instance.new("Part")
		zone.Name = "HomeZone"
		zone.Size = BASE_SIZE + Vector3.new(0, 8, 0)
		zone.CFrame = platform.CFrame * CFrame.new(0, 4, 0)
		zone.Anchored = true
		zone.Transparency = 1
		zone.CanCollide = false
		zone:SetAttribute("SlotIndex", slot)
		zone.Parent = baseModel

		local sign = Instance.new("Part")
		sign.Name = "NameSign"
		sign.Size = Vector3.new(10, 2.4, 0.15)
		sign.CFrame = platform.CFrame * CFrame.new(0, 3.2, -BASE_SIZE.Z * 0.5 - 1.2)
		sign.Anchored = true
		sign.Color = Color3.fromRGB(24, 28, 36)
		sign.Material = Enum.Material.SmoothPlastic
		sign.CanCollide = false
		sign.Parent = baseModel

		local signGui = Instance.new("SurfaceGui")
		signGui.Face = Enum.NormalId.Front
		signGui.CanvasSize = Vector2.new(400, 96)
		signGui.LightInfluence = 0
		signGui.Parent = sign

		local signLabel = Instance.new("TextLabel")
		signLabel.Name = "OwnerName"
		signLabel.Size = UDim2.fromScale(1, 1)
		signLabel.BackgroundTransparency = 1
		signLabel.Font = Enum.Font.GothamBold
		signLabel.TextSize = 28
		signLabel.TextColor3 = Color3.fromRGB(248, 246, 240)
		signLabel.Text = ("Base #%d"):format(slot)
		signLabel.Parent = signGui

		local spawn = Instance.new("Part")
		spawn.Name = "Spawn"
		spawn.Size = Vector3.new(4, 0.2, 4)
		spawn.CFrame = platform.CFrame * CFrame.new(0, 0.65, -18)
		spawn.Anchored = true
		spawn.Transparency = 1
		spawn.CanCollide = false
		spawn.Parent = baseModel

		slotSpawnCFrames[slot] = spawn.CFrame

		CosmicBaseService.RegisterZone(zone, "home", slot, nil)
	end
end

function CosmicBaseService.RegisterHubZone(part: BasePart)
	CosmicBaseService.RegisterZone(part, "hub", nil, nil)
end

function CosmicBaseService.UpdateBaseSign(slot: number, playerName: string)
	local island = workspace:FindFirstChild("SuperpowerIsland")
	if not island then
		return
	end
	local bases = island:FindFirstChild("PlayerBases")
	if not bases then
		return
	end
	local baseModel = bases:FindFirstChild(("BaseSlot_%d"):format(slot))
	if not baseModel then
		return
	end
	local sign = baseModel:FindFirstChild("NameSign")
	local gui = sign and sign:FindFirstChildOfClass("SurfaceGui")
	local label = gui and gui:FindFirstChild("OwnerName")
	if label and label:IsA("TextLabel") then
		label.Text = playerName
	end

	local owner = slotOwners[slot]
	local ownerUserId = if owner then owner.UserId else nil

	local zonePart = baseModel:FindFirstChild("HomeZone")
	if zonePart then
		zonePart:SetAttribute("OwnerUserId", ownerUserId)
	end

	for _, zone in zones do
		if zone.slot == slot then
			zone.ownerUserId = ownerUserId
		end
	end
end

function CosmicBaseService.Init()
	Players.PlayerAdded:Connect(function(player: Player)
		local slot = assignSlot(player)
		if not slot then
			CosmicGameService.Notify(player, "Server bases full — shared spawn only", "warn", "fail")
			return
		end

		CosmicBaseService.UpdateBaseSign(slot, player.DisplayName)

		player.CharacterAdded:Connect(function()
			task.defer(teleportToBase, player)
		end)
		if player.Character then
			task.defer(teleportToBase, player)
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		local slot = playerSlots[player]
		releaseSlot(player)
		if slot then
			CosmicBaseService.UpdateBaseSign(slot, ("Base #%d"):format(slot))
		end
	end)

	for _, player in Players:GetPlayers() do
		local slot = assignSlot(player)
		if slot then
			CosmicBaseService.UpdateBaseSign(slot, player.DisplayName)
		end
	end

	task.spawn(function()
		while true do
			task.wait(PowerConfig.DamageTickSeconds)
			for _, player in Players:GetPlayers() do
				tickPlayerZone(player)
			end
		end
	end)
end

return CosmicBaseService
