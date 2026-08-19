--!strict

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local AbilityCooldownHelper = require(ReplicatedStorage.Shared.AbilityCooldownHelper)
local CharacterRegistry = require(ReplicatedStorage.Shared.CharacterRegistry)
local CombatHelper = require(ReplicatedStorage.Shared.CombatHelper)
local GameConstants = require(ReplicatedStorage.Shared.GameConstants)
local InteractableHelper = require(ReplicatedStorage.Shared.InteractableHelper)
local ProjectileHelper = require(ReplicatedStorage.Shared.ProjectileHelper)
local PushHelper = require(ReplicatedStorage.Shared.PushHelper)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RagdollStatus = require(ReplicatedStorage.Shared.RagdollStatus)
local ScreenFeelHelper = require(ReplicatedStorage.Shared.ScreenFeelHelper)
local VfxHelper = require(ReplicatedStorage.Shared.VfxHelper)
local CharacterService = require(script.Parent.CharacterService)
local HandParticleHelper = require(script.Parent.HandParticleHelper)
local HexFlightService = require(script.Parent.HexFlightService)
local NameplateService = require(script.Parent.NameplateService)
local TelekinesisService = require(script.Parent.TelekinesisService)
local LokiService = require(script.Parent.LokiService)
local BeamClashService = require(script.Parent.BeamClashService)

local ScarletWitchService = {}

type BeamState = {
	character: Model,
	startHost: BasePart,
	handWeld: Weld?,
	tipHost: BasePart,
	startAtt: Attachment,
	endAtt: Attachment,
	beam: Beam?,
	victim: Model,
	victimRoot: BasePart,
	startedAt: number,
	smoothedTip: Vector3,
	lastHit: number,
	launched: boolean,
	reached: boolean,
	abilityStartedAt: number?,
	walk: number,
	jumpPower: number?,
	jumpHeight: number?,
	casterAutoRotate: boolean,
	victimWalk: number,
	victimJump: number?,
	victimAutoRotate: boolean,
	casterFace: AlignOrientation?,
	casterFaceAtt: Attachment?,
	victimFace: AlignOrientation?,
	victimFaceAtt: Attachment?,
	animTrack: AnimationTrack?,
	victimAnimTrack: AnimationTrack?,
}

type ShieldState = {
	character: Model,
	root: BasePart,
	visual: Instance?,
	activePartials: { BasePart },
	partialToken: number,
	hp: number,
	maxHp: number,
	billboard: BillboardGui,
	hpLabel: TextLabel,
	hpFill: Frame,
	walk: number,
	jumpPower: number?,
	jumpHeight: number?,
	autoRotate: boolean,
	animTrack: AnimationTrack?,
}

type RegenState = {
	character: Model,
	particles: { Instance },
}

type AbsorbBeamFx = {
	startAtt: Attachment,
	endAtt: Attachment,
	beam: Beam?,
	travelHost: BasePart?,
	destPart: BasePart,
	startWorld: Vector3,
	curve0Max: number,
	curve1Max: number,
	curve0Sign: number,
	curve1Sign: number,
	freq0: number,
	freq1: number,
	phase0: number,
	phase1: number,
	wander0: number,
	wander1: number,
	riseDelay: number,
	riseSpan: number,
}

type AbsorbState = {
	character: Model,
	target: Model,
	targetHum: Humanoid,
	casterHum: Humanoid,
	casterRoot: BasePart,
	targetRoot: BasePart,
	beams: { AbsorbBeamFx },
	startHealth: number,
	startedAt: number,
	reachTime: number,
	beamsReached: boolean,
	drainStartedAt: number?,
	duration: number,
	liftAlign: AlignPosition?,
	liftAtt: Attachment?,
	liftStartY: number,
	liftBaseX: number,
	liftBaseZ: number,
	casterFace: AlignOrientation?,
	targetFace: AlignOrientation?,
	casterFaceAtt: Attachment?,
	targetFaceAtt: Attachment?,
	prevTargetWalk: number,
	prevTargetJump: number,
	prevTargetAutoRotate: boolean,
	prevCasterAutoRotate: boolean,
}

type RuneKind = "fire" | "lightning" | "water"

type RuneVictimState = {
	model: Model,
	kind: RuneKind,
	fx: { Instance },
	bubble: Instance?,
	liftAlign: AlignPosition?,
	liftAtt: Attachment?,
	spinAlign: AlignOrientation?,
	walk: number,
	jump: number?,
	tickAcc: number,
	nextLightning: number,
	nextWander: number,
	spinRates: Vector3?,
	spinGoal: Vector3?,
	nextSpinShift: number?,
	spinCFrame: CFrame?,
	wanderGoal: Vector3?,
	bubblePos: Vector3?,
	animTrack: AnimationTrack?,
	autoRotate: boolean?,
	swirlSign: number?,
	transparencySnaps: { any }?,
}

type RuneFieldState = {
	character: Model,
	zone: Instance?,
	victims: { RuneVictimState },
	endsAt: number,
	dest: Vector3,
	walk: number,
	jumpPower: number?,
	jumpHeight: number?,
	casterAutoRotate: boolean,
	faceAlign: AlignOrientation?,
	faceAtt: Attachment?,
}

type ProbBeamState = {
	character: Model,
	victim: Model,
	hand: BasePart,
	casterRoot: BasePart,
	startHost: BasePart,
	tipHost: BasePart,
	startAtt: Attachment,
	endAtt: Attachment,
	beam: Beam?,
	beams: { Beam },
	startPos: Vector3,
	endPos: Vector3,
	startedAt: number,
	launched: boolean,
	channelStartedAt: number?,
	reached: boolean,
	finishing: boolean,
	damageAcc: number,
	casterAutoRotate: boolean,
	victimAutoRotate: boolean,
	victimWalk: number,
	victimJumpPower: number,
	victimJumpHeight: number,
	victimUseJumpPower: boolean,
	handWeld: Weld?,
	torsoWeld: Weld?,
	aimPart: BasePart?,
	walk: number,
	jumpPower: number?,
	jumpHeight: number?,
	useJumpPower: boolean,
	victimAlive: boolean,
	lastEndPos: Vector3?,
}

type ProbObjectState = {
	victim: Model,
	prop: Instance,
	snaps: any,
	look: Vector3,
	endsAt: number,
	displayType: Enum.HumanoidDisplayDistanceType?,
	walk: number?,
	jumpPower: number?,
	jumpHeight: number?,
	useJumpPower: boolean?,
	autoRotate: boolean?,
	jumpingEnabled: boolean?,
}

local beamByPlayer: { [Player]: BeamState } = {}
local shieldByPlayer: { [Player]: ShieldState } = {}
local regenByPlayer: { [Player]: RegenState } = {}
local absorbByPlayer: { [Player]: AbsorbState } = {}
local runeFieldByPlayer: { [Player]: RuneFieldState } = {}
local probBeamByPlayer: { [Player]: ProbBeamState } = {}
local objectHexByVictim: { [Model]: ProbObjectState } = {}

type ChaosFallState = {
	airborne: boolean,
	peakHeightAboveGround: number,
	wasFlying: boolean,
	impacted: boolean,
	landAnimPlayed: boolean,
}

local chaosFallByPlayer: { [Player]: ChaosFallState } = {}
local hexDashUntil: { [Player]: number } = {}
local hexDashCdUntil: { [Player]: number } = {}

local function getChaosFallState(player: Player): ChaosFallState
	local state = chaosFallByPlayer[player]
	if not state then
		state = {
			airborne = false,
			peakHeightAboveGround = 0,
			wasFlying = false,
			impacted = false,
			landAnimPlayed = false,
		}
		chaosFallByPlayer[player] = state
	end
	return state
end

local function playCharacterAnim(character: Model, assetId: string, priority: Enum.AnimationPriority?): AnimationTrack?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = assetId
	local ok, track = pcall(function()
		return (animator :: Animator):LoadAnimation(anim)
	end)
	if not ok or not track then
		return nil
	end
	track.Priority = priority or Enum.AnimationPriority.Action
	track:Play(0.08, 1, 1)
	return track
end

local function clearChaosFall(player: Player)
	chaosFallByPlayer[player] = nil
end

local function heightAboveGround(root: BasePart, character: Model): (number, Vector3?)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local origin = root.Position
	local hit = workspace:Raycast(origin, Vector3.new(0, -500, 0), params)
	if hit then
		return math.max(0, origin.Y - hit.Position.Y), hit.Position
	end
	return 500, nil
end

local function triggerChaosImpact(character: Model, landPos: Vector3)
	local radius = GameConstants.CHAOS_IMPACT_RADIUS
	VfxHelper.spawnScarletLandingImpact(landPos, radius)

	for _, victim in CombatHelper.overlapCharacters(landPos, radius, character) do
		if victim == character then
			continue
		end
		if victim:GetAttribute("LokiUltClone") == true or victim:GetAttribute("LokiDecoy") == true then
			continue
		end
		CombatHelper.dealDamage(character, victim, GameConstants.CHAOS_IMPACT_DAMAGE, landPos, "projectile")
		RagdollStatus.applyTimed(victim, GameConstants.CHAOS_IMPACT_RAGDOLL)
		local vRoot = victim:FindFirstChild("HumanoidRootPart") :: BasePart?
		local away = if vRoot then (vRoot.Position - landPos) else Vector3.new(0, 0, -1)
		if away.Magnitude < 0.05 then
			away = Vector3.new(0, 0, -1)
		end
		PushHelper.applyToCharacter(victim, away, {
			speed = GameConstants.CHAOS_IMPACT_PUSH_SPEED,
			upBoost = GameConstants.CHAOS_IMPACT_PUSH_UP,
		})
	end
end

local function updateChaosImpact(player: Player, character: Model, dt: number)
	-- Scarlet Witch now uses the standard high-fall landing for everyone; no special chaos-impact pose/AOE.
	clearChaosFall(player)
	return
	if character:GetAttribute(GameConstants.HERO_ATTRIBUTE) ~= "scarlet_witch" then
		clearChaosFall(player)
		return
	end
	if character:GetAttribute(GameConstants.RAGDOLLED_ATTRIBUTE) == true then
		clearChaosFall(player)
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		clearChaosFall(player)
		return
	end

	local state = getChaosFallState(player)
	local flying = character:GetAttribute(GameConstants.IS_FLYING_ATTRIBUTE) == true
	local height, groundPos = heightAboveGround(root, character)
	local vel = root.AssemblyLinearVelocity
	local falling = vel.Y < -2
	local humState = humanoid:GetState()
	local inAirState = humState == Enum.HumanoidStateType.Freefall
		or humState == Enum.HumanoidStateType.Jumping
		or humState == Enum.HumanoidStateType.FallingDown
	-- True land only (not "near ground while still falling")
	local trulyLanded = humState == Enum.HumanoidStateType.Landed
		or (
			height < 2.8
			and vel.Y > -18
			and (
				humanoid.FloorMaterial ~= Enum.Material.Air
				or humState == Enum.HumanoidStateType.Running
				or humState == Enum.HumanoidStateType.RunningNoPhysics
				or humState == Enum.HumanoidStateType.GettingUp
			)
		)
		or (state.airborne and height <= 2.2 and vel.Y > -16)

	if flying then
		state.wasFlying = true
		state.airborne = true
		state.impacted = false
		state.landAnimPlayed = false
		state.peakHeightAboveGround = math.max(state.peakHeightAboveGround, height)
		return
	end

	if state.wasFlying then
		state.wasFlying = false
		state.airborne = true
		state.impacted = false
		state.landAnimPlayed = false
		state.peakHeightAboveGround = math.max(state.peakHeightAboveGround, height)
	end

	if inAirState or (falling and height > 3) then
		-- Allow a new slam only after leaving the ground again
		if state.impacted and height > 5 then
			state.impacted = false
			state.landAnimPlayed = false
		end
		state.airborne = true
		state.peakHeightAboveGround = math.max(state.peakHeightAboveGround, height)
	end

	-- Pre-land pose: play while still airborne, very close to ground (qualifying fall only)
	if
		state.airborne
		and not state.impacted
		and not state.landAnimPlayed
		and falling
		and height <= GameConstants.CHAOS_IMPACT_LAND_ANIM_HEIGHT
		and state.peakHeightAboveGround >= GameConstants.CHAOS_IMPACT_MIN_FALL
		and not AbilityCooldownHelper.isOnCooldown(character, "chaos_impact")
	then
		state.landAnimPlayed = true
		playCharacterAnim(character, GameConstants.CHAOS_IMPACT_LAND_ANIM, Enum.AnimationPriority.Action4)
	end

	-- Landed after qualifying fall — hero pose only (no AoE slam damage).
	if state.airborne and not state.impacted and trulyLanded then
		state.impacted = true
		state.airborne = false
		state.peakHeightAboveGround = 0
		return
	end

	if trulyLanded and not falling then
		state.airborne = false
		state.peakHeightAboveGround = 0
		-- Keep impacted=true while grounded so Landedâ†’Running doesn't double-fire
		return
	end

	-- Strong, visible deceleration in the last ~30 studs (air only â€” never trigger impact here)
	if
		state.airborne
		and falling
		and height <= GameConstants.CHAOS_IMPACT_DECEL_HEIGHT
		and state.peakHeightAboveGround >= GameConstants.CHAOS_IMPACT_MIN_FALL
	then
		local t = math.clamp(height / GameConstants.CHAOS_IMPACT_DECEL_HEIGHT, 0, 1)
		local ease = t * t
		local maxDown = GameConstants.CHAOS_IMPACT_MAX_DOWN_NEAR_GROUND
			+ (GameConstants.CHAOS_IMPACT_MAX_DOWN_AT_START - GameConstants.CHAOS_IMPACT_MAX_DOWN_NEAR_GROUND) * ease
		local softTarget = -maxDown * (0.5 + 0.5 * t)
		local brakeSpeed = 10 + 22 * (1 - t)
		local blend = math.clamp(dt * brakeSpeed, 0, 1)
		local newY = vel.Y + (softTarget - vel.Y) * blend
		if newY < -maxDown then
			newY = -maxDown
		end
		if newY > vel.Y then
			root.AssemblyLinearVelocity = Vector3.new(vel.X, newY, vel.Z)
		elseif vel.Y < -maxDown then
			root.AssemblyLinearVelocity = Vector3.new(vel.X, -maxDown, vel.Z)
		end
	end
end

local function finishAbility(character: Model, abilityId: string, cooldown: number)
	AbilityCooldownHelper.setActive(character, abilityId, false)
	AbilityCooldownHelper.applyAfterUse(character, abilityId, cooldown)
end

local function trySpendEnergy(character: Model, amount: number): boolean
	return CharacterService.spendEnergy(character, amount)
end

local function refundEnergy(character: Model, amount: number)
	local energy = character:GetAttribute(GameConstants.ENERGY_ATTRIBUTE)
	if type(energy) == "number" then
		character:SetAttribute(
			GameConstants.ENERGY_ATTRIBUTE,
			math.min((character:GetAttribute(GameConstants.MAX_ENERGY_ATTRIBUTE) :: number?) or 100, energy + amount)
		)
	end
end

local SW_CONTROL_ACTIVE_IDS = {
	"hex_beam",
	"hex_shield",
	"hex_flight",
	"probability_hex",
	"hex_displacement",
	"rune_entrapment",
}

local function enterControlLock(player: Player, character: Model)
	if character:GetAttribute(GameConstants.SW_CONTROL_LOCK_ATTRIBUTE) == true then
		return
	end
	local untilTime = AbilityCooldownHelper.getNow() + GameConstants.SW_CONTROL_LOCK_TIME
	character:SetAttribute(GameConstants.SW_CONTROL_ATTRIBUTE, GameConstants.SW_CONTROL_MAX)
	character:SetAttribute(GameConstants.SW_CONTROL_LOCK_ATTRIBUTE, true)
	character:SetAttribute(GameConstants.SW_CONTROL_LOCK_UNTIL_ATTRIBUTE, untilTime)
end

local function spendControl(player: Player, character: Model, amount: number)
	if character:GetAttribute(GameConstants.SW_CONTROL_LOCK_ATTRIBUTE) == true then
		return
	end
	local current = character:GetAttribute(GameConstants.SW_CONTROL_ATTRIBUTE)
	if type(current) ~= "number" then
		current = 0
	end
	current = math.min(GameConstants.SW_CONTROL_MAX, current + amount)
	character:SetAttribute(GameConstants.SW_CONTROL_ATTRIBUTE, current)
	if current >= GameConstants.SW_CONTROL_MAX then
		enterControlLock(player, character)
	end
end

local function updateControl(player: Player, character: Model, dt: number)
	if character:GetAttribute(GameConstants.HERO_ATTRIBUTE) ~= "scarlet_witch" then
		return
	end
	local maxC = character:GetAttribute(GameConstants.SW_CONTROL_MAX_ATTRIBUTE)
	if type(maxC) ~= "number" or maxC <= 0 then
		maxC = GameConstants.SW_CONTROL_MAX
	end
	local current = character:GetAttribute(GameConstants.SW_CONTROL_ATTRIBUTE)
	if type(current) ~= "number" then
		current = 0
	end
	if character:GetAttribute(GameConstants.SW_CONTROL_LOCK_ATTRIBUTE) == true then
		current -= GameConstants.SW_CONTROL_OVERLOAD_DECAY_PER_SEC * dt
		current = math.clamp(current, 0, maxC)
		character:SetAttribute(GameConstants.SW_CONTROL_ATTRIBUTE, current)
		local untilTime = character:GetAttribute(GameConstants.SW_CONTROL_LOCK_UNTIL_ATTRIBUTE)
		local now = AbilityCooldownHelper.getNow()
		if type(untilTime) ~= "number" or now >= untilTime then
			character:SetAttribute(GameConstants.SW_CONTROL_LOCK_ATTRIBUTE, nil)
			character:SetAttribute(GameConstants.SW_CONTROL_LOCK_UNTIL_ATTRIBUTE, nil)
		end
		return
	end
	local flying = character:GetAttribute(GameConstants.IS_FLYING_ATTRIBUTE) == true
	local using = AbilityCooldownHelper.isAnyActive(character, SW_CONTROL_ACTIVE_IDS)
	if flying then
		current += GameConstants.SW_CONTROL_ACTIVE_PER_SEC * dt
	end
	if using then
		current += GameConstants.SW_CONTROL_ACTIVE_PER_SEC * dt
	end
	if not flying and not using then
		current -= GameConstants.SW_CONTROL_REGEN_PER_SEC * dt
	end
	current = math.clamp(current, 0, maxC)
	character:SetAttribute(GameConstants.SW_CONTROL_ATTRIBUTE, current)
	if current >= maxC then
		enterControlLock(player, character)
	end
end

local function canUse(character: Model, abilityId: string, energyCost: number): boolean
	if character:GetAttribute(GameConstants.HERO_ATTRIBUTE) ~= "scarlet_witch" then
		return false
	end
	if CombatHelper.arePowersDisabled(character) then
		return false
	end
	if character:GetAttribute(GameConstants.IS_FLYING_ATTRIBUTE) == true
		and abilityId ~= "hex_bolt"
		and abilityId ~= "hex_flight"
	then
		return false
	end
	if character:GetAttribute(GameConstants.SHIELD_ACTIVE_ATTRIBUTE) == true and abilityId ~= "hex_shield" then
		return false
	end
	if AbilityCooldownHelper.isActive(character, "regeneration") and abilityId ~= "regeneration" then
		return false
	end
	if character:GetAttribute(GameConstants.BUSY_ATTRIBUTE) == true then
		return false
	end
	if character:GetAttribute(GameConstants.TK_ACTIVE_ATTRIBUTE) == true and abilityId ~= "telekinesis" then
		return false
	end
	if AbilityCooldownHelper.isOnCooldown(character, abilityId) then
		return false
	end
	if AbilityCooldownHelper.isActive(character, abilityId) then
		return false
	end
	if AbilityCooldownHelper.hasBlockingActive(character, abilityId) then
		return false
	end
	if not trySpendEnergy(character, energyCost) then
		return false
	end
	local owner = Players:GetPlayerFromCharacter(character)
	local freeControlCast = abilityId == "telekinesis" or abilityId == "hex_bolt"
	if owner and not freeControlCast then
		spendControl(owner, character, GameConstants.SW_CONTROL_CAST_COST)
	end
	return true
end

local function fireCameraShake(player: Player, intensity: number?, duration: number?, fovScale: number?, vignetteScale: number?)
	Remotes.getEvent("CameraShake"):FireClient(player, {
		intensity = intensity or 0.4,
		duration = duration or 0.32,
		fovScale = fovScale,
		vignetteScale = vignetteScale,
	})
end

local function castTemplate(player: Player, abilityId: string)
	local character = player.Character
	if not character then
		return
	end
	local entry = CharacterRegistry.getAbilityById("scarlet_witch", abilityId)
	if not entry or not canUse(character, entry.id, entry.energyCost) then
		return
	end
	AbilityCooldownHelper.setActive(character, entry.id, true)
	HandParticleHelper.pulse(character, 0.45)
	fireCameraShake(player, 0.4, 0.32, 0.28, 0.45)
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		VfxHelper.castHandFlash(root.Position, VfxHelper.chaosColor())
	end
	task.delay(0.4, function()
		if character.Parent then
			finishAbility(character, entry.id, entry.cooldown)
		end
	end)
end

local function getRootPart(model: Model): BasePart?
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	local torso = model:FindFirstChild("Torso") or model:FindFirstChild("UpperTorso")
	if torso and torso:IsA("BasePart") then
		return torso
	end
	if model.PrimaryPart then
		return model.PrimaryPart
	end
	return nil
end

--[[ Aim point for Probability Hex beam tip (chest / upper torso, not HRP). ]]
local function getProbHexAimPart(model: Model): BasePart?
	local upper = model:FindFirstChild("UpperTorso")
	if upper and upper:IsA("BasePart") then
		return upper
	end
	local torso = model:FindFirstChild("Torso")
	if torso and torso:IsA("BasePart") then
		return torso
	end
	return getRootPart(model)
end

