local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")

local shared = ReplicatedStorage:WaitForChild("Shared", 30)
if not shared then
	error("[Powers] Shared folder missing.")
end

local configModule = shared:WaitForChild("CharacterConfig", 10)
local ok, CharacterConfig = pcall(require, configModule)
if not ok or type(CharacterConfig) ~= "table" then
	error("[Powers] Failed to require CharacterConfig.")
end

local gameHealthModule = shared:WaitForChild("GameHealth", 10)
local okGh, GameHealth = pcall(require, gameHealthModule)
if not okGh or type(GameHealth) ~= "table" then
	error("[Powers] Failed to require GameHealth.")
end

local moralityModule = shared:WaitForChild("Morality", 10)
local okMo, Morality = pcall(require, moralityModule)
if not okMo or type(Morality) ~= "table" then
	error("[Powers] Failed to require Morality.")
end
Morality.start()

local remotesFolder = ReplicatedStorage:FindFirstChild(CharacterConfig.RemotesFolderName)
if not remotesFolder then
	remotesFolder = Instance.new("Folder")
	remotesFolder.Name = CharacterConfig.RemotesFolderName
	remotesFolder.Parent = ReplicatedStorage
end

local powerCastRemote = remotesFolder:FindFirstChild(CharacterConfig.PowerCastRemoteName)
if not powerCastRemote then
	powerCastRemote = Instance.new("RemoteEvent")
	powerCastRemote.Name = CharacterConfig.PowerCastRemoteName
	powerCastRemote.Parent = remotesFolder
elseif not powerCastRemote:IsA("RemoteEvent") then
	error("[Powers] PowerCast must be RemoteEvent.")
end
local powerCastRemoteEvent = powerCastRemote :: RemoteEvent

local spellCastRemote = remotesFolder:FindFirstChild(CharacterConfig.SpellCastRemoteName)
if not spellCastRemote then
	spellCastRemote = Instance.new("RemoteEvent")
	spellCastRemote.Name = CharacterConfig.SpellCastRemoteName
	spellCastRemote.Parent = remotesFolder
elseif not spellCastRemote:IsA("RemoteEvent") then
	error("[Powers] SpellCast must be RemoteEvent.")
end
local spellCastRemoteEvent = spellCastRemote :: RemoteEvent

local validWitchChoice: { [string]: boolean } = {}
for _, name in CharacterConfig.Choices do
	validWitchChoice[name] = true
end

local SPELL_TEXT_BY_ID: { [string]: string } = (CharacterConfig :: any).SpellChatLinesById
	or {
		return_to_sender = "Let the object of objection become but a dream, as I cause the scene to be no more than it seems.",
		vanquish_belthazor = (CharacterConfig :: any).BelthazorVanquishIncantation
			or "By the Power of Three, we cast you out—harm to none, fate revealed. With this light we vanquish Belthazor.",
		powers_exchange = "What's mine is yours, What's yours is mine. I offer up my gift to share, Switch our powers through the air;",
	}

local function isPlayerWitch(player: Player): boolean
	local c = player:GetAttribute("ChosenCharacter")
	return type(c) == "string" and validWitchChoice[c] == true
end

local powersById: { [string]: any } = {}
for characterName, list in CharacterConfig.PowersByCharacter do
	for _, powerData in list do
		powerData.Character = characterName
		powersById[powerData.Id] = powerData
	end
end

local cooldowns: { [Player]: { [string]: number } } = {}
local lastEnergySpendAt: { [Player]: number } = {}
local energyRegenActive: { [Player]: boolean } = {}
local activeContinuous: { [Player]: { [string]: boolean } } = {}
local freezeStates: {
	[Player]: {
		frozenParts: { BasePart },
		frozenHumanoids: { [Humanoid]: { walkSpeed: number, jumpPower: number, autoRotate: boolean } },
		frozenHumanoidParts: { [Humanoid]: { BasePart } }?,
	},
} = {}
local levitationStates: {
	[Player]: {
		humanoid: Humanoid,
		jumpPower: number,
		autoRotate: boolean,
		velocity: Vector3,
		attachment: Attachment,
		flightVelocity: LinearVelocity,
		orientation: AlignOrientation,
		track: AnimationTrack?,
		mode: string,
		defensiveTargetY: number?,
		combatTarget: Humanoid?,
		combatPhase: string?,
		combatWindupStart: number?,
	},
} = {}
local levitationLeapFinishToken: { [Player]: number } = {}
local premonitionStates: {
	[Player]: {
		target: Humanoid?,
	},
} = {}
local healingStates: {
	[Player]: {
		target: Humanoid,
		walkSpeed: number,
		jumpPower: number,
		autoRotate: boolean,
		handVfx: { Instance },
		healAnimTrack: AnimationTrack?,
		targetMove: { walkSpeed: number, jumpPower: number, autoRotate: boolean },
		healingVictimPlayer: Player?,
	},
} = {}
local astralStates: {
	[Player]: {
		clone: Model,
		astralParticles: { Instance }?,
		astralParticleSessionId: number?,
		characterTransparencySnap: { [BasePart]: { transparency: number, localMod: number } }?,
	},
} = {}
local handlers: { [string]: (Player, Instance?, Vector3?) -> boolean }
local empathicDeflectionStates: { [Player]: { walkSpeed: number, jumpPower: number } } = {}
local telekinesisStates: {
	[Player]: {
		part: BasePart,
		anchor: Part,
		a0: Attachment,
		a1: Attachment,
		align: AlignPosition,
		track: AnimationTrack?,
		projectileLinear: LinearVelocity?,
		projectileLinearEnabled: boolean?,
		projectileVectorVelocity: Vector3?,
		prevCanQuery: boolean,
		mode: string,
		telekinesisChannelStyle: string,
		lastAimWorld: Vector3?,
		grabbedRestoreNetworkTo: Player?,
		victimHeldPlatformStand: Humanoid?,
		victimHeldPlatformStandWas: boolean?,
	},
} = {}
local telekineticOrbingStates: {
	[Player]: {
		part: BasePart,
		hoverPosition: Vector3,
		projectileLinear: LinearVelocity?,
		projectileLinearEnabled: boolean?,
		projectileVectorVelocity: Vector3?,
		mode: string,
		orbVfx: { Instance }?,
		restoreNetworkOwnerTo: Player?,
		transparencySnap: { [BasePart]: { transparency: number, localMod: number } }?,
	},
} = {}
local interactableStartCFrames: { [Instance]: CFrame } = {}
local interactablePartStartTransparency: { [BasePart]: number } = {}
local interactablePartStartLocalTransparencyMod: { [BasePart]: number } = {}

-- Stacked stuns: only the latest timer may restore; baseline is from before the first stun in the chain (never "forever").
local platformStandStun: {
	[Humanoid]: {
		token: number,
		baseline: { platformStand: boolean, walkSpeed: number, jumpPower: number, autoRotate: boolean },
	},
} = {}

-- Forward declarations: triggerTimedPlatformStand runs before these `local function` lines would assign names.
local clearTelekinesis: (Player) -> ()
local stopMolecularFreeze: (Player) -> ()
local stopPremonition: (Player) -> ()
local stopLevitation: (Player) -> ()
local stopHealing: (Player) -> ()
local stopTelekineticOrbing: (Player, boolean?) -> ()
local stopEmpathicDeflection: (Player, boolean?) -> ()

local function getRoot(character: Model): BasePart?
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function getHumanoid(character: Model): Humanoid?
	return character:FindFirstChildOfClass("Humanoid")
end

local function triggerTimedRagdoll(humanoid: Humanoid, duration: number)
	local character = humanoid.Parent
	if not character or not character:IsA("Model") then
		return
	end
	character:SetAttribute("Ragdolled", true)
	task.delay(duration, function()
		if not humanoid.Parent or humanoid.Health <= 0 then
			return
		end
		if character:GetAttribute("Ragdolled") == true then
			character:SetAttribute("Ragdolled", false)
		end
	end)
end

local function triggerTimedPlatformStand(humanoid: Humanoid, duration: number)
	-- PlatformStand is a "no-ragdoll" alternative: the character can't actively control itself.
	-- Duration is always bounded so stun cannot last forever; overlapping hits extend the latest timer only.
	local d = math.clamp(duration, 0.08, 8)
	local character = humanoid.Parent
	if character and character:IsA("Model") then
		-- If this humanoid belongs to a Player, stop their powers immediately so they can't keep attacking while platformstanced.
		local victimPlayer = Players:GetPlayerFromCharacter(character)
		if victimPlayer then
			clearTelekinesis(victimPlayer)
			stopMolecularFreeze(victimPlayer)
			stopPremonition(victimPlayer)
			stopLevitation(victimPlayer)
			stopHealing(victimPlayer)
			stopTelekineticOrbing(victimPlayer, true)
			stopEmpathicDeflection(victimPlayer, true)
		end
	end

	local entry = platformStandStun[humanoid]
	if not entry then
		entry = {
			token = 0,
			baseline = {
				platformStand = humanoid.PlatformStand,
				walkSpeed = humanoid.WalkSpeed,
				jumpPower = humanoid.JumpPower,
				autoRotate = humanoid.AutoRotate,
			},
		}
		platformStandStun[humanoid] = entry
	end
	entry.token += 1
	local myToken = entry.token

	humanoid.PlatformStand = true
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.AutoRotate = false

	task.delay(d, function()
		if not humanoid.Parent then
			platformStandStun[humanoid] = nil
			return
		end
		local st = platformStandStun[humanoid]
		if not st or st.token ~= myToken then
			return
		end
		if humanoid.Health <= 0 then
			platformStandStun[humanoid] = nil
			return
		end
		local b = st.baseline
		humanoid.PlatformStand = b.platformStand
		humanoid.WalkSpeed = b.walkSpeed
		humanoid.JumpPower = b.jumpPower
		humanoid.AutoRotate = b.autoRotate
		platformStandStun[humanoid] = nil
	end)
end

local function playAnimation(humanoid: Humanoid, animationId: string, looped: boolean): AnimationTrack?
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. animationId
	local ok, track = pcall(function()
		return (animator :: Animator):LoadAnimation(animation)
	end)
	animation:Destroy()
	if not ok or not track then
		return nil
	end
	local animTrack = track :: AnimationTrack
	animTrack.Looped = looped
	animTrack:Play(0.12)
	return animTrack
end

local function findInteractableAncestor(instance: Instance?): Instance?
	local current = instance
	while current and current ~= workspace do
		local nameLower = string.lower(current.Name)
		-- Avoid expensive recursive searches here; this runs a lot during snapshots.
		if string.find(nameLower, "interactable", 1, true) or current:FindFirstChild("Interactable") ~= nil then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function getInteractableRoots(): { Instance }
	local roots: { Instance } = {}
	local seen: { [Instance]: boolean } = {}
	local all = workspace:GetDescendants()
	for i, inst in all do
		-- Yield occasionally to avoid script timeout on big places.
		if i % 2000 == 0 then
			task.wait()
		end
		local interactable = findInteractableAncestor(inst)
		if interactable and not seen[interactable] then
			seen[interactable] = true
			table.insert(roots, interactable)
		end
	end
	return roots
end

local function snapshotInteractables()
	table.clear(interactableStartCFrames)
	table.clear(interactablePartStartTransparency)
	table.clear(interactablePartStartLocalTransparencyMod)
	for _, root in getInteractableRoots() do
		if root:IsA("BasePart") then
			interactableStartCFrames[root] = root.CFrame
			interactablePartStartTransparency[root] = root.Transparency
			interactablePartStartLocalTransparencyMod[root] = root.LocalTransparencyModifier
		elseif root:IsA("Model") then
			interactableStartCFrames[root] = root:GetPivot()
			for _, d in root:GetDescendants() do
				if d:IsA("BasePart") then
					local bp = d :: BasePart
					interactablePartStartTransparency[bp] = bp.Transparency
					interactablePartStartLocalTransparencyMod[bp] = bp.LocalTransparencyModifier
				end
			end
		end
	end
end

local RETURN_TO_SENDER_MAX_DISTANCE = 100

local function getInteractableRootWorldPosition(root: Instance): Vector3?
	if root:IsA("BasePart") then
		return root.Position
	end
	if root:IsA("Model") then
		local pp = root.PrimaryPart
		if pp then
			return pp.Position
		end
		return root:GetPivot().Position
	end
	return nil
end

local function returnInteractablesToStart(player: Player?)
	local origin: Vector3? = nil
	if player and player.Character then
		local hrp = getRoot(player.Character)
		if hrp then
			origin = hrp.Position
		end
	end
	if not origin then
		return
	end

	for root, startCf in interactableStartCFrames do
		if not root.Parent then
			continue
		end
		local objectPos = getInteractableRootWorldPosition(root)
		if not objectPos or (objectPos - origin).Magnitude > RETURN_TO_SENDER_MAX_DISTANCE then
			continue
		end
		local parts: { BasePart } = {}
		if root:IsA("BasePart") then
			table.insert(parts, root)
		elseif root:IsA("Model") then
			for _, d in root:GetDescendants() do
				if d:IsA("BasePart") then
					table.insert(parts, d)
				end
			end
		end
		if #parts == 0 then
			continue
		end

		local preFadeTransparency: { [BasePart]: number } = {}
		local preFadeLocalMod: { [BasePart]: number } = {}
		for _, p in parts do
			preFadeTransparency[p] = p.Transparency
			preFadeLocalMod[p] = p.LocalTransparencyModifier
			local fadeOut = TweenService:Create(p, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Transparency = 1,
			})
			fadeOut:Play()
		end
		task.wait(0.2)

		if root:IsA("BasePart") then
			root.CFrame = startCf
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
		elseif root:IsA("Model") then
			root:PivotTo(startCf)
			for _, d in parts do
				d.AssemblyLinearVelocity = Vector3.zero
				d.AssemblyAngularVelocity = Vector3.zero
			end
		end

		for _, p in parts do
			if p.Parent then
				local snapT = interactablePartStartTransparency[p]
				local snapLtm = interactablePartStartLocalTransparencyMod[p]
				local endT = if snapT ~= nil then snapT else (preFadeTransparency[p] or 0)
				local endLtm = if snapLtm ~= nil then snapLtm else (preFadeLocalMod[p] or 0)
				local fadeIn = TweenService:Create(p, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Transparency = endT,
					LocalTransparencyModifier = endLtm,
				})
				fadeIn:Play()
			end
		end
	end
end

local function findHumanoidAncestor(instance: Instance?): Model?
	local current = instance
	while current and current ~= workspace do
		if current:IsA("Model") and current:FindFirstChildOfClass("Humanoid") then
			return current
		end
		current = current.Parent
	end
	return nil
end

local HEALING_MAX_RANGE = 5
local ASTRAL_CHARACTER_TRANSPARENCY_TWEEN = 1.5
local ASTRAL_PARTICLE_DISABLE_AFTER = 0.5
local ASTRAL_PARTICLE_EMIT_FADE_DURATION = 0.28
local ASTRAL_PARTICLE_DESTROY_AFTER = 3

local function trackThrownObjectImpacts(
	projectile: BasePart,
	casterCharacter: Model,
	damage: number,
	pushSpeed: number,
	trackDuration: number?
)
	local casterPlayer = Players:GetPlayerFromCharacter(casterCharacter)
	local thrownModel = findHumanoidAncestor(projectile)
	local hitHumanoids: { [Humanoid]: boolean } = {}
	local expireAt = os.clock() + (trackDuration or 4)
	local conn: RBXScriptConnection? = nil
	local hbConn: RBXScriptConnection? = nil

	local function disconnectTracking()
		if conn then
			conn:Disconnect()
			conn = nil
		end
		if hbConn then
			hbConn:Disconnect()
			hbConn = nil
		end
	end

	local function tryHitVictim(victimModel: Model?)
		if not victimModel or victimModel == casterCharacter then
			return
		end
		if thrownModel and thrownModel == victimModel then
			return
		end
		local hum = victimModel:FindFirstChildOfClass("Humanoid")
		local hrp = victimModel:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hum or hum.Health <= 0 or not hrp then
			return
		end
		if hitHumanoids[hum] then
			return
		end
		hitHumanoids[hum] = true
		-- If the victim is using empathic deflection, it should negate the attack.
		if victimModel:GetAttribute("EmpathicDeflectionActive") == true then
			local away = projectile.Position - hrp.Position
			local dir = if away.Magnitude > 0.01 then away.Unit else projectile.AssemblyLinearVelocity.Unit
			if dir.Magnitude < 0.01 then
				dir = projectile.CFrame.LookVector
			end
			local bounceVel = dir * pushSpeed + Vector3.new(0, 18, 0)
			local lv = projectile:FindFirstChild("ProjectileLinearVelocity")
			if lv and lv:IsA("LinearVelocity") then
				lv.VectorVelocity = bounceVel
			else
				projectile.AssemblyLinearVelocity = bounceVel
			end
			return
		end
		GameHealth.applyDamage(hum, damage, casterPlayer)
		local away = hrp.Position - projectile.Position
		local dir = if away.Magnitude > 0.01 then away.Unit else projectile.AssemblyLinearVelocity.Unit
		if dir.Magnitude < 0.01 then
			dir = projectile.CFrame.LookVector
		end
		local victimPlr = Players:GetPlayerFromCharacter(victimModel)
		if victimPlr then
			pcall(function()
				hrp:SetNetworkOwner(nil)
			end)
		end
		hrp.AssemblyLinearVelocity = dir * pushSpeed + Vector3.new(0, 18, 0)
		if victimPlr then
			task.delay(0.14, function()
				if hrp.Parent then
					pcall(function()
						hrp:SetNetworkOwner(victimPlr)
					end)
				end
			end)
		end
		triggerTimedPlatformStand(hum, 2.2)

		local projectileChar = findHumanoidAncestor(projectile)
		if not projectileChar then
			-- Some runtime states can make `disconnectTracking()` unexpectedly nil; inline the disconnect.
			if conn then
				conn:Disconnect()
				conn = nil
			end
			if hbConn then
				hbConn:Disconnect()
				hbConn = nil
			end
			if projectile:GetAttribute("IsProjectile") == true or getProjectilePart(projectile) ~= nil then
				smoothAnchorRemoveProjectile(projectile)
			end
		end
	end

	conn = projectile.Touched:Connect(function(hitPart: BasePart)
		if os.clock() > expireAt then
			return
		end
		tryHitVictim(findHumanoidAncestor(hitPart))
	end)

	-- Touched is unreliable for player-vs-player (ownership); overlap sweep catches humanoid hits on the server.
	local sweepAccum = 0.0
	hbConn = RunService.Heartbeat:Connect(function(dt: number)
		if os.clock() > expireAt or not projectile.Parent then
			disconnectTracking()
			return
		end
		sweepAccum += dt
		if sweepAccum < 0.04 then
			return
		end
		sweepAccum = 0
		local overlap = OverlapParams.new()
		overlap.FilterType = Enum.RaycastFilterType.Blacklist
		local bl: { Instance } = { casterCharacter }
		if thrownModel then
			table.insert(bl, thrownModel)
		end
		overlap.FilterDescendantsInstances = bl
		local ok, parts = pcall(function()
			return workspace:GetPartBoundsInRadius(projectile.Position, 6.5, overlap)
		end)
		if not ok or type(parts) ~= "table" then
			return
		end
		local seen: { [Model]: boolean } = {}
		for _, p in parts :: { BasePart } do
			local vm = findHumanoidAncestor(p)
			if vm and not seen[vm] then
				seen[vm] = true
				tryHitVictim(vm)
			end
		end
	end)

	task.delay(trackDuration or 4, function()
		disconnectTracking()
	end)
