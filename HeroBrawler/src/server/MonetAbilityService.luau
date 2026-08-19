--!strict

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AbilityCooldownHelper = require(ReplicatedStorage.Shared.AbilityCooldownHelper)
local CharacterRegistry = require(ReplicatedStorage.Shared.CharacterRegistry)
local CombatHelper = require(ReplicatedStorage.Shared.CombatHelper)
local ConstraintHelper = require(ReplicatedStorage.Shared.ConstraintHelper)
local MonetConstants = require(ReplicatedStorage.Shared.MonetConstants)
local MovementHelper = require(ReplicatedStorage.Shared.MovementHelper)
local PushHelper = require(ReplicatedStorage.Shared.PushHelper)
local StatusEffectHelper = require(ReplicatedStorage.Shared.StatusEffectHelper)
local VfxHelper = require(ReplicatedStorage.Shared.VfxHelper)
local CharacterService = require(script.Parent.CharacterService)
local MonetFlightService = require(script.Parent.MonetFlightService)

local MonetAbilityService = {}

type CurlState = {
	character: Model,
	player: Player,
	humanoid: Humanoid,
	root: BasePart,
	mover: ConstraintHelper.MoverBundle,
	ball: BasePart,
	weld: WeldConstraint,
	spin: AngularVelocity,
	hidden: { BasePart },
	storedTransparency: { [BasePart]: number },
	lastContact: number,
	elapsed: number,
}

type ChargeState = {
	started: number,
	direction: Vector3,
	abilityId: string,
}

type DashState = {
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	mover: ConstraintHelper.MoverBundle,
	direction: Vector3,
	elapsed: number,
	duration: number,
	speed: number,
	hitTargets: { [Model]: boolean },
	lastTrail: number,
	abilityId: string,
	cooldown: number,
}

type OrbitVictim = {
	target: Model,
	angle: number,
	radius: number,
}

type AstralState = {
	player: Player,
	character: Model,
	root: BasePart,
	entry: any,
	victims: { OrbitVictim },
}

type CataclysmState = {
	player: Player,
	character: Model,
	root: BasePart,
	entry: any,
}

local activeCurls: { [Model]: CurlState } = {}
local curlMoveVectors: { [Model]: Vector3 } = {}
local chargeByCharacter: { [Model]: ChargeState } = {}
local dashByCharacter: { [Model]: DashState } = {}
local astralByPlayer: { [Player]: AstralState } = {}
local cataclysmByPlayer: { [Player]: CataclysmState } = {}

local BODY_HIDE_NAMES: { [string]: boolean } = {
	Head = true, UpperTorso = true, LowerTorso = true, Torso = true,
	LeftArm = true, RightArm = true, LeftLeg = true, RightLeg = true,
	LeftUpperArm = true, RightUpperArm = true, LeftLowerArm = true, RightLowerArm = true,
	LeftHand = true, RightHand = true, LeftUpperLeg = true, RightUpperLeg = true,
	LeftLowerLeg = true, RightLowerLeg = true, LeftFoot = true, RightFoot = true,
}

local function finishAbility(character: Model, abilityId: string, cooldown: number)
	AbilityCooldownHelper.setActive(character, abilityId, false)
	AbilityCooldownHelper.applyAfterUse(character, abilityId, cooldown)
end

local function trySpendEnergy(character: Model, amount: number): boolean
	local energy = character:GetAttribute(MonetConstants.ENERGY_ATTRIBUTE)
	if type(energy) ~= "number" or energy < amount then
		return false
	end
	character:SetAttribute(MonetConstants.ENERGY_ATTRIBUTE, energy - amount)
	return true
end

local function isFlying(character: Model?): boolean
	return character ~= nil and character:GetAttribute(MonetConstants.IS_FLYING_ATTRIBUTE) == true
end

