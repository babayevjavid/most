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
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AbilityCooldownHelper = require(ReplicatedStorage.Shared.AbilityCooldownHelper)
local CharacterRegistry = require(ReplicatedStorage.Shared.CharacterRegistry)
local CombatHelper = require(ReplicatedStorage.Shared.CombatHelper)
local ConstraintHelper = require(ReplicatedStorage.Shared.ConstraintHelper)
local GameConstants = require(ReplicatedStorage.Shared.GameConstants)
local ProjectileHelper = require(ReplicatedStorage.Shared.ProjectileHelper)
local PushHelper = require(ReplicatedStorage.Shared.PushHelper)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ScreenFeelHelper = require(ReplicatedStorage.Shared.ScreenFeelHelper)
local VfxHelper = require(ReplicatedStorage.Shared.VfxHelper)
local CharacterService = require(script.Parent.CharacterService)
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
	walk: number?,
	jumpPower: number?,
	jumpHeight: number?,
	animTrack: AnimationTrack?,
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
	align: AlignPosition?,
	attach: Attachment?,
	fx: { Instance },
	ownedParts: { BasePart },
	throwDir: Vector3,
	slam2Host: BasePart?,
	faceConn: RBXScriptConnection?,
	faceAlign: AlignOrientation?,
	faceAtt: Attachment?,
	animTrack: AnimationTrack?,
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
	-- Psychic-pain movement lock (victim saved walk/autoRotate)
	victimWalk: number?,
	victimAutoRotate: boolean?,
}

local barrierByPlayer: { [Player]: BarrierState } = {}
local astralByPlayer: { [Player]: AstralState } = {}
local painByPlayer: { [Player]: PainState } = {}
local phoenixDownByPlayer: { [Player]: { character: Model, reviving: boolean? } } = {}
local phoenixAutoLoadBlocks = 0

local function blockPhoenixAutoRespawn()
	if phoenixAutoLoadBlocks == 0 then
		Players.CharacterAutoLoads = false
	end
	phoenixAutoLoadBlocks += 1
end

local function unblockPhoenixAutoRespawn()
	if phoenixAutoLoadBlocks <= 0 then
		return
	end
	phoenixAutoLoadBlocks -= 1
	if phoenixAutoLoadBlocks == 0 then
		Players.CharacterAutoLoads = true
	end
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
} } = {}
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
		GameConstants.MG_PSI_BOLT_SOUND,
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

local ASTRAL_COLLISION_GROUP = "MarvelGirlAstral"

local function ensureAstralCollisionGroup()
	pcall(function()
		if not PhysicsService:IsCollisionGroupRegistered(ASTRAL_COLLISION_GROUP) then
			PhysicsService:RegisterCollisionGroup(ASTRAL_COLLISION_GROUP)
		end
	end)
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(ASTRAL_COLLISION_GROUP, "Default", false)
		PhysicsService:CollisionGroupSetCollidable(ASTRAL_COLLISION_GROUP, ASTRAL_COLLISION_GROUP, false)
		for _, info in PhysicsService:GetRegisteredCollisionGroups() do
			if type(info) == "table" and type(info.name) == "string" then
				PhysicsService:CollisionGroupSetCollidable(ASTRAL_COLLISION_GROUP, info.name, false)
			end
		end
	end)
end

local function forceAstralNoclip(model: Model)
	ensureAstralCollisionGroup()
	local function stripPart(part: BasePart)
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		pcall(function()
			part.CollisionGroup = ASTRAL_COLLISION_GROUP
		end)
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
	if CombatHelper.arePowersDisabled(character) then
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
			and abilityId ~= "psionic_barrier"
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
		and character:GetAttribute(GameConstants.LOOK_MODE_ATTRIBUTE) ~= "marvel_girl"
		and character:GetAttribute(GameConstants.MG_HAIR_TIED_ATTRIBUTE) ~= true
	then
		return false
	end
	if character:GetAttribute(GameConstants.TK_ACTIVE_ATTRIBUTE) == true and abilityId ~= "telekinesis" then
		return false
	end
	-- One ability at a time (flight + mind link do not block; astral allowed with barrier)
	for _, ab in CharacterRegistry.getAbilities("jean_grey") do
		if ab.passive or ab.id == abilityId or ab.id == "telekinetic_flight" or ab.id == "mind_link" or ab.id == "telekinesis" then
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
	-- Shields block telekinetic grabs/slams/pain: only shield damage, no CC on the holder.
	if CombatHelper.isShielded(victim) then
		return false
	end
	if not CombatHelper.isCombatEligible(victim) then
		return false
	end
	if victim:GetAttribute("LokiUltClone") == true or victim:GetAttribute("LokiDecoy") == true then
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
		for _, model in CombatHelper.overlapCharacters(aimPoint, AIM_POINT_RADIUS, jean) do
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

	local along = CombatHelper.raycastCharacter(jeanRoot.Position, aimDir, range, jean)
	if inRange(along) then
		return along
	end

	local best: Model? = nil
	local bestDist = AIM_LOCK_RADIUS
	for _, model in CombatHelper.overlapCharacters(jeanRoot.Position, range, jean) do
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
	local along = CombatHelper.raycastCharacter(jeanRoot.Position, aimDir, range, jean)
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

local function attachCloneToPart(template: Instance, part: BasePart, emitCount: number?): Instance?
	local clone = template:Clone()
	if clone:IsA("Attachment") then
		clone.Position = Vector3.zero
		clone.Orientation = Vector3.zero
	end
	clone.Parent = part
	VfxHelper.setParticlesEnabled(clone, true)
	local n = emitCount or 6
	for _, em in VfxHelper.collectParticleEmitters(clone) do
		em:Emit(n)
	end
	if clone:IsA("ParticleEmitter") then
		clone:Emit(n)
	end
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

