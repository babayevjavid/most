--!strict
--[[
	Telekinetic Flight animations: idle while hovering, fly while moving.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TelekineticFlightConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TelekineticFlightConstants"))

local IDLE_ANIM_ID = TelekineticFlightConstants.ANIM_IDLE_ID
local FLY_ANIM_ID = TelekineticFlightConstants.ANIM_FLY_ID

local TelekineticFlightAnimations = {}

local idleTrack: AnimationTrack? = nil
local flyTrack: AnimationTrack? = nil
local flying = false
local moving = false
local attributeConns: { RBXScriptConnection } = {}
local boundCharacter: Model? = nil

local function getAnimator(character: Model): Animator?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	return animator
end

local function loadTrack(animator: Animator, assetId: number): AnimationTrack?
	local anim = Instance.new("Animation")
	anim.AnimationId = "rbxassetid://" .. tostring(assetId)
	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	if ok and track then
		track.Priority = Enum.AnimationPriority.Action
		track.Looped = true
		return track
	end
	return nil
end

local function stopTracks()
	if idleTrack then
		idleTrack:Stop(0.15)
	end
	if flyTrack then
		flyTrack:Stop(0.15)
	end
end

local function updatePlayback()
	if not flying then
		stopTracks()
		return
	end
	if moving then
		if idleTrack and idleTrack.IsPlaying then
			idleTrack:Stop(0.2)
		end
		if flyTrack and not flyTrack.IsPlaying then
			flyTrack:Play(0.2)
		end
	else
		if flyTrack and flyTrack.IsPlaying then
			flyTrack:Stop(0.2)
		end
		if idleTrack and not idleTrack.IsPlaying then
			idleTrack:Play(0.2)
		end
	end
end

local function onFlightEnd()
	flying = false
	moving = false
	stopTracks()
end

local function onFlightStart(character: Model)
	local animator = getAnimator(character)
	if not animator then
		return
	end
	idleTrack = loadTrack(animator, IDLE_ANIM_ID)
	flyTrack = loadTrack(animator, FLY_ANIM_ID)
	flying = true
	moving = character:GetAttribute("FlightInputActive") == true
	updatePlayback()
end

local function clearConnections()
	for _, conn in attributeConns do
		conn:Disconnect()
	end
	table.clear(attributeConns)
end

local function bindCharacter(character: Model)
	clearConnections()
	stopTracks()
	idleTrack = nil
	flyTrack = nil
	boundCharacter = character
	flying = false
	moving = false

	if character:GetAttribute("IsTelekineticFlying") == true then
		onFlightStart(character)
	end

	table.insert(attributeConns, character:GetAttributeChangedSignal("IsTelekineticFlying"):Connect(function()
		if character:GetAttribute("IsTelekineticFlying") == true then
			onFlightStart(character)
		else
			onFlightEnd()
		end
	end))

	table.insert(attributeConns, character:GetAttributeChangedSignal("FlightInputActive"):Connect(function()
		moving = character:GetAttribute("FlightInputActive") == true
		updatePlayback()
	end))
end

function TelekineticFlightAnimations.start(player: Player)
	local function onCharacterAdded(character: Model)
		bindCharacter(character)
	end

	if player.Character then
		onCharacterAdded(player.Character)
	end

	player.CharacterAdded:Connect(onCharacterAdded)
	player.CharacterRemoving:Connect(function()
		boundCharacter = nil
		onFlightEnd()
		clearConnections()
		idleTrack = nil
		flyTrack = nil
	end)
end

return TelekineticFlightAnimations
