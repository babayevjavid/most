--!strict

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AbilityCooldownHelper = require(ReplicatedStorage.Shared.AbilityCooldownHelper)
local CharacterRegistry = require(ReplicatedStorage.Shared.CharacterRegistry)
local CombatHelper = require(ReplicatedStorage.Shared.CombatHelper)
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

local InvisibleWomanService = {}

type PowerFx = { instances: { Instance }, refs: number }

type ShieldState = {
	character: Model,
	hp: number,
	maxHp: number,
	forcefield: Instance,
	walk: number,
	jumpPower: number?,
	jumpHeight: number?,
	healthConn: RBXScriptConnection?,
	lastHealth: number,
	billboard: BillboardGui?,
	hpLabel: TextLabel?,
	hpFill: Frame?,
	lockWalk: boolean,
	fromProtect: boolean,
	animTrack: AnimationTrack?,
}

type FlightFx = {
	instances: { Instance },
	hp: number,
	maxHp: number,
	billboard: BillboardGui?,
	hpLabel: TextLabel?,
	hpFill: Frame?,
	stealthSaved: { { inst: Instance, t: number, enabled: boolean? } }?,
}

type PushState = {
	part: BasePart,
	visual: Instance,
	owner: Model,
	hit: { [Model]: boolean },
	alive: boolean,
	launched: boolean,
	launchAt: number,
	dir: Vector3,
	bornAt: number,
	casterHoldPos: Vector3,
	walk: number,
	jumpPower: number?,
	jumpHeight: number?,
	autoRotate: boolean,
}

type CrushState = {
	character: Model,
	victim: Model,
	vRoot: BasePart,
	fx: Instance,
	holdPos: Vector3,
	casterHoldPos: Vector3,
	tickAcc: number,
	walk: number,
	jumpPower: number?,
	jumpHeight: number?,
	autoRotate: boolean,
	faceAlign: AlignOrientation?,
	casterAnim: AnimationTrack?,
	victimAnim: AnimationTrack?,
	endsAt: number,
}

type ChokeVictim = {
	character: Model,
	walk: number,
	jumpPower: number?,
	jumpHeight: number?,
	fx: Instance?,
	damageTaken: number,
	previousPowersDisabledUntil: number?,
}

type AreaState = {
	character: Model,
	part: BasePart,
	visual: Instance,
	choking: boolean,
	victims: { [Model]: ChokeVictim },
	powerDisabled: { [Model]: number? },
	tickAcc: number,
	hp: number,
	maxHp: number,
	billboard: BillboardGui?,
	hpLabel: TextLabel?,
	hpFill: Frame?,
	walk: number,
	jumpPower: number?,
	jumpHeight: number?,
	autoRotate: boolean,
}

type ProjectionState = {
	visual: Instance,
	part: BasePart,
	owner: Model,
	hit: { [Model]: boolean },
	alive: boolean,
	dir: Vector3,
	launched: boolean,
	launchAt: number,
	bornAt: number,
	spawnPos: Vector3,
	casterHoldPos: Vector3,
	walk: number,
	jumpPower: number?,
	jumpHeight: number?,
	autoRotate: boolean,
}

type InvisState = {
	character: Model,
	fx: { Instance },
	saved: { { inst: Instance, t: number } },
	token: number,
}

local HERO = "invisible_woman"
local AIM_POINT_RADIUS = 6
local AIM_LOCK_RADIUS = 10

local powerFxByCharacter: { [Model]: PowerFx } = {}
local shieldByPlayer: { [Player]: ShieldState } = {}
local flightFxByCharacter: { [Model]: FlightFx } = {}
local pushByPlayer: { [Player]: PushState } = {}
local crushByPlayer: { [Player]: CrushState } = {}
local areaByPlayer: { [Player]: AreaState } = {}
local projectionByPlayer: { [Player]: ProjectionState } = {}
local smashToken: { [Player]: number } = {}
local smashWallsByPlayer: { [Player]: { Instance } } = {}
local smashHoldByPlayer: { [Player]: {
	walk: number,
	jumpPower: number?,
	jumpHeight: number?,
	autoRotate: boolean,
} } = {}
local discSideByPlayer: { [Player]: boolean } = {}
local invisByPlayer: { [Player]: InvisState } = {}
local invisToken: { [Player]: number } = {}

local function getRoot(model: Model): BasePart?
	local r = model:FindFirstChild("HumanoidRootPart")
	if r and r:IsA("BasePart") then
		return r
	end
	return model.PrimaryPart
end

local function playWorldSound(soundId: string, at: Vector3, volume: number?)
	local host = Instance.new("Part")
	host.Name = "IwSfx"
	host.Size = Vector3.new(0.2, 0.2, 0.2)
	host.Transparency = 1
	host.Anchored = true
	host.CanCollide = false
	host.CanQuery = false
	host.CanTouch = false
	host.CastShadow = false
	host.CFrame = CFrame.new(at)
	host.Parent = Workspace
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume or 0.85
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

local function stopTrack(track: AnimationTrack?)
	if track then
		pcall(function()
			track:Stop(0.12)
		end)
	end
end

local function playCharacterAnim(
	character: Model,
	assetId: string,
	looped: boolean?,
	priority: Enum.AnimationPriority?
): AnimationTrack?
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
	track.Looped = looped == true
	track:Play(0.1, 1, 1)
	return track
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

local function normalizeDir(v: Vector3): Vector3
	if v.Magnitude < 0.01 then
		return Vector3.new(0, 0, -1)
	end
	return v.Unit
end

local function fireCameraShake(player: Player, intensity: number?, duration: number?, fovScale: number?, vignetteScale: number?)
	Remotes.getEvent("CameraShake"):FireClient(player, {
		intensity = intensity or 0.42,
		duration = duration or 0.3,
		fovScale = fovScale,
		vignetteScale = vignetteScale,
	})
end

local function applyStandingPush(victim: Model, direction: Vector3, speed: number, upBoost: number)
	local vRoot = getRoot(victim)
	local hum = CombatHelper.getHumanoid(victim)
	if not vRoot or not hum or hum.Health <= 0 or vRoot.Anchored then
		return
	end

	local pushDir = if direction.Magnitude > 0.05 then direction.Unit else Vector3.new(0, 0, -1)
	local flat = Vector3.new(pushDir.X, 0, pushDir.Z)
	if flat.Magnitude < 0.08 then
		local look = vRoot.CFrame.LookVector
		flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude < 0.08 then
			flat = Vector3.new(0, 0, -1)
		end
	end
	flat = flat.Unit

	local att = Instance.new("Attachment")
	att.Name = "IwPushStruggleAtt"
	att.Parent = vRoot

	local align = Instance.new("AlignOrientation")
	align.Name = "IwPushStruggleAlign"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = att
	align.RigidityEnabled = false
	align.MaxTorque = 120000
	align.Responsiveness = 14
	-- Face reverse of shove (look back along the push)
	local facePos = vRoot.Position - flat
	align.CFrame = CFrame.lookAt(vRoot.Position, Vector3.new(facePos.X, vRoot.Position.Y, facePos.Z))
	align.Parent = vRoot

	vRoot.AssemblyLinearVelocity = flat * speed + Vector3.new(0, upBoost, 0)
	ScreenFeelHelper.pulseCharacter(victim, {
		intensity = 0.62,
		duration = 0.32,
		fovScale = 0.36,
		vignetteScale = 0.4,
	})

	local origWalk = hum.WalkSpeed
	local origJumpPower = if hum.UseJumpPower then hum.JumpPower else nil
	local origJumpHeight = if not hum.UseJumpPower then hum.JumpHeight else nil
	local origAutoRotate = hum.AutoRotate
	local token = (victim:GetAttribute("IwPushStruggleToken") :: number?) or 0
	token += 1
	victim:SetAttribute("IwPushStruggleToken", token)
	hum.WalkSpeed = 0
	hum.AutoRotate = false
	if hum.UseJumpPower then
		hum.JumpPower = 0
	else
		hum.JumpHeight = 0
	end

	task.spawn(function()
		local t0 = os.clock()
		local dur = GameConstants.IW_PUSH_STRUGGLE_TIME
		while os.clock() - t0 < dur do
			if not vRoot.Parent or not victim.Parent then
				break
			end
			if victim:GetAttribute("IwPushStruggleToken") ~= token then
				break
			end
			local elapsed = os.clock() - t0
			local wobble = math.sin(elapsed * 16) * 0.18
			local lookBack = vRoot.Position - flat
			local faceAt = Vector3.new(lookBack.X, vRoot.Position.Y, lookBack.Z)
			if (faceAt - vRoot.Position).Magnitude > 0.05 then
				align.CFrame = CFrame.lookAt(vRoot.Position, faceAt) * CFrame.Angles(wobble * 0.35, wobble, 0)
			end
			hum:Move(Vector3.zero, false)
			hum.WalkSpeed = 0
			local vel = vRoot.AssemblyLinearVelocity
			local retain = math.clamp(1 - elapsed / dur, 0.25, 1)
			vRoot.AssemblyLinearVelocity = Vector3.new(flat.X * speed * 0.55 * retain, math.max(vel.Y, 1.5), flat.Z * speed * 0.55 * retain)
			task.wait()
		end
		if align.Parent then
			align:Destroy()
		end
		if att.Parent then
			att:Destroy()
		end
		if hum.Parent and hum.Health > 0 and victim:GetAttribute("IwPushStruggleToken") == token then
			hum.WalkSpeed = origWalk
			hum.AutoRotate = origAutoRotate
			if origJumpPower ~= nil then
				hum.JumpPower = origJumpPower
			end
			if origJumpHeight ~= nil then
				hum.JumpHeight = origJumpHeight
			end
		end
	end)
end

local function yawLookAt(origin: Vector3, target: Vector3): CFrame
	local flat = Vector3.new(target.X - origin.X, 0, target.Z - origin.Z)
	if flat.Magnitude < 0.08 then
		return CFrame.new(origin)
	end
	return CFrame.lookAt(origin, origin + flat.Unit)
end

local function ensureCrushFaceAlign(root: BasePart, targetCf: CFrame): AlignOrientation
	local att = root:FindFirstChild("IwCrushFaceAtt")
	if not (att and att:IsA("Attachment")) then
		if att then
			att:Destroy()
		end
		att = Instance.new("Attachment")
		att.Name = "IwCrushFaceAtt"
		att.Parent = root
	end
	local align = root:FindFirstChild("IwCrushFaceAlign")
	if not (align and align:IsA("AlignOrientation")) then
		if align then
			align:Destroy()
		end
		align = Instance.new("AlignOrientation")
		align.Name = "IwCrushFaceAlign"
		align.Mode = Enum.OrientationAlignmentMode.OneAttachment
		align.Attachment0 = att
		align.RigidityEnabled = false
		align.MaxTorque = 400000
		align.Responsiveness = GameConstants.IW_FACE_RESPONSIVENESS
		align.Parent = root
	end
	align.CFrame = targetCf
	local flightAlign = root:FindFirstChild("HeroAlignOrientation")
	if flightAlign and flightAlign:IsA("AlignOrientation") then
		flightAlign.CFrame = targetCf
	end
	return align
end

local function clearCrushFace(root: BasePart?)
	if not root then
		return
	end
	local align = root:FindFirstChild("IwCrushFaceAlign")
	if align then
		align:Destroy()
	end
	local att = root:FindFirstChild("IwCrushFaceAtt")
	if att then
		att:Destroy()
	end
end

local faceTokenByCharacter: { [Model]: number } = {}

local function clearCastFace(character: Model)
	local root = getRoot(character)
	if root then
		local align = root:FindFirstChild("IwCastFaceAlign")
		if align then
			align:Destroy()
		end
		local att = root:FindFirstChild("IwCastFaceAtt")
		if att then
			att:Destroy()
		end
		clearCrushFace(root)
	end
	faceTokenByCharacter[character] = (faceTokenByCharacter[character] or 0) + 1
end

local function faceToward(character: Model, worldPoint: Vector3?, holdSeconds: number?)
	if not worldPoint then
		return
	end
	local root = getRoot(character)
	local hum = CombatHelper.getHumanoid(character)
	if not root or not hum or hum.Health <= 0 then
		return
	end
	local owner = Players:GetPlayerFromCharacter(character)
	if owner and crushByPlayer[owner] then
		ensureCrushFaceAlign(root, yawLookAt(root.Position, worldPoint))
		return
	end
	if character:GetAttribute(GameConstants.IS_FLYING_ATTRIBUTE) == true then
		return
	end
	local flat = Vector3.new(worldPoint.X - root.Position.X, 0, worldPoint.Z - root.Position.Z)
	if flat.Magnitude < 0.08 then
		return
	end
	local targetCf = CFrame.lookAt(root.Position, root.Position + flat.Unit)
	local token = (faceTokenByCharacter[character] or 0) + 1
	faceTokenByCharacter[character] = token

	local att = root:FindFirstChild("IwCastFaceAtt")
	if not (att and att:IsA("Attachment")) then
		if att then
			att:Destroy()
		end
		att = Instance.new("Attachment")
		att.Name = "IwCastFaceAtt"
		att.Parent = root
	end
	local existing = root:FindFirstChild("IwCastFaceAlign")
	if existing then
		existing:Destroy()
	end
	local align = Instance.new("AlignOrientation")
	align.Name = "IwCastFaceAlign"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = att
	align.RigidityEnabled = false
	align.MaxTorque = 420000
	align.Responsiveness = GameConstants.IW_FACE_RESPONSIVENESS
	align.CFrame = targetCf
	align.Parent = root

	local origAuto = hum.AutoRotate
	hum.AutoRotate = false
	task.delay(holdSeconds or 0.32, function()
		if faceTokenByCharacter[character] ~= token then
			return
		end
		if align.Parent then
			align:Destroy()
		end
		if att.Parent and att.Name == "IwCastFaceAtt" then
			att:Destroy()
		end
		if hum.Parent and hum.Health > 0 then
			local flying = character:GetAttribute(GameConstants.IS_FLYING_ATTRIBUTE) == true
			hum.AutoRotate = if flying then false else true
		end
	end)
end

local function finishAbility(character: Model, abilityId: string, cooldown: number)
	AbilityCooldownHelper.setActive(character, abilityId, false)
	AbilityCooldownHelper.applyAfterUse(character, abilityId, cooldown)
	CharacterService.markAbilityUse(character)
end

local function canUse(character: Model, abilityId: string, energy: number): boolean
	if character:GetAttribute(GameConstants.IS_FLYING_ATTRIBUTE) == true then
		local modern = character:GetAttribute(GameConstants.LOOK_MODE_ATTRIBUTE) == "modern"
		if
			abilityId ~= "forcefield_flight"
			and abilityId ~= "invisibility"
			and not (modern and (abilityId == "disc_throw" or abilityId == "forcefield_area"))
		then
			return false
		end
	end
	if CombatHelper.arePowersDisabled(character) then
		return false
	end
	local owner = Players:GetPlayerFromCharacter(character)
	local area = if owner then areaByPlayer[owner] else nil
	local areaCompanion = area ~= nil
		and (abilityId == "forcefield_choke" or abilityId == "forcefield_protect")
	if character:GetAttribute(GameConstants.BUSY_ATTRIBUTE) == true and not areaCompanion then
		return false
	end
	if character:GetAttribute(GameConstants.MG_TK_CONTROLLED_ATTRIBUTE) == true then
		return false
	end
	if AbilityCooldownHelper.isOnCooldown(character, abilityId) then
		return false
	end
	if AbilityCooldownHelper.isActive(character, abilityId) then
		return false
	end
	if area then
		if abilityId == "forcefield_flight" then
			return false
		end
		if not area.choking then
			if abilityId ~= "forcefield_area" and abilityId ~= "forcefield_choke" and abilityId ~= "forcefield_protect" then
				return false
			end
		end
	end
	for _, ab in CharacterRegistry.getAbilities(HERO) do
		if ab.passive or ab.id == abilityId or ab.id == "forcefield_flight" or ab.id == "invisibility" then
			continue
		end
		if area and (ab.id == "forcefield_area" or (area.choking and ab.id == "forcefield_choke")) then
			continue
		end
		if AbilityCooldownHelper.isActive(character, ab.id) then
			return false
		end
	end
	if character:GetAttribute(GameConstants.LOOK_MODE_ATTRIBUTE) == "modern" then
		energy *= 0.75
	end
	if energy > 0 and not CharacterService.spendEnergy(character, energy) then
		return false
	end
	return true