local function playWorldSound(soundId: string, at: Vector3, volume: number?, playbackSpeed: number?)
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
	task.delay(8, function()
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

local faceTokenByCharacter: { [Model]: number } = {}

--[[ Smooth yaw turn toward a world point (bolt / debris throws). ]]
local function smoothFaceToward(character: Model, worldPoint: Vector3, holdSeconds: number?)
	if character:GetAttribute(GameConstants.IS_FLYING_ATTRIBUTE) == true then
		return
	end
	local root = getRoot(character)
	local hum = CombatHelper.getHumanoid(character)
	if not root or not hum or hum.Health <= 0 then
		return
	end
	local flat = Vector3.new(worldPoint.X - root.Position.X, 0, worldPoint.Z - root.Position.Z)
	if flat.Magnitude < 0.08 then
		return
	end
	flat = flat.Unit
	local targetCf = CFrame.lookAt(root.Position, root.Position + flat)

	local token = (faceTokenByCharacter[character] or 0) + 1
	faceTokenByCharacter[character] = token

	local att = root:FindFirstChild("MgFaceAtt")
	if not (att and att:IsA("Attachment")) then
		if att then
			att:Destroy()
		end
		att = Instance.new("Attachment")
		att.Name = "MgFaceAtt"
		att.Parent = root
	end

	local existing = root:FindFirstChild("MgFaceAlign")
	if existing then
		existing:Destroy()
	end
	local align = Instance.new("AlignOrientation")
	align.Name = "MgFaceAlign"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = att
	align.RigidityEnabled = false
	align.MaxTorque = 250000
	align.Responsiveness = GameConstants.MG_FACE_RESPONSIVENESS
	align.CFrame = targetCf
	align.Parent = root

	local origAuto = hum.AutoRotate
	hum.AutoRotate = false
	local hold = holdSeconds or 0.5
	task.delay(hold, function()
		if faceTokenByCharacter[character] ~= token then
			return
		end
		if align.Parent then
			align:Destroy()
		end
		if att.Parent and att.Name == "MgFaceAtt" then
			att:Destroy()
		end
		if hum.Parent and hum.Health > 0 then
			local flying = character:GetAttribute(GameConstants.IS_FLYING_ATTRIBUTE) == true
			hum.AutoRotate = if flying then false else true
		end
	end)
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

--[[ Recolor Jean ability FX: X-Men '97 blue, Marvel Girl pink. ]]
local function isJean97(character: Model?): boolean
	if not character then
		return false
	end
	local skin = character:GetAttribute(GameConstants.LOOK_MODE_ATTRIBUTE)
	if skin == "marvel_girl" or skin == "phoenix" then
		return false
	end
	return true
end

local function jeanAccent(character: Model?): Color3
	if character and character:GetAttribute(GameConstants.LOOK_MODE_ATTRIBUTE) == "phoenix" then
		return GameConstants.MG_PSI_COLOR_PHOENIX
	end
	if isJean97(character) then
		return GameConstants.MG_PSI_COLOR
	end
	return GameConstants.MG_PSI_COLOR_MARVEL_GIRL
end

local function jeanScreenTint(character: Model?): Color3
	if character and character:GetAttribute(GameConstants.LOOK_MODE_ATTRIBUTE) == "marvel_girl" then
		return GameConstants.MG_PSI_COLOR_MARVEL_GIRL
	end
	return GameConstants.MG_PSI_COLOR
end

local function getPhoenixAsset(...: string): Instance?
	return VfxHelper.getMarvelGirlAsset("JeanGreyPhoenix", ...)
end

local function styleJeanFx(root: Instance, lifeSeconds: number?, character: Model?)
	local color = jeanAccent(character)
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
	if not isJean97(character) then
		return nil
	end
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

local function restoreJeanHeadPart(state: { headPart: BasePart?, headPartMaterial: Enum.Material? })
	local part = state.headPart
	local material = state.headPartMaterial
	if part and part.Parent and material then
		part.Material = material
	end
	state.headPart = nil
	state.headPartMaterial = nil
end

local function beginJeanHeadGlow(character: Model, state: { headPart: BasePart?, headPartMaterial: Enum.Material? })
	if state.headPart then
		return
	end
	local part = findBaseJeanHeadPart(character)
	if not part then
		return
	end
	state.headPart = part
	state.headPartMaterial = part.Material
	part.Material = Enum.Material.Neon
end

local function beginPowerFx(character: Model)
	local existing = powerFxByCharacter[character]
	if existing then
		existing.refs += 1
		beginJeanHeadGlow(character, existing)
		return
	end
	local instances: { Instance } = {}
	local right = getHand(character, true)
	local left = getHand(character, false)
	if character:GetAttribute(GameConstants.LOOK_MODE_ATTRIBUTE) == "phoenix" then
		local templates: { Instance } = {}
		for i = 1, 5 do
			local template = getPhoenixAsset("HandVFX", "ParticleEmitter" .. tostring(i))
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
						table.insert(instances, fx)
					end
				end
			end
		end
		powerFxByCharacter[character] = { instances = instances, refs = 1 }
		beginJeanHeadGlow(character, powerFxByCharacter[character])
		return
	end
	local rightTemplate = VfxHelper.getMarvelGirlAsset("HandVFXRightAttachment")
		or VfxHelper.getMarvelGirlAsset("HandAttachment")
	local leftTemplate = VfxHelper.getMarvelGirlAsset("HandVFXLeftAttachment")
		or VfxHelper.getMarvelGirlAsset("HandAttachment")
	if right and rightTemplate then
		local fx = attachCloneToPart(rightTemplate, right, 1)
		if fx then
			styleJeanFx(fx, nil, character)
			table.insert(instances, fx)
		end
	end
	if left and left ~= right and leftTemplate then
		local fx = attachCloneToPart(leftTemplate, left, 1)
		if fx then
			styleJeanFx(fx, nil, character)
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
			table.insert(instances, fx)
		end
	end
	powerFxByCharacter[character] = { instances = instances, refs = 1 }
	beginJeanHeadGlow(character, powerFxByCharacter[character])
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
	for _, inst in fx.instances do
		if inst.Parent then
			VfxHelper.setParticlesEnabled(inst, false)
			task.delay(3, function()
				if inst.Parent then
					inst:Destroy()
				end
			end)
		end
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
	for _, inst in fx.instances do
		if inst.Parent then
			VfxHelper.setParticlesEnabled(inst, false)
			task.delay(3, function()
				if inst.Parent then
					inst:Destroy()
				end
			end)
		end
	end
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
	root.Anchored = true
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
local function castPsionicBolt(player: Player, direction: Vector3?, aimPoint: Vector3?)
	local character = player.Character
	if not character then
		return
	end
	local entry = CharacterRegistry.getAbilityById("jean_grey", "psionic_bolt")
	if not entry or not canUse(character, entry.id, GameConstants.MG_PSI_BOLT_ENERGY) then
		return
	end

	AbilityCooldownHelper.setActive(character, entry.id, true)
	character:SetAttribute(GameConstants.BUSY_ATTRIBUTE, true)
	attachPowerFx(character)
	playJeanAnim(character, GameConstants.MG_PSI_BOLT_ANIM, false)
	fireCameraShake(player, 0.5, 0.38, 0.36, 0.55)
	local boltRoot = getRoot(character)
	if boltRoot then
		playWorldSound(GameConstants.MG_PSI_BOLT_SOUND, boltRoot.Position, 0.85)
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
		end
		task.wait(GameConstants.MG_PSI_BOLT_WINDUP)
		if hum and hum.Parent then
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
		end
		for i = 1, GameConstants.MG_PSI_BOLT_COUNT do
			if not character.Parent or player.Character ~= character then
				break
			end
			local liveAim = character:GetAttribute("MgBoltAim")
			local shotAim: Vector3? = if typeof(liveAim) == "Vector3" then liveAim else aimPoint
			local head = getHead(character)
			local headPos = if head then head.Position else character:GetPivot().Position
			-- Spawn from a random point around the head, still aimed at live cursor / aim
			local jitter = Vector3.new(
				(math.random() * 2 - 1) * 1.15,
				(math.random() * 2 - 1) * 0.75,
				(math.random() * 2 - 1) * 1.15
			)
			local origin = headPos + jitter
			local dir: Vector3
			if shotAim then
				local toAim = shotAim - origin
				dir = if toAim.Magnitude > 0.05 then toAim.Unit else resolveAimDir(character, direction, shotAim)
			else
				dir = resolveAimDir(character, direction, nil)
			end
			ProjectileHelper.spawn(origin, dir, {
				speed = GameConstants.MG_PSI_BOLT_SPEED,
				damage = GameConstants.MG_PSI_BOLT_DAMAGE,
				radius = GameConstants.MG_PSI_BOLT_HIT_RADIUS,
				maxDistance = GameConstants.MG_PSI_BOLT_RANGE,
				color = jeanAccent(character),
				owner = character,
				homeDir = dir,
				homePoint = shotAim,
				homeAfter = 0.08,
				homeTurnScale = 0.78,
				liveHomeAimAttribute = "MgBoltAim",
				impactFx = "psionic",
				boltFolder = "JeanGrey",
				boltAsset = "PsychicBolt",
				recolorVisual = true,
				onHit = function(victim: Model)
					local tint = jeanScreenTint(character)
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
			})
			if i < GameConstants.MG_PSI_BOLT_COUNT then
				task.wait(GameConstants.MG_PSI_BOLT_SPACING)
			end
		end
		if character.Parent then
			character:SetAttribute("MgBoltAim", nil)
			endPowerFx(character)
			if AbilityCooldownHelper.isActive(character, entry.id) then
				finishAbility(character, entry.id, GameConstants.MG_PSI_BOLT_COOLDOWN)
			end
		end
	end)
end

----------------------------------------------------------------
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

local function applyPsychicPull(victim: Model, jean: Model)
	local vRoot = getRoot(victim)
	local jeanRoot = getRoot(jean)
	local hum = CombatHelper.getHumanoid(victim)
	if not vRoot or not jeanRoot or not hum or hum.Health <= 0 or vRoot.Anchored then
		return
	end
	if not isValidTkVictim(victim, jean) then
		return
	end

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
		for _, template in templates do
			local clone = template:Clone()
			clone.Parent = vRoot
			styleJeanFx(clone, GameConstants.MG_PULL_FX_LIFE, jean)
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
		end
	end)
end

local function castPsychicPull(player: Player, target: Model?, direction: Vector3?, aimPoint: Vector3?, lockOn: boolean?)
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

local function launchJeanPushVictim(character: Model, victim: Model, direction: Vector3?, aimPoint: Vector3?)
	local jeanRoot = getRoot(character)
	local vRoot = getRoot(victim)
	local vHum = CombatHelper.getHumanoid(victim)
	if not jeanRoot or not vRoot or not vHum then
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

local function releaseJeanTelekinesis(player: Player, applyCooldown: boolean?)
	local character = player.Character
	local wasActive = TelekinesisService.isActive(player)
	TelekinesisService.release(player)
	if character then
		endPowerFx(character)
		if wasActive and applyCooldown ~= false then
			finishAbility(character, "telekinesis", GameConstants.MG_PUSH_COOLDOWN)
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
	local held = TelekinesisService.takeHeldForJeanPush(player)
	if #held == 0 then
		return
	end
	beginPowerFx(character)
	fireCameraShake(player, 0.55, 1.05, 0.38, 0.72)
	for _, victim in held do
		launchJeanPushVictim(character, victim, direction, aimPoint)
	end
	finishAbility(character, "telekinesis", GameConstants.MG_PUSH_COOLDOWN)
	task.delay(GameConstants.MG_PUSH_DRAW_TIME + 0.35, function()
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
	local anim = Instance.new("Animation")
	anim.AnimationId = animId
	local ok, track = pcall(function()
		return (animator :: Animator):LoadAnimation(anim)
	end)
	anim:Destroy()
	if not ok or not track then
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
		ScreenFeelHelper.setShakeHold(state.victim, false)
		ScreenFeelHelper.setTint(state.victim, nil)
	end
	local astral = astralByPlayer[player]
	if astral and astral.astral.Parent then
		astral.astral:SetAttribute(GameConstants.MG_PAIN_LOOK_ATTRIBUTE, nil)
	end
	if state.fx and state.fx.Parent then
		VfxHelper.smoothDisableParticles(state.fx, 0.22)
		local fx = state.fx
		task.delay(0.28, function()
			if fx.Parent then
				fx:Destroy()
			end
		end)
	end
	fadeStopSound(state.sound, GameConstants.MG_PAIN_SFX_FADE)
	-- Restore the victim's movement that psychic pain locked.
	if state.victim and state.victim.Parent then
		local vHum = CombatHelper.getHumanoid(state.victim)
		if vHum and vHum.Parent then
			if type(state.victimWalk) == "number" then
				vHum.WalkSpeed = state.victimWalk
			end
			if type(state.victimAutoRotate) == "boolean" then
				vHum.AutoRotate = state.victimAutoRotate
			end
		end
	end
	-- Always tear down hand VFX refs (even if the body was removed) to avoid leaked emitters.
	if state.body then
		endPowerFx(state.body)
	end
	if state.body and state.body.Parent then
		state.body:SetAttribute(GameConstants.MG_PAIN_LOOK_ATTRIBUTE, nil)
		state.body:SetAttribute(GameConstants.MG_PAIN_END_AT_ATTRIBUTE, nil)
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
	if not CharacterService.spendEnergy(body, GameConstants.MG_PAIN_ENERGY) then
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
	local victimAnimTrack = playJeanAnim(victim, GameConstants.MG_PAIN_TARGET_ANIM, true)
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
		victimWalk = nil,
		victimAutoRotate = nil,
		sound = nil,
		tickAcc = 0,
		animTrack = animTrack,
		victimAnimTrack = victimAnimTrack,
		startedAt = AbilityCooldownHelper.getNow(),
	}
	local vRoot = getRoot(victim)
	if vRoot then
		body:SetAttribute(GameConstants.MG_PAIN_LOOK_ATTRIBUTE, vRoot.Position)
		astral.astral:SetAttribute(GameConstants.MG_PAIN_LOOK_ATTRIBUTE, vRoot.Position)
	end
	-- Movement-lock the victim while psychically pained: they can't walk/strafe away from the hold.
	local painState = painByPlayer[player]
	local vHum = CombatHelper.getHumanoid(victim)
	if vHum and vHum.Parent then
		painState.victimWalk = vHum.WalkSpeed
		painState.victimAutoRotate = vHum.AutoRotate
		vHum.WalkSpeed = 0
		vHum.AutoRotate = false
	end
	if vRoot and not vRoot.Anchored then
		vRoot.AssemblyLinearVelocity = Vector3.new(0, math.min(0, vRoot.AssemblyLinearVelocity.Y), 0)
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
	-- Hold the victim in place each tick while psychically pained (preserve gravity on Y).
	if vRoot and not vRoot.Anchored then
		vRoot.AssemblyLinearVelocity = Vector3.new(0, math.min(0, vRoot.AssemblyLinearVelocity.Y), 0)
	end
	state.tickAcc += dt
	if state.tickAcc >= GameConstants.MG_PAIN_TICK then
		local slice = state.tickAcc
		state.tickAcc = 0
		CombatHelper.dealDamage(
			state.body,
			state.victim,
			GameConstants.MG_PAIN_DAMAGE_PER_SEC * slice,
			vRoot.Position,
			"dot"
		)
	end
end

local function outburstAoe(body: Model, pos: Vector3)
	for _, victim in CombatHelper.overlapCharacters(pos, GameConstants.MG_OUTBURST_RADIUS, body) do
		if victim:GetAttribute(GameConstants.MG_ASTRAL_ATTRIBUTE) == true then
			continue
		end
		-- Shields absorb the outburst damage but block all knockback/fling/ragdoll from it.
		CombatHelper.dealDamage(body, victim, GameConstants.MG_OUTBURST_DAMAGE, pos, "projectile")
		if CombatHelper.isShielded(victim) then
			continue
		end
		RagdollService.applyTimed(victim, GameConstants.MG_OUTBURST_RAGDOLL)
		local away = Vector3.zero
		local vRoot = getRoot(victim)
		if vRoot then
			away = vRoot.Position - pos
		end
		PushHelper.applyToCharacter(victim, if away.Magnitude > 0.05 then away.Unit else Vector3.new(0, 0, -1), {
			speed = GameConstants.MG_OUTBURST_KNOCK,
			upBoost = 22,
		})
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
	VfxHelper.setParticlesEnabled(fx, true)
	VfxHelper.emitAllParticles(fx, 16)
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
	local anim = Instance.new("Animation")
	anim.AnimationId = GameConstants.MG_WAKE_ANIM
	local ok, track = pcall(function()
		return (animator :: Animator):LoadAnimation(anim)
	end)
	anim:Destroy()
	if not ok or not track then
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
	local pony = other:FindFirstChild("PonytailHair")
	if not main or not pony then
		return
	end
	local showPonytails = isHairVisible(main)
	tweenHairTree(main, not showPonytails)
	tweenHairTree(pony, showPonytails)
	local ponyTail = pony:FindFirstChild("PonyTail")
	if ponyTail then
		tweenHairTree(ponyTail, showPonytails)
	end
	character:SetAttribute(GameConstants.MG_HAIR_TIED_ATTRIBUTE, showPonytails)
end

local function playJeanHairToggle(player: Player, character: Model)
	if character:GetAttribute(GameConstants.LOOK_MODE_ATTRIBUTE) == "marvel_girl" then
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
		local anim = Instance.new("Animation")
		anim.AnimationId = GameConstants.MG_HAIR_ANIM
		local ok, track = pcall(function()
			return (animator :: Animator):LoadAnimation(anim)
		end)
		anim:Destroy()
		if ok and track then
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
	if not overloaded then
		if flying then
			current += GameConstants.MG_RESTRAINT_FLIGHT_PER_SEC * dt
		end
		if tkOn then
			current += GameConstants.MG_RESTRAINT_TK_PER_SEC * dt
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

local function createBarrierHpBillboard(parent: Instance, forJean97: boolean): (BillboardGui, TextLabel, Frame)
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
	fill.BackgroundColor3 = if forJean97 then GameConstants.MG_PSI_COLOR else GameConstants.MG_PSI_COLOR_MARVEL_GIRL
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
		local hum = CombatHelper.getHumanoid(character)
		if hum and hum.Parent then
			if character:GetAttribute(GameConstants.MG_ASTRAL_BODY_ATTRIBUTE) ~= true then
				if type(state.walk) == "number" then
					hum.WalkSpeed = state.walk
				else
					hum.WalkSpeed = GameConstants.DEFAULT_WALK_SPEED
				end
				if state.jumpPower ~= nil then
					hum.JumpPower = state.jumpPower
				end
				if state.jumpHeight ~= nil then
					hum.JumpHeight = state.jumpHeight
				end
			end
		end
		state.character:SetAttribute(GameConstants.SHIELD_ACTIVE_ATTRIBUTE, nil)
		state.character:SetAttribute(GameConstants.MG_BARRIER_ATTRIBUTE, nil)
		state.character:SetAttribute(GameConstants.SHIELD_HP_ATTRIBUTE, nil)
		AbilityCooldownHelper.setActive(state.character, "psionic_barrier", false)
		endPowerFx(state.character)
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
	if CombatHelper.arePowersDisabled(character) then
		return
	end
	if character:GetAttribute(GameConstants.MG_ASTRAL_ATTRIBUTE) == true then
		return
	end
	if AbilityCooldownHelper.isOnCooldown(character, entry.id) then
		return
	end

	local root = getRoot(character)
	if not root then
		return
	end
	local template = if character:GetAttribute(GameConstants.LOOK_MODE_ATTRIBUTE) == "phoenix"
		then getPhoenixAsset("Shield")
		else (VfxHelper.getMarvelGirlAsset("Shield") or VfxHelper.getMarvelGirlAsset("Forcefield"))
	if not template then
		warn("[MarvelGirl] Missing Jean shield asset")
		return
	end

	AbilityCooldownHelper.setActive(character, entry.id, true)
	attachPowerFx(character)
	local animTrack = playBarrierAnim(character)

	local ff = template:Clone()
	ff.Name = "MgShield"
	styleJeanFx(ff, nil, character)
	VfxHelper.setParticlesEnabled(ff, true)
	VfxHelper.emitAllParticles(ff, 8)
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

	local maxHp = GameConstants.MG_BARRIER_HP
	character:SetAttribute(GameConstants.SHIELD_ACTIVE_ATTRIBUTE, true)
	character:SetAttribute(GameConstants.MG_BARRIER_ATTRIBUTE, true)
	character:SetAttribute(GameConstants.SHIELD_HP_ATTRIBUTE, maxHp)

	local billboard, hpLabel, hpFill = createBarrierHpBillboard(character, isJean97(character))
	local astralBody = character:GetAttribute(GameConstants.MG_ASTRAL_BODY_ATTRIBUTE) == true
	local hum = CombatHelper.getHumanoid(character)
	local savedWalk = GameConstants.DEFAULT_WALK_SPEED
	local savedJumpPower: number? = nil
	local savedJumpHeight: number? = nil
	if hum then
		savedWalk = hum.WalkSpeed
		if hum.UseJumpPower then
			savedJumpPower = hum.JumpPower
		else
			savedJumpHeight = hum.JumpHeight
		end
		if not astralBody then
			if hum.UseJumpPower then
				hum.JumpPower = 0
			else
				hum.JumpHeight = 0
			end
			hum.WalkSpeed = GameConstants.MG_BARRIER_WALK_SPEED
		end
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
		walk = savedWalk,
		jumpPower = savedJumpPower,
		jumpHeight = savedJumpHeight,
		animTrack = animTrack,
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
			if hum and hum.Health > 0 then
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
		AbilityCooldownHelper.setActive(state.body, "astral_projection", false)
		endPowerFx(state.body)
		if applyCooldown then
			AbilityCooldownHelper.applyAfterUse(state.body, "astral_projection", GameConstants.MG_ASTRAL_COOLDOWN)
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
			forceAstralNoclip(state.astral)
			task.wait()
		end
		if astralByPlayer[player] == state then
			astralByPlayer[player] = nil
			finishAstralCleanup(player, state, applyCooldown)
		end
	end)
