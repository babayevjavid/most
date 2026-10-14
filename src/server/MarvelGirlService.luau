--!strict
--[[
	Marvel Girl / Jean Grey:
	Q Psionic Barrier
	E Psionic Bolt
	F Telekinetic Flight
	R Telekinesis (hold lift, click push)
	T Telekinetic Pull
	X Telekinetic Slam
	Z Telekinetic Debris (hold: summon + click throw)
	G Mind Link
	H Astral Projection (30s)
	C/B Telepathic Pain / Outburst while astral
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ContentProvider = game:GetService("ContentProvider")
local TextService = game:GetService("TextService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AbilityCooldownHelper = require(ReplicatedStorage.Shared.AbilityCooldownHelper)
local AnimationLoadHelper = require(ReplicatedStorage.Shared.AnimationLoadHelper)
local CastFaceHelper = require(ReplicatedStorage.Shared.CastFaceHelper)
local CharacterRegistry = require(ReplicatedStorage.Shared.CharacterRegistry)
local CombatHelper = require(ReplicatedStorage.Shared.CombatHelper)
local ConstraintHelper = require(ReplicatedStorage.Shared.ConstraintHelper)
local GameConstants = require(ReplicatedStorage.Shared.GameConstants)
local FlightMath = require(ReplicatedStorage.Shared.FlightMath)
local InteractableHelper = require(ReplicatedStorage.Shared.InteractableHelper)
local ProjectileHelper = require(ReplicatedStorage.Shared.ProjectileHelper)
local PushHelper = require(ReplicatedStorage.Shared.PushHelper)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ScreenFeelHelper = require(ReplicatedStorage.Shared.ScreenFeelHelper)
local VfxHelper = require(ReplicatedStorage.Shared.VfxHelper)
local CharacterService = require(script.Parent.CharacterService)
local RemoteGuard = require(script.Parent.RemoteGuard)
local HexFlightService = require(script.Parent.HexFlightService)
local NameplateService = require(script.Parent.NameplateService)
local RagdollService = require(script.Parent.RagdollService)
local TelekinesisService = require(script.Parent.TelekinesisService)

local MarvelGirlService = {}

type BarrierState = {
	character: Model,
	hp: number,
	maxHp: number,
	forcefield: Instance,
	billboard: BillboardGui,
	hpLabel: TextLabel,
	hpFill: Frame,
	healthConn: RBXScriptConnection?,
	lastHealth: number,
	session: any?, -- AbilitySession holding the slow + no-jump (nil for astral / dark shields, which never slow)
	animTrack: AnimationTrack?,
	-- Dark Phoenix's Cosmic Shield: a toggle that never slows her, lets her use any ability, drains a bit more.
	dark: boolean?,
	}
	
	type AstralState = {
	character: Model,
	body: Model,
	astral: Model,
	root: BasePart,
	humanoid: Humanoid,
	mover: ConstraintHelper.MoverBundle,
	moveDir: Vector3,
	lookDir: Vector3,
	sideInput: number,
	currentVel: Vector3,
	startedAt: number,
	returning: boolean,
	healthConn: RBXScriptConnection?,
	fx: { Instance },
	outbursting: boolean,
	keepHighlightUntilNear: boolean,
	outburstHoldCf: CFrame?,
	loopSound: Sound?,
	bodyAnimTrack: AnimationTrack?,
	abilityId: string?, -- the cooldown / active id (Madison's Descensum borrows this projection under her own id)
}

type MindLinkState = {
	character: Model,
	members: { Model }, -- includes Jean
	startedAt: number,
	token: number,
	linkerIncluded: boolean,
	jeanFx: Instance?,
	jeanAtts: { Attachment },
	beamTemplates: { Beam },
	activeBeams: { Beam },
	targetFx: { Instance },
	healthConn: RBXScriptConnection?,
	lastHealth: number,
	spreading: boolean,
}

type SlamState = {
	character: Model,
	victim: Model,
	vRoot: BasePart,
	token: number,
	fx: { Instance },
	ownedParts: { BasePart },
	throwDir: Vector3,
	slam2Host: BasePart?,
	faceConn: RBXScriptConnection?,
	faceAlign: AlignOrientation?,
	faceAtt: Attachment?,
	animTrack: AnimationTrack?,
	victimTrack: AnimationTrack?,
	startedAt: number,
	victimSynced: boolean?,
	victimAutoRotate: boolean,
	released: boolean?,
	burnVfx: boolean?,
}

type DebrisRock = {
	part: BasePart,
	visual: Instance,
	ready: boolean,
	rising: boolean,
	thrown: boolean,
	expiring: boolean,
	followOffset: Vector3,
	homeOffset: Vector3,
	liftY: number,
	rot: CFrame,
	baseTilt: CFrame,
	spinAxis: Vector3,
	spinSpeed: number,
	spinAngle: number,
	yawSpeed: number,
	yawAngle: number,
	bobSpeed: number,
	bobPhase: number,
	orbitRadius: number,
	orbitHeight: number,
	orbitAngle: number,
	orbitSpeed: number,
}

type DebrisState = {
	character: Model,
	token: number,
	remaining: number,
	rocks: { DebrisRock },
	aimPoint: Vector3?,
	followUntil: number,
	holding: boolean,
	lastThrowAt: number,
	throwQueued: boolean?,
	liftAnimTrack: AnimationTrack?,
}

type PainState = {
	body: Model,
	victim: Model,
	fx: Instance?,
	sound: Sound?,
	tickAcc: number,
	animTrack: AnimationTrack?,
	victimAnimTrack: AnimationTrack?,
	startedAt: number,
	victimWalk: number,
	victimJumpPower: number?,
	victimJumpHeight: number?,
	victimAutoRotate: boolean,
}

type PhoenixPainState = {
	body: Model,
	root: BasePart,
	fx: Instance?,
	fxExtra: { Instance }?,
	tickAcc: number,
	animTrack: AnimationTrack?,
	startedAt: number,
	session: any?, -- AbilitySession holding the caster's slow / root
	-- Base Phoenix: one distant locked-on victim (`single`). Dark Phoenix: everyone in an area, no cursor.
	dark: boolean,
	single: Model?,
	victimTracks: { [Model]: AnimationTrack? },
	victimFxs: { [Model]: Instance },
	-- Victims currently caught, so leaving / the ability ending can restore their movement, tint and shake.
	affected: { [Model]: boolean },
	saved: { [Model]: { lock: any } }, -- AbilityLocks token holding each victim's slow + no-jump
}

local barrierByPlayer: { [Player]: BarrierState } = {}
local astralByPlayer: { [Player]: AstralState } = {}
local painByPlayer: { [Player]: PainState } = {}
local phoenixPainByPlayer: { [Player]: PhoenixPainState } = {}
local phoenixDownByPlayer: { [Player]: { character: Model, reviving: boolean?, reviveMorphFx: { Instance }?, deathPos: Vector3?, clamp: RBXScriptConnection? } } = {}
local phoenixAutoLoadBlocks = 0

-- Players.CharacterAutoLoads is now permanently false (CharacterService owns
-- spawning entirely via explicit LoadCharacter calls), so these no longer
-- need to touch it. Kept as a counter/no-op pair so call sites don't change.
local function blockPhoenixAutoRespawn()
	phoenixAutoLoadBlocks += 1
end

local function unblockPhoenixAutoRespawn()
	if phoenixAutoLoadBlocks <= 0 then
		return
	end
	phoenixAutoLoadBlocks -= 1
end

local outburstToken: { [Player]: number } = {}
local endAstral: (Player, boolean?, boolean?) -> ()
local playJeanAnim: (Model, string, boolean?) -> AnimationTrack?
local mindLinkByPlayer: { [Player]: MindLinkState } = {}
local slamByPlayer: { [Player]: SlamState } = {}
local debrisByPlayer: { [Player]: DebrisState } = {}
local debrisUseRightByPlayer: { [Player]: boolean } = {}
local mindLinkMsgCd: { [Player]: number } = {}
local mindLinkAddCd: { [Player]: number } = {}
local powerFxByCharacter: { [Model]: {
	instances: { Instance },
	refs: number,
	headPart: BasePart?,
	headPartMaterial: Enum.Material?,
	headEmitters: { [ParticleEmitter]: number }?,
} } = {}
-- pendingPowerFxCleanup lives on the Phoenix table (declared further down) -
-- module already sits near the 200 top-level-local ceiling (see CLAUDE.md),
-- so new state hangs off an existing table instead of adding a fresh local.
local bodyHoldByPlayer: { [Player]: {
	anchored: boolean,
	walk: number,
	jumpPower: number?,
	jumpHeight: number?,
	autoRotate: boolean,
} } = {}
local slamCasterHoldByPlayer: { [Player]: {
	anchored: boolean,
	walk: number,
	jumpPower: number?,
	jumpHeight: number?,
	autoRotate: boolean,
	ownedParts: { BasePart },
	animateWasDisabled: boolean?,
} } = {}
local overloadHoldByPlayer: { [Player]: {
	walk: number,
	jumpPower: number?,
	jumpHeight: number?,
	startedAt: number,
} } = {}

task.defer(function()
	local sounds: { Sound } = {}
	for _, id in {
		GameConstants.MG_BARRIER_BREAK_SOUND,
		GameConstants.MG_PULL_SOUND,
		GameConstants.MG_DEBRIS_HIT_SOUND,
		GameConstants.MG_DEBRIS_HIT_SOUNDS[1],
		GameConstants.MG_DEBRIS_HIT_SOUNDS[2],
		GameConstants.MG_DEBRIS_HIT_SOUNDS[3],
		GameConstants.MG_PSI_BOLT_SOUNDS[1],
		GameConstants.MG_PSI_BOLT_SOUNDS[2],
		GameConstants.MG_PSI_BOLT_SOUNDS[3],
		GameConstants.MG_ASTRAL_LOOP_SOUND,
		GameConstants.MG_OUTBURST_SOUND,
	} do
		local s = Instance.new("Sound")
		s.SoundId = id
		table.insert(sounds, s)
	end
	pcall(function()
		ContentProvider:PreloadAsync(sounds)
	end)
	for _, s in sounds do
		s:Destroy()
	end
end)

-- preload includes push sound
task.defer(function()
	local s = Instance.new("Sound")
	s.SoundId = GameConstants.MG_PUSH_SOUND
	pcall(function()
		ContentProvider:PreloadAsync({ s })
	end)
	s:Destroy()
end)

local lastPsiBoltSoundIndex = math.random(1, #GameConstants.MG_PSI_BOLT_SOUNDS)

-- Random each cast, but never the same clip twice in a row.
local function pickPsiBoltSound(): string
	local sounds = GameConstants.MG_PSI_BOLT_SOUNDS
	if #sounds <= 1 then
		return sounds[1]
	end
	local index = math.random(1, #sounds - 1)
	if index >= lastPsiBoltSoundIndex then
		index += 1
	end
	lastPsiBoltSoundIndex = index
	return sounds[index]
end

local function fireCameraShake(player: Player, intensity: number?, duration: number?, fovScale: number?, vignetteScale: number?)
	Remotes.getEvent("CameraShake"):FireClient(player, {
		intensity = intensity or 0.45,
		duration = duration or 0.35,
		fovScale = fovScale,
		vignetteScale = vignetteScale,
	})
end

local function normalizeDir(v: Vector3): Vector3
	if v.Magnitude < 0.01 then
		return Vector3.new(0, 0, -1)
	end
	return v.Unit
end

local function getBank(direction: Vector3, velocity: Vector3): number
	if direction.Magnitude < 0.01 or velocity.Magnitude < 2 then
		return 0
	end
	local lookVec = (CFrame.new(Vector3.zero, direction) * CFrame.Angles(0, math.rad(90), 0)).LookVector
	local dot = lookVec:Dot(velocity.Unit)
	local len = lookVec.Magnitude * velocity.Magnitude
	if len < 0.0001 then
		return 0
	end
	return math.clamp(90 - math.deg(math.acos(math.clamp(dot / len, -1, 1))), -90, 90)
end

local function forceAstralNoclip(model: Model)
	-- CanCollide = false alone already fully noclips a part against every
	-- other part in the game, at zero cost. This used to ALSO register a
	-- collision group and reconfigure its collidability against every other
	-- registered group (PhysicsService:CollisionGroupSetCollidable in a loop
	-- over PhysicsService:GetRegisteredCollisionGroups()) on every astral
	-- cast - that's a whole-physics-world matrix rebuild, not a per-part
	-- change, and was the actual cause of the server-wide lag spike on cast
	-- (it read as "everything in Workspace stopped colliding" because the
	-- rebuild stalls the whole physics step, not because other parts
	-- actually lost collision with each other). Dropped entirely - it did
	-- nothing CanCollide=false wasn't already doing.
	local function stripPart(part: BasePart)
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
	end
	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") then
			stripPart(desc)
		end
	end
	if model.PrimaryPart then
		stripPart(model.PrimaryPart)
	end
end

local function getRoot(model: Model?): BasePart?
	if not model then
		return nil
	end
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end
	return model.PrimaryPart
end

local function getHand(character: Model, preferRight: boolean): BasePart?
	local names = if preferRight
		then { "RightHand", "Right Arm", "RightLowerArm" }
		else { "LeftHand", "Left Arm", "LeftLowerArm" }
	for _, name in names do
		local p = character:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			return p
		end
	end
	return getRoot(character)
end

local function getHead(character: Model): BasePart?
	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head
	end
	return getRoot(character)
end

local function canUse(character: Model, abilityId: string, energy: number): boolean
	-- Set only for the synchronous duration of Rogue's absorbed copy (her own
	-- canUse/cooldown/cost already ran) - a character attribute, not a local, to
	-- stay clear of this file's 200-register module limit.
	if character:GetAttribute("MgAbsorbedCall") == true then
		return true
	end
	if CombatHelper.arePowersDisabled(character, abilityId) then
		return false
	end
	if character:GetAttribute(GameConstants.BUSY_ATTRIBUTE) == true then
		return false
	end
	if character:GetAttribute(GameConstants.MG_HAIR_SWITCHING_ATTRIBUTE) == true then
		return false
	end
	if character:GetAttribute(GameConstants.MG_TK_CONTROLLED_ATTRIBUTE) == true then
		return false
	end
	if character:GetAttribute(GameConstants.MG_SLAM_HELD_ATTRIBUTE) == true then
		return false
	end
	if character:GetAttribute(GameConstants.MG_ASTRAL_BODY_ATTRIBUTE) == true then
		if abilityId ~= "telepathic_pain"
			and abilityId ~= "telepathic_outburst"
		then
			return false
		end
	elseif character:GetAttribute(GameConstants.MG_ASTRAL_ATTRIBUTE) == true then
		return false
	end
	if AbilityCooldownHelper.isOnCooldown(character, abilityId) then
		return false
	end
	if AbilityCooldownHelper.isActive(character, abilityId) then
		return false
	end
	if
		(
			abilityId == "mind_link"
			or abilityId == "astral_projection"
		)
		and MarvelGirlService.lookOf(character) ~= "marvel_girl"
		and MarvelGirlService.lookOf(character) ~= "xmen_red"
		and character:GetAttribute(GameConstants.MG_HAIR_TIED_ATTRIBUTE) ~= true
	then
		return false
	end
	if character:GetAttribute(GameConstants.TK_ACTIVE_ATTRIBUTE) == true and abilityId ~= "telekinesis" then
		return false
	end
	-- One ability at a time (flight + mind link do not block; astral allowed with barrier)
	for _, ab in CharacterRegistry.getAbilities("jean_grey") do
		if ab.passive or ab.id == abilityId or ab.id == "telekinetic_flight" or ab.id == "mind_link" or ab.id == "telekinesis"
			or (ab.id == "psionic_barrier" and character:GetAttribute("MgDarkPhoenix") == true)
		then
			continue
		end
		if abilityId == "astral_projection" and ab.id == "psionic_barrier" then
			continue
		end
		if (abilityId == "telepathic_pain" or abilityId == "telepathic_outburst" or abilityId == "psionic_barrier")
			and (ab.id == "astral_projection" or ab.id == "psionic_barrier")
		then
			continue
		end
		if abilityId == "telepathic_outburst" and ab.id == "telepathic_pain" then
			continue
		end
		if AbilityCooldownHelper.isActive(character, ab.id) then
			return false
		end
	end
	if energy > 0 and not CharacterService.spendEnergy(character, energy) then
		return false
	end
	return true
end

--[[ Lock victim abilities while pulled / pushed / slammed. ]]
local function setVictimControlled(victim: Model, locked: boolean)
	if locked then
		victim:SetAttribute(GameConstants.MG_TK_CONTROLLED_ATTRIBUTE, true)
		victim:SetAttribute(GameConstants.BUSY_ATTRIBUTE, true)
	else
		if victim:GetAttribute(GameConstants.MG_TK_CONTROLLED_ATTRIBUTE) == true then
			victim:SetAttribute(GameConstants.MG_TK_CONTROLLED_ATTRIBUTE, nil)
			victim:SetAttribute(GameConstants.BUSY_ATTRIBUTE, nil)
		end
	end
end

local function isValidTkVictim(victim: Model?, jean: Model): boolean
	if not victim or victim == jean or not victim.Parent then
		return false
	end
	local hum = CombatHelper.getHumanoid(victim)
	local root = getRoot(victim)
	if not hum or not root or hum.Health <= 0 or root.Anchored then
		return false
	end
	if victim:GetAttribute(GameConstants.MG_ASTRAL_ATTRIBUTE) == true then
		return false
	end
	if not CombatHelper.isCombatEligible(victim) then
		return false
	end
	return true
end

local AIM_LOCK_RADIUS = 12
local AIM_POINT_RADIUS = 10

local function distPointToRay(point: Vector3, origin: Vector3, dir: Vector3, range: number): number
	if dir.Magnitude < 0.01 then
		return math.huge
	end
	local unit = dir.Unit
	local to = point - origin
	local along = to:Dot(unit)
	if along < 0 or along > range then
		return math.huge
	end
	return (point - (origin + unit * along)).Magnitude
end

local function resolveSingleTkTarget(
	jean: Model,
	jeanRoot: BasePart,
	target: Model?,
	direction: Vector3?,
	aimPoint: Vector3?,
	range: number,
	lockOn: boolean?
): Model?
	local function inRange(model: Model?): boolean
		if not isValidTkVictim(model, jean) then
			return false
		end
		local tRoot = getRoot(model)
		return tRoot ~= nil and (tRoot.Position - jeanRoot.Position).Magnitude <= range
	end

	-- Client hover / lock: accept anyone in range (don't require HRP to sit on Jean's look ray)
	if inRange(target) then
		return target
	end
	if lockOn ~= true then
		return nil
	end

	-- Cursor world point: nearest character around the aim hit
	if aimPoint then
		local bestNear: Model? = nil
		local bestNearDist = AIM_POINT_RADIUS
		for _, model in CombatHelper.overlapCharacters(aimPoint, AIM_POINT_RADIUS, jean, true) do
			if not inRange(model) then
				continue
			end
			local tRoot = getRoot(model)
			if not tRoot then
				continue
			end
			local d = (tRoot.Position - aimPoint).Magnitude
			if d < bestNearDist then
				bestNearDist = d
				bestNear = model
			end
		end
		if bestNear then
			return bestNear
		end
	end

	local aimDir = if direction and direction.Magnitude > 0.05
		then direction.Unit
		elseif aimPoint
		then Vector3.new(aimPoint.X - jeanRoot.Position.X, aimPoint.Y - jeanRoot.Position.Y, aimPoint.Z - jeanRoot.Position.Z)
		else jeanRoot.CFrame.LookVector
	if aimDir.Magnitude < 0.05 then
		aimDir = jeanRoot.CFrame.LookVector
	else
		aimDir = aimDir.Unit
	end

	local along = CombatHelper.raycastCharacter(jeanRoot.Position, aimDir, range, jean, true)
	if inRange(along) then
		return along
	end

	local best: Model? = nil
	local bestDist = AIM_LOCK_RADIUS
	for _, model in CombatHelper.overlapCharacters(jeanRoot.Position, range, jean, true) do
		if not inRange(model) then
			continue
		end
		local r = getRoot(model)
		if not r then
			continue
		end
		local d = distPointToRay(r.Position, jeanRoot.Position, aimDir, range)
		if d < bestDist then
			bestDist = d
			best = model
		end
	end
	return best
end

local function resolveCursorTarget(
	jean: Model,
	jeanRoot: BasePart,
	target: Model?,
	hitPart: Instance?,
	direction: Vector3?,
	aimPoint: Vector3?,
	range: number,
	lockOn: boolean?
): Model?
	local function inRange(model: Model?): boolean
		if not isValidTkVictim(model, jean) then
			return false
		end
		local tRoot = getRoot(model)
		return tRoot ~= nil and (tRoot.Position - jeanRoot.Position).Magnitude <= range
	end

	if inRange(target) then
		return target
	end
	if hitPart and hitPart:IsA("BasePart") then
		local fromPart = CombatHelper.getCharacterFromPart(hitPart)
		if inRange(fromPart) then
			return fromPart
		end
	end
	if lockOn ~= true then
		return nil
	end
	local aimDir = if direction and direction.Magnitude > 0.05
		then direction.Unit
		elseif aimPoint
		then Vector3.new(aimPoint.X - jeanRoot.Position.X, aimPoint.Y - jeanRoot.Position.Y, aimPoint.Z - jeanRoot.Position.Z)
		else jeanRoot.CFrame.LookVector
	if aimDir.Magnitude < 0.05 then
		aimDir = jeanRoot.CFrame.LookVector
	else
		aimDir = aimDir.Unit
	end
	local along = CombatHelper.raycastCharacter(jeanRoot.Position, aimDir, range, jean, true)
	if inRange(along) then
		return along
	end
	return nil
end

local function finishAbility(character: Model, abilityId: string, cooldown: number)
	AbilityCooldownHelper.setActive(character, abilityId, false)
	AbilityCooldownHelper.applyAfterUse(character, abilityId, cooldown)
	CharacterService.markAbilityUse(character)
end

local function attachCloneToPart(template: Instance, part: BasePart, emitCount: number?, keepAttachmentTransform: boolean?): Instance?
	local clone = template:Clone()
	if clone:IsA("Attachment") and not keepAttachmentTransform then
		clone.Position = Vector3.zero
		clone.Orientation = Vector3.zero
	end
	clone.Parent = part
	VfxHelper.setParticlesEnabled(clone, true)
	-- ponytail: :Emit() disabled repo-wide per request (see VfxHelper.emitAllParticles).
	return clone
end

local function getDirectBodyParts(model: Model): { BasePart }
	local parts: { BasePart } = {}
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") then
			table.insert(parts, child)
		end
	end
	return parts
end

local function makeFxHost(name: string, cf: CFrame): BasePart
	local host = Instance.new("Part")
	host.Name = name
	host.Size = Vector3.new(0.2, 0.2, 0.2)
	host.Transparency = 1
	host.Anchored = true
	host.CanCollide = false
	host.CanQuery = false
	host.CanTouch = false
	host.CastShadow = false
	host.CFrame = cf
	host.Parent = Workspace
	return host
end

local function playWorldSound(soundId: string, at: Vector3, volume: number?, playbackSpeed: number?, maxDuration: number?)
	local host = makeFxHost("MgSfx", CFrame.new(at))
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume or 0.85
	sound.PlaybackSpeed = playbackSpeed or 1
	sound.RollOffMaxDistance = 120
	sound.RollOffMinDistance = 12
	sound.Parent = host
	if sound.IsLoaded then
		sound:Play()
	else
		sound.Loaded:Once(function()
			if sound.Parent then
				sound:Play()
			end
		end)
	end
	sound.Ended:Once(function()
		if host.Parent then
			host:Destroy()
		end
	end)
	-- maxDuration cuts a long clip short with a quick fade (overlapping meteor impacts stacked into a wall of sound).
	if maxDuration and maxDuration > 0.3 then
		task.delay(maxDuration - 0.3, function()
			if sound.Parent then
				TweenService:Create(sound, TweenInfo.new(0.3), { Volume = 0 }):Play()
			end
		end)
	end
	task.delay(maxDuration or 8, function()
		if sound.Parent then
			sound:Stop()
		end
		if host.Parent then
			host:Destroy()
		end
	end)
end

--[[ Play on a living part so break SFX starts as soon as the asset is ready (preloaded). ]]
local function playAttachedSound(parent: Instance, soundId: string, volume: number?, playbackSpeed: number?)
	local sound = Instance.new("Sound")
	sound.Name = "MgAttachedSfx"
	sound.SoundId = soundId
	sound.Volume = volume or 1
	sound.PlaybackSpeed = playbackSpeed or 1
	sound.RollOffMaxDistance = 140
	sound.RollOffMinDistance = 8
	sound.Parent = parent
	if sound.IsLoaded then
		sound:Play()
	else
		sound.Loaded:Once(function()
			if sound.Parent then
				sound:Play()
			end
		end)
	end
	sound.Ended:Once(function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
	task.delay(8, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

local function playLoopingAttachedSound(parent: Instance, soundId: string, volume: number?): Sound
	local sound = Instance.new("Sound")
	sound.Name = "MgPainLoop"
	sound.SoundId = soundId
	sound.Volume = volume or 0.9
	sound.Looped = true
	sound.RollOffMaxDistance = 140
	sound.RollOffMinDistance = 8
	sound.Parent = parent
	if sound.IsLoaded then
		sound:Play()
	else
		sound.Loaded:Once(function()
			if sound.Parent then
				sound:Play()
			end
		end)
	end
	return sound
end

local function fadeStopSound(sound: Sound?, fadeSec: number)
	if not sound or not sound.Parent then
		return
	end
	local tween = TweenService:Create(sound, TweenInfo.new(fadeSec, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Volume = 0,
	})
	tween:Play()
	tween.Completed:Once(function()
		if sound.Parent then
			sound:Stop()
			sound:Destroy()
		end
	end)
	task.delay(fadeSec + 0.4, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

--[[ Smooth yaw turn toward a world point (bolt / debris throws). ]]
-- Thin wrapper over the shared CastFaceHelper (same system Hex Bolt/Beam,
-- Probability Hex, etc. all use now) - kept as a local alias so every
-- existing smoothFaceToward(...) call site below needs no changes.
local function smoothFaceToward(character: Model, worldPoint: Vector3, holdSeconds: number?)
	CastFaceHelper.faceToward(character, worldPoint, holdSeconds)
end

local function retireFx(inst: Instance, fade: number?, deleteAfter: number?)
	if not inst.Parent then
		return
	end
	VfxHelper.smoothDisableParticles(inst, fade or 0.25)
	local delaySec = deleteAfter or 3
	task.delay(delaySec, function()
		if inst.Parent then
			local parent = inst.Parent
			inst:Destroy()
			if parent:IsA("BasePart") and parent.Name:sub(1, 2) == "Mg" and parent.Parent then
				parent:Destroy()
			end
		end
	end)
end

-- Rogue's absorbed Jean powers (Telekinesis/Slam/Debris) must look like the skin they
-- were absorbed FROM (color, Phoenix/Marvel Girl variants), not Rogue's own look -
-- she stamps that skin here when she casts one; Jean herself never sets it.
function MarvelGirlService.lookOf(character: Model): any
	local absorbed = character:GetAttribute("MgAbsorbedSkin")
	if type(absorbed) == "string" then
		return absorbed
	end
	return character:GetAttribute(GameConstants.LOOK_MODE_ATTRIBUTE)
end

--[[ Recolor Jean ability FX: X-Men '97 blue, Marvel Girl pink. ]]
-- skinOverride lets a caller without their own LOOK_MODE_ATTRIBUTE (Rogue)
-- reproduce the look-specific color/accent for whichever skin the power was
-- absorbed FROM - defaults to the caster's own attribute (Jean's normal
-- case) when omitted.
local function isJean97(character: Model?, skinOverride: string?): boolean
	if not character then
		return false
	end
	local skin = skinOverride or MarvelGirlService.lookOf(character)
	-- X-Men Red is pink like Marvel Girl, not the base '97 blue.
	if skin == "marvel_girl" or skin == "xmen_red" or GameConstants.PHOENIX_LOOK_IDS[skin] then
		return false
	end
	return true
end

local function jeanAccent(character: Model?, skinOverride: string?): Color3
	local skin = skinOverride or (character and MarvelGirlService.lookOf(character))
	if GameConstants.PHOENIX_LOOK_IDS[skin] == true then
		return GameConstants.MG_PSI_COLOR_PHOENIX
	end
	if isJean97(character, skinOverride) then
		return GameConstants.MG_PSI_COLOR
	end
	return GameConstants.MG_PSI_COLOR_MARVEL_GIRL
end

-- Exported so Rogue's absorbed bolts use Jean's real accent color logic
-- (Phoenix/classic/Marvel Girl look) instead of a guessed hardcoded RGB.
MarvelGirlService.jeanAccentColor = jeanAccent

local function jeanScreenTint(character: Model?, skinOverride: string?): Color3
	local skin = skinOverride or (character and MarvelGirlService.lookOf(character))
	if skin == "marvel_girl" or skin == "xmen_red" then
		return GameConstants.MG_PSI_COLOR_MARVEL_GIRL
	end
	if GameConstants.PHOENIX_LOOK_IDS[skin] == true then
		return GameConstants.MG_PSI_COLOR_PHOENIX
	end
	return GameConstants.MG_PSI_COLOR
end

-- Backward compatible: an existing call site passing only path segments (getPhoenixAsset("Foo", "Bar"))
-- keeps resolving under JeanGreyThePhoenixForce exactly as before. Passing the caster's character as the
-- FIRST argument (getPhoenixAsset(character, "Foo", "Bar")) makes it skin-aware instead - the New X-Men
-- Phoenix skin has its own parallel Assets.JeanGrey.JeanGreyNewXMen folder ("the rest is same inside as
-- phoenix" per request), everyone else still gets JeanGreyThePhoenixForce.
local function getPhoenixAsset(first: (Model | string)?, ...: string): Instance?
	local folder = "JeanGreyThePhoenixForce"
	if typeof(first) == "Instance" and first:IsA("Model") then
		if first:GetAttribute(GameConstants.LOOK_MODE_ATTRIBUTE) == "phoenix_new_xmen" then
			folder = "JeanGreyNewXMen"
		end
		return VfxHelper.getMarvelGirlAsset(folder, ...)
	end
	return VfxHelper.getMarvelGirlAsset(folder, first :: string, ...)
end

-- Every Phoenix-only piece of Jean's kit (wings, Meteor Shower, Telepathic
-- Pain, Cosmic Aura Burn, the visual-only placeholders, ...) is grouped under
-- this ONE top-level local instead of each getting its own - this file's main
-- chunk has a hard 200-local-variable ceiling (Luau register limit) shared by
-- every top-level `local`/`local function` in it, and it was already close to
-- that before any of this kit existed. Each `do ... end` block below is its
-- own lexical scope, so its internal helpers/state tables don't add to that
-- count either - only the fields hung on Phoenix (and Phoenix itself) do.
local Phoenix = {}

-- Instances from the last endPowerFx/clearPowerFx that are still mid fade-out
-- (Destroy is delayed 3s so particles already in flight can die naturally).
-- A rapid re-trigger (TK grab/release spam, flight begin/finish flicker)
-- used to leave these orphaned while beginPowerFx spun up a brand new set on
-- top - two overlapping generations of hand/eye VFX read as "stuck on"/
-- glitching. beginPowerFx force-clears whatever's still pending here first.
Phoenix.pendingPowerFxCleanup = {} :: { [Model]: { Instance } }

-- Shared per-victim burn VFX (Cosmic Aura Burn, Phoenix Wrath, Flame Combo
-- all call these instead of each rolling their own): clones BurnMorph's
-- per-body-part particles (Assets.JeanGrey.JeanGreyThePhoenixForce.BurnMorph
-- - one BasePart per body part, e.g. UpperTorso, each holding the particles
-- for that part) onto the matching named part of whoever's burning.
-- Ref-counted so a victim caught by two burn sources at once (e.g. Aura +
-- Wrath) doesn't get double-cloned particles or have the first source's
-- end() strip the second source's fire early.
do
	local burnVfxByVictim: { [Model]: { Instance } } = {}
	local burnVfxRefs: { [Model]: number } = {}

	local function collectParticleEmitters(root: Instance, out: { ParticleEmitter })
		if root:IsA("ParticleEmitter") then
			table.insert(out, root)
		end
		for _, desc in root:GetDescendants() do
			if desc:IsA("ParticleEmitter") then
				table.insert(out, desc)
			end
		end
	end

	function Phoenix.beginBurnVfx(victim: Model)
		burnVfxRefs[victim] = (burnVfxRefs[victim] or 0) + 1
		if burnVfxByVictim[victim] then
			return
		end
		local template = getPhoenixAsset("BurnMorph")
		if not template or not template:IsA("Model") then
			return
		end
		local spawned: { Instance } = {}
		local emitters: { ParticleEmitter } = {}
		for _, sourcePart in template:GetChildren() do
			if not sourcePart:IsA("BasePart") then
				continue
			end
			local destName = if sourcePart.Name == "HumanoidRootPart" then "UpperTorso" else sourcePart.Name
			local destPart = victim:FindFirstChild(destName) or victim:FindFirstChild(sourcePart.Name)
			if not destPart or not destPart:IsA("BasePart") then
				continue
			end
			for _, child in sourcePart:GetChildren() do
				local clone = child:Clone()
				clone.Parent = destPart
				table.insert(spawned, clone)
				collectParticleEmitters(clone, emitters)
			end
		end
		if #spawned == 0 then
			return
		end
		for _, pe in emitters do
			pe.Enabled = true
		end
		burnVfxByVictim[victim] = spawned
	end

	function Phoenix.endBurnVfx(victim: Model)
		local refs = (burnVfxRefs[victim] or 1) - 1
		burnVfxRefs[victim] = if refs > 0 then refs else nil
		if refs > 0 then
			return
		end
		local spawned = burnVfxByVictim[victim]
		if not spawned then
			return
		end
		burnVfxByVictim[victim] = nil
		for _, inst in spawned do
			local emitters: { ParticleEmitter } = {}
			collectParticleEmitters(inst, emitters)
			for _, pe in emitters do
				pe.Enabled = false
			end
		end
		task.delay(2, function()
			for _, inst in spawned do
				if inst.Parent then
					inst:Destroy()
				end
			end
		end)
	end
end

do
	local jeanWingsByCharacter: { [Model]: Instance } = {}
	-- Ref-counted (flight and the manual Character Configuration toggle both
	-- call these) so flight ending doesn't rip wings out from under a
	-- player who turned them on manually, and turning the manual toggle off
	-- mid-flight doesn't hide them either - whoever's still holding a ref
	-- keeps them up.
	local jeanWingsRefs: { [Model]: number } = {}

	function Phoenix.usesDarkFlight(character: Model): boolean
		if character:GetAttribute("MgDarkPhoenix") ~= true then
			return false
		end
		local owner = Players:GetPlayerFromCharacter(character)
		return not owner or owner:GetAttribute("DarkFlightVfx") ~= false
	end

	function Phoenix.wingsSuppressed(character: Model): boolean
		local owner = Players:GetPlayerFromCharacter(character)
		return owner ~= nil and owner:GetAttribute("WingsSuppressed") == true
	end

	function Phoenix.attachWings(character: Model)
	if GameConstants.PHOENIX_LOOK_IDS[MarvelGirlService.lookOf(character)] ~= true or Phoenix.wingsSuppressed(character) then
		return
	end
	jeanWingsRefs[character] = (jeanWingsRefs[character] or 0) + 1
	if jeanWingsByCharacter[character] then
		return
	end
	local root = getRoot(character)
	-- getPhoenixAsset is now skin-aware (character passed as the first arg) - New X-Men Phoenix pulls
	-- from its own Assets.JeanGrey.JeanGreyNewXMen.Wings instead of JeanGreyThePhoenixForce's.
	local template = getPhoenixAsset(character, "Wings")
	-- Dark Phoenix swaps the wings for her own flight VFX (Settings toggle, mirrored onto the player by ClientPrefsService), sat on the back of the upper torso.
	local darkFlight: Instance? = nil
	if Phoenix.usesDarkFlight(character) then
		local assets = ReplicatedStorage:FindFirstChild("Assets")
		local jean = assets and assets:FindFirstChild("JeanGrey")
		local force = jean and jean:FindFirstChild("JeanGreyThePhoenixForce")
		darkFlight = force and force:FindFirstChild("DarkPhoenixFlight")
		if darkFlight and darkFlight:IsA("BasePart") then
			template = darkFlight
		else
			darkFlight = nil
		end
	end
	if MarvelGirlService.lookOf(character) == "phoenix_new_xmen" then
		warn(string.format(
			"[Phoenix.attachWings] skin=phoenix_new_xmen root=%s template=%s templateClass=%s",
			tostring(root ~= nil),
			tostring(template ~= nil),
			if template then template.ClassName else "nil"
		))
	end
	if not root or not template then
		return
	end
	local wings = template:Clone()
	wings.Name = "PhoenixWings"
	if wings:IsA("BasePart") then
		wings.Anchored = false
		wings.CanCollide = false
		wings.CanQuery = false
		wings.CanTouch = false
		wings.Massless = true
		-- WeldConstraint has no C0/C1 offset - it just locks Part0/Part1's
		-- relative CFrame at the moment it's created, so the 90-degree offset
		-- has to be baked into this CFrame before the weld goes on.
		local rotationCFrame = root.CFrame * CFrame.Angles(0, math.rad(-90), 0)
		local upperTorso = character:FindFirstChild("UpperTorso")
		local backRef = (upperTorso and upperTorso:IsA("BasePart")) and upperTorso or root
		local desiredPos = backRef.Position - backRef.CFrame.LookVector * (backRef.Size.Z / 2) + Vector3.new(0, 0.7, 0)
		wings.CFrame = CFrame.new(desiredPos) * (rotationCFrame - rotationCFrame.Position)
		if darkFlight then
			wings.CFrame = backRef.CFrame * CFrame.new(0, 0, backRef.Size.Z / 2) * CFrame.Angles(0, math.rad(-90), 0)
		end
		wings.Parent = character
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = if darkFlight then backRef else root
		weld.Part1 = wings
		weld.Parent = wings
	else
		wings:Destroy()
		return
	end
	jeanWingsByCharacter[character] = wings
	character:SetAttribute(GameConstants.PHOENIX_WINGS_ACTIVE_ATTRIBUTE, true)
	end

	function Phoenix.removeWings(character: Model)
		local refs = jeanWingsRefs[character]
		if refs then
			refs -= 1
			if refs > 0 then
				jeanWingsRefs[character] = refs
				return
			end
			jeanWingsRefs[character] = nil
		end
		local wings = jeanWingsByCharacter[character]
		if not wings then
			return
		end
		jeanWingsByCharacter[character] = nil
		character:SetAttribute(GameConstants.PHOENIX_WINGS_ACTIVE_ATTRIBUTE, nil)
		if wings.Parent then
			VfxHelper.retireFxSmooth(wings, 0.8, 1.6)
		end
	end

	function Phoenix.hasWings(character: Model): boolean
		return jeanWingsByCharacter[character] ~= nil
	end

	-- Bypasses the ref count entirely - removeWings only decrements by one, so a character that died
	-- mid-flight (flight's own ref never got a matching removeWings call, since death doesn't run the
	-- normal end-flight cleanup) kept an orphaned wings instance attached and visible the moment she
	-- was no longer dead/faded - "still gets her wings during resurrection". Used by tryPhoenixDown to
	-- guarantee a clean slate before she revives.
	function Phoenix.forceRemoveWings(character: Model)
		jeanWingsRefs[character] = nil
		local wings = jeanWingsByCharacter[character]
		if wings then
			jeanWingsByCharacter[character] = nil
			character:SetAttribute(GameConstants.PHOENIX_WINGS_ACTIVE_ATTRIBUTE, nil)
			if wings.Parent then
				wings:Destroy()
			end
		end
	end

	-- Separate from the clone-based wing PART above (jeanWingsByCharacter) -
	-- these are Attachments named "Wings" baked directly into the Phoenix
	-- morph's UpperTorso, each already holding its own particles/beams.
	-- Nothing to build/destroy, just enable or disable what's already there.
	function Phoenix.setMorphWingsVisible(character: Model, visible: boolean)
		local upperTorso = character:FindFirstChild("UpperTorso")
		if not upperTorso then
			return
		end
		for _, att in upperTorso:GetChildren() do
			if att:IsA("Attachment") and att.Name == "Wings" then
				for _, child in att:GetChildren() do
					if child:IsA("ParticleEmitter") or child:IsA("Beam") then
						child.Enabled = visible
					end
				end
			end
		end
	end
end

-- skinOverride lets a caller without their own LOOK_MODE_ATTRIBUTE (Rogue)
-- reproduce the look-specific tint for whichever skin the power was
-- absorbed FROM - see jeanAccent's own comment.
local function styleJeanFx(root: Instance, lifeSeconds: number?, character: Model?, skinOverride: string?)
	local color = jeanAccent(character, skinOverride)
	local seq = ColorSequence.new(color)
	local function paint(inst: Instance)
		if inst:IsA("ParticleEmitter") then
			inst.Color = seq
			if lifeSeconds then
				inst.Lifetime = NumberRange.new(lifeSeconds * 0.35, lifeSeconds)
			end
		elseif inst:IsA("Beam") then
			inst.Color = seq
		elseif inst:IsA("Trail") then
			inst.Color = seq
			if lifeSeconds then
				inst.Lifetime = lifeSeconds
			end
		elseif inst:IsA("PointLight") or inst:IsA("SpotLight") then
			inst.Color = color
		elseif inst:IsA("Highlight") then
			inst.FillColor = color
			inst.OutlineColor = color
		end
	end
	paint(root)
	for _, desc in root:GetDescendants() do
		paint(desc)
	end
end

local function findBaseJeanHeadPart(character: Model): BasePart?
	local head = character:FindFirstChild("Head")
	if not head then
		return nil
	end
	local other = head:FindFirstChild("Other")
	if not other then
		return nil
	end
	local part = other:FindFirstChild("HeadPart")
	if part and part:IsA("BasePart") then
		return part
	end
	return nil
end

Phoenix.HEAD_GLOW_FADE = 0.4 -- a field, not a local: this module sits at the 200-local ceiling

-- Ends the glow: the particles taper out first (Rate to 0), then the material goes back.
local function restoreJeanHeadPart(state: { headPart: BasePart?, headPartMaterial: Enum.Material?, headEmitters: { [ParticleEmitter]: number }? })
	local part = state.headPart
	local material = state.headPartMaterial
	local emitters = state.headEmitters
	state.headPart = nil
	state.headPartMaterial = nil
	state.headEmitters = nil
	if part then
		part:SetAttribute("MgHeadGlowOn", false)
	end
	if emitters then
		for em, rate in emitters do
			if em.Parent then
				local tween = TweenService:Create(em, TweenInfo.new(Phoenix.HEAD_GLOW_FADE, Enum.EasingStyle.Sine), { Rate = 0 })
				tween:Play()
				task.delay(Phoenix.HEAD_GLOW_FADE, function()
					if em.Parent then
						em.Enabled = false
						em.Rate = rate
					end
				end)
			end
		end
	end
	if part and material then
		task.delay(if emitters then Phoenix.HEAD_GLOW_FADE else 0, function()
			-- A new ability may have lit the head again in the meantime.
			if part.Parent and part:GetAttribute("MgHeadGlowOn") ~= true then
				part.Material = material
			end
		end)
	end
end

local function beginJeanHeadGlow(character: Model, state: { headPart: BasePart?, headPartMaterial: Enum.Material?, headEmitters: { [ParticleEmitter]: number }? })
	if state.headPart then
		return
	end
	local part = findBaseJeanHeadPart(character)
	if not part then
		return
	end
	state.headPart = part
	-- A fade-out still pending from the last ability must not leave Neon recorded as the "original" material.
	local material = part.Material
	local savedBase = part:GetAttribute("MgHeadGlowBase")
	if material ~= Enum.Material.Neon then
		part:SetAttribute("MgHeadGlowBase", material.Name)
	elseif type(savedBase) == "string" then
		material = Enum.Material[savedBase]
	end
	state.headPartMaterial = material
	part:SetAttribute("MgHeadGlowOn", true)
	part.Material = Enum.Material.Neon
	-- The particles inside HeadPart.Attachment fade in (Rate 0 -> authored) instead of popping on.
	local emitters: { [ParticleEmitter]: number } = {}
	local attachment = part:FindFirstChild("Attachment")
	if attachment then
		for _, d in attachment:GetDescendants() do
			if d:IsA("ParticleEmitter") then
				-- The authored Rate is remembered on the emitter, so a re-light mid-fade can't record a half-faded one.
				local baseRate = d:GetAttribute("MgBaseRate")
				if type(baseRate) ~= "number" then
					baseRate = d.Rate
					d:SetAttribute("MgBaseRate", baseRate)
				end
				emitters[d] = baseRate
				d.Rate = 0
				d.Enabled = true
				TweenService:Create(d, TweenInfo.new(Phoenix.HEAD_GLOW_FADE, Enum.EasingStyle.Sine), { Rate = baseRate }):Play()
			end
		end
	end
	state.headEmitters = emitters
end

local function smoothEnableFx(fx: Instance, duration: number?)
	VfxHelper.setParticlesEnabled(fx, true)
end

local function beginPowerFx(character: Model)
	local existing = powerFxByCharacter[character]
	if existing then
		existing.refs += 1
		beginJeanHeadGlow(character, existing)
		return
	end
	local pending = Phoenix.pendingPowerFxCleanup[character]
	if pending then
		Phoenix.pendingPowerFxCleanup[character] = nil
		for _, inst in pending do
			if inst.Parent then
				inst:Destroy()
			end
		end
	end
	local instances: { Instance } = {}
	local right = getHand(character, true)
	local left = getHand(character, false)
	if GameConstants.PHOENIX_LOOK_IDS[MarvelGirlService.lookOf(character)] == true then
		local templates: { Instance } = {}
		for i = 1, 5 do
			local template = getPhoenixAsset(character, "HandVFX", "ParticleEmitter" .. tostring(i))
			if template then
				table.insert(templates, template)
			end
		end
		for _, hand in { right, left } do
			if hand then
				for _, template in templates do
					local fx = attachCloneToPart(template, hand, 1)
					if fx then
						styleJeanFx(fx, nil, character)
						smoothEnableFx(fx, 0.25)
						table.insert(instances, fx)
					end
				end
			end
		end
		-- Cosmic Energy: shared choke point (beginPowerFx/attachPowerFx) means
		-- this is active for every ability that touches power fx - Bolt,
		-- Shield, Meteor Shower, and the placeholder kit alike - with no
		-- per-ability wiring needed.
		local cosmicTemplate = getPhoenixAsset(character, "CosmicEnergy")
		local cosmicRoot = getRoot(character)
		if cosmicTemplate and cosmicRoot then
			local fx = attachCloneToPart(cosmicTemplate, cosmicRoot, 1)
			if fx then
				styleJeanFx(fx, nil, character)
				smoothEnableFx(fx, 0.25)
				table.insert(instances, fx)
			end
		end
		local eyeHead = getHead(character)
		if eyeHead then
			for _, eyeName in { "EyeAttachmentVFX1", "EyeAttachmentVFX2" } do
				local eyeTemplate = getPhoenixAsset(character, "EyeVFX", eyeName)
				if eyeTemplate then
					-- keepAttachmentTransform: this attachment already has its
					-- own authored Position for the head - don't zero it out.
					local fx = attachCloneToPart(eyeTemplate, eyeHead, 1, true)
					if fx then
						styleJeanFx(fx, nil, character)
						smoothEnableFx(fx, 0.25)
						table.insert(instances, fx)
					end
				end
			end
		end
		powerFxByCharacter[character] = { instances = instances, refs = 1 }
		beginJeanHeadGlow(character, powerFxByCharacter[character])
		return
	end
	-- New hand VFX asset (Marvel Girl skin only): same attachment cloned to
	-- both hands. Base Jean keeps the old HandVFXRight/LeftAttachment assets.
	-- Always recolored via styleJeanFx (MG_PSI_COLOR_MARVEL_GIRL) regardless
	-- of which asset it came from - "everything about Marvel Girl" uses the
	-- one accent color, not whatever the source asset happened to be authored with.
	-- X-Men Red has its own hand asset (recolored pink below like Marvel Girl's).
	local xmenRedHand = if MarvelGirlService.lookOf(character) == "xmen_red"
		then VfxHelper.getMarvelGirlAsset("XMenRed", "HandVFXAttachment")
		else nil
	local newHandTemplate = xmenRedHand
		or (MarvelGirlService.lookOf(character) == "marvel_girl"
			and VfxHelper.getMarvelGirlAsset("MarvelGirlHandVFXAttachment"))
	local rightTemplate = newHandTemplate
		or VfxHelper.getMarvelGirlAsset("HandVFXRightAttachment")
		or VfxHelper.getMarvelGirlAsset("HandAttachment")
	local leftTemplate = newHandTemplate
		or VfxHelper.getMarvelGirlAsset("HandVFXLeftAttachment")
		or VfxHelper.getMarvelGirlAsset("HandAttachment")
	if right and rightTemplate then
		local fx = attachCloneToPart(rightTemplate, right, 1)
		if fx then
			styleJeanFx(fx, nil, character)
			smoothEnableFx(fx, 0.25)
			table.insert(instances, fx)
		end
	end
	if left and left ~= right and leftTemplate then
		local fx = attachCloneToPart(leftTemplate, left, 1)
		if fx then
			styleJeanFx(fx, nil, character)
			smoothEnableFx(fx, 0.25)
			table.insert(instances, fx)
		end
	end
	local headTemplate = VfxHelper.getMarvelGirlAsset("HeadAttachment")
		or VfxHelper.getMarvelGirlAsset("MentalPower") -- fallback old name
	local head = getHead(character)
	if headTemplate and head then
		local fx = attachCloneToPart(headTemplate, head)
		if fx then
			styleJeanFx(fx, nil, character)
			smoothEnableFx(fx, 0.25)
			table.insert(instances, fx)
		end
	end
	powerFxByCharacter[character] = { instances = instances, refs = 1 }
	beginJeanHeadGlow(character, powerFxByCharacter[character])
end

function Phoenix.scheduleFxFadeOut(character: Model, instances: { Instance })
	Phoenix.pendingPowerFxCleanup[character] = instances
	for _, inst in instances do
		if inst.Parent then
			VfxHelper.smoothDisableParticles(inst, 0.4)
			task.delay(3, function()
				-- Only clear the pending-cleanup slot if it's still this exact
				-- generation - a rapid re-trigger's beginPowerFx may already
				-- have force-cleared and replaced it.
				if Phoenix.pendingPowerFxCleanup[character] == instances then
					Phoenix.pendingPowerFxCleanup[character] = nil
				end
				if inst.Parent then
					inst:Destroy()
				end
			end)
		end
	end
end

local function endPowerFx(character: Model)
	local fx = powerFxByCharacter[character]
	if not fx then
		return
	end
	fx.refs -= 1
	if fx.refs > 0 then
		return
	end
	powerFxByCharacter[character] = nil
	restoreJeanHeadPart(fx)
	Phoenix.scheduleFxFadeOut(character, fx.instances)
end

local manualHandVfxByPlayer: { [Player]: boolean } = {}

--[[ Cosmetic, player-toggled hand/head VFX (Character Configurations panel).
	Reuses the existing ref-counted beginPowerFx/endPowerFx (same particles
	an ability temporarily turns on) via a "manual" ref, so it layers safely
	under anything an ability is doing instead of fighting it. ]]
function MarvelGirlService.toggleCosmeticHandVfx(player: Player): boolean
	local character = player.Character
	if not character or character:GetAttribute(GameConstants.HERO_ATTRIBUTE) ~= "jean_grey" then
		return false
	end
	local nowOn = not manualHandVfxByPlayer[player]
	manualHandVfxByPlayer[player] = nowOn
	if nowOn then
		beginPowerFx(character)
	else
		endPowerFx(character)
	end
	return nowOn
end

local function clearManualHandVfx(player: Player)
	if not manualHandVfxByPlayer[player] then
		return
	end
	manualHandVfxByPlayer[player] = nil
	local character = player.Character
	if character then
		endPowerFx(character)
	end
end

local manualWingsByPlayer: { [Player]: boolean } = {}

--[[ Cosmetic, player-toggled wings (Character Configurations panel), same
	ref-counted pattern as the hand VFX toggle above - layers safely under
	flight, which holds its own ref on Phoenix.attachWings/removeWings. ]]
function MarvelGirlService.togglePhoenixWings(player: Player, desired: boolean?): boolean
	local character = player.Character
	if not character
		or character:GetAttribute(GameConstants.HERO_ATTRIBUTE) ~= "jean_grey"
		or GameConstants.PHOENIX_LOOK_IDS[MarvelGirlService.lookOf(character)] ~= true
	then
		return false
	end
	-- The button reflects whether wings are actually attached (flight attaches them too), so a plain flip
	-- turned "Off" into a second ref on while flying - the client now sends the state it wants.
	local nowOn = if desired ~= nil then desired else not manualWingsByPlayer[player]
	if nowOn then
		player:SetAttribute("WingsSuppressed", nil)
		if manualWingsByPlayer[player] then
			return true
		end
		manualWingsByPlayer[player] = true
		Phoenix.attachWings(character)
		Phoenix.setMorphWingsVisible(character, not Phoenix.usesDarkFlight(character))
	else
		manualWingsByPlayer[player] = nil
		-- Off means off: drops every ref (flight's included) and keeps flight from putting them back up.
		player:SetAttribute("WingsSuppressed", true)
		Phoenix.forceRemoveWings(character)
		Phoenix.setMorphWingsVisible(character, false)
	end
	return nowOn
end

local function clearManualWings(player: Player)
	if not manualWingsByPlayer[player] then
		return
	end
	manualWingsByPlayer[player] = nil
	local character = player.Character
	if character then
		Phoenix.removeWings(character)
		Phoenix.setMorphWingsVisible(character, false)
	end
end

-- Force-clear all refs (cancel / death)
local function clearPowerFx(character: Model)
	local fx = powerFxByCharacter[character]
	if not fx then
		return
	end
	powerFxByCharacter[character] = nil
	restoreJeanHeadPart(fx)
	Phoenix.scheduleFxFadeOut(character, fx.instances)
end

local function attachPowerFx(character: Model)
	beginPowerFx(character)
end

local function stripCloneAnimators(model: Model)
	for _, desc in model:GetDescendants() do
		if desc:IsA("Animator") then
			for _, track in desc:GetPlayingAnimationTracks() do
				track:Stop(0)
				track:Destroy()
			end
			desc:Destroy()
		elseif desc.Name == "Animate" or desc:IsA("LocalScript") or desc:IsA("Script") then
			desc:Destroy()
		elseif desc:IsA("AnimationController") then
			desc:Destroy()
		end
	end
end

local function freezeBodyInPlace(player: Player, character: Model)
	local root = getRoot(character)
	local hum = CombatHelper.getHumanoid(character)
	if not root or not hum then
		return
	end
	bodyHoldByPlayer[player] = {
		anchored = root.Anchored,
		walk = hum.WalkSpeed,
		jumpPower = if hum.UseJumpPower then hum.JumpPower else nil,
		jumpHeight = if not hum.UseJumpPower then hum.JumpHeight else nil,
		autoRotate = hum.AutoRotate,
	}
	-- No Anchored=true here - startAstral only allows this while grounded
	-- now, so zeroed WalkSpeed/velocity/AutoRotate is enough to keep her in
	-- place without also freezing her mid-air if she were ever airborne.
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	hum.WalkSpeed = 0
	hum.AutoRotate = false
	if hum.UseJumpPower then
		hum.JumpPower = 0
	else
		hum.JumpHeight = 0
	end
	hum:Move(Vector3.zero, false)
end

local function unfreezeBody(player: Player, character: Model?)
	local hold = bodyHoldByPlayer[player]
	bodyHoldByPlayer[player] = nil
	if not hold or not character then
		return
	end
	local root = getRoot(character)
	local hum = CombatHelper.getHumanoid(character)
	if root then
		root.Anchored = hold.anchored
	end
	if hum and hum.Parent then
		hum.WalkSpeed = hold.walk
		hum.AutoRotate = hold.autoRotate
		if hold.jumpPower ~= nil then
			hum.JumpPower = hold.jumpPower
		end
		if hold.jumpHeight ~= nil then
			hum.JumpHeight = hold.jumpHeight
		end
	end
end

local function resolveAimDir(character: Model, direction: Vector3?, aimPoint: Vector3?): Vector3
	local root = getRoot(character)
	local origin = if root then root.Position else character:GetPivot().Position
	if aimPoint then
		local d = aimPoint - origin
		if d.Magnitude > 0.05 then
			return d.Unit
		end
	end
	if direction and direction.Magnitude > 0.05 then
		return direction.Unit
	end
	if root then
		return root.CFrame.LookVector
	end
	return Vector3.new(0, 0, -1)
end

----------------------------------------------------------------
-- Psionic Bolt
----------------------------------------------------------------
-- Real effect, no identity gate - castPsionicBolt below is Jean Grey's own
-- gated entry point; RogueService calls this directly. isPhoenix naturally
-- reads false for a caller without that skin attribute (Rogue), same as
-- Crystal's Concentration multiplier - no special-casing needed.
function MarvelGirlService.castPsionicBoltEffect(player: Player, direction: Vector3?, aimPoint: Vector3?, skinOverride: string?)
	local character = player.Character
	if not character then
		return
	end
	local entry = CharacterRegistry.getAbilityById("jean_grey", "psionic_bolt")
	if not entry then
		return
	end

	local resolvedSkin = skinOverride or MarvelGirlService.lookOf(character)
	local isPhoenix = GameConstants.PHOENIX_LOOK_IDS[resolvedSkin] == true

	AbilityCooldownHelper.setActive(character, entry.id, true)
	character:SetAttribute(GameConstants.BUSY_ATTRIBUTE, true)
	CombatHelper.lockMovementBriefly(character, 0.25)
	attachPowerFx(character)
	playJeanAnim(character, if isPhoenix then GameConstants.MG_PSI_BOLT_PHOENIX_ANIM else GameConstants.MG_PSI_BOLT_ANIM, false)
	fireCameraShake(player, 0.5, 0.38, 0.36, 0.55)
	-- Phoenix fires the sound once per bolt release (below, at each hand),
	-- not once upfront - every other look plays it once here at cast start,
	-- matching her single bolt.
	if not isPhoenix then
		local boltRoot = getRoot(character)
		if boltRoot then
			playWorldSound(pickPsiBoltSound(), boltRoot.Position, 0.85)
		end
	end
	if aimPoint then
		character:SetAttribute("MgBoltAim", aimPoint)
		smoothFaceToward(character, aimPoint, 0.55)
	elseif direction and direction.Magnitude > 0.05 then
		local root = getRoot(character)
		if root then
			smoothFaceToward(character, root.Position + direction.Unit * 40, 0.55)
		end
	end

	-- Token kept as a character Attribute, not a new module-level table -
	-- this file is already near Luau's 200-top-level-local ceiling (see the
	-- Phoenix-kit note above), and an Attribute needs no new top-level local.
	local myBoltWindupToken = (character:GetAttribute("MgBoltWindupToken") or 0) + 1
	character:SetAttribute("MgBoltWindupToken", myBoltWindupToken)
	task.spawn(function()
		local hum = CombatHelper.getHumanoid(character)
		local walk = if hum then hum.WalkSpeed else GameConstants.DEFAULT_WALK_SPEED
		local jumpPower = if hum then hum.JumpPower else nil
		local jumpHeight: number? = nil
		if hum then
			pcall(function()
				jumpHeight = hum.JumpHeight
			end)
			hum.WalkSpeed = 0
			hum.JumpPower = 0
			pcall(function()
				hum.JumpHeight = 0
			end)
			pcall(function()
				hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
			end)
			hum:Move(Vector3.zero, false)
			-- Saved as Attributes (not locals) so cancelAll can restore the same
			-- values if it bumps the token before this wait resumes - same
			-- register-limit reason as the token above.
			character:SetAttribute("MgBoltWindupWalk", walk)
			character:SetAttribute("MgBoltWindupJump", jumpPower)
			character:SetAttribute("MgBoltWindupJumpHeight", jumpHeight)
		end
		task.wait(GameConstants.MG_PSI_BOLT_WINDUP)
		local stillCurrent = character:GetAttribute("MgBoltWindupToken") == myBoltWindupToken
		if hum and hum.Parent and stillCurrent then
			hum.WalkSpeed = walk
			if jumpPower ~= nil then
				hum.JumpPower = jumpPower
			end
			if jumpHeight ~= nil then
				hum.JumpHeight = jumpHeight
			end
			pcall(function()
				hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
			end)
		end
		if character.Parent then
			character:SetAttribute(GameConstants.BUSY_ATTRIBUTE, nil)
			character:SetAttribute("MgBoltWindupWalk", nil)
			character:SetAttribute("MgBoltWindupJump", nil)
			character:SetAttribute("MgBoltWindupJumpHeight", nil)
		end
		local function fireBoltFrom(origin: Vector3, customVisual: Instance?)
			ScreenFeelHelper.pulseCharacter(character, { intensity = 0.12, duration = 0.12 })
			local liveAim = character:GetAttribute("MgBoltAim")
			local shotAim: Vector3? = if typeof(liveAim) == "Vector3" then liveAim else aimPoint
			local dir: Vector3
			if shotAim then
				local toAim = shotAim - origin
				dir = if toAim.Magnitude > 0.05 then toAim.Unit else resolveAimDir(character, direction, shotAim)
			else
				dir = resolveAimDir(character, direction, nil)
			end
			ProjectileHelper.spawn(origin, dir, {
				speed = GameConstants.MG_PSI_BOLT_SPEED,
				damage = if isPhoenix then GameConstants.MG_PSI_BOLT_PHOENIX_DAMAGE else GameConstants.MG_PSI_BOLT_DAMAGE,
				radius = GameConstants.MG_PSI_BOLT_HIT_RADIUS,
				maxDistance = GameConstants.MG_PSI_BOLT_RANGE,
				color = jeanAccent(character, resolvedSkin),
				owner = character,
				homeDir = dir,
				homePoint = shotAim,
				homeAfter = 0.08,
				homeTurnScale = 1.4, -- was 0.78, barely tracked the cursor at all
				steerable = true,
				liveHomeAimAttribute = "MgBoltAim",
				-- Phoenix uses her own BoltImpactAttachment asset (below) instead
				-- of the generic "psionic" flash classic Jean's bolt keeps.
				impactFx = if isPhoenix then "none" else "psionic",
				boltFolder = "JeanGrey",
				boltAsset = "PsychicBolt",
				customVisual = customVisual,
				recolorVisual = customVisual == nil,
				onHit = function(victim: Model)
					local tint = jeanScreenTint(character, resolvedSkin)
					ScreenFeelHelper.setTint(victim, tint, 0.7)
					ScreenFeelHelper.pulseCharacter(victim, {
						intensity = 0.28,
						duration = 0.32,
						fovScale = 0.22,
						vignetteScale = 0.35,
						tint = tint,
						tintDuration = 0.55,
					})
				end,
				onImpact = if isPhoenix
					then function(pos: Vector3)
						VfxHelper.spawnAttachmentImpact(getPhoenixAsset(character, "BoltImpactAttachment"), pos, {
							emitCount = 5,
							lifetime = 1.2,
						})
					end
					else nil,
			})
		end

		if isPhoenix then
			-- Left hand first, then right hand shortly after - both re-aim at
			-- whatever the live cursor is at the moment they actually fire.
			local phoenixBoltTemplate = getPhoenixAsset(character, "Bolts")
			if not phoenixBoltTemplate then
				warn("[MarvelGirl] Missing Phoenix bolt asset (Assets.JeanGrey.JeanGreyThePhoenixForce.Bolts)")
			end
			-- Pull the spawn point back behind the hand (opposite of where she's
			-- facing) instead of spawning it right at the hand's surface - with
			-- a trail attached, spawning AT the hand made it read as starting
			-- from mid-air/the hand's center instead of from the hand itself.
			local function pulledBackHandOrigin(hand: BasePart): Vector3
				local faceRoot = getRoot(character)
				local back = if faceRoot then -faceRoot.CFrame.LookVector else Vector3.new(0, 0, 1)
				return hand.Position + back * GameConstants.MG_PSI_BOLT_PHOENIX_BACK_OFFSET
			end
			task.wait(GameConstants.MG_PSI_BOLT_PHOENIX_DELAY_1)
			if character.Parent and player.Character == character then
				local leftHand = getHand(character, false)
				if leftHand then
					playWorldSound(pickPsiBoltSound(), leftHand.Position, 0.85)
					fireBoltFrom(pulledBackHandOrigin(leftHand), if phoenixBoltTemplate then phoenixBoltTemplate:Clone() else nil)
				end
			end
			task.wait(GameConstants.MG_PSI_BOLT_PHOENIX_DELAY_2)
			if character.Parent and player.Character == character then
				local rightHand = getHand(character, true)
				if rightHand then
					playWorldSound(pickPsiBoltSound(), rightHand.Position, 0.85)
					fireBoltFrom(pulledBackHandOrigin(rightHand), if phoenixBoltTemplate then phoenixBoltTemplate:Clone() else nil)
				end
			end
		else
			for i = 1, GameConstants.MG_PSI_BOLT_COUNT do
				if not character.Parent or player.Character ~= character then
					break
				end
				local head = getHead(character)
				local headPos = if head then head.Position else character:GetPivot().Position
				-- Spawn from a random point around the head, still aimed at live cursor / aim
				local jitter = Vector3.new(
					(math.random() * 2 - 1) * 1.15,
					(math.random() * 2 - 1) * 0.75,
					(math.random() * 2 - 1) * 1.15
				)
				fireBoltFrom(headPos + jitter, nil)
				if i < GameConstants.MG_PSI_BOLT_COUNT then
					task.wait(GameConstants.MG_PSI_BOLT_SPACING)
				end
			end
		end
		if character.Parent then
			character:SetAttribute("MgBoltAim", nil)
			endPowerFx(character)
			if AbilityCooldownHelper.isActive(character, entry.id) then
				local cooldown = if isPhoenix then GameConstants.MG_PSI_BOLT_PHOENIX_COOLDOWN else GameConstants.MG_PSI_BOLT_COOLDOWN
				finishAbility(character, entry.id, cooldown)
			end
		end
	end)
end

local function castPsionicBolt(player: Player, direction: Vector3?, aimPoint: Vector3?)
	local character = player.Character
	if not character then
		return
	end
	local entry = CharacterRegistry.getAbilityById("jean_grey", "psionic_bolt")
	if not entry or not canUse(character, entry.id, GameConstants.MG_PSI_BOLT_ENERGY) then
		return
	end
	MarvelGirlService.castPsionicBoltEffect(player, direction, aimPoint)
end

----------------------------------------------------------------
-- Phoenix kit: Meteor Shower (real) + 4 visual-only placeholders
----------------------------------------------------------------

do

-- Straight down (dir = (0,-1,0)) is the tested-correct orientation
-- CFrame.Angles(0, 0, math.rad(90)) - this finds the minimal rotation that
-- carries world-down to the meteor's actual (possibly tilted) travel
-- direction, then applies that same 90-degree roll on top, so an angled
-- meteor's "down" face still points along wherever it's actually heading
-- instead of always straight down.
local function meteorRotationFor(dir: Vector3): CFrame
	local down = Vector3.new(0, -1, 0)
	local to = if dir.Magnitude > 0.01 then dir.Unit else down
	local axis = down:Cross(to)
	local dot = math.clamp(down:Dot(to), -1, 1)
	local turn: CFrame
	if axis.Magnitude < 0.001 then
		if dot > 0 then
			turn = CFrame.identity
		else
			local ortho = if math.abs(down:Dot(Vector3.xAxis)) < 0.9 then Vector3.xAxis else Vector3.zAxis
			turn = CFrame.fromAxisAngle(down:Cross(ortho).Unit, math.pi)
		end
	else
		turn = CFrame.fromAxisAngle(axis.Unit, math.acos(dot))
	end
	return turn * CFrame.Angles(0, 0, math.rad(90))
end

-- Picks a random descent angle (up to MG_METEOR_MAX_TILT_DEGREES off
-- vertical) and places the sky origin so the straight-line path FROM that
-- origin THROUGH targetPoint is exactly along that angle - i.e. the meteor
-- always actually reaches targetPoint, it just approaches from a random
-- oblique angle instead of always coming straight down. Raycasts the
-- candidate path first and retries with a fresh random yaw/tilt (shrinking
-- toward straight down each attempt) if something's in the way - a building
-- overhang etc. could otherwise block an oblique approach that a straight
-- drop would've cleared fine.
local function meteorOriginAndDirection(targetPoint: Vector3, caster: Model?): (Vector3, Vector3)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if caster then { caster } else {}
	local height = GameConstants.MG_METEOR_SKY_HEIGHT
	local maxTilt = GameConstants.MG_METEOR_MAX_TILT_DEGREES

	for attempt = 1, 4 do
		-- Each failed attempt narrows the tilt range so the last try or two
		-- lean close to straight down, which is the likeliest to be clear.
		local attemptMaxTilt = maxTilt * (1 - (attempt - 1) / 4)
		local tilt = math.rad(math.random() * attemptMaxTilt)
		local yaw = math.random() * math.pi * 2
		local horizontalOffset = height * math.tan(tilt)
		local origin = targetPoint + Vector3.new(math.cos(yaw) * horizontalOffset, height, math.sin(yaw) * horizontalOffset)
		local toTarget = targetPoint - origin
		local hit = Workspace:Raycast(origin, toTarget, params)
		-- A hit very close to targetPoint is just the ground/target itself,
		-- not an obstruction blocking the approach.
		if not hit or (hit.Position - targetPoint).Magnitude < 4 then
			return origin, toTarget.Unit
		end
	end

	-- Every angled attempt was blocked - fall straight down instead.
	local origin = targetPoint + Vector3.new(0, height, 0)
	return origin, Vector3.new(0, -1, 0)
end

-- Channeled: a few meteors one after another, all thrown at the point the cursor was on when X was pressed.
-- Smoothly fades an instance's parts to invisible, disables its particles,
-- then destroys it - used for both the meteor visual itself on impact and
-- the ground-impact VFX once its lingering time is up. Never touches CFrame,
-- so it never introduces any rotation change.
local function fadeAndRemove(inst: Instance, waitBefore: number)
	task.delay(waitBefore, function()
		if not inst.Parent then
			return
		end
		local fadeTime = 1.2
		-- Ramp particles down over the same span as the part fade instead of
		-- cutting them off instantly - they used to vanish well before the
		-- part itself finished fading out.
		VfxHelper.smoothDisableParticles(inst, fadeTime)
		local parts: { BasePart } = {}
		if inst:IsA("BasePart") then
			table.insert(parts, inst)
		end
		for _, desc in inst:GetDescendants() do
			if desc:IsA("BasePart") then
				table.insert(parts, desc)
			end
		end
		for _, part in parts do
			TweenService:Create(part, TweenInfo.new(fadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Transparency = 1,
			}):Play()
		end
		task.delay(fadeTime, function()
			if inst.Parent then
				inst:Destroy()
			end
		end)
	end)
end

-- Pressing X throws the shower straight at wherever the mouse cursor is at that moment: no ground cursor, no
-- confirming click, and the aim isn't tracked afterwards. A cursor past MG_METEOR_AIM_RANGE is pulled in to it.
function Phoenix.castMeteorShower(player: Player, aimPoint: Vector3?)
	local character = player.Character
	if not character then
		return
	end
	local entry = CharacterRegistry.getAbilityById("jean_grey", "meteor_shower")
	if not entry or not canUse(character, entry.id, GameConstants.MG_METEOR_ENERGY_PER_METEOR) then
		return
	end
	local root = getRoot(character)
	if not root or aimPoint == nil or CombatHelper.arePowersDisabled(character) or character:GetAttribute(GameConstants.BUSY_ATTRIBUTE) == true then
		return
	end
	local offset = aimPoint - root.Position
	local target = if offset.Magnitude > GameConstants.MG_METEOR_AIM_RANGE
		then root.Position + offset.Unit * GameConstants.MG_METEOR_AIM_RANGE
		else aimPoint
	Phoenix.runMeteorShower(player, character, entry, target)
end

-- Experimental: rock blocks rise out of the ground around a meteor impact, matching whatever it hit
-- (part material/color, or the terrain's), then sink back. Purely visual - anchored, no collision/query.
function Phoenix.spawnImpactBlocks(pos: Vector3, ignore: { Instance })
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local filter = table.clone(ignore)
	params.FilterDescendantsInstances = filter
	local hit = Workspace:Raycast(pos + Vector3.new(0, 6, 0), Vector3.new(0, -30, 0), params)
	-- Never copy a character's look: skip any body the ray lands on and keep going down to the real ground.
	for _ = 1, 8 do
		local body = hit and CombatHelper.getCharacterFromPart(hit.Instance)
		if not body then
			break
		end
		table.insert(filter, body)
		params.FilterDescendantsInstances = filter
		hit = Workspace:Raycast(pos + Vector3.new(0, 6, 0), Vector3.new(0, -30, 0), params)
	end
	if not hit then
		return
	end
	local material = hit.Material
	local color = Color3.fromRGB(110, 100, 90)
	local variant = ""
	local surfaceLooks: { Instance } = {}
	local meshTexture = ""
	if hit.Instance:IsA("Terrain") then
		-- Throws "Unsupported terrain material" for materials terrain has no colour for (Air, etc.) - keep the default.
		local okColor, terrainColor = pcall(function()
			return Workspace.Terrain:GetMaterialColor(material)
		end)
		if okColor then
			color = terrainColor
		end
	elseif hit.Instance:IsA("BasePart") then
		color = hit.Instance.Color
		material = hit.Instance.Material
		variant = hit.Instance.MaterialVariant
		-- Same surface look: SurfaceAppearance / Textures on the hit part are cloned onto every block.
		for _, child in hit.Instance:GetChildren() do
			if child:IsA("SurfaceAppearance") or child:IsA("Texture") or child:IsA("Decal") then
				table.insert(surfaceLooks, child)
			end
		end
		-- A MeshPart's own TextureID has no Part equivalent, so it is re-applied as a Texture on every face.
		if hit.Instance:IsA("MeshPart") and hit.Instance.TextureID ~= "" then
			meshTexture = hit.Instance.TextureID
		end
	end
	local groundY = hit.Position.Y
	local rng = Random.new()
	-- Three loose rings (denser near the meteor, sparser outward): each block gets a jittered angle/radius,
	-- its own size, and a tilt, but still reads as rubble radiating from the impact instead of scatter.
	local rings = {
		{ count = 10, radius = 4.5, minSize = 1.4, maxSize = 2.6 },
		{ count = 12, radius = 7.5, minSize = 0.9, maxSize = 2.0 },
		{ count = 10, radius = 10.5, minSize = 0.6, maxSize = 1.4 },
	}
	local rise = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local sink = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local tiny = Vector3.new(0.05, 0.05, 0.05)
	local folder = Instance.new("Folder")
	folder.Name = "MgMeteorImpactBlocks"
	folder.Parent = Workspace
	for ringIndex, ring in rings do
		local step = (math.pi * 2) / ring.count
		local offset = rng:NextNumber(0, step)
		for i = 1, ring.count do
			local angle = offset + (i - 1) * step + rng:NextNumber(-step * 0.35, step * 0.35)
			local radius = ring.radius + rng:NextNumber(-1.1, 1.1)
			local size = rng:NextNumber(ring.minSize, ring.maxSize)
			local outward = Vector3.new(math.cos(angle), 0, math.sin(angle))
			local flat = Vector3.new(pos.X + outward.X * radius, groundY, pos.Z + outward.Z * radius)
			-- Same outward-facing base as a clean ring, with only a small random yaw/pitch/roll around it.
			local rot = CFrame.lookAt(Vector3.zero, outward)
				* CFrame.Angles(rng:NextNumber(-0.3, 0.05), rng:NextNumber(-0.35, 0.35), rng:NextNumber(-0.15, 0.15))
			local finalSize = Vector3.new(size * rng:NextNumber(0.9, 1.6), size * rng:NextNumber(0.7, 1.5), size)
			local block = Instance.new("Part")
			block.Anchored = true
			block.CanCollide = false
			block.CanQuery = false
			block.CanTouch = false
			block.Massless = true
			block.Material = material
			block.Color = color
			block.MaterialVariant = variant
			for _, look in surfaceLooks do
				look:Clone().Parent = block
			end
			if meshTexture ~= "" then
				for _, face in Enum.NormalId:GetEnumItems() do
					local tex = Instance.new("Texture")
					tex.Texture = meshTexture
					tex.Face = face
					tex.StudsPerTileU = 4
					tex.StudsPerTileV = 4
					tex.Parent = block
				end
			end
			block.TopSurface = Enum.SurfaceType.Smooth
			block.BottomSurface = Enum.SurfaceType.Smooth
			block.Size = tiny
			block.CFrame = CFrame.new(flat) * rot
			block.Parent = folder
			-- Where the block ends up resting (the sink tween below starts from here).
			local rest = flat + Vector3.new(0, finalSize.Y * 0.35, 0)
			local restRot = rot
			local delayIn = (ringIndex - 1) * 0.03 + rng:NextNumber(0, 0.05)
			if rng:NextNumber() < 0.3 then
				-- Debris: thrown outward and up with a tumble, lands back near its ring slot.
				task.delay(delayIn, function()
					if not block.Parent then
						return
					end
					block.Size = finalSize
					local vel = outward * rng:NextNumber(10, 22) + Vector3.new(0, rng:NextNumber(22, 38), 0)
					local spin = Vector3.new(rng:NextNumber(-6, 6), rng:NextNumber(-6, 6), rng:NextNumber(-6, 6))
					local position = flat + Vector3.new(0, finalSize.Y * 0.5, 0)
					local orientation = rot
					local t0 = os.clock()
					local last = t0
					while block.Parent do
						local now = os.clock()
						local dt = now - last
						last = now
						vel += Vector3.new(0, -85 * dt, 0)
						position += vel * dt
						orientation = CFrame.Angles(spin.X * dt, spin.Y * dt, spin.Z * dt) * orientation
						local restY = groundY + finalSize.Y * 0.35
						if position.Y <= restY and vel.Y < 0 then
							position = Vector3.new(position.X, restY, position.Z)
							block.CFrame = CFrame.new(position) * orientation.Rotation
							rest = position
							restRot = orientation.Rotation
							break
						end
						block.CFrame = CFrame.new(position) * orientation.Rotation
						if now - t0 > 3 then
							break
						end
						task.wait()
					end
				end)
			else
				task.delay(delayIn, function()
					if block.Parent then
						TweenService:Create(block, rise, { Size = finalSize, CFrame = CFrame.new(rest) * rot }):Play()
					end
				end)
			end
			task.delay(GameConstants.MG_METEOR_VFX_LIFETIME + 0.4 + (ringIndex - 1) * 0.05, function()
				if block.Parent then
					-- Quick fade while dropping back into the ground (no shrink).
					TweenService:Create(block, sink, { Transparency = 1, CFrame = CFrame.new(rest - Vector3.new(0, 1.5, 0)) * restRot }):Play()
					for _, child in block:GetChildren() do
						if child:IsA("Texture") or child:IsA("Decal") then
							TweenService:Create(child, sink, { Transparency = 1 }):Play()
						end
					end
				end
			end)
		end
	end
	task.delay(GameConstants.MG_METEOR_VFX_LIFETIME + 2, function()
		folder:Destroy()
	end)
end

-- Drops a point straight down onto the real ground (terrain/parts), skipping characters and `ignore`, so an impact
-- never happens at the height of a body, a flying target or the meteor itself.
function Phoenix.groundAt(pos: Vector3, ignore: { Instance }): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local filter = table.clone(ignore)
	for _ = 1, 8 do
		params.FilterDescendantsInstances = filter
		local hit = Workspace:Raycast(pos + Vector3.new(0, 4, 0), Vector3.new(0, -200, 0), params)
		if not hit then
			return pos
		end
		local body = CombatHelper.getCharacterFromPart(hit.Instance)
		if not body then
			return hit.Position
		end
		table.insert(filter, body)
	end
	return pos
end

function Phoenix.runMeteorShower(player: Player, character: Model, entry: CharacterRegistry.AbilityDef, initialTarget: Vector3)
	local root = getRoot(character)
	if not root then
		return
	end
	local meteorTemplate = getPhoenixAsset(character, "MeteorShower", "Meteor")
	local vfxTemplate = getPhoenixAsset(character, "MeteorShower", "MeteorVFX")
	if not meteorTemplate then
		warn("[MarvelGirl] Missing Phoenix meteor asset (Assets.JeanGrey.JeanGreyThePhoenixForce.MeteorShower.Meteor)")
	end
	if not vfxTemplate then
		warn("[MarvelGirl] Missing Phoenix meteor impact asset (Assets.JeanGrey.JeanGreyThePhoenixForce.MeteorShower.MeteorVFX)")
	end

	character:SetAttribute("MgMeteorAim", nil)
	AbilityCooldownHelper.setActive(character, entry.id, true)
	attachPowerFx(character)
	fireCameraShake(player, 0.55, 0.4, 0.4, 0.6)
	playJeanAnim(character, GameConstants.MG_METEOR_SHOWER_ANIM, false)

	-- Locked in place for the whole shower (per request) - previously nothing
	-- here touched WalkSpeed/BUSY at all, so she could freely run around
	-- mid-animation while meteors kept firing at wherever she was aiming.
	local meteorHum = CombatHelper.getHumanoid(character)
	local savedWalk = if meteorHum then meteorHum.WalkSpeed else nil
	character:SetAttribute(GameConstants.BUSY_ATTRIBUTE, true)
	if meteorHum then
		meteorHum.WalkSpeed = 0
	end

	local auraFx: Instance? = nil
	local auraTemplate = getPhoenixAsset(character, "MeteorShower", "CharacterAura")
	if auraTemplate and auraTemplate:IsA("BasePart") then
		local fx = auraTemplate:Clone()
		fx.Name = "PhoenixMeteorCharacterAura"
		fx.Anchored = false
		fx.CanCollide = false
		fx.CanQuery = false
		fx.CanTouch = false
		fx.Massless = true
		fx.CFrame = root.CFrame
		fx.Parent = character
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = fx
		weld.Parent = fx
		VfxHelper.setParticlesEnabled(fx, true)
		smoothEnableFx(fx, 0.25)
		VfxHelper.emitAllParticles(fx, 12)
		auraFx = fx
	elseif not auraTemplate then
		warn("[MarvelGirl] Missing Phoenix meteor aura asset (Assets.JeanGrey.JeanGreyThePhoenixForce.MeteorShower.CharacterAura)")
	end

	-- Interrupts (ragdoll, death, powers locked) end this session. A meteor already thrown still lands and cleans
	-- itself up completely; an interrupt only stops the NEXT meteor from being thrown.
	local showerSession = require(script.Parent.AbilitySession).begin(character, "meteor_shower", 20)
	task.spawn(function()
		for i = 1, 2 do
			if showerSession.ended or not character.Parent or player.Character ~= character then
				break
			end
			-- Spent per meteor as it actually fires, not upfront - if she runs
			-- out mid-shower, the remaining meteors just don't fire.
			if not CharacterService.spendEnergy(character, GameConstants.MG_METEOR_ENERGY_PER_METEOR) then
				break
			end
			local targetPoint = initialTarget
			-- The second meteor goes to wherever the cursor is NOW (the client streams it as X_aim while this runs).
			local liveAim = character:GetAttribute("MgMeteorAim")
			if i > 1 and typeof(liveAim) == "Vector3" then
				local liveOffset = liveAim - root.Position
				targetPoint = if liveOffset.Magnitude > GameConstants.MG_METEOR_AIM_RANGE
					then root.Position + liveOffset.Unit * GameConstants.MG_METEOR_AIM_RANGE
					else liveAim
			end
			targetPoint = Phoenix.groundAt(targetPoint, { character })
			local origin, dir = meteorOriginAndDirection(targetPoint, character)
			-- Small caster shake each time a meteor is actually summoned, not
			-- just once at cast start - separate from the target-only impact
			-- pulse in onImpact below.
			fireCameraShake(player, 0.3, 0.2, 0.2, 0.25)
			local meteorVisual = if meteorTemplate then meteorTemplate:Clone() else nil
			-- Backstop: if the projectile ends without ever reporting an impact (owner gone, out of range),
			-- the kept visual must not be left hanging in the world.
			if meteorVisual then
				local flightTime = (origin - targetPoint).Magnitude / math.max(GameConstants.MG_METEOR_SPEED, 1)
				task.delay(flightTime + 3, function()
					if meteorVisual.Parent then
						fadeAndRemove(meteorVisual, 0.2)
					end
				end)
			end
			-- Each meteor lands (sound, blocks, knockback, ragdoll) exactly once, even if the projectile
			-- reports its impact again - repeated impacts stacked into a pile of looping-sounding booms.
			local impacted = false
			ProjectileHelper.spawn(origin, dir, {
				speed = GameConstants.MG_METEOR_SPEED,
				damage = GameConstants.MG_METEOR_DAMAGE,
				radius = 3,
				maxDistance = (origin - targetPoint).Magnitude + 20,
				color = jeanAccent(character),
				owner = character,
				-- Keep whatever orientation the visual spawns with instead of
				-- continuously re-facing the travel direction every tick - and
				-- keepVisual (below) means nothing touches its CFrame again
				-- after impact either, so it never rotates on landing. The
				-- extra -90 degree pitch (local X) turns the model's forward
				-- face from "along travel direction" to "straight down".
				lockWorldRotation = meteorRotationFor(dir),
				impactAoeRadius = GameConstants.MG_METEOR_IMPACT_RADIUS,
				impactAoeDamage = GameConstants.MG_METEOR_DAMAGE,
				impactFx = "none",
				customVisual = meteorVisual,
				keepVisual = true,
				-- Falling hazard, not a thrown projectile - IW's shield
				-- deflect (ProjectileHelper.deflectNearShield) must not
				-- catch and redirect these.
				noDeflect = true,
				onImpact = function(hitPos: Vector3)
					if impacted then
						return
					end
					impacted = true
					local pos = Phoenix.groundAt(hitPos, if meteorVisual then { character, meteorVisual } else { character })
					playWorldSound(GameConstants.MG_METEOR_IMPACT_SOUND, pos, 0.35, nil, 1.4)
					Phoenix.spawnImpactBlocks(pos, if meteorVisual then { character, meteorVisual } else { character })
					if vfxTemplate and vfxTemplate:IsA("BasePart") then
						local groundFx = vfxTemplate:Clone()
						groundFx.Anchored = true
						groundFx.CanCollide = false
						groundFx.CanQuery = false
						groundFx.CanTouch = false
						-- Keep the template's own authored rotation (its bottom face is
						-- already built to sit against the ground) - only move it to
						-- the impact point, never re-rotate it.
						groundFx.CFrame = CFrame.new(pos) * (vfxTemplate.CFrame - vfxTemplate.CFrame.Position)
						groundFx.Parent = Workspace
						VfxHelper.emitByCount(groundFx)
						fadeAndRemove(groundFx, GameConstants.MG_METEOR_VFX_LIFETIME)
					end
					for _, victim in CombatHelper.overlapCharacters(pos, GameConstants.MG_METEOR_IMPACT_RADIUS, character) do
						-- Damage still lands on the shield (via ProjectileHelper's
						-- own CombatHelper.dealDamage) - only the knockback/ragdoll
						-- that would otherwise bypass a shield entirely is gated.
						if CombatHelper.isShielded(victim) then
							continue
						end
						-- Target-only screen feel per meteor impact - deliberately
						-- not fired for the caster (character), who already gets
						-- her own cast-time shake elsewhere.
						ScreenFeelHelper.pulseCharacter(victim, {
							intensity = 0.6,
							duration = 0.3,
							fovScale = 1.1,
							vignetteScale = 0.5,
						})
						local vRoot = getRoot(victim)
						if vRoot then
							local pushDir = Vector3.new(vRoot.Position.X - pos.X, 0, vRoot.Position.Z - pos.Z)
							PushHelper.applyToCharacter(victim, pushDir, {
								speed = GameConstants.MG_METEOR_PUSH_SPEED,
								upBoost = GameConstants.MG_METEOR_PUSH_UP,
								noRagdoll = true,
							})
						end
						RagdollService.applyTimed(victim, GameConstants.MG_METEOR_RAGDOLL_SECONDS)
					end
					if meteorVisual then
						fadeAndRemove(meteorVisual, 0)
					end
				end,
			})
			if i < 3 then
				task.wait(GameConstants.MG_METEOR_SPACING)
			end
		end
		showerSession:finish("done")
		if auraFx and auraFx.Parent then
			VfxHelper.retireFxSmooth(auraFx, 0.4, 0.5)
		end
		if character.Parent then
			character:SetAttribute(GameConstants.BUSY_ATTRIBUTE, nil)
			local endHum = CombatHelper.getHumanoid(character)
			if endHum and savedWalk ~= nil then
				endHum.WalkSpeed = savedWalk
			end
			endPowerFx(character)
			if AbilityCooldownHelper.isActive(character, entry.id) then
				finishAbility(character, entry.id, entry.cooldown)
			end
		end
	end)
end

-- Subatomic Disintegration / Infernal Aura / Phoenix Wrath / Flame Combo are
-- visual-only for now (per design) - a brief power flash + real cooldown, no
-- unique effect yet.
function Phoenix.castPlaceholder(player: Player, abilityId: string)
	local character = player.Character
	if not character then
		return
	end
	local entry = CharacterRegistry.getAbilityById("jean_grey", abilityId)
	if not entry or not canUse(character, entry.id, entry.energyCost) then
		return
	end
	AbilityCooldownHelper.setActive(character, entry.id, true)
	attachPowerFx(character)
	fireCameraShake(player, 0.4, 0.3, 0.3, 0.4)
	task.delay(0.5, function()
		if character.Parent then
			endPowerFx(character)
			if AbilityCooldownHelper.isActive(character, entry.id) then
				finishAbility(character, entry.id, entry.cooldown)
			end
		end
	end)
end

end -- Phoenix kit: Meteor Shower / placeholders

-- Psychic Pull (short yank toward Jean — no orbit)
----------------------------------------------------------------
local function setPullServerOwnership(model: Model): { BasePart }
	local parts: { BasePart } = {}
	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") then
			table.insert(parts, desc)
			pcall(function()
				desc:SetNetworkOwner(nil)
			end)
		end
	end
	return parts
end

local function restorePullOwnership(model: Model, parts: { BasePart })
	local plr = Players:GetPlayerFromCharacter(model)
	for _, part in parts do
		if part.Parent then
			pcall(function()
				if plr then
					part:SetNetworkOwner(plr)
				else
					part:SetNetworkOwnershipAuto()
				end
			end)
		end
	end
end

local function applyPsychicPull(victim: Model, jean: Model, skinOverride: string?)
	local vRoot = getRoot(victim)
	local jeanRoot = getRoot(jean)
	local hum = CombatHelper.getHumanoid(victim)
	if not vRoot or not jeanRoot or not hum or hum.Health <= 0 or vRoot.Anchored then
		return
	end
	if not isValidTkVictim(victim, jean) then
		return
	end

	-- Sampled before the pull's damage lands: that hit can break the shield, and a target who was shielded must not stumble.
	local wasShielded = CombatHelper.isShielded(victim)
	local ownedParts = setPullServerOwnership(victim)
	setVictimControlled(victim, true)

	local toJean = jeanRoot.Position - vRoot.Position
	local dist = toJean.Magnitude
	if dist < 0.5 then
		setVictimControlled(victim, false)
		restorePullOwnership(victim, ownedParts)
		return
	end
	local dir = toJean.Unit
	local speed = GameConstants.MG_PULL_SPEED

	local att = Instance.new("Attachment")
	att.Name = "MgPullAtt"
	att.Parent = vRoot

	local pullVel = Instance.new("LinearVelocity")
	pullVel.Name = "MgPullVel"
	pullVel.Attachment0 = att
	pullVel.RelativeTo = Enum.ActuatorRelativeTo.World
	pullVel.MaxForce = GameConstants.MG_PULL_MAX_FORCE
	pullVel.VectorVelocity = dir * speed + Vector3.new(0, 10, 0)
	pullVel.Parent = vRoot

	local alignOri = Instance.new("AlignOrientation")
	alignOri.Name = "MgPullOri"
	alignOri.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOri.Attachment0 = att
	alignOri.RigidityEnabled = false
	alignOri.MaxTorque = 180000
	alignOri.Responsiveness = GameConstants.MG_PULL_FACE_RESPONSIVENESS
	alignOri.CFrame = CFrame.lookAt(vRoot.Position, Vector3.new(jeanRoot.Position.X, vRoot.Position.Y, jeanRoot.Position.Z))
	alignOri.Parent = vRoot

	local origWalk = hum.WalkSpeed
	local origAutoRotate = hum.AutoRotate
	local token = (victim:GetAttribute("MgPullToken") :: number?) or 0
	token += 1
	victim:SetAttribute("MgPullToken", token)
	hum.WalkSpeed = 0
	hum.AutoRotate = false

	-- Initial yank + sustained LinearVelocity toward Jean
	vRoot.AssemblyLinearVelocity = dir * speed + Vector3.new(0, 6, 0)
	pcall(function()
		vRoot:ApplyImpulse(dir * vRoot.AssemblyMass * GameConstants.MG_PULL_STRENGTH)
	end)
	CombatHelper.dealDamage(jean, victim, GameConstants.MG_PULL_DAMAGE, jeanRoot.Position, "projectile")

	local pullFx: { Instance } = {}
	local pullAtts: { Attachment } = {}
	local function facePullAttachments(toward: Vector3)
		for _, fxAtt in pullAtts do
			if fxAtt.Parent then
				local pos = fxAtt.WorldPosition
				if (toward - pos).Magnitude > 0.05 then
					fxAtt.WorldCFrame = CFrame.lookAt(pos, toward)
				end
			end
		end
	end
	local pullTemplate = VfxHelper.getMarvelGirlAsset("TelekineticPull")
	if pullTemplate then
		local templates: { Attachment } = {}
		for _, child in pullTemplate:GetChildren() do
			if child:IsA("Attachment") then
				table.insert(templates, child)
			end
		end
		if #templates == 0 then
			for _, desc in pullTemplate:GetDescendants() do
				if desc:IsA("Attachment") then
					table.insert(templates, desc)
				end
			end
		end
		if #templates == 0 and pullTemplate:IsA("Attachment") then
			table.insert(templates, pullTemplate)
		end
		local fxPart = (victim:FindFirstChild("UpperTorso") or victim:FindFirstChild("Torso") or vRoot) :: Instance
		for _, template in templates do
			local clone = template:Clone()
			clone.Parent = fxPart
			styleJeanFx(clone, GameConstants.MG_PULL_FX_LIFE, jean, skinOverride)
			VfxHelper.setParticlesEnabled(clone, true)
			VfxHelper.emitAllParticles(clone, 12)
			table.insert(pullAtts, clone)
			table.insert(pullFx, clone)
			task.delay(GameConstants.MG_PULL_FX_LIFE, function()
				retireFx(clone, 0.08, GameConstants.MG_PULL_FX_LIFE)
			end)
		end
		if #templates == 0 then
			warn("[MarvelGirl] Missing attachments in Assets.JeanGrey.TelekineticPull")
		end
		facePullAttachments(jeanRoot.Position)
	else
		warn("[MarvelGirl] Missing Assets.JeanGrey.TelekineticPull")
	end

	task.spawn(function()
		local t0 = os.clock()
		local dur = math.max(GameConstants.MG_PULL_DURATION, GameConstants.MG_PULL_FACE_TIME)
		local stopDist = GameConstants.MG_PULL_STOP_DISTANCE
		while os.clock() - t0 < dur do
			if victim:GetAttribute("MgPullToken") ~= token or not victim.Parent or not vRoot.Parent then
				break
			end
			if jeanRoot.Parent then
				local flatDist = Vector3.new(
					jeanRoot.Position.X - vRoot.Position.X,
					0,
					jeanRoot.Position.Z - vRoot.Position.Z
				).Magnitude
				if flatDist <= stopDist then
					pullVel.VectorVelocity = Vector3.zero
					pullVel.MaxForce = 0
				else
					local toTarget = (jeanRoot.Position + Vector3.new(0, 1.2, 0)) - vRoot.Position
					if toTarget.Magnitude > 0.05 then
						pullVel.MaxForce = GameConstants.MG_PULL_MAX_FORCE
						pullVel.VectorVelocity = toTarget.Unit * GameConstants.MG_PULL_SPEED + Vector3.new(0, 8, 0)
					end
				end
				local facePos = Vector3.new(jeanRoot.Position.X, vRoot.Position.Y, jeanRoot.Position.Z)
				if (facePos - vRoot.Position).Magnitude > 0.05 then
					alignOri.CFrame = CFrame.lookAt(vRoot.Position, facePos)
				end
				facePullAttachments(jeanRoot.Position)
			end
			hum:Move(Vector3.zero, false)
			task.wait()
		end
		if pullVel.Parent then
			pullVel:Destroy()
		end
		if alignOri.Parent then
			alignOri:Destroy()
		end
		if att.Parent then
			att:Destroy()
		end
		-- Pull FX already scheduled for short life; clean any leftovers
		for _, fx in pullFx do
			if fx.Parent then
				retireFx(fx, 0.05, 0.15)
			end
		end
		restorePullOwnership(victim, ownedParts)
		if victim:GetAttribute("MgPullToken") == token then
			setVictimControlled(victim, false)
			if hum.Parent then
				hum.WalkSpeed = origWalk
				hum.AutoRotate = origAutoRotate
			end
			-- Landed at Jean's feet still bolt upright read as nothing happened.
			if victim.Parent and hum.Health > 0 and not wasShielded and not CombatHelper.isShielded(victim) then
				RagdollService.applyTimed(victim, GameConstants.MG_PULL_STUMBLE)
			end
		end
	end)
end

-- Exported so Rogue can use an absorbed Psychic Pull as the literal same
-- effect, not a rebuilt approximation - this function has no hero-attribute
-- gate of its own (only castPsychicPull's canUse() does, which the caller
-- is expected to have already checked), so it's exactly as safe to call
-- with any caster Model as it is with Jean herself.
MarvelGirlService.applyPsychicPullEffect = applyPsychicPull

-- Interactable prop fallback for Telekinetic Pull, same range/cursor logic
-- as TelekinesisService's prop grab so pull isn't limited to humanoids.
local function findPullPropUnderCursor(character: Model, casterRoot: BasePart, aimPoint: Vector3?, direction: Vector3?, hitPart: BasePart?): Instance?
	local inst: Instance? = nil
	if hitPart then
		inst = InteractableHelper.resolveFromPart(hitPart, character)
	end
	if not inst then
		local dir = casterRoot.CFrame.LookVector
		if direction and direction.Magnitude > 0.05 then
			dir = direction.Unit
		elseif aimPoint then
			local toAim = aimPoint - casterRoot.Position
			if toAim.Magnitude > 0.05 then
				dir = toAim.Unit
			end
		end
		inst = InteractableHelper.raycast(casterRoot.Position, dir, GameConstants.MG_PULL_RANGE, character)
	end
	if not inst or not inst.Parent then
		return nil
	end
	local part = InteractableHelper.getPushablePart(inst)
	if not part or part.Anchored then
		return nil
	end
	if (part.Position - casterRoot.Position).Magnitude > GameConstants.MG_PULL_RANGE then
		return nil
	end
	return inst
end

local function applyPsychicPullProp(inst: Instance, jean: Model)
	local part = InteractableHelper.getPushablePart(inst)
	local jeanRoot = getRoot(jean)
	if not part or part.Anchored or not jeanRoot then
		return
	end
	pcall(function()
		part:SetNetworkOwner(nil)
	end)

	local att = Instance.new("Attachment")
	att.Name = "MgPullPropAtt"
	att.Parent = part

	local pullVel = Instance.new("LinearVelocity")
	pullVel.Name = "MgPullPropVel"
	pullVel.Attachment0 = att
	pullVel.RelativeTo = Enum.ActuatorRelativeTo.World
	pullVel.MaxForce = GameConstants.MG_PULL_MAX_FORCE
	pullVel.Parent = part

	local particles = VfxHelper.attachTelekinesisParticleToPart(part)

	-- An explodable prop (oil barrel) can be pulled like any other and goes off the moment it touches the
	-- one who pulled it (merely aiming at it never does - the target queries above are quiet).
	if CombatHelper.isExplodable(part) then
		local conn: RBXScriptConnection? = nil
		conn = part.Touched:Connect(function(hit: BasePart)
			if hit:IsDescendantOf(jean) then
				if conn then
					conn:Disconnect()
				end
				CombatHelper.triggerExplodable(part)
			end
		end)
		task.delay(GameConstants.MG_PULL_DURATION + 6, function()
			if conn then
				conn:Disconnect()
			end
		end)
	end

	local token = ((part:GetAttribute("MgPullPropToken") :: number?) or 0) + 1
	part:SetAttribute("MgPullPropToken", token)

	local toJean = jeanRoot.Position - part.Position
	if toJean.Magnitude > 0.5 then
		part.AssemblyLinearVelocity = toJean.Unit * GameConstants.MG_PULL_SPEED + Vector3.new(0, 6, 0)
		pcall(function()
			part:ApplyImpulse(toJean.Unit * part.AssemblyMass * GameConstants.MG_PULL_STRENGTH)
		end)
	end

	task.spawn(function()
		local t0 = os.clock()
		local dur = GameConstants.MG_PULL_DURATION
		local stopDist = GameConstants.MG_PULL_STOP_DISTANCE + 2
		while os.clock() - t0 < dur do
			if part:GetAttribute("MgPullPropToken") ~= token or not part.Parent or not jeanRoot.Parent then
				break
			end
			local toTarget = jeanRoot.Position - part.Position
			if toTarget.Magnitude <= stopDist then
				pullVel.VectorVelocity = Vector3.zero
				pullVel.MaxForce = 0
			else
				pullVel.MaxForce = GameConstants.MG_PULL_MAX_FORCE
				pullVel.VectorVelocity = toTarget.Unit * GameConstants.MG_PULL_SPEED + Vector3.new(0, 6, 0)
			end
			task.wait()
		end
		if pullVel.Parent then
			pullVel:Destroy()
		end
		if att.Parent then
			att:Destroy()
		end
		if #particles > 0 then
			VfxHelper.fadeOutAndDestroyParticles(particles, 0.45, 2.5)
		end
		if part.Parent then
			pcall(function()
				part:SetNetworkOwnershipAuto()
			end)
		end
	end)
end

local function castPsychicPull(player: Player, target: Model?, direction: Vector3?, aimPoint: Vector3?, lockOn: boolean?, hitPart: BasePart?)
	local character = player.Character
	if not character then
		return
	end
	local entry = CharacterRegistry.getAbilityById("jean_grey", "psychic_pull")
	if not entry then
		return
	end
	local root = getRoot(character)
	if not root then
		return
	end
	local victim = resolveSingleTkTarget(
		character,
		root,
		target,
		direction,
		aimPoint,
		GameConstants.MG_PULL_RANGE,
		lockOn
	)
	if not victim then
		-- No living humanoid under the cursor: try pulling a nearby
		-- Interactable prop instead, same as Telekinesis's prop fallback.
		local propInst = findPullPropUnderCursor(character, root, aimPoint, direction, hitPart)
		if not propInst then
			return
		end
		if not canUse(character, entry.id, GameConstants.MG_PULL_ENERGY) then
			return
		end
		AbilityCooldownHelper.setActive(character, entry.id, true)
		beginPowerFx(character)
		playJeanAnim(character, GameConstants.MG_PSI_BOLT_ANIM, false)
		fireCameraShake(player, 0.5, 0.38)
		playWorldSound(GameConstants.MG_PULL_SOUND, root.Position, 0.95)
		applyPsychicPullProp(propInst, character)
		task.delay(GameConstants.MG_PULL_DURATION, function()
			if character.Parent then
				endPowerFx(character)
				finishAbility(character, entry.id, GameConstants.MG_PULL_COOLDOWN)
			end
		end)
		return
	end
	if not canUse(character, entry.id, GameConstants.MG_PULL_ENERGY) then
		return
	end

	AbilityCooldownHelper.setActive(character, entry.id, true)
	beginPowerFx(character)
	playJeanAnim(character, GameConstants.MG_PSI_BOLT_ANIM, false)
	fireCameraShake(player, 0.5, 0.38)
	local center = root.Position
	playWorldSound(GameConstants.MG_PULL_SOUND, center, 0.95)
	local victimRoot = getRoot(victim)
	if victimRoot then
		smoothFaceToward(character, victimRoot.Position, 0.4)
	end

	applyPsychicPull(victim, character)

	task.delay(GameConstants.MG_PULL_DURATION, function()
		if character.Parent then
			endPowerFx(character)
			finishAbility(character, entry.id, GameConstants.MG_PULL_COOLDOWN)
		end
	end)
end

local function attachPushVfx(vRoot: BasePart, caster: Model): { Instance }
	local fxList: { Instance } = {}
	local pushTemplate = VfxHelper.getMarvelGirlAsset("TelekineticPush")
		or VfxHelper.getMarvelGirlAsset("TelekineticPull")
	if not pushTemplate then
		warn("[MarvelGirl] Missing Assets.JeanGrey.TelekineticPush / TelekineticPull")
		return fxList
	end
	local templates: { Attachment } = {}
	if pushTemplate:IsA("Attachment") then
		table.insert(templates, pushTemplate)
	else
		for _, child in pushTemplate:GetChildren() do
			if child:IsA("Attachment") then
				table.insert(templates, child)
			end
		end
		if #templates == 0 then
			for _, desc in pushTemplate:GetDescendants() do
				if desc:IsA("Attachment") then
					table.insert(templates, desc)
				end
			end
		end
	end
	for _, template in templates do
		local clone = template:Clone()
		clone.Parent = vRoot
		styleJeanFx(clone, GameConstants.MG_PULL_FX_LIFE, caster)
		VfxHelper.setParticlesEnabled(clone, true)
		VfxHelper.emitAllParticles(clone, 14)
		table.insert(fxList, clone)
		task.delay(GameConstants.MG_PULL_FX_LIFE, function()
			retireFx(clone, 0.08, GameConstants.MG_PULL_FX_LIFE)
		end)
	end
	return fxList
end

local function launchJeanPushVictim(character: Model, victim: Model, direction: Vector3?, aimPoint: Vector3?, onPushed: (() -> ())?)
	local jeanRoot = getRoot(character)
	local vRoot = getRoot(victim)
	local vHum = CombatHelper.getHumanoid(victim)
	if not jeanRoot or not vRoot or not vHum then
		if onPushed then
			onPushed()
		end
		return
	end

	local player = Players:GetPlayerFromCharacter(character)
	if player then
		fireCameraShake(player, 0.52, 0.9, 0.32, 0.62)
	end
	smoothFaceToward(character, vRoot.Position, 0.45)
	setVictimControlled(victim, true)
	ScreenFeelHelper.setSpeedFov(victim, true)
	TelekinesisService.launchVictim(character, victim, direction, aimPoint, function(launchRoot)
		if player then
			fireCameraShake(player, 0.62, 0.42, 0.4, 0.7)
		end
		playWorldSound(GameConstants.MG_PUSH_SOUND, launchRoot.Position, 1.1)
		attachPushVfx(launchRoot, character)
		CombatHelper.dealDamage(character, victim, GameConstants.MG_PUSH_DAMAGE, launchRoot.Position, "projectile")
		-- The actual "target was pushed" moment - cooldown timing (see
		-- throwJeanTelekinesis) hangs off this, not launchVictim's onDone
		-- (which only fires ~MG_PUSH_RAGDOLL_TIME later, once the victim's
		-- recovery window ends).
		if onPushed then
			onPushed()
		end
	end, nil, function()
		if victim.Parent then
			setVictimControlled(victim, false)
			ScreenFeelHelper.setSpeedFov(victim, false)
		end
	end)
end

local function castTelekineticPush(player: Player, target: Model?, direction: Vector3?, aimPoint: Vector3?, lockOn: boolean?)
	local character = player.Character
	if not character then
		return
	end
	local jeanRoot = getRoot(character)
	if not jeanRoot then
		return
	end
	local victim = resolveSingleTkTarget(
		character,
		jeanRoot,
		target,
		direction,
		aimPoint,
		GameConstants.MG_PUSH_RANGE,
		lockOn
	)
	if not victim then
		return
	end
	beginPowerFx(character)
	fireCameraShake(player, 0.4, 0.32, 0.22, 0.35)
	launchJeanPushVictim(character, victim, direction, aimPoint)
	task.delay(0.35, function()
		if character.Parent then
			endPowerFx(character)
		end
	end)
end

local function startJeanTelekinesis(player: Player, target: Model?, aimPoint: Vector3?, hitPart: BasePart?, lockOn: boolean?)
	local character = player.Character
	if not character then
		return
	end
	if CombatHelper.arePowersDisabled(character) then
		return
	end
	local aim = aimPoint
	if not aim then
		local root = getRoot(character)
		if root then
			aim = root.Position + root.CFrame.LookVector * 20
		end
	end
	if not aim then
		return
	end
	if TelekinesisService.tryStart(player, aim, target, hitPart, lockOn) then
		beginPowerFx(character)
		fireCameraShake(player, 0.46, 0.4, 0.34, 0.58)
		local root = getRoot(character)
		if root then
			VfxHelper.spawnPulseRing(root.Position, 6, jeanAccent(character), 0.5)
		end
	end
end

local function jeanTkCooldown(character: Model): number
	if GameConstants.PHOENIX_LOOK_IDS[MarvelGirlService.lookOf(character)] == true then
		return GameConstants.MG_PHOENIX_TK_COOLDOWN
	end
	return GameConstants.MG_PUSH_COOLDOWN
end

local function releaseJeanTelekinesis(player: Player, applyCooldown: boolean?)
	local character = player.Character
	local wasActive = TelekinesisService.isActive(player)
	TelekinesisService.release(player)
	if character then
		-- endPowerFx now fires via TelekinesisService.onRelease (init()) for
		-- every release path; calling it here too double-decremented the ref count.
		if wasActive and applyCooldown ~= false then
			finishAbility(character, "telekinesis", jeanTkCooldown(character))
		else
			AbilityCooldownHelper.setActive(character, "telekinesis", false)
		end
	end
end

local function throwJeanTelekinesis(player: Player, target: Model?, direction: Vector3?, aimPoint: Vector3?)
	local character = player.Character
	if not character then
		return
	end
	if TelekinesisService.throwHeldProp(player, direction, aimPoint) then
		-- No beginPowerFx here: the hold (startJeanTelekinesis) already holds a
		-- ref, and R_throw never goes through releaseJeanTelekinesis - adding
		-- another ref here leaked one every throw, since the delayed endPowerFx
		-- below only ever drops it back to 1, not 0 (hands stayed lit until an
		-- unrelated ability's endPowerFx happened to finish it off later).
		fireCameraShake(player, 0.55, 1.05, 0.38, 0.72)
		finishAbility(character, "telekinesis", jeanTkCooldown(character))
		task.delay(GameConstants.MG_PUSH_DRAW_TIME + 0.35, function()
			if character.Parent then
				endPowerFx(character)
			end
		end)
		return
	end
	-- Same throw as Scarlet Witch's (TelekinesisService.throw) - the logic is
	-- shared, only the numbers (cooldown, range) differ per hero.
	if #TelekinesisService.getHeldModels(player) > 0 then
		local jeanRoot = getRoot(character)
		local throwDir = direction or (if jeanRoot then jeanRoot.CFrame.LookVector else Vector3.zAxis)
		TelekinesisService.throw(player, throwDir, aimPoint)
		fireCameraShake(player, 0.55, 1.05, 0.38, 0.72)
		task.delay(0.35, function()
			if character.Parent then
				endPowerFx(character)
			end
		end)
		return
	end
	local held = TelekinesisService.takeHeldForJeanPush(player)
	if #held == 0 then
		return
	end
	-- No beginPowerFx here either - same hold-ref reasoning as the
	-- throwHeldProp branch above.
	fireCameraShake(player, 0.55, 1.05, 0.38, 0.72)
	-- Cooldown now starts once the target(s) actually get pushed (the draw-in
	-- + fling sequence is async), not synchronously at the throw click - see
	-- launchJeanPushVictim's onPushed. finishOnce is also called from the
	-- safety-net delay below in case a victim never actually gets pushed
	-- (shielded mid-flight, despawned, etc.), so the ability can't get stuck
	-- permanently "active".
	local cooldownDone = false
	local function finishOnce()
		if cooldownDone then
			return
		end
		cooldownDone = true
		if character.Parent then
			finishAbility(character, "telekinesis", jeanTkCooldown(character))
		end
	end
	local pending = #held
	local function onOnePushed()
		pending -= 1
		if pending <= 0 then
			finishOnce()
		end
	end
	for _, victim in held do
		launchJeanPushVictim(character, victim, direction, aimPoint, onOnePushed)
	end
	task.delay(GameConstants.MG_PUSH_DRAW_TIME + 0.35, function()
		finishOnce()
		if character.Parent then
			endPowerFx(character)
		end
	end)
end

local function burstAtPart(part: BasePart, character: Model)
	local template = VfxHelper.getMarvelGirlAsset("HeadAttachment")
		or VfxHelper.getMarvelGirlAsset("MentalPower")
		or VfxHelper.getMarvelGirlAsset("TelekineticPush")
	if not template then
		return
	end
	local fx = attachCloneToPart(template, part, 18)
	if fx then
		styleJeanFx(fx, 0.7, character)
		task.delay(1.1, function()
			if fx.Parent then
				retireFx(fx, 0.12, 0.8)
			end
		end)
	end
end

playJeanAnim = function(character: Model, animId: string, looped: boolean?): AnimationTrack?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	local track = AnimationLoadHelper.load(animator :: Animator, animId, "MarvelGirl:" .. character.Name)
	if not track then
		return nil
	end
	track.Priority = Enum.AnimationPriority.Action4
	track.Looped = looped == true
	track:Play(0.08, 1, 1)
	return track
end

local function startAstralBodyAnim(character: Model): AnimationTrack?
	return playJeanAnim(character, GameConstants.MG_TELEKINESIS_ANIM, true)
end

local function stopAstralBodyAnim(state: AstralState)
	if state.bodyAnimTrack then
		state.bodyAnimTrack:Stop(0.12)
		state.bodyAnimTrack:Destroy()
		state.bodyAnimTrack = nil
	end
end

local function stopTelepathicPain(player: Player, applyCooldown: boolean)
	local state = painByPlayer[player]
	if not state then
		return
	end
	painByPlayer[player] = nil
	if state.animTrack then
		state.animTrack:Stop(0.2)
		state.animTrack:Destroy()
		state.animTrack = nil
	end
	if state.victimAnimTrack then
		state.victimAnimTrack:Stop(0.18)
		state.victimAnimTrack:Destroy()
		state.victimAnimTrack = nil
	end
	if state.victim.Parent then
		local victimHum = CombatHelper.getHumanoid(state.victim)
		if victimHum then
			victimHum.WalkSpeed = state.victimWalk
			if state.victimJumpPower ~= nil then
				victimHum.JumpPower = state.victimJumpPower
			end
			if state.victimJumpHeight ~= nil then
				victimHum.JumpHeight = state.victimJumpHeight
			end
			victimHum.AutoRotate = state.victimAutoRotate
			pcall(function()
				victimHum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
			end)
		end
	end
	-- Not nested under the Parent guard above: these already no-op safely on
	-- a torn-down character, and must run even if the victim's Parent check
	-- ever races, or a stuck tint/shake-hold survives until next respawn.
	ScreenFeelHelper.setShakeHold(state.victim, false)
	ScreenFeelHelper.setTint(state.victim, nil)
	state.victim:SetAttribute(GameConstants.MOVEMENT_SLOWED_ATTRIBUTE, nil)
	local astral = astralByPlayer[player]
	if astral and astral.astral.Parent then
		astral.astral:SetAttribute(GameConstants.MG_PAIN_LOOK_ATTRIBUTE, nil)
		-- Ensure pain animation on astral clone stops
		if astral.bodyAnimTrack then
			pcall(function()
				astral.bodyAnimTrack:Stop(0.2)
				astral.bodyAnimTrack:Destroy()
			end)
			astral.bodyAnimTrack = nil
		end
	end
	if state.fx and state.fx.Parent then
		VfxHelper.smoothDisableParticles(state.fx, 0.22)
		local fx = state.fx
		task.delay(1.5, function()
			if fx.Parent then
				fx:Destroy()
			end
		end)
	end
	fadeStopSound(state.sound, GameConstants.MG_PAIN_SFX_FADE)
	if state.body.Parent then
		state.body:SetAttribute(GameConstants.MG_PAIN_LOOK_ATTRIBUTE, nil)
		state.body:SetAttribute(GameConstants.MG_PAIN_END_AT_ATTRIBUTE, nil)
		endPowerFx(state.body)
		if applyCooldown then
			finishAbility(state.body, "telepathic_pain", GameConstants.MG_PAIN_COOLDOWN)
		else
			AbilityCooldownHelper.setActive(state.body, "telepathic_pain", false)
		end
		if astral and astral.body.Parent and astral.body:GetAttribute(GameConstants.MG_ASTRAL_BODY_ATTRIBUTE) == true then
			astral.bodyAnimTrack = startAstralBodyAnim(astral.body)
		end
	end
end

local function startTelepathicPain(player: Player, target: Model?, direction: Vector3?, aimPoint: Vector3?, lockOn: boolean?)
	local astral = astralByPlayer[player]
	local body = player.Character
	if not astral or not body or painByPlayer[player] or astral.outbursting or astral.returning then
		return
	end
	if not canUse(body, "telepathic_pain", 0) then
		return
	end
	local victim = resolveSingleTkTarget(
		body,
		astral.root,
		target,
		direction,
		aimPoint,
		GameConstants.MG_PAIN_RANGE,
		lockOn
	)
	if not victim then
		return
	end
	if CombatHelper.isShielded(victim) then
		return
	end
	-- No upfront flat cost - updateTelepathicPain already drains
	-- MG_PAIN_ENERGY_PER_SEC continuously while held; spending MG_PAIN_ENERGY
	-- here too double-charged the same cast. Still needs some energy to start.
	local startEnergy = body:GetAttribute(GameConstants.ENERGY_ATTRIBUTE)
	if type(startEnergy) ~= "number" or startEnergy <= 0 then
		return
	end
	AbilityCooldownHelper.setActive(body, "telepathic_pain", true)
	body:SetAttribute(
		GameConstants.MG_PAIN_END_AT_ATTRIBUTE,
		AbilityCooldownHelper.getNow() + GameConstants.MG_PAIN_MAX_DURATION
	)
	beginPowerFx(body)
	stopAstralBodyAnim(astral)
	local animTrack = playJeanAnim(body, GameConstants.MG_TELEKINESIS_ANIM, true)
	if astral.astral.Parent then
		astral.bodyAnimTrack = playJeanAnim(astral.astral, GameConstants.MG_TELEKINESIS_ANIM, true)
	end
	local victimAnimTrack = playJeanAnim(victim, GameConstants.MG_PAIN_TARGET_ANIM, true)
	local victimHum = CombatHelper.getHumanoid(victim)
	local victimWalk = victimHum and victimHum.WalkSpeed or GameConstants.DEFAULT_WALK_SPEED
	local victimJumpPower: number? = nil
	local victimJumpHeight: number? = nil
	local victimAutoRotate = true
	if victimHum then
		victimAutoRotate = victimHum.AutoRotate
		if victimHum.UseJumpPower then
			victimJumpPower = victimHum.JumpPower
		else
			victimJumpHeight = victimHum.JumpHeight
		end
		victimHum.WalkSpeed = GameConstants.MG_PAIN_VICTIM_WALK_SPEED
		victimHum.JumpPower = 0
		victimHum.JumpHeight = 0
		pcall(function()
			victimHum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		end)
		-- Without this, SprintService's per-frame loop (which only skips its
		-- own WalkSpeed reset when this attribute is set) stomps the slow
		-- back to default WalkSpeed on the very next frame.
		victim:SetAttribute(GameConstants.MOVEMENT_SLOWED_ATTRIBUTE, true)
	end
	victim:SetAttribute(
		GameConstants.POWERS_DISABLED_UNTIL,
		AbilityCooldownHelper.getNow() + GameConstants.MG_PAIN_MAX_DURATION
	)
	fireCameraShake(player, 0.42, 0.35, 0.28, 0.5)
	local painTint = jeanScreenTint(body)
	ScreenFeelHelper.setTint(victim, painTint)
	ScreenFeelHelper.setShakeHold(victim, true)
	ScreenFeelHelper.pulseCharacter(victim, {
		intensity = 0.58,
		duration = 0.28,
		fovScale = 1.25,
		vignetteScale = 0.55,
		tint = painTint,
		tintDuration = 0.35,
	})
	local head = getHead(victim)
	local fx: Instance? = nil
	local template = VfxHelper.getMarvelGirlAsset("TelepathicPain", "PainAttachment")
	if template and head then
		fx = template:Clone()
		fx.Name = "MgPainAttachment"
		fx.Parent = head
		VfxHelper.setParticlesEnabled(fx, true)
		VfxHelper.emitAllParticles(fx, 8)
		styleJeanFx(fx, nil, body)
	end
	painByPlayer[player] = {
		body = body,
		victim = victim,
		fx = fx,
		sound = nil,
		tickAcc = 0,
		animTrack = animTrack,
		victimAnimTrack = victimAnimTrack,
		startedAt = AbilityCooldownHelper.getNow(),
		victimWalk = victimWalk,
		victimJumpPower = victimJumpPower,
		victimJumpHeight = victimJumpHeight,
		victimAutoRotate = victimAutoRotate,
	}
	local vRoot = getRoot(victim)
	if vRoot then
		body:SetAttribute(GameConstants.MG_PAIN_LOOK_ATTRIBUTE, vRoot.Position)
		astral.astral:SetAttribute(GameConstants.MG_PAIN_LOOK_ATTRIBUTE, vRoot.Position)
	end
end

local function updateTelepathicPain(player: Player, dt: number)
	local state = painByPlayer[player]
	if not state then
		return
	end
	local astral = astralByPlayer[player]
	if not astral or astral.returning or not state.body.Parent or not state.victim.Parent then
		stopTelepathicPain(player, true)
		return
	end
	-- Hold/release (Q_up) as before, but it also ends by itself after MG_PAIN_MAX_DURATION.
	if AbilityCooldownHelper.getNow() - state.startedAt >= GameConstants.MG_PAIN_MAX_DURATION then
		stopTelepathicPain(player, true)
		return
	end
	local vRoot = getRoot(state.victim)
	local vHum = CombatHelper.getHumanoid(state.victim)
	if not vRoot or not vHum or vHum.Health <= 0 then
		stopTelepathicPain(player, true)
		return
	end
	if (vRoot.Position - astral.root.Position).Magnitude > GameConstants.MG_PAIN_RANGE then
		stopTelepathicPain(player, true)
		return
	end
	state.body:SetAttribute(GameConstants.MG_PAIN_LOOK_ATTRIBUTE, vRoot.Position)
	astral.astral:SetAttribute(GameConstants.MG_PAIN_LOOK_ATTRIBUTE, vRoot.Position)
	if not CharacterService.spendEnergy(state.body, GameConstants.MG_PAIN_ENERGY_PER_SEC * dt) then
		stopTelepathicPain(player, true)
		return
	end
	state.tickAcc += dt
	if state.tickAcc >= GameConstants.MG_PAIN_TICK then
		local slice = state.tickAcc
		state.tickAcc = 0
		CombatHelper.dealDamage(
			state.body,
			state.victim,
			GameConstants.MG_PAIN_DAMAGE_PER_SEC * slice * (GameConstants.MG_PAIN_RAMP_START + (1 - GameConstants.MG_PAIN_RAMP_START) * 2 * math.clamp((AbilityCooldownHelper.getNow() - state.startedAt) / GameConstants.MG_PAIN_MAX_DURATION, 0, 1)),
			vRoot.Position,
			"dot"
		)
	end
end

----------------------------------------------------------------
-- Phoenix's Telepathic Pain: same mechanic as classic's astral-only pain,
-- but usable directly (no astral required) and doesn't fully root her - she
-- can still move, just slowly, matching every other channeled ability's
-- "some real cost/downside" while active.
----------------------------------------------------------------

do

function Phoenix.painLock(state: PhoenixPainState, victim: Model, walkSpeed: number)
	local vHum = CombatHelper.getHumanoid(victim)
	if not vHum then
		return
	end
	if not state.saved[victim] then
		state.saved[victim] = {
			lock = require(script.Parent.AbilityLocks).acquire(victim, "phoenix_mind_pain", {
				walk = math.clamp(walkSpeed / math.max(vHum.WalkSpeed, 1), 0, 1),
				jump = true,
			}),
		}
		-- Without this, SprintService's per-frame loop (which only skips its own WalkSpeed reset when this
		-- attribute is set) stomps the slow back to default WalkSpeed on the very next frame.
		victim:SetAttribute(GameConstants.MOVEMENT_SLOWED_ATTRIBUTE, true)
		local painTint = jeanScreenTint(state.body)
		ScreenFeelHelper.setTint(victim, painTint)
		ScreenFeelHelper.setShakeHold(victim, true)
		ScreenFeelHelper.pulseCharacter(victim, {
			intensity = 0.58,
			duration = 0.28,
			fovScale = 1.25,
			vignetteScale = 0.55,
			tint = painTint,
			tintDuration = 0.35,
		})
		-- Same per-victim presentation for both forms: the target's pain animation + the pain effect on its head.
		state.victimTracks[victim] = playJeanAnim(victim, GameConstants.MG_PAIN_TARGET_ANIM, true)
		local head = getHead(victim)
		local template: Instance? = VfxHelper.getMarvelGirlAsset("TelepathicPain", "PainAttachment")
		if state.dark then
			-- Dark Phoenix's targets get her own authored effect (kept in its own colours, no jeanAccent restyle).
			local assets = ReplicatedStorage:FindFirstChild("Assets")
			local jean = assets and assets:FindFirstChild("JeanGrey")
			local force = jean and jean:FindFirstChild("JeanGreyThePhoenixForce")
			template = force and force:FindFirstChild("DarkPhoenixTelepathicPain") or template
		end
		if template and head then
			local vfx = template:Clone()
			vfx.Name = "MgPainAttachment"
			vfx.Parent = head
			VfxHelper.setParticlesEnabled(vfx, true)
			VfxHelper.emitAllParticles(vfx, 8)
			if not state.dark then
				styleJeanFx(vfx, nil, state.body)
			end
			state.victimFxs[victim] = vfx
		end
	end
	vHum.WalkSpeed = walkSpeed
	vHum.UseJumpPower = true
	vHum.JumpPower = 0
	vHum:Move(Vector3.zero, false)
end

function Phoenix.painRelease(state: PhoenixPainState, victim: Model)
	local saved = state.saved[victim]
	state.saved[victim] = nil
	state.affected[victim] = nil
	local track = state.victimTracks[victim]
	state.victimTracks[victim] = nil
	if track then
		track:Stop(0.2)
	end
	local vfx = state.victimFxs[victim]
	state.victimFxs[victim] = nil
	if vfx and vfx.Parent then
		VfxHelper.smoothDisableParticles(vfx, 0.22)
		task.delay(1.5, function()
			if vfx.Parent then
				vfx:Destroy()
			end
		end)
	end
	if not victim.Parent then
		return
	end
	victim:SetAttribute(GameConstants.MOVEMENT_SLOWED_ATTRIBUTE, nil)
	ScreenFeelHelper.setShakeHold(victim, false)
	ScreenFeelHelper.setTint(victim, nil)
	if saved then
		require(script.Parent.AbilityLocks).release(saved.lock)
	end
end

function Phoenix.stopPain(player: Player, applyCooldown: boolean)
	local state = phoenixPainByPlayer[player]
	if not state then
		return
	end
	phoenixPainByPlayer[player] = nil
	if state.animTrack then
		state.animTrack:Stop(0.2)
	end
	for victim in state.saved do
		Phoenix.painRelease(state, victim)
	end
	for victim in state.affected do
		Phoenix.painRelease(state, victim)
	end
	local painFxs: { Instance } = { table.unpack(state.fxExtra or {}) }
	if state.fx then
		table.insert(painFxs, state.fx)
	end
	for _, fx in painFxs do
		if fx.Parent then
			VfxHelper.smoothDisableParticles(fx, 0.22)
			task.delay(1.5, function()
				if fx.Parent then
					fx:Destroy()
				end
			end)
		end
	end
	if state.body.Parent then
		if state.session then
			state.session:finish("stop")
		end
		state.body:SetAttribute(GameConstants.MOVEMENT_SLOWED_ATTRIBUTE, nil)
		endPowerFx(state.body)
		if applyCooldown then
			finishAbility(state.body, "phoenix_mind_pain", GameConstants.MG_PHOENIX_PAIN_COOLDOWN)
		else
			AbilityCooldownHelper.setActive(state.body, "phoenix_mind_pain", false)
		end
	end
end

function Phoenix.startPain(player: Player, target: Model?, direction: Vector3?, aimPoint: Vector3?, lockOn: boolean?)
	local body = player.Character
	if not body or phoenixPainByPlayer[player] then
		return
	end
	if not canUse(body, "phoenix_mind_pain", 0) then
		return
	end
	local root = getRoot(body)
	if not root then
		return
	end
	-- No upfront flat cost - updatePain already drains
	-- MG_PHOENIX_PAIN_ENERGY_PER_SEC continuously while channeling; spending
	-- MG_PHOENIX_PAIN_ENERGY here too double-charged the same cast. Still
	-- needs some energy to start.
	local startEnergy = body:GetAttribute(GameConstants.ENERGY_ATTRIBUTE)
	if type(startEnergy) ~= "number" or startEnergy <= 0 then
		return
	end
	-- Same ability for both forms - base Phoenix locks onto ONE distant target under her cursor, Dark Phoenix
	-- (after her resurrection) hits everyone around her instead, no cursor needed.
	local dark = body:GetAttribute("MgDarkPhoenix") == true
	local victim: Model? = nil
	if not dark then
		victim = resolveSingleTkTarget(body, root, target, direction, aimPoint, GameConstants.MG_PHOENIX_PAIN_RANGE, lockOn)
		local vHum = if victim then CombatHelper.getHumanoid(victim) else nil
		if not victim or not vHum or vHum.Health <= 0 or CombatHelper.isShielded(victim) then
			return
		end
	end
	beginPowerFx(body)
	local hum = CombatHelper.getHumanoid(body)
	local painSession: any = nil
	if hum then
		painSession = require(script.Parent.AbilitySession).begin(body, "phoenix_mind_pain", 60)
		if dark then
			-- Dark Phoenix is rooted in place for the whole scream (the lock also sets MOVEMENT_LOCK, which stops
			-- SprintService's per-frame WalkSpeed reset from undoing the zero).
			painSession:lock({ walk = 0 })
		else
			painSession:lock({ walk = math.clamp(GameConstants.MG_PHOENIX_PAIN_CASTER_WALK_SPEED / math.max(hum.WalkSpeed, 1), 0, 1) })
			-- Lets the slow stick: SprintService resets WalkSpeed every frame unless this is set.
			body:SetAttribute(GameConstants.MOVEMENT_SLOWED_ATTRIBUTE, true)
		end
	end
	fireCameraShake(player, 0.42, 0.35, 0.28, 0.5)
	local state: PhoenixPainState = {
		body = body,
		root = root,
		fx = nil,
		fxExtra = nil,
		tickAcc = 0,
		animTrack = playJeanAnim(body, GameConstants.MG_TELEKINESIS_ANIM, true),
		startedAt = AbilityCooldownHelper.getNow(),
		session = painSession,
		dark = dark,
		single = victim,
		victimTracks = {},
		victimFxs = {},
		affected = {},
		saved = {},
	}
	phoenixPainByPlayer[player] = state
	AbilityCooldownHelper.setActive(body, "phoenix_mind_pain", true)
	if victim then
		state.affected[victim] = true
		Phoenix.painLock(state, victim, GameConstants.MG_PAIN_VICTIM_WALK_SPEED)
		return
	end
	-- Dark Phoenix: the area FX plants on HER OWN head, a beat after the scream starts.
	task.delay(GameConstants.MG_PHOENIX_PAIN_FX_DELAY, function()
		if phoenixPainByPlayer[player] ~= state or state.fx ~= nil then
			return
		end
		local head = getHead(body)
		-- Her own pain effect: DarkPhoenixTelepathicPainTorso on her upper torso + ...Head on her head, both
		-- kept running (authored colours) until the scream ends.
		local painFolder = ReplicatedStorage:FindFirstChild("Assets")
		painFolder = painFolder and painFolder:FindFirstChild("JeanGrey")
		painFolder = painFolder and painFolder:FindFirstChild("JeanGreyThePhoenixForce")
		painFolder = painFolder and painFolder:FindFirstChild("TelepathicPain")
		local torsoPart = (body:FindFirstChild("UpperTorso") or body:FindFirstChild("Torso")) :: BasePart?
		local planted: { Instance } = {}
		for _, spec in { { "DarkPhoenixTelepathicPainTorso", torsoPart }, { "DarkPhoenixTelepathicPainHead", head } } do
			local tmpl = painFolder and painFolder:FindFirstChild(spec[1] :: string)
			local host = spec[2] :: BasePart?
			if tmpl and host then
				local att = tmpl:Clone()
				att.Parent = host
				VfxHelper.setParticlesEnabled(att, true)
				table.insert(planted, att)
			end
		end
		if #planted > 0 then
			state.fx = planted[1]
			state.fxExtra = { table.unpack(planted, 2) }
			return
		end
		local template = getPhoenixAsset(body, "TelepathicPain", "AreaTelepathicPain")
		if template and template:IsA("BasePart") and head then
			local fx = template:Clone() :: BasePart
			fx.Name = "MgPhoenixAreaPainAttachment"
			-- The template is a Part (invisible carrier for its Attachments'
			-- particles), not an Attachment itself - just reparenting it under
			-- Head leaves it sitting at its ReplicatedStorage position instead
			-- of on her, since reparenting a BasePart doesn't move or weld it.
			-- Snap it to Head's CFrame and weld it there.
			fx.Anchored = false
			fx.CanCollide = false
			fx.CanQuery = false
			fx.CFrame = head.CFrame
			fx.Parent = head
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = head
			weld.Part1 = fx
			weld.Parent = fx
			VfxHelper.setParticlesEnabled(fx, true)
			VfxHelper.emitAllParticles(fx, 12)
			styleJeanFx(fx, nil, body)
			state.fx = fx
			-- Stays up for the whole scream; stopPain fades it out when the pain ends.
		else
			warn("[MarvelGirl] Missing Assets.JeanGrey.JeanGreyThePhoenixForce.TelepathicPain.AreaTelepathicPain")
		end
	end)
end

function Phoenix.updatePain(player: Player, dt: number)
	local state = phoenixPainByPlayer[player]
	if not state then
		return
	end
	if not state.body.Parent or not state.root.Parent then
		Phoenix.stopPain(player, true)
		return
	end
	if not CharacterService.spendEnergy(state.body, GameConstants.MG_PHOENIX_PAIN_ENERGY_PER_SEC * dt) then
		Phoenix.stopPain(player, true)
		return
	end
	if AbilityCooldownHelper.getNow() - state.startedAt >= GameConstants.MG_PHOENIX_PAIN_DURATION then
		Phoenix.stopPain(player, true)
		return
	end
	local single = state.single
	if single then
		local sRoot = getRoot(single)
		local sHum = CombatHelper.getHumanoid(single)
		if not sRoot or not sHum or sHum.Health <= 0 or not single.Parent then
			Phoenix.stopPain(player, true)
			return
		end
		if (sRoot.Position - state.root.Position).Magnitude > GameConstants.MG_PHOENIX_PAIN_RANGE then
			Phoenix.stopPain(player, true)
			return
		end
	end
	-- Re-asserted every frame, not only on the damage tick, so nothing can speed a victim back up.
	for victim in state.affected do
		Phoenix.painLock(state, victim, GameConstants.MG_PAIN_VICTIM_WALK_SPEED)
	end
	state.tickAcc += dt
	if state.tickAcc < GameConstants.MG_PAIN_TICK then
		return
	end
	local slice = state.tickAcc
	state.tickAcc = 0

	if single then
		local sRoot = getRoot(single)
		if sRoot then
			CombatHelper.dealDamage(state.body, single, GameConstants.MG_PHOENIX_PAIN_DAMAGE_PER_SEC * slice, sRoot.Position, "dot")
		end
		return
	end

	-- Dark Phoenix: everyone inside the area, re-evaluated each tick.
	local stillInRange: { [Model]: boolean } = {}
	for _, victim in CombatHelper.overlapCharacters(state.root.Position, GameConstants.MG_PHOENIX_PAIN_AOE_RADIUS, state.body) do
		if CombatHelper.isShielded(victim) then
			continue
		end
		local vHum = CombatHelper.getHumanoid(victim)
		local vRoot = getRoot(victim)
		if not vHum or vHum.Health <= 0 or not vRoot then
			continue
		end
		stillInRange[victim] = true
		state.affected[victim] = true
		Phoenix.painLock(state, victim, GameConstants.MG_PAIN_VICTIM_WALK_SPEED)
		CombatHelper.dealDamage(state.body, victim, GameConstants.MG_PHOENIX_PAIN_DAMAGE_PER_SEC * slice, vRoot.Position, "dot")
	end
	-- Anyone who left the area this tick is freed immediately - it's a live area, not a lingering debuff
	-- once you step out of it.
	for victim in state.affected do
		if not stillInRange[victim] then
			Phoenix.painRelease(state, victim)
		end
	end
end

end -- Phoenix's Telepathic Pain


----------------------------------------------------------------
-- Phoenix's Cosmic Aura Burn: a burning aura around her that follows her
-- (welded ground-level visual), damaging and slowing anyone within
-- MG_COSMIC_AURA_RADIUS studs of her CURRENT position for its duration.
----------------------------------------------------------------

type PhoenixAuraState = {
	character: Model,
	visual: Instance?,
	slowed: { [Model]: any }, -- AbilityLocks tokens, one per slowed victim
	burning: { [Model]: boolean },
	session: any?, -- AbilitySession rooting the caster
	insta: boolean,
	rootAtt: Attachment?,
	rootAlign: AlignPosition?,
	animTrack: AnimationTrack?,
	pendingInsta: { [Model]: boolean },
	repulsed: boolean?,
	repulseAt: number?,
}

local phoenixAuraByPlayer: { [Player]: PhoenixAuraState } = {}
local phoenixAuraToken: { [Player]: number } = {}

-- Ragdoll starting mid-burn used to still call Phoenix.stopAuraBurn (via the
-- generic RagdollService.onAbilityInterrupt -> cancelAll chain), but that
-- only fires AFTER RagdollService.apply already broke her joints and freed
-- her limbs - the rigid rootAlign below was still gripping the root that
-- whole gap, which is what kept flinging her regardless of how carefully
-- stopAuraBurn cleaned up afterward. A GetAttributeChangedSignal watcher
-- doesn't close this either - Roblox's default Deferred signal behavior
-- means it also fires after RagdollService.apply's synchronous work is
-- already done, not before. RagdollService.onBeforeApply is the one hook
-- that runs synchronously BEFORE the ragdoll is built, so it's the only
-- place this can actually be fixed.
RagdollService.onBeforeApply(function(character: Model)
	local player = Players:GetPlayerFromCharacter(character)
	local state = player and phoenixAuraByPlayer[player]
	if not state then
		return
	end
	-- Stop her aura-cast animation here too, synchronously before ragdoll
	-- breaks the rig - it used to only get stopped in stopAuraBurn, which
	-- runs AFTER ragdoll already built (the deferred ability-interrupt
	-- chain), same ordering gap the rootAlign teardown below was written to
	-- close. A still-playing AnimationTrack fighting newly-broken/loose
	-- joints is what read as "flinching like crazy" even with rootAlign
	-- already handled.
	if state.animTrack then
		state.animTrack:Stop(0)
		state.animTrack:Destroy()
		state.animTrack = nil
	end
	if not state.rootAlign then
		return
	end
	local rootAlign = state.rootAlign
	local rootAtt = state.rootAtt
	state.rootAlign = nil
	state.rootAtt = nil
	-- Used to briefly disable CanCollide instead of anchoring - but that left
	-- every part free-falling (still unanchored, gravity still live) with
	-- NO floor collision for up to 0.15s. That's easily enough time to sink
	-- partway into the ground/a wall, and the instant CanCollide flipped
	-- back on, Roblox's solver depenetrated her out of solid geometry in one
	-- violent step - a real fling, just from a different cause than the
	-- rigid-align-vs-ragdoll conflict this hook was originally written to
	-- fix. Anchoring instead means she genuinely does not move AT ALL during
	-- the brief handoff, so there's nothing for the solver to eject her from
	-- once released.
	--
	-- This used to be the ONLY protection window, with a second, separate
	-- one duplicated in Phoenix.stopAuraBurn's own ragdoll branch (destroy
	-- align -> zero velocity -> noclip -> re-collide 0.15s later) - that
	-- second copy runs deferred (via the ability-interrupt task.spawn chain,
	-- not synchronously like this hook), so its own 0.15s noclip timer could
	-- start noticeably later than this hook's anchor timer and end up
	-- re-enabling collision WHILE she was still sinking, from a totally
	-- unrelated race between the two windows - "flings VERY far" despite
	-- both windows individually looking safe. Owning the WHOLE handoff here
	-- (anchor, then a staggered noclip-only tail before collision returns)
	-- instead of splitting it across two independently-timed places removes
	-- that race entirely.
	local anchoredParts: { BasePart } = {}
	local collidingParts: { BasePart } = {}
	for _, desc in character:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.AssemblyLinearVelocity = Vector3.zero
			desc.AssemblyAngularVelocity = Vector3.zero
			if not desc.Anchored then
				desc.Anchored = true
				table.insert(anchoredParts, desc)
			end
			if desc.CanCollide then
				desc.CanCollide = false
				table.insert(collidingParts, desc)
			end
		end
	end
	task.delay(0.15, function()
		for _, part in anchoredParts do
			if part.Parent then
				part.Anchored = false
			end
		end
		-- Collision stays off a bit longer than the anchor itself - unanchored
		-- but still non-colliding gives the ragdoll a moment to fall/settle
		-- under gravity before the solver is allowed to react to overlaps,
		-- instead of anchored-solid snapping straight to fully-physical-and-
		-- colliding in the same instant.
		task.delay(0.15, function()
			for _, part in collidingParts do
				if part.Parent then
					part.CanCollide = true
				end
			end
		end)
	end)
	if rootAlign and rootAlign.Parent then
		rootAlign:Destroy()
	end
	if rootAtt and rootAtt.Parent then
		rootAtt:Destroy()
	end
end)

do

local COSMIC_AURA_INSTA_HP_RATIO = 0.1

local function auraBodyParts(character: Model): { BasePart }
	local parts: { BasePart } = {}
	for _, desc in character:GetDescendants() do
		if desc:IsA("BasePart") then
			table.insert(parts, desc)
		end
	end
	table.sort(parts, function(a, b)
		return a.Position.Y < b.Position.Y
	end)
	return parts
end

-- Anyone caught under COSMIC_AURA_INSTA_HP_RATIO HP while the aura is up
-- gets executed outright instead of just ticked: feet-to-head transparency
-- dissolve (like Flame Combo's old insta used to be) with PhoenixInsta welded
-- to their HRP, then every part anchored in place once the fade is done.
local function playAuraInsta(victim: Model, caster: Model)
	local vRoot = getRoot(victim)
	local vHum = CombatHelper.getHumanoid(victim)
	if vHum and vHum.Health > 0 then
		CombatHelper.dealDamage(caster, victim, vHum.Health + 1, if vRoot then vRoot.Position else victim:GetPivot().Position, "execute")
	end
	ScreenFeelHelper.pulseCharacter(victim, {
		intensity = 0.7,
		duration = 0.5,
		fovScale = 0.4,
		vignetteScale = 0.6,
		tint = GameConstants.MG_PSI_COLOR_PHOENIX,
		tintDuration = 0.6,
	})
	if vRoot then
		local template = getPhoenixAsset(caster, "PhoenixInsta")
		if template and template:IsA("BasePart") then
			local fx = template:Clone()
			fx.Name = "PhoenixCosmicAuraInsta"
			fx.Anchored = false
			fx.CanCollide = false
			fx.CanQuery = false
			fx.CanTouch = false
			fx.Massless = true
			fx.CFrame = vRoot.CFrame
			fx.Parent = victim
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = vRoot
			weld.Part1 = fx
			weld.Parent = fx
			VfxHelper.emitByCount(fx)
			task.delay(2, function()
				if fx.Parent then
					VfxHelper.retireFxSmooth(fx, 0.4, 0.6)
				end
			end)
		else
			warn("[MarvelGirl] Missing Phoenix insta asset (Assets.JeanGrey.JeanGreyThePhoenixForce.PhoenixInsta)")
		end
	end
	local parts = auraBodyParts(victim)
	-- Much quicker per request (was 0.05s/part stagger + 0.18s tween + 0.18s final wait). Already
	-- anchored the whole time (anchorPendingAuraInsta ran when she first crossed the threshold), so
	-- this is only re-asserting it, not the first time she can't move.
	task.spawn(function()
		for _, part in parts do
			if part.Parent then
				TweenService:Create(part, TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Transparency = 1,
				}):Play()
			end
			task.wait(0.015)
		end
		task.wait(0.07)
		for _, part in parts do
			if part.Parent then
				part.Anchored = true
			end
		end
	end)
end

-- The moment a victim crosses the insta threshold, freeze them in place
-- instead of executing them immediately - playAuraInsta itself runs for
-- everyone marked pending, together, once the burn actually ends (see
-- Phoenix.stopAuraBurn below).
local function anchorPendingAuraInsta(victim: Model)
	local vHum = CombatHelper.getHumanoid(victim)
	if vHum then
		vHum.WalkSpeed = 0
		vHum.JumpPower = 0
		vHum.PlatformStand = true
	end
	for _, part in auraBodyParts(victim) do
		part.Anchored = true
		part.AssemblyLinearVelocity = Vector3.zero
		part.AssemblyAngularVelocity = Vector3.zero
	end
end

function Phoenix.repulse(state: PhoenixAuraState)
	if state.repulsed then
		return
	end
	state.repulsed = true
	state.repulseAt = os.clock()
	local character = state.character
	-- A beat of buildup before the disintegrate: plants PhoenixRepulseAttachment on her for
	-- MG_COSMIC_AURA_REPULSE_DELAY, then bursts everyone nearby away and ragdolls them briefly -
	-- runs whether or not anyone is actually pending an insta-kill this time.
	local repulseRoot = getRoot(character)
	if repulseRoot then
		local repulseTemplate = getPhoenixAsset(character, "PhoenixRepulseAttachment")
		if repulseTemplate then
			local repulseFx = repulseTemplate:Clone()
			repulseFx.Name = "PhoenixRepulseAttachment"
			if repulseFx:IsA("BasePart") then
				repulseFx.Anchored = false
				repulseFx.CanCollide = false
				repulseFx.CanQuery = false
				repulseFx.CanTouch = false
				repulseFx.Massless = true
				repulseFx.CFrame = repulseRoot.CFrame
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = repulseRoot
				weld.Part1 = repulseFx
				weld.Parent = repulseFx
			end
			repulseFx.Parent = character
			-- One-shot burst: emitters stay off, each emits its own EmitCount attribute.
			for _, em in repulseFx:GetDescendants() do
				if em:IsA("ParticleEmitter") then
					em.Enabled = false
					em:Emit(em:GetAttribute("EmitCount") or 1)
				end
			end
			local repulsePos = repulseRoot.Position
			task.delay(GameConstants.MG_COSMIC_AURA_REPULSE_DELAY, function()
				if repulseFx.Parent then
					repulseFx:Destroy()
				end
				if not character.Parent then
					return
				end
				for _, victim in CombatHelper.overlapCharacters(repulsePos, GameConstants.MG_COSMIC_AURA_RADIUS, character) do
					local vRoot = getRoot(victim)
					-- Those about to be disintegrated stay anchored where they are; only everyone else is blown away.
					if not vRoot or state.pendingInsta[victim] then
						continue
					end
					RagdollService.applyTimed(victim, GameConstants.MG_COSMIC_AURA_REPULSE_RAGDOLL)
					local away = vRoot.Position - repulsePos
					PushHelper.applyToCharacter(victim, if away.Magnitude > 0.05 then away.Unit else Vector3.new(0, 0, -1), {
						speed = GameConstants.MG_COSMIC_AURA_REPULSE_PUSH_SPEED,
						upBoost = GameConstants.MG_COSMIC_AURA_REPULSE_PUSH_UP,
						noRagdoll = true,
					})
				end
			end)
		else
			warn("[MarvelGirl] Missing Assets.JeanGrey.JeanGreyThePhoenixForce.PhoenixRepulseAttachment")
		end
	end
end

function Phoenix.stopAuraBurn(player: Player, applyCooldown: boolean)
	local state = phoenixAuraByPlayer[player]
	if not state then
		return
	end
	phoenixAuraByPlayer[player] = nil
	phoenixAuraToken[player] = (phoenixAuraToken[player] or 0) + 1
	if state.rootAlign and state.rootAlign.Parent then
		state.rootAlign:Destroy()
	end
	if state.rootAtt and state.rootAtt.Parent then
		state.rootAtt:Destroy()
	end
	-- The rigid AlignPosition above was holding her position outright for
	-- the whole burn - destroying it handed control straight back to normal
	-- physics, which could carry over whatever velocity had built up against
	-- it (e.g. a hit landing right as the burn ends). Only the non-ragdoll
	-- (natural end) case is handled here now - the ragdoll case used to have
	-- its OWN separate anchor/noclip window right here, running deferred
	-- (via the ability-interrupt task.spawn chain) alongside
	-- RagdollService.onBeforeApply's own SYNCHRONOUS window, which starts
	-- immediately when the ragdoll is actually built. Two independently-timed
	-- windows racing each other - one could re-enable collision while the
	-- other's freeze was still technically in effect - was itself the
	-- "flings VERY far" bug, not a gap in either window alone. onBeforeApply
	-- now owns the whole ragdoll handoff by itself; duplicating it here only
	-- reintroduces that race.
	if state.character.Parent and state.character:GetAttribute(GameConstants.RAGDOLLED_ATTRIBUTE) ~= true then
		local anchorRoot = getRoot(state.character)
		if anchorRoot then
			for _, desc in state.character:GetDescendants() do
				if desc:IsA("BasePart") then
					desc.AssemblyLinearVelocity = Vector3.zero
					desc.AssemblyAngularVelocity = Vector3.zero
				end
			end
			anchorRoot.Anchored = true
			task.delay(0.1, function()
				if anchorRoot.Parent then
					anchorRoot.Anchored = false
				end
			end)
		end
	end
	for victim, slowLock in pairs(state.slowed) do
		require(script.Parent.AbilityLocks).release(slowLock)
		if victim.Parent then
			victim:SetAttribute(GameConstants.MOVEMENT_SLOWED_ATTRIBUTE, nil)
		end
	end
	for victim in pairs(state.burning) do
		Phoenix.endBurnVfx(victim)
	end
	if state.visual and state.visual.Parent then
		-- Ground VFX lingers a little past the burn's end before fading out.
		local lingering = state.visual
		task.delay(GameConstants.MG_COSMIC_AURA_VFX_LINGER, function()
			if lingering.Parent then
				VfxHelper.retireFxSmooth(lingering, 0.3, 0.8)
			end
		end)
	end
	local character = state.character

	Phoenix.repulse(state)

	-- Everyone who crossed the insta threshold during the burn was only
	-- anchored, not killed yet - execute all of them together right now,
	-- at the moment the burn actually ends (natural timeout or early stop).
	-- The insta-kill damage lands with the repulse push, REPULSE_DELAY after the shockwave particles burst.
	local instaWait = math.max(0, (state.repulseAt or os.clock()) + GameConstants.MG_COSMIC_AURA_REPULSE_DELAY - os.clock())
	for victim in pairs(state.pendingInsta) do
		task.delay(instaWait, function()
			if victim.Parent then
				playAuraInsta(victim, character)
			end
		end)
	end
	if state.animTrack then
		state.animTrack:Stop(0.15)
		state.animTrack:Destroy()
	end
	if character.Parent then
		local hum = CombatHelper.getHumanoid(character)
		if state.session then
			state.session:finish("stop")
		end
		if hum then
			pcall(function()
				hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
			end)
		end
		character:SetAttribute(GameConstants.MOVEMENT_SLOWED_ATTRIBUTE, nil)
		character:SetAttribute(GameConstants.BUSY_ATTRIBUTE, nil)
		endPowerFx(character)
		if applyCooldown and AbilityCooldownHelper.isActive(character, "cosmic_aura_burn") then
			local cooldown = if state.insta then GameConstants.MG_COSMIC_AURA_INSTA_COOLDOWN else GameConstants.MG_COSMIC_AURA_COOLDOWN
			finishAbility(character, "cosmic_aura_burn", cooldown)
		else
			AbilityCooldownHelper.setActive(character, "cosmic_aura_burn", false)
		end
	end
end

-- Passive Phoenix-only effect on whatever Telekinesis is currently gripping:
-- reuses the same per-victim burn VFX as Cosmic Aura Burn/Wrath, plus 1
-- damage/sec while held. Separate from Cosmic Aura Burn itself (that ability
-- is untouched) - this just piggybacks its flame visual onto TK's grip.
do
	local tkBurnState: { [Player]: { accum: { [Model]: number }, burning: { [Model]: boolean } } } = {}

	local function stopAllTkBurn(player: Player)
		local state = tkBurnState[player]
		if not state then
			return
		end
		for victim in pairs(state.burning) do
			Phoenix.endBurnVfx(victim)
		end
		tkBurnState[player] = nil
	end

	function Phoenix.updateTkBurn(dtClamped: number)
		for _, player in Players:GetPlayers() do
			local character = player.Character
			if not character or GameConstants.PHOENIX_LOOK_IDS[MarvelGirlService.lookOf(character)] ~= true then
				stopAllTkBurn(player)
				continue
			end
			local heldModels = TelekinesisService.getHeldModels(player)
			if #heldModels == 0 then
				stopAllTkBurn(player)
				continue
			end
			local state = tkBurnState[player]
			if not state then
				state = { accum = {}, burning = {} }
				tkBurnState[player] = state
			end
			local heldSet: { [Model]: boolean } = {}
			for _, victim in heldModels do
				heldSet[victim] = true
				if not state.burning[victim] then
					state.burning[victim] = true
					state.accum[victim] = 0
					Phoenix.beginBurnVfx(victim)
				end
				local accum = (state.accum[victim] or 0) + dtClamped
				if accum >= 1 then
					accum -= 1
					local vHum = CombatHelper.getHumanoid(victim)
					local vRoot = getRoot(victim)
					if vHum and vHum.Health > 0 and vRoot then
						CombatHelper.dealDamage(character, victim, 1, vRoot.Position, "dot")
					end
				end
				state.accum[victim] = accum
			end
			for victim in pairs(state.burning) do
				if not heldSet[victim] then
					state.burning[victim] = nil
					state.accum[victim] = nil
					Phoenix.endBurnVfx(victim)
				end
			end
		end
	end
end

function Phoenix.startAuraBurn(player: Player)
	local character = player.Character
	if not character or phoenixAuraByPlayer[player] then
		return
	end
	local entry = CharacterRegistry.getAbilityById("jean_grey", "cosmic_aura_burn")
	if not entry or not canUse(character, entry.id, GameConstants.MG_COSMIC_AURA_ENERGY_PER_TICK) then
		return
	end
	local root = getRoot(character)
	if not root then
		return
	end
	AbilityCooldownHelper.setActive(character, entry.id, true)
	-- Rooted in place for the whole burn - blocks every other ability
	-- (canUse checks this) AND flight (HexFlightService.powersBlocked checks
	-- it too), not just movement.
	character:SetAttribute(GameConstants.BUSY_ATTRIBUTE, true)
	attachPowerFx(character)
	-- Timed ability now, not a hold - plays once instead of looping.
	local auraAnimTrack = playJeanAnim(character, GameConstants.MG_COSMIC_AURA_ANIM, false)
	fireCameraShake(player, 0.4, 0.35, 0.3, 0.45)

	-- Unable to jump, and moves slower - "smoother"/heavier feeling instead of
	-- a free-roam AoE - while the aura is up.
	local hum = CombatHelper.getHumanoid(character)
	local auraSession = require(script.Parent.AbilitySession).begin(character, "cosmic_aura_burn", 180)
	auraSession:lock({ walk = 0, jump = true })
	if hum then
		pcall(function()
			hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		end)
	end
	-- SprintService doesn't know about this lock on its own (no BUSY/shield/
	-- TK attribute is set here) - without this, holding shift sprung
	-- WalkSpeed back up every frame, fighting the intended full stop.
	character:SetAttribute(GameConstants.MOVEMENT_SLOWED_ATTRIBUTE, true)

	local visual: Instance? = nil
	local template = getPhoenixAsset(character, "CosmicAuraBurn")
	if template and template:IsA("BasePart") then
		visual = template:Clone()
		visual.Name = "PhoenixCosmicAuraBurn"
		visual.Anchored = false
		visual.CanCollide = false
		visual.CanQuery = false
		visual.CanTouch = false
		visual.Massless = true
		visual.CFrame = root.CFrame * CFrame.new(0, -(root.Size.Y / 2 + 2.5), 0)
		visual.Parent = character
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = visual
		weld.Parent = visual
	elseif not template then
		warn("[MarvelGirl] Missing Phoenix aura asset (Assets.JeanGrey.JeanGreyThePhoenixForce.CosmicAuraBurn)")
	end

	-- WalkSpeed/JumpPower alone only block her own input - they don't resist
	-- an external push. Taking a hit while otherwise-stationary (Humanoid
	-- can't self-correct with WalkSpeed 0) used to fling her across the map
	-- from a knock that would normally be barely noticeable - same class of
	-- bug Phoenix Wrath's float already avoids by owning her position
	-- outright instead of just disabling movement input.
	local rootAtt = Instance.new("Attachment")
	rootAtt.Name = "MgAuraBurnRootAtt"
	rootAtt.Parent = root
	local rootAlign = Instance.new("AlignPosition")
	rootAlign.Name = "MgAuraBurnRootAlign"
	rootAlign.Mode = Enum.PositionAlignmentMode.OneAttachment
	rootAlign.Attachment0 = rootAtt
	rootAlign.ApplyAtCenterOfMass = true
	-- Was a spring-force lock (RigidityEnabled=false, MaxForce/MaxVelocity
	-- capped) - strong enough to shrug off a light bump, but a real fling
	-- (Telekinesis, a strong push ability, etc.) sets velocity every frame
	-- for its own duration, which a capped-speed correction can never fully
	-- outrun in real time - she'd travel far before it caught up. Rigidity
	-- sets her position directly every physics step instead of applying a
	-- resistible force, so no external velocity write can move her at all
	-- while this is up (same fix pattern as Cyclops's leap tilt align).
	rootAlign.RigidityEnabled = true
	rootAlign.Responsiveness = 40
	rootAlign.MaxForce = 1e6
	rootAlign.MaxVelocity = 6
	rootAlign.Position = root.Position
	rootAlign.Parent = root

	local token = (phoenixAuraToken[player] or 0) + 1
	phoenixAuraToken[player] = token
	phoenixAuraByPlayer[player] = {
		character = character,
		visual = visual,
		slowed = {},
		burning = {},
		session = auraSession,
		insta = false,
		rootAtt = rootAtt,
		rootAlign = rootAlign,
		animTrack = auraAnimTrack,
		pendingInsta = {},
	}

	-- The repulse buildup starts REPULSE_LEAD before the burn ends (stopAuraBurn does it itself if the
	-- burn is cut short first). Token-gated like the tick loop below.
	task.delay(math.max(GameConstants.MG_COSMIC_AURA_MAX_HOLD - GameConstants.MG_COSMIC_AURA_REPULSE_LEAD, 0), function()
		local live = phoenixAuraByPlayer[player]
		if live and phoenixAuraToken[player] == token then
			Phoenix.repulse(live)
		end
	end)

	task.spawn(function()
		local elapsed = 0
		-- Not a hold ability - once started this loop always runs the full
		-- MG_COSMIC_AURA_MAX_HOLD duration (Z_up/re-tap no longer call
		-- Phoenix.stopAuraBurn early). The only way out early is the token
		-- check below going stale, which happens via the ragdoll/ability-
		-- interrupt hook (Phoenix.stopAuraBurn is still called from there).
		while elapsed < GameConstants.MG_COSMIC_AURA_MAX_HOLD do
			task.wait(GameConstants.MG_COSMIC_AURA_TICK)
			elapsed += GameConstants.MG_COSMIC_AURA_TICK
			local state = phoenixAuraByPlayer[player]
			if not state or phoenixAuraToken[player] ~= token or not character.Parent then
				return
			end
			-- Spend what's available, but running out of energy doesn't cut
			-- the burn short either - only being knocked out does.
			CharacterService.spendEnergy(character, GameConstants.MG_COSMIC_AURA_ENERGY_PER_TICK)
			local curRoot = getRoot(character)
			if not curRoot then
				break
			end
			local inRange: { [Model]: boolean } = {}
			for _, victim in CombatHelper.overlapCharacters(curRoot.Position, GameConstants.MG_COSMIC_AURA_RADIUS, character) do
				inRange[victim] = true
				-- The slow is (re)asserted every tick, before anything else can `continue` past it: a released
				-- token (another ability's releaseAll, a ragdoll) or a cleared MOVEMENT_SLOWED flag used to
				-- silently end it mid-burn while the victim stayed inside the aura.
				if not state.pendingInsta[victim] then
					local slowToken = state.slowed[victim]
					if slowToken and slowToken.released then
						slowToken = nil
						state.slowed[victim] = nil
					end
					if not slowToken and CombatHelper.getHumanoid(victim) then
						state.slowed[victim] = require(script.Parent.AbilityLocks).acquire(
							victim,
							"cosmic_aura_burn",
							{ walk = GameConstants.MG_COSMIC_AURA_SLOW_MULT }
						)
					end
					victim:SetAttribute(GameConstants.MOVEMENT_SLOWED_ATTRIBUTE, true)
				end
				-- Refreshed every tick so it naturally expires shortly after
				-- they leave the aura instead of needing separate cleanup.
				victim:SetAttribute(
					GameConstants.POWERS_DISABLED_UNTIL,
					AbilityCooldownHelper.getNow() + GameConstants.MG_COSMIC_AURA_TICK + 0.3
				)
				-- Shielded targets: skip the insta-kill (that's an HP-ratio
				-- check, meaningless against a shield) but the burn tick
				-- itself still lands - CombatHelper.dealDamage already
				-- drains shield HP instead of health when isShielded, so no
				-- separate shield branch is needed here.
				if CombatHelper.isShielded(victim) then
					CombatHelper.dealDamage(
						character,
						victim,
						GameConstants.MG_COSMIC_AURA_DAMAGE_PER_TICK,
						curRoot.Position,
						"dot"
					)
				elseif state.pendingInsta[victim] then
					-- Already anchored, awaiting execution once the burn
					-- actually ends (all pending victims die together then,
					-- not one-by-one as they individually cross the threshold).
					continue
				else
					local vHum = CombatHelper.getHumanoid(victim)
					if vHum and vHum.Health > 0 and vHum.Health <= vHum.MaxHealth * COSMIC_AURA_INSTA_HP_RATIO then
						state.insta = true
						state.pendingInsta[victim] = true
						anchorPendingAuraInsta(victim)
						continue
					end
					CombatHelper.dealDamage(
						character,
						victim,
						GameConstants.MG_COSMIC_AURA_DAMAGE_PER_TICK,
						curRoot.Position,
						"dot"
					)
					if not state.burning[victim] then
						state.burning[victim] = true
						Phoenix.beginBurnVfx(victim)
					end
				end
				end
				for victim, slowLock in pairs(state.slowed) do
				if not inRange[victim] and not state.pendingInsta[victim] then
					require(script.Parent.AbilityLocks).release(slowLock)
					if victim.Parent then
						victim:SetAttribute(GameConstants.MOVEMENT_SLOWED_ATTRIBUTE, nil)
					end
					state.slowed[victim] = nil
				end
			end
			for victim in pairs(state.burning) do
				if not inRange[victim] and not state.pendingInsta[victim] then
					state.burning[victim] = nil
					Phoenix.endBurnVfx(victim)
				end
			end
		end
		Phoenix.stopAuraBurn(player, true)
	end)
end

end -- Phoenix's Cosmic Aura Burn

----------------------------------------------------------------
-- Phoenix Wrath: floats her 50 studs straight up over 1s, then holds her
-- there for 5s pushing and burning everyone within 100 studs. Uses the same
-- Attachment+AlignPosition float technique as tryPhoenixRevive.
----------------------------------------------------------------

do

function Phoenix.castWrath(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local entry = CharacterRegistry.getAbilityById("jean_grey", "phoenix_wrath")
	if not entry or not canUse(character, entry.id, entry.energyCost) then
		return
	end
	local root = getRoot(character)
	local hum = CombatHelper.getHumanoid(character)
	if not root or not hum then
		return
	end

	-- Server-wide, not per-player: Phoenix Wrath charges off damage she
	-- deals (CombatHelper.dealDamage accumulates this on every hit while
	-- LOOK_MODE_ATTRIBUTE == "phoenix"), not a timer - only ready once
	-- MG_WRATH_DAMAGE_THRESHOLD has landed since the last cast. On top of
	-- that, MG_WRATH_GLOBAL_COOLDOWN enforces a real-time floor so a very
	-- high damage output can't chain casts back to back. Resetting both the
	-- counter and the timestamp on cast is also what enforces "only one at a
	-- time". Stored as Workspace attributes so any client can read readiness
	-- directly off replication - see GameplayHUD's Wrath bar.
	do
		local accum = Workspace:GetAttribute("PhoenixWrathDamageAccum")
		if type(accum) ~= "number" then
			accum = 0
		end
		local lastCastAt = Workspace:GetAttribute("PhoenixWrathLastCastAt")
		local onCooldown = type(lastCastAt) == "number"
			and (AbilityCooldownHelper.getNow() - lastCastAt) < GameConstants.MG_WRATH_GLOBAL_COOLDOWN
		if accum < GameConstants.MG_WRATH_DAMAGE_THRESHOLD or onCooldown then
			-- canUse() above already spent the energy cost - refund it since
			-- Wrath never actually goes off from here.
			local energy = character:GetAttribute(GameConstants.ENERGY_ATTRIBUTE)
			local maxEnergy = character:GetAttribute(GameConstants.MAX_ENERGY_ATTRIBUTE)
			if type(energy) == "number" and type(maxEnergy) == "number" then
				character:SetAttribute(GameConstants.ENERGY_ATTRIBUTE, math.min(maxEnergy, energy + entry.energyCost))
			end
			return
		end
	end
	Workspace:SetAttribute("PhoenixWrathDamageAccum", 0)
	Workspace:SetAttribute("PhoenixWrathLastCastAt", AbilityCooldownHelper.getNow())

	AbilityCooldownHelper.setActive(character, entry.id, true)
	character:SetAttribute(GameConstants.BUSY_ATTRIBUTE, true)
	attachPowerFx(character)
	playJeanAnim(character, GameConstants.MG_PHOENIX_WRATH_ANIM, false)
	fireCameraShake(player, 0.6, 0.45, 0.4, 0.6)

	local walk = hum.WalkSpeed
	local jumpPower: number? = nil
	local jumpHeight: number? = nil
	if hum.UseJumpPower then
		jumpPower = hum.JumpPower
	else
		jumpHeight = hum.JumpHeight
	end
	hum.WalkSpeed = 0
	hum.JumpPower = 0
	pcall(function()
		hum.JumpHeight = 0
		hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	end)
	hum:Move(Vector3.zero, false)

	local function attachFollowFx(template: Instance?, yOffset: number, name: string, rotation: CFrame?, zOffset: number?): Instance?
		if not template or not template:IsA("BasePart") then
			return nil
		end
		local fx = template:Clone()
		fx.Name = name
		fx.Anchored = false
		fx.CanCollide = false
		fx.CanQuery = false
		fx.CanTouch = false
		fx.Massless = true
		-- WeldConstraint has no C0/C1 offset - any rotation offset has to be
		-- baked into this CFrame before the weld goes on (same as the wings).
		-- zOffset is in root's local space, where +Z is backward (LookVector
		-- is -Z), so a positive value pushes the fx behind her.
		fx.CFrame = root.CFrame * CFrame.new(0, yOffset, zOffset or 0) * (rotation or CFrame.new())
		fx.Parent = character
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = fx
		weld.Parent = fx
		VfxHelper.setParticlesEnabled(fx, true)
		VfxHelper.emitAllParticles(fx, 12)
		return fx
	end

	local auraTemplate = getPhoenixAsset(character, "PhoenixWrath", "Phoenix")
	local groundTemplate = getPhoenixAsset(character, "PhoenixWrath", "Ground")
	local chargeTemplate = getPhoenixAsset(character, "PhoenixWrath", "PhoenixWrathCharge")
	if not auraTemplate then
		warn("[MarvelGirl] Missing Phoenix wrath asset (Assets.JeanGrey.JeanGreyThePhoenixForce.PhoenixWrath.Phoenix)")
	end
	if not groundTemplate then
		warn("[MarvelGirl] Missing Phoenix wrath asset (Assets.JeanGrey.JeanGreyThePhoenixForce.PhoenixWrath.Ground)")
	end
	if not chargeTemplate then
		warn("[MarvelGirl] Missing Phoenix wrath asset (Assets.JeanGrey.JeanGreyThePhoenixForce.PhoenixWrath.PhoenixWrathCharge)")
	end
	-- Ground and the Phoenix aura both now stay hidden until the charge-up
	-- finishes (float complete + 1s) - see the float-complete branch below,
	-- which disables the charge VFX and activates both together at that
	-- moment instead of each on its own separate delay.
	local groundFx: Instance? = nil
	local auraFx: Instance? = nil
	local chargeFx: Instance? = nil
	if chargeTemplate then
		-- emitCount 0: charge VFX should build up via its own Rate, not also
		-- burst 12 particles the instant Wrath starts (that's the "too much
		-- at the start" the user reported).
		chargeFx = attachCloneToPart(chargeTemplate, root, 0)
	end

	local att = Instance.new("Attachment")
	att.Name = "MgWrathFloatAtt"
	att.Parent = root
	local align = Instance.new("AlignPosition")
	align.Name = "MgWrathFloat"
	align.Mode = Enum.PositionAlignmentMode.OneAttachment
	align.Attachment0 = att
	align.ApplyAtCenterOfMass = true
	align.RigidityEnabled = false
	align.Responsiveness = 10
	align.MaxForce = 1e6
	align.MaxVelocity = 90
	align.Parent = root

	local startPos = root.Position
	local floatTarget = startPos + Vector3.new(0, GameConstants.MG_WRATH_FLOAT_HEIGHT, 0)
	align.Position = startPos

	-- Dying (or any other interrupt that removes/replaces her, or drops her
	-- health) mid-Wrath must cancel it, not keep floating/burning a corpse.
	local function wrathAlive(): boolean
		return character.Parent
			and root.Parent
			and player.Character == character
			and hum.Parent ~= nil
			and hum.Health > 0
	end

	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < GameConstants.MG_WRATH_FLOAT_TIME do
			if not wrathAlive() then
				break
			end
			local a = math.clamp((os.clock() - t0) / GameConstants.MG_WRATH_FLOAT_TIME, 0, 1)
			local ease = a * a * (3 - 2 * a)
			align.Position = startPos:Lerp(floatTarget, ease)
			task.wait()
		end

		if wrathAlive() then
			align.Position = floatTarget
			root.AssemblyLinearVelocity = Vector3.zero
			ScreenFeelHelper.setShakeHold(character, true)

			-- Charge VFX covers the whole cast-to-float window; hold it this
			-- long once the float position is reached, then swap it out for
			-- the real aura + ground VFX together - this is the "phoenix
			-- baseparts effects appearing" delay (2s earlier per request).
			task.wait(GameConstants.MG_WRATH_PHOENIX_FX_DELAY)

			if chargeFx and chargeFx.Parent then
				VfxHelper.smoothDisableParticles(chargeFx, 0.3)
				local fx = chargeFx
				task.delay(0.4, function()
					if fx.Parent then
						fx:Destroy()
					end
				end)
			end

			if wrathAlive() then
				-- Same -90 degree yaw offset as the wings - the asset is
				-- authored facing the "wrong" way for a straight weld, same
				-- fix as attachWings above.
				auraFx = attachFollowFx(auraTemplate, -4, "PhoenixWrathAura", CFrame.Angles(0, math.rad(-90), 0), 1.5)
			end

			if groundTemplate and groundTemplate:IsA("BasePart") and wrathAlive() then
				local fx = groundTemplate:Clone()
				fx.Name = "PhoenixWrathGround"
				fx.Anchored = true
				fx.CanCollide = false
				fx.CanQuery = false
				fx.CanTouch = false
				-- startPos (captured before the float-up began), NOT the live
				-- root.Position - by the time this runs she's already hovering
				-- at floatTarget (50 studs up), so root.Position here was her
				-- elevated position, placing the ground FX floating in midair
				-- next to her instead of on the actual ground.
				local groundPos = startPos - Vector3.new(0, root.Size.Y / 2 - 1, 0)
				fx.CFrame = CFrame.new(groundPos) * (groundTemplate.CFrame - groundTemplate.CFrame.Position)
				fx.Parent = Workspace
				VfxHelper.setParticlesEnabled(fx, true)
				smoothEnableFx(fx, 0.25)
				VfxHelper.emitAllParticles(fx, 12)
				groundFx = fx
			end

			-- Burn + slow for the whole duration, THEN throw everyone once at
			-- the end. Pushing every tick (what it used to do) both flung
			-- targets out of range immediately - so they never took more than
			-- the first tick - and re-ragdolled them every second, since
			-- PushHelper.applyToCharacter puts the Humanoid into Physics state
			-- unless noRagdoll is passed.
			local slowed: { [Model]: number } = {}
			local dealt: { [Model]: number } = {}
			local burning: { [Model]: boolean } = {}
			local elapsed = 0
			while wrathAlive() and elapsed < GameConstants.MG_WRATH_DURATION do
				local inRange: { [Model]: boolean } = {}
				for _, victim in CombatHelper.overlapCharacters(root.Position, GameConstants.MG_WRATH_RADIUS, character) do
					inRange[victim] = true
					do
						-- Damage always routes through dealDamage - shielded
						-- targets take it on the shield HP instead of health
						-- (CombatHelper handles that split internally). The
						-- burn visuals only make sense once it's actually
						-- reaching the character, so those stay shield-gated.
						local already = dealt[victim] or 0
						local hit = math.min(GameConstants.MG_WRATH_DAMAGE_PER_TICK, GameConstants.MG_WRATH_MAX_DAMAGE - already)
						if hit > 0 then
							dealt[victim] = already + hit
							CombatHelper.dealDamage(character, victim, hit, root.Position, "dot")
						end
						if not CombatHelper.isShielded(victim) and not burning[victim] then
							burning[victim] = true
							Phoenix.beginBurnVfx(victim)
							ScreenFeelHelper.setTint(victim, GameConstants.MG_WRATH_ORANGE, nil)
							ScreenFeelHelper.setShakeHold(victim, true)
						end
					end
					if slowed[victim] == nil then
						local vHum = CombatHelper.getHumanoid(victim)
						if vHum then
							slowed[victim] = vHum.WalkSpeed
							vHum.WalkSpeed *= GameConstants.MG_WRATH_SLOW_MULT
							victim:SetAttribute(GameConstants.MOVEMENT_SLOWED_ATTRIBUTE, true)
						end
					end
				end
				-- Anyone who left the radius gets their speed back right away
				-- rather than staying slowed until the ability ends.
				for victim, savedWalk in pairs(slowed) do
					if not inRange[victim] then
						if victim.Parent then
							local vHum = CombatHelper.getHumanoid(victim)
							if vHum then
								vHum.WalkSpeed = savedWalk
							end
							victim:SetAttribute(GameConstants.MOVEMENT_SLOWED_ATTRIBUTE, nil)
						end
						slowed[victim] = nil
					end
				end
				for victim in pairs(burning) do
					if not inRange[victim] then
						burning[victim] = nil
						Phoenix.endBurnVfx(victim)
						ScreenFeelHelper.setTint(victim, nil)
						ScreenFeelHelper.setShakeHold(victim, false)
					end
				end
				task.wait(GameConstants.MG_WRATH_TICK)
				elapsed += GameConstants.MG_WRATH_TICK
			end

			-- Restore speed first, then throw - a still-slowed Humanoid fights
			-- its own knockback velocity.
			for victim, savedWalk in pairs(slowed) do
				if victim.Parent then
					local vHum = CombatHelper.getHumanoid(victim)
					if vHum then
						vHum.WalkSpeed = savedWalk
					end
					victim:SetAttribute(GameConstants.MOVEMENT_SLOWED_ATTRIBUTE, nil)
				end
			end
			table.clear(slowed)
			for victim in pairs(burning) do
				Phoenix.endBurnVfx(victim)
				ScreenFeelHelper.setTint(victim, nil)
				ScreenFeelHelper.setShakeHold(victim, false)
			end
			table.clear(burning)

			if wrathAlive() then
				for _, victim in CombatHelper.overlapCharacters(root.Position, GameConstants.MG_WRATH_RADIUS, character) do
					-- Knockback/ragdoll shouldn't bypass a shield still up at
					-- the end of the burn, even though the DoT above already
					-- chipped it.
					local vRoot = not CombatHelper.isShielded(victim) and getRoot(victim)
					if vRoot then
						local pushDir = Vector3.new(vRoot.Position.X - root.Position.X, 0, vRoot.Position.Z - root.Position.Z)
						if pushDir.Magnitude < 0.01 then
							pushDir = Vector3.new(0, 0, -1)
						end
						PushHelper.applyToCharacter(victim, pushDir, {
							speed = GameConstants.MG_WRATH_PUSH_SPEED,
							upBoost = GameConstants.MG_WRATH_PUSH_UP,
							noRagdoll = true,
						})
						RagdollService.applyTimed(victim, GameConstants.MG_WRATH_PUSH_RAGDOLL_TIME)
					end
				end
			end
		end

		if align.Parent then
			align:Destroy()
		end
		if att.Parent then
			att:Destroy()
		end
		if auraFx and auraFx.Parent then
			VfxHelper.retireFxSmooth(auraFx, 1, 1.8)
		end
		if groundFx and groundFx.Parent then
			VfxHelper.retireFxSmooth(groundFx, 1, 1.8)
		end

		ScreenFeelHelper.setShakeHold(character, false)
		if character.Parent then
			endPowerFx(character)
			character:SetAttribute(GameConstants.BUSY_ATTRIBUTE, nil)
			if hum.Parent then
				hum.WalkSpeed = walk
				if jumpPower ~= nil then
					hum.JumpPower = jumpPower
				end
				if jumpHeight ~= nil then
					pcall(function()
						hum.JumpHeight = jumpHeight
					end)
				end
				pcall(function()
					hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
				end)
			end
			if AbilityCooldownHelper.isActive(character, entry.id) then
				-- Dying mid-Wrath is a cancel, not a completed use - no
				-- cooldown for that (matches every other interrupt path).
				if hum.Health > 0 then
					finishAbility(character, entry.id, entry.cooldown)
				else
					AbilityCooldownHelper.setActive(character, entry.id, false)
				end
			end
		end
	end)
end

end -- Phoenix Wrath

local function outburstAoe(body: Model, pos: Vector3)
	for _, victim in CombatHelper.overlapCharacters(pos, GameConstants.MG_OUTBURST_RADIUS, body) do
		if victim:GetAttribute(GameConstants.MG_ASTRAL_ATTRIBUTE) == true then
			continue
		end
		local shieldedBeforeHit = CombatHelper.isShielded(victim)
		local away = Vector3.zero
		local vRoot = getRoot(victim)
		if vRoot then
			away = vRoot.Position - pos
		end
		-- Point-blank takes the full blast, the edge of the radius a fraction of it.
		local closeness = 1 - GameConstants.MG_OUTBURST_EDGE_LOSS * math.clamp(away.Magnitude / GameConstants.MG_OUTBURST_RADIUS, 0, 1)
		CombatHelper.dealDamage(body, victim, GameConstants.MG_OUTBURST_DAMAGE * closeness, pos, "projectile")
		if not (shieldedBeforeHit and CombatHelper.isShielded(victim)) then
			RagdollService.applyTimed(victim, GameConstants.MG_OUTBURST_RAGDOLL * closeness)
		end
		if not (shieldedBeforeHit and CombatHelper.isShielded(victim)) then
			PushHelper.applyToCharacter(victim, if away.Magnitude > 0.05 then away.Unit else Vector3.new(0, 0, -1), {
				speed = GameConstants.MG_OUTBURST_KNOCK * closeness,
				upBoost = 22,
				noRagdoll = true,
			})
		end
	end
end

local function spawnOutburstRepulse(pos: Vector3, character: Model?)
	local template = VfxHelper.getMarvelGirlAsset("TelepathicOutburst", "Repulse")
	if not template then
		local color = jeanAccent(character)
		VfxHelper.spawnPulseRing(pos, 12, color, 0.7)
		VfxHelper.spawnBurstSparks(pos, color, 18)
		return
	end
	local fx = template:Clone()
	fx.Name = "MgTelepathicRepulse"
	if fx:IsA("BasePart") then
		fx.Anchored = true
		fx.CanCollide = false
		fx.CanQuery = false
		fx.CanTouch = false
		fx.CFrame = CFrame.new(pos)
		fx.Parent = Workspace
	elseif fx:IsA("Model") then
		fx:PivotTo(CFrame.new(pos))
		fx.Parent = Workspace
	elseif fx:IsA("Attachment") then
		local host = makeFxHost("MgOutburstHost", CFrame.new(pos))
		fx.Parent = host
		fx.CFrame = CFrame.identity
	else
		fx.Parent = Workspace
	end
	VfxHelper.emitByCount(fx)
	styleJeanFx(fx, nil, character)
	local accent = jeanAccent(character)
	local function paintOutburstPart(inst: Instance)
		if inst:IsA("BasePart") then
			inst.Color = accent
		end
	end
	paintOutburstPart(fx)
	for _, desc in fx:GetDescendants() do
		paintOutburstPart(desc)
	end
	task.delay(2.2, function()
		if fx.Parent then
			VfxHelper.smoothDisableParticles(fx, 0.7)
		end
	end)
	task.delay(4.2, function()
		local parent = fx.Parent
		if fx.Parent then
			fx:Destroy()
		end
		if parent and parent.Name == "MgOutburstHost" and parent.Parent then
			parent:Destroy()
		end
	end)
end

local function fadeAstralInvisible(state: AstralState, duration: number)
	local info = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	if state.astral.Parent then
		for _, desc in state.astral:GetDescendants() do
			if desc:IsA("BasePart") then
				TweenService:Create(desc, info, { Transparency = 1 }):Play()
			elseif desc:IsA("Decal") or desc:IsA("Texture") then
				TweenService:Create(desc, info, { Transparency = 1 }):Play()
			end
		end
	end
	for _, fx in state.fx do
		if fx:IsA("Highlight") then
			TweenService:Create(fx, info, { FillTransparency = 1, OutlineTransparency = 1 }):Play()
		elseif fx:IsA("ParticleEmitter") or fx:IsA("Trail") or fx:IsA("Beam") then
			fx.Enabled = false
		end
	end
end

local function castTelepathicOutburst(player: Player)
	local astral = astralByPlayer[player]
	local body = player.Character
	if not astral or not body or astral.outbursting or astral.returning then
		return
	end
	if not canUse(body, "telepathic_outburst", GameConstants.MG_OUTBURST_ENERGY) then
		return
	end
	stopTelepathicPain(player, true)
	AbilityCooldownHelper.setActive(body, "telepathic_outburst", true)
	astral.outbursting = true
	astral.moveDir = Vector3.zero
	astral.currentVel = Vector3.zero
	astral.outburstHoldCf = astral.root.CFrame
	astral.mover.linearVelocity.VectorVelocity = Vector3.zero
	-- AlignOrientation is never re-targeted while outbursting (the update
	-- loop just force-sets root.CFrame every tick), so if it was still
	-- aimed wherever Pain/flight last left it, it fights the frozen CFrame
	-- with real torque the whole time - reads as rotation stuck/snapping.
	-- Pin it to the same frozen orientation so there's nothing to fight.
	if astral.mover.alignOrientation then
		astral.mover.alignOrientation.CFrame = astral.outburstHoldCf
	end
	pcall(function()
		astral.root:SetNetworkOwner(nil)
	end)
	fireCameraShake(player, 0.5, 0.55, 0.38, 0.7)
	local token = (outburstToken[player] or 0) + 1
	outburstToken[player] = token
	task.spawn(function()
		local dur = GameConstants.MG_OUTBURST_HIGHLIGHT_TIME
		local t0 = os.clock()
		local starts: { [Highlight]: number } = {}
		for _, fx in astral.fx do
			if fx:IsA("Highlight") then
				starts[fx] = fx.FillTransparency
			end
		end
		while os.clock() - t0 < dur do
			if outburstToken[player] ~= token or astralByPlayer[player] ~= astral or not astral.astral.Parent then
				if body.Parent then
					AbilityCooldownHelper.setActive(body, "telepathic_outburst", false)
				end
				return
			end
			local a = math.clamp((os.clock() - t0) / dur, 0, 1)
			for hl, startFill in starts do
				if hl.Parent then
					hl.FillTransparency = startFill + (0.12 - startFill) * a
				end
			end
			task.wait()
		end
		task.wait(GameConstants.MG_OUTBURST_PAUSE)
		if outburstToken[player] ~= token or astralByPlayer[player] ~= astral or not astral.astral.Parent then
			if body.Parent then
				AbilityCooldownHelper.setActive(body, "telepathic_outburst", false)
			end
			return
		end
		local pos = astral.root.Position
		playWorldSound(GameConstants.MG_OUTBURST_SOUND, pos, 1.1)
		spawnOutburstRepulse(pos, body)
		outburstAoe(body, pos)
		astral.keepHighlightUntilNear = false
		if body.Parent then
			finishAbility(body, "telepathic_outburst", GameConstants.MG_OUTBURST_COOLDOWN)
		end
		fadeAstralInvisible(astral, GameConstants.MG_OUTBURST_FADE)
		task.wait(GameConstants.MG_OUTBURST_FADE)
		if GameConstants.MG_OUTBURST_STAY > 0 then
			task.wait(GameConstants.MG_OUTBURST_STAY)
		end
		if outburstToken[player] ~= token or astralByPlayer[player] ~= astral or not astral.astral.Parent then
			return
		end
		astral.outbursting = false
		astral.outburstHoldCf = nil
		endAstral(player, true)
	end)
end

local function playWakeAnim(character: Model): AnimationTrack?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	local track = AnimationLoadHelper.load(animator :: Animator, GameConstants.MG_WAKE_ANIM, "MarvelGirl MG_WAKE_ANIM:" .. character.Name)
	if not track then
		return nil
	end
	track.Priority = Enum.AnimationPriority.Action4
	track.Looped = false
	track:Play(0.12, 1, 1)
	return track
end

local hairTrackByPlayer: { [Player]: AnimationTrack? } = {}
local hairToken: { [Player]: number } = {}

local function tweenHairTree(inst: Instance, visible: boolean)
	local transparency = if visible then 0 else 1
	local info = TweenInfo.new(GameConstants.MG_HAIR_SWITCH_FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local function apply(obj: Instance)
		if obj:IsA("BasePart") then
			obj.LocalTransparencyModifier = 0
			TweenService:Create(obj, info, { Transparency = transparency }):Play()
		elseif obj:IsA("Decal") or obj:IsA("Texture") then
			TweenService:Create(obj, info, { Transparency = transparency }):Play()
		elseif obj:IsA("ParticleEmitter") or obj:IsA("Beam") or obj:IsA("Trail") or obj:IsA("Highlight") then
			obj.Enabled = visible
		end
	end
	apply(inst)
	for _, desc in inst:GetDescendants() do
		apply(desc)
	end
end

local function isHairVisible(inst: Instance): boolean
	if inst:IsA("BasePart") then
		return inst.Transparency < 0.5
	end
	for _, desc in inst:GetDescendants() do
		if desc:IsA("BasePart") and desc.Transparency < 0.5 then
			return true
		end
	end
	return false
end

local function toggleJeanHair(character: Model)
	local head = character:FindFirstChild("Head")
	local other = if head then head:FindFirstChild("Other") else nil
	if not other then
		return
	end
	local main = other:FindFirstChild("MainHair")
	-- Asset is "Toggle" (Head.Other.Toggle), with its own nested Toggle.Toggle
	-- child being the same hair piece, not a separate one - tweenHairTree
	-- already recurses via GetDescendants() so toggling the outer Toggle covers both.
	local pony = other:FindFirstChild("Toggle")
	if not main or not pony then
		return
	end
	local showPonytails = isHairVisible(main)
	tweenHairTree(main, not showPonytails)
	tweenHairTree(pony, showPonytails)
	character:SetAttribute(GameConstants.MG_HAIR_TIED_ATTRIBUTE, showPonytails)
end

local function playJeanHairToggle(player: Player, character: Model)
	-- Base Jean only - Marvel Girl never had it, and Phoenix shouldn't either.
	local lookMode = MarvelGirlService.lookOf(character)
	if lookMode == "marvel_girl" or lookMode == "xmen_red" or GameConstants.PHOENIX_LOOK_IDS[lookMode] then
		return
	end
	if character:GetAttribute(GameConstants.IS_FLYING_ATTRIBUTE) == true
		or character:GetAttribute(GameConstants.BUSY_ATTRIBUTE) == true
		or character:GetAttribute(GameConstants.MG_ASTRAL_BODY_ATTRIBUTE) == true
	then
		return
	end
	if AbilityCooldownHelper.isOnCooldown(character, "jean_hair") then
		return
	end
	AbilityCooldownHelper.applyAfterUse(character, "jean_hair", GameConstants.MG_HAIR_COOLDOWN)
	local lockDuration = GameConstants.MG_HAIR_SWITCH_DELAY + GameConstants.MG_HAIR_SWITCH_FADE
	character:SetAttribute(GameConstants.MG_HAIR_SWITCHING_ATTRIBUTE, true)
	character:SetAttribute(GameConstants.BUSY_ATTRIBUTE, true)
	local savedWalk = GameConstants.DEFAULT_WALK_SPEED
	local savedJumpPower: number? = nil
	local savedJumpHeight: number? = nil
	local existing = hairTrackByPlayer[player]
	if existing then
		pcall(function()
			existing:Stop(0.08)
		end)
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		savedWalk = humanoid.WalkSpeed
		savedJumpPower = humanoid.JumpPower
		savedJumpHeight = humanoid.JumpHeight
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		pcall(function()
			humanoid.JumpHeight = 0
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		end)
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = humanoid
		end
		local track = AnimationLoadHelper.load(animator :: Animator, GameConstants.MG_HAIR_ANIM, "MarvelGirl MG_HAIR_ANIM:" .. character.Name)
		if track then
			track.Priority = Enum.AnimationPriority.Action
			track.Looped = false
			track:Play(0.08, 1, 1)
			hairTrackByPlayer[player] = track
		end
	end
	local token = (hairToken[player] or 0) + 1
	hairToken[player] = token
	task.delay(GameConstants.MG_HAIR_SWITCH_DELAY, function()
		if hairToken[player] ~= token then
			return
		end
		toggleJeanHair(character)
		local astral = astralByPlayer[player]
		if astral then
			if astral.body ~= character then
				toggleJeanHair(astral.body)
			end
			if astral.astral ~= character then
				toggleJeanHair(astral.astral)
			end
		end
	end)
	task.delay(lockDuration, function()
		if not character.Parent then
			return
		end
		character:SetAttribute(GameConstants.MG_HAIR_SWITCHING_ATTRIBUTE, nil)
		character:SetAttribute(GameConstants.BUSY_ATTRIBUTE, nil)
		local hum = character:FindFirstChildOfClass("Humanoid")
		if hum and hum.Parent then
			hum.WalkSpeed = savedWalk
			if savedJumpPower ~= nil then
				hum.JumpPower = savedJumpPower
			end
			if savedJumpHeight ~= nil then
				hum.JumpHeight = savedJumpHeight
			end
			pcall(function()
				hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
			end)
		end
	end)
end

local function restoreOverloadMove(player: Player, character: Model?)
	local hold = overloadHoldByPlayer[player]
	overloadHoldByPlayer[player] = nil
	if character then
		character:SetAttribute(GameConstants.MG_WAKING_ATTRIBUTE, nil)
		character:SetAttribute(GameConstants.BUSY_ATTRIBUTE, nil)
	end
	if not hold or not character then
		return
	end
	local hum = CombatHelper.getHumanoid(character)
	if not hum or not hum.Parent then
		return
	end
	hum.WalkSpeed = hold.walk
	if hold.jumpPower ~= nil then
		hum.JumpPower = hold.jumpPower
	end
	if hold.jumpHeight ~= nil then
		hum.JumpHeight = hold.jumpHeight
	end
	pcall(function()
		hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
	end)
end

local wakeToken: { [Player]: number } = {}

local function beginWakeFromOverload(player: Player, character: Model)
	if character:GetAttribute(GameConstants.MG_WAKING_ATTRIBUTE) == true then
		return
	end
	character:SetAttribute(GameConstants.MG_OVERLOAD_ATTRIBUTE, nil)
	character:SetAttribute(GameConstants.MG_WAKING_ATTRIBUTE, true)
	character:SetAttribute(GameConstants.BUSY_ATTRIBUTE, true)
	local hum = CombatHelper.getHumanoid(character)
	if hum then
		hum.WalkSpeed = 0
		hum.JumpPower = 0
		pcall(function()
			hum.JumpHeight = 0
			hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		end)
	end
	local token = (wakeToken[player] or 0) + 1
	wakeToken[player] = token
	local function finishWake()
		if wakeToken[player] ~= token then
			return
		end
		if character.Parent and character:GetAttribute(GameConstants.MG_WAKING_ATTRIBUTE) == true then
			restoreOverloadMove(player, character)
		end
	end
	if character:GetAttribute("Ragdolled") == true then
		RagdollService.clear(character)
		task.spawn(function()
			local deadline = os.clock() + 4
			while character.Parent and character:GetAttribute(GameConstants.GETTING_UP_ATTRIBUTE) == true and os.clock() < deadline do
				task.wait()
			end
			finishWake()
		end)
		return
	end
	local track = playWakeAnim(character)
	local duration = 1.8
	if track and track.Length > 0.05 then
		duration = track.Length / math.max(track.Speed, 0.01)
	end
	task.delay(duration + 0.05, finishWake)
end

local function enterPowerOverload(player: Player, character: Model)
	if character:GetAttribute(GameConstants.MG_OVERLOAD_ATTRIBUTE) == true then
		return
	end
	character:SetAttribute(GameConstants.MG_OVERLOAD_ATTRIBUTE, true)
	HexFlightService.endFlight(player, true)
	MarvelGirlService.cancelAll(player)

	local hum = CombatHelper.getHumanoid(character)
	if hum and not overloadHoldByPlayer[player] then
		local jumpH: number? = nil
		pcall(function()
			jumpH = hum.JumpHeight
		end)
		overloadHoldByPlayer[player] = {
			walk = hum.WalkSpeed,
			jumpPower = hum.JumpPower,
			jumpHeight = jumpH,
			startedAt = os.clock(),
		}
		hum.WalkSpeed = 0
		hum.JumpPower = 0
		pcall(function()
			hum.JumpHeight = 0
			hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		end)
	end
	if not overloadHoldByPlayer[player] then
		overloadHoldByPlayer[player] = {
			walk = GameConstants.DEFAULT_WALK_SPEED,
			jumpPower = 50,
			jumpHeight = nil,
			startedAt = os.clock(),
		}
	end
	RagdollService.apply(character)
	fireCameraShake(player, 0.58, 0.7, 0.45, 0.72)
end

local function updateJeanRestraint(player: Player, dt: number)
	local character = player.Character
	if not character or character:GetAttribute(GameConstants.HERO_ATTRIBUTE) ~= "jean_grey" then
		return
	end
	local maxR = GameConstants.MG_RESTRAINT_MAX
	local current = character:GetAttribute(GameConstants.MG_RESTRAINT_ATTRIBUTE)
	if type(current) ~= "number" then
		current = 0
	end
	local overloaded = character:GetAttribute(GameConstants.MG_OVERLOAD_ATTRIBUTE) == true
	local flying = character:GetAttribute(GameConstants.IS_FLYING_ATTRIBUTE) == true
	local tkOn = character:GetAttribute(GameConstants.TK_ACTIVE_ATTRIBUTE) == true
	local isPhoenixSkin = GameConstants.PHOENIX_LOOK_IDS[MarvelGirlService.lookOf(character)] == true
	local restraintMult = if isPhoenixSkin then GameConstants.MG_PHOENIX_RESTRAINT_MULT else 1
	if not overloaded then
		if flying then
			current += GameConstants.MG_RESTRAINT_FLIGHT_PER_SEC * restraintMult * dt
		end
		if tkOn then
			current += GameConstants.MG_RESTRAINT_TK_PER_SEC * restraintMult * dt
		end
		if not flying and not tkOn then
			current -= GameConstants.MG_RESTRAINT_DECAY_PER_SEC * dt
		end
	else
		current -= GameConstants.MG_RESTRAINT_OVERLOAD_DECAY_PER_SEC * dt
	end
	current = math.clamp(current, 0, maxR)
	character:SetAttribute(GameConstants.MG_RESTRAINT_ATTRIBUTE, current)
	if not overloaded and current >= maxR then
		enterPowerOverload(player, character)
		return
	end
	if overloaded then
		local hold = overloadHoldByPlayer[player]
		local started = if hold then hold.startedAt else os.clock()
		if (os.clock() - started) >= GameConstants.MG_OVERLOAD_DURATION then
			beginWakeFromOverload(player, character)
			return
		end
	end
	if overloaded and current <= maxR * GameConstants.MG_RESTRAINT_WAKE_RATIO then
		beginWakeFromOverload(player, character)
	end
end


----------------------------------------------------------------
-- Psionic Barrier
----------------------------------------------------------------
local function updateBarrierHpUi(state: BarrierState)
	local ratio = if state.maxHp > 0 then math.clamp(state.hp / state.maxHp, 0, 1) else 0
	state.hpLabel.Text = string.format("%d/%d", math.max(0, math.ceil(state.hp)), state.maxHp)
	TweenService:Create(state.hpFill, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.new(ratio, 0, 1, 0),
	}):Play()
	if state.character.Parent then
		state.character:SetAttribute(GameConstants.SHIELD_HP_ATTRIBUTE, state.hp)
	end
end

local function createBarrierHpBillboard(parent: Instance, forJean97: boolean, fillColor: Color3): (BillboardGui, TextLabel, Frame)
	local character = if parent:IsA("Model") then parent else parent:FindFirstAncestorOfClass("Model")
	local head = if character then getHead(character) else nil
	local gui = Instance.new("BillboardGui")
	gui.Name = "ShieldHealthGui"
	gui.Size = GameConstants.SHIELD_UI_SIZE
	gui.StudsOffset = GameConstants.SHIELD_UI_OFFSET
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = GameConstants.NAMEPLATE_MAX_DISTANCE
	if head then
		gui.Adornee = head
		gui.Parent = character
	else
		gui.Parent = parent
	end

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Size = UDim2.fromScale(1, 1)
	track.BackgroundColor3 = if forJean97 then Color3.fromRGB(28, 28, 34) else Color3.fromRGB(28, 22, 28)
	track.BackgroundTransparency = 0
	track.BorderSizePixel = 0
	track.Parent = gui

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(0.2, 0)
	trackCorner.Parent = track

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = fillColor
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
	hpLabel.Text = "100/100"
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

local function retireForcefield(ff: Instance)
	if not ff.Parent then
		return
	end
	-- Detach so particles can finish without following the character
	for _, d in ff:GetDescendants() do
		if d:IsA("WeldConstraint") or d:IsA("Weld") or d:IsA("Motor6D") then
			d:Destroy()
		end
	end
	if ff:IsA("BasePart") then
		ff.Anchored = true
		ff.CanCollide = false
		ff.Parent = Workspace
	elseif ff:IsA("Model") then
		local primary = ff.PrimaryPart or ff:FindFirstChildWhichIsA("BasePart", true)
		if primary and primary:IsA("BasePart") then
			primary.Anchored = true
			primary.CanCollide = false
		end
		ff.Parent = Workspace
	end
	-- Disable particles first, delete after 3s
	VfxHelper.smoothDisableParticles(ff, 0.2)
	if ff:IsA("BasePart") then
		TweenService:Create(ff, TweenInfo.new(0.35), { Transparency = 1 }):Play()
	end
	for _, d in ff:GetDescendants() do
		if d:IsA("BasePart") then
			TweenService:Create(d, TweenInfo.new(0.35), { Transparency = 1 }):Play()
		end
	end
	task.delay(3, function()
		if ff.Parent then
			ff:Destroy()
		end
	end)
end

local function playBarrierAnim(character: Model): AnimationTrack?
	return playJeanAnim(character, GameConstants.MG_SHIELD_ANIM, true)
end

local function stopBarrier(player: Player, applyCooldown: boolean?)
	local state = barrierByPlayer[player]
	if not state then
		return
	end
	barrierByPlayer[player] = nil
	if state.animTrack then
		state.animTrack:Stop(0.2)
		state.animTrack:Destroy()
		state.animTrack = nil
	end
	if state.healthConn then
		state.healthConn:Disconnect()
		state.healthConn = nil
	end
	if state.billboard and state.billboard.Parent then
		state.billboard:Destroy()
	end
	retireForcefield(state.forcefield)
	local character = state.character
	if character and character.Parent then
		if state.session then
			state.session:finish("stop")
		end
		state.character:SetAttribute(GameConstants.SHIELD_ACTIVE_ATTRIBUTE, nil)
		state.character:SetAttribute(GameConstants.MG_BARRIER_ATTRIBUTE, nil)
		state.character:SetAttribute(GameConstants.SHIELD_HP_ATTRIBUTE, nil)
		AbilityCooldownHelper.setActive(state.character, "psionic_barrier", false)
		endPowerFx(state.character)
		if MarvelGirlService.lookOf(state.character) == "marvel_girl" then
			Phoenix.removeMarvelGirlFlightEyes(state.character)
		end
		if applyCooldown then
			AbilityCooldownHelper.applyAfterUse(state.character, "psionic_barrier", GameConstants.MG_BARRIER_COOLDOWN)
			CharacterService.markAbilityUse(state.character)
		end
	end
end

local function startBarrier(player: Player)
	local character = player.Character
	if not character or barrierByPlayer[player] then
		return
	end
	local entry = CharacterRegistry.getAbilityById("jean_grey", "psionic_barrier")
	if not entry then
		return
	end
	if CombatHelper.arePowersDisabled(character, entry.id) then
		return
	end
	if character:GetAttribute(GameConstants.MG_ASTRAL_ATTRIBUTE) == true
		or character:GetAttribute(GameConstants.MG_ASTRAL_BODY_ATTRIBUTE) == true
	then
		return
	end
	if AbilityCooldownHelper.isOnCooldown(character, entry.id) then
		return
	end

	local root = getRoot(character)
	if not root then
		return
	end
	local phoenixSkin = GameConstants.PHOENIX_LOOK_IDS[MarvelGirlService.lookOf(character)] == true
	-- Phoenix keeps her own Infernal shield; only Dark Phoenix (after her resurrection) gets the Cosmic Shield look.
	local darkShield = phoenixSkin and character:GetAttribute("MgDarkPhoenix") == true
	local marvelGirlSkin = MarvelGirlService.lookOf(character) == "marvel_girl"
	-- New shield asset (Marvel Girl skin only) - always recolored via
	-- styleJeanFx (MG_PSI_COLOR_MARVEL_GIRL) below regardless of source
	-- asset. Base Jean keeps the old Shield asset.
	local newMgShield = marvelGirlSkin and VfxHelper.getMarvelGirlAsset("MarvelGirlShield")
	local template = if phoenixSkin
		then (if darkShield then getPhoenixAsset(character, "HealingAura", "CosmicHealing") else getPhoenixAsset(character, "Shield"))
		else (newMgShield or VfxHelper.getMarvelGirlAsset("Shield") or VfxHelper.getMarvelGirlAsset("Forcefield"))
	if not template then
		warn("[MarvelGirl] Missing Jean shield asset")
		return
	end

	AbilityCooldownHelper.setActive(character, entry.id, true)
	attachPowerFx(character)
	if marvelGirlSkin then
		Phoenix.attachMarvelGirlFlightEyes(character)
	end
	local animTrack = if darkShield then nil else playBarrierAnim(character)

	local ff = template:Clone()
	ff.Name = "MgShield"
	-- Dark Phoenix's Cosmic Shield keeps the Cosmic Healing look exactly as authored (no Jean recolour / burst).
	if not darkShield then
		styleJeanFx(ff, nil, character)
	end
	VfxHelper.setParticlesEnabled(ff, true)
	if not darkShield then
		VfxHelper.emitAllParticles(ff, 8)
	end
	if ff:IsA("BasePart") then
		ff.Anchored = false
		ff.CanCollide = false
		ff.CanQuery = false
		ff.CanTouch = false
		ff.Massless = true
		ff.CFrame = root.CFrame
		ff.Parent = character
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = ff
		weld.Parent = ff
	elseif ff:IsA("Model") or ff:FindFirstChildWhichIsA("BasePart", true) then
		ff.Parent = character
		if ff:IsA("Model") then
			ff:PivotTo(root.CFrame)
		end
		local primary = if ff:IsA("Model")
			then (ff.PrimaryPart or ff:FindFirstChildWhichIsA("BasePart", true))
			else ff:FindFirstChildWhichIsA("BasePart", true)
		if primary and primary:IsA("BasePart") then
			primary.Anchored = false
			primary.CanCollide = false
			primary.Massless = true
			primary.CFrame = root.CFrame
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = primary
			weld.Parent = primary
		end
	else
		ff.Parent = root
	end

	local maxHp = if GameConstants.PHOENIX_LOOK_IDS[MarvelGirlService.lookOf(character)] == true
		then GameConstants.MG_PHOENIX_BARRIER_HP
		else GameConstants.MG_BARRIER_HP
	character:SetAttribute(GameConstants.SHIELD_ACTIVE_ATTRIBUTE, true)
	character:SetAttribute(GameConstants.MG_BARRIER_ATTRIBUTE, true)
	character:SetAttribute(GameConstants.SHIELD_HP_ATTRIBUTE, maxHp)

	local billboard, hpLabel, hpFill = createBarrierHpBillboard(character, isJean97(character), jeanAccent(character))
	local astralBody = character:GetAttribute(GameConstants.MG_ASTRAL_BODY_ATTRIBUTE) == true
	local hum = CombatHelper.getHumanoid(character)
	local barrierSession: any = nil
	if hum and not astralBody and not darkShield then
		barrierSession = require(script.Parent.AbilitySession).begin(character, "psionic_barrier", 900)
		barrierSession:lock({
			walk = math.clamp(GameConstants.MG_BARRIER_WALK_SPEED / math.max(hum.WalkSpeed, 1), 0, 1),
			jump = true,
		})
	end
	local state: BarrierState = {
		character = character,
		hp = maxHp,
		maxHp = maxHp,
		forcefield = ff,
		billboard = billboard,
		hpLabel = hpLabel,
		hpFill = hpFill,
		healthConn = nil,
		lastHealth = if hum then hum.Health else 100,
		session = barrierSession,
		animTrack = animTrack,
		dark = darkShield,
		}
		updateBarrierHpUi(state)
	barrierByPlayer[player] = state

	-- Any HP loss while shielded is redirected into the barrier
	if hum then
		state.healthConn = hum.HealthChanged:Connect(function(hp)
			local live = barrierByPlayer[player]
			if not live or live ~= state then
				return
			end
			if hp >= live.lastHealth then
				live.lastHealth = hp
				return
			end
			-- A genuine kill (Reset's forced hum.Health = 0, admin kill, ...)
			-- must not get redirected into the barrier as "damage" - same
			-- guard InvisibleWomanService's own shield redirect already has.
			-- Without it, Reset while shielded both restored her health right
			-- back (fighting the reset) and played the real break sound/
			-- overflow-damage path for a death that was never real combat.
			if hp <= 0 then
				return
			end
			local lost = live.lastHealth - hp
			hum.Health = live.lastHealth
			MarvelGirlService.damageBarrier(character, lost, nil)
		end)
	end
end

function MarvelGirlService.damageBarrier(character: Model, amount: number, _hitFrom: Vector3?): boolean
	if character:GetAttribute(GameConstants.MG_BARRIER_ATTRIBUTE) ~= true then
		return false
	end
	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return false
	end
	local state = barrierByPlayer[player]
	if not state then
		return false
	end
	state.hp -= amount
	updateBarrierHpUi(state)
	if state.hp <= 0 then
		local overflow = -state.hp
		local root = getRoot(character)
		-- Break SFX first, on Jean's root so it starts immediately (asset is preloaded)
		if root then
			playAttachedSound(root, GameConstants.MG_BARRIER_BREAK_SOUND, 1.25)
		end
		stopBarrier(player, true)
		if overflow > 0 then
			local hum = CombatHelper.getHumanoid(character)
			if hum and hum.Health > 0 and CombatHelper.isCombatEligible(character) then
				hum:TakeDamage(overflow)
			end
		end
	end
	return true
end

----------------------------------------------------------------
-- Astral Projection
----------------------------------------------------------------
local function lingerAstralFx(fxList: { Instance }, _body: Model?)
	local deleteAfter = GameConstants.MG_ASTRAL_FX_DELETE
	for _, fx in fxList do
		if not fx.Parent then
			continue
		end
		if fx:IsA("Highlight") then
			-- Highlight already faded during return; destroy immediately
			fx:Destroy()
			continue
		end
		VfxHelper.smoothDisableParticles(fx, 0.35)
		local worldCf: CFrame
		if fx:IsA("BasePart") then
			worldCf = fx.CFrame
		elseif fx:IsA("Attachment") then
			worldCf = fx.WorldCFrame
		elseif fx:IsA("ParticleEmitter") and fx.Parent and fx.Parent:IsA("BasePart") then
			worldCf = (fx.Parent :: BasePart).CFrame
		else
			worldCf = CFrame.new()
		end
		local host = makeFxHost("MgAstralFxLinger", worldCf)
		fx.Parent = host
		task.delay(deleteAfter, function()
			if host.Parent then
				host:Destroy()
			end
		end)
	end
end

local function finishAstralCleanup(player: Player, state: AstralState, applyCooldown: boolean?)
	if state.healthConn then
		state.healthConn:Disconnect()
	end
	stopAstralBodyAnim(state)
	ConstraintHelper.destroyMover(state.mover)
	lingerAstralFx(state.fx, state.body)
	if state.astral.Parent then
		CombatHelper.silenceDeathSounds(state.astral)
		state.astral:Destroy()
	end
	if state.body.Parent then
		state.body:SetAttribute(GameConstants.MG_ASTRAL_BODY_ATTRIBUTE, nil)
		state.body:SetAttribute(GameConstants.MG_ASTRAL_END_AT_ATTRIBUTE, nil)
		unfreezeBody(player, state.body)
		NameplateService.setHidden(state.body, false, 0.18)
	end
	fadeStopSound(state.loopSound, 0.25)
	state.loopSound = nil
	Remotes.getEvent("MindLink"):FireClient(player, { phase = "astral_end" })
	if state.body.Parent then
		local cooldownId = state.abilityId or "astral_projection"
		AbilityCooldownHelper.setActive(state.body, cooldownId, false)
		endPowerFx(state.body)
		if applyCooldown then
			AbilityCooldownHelper.applyAfterUse(state.body, cooldownId, GameConstants.MG_ASTRAL_COOLDOWN)
			CharacterService.markAbilityUse(state.body)
		end
	end
end

endAstral = function(player: Player, applyCooldown: boolean?, instant: boolean?)
	stopTelepathicPain(player, true)
	outburstToken[player] = (outburstToken[player] or 0) + 1
	local state = astralByPlayer[player]
	if not state then
		return
	end
	if state.returning and not instant then
		return
	end

	-- Instant: death / cancel / missing parts
	if instant or not state.astral.Parent or not state.body.Parent then
		astralByPlayer[player] = nil
		finishAstralCleanup(player, state, applyCooldown)
		return
	end

	state.returning = true
	state.moveDir = Vector3.zero
	state.currentVel = Vector3.zero
	state.mover.linearVelocity.VectorVelocity = Vector3.zero
	fadeStopSound(state.loopSound, 0.2)
	state.loopSound = nil
	fireCameraShake(player, 0.55, 0.45)
	Remotes.getEvent("MindLink"):FireClient(player, {
		phase = "astral_returning",
		duration = GameConstants.MG_ASTRAL_RETURN_TIME,
	})

	task.spawn(function()
		local dur = GameConstants.MG_ASTRAL_RETURN_TIME
		local t0 = os.clock()
		local startCf = state.root.CFrame
		local highlightStarts: { [Highlight]: { fill: number, outline: number } } = {}
		for _, fx in state.fx do
			if fx:IsA("Highlight") then
				highlightStarts[fx] = {
					fill = fx.FillTransparency,
					outline = fx.OutlineTransparency,
				}
			end
		end
		while os.clock() - t0 < dur do
			if astralByPlayer[player] ~= state then
				return
			end
			local bodyRoot = getRoot(state.body)
			if not bodyRoot or not state.root.Parent or not state.astral.Parent then
				break
			end
			local a = math.clamp((os.clock() - t0) / dur, 0, 1)
			local s = a * a * (3 - 2 * a)
			state.root.CFrame = startCf:Lerp(bodyRoot.CFrame, s)
			-- Keep AlignOrientation's target riding along with the lerp too -
			-- otherwise it's still aimed at whatever it was left at (e.g. the
			-- outburst freeze CFrame) and fights this CFrame write with torque.
			if state.mover.alignOrientation then
				state.mover.alignOrientation.CFrame = state.root.CFrame
			end
			state.mover.linearVelocity.VectorVelocity = Vector3.zero
			if state.mover.vectorForce then
				state.mover.vectorForce.Force = Vector3.new(0, state.root.AssemblyMass * Workspace.Gravity, 0)
			end
			local dist = (state.root.Position - bodyRoot.Position).Magnitude
			local near = GameConstants.MG_ASTRAL_HIGHLIGHT_NEAR
			for hl, start in highlightStarts do
				if hl.Parent then
					if state.keepHighlightUntilNear then
						if dist > near then
							hl.FillTransparency = math.min(start.fill, 0.12)
							hl.OutlineTransparency = start.outline
						else
							local fade = 1 - math.clamp(dist / near, 0, 1)
							local fullFill = math.min(start.fill, 0.12)
							hl.FillTransparency = fullFill + (1 - fullFill) * fade
							hl.OutlineTransparency = start.outline + (1 - start.outline) * fade
						end
					else
						hl.FillTransparency = start.fill + (1 - start.fill) * s
						hl.OutlineTransparency = start.outline + (1 - start.outline) * s
					end
				end
			end
			-- forceAstralNoclip(state.astral) used to run here too, every
			-- single frame of the whole return sequence - the exact same
			-- "residual per-frame lag" documented on the main update loop
			-- above (full GetDescendants() rescan). The astral clone is
			-- already fully stripped once at creation, with a DescendantAdded
			-- listener catching anything added since - nothing new is added
			-- during the return animation, so this was pure waste, reintroduced
			-- here separately from the main loop's own fix.
			task.wait()
		end
		if astralByPlayer[player] == state then
			astralByPlayer[player] = nil
			finishAstralCleanup(player, state, applyCooldown)
		end
	end)
end

-- `borrowedAs`: another hero (Madison's Descensum) projecting through this machinery under its own ability id; its
-- caller has already done that hero's own gating.
local function startAstral(player: Player, borrowedAs: string?)
	local character = player.Character
	if not character or astralByPlayer[player] then
		return
	end
	-- Cannot astral while flying
	if HexFlightService.isFlying(player) then
		return
	end
	-- Grounded only: the true body gets frozen in place for the whole
	-- projection (freezeBodyInPlace), and it no longer anchors the root to
	-- do that (see below) - starting mid-air used to leave the body
	-- Anchored=true and stuck floating exactly where the jump/fall caught
	-- it, which read as a broken floating statue.
	do
		local checkHum = CombatHelper.getHumanoid(character)
		local checkState = checkHum and checkHum:GetState()
		if
			checkState == Enum.HumanoidStateType.Freefall
			or checkState == Enum.HumanoidStateType.Jumping
			or (checkHum and checkHum.FloorMaterial == Enum.Material.Air)
		then
			return
		end
	end
	local entry = CharacterRegistry.getAbilityById("jean_grey", "astral_projection")
	if not entry then
		return
	end
	if borrowedAs then
		if not CharacterService.spendEnergy(character, GameConstants.MG_ASTRAL_ENERGY) then
			return
		end
	elseif not canUse(character, entry.id, GameConstants.MG_ASTRAL_ENERGY) then
		return
	end
	local abilityId = borrowedAs or entry.id
	-- Shield can stay up; astral still drains energy from the body

	local root = getRoot(character)
	local hum = CombatHelper.getHumanoid(character)
	if not root or not hum then
		return
	end

	AbilityCooldownHelper.setActive(character, abilityId, true)
	if not borrowedAs then
		beginPowerFx(character)
	end

	local ok, clone = pcall(function()
		local was = character.Archivable
		character.Archivable = true
		local c = character:Clone()
		character.Archivable = was
		return c
	end)
	if not ok or not clone or not clone:IsA("Model") then
		finishAbility(character, abilityId, 1)
		endPowerFx(character)
		return
	end

	clone.Name = "MarvelGirlAstral_" .. tostring(player.UserId)
	clone:SetAttribute(GameConstants.MG_ASTRAL_ATTRIBUTE, true)
	clone:SetAttribute(GameConstants.HERO_ATTRIBUTE, nil) -- not a playable hero body
	clone:SetAttribute(GameConstants.IS_FLYING_ATTRIBUTE, true)
	clone:SetAttribute(GameConstants.FLIGHT_ALPHA_ATTRIBUTE, 0)
	clone:SetAttribute(GameConstants.FLIGHT_BANK_ATTRIBUTE, 0)
	clone:SetAttribute(GameConstants.FLIGHT_SIDE_ATTRIBUTE, 0)
	stripCloneAnimators(clone)
	local fadeParts: { { part: BasePart, target: number } } = {}
	for _, desc in clone:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.CanCollide = false
			-- Attackable now (raycasts/AoE queries need CanQuery to land a
			-- hit) - she still noclips through the world since CanCollide
			-- stays false.
			desc.CanQuery = true
			desc.CanTouch = false
			desc.Massless = true
			if desc.Name ~= "HumanoidRootPart" then
				-- Unused hair meshes stay fully invisible so they don't ghost over the other style
				if desc.Transparency >= 0.95 then
					desc.Transparency = 1
				else
					local targetT = math.clamp(desc.Transparency + 0.28, 0, 0.82)
					table.insert(fadeParts, { part = desc, target = targetT })
					desc.Transparency = 1
				end
			else
				desc.Transparency = 1
				desc.Anchored = false
			end
		elseif
			desc:IsA("ParticleEmitter")
			or desc:IsA("Trail")
			or desc:IsA("Beam")
			or desc:IsA("Fire")
			or desc:IsA("Smoke")
			or desc:IsA("Sparkles")
		then
			desc:Destroy()
		elseif desc:IsA("PointLight") or desc:IsA("SpotLight") or desc:IsA("SurfaceLight") then
			desc:Destroy()
		elseif desc:IsA("BillboardGui") or desc:IsA("Highlight") then
			desc:Destroy()
		elseif desc:IsA("Attachment") then
			local n = desc.Name
			if
				n == "HandAttachment"
				or n == "HeadAttachment"
				or n == "MentalPower"
				or n == "PsionicBlastAttachment"
				or n == "HandVFXLeftAttachment"
				or n == "HandVFXRightAttachment"
			then
				desc:Destroy()
			end
		end
	end

	local astralFx: { Instance } = {}
	local highlightTemplate = if borrowedAs then nil else VfxHelper.getMarvelGirlAsset("AstralProjection", "Highlight")
	local highlightInst: Highlight? = nil
	if highlightTemplate then
		if highlightTemplate:IsA("Highlight") then
			highlightInst = highlightTemplate
		else
			local nested = highlightTemplate:FindFirstChildWhichIsA("Highlight", true)
			if nested then
				highlightInst = nested
			end
		end
	end
	if highlightInst then
		local outline = highlightInst:Clone()
		outline.Name = "MgAstralOutline"
		local accent = jeanAccent(character)
		outline.FillColor = accent
		outline.OutlineColor = accent
		outline.Adornee = clone
		outline.Parent = clone
		table.insert(astralFx, outline)
	elseif borrowedAs then
		-- Madison: no outline and no particles, only a grey fill on the figure itself.
		local inner = Instance.new("Highlight")
		inner.Name = "MgAstralOutline"
		inner.FillColor = Color3.fromRGB(176, 178, 186)
		inner.FillTransparency = 0.5
		inner.OutlineTransparency = 1
		inner.DepthMode = Enum.HighlightDepthMode.Occluded
		inner.Adornee = clone
		inner.Parent = clone
		table.insert(astralFx, inner)
	else
		local outline = Instance.new("Highlight")
		outline.Name = "MgAstralOutline"
		local accent = jeanAccent(character)
		outline.FillColor = accent
		outline.FillTransparency = 0.92
		outline.OutlineTransparency = 0
		outline.OutlineColor = accent
		outline.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		outline.Adornee = clone
		outline.Parent = clone
		table.insert(astralFx, outline)
	end

	local pe1 = if borrowedAs then nil else VfxHelper.getMarvelGirlAsset("AstralProjection", "ParticleEmitter1")
	local pe2 = if borrowedAs then nil else VfxHelper.getMarvelGirlAsset("AstralProjection", "ParticleEmitter2")
	for _, part in getDirectBodyParts(clone) do
		if pe1 then
			local fx = attachCloneToPart(pe1, part)
			if fx then
				styleJeanFx(fx, nil, character)
				table.insert(astralFx, fx)
			end
		end
		if pe2 then
			local fx = attachCloneToPart(pe2, part)
			if fx then
				styleJeanFx(fx, nil, character)
				table.insert(astralFx, fx)
			end
		end
	end

	local astralRoot = clone:FindFirstChild("HumanoidRootPart") :: BasePart?
	local astralHum = clone:FindFirstChildOfClass("Humanoid")
	if not astralRoot or not astralHum then
		clone:Destroy()
		finishAbility(character, abilityId, 1)
		endPowerFx(character)
		return
	end

	local freshAnimator = Instance.new("Animator")
	freshAnimator.Parent = astralHum

	astralHum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	astralHum.MaxHealth = hum.MaxHealth
	astralHum.Health = hum.Health
	astralHum.PlatformStand = true
	astralHum.AutoRotate = false
	clone:PivotTo(root.CFrame)
	clone.Parent = Workspace
	forceAstralNoclip(clone)
	clone.DescendantAdded:Connect(function(desc)
		-- Used to call forceAstralNoclip(clone) here - a FULL
		-- GetDescendants() rescan of the whole clone - on every single new
		-- part. Accessories/hair/attachments can add several parts each in
		-- quick succession while the clone finishes loading, turning what
		-- should be O(1) per part into O(n) per part (O(n^2) overall) - with
		-- enough parts that's real, compounding server-side cost right at
		-- astral cast. Strip just the newly-added part directly instead.
		if desc:IsA("BasePart") then
			desc.CanCollide = false
			desc.CanQuery = false
			desc.CanTouch = false
			desc.Massless = true
		end
	end)
	astralHum.HipHeight = 0
	pcall(function()
		(astralHum :: any).EvaluateStateMachine = false
	end)
	pcall(function()
		for _, desc in clone:GetDescendants() do
			if desc:IsA("BasePart") then
				desc:SetNetworkOwner(player)
			end
		end
	end)

	-- Smooth fade-in at the body's position
	local appearInfo = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, entry in fadeParts do
		if entry.part.Parent then
			TweenService:Create(entry.part, appearInfo, { Transparency = entry.target }):Play()
		end
	end
	for _, fx in astralFx do
		if fx:IsA("Highlight") then
			local startFill = fx.FillTransparency
			local startOutline = fx.OutlineTransparency
			fx.FillTransparency = 1
			fx.OutlineTransparency = 1
			TweenService:Create(fx, appearInfo, {
				FillTransparency = startFill,
				OutlineTransparency = startOutline,
			}):Play()
		end
	end

	ConstraintHelper.lockHumanoidForAbility(astralHum)
	local mover = ConstraintHelper.createMover(astralRoot, true, true)
	pcall(function()
		astralRoot:SetNetworkOwner(player)
	end)

	character:SetAttribute(GameConstants.MG_ASTRAL_BODY_ATTRIBUTE, true)
	character:SetAttribute(
		GameConstants.MG_ASTRAL_END_AT_ATTRIBUTE,
		AbilityCooldownHelper.getNow() + GameConstants.MG_ASTRAL_DURATION
	)
	NameplateService.setHidden(character, true, 0.12)
	NameplateService.setHidden(clone, true, 0)
	freezeBodyInPlace(player, character)
	local bodyAnimTrack = startAstralBodyAnim(character)

	local lastBodyHp = hum.Health
	local healthConn = hum.HealthChanged:Connect(function(hp)
		if astralHum.Parent then
			astralHum.Health = hp
		end
		lastBodyHp = hp
		if hp <= 0 then
			endAstral(player, true, true)
		end
	end)

	astralHum.HealthChanged:Connect(function(hp)
		if hp < lastBodyHp and CombatHelper.isCombatEligible(character) then
			local damage = lastBodyHp - hp
			hum:TakeDamage(damage * 0.5)
			lastBodyHp = hum.Health
			astralHum.Health = lastBodyHp
		end
	end)

	astralByPlayer[player] = {
		character = character,
		body = character,
		astral = clone,
		root = astralRoot,
		humanoid = astralHum,
		mover = mover,
		moveDir = Vector3.zero,
		lookDir = astralRoot.CFrame.LookVector,
		sideInput = 0,
		currentVel = Vector3.zero,
		startedAt = os.clock(),
		returning = false,
		healthConn = healthConn,
		fx = astralFx,
		outbursting = false,
		keepHighlightUntilNear = false,
		outburstHoldCf = nil,
		loopSound = playLoopingAttachedSound(astralRoot, GameConstants.MG_ASTRAL_LOOP_SOUND, 0.85),
		bodyAnimTrack = bodyAnimTrack,
		abilityId = abilityId,
	}

	Remotes.getEvent("MindLink"):FireClient(player, {
		phase = "astral_start",
		astralName = clone.Name,
	})
end

-- Madison's Descensum: the same projection, under her own ability id (her service does the gating).
function MarvelGirlService.startBorrowedAstral(player: Player, abilityId: string): boolean
	if astralByPlayer[player] then
		return false
	end
	startAstral(player, abilityId)
	return astralByPlayer[player] ~= nil
end

function MarvelGirlService.endBorrowedAstral(player: Player)
	if astralByPlayer[player] then
		endAstral(player, true)
	end
end

function MarvelGirlService.hasAstral(player: Player): boolean
	return astralByPlayer[player] ~= nil
end

function MarvelGirlService.setAstralInput(player: Player, moveDir: Vector3, lookDir: Vector3, sideInput: number?)
	local state = astralByPlayer[player]
	if not state or state.returning or state.outbursting then
		return
	end
	if painByPlayer[player] then
		state.moveDir = Vector3.zero
		state.sideInput = 0
		local look = state.body:GetAttribute(GameConstants.MG_PAIN_LOOK_ATTRIBUTE)
		if typeof(look) == "Vector3" then
			local to = look - state.root.Position
			if to.Magnitude > 0.05 then
				state.lookDir = to.Unit
			end
		end
		return
	end
	state.moveDir = moveDir
	state.lookDir = lookDir
	state.sideInput = sideInput or 0
end

----------------------------------------------------------------
-- Mind Link
----------------------------------------------------------------
local function collectAttachments(root: Instance): { Attachment }
	local list: { Attachment } = {}
	if root:IsA("Attachment") then
		table.insert(list, root)
	end
	for _, desc in root:GetDescendants() do
		if desc:IsA("Attachment") then
			table.insert(list, desc)
		end
	end
	return list
end

local function attachMindLinkAsset(template: Instance, hostPart: BasePart, name: string): (Instance, { Attachment })
	local clone = template:Clone()
	clone.Name = name
	clone:SetAttribute("MgMindLinkFx", true)
	if clone:IsA("Attachment") then
		clone.Parent = hostPart
		return clone, collectAttachments(clone)
	end
	if clone:IsA("BasePart") then
		clone.Anchored = false
		clone.CanCollide = false
		clone.CanQuery = false
		clone.CanTouch = false
		clone.Massless = true
		clone.CFrame = hostPart.CFrame
		clone.Parent = hostPart.Parent or hostPart
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = hostPart
		weld.Part1 = clone
		weld.Parent = clone
		return clone, collectAttachments(clone)
	end
	if clone:IsA("Model") then
		local primary = clone.PrimaryPart or clone:FindFirstChildWhichIsA("BasePart", true)
		if primary then
			clone.Parent = hostPart.Parent or hostPart
			clone:PivotTo(hostPart.CFrame)
			for _, desc in clone:GetDescendants() do
				if desc:IsA("BasePart") then
					desc.Anchored = false
					desc.CanCollide = false
					desc.CanQuery = false
					desc.CanTouch = false
					desc.Massless = true
				end
			end
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = hostPart
			weld.Part1 = primary
			weld.Parent = primary
			return clone, collectAttachments(clone)
		end
	end
	clone.Parent = hostPart
	local atts = collectAttachments(clone)
	for _, att in atts do
		local parent = att.Parent
		if not (parent and (parent:IsA("BasePart") or parent:IsA("Bone") or parent:IsA("Attachment"))) then
			att.Parent = hostPart
		end
	end
	return clone, atts
end

local function getMindLinkHostPart(model: Instance): BasePart?
	if model:IsA("BasePart") then
		return model
	end
	if model:IsA("Model") then
		local head = model:FindFirstChild("Head")
		if head and head:IsA("BasePart") then
			return head
		end
		return getRoot(model)
	end
	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function beamParentAttachments(atts: { Attachment }): { Attachment }
	local parents: { Attachment } = {}
	for _, att in atts do
		local hasBeam = false
		for _, desc in att:GetDescendants() do
			if desc:IsA("Beam") then
				hasBeam = true
				break
			end
		end
		if hasBeam then
			table.insert(parents, att)
		end
	end
	if #parents > 0 then
		return parents
	end
	return atts
end

local function clearMindLinkVfx(state: MindLinkState)
	for _, beam in state.activeBeams do
		if beam.Parent then
			beam:Destroy()
		end
	end
	table.clear(state.activeBeams)
	for _, inst in state.targetFx do
		if inst.Parent then
			inst:Destroy()
		end
	end
	table.clear(state.targetFx)
	for _, att in state.jeanAtts do
		if att.Parent then
			att:Destroy()
		end
	end
	table.clear(state.jeanAtts)
	table.clear(state.beamTemplates)
	if state.jeanFx and state.jeanFx.Parent then
		state.jeanFx:Destroy()
	end
	state.jeanFx = nil
end

--[[ Retract active beams back to Jean's attachments, then fade everything out. ]]
local function retractAndClearMindLinkVfx(state: MindLinkState, smooth: boolean?)
	if not smooth then
		clearMindLinkVfx(state)
		return
	end

	local retractHosts: { BasePart } = {}
	local beams = table.clone(state.activeBeams)
	table.clear(state.activeBeams)

	for _, beam in beams do
		if not beam.Parent then
			continue
		end
		local a0 = beam.Attachment0
		local a1 = beam.Attachment1
		if not a0 or not a1 then
			beam:Destroy()
			continue
		end
		local host = makeFxHost("MgMindLinkRetract", a1.WorldCFrame)
		table.insert(retractHosts, host)
		local retractAtt = Instance.new("Attachment")
		retractAtt.Name = "MgMindLinkRetractAtt"
		retractAtt.Parent = host
		beam.Attachment1 = retractAtt

		local startCf = a1.WorldCFrame
		local endCf = a0.WorldCFrame
		task.spawn(function()
			local dur = 0.4
			local t0 = os.clock()
			while os.clock() - t0 < dur do
				if not host.Parent or not beam.Parent then
					break
				end
				local a = math.clamp((os.clock() - t0) / dur, 0, 1)
				local s = a * a * (3 - 2 * a)
				host.CFrame = startCf:Lerp(endCf, s)
				beam.Width0 = beam.Width0 * (1 - s * 0.15)
				beam.Width1 = beam.Width1 * (1 - s * 0.15)
				task.wait()
			end
			if beam.Parent then
				beam.Enabled = false
				beam:Destroy()
			end
		end)
	end

	task.delay(0.45, function()
		for _, host in retractHosts do
			if host.Parent then
				host:Destroy()
			end
		end
		for _, inst in state.targetFx do
			if inst.Parent then
				retireFx(inst, 0.35, 1.2)
			end
		end
		table.clear(state.targetFx)
		for _, att in state.jeanAtts do
			if att.Parent then
				retireFx(att, 0.35, 1.2)
			end
		end
		table.clear(state.jeanAtts)
		table.clear(state.beamTemplates)
		if state.jeanFx and state.jeanFx.Parent then
			retireFx(state.jeanFx, 0.35, 1.2)
		end
		state.jeanFx = nil
	end)
end

local function ensureMindLinkJean(state: MindLinkState)
	if state.jeanFx and state.jeanFx.Parent then
		return
	end
	local template = VfxHelper.getMarvelGirlAsset("MindLink", "MindLinkJean")
	if not template then
		warn("[MarvelGirl] Missing Assets.JeanGrey.MindLink.MindLinkJean")
		return
	end
	local head = getHead(state.character)
	if not head then
		return
	end
	local fx, atts = attachMindLinkAsset(template, head, "MgMindLinkJean")
	if fx then
		styleJeanFx(fx, nil, state.character)
	end
	state.jeanFx = fx
	state.jeanAtts = beamParentAttachments(atts)
	table.clear(state.beamTemplates)
	for _, att in state.jeanAtts do
		for _, desc in att:GetDescendants() do
			if desc:IsA("Beam") then
				desc.Enabled = false
				table.insert(state.beamTemplates, desc)
			end
		end
	end
end

local function addMindLinkTargetVfx(state: MindLinkState, host: Instance)
	ensureMindLinkJean(state)
	if #state.jeanAtts == 0 or #state.beamTemplates == 0 then
		return
	end
	local part = getMindLinkHostPart(host)
	if not part then
		return
	end
	local template = VfxHelper.getMarvelGirlAsset("MindLink", "MindLinkTarget")
	if not template then
		warn("[MarvelGirl] Missing Assets.JeanGrey.MindLink.MindLinkTarget")
		return
	end
	local fx, atts = attachMindLinkAsset(template, part, "MgMindLinkTarget")
	if fx then
		styleJeanFx(fx, nil, state.character)
	end
	table.insert(state.targetFx, fx)
	local targetAtt = atts[1]
	if not targetAtt then
		return
	end
	for _, beamTemplate in state.beamTemplates do
		local parentAtt = beamTemplate.Parent
		if parentAtt and parentAtt:IsA("Attachment") then
			local beam = beamTemplate:Clone()
			beam.Enabled = true
			beam.Color = ColorSequence.new(jeanAccent(state.character))
			beam.Attachment0 = parentAtt
			beam.Attachment1 = targetAtt
			beam.Parent = parentAtt
			table.insert(state.activeBeams, beam)
		end
	end
end

local function fireMindLink(members: { Model }, payload: { [string]: any })
	local ev = Remotes.getEvent("MindLink")
	for _, model in members do
		local plr = Players:GetPlayerFromCharacter(model)
		if plr then
			ev:FireClient(plr, payload)
		end
	end
end

local function bindMindLinkDamageShare(state: MindLinkState)
	if state.healthConn then
		state.healthConn:Disconnect()
		state.healthConn = nil
	end
	local jean = state.character
	local hum = CombatHelper.getHumanoid(jean)
	if not hum then
		return
	end
	state.lastHealth = hum.Health
	state.spreading = false
	state.healthConn = hum.HealthChanged:Connect(function(hp)
		if state.spreading then
			state.lastHealth = hp
			return
		end
		local prev = state.lastHealth
		if hp >= prev - 0.05 then
			state.lastHealth = hp
			return
		end
		if jean:GetAttribute(GameConstants.SHIELD_ACTIVE_ATTRIBUTE) == true
			or jean:GetAttribute(GameConstants.MG_BARRIER_ATTRIBUTE) == true
			or not CombatHelper.isCombatEligible(jean)
		then
			state.lastHealth = hp
			return
		end

		local lost = prev - hp
		local shares: { Model } = { jean }
		for _, model in state.members do
			if model ~= jean and model.Parent then
				local otherHum = CombatHelper.getHumanoid(model)
				if otherHum and otherHum.Health > 0 and CombatHelper.isCombatEligible(model) then
					table.insert(shares, model)
				end
			end
		end
		local n = #shares
		if n <= 1 then
			state.lastHealth = hp
			return
		end

		local jeanShare = lost / n
		state.spreading = true
		if hum.Parent then
			hum.Health = math.max(0, prev - jeanShare)
		end
		for i = 2, n do
			local other = shares[i]
			local otherHum = CombatHelper.getHumanoid(other)
			if otherHum and otherHum.Parent and otherHum.Health > 0 then
				otherHum:TakeDamage(jeanShare)
				CombatHelper.markInCombat(other)
			end
		end
		state.spreading = false
		state.lastHealth = if hum.Parent then hum.Health else hp
	end)
end

local function endMindLink(player: Player, applyCooldown: boolean?, smooth: boolean?)
	local state = mindLinkByPlayer[player]
	if not state then
		return
	end
	mindLinkByPlayer[player] = nil
	if state.healthConn then
		state.healthConn:Disconnect()
		state.healthConn = nil
	end
	retractAndClearMindLinkVfx(state, smooth == true)
	for _, model in state.members do
		if model.Parent then
			model:SetAttribute(GameConstants.MG_MIND_LINK_ATTRIBUTE, nil)
		end
	end
	fireMindLink(state.members, {
		phase = if smooth then "end_smooth" else "end",
	})
	if state.character.Parent then
		AbilityCooldownHelper.setActive(state.character, "mind_link", false)
		if applyCooldown then
			AbilityCooldownHelper.applyAfterUse(state.character, "mind_link", GameConstants.MG_MIND_LINK_COOLDOWN)
			CharacterService.markAbilityUse(state.character)
		end
	end
end

local function memberNames(state: MindLinkState): { string }
	local names = {}
	for _, model in state.members do
		local plr = Players:GetPlayerFromCharacter(model)
		table.insert(names, if plr then plr.DisplayName else model.Name)
	end
	if state.linkerIncluded then
		table.insert(names, "MindLinker")
	end
	return names
end

local function broadcastMembers(state: MindLinkState)
	fireMindLink(state.members, {
		phase = "members",
		members = memberNames(state),
	})
end

--[[
	Drop a dead/gone member from the link. VFX is tracked as flat lists
	(not per-member), so the safe way to remove just one member's beam is a
	full teardown + rebuild for whoever's left, including Jean's own anchor.
]]
local function removeMindLinkMember(state: MindLinkState, model: Model)
	local idx: number? = nil
	for i, m in state.members do
		if m == model then
			idx = i
			break
		end
	end
	if not idx then
		return
	end
	table.remove(state.members, idx)
	if model.Parent then
		model:SetAttribute(GameConstants.MG_MIND_LINK_ATTRIBUTE, nil)
	end
	local plr = Players:GetPlayerFromCharacter(model)
	if plr then
		Remotes.getEvent("MindLink"):FireClient(plr, { phase = "astral_end" })
	end
	retractAndClearMindLinkVfx(state, false)
	ensureMindLinkJean(state)
	for _, member in state.members do
		if member ~= state.character and member.Parent then
			addMindLinkTargetVfx(state, member)
		end
	end
	if state.linkerIncluded then
		local linker = Workspace:FindFirstChild("MindLinker")
		if linker then
			addMindLinkTargetVfx(state, linker)
		end
	end
	broadcastMembers(state)
end

local function addMindLinkMember(player: Player, target: Model?): boolean
	local state = mindLinkByPlayer[player]
	if not state then
		return false
	end
	local now = os.clock()
	if (mindLinkAddCd[player] or 0) > now then
		return false
	end

	-- Manual add: character target OR MindLinker part aimed
	local addedName: string? = nil
	if target and target.Parent and target ~= state.character then
		local already = false
		for _, m in state.members do
			if m == target then
				already = true
				break
			end
		end
		local otherCount = #state.members - 1 + (if state.linkerIncluded then 1 else 0)
		if not already and otherCount < GameConstants.MG_MIND_LINK_MAX then
			local hum = CombatHelper.getHumanoid(target)
			if hum and hum.Health > 0 and CombatHelper.isCombatEligible(target) then
				table.insert(state.members, target)
				target:SetAttribute(GameConstants.MG_MIND_LINK_ATTRIBUTE, true)
				local plr = Players:GetPlayerFromCharacter(target)
				addedName = if plr then plr.DisplayName else target.Name
				-- Notify new member with full chat open
				if plr then
					Remotes.getEvent("MindLink"):FireClient(plr, {
						phase = "start",
						host = player.DisplayName,
						members = memberNames(state),
						isHost = false,
					})
				end
			end
		end
	end

	-- Aiming MindLinker in workspace counts as adding the test node
	if not addedName then
		local linker = Workspace:FindFirstChild("MindLinker")
		if linker and not state.linkerIncluded then
			local otherCount = #state.members - 1
			if otherCount < GameConstants.MG_MIND_LINK_MAX then
				state.linkerIncluded = true
				addedName = "MindLinker"
			end
		end
	end

	if not addedName then
		return false
	end

	mindLinkAddCd[player] = now + GameConstants.MG_MIND_LINK_ADD_COOLDOWN
	if addedName ~= "MindLinker" then
		fireCameraShake(player, 0.22, 0.32, 0.2, 0.35)
		if target then
			local other = Players:GetPlayerFromCharacter(target)
			if other then
				fireCameraShake(other, 0.22, 0.32, 0.2, 0.35)
			end
		end
	end
	if addedName == "MindLinker" then
		local linker = Workspace:FindFirstChild("MindLinker")
		if linker then
			addMindLinkTargetVfx(state, linker)
		end
	elseif target then
		addMindLinkTargetVfx(state, target)
	end
	broadcastMembers(state)
	return true
end

local function startMindLink(player: Player, target: Model?)
	local character = player.Character
	if not character then
		return
	end
	-- G while active only adds (never closes — Jean uses chat X)
	if mindLinkByPlayer[player] then
		if target then
			addMindLinkMember(player, target)
		end
		return
	end
	local entry = CharacterRegistry.getAbilityById("jean_grey", "mind_link")
	if not entry or not canUse(character, entry.id, GameConstants.MG_MIND_LINK_START_ENERGY) then
		return
	end

	AbilityCooldownHelper.setActive(character, entry.id, true)
	-- No attachPowerFx for mind link
	character:SetAttribute(GameConstants.MG_MIND_LINK_ATTRIBUTE, true)

	local state: MindLinkState = {
		character = character,
		members = { character },
		startedAt = os.clock(),
		token = os.clock(),
		linkerIncluded = false,
		jeanFx = nil,
		jeanAtts = {},
		beamTemplates = {},
		activeBeams = {},
		targetFx = {},
		healthConn = nil,
		lastHealth = 0,
		spreading = false,
	}
	mindLinkByPlayer[player] = state
	mindLinkAddCd[player] = 0
	bindMindLinkDamageShare(state)
	ensureMindLinkJean(state)

	fireMindLink(state.members, {
		phase = "start",
		host = player.DisplayName,
		members = memberNames(state),
		isHost = true,
	})

	if target then
		addMindLinkMember(player, target)
	end
end

local function broadcastMindMessage(player: Player, text: string)
	local state = mindLinkByPlayer[player]
	-- Also allow linked non-Jean members to speak: find any link containing them
	if not state then
		for _, link in mindLinkByPlayer do
			for _, model in link.members do
				if Players:GetPlayerFromCharacter(model) == player then
					state = link
					break
				end
			end
			if state then
				break
			end
		end
	end
	if not state then
		return
	end
	local now = os.clock()
	if (mindLinkMsgCd[player] or 0) > now then
		return
	end
	mindLinkMsgCd[player] = now + GameConstants.MG_MIND_LINK_MSG_COOLDOWN
	local clean = string.sub(tostring(text), 1, 120)
	if clean == "" then
		return
	end
	-- Same content filter as ordinary chat (Roblox's TextService), since
	-- Mind Link is a custom broadcast path that bypasses TextChatService's
	-- own automatic filtering entirely - unfiltered raw text was going
	-- straight to every linked member's client.
	local filtered = clean
	local ok, result = pcall(function()
		return TextService:FilterStringAsync(clean, player.UserId)
	end)
	if ok and result then
		local okBroadcast, broadcastText = pcall(function()
			return result:GetNonChatStringForBroadcastAsync()
		end)
		if okBroadcast and type(broadcastText) == "string" then
			filtered = broadcastText
		end
	end
	if filtered == "" then
		return
	end
	fireMindLink(state.members, {
		phase = "message",
		from = player.DisplayName,
		text = filtered,
	})
	-- MindLinker echo for testing
	local linker = Workspace:FindFirstChild("MindLinker")
	if linker and state.character == (Players:GetPlayerFromCharacter(state.character) and state.character) then
		-- no-op visual; host already in chat
	end
end

----------------------------------------------------------------
-- Telekinetic Combo (caster/target animations: lift, sweep, push away, ragdoll)
----------------------------------------------------------------
local function setSlamOwnership(model: Model): { BasePart }
	local parts: { BasePart } = {}
	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") then
			table.insert(parts, desc)
			pcall(function()
				desc:SetNetworkOwner(nil)
			end)
		end
	end
	return parts
end

local function restoreSlamOwnership(model: Model, parts: { BasePart })
	local plr = Players:GetPlayerFromCharacter(model)
	for _, part in parts do
		if part.Parent then
			pcall(function()
				if plr then
					part:SetNetworkOwner(plr)
				else
					part:SetNetworkOwnershipAuto()
				end
			end)
		end
	end
end

local function attachSlamAttachment(parentPart: BasePart, assetName: string, offset: Vector3?, caster: Model?): Instance?
	local template = VfxHelper.getMarvelGirlAsset("TelekineticSlam", assetName)
	if not template then
		warn("[MarvelGirl] Missing Assets.JeanGrey.TelekineticSlam." .. assetName)
		return nil
	end
	local fx = template:Clone()
	if fx:IsA("Attachment") then
		fx.Position = offset or Vector3.zero
		fx.Orientation = Vector3.zero
	end
	fx.Parent = parentPart
	styleJeanFx(fx, nil, caster)
	VfxHelper.setParticlesEnabled(fx, true)
	VfxHelper.emitAllParticles(fx, 10)
	return fx
end

local function clearSlamFx(fxList: { Instance })
	for _, fx in fxList do
		if fx.Parent then
			VfxHelper.setParticlesEnabled(fx, false)
			task.delay(2.5, function()
				if fx.Parent then
					fx:Destroy()
				end
			end)
		end
	end
end

local function playSlamAnim(character: Model, animId: string): AnimationTrack?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	local track = AnimationLoadHelper.load(animator :: Animator, animId, "MarvelGirl combo anim:" .. animId .. ":" .. character.Name)
	if not track then
		return nil
	end
	track.Priority = Enum.AnimationPriority.Action4
	track.Looped = false
	track:Play(0.05, 1, 1)
	return track
end

local function applySlamCasterLock(character: Model)
	local root = getRoot(character)
	local hum = CombatHelper.getHumanoid(character)
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
	if hum then
		hum.WalkSpeed = 0
		hum.AutoRotate = false
		if hum.UseJumpPower then
			hum.JumpPower = 0
		else
			hum.JumpHeight = 0
		end
		hum:Move(Vector3.zero, false)
	end
	character:SetAttribute(GameConstants.BUSY_ATTRIBUTE, true)
end

local function lockSlamCaster(player: Player, character: Model)
	local root = getRoot(character)
	local hum = CombatHelper.getHumanoid(character)
	if not root or not hum then
		return
	end
	local animate = character:FindFirstChild("Animate")
	local animateWasDisabled = false
	if animate and animate:IsA("Script") then
		animateWasDisabled = animate.Disabled
		animate.Disabled = true
	end
	slamCasterHoldByPlayer[player] = {
		anchored = root.Anchored,
		walk = hum.WalkSpeed,
		jumpPower = if hum.UseJumpPower then hum.JumpPower else nil,
		jumpHeight = if not hum.UseJumpPower then hum.JumpHeight else nil,
		autoRotate = hum.AutoRotate,
		ownedParts = setPullServerOwnership(character),
		animateWasDisabled = animateWasDisabled,
	}
	applySlamCasterLock(character)
end

local function unlockSlamCaster(player: Player, character: Model?)
	local hold = slamCasterHoldByPlayer[player]
	slamCasterHoldByPlayer[player] = nil
	if not hold or not character then
		return
	end
	local root = getRoot(character)
	local hum = CombatHelper.getHumanoid(character)
	if root then
		root.Anchored = hold.anchored
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
	restorePullOwnership(character, hold.ownedParts)
	local animate = character:FindFirstChild("Animate")
	if animate and animate:IsA("Script") then
		animate.Disabled = hold.animateWasDisabled == true
	end
	if character:GetAttribute(GameConstants.BUSY_ATTRIBUTE) == true then
		character:SetAttribute(GameConstants.BUSY_ATTRIBUTE, nil)
	end
	CastFaceHelper.cancelPending(character)
	CastFaceHelper.destroyHold(character)
	if hum and hum.Parent then
		hum.WalkSpeed = hold.walk
		hum.AutoRotate = hold.autoRotate
		if hold.jumpPower ~= nil then
			hum.JumpPower = hold.jumpPower
		end
		if hold.jumpHeight ~= nil then
			hum.JumpHeight = hold.jumpHeight
		end
	end
end

local function endSlam(player: Player, applyCooldown: boolean?, throw: boolean?)
	local state = slamByPlayer[player]
	if not state then
		return
	end
	slamByPlayer[player] = nil
	state.token += 1
	-- Flame Combo (castFlameCombo) watches slamByPlayer clearing to know when
	-- to mirror telekinetic_slam's cooldown onto flame_combo, but can't tell
	-- *why* it cleared - record it as an Attribute so an interrupted slam
	-- (applyCooldown=false, from cancelAll) doesn't still put flame_combo on
	-- cooldown.
	if state.character then
		state.character:SetAttribute("MgLastSlamApplyCooldown", applyCooldown == true)
	end

	if state.faceConn then
		state.faceConn:Disconnect()
		state.faceConn = nil
	end
	if state.faceAlign then
		state.faceAlign:Destroy()
		state.faceAlign = nil
	end
	if state.faceAtt then
		state.faceAtt:Destroy()
		state.faceAtt = nil
	end
	-- Timed (non-looped) combo tracks are left to finish on a normal ending;
	-- only an interrupted combo (throw=false) cuts them.
	if not throw then
		if state.animTrack then
			state.animTrack:Stop(0)
		end
		if state.victimTrack then
			state.victimTrack:Stop(0.1)
		end
	end
	state.animTrack = nil
	state.victimTrack = nil
	unlockSlamCaster(player, state.character)

	if state.slam2Host then
		retireFx(state.slam2Host, 0.55, 3.5)
		state.slam2Host = nil
	end
	clearSlamFx(state.fx)
	if state.burnVfx then
		Phoenix.endBurnVfx(state.victim)
	end
	if state.character.Parent then
		endPowerFx(state.character)
		if MarvelGirlService.lookOf(state.character) == "marvel_girl" then
			Phoenix.removeMarvelGirlFlightEyes(state.character)
		end
	end

	local victim = state.victim
	if victim.Parent then
		victim:SetAttribute(GameConstants.MG_SLAM_HELD_ATTRIBUTE, nil)
		setVictimControlled(victim, false)
		if state.vRoot.Parent then
			state.vRoot.Anchored = false
		end
		local vHum = CombatHelper.getHumanoid(victim)
		if vHum then
			vHum.AutoRotate = state.victimAutoRotate
			vHum.PlatformStand = false
		end
		if throw and state.vRoot.Parent then
			if not CombatHelper.isShielded(victim) then
				RagdollService.applyTimed(victim, GameConstants.MG_SLAM_RAGDOLL_TIME)
			end
		elseif victim:GetAttribute(GameConstants.RAGDOLLED_ATTRIBUTE) == true then
			if not CombatHelper.isShielded(victim) then
				RagdollService.applyTimed(victim, math.min(1.2, GameConstants.MG_SLAM_RAGDOLL_TIME))
			end
		end
		restoreSlamOwnership(victim, state.ownedParts)
	end

	if state.character.Parent then
		AbilityCooldownHelper.setActive(state.character, "telekinetic_slam", false)
		if applyCooldown then
			AbilityCooldownHelper.applyAfterUse(state.character, "telekinetic_slam", GameConstants.MG_SLAM_COOLDOWN)
			CharacterService.markAbilityUse(state.character)
		end
	end
end

local function castTelekineticSlam(player: Player, target: Model?, direction: Vector3?, aimPoint: Vector3?, lockOn: boolean?, damageMult: number?)
	local character = player.Character
	if not character or slamByPlayer[player] then
		return
	end
	if character:GetAttribute(GameConstants.IS_FLYING_ATTRIBUTE) == true then
		return
	end
	local entry = CharacterRegistry.getAbilityById("jean_grey", "telekinetic_slam")
	if not entry then
		return
	end
	-- Pre-checks without spending energy yet
	if CombatHelper.arePowersDisabled(character) then
		return
	end
	if character:GetAttribute(GameConstants.BUSY_ATTRIBUTE) == true then
		return
	end
	if character:GetAttribute(GameConstants.MG_ASTRAL_BODY_ATTRIBUTE) == true then
		return
	end
	if AbilityCooldownHelper.isOnCooldown(character, entry.id) or AbilityCooldownHelper.isActive(character, entry.id) then
		return
	end

	local jeanRoot = getRoot(character)
	if not jeanRoot then
		return
	end

	local victim = resolveSingleTkTarget(
		character,
		jeanRoot,
		target,
		direction,
		aimPoint,
		GameConstants.MG_SLAM_RANGE,
		lockOn
	)
	if not victim or victim == character then
		return
	end
	local vRoot = getRoot(victim)
	local vHum = CombatHelper.getHumanoid(victim)
	if not vRoot or not vHum or vHum.Health <= 0 or vRoot.Anchored then
		return
	end
	if (vRoot.Position - jeanRoot.Position).Magnitude > GameConstants.MG_SLAM_RANGE then
		return
	end
	if CombatHelper.isShielded(victim) then
		return
	end
	-- A ragdolled target can't hold the slam animation (it never plays once they get up), so don't start it.
	if victim:GetAttribute(GameConstants.RAGDOLLED_ATTRIBUTE) == true then
		return
	end
	if not canUse(character, entry.id, GameConstants.MG_SLAM_ENERGY) then
		return
	end

	AbilityCooldownHelper.setActive(character, entry.id, true)
	beginPowerFx(character)
	if MarvelGirlService.lookOf(character) == "marvel_girl" then
		Phoenix.attachMarvelGirlFlightEyes(character)
	end
	lockSlamCaster(player, character)

	-- No smoothFaceToward snapshot here: the per-frame MgSlamFaceAlign set up
	-- a bit further down (state.faceConn, live-tracks vRoot every heartbeat)
	-- already owns facing for the whole slam. A one-shot snapshot toward
	-- vRoot's pre-slam position used to run alongside it - two separate
	-- AlignOrientations on the same root fighting over the caster's
	-- orientation (one stale, one live) is what actually caused "doesn't
	-- turn toward target".
	local throwDir = if direction and direction.Magnitude > 0.05
		then Vector3.new(direction.X, 0, direction.Z)
		elseif aimPoint
		then Vector3.new(aimPoint.X - jeanRoot.Position.X, 0, aimPoint.Z - jeanRoot.Position.Z)
		else Vector3.new(jeanRoot.CFrame.LookVector.X, 0, jeanRoot.CFrame.LookVector.Z)
	if throwDir.Magnitude < 0.05 then
		throwDir = Vector3.new(0, 0, -1)
	else
		throwDir = throwDir.Unit
	end

	local ownedParts = setSlamOwnership(victim)
	victim:SetAttribute(GameConstants.MG_SLAM_HELD_ATTRIBUTE, true)
	setVictimControlled(victim, true)
	local victimAutoRotate = vHum.AutoRotate
	vHum.AutoRotate = false
	-- Anchored so the target's own animation (not a script) holds them in the air.
	vRoot.AssemblyLinearVelocity = Vector3.zero
	vRoot.Anchored = true

	-- Flame Combo (Phoenix's reskin of this same ability) uses BurnMorph's
	-- per-body-part burn particles on the victim instead of the classic
	-- TelekineticSlam1Attachment spark - base Jean's plain Telekinetic Slam
	-- keeps the original.
	local isPhoenixFlame = GameConstants.PHOENIX_LOOK_IDS[MarvelGirlService.lookOf(character)] == true
	local fxList: { Instance } = {}
	if isPhoenixFlame then
		Phoenix.beginBurnVfx(victim)
	else
		local vTorso = victim:FindFirstChild("UpperTorso") or victim:FindFirstChild("Torso") or vRoot
		local slam1 = attachSlamAttachment(vTorso :: BasePart, "TelekineticSlam1Attachment", Vector3.zero, character)
		if slam1 then
			table.insert(fxList, slam1)
		end
	end

	local token = 1
	local state: SlamState = {
		character = character,
		victim = victim,
		vRoot = vRoot,
		token = token,
		fx = fxList,
		ownedParts = ownedParts,
		throwDir = throwDir,
		slam2Host = nil,
		faceConn = nil,
		faceAlign = nil,
		faceAtt = nil,
		animTrack = playSlamAnim(character, GameConstants.MG_SLAM_ANIM),
		victimTrack = playSlamAnim(victim, GameConstants.MG_SLAM_TARGET_ANIM),
		startedAt = os.clock(),
		victimAutoRotate = victimAutoRotate,
		burnVfx = isPhoenixFlame,
	}
	slamByPlayer[player] = state

	local vAnimator = vHum:FindFirstChildOfClass("Animator")
	if vAnimator then
		for _, other in vAnimator:GetPlayingAnimationTracks() do
			-- Only looped holds/poses: a timed (non-looped) track is never cut short.
			if other ~= state.victimTrack and other.Looped and other.Priority.Value >= Enum.AnimationPriority.Action.Value then
				other:Stop(0.1)
			end
		end
	end

	-- AlignOrientation (Responsiveness 4) only turned the caster ~10deg over the
	-- whole 6s combo, so both bodies are steered directly each frame instead.
	state.faceConn = RunService.Heartbeat:Connect(function()
		if slamByPlayer[player] ~= state or not jeanRoot.Parent or not vRoot.Parent then
			return
		end
		local flat = Vector3.new(vRoot.Position.X - jeanRoot.Position.X, 0, vRoot.Position.Z - jeanRoot.Position.Z)
		if flat.Magnitude < 0.08 then
			return
		end
		jeanRoot.CFrame = jeanRoot.CFrame:Lerp(CFrame.lookAt(jeanRoot.Position, jeanRoot.Position + flat.Unit), 0.2)
		if not state.released then
			vRoot.CFrame = CFrame.lookAt(vRoot.Position, vRoot.Position - flat.Unit)
			-- A morph's own state/animation code (or a not-yet-loaded asset, Length
			-- 0 on first use) can leave the target track not actually playing;
			-- re-assert it at the right timeline position instead of trusting the
			-- single Play() at cast start.
			local vt = state.victimTrack
			-- Re-asserted only while the clip should still be running: once it has played out, IsPlaying is false for good and
			-- restarting it every heartbeat froze the victim near the end and made the pose stutter.
			if vt and vt.Length > 0 and (not state.victimSynced or (not vt.IsPlaying and os.clock() - state.startedAt < vt.Length - 0.1)) then
				state.victimSynced = true
				vt:Play(0.05, 1, 1)
				vt.TimePosition = math.min(os.clock() - state.startedAt, vt.Length - 0.05)
			end
		end
	end)

	-- A wall effect appears on the target's left then right as each matching sweep of the animation
	-- begins, each one facing the target (Phoenix's Flame Combo uses the Cosmic wall, base Jean's the Telekinetic one).
	task.spawn(function()
		local template = getPhoenixAsset(if isPhoenixFlame then "CosmicComboWall" else "TelekineticComboWall")
		if not template or not template:IsA("Attachment") then
			warn("[MarvelGirl] Missing Assets.JeanGrey.JeanGreyThePhoenixForce combo wall attachment")
			return
		end
		for _, wall in GameConstants.MG_COMBO_WALLS do
			local remaining = state.startedAt + wall.at - os.clock()
			if remaining > 0 then
				task.wait(remaining)
			end
			if slamByPlayer[player] ~= state or not victim.Parent or not vRoot.Parent or not jeanRoot.Parent then
				return
			end
			-- Centred on the target's upper torso (it rides up with the animation), not the anchored root.
			local torso = victim:FindFirstChild("UpperTorso") or victim:FindFirstChild("Torso")
			local center = if torso and torso:IsA("BasePart") then torso.Position else vRoot.Position
			local offset = if wall.side == "right" then jeanRoot.CFrame.RightVector else -jeanRoot.CFrame.RightVector
			local pos = center + offset * GameConstants.MG_COMBO_WALL_DIST
			local host = Instance.new("Part")
			host.Name = "MgComboWall_" .. wall.side
			host.Size = Vector3.new(0.2, 0.2, 0.2)
			host.Transparency = 1
			host.Anchored = true
			host.CanCollide = false
			host.CanQuery = false
			host.CanTouch = false
			host.CFrame = CFrame.lookAt(pos, center)
			host.Parent = Workspace
			local fx = template:Clone()
			fx.CFrame = CFrame.Angles(0, math.rad(GameConstants.MG_COMBO_WALL_YAW), 0) * CFrame.Angles(math.rad(GameConstants.MG_COMBO_WALL_PITCH), 0, 0)
			fx.Parent = host
			-- The wall asset is authored pink; base Jean's psychic colour is blue (Marvel Girl keeps the pink).
			if not isPhoenixFlame and isJean97(character) then
				styleJeanFx(fx, nil, character)
			end
			VfxHelper.setParticlesEnabled(fx, true)
			-- Show up at once instead of building up from the emission rate.
			for _, em in fx:GetDescendants() do
				if em:IsA("ParticleEmitter") then
					em:Emit(math.max(3, math.floor(em.Rate * 0.1)))
				end
			end
			task.delay(wall.life, function()
				if fx.Parent then
					VfxHelper.smoothDisableParticles(fx, 0.2)
				end
				task.delay(1.5, function()
					if host.Parent then
						host:Destroy()
					end
				end)
			end)
		end
	end)

	task.spawn(function()
		local t0 = os.clock()
		local function waitUntil(t: number): boolean
			while os.clock() - t0 < t do
				if slamByPlayer[player] ~= state or state.token ~= token then
					return false
				end
				if not victim.Parent or not vRoot.Parent or not character.Parent then
					return false
				end
				if character:GetAttribute(GameConstants.RAGDOLLED_ATTRIBUTE) == true then
					return false
				end
				task.wait()
			end
			return true
		end
		local function abort()
			if slamByPlayer[player] == state then
				endSlam(player, true, false)
			end
		end

		-- The target animation does the lift / right / left / front sweep; these
		-- ticks only land the damage at the end of each sweep.
		for _, t in GameConstants.MG_COMBO_HIT_TIMES do
			if not waitUntil(t) then
				abort()
				return
			end
			CombatHelper.dealDamage(character, victim, GameConstants.MG_SLAM_DAMAGE * (damageMult or 1), vRoot.Position, "projectile")
		end

		if not waitUntil(GameConstants.MG_COMBO_PUSH_TIME) then
			abort()
			return
		end
		-- Thrown straight away from Jean, not toward the cursor.
		local awayFlat = Vector3.new(vRoot.Position.X - jeanRoot.Position.X, 0, vRoot.Position.Z - jeanRoot.Position.Z)
		local dir = if awayFlat.Magnitude > 0.05 then awayFlat.Unit else state.throwDir
		character:SetAttribute("MgSlamAim", nil)
		-- Released mid-animation: the target keeps playing its anim while flung,
		-- and only ragdolls once the animation ends (endSlam).
		state.released = true
		vRoot.Anchored = false
		-- Standing on the ground, the Humanoid's own floor friction ate the push
		-- within ~0.2s (82 studs/s -> 0); PlatformStand hands it to physics.
		CombatHelper.getHumanoid(victim).PlatformStand = true
		if not CombatHelper.isShielded(victim) then
			vRoot.AssemblyLinearVelocity = dir * GameConstants.MG_SLAM_THROW_SPEED + Vector3.new(0, GameConstants.MG_SLAM_THROW_UP, 0)
			CombatHelper.dealDamage(character, victim, GameConstants.MG_SLAM_THROW_DAMAGE, vRoot.Position, "projectile")
		end

		-- Cosmic (Phoenix) combo only: where the thrown target first comes down on the ground, the
		-- CosmicComboAttachment bursts there (each emitter emits its own EmitCount; purely visual).
		if isPhoenixFlame then
			task.spawn(function()
				local template = getPhoenixAsset(character, "CosmicComboAttachment")
				if not template or not template:IsA("Attachment") then
					return
				end
				local rayParams = RaycastParams.new()
				rayParams.FilterType = Enum.RaycastFilterType.Exclude
				rayParams.FilterDescendantsInstances = { victim, character }
				local deadline = os.clock() + 4
				local airborne = false
				while os.clock() < deadline and victim.Parent and vRoot.Parent do
					task.wait()
					local ground = Workspace:Raycast(vRoot.Position, Vector3.new(0, -8, 0), rayParams)
					local height = if ground then vRoot.Position.Y - ground.Position.Y else math.huge
					if height > 3.5 then
						airborne = true
					elseif airborne and ground then
						local host = Instance.new("Part")
						host.Name = "MgCosmicComboLanding"
						host.Size = Vector3.new(0.2, 0.2, 0.2)
						host.Transparency = 1
						host.Anchored = true
						host.CanCollide = false
						host.CanQuery = false
						host.CanTouch = false
						host.CFrame = CFrame.new(ground.Position)
						host.Parent = Workspace
						local fx = template:Clone()
						fx.Parent = host
						for _, em in fx:GetDescendants() do
							if em:IsA("ParticleEmitter") then
								em.Enabled = false
								local count = em:GetAttribute("EmitCount")
								em:Emit(if type(count) == "number" then count else 10)
							end
						end
						task.delay(4, function()
							if host.Parent then
								host:Destroy()
							end
						end)
						return
					end
				end
			end)
		end

		-- Cosmic combo: anyone the thrown target flies into takes a little damage, a knock-back and a short ragdoll.
		if isPhoenixFlame then
			task.spawn(function()
				local struck: { [Model]: boolean } = { [victim] = true, [character] = true }
				local deadline = os.clock() + GameConstants.MG_FLAME_COMBO_SPLASH_WINDOW
				while os.clock() < deadline and victim.Parent and vRoot.Parent do
					for _, other in CombatHelper.overlapCharacters(vRoot.Position, GameConstants.MG_FLAME_COMBO_SPLASH_RADIUS, character) do
						local oRoot = other:FindFirstChild("HumanoidRootPart") :: BasePart?
						if struck[other] or not oRoot or CombatHelper.isShielded(other) then
							continue
						end
						struck[other] = true
						CombatHelper.dealDamage(character, other, GameConstants.MG_FLAME_COMBO_SPLASH_DAMAGE, oRoot.Position, "projectile")
						RagdollService.applyTimed(other, GameConstants.MG_FLAME_COMBO_SPLASH_RAGDOLL)
						PushHelper.applyToCharacter(other, dir, {
							speed = GameConstants.MG_FLAME_COMBO_SPLASH_PUSH,
							upBoost = GameConstants.MG_FLAME_COMBO_SPLASH_PUSH_UP,
							noRagdoll = true,
						})
					end
					task.wait(0.05)
				end
			end)
		end

		if not waitUntil(GameConstants.MG_COMBO_END_TIME) then
			abort()
			return
		end
		endSlam(player, true, true)
	end)
end

----------------------------------------------------------------
-- Phoenix's Flame Combo: identical to Telekinetic Slam. (The insta-kill
-- under 10% HP that used to live here moved to Cosmic Aura Burn instead.)
----------------------------------------------------------------

do

function Phoenix.castFlameCombo(player: Player, target: Model?, direction: Vector3?, aimPoint: Vector3?, lockOn: boolean?)
	local character = player.Character
	if not character then
		return
	end
	local entry = CharacterRegistry.getAbilityById("jean_grey", "flame_combo")
	if not entry then
		return
	end
	if AbilityCooldownHelper.isOnCooldown(character, entry.id) or AbilityCooldownHelper.isActive(character, entry.id) then
		return
	end
	-- Identical to Telekinetic Slam, calling it directly with no pre-emptive
	-- flag of its own - exactly how base Jean's X key calls it.
	-- castTelekineticSlam owns "telekinetic_slam"'s whole cooldown/active
	-- lifecycle itself, including silently no-opping on a bad aim/out-of-
	-- range/shielded target via its own checks. The previous version marked
	-- "flame_combo" active and queued an unconditional 18s task.delay to
	-- clear it *before* calling castTelekineticSlam, regardless of whether a
	-- slam actually started - so a whiffed cast (nothing under the cursor)
	-- still locked the G button doing nothing for the full mirrored cooldown
	-- ("works on nothing and doesn't stop"). castTelekineticSlam
	-- synchronously registers slamByPlayer[player] before it spawns the
	-- async slam sequence, so checking it right after the call reliably
	-- tells us whether a real cast actually began.
	castTelekineticSlam(player, target, direction, aimPoint, lockOn, GameConstants.MG_FLAME_COMBO_DAMAGE_MULT)
	if slamByPlayer[player] then
		AbilityCooldownHelper.setActive(character, entry.id, true)
		task.spawn(function()
			while slamByPlayer[player] do
				task.wait(0.1)
			end
			if character.Parent then
				AbilityCooldownHelper.setActive(character, entry.id, false)
				-- Mirror the underlying slam's own cooldown decision - an
				-- interrupted slam (ragdoll/cancelAll) skips its cooldown, so
				-- flame_combo must skip it too instead of always applying one.
				if character:GetAttribute("MgLastSlamApplyCooldown") == true then
					AbilityCooldownHelper.applyAfterUse(character, entry.id, entry.cooldown)
				end
			end
		end)
	end
end

end -- Phoenix's Flame Combo

----------------------------------------------------------------
-- Molecular Eradication: instant execute on a sub-20%-HP target within 40
-- studs. Both sides frozen and locked looking at each other for the whole
-- channel; only Phoenix dying mid-channel aborts it (the target dying some
-- other way, or leaving, also aborts - there's nothing left to erase).
----------------------------------------------------------------

do

local eradicationByPlayer: { [Player]: {
	character: Model,
	victim: Model,
	fx: { Instance },
	startedAt: number,
	startHealth: number,
	casterWalk: number,
	victimWalk: number,
	victimJumpPower: number?,
	victimJumpHeight: number?,
	victimAutoRotate: boolean,
	casterAtt: Attachment?,
	casterAlign: AlignPosition?,
	victimAtt: Attachment?,
	victimAlign: AlignPosition?,
	victimAnchoredParts: { BasePart },
	victimOwned: { BasePart },
	anchored: boolean,
	pullFrom: Vector3,
	pullTo: Vector3,
	pullT0: number,
	travel: number,
	casterTrack: AnimationTrack?,
	victimTrack: AnimationTrack?,
} } = {}

local function makeEradicationFloat(part: BasePart, holdAt: Vector3?): (Attachment, AlignPosition)
	local att = Instance.new("Attachment")
	att.Name = "MgEradicationFloatAtt"
	att.Parent = part
	local align = Instance.new("AlignPosition")
	align.Name = "MgEradicationFloatAlign"
	align.Mode = Enum.PositionAlignmentMode.OneAttachment
	align.Attachment0 = att
	align.ApplyAtCenterOfMass = true
	align.MaxForce = 1e9
	align.MaxVelocity = 40
	align.Responsiveness = GameConstants.MG_ERADICATION_FLOAT_RESPONSIVENESS
	-- holdAt: pin here instead of lifting (Molecular Eradication no longer lifts anyone).
	align.Position = holdAt or (part.Position + Vector3.new(0, GameConstants.MG_ERADICATION_FLOAT_HEIGHT, 0))
	align.Parent = part
	return att, align
end

local function clearEradicationFloat(att: Attachment?, align: AlignPosition?)
	if align and align.Parent then
		align:Destroy()
	end
	if att and att.Parent then
		att:Destroy()
	end
end

-- Highest part first - opposite order from Cosmic Aura's feet-to-head insta
-- dissolve (auraBodyParts, a different do-block's own helper).
local function topToBottomParts(character: Model): { BasePart }
	local parts: { BasePart } = {}
	for _, desc in character:GetDescendants() do
		if desc:IsA("BasePart") then
			table.insert(parts, desc)
		end
	end
	table.sort(parts, function(a, b)
		return a.Position.Y > b.Position.Y
	end)
	return parts
end

local function finishEradication(player: Player, killed: boolean)
	local state = eradicationByPlayer[player]
	if not state then
		return
	end
	eradicationByPlayer[player] = nil
	local character = state.character
	local victim = state.victim
	if state.casterTrack then
		state.casterTrack:Stop(0.2)
	end
	if state.victimTrack then
		state.victimTrack:Stop(0.2)
	end
	clearEradicationFloat(state.casterAtt, state.casterAlign)
	clearEradicationFloat(state.victimAtt, state.victimAlign)
	if victim.Parent then
		restorePullOwnership(victim, state.victimOwned)
	end
	if not killed then
		-- Interrupted, not actually erased - give back only the parts this ability itself anchored.
		for _, part in state.victimAnchoredParts do
			if part.Parent then
				part.Anchored = false
			end
		end
	end
	if killed then
		-- She's dissolving into dust, not fading out - the per-body-part
		-- morph particles vanish instantly rather than smooth-disabling.
		for _, f in state.fx do
			if f.Parent then
				f:Destroy()
			end
		end
		if victim.Parent then
			local vRootPos = getRoot(victim)
			local pos = if vRootPos then vRootPos.Position else victim:GetPivot().Position
			-- Starts right alongside the dust VFX below - head first, working
			-- down, opposite of Cosmic Aura's feet-first insta dissolve. The
			-- ground Dust basepart further below waits for this to fully
			-- finish (bodyFadeDuration) instead of a fixed 0.5s, so it never
			-- appears while she's still visibly there.
			local partsToFade = topToBottomParts(victim)
			-- Much quicker per request (was 0.12s/part stagger + 0.02s tween, ~0.5s for the whole body).
			local bodyFadeDuration = 0.05 + #partsToFade * 0.008
			task.spawn(function()
				for _, part in partsToFade do
					if part.Parent then
						TweenService:Create(part, TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
							Transparency = 1,
						}):Play()
					end
					task.wait(0.008)
				end
			end)
			local dustParticlesTemplate = getPhoenixAsset(character, "MolecularEradication", "DustParticles")
			if dustParticlesTemplate then
				local dustFx = dustParticlesTemplate:Clone()
				if dustFx:IsA("BasePart") then
					dustFx.Anchored = true
					dustFx.CanCollide = false
					dustFx.CFrame = CFrame.new(pos)
				elseif dustFx:IsA("Model") then
					dustFx:PivotTo(CFrame.new(pos))
				end
				dustFx.Parent = Workspace
				VfxHelper.setParticlesEnabled(dustFx, true)
				VfxHelper.emitAllParticles(dustFx, 20)
				task.delay(math.max(0.5, bodyFadeDuration), function()
					VfxHelper.setParticlesEnabled(dustFx, false)
					task.delay(1, function()
						if dustFx.Parent then
							dustFx:Destroy()
						end
					end)
					local foot = victim:FindFirstChild("LeftFoot") or victim:FindFirstChild("Left Leg")
					local footY = if foot and foot:IsA("BasePart") then foot.Position.Y else pos.Y - 3
					local dustTemplate = getPhoenixAsset(character, "MolecularEradication", "Dust")
					if dustTemplate and dustTemplate:IsA("BasePart") then
						local dust = dustTemplate:Clone()
						dust.Name = "MgEradicationDust"
						dust.Anchored = true
						dust.CanCollide = false
						dust.CFrame = dust.CFrame - dust.CFrame.Position + Vector3.new(pos.X, footY, pos.Z)
						dust.Parent = Workspace
						VfxHelper.setParticlesEnabled(dust, true)
						task.delay(10, function()
							if dust.Parent then
								VfxHelper.retireFxSmooth(dust, 1, 1.5)
							end
						end)
					end
				end)
			end
		end
	else
		for _, f in state.fx do
			if f.Parent then
				VfxHelper.retireFxSmooth(f, 0.4, 0.6)
			end
		end
	end
	if victim.Parent then
		local vHum = CombatHelper.getHumanoid(victim)
		if vHum then
			if killed and vHum.Health > 0 then
				-- Bypasses CombatHelper.dealDamage (direct kill), so stamp the
				-- same "what killed me" attribute it would - both revival
				-- systems check this to recognize a real insta-kill.
				CombatHelper.kill(player.Character, victim, "molecular_eradication")
			elseif vHum.Health > 0 then
				vHum.WalkSpeed = state.victimWalk
				vHum.AutoRotate = state.victimAutoRotate
				if state.victimJumpPower then
					vHum.JumpPower = state.victimJumpPower
				elseif state.victimJumpHeight then
					pcall(function()
						vHum.JumpHeight = state.victimJumpHeight :: number
					end)
				end
			end
		end
		victim:SetAttribute(GameConstants.MOVEMENT_SLOWED_ATTRIBUTE, nil)
		victim:SetAttribute(GameConstants.POWERS_DISABLED_UNTIL, nil)
		-- releaseContinuous (not destroyContinuous) - restores AutoRotate
		-- itself. Both sides were locked facing each other the whole channel
		-- via faceTowardContinuous, which never restores AutoRotate on its
		-- own (by design - see CastFaceHelper's own doc comment); skipping
		-- this left both Phoenix and the target stuck unable to turn forever
		-- after the ability ended.
		CastFaceHelper.releaseContinuous(victim)
	end
	if character.Parent then
		local hum = CombatHelper.getHumanoid(character)
		if hum then
			hum.WalkSpeed = state.casterWalk
		end
		character:SetAttribute(GameConstants.BUSY_ATTRIBUTE, nil)
		CastFaceHelper.releaseContinuous(character)
		endPowerFx(character)
		local entry = CharacterRegistry.getAbilityById("jean_grey", "molecular_eradication")
		if entry then
			AbilityCooldownHelper.setActive(character, entry.id, false)
			AbilityCooldownHelper.applyAfterUse(character, entry.id, entry.cooldown)
		end
	end
end

function Phoenix.castMolecularEradication(
	player: Player,
	target: Model?,
	direction: Vector3?,
	aimPoint: Vector3?,
	lockOn: boolean?
)
	local character = player.Character
	if not character or eradicationByPlayer[player] then
		return
	end
	local entry = CharacterRegistry.getAbilityById("jean_grey", "molecular_eradication")
	if not entry or not canUse(character, entry.id, 0) then
		return
	end
	local root = getRoot(character)
	if not root then
		return
	end
	local victim = resolveSingleTkTarget(
		character,
		root,
		target,
		direction,
		aimPoint,
		GameConstants.MG_ERADICATION_RANGE,
		lockOn
	)
	if not victim or victim == character then
		return
	end
	local vRoot = getRoot(victim)
	local vHum = CombatHelper.getHumanoid(victim)
	if not vRoot or not vHum or vHum.Health <= 0 then
		return
	end
	if vHum.Health > vHum.MaxHealth * GameConstants.MG_ERADICATION_HP_RATIO then
		return
	end
	if CombatHelper.isShielded(victim) then
		return
	end
	if not CharacterService.spendEnergy(character, entry.energyCost) then
		return
	end

	AbilityCooldownHelper.setActive(character, entry.id, true)
	character:SetAttribute(GameConstants.BUSY_ATTRIBUTE, true)
	beginPowerFx(character)
	fireCameraShake(player, 0.4, GameConstants.MG_ERADICATION_DURATION, 0.3, 0.5)

	local victimWalk = vHum.WalkSpeed
	local victimJumpPower: number? = nil
	local victimJumpHeight: number? = nil
	if vHum.UseJumpPower then
		victimJumpPower = vHum.JumpPower
	else
		pcall(function()
			victimJumpHeight = vHum.JumpHeight
		end)
	end
	local victimAutoRotate = vHum.AutoRotate
	vHum.WalkSpeed = 0
	vHum.JumpPower = 0
	pcall(function()
		vHum.JumpHeight = 0
	end)
	vHum.AutoRotate = false
	pcall(function()
		vHum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	end)
	victim:SetAttribute(GameConstants.MOVEMENT_SLOWED_ATTRIBUTE, true)
	victim:SetAttribute(
		GameConstants.POWERS_DISABLED_UNTIL,
		AbilityCooldownHelper.getNow() + GameConstants.MG_ERADICATION_DURATION + 0.5
	)
	-- Server-owned while she drags them in, so the victim's own client can't fight the pull. They are only
	-- anchored once they arrive (see updateEradication) - a knockback landing mid-channel used to be able to
	-- drag a held victim, and full Anchored is the only thing that guarantees they can't move after that.
	local victimOwned = setPullServerOwnership(victim)
	local victimAnchoredParts: { BasePart } = {}

	local hum = CombatHelper.getHumanoid(character)
	local casterWalk = if hum then hum.WalkSpeed else GameConstants.DEFAULT_WALK_SPEED
	if hum then
		hum.WalkSpeed = 0
		hum:Move(Vector3.zero, false)
	end

	-- MolecularEradicationMorph's per-body-part particles get copied onto
	-- the victim's matching body parts (same technique as Phoenix's revival
	-- ReviveMorph) instead of one head-anchored fx - they follow the real
	-- limbs automatically since they're parented onto them, no per-frame
	-- repositioning needed.
	local fx: { Instance } = {}
	local morphTemplate = getPhoenixAsset(character, "MolecularEradication", "MolecularEradicationMorph")
	if morphTemplate then
		fx = VfxHelper.attachMorphParticles(victim, morphTemplate)
	end

	-- Phoenix stays where she is and PULLS the victim to her; the (unchanged) dissolve channel starts once they
	-- have arrived in front of her.
	local toVictim = Vector3.new(vRoot.Position.X - root.Position.X, 0, vRoot.Position.Z - root.Position.Z)
	local flatDir = if toVictim.Magnitude > 0.05 then toVictim.Unit else Vector3.new(0, 0, -1)
	local standPos = Vector3.new(root.Position.X, root.Position.Y, root.Position.Z) + flatDir * GameConstants.MG_ERADICATION_STAND_DIST
	local travel = math.clamp((standPos - vRoot.Position).Magnitude / GameConstants.MG_ERADICATION_PULL_SPEED, 0.45, 1.2)
	-- Never shorter than a glide the eye can follow: a near-instant pull read as a teleport.
	travel = math.max(travel - GameConstants.MG_ERADICATION_START_LEAD, 0.3)
	local casterAtt, casterAlign = makeEradicationFloat(root, root.Position)
	local victimAtt, victimAlign = makeEradicationFloat(vRoot, standPos)
	victimAlign.MaxVelocity = GameConstants.MG_ERADICATION_PULL_SPEED

	eradicationByPlayer[player] = {
		character = character,
		victim = victim,
		fx = fx,
		startedAt = AbilityCooldownHelper.getNow() + travel,
		startHealth = vHum.Health,
		casterWalk = casterWalk,
		victimWalk = victimWalk,
		victimJumpPower = victimJumpPower,
		victimJumpHeight = victimJumpHeight,
		victimAutoRotate = victimAutoRotate,
		casterAtt = casterAtt,
		casterAlign = casterAlign,
		victimAtt = victimAtt,
		victimAlign = victimAlign,
		victimAnchoredParts = victimAnchoredParts,
		victimOwned = victimOwned,
		anchored = false,
		pullFrom = vRoot.Position,
		pullTo = standPos,
		pullT0 = AbilityCooldownHelper.getNow(),
		travel = travel,
		casterTrack = playJeanAnim(character, GameConstants.MG_ERADICATION_CASTER_ANIM, false),
		victimTrack = playJeanAnim(victim, GameConstants.MG_ERADICATION_VICTIM_ANIM, false),
	}
end

function Phoenix.updateEradication(dt: number)
	local now = AbilityCooldownHelper.getNow()
	for player, state in eradicationByPlayer do
		local character = state.character
		local victim = state.victim
		if not character.Parent or player.Character ~= character then
			finishEradication(player, false)
			continue
		end
		local hum = CombatHelper.getHumanoid(character)
		if not hum or hum.Health <= 0 then
			-- The one thing that stops this once started: Phoenix herself dying.
			finishEradication(player, false)
			continue
		end
		if not victim.Parent then
			finishEradication(player, false)
			continue
		end
		local vHum = CombatHelper.getHumanoid(victim)
		if not vHum or vHum.Health <= 0 then
			finishEradication(player, false)
			continue
		end
		local root = getRoot(character)
		local vRoot = getRoot(victim)
		if root and vRoot then
			CastFaceHelper.faceTowardContinuous(character, vRoot.Position)
			CastFaceHelper.faceTowardContinuous(victim, root.Position)
		end
		-- Being dragged in: moved directly (the physics constraint alone left them standing where they were).
		if not state.anchored and vRoot and now < state.startedAt then
			local a = math.clamp((now - state.pullT0) / math.max(state.travel, 0.01), 0, 1)
			local pos = state.pullFrom:Lerp(state.pullTo, a * a * (3 - 2 * a))
			victim:PivotTo(victim:GetPivot() + (pos - vRoot.Position))
			vRoot.AssemblyLinearVelocity = Vector3.zero
		end
		-- Face Phoenix for the whole channel. The physics-based turn above cannot rotate an anchored root, so once
		-- they are held, turn the victim directly (smoothed), keeping its position.
		if vRoot and root and (state.anchored or now >= state.startedAt) then
			local toCaster = Vector3.new(root.Position.X - vRoot.Position.X, 0, root.Position.Z - vRoot.Position.Z)
			if toCaster.Magnitude > 0.05 then
				local from = vRoot.CFrame
				local want = CFrame.lookAt(vRoot.Position, vRoot.Position + toCaster.Unit)
				local turned = from.Rotation:Lerp(want.Rotation, math.clamp(dt * 12, 0, 1))
				victim:PivotTo(CFrame.new(vRoot.Position) * turned + (victim:GetPivot().Position - vRoot.Position))
			end
		end
		-- Arrived: hold them rigidly in place for the dissolve.
		if not state.anchored and now >= state.startedAt and vRoot then
			state.anchored = true
			-- Only the root is anchored: with every limb anchored too, the victim's animation could not move them.
			if not vRoot.Anchored then
				vRoot.Anchored = true
				vRoot.AssemblyLinearVelocity = Vector3.zero
				vRoot.AssemblyAngularVelocity = Vector3.zero
				table.insert(state.victimAnchoredParts, vRoot)
			end
		end
		-- Smooth drain, not an instant zero at the end - reaches exactly 0
		-- right as the channel finishes, not before (so the health<=0 abort
		-- guard above never mistakes our own drain for the target dying
		-- some other way).
		local elapsed = math.clamp(now - state.startedAt, 0, GameConstants.MG_ERADICATION_DURATION)
		local frac = elapsed / GameConstants.MG_ERADICATION_DURATION
		vHum.Health = math.max(0, state.startHealth * (1 - frac))
		if elapsed >= GameConstants.MG_ERADICATION_DURATION then
			finishEradication(player, true)
		end
	end
end

end -- Molecular Eradication

----------------------------------------------------------------
-- Telekinetic Debris (3 rocks emerge from nearby ground, seek cursor)
----------------------------------------------------------------
local function fadeAndDestroyDebris(part: BasePart)
	if not part.Parent then
		return
	end
	local model = if part.Parent:IsA("Model") and part.Parent.Name == "MgTelekineticDebris"
		then part.Parent
		else nil
	local fadeRoot: Instance = model or part
	VfxHelper.setParticlesEnabled(fadeRoot, false)
	part.Anchored = true
	part.CanCollide = false
	part.AssemblyLinearVelocity = Vector3.zero
	part.AssemblyAngularVelocity = Vector3.zero
	local fade = GameConstants.MG_DEBRIS_CANCEL_FADE
	local function fadeInst(inst: Instance)
		if inst:IsA("ParticleEmitter") then
			inst.Enabled = false
		elseif inst:IsA("Highlight") then
			TweenService:Create(inst, TweenInfo.new(fade, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				FillTransparency = 1,
				OutlineTransparency = 1,
			}):Play()
		elseif inst:IsA("BasePart") then
			TweenService:Create(inst, TweenInfo.new(fade, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Transparency = 1,
			}):Play()
		elseif inst:IsA("Decal") or inst:IsA("Texture") then
			TweenService:Create(inst, TweenInfo.new(fade), { Transparency = 1 }):Play()
		end
	end
	fadeInst(fadeRoot)
	for _, child in fadeRoot:GetDescendants() do
		fadeInst(child)
	end
	task.delay(math.max(fade, GameConstants.MG_DEBRIS_CANCEL_DELETE), function()
		if fadeRoot.Parent then
			fadeRoot:Destroy()
		end
	end)
end

local function dropUnusedDebris(rock: DebrisRock)
	if rock.thrown or rock.expiring or not rock.part.Parent then
		return
	end
	rock.expiring = true
	rock.rising = false
	local root = rock.visual.Parent and rock.visual or rock.part
	VfxHelper.setParticlesEnabled(rock.visual, false)
	VfxHelper.setParticlesEnabled(rock.part, false)
	local highlightFade = TweenInfo.new(0.65, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local function killParticles(inst: Instance)
		if inst:IsA("ParticleEmitter") then
			inst.Enabled = false
		elseif inst:IsA("Highlight") then
			TweenService:Create(inst, highlightFade, {
				FillTransparency = 1,
				OutlineTransparency = 1,
			}):Play()
		end
	end
	killParticles(root)
	for _, desc in root:GetDescendants() do
		killParticles(desc)
	end
	local function dropPart(part: BasePart)
		part.Anchored = false
		part.CanCollide = true
		part.CanQuery = true
		part.CanTouch = true
		part.AssemblyLinearVelocity = Vector3.new(0, -6, 0)
		part.AssemblyAngularVelocity = Vector3.new(
			(math.random() - 0.5) * 2.5,
			(math.random() - 0.5) * 2.5,
			(math.random() - 0.5) * 2.5
		)
	end
	dropPart(rock.part)
	if rock.visual:IsA("Model") then
		for _, desc in rock.visual:GetDescendants() do
			if desc:IsA("BasePart") then
				dropPart(desc)
			end
		end
	end
	local host = rock.part
	task.delay(GameConstants.MG_DEBRIS_EXPIRE_WAIT, function()
		if rock.thrown or not host.Parent then
			return
		end
		fadeAndDestroyDebris(host)
	end)
end

local function debrisImpactFloorPos(pos: Vector3, caster: Model?): (Vector3, Vector3)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = {}
	if caster then
		table.insert(exclude, caster)
	end
	params.FilterDescendantsInstances = exclude
	local hit = Workspace:Raycast(pos + Vector3.new(0, 8, 0), Vector3.new(0, -80, 0), params)
	if hit then
		local up = if hit.Normal.Magnitude > 0.05 then hit.Normal.Unit else Vector3.yAxis
		return hit.Position, up
	end
	return pos, Vector3.yAxis
end

local function spawnDebrisImpact(pos: Vector3, incomingDir: Vector3, caster: Model?, onBody: boolean?, playSound: boolean?)
	-- Initial lift has playSound == false and faces "up" with no real impact normal — skip FX, only spawn on actual hit
	local fakeLift = playSound == false and incomingDir.Magnitude <= 0.05
	if fakeLift then
		return
	end
	if playSound ~= false then
		playWorldSound(GameConstants.MG_DEBRIS_HIT_SOUNDS[math.random(1, #GameConstants.MG_DEBRIS_HIT_SOUNDS)], pos, 0.95)
	end
	local impactPos = pos
	local up = Vector3.yAxis
	if not onBody then
		impactPos, up = debrisImpactFloorPos(pos, caster)
	end

	local lookDir = if incomingDir.Magnitude > 0.05 then incomingDir.Unit else -up
	local host: Instance = Instance.new("Part")
	local hostPart = host :: BasePart
	hostPart.Name = "MgDebrisImpact"
	hostPart.Shape = Enum.PartType.Ball
	hostPart.Size = Vector3.new(4.2, 4.2, 4.2)
	hostPart.CFrame = CFrame.lookAt(impactPos, impactPos + lookDir)
	hostPart.Anchored = true
	hostPart.CanCollide = false
	hostPart.CanQuery = false
	hostPart.CanTouch = false
	hostPart.Transparency = 1
	hostPart.CastShadow = false
	hostPart.Parent = Workspace

	local attTemplate = VfxHelper.getMarvelGirlAsset("TelekineticDebrisThrow", "DebrisImpactAttachment")
		or VfxHelper.getMarvelGirlAsset("TelekineticDebrisThrow", "DebrisImpact")
	local spawned = false
	if attTemplate then
		VfxHelper.spawnAttachmentImpact(attTemplate, impactPos, {
			tint = jeanAccent(caster),
			emitCount = 5,
			disableAfter = 0.35,
			lifetime = 1.4,
			worldNormal = up,
		})
		spawned = true
	end

	if not onBody then
		local floorTemplate = VfxHelper.getMarvelGirlAsset("TelekineticDebrisThrow", "DebrisImpactFloor")
			or VfxHelper.getMarvelGirlAsset("TelekineticDebrisThrow", "ImpactFloor")
		if floorTemplate then
			local floorPos, floorUp = debrisImpactFloorPos(pos, caster)
			-- Yaw the decal along the throw line (caster -> surface) instead of an
			-- arbitrary default facing, flattened onto the surface via the up hint
			-- so it still conforms to a sloped/rotated surface.
			local tangentForward = lookDir - floorUp * lookDir:Dot(floorUp)
			if tangentForward.Magnitude < 0.05 then
				tangentForward = floorUp:Cross(Vector3.xAxis)
				if tangentForward.Magnitude < 0.05 then
					tangentForward = floorUp:Cross(Vector3.zAxis)
				end
			end
			local face = CFrame.lookAt(floorPos, floorPos + tangentForward.Unit, floorUp)
			local floor = floorTemplate:Clone()
			styleJeanFx(floor, nil, caster)
			if floor:IsA("BasePart") then
				floor.Anchored = true
				floor.CanCollide = false
				floor.CanQuery = false
				floor.CanTouch = false
				floor.CFrame = face + floorUp * 0.04
				floor.Parent = Workspace
			elseif floor:IsA("Model") then
				floor:PivotTo(face + floorUp * 0.04)
				floor.Parent = Workspace
			else
				floor.Parent = host
			end
			VfxHelper.emitByCount(floor)
			retireFx(floor, 0.2, 1.6)
			spawned = true
		end
	end

	if not spawned then
		-- No debris-specific FX available; leave room for the shared impact below
	end
	task.delay(0.5, function()
		if host.Parent then
			VfxHelper.setParticlesEnabled(host, false)
		end
	end)
	retireFx(host, 0.5, 3)
end

local function endDebris(player: Player, applyCooldown: boolean?, dropRocks: boolean?)
	local state = debrisByPlayer[player]
	if not state then
		return
	end
	debrisByPlayer[player] = nil
	if state.liftAnimTrack then
		state.liftAnimTrack:Stop(0.15)
		state.liftAnimTrack:Destroy()
		state.liftAnimTrack = nil
	end
	if dropRocks then
		for _, rock in state.rocks do
			if not rock.thrown and rock.part.Parent then
				fadeAndDestroyDebris(rock.part)
			end
		end
	end
	if state.character.Parent then
		state.character:SetAttribute("MgDebrisAim", nil)
		local hum = CombatHelper.getHumanoid(state.character)
		if hum then
			hum.AutoRotate = true
		end
		CastFaceHelper.cancelPending(state.character)
		CastFaceHelper.destroyHold(state.character)
		endPowerFx(state.character)
		AbilityCooldownHelper.setActive(state.character, "telekinetic_debris", false)
		if applyCooldown then
			AbilityCooldownHelper.applyAfterUse(state.character, "telekinetic_debris", GameConstants.MG_DEBRIS_COOLDOWN)
			CharacterService.markAbilityUse(state.character)
		end
	end
end

local function noteDebrisFinished(player: Player, state: DebrisState)
	if debrisByPlayer[player] ~= state then
		return
	end
	state.remaining -= 1
	if state.remaining <= 0 then
		endDebris(player, true, false)
	end
end

local function debrisFollowWorld(root: BasePart, offset: Vector3): Vector3
	return root.Position
		- root.CFrame.LookVector * offset.Z
		+ root.CFrame.RightVector * offset.X
		+ Vector3.new(0, offset.Y, 0)
end

local function worldToDebrisOffset(root: BasePart, worldPos: Vector3): Vector3
	local to = worldPos - root.Position
	return Vector3.new(
		to:Dot(root.CFrame.RightVector),
		worldPos.Y - root.Position.Y,
		-to:Dot(root.CFrame.LookVector)
	)
end

local function debrisWorldRotation(rock: DebrisRock): CFrame
	return CFrame.Angles(0, rock.yawAngle, 0) * CFrame.fromAxisAngle(rock.spinAxis, rock.spinAngle) * rock.baseTilt
end

local function setDebrisRockCf(rock: DebrisRock, cf: CFrame)
	if rock.visual:IsA("Model") then
		rock.visual:PivotTo(cf)
	else
		rock.part.CFrame = cf
	end
end

local function beginDebrisExpire(player: Player, state: DebrisState, rock: DebrisRock)
	dropUnusedDebris(rock)
	if debrisByPlayer[player] == state then
		noteDebrisFinished(player, state)
	end
end

local function findDebrisSpawnPoints(character: Model, root: BasePart, count: number): { Vector3 }
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	if look.Magnitude < 0.05 then
		look = Vector3.new(0, 0, -1)
	else
		look = look.Unit
	end
	local right = Vector3.new(root.CFrame.RightVector.X, 0, root.CFrame.RightVector.Z)
	if right.Magnitude < 0.05 then
		right = Vector3.new(1, 0, 0)
	else
		right = right.Unit
	end
	local back = -look
	local minSpacing = math.max(2.6, GameConstants.MG_DEBRIS_SPAWN_SPACING * 0.85)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }

	local points: { Vector3 } = {}
	for _ = 1, count do
		local chosen: Vector3? = nil
		for _try = 1, 12 do
			local yaw = math.random() * math.pi * 2
			local dist = 4.2 + math.random() * 4.8
			local offset = (CFrame.lookAt(Vector3.zero, look) * CFrame.Angles(0, yaw, 0)).LookVector * dist
			offset += Vector3.new((math.random() * 2 - 1) * 0.7, 0, (math.random() * 2 - 1) * 0.6)
			
			-- Cast from higher to ensure we hit ground even when flying
			local origin = root.Position + offset + Vector3.new(0, 100, 0)
			local hit = Workspace:Raycast(origin, Vector3.new(0, -250, 0), params)
			local pos = if hit then hit.Position else root.Position + offset - Vector3.new(0, 3, 0)
			local ok = true
			for _, other in points do
				if (other - pos).Magnitude < minSpacing then
					ok = false
					break
				end
			end
			if ok then
				chosen = pos
				break
			end
			chosen = pos
		end
		if chosen then
			table.insert(points, chosen)
		end
	end
	return points
end


local function randomDebrisRotation(): CFrame
	return CFrame.Angles(
		math.rad((math.random() * 2 - 1) * 22),
		math.rad(math.random() * 360),
		math.rad((math.random() * 2 - 1) * 16)
	)
end

local function instantiateDebrisRock(template: Instance, spawnCf: CFrame, caster: Model?): (BasePart?, Instance?)
	local clone = template:Clone()
	clone.Name = "MgTelekineticDebris"
	if clone:IsA("BasePart") then
		clone.Anchored = true
		clone.CanCollide = false
		clone.CanQuery = false
		clone.CanTouch = false
		clone.CFrame = spawnCf
		clone.Parent = Workspace
		styleJeanFx(clone, nil, caster)
		VfxHelper.setParticlesEnabled(clone, true)
		VfxHelper.emitAllParticles(clone, 8)
		for _, desc in clone:GetDescendants() do
			if desc:IsA("Sound") then
				desc.TimePosition = 0
				desc:Play()
			end
		end
		if clone:IsA("Sound") then
			clone.TimePosition = 0
			clone:Play()
		end
		return clone, clone
	end
	if clone:IsA("Model") then
		local primary = clone.PrimaryPart or clone:FindFirstChildWhichIsA("BasePart", true)
		if not primary then
			clone:Destroy()
			return nil, nil
		end
		if not clone.PrimaryPart then
			clone.PrimaryPart = primary
		end
		clone:PivotTo(spawnCf)
		clone.Parent = Workspace
		for _, desc in clone:GetDescendants() do
			if desc:IsA("BasePart") then
				desc.Anchored = true
				desc.CanCollide = false
				desc.CanQuery = false
				desc.CanTouch = false
			end
		end
		styleJeanFx(clone, nil, caster)
		VfxHelper.setParticlesEnabled(clone, true)
		VfxHelper.emitAllParticles(clone, 8)
		for _, desc in clone:GetDescendants() do
			if desc:IsA("Sound") then
				desc.TimePosition = 0
				desc:Play()
			end
		end
		return primary, clone
	end
	local host = makeFxHost("MgTelekineticDebris", spawnCf)
	host.Transparency = 0
	host.Size = Vector3.new(2, 2, 2)
	clone.Parent = host
	styleJeanFx(host, nil, caster)
	VfxHelper.setParticlesEnabled(host, true)
	VfxHelper.emitAllParticles(host, 8)
	return host, host
end

local function launchDebrisRock(player: Player, state: DebrisState, rock: DebrisRock, direction: Vector3?)
	if rock.thrown or rock.expiring or not rock.part.Parent then
		return
	end
	local character = state.character
	local root = getRoot(character)
	if not character.Parent or not root then
		fadeAndDestroyDebris(rock.part)
		noteDebrisFinished(player, state)
		return
	end

	rock.thrown = true
	local part = rock.part
	local visual = rock.visual
	local useRight = debrisUseRightByPlayer[player] == true
	debrisUseRightByPlayer[player] = not useRight
	if state.liftAnimTrack then
		state.liftAnimTrack:Stop(0.06)
		state.liftAnimTrack:Destroy()
		state.liftAnimTrack = nil
	end
	local throwTrack = playJeanAnim(
		character,
		if useRight then GameConstants.IW_DISC_RIGHT_ANIM else GameConstants.IW_DISC_LEFT_ANIM,
		false
	)
	if throwTrack then
		throwTrack.Priority = Enum.AnimationPriority.Action4
		local track = throwTrack
		task.delay(track.Length / math.max(track.Speed, 0.01) + 0.1, function()
			track:Stop(0.1)
			track:Destroy()
			local live = debrisByPlayer[player]
			if live ~= state then
				return
			end
			local remaining = false
			for _, other in state.rocks do
				if not other.thrown and not other.expiring then
					remaining = true
					break
				end
			end
			if remaining and state.liftAnimTrack == nil then
				local lift = playJeanAnim(character, GameConstants.MG_DEBRIS_LIFT_ANIM, true)
				if lift then
					lift.Priority = Enum.AnimationPriority.Action
				end
				state.liftAnimTrack = lift
			end
		end)
	end
	local capturedAim = character:GetAttribute("MgDebrisAim")
	local homePoint: Vector3
	if typeof(capturedAim) == "Vector3" then
		homePoint = capturedAim
	elseif state.aimPoint then
		homePoint = state.aimPoint
	elseif direction and direction.Magnitude > 0.01 then
		homePoint = part.Position + direction.Unit * 60
	else
		homePoint = root.Position + root.CFrame.LookVector * 60
	end
	smoothFaceToward(character, homePoint, GameConstants.MG_DEBRIS_THROW_WINDUP + 0.12)
	task.wait(GameConstants.MG_DEBRIS_THROW_WINDUP)
	if debrisByPlayer[player] ~= state or not part.Parent or rock.expiring then
		if part.Parent and not rock.expiring then
			fadeAndDestroyDebris(part)
			noteDebrisFinished(player, state)
		end
		return
	end

	local origin = if visual:IsA("Model") then visual:GetPivot().Position else part.Position
	local toHome = homePoint - origin
	local dir = if toHome.Magnitude > 0.08 then toHome.Unit else root.CFrame.LookVector

	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.AssemblyLinearVelocity = Vector3.zero
	part.AssemblyAngularVelocity = Vector3.zero

	fireCameraShake(player, 0.5, 0.32, 0.82, 0)

	ProjectileHelper.spawn(origin, dir, {
		speed = GameConstants.MG_DEBRIS_THROW_SPEED,
		damage = GameConstants.MG_DEBRIS_DAMAGE,
		radius = GameConstants.MG_DEBRIS_HIT_RADIUS,
		maxDistance = GameConstants.MG_DEBRIS_RANGE,
		owner = character,
		color = jeanAccent(character),
		pushOnHit = true,
		pushSpeed = GameConstants.MG_DEBRIS_PUSH_SPEED,
		pushUp = GameConstants.MG_DEBRIS_PUSH_UP,
		ragdollOnHit = GameConstants.MG_DEBRIS_RAGDOLL_TIME,
		lockWorldRotation = debrisWorldRotation(rock),
		impactFx = "none",
		impactOnCharacter = true,
		customVisual = visual,
		recolorVisual = true,
		deleteAfterFx = GameConstants.MG_DEBRIS_CANCEL_DELETE,
		onHit = function(victim: Model)
			-- Just a strong quick shake, no lingering color correction - clear
			-- the held tint the generic dealDamage hit-feel hook just set.
			-- A boulder slamming into you should be one of the heaviest hits
			-- in the game.
			ScreenFeelHelper.setTint(victim, nil)
			ScreenFeelHelper.pulseCharacter(victim, {
				intensity = 1.3,
				duration = 0.28,
				fovScale = 0.9,
				vignetteScale = 0.5,
			})
		end,
		onImpact = function(pos: Vector3, hitCharacter: boolean?)
			local incoming = dir
			spawnDebrisImpact(pos, incoming, character, hitCharacter == true)
			noteDebrisFinished(player, state)
		end,
	})
end

local function throwNextDebris(player: Player, direction: Vector3?, aimPoint: Vector3?)
	local state = debrisByPlayer[player]
	if not state then
		return
	end
	if aimPoint then
		state.aimPoint = aimPoint
		state.character:SetAttribute("MgDebrisAim", aimPoint)
	end
	local now = os.clock()
	local remaining = GameConstants.MG_DEBRIS_THROW_GAP - (now - state.lastThrowAt)
	if remaining > 0 then
		-- Used to just silently drop a throw request that arrived before the
		-- gap elapsed, requiring another click - a click that landed a
		-- fraction too early read as "way too much cooldown" (had to wait an
		-- arbitrary extra beat for the next click instead of the actual
		-- 0.15s). Queue it to fire itself once the gap is up instead of
		-- dropping it, so every throw is exactly MG_DEBRIS_THROW_GAP apart
		-- regardless of click timing. One pending queue at a time - extra
		-- clicks while already queued don't stack up more throws.
		if state.throwQueued then
			return
		end
		state.throwQueued = true
		task.delay(remaining, function()
			if debrisByPlayer[player] == state then
				state.throwQueued = false
				throwNextDebris(player, direction, aimPoint)
			end
		end)
		return
	end
	local pendingRock = false
	for _, rock in state.rocks do
		if rock.ready and not rock.thrown and not rock.expiring then
			if not CharacterService.spendEnergy(state.character, GameConstants.MG_DEBRIS_THROW_ENERGY) then
				return
			end
			state.lastThrowAt = now
			task.spawn(function()
				launchDebrisRock(player, state, rock, direction)
			end)
			return
		elseif not rock.thrown and not rock.expiring then
			-- Still emerging/bouncing, not ready yet.
			pendingRock = true
		end
	end
	-- Clicking the instant the ability starts (before any rock has finished
	-- emerging) used to just silently do nothing - same "click did nothing,
	-- had to click again" symptom as the gap case above, just from a
	-- different cause. Retry shortly instead of dropping it.
	if pendingRock and not state.throwQueued then
		state.throwQueued = true
		task.delay(0.05, function()
			if debrisByPlayer[player] == state then
				state.throwQueued = false
				throwNextDebris(player, direction, aimPoint)
			end
		end)
	end
end

local function releaseDebrisHold(player: Player)
	local state = debrisByPlayer[player]
	if not state then
		return
	end
	-- Releasing X keeps rocks following until the 10s window ends or they are thrown
	state.holding = false
end

local function castTelekineticDebris(player: Player, aimPoint: Vector3?)
	local character = player.Character
	if not character or debrisByPlayer[player] then
		return
	end
	local entry = CharacterRegistry.getAbilityById("jean_grey", "telekinetic_debris")
	if not entry or not canUse(character, entry.id, 0) then
		return
	end
	-- No upfront flat cost - drains continuously while held instead (see the
	-- debris follow loop in update()). Still needs some energy on hand to
	-- start the hold at all, same shape as Storm's Wind Shield.
	local startEnergy = character:GetAttribute(GameConstants.ENERGY_ATTRIBUTE)
	if type(startEnergy) ~= "number" or startEnergy <= 0 then
		return
	end

	local root = getRoot(character)
	if not root then
		return
	end

	local rockNames = { "DebrisThrowRock1", "DebrisThrowRock2", "DebrisThrowRock3" }
	local templates: { Instance } = {}
	for _, name in rockNames do
		local t = VfxHelper.getMarvelGirlAsset("TelekineticDebrisThrow", name)
		if t then
			table.insert(templates, t)
		end
	end
	if #templates == 0 then
		warn("[MarvelGirl] Missing Assets.JeanGrey.TelekineticDebrisThrow rocks")
		-- No refund needed - no upfront cost is spent anymore (drains
		-- continuously once the hold actually starts below).
		return
	end

	local function pickRockTemplates(pool: { Instance }, n: number): { Instance }
		local picked: { Instance } = {}
		for _ = 1, n do
			table.insert(picked, pool[math.random(1, #pool)])
		end
		if #pool > 1 then
			local first = picked[1]
			local allSame = true
			for i = 2, #picked do
				if picked[i] ~= first then
					allSame = false
					break
				end
			end
			if allSame then
				local other = first
				for _ = 1, 8 do
					other = pool[math.random(1, #pool)]
					if other ~= first then
						break
					end
				end
				picked[math.random(1, #picked)] = other
			end
		end
		return picked
	end

	local function buildRocks(n: number): { DebrisRock }
		local points = findDebrisSpawnPoints(character, root, n)
		local chosen = pickRockTemplates(templates, n)
		local built: { DebrisRock } = {}
		for i = 1, n do
			local template = chosen[i]
			local ground = points[i] or points[((i - 1) % math.max(#points, 1)) + 1]
			if not ground then
				continue
			end
			local spawnOffset = worldToDebrisOffset(root, ground)
			local spawnCf = CFrame.new(ground - Vector3.new(0, 2.4, 0)) * randomDebrisRotation()
			local part, visual = instantiateDebrisRock(template, spawnCf, character)
			if part and visual then
				local axis = Vector3.new(
					(math.random() * 2 - 1) * 0.85,
					0.12 + math.random() * 0.55,
					(math.random() * 2 - 1) * 0.85
				)
				if axis.Magnitude < 0.05 then
					axis = Vector3.new(0.35, 0.7, 0.2)
				end
				axis = axis.Unit
				table.insert(built, {
					part = part,
					visual = visual,
					ready = false,
					rising = true,
					thrown = false,
					expiring = false,
					followOffset = spawnOffset,
					homeOffset = spawnOffset,
					liftY = spawnOffset.Y - 2.4,
					rot = spawnCf.Rotation,
					baseTilt = CFrame.Angles(
						math.rad((math.random() * 2 - 1) * 18),
						math.rad((math.random() * 2 - 1) * 24),
						math.rad((math.random() * 2 - 1) * 14)
					),
					spinAxis = axis,
					spinSpeed = math.rad(5 + math.random() * 9),
					spinAngle = math.random() * math.pi * 2,
					yawSpeed = math.rad((math.random() * 2 - 1) * (2.5 + math.random() * 4.5)),
					yawAngle = math.random() * math.pi * 2,
					bobSpeed = 0,
					bobPhase = 0,
					orbitRadius = 5.2 + math.random() * 3.4,
					orbitHeight = 2.1 + math.random() * 1.6,
					orbitAngle = ((i - 1) / math.max(n, 1)) * math.pi * 2,
					orbitSpeed = GameConstants.MG_DEBRIS_ORBIT_SPEED,
				})
			end
		end
		return built
	end

	local count = GameConstants.MG_DEBRIS_ROCK_COUNT
	local rocks = buildRocks(count)
	if #rocks == 0 then
		-- No refund needed - no upfront cost is spent anymore.
		return
	end

	AbilityCooldownHelper.setActive(character, entry.id, true)
	attachPowerFx(character)
	playWorldSound(GameConstants.MG_DEBRIS_HIT_SOUNDS[math.random(1, #GameConstants.MG_DEBRIS_HIT_SOUNDS)], root.Position, 1.05)
	for _, rock in rocks do
		local liftPos = if rock.visual:IsA("Model") then rock.visual:GetPivot().Position else rock.part.Position
		spawnDebrisImpact(liftPos, Vector3.new(0, 1, 0), character, false, false)
	end
	local liftAnimTrack = playJeanAnim(character, GameConstants.MG_DEBRIS_LIFT_ANIM, true)
	if aimPoint then
		character:SetAttribute("MgDebrisAim", aimPoint)
	end

	local token = (character:GetAttribute("MgDebrisToken") :: number?) or 0
	token += 1
	character:SetAttribute("MgDebrisToken", token)

	local state: DebrisState = {
		character = character,
		token = token,
		remaining = #rocks,
		rocks = rocks,
		aimPoint = aimPoint,
		followUntil = os.clock() + GameConstants.MG_DEBRIS_HOLD_TIME + 2,
		holding = true,
		lastThrowAt = 0,
		liftAnimTrack = liftAnimTrack,
	}
	debrisByPlayer[player] = state

	task.spawn(function()
		local riseTime = GameConstants.MG_DEBRIS_EMERGE_TIME
		local bounceTime = GameConstants.MG_DEBRIS_BOUNCE_TIME
		local hoverH = GameConstants.MG_DEBRIS_HOVER_HEIGHT
		local peakExtra = GameConstants.MG_DEBRIS_BOUNCE_EXTRA

		local function emergeAndBounce(rock: DebrisRock)
			VfxHelper.setParticlesEnabled(rock.visual, true)
			VfxHelper.emitAllParticles(rock.visual, 10)
			local startCf = if rock.visual:IsA("Model") then rock.visual:GetPivot() else rock.part.CFrame
			rock.rot = startCf.Rotation
			local startY = rock.orbitHeight - 4.2
			local restY = rock.orbitHeight
			local peakY = restY + peakExtra
			rock.rising = true
			rock.liftY = startY
			local t0 = os.clock()
			while rock.part.Parent and (os.clock() - t0) < riseTime do
				if debrisByPlayer[player] ~= state or rock.thrown or rock.expiring then
					return
				end
				local a = math.clamp((os.clock() - t0) / riseTime, 0, 1)
				local s = 1 - (1 - a) * (1 - a) * (1 - a)
				rock.liftY = startY + (peakY - startY) * s
				task.wait()
			end
			rock.liftY = peakY
			local t1 = os.clock()
			while rock.part.Parent and (os.clock() - t1) < bounceTime do
				if debrisByPlayer[player] ~= state or rock.thrown or rock.expiring then
					return
				end
				local u = math.clamp((os.clock() - t1) / bounceTime, 0, 1)
				local damp = math.exp(-4.4 * u)
				local osc = math.cos(u * math.pi * 2.15)
				rock.liftY = restY + peakExtra * damp * osc
				task.wait()
			end
			if rock.part.Parent then
				rock.followOffset = Vector3.new(rock.followOffset.X, restY, rock.followOffset.Z)
				rock.liftY = restY
				rock.rising = false
				rock.ready = true
			end
		end

		local threadsDone = 0
		for _, rock in rocks do
			task.spawn(function()
				if debrisByPlayer[player] == state and rock.part.Parent then
					emergeAndBounce(rock)
				end
				threadsDone += 1
			end)
		end
		while threadsDone < #rocks do
			if debrisByPlayer[player] ~= state then
				return
			end
			task.wait(0.05)
		end
		if debrisByPlayer[player] ~= state then
			return
		end
		state.followUntil = os.clock() + GameConstants.MG_DEBRIS_HOLD_TIME
	end)
end

----------------------------------------------------------------
-- Telekinetic Area Lift (Marvel Girl skin only, key C)
-- Wrapped in one do...end block (locals inside don't count against this
-- file's top-level 200-local-register ceiling - see the CLAUDE.md note on
-- MarvelGirlService.luau) and hung off the existing Phoenix table instead of
-- adding fresh top-level locals.
----------------------------------------------------------------
type AreaLiftVictim = {
	model: Model,
	hum: Humanoid,
	root: BasePart,
	ownedParts: { BasePart },
	atts: { Attachment },
	aligns: { AlignPosition },
	savedAnchored: boolean,
	savedWalk: number,
	savedAutoRotate: boolean,
	fx: { Instance },
	released: boolean,
	orbitSpeed: number,
}

type AreaLiftState = {
	character: Model,
	root: BasePart,
	rootAtt: Attachment,
	rootAlign: AlignPosition,
	savedAnchored: boolean,
	savedWalk: number,
	savedJumpPower: number?,
	savedJumpHeight: number?,
	victims: { AreaLiftVictim },
	groundVfx: Instance?,
	animTrack: AnimationTrack?,
}

do
local areaLiftByPlayer: { [Player]: AreaLiftState } = {}
local areaLiftToken: { [Player]: number } = {}

-- Same fling as Cosmic Aura Burn's rootAlign, same fix - this ability owns
-- an equally rigid AlignPosition on the caster's root (RigidityEnabled,
-- MaxForce=1e6) that fights any ragdoll build the exact same way. Anchoring
-- everything briefly instead of just zeroing velocity/toggling CanCollide
-- avoids the sink-then-depenetrate launch (see the Cosmic Aura Burn hook's
-- own comment for the full reasoning).
RagdollService.onBeforeApply(function(character: Model)
	local player = Players:GetPlayerFromCharacter(character)
	local state = player and areaLiftByPlayer[player]
	if not state or not state.rootAlign then
		return
	end
	local rootAlign = state.rootAlign
	local rootAtt = state.rootAtt
	state.rootAlign = nil :: any
	state.rootAtt = nil :: any
	local anchoredParts: { BasePart } = {}
	for _, desc in character:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.AssemblyLinearVelocity = Vector3.zero
			desc.AssemblyAngularVelocity = Vector3.zero
			if not desc.Anchored then
				desc.Anchored = true
				table.insert(anchoredParts, desc)
			end
		end
	end
	task.delay(0.15, function()
		for _, part in anchoredParts do
			if part.Parent then
				part.Anchored = false
			end
		end
	end)
	if rootAlign and rootAlign.Parent then
		rootAlign:Destroy()
	end
	if rootAtt and rootAtt.Parent then
		rootAtt:Destroy()
	end
end)

local function setAreaLiftOwnership(model: Model): { BasePart }
	local parts: { BasePart } = {}
	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") then
			table.insert(parts, desc)
			pcall(function()
				desc:SetNetworkOwner(nil)
			end)
		end
	end
	return parts
end

local function restoreAreaLiftOwnership(model: Model, parts: { BasePart })
	local plr = Players:GetPlayerFromCharacter(model)
	for _, part in parts do
		if part.Parent then
			pcall(function()
				if plr then
					part:SetNetworkOwner(plr)
				else
					part:SetNetworkOwnershipAuto()
				end
			end)
		end
	end
end

-- Shared release path for one victim, used both for the early push (1s
-- before the ability naturally ends) and the normal end/interrupt path -
-- `released` guards against a victim getting torn down twice. Only the
-- early-push call actually pushes; the natural end never pushes on top of
-- that (it either already happened, or never applies for a victim who was
-- ragdolled/interrupted before the push moment).
local function releaseAreaLiftVictim(v: AreaLiftVictim, withPush: boolean, pushOrigin: Vector3?)
	if v.released then
		return
	end
	v.released = true
	for _, align in v.aligns do
		if align.Parent then
			align:Destroy()
		end
	end
	for _, att in v.atts do
		if att.Parent then
			att:Destroy()
		end
	end
	if v.fx then
		VfxHelper.fadeOutAndDestroyParticles(v.fx, 0.4, 3)
	end
	if not v.model.Parent then
		restoreAreaLiftOwnership(v.model, v.ownedParts)
		return
	end
	if v.root and v.root.Parent then
		v.root.Anchored = v.savedAnchored
	end
	v.model:SetAttribute(GameConstants.BUSY_ATTRIBUTE, nil)
	v.model:SetAttribute(GameConstants.POWERS_DISABLED_UNTIL, nil)
	if not v.hum.Parent or v.hum.Health <= 0 then
		restoreAreaLiftOwnership(v.model, v.ownedParts)
		return
	end
	v.hum.WalkSpeed = v.savedWalk
	v.hum.AutoRotate = v.savedAutoRotate
	-- Ragdoll BEFORE the push, not after: applyTimed builds fresh ragdoll
	-- constraints (RagdollService.apply), which - same fight PushHelper's
	-- own noRagdoll option exists to dodge - can reset/fight velocity while
	-- it settles. Push was called with noRagdoll=true specifically so it
	-- wouldn't ragdoll-on-top-of-itself, but this call right after it
	-- ragdolled her anyway every time, sometimes clobbering the throw right
	-- after it landed. Ragdolling first, then pushing last (right before
	-- ownership hands off) makes the push the final physics write, same
	-- principle as the ownership-restore-last fix below.
	RagdollService.applyTimed(v.model, GameConstants.MG_AREA_LIFT_RAGDOLL_SECONDS)
	if withPush and pushOrigin and v.root and v.root.Parent then
		local flat = Vector3.new(v.root.Position.X - pushOrigin.X, 0, v.root.Position.Z - pushOrigin.Z)
		local dir = if flat.Magnitude > 0.5 then flat.Unit else Vector3.new(0, 0, -1)
		PushHelper.applyToCharacter(v.model, dir, {
			speed = GameConstants.MG_AREA_LIFT_PUSH_SPEED,
			upBoost = GameConstants.MG_AREA_LIFT_PUSH_UP,
			noRagdoll = true,
		})
	else
		v.root.AssemblyLinearVelocity = Vector3.zero
		v.root.AssemblyAngularVelocity = Vector3.zero
	end
	-- Restore network ownership to the victim's own client LAST, after the
	-- push velocity is already set - handing physics control back first let
	-- the client's own simulation silently swallow a server-set velocity
	-- before it ever took effect, which read as "the push doesn't happen".
	restoreAreaLiftOwnership(v.model, v.ownedParts)
	-- Still reported missing sometimes even with ownership restored last -
	-- the handoff itself can race the very first replicated physics step,
	-- so the client's next frame can start from a stale pre-push velocity
	-- before the push ever reaches it. Re-assert once more a frame later,
	-- now that ownership has already settled, as a belt-and-suspenders
	-- resend rather than relying on a single write to survive the handoff.
	if withPush and pushOrigin and v.model.Parent and v.root.Parent then
		task.defer(function()
			if v.model.Parent and v.root.Parent and not v.root.Anchored then
				local flat = Vector3.new(v.root.Position.X - pushOrigin.X, 0, v.root.Position.Z - pushOrigin.Z)
				local dir = if flat.Magnitude > 0.5 then flat.Unit else Vector3.new(0, 0, -1)
				PushHelper.applyToCharacter(v.model, dir, {
					speed = GameConstants.MG_AREA_LIFT_PUSH_SPEED,
					upBoost = GameConstants.MG_AREA_LIFT_PUSH_UP,
					noRagdoll = true,
				})
			end
		end)
	end
end

function Phoenix.endTelekineticAreaLift(player: Player, applyCooldown: boolean)
	local state = areaLiftByPlayer[player]
	if not state then
		return
	end
	areaLiftByPlayer[player] = nil
	areaLiftToken[player] = (areaLiftToken[player] or 0) + 1

	if state.rootAlign and state.rootAlign.Parent then
		state.rootAlign:Destroy()
	end
	if state.rootAtt and state.rootAtt.Parent then
		state.rootAtt:Destroy()
	end
	local character = state.character
	if character.Parent then
		if state.root and state.root.Parent then
			state.root.Anchored = state.savedAnchored
		end
		local hum = CombatHelper.getHumanoid(character)
		if hum then
			hum.WalkSpeed = state.savedWalk
			if state.savedJumpPower ~= nil then
				hum.JumpPower = state.savedJumpPower
			end
			if state.savedJumpHeight ~= nil then
				hum.JumpHeight = state.savedJumpHeight
			end
			pcall(function()
				hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
			end)
		end
		character:SetAttribute(GameConstants.BUSY_ATTRIBUTE, nil)
		endPowerFx(character)
		Phoenix.removeMarvelGirlFlightEyes(character)
		if applyCooldown and AbilityCooldownHelper.isActive(character, "telekinetic_area_lift") then
			finishAbility(character, "telekinetic_area_lift", GameConstants.MG_AREA_LIFT_COOLDOWN)
		else
			AbilityCooldownHelper.setActive(character, "telekinetic_area_lift", false)
		end
	end
	if state.animTrack then
		state.animTrack:Stop(0.15)
		state.animTrack:Destroy()
	end
	if state.groundVfx and state.groundVfx.Parent then
		VfxHelper.retireFxSmooth(state.groundVfx, 0.9, 1.6)
	end

	-- Stagger the release like Mass Containment does - dropping every
	-- still-lifted victim in the same physics frame right before ragdoll's
	-- own push cascades their overlaps into each other instead of settling
	-- cleanly. Victims already released by the pre-end push (releaseAreaLift
	-- Victim's `released` guard) are skipped here - never pushed twice.
	--
	-- Fallback push (applyCooldown=true only, i.e. a natural completion, not
	-- MarvelGirlService.cancelAll's hard interrupt): the tick loop above is
	-- meant to push everyone away MG_AREA_LIFT_PUSH_LEAD before this runs,
	-- but if that check's timing ever missed (loop broke early, a straggler
	-- wasn't alive yet when checked, etc.) victims were silently dropped in
	-- place instead of thrown - "sometimes she doesn't throw them". This is
	-- the same origin/push used there, so any survivor still gets thrown
	-- even if the earlier tick never caught them.
	-- .Position is readable even if the root's Parent got cleared out from
	-- under it (a morph swap, etc.) between the last tick and here - gating
	-- on .Parent too made pushOrigin go nil for that case, which silently
	-- skipped the fallback push below for every still-lifted straggler
	-- exactly the "victims were silently dropped in place instead of thrown"
	-- failure the comment above already describes.
	local pushOrigin = state.root.Position
	local releaseIndex = 0
	for _, v in state.victims do
		local staggerDelay = releaseIndex * 0.08
		releaseIndex += 1
		task.delay(staggerDelay, function()
			releaseAreaLiftVictim(v, applyCooldown and pushOrigin ~= nil, pushOrigin)
		end)
	end
end

function Phoenix.castTelekineticAreaLift(player: Player)
	local character = player.Character
	if not character or areaLiftByPlayer[player] then
		return
	end
	if MarvelGirlService.lookOf(character) ~= "marvel_girl" then
		return
	end
	if character:GetAttribute(GameConstants.IS_FLYING_ATTRIBUTE) == true then
		return
	end
	local entry = CharacterRegistry.getAbilityById("jean_grey", "telekinetic_area_lift")
	-- energy=0 here: canUse would otherwise spend MG_AREA_LIFT_ENERGY itself
	-- as a side effect (see its last check) before the hasTarget empty-cast
	-- guard below even runs, then the explicit spendEnergy further down
	-- charged it AGAIN - double-spent, and spent even on a no-target cast.
	if not entry or not canUse(character, entry.id, 0) then
		return
	end
	local root = getRoot(character)
	if not root then
		return
	end
	-- Centered on the caster herself, not the cursor.
	local origin = root.Position
	-- Cosmic Aura Burn's own hold (MG_COSMIC_AURA_MAX_HOLD) minus
	-- MG_AREA_LIFT_DURATION_CUT, read directly from those constants rather
	-- than a separately hardcoded number, so it can't drift.
	-- +1: on top of Cosmic Aura Burn parity, by explicit request so the cast
	-- animation has room to play out fully.
	local liftDuration = GameConstants.MG_COSMIC_AURA_MAX_HOLD - GameConstants.MG_AREA_LIFT_DURATION_CUT + 1 - 1.5

	-- Nothing to lift - don't burn energy/cooldown on an empty cast (same
	-- convention as Mass Containment).
	local nearby = CombatHelper.overlapCharacters(origin, GameConstants.MG_AREA_LIFT_RADIUS, character)
	local hasTarget = false
	for _, victim in nearby do
		local vHum = CombatHelper.getHumanoid(victim)
		if not CombatHelper.isShielded(victim) and getRoot(victim) and vHum and vHum.Health > 0 then
			hasTarget = true
			break
		end
	end
	if not hasTarget then
		return
	end
	if not CharacterService.spendEnergy(character, GameConstants.MG_AREA_LIFT_ENERGY) then
		return
	end

	AbilityCooldownHelper.setActive(character, entry.id, true)
	attachPowerFx(character)
	Phoenix.attachMarvelGirlFlightEyes(character)
	character:SetAttribute(GameConstants.BUSY_ATTRIBUTE, true)
	-- Same cast animation and cast-feedback shake as Cosmic Aura Burn - it's
	-- the closest existing ability in shape (timed AoE, caster locked for the
	-- whole cast), so borrowing its anim/shake keeps the activation feeling
	-- consistent with the rest of the kit instead of popping in instantly.
	local animTrack = playJeanAnim(character, GameConstants.MG_COSMIC_AURA_ANIM, false)
	fireCameraShake(player, 0.4, 0.35, 0.3, 0.45)

	local hum = CombatHelper.getHumanoid(character)
	local savedWalk = if hum then hum.WalkSpeed else GameConstants.DEFAULT_WALK_SPEED
	local savedJumpPower: number? = nil
	local savedJumpHeight: number? = nil
	if hum then
		if hum.UseJumpPower then
			savedJumpPower = hum.JumpPower
		else
			savedJumpHeight = hum.JumpHeight
		end
		hum.WalkSpeed = 0
		hum.JumpPower = 0
		hum.JumpHeight = 0
		pcall(function()
			hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		end)
	end

	-- Own position outright (rigid AlignPosition) instead of just disabling
	-- movement input - same reasoning as Cosmic Aura Burn's rootAlign, so a
	-- stray hit during the cast can't fling her off her own AoE center.
	local savedAnchored = root.Anchored
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	local rootAtt = Instance.new("Attachment")
	rootAtt.Name = "MgAreaLiftCasterAtt"
	rootAtt.Parent = root
	local rootAlign = Instance.new("AlignPosition")
	rootAlign.Name = "MgAreaLiftCasterAlign"
	rootAlign.Mode = Enum.PositionAlignmentMode.OneAttachment
	rootAlign.Attachment0 = rootAtt
	rootAlign.ApplyAtCenterOfMass = true
	rootAlign.RigidityEnabled = true
	rootAlign.Responsiveness = 40
	rootAlign.MaxForce = 1e6
	rootAlign.MaxVelocity = 6
	rootAlign.Position = root.Position
	rootAlign.Parent = root

	-- Body particles/beams for every lifted victim, sourced from the same
	-- morph asset (matched to each victim's body parts by name, same helper
	-- used for telekinesis/revive morphs) instead of a bespoke VFX list.
	local liftTemplate = VfxHelper.getMarvelGirlAsset("TelekineticAreaLift", "TelekineticAreaLiftTarget")

	-- Ground-level AoE marker at the caster's feet, snapped down to the
	-- actual floor beneath her (not just root height) the same way other
	-- ground VFX in this file resolve their spawn position.
	local groundVfx: Instance? = nil
	local groundTemplate = VfxHelper.getMarvelGirlAsset("TelekineticAreaLift", "TelekineticLiftVFX")
	if groundTemplate then
		local groundPos = VfxHelper.snapToFloor(origin)
		local clone = groundTemplate:Clone()
		clone.Name = "MgAreaLiftGroundVfx"
		if clone:IsA("BasePart") then
			clone.Anchored = true
			clone.CanCollide = false
			clone.CanQuery = false
			clone.CanTouch = false
			clone.CFrame = CFrame.new(groundPos)
			clone.Parent = Workspace
			groundVfx = clone
		elseif clone:IsA("Model") then
			clone.Parent = Workspace
			clone:PivotTo(CFrame.new(groundPos))
			groundVfx = clone
		else
			local host = Instance.new("Part")
			host.Name = "MgAreaLiftGroundVfxHost"
			host.Size = Vector3.new(0.2, 0.2, 0.2)
			host.Transparency = 1
			host.Anchored = true
			host.CanCollide = false
			host.CanQuery = false
			host.CanTouch = false
			host.CFrame = CFrame.new(groundPos)
			host.Parent = Workspace
			clone.Parent = host
			groundVfx = host
		end
		VfxHelper.setParticlesEnabled(groundVfx, true)
		VfxHelper.emitAllParticles(groundVfx, 12)
	end

	local victims: { AreaLiftVictim } = {}
	for _, victimModel in nearby do
		if CombatHelper.isShielded(victimModel) then
			continue
		end
		local vRoot = getRoot(victimModel)
		local vHum = CombatHelper.getHumanoid(victimModel)
		if not vRoot or not vHum or vHum.Health <= 0 then
			continue
		end
		local ownedParts = setAreaLiftOwnership(victimModel)
		local vSavedAnchored = vRoot.Anchored
		vRoot.Anchored = false
		vRoot.AssemblyLinearVelocity = Vector3.zero
		local savedVWalk = vHum.WalkSpeed
		local savedVAutoRotate = vHum.AutoRotate
		vHum.WalkSpeed = 0
		vHum.AutoRotate = false

		victimModel:SetAttribute(GameConstants.BUSY_ATTRIBUTE, true)
		victimModel:SetAttribute(GameConstants.POWERS_DISABLED_UNTIL, AbilityCooldownHelper.getNow() + liftDuration)
		-- BUSY/POWERS_DISABLED only block *new* casts - cut anything already
		-- mid-cast the same way Mass Containment does.
		RagdollService.interruptAbilities(victimModel)
		-- Ragdoll BEFORE the lift aligns below are created (same order
		-- Chaotic Revive's ragdoll-then-float uses) - a limp body hoisted by
		-- the align reads as actually telekinetically grabbed, not just
		-- frozen in place. Timed to cover the whole lift plus the release
		-- settle so it can't wear off mid-air; releaseAreaLiftVictim's own
		-- applyTimed call at the end just re-times it down to the short
		-- settle window.
		RagdollService.applyTimed(victimModel, liftDuration + GameConstants.MG_AREA_LIFT_RAGDOLL_SECONDS + 1)

		-- One AlignPosition per limb, not just the root - once ragdolled,
		-- every limb is its own separate physics Assembly connected only by
		-- loose BallSocketConstraints (same reasoning as PushHelper.
		-- applyToCharacter's own per-limb velocity set). An align on just
		-- the root only tugs the root; the still-near-zero limbs yank it
		-- back down through their constraints, which read as "just ragdolls,
		-- never actually lifts". Each limb aligns to its OWN position plus
		-- the same vertical offset, so the whole loose body rises together.
		local atts: { Attachment } = {}
		local aligns: { AlignPosition } = {}
		for _, part in victimModel:GetDescendants() do
			if part:IsA("BasePart") and not part.Anchored then
				local partAtt = Instance.new("Attachment")
				partAtt.Name = "MgAreaLiftAtt"
				partAtt.Parent = part
				local partAlign = Instance.new("AlignPosition")
				partAlign.Name = "MgAreaLiftAlign"
				partAlign.Mode = Enum.PositionAlignmentMode.OneAttachment
				partAlign.Attachment0 = partAtt
				partAlign.ApplyAtCenterOfMass = true
				partAlign.RigidityEnabled = false
				partAlign.Responsiveness = GameConstants.MG_AREA_LIFT_ALIGN_RESPONSIVENESS
				partAlign.MaxForce = GameConstants.MG_AREA_LIFT_ALIGN_MAX_FORCE
				partAlign.MaxVelocity = 40
				partAlign.Position = part.Position + Vector3.new(0, GameConstants.MG_AREA_LIFT_HEIGHT, 0)
				partAlign.Parent = part
				table.insert(atts, partAtt)
				table.insert(aligns, partAlign)
			end
		end

		local fx: { Instance } = {}
		if liftTemplate then
			fx = VfxHelper.attachMorphParticles(victimModel, liftTemplate)
		end

		table.insert(victims, {
			model = victimModel,
			hum = vHum,
			root = vRoot,
			ownedParts = ownedParts,
			atts = atts,
			aligns = aligns,
			savedAnchored = vSavedAnchored,
			savedWalk = savedVWalk,
			savedAutoRotate = savedVAutoRotate,
			fx = fx,
			released = false,
			orbitSpeed = (GameConstants.MG_AREA_LIFT_SPIN_MIN
				+ math.random() * (GameConstants.MG_AREA_LIFT_SPIN_MAX - GameConstants.MG_AREA_LIFT_SPIN_MIN))
				* (if math.random() < 0.5 then -1 else 1),
		})
	end

	local token = (areaLiftToken[player] or 0) + 1
	areaLiftToken[player] = token
	areaLiftByPlayer[player] = {
		character = character,
		root = root,
		rootAtt = rootAtt,
		rootAlign = rootAlign,
		savedAnchored = savedAnchored,
		savedWalk = savedWalk,
		savedJumpPower = savedJumpPower,
		savedJumpHeight = savedJumpHeight,
		victims = victims,
		groundVfx = groundVfx,
		animTrack = animTrack,
	}

	-- Orbit each lifted victim around Jean while held - rotates every limb
	-- align's current target around her (root/origin) each frame by that
	-- victim's own random speed/direction, on top of whatever height/spread
	-- the per-limb aligns above already gave it, instead of just hanging
	-- there motionless.
	-- She floats too while lifting them - smoothly (eased over
	-- CASTER_FLOAT_RISE_TIME), not as high as the victims, half of
	-- MG_AREA_LIFT_HEIGHT. rootAlign stays RigidityEnabled=true throughout
	-- (still immune to a stray hit flinging her off-center) - only the
	-- *target* position it holds eases upward each frame, not the align mode.
	local casterFloatStart = os.clock()
	local CASTER_FLOAT_RISE_TIME = 0.6
	local casterFloatTargetY = origin.Y + GameConstants.MG_AREA_LIFT_HEIGHT / 2

	local spinConn: RBXScriptConnection? = nil
	spinConn = RunService.Heartbeat:Connect(function(dt)
		if areaLiftToken[player] ~= token or not character.Parent then
			if spinConn then
				spinConn:Disconnect()
			end
			return
		end
		if rootAlign.Parent then
			local floatA = math.clamp((os.clock() - casterFloatStart) / CASTER_FLOAT_RISE_TIME, 0, 1)
			local ease = floatA * floatA * (3 - 2 * floatA)
			rootAlign.Position = Vector3.new(origin.X, origin.Y + (casterFloatTargetY - origin.Y) * ease, origin.Z)
		end
		for _, v in victims do
			if not v.released then
				local deltaAngle = v.orbitSpeed * dt
				local cosA, sinA = math.cos(deltaAngle), math.sin(deltaAngle)
				for _, align in v.aligns do
					local p = align.Position
					local dx, dz = p.X - origin.X, p.Z - origin.Z
					local nx = dx * cosA - dz * sinA
					local nz = dx * sinA + dz * cosA
					align.Position = Vector3.new(origin.X + nx, p.Y, origin.Z + nz)
				end
			end
		end
	end)

	task.spawn(function()
		local elapsed = 0
		local duration = liftDuration
		local pushed = false
		while elapsed < duration do
			task.wait(GameConstants.MG_AREA_LIFT_TICK)
			elapsed += GameConstants.MG_AREA_LIFT_TICK
			if areaLiftToken[player] ~= token or not character.Parent then
				return
			end
			-- Push everyone still lifted away MG_AREA_LIFT_PUSH_LEAD seconds
			-- before the natural end, instead of at the very end - the final
			-- release (below/endTelekineticAreaLift) never pushes on top of
			-- this, releaseAreaLiftVictim's `released` guard prevents that.
			if not pushed and elapsed >= duration - GameConstants.MG_AREA_LIFT_PUSH_LEAD then
				pushed = true
				for _, v in victims do
					if not v.released and v.model.Parent and v.hum.Parent and v.hum.Health > 0 then
						releaseAreaLiftVictim(v, true, origin)
					end
				end
			end
			local anyAlive = false
			for _, v in victims do
				if not v.released and v.model.Parent and v.hum.Parent and v.hum.Health > 0 then
					anyAlive = true
					if not CombatHelper.isShielded(v.model) then
						CombatHelper.dealDamage(
							character,
							v.model,
							GameConstants.MG_AREA_LIFT_DAMAGE_PER_TICK,
							v.root.Position,
							"beam"
						)
					end
				end
			end
			-- Only bail early for "everyone died/left" - once the scheduled
			-- pre-end push above has released them (`pushed`), anyAlive going
			-- false is expected (that's the intended end-of-lift release, not
			-- an empty cast) and must NOT cut the ability/animation short.
			if not pushed and not anyAlive then
				break
			end
		end
		if areaLiftToken[player] == token then
			Phoenix.endTelekineticAreaLift(player, true)
		end
	end)
end
end

----------------------------------------------------------------
-- Public API
----------------------------------------------------------------
function MarvelGirlService.cancelAll(player: Player)
	HexFlightService.endFlight(player, false)
	Phoenix.endTelekineticAreaLift(player, false)
	stopBarrier(player, false)
	-- Must go through stopTelepathicPain (not just clear the cooldown-active
	-- flag below) so painByPlayer state and the victim's screen-hold/tint
	-- attributes actually get released too.
	stopTelepathicPain(player, false)
	Phoenix.stopPain(player, false)
	Phoenix.stopAuraBurn(player, false)
	endAstral(player, false, true)
	endMindLink(player, false, false)
	endSlam(player, false, false)
	if debrisByPlayer[player] then
		endDebris(player, false, true)
	end
	TelekinesisService.release(player)
	unfreezeBody(player, player.Character)
	unlockSlamCaster(player, player.Character)
	local char = player.Character
	if char then
		setVictimControlled(char, false)
		clearPowerFx(char)
		CastFaceHelper.cancelPending(char)
		CastFaceHelper.destroyHold(char)
		CastFaceHelper.destroyContinuous(char)
		local root = getRoot(char)
		if root then
			for _, name in { "TKCasterFaceAlign", "TKCasterFaceAttachment" } do
				local inst = root:FindFirstChild(name)
				if inst then
					inst:Destroy()
				end
			end
		end
		local hum = CombatHelper.getHumanoid(char)
		if hum and char:GetAttribute(GameConstants.IS_FLYING_ATTRIBUTE) ~= true then
			hum.AutoRotate = true
		end
		AbilityCooldownHelper.setActive(char, "psionic_bolt", false)
		AbilityCooldownHelper.setActive(char, "psychic_pull", false)
		AbilityCooldownHelper.setActive(char, "telekinesis", false)
		AbilityCooldownHelper.setActive(char, "telekinetic_slam", false)
		AbilityCooldownHelper.setActive(char, "telekinetic_debris", false)
		AbilityCooldownHelper.setActive(char, "telepathic_pain", false)
		AbilityCooldownHelper.setActive(char, "telepathic_outburst", false)
		-- Phoenix Wrath's whole float/hover/unleash sequence has no
		-- interrupt/cancel path of its own (unlike Cosmic Aura Burn's
		-- phoenixAuraToken) - an interrupt (ragdoll, etc) mid-sequence left
		-- AbilityActive_phoenix_wrath stuck true forever, which reads as the
		-- ability icon's readiness fill never progressing again (GameplayHUD/
		-- MobileAbilityRingClient force it to 0 while active).
		AbilityCooldownHelper.setActive(char, "phoenix_wrath", false)
		char:SetAttribute("MgSlamAim", nil)
		char:SetAttribute("MgDebrisAim", nil)
		-- Blanket safety net: Psionic Bolt's windup, the hair toggle, and
		-- overload-wake all set BUSY_ATTRIBUTE true but only clear it from
		-- their own delayed/async completion callback, with no cancel path
		-- reachable from here - without this, an interrupt (e.g. ragdoll)
		-- mid-windup/mid-delay leaves BUSY stuck true.
		char:SetAttribute(GameConstants.BUSY_ATTRIBUTE, nil)
		-- Also invalidates a mid-windup Psionic Bolt's delayed WalkSpeed
		-- restore (see castPsionicBolt) so it can't clobber a newer
		-- WalkSpeed/JumpPower lock set after this interrupt. Restore the
		-- windup's own saved values here first, since invalidating the token
		-- makes castPsionicBolt's delayed restore a no-op - without this a
		-- ragdoll/interrupt mid-windup left her stuck at 0 WalkSpeed/JumpPower.
		local savedBoltWalk = char:GetAttribute("MgBoltWindupWalk")
		if savedBoltWalk ~= nil then
			local hum = CombatHelper.getHumanoid(char)
			if hum then
				hum.WalkSpeed = savedBoltWalk
				local savedBoltJump = char:GetAttribute("MgBoltWindupJump")
				if savedBoltJump ~= nil then
					hum.JumpPower = savedBoltJump
				end
				local savedBoltJumpHeight = char:GetAttribute("MgBoltWindupJumpHeight")
				if savedBoltJumpHeight ~= nil then
					pcall(function()
						hum.JumpHeight = savedBoltJumpHeight
					end)
				end
				pcall(function()
					hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
				end)
			end
			char:SetAttribute("MgBoltWindupWalk", nil)
			char:SetAttribute("MgBoltWindupJump", nil)
			char:SetAttribute("MgBoltWindupJumpHeight", nil)
		end
		char:SetAttribute("MgBoltWindupToken", (char:GetAttribute("MgBoltWindupToken") or 0) + 1)
	end
end

----------------------------------------------------------------
-- Psychic Current (X-Men Red skin, Z - replaces Telekinetic Debris on that skin only): a single
-- forward current, not a sustained beam - looks like one (particles + beam fx at both ends) but
-- resolves instantly, stopping at the first thing in its way instead of tracking a live target.
----------------------------------------------------------------
local function castPsychicCurrent(player: Player, _direction: Vector3?, _aimPoint: Vector3?)
	local character = player.Character
	if not character then
		return
	end
	if character:GetAttribute(GameConstants.IS_FLYING_ATTRIBUTE) == true then
		return
	end
	local entry = CharacterRegistry.getAbilityById("jean_grey", "psychic_current")
	if not entry or not canUse(character, entry.id, entry.energyCost) then
		return
	end
	local root = getRoot(character)
	if not root then
		return
	end

	-- Straight ahead of the character, regardless of cursor position or target lock (per request).
	local forward = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	forward = if forward.Magnitude > 0.05 then forward.Unit else Vector3.new(0, 0, -1)

	local startTemplate = VfxHelper.getMarvelGirlAsset("JeanGreyXMenRed", "PsychicCurrent", "StartAttachment")
	local endTemplate = VfxHelper.getMarvelGirlAsset("JeanGreyXMenRed", "PsychicCurrent", "EndAttachment")
	if not startTemplate or not startTemplate:IsA("Attachment") or not endTemplate or not endTemplate:IsA("Attachment") then
		warn("[MarvelGirl] Missing Assets.JeanGrey.JeanGreyXMenRed.PsychicCurrent.StartAttachment/EndAttachment")
		return
	end

	fireCameraShake(player, 0.3, 0.4, 0.2, 0.3)
	AbilityCooldownHelper.setActive(character, entry.id, true)
	CharacterService.markAbilityUse(character)

	local origin = root.Position + Vector3.new(0, 1, 0)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local ray = Workspace:Raycast(origin, forward * GameConstants.MG_PSYCHIC_CURRENT_RANGE, params)
	local endPos = if ray then ray.Position else origin + forward * GameConstants.MG_PSYCHIC_CURRENT_RANGE

	local FX_DURATION = 1 -- was 1.5, a bit shorter per request
	local FX_FADE = 0.4

	-- Rooted for the current's duration, per request.
	local hum = CombatHelper.getHumanoid(character)
	local savedWalk = if hum then hum.WalkSpeed else GameConstants.DEFAULT_WALK_SPEED
	local savedAutoRotate = if hum then hum.AutoRotate else true
	if hum then
		hum.WalkSpeed = 0
		hum.AutoRotate = false
	end
	character:SetAttribute(GameConstants.MOVEMENT_SLOWED_ATTRIBUTE, true)

	local startAtt = startTemplate:Clone() :: Attachment
	startAtt.Parent = root
	startAtt.CFrame = CFrame.new(0, 0, -2)
	VfxHelper.setParticlesEnabled(startAtt, true)
	VfxHelper.emitAllParticles(startAtt, 20)

	local endHost = Instance.new("Part")
	endHost.Name = "PsychicCurrentEndHost"
	endHost.Anchored = true
	endHost.CanCollide = false
	endHost.CanQuery = false
	endHost.CanTouch = false
	endHost.Transparency = 1
	endHost.Size = Vector3.new(0.2, 0.2, 0.2)
	endHost.CFrame = CFrame.new(endPos)
	endHost.Parent = Workspace
	local endAtt = endTemplate:Clone() :: Attachment
	endAtt.Parent = endHost
	VfxHelper.setParticlesEnabled(endAtt, true)
	VfxHelper.emitAllParticles(endAtt, 20)

	-- Wire the current across both ends - whichever side the beam is authored on, force both of its
	-- attachments so it actually spans start to end instead of sitting unconnected on one side.
	for _, inst in startAtt:GetDescendants() do
		if inst:IsA("Beam") then
			inst.Attachment0 = startAtt
			inst.Attachment1 = endAtt
			inst.Enabled = true
		end
	end
	for _, inst in endAtt:GetDescendants() do
		if inst:IsA("Beam") then
			inst.Attachment0 = endAtt
			inst.Attachment1 = startAtt
			inst.Enabled = true
		end
	end

	task.delay(FX_DURATION, function()
		if character.Parent then
			local humNow = CombatHelper.getHumanoid(character)
			if humNow then
				humNow.WalkSpeed = savedWalk
				humNow.AutoRotate = savedAutoRotate
			end
			character:SetAttribute(GameConstants.MOVEMENT_SLOWED_ATTRIBUTE, nil)
		end
		-- Particles/beams fade first, the hosting parts disappear once that's done.
		if startAtt.Parent then
			VfxHelper.smoothDisableParticles(startAtt, FX_FADE)
		end
		if endAtt.Parent then
			VfxHelper.smoothDisableParticles(endAtt, FX_FADE)
		end
		task.delay(FX_FADE, function()
			if startAtt.Parent then
				startAtt:Destroy()
			end
			if endHost.Parent then
				endHost:Destroy()
			end
		end)
	end)

	for _, victim in CombatHelper.overlapCharacters(endPos, GameConstants.MG_PSYCHIC_CURRENT_DAMAGE_RADIUS, character) do
		local vRoot = getRoot(victim)
		if not vRoot or CombatHelper.isShielded(victim) then
			continue
		end
		CombatHelper.dealDamage(character, victim, GameConstants.MG_PSYCHIC_CURRENT_DAMAGE, endPos, "psychic")
		RagdollService.applyTimed(victim, GameConstants.MG_PSYCHIC_CURRENT_RAGDOLL)
		local away = vRoot.Position - endPos
		PushHelper.applyToCharacter(victim, if away.Magnitude > 0.05 then away.Unit else forward, {
			speed = GameConstants.MG_PSYCHIC_CURRENT_PUSH_SPEED,
			upBoost = GameConstants.MG_PSYCHIC_CURRENT_PUSH_UP,
			noRagdoll = true,
		})
	end

	finishAbility(character, entry.id, entry.cooldown)
end

function MarvelGirlService.handleAction(player: Player, payload: any)
	if type(payload) ~= "table" then
		return
	end
	local character = player.Character
	if not character or character:GetAttribute(GameConstants.HERO_ATTRIBUTE) ~= "jean_grey" then
		return
	end
	if character:GetAttribute(GameConstants.RAGDOLLED_ATTRIBUTE) == true then
		return
	end
	if character:GetAttribute(GameConstants.MG_OVERLOAD_ATTRIBUTE) == true then
		return
	end
	-- While controlled / slam-held as a victim, block ability input (caster BUSY is fine for own casts)
	if character:GetAttribute(GameConstants.MG_TK_CONTROLLED_ATTRIBUTE) == true
		or character:GetAttribute(GameConstants.MG_SLAM_HELD_ATTRIBUTE) == true
	then
		local action = payload.action
		if action ~= "Q_up" and action ~= "Z_up" then
			return
		end
	end

	local isPhoenix = GameConstants.PHOENIX_LOOK_IDS[MarvelGirlService.lookOf(character)] == true
	local isXMenRed = MarvelGirlService.lookOf(character) == "xmen_red"
	-- While Telepathic Pain is running nothing else can be used (flight included) - only T, which ends it early.
	if isPhoenix and phoenixPainByPlayer[player] and payload.action ~= "T" then
		return
	end
	if isPhoenix then
		-- Phoenix's kit is Bolt/Barrier/Flight/Telekinesis (unchanged) + Meteor
		-- Shower/Telepathic Pain/Cosmic Aura Burn/Phoenix Wrath/Flame Combo/
		-- Molecular Eradication (X/T/Z/G/B/V below) - Astral Projection (and
		-- every hold/aim/scroll sub-action of the old Slam/Debris keys they
		-- share) never existed for this skin. "V" is NOT excluded here (only
		-- "H" is) - base Jean's astral bind is H/V both, but Phoenix reuses V
		-- for Molecular Eradication, so only H should still fall through to
		-- startAstral below. R (Telekinesis) is NOT excluded either - Phoenix
		-- keeps it exactly as base Jean has it, so R/R_down/R_up/etc fall
		-- through to the shared startJeanTelekinesis/releaseJeanTelekinesis
		-- branches below.
		local a = payload.action
		if a == "E_scroll"
			or a == "H"
			or a == "Z_throw" or a == "Z_aim"
			or a == "X_down" or a == "X_up" or a == "X_throw"
			or a == "telekinetic_debris_cancel"
		then
			return
		end
		-- Z_down/Z_up are NOT excluded here (unlike telekinetic_debris' other
		-- sub-actions) - Cosmic Aura Burn is a hold ability sharing the same
		-- physical Z key, so it needs those to reach the Z_down/Z_up branches
		-- below instead of being silently swallowed.
		-- X_aim/T_aim fall through below: for base Jean they only update
		-- MgSlamAim while telekinetic_slam is active, which never happens for
		-- Phoenix, so they're harmless there - Phoenix instead uses X_aim to
		-- live-update Meteor Shower's aim (see the X_aim branch below).
	end

	-- While in astral, H/V returns; Q hold pain / B outburst (barrier is
	-- unavailable in astral, so Q is free to mean pain here instead).
	if astralByPlayer[player] then
		local direction = if typeof(payload.direction) == "Vector3" then payload.direction else nil
		local aimPoint = if typeof(payload.aimPoint) == "Vector3" then payload.aimPoint else nil
		local target = if typeof(payload.target) == "Instance" and payload.target:IsA("Model") then payload.target else nil
		local lockOn = payload.softLock == true
		if payload.action == "H" or payload.action == "V" then
			endAstral(player, true)
		elseif payload.action == "Q_up" then
			stopTelepathicPain(player, true)
		elseif payload.action == "Q_down" then
			startTelepathicPain(player, target, direction, aimPoint, lockOn)
		elseif payload.action == "Q" then
			if painByPlayer[player] then
				stopTelepathicPain(player, true)
			else
				startTelepathicPain(player, target, direction, aimPoint, lockOn)
			end
		elseif payload.action == "B" or payload.action == "B_down" then
			castTelepathicOutburst(player)
		elseif payload.action == "J" then
			playJeanHairToggle(player, character)
		end
		return
	end

	local action = payload.action
	-- Barrier holds: release (Q_up) or astral (H); other abilities blocked
	local darkShieldUp = character:GetAttribute("MgDarkPhoenix") == true
	if not darkShieldUp and (barrierByPlayer[player] or character:GetAttribute(GameConstants.MG_BARRIER_ATTRIBUTE) == true) then
		if action == "Q_up" then
			stopBarrier(player, true)
		elseif action == "H" or action == "V" then
			startAstral(player)
		elseif action == "J" then
			playJeanHairToggle(player, character)
		end
		return
	end

	local direction = if typeof(payload.direction) == "Vector3" then payload.direction else nil
	local aimPoint = if typeof(payload.aimPoint) == "Vector3" then payload.aimPoint else nil
	local target = if typeof(payload.target) == "Instance" and payload.target:IsA("Model") then payload.target else nil
	local lockOn = payload.softLock == true
	local hitPart = if typeof(payload.hitPart) == "Instance" and payload.hitPart:IsA("BasePart")
		then payload.hitPart
		else nil

	if action == "Q_down" or action == "Q" then
		-- Dark Phoenix: Q toggles the Cosmic Shield on / off. Everyone else: hold.
		if darkShieldUp and barrierByPlayer[player] then
			stopBarrier(player, true)
		else
			startBarrier(player)
		end
	elseif action == "Q_up" and darkShieldUp then
		-- Toggle, not a hold - releasing the key does nothing.
	elseif action == "Q_up" then
		stopBarrier(player, true)
	elseif action == "E" then
		castPsionicBolt(player, direction, aimPoint)
	elseif action == "E_aim" or action == "Q_aim" then
		if AbilityCooldownHelper.isActive(character, "psionic_bolt") and aimPoint then
			character:SetAttribute("MgBoltAim", aimPoint)
		end
	elseif action == "T" and isPhoenix then
		-- Timed (max MG_PHOENIX_PAIN_DURATION) but a second press ends it early, so she can never be stuck in it.
		if phoenixPainByPlayer[player] then
			Phoenix.stopPain(player, true)
		else
			Phoenix.startPain(player, target, direction, aimPoint, lockOn)
		end
	elseif action == "T" then
		castPsychicPull(player, target, direction, aimPoint, lockOn, hitPart)
	elseif action == "R_down" then
		startJeanTelekinesis(player, target, aimPoint, hitPart, lockOn)
	elseif action == "R_up" then
		-- Releasing R with no click just drops what's held - it does NOT
		-- throw. Throw only fires from an explicit mouse click while held
		-- (R_throw below, sent by AbilityInput's MouseButton1 handler).
		releaseJeanTelekinesis(player)
	elseif action == "R_scroll" or action == "E_scroll" then
		if type(payload.scroll) == "number" then
			TelekinesisService.adjustDistance(player, payload.scroll)
		end
		if aimPoint then
			TelekinesisService.updateAim(player, aimPoint)
		end
	elseif action == "R_throw" then
		throwJeanTelekinesis(player, target, direction, aimPoint)
	elseif action == "R" then
		-- HUD tap: start hold if idle
		if not TelekinesisService.isActive(player) then
			startJeanTelekinesis(player, target, aimPoint, hitPart, lockOn)
		end
	elseif action == "F" then
		HexFlightService.toggleFlight(player)
	elseif action == "X" and isPhoenix then
		Phoenix.castMeteorShower(player, aimPoint)
	elseif action == "X" then
		castTelekineticSlam(player, target, direction, aimPoint, lockOn)
	elseif action == "X_aim" or action == "T_aim" then
		if AbilityCooldownHelper.isActive(character, "telekinetic_slam") and aimPoint then
			character:SetAttribute("MgSlamAim", aimPoint)
		end
		if AbilityCooldownHelper.isActive(character, "meteor_shower") and aimPoint then
			character:SetAttribute("MgMeteorAim", aimPoint)
		end
	elseif action == "Z_down" and isPhoenix then
		Phoenix.startAuraBurn(player)
	elseif action == "Z_up" and isPhoenix then
		-- No longer a hold ability - releasing the key does not cut it
		-- short. Once activated it always runs its full duration (see
		-- Phoenix.startAuraBurn's own task.spawn loop), the only way to end
		-- it early is the ragdoll/ability-interrupt path.
	elseif action == "Z" and isXMenRed then
		castPsychicCurrent(player, direction, aimPoint)
	elseif action == "Z_down" or action == "X_down" then
		castTelekineticDebris(player, aimPoint)
	elseif action == "Z_up" or action == "X_up" then
		releaseDebrisHold(player)
	elseif action == "Z_throw" or action == "X_throw" then
		throwNextDebris(player, direction, aimPoint)
	elseif action == "telekinetic_debris_cancel" then
		endDebris(player, true, true)
	elseif action == "Z" and isPhoenix then
		-- HUD tap fallback: only starts it if idle - re-tapping while it's
		-- already running does nothing (not a hold/toggle anymore).
		if not phoenixAuraByPlayer[player] then
			Phoenix.startAuraBurn(player)
		end
	elseif action == "Z" then
		-- Legacy tap: start hold if idle
		if not debrisByPlayer[player] then
			castTelekineticDebris(player, aimPoint)
		end
	elseif action == "B" and isPhoenix then
		Phoenix.castWrath(player)
	elseif action == "Z_aim" then
		if AbilityCooldownHelper.isActive(character, "telekinetic_debris") and aimPoint then
			character:SetAttribute("MgDebrisAim", aimPoint)
			local st = debrisByPlayer[player]
			if st then
				st.aimPoint = aimPoint
			end
		end
	elseif action == "V" and isPhoenix then
		Phoenix.castMolecularEradication(player, target, direction, aimPoint, lockOn)
	elseif action == "H" or action == "V" then
		startAstral(player)
	elseif action == "G" and isPhoenix then
		Phoenix.castFlameCombo(player, target, direction, aimPoint, lockOn)
	elseif action == "G" then
		-- Manual mind link: start / add target (close only via chat X)
		local hitPart = if typeof(payload.hitPart) == "Instance" then payload.hitPart else nil
		local jeanRoot = getRoot(character)
		local aimTarget = target
		if jeanRoot then
			local resolved = resolveCursorTarget(
				character,
				jeanRoot,
				target,
				hitPart,
				direction,
				aimPoint,
				GameConstants.MG_MIND_LINK_RANGE,
				lockOn
			)
			if resolved then
				aimTarget = resolved
			end
		end
		if not aimTarget and hitPart then
			local model = CombatHelper.getCharacterFromPart(if hitPart:IsA("BasePart") then hitPart else nil)
			if model then
				aimTarget = model
			elseif hitPart.Name == "MindLinker" or (hitPart.Parent and hitPart.Parent.Name == "MindLinker") then
				aimTarget = nil
				if mindLinkByPlayer[player] then
					local st = mindLinkByPlayer[player]
					if st and not st.linkerIncluded then
						local now = os.clock()
						if (mindLinkAddCd[player] or 0) <= now then
							st.linkerIncluded = true
							mindLinkAddCd[player] = now + GameConstants.MG_MIND_LINK_ADD_COOLDOWN
							broadcastMembers(st)
							local linker = Workspace:FindFirstChild("MindLinker")
							if linker then
								addMindLinkTargetVfx(st, linker)
							end
							return
						end
					end
				end
			end
		end
		startMindLink(player, aimTarget)
	elseif action == "C" and not isPhoenix then
		Phoenix.castTelekineticAreaLift(player)
	elseif action == "J" then
		playJeanHairToggle(player, character)
	end
end

-- Astral flight used to spend energy and rewrite 3 replicated attributes EVERY frame per astral player (60 replication
-- updates/s each, the residual lag). Both are batched to ~20Hz now; weak-keyed so a leaving player leaves no entry.
Phoenix.astralDrainAcc = setmetatable({}, { __mode = "k" }) :: { [Player]: number }
Phoenix.astralAttrAt = setmetatable({}, { __mode = "k" }) :: { [Player]: number }

function MarvelGirlService.update(dt: number)
	local dtClamped = math.clamp(dt, 0.001, 0.1)

	Phoenix.updateTkBurn(dtClamped)

	for _, state in slamByPlayer do
		if state.character.Parent then
			applySlamCasterLock(state.character)
		end
	end

	for player in painByPlayer do
		updateTelepathicPain(player, dtClamped)
	end

	for player in phoenixPainByPlayer do
		Phoenix.updatePain(player, dtClamped)
	end

	Phoenix.updateEradication(dtClamped)

	-- Astral flight (HexFlight feel) + energy drain; skip while returning
	for player, state in astralByPlayer do
		if not state.astral.Parent or not state.body.Parent then
			endAstral(player, true, true)
			continue
		end
		if state.returning then
			continue
		end
		local energy = state.body:GetAttribute(GameConstants.ENERGY_ATTRIBUTE)
		if type(energy) ~= "number" or energy <= 0 then
			endAstral(player, true)
			continue
		end
		local drainAcc = (Phoenix.astralDrainAcc[player] or 0) + GameConstants.MG_ASTRAL_ENERGY_PER_SEC * dtClamped
		if drainAcc >= GameConstants.MG_ASTRAL_ENERGY_PER_SEC * 0.05 then
			Phoenix.astralDrainAcc[player] = 0
			if not CharacterService.spendEnergy(state.body, math.min(drainAcc, energy)) then
				endAstral(player, true)
				continue
			end
		else
			Phoenix.astralDrainAcc[player] = drainAcc
		end
		if os.clock() - state.startedAt >= GameConstants.MG_ASTRAL_DURATION then
			endAstral(player, true)
			continue
		end

		-- forceAstralNoclip(state.astral) used to run here every tick - the
		-- clone is already fully stripped once at creation, and its
		-- DescendantAdded listener strips any part added afterward, so a
		-- full GetDescendants() rescan every single frame for every astral
		-- player was pure waste (the residual per-frame lag).

		if state.outbursting then
			state.moveDir = Vector3.zero
			state.currentVel = Vector3.zero
			state.mover.linearVelocity.VectorVelocity = Vector3.zero
			if state.mover.vectorForce then
				state.mover.vectorForce.Force = Vector3.new(0, state.root.AssemblyMass * Workspace.Gravity, 0)
			end
			local hold = state.outburstHoldCf
			if hold then
				state.root.CFrame = hold
			end
			state.root.AssemblyLinearVelocity = Vector3.zero
			state.root.AssemblyAngularVelocity = Vector3.zero
			continue
		end

		local pain = painByPlayer[player]
		if pain then
			state.moveDir = Vector3.zero
			state.currentVel = Vector3.zero
			state.mover.linearVelocity.VectorVelocity = Vector3.zero
			if state.mover.vectorForce then
				state.mover.vectorForce.Force = Vector3.new(0, state.root.AssemblyMass * Workspace.Gravity, 0)
			end
			state.root.AssemblyLinearVelocity = Vector3.zero
			state.root.AssemblyAngularVelocity = Vector3.zero
			local lookPos = pain.victim:FindFirstChild("HumanoidRootPart")
			local lookAt = if lookPos and lookPos:IsA("BasePart") then lookPos.Position else nil
			if typeof(lookAt) ~= "Vector3" then
				local attr = state.body:GetAttribute(GameConstants.MG_PAIN_LOOK_ATTRIBUTE)
				if typeof(attr) == "Vector3" then
					lookAt = attr
				end
			end
			if lookAt and state.mover.alignOrientation then
				local to = lookAt - state.root.Position
				if to.Magnitude > 0.08 then
					local targetCf = CFrame.lookAt(state.root.Position, state.root.Position + to.Unit)
					state.mover.alignOrientation.CFrame = targetCf
					state.lookDir = to.Unit
				end
			end
			state.astral:SetAttribute(GameConstants.FLIGHT_ALPHA_ATTRIBUTE, 0)
			continue
		end

		local speed = GameConstants.FLIGHT_SPEED
		-- Same top speed as her usual flight: base Jean is slower than Phoenix.
		if GameConstants.PHOENIX_LOOK_IDS[state.body:GetAttribute(GameConstants.LOOK_MODE_ATTRIBUTE)] ~= true then
			speed *= GameConstants.MG_JEAN_FLIGHT_SPEED_MULT
		end
		if painByPlayer[player] then
			speed *= GameConstants.MG_PAIN_ASTRAL_SPEED_MULT
		end
		local moveMag = state.moveDir.Magnitude
		local direction = if moveMag > 0.01 then state.moveDir.Unit else normalizeDir(state.lookDir)
		state.currentVel = FlightMath.stepVelocity(state.currentVel, if moveMag > 0.01 then direction else nil, speed, dtClamped)

		local ownerIsPlayer = false
		pcall(function()
			ownerIsPlayer = state.root:GetNetworkOwner() == player
		end)
		if not ownerIsPlayer then
			state.mover.linearVelocity.VectorVelocity = state.currentVel
			if state.mover.vectorForce then
				state.mover.vectorForce.Force = Vector3.new(0, state.root.AssemblyMass * Workspace.Gravity, 0)
			end
		end

		local velMag = state.currentVel.Magnitude
		local alphaSpeed = if speed > 0 then velMag / speed else 0
		local leanStrength = math.clamp(alphaSpeed, 0, 1)
		local facingDir = if moveMag > 0.01 then direction else normalizeDir(state.lookDir)
		local sideLean = math.clamp(state.sideInput, -1, 1)
		local bank = 0
		local sideYaw = 0
		local pitchAlpha = 0
		if moveMag > 0.01 and velMag > 2 then
			bank = getBank(direction, state.currentVel) * leanStrength * GameConstants.FLIGHT_BANK_SCALE
			bank += sideLean * GameConstants.FLIGHT_BANK_MAX * GameConstants.FLIGHT_SIDE_YIELD * leanStrength
			sideYaw = sideLean * GameConstants.FLIGHT_SIDE_YAW * leanStrength
			pitchAlpha = math.min(1, alphaSpeed) * 1.15
		end
		bank = math.clamp(bank, -GameConstants.FLIGHT_BANK_MAX, GameConstants.FLIGHT_BANK_MAX)
		sideYaw = math.clamp(sideYaw, -GameConstants.FLIGHT_SIDE_YAW, GameConstants.FLIGHT_SIDE_YAW)

		if not ownerIsPlayer and state.mover.alignOrientation then
			local baseCf = CFrame.lookAt(state.root.Position, state.root.Position + facingDir)
			local targetCf = baseCf
				* CFrame.Angles(
					math.rad(-pitchAlpha * GameConstants.MG_FLIGHT_PITCH_MAX),
					math.rad(sideYaw),
					math.rad(-bank)
				)
			state.mover.alignOrientation.CFrame = targetCf
		end

		local nowClock = os.clock()
		if nowClock - (Phoenix.astralAttrAt[player] or 0) >= 0.05 then
			Phoenix.astralAttrAt[player] = nowClock
			state.astral:SetAttribute(GameConstants.FLIGHT_ALPHA_ATTRIBUTE, math.clamp(alphaSpeed, 0, 1))
			state.astral:SetAttribute(GameConstants.FLIGHT_BANK_ATTRIBUTE, bank)
			state.astral:SetAttribute(GameConstants.FLIGHT_SIDE_ATTRIBUTE, sideLean)
		end
	end

	-- Mind link energy / duration
	for player, state in mindLinkByPlayer do
		if not state.character.Parent or player.Character ~= state.character then
			endMindLink(player, true, true)
			continue
		end
		-- Drop any member who died - they shouldn't stay linked (damage
		-- share, chat, VFX) once they're gone.
		local deadMembers: { Model } = {}
		for _, member in state.members do
			if member == state.character then
				continue
			end
			local memberHum = CombatHelper.getHumanoid(member)
			if not member.Parent or not memberHum or memberHum.Health <= 0 then
				table.insert(deadMembers, member)
			end
		end
		for _, member in deadMembers do
			removeMindLinkMember(state, member)
		end
		local elapsed = os.clock() - state.startedAt
		if elapsed >= GameConstants.MG_MIND_LINK_MAX_DURATION then
			endMindLink(player, true, true)
			continue
		end
		local energy = state.character:GetAttribute(GameConstants.ENERGY_ATTRIBUTE)
		if type(energy) ~= "number" or energy <= 0 then
			endMindLink(player, true, true)
			continue
		end
		local drain = GameConstants.MG_MIND_LINK_ENERGY_PER_SEC * dtClamped
		if not CharacterService.spendEnergy(state.character, math.min(drain, energy)) then
			endMindLink(player, true, true)
		end
	end

	-- Telekinetic debris follow / timeout
	local now = os.clock()
	for player, state in debrisByPlayer do
		local root = getRoot(state.character)
		if not state.character.Parent or not root or player.Character ~= state.character then
			endDebris(player, true, true)
			continue
		end
		if state.holding then
			if not CharacterService.spendEnergy(state.character, GameConstants.MG_DEBRIS_ENERGY_PER_SEC * dtClamped) then
				endDebris(player, true, true)
				continue
			end
		end
		local followExpired = now >= state.followUntil
		for _, rock in state.rocks do
			if rock.thrown or rock.expiring or not rock.part.Parent then
				continue
			end
			if followExpired then
				beginDebrisExpire(player, state, rock)
				continue
			end
			if not rock.rising then
				rock.orbitAngle += rock.orbitSpeed * dtClamped
			end
			local y = if rock.rising then rock.liftY else rock.orbitHeight
			local targetPos = root.Position
				+ Vector3.new(math.cos(rock.orbitAngle) * rock.orbitRadius, y, math.sin(rock.orbitAngle) * rock.orbitRadius)
			local current = if rock.visual:IsA("Model") then rock.visual:GetPivot().Position else rock.part.Position
			local followRate = GameConstants.MG_DEBRIS_FOLLOW_LERP
			local nextPos = current:Lerp(targetPos, math.clamp(dtClamped * followRate, 0, 1))
			rock.spinAngle += rock.spinSpeed * dtClamped * 2.4
			rock.yawAngle += rock.yawSpeed * dtClamped
			setDebrisRockCf(rock, CFrame.new(nextPos) * debrisWorldRotation(rock))
			rock.part.AssemblyLinearVelocity = Vector3.zero
			rock.part.AssemblyAngularVelocity = Vector3.zero
		end
	end

	for player, state in barrierByPlayer do
		if not state.character.Parent then
			stopBarrier(player, true)
			continue
		end
		local drain = GameConstants.MG_BARRIER_ENERGY_PER_SEC * (if state.dark then GameConstants.MG_DARK_BARRIER_DRAIN_MULT else 1)
		if not CharacterService.spendEnergy(state.character, drain * dtClamped) then
			stopBarrier(player, true)
		elseif state.dark then
			-- Dark Phoenix's Cosmic Shield mends her while it is up.
			local shieldHum = CombatHelper.getHumanoid(state.character)
			if shieldHum and shieldHum.Health > 0 and shieldHum.Health < shieldHum.MaxHealth then
				shieldHum.Health = math.min(shieldHum.MaxHealth, shieldHum.Health + GameConstants.MG_DARK_BARRIER_HEAL_PER_SEC * dtClamped)
			end
		end
	end

	for _, player in Players:GetPlayers() do
		updateJeanRestraint(player, dtClamped)
	end
end

local function isPhoenixJean(character: Model): boolean
	return character:GetAttribute(GameConstants.HERO_ATTRIBUTE) == "jean_grey"
		and GameConstants.PHOENIX_LOOK_IDS[MarvelGirlService.lookOf(character)] == true
end

local function clearPhoenixDown(player: Player)
local downState = phoenixDownByPlayer[player]
if downState and downState.clamp then
	downState.clamp:Disconnect()
	downState.clamp = nil
end
if phoenixDownByPlayer[player] then
	phoenixDownByPlayer[player] = nil
	unblockPhoenixAutoRespawn()
end
	local character = player.Character
	if character and character.Parent then
		character:SetAttribute(GameConstants.MG_PHOENIX_REVIVE_AVAILABLE_ATTRIBUTE, nil)
	end
end

-- Fully automatic now, mirroring ScarletWitchService.tryChaoticRevive
-- exactly (same structure, just Phoenix's own assets/constants/durations) -
-- no more player-facing "Come Back" button. That button required
-- DeathScreenClient to show its full black-screen/locked-camera flow and
-- wait on an explicit click before anything server-side even started,
-- which is what caused the "can't rotate camera, still shows 0 HP for a
-- few seconds" complaints: normal deaths, and ANAD's own auto-revive, never
-- show that locked camera at all (see isChaosReviveShielded's client-side
-- equivalent for Phoenix in init.client.luau, which now skips
-- DeathScreenClient entirely for her the same way). Movement/abilities stay
-- blocked via BUSY_ATTRIBUTE for the whole ragdoll+float+ramp window - she
-- can't move until RagdollService.clear's get-up animation actually
-- finishes, exactly like ChaoticRevive.
-- Hung on Phoenix (an already-counted top-level local), inside a do-block, same as every other
-- multi-part Phoenix feature - see Phoenix's own declaration comment on the 200-register limit.
do
	function Phoenix.teleportTo(character: Model, pos: Vector3)
		local pivot = character:GetPivot()
		character:PivotTo((pivot - pivot.Position) + pos)
		local root = character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
		end
	end

	function Phoenix.whrModelPosition(): Vector3?
		local target = Workspace:FindFirstChild("WHRModel")
		if not target then
			return nil
		end
		if target:IsA("Model") then
			return target:GetPivot().Position
		elseif target:IsA("BasePart") then
			return target.Position
		end
		return nil
	end

	-- Becomes the real Dark Phoenix morph (Assets.Morphs.DarkPhoenix), the same way picking a skin from
	-- the menu swaps her model - not a per-part color/mesh copy onto her existing body. Returns the new
	-- character (the old one is destroyed), or nil if the swap failed (caller keeps using the old one).
	function Phoenix.applyDarkPhoenixLook(player: Player, character: Model): Model?
		local assets = ReplicatedStorage:FindFirstChild("Assets")
		local morphs = assets and assets:FindFirstChild("Morphs")
		local darkPhoenix = morphs and morphs:FindFirstChild("DarkPhoenix")
		if not darkPhoenix or not darkPhoenix:IsA("Model") then
			warn("[Phoenix] Missing Assets.Morphs.DarkPhoenix")
			return nil
		end
		return CharacterService.swapToMorphTemplate(player, character, darkPhoenix)
		end
		
		-- A short burst of the DarkPhoenixResurectionShockwave asset where she lands after the resurrection:
		-- its emitters carry authored EmitCount attributes, so it is emitted twice and then removed.
		function Phoenix.playResurrectionShockwave(character: Model)
		local root = (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso") or getRoot(character)) :: BasePart?
		local template = getPhoenixAsset("DarkPhoenixResurectionShockwave")
		if not root or not template or not template:IsA("BasePart") then
			warn("[Phoenix] Missing Assets.JeanGrey.JeanGreyThePhoenixForce.DarkPhoenixResurectionShockwave")
			return
		end
		local fx = template:Clone() :: BasePart
		fx.Anchored = true
		fx.CanCollide = false
		fx.CanQuery = false
		fx.CanTouch = false
		-- Position only - keep the template's authored orientation. At her upper torso.
		fx.CFrame = fx.CFrame - fx.CFrame.Position + root.Position
		fx.Parent = Workspace
		local function burst()
			for _, desc in fx:GetDescendants() do
				if desc:IsA("ParticleEmitter") then
					desc.Enabled = false
					local count = desc:GetAttribute("EmitCount")
					desc:Emit(if type(count) == "number" then count else 20)
				end
			end
		end
		-- Slightly after the teleport so it's seen as the whiteout clears, not hidden behind it.
		task.delay(0.25, function()
			if not fx.Parent then
				return
			end
			burst()
			task.wait(0.15)
			if fx.Parent then
				burst()
			end
		end)
		task.delay(3, function()
			if fx.Parent then
				fx:Destroy()
			end
		end)
		end
end

function MarvelGirlService.tryPhoenixDown(player: Player, character: Model): boolean
	if not isPhoenixJean(character) then
		return false
	end
	-- Reset must always be a clean death, never a revive - but Dead state
	-- is unconditionally disabled the instant she's Phoenix (see
	-- ensurePhoenixDeadDisabled), with nothing else left to ever re-enable
	-- it or fire Humanoid.Died once tryPhoenixDown declines to run its own
	-- revive sequence. Force the real death through here instead of just
	-- returning false, or she's stuck at 0 HP forever with no death screen.
	if character:GetAttribute("ResetForcedDeath") == true then
		-- Cosmic Aura Burn's rigid rootAlign is still fully up at this point
		-- (nothing else has torn it down yet - the real Died-based cleanup
		-- below hasn't fired) - forcing the Dead state transition while it's
		-- still fighting to pin her position is exactly what flung her on
		-- Reset. Tear it down first, same reasoning as the main revive path
		-- below.
		Phoenix.stopAuraBurn(player, false)
		-- Telekinetic Area Lift owns the exact same kind of rigid rootAlign
		-- on the caster, same fling risk.
		Phoenix.endTelekineticAreaLift(player, false)
		-- (She is a fake-death body like everyone: FakeDeath flags her Downed on this Reset - no real Dead is forced.)
		-- The CLIENT's own death-screen gate (isPhoenixReviveShielded in
		-- init.client.luau) defaults to "shielded" - assumes a revive is
		-- still coming - unless MgPhoenixReviveUsed is true. Returning
		-- false here without ALSO setting this left the client waiting
		-- forever for a revive that was never going to happen: Dead fires
		-- server-side fine, but the death screen itself never shows -
		-- exactly what "stuck at 0 health" actually was.
		character:SetAttribute("MgPhoenixReviveUsed", true)
		return false
		end
		-- Once per character selection - this attribute lives on the character
	-- instance itself, so a fresh selection (a brand new character Model)
	-- naturally starts clean with no reset logic needed.
	if character:GetAttribute("MgPhoenixReviveUsed") == true then
		return false
	end
	if phoenixDownByPlayer[player] then
		return false
	end
	-- Same rule as ANAD's Chaotic Revive: an insta-kill (vaporize, Crush
	-- Finisher, Cosmic Aura's execute, Molecular Eradication, ...) cancels
	-- the revive outright - she just stays dead like anyone else hit by one.
	local lastSource = character:GetAttribute(GameConstants.LAST_DAMAGE_SOURCE_ATTRIBUTE)
	if type(lastSource) == "string" and GameConstants.SW_CHAOS_REVIVE_INSTA_SOURCES[lastSource] then
		return false
	end
	-- Cosmic Aura Burn's rootAlign (RigidityEnabled, MaxForce=1e6) rigidly
	-- pins the root - going down while it's still up (Reset with Dead
	-- disabled skips Humanoid.Died entirely, so it never reaches
	-- RagdollService.apply/onBeforeApply through the normal path) left it
	-- fighting whatever this down-sequence and the eventual async
	-- RagdollService.apply do to her body, which is exactly the spring-
	-- loaded-velocity fling stopAuraBurn's own comments describe. Tearing
	-- it down HERE, synchronously and first, is the same fix as
	-- RagdollService.onBeforeApply but for this separate down-sequence,
	-- which doesn't go through that hook in time (or at all, on Reset).
	Phoenix.stopAuraBurn(player, false)
	Phoenix.endTelekineticAreaLift(player, false)
	-- A death ends every lingering status (burn, frost...): left running they ticked her back to 0 mid-rebirth.
	pcall(function()
		require(ReplicatedStorage.Shared.StatusService).clearAll(character)
	end)
	-- Dying mid-flight never runs flight's own end-of-flight cleanup (Dead is disabled for her, so this
	-- whole down-sequence substitutes for the normal Humanoid.Died-driven MarvelGirlService.cancelAll) -
	-- without this her wings' ref count was left stuck above zero, so removeWings elsewhere could never
	-- actually clear them, and the leftover wings instance just sat there until revealed again once she
	-- was no longer dead/faded. Force-cleared here regardless of ref count, per request.
	HexFlightService.endFlight(player, false)
	Phoenix.forceRemoveWings(character)
	Phoenix.setMorphWingsVisible(character, false)
	-- Also clear the manual Character Configs toggle flag itself - without this, the config panel's
	-- button (purely client-side optimistic state, see GameplayHUD) still read "on" after revival even
	-- though the actual wings were just force-removed above, and nothing was left to turn it off.
	manualWingsByPlayer[player] = nil
	character:SetAttribute("MgPhoenixReviveUsed", true)
	local deathRoot = character:FindFirstChild("HumanoidRootPart")
	local deathPos = if deathRoot and deathRoot:IsA("BasePart") then deathRoot.Position else character:GetPivot().Position
	phoenixDownByPlayer[player] = { character = character, deathPos = deathPos }
	character:SetAttribute(GameConstants.MG_PHOENIX_REVIVE_AVAILABLE_ATTRIBUTE, true)
	blockPhoenixAutoRespawn()
	local hum = character:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.BreakJointsOnDeath = false
	end
	-- 3s after death (per request - she visibly collapses/reads as a real death first, same reasoning as
	-- MG_PHOENIX_REVIVE_DELAY below), THEN to WHRModel's position - the rest of the down/revive sequence
	-- plays out there, not where she actually died (teleported back to deathPos once revival succeeds).
	local downStateForWhr = phoenixDownByPlayer[player]
	task.delay(3, function()
		if phoenixDownByPlayer[player] ~= downStateForWhr or not character.Parent then
			return
		end
		local whrPos = Phoenix.whrModelPosition()
		if whrPos then
			Phoenix.teleportTo(character, whrPos)
		else
			warn("[Phoenix] Missing workspace.WHRModel - reviving in place")
		end
	end)
	-- She visibly collapses (this game's own ragdoll, not Roblox's
	-- joint-breaking one - hence BreakJointsOnDeath = false above) right
	-- when she goes down. task.spawn because RagdollService.apply can yield
	-- waiting on the rig/appearance to be ready, and this runs synchronously
	-- off Humanoid.Died.
	task.spawn(function()
		if character.Parent then
			RagdollService.apply(character)
		end
	end)

	-- ReviveMorph's per-body-part particles start 1s before the rest of the
	-- revive sequence below (its own timing is otherwise anchored to
	-- MG_PHOENIX_REVIVE_DELAY, which would read as popping in all at once).
	task.delay(math.max(GameConstants.MG_PHOENIX_REVIVE_DELAY - 1, 0), function()
		local state = phoenixDownByPlayer[player]
		if not state or state.character ~= character or not character.Parent then
			return
		end
		local reviveMorphTemplate = getPhoenixAsset(character, "PhoenixRebirth", "ReviveMorph")
		if reviveMorphTemplate then
			state.reviveMorphFx = VfxHelper.attachMorphParticles(character, reviveMorphTemplate)
		end
	end)

	-- Let a real death actually read as a real death first - same as
	-- ChaoticRevive's SW_CHAOS_REVIVE_DELAY.
	task.delay(GameConstants.MG_PHOENIX_REVIVE_DELAY, function()
		if character ~= player.Character or not character.Parent then
			clearPhoenixDown(player)
			return
		end
		local hum = CombatHelper.getHumanoid(character)
		local root = getRoot(character)
		if not hum or not root then
			clearPhoenixDown(player)
			return
		end

		-- Roblox does not let a Humanoid climb back above 0 Health on its own
		-- once it's actually Dead - later Health writes get silently ignored
		-- unless Dead is explicitly disabled first (same fix as ANAD Scarlet
		-- Witch's ChaoticRevive - this is what previously left her stuck at 0 HP
		-- and unable to move no matter what this function wrote to Health).
		-- Diagnostic-confirmed: re-enabling Dead right after this clamp (the
		-- old code did SetStateEnabled(Dead,false) -> Health=1 ->
		-- SetStateEnabled(Dead,true) back-to-back) let her snap straight
		-- back into the Dead state an instant later - hum:GetState() read
		-- Dead and hum.Health read 0 at the start of the ramp every single
		-- time, regardless of death cause. Keep Dead disabled for the whole
		-- revival window instead; it only gets re-enabled once revival
		-- actually succeeds (or fails for real) further down.
		pcall(function()
			hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
		end)
		-- SetStateEnabled only blocks FUTURE entry into a state - it does
		-- NOT retroactively pull her out of Dead if she's already settled
		-- into it by the time this runs (confirmed: hum:GetState() still
		-- read Dead here even with Dead disabled). ChangeState forces an
		-- actual transition; Dead is disabled so it can't re-target Dead,
		-- landing her in Physics instead - the same state the ragdoll
		-- system already drives her with, so this doesn't fight anything.
		pcall(function()
			hum:ChangeState(Enum.HumanoidStateType.Physics)
		end)
		hum.Health = math.max(hum.Health, 1)
		-- From here to the end of the rebirth nothing may put her back at 0 (a burn tick, a status, a lingering hazard,
		-- anything that slips past PROTECTED_UNTIL): that used to fail the rebirth and leave her standing at 0 HP.
		-- clearPhoenixDown (every exit, and Reset) lets go of this.
		local downState = phoenixDownByPlayer[player]
		if downState and not downState.clamp then
			downState.clamp = hum.HealthChanged:Connect(function(hp: number)
				if hp <= 0 and hum.Parent and character:GetAttribute("ResetForcedDeath") ~= true then
					hum.Health = 1
				end
			end)
		end
		-- MG_PHOENIX_REVIVE_IMMUNITY (5s) alone doesn't reliably cover the
		-- float animation (variable length) + HP ramp (1.35s) that follow -
		-- if it runs out before the ramp finishes, real damage can land,
		-- driving Health to 0 for real. Once Humanoid is actually Dead again
		-- every further `hum.Health = ...` write below is silently discarded
		-- (same Roblox behavior documented above), which read as "gave her
		-- health and it just went back to 0, stuck". Refreshed again once
		-- animLen is known and again right before the HP ramp starts, so
		-- protection always covers what's actually left of the sequence.
		local function refreshReviveImmunity(extraSeconds: number)
			character:SetAttribute(
				GameConstants.PROTECTED_UNTIL_ATTRIBUTE,
				AbilityCooldownHelper.getNow() + math.max(GameConstants.MG_PHOENIX_REVIVE_IMMUNITY, extraSeconds + 1)
			)
		end
		refreshReviveImmunity(GameConstants.MG_PHOENIX_REVIVE_IMMUNITY)

		-- Owning BUSY_ATTRIBUTE explicitly (same as ChaoticRevive) locks
		-- input for the sequence - she's still ragdolled right now (from
		-- tryPhoenixDown) and stays that way through the float/animation
		-- below; RagdollService.clear() only runs once her HP ramp actually
		-- reaches MG_PHOENIX_REVIVE_HP_RATIO, further down.
		--
		-- BUG FOUND (this was the actual cause of the revive "not working" -
		-- looking frozen/stuck or toppling over instead of floating): this
		-- used to also force PlatformStand=false and ChangeState(Physics)
		-- right here, which hands the Humanoid's own upright-balance control
		-- back on top of the ragdoll constraints RagdollService.apply already
		-- built and is still actively driving - the two fought each other for
		-- the entire float/animation window. ChaoticRevive (the reference
		-- this was modeled on) never touches PlatformStand/ChangeState/
		-- WalkSpeed/Move during its ragdoll window at all - it just lets the
		-- ragdoll own the body and relies on BUSY_ATTRIBUTE alone to lock
		-- input, exactly like this does now.
		character:SetAttribute(GameConstants.BUSY_ATTRIBUTE, true)

		-- Revive VFX: ReviveMorph's per-body-part particles were already
		-- started 1s ago (see the earlier task.delay above); RebirthBasepart
		-- appears at her feet REBIRTH_BASEPART_DELAY after this point, so the
		-- ground effect reads as an escalation after the morph is already
		-- glowing, not both popping in at once.
		local downState = phoenixDownByPlayer[player]
		local reviveMorphFx: { Instance } = (downState and downState.reviveMorphFx) or {}
		if #reviveMorphFx == 0 then
			-- MG_PHOENIX_REVIVE_DELAY < 1s: the early attach above hasn't
			-- fired yet, so just attach now instead of ending up with no fx.
			local reviveMorphTemplate = getPhoenixAsset(character, "PhoenixRebirth", "ReviveMorph")
			if reviveMorphTemplate then
				reviveMorphFx = VfxHelper.attachMorphParticles(character, reviveMorphTemplate)
			end
		end
		local rebirthBaseFx: BasePart? = nil
		local reviveFloatAtt: Attachment? = nil
		local reviveFloatAlign: AlignPosition? = nil
		task.delay(GameConstants.MG_PHOENIX_REBIRTH_BASEPART_DELAY, function()
			if not character.Parent or rebirthBaseFx then
				return
			end
			local groundRoot = getRoot(character)
			if not groundRoot then
				return
			end
			-- A missing/invalid RebirthBasepart asset must only skip the ground
			-- fx - the un-ragdoll, rebirth anim and float below are what the
			-- revive animation depends on (it used to return here, leaving her
			-- ragdolled so the animation never rendered).
			local baseTemplate = getPhoenixAsset(character, "PhoenixRebirth", "RebirthBasepart")
			if baseTemplate and baseTemplate:IsA("BasePart") then
				local foot = character:FindFirstChild("LeftFoot") or character:FindFirstChild("Left Leg")
				local groundPos = if foot and foot:IsA("BasePart")
					then Vector3.new(groundRoot.Position.X, foot.Position.Y, groundRoot.Position.Z)
					else groundRoot.Position - Vector3.new(0, 3, 0)
				local clone = baseTemplate:Clone()
				clone.Name = "PhoenixRebirthBasepart"
				clone.Anchored = true
				clone.CanCollide = false
				clone.CanQuery = false
				clone.CanTouch = false
				clone.Massless = true
				-- Position only - keep the template's own authored orientation,
				-- don't rotate it to face the caster.
				clone.CFrame = clone.CFrame - clone.CFrame.Position + groundPos
				clone.Parent = workspace
				VfxHelper.setParticlesEnabled(clone, true)
				rebirthBaseFx = clone
			else
				warn("[Phoenix] Missing PhoenixRebirth.RebirthBasepart - reviving without ground fx")
			end

			-- Per request: the moment the rebirth basepart actually shows is
			-- when she gets back up, not later once the HP ramp finishes -
			-- RagdollService.clear is the proper teardown (unlike the manual
			-- PlatformStand/ChangeState hack documented above as the actual
			-- cause of the old "fights the float" bug), so this is safe to
			-- call even with the float AlignPosition about to be set up below.
			-- skipGetUpAnim: she's not actually still ragdolled by this point in
			-- the rebirth sequence, so the standard get-up animation shouldn't
			-- play on top of / instead of the rebirth animation below.
			-- skipGetUpAnim only skips OUR custom get-up track - Roblox's own
			-- Humanoid still auto-transitions through HumanoidStateType.
			-- GettingUp (and its own built-in get-up montage) the instant
			-- PlatformStand/ragdoll physics let go, regardless of our
			-- animation choice. Disabling GettingUp BEFORE clear() (not
			-- forcing ChangeState(Physics) after, as this used to) is the
			-- fix here: Physics is what ragdoll itself drives her with, and
			-- forcing her back into it turned out to ALSO block the
			-- Animator from actually driving Motor6Ds at all - the rebirth
			-- animation track was genuinely playing (Track:IsPlaying() true)
			-- the whole time, it just never visually rendered, which is
			-- what "floats unragdolled but plays no animation" actually was.
			if hum and hum.Parent then
				pcall(function()
					hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
				end)
			end
			RagdollService.clear(character, true)
			if hum and hum.Parent then
				pcall(function()
					hum:ChangeState(Enum.HumanoidStateType.Running)
				end)
			end
			playJeanAnim(character, GameConstants.MG_PHOENIX_REBIRTH_ANIM, false)

			-- Float starts the moment the rebirth basepart activates (not the
			-- whole revive sequence) and gets cleaned up wherever the revive
			-- fx themselves are torn down (destroyReviveFx/retireReviveFx
			-- below) - same AlignPosition technique as Molecular Eradication.
			local floatHost = (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")) :: BasePart? or groundRoot
			local att = Instance.new("Attachment")
			att.Name = "MgPhoenixReviveFloatAtt"
			att.Parent = floatHost
			local align = Instance.new("AlignPosition")
			align.Name = "MgPhoenixReviveFloatAlign"
			align.Mode = Enum.PositionAlignmentMode.OneAttachment
			align.Attachment0 = att
			align.ApplyAtCenterOfMass = true
			align.MaxForce = 1e9
			align.MaxVelocity = 25
			align.Responsiveness = GameConstants.MG_PHOENIX_REVIVE_FLOAT_RESPONSIVENESS
			align.Position = groundRoot.Position + Vector3.new(0, GameConstants.MG_PHOENIX_REVIVE_FLOAT_HEIGHT, 0)
			align.Parent = groundRoot
			reviveFloatAtt = att
			reviveFloatAlign = align
		end)
		local function clearReviveFloat()
			if reviveFloatAlign and reviveFloatAlign.Parent then
				reviveFloatAlign:Destroy()
			end
			if reviveFloatAtt and reviveFloatAtt.Parent then
				reviveFloatAtt:Destroy()
			end
			reviveFloatAlign = nil
			reviveFloatAtt = nil
		end
		local function destroyReviveFx()
			clearReviveFloat()
			for _, fx in reviveMorphFx do
				if fx.Parent then
					fx:Destroy()
				end
			end
			if rebirthBaseFx and rebirthBaseFx.Parent then
				rebirthBaseFx:Destroy()
			end
		end
		local function retireReviveFx()
			clearReviveFloat()
			for _, fx in reviveMorphFx do
				if fx.Parent then
					VfxHelper.retireFxSmooth(fx, 0.4, 0.6)
				end
			end
			if rebirthBaseFx and rebirthBaseFx.Parent then
				VfxHelper.retireFxSmooth(rebirthBaseFx, 0.4, 0.6)
			end
		end

		-- Ground-in-place animation/HP ramp below is unchanged - the float
		-- added back above is scoped to the AlignPosition on her root
		-- (starting once the rebirth basepart appears, cleared the instant
		-- destroyReviveFx/retireReviveFx runs), not this per-request removal.
		-- she revives in place now. Just plays the animation and waits it out
		-- before moving on to the HP ramp below.
		--
		-- BUG FOUND (this was "the animation doesn't play"): MG_PHOENIX_
		-- REVIVE_ANIM used to play HERE, immediately - while she's still in
		-- the SAME real ragdoll tryPhoenixDown applied at death (nothing
		-- un-ragdolls her until the MG_PHOENIX_REBIRTH_BASEPART_DELAY closure
		-- above runs). That's exactly the "Physics state blocks the Animator
		-- from driving Motor6Ds at all" bug already diagnosed and fixed for
		-- MG_PHOENIX_REBIRTH_ANIM in that same closure (see its comment) -
		-- the track genuinely played (IsPlaying true) but never visually
		-- rendered. Delayed by the same REBIRTH_BASEPART_DELAY here so it
		-- only starts once she's actually un-ragdolled, same fix, same delay.
		task.delay(GameConstants.MG_PHOENIX_REBIRTH_BASEPART_DELAY, function()
		if not character.Parent or player.Character ~= character then
			-- Bailing without this left phoenixDownByPlayer set and the auto-respawn block held forever.
			destroyReviveFx()
			character:SetAttribute(GameConstants.BUSY_ATTRIBUTE, nil)
			clearPhoenixDown(player)
			return
		end
		local animTrack = playJeanAnim(character, GameConstants.MG_PHOENIX_REVIVE_ANIM, false)
		-- Fixed, not animTrack.Length - see MG_PHOENIX_REVIVE_ANIM_TIME.
		local animLen = GameConstants.MG_PHOENIX_REVIVE_ANIM_TIME
		-- Cutscene covers the animation + HP ramp; the client whites out at the end, the
		-- morph swap/teleport back happen behind it, and PhoenixRevive tears the white away.
		Remotes.getEvent("PhoenixCutscene"):FireClient(player, "start", animLen + GameConstants.MG_PHOENIX_REVIVE_HP_TIME)
		refreshReviveImmunity(animLen + GameConstants.MG_PHOENIX_REVIVE_HP_TIME)

		task.spawn(function()
			local t0 = os.clock()
			local diedDuringAnim = false
			while os.clock() - t0 < animLen do
				if not character.Parent or not root.Parent or player.Character ~= character then
					break
				end
				-- A real death landing during the revive animation used to go
				-- unnoticed until the animation's fixed duration finished and
				-- the HP ramp below started - the full ~2.4s "coming back to
				-- life" animation played out even when she was already dead
				-- for real, before the game admitted it. Health <= 0 here
				-- means the same real-death detection the HP ramp uses below
				-- (Health stuck at 0, further writes silently discarded).
				if hum.Health <= 0 then
					diedDuringAnim = true
					break
				end
				task.wait()
			end

			if animTrack then
				animTrack:Stop(0.15)
				animTrack:Destroy()
			end
			-- Animation over: drop her back down instead of hovering through the HP ramp.
			clearReviveFloat()

			if not character.Parent or not hum.Parent or player.Character ~= character then
				destroyReviveFx()
				character:SetAttribute(GameConstants.BUSY_ATTRIBUTE, nil)
				clearPhoenixDown(player)
				return
			end

			if diedDuringAnim then
				pcall(function()
					hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
				end)
				character:SetAttribute(GameConstants.BUSY_ATTRIBUTE, nil)
				destroyReviveFx()
				clearPhoenixDown(player)
				-- killed during the rebirth: a real (second) death, as a Downed body
				require(script.Parent.FakeDeath).down(character)
				return
			end

			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero

			-- Never actually zero Health here - unlike a fresh death, this would
			-- fire Humanoid.Died/Dead for real a second time (same lesson as
			-- ChaoticRevive), silently discarding every ramp-up write after it.
			-- Health stays clamped to >= 1 for the whole ramp.
			refreshReviveImmunity(GameConstants.MG_PHOENIX_REVIVE_HP_TIME)
			local targetHp = hum.MaxHealth * GameConstants.MG_PHOENIX_REVIVE_HP_RATIO
			local hpStart = math.max(hum.Health, 1)
			local hpT0 = os.clock()
			local diedForReal = false
			while os.clock() - hpT0 < GameConstants.MG_PHOENIX_REVIVE_HP_TIME do
				if not hum.Parent or player.Character ~= character then
					break
				end
				-- Health writes below are silently ignored once Humanoid is
				-- truly Dead - bail instead of spinning on discarded writes
				-- and leaving BUSY_ATTRIBUTE/Ragdolled stuck on a real corpse.
				if hum:GetState() == Enum.HumanoidStateType.Dead then
					pcall(function()
						hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
						hum:ChangeState(Enum.HumanoidStateType.Physics)
					end)
					hum.Health = math.max(hum.Health, 1)
				end
				if hum.Health <= 0 then
					diedForReal = true
					break
				end
				local u = math.clamp((os.clock() - hpT0) / GameConstants.MG_PHOENIX_REVIVE_HP_TIME, 0, 1)
				hum.Health = hpStart + (targetHp - hpStart) * u
				task.wait()
			end
			if diedForReal then
				-- Genuinely dead for real this time - restore Dead state so
				-- the normal death flow (respawn availability etc.) works.
				pcall(function()
					hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
				end)
				character:SetAttribute(GameConstants.BUSY_ATTRIBUTE, nil)
				destroyReviveFx()
				clearPhoenixDown(player)
				require(script.Parent.FakeDeath).down(character)
				return
			end
			if hum.Parent and player.Character == character then
				hum.Health = targetHp
				-- Revival succeeded and Health is well above 0 now - safe to
				-- restore Dead so a genuine future death behaves normally.
				pcall(function()
					hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
				end)
				-- She was already un-ragdolled back at MG_PHOENIX_REBIRTH_
				-- BASEPART_DELAY (skipGetUpAnim=true, so the custom rebirth
				-- animation could render instead of Roblox's own get-up
				-- montage) - calling clear() again here is just a harmless
				-- cleanup no-op on the ragdoll-physics side (ragdollVisualLast
				-- already matches), EXCEPT this call used to omit
				-- skipGetUpAnim, which re-armed and fired Roblox's own
				-- built-in get-up montage a second time on top of the
				-- already-finished custom animation. skipGetUpAnim=true here
				-- too, matching the earlier call, so nothing re-triggers it.
				RagdollService.clear(character, true)
				hum.WalkSpeed = GameConstants.DEFAULT_WALK_SPEED
				hum.JumpPower = 50
				pcall(function()
					hum.JumpHeight = 7.2
					hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
				end)
				-- Morph change happens HERE, still at WHR, before teleporting back - not after she's
				-- already back in the open world (per request). Base "Phoenix Force" skin only - New
				-- X-Men/Live Action keep their own look. Permanent for the rest of this life
				-- (applyDarkPhoenixLook's transplanted fx are never torn down like the revive fx above;
				-- the recolor sticks until she genuinely dies and respawns fresh).
				local darkApplied = false
				if MarvelGirlService.lookOf(character) == "phoenix" then
					local newCharacter = Phoenix.applyDarkPhoenixLook(player, character)
					if newCharacter then
						character = newCharacter
						darkApplied = true
						-- Telepathic Pain switches to its area form for the rest of this life.
						character:SetAttribute("MgDarkPhoenix", true)
						-- Permanent Cosmic buff for this life: +10% damage over base Phoenix (CombatHelper reads it).
						character:SetAttribute("MgCosmicDamageMult", GameConstants.MG_DARK_PHOENIX_DAMAGE_MULT)
						local darkHum = CombatHelper.getHumanoid(character)
						if darkHum then
							darkHum.MaxHealth = GameConstants.MG_DARK_PHOENIX_HEALTH
							darkHum.Health = GameConstants.MG_DARK_PHOENIX_HEALTH
						end
					end
				end
				if downState and downState.deathPos then
					Phoenix.teleportTo(character, downState.deathPos)
				end
				if darkApplied then
					Phoenix.playResurrectionShockwave(character)
					-- Becoming Dark Phoenix tops up Phoenix Wrath's charge (smoothly, the HUD reads it live) and
					-- drops its real-time floor, so the ultimate is usable straight away.
					Workspace:SetAttribute("PhoenixWrathLastCastAt", nil)
					task.spawn(function()
						local from = Workspace:GetAttribute("PhoenixWrathDamageAccum")
						from = if type(from) == "number" then from else 0
						local full = GameConstants.MG_WRATH_DAMAGE_THRESHOLD
						local t0 = os.clock()
						local span = 1.8
						while character.Parent do
							local a = math.clamp((os.clock() - t0) / span, 0, 1)
							Workspace:SetAttribute("PhoenixWrathDamageAccum", from + (full - from) * a)
							if a >= 1 then
								break
							end
							task.wait()
						end
					end)
				end
				-- Final safety net: force wings off again right here, at the very end of a successful
				-- revival - if they were still showing after death despite the same force-removal at the
				-- top of tryPhoenixDown, something between there and here re-enabled them (or the
				-- DarkPhoenix particle transplant landed wing fx on a part not caught by its own hair/
				-- wing name filter); this guarantees the end state is off regardless of the cause.
				Phoenix.forceRemoveWings(character)
				Phoenix.setMorphWingsVisible(character, false)
			end
			character:SetAttribute(GameConstants.BUSY_ATTRIBUTE, nil)

			retireReviveFx()
			clearPhoenixDown(player)
			Remotes.getEvent("PhoenixRevive"):FireClient(player, true)
		end)
		end)
	end)

	return true
end

-- Reset pressed WHILE the revive sequence above is already running (Health
-- may currently be 0 mid-float, or ramping back up) - CharacterService's
-- RequestReset handler used to just no-op the whole time
-- MG_PHOENIX_REVIVE_AVAILABLE_ATTRIBUTE is true (added so Reset couldn't yank
-- the camera-fragile revive out from under itself), but that left Reset
-- doing NOTHING for the entire revive window, reading as "stuck as Phoenix"
-- with no way out. Cancels the pending revive outright and forces the exact
-- same real-death path tryPhoenixDown's own ResetForcedDeath branch above
-- takes, instead of waiting on Health/Died to fire naturally (Health may
-- already be 0, so setting it to 0 again wouldn't fire anything).
function MarvelGirlService.forceResetDuringRevive(player: Player, character: Model)
	if not isPhoenixJean(character) then
		return
	end
	clearPhoenixDown(player)
	character:SetAttribute("MgPhoenixReviveUsed", true)
	local hum = character:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.Health = 0
		require(script.Parent.FakeDeath).down(character)
	end
end

Phoenix.marvelGirlFlightEyesByCharacter = {} :: { [Model]: { Instance } }
-- Ref-counted (flight and now Shield/Telekinesis/Area Lift/Telekinetic Slam
-- can all call these, sometimes overlapping) so one source ending the eye
-- glow doesn't rip it out from under another still-active source.
Phoenix.marvelGirlFlightEyesRefs = {} :: { [Model]: number }
Phoenix.marvelGirlFlightMorphFxByCharacter = {} :: { [Model]: { Instance } }
Phoenix.marvelGirlFlightHighlightByCharacter = {} :: { [Model]: Highlight }

-- Body particles/beams for base Jean's flight, sourced from the
-- MarvelGirlFlightMorph asset (same attach-by-body-part-name helper used for
-- telekinesis/revive morphs) instead of a bespoke per-part VFX list.
function Phoenix.attachMarvelGirlFlightMorphFx(character: Model)
	if Phoenix.marvelGirlFlightMorphFxByCharacter[character] then
		return
	end
	-- X-Men Red and base Jean ('97) each have their own flight morph; every other look uses Marvel Girl's.
	local morph = if MarvelGirlService.lookOf(character) == "xmen_red"
		then VfxHelper.getMarvelGirlAsset("XMenRed", "FlightMorph")
		elseif isJean97(character)
		then VfxHelper.getMarvelGirlAsset("JeanGreyBaseFlightMorph")
		else VfxHelper.getMarvelGirlAsset("MarvelGirlFlightMorph")
	if not morph then
		return
	end
	-- preserveAttachmentTransform=true: keep this morph's authored attachment
	-- positions/orientations as-is instead of the shared helper's default
	-- zero-out (every other attachMorphParticles caller - telekinesis/rune/
	-- revive/eradication/area-lift morphs - is unaffected).
	-- excludeNameSubstr="arealift": flight should only ever pull flight
	-- particles/beams, never anything named after the Telekinetic Area Lift
	-- morph, even if the two assets end up sharing a rig in Studio.
	local flightClones = VfxHelper.attachMorphParticles(character, morph, true, "arealift")
	Phoenix.marvelGirlFlightMorphFxByCharacter[character] = flightClones
	-- Trails (base Jean's flight morph has two on the torso): a cloned Trail still points its second attachment at the
	-- template's copy in ReplicatedStorage, so re-aim it at the sibling attachment cloned onto this character.
	for _, clone in flightClones do
		local trails: { Instance } = clone:GetDescendants()
		table.insert(trails, clone)
		for _, inst in trails do
			if inst:IsA("Trail") then
				local second = inst.Attachment1
				local host = if inst.Parent then inst.Parent.Parent else nil
				if second and host and second:IsDescendantOf(ReplicatedStorage) then
					local copy = host:FindFirstChild("TkMorph_" .. second.Name)
					if copy and copy:IsA("Attachment") then
						inst.Attachment1 = copy
					end
				end
				inst.Enabled = true
			end
		end
	end
	-- Base Jean's flight morph also carries a Highlight (blue body glow): put it on her for the flight, fading in smoothly.
	if isJean97(character) then
		local source = morph:FindFirstChildWhichIsA("Highlight", true)
		if source and not Phoenix.marvelGirlFlightHighlightByCharacter[character] then
			local glow = source:Clone()
			local targetFill, targetOutline = glow.FillTransparency, glow.OutlineTransparency
			glow.Name = "MgFlightHighlight"
			glow.Adornee = character
			glow.FillTransparency = 1
			glow.OutlineTransparency = 1
			glow.Parent = character
			TweenService:Create(glow, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
				FillTransparency = targetFill,
				OutlineTransparency = targetOutline,
			}):Play()
			Phoenix.marvelGirlFlightHighlightByCharacter[character] = glow
		end
	end
end

function Phoenix.removeMarvelGirlFlightMorphFx(character: Model)
	local glow = Phoenix.marvelGirlFlightHighlightByCharacter[character]
	if glow then
		Phoenix.marvelGirlFlightHighlightByCharacter[character] = nil
		local fadeOut = TweenService:Create(glow, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
			FillTransparency = 1,
			OutlineTransparency = 1,
		})
		fadeOut.Completed:Once(function()
			glow:Destroy()
		end)
		fadeOut:Play()
	end
	local fx = Phoenix.marvelGirlFlightMorphFxByCharacter[character]
	if not fx then
		return
	end
	Phoenix.marvelGirlFlightMorphFxByCharacter[character] = nil
	VfxHelper.fadeOutAndDestroyParticles(fx, 0.4, 3)
end

function Phoenix.attachMarvelGirlFlightEyes(character: Model)
	Phoenix.marvelGirlFlightEyesRefs[character] = (Phoenix.marvelGirlFlightEyesRefs[character] or 0) + 1
	if Phoenix.marvelGirlFlightEyesByCharacter[character] then
		return
	end
	local head = getHead(character)
	if not head then
		return
	end
	local instances: { Instance } = {}
	for _, eyeName in { "EyeAttachmentVFX1", "EyeAttachmentVFX2" } do
		local eyeTemplate = getPhoenixAsset(character, "EyeVFX", eyeName)
		if eyeTemplate then
			local fx = attachCloneToPart(eyeTemplate, head, 1, true)
			if fx then
				styleJeanFx(fx, nil, character)
				smoothEnableFx(fx, 0.25)
				table.insert(instances, fx)
			end
		end
	end
	Phoenix.marvelGirlFlightEyesByCharacter[character] = instances
end

function Phoenix.removeMarvelGirlFlightEyes(character: Model)
	local refs = Phoenix.marvelGirlFlightEyesRefs[character]
	if refs then
		refs -= 1
		if refs > 0 then
			Phoenix.marvelGirlFlightEyesRefs[character] = refs
			return
		end
		Phoenix.marvelGirlFlightEyesRefs[character] = nil
	end
	local instances = Phoenix.marvelGirlFlightEyesByCharacter[character]
	if not instances then
		return
	end
	Phoenix.marvelGirlFlightEyesByCharacter[character] = nil
	for _, inst in instances do
		if inst.Parent then
			VfxHelper.smoothDisableParticles(inst, 0.4)
			task.delay(3, function()
				if inst.Parent then
					inst:Destroy()
				end
			end)
		end
	end
end

function MarvelGirlService.init()
	-- TelekinesisService is hero-agnostic and can end a hold internally
	-- (energy ran out mid-hold) without ever going through
	-- releaseJeanTelekinesis - beginPowerFx's hand/eye glow only ever got
	-- turned off through that path, so an energy-depletion release left it
	-- on forever. endPowerFx is a safe no-op for a character that never
	-- began one, so this is safe to fire unconditionally for every release.
	TelekinesisService.onRelease(function(_player: Player, character: Model)
		endPowerFx(character)
	end)
	HexFlightService.registerHeroFx("jean_grey", {
		begin = function(character: Model)
			-- The takeoff animation itself plays earlier, immediately on
			-- input - HexFlightService.startFlight owns that timing (0.5s
			-- wind-up before she actually lifts off) since this hook only
			-- fires once flight has actually engaged.
			Phoenix.attachWings(character)
			local skin = MarvelGirlService.lookOf(character)
			if GameConstants.PHOENIX_LOOK_IDS[skin] then
				beginPowerFx(character)
				Phoenix.setMorphWingsVisible(character, not Phoenix.usesDarkFlight(character) and not Phoenix.wingsSuppressed(character))
				do
					local root = getRoot(character)
					local foot = character:FindFirstChild("LeftFoot") or character:FindFirstChild("Left Leg")
					local feetPos = if foot and foot:IsA("BasePart")
						then foot.Position
						elseif root
						then root.Position - Vector3.new(0, 3, 0)
						else nil
					local launchTemplate = getPhoenixAsset(character, "LaunchAttachment")
					if feetPos and launchTemplate then
						local host = makeFxHost("MgPhoenixLaunch", CFrame.new(feetPos))
						local fx = attachCloneToPart(launchTemplate, host, 12)
						task.delay(0.75, function()
							if fx then
								VfxHelper.smoothDisableParticles(fx, 0.3)
							end
							task.delay(3, function()
								if host.Parent then
									host:Destroy()
								end
							end)
						end)
					end
				end
			elseif skin == "marvel_girl" then
				beginPowerFx(character)
				Phoenix.attachMarvelGirlFlightEyes(character)
				Phoenix.attachMarvelGirlFlightMorphFx(character)
			elseif skin == "xmen_red" or isJean97(character) then
				beginPowerFx(character)
				Phoenix.attachMarvelGirlFlightMorphFx(character)
			end
		end,
		finish = function(character: Model)
			Phoenix.removeWings(character)
			local skin = MarvelGirlService.lookOf(character)
			if GameConstants.PHOENIX_LOOK_IDS[skin] then
				endPowerFx(character)
				Phoenix.setMorphWingsVisible(character, false)
			elseif skin == "marvel_girl" then
				endPowerFx(character)
				Phoenix.removeMarvelGirlFlightEyes(character)
				Phoenix.removeMarvelGirlFlightMorphFx(character)
			elseif skin == "xmen_red" or isJean97(character) then
				endPowerFx(character)
				Phoenix.removeMarvelGirlFlightMorphFx(character)
			end
		end,
	})
	-- Wrap existing shield handler so barrier works alongside Wanda shield
	local previous = nil
	pcall(function()
		-- Install combined handler
	end)
	CombatHelper.setShieldDamageHandler(function(character: Model, amount: number, hitFrom: Vector3?): boolean
		local okIw, InvisibleWomanService = pcall(function()
			return require(script.Parent.InvisibleWomanService)
		end)
		if okIw and InvisibleWomanService and type(InvisibleWomanService.absorbShield) == "function" then
			if InvisibleWomanService.absorbShield(character, amount, hitFrom) then
				return true
			end
		end
		if MarvelGirlService.damageBarrier(character, amount, hitFrom) then
			return true
		end
		local ok, ScarletWitchService = pcall(function()
			return require(script.Parent.ScarletWitchService)
		end)
		if ok and ScarletWitchService and type(ScarletWitchService.damageShieldForCharacter) == "function" then
			return ScarletWitchService.damageShieldForCharacter(character, amount, hitFrom)
		end
		return false
	end)

	RemoteGuard.onUseAbility(function(player: Player, payload: any)
		MarvelGirlService.handleAction(player, payload)
	end)

	Remotes.getEvent("ToggleCosmeticHandVfx").OnServerEvent:Connect(function(player: Player, payload: any)
		if type(payload) == "table" and payload.kind == "jean_toggle" then
			MarvelGirlService.toggleCosmeticHandVfx(player)
		elseif type(payload) == "table" and payload.kind == "jean_wings_toggle" then
			MarvelGirlService.togglePhoenixWings(player, if type(payload.on) == "boolean" then payload.on else nil)
		end
	end)

	Remotes.getEvent("MindLink").OnServerEvent:Connect(function(player: Player, payload: any)
		if type(payload) ~= "table" then
			return
		end
		if payload.action == "message" and type(payload.text) == "string" then
			broadcastMindMessage(player, payload.text)
		elseif payload.action == "close" then
			-- Only Jean (link host) can close via chat X
			if mindLinkByPlayer[player] then
				endMindLink(player, true, true)
			end
		elseif payload.action == "astral_input" then
			local move = if typeof(payload.moveDir) == "Vector3" then payload.moveDir
				elseif typeof(payload.moveVector) == "Vector3" then payload.moveVector
				else Vector3.zero
			local look = if typeof(payload.lookDir) == "Vector3" then payload.lookDir
				elseif typeof(payload.lookVector) == "Vector3" then payload.lookVector
				else Vector3.new(0, 0, -1)
			local side = if type(payload.sideInput) == "number" then payload.sideInput else 0
			MarvelGirlService.setAstralInput(player, move, look, side)
		elseif payload.action == "astral_end" then
			endAstral(player, true)
		end
	end)

	-- Astral / flight-style input also via FlightInput when astral active
	Remotes.getUnreliableEvent("FlightInput").OnServerEvent:Connect(function(player: Player, payload: any)
		if not astralByPlayer[player] or type(payload) ~= "table" then
			return
		end
		local move = if typeof(payload.moveDir) == "Vector3" then payload.moveDir
			elseif typeof(payload.moveVector) == "Vector3" then payload.moveVector
			else Vector3.zero
		local look = if typeof(payload.lookDir) == "Vector3" then payload.lookDir
			elseif typeof(payload.lookVector) == "Vector3" then payload.lookVector
			else Vector3.new(0, 0, -1)
		local side = if type(payload.sideInput) == "number" then payload.sideInput else 0
		MarvelGirlService.setAstralInput(player, move, look, side)
	end)

	local function hookPlayer(player: Player)
		player.CharacterRemoving:Connect(function()
			wakeToken[player] = (wakeToken[player] or 0) + 1
			MarvelGirlService.cancelAll(player)
			clearPhoenixDown(player)
			restoreOverloadMove(player, nil)
			overloadHoldByPlayer[player] = nil
			clearManualHandVfx(player)
			clearManualWings(player)
		end)
		player.CharacterAdded:Connect(function(character)
			local humanoid = character:WaitForChild("Humanoid", 5)
			if humanoid and humanoid:IsA("Humanoid") then
				-- Confirmed against Roblox's own documented behavior (not
				-- guesswork): SetStateEnabled(Dead, false) called REACTIVELY
				-- inside a Died handler - after Health has already hit 0
				-- from real damage - does not reliably undo the "true
				-- death" lock; multiple devforum reports describe this exact
				-- symptom. The verified fix is disabling Dead PROACTIVELY,
				-- before any death ever happens.
				--
				-- isPhoenixJean(character) is FALSE at the exact instant
				-- CharacterAdded fires - hero/skin selection sets
				-- LOOK_MODE_ATTRIBUTE to "phoenix" afterward, via a separate
				-- morph step - so a one-shot check here would silently never
				-- run for a freshly-spawned character. Re-check whenever the
				-- relevant attributes actually change, not just once at spawn.
				local phoenixDeadDisabled = false
				local function ensurePhoenixDeadDisabled()
					if phoenixDeadDisabled or not isPhoenixJean(character) then
						return
					end
					phoenixDeadDisabled = true
					pcall(function()
						humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
					end)
				end
				ensurePhoenixDeadDisabled()
				character:GetAttributeChangedSignal(GameConstants.LOOK_MODE_ATTRIBUTE):Connect(ensurePhoenixDeadDisabled)
				character:GetAttributeChangedSignal(GameConstants.HERO_ATTRIBUTE):Connect(ensurePhoenixDeadDisabled)
				-- Config-panel wings toggle only ever applied at click time - a
				-- skin change away from Phoenix afterward left manually-toggled
				-- wings stuck on forever since nothing re-checked eligibility.
				-- Actively watch LOOK_MODE_ATTRIBUTE so a mismatch corrects
				-- (turns wings off) the instant it appears.
				character:GetAttributeChangedSignal(GameConstants.LOOK_MODE_ATTRIBUTE):Connect(function()
					if manualWingsByPlayer[player]
						and Phoenix.hasWings(character)
						and GameConstants.PHOENIX_LOOK_IDS[MarvelGirlService.lookOf(character)] ~= true
					then
						manualWingsByPlayer[player] = nil
						Phoenix.removeWings(character)
					end
				end)
				-- Marvel Girl's eye glow, extended to Telekinesis: TK_ACTIVE_ATTRIBUTE
				-- is owned by the shared TelekinesisService (used by multiple heroes),
				-- not this file - watching it here instead of touching that generic
				-- service keeps the eye VFX Jean-specific without coupling it in.
				local tkEyesOn = false
				character:GetAttributeChangedSignal(GameConstants.TK_ACTIVE_ATTRIBUTE):Connect(function()
					local shouldBeOn = character:GetAttribute(GameConstants.TK_ACTIVE_ATTRIBUTE) == true
						and MarvelGirlService.lookOf(character) == "marvel_girl"
					if shouldBeOn == tkEyesOn then
						return
					end
					tkEyesOn = shouldBeOn
					if shouldBeOn then
						Phoenix.attachMarvelGirlFlightEyes(character)
					else
						Phoenix.removeMarvelGirlFlightEyes(character)
					end
				end)
				-- Detecting "she went down" via HealthChanged instead of
				-- relying on Died (Died only fires from actually entering
				-- the Dead state, which is now blocked once disabled above).
				-- tryPhoenixDown already no-ops on a repeat call, so this is
				-- a safe, redundant trigger alongside the existing
				-- Died-based one below, not a replacement for it - whichever
				-- fires first wins.
				humanoid.HealthChanged:Connect(function(hp)
					if hp <= 0 and isPhoenixJean(character) then
						-- Wrath charge lives on Workspace (server-wide, not
						-- per-character - see CombatHelper.dealDamage), so it
						-- otherwise survives a death/respawn indefinitely.
						-- Reset it here so dying always clears the meter, same
						-- as every other "resurrect"-style readiness bar.
						Workspace:SetAttribute("PhoenixWrathDamageAccum", 0)
						-- Always call this (not gated on ResetForcedDeath) -
						-- tryPhoenixDown itself is what re-enables Dead state
						-- when Reset caused this. Skipping the call entirely
						-- left Dead permanently disabled with nothing left to
						-- ever fire Humanoid.Died - stuck at 0 HP forever,
						-- no ragdoll, no death screen.
						MarvelGirlService.tryPhoenixDown(player, character)
					end
				end)
				require(ReplicatedStorage.Shared.DeathSignal).connect(humanoid, function()
					-- CharacterService's own Died handler runs first (its
					-- init() is called before this file's) and calls
					-- tryPhoenixDown synchronously, so phoenixDownByPlayer is
					-- already set by the time this fires if it just
					-- intercepted this exact death. cancelAll's blanket
					-- cleanup (BUSY_ATTRIBUTE=nil, AutoRotate=true, etc.) has
					-- no business running on a death that isn't actually
					-- resolving as a normal death - she's ragdolled and
					-- waiting on the player's Come Back/Menu choice, not
					-- mid-ability-cast needing a cancel.
					if phoenixDownByPlayer[player] then
						return
					end
					MarvelGirlService.cancelAll(player)
				end)
			end
		end)
	end

	for _, player in Players:GetPlayers() do
		hookPlayer(player)
	end
	Players.PlayerAdded:Connect(hookPlayer)
	Players.PlayerRemoving:Connect(function(player)
		wakeToken[player] = (wakeToken[player] or 0) + 1
		MarvelGirlService.cancelAll(player)
		clearPhoenixDown(player)
		restoreOverloadMove(player, nil)
		overloadHoldByPlayer[player] = nil
		mindLinkMsgCd[player] = nil
		wakeToken[player] = nil
		manualHandVfxByPlayer[player] = nil
	end)
end

-- Gate-free entry points for Rogue's absorbed copies (see RogueService HOLD_HANDLERS).
function MarvelGirlService.runAbsorbed(player: Player, fn: () -> ())
	local character = player.Character
	if not character then
		return
	end
	character:SetAttribute("MgAbsorbedCall", true)
	local ok, err = pcall(fn)
	character:SetAttribute("MgAbsorbedCall", nil)
	if not ok then
		warn("[MarvelGirl] absorbed call failed: " .. tostring(err))
	end
end

function MarvelGirlService.absorbedSlam(player: Player, target: Model?, direction: Vector3?, aimPoint: Vector3?)
	MarvelGirlService.runAbsorbed(player, function()
		castTelekineticSlam(player, target, direction, aimPoint, false)
	end)
end

function MarvelGirlService.absorbedSlamAim(player: Player, aimPoint: Vector3?)
	local character = player.Character
	if character and aimPoint and AbilityCooldownHelper.isActive(character, "telekinetic_slam") then
		character:SetAttribute("MgSlamAim", aimPoint)
	end
end

function MarvelGirlService.absorbedTkStart(player: Player, target: Model?, aimPoint: Vector3?)
	MarvelGirlService.runAbsorbed(player, function()
		startJeanTelekinesis(player, target, aimPoint, nil, false)
	end)
end

function MarvelGirlService.absorbedTkActive(player: Player): boolean
	return TelekinesisService.isActive(player)
end

function MarvelGirlService.absorbedTkRelease(player: Player)
	releaseJeanTelekinesis(player)
end

function MarvelGirlService.absorbedTkThrow(player: Player, target: Model?, direction: Vector3?, aimPoint: Vector3?)
	throwJeanTelekinesis(player, target, direction, aimPoint)
end

function MarvelGirlService.absorbedTkScroll(player: Player, scroll: number?, aimPoint: Vector3?)
	if type(scroll) == "number" then
		TelekinesisService.adjustDistance(player, scroll)
	end
	if aimPoint then
		TelekinesisService.updateAim(player, aimPoint)
	end
end

function MarvelGirlService.absorbedDebrisStart(player: Player, aimPoint: Vector3?)
	MarvelGirlService.runAbsorbed(player, function()
		castTelekineticDebris(player, aimPoint)
	end)
end

function MarvelGirlService.absorbedDebrisRelease(player: Player)
	releaseDebrisHold(player)
end

function MarvelGirlService.absorbedDebrisThrow(player: Player, direction: Vector3?, aimPoint: Vector3?)
	throwNextDebris(player, direction, aimPoint)
end

function MarvelGirlService.absorbedDebrisAim(player: Player, aimPoint: Vector3?)
	local character = player.Character
	if character and aimPoint and AbilityCooldownHelper.isActive(character, "telekinetic_debris") then
		character:SetAttribute("MgDebrisAim", aimPoint)
		local st = debrisByPlayer[player]
		if st then
			st.aimPoint = aimPoint
		end
	end
end

function MarvelGirlService.absorbedCancel(player: Player)
	endDebris(player, false, true)
	releaseJeanTelekinesis(player, false)
end

return MarvelGirlService