end

local function fadeParticles(root: Instance, enabled: boolean)
	VfxHelper.setParticlesEnabled(root, enabled)
	for _, desc in root:GetDescendants() do
		if desc:IsA("ParticleEmitter") then
			desc.Enabled = enabled
		end
	end
end

local function forEachEmitter(root: Instance, fn: (ParticleEmitter) -> ())
	if root:IsA("ParticleEmitter") then
		fn(root)
	end
	for _, desc in root:GetDescendants() do
		if desc:IsA("ParticleEmitter") then
			fn(desc)
		end
	end
end

local function setBreakBurst(root: Instance, enabled: boolean)
	forEachEmitter(root, function(em)
		if em.Name == "1" then
			em.Enabled = false
			if enabled then
				em:Emit(math.clamp(math.floor(em.Rate * 0.3 + 8), 6, 40))
			end
		end
	end)
end

local function setIdleShieldParticles(root: Instance, enabled: boolean)
	forEachEmitter(root, function(em)
		if em.Name == "1" then
			em.Enabled = false
		else
			em.Enabled = enabled
		end
	end)
end

local function disableAreaShieldCollision(root: Instance)
	local function prep(bp: BasePart)
		bp.CanCollide = false
		bp.CanQuery = false
	end
	if root:IsA("BasePart") then
		prep(root)
	end
	for _, desc in root:GetDescendants() do
		if desc:IsA("BasePart") then
			prep(desc)
		end
	end
end

local function fadeOutVisual(root: Instance, duration: number, skipParticles: boolean?)
	disableAreaShieldCollision(root)
	local fade = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local function fadeInst(inst: Instance)
		if inst:IsA("BasePart") then
			TweenService:Create(inst, fade, { Transparency = 1 }):Play()
		elseif inst:IsA("Decal") or inst:IsA("Texture") then
			TweenService:Create(inst, fade, { Transparency = 1 }):Play()
		elseif inst:IsA("Beam") or inst:IsA("Trail") then
			inst.Enabled = false
			local keys: { NumberSequenceKeypoint } = {}
			for _, key in inst.Transparency.Keypoints do
				table.insert(keys, NumberSequenceKeypoint.new(key.Time, 1, key.Envelope))
			end
			inst.Transparency = NumberSequence.new(keys)
		elseif inst:IsA("PointLight") or inst:IsA("SpotLight") or inst:IsA("SurfaceLight") then
			TweenService:Create(inst, fade, { Brightness = 0 }):Play()
		end
	end
	fadeInst(root)
	for _, desc in root:GetDescendants() do
		fadeInst(desc)
	end
	if skipParticles ~= true then
		VfxHelper.smoothDisableParticles(root, duration)
		forEachEmitter(root, function(em)
			local startKeys = em.Transparency.Keypoints
			local t0 = os.clock()
			task.spawn(function()
				while em.Parent and (os.clock() - t0) < duration do
					local a = math.clamp((os.clock() - t0) / duration, 0, 1)
					local keys: { NumberSequenceKeypoint } = {}
					for _, key in startKeys do
						table.insert(keys, NumberSequenceKeypoint.new(key.Time, key.Value + (1 - key.Value) * a, key.Envelope))
					end
					em.Transparency = NumberSequence.new(keys)
					task.wait()
				end
				if em.Parent then
					em.Enabled = false
				end
			end)
		end)
	end
	task.delay(duration + 0.55, function()
		if root.Parent then
			root:Destroy()
		end
	end)
end

local function fadeInVisual(root: Instance, duration: number)
	local fade = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local function prepare(inst: Instance)
		if inst:IsA("BasePart") or inst:IsA("Decal") or inst:IsA("Texture") then
			local orig = inst.Transparency
			inst:SetAttribute("IwFadeOrigT", orig)
			inst.Transparency = 1
			TweenService:Create(inst, fade, { Transparency = orig }):Play()
		elseif inst:IsA("PointLight") or inst:IsA("SpotLight") or inst:IsA("SurfaceLight") then
			local origB = inst.Brightness
			inst:SetAttribute("IwFadeOrigB", origB)
			inst.Brightness = 0
			TweenService:Create(inst, fade, { Brightness = origB }):Play()
		end
	end
	prepare(root)
	for _, desc in root:GetDescendants() do
		prepare(desc)
	end
	setIdleShieldParticles(root, true)
end

local function destroyShieldUi(gui: BillboardGui?)
	if gui and gui.Parent then
		gui:Destroy()
	end
end

local function updateShieldUi(hpLabel: TextLabel?, hpFill: Frame?, hp: number, maxHp: number)
	if hpLabel then
		hpLabel.Text = string.format("%d/%d", math.max(0, math.ceil(hp)), maxHp)
	end
	if hpFill then
		local ratio = if maxHp > 0 then math.clamp(hp / maxHp, 0, 1) else 0
		TweenService:Create(hpFill, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.new(ratio, 0, 1, 0),
		}):Play()
	end
end

local function createShieldHpBillboard(adornee: BasePart, maxHp: number, compact: boolean?): (BillboardGui, TextLabel, Frame)
	local character = adornee:FindFirstAncestorOfClass("Model")
	local head: BasePart? = nil
	if character and character:FindFirstChildOfClass("Humanoid") then
		local found = character:FindFirstChild("Head")
		if found and found:IsA("BasePart") then
			head = found
		end
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "ShieldHealthGui"
	gui.Size = if compact then GameConstants.SHIELD_UI_SIZE_COMPACT else GameConstants.SHIELD_UI_SIZE
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = GameConstants.NAMEPLATE_MAX_DISTANCE
	if head and character then
		gui.Adornee = head
		gui.StudsOffset = if compact then GameConstants.SHIELD_UI_OFFSET_COMPACT else GameConstants.SHIELD_UI_OFFSET
		gui.Parent = character
	else
		gui.Adornee = adornee
		gui.StudsOffset = Vector3.new(0, if compact then 3.4 else 4.2, 0)
		gui.Parent = adornee.Parent or adornee
	end

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
	fill.BackgroundColor3 = GameConstants.IW_COLOR
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
	hpLabel.Text = string.format("%d/%d", maxHp, maxHp)
	hpLabel.TextColor3 = Color3.fromRGB(245, 245, 248)
	hpLabel.TextScaled = true
	hpLabel.TextStrokeTransparency = 0.35
	hpLabel.ZIndex = 2
	hpLabel.Parent = track

	local textConstraint = Instance.new("UITextSizeConstraint")
	textConstraint.MaxTextSize = if compact then 14 else 18
	textConstraint.MinTextSize = 7
	textConstraint.Parent = hpLabel

	return gui, hpLabel, fill
end

local function setInstanceHidden(inst: Instance, hidden: boolean)
	if inst:IsA("BillboardGui") then
		inst.Enabled = not hidden
		return
	end
	local function hide(obj: Instance)
		if obj:IsA("BasePart") then
			if hidden then
				if obj:GetAttribute("IwVisT") == nil then
					obj:SetAttribute("IwVisT", obj.Transparency)
				end
				obj.Transparency = 1
			else
				local saved = obj:GetAttribute("IwVisT")
				if type(saved) == "number" then
					obj.Transparency = saved
				end
				obj:SetAttribute("IwVisT", nil)
			end
		elseif obj:IsA("Beam") or obj:IsA("Trail") then
			obj.Enabled = not hidden
		elseif obj:IsA("ParticleEmitter") then
			obj.Enabled = if hidden then false else obj.Name ~= "1"
		elseif obj:IsA("BillboardGui") then
			obj.Enabled = not hidden
		end
	end
	hide(inst)
	for _, desc in inst:GetDescendants() do
		hide(desc)
	end
end

local function restoreFlightFx(character: Model)
	local flight = flightFxByCharacter[character]
	if not flight then
		return
	end
	if flight.billboard then
		flight.billboard.Enabled = true
	end
	for _, inst in flight.instances do
		if not inst.Parent then
			continue
		end
		local function restore(em: ParticleEmitter)
			local orig = em:GetAttribute("IwOrigRate")
			if type(orig) == "number" then
				em.Rate = orig
			end
			em.Enabled = em.Name ~= "1"
		end
		if inst:IsA("ParticleEmitter") then
			restore(inst)
		end
		for _, desc in inst:GetDescendants() do
			if desc:IsA("ParticleEmitter") then
				restore(desc)
			end
		end
		if inst:IsA("BasePart") then
			local saved = inst:GetAttribute("IwVisT")
			if type(saved) == "number" then
				inst.Transparency = saved
				inst:SetAttribute("IwVisT", nil)
			end
		end
	end
end

local function isBaseInvisibleWoman(character: Model): boolean
	return character:GetAttribute(GameConstants.LOOK_MODE_ATTRIBUTE) ~= "modern"
end

local function setDefenceHidden(character: Model, hidden: boolean)
	local player = Players:GetPlayerFromCharacter(character)
	local hideQShield = hidden and not isBaseInvisibleWoman(character)
	local hideFlightShield = hidden and not isBaseInvisibleWoman(character)
	if player then
		local shield = shieldByPlayer[player]
		if shield then
			if shield.billboard then
				shield.billboard.Enabled = not hidden
			end
			if shield.forcefield.Parent then
				setInstanceHidden(shield.forcefield, hideQShield)
			end
		end
	end
	local flight = flightFxByCharacter[character]
	if flight then
		if flight.billboard then
			flight.billboard.Enabled = not hideFlightShield
		end
		for _, inst in flight.instances do
			if inst.Parent then
				setInstanceHidden(inst, hideFlightShield)
			end
		end
	end
	local gui = character:FindFirstChild("ShieldHealthGui", true)
	if gui and gui:IsA("BillboardGui") then
		local keepFlightUi = isBaseInvisibleWoman(character) and flight ~= nil and gui == flight.billboard
		gui.Enabled = if keepFlightUi then true else not hidden
	end
end

local function hideHandVfx(character: Model)
	local fx = powerFxByCharacter[character]
	if not fx then
		return
	end
	for _, inst in fx.instances do
		if inst.Parent then
			fadeParticles(inst, false)
			task.delay(0.2, function()
				if inst.Parent then
					inst:Destroy()
				end
			end)
		end
	end
	fx.instances = {}
end

local function isFlightFxInst(character: Model, inst: Instance): boolean
	if inst.Name == "IwFlightForcefield" or inst:FindFirstAncestor("IwFlightForcefield") ~= nil then
		return true
	end
	local flight = flightFxByCharacter[character]
	if not flight then
		return false
	end
	if flight.billboard and (inst == flight.billboard or inst:IsDescendantOf(flight.billboard)) then
		return true
	end
	for _, fx in flight.instances do
		if inst == fx or inst:IsDescendantOf(fx) or (fx:IsDescendantOf(inst) and inst:IsDescendantOf(character)) then
			return true
		end
	end
	return false
end

local function lockHumanoidMotion(hum: Humanoid)
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

local function unlockHumanoidMotion(hum: Humanoid, walk: number, jumpPower: number?, jumpHeight: number?)
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

local function restoreMove(character: Model, walk: number, jumpPower: number?, jumpHeight: number?, autoRotate: boolean?)
	local hum = CombatHelper.getHumanoid(character)
	if hum then
		unlockHumanoidMotion(hum, walk, jumpPower, jumpHeight)
		if autoRotate ~= nil then
			hum.AutoRotate = autoRotate
		end
	end
end

local function freezeCasterInPlace(character: Model, _holdPos: Vector3)
	local hum = CombatHelper.getHumanoid(character)
	if hum then
		lockHumanoidMotion(hum)
		hum.AutoRotate = false
		hum:Move(Vector3.zero, false)
	end
end

local function captureAndLockMove(character: Model): (number, number?, number?)
	local hum = CombatHelper.getHumanoid(character)
	local walk = GameConstants.DEFAULT_WALK_SPEED
	local jumpPower: number? = nil
	local jumpHeight: number? = nil
	if hum then
		walk = hum.WalkSpeed
		jumpPower = hum.JumpPower
		pcall(function()
			jumpHeight = hum.JumpHeight
		end)
		lockHumanoidMotion(hum)
	end
	return walk, jumpPower, jumpHeight
end

local function isHumanoidPart(part: BasePart): boolean
	if CombatHelper.getCharacterFromPart(part) then
		return true
	end
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		if model:FindFirstChildOfClass("Humanoid") then
			return true
		end
		local parent = model.Parent
		if not parent then
			break
		end
		model = parent:FindFirstAncestorOfClass("Model")
	end
	return false
end

local function worldYOf(inst: Instance): number
	if inst:IsA("BasePart") then
		return inst.Position.Y
	end
	local parent = inst.Parent
	if parent and parent:IsA("BasePart") then
		return parent.Position.Y
	end
	return 0
end

local function retireFx(inst: Instance, fadeWait: number, deleteWait: number)
	task.delay(fadeWait, function()
		if inst.Parent then
			fadeParticles(inst, false)
		end
	end)
	task.delay(fadeWait + deleteWait, function()
		if inst.Parent then
			inst:Destroy()
		end
	end)
end

local function weldVisual(inst: Instance, root: BasePart)
	local function prep(part: BasePart)
		part.Anchored = false
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
	end
	if inst:IsA("BasePart") then
		prep(inst)
		inst.CFrame = root.CFrame
		inst.Parent = root.Parent
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = inst
		weld.Parent = inst
		return
	end
	inst.Parent = root.Parent
	if inst:IsA("Model") then
		inst:PivotTo(root.CFrame)
	end
	local primary = if inst:IsA("Model")
		then (inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true))
		else inst:FindFirstChildWhichIsA("BasePart", true)
	if primary and primary:IsA("BasePart") then
		for _, desc in inst:GetDescendants() do
			if desc:IsA("BasePart") then
				prep(desc)
			end
		end
		prep(primary)
		primary.CFrame = root.CFrame
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = primary
		weld.Parent = primary
	end
end

local function spawnHandVfx(character: Model): { Instance }
	local instances: { Instance } = {}
	local template = VfxHelper.getInvisibleWomanAsset("HandVFXAttachment")
	local right = getHand(character, true)
	local left = getHand(character, false)
	local function attach(hand: BasePart?)
		if not hand or not template then
			return
		end
		local fx = template:Clone()
		if fx:IsA("Attachment") then
			fx.Position = Vector3.zero
			fx.Orientation = Vector3.zero
		end
		fx.Parent = hand
		fadeParticles(fx, true)
		table.insert(instances, fx)
	end
	attach(right)
	if left and left ~= right then
		attach(left)
	end
	return instances
end

local function isPowerFxInst(character: Model, inst: Instance): boolean
	local fx = powerFxByCharacter[character]
	if not fx then
		return false
	end
	for _, handFx in fx.instances do
		if inst == handFx or inst:IsDescendantOf(handFx) then
			return true
		end
	end
	return false
end

local function beginPowerFx(character: Model, allowDuringInvis: boolean?)
	local invisible = character:GetAttribute(GameConstants.IW_INVIS_ATTRIBUTE) == true
	local skipHands = invisible and allowDuringInvis ~= true
	local existing = powerFxByCharacter[character]
	if existing then
		existing.refs += 1
		if not skipHands and #existing.instances == 0 then
			existing.instances = spawnHandVfx(character)
		end
		return
	end
	if skipHands then
		powerFxByCharacter[character] = { instances = {}, refs = 1 }
		return
	end
	powerFxByCharacter[character] = { instances = spawnHandVfx(character), refs = 1 }
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
	for _, inst in fx.instances do
		if inst.Parent then
			fadeParticles(inst, false)
			task.delay(GameConstants.IW_HAND_FADE + 2.5, function()
				if inst.Parent then
					inst:Destroy()
				end
			end)
		end
	end