end

local function startAstral(player: Player)
	local character = player.Character
	if not character or astralByPlayer[player] then
		return
	end
	-- Cannot astral while flying
	if HexFlightService.isFlying(player) then
		return
	end
	local entry = CharacterRegistry.getAbilityById("jean_grey", "astral_projection")
	if not entry or not canUse(character, entry.id, GameConstants.MG_ASTRAL_ENERGY) then
		return
	end
	-- Shield can stay up; astral still drains energy from the body

	local root = getRoot(character)
	local hum = CombatHelper.getHumanoid(character)
	if not root or not hum then
		return
	end

	AbilityCooldownHelper.setActive(character, entry.id, true)
	beginPowerFx(character)

	local ok, clone = pcall(function()
		local was = character.Archivable
		character.Archivable = true
		local c = character:Clone()
		character.Archivable = was
		return c
	end)
	if not ok or not clone or not clone:IsA("Model") then
		finishAbility(character, entry.id, 1)
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
			desc.CanQuery = false
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
	local highlightTemplate = VfxHelper.getMarvelGirlAsset("AstralProjection", "Highlight")
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

	local pe1 = VfxHelper.getMarvelGirlAsset("AstralProjection", "ParticleEmitter1")
	local pe2 = VfxHelper.getMarvelGirlAsset("AstralProjection", "ParticleEmitter2")
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
		finishAbility(character, entry.id, 1)
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
		if desc:IsA("BasePart") then
			forceAstralNoclip(clone)
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

	local healthConn = hum.HealthChanged:Connect(function(hp)
		if astralHum.Parent then
			astralHum.Health = hp
		end
		if hp <= 0 then
			endAstral(player, true, true)
		end
	end)

	astralHum.HealthChanged:Connect(function(hp)
		if hp < hum.Health then
			astralHum.Health = hum.Health
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
	}

	Remotes.getEvent("MindLink"):FireClient(player, {
		phase = "astral_start",
		astralName = clone.Name,
	})
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
	fireMindLink(state.members, {
		phase = "message",
		from = player.DisplayName,
		text = clean,
	})
	-- MindLinker echo for testing
	local linker = Workspace:FindFirstChild("MindLinker")
	if linker and state.character == (Players:GetPlayerFromCharacter(state.character) and state.character) then
		-- no-op visual; host already in chat
	end
