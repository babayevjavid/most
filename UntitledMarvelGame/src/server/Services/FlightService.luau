--!strict

--[[

	Wanda flight — ported from NewMarvelProject NewFlightService (Scarlet Witch).

	LinearVelocity + gravity cancel + idle/move animation blend. NewMarvel pitch/bank with reduced forward tilt.

]]



local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RunService = game:GetService("RunService")



local AbilityConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityConstants"))

local HeroRegistry = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("HeroRegistry"))



local PlayerStateService = require(script.Parent.PlayerStateService)

local ShieldService = require(script.Parent.ShieldService)

local SprintService = require(script.Parent.SprintService)

local TelekinesisService = require(script.Parent.TelekinesisService)
local WandaHandParticlesService = require(script.Parent.WandaHandParticlesService)



local C = AbilityConstants



local NEAR_ZERO_VEL = Vector3.new(0.001, 0.001, 0.001)

local function GetRotate(direction: Vector3, velocityUnit: Vector3): number
	if direction.Magnitude < 0.01 or velocityUnit.Magnitude < 0.01 then
		return 0
	end
	local rootPos = Vector3.zero
	local lookVec = (CFrame.new(rootPos, rootPos + direction) * CFrame.Angles(0, math.rad(90), 0)).LookVector
	local dot = lookVec:Dot(velocityUnit)
	local len = lookVec.Magnitude * velocityUnit.Magnitude
	if len < 0.0001 then
		return 0
	end
	local deg = 90 - math.deg(math.acos(math.clamp(dot / len, -1, 1)))
	return math.clamp(deg, -90, 90)
end



type FlightState = {

	character: Model?,

	moveDir: Vector3,

	lookDir: Vector3,

	lastInputTime: number,

	linearVel: LinearVelocity?,

	linearVelAtt: Attachment?,

	gravityCancel: VectorForce?,

	gravCancelAtt: Attachment?,

	align: AlignOrientation?,

	att: Attachment?,

	tracks: { idle: AnimationTrack, move: AnimationTrack },

	originalWalkSpeed: number?,

	originalJumpPower: number?,

	originalJumpHeight: number?,

}



local FlightService = {}



local stateByPlayer: { [Player]: FlightState } = {}

local lastFlightToggleTime: { [Player]: number } = {}

local onStatUpdate: ((player: Player) -> ())? = nil

local onCooldown: ((player: Player, abilityId: string, duration: number) -> ())? = nil

local updateConn: RBXScriptConnection? = nil



local function canUseFlight(plr: Player): boolean

	local state = PlayerStateService.get(plr)

	if not state.HeroId then

		return false

	end

	return HeroRegistry.heroOwnsAbility(state.HeroId, "ChaosLevitate")

end



local function setWandaFlightTrailsEnabled(char: Model, enabled: boolean)

	for _, desc in char:GetDescendants() do

		if desc.Name == "HandTrail" then

			local trail = desc:FindFirstChild("Trail")

			if trail and trail:IsA("Trail") then

				trail.Enabled = enabled

			else

				local att = desc:FindFirstChild("Attachment")

				if att then

					local nested = att:FindFirstChild("Trail")

					if nested and nested:IsA("Trail") then

						nested.Enabled = enabled

					end

				end

			end

		end

	end

end



local function endFlight(plr: Player, applyCooldown: boolean)

	local s = stateByPlayer[plr]

	stateByPlayer[plr] = nil



	local char = plr.Character

	if char and char.Parent then

		char:SetAttribute("FlightAlphaSpeed", nil)

		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?

		if root and root.AssemblyLinearVelocity.Magnitude > 0 then

			local vel = root.AssemblyLinearVelocity

			vel = Vector3.new(vel.X * 0.92, vel.Y, vel.Z * 0.92)

			if vel.Y < -C.FLIGHT_MAX_LANDING_VERTICAL_SPEED then

				vel = Vector3.new(vel.X, -C.FLIGHT_MAX_LANDING_VERTICAL_SPEED, vel.Z)

			end

			root.AssemblyLinearVelocity = vel

		end

		char:SetAttribute("IsLevitating", nil)

		char:SetAttribute("NewFlightActive", nil)

		char:SetAttribute("FlightMoving", nil)

		char:SetAttribute("FlightInputActive", nil)



		local humanoid = char:FindFirstChildOfClass("Humanoid")

		if humanoid then

			humanoid.PlatformStand = false

			if s and s.originalWalkSpeed then

				humanoid.WalkSpeed = s.originalWalkSpeed

			end

			if s and s.originalJumpPower then

				humanoid.JumpPower = s.originalJumpPower

			end

			if s and s.originalJumpHeight then

				humanoid.JumpHeight = s.originalJumpHeight

			end

		end



		setWandaFlightTrailsEnabled(char, false)
		WandaHandParticlesService.disable(char)



		if applyCooldown then

			PlayerStateService.setCooldown(plr, "ChaosLevitate", os.clock() + C.FLIGHT_COOLDOWN)

			if onCooldown then

				onCooldown(plr, "ChaosLevitate", C.FLIGHT_COOLDOWN)

			end

		end

	end



	if s then

		if s.linearVel and s.linearVel.Parent then

			s.linearVel:Destroy()

		end

		if s.linearVelAtt and s.linearVelAtt.Parent then

			s.linearVelAtt:Destroy()

		end

		if s.gravityCancel and s.gravityCancel.Parent then

			s.gravityCancel:Destroy()

		end

		if s.gravCancelAtt and s.gravCancelAtt.Parent then

			s.gravCancelAtt:Destroy()

		end

		if s.align and s.align.Parent then

			s.align:Destroy()

		end

		if s.att and s.att.Parent then

			s.att:Destroy()

		end

		for _, track in { s.tracks.idle, s.tracks.move } do

			if track.IsPlaying then

				track:Stop()

			end

		end

	end



	if onStatUpdate then

		onStatUpdate(plr)

	end

