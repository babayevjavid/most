--!strict
--[[
	Iceman (Bobby Drake) — Chill / Freeze pressure hero.
	Q Ice Shards — one shard, stacks Chill
	E Ice Wall — anchored wall wherever you aim, ground or mid-air
	F Ice Slide — camera-aimed skate (not flight); ice path is visual only
	T Cryo Stream — hold frontal chill cone (hands particle FX)
	C Ice Form — toggle, double health, ice material + blue body
	X Absolute Zero — expanding ice circle from caster
	V Flash Freeze — freeze one target solid
	G Shatter — spend Chill on nearby foes for burst damage
	Passive Sub-Zero Body — immune to Chill

	All visuals here are PARTICLE_PLACEHOLDER parts until Assets.IceMan is filled in.
]]

local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local AbilityCooldownHelper = require(ReplicatedStorage.Shared.AbilityCooldownHelper)
local CharacterRegistry = require(ReplicatedStorage.Shared.CharacterRegistry)
local CombatHelper = require(ReplicatedStorage.Shared.CombatHelper)
local FrostStatus = require(ReplicatedStorage.Shared.FrostStatus)
local GameConstants = require(ReplicatedStorage.Shared.GameConstants)
local ProjectileHelper = require(ReplicatedStorage.Shared.ProjectileHelper)
local PushHelper = require(ReplicatedStorage.Shared.PushHelper)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local VfxHelper = require(ReplicatedStorage.Shared.VfxHelper)
local CharacterService = require(script.Parent.CharacterService)

local IcemanService = {}

type StreamState = {
	character: Model,
	handFx: { Instance },
	aimPoint: Vector3,
	lastTick: number,
	baseAutoRotate: boolean?,
	faceAtt: Attachment?,
	faceAlign: AlignOrientation?,
	animTrack: AnimationTrack?,
}

type SlideBeamFx = {
	leftStart: Attachment,
	rightStart: Attachment,
	backHost: BasePart,
	frontHost: BasePart,
	backEnd: Attachment,
	frontEnd: Attachment,
	backBeam: Beam,
	frontBeam: Beam,
}

type SlideState = {
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	baseWalk: number,
	baseAutoRotate: boolean,
	moveDir: Vector3,
	lookDir: Vector3,
	lastSlabAt: number,
	faceAtt: Attachment,
	faceAlign: AlignOrientation,
	animTrack: AnimationTrack?,
	beamFx: SlideBeamFx?,
}

type FormPartLook = {
	material: Enum.Material,
	color: Color3,
}

type FormState = {
	character: Model,
	baseMaxHealth: number,
	endsAt: number,
	lastAuraAt: number,
	parts: { [BasePart]: FormPartLook },
}

type BlizzardState = {
	character: Model,
	center: Vector3,
	part: BasePart,
	startedAt: number,
	endsAt: number,
	lastTick: number,
}

local streamByPlayer: { [Player]: StreamState } = {}
local slideByPlayer: { [Player]: SlideState } = {}
local formByPlayer: { [Player]: FormState } = {}
local blizzardByPlayer: { [Player]: BlizzardState } = {}
local wallsByPlayer: { [Player]: { BasePart } } = {}

-- Toggles / stances that should not block (or be blocked by) other casts
local NON_BLOCKING: { [string]: boolean } = {
	ice_slide = true,
	ice_form = true,
}

----------------------------------------------------------------
-- Helpers
----------------------------------------------------------------
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

local function getFootPosition(character: Model): Vector3
	local root = getRoot(character)
	if not root then
		return character:GetPivot().Position
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local cast = Workspace:Raycast(root.Position + Vector3.new(0, 1, 0), Vector3.new(0, -14, 0), params)
	if cast then
		return cast.Position + Vector3.new(0, 0.05, 0)
	end
	local hum = CombatHelper.getHumanoid(character)
	local drop = if hum then (hum.HipHeight + root.Size.Y * 0.5) else 3
	return root.Position - Vector3.new(0, drop, 0)
end

local function isRealTarget(victim: Model, caster: Model): boolean
	if victim == caster then
		return false
	end
	if victim:GetAttribute("LokiUltClone") == true or victim:GetAttribute("LokiDecoy") == true then
		return false
	end
	if victim:GetAttribute("FearVisual") == true or victim.Name == "FearClone" then
		return false
	end
	if victim:GetAttribute(GameConstants.MG_ASTRAL_ATTRIBUTE) == true then
		return false
	end
	return true
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

local function getIceManAsset(assetName: string): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("IceMan")
	return if folder then folder:FindFirstChild(assetName) else nil
end

local function getIceManAttachment(assetName: string): Attachment?
	local inst = getIceManAsset(assetName)
	if inst and inst:IsA("Attachment") then
		return inst
	end
	if inst then
		local nested = inst:FindFirstChildWhichIsA("Attachment", true)
		if nested then
			return nested
		end
	end
	return nil
end

local function cloneIceManAttachment(assetName: string): Attachment?
	local template = getIceManAttachment(assetName)
	if not template then
		return nil
	end
	return template:Clone()
end

local function getIceManPart(assetName: string): BasePart?
	local ice = getIceManAsset(assetName)
	if ice and ice:IsA("BasePart") then
		return ice
	end
	return nil
end

local function refundEnergy(character: Model, amount: number)
	if amount <= 0 then
		return
	end
	local energy = character:GetAttribute(GameConstants.ENERGY_ATTRIBUTE)
	local maxEnergy = character:GetAttribute(GameConstants.MAX_ENERGY_ATTRIBUTE)
	if type(energy) ~= "number" then
		return
	end
	local cap = if type(maxEnergy) == "number" then maxEnergy else 100
	character:SetAttribute(GameConstants.ENERGY_ATTRIBUTE, math.min(cap, energy + amount))
end

local function playAbilityAnim(humanoid: Humanoid, animId: string, looped: boolean): AnimationTrack?
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
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = looped
	track:Play(0.15, 1, 1)
	return track
end

local function makeTipHost(name: string): (BasePart, Attachment)
	local host = Instance.new("Part")
	host.Name = name
	host.Size = Vector3.new(0.2, 0.2, 0.2)
	host.Transparency = 1
	host.Anchored = true
	host.CanCollide = false
	host.CanQuery = false
	host.CanTouch = false
	host.CastShadow = false
	host.Parent = Workspace
	local att = Instance.new("Attachment")
	att.Name = name .. "Att"
	att.Parent = host
	return host, att
end

local function makeIceSlideBeam(startParent: BasePart, endAtt: Attachment, name: string): (Attachment, Beam)
	local startAtt = Instance.new("Attachment")
	startAtt.Name = name .. "Start"
	startAtt.Parent = startParent
	local beam = Instance.new("Beam")
	beam.Name = name
	beam.Attachment0 = startAtt
	beam.Attachment1 = endAtt
	beam.Width0 = 0.35
	beam.Width1 = 0.85
	beam.FaceCamera = true
	beam.LightEmission = 0.55
	beam.LightInfluence = 0
	beam.Color = ColorSequence.new(GameConstants.ICE_COLOR)
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 0.65),
	})
	beam.Enabled = true
	beam.Parent = startAtt
	return startAtt, beam