local function canStartAbility(character: Model, abilityId: string, energyCost: number): boolean
	if AbilityCooldownHelper.isOnCooldown(character, abilityId) then
		return false
	end
	if AbilityCooldownHelper.isActive(character, abilityId) then
		return false
	end
	if character:GetAttribute(MonetConstants.HERO_ATTRIBUTE) ~= "monet_st_croix" then
		return false
	end
	if not trySpendEnergy(character, energyCost) then
		return false
	end
	return true
end

local function getAbilityDef(form: "Monet" | "Penance", key: string)
	return CharacterRegistry.getAbilityByKey("monet_st_croix", form, key)
end

-- Blood Rush (Penance Q)

function MonetAbilityService.bloodRush(player: Player, direction: Vector3)
	local character = player.Character
	if not character or CharacterService.getForm(character) ~= "Penance" then
		return
	end
	local entry = getAbilityDef("Penance", "Q")
	if not entry or entry.id ~= "blood_rush" then
		return
	end
	if not canStartAbility(character, entry.id, entry.energyCost) then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root then
		return
	end

	AbilityCooldownHelper.setActive(character, entry.id, true)
	ConstraintHelper.lockHumanoidForAbility(humanoid)
	local mover = ConstraintHelper.createMover(root, true, false)
	local flatDir = MovementHelper.flattenDirection(direction)

	dashByCharacter[character] = {
		character = character,
		humanoid = humanoid,
		root = root,
		mover = mover,
		direction = flatDir,
		elapsed = 0,
		duration = MonetConstants.RUSH_DURATION,
		speed = MonetConstants.RUSH_SPEED,
		hitTargets = {},
		lastTrail = 0,
		abilityId = entry.id,
		cooldown = entry.cooldown,
	}

	VfxHelper.pulseAbility(character, entry.id)
	VfxHelper.spawnBurstSparks(root.Position, Color3.fromRGB(255, 60, 70), 12)
end

-- Psychic Repulsion charge (Monet F)

function MonetAbilityService.startPsychicCharge(player: Player, direction: Vector3)
	local character = player.Character
	if not character or CharacterService.getForm(character) ~= "Monet" or isFlying(character) then
		return
	end
	local entry = getAbilityDef("Monet", "F")
	if not entry then
		return
	end
	if AbilityCooldownHelper.isOnCooldown(character, entry.id) or AbilityCooldownHelper.isActive(character, entry.id) then
		return
	end
	chargeByCharacter[character] = {
		started = os.clock(),
		direction = MovementHelper.flattenDirection(direction),
		abilityId = entry.id,
	}
	character:SetAttribute("PsychicCharging", true)
	VfxHelper.spawnPulseRing(
		(character:FindFirstChild("HumanoidRootPart") :: BasePart?).Position or Vector3.zero,
		3,
		VfxHelper.psychicColor(),
		0.3
	)
end

