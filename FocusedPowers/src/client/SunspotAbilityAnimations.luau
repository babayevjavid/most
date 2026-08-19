--!strict
--[[ Sunspot flight animations — same tracks as Polaris magnetic flight. ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PolarisConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PolarisConstants"))
local SunspotConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SunspotConstants"))

local ANIM = PolarisConstants.Animations
local UPPERCUT_ANIM = SunspotConstants.Animations.UPPERCUT_RIGHT

local SunspotAbilityAnimations = {}

local boundCharacter: Model? = nil
local attributeConns: { RBXScriptConnection } = {}

local flyIdleTrack: AnimationTrack? = nil
local flyMoveTrack: AnimationTrack? = nil
local uppercutTrack: AnimationTrack? = nil

local flying = false
local flightMoving = false

local function isSunspotPlayer(player: Player): boolean
	return player:GetAttribute("SelectedCharacter") == "Sunspot"
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
	flyIdleTrack = nil
	flyMoveTrack = nil
	uppercutTrack = nil
	flying = false
	flightMoving = false
end

local function bindCharacter(character: Model)
	clearConnections()
	resetTracks()
	boundCharacter = character

	if character:GetAttribute("IsSolarFlying") == true then
		onFlightStart(character)
	end

	table.insert(attributeConns, character:GetAttributeChangedSignal("IsSolarFlying"):Connect(function()
		if character:GetAttribute("IsSolarFlying") == true then
			onFlightStart(character)
		else
			onFlightEnd()
		end
	end))

	table.insert(attributeConns, character:GetAttributeChangedSignal("FlightInputActive"):Connect(function()
		flightMoving = character:GetAttribute("FlightInputActive") == true
		updateFlightPlayback()
	end))
end

function SunspotAbilityAnimations.playUppercut()
	local character = boundCharacter
	if not character then
		return
	end
	local animator = getAnimator(character)
	if not animator then
		return
	end
	if not uppercutTrack then
		uppercutTrack = loadTrack(animator, UPPERCUT_ANIM, Enum.AnimationPriority.Action4, false)
	end
	if uppercutTrack then
		uppercutTrack:Play(0.1)
	end
end

function SunspotAbilityAnimations.start(player: Player)
	local function onCharacterAdded(character: Model)
		if isSunspotPlayer(player) then
			bindCharacter(character)
		end
	end

	if player.Character and isSunspotPlayer(player) then
		onCharacterAdded(player.Character)
	end

	player.CharacterAdded:Connect(onCharacterAdded)
	player.CharacterRemoving:Connect(function()
		boundCharacter = nil
		clearConnections()
		resetTracks()
	end)

	player:GetAttributeChangedSignal("SelectedCharacter"):Connect(function()
		if not isSunspotPlayer(player) then
			boundCharacter = nil
			clearConnections()
			resetTracks()
		elseif player.Character then
			bindCharacter(player.Character)
		end
	end)
end

return SunspotAbilityAnimations
