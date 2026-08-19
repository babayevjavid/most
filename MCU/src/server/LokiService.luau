--!strict
--[[
	Loki:
	Q Dagger Throw (R then L)
	E Illusion Decoy (hold + click; Punch / Run / Detonate / Lie of Place)
	F Trickster Dash (WASD)
	C Reflect Shield (0.5s outline)
	V Shapeshift
	X God of Mischief (invis + 3 roaming clones; Attack/Idle panel)
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
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
local VfxHelper = require(ReplicatedStorage.Shared.VfxHelper)
local CharacterService = require(script.Parent.CharacterService)
local RagdollStatus = require(ReplicatedStorage.Shared.RagdollStatus)

local LokiService = {}

type DecoyState = {
	character: Model,
	clone: Model,
	humanoid: Humanoid,
	root: BasePart,
	mode: string,
	aimPoint: Vector3,
	startedAt: number,
	ownerName: string,
	animConn: RBXScriptConnection?,
	swapping: boolean?,
}

type UltCloneState = {
	clone: Model,
	root: BasePart,
	humanoid: Humanoid,
	lastBlast: number,
	owner: Model,
	home: Vector3,
	wanderTarget: Vector3,
	nextWanderAt: number,
	animConn: RBXScriptConnection?,
}

type UltState = {
	character: Model,
	clones: { UltCloneState },
	startedAt: number,
	attackEnabled: boolean,
}

local decoyArmed: { [Player]: boolean } = {}
local decoyByPlayer: { [Player]: DecoyState } = {}
local reflectUntil: { [Player]: number } = {}
local shapeshiftToken: { [Player]: number } = {}
local ultByPlayer: { [Player]: UltState } = {}
local dashUntil: { [Player]: number } = {}

local function lokiGreen(): Color3
	return Color3.fromRGB(40, 200, 90)
end

local function getRoot(model: Model): BasePart?
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

local function canUse(character: Model, abilityId: string, energyCost: number): boolean
	if character:GetAttribute(GameConstants.HERO_ATTRIBUTE) ~= "loki" then
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

function LokiService.isReflecting(character: Model): boolean
	return character:GetAttribute(GameConstants.LOKI_REFLECT_ATTRIBUTE) == true
end

--[[ Returns true if the ability was reflected (caller should cancel effect on Loki). ]]
function LokiService.tryReflect(attacker: Model, victim: Model, kind: string): boolean
	if victim:GetAttribute(GameConstants.HERO_ATTRIBUTE) ~= "loki" then
		return false
	end
	if not LokiService.isReflecting(victim) then
		return false
	end
	if kind == "projectile" or kind == "beam" or kind == "explosion" or kind == "blast" then
		return false
	end

	local aRoot = getRoot(attacker)
	local vRoot = getRoot(victim)
	if not aRoot or not vRoot then
		return true
	end

	if kind == "telekinesis" then
		local away = aRoot.Position - vRoot.Position
		local dir = if away.Magnitude > 0.05 then away.Unit else aRoot.CFrame.LookVector
		PushHelper.applyToCharacter(attacker, dir, {
			speed = GameConstants.TK_THROW_SPEED,
			upBoost = GameConstants.TK_THROW_UP,
		})
		RagdollStatus.applyTimed(attacker, GameConstants.RAGDOLL_TK_THROW_DURATION)
		return true
	end

	if kind == "torture" then
		attacker:SetAttribute(GameConstants.TORTURE_LOCKED_ATTRIBUTE, true)
		local hum = CombatHelper.getHumanoid(attacker)
		if hum then
			hum.WalkSpeed = 0
			hum.JumpPower = 0
			hum.AutoRotate = false
		end
		task.delay(GameConstants.LOKI_REFLECT_TORTURE_DURATION, function()
			if attacker.Parent then
				attacker:SetAttribute(GameConstants.TORTURE_LOCKED_ATTRIBUTE, nil)
			end
			if hum and hum.Parent then
				hum.WalkSpeed = GameConstants.DEFAULT_WALK_SPEED
				hum.JumpPower = 50
				hum.AutoRotate = true
			end
		end)
		local now = os.clock()
		task.spawn(function()
			while os.clock() - now < GameConstants.LOKI_REFLECT_TORTURE_DURATION do
				if not attacker.Parent then
					break
				end
				CombatHelper.dealDamage(victim, attacker, GameConstants.TK_TORTURE_DAMAGE)
				task.wait(GameConstants.TK_TORTURE_DAMAGE_INTERVAL)
			end
		end)
		return true
	end

	if kind == "disintegrate" then
		local hum = CombatHelper.getHumanoid(attacker)
		if
			hum
			and hum.MaxHealth > 0
			and (hum.Health / hum.MaxHealth) <= GameConstants.DISINTEGRATE_HP_THRESHOLD
		then
			VfxHelper.spawnImpact(aRoot.Position, lokiGreen(), 5)
			hum.WalkSpeed = 0
			hum.JumpPower = 0
			hum.AutoRotate = false
			VfxHelper.fadePartsByHeight(attacker, 1, GameConstants.DISINTEGRATE_DURATION, true, function()
				if hum.Parent then
					hum.Health = 0
				end
			end)
		else
			-- Redirect disintegration blast visually / lightly without full dissolve
			VfxHelper.spawnImpact(aRoot.Position, lokiGreen(), 4)
			VfxHelper.spawnBeamLine(vRoot.Position, aRoot.Position, lokiGreen(), 0.35, 0.2)
			CombatHelper.dealDamage(victim, attacker, 8)
		end
		return true
	end

	if kind == "fear" or kind == "generic" then
		attacker:SetAttribute(
			GameConstants.POWERS_DISABLED_UNTIL,
			AbilityCooldownHelper.getNow() + 4
		)
		return true
	end

	return true
end

local function stripCloneNoise(clone: Model, keepHumanoid: boolean)
	for _, desc in clone:GetDescendants() do
		if desc:IsA("Script") or desc:IsA("LocalScript") or desc:IsA("ModuleScript") or desc:IsA("Sound") then
			-- Keep Animate asset tree for server playback (LocalScript itself is useless on NPCs)
			if desc.Name == "Animate" then
				continue
			end
			desc:Destroy()
		elseif not keepHumanoid and (desc:IsA("Humanoid") or desc:IsA("Animator")) then
			desc:Destroy()
		elseif
			desc:IsA("ParticleEmitter")
			or desc:IsA("Trail")
			or desc:IsA("Beam")
			or desc:IsA("Fire")
			or desc:IsA("Smoke")
			or desc:IsA("Sparkles")
		then
			desc:Destroy()
		elseif
			desc.Name == "HandParticle"
			or desc.Name == "MCU_Nameplate"
			or desc.Name == "ShieldHealthGui"
			or desc:IsA("BillboardGui")
			or desc:IsA("Highlight")
			or desc:IsA("ForceField")
		then
			desc:Destroy()
		end
	end
	-- Remove Animate LocalScript runners but keep folder/value children with AnimationIds
	local animate = clone:FindFirstChild("Animate")
	if animate then
		if animate:IsA("LocalScript") or animate:IsA("Script") then
			-- Convert to Folder preserving children
			local folder = Instance.new("Folder")
			folder.Name = "Animate"
			for _, child in animate:GetChildren() do
				child.Parent = folder
			end
			folder.Parent = clone
			animate:Destroy()
		end
	end
end

local function findAnimIdFromAnimate(animate: Instance?, categoryNames: { string }): string?
	if not animate then
		return nil
	end
	for _, catName in categoryNames do
		local folder = animate:FindFirstChild(catName)
		if not folder then
			continue
		end
		for _, child in folder:GetChildren() do
			if child:IsA("Animation") and child.AnimationId ~= "" then
				return child.AnimationId
			end
			if child:IsA("StringValue") and child.Value ~= "" then
				return child.Value
			end
			local nested = child:FindFirstChildOfClass("Animation")
			if nested and nested.AnimationId ~= "" then
				return nested.AnimationId
			end
		end
	end
	return nil
end

--[[ Server-side idle/walk using the owner's Animate AnimationIds. ]]
local function attachCloneAnimate(clone: Model, source: Model): RBXScriptConnection?
	local hum = clone:FindFirstChildOfClass("Humanoid")
	if not hum then
		return nil
	end
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = hum
	end

	local srcAnimate = source:FindFirstChild("Animate") or clone:FindFirstChild("Animate")
	local idleId = findAnimIdFromAnimate(srcAnimate, { "idle", "Idle" })
	local walkId = findAnimIdFromAnimate(srcAnimate, { "walk", "Walk", "run", "Run" })

	local idleTrack: AnimationTrack? = nil
	local walkTrack: AnimationTrack? = nil
	if idleId then
		local anim = Instance.new("Animation")
		anim.AnimationId = idleId
		idleTrack = animator:LoadAnimation(anim)
		idleTrack.Looped = true
		idleTrack.Priority = Enum.AnimationPriority.Idle
	end
	if walkId then
		local anim = Instance.new("Animation")
		anim.AnimationId = walkId
		walkTrack = animator:LoadAnimation(anim)
		walkTrack.Looped = true
		walkTrack.Priority = Enum.AnimationPriority.Movement
	end

	local playing: string? = nil
	local function setAnim(kind: string)
		if playing == kind then
			return
		end
		playing = kind
		if kind == "walk" then
			if idleTrack and idleTrack.IsPlaying then
				idleTrack:Stop(0.15)
			end
			if walkTrack and not walkTrack.IsPlaying then
				walkTrack:Play(0.15)
			end
		else
			if walkTrack and walkTrack.IsPlaying then
				walkTrack:Stop(0.15)
			end
			if idleTrack and not idleTrack.IsPlaying then
				idleTrack:Play(0.2)
			end
		end
	end
	setAnim("idle")

	local conn = RunService.Heartbeat:Connect(function()
		if not clone.Parent or not hum.Parent then
			return
		end
		local moving = hum.MoveDirection.Magnitude > 0.08
		local root = clone:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local flat = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z)
			if flat.Magnitude > 1.2 then
				moving = true
			end
		end
		setAnim(if moving then "walk" else "idle")
	end)
	return conn
end

local function copyAnimateFromSource(clone: Model, source: Model)
	local existing = clone:FindFirstChild("Animate")
	if existing then
		existing:Destroy()
	end
	local src = source:FindFirstChild("Animate")
	if not src then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "Animate"
	for _, child in src:GetChildren() do
		-- Skip scripts; copy animation data only
		if child:IsA("LocalScript") or child:IsA("Script") or child:IsA("ModuleScript") then
			for _, nested in child:GetChildren() do
				nested:Clone().Parent = folder
			end
		else
			child:Clone().Parent = folder
		end
	end
	folder.Parent = clone
end

-- Smooth reveal from feet → head
local function revealCloneFeetToHead(clone: Model, duration: number)
	type PartFade = { inst: BasePart | Decal | Texture, goal: number, y: number }
	local fades: { PartFade } = {}
	local minY = math.huge
	local maxY = -math.huge
	for _, desc in clone:GetDescendants() do
		if desc:IsA("BasePart") and desc.Name ~= "HumanoidRootPart" then
			local y = desc.Position.Y
			minY = math.min(minY, y - desc.Size.Y * 0.5)
			maxY = math.max(maxY, y + desc.Size.Y * 0.5)
			table.insert(fades, { inst = desc, goal = desc.Transparency, y = y })
			desc.Transparency = 1
		elseif desc:IsA("Decal") or desc:IsA("Texture") then
			local parent = desc.Parent
			local y = if parent and parent:IsA("BasePart") then parent.Position.Y else 0
			table.insert(fades, { inst = desc, goal = desc.Transparency, y = y })
			desc.Transparency = 1
		end
	end
	if maxY <= minY or #fades == 0 then
		return
	end
	task.spawn(function()
		local t0 = os.clock()
		while clone.Parent and (os.clock() - t0) < duration do
			local a = math.clamp((os.clock() - t0) / duration, 0, 1)
			local cutY = minY + (maxY - minY) * a
			for _, info in fades do
				local inst = info.inst
				if not inst.Parent then
					continue
				end
				if info.y <= cutY then
					inst.Transparency = info.goal
				else
					local blend = math.clamp(1 - (info.y - cutY) / math.max(maxY - minY, 0.01) * 3, 0, 1)
					inst.Transparency = 1 - (1 - info.goal) * blend
				end
			end
			task.wait()
		end
		for _, info in fades do
			if info.inst.Parent then
				info.inst.Transparency = info.goal
			end
		end
	end)
end

local function addCloneNameplate(clone: Model, labelText: string)
	local head = clone:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "LokiCloneNameplate"
	gui.Size = UDim2.new(4, 0, 0.7, 0)
	gui.StudsOffset = Vector3.new(0, 2.2, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 80
	gui.Adornee = head
	gui.Parent = head

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = lokiGreen()
	label.TextStrokeTransparency = 0.4
	label.Text = labelText
	label.Parent = gui
end

local function spawnDagger(character: Model, origin: Vector3, homeDir: Vector3, aimPoint: Vector3?)
	ProjectileHelper.spawn(origin, homeDir, {
		speed = GameConstants.LOKI_DAGGER_SPEED,
		damage = GameConstants.LOKI_DAGGER_DAMAGE,
		radius = GameConstants.LOKI_DAGGER_HIT_RADIUS,
		maxDistance = GameConstants.LOKI_DAGGER_RANGE,
		owner = character,
		color = lokiGreen(),
		homeDir = homeDir,
		homePoint = aimPoint or (origin + homeDir * 50),
		homeAfter = 0,
		seekUntilClose = true,
		seekCloseDistance = 2.2,
		boltFolder = "Loki",
		boltAsset = "Dagger",
		impactFx = "none",
		deleteAfterFx = GameConstants.LOKI_DAGGER_DELETE_AFTER_FX,
		-- Omit facingOffset so Tip attachment or size heuristic can auto-align tip to travel
	})
end

local function fireDaggers(player: Player, direction: Vector3, aimPoint: Vector3?)
	local character = player.Character
	if not character then
		return
	end
	local entry = CharacterRegistry.getAbilityById("loki", "dagger_throw")
	if not entry or not canUse(character, entry.id, GameConstants.LOKI_DAGGER_ENERGY) then
		return
	end

	AbilityCooldownHelper.setActive(character, entry.id, true)
	local dir = if direction.Magnitude > 0.01 then direction.Unit else character:GetPivot().LookVector
	local homeDir = dir
	local root = getRoot(character)
	if aimPoint then
		local from = if root then root.Position else character:GetPivot().Position
		local toAim = aimPoint - from
		if toAim.Magnitude > 0.05 then
			homeDir = toAim.Unit
		end
	end

	local right = getHand(character, true)
	local left = getHand(character, false)
	local rightPos = if right then right.Position else character:GetPivot().Position
	spawnDagger(character, rightPos, homeDir, aimPoint)
	VfxHelper.castHandFlash(rightPos, lokiGreen())

	task.delay(GameConstants.LOKI_DAGGER_HAND_DELAY, function()
		if not character.Parent or player.Character ~= character then
			AbilityCooldownHelper.setActive(character, entry.id, false)
			return
		end
		local leftPos = if left and left.Parent then left.Position else character:GetPivot().Position
		spawnDagger(character, leftPos, homeDir, aimPoint)
		VfxHelper.castHandFlash(leftPos, lokiGreen())
		finishAbility(character, entry.id, GameConstants.LOKI_DAGGER_COOLDOWN)
	end)
end

local function endDecoy(player: Player, applyCooldown: boolean)
	local state = decoyByPlayer[player]
	if not state then
		return
	end
	decoyByPlayer[player] = nil
	local char = state.character
	if char.Parent then
		char:SetAttribute(GameConstants.LOKI_CLONE_ACTIVE_ATTRIBUTE, nil)
		char:SetAttribute(GameConstants.LOKI_CLONE_MODE_ATTRIBUTE, nil)
		AbilityCooldownHelper.setActive(char, "illusion_decoy", false)
		if applyCooldown then
			AbilityCooldownHelper.applyAfterUse(char, "illusion_decoy", GameConstants.LOKI_CLONE_COOLDOWN)
			CharacterService.markAbilityUse(char)
		end
	end
	if state.animConn then
		state.animConn:Disconnect()
		state.animConn = nil
	end
	if state.clone.Parent then
		state.clone:Destroy()
	end
end

local function detonateDecoy(player: Player)
	local state = decoyByPlayer[player]
	if not state then
		return
	end
	-- Don't start a second detonate
	if state.mode == "Detonating" then
		return
	end
	state.mode = "Detonating"
	if state.character.Parent then
		state.character:SetAttribute(GameConstants.LOKI_CLONE_MODE_ATTRIBUTE, "Detonate")
	end

	-- Freeze in place for the windup (don't keep walking from Run)
	if state.humanoid.Parent then
		state.humanoid.WalkSpeed = 0
		state.humanoid:MoveTo(state.root.Position)
	end
	if state.root.Parent then
		state.root.AssemblyLinearVelocity = Vector3.zero
		state.root.AssemblyAngularVelocity = Vector3.zero
	end

	local existing = state.clone:FindFirstChild("LokiDetonateHighlight")
	if existing then
		existing:Destroy()
	end
	local hl = Instance.new("Highlight")
	hl.Name = "LokiDetonateHighlight"
	hl.FillColor = Color3.fromRGB(80, 255, 120)
	hl.FillTransparency = 1
	hl.OutlineColor = Color3.fromRGB(180, 255, 200)
	hl.OutlineTransparency = 1
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Adornee = state.clone
	hl.Parent = state.clone

	TweenService:Create(hl, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FillTransparency = 0.05,
		OutlineTransparency = 0,
	}):Play()

	task.wait(1)
	if not state.clone.Parent or decoyByPlayer[player] ~= state then
		if hl.Parent then
			hl:Destroy()
		end
		return
	end

	local pos = state.root.Position
	VfxHelper.spawnLokiDetonateAttachment(pos)
	local near = CombatHelper.overlapCharacters(pos, GameConstants.LOKI_CLONE_DETONATE_RADIUS, state.character)
	for _, model in near do
		if model ~= state.clone and model:GetAttribute("LokiUltClone") ~= true then
			CombatHelper.dealDamage(state.character, model, GameConstants.LOKI_CLONE_DETONATE_DAMAGE)
			RagdollStatus.applyTimed(model, GameConstants.LOKI_CLONE_DETONATE_RAGDOLL)
			local mRoot = getRoot(model)
			if mRoot then
				local push = mRoot.Position - pos
				if push.Magnitude > 0.05 then
					PushHelper.applyToCharacter(model, push.Unit, {
						speed = GameConstants.LOKI_CLONE_DETONATE_PUSH_SPEED,
						upBoost = GameConstants.LOKI_CLONE_DETONATE_PUSH_UP,
					})
				end
			end
		end
	end
	endDecoy(player, true)
end

local function punchWithDecoy(state: DecoyState)
	local look = state.root.CFrame.LookVector
	local origin = state.root.Position
	local best: Model? = nil
	local bestDist = GameConstants.LOKI_CLONE_PUNCH_RANGE
	local near = CombatHelper.overlapCharacters(origin, GameConstants.LOKI_CLONE_PUNCH_RANGE, state.character)
	for _, model in near do
		if model == state.clone then
			continue
		end
		local root = getRoot(model)
		if not root then
			continue
		end
		local to = root.Position - origin
		if to.Magnitude < 0.05 then
			continue
		end
		if to.Unit:Dot(look) < 0.35 then
			continue
		end
		if to.Magnitude < bestDist then
			bestDist = to.Magnitude
			best = model
		end
	end
	if best then
		CombatHelper.dealDamage(state.character, best, GameConstants.LOKI_CLONE_PUNCH_DAMAGE)
		local r = getRoot(best)
		if r then
			PushHelper.applyToCharacter(best, look, { speed = 28, upBoost = 4 })
		end
	end
end

local function placeDecoy(player: Player, aimPoint: Vector3?)
	local character = player.Character
	if not character or not decoyArmed[player] then
		return
	end
	decoyArmed[player] = false
	if decoyByPlayer[player] then
		return
	end
	local entry = CharacterRegistry.getAbilityById("loki", "illusion_decoy")
	if not entry or not canUse(character, entry.id, GameConstants.LOKI_CLONE_ENERGY) then
		return
	end

	local placeAt = aimPoint or (character:GetPivot().Position + character:GetPivot().LookVector * 8)
	do
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character }
		local cast = Workspace:Raycast(placeAt + Vector3.new(0, 3, 0), Vector3.new(0, -50, 0), params)
		if cast then
			placeAt = cast.Position
		end
	end
	local ok, clone = pcall(function()
		local was = character.Archivable
		character.Archivable = true
		local c = character:Clone()
		character.Archivable = was
		return c
	end)
	if not ok or not clone or not clone:IsA("Model") then
		AbilityCooldownHelper.setActive(character, entry.id, false)
		return
	end

	stripCloneNoise(clone, true)
	copyAnimateFromSource(clone, character)
	clone.Name = string.format("%s's clone", player.DisplayName)
	clone:SetAttribute("LokiDecoy", true)
	clone:SetAttribute("FearVisual", true) -- soft-lock ignore pattern
	local hum = clone:FindFirstChildOfClass("Humanoid")
	local root = getRoot(clone)
	if not hum or not root then
		clone:Destroy()
		AbilityCooldownHelper.setActive(character, entry.id, false)
		return
	end
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.Health = math.max(50, hum.MaxHealth * 0.35)
	hum.WalkSpeed = 0
	hum.MaxHealth = hum.Health
	for _, part in clone:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = true
			part.Massless = false
		end
	end
	local spawnPos = placeAt + Vector3.new(0, 3, 0)
	local lookFlat = Vector3.new(character:GetPivot().LookVector.X, 0, character:GetPivot().LookVector.Z)
	if lookFlat.Magnitude > 0.01 then
		clone:PivotTo(CFrame.lookAt(spawnPos, spawnPos + lookFlat.Unit))
	else
		clone:PivotTo(CFrame.new(spawnPos))
	end
	clone.Parent = Workspace
	revealCloneFeetToHead(clone, 0.55)
	addCloneNameplate(clone, clone.Name)
	local animConn = attachCloneAnimate(clone, character)

	AbilityCooldownHelper.setActive(character, entry.id, true)
	character:SetAttribute(GameConstants.LOKI_CLONE_ACTIVE_ATTRIBUTE, true)
	character:SetAttribute(GameConstants.LOKI_CLONE_MODE_ATTRIBUTE, "Punch")
	CharacterService.markAbilityUse(character)

	decoyByPlayer[player] = {
		character = character,
		clone = clone,
		humanoid = hum,
		root = root,
		mode = "Punch",
		aimPoint = placeAt,
		startedAt = os.clock(),
		ownerName = player.DisplayName,
		animConn = animConn,
		swapping = false,
	}
end

local function lieOfPlace(player: Player)
	local state = decoyByPlayer[player]
	if not state or state.swapping or state.mode == "Detonating" then
		return
	end
	local character = state.character
	local charRoot = getRoot(character)
	if not charRoot or not state.root.Parent or not character.Parent then
		return
	end

	state.swapping = true
	state.mode = "Lie of Place"
	character:SetAttribute(GameConstants.LOKI_CLONE_MODE_ATTRIBUTE, "Lie of Place")
	character:SetAttribute(GameConstants.BUSY_ATTRIBUTE, true)

	-- Stop run walk during swap
	state.humanoid.WalkSpeed = 0
	state.humanoid:MoveTo(state.root.Position)

	local playerCf = charRoot.CFrame
	local decoyCf = state.root.CFrame
	VfxHelper.spawnBurstSparks(playerCf.Position, lokiGreen(), 6)
	VfxHelper.spawnBurstSparks(decoyCf.Position, lokiGreen(), 6)

	local duration = 0.32
	local t0 = os.clock()
	while decoyByPlayer[player] == state and (os.clock() - t0) < duration do
		local a = math.clamp((os.clock() - t0) / duration, 0, 1)
		-- Smoothstep
		a = a * a * (3 - 2 * a)
		if charRoot.Parent and state.root.Parent then
			charRoot.CFrame = playerCf:Lerp(decoyCf, a)
			state.root.CFrame = decoyCf:Lerp(playerCf, a)
			charRoot.AssemblyLinearVelocity = Vector3.zero
			state.root.AssemblyLinearVelocity = Vector3.zero
		end
		task.wait()
	end

	if decoyByPlayer[player] == state and charRoot.Parent and state.root.Parent then
		charRoot.CFrame = decoyCf
		state.root.CFrame = playerCf
		charRoot.AssemblyLinearVelocity = Vector3.zero
		state.root.AssemblyLinearVelocity = Vector3.zero
		VfxHelper.spawnBurstSparks(decoyCf.Position, lokiGreen(), 5)
		VfxHelper.spawnBurstSparks(playerCf.Position, lokiGreen(), 5)
	end

	if character.Parent then
		character:SetAttribute(GameConstants.BUSY_ATTRIBUTE, nil)
	end
	if decoyByPlayer[player] == state then
		state.swapping = false
		-- Stay on Lie of Place highlight; idle until next mode
		state.humanoid.WalkSpeed = 0
	end
end

local function setDecoyMode(player: Player, mode: string)
	local state = decoyByPlayer[player]
	if not state then
		return
	end
	if state.swapping or state.mode == "Detonating" then
		return
	end
	if mode ~= "Punch" and mode ~= "Run" and mode ~= "Detonate" and mode ~= "Lie of Place" then
		return
	end
	if mode == "Detonate" then
		task.spawn(function()
			detonateDecoy(player)
		end)
		return
	end
	if mode == "Lie of Place" then
		task.spawn(function()
			lieOfPlace(player)
		end)
		return
	end

	-- Leaving Run: cancel ongoing MoveTo so Punch doesn't keep walking forever
	if state.mode == "Run" and mode ~= "Run" then
		state.humanoid:MoveTo(state.root.Position)
		state.humanoid.WalkSpeed = 0
	end

	state.mode = mode
	if state.character.Parent then
		state.character:SetAttribute(GameConstants.LOKI_CLONE_MODE_ATTRIBUTE, mode)
	end
	if mode == "Punch" then
		punchWithDecoy(state)
		-- Keep decoy alive after punch so it can Run / Detonate
	elseif mode == "Run" then
		state.humanoid.WalkSpeed = GameConstants.LOKI_CLONE_RUN_SPEED
	end
end

local function clearTeleportAim(character: Model?, abilityId: string?)
	if not character or not character.Parent then
		return
	end
	character:SetAttribute(GameConstants.TELEPORT_AIMING_ATTRIBUTE, nil)
	if abilityId then
		AbilityCooldownHelper.setActive(character, abilityId, false)
	end
end

local function beginTeleportAim(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local entry = CharacterRegistry.getAbilityById("loki", "trickster_dash")
	if not entry then
		return
	end
	if character:GetAttribute(GameConstants.LOKI_DASH_MODE_ATTRIBUTE) ~= "Teleport" then
		return
	end
	if AbilityCooldownHelper.isOnCooldown(character, entry.id) then
		return
	end
	if CombatHelper.arePowersDisabled(character) or character:GetAttribute(GameConstants.BUSY_ATTRIBUTE) == true then
		return
	end
	-- Already aiming: confirm handled by client separately
	if character:GetAttribute(GameConstants.TELEPORT_AIMING_ATTRIBUTE) == true then
		return
	end
	character:SetAttribute(GameConstants.TELEPORT_AIMING_ATTRIBUTE, true)
	-- UI hold/select effect (no energy until confirm)
	AbilityCooldownHelper.setActive(character, entry.id, true)
end

local function confirmTeleport(player: Player, aimPoint: Vector3?)
	local character = player.Character
	if not character then
		return
	end
	local entry = CharacterRegistry.getAbilityById("loki", "trickster_dash")
	if not entry then
		return
	end
	if character:GetAttribute(GameConstants.TELEPORT_AIMING_ATTRIBUTE) ~= true then
		return
	end
	local root = getRoot(character)
	if not root then
		clearTeleportAim(character, entry.id)
		return
	end
	if not CharacterService.spendEnergy(character, GameConstants.LOKI_DASH_ENERGY) then
		clearTeleportAim(character, entry.id)
		return
	end

	local target = aimPoint or (root.Position + root.CFrame.LookVector * GameConstants.LOKI_TELEPORT_RANGE)
	local offset = target - root.Position
	local flat = Vector3.new(offset.X, 0, offset.Z)
	if flat.Magnitude > GameConstants.LOKI_TELEPORT_RANGE then
		flat = flat.Unit * GameConstants.LOKI_TELEPORT_RANGE
	end
	local dest = root.Position + flat
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local cast = Workspace:Raycast(dest + Vector3.new(0, 4, 0), Vector3.new(0, -60, 0), params)
	if cast then
		dest = cast.Position + Vector3.new(0, 3, 0)
	else
		dest = Vector3.new(dest.X, root.Position.Y, dest.Z)
	end

	character:SetAttribute(GameConstants.TELEPORT_AIMING_ATTRIBUTE, nil)
	AbilityCooldownHelper.setActive(character, entry.id, true)
	character:SetAttribute(GameConstants.BUSY_ATTRIBUTE, true)

	local fade = GameConstants.TELEPORT_FADE
	local lookCf = root.CFrame - root.CFrame.Position
	VfxHelper.spawnBurstSparks(root.Position, lokiGreen(), 6)
	VfxHelper.fadePartsByHeight(character, 1, fade, true, function()
		if not character.Parent or not root.Parent then
			if character.Parent then
				character:SetAttribute(GameConstants.BUSY_ATTRIBUTE, nil)
				finishAbility(character, entry.id, GameConstants.LOKI_DASH_COOLDOWN)
			end
			return
		end
		root.CFrame = CFrame.new(dest) * lookCf
		VfxHelper.setCharacterTransparency(character, 1)
		VfxHelper.spawnBurstSparks(dest, lokiGreen(), 8)
		VfxHelper.fadePartsByHeight(character, 0, fade, true, function()
			if character.Parent then
				character:SetAttribute(GameConstants.BUSY_ATTRIBUTE, nil)
				finishAbility(character, entry.id, GameConstants.LOKI_DASH_COOLDOWN)
			end
		end)
	end)
end

local function tricksterMove(player: Player, moveVector: Vector3?, lookDir: Vector3?, aimPoint: Vector3?)
	local character = player.Character
	if not character then
		return
	end
	local entry = CharacterRegistry.getAbilityById("loki", "trickster_dash")
	if not entry then
		return
	end
	local root = getRoot(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return
	end

	local modeAttr = character:GetAttribute(GameConstants.LOKI_DASH_MODE_ATTRIBUTE)
	if modeAttr == "Teleport" then
		-- Teleport uses aim → confirm flow
		if character:GetAttribute(GameConstants.TELEPORT_AIMING_ATTRIBUTE) == true then
			confirmTeleport(player, aimPoint)
		else
			beginTeleportAim(player)
		end
		return
	end

	if not canUse(character, entry.id, GameConstants.LOKI_DASH_ENERGY) then
		return
	end

	-- Dash mode (original)
	local move = moveVector or Vector3.zero
	local dir: Vector3
	if move.Magnitude > 0.08 then
		dir = move.Unit
	elseif lookDir and lookDir.Magnitude > 0.01 then
		dir = lookDir.Unit
	else
		dir = root.CFrame.LookVector
	end
	dir = Vector3.new(dir.X, 0, dir.Z)
	if dir.Magnitude < 0.05 then
		dir = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	end
	if dir.Magnitude < 0.05 then
		AbilityCooldownHelper.setActive(character, entry.id, false)
		finishAbility(character, entry.id, 0.5)
		return
	end
	dir = dir.Unit

	AbilityCooldownHelper.setActive(character, entry.id, true)
	dashUntil[player] = os.clock() + GameConstants.LOKI_DASH_DURATION

	local att = root:FindFirstChild("LokiDashAttachment") :: Attachment?
	if not att then
		att = Instance.new("Attachment")
		att.Name = "LokiDashAttachment"
		att.Parent = root
	end
	local oldLv = root:FindFirstChild("LokiDashVelocity")
	if oldLv then
		oldLv:Destroy()
	end
	local lv = Instance.new("LinearVelocity")
	lv.Name = "LokiDashVelocity"
	lv.Attachment0 = att
	lv.MaxForce = 1e6
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VectorVelocity = dir * GameConstants.LOKI_DASH_SPEED + Vector3.new(0, 8, 0)
	lv.Parent = root

	VfxHelper.spawnBurstSparks(root.Position, lokiGreen(), 5)

	task.delay(GameConstants.LOKI_DASH_DURATION, function()
		dashUntil[player] = nil
		if lv.Parent then
			lv:Destroy()
		end
		if character.Parent then
			finishAbility(character, entry.id, GameConstants.LOKI_DASH_COOLDOWN)
		end
	end)
end

local SHAPESHIFT_HIDE_NAME = "LokiShapeshiftHidden"
local SHAPESHIFT_BODY_NAME = "LokiShapeshiftBody"
local SHAPESHIFT_ORIG_T = "LokiShapeshiftOrigT"
local SHAPESHIFT_MORPH_TIME = 0.45

local function clearShapeshift(player: Player, character: Model?)
	if not character or not character.Parent then
		return
	end
	character:SetAttribute(GameConstants.LOKI_SHAPESHIFT_ATTRIBUTE, nil)
	local body = character:FindFirstChild(SHAPESHIFT_BODY_NAME)
	if body then
		-- Fade disguise out quickly
		for _, desc in body:GetDescendants() do
			if desc:IsA("BasePart") or desc:IsA("Decal") or desc:IsA("Texture") then
				TweenService:Create(desc, TweenInfo.new(0.25), { Transparency = 1 }):Play()
			end
		end
		task.delay(0.28, function()
			if body.Parent then
				body:Destroy()
			end
		end)
	end
	for _, desc in character:GetDescendants() do
		if desc:IsA("BasePart") and desc:GetAttribute(SHAPESHIFT_HIDE_NAME) == true then
			local orig = desc:GetAttribute(SHAPESHIFT_ORIG_T)
			local goal = if typeof(orig) == "number" then orig else 0
			desc.LocalTransparencyModifier = 0
			TweenService:Create(desc, TweenInfo.new(SHAPESHIFT_MORPH_TIME), { Transparency = goal }):Play()
			desc:SetAttribute(SHAPESHIFT_HIDE_NAME, nil)
			desc:SetAttribute(SHAPESHIFT_ORIG_T, nil)
		elseif (desc:IsA("Decal") or desc:IsA("Texture")) and desc:GetAttribute(SHAPESHIFT_HIDE_NAME) == true then
			local orig = desc:GetAttribute(SHAPESHIFT_ORIG_T)
			local goal = if typeof(orig) == "number" then orig else 0
			TweenService:Create(desc, TweenInfo.new(SHAPESHIFT_MORPH_TIME), { Transparency = goal }):Play()
			desc:SetAttribute(SHAPESHIFT_HIDE_NAME, nil)
			desc:SetAttribute(SHAPESHIFT_ORIG_T, nil)
		elseif desc:IsA("Accessory") and desc:GetAttribute(SHAPESHIFT_HIDE_NAME) == true then
			desc:SetAttribute(SHAPESHIFT_HIDE_NAME, nil)
			for _, p in desc:GetDescendants() do
				if p:IsA("BasePart") then
					local orig = p:GetAttribute(SHAPESHIFT_ORIG_T)
					local goal = if typeof(orig) == "number" then orig else 0
					TweenService:Create(p, TweenInfo.new(SHAPESHIFT_MORPH_TIME), { Transparency = goal }):Play()
					p:SetAttribute(SHAPESHIFT_ORIG_T, nil)
				end
			end
		end
	end
end

local function startShapeshift(player: Player, targetModel: Model?)
	local character = player.Character
	if not character then
		return
	end
	local entry = CharacterRegistry.getAbilityById("loki", "shapeshift")
	if not entry then
		return
	end

	-- V again while shifted: cancel early and start cooldown
	if character:GetAttribute(GameConstants.LOKI_SHAPESHIFT_ATTRIBUTE) == true then
		shapeshiftToken[player] = (shapeshiftToken[player] or 0) + 1
		clearShapeshift(player, character)
		finishAbility(character, entry.id, GameConstants.LOKI_SHAPESHIFT_COOLDOWN)
		return
	end

	-- Validate target BEFORE spending energy
	if character:GetAttribute(GameConstants.HERO_ATTRIBUTE) ~= "loki" then
		return
	end
	if CombatHelper.arePowersDisabled(character) then
		return
	end
	if character:GetAttribute(GameConstants.BUSY_ATTRIBUTE) == true then
		return
	end
	if AbilityCooldownHelper.isOnCooldown(character, entry.id) then
		return
	end
	if AbilityCooldownHelper.isActive(character, entry.id) then
		return
	end

	local target = targetModel
	if not target or target == character then
		return
	end
	if not CombatHelper.getHumanoid(target) then
		return
	end

	if not CharacterService.spendEnergy(character, GameConstants.LOKI_SHAPESHIFT_ENERGY) then
		return
	end

	local ok, body = pcall(function()
		local was = target.Archivable
		target.Archivable = true
		local c = target:Clone()
		target.Archivable = was
		return c
	end)
	if not ok or not body or not body:IsA("Model") then
		-- Refund energy if clone failed
		local energy = character:GetAttribute(GameConstants.ENERGY_ATTRIBUTE)
		local maxE = character:GetAttribute(GameConstants.MAX_ENERGY_ATTRIBUTE)
		if type(energy) == "number" and type(maxE) == "number" then
			character:SetAttribute(
				GameConstants.ENERGY_ATTRIBUTE,
				math.min(maxE, energy + GameConstants.LOKI_SHAPESHIFT_ENERGY)
			)
		end
		return
	end

	stripCloneNoise(body, false)
	-- Remove leftover humanoid / UI; keep visual transparency exactly as cloned
	for _, d in body:GetDescendants() do
		if d:IsA("Humanoid") or d:IsA("Animator") or d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		elseif d:IsA("BillboardGui") or d:IsA("Highlight") then
			d:Destroy()
		end
	end
	body.Name = SHAPESHIFT_BODY_NAME
	local bodyRoot = getRoot(body)
	local charRoot = getRoot(character)
	if not bodyRoot or not charRoot then
		body:Destroy()
		local energy = character:GetAttribute(GameConstants.ENERGY_ATTRIBUTE)
		local maxE = character:GetAttribute(GameConstants.MAX_ENERGY_ATTRIBUTE)
		if type(energy) == "number" and type(maxE) == "number" then
			character:SetAttribute(
				GameConstants.ENERGY_ATTRIBUTE,
				math.min(maxE, energy + GameConstants.LOKI_SHAPESHIFT_ENERGY)
			)
		end
		return
	end

	-- Fade Loki out (restore later from saved transparency — keep invisible parts invisible)
	for _, desc in character:GetDescendants() do
		if desc:IsA("BasePart") and desc ~= charRoot then
			desc:SetAttribute(SHAPESHIFT_HIDE_NAME, true)
			desc:SetAttribute(SHAPESHIFT_ORIG_T, desc.Transparency)
			TweenService:Create(desc, TweenInfo.new(SHAPESHIFT_MORPH_TIME), { Transparency = 1 }):Play()
		elseif desc:IsA("Decal") or desc:IsA("Texture") then
			desc:SetAttribute(SHAPESHIFT_HIDE_NAME, true)
			desc:SetAttribute(SHAPESHIFT_ORIG_T, desc.Transparency)
			TweenService:Create(desc, TweenInfo.new(SHAPESHIFT_MORPH_TIME), { Transparency = 1 }):Play()
		elseif desc:IsA("Accessory") then
			desc:SetAttribute(SHAPESHIFT_HIDE_NAME, true)
			for _, p in desc:GetDescendants() do
				if p:IsA("BasePart") then
					p:SetAttribute(SHAPESHIFT_ORIG_T, p.Transparency)
					TweenService:Create(p, TweenInfo.new(SHAPESHIFT_MORPH_TIME), { Transparency = 1 }):Play()
				end
			end
		end
	end

	-- Disguise: collision off, preserve exact visual transparency (incl. already-invisible parts)
	local fadeGoals: { { inst: Instance, goal: number } } = {}
	for _, part in body:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = true
			local goal = part.Transparency
			table.insert(fadeGoals, { inst = part, goal = goal })
			part.Transparency = 1
		elseif part:IsA("Decal") or part:IsA("Texture") then
			local goal = part.Transparency
			table.insert(fadeGoals, { inst = part, goal = goal })
			part.Transparency = 1
		end
	end
	body:PivotTo(character:GetPivot())
	body.Parent = character
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = charRoot
	weld.Part1 = bodyRoot
	weld.Parent = bodyRoot

	for _, entryFade in fadeGoals do
		local inst = entryFade.inst
		if inst:IsA("BasePart") or inst:IsA("Decal") or inst:IsA("Texture") then
			TweenService:Create(inst, TweenInfo.new(SHAPESHIFT_MORPH_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Transparency = entryFade.goal,
			}):Play()
		end
	end

	AbilityCooldownHelper.setActive(character, entry.id, true)
	character:SetAttribute(GameConstants.LOKI_SHAPESHIFT_ATTRIBUTE, true)

	local token = (shapeshiftToken[player] or 0) + 1
	shapeshiftToken[player] = token
	task.delay(GameConstants.LOKI_SHAPESHIFT_DURATION, function()
		if shapeshiftToken[player] ~= token then
			return
		end
		clearShapeshift(player, character)
		if character.Parent then
			finishAbility(character, entry.id, GameConstants.LOKI_SHAPESHIFT_COOLDOWN)
		end
	end)
end

local INVIS_ORIG_T = "LokiInvisServerOrigT"
local INVIS_WAS_ENABLED = "LokiInvisServerWasEnabled"
local invisDescConns: { [Model]: RBXScriptConnection } = {}

local function applyInvisToDescendant(desc: Instance, on: boolean)
	if desc:IsA("BasePart") then
		if on then
			if desc:GetAttribute(INVIS_ORIG_T) == nil then
				desc:SetAttribute(INVIS_ORIG_T, desc.Transparency)
			end
			desc.Transparency = 1
			desc.LocalTransparencyModifier = 0
		else
			local orig = desc:GetAttribute(INVIS_ORIG_T)
			if type(orig) == "number" then
				desc.Transparency = if desc.Name == "HumanoidRootPart" then 1 else orig
				desc:SetAttribute(INVIS_ORIG_T, nil)
			end
			desc.LocalTransparencyModifier = 0
		end
	elseif desc:IsA("Decal") or desc:IsA("Texture") then
		if on then
			if desc:GetAttribute(INVIS_ORIG_T) == nil then
				desc:SetAttribute(INVIS_ORIG_T, desc.Transparency)
			end
			desc.Transparency = 1
		else
			local orig = desc:GetAttribute(INVIS_ORIG_T)
			if type(orig) == "number" then
				desc.Transparency = orig
				desc:SetAttribute(INVIS_ORIG_T, nil)
			end
		end
	elseif desc:IsA("ParticleEmitter") or desc:IsA("Beam") or desc:IsA("Trail") or desc:IsA("Fire") or desc:IsA("Smoke") then
		if on then
			if desc:GetAttribute(INVIS_WAS_ENABLED) == nil then
				desc:SetAttribute(INVIS_WAS_ENABLED, desc.Enabled)
			end
			desc.Enabled = false
		else
			local was = desc:GetAttribute(INVIS_WAS_ENABLED)
			if typeof(was) == "boolean" then
				desc.Enabled = was
				desc:SetAttribute(INVIS_WAS_ENABLED, nil)
			end
		end
	elseif desc:IsA("Highlight") then
		desc.Enabled = not on
	elseif desc:IsA("BillboardGui") or desc:IsA("SurfaceGui") then
		desc.Enabled = not on
	elseif desc:IsA("PointLight") or desc:IsA("SpotLight") or desc:IsA("SurfaceLight") then
		if on then
			if desc:GetAttribute(INVIS_WAS_ENABLED) == nil then
				desc:SetAttribute(INVIS_WAS_ENABLED, desc.Enabled)
			end
			desc.Enabled = false
		else
			local was = desc:GetAttribute(INVIS_WAS_ENABLED)
			if typeof(was) == "boolean" then
				desc.Enabled = was
				desc:SetAttribute(INVIS_WAS_ENABLED, nil)
			end
		end
	end
end

local function setInvisible(character: Model, on: boolean)
	-- Server-authoritative invis (replicates to all clients + Studio server view).
	-- Local Loki client restores a ghost silhouette for the caster only.
	character:SetAttribute(GameConstants.LOKI_INVISIBLE_ATTRIBUTE, if on then true else nil)

	for _, desc in character:GetDescendants() do
		applyInvisToDescendant(desc, on)
	end

	local existing = invisDescConns[character]
	if existing then
		existing:Disconnect()
		invisDescConns[character] = nil
	end
	if on then
		invisDescConns[character] = character.DescendantAdded:Connect(function(desc)
			if character:GetAttribute(GameConstants.LOKI_INVISIBLE_ATTRIBUTE) == true then
				applyInvisToDescendant(desc, true)
			end
		end)
	end

	local hum = character:FindFirstChildOfClass("Humanoid")
	if hum then
		if on then
			hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			hum.NameDisplayDistance = 0
			hum.HealthDisplayDistance = 0
		else
			hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
		end
	end
end

local function destroyUlt(player: Player, applyCooldown: boolean)
	local state = ultByPlayer[player]
	if not state then
		return
	end
	ultByPlayer[player] = nil
	for _, c in state.clones do
		if c.animConn then
			c.animConn:Disconnect()
			c.animConn = nil
		end
		if c.clone.Parent then
			for _, part in c.clone:GetDescendants() do
				if part:IsA("BasePart") then
					TweenService:Create(part, TweenInfo.new(0.45), { Transparency = 1 }):Play()
				end
			end
			task.delay(0.5, function()
				if c.clone.Parent then
					c.clone:Destroy()
				end
			end)
		end
	end
	if state.character.Parent then
		setInvisible(state.character, false)
		state.character:SetAttribute(GameConstants.LOKI_ULT_ACTIVE_ATTRIBUTE, nil)
		state.character:SetAttribute(GameConstants.LOKI_ULT_ATTACK_ATTRIBUTE, nil)
		AbilityCooldownHelper.setActive(state.character, "god_of_mischief", false)
		if applyCooldown then
			AbilityCooldownHelper.applyAfterUse(state.character, "god_of_mischief", GameConstants.LOKI_ULT_COOLDOWN)
			CharacterService.markAbilityUse(state.character)
		end
	end
end

local function pickUltWander(home: Vector3): Vector3
	local angle = math.random() * math.pi * 2
	local dist = math.random() * GameConstants.LOKI_ULT_ROAM_RADIUS
	return home + Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
end

local function spawnUltClone(owner: Model, offset: Vector3): UltCloneState?
	local ok, clone = pcall(function()
		local was = owner.Archivable
		owner.Archivable = true
		local c = owner:Clone()
		owner.Archivable = was
		return c
	end)
	if not ok or not clone or not clone:IsA("Model") then
		return nil
	end
	stripCloneNoise(clone, true)
	copyAnimateFromSource(clone, owner)
	clone.Name = "LokiMischiefClone"
	clone:SetAttribute("LokiUltClone", true)
	clone:SetAttribute("FearVisual", true)
	-- Roaming clones: unanchored, light collision
	for _, part in clone:GetDescendants() do
		if part:IsA("BasePart") then
			part.LocalTransparencyModifier = 0
			part.CanCollide = part.Name == "HumanoidRootPart" or part.Name == "UpperTorso" or part.Name == "Torso"
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = false
			part.Anchored = false
		elseif part:IsA("ParticleEmitter") or part:IsA("Trail") or part:IsA("Beam") then
			part:Destroy()
		end
	end
	local hum = clone:FindFirstChildOfClass("Humanoid")
	local root = getRoot(clone)
	if not hum or not root then
		clone:Destroy()
		return nil
	end
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.PlatformStand = false
	hum.WalkSpeed = GameConstants.LOKI_ULT_ROAM_SPEED
	hum.AutoRotate = true
	root.Anchored = false
	root.CanCollide = true
	local ownerRoot = getRoot(owner)
	local base = if ownerRoot then ownerRoot.CFrame else owner:GetPivot()
	clone:PivotTo(base * CFrame.new(offset))
	clone.Parent = Workspace
	revealCloneFeetToHead(clone, 0.45)
	local home = root.Position
	local animConn = attachCloneAnimate(clone, owner)
	return {
		clone = clone,
		root = root,
		humanoid = hum,
		lastBlast = 0,
		owner = owner,
		home = home,
		wanderTarget = pickUltWander(home),
		nextWanderAt = os.clock() + 0.2 + math.random() * 0.5,
		animConn = animConn,
	}
end

local function setUltAttackMode(player: Player, mode: string)
	local state = ultByPlayer[player]
	if not state then
		return
	end
	local enabled = mode == "Attack" or mode == "Attack On" or mode == "On"
	if mode == "Idle" or mode == "Attack Off" or mode == "Off" or mode == "Cease" then
		enabled = false
	elseif mode ~= "Attack" and mode ~= "Attack On" and mode ~= "On" then
		return
	end
	state.attackEnabled = enabled
	if state.character.Parent then
		state.character:SetAttribute(GameConstants.LOKI_ULT_ATTACK_ATTRIBUTE, if enabled then true else false)
	end
end

local function startGodOfMischief(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local entry = CharacterRegistry.getAbilityById("loki", "god_of_mischief")
	if not entry or not canUse(character, entry.id, GameConstants.LOKI_ULT_ENERGY) then
		return
	end
	if ultByPlayer[player] then
		return
	end

	AbilityCooldownHelper.setActive(character, entry.id, true)

	-- Spawn clones WHILE still visible, then go invisible
	local clones: { UltCloneState } = {}
	local offsets = {
		Vector3.new(4, 0, 2),
		Vector3.new(-4, 0, 2),
		Vector3.new(0, 0, -4),
	}
	for _, off in offsets do
		local c = spawnUltClone(character, off)
		if c then
			table.insert(clones, c)
		end
	end
	setInvisible(character, true)
	character:SetAttribute(GameConstants.LOKI_ULT_ACTIVE_ATTRIBUTE, true)
	character:SetAttribute(GameConstants.LOKI_ULT_ATTACK_ATTRIBUTE, true)

	ultByPlayer[player] = {
		character = character,
		clones = clones,
		startedAt = os.clock(),
		attackEnabled = true,
	}

	task.delay(GameConstants.LOKI_ULT_CLONE_LIFE, function()
		local state = ultByPlayer[player]
		if not state then
			return
		end
		for _, c in state.clones do
			if c.animConn then
				c.animConn:Disconnect()
				c.animConn = nil
			end
			if c.clone.Parent then
				for _, part in c.clone:GetDescendants() do
					if part:IsA("BasePart") then
						TweenService:Create(part, TweenInfo.new(0.45), { Transparency = 1 }):Play()
					end
				end
				task.delay(0.5, function()
					if c.clone.Parent then
						c.clone:Destroy()
					end
				end)
			end
		end
		state.clones = {}
	end)

	task.delay(GameConstants.LOKI_ULT_DURATION_INVIS, function()
		destroyUlt(player, true)
	end)
end

local function startReflect(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local entry = CharacterRegistry.getAbilityById("loki", "reflect_shield")
	if not entry or not canUse(character, entry.id, GameConstants.LOKI_REFLECT_ENERGY) then
		return
	end

	AbilityCooldownHelper.setActive(character, entry.id, true)
	character:SetAttribute(GameConstants.LOKI_REFLECT_ATTRIBUTE, true)
	reflectUntil[player] = AbilityCooldownHelper.getNow() + GameConstants.LOKI_REFLECT_DURATION

	local hl = Instance.new("Highlight")
	hl.Name = "LokiReflectHighlight"
	hl.FillTransparency = 1
	hl.OutlineTransparency = 0
	hl.OutlineColor = lokiGreen()
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Adornee = character
	hl.Parent = character

	task.delay(GameConstants.LOKI_REFLECT_DURATION, function()
		if hl.Parent then
			hl:Destroy()
		end
		if character.Parent then
			character:SetAttribute(GameConstants.LOKI_REFLECT_ATTRIBUTE, nil)
			finishAbility(character, entry.id, GameConstants.LOKI_REFLECT_COOLDOWN)
		end
		reflectUntil[player] = nil
	end)
end

local function fireUltCloneBlast(c: UltCloneState)
	local near = CombatHelper.overlapCharacters(c.root.Position, GameConstants.LOKI_ULT_BLAST_RANGE, c.owner)
	local best: Model? = nil
	local bestDist = GameConstants.LOKI_ULT_BLAST_RANGE
	for _, model in near do
		if model:GetAttribute("LokiUltClone") == true or model:GetAttribute("LokiDecoy") == true then
			continue
		end
		local root = getRoot(model)
		if not root then
			continue
		end
		local d = (root.Position - c.root.Position).Magnitude
		if d < bestDist then
			bestDist = d
			best = model
		end
	end
	if not best then
		return
	end
	local tRoot = getRoot(best)
	if not tRoot then
		return
	end
	local origin = c.root.Position + Vector3.new(0, 1.5, 0)
	local dir = (tRoot.Position - origin)
	if dir.Magnitude < 0.05 then
		return
	end
	dir = dir.Unit
	c.root.CFrame = CFrame.lookAt(c.root.Position, Vector3.new(tRoot.Position.X, c.root.Position.Y, tRoot.Position.Z))
	ProjectileHelper.spawn(origin, dir, {
		speed = 120,
		damage = GameConstants.LOKI_ULT_BLAST_DAMAGE,
		radius = 2.4,
		maxDistance = GameConstants.LOKI_ULT_BLAST_RANGE,
		owner = c.owner,
		color = lokiGreen(),
		homeDir = dir,
		homePoint = tRoot.Position,
		homeTarget = best,
		homeAfter = 0,
		seekUntilClose = true,
		seekCloseDistance = 2.2,
		boltFolder = "Loki",
		boltAsset = "EnergyBlast",
		impactFx = "loki",
	})
end

function LokiService.update(dt: number)
	local now = os.clock()
	local _ = dt

	for player, state in decoyByPlayer do
		if not state.character.Parent or player.Character ~= state.character or not state.clone.Parent then
			endDecoy(player, true)
			continue
		end
		if now - state.startedAt >= GameConstants.LOKI_CLONE_DURATION then
			endDecoy(player, true)
			continue
		end
		if state.humanoid.Health <= 0 then
			endDecoy(player, true)
			continue
		end
		if state.mode == "Run" then
			state.humanoid.WalkSpeed = GameConstants.LOKI_CLONE_RUN_SPEED
			state.humanoid:MoveTo(state.aimPoint)
		end
	end

	for player, state in ultByPlayer do
		if not state.character.Parent or player.Character ~= state.character then
			destroyUlt(player, false)
			continue
		end
		for _, c in state.clones do
			if not c.clone.Parent or not c.root.Parent then
				continue
			end
			-- Random roam in a small area around spawn home
			if now >= c.nextWanderAt then
				c.wanderTarget = pickUltWander(c.home)
				c.nextWanderAt = now + GameConstants.LOKI_ULT_WANDER_INTERVAL * (0.7 + math.random() * 0.6)
			end
			c.humanoid.WalkSpeed = GameConstants.LOKI_ULT_ROAM_SPEED
			c.humanoid:MoveTo(c.wanderTarget)

			if state.attackEnabled and now - c.lastBlast >= GameConstants.LOKI_ULT_BLAST_CD then
				c.lastBlast = now
				fireUltCloneBlast(c)
			end
		end
	end
end

function LokiService.cancelAll(player: Player)
	decoyArmed[player] = false
	endDecoy(player, false)
	destroyUlt(player, false)
	reflectUntil[player] = nil
	dashUntil[player] = nil
	shapeshiftToken[player] = (shapeshiftToken[player] or 0) + 1
	local char = player.Character
	if char then
		clearShapeshift(player, char)
		clearTeleportAim(char, "trickster_dash")
		char:SetAttribute(GameConstants.LOKI_REFLECT_ATTRIBUTE, nil)
		char:SetAttribute(GameConstants.LOKI_CLONE_ACTIVE_ATTRIBUTE, nil)
		char:SetAttribute(GameConstants.LOKI_CLONE_MODE_ATTRIBUTE, nil)
		char:SetAttribute(GameConstants.LOKI_SHAPESHIFT_ATTRIBUTE, nil)
		char:SetAttribute(GameConstants.LOKI_INVISIBLE_ATTRIBUTE, nil)
		local hl = char:FindFirstChild("LokiReflectHighlight")
		if hl then
			hl:Destroy()
		end
		local dashLv = char:FindFirstChild("LokiDashVelocity", true)
		if dashLv then
			dashLv:Destroy()
		end
	end
end

function LokiService.handleAction(player: Player, payload: any)
	if type(payload) ~= "table" then
		return
	end
	local character = player.Character
	if not character or character:GetAttribute(GameConstants.HERO_ATTRIBUTE) ~= "loki" then
		return
	end

	local action = payload.action
	if type(action) ~= "string" then
		return
	end

	local direction = if typeof(payload.direction) == "Vector3" then payload.direction else Vector3.new(0, 0, -1)
	local aimPoint = if typeof(payload.aimPoint) == "Vector3" then payload.aimPoint else nil
	local moveVector = if typeof(payload.moveVector) == "Vector3" then payload.moveVector else nil
	local targetModel = if typeof(payload.target) == "Instance" and payload.target:IsA("Model")
		then payload.target
		else nil

	if action == "SetMode" then
		if type(payload.abilityId) == "string" and type(payload.mode) == "string" then
			if payload.abilityId == "illusion_decoy" then
				setDecoyMode(player, payload.mode)
			elseif payload.abilityId == "god_of_mischief" then
				setUltAttackMode(player, payload.mode)
			elseif payload.abilityId == "trickster_dash" then
				if payload.mode == "Dash" or payload.mode == "Teleport" then
					character:SetAttribute(GameConstants.LOKI_DASH_MODE_ATTRIBUTE, payload.mode)
				end
			end
		end
		return
	end

	if action == "Q" then
		fireDaggers(player, direction, aimPoint)
	elseif action == "E_down" then
		local entry = CharacterRegistry.getAbilityById("loki", "illusion_decoy")
		if
			entry
			and not AbilityCooldownHelper.isOnCooldown(character, entry.id)
			and not decoyByPlayer[player]
		then
			decoyArmed[player] = true
		end
	elseif action == "E_up" then
		decoyArmed[player] = false
	elseif action == "E_throw" then
		placeDecoy(player, aimPoint)
	elseif action == "E_update" then
		local state = decoyByPlayer[player]
		if state and aimPoint then
			state.aimPoint = aimPoint
		end
	elseif action == "F" then
		tricksterMove(player, moveVector, direction, aimPoint)
	elseif action == "F_confirm" then
		confirmTeleport(player, aimPoint)
	elseif action == "C" or action == "C_down" then
		startReflect(player)
	elseif action == "V" then
		startShapeshift(player, targetModel)
	elseif action == "X" then
		startGodOfMischief(player)
	end
end

function LokiService.init()
	Remotes.getEvent("UseAbility").OnServerEvent:Connect(function(player: Player, payload: any)
		LokiService.handleAction(player, payload)
	end)

	local function hookPlayer(player: Player)
		player.CharacterRemoving:Connect(function()
			LokiService.cancelAll(player)
		end)
		player.CharacterAdded:Connect(function(character)
			LokiService.cancelAll(player)
			local humanoid = character:WaitForChild("Humanoid", 5)
			if humanoid and humanoid:IsA("Humanoid") then
				humanoid.Died:Connect(function()
					LokiService.cancelAll(player)
				end)
			end
		end)
		if player.Character then
			local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.Died:Connect(function()
					LokiService.cancelAll(player)
				end)
			end
		end
	end

	for _, player in Players:GetPlayers() do
		hookPlayer(player)
	end
	Players.PlayerAdded:Connect(hookPlayer)
	Players.PlayerRemoving:Connect(function(player)
		LokiService.cancelAll(player)
	end)
end

return LokiService
