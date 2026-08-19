--!strict

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local CombatHelper = require(ReplicatedStorage.Shared.CombatHelper)
local GameConstants = require(ReplicatedStorage.Shared.GameConstants)
local PushHelper = require(ReplicatedStorage.Shared.PushHelper)
local RagdollStatus = require(ReplicatedStorage.Shared.RagdollStatus)
local VfxHelper = require(ReplicatedStorage.Shared.VfxHelper)

local ProjectileHelper = {}

export type ProjectileOptions = {
	speed: number,
	damage: number,
	radius: number,
	maxDistance: number,
	color: Color3?,
	owner: Model,
	accel: number?,
	maxSpeed: number?,
	homeDir: Vector3?,
	homePoint: Vector3?, -- steer toward this world point (aim / body)
	homeTarget: Model?, -- keep updating homePoint from this character
	-- If set, each frame read owner:GetAttribute(name) as Vector3 for live aim (e.g. mouse)
	liveHomeAimAttribute: string?,
	homeAfter: number?,
	homeTurnScale: number?,
	-- If true: deal damage on touch but keep flying until near the target body
	seekUntilClose: boolean?,
	seekCloseDistance: number?,
	ragdollOnHit: number?,
	pushOnHit: boolean?,
	pushSpeed: number?,
	pushUp: number?,
	impactAoeRadius: number?,
	impactAoeDamage: number?,
	impactFx: string?, -- "blast" (default) | "photon_explosion" | "dagger_light" | "psionic" | "none"
	boltFolder: string?, -- Assets subfolder (default ScarletWitch)
	boltAsset: string?, -- template name (default HexBolt)
	customVisual: Instance?, -- existing Part/Model to fly as the bolt (e.g. debris)
	facingOffset: CFrame?, -- extra rotation so mesh faces travel direction
	lockWorldRotation: CFrame?, -- keep this world rotation instead of facing travel (debris rocks)
	-- Seconds to keep visual after particles disable (default short fade)
	deleteAfterFx: number?,
	shouldHeal: ((Model, Model) -> boolean)?, -- (owner, victim) → heal instead of damage
	healAmount: number?,
	ricochetMax: number?, -- max bounces (targets + surfaces)
	ricochetSearchRadius: number?, -- range to find next target after a hit
	onHit: ((Model, Vector3) -> ())?,
	onImpact: ((Vector3, boolean?) -> ())?,
	recolorVisual: boolean?, -- tint cloned bolt particles/beams/trails to options.color
	keepVisual: boolean?, -- leave custom visual in the world after impact (caller owns cleanup)
	impactOnCharacter: boolean?, -- stop at first body contact instead of seeking into the torso
}

type ProjectileState = {
	owner: Model,
	velocity: Vector3,
	speed: number,
	accel: number,
	maxSpeed: number,
	homeDir: Vector3?,
	homePoint: Vector3?,
	homeTarget: Model?,
	liveHomeAimAttribute: string?,
	homeAfter: number,
	homeTurnScale: number,
	seekUntilClose: boolean,
	seekCloseDistance: number,
	age: number,
	damage: number,
	radius: number,
	traveled: number,
	maxDistance: number,
	spawnOrigin: Vector3,
	ragdollOnHit: number?,
	pushOnHit: boolean?,
	pushSpeed: number?,
	pushUp: number?,
	impactAoeRadius: number?,
	impactAoeDamage: number?,
	impactFx: string?,
	shouldHeal: ((Model, Model) -> boolean)?,
	healAmount: number?,
	ricochetsLeft: number,
	ricochetSearchRadius: number,
	hit: { [Model]: boolean },
	onHit: ((Model, Vector3) -> ())?,
	onImpact: ((Vector3, boolean?) -> ())?,
	color: Color3,
	visual: Instance,
	facingOffset: CFrame,
	lockWorldRotation: CFrame?,
	deleteAfterFx: number?,
	recolorVisual: boolean?,
	keepVisual: boolean?,
	impactOnCharacter: boolean,
	hitCharacter: boolean,
}

local active: { [BasePart]: ProjectileState } = {}

local function getBoltTemplate(folderName: string?, assetName: string?): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		return nil
	end
	local name = assetName or "HexBolt"
	if folderName == nil or folderName == "ScarletWitch" or folderName == "ScarletWitchClassic" then
		local classic = assets:FindFirstChild("ScarletWitchClassic")
		local hexBolt = classic and classic:FindFirstChild("HexBolt")
		if hexBolt then
			local nested = hexBolt:FindFirstChild(if name == "HexBolt" then "Bolt" else name)
				or hexBolt:FindFirstChild("Bolt")
			if nested then
				return nested
			end
			if hexBolt:IsA("BasePart") or hexBolt:IsA("Attachment") or hexBolt:IsA("Model") then
				return hexBolt
			end
		end
	end
	local folder = assets:FindFirstChild(folderName or "ScarletWitch")
	if not folder then
		return nil
	end
	local direct = folder:FindFirstChild(name)
	if direct then
		return direct
	end
	if folderName == "JeanGrey" or folderName == "MarvelGirl" then
		local boltFolder = folder:FindFirstChild("PsionicBolt")
		if boltFolder then
			local nested = boltFolder:FindFirstChild(name)
			if nested then
				return nested
			end
			if name == "PsychicBlast" or name == "PsychicBolt" then
				return boltFolder:FindFirstChild("PsychicBolt")
			end
		end
	end
	return nil
