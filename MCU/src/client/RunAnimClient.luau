--!strict
--[[
	Ground locomotion overlay:
	- walk (LOCOMOTION_ANIM) while moving without sprint
	- run (RUN_ANIM) while holding Shift sprint
	Idle / jump / flight / ragdoll stay on Animate.
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConstants = require(ReplicatedStorage.Shared.GameConstants)

local RunAnimClient = {}

local LOCO_STATES: { [Enum.HumanoidStateType]: boolean } = {
	[Enum.HumanoidStateType.Running] = true,
	[Enum.HumanoidStateType.RunningNoPhysics] = true,
	[Enum.HumanoidStateType.Landed] = true,
}

local function loadTrack(animator: Animator, assetId: string): AnimationTrack?
	local anim = Instance.new("Animation")
	anim.AnimationId = assetId
	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	anim:Destroy()
	if ok and track then
		track.Priority = Enum.AnimationPriority.Action
		track.Looped = true
		return track
	end
	return nil
end

function RunAnimClient.init(player: Player)
	local bound: Model? = nil
	local walkTrack: AnimationTrack? = nil
	local runTrack: AnimationTrack? = nil
	local mode: "none" | "walk" | "run" = "none"

	local function stopTracks(fade: number?)
		local fadeTime = fade or 0.12
		if walkTrack and walkTrack.IsPlaying then
			walkTrack:Stop(fadeTime)
		end
		if runTrack and runTrack.IsPlaying then
			runTrack:Stop(fadeTime)
		end
		mode = "none"
	end

	local function clear()
		stopTracks(0.08)
		if walkTrack then
			walkTrack:Destroy()
			walkTrack = nil
		end
		if runTrack then
			runTrack:Destroy()
			runTrack = nil
		end
		bound = nil
	end

	local function ensure(character: Model): boolean
		if bound == character and walkTrack and runTrack then
			return true
		end
		clear()
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return false
		end
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = humanoid
		end
		walkTrack = loadTrack(animator, GameConstants.LOCOMOTION_ANIM)
		runTrack = loadTrack(animator, GameConstants.RUN_ANIM)
		bound = character
		return walkTrack ~= nil and runTrack ~= nil
	end

	local function canLoco(character: Model, humanoid: Humanoid): boolean
		if humanoid.Health <= 0 then
			return false
		end
		if character:GetAttribute(GameConstants.IS_FLYING_ATTRIBUTE) == true then
			return false
		end
		if character:GetAttribute(GameConstants.RAGDOLLED_ATTRIBUTE) == true then
			return false
		end
		if character:GetAttribute(GameConstants.ICE_SLIDE_ATTRIBUTE) == true then
			return false
		end
		if character:GetAttribute(GameConstants.MG_ASTRAL_BODY_ATTRIBUTE) == true then
			return false
		end
		if character:GetAttribute(GameConstants.HIGH_FALL_LANDING_ATTRIBUTE) == true then
			return false
		end
		if character:GetAttribute(GameConstants.BUSY_ATTRIBUTE) == true then
			return false
		end
		if humanoid.WalkSpeed < 1 then
			return false
		end
		local state = humanoid:GetState()
		if not LOCO_STATES[state] then
			return false
		end
		if humanoid.MoveDirection.Magnitude < 0.08 then
			return false
		end
		return true
	end

	local function setMode(nextMode: "walk" | "run")
		if mode == nextMode then
			return
		end
		if nextMode == "walk" then
			if runTrack and runTrack.IsPlaying then
				runTrack:Stop(0.12)
			end
			if walkTrack and not walkTrack.IsPlaying then
				walkTrack:Play(0.12)
			end
		else
			if walkTrack and walkTrack.IsPlaying then
				walkTrack:Stop(0.12)
			end
			if runTrack and not runTrack.IsPlaying then
				runTrack:Play(0.12)
			end
		end
		mode = nextMode
	end

	RunService.RenderStepped:Connect(function()
		local character = player.Character
		if not character then
			if mode ~= "none" then
				clear()
			end
			return
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end
		if not ensure(character) then
			return
		end
		if not canLoco(character, humanoid) then
			if mode ~= "none" then
				stopTracks(0.12)
			end
			return
		end
		local sprinting = character:GetAttribute(GameConstants.SPRINTING_ATTRIBUTE) == true
		setMode(if sprinting then "run" else "walk")
		local active = if sprinting then runTrack else walkTrack
		if active and active.IsPlaying then
			local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local spd = 0
			if root then
				local vel = root.AssemblyLinearVelocity
				spd = Vector3.new(vel.X, 0, vel.Z).Magnitude
			end
			local base = if sprinting then GameConstants.SPRINT_WALK_SPEED else GameConstants.DEFAULT_WALK_SPEED
			active:AdjustSpeed(math.clamp(spd / math.max(base, 1), 0.85, 1.35))
		end
	end)

	player.CharacterRemoving:Connect(function()
		clear()
	end)
end

return RunAnimClient
