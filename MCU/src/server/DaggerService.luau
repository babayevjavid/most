--!strict
--[[
	Dagger:
	Q Light Daggers — heal allies / damage others
	E Radiant Bomb — AoE
	F Light Veil — white Highlight on target (particles TBD)
	T Sanctuary — light circle heal/damage zone (particles TBD)
	C Blinding Flash — screen whiteout for foes (particles TBD)
	X Lumen Barrage — 5 light daggers toward cursor
	V Purify — cleanse + 1.5x speed/jump buff 10s (particles TBD)
]]

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local AbilityCooldownHelper = require(ReplicatedStorage.Shared.AbilityCooldownHelper)
local CharacterRegistry = require(ReplicatedStorage.Shared.CharacterRegistry)
local CombatHelper = require(ReplicatedStorage.Shared.CombatHelper)
local FrostStatus = require(ReplicatedStorage.Shared.FrostStatus)
local GameConstants = require(ReplicatedStorage.Shared.GameConstants)
local ProjectileHelper = require(ReplicatedStorage.Shared.ProjectileHelper)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local VfxHelper = require(ReplicatedStorage.Shared.VfxHelper)
local CharacterService = require(script.Parent.CharacterService)
local RagdollService = require(script.Parent.RagdollService)

local DaggerService = {}

type AllyEntry = {
	key: string,
	name: string,
	model: Model,
}

type SanctuaryState = {
	owner: Model,
	player: Player,
	center: Vector3,
	part: BasePart,
	endsAt: number,
}

local alliesByPlayer: { [Player]: { [string]: AllyEntry } } = {}
local sanctuaryByPlayer: { [Player]: SanctuaryState } = {}
local veilTokenByModel: { [Model]: number } = {}

local function daggerColor(): Color3
	return GameConstants.DAGGER_LIGHT
end

local function fireCameraShake(targetPlayer: Player, intensity: number?, duration: number?)
	Remotes.getEvent("CameraShake"):FireClient(targetPlayer, {
		intensity = intensity or 0.55,
		duration = duration or 0.35,
	})
end

local function shakePlayersNear(pos: Vector3, radius: number, intensity: number?, duration: number?)
	for _, model in CombatHelper.overlapCharacters(pos, radius, nil) do
		local plr = Players:GetPlayerFromCharacter(model)
		if plr then
			fireCameraShake(plr, intensity, duration)
		end
	end
end

local function getRoot(model: Model): BasePart?
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end
	return model.PrimaryPart
end

local function getFootPosition(character: Model): Vector3
	local root = getRoot(character)
	if not root then
		return character:GetPivot().Position
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local cast = Workspace:Raycast(root.Position + Vector3.new(0, 1, 0), Vector3.new(0, -12, 0), params)
	if cast then
		return cast.Position + Vector3.new(0, 0.05, 0)
	end
	local hum = CombatHelper.getHumanoid(character)
	local drop = if hum then (hum.HipHeight + root.Size.Y * 0.5) else 3
	return root.Position - Vector3.new(0, drop, 0)
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

local function displayNameFor(model: Model): string
	local plr = Players:GetPlayerFromCharacter(model)
	if plr then
		return plr.DisplayName
	end
	return model.Name
end

local function allyKeyFor(model: Model): string
	local plr = Players:GetPlayerFromCharacter(model)
	if plr then
		return "p:" .. tostring(plr.UserId)
	end
	local existing = model:GetAttribute(GameConstants.DAGGER_ALLY_TAG_ATTRIBUTE)
	if type(existing) == "string" and existing ~= "" then
		return "n:" .. existing
	end
	local tag = HttpService:GenerateGUID(false)
	model:SetAttribute(GameConstants.DAGGER_ALLY_TAG_ATTRIBUTE, tag)
	return "n:" .. tag
end

local function fireAlliesSync(player: Player)
	local map = alliesByPlayer[player]
	local list: { { key: string, name: string } } = {}
	if map then
		for key, entry in map do
			if entry.model.Parent and CombatHelper.getHumanoid(entry.model) then
				table.insert(list, { key = key, name = displayNameFor(entry.model) })
			else
				map[key] = nil
			end
		end
	end
	table.sort(list, function(a, b)
		return a.name < b.name
	end)
	Remotes.getEvent("DaggerAllies"):FireClient(player, list)
end

local function isAllyModel(owner: Model, victim: Model): boolean
	local player = Players:GetPlayerFromCharacter(owner)
	if not player then
		return false
	end
	if victim == owner then
		return true
	end
	local map = alliesByPlayer[player]
	if not map then
		return false
	end
	for _, entry in map do
		if entry.model == victim then
			return true
		end
	end
	return false