end

----------------------------------------------------------------
-- Telekinetic Slam (grab → slam x3 → throw toward cursor)
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

local function spawnGroundSlamImpact(pos: Vector3, caster: Model?, ...: Instance)
	local template = VfxHelper.getMarvelGirlAsset("TelekineticSlam", "GroundSlamImpactAttachment")
	if not template then
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { ... }
	local hit = Workspace:Raycast(pos + Vector3.new(0, 6, 0), Vector3.new(0, -40, 0), params)
	local floorPos = if hit then hit.Position else Vector3.new(pos.X, pos.Y - GameConstants.MG_SLAM_GROUND_HEIGHT, pos.Z)
	local up = if hit then hit.Normal else Vector3.yAxis
	if up.Magnitude < 0.05 then
		up = Vector3.yAxis
	else
		up = up.Unit
	end
	-- Sit flat on the ground under the target; tip attachment upward along surface normal
	local hostCf = CFrame.lookAt(floorPos, floorPos + up) * CFrame.Angles(math.rad(-90), 0, 0)
	local host = makeFxHost("MgGroundSlamImpact", hostCf + up * 0.04)
	local fx = template:Clone()
	if fx:IsA("Attachment") then
		fx.Position = Vector3.zero
		fx.Orientation = Vector3.new(0, 0, 0)
	end
	fx.Parent = host
	-- Keep authored ground-slam impact colors (do not recolor for base Jean)
	VfxHelper.setParticlesEnabled(fx, true)
	VfxHelper.emitAllParticles(fx, 22)
	VfxHelper.disableImpactSoon(fx)
	retireFx(host, 0.55, 3.5)
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

