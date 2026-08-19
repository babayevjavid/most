--!strict
--[[ Havok ability animations — reuses Polaris hand-cast pulse tracks. ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PolarisConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PolarisConstants"))

local ANIM = PolarisConstants.Animations

local HavokAbilityAnimations = {}

local boundCharacter: Model? = nil
local pulseRightTrack: AnimationTrack? = nil
local pulseLeftTrack: AnimationTrack? = nil
local beamHoldTrack: AnimationTrack? = nil
local nextPulseUsesLeftHand = true

local function isHavokPlayer(player: Player): boolean
	return player:GetAttribute("SelectedCharacter") == "Havok"
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
	if not beamHoldTrack then
		beamHoldTrack = loadTrack(animator, ANIM.FERROKINESIS_HOLD, Enum.AnimationPriority.Action4, true)
	end
end

local function resetTracks()
	pulseRightTrack = nil
	pulseLeftTrack = nil
	beamHoldTrack = nil
	nextPulseUsesLeftHand = true
end

local function bindCharacter(character: Model)
	resetTracks()
	boundCharacter = character
end

function HavokAbilityAnimations.playHandCast()
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

function HavokAbilityAnimations.playBeamChannel()
	local character = boundCharacter
	if not character then
		return
	end
	ensurePulseTracks(character)
	if beamHoldTrack and not beamHoldTrack.IsPlaying then
		beamHoldTrack:Play(0.18, 1, 1.05)
	end
end

function HavokAbilityAnimations.stopBeamChannel()
	if beamHoldTrack and beamHoldTrack.IsPlaying then
		beamHoldTrack:Stop(0.15)
	end
end

function HavokAbilityAnimations.start(player: Player)
	local function onCharacterAdded(character: Model)
		if isHavokPlayer(player) then
			bindCharacter(character)
		end
	end

	if player.Character and isHavokPlayer(player) then
		onCharacterAdded(player.Character)
	end

	player.CharacterAdded:Connect(onCharacterAdded)
	player.CharacterRemoving:Connect(function()
		boundCharacter = nil
		resetTracks()
	end)

	player:GetAttributeChangedSignal("SelectedCharacter"):Connect(function()
		if not isHavokPlayer(player) then
			boundCharacter = nil
			resetTracks()
		elseif player.Character then
			bindCharacter(player.Character)
		end
	end)
end

return HavokAbilityAnimations