end

local function canUse(character: Model, abilityId: string, energyCost: number): boolean
	if character:GetAttribute(GameConstants.HERO_ATTRIBUTE) ~= "dagger" then
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
	if energyCost > 0 and not CharacterService.spendEnergy(character, energyCost) then
		return false
	end
	return true
end

local function finishAbility(character: Model, abilityId: string, cooldown: number)
	AbilityCooldownHelper.setActive(character, abilityId, false)
	AbilityCooldownHelper.applyAfterUse(character, abilityId, cooldown)
	CharacterService.markAbilityUse(character)
end

local function spawnLightDagger(
	character: Model,
	origin: Vector3,
	homeDir: Vector3,
	aimPoint: Vector3?,
	liveAimAttribute: string?
)
	ProjectileHelper.spawn(origin, homeDir, {
		speed = GameConstants.DAGGER_DAGGER_SPEED,
		damage = GameConstants.DAGGER_DAGGER_DAMAGE,
		healAmount = GameConstants.DAGGER_DAGGER_HEAL,
		radius = GameConstants.DAGGER_DAGGER_HIT_RADIUS,
		maxDistance = GameConstants.DAGGER_DAGGER_RANGE,
		owner = character,
		color = daggerColor(),
		homeDir = homeDir,
		homePoint = aimPoint or (origin + homeDir * 50),
		homeAfter = 0,
		seekUntilClose = false,
		liveHomeAimAttribute = liveAimAttribute,
		boltFolder = "Dagger",
		boltAsset = "LightDagger",
		impactFx = "none",
		shouldHeal = isAllyModel,
		ricochetMax = GameConstants.DAGGER_DAGGER_RICOCHET_MAX,
		ricochetSearchRadius = GameConstants.DAGGER_DAGGER_RICOCHET_RANGE,
	})
end

local function resolveAimDir(character: Model, direction: Vector3, aimPoint: Vector3?): Vector3
	local dir = if direction.Magnitude > 0.01 then direction.Unit else character:GetPivot().LookVector
	local root = getRoot(character)
	if aimPoint and root then
		local toAim = aimPoint - root.Position
		if toAim.Magnitude > 0.05 then
			return toAim.Unit
		end
	end
	return dir
end

local function fireLightDagger(player: Player, direction: Vector3, aimPoint: Vector3?)
	local character = player.Character
	if not character then
		return
	end
	local entry = CharacterRegistry.getAbilityById("dagger", "light_daggers")
	if not entry or not canUse(character, entry.id, GameConstants.DAGGER_DAGGER_ENERGY) then
		return
	end

	AbilityCooldownHelper.setActive(character, entry.id, true)
	local homeDir = resolveAimDir(character, direction, aimPoint)
	local hand = getHand(character, true)
	local origin = if hand then hand.Position else character:GetPivot().Position
	spawnLightDagger(character, origin, homeDir, aimPoint)
	-- PARTICLE_PLACEHOLDER: LightDagger cast flash (hand)
	VfxHelper.castHandFlash(origin, daggerColor())
	finishAbility(character, entry.id, GameConstants.DAGGER_DAGGER_COOLDOWN)
end

local function fireRadiantBomb(player: Player, direction: Vector3, aimPoint: Vector3?)
	local character = player.Character
	if not character then
		return
	end
	local entry = CharacterRegistry.getAbilityById("dagger", "radiant_bomb")
	if not entry or not canUse(character, entry.id, GameConstants.DAGGER_BOMB_ENERGY) then
		return
	end

	local originPart = getHand(character, true)
	local origin = if originPart then originPart.Position else character:GetPivot().Position
	local homeDir = resolveAimDir(character, direction, aimPoint)

	AbilityCooldownHelper.setActive(character, entry.id, true)
	-- PARTICLE_PLACEHOLDER: RadiantBomb cast (hand)
	VfxHelper.castHandFlash(origin, daggerColor())

	local aoeR = GameConstants.DAGGER_BOMB_AOE_RADIUS
	ProjectileHelper.spawn(origin, homeDir, {
		speed = GameConstants.DAGGER_BOMB_SPEED,
		damage = GameConstants.DAGGER_BOMB_DAMAGE,
		healAmount = GameConstants.DAGGER_BOMB_HEAL,
		radius = GameConstants.DAGGER_BOMB_HIT_RADIUS,
		maxDistance = GameConstants.DAGGER_BOMB_RANGE,
		owner = character,
		color = daggerColor(),
		homeDir = homeDir,
		homePoint = aimPoint or (origin + homeDir * math.min(60, GameConstants.DAGGER_BOMB_RANGE * 0.7)),
		homeAfter = 0,
		seekUntilClose = true,
		seekCloseDistance = 2.4,
		boltFolder = "Dagger",
		boltAsset = "RadiantBomb",
		impactAoeRadius = aoeR,
		impactAoeDamage = GameConstants.DAGGER_BOMB_DAMAGE,
		impactFx = "dagger_light",
		ragdollOnHit = GameConstants.DAGGER_BOMB_RAGDOLL,
		pushOnHit = true,
		pushSpeed = GameConstants.DAGGER_BOMB_PUSH_SPEED,
		pushUp = GameConstants.DAGGER_BOMB_PUSH_UP,
		shouldHeal = isAllyModel,
		onImpact = function(pos: Vector3)
			shakePlayersNear(pos, aoeR, 0.7, 0.4)
		end,
	})

	finishAbility(character, entry.id, GameConstants.DAGGER_BOMB_COOLDOWN)