local function playSlamAnim(character: Model): AnimationTrack?
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
	anim.AnimationId = GameConstants.MG_SLAM_ANIM
	local ok, track = pcall(function()
		return (animator :: Animator):LoadAnimation(anim)
	end)
	anim:Destroy()
	if not ok or not track then
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
		local leftover = root:FindFirstChild("MgFaceAlign")
		if leftover then
			leftover:Destroy()
		end
		local leftoverAtt = root:FindFirstChild("MgFaceAtt")
		if leftoverAtt then
			leftoverAtt:Destroy()
		end
	end
	restorePullOwnership(character, hold.ownedParts)
	local animate = character:FindFirstChild("Animate")
	if animate and animate:IsA("Script") then
		animate.Disabled = hold.animateWasDisabled == true
	end
	if character:GetAttribute(GameConstants.BUSY_ATTRIBUTE) == true then
		character:SetAttribute(GameConstants.BUSY_ATTRIBUTE, nil)
	end
	faceTokenByCharacter[character] = (faceTokenByCharacter[character] or 0) + 1
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
	if state.animTrack then
		state.animTrack:Stop(0)
		state.animTrack = nil
	end
	unlockSlamCaster(player, state.character)

	if state.align then
		state.align:Destroy()
		state.align = nil
	end
	if state.attach then
		state.attach:Destroy()
		state.attach = nil
	end
	if state.slam2Host then
		retireFx(state.slam2Host, 0.55, 3.5)
		state.slam2Host = nil
	end
	clearSlamFx(state.fx)
	if state.character.Parent then
		endPowerFx(state.character)
	end

	local victim = state.victim
	if victim.Parent then
		victim:SetAttribute(GameConstants.MG_SLAM_HELD_ATTRIBUTE, nil)
		setVictimControlled(victim, false)
		if throw and state.vRoot.Parent then
			local dir = state.throwDir
			if dir.Magnitude < 0.05 then
				dir = Vector3.new(0, 0, -1)
			else
				dir = dir.Unit
			end
			-- Shield-first: shielded victims still take the throw damage (routed to their shield),
			-- but are never flung or ragdolled.
			if CombatHelper.isShielded(victim) then
				CombatHelper.dealDamage(
					state.character,
					victim,
					GameConstants.MG_SLAM_THROW_DAMAGE,
					state.vRoot.Position,
					"projectile"
				)
			else
				state.vRoot.AssemblyLinearVelocity = dir * GameConstants.MG_SLAM_THROW_SPEED
				+ Vector3.new(0, GameConstants.MG_SLAM_THROW_UP, 0)
				CombatHelper.dealDamage(
					state.character,
					victim,
					GameConstants.MG_SLAM_THROW_DAMAGE,
					state.vRoot.Position,
					"projectile"
				)
				RagdollService.applyTimed(victim, GameConstants.MG_SLAM_RAGDOLL_TIME)
			end
		elseif victim:GetAttribute(GameConstants.RAGDOLLED_ATTRIBUTE) == true then
			RagdollService.applyTimed(victim, math.min(1.2, GameConstants.MG_SLAM_RAGDOLL_TIME))
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

local function moveAlignTo(align: AlignPosition, target: Vector3, duration: number, token: number, state: SlamState, player: Player): boolean
	local t0 = os.clock()
	local start = state.vRoot.Position
	while os.clock() - t0 < duration do
		if slamByPlayer[player] ~= state or state.token ~= token then
			return false
		end
		if not state.victim.Parent or not state.vRoot.Parent or not state.character.Parent then
			return false
		end
		if state.character:GetAttribute(GameConstants.RAGDOLLED_ATTRIBUTE) == true then
			return false
		end
		local a = math.clamp((os.clock() - t0) / duration, 0, 1)
		local s = a * a * (3 - 2 * a)
		align.Position = start:Lerp(target, s)
		state.vRoot.AssemblyLinearVelocity = Vector3.zero
		task.wait()
	end
	align.Position = target
	return true
end

local function groundPointNear(jeanRoot: BasePart, victimPos: Vector3, exclude: Model): Vector3
	local origin = Vector3.new(victimPos.X, victimPos.Y + 10, victimPos.Z)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local filter: { Instance } = { exclude }
	if jeanRoot.Parent then
		table.insert(filter, jeanRoot.Parent)
	end
	params.FilterDescendantsInstances = filter
	local hit = Workspace:Raycast(origin, Vector3.new(0, -80, 0), params)
	if hit then
		return hit.Position + Vector3.new(0, GameConstants.MG_SLAM_GROUND_HEIGHT, 0)
	end
	return Vector3.new(victimPos.X, math.min(victimPos.Y, jeanRoot.Position.Y), victimPos.Z)
end

