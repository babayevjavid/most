--!strict
--[[
	Psionic Bolt server: fire immediately on start; aim updates steer active bolt.
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local AbilityCooldownHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityCooldownHelper"))
local EnergyConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("EnergyConstants"))
local PsionicBoltConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PsionicBoltConstants"))
local PushHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PushHelper"))

local EnergyService = require(script.Parent:WaitForChild("EnergyService"))

local ABILITY_ID = PsionicBoltConstants.ABILITY_ID
local COOLDOWN_SEC = PsionicBoltConstants.COOLDOWN_SEC

type BoltState = {
	part: BasePart,
	velocity: Vector3,
	origin: Vector3,
	caster: Model,
	steerable: boolean,
	aimDirection: Vector3,
	traveled: number,
}

local steerableByPlayer: { [Player]: BoltState? } = {}
local activeBolts: { [BasePart]: BoltState } = {}

local PsionicBoltService = {}

local function isJeanGrey(plr: Player): boolean
	return plr:GetAttribute("SelectedCharacter") == "JeanGrey"
end

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

local function createBoltPart(origin: CFrame): BasePart
	local part = Instance.new("Part")
	part.Name = "PsionicBolt"
	part.Size = PsionicBoltConstants.BOLT_SIZE
	part.Material = Enum.Material.Neon
	part.Color = Color3.fromRGB(255, 105, 220)
	part.CanCollide = false
	part.CanQuery = true
	part.CanTouch = true
	part.Massless = true
	part.Anchored = false
	part.CFrame = origin
	part.Parent = workspace

	return part
end

local function isPartOfCharacter(part: BasePart, character: Model): boolean
	local model = part:FindFirstAncestorOfClass("Model")
	return model == character
end

local function spawnImpactVfx(position: Vector3)
	local radius = PsionicBoltConstants.IMPACT_VFX_RADIUS
	local duration = PsionicBoltConstants.IMPACT_VFX_DURATION
	local boltColor = Color3.fromRGB(255, 105, 220)

	local anchor = Instance.new("Part")
	anchor.Name = "PsionicBoltImpact"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = workspace

	local core = Instance.new("Part")
	core.Name = "Core"
	core.Shape = Enum.PartType.Ball
	core.Material = Enum.Material.Neon
	core.Color = boltColor
	core.Anchored = true
	core.CanCollide = false
	core.CanQuery = false
	core.CanTouch = false
	core.Size = Vector3.new(0.8, 0.8, 0.8)
	core.CFrame = CFrame.new(position)
	core.Parent = anchor

	local endSize = Vector3.new(radius * 1.6, radius * 1.6, radius * 1.6)
	TweenService:Create(
		core,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = endSize, Transparency = 1 }
	):Play()

	Debris:AddItem(anchor, duration + 0.05)
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
	state.velocity = reverseDir * PsionicBoltConstants.BOLT_SPEED
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

local function onBoltHit(state: BoltState, hit: BasePart)
	if not hit or not hit.Parent then
		return
	end
	if isPartOfCharacter(hit, state.caster) then
		return
	end
	if tryDeflectByProbabilityShield(hit, state) then
		return
	end

	spawnImpactVfx(state.part.Position)

	local model = hit:FindFirstAncestorOfClass("Model")
	local humanoid = if model then model:FindFirstChildOfClass("Humanoid") else nil
	local pushDirection = if state.velocity.Magnitude > 0.01 then state.velocity else state.aimDirection

	if humanoid and humanoid.Health > 0 then
		humanoid:TakeDamage(PsionicBoltConstants.BOLT_DAMAGE)
	end

	PushHelper.applyFromHit(hit, pushDirection, {
		speed = PsionicBoltConstants.BOLT_PUSH_SPEED,
		upBoost = PsionicBoltConstants.BOLT_PUSH_UP,
		impulseMult = PsionicBoltConstants.BOLT_PUSH_IMPULSE_MULT,
	}, state.caster)

	destroyBolt(state)
end

local function launchBolt(plr: Player, direction: Vector3, steerable: boolean): BoltState?
	local char = plr.Character
	if not char then
		return nil
	end
	local head = getHeadPart(char)
	if not head then
		return nil
	end

	local spawnCF = head.CFrame * CFrame.new(0, 0, -2)
	local part = createBoltPart(spawnCF)
	local vel = direction * PsionicBoltConstants.BOLT_SPEED
	part.AssemblyLinearVelocity = vel

	local state: BoltState = {
		part = part,
		velocity = vel,
		origin = spawnCF.Position,
		caster = char,
		steerable = steerable,
		aimDirection = direction,
		traveled = 0,
	}

	activeBolts[part] = state
	Debris:AddItem(part, PsionicBoltConstants.BOLT_LIFETIME)

	part.Touched:Connect(function(hit)
		if activeBolts[part] then
			onBoltHit(state, hit)
		end
	end)

	return state
end

function PsionicBoltService.setup(boltStart: RemoteEvent, boltAim: RemoteEvent, boltRelease: RemoteEvent)
	boltStart.OnServerEvent:Connect(function(plr: Player, dirX: number, dirY: number, dirZ: number)
		if not isJeanGrey(plr) then
			return
		end
		local char = plr.Character
		if not char then
			return
		end
		if char:GetAttribute("IsTelekineticFlying") == true then
			return
		end
		if AbilityCooldownHelper.isOnCooldown(char, ABILITY_ID) then
			return
		end
		if not EnergyService.trySpend(char, EnergyConstants.INSTANT.PsionicBolt) then
			return
		end

		local direction = normalizeDir(dirX, dirY, dirZ)
		local state = launchBolt(plr, direction, true)
		if state then
			steerableByPlayer[plr] = state
			AbilityCooldownHelper.apply(char, ABILITY_ID, COOLDOWN_SEC)
		end
	end)

	boltAim.OnServerEvent:Connect(function(plr: Player, dirX: number, dirY: number, dirZ: number)
		local state = steerableByPlayer[plr]
		if not state or not activeBolts[state.part] then
			return
		end
		state.aimDirection = normalizeDir(dirX, dirY, dirZ)
		state.steerable = true
	end)

	boltRelease.OnServerEvent:Connect(function(plr: Player)
		steerableByPlayer[plr] = nil
	end)
end

function PsionicBoltService.update(dt: number)
	for part, state in activeBolts do
		if not part.Parent then
			activeBolts[part] = nil
			continue
		end

		local step = state.velocity * dt
		state.traveled += step.Magnitude

		if state.steerable then
			local desired = state.aimDirection * PsionicBoltConstants.BOLT_SPEED
			local alpha = math.min(1, dt * PsionicBoltConstants.CURVE_STRENGTH)
			state.velocity = state.velocity:Lerp(desired, alpha)
			part.AssemblyLinearVelocity = state.velocity
			local look = if state.velocity.Magnitude > 0.01 then state.velocity.Unit else state.aimDirection
			part.CFrame = CFrame.lookAt(part.Position, part.Position + look)
		end

		if state.traveled >= PsionicBoltConstants.BOLT_MAX_RANGE then
			destroyBolt(state)
		end
	end
end

function PsionicBoltService.onPlayerRemoving(plr: Player)
	steerableByPlayer[plr] = nil
end

return PsionicBoltService