end

local function clearPowerFx(character: Model)
	local fx = powerFxByCharacter[character]
	if not fx then
		return
	end
	powerFxByCharacter[character] = nil
	for _, inst in fx.instances do
		if inst.Parent then
			fadeParticles(inst, false)
			task.delay(2, function()
				if inst.Parent then
					inst:Destroy()
				end
			end)
		end
	end
end

local function snapshotStealthVisuals(character: Model): { { inst: Instance, t: number, enabled: boolean? } }
	local saved: { { inst: Instance, t: number, enabled: boolean? } } = {}
	local function remember(inst: Instance)
		if inst.Name == "HumanoidRootPart" then
			return
		end
		if inst:IsA("BasePart") or inst:IsA("Decal") or inst:IsA("Texture") then
			table.insert(saved, { inst = inst, t = inst.Transparency })
		elseif inst:IsA("ParticleEmitter") or inst:IsA("Beam") or inst:IsA("Trail") then
			table.insert(saved, { inst = inst, t = 1, enabled = inst.Enabled })
		end
	end
	for _, desc in character:GetDescendants() do
		remember(desc)
	end
	return saved
end

local function fadeStealthVisuals(saved: { { inst: Instance, t: number, enabled: boolean? } }, hidden: boolean)
	local info = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, rec in saved do
		if not rec.inst.Parent then
			continue
		end
		if rec.inst:IsA("BasePart") or rec.inst:IsA("Decal") or rec.inst:IsA("Texture") then
			local target = if hidden then 1 else rec.t
			TweenService:Create(rec.inst, info, { Transparency = target }):Play()
		elseif rec.inst:IsA("ParticleEmitter") or rec.inst:IsA("Beam") or rec.inst:IsA("Trail") then
			rec.inst.Enabled = if hidden then false else rec.enabled == true
		end
	end
end

local function stealthTransparencyOf(character: Model, inst: Instance, fallback: number): number
	local flight = flightFxByCharacter[character]
	if flight and flight.stealthSaved then
		for _, rec in flight.stealthSaved do
			if rec.inst == inst then
				return rec.t
			end
		end
	end
	return fallback
end

local function beginFlightFx(character: Model)
	if flightFxByCharacter[character] then
		return
	end
	beginPowerFx(character)
	local instances: { Instance } = {}
	local modern = character:GetAttribute(GameConstants.LOOK_MODE_ATTRIBUTE) == "modern"
	local maxHp = if modern then GameConstants.IW_FLIGHT_SHIELD_HP_MODERN else GameConstants.IW_FLIGHT_SHIELD_HP
	local stealthSaved: { { inst: Instance, t: number, enabled: boolean? } }? = nil
	if modern then
		local em1 = VfxHelper.getInvisibleWomanAsset("ForcefieldFlight", "ParticleEmitter1")
		local em2 = VfxHelper.getInvisibleWomanAsset("ForcefieldFlight", "ParticleEmitter2")
		for _, child in character:GetChildren() do
			if child:IsA("BasePart") then
				if em1 then
					local a = em1:Clone()
					a.Parent = child
					if a:IsA("ParticleEmitter") then
						a:SetAttribute("IwOrigRate", a.Rate)
						a.Enabled = character:GetAttribute(GameConstants.IW_INVIS_ATTRIBUTE) ~= true
					end
					table.insert(instances, a)
				end
				if em2 then
					local b = em2:Clone()
					b.Parent = child
					if b:IsA("ParticleEmitter") then
						b:SetAttribute("IwOrigRate", b.Rate)
						b.Enabled = character:GetAttribute(GameConstants.IW_INVIS_ATTRIBUTE) ~= true
					end
					table.insert(instances, b)
				end
			end
		end
	else
		local root = getRoot(character)
		local shieldTemplate = VfxHelper.getInvisibleWomanAsset("ForcefieldFlight", "FlightForcefield")
		if shieldTemplate and root then
			local shield = shieldTemplate:Clone()
			shield.Name = "IwFlightForcefield"
			weldVisual(shield, root)
			setIdleShieldParticles(shield, true)
			table.insert(instances, shield)
		end
	end
	local root = getRoot(character)
	character:SetAttribute(GameConstants.IW_FLIGHT_SHIELD_ATTRIBUTE, true)
	character:SetAttribute(GameConstants.SHIELD_ACTIVE_ATTRIBUTE, true)
	character:SetAttribute(GameConstants.SHIELD_HP_ATTRIBUTE, maxHp)
	AbilityCooldownHelper.setActive(character, "forcefield_flight", true)
	local billboard: BillboardGui? = nil
	local hpLabel: TextLabel? = nil
	local hpFill: Frame? = nil
	if root and not shieldByPlayer[Players:GetPlayerFromCharacter(character) :: Player] then
		billboard, hpLabel, hpFill = createShieldHpBillboard(root, maxHp, true)
	end
	flightFxByCharacter[character] = {
		instances = instances,
		hp = maxHp,
		maxHp = maxHp,
		billboard = billboard,
		hpLabel = hpLabel,
		hpFill = hpFill,
		stealthSaved = stealthSaved,
	}
	if character:GetAttribute(GameConstants.IW_INVIS_ATTRIBUTE) == true then
		setDefenceHidden(character, true)
	end
end

local function endFlightFx(character: Model)
	local fx = flightFxByCharacter[character]
	if not fx then
		return
	end
	flightFxByCharacter[character] = nil
	character:SetAttribute(GameConstants.IW_FLIGHT_SHIELD_ATTRIBUTE, nil)
	if character:GetAttribute(GameConstants.IW_FORCEFIELD_ATTRIBUTE) ~= true then
		character:SetAttribute(GameConstants.SHIELD_ACTIVE_ATTRIBUTE, nil)
		character:SetAttribute(GameConstants.SHIELD_HP_ATTRIBUTE, nil)
	end
	AbilityCooldownHelper.setActive(character, "forcefield_flight", false)
	destroyShieldUi(fx.billboard)
	if fx.stealthSaved and character:GetAttribute(GameConstants.IW_INVIS_ATTRIBUTE) ~= true then
		fadeStealthVisuals(fx.stealthSaved, false)
		pcall(function()
			NameplateService.setHidden(character, false, 0.22)
		end)
	end
	for _, inst in fx.instances do
		if inst.Parent then
			if inst.Name == "IwFlightForcefield" then
				setBreakBurst(inst, false)
				fadeOutVisual(inst, 0.4)
			else
				VfxHelper.smoothDisableParticles(inst, 1.05)
				fadeParticles(inst, false)
				task.delay(2.15, function()
					if inst.Parent then
						inst:Destroy()
					end
				end)
			end
		end
	end
	endPowerFx(character)
end

local function spawnShieldImpact(character: Model, hitFrom: Vector3?)
	local template = VfxHelper.getInvisibleWomanAsset("Forcefield", "ShieldImpactAttachment")
	local root = getRoot(character)
	if not template or not root then
		return
	end
	local pos = hitFrom or root.Position
	local host = Instance.new("Part")
	host.Name = "IwShieldImpact"
	host.Anchored = true
	host.CanCollide = false
	host.CanQuery = false
	host.CanTouch = false
	host.Transparency = 1
	host.Size = Vector3.new(0.2, 0.2, 0.2)
	host.CFrame = CFrame.new(pos)
	host.Parent = Workspace
	local fx = template:Clone()
	if fx:IsA("Attachment") then
		fx.Parent = host
	else
		fx.Parent = host
	end
	fadeParticles(fx, true)
	VfxHelper.emitAllParticles(fx, 10)
	task.delay(0.08, function()
		if fx.Parent then
			fadeParticles(fx, false)
		end
	end)
	task.delay(GameConstants.IW_FORCEFIELD_IMPACT_LIFE, function()
		if host.Parent then
			host:Destroy()
		end
	end)
end

local function stopForcefield(player: Player, applyCooldown: boolean, broken: boolean?)
	local state = shieldByPlayer[player]
	if not state then
		return
	end
	shieldByPlayer[player] = nil
	if state.healthConn then
		state.healthConn:Disconnect()
	end
	destroyShieldUi(state.billboard)
	stopTrack(state.animTrack)
	local character = state.character
	character:SetAttribute(GameConstants.IW_FORCEFIELD_ATTRIBUTE, nil)
	if character:GetAttribute(GameConstants.IW_FLIGHT_SHIELD_ATTRIBUTE) ~= true then
		character:SetAttribute(GameConstants.SHIELD_ACTIVE_ATTRIBUTE, nil)
		character:SetAttribute(GameConstants.SHIELD_HP_ATTRIBUTE, nil)
	end
	local hum = CombatHelper.getHumanoid(character)
	if hum and state.lockWalk then
		hum.WalkSpeed = state.walk
		if state.jumpPower then
			hum.JumpPower = state.jumpPower
		end
		if state.jumpHeight then
			hum.JumpHeight = state.jumpHeight
		end
	end
	if state.forcefield.Parent then
		if broken then
			setIdleShieldParticles(state.forcefield, false)
			setBreakBurst(state.forcefield, true)
			task.delay(1, function()
				if state.forcefield.Parent then
					VfxHelper.smoothDisableParticles(state.forcefield, 0.5)
				end
			end)
		else
			setBreakBurst(state.forcefield, false)
			setIdleShieldParticles(state.forcefield, false)
			fadeOutVisual(state.forcefield, 0.4)
		end
	end
	endPowerFx(character)
	local flightFx = flightFxByCharacter[character]
	if flightFx and character:GetAttribute(GameConstants.IW_FLIGHT_SHIELD_ATTRIBUTE) == true then
		character:SetAttribute(GameConstants.SHIELD_HP_ATTRIBUTE, math.max(0, flightFx.hp))
		local root = getRoot(character)
		if root and not flightFx.billboard then
			local gui, label, fill = createShieldHpBillboard(root, flightFx.maxHp, true)
			flightFx.billboard = gui
			flightFx.hpLabel = label
			flightFx.hpFill = fill
			updateShieldUi(label, fill, flightFx.hp, flightFx.maxHp)
		end
	end
	if applyCooldown and not state.fromProtect then
		finishAbility(character, "iw_forcefield", GameConstants.IW_FORCEFIELD_COOLDOWN)
	else
		AbilityCooldownHelper.setActive(character, "iw_forcefield", false)
	end
end

local function startForcefield(player: Player, fromProtect: boolean?)
	local character = player.Character
	if not character then
		return
	end
	if shieldByPlayer[player] then
		if fromProtect then
			stopForcefield(player, false)
		else
			return
		end
	end
	local entry = CharacterRegistry.getAbilityById(HERO, "iw_forcefield")
	if not fromProtect then
		if not entry or not canUse(character, entry.id, 0) then
			return
		end
	end
	local root = getRoot(character)
	local template = VfxHelper.getInvisibleWomanAsset("Forcefield", "Forcefield")
	if not root or not template then
		return
	end
	if not fromProtect and entry then
		AbilityCooldownHelper.setActive(character, entry.id, true)
	end
	beginPowerFx(character)
	fireCameraShake(player, 0.38, 0.34, 0.26, 0.5)
	local ff = template:Clone()
	ff.Name = "IwForcefield"
	weldVisual(ff, root)
	setIdleShieldParticles(ff, true)
	local maxHp = if fromProtect then GameConstants.IW_PROTECT_SHIELD_HP else GameConstants.IW_FORCEFIELD_HP
	if not fromProtect and character:GetAttribute(GameConstants.LOOK_MODE_ATTRIBUTE) == "modern" then
		maxHp = GameConstants.IW_FORCEFIELD_HP_MODERN
	end
	character:SetAttribute(GameConstants.SHIELD_ACTIVE_ATTRIBUTE, true)
	character:SetAttribute(GameConstants.IW_FORCEFIELD_ATTRIBUTE, true)
	character:SetAttribute(GameConstants.SHIELD_HP_ATTRIBUTE, maxHp)
	local hum = CombatHelper.getHumanoid(character)
	local savedWalk = GameConstants.DEFAULT_WALK_SPEED
	local savedJumpPower: number? = nil
	local savedJumpHeight: number? = nil
	local lockWalk = fromProtect ~= true
	if hum and lockWalk then
		savedWalk = hum.WalkSpeed
		if hum.UseJumpPower then
			savedJumpPower = hum.JumpPower
			hum.JumpPower = 0
		else
			savedJumpHeight = hum.JumpHeight
			hum.JumpHeight = 0
		end
		hum.WalkSpeed = GameConstants.IW_FORCEFIELD_WALK_SPEED
	end
	local flightFx = flightFxByCharacter[character]
	if flightFx then
		destroyShieldUi(flightFx.billboard)
		flightFx.billboard = nil
		flightFx.hpLabel = nil
		flightFx.hpFill = nil
	end
	local billboard, hpLabel, hpFill = createShieldHpBillboard(root, maxHp, true)
	local state: ShieldState = {
		character = character,
		hp = maxHp,
		maxHp = maxHp,
		forcefield = ff,
		walk = savedWalk,
		jumpPower = savedJumpPower,
		jumpHeight = savedJumpHeight,
		healthConn = nil,
		lastHealth = if hum then hum.Health else 100,
		billboard = billboard,
		hpLabel = hpLabel,
		hpFill = hpFill,
		lockWalk = lockWalk,
		fromProtect = fromProtect == true,
		animTrack = playCharacterAnim(character, GameConstants.IW_FORCEFIELD_ANIM, true, Enum.AnimationPriority.Action),
	}
	shieldByPlayer[player] = state
	if hum then
		state.healthConn = hum.HealthChanged:Connect(function(hp)
			local live = shieldByPlayer[player]
			if not live or live ~= state then
				return
			end
			if hp >= live.lastHealth then
				live.lastHealth = hp
				return
			end
			if hp <= 0 then
				return
			end
			local lost = live.lastHealth - hp
			hum.Health = live.lastHealth
			InvisibleWomanService.absorbShield(character, lost, nil)
		end)
	end
	if character:GetAttribute(GameConstants.IW_INVIS_ATTRIBUTE) == true then
		setDefenceHidden(character, true)
	end
end

local function isValidVictim(model: Model?, caster: Model): boolean
	if not model or model == caster or not model.Parent then
		return false
	end
	local hum = CombatHelper.getHumanoid(model)
	return hum ~= nil and hum.Health > 0 and CombatHelper.isCombatEligible(model)
end

local function resolveTarget(
	caster: Model,
	root: BasePart,
	target: Model?,
	direction: Vector3?,
	aimPoint: Vector3?,
	range: number,
	lockOn: boolean?
): Model?
	if isValidVictim(target, caster) then
		local tRoot = getRoot(target :: Model)
		if tRoot and (tRoot.Position - root.Position).Magnitude <= range then
			return target
		end
	end
	if lockOn ~= true then
		return nil
	end
	if aimPoint then
		local best: Model? = nil
		local bestD = AIM_POINT_RADIUS
		for _, model in CombatHelper.overlapCharacters(aimPoint, AIM_POINT_RADIUS, caster) do
			if not isValidVictim(model, caster) then
				continue
			end
			local tRoot = getRoot(model)
			if not tRoot then
				continue
			end
			local d = (tRoot.Position - aimPoint).Magnitude
			if d < bestD then
				bestD = d
				best = model
			end
		end
		if best then
			return best
		end
	end
	local aimDir = if direction and direction.Magnitude > 0.05
		then direction.Unit
		elseif aimPoint
		then normalizeDir(aimPoint - root.Position)
		else root.CFrame.LookVector
	return CombatHelper.raycastCharacter(root.Position, aimDir, range, caster)