function MonetAbilityService.releasePsychicCharge(player: Player, direction: Vector3)
	local character = player.Character
	if not character then
		return
	end
	local charge = chargeByCharacter[character]
	chargeByCharacter[character] = nil
	character:SetAttribute("PsychicCharging", nil)
	if not charge then
		return
	end

	local entry = CharacterRegistry.getAbilityById("monet_st_croix", charge.abilityId)
	if not entry then
		return
	end
	if not canStartAbility(character, entry.id, entry.energyCost) then
		return
	end

	AbilityCooldownHelper.setActive(character, entry.id, true)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		finishAbility(character, entry.id, entry.cooldown)
		return
	end

	local held = math.clamp(os.clock() - charge.started, 0, MonetConstants.PUSH_CHARGE_MAX)
	local ratio = held / MonetConstants.PUSH_CHARGE_MAX
	local flatDir = MovementHelper.flattenDirection(direction)
	local damage = MonetConstants.PUSH_MIN_DAMAGE + (MonetConstants.PUSH_MAX_DAMAGE - MonetConstants.PUSH_MIN_DAMAGE) * ratio
	local force = MonetConstants.PUSH_MIN_FORCE + (MonetConstants.PUSH_MAX_FORCE - MonetConstants.PUSH_MIN_FORCE) * ratio

	for ring = 1, MonetConstants.PUSH_RING_COUNT do
		local dist = (MonetConstants.PUSH_RANGE / MonetConstants.PUSH_RING_COUNT) * ring
		local origin = root.Position + flatDir * dist
		VfxHelper.spawnPulseRing(origin, 4 + ring * 2, VfxHelper.psychicColor(), 0.35)
		local targets = CombatHelper.overlapCharacters(origin, 10 + ring * 2, character)
		for _, target in targets do
			CombatHelper.dealDamage(character, target, damage * (0.65 + ring * 0.1))
			PushHelper.applyToCharacter(target, flatDir, { speed = force, upBoost = 12 + ratio * 18 })
		end
		task.wait(0.05)
	end

	VfxHelper.pulseAbility(character, entry.id)
	character:SetAttribute("PsychicRepulsionRelease", true)
	task.delay(0.05, function()
		if character.Parent then
			character:SetAttribute("PsychicRepulsionRelease", nil)
		end
	end)
	finishAbility(character, entry.id, entry.cooldown)
end

function MonetAbilityService.mindShatter(player: Player, direction: Vector3)
	local character = player.Character
	if not character or CharacterService.getForm(character) ~= "Monet" then
		return
	end
	local entry = getAbilityDef("Monet", "R")
	if not entry then
		return
	end
	if not canStartAbility(character, entry.id, entry.energyCost) then
		return
	end

	AbilityCooldownHelper.setActive(character, entry.id, true)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		finishAbility(character, entry.id, entry.cooldown)
		return
	end

	local flatDir = MovementHelper.flattenDirection(direction)
	local target = CombatHelper.raycastCharacter(root.Position, flatDir, MonetConstants.PROBE_RANGE, character)
	local endPos = root.Position + flatDir * MonetConstants.PROBE_RANGE
	if target then
		local targetRoot = target:FindFirstChild("HumanoidRootPart") :: BasePart?
		if targetRoot then
			endPos = targetRoot.Position
			CombatHelper.dealDamage(character, target, MonetConstants.PROBE_DAMAGE)
			StatusEffectHelper.apply(target, "mind_shattered", "Mind Shattered", "Marked and disrupted by psychic fracture", MonetConstants.PROBE_DURATION)
			target:SetAttribute(MonetConstants.MIND_PROBE_ATTRIBUTE, AbilityCooldownHelper.getNow() + MonetConstants.PROBE_DURATION)
			PushHelper.applyToCharacter(target, flatDir, { speed = MonetConstants.PROBE_PULL_FORCE, upBoost = 6 })
			VfxHelper.spawnBurstSparks(targetRoot.Position, VfxHelper.psychicColor(), 14)
		end
	end

	VfxHelper.spawnBeamLine(root.Position, endPos, VfxHelper.psychicColor(), 0.5)
	VfxHelper.pulseAbility(character, entry.id)
	finishAbility(character, entry.id, entry.cooldown)
end

-- Diamond Curl ball (Penance F)

local function hideCharacterForBall(character: Model): ({ BasePart }, { [BasePart]: number })
	local hidden: { BasePart } = {}
	local stored: { [BasePart]: number } = {}
	for _, desc in character:GetDescendants() do
		if desc:IsA("BasePart") and BODY_HIDE_NAMES[desc.Name] then
			table.insert(hidden, desc)
			stored[desc] = desc.Transparency
			desc.Transparency = 1
			desc.CanCollide = false
		end
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		stored[root] = root.Transparency
		root.CanCollide = false
		root.Transparency = 1
	end
	return hidden, stored
end