end

local function getSlidePathPoint(character: Model, cameraLook: Vector3, lead: number): Vector3
	local root = getRoot(character)
	if not root then
		return character:GetPivot().Position
	end
	local hum = CombatHelper.getHumanoid(character)
	local drop = if hum then (hum.HipHeight + root.Size.Y * 0.5) else 3
	local flat = Vector3.new(cameraLook.X, 0, cameraLook.Z)
	if flat.Magnitude < 0.05 then
		local look = root.CFrame.LookVector
		flat = Vector3.new(look.X, 0, look.Z)
	end
	if flat.Magnitude < 0.05 then
		flat = Vector3.new(0, 0, -1)
	else
		flat = flat.Unit
	end
	return root.Position - Vector3.new(0, drop, 0) + flat * lead
end

local function clearSlideBeamFx(fx: SlideBeamFx?)
	if not fx then
		return
	end
	if fx.leftStart.Parent then
		fx.leftStart:Destroy()
	end
	if fx.rightStart.Parent then
		fx.rightStart:Destroy()
	end
	if fx.backHost.Parent then
		fx.backHost:Destroy()
	end
	if fx.frontHost.Parent then
		fx.frontHost:Destroy()
	end
end

local function attachCryoStreamParticle(hand: BasePart): Instance?
	local template = getIceManAsset("CryoStreamParticle")
	if not template then
		warn("[IcemanService] Missing ReplicatedStorage.Assets.IceMan.CryoStreamParticle")
		return nil
	end
	local clone = template:Clone()
	clone.Name = "CryoStreamParticle"
	if clone:IsA("Attachment") then
		clone.Position = Vector3.zero
		clone.Orientation = Vector3.zero
		clone.Parent = hand
	elseif clone:IsA("ParticleEmitter") then
		clone.Parent = hand
	else
		clone.Parent = hand
		local nested = clone:FindFirstChildWhichIsA("Attachment", true)
		if nested then
			nested.Position = Vector3.zero
			nested.Orientation = Vector3.zero
		end
	end
	VfxHelper.setParticlesEnabled(clone, true)
	VfxHelper.emitAllParticles(clone, 10)
	return clone
end

--[[ PARTICLE_PLACEHOLDER: expanding ice orb, stands in for Assets.IceMan impact FX. ]]
local function iceBurst(pos: Vector3, radius: number)
	local r = math.clamp(radius, 1, 30)
	local orb = Instance.new("Part")
	orb.Name = "IcePlaceholderBurst"
	orb.Shape = Enum.PartType.Ball
	orb.Size = Vector3.new(r * 0.5, r * 0.5, r * 0.5)
	orb.CFrame = CFrame.new(pos)
	orb.Anchored = true
	orb.CanCollide = false
	orb.CanQuery = false
	orb.CanTouch = false
	orb.CastShadow = false
	orb.Material = Enum.Material.Ice
	orb.Color = GameConstants.ICE_COLOR
	orb.Transparency = 0.35
	orb.Parent = Workspace
	TweenService:Create(orb, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(r * 2, r * 2, r * 2),
		Transparency = 1,
	}):Play()
	Debris:AddItem(orb, 0.5)
end

local function fireCameraShake(player: Player, intensity: number?, duration: number?)
	Remotes.getEvent("CameraShake"):FireClient(player, {
		intensity = intensity or 0.45,
		duration = duration or 0.3,
	})
end

local function canUse(character: Model, abilityId: string, energy: number): boolean
	if character:GetAttribute(GameConstants.HERO_ATTRIBUTE) ~= "iceman" then
		return false
	end
	if CombatHelper.arePowersDisabled(character) then
		return false
	end
	if character:GetAttribute(GameConstants.BUSY_ATTRIBUTE) == true then
		return false
	end
	if AbilityCooldownHelper.isOnCooldown(character, abilityId) then
		return false
	end
	if AbilityCooldownHelper.isActive(character, abilityId) then
		return false
	end
	-- One cast at a time; stances (slide / form) are exempt both ways
	for _, ab in CharacterRegistry.getAbilities("iceman") do
		if ab.passive or ab.id == abilityId or NON_BLOCKING[ab.id] then
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

local function finishAbility(character: Model, abilityId: string, cooldown: number)
	AbilityCooldownHelper.setActive(character, abilityId, false)
	AbilityCooldownHelper.applyAfterUse(character, abilityId, cooldown)
	CharacterService.markAbilityUse(character)
end

----------------------------------------------------------------
-- Q Ice Shards
----------------------------------------------------------------
local function castIceShards(player: Player, direction: Vector3?, aimPoint: Vector3?)
	local character = player.Character
	if not character then
		return
	end
	local entry = CharacterRegistry.getAbilityById("iceman", "ice_shards")
	if not entry or not canUse(character, entry.id, GameConstants.ICE_SHARD_ENERGY) then
		return
	end

	AbilityCooldownHelper.setActive(character, entry.id, true)

	local hand = getHand(character, true)
	local origin = if hand then hand.Position else character:GetPivot().Position
	local dir = resolveAimDir(character, direction, aimPoint)
	if aimPoint then
		local toAim = aimPoint - origin
		if toAim.Magnitude > 0.05 then
			dir = toAim.Unit
		end
	end

	ProjectileHelper.spawn(origin, dir, {
		speed = GameConstants.ICE_SHARD_SPEED,
		damage = GameConstants.ICE_SHARD_DAMAGE,
		radius = GameConstants.ICE_SHARD_HIT_RADIUS,
		maxDistance = GameConstants.ICE_SHARD_RANGE,
		owner = character,
		color = GameConstants.ICE_COLOR,
		homeDir = dir,
		homePoint = aimPoint or (origin + dir * 60),
		homeAfter = 0,
		boltFolder = "IceMan",
		boltAsset = "IceShard",
		impactFx = "none",
		deleteAfterFx = GameConstants.ICE_SHARD_DELETE_AFTER_FX,
		onHit = function(victim: Model, hitPos: Vector3)
			FrostStatus.addChill(victim, GameConstants.ICE_SHARD_CHILL)
			iceBurst(hitPos, 2.5)
		end,
	})

	finishAbility(character, entry.id, GameConstants.ICE_SHARD_COOLDOWN)
end

----------------------------------------------------------------
-- E Ice Wall
----------------------------------------------------------------
local function retireWall(wall: BasePart)
	if not wall.Parent then
		return
	end
	wall.CanCollide = false
	TweenService:Create(wall, TweenInfo.new(GameConstants.ICE_WALL_FADE), { Transparency = 1 }):Play()
	Debris:AddItem(wall, GameConstants.ICE_WALL_FADE + 0.2)