local function setWorldPosKeepRot(inst: Instance, pos: Vector3)
	if inst:IsA("Model") then
		local model = inst :: Model
		model:PivotTo(CFrame.new(pos) * model:GetPivot().Rotation)
	elseif inst:IsA("BasePart") then
		local part = inst :: BasePart
		part.CFrame = CFrame.new(pos) * part.CFrame.Rotation
	end
end

local function attachRuneHeadFx(victim: Model, assetName: string): Instance?
	local head = victim:FindFirstChild("Head")
	if not (head and head:IsA("BasePart")) then
		return nil
	end
	local template = VfxHelper.getScarletAsset("RuneDisplacement", assetName)
	if not template then
		return nil
	end
	local clone = VfxHelper.attachFxToBodyPart(template, head, "SwRuneHeadFx_")
	if not clone then
		return nil
	end
	VfxHelper.muteSounds(clone)
	VfxHelper.setParticlesEnabled(clone, true)
	VfxHelper.emitAllParticles(clone, 10)
	return clone
end

local function placeBubbleAtHrp(victim: Model): Instance?
	local hrp = getRootPart(victim)
	local template = VfxHelper.getScarletAsset("RuneDisplacement", "BubblePart")
	if not hrp or not template then
		return nil
	end
	local clone = VfxHelper.attachFxToBodyPart(template, hrp, "SwRuneBubble_")
	if not clone then
		return nil
	end
	VfxHelper.muteSounds(clone)
	VfxHelper.setParticlesEnabled(clone, true)
	VfxHelper.emitAllParticles(clone, 8)
	return clone
end

local function clearRuneVictim(victim: RuneVictimState)
	local hum = CombatHelper.getHumanoid(victim.model)
	if hum and hum.Parent then
		hum.WalkSpeed = victim.walk
		if victim.jump ~= nil then
			hum.JumpPower = victim.jump
		end
		if victim.autoRotate ~= nil then
			hum.AutoRotate = victim.autoRotate
		end
	end
	if victim.animTrack then
		victim.animTrack:Stop(0.2)
		victim.animTrack:Destroy()
		victim.animTrack = nil
	end
	if victim.liftAlign then
		victim.liftAlign:Destroy()
	end
	if victim.spinAlign then
		victim.spinAlign:Destroy()
	end
	if victim.liftAtt then
		victim.liftAtt:Destroy()
	end
	for _, fx in victim.fx do
		if fx.Parent then
			VfxHelper.retireFxSmooth(fx, 0.4, 2.2)
		end
	end
	if victim.bubble and victim.bubble.Parent then
		VfxHelper.retireFxSmooth(victim.bubble, 0.45, 2.4)
	end
	VfxHelper.restorePartTransparencies(victim.transparencySnaps)
	ScreenFeelHelper.clear(victim.model)
	if victim.kind == "fire" or victim.kind == "lightning" then
		RagdollStatus.clear(victim.model)
	end
	local root = getRootPart(victim.model)
	if root and root.Parent then
		local plr = Players:GetPlayerFromCharacter(victim.model)
		pcall(function()
			if plr then
				root:SetNetworkOwner(plr)
			else
				root:SetNetworkOwnershipAuto()
			end
		end)
	end
end

local function clearRuneCasterFace(state: RuneFieldState)
	if state.faceAlign then
		state.faceAlign:Destroy()
		state.faceAlign = nil
	end
	if state.faceAtt then
		state.faceAtt:Destroy()
		state.faceAtt = nil
	end
end

local function updateRuneCasterFace(state: RuneFieldState)
	if not state.faceAlign or not state.faceAlign.Parent then
		return
	end
	local root = state.character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local flat = Vector3.new(state.dest.X - root.Position.X, 0, state.dest.Z - root.Position.Z)
	if flat.Magnitude < 0.05 then
		return
	end
	state.faceAlign.CFrame = CFrame.lookAt(root.Position, root.Position + flat.Unit)
end

local function stopRuneDisplacement(player: Player, applyCooldown: boolean?)
	local state = runeFieldByPlayer[player]
	if not state then
		return
	end
	runeFieldByPlayer[player] = nil
	if state.zone and state.zone.Parent then
		VfxHelper.retireFxSmooth(state.zone, 0.5, GameConstants.SW_RUNE_DURATION)
	end
	for _, victim in state.victims do
		clearRuneVictim(victim)
	end
	clearRuneCasterFace(state)
	local char = state.character
	if char.Parent then
		local hum = CombatHelper.getHumanoid(char)
		if hum and hum.Parent then
			hum.WalkSpeed = state.walk
			if state.jumpPower ~= nil then
				hum.JumpPower = state.jumpPower
			end
			if state.jumpHeight ~= nil then
				hum.JumpHeight = state.jumpHeight
			end
			hum.AutoRotate = state.casterAutoRotate
			pcall(function()
				hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
			end)
		end
		if char:GetAttribute(GameConstants.BUSY_ATTRIBUTE) == true then
			char:SetAttribute(GameConstants.BUSY_ATTRIBUTE, nil)
		end
		AbilityCooldownHelper.setActive(char, "rune_entrapment", false)
		if applyCooldown then
			local entry = CharacterRegistry.getAbilityById("scarlet_witch", "rune_entrapment")
			if entry then
				AbilityCooldownHelper.applyAfterUse(char, entry.id, entry.cooldown)
			end
		end
	end
	if char then
		HandParticleHelper.endUse(char)
	end
end

local function pickRuneKind(): RuneKind
	local roll = math.random(1, 3)
	if roll == 1 then
		return "fire"
	elseif roll == 2 then
		return "lightning"
	end
	return "water"
end

local function randomWaterFloatPos(center: Vector3): Vector3
	local angle = math.random() * math.pi * 2
	local radius = math.sqrt(math.random()) * GameConstants.SW_RUNE_RADIUS
	return Vector3.new(
		center.X + math.cos(angle) * radius,
		center.Y + GameConstants.SW_RUNE_WATER_LIFT,
		center.Z + math.sin(angle) * radius
	)
end

local function waterWanderDelay(): number
	return GameConstants.SW_RUNE_WATER_WANDER_MIN
		+ math.random() * (GameConstants.SW_RUNE_WATER_WANDER_MAX - GameConstants.SW_RUNE_WATER_WANDER_MIN)
end

local function waterSpinShiftDelay(): number
	return GameConstants.SW_RUNE_WATER_SPIN_SHIFT_MIN
		+ math.random() * (GameConstants.SW_RUNE_WATER_SPIN_SHIFT_MAX - GameConstants.SW_RUNE_WATER_SPIN_SHIFT_MIN)
end

--[[ Tumble rates for every axis so bubbled victims flip and turn, not just yaw. ]]
local function randomWaterSpinRates(): Vector3
	local base = GameConstants.SW_RUNE_WATER_SPIN_SPEED
	local function rate(): number
		local sign = if math.random(1, 2) == 1 then 1 else -1
		return sign * base * (0.45 + math.random() * 0.95)
	end
	return Vector3.new(rate(), rate(), rate())
end

local function applyRuneToVictim(attacker: Model, victim: Model, kind: RuneKind, dest: Vector3): RuneVictimState?
	local hum = CombatHelper.getHumanoid(victim)
	local root = getRootPart(victim)
	if not hum or not root or hum.Health <= 0 then
		return nil
	end
	local fx: { Instance } = {}
	local bubble: Instance? = nil
	local liftAlign: AlignPosition? = nil
	local liftAtt: Attachment? = nil
	local walk = hum.WalkSpeed
	local jump: number? = if hum.UseJumpPower then hum.JumpPower else nil
	local autoRotate = hum.AutoRotate
	local transparencySnaps = VfxHelper.capturePartTransparencies(victim)
	ScreenFeelHelper.setTint(victim, VfxHelper.chaosColor(), GameConstants.SW_RUNE_DURATION)
	ScreenFeelHelper.pulseCharacter(victim, {
		intensity = 0.22,
		duration = 0.4,
		fovScale = 0.18,
		vignetteScale = 0.45,
		tint = VfxHelper.chaosColor(),
		tintDuration = 0.5,
	})

	if kind == "fire" then
		local morph = VfxHelper.getScarletAsset("RuneDisplacement", "FireMorph")
		if morph then
			for _, inst in VfxHelper.attachRuneMorphFx(victim, morph) do
				VfxHelper.muteSounds(inst)
				table.insert(fx, inst)
			end
		end
		local headFx = attachRuneHeadFx(victim, "RuneFireAttachment")
		if headFx then
			table.insert(fx, headFx)
		end
		hum.WalkSpeed = 0
		hum.JumpPower = 0
		hum.UseJumpPower = true
		hum:Move(Vector3.zero, false)
		RagdollStatus.apply(victim)
		pcall(function()
			root:SetNetworkOwner(nil)
		end)
		return {
			model = victim,
			kind = kind,
			fx = fx,
			bubble = nil,
			liftAlign = nil,
			liftAtt = nil,
			walk = walk,
			jump = jump,
			autoRotate = autoRotate,
			tickAcc = 0,
			nextLightning = 0,
			nextWander = 0,
			swirlSign = if math.random(1, 2) == 1 then 1 else -1,
			transparencySnaps = transparencySnaps,
		}
	elseif kind == "lightning" then
		local morph = VfxHelper.getScarletAsset("RuneDisplacement", "LightningMorph")
		if morph then
			for _, inst in VfxHelper.attachRuneMorphFx(victim, morph) do
				VfxHelper.muteSounds(inst)
				table.insert(fx, inst)
			end
		end
		local headFx = attachRuneHeadFx(victim, "RunesLightningAttachment")
		if headFx then
			table.insert(fx, headFx)
		end
		hum.WalkSpeed = 0
		hum.JumpPower = 0
		hum.UseJumpPower = true
		hum:Move(Vector3.zero, false)
		RagdollStatus.apply(victim)
		pcall(function()
			root:SetNetworkOwner(nil)
		end)
		return {
			model = victim,
			kind = kind,
			fx = fx,
			bubble = nil,
			liftAlign = nil,
			liftAtt = nil,
			walk = walk,
			jump = jump,
			autoRotate = autoRotate,
			tickAcc = 0,
			nextLightning = 0,
			nextWander = 0,
			swirlSign = if math.random(1, 2) == 1 then 1 else -1,
			transparencySnaps = transparencySnaps,
		}
	else
		local headFx = attachRuneHeadFx(victim, "RuneWaterAttachment")
		if headFx then
			table.insert(fx, headFx)
		end
		bubble = placeBubbleAtHrp(victim)
		liftAtt = Instance.new("Attachment")
		liftAtt.Name = "SwRuneLiftAtt"
		liftAtt.Parent = root
		liftAlign = Instance.new("AlignPosition")
		liftAlign.Name = "SwRuneLift"
		liftAlign.Mode = Enum.PositionAlignmentMode.OneAttachment
		liftAlign.Attachment0 = liftAtt
		liftAlign.ApplyAtCenterOfMass = true
		liftAlign.RigidityEnabled = false
		liftAlign.Responsiveness = GameConstants.SW_RUNE_WATER_ALIGN_RESPONSIVENESS
		liftAlign.MaxForce = 1e6
		liftAlign.MaxVelocity = GameConstants.SW_RUNE_WATER_ALIGN_MAX_VELOCITY
		local startFloat = Vector3.new(root.Position.X, dest.Y + GameConstants.SW_RUNE_WATER_LIFT, root.Position.Z)
		liftAlign.Position = startFloat
		liftAlign.Parent = root
		local spinAlign = Instance.new("AlignOrientation")
		spinAlign.Name = "SwRuneTumble"
		spinAlign.Mode = Enum.OrientationAlignmentMode.OneAttachment
		spinAlign.Attachment0 = liftAtt
		spinAlign.RigidityEnabled = false
		spinAlign.Responsiveness = 5
		spinAlign.MaxTorque = 1e7
		spinAlign.MaxAngularVelocity = 3
		spinAlign.CFrame = root.CFrame.Rotation
		spinAlign.Parent = root
		hum.WalkSpeed = 0
		hum.JumpPower = 0
		hum.UseJumpPower = true
		local autoRotate = hum.AutoRotate
		hum.AutoRotate = false
		hum:Move(Vector3.zero, false)
		local spinRates = randomWaterSpinRates()
		local animTrack = playCharacterAnim(victim, GameConstants.SW_RUNE_WATER_ANIM, Enum.AnimationPriority.Action4)
		if animTrack then
			animTrack.Looped = true
		end
		pcall(function()
			root:SetNetworkOwner(nil)
		end)
		return {
			model = victim,
			kind = kind,
			fx = fx,
			bubble = bubble,
			liftAlign = liftAlign,
			liftAtt = liftAtt,
			spinAlign = spinAlign,
			walk = walk,
			jump = jump,
			tickAcc = 0,
			nextLightning = 0,
			nextWander = waterWanderDelay(),
			spinRates = spinRates,
			spinGoal = randomWaterSpinRates(),
			nextSpinShift = waterSpinShiftDelay(),
			spinCFrame = root.CFrame.Rotation,
			wanderGoal = randomWaterFloatPos(dest),
			bubblePos = root.Position,
			animTrack = animTrack,
			autoRotate = autoRotate,
			transparencySnaps = transparencySnaps,
		}
	end

	return {
		model = victim,
		kind = kind,
		fx = fx,
		bubble = bubble,
		liftAlign = liftAlign,
		liftAtt = liftAtt,
		walk = walk,
		jump = jump,
		tickAcc = 0,
		nextLightning = 0,
		nextWander = waterWanderDelay(),
		transparencySnaps = transparencySnaps,
	}
end

local function castRuneDisplacement(player: Player, aimPoint: Vector3?)
	local character = player.Character
	if not character then
		return
	end
	if runeFieldByPlayer[player] then
		return
	end
	local entry = CharacterRegistry.getAbilityById("scarlet_witch", "rune_entrapment")
	if not entry or not canUse(character, entry.id, entry.energyCost) then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local dest = aimPoint or (root.Position + root.CFrame.LookVector * 22)
	dest = VfxHelper.snapToFloor(dest, { character })
	AbilityCooldownHelper.setActive(character, entry.id, true)
	character:SetAttribute(GameConstants.BUSY_ATTRIBUTE, true)
	local castTrack = playCharacterAnim(character, GameConstants.SW_RUNE_CAST_ANIM, Enum.AnimationPriority.Action4)
	if castTrack then
		castTrack.Looped = false
	end
	local hum = CombatHelper.getHumanoid(character)
	local walk = GameConstants.DEFAULT_WALK_SPEED
	local jumpPower: number? = nil
	local jumpHeight: number? = nil
	local casterAutoRotate = true
	if hum then
		walk = hum.WalkSpeed
		casterAutoRotate = hum.AutoRotate
		if hum.UseJumpPower then
			jumpPower = hum.JumpPower
		else
			jumpHeight = hum.JumpHeight
		end
		hum.WalkSpeed = 0
		hum.AutoRotate = false
		hum.JumpPower = 0
		hum.UseJumpPower = true
		pcall(function()
			hum.JumpHeight = 0
		end)
		pcall(function()
			hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		end)
		hum:Move(Vector3.zero, false)
	end

	local faceAlign: AlignOrientation? = nil
	local faceAtt: Attachment? = nil
	if root then
		faceAtt = Instance.new("Attachment")
		faceAtt.Name = "SwRuneCasterFaceAtt"
		faceAtt.Parent = root
		faceAlign = Instance.new("AlignOrientation")
		faceAlign.Name = "SwRuneCasterFace"
		faceAlign.Mode = Enum.OrientationAlignmentMode.OneAttachment
		faceAlign.Attachment0 = faceAtt
		faceAlign.MaxTorque = math.huge
		faceAlign.Responsiveness = 18
		faceAlign.RigidityEnabled = false
		faceAlign.Parent = root
		local flat = Vector3.new(dest.X - root.Position.X, 0, dest.Z - root.Position.Z)
		if flat.Magnitude > 0.05 then
			faceAlign.CFrame = CFrame.lookAt(root.Position, root.Position + flat.Unit)
		else
			faceAlign.CFrame = root.CFrame
		end
	end

	HandParticleHelper.beginUse(character)
	fireCameraShake(player, 0.42, 0.4, 0.34, 0.5)
	local zoneTemplate = VfxHelper.getScarletAsset("RuneDisplacement", "RuneDisplacement")
	local zone: Instance? = nil
	if zoneTemplate then
		zone = zoneTemplate:Clone()
		VfxHelper.muteSounds(zone)
		if zone:IsA("BasePart") then
			zone.Anchored = true
			zone.CanCollide = false
			zone.Parent = workspace
			setWorldPosKeepRot(zone, dest)
		elseif zone:IsA("Model") then
			zone.Parent = workspace
			setWorldPosKeepRot(zone, dest)
		elseif zone:IsA("Attachment") then
			local host = Instance.new("Part")
			host.Name = "SwRuneZoneHost"
			host.Size = Vector3.new(0.2, 0.2, 0.2)
			host.Transparency = 1
			host.Anchored = true
			host.CanCollide = false
			host.CFrame = CFrame.new(dest)
			host.Parent = workspace
			zone.Parent = host
			zone = host
		else
			zone.Parent = workspace
		end
		VfxHelper.setParticlesEnabled(zone, true)
		VfxHelper.emitAllParticles(zone, 16)
	end
	VfxHelper.playWorldSound(GameConstants.SW_RUNE_ENTRAPMENT_SOUND, dest, 1.05)

	local victims: { RuneVictimState } = {}
	for _, model in CombatHelper.overlapCharacters(dest, GameConstants.SW_RUNE_RADIUS, character) do
		if model:GetAttribute(GameConstants.HERO_ATTRIBUTE) == "scarlet_witch" then
			continue
		end
		local applied = applyRuneToVictim(character, model, pickRuneKind(), dest)
		if applied then
			table.insert(victims, applied)
		end
	end

	local fieldState: RuneFieldState = {
		character = character,
		zone = zone,
		victims = victims,
		endsAt = os.clock() + GameConstants.SW_RUNE_DURATION,
		dest = dest,
		walk = walk,
		jumpPower = jumpPower,
		jumpHeight = jumpHeight,
		casterAutoRotate = casterAutoRotate,
		faceAlign = faceAlign,
		faceAtt = faceAtt,
	}
	runeFieldByPlayer[player] = fieldState
	if castTrack then
		castTrack.Ended:Once(function()
			if runeFieldByPlayer[player] == fieldState then
				stopRuneDisplacement(player, true)
			end
			castTrack:Destroy()
		end)
	end
	-- Safety fallback in case the animation cannot load or never reports completion.
	task.delay(GameConstants.SW_RUNE_DURATION, function()
		if runeFieldByPlayer[player] == fieldState then
			stopRuneDisplacement(player, true)
		end
	end)
end

local function updateRuneDisplacement(player: Player, dt: number)
	local state = runeFieldByPlayer[player]
	if not state then
		return
	end
	if os.clock() >= state.endsAt or not state.character.Parent then
		stopRuneDisplacement(player, true)
		return
	end
	local casterHum = CombatHelper.getHumanoid(state.character)
	if casterHum and casterHum.Parent then
		casterHum.WalkSpeed = 0
		casterHum.JumpPower = 0
	end
	updateRuneCasterFace(state)
	--[[ Pull fire/lightning victims into the rune center while swirling on the ground plane (X/Z). ]]
	local function swirlPullToRuneCenter(root: BasePart, swirlSign: number)
		local pos = root.Position
		local offset = Vector3.new(pos.X - state.dest.X, 0, pos.Z - state.dest.Z)
		local dist = offset.Magnitude
		local inward = Vector3.zero
		local tangent = Vector3.zero
		if dist > 0.2 then
			local radial = offset.Unit
			inward = -radial * GameConstants.SW_RUNE_PULL_SPEED
			tangent = Vector3.new(-radial.Z, 0, radial.X) * (swirlSign * GameConstants.SW_RUNE_SWIRL_SPEED)
			-- Keep a tight swirl near the center instead of locking still.
			if dist < 3 then
				inward *= dist / 3
				tangent = tangent.Unit * (GameConstants.SW_RUNE_SWIRL_SPEED * (0.55 + dist / 3))
			end
		else
			tangent = Vector3.new(swirlSign * GameConstants.SW_RUNE_SWIRL_SPEED, 0, 0)
		end
		local vel = inward + tangent
		root.AssemblyLinearVelocity = Vector3.new(vel.X, math.min(root.AssemblyLinearVelocity.Y, 2), vel.Z)
		root.AssemblyAngularVelocity = Vector3.new(
			swirlSign * 2.2,
			swirlSign * 4.5,
			swirlSign * 1.6
		)
	end
	local affected: { [Model]: boolean } = {}
	for _, victim in state.victims do
		affected[victim.model] = true
	end
	for _, model in CombatHelper.overlapCharacters(state.dest, GameConstants.SW_RUNE_RADIUS, state.character) do
		if not affected[model] and model:GetAttribute(GameConstants.HERO_ATTRIBUTE) ~= "scarlet_witch" then
			local applied = applyRuneToVictim(state.character, model, pickRuneKind(), state.dest)
			if applied then
				table.insert(state.victims, applied)
				affected[model] = true
			end
		end
	end
	for _, victim in state.victims do
		local model = victim.model
		local hum = CombatHelper.getHumanoid(model)
		local vRoot = getRootPart(model)
		if not model.Parent or not hum or hum.Health <= 0 or not vRoot then
			continue
		end
		if victim.kind == "fire" then
			hum.WalkSpeed = 0
			hum.JumpPower = 0
			hum:Move(Vector3.zero, false)
			if model:GetAttribute("Ragdolled") ~= true then
				RagdollStatus.apply(model)
			end
			swirlPullToRuneCenter(vRoot, victim.swirlSign or 1)
			victim.tickAcc += dt
			if victim.tickAcc >= 0.25 then
				local slice = victim.tickAcc
				victim.tickAcc = 0
				CombatHelper.dealDamage(state.character, model, GameConstants.SW_RUNE_FIRE_DPS * slice, vRoot.Position, "hex")
			end
		elseif victim.kind == "lightning" then
			hum.WalkSpeed = 0
			hum.JumpPower = 0
			hum:Move(Vector3.zero, false)
			if model:GetAttribute("Ragdolled") ~= true then
				RagdollStatus.apply(model)
			end
			swirlPullToRuneCenter(vRoot, victim.swirlSign or 1)
			victim.nextLightning += dt
			if victim.nextLightning >= GameConstants.SW_RUNE_LIGHTNING_INTERVAL then
				victim.nextLightning = 0
				CombatHelper.dealDamage(state.character, model, GameConstants.SW_RUNE_LIGHTNING_DAMAGE, vRoot.Position, "hex")
			end
		elseif victim.kind == "water" then
			hum.WalkSpeed = 0
			hum.JumpPower = 0
			hum.AutoRotate = false
			hum:Move(Vector3.zero, false)
			victim.nextWander -= dt
			if victim.nextWander <= 0 then
				victim.wanderGoal = randomWaterFloatPos(state.dest)
				victim.nextWander = waterWanderDelay()
			end
			-- Ease the align target toward the next float spot so the bubble glides instead of jumping.
			if victim.liftAlign and victim.liftAlign.Parent then
				local goal = victim.wanderGoal or victim.liftAlign.Position
				local blend = math.clamp(dt * GameConstants.SW_RUNE_WATER_DRIFT_RESPONSE, 0, 1)
				victim.liftAlign.Position = victim.liftAlign.Position:Lerp(goal, blend)
			end
			victim.nextSpinShift = (victim.nextSpinShift or waterSpinShiftDelay()) - dt
			if victim.nextSpinShift <= 0 then
				victim.spinGoal = randomWaterSpinRates()
				victim.nextSpinShift = waterSpinShiftDelay()
			end
			local rates = victim.spinRates or randomWaterSpinRates()
			local goalRates = victim.spinGoal or rates
			rates = rates:Lerp(goalRates, math.clamp(dt * GameConstants.SW_RUNE_WATER_SPIN_BLEND, 0, 1))
			victim.spinRates = rates
			local spinCFrame = victim.spinCFrame or vRoot.CFrame.Rotation
			spinCFrame *= CFrame.fromEulerAnglesXYZ(rates.X * dt, rates.Y * dt, rates.Z * dt)
			victim.spinCFrame = spinCFrame
			if victim.spinAlign and victim.spinAlign.Parent then
				victim.spinAlign.CFrame = spinCFrame
			end
		end
	end