end



local function startFlight(plr: Player, char: Model, humanoid: Humanoid, root: BasePart)

	char:SetAttribute("IsLevitating", true)

	char:SetAttribute("NewFlightActive", true)

	char:SetAttribute("FlightMoving", nil)

	char:SetAttribute("FlightInputActive", nil)

	humanoid.PlatformStand = true



	local animator = humanoid:FindFirstChildOfClass("Animator")

	if not animator then

		animator = Instance.new("Animator")

		animator.Parent = humanoid

	end



	local function loadAnim(id: string): AnimationTrack

		local anim = Instance.new("Animation")

		anim.AnimationId = id

		return humanoid:LoadAnimation(anim)

	end



	local tracks = {

		idle = loadAnim(C.FLIGHT_IDLE_ANIMATION_ID),

		move = loadAnim(C.FLIGHT_MOVE_ANIMATION_ID),

	}



	local att = Instance.new("Attachment")

	att.Name = "NewFlightAlignAtt"

	att.Parent = root

	local align = Instance.new("AlignOrientation")

	align.Mode = Enum.OrientationAlignmentMode.OneAttachment

	align.Attachment0 = att

	align.MaxTorque = math.huge

	align.Responsiveness = C.FLIGHT_ALIGN_RESPONSIVENESS

	align.Parent = root



	local linearVelAtt = Instance.new("Attachment")

	linearVelAtt.Name = "NewFlightLinearVelAtt"

	linearVelAtt.Parent = root

	local linearVel = Instance.new("LinearVelocity")

	linearVel.Name = "NewFlightLinearVel"

	linearVel.Attachment0 = linearVelAtt

	linearVel.RelativeTo = Enum.ActuatorRelativeTo.World

	linearVel.MaxForce = math.huge

	linearVel.VectorVelocity = Vector3.zero

	linearVel.Parent = root



	local gravCancelAtt = Instance.new("Attachment")

	gravCancelAtt.Name = "NewFlightGravCancelAtt"

	gravCancelAtt.Parent = root

	local gravityCancel = Instance.new("VectorForce")

	gravityCancel.Name = "NewFlightGravityCancel"

	gravityCancel.RelativeTo = Enum.ActuatorRelativeTo.World

	gravityCancel.Attachment0 = gravCancelAtt

	gravityCancel.Force = Vector3.new(0, root.AssemblyMass * workspace.Gravity, 0)

	gravityCancel.Parent = root



	align.Enabled = true

	align.CFrame = root.CFrame



	local look = root.CFrame.LookVector

	if look.Magnitude < 0.01 then

		look = Vector3.new(0, 0, -1)

	else

		look = look.Unit

	end



	setWandaFlightTrailsEnabled(char, true)
	WandaHandParticlesService.enable(char)
	WandaHandParticlesService.emit(char)



	stateByPlayer[plr] = {

		character = char,

		moveDir = Vector3.zero,

		lookDir = look,

		lastInputTime = os.clock(),

		linearVel = linearVel,

		linearVelAtt = linearVelAtt,

		gravityCancel = gravityCancel,

		gravCancelAtt = gravCancelAtt,

		align = align,

		att = att,

		tracks = tracks,

		originalWalkSpeed = humanoid.WalkSpeed,

		originalJumpPower = humanoid.JumpPower,

		originalJumpHeight = humanoid.JumpHeight,

	}



	humanoid.WalkSpeed = 0

	humanoid.JumpPower = 0

	if humanoid.JumpHeight then

		humanoid.JumpHeight = 0

	end



	tracks.idle:Play(0.3, 1, 1)



	humanoid.Died:Once(function()

		endFlight(plr, false)

	end)