end

local function trackWall(player: Player, wall: BasePart)
	local list = wallsByPlayer[player]
	if not list then
		list = {}
		wallsByPlayer[player] = list
	end
	for i = #list, 1, -1 do
		if not list[i].Parent then
			table.remove(list, i)
		end
	end
	table.insert(list, wall)
end

local function castIceWall(player: Player, direction: Vector3?, aimPoint: Vector3?)
	local character = player.Character
	if not character then
		return
	end
	local entry = CharacterRegistry.getAbilityById("iceman", "ice_wall")
	if not entry or not canUse(character, entry.id, GameConstants.ICE_WALL_ENERGY) then
		return
	end

	AbilityCooldownHelper.setActive(character, entry.id, true)

	local root = getRoot(character)
	local origin = if root then root.Position else character:GetPivot().Position
	-- Always rise square in front of the body (character facing), not under the camera
	local look = if root then root.CFrame.LookVector else character:GetPivot().LookVector
	local facing = Vector3.new(look.X, 0, look.Z)
	if facing.Magnitude < 0.05 then
		facing = Vector3.new(0, 0, -1)
	else
		facing = facing.Unit
	end

	local height = GameConstants.ICE_WALL_HEIGHT
	local front = GameConstants.ICE_WALL_FRONT_DISTANCE
	local spot = origin + facing * front

	-- Must plant on solid ground — no mid-air walls
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local probe = GameConstants.ICE_WALL_GROUND_PROBE
	local snap = GameConstants.ICE_WALL_GROUND_SNAP
	local ground = Workspace:Raycast(spot + Vector3.new(0, probe, 0), Vector3.new(0, -(snap + probe), 0), params)
	if not ground then
		AbilityCooldownHelper.setActive(character, entry.id, false)
		refundEnergy(character, GameConstants.ICE_WALL_ENERGY)
		return
	end
	local basePos = ground.Position

	local center = basePos + Vector3.new(0, height * 0.5, 0)
	local finalCf = CFrame.lookAt(center, center + facing)

	local width = GameConstants.ICE_WALL_WIDTH
	local thickness = GameConstants.ICE_WALL_THICKNESS

	local template = getIceManPart("Ice")
	local wall: BasePart
	if template then
		wall = template:Clone()
	else
		wall = Instance.new("Part")
		wall.Material = Enum.Material.Ice
		wall.Color = GameConstants.ICE_COLOR
		wall.Transparency = 0.25
	end
	wall.Name = "IceWall"
	wall.Size = Vector3.new(width, 0.5, thickness)
	wall.CFrame = CFrame.lookAt(basePos + Vector3.new(0, 0.25, 0), basePos + Vector3.new(0, 0.25, 0) + facing)
	wall.Anchored = true
	wall.CanCollide = true
	wall.CanQuery = true
	wall.CanTouch = false
	wall.CastShadow = false
	wall.Color = GameConstants.ICE_COLOR
	wall:SetAttribute("OwnerUserId", player.UserId)
	wall.Parent = Workspace

	-- Grow up out of the ground
	TweenService:Create(
		wall,
		TweenInfo.new(GameConstants.ICE_WALL_RISE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = finalCf, Size = Vector3.new(width, height, thickness) }
	):Play()
	iceBurst(basePos, 5)
	trackWall(player, wall)

	task.delay(GameConstants.ICE_WALL_DURATION, function()
		retireWall(wall)
	end)

	finishAbility(character, entry.id, GameConstants.ICE_WALL_COOLDOWN)
end

----------------------------------------------------------------
-- F Ice Slide (camera-aimed skate — humanoid stays free; slabs are visual)
----------------------------------------------------------------
local function createYawAlign(root: BasePart, namePrefix: string): (Attachment, AlignOrientation)
	local att = Instance.new("Attachment")
	att.Name = namePrefix .. "Att"
	att.Parent = root

	local align = Instance.new("AlignOrientation")
	align.Name = namePrefix .. "Align"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = att
	align.RigidityEnabled = false
	align.MaxTorque = 200000
	align.Responsiveness = 18
	align.CFrame = CFrame.new(root.Position) * (root.CFrame - root.Position)
	align.Parent = root
	return att, align
end

local function setYawAlign(align: AlignOrientation, root: BasePart, lookFlat: Vector3)
	local face = Vector3.new(lookFlat.X, 0, lookFlat.Z)
	if face.Magnitude < 0.05 then
		return
	end
	face = face.Unit
	local lookCf = CFrame.lookAt(root.Position, root.Position + face)
	local _p, yaw, _r = lookCf:ToOrientation()
	-- Pitch locked to 0 — upright skate
	align.CFrame = CFrame.new(root.Position) * CFrame.fromOrientation(0, yaw, 0)
end

local function playSlideAnim(humanoid: Humanoid): AnimationTrack?
	return playAbilityAnim(humanoid, GameConstants.ICE_SLIDE_ANIM, true)
end

local function stopIceSlide(player: Player, applyCooldown: boolean?)
	local state = slideByPlayer[player]
	slideByPlayer[player] = nil

	local function clearAttrs(char: Model?)
		if char and char.Parent then
			char:SetAttribute(GameConstants.ICE_SLIDE_ATTRIBUTE, nil)
			AbilityCooldownHelper.setActive(char, "ice_slide", false)
		end
	end

	if not state then
		clearAttrs(player.Character)
		return
	end

	local character = state.character
	clearAttrs(character)
	clearSlideBeamFx(state.beamFx)

	if state.animTrack then
		state.animTrack:Stop(0.15)
		state.animTrack:Destroy()
	end
	if state.faceAlign.Parent then
		state.faceAlign:Destroy()
	end
	if state.faceAtt.Parent then
		state.faceAtt:Destroy()
	end

	local hum = state.humanoid
	if hum.Parent then
		hum.WalkSpeed = state.baseWalk
		hum.AutoRotate = state.baseAutoRotate
	end

	if applyCooldown and character.Parent then
		AbilityCooldownHelper.applyAfterUse(character, "ice_slide", GameConstants.ICE_SLIDE_COOLDOWN)
		CharacterService.markAbilityUse(character)
	end
end