end

local function getBlastMode(character: Model): string
	local mode = character:GetAttribute(GameConstants.HEX_BLAST_MODE_ATTRIBUTE)
	if mode == "Barrage" then
		return "Barrage"
	end
	return "Single"
end

local function getLeftHand(character: Model): BasePart?
	return (character:FindFirstChild("LeftHand")
		or character:FindFirstChild("Left Arm")
		or character:FindFirstChild("LeftLowerArm")) :: BasePart?
end

local function getRightHand(character: Model): BasePart?
	return (character:FindFirstChild("RightHand")
		or character:FindFirstChild("Right Arm")
		or character:FindFirstChild("RightLowerArm")) :: BasePart?
end

local function playCharacterAnim(character: Model, assetId: string, priority: Enum.AnimationPriority?): AnimationTrack?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = assetId
	local ok, track = pcall(function()
		return (animator :: Animator):LoadAnimation(anim)
	end)
	anim:Destroy()
	if not ok or not track then
		return nil
	end
	track.Priority = priority or Enum.AnimationPriority.Action
	track.Looped = false
	track:Play(0.1, 1, 1)
	return track
end

local function getOrigin(character: Model): Vector3
	local hand = getRightHand(character)
	if hand then
		return hand.Position
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return if root then root.Position + Vector3.new(0, 1.5, 0) else Vector3.zero
end

local function flashBothHands(character: Model)
	local color = VfxHelper.chaosColor()
	local left = getLeftHand(character)
	local right = getRightHand(character)
	if left then
		VfxHelper.castHandFlash(left.Position, color)
	end
	if right then
		VfxHelper.castHandFlash(right.Position, color)
	end
	if not left and not right then
		VfxHelper.castHandFlash(getOrigin(character), color)
	end
end

local function fireHexBolt(player: Player, direction: Vector3, aimPoint: Vector3?)
	local character = player.Character
	if not character then
		return
	end
	local entry = CharacterRegistry.getAbilityById("scarlet_witch", "hex_bolt")
	if not entry or not canUse(character, entry.id, entry.energyCost) then
		return
	end
	local useRight = character:GetAttribute("SwBoltUseRight") ~= false
	character:SetAttribute("SwBoltUseRight", not useRight)
	local hand = if useRight then getRightHand(character) else getLeftHand(character)
	local origin = if hand then hand.Position else getOrigin(character)
	local dir = if direction.Magnitude > 0.01 then direction.Unit else character:GetPivot().LookVector
	if aimPoint then
		local toAim = aimPoint - origin
		if toAim.Magnitude > 0.05 then
			dir = toAim.Unit
		end
	end
	AbilityCooldownHelper.setActive(character, entry.id, true)
	HandParticleHelper.pulse(character, 0.4)
	playCharacterAnim(
		character,
		if useRight then GameConstants.IW_DISC_RIGHT_ANIM else GameConstants.IW_DISC_LEFT_ANIM,
		Enum.AnimationPriority.Action
	)
	fireCameraShake(player, 0.34, 0.22, 0.22, 0.35)
	task.delay(0.1, function()
		if not character.Parent or player.Character ~= character then
			AbilityCooldownHelper.setActive(character, entry.id, false)
			return
		end
		local liveHand = if useRight then getRightHand(character) else getLeftHand(character)
		local fireOrigin = if liveHand then liveHand.Position else getOrigin(character)
		local fireDir = dir
		if aimPoint then
			local toAim = aimPoint - fireOrigin
			if toAim.Magnitude > 0.05 then
				fireDir = toAim.Unit
			end
		end
		VfxHelper.playWorldSound(GameConstants.HEX_BOLT_SOUND, fireOrigin, 0.95)
		VfxHelper.castHandFlash(fireOrigin, VfxHelper.chaosColor())
		ProjectileHelper.spawn(fireOrigin, fireDir, {
			speed = GameConstants.HEX_BLAST_SPEED,
			damage = GameConstants.HEX_BOLT_DAMAGE,
			radius = GameConstants.HEX_BLAST_HIT_RADIUS,
			maxDistance = GameConstants.HEX_BLAST_RANGE,
			owner = character,
			color = VfxHelper.chaosColor(),
			homeDir = fireDir,
			homePoint = aimPoint or (fireOrigin + fireDir * math.min(70, GameConstants.HEX_BLAST_RANGE * 0.75)),
			homeAfter = 0.04,
			boltFolder = "ScarletWitchClassic",
			boltAsset = "Bolt",
			impactOnCharacter = true,
		})
		finishAbility(character, entry.id, entry.cooldown)
	end)
end

local function resolveTarget(
	character: Model,
	targetModel: Model?,
	direction: Vector3,
	range: number,
	lockOn: boolean?
): Model?
	-- Players and NPCs (any Model with a living Humanoid)
	if targetModel and targetModel.Parent and targetModel ~= character then
		local hum = targetModel:FindFirstChildOfClass("Humanoid")
		local root = getRootPart(targetModel)
		local casterRoot = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hum and hum.Health > 0 and root and casterRoot then
			if (root.Position - casterRoot.Position).Magnitude <= range then
				return targetModel
			end
		end
	end
	if lockOn ~= true then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil
	end
	local dir = if direction.Magnitude > 0.01 then direction.Unit else root.CFrame.LookVector
	return CombatHelper.raycastCharacter(root.Position, dir, range, character)
end

-- Hex Blast

local function fireHexBlast(player: Player, direction: Vector3, aimPoint: Vector3?)
	local character = player.Character
	if not character then
		return
	end
	local entry = CharacterRegistry.getAbilityById("scarlet_witch", "hex_blast")
	if not entry or not canUse(character, entry.id, entry.energyCost) then
		return
	end

	local origin = getOrigin(character)
	local dir = if direction.Magnitude > 0.01 then direction.Unit else character:GetPivot().LookVector
	local homeDir = dir
	if aimPoint then
		local toAim = aimPoint - origin
		if toAim.Magnitude > 0.05 then
			homeDir = toAim.Unit
		end
	end
	local mode = getBlastMode(character)

	AbilityCooldownHelper.setActive(character, entry.id, true)
	HandParticleHelper.beginUse(character)
	flashBothHands(character)
	fireCameraShake(player, 0.36, 0.38, 0.22, 0.4)

	VfxHelper.castHandFlash(origin, VfxHelper.chaosColor())

	local cd = if mode == "Barrage"
		then GameConstants.HEX_BLAST_BARRAGE_COOLDOWN
		else GameConstants.HEX_BLAST_SINGLE_COOLDOWN

	if mode == "Single" then
		local isFlying = character:GetAttribute(GameConstants.IS_FLYING_ATTRIBUTE) == true
		if isFlying then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				local animator = humanoid:FindFirstChildOfClass("Animator")
				if not animator then
					animator = Instance.new("Animator")
					animator.Parent = humanoid
				end
				-- Alternate flight cast anims (left/right hand) each shot
				local useAlt = character:GetAttribute("HexBlastFlightAnimAlt") == true
				character:SetAttribute("HexBlastFlightAnimAlt", not useAlt)
				local animId = if useAlt
					then GameConstants.HEX_BLAST_FLIGHT_ANIM_ALT
					else GameConstants.HEX_BLAST_FLIGHT_ANIM
				local anim = Instance.new("Animation")
				anim.AnimationId = animId
				local ok, track = pcall(function()
					return (animator :: Animator):LoadAnimation(anim)
				end)
				anim:Destroy()
				if ok and track then
					track.Priority = Enum.AnimationPriority.Action4
					track.Looped = false
					track:Play(0.08)
				end
			end
		end
		-- Wait briefly after cast anim so the bolt syncs with the hand motion
		task.delay(0.1, function()
			if not character.Parent or player.Character ~= character then
				AbilityCooldownHelper.setActive(character, entry.id, false)
				HandParticleHelper.endUse(character)
				return
			end
			local fireOrigin = getOrigin(character)
			VfxHelper.playWorldSound(GameConstants.HEX_BOLT_SOUND, fireOrigin, 0.95)
			ProjectileHelper.spawn(fireOrigin, homeDir, {
				speed = GameConstants.HEX_BLAST_SPEED,
				damage = GameConstants.HEX_BLAST_DAMAGE,
				radius = GameConstants.HEX_BLAST_HIT_RADIUS,
				maxDistance = GameConstants.HEX_BLAST_RANGE,
				owner = character,
				color = VfxHelper.chaosColor(),
				homeDir = homeDir,
				homePoint = aimPoint or (fireOrigin + homeDir * math.min(60, GameConstants.HEX_BLAST_RANGE * 0.7)),
				homeAfter = 0,
				seekUntilClose = true,
				seekCloseDistance = 2.2,
			})
			VfxHelper.spawnBeamLine(fireOrigin, fireOrigin + homeDir * 8, VfxHelper.chaosSoft(), 0.35, 0.16)
			finishAbility(character, entry.id, cd)
			task.delay(0.4, function()
				if character.Parent then
					HandParticleHelper.endUse(character)
				end
			end)
		end)
		return
	end

	-- Barrage: while flying play cast anim + 360 yaw spin; on ground just fire
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local isFlying = character:GetAttribute(GameConstants.IS_FLYING_ATTRIBUTE) == true

	local function releaseBarrageBolts()
		if not character.Parent then
			return
		end
		local fireOrigin = getOrigin(character)
		local count = GameConstants.HEX_BLAST_MULTI_COUNT
		local basis = CFrame.lookAt(Vector3.zero, homeDir)
		local right = basis.RightVector
		local up = basis.UpVector

		-- Spread/random scale from cursor distance (closer = tighter, farther = wider)
		local aimDist = if aimPoint then (aimPoint - fireOrigin).Magnitude else GameConstants.HEX_BLAST_BARRAGE_DIST_FAR * 0.65
		local distT = math.clamp(
			(aimDist - GameConstants.HEX_BLAST_BARRAGE_DIST_CLOSE)
				/ math.max(1, GameConstants.HEX_BLAST_BARRAGE_DIST_FAR - GameConstants.HEX_BLAST_BARRAGE_DIST_CLOSE),
			0,
			1
		)
		local outwardBase = GameConstants.HEX_BLAST_BARRAGE_OUTWARD_CLOSE
			+ (GameConstants.HEX_BLAST_BARRAGE_OUTWARD_FAR - GameConstants.HEX_BLAST_BARRAGE_OUTWARD_CLOSE) * distT
		local outwardJitter = GameConstants.HEX_BLAST_BARRAGE_OUTWARD_JITTER_CLOSE
			+ (GameConstants.HEX_BLAST_BARRAGE_OUTWARD_JITTER_FAR - GameConstants.HEX_BLAST_BARRAGE_OUTWARD_JITTER_CLOSE) * distT
		local angleJitter = math.rad(
			GameConstants.HEX_BLAST_BARRAGE_ANGLE_JITTER_CLOSE
				+ (GameConstants.HEX_BLAST_BARRAGE_ANGLE_JITTER_FAR - GameConstants.HEX_BLAST_BARRAGE_ANGLE_JITTER_CLOSE) * distT
		)
		local homeJitterDeg = GameConstants.HEX_BLAST_BARRAGE_HOME_JITTER_CLOSE
			+ (GameConstants.HEX_BLAST_BARRAGE_HOME_JITTER_FAR - GameConstants.HEX_BLAST_BARRAGE_HOME_JITTER_CLOSE) * distT
		local curveJitter = GameConstants.HEX_BLAST_BARRAGE_CURVE_JITTER_CLOSE
			+ (GameConstants.HEX_BLAST_BARRAGE_CURVE_JITTER_FAR - GameConstants.HEX_BLAST_BARRAGE_CURVE_JITTER_CLOSE) * distT

		local aimHome = aimPoint or (fireOrigin + homeDir * 60)
		-- Scatter end positions around the aim (not one shared lock point)
		local endScatter = 5 + distT * 12

		for i = 1, count do
			local baseAngle = ((i - 1) / count) * math.pi * 2
			local angle = baseAngle + (math.random() - 0.5) * angleJitter * 2
			local radial = (right * math.cos(angle) + up * math.sin(angle))
			if radial.Magnitude < 0.01 then
				radial = right
			else
				radial = radial.Unit
			end
			local outward = math.clamp(
				outwardBase + (math.random() - 0.5) * outwardJitter * 2,
				0.55,
				0.995
			)
			local spreadDir = (radial * outward + homeDir * (1 - outward))
			if spreadDir.Magnitude < 0.01 then
				spreadDir = radial
			else
				spreadDir = spreadDir.Unit
			end

			local homeJitter = CFrame.Angles(
				math.rad((math.random() - 0.5) * homeJitterDeg * 2),
				math.rad((math.random() - 0.5) * homeJitterDeg * 2),
				0
			)
			local boltHome = (CFrame.lookAt(Vector3.zero, homeDir) * homeJitter).LookVector
			local turnScale = 0.9 + math.random() * curveJitter

			-- Random end position near aim (sphere scatter), independent per bolt
			local scatterOffset = Vector3.new(
				(math.random() - 0.5) * 2,
				(math.random() - 0.5) * 1.4,
				(math.random() - 0.5) * 2
			)
			if scatterOffset.Magnitude < 0.05 then
				scatterOffset = right
			end
			local boltHomePoint = aimHome + scatterOffset.Unit * (math.random() * endScatter)

			task.delay((i - 1) * 0.02 + math.random() * 0.03, function()
				if not character.Parent then
					return
				end
				VfxHelper.playWorldSound(GameConstants.HEX_BOLT_SOUND, fireOrigin, 0.85)
				ProjectileHelper.spawn(fireOrigin, spreadDir, {
					speed = GameConstants.HEX_BLAST_BARRAGE_START_SPEED * (0.9 + math.random() * 0.2),
					damage = GameConstants.HEX_BLAST_BARRAGE_DAMAGE,
					radius = GameConstants.HEX_BLAST_BARRAGE_HIT_RADIUS,
					maxDistance = GameConstants.HEX_BLAST_BARRAGE_RANGE,
					owner = character,
					color = VfxHelper.chaosColor(),
					accel = GameConstants.HEX_BLAST_BARRAGE_ACCEL,
					maxSpeed = GameConstants.HEX_BLAST_BARRAGE_MAX_SPEED,
					homeDir = boltHome,
					homePoint = boltHomePoint,
					homeAfter = GameConstants.HEX_BLAST_BARRAGE_HOME_AFTER * (0.9 + math.random() * 0.2),
					homeTurnScale = turnScale,
					seekUntilClose = true,
					seekCloseDistance = 2.2,
					ragdollOnHit = GameConstants.RAGDOLL_BARRAGE_HIT_DURATION,
					pushOnHit = true,
					pushSpeed = GameConstants.HEX_BLAST_BARRAGE_PUSH_SPEED,
					pushUp = GameConstants.HEX_BLAST_BARRAGE_PUSH_UP,
				})
			end)
		end
		VfxHelper.spawnPulseRing(fireOrigin, 2.5, VfxHelper.chaosColor(), 0.28)
	end

	local function playBarrageCastAnim(): AnimationTrack?
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return nil
		end
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = humanoid
		end
		local anim = Instance.new("Animation")
		anim.AnimationId = GameConstants.HEX_BLAST_BARRAGE_ANIM
		local ok, track = pcall(function()
			return animator:LoadAnimation(anim)
		end)
		anim:Destroy()
		if not ok or not track then
			return nil
		end
		track.Priority = Enum.AnimationPriority.Action4
		track.Looped = false
		track:Play(0.1)
		return track
	end

	if not isFlying or not root then
		releaseBarrageBolts()
		finishAbility(character, entry.id, cd)
		task.delay(0.4, function()
			if character.Parent then
				HandParticleHelper.endUse(character)
			end
		end)
		return
	end

	task.spawn(function()
		local track = playBarrageCastAnim()
		-- Capture full start pose (includes flight pitch/bank); spin in local yaw so pitch axis stays consistent
		local startCf = root.CFrame
		local startRot = startCf - startCf.Position
		local spinSign = if math.random() > 0.5 then 1 else -1
		local yawJitter = spinSign * math.rad((math.random() - 0.5) * 24)
		local totalDelta = spinSign * math.pi * 2 + yawJitter

		local spinTime = GameConstants.HEX_BLAST_BARRAGE_SPIN_TIME
		local releaseAt = GameConstants.HEX_BLAST_BARRAGE_RELEASE_AT
		local released = false
		local t0 = os.clock()

		character:SetAttribute("BarrageSpinActive", true)
		character:SetAttribute("BarrageSpinYaw", 0)

		local function applySpin(yaw: number)
			-- Local-Y spin on the flight pose: respects pitch/bank instead of tumbling around world Y
			local spun = CFrame.new(root.Position) * (startRot * CFrame.Angles(0, yaw, 0))
			local align = root:FindFirstChild("HeroAlignOrientation")
			if align and align:IsA("AlignOrientation") then
				align.CFrame = spun
			else
				root.CFrame = spun
			end
		end

		while character.Parent and root.Parent and (os.clock() - t0) < spinTime do
			local alpha = math.clamp((os.clock() - t0) / spinTime, 0, 1)
			local yaw = totalDelta * alpha
			character:SetAttribute("BarrageSpinYaw", yaw)
			applySpin(yaw)

			if not released and alpha >= releaseAt then
				released = true
				releaseBarrageBolts()
			end
			task.wait()
		end

		if character.Parent and root.Parent then
			character:SetAttribute("BarrageSpinYaw", totalDelta)
			applySpin(totalDelta)
			task.wait()
		end

		if character.Parent then
			character:SetAttribute("BarrageSpinActive", nil)
			character:SetAttribute("BarrageSpinYaw", nil)
		end
		if not released then
			releaseBarrageBolts()
		end
		if track then
			pcall(function()
				track:Stop(0.15)
				track:Destroy()
			end)
		end
		if character.Parent then
			finishAbility(character, entry.id, cd)
			task.delay(0.35, function()
				if character.Parent then
					HandParticleHelper.endUse(character)
				end
			end)
		end
	end)
end

-- Hex Beam (HexBeam at the hand, HexBeamEnd at the locked target)

local BEAM_FX_FADE = 2.0

local function cloneScarletInstance(...: string): Instance?
	local template = VfxHelper.getScarletAsset(...)
	if not template then
		return nil
	end
	return template:Clone()
end

local function firstAttachment(root: Instance): Attachment?
	if root:IsA("Attachment") then
		return root
	end
	return root:FindFirstChildWhichIsA("Attachment", true)
end

local function firstBeam(root: Instance): Beam?
	if root:IsA("Beam") then
		return root
	end
	return root:FindFirstChildWhichIsA("Beam", true)
end

local function collectBeams(root: Instance): { Beam }
	local list: { Beam } = {}
	if root:IsA("Beam") then
		table.insert(list, root)
	end
	for _, desc in root:GetDescendants() do
		if desc:IsA("Beam") then
			table.insert(list, desc)
		end
	end
	return list
end