end

local function getTargetPart(instance: Instance?): BasePart?
	local humanoidModel = findHumanoidAncestor(instance)
	if humanoidModel then
		local hrp = humanoidModel:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then
			return hrp
		end
	end
	local interactable = findInteractableAncestor(instance)
	if not interactable then
		return nil
	end
	if interactable:IsA("BasePart") then
		return interactable
	end
	if interactable:IsA("Model") then
		if interactable.PrimaryPart then
			return interactable.PrimaryPart
		end
		local anyPart = interactable:FindFirstChildWhichIsA("BasePart", true)
		if anyPart then
			return anyPart
		end
	end
	return nil
end

local function getProjectilePart(instance: Instance?): BasePart?
	local current = instance
	while current and current ~= workspace do
		if current:IsA("BasePart") then
			if current:GetAttribute("IsProjectile") == true then
				return current
			end
			local lowered = string.lower(current.Name)
			-- Spawner parts (e.g. FireballSender) match "fireball" but are not flying projectiles.
			if not string.find(lowered, "sender", 1, true) then
				if string.find(lowered, "fireball", 1, true) or string.find(lowered, "projectile", 1, true) then
					return current
				end
			end
		end
		current = current.Parent
	end
	return nil
end

-- Telekinesis / telekinetic-orbing: only Humanoids, projectiles, or instances under a model with an Interactable child.
local function hasInteractableValueInAncestorChain(instance: Instance?): boolean
	local current = instance
	while current and current ~= workspace do
		if current:FindFirstChild("Interactable") ~= nil then
			return true
		end
		current = current.Parent
	end
	return false
end

local function isTelekinesisOrOrbingGrabTarget(target: Instance?, part: BasePart, casterCharacter: Model): boolean
	if not target or not part or part:IsDescendantOf(casterCharacter) then
		return false
	end
	local projFromTarget = getProjectilePart(target)
	if projFromTarget ~= nil and projFromTarget == part then
		return true
	end
	if findHumanoidAncestor(part) ~= nil then
		return true
	end
	if getProjectilePart(part) ~= nil then
		return true
	end
	return hasInteractableValueInAncestorChain(target)
end

local function getPartFromTarget(target: Instance?): BasePart?
	if not target then
		return nil
	end
	if target:IsA("BasePart") then
		return target
	end
	if target:IsA("Model") then
		if target.PrimaryPart then
			return target.PrimaryPart
		end
		local anyPart = target:FindFirstChildWhichIsA("BasePart", true)
		if anyPart then
			return anyPart
		end
	end
	return nil
end

local function setEnergy(player: Player, amount: number)
	local clamped = math.clamp(amount, 0, CharacterConfig.DefaultEnergy)
	player:SetAttribute("Energy", clamped)
	local character = player.Character
	if character then
		character:SetAttribute("Energy", clamped)
	end
end

local startEnergyRegen: (player: Player) -> ()

local function spendEnergyAmount(player: Player, amount: number): boolean
	if amount <= 0 then
		return true
	end
	local energy = player:GetAttribute("Energy")
	local current = if type(energy) == "number" then energy else CharacterConfig.DefaultEnergy
	if current < amount then
		return false
	end
	setEnergy(player, current - amount)
	lastEnergySpendAt[player] = os.clock()
	startEnergyRegen(player)
	return true
end

function startEnergyRegen(player: Player)
	if energyRegenActive[player] then
		return
	end
	energyRegenActive[player] = true
	task.spawn(function()
		while player.Parent do
			local lastSpend = lastEnergySpendAt[player]
			local now = os.clock()
			if lastSpend and (now - lastSpend) >= 2 then
				local energy = player:GetAttribute("Energy")
				local current = if type(energy) == "number" then energy else CharacterConfig.DefaultEnergy
				if current < CharacterConfig.DefaultEnergy then
					setEnergy(player, current + 4)
				end
			end
			task.wait(0.2)
		end
		energyRegenActive[player] = nil
	end)
end

local function spendEnergy(player: Player, cost: number): boolean
	local energy = player:GetAttribute("Energy")
	local current = if type(energy) == "number" then energy else CharacterConfig.DefaultEnergy
	if current < cost then
		return false
	end
	setEnergy(player, current - cost)
	lastEnergySpendAt[player] = os.clock()
	startEnergyRegen(player)
	return true
end

local function setAbilityActive(player: Player, abilityId: string, isActive: boolean)
	local byPlayer = activeContinuous[player]
	if not byPlayer then
		byPlayer = {}
		activeContinuous[player] = byPlayer
	end
	byPlayer[abilityId] = isActive
	powerCastRemoteEvent:FireClient(player, "ability_state", abilityId, isActive)
end

local function isAbilityActive(player: Player, abilityId: string): boolean
	local byPlayer = activeContinuous[player]
	return byPlayer ~= nil and byPlayer[abilityId] == true
end

local CONCURRENT_CHANNELED_ABILITY_IDS: { [string]: boolean } = {
	telekinesis = true,
	telekinetic_orbing = true,
	astral_projection = true,
	molecular_freeze = true,
	premonition = true,
	levitation = true,
	healing = true,
	-- Victim of another player's Healing channel: cannot use other powers until the heal ends.
	healing_target = true,
	empathic_deflection = true,
}

local function getConcurrentChanneledAbilityId(player: Player): string?
	local byPlayer = activeContinuous[player]
	if not byPlayer then
		return nil
	end
	for id, on in byPlayer do
		if on and CONCURRENT_CHANNELED_ABILITY_IDS[id] then
			return id
		end
	end
	return nil
end

local function shouldBlockPowerCastDueToConcurrentAbility(player: Player, powerId: string, castAction: string?): boolean
	local activeId = getConcurrentChanneledAbilityId(player)
	if not activeId then
		return false
	end
	if activeId == powerId then
		if castAction == "update" or castAction == "push" or castAction == "stop" then
			return false
		end
		return true
	end
	return true
end

local continuousDrainPerSecond: { [string]: number } = {
	telekinesis = 5,
	astral_projection = 4,
	molecular_freeze = 6,
	levitation = 5,
	healing = 4,
	telekinetic_orbing = 4,
	empathic_deflection = 14,
}

local function isInteractableProjectile(projectile: BasePart): boolean
	if projectile:GetAttribute("IsProjectile") ~= true then
		return false
	end
	local interactableTag = projectile:FindFirstChild("Interactable")
	if interactableTag and interactableTag:IsA("BoolValue") and interactableTag.Value == true then
		return true
	end
	local interactableAncestor = findInteractableAncestor(projectile)
	return interactableAncestor ~= nil
end

local function reflectProjectilesAround(player: Player, radius: number, requireInteractable: boolean?, barrierNoRepeat: boolean?, requireMarkedProjectile: boolean?): number
	local character = player.Character
	if not character then
		return 0
	end
	local root = getRoot(character)
	if not root then
		return 0
	end
	local reflected = 0
	for _, part in workspace:GetPartBoundsInRadius(root.Position, radius) do
		local projectile = getProjectilePart(part)
		if projectile and not projectile:IsDescendantOf(character) then
			if requireMarkedProjectile and projectile:GetAttribute("IsProjectile") ~= true then
				continue
			end
			if requireInteractable and not isInteractableProjectile(projectile) then
				continue
			end
			local now = os.clock()
			if barrierNoRepeat then
				local barrierLockUntil = projectile:GetAttribute("BarrierDeflectLockUntil")
				if type(barrierLockUntil) == "number" and barrierLockUntil > now then
					continue
				end
			end
			local linearVelocity = projectile:FindFirstChild("ProjectileLinearVelocity")
			local projectileToCharacter = root.Position - projectile.Position
			local deflectDirection = if projectileToCharacter.Magnitude > 0.01
				then (projectileToCharacter.Unit * -1)
				else root.CFrame.LookVector
			if linearVelocity and linearVelocity:IsA("LinearVelocity") then
				local current = linearVelocity.VectorVelocity
				local speed = if current.Magnitude > 0.1 then current.Magnitude else 90
				linearVelocity.VectorVelocity = deflectDirection * speed
				if barrierNoRepeat then
					projectile:SetAttribute("BarrierDeflectLockUntil", now + 0.55)
				end
				reflected += 1
				continue
			end
			local velocity = projectile.AssemblyLinearVelocity
			local speed = if velocity.Magnitude > 0.1 then velocity.Magnitude else 90
			projectile.AssemblyLinearVelocity = deflectDirection * speed
			if barrierNoRepeat then
				projectile:SetAttribute("BarrierDeflectLockUntil", now + 0.55)
			end
			reflected += 1
		end
	end
	return reflected
end