local function restoreCharacterFromBall(state: CurlState)
	for part, transparency in state.storedTransparency do
		if part.Parent then
			part.Transparency = transparency
			if part ~= state.root then
				part.CanCollide = true
			end
		end
	end
	state.root.CanCollide = false
	if state.spin.Parent then
		state.spin:Destroy()
	end
	if state.weld.Parent then
		state.weld:Destroy()
	end
	if state.ball.Parent then
		state.ball:Destroy()
	end
	ConstraintHelper.destroyMover(state.mover)
	ConstraintHelper.unlockHumanoid(state.humanoid)
	state.character:SetAttribute(MonetConstants.CURL_ACTIVE_ATTRIBUTE, nil)
end

function MonetAbilityService.startDiamondCurl(player: Player, moveVector: Vector3)
	local character = player.Character
	if not character or CharacterService.getForm(character) ~= "Penance" or activeCurls[character] then
		return
	end
	local entry = getAbilityDef("Penance", "F")
	if not entry or not canStartAbility(character, entry.id, entry.energyCost) then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root then
		return
	end

	AbilityCooldownHelper.setActive(character, entry.id, true)
	ConstraintHelper.lockHumanoidForAbility(humanoid)

	local hidden, stored = hideCharacterForBall(character)
	local ball = Instance.new("Part")
	ball.Name = "DiamondCurlBall"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(MonetConstants.CURL_BALL_SIZE, MonetConstants.CURL_BALL_SIZE, MonetConstants.CURL_BALL_SIZE)
	ball.Material = Enum.Material.Glass
	ball.Color = Color3.fromRGB(190, 30, 55)
	ball.Reflectance = 0.45
	ball.CanCollide = true
	ball.Massless = false
	ball.CFrame = root.CFrame
	ball.Parent = character

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = ball
	weld.Parent = ball

	local att = root:FindFirstChild("HeroMoverAttachment") or Instance.new("Attachment")
	att.Name = "HeroMoverAttachment"
	att.Parent = root

	local spin = Instance.new("AngularVelocity")
	spin.Attachment0 = att
	spin.AngularVelocity = Vector3.new(0, MonetConstants.CURL_SPIN_SPEED, 0)
	spin.MaxTorque = math.huge
	spin.RelativeTo = Enum.ActuatorRelativeTo.World
	spin.Parent = root

	local mover = ConstraintHelper.createMover(root, false, true)
	activeCurls[character] = {
		character = character,
		player = player,
		humanoid = humanoid,
		root = root,
		mover = mover,
		ball = ball,
		weld = weld,
		spin = spin,
		hidden = hidden,
		storedTransparency = stored,
		lastContact = 0,
		elapsed = 0,
	}
	curlMoveVectors[character] = moveVector
	character:SetAttribute(MonetConstants.CURL_ACTIVE_ATTRIBUTE, true)
	VfxHelper.pulseAbility(character, entry.id)
	VfxHelper.spawnBurstSparks(root.Position, Color3.fromRGB(255, 40, 60), 10)
end

function MonetAbilityService.updateCurlMovement(player: Player, moveVector: Vector3)
	local character = player.Character
	if character and activeCurls[character] then
		curlMoveVectors[character] = moveVector
	end
end

