--[[
	Local visuals for living Ragdolled status: disable Animate, match Humanoid state.
	R is not used — server applies constraint ragdoll when Ragdolled is true (same duration as status).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer

local ignoreIDs = {
	100114491214554,
}

local ragdollConn: RBXScriptConnection? = nil
local humanoidStateConn: RBXScriptConnection? = nil

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

local function applyLocalRagdollVisual(enabled: boolean)
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
		if humanoid.Health > 0 and character:GetAttribute("CombatDeathHandled") ~= true then
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end
end

local function onRagdolledAttributeChanged(character: Model)
	applyLocalRagdollVisual(character:GetAttribute("Ragdolled") == true)
end

local function bindHumanoidStateGuard(character: Model, humanoid: Humanoid)
	if humanoidStateConn then
		humanoidStateConn:Disconnect()
		humanoidStateConn = nil
	end
	humanoidStateConn = humanoid.StateChanged:Connect(function(_, newState)
		if newState == Enum.HumanoidStateType.FallingDown then
			if
				character:GetAttribute("Ragdolled") == true
				or humanoid.Health <= 0
				or character:GetAttribute("CombatDeathHandled") == true
			then
				return
			end
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
		local animate = character:FindFirstChild("Animate")
		if not animate or not animate:IsA("LocalScript") then
			return
		end
		if character:GetAttribute("Ragdolled") ~= true then
			return
		end
		if newState ~= Enum.HumanoidStateType.Physics and newState ~= Enum.HumanoidStateType.GettingUp and animate.Disabled then
			humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		end
	end)
end

local function onCharacterAdded(character: Model)
	if ragdollConn then
		ragdollConn:Disconnect()
		ragdollConn = nil
	end

	ragdollConn = character:GetAttributeChangedSignal("Ragdolled"):Connect(function()
		onRagdolledAttributeChanged(character)
	end)

	local humanoid = character:WaitForChild("Humanoid", 5) :: Humanoid?
	if not humanoid then
		return
	end
	bindHumanoidStateGuard(character, humanoid)
	onRagdolledAttributeChanged(character)
end

if player.Character then
	onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)