local function startIceSlide(player: Player)
	local character = player.Character
	if not character then
		return
	end
	if slideByPlayer[player] then
		stopIceSlide(player, true)
		return
	end
	local entry = CharacterRegistry.getAbilityById("iceman", "ice_slide")
	if not entry or not canUse(character, entry.id, 0) then
		return
	end
	local root = getRoot(character)
	local hum = CombatHelper.getHumanoid(character)
	if not root or not hum or hum.Health <= 0 then
		return
	end

	AbilityCooldownHelper.setActive(character, entry.id, true)
	character:SetAttribute(GameConstants.ICE_SLIDE_ATTRIBUTE, true)

	local faceAtt, faceAlign = createYawAlign(root, "IceSlide")
	local baseAutoRotate = hum.AutoRotate
	local baseWalk = hum.WalkSpeed
	hum.AutoRotate = false
	hum.WalkSpeed = GameConstants.ICE_SLIDE_SPEED

	local beamFx: SlideBeamFx? = nil
	local leftHand = getHand(character, false)
	local rightHand = getHand(character, true)
	if leftHand and rightHand then
		local backHost, backEnd = makeTipHost("IceSlideBackTip")
		local frontHost, frontEnd = makeTipHost("IceSlideFrontTip")
		local leftStart, backBeam = makeIceSlideBeam(leftHand, backEnd, "IceSlideBackBeam")
		local rightStart, frontBeam = makeIceSlideBeam(rightHand, frontEnd, "IceSlideFrontBeam")
		local look = root.CFrame.LookVector
		backHost.CFrame = CFrame.new(getSlidePathPoint(character, look, -GameConstants.ICE_SLIDE_SLAB_LEAD))
		frontHost.CFrame = CFrame.new(getSlidePathPoint(character, look, GameConstants.ICE_SLIDE_SLAB_LEAD))
		beamFx = {
			leftStart = leftStart,
			rightStart = rightStart,
			backHost = backHost,
			frontHost = frontHost,
			backEnd = backEnd,
			frontEnd = frontEnd,
			backBeam = backBeam,
			frontBeam = frontBeam,
		}
	end

	slideByPlayer[player] = {
		character = character,
		humanoid = hum,
		root = root,
		baseWalk = baseWalk,
		baseAutoRotate = baseAutoRotate,
		moveDir = Vector3.zero,
		lookDir = root.CFrame.LookVector,
		lastSlabAt = 0,
		faceAtt = faceAtt,
		faceAlign = faceAlign,
		animTrack = playSlideAnim(hum),
		beamFx = beamFx,
	}
end

function IcemanService.setSlideInput(player: Player, moveDir: Vector3, lookDir: Vector3)
	local state = slideByPlayer[player]
	if not state then
		return
	end
	state.moveDir = moveDir
	state.lookDir = lookDir
end

--[[ Visual ice path under / ahead of the skater — facing follows camera look. ]]
local function spawnSlideSlab(character: Model, cameraLook: Vector3)
	local root = getRoot(character)
	if not root then
		return
	end
	local flat = Vector3.new(cameraLook.X, 0, cameraLook.Z)
	if flat.Magnitude < 0.05 then
		local look = root.CFrame.LookVector
		flat = Vector3.new(look.X, 0, look.Z)
	end
	if flat.Magnitude < 0.05 then
		flat = Vector3.new(0, 0, -1)
	else
		flat = flat.Unit
	end

	local pos = getSlidePathPoint(character, cameraLook, GameConstants.ICE_SLIDE_SLAB_LEAD)
	local size = GameConstants.ICE_SLIDE_SLAB_SIZE
	local slab = Instance.new("Part")
	slab.Name = "IceSlideSlab"
	slab.Size = size
	-- Yaw from camera; slight pitch so looking up/down tips the visual path
	local pitch = math.clamp(math.asin(math.clamp(cameraLook.Y, -0.95, 0.95)), math.rad(-35), math.rad(35))
	local lookCf = CFrame.lookAt(Vector3.zero, flat)
	local _p, yaw, _r = lookCf:ToOrientation()
	slab.CFrame = CFrame.new(pos - Vector3.new(0, size.Y * 0.5, 0)) * CFrame.fromOrientation(pitch, yaw, 0)
	slab.Anchored = true
	slab.CanCollide = false
	slab.CanQuery = false
	slab.CanTouch = false
	slab.CastShadow = false
	slab.Material = Enum.Material.Ice
	slab.Color = GameConstants.ICE_COLOR_SOFT
	slab.Transparency = 0.35
	slab.Parent = Workspace

	TweenService:Create(slab, TweenInfo.new(GameConstants.ICE_SLIDE_SLAB_LIFE), { Transparency = 1 }):Play()
	Debris:AddItem(slab, GameConstants.ICE_SLIDE_SLAB_LIFE + 0.2)
end

----------------------------------------------------------------
-- T Cryo Stream (frontal chill cone + hand particles)
----------------------------------------------------------------
local CRYO_FX_FADE = 0.35

local function fadeOutCryoStreamFx(state: StreamState)
	for _, fx in state.handFx do
		VfxHelper.setParticlesEnabled(fx, false)
		VfxHelper.smoothDisableParticles(fx, CRYO_FX_FADE)
	end
	task.delay(CRYO_FX_FADE, function()
		for _, fx in state.handFx do
			if fx.Parent then
				fx:Destroy()
			end
		end
	end)
end

local function stopCryoStream(player: Player, applyCooldown: boolean?)
	local state = streamByPlayer[player]
	if not state then
		return
	end
	streamByPlayer[player] = nil

	local character = state.character
	local hum = CombatHelper.getHumanoid(character)
	if hum and hum.Parent and state.baseAutoRotate ~= nil then
		hum.AutoRotate = state.baseAutoRotate
	end
	if state.animTrack then
		state.animTrack:Stop(0.15)
		state.animTrack:Destroy()
	end
	if state.faceAlign and state.faceAlign.Parent then
		state.faceAlign:Destroy()
	end
	if state.faceAtt and state.faceAtt.Parent then
		state.faceAtt:Destroy()
	end

	fadeOutCryoStreamFx(state)

	if character.Parent then
		AbilityCooldownHelper.setActive(character, "cryo_stream", false)
		if applyCooldown then
			AbilityCooldownHelper.applyAfterUse(character, "cryo_stream", GameConstants.ICE_STREAM_COOLDOWN)
			CharacterService.markAbilityUse(character)
		end
	end
end

local function startCryoStream(player: Player, aimPoint: Vector3)
	local character = player.Character
	if not character or streamByPlayer[player] then
		return
	end
	local entry = CharacterRegistry.getAbilityById("iceman", "cryo_stream")
	if not entry or not canUse(character, entry.id, entry.energyCost) then
		return
	end

	local rightHand = getHand(character, true)
	local leftHand = getHand(character, false)
	if not rightHand and not leftHand then
		refundEnergy(character, entry.energyCost)
		return
	end

	AbilityCooldownHelper.setActive(character, entry.id, true)

	local hum = CombatHelper.getHumanoid(character)
	local root = getRoot(character)
	local baseAutoRotate: boolean? = nil
	local faceAtt: Attachment? = nil
	local faceAlign: AlignOrientation? = nil
	if hum then
		baseAutoRotate = hum.AutoRotate
		hum.AutoRotate = false
	end
	if root then
		faceAtt, faceAlign = createYawAlign(root, "CryoStream")
	end

	local handFx: { Instance } = {}
	if rightHand then
		local fx = attachCryoStreamParticle(rightHand)
		if fx then
			table.insert(handFx, fx)
		end
	end
	if leftHand and leftHand ~= rightHand then
		local fx = attachCryoStreamParticle(leftHand)
		if fx then
			table.insert(handFx, fx)
		end
	end
	if #handFx == 0 then
		warn("[IcemanService] CryoStreamParticle failed to attach")
	end

	local animTrack: AnimationTrack? = nil
	if hum then
		animTrack = playAbilityAnim(hum, GameConstants.ICE_STREAM_ANIM, true)
	end

	streamByPlayer[player] = {
		character = character,
		handFx = handFx,
		aimPoint = aimPoint,
		lastTick = AbilityCooldownHelper.getNow(),
		baseAutoRotate = baseAutoRotate,
		faceAtt = faceAtt,
		faceAlign = faceAlign,
		animTrack = animTrack,
	}