end

local function clearLightVeil(target: Model)
	local existing = target:FindFirstChild("DaggerLightVeilHighlight")
	if existing then
		existing:Destroy()
	end
	target:SetAttribute(GameConstants.DAGGER_VEIL_ATTRIBUTE, nil)
	-- PARTICLE_PLACEHOLDER: remove LightVeil body particles on target
end

local function applyLightVeilBuff(target: Model)
	local hum = CombatHelper.getHumanoid(target)
	if not hum or hum.Health <= 0 then
		return
	end
	clearLightVeil(target)

	local hl = Instance.new("Highlight")
	hl.Name = "DaggerLightVeilHighlight"
	hl.FillColor = Color3.fromRGB(255, 255, 255)
	hl.OutlineColor = Color3.fromRGB(255, 255, 255)
	hl.FillTransparency = 0.65
	hl.OutlineTransparency = 0.15
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Adornee = target
	hl.Parent = target

	target:SetAttribute(GameConstants.DAGGER_VEIL_ATTRIBUTE, true)
	-- PARTICLE_PLACEHOLDER: LightVeil wrap particles on target (white)

	local token = (veilTokenByModel[target] or 0) + 1
	veilTokenByModel[target] = token
	task.delay(GameConstants.DAGGER_VEIL_DURATION, function()
		if veilTokenByModel[target] ~= token then
			return
		end
		if target.Parent then
			clearLightVeil(target)
		end
		veilTokenByModel[target] = nil
	end)
end

local function castLightVeil(player: Player, direction: Vector3, aimPoint: Vector3?)
	local character = player.Character
	if not character then
		return
	end
	local entry = CharacterRegistry.getAbilityById("dagger", "light_veil")
	if not entry or not canUse(character, entry.id, GameConstants.DAGGER_VEIL_ENERGY) then
		return
	end

	AbilityCooldownHelper.setActive(character, entry.id, true)
	local homeDir = resolveAimDir(character, direction, aimPoint)
	local hand = getHand(character, true)
	local origin = if hand then hand.Position else character:GetPivot().Position
	-- PARTICLE_PLACEHOLDER: LightVeil cast flash (hand)
	VfxHelper.castHandFlash(origin, daggerColor())

	ProjectileHelper.spawn(origin, homeDir, {
		speed = GameConstants.DAGGER_VEIL_SPEED,
		damage = 0,
		healAmount = 0,
		radius = GameConstants.DAGGER_VEIL_HIT_RADIUS,
		maxDistance = GameConstants.DAGGER_VEIL_RANGE,
		owner = character,
		color = daggerColor(),
		homeDir = homeDir,
		homePoint = aimPoint or (origin + homeDir * 55),
		homeAfter = 0,
		seekUntilClose = false,
		boltFolder = "Dagger",
		boltAsset = "LightDagger",
		impactFx = "none",
		-- Treat hit as buff path (no damage); veil applied in onHit
		shouldHeal = function(_owner: Model, _victim: Model)
			return true
		end,
		onHit = function(victim: Model, _hitPos: Vector3)
			applyLightVeilBuff(victim)
		end,
	})

	finishAbility(character, entry.id, GameConstants.DAGGER_VEIL_COOLDOWN)
end

local function getDaggerAttachmentAsset(assetName: string): Attachment?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local dagger = assets and assets:FindFirstChild("Dagger")
	local inst = dagger and dagger:FindFirstChild(assetName)
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

--[[ Clone attachment onto a BasePart already in Workspace, enable + immediate Emit. ]]
local function attachAndEmitDaggerFx(host: BasePart, assetName: string, emitCount: number?): Attachment?
	local template = getDaggerAttachmentAsset(assetName)
	if not template then
		warn("[DaggerService] Missing ReplicatedStorage.Assets.Dagger." .. assetName)
		return nil
	end
	local att = template:Clone()
	att.Name = assetName
	att.Position = Vector3.zero
	att.Orientation = Vector3.zero
	att.Parent = host
	VfxHelper.tintParticles(att, daggerColor())
	VfxHelper.setParticlesEnabled(att, true)
	VfxHelper.emitAllParticles(att, emitCount or 14)
	return att
