--!strict
--[[
	Shared steerable projectile logic (Psionic Bolt pattern).
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local AbilityVfxHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityVfxHelper"))
local PushHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PushHelper"))

export type BoltConfig = {
	abilityId: string,
	boltName: string,
	size: Vector3,
	color: Color3,
	speed: number,
	maxRange: number,
	lifetime: number,
	damage: number,
	pushSpeed: number,
	pushUp: number,
	pushImpulseMult: number?,
	curveStrength: number,
	impactRadius: number,
	impactDuration: number,
}

export type HitCallback = (player: Player, hit: BasePart, caster: Model, direction: Vector3) -> ()
export type SpawnPartFactory = (spawnCF: CFrame, config: BoltConfig) -> BasePart

type BoltState = {
	part: BasePart,
	velocity: Vector3,
	origin: Vector3,
	caster: Model,
	steerable: boolean,
	aimDirection: Vector3,
	traveled: number,
	config: BoltConfig,
	onHit: HitCallback?,
}

local SteerableBoltService = {}

local steerableByPlayer: { [Player]: { [string]: { BoltState } } } = {}
local activeBolts: { [BasePart]: BoltState } = {}

local function normalizeDir(x: number, y: number, z: number): Vector3
	local v = Vector3.new(x, y, z)
	if v.Magnitude < 0.01 then
		return Vector3.new(0, 0, -1)
	end
	return v.Unit
end

local function getHeadPart(character: Model): BasePart?
	return character:FindFirstChild("Head") :: BasePart?
		or character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function isPartOfCharacter(part: BasePart, character: Model): boolean
	return part:FindFirstAncestorOfClass("Model") == character
end

local function spawnImpactVfx(position: Vector3, color: Color3, radius: number, duration: number)
	AbilityVfxHelper.spawnExpandingSphere(position, color, 0.8, radius, duration)
end

local function tryDeflectByProbabilityShield(hit: BasePart, state: BoltState): boolean
	local model = hit:FindFirstAncestorOfClass("Model")
	if not model or model == state.caster then
		return false
	end
	if model:GetAttribute("ProbabilityShieldActive") ~= true then
		return false
	end
	local hp = model:GetAttribute("ProbabilityShieldHealth")
	if typeof(hp) ~= "number" then
		hp = 100
	end
	hp -= 20
	model:SetAttribute("ProbabilityShieldHealth", hp)
	if hp <= 0 then
		model:SetAttribute("ProbabilityShieldActive", nil)
		model:SetAttribute("ProbabilityShieldHealth", nil)
	end
	local reverseDir = if state.velocity.Magnitude > 0.01 then -state.velocity.Unit else -state.aimDirection
	state.velocity = reverseDir * state.config.speed
	state.aimDirection = reverseDir
	state.part.AssemblyLinearVelocity = state.velocity
	return true
end

local function destroyBolt(state: BoltState)
	activeBolts[state.part] = nil
	if state.part.Parent then
		state.part:Destroy()
	end
end

local function defaultOnHit(state: BoltState, hit: BasePart)
	local model = hit:FindFirstAncestorOfClass("Model")
	local humanoid = if model then model:FindFirstChildOfClass("Humanoid") else nil
	local pushDirection = if state.velocity.Magnitude > 0.01 then state.velocity else state.aimDirection
	if humanoid and humanoid.Health > 0 then
		humanoid:TakeDamage(state.config.damage)
	end
	PushHelper.applyFromHit(hit, pushDirection, {
		speed = state.config.pushSpeed,
		upBoost = state.config.pushUp,
		impulseMult = state.config.pushImpulseMult or 1.2,
	}, state.caster)
end

function SteerableBoltService.launch(
	plr: Player,
	char: Model,
	direction: Vector3,
	config: BoltConfig,
	onHit: HitCallback?,
	spawnPart: SpawnPartFactory?
): BoltState?
	local head = getHeadPart(char)
	if not head then
		return nil
	end
	local spawnCF = head.CFrame * CFrame.new(0, 0, -2)
	local part = if spawnPart
		then spawnPart(spawnCF, config)
		else AbilityVfxHelper.spawnProjectilePart(spawnCF, config.color, config.size)
	part.Name = config.boltName
	local vel = direction * config.speed
	part.AssemblyLinearVelocity = vel

	local state: BoltState = {
		part = part,
		velocity = vel,
		origin = spawnCF.Position,
		caster = char,
		steerable = true,
		aimDirection = direction,
		traveled = 0,
		config = config,
		onHit = onHit,
	}

	activeBolts[part] = state
	Debris:AddItem(part, config.lifetime)

	part.Touched:Connect(function(hit)
		if not activeBolts[part] then
			return
		end
		if not hit or not hit.Parent or isPartOfCharacter(hit, char) then
			return
		end
		if tryDeflectByProbabilityShield(hit, state) then
			return
		end
		spawnImpactVfx(part.Position, config.color, config.impactRadius, config.impactDuration)
		if onHit then
			local dir = if state.velocity.Magnitude > 0.01 then state.velocity else state.aimDirection
			onHit(plr, hit, char, dir)
		else
			defaultOnHit(state, hit)
		end
		destroyBolt(state)
	end)

	return state
end

local function spreadDirection(base: Vector3, angleDeg: number): Vector3
	local c = math.cos(math.rad(angleDeg))
	local s = math.sin(math.rad(angleDeg))
	return Vector3.new(base.X * c - base.Z * s, base.Y, base.X * s + base.Z * c).Unit
end

local function storeSteerStates(plr: Player, abilityId: string, states: { BoltState })
	if #states == 0 then
		return
	end
	if not steerableByPlayer[plr] then
		steerableByPlayer[plr] = {}
	end
	steerableByPlayer[plr][abilityId] = states
end

function SteerableBoltService.handleStart(plr: Player, abilityId: string, dirX: number, dirY: number, dirZ: number, config: BoltConfig, onHit: HitCallback?, spawnPart: SpawnPartFactory?): BoltState?
	local char = plr.Character
	if not char then
		return nil
	end
	local direction = normalizeDir(dirX, dirY, dirZ)
	local state = SteerableBoltService.launch(plr, char, direction, config, onHit, spawnPart)
	if state then
		storeSteerStates(plr, abilityId, { state })
		if abilityId == "MagneticPulse" then
			char:SetAttribute("IsMagneticPulseActive", true)
		elseif abilityId == "EnergyBlast" then
			char:SetAttribute("IsEnergyBlastActive", true)
		elseif abilityId == "SolarFlare" then
			char:SetAttribute("IsSolarFlareActive", true)
		end
	end
	return state
end

function SteerableBoltService.handleStartVolley(
	plr: Player,
	abilityId: string,
	dirX: number,
	dirY: number,
	dirZ: number,
	config: BoltConfig,
	onHit: HitCallback?,
	shotCount: number,
	spreadDeg: number
): { BoltState }
	local char = plr.Character
	if not char then
		return {}
	end
	local direction = normalizeDir(dirX, dirY, dirZ)
	local states: { BoltState } = {}
	for i = 1, shotCount do
		local offsetIdx = i - ((shotCount + 1) * 0.5)
		local spreadDir = spreadDirection(direction, offsetIdx * spreadDeg)
		local state = SteerableBoltService.launch(plr, char, spreadDir, config, onHit)
		if state then
			table.insert(states, state)
		end
	end
	storeSteerStates(plr, abilityId, states)
	return states
end

function SteerableBoltService.handleAim(plr: Player, abilityId: string, dirX: number, dirY: number, dirZ: number)
	local bucket = steerableByPlayer[plr]
	if not bucket then
		return
	end
	local states = bucket[abilityId]
	if not states then
		return
	end
	local aim = normalizeDir(dirX, dirY, dirZ)
	for _, state in states do
		if activeBolts[state.part] then
			state.aimDirection = aim
			state.steerable = true
		end
	end
end

function SteerableBoltService.handleRelease(plr: Player, abilityId: string)
	local bucket = steerableByPlayer[plr]
	if bucket then
		bucket[abilityId] = nil
	end
	if abilityId == "MagneticPulse" then
		local char = plr.Character
		if char then
			char:SetAttribute("IsMagneticPulseActive", nil)
		end
	elseif abilityId == "EnergyBlast" then
		local char = plr.Character
		if char then
			char:SetAttribute("IsEnergyBlastActive", nil)
		end
	elseif abilityId == "SolarFlare" then
		local char = plr.Character
		if char then
			char:SetAttribute("IsSolarFlareActive", nil)
		end
	end
end

function SteerableBoltService.update(dt: number)
	for part, state in activeBolts do
		if not part.Parent then
			activeBolts[part] = nil
			continue
		end
		local step = state.velocity * dt
		state.traveled += step.Magnitude
		if state.steerable then
			local desired = state.aimDirection * state.config.speed
			local alpha = math.min(1, dt * state.config.curveStrength)
			state.velocity = state.velocity:Lerp(desired, alpha)
			part.AssemblyLinearVelocity = state.velocity
			local look = if state.velocity.Magnitude > 0.01 then state.velocity.Unit else state.aimDirection
			part.CFrame = CFrame.lookAt(part.Position, part.Position + look)
		else
			part.AssemblyLinearVelocity = state.velocity
			local look = if state.velocity.Magnitude > 0.01 then state.velocity.Unit else state.aimDirection
			part.CFrame = CFrame.lookAt(part.Position, part.Position + look)
		end
		if state.traveled >= state.config.maxRange then
			destroyBolt(state)
		end
	end
end

function SteerableBoltService.onPlayerRemoving(plr: Player)
	steerableByPlayer[plr] = nil
end

return SteerableBoltService
