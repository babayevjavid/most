--!strict
--[[ Sunspot: Solar Flight, Sun Uppercut, Solar Flare + solar strength updates. ]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AbilityCombatHelper = require(Shared:WaitForChild("AbilityCombatHelper"))
local AbilityCooldownHelper = require(Shared:WaitForChild("AbilityCooldownHelper"))
local AbilityVfxHelper = require(Shared:WaitForChild("AbilityVfxHelper"))
local SunspotConstants = require(Shared:WaitForChild("SunspotConstants"))
local SunspotSolarHelper = require(Shared:WaitForChild("SunspotSolarHelper"))
local ParticleHelper = require(Shared:WaitForChild("ParticleHelper"))
local ResourceService = require(script.Parent:WaitForChild("ResourceService"))
local SteerableBoltService = require(script.Parent:WaitForChild("SteerableBoltService"))
local ProgressionService = require(script.Parent:WaitForChild("ProgressionService"))

local FLIGHT = SunspotConstants.SolarFlight
local UPPERCUT = SunspotConstants.SunUppercut
local FLARE = SunspotConstants.SolarFlare
local PHOTO = SunspotConstants.Photosynthesis
local BLACK_SUN = SunspotConstants.BlackSun
local CHARGE = SunspotConstants.SolarCharge
local FIRE = SunspotConstants.SOLAR_FIRE
local NEAR_ZERO = Vector3.new(0.001, 0.001, 0.001)
local CHAR_ID = "Sunspot"

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

local flightByPlayer: { [Player]: FlightState } = {}
local strengthByCharacter: { [Model]: number } = {}
local photosynthesisByPlayer: { [Player]: { char: Model, regenTimer: number } } = {}
local blackSunChargeByPlayer: { [Player]: {
	char: Model,
	root: BasePart,
	orb: BasePart,
	chargeAlpha: number,
} } = {}
local blackSunProjectileByPlayer: { [Player]: {
	orb: BasePart,
	caster: Model,
	casterPlr: Player,
	chargeAlpha: number,
	velocity: Vector3,
	detonated: boolean,
} } = {}

local function flareBoltConfig(strength: number): SteerableBoltService.BoltConfig
	local scale = 0.45 + strength * 0.55
	return {
		abilityId = FLARE.ABILITY_ID,
		boltName = "SolarFlareBolt",
		size = FLARE.SIZE,
		color = FIRE,
		speed = FLARE.SPEED,
		maxRange = FLARE.RANGE,
		lifetime = FLARE.LIFETIME,
		damage = math.floor(FLARE.BASE_DAMAGE * scale + 0.5),
		pushSpeed = FLARE.PUSH_SPEED,
		pushUp = FLARE.PUSH_UP,
		curveStrength = FLARE.CURVE_STRENGTH,
		impactRadius = FLARE.IMPACT_RADIUS,
		impactDuration = FLARE.IMPACT_DURATION,
	}
end

local function spawnSolarFlareVisual(spawnCF: CFrame, _config: SteerableBoltService.BoltConfig): BasePart
	return AbilityVfxHelper.spawnSolarFlareBolt(
		spawnCF,
		FLARE.RING_OUTER_RADIUS,
		FLARE.RING_THICKNESS,
		SunspotConstants.SOLAR_GOLD
	)
end

local function trySpendAbility(char: Model, abilityId: string): boolean
	return ResourceService.trySpendForAbility(char, CHAR_ID, abilityId)
end

local function setStrength(char: Model, value: number)
	local clamped = math.clamp(value, 0, 1)
	strengthByCharacter[char] = clamped
	char:SetAttribute("SunspotStrength", clamped)
end

local function blackSunChargeYOffset(diameter: number): number
	return diameter * 0.5 + BLACK_SUN.CHARGE_BODY_CLEARANCE
end

local function blackSunChargeCFrame(root: BasePart, diameter: number): CFrame
	local yOffset = blackSunChargeYOffset(diameter)
	return root.CFrame * CFrame.new(0, yOffset, 0)
end

local function diameterFromAlpha(alpha: number): number
	return BLACK_SUN.MIN_DIAMETER + (BLACK_SUN.MAX_DIAMETER - BLACK_SUN.MIN_DIAMETER) * math.clamp(alpha, 0, 1)
end

local function blastStatsFromAlpha(alpha: number): (number, number, number)
	local a = math.clamp(alpha, 0, 1)
	local damage = BLACK_SUN.BASE_DAMAGE + (BLACK_SUN.MAX_DAMAGE - BLACK_SUN.BASE_DAMAGE) * a
	local push = BLACK_SUN.BASE_PUSH_SPEED + (BLACK_SUN.MAX_PUSH_SPEED - BLACK_SUN.BASE_PUSH_SPEED) * a
	local radius = diameterFromAlpha(a) * 0.5 * BLACK_SUN.BLAST_RADIUS_SCALE
	return damage, push, radius
end

local SunspotAbilitiesService = {}

local function isSunspot(plr: Player): boolean
	return plr:GetAttribute("SelectedCharacter") == CHAR_ID
end

local function getStrength(char: Model): number
	local value = char:GetAttribute("SunspotStrength")
	if typeof(value) == "number" then
		return math.clamp(value, 0, 1)
	end
	return 0
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

local function endFlight(plr: Player, applyCooldown: boolean)
	local state = flightByPlayer[plr]
	if not state then
		return
	end
	flightByPlayer[plr] = nil
	local char = state.caster
	if char and char.Parent then
		char:SetAttribute("IsSolarFlying", nil)
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
	if char:GetAttribute("IsSolarFlareActive") == true then
		return
	end
	if char:GetAttribute("IsPhotosynthesisActive") == true or char:GetAttribute("IsBlackSunCharging") == true then
		return
	end
	if AbilityCooldownHelper.isOnCooldown(char, FLIGHT.ABILITY_ID) then
		return
	end
	if not ResourceService.hasMinimum(char, CHAR_ID, FLIGHT.ABILITY_ID) then
		return
	end

	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root then
		return
	end

	local att = root:FindFirstChildOfClass("Attachment") or Instance.new("Attachment")
	att.Name = "SolarFlightAttachment"
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
	char:SetAttribute("IsSolarFlying", true)
	char:SetAttribute("FlightInputActive", false)
	char:SetAttribute("FlightAlphaSpeed", 0)
end

local function findUppercutTarget(
	caster: Model,
	plr: Player,
	aimDir: Vector3
): (Model?, Humanoid?, BasePart?)
	local root = caster:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil
	end
	local flatAim = Vector3.new(aimDir.X, 0, aimDir.Z)
	if flatAim.Magnitude < 0.01 then
		flatAim = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	end
	if flatAim.Magnitude < 0.01 then
		return nil
	end
	flatAim = flatAim.Unit

	local origin = root.Position + Vector3.new(0, 1.1, 0)
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { caster }
	params.FilterType = Enum.RaycastFilterType.Exclude

	local result = workspace:Spherecast(origin, UPPERCUT.HIT_RADIUS, flatAim * UPPERCUT.RANGE, params)
	if result and result.Instance:IsA("BasePart") then
		local model = (result.Instance :: BasePart):FindFirstAncestorOfClass("Model")
		if model and model ~= caster then
			local hum = model:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				local targetPlr = Players:GetPlayerFromCharacter(model)
				if targetPlr ~= plr then
					return model, hum, result.Instance :: BasePart
				end
			end
		end
	end

	local bestModel: Model? = nil
	local bestHum: Humanoid? = nil
	local bestPart: BasePart? = nil
	local bestDist = UPPERCUT.RANGE + 1

	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { caster }

	for _, part in workspace:GetPartBoundsInRadius(origin, UPPERCUT.RANGE + 1, overlap) do
		if not part:IsA("BasePart") then
			continue
		end
		local model = part:FindFirstAncestorOfClass("Model")
		if not model or model == caster then
			continue
		end
		local hum = model:FindFirstChildOfClass("Humanoid")
		local targetRoot = model:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hum or hum.Health <= 0 or not targetRoot then
			continue
		end
		local targetPlr = Players:GetPlayerFromCharacter(model)
		if targetPlr == plr then
			continue
		end
		local offset = targetRoot.Position - origin
		local dist = offset.Magnitude
		if dist > UPPERCUT.RANGE then
			continue
		end
		if offset.Unit:Dot(flatAim) < 0.45 then
			continue
		end
		if dist < bestDist then
			bestDist = dist
			bestModel = model
			bestHum = hum
			bestPart = targetRoot
		end
	end

	return bestModel, bestHum, bestPart
end

local function beginUppercutEmpower(char: Model)
	char:SetAttribute("SunUppercutEmpowerUntil", tick() + UPPERCUT.EMPOWER_DURATION)
	task.delay(UPPERCUT.EMPOWER_DURATION, function()
		if char.Parent and char:GetAttribute("SunUppercutEmpowerUntil") then
			local untilTime = char:GetAttribute("SunUppercutEmpowerUntil")
			if typeof(untilTime) == "number" and tick() >= untilTime - 0.05 then
				char:SetAttribute("SunUppercutEmpowerUntil", nil)
			end
		end
	end)
end

local function onSunUppercut(plr: Player, dirX: number?, dirY: number?, dirZ: number?)
	if not isSunspot(plr) then
		return
	end
	local char = plr.Character
	if not char or char:GetAttribute("IsSolarFlying") == true or char:GetAttribute("IsSolarFlareActive") == true then
		return
	end
	if char:GetAttribute("IsPhotosynthesisActive") == true or char:GetAttribute("IsBlackSunCharging") == true then
		return
	end
	if AbilityCooldownHelper.isOnCooldown(char, UPPERCUT.ABILITY_ID) then
		return
	end

	local config = ResourceService.getConfig(CHAR_ID)
	if not config or not ResourceService.hasMinimum(char, CHAR_ID, UPPERCUT.ABILITY_ID) then
		return
	end
	if not trySpendAbility(char, UPPERCUT.ABILITY_ID) then
		return
	end

	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	beginUppercutEmpower(char)

	local aim = root.CFrame.LookVector
	if typeof(dirX) == "number" and typeof(dirY) == "number" and typeof(dirZ) == "number" then
		local candidate = Vector3.new(dirX, dirY, dirZ)
		if candidate.Magnitude > 0.01 then
			aim = candidate.Unit
		end
	end

	local targetModel, targetHum, targetPart = findUppercutTarget(char, plr, aim)
		if targetModel and targetHum and targetPart then
		local strength = getStrength(char)
		local scale = 0.4 + strength * 0.6
		local pushDir = Vector3.new(aim.X * 0.12, 1, aim.Z * 0.12)
		if pushDir.Magnitude < 0.01 then
			pushDir = Vector3.new(0, 1, 0)
		else
			pushDir = pushDir.Unit
		end

		AbilityCombatHelper.damageAndPush(targetModel, targetHum, targetPart, pushDir, {
			damage = math.floor(UPPERCUT.BASE_DAMAGE * scale + 0.5),
			pushSpeed = UPPERCUT.PUSH_SPEED * scale,
			pushUp = UPPERCUT.PUSH_UP * scale,
			impulseMult = UPPERCUT.IMPULSE_MULT,
		})
		AbilityCombatHelper.applyRagdoll(targetModel, 0.85)
	end

	AbilityCooldownHelper.apply(char, UPPERCUT.ABILITY_ID, UPPERCUT.COOLDOWN_SEC)
	ProgressionService.grantAbilityXp(plr, UPPERCUT.ABILITY_ID, "cast")
end

local function onFlareStart(plr: Player, dirX: number, dirY: number, dirZ: number)
	if not isSunspot(plr) then
		return
	end
	local char = plr.Character
	if not char then
		return
	end
	if char:GetAttribute("IsPhotosynthesisActive") == true or char:GetAttribute("IsBlackSunCharging") == true then
		return
	end
	if AbilityCooldownHelper.isOnCooldown(char, FLARE.ABILITY_ID) then
		return
	end

	local config = ResourceService.getConfig(CHAR_ID)
	if not config or not ResourceService.hasMinimum(char, CHAR_ID, FLARE.ABILITY_ID) then
		return
	end
	if not trySpendAbility(char, FLARE.ABILITY_ID) then
		return
	end

	local strength = getStrength(char)
	SteerableBoltService.handleStart(
		plr,
		FLARE.ABILITY_ID,
		dirX,
		dirY,
		dirZ,
		flareBoltConfig(strength),
		nil,
		spawnSolarFlareVisual
	)
	ProgressionService.grantAbilityXp(plr, FLARE.ABILITY_ID, "fire")
end

local function onFlareRelease(plr: Player)
	SteerableBoltService.handleRelease(plr, FLARE.ABILITY_ID)
	local char = plr.Character
	if char and char.Parent then
		AbilityCooldownHelper.apply(char, FLARE.ABILITY_ID, FLARE.COOLDOWN_SEC)
	end
end

local function endPhotosynthesis(plr: Player, applyCooldown: boolean)
	local state = photosynthesisByPlayer[plr]
	photosynthesisByPlayer[plr] = nil
	local char = if state then state.char else nil
	if char and char.Parent then
		char:SetAttribute("IsPhotosynthesisActive", nil)
		if applyCooldown then
			AbilityCooldownHelper.apply(char, PHOTO.ABILITY_ID, PHOTO.COOLDOWN_SEC)
		end
	end
end

local function startPhotosynthesis(plr: Player)
	if not isSunspot(plr) then
		return
	end
	local char = plr.Character
	if not char or photosynthesisByPlayer[plr] then
		return
	end
	if char:GetAttribute("IsSolarFlying") == true
		or char:GetAttribute("IsSolarFlareActive") == true
		or char:GetAttribute("IsBlackSunCharging") == true
	then
		return
	end
	if AbilityCooldownHelper.isOnCooldown(char, PHOTO.ABILITY_ID) then
		return
	end
	if not SunspotSolarHelper.canStartPhotosynthesis(char) then
		return
	end

	photosynthesisByPlayer[plr] = {
		char = char,
		regenTimer = 0,
	}
	char:SetAttribute("IsPhotosynthesisActive", true)
end

local function fadeDestroyBlackSunOrb(orb: BasePart)
	if not orb.Parent then
		return
	end
	AbilityVfxHelper.fadeOutBlackSunOrb(orb, BLACK_SUN.ORB_FADE_DURATION)
end

local function fadeDestroyPart(part: BasePart)
	if not part.Parent then
		return
	end
	ParticleHelper.disableDescendantsAndScheduleDestroy(part)
	task.delay(5, function()
		if part.Parent then
			part:Destroy()
		end
	end)
end

local function cancelBlackSunCharge(plr: Player, applyCooldown: boolean)
	local state = blackSunChargeByPlayer[plr]
	blackSunChargeByPlayer[plr] = nil
	if not state then
		return
	end
	if state.orb and state.orb.Parent then
		fadeDestroyBlackSunOrb(state.orb)
	end
	if state.char and state.char.Parent then
		state.char:SetAttribute("IsBlackSunCharging", nil)
		state.char:SetAttribute("BlackSunCharge", nil)
		if applyCooldown then
			AbilityCooldownHelper.apply(state.char, BLACK_SUN.ABILITY_ID, BLACK_SUN.COOLDOWN_SEC)
		end
	end
end

local function detonateBlackSun(plr: Player, position: Vector3, chargeAlpha: number)
	local proj = blackSunProjectileByPlayer[plr]
	if proj and proj.detonated then
		return
	end
	if proj then
		proj.detonated = true
	end
	local char = plr.Character
	if not char then
		return
	end
	local damage, pushSpeed, radius = blastStatsFromAlpha(chargeAlpha)
	AbilityCombatHelper.hitInRadius(position, radius, char, {
		damage = math.floor(damage + 0.5),
		pushSpeed = pushSpeed,
		pushUp = BLACK_SUN.PUSH_UP,
		excludePlayer = plr,
	})
	AbilityVfxHelper.spawnBlackSunDetonation(position, radius, BLACK_SUN.IMPACT_VFX_DURATION)
	setStrength(char, math.max(0, getStrength(char) - chargeAlpha * 0.55))
	AbilityCooldownHelper.apply(char, BLACK_SUN.ABILITY_ID, BLACK_SUN.COOLDOWN_SEC)
	ProgressionService.grantAbilityXp(plr, BLACK_SUN.ABILITY_ID, "cast")
end

local function endBlackSunProjectile(plr: Player)
	blackSunProjectileByPlayer[plr] = nil
end

local function launchBlackSun(plr: Player, targetX: number, targetY: number, targetZ: number)
	local chargeState = blackSunChargeByPlayer[plr]
	if not chargeState then
		return
	end
	local char = chargeState.char
	if not char or not char.Parent or not chargeState.orb.Parent then
		cancelBlackSunCharge(plr, false)
		return
	end

	local config = ResourceService.getConfig(CHAR_ID)
	if not config or not ResourceService.hasMinimum(char, CHAR_ID, BLACK_SUN.ABILITY_ID) then
		cancelBlackSunCharge(plr, false)
		return
	end
	if not trySpendAbility(char, BLACK_SUN.ABILITY_ID) then
		cancelBlackSunCharge(plr, false)
		return
	end

	local chargeAlpha = chargeState.chargeAlpha
	local orb = chargeState.orb
	blackSunChargeByPlayer[plr] = nil
	char:SetAttribute("IsBlackSunCharging", nil)
	char:SetAttribute("BlackSunCharge", nil)

	local target = Vector3.new(targetX, targetY, targetZ)
	local dir = target - orb.Position
	if dir.Magnitude < 1 then
		dir = char:GetPivot().LookVector
	else
		dir = dir.Unit
	end

	orb.Parent = workspace
	orb.Anchored = true
	orb.CanTouch = false
	local vel = dir * BLACK_SUN.THROW_SPEED

	blackSunProjectileByPlayer[plr] = {
		orb = orb,
		caster = char,
		casterPlr = plr,
		chargeAlpha = chargeAlpha,
		velocity = vel,
		detonated = false,
	}

	Debris:AddItem(orb, 6)
	task.delay(6, function()
		if blackSunProjectileByPlayer[plr] and blackSunProjectileByPlayer[plr].orb == orb then
			local pos = if orb.Parent then orb.Position else target
			if orb.Parent then
				orb.Anchored = true
				orb.CFrame = CFrame.new(pos)
				fadeDestroyBlackSunOrb(orb)
			end
			endBlackSunProjectile(plr)
			detonateBlackSun(plr, pos, chargeAlpha)
		end
	end)
end

local function startBlackSunCharge(plr: Player)
	if not isSunspot(plr) then
		return
	end
	local char = plr.Character
	if not char or blackSunChargeByPlayer[plr] or blackSunProjectileByPlayer[plr] then
		return
	end
	if char:GetAttribute("IsSolarFlying") == true
		or char:GetAttribute("IsSolarFlareActive") == true
		or char:GetAttribute("IsPhotosynthesisActive") == true
	then
		return
	end
	if AbilityCooldownHelper.isOnCooldown(char, BLACK_SUN.ABILITY_ID) then
		return
	end
	if not SunspotSolarHelper.canStartBlackSun(char) then
		return
	end
	if not ResourceService.hasMinimum(char, CHAR_ID, BLACK_SUN.ABILITY_ID) then
		return
	end

	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	local spawnPos = blackSunChargeCFrame(root, BLACK_SUN.MIN_DIAMETER).Position
	local orb = AbilityVfxHelper.spawnBlackSunOrb(CFrame.new(spawnPos), BLACK_SUN.MIN_DIAMETER)
	orb.Parent = char
	blackSunChargeByPlayer[plr] = {
		char = char,
		root = root,
		orb = orb,
		chargeAlpha = 0,
	}
	char:SetAttribute("IsBlackSunCharging", true)
	char:SetAttribute("BlackSunCharge", 0)
end

function SunspotAbilitiesService.forceEndPhotosynthesis(plr: Player)
	endPhotosynthesis(plr, false)
end

function SunspotAbilitiesService.forceEndBlackSun(plr: Player)
	cancelBlackSunCharge(plr, false)
	local proj = blackSunProjectileByPlayer[plr]
	if proj and proj.orb.Parent then
		fadeDestroyBlackSunOrb(proj.orb)
	end
	endBlackSunProjectile(plr)
end

function SunspotAbilitiesService.initCharacter(char: Model)
	char:SetAttribute("SunspotStrength", 0)
	char:SetAttribute("IsSolarFlying", nil)
	char:SetAttribute("IsSolarFlareActive", nil)
	char:SetAttribute("IsPhotosynthesisActive", nil)
	char:SetAttribute("IsBlackSunCharging", nil)
	char:SetAttribute("BlackSunCharge", nil)
	strengthByCharacter[char] = 0
end

function SunspotAbilitiesService.forceEndFlight(plr: Player)
	endFlight(plr, false)
end

function SunspotAbilitiesService.setup(
	flightToggle: RemoteEvent,
	flightInput: RemoteEvent,
	sunUppercut: RemoteEvent,
	flareStart: RemoteEvent,
	flareAim: RemoteEvent,
	flareRelease: RemoteEvent,
	photosynthesis: RemoteEvent,
	blackSunCharge: RemoteEvent,
	blackSunThrow: RemoteEvent
)
	flightToggle.OnServerEvent:Connect(function(plr: Player, enable: boolean)
		if not isSunspot(plr) then
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

	sunUppercut.OnServerEvent:Connect(function(plr: Player, dirX: number?, dirY: number?, dirZ: number?)
		if typeof(dirX) == "number" and typeof(dirY) == "number" and typeof(dirZ) == "number" then
			onSunUppercut(plr, dirX, dirY, dirZ)
		else
			onSunUppercut(plr)
		end
	end)

	flareStart.OnServerEvent:Connect(function(plr: Player, dirX: number, dirY: number, dirZ: number)
		onFlareStart(plr, dirX, dirY, dirZ)
	end)

	flareAim.OnServerEvent:Connect(function(plr, dirX, dirY, dirZ)
		SteerableBoltService.handleAim(plr, FLARE.ABILITY_ID, dirX, dirY, dirZ)
	end)

	flareRelease.OnServerEvent:Connect(function(plr: Player)
		if not isSunspot(plr) then
			return
		end
		onFlareRelease(plr)
	end)

	photosynthesis.OnServerEvent:Connect(function(plr: Player, active: boolean)
		if not isSunspot(plr) then
			return
		end
		if active == true then
			startPhotosynthesis(plr)
		else
			endPhotosynthesis(plr, true)
		end
	end)

	blackSunCharge.OnServerEvent:Connect(function(plr: Player, active: boolean)
		if not isSunspot(plr) then
			return
		end
		if active == true then
			startBlackSunCharge(plr)
		else
			cancelBlackSunCharge(plr, false)
		end
	end)

	blackSunThrow.OnServerEvent:Connect(function(plr: Player, x: number, y: number, z: number)
		if not isSunspot(plr) then
			return
		end
		if typeof(x) == "number" and typeof(y) == "number" and typeof(z) == "number" then
			launchBlackSun(plr, x, y, z)
		end
	end)
end

function SunspotAbilitiesService.update(dt: number)
	local dtClamped = math.clamp(dt, 0.001, 0.1)
	local velLerpMove = 1 - (1 - FLIGHT.VEL_LERP_MOVE) ^ (dtClamped * 60)
	local velLerpDecay = 1 - (1 - FLIGHT.VEL_LERP_DECAY) ^ (dtClamped * 60)
	local strengthAlpha = 1 - math.exp(-dtClamped / CHARGE.STRENGTH_SMOOTH_TAU)

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

	for plr, state in photosynthesisByPlayer do
		local char = state.char
		if not char.Parent or not isSunspot(plr) then
			endPhotosynthesis(plr, false)
			continue
		end
		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			endPhotosynthesis(plr, false)
			continue
		end
		if root.AssemblyLinearVelocity.Magnitude > PHOTO.MAX_MOVE_SPEED then
			endPhotosynthesis(plr, true)
			continue
		end

		local liveSun = SunspotSolarHelper.computeTargetStrength(char)
		local inSun = SunspotSolarHelper.isInDirectSunlight(char)
		local interval = if inSun
			then PHOTO.REGEN_INTERVAL_SUN / math.clamp(liveSun, 0.35, 1)
			else PHOTO.REGEN_INTERVAL_SHADE

		state.regenTimer += dtClamped
		while state.regenTimer >= interval do
			state.regenTimer -= interval
			local currentEnergy, maxEnergy = ResourceService.getEnergy(char)
			if not inSun then
				if currentEnergy < PHOTO.ENERGY_COST_PER_TICK_SHADE then
					char:SetAttribute("Energy", 0)
					endPhotosynthesis(plr, true)
					break
				end
				currentEnergy -= PHOTO.ENERGY_COST_PER_TICK_SHADE
			end
			char:SetAttribute("Energy", math.min(maxEnergy, currentEnergy + PHOTO.ENERGY_PER_TICK))

			local humanoid = char:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				local healAmount = if inSun then PHOTO.HEAL_PER_TICK_SUN else PHOTO.HEAL_PER_TICK_SHADE
				humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + healAmount)
			end
		end

		if not photosynthesisByPlayer[plr] then
			continue
		end

		if inSun then
			local stored = strengthByCharacter[char] or 0
			setStrength(char, math.min(1, stored + PHOTO.SOLAR_BOOST_PER_SEC * liveSun * dtClamped))
		end
	end

	for plr, state in blackSunChargeByPlayer do
		if not state.char.Parent or not state.root.Parent or not state.orb.Parent then
			cancelBlackSunCharge(plr, false)
			continue
		end
		state.chargeAlpha = math.min(1, state.chargeAlpha + BLACK_SUN.CHARGE_RATE * dtClamped)
		local diameter = diameterFromAlpha(state.chargeAlpha)
		state.orb.CFrame = blackSunChargeCFrame(state.root, diameter)
		AbilityVfxHelper.setBlackSunOrbDiameter(state.orb, diameter)
		state.char:SetAttribute("BlackSunCharge", state.chargeAlpha)
	end

	for plr, proj in blackSunProjectileByPlayer do
		if not proj.orb.Parent then
			endBlackSunProjectile(plr)
			continue
		end
		local delta = proj.velocity * dtClamped
		if delta.Magnitude < 0.001 then
			continue
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { proj.caster, proj.orb }
		local startPos = proj.orb.Position
		local hit = workspace:Raycast(startPos, delta * 1.05, params)
		if hit then
			local pos = hit.Position
			proj.velocity = Vector3.zero
			if proj.orb.Parent then
				proj.orb.Anchored = true
				proj.orb.CFrame = CFrame.new(pos)
				fadeDestroyBlackSunOrb(proj.orb)
			end
			endBlackSunProjectile(plr)
			detonateBlackSun(plr, pos, proj.chargeAlpha)
		else
			proj.orb.CFrame = CFrame.new(startPos + delta)
		end
	end

	for _, plr in Players:GetPlayers() do
		if plr:GetAttribute("SelectedCharacter") ~= CHAR_ID then
			continue
		end
		local char = plr.Character
		if not char or not char.Parent then
			continue
		end
		local target = SunspotSolarHelper.computeTargetStrength(char)
		local current = strengthByCharacter[char] or SunspotSolarHelper.getStoredStrength(char)
		if target > current then
			local nextStrength = current + (target - current) * strengthAlpha
			setStrength(char, nextStrength)
		elseif target < current then
			local nextStrength = current + (target - current) * strengthAlpha
			setStrength(char, nextStrength)
		end
	end
end

function SunspotAbilitiesService.onPlayerRemoving(plr: Player)
	endFlight(plr, false)
	endPhotosynthesis(plr, false)
	SunspotAbilitiesService.forceEndBlackSun(plr)
	local char = plr.Character
	if char then
		strengthByCharacter[char] = nil
	end
end

return SunspotAbilitiesService
