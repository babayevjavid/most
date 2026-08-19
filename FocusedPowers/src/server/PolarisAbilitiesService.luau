--!strict
--[[ Polaris: Magnetic Flight, Magnetic Pulse, Metal Lance, Orbital Strikes. ]]

local Debris = game:GetService("Debris")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AbilityCombatHelper = require(Shared:WaitForChild("AbilityCombatHelper"))
local AbilityCooldownHelper = require(Shared:WaitForChild("AbilityCooldownHelper"))
local AbilityVfxHelper = require(Shared:WaitForChild("AbilityVfxHelper"))
local MetallicHelper = require(Shared:WaitForChild("MetallicHelper"))
local PolarisConstants = require(Shared:WaitForChild("PolarisConstants"))
local FerrokinesisService = require(script.Parent:WaitForChild("FerrokinesisService"))
local ResourceService = require(script.Parent:WaitForChild("ResourceService"))
local SteerableBoltService = require(script.Parent:WaitForChild("SteerableBoltService"))
local ProgressionService = require(script.Parent:WaitForChild("ProgressionService"))

local FLIGHT = PolarisConstants.MagneticFlight
local PULSE = PolarisConstants.MagneticPulse
local LANCE = PolarisConstants.MetalLance
local ORBITAL = PolarisConstants.OrbitalStrikes
local GREEN = PolarisConstants.POLARIS_GREEN
local NEAR_ZERO = Vector3.new(0.001, 0.001, 0.001)

type FlightState = {
	caster: Model,
	humanoid: Humanoid,
	root: BasePart,
	linearVel: LinearVelocity,
	gravityCancel: VectorForce,
	align: AlignOrientation,
	lookDir: Vector3,
	moveDir: Vector3,
	currentVel: Vector3,
	originalWalkSpeed: number,
	originalJumpPower: number,
	originalJumpHeight: number?,
	originalJumpEnabled: boolean,
	originalAutoRotate: boolean,
	originalRunningEnabled: boolean,
	lastFlightInputActive: boolean,
}

type LanceState = {
	caster: Player,
	targetModel: Model?,
	targetHum: Humanoid?,
	targetRoot: BasePart?,
	shard: BasePart,
	currentVel: Vector3,
	speedCap: number,
	launched: boolean,
	targetDiedConn: RBXScriptConnection?,
}

type OrbitalState = {
	caster: Player,
	shards: { BasePart },
	angle: number,
	aimPoint: Vector3,
}

type FlyingOrbitalShard = {
	shard: BasePart,
	throwVel: LinearVelocity,
	caster: Player,
	casterChar: Model,
	steerDir: Vector3,
	touched: boolean,
}

local flightByPlayer: { [Player]: FlightState } = {}
local lanceByPlayer: { [Player]: LanceState } = {}
local orbitalByPlayer: { [Player]: OrbitalState } = {}
local flyingOrbitalShards: { FlyingOrbitalShard } = {}
local lastOrbitalAimByPlayer: { [Player]: Vector3 } = {}

local pulseBoltConfig: SteerableBoltService.BoltConfig = {
	abilityId = PULSE.ABILITY_ID,
	boltName = "MagneticPulseBolt",
	size = PULSE.SIZE,
	color = GREEN,
	speed = PULSE.SPEED,
	maxRange = PULSE.RANGE,
	lifetime = PULSE.LIFETIME,
	damage = PULSE.DAMAGE,
	pushSpeed = PULSE.PUSH_SPEED,
	pushUp = PULSE.PUSH_UP,
	curveStrength = PULSE.CURVE_STRENGTH,
	impactRadius = PULSE.IMPACT_RADIUS,
	impactDuration = 0.35,
}

local function spawnMagneticPulseVisual(spawnCF: CFrame, config: SteerableBoltService.BoltConfig): BasePart
	return AbilityVfxHelper.spawnMagneticRingStack(
		spawnCF,
		config.color,
		PULSE.RING_COUNT,
		PULSE.RING_SPACING,
		PULSE.RING_OUTER_RADIUS,
		PULSE.RING_THICKNESS,
		PULSE.RING_INNER_RADIUS,
		PULSE.RING_SEGMENTS
	)
end

local PolarisAbilitiesService = {}