end

local function liveAim(character: Model, fallback: Vector3?): Vector3?
	local attr = character:GetAttribute(GameConstants.IW_AIM_ATTRIBUTE)
	if typeof(attr) == "Vector3" then
		return attr
	end
	return fallback
end

local function spawnDiscImpact(pos: Vector3)
	playWorldSound(GameConstants.IW_DISC_HIT_SOUND, pos, 0.95)
	VfxHelper.spawnInvisibleWomanDiscImpact(pos)
end

local function returnDiscToCaster(visual: Instance, caster: Model, fromPos: Vector3)
	task.spawn(function()
		local pos = fromPos
		local speed = GameConstants.IW_DISC_SPEED * 0.9
		local fading = false
		local fadeDist = 6.2
		local removeDist = 3.2
		local fadeInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		while visual.Parent and caster.Parent do
			local root = getRoot(caster)
			if not root then
				break
			end
			local dest = root.Position + Vector3.new(0, 1.15, 0)
			local delta = dest - pos
			local dist = delta.Magnitude
			if dist <= removeDist then
				if visual.Parent then
					visual:Destroy()
				end
				return
			end
			if not fading and dist <= fadeDist then
				fading = true
				local function fadeInst(inst: Instance)
					if inst:IsA("BasePart") or inst:IsA("Decal") or inst:IsA("Texture") then
						TweenService:Create(inst, fadeInfo, { Transparency = 1 }):Play()
					end
				end
				fadeInst(visual)
				for _, desc in visual:GetDescendants() do
					fadeInst(desc)
				end
				VfxHelper.smoothDisableParticles(visual, 0.18)
			end
			local dt = task.wait()
			local step = speed * math.max(dt, 0.016)
			if dist > 0.05 then
				pos += delta.Unit * math.min(step, dist)
				local look = delta.Unit
				local cf = CFrame.lookAt(pos, pos + look)
				if visual:IsA("Model") then
					visual:PivotTo(cf)
				elseif visual:IsA("BasePart") then
					visual.CFrame = cf
				end
			end
		end
		if visual.Parent then
			visual:Destroy()
		end
	end)
end

local function castDisc(player: Player, direction: Vector3?, aimPoint: Vector3?)
	local character = player.Character
	if not character then
		return
	end
	local entry = CharacterRegistry.getAbilityById(HERO, "disc_throw")
	if not entry or not canUse(character, entry.id, GameConstants.IW_DISC_ENERGY) then
		return
	end
	local root = getRoot(character)
	local template = VfxHelper.getInvisibleWomanAsset("DiscThrow", "Bolt")
	if not root or not template then
		return
	end
	AbilityCooldownHelper.setActive(character, entry.id, true)
	beginPowerFx(character)
	fireCameraShake(player, 0.4, 0.26, 0.3, 0.5)
	if aimPoint then
		character:SetAttribute(GameConstants.IW_AIM_ATTRIBUTE, aimPoint)
		faceToward(character, aimPoint, 0.34)
	elseif direction and direction.Magnitude > 0.05 then
		faceToward(character, root.Position + direction.Unit * 40, 0.34)
	end
	local useRight = discSideByPlayer[player] == true
	discSideByPlayer[player] = not useRight
	playCharacterAnim(
		character,
		if useRight then GameConstants.IW_DISC_RIGHT_ANIM else GameConstants.IW_DISC_LEFT_ANIM,
		false,
		Enum.AnimationPriority.Action
	)
	task.delay(0.1, function()
		if not character.Parent or not AbilityCooldownHelper.isActive(character, entry.id) then
			return
		end
		local liveRoot = getRoot(character)
		if not liveRoot then
			if character.Parent then
				endPowerFx(character)
				AbilityCooldownHelper.setActive(character, entry.id, false)
			end
			return
		end
		local hand = getHand(character, useRight)
		local origin = if hand
			then hand.Position + liveRoot.CFrame.LookVector * 0.35
			else liveRoot.Position + liveRoot.CFrame.LookVector * 2 + Vector3.new(0, 1.2, 0)
		local liveAim = character:GetAttribute(GameConstants.IW_AIM_ATTRIBUTE)
		local dir = if typeof(liveAim) == "Vector3"
			then normalizeDir(liveAim - origin)
			elseif aimPoint then normalizeDir(aimPoint - origin)
			else normalizeDir(direction or liveRoot.CFrame.LookVector)
		local bolt = template:Clone()
		if bolt:IsA("BasePart") then
			bolt.CFrame = CFrame.lookAt(origin, origin + dir)
			bolt.Anchored = true
			bolt.CanCollide = false
			bolt.Parent = Workspace
			fadeParticles(bolt, true)
		elseif bolt:IsA("Model") then
			bolt:PivotTo(CFrame.lookAt(origin, origin + dir))
			bolt.Parent = Workspace
			fadeParticles(bolt, true)
		end
		playWorldSound(GameConstants.IW_DISC_RELEASE_SOUND, origin, 0.9)
		ProjectileHelper.spawn(origin, dir, {
			speed = GameConstants.IW_DISC_SPEED,
			damage = GameConstants.IW_DISC_DAMAGE,
			radius = GameConstants.IW_DISC_HIT_RADIUS,
			maxDistance = GameConstants.IW_DISC_RANGE,
			owner = character,
			customVisual = bolt,
			impactFx = "none",
			keepVisual = true,
			impactOnCharacter = true,
			onImpact = function(pos: Vector3)
				spawnDiscImpact(pos)
				if bolt.Parent then
					returnDiscToCaster(bolt, character, pos)
				end
			end,
		})
		task.delay(0.2, function()
			if character.Parent then
				endPowerFx(character)
				if AbilityCooldownHelper.isActive(character, entry.id) then
					finishAbility(character, entry.id, GameConstants.IW_DISC_COOLDOWN)
				end
			end
		end)
	end)
end

local function destroyPush(player: Player)
	local state = pushByPlayer[player]
	if not state then
		return
	end
	pushByPlayer[player] = nil
	state.alive = false
	if not state.launched then
		restoreMove(state.owner, state.walk, state.jumpPower, state.jumpHeight, state.autoRotate)
		if state.owner.Parent then
			state.owner:SetAttribute(GameConstants.BUSY_ATTRIBUTE, nil)
		end
	end
	if state.visual.Parent then
		fadeOutVisual(state.visual, GameConstants.IW_PUSH_FADE)
	end
end

local function castPush(player: Player, direction: Vector3?, aimPoint: Vector3?)
	local character = player.Character
	if not character or pushByPlayer[player] then
		return
	end
	local entry = CharacterRegistry.getAbilityById(HERO, "forcefield_push")
	if not entry or not canUse(character, entry.id, GameConstants.IW_PUSH_ENERGY) then
		return
	end
	local root = getRoot(character)
	local template = VfxHelper.getInvisibleWomanAsset("ForcefieldPush", "ForcefieldPush")
	if not root or not template then
		return
	end
	AbilityCooldownHelper.setActive(character, entry.id, true)
	character:SetAttribute(GameConstants.BUSY_ATTRIBUTE, true)
	beginPowerFx(character)
	playCharacterAnim(character, GameConstants.IW_PUSH_ANIM, false, Enum.AnimationPriority.Action)
	fireCameraShake(player, 0.52, 0.4, 0.38, 0.62)
	if aimPoint then
		character:SetAttribute(GameConstants.IW_AIM_ATTRIBUTE, aimPoint)
	end
	local flatLook = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	local dir = if flatLook.Magnitude > 0.05 then flatLook.Unit else Vector3.new(0, 0, -1)
	local origin = root.Position + Vector3.new(0, 1.2, 0) + dir * 2.2
	local clone = template:Clone()
	local part: BasePart?
	if clone:IsA("BasePart") then
		part = clone
		clone.CFrame = CFrame.lookAt(origin, origin + dir)
		clone.Anchored = true
		clone.CanCollide = false
		clone.CanQuery = true
		clone.CanTouch = true
		clone.Parent = Workspace
	elseif clone:IsA("Model") then
		clone:PivotTo(CFrame.lookAt(origin, origin + dir))
		clone.Parent = Workspace
		part = clone.PrimaryPart or clone:FindFirstChildWhichIsA("BasePart", true)
		if part then
			part.Anchored = true
			part.CanCollide = false
		end
	end
	if not part then
		clone:Destroy()
		endPowerFx(character)
		AbilityCooldownHelper.setActive(character, entry.id, false)
		return
	end
	fadeParticles(clone, true)
	fireCameraShake(player, 0.38, 0.28, 0.28, 0.45)
	local walk, jumpPower, jumpHeight = captureAndLockMove(character)
	local hum = CombatHelper.getHumanoid(character)
	local autoRotate = if hum then hum.AutoRotate else true
	if hum then
		hum.AutoRotate = false
	end
	pushByPlayer[player] = {
		part = part,
		visual = clone,
		owner = character,
		hit = {},
		alive = true,
		launched = false,
		launchAt = os.clock() + GameConstants.IW_PUSH_WINDUP,
		dir = dir,
		bornAt = os.clock(),
		casterHoldPos = root.Position,
		walk = walk,
		jumpPower = jumpPower,
		jumpHeight = jumpHeight,
		autoRotate = autoRotate,
	}
	task.delay(0.25, function()
		if character.Parent then
			endPowerFx(character)
			if AbilityCooldownHelper.isActive(character, entry.id) then
				finishAbility(character, entry.id, GameConstants.IW_PUSH_COOLDOWN)
			end
		end
	end)
end

local function attachInvisMorphFx(character: Model): { Instance }
	local copied: { Instance } = {}
	local morph = VfxHelper.getInvisibleWomanAsset("InvisibilityMorph")
	if not morph then
		return copied
	end
	for _, src in morph:GetChildren() do
		if src:IsA("BasePart") then
			local dest = character:FindFirstChild(src.Name)
			if dest and dest:IsA("BasePart") then
				for _, child in src:GetChildren() do
					if child:IsA("Attachment") or child:IsA("ParticleEmitter") then
						local clone = child:Clone()
						clone.Name = "IwInvisFx"
						clone.Parent = dest
						table.insert(copied, clone)
					end
				end
			end
		end
	end
	return copied
end

local function restoreInvis(player: Player, character: Model?)
	local state = invisByPlayer[player]
	if not state then
		return
	end
	invisByPlayer[player] = nil
	local char = character or state.character
	local token = (invisToken[player] or 0) + 1
	invisToken[player] = token
	char:SetAttribute(GameConstants.IW_INVIS_ATTRIBUTE, nil)
	local charRoot = getRoot(char)
	if charRoot then
		playWorldSound(GameConstants.IW_INVIS_OFF_SOUND, charRoot.Position, 0.9)
	end
	pcall(function()
		NameplateService.setHidden(char, false, GameConstants.IW_INVIS_FADE)
	end)
	for _, fx in state.fx do
		if fx.Parent then
			fx:Destroy()
		end
	end
	local copied = attachInvisMorphFx(char)
	for _, fx in copied do
		fadeParticles(fx, true)
		VfxHelper.emitAllParticles(fx, 6)
	end
	local fadeTime = GameConstants.IW_INVIS_FADE
	local sweep = GameConstants.IW_INVIS_SWEEP
	local minY, maxY = math.huge, -math.huge
	for _, rec in state.saved do
		if rec.inst.Parent then
			local y = worldYOf(rec.inst)
			if y < minY then
				minY = y
			end
			if y > maxY then
				maxY = y
			end
		end
	end
	local span = math.max(0.2, maxY - minY)
	for _, rec in state.saved do
		if rec.inst.Parent and (rec.inst:IsA("BasePart") or rec.inst:IsA("Decal") or rec.inst:IsA("Texture")) then
			local y = worldYOf(rec.inst)
			local delay = ((maxY - y) / span) * sweep
			task.delay(delay, function()
				if invisToken[player] ~= token or not rec.inst.Parent then
					return
				end
				if isFlightFxInst(char, rec.inst) then
					return
				end
				TweenService:Create(
					rec.inst,
					TweenInfo.new(fadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ Transparency = rec.t }
				):Play()
			end)
		end
	end
	task.delay(sweep + fadeTime, function()
		if invisToken[player] ~= token then
			return
		end
		for _, fx in copied do
			if fx.Parent then
				fadeParticles(fx, false)
			end
		end
		task.delay(0.35, function()
			for _, fx in copied do
				if fx.Parent then
					fx:Destroy()
				end
			end
		end)
	end)
	setDefenceHidden(char, false)
	restoreFlightFx(char)
	if char.Parent then
		finishAbility(char, "invisibility", GameConstants.IW_INVIS_COOLDOWN)
	end
end

