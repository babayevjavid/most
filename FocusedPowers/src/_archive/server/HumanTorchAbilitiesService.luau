--!strict
--[[ Human Torch abilities server ]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AbilityCombatHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityCombatHelper"))
local AbilityCooldownHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityCooldownHelper"))
local AbilityVfxHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityVfxHelper"))
local HumanTorchConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("HumanTorchConstants"))
local InteractableHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("InteractableHelper"))
local PushHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PushHelper"))
local SmoothMotionHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SmoothMotionHelper"))
local TelekineticFlightConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TelekineticFlightConstants"))

local ResourceService = require(script.Parent:WaitForChild("ResourceService"))
local SteerableBoltService = require(script.Parent:WaitForChild("SteerableBoltService"))

local CHAR_ID = "HumanTorch"
local C = HumanTorchConstants
local COLOR = C.COLOR
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

local HumanTorchAbilitiesService = {}

local function isTorch(plr: Player): boolean
	return plr:GetAttribute("SelectedCharacter") == CHAR_ID
end

local function normalizeLook(x: number, y: number, z: number, fallback: Vector3): Vector3
	local v = Vector3.new(x, y, z)
	if v.Magnitude < 0.01 then
		return fallback
	end
	return v.Unit
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

local function endFlight(plr: Player, applyCd: boolean)
	local state = flightByPlayer[plr]
	if not state then
		return
	end
	flightByPlayer[plr] = nil
	local char = state.caster
	if char and char.Parent then
		char:SetAttribute("IsFlameFlying", nil)
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
	if applyCd and char and char.Parent then
		AbilityCooldownHelper.apply(char, C.FlameFlight.ABILITY_ID, C.FlameFlight.COOLDOWN_SEC)
	end
end

local function startFlight(plr: Player)
	local char = plr.Character
	if not char or flightByPlayer[plr] then
		return
	end
	if not ResourceService.hasMinimum(char, CHAR_ID, C.FlameFlight.ABILITY_ID) then
		return
	end
	if AbilityCooldownHelper.isOnCooldown(char, C.FlameFlight.ABILITY_ID) then
		return
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or not root then
		return
	end
	local att = root:FindFirstChildOfClass("Attachment")
	if not att then
		att = Instance.new("Attachment")
		att.Name = "FlightAttachment"
		att.Parent = root
	end
	local lv = Instance.new("LinearVelocity", root)
	lv.Name = "FlameFlightLinearVel"
	lv.Attachment0 = att
	lv.MaxForce = math.huge
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	local vf = Instance.new("VectorForce", root)
	vf.Name = "FlameFlightGravityCancel"
	vf.Attachment0 = att
	vf.Force = Vector3.new(0, root.AssemblyMass * workspace.Gravity, 0)
	vf.RelativeTo = Enum.ActuatorRelativeTo.World
	local al = Instance.new("AlignOrientation", root)
	al.Name = "FlameFlightAlign"
	al.Attachment0 = att
	al.Mode = Enum.OrientationAlignmentMode.OneAttachment
	al.MaxTorque = math.huge
	al.Responsiveness = TelekineticFlightConstants.ALIGN_RESPONSIVENESS
	al.RigidityEnabled = false
	al.CFrame = root.CFrame
	hum.PlatformStand = true
	hum:ChangeState(Enum.HumanoidStateType.Physics)
	flightByPlayer[plr] = {
		caster = char,
		humanoid = hum,
		root = root,
		linearVel = lv,
		gravityCancel = vf,
		align = al,
		moveDir = Vector3.zero,
		lookDir = root.CFrame.LookVector,
		flightMode = MODE_IDLE,
		currentVel = Vector3.zero,
		originalWalkSpeed = hum.WalkSpeed,
		originalJumpPower = hum.JumpPower,
		originalJumpHeight = hum.JumpHeight,
		originalJumpEnabled = hum:GetStateEnabled(Enum.HumanoidStateType.Jumping),
		originalAutoRotate = hum.AutoRotate,
	}
	char:SetAttribute("IsFlameFlying", true)
	char:SetAttribute("FlightInputActive", false)
	char:SetAttribute("FlightAlphaSpeed", 0)
end

local function fireballConfig()
	local cfg = C.Fireball
	return {
		abilityId = cfg.ABILITY_ID,
		boltName = "Fireball",
		size = cfg.SIZE,
		color = COLOR,
		speed = cfg.SPEED,
		maxRange = cfg.RANGE,
		lifetime = cfg.LIFETIME,
		damage = cfg.DAMAGE,
		pushSpeed = cfg.PUSH_SPEED,
		pushUp = cfg.PUSH_UP,
		curveStrength = cfg.CURVE_STRENGTH,
		impactRadius = cfg.EXPLOSION_RADIUS,
		impactDuration = 0.35,
	}
end