end

----------------------------------------------------------------
-- C Ice Form (toggle — double health)
----------------------------------------------------------------
--[[
	Turn only body MeshParts to ice (direct children of the character).
	Accessories / Handle parts are left alone.
]]
local function applyIceLook(character: Model): { [BasePart]: FormPartLook }
	local saved: { [BasePart]: FormPartLook } = {}
	for _, part in FrostStatus.getBodyParts(character) do
		saved[part] = {
			material = part.Material,
			color = part.Color,
		}
		part.Material = Enum.Material.Ice
		part.Color = GameConstants.ICE_COLOR
	end
	return saved
end

local function stopIceForm(player: Player, applyCooldown: boolean?)
	local state = formByPlayer[player]
	if not state then
		return
	end
	formByPlayer[player] = nil

	local character = state.character
	local hum = CombatHelper.getHumanoid(character)
	if hum and hum.Parent then
		local ratio = if hum.MaxHealth > 0 then math.clamp(hum.Health / hum.MaxHealth, 0, 1) else 1
		hum.MaxHealth = state.baseMaxHealth
		hum.Health = math.clamp(state.baseMaxHealth * ratio, 1, state.baseMaxHealth)
	end
	for part, look in state.parts do
		if part.Parent then
			part.Material = look.material
			part.Color = look.color
		end
	end
	if character.Parent then
		character:SetAttribute(GameConstants.ICE_FORM_ATTRIBUTE, nil)
		character:SetAttribute(GameConstants.ICE_FORM_UNTIL_ATTRIBUTE, nil)
		AbilityCooldownHelper.setActive(character, "ice_form", false)
		if applyCooldown then
			AbilityCooldownHelper.applyAfterUse(character, "ice_form", GameConstants.ICE_FORM_COOLDOWN)
			CharacterService.markAbilityUse(character)
		end
	end
end

local function startIceForm(player: Player)
	local character = player.Character
	if not character then
		return
	end
	if formByPlayer[player] then
		stopIceForm(player, true)
		return
	end
	local entry = CharacterRegistry.getAbilityById("iceman", "ice_form")
	if not entry or not canUse(character, entry.id, 0) then
		return
	end
	local hum = CombatHelper.getHumanoid(character)
	if not hum or hum.Health <= 0 then
		return
	end

	AbilityCooldownHelper.setActive(character, entry.id, true)

	-- Percentage HP scale only — Ice Form is not a heal / regen ability
	local base = hum.MaxHealth
	local ratio = if base > 0 then math.clamp(hum.Health / base, 0, 1) else 1
	local newMax = base * GameConstants.ICE_FORM_HEALTH_MULT
	hum.MaxHealth = newMax
	hum.Health = math.clamp(newMax * ratio, 1, newMax)

	local endsAt = AbilityCooldownHelper.getNow() + GameConstants.ICE_FORM_DURATION
	character:SetAttribute(GameConstants.ICE_FORM_ATTRIBUTE, true)
	character:SetAttribute(GameConstants.ICE_FORM_UNTIL_ATTRIBUTE, endsAt)

	formByPlayer[player] = {
		character = character,
		baseMaxHealth = base,
		endsAt = endsAt,
		lastAuraAt = 0,
		parts = applyIceLook(character),
	}
	iceBurst(character:GetPivot().Position, 6)
end

----------------------------------------------------------------
-- V Flash Freeze (shard → soft shove like Blinding Flash + cascade freeze)
----------------------------------------------------------------
--[[ Face the caster and get shoved outward while ice climbs the body. ]]
local function applyFlashFreezeStruggle(victim: Model, burstPos: Vector3)
	local vRoot = getRoot(victim)
	local hum = CombatHelper.getHumanoid(victim)
	if not vRoot or not hum or hum.Health <= 0 then
		return
	end

	local away = vRoot.Position - burstPos
	local flat = Vector3.new(away.X, 0, away.Z)
	if flat.Magnitude < 0.08 then
		local look = vRoot.CFrame.LookVector
		flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude < 0.08 then
			flat = Vector3.new(0, 0, -1)
		end
	end
	flat = flat.Unit

	local att = Instance.new("Attachment")
	att.Name = "IceFlashStruggleAtt"
	att.Parent = vRoot

	local align = Instance.new("AlignOrientation")
	align.Name = "IceFlashStruggleAlign"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = att
	align.RigidityEnabled = false
	align.MaxTorque = 120000
	align.Responsiveness = 14
	align.CFrame = CFrame.lookAt(vRoot.Position, Vector3.new(burstPos.X, vRoot.Position.Y, burstPos.Z))
	align.Parent = vRoot

	local speed = GameConstants.ICE_FLASH_PUSH_SPEED
	local up = GameConstants.ICE_FLASH_PUSH_UP
	vRoot.AssemblyLinearVelocity = flat * speed + Vector3.new(0, up, 0)

	local token = (victim:GetAttribute("IceFlashStruggleToken") :: number?) or 0
	token += 1
	victim:SetAttribute("IceFlashStruggleToken", token)

	task.spawn(function()
		local t0 = os.clock()
		local dur = GameConstants.ICE_FLASH_STRUGGLE_TIME
		while os.clock() - t0 < dur do
			if not vRoot.Parent or not victim.Parent then
				break
			end
			if victim:GetAttribute("IceFlashStruggleToken") ~= token then
				break
			end
			if not FrostStatus.isFrozen(victim) then
				break
			end
			local elapsed = os.clock() - t0
			local wobble = math.sin(elapsed * 16) * 0.18
			local facePos = Vector3.new(burstPos.X, vRoot.Position.Y, burstPos.Z)
			if (facePos - vRoot.Position).Magnitude > 0.05 then
				align.CFrame = CFrame.lookAt(vRoot.Position, facePos) * CFrame.Angles(wobble * 0.35, wobble, 0)
			end
			if hum.Parent then
				hum:Move(Vector3.zero, false)
				hum.WalkSpeed = 0
			end
			-- Don't fight seal() once it anchors
			if not vRoot.Anchored then
				local vel = vRoot.AssemblyLinearVelocity
				local retain = math.clamp(1 - elapsed / dur, 0.25, 1)
				vRoot.AssemblyLinearVelocity =
					Vector3.new(flat.X * speed * 0.55 * retain, math.max(vel.Y, 1.5), flat.Z * speed * 0.55 * retain)
			end
			task.wait()
		end
		if align.Parent then
			align:Destroy()
		end
		if att.Parent then
			att:Destroy()
		end
		-- Lock solid after the shove
		if victim.Parent and FrostStatus.isFrozen(victim) and victim:GetAttribute("IceFlashStruggleToken") == token then
			FrostStatus.seal(victim)
		end
	end)