end

--[[ Charge rises smoothly from character position into the air. ]]
local function spawnRisingCharge(character: Model, player: Player): (BasePart?, Vector3)
	local root = getRoot(character)
	local startPos = if root then root.Position else character:GetPivot().Position
	local endPos = startPos + Vector3.new(0, GameConstants.DAGGER_FLASH_CHARGE_RISE, 0)

	local host = Instance.new("Part")
	host.Name = "DaggerFlashChargeHost"
	host.Size = Vector3.new(0.3, 0.3, 0.3)
	host.Transparency = 1
	host.Anchored = true
	host.CanCollide = false
	host.CanQuery = false
	host.CanTouch = false
	host.CastShadow = false
	host.CFrame = CFrame.new(startPos)
	host:SetAttribute("OwnerUserId", player.UserId)
	host.Parent = Workspace

	attachAndEmitDaggerFx(host, "Charge", 16)
	TweenService:Create(
		host,
		TweenInfo.new(GameConstants.DAGGER_FLASH_CHARGE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = CFrame.new(endPos) }
	):Play()

	return host, endPos
end

local function fadeDestroyAttachment(att: Attachment?, fade: number?, deleteAfter: number?)
	if not att or not att.Parent then
		return
	end
	VfxHelper.fadeOutAndDestroyParticles({ att }, fade or 0.45, deleteAfter or 1.25)
end