end



local function toggleFlight(plr: Player)

	if not canUseFlight(plr) then

		return

	end



	local char = plr.Character

	if not char then

		return

	end



	local now = os.clock()

	local lastToggle = lastFlightToggleTime[plr]

	if lastToggle and (now - lastToggle) < C.FLIGHT_TOGGLE_COOLDOWN then

		return

	end

	lastFlightToggleTime[plr] = now



	if char:GetAttribute("NewFlightActive") == true then

		endFlight(plr, true)

		return

	end



	if PlayerStateService.isOnCooldown(plr, "ChaosLevitate") then

		return

	end

	if char:GetAttribute("IsShieldActive") == true then

		return

	end

	if TelekinesisService.isActive(plr) then

		return

	end

	local humanoid = char:FindFirstChildOfClass("Humanoid")

	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?

	if not humanoid or not root or humanoid.Health <= 0 then

		return

	end



	local playerState = PlayerStateService.get(plr)

	if playerState.Energy <= 0 then

		return

	end



	SprintService.forceStopSprint(plr)

	ShieldService.turnOff(plr)

	startFlight(plr, char, humanoid, root)



	if onStatUpdate then

		onStatUpdate(plr)

	end

end



local function onInput(plr: Player, moveX: number, moveY: number, moveZ: number, lookX: number, lookY: number, lookZ: number)

	local s = stateByPlayer[plr]

	if not s then

		return

	end



	local moveDir = Vector3.new(

		type(moveX) == "number" and moveX or 0,

		type(moveY) == "number" and moveY or 0,

		type(moveZ) == "number" and moveZ or 0

	)

	if moveDir.Magnitude > 1 then

		moveDir = moveDir.Unit

	end



	local lookDir = Vector3.new(

		type(lookX) == "number" and lookX or 0,

		type(lookY) == "number" and lookY or 0,

		type(lookZ) == "number" and lookZ or -1

	)

	if lookDir.Magnitude < 0.01 then

		lookDir = Vector3.new(0, 0, -1)

	else

		lookDir = lookDir.Unit

	end



	s.moveDir = moveDir

	s.lookDir = lookDir

	s.lastInputTime = os.clock()

end