--[[ Lift to Jean's left / right / left, then slam down to the ground. ]]
local function slamWindup(jeanRoot: BasePart, anchor: Vector3, hoverHeight: number, slamIndex: number): Vector3
	local sideSign = if slamIndex == 2 then 1 else -1
	local side = jeanRoot.CFrame.RightVector * (sideSign * GameConstants.MG_SLAM_SIDE_DIST)
	return anchor + side + Vector3.new(0, hoverHeight, 0)
end

local function castTelekineticSlam(player: Player, target: Model?, direction: Vector3?, aimPoint: Vector3?, lockOn: boolean?)
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
	if victim:GetAttribute("LokiUltClone") == true or victim:GetAttribute("LokiDecoy") == true then
		return
	end
	if not canUse(character, entry.id, GameConstants.MG_SLAM_ENERGY) then
		return
	end

	AbilityCooldownHelper.setActive(character, entry.id, true)
	beginPowerFx(character)
	lockSlamCaster(player, character)

	local slamDuration = GameConstants.MG_SLAM_LIFT_TIME
		+ GameConstants.MG_SLAM_COUNT * (GameConstants.MG_SLAM_DOWN_TIME + GameConstants.MG_SLAM_GROUND_HOLD + GameConstants.MG_SLAM_UP_TIME)
		+ GameConstants.MG_SLAM_THROW_DELAY
		+ 0.6
	smoothFaceToward(character, vRoot.Position, slamDuration)

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
	RagdollService.apply(victim)
	pcall(function()
		vHum:ChangeState(Enum.HumanoidStateType.Physics)
	end)
	vHum.AutoRotate = false

	local att = Instance.new("Attachment")
	att.Name = "MgSlamAtt"
	att.Parent = vRoot

	local align = Instance.new("AlignPosition")
	align.Name = "MgSlamPos"
	align.Mode = Enum.PositionAlignmentMode.OneAttachment
	align.Attachment0 = att
	align.ApplyAtCenterOfMass = true
	align.MaxForce = 1e9
	align.MaxVelocity = 95
	align.Responsiveness = 42
	align.Position = vRoot.Position
	align.Parent = vRoot

	local fxList: { Instance } = {}
	local slam1 = attachSlamAttachment(vRoot, "TelekineticSlam1Attachment", Vector3.zero, character)
	if slam1 then
		table.insert(fxList, slam1)
	end

	local token = 1
	local state: SlamState = {
		character = character,
		victim = victim,
		vRoot = vRoot,
		token = token,
		align = align,
		attach = att,
		fx = fxList,
		ownedParts = ownedParts,
		throwDir = throwDir,
		slam2Host = nil,
		faceConn = nil,
		faceAlign = nil,
		faceAtt = nil,
		animTrack = playSlamAnim(character),
	}
	slamByPlayer[player] = state

	local faceAtt = Instance.new("Attachment")
	faceAtt.Name = "MgSlamFaceAtt"
	faceAtt.Parent = jeanRoot
	local faceAlign = Instance.new("AlignOrientation")
	faceAlign.Name = "MgSlamFaceAlign"
	faceAlign.Mode = Enum.OrientationAlignmentMode.OneAttachment
	faceAlign.Attachment0 = faceAtt
	faceAlign.RigidityEnabled = false
	faceAlign.MaxTorque = 250000
	faceAlign.Responsiveness = 9
	faceAlign.Parent = jeanRoot
	state.faceAtt = faceAtt
	state.faceAlign = faceAlign
	state.faceConn = RunService.Heartbeat:Connect(function()
		if slamByPlayer[player] ~= state or not state.faceAlign then
			return
		end
		if not jeanRoot.Parent or not vRoot.Parent then
			return
		end
		local flat = Vector3.new(vRoot.Position.X - jeanRoot.Position.X, 0, vRoot.Position.Z - jeanRoot.Position.Z)
		if flat.Magnitude < 0.08 then
			return
		end
		state.faceAlign.CFrame = CFrame.lookAt(jeanRoot.Position, jeanRoot.Position + flat.Unit)
	end)

	task.spawn(function()
		-- Slam in place on target XZ; each lift comes from a randomized side/height
		local basePos = vRoot.Position
		local ground = groundPointNear(jeanRoot, basePos, victim)
		local hoverH = GameConstants.MG_SLAM_HOVER_HEIGHT
		local topY = ground.Y + hoverH
		local windup = slamWindup(jeanRoot, ground, hoverH, 1)
		if windup.Y > topY then
			windup = Vector3.new(windup.X, topY, windup.Z)
		end
		if not moveAlignTo(align, windup, GameConstants.MG_SLAM_LIFT_TIME, token, state, player) then
			endSlam(player, true, false)
			return
		end

		for i = 1, GameConstants.MG_SLAM_COUNT do
			if slamByPlayer[player] ~= state or state.token ~= token then
				return
			end
			ground = groundPointNear(jeanRoot, Vector3.new(basePos.X, ground.Y, basePos.Z), victim)
			if not moveAlignTo(align, ground, GameConstants.MG_SLAM_DOWN_TIME, token, state, player) then
				endSlam(player, true, false)
				return
			end
			CombatHelper.dealDamage(character, victim, GameConstants.MG_SLAM_DAMAGE, ground, "projectile")
			-- Impact on the floor under the slam point (not the elevated victim root)
			spawnGroundSlamImpact(Vector3.new(basePos.X, ground.Y, basePos.Z), character, victim, character)
			fireCameraShake(player, 0.7, 0.38, 0.52, 0.85)
			vRoot.AssemblyLinearVelocity = Vector3.zero
			task.wait(GameConstants.MG_SLAM_GROUND_HOLD)
			if i < GameConstants.MG_SLAM_COUNT then
				windup = slamWindup(jeanRoot, ground, hoverH, i + 1)
				if windup.Y > topY then
					windup = Vector3.new(windup.X, topY, windup.Z)
				end
				if not moveAlignTo(align, windup, GameConstants.MG_SLAM_UP_TIME, token, state, player) then
					endSlam(player, true, false)
					return
				end
			end
		end

		local liveAim = character:GetAttribute("MgSlamAim")
		if typeof(liveAim) == "Vector3" then
			local flat = Vector3.new((liveAim :: Vector3).X - jeanRoot.Position.X, 0, (liveAim :: Vector3).Z - jeanRoot.Position.Z)
			if flat.Magnitude > 0.1 then
				state.throwDir = flat.Unit
			end
		end
		character:SetAttribute("MgSlamAim", nil)
		task.wait(GameConstants.MG_SLAM_THROW_DELAY)
		if slamByPlayer[player] ~= state or state.token ~= token then
			return
		end
		endSlam(player, true, true)
	end)
end

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
			inst.Rate = 0
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
			inst.Rate = 0
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
		or VfxHelper.getMarvelGirlAsset("PsionicBolt", "BoltImpactAttachment")
		or VfxHelper.getMarvelGirlAsset("PsionicBlastImpact")
	local spawned = false
	if attTemplate then
		local fx = attTemplate:Clone()
		if fx:IsA("Attachment") then
			fx.Position = Vector3.zero
			fx.Orientation = Vector3.zero
			fx.Parent = hostPart
		elseif fx:IsA("BasePart") then
			fx.Anchored = true
			fx.CanCollide = false
			fx.CanQuery = false
			fx.CFrame = hostPart.CFrame
			fx.Parent = Workspace
			host = fx
		elseif fx:IsA("Model") then
			fx:PivotTo(hostPart.CFrame)
			fx.Parent = Workspace
			host = fx
		else
			fx.Parent = hostPart
		end
		styleJeanFx(fx, nil, caster)
		VfxHelper.setParticlesEnabled(fx, true)
		VfxHelper.emitAllParticles(fx, 28)
		spawned = true
	end

	if not onBody then
		local floorTemplate = VfxHelper.getMarvelGirlAsset("TelekineticDebrisThrow", "DebrisImpactFloor")
			or VfxHelper.getMarvelGirlAsset("TelekineticDebrisThrow", "ImpactFloor")
		if floorTemplate then
			local floorPos, floorUp = debrisImpactFloorPos(pos, caster)
			local face = CFrame.lookAt(floorPos, floorPos + floorUp) * CFrame.Angles(math.rad(-90), 0, 0)
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
			VfxHelper.setParticlesEnabled(floor, true)
			VfxHelper.emitAllParticles(floor, 22)
			retireFx(floor, 1.1, GameConstants.MG_DEBRIS_CANCEL_DELETE)
			spawned = true
		end
	end

	if not spawned then
		VfxHelper.spawnMarvelGirlPsionicImpact(impactPos, 4.4, jeanAccent(caster))
	else
		VfxHelper.spawnMarvelGirlPsionicImpact(impactPos, 3.2, jeanAccent(caster))
	end
	task.delay(1.15, function()
		if host.Parent then
			VfxHelper.setParticlesEnabled(host, false)
		end
	end)
	retireFx(host, 1.15, 3.6)
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
		local root = getRoot(state.character)
		if root then
			local leftover = root:FindFirstChild("MgFaceAlign")
			if leftover then
				leftover:Destroy()
			end
		end
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
			local origin = root.Position + offset + Vector3.new(0, 8, 0)
			local hit = Workspace:Raycast(origin, Vector3.new(0, -28, 0), params)
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
			ScreenFeelHelper.pulseCharacter(victim, {
				intensity = 1.05,
				duration = 0.22,
				fovScale = 0.7,
				vignetteScale = 0.4,
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
	local now = os.clock()
	if now - state.lastThrowAt < GameConstants.MG_DEBRIS_THROW_GAP then
		return
	end
	if aimPoint then
		state.aimPoint = aimPoint
		state.character:SetAttribute("MgDebrisAim", aimPoint)
	end
	for _, rock in state.rocks do
		if rock.ready and not rock.thrown and not rock.expiring then
			state.lastThrowAt = now
			task.spawn(function()
				launchDebrisRock(player, state, rock, direction)
			end)
			return
		end
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
	if not entry or not canUse(character, entry.id, GameConstants.MG_DEBRIS_ENERGY) then
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
		local energy = character:GetAttribute(GameConstants.ENERGY_ATTRIBUTE)
		if type(energy) == "number" then
			character:SetAttribute(GameConstants.ENERGY_ATTRIBUTE, energy + GameConstants.MG_DEBRIS_ENERGY)
		end
		return
	end

	local function pickRockTemplates(pool: { Instance }, count: number): { Instance }
		local picked: { Instance } = {}
		for _ = 1, count do
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

	local count = GameConstants.MG_DEBRIS_ROCK_COUNT
	local points = findDebrisSpawnPoints(character, root, count)
	local chosen = pickRockTemplates(templates, count)
	local rocks: { DebrisRock } = {}
	for i = 1, count do
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
			table.insert(rocks, {
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
				orbitAngle = ((i - 1) / math.max(count, 1)) * math.pi * 2,
				orbitSpeed = GameConstants.MG_DEBRIS_ORBIT_SPEED,
			})
		end
	end
	if #rocks == 0 then
		local energy = character:GetAttribute(GameConstants.ENERGY_ATTRIBUTE)
		if type(energy) == "number" then
			character:SetAttribute(GameConstants.ENERGY_ATTRIBUTE, energy + GameConstants.MG_DEBRIS_ENERGY)
		end
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
-- Public API
----------------------------------------------------------------
function MarvelGirlService.cancelAll(player: Player)
	HexFlightService.endFlight(player, false)
	stopBarrier(player, false)
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
		faceTokenByCharacter[char] = (faceTokenByCharacter[char] or 0) + 1
		local root = getRoot(char)
		if root then
			for _, name in { "MgFaceAlign", "MgFaceAtt", "TKCasterFaceAlign", "TKCasterFaceAttachment" } do
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
		char:SetAttribute("MgSlamAim", nil)
		char:SetAttribute("MgDebrisAim", nil)
	end
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

	-- While in astral, H/V returns; C hold pain / B outburst
	if astralByPlayer[player] then
		local direction = if typeof(payload.direction) == "Vector3" then payload.direction else nil
		local aimPoint = if typeof(payload.aimPoint) == "Vector3" then payload.aimPoint else nil
		local target = if typeof(payload.target) == "Instance" and payload.target:IsA("Model") then payload.target else nil
		local lockOn = payload.softLock == true
		if payload.action == "H" or payload.action == "V" then
			endAstral(player, true)
		elseif payload.action == "Q_down" or payload.action == "Q" then
			startBarrier(player)
		elseif payload.action == "Q_up" then
			stopBarrier(player, true)
		elseif payload.action == "C_up" then
			stopTelepathicPain(player, false)
		elseif payload.action == "C_down" then
			startTelepathicPain(player, target, direction, aimPoint, lockOn)
		elseif payload.action == "C" then
			if painByPlayer[player] then
				stopTelepathicPain(player, false)
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
	if barrierByPlayer[player] or character:GetAttribute(GameConstants.MG_BARRIER_ATTRIBUTE) == true then
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

	if action == "Q_down" then
		startBarrier(player)
	elseif action == "Q_up" then
		stopBarrier(player, true)
	elseif action == "Q" then
		startBarrier(player)
	elseif action == "E" then
		castPsionicBolt(player, direction, aimPoint)
	elseif action == "E_aim" or action == "Q_aim" then
		if AbilityCooldownHelper.isActive(character, "psionic_bolt") and aimPoint then
			character:SetAttribute("MgBoltAim", aimPoint)
		end
	elseif action == "T" then
		castPsychicPull(player, target, direction, aimPoint, lockOn)
	elseif action == "R_down" then
		startJeanTelekinesis(player, target, aimPoint, hitPart, lockOn)
	elseif action == "R_up" then
		releaseJeanTelekinesis(player, true)
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
		throwJeanTelekinesis(player, target, direction, aimPoint)
	elseif action == "R" then
		-- HUD tap: start hold if idle
		if not TelekinesisService.isActive(player) then
			startJeanTelekinesis(player, target, aimPoint, hitPart, lockOn)
		end
	elseif action == "F" then
		HexFlightService.toggleFlight(player)
	elseif action == "X" then
		castTelekineticSlam(player, target, direction, aimPoint, lockOn)
	elseif action == "X_aim" or action == "T_aim" then
		if AbilityCooldownHelper.isActive(character, "telekinetic_slam") and aimPoint then
			character:SetAttribute("MgSlamAim", aimPoint)
		end
	elseif action == "Z_down" or action == "X_down" then
		castTelekineticDebris(player, aimPoint)
	elseif action == "Z_up" or action == "X_up" then
		releaseDebrisHold(player)
	elseif action == "Z_throw" or action == "X_throw" then
		throwNextDebris(player, direction, aimPoint)
	elseif action == "Z" then
		-- Legacy tap: start hold if idle
		if not debrisByPlayer[player] then
			castTelekineticDebris(player, aimPoint)
		end
	elseif action == "Z_aim" then
		if AbilityCooldownHelper.isActive(character, "telekinetic_debris") and aimPoint then
			character:SetAttribute("MgDebrisAim", aimPoint)
			local st = debrisByPlayer[player]
			if st then
				st.aimPoint = aimPoint
			end
		end
	elseif action == "H" or action == "V" then
		startAstral(player)
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
	elseif action == "J" then
		playJeanHairToggle(player, character)
	end
end

function MarvelGirlService.update(dt: number)
	local dtClamped = math.clamp(dt, 0.001, 0.1)

	for _, state in slamByPlayer do
		if state.character.Parent then
			applySlamCasterLock(state.character)
		end
	end

	for player in painByPlayer do
		updateTelepathicPain(player, dtClamped)
	end

	-- Astral flight (HexFlight feel) + energy drain; skip while returning
	local velLerpMove = 1 - (1 - GameConstants.FLIGHT_VEL_LERP_MOVE) ^ (dtClamped * 60)
	local velLerpDecay = 1 - (1 - GameConstants.FLIGHT_VEL_LERP_DECAY) ^ (dtClamped * 60)
	for player, state in astralByPlayer do
		if not state.astral.Parent or not state.body.Parent then
			endAstral(player, true, true)
			continue
		end
		if state.returning then
			forceAstralNoclip(state.astral)
			continue
		end
		local energy = state.body:GetAttribute(GameConstants.ENERGY_ATTRIBUTE)
		if type(energy) ~= "number" or energy <= 0 then
			endAstral(player, true)
			continue
		end
		local drain = GameConstants.MG_ASTRAL_ENERGY_PER_SEC * dtClamped
		if not CharacterService.spendEnergy(state.body, math.min(drain, energy)) then
			endAstral(player, true)
			continue
		end
		if os.clock() - state.startedAt >= GameConstants.MG_ASTRAL_DURATION then
			endAstral(player, true)
			continue
		end

		forceAstralNoclip(state.astral)

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
		if painByPlayer[player] then
			speed *= GameConstants.MG_PAIN_ASTRAL_SPEED_MULT
		end
		local moveMag = state.moveDir.Magnitude
		local direction = if moveMag > 0.01 then state.moveDir.Unit else normalizeDir(state.lookDir)
		local targetVel = if moveMag > 0.01 then direction * speed else Vector3.zero
		local lerpAlpha = if moveMag > 0.01 then velLerpMove else velLerpDecay
		state.currentVel = state.currentVel:Lerp(targetVel, lerpAlpha)

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
			local rotAlpha = 1 - (1 - GameConstants.FLIGHT_ROTATION_LERP) ^ (dtClamped * 60)
			state.mover.alignOrientation.CFrame = state.mover.alignOrientation.CFrame:Lerp(targetCf, rotAlpha)
		end

		state.astral:SetAttribute(GameConstants.FLIGHT_ALPHA_ATTRIBUTE, math.clamp(alphaSpeed, 0, 1))
		state.astral:SetAttribute(GameConstants.FLIGHT_BANK_ATTRIBUTE, bank)
		state.astral:SetAttribute(GameConstants.FLIGHT_SIDE_ATTRIBUTE, sideLean)
	end

	-- Mind link energy / duration
	for player, state in mindLinkByPlayer do
		if not state.character.Parent or player.Character ~= state.character then
			endMindLink(player, true, true)
			continue
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
		if HexFlightService.isFlying(player) then
			for _, rock in state.rocks do
				if not rock.thrown and not rock.expiring and rock.part.Parent then
					beginDebrisExpire(player, state, rock)
				end
			end
			continue
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
		if not CharacterService.spendEnergy(state.character, GameConstants.MG_BARRIER_ENERGY_PER_SEC * dtClamped) then
			stopBarrier(player, true)
		end
	end

	for _, player in Players:GetPlayers() do
		updateJeanRestraint(player, dtClamped)
	end
end

local function isPhoenixJean(character: Model): boolean
	return character:GetAttribute(GameConstants.HERO_ATTRIBUTE) == "jean_grey"
		and character:GetAttribute(GameConstants.LOOK_MODE_ATTRIBUTE) == "phoenix"
end

local function clearPhoenixDown(player: Player)
	if phoenixDownByPlayer[player] then
		phoenixDownByPlayer[player] = nil
		unblockPhoenixAutoRespawn()
	end
	local character = player.Character
	if character and character.Parent then
		character:SetAttribute(GameConstants.MG_PHOENIX_REVIVE_AVAILABLE_ATTRIBUTE, nil)
	end
end

function MarvelGirlService.tryPhoenixDown(player: Player, character: Model): boolean
	if not isPhoenixJean(character) then
		return false
	end
	if not phoenixDownByPlayer[player] then
		blockPhoenixAutoRespawn()
	end
	phoenixDownByPlayer[player] = { character = character }
	character:SetAttribute(GameConstants.MG_PHOENIX_REVIVE_AVAILABLE_ATTRIBUTE, true)
	local hum = character:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.BreakJointsOnDeath = false
	end
	return true
end

function MarvelGirlService.tryPhoenixRevive(player: Player): boolean
	local state = phoenixDownByPlayer[player]
	if not state or state.reviving then
		return false
	end
	local character = state.character
	if character ~= player.Character or not character.Parent then
		clearPhoenixDown(player)
		return false
	end
	if character:GetAttribute(GameConstants.MG_PHOENIX_REVIVE_AVAILABLE_ATTRIBUTE) ~= true then
		return false
	end

	state.reviving = true
	local hum = CombatHelper.getHumanoid(character)
	local root = getRoot(character)
	if not hum or not root then
		state.reviving = false
		return false
	end

	RagdollService.clear(character)
	hum.PlatformStand = false
	pcall(function()
		hum:ChangeState(Enum.HumanoidStateType.Physics)
	end)
	hum.WalkSpeed = 0
	hum.JumpPower = 0
	hum:Move(Vector3.zero, false)
	hum.Health = math.max(hum.Health, 1)

	local att = Instance.new("Attachment")
	att.Name = "MgPhoenixFloatAtt"
	att.Parent = root
	local align = Instance.new("AlignPosition")
	align.Name = "MgPhoenixFloat"
	align.Mode = Enum.PositionAlignmentMode.OneAttachment
	align.Attachment0 = att
	align.ApplyAtCenterOfMass = true
	align.RigidityEnabled = false
	align.Responsiveness = 6
	align.MaxForce = 1e6
	align.MaxVelocity = 14
	align.Parent = root

	local startPos = root.Position
	local floatTarget = startPos + Vector3.new(0, GameConstants.MG_PHOENIX_REVIVE_FLOAT, 0)
	align.Position = floatTarget

	local animTrack = playJeanAnim(character, GameConstants.MG_PHOENIX_REVIVE_ANIM, false)
	local animLen = if animTrack and animTrack.Length > 0.05 then animTrack.Length / math.max(animTrack.Speed, 0.01) else 2.4

	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < animLen do
			if not character.Parent or not root.Parent then
				break
			end
			local a = math.clamp((os.clock() - t0) / animLen, 0, 1)
			local ease = a * a * (3 - 2 * a)
			align.Position = startPos:Lerp(floatTarget, ease)
			task.wait()
		end

		if align.Parent then
			align:Destroy()
		end
		if att.Parent then
			att:Destroy()
		end
		if animTrack then
			animTrack:Stop(0.15)
			animTrack:Destroy()
		end

		if not character.Parent or not hum.Parent then
			clearPhoenixDown(player)
			return
		end

		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero

		local targetHp = hum.MaxHealth * GameConstants.MG_PHOENIX_REVIVE_HP_RATIO
		hum.Health = 0
		local hpT0 = os.clock()
		while os.clock() - hpT0 < GameConstants.MG_PHOENIX_REVIVE_HP_TIME do
			if not hum.Parent then
				break
			end
			local u = math.clamp((os.clock() - hpT0) / GameConstants.MG_PHOENIX_REVIVE_HP_TIME, 0, 1)
			hum.Health = targetHp * u
			task.wait()
		end
		if hum.Parent then
			hum.Health = targetHp
			hum.WalkSpeed = GameConstants.DEFAULT_WALK_SPEED
			hum.JumpPower = 50
			pcall(function()
				hum.JumpHeight = 7.2
				hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
			end)
		end

		clearPhoenixDown(player)
		Remotes.getEvent("PhoenixRevive"):FireClient(player, true)
	end)

	return true
end

function MarvelGirlService.init()
	ensureAstralCollisionGroup()
	HexFlightService.registerHeroFx("jean_grey", {
		begin = beginPowerFx,
		finish = endPowerFx,
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

	Remotes.getEvent("UseAbility").OnServerEvent:Connect(function(player: Player, payload: any)
		MarvelGirlService.handleAction(player, payload)
	end)

	Remotes.getEvent("PhoenixRevive").OnServerEvent:Connect(function(player: Player)
		MarvelGirlService.tryPhoenixRevive(player)
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
	Remotes.getEvent("FlightInput").OnServerEvent:Connect(function(player: Player, payload: any)
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
		end)
		player.CharacterAdded:Connect(function(character)
			local humanoid = character:WaitForChild("Humanoid", 5)
			if humanoid and humanoid:IsA("Humanoid") then
				humanoid.Died:Connect(function()
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
	end)
end

return MarvelGirlService