--[[ Face the burst and get shoved outward — no damage / ragdoll. ]]
local function applyFlashStruggle(victim: Model, burstPos: Vector3)
	local vRoot = getRoot(victim)
	local hum = CombatHelper.getHumanoid(victim)
	if not vRoot or not hum or hum.Health <= 0 or vRoot.Anchored then
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
	att.Name = "DaggerFlashStruggleAtt"
	att.Parent = vRoot

	local align = Instance.new("AlignOrientation")
	align.Name = "DaggerFlashStruggleAlign"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = att
	align.RigidityEnabled = false
	align.MaxTorque = 120000
	align.Responsiveness = 14
	align.CFrame = CFrame.lookAt(vRoot.Position, Vector3.new(burstPos.X, vRoot.Position.Y, burstPos.Z))
	align.Parent = vRoot

	-- Soft shove (no Humanoid Physics state / ragdoll)
	local speed = GameConstants.DAGGER_FLASH_PUSH_SPEED
	local up = GameConstants.DAGGER_FLASH_PUSH_UP
	vRoot.AssemblyLinearVelocity = flat * speed + Vector3.new(0, up, 0)

	local origWalk = hum.WalkSpeed
	local origJumpPower = if hum.UseJumpPower then hum.JumpPower else nil
	local origJumpHeight = if not hum.UseJumpPower then hum.JumpHeight else nil
	local origAutoRotate = hum.AutoRotate
	local token = (victim:GetAttribute("DaggerFlashStruggleToken") :: number?) or 0
	token += 1
	victim:SetAttribute("DaggerFlashStruggleToken", token)
	-- Lock movement until push finishes
	hum.WalkSpeed = 0
	hum.AutoRotate = false
	if hum.UseJumpPower then
		hum.JumpPower = 0
	else
		hum.JumpHeight = 0
	end

	task.spawn(function()
		local t0 = os.clock()
		local dur = GameConstants.DAGGER_FLASH_STRUGGLE_TIME
		while os.clock() - t0 < dur do
			if not vRoot.Parent or not victim.Parent then
				break
			end
			if victim:GetAttribute("DaggerFlashStruggleToken") ~= token then
				break
			end
			local elapsed = os.clock() - t0
			local wobble = math.sin(elapsed * 16) * 0.18
			local facePos = Vector3.new(burstPos.X, vRoot.Position.Y, burstPos.Z)
			if (facePos - vRoot.Position).Magnitude > 0.05 then
				align.CFrame = CFrame.lookAt(vRoot.Position, facePos) * CFrame.Angles(wobble * 0.35, wobble, 0)
			end
			-- Keep a struggling outward shove; block player input movement
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
		if hum.Parent and hum.Health > 0 and victim:GetAttribute("DaggerFlashStruggleToken") == token then
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

local function clearFlashChargeHosts(player: Player)
	for _, child in Workspace:GetChildren() do
		if child.Name == "DaggerFlashChargeHost" and child:GetAttribute("OwnerUserId") == player.UserId then
			child:Destroy()
		end
	end
end

local function endSanctuary(player: Player)
	local state = sanctuaryByPlayer[player]
	if not state then
		return
	end
	sanctuaryByPlayer[player] = nil
	if state.part.Parent then
		state.part:Destroy()
	end
end

local function castSanctuary(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local entry = CharacterRegistry.getAbilityById("dagger", "sanctuary")
	if not entry or not canUse(character, entry.id, GameConstants.DAGGER_SANCTUARY_ENERGY) then
		return
	end

	AbilityCooldownHelper.setActive(character, entry.id, true)
	endSanctuary(player)

	local pos = getFootPosition(character)

	-- Foot-level upright host so SanctuaryAttachment sits on the ground
	local host = Instance.new("Part")
	host.Name = "DaggerSanctuaryZone"
	host.Shape = Enum.PartType.Ball
	host.Size = Vector3.new(1, 1, 1)
	host.CFrame = CFrame.new(pos)
	host.Anchored = true
	host.CanCollide = false
	host.CanQuery = false
	host.CanTouch = false
	host.Transparency = 1
	host.Parent = Workspace

	local att = attachAndEmitDaggerFx(host, "SanctuaryAttachment", 18)
	if not att then
		host.Shape = Enum.PartType.Cylinder
		host.Size = Vector3.new(0.2, GameConstants.DAGGER_SANCTUARY_RADIUS * 2, GameConstants.DAGGER_SANCTUARY_RADIUS * 2)
		host.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
		host.Transparency = 0.75
		host.Material = Enum.Material.Neon
		host.Color = Color3.fromRGB(255, 255, 255)
	end

	sanctuaryByPlayer[player] = {
		owner = character,
		player = player,
		center = pos,
		part = host,
		endsAt = os.clock() + GameConstants.DAGGER_SANCTUARY_DURATION,
	}

	finishAbility(character, entry.id, GameConstants.DAGGER_SANCTUARY_COOLDOWN)
end

local function castBlindingFlash(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local entry = CharacterRegistry.getAbilityById("dagger", "blinding_flash")
	if not entry or not canUse(character, entry.id, GameConstants.DAGGER_FLASH_ENERGY) then
		return
	end

	AbilityCooldownHelper.setActive(character, entry.id, true)
	character:SetAttribute(GameConstants.BUSY_ATTRIBUTE, true)

	local root = getRoot(character)
	if not root then
		character:SetAttribute(GameConstants.BUSY_ATTRIBUTE, nil)
		finishAbility(character, entry.id, GameConstants.DAGGER_FLASH_COOLDOWN)
		return
	end

	clearFlashChargeHosts(player)
	local chargeHost, burstPos = spawnRisingCharge(character, player)
	local chargeToken = (character:GetAttribute("DaggerFlashToken") :: number?) or 0
	chargeToken += 1
	character:SetAttribute("DaggerFlashToken", chargeToken)

	task.delay(GameConstants.DAGGER_FLASH_CHARGE_TIME, function()
		local liveBurstPos = burstPos
		if chargeHost and chargeHost.Parent then
			liveBurstPos = chargeHost.Position
			chargeHost:Destroy()
		end
		if not character.Parent or player.Character ~= character then
			return
		end
		if character:GetAttribute("DaggerFlashToken") ~= chargeToken then
			return
		end

		-- Burst at risen charge position
		local burstHost = Instance.new("Part")
		burstHost.Name = "DaggerFlashBurstHost"
		burstHost.Size = Vector3.new(0.3, 0.3, 0.3)
		burstHost.Transparency = 1
		burstHost.Anchored = true
		burstHost.CanCollide = false
		burstHost.CanQuery = false
		burstHost.CanTouch = false
		burstHost.CastShadow = false
		burstHost.CFrame = CFrame.new(liveBurstPos)
		burstHost.Parent = Workspace
		local burstAtt = attachAndEmitDaggerFx(burstHost, "Burst", 24)
		fadeDestroyAttachment(burstAtt, 0.5, 1.4)
		task.delay(1.6, function()
			if burstHost.Parent then
				burstHost:Destroy()
			end
		end)

		local near = CombatHelper.overlapCharacters(liveBurstPos, GameConstants.DAGGER_FLASH_RADIUS, character)
		local blindEvent = Remotes.getEvent("BlindFlash")
		for _, model in near do
			if isAllyModel(character, model) then
				continue
			end
			if model:GetAttribute("LokiUltClone") == true or model:GetAttribute("LokiDecoy") == true then
				continue
			end
			-- No damage / ragdoll — face the burst and struggle-push outward
			applyFlashStruggle(model, liveBurstPos)
			local victimPlayer = Players:GetPlayerFromCharacter(model)
			if victimPlayer then
				fireCameraShake(victimPlayer, 0.85, 0.55)
				blindEvent:FireClient(victimPlayer, {
					duration = GameConstants.DAGGER_FLASH_DURATION,
				})
			end
		end

		character:SetAttribute(GameConstants.BUSY_ATTRIBUTE, nil)
		finishAbility(character, entry.id, GameConstants.DAGGER_FLASH_COOLDOWN)
	end)
end

local function restorePurifyBuff(model: Model, humanoid: Humanoid)
	local origWalk = humanoid:GetAttribute("DaggerPurifyOrigWalk")
	if type(origWalk) == "number" then
		humanoid.WalkSpeed = origWalk
		humanoid:SetAttribute("DaggerPurifyOrigWalk", nil)
	end
	local origJump = humanoid:GetAttribute("DaggerPurifyOrigJump")
	if type(origJump) == "number" then
		if humanoid.UseJumpPower then
			humanoid.JumpPower = origJump
		else
			humanoid.JumpHeight = origJump
		end
		humanoid:SetAttribute("DaggerPurifyOrigJump", nil)
	end
	model:SetAttribute("DaggerPurifyUntil", nil)
	-- PARTICLE_PLACEHOLDER: remove Purify buff particles
end

local function applyPurifyBuff(model: Model)
	local humanoid = CombatHelper.getHumanoid(model)
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	-- Cleanse
	model:SetAttribute(GameConstants.POWERS_DISABLED_UNTIL, nil)
	model:SetAttribute(GameConstants.TORTURE_LOCKED_ATTRIBUTE, nil)
	RagdollService.clear(model)
	FrostStatus.clear(model)

	local token = (model:GetAttribute("DaggerPurifyToken") :: number?) or 0
	token += 1
	model:SetAttribute("DaggerPurifyToken", token)
	model:SetAttribute("DaggerPurifyUntil", AbilityCooldownHelper.getNow() + GameConstants.DAGGER_PURIFY_BUFF_DURATION)

	if humanoid:GetAttribute("DaggerPurifyOrigWalk") == nil then
		humanoid:SetAttribute("DaggerPurifyOrigWalk", humanoid.WalkSpeed)
	end
	local baseWalk = humanoid:GetAttribute("DaggerPurifyOrigWalk") :: number
	humanoid.WalkSpeed = baseWalk * GameConstants.DAGGER_PURIFY_SPEED_MULT

	if humanoid.UseJumpPower then
		if humanoid:GetAttribute("DaggerPurifyOrigJump") == nil then
			humanoid:SetAttribute("DaggerPurifyOrigJump", humanoid.JumpPower)
		end
		local baseJump = humanoid:GetAttribute("DaggerPurifyOrigJump") :: number
		humanoid.JumpPower = baseJump * GameConstants.DAGGER_PURIFY_JUMP_MULT
	else
		if humanoid:GetAttribute("DaggerPurifyOrigJump") == nil then
			humanoid:SetAttribute("DaggerPurifyOrigJump", humanoid.JumpHeight)
		end
		local baseJump = humanoid:GetAttribute("DaggerPurifyOrigJump") :: number
		humanoid.JumpHeight = baseJump * GameConstants.DAGGER_PURIFY_JUMP_MULT
	end

	-- PARTICLE_PLACEHOLDER: Purify buff particles on model (speed aura)

	task.delay(GameConstants.DAGGER_PURIFY_BUFF_DURATION, function()
		if not model.Parent or not humanoid.Parent then
			return
		end
		if model:GetAttribute("DaggerPurifyToken") ~= token then
			return
		end
		restorePurifyBuff(model, humanoid)
	end)
end

local function castPurify(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local entry = CharacterRegistry.getAbilityById("dagger", "purify")
	if not entry or not canUse(character, entry.id, GameConstants.DAGGER_PURIFY_ENERGY) then
		return
	end

	AbilityCooldownHelper.setActive(character, entry.id, true)
	local root = getRoot(character)
	local pos = if root then root.Position else getFootPosition(character)

	-- PurifyingAttachment on caster (HRP), not a custom pulse area
	local host = root
	local ownedHost: BasePart? = nil
	if not host then
		local part = Instance.new("Part")
		part.Name = "DaggerPurifyHost"
		part.Size = Vector3.new(0.4, 0.4, 0.4)
		part.Transparency = 1
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.CFrame = CFrame.new(pos)
		part.Parent = Workspace
		ownedHost = part
		host = part
	end

	local purifyAtt = attachAndEmitDaggerFx(host, "PurifyingAttachment", 22)
	if purifyAtt then
		fadeDestroyAttachment(purifyAtt, 0.55, 1.8)
	else
		warn("[DaggerService] Missing ReplicatedStorage.Assets.Dagger.PurifyingAttachment")
	end
	if ownedHost then
		task.delay(2, function()
			if ownedHost and ownedHost.Parent then
				ownedHost:Destroy()
			end
		end)
	end

	applyPurifyBuff(character)
	for _, model in CombatHelper.overlapCharacters(pos, GameConstants.DAGGER_PURIFY_RADIUS, character) do
		if isAllyModel(character, model) then
			applyPurifyBuff(model)
		end
	end

	finishAbility(character, entry.id, GameConstants.DAGGER_PURIFY_COOLDOWN)
end

local function castLumenBarrage(player: Player, direction: Vector3, aimPoint: Vector3?)
	local character = player.Character
	if not character then
		return
	end
	local entry = CharacterRegistry.getAbilityById("dagger", "lumen_barrage")
	if not entry or not canUse(character, entry.id, GameConstants.DAGGER_BARRAGE_ENERGY) then
		return
	end

	AbilityCooldownHelper.setActive(character, entry.id, true)
	if aimPoint then
		character:SetAttribute("DaggerBarrageAim", aimPoint)
	end

	task.spawn(function()
		for i = 1, GameConstants.DAGGER_BARRAGE_COUNT do
			if not character.Parent or player.Character ~= character then
				break
			end
			local liveAim = character:GetAttribute("DaggerBarrageAim")
			local shotAim: Vector3? = if typeof(liveAim) == "Vector3" then liveAim else aimPoint
			local homeDir = resolveAimDir(character, direction, shotAim)
			local preferRight = (i % 2) == 1
			local hand = getHand(character, preferRight)
			local origin = if hand then hand.Position else character:GetPivot().Position
			-- slight spread so the 5 shots aren't perfectly stacked
			local spread = ((i - 3) * 0.04)
			local right = homeDir:Cross(Vector3.yAxis)
			if right.Magnitude < 0.05 then
				right = homeDir:Cross(Vector3.xAxis)
			end
			right = right.Unit
			local shotDir = (homeDir + right * spread)
			if shotDir.Magnitude > 0.01 then
				shotDir = shotDir.Unit
			else
				shotDir = homeDir
			end
			-- Home to live mouse aim (updated via X_aim while barrage is active)
			spawnLightDagger(character, origin, shotDir, shotAim, "DaggerBarrageAim")
			if i < GameConstants.DAGGER_BARRAGE_COUNT then
				task.wait(GameConstants.DAGGER_BARRAGE_SPACING)
			end
		end
		if character.Parent then
			character:SetAttribute("DaggerBarrageAim", nil)
			if AbilityCooldownHelper.isActive(character, entry.id) then
				finishAbility(character, entry.id, GameConstants.DAGGER_BARRAGE_COOLDOWN)
			end
		end
	end)
end

local function addAlly(player: Player, target: Model?)
	if not target or not target.Parent then
		return
	end
	local character = player.Character
	if not character or character:GetAttribute(GameConstants.HERO_ATTRIBUTE) ~= "dagger" then
		return
	end
	if target == character then
		return
	end
	local humanoid = CombatHelper.getHumanoid(target)
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	if target:GetAttribute("LokiUltClone") == true or target:GetAttribute("LokiDecoy") == true then
		return
	end
	if target:GetAttribute("FearVisual") == true or target.Name == "FearClone" then
		return
	end

	local map = alliesByPlayer[player]
	if not map then
		map = {}
		alliesByPlayer[player] = map
	end
	local key = allyKeyFor(target)
	map[key] = {
		key = key,
		name = displayNameFor(target),
		model = target,
	}
	fireAlliesSync(player)
end

local function removeAlly(player: Player, key: string?)
	if type(key) ~= "string" or key == "" then
		return
	end
	local map = alliesByPlayer[player]
	if not map then
		return
	end
	map[key] = nil
	fireAlliesSync(player)
end

function DaggerService.clearAllies(player: Player)
	alliesByPlayer[player] = nil
	fireAlliesSync(player)
end

function DaggerService.cancelAll(player: Player)
	endSanctuary(player)
	clearFlashChargeHosts(player)
	local character = player.Character
	if character then
		character:SetAttribute(GameConstants.BUSY_ATTRIBUTE, nil)
		character:SetAttribute("DaggerFlashToken", nil)
		character:SetAttribute("DaggerBarrageAim", nil)
		for _, name in { "Charge", "Burst", "DaggerFlashStruggleAlign", "DaggerFlashStruggleAtt" } do
			local fx = character:FindFirstChild(name, true)
			if fx then
				fx:Destroy()
			end
		end
		AbilityCooldownHelper.setActive(character, "light_daggers", false)
		AbilityCooldownHelper.setActive(character, "radiant_bomb", false)
		AbilityCooldownHelper.setActive(character, "light_veil", false)
		AbilityCooldownHelper.setActive(character, "sanctuary", false)
		AbilityCooldownHelper.setActive(character, "blinding_flash", false)
		AbilityCooldownHelper.setActive(character, "lumen_barrage", false)
		AbilityCooldownHelper.setActive(character, "purify", false)
	end
end

function DaggerService.handleAction(player: Player, payload: any)
	if type(payload) ~= "table" then
		return
	end
	local character = player.Character
	if not character or character:GetAttribute(GameConstants.HERO_ATTRIBUTE) ~= "dagger" then
		return
	end

	local action = payload.action
	if type(action) ~= "string" then
		return
	end

	local direction = if typeof(payload.direction) == "Vector3" then payload.direction else Vector3.new(0, 0, -1)
	local aimPoint = if typeof(payload.aimPoint) == "Vector3" then payload.aimPoint else nil
	local targetModel = if typeof(payload.target) == "Instance" and payload.target:IsA("Model")
		then payload.target
		else nil

	if action == "Q" then
		fireLightDagger(player, direction, aimPoint)
	elseif action == "E" or action == "E_down" then
		fireRadiantBomb(player, direction, aimPoint)
	elseif action == "F" then
		castLightVeil(player, direction, aimPoint)
	elseif action == "T" or action == "T_down" then
		castSanctuary(player)
	elseif action == "C" or action == "C_down" then
		castBlindingFlash(player)
	elseif action == "X" then
		castLumenBarrage(player, direction, aimPoint)
	elseif action == "X_aim" then
		if AbilityCooldownHelper.isActive(character, "lumen_barrage") and aimPoint then
			character:SetAttribute("DaggerBarrageAim", aimPoint)
		end
	elseif action == "V" then
		castPurify(player)
	elseif action == "AllyAdd" then
		addAlly(player, targetModel)
	elseif action == "AllyRemove" then
		removeAlly(player, if type(payload.key) == "string" then payload.key else nil)
	elseif action == "AllyRefresh" then
		fireAlliesSync(player)
	end
end

function DaggerService.update(dt: number)
	local now = os.clock()
	local dtClamped = math.clamp(dt, 0, 0.2)

	for player, state in sanctuaryByPlayer do
		if now >= state.endsAt or not state.owner.Parent or player.Character ~= state.owner then
			endSanctuary(player)
			continue
		end
		if not state.part.Parent then
			endSanctuary(player)
			continue
		end

		local near = CombatHelper.overlapCharacters(state.center, GameConstants.DAGGER_SANCTUARY_RADIUS, nil)
		for _, model in near do
			if model:GetAttribute("LokiUltClone") == true or model:GetAttribute("LokiDecoy") == true then
				continue
			end
			if isAllyModel(state.owner, model) then
				CombatHelper.heal(model, GameConstants.DAGGER_SANCTUARY_HEAL_PER_SEC * dtClamped)
			elseif model ~= state.owner then
				CombatHelper.dealDamage(
					state.owner,
					model,
					GameConstants.DAGGER_SANCTUARY_DAMAGE_PER_SEC * dtClamped,
					state.center,
					"projectile"
				)
			end
		end
	end
end

function DaggerService.init()
	Remotes.getEvent("DaggerAllies")
	Remotes.getEvent("BlindFlash")
	Remotes.getEvent("CameraShake")
	Remotes.getEvent("UseAbility").OnServerEvent:Connect(function(player: Player, payload: any)
		DaggerService.handleAction(player, payload)
	end)

	local function hookPlayer(player: Player)
		player.CharacterRemoving:Connect(function()
			DaggerService.cancelAll(player)
			DaggerService.clearAllies(player)
		end)
		player.CharacterAdded:Connect(function(character)
			DaggerService.cancelAll(player)
			DaggerService.clearAllies(player)
			local humanoid = character:WaitForChild("Humanoid", 5)
			if humanoid and humanoid:IsA("Humanoid") then
				humanoid.Died:Connect(function()
					DaggerService.cancelAll(player)
				end)
			end
		end)
	end

	for _, player in Players:GetPlayers() do
		hookPlayer(player)
	end
	Players.PlayerAdded:Connect(hookPlayer)
	Players.PlayerRemoving:Connect(function(player)
		DaggerService.cancelAll(player)
		alliesByPlayer[player] = nil
	end)
end

return DaggerService