function MonetAbilityService.releaseDiamondCurl(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local state = activeCurls[character]
	if not state then
		return
	end
	activeCurls[character] = nil
	curlMoveVectors[character] = nil

	local entry = getAbilityDef("Penance", "F")
	if not entry then
		return
	end

	local root = state.root
	restoreCharacterFromBall(state)

	if root.Parent then
		local targets = CombatHelper.overlapCharacters(root.Position, MonetConstants.CURL_BURST_RADIUS, character)
		for _, target in targets do
			CombatHelper.dealDamage(character, target, MonetConstants.CURL_BURST_DAMAGE)
			PushHelper.applyToCharacter(target, root.CFrame.LookVector, {
				speed = MonetConstants.CURL_BURST_UP_FORCE,
				upBoost = MonetConstants.CURL_BURST_UP_FORCE,
			})
		end
		VfxHelper.spawnPulseRing(root.Position, MonetConstants.CURL_BURST_RADIUS, Color3.fromRGB(255, 35, 55), 0.5)
		VfxHelper.spawnBurstSparks(root.Position, Color3.fromRGB(255, 50, 70), 16)
	end

	finishAbility(character, entry.id, entry.cooldown)
end

-- Pain Lash (Penance R)

function MonetAbilityService.painLash(player: Player, direction: Vector3)
	local character = player.Character
	if not character or CharacterService.getForm(character) ~= "Penance" then
		return
	end
	local entry = getAbilityDef("Penance", "R")
	if not entry or entry.id ~= "pain_lash" or not canStartAbility(character, entry.id, entry.energyCost) then
		return
	end

	AbilityCooldownHelper.setActive(character, entry.id, true)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		finishAbility(character, entry.id, entry.cooldown)
		return
	end

	local flatDir = MovementHelper.flattenDirection(direction)
	local target = CombatHelper.raycastCharacter(root.Position, flatDir, MonetConstants.PAIN_LASH_RANGE, character)
	if target then
		CombatHelper.dealDamage(character, target, MonetConstants.PAIN_LASH_DAMAGE)
		local targetRoot = target:FindFirstChild("HumanoidRootPart") :: BasePart?
		if targetRoot then
			local pullDir = (root.Position - targetRoot.Position)
			if pullDir.Magnitude > 1 then
				PushHelper.applyToCharacter(target, pullDir, { speed = MonetConstants.PAIN_LASH_PULL, upBoost = 8 })
			end
			VfxHelper.spawnBeamLine(targetRoot.Position, root.Position, Color3.fromRGB(255, 50, 70), 0.4)
			StatusEffectHelper.apply(target, "pain_lash_slow", "Pain Lash", "Claw chain slow", MonetConstants.PAIN_LASH_SLOW_DURATION)
			local th = CombatHelper.getHumanoid(target)
			if th then
				th.WalkSpeed = math.max(6, th.WalkSpeed * 0.45)
				task.delay(MonetConstants.PAIN_LASH_SLOW_DURATION, function()
					if th.Parent and th.Health > 0 then
						th.WalkSpeed = 16
					end
					StatusEffectHelper.clear(target, "pain_lash_slow")
				end)
			end
		end
	end

	VfxHelper.pulseAbility(character, entry.id)
	finishAbility(character, entry.id, entry.cooldown)
end

function MonetAbilityService.startAstralDominion(player: Player)
	local character = player.Character
	if not character or CharacterService.getForm(character) ~= "Monet" or isFlying(character) then
		return
	end
	local entry = CharacterRegistry.getAbilityById("monet_st_croix", "astral_dominion")
	if not entry or not canStartAbility(character, entry.id, entry.energyCost) then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	AbilityCooldownHelper.setActive(character, entry.id, true)
	character:SetAttribute(MonetConstants.ASTRAL_ACTIVE_ATTRIBUTE, true)

	local victims: { OrbitVictim } = {}
	for _, target in CombatHelper.overlapCharacters(root.Position, MonetConstants.ASTRAL_RADIUS, character) do
		table.insert(victims, {
			target = target,
			angle = math.random() * math.pi * 2,
			radius = MonetConstants.ASTRAL_RADIUS * (0.55 + math.random() * 0.35),
		})
		local th = CombatHelper.getHumanoid(target)
		if th then
			th.PlatformStand = true
		end
	end

	astralByPlayer[player] = {
		player = player,
		character = character,
		root = root,
		entry = entry,
		victims = victims,
	}
	VfxHelper.spawnPulseRing(root.Position, MonetConstants.ASTRAL_RADIUS, VfxHelper.psychicColor(), 0.5)
end

function MonetAbilityService.endAstralDominion(player: Player)
	local state = astralByPlayer[player]
	if not state then
		return
	end
	astralByPlayer[player] = nil

	local character = state.character
	character:SetAttribute(MonetConstants.ASTRAL_ACTIVE_ATTRIBUTE, nil)

	for _, victim in state.victims do
		if victim.target.Parent then
			local th = CombatHelper.getHumanoid(victim.target)
			if th then
				th.PlatformStand = false
				th:ChangeState(Enum.HumanoidStateType.Freefall)
			end
			local vr = victim.target:FindFirstChild("HumanoidRootPart") :: BasePart?
			if vr and state.root.Parent then
				local pushDir = (vr.Position - state.root.Position)
				if pushDir.Magnitude > 0.5 then
					PushHelper.applyToCharacter(victim.target, pushDir, {
						speed = MonetConstants.ASTRAL_PUSH_FORCE,
						upBoost = MonetConstants.ASTRAL_PUSH_UP,
					})
				end
			end
		end
	end

	VfxHelper.spawnBurstSparks(state.root.Position, VfxHelper.psychicColor(), 18)
	finishAbility(character, state.entry.id, state.entry.cooldown)
end

function MonetAbilityService.startCrimsonCataclysm(player: Player)
	local character = player.Character
	if not character or CharacterService.getForm(character) ~= "Penance" then
		return
	end
	local entry = CharacterRegistry.getAbilityById("monet_st_croix", "crimson_cataclysm")
	if not entry or not canStartAbility(character, entry.id, entry.energyCost) then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	AbilityCooldownHelper.setActive(character, entry.id, true)
	character:SetAttribute(MonetConstants.CATACLYSM_ACTIVE_ATTRIBUTE, true)

	cataclysmByPlayer[player] = {
		player = player,
		character = character,
		root = root,
		entry = entry,
	}
	VfxHelper.spawnPulseRing(root.Position, MonetConstants.CATACLYSM_RADIUS, Color3.fromRGB(255, 40, 55), 0.5)
end

function MonetAbilityService.endCrimsonCataclysm(player: Player)
	local state = cataclysmByPlayer[player]
	if not state then
		return
	end
	cataclysmByPlayer[player] = nil

	local character = state.character
	character:SetAttribute(MonetConstants.CATACLYSM_ACTIVE_ATTRIBUTE, nil)

	local root = state.root
	if root.Parent then
		local targets = CombatHelper.overlapCharacters(root.Position, MonetConstants.CATACLYSM_RADIUS, character)
		for _, target in targets do
			CombatHelper.dealDamage(character, target, MonetConstants.CATACLYSM_BURST_DAMAGE)
			local tr = target:FindFirstChild("HumanoidRootPart") :: BasePart?
			if tr then
				local pushDir = tr.Position - root.Position
				if pushDir.Magnitude > 0.5 then
					PushHelper.applyToCharacter(target, pushDir, {
						speed = MonetConstants.CATACLYSM_PUSH_FORCE,
						upBoost = 50,
					})
				end
			end
		end
		VfxHelper.spawnPulseRing(root.Position, MonetConstants.CATACLYSM_RADIUS * 1.2, Color3.fromRGB(255, 30, 45), 0.6)
		VfxHelper.spawnBurstSparks(root.Position, Color3.fromRGB(255, 50, 65), 22)
	end

	finishAbility(character, state.entry.id, state.entry.cooldown)
end

function MonetAbilityService.update(dt: number)
	for character, dash in dashByCharacter do
		dash.elapsed += dt
		if not dash.root.Parent or dash.elapsed >= dash.duration then
			ConstraintHelper.destroyMover(dash.mover)
			ConstraintHelper.unlockHumanoid(dash.humanoid)
			finishAbility(character, dash.abilityId, dash.cooldown)
			dashByCharacter[character] = nil
			continue
		end

		dash.mover.linearVelocity.VectorVelocity = dash.direction * dash.speed
		if dash.mover.alignOrientation then
			local cf = CFrame.new(dash.root.Position, dash.root.Position + dash.direction)
			dash.mover.alignOrientation.CFrame = cf
		end

		if dash.elapsed - dash.lastTrail >= MonetConstants.RUSH_TRAIL_TICK then
			dash.lastTrail = dash.elapsed
			VfxHelper.spawnTrail(dash.root, Color3.fromRGB(255, 70, 80), 0.25)
		end

		local targets = CombatHelper.overlapCharacters(dash.root.Position, MonetConstants.RUSH_HIT_RADIUS, character)
		for _, target in targets do
			if not dash.hitTargets[target] then
				dash.hitTargets[target] = true
				CombatHelper.dealDamage(character, target, MonetConstants.RUSH_DAMAGE)
				VfxHelper.spawnBurstSparks(
					(target:FindFirstChild("HumanoidRootPart") :: BasePart?).Position or dash.root.Position,
					Color3.fromRGB(255, 90, 90),
					6
				)
			end
		end
	end

	for player, astral in astralByPlayer do
		local character = astral.character
		if not character.Parent or not astral.root.Parent then
			MonetAbilityService.endAstralDominion(player)
			continue
		end

		local energy = character:GetAttribute(MonetConstants.ENERGY_ATTRIBUTE)
		if type(energy) ~= "number" or energy <= 0 then
			MonetAbilityService.endAstralDominion(player)
			continue
		end
		character:SetAttribute(MonetConstants.ENERGY_ATTRIBUTE, math.max(0, energy - MonetConstants.ASTRAL_ENERGY_PER_SEC * dt))

		for _, victim in astral.victims do
			if victim.target.Parent then
				victim.angle += MonetConstants.ASTRAL_CAROUSEL_SPEED * dt
				local offset = Vector3.new(math.cos(victim.angle) * victim.radius, 3, math.sin(victim.angle) * victim.radius)
				local targetPos = astral.root.Position + offset
				local vr = victim.target:FindFirstChild("HumanoidRootPart") :: BasePart?
				if vr then
					vr.CFrame = CFrame.new(targetPos)
				end
				CombatHelper.dealDamage(character, victim.target, MonetConstants.ASTRAL_TICK_DAMAGE * dt)
			end
		end
		if math.random() < dt * 3 then
			VfxHelper.spawnPulseRing(astral.root.Position, MonetConstants.ASTRAL_RADIUS * 0.6, VfxHelper.psychicColor(), 0.15)
		end
	end

	for player, cataclysm in cataclysmByPlayer do
		local character = cataclysm.character
		if not character.Parent or not cataclysm.root.Parent then
			MonetAbilityService.endCrimsonCataclysm(player)
			continue
		end

		local energy = character:GetAttribute(MonetConstants.ENERGY_ATTRIBUTE)
		if type(energy) ~= "number" or energy <= 0 then
			MonetAbilityService.endCrimsonCataclysm(player)
			continue
		end
		character:SetAttribute(MonetConstants.ENERGY_ATTRIBUTE, math.max(0, energy - MonetConstants.CATACLYSM_ENERGY_PER_SEC * dt))

		local victims = CombatHelper.overlapCharacters(cataclysm.root.Position, MonetConstants.CATACLYSM_RADIUS, character)
		for _, victim in victims do
			CombatHelper.dealDamage(character, victim, MonetConstants.CATACLYSM_TICK_DAMAGE * dt)
			local vr = victim:FindFirstChild("HumanoidRootPart") :: BasePart?
			if vr then
				local pull = (cataclysm.root.Position - vr.Position)
				if pull.Magnitude > 1 then
					PushHelper.applyToCharacter(victim, pull, { speed = MonetConstants.CATACLYSM_PULL_FORCE * dt * 3, upBoost = 2 })
				end
			end
		end
	end

	for character, curl in activeCurls do
		local move = curlMoveVectors[character] or Vector3.zero
		local inputDir = if move.Magnitude > 0.05 then MovementHelper.flattenDirection(move) else Vector3.zero
		local vel = MovementHelper.buildMomentum(
			curl.root.AssemblyLinearVelocity,
			inputDir,
			MonetConstants.CURL_ACCELERATION,
			MonetConstants.CURL_MAX_SPEED,
			MonetConstants.CURL_DRAG,
			dt
		)
		curl.mover.linearVelocity.VectorVelocity = vel
		if curl.mover.vectorForce then
			curl.mover.vectorForce.Force = Vector3.new(0, curl.root.AssemblyMass * workspace.Gravity, 0)
		end

		curl.lastContact += dt
		if curl.lastContact >= MonetConstants.CURL_CONTACT_INTERVAL then
			curl.lastContact = 0
			local victims = CombatHelper.overlapCharacters(curl.root.Position, MonetConstants.CURL_BALL_SIZE * 0.55, character)
			for _, victim in victims do
				CombatHelper.dealDamage(character, victim, MonetConstants.CURL_CONTACT_DAMAGE)
			end
			if vel.Magnitude > 20 then
				VfxHelper.spawnTrail(curl.root, Color3.fromRGB(255, 45, 65), 0.15)
			end
		end
	end
end

function MonetAbilityService.handleAbilityRequest(player: Player, payload: any)
	if type(payload) ~= "table" or type(payload.action) ~= "string" then
		return
	end

	local action = payload.action
	local direction = if typeof(payload.direction) == "Vector3" then payload.direction else Vector3.new(0, 0, -1)
	local moveVector = if typeof(payload.moveVector) == "Vector3" then payload.moveVector else Vector3.zero
	local character = player.Character

	if action == "Q" then
		if not character then
			return
		end
		if CharacterService.getForm(character) == "Monet" then
			MonetFlightService.toggleFlight(player)
		elseif not isFlying(character) then
			MonetAbilityService.bloodRush(player, direction)
		end
	elseif action == "F_down" then
		if not character or isFlying(character) then
			return
		end
		if CharacterService.getForm(character) == "Monet" then
			MonetAbilityService.startPsychicCharge(player, direction)
		else
			MonetAbilityService.startDiamondCurl(player, moveVector)
		end
	elseif action == "F_move" then
		if not isFlying(character) then
			MonetAbilityService.updateCurlMovement(player, moveVector)
		end
	elseif action == "F_up" then
		if not character or isFlying(character) then
			return
		end
		if CharacterService.getForm(character) == "Monet" then
			MonetAbilityService.releasePsychicCharge(player, direction)
		else
			MonetAbilityService.releaseDiamondCurl(player)
		end
	elseif action == "R" then
		if not character then
			return
		end
		if CharacterService.getForm(character) == "Monet" then
			MonetAbilityService.mindShatter(player, direction)
		elseif not isFlying(character) then
			MonetAbilityService.painLash(player, direction)
		end
	elseif action == "T_down" then
		if not character or isFlying(character) then
			return
		end
		if CharacterService.getForm(character) == "Monet" then
			MonetAbilityService.startAstralDominion(player)
		else
			MonetAbilityService.startCrimsonCataclysm(player)
		end
	elseif action == "T_up" then
		if not character then
			return
		end
		if CharacterService.getForm(character) == "Monet" then
			MonetAbilityService.endAstralDominion(player)
		else
			MonetAbilityService.endCrimsonCataclysm(player)
		end
	elseif action == "E" then
		if character then
			MonetFlightService.endFlight(player, false)
			MonetAbilityService.endAstralDominion(player)
			MonetAbilityService.endCrimsonCataclysm(player)
			CharacterService.toggleForm(character)
		end
	end
end

function MonetAbilityService.init()
	require(ReplicatedStorage.Shared.Remotes).getEvent("UseAbility").OnServerEvent:Connect(function(player, payload)
		MonetAbilityService.handleAbilityRequest(player, payload)
	end)
end

return MonetAbilityService