local function isPolaris(plr: Player): boolean
	return plr:GetAttribute("SelectedCharacter") == "Polaris"
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
	local lookVec = (CFrame.new(Vector3.zero, direction) * CFrame.Angles(0, math.rad(90), 0)).LookVector
	local dot = lookVec:Dot(velocityUnit)
	local len = lookVec.Magnitude * velocityUnit.Magnitude
	if len < 0.0001 then
		return 0
	end
	return math.clamp(90 - math.deg(math.acos(math.clamp(dot / len, -1, 1))), -90, 90)
end

local function spawnMetalShard(size: Vector3, position: Vector3): BasePart
	local part = Instance.new("Part")
	part.Size = size
	part.Color = Color3.fromRGB(150, 152, 158)
	part.Material = Enum.Material.Metal
	part.Anchored = false
	part.CanCollide = true
	part.CFrame = CFrame.new(position)
	part:SetAttribute("PolarisMetalShard", true)
	CollectionService:AddTag(part, "PolarisMetalShard")
	part.Parent = workspace
	return part
end

local function findNearestMetallic(origin: Vector3, radius: number, exclude: { Instance }): BasePart?
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	local best: BasePart? = nil
	local bestDist = math.huge
	for _, part in workspace:GetPartBoundsInRadius(origin, radius, params) do
		if part:IsA("BasePart") and MetallicHelper.partIsMetallicTarget(part, nil) then
			local d = (part.Position - origin).Magnitude
			if d < bestDist then
				bestDist = d
				best = MetallicHelper.getMetallicRoot(part)
			end
		end
	end
	return best
end

-- Magnetic Flight

local function endFlight(plr: Player, applyCooldown: boolean)
	local state = flightByPlayer[plr]
	if not state then
		return
	end
	flightByPlayer[plr] = nil
	local char = state.caster
	if char and char.Parent then
		char:SetAttribute("IsMagneticFlying", nil)
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
		state.humanoid:SetStateEnabled(Enum.HumanoidStateType.Running, state.originalRunningEnabled)
		state.humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	end
	if applyCooldown and char and char.Parent then
		AbilityCooldownHelper.apply(char, FLIGHT.ABILITY_ID, FLIGHT.COOLDOWN_SEC)
	end
end

local function startFlight(plr: Player)
	local char = plr.Character
	if not char or flightByPlayer[plr] then
		return
	end
	if char:GetAttribute("IsFerrokinesisActive") == true
		or char:GetAttribute("IsOrbitalStrikesActive") == true
		or char:GetAttribute("IsMetalLanceActive") == true
	then
		return
	end
	if AbilityCooldownHelper.isOnCooldown(char, FLIGHT.ABILITY_ID) then
		return
	end
	if not ResourceService.hasMinimum(char, "Polaris", FLIGHT.ABILITY_ID) then
		return
	end

	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root then
		return
	end

	local att = root:FindFirstChildOfClass("Attachment") or Instance.new("Attachment")
	att.Name = "FlightAttachment"
	att.Parent = root

	local linearVel = Instance.new("LinearVelocity")
	linearVel.Attachment0 = att
	linearVel.MaxForce = math.huge
	linearVel.RelativeTo = Enum.ActuatorRelativeTo.World
	linearVel.VectorVelocity = Vector3.zero
	linearVel.Parent = root

	local gravityCancel = Instance.new("VectorForce")
	gravityCancel.Attachment0 = att
	gravityCancel.Force = Vector3.new(0, root.AssemblyMass * workspace.Gravity, 0)
	gravityCancel.RelativeTo = Enum.ActuatorRelativeTo.World
	gravityCancel.Parent = root

	local align = Instance.new("AlignOrientation")
	align.Attachment0 = att
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.MaxTorque = math.huge
	align.Responsiveness = FLIGHT.ALIGN_RESPONSIVENESS
	align.CFrame = root.CFrame
	align.Parent = root

	humanoid.PlatformStand = true
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Running, false)

	flightByPlayer[plr] = {
		caster = char,
		humanoid = humanoid,
		root = root,
		linearVel = linearVel,
		gravityCancel = gravityCancel,
		align = align,
		lookDir = root.CFrame.LookVector,
		moveDir = Vector3.zero,
		currentVel = Vector3.zero,
		originalWalkSpeed = humanoid.WalkSpeed,
		originalJumpPower = humanoid.JumpPower,
		originalJumpHeight = humanoid.JumpHeight,
		originalJumpEnabled = humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping),
		originalAutoRotate = humanoid.AutoRotate,
		originalRunningEnabled = humanoid:GetStateEnabled(Enum.HumanoidStateType.Running),
		lastFlightInputActive = false,
	}
	char:SetAttribute("IsMagneticFlying", true)
	char:SetAttribute("FlightInputActive", false)
	char:SetAttribute("FlightAlphaSpeed", 0)