end

--[[ Explicit: ReplicatedStorage.Assets.Dagger.RadiantBomb (Attachment). ]]
local function getRadiantBombAttachment(): Attachment?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local dagger = assets and assets:FindFirstChild("Dagger")
	local inst = dagger and dagger:FindFirstChild("RadiantBomb")
	if inst and inst:IsA("Attachment") then
		return inst
	end
	-- Nested attachment under a folder/part
	if inst then
		if inst:IsA("Attachment") then
			return inst
		end
		local nested = inst:FindFirstChildWhichIsA("Attachment", true)
		if nested then
			return nested
		end
	end
	return nil
end

local function emitBoltParticlesNow(root: Instance, count: number?)
	-- Immediate Emit on every ParticleEmitter (plus keep Enabled for flight Rate)
	for _, desc in root:GetDescendants() do
		if desc:IsA("ParticleEmitter") or desc:IsA("Beam") or desc:IsA("Trail") or desc:IsA("PointLight") or desc:IsA("SpotLight") then
			(desc :: any).Enabled = true
		end
	end
	if root:IsA("ParticleEmitter") or root:IsA("Beam") or root:IsA("Trail") then
		(root :: any).Enabled = true
	end
	VfxHelper.emitAllParticles(root, count or 16)
end

local function applyAreaForcefieldHit(hitInst: Instance, damage: number): boolean
	local node: Instance? = hitInst
	while node and node ~= workspace do
		if node:GetAttribute("IwAreaShield") == true then
			local root = node
			local parent = root.Parent
			while parent and parent ~= workspace and parent:GetAttribute("IwAreaShield") == true do
				root = parent
				parent = root.Parent
			end
			if root:GetAttribute("IwAreaBroken") == true then
				return true
			end
			local hp = root:GetAttribute("IwAreaHp")
			if type(hp) ~= "number" then
				hp = GameConstants.IW_AREA_HP
			end
			hp -= damage
			root:SetAttribute("IwAreaHp", hp)
			if hp <= 0 then
				root:SetAttribute("IwAreaBroken", true)
				root:SetAttribute("IwAreaHp", 0)
			end
			return true
		end
		node = node.Parent
	end
	return false
end