local function onFireballHit(plr: Player, hit: BasePart, caster: Model, direction: Vector3)
	AbilityCombatHelper.hitInRadius(hit.Position, C.Fireball.EXPLOSION_RADIUS, caster, {
		damage = C.Fireball.DAMAGE,
		pushSpeed = C.Fireball.PUSH_SPEED,
		pushUp = C.Fireball.PUSH_UP,
		excludePlayer = plr,
	})
end

local function novaBurst(plr: Player, char: Model)
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	AbilityVfxHelper.spawnGroundRing(root.Position, COLOR, 2, C.NovaBurst.RADIUS, 0.4)
	AbilityCombatHelper.hitInRadius(root.Position, C.NovaBurst.RADIUS, char, {
		damage = C.NovaBurst.DAMAGE,
		pushSpeed = C.NovaBurst.PUSH_SPEED,
		pushUp = C.NovaBurst.PUSH_UP,
		excludePlayer = plr,
	})
end

local function fireRush(plr: Player, char: Model, lookX: number, lookY: number, lookZ: number)
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not root or not hum then
		return
	end
	local cfg = C.FireRush
	local look = normalizeLook(lookX, lookY, lookZ, root.CFrame.LookVector)
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.01 then
		flat = Vector3.new(0, 0, -1)
	else
		flat = flat.Unit
	end
	local endPos = root.Position + flat * cfg.DASH_DISTANCE
	endPos = Vector3.new(endPos.X, root.Position.Y, endPos.Z)

	char:SetAttribute("IsFireRushing", true)
	hum.PlatformStand = true
	AbilityVfxHelper.spawnDirectionalBurst(root.Position, flat, COLOR, 4, cfg.DASH_DURATION)
	SmoothMotionHelper.runSmoothTravel(root, root.Position, endPos, cfg.DASH_DURATION, flat)
	hum.PlatformStand = false
	char:SetAttribute("IsFireRushing", nil)

	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { char }
	local hitOnce: { [Instance]: boolean } = {}
	for _, part in workspace:GetPartBoundsInRadius(root.Position, 5, overlap) do
		local model = part:FindFirstAncestorOfClass("Model")
		if not model or model == char then
			if InteractableHelper.hasInteractableMark(part) and not hitOnce[part] then
				hitOnce[part] = true
				InteractableHelper.applyDamage(part, cfg.DAMAGE)
				PushHelper.applyToPart(part, flat, { speed = cfg.PUSH_SPEED, upBoost = cfg.PUSH_UP })
			end
			continue
		end
		local key = model:FindFirstChild("HumanoidRootPart") or part
		if hitOnce[key] then
			continue
		end
		hitOnce[key] = true
		local targetHum = model:FindFirstChildOfClass("Humanoid")
		if targetHum and targetHum.Health > 0 then
			local targetPlr = Players:GetPlayerFromCharacter(model)
			if targetPlr ~= plr then
				targetHum:TakeDamage(cfg.DAMAGE)
				PushHelper.applyToModel(model, flat, { speed = cfg.PUSH_SPEED, upBoost = cfg.PUSH_UP })
			end
		elseif InteractableHelper.modelIsInteractableProp(model) then
			InteractableHelper.applyDamage(model, cfg.DAMAGE)
			PushHelper.applyToModel(model, flat, { speed = cfg.PUSH_SPEED, upBoost = cfg.PUSH_UP })
		end
	end
end

local function inferno(plr: Player, char: Model, alpha: number)
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local cfg = C.Inferno
	local maxR = cfg.MIN_RADIUS + (cfg.MAX_RADIUS - cfg.MIN_RADIUS) * alpha
	local damage = cfg.MIN_DAMAGE + (cfg.MAX_DAMAGE - cfg.MIN_DAMAGE) * alpha
	AbilityVfxHelper.spawnExpandingSphere(root.Position, COLOR, 2, maxR, cfg.WAVE_DURATION)
	AbilityVfxHelper.spawnGroundRing(root.Position, COLOR, 3, maxR, cfg.WAVE_DURATION)
	local hitOnce: { [Instance]: boolean } = {}
	local start = tick()
	while tick() - start < cfg.WAVE_DURATION do
		local a = SmoothMotionHelper.smoothstep((tick() - start) / cfg.WAVE_DURATION)
		AbilityCombatHelper.hitInRadius(root.Position, maxR * a, char, {
			damage = damage,
			pushSpeed = cfg.PUSH_SPEED,
			pushUp = cfg.PUSH_UP,
			excludePlayer = plr,
		}, hitOnce)
		RunService.Heartbeat:Wait()
	end
end

