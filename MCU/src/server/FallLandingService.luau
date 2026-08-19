--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local AbilityCooldownHelper = require(ReplicatedStorage.Shared.AbilityCooldownHelper)
local CombatHelper = require(ReplicatedStorage.Shared.CombatHelper)
local GameConstants = require(ReplicatedStorage.Shared.GameConstants)
local PushHelper = require(ReplicatedStorage.Shared.PushHelper)
local RagdollStatus = require(ReplicatedStorage.Shared.RagdollStatus)
local VfxHelper = require(ReplicatedStorage.Shared.VfxHelper)

local FallLandingService = {}

type FallTrackState = {
	character: Model,
	peakHeightAboveGround: number,
	wasFlying: boolean,
}

type LandingLockState = {
	character: Model,
	walk: number,
	jumpPower: number?,
	jumpHeight: number?,
	hipHeight: number?,
	animTrack: AnimationTrack?,
	token: number,
}

local fallByPlayer: { [Player]: FallTrackState } = {}
local landingByPlayer: { [Player]: LandingLockState } = {}
local landingToken = 0

local function heightAboveGround(root: BasePart, character: Model): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local hit = Workspace:Raycast(root.Position, Vector3.new(0, -500, 0), params)
	if hit then
		return math.max(0, root.Position.Y - hit.Position.Y)
	end
	return 500
end

local function shouldTrackFall(character: Model): boolean
	if character:GetAttribute(GameConstants.HERO_ATTRIBUTE) == nil then
		return false
	end
	if character:GetAttribute(GameConstants.RAGDOLLED_ATTRIBUTE) == true then
		return false
	end
	if character:GetAttribute(GameConstants.IS_FLYING_ATTRIBUTE) == true then
		return false
	end
	if character:GetAttribute(GameConstants.MG_ASTRAL_BODY_ATTRIBUTE) == true then
		return false
	end
	if character:GetAttribute(GameConstants.ICE_SLIDE_ATTRIBUTE) == true then
		return false
	end
	if character:GetAttribute(GameConstants.HIGH_FALL_LANDING_ATTRIBUTE) == true then
		return false
	end
	if character:GetAttribute(GameConstants.BUSY_ATTRIBUTE) == true then
		return false
	end
	return true
end

local function playLandingAnim(character: Model): AnimationTrack?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = GameConstants.HIGH_FALL_LANDING_ANIM
	local ok, track = pcall(function()
		return (animator :: Animator):LoadAnimation(anim)
	end)
	anim:Destroy()
	if not ok or not track then
		return nil
	end
	track.Priority = Enum.AnimationPriority.Action4
	track.Looped = false
	track:Play(0, 1, 1)
	return track
end

local function applyLandingImpact(character: Model, landPos: Vector3)
	local heroId = character:GetAttribute(GameConstants.HERO_ATTRIBUTE)
	if heroId == "scarlet_witch" then
		return
	end

	local radius = GameConstants.HIGH_FALL_LANDING_RADIUS
	if heroId == "captain_marvel" then
		VfxHelper.spawnPhotonGroundSlam(landPos, radius)
	else
		VfxHelper.spawnPulseRing(landPos, radius * 0.7, Color3.fromRGB(220, 220, 230), 0.35)
		VfxHelper.spawnBurstSparks(landPos, Color3.fromRGB(240, 240, 245), 12)
	end
	pcall(function()
		VfxHelper.playWorldSound(GameConstants.TK_LAND_SOUND, landPos, 0.9)
	end)

	for _, victim in CombatHelper.overlapCharacters(landPos, radius, character) do
		if victim == character then
			continue
		end
		if victim:GetAttribute("LokiUltClone") == true or victim:GetAttribute("LokiDecoy") == true then
			continue
		end
		CombatHelper.dealDamage(character, victim, GameConstants.HIGH_FALL_LANDING_DAMAGE, landPos, "projectile")
		RagdollStatus.applyTimed(victim, GameConstants.HIGH_FALL_LANDING_RAGDOLL)
		local vRoot = victim:FindFirstChild("HumanoidRootPart") :: BasePart?
		local away = if vRoot then (vRoot.Position - landPos) else Vector3.new(0, 0, -1)
		if away.Magnitude < 0.05 then
			away = Vector3.new(0, 0, -1)
		end
		PushHelper.applyToCharacter(victim, away, {
			speed = GameConstants.HIGH_FALL_LANDING_PUSH_SPEED,
			upBoost = GameConstants.HIGH_FALL_LANDING_PUSH_UP,
		})
	end
end

local function lockMovement(humanoid: Humanoid)
	humanoid.WalkSpeed = 0
	humanoid.AutoRotate = false
	if humanoid.UseJumpPower then
		humanoid.JumpPower = 0
	else
		humanoid.JumpHeight = 0
	end
	humanoid:Move(Vector3.zero, false)
end

local function unlockMovement(state: LandingLockState)
	local character = state.character
	if not character.Parent then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	humanoid.WalkSpeed = state.walk
	humanoid.AutoRotate = true
	if state.jumpPower ~= nil then
		humanoid.JumpPower = state.jumpPower
	end
	if state.jumpHeight ~= nil then
		humanoid.JumpHeight = state.jumpHeight
	end
	if state.hipHeight ~= nil then
		humanoid.HipHeight = state.hipHeight
	end
	character:SetAttribute(GameConstants.HIGH_FALL_LANDING_ATTRIBUTE, nil)