end

local function castFlashFreeze(player: Player, direction: Vector3?, aimPoint: Vector3?)
	local character = player.Character
	if not character then
		return
	end
	local entry = CharacterRegistry.getAbilityById("iceman", "flash_freeze")
	if not entry or not canUse(character, entry.id, GameConstants.ICE_FLASH_FREEZE_ENERGY) then
		return
	end

	AbilityCooldownHelper.setActive(character, entry.id, true)

	local hand = getHand(character, true)
	local origin = if hand then hand.Position else character:GetPivot().Position
	local dir = resolveAimDir(character, direction, aimPoint)
	if aimPoint then
		local toAim = aimPoint - origin
		if toAim.Magnitude > 0.05 then
			dir = toAim.Unit
		end
	end

	ProjectileHelper.spawn(origin, dir, {
		speed = GameConstants.ICE_FLASH_FREEZE_SPEED,
		damage = GameConstants.ICE_FLASH_FREEZE_DAMAGE,
		radius = GameConstants.ICE_FLASH_FREEZE_HIT_RADIUS,
		maxDistance = GameConstants.ICE_FLASH_FREEZE_RANGE,
		owner = character,
		color = GameConstants.ICE_COLOR,
		homeDir = dir,
		homePoint = aimPoint or (origin + dir * 60),
		homeAfter = 0,
		boltFolder = "IceMan",
		boltAsset = "IceShard",
		impactFx = "none",
		deleteAfterFx = GameConstants.ICE_SHARD_DELETE_AFTER_FX,
		onHit = function(victim: Model, hitPos: Vector3)
			if not isRealTarget(victim, character) or FrostStatus.isImmune(victim) or CombatHelper.isShielded(victim) then
				return
			end
			iceBurst(hitPos, 4)
			local victimPlayer = Players:GetPlayerFromCharacter(victim)
			if victimPlayer then
				fireCameraShake(victimPlayer, 0.55, 0.35)
			end
			-- Soft freeze (shells climb feet→head) while the shove plays out, then seal
			if FrostStatus.freeze(victim, GameConstants.ICE_FLASH_FREEZE_DURATION, { allowMotion = true }) then
				applyFlashFreezeStruggle(victim, origin)
			end
		end,
	})

	finishAbility(character, entry.id, GameConstants.ICE_FLASH_FREEZE_COOLDOWN)
end

----------------------------------------------------------------
-- G Shatter
----------------------------------------------------------------
--[[ Clone ShatterAttachment onto HRP; smooth-disable at 0.2s, delete at 5s. ]]
local function playShatterAttachment(root: BasePart)
	local template = getIceManAttachment("ShatterAttachment")
	if not template then
		warn("[IcemanService] Missing ReplicatedStorage.Assets.IceMan.ShatterAttachment")
		return
	end
	local att = template:Clone()
	att.Name = "ShatterAttachment"
	att.Position = Vector3.zero
	att.Orientation = Vector3.zero
	att.Parent = root
	VfxHelper.setParticlesEnabled(att, true)
	VfxHelper.emitAllParticles(att, 18)
	task.delay(0.05, function()
		if att.Parent then
			VfxHelper.smoothDisableParticles(att, 0.08)
		end
	end)
	task.delay(1.5, function()
		if att.Parent then
			att:Destroy()
		end
	end)
end

