--!strict
--[[ Havok: siphon charges, burst, beam, surge, blast. ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AbilityCombatHelper = require(Shared:WaitForChild("AbilityCombatHelper"))
local AbilityCooldownHelper = require(Shared:WaitForChild("AbilityCooldownHelper"))
local AbilityVfxHelper = require(Shared:WaitForChild("AbilityVfxHelper"))
local HavokConstants = require(Shared:WaitForChild("HavokConstants"))
local PushHelper = require(Shared:WaitForChild("PushHelper"))
local ResourceService = require(script.Parent:WaitForChild("ResourceService"))
local ProgressionService = require(script.Parent:WaitForChild("ProgressionService"))
local SteerableBoltService = require(script.Parent:WaitForChild("SteerableBoltService"))

local SIPHON = HavokConstants.EnergySiphon
local BURST = HavokConstants.EnergyBurst
local BEAM = HavokConstants.ConcussiveBeam
local BLAST = HavokConstants.EnergyBlast
local SURGE = HavokConstants.KineticSurge
local BLUE = HavokConstants.HAVOK_BLUE
local BLUE_SOFT = HavokConstants.HAVOK_BLUE_SOFT
local CHAR_ID = "Havok"

type BeamState = {
	caster: Player,
	char: Model,
	aimDir: Vector3,
	lastTick: number,
	holdTime: number,
}

type SurgeState = {
	caster: Player,
	root: BasePart,
	humanoid: Humanoid,
	elapsed: number,
	duration: number,
	linearVel: LinearVelocity,
	savedAutoRotate: boolean,
	surgeDir: Vector3,
}

local beamByPlayer: { [Player]: BeamState } = {}
local surgeByPlayer: { [Player]: SurgeState } = {}

local blastBoltConfig: SteerableBoltService.BoltConfig = {
	abilityId = BLAST.ABILITY_ID,
	boltName = "HavokEnergyBlast",
	size = BLAST.SIZE,
	color = BLUE,
	speed = BLAST.SPEED,
	maxRange = BLAST.RANGE,
	lifetime = BLAST.LIFETIME,
	damage = BLAST.DAMAGE,
	pushSpeed = BLAST.PUSH_SPEED,
	pushUp = BLAST.PUSH_UP,
	curveStrength = BLAST.CURVE_STRENGTH,
	impactRadius = BLAST.IMPACT_RADIUS,
	impactDuration = BLAST.IMPACT_DURATION,
}

local HavokAbilitiesService = {}

local function isHavok(plr: Player): boolean
	return plr:GetAttribute("SelectedCharacter") == CHAR_ID
end

local function getChestPart(char: Model): BasePart?
	return char:FindFirstChild("UpperTorso") :: BasePart?
		or char:FindFirstChild("Torso") :: BasePart?
		or char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function normalizeDir(x: number, y: number, z: number): Vector3
	local v = Vector3.new(x, y, z)
	if v.Magnitude < 0.01 then
		return Vector3.new(0, 0, -1)
	end
	return v.Unit
end

local function getCharge(char: Model): number
	local charge = char:GetAttribute("HavokCharge")
	return if typeof(charge) == "number" then math.clamp(math.floor(charge), 0, SIPHON.MAX_CHARGE) else 0
end

local function setCharge(char: Model, value: number)
	char:SetAttribute("HavokCharge", math.clamp(value, 0, SIPHON.MAX_CHARGE))
end

local function spawnHavokBlastVisual(spawnCF: CFrame, config: SteerableBoltService.BoltConfig): BasePart
	return AbilityVfxHelper.spawnMagneticRingStack(
		spawnCF,
		config.color,
		BLAST.RING_COUNT,
		BLAST.RING_SPACING,
		BLAST.RING_OUTER_RADIUS,
		BLAST.RING_THICKNESS,
		BLAST.RING_INNER_RADIUS,
		BLAST.RING_SEGMENTS
	)
end

function HavokAbilitiesService.initCharacter(char: Model)
	char:SetAttribute("HavokCharge", 0)
	char:SetAttribute("MaxHavokCharge", SIPHON.MAX_CHARGE)
	char:SetAttribute("IsConcussiveBeamActive", nil)
	char:SetAttribute("IsKineticSurgeActive", nil)
	char:SetAttribute("IsEnergyBlastActive", nil)
end

local function setBeamAimAttribute(char: Model, aimDir: Vector3)
	char:SetAttribute("HavokBeamDirX", aimDir.X)
	char:SetAttribute("HavokBeamDirY", aimDir.Y)
	char:SetAttribute("HavokBeamDirZ", aimDir.Z)
end

local function clearBeamAimAttribute(char: Model)
	char:SetAttribute("HavokBeamDirX", nil)
	char:SetAttribute("HavokBeamDirY", nil)
	char:SetAttribute("HavokBeamDirZ", nil)
	char:SetAttribute("HavokBeamIntensity", nil)
end

function HavokAbilitiesService.forceEndBeam(plr: Player)
	local char = plr.Character
	beamByPlayer[plr] = nil
	if char and char.Parent then
		char:SetAttribute("IsConcussiveBeamActive", nil)
		clearBeamAimAttribute(char)
		AbilityCooldownHelper.apply(char, BEAM.ABILITY_ID, BEAM.COOLDOWN_SEC)
	end
end

function HavokAbilitiesService.forceEndSurge(plr: Player)
	local state = surgeByPlayer[plr]
	if state then
		if state.linearVel.Parent then
			state.linearVel:Destroy()
		end
		if state.humanoid.Parent then
			state.humanoid.AutoRotate = state.savedAutoRotate
		end
	end
	surgeByPlayer[plr] = nil
	local char = plr.Character
	if char and char.Parent then
		char:SetAttribute("IsKineticSurgeActive", nil)
	end
end

local function getOrCreateSurgeAttachment(root: BasePart): Attachment
	local att = root:FindFirstChild("HavokSurgeAttachment") :: Attachment?
	if not att then
		att = Instance.new("Attachment")
		att.Name = "HavokSurgeAttachment"
		att.Parent = root
	end
	return att
end

local function createSurgeVelocity(root: BasePart, direction: Vector3): LinearVelocity
	local linearVel = Instance.new("LinearVelocity")
	linearVel.Name = "HavokSurgeVelocity"
	linearVel.Attachment0 = getOrCreateSurgeAttachment(root)
	linearVel.MaxForce = math.huge
	linearVel.RelativeTo = Enum.ActuatorRelativeTo.World
	linearVel.VectorVelocity = direction * SURGE.BOOST_SPEED
	linearVel.Parent = root
	return linearVel
end

local function endBeam(plr: Player)
	HavokAbilitiesService.forceEndBeam(plr)
end

local function tickBeam(plr: Player, state: BeamState, now: number)
	if now - state.lastTick < BEAM.TICK_INTERVAL then
		return
	end
	state.lastTick = now

	local chest = getChestPart(state.char)
	if not chest then
		endBeam(plr)
		return
	end

	local origin = chest.Position + state.aimDir * 1.4
	local ramp = math.clamp(state.holdTime / BEAM.RAMP_SEC, 0, 1)
	local damageMult = BEAM.MIN_DAMAGE_MULT + (1 - BEAM.MIN_DAMAGE_MULT) * ramp
	state.char:SetAttribute("HavokBeamIntensity", ramp)

	local _hitDistance = AbilityCombatHelper.spherecastHit(origin, state.aimDir, BEAM.RANGE, BEAM.HIT_RADIUS, state.char, {
		damage = math.max(1, math.floor(BEAM.DAMAGE_PER_TICK * damageMult + 0.5)),
		pushSpeed = BEAM.PUSH_SPEED * (0.65 + ramp * 0.35),
		pushUp = BEAM.PUSH_UP,
		excludePlayer = plr,
	})
end

local function startBeam(plr: Player, dirX: number, dirY: number, dirZ: number)
	if beamByPlayer[plr] or surgeByPlayer[plr] then
		return
	end
	local char = plr.Character
	if not char then
		return
	end
	if not ResourceService.hasMinimum(char, CHAR_ID, BEAM.ABILITY_ID) then
		return
	end
	if char:GetAttribute("IsKineticSurgeActive") == true then
		return
	end
	if AbilityCooldownHelper.isOnCooldown(char, BEAM.ABILITY_ID) then
		return
	end

	local aimDir = normalizeDir(dirX, dirY, dirZ)
	char:SetAttribute("IsConcussiveBeamActive", true)
	char:SetAttribute("HavokBeamIntensity", 0)
	setBeamAimAttribute(char, aimDir)
	beamByPlayer[plr] = {
		caster = plr,
		char = char,
		aimDir = aimDir,
		lastTick = 0,
		holdTime = 0,
	}
end

local function updateBeamAim(plr: Player, dirX: number, dirY: number, dirZ: number)
	local state = beamByPlayer[plr]
	if state then
		local newDir = normalizeDir(dirX, dirY, dirZ)
		state.aimDir = state.aimDir:Lerp(newDir, 0.35)
		if state.char.Parent then
			setBeamAimAttribute(state.char, state.aimDir)
		end
	end
end

local function onSiphon(plr: Player)
	if not isHavok(plr) then
		return
	end
	local char = plr.Character
	if not char or surgeByPlayer[plr] or beamByPlayer[plr] then
		return
	end
	if AbilityCooldownHelper.isOnCooldown(char, SIPHON.ABILITY_ID) then
		return
	end
	local charge = getCharge(char)
	if charge >= SIPHON.MAX_CHARGE then
		return
	end

	setCharge(char, charge + 1)
	AbilityCooldownHelper.apply(char, SIPHON.ABILITY_ID, SIPHON.COOLDOWN_SEC)
	ProgressionService.grantAbilityXp(plr, SIPHON.ABILITY_ID, "cast")
end

local function getBurstOrigin(char: Model): Vector3
	local chest = getChestPart(char)
	if chest then
		return chest.Position
	end
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	return if root then root.Position else char:GetPivot().Position
end

local function onBurst(plr: Player)
	if not isHavok(plr) then
		return
	end
	local char = plr.Character
	if not char or beamByPlayer[plr] or surgeByPlayer[plr] then
		return
	end
	if AbilityCooldownHelper.isOnCooldown(char, BURST.ABILITY_ID) then
		return
	end

	local charge = getCharge(char)
	if charge < BURST.MIN_CHARGE then
		return
	end

	local config = ResourceService.getConfig(CHAR_ID)
	if not config or not ResourceService.hasMinimum(char, CHAR_ID, BURST.ABILITY_ID) then
		return
	end
	if not ResourceService.trySpend(char, config.instant.EnergyBurst or 4) then
		return
	end

	local tier = BURST.TIERS[charge]
	if not tier then
		tier = BURST.TIERS[#BURST.TIERS]
	end
	setCharge(char, 0)

	local pos = getBurstOrigin(char)
	AbilityVfxHelper.spawnGroundRing(pos, BLUE, tier.radius * 0.12, tier.radius * 1.05, BURST.VFX_DURATION)
	AbilityVfxHelper.spawnExpandingSphere(pos, BLUE_SOFT, tier.radius * 0.2, tier.radius * 0.9, BURST.VFX_DURATION * 0.9)
	AbilityVfxHelper.spawnExpandingSphere(pos, BLUE, tier.radius * 0.35, tier.radius * 1.15, BURST.VFX_DURATION)
	AbilityCombatHelper.hitInRadius(pos, tier.radius, char, {
		damage = tier.damage,
		pushSpeed = tier.pushSpeed,
		pushUp = tier.pushUp,
		excludePlayer = plr,
	})

	AbilityCooldownHelper.apply(char, BURST.ABILITY_ID, BURST.COOLDOWN_SEC)
	ProgressionService.grantAbilityXp(plr, BURST.ABILITY_ID, "fire")
end

local function onSurge(plr: Player, dirX: number, dirY: number, dirZ: number)
	if not isHavok(plr) then
		return
	end
	local char = plr.Character
	if not char or beamByPlayer[plr] or surgeByPlayer[plr] then
		return
	end
	if AbilityCooldownHelper.isOnCooldown(char, SURGE.ABILITY_ID) then
		return
	end

	local config = ResourceService.getConfig(CHAR_ID)
	if not config or not ResourceService.hasMinimum(char, CHAR_ID, SURGE.ABILITY_ID) then
		return
	end
	if not ResourceService.trySpend(char, config.instant.KineticSurge or 5) then
		return
	end

	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not root or not hum then
		return
	end

	endBeam(plr)
	local dir = normalizeDir(dirX, dirY, dirZ)
	local savedAutoRotate = hum.AutoRotate
	hum.AutoRotate = false
	hum:ChangeState(Enum.HumanoidStateType.Freefall)
	PushHelper.applyToModel(char, dir, {
		speed = SURGE.BOOST_SPEED,
		impulseMult = 1.35,
	})

	local linearVel = createSurgeVelocity(root, dir)
	char:SetAttribute("IsKineticSurgeActive", true)
	surgeByPlayer[plr] = {
		caster = plr,
		root = root,
		humanoid = hum,
		elapsed = 0,
		duration = SURGE.ACTIVE_DURATION,
		linearVel = linearVel,
		savedAutoRotate = savedAutoRotate,
		surgeDir = dir,
	}

	AbilityCooldownHelper.apply(char, SURGE.ABILITY_ID, SURGE.COOLDOWN_SEC)
	ProgressionService.grantAbilityXp(plr, SURGE.ABILITY_ID, "cast")
end

local function onBlastStart(plr: Player, dirX: number, dirY: number, dirZ: number)
	if not isHavok(plr) then
		return
	end
	local char = plr.Character
	if not char or surgeByPlayer[plr] or beamByPlayer[plr] then
		return
	end
	if AbilityCooldownHelper.isOnCooldown(char, BLAST.ABILITY_ID) then
		return
	end

	local config = ResourceService.getConfig(CHAR_ID)
	if not config or not ResourceService.hasMinimum(char, CHAR_ID, BLAST.ABILITY_ID) then
		return
	end
	if not ResourceService.trySpend(char, config.instant.EnergyBlast or 2) then
		return
	end

	SteerableBoltService.handleStart(plr, BLAST.ABILITY_ID, dirX, dirY, dirZ, blastBoltConfig, nil, spawnHavokBlastVisual)
	ProgressionService.grantAbilityXp(plr, BLAST.ABILITY_ID, "fire")
end

local function onBlastRelease(plr: Player)
	SteerableBoltService.handleRelease(plr, BLAST.ABILITY_ID)
	local char = plr.Character
	if char and char.Parent then
		AbilityCooldownHelper.apply(char, BLAST.ABILITY_ID, BLAST.COOLDOWN_SEC)
	end
end

function HavokAbilitiesService.update(dt: number)
	local now = tick()

	for plr, state in beamByPlayer do
		local char = state.char
		if not char.Parent or not isHavok(plr) then
			endBeam(plr)
			continue
		end
		if not ResourceService.hasMinimum(char, CHAR_ID, BEAM.ABILITY_ID) then
			endBeam(plr)
			continue
		end
		state.holdTime += dt
		tickBeam(plr, state, now)
	end

	for plr, state in surgeByPlayer do
		if not state.root.Parent then
			HavokAbilitiesService.forceEndSurge(plr)
			continue
		end
		state.elapsed += dt
		if state.linearVel.Parent then
			state.linearVel.VectorVelocity = state.surgeDir * SURGE.BOOST_SPEED
		end
		if state.elapsed >= state.duration then
			HavokAbilitiesService.forceEndSurge(plr)
		end
	end
end

function HavokAbilitiesService.onPlayerRemoving(plr: Player)
	beamByPlayer[plr] = nil
	HavokAbilitiesService.forceEndSurge(plr)
end

function HavokAbilitiesService.setup(
	siphon: RemoteEvent,
	burst: RemoteEvent,
	beamStart: RemoteEvent,
	beamAim: RemoteEvent,
	beamEnd: RemoteEvent,
	surge: RemoteEvent,
	blastStart: RemoteEvent,
	blastAim: RemoteEvent,
	blastRelease: RemoteEvent
)
	siphon.OnServerEvent:Connect(function(plr: Player)
		onSiphon(plr)
	end)

	burst.OnServerEvent:Connect(function(plr: Player)
		onBurst(plr)
	end)

	beamStart.OnServerEvent:Connect(function(plr: Player, x: number, y: number, z: number)
		if typeof(x) == "number" and typeof(y) == "number" and typeof(z) == "number" then
			startBeam(plr, x, y, z)
		end
	end)

	beamAim.OnServerEvent:Connect(function(plr: Player, x: number, y: number, z: number)
		if typeof(x) == "number" and typeof(y) == "number" and typeof(z) == "number" then
			updateBeamAim(plr, x, y, z)
		end
	end)

	beamEnd.OnServerEvent:Connect(function(plr: Player)
		endBeam(plr)
	end)

	surge.OnServerEvent:Connect(function(plr: Player, x: number, y: number, z: number)
		if typeof(x) == "number" and typeof(y) == "number" and typeof(z) == "number" then
			onSurge(plr, x, y, z)
		end
	end)

	blastStart.OnServerEvent:Connect(function(plr: Player, x: number, y: number, z: number)
		if typeof(x) == "number" and typeof(y) == "number" and typeof(z) == "number" then
			onBlastStart(plr, x, y, z)
		end
	end)

	blastAim.OnServerEvent:Connect(function(plr: Player, x: number, y: number, z: number)
		if not isHavok(plr) then
			return
		end
		if typeof(x) == "number" and typeof(y) == "number" and typeof(z) == "number" then
			SteerableBoltService.handleAim(plr, BLAST.ABILITY_ID, x, y, z)
		end
	end)

	blastRelease.OnServerEvent:Connect(function(plr: Player)
		if not isHavok(plr) then
			return
		end
		onBlastRelease(plr)
	end)
end

return HavokAbilitiesService
