--!strict
--[[
	Telekinetic Flight server: toggle flight with tilt, accel/decel, three input modes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AbilityCooldownHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityCooldownHelper"))
local EnergyConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("EnergyConstants"))
local TelekineticFlightConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TelekineticFlightConstants"))

local EnergyService = require(script.Parent:WaitForChild("EnergyService"))

local ABILITY_ID = TelekineticFlightConstants.ABILITY_ID
local COOLDOWN_SEC = TelekineticFlightConstants.COOLDOWN_SEC
local FLY_SPEED = TelekineticFlightConstants.FLY_SPEED
local VEL_LERP_MOVE = TelekineticFlightConstants.VEL_LERP_MOVE
local VEL_LERP_DECAY = TelekineticFlightConstants.VEL_LERP_DECAY
local NEAR_ZERO = Vector3.new(0.001, 0.001, 0.001)
local MODE_IDLE = TelekineticFlightConstants.FLIGHT_MODE_IDLE

type FlightState = {
	caster: Model,
	humanoid: Humanoid,
	root: BasePart,
	linearVel: LinearVelocity,
	gravityCancel: VectorForce,
	align: AlignOrientation,
	lookDir: Vector3,
	moveDir: Vector3,
	flightMode: number,
	currentVel: Vector3,
	originalWalkSpeed: number,
	originalJumpPower: number,
	originalJumpHeight: number?,
	originalJumpEnabled: boolean,
	originalAutoRotate: boolean,
}

local flightByPlayer: { [Player]: FlightState } = {}

local TelekineticFlightService = {}

local function isJeanGrey(plr: Player): boolean
	return plr:GetAttribute("SelectedCharacter") == "JeanGrey"
end

local function normalize(v: Vector3): Vector3
	if v.Magnitude < 0.01 then
		return Vector3.new(0, 0, -1)
	end
	return v.Unit
end

local function getRotate(direction: Vector3, velocityUnit: Vector3): number
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

local function endFlight(plr: Player, applyCooldown: boolean)
	local state = flightByPlayer[plr]
	if not state then
		return
	end
	flightByPlayer[plr] = nil

	local char = state.caster
	if char and char.Parent then
		char:SetAttribute("IsTelekineticFlying", nil)
		char:SetAttribute("FlightInputActive", nil)
		char:SetAttribute("FlightAlphaSpeed", nil)
	end

	for _, inst in { state.linearVel, state.gravityCancel, state.align } do
		if inst and inst.Parent then
			inst:Destroy()
		end
	end

	if state.humanoid.Parent then
		state.humanoid.WalkSpeed = state.originalWalkSpeed
		state.humanoid.JumpPower = state.originalJumpPower
		if state.originalJumpHeight then
			state.humanoid.JumpHeight = state.originalJumpHeight
		end
		state.humanoid.AutoRotate = state.originalAutoRotate
		state.humanoid.PlatformStand = false
		state.humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, state.originalJumpEnabled)
		state.humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	end

	if applyCooldown and char and char.Parent then
		AbilityCooldownHelper.apply(char, ABILITY_ID, COOLDOWN_SEC)
	end

	if char and char:GetAttribute("TelekinesisFlightMode") == true then
		require(script.Parent:WaitForChild("TelekinesisService")).forceEnd(plr)
	end
end

function TelekineticFlightService.forceEnd(plr: Player)
	endFlight(plr, false)
end

local function startFlight(plr: Player)
	local char = plr.Character
	if not char then
		return
	end
	if flightByPlayer[plr] then
		return
	end
	if char:GetAttribute("IsTelekinesisActive") == true
		and char:GetAttribute("TelekinesisFlightMode") ~= true
	then
		return
	end
	if char:GetAttribute("IsTelepathicSenseActive") == true then
		return
	end
	if AbilityCooldownHelper.isOnCooldown(char, ABILITY_ID) then
		return
	end
	if not EnergyService.hasMinimum(char, ABILITY_ID) then
		return
	end

	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root then
		return
	end

	local att = root:FindFirstChildOfClass("Attachment")
	if not att then
		att = Instance.new("Attachment")
		att.Name = "FlightAttachment"
		att.Parent = root
	end

	local linearVel = Instance.new("LinearVelocity")
	linearVel.Name = "TelekineticFlightLinearVel"
	linearVel.Attachment0 = att
	linearVel.MaxForce = math.huge
	linearVel.RelativeTo = Enum.ActuatorRelativeTo.World
	linearVel.VectorVelocity = Vector3.zero
	linearVel.Parent = root

	local gravityCancel = Instance.new("VectorForce")
	gravityCancel.Name = "TelekineticFlightGravityCancel"
	gravityCancel.Attachment0 = att
	gravityCancel.Force = Vector3.new(0, root.AssemblyMass * workspace.Gravity, 0)
	gravityCancel.RelativeTo = Enum.ActuatorRelativeTo.World
	gravityCancel.Parent = root

	local align = Instance.new("AlignOrientation")
	align.Name = "TelekineticFlightAlign"
	align.Attachment0 = att
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.MaxTorque = math.huge
	align.Responsiveness = TelekineticFlightConstants.ALIGN_RESPONSIVENESS
	align.RigidityEnabled = false
	align.CFrame = root.CFrame
	align.Parent = root

	humanoid.PlatformStand = true
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)

	flightByPlayer[plr] = {
		caster = char,
		humanoid = humanoid,
		root = root,
		linearVel = linearVel,
		gravityCancel = gravityCancel,
		align = align,
		lookDir = root.CFrame.LookVector,
		moveDir = Vector3.zero,
		flightMode = MODE_IDLE,
		currentVel = Vector3.zero,
		originalWalkSpeed = humanoid.WalkSpeed,
		originalJumpPower = humanoid.JumpPower,
		originalJumpHeight = humanoid.JumpHeight,
		originalJumpEnabled = humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping),
		originalAutoRotate = humanoid.AutoRotate,
	}

	char:SetAttribute("IsTelekineticFlying", true)
	char:SetAttribute("FlightInputActive", false)
	char:SetAttribute("FlightAlphaSpeed", 0)