local function castShatter(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local entry = CharacterRegistry.getAbilityById("iceman", "shatter")
	if not entry or not canUse(character, entry.id, GameConstants.ICE_SHATTER_ENERGY) then
		return
	end

	AbilityCooldownHelper.setActive(character, entry.id, true)

	local root = getRoot(character)
	local center = if root then root.Position else character:GetPivot().Position
	if root then
		playShatterAttachment(root)
	end
	iceBurst(center, GameConstants.ICE_SHATTER_RADIUS * 0.6)
	fireCameraShake(player, 0.5, 0.3)

	for _, victim in CombatHelper.overlapCharacters(center, GameConstants.ICE_SHATTER_RADIUS, character) do
		if not isRealTarget(victim, character) then
			continue
		end
		local chill, wasFrozen, shells = FrostStatus.consumeChill(victim)
		if chill <= 0 and not wasFrozen then
			continue
		end

		local damage = math.max(GameConstants.ICE_SHATTER_MIN_DAMAGE, chill * GameConstants.ICE_SHATTER_CHILL_MULT)
		if wasFrozen then
			damage += GameConstants.ICE_SHATTER_FROZEN_BONUS
		end

		local vRoot = getRoot(victim)
		local hitPos = if vRoot then vRoot.Position else victim:GetPivot().Position
		CombatHelper.dealDamage(character, victim, damage, center, "projectile")
		iceBurst(hitPos, 4)

		if #shells > 0 then
			FrostStatus.flingShells(shells)
		end

		if not CombatHelper.isShielded(victim) then
			local away = hitPos - center
			if away.Magnitude < 0.05 then
				away = Vector3.new(0, 0, -1)
			end
			PushHelper.applyToCharacter(victim, away, {
				speed = GameConstants.ICE_SHATTER_PUSH_SPEED,
				upBoost = GameConstants.ICE_SHATTER_PUSH_UP,
			})
		end
	end

	finishAbility(character, entry.id, GameConstants.ICE_SHATTER_COOLDOWN)
end

----------------------------------------------------------------
-- X Absolute Zero
----------------------------------------------------------------
local function endBlizzard(player: Player, applyCooldown: boolean?)
	local state = blizzardByPlayer[player]
	if not state then
		return
	end
	blizzardByPlayer[player] = nil

	if state.part.Parent then
		TweenService:Create(state.part, TweenInfo.new(0.6), { Transparency = 1 }):Play()
		Debris:AddItem(state.part, 0.8)
	end
	local character = state.character
	if character.Parent then
		AbilityCooldownHelper.setActive(character, "absolute_zero", false)
		if applyCooldown then
			AbilityCooldownHelper.applyAfterUse(character, "absolute_zero", GameConstants.ICE_BLIZZARD_COOLDOWN)
			CharacterService.markAbilityUse(character)
		end
	end
end

local function castAbsoluteZero(player: Player)
	local character = player.Character
	if not character or blizzardByPlayer[player] then
		return
	end
	local entry = CharacterRegistry.getAbilityById("iceman", "absolute_zero")
	if not entry or not canUse(character, entry.id, GameConstants.ICE_BLIZZARD_ENERGY) then
		return
	end

	AbilityCooldownHelper.setActive(character, entry.id, true)

	local center = getFootPosition(character)

	-- PARTICLE_PLACEHOLDER: flat ice disc that grows out from Iceman
	local zone = Instance.new("Part")
	zone.Name = "AbsoluteZeroField"
	zone.Shape = Enum.PartType.Cylinder
	local thick = GameConstants.ICE_BLIZZARD_DISC_THICKNESS
	zone.Size = Vector3.new(thick, 2, 2)
	-- Cylinder axis is X; rotate so the disc lies flat on the ground plane
	zone.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
	zone.Anchored = true
	zone.CanCollide = false
	zone.CanQuery = false
	zone.CanTouch = false
	zone.CastShadow = false
	zone.Material = Enum.Material.Ice
	zone.Color = GameConstants.ICE_COLOR
	zone.Transparency = 0.55
	zone.Parent = Workspace

	local now = AbilityCooldownHelper.getNow()
	blizzardByPlayer[player] = {
		character = character,
		center = center,
		part = zone,
		startedAt = now,
		endsAt = now + GameConstants.ICE_BLIZZARD_DURATION,
		lastTick = now,
	}
	fireCameraShake(player, 0.7, 0.5)
end

----------------------------------------------------------------
-- Public API
----------------------------------------------------------------
function IcemanService.cancelAll(player: Player)
	stopCryoStream(player, false)
	stopIceSlide(player, false)
	stopIceForm(player, false)
	endBlizzard(player, false)

	local walls = wallsByPlayer[player]
	if walls then
		wallsByPlayer[player] = nil
		for _, wall in walls do
			retireWall(wall)
		end
	end

	local character = player.Character
	if character then
		character:SetAttribute(GameConstants.BUSY_ATTRIBUTE, nil)
		for _, ability in CharacterRegistry.getAbilities("iceman") do
			AbilityCooldownHelper.setActive(character, ability.id, false)
		end
	end
end

function IcemanService.handleAction(player: Player, payload: any)
	if type(payload) ~= "table" then
		return
	end
	local character = player.Character
	if not character or character:GetAttribute(GameConstants.HERO_ATTRIBUTE) ~= "iceman" then
		return
	end
	if character:GetAttribute(GameConstants.RAGDOLLED_ATTRIBUTE) == true then
		return
	end

	local action = payload.action
	if type(action) ~= "string" then
		return
	end

	local direction = if typeof(payload.direction) == "Vector3" then payload.direction else nil
	local aimPoint = if typeof(payload.aimPoint) == "Vector3" then payload.aimPoint else nil

	if action == "Q" then
		castIceShards(player, direction, aimPoint)
	elseif action == "E" or action == "E_down" then
		castIceWall(player, direction, aimPoint)
	elseif action == "F" then
		startIceSlide(player)
	elseif action == "T_down" then
		startCryoStream(player, aimPoint or (character:GetPivot().Position + character:GetPivot().LookVector * 40))
	elseif action == "T_up" then
		stopCryoStream(player, true)
	elseif action == "T_aim" then
		local state = streamByPlayer[player]
		if state and aimPoint then
			state.aimPoint = aimPoint
		end
	elseif action == "C" or action == "C_down" then
		startIceForm(player)
	elseif action == "X" then
		castAbsoluteZero(player)
	elseif action == "V" then
		castFlashFreeze(player, direction, aimPoint)
	elseif action == "G" then
		castShatter(player)
	end
end

local function updateStreams(dtClamped: number, now: number)
	for player, state in streamByPlayer do
		local character = state.character
		if not character.Parent or player.Character ~= character then
			stopCryoStream(player, true)
			continue
		end
		if CombatHelper.arePowersDisabled(character) then
			stopCryoStream(player, true)
			continue
		end

		local energy = character:GetAttribute(GameConstants.ENERGY_ATTRIBUTE)
		if type(energy) ~= "number" or energy <= 0 then
			stopCryoStream(player, true)
			continue
		end
		character:SetAttribute(
			GameConstants.ENERGY_ATTRIBUTE,
			math.max(0, energy - GameConstants.ICE_STREAM_ENERGY_PER_SEC * dtClamped)
		)
		CharacterService.markAbilityUse(character)

		local root = getRoot(character)
		local origin = if root then root.Position else character:GetPivot().Position
		local toAim = state.aimPoint - origin
		local faceDir = if toAim.Magnitude > 0.05 then toAim.Unit else character:GetPivot().LookVector
		local forward = Vector3.new(faceDir.X, 0, faceDir.Z)
		if forward.Magnitude < 0.05 then
			forward = Vector3.new(0, 0, -1)
		else
			forward = forward.Unit
		end

		if root and state.faceAlign then
			setYawAlign(state.faceAlign, root, forward)
		end

		if state.animTrack and state.animTrack.Parent and not state.animTrack.IsPlaying then
			state.animTrack:Play(0.1, 1, 1)
		end

		if now - state.lastTick >= GameConstants.ICE_STREAM_TICK then
			local tick = math.clamp(now - state.lastTick, 0, 0.5)
			state.lastTick = now
			local range = GameConstants.ICE_STREAM_RANGE
			local chill = GameConstants.ICE_STREAM_CHILL_PER_SEC * tick
			for _, victim in CombatHelper.overlapCharacters(origin, range, character) do
				if not isRealTarget(victim, character) then
					continue
				end
				local vRoot = getRoot(victim)
				local vPos = if vRoot then vRoot.Position else victim:GetPivot().Position
				local delta = vPos - origin
				local flat = Vector3.new(delta.X, 0, delta.Z)
				if flat.Magnitude > range or flat.Magnitude < 0.05 then
					continue
				end
				if flat.Unit:Dot(forward) < GameConstants.ICE_STREAM_FRONT_DOT then
					continue
				end
				FrostStatus.addChill(victim, chill)
			end
		end
	end
end

local function updateSlides(dtClamped: number, now: number)
	for player, state in slideByPlayer do
		local character = state.character
		if player.Character ~= character or not character.Parent or not state.humanoid.Parent or not state.root.Parent then
			stopIceSlide(player, false)
			continue
		end
		if state.humanoid.Health <= 0 or CombatHelper.arePowersDisabled(character) then
			stopIceSlide(player, true)
			continue
		end

		local energy = character:GetAttribute(GameConstants.ENERGY_ATTRIBUTE)
		if type(energy) ~= "number" or energy <= 0 then
			stopIceSlide(player, true)
			continue
		end
		character:SetAttribute(
			GameConstants.ENERGY_ATTRIBUTE,
			math.max(0, energy - GameConstants.ICE_SLIDE_ENERGY_PER_SEC * dtClamped)
		)
		CharacterService.markAbilityUse(character)

		local look = state.lookDir
		if look.Magnitude < 0.01 then
			look = Vector3.new(0, 0, -1)
		else
			look = look.Unit
		end
		local lookFlat = Vector3.new(look.X, 0, look.Z)
		if lookFlat.Magnitude < 0.01 then
			lookFlat = Vector3.new(0, 0, -1)
		else
			lookFlat = lookFlat.Unit
		end

		local speed = GameConstants.ICE_SLIDE_SPEED
		-- Always skate forward along camera look, biased a bit upward — ignore strafe/WASD
		local dir = (look + Vector3.new(0, GameConstants.ICE_SLIDE_LOOK_UP, 0))
		if dir.Magnitude < 0.05 then
			dir = lookFlat + Vector3.new(0, GameConstants.ICE_SLIDE_LOOK_UP, 0)
		end
		dir = dir.Unit
		state.root.AssemblyLinearVelocity = dir * speed
		state.humanoid:Move(lookFlat, false)

		setYawAlign(state.faceAlign, state.root, lookFlat)

		if state.animTrack and state.animTrack.Parent and not state.animTrack.IsPlaying then
			state.animTrack:Play(0.1, 1, 1)
		end

		if state.humanoid.WalkSpeed < speed - 0.5 then
			state.humanoid.WalkSpeed = speed
		end

		local fx = state.beamFx
		if fx then
			local backPos = getSlidePathPoint(character, look, -GameConstants.ICE_SLIDE_SLAB_LEAD)
			local frontPos = getSlidePathPoint(character, look, GameConstants.ICE_SLIDE_SLAB_LEAD)
			fx.backHost.CFrame = CFrame.new(backPos)
			fx.frontHost.CFrame = CFrame.new(frontPos)
			if not fx.backBeam.Enabled then
				fx.backBeam.Enabled = true
			end
			if not fx.frontBeam.Enabled then
				fx.frontBeam.Enabled = true
			end
		end

		if now - state.lastSlabAt >= GameConstants.ICE_SLIDE_SLAB_INTERVAL then
			state.lastSlabAt = now
			spawnSlideSlab(character, look)
		end
	end
end

local function updateForms(dtClamped: number, now: number)
	for player, state in formByPlayer do
		local character = state.character
		if not character.Parent or player.Character ~= character then
			stopIceForm(player, true)
			continue
		end
		local hum = CombatHelper.getHumanoid(character)
		if not hum or hum.Health <= 0 then
			stopIceForm(player, true)
			continue
		end
		if now >= state.endsAt then
			stopIceForm(player, true)
			continue
		end

		local energy = character:GetAttribute(GameConstants.ENERGY_ATTRIBUTE)
		if type(energy) ~= "number" or energy <= 0 then
			stopIceForm(player, true)
			continue
		end
		character:SetAttribute(
			GameConstants.ENERGY_ATTRIBUTE,
			math.max(0, energy - GameConstants.ICE_FORM_ENERGY_PER_SEC * dtClamped)
		)

		if now - state.lastAuraAt >= GameConstants.ICE_FORM_AURA_INTERVAL then
			state.lastAuraAt = now
			local root = getRoot(character)
			local center = if root then root.Position else character:GetPivot().Position
			for _, victim in CombatHelper.overlapCharacters(center, GameConstants.ICE_FORM_AURA_RADIUS, character) do
				if isRealTarget(victim, character) then
					FrostStatus.addChill(victim, GameConstants.ICE_FORM_AURA_CHILL)
				end
			end
		end
	end
end

local function updateBlizzards(now: number)
	for player, state in blizzardByPlayer do
		local character = state.character
		if not character.Parent or player.Character ~= character then
			endBlizzard(player, true)
			continue
		end
		if now >= state.endsAt then
			endBlizzard(player, true)
			continue
		end

		-- Fixed spawn center — does not follow Iceman
		local radius = GameConstants.ICE_BLIZZARD_RADIUS
		local grow = math.clamp((now - state.startedAt) / GameConstants.ICE_BLIZZARD_GROW_TIME, 0, 1)
		local diameter = math.max(2, radius * 2 * grow)
		local thick = GameConstants.ICE_BLIZZARD_DISC_THICKNESS
		if state.part.Parent then
			state.part.Size = Vector3.new(thick, diameter, diameter)
			state.part.CFrame = CFrame.new(state.center) * CFrame.Angles(0, 0, math.rad(90))
		end

		if now - state.lastTick >= GameConstants.ICE_BLIZZARD_TICK then
			local tick = math.clamp(now - state.lastTick, 0, 0.5)
			state.lastTick = now
			for _, victim in CombatHelper.overlapCharacters(state.center, radius * grow, character) do
				if not isRealTarget(victim, character) then
					continue
				end
				CombatHelper.dealDamage(
					character,
					victim,
					GameConstants.ICE_BLIZZARD_DAMAGE_PER_SEC * tick,
					state.center,
					"projectile"
				)
				FrostStatus.addChill(victim, GameConstants.ICE_BLIZZARD_CHILL_PER_SEC * tick)
			end
		end
	end
end

function IcemanService.update(dt: number)
	local dtClamped = math.clamp(dt, 0.001, 0.1)
	local now = AbilityCooldownHelper.getNow()

	FrostStatus.update(dtClamped)
	updateStreams(dtClamped, now)
	updateSlides(dtClamped, now)
	updateForms(dtClamped, now)
	updateBlizzards(now)
end

function IcemanService.init()
	Remotes.getEvent("CameraShake")
	Remotes.getEvent("UseAbility").OnServerEvent:Connect(function(player: Player, payload: any)
		IcemanService.handleAction(player, payload)
	end)
	-- Reuse the flight input stream while Ice Slide is active
	Remotes.getEvent("FlightInput").OnServerEvent:Connect(function(player: Player, payload: any)
		if type(payload) ~= "table" or not slideByPlayer[player] then
			return
		end
		local move = if typeof(payload.moveVector) == "Vector3" then payload.moveVector else Vector3.zero
		local look = if typeof(payload.lookVector) == "Vector3" then payload.lookVector else Vector3.new(0, 0, -1)
		IcemanService.setSlideInput(player, move, look)
	end)

	local function hookPlayer(player: Player)
		player.CharacterRemoving:Connect(function(character)
			IcemanService.cancelAll(player)
			FrostStatus.clear(character)
		end)
		player.CharacterAdded:Connect(function(character)
			IcemanService.cancelAll(player)
			FrostStatus.clear(character)
			local humanoid = character:WaitForChild("Humanoid", 5)
			if humanoid and humanoid:IsA("Humanoid") then
				humanoid.Died:Connect(function()
					IcemanService.cancelAll(player)
					FrostStatus.clear(character)
				end)
			end
		end)
	end

	for _, player in Players:GetPlayers() do
		hookPlayer(player)
	end
	Players.PlayerAdded:Connect(hookPlayer)
	Players.PlayerRemoving:Connect(function(player)
		IcemanService.cancelAll(player)
		wallsByPlayer[player] = nil
	end)
end

return IcemanService