end

local function endLandingLock(player: Player, token: number)
	local state = landingByPlayer[player]
	if not state or state.token ~= token then
		return
	end
	if state.animTrack then
		state.animTrack:Stop(0.12)
		state.animTrack:Destroy()
		state.animTrack = nil
	end
	unlockMovement(state)
	landingByPlayer[player] = nil
end

local function beginLandingLock(player: Player, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	landingToken += 1
	local token = landingToken
	local savedWalk = humanoid.WalkSpeed
	local savedJumpPower: number? = nil
	local savedJumpHeight: number? = nil
	if humanoid.UseJumpPower then
		savedJumpPower = humanoid.JumpPower
	else
		savedJumpHeight = humanoid.JumpHeight
	end

	character:SetAttribute(GameConstants.HIGH_FALL_LANDING_ATTRIBUTE, true)
	lockMovement(humanoid)

	local savedHip = humanoid.HipHeight
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character }
		local hit = Workspace:Raycast(root.Position + Vector3.new(0, 2, 0), Vector3.new(0, -12, 0), params)
		if hit then
			humanoid.HipHeight = GameConstants.HIGH_FALL_LANDING_HIP_HEIGHT
			local rot = root.CFrame - root.CFrame.Position
			root.CFrame = CFrame.new(root.Position.X, hit.Position.Y + humanoid.HipHeight, root.Position.Z) * rot
			root.AssemblyLinearVelocity = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z)
		end
	end

	local animTrack = playLandingAnim(character)
	local landPos = if root then root.Position else character:GetPivot().Position
	applyLandingImpact(character, landPos)
	local lockDuration = GameConstants.HIGH_FALL_LANDING_LOCK_FALLBACK
	if animTrack then
		lockDuration = math.max(animTrack.Length, lockDuration)
		animTrack.Stopped:Connect(function()
			endLandingLock(player, token)
		end)
	end

	landingByPlayer[player] = {
		character = character,
		walk = savedWalk,
		jumpPower = savedJumpPower,
		jumpHeight = savedJumpHeight,
		hipHeight = savedHip,
		animTrack = animTrack,
		token = token,
	}

	task.delay(lockDuration, function()
		endLandingLock(player, token)
	end)
end

local function clearFallTrack(player: Player)
	fallByPlayer[player] = nil
end

local function updateFallTrack(player: Player, character: Model, dt: number)
	local landingLock = landingByPlayer[player]
	if landingLock and landingLock.character == character then
		if character:GetAttribute(GameConstants.RAGDOLLED_ATTRIBUTE) == true then
			endLandingLock(player, landingLock.token)
			clearFallTrack(player)
			return
		end
		local hum = character:FindFirstChildOfClass("Humanoid")
		if hum and hum.Parent then
			lockMovement(hum)
		end
		return
	end

	if not shouldTrackFall(character) then
		clearFallTrack(player)
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		clearFallTrack(player)
		return
	end

	local state = fallByPlayer[player]
	if not state or state.character ~= character then
		state = {
			character = character,
			peakHeightAboveGround = 0,
			wasFlying = false,
		}
		fallByPlayer[player] = state
	end

	local flying = character:GetAttribute(GameConstants.IS_FLYING_ATTRIBUTE) == true
	if flying then
		state.wasFlying = true
		return
	end

	if state.wasFlying then
		state.wasFlying = false
	end

	local height = heightAboveGround(root, character)
	local vel = root.AssemblyLinearVelocity
	local falling = vel.Y < -2
	local humState = humanoid:GetState()
	local inAirState = humState == Enum.HumanoidStateType.Freefall
		or humState == Enum.HumanoidStateType.Jumping
		or humState == Enum.HumanoidStateType.FallingDown
	local trulyLanded = humState == Enum.HumanoidStateType.Landed
		or (
			(humState == Enum.HumanoidStateType.Running or humState == Enum.HumanoidStateType.RunningNoPhysics)
			and humanoid.FloorMaterial ~= Enum.Material.Air
			and height < 2.8
			and vel.Y > -6
		)

	if inAirState or (falling and height > 3) then
		state.peakHeightAboveGround = math.max(state.peakHeightAboveGround, height)
	end

	if trulyLanded and state.peakHeightAboveGround >= GameConstants.HIGH_FALL_LANDING_MIN_HEIGHT then
		local peak = state.peakHeightAboveGround
		state.peakHeightAboveGround = 0
		if character:GetAttribute(GameConstants.RAGDOLLED_ATTRIBUTE) ~= true then
			beginLandingLock(player, character)
		end
		return
	end

	if trulyLanded and not falling then
		state.peakHeightAboveGround = 0
	end

	-- dt unused but kept for heartbeat signature parity
	_ = dt
end

function FallLandingService.init()
	Players.PlayerRemoving:Connect(function(player)
		local state = landingByPlayer[player]
		if state then
			endLandingLock(player, state.token)
		end
		clearFallTrack(player)
	end)
end

function FallLandingService.update(_dt: number)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character then
			updateFallTrack(player, character, _dt)
		else
			clearFallTrack(player)
		end
	end
end

return FallLandingService