end

-- Metal Lance

local function spawnLanceSpike(position: Vector3, lookAtPos: Vector3): BasePart
	local part = Instance.new("Part")
	part.Size = LANCE.SHARD_SIZE
	part.Color = Color3.fromRGB(170, 174, 182)
	part.Material = Enum.Material.Metal
	part.Shape = Enum.PartType.Block
	part.Anchored = true
	part.CanCollide = false
	part.CFrame = CFrame.lookAt(position, lookAtPos)
	part:SetAttribute("PolarisMetalShard", true)
	CollectionService:AddTag(part, "PolarisMetalShard")
	part.Parent = workspace
	return part
end

local MAGNETIZE_ATTACH_PARTS = {
	"Head",
	"UpperTorso",
	"LowerTorso",
	"LeftUpperArm",
	"RightUpperArm",
	"LeftHand",
	"RightHand",
	"LeftLowerLeg",
	"RightLowerLeg",
}

local function clearMetalLanceMagnetize(targetModel: Model)
	targetModel:SetAttribute("MetalLanceMagnetized", nil)
	targetModel:SetAttribute("MetalLanceHitPulse", nil)
	local stored = targetModel:GetAttribute("MetalLanceOrigWalkSpeed")
	local hum = targetModel:FindFirstChildOfClass("Humanoid")
	if hum and typeof(stored) == "number" then
		hum.WalkSpeed = stored
	end
	targetModel:SetAttribute("MetalLanceOrigWalkSpeed", nil)
	for _, child in targetModel:GetChildren() do
		if child.Name == "MetalLanceShard" then
			child:Destroy()
		end
	end
	FerrokinesisService.forceEndHoldingTarget(targetModel)
end

