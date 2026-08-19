--!strict
--[[
	Telekinesis: hold target in place with velocity steering; LMB throw with brief pull-in.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AbilityCooldownHelper = require(Shared:WaitForChild("AbilityCooldownHelper"))
local InteractableHelper = require(Shared:WaitForChild("InteractableHelper"))
local TelekinesisConstants = require(Shared:WaitForChild("TelekinesisConstants"))
local EnergyConstants = require(Shared:WaitForChild("EnergyConstants"))
local ProgressionService = require(script.Parent:WaitForChild("ProgressionService"))
local EnergyService = require(script.Parent:WaitForChild("EnergyService"))

local HOLD_DISTANCE = TelekinesisConstants.HOLD_DISTANCE
local HOLD_DISTANCE_MIN = TelekinesisConstants.HOLD_DISTANCE_MIN
local HOLD_DISTANCE_MAX = TelekinesisConstants.HOLD_DISTANCE_MAX
local HOLD_DISTANCE_LERP_SPEED = TelekinesisConstants.HOLD_DISTANCE_LERP_SPEED
local THROW_SPEED = TelekinesisConstants.THROW_SPEED
local THROW_UP_BOOST = TelekinesisConstants.THROW_UP_BOOST
local THROW_IMPULSE_MULT = TelekinesisConstants.THROW_IMPULSE_MULT
local THROW_DAMAGE = TelekinesisConstants.THROW_DAMAGE
local THROW_PULL_DURATION = TelekinesisConstants.THROW_PULL_DURATION
local THROW_PULL_DISTANCE = TelekinesisConstants.THROW_PULL_DISTANCE
local HOLD_SPEED = TelekinesisConstants.HOLD_SPEED
local HOLD_ACCEL = TelekinesisConstants.HOLD_ACCEL
local GRAB_DISTANCE_LOCK_SEC = TelekinesisConstants.GRAB_DISTANCE_LOCK_SEC
local CASTER_WALK_SPEED = TelekinesisConstants.CASTER_WALK_SPEED
local RAGDOLL_AFTER_THROW_SEC = TelekinesisConstants.RAGDOLL_AFTER_THROW_SEC
local TELEKINESIS_ABILITY_ID = "Telekinesis"
local COOLDOWN_SEC = TelekinesisConstants.COOLDOWN_SEC
local MAX_RANGE_SQ = TelekinesisConstants.RAYCAST_MAX_DIST * TelekinesisConstants.RAYCAST_MAX_DIST
local FLIGHT_MAX_TARGETS = TelekinesisConstants.FLIGHT_MAX_TARGETS
local FLIGHT_HOLD_DISTANCE = TelekinesisConstants.FLIGHT_HOLD_DISTANCE
local FLIGHT_HOLD_DISTANCE_MIN = TelekinesisConstants.FLIGHT_HOLD_DISTANCE_MIN
local FLIGHT_HOLD_DISTANCE_MAX = TelekinesisConstants.FLIGHT_HOLD_DISTANCE_MAX
local FLIGHT_TARGET_SPREAD_DEG = TelekinesisConstants.FLIGHT_TARGET_SPREAD_DEG
local FLIGHT_HOLD_SPEED = TelekinesisConstants.FLIGHT_HOLD_SPEED
local FLIGHT_HOLD_ACCEL = TelekinesisConstants.FLIGHT_HOLD_ACCEL

type TelekinesisTargetState = {
	root: BasePart,
	model: Model?,
	humanoid: Humanoid?,
	currentVel: Vector3,
	holdDistance: number,
	targetHoldDistance: number,
	grabTime: number,
	grabDistance: number,
	slotIndex: number,
}

type TelekinesisState = {
	caster: Player,
	targetRoot: BasePart,
	targetModel: Model?,
	targetHumanoid: Humanoid?,
	heldTargets: { TelekinesisTargetState },
	holdDistance: number,
	targetHoldDistance: number,
	holdDirection: Vector3,
	lastDrainTime: number,
	originalWalkSpeed: number?,
	originalJumpPower: number?,
	originalJumpHeight: number?,
	originalJumpingEnabled: boolean?,
	originalAutoJumpEnabled: boolean?,
	throwPhaseStartTime: number?,
	throwPhase: "pull"?,
	grabTime: number,
	grabDistance: number,
	isFlightMode: boolean,
}

local tkByPlayer: { [Player]: TelekinesisState } = {}

local function rotateFlatY(dir: Vector3, radians: number): Vector3
	local flat = Vector3.new(dir.X, 0, dir.Z)
	if flat.Magnitude < 0.01 then
		flat = Vector3.new(0, 0, -1)
	else
		flat = flat.Unit
	end
	local c, s = math.cos(radians), math.sin(radians)
	return Vector3.new(flat.X * c - flat.Z * s, dir.Y, flat.X * s + flat.Z * c).Unit
end

local function syncHeldCountAttribute(char: Model, count: number)
	char:SetAttribute("TelekinesisHeldCount", count)
end

local function setupHeldTarget(target: TelekinesisTargetState, slotIndex: number)
	target.slotIndex = slotIndex
	if target.model and target.humanoid then
		target.model:SetAttribute("Ragdolled", true)
		target.model:SetAttribute("TelekinesisHeld", true)
		target.humanoid.PlatformStand = true
		pcall(function()
			target.humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		end)
	elseif target.root and target.root:IsA("BasePart") then
		target.root:SetAttribute("TK_WasAnchored", target.root.Anchored)
		target.root.Anchored = false
		target.root:SetAttribute("TelekinesisHeld", true)
	end
end

local function isRootAlreadyHeld(s: TelekinesisState, root: BasePart): boolean
	for _, target in s.heldTargets do
		if target.root == root then
			return true
		end
	end
	return false
end

local function clampWorldPosToCasterRange(worldPos: Vector3, casterPos: Vector3, maxDist: number): Vector3
	local delta = worldPos - casterPos
	local d = delta.Magnitude
	if d > maxDist then
		return casterPos + delta.Unit * maxDist
	end
	return worldPos
end

local function isJeanGreyPlayer(plr: Player): boolean
	return plr:GetAttribute("SelectedCharacter") == "JeanGrey"
end

local function resolveTarget(hitPart: Instance?, casterRoot: BasePart)
	if not hitPart or not hitPart:IsA("BasePart") then
		return nil
	end
	local casterChar = casterRoot.Parent
	if casterChar and hitPart:IsDescendantOf(casterChar) then
		return nil
	end

	local model = hitPart:FindFirstAncestorOfClass("Model")
	if model and model ~= casterChar then
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			if humanoid.Health <= 0 then
				return nil
			end
			local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				return root, model, humanoid
			end
		end
		if InteractableHelper.modelIsInteractableProp(model) then
			local root = hitPart.AssemblyRootPart or hitPart
			return root, model, nil
		end
	end

	if InteractableHelper.hasInteractableMark(hitPart) then
		local root = hitPart.AssemblyRootPart or hitPart
		return root, nil, nil
	end
	return nil
end

local function clearTargetRagdolled(targetModel: Model?, targetHumanoid: Humanoid?)
	if targetModel then
		targetModel:SetAttribute("Ragdolled", nil)
	end
	if targetHumanoid and targetHumanoid.Parent and (not targetModel or targetModel:GetAttribute("Ragdolled") ~= true) then
		targetHumanoid.PlatformStand = false
	end
end

local function endTelekinesisFor(
	casterPlr: Player?,
	applyCooldown: boolean?,
	skipTargetRagdollClear: boolean?,
	fromThrow: boolean?
)
	if not casterPlr then
		return
	end
	local s = tkByPlayer[casterPlr]
	tkByPlayer[casterPlr] = nil
	if not s then
		return
	end

	local heldTargets = s.heldTargets
	if not heldTargets or #heldTargets == 0 then
		heldTargets = {
			{
				root = s.targetRoot,
				model = s.targetModel,
				humanoid = s.targetHumanoid,
				currentVel = Vector3.zero,
				holdDistance = s.holdDistance,
				targetHoldDistance = s.targetHoldDistance,
				grabTime = s.grabTime,
				grabDistance = s.grabDistance,
				slotIndex = 0,
			},
		}
	end

	for _, target in heldTargets do
		if target.model then
			target.model:SetAttribute("TelekinesisHeld", nil)
		end
		if target.root and target.root.Parent then
			target.root:SetAttribute("TelekinesisHeld", nil)
		end
	end

	local char = s.caster.Character
	if char and char.Parent then
		local humanoid = char:FindFirstChildOfClass("Humanoid")
		if humanoid then
			if s.originalWalkSpeed ~= nil then
				humanoid.WalkSpeed = s.originalWalkSpeed
			end
			if s.originalJumpPower ~= nil then
				humanoid.JumpPower = s.originalJumpPower
			end
			if s.originalJumpHeight ~= nil then
				humanoid.JumpHeight = s.originalJumpHeight
			end
			if s.originalJumpingEnabled ~= nil then
				humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, s.originalJumpingEnabled)
			end
			if s.originalAutoJumpEnabled ~= nil then
				humanoid.AutoJumpEnabled = s.originalAutoJumpEnabled
			end
		end
		char:SetAttribute("IsTelekinesisActive", nil)
		char:SetAttribute("TelekinesisHoldDistance", nil)
		char:SetAttribute("TelekinesisFlightMode", nil)
		char:SetAttribute("TelekinesisHeldCount", nil)
		local heldRef = char:FindFirstChild("TelekinesisHeldRoot")
		if heldRef and heldRef:IsA("ObjectValue") then
			heldRef.Value = nil
		end
		if applyCooldown then
			AbilityCooldownHelper.apply(char, TELEKINESIS_ABILITY_ID, COOLDOWN_SEC)
		end
	end

	ProgressionService.clearHoldTimer(casterPlr)
	if casterPlr and applyCooldown then
		if fromThrow then
			-- throw XP granted in applyThrowAndLaunch
		else
			ProgressionService.grantAbilityXp(casterPlr, TELEKINESIS_ABILITY_ID, "release")
		end
	end

	if not skipTargetRagdollClear then
		for _, target in heldTargets do
			clearTargetRagdolled(target.model, target.humanoid)
		end
	end

	for _, target in heldTargets do
		if target.root and target.root.Parent and not target.humanoid then
			local wasAnchored = target.root:GetAttribute("TK_WasAnchored")
			if wasAnchored ~= nil then
				target.root.Anchored = wasAnchored
				target.root:SetAttribute("TK_WasAnchored", nil)
			end
			pcall(function()
				target.root:SetNetworkOwnershipAuto()
			end)
		end
	end
end

local function applyThrowAndLaunch(s: TelekinesisState)
	local char = s.caster.Character
	if not char or not char.Parent then
		endTelekinesisFor(s.caster, false, false, false)
		return
	end

	local casterRoot = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local heldTargets = s.heldTargets
	if not heldTargets or #heldTargets == 0 then
		heldTargets = {
			{
				root = s.targetRoot,
				model = s.targetModel,
				humanoid = s.targetHumanoid,
				currentVel = Vector3.zero,
				holdDistance = s.holdDistance,
				targetHoldDistance = s.targetHoldDistance,
				grabTime = s.grabTime,
				grabDistance = s.grabDistance,
				slotIndex = 0,
			},
		}
	end

	local throwDir = if s.holdDirection.Magnitude > 0.01
		then s.holdDirection.Unit
		else (casterRoot and casterRoot.CFrame.LookVector or Vector3.new(0, 0, -1))
	local delayReanchorParts: { BasePart } = {}
	local thrownTargets: { { model: Model?, humanoid: Humanoid? } } = {}

	for _, target in heldTargets do
		if target.root and target.root.Parent then
			local vel = throwDir * THROW_SPEED + Vector3.new(0, THROW_UP_BOOST, 0)
			target.root.AssemblyLinearVelocity = vel
			pcall(function()
				target.root:ApplyImpulse(throwDir * (target.root.AssemblyMass * THROW_SPEED * THROW_IMPULSE_MULT))
			end)
			if target.humanoid then
				target.humanoid.PlatformStand = false
				if target.humanoid.Health > 0 then
					target.humanoid:TakeDamage(THROW_DAMAGE)
				end
				pcall(function()
					target.humanoid:ChangeState(Enum.HumanoidStateType.Physics)
				end)
			end
		end
		if not target.humanoid and target.root then
			local wasAnchored = target.root:GetAttribute("TK_WasAnchored")
			if wasAnchored == true then
				table.insert(delayReanchorParts, target.root)
				target.root:SetAttribute("TK_WasAnchored", nil)
			end
		end
		if target.model and target.humanoid then
			target.model:SetAttribute("Ragdolled", true)
		end
		table.insert(thrownTargets, { model = target.model, humanoid = target.humanoid })
	end

	char:SetAttribute("TelekinesisThrowPulse", tick())
	EnergyService.trySpend(char, EnergyConstants.INSTANT.TelekinesisThrow)
	ProgressionService.grantAbilityXp(s.caster, TELEKINESIS_ABILITY_ID, "throw")
	endTelekinesisFor(s.caster, true, true, true)

	task.delay(RAGDOLL_AFTER_THROW_SEC, function()
		for _, thrown in thrownTargets do
			clearTargetRagdolled(thrown.model, thrown.humanoid)
		end
	end)

	if #delayReanchorParts > 0 then
		task.delay(3, function()
			for _, part in delayReanchorParts do
				if part and part.Parent then
					part.Anchored = true
				end
			end
		end)
	end
end

local function buildTargetState(
	root: BasePart,
	targetModel: Model?,
	targetHumanoid: Humanoid?,
	casterRoot: BasePart,
	slotIndex: number,
	isFlightMode: boolean
): TelekinesisTargetState
	local minDist = if isFlightMode then FLIGHT_HOLD_DISTANCE_MIN else HOLD_DISTANCE_MIN
	local maxDist = if isFlightMode then FLIGHT_HOLD_DISTANCE_MAX else HOLD_DISTANCE_MAX
	local defaultDist = if isFlightMode then FLIGHT_HOLD_DISTANCE else HOLD_DISTANCE

	local delta = root.Position - casterRoot.Position
	local initialHoldDist = defaultDist
	if delta.Magnitude > 0.05 then
		initialHoldDist = delta.Magnitude
	end
	initialHoldDist = math.clamp(initialHoldDist, minDist, maxDist)

	return {
		root = root,
		model = targetHumanoid and targetModel or nil,
		humanoid = targetHumanoid,
		currentVel = Vector3.zero,
		holdDistance = initialHoldDist,
		targetHoldDistance = initialHoldDist,
		grabTime = tick(),
		grabDistance = initialHoldDist,
		slotIndex = slotIndex,
	}
end

local function tryAddTarget(plr: Player, hitPart: Instance?): boolean
	local s = tkByPlayer[plr]
	if not s or not s.isFlightMode then
		return false
	end
	if #s.heldTargets >= FLIGHT_MAX_TARGETS then
		return false
	end

	local char = plr.Character
	if not char or char:GetAttribute("IsTelekineticFlying") ~= true then
		return false
	end
	local casterRoot = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not casterRoot then
		return false
	end

	local root, targetModel, targetHumanoid = resolveTarget(hitPart, casterRoot)
	if not root or not root.Parent or isRootAlreadyHeld(s, root) then
		return false
	end

	local hitPos = (hitPart and hitPart:IsA("BasePart")) and hitPart.Position or root.Position
	if (hitPos - casterRoot.Position).Magnitude ^ 2 > MAX_RANGE_SQ then
		return false
	end

	local targetState = buildTargetState(root, targetModel, targetHumanoid, casterRoot, #s.heldTargets, true)
	table.insert(s.heldTargets, targetState)
	setupHeldTarget(targetState, targetState.slotIndex)
	syncHeldCountAttribute(char, #s.heldTargets)

	if targetHumanoid then
		targetHumanoid.Died:Once(function()
			endTelekinesisFor(plr, false, false, false)
		end)
	end
	return true
end

local function tryStart(plr: Player, hitPart: Instance?, cursorAnchorPos: Vector3?, flightMode: boolean?): boolean
	if tkByPlayer[plr] then
		return false
	end
	if not isJeanGreyPlayer(plr) then
		return false
	end

	local char = plr.Character
	if not char or not char.Parent then
		return false
	end
	local casterRoot = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not casterRoot or not humanoid or humanoid.Health <= 0 then
		return false
	end
	if char:GetAttribute("Ragdolled") == true then
		return false
	end
	local isFlying = char:GetAttribute("IsTelekineticFlying") == true
	if flightMode == true then
		if not isFlying then
			return false
		end
	else
		if isFlying then
			return false
		end
	end
	if char:GetAttribute("IsTelepathicSenseActive") == true then
		return false
	end

	if AbilityCooldownHelper.isOnCooldown(char, TELEKINESIS_ABILITY_ID) then
		return false
	end
	if not EnergyService.hasMinimum(char, TELEKINESIS_ABILITY_ID) then
		return false
	end

	local root, targetModel, targetHumanoid = resolveTarget(hitPart, casterRoot)
	if not root or not root.Parent then
		return false
	end

	local hitPos = (hitPart and hitPart:IsA("BasePart")) and hitPart.Position or root.Position
	if (hitPos - casterRoot.Position).Magnitude ^ 2 > MAX_RANGE_SQ then
		return false
	end

	local initialHoldDist = HOLD_DISTANCE
	local delta = root.Position - casterRoot.Position
	if delta.Magnitude > 0.05 then
		initialHoldDist = delta.Magnitude
	end
	if flightMode == true then
		initialHoldDist = math.clamp(initialHoldDist, FLIGHT_HOLD_DISTANCE_MIN, FLIGHT_HOLD_DISTANCE_MAX)
	else
		initialHoldDist = math.clamp(initialHoldDist, HOLD_DISTANCE_MIN, HOLD_DISTANCE_MAX)
	end

	local holdDirection = if delta.Magnitude > 0.05 then delta.Unit else casterRoot.CFrame.LookVector

	local heldTargets: { TelekinesisTargetState } = {
		buildTargetState(root, targetModel, targetHumanoid, casterRoot, 0, flightMode == true),
	}

	local s: TelekinesisState = {
		caster = plr,
		targetRoot = root,
		targetModel = targetHumanoid and targetModel or nil,
		targetHumanoid = targetHumanoid,
		heldTargets = heldTargets,
		holdDistance = initialHoldDist,
		targetHoldDistance = initialHoldDist,
		holdDirection = holdDirection,
		lastDrainTime = tick(),
		grabTime = tick(),
		grabDistance = initialHoldDist,
		isFlightMode = flightMode == true,
		originalWalkSpeed = if flightMode == true then nil else humanoid.WalkSpeed,
		originalJumpPower = if flightMode == true then nil else humanoid.JumpPower,
		originalJumpHeight = if flightMode == true then nil else humanoid.JumpHeight,
		originalJumpingEnabled = if flightMode == true then nil else humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping),
		originalAutoJumpEnabled = if flightMode == true then nil else humanoid.AutoJumpEnabled,
	}

	tkByPlayer[plr] = s
	char:SetAttribute("IsTelekinesisActive", true)
	char:SetAttribute("TelekinesisHoldDistance", initialHoldDist)
	if flightMode == true then
		char:SetAttribute("TelekinesisFlightMode", true)
		syncHeldCountAttribute(char, 1)
	end

	local heldRef = char:FindFirstChild("TelekinesisHeldRoot")
	if not heldRef then
		heldRef = Instance.new("ObjectValue")
		heldRef.Name = "TelekinesisHeldRoot"
		heldRef.Parent = char
	end
	(heldRef :: ObjectValue).Value = root

	if flightMode ~= true then
		humanoid.WalkSpeed = CASTER_WALK_SPEED
		humanoid.JumpPower = 0
		if humanoid.JumpHeight then
			humanoid.JumpHeight = 0
		end
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		humanoid.AutoJumpEnabled = false
	end

	for _, target in heldTargets do
		setupHeldTarget(target, target.slotIndex)
	end

	humanoid.Died:Once(function()
		endTelekinesisFor(plr, false, false, false)
	end)
	for _, target in heldTargets do
		if target.humanoid then
			target.humanoid.Died:Once(function()
				endTelekinesisFor(plr, false, false, false)
			end)
		end
	end

	ProgressionService.grantAbilityXp(plr, TELEKINESIS_ABILITY_ID, "start")
	return true
end

local function updateDirection(plr: Player, lookX: number, lookY: number, lookZ: number, _cursorAnchorPos: Vector3?, holdDistanceTarget: number?)
	local s = tkByPlayer[plr]
	if not s then
		return
	end
	local dir = Vector3.new(lookX or 0, lookY or 0, lookZ or -1)
	if dir.Magnitude < 0.01 then
		return
	end
	s.holdDirection = dir.Unit
	if typeof(holdDistanceTarget) == "number" then
		local minD = if s.isFlightMode then FLIGHT_HOLD_DISTANCE_MIN else HOLD_DISTANCE_MIN
		local maxD = if s.isFlightMode then FLIGHT_HOLD_DISTANCE_MAX else HOLD_DISTANCE_MAX
		local clamped = math.clamp(holdDistanceTarget, minD, maxD)
		if (tick() - s.grabTime) >= GRAB_DISTANCE_LOCK_SEC then
			s.targetHoldDistance = clamped
		elseif math.abs(clamped - s.grabDistance) > 0.5 then
			s.targetHoldDistance = clamped
			s.grabDistance = clamped
		end
		if s.isFlightMode then
			for _, target in s.heldTargets do
				target.targetHoldDistance = clamped
			end
		end
		local char = s.caster.Character
		if char then
			char:SetAttribute("TelekinesisHoldDistance", s.targetHoldDistance)
		end
	end
end

local function doThrow(plr: Player): boolean
	local s = tkByPlayer[plr]
	if not s then
		return false
	end
	if s.throwPhase == "pull" then
		return true
	end
	s.throwPhase = "pull"
	s.throwPhaseStartTime = tick()
	return true
end

local function update(dt: number, now: number)
	for plr, s in pairs(tkByPlayer) do
		local char = s.caster.Character
		if not char or not char.Parent then
			endTelekinesisFor(plr, false, false, false)
			continue
		end
		if char:GetAttribute("Ragdolled") == true then
			endTelekinesisFor(plr, false, false, false)
			continue
		end

		local casterRoot = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = char:FindFirstChildOfClass("Humanoid")
		if not casterRoot then
			endTelekinesisFor(plr, false, false, false)
			continue
		end

		if s.isFlightMode and char:GetAttribute("IsTelekineticFlying") ~= true then
			endTelekinesisFor(plr, false, false, false)
			continue
		end

		local aliveTargets: { TelekinesisTargetState } = {}
		for _, target in s.heldTargets do
			if target.root and target.root.Parent then
				table.insert(aliveTargets, target)
			else
				if target.model then
					target.model:SetAttribute("TelekinesisHeld", nil)
				end
				if target.root then
					target.root:SetAttribute("TelekinesisHeld", nil)
				end
			end
		end
		s.heldTargets = aliveTargets
		if #aliveTargets == 0 then
			endTelekinesisFor(plr, true, false, false)
			continue
		end
		s.targetRoot = aliveTargets[1].root
		syncHeldCountAttribute(char, #aliveTargets)

		if humanoid and humanoid.Parent and not s.isFlightMode then
			humanoid.WalkSpeed = CASTER_WALK_SPEED
			humanoid.JumpPower = 0
			if humanoid.JumpHeight then
				humanoid.JumpHeight = 0
			end
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
			humanoid.AutoJumpEnabled = false
		end

		if s.throwPhase == "pull" and type(s.throwPhaseStartTime) == "number" then
			if now - s.throwPhaseStartTime >= THROW_PULL_DURATION then
				applyThrowAndLaunch(s)
				continue
			end
		else
			ProgressionService.tickAbilityHold(plr, TELEKINESIS_ABILITY_ID, dt)
		end

		local sharedHoldDist = HOLD_DISTANCE
		if s.throwPhase == "pull" then
			sharedHoldDist = THROW_PULL_DISTANCE
		elseif not s.isFlightMode then
			local targetDist = if (now - s.grabTime) < GRAB_DISTANCE_LOCK_SEC then s.grabDistance else s.targetHoldDistance
			local alpha = math.min(1, dt * HOLD_DISTANCE_LERP_SPEED)
			s.holdDistance = s.holdDistance + (targetDist - s.holdDistance) * alpha
			sharedHoldDist = s.holdDistance
		end

		local holdSpeed = if s.isFlightMode then FLIGHT_HOLD_SPEED else HOLD_SPEED
		local holdAccel = if s.isFlightMode then FLIGHT_HOLD_ACCEL else HOLD_ACCEL
		local spreadCenter = (#s.heldTargets - 1) * 0.5

		for _, target in s.heldTargets do
			if not (target.root and target.root.Parent) then
				continue
			end
			if target.humanoid and target.humanoid.Parent then
				target.humanoid.PlatformStand = true
			elseif target.root:IsA("BasePart") then
				target.root.Anchored = false
			end

			local holdDist = sharedHoldDist
			if s.isFlightMode and s.throwPhase ~= "pull" then
				local targetDist = if (now - target.grabTime) < GRAB_DISTANCE_LOCK_SEC
					then target.grabDistance
					else target.targetHoldDistance
				local alpha = math.min(1, dt * HOLD_DISTANCE_LERP_SPEED)
				target.holdDistance = target.holdDistance + (targetDist - target.holdDistance) * alpha
				holdDist = target.holdDistance
			end

			local flat = Vector3.new(s.holdDirection.X, 0, s.holdDirection.Z)
			if flat.Magnitude < 0.01 then
				flat = Vector3.new(0, 0, -1)
			else
				flat = flat.Unit
			end
			local slotDir = -flat
			if s.isFlightMode then
				local angleDeg = (target.slotIndex - spreadCenter) * FLIGHT_TARGET_SPREAD_DEG
				slotDir = rotateFlatY(slotDir, math.rad(angleDeg))
			end

			local holdAnchor = casterRoot.Position + slotDir * holdDist
			holdAnchor = clampWorldPosToCasterRange(holdAnchor, casterRoot.Position, TelekinesisConstants.RAYCAST_MAX_DIST)

			local desiredPos = holdAnchor
			local currentPos = target.root.Position
			local toDesired = desiredPos - currentPos
			local dist = toDesired.Magnitude
			local desiredVel = Vector3.zero
			if dist > 0.35 then
				local dir = toDesired.Unit
				local speed = math.min(holdSpeed, dist * 5)
				desiredVel = dir * speed
			end
			if not s.isFlightMode then
				desiredVel = desiredVel + Vector3.new(0, workspace.Gravity * dt, 0)
			end

			local currentVel = target.currentVel
			local diff = desiredVel - currentVel
			local maxStep = dt * holdAccel
			local step = if diff.Magnitude <= maxStep then diff else diff.Unit * maxStep
			currentVel = currentVel + step
			target.currentVel = currentVel
			target.root.AssemblyLinearVelocity = currentVel
		end
	end
end

local TelekinesisService = {}

function TelekinesisService.setup(
	telekinesisRequest: RemoteEvent,
	telekinesisUpdate: RemoteEvent,
	telekinesisThrow: RemoteEvent,
	telekinesisEnd: RemoteEvent
)
	telekinesisRequest.OnServerEvent:Connect(function(plr: Player, hitPart: Instance?, cursorAnchorPos: Vector3?, flightMode: unknown)
		local existing = tkByPlayer[plr]
		if existing then
			if existing.isFlightMode and flightMode == true then
				tryAddTarget(plr, hitPart)
			end
			return
		end
		tryStart(plr, hitPart, cursorAnchorPos, flightMode == true)
	end)

	telekinesisUpdate.OnServerEvent:Connect(function(
		plr: Player,
		lookX: number,
		lookY: number,
		lookZ: number,
		cursorAnchorPos: Vector3?,
		holdDistanceTarget: number?
	)
		if not tkByPlayer[plr] then
			return
		end
		updateDirection(plr, lookX, lookY, lookZ, cursorAnchorPos, holdDistanceTarget)
	end)

	telekinesisThrow.OnServerEvent:Connect(function(plr: Player)
		if not tkByPlayer[plr] then
			return
		end
		doThrow(plr)
	end)

	telekinesisEnd.OnServerEvent:Connect(function(plr: Player)
		local s = tkByPlayer[plr]
		if not s then
			return
		end
		if s.throwPhase == "pull" then
			return
		end
		endTelekinesisFor(plr, true, false, false)
	end)
end

function TelekinesisService.update(dt: number, now: number)
	update(dt, now)
end

function TelekinesisService.onPlayerRemoving(plr: Player)
	if tkByPlayer[plr] then
		endTelekinesisFor(plr, false, false, false)
	end
end

function TelekinesisService.forceEnd(plr: Player)
	if tkByPlayer[plr] then
		endTelekinesisFor(plr, false, false, false)
	end
end

return TelekinesisService
