local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RagdollConfig = require(ReplicatedStorage.Shared.RagdollConfig)

local remotesFolder = ReplicatedStorage:WaitForChild("RagdollRemotes")
local toggleRemote = remotesFolder:WaitForChild(RagdollConfig.ToggleRemoteName) :: RemoteEvent
local stateRemote = remotesFolder:WaitForChild(RagdollConfig.StateRemoteName) :: RemoteEvent

local ragdollHandlerFolder = script.Parent:WaitForChild("RagdollHandler")
local BuildRagdoll = require(ragdollHandlerFolder:WaitForChild("buildRagdoll"))
local RagdollHandler = require(ragdollHandlerFolder)

local lastToggle: { [Player]: number } = {}

local function setServerOwnership(character: Model, owner: Player?)
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("BasePart") then
			pcall(function()
				d:SetNetworkOwner(owner)
			end)
		end
	end
end

local function ragdoll(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	character:SetAttribute("Ragdoll", true)
	setServerOwnership(character, nil)
	RagdollHandler:ManualRagdoll(humanoid, true)

	local plr = Players:GetPlayerFromCharacter(character)
	if plr then
		stateRemote:FireClient(plr, true)
	end
end

local function unragdoll(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	character:SetAttribute("Ragdoll", false)
	RagdollHandler:ManualRagdoll(humanoid, false)

	local plr = Players:GetPlayerFromCharacter(character)
	if plr then
		setServerOwnership(character, plr)
		stateRemote:FireClient(plr, false)
	end
end

local function setupRagdoll(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
	if not humanoid then
		return
	end
	BuildRagdoll(humanoid)
	RagdollHandler:ragdollAdded(humanoid)
	if character:GetAttribute("Ragdoll") == nil then
		character:SetAttribute("Ragdoll", false)
	end
end

local function disconnectRagdoll(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		RagdollHandler:ragdollRemoved(humanoid)
	end
end

toggleRemote.OnServerEvent:Connect(function(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local now = os.clock()
	local last = lastToggle[player]
	if last and (now - last) < RagdollConfig.CooldownSeconds then
		return
	end
	lastToggle[player] = now

	if character:GetAttribute("Ragdoll") then
		unragdoll(character)
	else
		ragdoll(character)
	end
end)

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		setupRagdoll(character)
	end)
	player.CharacterRemoving:Connect(function(character)
		disconnectRagdoll(character)
	end)
end)

for _, player in ipairs(Players:GetPlayers()) do
	if player.Character then
		setupRagdoll(player.Character)
	end
end

for _, character in ipairs(CollectionService:GetTagged("TestCharacter")) do
	setupRagdoll(character)
end

CollectionService:GetInstanceAddedSignal("TestCharacter"):Connect(function(character)
	if character:IsA("Model") then
		setupRagdoll(character)
	end
end)