local function prepareBoltPart(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
end

local function disableBoltEffects(root: Instance)
	local stack: { Instance } = { root }
	while #stack > 0 do
		local inst = table.remove(stack) :: Instance
		if inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Beam") then
			inst.Enabled = false
		elseif inst:IsA("Fire") or inst:IsA("Smoke") or inst:IsA("Sparkles") then
			inst.Enabled = false
		elseif inst:IsA("Light") then
			inst.Enabled = false
		end
		for _, child in inst:GetChildren() do
			table.insert(stack, child)
		end
	end
end

-- Stop simulating, fade all parts smoothly, kill FX, then delete.
local function retireVisual(visual: Instance, root: BasePart, deleteAfterFx: number?)
	task.spawn(function()
		local fadeTime = 0.35
		local targets: { Instance } = {}
		local source = if visual.Parent then visual else root
		if source.Parent then
			if source:IsA("BasePart") then
				table.insert(targets, source)
			end
			for _, desc in source:GetDescendants() do
				if desc:IsA("BasePart") or desc:IsA("Decal") or desc:IsA("Texture") then
					table.insert(targets, desc)
				end
			end
			for _, inst in targets do
				if inst:IsA("BasePart") or inst:IsA("Decal") or inst:IsA("Texture") then
					TweenService:Create(inst, TweenInfo.new(fadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
						Transparency = 1,
					}):Play()
				end
			end
		end
		task.wait(GameConstants.HEX_BOLT_FX_DISABLE_DELAY)
		if visual.Parent then
			disableBoltEffects(visual)
		elseif root.Parent then
			disableBoltEffects(root)
		end
		local waitDelete = deleteAfterFx
			or math.max(fadeTime, GameConstants.HEX_BOLT_DELETE_DELAY * 0.25)
		task.wait(waitDelete)
		if visual.Parent then
			visual:Destroy()
		elseif root.Parent then
			root:Destroy()
		end
	end)
end

local function lookCFrame(pos: Vector3, dir: Vector3): CFrame
	local d = if dir.Magnitude > 0.01 then dir.Unit else Vector3.new(0, 0, -1)
	local up = Vector3.yAxis
	if math.abs(d:Dot(up)) > 0.95 then
		up = Vector3.xAxis
	end
	return CFrame.lookAt(pos, pos + d, up)
end

local function setVisualCFrame(visual: Instance, root: BasePart, cf: CFrame)
	if visual:IsA("Model") then
		visual:PivotTo(cf)
	else
		root.CFrame = cf
	end
end

local function visualTravelCFrame(state: ProjectileState, pos: Vector3, look: Vector3): CFrame
	if state.lockWorldRotation then
		local rot = state.lockWorldRotation - state.lockWorldRotation.Position
		return CFrame.new(pos) * rot
	end
	return lookCFrame(pos, look) * state.facingOffset
end

local function createFallbackBolt(origin: Vector3, dir: Vector3, color: Color3): (BasePart, Instance)
	local ball = Instance.new("Part")
	ball.Name = "HexProjectile"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(1.2, 1.2, 1.2)
	ball.CFrame = CFrame.lookAt(origin, origin + dir)
	ball.Material = Enum.Material.SmoothPlastic
	ball.Color = color
	ball.Transparency = 0.25
	prepareBoltPart(ball)
	ball.Parent = workspace

	local shell = Instance.new("Part")
	shell.Name = "HexShell"
	shell.Shape = Enum.PartType.Ball
	shell.Size = Vector3.new(1.85, 1.85, 1.85)
	shell.CFrame = ball.CFrame
	shell.Material = Enum.Material.ForceField
	shell.Color = color
	shell.Transparency = 0.65
	prepareBoltPart(shell)
	shell.Parent = ball

	VfxHelper.attachProjectileTrail(ball, color)
	return ball, ball
end

local function createHexBoltVisual(
	origin: Vector3,
	dir: Vector3,
	color: Color3,
	folderName: string?,
	assetName: string?
): (BasePart, Instance)
	local cf = CFrame.lookAt(origin, origin + dir)

	-- Radiant Bomb: always use ReplicatedStorage.Assets.Dagger.RadiantBomb attachment
	if folderName == "Dagger" and assetName == "RadiantBomb" then
		local template = getRadiantBombAttachment()
		if not template then
			warn("[ProjectileHelper] Missing ReplicatedStorage.Assets.Dagger.RadiantBomb (Attachment)")
			return createFallbackBolt(origin, dir, color)
		end
		local host = Instance.new("Part")
		host.Name = "RadiantBombProjectile"
		host.Shape = Enum.PartType.Ball
		host.Size = Vector3.new(1.6, 1.6, 1.6)
		host.CFrame = cf
		host.Transparency = 1
		host.Material = Enum.Material.SmoothPlastic
		host.CastShadow = false
		prepareBoltPart(host)
		-- Parent host first so emitters are in World when Emitting
		host.Parent = workspace
		local att = template:Clone()
		att.Name = "RadiantBomb"
		att.Position = Vector3.zero
		att.Orientation = Vector3.zero
		att.Parent = host
		VfxHelper.tintParticles(att, color)
		emitBoltParticlesNow(att, 24)
		-- Second Emit next frame in case template Rate/lifetime needs a live step
		task.defer(function()
			if att.Parent then
				emitBoltParticlesNow(att, 24)
			end
		end)
		return host, host
	end

	local template = getBoltTemplate(folderName, assetName)
	if not template then
		return createFallbackBolt(origin, dir, color)
	end

	local clone = template:Clone()
	clone.Name = "HexProjectile"

	-- Attachment-only assets: host on invisible part
	if clone:IsA("Attachment") then
		local host = Instance.new("Part")
		host.Name = "HexProjectile"
		host.Shape = Enum.PartType.Ball
		host.Size = Vector3.new(1.4, 1.4, 1.4)
		host.CFrame = cf
		host.Transparency = 1
		host.Material = Enum.Material.SmoothPlastic
		prepareBoltPart(host)
		clone.Parent = host
		if folderName == "Dagger" then
			VfxHelper.tintParticles(host, color)
		end
		host.Parent = workspace
		emitBoltParticlesNow(host, 12)
		-- PsychicBolt already includes trails — don't stack a generic trail
		if not ((folderName == "JeanGrey" or folderName == "MarvelGirl") and (assetName == "PsychicBolt" or assetName == "PsychicBlast")) then
			VfxHelper.attachProjectileTrail(host, color)
		end
		return host, host
	end

	if clone:IsA("BasePart") then
		prepareBoltPart(clone)
		local impact = clone:FindFirstChild("DaggerImpact", true) or clone:FindFirstChild("ImpactParticle", true)
		if impact then
			impact:Destroy()
		end
		if folderName == "Dagger" then
			VfxHelper.tintParticles(clone, color)
		end
		clone.CFrame = cf
		clone.Parent = workspace
		emitBoltParticlesNow(clone, 10)
		return clone, clone
	end

	if clone:IsA("Model") then
		local primary = clone.PrimaryPart or clone:FindFirstChildWhichIsA("BasePart", true)
		if not primary then
			clone:Destroy()
			return createFallbackBolt(origin, dir, color)
		end
		for _, desc in clone:GetDescendants() do
			if desc:IsA("BasePart") then
				prepareBoltPart(desc)
			end
			-- Never carry impact FX on the flying bolt
			if desc.Name == "DaggerImpact" or desc.Name == "ImpactParticle" then
				desc:Destroy()
			end
		end
		if folderName == "Dagger" then
			VfxHelper.tintParticles(clone, color)
		end
		if not clone.PrimaryPart then
			clone.PrimaryPart = primary
		end
		clone:PivotTo(cf)
		clone.Parent = workspace
		emitBoltParticlesNow(clone, 10)
		return primary, clone
	end

	-- Folder / other: prefer first BasePart, parent whole clone under a Model
	local firstPart = clone:FindFirstChildWhichIsA("BasePart", true)
	if not firstPart then
		-- Attachment / particle-only folder (PsychicBolt internals)
		local host = Instance.new("Part")
		host.Name = "HexProjectile"
		host.Shape = Enum.PartType.Ball
		host.Size = Vector3.new(1.4, 1.4, 1.4)
		host.CFrame = cf
		host.Transparency = 1
		host.Material = Enum.Material.SmoothPlastic
		prepareBoltPart(host)
		clone.Parent = host
		host.Parent = workspace
		emitBoltParticlesNow(host, 12)
		if not ((folderName == "JeanGrey" or folderName == "MarvelGirl") and (assetName == "PsychicBolt" or assetName == "PsychicBlast")) then
			VfxHelper.attachProjectileTrail(host, color)
		end
		return host, host
	end
	local wrapper = Instance.new("Model")
	wrapper.Name = "HexProjectile"
	clone.Parent = wrapper
	for _, desc in wrapper:GetDescendants() do
		if desc:IsA("BasePart") then
			prepareBoltPart(desc)
		end
	end
	wrapper.PrimaryPart = firstPart
	wrapper:PivotTo(cf)
	wrapper.Parent = workspace
	emitBoltParticlesNow(wrapper, 10)
	return firstPart, wrapper
end

local function getBoltEndPosition(visual: Instance, root: BasePart, look: Vector3): Vector3
	local dir = if look.Magnitude > 0.01 then look.Unit else root.CFrame.LookVector
	if visual:IsA("Model") then
		local cf, size = visual:GetBoundingBox()
		return cf.Position + dir * (size.Z * 0.5)
	end
	return root.Position + dir * (math.max(root.Size.Z, root.Size.X) * 0.5)
end

local function contactOnCharacter(from: Vector3, delta: Vector3, victim: Model, fallback: Vector3): Vector3
	local parts: { Instance } = {}
	for _, desc in victim:GetDescendants() do
		if desc:IsA("BasePart") then
			table.insert(parts, desc)
		end
	end
	if #parts == 0 then
		return fallback
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = parts
	local travel = if delta.Magnitude > 0.01 then delta else Vector3.new(0, -1, 0)
	local hit = workspace:Raycast(from, travel.Unit * (travel.Magnitude + 6), params)
	if hit then
		return hit.Position
	end
	return fallback
end

local function showImpactAoe(pos: Vector3, radius: number, color: Color3, impactFx: string?)
	local fx = impactFx or "blast"
	if fx == "photon_explosion" then
		VfxHelper.spawnPhotonExplosionImpact(pos, radius)
	elseif fx == "photon_blast" then
		VfxHelper.spawnPhotonBlastImpact(pos, radius)
	elseif fx == "dagger_light" then
		VfxHelper.spawnDaggerLightImpact(pos, radius)
	elseif fx ~= "none" then
		VfxHelper.spawnBlastImpact(pos, radius)
	end
	-- No procedural PulseRing — Assets particles only
end

local function applyProjectileHit(state: ProjectileState, victim: Model, hitFrom: Vector3?)
	if state.shouldHeal and state.shouldHeal(state.owner, victim) then
		CombatHelper.heal(victim, state.healAmount or state.damage)
		return
	end
	CombatHelper.dealDamage(state.owner, victim, state.damage, hitFrom, "projectile")
	if state.ragdollOnHit and state.ragdollOnHit > 0 then
		RagdollStatus.applyTimed(victim, state.ragdollOnHit)
	end
	if state.pushOnHit then
		local away = victim:FindFirstChild("HumanoidRootPart") :: BasePart?
		local pushDir = if away and hitFrom then (away.Position - hitFrom) else state.velocity
		if pushDir.Magnitude < 0.05 then
			pushDir = state.velocity
		end
		if pushDir.Magnitude < 0.01 then
			pushDir = Vector3.new(0, 0, -1)
		end
		PushHelper.applyToCharacter(victim, pushDir, {
			speed = state.pushSpeed or GameConstants.HEX_BLAST_BARRAGE_PUSH_SPEED,
			upBoost = state.pushUp or GameConstants.HEX_BLAST_BARRAGE_PUSH_UP,
		})
	end
end

local function findRicochetTarget(
	fromPos: Vector3,
	owner: Model,
	alreadyHit: { [Model]: boolean },
	searchRadius: number
): Model?
	local best: Model? = nil
	local bestDist = searchRadius
	for _, victim in CombatHelper.overlapCharacters(fromPos, searchRadius, owner) do
		if alreadyHit[victim] then
			continue
		end
		if victim:GetAttribute("LokiUltClone") == true or victim:GetAttribute("LokiDecoy") == true then
			continue
		end
		if victim:GetAttribute("FearVisual") == true or victim.Name == "FearClone" then
			continue
		end
		local root = victim:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			continue
		end
		local dist = (root.Position - fromPos).Magnitude
		if dist < bestDist then
			bestDist = dist
			best = victim
		end
	end
	return best
end

local function redirectToward(state: ProjectileState, part: BasePart, targetPos: Vector3)
	local to = targetPos - part.Position
	if to.Magnitude < 0.05 then
		return
	end
	local dir = to.Unit
	state.velocity = dir * state.speed
	state.homeDir = dir
	state.homePoint = targetPos
	state.homeTarget = nil
	state.seekUntilClose = false
end

--[[ Wanda shield: bounce bolt back at whoever fired it (or radial if unknown). ]]
local function redirectOffShield(
	state: ProjectileState,
	part: BasePart,
	shieldCharacter: Model,
	previousOwner: Model?,
	sparkPos: Vector3
)
	state.speed = GameConstants.SHIELD_DEFLECT_SPEED
	state.accel = 0
	state.traveled = 0
	state.owner = shieldCharacter
	-- Clear old seek so it doesn't steer back into the shield
	state.homePoint = nil
	state.homeTarget = nil
	state.seekUntilClose = false

	local aimModel: Model? = nil
	if previousOwner and previousOwner.Parent and previousOwner ~= shieldCharacter then
		aimModel = previousOwner
	end
	local aimRoot = aimModel and (aimModel:FindFirstChild("HumanoidRootPart") :: BasePart?)
	if aimRoot then
		redirectToward(state, part, aimRoot.Position)
		state.homeTarget = aimModel
		state.homePoint = aimRoot.Position
		state.seekUntilClose = true
	else
		local shieldRoot = shieldCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?
		local away = if shieldRoot then (part.Position - shieldRoot.Position) else state.velocity
		if away.Magnitude < 0.05 then
			away = if shieldRoot then shieldRoot.CFrame.LookVector else Vector3.new(0, 0, -1)
		end
		state.velocity = away.Unit * state.speed
		state.homeDir = away.Unit
	end
	VfxHelper.spawnBurstSparks(sparkPos, VfxHelper.chaosSoft(), 4)
end

local function reflectVelocity(state: ProjectileState, normal: Vector3)
	local vel = state.velocity
	if vel.Magnitude < 0.01 then
		return
	end
	local n = if normal.Magnitude > 0.01 then normal.Unit else Vector3.yAxis
	local reflected = vel - 2 * vel:Dot(n) * n
	if reflected.Magnitude < 0.01 then
		reflected = n * state.speed
	else
		reflected = reflected.Unit * state.speed
	end
	state.velocity = reflected
	state.homeDir = reflected.Unit
	state.homePoint = nil
	state.homeTarget = nil
	state.seekUntilClose = false
end

local function applyImpactAoe(state: ProjectileState, pos: Vector3)
	local aoeR = state.impactAoeRadius
	if not aoeR or aoeR <= 0 then
		return
	end
	showImpactAoe(pos, aoeR, state.color, state.impactFx)
	for _, victim in CombatHelper.overlapCharacters(pos, aoeR, state.owner) do
		if state.hit[victim] then
			continue
		end
		if victim:GetAttribute("LokiUltClone") == true or victim:GetAttribute("LokiDecoy") == true then
			continue
		end
		state.hit[victim] = true
		if CombatHelper.isShielded(victim) then
			-- Shields still block; only damage path (no heal through shield)
			if not (state.shouldHeal and state.shouldHeal(state.owner, victim)) then
				CombatHelper.dealDamage(state.owner, victim, state.impactAoeDamage or state.damage, state.spawnOrigin, "projectile")
			end
			continue
		end
		local prevDamage = state.damage
		state.damage = state.impactAoeDamage or state.damage
		applyProjectileHit(state, victim, pos)
		state.damage = prevDamage
		if state.onHit then
			state.onHit(victim, pos)
		end
	end
end

local function impactAt(state: ProjectileState, pos: Vector3)
	if state.impactAoeRadius and state.impactAoeRadius > 0 then
		applyImpactAoe(state, pos)
	else
		local r = math.clamp(state.radius * 0.4, 1.5, GameConstants.HEX_BLAST_IMPACT_VISUAL)
		if state.impactFx == "photon_blast" then
			VfxHelper.spawnPhotonBlastImpact(pos, r)
		elseif state.impactFx == "photon_explosion" then
			VfxHelper.spawnPhotonExplosionImpact(pos, r)
		elseif state.impactFx == "loki" then
			VfxHelper.spawnLokiBlastImpact(pos, r)
		elseif state.impactFx == "dagger_light" then
			VfxHelper.spawnDaggerLightImpact(pos, r)
		elseif state.impactFx == "psionic" then
			VfxHelper.spawnMarvelGirlPsionicImpact(pos, r, if state.recolorVisual then state.color else nil)
		elseif state.impactFx ~= "none" then
			VfxHelper.spawnBlastImpact(pos, r)
		end
	end
	if state.onImpact then
		state.onImpact(pos, state.hitCharacter)
	end
end

function ProjectileHelper.spawn(origin: Vector3, direction: Vector3, options: ProjectileOptions): BasePart
	local dir = if direction.Magnitude > 0.01 then direction.Unit else Vector3.new(0, 0, -1)
	local color = options.color or VfxHelper.chaosColor()

	local root: BasePart
	local visual: Instance
	local custom = options.customVisual
	if custom and custom:IsA("BasePart") then
		root = custom
		visual = custom
		prepareBoltPart(root)
		root.Name = "HexProjectile"
		if not root.Parent then
			root.Parent = workspace
		end
	elseif custom and custom:IsA("Model") then
		local primary = custom.PrimaryPart or custom:FindFirstChildWhichIsA("BasePart", true)
		if primary and primary:IsA("BasePart") then
			root = primary
			visual = custom
			for _, desc in custom:GetDescendants() do
				if desc:IsA("BasePart") then
					prepareBoltPart(desc)
				end
			end
			if not custom.Parent then
				custom.Parent = workspace
			end
		else
			root, visual = createHexBoltVisual(origin, dir, color, options.boltFolder, options.boltAsset)
		end
	else
		root, visual = createHexBoltVisual(origin, dir, color, options.boltFolder, options.boltAsset)
	end

	local facingOffset = options.facingOffset or CFrame.identity
	-- Asset can declare ProjectileYaw/Pitch/Roll (degrees) for mesh tip alignment
	if typeof(visual:GetAttribute("ProjectileYaw")) == "number"
		or typeof(visual:GetAttribute("ProjectilePitch")) == "number"
		or typeof(visual:GetAttribute("ProjectileRoll")) == "number"
	then
		local yaw = (visual:GetAttribute("ProjectileYaw") :: number?) or 0
		local pitch = (visual:GetAttribute("ProjectilePitch") :: number?) or 0
		local roll = (visual:GetAttribute("ProjectileRoll") :: number?) or 0
		facingOffset = CFrame.Angles(math.rad(pitch), math.rad(yaw), math.rad(roll))
	end
	local baseLook = lookCFrame(origin, dir)
	local tipPart: BasePart? = if visual:IsA("Model") then visual.PrimaryPart elseif visual:IsA("BasePart") then visual else nil
	local tip = visual:FindFirstChild("Tip", true) or visual:FindFirstChild("Forward", true)
	if tip and tip:IsA("Attachment") and tipPart then
		setVisualCFrame(visual, root, baseLook)
		local tipLook = tip.WorldCFrame.LookVector
		if tipLook.Magnitude > 0.01 then
			local from = tipLook.Unit
			local to = dir.Unit
			local axis = from:Cross(to)
			local dot = math.clamp(from:Dot(to), -1, 1)
			local align = CFrame.identity
			if axis.Magnitude > 0.001 then
				align = CFrame.fromAxisAngle(axis.Unit, math.acos(dot))
			elseif dot < 0 then
				local ortho = if math.abs(from:Dot(Vector3.yAxis)) < 0.9 then Vector3.yAxis else Vector3.xAxis
				align = CFrame.fromAxisAngle(from:Cross(ortho).Unit, math.pi)
			end
			local finalCf = CFrame.new(origin) * align * (baseLook - baseLook.Position)
			facingOffset = baseLook:Inverse() * finalCf
		end
	elseif
		(options.boltAsset == "Dagger" or options.boltAsset == "LightDagger" or options.boltAsset == "IceShard")
		and options.facingOffset == nil
		and tipPart
	then
		-- No Tip: aim longest mesh axis along travel
		local size = tipPart.Size
		if size.X >= size.Y and size.X >= size.Z then
			facingOffset = CFrame.Angles(0, math.rad(-90), 0)
		elseif size.Y >= size.X and size.Y >= size.Z then
			facingOffset = CFrame.Angles(math.rad(-90), 0, 0)
		else
			facingOffset = CFrame.Angles(0, math.pi, 0)
		end
	end
	setVisualCFrame(visual, root, lookCFrame(origin, dir) * facingOffset)
	if options.lockWorldRotation then
		local rot = options.lockWorldRotation - options.lockWorldRotation.Position
		setVisualCFrame(visual, root, CFrame.new(origin) * rot)
	end

	if options.recolorVisual == true then
		VfxHelper.tintParticles(visual, color)
	end

	local startSpeed = options.speed
	active[root] = {
		owner = options.owner,
		velocity = dir * startSpeed,
		speed = startSpeed,
		accel = options.accel or 0,
		maxSpeed = options.maxSpeed or startSpeed,
		homeDir = if options.homeDir and options.homeDir.Magnitude > 0.01 then options.homeDir.Unit else nil,
		homePoint = options.homePoint,
		homeTarget = options.homeTarget,
		liveHomeAimAttribute = options.liveHomeAimAttribute,
		homeAfter = options.homeAfter or 0,
		homeTurnScale = options.homeTurnScale or 1,
		seekUntilClose = options.seekUntilClose == true,
		seekCloseDistance = options.seekCloseDistance or 2.2,
		age = 0,
		damage = options.damage,
		radius = options.radius,
		traveled = 0,
		maxDistance = options.maxDistance,
		spawnOrigin = origin,
		ragdollOnHit = options.ragdollOnHit,
		pushOnHit = options.pushOnHit,
		pushSpeed = options.pushSpeed,
		pushUp = options.pushUp,
		impactAoeRadius = options.impactAoeRadius,
		impactAoeDamage = options.impactAoeDamage,
		impactFx = options.impactFx,
		shouldHeal = options.shouldHeal,
		healAmount = options.healAmount,
		ricochetsLeft = math.max(0, options.ricochetMax or 0),
		ricochetSearchRadius = options.ricochetSearchRadius or 35,
		hit = {},
		onHit = options.onHit,
		onImpact = options.onImpact,
		color = color,
		visual = visual,
		facingOffset = facingOffset,
		lockWorldRotation = options.lockWorldRotation,
		deleteAfterFx = options.deleteAfterFx,
		recolorVisual = options.recolorVisual == true,
		keepVisual = options.keepVisual == true,
		impactOnCharacter = options.impactOnCharacter == true,
		hitCharacter = false,
	}

	-- Failsafe only; normal lifetime ends via retireVisual (FX off, then delete)
	if options.keepVisual ~= true then
		local deleteFx = options.deleteAfterFx or GameConstants.HEX_BOLT_DELETE_DELAY
		Debris:AddItem(visual, options.maxDistance / math.max(startSpeed, 1) + GameConstants.HEX_BOLT_FX_DISABLE_DELAY + deleteFx + 4)
	end
	return root
end

function ProjectileHelper.update(dt: number)
	local dtClamped = math.clamp(dt, 0.001, 0.1)
	for part, state in active do
		if not part.Parent or not state.visual.Parent then
			active[part] = nil
			continue
		end

		state.age += dtClamped

		-- Keep seeking a live character body if assigned
		if state.homeTarget and state.homeTarget.Parent then
			local targetRoot = state.homeTarget:FindFirstChild("HumanoidRootPart") :: BasePart?
			if targetRoot then
				state.homePoint = targetRoot.Position
			end
		elseif state.homeTarget then
			state.homeTarget = nil
		end

		-- Live mouse / aim attribute on owner (Lumen Barrage)
		if state.liveHomeAimAttribute then
			local live = state.owner:GetAttribute(state.liveHomeAimAttribute)
			if typeof(live) == "Vector3" then
				state.homePoint = live
				local toLive = live - part.Position
				if toLive.Magnitude > 0.05 then
					state.homeDir = toLive.Unit
				end
			end
		end

		local canHome = state.age >= state.homeAfter
			and (state.homeDir ~= nil or state.homePoint ~= nil)

		if state.accel > 0 then
			if canHome then
				state.speed = math.min(state.maxSpeed, state.speed + state.accel * dtClamped)
			else
				-- Balloon expand: stay relatively slow while fanning out
				state.speed = math.min(state.maxSpeed * 0.28, state.speed + state.accel * 0.12 * dtClamped)
			end
		end

		local dir = if state.velocity.Magnitude > 0.01 then state.velocity.Unit else Vector3.new(0, 0, -1)
		if canHome then
			local desired = state.homeDir
			if state.homePoint then
				local toPoint = state.homePoint - part.Position
				if toPoint.Magnitude > 0.05 then
					desired = toPoint.Unit
				end
			end
			if desired then
				local dist = 24
				if state.homePoint then
					dist = (state.homePoint - part.Position).Magnitude
				end
				local farT = math.clamp((dist - 6) / 58, 0, 1)
				local scale = math.clamp(state.homeTurnScale, 0.2, 1.6)
				local rate = (1.45 * scale) * (1 - 0.8 * farT)
				if state.accel > 0 then
					local blend = math.clamp((state.age - state.homeAfter) / 0.55, 0, 1)
					rate *= 0.35 + blend * 0.65
				end
				local turn = 1 - math.exp(-rate * dtClamped)
				dir = dir:Lerp(desired, math.clamp(turn, 0, 1))
				if dir.Magnitude > 0.01 then
					dir = dir.Unit
				end
			end
		end
		state.velocity = dir * state.speed

		local step = state.velocity * dtClamped
		local nextPos = part.Position + step
		state.traveled += step.Magnitude

		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { state.owner, state.visual }
		local hit = workspace:Raycast(part.Position, step, params)
		if hit then
			-- Ignore character parts for wall ricochet — character hits use overlap
			local hitChar = CombatHelper.getCharacterFromPart(hit.Instance)
			if hitChar then
				hit = nil
			else
				nextPos = hit.Position - state.velocity.Unit * 0.15
			end
		end
		local look = if state.velocity.Magnitude > 0.01 then state.velocity.Unit else Vector3.new(0, 0, -1)
		setVisualCFrame(state.visual, part, visualTravelCFrame(state, nextPos, look))
		local shell = part:FindFirstChild("HexShell")
		if shell and shell:IsA("BasePart") then
			shell.CFrame = part.CFrame
		end

		-- Impact / callbacks use bolt tip, or exact raycast contact if we hit geometry
		local endPos = if hit then hit.Position else getBoltEndPosition(state.visual, part, look)

		local victims = CombatHelper.overlapCharacters(nextPos, state.radius, state.owner)
		local hitSomeone = false
		local ricocheted = false
		for _, victim in victims do
			if state.hit[victim] then
				continue
			end
			-- Loki ult/decoy clones: never damage each other or friendly clones
			if
				victim:GetAttribute("LokiUltClone") == true
				or victim:GetAttribute("LokiDecoy") == true
			then
				continue
			end
			if CombatHelper.isShielded(victim) then
				if not state.hit[victim] then
					state.hit[victim] = true
					if not (state.shouldHeal and state.shouldHeal(state.owner, victim)) then
						CombatHelper.dealDamage(state.owner, victim, state.damage, endPos, "projectile")
					end
				end
				-- Marvel Girl barrier absorbs (damage only); Wanda still reflects
				if victim:GetAttribute(GameConstants.MG_BARRIER_ATTRIBUTE) == true then
					hitSomeone = true
					break
				end
				local previousOwner = state.owner
				redirectOffShield(state, part, victim, previousOwner, endPos)
				continue
			end
			state.hit[victim] = true
			local contact = contactOnCharacter(part.Position, step, victim, nextPos)
			endPos = contact
			applyProjectileHit(state, victim, state.spawnOrigin)
			if state.onHit then
				state.onHit(victim, contact)
			end

			if state.impactOnCharacter then
				state.hitCharacter = true
				hitSomeone = true
				break
			end

			if state.ricochetsLeft > 0 then
				state.ricochetsLeft -= 1
				local nextTarget = findRicochetTarget(nextPos, state.owner, state.hit, state.ricochetSearchRadius)
				if nextTarget then
					local tRoot = nextTarget:FindFirstChild("HumanoidRootPart") :: BasePart?
					if tRoot then
						redirectToward(state, part, tRoot.Position)
						state.homeTarget = nextTarget
						state.homePoint = tRoot.Position
						ricocheted = true
						VfxHelper.spawnBurstSparks(nextPos, state.color, 5)
						break
					end
				end
				-- No next target: stop after this hit
				hitSomeone = true
				break
			elseif state.seekUntilClose then
				-- Keep flying into the body / aim so the bolt visually connects
				state.homeTarget = victim
				local vRoot = victim:FindFirstChild("HumanoidRootPart") :: BasePart?
				if vRoot then
					state.homePoint = vRoot.Position
				end
			else
				hitSomeone = true
				break
			end
		end

		if ricocheted then
			-- Keep flying after redirect
			continue
		end

		-- Seek bolts finish when close to the body / aim point
		if state.seekUntilClose and state.homePoint then
			local distToHome = (nextPos - state.homePoint).Magnitude
			if distToHome <= state.seekCloseDistance then
				local focus = state.homeTarget
				if focus and focus.Parent and not state.hit[focus] and not CombatHelper.isShielded(focus) then
					state.hit[focus] = true
					applyProjectileHit(state, focus, state.spawnOrigin)
					if state.onHit then
						state.onHit(focus, state.homePoint)
					end
				end
				hitSomeone = true
				endPos = state.homePoint
			end
		end

		if hitSomeone then
			impactAt(state, endPos)
			if state.keepVisual then
				active[part] = nil
			else
				retireVisual(state.visual, part, state.deleteAfterFx)
				active[part] = nil
			end
			continue
		end

		if state.traveled >= state.maxDistance then
			impactAt(state, endPos)
			if state.keepVisual then
				active[part] = nil
			else
				retireVisual(state.visual, part, state.deleteAfterFx)
				active[part] = nil
			end
		elseif hit then
			-- Surface hit: ricochet off walls if charges remain
			if state.ricochetsLeft > 0 then
				state.ricochetsLeft -= 1
				reflectVelocity(state, hit.Normal)
				setVisualCFrame(
					state.visual,
					part,
					visualTravelCFrame(state, nextPos, state.velocity.Unit)
				)
				VfxHelper.spawnBurstSparks(hit.Position, state.color, 4)
			else
				applyAreaForcefieldHit(hit.Instance, state.damage)
				impactAt(state, endPos)
				if state.keepVisual then
					active[part] = nil
				else
					retireVisual(state.visual, part, state.deleteAfterFx)
					active[part] = nil
				end
			end
		end
	end
end

function ProjectileHelper.deflectNearShield(shieldCharacter: Model, radius: number)
	local root = shieldCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	for part, state in active do
		if not part.Parent then
			continue
		end
		if (part.Position - root.Position).Magnitude > radius then
			continue
		end
		if state.owner == shieldCharacter then
			continue
		end

		-- First contact: apply shield damage + partial shield VFX immediately
		local previousOwner = state.owner
		if not state.hit[shieldCharacter] then
			state.hit[shieldCharacter] = true
			CombatHelper.dealDamage(previousOwner, shieldCharacter, state.damage, part.Position, "projectile")
		end

		redirectOffShield(state, part, shieldCharacter, previousOwner, part.Position)
	end
end

return ProjectileHelper
