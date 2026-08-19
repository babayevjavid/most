local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local config = require(ReplicatedStorage.Shared.RagdollConfig)

local remotes = ReplicatedStorage:WaitForChild("RagdollRemotes")
local toggleRemote = remotes:WaitForChild(config.ToggleRemoteName) :: RemoteEvent
local stateRemote = remotes:WaitForChild(config.StateRemoteName) :: RemoteEvent

local ignoreIDs = {
	100114491214554,
}

local lastFire = 0

local function stopNonAbilityAnimations(humanoid: Humanoid)
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		local animation = track.Animation
		if animation and CollectionService:HasTag(animation, "AbilityAnims") then
			continue
		end
		local id = animation and animation.AnimationId
		local idNum = id and tonumber((id :: string):match("%d+")) or nil
		if idNum and table.find(ignoreIDs, idNum) then
			task.delay(1, function()
				track:Stop()
			end)
		else
			track:Stop()
		end
	end
end

local function onRagdollChanged(enabled: boolean)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid then
		return
	end

	local animate = character:FindFirstChild("Animate")
	if enabled then
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		stopNonAbilityAnimations(humanoid)
		if animate and animate:IsA("LocalScript") then
			animate.Disabled = true
		end
	else
		if animate and animate:IsA("LocalScript") then
			animate.Disabled = false
		end
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
end

local function onCharacterAdded(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 5)
	if not humanoid then
		return
	end
	humanoid.StateChanged:Connect(function(_, newState)
		if newState == Enum.HumanoidStateType.FallingDown then
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
		local animate = character:FindFirstChild("Animate")
		if not animate or not animate:IsA("LocalScript") then
			return
		end
		if newState ~= Enum.HumanoidStateType.Physics and newState ~= Enum.HumanoidStateType.GettingUp and animate.Disabled then
			humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		end
	end)
end

ContextActionService:BindActionAtPriority(
	"RagdollToggleAction",
	function(_, inputState)
		if inputState ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		local now = os.clock()
		if (now - lastFire) < config.CooldownSeconds then
			return Enum.ContextActionResult.Sink
		end
		lastFire = now
		toggleRemote:FireServer()
		return Enum.ContextActionResult.Sink
	end,
	false,
	50000,
	Enum.KeyCode.R
)

stateRemote.OnClientEvent:Connect(onRagdollChanged)

if player.Character then
	onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)