local function prepFxPart(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false
end

local function fadeOutBeamFx(startHost: BasePart, tipHost: BasePart, startAtt: Attachment, endAtt: Attachment, beam: Beam?)
	VfxHelper.smoothDisableParticles(startHost, 0.4)
	VfxHelper.smoothDisableParticles(tipHost, 0.4)
	VfxHelper.smoothDisableParticles(startAtt, 0.4)
	VfxHelper.smoothDisableParticles(endAtt, 0.4)
	for _, b in collectBeams(startHost) do
		b.Enabled = false
	end
	for _, b in collectBeams(tipHost) do
		b.Enabled = false
	end
	if beam then
		beam.Enabled = false
	end
	task.delay(BEAM_FX_FADE, function()
		if startHost.Parent then
			startHost:Destroy()
		end
		if tipHost.Parent then
			tipHost:Destroy()
		end
	end)
end

local function destroyBeamFaceAligns(state: BeamState)
	if state.casterFace then
		state.casterFace:Destroy()
	end
	if state.casterFaceAtt then
		state.casterFaceAtt:Destroy()
	end
	if state.victimFace then
		state.victimFace:Destroy()
	end
	if state.victimFaceAtt then
		state.victimFaceAtt:Destroy()
	end
	state.casterFace = nil
	state.casterFaceAtt = nil
	state.victimFace = nil
	state.victimFaceAtt = nil
end

local function restoreVictimAfterBeam(state: BeamState)
	local victim = state.victim
	local vRoot = state.victimRoot
	if state.victimAnimTrack then
		state.victimAnimTrack:Stop(0.15)
		state.victimAnimTrack:Destroy()
		state.victimAnimTrack = nil
	end
	local vHum = CombatHelper.getHumanoid(victim)
	if vHum and vHum.Parent then
		vHum.WalkSpeed = state.victimWalk
		if state.victimJump ~= nil then
			vHum.JumpPower = state.victimJump
		end
		vHum.AutoRotate = state.victimAutoRotate
	end
	if vRoot and vRoot.Parent then
		local plr = Players:GetPlayerFromCharacter(victim)
		pcall(function()
			if plr then
				vRoot:SetNetworkOwner(plr)
			else
				vRoot:SetNetworkOwnershipAuto()
			end
		end)
	end
end

local function restoreBeamMovement(state: BeamState)
	local hum = CombatHelper.getHumanoid(state.character)
	if not hum then
		return
	end
	hum.WalkSpeed = state.walk
	if state.jumpPower ~= nil then
		hum.JumpPower = state.jumpPower
	end
	if state.jumpHeight ~= nil then
		hum.JumpHeight = state.jumpHeight
	end
	hum.AutoRotate = state.casterAutoRotate
	pcall(function()
		hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
	end)
end

local function applyBeamMovement(state: BeamState)
	local hum = CombatHelper.getHumanoid(state.character)
	if not hum then
		return
	end
	hum.WalkSpeed = GameConstants.HEX_BEAM_WALK_SPEED
	hum.JumpPower = 0
	hum.UseJumpPower = true
	pcall(function()
		hum.JumpHeight = 0
	end)
	pcall(function()
		hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	end)
	hum.AutoRotate = false
end

local function knockBeamVictim(state: BeamState)
	local victim = state.victim
	local vRoot = state.victimRoot
	if not victim.Parent or not vRoot.Parent then
		return
	end
	local hum = CombatHelper.getHumanoid(victim)
	if not hum or hum.Health <= 0 then
		return
	end
	local casterRoot = state.character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local away = vRoot.Position - (if casterRoot then casterRoot.Position else vRoot.Position)
	local dir = if away.Magnitude > 0.05 then away.Unit else Vector3.new(0, 0, -1)
	RagdollStatus.applyTimed(victim, GameConstants.HEX_BEAM_END_RAGDOLL)
	pcall(function()
		vRoot:SetNetworkOwner(nil)
	end)
	local function shove()
		if not victim.Parent or not vRoot.Parent then
			return
		end
		PushHelper.applyToCharacter(victim, dir, {
			speed = GameConstants.HEX_BEAM_END_PUSH_SPEED,
			upBoost = GameConstants.HEX_BEAM_END_PUSH_UP,
			impulseMult = 1.25,
		})
		vRoot.AssemblyLinearVelocity = dir * GameConstants.HEX_BEAM_END_PUSH_SPEED
			+ Vector3.new(0, GameConstants.HEX_BEAM_END_PUSH_UP, 0)
	end
	shove()
	task.defer(shove)
end

local function finishHexBeamFx(state: BeamState, applyCooldown: boolean?)
	destroyBeamFaceAligns(state)
	knockBeamVictim(state)
	restoreBeamMovement(state)
	if state.victim.Parent then
		local vHum = CombatHelper.getHumanoid(state.victim)
		if vHum and vHum.Parent then
			vHum.WalkSpeed = state.victimWalk
			if state.victimJump ~= nil then
				vHum.JumpPower = state.victimJump
			end
		end
	end
	fadeOutBeamFx(state.startHost, state.tipHost, state.startAtt, state.endAtt, state.beam)
	if state.victimAnimTrack then
		state.victimAnimTrack:Stop(0.15)
		state.victimAnimTrack:Destroy()
		state.victimAnimTrack = nil
	end
	if state.animTrack then
		state.animTrack:Stop(0.15)
		state.animTrack:Destroy()
		state.animTrack = nil
	end
	local char = state.character
	if char.Parent then
		AbilityCooldownHelper.setActive(char, "hex_beam", false)
		if char:GetAttribute(GameConstants.BUSY_ATTRIBUTE) == true then
			char:SetAttribute(GameConstants.BUSY_ATTRIBUTE, nil)
		end
		HandParticleHelper.endUse(char, "Right")
		if applyCooldown then
			local entry = CharacterRegistry.getAbilityById("scarlet_witch", "hex_beam")
			if entry then
				AbilityCooldownHelper.applyAfterUse(char, entry.id, entry.cooldown)
			end
		end
	end
end

local function stopHexBeam(player: Player, applyCooldown: boolean?)
	local state = beamByPlayer[player]
	if not state then
		return
	end
	-- Stay locked in beam during clash (key release ignored)
	if state.character:GetAttribute(GameConstants.BEAM_CLASH_ATTRIBUTE) == true
		or BeamClashService.shouldKeepBeamAlive(state.character)
	then
		return
	end
	beamByPlayer[player] = nil
	finishHexBeamFx(state, applyCooldown)
end

function ScarletWitchService.forceStopBeam(player: Player, applyCooldown: boolean?)
	local state = beamByPlayer[player]
	if not state then
		return
	end
	beamByPlayer[player] = nil
	finishHexBeamFx(state, applyCooldown)
end

local function hexBeamTipInFront(origin: Vector3, victimPos: Vector3): Vector3
	local toVictim = victimPos - origin
	local dist = toVictim.Magnitude
	if dist < 0.15 then
		return victimPos
	end
	-- Sit 1 stud in front of the target (Wanda's side).
	return origin + toVictim.Unit * math.max(dist - GameConstants.HEX_BEAM_TIP_FRONT, 0.05)
end

local function makeBeamFaceAlign(root: BasePart, name: string): (AlignOrientation, Attachment)
	local att = Instance.new("Attachment")
	att.Name = name .. "Att"
	att.Parent = root
	local align = Instance.new("AlignOrientation")
	align.Name = name
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = att
	align.MaxTorque = math.huge
	align.Responsiveness = 18
	align.CFrame = root.CFrame
	align.Parent = root
	return align, att
end

local function beginHexBeamOnTarget(state: BeamState)
	local vHum = CombatHelper.getHumanoid(state.victim)
	local vRoot = state.victimRoot
	if vHum and vHum.Parent then
		vHum.WalkSpeed = 0
		vHum.JumpPower = 0
		vHum.UseJumpPower = true
		vHum.AutoRotate = false
	end
	if vRoot and vRoot.Parent then
		pcall(function()
			vRoot:SetNetworkOwner(nil)
		end)
	end
	if not state.casterFace then
		local casterRoot = state.character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if casterRoot then
			state.casterFace, state.casterFaceAtt = makeBeamFaceAlign(casterRoot, "HexBeamCasterFace")
		end
	end
	if not state.victimFace then
		state.victimFace, state.victimFaceAtt = makeBeamFaceAlign(vRoot, "HexBeamVictimFace")
	end
	if not state.victimAnimTrack and state.victim.Parent then
		local victimTrack = playCharacterAnim(
			state.victim,
			GameConstants.HEX_BEAM_TARGET_ANIM,
			Enum.AnimationPriority.Action4
		)
		if victimTrack then
			victimTrack.Looped = true
		end
		state.victimAnimTrack = victimTrack
	end
end

local function startHexBeam(player: Player, targetModel: Model?, direction: Vector3, lockOn: boolean?)
	local character = player.Character
	if not character or beamByPlayer[player] then
		return
	end
	local entry = CharacterRegistry.getAbilityById("scarlet_witch", "hex_beam")
	if not entry then
		return
	end
	local hand = getRightHand(character)
	if not hand then
		return
	end

	local victim = resolveTarget(character, targetModel, direction, GameConstants.HEX_BEAM_RANGE, lockOn == true)
	if not victim then
		return
	end
	local victimRoot = getRootPart(victim)
	local victimHum = CombatHelper.getHumanoid(victim)
	local casterRoot = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not victimRoot or not victimHum or victimHum.Health <= 0 or not casterRoot then
		return
	end
	if (victimRoot.Position - casterRoot.Position).Magnitude >= GameConstants.HEX_BEAM_BREAK_DISTANCE then
		return
	end
	if not canUse(character, entry.id, entry.energyCost) then
		return
	end

	local startClone = cloneScarletInstance("HexBeam", "HexBeam")
	local endClone = cloneScarletInstance("HexBeam", "HexBeamEnd")
	if not (startClone and startClone:IsA("BasePart") and endClone and endClone:IsA("BasePart")) then
		refundEnergy(character, entry.energyCost)
		warn("[ScarletWitch] Missing HexBeam.HexBeam / HexBeam.HexBeamEnd BaseParts")
		return
	end

	AbilityCooldownHelper.setActive(character, entry.id, true)
	HandParticleHelper.beginUse(character, "Right")
	local animTrack = playCharacterAnim(character, GameConstants.HEX_BEAM_ANIM, Enum.AnimationPriority.Action4)
	if animTrack then
		animTrack.Looped = false
	end

	local startHost = startClone :: BasePart
	prepFxPart(startHost)
	startHost.Name = "HexBeam"
	startHost.Anchored = false
	startHost.Massless = true
	startHost.CFrame = CFrame.lookAt(hand.Position, victimRoot.Position)
	startHost.Parent = hand
	local handWeld = Instance.new("Weld")
	handWeld.Name = "HexBeamHandWeld"
	handWeld.Part0 = hand
	handWeld.Part1 = startHost
	handWeld.C0 = hand.CFrame:ToObjectSpace(startHost.CFrame)
	handWeld.Parent = startHost

	local startAtt = firstAttachment(startHost)
	if not startAtt then
		startAtt = Instance.new("Attachment")
		startAtt.Name = "HexBeamAttachment"
		startAtt.Parent = startHost
	end

	local tipHost = endClone :: BasePart
	prepFxPart(tipHost)
	tipHost.Name = "HexBeamEnd"
	local initialTip = hand.Position
	tipHost.CFrame = CFrame.lookAt(initialTip, victimRoot.Position)
	tipHost.Parent = workspace

	local endAtt = firstAttachment(tipHost)
	if not endAtt then
		endAtt = Instance.new("Attachment")
		endAtt.Name = "HexBeamEndAtt"
		endAtt.Parent = tipHost
	end

	local beams = collectBeams(startHost)
	for _, extra in collectBeams(tipHost) do
		local seen = false
		for _, b in beams do
			if b == extra then
				seen = true
				break
			end
		end
		if not seen then
			table.insert(beams, extra)
		end
	end
	if #beams == 0 then
		local created = Instance.new("Beam")
		created.Name = "HexBeam"
		created.Width0 = 1.4
		created.Width1 = 1.1
		created.FaceCamera = true
		created.LightEmission = 0.7
		created.Color = ColorSequence.new(VfxHelper.chaosColor())
		created.Attachment0 = startAtt
		created.Parent = startHost
		table.insert(beams, created)
	end
	for _, liveBeam in beams do
		liveBeam.Attachment0 = startAtt
		liveBeam.Attachment1 = endAtt
		liveBeam.Enabled = false
	end
	local beam = beams[1]

	VfxHelper.setParticlesEnabled(startHost, false)
	VfxHelper.setParticlesEnabled(tipHost, false)

	local hum = CombatHelper.getHumanoid(character)
	local walk = GameConstants.DEFAULT_WALK_SPEED
	local jumpPower: number? = nil
	local jumpHeight: number? = nil
	local casterAuto = true
	if hum then
		walk = hum.WalkSpeed
		casterAuto = hum.AutoRotate
		if hum.UseJumpPower then
			jumpPower = hum.JumpPower
		else
			jumpHeight = hum.JumpHeight
		end
	end

	local victimWalk = victimHum.WalkSpeed
	local victimJump: number? = if victimHum.UseJumpPower then victimHum.JumpPower else nil
	local victimAuto = victimHum.AutoRotate

	local casterFace: AlignOrientation? = nil
	local casterFaceAtt: Attachment? = nil
	local victimFace: AlignOrientation? = nil
	local victimFaceAtt: Attachment? = nil

	beamByPlayer[player] = {
		character = character,
		startHost = startHost,
		handWeld = handWeld,
		tipHost = tipHost,
		startAtt = startAtt,
		endAtt = endAtt,
		beam = beam,
		victim = victim,
		victimRoot = victimRoot,
		startedAt = os.clock(),
		smoothedTip = initialTip,
		lastHit = 0,
		launched = false,
		reached = false,
		abilityStartedAt = nil,
		walk = walk,
		jumpPower = jumpPower,
		jumpHeight = jumpHeight,
		casterAutoRotate = casterAuto,
		victimWalk = victimWalk,
		victimJump = victimJump,
		victimAutoRotate = victimAuto,
		casterFace = casterFace,
		casterFaceAtt = casterFaceAtt,
		victimFace = victimFace,
		victimFaceAtt = victimFaceAtt,
		animTrack = animTrack,
		victimAnimTrack = nil,
	}
	applyBeamMovement(beamByPlayer[player] :: BeamState)
	character:SetAttribute(GameConstants.BUSY_ATTRIBUTE, true)
	fireCameraShake(player, 0.32, 0.45, 0.2, 0.42)
end

local function moveToward(from: Vector3, to: Vector3, step: number): Vector3
	local delta = to - from
	if delta.Magnitude <= step then
		return to
	end
	return from + delta.Unit * step
end

local function lookFlat(root: BasePart): Vector3
	local pitch, yaw = root.CFrame:ToEulerAnglesYXZ()
	return CFrame.fromEulerAnglesYXZ(pitch, yaw, 0).LookVector
end

local function setBeamPartCFrame(part: BasePart, pos: Vector3, toward: Vector3)
	local delta = toward - pos
	if delta.Magnitude < 0.05 then
		part.CFrame = CFrame.new(pos) * part.CFrame.Rotation
		return
	end
	part.CFrame = CFrame.lookAt(pos, pos + delta.Unit)
end

local function endObjectHex(victim: Model)
	local state = objectHexByVictim[victim]
	if not state then
		return
	end
	objectHexByVictim[victim] = nil
	victim:SetAttribute(GameConstants.PROB_HEX_OBJECT_ATTRIBUTE, nil)
	victim:SetAttribute(GameConstants.POWERS_DISABLED_UNTIL, nil)
	if state.prop and state.prop.Parent then
		state.prop:Destroy()
	end
	VfxHelper.restoreCapturedParts(state.snaps, 0.25)
	NameplateService.setHidden(victim, false, 0.15)
	local hum = CombatHelper.getHumanoid(victim)
	if hum and hum.Parent then
		if state.displayType then
			hum.DisplayDistanceType = state.displayType
		end
		if state.walk ~= nil then
			hum.WalkSpeed = state.walk
		end
		if state.useJumpPower ~= nil then
			hum.UseJumpPower = state.useJumpPower
		end
		if state.jumpPower ~= nil then
			hum.JumpPower = state.jumpPower
		end
		if state.jumpHeight ~= nil then
			hum.JumpHeight = state.jumpHeight
		end
		if state.autoRotate ~= nil then
			hum.AutoRotate = state.autoRotate
		end
		if state.jumpingEnabled ~= nil then
			pcall(function()
				hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, state.jumpingEnabled)
			end)
		end
	end
	local root = getRootPart(victim)
	if root and root.Parent then
		root.AssemblyAngularVelocity = Vector3.zero
		local plr = Players:GetPlayerFromCharacter(victim)
		pcall(function()
			if plr then
				root:SetNetworkOwner(plr)
			else
				root:SetNetworkOwnershipAuto()
			end
		end)
	end
end

local function collectProbHexObjectTemplates(folder: Instance): { Instance }
	local templates: { Instance } = {}
	local function take(inst: Instance)
		if inst:IsA("Folder") then
			for _, child in inst:GetChildren() do
				take(child)
			end
		elseif inst:IsA("BasePart") or inst:IsA("Model") or inst:FindFirstChildWhichIsA("BasePart", true) then
			table.insert(templates, inst)
		end
	end
	for _, child in folder:GetChildren() do
		take(child)
	end
	return templates
end

local function applyObjectHex(victim: Model)
	endObjectHex(victim)
	local vRoot = getRootPart(victim)
	local folder = VfxHelper.getScarletAsset("ProbabilityHex", "Objects")
	if not vRoot or not folder then
		return false
	end
	local kids = collectProbHexObjectTemplates(folder)
	if #kids == 0 then
		return false
	end
	local template = kids[math.random(1, #kids)]
	local cloned = template:Clone()
	local prop: Instance = cloned
	if not cloned:IsA("BasePart") and not cloned:IsA("Model") then
		local wrapper = Instance.new("Model")
		wrapper.Name = "SwProbabilityObject"
		cloned.Parent = wrapper
		prop = wrapper
	end
	prop.Name = "SwProbabilityObject"
	-- Keep object upright; match only the victim's yaw facing.
	local _, yaw = vRoot.CFrame:ToEulerAnglesYXZ()
	local function harden(inst: Instance)
		if inst:IsA("BasePart") then
			inst.Anchored = false
			inst.CanCollide = false
			inst.CanQuery = false
			inst.CanTouch = false
			inst.Massless = true
		end
	end
	harden(prop)
	for _, desc in prop:GetDescendants() do
		harden(desc)
	end
	local primary: BasePart? = nil
	if prop:IsA("BasePart") then
		primary = prop
	elseif prop:IsA("Model") then
		local model = prop :: Model
		if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
			primary = model.PrimaryPart
		else
			primary = model:FindFirstChildWhichIsA("BasePart", true)
			if primary then
				model.PrimaryPart = primary
			end
		end
	end
	if not primary then
		prop:Destroy()
		return false
	end
	for _, desc in prop:GetDescendants() do
		if desc:IsA("BasePart") and desc ~= primary then
			local join = Instance.new("WeldConstraint")
			join.Name = "SwProbabilityObjectWeld"
			join.Part0 = primary
			join.Part1 = desc
			join.Parent = desc
		end
	end
	local at = CFrame.new(vRoot.Position) * CFrame.Angles(0, yaw, 0)
	if prop:IsA("Model") then
		(prop :: Model):PivotTo(at)
	else
		primary.CFrame = at
	end
	prop.Parent = workspace
	local weld = Instance.new("WeldConstraint")
	weld.Name = "SwProbabilityWeld"
	weld.Part0 = vRoot
	weld.Part1 = primary
	weld.Parent = primary
	local hum = CombatHelper.getHumanoid(victim)
	local displayType: Enum.HumanoidDisplayDistanceType? = if hum then hum.DisplayDistanceType else nil
	local walk: number? = if hum then hum.WalkSpeed else nil
	local jumpPower: number? = if hum then hum.JumpPower else nil
	local jumpHeight: number? = if hum then hum.JumpHeight else nil
	local useJumpPower: boolean? = if hum then hum.UseJumpPower else nil
	local autoRotate: boolean? = if hum then hum.AutoRotate else nil
	local jumpingEnabled: boolean? = nil
	if hum then
		jumpingEnabled = hum:GetStateEnabled(Enum.HumanoidStateType.Jumping)
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.WalkSpeed = 0
		hum.JumpPower = 0
		hum.JumpHeight = 0
		hum.AutoRotate = false
		hum:Move(Vector3.zero, false)
		pcall(function()
			hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		end)
	end
	vRoot.AssemblyLinearVelocity = Vector3.zero
	vRoot.AssemblyAngularVelocity = Vector3.zero
	pcall(function()
		vRoot:SetNetworkOwner(nil)
	end)
	victim:SetAttribute(GameConstants.PROB_HEX_OBJECT_ATTRIBUTE, true)
	victim:SetAttribute(GameConstants.SPRINTING_ATTRIBUTE, nil)
	NameplateService.setHidden(victim, true, 0.08)
	local snaps = VfxHelper.captureVisibleParts(victim)
	VfxHelper.hideCapturedParts(snaps)
	objectHexByVictim[victim] = {
		victim = victim,
		prop = prop,
		snaps = snaps,
		look = Vector3.new(math.sin(-yaw), 0, -math.cos(-yaw)),
		endsAt = os.clock() + GameConstants.PROB_HEX_EFFECT_TIME,
		displayType = displayType,
		walk = walk,
		jumpPower = jumpPower,
		jumpHeight = jumpHeight,
		useJumpPower = useJumpPower,
		autoRotate = autoRotate,
		jumpingEnabled = jumpingEnabled,
	}
	return true
end

local function spawnProbHexExplosion(victim: Model)
	local host = (victim:FindFirstChild("UpperTorso") or victim:FindFirstChild("Torso") or getRootPart(victim)) :: BasePart?
	local template = VfxHelper.getScarletAsset("ProbabilityHex", "ExplosionAttachment")
	if not host or not template then
		return
	end
	local fx = template:Clone()
	fx.Name = "SwProbabilityExplosion"
	VfxHelper.muteSounds(fx)
	if fx:IsA("Attachment") then
		fx.Parent = host
	else
		fx.Parent = host
	end
	VfxHelper.setParticlesEnabled(fx, true)
	VfxHelper.emitAllParticles(fx, 18)
	VfxHelper.retireFxSmooth(fx, 0.45, 2.8)
end

local function applyProbabilityHit(player: Player, attacker: Model, victim: Model): string?
	if not victim.Parent then
		return nil
	end
	spawnProbHexExplosion(victim)
	-- Exclusive outcomes: object OR power strip, never both.
	endObjectHex(victim)
	local wantsObject = math.random() < 0.5
	if wantsObject then
		if applyObjectHex(victim) then
			victim:SetAttribute(
				GameConstants.POWERS_DISABLED_UNTIL,
				AbilityCooldownHelper.getNow() + GameConstants.PROB_HEX_EFFECT_TIME
			)
			return "object"
		end
		-- Never silently replace the randomly selected object result with power stripping.
		warn("[ScarletWitch] Probability Hex selected object, but ProbabilityHex.Objects has no usable object")
		return nil
	end
	victim:SetAttribute(GameConstants.POWERS_DISABLED_UNTIL, AbilityCooldownHelper.getNow() + GameConstants.PROB_HEX_EFFECT_TIME)
	local victimRoot = getRootPart(victim)
	local attackerRoot = getRootPart(attacker)
	if victimRoot then
		local away = victimRoot.Position - (if attackerRoot then attackerRoot.Position else victimRoot.Position)
		local dir = if away.Magnitude > 0.05 then away.Unit else Vector3.new(0, 0, -1)
		RagdollStatus.applyTimed(victim, GameConstants.PROB_HEX_STRIP_RAGDOLL)
		PushHelper.applyToCharacter(victim, dir, {
			speed = GameConstants.PROB_HEX_STRIP_PUSH_SPEED,
			upBoost = GameConstants.PROB_HEX_STRIP_PUSH_UP,
		})
	end
	return "powers_stripped"
end

local function detachProbHexWelds(state: ProbBeamState)
	if state.handWeld and state.handWeld.Parent then
		state.handWeld:Destroy()
	end
	state.handWeld = nil
	if state.torsoWeld and state.torsoWeld.Parent then
		state.torsoWeld:Destroy()
	end
	state.torsoWeld = nil
	if state.startHost.Parent and state.startHost.Parent ~= workspace then
		local worldCf = state.startHost.CFrame
		state.startHost.Anchored = true
		state.startHost.Parent = workspace
		state.startHost.CFrame = worldCf
	end
	if state.tipHost.Parent and state.tipHost.Parent ~= workspace then
		local worldCf = state.tipHost.CFrame
		state.tipHost.Anchored = true
		state.tipHost.Parent = workspace
		state.tipHost.CFrame = worldCf
	end
end

local function weldProbTipToTorso(state: ProbBeamState, aimPart: BasePart)
	if state.torsoWeld and state.torsoWeld.Parent then
		return
	end
	state.tipHost.Anchored = false
	state.tipHost.CFrame = CFrame.lookAt(aimPart.Position, state.hand.Position)
	state.tipHost.Parent = aimPart
	local torsoWeld = Instance.new("Weld")
	torsoWeld.Name = "ProbHexTorsoWeld"
	torsoWeld.Part0 = aimPart
	torsoWeld.Part1 = state.tipHost
	torsoWeld.C0 = aimPart.CFrame:ToObjectSpace(state.tipHost.CFrame)
	torsoWeld.Parent = state.tipHost
	state.torsoWeld = torsoWeld
	state.aimPart = aimPart
end

local function lockProbHexCaster(hum: Humanoid)
	hum.WalkSpeed = 0
	hum.JumpPower = 0
	hum.UseJumpPower = true
	pcall(function()
		hum.JumpHeight = 0
	end)
	pcall(function()
		hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	end)
	hum:Move(Vector3.zero, false)
end

local function restoreProbHexCaster(state: ProbBeamState)
	local hum = CombatHelper.getHumanoid(state.character)
	if not hum or not hum.Parent then
		return
	end
	hum.WalkSpeed = state.walk
	hum.UseJumpPower = state.useJumpPower
	hum.JumpPower = state.jumpPower
	if state.jumpHeight ~= nil then
		hum.JumpHeight = state.jumpHeight
	end
	hum.AutoRotate = state.casterAutoRotate
	pcall(function()
		hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
	end)
	if state.character.Parent then
		state.character:SetAttribute(GameConstants.BUSY_ATTRIBUTE, nil)
	end
	HandParticleHelper.endUse(state.character, "Left")
end

local function stopProbabilityHex(player: Player, applyCooldown: boolean?, hitVictim: Model?)
	local state = probBeamByPlayer[player]
	if not state then
		return
	end
	probBeamByPlayer[player] = nil
	detachProbHexWelds(state)
	fadeOutBeamFx(state.startHost, state.tipHost, state.startAtt, state.endAtt, state.beam)
	restoreProbHexCaster(state)
	local victimHum = CombatHelper.getHumanoid(state.victim)
	if victimHum and victimHum.Parent then
		victimHum.AutoRotate = state.victimAutoRotate
		victimHum.WalkSpeed = state.victimWalk
		victimHum.UseJumpPower = state.victimUseJumpPower
		victimHum.JumpPower = state.victimJumpPower
		victimHum.JumpHeight = state.victimJumpHeight
	end
	local victimRoot = getRootPart(state.victim)
	if victimRoot and victimRoot.Parent then
		local victimPlayer = Players:GetPlayerFromCharacter(state.victim)
		pcall(function()
			if victimPlayer then
				victimRoot:SetNetworkOwner(victimPlayer)
			else
				victimRoot:SetNetworkOwnershipAuto()
			end
		end)
	end
	local outcome: string? = nil
	if hitVictim then
		outcome = applyProbabilityHit(player, state.character, hitVictim)
		if outcome then
			Remotes.getEvent("ProbabilityHexResult"):FireClient(player, {
				outcome = outcome,
				targetName = hitVictim.Name,
				duration = GameConstants.PROB_HEX_EFFECT_TIME,
			})
		end
	end
	local char = state.character
	if char.Parent then
		AbilityCooldownHelper.setActive(char, "probability_hex", false)
		if applyCooldown then
			local cooldownSeconds = GameConstants.PROB_HEX_COOLDOWN_OBJECT
			if outcome == "powers_stripped" then
				cooldownSeconds = GameConstants.PROB_HEX_COOLDOWN_STRIP
			end
			AbilityCooldownHelper.applyAfterUse(char, "probability_hex", cooldownSeconds)
		end
	end
end

local function smoothlyFace(root: BasePart, targetPosition: Vector3, dt: number)
	local flatTarget = Vector3.new(targetPosition.X, root.Position.Y, targetPosition.Z)
	if (flatTarget - root.Position).Magnitude < 0.05 then
		return
	end
	local goal = CFrame.lookAt(root.Position, flatTarget)
	root.CFrame = root.CFrame:Lerp(goal, math.clamp(dt * 7, 0, 1))
end

local function updateObjectHexes()
	local now = os.clock()
	local dying: { Model } = {}
	for victim, state in objectHexByVictim do
		local hum = CombatHelper.getHumanoid(victim)
		if now >= state.endsAt or not victim.Parent or not hum or hum.Health <= 0 then
			table.insert(dying, victim)
		else
			VfxHelper.hideCapturedParts(state.snaps)
			hum.WalkSpeed = 0
			hum.JumpPower = 0
			hum.JumpHeight = 0
			hum.AutoRotate = false
			hum:Move(Vector3.zero, false)
			local root = getRootPart(victim)
			if root then
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
			end
		end
	end
	for _, victim in dying do
		endObjectHex(victim)
	end
end

local function updateProbabilityHex(player: Player, dt: number)
	local state = probBeamByPlayer[player]
	if not state then
		return
	end
	local casterRoot = state.casterRoot
	if not state.character.Parent or not casterRoot.Parent or not state.hand.Parent then
		stopProbabilityHex(player, true, nil)
		return
	end
	local casterHum = CombatHelper.getHumanoid(state.character)
	if casterHum then
		lockProbHexCaster(casterHum)
	end

	local victim = state.victim
	local vRoot = getRootPart(victim)
	local vHum = CombatHelper.getHumanoid(victim)
	local victimOk = state.victimAlive
		and victim.Parent
		and vRoot ~= nil
		and vHum ~= nil
		and vHum.Health > 0

	if not victimOk and state.victimAlive then
		state.victimAlive = false
		if vRoot then
			state.lastEndPos = vRoot.Position
		end
		if state.torsoWeld and state.torsoWeld.Parent then
			state.lastEndPos = state.tipHost.Position
		end
		if state.launched and not state.reached and state.lastEndPos then
			state.reached = true
			state.channelStartedAt = os.clock()
			state.endPos = state.lastEndPos
		end
	end

	local now = os.clock()
	local aimPart = if victimOk then (getProbHexAimPart(victim) or vRoot) else nil
	local aimPos = if aimPart then aimPart.Position else (state.lastEndPos or state.endPos)

	if victimOk and aimPart then
		smoothlyFace(casterRoot, aimPart.Position, dt)
	elseif state.lastEndPos then
		smoothlyFace(casterRoot, state.lastEndPos, dt)
	end

	if state.handWeld and state.handWeld.Parent and not state.finishing then
		local lookTarget = aimPos
		local origin = state.hand.Position
		local look = if (lookTarget - origin).Magnitude > 0.08
			then CFrame.lookAt(origin, lookTarget)
			else CFrame.new(origin)
		state.handWeld.C0 = state.hand.CFrame:ToObjectSpace(look)
	end

	if not state.launched then
		state.startPos = state.hand.Position
		state.endPos = state.startPos
		if not state.finishing then
			setBeamPartCFrame(state.startHost, state.startPos, aimPos)
			setBeamPartCFrame(state.tipHost, state.endPos, aimPos)
		end
		if now - state.startedAt < GameConstants.PROB_HEX_START_DELAY then
			return
		end
		state.launched = true
		for _, liveBeam in state.beams do
			liveBeam.Enabled = true
		end
		VfxHelper.setParticlesEnabled(state.startHost, true)
		VfxHelper.setParticlesEnabled(state.tipHost, true)
		VfxHelper.emitAllParticles(state.startHost, 10)
		VfxHelper.emitAllParticles(state.tipHost, 10)
	end

	if not state.finishing then
		state.endPos = moveToward(state.endPos, aimPos, GameConstants.PROB_HEX_BEAM_SPEED * dt)
		state.lastEndPos = state.endPos
		if victimOk and aimPart and not state.reached and (state.endPos - aimPos).Magnitude <= GameConstants.PROB_HEX_REACH then
			state.reached = true
			state.channelStartedAt = now
			weldProbTipToTorso(state, aimPart)
			vHum.AutoRotate = false
			vHum.WalkSpeed = 0
			vHum.JumpPower = 0
			vHum.JumpHeight = 0
			vHum:Move(Vector3.zero, false)
			pcall(function()
				vRoot:SetNetworkOwner(nil)
			end)
			playCharacterAnim(victim, GameConstants.PROB_HEX_TARGET_ANIM, Enum.AnimationPriority.Action4)
		end
	end

	if not state.reached then
		if not state.finishing then
			setBeamPartCFrame(state.tipHost, state.endPos, state.hand.Position)
		end
		if now - state.startedAt >= 6 then
			stopProbabilityHex(player, true, nil)
		end
		return
	end

	if victimOk and vRoot and vHum then
		smoothlyFace(vRoot, casterRoot.Position, dt)
	end

	local elapsed = now - (state.channelStartedAt or now)
	if victimOk and vHum and vRoot and not state.finishing then
		local away = vRoot.Position - casterRoot.Position
		local flatAway = Vector3.new(away.X, 0, away.Z)
		if flatAway.Magnitude > 0.05 then
			local currentY = vRoot.AssemblyLinearVelocity.Y
			vRoot.AssemblyLinearVelocity =
				flatAway.Unit * GameConstants.PROB_HEX_PUSH_SPEED + Vector3.new(0, currentY, 0)
		end
		vHum.WalkSpeed = 0
		vHum.JumpPower = 0
		vHum.JumpHeight = 0
		vHum:Move(Vector3.zero, false)

		if elapsed < GameConstants.PROB_HEX_CHANNEL_TIME then
			state.damageAcc += dt
			if state.damageAcc >= 0.25 then
				local slice = state.damageAcc
				state.damageAcc = 0
				CombatHelper.dealDamage(
					state.character,
					victim,
					GameConstants.PROB_HEX_DAMAGE_PER_SEC * slice,
					vRoot.Position,
					"hex"
				)
			end
		end
	end

	if elapsed >= GameConstants.PROB_HEX_CHANNEL_TIME and not state.finishing then
		state.finishing = true
		if victimOk and vRoot then
			vRoot.AssemblyLinearVelocity = Vector3.new(0, vRoot.AssemblyLinearVelocity.Y, 0)
		end
		state.endPos = if state.torsoWeld and state.tipHost.Parent then state.tipHost.Position else (state.lastEndPos or state.endPos)
		state.startPos = state.startHost.Position
		detachProbHexWelds(state)
	end

	if state.finishing then
		state.startPos = moveToward(state.startPos, state.endPos, GameConstants.PROB_HEX_BEAM_SPEED * dt)
		setBeamPartCFrame(state.startHost, state.startPos, state.endPos)
		setBeamPartCFrame(state.tipHost, state.endPos, state.startPos)
		if (state.startPos - state.endPos).Magnitude <= GameConstants.PROB_HEX_REACH then
			stopProbabilityHex(player, true, if victimOk then victim else nil)
		end
	end
end

local function castProbabilityHex(player: Player, targetModel: Model?, direction: Vector3)
	local character = player.Character
	if not character or probBeamByPlayer[player] then
		return
	end
	local entry = CharacterRegistry.getAbilityById("scarlet_witch", "probability_hex")
	if not entry then
		return
	end
	local victim = resolveTarget(character, targetModel, direction, GameConstants.PROB_HEX_RANGE, true)
	if not victim then
		return
	end
	local vRoot = getRootPart(victim)
	local hand = getLeftHand(character) or getRightHand(character)
	local casterRoot = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local casterHum = CombatHelper.getHumanoid(character)
	local victimHum = CombatHelper.getHumanoid(victim)
	if not vRoot or not hand or not casterRoot or not casterHum or not victimHum then
		return
	end
	if not canUse(character, entry.id, entry.energyCost) then
		return
	end
	local startClone = cloneScarletInstance("HexBeam", "HexBeam")
	local endClone = cloneScarletInstance("HexBeam", "HexBeamEnd")
	if not (startClone and startClone:IsA("BasePart") and endClone and endClone:IsA("BasePart")) then
		refundEnergy(character, entry.energyCost)
		warn("[ScarletWitch] Missing HexBeam.HexBeam / HexBeam.HexBeamEnd for Probability Hex")
		return
	end

	AbilityCooldownHelper.setActive(character, entry.id, true)
	character:SetAttribute(GameConstants.BUSY_ATTRIBUTE, true)
	HandParticleHelper.beginUse(character, "Left")
	playCharacterAnim(character, GameConstants.PROB_HEX_CASTER_ANIM, Enum.AnimationPriority.Action4)
	fireCameraShake(player, 0.36, 0.4, 0.36, 0.45)
	local casterAutoRotate = casterHum.AutoRotate
	local casterWalk = casterHum.WalkSpeed
	local casterJumpPower = casterHum.JumpPower
	local casterJumpHeight = casterHum.JumpHeight
	local casterUseJumpPower = casterHum.UseJumpPower
	local victimAutoRotate = victimHum.AutoRotate
	local victimWalk = victimHum.WalkSpeed
	local victimJumpPower = victimHum.JumpPower
	local victimJumpHeight = victimHum.JumpHeight
	local victimUseJumpPower = victimHum.UseJumpPower
	casterHum.AutoRotate = false
	lockProbHexCaster(casterHum)

	local origin = hand.Position
	local aimPart = getProbHexAimPart(victim) or vRoot
	local startHost = startClone :: BasePart
	prepFxPart(startHost)
	startHost.Name = "ProbHexBeam"
	startHost.Anchored = false
	startHost.CFrame = CFrame.lookAt(origin, aimPart.Position)
	startHost.Parent = hand
	local handWeld = Instance.new("Weld")
	handWeld.Name = "ProbHexHandWeld"
	handWeld.Part0 = hand
	handWeld.Part1 = startHost
	handWeld.C0 = hand.CFrame:ToObjectSpace(startHost.CFrame)
	handWeld.Parent = startHost

	local startAtt = firstAttachment(startHost)
	if not startAtt then
		startAtt = Instance.new("Attachment")
		startAtt.Name = "ProbHexStartAtt"
		startAtt.Parent = startHost
	end

	local tipHost = endClone :: BasePart
	prepFxPart(tipHost)
	tipHost.Name = "ProbHexBeamEnd"
	tipHost.CFrame = CFrame.lookAt(origin, aimPart.Position)
	tipHost.Parent = workspace

	local endAtt = firstAttachment(tipHost)
	if not endAtt then
		endAtt = Instance.new("Attachment")
		endAtt.Name = "ProbHexEndAtt"
		endAtt.Parent = tipHost
	end

	local beams = collectBeams(startHost)
	for _, extra in collectBeams(tipHost) do
		local seen = false
		for _, b in beams do
			if b == extra then
				seen = true
				break
			end
		end
		if not seen then
			table.insert(beams, extra)
		end
	end
	if #beams == 0 then
		local created = Instance.new("Beam")
		created.Name = "ProbHexBeam"
		created.Width0 = 1.4
		created.Width1 = 1.1
		created.FaceCamera = true
		created.LightEmission = 0.7
		created.Color = ColorSequence.new(VfxHelper.chaosColor())
		created.Attachment0 = startAtt
		created.Parent = startHost
		table.insert(beams, created)
	end
	for _, liveBeam in beams do
		liveBeam.Attachment0 = startAtt
		liveBeam.Attachment1 = endAtt
		liveBeam.Enabled = false
	end
	VfxHelper.setParticlesEnabled(startHost, false)
	VfxHelper.setParticlesEnabled(tipHost, false)

	probBeamByPlayer[player] = {
		character = character,
		victim = victim,
		hand = hand,
		casterRoot = casterRoot,
		startHost = startHost,
		tipHost = tipHost,
		startAtt = startAtt,
		endAtt = endAtt,
		beam = beams[1],
		beams = beams,
		startPos = origin,
		endPos = origin,
		startedAt = os.clock(),
		launched = false,
		channelStartedAt = nil,
		reached = false,
		finishing = false,
		damageAcc = 0,
		casterAutoRotate = casterAutoRotate,
		victimAutoRotate = victimAutoRotate,
		victimWalk = victimWalk,
		victimJumpPower = victimJumpPower,
		victimJumpHeight = victimJumpHeight,
		victimUseJumpPower = victimUseJumpPower,
		handWeld = handWeld,
		torsoWeld = nil,
		aimPart = aimPart,
		walk = casterWalk,
		jumpPower = casterJumpPower,
		jumpHeight = casterJumpHeight,
		useJumpPower = casterUseJumpPower,
		victimAlive = true,
		lastEndPos = aimPart.Position,
	}
end

-- Shield: PartialShieldAttachment bursts toward hits (no visible bubble / no runes)

local function updateShieldHpUi(state: ShieldState)
	local ratio = if state.maxHp > 0 then math.clamp(state.hp / state.maxHp, 0, 1) else 0
	state.hpLabel.Text = string.format("%d/%d", math.ceil(state.hp), state.maxHp)
	state.hpFill.Size = UDim2.new(ratio, 0, 1, 0)
	if state.character.Parent then
		state.character:SetAttribute(GameConstants.SHIELD_HP_ATTRIBUTE, state.hp)
	end
end

local function createShieldHpBillboard(character: Model): (BillboardGui, TextLabel, Frame)
	local head = character:FindFirstChild("Head")
	local gui = Instance.new("BillboardGui")
	gui.Name = "ShieldHealthGui"
	gui.Size = GameConstants.SHIELD_UI_SIZE
	gui.StudsOffset = GameConstants.SHIELD_UI_OFFSET
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = GameConstants.NAMEPLATE_MAX_DISTANCE
	if head and head:IsA("BasePart") then
		gui.Adornee = head
	end
	gui.Parent = character

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Size = UDim2.fromScale(1, 1)
	track.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
	track.BorderSizePixel = 0
	track.Parent = gui

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(0.2, 0)
	trackCorner.Parent = track

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(190, 55, 90)
	fill.BorderSizePixel = 0
	fill.Parent = track

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0.2, 0)
	fillCorner.Parent = fill

	local hpLabel = Instance.new("TextLabel")
	hpLabel.Name = "HpLabel"
	hpLabel.Size = UDim2.fromScale(1, 1)
	hpLabel.BackgroundTransparency = 1
	hpLabel.Font = Enum.Font.Bangers
	hpLabel.Text = "0/0"
	hpLabel.TextColor3 = Color3.fromRGB(245, 245, 248)
	hpLabel.TextScaled = true
	hpLabel.TextStrokeTransparency = 0.35
	hpLabel.ZIndex = 2
	hpLabel.Parent = track

	local textConstraint = Instance.new("UITextSizeConstraint")
	textConstraint.MaxTextSize = 18
	textConstraint.MinTextSize = 8
	textConstraint.Parent = hpLabel

	return gui, hpLabel, fill
end

local function disablePartialEmitters(shell: BasePart)
	VfxHelper.setParticlesEnabled(shell, false)
end

local function retirePartialShield(shell: BasePart)
	if not shell.Parent then
		return
	end
	disablePartialEmitters(shell)
	task.delay(GameConstants.SHIELD_PARTIAL_DELETE_DELAY, function()
		if shell.Parent then
			shell:Destroy()
		end
	end)
end

local function clearAllPartialShields(state: ShieldState)
	for _, shell in state.activePartials do
		if shell.Parent then
			retirePartialShield(shell)
		end
	end
	table.clear(state.activePartials)
end

local function spawnPartialShieldBurst(state: ShieldState, hitFrom: Vector3)
	local root = state.root
	if not root.Parent then
		return
	end

	local shell = VfxHelper.spawnPartialShieldShell(root, hitFrom, 10)
	if not shell then
		return
	end

	task.defer(function()
		if shell.Parent then
			VfxHelper.emitAllParticles(shell, 10)
		end
	end)

	table.insert(state.activePartials, shell)

	local char = state.character
	if char.Parent then
		Remotes.getUnreliableEvent("ShieldPartialHit"):FireAllClients(char, hitFrom)
	end

	state.partialToken += 1
	local token = state.partialToken
	local shellRef = shell

	task.delay(GameConstants.SHIELD_PARTIAL_EMIT_TIME, function()
		if not shellRef.Parent then
			return
		end
		disablePartialEmitters(shellRef)
		task.delay(GameConstants.SHIELD_PARTIAL_DELETE_DELAY, function()
			if shellRef.Parent then
				shellRef:Destroy()
			end
			for i = #state.activePartials, 1, -1 do
				if state.activePartials[i] == shellRef then
					table.remove(state.activePartials, i)
					break
				end
			end
		end)
		_ = token
	end)
end

local function stopShield(player: Player, applyCooldown: boolean?)
	local state = shieldByPlayer[player]
	if not state then
		return
	end
	shieldByPlayer[player] = nil

	if state.animTrack then
		state.animTrack:Stop(0.2)
		state.animTrack:Destroy()
		state.animTrack = nil
	end

	local char = state.character
	if char.Parent then
		char:SetAttribute(GameConstants.SHIELD_ACTIVE_ATTRIBUTE, nil)
		char:SetAttribute(GameConstants.SHIELD_HP_ATTRIBUTE, nil)
		char:SetAttribute(GameConstants.BUSY_ATTRIBUTE, nil)
		AbilityCooldownHelper.setActive(char, "hex_shield", false)
		HandParticleHelper.endUse(char)
		local hum = CombatHelper.getHumanoid(char)
		if hum then
			hum.WalkSpeed = state.walk
			hum.AutoRotate = state.autoRotate
			if state.jumpPower ~= nil then
				hum.JumpPower = state.jumpPower
			end
			if state.jumpHeight ~= nil then
				pcall(function()
					hum.JumpHeight = state.jumpHeight :: number
				end)
			end
		end
		if applyCooldown then
			local entry = CharacterRegistry.getAbilityById("scarlet_witch", "hex_shield")
			if entry then
				AbilityCooldownHelper.applyAfterUse(char, entry.id, entry.cooldown)
			end
		end
	end

	if state.billboard.Parent then
		state.billboard:Destroy()
	end
	if state.visual and state.visual.Parent then
		VfxHelper.retireFxSmooth(state.visual, 0.45, 2.4)
	end
	clearAllPartialShields(state)
end

local function startShield(player: Player)
	local character = player.Character
	if not character or shieldByPlayer[player] then
		return
	end
	if TelekinesisService.isActive(player) then
		return
	end
	if regenByPlayer[player] then
		return
	end
	local entry = CharacterRegistry.getAbilityById("scarlet_witch", "hex_shield")
	if not entry then
		return
	end
	if CombatHelper.arePowersDisabled(character) then
		return
	end
	if AbilityCooldownHelper.isOnCooldown(character, entry.id) then
		return
	end
	if not trySpendEnergy(character, entry.energyCost) then
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	AbilityCooldownHelper.setActive(character, entry.id, true)
	HandParticleHelper.beginUse(character)
	character:SetAttribute(GameConstants.SHIELD_ACTIVE_ATTRIBUTE, true)
	fireCameraShake(player, 0.28, 0.4, 0.16, 0.38)

	local maxHp = GameConstants.SHIELD_MAX_HP
	character:SetAttribute(GameConstants.SHIELD_HP_ATTRIBUTE, maxHp)

	local visual: Instance? = nil
	local template = VfxHelper.getScarletAsset("HexShield", "Shield") or VfxHelper.getScarletAsset("Shield")
	if template then
		visual = template:Clone()
		visual.Name = "HexShield"
		local function prep(part: BasePart)
			part.Anchored = false
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = true
		end
		local shieldPart: BasePart? = nil
		if visual:IsA("BasePart") then
			prep(visual)
			shieldPart = visual
			visual.Parent = character
		else
			visual.Parent = character
			if visual:IsA("Model") then
				visual:PivotTo(root.CFrame)
			end
			local primary = if visual:IsA("Model")
				then (visual.PrimaryPart or visual:FindFirstChildWhichIsA("BasePart", true))
				else visual:FindFirstChildWhichIsA("BasePart", true)
			if primary and primary:IsA("BasePart") then
				for _, desc in visual:GetDescendants() do
					if desc:IsA("BasePart") then
						prep(desc)
					end
				end
				prep(primary)
				shieldPart = primary
			end
		end
		if shieldPart then
			local weld = Instance.new("Weld")
			weld.Name = "HexShieldWeld"
			weld.Part0 = root
			weld.Part1 = shieldPart
			-- Centered on the character. Mesh is authored flat / +Y; stand it up, then yaw 180.
			weld.C0 = CFrame.Angles(0, math.rad(180), 0) * CFrame.Angles(math.rad(-90), 0, 0)
			weld.Parent = shieldPart
		end
		VfxHelper.setParticlesEnabled(visual, true)
		VfxHelper.emitAllParticles(visual, 12)
	else
		warn("[ScarletWitch] Missing Assets.ScarletWitchClassic.HexShield.Shield")
	end

	local billboard, hpLabel, hpFill = createShieldHpBillboard(character)

	local hum = CombatHelper.getHumanoid(character)
	local walk = GameConstants.DEFAULT_WALK_SPEED
	local jumpPower: number? = nil
	local jumpHeight: number? = nil
	local autoRotate = true
	if hum then
		walk = hum.WalkSpeed
		autoRotate = hum.AutoRotate
		jumpPower = hum.JumpPower
		pcall(function()
			jumpHeight = hum.JumpHeight
		end)
		hum.WalkSpeed = 0
		hum.JumpPower = 0
		hum.UseJumpPower = true
		pcall(function()
			hum.JumpHeight = 0
		end)
		hum:Move(Vector3.zero, false)
	end
	character:SetAttribute(GameConstants.BUSY_ATTRIBUTE, true)

	local animTrack = playCharacterAnim(character, GameConstants.SHIELD_ANIM, Enum.AnimationPriority.Action4)
	if animTrack then
		animTrack.Looped = true
	end

	local state: ShieldState = {
		character = character,
		root = root,
		visual = visual,
		activePartials = {},
		partialToken = 0,
		hp = maxHp,
		maxHp = maxHp,
		billboard = billboard,
		hpLabel = hpLabel,
		hpFill = hpFill,
		walk = walk,
		jumpPower = jumpPower,
		jumpHeight = jumpHeight,
		autoRotate = autoRotate,
		animTrack = animTrack,
	}
	updateShieldHpUi(state)
	shieldByPlayer[player] = state
end

function ScarletWitchService.damageShield(player: Player, amount: number, hitFrom: Vector3?): boolean
	local state = shieldByPlayer[player]
	if not state then
		return false
	end
	state.hp = math.max(0, state.hp - amount)
	updateShieldHpUi(state)
	if state.hp <= 0 then
		stopShield(player, true)
	end
	return true
end

function ScarletWitchService.damageShieldForCharacter(character: Model, amount: number, hitFrom: Vector3?): boolean
	local plr = Players:GetPlayerFromCharacter(character)
	if not plr then
		return false
	end
	return ScarletWitchService.damageShield(plr, amount, hitFrom)
end

local function applyHexTeleportExplosion(attacker: Model, origin: Vector3)
	local near = CombatHelper.overlapCharacters(origin, GameConstants.HEX_TELEPORT_EXPLOSION_RADIUS, attacker)
	if #near == 0 then
		return
	end
	local blastTime = GameConstants.HEX_TELEPORT_BLAST_TIME
	local tickSec = 0.12
	local slices = math.max(1, math.floor(blastTime / tickSec + 0.5))
	local damageSlice = GameConstants.HEX_TELEPORT_EXPLOSION_DAMAGE / slices
	task.spawn(function()
		local t0 = os.clock()
		local lastTick = t0
		local ticksLeft = slices
		while os.clock() - t0 < blastTime do
			for _, victim in near do
				if not victim.Parent then
					continue
				end
				local victimRoot = getRootPart(victim)
				if not victimRoot then
					continue
				end
				local push = victimRoot.Position - origin
				local away = Vector3.new(push.X, 0, push.Z)
				if away.Magnitude < 0.05 then
					away = Vector3.new(0, 0, -1)
				else
					away = away.Unit
				end
				PushHelper.applyToCharacter(victim, away, {
					speed = GameConstants.HEX_BEAM_PUSH_SPEED,
					upBoost = GameConstants.HEX_BEAM_PUSH_UP,
					impulseMult = 0.28,
				})
				local vel = victimRoot.AssemblyLinearVelocity
				victimRoot.AssemblyLinearVelocity = Vector3.new(
					away.X * GameConstants.HEX_BEAM_PUSH_SPEED,
					math.max(vel.Y, GameConstants.HEX_BEAM_PUSH_UP),
					away.Z * GameConstants.HEX_BEAM_PUSH_SPEED
				)
			end
			if os.clock() - lastTick >= tickSec and ticksLeft > 1 then
				lastTick = os.clock()
				ticksLeft -= 1
				for _, victim in near do
					if victim.Parent then
						CombatHelper.dealDamage(attacker, victim, damageSlice, origin, "explosion")
					end
				end
			end
			task.wait()
		end
		for _, victim in near do
			if not victim.Parent then
				continue
			end
			if ticksLeft > 0 then
				CombatHelper.dealDamage(attacker, victim, damageSlice * ticksLeft, origin, "explosion")
			end
			RagdollStatus.applyTimed(victim, GameConstants.HEX_TELEPORT_EXPLOSION_RAGDOLL)
			local victimRoot = getRootPart(victim)
			if victimRoot then
				local push = victimRoot.Position - origin
				if push.Magnitude < 0.05 then
					push = Vector3.new(0, 0, -1)
				end
				PushHelper.applyToCharacter(victim, push.Unit, {
					speed = GameConstants.HEX_TELEPORT_EXPLOSION_PUSH_SPEED,
					upBoost = GameConstants.HEX_TELEPORT_EXPLOSION_PUSH_UP,
				})
			end
		end
	end)
end

-- Teleportation (aim → click confirm)

local function clearWandaTeleportAim(character: Model?)
	if not character or not character.Parent then
		return
	end
	character:SetAttribute(GameConstants.TELEPORT_AIMING_ATTRIBUTE, nil)
	AbilityCooldownHelper.setActive(character, "hex_displacement", false)
end

local function beginWandaTeleportAim(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local entry = CharacterRegistry.getAbilityById("scarlet_witch", "hex_displacement")
	if not entry then
		return
	end
	if AbilityCooldownHelper.isOnCooldown(character, entry.id) then
		return
	end
	if CombatHelper.arePowersDisabled(character) or character:GetAttribute(GameConstants.BUSY_ATTRIBUTE) == true then
		return
	end
	if character:GetAttribute(GameConstants.TK_ACTIVE_ATTRIBUTE) == true then
		return
	end
	if character:GetAttribute(GameConstants.SHIELD_ACTIVE_ATTRIBUTE) == true then
		return
	end
	if character:GetAttribute(GameConstants.IS_FLYING_ATTRIBUTE) == true then
		return
	end
	if character:GetAttribute(GameConstants.TELEPORT_AIMING_ATTRIBUTE) == true then
		clearWandaTeleportAim(character)
		return
	end
	character:SetAttribute(GameConstants.TELEPORT_AIMING_ATTRIBUTE, true)
	AbilityCooldownHelper.setActive(character, entry.id, true)
end

local function castTeleport(player: Player, direction: Vector3, aimPoint: Vector3?)
	local character = player.Character
	if not character then
		return
	end
	local entry = CharacterRegistry.getAbilityById("scarlet_witch", "hex_displacement")
	if not entry then
		return
	end

	local wasAiming = character:GetAttribute(GameConstants.TELEPORT_AIMING_ATTRIBUTE) == true
	if not wasAiming then
		return
	end

	if AbilityCooldownHelper.isOnCooldown(character, entry.id) then
		clearWandaTeleportAim(character)
		return
	end
	if CombatHelper.arePowersDisabled(character) then
		clearWandaTeleportAim(character)
		return
	end
	if not CharacterService.spendEnergy(character, entry.energyCost) then
		clearWandaTeleportAim(character)
		return
	end
	local owner = Players:GetPlayerFromCharacter(character)
	if owner then
		spendControl(owner, character, GameConstants.SW_CONTROL_CAST_COST)
	end

	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		clearWandaTeleportAim(character)
		return
	end

	local fromPos = root.Position
	local dest: Vector3
	if aimPoint then
		local offset = aimPoint - fromPos
		if offset.Magnitude > GameConstants.TELEPORT_RANGE then
			offset = offset.Unit * GameConstants.TELEPORT_RANGE
		end
		dest = fromPos + offset
	else
		local dir = if direction.Magnitude > 0.01 then direction.Unit else root.CFrame.LookVector
		dest = fromPos + dir * math.min(GameConstants.TELEPORT_RANGE, 40)
	end
	local fromFx = VfxHelper.snapToFloor(fromPos, { character })
	local destFx = VfxHelper.snapToFloor(dest, { character })

	character:SetAttribute(GameConstants.TELEPORT_AIMING_ATTRIBUTE, nil)
	AbilityCooldownHelper.setActive(character, entry.id, true)
	HandParticleHelper.beginUse(character)
	character:SetAttribute(GameConstants.BUSY_ATTRIBUTE, true)

	local hum = CombatHelper.getHumanoid(character)
	local savedWalk = if hum then hum.WalkSpeed else GameConstants.DEFAULT_WALK_SPEED
	local savedJump = if hum then hum.JumpPower else 50
	if hum then
		hum.WalkSpeed = 0
		hum.JumpPower = 0
		hum:Move(Vector3.zero, false)
	end

	local fromMark = VfxHelper.spawnHexTeleportMark(fromFx)
	local destMark = VfxHelper.spawnHexTeleportMark(destFx)
	VfxHelper.playWorldSound(GameConstants.HEX_TELEPORT_SOUND, fromFx, 1.05)
	fireCameraShake(player, 0.38, 0.55, 0.24, 0.5)
	local camEvent = Remotes.getEvent("HexDisplacementCam")
	local camRide: BasePart? = nil

	local function clearCam()
		camEvent:FireClient(player, nil)
		if camRide then
			local ride = camRide
			camRide = nil
			if ride.Parent then
				ride:Destroy()
			end
		end
	end

	local function finishMove(captured: any)
		if not character.Parent or not root.Parent then
			clearCam()
			HandParticleHelper.endUse(character)
			return
		end
		root.CFrame = CFrame.new(dest) * (root.CFrame - root.CFrame.Position)
		if hum and hum.Parent then
			hum.WalkSpeed = savedWalk
			hum.JumpPower = savedJump
		end
		applyHexTeleportExplosion(character, destFx)
		fireCameraShake(player, 0.48, 0.42, 0.3, 0.55)
		-- Restore camera only after the character is at the destination.
		clearCam()
		VfxHelper.restoreCapturedParts(captured, GameConstants.TELEPORT_FADE * 0.55, function()
			if character.Parent then
				character:SetAttribute(GameConstants.BUSY_ATTRIBUTE, nil)
				finishAbility(character, entry.id, entry.cooldown)
				HandParticleHelper.endUse(character)
			end
		end)
		VfxHelper.retireFxSmooth(fromMark, 0.5, GameConstants.HEX_TELEPORT_FX_LIFE)
		VfxHelper.retireFxSmooth(destMark, 0.5, GameConstants.HEX_TELEPORT_FX_LIFE)
	end

	task.delay(0.18, function()
		if not character.Parent or not root.Parent then
			clearCam()
			return
		end
		local captured = VfxHelper.captureVisibleParts(character)
		VfxHelper.hideCapturedParts(captured)
		local _mover, ride = VfxHelper.playHexTeleportTravel(fromFx, destFx, function()
			finishMove(captured)
		end)
		camRide = ride
		if ride then
			camEvent:FireClient(player, ride, destFx)
		end
	end)
end

-- Regeneration (hold)

local function stopRegen(player: Player, applyCooldown: boolean?)
	local state = regenByPlayer[player]
	if not state then
		return
	end
	regenByPlayer[player] = nil

	local char = state.character
	VfxHelper.fadeOutAndDestroyParticles(state.particles, GameConstants.REGEN_PARTICLE_FADE, 3)

	if char.Parent then
		AbilityCooldownHelper.setActive(char, "regeneration", false)
		HandParticleHelper.endUse(char)
		if applyCooldown then
			local entry = CharacterRegistry.getAbilityById("scarlet_witch", "regeneration")
			if entry then
				AbilityCooldownHelper.applyAfterUse(char, entry.id, entry.cooldown)
			end
		end
	end
end

local function startRegen(player: Player)
	local character = player.Character
	if not character or regenByPlayer[player] then
		return
	end
	if HexFlightService.isFlying(player) or TelekinesisService.isActive(player) or shieldByPlayer[player] then
		return
	end
	local entry = CharacterRegistry.getAbilityById("scarlet_witch", "regeneration")
	if not entry then
		return
	end
	if CombatHelper.arePowersDisabled(character) then
		return
	end
	if AbilityCooldownHelper.isOnCooldown(character, entry.id) then
		return
	end
	if AbilityCooldownHelper.isActive(character, entry.id) then
		return
	end

	local energy = character:GetAttribute(GameConstants.ENERGY_ATTRIBUTE)
	if type(energy) ~= "number" or energy < 5 then
		return
	end

	AbilityCooldownHelper.setActive(character, entry.id, true)
	HandParticleHelper.beginUse(character)
	CharacterService.markAbilityUse(character)
	fireCameraShake(player, 0.26, 0.5, 0.14, 0.36)

	local particles = VfxHelper.attachTelekinesisParticles(character)
	regenByPlayer[player] = {
		character = character,
		particles = particles,
	}
end

-- Disintegration: living targets under 10% HP, or Interactable props

local function dissolveInteractable(target: Instance, onDone: () -> ())
	if target:IsA("Model") then
		local pivot = target:GetPivot().Position
		VfxHelper.spawnImpact(pivot, VfxHelper.chaosColor(), 4)
		VfxHelper.fadePartsByHeight(target, 1, GameConstants.DISINTEGRATE_DURATION, true, function()
			if target.Parent then
				target:Destroy()
			end
			onDone()
		end)
	elseif target:IsA("BasePart") then
		VfxHelper.spawnImpact(target.Position, VfxHelper.chaosColor(), 4)
		TweenService:Create(
			target,
			TweenInfo.new(GameConstants.DISINTEGRATE_DURATION, Enum.EasingStyle.Sine),
			{ Transparency = 1, Size = target.Size * 0.2 }
		):Play()
		task.delay(GameConstants.DISINTEGRATE_DURATION, function()
			if target.Parent then
				target:Destroy()
			end
			onDone()
		end)
	else
		onDone()
	end
end

local function getUltimateMode(character: Model): string
	local mode = character:GetAttribute(GameConstants.ULTIMATE_MODE_ATTRIBUTE)
	if mode == "Absorption" then
		return "Absorption"
	end
	return "Disintegration"
end

local function cleanupAbsorbBeams(beams: { AbsorbBeamFx })
	for _, fx in beams do
		if fx.beam then
			fx.beam.Enabled = false
		end
		-- Smoothly fade particle rates, then keep disabled until delayed delete
		VfxHelper.smoothDisableParticles(fx.startAtt, GameConstants.ABSORB_PARTICLE_FADE)
		VfxHelper.smoothDisableParticles(fx.endAtt, GameConstants.ABSORB_PARTICLE_FADE)
		task.delay(GameConstants.ABSORB_PARTICLE_FADE, function()
			for _, desc in fx.startAtt:GetDescendants() do
				if desc:IsA("ParticleEmitter") then
					desc.Enabled = false
				end
			end
			for _, desc in fx.endAtt:GetDescendants() do
				if desc:IsA("ParticleEmitter") then
					desc.Enabled = false
				end
			end
		end)
		task.delay(GameConstants.ABSORB_PARTICLE_DELETE_DELAY, function()
			if fx.startAtt.Parent then
				fx.startAtt:Destroy()
			end
			if fx.endAtt.Parent then
				fx.endAtt:Destroy()
			end
			if fx.travelHost and fx.travelHost.Parent then
				fx.travelHost:Destroy()
			end
		end)
	end
end

local function destroyAbsorbConstraints(state: AbsorbState)
	if state.liftAlign and state.liftAlign.Parent then
		state.liftAlign:Destroy()
	end
	if state.liftAtt and state.liftAtt.Parent then
		state.liftAtt:Destroy()
	end
	if state.casterFace and state.casterFace.Parent then
		state.casterFace:Destroy()
	end
	if state.targetFace and state.targetFace.Parent then
		state.targetFace:Destroy()
	end
	if state.casterFaceAtt and state.casterFaceAtt.Parent then
		state.casterFaceAtt:Destroy()
	end
	if state.targetFaceAtt and state.targetFaceAtt.Parent then
		state.targetFaceAtt:Destroy()
	end
	state.liftAlign = nil
	state.liftAtt = nil
	state.casterFace = nil
	state.targetFace = nil
	state.casterFaceAtt = nil
	state.targetFaceAtt = nil
end

local function createAbsorbFaceAlign(root: BasePart, name: string): (AlignOrientation, Attachment)
	local att = Instance.new("Attachment")
	att.Name = name .. "Att"
	att.Parent = root
	local align = Instance.new("AlignOrientation")
	align.Name = name
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = att
	align.MaxTorque = math.huge
	align.Responsiveness = 16
	align.CFrame = root.CFrame
	align.Parent = root
	return align, att
end

local function createAbsorbLift(root: BasePart, pos: Vector3): (AlignPosition, Attachment)
	local att = Instance.new("Attachment")
	att.Name = "AbsorbLiftAtt"
	att.Parent = root
	local align = Instance.new("AlignPosition")
	align.Name = "AbsorbLiftAlign"
	align.Mode = Enum.PositionAlignmentMode.OneAttachment
	align.Attachment0 = att
	align.ApplyAtCenterOfMass = true
	align.RigidityEnabled = false
	align.Responsiveness = 8 -- smoother lift
	align.MaxForce = 1e6
	align.MaxVelocity = 18
	align.Position = pos
	align.Parent = root
	return align, att
end

local function stopPowerAbsorb(player: Player, applyCooldown: boolean?)
	local state = absorbByPlayer[player]
	if not state then
		return
	end
	absorbByPlayer[player] = nil
	cleanupAbsorbBeams(state.beams)
	destroyAbsorbConstraints(state)

	if state.targetHum.Parent then
		state.targetHum.WalkSpeed = state.prevTargetWalk
		state.targetHum.JumpPower = state.prevTargetJump
		state.targetHum.AutoRotate = state.prevTargetAutoRotate
	end
	if state.casterHum.Parent then
		state.casterHum.AutoRotate = state.prevCasterAutoRotate
	end

	local char = state.character
	if char.Parent then
		char:SetAttribute("AbsorbActive", nil)
		AbilityCooldownHelper.setActive(char, "ultimate", false)
		HandParticleHelper.endUse(char)
		if applyCooldown then
			local entry = CharacterRegistry.getAbilityById("scarlet_witch", "ultimate")
			if entry then
				AbilityCooldownHelper.applyAfterUse(char, entry.id, entry.cooldown)
			end
		end
	end
end

local function castPowerAbsorption(player: Player, direction: Vector3, targetModel: Model?)
	local character = player.Character
	if not character then
		return
	end
	if absorbByPlayer[player] then
		return
	end
	local entry = CharacterRegistry.getAbilityById("scarlet_witch", "ultimate")
	if not entry or not canUse(character, entry.id, entry.energyCost) then
		return
	end
	if character:GetAttribute(GameConstants.IS_FLYING_ATTRIBUTE) == true then
		refundEnergy(character, entry.energyCost)
		return
	end

	local casterRoot = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local casterHum = CombatHelper.getHumanoid(character)
	if not casterRoot or not casterHum then
		refundEnergy(character, entry.energyCost)
		return
	end

	local dir = if direction.Magnitude > 0.01 then direction.Unit else character:GetPivot().LookVector
	local target = resolveTarget(character, targetModel, dir, GameConstants.DISINTEGRATE_RANGE)
	if not target or CombatHelper.isShielded(target) then
		refundEnergy(character, entry.energyCost)
		return
	end

	local targetHum = CombatHelper.getHumanoid(target)
	local targetRoot = getRootPart(target)
	if not targetHum or not targetRoot or targetHum.MaxHealth <= 0 then
		refundEnergy(character, entry.energyCost)
		return
	end
	if (targetHum.Health / targetHum.MaxHealth) > GameConstants.DISINTEGRATE_HP_THRESHOLD then
		refundEnergy(character, entry.energyCost)
		return
	end

	AbilityCooldownHelper.setActive(character, entry.id, true)
	HandParticleHelper.beginUse(character)
	CharacterService.markAbilityUse(character)
	character:SetAttribute("AbsorbActive", true)

	local prevTargetWalk = targetHum.WalkSpeed
	local prevTargetJump = targetHum.JumpPower
	local prevTargetAuto = targetHum.AutoRotate
	local prevCasterAuto = casterHum.AutoRotate

	targetHum.WalkSpeed = 0
	targetHum.JumpPower = 0
	targetHum.AutoRotate = false
	casterHum.AutoRotate = false

	local liftStart = targetRoot.Position
	local liftAlign, liftAtt = createAbsorbLift(targetRoot, liftStart)
	local casterFace, casterFaceAtt = createAbsorbFaceAlign(casterRoot, "AbsorbCasterFace")
	local targetFace, targetFaceAtt = createAbsorbFaceAlign(targetRoot, "AbsorbTargetFace")

	local startHealth = targetHum.Health
	local beams: { AbsorbBeamFx } = {}

	local rightHand = getRightHand(character)
	local leftHand = getLeftHand(character)
	local endParts: { BasePart } = {
		rightHand or casterRoot,
		casterRoot,
		leftHand or casterRoot,
	}

	local function pickTargetPart(index: number): BasePart
		local namesByIndex = {
			{ "Head", "UpperTorso", "Torso" },
			{ "UpperTorso", "Torso", "HumanoidRootPart" },
			{ "LeftHand", "Left Arm", "LeftLowerArm", "LowerTorso", "Torso" },
		}
		local names = namesByIndex[index] or namesByIndex[1]
		for _, name in names do
			local part = target:FindFirstChild(name)
			if part and part:IsA("BasePart") then
				return part
			end
		end
		return targetRoot
	end

	local startJitter = {
		Vector3.new(0.35, 0.2, 0.1),
		Vector3.new(-0.25, 0.15, -0.2),
		Vector3.new(0.1, -0.2, 0.25),
	}

	for i = 1, GameConstants.ABSORB_BEAM_COUNT do
		local startAtt = cloneScarletAttachment("BeamStartAttachment")
		local endAtt = cloneScarletAttachment("BeamEndAttachment")
		if not startAtt or not endAtt then
			warn("[ScarletWitch] Missing BeamStartAttachment / BeamEndAttachment for Power Absorption")
			break
		end

		local startPart = pickTargetPart(i)
		startAtt.Name = "AbsorbBeamStart" .. tostring(i)
		startAtt.Position = startJitter[i] or Vector3.zero
		startAtt.Parent = startPart

		local startWorld = startPart.CFrame:PointToWorldSpace(startAtt.Position)
		local travelHost = Instance.new("Part")
		travelHost.Name = "AbsorbBeamTravel" .. tostring(i)
		travelHost.Anchored = true
		travelHost.CanCollide = false
		travelHost.CanQuery = false
		travelHost.CanTouch = false
		travelHost.Transparency = 1
		travelHost.Size = Vector3.new(0.2, 0.2, 0.2)
		travelHost.CFrame = CFrame.new(startWorld)
		travelHost.Parent = workspace

		local endPart = endParts[i] or casterRoot
		endAtt.Name = "AbsorbBeamEnd" .. tostring(i)
		endAtt.Position = Vector3.zero
		endAtt.Parent = travelHost

		local beam = startAtt:FindFirstChildWhichIsA("Beam", true)
		if beam then
			beam.Attachment0 = startAtt
			beam.Attachment1 = endAtt
			beam.CurveSize0 = 0
			beam.CurveSize1 = 0
			beam.Enabled = true
		end

		-- Disable "In" particle on beam start during absorption
		local inFx = startAtt:FindFirstChild("In", true)
		if inFx and inFx:IsA("ParticleEmitter") then
			inFx.Enabled = false
		end

		VfxHelper.setParticlesEnabled(startAtt, true)
		VfxHelper.setParticlesEnabled(endAtt, false)
		if inFx and inFx:IsA("ParticleEmitter") then
			inFx.Enabled = false
		end
		for _, desc in startAtt:GetDescendants() do
			if desc:IsA("ParticleEmitter") and desc.Name == "In" then
				desc.Enabled = false
			elseif desc:IsA("ParticleEmitter") then
				pcall(function()
					desc:Emit(4)
				end)
			end
		end

		table.insert(beams, {
			startAtt = startAtt,
			endAtt = endAtt,
			beam = beam,
			travelHost = travelHost,
			destPart = endPart,
			startWorld = startWorld,
			curve0Max = 2.5 + math.random() * (GameConstants.ABSORB_CURVE_MAX - 2.5),
			curve1Max = 2.5 + math.random() * (GameConstants.ABSORB_CURVE_MAX - 2.5),
			curve0Sign = if math.random() > 0.5 then 1 else -1,
			curve1Sign = if math.random() > 0.5 then 1 else -1,
			freq0 = 0.7 + math.random() * 2.8,
			freq1 = 0.6 + math.random() * 3.0,
			phase0 = math.random() * math.pi * 2,
			phase1 = math.random() * math.pi * 2,
			wander0 = 0.8 + math.random() * 2.6,
			wander1 = 0.8 + math.random() * 2.6,
			riseDelay = 0,
			riseSpan = GameConstants.ABSORB_BEAM_REACH_TIME,
		})
	end

	if #beams == 0 then
		refundEnergy(character, entry.energyCost)
		AbilityCooldownHelper.setActive(character, entry.id, false)
		HandParticleHelper.endUse(character)
		liftAlign:Destroy()
		liftAtt:Destroy()
		casterFace:Destroy()
		targetFace:Destroy()
		casterFaceAtt:Destroy()
		targetFaceAtt:Destroy()
		targetHum.WalkSpeed = prevTargetWalk
		targetHum.JumpPower = prevTargetJump
		targetHum.AutoRotate = prevTargetAuto
		casterHum.AutoRotate = prevCasterAuto
		return
	end

	absorbByPlayer[player] = {
		character = character,
		target = target,
		targetHum = targetHum,
		casterHum = casterHum,
		casterRoot = casterRoot,
		targetRoot = targetRoot,
		beams = beams,
		startHealth = startHealth,
		startedAt = os.clock(),
		reachTime = GameConstants.ABSORB_BEAM_REACH_TIME,
		beamsReached = false,
		drainStartedAt = nil,
		duration = GameConstants.ABSORB_DURATION,
		liftAlign = liftAlign,
		liftAtt = liftAtt,
		liftStartY = liftStart.Y,
		liftBaseX = liftStart.X,
		liftBaseZ = liftStart.Z,
		casterFace = casterFace,
		targetFace = targetFace,
		casterFaceAtt = casterFaceAtt,
		targetFaceAtt = targetFaceAtt,
		prevTargetWalk = prevTargetWalk,
		prevTargetJump = prevTargetJump,
		prevTargetAutoRotate = prevTargetAuto,
		prevCasterAutoRotate = prevCasterAuto,
	}
end

local function castDisintegration(
	player: Player,
	direction: Vector3,
	targetModel: Model?,
	aimPoint: Vector3?,
	interactable: Instance?
)
	local character = player.Character
	if not character then
		return
	end
	local entry = CharacterRegistry.getAbilityById("scarlet_witch", "ultimate")
	if not entry or not canUse(character, entry.id, entry.energyCost) then
		return
	end

	local origin = getOrigin(character)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local dir = if direction.Magnitude > 0.01 then direction.Unit else character:GetPivot().LookVector
	if aimPoint then
		local toAim = aimPoint - origin
		if toAim.Magnitude > 0.05 then
			dir = toAim.Unit
		end
	end

	-- Prefer living target under 10% HP â€” only the chosen victim dies
	local living = resolveTarget(character, targetModel, dir, GameConstants.DISINTEGRATE_RANGE)
	if living and not CombatHelper.isShielded(living) then
		if LokiService.tryReflect(character, living, "disintegrate") then
			refundEnergy(character, entry.energyCost)
			return
		end
		local hum = CombatHelper.getHumanoid(living)
		if hum and hum.MaxHealth > 0 and (hum.Health / hum.MaxHealth) <= GameConstants.DISINTEGRATE_HP_THRESHOLD then
			local tRoot = getRootPart(living)
			if tRoot then
				dir = (tRoot.Position - origin)
				if dir.Magnitude > 0.05 then
					dir = dir.Unit
				end
			end
			AbilityCooldownHelper.setActive(character, entry.id, true)
			character:SetAttribute(GameConstants.DISINTEGRATE_ACTIVE_ATTRIBUTE, true)
			HandParticleHelper.beginUse(character)
			local finished = false
			local function clearDisintegrate()
				if character.Parent then
					character:SetAttribute(GameConstants.DISINTEGRATE_ACTIVE_ATTRIBUTE, nil)
				end
			end
			local function dissolveLiving(victim: Model)
				if finished then
					return
				end
				if victim ~= living then
					return
				end
				finished = true
				local vRoot = getRootPart(victim)
				if vRoot then
					VfxHelper.spawnImpact(vRoot.Position, VfxHelper.chaosColor(), 5)
					VfxHelper.spawnBeamLine(origin, vRoot.Position, VfxHelper.chaosSoft(), 0.4, 0.2)
				end
				local humanoid = CombatHelper.getHumanoid(victim)
				if humanoid then
					humanoid.WalkSpeed = 0
					humanoid.JumpPower = 0
					humanoid.AutoRotate = false
				end
				VfxHelper.fadePartsByHeight(victim, 1, GameConstants.DISINTEGRATE_DURATION, true, function()
					if humanoid and humanoid.Parent then
						humanoid.Health = 0
					end
					clearDisintegrate()
					if character.Parent then
						finishAbility(character, entry.id, entry.cooldown)
						HandParticleHelper.endUse(character)
					end
				end)
			end
			ProjectileHelper.spawn(origin, dir, {
				speed = 120,
				damage = 0,
				radius = 1.25,
				maxDistance = GameConstants.DISINTEGRATE_RANGE,
				owner = character,
				color = VfxHelper.chaosColor(),
				onHit = function(victim: Model, _hitPos: Vector3)
					dissolveLiving(victim)
				end,
			})
			task.delay(0.45, function()
				if not finished and living.Parent then
					dissolveLiving(living)
				elseif not finished and character.Parent then
					clearDisintegrate()
					finishAbility(character, entry.id, entry.cooldown)
					HandParticleHelper.endUse(character)
				end
			end)
			return
		end
	end

	-- Interactable objects (no HP gate)
	local prop = interactable
	if not prop and root then
		prop = InteractableHelper.raycast(root.Position, dir, GameConstants.DISINTEGRATE_RANGE, character)
	end
	if prop then
		AbilityCooldownHelper.setActive(character, entry.id, true)
		character:SetAttribute(GameConstants.DISINTEGRATE_ACTIVE_ATTRIBUTE, true)
		HandParticleHelper.beginUse(character)
		dissolveInteractable(prop, function()
			if character.Parent then
				character:SetAttribute(GameConstants.DISINTEGRATE_ACTIVE_ATTRIBUTE, nil)
				finishAbility(character, entry.id, entry.cooldown)
				HandParticleHelper.endUse(character)
			end
		end)
		return
	end

	refundEnergy(character, entry.energyCost)
end

local function castUltimate(
	player: Player,
	direction: Vector3,
	targetModel: Model?,
	aimPoint: Vector3?,
	interactable: Instance?
)
	local character = player.Character
	if not character then
		return
	end
	if getUltimateMode(character) == "Absorption" then
		castPowerAbsorption(player, direction, targetModel)
	else
		castDisintegration(player, direction, targetModel, aimPoint, interactable)
	end
end

-- Fear Inducement: copy appears behind target while sliding right, returns while fading out

local function tweenCloneTransparency(clone: Model, toTransparency: number, duration: number)
	local info = TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	for _, desc in clone:GetDescendants() do
		if desc:IsA("BasePart") then
			if desc.Name == "HumanoidRootPart" then
				desc.Transparency = 1
			else
				TweenService:Create(desc, info, { Transparency = toTransparency }):Play()
			end
		elseif desc:IsA("Decal") or desc:IsA("Texture") then
			TweenService:Create(desc, info, { Transparency = toTransparency }):Play()
		elseif desc:IsA("Highlight") then
			TweenService:Create(desc, info, {
				FillTransparency = if toTransparency >= 1 then 1 else 0.55,
				OutlineTransparency = if toTransparency >= 1 then 1 else 0.2,
			}):Play()
		end
	end
end

local function castFear(player: Player, direction: Vector3, targetModel: Model?)
	local character = player.Character
	if not character then
		return
	end
	local entry = CharacterRegistry.getAbilityById("scarlet_witch", "fear_inducement")
	if not entry or not canUse(character, entry.id, entry.energyCost) then
		return
	end

	local target = resolveTarget(character, targetModel, direction, GameConstants.FEAR_RANGE)
	if not target or CombatHelper.isShielded(target) then
		refundEnergy(character, entry.energyCost)
		return
	end
	if LokiService.tryReflect(character, target, "fear") then
		refundEnergy(character, entry.energyCost)
		return
	end

	local tRoot = getRootPart(target)
	if not tRoot then
		refundEnergy(character, entry.energyCost)
		return
	end

	AbilityCooldownHelper.setActive(character, entry.id, true)
	HandParticleHelper.beginUse(character)

	-- Powers locked for FEAR_POWER_LOCK seconds (continues after movement unlock)
	target:SetAttribute(GameConstants.POWERS_DISABLED_UNTIL, AbilityCooldownHelper.getNow() + GameConstants.FEAR_POWER_LOCK)

	local targetHum = CombatHelper.getHumanoid(target)
	local savedWalk = if targetHum then targetHum.WalkSpeed else 16
	local savedJump = if targetHum then targetHum.JumpPower else 50
	local savedJumpHeight = if targetHum then targetHum.JumpHeight else 7.2
	local savedAutoRotate = if targetHum then targetHum.AutoRotate else true
	if targetHum then
		targetHum.WalkSpeed = 0
		targetHum.JumpPower = 0
		targetHum.JumpHeight = 0
		targetHum.AutoRotate = false
	end

	local function unlockTargetMove()
		if targetHum and targetHum.Parent then
			targetHum.WalkSpeed = savedWalk
			targetHum.JumpPower = savedJump
			targetHum.JumpHeight = savedJumpHeight
			targetHum.AutoRotate = savedAutoRotate
		end
	end

	local function finishFear()
		unlockTargetMove()
		if character.Parent then
			finishAbility(character, entry.id, entry.cooldown)
			HandParticleHelper.endUse(character)
		end
	end

	local ok, clone = pcall(function()
		local wasArchivable = character.Archivable
		character.Archivable = true
		local cloned = character:Clone()
		character.Archivable = wasArchivable
		return cloned
	end)
	if not ok or not clone or not clone:IsA("Model") then
		finishFear()
		return
	end

	-- Pure visual: exact look (no recolor), no humanoid/collision, strip VFX + nameplates
	for _, desc in clone:GetDescendants() do
		if desc:IsA("Script") or desc:IsA("LocalScript") or desc:IsA("ModuleScript") or desc:IsA("Sound") then
			desc:Destroy()
		elseif desc:IsA("Humanoid") or desc:IsA("Animator") or desc:IsA("ControllerManager") then
			desc:Destroy()
		elseif desc.Name == "HandParticle"
			or desc.Name == "MCU_Nameplate"
			or desc.Name == "ShieldHealthGui"
			or desc:IsA("BillboardGui")
			or desc:IsA("ParticleEmitter")
			or desc:IsA("Trail")
			or desc:IsA("Beam")
			or desc:IsA("Highlight")
			or desc:IsA("ForceField")
		then
			desc:Destroy()
		elseif desc:IsA("BasePart") then
			desc.Anchored = true
			desc.CanCollide = false
			desc.CanQuery = false
			desc.CanTouch = false
			desc.CastShadow = false
			desc.Massless = true
		end
	end

	clone.Name = "FearClone"
	clone:SetAttribute("FearVisual", true)
	VfxHelper.setCharacterTransparency(clone, 1)

	local function behindOfTarget(): CFrame
		local root = getRootPart(target)
		if not root then
			return clone:GetPivot()
		end
		return root.CFrame * CFrame.new(0, 0, GameConstants.FEAR_CLONE_OFFSET)
	end

	local function rightOfTarget(): CFrame
		local root = getRootPart(target)
		if not root then
			return clone:GetPivot()
		end
		-- Closer step to the target's right; yaw flipped the other way (*-1)
		local yaw = math.rad(GameConstants.FEAR_SLIDE_YAW_DEG) * -1
		return root.CFrame
			* CFrame.new(GameConstants.FEAR_SLIDE_RIGHT, 0, GameConstants.FEAR_CLONE_OFFSET * 0.2)
			* CFrame.Angles(0, -yaw, 0)
	end

	clone:PivotTo(behindOfTarget())
	clone.Parent = workspace

	local function moveCloneLive(goalFn: () -> CFrame, duration: number)
		local start = clone:GetPivot()
		local t0 = os.clock()
		while clone.Parent and target.Parent and (os.clock() - t0) < duration do
			local alpha = math.clamp((os.clock() - t0) / duration, 0, 1)
			local smooth = alpha * alpha * (3 - 2 * alpha)
			clone:PivotTo(start:Lerp(goalFn(), smooth))
			task.wait()
		end
		if clone.Parent and target.Parent then
			clone:PivotTo(goalFn())
		end
	end

	task.spawn(function()
		if not clone.Parent or not target.Parent then
			if clone.Parent then
				clone:Destroy()
			end
			finishFear()
			return
		end

		-- 1) Appear while sliding from behind â†’ right (and yawing right)
		local appearTime = GameConstants.FEAR_APPEAR_TIME
		tweenCloneTransparency(clone, 0.12, appearTime)
		moveCloneLive(rightOfTarget, appearTime)

		if not clone.Parent or not target.Parent then
			if clone.Parent then
				clone:Destroy()
			end
			finishFear()
			return
		end

		-- Hold at the right pose
		task.wait(GameConstants.FEAR_HOLD_TIME)

		if not clone.Parent or not target.Parent then
			if clone.Parent then
				clone:Destroy()
			end
			finishFear()
			return
		end

		-- 2) Return behind while yawing back and fading out
		local returnTime = GameConstants.FEAR_RETURN_TIME
		tweenCloneTransparency(clone, 1, returnTime)
		moveCloneLive(behindOfTarget, returnTime)

		if clone.Parent then
			clone:Destroy()
		end
		finishFear()
	end)

	Debris:AddItem(
		clone,
		GameConstants.FEAR_APPEAR_TIME + GameConstants.FEAR_HOLD_TIME + GameConstants.FEAR_RETURN_TIME + 4
	)
end

local function setMode(player: Player, abilityId: string, mode: string)
	local character = player.Character
	if not character or character:GetAttribute(GameConstants.HERO_ATTRIBUTE) ~= "scarlet_witch" then
		return
	end
	if abilityId == "hex_blast" and (mode == "Single" or mode == "Barrage") then
		character:SetAttribute(GameConstants.HEX_BLAST_MODE_ATTRIBUTE, mode)
	elseif abilityId == "telekinesis" then
		-- Revamp: no TK modes
	elseif abilityId == "ultimate" and (mode == "Absorption" or mode == "Disintegration") then
		character:SetAttribute(GameConstants.ULTIMATE_MODE_ATTRIBUTE, mode)
	end
end

function ScarletWitchService.update(dt: number)
	local now = AbilityCooldownHelper.getNow()
	local dtClamped = math.clamp(dt, 0.001, 0.1)

	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character and character:GetAttribute(GameConstants.HERO_ATTRIBUTE) == "scarlet_witch" then
			updateChaosImpact(player, character, dtClamped)
			updateControl(player, character, dtClamped)
			updateRuneDisplacement(player, dtClamped)
			if character:GetAttribute(GameConstants.SW_CONTROL_LOCK_ATTRIBUTE) == true then
				if beamByPlayer[player] then
					stopHexBeam(player, true)
				end
				if shieldByPlayer[player] then
					stopShield(player, true)
				end
				if TelekinesisService.isActive(player) then
					TelekinesisService.release(player)
				end
				if HexFlightService.isFlying(player) then
					HexFlightService.endFlight(player, true)
				end
				if probBeamByPlayer[player] then
					stopProbabilityHex(player, true, nil)
				end
			end
		else
			clearChaosFall(player)
		end
	end

	local beamPlayers: { Player } = {}
	for player in probBeamByPlayer do
		table.insert(beamPlayers, player)
	end
	for _, player in beamPlayers do
		updateProbabilityHex(player, dtClamped)
	end
	updateObjectHexes()

	for player, state in beamByPlayer do
		local char = state.character
		if not char.Parent or player.Character ~= char then
			stopHexBeam(player, true)
			continue
		end

		local victim = state.victim
		local vRoot = state.victimRoot
		local vHum = CombatHelper.getHumanoid(victim)
		if not victim.Parent or not vRoot.Parent or not vHum or vHum.Health <= 0 then
			stopHexBeam(player, true)
			continue
		end

		local casterRoot = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not casterRoot then
			stopHexBeam(player, true)
			continue
		end

		local hand = getRightHand(char)
		local origin = if hand then hand.Position else casterRoot.Position
		local now = os.clock()

		if not state.launched then
			state.smoothedTip = origin
			if state.handWeld and state.handWeld.Parent and hand then
				local look = if (vRoot.Position - origin).Magnitude > 0.08
					then CFrame.lookAt(origin, vRoot.Position)
					else CFrame.new(origin)
				state.handWeld.C0 = hand.CFrame:ToObjectSpace(look)
			end
			if state.tipHost.Parent then
				if (vRoot.Position - origin).Magnitude > 0.08 then
					state.tipHost.CFrame = CFrame.lookAt(origin, vRoot.Position)
				else
					state.tipHost.CFrame = CFrame.new(origin)
				end
			end
			if now - state.startedAt >= GameConstants.HEX_BEAM_START_DELAY then
				state.launched = true
				for _, liveBeam in collectBeams(state.startHost) do
					liveBeam.Enabled = true
				end
				for _, liveBeam in collectBeams(state.tipHost) do
					liveBeam.Enabled = true
				end
				if state.beam and not state.beam.Enabled then
					state.beam.Enabled = true
				end
				VfxHelper.setParticlesEnabled(state.startHost, true)
				VfxHelper.setParticlesEnabled(state.tipHost, true)
			end
			applyBeamMovement(state)
			continue
		end

		local desiredTip = hexBeamTipInFront(origin, vRoot.Position)
		if not state.reached then
			state.smoothedTip = moveToward(
				state.smoothedTip,
				desiredTip,
				GameConstants.HEX_BEAM_TRAVEL_SPEED * dtClamped
			)
			local tipPos = state.smoothedTip
			if state.handWeld and state.handWeld.Parent and hand then
				local look = if (tipPos - origin).Magnitude > 0.08
					then CFrame.lookAt(origin, tipPos)
					else CFrame.new(origin)
				state.handWeld.C0 = hand.CFrame:ToObjectSpace(look)
			end
			if state.tipHost.Parent then
				if (tipPos - origin).Magnitude > 0.08 then
					state.tipHost.CFrame = CFrame.lookAt(tipPos, origin)
				else
					state.tipHost.CFrame = CFrame.new(tipPos)
				end
			end
			if (state.smoothedTip - desiredTip).Magnitude <= GameConstants.HEX_BEAM_REACH then
				state.reached = true
				state.abilityStartedAt = now
				state.smoothedTip = desiredTip
				beginHexBeamOnTarget(state)
			end
			applyBeamMovement(state)
			continue
		end

		local abilityStart = state.abilityStartedAt or state.startedAt
		if now - abilityStart >= GameConstants.HEX_BEAM_DURATION then
			stopHexBeam(player, true)
			continue
		end
		if (vRoot.Position - casterRoot.Position).Magnitude >= GameConstants.HEX_BEAM_BREAK_DISTANCE then
			stopHexBeam(player, true)
			continue
		end

		local energy = char:GetAttribute(GameConstants.ENERGY_ATTRIBUTE)
		if type(energy) ~= "number" or energy <= 0 then
			stopHexBeam(player, true)
			continue
		end
		char:SetAttribute(
			GameConstants.ENERGY_ATTRIBUTE,
			math.max(0, energy - GameConstants.HEX_BEAM_ENERGY_PER_SEC * dtClamped)
		)
		CharacterService.markAbilityUse(char)
		applyBeamMovement(state)

		local tipLerp = 1 - (1 - GameConstants.HEX_BEAM_TIP_LERP) ^ (dtClamped * 60)
		state.smoothedTip = state.smoothedTip:Lerp(desiredTip, tipLerp)
		local tipPos = state.smoothedTip

		local forcedTip = BeamClashService.getForcedBeamTip(char)
		if forcedTip then
			tipPos = forcedTip
			state.smoothedTip = forcedTip
		end

		if state.handWeld and state.handWeld.Parent and hand then
			local look = if (tipPos - origin).Magnitude > 0.08
				then CFrame.lookAt(origin, tipPos)
				else CFrame.new(origin)
			state.handWeld.C0 = hand.CFrame:ToObjectSpace(look)
		elseif state.startHost.Parent then
			if (tipPos - origin).Magnitude > 0.08 then
				state.startHost.CFrame = CFrame.lookAt(origin, tipPos)
			else
				state.startHost.CFrame = CFrame.new(origin)
			end
		end
		if state.tipHost.Parent then
			if (tipPos - origin).Magnitude > 0.08 then
				state.tipHost.CFrame = CFrame.lookAt(tipPos, origin)
			else
				state.tipHost.CFrame = CFrame.new(tipPos)
			end
		end
		if state.beam and not state.beam.Enabled then
			state.beam.Enabled = true
		end

		local toVictim = vRoot.Position - casterRoot.Position
		local flat = Vector3.new(toVictim.X, 0, toVictim.Z)
		if flat.Magnitude > 0.05 then
			local away = flat.Unit
			local casterLook = CFrame.lookAt(casterRoot.Position, casterRoot.Position + away)
			local victimLook = CFrame.lookAt(vRoot.Position, vRoot.Position - away)
			if state.casterFace and state.casterFace.Parent then
				state.casterFace.CFrame = casterLook
			end
			local flightAlign = casterRoot:FindFirstChild("HeroAlignOrientation")
			if flightAlign and flightAlign:IsA("AlignOrientation") then
				flightAlign.CFrame = casterLook
			end
			if state.victimFace and state.victimFace.Parent then
				state.victimFace.CFrame = victimLook
			end

			if char:GetAttribute(GameConstants.BEAM_CLASH_ATTRIBUTE) ~= true and not forcedTip then
				PushHelper.applyToCharacter(victim, away, {
					speed = GameConstants.HEX_BEAM_PUSH_SPEED,
					upBoost = GameConstants.HEX_BEAM_PUSH_UP,
					impulseMult = 0.28,
				})
				local vel = vRoot.AssemblyLinearVelocity
				vRoot.AssemblyLinearVelocity = Vector3.new(
					away.X * GameConstants.HEX_BEAM_PUSH_SPEED,
					math.max(vel.Y, GameConstants.HEX_BEAM_PUSH_UP),
					away.Z * GameConstants.HEX_BEAM_PUSH_SPEED
				)
			end
		end

		if now - state.lastHit >= 0.12 then
			state.lastHit = now
			if char:GetAttribute(GameConstants.BEAM_CLASH_ATTRIBUTE) == true or forcedTip then
				-- no tip damage while clashing
			else
				CombatHelper.dealDamage(char, victim, GameConstants.HEX_BEAM_DAMAGE_PER_SEC * 0.12, origin, "beam")
			end
		end
	end

	for player, state in shieldByPlayer do
		local char = state.character
		if not char.Parent or player.Character ~= char then
			stopShield(player, true)
			continue
		end
		local energy = char:GetAttribute(GameConstants.ENERGY_ATTRIBUTE)
		if type(energy) ~= "number" or energy <= 0 then
			stopShield(player, true)
			continue
		end
		char:SetAttribute(
			GameConstants.ENERGY_ATTRIBUTE,
			math.max(0, energy - GameConstants.SHIELD_ENERGY_PER_SEC * dtClamped)
		)
		CharacterService.markAbilityUse(char)
		ProjectileHelper.deflectNearShield(char, 8)
		local hum = CombatHelper.getHumanoid(char)
		if hum then
			hum.WalkSpeed = 0
			hum.JumpPower = 0
			hum:Move(Vector3.zero, false)
		end
		char:SetAttribute(GameConstants.BUSY_ATTRIBUTE, true)
	end

	for player, state in regenByPlayer do
		local char = state.character
		if not char.Parent or player.Character ~= char then
			stopRegen(player, true)
			continue
		end
		local energy = char:GetAttribute(GameConstants.ENERGY_ATTRIBUTE)
		if type(energy) ~= "number" or energy <= 0 then
			stopRegen(player, true)
			continue
		end
		char:SetAttribute(
			GameConstants.ENERGY_ATTRIBUTE,
			math.max(0, energy - GameConstants.REGEN_ENERGY_PER_SEC * dtClamped)
		)
		CharacterService.markAbilityUse(char)
		local hum = CombatHelper.getHumanoid(char)
		if hum and hum.Health > 0 and hum.Health < hum.MaxHealth then
			hum.Health = math.min(hum.MaxHealth, hum.Health + GameConstants.REGEN_HEAL_PER_SEC * dtClamped)
		end
	end

	for player, state in absorbByPlayer do
		local char = state.character
		local target = state.target
		if not char.Parent or player.Character ~= char or not target.Parent or not state.targetHum.Parent then
			stopPowerAbsorb(player, true)
			continue
		end
		if state.targetHum.Health <= 0 then
			stopPowerAbsorb(player, true)
			continue
		end
		if not state.casterRoot.Parent or not state.targetRoot.Parent then
			stopPowerAbsorb(player, true)
			continue
		end

		local elapsed = os.clock() - state.startedAt
		local nowClock = os.clock()
		local casterPos = state.casterRoot.Position
		local targetPos = state.targetRoot.Position

		-- Smoothly face each other (flat yaw)
		local toTarget = targetPos - casterPos
		local flatToTarget = Vector3.new(toTarget.X, 0, toTarget.Z)
		if flatToTarget.Magnitude > 0.05 then
			local casterLook = CFrame.lookAt(casterPos, casterPos + flatToTarget.Unit)
			local targetLook = CFrame.lookAt(targetPos, targetPos - flatToTarget.Unit)
			if state.casterFace and state.casterFace.Parent then
				state.casterFace.CFrame = casterLook
			end
			-- While flying, also write flight align so HexFlight doesn't fight us
			local flightAlign = state.casterRoot:FindFirstChild("HeroAlignOrientation")
			if flightAlign and flightAlign:IsA("AlignOrientation") then
				flightAlign.CFrame = casterLook
			end
			if state.targetFace and state.targetFace.Parent then
				state.targetFace.CFrame = targetLook
			end
		end

		-- Smooth lift over ABSORB_LIFT_TIME, then hold height
		if state.liftAlign and state.liftAlign.Parent then
			local liftT = math.clamp(elapsed / GameConstants.ABSORB_LIFT_TIME, 0, 1)
			local liftSmooth = liftT * liftT * (3 - 2 * liftT)
			local targetY = state.liftStartY + GameConstants.ABSORB_LIFT_HEIGHT * liftSmooth
			state.liftAlign.Position = Vector3.new(state.liftBaseX, targetY, state.liftBaseZ)
		end

		-- Animate beam tips from target â†’ caster over ABSORB_BEAM_REACH_TIME (distance-independent)
		local reachAlpha = math.clamp(elapsed / state.reachTime, 0, 1)
		local reachSmooth = reachAlpha * reachAlpha * (3 - 2 * reachAlpha)
		for _, fx in state.beams do
			if not state.beamsReached and fx.travelHost and fx.travelHost.Parent and fx.destPart.Parent then
				local destWorld = fx.destPart.Position
				local tipPos = fx.startWorld:Lerp(destWorld, reachSmooth)
				fx.travelHost.CFrame = CFrame.new(tipPos)
			end

			if fx.beam and fx.beam.Parent then
				local rise = if state.beamsReached then 1 else reachSmooth
				local wiggle0 = math.sin(nowClock * fx.freq0 + fx.phase0) * fx.wander0 * rise
				local wiggle1 = math.sin(nowClock * fx.freq1 + fx.phase1) * fx.wander1 * rise
				fx.beam.CurveSize0 = math.clamp(
					fx.curve0Sign * (rise * fx.curve0Max + wiggle0),
					-GameConstants.ABSORB_CURVE_MAX - 2,
					GameConstants.ABSORB_CURVE_MAX + 2
				)
				fx.beam.CurveSize1 = math.clamp(
					fx.curve1Sign * (rise * fx.curve1Max + wiggle1),
					-GameConstants.ABSORB_CURVE_MAX - 2,
					GameConstants.ABSORB_CURVE_MAX + 2
				)
			end
			local inFx = fx.startAtt:FindFirstChild("In", true)
			if inFx and inFx:IsA("ParticleEmitter") and inFx.Enabled then
				inFx.Enabled = false
			end
		end

		if not state.beamsReached and reachAlpha >= 1 then
			state.beamsReached = true
			state.drainStartedAt = os.clock()
			state.startHealth = state.targetHum.Health
			for _, fx in state.beams do
				if fx.destPart.Parent then
					fx.endAtt.Parent = fx.destPart
					fx.endAtt.Position = Vector3.zero
					VfxHelper.setParticlesEnabled(fx.endAtt, true)
					VfxHelper.emitAllParticles(fx.endAtt, 6)
				end
				if fx.travelHost and fx.travelHost.Parent then
					fx.travelHost:Destroy()
				end
				fx.travelHost = nil
			end
		end

		-- Drain / heal only after beams have reached the caster
		if state.beamsReached and state.drainStartedAt then
			local drainElapsed = os.clock() - state.drainStartedAt
			local u = math.clamp(drainElapsed / state.duration, 0, 1)
			local desiredHealth = state.startHealth * (1 - u)
			local before = state.targetHum.Health
			local nextHealth = math.max(0, math.min(before, desiredHealth))
			local drained = before - nextHealth
			if drained > 0 then
				state.targetHum.Health = nextHealth
				if state.casterHum.Parent and state.casterHum.Health > 0 then
					state.casterHum.Health = math.min(state.casterHum.MaxHealth, state.casterHum.Health + drained)
				end
			end

			if u >= 1 or state.targetHum.Health <= 0 then
				state.targetHum.Health = 0
				stopPowerAbsorb(player, true)
			end
		end
	end
end

function ScarletWitchService.handleAction(player: Player, payload: any)
	if type(payload) ~= "table" then
		return
	end
	local character = player.Character
	if not character or character:GetAttribute(GameConstants.HERO_ATTRIBUTE) ~= "scarlet_witch" then
		return
	end
	local action = payload.action
	if type(action) ~= "string" then
		return
	end

	local direction = if typeof(payload.direction) == "Vector3" then payload.direction else Vector3.new(0, 0, -1)
	local aimPoint = if typeof(payload.aimPoint) == "Vector3" then payload.aimPoint else nil
	local targetModel: Model? = nil
	if typeof(payload.target) == "Instance" and (payload.target :: Instance):IsA("Model") then
		targetModel = payload.target :: Model
	end
	local hitPart: BasePart? = nil
	if typeof(payload.hitPart) == "Instance" and (payload.hitPart :: Instance):IsA("BasePart") then
		hitPart = payload.hitPart :: BasePart
	end
	local interactable: Instance? = nil
	if typeof(payload.interactable) == "Instance" then
		interactable = payload.interactable :: Instance
	end

	if action == "SetMode" then
		if type(payload.abilityId) == "string" and type(payload.mode) == "string" then
			setMode(player, payload.abilityId, payload.mode)
		end
		return
	end

	if action == "F" then
		HexFlightService.toggleFlight(player)
	elseif action == "R_down" then
		local aim = aimPoint
			or (player.Character and player.Character:FindFirstChild("HumanoidRootPart") and (player.Character.HumanoidRootPart :: BasePart).Position + direction * 20)
		if aim and TelekinesisService.tryStart(player, aim, targetModel, hitPart, payload.softLock == true) then
			fireCameraShake(player, 0.3, 0.4, 0.18, 0.4)
		end
	elseif action == "R_up" then
		TelekinesisService.release(player)
	elseif action == "R_update" then
		if aimPoint then
			TelekinesisService.updateAim(player, aimPoint)
		end
	elseif action == "R_scroll" or action == "E_scroll" then
		if type(payload.scroll) == "number" then
			TelekinesisService.adjustDistance(player, payload.scroll)
		end
		if aimPoint then
			TelekinesisService.updateAim(player, aimPoint)
		end
	elseif action == "R_throw" then
		TelekinesisService.throw(player, direction, aimPoint)
	elseif action == "R" then
		-- HUD tap: start the hold when idle
		if not TelekinesisService.isActive(player) then
			local aim = aimPoint
				or (player.Character and player.Character:FindFirstChild("HumanoidRootPart") and (player.Character.HumanoidRootPart :: BasePart).Position + direction * 20)
			if aim then
				TelekinesisService.tryStart(player, aim, targetModel, hitPart, payload.softLock == true)
			end
		end
	elseif action == "E" then
		fireHexBolt(player, direction, aimPoint)
	elseif action == "T" or action == "T_down" then
		startHexBeam(player, targetModel, direction, payload.softLock == true)
	elseif action == "T_up" then
		-- Hex Beam is a one-shot; release does not cancel.
	elseif action == "T_aim" then
		-- Lock-on beam tracks the victim; mouse aim is ignored.
	elseif action == "Q" or action == "Q_down" then
		startShield(player)
	elseif action == "Q_up" then
		stopShield(player, true)
	elseif action == "B_down" then
		startRegen(player)
	elseif action == "B_up" then
		stopRegen(player, true)
	elseif action == "V" then
		beginWandaTeleportAim(player)
	elseif action == "V_confirm" then
		castTeleport(player, direction, aimPoint)
	elseif action == "X" then
		castRuneDisplacement(player, aimPoint)
	elseif action == "G" then
		castProbabilityHex(player, targetModel, direction)
	end
end

function ScarletWitchService.tryHexDash(player: Player, moveWorld: Vector3): boolean
	-- Dash temporarily disabled
	return false
end


function ScarletWitchService.cancelAll(player: Player)
	ScarletWitchService.forceStopBeam(player, false)
	stopShield(player, false)
	stopRegen(player, false)
	stopRuneDisplacement(player, false)
	stopProbabilityHex(player, false, nil)
	stopPowerAbsorb(player, false)
	HexFlightService.endFlight(player, false)
	TelekinesisService.release(player)
	clearChaosFall(player)
	hexDashUntil[player] = nil
	hexDashCdUntil[player] = nil
	local char = player.Character
	if char then
		clearWandaTeleportAim(char)
		Remotes.getEvent("HexDisplacementCam"):FireClient(player, nil)
		Remotes.getEvent("SprintInput"):FireClient(player, { clearDash = true })
		local root = char:FindFirstChild("HumanoidRootPart")
		local dashLv = root and root:FindFirstChild("HexDashBoost")
		if dashLv then
			dashLv:Destroy()
		end
		local humanoid = char:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health <= 0 then
			local RagdollService = require(script.Parent.RagdollService)
			RagdollService.apply(char)
		end
	end
end

function ScarletWitchService.getActiveBeamSegments(): {
	{
		id: string,
		kind: "player",
		player: Player,
		character: Model,
		origin: Vector3,
		tip: Vector3,
		label: string,
	}
}
	local list = {}
	for player, state in beamByPlayer do
		local char = state.character
		if char.Parent and player.Character == char then
			local origin = if state.startHost.Parent then state.startHost.Position else char:GetPivot().Position
			local tip = state.tipHost.Position
			table.insert(list, {
				id = "hex:" .. tostring(player.UserId),
				kind = "player" :: "player",
				player = player,
				character = char,
				origin = origin,
				tip = tip,
				label = player.DisplayName,
			})
		end
	end
	return list
end

function ScarletWitchService.init()
	CombatHelper.setShieldDamageHandler(function(character: Model, amount: number, hitFrom: Vector3?): boolean
		return ScarletWitchService.damageShieldForCharacter(character, amount, hitFrom)
	end)

	Remotes.getEvent("UseAbility").OnServerEvent:Connect(function(player: Player, payload: any)
		ScarletWitchService.handleAction(player, payload)
	end)

	local function hookPlayer(player: Player)
		player.CharacterRemoving:Connect(function()
			ScarletWitchService.cancelAll(player)
		end)
		player.CharacterAdded:Connect(function(character)
			local humanoid = character:WaitForChild("Humanoid", 5)
			if humanoid and humanoid:IsA("Humanoid") then
				humanoid.Died:Connect(function()
					ScarletWitchService.cancelAll(player)
				end)
			end
		end)
		if player.Character then
			local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.Died:Connect(function()
					ScarletWitchService.cancelAll(player)
				end)
			end
		end
	end

	for _, player in Players:GetPlayers() do
		hookPlayer(player)
	end
	Players.PlayerAdded:Connect(hookPlayer)

	Players.PlayerRemoving:Connect(function(player)
		ScarletWitchService.cancelAll(player)
	end)
end

return ScarletWitchService