local function smoothAnchorRemoveProjectile(projectile: BasePart)
	if not projectile.Parent then
		return
	end
	projectile.Anchored = true
	projectile.AssemblyLinearVelocity = Vector3.zero
	projectile.AssemblyAngularVelocity = Vector3.zero
	for _, d in projectile:GetDescendants() do
		if d:IsA("LinearVelocity") then
			d.Enabled = false
			d.VectorVelocity = Vector3.zero
		elseif d:IsA("BodyVelocity") then
			d.MaxForce = 0
			d.Velocity = Vector3.zero
		elseif d:IsA("BodyAngularVelocity") then
			d.MaxTorque = 0
			d.AngularVelocity = Vector3.zero
		end
	end
	local origSize = projectile.Size
	local tweenInfo = TweenInfo.new(0.52, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(projectile, tweenInfo, { Transparency = 1 }):Play()
	TweenService:Create(projectile, tweenInfo, { Size = origSize * 0.04 }):Play()
	task.delay(0.56, function()
		if projectile.Parent then
			projectile:Destroy()
		end
	end)
end

local MOLECULAR_DEVIATION_MAX_TARGET_RANGE = 40
local MOLECULAR_DEVIATION_PROJECTILE_MAX_RANGE = 36
local MOLECULAR_DEVIATION_PUSH_STUDS = 74
local MOLECULAR_DEVIATION_PUSH_Y = 16

local function isValidMolecularDeviationTarget(player: Player, target: Instance?): boolean
	if not target then
		return false
	end
	local character = player.Character
	if not character then
		return false
	end
	local root = getRoot(character)
	if not root then
		return false
	end
	local humModel = findHumanoidAncestor(target)
	if humModel and humModel ~= character then
		local hum = humModel:FindFirstChildOfClass("Humanoid")
		local hrp = humModel:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hum and hrp and hrp:IsA("BasePart") and hum.Health > 0 then
			if (hrp.Position - root.Position).Magnitude <= MOLECULAR_DEVIATION_MAX_TARGET_RANGE then
				return true
			end
		end
	end
	local projectile = getProjectilePart(target)
	if not projectile or projectile:IsDescendantOf(character) then
		return false
	end
	if projectile:GetAttribute("IsProjectile") ~= true then
		return false
	end
	if not isInteractableProjectile(projectile) then
		return false
	end
	if (projectile.Position - root.Position).Magnitude > MOLECULAR_DEVIATION_PROJECTILE_MAX_RANGE then
		return false
	end
	local now = os.clock()
	local barrierLockUntil = projectile:GetAttribute("BarrierDeflectLockUntil")
	if type(barrierLockUntil) == "number" and barrierLockUntil > now then
		return false
	end
	return true
end

local function startContinuousDrain(player: Player, abilityId: string, onOutOfEnergy: (() -> ())?)
	task.spawn(function()
		while player.Parent and isAbilityActive(player, abilityId) do
			local drainPerSecond = continuousDrainPerSecond[abilityId] or 0
			local ok = spendEnergyAmount(player, drainPerSecond * 0.25)
			if not ok then
				setAbilityActive(player, abilityId, false)
				if onOutOfEnergy then
					onOutOfEnergy()
				end
				break
			end
			task.wait(0.25)
		end
	end)
end

local function canCast(player: Player, powerId: string): (boolean, any?)
	local power = powersById[powerId]
	if not power then
		return false, nil
	end

	local chosen = player:GetAttribute("ChosenCharacter")
	if type(chosen) ~= "string" or chosen ~= power.Character then
		return false, nil
	end

	local character = player.Character
	if not character then
		return false, nil
	end
	local humanoid = getHumanoid(character)
	if not humanoid or humanoid.Health <= 0 then
		return false, nil
	end

	local byPlayer = cooldowns[player]
	if not byPlayer then
		byPlayer = {}
		cooldowns[player] = byPlayer
	end
	local last = byPlayer[powerId]
	local now = os.clock()
	if last and (now - last) < power.Cooldown then
		return false, nil
	end

	local energy = player:GetAttribute("Energy")
	local current = if type(energy) == "number" then energy else CharacterConfig.DefaultEnergy
	if current < power.Energy then
		return false, nil
	end

	return true, power
end

local function setLastUsedAbility(player: Player, powerId: string)
	player:SetAttribute("LastUsedAbilityId", powerId)
	local character = player.Character
	if character then
		character:SetAttribute("LastUsedAbilityId", powerId)
	end
end

local function beginCooldown(player: Player, powerId: string, cooldownOverrideSeconds: number?)
	local power = powersById[powerId]
	if not power then
		return
	end
	local byPlayer = cooldowns[player]
	if not byPlayer then
		byPlayer = {}
		cooldowns[player] = byPlayer
	end
	local baseCd = power.Cooldown
	local cd = if type(cooldownOverrideSeconds) == "number" and cooldownOverrideSeconds > 0 then cooldownOverrideSeconds else baseCd
	-- Store a timestamp adjusted so `canCast` can keep using baseCd comparisons while still
	-- producing style-dependent cooldown lengths.
	byPlayer[powerId] = os.clock() + (cd - baseCd)
	powerCastRemoteEvent:FireClient(player, "ability_cooldown", powerId, cd)
end

local DEFLECT_COMBUSTION_RADIUS = 22
local DEFLECT_PROJECTILE_RADIUS = 22

local function pushCasterFromDeflector(caster: Player, deflectorWorldPos: Vector3, horizontalSpeed: number, yBoost: number)
	local ch = caster.Character
	local root = ch and getRoot(ch)
	if not root then
		return
	end
	clearTelekinesis(caster)
	local casterPlr = Players:GetPlayerFromCharacter(ch)
	if casterPlr then
		pcall(function()
			root:SetNetworkOwner(nil)
		end)
	end
	local away = root.Position - deflectorWorldPos
	if away.Magnitude < 0.08 then
		away = Vector3.new(0, 1, 0)
	end
	root.AssemblyLinearVelocity = away.Unit * horizontalSpeed + Vector3.new(0, yBoost, 0)
	if casterPlr then
		task.delay(0.14, function()
			if root.Parent then
				pcall(function()
					root:SetNetworkOwner(casterPlr)
				end)
			end
		end)
	end
	local hum = ch and getHumanoid(ch)
	if hum then
		triggerTimedPlatformStand(hum, 1.1)
	end
end

-- When an empathic deflection rejects a grab/orb/combustion: also knock back the subject of the attack.
local function pushDeflectedAbilitySubject(part: BasePart?, fromWorldPos: Vector3, horizontalSpeed: number, yBoost: number)
	if not part or not part.Parent then
		return
	end
	local away = part.Position - fromWorldPos
	if away.Magnitude < 0.06 then
		away = Vector3.new(0, 1, 0)
	end
	part.AssemblyLinearVelocity = away.Unit * horizontalSpeed + Vector3.new(0, yBoost, 0)
	local m = findHumanoidAncestor(part)
	if m then
		local hum = m:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			triggerTimedPlatformStand(hum, 1.15)
		end
	end
end

local function pushDeflectedCombustionBystanders(
	hitPosition: Vector3,
	attackerChar: Model?,
	deflectorChar: Model?,
	deflectorRoot: BasePart,
	castHalfSize: number,
	horizontalSpeed: number,
	yBoost: number
)
	local affected: { [Humanoid]: boolean } = {}
	local box = Vector3.new(castHalfSize * 2, castHalfSize * 2, castHalfSize * 2)
	for _, p in workspace:GetPartBoundsInBox(CFrame.new(hitPosition), box) do
		local md = findHumanoidAncestor(p)
		if md and md ~= attackerChar and md ~= deflectorChar then
			local hum = md:FindFirstChildOfClass("Humanoid")
			local hrp = md:FindFirstChild("HumanoidRootPart") :: BasePart?
			if hum and hum.Health > 0 and hrp and not affected[hum] then
				affected[hum] = true
				pushDeflectedAbilitySubject(hrp, deflectorRoot.Position, horizontalSpeed, yBoost)
			end
		end
	end
end

-- Any humanoid model (player or NPC) with EmpathicDeflectionActive — same rule as ray/impact checks.
local function getEmpathicDeflectorNear(attackerChar: Model?, worldPos: Vector3, maxDist: number): Model?
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	if attackerChar then
		overlapParams.FilterDescendantsInstances = { attackerChar }
	end
	local ok, parts = pcall(function()
		return workspace:GetPartBoundsInRadius(worldPos, maxDist, overlapParams)
	end)
	if not ok or type(parts) ~= "table" then
		return nil
	end
	local seen: { [Model]: boolean } = {}
	for _, p in parts :: { BasePart } do
		local m = findHumanoidAncestor(p)
		if m and m ~= attackerChar and not seen[m] and m:GetAttribute("EmpathicDeflectionActive") == true then
			seen[m] = true
			local r = getRoot(m)
			if r and (r.Position - worldPos).Magnitude <= maxDist then
				return m
			end
		end
	end
	return nil
end

local function unfreezeVictimHumanoid(hum: Humanoid)
	local model = hum.Parent
	if model and model:IsA("Model") then
		model:SetAttribute("MolecularFrozen", false)
	end
	for _, st in freezeStates do
		if st.frozenHumanoids[hum] then
			local stored = st.frozenHumanoids[hum]
			local byParts = st.frozenHumanoidParts
			local parts = if byParts then byParts[hum] else nil
			if type(parts) == "table" then
				for _, bp in parts do
					if typeof(bp) == "Instance" and bp:IsA("BasePart") and bp.Parent then
						bp.Anchored = false
					end
				end
				byParts[hum] = nil
			end
			if hum.Parent then
				hum.WalkSpeed = stored.walkSpeed
				hum.JumpPower = stored.jumpPower
				hum.AutoRotate = stored.autoRotate
			end
			st.frozenHumanoids[hum] = nil
			return
		end
	end
end

local function unfreezeVictimPart(part: BasePart)
	for _, st in freezeStates do
		for i = #st.frozenParts, 1, -1 do
			if st.frozenParts[i] == part then
				if part.Parent then
					part.Anchored = false
				end
				table.remove(st.frozenParts, i)
				return
			end
		end
	end
end

stopEmpathicDeflection = function(player: Player, applyCooldown: boolean?)
	local st = empathicDeflectionStates[player]
	local character = player.Character
	local hum = character and getHumanoid(character)
	if hum and st then
		hum.WalkSpeed = st.walkSpeed
		hum.JumpPower = st.jumpPower
	end
	if character and character:IsA("Model") then
		character:SetAttribute("EmpathicDeflectionActive", false)
	end
	empathicDeflectionStates[player] = nil
	setAbilityActive(player, "empathic_deflection", false)
	if applyCooldown ~= false then
		beginCooldown(player, "empathic_deflection")
	end
end

local function applyEmpathicDeflection(player: Player)
	local character = player.Character
	local hum = character and getHumanoid(character)
	if not hum then
		return
	end
	empathicDeflectionStates[player] = { walkSpeed = hum.WalkSpeed, jumpPower = hum.JumpPower }
	if character and character:IsA("Model") then
		character:SetAttribute("EmpathicDeflectionActive", true)
	end
	hum.WalkSpeed = 4
	hum.JumpPower = 0
	setAbilityActive(player, "empathic_deflection", true)
	startContinuousDrain(player, "empathic_deflection", function()
		stopEmpathicDeflection(player, false)
	end)
end

local function movePartSmooth(part: BasePart, destination: Vector3, duration: number, holdSeconds: number?)
	local anchor = Instance.new("Part")
	anchor.Name = "PowerAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(destination)
	anchor.Parent = workspace

	local a0 = Instance.new("Attachment")
	a0.Parent = part

	local a1 = Instance.new("Attachment")
	a1.Parent = anchor

	local align = Instance.new("AlignPosition")
	align.Attachment0 = a0
	align.Attachment1 = a1
	align.MaxForce = 100000
	align.MaxVelocity = 200
	align.Responsiveness = 35
	align.RigidityEnabled = false
	align.Parent = part

	task.delay(duration + (holdSeconds or 0), function()
		align:Destroy()
		a0:Destroy()
		a1:Destroy()
		anchor:Destroy()
	end)
end

clearTelekinesis = function(player: Player)
	local state = telekinesisStates[player]
	if not state then
		return
	end
	if state.victimHeldPlatformStand and state.victimHeldPlatformStand.Parent then
		state.victimHeldPlatformStand.PlatformStand = if state.victimHeldPlatformStandWas ~= nil
			then state.victimHeldPlatformStandWas
			else false
	end
	if state.track then
		state.track:Stop(0.12)
		state.track:Destroy()
	end
	if state.align.Parent then
		state.align:Destroy()
	end
	if state.projectileLinear and state.projectileLinear.Parent and state.part.Parent then
		local lv = state.projectileLinear
		local spd: number
		if state.projectileVectorVelocity and state.projectileVectorVelocity.Magnitude > 6 then
			spd = state.projectileVectorVelocity.Magnitude
		else
			spd = 90
		end
		local dir: Vector3
		if state.projectileVectorVelocity and state.projectileVectorVelocity.Magnitude > 0.1 then
			dir = state.projectileVectorVelocity
		elseif state.lastAimWorld and typeof(state.lastAimWorld) == "Vector3" then
			dir = state.lastAimWorld - state.part.Position
		else
			dir = Vector3.new(0, 0, -1)
		end
		if dir.Magnitude < 0.08 then
			dir = Vector3.new(0, 1, 0)
		end
		lv.VectorVelocity = dir.Unit * spd
		lv.Enabled = true
	end
	if state.a0.Parent then
		state.a0:Destroy()
	end
	if state.a1.Parent then
		state.a1:Destroy()
	end
	if state.anchor.Parent then
		state.anchor:Destroy()
	end
	if state.part.Parent then
		state.part.CanQuery = state.prevCanQuery
		if state.grabbedRestoreNetworkTo then
			pcall(function()
				state.part:SetNetworkOwner(state.grabbedRestoreNetworkTo)
			end)
		end
	end
	local channelStyle = state.telekinesisChannelStyle or "hand"
	-- Note: cooldown multipliers are declared later in the file, so avoid referencing
	-- them here (this runs before their `local` declarations in Luau).
	local cdMult = if channelStyle == "eye" then 0.85 else 1.15
	local actualCd = (powersById.telekinesis and powersById.telekinesis.Cooldown or 2) * cdMult
	telekinesisStates[player] = nil
	powerCastRemoteEvent:FireClient(player, "telekinesis_grab", nil)
	setAbilityActive(player, "telekinesis", false)
	beginCooldown(player, "telekinesis", actualCd)
end

local function getTelekinesisGrabRange(): number
	local v = (CharacterConfig :: any).TelekinesisGrabRangeStuds
	return if type(v) == "number" then v else 30
end

local function getTelekinesisMaxHoldDistance(): number
	local v = (CharacterConfig :: any).TelekinesisMaxHoldDistanceStuds
	return if type(v) == "number" then v else 30
end

-- Drops grab if grabbed part is farther than max hold distance from caster (aim has no range limit).
local function telekinesisBreakIfOutOfRange(player: Player): boolean
	local state = telekinesisStates[player]
	local character = player.Character
	if not state or not character then
		return false
	end
	if not state.part.Parent then
		clearTelekinesis(player)
		return true
	end
	local root = getRoot(character)
	if not root then
		clearTelekinesis(player)
		return true
	end
	local maxDist = getTelekinesisMaxHoldDistance()
	if (state.part.Position - root.Position).Magnitude > maxDist then
		clearTelekinesis(player)
		return true
	end
	return false
end

-- Hold point floats at fixed distance along aim (viewport ray), not toward far raycast hits.
local TELEK_HOLD_ANCHOR_STUDS = 14
local TELEK_ANCHOR_LERP_ALPHA = 0.12

local function telekinesisHoldAimDirection(
	partPos: Vector3,
	hitPosition: Vector3?,
	aimFromCamera: Vector3?,
	root: BasePart
): Vector3
	if typeof(aimFromCamera) == "Vector3" and aimFromCamera.Magnitude > 0.05 then
		return aimFromCamera.Unit
	end
	if typeof(hitPosition) == "Vector3" then
		local delta = hitPosition - partPos
		if delta.Magnitude > 0.05 then
			return delta.Unit
		end
	end
	return root.CFrame.LookVector
end

local function updateTelekinesisTarget(player: Player, hitPosition: Vector3?, aimFromCamera: Vector3?)
	local state = telekinesisStates[player]
	local character = player.Character
	if not state or not character then
		return
	end
	if telekinesisBreakIfOutOfRange(player) then
		return
	end
	if state.mode == "deflective" then
		return
	end
	local root = getRoot(character)
	if not root then
		return
	end
	local dir = telekinesisHoldAimDirection(state.part.Position, hitPosition, aimFromCamera, root)
	local desiredAnchor = state.part.Position + dir * TELEK_HOLD_ANCHOR_STUDS
	state.lastAimWorld = state.part.Position + dir * 400
	local cur = state.anchor.Position
	state.anchor.CFrame = CFrame.new(cur:Lerp(desiredAnchor, TELEK_ANCHOR_LERP_ALPHA))
end

local TELEKINESIS_EYE_ENERGY_MULT = 0.85
local TELEKINESIS_HAND_ENERGY_MULT = 1.15
local TELEKINESIS_EYE_COOLDOWN_MULT = 0.85
local TELEKINESIS_HAND_COOLDOWN_MULT = 1.15
local TELEKINESIS_EYE_DAMAGE_MULT = 0.85
local TELEKINESIS_HAND_DAMAGE_MULT = 1.15
local TELEKINESIS_EYE_KNOCKBACK_MULT = 0.8
local TELEKINESIS_HAND_KNOCKBACK_MULT = 1.2

-- abilityMode token encodes direction ("dynamic"/"deflective") + channel style ("eye"/"hand").
-- Client encodes as: "dynamic_eye", "deflective_hand", etc.
local function telekinesisParseFromRemote(m: any): (string, string)
	local direction = "dynamic"
	local style = "hand"
	if type(m) == "string" then
		local l = string.lower(m)
		if l:find("deflective", 1, true) then
			direction = "deflective"
		end
		if l:find("eye", 1, true) then
			style = "eye"
		elseif l:find("hand", 1, true) then
			style = "hand"
		end
	end
	return direction, style
end

local function applyTelekinesis(
	player: Player,
	target: Instance?,
	hitPosition: Vector3?,
	abilityMode: any?,
	aimFromCamera: Vector3?
): boolean
	local character = player.Character
	if not character then
		return false
	end
	local root = getRoot(character)
	if not root then
		return false
	end
	local mode, channelStyle = telekinesisParseFromRemote(abilityMode)
	local part: BasePart?
	-- Deflective telekinesis must be able to push/grab anything too (targets, objects, projectiles).
	part = getProjectilePart(target) or getTargetPart(target)
	if not part or part:IsDescendantOf(character) then
		return false
	end
	if not isTelekinesisOrOrbingGrabTarget(target, part, character) then
		return false
	end
	-- Pickup range gate (hold break distance uses TelekinesisMaxHoldDistanceStuds separately).
	if (part.Position - root.Position).Magnitude > getTelekinesisGrabRange() then
		return false
	end
	local victimModel = findHumanoidAncestor(part)
	if victimModel and victimModel ~= character and victimModel:GetAttribute("EmpathicDeflectionActive") == true then
		local vRoot = getRoot(victimModel)
		if vRoot then
			pushCasterFromDeflector(player, vRoot.Position, 100, 20)
			pushDeflectedAbilitySubject(part, vRoot.Position, 88, 15)
		end
		return false
	end
	local humanoid = getHumanoid(character)
	local teleTrack: AnimationTrack? = nil
	if humanoid and mode == "dynamic" then
		teleTrack = playAnimation(humanoid, "78788244679103", true)
	end
	local humModel = findHumanoidAncestor(part)
	local victimHeldPlatformStand: Humanoid? = nil
	local victimHeldPlatformStandWas: boolean? = nil
	if humModel and humModel ~= character then
		local hum = humModel:FindFirstChildOfClass("Humanoid")
		if hum then
			victimHeldPlatformStand = hum
			victimHeldPlatformStandWas = hum.PlatformStand
			hum.PlatformStand = true
		end
	end
	clearTelekinesis(player)

	local grabbedRestoreNetworkTo: Player? = nil
	local victimPlrForNet = humModel and Players:GetPlayerFromCharacter(humModel) or nil
	if victimPlrForNet then
		grabbedRestoreNetworkTo = victimPlrForNet
		pcall(function()
			part:SetNetworkOwner(nil)
		end)
	end

	local anchor = Instance.new("Part")
	anchor.Name = "TelekinesisAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Parent = workspace
	anchor.CFrame = CFrame.new(part.Position)

	local a0 = Instance.new("Attachment")
	a0.Parent = part
	local a1 = Instance.new("Attachment")
	a1.Parent = anchor

	local align = Instance.new("AlignPosition")
	align.Attachment0 = a0
	align.Attachment1 = a1
	align.MaxForce = 220000
	align.MaxVelocity = 95
	align.Responsiveness = 28
	align.RigidityEnabled = false
	align.ApplyAtCenterOfMass = true
	align.Parent = part

	part.AssemblyLinearVelocity = Vector3.zero
	part.AssemblyAngularVelocity = Vector3.zero

	local projectileLinear: LinearVelocity? = nil
	local projectileLinearEnabled: boolean? = nil
	local projectileVectorVelocity: Vector3? = nil
	local maybeLinear = part:FindFirstChild("ProjectileLinearVelocity")
	if maybeLinear and maybeLinear:IsA("LinearVelocity") then
		projectileLinear = maybeLinear
		projectileLinearEnabled = maybeLinear.Enabled
		projectileVectorVelocity = maybeLinear.VectorVelocity
		maybeLinear.VectorVelocity = Vector3.zero
		maybeLinear.Enabled = false
	end

	local prevCanQuery = part.CanQuery
	part.CanQuery = false

	local aimDir0 = telekinesisHoldAimDirection(part.Position, hitPosition, aimFromCamera, root)
	local initialAimAlongRay = part.Position + aimDir0 * 400
	telekinesisStates[player] = {
		part = part,
		anchor = anchor,
		a0 = a0,
		a1 = a1,
		align = align,
		track = teleTrack,
		projectileLinear = projectileLinear,
		projectileLinearEnabled = projectileLinearEnabled,
		projectileVectorVelocity = projectileVectorVelocity,
		prevCanQuery = prevCanQuery,
		mode = mode,
		telekinesisChannelStyle = channelStyle,
		lastAimWorld = initialAimAlongRay,
		grabbedRestoreNetworkTo = grabbedRestoreNetworkTo,
		victimHeldPlatformStand = victimHeldPlatformStand,
		victimHeldPlatformStandWas = victimHeldPlatformStandWas,
	}
	setAbilityActive(player, "telekinesis", true)
	powerCastRemoteEvent:FireClient(player, "telekinesis_grab", part)
	updateTelekinesisTarget(player, hitPosition, aimFromCamera)
	return true
end

local function pushTelekinesisTarget(player: Player, hitPosition: Vector3?, aimFromCamera: Vector3?)
	local state = telekinesisStates[player]
	local character = player.Character
	if not state or not character then
		return
	end
	local root = getRoot(character)
	if not root or not state.part.Parent then
		return
	end
	if hitPosition and typeof(hitPosition) == "Vector3" then
		state.lastAimWorld = hitPosition
	end
	local dir: Vector3
	if state.mode == "dynamic" and (hitPosition or aimFromCamera) then
		dir = telekinesisHoldAimDirection(state.part.Position, hitPosition, aimFromCamera, root)
	else
		-- Deflective (and dynamic fallback): push through the line from player through the part.
		dir = state.part.Position - root.Position
		if dir.Magnitude < 0.01 then
			dir = root.CFrame.LookVector
		end
	end
	local channelStyle = state.telekinesisChannelStyle or "hand"
	local knockMult = if channelStyle == "eye" then TELEKINESIS_EYE_KNOCKBACK_MULT else TELEKINESIS_HAND_KNOCKBACK_MULT
	local dmgMult = if channelStyle == "eye" then TELEKINESIS_EYE_DAMAGE_MULT else TELEKINESIS_HAND_DAMAGE_MULT

	local pushSpeed = (if state.mode == "deflective" then 105 else 88) * knockMult
	local pushVelocity = dir.Unit * pushSpeed
	state.part.AssemblyLinearVelocity = pushVelocity
	if state.projectileLinear then
		state.projectileLinear.VectorVelocity = pushVelocity
		state.projectileLinear.Enabled = true
		state.projectileVectorVelocity = pushVelocity
	end
	local dmg = (if state.mode == "deflective" then 28 else 22) * dmgMult
	local pushHit = (if state.mode == "deflective" then 108 else 95) * knockMult
	local humModel = findHumanoidAncestor(state.part)
	local victimHumanoid = humModel and humModel ~= character and humModel:FindFirstChildOfClass("Humanoid")
	if humModel and victimHumanoid and humModel:GetAttribute("EmpathicDeflectionActive") == true then
		local vRoot = getRoot(humModel)
		if vRoot then
			-- Reflect: negate damage/ragdoll on the deflector; bounce the telekinetic subject away.
			pushCasterFromDeflector(player, vRoot.Position, 100 * knockMult, 20 * knockMult)
			local away = state.part.Position - vRoot.Position
			if away.Magnitude < 0.06 then
				away = Vector3.new(0, 1, 0)
			end
			local horizontal = (if state.mode == "deflective" then 88 else 52) * knockMult
			local yBoost = (if state.mode == "deflective" then 15 else 12) * knockMult
			local bounceVel = away.Unit * horizontal + Vector3.new(0, yBoost, 0)
			if state.projectileLinear then
				state.projectileLinear.VectorVelocity = bounceVel
				state.projectileLinear.Enabled = true
			else
				state.part.AssemblyLinearVelocity = bounceVel
			end
		end
		return
	end
	if victimHumanoid and victimHumanoid:IsA("Humanoid") then
		triggerTimedPlatformStand(victimHumanoid, 2.5)
		-- Deflective grab-push: guarantee damage on humanoids (impact tracker is for collateral / props).
		if state.mode == "deflective" and victimHumanoid.Health > 0 then
			GameHealth.applyDamage(victimHumanoid, dmg, player)
		end
		-- Deflective skips trackThrownObjectImpacts; apply knockback on HRP so players move (not only a grabbed limb).
		if state.mode == "deflective" and humModel then
			local hrp = humModel:FindFirstChild("HumanoidRootPart") :: BasePart?
			if hrp and hrp:IsA("BasePart") then
				hrp.AssemblyLinearVelocity = pushVelocity + Vector3.new(0, 14 * knockMult, 0)
			end
		end
	end
	if state.mode == "deflective" and victimHumanoid then
		return
	end
	trackThrownObjectImpacts(state.part, character, dmg, pushHit, 4)
end

local function attachAstralParticlesToCharacter(character: Model): { Instance }
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local prueAssets = assets and assets:FindFirstChild("PrueAssets")
	local template = prueAssets and prueAssets:FindFirstChild("AstralParticle")
	if not template then
		return {}
	end
	local roots: { Instance } = {}
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") then
			local clone = template:Clone()
			clone.Parent = d
			table.insert(roots, clone)
		end
	end
	return roots
end

local function collectEmittersUnderParticleRoot(root: Instance): { ParticleEmitter }
	local emitters: { ParticleEmitter } = {}
	if root:IsA("ParticleEmitter") then
		table.insert(emitters, root)
	end
	for _, desc in root:GetDescendants() do
		if desc:IsA("ParticleEmitter") then
			table.insert(emitters, desc)
		end
	end
	return emitters
end

-- Particles are parented to BaseParts. After 0.5s: tween emit rate to 0 then disable each emitter; after 3s: destroy roots.
local function scheduleAstralParticleLifecycle(player: Player, roots: { Instance }, sessionId: number)
	if #roots == 0 then
		return
	end
	task.delay(ASTRAL_PARTICLE_DISABLE_AFTER, function()
		local st = astralStates[player]
		if not st or st.astralParticleSessionId ~= sessionId then
			return
		end
		for _, root in roots do
			for _, pe in collectEmittersUnderParticleRoot(root) do
				if not pe.Parent then
					continue
				end
				local startRate = pe.Rate
				local tw = TweenService:Create(
					pe,
					TweenInfo.new(ASTRAL_PARTICLE_EMIT_FADE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ Rate = 0 }
				)
				tw:Play()
				tw.Completed:Once(function()
					if pe.Parent then
						pe.Enabled = false
						pe.Rate = startRate
					end
				end)
			end
		end
	end)
	task.delay(ASTRAL_PARTICLE_DESTROY_AFTER, function()
		local st = astralStates[player]
		if not st or st.astralParticleSessionId ~= sessionId then
			return
		end
		for _, root in roots do
			if root.Parent then
				root:Destroy()
			end
		end
		if astralStates[player] and astralStates[player].astralParticleSessionId == sessionId then
			astralStates[player].astralParticles = {}
		end
	end)
end

-- Exit / one-off bursts (no astral session validation)
local function scheduleStandaloneAstralParticleRoots(roots: { Instance })
	if #roots == 0 then
		return
	end
	task.delay(ASTRAL_PARTICLE_DISABLE_AFTER, function()
		for _, root in roots do
			for _, pe in collectEmittersUnderParticleRoot(root) do
				if not pe.Parent then
					continue
				end
				local startRate = pe.Rate
				local tw = TweenService:Create(
					pe,
					TweenInfo.new(ASTRAL_PARTICLE_EMIT_FADE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ Rate = 0 }
				)
				tw:Play()
				tw.Completed:Once(function()
					if pe.Parent then
						pe.Enabled = false
						pe.Rate = startRate
					end
				end)
			end
		end
	end)
	task.delay(ASTRAL_PARTICLE_DESTROY_AFTER, function()
		for _, root in roots do
			if root.Parent then
				root:Destroy()
			end
		end
	end)
end

local function cleanupAstralFor(player: Player, skipCharacterTransparencyRestore: boolean?)
	local state = astralStates[player]
	if not state then
		return
	end
	if not skipCharacterTransparencyRestore and state.characterTransparencySnap then
		for part, snap in state.characterTransparencySnap do
			if part.Parent then
				part.Transparency = snap.transparency
				part.LocalTransparencyModifier = snap.localMod
			end
		end
	end
	if state.astralParticles then
		for _, inst in state.astralParticles do
			if inst.Parent then
				inst:Destroy()
			end
		end
	end
	if state.clone and state.clone.Parent then
		state.clone:Destroy()
	end
	astralStates[player] = nil
end

local function applyAstralProjection(player: Player, hitPosition: Vector3?)
	local character = player.Character
	if not character then
		return
	end
	local root = getRoot(character)
	if not root then
		return
	end

	local active = astralStates[player]
	if active and active.clone and active.clone.Parent then
		local stash = active.characterTransparencySnap
		if stash then
			for part, _ in stash do
				if part.Parent then
					part.Transparency = 1
				end
			end
		end

		local returnRoots = attachAstralParticlesToCharacter(character)
		scheduleStandaloneAstralParticleRoots(returnRoots)

		local cloneRoot = active.clone:FindFirstChild("HumanoidRootPart")
		if cloneRoot and cloneRoot:IsA("BasePart") then
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			local goalPos = cloneRoot.Position + Vector3.new(0, 2.5, 0)
			local tweenBack = TweenService:Create(root, TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {
				CFrame = CFrame.new(goalPos, goalPos + root.CFrame.LookVector),
			})
			tweenBack:Play()
			tweenBack.Completed:Once(function()
				if root.Parent then
					root.AssemblyLinearVelocity = Vector3.zero
					root.AssemblyAngularVelocity = Vector3.zero
				end
				if stash then
					local fadeInfo = TweenInfo.new(ASTRAL_CHARACTER_TRANSPARENCY_TWEEN, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
					for part, snap in stash do
						if part.Parent then
							TweenService:Create(part, fadeInfo, {
								Transparency = snap.transparency,
								LocalTransparencyModifier = snap.localMod,
							}):Play()
						end
					end
				end
				cleanupAstralFor(player, true)
				setAbilityActive(player, "astral_projection", false)
			end)
		else
			if stash then
				local fadeInfo = TweenInfo.new(ASTRAL_CHARACTER_TRANSPARENCY_TWEEN, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
				for part, snap in stash do
					if part.Parent then
						TweenService:Create(part, fadeInfo, {
							Transparency = snap.transparency,
							LocalTransparencyModifier = snap.localMod,
						}):Play()
					end
				end
			end
			cleanupAstralFor(player, true)
			setAbilityActive(player, "astral_projection", false)
		end
		return
	end

	local targetPosition = if hitPosition then hitPosition + Vector3.new(0, 3, 0) else (root.Position + root.CFrame.LookVector * 24)
	local delta = targetPosition - root.Position
	if delta.Magnitude > 80 then
		targetPosition = root.Position + delta.Unit * 80
	end

	character.Archivable = true
	local clone = character:Clone()
	clone.Name = character.Name .. "_AstralBody"
	clone:PivotTo(character:GetPivot())
	for _, desc in clone:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.Anchored = false
			-- Collide so the physics clone doesn’t drop through the map; scripts stripped so it won’t be controlled.
			desc.CanCollide = true
		elseif desc:IsA("Script") or desc:IsA("LocalScript") then
			desc:Destroy()
		end
	end
	clone.Parent = workspace

	local characterTransparencySnap: { [BasePart]: { transparency: number, localMod: number } } = {}
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") then
			local p = d :: BasePart
			characterTransparencySnap[p] = {
				transparency = p.Transparency,
				localMod = p.LocalTransparencyModifier,
			}
			p.Transparency = 1
		end
	end

	local astralParticleRoots = attachAstralParticlesToCharacter(character)
	local astralParticleSessionId = os.clock()
	astralStates[player] = {
		clone = clone,
		astralParticles = astralParticleRoots,
		astralParticleSessionId = astralParticleSessionId,
		characterTransparencySnap = characterTransparencySnap,
	}
	setAbilityActive(player, "astral_projection", true)
	startContinuousDrain(player, "astral_projection", function()
		applyAstralProjection(player, nil)
	end)

	scheduleAstralParticleLifecycle(player, astralParticleRoots, astralParticleSessionId)

	local tweenOut = TweenService:Create(root, TweenInfo.new(0.65, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
		CFrame = CFrame.new(targetPosition, targetPosition + root.CFrame.LookVector),
	})
	tweenOut:Play()
	tweenOut.Completed:Once(function()
		local st = astralStates[player]
		if not st or not st.characterTransparencySnap then
			return
		end
		local snap = st.characterTransparencySnap
		local fadeInfo = TweenInfo.new(ASTRAL_CHARACTER_TRANSPARENCY_TWEEN, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
		for part, vals in snap do
			if part.Parent then
				TweenService:Create(part, fadeInfo, {
					Transparency = vals.transparency,
					LocalTransparencyModifier = vals.localMod,
				}):Play()
			end
		end
	end)

	local astralSfx = Instance.new("Sound")
	astralSfx.Name = "AstralProjectionSfx"
	astralSfx.SoundId = "rbxassetid://17569412308"
	astralSfx.Volume = 1
	astralSfx.Parent = root
	astralSfx:Play()
	astralSfx.Ended:Once(function()
		if astralSfx.Parent then
			astralSfx:Destroy()
		end
	end)
end

-- Paige orbing: all OrbingParticle clones are created on the server (replicated to clients).
local ORBING_GROUP_RADIUS_STUDS = 10
local TELEKINETIC_ORBING_END_VISIBILITY_FADE = 0.52

local function applyOrbing(player: Player, hitPosition: Vector3?): boolean
	local character = player.Character
	if not character then
		return false
	end
	local root = getRoot(character)
	if not root or not hitPosition then
		return false
	end
	local humanoid = getHumanoid(character)
	if not humanoid then
		return false
	end
	local orbAsset: Instance? = nil
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if assets then
		local paigeAssets = assets:FindFirstChild("PaigeAssets")
		if paigeAssets then
			orbAsset = paigeAssets:FindFirstChild("OrbingParticle")
		end
	end

	local companionModels: { Model } = {}
	local companionSeen: { [Model]: boolean } = {}
	local companionOffsetByModel: { [Model]: Vector3 } = {}
	local looseParts: { BasePart } = {}
	local looseOffsetByPart: { [BasePart]: Vector3 } = {}

	for _, part in workspace:GetPartBoundsInRadius(root.Position, ORBING_GROUP_RADIUS_STUDS) do
		if part:IsDescendantOf(character) then
			continue
		end
		local humModel = findHumanoidAncestor(part)
		if humModel and humModel ~= character then
			if not companionSeen[humModel] then
				local hrp = humModel:FindFirstChild("HumanoidRootPart") :: BasePart?
				if hrp and hrp:IsA("BasePart") then
					companionSeen[humModel] = true
					companionOffsetByModel[humModel] = hrp.Position - root.Position
					table.insert(companionModels, humModel)
				end
			end
			continue
		end
		local interactable = findInteractableAncestor(part)
		local chosenPart = getPartFromTarget(interactable)
		if chosenPart and not chosenPart:IsDescendantOf(character) and looseOffsetByPart[chosenPart] == nil then
			local hm = findHumanoidAncestor(chosenPart)
			if hm and companionSeen[hm] then
				continue
			end
			looseOffsetByPart[chosenPart] = chosenPart.Position - root.Position
			table.insert(looseParts, chosenPart)
		end
	end

	local orbInstances: { Instance } = {}
	local particleData: { { emitter: ParticleEmitter, startRate: number } } = {}
	local originalPartVisual: { [BasePart]: { transparency: number, localMod: number } } = {}
	local orbFadeDuration = 0.58
	local orbFadeStyle = Enum.EasingStyle.Sine
	local orbFadeDir = Enum.EasingDirection.InOut

	local function attachOrbVfxToBasePart(bp: BasePart)
		originalPartVisual[bp] = { transparency = bp.Transparency, localMod = bp.LocalTransparencyModifier }
		local fadeOut = TweenService:Create(bp, TweenInfo.new(orbFadeDuration, orbFadeStyle, orbFadeDir), {
			Transparency = 1,
		})
		fadeOut:Play()
		if orbAsset then
			local cloned = orbAsset:Clone()
			cloned.Parent = bp
			table.insert(orbInstances, cloned)
			for _, child in cloned:GetDescendants() do
				if child:IsA("ParticleEmitter") then
					table.insert(particleData, { emitter = child, startRate = child.Rate })
				end
			end
			if cloned:IsA("ParticleEmitter") then
				table.insert(particleData, { emitter = cloned, startRate = cloned.Rate })
			end
		end
	end

	local function attachOrbVfxToModel(m: Model)
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				attachOrbVfxToBasePart(d :: BasePart)
			end
		end
	end

	attachOrbVfxToModel(character)
	for _, compModel in companionModels do
		attachOrbVfxToModel(compModel)
	end
	for _, p in looseParts do
		attachOrbVfxToBasePart(p)
	end

	local orbStartSfx = Instance.new("Sound")
	orbStartSfx.Name = "OrbingStartSfx"
	orbStartSfx.SoundId = "rbxassetid://2496154914"
	orbStartSfx.Volume = 0.9
	orbStartSfx.Parent = root
	orbStartSfx:Play()
	orbStartSfx.Ended:Once(function()
		if orbStartSfx.Parent then
			orbStartSfx:Destroy()
		end
	end)

	local humSnaps: { { hum: Humanoid, ws: number, jp: number, ar: boolean } } = {}
	local function freezeHum(h: Humanoid)
		table.insert(humSnaps, { hum = h, ws = h.WalkSpeed, jp = h.JumpPower, ar = h.AutoRotate })
		h.WalkSpeed = 0
		h.JumpPower = 0
		h.AutoRotate = false
	end
	freezeHum(humanoid)
	for _, m in companionModels do
		local h = m:FindFirstChildOfClass("Humanoid")
		if h then
			freezeHum(h)
		end
	end

	local upTween = TweenService:Create(root, TweenInfo.new(0.48, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
		CFrame = root.CFrame + Vector3.new(0, 3, 0),
	})
	upTween:Play()
	upTween.Completed:Wait()

	local destTop = hitPosition + Vector3.new(0, 3, 0)
	local destBottom = hitPosition
	local currentLook = root.CFrame.LookVector

	root.CFrame = CFrame.new(destTop, destTop + currentLook)
	for _, m in companionModels do
		local off = companionOffsetByModel[m]
		local hrp = m:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hrp and off and hrp.Parent then
			hrp.CFrame = CFrame.new(destTop + off)
		end
	end
	for _, p in looseParts do
		local off = looseOffsetByPart[p]
		if p.Parent and off then
			p.CFrame = CFrame.new(destTop + off)
		end
	end

	local downTween = TweenService:Create(root, TweenInfo.new(0.48, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
		CFrame = CFrame.new(destBottom, destBottom + currentLook),
	})
	downTween:Play()
	downTween.Completed:Wait()

	local orbEndSfx = Instance.new("Sound")
	orbEndSfx.Name = "OrbingEndSfx"
	orbEndSfx.SoundId = "rbxassetid://2496155278"
	orbEndSfx.Volume = 0.9
	orbEndSfx.Parent = root
	orbEndSfx:Play()
	orbEndSfx.Ended:Once(function()
		if orbEndSfx.Parent then
			orbEndSfx:Destroy()
		end
	end)

	for part, original in originalPartVisual do
		if part.Parent then
			local fadeIn = TweenService:Create(part, TweenInfo.new(orbFadeDuration, orbFadeStyle, orbFadeDir), {
				Transparency = original.transparency,
				LocalTransparencyModifier = original.localMod,
			})
			fadeIn:Play()
		end
	end

	for _, snap in humSnaps do
		if snap.hum.Parent then
			snap.hum.WalkSpeed = snap.ws
			snap.hum.JumpPower = snap.jp
			snap.hum.AutoRotate = snap.ar
		end
	end

	task.spawn(function()
		local steps = 10
		for i = 1, steps do
			local alpha = i / steps
			for _, info in particleData do
				if info.emitter.Parent then
					info.emitter.Rate = info.startRate * (1 - alpha)
				end
			end
			task.wait(0.08)
		end
		for _, info in particleData do
			if info.emitter.Parent then
				info.emitter.Enabled = false
			end
		end
	end)

	task.delay(3, function()
		for _, inst in orbInstances do
			if inst.Parent then
				inst:Destroy()
			end
		end
	end)
	return true
end

stopTelekineticOrbing = function(player: Player, skipCooldown: boolean?)
	local state = telekineticOrbingStates[player]
	if not state then
		return
	end
	if state.orbVfx then
		local roots = state.orbVfx
		scheduleStandaloneAstralParticleRoots(roots)
	end
	if state.projectileLinear and state.projectileLinear.Parent then
		if state.projectileVectorVelocity then
			state.projectileLinear.VectorVelocity = state.projectileVectorVelocity
		end
		if state.projectileLinearEnabled ~= nil then
			state.projectileLinear.Enabled = state.projectileLinearEnabled
		end
	end
	if state.restoreNetworkOwnerTo and state.part.Parent then
		pcall(function()
			state.part:SetNetworkOwner(state.restoreNetworkOwnerTo)
		end)
	end
	if state.transparencySnap then
		local fadeInfo =
			TweenInfo.new(TELEKINETIC_ORBING_END_VISIBILITY_FADE, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
		for bp, vals in state.transparencySnap do
			if bp.Parent then
				TweenService:Create(bp, fadeInfo, {
					Transparency = vals.transparency,
					LocalTransparencyModifier = vals.localMod,
				}):Play()
			end
		end
	end
	telekineticOrbingStates[player] = nil
	setAbilityActive(player, "telekinetic_orbing", false)
	if not skipCooldown then
		beginCooldown(player, "telekinetic_orbing")
	end
end

local function orbingModeFromRemote(m: any): string
	if type(m) == "string" and string.lower(m) == "deflective" then
		return "deflective"
	end
	return "dynamic"
end

local function startTelekineticOrbing(player: Player, target: Instance?, abilityMode: any?): boolean
	local character = player.Character
	if not character then
		return false
	end
	local part = getProjectilePart(target) or getTargetPart(target)
	if not part or part:IsDescendantOf(character) then
		return false
	end
	if not isTelekinesisOrOrbingGrabTarget(target, part, character) then
		return false
	end
	local holderModel = findHumanoidAncestor(part)
	if holderModel and holderModel ~= character and holderModel:GetAttribute("EmpathicDeflectionActive") == true then
		local hRoot = getRoot(holderModel)
		if hRoot then
			pushCasterFromDeflector(player, hRoot.Position, 96, 18)
			pushDeflectedAbilitySubject(part, hRoot.Position, 84, 14)
		end
		return false
	end
	stopTelekineticOrbing(player, true)

	-- Snapshot before VFX/parent scripts can change visuals; restored when orbing ends.
	local transparencySnap: { [BasePart]: { transparency: number, localMod: number } } = {}
	local snapModelEarly = part:FindFirstAncestorOfClass("Model")
	if snapModelEarly then
		for _, d in snapModelEarly:GetDescendants() do
			if d:IsA("BasePart") then
				local bp = d :: BasePart
				transparencySnap[bp] = { transparency = bp.Transparency, localMod = bp.LocalTransparencyModifier }
			end
		end
	else
		transparencySnap[part] = { transparency = part.Transparency, localMod = part.LocalTransparencyModifier }
	end

	-- Orbing particles on the TARGET while holding telekinetic-orbing.
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local paigeAssets = assets and assets:FindFirstChild("PaigeAssets")
	local orbAsset = paigeAssets and paigeAssets:FindFirstChild("OrbingParticle")
	local orbVfx: { Instance } = {}
	if orbAsset then
		local targetModel = part:FindFirstAncestorOfClass("Model")
		if targetModel then
			for _, d in targetModel:GetDescendants() do
				if d:IsA("BasePart") then
					local cloned = orbAsset:Clone()
					cloned.Parent = d
					table.insert(orbVfx, cloned)
				end
			end
		else
			local cloned = orbAsset:Clone()
			cloned.Parent = part
			table.insert(orbVfx, cloned)
		end
	end

	local projectileLinear: LinearVelocity? = nil
	local projectileLinearEnabled: boolean? = nil
	local projectileVectorVelocity: Vector3? = nil
	local maybeLinear = part:FindFirstChild("ProjectileLinearVelocity")
	if maybeLinear and maybeLinear:IsA("LinearVelocity") then
		projectileLinear = maybeLinear
		projectileLinearEnabled = maybeLinear.Enabled
		projectileVectorVelocity = maybeLinear.VectorVelocity
		maybeLinear.Enabled = false
	end

	local restoreNetworkOwnerTo: Player? = nil
	local carrierModel = findHumanoidAncestor(part)
	if carrierModel then
		local carrierPlayer = Players:GetPlayerFromCharacter(carrierModel)
		if carrierPlayer then
			restoreNetworkOwnerTo = carrierPlayer
			pcall(function()
				part:SetNetworkOwner(nil)
			end)
		end
	end

	telekineticOrbingStates[player] = {
		part = part,
		-- Paige orbs feel better from a higher hover point.
		hoverPosition = part.Position + Vector3.new(0, 6, 0),
		projectileLinear = projectileLinear,
		projectileLinearEnabled = projectileLinearEnabled,
		projectileVectorVelocity = projectileVectorVelocity,
		mode = orbingModeFromRemote(abilityMode),
		orbVfx = orbVfx,
		restoreNetworkOwnerTo = restoreNetworkOwnerTo,
		transparencySnap = transparencySnap,
	}
	setAbilityActive(player, "telekinetic_orbing", true)
	startContinuousDrain(player, "telekinetic_orbing", function()
		stopTelekineticOrbing(player)
	end)
	return true
end

local function updateTelekineticOrbing(player: Player)
	local state = telekineticOrbingStates[player]
	if not state or not state.part.Parent then
		stopTelekineticOrbing(player, true)
		return
	end
	if state.mode == "deflective" then
		return
	end
	local toHover = state.hoverPosition - state.part.Position
	-- Smooth spring: apply force proportional to distance, but blend with current velocity.
	local desired = toHover * 8
	if toHover.Magnitude < 0.35 then
		desired = Vector3.zero
	end
	local cur = state.part.AssemblyLinearVelocity
	-- Lower alpha = smoother / less twitch.
	state.part.AssemblyLinearVelocity = cur:Lerp(desired, 0.22)
end

local function pushTelekineticOrbing(player: Player, hitPosition: Vector3?)
	local state = telekineticOrbingStates[player]
	local character = player.Character
	if not state or not state.part.Parent or not character then
		return
	end
	local root = getRoot(character)
	if not root then
		return
	end
	local frontPos = root.Position + root.CFrame.LookVector * 5 + Vector3.new(0, 3.5, 0)
	local grabbedModel = findHumanoidAncestor(state.part)
	local isOtherPlayer = grabbedModel and grabbedModel ~= character
		and Players:GetPlayerFromCharacter(grabbedModel) ~= nil
	-- Blend the transition for thrown objects; thrown players keep world position and launch toward aim.
	if not isOtherPlayer then
		local goalLook = frontPos + root.CFrame.LookVector
		local goal = CFrame.new(frontPos, goalLook)
		-- Keep it short so the throw still feels responsive, but avoids an obvious snap.
		TweenService:Create(
			state.part,
			TweenInfo.new(0.09, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{ CFrame = goal }
		):Play()
	end
	local aimWorld = if hitPosition then hitPosition else (root.Position + root.CFrame.LookVector * 35)
	local toMouse: Vector3
	if state.mode == "deflective" then
		toMouse = state.part.Position - root.Position
	else
		toMouse = aimWorld - state.part.Position
	end
	if toMouse.Magnitude < 0.01 then
		toMouse = root.CFrame.LookVector
	end
	local pushMag = if state.mode == "deflective" then 40 else 52
	local pushVelocity = toMouse.Unit * pushMag
	state.part.AssemblyLinearVelocity = pushVelocity
	if state.projectileLinear then
		state.projectileLinear.VectorVelocity = pushVelocity
		state.projectileLinear.Enabled = true
		state.projectileVectorVelocity = pushVelocity
	end
	local humModel = findHumanoidAncestor(state.part)
	if humModel and humModel ~= character then
		local hum = humModel:FindFirstChildOfClass("Humanoid")
		local hrp = humModel:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hum then
			triggerTimedPlatformStand(hum, 2.5)
		end
		-- Thrown body parts don't move the whole character; HRP must receive velocity for PvP.
		if hrp and hrp:IsA("BasePart") and hrp ~= state.part then
			local vPlr = Players:GetPlayerFromCharacter(humModel)
			if vPlr then
				pcall(function()
					hrp:SetNetworkOwner(nil)
				end)
			end
			hrp.AssemblyLinearVelocity = pushVelocity + Vector3.new(0, 12, 0)
			if vPlr then
				task.delay(0.14, function()
					if hrp.Parent then
						pcall(function()
							hrp:SetNetworkOwner(vPlr)
						end)
					end
				end)
			end
		end
	end
	local dmg = if state.mode == "deflective" then 18 else 22
	local pushHit = if state.mode == "deflective" then 78 else 95
	trackThrownObjectImpacts(state.part, character, dmg, pushHit, 4)
	stopTelekineticOrbing(player)
end

local function applyHealing(player: Player)
	local state = healingStates[player]
	if not state then
		return
	end
	local targetHumanoid = state.target
	local character = player.Character
	if not character or not targetHumanoid.Parent then
		return
	end
	local humanoid = getHumanoid(character)
	local root = getRoot(character)
	local targetModel = targetHumanoid.Parent
	if not root or not targetModel or not targetModel:IsA("Model") then
		return
	end
	local targetRoot = targetModel:FindFirstChild("HumanoidRootPart")
	if not targetRoot or not targetRoot:IsA("BasePart") then
		return
	end
	if targetModel == character then
		return
	end
	if (root.Position - targetRoot.Position).Magnitude > HEALING_MAX_RANGE then
		return
	end

	-- Instantly teleport in front of the healed target.
	-- Face toward the target so the player looks "at" who was healed.
	local desiredPos = targetRoot.Position + targetRoot.CFrame.LookVector * 3
	local lookAt = CFrame.new(desiredPos, targetRoot.Position + Vector3.new(0, 1, 0))
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	root.CFrame = lookAt
	GameHealth.heal(targetHumanoid, 2.5)
end

local function getHealingHandParts(character: Model): (BasePart?, BasePart?)
	local left = character:FindFirstChild("LeftHand")
	local right = character:FindFirstChild("RightHand")
	if left and left:IsA("BasePart") and right and right:IsA("BasePart") then
		return left, right
	end
	left = character:FindFirstChild("Left Arm")
	right = character:FindFirstChild("Right Arm")
	if left and left:IsA("BasePart") and right and right:IsA("BasePart") then
		return left, right
	end
	return nil, nil
end

local function cloneHealingAttachmentToHand(template: Instance, hand: BasePart, character: Model): Instance?
	local clone = template:Clone()
	if clone:IsA("Attachment") then
		clone.Parent = hand
		return clone
	end
	if clone:IsA("BasePart") then
		local p = clone :: BasePart
		p.Anchored = false
		p.CanCollide = false
		p.Massless = true
		p.CFrame = hand.CFrame
		p.Parent = character
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = hand
		weld.Part1 = p
		weld.Parent = p
		return clone
	end
	if clone:IsA("Model") then
		local m = clone :: Model
		m.Parent = character
		local pp: BasePart? = m.PrimaryPart
		if not pp then
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") then
					pp = d
					break
				end
			end
		end
		if not pp then
			m:Destroy()
			return nil
		end
		m.PrimaryPart = pp
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = false
				d.CanCollide = false
				d.Massless = true
			end
		end
		m:PivotTo(hand.CFrame)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = hand
		weld.Part1 = pp
		weld.Parent = pp
		return clone
	end
	clone.Parent = hand
	return clone
end

local function attachHealingHandVfx(character: Model): { Instance }
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local paigeAssets = assets and assets:FindFirstChild("PaigeAssets")
	local template = paigeAssets and paigeAssets:FindFirstChild("HealingAttachment")
	if not template then
		return {}
	end
	local leftHand, rightHand = getHealingHandParts(character)
	if not leftHand or not rightHand then
		return {}
	end
	local out: { Instance } = {}
	local leftClone = cloneHealingAttachmentToHand(template, leftHand, character)
	local rightClone = cloneHealingAttachmentToHand(template, rightHand, character)
	if leftClone then
		table.insert(out, leftClone)
	end
	if rightClone then
		table.insert(out, rightClone)
	end
	return out
end

local function fadeAndDestroyHealingHandVfx(handVfx: { Instance })
	if #handVfx == 0 then
		return
	end
	for _, root in handVfx do
		for _, d in root:GetDescendants() do
			if d:IsA("ParticleEmitter") then
				local pe = d :: ParticleEmitter
				local tw = TweenService:Create(
					pe,
					TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ Rate = 0 }
				)
				tw:Play()
				tw.Completed:Once(function()
					pe.Enabled = false
				end)
			end
		end
	end
	task.delay(2, function()
		for _, root in handVfx do
			if root.Parent then
				root:Destroy()
			end
		end
	end)
end

local function startHealing(player: Player, target: Instance?): boolean
	if not target then
		return false
	end
	local character = player.Character
	if not character then
		return false
	end
	local targetModel = findHumanoidAncestor(target)
	if not targetModel or targetModel == character then
		return false
	end
	local targetHumanoid = targetModel:FindFirstChildOfClass("Humanoid")
	if not targetHumanoid or targetHumanoid.Health <= 0 then
		return false
	end
	local healerHumanoid = getHumanoid(character)
	if not healerHumanoid then
		return false
	end
	local healerRoot = getRoot(character)
	local targetRoot = targetModel:FindFirstChild("HumanoidRootPart")
	if not healerRoot or not targetRoot or not targetRoot:IsA("BasePart") then
		return false
	end
	if (healerRoot.Position - targetRoot.Position).Magnitude > HEALING_MAX_RANGE then
		return false
	end
	local handVfx = attachHealingHandVfx(character)
	-- Asset is authored as a loop: play once here, stop in stopHealing when the channel ends.
	local healAnimTrack = playAnimation(healerHumanoid, "73402411553001", true)
	local targetMove = {
		walkSpeed = targetHumanoid.WalkSpeed,
		jumpPower = targetHumanoid.JumpPower,
		autoRotate = targetHumanoid.AutoRotate,
	}
	local healingVictimPlayer = Players:GetPlayerFromCharacter(targetModel)
	healingStates[player] = {
		target = targetHumanoid,
		walkSpeed = healerHumanoid.WalkSpeed,
		jumpPower = healerHumanoid.JumpPower,
		autoRotate = healerHumanoid.AutoRotate,
		handVfx = handVfx,
		healAnimTrack = healAnimTrack,
		targetMove = targetMove,
		healingVictimPlayer = healingVictimPlayer,
	}
	healerHumanoid.WalkSpeed = 0
	healerHumanoid.JumpPower = 0
	healerHumanoid.AutoRotate = false
	targetHumanoid.WalkSpeed = 0
	targetHumanoid.JumpPower = 0
	targetHumanoid.AutoRotate = false
	if healingVictimPlayer then
		setAbilityActive(healingVictimPlayer, "healing_target", true)
	end
	setAbilityActive(player, "healing", true)
	startContinuousDrain(player, "healing", function()
		stopHealing(player)
	end)
	task.spawn(function()
		while player.Parent and isAbilityActive(player, "healing") do
			applyHealing(player)
			task.wait(0.1)
		end
	end)
	return true
end

stopHealing = function(player: Player)
	local character = player.Character
	local healerHumanoid = character and getHumanoid(character)
	local state = healingStates[player]
	local handVfx = state and state.handVfx
	local healAnimTrack = state and state.healAnimTrack
	if healAnimTrack then
		pcall(function()
			healAnimTrack:Stop(0.15)
		end)
	end
	if healerHumanoid and state then
		healerHumanoid.WalkSpeed = state.walkSpeed
		healerHumanoid.JumpPower = state.jumpPower
		healerHumanoid.AutoRotate = state.autoRotate
	end
	if state and state.targetMove and state.target and state.target.Parent then
		local th = state.target
		th.WalkSpeed = state.targetMove.walkSpeed
		th.JumpPower = state.targetMove.jumpPower
		th.AutoRotate = state.targetMove.autoRotate
	end
	if state and state.healingVictimPlayer then
		setAbilityActive(state.healingVictimPlayer, "healing_target", false)
	end
	local root = character and getRoot(character)
	if root then
		root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
	end
	healingStates[player] = nil
	if handVfx then
		fadeAndDestroyHealingHandVfx(handVfx)
	end
	setAbilityActive(player, "healing", false)
	beginCooldown(player, "healing")
end

local function applyMolecularFreeze(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local root = getRoot(character)
	local humanoid = getHumanoid(character)
	if not root then
		return
	end
	if humanoid then
		playAnimation(humanoid, "130317535855114", false)
	end

	local hitParts = workspace:GetPartBoundsInRadius(root.Position, 45)
	local frozen: { BasePart } = {}
	local frozenHumanoids: {
		[Humanoid]: { walkSpeed: number, jumpPower: number, autoRotate: boolean },
	} = {}
	local frozenHumanoidParts: { [Humanoid]: { BasePart } } = {}
	local frozenModelsForMorality: { Model } = {}
	for _, part in hitParts do
		local humanoidModel = findHumanoidAncestor(part)
		if humanoidModel and humanoidModel ~= character then
			if not Morality.shouldMolecularFreezeAffect(player, humanoidModel) then
				continue
			end
				-- Empathic deflection should negate incoming crowd-control.
				if humanoidModel:GetAttribute("EmpathicDeflectionActive") == true then
					continue
				end
			local hum = humanoidModel:FindFirstChildOfClass("Humanoid")
			local humRoot = humanoidModel:FindFirstChild("HumanoidRootPart")
			if hum and humRoot and humRoot:IsA("BasePart") and not frozenHumanoids[hum] then
				table.insert(frozenModelsForMorality, humanoidModel)
				frozenHumanoids[hum] = {
					walkSpeed = hum.WalkSpeed,
					jumpPower = hum.JumpPower,
					autoRotate = hum.AutoRotate,
				}
				-- Anchor ALL parts so ragdolls / accessories can't keep moving.
				local partsToAnchor: { BasePart } = {}
				for _, d in humanoidModel:GetDescendants() do
					if d:IsA("BasePart") then
						local bp = d :: BasePart
						bp.Anchored = true
						table.insert(partsToAnchor, bp)
					end
				end
				frozenHumanoidParts[hum] = partsToAnchor
				hum.WalkSpeed = 0
				hum.JumpPower = 0
				hum.AutoRotate = false
				humanoidModel:SetAttribute("MolecularFrozen", true)
			end
		end

		local interactable = findInteractableAncestor(part)
		local targetPart = getPartFromTarget(interactable)
		if targetPart and not targetPart.Anchored and not targetPart:IsDescendantOf(character) then
			targetPart.Anchored = true
			table.insert(frozen, targetPart)
		end
	end

	Morality.onFreezeVictims(player, frozenModelsForMorality)

	freezeStates[player] = {
		frozenParts = frozen,
		frozenHumanoids = frozenHumanoids,
		-- Store anchored parts so we can reliably restore.
		frozenHumanoidParts = frozenHumanoidParts,
	}
	setAbilityActive(player, "molecular_freeze", true)
	startContinuousDrain(player, "molecular_freeze", function()
		local state = freezeStates[player]
		if not state then
			return
		end
		for _, part in state.frozenParts do
			if part.Parent then
				part.Anchored = false
			end
		end
		-- Restore anchored humanoid parts first, then mobility.
		local byHumParts = (state :: any).frozenHumanoidParts
		if type(byHumParts) == "table" then
			for hum, parts in byHumParts do
				if hum.Parent and type(parts) == "table" then
					for _, bp in parts do
						if typeof(bp) == "Instance" and bp:IsA("BasePart") and bp.Parent then
							bp.Anchored = false
						end
					end
				end
			end
		end
		for hum, stored in state.frozenHumanoids do
			local frModel = hum.Parent
			if frModel and frModel:IsA("Model") then
				frModel:SetAttribute("MolecularFrozen", false)
			end
			if hum.Parent then
				hum.WalkSpeed = stored.walkSpeed
				hum.JumpPower = stored.jumpPower
				hum.AutoRotate = stored.autoRotate
			end
		end
		freezeStates[player] = nil
		setAbilityActive(player, "molecular_freeze", false)
	end)
end

stopMolecularFreeze = function(player: Player)
	local state = freezeStates[player]
	if not state then
		setAbilityActive(player, "molecular_freeze", false)
		return
	end
	for _, part in state.frozenParts do
		if part.Parent then
			part.Anchored = false
		end
	end
	local byHumParts = state.frozenHumanoidParts
	if byHumParts then
		for hum, parts in byHumParts do
			if hum.Parent then
				for _, bp in parts do
					if bp.Parent then
						bp.Anchored = false
					end
				end
			end
		end
	end
	for hum, stored in state.frozenHumanoids do
		local frModel = hum.Parent
		if frModel and frModel:IsA("Model") then
			frModel:SetAttribute("MolecularFrozen", false)
		end
		if hum.Parent then
			hum.WalkSpeed = stored.walkSpeed
			hum.JumpPower = stored.jumpPower
			hum.AutoRotate = stored.autoRotate
		end
	end
	freezeStates[player] = nil
	setAbilityActive(player, "molecular_freeze", false)
	beginCooldown(player, "molecular_freeze")
end

local MOLECULAR_PIPER_CAST = {
	destructive = { Energy = 13, Cooldown = 2 },
	deviation = { Energy = 8, Cooldown = 1 },
}

local function piperMolecularModeFromRemote(m: any): string
	if type(m) == "string" then
		local l = string.lower(m)
		if l == "deviation" or l == "deflective" then
			return "deviation"
		end
		if l == "destructive" or l == "combustion" then
			return "destructive"
		end
	end
	return "destructive"
end

-- Single shared cooldown for both destructive and deviation (value = os.clock() when cooldown ends).
local MOLECULAR_COMBUSTION_SHARED_CD_KEY = "molecular_combustion_shared_cd"

local function canCastMolecularPiper(player: Player, mode: string): (boolean, { Energy: number, Cooldown: number }?)
	local cfg = MOLECULAR_PIPER_CAST[mode]
	if not cfg then
		return false, nil
	end
	local chosen = player:GetAttribute("ChosenCharacter")
	if type(chosen) ~= "string" or chosen ~= "Piper" then
		return false, nil
	end
	local character = player.Character
	if not character then
		return false, nil
	end
	local humanoid = getHumanoid(character)
	if not humanoid or humanoid.Health <= 0 then
		return false, nil
	end
	local byPlayer = cooldowns[player]
	if not byPlayer then
		byPlayer = {}
		cooldowns[player] = byPlayer
	end
	local cdEnd = byPlayer[MOLECULAR_COMBUSTION_SHARED_CD_KEY]
	if type(cdEnd) == "number" and os.clock() < cdEnd then
		return false, nil
	end
	local energy = player:GetAttribute("Energy")
	local current = if type(energy) == "number" then energy else CharacterConfig.DefaultEnergy
	if current < cfg.Energy then
		return false, nil
	end
	return true, cfg
end

local function beginMolecularPiperCooldown(player: Player, _mode: string, cooldownSeconds: number)
	local byPlayer = cooldowns[player]
	if not byPlayer then
		byPlayer = {}
		cooldowns[player] = byPlayer
	end
	byPlayer[MOLECULAR_COMBUSTION_SHARED_CD_KEY] = os.clock() + cooldownSeconds
	powerCastRemoteEvent:FireClient(player, "ability_cooldown", "molecular_combustion", cooldownSeconds)
end

-- GetPartBoundsInBox often misses avatars (CanQuery / replication). Scan players by HRP for reliable knockback.
local COMBUSTION_PLAYER_FALLBACK_RADIUS = 14

-- Molecular Combustion "fuel" (stronger knockback while fueled, shown in UI).
local MOLECULAR_FUEL_ATTRIBUTE = "MolecularCombustionFuel"
local MOLECULAR_FUEL_MAX = 100
local MOLECULAR_FUEL_DECAY_PER_SEC = 14
local MOLECULAR_FUEL_GAIN_PER_HIT = 18

local function getMolecularCombustionFuel(player: Player): number
	local v = player:GetAttribute(MOLECULAR_FUEL_ATTRIBUTE)
	if type(v) == "number" then
		return v
	end
	return 0
end

local function setMolecularCombustionFuel(player: Player, value: number)
	local clamped = math.clamp(value, 0, MOLECULAR_FUEL_MAX)
	player:SetAttribute(MOLECULAR_FUEL_ATTRIBUTE, clamped)
end

local function addMolecularCombustionFuel(player: Player, amount: number)
	if amount <= 0 then
		return
	end
	setMolecularCombustionFuel(player, getMolecularCombustionFuel(player) + amount)
end

local function getMolecularCombustionFuelRatio(player: Player): number
	return getMolecularCombustionFuel(player) / MOLECULAR_FUEL_MAX
end

local function applyCombustionKnockbackToHumanoidModel(
	player: Player,
	humanoidModel: Model,
	hitPosition: Vector3,
	affectedHumanoids: { [Humanoid]: boolean }
)
	local hum = humanoidModel:FindFirstChildOfClass("Humanoid")
	local humRoot = humanoidModel:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or not humRoot or not humRoot:IsA("BasePart") or hum.Health <= 0 or humanoidModel == player.Character then
		return
	end
	if affectedHumanoids[hum] then
		return
	end
	if humanoidModel:GetAttribute("EmpathicDeflectionActive") == true then
		local vRoot = getRoot(humanoidModel)
		if vRoot then
			pushCasterFromDeflector(player, vRoot.Position, 104, 24)
		end
		affectedHumanoids[hum] = true
		return
	end
	affectedHumanoids[hum] = true
	unfreezeVictimHumanoid(hum)
	-- Push mostly horizontally away from blast (avoid launching straight up when aim is above feet).
	local delta = humRoot.Position - hitPosition
	local horizontal = Vector3.new(delta.X, 0, delta.Z)
	local dir = if horizontal.Magnitude > 0.15
		then horizontal.Unit
		else (if delta.Magnitude > 0.08 then Vector3.new(delta.X, 0, delta.Z).Unit else Vector3.new(0, 0, -1))
	if dir.Magnitude < 0.01 then
		dir = Vector3.new(0, 0, -1)
	end
	local fuelRatio = getMolecularCombustionFuelRatio(player)
	local dmg = 20 * (1 + fuelRatio * 0.6)
	local pushH = 72 * (1 + fuelRatio * 0.7)
	local yBoost = 10 * (1 + fuelRatio * 0.25)
	GameHealth.applyDamage(hum, dmg, player)
	local victimPlr = Players:GetPlayerFromCharacter(humanoidModel)
	if victimPlr then
		pcall(function()
			humRoot:SetNetworkOwner(nil)
		end)
	end
	humRoot.AssemblyLinearVelocity = dir * pushH + Vector3.new(0, yBoost, 0)
	addMolecularCombustionFuel(player, MOLECULAR_FUEL_GAIN_PER_HIT)
	if victimPlr then
		task.delay(0.14, function()
			if humRoot.Parent then
				pcall(function()
					humRoot:SetNetworkOwner(victimPlr)
				end)
			end
		end)
	end
	triggerTimedPlatformStand(hum, 2.2)
end

local function applyMolecularCombustion(player: Player, _target: Instance?, hitPosition: Vector3?): boolean
	if not hitPosition then
		return false
	end
	local character = player.Character
	local deflectorModel = getEmpathicDeflectorNear(character, hitPosition, DEFLECT_COMBUSTION_RADIUS)
	if deflectorModel and deflectorModel ~= character then
		local dRoot = getRoot(deflectorModel)
		if dRoot then
			pushCasterFromDeflector(player, dRoot.Position, 104, 24)
			pushDeflectedCombustionBystanders(hitPosition, character, deflectorModel, dRoot, 5, 72, 12)
		end
		return true
	end
	local humanoid = character and getHumanoid(character)
	if humanoid then
		playAnimation(humanoid, "107060335668362", false)
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local piperAssets = if assets then assets:FindFirstChild("PiperAssets") else nil
	local assetAttachment: Attachment? = nil
	if piperAssets then
		local found = piperAssets:FindFirstChild("CombustionAttachment")
		if found and found:IsA("Attachment") then
			assetAttachment = found
		end
	end

	local effectPart = Instance.new("Part")
	effectPart.Name = "PiperCombustionFX"
	effectPart.Anchored = true
	effectPart.CanCollide = false
	effectPart.Transparency = 1
	effectPart.Size = Vector3.new(1, 1, 1)
	effectPart.CFrame = CFrame.new(hitPosition)
	effectPart.Parent = workspace

	local emitters: { { emitter: ParticleEmitter, startRate: number } } = {}
	if assetAttachment then
		local newAttachment = assetAttachment:Clone()
		newAttachment.Parent = effectPart
		for _, d in newAttachment:GetDescendants() do
			if d:IsA("ParticleEmitter") then
				table.insert(emitters, { emitter = d, startRate = d.Rate })
			end
		end
	end

	local castBox = Vector3.new(10, 10, 10)
	local hitParts = workspace:GetPartBoundsInBox(CFrame.new(hitPosition), castBox)
	local affectedHumanoids: { [Humanoid]: boolean } = {}
	local affectedParts: { [BasePart]: boolean } = {}
	local affectedProjectiles: { [BasePart]: boolean } = {}
	for _, part in hitParts do
		local projPart = getProjectilePart(part)
		if
			projPart
			and projPart:GetAttribute("IsProjectile") == true
			and character
			and not projPart:IsDescendantOf(character)
			and not affectedProjectiles[projPart]
		then
			affectedProjectiles[projPart] = true
			smoothAnchorRemoveProjectile(projPart)
			continue
		end
		local humanoidModel = findHumanoidAncestor(part)
		if humanoidModel then
			applyCombustionKnockbackToHumanoidModel(player, humanoidModel, hitPosition, affectedHumanoids)
		else
			local interactable = findInteractableAncestor(part)
			local targetPart = getPartFromTarget(interactable)
			if targetPart and not affectedParts[targetPart] then
				affectedParts[targetPart] = true
				unfreezeVictimPart(targetPart)
				local away = (targetPart.Position - hitPosition)
				local dir = if away.Magnitude > 0.01 then away.Unit else Vector3.new(0, 1, 0)
				targetPart.AssemblyLinearVelocity = dir * 58 + Vector3.new(0, 12, 0)
			end
		end
	end

	for _, plr in Players:GetPlayers() do
		if plr ~= player and plr.Character then
			local hrp = plr.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if hrp and (hrp.Position - hitPosition).Magnitude <= COMBUSTION_PLAYER_FALLBACK_RADIUS then
				applyCombustionKnockbackToHumanoidModel(player, plr.Character, hitPosition, affectedHumanoids)
			end
		end
	end

	task.spawn(function()
		local steps = 10
		for i = 1, steps do
			local alpha = i / steps
			for _, info in emitters do
				if info.emitter.Parent then
					info.emitter.Rate = info.startRate * (1 - alpha)
				end
			end
			task.wait(0.07)
		end
		for _, info in emitters do
			if info.emitter.Parent then
				info.emitter.Enabled = false
				pcall(function()
					info.emitter:Clear()
				end)
			end
		end
		task.wait(0.35)
		if effectPart.Parent then
			effectPart:Destroy()
		end
	end)

	-- Fallback cleanup if emitters list was empty (no asset) or task.spawn fails.
	task.delay(5.0, function()
		if effectPart.Parent then
			for _, d in effectPart:GetDescendants() do
				if d:IsA("ParticleEmitter") then
					d.Enabled = false
					pcall(function()
						d:Clear()
					end)
				end
			end
			effectPart:Destroy()
		end
	end)
	return true
end

local function applyPremonition(player: Player, _target: Instance?): boolean
	local character = player.Character
	if not character then
		return false
	end

	local pool: { Humanoid } = {}
	for _, d in workspace:GetDescendants() do
		if d:IsA("Humanoid") and d.Health > 0 then
			local m = d.Parent
			if m and m:IsA("Model") and m ~= character then
				table.insert(pool, d)
			end
		end
	end
	if #pool == 0 then
		return false
	end
	local targetHum = pool[math.random(1, #pool)]

	local PREMONITION_DURATION_SEC = 5
	powerCastRemoteEvent:FireClient(player, "premonition_view", targetHum, PREMONITION_DURATION_SEC)
	premonitionStates[player] = { target = targetHum }
	setAbilityActive(player, "premonition", true)
	task.delay(PREMONITION_DURATION_SEC, function()
		if not player.Parent then
			return
		end
		if not premonitionStates[player] then
			return
		end
		stopPremonition(player)
	end)
	return true
end

stopPremonition = function(player: Player)
	premonitionStates[player] = nil
	powerCastRemoteEvent:FireClient(player, "premonition_stop")
	setAbilityActive(player, "premonition", false)
	beginCooldown(player, "premonition")
end

local function cleanupLevitationState(player: Player)
	levitationLeapFinishToken[player] = (levitationLeapFinishToken[player] or 0) + 1
	local state = levitationStates[player]
	if not state then
		return
	end
	if state.track then
		state.track:Stop(0.12)
		state.track:Destroy()
	end
	if state.flightVelocity.Parent then
		state.flightVelocity:Destroy()
	end
	if state.orientation.Parent then
		state.orientation:Destroy()
	end
	if state.attachment.Parent then
		state.attachment:Destroy()
	end
	if state.humanoid.Parent then
		state.humanoid.JumpPower = state.jumpPower
		state.humanoid.AutoRotate = state.autoRotate
	end
	levitationStates[player] = nil
end

stopLevitation = function(player: Player)
	cleanupLevitationState(player)
	setAbilityActive(player, "levitation", false)
	beginCooldown(player, "levitation")
end

local function levitationModeFromRemote(m: any): string
	if type(m) == "string" then
		local l = string.lower(m)
		if l == "combat" then
			return "combat"
		end
		if l == "leap" then
			return "leap"
		end
		if l == "defensive" then
			return "defensive"
		end
		if l == "dynamic" then
			return "dynamic"
		end
		if l == "aggressive" then
			return "dynamic"
		end
	end
	return "dynamic"
end

local function findLevitationCombatTarget(player: Player, target: Instance?): Humanoid?
	if not target then
		return nil
	end
	local character = player.Character
	if not character then
		return nil
	end
	local root = getRoot(character)
	if not root then
		return nil
	end
	local model = findHumanoidAncestor(target)
	if not model or model == character then
		return nil
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return nil
	end
	local tRoot = model:FindFirstChild("HumanoidRootPart")
	if not tRoot or not tRoot:IsA("BasePart") then
		return nil
	end
	if (tRoot.Position - root.Position).Magnitude > 88 then
		return nil
	end
	return hum
end

-- Combat dash aims at this world position: target HRP, pulled toward the player by up to 2 studs (stop short of overlapping).
local LEVITATION_COMBAT_STANDOFF = 2
local LEVITATION_COMBAT_GOAL_EPS = 2.4

local function levitationCombatGoalWorldPos(tRoot: BasePart, root: BasePart): Vector3
	-- Use a flat approach direction so we stop 2 studs BEFORE the target (not past/around it).
	local delta = tRoot.Position - root.Position
	local flat = Vector3.new(delta.X, 0, delta.Z)
	local d = flat.Magnitude
	if d < 1e-3 then
		return tRoot.Position
	end
	local pullBack = math.min(LEVITATION_COMBAT_STANDOFF, math.max(0, d - 0.2))
	local goal = tRoot.Position - flat.Unit * pullBack
	goal = Vector3.new(goal.X, tRoot.Position.Y, goal.Z)
	return goal
end

local function applyLevitation(player: Player, abilityMode: any?, cameraLook: Vector3?, combatTargetInst: Instance?)
	local character = player.Character
	if not character then
		return
	end
	local root = getRoot(character)
	local humanoid = getHumanoid(character)
	if not root or not humanoid then
		return
	end
	cleanupLevitationState(player)

	local mode = levitationModeFromRemote(abilityMode)

	if mode == "leap" then
		-- Pure high jump (no animation, no forward dash).
		root.AssemblyLinearVelocity = Vector3.new(0, 108, 0)
		setAbilityActive(player, "levitation", true)
		levitationLeapFinishToken[player] = (levitationLeapFinishToken[player] or 0) + 1
		local token = levitationLeapFinishToken[player]
		task.delay(1.2, function()
			if not player.Parent or levitationLeapFinishToken[player] ~= token then
				return
			end
			if isAbilityActive(player, "levitation") then
				stopLevitation(player)
			end
		end)
		return
	end

	if mode == "defensive" then
		local targetY = root.Position.Y + 20
		local attachment = Instance.new("Attachment")
		attachment.Name = "LevitationAttachment"
		attachment.Parent = root

		local flightVelocity = Instance.new("LinearVelocity")
		flightVelocity.Name = "LevitationLinearVelocity"
		flightVelocity.Attachment0 = attachment
		flightVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
		flightVelocity.MaxForce = math.huge
		-- Kick up quickly, then the update loop maintains constant height.
		flightVelocity.VectorVelocity = Vector3.new(0, 60, 0)
		flightVelocity.Parent = root

		local orientation = Instance.new("AlignOrientation")
		orientation.Name = "LevitationOrientation"
		orientation.Attachment0 = attachment
		orientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
		orientation.RigidityEnabled = false
		orientation.MaxTorque = math.huge
		orientation.Responsiveness = 18
		orientation.CFrame = CFrame.new(Vector3.zero, root.CFrame.LookVector)
		orientation.Parent = root

		local levitationTrack = playAnimation(humanoid, "95502198265787", true)
		levitationStates[player] = {
			humanoid = humanoid,
			jumpPower = humanoid.JumpPower,
			autoRotate = humanoid.AutoRotate,
			velocity = Vector3.new(0, 60, 0),
			defensiveTargetY = targetY,
			attachment = attachment,
			flightVelocity = flightVelocity,
			orientation = orientation,
			track = levitationTrack,
			mode = "defensive",
			combatTarget = nil,
			combatPhase = nil,
			combatWindupStart = nil,
		}
		humanoid.JumpPower = 0
		humanoid.AutoRotate = false
		setAbilityActive(player, "levitation", true)
		startContinuousDrain(player, "levitation", function()
			cleanupLevitationState(player)
			setAbilityActive(player, "levitation", false)
		end)
		return
	end

	if mode == "combat" then
		local enemyHum = findLevitationCombatTarget(player, combatTargetInst)
		if not enemyHum then
			return
		end
		local enemyModel = enemyHum.Parent
		local enemyRoot = enemyModel and enemyModel:FindFirstChild("HumanoidRootPart")
		if not enemyRoot or not enemyRoot:IsA("BasePart") then
			return
		end
		local goalPos = levitationCombatGoalWorldPos(enemyRoot, root)
		local toGoal = goalPos - root.Position
		local flat = Vector3.new(toGoal.X, 0, toGoal.Z)
		local startVel = if flat.Magnitude > 0.12 then flat.Unit * 92 + Vector3.new(0, 22, 0) else Vector3.new(0, 18, 0)

		local attachment = Instance.new("Attachment")
		attachment.Name = "LevitationAttachment"
		attachment.Parent = root

		local flightVelocity = Instance.new("LinearVelocity")
		flightVelocity.Name = "LevitationLinearVelocity"
		flightVelocity.Attachment0 = attachment
		flightVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
		flightVelocity.MaxForce = math.huge
		flightVelocity.VectorVelocity = startVel
		flightVelocity.Parent = root

		local orientation = Instance.new("AlignOrientation")
		orientation.Name = "LevitationOrientation"
		orientation.Attachment0 = attachment
		orientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
		orientation.RigidityEnabled = false
		orientation.MaxTorque = math.huge
		orientation.Responsiveness = 22
		orientation.CFrame = CFrame.new(Vector3.zero, root.CFrame.LookVector)
		orientation.Parent = root

		local levitationTrack = playAnimation(humanoid, "95502198265787", true)
		levitationStates[player] = {
			humanoid = humanoid,
			jumpPower = humanoid.JumpPower,
			autoRotate = humanoid.AutoRotate,
			velocity = startVel,
			attachment = attachment,
			flightVelocity = flightVelocity,
			orientation = orientation,
			track = levitationTrack,
			mode = "combat",
			combatTarget = enemyHum,
			combatPhase = "dash",
			combatWindupStart = nil,
		}
		humanoid.JumpPower = 0
		humanoid.AutoRotate = false
		setAbilityActive(player, "levitation", true)
		startContinuousDrain(player, "levitation", function()
			cleanupLevitationState(player)
			setAbilityActive(player, "levitation", false)
		end)
		return
	end

	local startY = 6
	local attachment = Instance.new("Attachment")
	attachment.Name = "LevitationAttachment"
	attachment.Parent = root

	local flightVelocity = Instance.new("LinearVelocity")
	flightVelocity.Name = "LevitationLinearVelocity"
	flightVelocity.Attachment0 = attachment
	flightVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	flightVelocity.MaxForce = math.huge
	flightVelocity.VectorVelocity = Vector3.new(0, startY, 0)
	flightVelocity.Parent = root

	local orientation = Instance.new("AlignOrientation")
	orientation.Name = "LevitationOrientation"
	orientation.Attachment0 = attachment
	orientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	orientation.RigidityEnabled = false
	orientation.MaxTorque = math.huge
	orientation.Responsiveness = 18
	orientation.CFrame = CFrame.new(Vector3.zero, root.CFrame.LookVector)
	orientation.Parent = root

	local levitationTrack = playAnimation(humanoid, "95502198265787", true)
	levitationStates[player] = {
		humanoid = humanoid,
		jumpPower = humanoid.JumpPower,
		autoRotate = humanoid.AutoRotate,
		velocity = Vector3.new(0, startY, 0),
		attachment = attachment,
		flightVelocity = flightVelocity,
		orientation = orientation,
		track = levitationTrack,
		mode = "dynamic",
		combatTarget = nil,
		combatPhase = nil,
		combatWindupStart = nil,
	}
	humanoid.JumpPower = 0
	humanoid.AutoRotate = false
	setAbilityActive(player, "levitation", true)
	startContinuousDrain(player, "levitation", function()
		cleanupLevitationState(player)
		setAbilityActive(player, "levitation", false)
	end)
end

local function findClosestHumanoidNearPositionForDeviation(
	pos: Vector3,
	excludeModel: Model,
	maxDist: number
): (Humanoid?, BasePart?)
	local bestHum: Humanoid?
	local bestHrp: BasePart?
	local bestD = maxDist
	for _, d in workspace:GetDescendants() do
		if d:IsA("Humanoid") and d.Health > 0 then
			local m = d.Parent
			if m and m:IsA("Model") and m ~= excludeModel then
				local hrp = m:FindFirstChild("HumanoidRootPart") :: BasePart?
				if hrp and hrp:IsA("BasePart") then
					local dist = (hrp.Position - pos).Magnitude
					if dist < bestD then
						bestD = dist
						bestHum = d
						bestHrp = hrp
					end
				end
			end
		end
	end
	return bestHum, bestHrp
end

local function resolveMolecularDeviationPushVictim(
	player: Player,
	target: Instance?,
	character: Model,
	root: BasePart
): (Humanoid?, BasePart?)
	local clickedModel = target and findHumanoidAncestor(target)
	if clickedModel and clickedModel ~= character then
		local hum = clickedModel:FindFirstChildOfClass("Humanoid")
		local hrp = clickedModel:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hum and hrp and hrp:IsA("BasePart") and hum.Health > 0 then
			if (hrp.Position - root.Position).Magnitude <= MOLECULAR_DEVIATION_MAX_TARGET_RANGE then
				return hum, hrp
			end
		end
	end
	local proj = target and getProjectilePart(target)
	if proj then
		local hum, hrp = findClosestHumanoidNearPositionForDeviation(proj.Position, character, 22)
		if
			hum
			and hrp
			and (hrp.Position - root.Position).Magnitude <= MOLECULAR_DEVIATION_MAX_TARGET_RANGE
		then
			return hum, hrp
		end
	end
	return findClosestHumanoidNearPositionForDeviation(root.Position, character, MOLECULAR_DEVIATION_MAX_TARGET_RANGE)
end

local function applyMolecularDeviationKnockback(player: Player, hum: Humanoid, hrp: BasePart)
	local character = player.Character
	if not character then
		return
	end
	local root = getRoot(character)
	if not root then
		return
	end
	local victimModel = hum.Parent
	if not victimModel or not victimModel:IsA("Model") then
		return
	end
	if victimModel:GetAttribute("EmpathicDeflectionActive") == true then
		local vRoot = getRoot(victimModel)
		if vRoot then
			pushCasterFromDeflector(player, vRoot.Position, 95, 22)
		end
		return
	end
	local away = hrp.Position - root.Position
	local dir = if away.Magnitude > 0.06 then away.Unit else root.CFrame.LookVector
	local fuelRatio = getMolecularCombustionFuelRatio(player)
	local pushH = MOLECULAR_DEVIATION_PUSH_STUDS * (1 + fuelRatio * 0.7)
	local pushY = MOLECULAR_DEVIATION_PUSH_Y * (1 + fuelRatio * 0.25)
	hrp.AssemblyLinearVelocity = dir * pushH + Vector3.new(0, pushY, 0)
	triggerTimedPlatformStand(hum, 2)
	addMolecularCombustionFuel(player, MOLECULAR_FUEL_GAIN_PER_HIT * 0.75)
end

local function applyMolecularDeviation(player: Player, target: Instance?): boolean
	if not isValidMolecularDeviationTarget(player, target) then
		return false
	end
	local character = player.Character
	if not character then
		return false
	end
	local root = getRoot(character)
	if not root then
		return false
	end
	local reflected = reflectProjectilesAround(player, 36, true, false, true)
	local victimHum, victimHrp = resolveMolecularDeviationPushVictim(player, target, character, root)
	if reflected <= 0 and not victimHum then
		return false
	end
	if victimHum and victimHrp then
		applyMolecularDeviationKnockback(player, victimHum, victimHrp)
	end
	local humanoid = getHumanoid(character)
	if humanoid then
		playAnimation(humanoid, "130317535855114", false)
	end
	return true
end

local function updateLevitationControl(player: Player, moveDirection: Vector3?, cameraLook: Vector3?)
	local state = levitationStates[player]
	if not state then
		return
	end
	if not state.flightVelocity.Parent then
		cleanupLevitationState(player)
		return
	end
	local character = player.Character
	local root = character and getRoot(character)
	if not root then
		stopLevitation(player)
		return
	end

	local look = if cameraLook then cameraLook else Vector3.new(0, 0, -1)
	local isPhoebe = player:GetAttribute("ChosenCharacter") == "Phoebe"
	-- Lean: opposite of previous tilt (negative Y in look = tilt the other way).
	local PHOEBE_BACK_TILT_Y = -0.38

	if state.mode == "defensive" then
		local targetY = state.defensiveTargetY
		if typeof(targetY) ~= "number" then
			targetY = root.Position.Y + 20
			state.defensiveTargetY = targetY
		end

		local errY = targetY - root.Position.Y
		local yVel = math.clamp(errY * 2.2, -18, 28)
		if math.abs(errY) < 0.15 then
			yVel = 0
		end
		-- Hold height: no lateral flight, only vertical servo.
		state.flightVelocity.VectorVelocity = Vector3.new(0, yVel, 0)

		if state.orientation.Parent then
			local flatLook = Vector3.new(look.X, 0, look.Z)
			if flatLook.Magnitude > 0.01 then
				local desiredLook = flatLook.Unit
				if isPhoebe then
					desiredLook = Vector3.new(desiredLook.X, PHOEBE_BACK_TILT_Y, desiredLook.Z)
				end
				state.orientation.CFrame = CFrame.new(Vector3.zero, desiredLook)
			end
		end
		return
	end

	if state.mode == "combat" then
		local targetHum = state.combatTarget
		if not targetHum or not targetHum.Parent or targetHum.Health <= 0 then
			stopLevitation(player)
			return
		end
		local enemyModel = targetHum.Parent
		local tRoot = enemyModel and enemyModel:FindFirstChild("HumanoidRootPart")
		if not tRoot or not tRoot:IsA("BasePart") then
			stopLevitation(player)
			return
		end

		if state.combatPhase == "windup" then
			state.velocity = Vector3.zero
			state.flightVelocity.VectorVelocity = Vector3.zero
			local startT = state.combatWindupStart
			if type(startT) == "number" and (os.clock() - startT) >= 0.5 then
				-- Empathic deflection should negate levitation hit on the deflector.
				if enemyModel and enemyModel:IsA("Model") and enemyModel:GetAttribute("EmpathicDeflectionActive") == true then
					stopLevitation(player)
					pushCasterFromDeflector(player, tRoot.Position, 95, 26)
					return
				end
				local away = tRoot.Position - root.Position
				local dir = if away.Magnitude > 0.08 then away.Unit else root.CFrame.LookVector
				GameHealth.applyDamage(targetHum, 34, player)
				tRoot.AssemblyLinearVelocity = dir * 95 + Vector3.new(0, 26, 0)
				triggerTimedPlatformStand(targetHum, 2.4)
				stopLevitation(player)
			end
			if state.orientation.Parent then
				local flatLook = Vector3.new(look.X, 0, look.Z)
				if flatLook.Magnitude > 0.01 then
					local desiredLook = flatLook.Unit
					if isPhoebe then
						-- Lean/tilt back while levitating.
						desiredLook = Vector3.new(desiredLook.X, PHOEBE_BACK_TILT_Y, desiredLook.Z)
					end
					state.orientation.CFrame = CFrame.new(Vector3.zero, desiredLook)
				end
			end
			return
		end

		local goalPos = levitationCombatGoalWorldPos(tRoot, root)
		local toGoal = goalPos - root.Position
		local distToGoal = toGoal.Magnitude
		if distToGoal <= LEVITATION_COMBAT_GOAL_EPS then
			state.combatPhase = "windup"
			state.combatWindupStart = os.clock()
			state.velocity = Vector3.zero
			state.flightVelocity.VectorVelocity = Vector3.zero
			if state.orientation.Parent then
				local flatLook = Vector3.new(look.X, 0, look.Z)
				if flatLook.Magnitude > 0.01 then
					local desiredLook = flatLook.Unit
					if isPhoebe then
						desiredLook = Vector3.new(desiredLook.X, PHOEBE_BACK_TILT_Y, desiredLook.Z)
					end
					state.orientation.CFrame = CFrame.new(Vector3.zero, desiredLook)
				end
			end
			return
		end

		local dir = toGoal.Unit
		local speed = math.clamp(distToGoal * 6, 34, 82)
		local desired = dir * speed
		state.velocity = state.velocity:Lerp(desired, 0.28)
		state.flightVelocity.VectorVelocity = state.velocity
		if state.orientation.Parent then
			local flat = Vector3.new(dir.X, 0, dir.Z)
			if flat.Magnitude > 0.01 then
				local desiredLook = flat.Unit
				if isPhoebe then
					desiredLook = Vector3.new(desiredLook.X, PHOEBE_BACK_TILT_Y, desiredLook.Z)
				end
				state.orientation.CFrame = CFrame.new(Vector3.zero, desiredLook)
			end
		end
		return
	end

	local lerpAlpha = 0.038
	local move = if moveDirection then moveDirection else Vector3.zero

	if isPhoebe and move.Magnitude > 0.04 then
		-- Full 3D toward mouse (client sends unit vector root → cursor, all axes).
		local dir = move.Unit
		local cruise = 40
		local hoverLift = 3.5
		local desiredVelocity = dir * cruise + Vector3.new(0, hoverLift, 0)
		state.velocity = state.velocity:Lerp(desiredVelocity, lerpAlpha)
		state.flightVelocity.VectorVelocity = state.velocity
		if state.orientation.Parent then
			local desiredLook = dir
			desiredLook = Vector3.new(desiredLook.X, PHOEBE_BACK_TILT_Y, desiredLook.Z)
			if desiredLook.Magnitude > 0.02 then
				state.orientation.CFrame = CFrame.new(Vector3.zero, desiredLook.Unit)
			end
		end
		return
	end

	local hoverVertical = 4
	local vertMult = 10
	local horiz = 12
	local verticalControl = 0
	if math.abs(look.Y) > 0.1 then
		verticalControl = look.Y * vertMult
	end
	local desiredVelocity = Vector3.new(move.X * horiz, hoverVertical + verticalControl, move.Z * horiz)
	state.velocity = state.velocity:Lerp(desiredVelocity, lerpAlpha)
	state.flightVelocity.VectorVelocity = state.velocity
	if state.orientation.Parent then
		local flatLook = Vector3.new(look.X, 0, look.Z)
		if flatLook.Magnitude > 0.01 then
			local desiredLook = flatLook.Unit
			if isPhoebe then
				desiredLook = Vector3.new(desiredLook.X, PHOEBE_BACK_TILT_Y, desiredLook.Z)
			end
			state.orientation.CFrame = CFrame.new(Vector3.zero, desiredLook)
		end
	end
end

-- Playable Belthazor: projectiles from right hand toward aim; shimmer uses mouse/ray hit (client-sent world position).
local BELTHAZOR_TAG = CharacterConfig.BelthazorTagName or "Belthazor"
local CfgAny = CharacterConfig :: any

local function getBelthazorRightHand(model: Model): BasePart?
	local r = model:FindFirstChild("RightHand")
	if r and r:IsA("BasePart") then
		return r
	end
	r = model:FindFirstChild("Right Arm")
	if r and r:IsA("BasePart") then
		return r
	end
	return getRoot(model)
end

local function buildBelthazorProjectile(
	origin: CFrame,
	size: number,
	color: Color3,
	projectileName: string
): BasePart
	local ball = Instance.new("Part")
	ball.Name = projectileName
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(size, size, size)
	ball.Material = Enum.Material.Neon
	ball.Color = color
	ball.CanCollide = false
	ball.CanQuery = true
	ball.Anchored = false
	ball.CFrame = origin
	ball:SetAttribute("IsProjectile", true)

	local interactableTag = Instance.new("BoolValue")
	interactableTag.Name = "Interactable"
	interactableTag.Value = true
	interactableTag.Parent = ball

	local attachment = Instance.new("Attachment")
	attachment.Name = "ProjectileAttachment"
	attachment.Parent = ball

	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "ProjectileLinearVelocity"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.MaxForce = math.huge
	velocity.Enabled = true
	velocity.Parent = ball

	return ball
end

local function launchBelthazorProjectile(
	player: Player,
	aimWorld: Vector3,
	opts: { speed: number, damage: number, size: number, lifetime: number, color: Color3, name: string, push: number }
): boolean
	local casterModel = player.Character
	if not casterModel then
		return false
	end
	local hand = getBelthazorRightHand(casterModel)
	if not hand then
		return false
	end
	local offset = aimWorld - hand.Position
	local dir = if offset.Magnitude > 0.15 then offset.Unit else hand.CFrame.LookVector
	local spawnPos = hand.Position + dir * (math.max(hand.Size.Magnitude * 0.35, 1.2) + opts.size * 0.35)
	local ball = buildBelthazorProjectile(CFrame.new(spawnPos), opts.size, opts.color, opts.name)
	ball.Parent = workspace

	local lv = ball:FindFirstChild("ProjectileLinearVelocity")
	if lv and lv:IsA("LinearVelocity") then
		lv.VectorVelocity = dir * opts.speed
	end

	local touched = false
	ball.Touched:Connect(function(hit: BasePart)
		if touched or not ball.Parent then
			return
		end
		if hit:IsDescendantOf(casterModel) then
			return
		end
		local victimModel = hit:FindFirstAncestorOfClass("Model")
		if not victimModel then
			return
		end
		local hum = victimModel:FindFirstChildOfClass("Humanoid")
		local root = victimModel:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hum or hum.Health <= 0 or not root then
			return
		end
		if CollectionService:HasTag(victimModel, BELTHAZOR_TAG) then
			return
		end
		touched = true
		GameHealth.applyDamage(hum, opts.damage, player)
		local away = root.Position - ball.Position
		local pushDir = if away.Magnitude > 0.01 then away.Unit else dir
		root.AssemblyLinearVelocity = pushDir * opts.push + Vector3.new(0, 20, 0)
		victimModel:SetAttribute("Ragdolled", true)
		task.delay(2.4, function()
			if victimModel.Parent and hum.Health > 0 and victimModel:GetAttribute("Ragdolled") == true then
				victimModel:SetAttribute("Ragdolled", false)
			end
		end)
		ball:Destroy()
	end)

	Debris:AddItem(ball, opts.lifetime)
	return true
end

local function castBelthazorFireball(player: Player, hitPos: Vector3?): boolean
	if typeof(hitPos) ~= "Vector3" then
		return false
	end
	local spd = CfgAny.BelthazorFireballSpeed
	local dmg = CfgAny.BelthazorFireballDamage
	local sz = CfgAny.BelthazorFireballSizeStuds
	local life = CfgAny.BelthazorFireballLifetime
	if type(spd) ~= "number" then
		spd = 100
	end
	if type(dmg) ~= "number" then
		dmg = 24
	end
	if type(sz) ~= "number" then
		sz = 3
	end
	if type(life) ~= "number" then
		life = 5
	end
	return launchBelthazorProjectile(player, hitPos, {
		speed = spd,
		damage = dmg,
		size = sz,
		lifetime = life,
		color = Color3.fromRGB(255, 110, 28),
		name = "BelthazorFireball",
		push = 92,
	})
end

local function castBelthazorEnergyBall(player: Player, hitPos: Vector3?): boolean
	if typeof(hitPos) ~= "Vector3" then
		return false
	end
	local spd = CfgAny.BelthazorEnergyBallSpeed
	local dmg = CfgAny.BelthazorEnergyBallDamage
	local sz = CfgAny.BelthazorEnergyBallSizeStuds
	local life = CfgAny.BelthazorEnergyBallLifetime
	if type(spd) ~= "number" then
		spd = 92
	end
	if type(dmg) ~= "number" then
		dmg = 46
	end
	if type(sz) ~= "number" then
		sz = 3.5
	end
	if type(life) ~= "number" then
		life = 5
	end
	return launchBelthazorProjectile(player, hitPos, {
		speed = spd,
		damage = dmg,
		size = sz,
		lifetime = life,
		color = Color3.fromRGB(120, 220, 255),
		name = "BelthazorEnergyBall",
		push = 105,
	})
end

local function castBelthazorShimmer(player: Player, hitPos: Vector3?): boolean
	if typeof(hitPos) ~= "Vector3" then
		return false
	end
	local character = player.Character
	if not character then
		return false
	end
	local hum = getHumanoid(character)
	local hrp = getRoot(character)
	if not hum or not hrp or hum.Health <= 0 then
		return false
	end
	if character:GetAttribute("Ragdolled") == true then
		return false
	end
	local maxR = CfgAny.BelthazorShimmerMaxRangeStuds
	if type(maxR) ~= "number" then
		maxR = 78
	end
	local startPos = hrp.Position
	if (hitPos - startPos).Magnitude > maxR then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	-- Long vertical ray from above aim XZ so we never use sky/deep-void Y as floor.
	local rayOrigin = Vector3.new(hitPos.X, math.max(hitPos.Y, startPos.Y) + 120, hitPos.Z)
	local res = workspace:Raycast(rayOrigin, Vector3.new(0, -500, 0), params)
	if not res then
		return false
	end
	local surface = res.Position
	local up = res.Normal
	if up.Magnitude < 0.1 then
		up = Vector3.new(0, 1, 0)
	else
		up = up.Unit
	end
	local hrpHalf = hrp.Size.Y * 0.5
	local clearance = 0.4
	-- Stand on surface along its normal (HRP pivot ≈ hip height + half height above feet contact).
	local newPos = surface + up * (clearance + hum.HipHeight + hrpHalf + 0.12)
	local flatLook = Vector3.new(hitPos.X, newPos.Y, hitPos.Z)
	local goalCf: CFrame
	if (flatLook - newPos).Magnitude < 0.08 then
		goalCf = CFrame.new(newPos) * (hrp.CFrame - hrp.CFrame.Position)
	else
		goalCf = CFrame.new(newPos, flatLook)
	end

	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero

	local tweenDur = 0.42
	local tw = TweenService:Create(hrp, TweenInfo.new(tweenDur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = goalCf,
	})
	tw:Play()
	return true
end

handlers = {
	telekinesis = function(player, target, hitPos)
		return applyTelekinesis(player, target, hitPos, nil, nil)
	end,
	astral_projection = function(player, _, hitPos)
		applyAstralProjection(player, hitPos)
		return isAbilityActive(player, "astral_projection")
	end,
	orbing = function(player, _, hitPos)
		return applyOrbing(player, hitPos)
	end,
	telekinetic_orbing = function(player, target, hitPos)
		return startTelekineticOrbing(player, target, nil)
	end,
	healing = function(player, target)
		return startHealing(player, target)
	end,
	molecular_freeze = function(player)
		applyMolecularFreeze(player)
		return isAbilityActive(player, "molecular_freeze")
	end,
	molecular_combustion = function(player, target, hitPos)
		return applyMolecularCombustion(player, target, hitPos)
	end,
	premonition = function(player, _target)
		return applyPremonition(player, nil)
	end,
	levitation = function(player)
		applyLevitation(player, nil, nil, nil)
		return isAbilityActive(player, "levitation")
	end,
	empathic_deflection = function(player)
		applyEmpathicDeflection(player)
		return isAbilityActive(player, "empathic_deflection")
	end,
	belthazor_fireball = function(player, _target, hitPos)
		return castBelthazorFireball(player, hitPos)
	end,
	belthazor_energy_ball = function(player, _target, hitPos)
		return castBelthazorEnergyBall(player, hitPos)
	end,
	belthazor_shimmer = function(player, _target, hitPos)
		return castBelthazorShimmer(player, hitPos)
	end,
}

powerCastRemoteEvent.OnServerEvent:Connect(function(
	player: Player,
	powerId: string,
	target: Instance?,
	hitPosition: Vector3?,
	castAction: string?,
	cameraLook: Vector3?,
	abilityMode: string?
)
	if type(powerId) ~= "string" then
		return
	end
	local character = player.Character
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	if character
		and (character:GetAttribute("Ragdolled") == true or (hum and hum.PlatformStand == true)) then
		clearTelekinesis(player)
		stopMolecularFreeze(player)
		stopPremonition(player)
		stopLevitation(player)
		stopHealing(player)
		stopTelekineticOrbing(player, true)
		stopEmpathicDeflection(player, true)
		return
	end
	if shouldBlockPowerCastDueToConcurrentAbility(player, powerId, castAction) then
		return
	end
	if astralStates[player] and powerId ~= "astral_projection" then
		return
	end
	if powerId == "astral_projection" and type(castAction) == "string" then
		if castAction == "start" then
			local allowed, _ = canCast(player, powerId)
			if allowed then
				applyAstralProjection(player, hitPosition)
				if isAbilityActive(player, "astral_projection") and spendEnergy(player, powersById[powerId].Energy) then
					setLastUsedAbility(player, powerId)
				else
					cleanupAstralFor(player)
					setAbilityActive(player, "astral_projection", false)
				end
			end
		elseif castAction == "stop" then
			if astralStates[player] then
				applyAstralProjection(player, hitPosition)
			end
			beginCooldown(player, "astral_projection")
		end
		return
	end
	if powerId == "molecular_freeze" and type(castAction) == "string" then
		if castAction == "start" then
			local allowed, _ = canCast(player, powerId)
			if allowed then
				applyMolecularFreeze(player)
				if isAbilityActive(player, "molecular_freeze") and spendEnergy(player, powersById[powerId].Energy) then
					setLastUsedAbility(player, powerId)
				else
					stopMolecularFreeze(player)
				end
			end
		elseif castAction == "stop" then
			stopMolecularFreeze(player)
		end
		return
	end
	if powerId == "premonition" and type(castAction) == "string" then
		if castAction == "start" then
			local allowed, _ = canCast(player, powerId)
			if allowed then
				applyPremonition(player, nil)
				if isAbilityActive(player, "premonition") and spendEnergy(player, powersById[powerId].Energy) then
					setLastUsedAbility(player, powerId)
				else
					stopPremonition(player)
				end
			end
		elseif castAction == "stop" then
			stopPremonition(player)
		end
		return
	end
	if powerId == "molecular_combustion" then
		local mode = piperMolecularModeFromRemote(abilityMode)
		local allowed, cfg = canCastMolecularPiper(player, mode)
		if not allowed or not cfg then
			return
		end
		local activated: boolean
		if mode == "deviation" then
			activated = applyMolecularDeviation(player, target)
		else
			activated = applyMolecularCombustion(player, target, hitPosition)
		end
		if not activated then
			return
		end
		if not spendEnergy(player, cfg.Energy) then
			return
		end
		beginMolecularPiperCooldown(player, mode, cfg.Cooldown)
		setLastUsedAbility(player, powerId)
		return
	end
	if powerId == "empathic_deflection" and type(castAction) == "string" then
		if castAction == "start" then
			local allowed, _ = canCast(player, powerId)
			if allowed then
				applyEmpathicDeflection(player)
				if isAbilityActive(player, "empathic_deflection") and spendEnergy(player, powersById[powerId].Energy) then
					setLastUsedAbility(player, powerId)
				else
					stopEmpathicDeflection(player, false)
				end
			end
		elseif castAction == "stop" then
			stopEmpathicDeflection(player, true)
		end
		return
	end
	if powerId == "levitation" and type(castAction) == "string" then
		if castAction == "start" then
			local allowed, _ = canCast(player, powerId)
			if allowed then
				applyLevitation(player, abilityMode, cameraLook, target)
				if isAbilityActive(player, "levitation") and spendEnergy(player, powersById[powerId].Energy) then
					setLastUsedAbility(player, powerId)
				else
					stopLevitation(player)
				end
			end
		elseif castAction == "update" then
			updateLevitationControl(player, hitPosition, cameraLook)
		elseif castAction == "stop" then
			stopLevitation(player)
		end
		return
	end
	if powerId == "healing" and type(castAction) == "string" then
		if castAction == "start" then
			if target == nil then
				return
			end
			local allowed, _ = canCast(player, powerId)
			if allowed then
				startHealing(player, target)
				if isAbilityActive(player, "healing") and spendEnergy(player, powersById[powerId].Energy) then
					setLastUsedAbility(player, powerId)
				else
					stopHealing(player)
				end
			end
		elseif castAction == "stop" then
			stopHealing(player)
		end
		return
	end
	if powerId == "telekinetic_orbing" and type(castAction) == "string" then
		if castAction == "start" then
			local allowed, _ = canCast(player, powerId)
			if not allowed then
				return
			end
			local activated = startTelekineticOrbing(player, target, abilityMode)
			if activated and isAbilityActive(player, "telekinetic_orbing") and spendEnergy(player, powersById[powerId].Energy) then
				setLastUsedAbility(player, powerId)
			else
				stopTelekineticOrbing(player, true)
			end
			return
		elseif castAction == "update" then
			updateTelekineticOrbing(player)
			return
		elseif castAction == "push" then
			pushTelekineticOrbing(player, hitPosition)
			return
		elseif castAction == "stop" then
			stopTelekineticOrbing(player)
			return
		end
	end
	if powerId == "telekinesis" and type(castAction) == "string" then
		if castAction == "start" then
			local power = powersById[powerId]
			if not power then
				return
			end
			-- Channel style affects energy cost (and indirectly cooldown via beginCooldown override).
			local _, channelStyle = telekinesisParseFromRemote(abilityMode)
			local energyMult = if channelStyle == "eye" then TELEKINESIS_EYE_ENERGY_MULT else TELEKINESIS_HAND_ENERGY_MULT

			local chosen = player:GetAttribute("ChosenCharacter")
			if type(chosen) ~= "string" or chosen ~= power.Character then
				return
			end
			local character = player.Character
			if not character then
				return
			end
			local humanoid = getHumanoid(character)
			if not humanoid or humanoid.Health <= 0 then
				return
			end
			local byPlayer = cooldowns[player]
			local last = byPlayer and byPlayer[powerId] or nil
			local now = os.clock()
			if last and (now - last) < power.Cooldown then
				return
			end
			local energy = player:GetAttribute("Energy")
			local current = if type(energy) == "number" then energy else CharacterConfig.DefaultEnergy
			local required = power.Energy * energyMult
			if current < required then
				return
			end

			if not applyTelekinesis(player, target, hitPosition, abilityMode, cameraLook) then
				setAbilityActive(player, "telekinesis", false)
				return
			end
			if isAbilityActive(player, "telekinesis") and spendEnergy(player, power.Energy * energyMult) then
				setLastUsedAbility(player, powerId)
			else
				clearTelekinesis(player)
			end
			return
		elseif castAction == "update" then
			local aim = if typeof(hitPosition) == "Vector3" then hitPosition :: Vector3 else nil
			updateTelekinesisTarget(player, aim, cameraLook)
			return
		elseif castAction == "push" then
			pushTelekinesisTarget(player, hitPosition, cameraLook)
			clearTelekinesis(player)
			return
		elseif castAction == "stop" then
			clearTelekinesis(player)
			return
		end
	end
	if powerId == "astral_projection" and astralStates[player] then
		applyAstralProjection(player, hitPosition)
		return
	end
	local allowed, _power = canCast(player, powerId)
	if not allowed then
		return
	end
	local handler = handlers[powerId]
	if handler then
		local activated = handler(player, target, hitPosition)
		if not activated then
			return
		end
		if not spendEnergy(player, powersById[powerId].Energy) then
			return
		end
		beginCooldown(player, powerId)
		setLastUsedAbility(player, powerId)
	end
end)

Players.PlayerAdded:Connect(function(player)
	player:SetAttribute("Energy", CharacterConfig.DefaultEnergy)
	player:SetAttribute(MOLECULAR_FUEL_ATTRIBUTE, 0)
	startEnergyRegen(player)
	player.Chatted:Connect(function(message)
		if not isPlayerWitch(player) then
			return
		end
		local lower = string.lower(message)
		if string.find(lower, "return to sender", 1, true) or string.find(lower, "object of objection", 1, true) then
			returnInteractablesToStart(player)
		end
	end)
end)

for _, player in Players:GetPlayers() do
	player:SetAttribute("Energy", CharacterConfig.DefaultEnergy)
	player:SetAttribute(MOLECULAR_FUEL_ATTRIBUTE, 0)
	startEnergyRegen(player)
	player.Chatted:Connect(function(message)
		if not isPlayerWitch(player) then
			return
		end
		local lower = string.lower(message)
		if string.find(lower, "return to sender", 1, true) or string.find(lower, "object of objection", 1, true) then
			returnInteractablesToStart(player)
		end
	end)
end

local POWERS_EXCHANGE_MAX_RANGE_STUDS = 12
local POWERS_EXCHANGE_BALLS_PER_SIDE = 3

local powersExchangeInProgress: { [Player]: boolean } = {}

-- Only the caster runs the spell; the partner does not cast. Do not mark the target as
-- "in progress" or they cannot be selected. Single-caster ritual uses optional UserId or nearest witch.
local function getNearestWitchForPowersExchange(caster: Player): Player?
	local casterChar = caster.Character
	if not casterChar then
		return nil
	end
	local casterRoot = getRoot(casterChar)
	if not casterRoot then
		return nil
	end
	local bestPlr: Player? = nil
	local bestDist = math.huge
	for _, plr in Players:GetPlayers() do
		if plr ~= caster and isPlayerWitch(plr) then
			local ch = plr.Character
			local r = ch and getRoot(ch)
			local hum = ch and ch:FindFirstChildOfClass("Humanoid")
			if r and hum and hum.Health > 0 then
				local dist = (r.Position - casterRoot.Position).Magnitude
				if dist <= POWERS_EXCHANGE_MAX_RANGE_STUDS and dist < bestDist then
					bestDist = dist
					bestPlr = plr
				end
			end
		end
	end
	return bestPlr
end

local function getPowersExchangeTargetFromUserId(caster: Player, targetUserId: number?): Player?
	local target: Player? = nil
	if type(targetUserId) == "number" then
		target = Players:GetPlayerByUserId(targetUserId)
	end
	if not target then
		target = getNearestWitchForPowersExchange(caster)
	end
	if not target or target == caster then
		return nil
	end
	if not isPlayerWitch(target) then
		return nil
	end
	local casterChar = caster.Character
	local targetChar = target.Character
	if not casterChar or not targetChar then
		return nil
	end
	local casterRoot = getRoot(casterChar)
	local targetRoot = getRoot(targetChar)
	if not casterRoot or not targetRoot then
		return nil
	end
	local casterHum = casterChar:FindFirstChildOfClass("Humanoid")
	local targetHum = targetChar:FindFirstChildOfClass("Humanoid")
	if not casterHum or not targetHum or casterHum.Health <= 0 or targetHum.Health <= 0 then
		return nil
	end
	if (targetRoot.Position - casterRoot.Position).Magnitude > POWERS_EXCHANGE_MAX_RANGE_STUDS then
		return nil
	end
	return target
end

local function applyRoleToPlayerCharacter(plr: Player, roleName: string)
	plr:SetAttribute("ChosenCharacter", roleName)
	plr:SetAttribute("Energy", CharacterConfig.DefaultEnergy)
	plr:SetAttribute(MOLECULAR_FUEL_ATTRIBUTE, 0)
	local ch = plr.Character
	if not ch then
		return
	end
	ch:SetAttribute("ChosenCharacter", roleName)
	ch:SetAttribute("Energy", CharacterConfig.DefaultEnergy)
	ch:SetAttribute(MOLECULAR_FUEL_ATTRIBUTE, 0)

	local maxH = (CharacterConfig :: any).CombatMaxHealth
	if type(maxH) ~= "number" then
		maxH = 100
	end
	if roleName == "Belthazor" then
		local bMax = (CharacterConfig :: any).BelthazorCombatHealth
		if type(bMax) == "number" then
			maxH = bMax
		end
	end
	GameHealth.initCharacter(ch, maxH)
end

local function spawnWhiteBall(fromPos: Vector3, initialCFrame: CFrame): Part
	local ball = Instance.new("Part")
	ball.Name = "PowersExchangeBall"
	ball.Shape = Enum.PartType.Ball
	local sz = 0.85
	ball.Size = Vector3.new(sz, sz, sz)
	ball.Material = Enum.Material.Neon
	ball.Color = Color3.fromRGB(245, 245, 255)
	ball.Transparency = 0.48
	ball.CanCollide = false
	ball.CanTouch = false
	ball.CanQuery = false
	ball.Anchored = true
	ball.CFrame = initialCFrame
	ball.Parent = workspace
	return ball
end

local function tweenBallSequence(ball: Part, a: Vector3, b: Vector3, c: Vector3, d: Vector3, t1: number, t2: number, t3: number)
	local ease = Enum.EasingStyle.Sine
	local tw1 = TweenService:Create(ball, TweenInfo.new(t1, ease, Enum.EasingDirection.InOut), { CFrame = CFrame.new(b) })
	local tw2 = TweenService:Create(ball, TweenInfo.new(t2, ease, Enum.EasingDirection.InOut), { CFrame = CFrame.new(c) })
	local tw3 = TweenService:Create(ball, TweenInfo.new(t3, ease, Enum.EasingDirection.InOut), { CFrame = CFrame.new(d) })
	tw1.Completed:Once(function()
		if not ball.Parent then
			return
		end
		tw2:Play()
	end)
	tw2.Completed:Once(function()
		if not ball.Parent then
			return
		end
		tw3:Play()
	end)
	tw1:Play()
end

-- After a role swap the client rebuilds power buttons (clears cooldown overlays). Replay remaining server cooldowns.
local function syncCooldownVisualsToClient(plr: Player)
	local byPlayer = cooldowns[plr]
	if not byPlayer then
		return
	end
	local chosen = plr:GetAttribute("ChosenCharacter")
	if type(chosen) ~= "string" or chosen == "" then
		return
	end
	local kit = CharacterConfig.PowersByCharacter[chosen]
	if type(kit) ~= "table" then
		return
	end
	local now = os.clock()

	if chosen == "Piper" then
		local cdEnd = byPlayer[MOLECULAR_COMBUSTION_SHARED_CD_KEY]
		if type(cdEnd) == "number" then
			local rem = cdEnd - now
			if rem > 0.05 then
				powerCastRemoteEvent:FireClient(plr, "ability_cooldown", "molecular_combustion", rem)
			end
		end
	end

	for _, power in kit do
		local powerId = power.Id
		if powerId == "molecular_combustion" and chosen == "Piper" then
			-- Uses shared key; handled above.
		else
			local last = byPlayer[powerId]
			if type(last) == "number" then
				local powerDef = powersById[powerId]
				if powerDef and powerDef.Character == chosen then
					local rem = powerDef.Cooldown - (now - last)
					if rem > 0.05 then
						powerCastRemoteEvent:FireClient(plr, "ability_cooldown", powerId, rem)
					end
				end
			end
		end
	end
end

local function castPowersExchange(caster: Player, targetUserId: number?)
	if powersExchangeInProgress[caster] then
		return
	end
	local target = getPowersExchangeTargetFromUserId(caster, targetUserId)
	if not target then
		return
	end

	local casterChar = caster.Character
	local targetChar = target.Character
	if not casterChar or not targetChar then
		return
	end
	local casterRoot = getRoot(casterChar)
	local targetRoot = getRoot(targetChar)
	if not casterRoot or not targetRoot then
		return
	end

	local casterRole = caster:GetAttribute("ChosenCharacter")
	local targetRole = target:GetAttribute("ChosenCharacter")
	if type(casterRole) ~= "string" or casterRole == "" or type(targetRole) ~= "string" or targetRole == "" then
		return
	end

	powersExchangeInProgress[caster] = true

	-- Stop ongoing powers so the swap doesn't leave lingering active states.
	clearTelekinesis(caster)
	stopMolecularFreeze(caster)
	stopPremonition(caster)
	stopLevitation(caster)
	stopHealing(caster)
	stopTelekineticOrbing(caster, true)
	stopEmpathicDeflection(caster, false)

	clearTelekinesis(target)
	stopMolecularFreeze(target)
	stopPremonition(target)
	stopLevitation(target)
	stopHealing(target)
	stopTelekineticOrbing(target, true)
	stopEmpathicDeflection(target, false)

	local startPosCaster = casterRoot.Position + Vector3.new(0, 2.2, 0)
	local startPosTarget = targetRoot.Position + Vector3.new(0, 2.2, 0)
	local endPosCaster = startPosCaster
	local endPosTarget = startPosTarget

	local totalT = 0
	local function queueBalls(fromRoot: BasePart, toRoot: BasePart)
		local fromBase = fromRoot.Position + Vector3.new(0, 2.2, 0)
		local toBase = toRoot.Position + Vector3.new(0, 2.2, 0)
		for i = 1, POWERS_EXCHANGE_BALLS_PER_SIDE do
			local jitter = Vector3.new((math.random(-95, 95) / 100), (math.random(0, 45) / 100), (math.random(-95, 95) / 100))
			local j2 = Vector3.new((math.random(-95, 95) / 100), (math.random(0, 45) / 100), (math.random(-95, 95) / 100))
			local a = fromBase + jitter
			local d = toBase + j2

			local midLift = math.random(42, 68) / 10 -- ~4.2..6.8 studs (lower arc)
			local mid = (a + d) * 0.5 + Vector3.new(math.random(-28, 28) / 10, midLift, math.random(-28, 28) / 10)
			local c = mid + Vector3.new(math.random(-18, 18) / 10, math.random(-6, 6) / 10, math.random(-18, 18) / 10)

			local t1 = 0.42 + math.random(0, 14) / 100
			local t2 = 0.36 + math.random(0, 14) / 100
			local t3 = 0.52 + math.random(0, 16) / 100
			local ball = spawnWhiteBall(a, CFrame.new(a))
			Debris:AddItem(ball, t1 + t2 + t3 + 0.25)

			tweenBallSequence(ball, a, mid, c, d, t1, t2, t3)
			totalT = math.max(totalT, t1 + t2 + t3)
		end
	end

	-- Balls fly both directions.
	queueBalls(casterRoot, targetRoot)
	queueBalls(targetRoot, casterRoot)

	task.delay(totalT + 0.05, function()
		-- Players may have left / died during the animation.
		if not caster.Parent or not target.Parent then
			powersExchangeInProgress[caster] = nil
			return
		end

		applyRoleToPlayerCharacter(caster, targetRole)
		applyRoleToPlayerCharacter(target, casterRole)

		powersExchangeInProgress[caster] = nil

		-- Client clears cooldown UI when ChosenCharacter changes; resend active cooldowns after UI rebuilds.
		task.delay(0.18, function()
			if caster.Parent then
				syncCooldownVisualsToClient(caster)
			end
			if target.Parent then
				syncCooldownVisualsToClient(target)
			end
		end)
	end)
end

spellCastRemoteEvent.OnServerEvent:Connect(function(player: Player, spellId: any, phase: any?, targetUserId: any?)
	if type(spellId) ~= "string" then
		return
	end
	if not isPlayerWitch(player) then
		return
	end
	if phase == "commit" then
		if spellId == "powers_exchange" then
			local uid: number? = if type(targetUserId) == "number" then targetUserId :: number else nil
			castPowersExchange(player, uid)
			return
		end
		if spellId == "return_to_sender" and SPELL_TEXT_BY_ID[spellId] then
			returnInteractablesToStart(player)
		end
		return
	end
	local text = SPELL_TEXT_BY_ID[spellId]
	if not text then
		return
	end
	powerCastRemoteEvent:FireClient(player, "spell_chat_ok", text, spellId)
end)

Players.PlayerRemoving:Connect(function(player)
	powersExchangeInProgress[player] = nil
	cleanupAstralFor(player)
	clearTelekinesis(player)
	stopMolecularFreeze(player)
	stopPremonition(player)
	stopLevitation(player)
	stopHealing(player)
	stopTelekineticOrbing(player, true)
	stopEmpathicDeflection(player, false)
	cooldowns[player] = nil
	lastEnergySpendAt[player] = nil
	energyRegenActive[player] = nil
end)

Players.PlayerAdded:Connect(function(player)
	player.CharacterRemoving:Connect(function()
		cleanupAstralFor(player)
		clearTelekinesis(player)
		stopMolecularFreeze(player)
		stopPremonition(player)
		stopLevitation(player)
		stopHealing(player)
		stopTelekineticOrbing(player, true)
		stopEmpathicDeflection(player, false)
	end)
end)

RunService.Heartbeat:Connect(function(dt)
	for _, plr in Players:GetPlayers() do
		local fuel = plr:GetAttribute(MOLECULAR_FUEL_ATTRIBUTE)
		if type(fuel) == "number" and fuel > 0 then
			local newFuel = math.max(fuel - MOLECULAR_FUEL_DECAY_PER_SEC * (dt or 0), 0)
			if newFuel ~= fuel then
				plr:SetAttribute(MOLECULAR_FUEL_ATTRIBUTE, newFuel)
			end
		end
		if telekinesisStates[plr] then
			telekinesisBreakIfOutOfRange(plr)
		end
	end
	for _, plr in Players:GetPlayers() do
		local state = astralStates[plr]
		if not state then
			continue
		end
		local ch = plr.Character
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		-- If the caster dies while in astral form, immediately end astral and cancel the ability.
		if not ch or not hum or hum.Health <= 0 or ch:GetAttribute("CombatDeathHandled") == true then
			cleanupAstralFor(plr, false)
			setAbilityActive(plr, "astral_projection", false)
		end
	end
	for _, plr in Players:GetPlayers() do
		if not isAbilityActive(plr, "empathic_deflection") then
			continue
		end
		-- Push nearby projectiles radially away from the deflector; handles LinearVelocity-driven orbs/fireballs too.
		reflectProjectilesAround(plr, DEFLECT_PROJECTILE_RADIUS, false, false, false)
	end
end)

task.defer(snapshotInteractables)
