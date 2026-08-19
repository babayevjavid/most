--!strict
--[[ Polaris ability animations: flight, ferrokinesis, magnetic pulse. ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PolarisConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PolarisConstants"))

local ANIM = PolarisConstants.Animations

local PolarisAbilityAnimations = {}

local boundCharacter: Model? = nil
local attributeConns: { RBXScriptConnection } = {}

local flyIdleTrack: AnimationTrack? = nil
local flyMoveTrack: AnimationTrack? = nil
local ferroHoldTrack: AnimationTrack? = nil
local ferroThrowTrack: AnimationTrack? = nil
local pulseRightTrack: AnimationTrack? = nil
local pulseLeftTrack: AnimationTrack? = nil
local nextPulseUsesLeftHand = true

local flying = false
local flightMoving = false
local ferroHolding = false

local function isPolarisPlayer(player: Player): boolean
	return player:GetAttribute("SelectedCharacter") == "Polaris"
end

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

local function loadTrack(
	animator: Animator,
	assetId: number,
	priority: Enum.AnimationPriority,
	looped: boolean
): AnimationTrack?
	local anim = Instance.new("Animation")
	anim.AnimationId = "rbxassetid://" .. tostring(assetId)
	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	if ok and track then
		track.Priority = priority
		track.Looped = looped
		return track
	end
	return nil
end

local function ensureFlightTracks(character: Model)
	if flyIdleTrack and flyMoveTrack then
		return
	end
	local animator = getAnimator(character)
	if not animator then
		return
	end
	flyIdleTrack = loadTrack(animator, ANIM.FLY_IDLE, Enum.AnimationPriority.Action, true)
	flyMoveTrack = loadTrack(animator, ANIM.FLY_MOVE, Enum.AnimationPriority.Action, true)
end

local function ensureFerroTracks(character: Model)
	local animator = getAnimator(character)
	if not animator then
		return
	end
	if not ferroHoldTrack then
		ferroHoldTrack = loadTrack(animator, ANIM.FERROKINESIS_HOLD, Enum.AnimationPriority.Action, true)
	end
	if not ferroThrowTrack then
		ferroThrowTrack = loadTrack(animator, ANIM.FERROKINESIS_THROW, Enum.AnimationPriority.Action4, false)
	end
end

local function ensurePulseTracks(character: Model)
	local animator = getAnimator(character)
	if not animator then
		return
	end
	if not pulseRightTrack then
		pulseRightTrack = loadTrack(animator, ANIM.PULSE_RIGHT_HAND, Enum.AnimationPriority.Action3, false)
	end
	if not pulseLeftTrack then
		pulseLeftTrack = loadTrack(animator, ANIM.PULSE_LEFT_HAND, Enum.AnimationPriority.Action3, false)
	end
end

local function stopFlightTracks()
	if flyIdleTrack and flyIdleTrack.IsPlaying then
		flyIdleTrack:Stop(0.15)
	end
	if flyMoveTrack and flyMoveTrack.IsPlaying then
		flyMoveTrack:Stop(0.15)
	end
end

local function updateFlightPlayback()
	if not flying or not boundCharacter then
		stopFlightTracks()
		return
	end
	ensureFlightTracks(boundCharacter)
	if flightMoving then
		if flyIdleTrack and flyIdleTrack.IsPlaying then
			flyIdleTrack:Stop(0.2)
		end
		if flyMoveTrack and not flyMoveTrack.IsPlaying then
			flyMoveTrack:Play(0.2)
		end
	else
		if flyMoveTrack and flyMoveTrack.IsPlaying then
			flyMoveTrack:Stop(0.2)
		end
		if flyIdleTrack and not flyIdleTrack.IsPlaying then
			flyIdleTrack:Play(0.2)
		end
	end
end

local function stopFerroHold()
	if ferroHoldTrack and ferroHoldTrack.IsPlaying then
		ferroHoldTrack:Stop(0.15)
	end
	ferroHolding = false
end

local function updateFerroHold()
	if not boundCharacter then
		stopFerroHold()
		return
	end
	local active = boundCharacter:GetAttribute("IsFerrokinesisActive") == true
	if not active then
		stopFerroHold()
		return
	end
	ensureFerroTracks(boundCharacter)
	if ferroThrowTrack and ferroThrowTrack.IsPlaying then
		return
	end
	ferroHolding = true
	if ferroHoldTrack and not ferroHoldTrack.IsPlaying then
		ferroHoldTrack:Play(0.15)
	end
end

local function onFlightEnd()
	flying = false
	flightMoving = false
	stopFlightTracks()
end

local function onFlightStart(character: Model)
	flying = true
	flightMoving = character:GetAttribute("FlightInputActive") == true
	ensureFlightTracks(character)
	updateFlightPlayback()
end

local function clearConnections()
	for _, conn in attributeConns do
		conn:Disconnect()
	end
	table.clear(attributeConns)
end

local function resetTracks()
	stopFlightTracks()
	stopFerroHold()
	flyIdleTrack = nil
	flyMoveTrack = nil
	ferroHoldTrack = nil
	ferroThrowTrack = nil
	pulseRightTrack = nil
	pulseLeftTrack = nil
	nextPulseUsesLeftHand = true
	flying = false
	flightMoving = false
	ferroHolding = false
end

local function bindCharacter(character: Model)
	clearConnections()
	resetTracks()
	boundCharacter = character

	if character:GetAttribute("IsMagneticFlying") == true then
		onFlightStart(character)
	end
	updateFerroHold()

	table.insert(attributeConns, character:GetAttributeChangedSignal("IsMagneticFlying"):Connect(function()
		if character:GetAttribute("IsMagneticFlying") == true then
			onFlightStart(character)
		else
			onFlightEnd()
		end
	end))

	table.insert(attributeConns, character:GetAttributeChangedSignal("FlightInputActive"):Connect(function()
		flightMoving = character:GetAttribute("FlightInputActive") == true
		updateFlightPlayback()
	end))

	table.insert(attributeConns, character:GetAttributeChangedSignal("IsFerrokinesisActive"):Connect(function()
		updateFerroHold()
	end))
end

function PolarisAbilityAnimations.playFerroThrow()
	local character = boundCharacter
	if not character or character:GetAttribute("IsFerrokinesisActive") ~= true then
		return
	end
	ensureFerroTracks(character)
	stopFerroHold()
	if ferroThrowTrack then
		ferroThrowTrack:Play(0.1)
		ferroThrowTrack.Stopped:Once(function()
			if character.Parent and character:GetAttribute("IsFerrokinesisActive") == true then
				updateFerroHold()
			end
		end)
	end
end

function PolarisAbilityAnimations.playHandCast()
	local character = boundCharacter
	if not character then
		return
	end
	ensurePulseTracks(character)
	if nextPulseUsesLeftHand then
		if pulseLeftTrack then
			pulseLeftTrack:Play(0.08)
		end
	else
		if pulseRightTrack then
			pulseRightTrack:Play(0.08)
		end
	end
	nextPulseUsesLeftHand = not nextPulseUsesLeftHand
end

function PolarisAbilityAnimations.playPulse()
	PolarisAbilityAnimations.playHandCast()
end

function PolarisAbilityAnimations.start(player: Player)
	local function onCharacterAdded(character: Model)
		if isPolarisPlayer(player) then
			bindCharacter(character)
		end
	end

	if player.Character and isPolarisPlayer(player) then
		onCharacterAdded(player.Character)
	end

	player.CharacterAdded:Connect(onCharacterAdded)
	player.CharacterRemoving:Connect(function()
		boundCharacter = nil
		clearConnections()
		resetTracks()
	end)

	player:GetAttributeChangedSignal("SelectedCharacter"):Connect(function()
		if not isPolarisPlayer(player) then
			boundCharacter = nil
			clearConnections()
			resetTracks()
		elseif player.Character then
			bindCharacter(player.Character)
		end
	end)
end

return PolarisAbilityAnimations