local function castInvis(player: Player)
	local character = player.Character
	if not character then
		return
	end
	if invisByPlayer[player] then
		restoreInvis(player, character)
		return
	end
	local entry = CharacterRegistry.getAbilityById(HERO, "invisibility")
	if not entry or not canUse(character, entry.id, GameConstants.IW_INVIS_ENERGY) then
		return
	end
	AbilityCooldownHelper.setActive(character, entry.id, true)
	hideHandVfx(character)
	fireCameraShake(player, 0.36, 0.42, 0.22, 0.48)
	local root = getRoot(character)
	if root then
		playWorldSound(GameConstants.IW_INVIS_ON_SOUND, root.Position, 0.9)
	end
	local copied = attachInvisMorphFx(character)
	for _, fx in copied do
		fadeParticles(fx, true)
		VfxHelper.emitAllParticles(fx, 6)
	end
	local saved: { { inst: Instance, t: number } } = {}
	local function remember(inst: Instance)
		if isFlightFxInst(character, inst) then
			return
		end
		if isPowerFxInst(character, inst) then
			return
		end
		if inst.Name == "IwInvisFx" then
			return
		end
		if inst:IsA("BasePart") or inst:IsA("Decal") or inst:IsA("Texture") then
			table.insert(saved, { inst = inst, t = stealthTransparencyOf(character, inst, inst.Transparency) })
		end
	end
	for _, desc in character:GetDescendants() do
		remember(desc)
		if desc:IsA("Accessory") then
			for _, p in desc:GetDescendants() do
				remember(p)
			end
		end
	end
	local token = (invisToken[player] or 0) + 1
	invisToken[player] = token
	invisByPlayer[player] = {
		character = character,
		fx = copied,
		saved = saved,
		token = token,
	}
	character:SetAttribute(GameConstants.IW_INVIS_ATTRIBUTE, true)
	setDefenceHidden(character, true)
	if crushByPlayer[player] or areaByPlayer[player] then
		local fx = powerFxByCharacter[character]
		if fx and #fx.instances == 0 then
			fx.instances = spawnHandVfx(character)
		end
	end
	task.delay(GameConstants.IW_INVIS_COPY_WAIT, function()
		if invisToken[player] ~= token then
			return
		end
		for _, fx in copied do
			if fx.Parent then
				fadeParticles(fx, false)
			end
		end
		local fadeTime = GameConstants.IW_INVIS_FADE
		local sweep = GameConstants.IW_INVIS_SWEEP
		local minY, maxY = math.huge, -math.huge
		for _, rec in saved do
			if rec.inst.Parent then
				local y = worldYOf(rec.inst)
				if y < minY then
					minY = y
				end
				if y > maxY then
					maxY = y
				end
			end
		end
		local span = math.max(0.2, maxY - minY)
		for _, rec in saved do
			if rec.inst.Parent and (rec.inst:IsA("BasePart") or rec.inst:IsA("Decal") or rec.inst:IsA("Texture")) then
				local y = worldYOf(rec.inst)
				local delay = ((maxY - y) / span) * sweep
				task.delay(delay, function()
					if invisToken[player] ~= token or not rec.inst.Parent then
						return
					end
					if isFlightFxInst(character, rec.inst) then
						return
					end
					TweenService:Create(
						rec.inst,
						TweenInfo.new(fadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
						{ Transparency = 1 }
					):Play()
				end)
			end
		end
		pcall(function()
			NameplateService.setHidden(character, true, sweep + fadeTime)
		end)
	end)
end

local function getHead(model: Model): BasePart?
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head
	end
	return getRoot(model)
end

local function charactersInPart(part: BasePart, visual: Instance, owner: Model): { Model }
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { owner, visual }
	local cf = part.CFrame
	local size = part.Size
	if visual:IsA("Model") then
		cf, size = visual:GetBoundingBox()
	end
	local hits = Workspace:GetPartBoundsInBox(cf, size, params)
	local seen: { [Model]: boolean } = {}
	local results: { Model } = {}
	for _, hit in hits do
		local character = CombatHelper.getCharacterFromPart(hit)
		if character and not seen[character] and character ~= owner then
			seen[character] = true
			if isValidVictim(character, owner) then
				table.insert(results, character)
			end
		end
	end
	return results
end

local function releaseChokeVictim(hold: ChokeVictim)
	local hum = CombatHelper.getHumanoid(hold.character)
	if hum and hum.Parent and hum.Health > 0 then
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
	if hold.fx and hold.fx.Parent then
		fadeOutVisual(hold.fx, GameConstants.IW_CHOKE_FADE)
	end
	if hold.previousPowersDisabledUntil ~= nil then
		hold.character:SetAttribute(GameConstants.POWERS_DISABLED_UNTIL, hold.previousPowersDisabledUntil)
	else
		hold.character:SetAttribute(GameConstants.POWERS_DISABLED_UNTIL, nil)
	end
	hold.character:SetAttribute(GameConstants.BUSY_ATTRIBUTE, nil)
	if Players:GetPlayerFromCharacter(hold.character) then
		hold.character:SetAttribute(GameConstants.IW_CHOKED_ATTRIBUTE, nil)
	end
end

local function stopChoke(state: AreaState, applyCooldown: boolean?)
	local wasChoking = state.choking
	state.choking = false
	for victim, hold in state.victims do
		releaseChokeVictim(hold)
		state.victims[victim] = nil
	end
	if state.character.Parent then
		if wasChoking and applyCooldown then
			finishAbility(state.character, "forcefield_choke", GameConstants.IW_CHOKE_COOLDOWN)
		else
			AbilityCooldownHelper.setActive(state.character, "forcefield_choke", false)
		end
	end
end

local function findChildByNames(root: Instance?, names: { string }): Instance?
	if not root then
		return nil
	end
	for _, name in names do
		local child = root:FindFirstChild(name)
		if child then
			return child
		end
		local deep = root:FindFirstChild(name, true)
		if deep then
			return deep
		end
	end
	return nil
end

local function getForcefieldAreaRoot(): Instance?
	return VfxHelper.getInvisibleWomanAsset("ForcefieldArea")
end

local function getAreaVisualTemplate(): Instance?
	return VfxHelper.getInvisibleWomanAsset("ForcefieldArea", "ForcefieldArea")
end

local function getChokeTemplate(): Instance?
	local root = getForcefieldAreaRoot()
	local named = findChildByNames(root, { "ChokeAttachment", "ChokenArea", "ChokeArea", "Choke" })
	if named then
		return named
	end
	return VfxHelper.getInvisibleWomanAsset("ForcefieldPush", "ChokeAttachment")
end

local function attachChokeFx(victim: Model): Instance?
	local template = getChokeTemplate()
	local head = getHead(victim)
	if not template or not head then
		return nil
	end
	local fx = template:Clone()
	fx.Name = "IwChokeAttachment"
	fx.Parent = head
	fadeParticles(fx, true)
	VfxHelper.emitAllParticles(fx, 8)
	return fx
end

local function seizeChokeVictim(owner: Model, victim: Model): ChokeVictim?
	local hum = CombatHelper.getHumanoid(victim)
	if not hum or hum.Health <= 0 then
		return nil
	end
	local jumpPower: number? = if hum.UseJumpPower then hum.JumpPower else nil
	local jumpHeight: number? = nil
	if not hum.UseJumpPower then
		pcall(function()
			jumpHeight = hum.JumpHeight
		end)
	end
	local hold: ChokeVictim = {
		character = victim,
		walk = hum.WalkSpeed,
		jumpPower = jumpPower,
		jumpHeight = jumpHeight,
		fx = attachChokeFx(victim),
		damageTaken = 0,
		previousPowersDisabledUntil = victim:GetAttribute(GameConstants.POWERS_DISABLED_UNTIL),
	}
	hum.WalkSpeed = 0
	if hum.UseJumpPower then
		hum.JumpPower = 0
	else
		hum.JumpHeight = 0
	end
	pcall(function()
		hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	end)
	victim:SetAttribute(GameConstants.BUSY_ATTRIBUTE, true)
	victim:SetAttribute(GameConstants.POWERS_DISABLED_UNTIL, AbilityCooldownHelper.getNow() + 0.5)
	if Players:GetPlayerFromCharacter(victim) then
		victim:SetAttribute(GameConstants.IW_CHOKED_ATTRIBUTE, true)
	end
	return hold
end

local function endArea(player: Player, applyCooldown: boolean, broken: boolean?)
	local state = areaByPlayer[player]
	if not state then
		return
	end
	areaByPlayer[player] = nil
	local ragdollVictims: { Model } = {}
	if state.choking then
		for victim in state.victims do
			table.insert(ragdollVictims, victim)
		end
	end
	stopChoke(state, applyCooldown)
	for victim, previous in state.powerDisabled do
		if victim.Parent then
			victim:SetAttribute(GameConstants.POWERS_DISABLED_UNTIL, previous)
		end
		state.powerDisabled[victim] = nil
	end
	for _, victim in ragdollVictims do
		if victim.Parent then
			RagdollService.applyTimed(victim, 3)
		end
	end
	destroyShieldUi(state.billboard)
	if state.visual.Parent then
		disableAreaShieldCollision(state.visual)
		fadeOutVisual(state.visual, GameConstants.IW_AREA_FADE, true)
	elseif state.part.Parent then
		disableAreaShieldCollision(state.part)
		fadeOutVisual(state.part, GameConstants.IW_AREA_FADE, true)
	end
	endPowerFx(state.character)
	if state.character.Parent then
		state.character:SetAttribute(GameConstants.BUSY_ATTRIBUTE, nil)
	end
	local casterHum = CombatHelper.getHumanoid(state.character)
	if casterHum and state.character.Parent then
		clearCastFace(state.character)
		restoreMove(state.character, state.walk, state.jumpPower, state.jumpHeight, state.autoRotate)
	end
	if applyCooldown then
		finishAbility(state.character, "forcefield_area", GameConstants.IW_AREA_COOLDOWN)
	else
		AbilityCooldownHelper.setActive(state.character, "forcefield_area", false)
	end
	local shield = shieldByPlayer[player]
	if shield and shield.fromProtect then
		stopForcefield(player, false)
		if state.character.Parent then
			if applyCooldown then
				finishAbility(state.character, "forcefield_protect", GameConstants.IW_PROTECT_COOLDOWN)
			else
				AbilityCooldownHelper.setActive(state.character, "forcefield_protect", false)
			end
		end
	end
end

local function startChoke(player: Player)
	local state = areaByPlayer[player]
	if not state or not state.part.Parent then
		return
	end
	local character = player.Character
	if not character then
		return
	end
	local entry = CharacterRegistry.getAbilityById(HERO, "forcefield_choke")
	if not entry or not canUse(character, entry.id, 0) then
		return
	end
	if state.choking then
		return
	end
	AbilityCooldownHelper.setActive(character, entry.id, true)
	state.choking = true
	fireCameraShake(player, 0.38, 0.28, 0.2, 0.4)
	faceToward(character, state.part.Position, 0.4)
end

local function protectArea(player: Player)
	local state = areaByPlayer[player]
	if not state then
		return
	end
	local character = player.Character
	if not character then
		return
	end
	local entry = CharacterRegistry.getAbilityById(HERO, "forcefield_protect")
	if not entry or not canUse(character, entry.id, 0) then
		return
	end
	local existingShield = shieldByPlayer[player]
	if existingShield and existingShield.fromProtect then
		return
	end
	startForcefield(player, true)
	AbilityCooldownHelper.setActive(character, entry.id, true)
	fireCameraShake(player, 0.28, 0.22, 0.12, 0.3)
end

local function stopProtect(player: Player, applyCooldown: boolean)
	local character = player.Character
	local wasActive = character ~= nil and AbilityCooldownHelper.isActive(character, "forcefield_protect")
	local shield = shieldByPlayer[player]
	if shield and shield.fromProtect then
		stopForcefield(player, false)
	end
	if not character then
		return
	end
	if wasActive and applyCooldown then
		finishAbility(character, "forcefield_protect", GameConstants.IW_PROTECT_COOLDOWN)
	else
		AbilityCooldownHelper.setActive(character, "forcefield_protect", false)
	end
end

local function stampAreaShield(root: Instance, part: BasePart, maxHp: number)
	local function prep(bp: BasePart)
		bp.Anchored = true
		bp.CanCollide = true
		bp.CanQuery = true
		bp.CanTouch = false
		bp:SetAttribute("IwAreaShield", true)
		bp:SetAttribute("IwAreaHp", maxHp)
	end
	prep(part)
	if root:IsA("BasePart") then
		prep(root)
	end
	for _, desc in root:GetDescendants() do
		if desc:IsA("BasePart") then
			prep(desc)
		end
	end
	root:SetAttribute("IwAreaShield", true)
	root:SetAttribute("IwAreaHp", maxHp)
end

local function placeAreaVisual(aimPoint: Vector3): (BasePart?, Instance?)
	local template = getAreaVisualTemplate()
	if not template then
		warn("[InvisibleWoman] Missing Assets.InvisibleWoman.ForcefieldArea.ForcefieldArea")
		return nil, nil
	end
	local clone = template:Clone()
	clone.Name = "IwForcefieldArea"
	local maxHp = GameConstants.IW_AREA_HP
	if clone:IsA("BasePart") then
		local part = clone
		part.CFrame = CFrame.new(aimPoint)
		stampAreaShield(clone, part, maxHp)
		part.Parent = Workspace
		return part, part
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
		clone:PivotTo(CFrame.new(aimPoint))
		stampAreaShield(clone, primary, maxHp)
		clone.Parent = Workspace
		return primary, clone
	end
	if clone:IsA("Attachment") then
		local host = Instance.new("Part")
		host.Name = "IwForcefieldArea"
		host.Anchored = true
		host.CanCollide = true
		host.CanQuery = true
		host.Transparency = 1
		host.Size = Vector3.new(12, 12, 12)
		host.CFrame = CFrame.new(aimPoint)
		host.Parent = Workspace
		clone.Parent = host
		stampAreaShield(host, host, maxHp)
		return host, host
	end
	clone:Destroy()
	return nil, nil
end

local function castArea(player: Player, aimPoint: Vector3?)
	local character = player.Character
	if not character then
		return
	end
	local existing = areaByPlayer[player]
	if existing then
		endArea(player, true, false)
		return
	end
	local entry = CharacterRegistry.getAbilityById(HERO, "forcefield_area")
	local map = Workspace:FindFirstChild("Map")
	local spawnModel = map and map:FindFirstChild("SpawnModel")
	if spawnModel and spawnModel:IsA("Model") and aimPoint then
		local boxCf, boxSize = spawnModel:GetBoundingBox()
		local expanded = boxSize + Vector3.new(24, 24, 24)
		local localPoint = boxCf:PointToObjectSpace(aimPoint)
		if math.abs(localPoint.X) <= expanded.X * 0.5
			and math.abs(localPoint.Y) <= expanded.Y * 0.5
			and math.abs(localPoint.Z) <= expanded.Z * 0.5
		then
			return
		end
	end
	if not entry or not canUse(character, entry.id, GameConstants.IW_AREA_ENERGY) then
		return
	end
	local root = getRoot(character)
	if not root then
		return
	end
	local aim = aimPoint
		or liveAim(character, root.Position + root.CFrame.LookVector * 24)
		or (root.Position + root.CFrame.LookVector * 24)
	faceToward(character, aim, 0.36)
	local part, visual = placeAreaVisual(aim)
	if not part or not visual then
		local energy = character:GetAttribute(GameConstants.ENERGY_ATTRIBUTE)
		if type(energy) == "number" then
			character:SetAttribute(GameConstants.ENERGY_ATTRIBUTE, energy + GameConstants.IW_AREA_ENERGY)
		end
		return
	end
	AbilityCooldownHelper.setActive(character, entry.id, true)
	beginPowerFx(character, true)
	fireCameraShake(player, 0.52, 0.38, 0.44, 0.55)
	local maxHp = GameConstants.IW_AREA_HP
	local billboard, hpLabel, hpFill = createShieldHpBillboard(part, maxHp, true)
	local hum = CombatHelper.getHumanoid(character)
	local savedWalk = GameConstants.DEFAULT_WALK_SPEED
	local savedJumpPower: number? = nil
	local savedJumpHeight: number? = nil
	local savedAutoRotate = true
	if hum then
		savedWalk = hum.WalkSpeed
		savedJumpPower = hum.JumpPower
		savedJumpHeight = hum.JumpHeight
		savedAutoRotate = hum.AutoRotate
		lockHumanoidMotion(hum)
		hum.AutoRotate = false
		hum:Move(Vector3.zero, false)
	end
	character:SetAttribute(GameConstants.BUSY_ATTRIBUTE, true)
	areaByPlayer[player] = {
		character = character,
		part = part,
		visual = visual,
		choking = false,
		victims = {},
		powerDisabled = {},
		tickAcc = 0,
		hp = maxHp,
		maxHp = maxHp,
		billboard = billboard,
		hpLabel = hpLabel,
		hpFill = hpFill,
		walk = savedWalk,
		jumpPower = savedJumpPower,
		jumpHeight = savedJumpHeight,
		autoRotate = savedAutoRotate,
	}
	updateShieldUi(hpLabel, hpFill, maxHp, maxHp)
end

local function updateArea(player: Player, state: AreaState, dt: number)
	if not state.character.Parent or not state.part.Parent or player.Character ~= state.character then
		endArea(player, true, false)
		return
	end
	local extra = 0
	if state.choking then
		local n = 0
		for _victim in state.victims do
			n += 1
		end
		extra = GameConstants.IW_CHOKE_ENERGY_PER_VICTIM_PER_SEC * n
	end
	local areaDrain = (GameConstants.IW_AREA_ENERGY_PER_SEC + extra) * dt
	if state.character:GetAttribute(GameConstants.LOOK_MODE_ATTRIBUTE) == "modern" then
		areaDrain *= 0.75
	end
	if not CharacterService.spendEnergy(state.character, areaDrain) then
		endArea(player, true, false)
		return
	end
	local flying = state.character:GetAttribute(GameConstants.IS_FLYING_ATTRIBUTE) == true
	local modern = state.character:GetAttribute(GameConstants.LOOK_MODE_ATTRIBUTE) == "modern"
	local strainRate = GameConstants.IW_HYPERSPACE_AREA_PER_SEC
	if flying and modern then
		strainRate = GameConstants.IW_HYPERSPACE_AREA_FLIGHT_PER_SEC
	end
	local maxHs = GameConstants.IW_HYPERSPACE_MAX
	local hs = state.character:GetAttribute(GameConstants.IW_HYPERSPACE_ATTRIBUTE)
	if type(hs) ~= "number" then
		hs = 0
	end
	hs = math.clamp(hs + strainRate * dt, 0, maxHs)
	state.character:SetAttribute(GameConstants.IW_HYPERSPACE_ATTRIBUTE, hs)
	state.character:SetAttribute(GameConstants.IW_HYPERSPACE_MAX_ATTRIBUTE, maxHs)
	if hs >= maxHs then
		state.character:SetAttribute(GameConstants.IW_HYPERSPACE_LOCK_ATTRIBUTE, true)
		HexFlightService.endFlight(player, true)
		endArea(player, true, false)
		return
	end
	local attrHp = state.visual:GetAttribute("IwAreaHp")
	if type(attrHp) == "number" then
		state.hp = attrHp
	end
	if state.visual:GetAttribute("IwAreaBroken") == true or state.hp <= 0 then
		endArea(player, true, true)
		return
	end
	updateShieldUi(state.hpLabel, state.hpFill, state.hp, state.maxHp)
	local casterHum = CombatHelper.getHumanoid(state.character)
	local casterRoot = getRoot(state.character)
	if casterHum then
		lockHumanoidMotion(casterHum)
		casterHum.AutoRotate = false
		casterHum:Move(Vector3.zero, false)
	end
	if casterRoot then
		casterRoot.AssemblyLinearVelocity = Vector3.zero
		casterRoot.AssemblyAngularVelocity = Vector3.zero
	end
	local insideArea: { [Model]: boolean } = {}
	for _, victim in charactersInPart(state.part, state.visual, state.character) do
		insideArea[victim] = true
		if state.powerDisabled[victim] == nil then
			state.powerDisabled[victim] = victim:GetAttribute(GameConstants.POWERS_DISABLED_UNTIL)
		end
		victim:SetAttribute(GameConstants.POWERS_DISABLED_UNTIL, AbilityCooldownHelper.getNow() + 0.5)
	end
	for victim, previous in state.powerDisabled do
		if not insideArea[victim] or not victim.Parent then
			victim:SetAttribute(GameConstants.POWERS_DISABLED_UNTIL, previous)
			state.powerDisabled[victim] = nil
		end
	end
	if not state.choking then
		return
	end
	local inside: { [Model]: boolean } = {}
	for _, victim in charactersInPart(state.part, state.visual, state.character) do
		inside[victim] = true
		if not state.victims[victim] then
			local hold = seizeChokeVictim(state.character, victim)
			if hold then
				state.victims[victim] = hold
			end
		end
	end
	for victim, hold in state.victims do
		if not inside[victim] or not victim.Parent then
			releaseChokeVictim(hold)
			state.victims[victim] = nil
		end
	end
	state.tickAcc += dt
	if state.tickAcc >= GameConstants.IW_CHOKE_TICK then
		local slice = state.tickAcc
		state.tickAcc = 0
		local n = 0
		for _victim, _hold in state.victims do
			n += 1
		end
		if n <= 0 then
			return
		end
		local dmg = (GameConstants.IW_CHOKE_DAMAGE_PER_SEC / n) * slice
		for victim, _hold in state.victims do
			local vRoot = getRoot(victim)
			CombatHelper.dealDamage(state.character, victim, dmg, vRoot and vRoot.Position or nil, "dot")
		end
	end
end

local function endCrush(player: Player, applyCooldown: boolean, launchVictim: boolean?)
	local state = crushByPlayer[player]
	if not state then
		return
	end
	crushByPlayer[player] = nil
	stopTrack(state.casterAnim)
	stopTrack(state.victimAnim)
	state.victim:SetAttribute(GameConstants.MG_TK_CONTROLLED_ATTRIBUTE, nil)
	state.victim:SetAttribute(GameConstants.BUSY_ATTRIBUTE, nil)
	if state.character.Parent then
		state.character:SetAttribute(GameConstants.BUSY_ATTRIBUTE, nil)
	end
	local casterRoot = getRoot(state.character)
	clearCrushFace(casterRoot)
	local casterHum = CombatHelper.getHumanoid(state.character)
	if casterHum then
		unlockHumanoidMotion(casterHum, state.walk, state.jumpPower, state.jumpHeight)
		casterHum.AutoRotate = state.autoRotate
	end
	if casterRoot then
		local plr = Players:GetPlayerFromCharacter(state.character)
		pcall(function()
			if plr then
				casterRoot:SetNetworkOwner(plr)
			else
				casterRoot:SetNetworkOwnershipAuto()
			end
		end)
	end
	if state.fx.Parent then
		fadeParticles(state.fx, false)
		task.delay(0.4, function()
			if state.fx.Parent then
				state.fx:Destroy()
			end
		end)
	end
	endPowerFx(state.character)
	if launchVictim and state.victim.Parent and state.vRoot.Parent then
		local victim = state.victim
		local vRoot = state.vRoot
		local away = vRoot.Position - state.casterHoldPos
		local dir = if away.Magnitude > 0.05 then away.Unit else Vector3.new(0, 0, -1)
		local speed = GameConstants.IW_CRUSH_KNOCK_SPEED
		local up = GameConstants.IW_CRUSH_KNOCK_UP
		local velocity = dir * speed + Vector3.new(0, up, 0)
		PushHelper.applyToCharacter(victim, dir, {
			speed = speed,
			upBoost = up,
			impulseMult = 1.35,
		})
		vRoot.AssemblyLinearVelocity = velocity
		RagdollService.applyTimed(victim, 2.2)
		task.delay(0.05, function()
			if not victim.Parent then
				return
			end
			PushHelper.applyToCharacter(victim, dir, {
				speed = speed,
				upBoost = up,
				impulseMult = 1.35,
			})
			for _, desc in victim:GetDescendants() do
				if desc:IsA("BasePart") and not desc.Anchored then
					desc.AssemblyLinearVelocity = velocity
				end
			end
		end)
	end
	if applyCooldown then
		finishAbility(state.character, "forcefield_crush", GameConstants.IW_CRUSH_COOLDOWN)
	else
		AbilityCooldownHelper.setActive(state.character, "forcefield_crush", false)
	end
end

local function tryCrushExecute(character: Model, victim: Model, vRoot: BasePart): boolean
	if character:GetAttribute(GameConstants.LOOK_MODE_ATTRIBUTE) ~= "modern" then
		return false
	end
	local hum = CombatHelper.getHumanoid(victim)
	if not hum or hum.MaxHealth <= 0 then
		return false
	end
	if hum.Health / hum.MaxHealth >= GameConstants.IW_CRUSH_EXECUTE_HP then
		return false
	end
	if AbilityCooldownHelper.isOnCooldown(character, "crush_execute") then
		return false
	end
	local snaps = VfxHelper.captureVisibleParts(victim)
	local crushFx: Instance? = nil
	local template = VfxHelper.getInvisibleWomanAsset("ForcefieldCrush", "BodyCrushInsta")
	if template then
		local fx = template:Clone()
		fx.Name = "IwBodyCrushInsta"
		crushFx = fx
		if fx:IsA("Attachment") then
			fx.Position = Vector3.zero
			fx.Parent = vRoot
		else
			fx.Parent = vRoot
		end
		fadeParticles(fx, true)
		VfxHelper.emitAllParticles(fx, 16)
		task.delay(4, function()
			if fx.Parent then
				fadeParticles(fx, false)
			end
		end)
		task.delay(6, function()
			if fx.Parent then
				fx:Destroy()
			end
		end)
	end
	AbilityCooldownHelper.applyAfterUse(character, "crush_execute", GameConstants.IW_CRUSH_EXECUTE_COOLDOWN)
	AbilityCooldownHelper.applyAfterUse(character, "forcefield_crush", GameConstants.IW_CRUSH_EXECUTE_COOLDOWN)
	AbilityCooldownHelper.setActive(character, "forcefield_crush", false)
	VfxHelper.hideCapturedParts(snaps)
	for _, desc in victim:GetDescendants() do
		if crushFx and (desc == crushFx or desc:IsDescendantOf(crushFx)) then
			continue
		end
		if desc:IsA("BasePart") and desc.Name ~= "HumanoidRootPart" then
			desc.Transparency = 1
			for _, child in desc:GetChildren() do
				if child:IsA("Decal") or child:IsA("Texture") then
					child.Transparency = 1
				end
			end
		end
	end
	local victimPlayer = Players:GetPlayerFromCharacter(victim)
	if victimPlayer then
		local crushRed = Color3.fromRGB(190, 18, 18)
		ScreenFeelHelper.setTint(victim, crushRed, 1.25)
		ScreenFeelHelper.pulsePlayer(victimPlayer, {
			intensity = 0.72,
			duration = 0.7,
			fovScale = 0.45,
			vignetteScale = 0.85,
			tint = crushRed,
			tintDuration = 1.05,
		})
	end
	hum.Health = 0
	playWorldSound(GameConstants.IW_CRUSH_INSTA_SOUND, vRoot.Position, 1.15)
	local ownerPlayer = Players:GetPlayerFromCharacter(character)
	if ownerPlayer then
		fireCameraShake(ownerPlayer, 0.78, 0.48, 0.58, 0.9)
	end
	return true
end

local function startCrush(player: Player, target: Model?, direction: Vector3?, aimPoint: Vector3?, lockOn: boolean?)
	local character = player.Character
	if not character or crushByPlayer[player] then
		return
	end
	local entry = CharacterRegistry.getAbilityById(HERO, "forcefield_crush")
	if not entry then
		return
	end
	local root = getRoot(character)
	if not root then
		return
	end
	local victim = resolveTarget(character, root, target, direction, aimPoint, GameConstants.IW_CRUSH_RANGE, lockOn)
	if not victim then
		return
	end
	local vRoot = getRoot(victim)
	if not vRoot then
		return
	end
	if not canUse(character, entry.id, GameConstants.IW_CRUSH_START_ENERGY) then
		return
	end
	if tryCrushExecute(character, victim, vRoot) then
		beginPowerFx(character, true)
		task.delay(0.25, function()
			if character.Parent then
				endPowerFx(character)
			end
		end)
		return
	end
	AbilityCooldownHelper.setActive(character, entry.id, true)
	beginPowerFx(character, true)
	fireCameraShake(player, 0.56, 0.42, 0.4, 0.65)
	victim:SetAttribute(GameConstants.MG_TK_CONTROLLED_ATTRIBUTE, true)
	victim:SetAttribute(GameConstants.BUSY_ATTRIBUTE, true)
	character:SetAttribute(GameConstants.BUSY_ATTRIBUTE, true)
	local casterHum = CombatHelper.getHumanoid(character)
	local walk = GameConstants.DEFAULT_WALK_SPEED
	local jumpPower: number? = nil
	local jumpHeight: number? = nil
	local autoRotate = true
	if casterHum then
		walk = casterHum.WalkSpeed
		autoRotate = casterHum.AutoRotate
		jumpPower = casterHum.JumpPower
		pcall(function()
			jumpHeight = casterHum.JumpHeight
		end)
		lockHumanoidMotion(casterHum)
		casterHum.AutoRotate = false
		casterHum:Move(Vector3.zero, false)
	end
	local victimHum = CombatHelper.getHumanoid(victim)
	if victimHum then
		lockHumanoidMotion(victimHum)
	end
	local lookCf = yawLookAt(root.Position, vRoot.Position)
	root.CFrame = CFrame.new(root.Position) * lookCf.Rotation
	ensureCrushFaceAlign(root, lookCf)
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	local template = VfxHelper.getInvisibleWomanAsset("ForcefieldCrush", "BodyCrush")
	local fx: Instance
	if template then
		fx = template:Clone()
		fx.Name = "IwBodyCrush"
		if fx:IsA("BasePart") then
			fx.Anchored = true
			fx.CanCollide = false
			fx.CFrame = vRoot.CFrame
			fx.Parent = Workspace
		elseif fx:IsA("Model") then
			fx:PivotTo(vRoot.CFrame)
			fx.Parent = Workspace
			for _, desc in fx:GetDescendants() do
				if desc:IsA("BasePart") then
					desc.Anchored = true
					desc.CanCollide = false
				end
			end
		else
			fx.Parent = Workspace
		end
		fadeParticles(fx, true)
		VfxHelper.emitAllParticles(fx, 8)
	else
		fx = Instance.new("Folder")
		fx.Parent = Workspace
	end
	crushByPlayer[player] = {
		character = character,
		victim = victim,
		vRoot = vRoot,
		fx = fx,
		holdPos = vRoot.Position,
		casterHoldPos = root.Position,
		tickAcc = 0,
		walk = walk,
		jumpPower = jumpPower,
		jumpHeight = jumpHeight,
		autoRotate = autoRotate,
		faceAlign = nil,
		casterAnim = playCharacterAnim(character, GameConstants.IW_CRUSH_ANIM, true, Enum.AnimationPriority.Action),
		victimAnim = playCharacterAnim(victim, GameConstants.IW_CRUSH_TARGET_ANIM, true, Enum.AnimationPriority.Action4),
		endsAt = os.clock() + GameConstants.IW_CRUSH_DURATION,
	}
end

local function aoeBurst(owner: Model, pos: Vector3, radius: number, damage: number, ragdoll: number, knock: number)
	for _, victim in CombatHelper.overlapCharacters(pos, radius, owner) do
		CombatHelper.dealDamage(owner, victim, damage, pos, "projectile")
		RagdollService.applyTimed(victim, ragdoll)
		ScreenFeelHelper.pulseCharacter(victim, {
			intensity = 0.64,
			duration = 0.34,
			fovScale = 0.38,
			vignetteScale = 0.4,
		})
		local vRoot = getRoot(victim)
		if vRoot then
			local away = vRoot.Position - pos
			PushHelper.applyToCharacter(victim, if away.Magnitude > 0.05 then away.Unit else Vector3.new(0, 0, -1), {
				speed = knock,
				upBoost = 22,
			})
		end
	end
end

local function applyProjectionHit(owner: Model, victim: Model, dir: Vector3, pos: Vector3)
	CombatHelper.dealDamage(owner, victim, GameConstants.IW_PROJECTION_DAMAGE, pos, "projectile")
	RagdollService.applyTimed(victim, GameConstants.IW_PROJECTION_RAGDOLL)
	ScreenFeelHelper.pulseCharacter(victim, {
		intensity = 0.58,
		duration = 0.32,
		fovScale = 0.34,
		vignetteScale = 0.38,
		tint = GameConstants.IW_COLOR,
		tintDuration = 0.8,
	})
	local vRoot = getRoot(victim)
	if vRoot then
		local pushDir = if dir.Magnitude > 0.05 then dir.Unit else Vector3.new(0, 0, -1)
		vRoot.AssemblyLinearVelocity = pushDir * GameConstants.IW_PUSH_KNOCK_SPEED + Vector3.new(0, GameConstants.IW_PUSH_KNOCK_UP, 0)
	end
end

local function restoreProjectionMove(state: ProjectionState)
	restoreMove(state.owner, state.walk, state.jumpPower, state.jumpHeight, state.autoRotate)
end

local function destroyProjection(player: Player, explode: boolean, pos: Vector3?)
	local state = projectionByPlayer[player]
	if not state then
		return
	end
	projectionByPlayer[player] = nil
	state.alive = false
	if not state.launched then
		restoreProjectionMove(state)
	end
	if explode then
		aoeBurst(
			state.owner,
			pos or state.part.Position,
			GameConstants.IW_PROJECTION_AOE,
			GameConstants.IW_PROJECTION_DAMAGE,
			GameConstants.IW_PROJECTION_RAGDOLL,
			GameConstants.IW_PROJECTION_KNOCK
		)
	end
	if state.visual.Parent then
		fadeOutVisual(state.visual, GameConstants.IW_PUSH_FADE)
	elseif state.part.Parent then
		fadeOutVisual(state.part, GameConstants.IW_PUSH_FADE)
	end
end

local function isSolidWorldPart(part: BasePart, owner: Model): boolean
	local character = CombatHelper.getCharacterFromPart(part)
	if character then
		return false
	end
	if part:IsDescendantOf(owner) then
		return false
	end
	return true
end

local function castProjection(player: Player, direction: Vector3?, aimPoint: Vector3?)
	local character = player.Character
	if not character or projectionByPlayer[player] then
		return
	end
	local entry = CharacterRegistry.getAbilityById(HERO, "body_projection")
	if not entry or not canUse(character, entry.id, GameConstants.IW_PROJECTION_ENERGY) then
		return
	end
	local root = getRoot(character)
	local template = VfxHelper.getInvisibleWomanAsset("BodyProjection", "BodyProjection")
	if not root or not template then
		return
	end
	beginPowerFx(character)
	fireCameraShake(player, 0.42, 0.32, 0.32, 0.52)
	local flatLook = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	local dir = if flatLook.Magnitude > 0.05 then flatLook.Unit else Vector3.new(0, 0, -1)
	local origin = root.Position + Vector3.new(0, 1.2, 0) + dir * 2.2
	local clone = template:Clone()
	clone.Name = "IwBodyProjection"
	local part: BasePart?
	if clone:IsA("BasePart") then
		part = clone
		clone.CFrame = CFrame.lookAt(origin, origin + dir)
		clone.Anchored = true
		clone.CanCollide = false
		clone.CanQuery = true
		clone.CanTouch = true
		clone.Parent = Workspace
	elseif clone:IsA("Model") then
		clone:PivotTo(CFrame.lookAt(origin, origin + dir))
		clone.Parent = Workspace
		part = clone.PrimaryPart or clone:FindFirstChildWhichIsA("BasePart", true)
		if part then
			part.Anchored = true
			part.CanCollide = false
		end
	end
	if not part then
		clone:Destroy()
		endPowerFx(character)
		return
	end
	fadeParticles(clone, true)
	playWorldSound(GameConstants.IW_PROJECTION_RELEASE_SOUND, origin, 0.95)
	AbilityCooldownHelper.setActive(character, entry.id, true)
	local walk, jumpPower, jumpHeight = captureAndLockMove(character)
	local hum = CombatHelper.getHumanoid(character)
	local autoRotate = if hum then hum.AutoRotate else true
	if hum then
		hum.AutoRotate = false
	end
	projectionByPlayer[player] = {
		visual = clone,
		part = part,
		owner = character,
		hit = {},
		alive = true,
		dir = dir,
		launched = false,
		launchAt = os.clock() + GameConstants.IW_PROJECTION_HOLD,
		bornAt = os.clock(),
		spawnPos = origin,
		casterHoldPos = root.Position,
		walk = walk,
		jumpPower = jumpPower,
		jumpHeight = jumpHeight,
		autoRotate = autoRotate,
	}
	task.delay(0.25, function()
		if character.Parent then
			endPowerFx(character)
			if AbilityCooldownHelper.isActive(character, entry.id) then
				finishAbility(character, entry.id, GameConstants.IW_PROJECTION_COOLDOWN)
			end
		end
	end)
end

local function beginSmashLock(player: Player, character: Model)
	if smashHoldByPlayer[player] then
		return
	end
	local hum = CombatHelper.getHumanoid(character)
	if not hum then
		return
	end
	local walk = hum.WalkSpeed
	local jumpPower: number? = hum.JumpPower
	local jumpHeight: number? = nil
	pcall(function()
		jumpHeight = hum.JumpHeight
	end)
	smashHoldByPlayer[player] = {
		walk = walk,
		jumpPower = jumpPower,
		jumpHeight = jumpHeight,
		autoRotate = hum.AutoRotate,
	}
	character:SetAttribute(GameConstants.BUSY_ATTRIBUTE, true)
	lockHumanoidMotion(hum)
	hum.AutoRotate = false
	hum:Move(Vector3.zero, false)
end

local function applySmashLock(character: Model)
	local hum = CombatHelper.getHumanoid(character)
	if hum then
		lockHumanoidMotion(hum)
		hum.AutoRotate = false
		hum:Move(Vector3.zero, false)
	end
	character:SetAttribute(GameConstants.BUSY_ATTRIBUTE, true)
end

local function endSmashLock(player: Player, character: Model?)
	local hold = smashHoldByPlayer[player]
	smashHoldByPlayer[player] = nil
	if not hold then
		return
	end
	local char = character
	if not char then
		return
	end
	if char:GetAttribute(GameConstants.BUSY_ATTRIBUTE) == true then
		char:SetAttribute(GameConstants.BUSY_ATTRIBUTE, nil)
	end
	clearCastFace(char)
	local flying = char:GetAttribute(GameConstants.IS_FLYING_ATTRIBUTE) == true
	restoreMove(char, hold.walk, hold.jumpPower, hold.jumpHeight, not flying)
end

local function smashSkinFolder(character: Model): string
	if character:GetAttribute(GameConstants.LOOK_MODE_ATTRIBUTE) == "modern" then
		return "ModernSmash"
	end
	return "BaseSmash"
end

local function smashAsset(character: Model, name: string): Instance?
	return VfxHelper.getInvisibleWomanAsset("ForcefieldSmash", smashSkinFolder(character), name)
end

local function abortSmash(player: Player)
	smashToken[player] = (smashToken[player] or 0) + 1
	local walls = smashWallsByPlayer[player]
	smashWallsByPlayer[player] = nil
	if walls then
		for _, inst in walls do
			if inst.Parent then
				fadeOutVisual(inst, 0.2)
			end
		end
	end
	endSmashLock(player, player.Character)
end

local function spawnSmashPart(template: Instance?, cf: CFrame, name: string, particlesOn: boolean): Instance?
	if not template then
		return nil
	end
	local clone = template:Clone()
	clone.Name = name
	if clone:IsA("BasePart") then
		clone.Anchored = true
		clone.CanCollide = false
		clone.CFrame = cf
		clone.Parent = Workspace
	elseif clone:IsA("Model") then
		clone:PivotTo(cf)
		clone.Parent = Workspace
		for _, desc in clone:GetDescendants() do
			if desc:IsA("BasePart") then
				desc.Anchored = true
				desc.CanCollide = false
			end
		end
	else
		clone.Parent = Workspace
	end
	fadeParticles(clone, particlesOn)
	if particlesOn then
		VfxHelper.emitAllParticles(clone, 8)
	end
	return clone
end

local function setInstCf(inst: Instance, cf: CFrame)
	if inst:IsA("BasePart") then
		inst.CFrame = cf
	elseif inst:IsA("Model") then
		inst:PivotTo(cf)
	end
end

local function castSmash(player: Player, direction: Vector3?, aimPoint: Vector3?)
	local character = player.Character
	if not character then
		return
	end
	local entry = CharacterRegistry.getAbilityById(HERO, "forcefield_smash")
	if not entry or not canUse(character, entry.id, GameConstants.IW_SMASH_ENERGY) then
		return
	end
	local root = getRoot(character)
	if not root then
		return
	end
	local smashRange = if character:GetAttribute(GameConstants.LOOK_MODE_ATTRIBUTE) == "modern"
		then GameConstants.IW_SMASH_RANGE_MODERN
		else GameConstants.IW_SMASH_RANGE
	local midPos = aimPoint or (root.Position + root.CFrame.LookVector * 18)
	if (midPos - root.Position).Magnitude > smashRange then
		midPos = root.Position + normalizeDir(midPos - root.Position) * smashRange
	end
	local groundParams = RaycastParams.new()
	groundParams.FilterType = Enum.RaycastFilterType.Exclude
	groundParams.FilterDescendantsInstances = { character }
	local groundHit = Workspace:Raycast(midPos + Vector3.new(0, 12, 0), Vector3.new(0, -60, 0), groundParams)
	if not groundHit then
		groundHit = Workspace:Raycast(root.Position + Vector3.new(0, 4, 0), Vector3.new(0, -40, 0), groundParams)
	end
	local wallTemplate = smashAsset(character, "WallCrush1")
	local wallHeight = 6
	if wallTemplate and wallTemplate:IsA("BasePart") then
		wallHeight = wallTemplate.Size.Y
	elseif wallTemplate and wallTemplate:IsA("Model") then
		wallHeight = wallTemplate:GetExtentsSize().Y
	end
	local groundY = if groundHit then groundHit.Position.Y + wallHeight * 0.5 else midPos.Y
	midPos = Vector3.new(midPos.X, groundY, midPos.Z)
	local flat = Vector3.new(midPos.X - root.Position.X, 0, midPos.Z - root.Position.Z)
	local look = if flat.Magnitude > 0.05 then flat.Unit else Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	if look.Magnitude < 0.05 then
		look = Vector3.new(0, 0, -1)
	else
		look = look.Unit
	end
	root.CFrame = CFrame.lookAt(root.Position, root.Position + look)
	local right = look:Cross(Vector3.yAxis)
	if right.Magnitude < 0.05 then
		right = Vector3.new(1, 0, 0)
	else
		right = right.Unit
	end
	AbilityCooldownHelper.setActive(character, entry.id, true)
	beginSmashLock(player, character)
	beginPowerFx(character)
	playCharacterAnim(character, GameConstants.IW_SMASH_ANIM, false, Enum.AnimationPriority.Action)
	fireCameraShake(player, 0.46, 0.3, 0.38, 0.58)
	local token = (smashToken[player] or 0) + 1
	smashToken[player] = token
	local leftPos = midPos - right * GameConstants.IW_SMASH_WALL_DIST
	local rightPos = midPos + right * GameConstants.IW_SMASH_WALL_DIST
	local leftRot = CFrame.lookAt(leftPos, midPos).Rotation
	local rightRot = CFrame.lookAt(rightPos, midPos).Rotation
	local midCf = CFrame.lookAt(midPos, midPos + look)
	task.spawn(function()
		task.wait(GameConstants.IW_SMASH_SPAWN_HOLD)
		if smashToken[player] ~= token then
			return
		end
		if not character.Parent or character:GetAttribute(GameConstants.RAGDOLLED_ATTRIBUTE) == true then
			abortSmash(player)
			if character.Parent then
				endPowerFx(character)
				AbilityCooldownHelper.setActive(character, entry.id, false)
			end
			return
		end
		local leftStart = CFrame.new(leftPos) * leftRot
		local rightStart = CFrame.new(rightPos) * rightRot
		local wall1 = spawnSmashPart(smashAsset(character, "WallCrush1"), leftStart, "IwSmashWall1", true)
		local wall2 = spawnSmashPart(smashAsset(character, "WallCrush2"), rightStart, "IwSmashWall2", true)
		smashWallsByPlayer[player] = {}
		if wall1 then
			table.insert(smashWallsByPlayer[player], wall1)
		end
		if wall2 then
			table.insert(smashWallsByPlayer[player], wall2)
		end
		task.wait(GameConstants.IW_SMASH_VISIBLE_HOLD)
		if smashToken[player] ~= token or character:GetAttribute(GameConstants.RAGDOLLED_ATTRIBUTE) == true then
			abortSmash(player)
			if character.Parent then
				endPowerFx(character)
				AbilityCooldownHelper.setActive(character, entry.id, false)
			end
			return
		end
		local t0 = os.clock()
		local dur = GameConstants.IW_SMASH_CLOSE_TIME
		while os.clock() - t0 < dur do
			if smashToken[player] ~= token or character:GetAttribute(GameConstants.RAGDOLLED_ATTRIBUTE) == true then
				abortSmash(player)
				if character.Parent then
					endPowerFx(character)
					AbilityCooldownHelper.setActive(character, entry.id, false)
				end
				return
			end
			local a = math.clamp((os.clock() - t0) / dur, 0, 1)
			local s = a * a * (3 - 2 * a)
			if wall1 then
				setInstCf(wall1, CFrame.new(leftPos:Lerp(midPos, s)) * leftRot)
			end
			if wall2 then
				setInstCf(wall2, CFrame.new(rightPos:Lerp(midPos, s)) * rightRot)
			end
			task.wait()
		end
		if smashToken[player] ~= token or character:GetAttribute(GameConstants.RAGDOLLED_ATTRIBUTE) == true then
			abortSmash(player)
			if character.Parent then
				endPowerFx(character)
				AbilityCooldownHelper.setActive(character, entry.id, false)
			end
			return
		end
		if wall1 then
			setInstCf(wall1, CFrame.new(midPos) * leftRot)
		end
		if wall2 then
			setInstCf(wall2, CFrame.new(midPos) * rightRot)
		end
		local middle = spawnSmashPart(smashAsset(character, "Impact"), midCf, "IwSmashImpact", true)
		if middle and smashWallsByPlayer[player] then
			table.insert(smashWallsByPlayer[player], middle)
		end
		playWorldSound(GameConstants.IW_SMASH_COLLIDE_SOUND, midPos, 1.05)
		fireCameraShake(player, 0.68, 0.4, 0.52, 0.82)
		aoeBurst(
			character,
			midPos,
			GameConstants.IW_SMASH_RADIUS,
			GameConstants.IW_SMASH_DAMAGE,
			GameConstants.IW_SMASH_RAGDOLL,
			GameConstants.IW_SMASH_KNOCK_SPEED
		)
		for _, victim in CombatHelper.overlapCharacters(midPos, GameConstants.IW_SMASH_RADIUS, character) do
			local vRoot = getRoot(victim)
			if not vRoot then
				continue
			end
			local away = vRoot.Position - midPos
			local dir = if away.Magnitude > 0.08 then away.Unit else look
			local speed = GameConstants.IW_SMASH_KNOCK_SPEED
			local up = GameConstants.IW_SMASH_KNOCK_UP
			local function shove()
				if not victim.Parent or not vRoot.Parent then
					return
				end
				PushHelper.applyToCharacter(victim, dir, {
					speed = speed,
					upBoost = up,
					impulseMult = 1.4,
				})
				vRoot.AssemblyLinearVelocity = dir * speed + Vector3.new(0, up, 0)
			end
			shove()
			task.defer(shove)
			task.delay(0.06, shove)
		end
		task.wait(GameConstants.IW_SMASH_WALL_LINGER)
		if smashToken[player] ~= token then
			return
		end
		if middle then
			fadeOutVisual(middle, 0.55)
		end
		if wall1 then
			fadeOutVisual(wall1, 0.9)
		end
		if wall2 then
			fadeOutVisual(wall2, 0.9)
		end
		smashWallsByPlayer[player] = nil
		endSmashLock(player, character)
		if character.Parent then
			endPowerFx(character)
			if AbilityCooldownHelper.isActive(character, entry.id) then
				finishAbility(character, entry.id, GameConstants.IW_SMASH_COOLDOWN)
			end
		end
	end)
end

function InvisibleWomanService.absorbShield(character: Model, amount: number, hitFrom: Vector3?): boolean
	if character:GetAttribute(GameConstants.HERO_ATTRIBUTE) ~= HERO then
		return false
	end
	local hum = CombatHelper.getHumanoid(character)
	if hum and hum.Health <= 0 then
		return false
	end
	local player = Players:GetPlayerFromCharacter(character)
	if character:GetAttribute(GameConstants.IW_FORCEFIELD_ATTRIBUTE) == true and player then
		local state = shieldByPlayer[player]
		if state then
			if hitFrom and math.random() < 0.3 then
				spawnShieldImpact(character, hitFrom)
				return true
			end
			state.hp -= amount
			character:SetAttribute(GameConstants.SHIELD_HP_ATTRIBUTE, math.max(0, state.hp))
			updateShieldUi(state.hpLabel, state.hpFill, state.hp, state.maxHp)
			spawnShieldImpact(character, hitFrom)
			if state.hp <= 0 then
				local overflow = -state.hp
				stopForcefield(player, true, true)
				if overflow > 0 then
					local hum = CombatHelper.getHumanoid(character)
					if hum and hum.Health > 0 then
						hum:TakeDamage(overflow)
					end
				end
			end
			return true
		end
	end
	if character:GetAttribute(GameConstants.IW_FLIGHT_SHIELD_ATTRIBUTE) == true then
		local fx = flightFxByCharacter[character]
		if fx then
			if hitFrom and math.random() < 0.3 then
				spawnShieldImpact(character, hitFrom)
				return true
			end
			fx.hp -= amount
			character:SetAttribute(GameConstants.SHIELD_HP_ATTRIBUTE, math.max(0, fx.hp))
			updateShieldUi(fx.hpLabel, fx.hpFill, fx.hp, fx.maxHp)
			spawnShieldImpact(character, hitFrom)
			if fx.hp <= 0 then
				local overflow = -fx.hp
				if player then
					HexFlightService.endFlight(player, true)
				else
					endFlightFx(character)
				end
				if overflow > 0 then
					local hum = CombatHelper.getHumanoid(character)
					if hum and hum.Health > 0 then
						hum:TakeDamage(overflow)
					end
				end
			end
			return true
		end
	end
	return false
end

function InvisibleWomanService.cancelAll(player: Player)
	HexFlightService.endFlight(player, false)
	stopForcefield(player, false)
	endArea(player, false)
	endCrush(player, false)
	destroyPush(player)
	destroyProjection(player, false)
	abortSmash(player)
	restoreInvis(player, player.Character)
	local char = player.Character
	if char then
		endFlightFx(char)
		clearPowerFx(char)
		AbilityCooldownHelper.setActive(char, "forcefield_flight", false)
		AbilityCooldownHelper.setActive(char, "iw_forcefield", false)
		AbilityCooldownHelper.setActive(char, "disc_throw", false)
		AbilityCooldownHelper.setActive(char, "forcefield_push", false)
		AbilityCooldownHelper.setActive(char, "invisibility", false)
		AbilityCooldownHelper.setActive(char, "forcefield_area", false)
		AbilityCooldownHelper.setActive(char, "forcefield_choke", false)
		AbilityCooldownHelper.setActive(char, "forcefield_protect", false)
		AbilityCooldownHelper.setActive(char, "forcefield_crush", false)
		AbilityCooldownHelper.setActive(char, "body_projection", false)
		AbilityCooldownHelper.setActive(char, "forcefield_smash", false)
		char:SetAttribute(GameConstants.IW_AIM_ATTRIBUTE, nil)
	end
end

function InvisibleWomanService.handleAction(player: Player, payload: any)
	if type(payload) ~= "table" then
		return
	end
	local character = player.Character
	if not character or character:GetAttribute(GameConstants.HERO_ATTRIBUTE) ~= HERO then
		return
	end
	if character:GetAttribute(GameConstants.RAGDOLLED_ATTRIBUTE) == true then
		return
	end
	if areaByPlayer[player] then
		local areaAction = payload.action
		if
			areaAction ~= "X"
			and areaAction ~= "X_down"
			and areaAction ~= "B"
			and areaAction ~= "B_down"
			and areaAction ~= "B_up"
			and areaAction ~= "C"
			and areaAction ~= "C_down"
			and areaAction ~= "C_up"
			and areaAction ~= "Iw_aim"
			and areaAction ~= "X_aim"
		then
			return
		end
	end
	if character:GetAttribute(GameConstants.IS_FLYING_ATTRIBUTE) == true then
		local flyAction = payload.action
		local modern = character:GetAttribute(GameConstants.LOOK_MODE_ATTRIBUTE) == "modern"
		if
			flyAction ~= "F"
			and flyAction ~= "T"
			and flyAction ~= "Iw_aim"
			and not (modern and (flyAction == "E" or flyAction == "E_aim" or flyAction == "X" or flyAction == "X_down" or flyAction == "X_aim"))
		then
			return
		end
	end
	local action = payload.action
	local direction = if typeof(payload.direction) == "Vector3" then payload.direction else nil
	local aimPoint = if typeof(payload.aimPoint) == "Vector3" then payload.aimPoint else nil
	local target = if typeof(payload.target) == "Instance" and payload.target:IsA("Model") then payload.target else nil
	local lockOn = payload.softLock == true
	if not target and typeof(payload.hitPart) == "Instance" and payload.hitPart:IsA("BasePart") then
		target = CombatHelper.getCharacterFromPart(payload.hitPart)
	end
	if aimPoint then
		character:SetAttribute(GameConstants.IW_AIM_ATTRIBUTE, aimPoint)
	end
	if action == "Q_down" then
		startForcefield(player)
	elseif action == "Q_up" then
		if shieldByPlayer[player] then
			stopForcefield(player, true)
		end
	elseif action == "E" then
		castDisc(player, direction, aimPoint)
	elseif action == "R" then
		castPush(player, direction, aimPoint)
	elseif action == "T" then
		castInvis(player)
	elseif action == "F" then
		HexFlightService.toggleFlight(player)
	elseif action == "X_down" or action == "X" then
		castArea(player, aimPoint)
	elseif action == "B" or action == "B_down" then
		startChoke(player)
	elseif action == "B_up" then
		local area = areaByPlayer[player]
		if area then
			stopChoke(area, true)
		end
	elseif action == "C" or action == "C_down" then
		protectArea(player)
	elseif action == "C_up" then
		stopProtect(player, true)
	elseif action == "Z" or action == "Z_down" then
		startCrush(player, target, direction, aimPoint, lockOn)
	elseif action == "Z_up" then
		-- Crush is timed; release does not cancel it.
	elseif action == "G" then
		castProjection(player, direction, aimPoint)
	elseif action == "H" then
		castSmash(player, direction, aimPoint)
	elseif action == "Iw_aim" or action == "E_aim" or action == "X_aim" or action == "Z_aim" then
		-- live aim already stored
	end
end

local function updateHyperspaceStrain(player: Player, dt: number)
	local character = player.Character
	if not character or character:GetAttribute(GameConstants.HERO_ATTRIBUTE) ~= HERO then
		return
	end
	local maxHs = GameConstants.IW_HYPERSPACE_MAX
	local current = character:GetAttribute(GameConstants.IW_HYPERSPACE_ATTRIBUTE)
	if type(current) ~= "number" then
		current = 0
	end
	local locked = character:GetAttribute(GameConstants.IW_HYPERSPACE_LOCK_ATTRIBUTE) == true
	local flying = character:GetAttribute(GameConstants.IS_FLYING_ATTRIBUTE) == true
	if flying and not locked then
		current += GameConstants.IW_HYPERSPACE_FLIGHT_PER_SEC * dt
	else
		current -= GameConstants.IW_HYPERSPACE_DECAY_PER_SEC * dt
	end
	current = math.clamp(current, 0, maxHs)
	character:SetAttribute(GameConstants.IW_HYPERSPACE_ATTRIBUTE, current)
	character:SetAttribute(GameConstants.IW_HYPERSPACE_MAX_ATTRIBUTE, maxHs)
	if not locked and current >= maxHs then
		character:SetAttribute(GameConstants.IW_HYPERSPACE_LOCK_ATTRIBUTE, true)
		HexFlightService.endFlight(player, true)
		return
	end
	if locked and current <= maxHs * GameConstants.IW_HYPERSPACE_WAKE_RATIO then
		character:SetAttribute(GameConstants.IW_HYPERSPACE_LOCK_ATTRIBUTE, nil)
	end
end

function InvisibleWomanService.update(dt: number)
	local dtClamped = math.clamp(dt, 0.001, 0.1)
	local now = os.clock()
	for player, _hold in smashHoldByPlayer do
		local character = player.Character
		if character then
			applySmashLock(character)
		end
	end
	for _, player in Players:GetPlayers() do
		updateHyperspaceStrain(player, dtClamped)
	end

	for player, state in invisByPlayer do
		if not state.character.Parent then
			restoreInvis(player, state.character)
			continue
		end
		local invisDrain = GameConstants.IW_INVIS_ENERGY_PER_SEC * dtClamped
		if state.character:GetAttribute(GameConstants.LOOK_MODE_ATTRIBUTE) == "modern" then
			invisDrain *= 0.75
		end
		if not CharacterService.spendEnergy(state.character, invisDrain) then
			restoreInvis(player, state.character)
		end
	end

	for player, state in pushByPlayer do
		if not state.alive or not state.part.Parent then
			destroyPush(player)
			continue
		end
		local owner = state.owner
		if owner:GetAttribute(GameConstants.RAGDOLLED_ATTRIBUTE) == true then
			destroyPush(player)
			continue
		end
		if not state.launched then
			freezeCasterInPlace(owner, state.casterHoldPos)
			if now < state.launchAt then
				continue
			end
			state.launched = true
			state.bornAt = now
			if owner.Parent then
				owner:SetAttribute(GameConstants.BUSY_ATTRIBUTE, nil)
			end
			restoreMove(owner, state.walk, state.jumpPower, state.jumpHeight, state.autoRotate)
			playWorldSound(GameConstants.IW_PUSH_RELEASE_SOUND, state.part.Position, 0.95)
			local plr = Players:GetPlayerFromCharacter(owner)
			if plr then
				fireCameraShake(plr, 0.46, 0.3, 0.34, 0.55)
			end
		end
		local origin = state.part.Position
		local dir = state.dir
		local nextPos = origin + dir * GameConstants.IW_PUSH_SPEED * dtClamped
		local traveled = (nextPos - origin).Magnitude
		local ownerRoot = getRoot(owner)
		if now - state.bornAt > GameConstants.IW_PUSH_MAX_LIFE then
			destroyPush(player)
			continue
		end
		if ownerRoot and (origin - ownerRoot.Position).Magnitude > GameConstants.IW_PUSH_RANGE then
			destroyPush(player)
			continue
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { owner, state.visual }
		local hit = Workspace:Raycast(origin, dir * math.max(traveled, 1.2), params)
		if hit then
			local otherChar = CombatHelper.getCharacterFromPart(hit.Instance)
			if otherChar and isValidVictim(otherChar, owner) then
				if not state.hit[otherChar] then
					state.hit[otherChar] = true
					CombatHelper.dealDamage(owner, otherChar, GameConstants.IW_PUSH_DAMAGE, origin, "projectile")
					applyStandingPush(otherChar, dir, GameConstants.IW_PUSH_KNOCK_SPEED, GameConstants.IW_PUSH_KNOCK_UP)
				end
			else
				destroyPush(player)
				continue
			end
		end
		local cf = CFrame.lookAt(nextPos, nextPos + dir)
		if state.visual:IsA("Model") then
			state.visual:PivotTo(cf)
		else
			state.part.CFrame = cf
		end
		for _, victim in CombatHelper.overlapCharacters(nextPos, GameConstants.IW_PUSH_HIT_RADIUS, owner) do
			if not state.hit[victim] then
				state.hit[victim] = true
				CombatHelper.dealDamage(owner, victim, GameConstants.IW_PUSH_DAMAGE, nextPos, "projectile")
				applyStandingPush(victim, dir, GameConstants.IW_PUSH_KNOCK_SPEED, GameConstants.IW_PUSH_KNOCK_UP)
			end
		end
	end

	for player, state in areaByPlayer do
		updateArea(player, state, dtClamped)
	end

	for player, state in projectionByPlayer do
		if not state.alive or not state.part.Parent or not state.owner.Parent then
			destroyProjection(player, false)
			continue
		end
		local owner = state.owner
		if owner:GetAttribute(GameConstants.RAGDOLLED_ATTRIBUTE) == true then
			destroyProjection(player, false)
			continue
		end
		if not state.launched then
			freezeCasterInPlace(owner, state.casterHoldPos)
			if now < state.launchAt then
				continue
			end
			state.launched = true
			state.bornAt = now
			restoreProjectionMove(state)
			local plr = Players:GetPlayerFromCharacter(owner)
			if plr then
				fireCameraShake(plr, 0.46, 0.3, 0.34, 0.55)
			end
		end
		local origin = state.part.Position
		local dir = state.dir
		local nextPos = origin + dir * GameConstants.IW_PROJECTION_SPEED * dtClamped
		local traveled = (nextPos - origin).Magnitude
		local ownerRoot = getRoot(owner)
		if now - state.bornAt > GameConstants.IW_PROJECTION_MAX_LIFE then
			destroyProjection(player, false)
			continue
		end
		if ownerRoot and (origin - ownerRoot.Position).Magnitude > GameConstants.IW_PROJECTION_RANGE then
			destroyProjection(player, false)
			continue
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { owner, state.visual }
		local hit = Workspace:Raycast(origin, dir * math.max(traveled, 1.2), params)
		if hit then
			local otherChar = CombatHelper.getCharacterFromPart(hit.Instance)
			if otherChar and isValidVictim(otherChar, owner) then
				if not state.hit[otherChar] then
					state.hit[otherChar] = true
					applyProjectionHit(owner, otherChar, dir, origin)
				end
			else
				destroyProjection(player, false)
				continue
			end
		end
		local cf = CFrame.lookAt(nextPos, nextPos + dir)
		if state.visual:IsA("Model") then
			state.visual:PivotTo(cf)
		else
			state.part.CFrame = cf
		end
		for _, victim in CombatHelper.overlapCharacters(nextPos, GameConstants.IW_PROJECTION_HIT_RADIUS, owner) do
			if not state.hit[victim] then
				state.hit[victim] = true
				applyProjectionHit(owner, victim, dir, nextPos)
			end
		end
	end

	for player, state in crushByPlayer do
		if not state.character.Parent or not state.victim.Parent or not state.vRoot.Parent then
			endCrush(player, true)
			continue
		end
		if now >= state.endsAt then
			endCrush(player, true, true)
			continue
		end
		local hum = CombatHelper.getHumanoid(state.victim)
		if not hum or hum.Health <= 0 then
			endCrush(player, true)
			continue
		end
		local casterRoot = getRoot(state.character)
		if casterRoot and (state.vRoot.Position - casterRoot.Position).Magnitude > GameConstants.IW_CRUSH_RANGE + 8 then
			endCrush(player, true)
			continue
		end
		state.vRoot.AssemblyLinearVelocity = Vector3.zero
		state.vRoot.AssemblyAngularVelocity = Vector3.zero
		local victimHum = CombatHelper.getHumanoid(state.victim)
		if victimHum then
			lockHumanoidMotion(victimHum)
		end
		if tryCrushExecute(state.character, state.victim, state.vRoot) then
			endCrush(player, false)
			continue
		end
		if casterRoot then
			local casterHum = CombatHelper.getHumanoid(state.character)
			if casterHum then
				lockHumanoidMotion(casterHum)
				casterHum.AutoRotate = false
				casterHum:Move(Vector3.zero, false)
			end
			ensureCrushFaceAlign(casterRoot, yawLookAt(casterRoot.Position, state.vRoot.Position))
		end
		if state.fx:IsA("BasePart") then
			state.fx.CFrame = state.vRoot.CFrame
		elseif state.fx:IsA("Model") then
			state.fx:PivotTo(state.vRoot.CFrame)
		end
		state.tickAcc += dtClamped
		if state.tickAcc >= 0.25 then
			local slice = state.tickAcc
			state.tickAcc = 0
			CombatHelper.dealDamage(state.character, state.victim, GameConstants.IW_CRUSH_DAMAGE_PER_SEC * slice, state.holdPos, "beam")
			if tryCrushExecute(state.character, state.victim, state.vRoot) then
				endCrush(player, false)
				continue
			end
			local crushDrain = GameConstants.IW_CRUSH_ENERGY_PER_SEC * slice
			if state.character:GetAttribute(GameConstants.LOOK_MODE_ATTRIBUTE) == "modern" then
				crushDrain *= 0.75
			end
			CharacterService.spendEnergy(state.character, crushDrain)
		end
	end
end

function InvisibleWomanService.init()
	HexFlightService.registerHeroFx(HERO, {
		begin = beginFlightFx,
		finish = endFlightFx,
	})
	Remotes.getEvent("UseAbility").OnServerEvent:Connect(function(player: Player, payload: any)
		InvisibleWomanService.handleAction(player, payload)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		InvisibleWomanService.cancelAll(player)
	end)
	Players.PlayerAdded:Connect(function(player: Player)
		player.CharacterRemoving:Connect(function()
			InvisibleWomanService.cancelAll(player)
		end)
	end)
	for _, player in Players:GetPlayers() do
		player.CharacterRemoving:Connect(function()
			InvisibleWomanService.cancelAll(player)
		end)
	end
end

return InvisibleWomanService