end

function TelekineticFlightService.setup(flightToggle: RemoteEvent, flightInput: RemoteEvent)
	flightToggle.OnServerEvent:Connect(function(plr: Player, enable: boolean)
		if not isJeanGrey(plr) then
			return
		end
		if enable then
			startFlight(plr)
		else
			endFlight(plr, true)
		end
	end)

	flightInput.OnServerEvent:Connect(function(
		plr: Player,
		moveX: number,
		moveY: number,
		moveZ: number,
		lookX: number,
		lookY: number,
		lookZ: number,
		mode: number
	)
		local state = flightByPlayer[plr]
		if not state then
			return
		end
		state.moveDir = Vector3.new(moveX, moveY, moveZ)
		if state.moveDir.Magnitude > 1 then
			state.moveDir = state.moveDir.Unit
		elseif state.moveDir.Magnitude < 0.01 then
			state.moveDir = Vector3.zero
		end
		state.lookDir = normalize(Vector3.new(lookX, lookY, lookZ))
		state.flightMode = if typeof(mode) == "number" then math.floor(mode) else MODE_IDLE
	end)
end

function TelekineticFlightService.update(dt: number)
	local dtClamped = math.clamp(dt, 0.001, 0.1)
	local velLerpMoveAlpha = 1 - (1 - VEL_LERP_MOVE) ^ (dtClamped * 60)
	local velLerpDecayAlpha = 1 - (1 - VEL_LERP_DECAY) ^ (dtClamped * 60)

	for plr, state in flightByPlayer do
		if not state.caster.Parent or not state.humanoid.Parent or not state.root.Parent then
			endFlight(plr, false)
			continue
		end

		local char = state.caster
		local root = state.root
		local moveMag = state.moveDir.Magnitude
		local lookDir = state.lookDir

		local direction: Vector3
		if moveMag > 0.01 then
			direction = state.moveDir.Unit
		else
			direction = lookDir
		end
		if direction.Magnitude < 0.01 then
			direction = root.CFrame.LookVector
		end
		direction = direction.Unit

		local targetVel: Vector3
		local lerpAlpha: number
		if moveMag > 0.01 then
			targetVel = direction * FLY_SPEED
			lerpAlpha = velLerpMoveAlpha
		else
			targetVel = NEAR_ZERO
			lerpAlpha = velLerpDecayAlpha
		end

		state.currentVel = state.currentVel:Lerp(targetVel, lerpAlpha)
		local velMag = state.currentVel.Magnitude

		if state.linearVel.Parent then
			state.linearVel.VectorVelocity = state.currentVel
		end
		if state.gravityCancel.Parent then
			state.gravityCancel.Force = Vector3.new(0, root.AssemblyMass * workspace.Gravity, 0)
		end

		local alphaSpeed = if FLY_SPEED > 0 then velMag / FLY_SPEED else 0
		local bank = 0
		if velMag > 0.01 then
			bank = getRotate(direction, state.currentVel.Unit)
				* math.clamp(alphaSpeed * TelekineticFlightConstants.BANK_SPEED_SCALE, 0, 1)
				* TelekineticFlightConstants.BANK_SCALE
		end

		if state.align.Parent then
			local charPos = root.Position
			local baseCf: CFrame
			if math.abs(direction.Y) >= 0.99 then
				baseCf = CFrame.lookAt(charPos, charPos + direction, Vector3.new(1, 0, 0))
			else
				baseCf = CFrame.new(charPos, charPos + direction)
			end
			local pitchAlpha = math.min(1, alphaSpeed * TelekineticFlightConstants.PITCH_RESPONSE_FACTOR)
			local pitchDeg = TelekineticFlightConstants.PITCH_DEG_AT_MAX
			local bankDeg = math.clamp(bank, -TelekineticFlightConstants.BANK_MAX_DEG, TelekineticFlightConstants.BANK_MAX_DEG)
			local rollDeg = bankDeg * TelekineticFlightConstants.ROLL_BLEND
			local targetCf = baseCf * CFrame.Angles(
				math.rad(pitchAlpha * -pitchDeg),
				math.rad(bankDeg),
				math.rad(-rollDeg)
			)
			local rotAlpha = 1 - (1 - TelekineticFlightConstants.ROTATION_LERP) ^ (dtClamped * 60)
			state.align.CFrame = state.align.CFrame:Lerp(targetCf, rotAlpha)
		end

		char:SetAttribute("FlightInputActive", moveMag > 0.01)
		char:SetAttribute("FlightAlphaSpeed", math.clamp(alphaSpeed, 0, 1))
	end
end

function TelekineticFlightService.onPlayerRemoving(plr: Player)
	endFlight(plr, false)
end

return TelekineticFlightService