local function updateFlight(dt: number)

	local now = os.clock()

	local dtClamped = math.clamp(dt, 0.001, 0.1)

	local velLerpMoveAlpha = 1 - (1 - C.FLIGHT_VEL_LERP_MOVE) ^ (dtClamped * 60)

	local velLerpDecayAlpha = 1 - (1 - C.FLIGHT_VEL_LERP_DECAY) ^ (dtClamped * 60)



	for plr, s in stateByPlayer do

		local char = plr.Character

		if s.character and char ~= s.character then

			endFlight(plr, true)

			continue

		end

		if not char or not char.Parent or char:GetAttribute("NewFlightActive") ~= true then

			endFlight(plr, true)

			continue

		end



		local humanoid = char:FindFirstChildOfClass("Humanoid")

		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?

		if not humanoid or not root or humanoid.Health <= 0 then

			endFlight(plr, true)

			continue

		end

		if char:GetAttribute("IsShieldActive") == true then

			endFlight(plr, true)

			continue

		end



		local moveDir = s.moveDir

		local lookDir = s.lookDir

		local moveMag = moveDir.Magnitude



		if now - s.lastInputTime > C.FLIGHT_STALE_INPUT_TIME and moveMag > 0.01 then

			s.moveDir = s.moveDir * 0.95

			moveDir = s.moveDir

			moveMag = moveDir.Magnitude

		end



		local playerState = PlayerStateService.get(plr)

		local drainRate = if moveMag > 0.01 then C.FLIGHT_ENERGY_DRAIN_MOVING else C.FLIGHT_ENERGY_DRAIN_IDLE

		playerState.Energy = math.max(0, playerState.Energy - drainRate * dtClamped)

		PlayerStateService.markResourceUsed(plr)

		if playerState.Energy <= 0 then

			endFlight(plr, true)

			continue

		end



		local direction: Vector3?

		if char:GetAttribute("IsChaosBeamActive") == true then

			local bx = char:GetAttribute("ChaosBeamLookX")

			local bz = char:GetAttribute("ChaosBeamLookZ")

			if type(bx) == "number" and type(bz) == "number" then

				local beamDir = Vector3.new(bx, 0, bz)

				if beamDir.Magnitude > 0.01 then

					direction = beamDir.Unit

				end

			end

		end

		if not direction then

			if moveMag > 0.01 then

				direction = moveDir.Unit

			else

				direction = lookDir

			end

			if direction.Magnitude < 0.01 then

				direction = lookDir

			end

			direction = direction.Unit

		end



		local flySpeed = C.FLIGHT_SPEED

		local velocity = root.AssemblyLinearVelocity

		local targetVel: Vector3

		local lerpAlpha: number

		if moveMag > 0.01 then

			targetVel = direction * flySpeed

			lerpAlpha = velLerpMoveAlpha

		else

			targetVel = NEAR_ZERO_VEL

			lerpAlpha = velLerpDecayAlpha

		end

		velocity = velocity:Lerp(targetVel, lerpAlpha)

		local velMag = velocity.Magnitude



		if s.linearVel and s.linearVel.Parent then

			s.linearVel.VectorVelocity = velocity

			s.linearVel.MaxForce = math.huge

		end

		if s.gravityCancel and s.gravityCancel.Parent then

			s.gravityCancel.Force = Vector3.new(0, root.AssemblyMass * workspace.Gravity, 0)

		end



		local alphaSpeed = velMag / flySpeed



		if s.align and s.align.Parent then
			local charPos = root.Position
			local baseCf: CFrame
			if math.abs(direction.Y) >= 0.99 then
				baseCf = CFrame.lookAt(charPos, charPos + direction, Vector3.new(1, 0, 0))
			else
				baseCf = CFrame.new(charPos, charPos + direction)
			end

			local difference = 0
			if velMag > 0.01 then
				difference = GetRotate(direction, velocity.Unit)
					* math.clamp(alphaSpeed * 1.2, 0, 1)
					* C.FLIGHT_BANK_SCALE
			end

			local pitchAlpha = math.min(1, alphaSpeed * C.FLIGHT_PITCH_RESPONSE_FACTOR)
			local targetCf = baseCf
				* CFrame.Angles(math.rad(pitchAlpha * -C.FLIGHT_PITCH_DEG_AT_MAX), math.rad(difference), 0)
			s.align.CFrame = s.align.CFrame:Lerp(targetCf, C.FLIGHT_ROTATION_LERP)
		end



		char:SetAttribute("FlightMoving", velMag > C.FLIGHT_IDLE_STOPPED_SPEED)

		char:SetAttribute("FlightInputActive", moveMag > 0.01)

		char:SetAttribute("FlightAlphaSpeed", math.clamp(alphaSpeed, 0, 1))



		local tracks = s.tracks

		local a = math.clamp(alphaSpeed, 0, 1)

		if not tracks.idle.IsPlaying then

			tracks.idle:Play(0.2, 1, 1)

		end

		if not tracks.move.IsPlaying then

			tracks.move:Play(0.2, 1, 1)

		end

		tracks.idle:AdjustWeight(1 - a, 0.1)

		tracks.move:AdjustWeight(a, 0.1)

		tracks.move:AdjustSpeed(0.9 + a * 0.35, 0.1)

	end

end



function FlightService.setup(

	flightToggle: RemoteEvent,

	flightInput: RemoteEvent,

	statUpdateCallback: (player: Player) -> (),

	cooldownCallback: (player: Player, abilityId: string, duration: number) -> ()

)

	onStatUpdate = statUpdateCallback

	onCooldown = cooldownCallback



	flightToggle.OnServerEvent:Connect(function(plr: Player)

		toggleFlight(plr)

	end)



	flightInput.OnServerEvent:Connect(function(

		plr: Player,

		moveX: number,

		moveY: number,

		moveZ: number,

		lookX: number,

		lookY: number,

		lookZ: number,

		_speedBoost: boolean?

	)

		onInput(plr, moveX, moveY, moveZ, lookX, lookY, lookZ)

	end)

end



function FlightService.startUpdateLoop()

	if updateConn then

		return

	end

	updateConn = RunService.Heartbeat:Connect(updateFlight)

end



function FlightService.forceStop(plr: Player, applyCooldown: boolean)

	endFlight(plr, applyCooldown)

end



function FlightService.cleanupPlayer(plr: Player)

	endFlight(plr, false)

	stateByPlayer[plr] = nil

	lastFlightToggleTime[plr] = nil

end



function FlightService.isFlying(plr: Player): boolean

	local char = plr.Character

	return char ~= nil and char:GetAttribute("NewFlightActive") == true

end



Players.PlayerRemoving:Connect(function(plr)

	endFlight(plr, false)

end)



return FlightService