function HumanTorchAbilitiesService.setup(
	flightToggle: RemoteEvent,
	flightInput: RemoteEvent,
	fireballStart: RemoteEvent,
	fireballAim: RemoteEvent,
	fireballRelease: RemoteEvent,
	novaRemote: RemoteEvent,
	fireRushRemote: RemoteEvent,
	infernoRemote: RemoteEvent
)
	ResourceService.registerStopCallback("IsFlameFlying", function(p)
		endFlight(p, false)
	end)

	flightToggle.OnServerEvent:Connect(function(plr, enable: unknown)
		if not isTorch(plr) or typeof(enable) ~= "boolean" then
			return
		end
		if enable then
			startFlight(plr)
		else
			endFlight(plr, true)
		end
	end)

	flightInput.OnServerEvent:Connect(function(plr, mx, my, mz, lx, ly, lz, mode)
		local state = flightByPlayer[plr]
		if not state then
			return
		end
		state.moveDir = Vector3.new(mx, my, mz)
		if state.moveDir.Magnitude > 1 then
			state.moveDir = state.moveDir.Unit
		elseif state.moveDir.Magnitude < 0.01 then
			state.moveDir = Vector3.zero
		end
		state.lookDir = normalize(Vector3.new(lx, ly, lz))
		state.flightMode = if typeof(mode) == "number" then math.floor(mode) else MODE_IDLE
	end)

	fireballStart.OnServerEvent:Connect(function(plr: Player, dirX: unknown, dirY: unknown, dirZ: unknown)
		if not isTorch(plr) or typeof(dirX) ~= "number" or typeof(dirY) ~= "number" or typeof(dirZ) ~= "number" then
			return
		end
		local char = plr.Character
		if not char or AbilityCooldownHelper.isOnCooldown(char, C.Fireball.ABILITY_ID) then
			return
		end
		if not ResourceService.trySpend(char, 7) then
			return
		end
		local state = SteerableBoltService.handleStart(plr, C.Fireball.ABILITY_ID, dirX, dirY, dirZ, fireballConfig(), onFireballHit)
		if state then
			AbilityCooldownHelper.apply(char, C.Fireball.ABILITY_ID, C.Fireball.COOLDOWN_SEC)
		end
	end)

	fireballAim.OnServerEvent:Connect(function(plr: Player, dirX: unknown, dirY: unknown, dirZ: unknown)
		if not isTorch(plr) or typeof(dirX) ~= "number" or typeof(dirY) ~= "number" or typeof(dirZ) ~= "number" then
			return
		end
		SteerableBoltService.handleAim(plr, C.Fireball.ABILITY_ID, dirX, dirY, dirZ)
	end)

	fireballRelease.OnServerEvent:Connect(function(plr: Player)
		if not isTorch(plr) then
			return
		end
		SteerableBoltService.handleRelease(plr, C.Fireball.ABILITY_ID)
	end)

	novaRemote.OnServerEvent:Connect(function(plr)
		if not isTorch(plr) then
			return
		end
		local char = plr.Character
		if not char or AbilityCooldownHelper.isOnCooldown(char, C.NovaBurst.ABILITY_ID) then
			return
		end
		if not ResourceService.trySpend(char, 22) then
			return
		end
		AbilityCooldownHelper.apply(char, C.NovaBurst.ABILITY_ID, C.NovaBurst.COOLDOWN_SEC)
		novaBurst(plr, char)
	end)

	fireRushRemote.OnServerEvent:Connect(function(plr, lookX: unknown, lookY: unknown, lookZ: unknown)
		if not isTorch(plr) or typeof(lookX) ~= "number" or typeof(lookY) ~= "number" or typeof(lookZ) ~= "number" then
			return
		end
		local char = plr.Character
		if not char or AbilityCooldownHelper.isOnCooldown(char, C.FireRush.ABILITY_ID) then
			return
		end
		if not ResourceService.trySpend(char, 14) then
			return
		end
		AbilityCooldownHelper.apply(char, C.FireRush.ABILITY_ID, C.FireRush.COOLDOWN_SEC)
		task.spawn(function()
			fireRush(plr, char, lookX, lookY, lookZ)
		end)
	end)

	infernoRemote.OnServerEvent:Connect(function(plr, alpha: unknown)
		if not isTorch(plr) or typeof(alpha) ~= "number" then
			return
		end
		local char = plr.Character
		if not char or AbilityCooldownHelper.isOnCooldown(char, C.Inferno.ABILITY_ID) then
			return
		end
		local a = math.clamp(alpha, 0, 1)
		local cost = ResourceService.getScaledCost(CHAR_ID, C.Inferno.ABILITY_ID, a) or 12
		if not ResourceService.trySpend(char, cost) then
			return
		end
		AbilityCooldownHelper.apply(char, C.Inferno.ABILITY_ID, C.Inferno.COOLDOWN_SEC)
		task.spawn(function()
			inferno(plr, char, a)
		end)
	end)
end

function HumanTorchAbilitiesService.update(dt: number)
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

function HumanTorchAbilitiesService.forceEnd(plr: Player)
	endFlight(plr, false)
end

function HumanTorchAbilitiesService.onPlayerRemoving(plr: Player)
	endFlight(plr, false)
end

return HumanTorchAbilitiesService
