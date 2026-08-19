--!strict
--[[
	Hold E on cursor target to lift; target follows mouse at scrollable hold distance.
	Click to throw away from caster; release E to drop.
	Modes: Single, Multiple, Torture (locks caster walk, damages while held, head VFX).
	Held targets get Ragdolled status; release clears after 0.5s, throw after 3s.
	On ground, caster faces the lifted target. During flight, HexFlight owns rotation.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AbilityCooldownHelper = require(ReplicatedStorage.Shared.AbilityCooldownHelper)
local CombatHelper = require(ReplicatedStorage.Shared.CombatHelper)
local GameConstants = require(ReplicatedStorage.Shared.GameConstants)
local PushHelper = require(ReplicatedStorage.Shared.PushHelper)
local ScreenFeelHelper = require(ReplicatedStorage.Shared.ScreenFeelHelper)
local VfxHelper = require(ReplicatedStorage.Shared.VfxHelper)
local CharacterService = require(script.Parent.CharacterService)
local HandParticleHelper = require(script.Parent.HandParticleHelper)
local RagdollService = require(script.Parent.RagdollService)
local LokiService = require(script.Parent.LokiService)

local TelekinesisService = {}

type HeldTarget = {
	root: BasePart,
	model: Model,
	humanoid: Humanoid,
	align: AlignPosition?,
	attach: Attachment?,
	offsetFromAnchor: Vector3,
	ownerParts: { BasePart },
	particles: { Instance },
	tortureHeadAtt: Instance?,
}

type TkState = {
	character: Model,
	casterRoot: BasePart,
	casterHumanoid: Humanoid,
	held: { HeldTarget },
	isMass: boolean,
	isTorture: boolean,
	cursorWorld: Vector3,
	holdDistance: number,
	smoothedHoldPoint: Vector3,
	lastDrain: number,
	lastTortureDamage: number,
	throwing: boolean,
	startedAt: number,
	faceAlign: AlignOrientation?,
	faceAttach: Attachment?,
	savedAutoRotate: boolean,
	savedWalkSpeed: number?,
	savedJumpPower: number?,
	savedJumpHeight: number?,
	casterWalkLocked: boolean,
	animTrack: AnimationTrack?,
}

local tkByPlayer: { [Player]: TkState } = {}

local function playTkAnim(character: Model, assetId: string, looped: boolean?): AnimationTrack?
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
	track.Priority = Enum.AnimationPriority.Action4
	track.Looped = looped == true
	track:Play(0.08, 1, 1)
	return track
end

local function stopTkHoldAnim(state: TkState)
	if state.animTrack then
		state.animTrack:Stop(0.12)
		state.animTrack:Destroy()
		state.animTrack = nil
	end
end

function TelekinesisService.playThrowAnim(character: Model)
	playTkAnim(character, GameConstants.MG_PSI_BOLT_ANIM, false)
end

local function getMode(_character: Model): string
	return "Single"
end

local function lockCasterWalk(state: TkState)
	local humanoid = state.casterHumanoid
	if not humanoid.Parent then
		return
	end
	if not state.casterWalkLocked then
		state.savedWalkSpeed = humanoid.WalkSpeed
		state.savedJumpPower = humanoid.JumpPower
		local jumpH: number? = nil
		pcall(function()
			jumpH = humanoid.JumpHeight
		end)
		state.savedJumpHeight = jumpH
		state.casterWalkLocked = true
	end
	humanoid.WalkSpeed = GameConstants.TK_HOLD_WALK_SPEED
	humanoid.JumpPower = 0
	pcall(function()
		humanoid.JumpHeight = 0
	end)
	pcall(function()
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	end)
end

local function unlockCasterWalk(state: TkState)
	if not state.casterWalkLocked then
		return
	end
	state.casterWalkLocked = false
	local humanoid = state.casterHumanoid
	if not humanoid.Parent then
		return
	end
	if type(state.savedWalkSpeed) == "number" then
		humanoid.WalkSpeed = state.savedWalkSpeed
	end
	if type(state.savedJumpPower) == "number" then
		humanoid.JumpPower = state.savedJumpPower
	end
	if type(state.savedJumpHeight) == "number" then
		pcall(function()
			humanoid.JumpHeight = state.savedJumpHeight :: number
		end)
	end
	pcall(function()
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
	end)
	state.savedWalkSpeed = nil
	state.savedJumpPower = nil
	state.savedJumpHeight = nil
end

local function attachTortureHead(model: Model): Instance?
	local head = model:FindFirstChild("Head")
	if not (head and head:IsA("BasePart")) then
		return nil
	end
	local template = VfxHelper.getScarletAsset("TortureHeadAttachment")
	if not template then
		warn("[Telekinesis] Missing Assets.ScarletWitch.TortureHeadAttachment")
		return nil
	end
	local clone: Instance
	if template:IsA("Attachment") then
		clone = template:Clone()
	else
		local nested = template:FindFirstChildWhichIsA("Attachment", true)
		if nested then
			clone = nested:Clone()
		else
			clone = template:Clone()
		end
	end
	clone.Name = "TortureHeadAttachment"
	clone.Parent = head
	VfxHelper.setParticlesEnabled(clone, true)
	VfxHelper.emitAllParticles(clone, 8)
	return clone
end

local function clearTortureHead(target: HeldTarget)
	if target.tortureHeadAtt and target.tortureHeadAtt.Parent then
		VfxHelper.setParticlesEnabled(target.tortureHeadAtt, false)
		target.tortureHeadAtt:Destroy()
	end
	target.tortureHeadAtt = nil
end

local function createHoldAlign(root: BasePart, initialPos: Vector3): (AlignPosition, Attachment)
	local att = Instance.new("Attachment")
	att.Name = "TKHoldAttachment"
	att.Parent = root
	local align = Instance.new("AlignPosition")
	align.Name = "TKHoldAlign"
	align.Mode = Enum.PositionAlignmentMode.OneAttachment
	align.Attachment0 = att
	align.RigidityEnabled = false
	align.Responsiveness = GameConstants.TK_HOLD_ALIGN_RESPONSIVENESS
	align.MaxForce = GameConstants.TK_HOLD_MAX_FORCE
	align.MaxVelocity = GameConstants.TK_HOLD_SPEED
	-- Pull at the grabbed body part
	align.ApplyAtCenterOfMass = true
	align.Position = initialPos
	align.Parent = root
	return align, att
end

local function isAccessoryPart(part: BasePart): boolean
	local parent = part.Parent
	return parent ~= nil and parent:IsA("Accessory")
end

local function resolveGrabPart(model: Model, _preferred: BasePart?): BasePart
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end
	local torso = model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso")
	if torso and torso:IsA("BasePart") then
		return torso
	end
	if model.PrimaryPart then
		return model.PrimaryPart
	end
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and not isAccessoryPart(child) then
			return child
		end
	end
	error("character has no grab part")
end

local function clearTkParticles(target: HeldTarget)
	if #target.particles > 0 then
		VfxHelper.fadeOutAndDestroyParticles(target.particles, 0.45, 2.5)
	end
	table.clear(target.particles)
end

local function attachTkParticles(model: Model): { Instance }
	return VfxHelper.attachTelekinesisParticles(model)
end

local function createFaceAlign(root: BasePart): (AlignOrientation, Attachment)
	local att = root:FindFirstChild("TKCasterFaceAttachment")
	if not (att and att:IsA("Attachment")) then
		att = Instance.new("Attachment")
		att.Name = "TKCasterFaceAttachment"
		att.Parent = root
	end
	local align = Instance.new("AlignOrientation")
	align.Name = "TKCasterFaceAlign"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = att
	align.MaxTorque = math.huge
	align.Responsiveness = 22
	align.CFrame = root.CFrame
	align.Parent = root
	return align, att :: Attachment
end

local function setServerOwnership(model: Model): { BasePart }
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

local function restoreOwnership(model: Model, parts: { BasePart })
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

--[[ Pull in, then fling toward cursor. Shared by Wanda throw and Jean push. ]]
function TelekinesisService.launchVictim(
	caster: Model,
	victim: Model,
	direction: Vector3?,
	aimPoint: Vector3?,
	onLaunch: ((root: BasePart) -> ())?,
	speedMul: number?,
	onDone: (() -> ())?
)
	local casterRoot = caster:FindFirstChild("HumanoidRootPart") :: BasePart?
	local vRoot = victim:FindFirstChild("HumanoidRootPart") :: BasePart?
	local vHum = CombatHelper.getHumanoid(victim)
	if not casterRoot or not vRoot or not vHum then
		if onDone then
			onDone()
		end
		return
	end

	ScreenFeelHelper.setSpeedFov(victim, true)
	local ownedParts = setServerOwnership(victim)
	local mul = if type(speedMul) == "number" then speedMul else 1
	local token = (victim:GetAttribute("TkLaunchToken") :: number?) or 0
	token += 1
	victim:SetAttribute("TkLaunchToken", token)

	local att = Instance.new("Attachment")
	att.Name = "TkLaunchDrawAtt"
	att.Parent = vRoot
	local align = Instance.new("AlignPosition")
	align.Name = "TkLaunchDrawPos"
	align.Mode = Enum.PositionAlignmentMode.OneAttachment
	align.Attachment0 = att
	align.ApplyAtCenterOfMass = true
	align.RigidityEnabled = false
	align.MaxForce = GameConstants.MG_PULL_MAX_FORCE
	align.MaxVelocity = 58
	align.Responsiveness = 18
	align.Parent = vRoot

	local origWalk = vHum.WalkSpeed
	local origAutoRotate = vHum.AutoRotate
	vHum.WalkSpeed = 0
	vHum.AutoRotate = false

	local drawTime = GameConstants.MG_PUSH_DRAW_TIME
	local holdDist = GameConstants.MG_PUSH_DRAW_DIST
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < drawTime do
			if not victim.Parent or not vRoot.Parent or not casterRoot.Parent or victim:GetAttribute("TkLaunchToken") ~= token then
				break
			end
			local away = vRoot.Position - casterRoot.Position
			local flat = Vector3.new(away.X, 0, away.Z)
			if flat.Magnitude < 0.08 then
				local look = Vector3.new(casterRoot.CFrame.LookVector.X, 0, casterRoot.CFrame.LookVector.Z)
				flat = if look.Magnitude > 0.05 then look else Vector3.new(0, 0, -1)
			end
			align.Position = casterRoot.Position + flat.Unit * holdDist + Vector3.new(0, 2.2, 0)
			vRoot.AssemblyAngularVelocity = Vector3.zero
			vHum:Move(Vector3.zero, false)
			task.wait()
		end

		if align.Parent then
			align:Destroy()
		end
		if att.Parent then
			att:Destroy()
		end

		if not victim.Parent or not vRoot.Parent or victim:GetAttribute("TkLaunchToken") ~= token then
			restoreOwnership(victim, ownedParts)
			if vHum.Parent then
				vHum.WalkSpeed = origWalk
				vHum.AutoRotate = origAutoRotate
			end
			if victim.Parent then
				ScreenFeelHelper.setSpeedFov(victim, false)
			end
			if onDone then
				onDone()
			end
			return
		end

		local fromPos = vRoot.Position
		local casterLook = Vector3.new(casterRoot.CFrame.LookVector.X, 0, casterRoot.CFrame.LookVector.Z)
		local fallbackAim = aimPoint
		if typeof(fallbackAim) ~= "Vector3" then
			local look = if direction and direction.Magnitude > 0.05 then direction.Unit else casterRoot.CFrame.LookVector
			fallbackAim = fromPos + look * 90
		elseif (fallbackAim - fromPos).Magnitude < 10 then
			local look = if direction and direction.Magnitude > 0.05 then direction.Unit else casterRoot.CFrame.LookVector
			fallbackAim = fromPos + look * 90
		end
		local launch = PushHelper.launchTowardCursor(fromPos, fallbackAim, casterLook)
		RagdollService.applyTimed(victim, GameConstants.MG_PUSH_RAGDOLL_TIME)
		RagdollService.markTelekineticLand(victim)
		pcall(function()
			vRoot:SetNetworkOwner(nil)
		end)
		if onLaunch then
			onLaunch(vRoot)
		end
		PushHelper.telekineticFling(
			victim,
			vRoot,
			launch,
			GameConstants.MG_PUSH_SPEED * mul,
			GameConstants.MG_PUSH_UP
		)

		task.delay(GameConstants.MG_PUSH_RAGDOLL_TIME, function()
			restoreOwnership(victim, ownedParts)
			if vHum.Parent and vHum.Health > 0 then
				vHum.WalkSpeed = origWalk
				vHum.AutoRotate = origAutoRotate
			end
			if victim.Parent then
				ScreenFeelHelper.setSpeedFov(victim, false)
			end
			if onDone then
				onDone()
			end
		end)
	end)
end

local function applyTargetRagdoll(target: HeldTarget, isTorture: boolean?)
	-- Same as NewMarvel: attribute drives RagdollService physics
	target.model:SetAttribute("TelekinesisHeld", true)
	target.model:SetAttribute("Ragdolled", true)
	if isTorture then
		target.model:SetAttribute(GameConstants.TORTURE_LOCKED_ATTRIBUTE, true)
	end
	target.humanoid.AutoRotate = false
	pcall(function()
		target.humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	end)
	target.ownerParts = setServerOwnership(target.model)
	target.root.AssemblyLinearVelocity = Vector3.zero
	target.root.AssemblyAngularVelocity = Vector3.zero
end

local function destroyHold(target: HeldTarget, keepServerOwnership: boolean?)
	clearTortureHead(target)
	clearTkParticles(target)
	if target.align then
		target.align:Destroy()
		target.align = nil
	end
	if target.attach then
		target.attach:Destroy()
		target.attach = nil
	end
	if not keepServerOwnership then
		restoreOwnership(target.model, target.ownerParts or {})
	end
	target.model:SetAttribute("TelekinesisHeld", nil)
	target.model:SetAttribute(GameConstants.TORTURE_LOCKED_ATTRIBUTE, nil)
end

local function destroyCasterFace(state: TkState, restoreAutoRotate: boolean?)
	if state.faceAlign then
		state.faceAlign:Destroy()
		state.faceAlign = nil
	end
	if state.faceAttach then
		state.faceAttach:Destroy()
		state.faceAttach = nil
	end
	if restoreAutoRotate ~= false and state.casterHumanoid.Parent then
		local flying = state.character.Parent
			and state.character:GetAttribute(GameConstants.IS_FLYING_ATTRIBUTE) == true
		if not flying then
			state.casterHumanoid.AutoRotate = true
		end
	end
end

local function endTelekinesis(player: Player, applyCooldown: boolean?, ragdollClearDelay: number?)
	local state = tkByPlayer[player]
	if not state then
		-- Clear sticky attribute if present without state
		local char = player.Character
		if char then
			char:SetAttribute(GameConstants.TK_ACTIVE_ATTRIBUTE, nil)
			AbilityCooldownHelper.setActive(char, "telekinesis", false)
		end
		return
	end
	tkByPlayer[player] = nil

	unlockCasterWalk(state)
	destroyCasterFace(state)
	stopTkHoldAnim(state)
	if state.casterRoot and state.casterRoot.Parent then
		for _, name in { "TKCasterFaceAlign", "TKCasterFaceAttachment" } do
			local inst = state.casterRoot:FindFirstChild(name)
			if inst then
				inst:Destroy()
			end
		end
	end

	local clearDelay = ragdollClearDelay
	for _, target in state.held do
		local model = target.model
		destroyHold(target)
		if model.Parent then
			if clearDelay and clearDelay > 0 then
				RagdollService.applyTimed(model, clearDelay)
			else
				RagdollService.clear(model)
			end
		end
	end

	if state.character.Parent then
		state.character:SetAttribute(GameConstants.TK_ACTIVE_ATTRIBUTE, nil)
		AbilityCooldownHelper.setActive(state.character, "telekinesis", false)
		if state.character:GetAttribute(GameConstants.HERO_ATTRIBUTE) == "scarlet_witch" then
			HandParticleHelper.endUse(state.character)
		end
		if applyCooldown then
			AbilityCooldownHelper.applyAfterUse(state.character, "telekinesis", GameConstants.TK_COOLDOWN)
			CharacterService.markAbilityUse(state.character)
		end
	end
end

local function gatherMass(
	caster: Model,
	center: Vector3,
	primaryModel: Model?,
	primaryPart: BasePart?
): { HeldTarget }
	local results: { HeldTarget } = {}
	local seen: { [Model]: boolean } = {}
	for _, model in CombatHelper.overlapCharacters(center, GameConstants.TK_MASS_RADIUS, caster) do
		if seen[model] or CombatHelper.isShielded(model) then
			continue
		end
		local root = resolveGrabPart(model, primaryPart)
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0 then
			seen[model] = true
			table.insert(results, {
				root = root,
				model = model,
				humanoid = humanoid,
				align = nil,
				attach = nil,
				offsetFromAnchor = root.Position - center,
				ownerParts = {},
				particles = {},
				tortureHeadAtt = nil,
			})
		end
	end
	return results
end

local function getHeldFocusPosition(state: TkState): Vector3?
	if #state.held == 0 then
		return nil
	end
	local sum = Vector3.zero
	local n = 0
	for _, target in state.held do
		if target.root.Parent then
			sum += target.root.Position
			n += 1
		end
	end
	if n == 0 then
		return nil
	end
	return sum / n
end

local function resolveSingleTarget(
	character: Model,
	casterRoot: BasePart,
	cursorWorld: Vector3,
	hitCharacter: Model?,
	hitPart: BasePart?,
	lockOn: boolean?
): (Model?, BasePart?)
	local target = hitCharacter
	local preferredPart = hitPart
	if preferredPart and not target then
		target = CombatHelper.getCharacterFromPart(preferredPart)
	end
	if target and target.Parent and target ~= character then
		local hum = target:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 and not CombatHelper.isShielded(target) then
			local grab = resolveGrabPart(target, preferredPart)
			if grab and (grab.Position - casterRoot.Position).Magnitude <= GameConstants.TK_RANGE then
				return target, grab
			end
		end
	end
	if lockOn ~= true then
		return nil, nil
	end

	local toCursor = cursorWorld - casterRoot.Position
	local dir = if toCursor.Magnitude > 0.05 then toCursor.Unit else casterRoot.CFrame.LookVector
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local result = workspace:Raycast(casterRoot.Position, dir * GameConstants.TK_RANGE, params)
	if result and result.Instance:IsA("BasePart") then
		local model = CombatHelper.getCharacterFromPart(result.Instance)
		if model and not CombatHelper.isShielded(model) then
			local hum = model:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				return model, resolveGrabPart(model, result.Instance)
			end
		end
	end
	local near = CombatHelper.overlapCharacters(cursorWorld, 4, character)
	for _, model in near do
		if not CombatHelper.isShielded(model) then
			local grab = resolveGrabPart(model, nil)
			if grab and (grab.Position - casterRoot.Position).Magnitude <= GameConstants.TK_RANGE then
				return model, grab
			end
		end
	end
	return nil, nil
end

function TelekinesisService.tryStart(player: Player, cursorWorld: Vector3, hitCharacter: Model?, hitPart: BasePart?, lockOn: boolean?): boolean
	if tkByPlayer[player] then
		return false
	end
	local character = player.Character
	if not character then
		return false
	end
	local heroId = character:GetAttribute(GameConstants.HERO_ATTRIBUTE)
	if heroId ~= "scarlet_witch" and heroId ~= "jean_grey" then
		return false
	end
	if heroId == "scarlet_witch" and character:GetAttribute(GameConstants.IS_FLYING_ATTRIBUTE) == true then
		return false
	end
	if CombatHelper.arePowersDisabled(character) then
		return false
	end
	if character:GetAttribute(GameConstants.SHIELD_ACTIVE_ATTRIBUTE) == true then
		return false
	end
	if character:GetAttribute(GameConstants.BUSY_ATTRIBUTE) == true then
		return false
	end
	if AbilityCooldownHelper.hasBlockingActive(character, "telekinesis") then
		return false
	end
	if AbilityCooldownHelper.isOnCooldown(character, "telekinesis") then
		return false
	end

	-- Clear sticky active flag from a failed prior session
	if character:GetAttribute(GameConstants.TK_ACTIVE_ATTRIBUTE) == true then
		character:SetAttribute(GameConstants.TK_ACTIVE_ATTRIBUTE, nil)
		AbilityCooldownHelper.setActive(character, "telekinesis", false)
	end

	local casterRoot = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local casterHumanoid = character:FindFirstChildOfClass("Humanoid")
	if not casterRoot or not casterHumanoid then
		return false
	end

	local energy = character:GetAttribute(GameConstants.ENERGY_ATTRIBUTE)
	local mode = getMode(character)
	local isTorture = mode == "Torture"
	if isTorture and character:GetAttribute(GameConstants.IS_FLYING_ATTRIBUTE) == true then
		return false
	end
	local startCost = if isTorture then GameConstants.TK_TORTURE_ENERGY_DRAIN else GameConstants.TK_ENERGY_DRAIN
	if type(energy) ~= "number" or energy < startCost then
		return false
	end

	local isMass = mode == "Multiple"
	local held: { HeldTarget } = {}

	if isMass then
		local primary = hitCharacter
		if hitPart and not primary then
			primary = CombatHelper.getCharacterFromPart(hitPart)
		end
		held = gatherMass(character, cursorWorld, primary, hitPart)
		do
			local filtered: { HeldTarget } = {}
			for _, target in held do
				if LokiService.tryReflect(character, target.model, "telekinesis") then
					continue
				end
				table.insert(filtered, target)
			end
			held = filtered
		end
		if #held == 0 then
			return false
		end
	else
		local target, grabPart = resolveSingleTarget(character, casterRoot, cursorWorld, hitCharacter, hitPart, lockOn)
		if not target or not grabPart then
			return false
		end
		local humanoid = target:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			return false
		end
		-- Loki Reflect Shield: bounce TK / Torture back onto caster
		local reflectKind = if isTorture then "torture" else "telekinesis"
		if LokiService.tryReflect(character, target, reflectKind) then
			return false
		end
		grabPart = resolveGrabPart(target, nil)
		table.insert(held, {
			root = grabPart,
			model = target,
			humanoid = humanoid,
			align = nil,
			attach = nil,
			offsetFromAnchor = Vector3.zero,
			ownerParts = {},
			particles = {},
			tortureHeadAtt = nil,
		})
	end

	local startDrain = startCost
	if not CharacterService.spendEnergy(character, startDrain) then
		return false
	end

	local holdDist = math.clamp(
		(cursorWorld - casterRoot.Position).Magnitude,
		GameConstants.TK_HOLD_DIST_MIN,
		GameConstants.TK_HOLD_DIST_MAX
	)
	local toCursor = cursorWorld - casterRoot.Position
	local holdPoint = if toCursor.Magnitude > 0.05
		then casterRoot.Position + toCursor.Unit * holdDist
		else casterRoot.Position + casterRoot.CFrame.LookVector * holdDist
	if isTorture then
		holdPoint = holdPoint + Vector3.new(0, GameConstants.TK_TORTURE_LIFT_HEIGHT, 0)
	end

	local isFlying = character:GetAttribute(GameConstants.IS_FLYING_ATTRIBUTE) == true
	local savedAutoRotate = casterHumanoid.AutoRotate
	local faceAlign: AlignOrientation? = nil
	local faceAttach: Attachment? = nil
	if not isFlying then
		casterHumanoid.AutoRotate = false
		faceAlign, faceAttach = createFaceAlign(casterRoot)
	end

	-- Register state first so release/throw always have something to clean up
	local state: TkState = {
		character = character,
		casterRoot = casterRoot,
		casterHumanoid = casterHumanoid,
		held = held,
		isMass = isMass,
		isTorture = isTorture,
		cursorWorld = cursorWorld,
		holdDistance = holdDist,
		smoothedHoldPoint = holdPoint,
		lastDrain = os.clock(),
		lastTortureDamage = 0,
		throwing = false,
		startedAt = os.clock(),
		faceAlign = faceAlign,
		faceAttach = faceAttach,
		savedAutoRotate = savedAutoRotate,
		savedWalkSpeed = nil,
		savedJumpPower = nil,
		savedJumpHeight = nil,
		casterWalkLocked = false,
		animTrack = nil,
	}
	tkByPlayer[player] = state

	AbilityCooldownHelper.setActive(character, "telekinesis", true)
	if heroId == "scarlet_witch" then
		HandParticleHelper.beginUse(character)
		state.animTrack = playTkAnim(character, GameConstants.SW_TELEKINESIS_ANIM, true)
	elseif heroId == "jean_grey" then
		state.animTrack = playTkAnim(character, GameConstants.MG_TELEKINESIS_ANIM, true)
	end
	character:SetAttribute(GameConstants.TK_ACTIVE_ATTRIBUTE, true)

	if character:GetAttribute(GameConstants.IS_FLYING_ATTRIBUTE) ~= true then
		lockCasterWalk(state)
	end

	for _, target in held do
		local ok, err = pcall(function()
			applyTargetRagdoll(target, isTorture)
			local align, att = createHoldAlign(target.root, holdPoint + target.offsetFromAnchor)
			target.align = align
			target.attach = att
			if isTorture then
				target.tortureHeadAtt = attachTortureHead(target.model)
			end
			if heroId == "scarlet_witch" or heroId == "jean_grey" then
				target.particles = VfxHelper.attachHeroTelekinesisMorphParticles(target.model, heroId, character)
			end
		end)
		if not ok then
			warn("[Telekinesis] hold setup failed:", err)
			destroyHold(target)
			if target.model.Parent then
				RagdollService.clear(target.model)
			end
		end
	end

	-- Drop any targets that failed setup
	local alive: { HeldTarget } = {}
	for _, target in held do
		if target.align and target.root.Parent then
			table.insert(alive, target)
		end
	end
	state.held = alive
	if #alive == 0 then
		endTelekinesis(player, false, 0)
		return false
	end

	VfxHelper.spawnPulseRing(
		casterRoot.Position,
		3,
		if heroId == "jean_grey"
			then (if character:GetAttribute(GameConstants.LOOK_MODE_ATTRIBUTE) == "marvel_girl"
				then GameConstants.MG_PSI_COLOR_MARVEL_GIRL
				else GameConstants.MG_PSI_COLOR)
			else VfxHelper.chaosColor(),
		0.3
	)
	return true
end

function TelekinesisService.updateAim(player: Player, cursorWorld: Vector3)
	local state = tkByPlayer[player]
	if not state or state.throwing then
		return
	end
	state.cursorWorld = cursorWorld
end

function TelekinesisService.adjustDistance(player: Player, scrollDelta: number)
	local state = tkByPlayer[player]
	if not state or state.throwing then
		return
	end
	local step = if scrollDelta > 0 then GameConstants.TK_SCROLL_STEP else -GameConstants.TK_SCROLL_STEP
	state.holdDistance = math.clamp(
		state.holdDistance + step,
		GameConstants.TK_HOLD_DIST_MIN,
		GameConstants.TK_HOLD_DIST_MAX
	)
end

function TelekinesisService.throw(player: Player, throwDir: Vector3, aimPoint: Vector3?)
	local state = tkByPlayer[player]
	if not state or state.throwing then
		return
	end
	-- Torture: hold-only damage mode — no throw
	if state.isTorture then
		return
	end
	if #state.held == 0 then
		return
	end
	state.throwing = true

	CharacterService.spendEnergy(state.character, GameConstants.TK_THROW_COST)

	local mouseDir = if throwDir.Magnitude > 0.01 then throwDir.Unit else state.casterRoot.CFrame.LookVector
	local dmgMul = if state.isMass then GameConstants.TK_MASS_THROW_DAMAGE_MULT else 1
	local speedMul = if state.isMass then GameConstants.TK_MASS_THROW_SPEED_MULT else 1
	local heldSnapshot = table.clone(state.held)
	local caster = state.character

	stopTkHoldAnim(state)
	TelekinesisService.playThrowAnim(caster)

	state.held = {}
	unlockCasterWalk(state)
	destroyCasterFace(state)
	tkByPlayer[player] = nil
	if state.character.Parent then
		state.character:SetAttribute(GameConstants.TK_ACTIVE_ATTRIBUTE, nil)
		AbilityCooldownHelper.setActive(state.character, "telekinesis", false)
		if state.character:GetAttribute(GameConstants.HERO_ATTRIBUTE) == "scarlet_witch" then
			HandParticleHelper.endUse(state.character)
		end
		AbilityCooldownHelper.applyAfterUse(state.character, "telekinesis", GameConstants.TK_COOLDOWN)
		CharacterService.markAbilityUse(state.character)
	end

	for _, target in heldSnapshot do
		if not target.root.Parent or not target.model.Parent then
			continue
		end
		local model = target.model
		destroyHold(target, true)
		TelekinesisService.launchVictim(state.character, model, mouseDir, aimPoint, function(vRoot)
			CombatHelper.dealDamage(state.character, model, GameConstants.TK_THROW_DAMAGE * dmgMul)
			VfxHelper.spawnBurstSparks(vRoot.Position, VfxHelper.chaosSoft(), 6)
		end, speedMul)
	end
end

function TelekinesisService.takeHeldForJeanPush(player: Player): { Model }
	local state = tkByPlayer[player]
	if not state or state.throwing then
		return {}
	end
	state.throwing = true
	local caster = state.character
	local models: { Model } = {}
	local snapshot = table.clone(state.held)
	stopTkHoldAnim(state)
	TelekinesisService.playThrowAnim(caster)
	state.held = {}
	unlockCasterWalk(state)
	destroyCasterFace(state)
	tkByPlayer[player] = nil
	if state.character.Parent then
		state.character:SetAttribute(GameConstants.TK_ACTIVE_ATTRIBUTE, nil)
		AbilityCooldownHelper.setActive(state.character, "telekinesis", false)
	end
	for _, target in snapshot do
		destroyHold(target, true)
		if target.model.Parent then
			table.insert(models, target.model)
		end
	end
	return models
end

function TelekinesisService.release(player: Player)
	endTelekinesis(player, true, GameConstants.RAGDOLL_TK_RELEASE_DELAY)
end

function TelekinesisService.isActive(player: Player): boolean
	return tkByPlayer[player] ~= nil
end

function TelekinesisService.update(dt: number)
	local now = os.clock()
	local dtClamped = math.clamp(dt, 0.001, 0.1)
	local holdLerp = 1 - (1 - GameConstants.TK_HOLD_POINT_LERP) ^ (dtClamped * 60)

	for player, state in tkByPlayer do
		if not state.character.Parent or not state.casterRoot.Parent then
			endTelekinesis(player, false, GameConstants.RAGDOLL_TK_RELEASE_DELAY)
			continue
		end

		if state.throwing then
			continue
		end

		if now - state.lastDrain >= GameConstants.TK_ENERGY_INTERVAL then
			state.lastDrain = now
			local drain = if state.isTorture then GameConstants.TK_TORTURE_ENERGY_DRAIN else GameConstants.TK_ENERGY_DRAIN
			if not CharacterService.spendEnergy(state.character, drain) then
				endTelekinesis(player, true, GameConstants.RAGDOLL_TK_RELEASE_DELAY)
				continue
			end
		end

		if state.character:GetAttribute(GameConstants.IS_FLYING_ATTRIBUTE) ~= true then
			lockCasterWalk(state)
		end

		local casterPos = state.casterRoot.Position
		local toCursor = state.cursorWorld - casterPos
		local desired = if toCursor.Magnitude > 0.05
			then casterPos + toCursor.Unit * state.holdDistance
			else casterPos + state.casterRoot.CFrame.LookVector * state.holdDistance
		if state.isTorture then
			desired = desired + Vector3.new(0, GameConstants.TK_TORTURE_LIFT_HEIGHT, 0)
		end

		state.smoothedHoldPoint = state.smoothedHoldPoint:Lerp(desired, holdLerp)
		local holdPoint = state.smoothedHoldPoint

		local isFlying = state.character:GetAttribute(GameConstants.IS_FLYING_ATTRIBUTE) == true
		if isFlying then
			if state.faceAlign or state.faceAttach then
				destroyCasterFace(state, false)
			end
		else
			if not state.faceAlign then
				state.savedAutoRotate = state.casterHumanoid.AutoRotate
				state.casterHumanoid.AutoRotate = false
				local faceAlign, faceAttach = createFaceAlign(state.casterRoot)
				state.faceAlign = faceAlign
				state.faceAttach = faceAttach
			end
			local focus = getHeldFocusPosition(state)
			if focus and state.faceAlign then
				local flat = Vector3.new(focus.X - casterPos.X, 0, focus.Z - casterPos.Z)
				if flat.Magnitude > 0.15 then
					state.faceAlign.CFrame = CFrame.lookAt(casterPos, casterPos + flat.Unit)
				end
			end
			if state.casterHumanoid.Parent then
				state.casterHumanoid.AutoRotate = false
			end
		end

		-- Torture: continuous damage while held
		if state.isTorture and now - state.lastTortureDamage >= GameConstants.TK_TORTURE_DAMAGE_INTERVAL then
			state.lastTortureDamage = now
			for _, target in state.held do
				if target.model.Parent and target.humanoid.Parent and target.humanoid.Health > 0 then
					CombatHelper.dealDamage(state.character, target.model, GameConstants.TK_TORTURE_DAMAGE)
				end
			end
		end

		local grace = (now - state.startedAt) < 0.75
		local stillHeld: { HeldTarget } = {}
		for _, target in state.held do
			if not target.root.Parent or not target.humanoid.Parent or target.humanoid.Health <= 0 then
				destroyHold(target)
				if target.model.Parent then
					RagdollService.applyTimed(target.model, GameConstants.RAGDOLL_TK_RELEASE_DELAY)
				end
				continue
			end
			if not grace and (target.root.Position - casterPos).Magnitude > GameConstants.TK_RANGE * 1.75 then
				destroyHold(target)
				RagdollService.applyTimed(target.model, GameConstants.RAGDOLL_TK_RELEASE_DELAY)
				continue
			end

			-- Keep Ragdolled status alive (NewMarvel-style soft maintain)
			if target.model:GetAttribute(GameConstants.RAGDOLLED_ATTRIBUTE) ~= true then
				target.model:SetAttribute("Ragdolled", true)
			else
				RagdollService.maintain(target.model)
			end
			pcall(function()
				if target.humanoid:GetState() ~= Enum.HumanoidStateType.Physics then
					target.humanoid:ChangeState(Enum.HumanoidStateType.Physics)
				end
			end)

			local goal = if state.isMass then holdPoint + target.offsetFromAnchor else holdPoint
			if not target.align or not target.align.Parent then
				local align, att = createHoldAlign(target.root, goal)
				target.align = align
				target.attach = att
			else
				target.align.Position = goal
			end
			table.insert(stillHeld, target)
		end
		state.held = stillHeld
		if #stillHeld == 0 then
			endTelekinesis(player, true, GameConstants.RAGDOLL_TK_RELEASE_DELAY)
		end
	end
end

function TelekinesisService.init()
	Players.PlayerRemoving:Connect(function(player)
		endTelekinesis(player, false, 0)
	end)
end

return TelekinesisService
