local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CosmicConfig = require(Shared:WaitForChild("CosmicConfig"))
local CosmicFormat = require(Shared:WaitForChild("CosmicFormat"))
local PowerConfig = require(Shared:WaitForChild("PowerConfig"))

type PlayerState = CosmicConfig.PlayerState

local CosmicGameService = {}

local playerStates: { [Player]: PlayerState } = {}
local replicatedValues: { [Player]: { Power: IntValue, Ascensions: IntValue, PowerPerSec: NumberValue, TotalMultiplier: NumberValue } } = {}
local notifyRemote: RemoteEvent
local padFeedbackRemote: RemoteEvent
local powersSyncRemote: RemoteEvent
local buyPowerRemote: RemoteFunction
local equipPowerRemote: RemoteFunction
local unequipPowerRemote: RemoteFunction
local activateAbilityRemote: RemoteFunction
local abilityUsedRemote: RemoteEvent
local onStateChanged: ((player: Player) -> ())?
local abilityCooldowns: { [Player]: { [number]: number } } = {}

local function ensureRemotes()
	local folder = ReplicatedStorage:FindFirstChild("SuperpowerRemotes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "SuperpowerRemotes"
		folder.Parent = ReplicatedStorage
	end

	local function getOrCreateRemote(name: string): RemoteEvent
		local existing = folder:FindFirstChild(name)
		if existing and existing:IsA("RemoteEvent") then
			return existing
		end
		if existing then
			existing:Destroy()
		end
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
		return remote
	end

	notifyRemote = getOrCreateRemote("Notify")
	padFeedbackRemote = getOrCreateRemote("PadFeedback")
	powersSyncRemote = getOrCreateRemote("PowersSync")

	local function getOrCreateFunction(name: string): RemoteFunction
		local existing = folder:FindFirstChild(name)
		if existing and existing:IsA("RemoteFunction") then
			return existing
		end
		if existing then
			existing:Destroy()
		end
		local remote = Instance.new("RemoteFunction")
		remote.Name = name
		remote.Parent = folder
		return remote
	end

	buyPowerRemote = getOrCreateFunction("BuyPower")
	equipPowerRemote = getOrCreateFunction("EquipPower")
	unequipPowerRemote = getOrCreateFunction("UnequipPower")
	activateAbilityRemote = getOrCreateFunction("ActivateAbility")
	abilityUsedRemote = getOrCreateRemote("AbilityUsed")
	return notifyRemote
end

local function buildPowerPayload(state: PlayerState)
	return {
		owned = state.OwnedPowers,
		equipped = state.EquippedPowers,
		maxEquipped = PowerConfig.MaxEquipped,
	}
end

local function syncPowers(player: Player)
	local state = playerStates[player]
	if not state or not powersSyncRemote then
		return
	end
	powersSyncRemote:FireClient(player, buildPowerPayload(state))
end

function CosmicGameService.FirePadPress(player: Player)
	padFeedbackRemote:FireClient(player, "press")
end

function CosmicGameService.Notify(player: Player, message: string, tone: string?, sfx: string?)
	notifyRemote:FireClient(player, {
		text = message,
		tone = tone or "info",
		sfx = sfx,
	})
end

local function syncReplicatedStats(player: Player)
	local state = playerStates[player]
	local values = replicatedValues[player]
	if not state or not values then
		return
	end

	values.Power.Value = state.Power
	values.Ascensions.Value = state.Ascensions
	values.PowerPerSec.Value = CosmicConfig.GetPowerPerSecond(state)
	values.TotalMultiplier.Value = CosmicConfig.GetTotalMultiplier(state)
end

local function fireStateChanged(player: Player)
	syncReplicatedStats(player)
	syncPowers(player)
	if onStateChanged then
		onStateChanged(player)
	end
end

function CosmicGameService.SetStateChangedCallback(callback: (player: Player) -> ())
	onStateChanged = callback
end

function CosmicGameService.GetState(player: Player): PlayerState?
	return playerStates[player]
end

function CosmicGameService.GetStateForSave(player: Player): PlayerState?
	local state = playerStates[player]
	if not state then
		return nil
	end

	return {
		Power = state.Power,
		LifetimePower = state.LifetimePower,
		OwnedGenerators = table.clone(state.OwnedGenerators),
		MultiplierLevels = table.clone(state.MultiplierLevels),
		Ascensions = state.Ascensions,
		OwnedPowers = table.clone(state.OwnedPowers),
		EquippedPowers = table.clone(state.EquippedPowers),
		LastSaveUnix = os.time(),
	}
end

function CosmicGameService.SyncState(player: Player)
	fireStateChanged(player)
end

function CosmicGameService.ApplyLoadedState(player: Player, loaded: PlayerState, offlineBonus: number)
	local state = playerStates[player]
	if not state then
		return
	end

	state.Power = loaded.Power + offlineBonus
	state.LifetimePower = loaded.LifetimePower + offlineBonus
	state.OwnedGenerators = loaded.OwnedGenerators
	state.MultiplierLevels = loaded.MultiplierLevels
	state.Ascensions = loaded.Ascensions
	state.OwnedPowers = loaded.OwnedPowers or {}
	state.EquippedPowers = loaded.EquippedPowers or {}
	state.LastSaveUnix = loaded.LastSaveUnix

	fireStateChanged(player)

	if offlineBonus > 0 then
		CosmicGameService.Notify(
			player,
			("Welcome back! +%s offline power while training"):format(CosmicFormat.Number(offlineBonus)),
			"success"
		)
	end
end

local function buildLeaderstats(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local power = Instance.new("IntValue")
	power.Name = "Power"
	power.Value = 0
	power.Parent = leaderstats

	local ascensions = Instance.new("IntValue")
	ascensions.Name = "Ascensions"
	ascensions.Value = 0
	ascensions.Parent = leaderstats

	local powerStats = Instance.new("Folder")
	powerStats.Name = "PowerStats"
	powerStats.Parent = player

	local powerPerSec = Instance.new("NumberValue")
	powerPerSec.Name = "PowerPerSec"
	powerPerSec.Value = 0
	powerPerSec.Parent = powerStats

	local totalMultiplier = Instance.new("NumberValue")
	totalMultiplier.Name = "TotalMultiplier"
	totalMultiplier.Value = 1
	totalMultiplier.Parent = powerStats

	replicatedValues[player] = {
		Power = power,
		Ascensions = ascensions,
		PowerPerSec = powerPerSec,
		TotalMultiplier = totalMultiplier,
	}
end

local function onPlayerAdded(player: Player)
	buildLeaderstats(player)
	playerStates[player] = CosmicConfig.CreateDefaultState()
	fireStateChanged(player)
end

local function onPlayerRemoving(player: Player)
	playerStates[player] = nil
	replicatedValues[player] = nil
	abilityCooldowns[player] = nil
end

local function applyAbilityDamage(target: Player, amount: number)
	local character = target.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid:TakeDamage(amount)
	end
end

function CosmicGameService.TryActivateAbility(player: Player, slotIndex: number): (boolean, string?)
	if slotIndex < 1 or slotIndex > PowerConfig.MaxEquipped then
		return false, "Invalid slot"
	end

	local state = playerStates[player]
	if not state then
		return false, "No state"
	end

	local powerId = state.EquippedPowers[slotIndex]
	if not powerId then
		return false, ("Nothing equipped in slot %d"):format(slotIndex)
	end

	local power = PowerConfig.GetPower(powerId)
	if not power then
		return false, "Unknown power"
	end

	if not power.ActiveAbility then
		return false, "Passive — always on"
	end

	abilityCooldowns[player] = abilityCooldowns[player] or {}
	local now = os.clock()
	local readyAt = abilityCooldowns[player][slotIndex] or 0
	if now < readyAt then
		return false, ("Cooldown %.1fs"):format(math.max(0.1, readyAt - now))
	end

	local character = player.Character
	if not character then
		return false, "No character"
	end

	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false, "No character"
	end

	local ability = power.ActiveAbility

	if ability.DashStuds then
		root.CFrame = root.CFrame + root.CFrame.LookVector * ability.DashStuds
	end

	if ability.Heal then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + ability.Heal)
		end
	end

	if ability.Damage and ability.Range then
		for _, other in Players:GetPlayers() do
			if other ~= player then
				local otherCharacter = other.Character
				local otherRoot = otherCharacter and otherCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?
				if otherRoot and (otherRoot.Position - root.Position).Magnitude <= ability.Range then
					applyAbilityDamage(other, ability.Damage)
				end
			end
		end
	end

	abilityCooldowns[player][slotIndex] = now + ability.Cooldown
	abilityUsedRemote:FireClient(player, slotIndex, powerId)
	CosmicGameService.Notify(player, ability.DisplayAction .. "!", "success", "success")
	return true, nil
end

function CosmicGameService.TryBuyGenerator(player: Player, generatorId: string): boolean
	local state = playerStates[player]
	if not state then
		return false
	end

	if state.OwnedGenerators[generatorId] then
		CosmicGameService.Notify(player, "Training already unlocked", "warn", "fail")
		return false
	end

	if not CosmicConfig.IsGeneratorUnlocked(state, generatorId) then
		CosmicGameService.Notify(player, "Training locked — unlock the previous pad first", "warn", "fail")
		return false
	end

	local generator = CosmicConfig.Generators[generatorId]
	if not generator then
		return false
	end

	local cost = CosmicConfig.GetGeneratorCost(generatorId)
	if state.Power < cost then
		CosmicGameService.Notify(player, "Not enough power", "warn", "fail")
		return false
	end

	state.Power -= cost
	state.OwnedGenerators[generatorId] = true
	fireStateChanged(player)

	CosmicGameService.Notify(
		player,
		("Unlocked %s (+%d power/s)"):format(generator.DisplayName, generator.BaseRate),
		"success",
		"success"
	)
	return true
end

function CosmicGameService.TryBuyMultiplier(player: Player, upgradeId: string): boolean
	local state = playerStates[player]
	if not state then
		return false
	end

	if not CosmicConfig.HasAnyGenerator(state) then
		CosmicGameService.Notify(player, "Unlock a training pad first", "warn", "fail")
		return false
	end

	local upgrade = CosmicConfig.Multipliers[upgradeId]
	if not upgrade then
		return false
	end

	local currentLevel = state.MultiplierLevels[upgradeId] or 0
	if currentLevel >= upgrade.MaxLevel then
		CosmicGameService.Notify(player, "Max level reached", "warn", "fail")
		return false
	end

	local cost = CosmicConfig.GetMultiplierCost(upgradeId, currentLevel)
	if state.Power < cost then
		CosmicGameService.Notify(player, "Not enough power", "warn", "fail")
		return false
	end

	state.Power -= cost
	state.MultiplierLevels[upgradeId] = currentLevel + 1
	fireStateChanged(player)

	CosmicGameService.Notify(
		player,
		("%s upgraded to level %d"):format(upgrade.DisplayName, currentLevel + 1),
		"success",
		"success"
	)
	return true
end

function CosmicGameService.TryBuyPower(player: Player, powerId: string): (boolean, string?)
	local state = playerStates[player]
	if not state then
		return false, "No state"
	end

	local power = PowerConfig.GetPower(powerId)
	if not power then
		return false, "Unknown power"
	end

	if state.OwnedPowers[powerId] then
		return false, "Already owned"
	end

	if state.Power < power.Cost then
		return false, "Not enough power"
	end

	state.Power -= power.Cost
	state.OwnedPowers[powerId] = true

	if #state.EquippedPowers < PowerConfig.MaxEquipped then
		table.insert(state.EquippedPowers, powerId)
	end

	fireStateChanged(player)
	CosmicGameService.Notify(
		player,
		("Unlocked %s"):format(power.DisplayName),
		"success",
		"success"
	)
	return true, nil
end

function CosmicGameService.TryEquipPower(player: Player, powerId: string): (boolean, string?)
	local state = playerStates[player]
	if not state then
		return false, "No state"
	end

	if not state.OwnedPowers[powerId] then
		return false, "Buy this power first"
	end

	for _, equippedId in state.EquippedPowers do
		if equippedId == powerId then
			return false, "Already equipped"
		end
	end

	if #state.EquippedPowers >= PowerConfig.MaxEquipped then
		return false, ("Max %d powers equipped"):format(PowerConfig.MaxEquipped)
	end

	table.insert(state.EquippedPowers, powerId)
	fireStateChanged(player)
	return true, nil
end

function CosmicGameService.TryUnequipPower(player: Player, powerId: string): (boolean, string?)
	local state = playerStates[player]
	if not state then
		return false, "No state"
	end

	for index, equippedId in state.EquippedPowers do
		if equippedId == powerId then
			table.remove(state.EquippedPowers, index)
			fireStateChanged(player)
			return true, nil
		end
	end

	return false, "Not equipped"
end

function CosmicGameService.TryAscension(player: Player): boolean
	local state = playerStates[player]
	if not state then
		return false
	end

	local requirement = CosmicConfig.GetAscensionRequirement(state.Ascensions)
	if state.LifetimePower < requirement then
		CosmicGameService.Notify(
			player,
			("Need %s lifetime power to ascend"):format(CosmicFormat.Number(requirement)),
			"warn",
			"fail"
		)
		return false
	end

	state.Ascensions += 1
	state.Power = CosmicConfig.StartingPower
	state.OwnedGenerators = {}
	state.MultiplierLevels = {}
	fireStateChanged(player)

	CosmicGameService.Notify(
		player,
		("Ascension #%d! Permanent boost: %s"):format(
			state.Ascensions,
			CosmicFormat.Multiplier(CosmicConfig.GetAscensionMultiplier(state.Ascensions))
		),
		"success",
		"success"
	)
	return true
end

function CosmicGameService.Init()
	notifyRemote = ensureRemotes()

	buyPowerRemote.OnServerInvoke = function(player: Player, powerId: string)
		local ok, err = CosmicGameService.TryBuyPower(player, powerId)
		if not ok and err then
			CosmicGameService.Notify(player, err, "warn", "fail")
		end
		return ok
	end

	equipPowerRemote.OnServerInvoke = function(player: Player, powerId: string)
		local ok, err = CosmicGameService.TryEquipPower(player, powerId)
		if not ok and err then
			CosmicGameService.Notify(player, err, "warn", "fail")
		end
		return ok
	end

	unequipPowerRemote.OnServerInvoke = function(player: Player, powerId: string)
		local ok, err = CosmicGameService.TryUnequipPower(player, powerId)
		if not ok and err then
			CosmicGameService.Notify(player, err, "warn", "fail")
		end
		return ok
	end

	activateAbilityRemote.OnServerInvoke = function(player: Player, slotIndex: number)
		local ok, err = CosmicGameService.TryActivateAbility(player, slotIndex)
		if not ok and err then
			CosmicGameService.Notify(player, err, "warn", "fail")
		end
		return ok
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	task.spawn(function()
		while true do
			task.wait(1)
			for player, state in playerStates do
				local gain = math.floor(CosmicConfig.GetPowerPerSecond(state))
				if gain > 0 then
					state.Power += gain
					state.LifetimePower += gain
					fireStateChanged(player)
				end
			end
		end
	end)
end

return CosmicGameService