local function applyMetalLanceMagnetize(targetModel: Model, humanoid: Humanoid)
	clearMetalLanceMagnetize(targetModel)

	local attachCandidates: { BasePart } = {}
	for _, name in MAGNETIZE_ATTACH_PARTS do
		local part = targetModel:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			table.insert(attachCandidates, part)
		end
	end
	local attachPart = if #attachCandidates > 0
		then attachCandidates[math.random(1, #attachCandidates)]
		else targetModel:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not attachPart then
		return
	end

	local shard = Instance.new("Part")
	shard.Name = "MetalLanceShard"
	shard.Size = LANCE.MAGNETIZE_SHARD_SIZE
	shard.Color = Color3.fromRGB(176, 182, 194)
	shard.Material = Enum.Material.Metal
	shard.CanCollide = false
	shard.CanQuery = true
	shard.CanTouch = true
	shard.Massless = true
	shard.Anchored = false
	shard.CFrame = attachPart.CFrame * CFrame.new(0, 0, -0.75) * CFrame.Angles(math.rad(90), 0, 0)
	shard.Parent = targetModel

	local metalFlag = Instance.new("BoolValue")
	metalFlag.Name = "Metal"
	metalFlag.Value = true
	metalFlag.Parent = shard

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = attachPart
	weld.Part1 = shard
	weld.Parent = shard

	targetModel:SetAttribute("MetalLanceMagnetized", true)
	targetModel:SetAttribute("MetalLanceHitPulse", tick())
	targetModel:SetAttribute("MetalLanceOrigWalkSpeed", humanoid.WalkSpeed)
	humanoid.WalkSpeed = humanoid.WalkSpeed * LANCE.MAGNETIZE_SLOW_MULT

	humanoid.Died:Once(function()
		if targetModel.Parent then
			clearMetalLanceMagnetize(targetModel)
		end
	end)

	task.delay(LANCE.MAGNETIZE_DURATION, function()
		if targetModel.Parent and targetModel:GetAttribute("MetalLanceMagnetized") == true then
			clearMetalLanceMagnetize(targetModel)
		end
	end)
end

local function endLance(plr: Player, applyCooldown: boolean, hit: boolean)
	local s = lanceByPlayer[plr]
	lanceByPlayer[plr] = nil
	if not s then
		return
	end
	local char = s.caster.Character
	if char and char.Parent then
		char:SetAttribute("IsMetalLanceActive", nil)
		char:SetAttribute("MetalLanceArmed", nil)
		local targetRef = char:FindFirstChild("MetalLanceTarget")
		if targetRef and targetRef:IsA("ObjectValue") then
			targetRef.Value = nil
		end
		if applyCooldown then
			AbilityCooldownHelper.apply(char, LANCE.ABILITY_ID, LANCE.COOLDOWN_SEC)
		end
	end
	if s.shard and s.shard.Parent then
		if not hit then
			s.shard.Anchored = false
			Debris:AddItem(s.shard, 4)
		else
			s.shard:Destroy()
		end
	end
	if s.targetDiedConn then
		s.targetDiedConn:Disconnect()
	end
	if applyCooldown and not hit then
		ProgressionService.grantAbilityXp(plr, LANCE.ABILITY_ID, "release")
	end
end

local function bindLanceTarget(s: LanceState, targetModel: Model)
	if s.targetDiedConn then
		s.targetDiedConn:Disconnect()
		s.targetDiedConn = nil
	end
	s.targetModel = targetModel
	s.targetHum = targetModel:FindFirstChildOfClass("Humanoid")
	s.targetRoot = targetModel:FindFirstChild("HumanoidRootPart") :: BasePart?
	if s.targetHum and s.targetHum.Health > 0 then
		s.targetDiedConn = s.targetHum.Died:Once(function()
			s.targetModel = nil
			s.targetHum = nil
			s.targetRoot = nil
			s.targetDiedConn = nil
			local char = s.caster.Character
			if char then
				local targetRef = char:FindFirstChild("MetalLanceTarget")
				if targetRef and targetRef:IsA("ObjectValue") then
					targetRef.Value = nil
				end
			end
		end)
	end
	local char = s.caster.Character
	if char then
		local targetRef = char:FindFirstChild("MetalLanceTarget")
		if not targetRef then
			targetRef = Instance.new("ObjectValue")
			targetRef.Name = "MetalLanceTarget"
			targetRef.Parent = char
		end
		(targetRef :: ObjectValue).Value = targetModel
	end
end

local function startLance(plr: Player, targetModel: Model?)
	if lanceByPlayer[plr] or not isPolaris(plr) then
		return
	end
	local char = plr.Character
	if not char or char:GetAttribute("IsMagneticFlying") == true then
		return
	end
	if char:GetAttribute("IsFerrokinesisActive") == true or char:GetAttribute("IsOrbitalStrikesActive") == true then
		return
	end
	if AbilityCooldownHelper.isOnCooldown(char, LANCE.ABILITY_ID) then
		return
	end
	if not ResourceService.hasMinimum(char, "Polaris", LANCE.ABILITY_ID) then
		return
	end

	local casterRoot = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not casterRoot then
		return
	end

	if targetModel then
		if targetModel == char then
			return
		end
		local hum = targetModel:FindFirstChildOfClass("Humanoid")
		local targetRoot = targetModel:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hum or hum.Health <= 0 or not targetRoot then
			targetModel = nil
		end
	end

	local offset = casterRoot.CFrame:VectorToWorldSpace(LANCE.NEARBY_OFFSET)
	local spawnPos = casterRoot.Position + offset
	local lookAt = if targetModel
		then (targetModel :: Model):GetPivot().Position
		else casterRoot.Position + casterRoot.CFrame.LookVector * 12
	local shard = spawnLanceSpike(spawnPos, lookAt)
	shard.Massless = true

	local state: LanceState = {
		caster = plr,
		targetModel = nil,
		targetHum = nil,
		targetRoot = nil,
		shard = shard,
		currentVel = Vector3.zero,
		speedCap = LANCE.CHASE_SPEED_START,
		launched = false,
		targetDiedConn = nil,
	}
	lanceByPlayer[plr] = state

	if targetModel then
		bindLanceTarget(state, targetModel)
	end

	char:SetAttribute("IsMetalLanceActive", true)
	char:SetAttribute("MetalLanceArmed", true)
	ProgressionService.grantAbilityXp(plr, LANCE.ABILITY_ID, "start")
end

local function launchLance(plr: Player, targetModel: Model)
	local s = lanceByPlayer[plr]
	if not s or s.launched or not s.shard.Parent then
		return
	end
	if not targetModel:IsA("Model") or targetModel == s.caster.Character then
		return
	end
	local hum = targetModel:FindFirstChildOfClass("Humanoid")
	local targetRoot = targetModel:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or hum.Health <= 0 or not targetRoot then
		return
	end
	local char = s.caster.Character
	local casterRoot = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not casterRoot or (targetRoot.Position - casterRoot.Position).Magnitude > LANCE.TARGET_MAX_DIST then
		return
	end

	bindLanceTarget(s, targetModel)
	s.launched = true
	s.speedCap = LANCE.CHASE_SPEED_START
	s.currentVel = Vector3.zero
	if char then
		char:SetAttribute("MetalLanceArmed", nil)
	end
	s.shard.Anchored = false
	s.shard.CanCollide = true
end

-- Orbital Strikes

local function endOrbital(plr: Player, applyCooldown: boolean)
	local s = orbitalByPlayer[plr]
	orbitalByPlayer[plr] = nil
	if not s then
		return
	end
	local char = s.caster.Character
	if char and char.Parent then
		char:SetAttribute("IsOrbitalStrikesActive", nil)
		char:SetAttribute("OrbitalShardCount", nil)
		if applyCooldown then
			AbilityCooldownHelper.apply(char, ORBITAL.ABILITY_ID, ORBITAL.COOLDOWN_SEC)
		end
	end
	for _, shard in s.shards do
		if shard.Parent then
			shard:Destroy()
		end
	end
end

local function startOrbital(plr: Player)
	if orbitalByPlayer[plr] or not isPolaris(plr) then
		return
	end
	local char = plr.Character
	if not char or char:GetAttribute("IsMagneticFlying") == true then
		return
	end
	if char:GetAttribute("IsFerrokinesisActive") == true or char:GetAttribute("IsMetalLanceActive") == true then
		return
	end
	if AbilityCooldownHelper.isOnCooldown(char, ORBITAL.ABILITY_ID) then
		return
	end
	if not ResourceService.hasMinimum(char, "Polaris", ORBITAL.ABILITY_ID) then
		return
	end

	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	local shards: { BasePart } = {}
	for i = 1, ORBITAL.SHARD_COUNT do
		local shard = spawnMetalShard(ORBITAL.SHARD_SIZE, root.Position)
		shard.CanCollide = false
		shard.Anchored = true
		table.insert(shards, shard)
	end

	orbitalByPlayer[plr] = {
		caster = plr,
		shards = shards,
		angle = 0,
		aimPoint = root.Position + root.CFrame.LookVector * 12,
	}
	char:SetAttribute("IsOrbitalStrikesActive", true)
	char:SetAttribute("OrbitalShardCount", #shards)
	ProgressionService.grantAbilityXp(plr, ORBITAL.ABILITY_ID, "start")
end

local function throwOrbitalShard(plr: Player, worldX: number, worldY: number, worldZ: number)
	local s = orbitalByPlayer[plr]
	if not s or #s.shards == 0 then
		return
	end
	local char = s.caster.Character
	if not char then
		return
	end
	local config = ResourceService.getConfig("Polaris")
	if not config or not ResourceService.trySpend(char, config.instant.OrbitalThrow or ORBITAL.THROW_COST) then
		endOrbital(plr, false)
		return
	end

	local shard = table.remove(s.shards, 1)
	if not shard or not shard.Parent then
		return
	end
	char:SetAttribute("OrbitalShardCount", #s.shards)

	local worldPoint = Vector3.new(worldX, worldY, worldZ)
	lastOrbitalAimByPlayer[plr] = worldPoint
	local direction = normalize(worldPoint - shard.Position)
	shard.Anchored = false
	shard.CanCollide = true
	shard.Massless = true

	local att = shard:FindFirstChildOfClass("Attachment")
	if not att then
		att = Instance.new("Attachment")
		att.Parent = shard
	end
	local throwVel = Instance.new("LinearVelocity")
	throwVel.Attachment0 = att
	throwVel.MaxForce = math.huge
	throwVel.RelativeTo = Enum.ActuatorRelativeTo.World
	throwVel.VectorVelocity = direction * ORBITAL.THROW_SPEED
	throwVel.Parent = shard
	shard.CFrame = CFrame.lookAt(shard.Position, shard.Position + direction)

	local flying: FlyingOrbitalShard = {
		shard = shard,
		throwVel = throwVel,
		caster = plr,
		casterChar = char,
		steerDir = direction,
		touched = false,
	}
	table.insert(flyingOrbitalShards, flying)

	local touched = false
	shard.Touched:Connect(function(hit)
		if flying.touched or touched or not hit or not hit.Parent then
			return
		end
		local model = hit:FindFirstAncestorOfClass("Model")
		if model == char then
			return
		end
		flying.touched = true
		touched = true
		local hum = if model then model:FindFirstChildOfClass("Humanoid") else nil
		local pushDir = flying.steerDir
		AbilityCombatHelper.damageAndPush(model or hit.Parent, hum, hit, pushDir, {
			damage = ORBITAL.DAMAGE,
			pushSpeed = ORBITAL.PUSH_SPEED,
			pushUp = ORBITAL.PUSH_UP,
		})
		throwVel:Destroy()
		shard:Destroy()
	end)
	Debris:AddItem(shard, 3)

	if #s.shards == 0 then
		endOrbital(plr, true)
	end
end

-- Magnetic Pulse

local function onPulseStart(plr: Player, dirX: number, dirY: number, dirZ: number)
	if not isPolaris(plr) then
		return
	end
	local char = plr.Character
	if not char then
		return
	end
	if char:GetAttribute("IsOrbitalStrikesActive") == true or char:GetAttribute("IsMetalLanceActive") == true then
		return
	end
	if AbilityCooldownHelper.isOnCooldown(char, PULSE.ABILITY_ID) then
		return
	end
	local config = ResourceService.getConfig("Polaris")
	if not config or not ResourceService.hasMinimum(char, "Polaris", PULSE.ABILITY_ID) then
		return
	end
	if not ResourceService.trySpend(char, config.instant.MagneticPulse or 3) then
		return
	end
	SteerableBoltService.handleStart(plr, PULSE.ABILITY_ID, dirX, dirY, dirZ, pulseBoltConfig, nil, spawnMagneticPulseVisual)
	ProgressionService.grantAbilityXp(plr, PULSE.ABILITY_ID, "fire")
end

local function onPulseRelease(plr: Player)
	SteerableBoltService.handleRelease(plr, PULSE.ABILITY_ID)
	local char = plr.Character
	if char and char.Parent then
		AbilityCooldownHelper.apply(char, PULSE.ABILITY_ID, PULSE.COOLDOWN_SEC)
	end
end

function PolarisAbilitiesService.forceEndFlight(plr: Player)
	endFlight(plr, false)
end

function PolarisAbilitiesService.forceEndOrbital(plr: Player)
	endOrbital(plr, false)
end

function PolarisAbilitiesService.forceEndLance(plr: Player)
	endLance(plr, false, false)
end

function PolarisAbilitiesService.setup(
	flightToggle: RemoteEvent,
	flightInput: RemoteEvent,
	pulseStart: RemoteEvent,
	pulseAim: RemoteEvent,
	pulseRelease: RemoteEvent,
	orbitalToggle: RemoteEvent,
	orbitalThrow: RemoteEvent,
	orbitalAim: RemoteEvent,
	lanceStart: RemoteEvent,
	lanceLaunch: RemoteEvent,
	lanceEnd: RemoteEvent
)
	flightToggle.OnServerEvent:Connect(function(plr: Player, enable: boolean)
		if not isPolaris(plr) then
			return
		end
		if enable then
			startFlight(plr)
		else
			endFlight(plr, true)
		end
	end)

	flightInput.OnServerEvent:Connect(function(plr, moveX, moveY, moveZ, lookX, lookY, lookZ)
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
	end)

	pulseStart.OnServerEvent:Connect(onPulseStart)
	pulseAim.OnServerEvent:Connect(function(plr, dirX, dirY, dirZ)
		SteerableBoltService.handleAim(plr, PULSE.ABILITY_ID, dirX, dirY, dirZ)
	end)
	pulseRelease.OnServerEvent:Connect(function(plr)
		if not isPolaris(plr) then
			return
		end
		onPulseRelease(plr)
	end)

	orbitalToggle.OnServerEvent:Connect(function(plr: Player)
		if not isPolaris(plr) then
			return
		end
		if orbitalByPlayer[plr] then
			endOrbital(plr, true)
		else
			startOrbital(plr)
		end
	end)

	orbitalThrow.OnServerEvent:Connect(function(plr, worldX, worldY, worldZ)
		if not isPolaris(plr) then
			return
		end
		local worldPoint = Vector3.new(worldX, worldY, worldZ)
		lastOrbitalAimByPlayer[plr] = worldPoint
		local s = orbitalByPlayer[plr]
		if s then
			s.aimPoint = worldPoint
		end
		throwOrbitalShard(plr, worldX, worldY, worldZ)
	end)

	orbitalAim.OnServerEvent:Connect(function(plr, worldX, worldY, worldZ)
		if not isPolaris(plr) then
			return
		end
		local worldPoint = Vector3.new(worldX, worldY, worldZ)
		lastOrbitalAimByPlayer[plr] = worldPoint
		local s = orbitalByPlayer[plr]
		if s then
			s.aimPoint = worldPoint
		end
	end)

	lanceStart.OnServerEvent:Connect(function(plr: Player, targetModel: Instance?)
		if not isPolaris(plr) then
			return
		end
		if typeof(targetModel) == "Instance" and targetModel:IsA("Model") then
			startLance(plr, targetModel)
		else
			startLance(plr, nil)
		end
	end)

	lanceLaunch.OnServerEvent:Connect(function(plr: Player, targetModel: Instance?)
		if not isPolaris(plr) then
			return
		end
		if typeof(targetModel) == "Instance" and targetModel:IsA("Model") then
			launchLance(plr, targetModel)
		end
	end)

	lanceEnd.OnServerEvent:Connect(function(plr: Player)
		endLance(plr, true, false)
	end)
end

function PolarisAbilitiesService.update(dt: number)
	local dtClamped = math.clamp(dt, 0.001, 0.1)
	local velLerpMove = 1 - (1 - FLIGHT.VEL_LERP_MOVE) ^ (dtClamped * 60)
	local velLerpDecay = 1 - (1 - FLIGHT.VEL_LERP_DECAY) ^ (dtClamped * 60)

	for plr, state in flightByPlayer do
		if not state.caster.Parent or not state.humanoid.Parent or not state.root.Parent then
			endFlight(plr, false)
			continue
		end
		local char = state.caster
		local moveMag = state.moveDir.Magnitude
		local direction = if moveMag > 0.01 then state.moveDir.Unit else state.lookDir
		if direction.Magnitude < 0.01 then
			direction = state.root.CFrame.LookVector.Unit
		end
		local targetVel = if moveMag > 0.01 then direction * FLIGHT.FLY_SPEED else NEAR_ZERO
		local lerpAlpha = if moveMag > 0.01 then velLerpMove else velLerpDecay
		state.currentVel = state.currentVel:Lerp(targetVel, lerpAlpha)
		state.linearVel.VectorVelocity = state.currentVel
		state.gravityCancel.Force = Vector3.new(0, state.root.AssemblyMass * workspace.Gravity, 0)

		local velMag = state.currentVel.Magnitude
		local alphaSpeed = if FLIGHT.FLY_SPEED > 0 then velMag / FLIGHT.FLY_SPEED else 0
		local facingDir = if moveMag > 0.01 then direction else state.lookDir
		if facingDir.Magnitude < 0.01 then
			facingDir = state.root.CFrame.LookVector
		else
			facingDir = facingDir.Unit
		end
		local charPos = state.root.Position
		local bank = 0
		local pitchAlpha = 0
		if moveMag > 0.01 and velMag > 2 then
			if velMag > 0.01 then
				bank = getRotate(direction, state.currentVel.Unit)
					* math.clamp(alphaSpeed * FLIGHT.BANK_SPEED_SCALE, 0, 1)
					* FLIGHT.BANK_SCALE
			end
			pitchAlpha = math.min(1, alphaSpeed * FLIGHT.PITCH_RESPONSE_FACTOR)
		end
		local baseCf = CFrame.new(charPos, charPos + facingDir)
		local targetCf = baseCf
			* CFrame.Angles(
				math.rad(pitchAlpha * -FLIGHT.PITCH_DEG_AT_MAX),
				math.rad(math.clamp(bank, -FLIGHT.BANK_MAX_DEG, FLIGHT.BANK_MAX_DEG)),
				math.rad(-bank * FLIGHT.ROLL_BLEND)
			)
		local rotLerp = if moveMag > 0.01 then FLIGHT.ROTATION_LERP else FLIGHT.IDLE_ROTATION_LERP
		local rotAlpha = 1 - (1 - rotLerp) ^ (dtClamped * 60)
		state.align.CFrame = state.align.CFrame:Lerp(targetCf, rotAlpha)
		local inputActive = moveMag > 0.01
		if state.lastFlightInputActive ~= inputActive then
			state.lastFlightInputActive = inputActive
			char:SetAttribute("FlightInputActive", inputActive)
		end
		char:SetAttribute("FlightAlphaSpeed", math.clamp(alphaSpeed, 0, 1))
	end

	for plr, s in lanceByPlayer do
		local char = s.caster.Character
		local casterRoot = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not char or not casterRoot or not s.shard.Parent then
			endLance(plr, true, false)
			continue
		end
		ProgressionService.tickAbilityHold(plr, LANCE.ABILITY_ID, dt)

		if not s.launched then
			local offset = casterRoot.CFrame:VectorToWorldSpace(LANCE.NEARBY_OFFSET)
			local pos = casterRoot.Position + offset
			local lookAt = if s.targetRoot and s.targetRoot.Parent
				then s.targetRoot.Position
				else casterRoot.Position + casterRoot.CFrame.LookVector * 12
			s.shard.CFrame = CFrame.lookAt(pos, lookAt)
			s.shard.Anchored = true
			continue
		end

		if not s.targetRoot or not s.targetRoot.Parent or not s.targetHum or s.targetHum.Health <= 0 then
			endLance(plr, true, false)
			continue
		end

		local toTarget = s.targetRoot.Position - s.shard.Position
		local dist = toTarget.Magnitude
		if dist < 2.5 then
			local pushDir = if dist > 0.01 then toTarget.Unit else s.targetRoot.CFrame.LookVector
			AbilityCombatHelper.damageAndPush(s.targetModel, s.targetHum, s.targetRoot, pushDir, {
				damage = LANCE.DAMAGE,
				pushSpeed = LANCE.PUSH_SPEED,
				pushUp = LANCE.PUSH_UP,
			})
			if s.targetModel and s.targetHum then
				applyMetalLanceMagnetize(s.targetModel, s.targetHum)
			end
			endLance(plr, true, true)
			continue
		end

		s.speedCap = math.min(LANCE.CHASE_SPEED_MAX, s.speedCap + dt * LANCE.CHASE_SPEED_RAMP)
		local desiredSpeed = math.min(s.speedCap, dist * 6)
		local desiredVel = if dist > 0.35 then toTarget.Unit * desiredSpeed else Vector3.zero
		local diff = desiredVel - s.currentVel
		local maxStep = dt * LANCE.CHASE_ACCEL
		local step = if diff.Magnitude <= maxStep then diff else diff.Unit * maxStep
		s.currentVel = s.currentVel + step
		s.shard.AssemblyLinearVelocity = s.currentVel
		local look = if s.currentVel.Magnitude > 0.01 then s.currentVel.Unit else toTarget.Unit
		s.shard.CFrame = CFrame.lookAt(s.shard.Position, s.shard.Position + look)
	end

	for plr, s in orbitalByPlayer do
		local char = s.caster.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			endOrbital(plr, false)
			continue
		end
		s.angle += ORBITAL.ORBIT_SPEED * dt
		local count = #s.shards
		local flatAim = Vector3.new(s.aimPoint.X, root.Position.Y, s.aimPoint.Z)
		local toAim = flatAim - root.Position
		local orbitCenter = if toAim.Magnitude > 0.5
			then root.Position + toAim.Unit * ORBITAL.ORBIT_RADIUS * 0.55
			else root.Position
		for i, shard in s.shards do
			if shard.Parent then
				local angle = s.angle + (i - 1) * (math.pi * 2 / math.max(count, 1))
				local offset = Vector3.new(math.cos(angle), 0.4, math.sin(angle)) * ORBITAL.ORBIT_RADIUS
				local pos = orbitCenter + offset
				shard.CFrame = CFrame.lookAt(pos, flatAim)
			end
		end
	end

	for i = #flyingOrbitalShards, 1, -1 do
		local flying = flyingOrbitalShards[i]
		if not flying.shard.Parent or not flying.throwVel.Parent then
			table.remove(flyingOrbitalShards, i)
			continue
		end
		local orbitalState = orbitalByPlayer[flying.caster]
		local aimPoint = if orbitalState
			then orbitalState.aimPoint
			else lastOrbitalAimByPlayer[flying.caster]
		if not aimPoint then
			continue
		end
		local toAim = aimPoint - flying.shard.Position
		if toAim.Magnitude > 0.05 then
			local targetDir = normalize(toAim)
			local steerAlpha = math.min(1, ORBITAL.THROW_STEER_RATE * dt)
			flying.steerDir = normalize(flying.steerDir:Lerp(targetDir, steerAlpha))
			flying.throwVel.VectorVelocity = flying.steerDir * ORBITAL.THROW_SPEED
			flying.shard.CFrame = CFrame.lookAt(flying.shard.Position, flying.shard.Position + flying.steerDir)
		end
	end
end

function PolarisAbilitiesService.onPlayerRemoving(plr: Player)
	endFlight(plr, false)
	endLance(plr, false, false)
	endOrbital(plr, false)
	lastOrbitalAimByPlayer[plr] = nil
end

return PolarisAbilitiesService
