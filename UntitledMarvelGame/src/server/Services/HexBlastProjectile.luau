--!strict
--[[
	Wanda Hex Blast — uses Assets.WandaMaximoff projectile template (thrown asset), NewMarvel flight/VFX.
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local AbilityConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityConstants"))
local ProjectileFlight = require(script.Parent.ProjectileFlight)

local CombatService = require(script.Parent.CombatService)
local PlayerStateService = require(script.Parent.PlayerStateService)
local WandaHandParticlesService = require(script.Parent.WandaHandParticlesService)

local C = AbilityConstants

local WANDA_ACCENT = Color3.fromRGB(220, 50, 80)
local BLAST_EMIT_COUNT = 15
local VISUAL_COLLISION_GROUP = "WandaHexVisuals"

local function setupVisualGroup()
	pcall(function()
		local PhysicsService = game:GetService("PhysicsService")
		PhysicsService:RegisterCollisionGroup(VISUAL_COLLISION_GROUP)
		PhysicsService:CollisionGroupSetCollidable(VISUAL_COLLISION_GROUP, "Default", false)
	end)
end
setupVisualGroup()

local WANDA_PROJECTILE_NAMES = { "Projectile", "HexBlast", "HexBolt", "Blast", "ChaosBlast" }

local function getOverlapParams(char: Model): OverlapParams
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	return params
end

local function findWandaChild(folder: Instance, names: { string }): Instance?
	for _, name in names do
		local found = folder:FindFirstChild(name)
		if found then
			return found
		end
	end
	return nil
end

local function getHexTemplate(): (Instance?, boolean)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local wanda = assets and assets:FindFirstChild("WandaMaximoff")
	if wanda then
		local tpl = findWandaChild(wanda, WANDA_PROJECTILE_NAMES)
		if tpl then
			return tpl, true
		end
	end
	local sw = assets and assets:FindFirstChild("ScarletWitch")
	if sw then
		local classic = sw:FindFirstChild("ClassicScarletWitch")
		local tpl = findWandaChild(classic or sw, { "HexBlast", "HexBolt" })
		if tpl then
			return tpl, false
		end
		return findWandaChild(sw, { "HexBolt" }), false
	end
	return nil, false
end

local function getImpactTemplate(): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local wanda = assets and assets:FindFirstChild("WandaMaximoff")
	if wanda then
		local ae = wanda:FindFirstChild("BlastAE") or wanda:FindFirstChild("ImpactAE")
		if ae then
			return ae
		end
	end
	local sw = assets and assets:FindFirstChild("ScarletWitch")
	local classic = sw and sw:FindFirstChild("ClassicScarletWitch")
	return classic and classic:FindFirstChild("BlastAE")
end

local function getHandPart(char: Model, useRight: boolean): BasePart?
	local name = if useRight then "RightHand" else "LeftHand"
	local fallback = if useRight then "Right Arm" else "Left Arm"
	return (char:FindFirstChild(name) or char:FindFirstChild(fallback)) :: BasePart?
end

local function prepareProjectileParts(projectile: Instance)
	for _, desc in projectile:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.Anchored = true
			desc.CanCollide = false
			desc.CanTouch = false
			desc.CanQuery = false
			desc.CollisionGroup = VISUAL_COLLISION_GROUP
		end
	end
end

local function enableProjectileVfx(projectile: Instance, part: BasePart, fromWandaAsset: boolean, accent: Color3)
	local emitCount = if fromWandaAsset then BLAST_EMIT_COUNT else 8
	local hasEmitter = false

	for _, desc in projectile:GetDescendants() do
		if desc:IsA("ParticleEmitter") then
			hasEmitter = true
			if not fromWandaAsset then
				desc.Color = ColorSequence.new(accent)
			end
			desc.Enabled = true
			desc:Emit(emitCount)
		elseif desc:IsA("Trail") then
			desc.Enabled = true
		elseif desc:IsA("Beam") then
			desc.Enabled = true
		elseif not fromWandaAsset and desc:IsA("BasePart") then
			desc.Color = accent
			desc.Material = Enum.Material.Neon
		end
	end

	if fromWandaAsset then
		for _, desc in projectile:GetDescendants() do
			local par = desc.Parent
			if desc:IsA("ParticleEmitter") and par and par:IsA("Attachment") then
				desc.Enabled = true
				desc:Emit(emitCount)
			end
		end
	end

	if not hasEmitter then
		local inner = Instance.new("ParticleEmitter")
		inner.Name = "HexBlastInner"
		inner.Rate = 0
		inner.Lifetime = NumberRange.new(0.25, 0.55)
		inner.Speed = NumberRange.new(0, 2)
		inner.SpreadAngle = Vector2.new(180, 180)
		inner.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.55),
			NumberSequenceKeypoint.new(1, 0),
		})
		inner.Color = ColorSequence.new(accent)
		inner.LightEmission = 1
		inner.Texture = "rbxasset://textures/particles/smoke_main.dds"
		inner.Parent = part
		inner:Emit(emitCount)
	end

	local glow = part:FindFirstChild("HexBlastGlow")
	if not glow then
		glow = Instance.new("PointLight")
		glow.Name = "HexBlastGlow"
		glow.Color = accent
		glow.Brightness = if fromWandaAsset then 2.4 else 1.6
		glow.Range = if fromWandaAsset then 14 else 10
		glow.Parent = part
	end
end

local function spawnVisual(spawnPos: Vector3): (Instance?, BasePart?, Model?, boolean)
	local template, fromWanda = getHexTemplate()
	if template then
		local projectile = template:Clone()
		projectile.Name = "HexBlastProjectile"
		local part: BasePart?
		local model: Model? = nil

		if projectile:IsA("Model") then
			model = projectile
			part = projectile.PrimaryPart or projectile:FindFirstChildWhichIsA("BasePart")
			if part and not projectile.PrimaryPart then
				projectile.PrimaryPart = part
			end
			if part then
				local lookCf = CFrame.lookAt(spawnPos, spawnPos + Vector3.new(0, 0, -1))
				projectile:PivotTo(lookCf)
			end
		elseif projectile:IsA("BasePart") then
			part = projectile
			part.CFrame = CFrame.new(spawnPos)
		else
			part = projectile:FindFirstChildWhichIsA("BasePart", true)
			if part then
				part.CFrame = CFrame.new(spawnPos)
			end
		end

		if not part then
			projectile:Destroy()
			return nil, nil, nil, fromWanda
		end

		prepareProjectileParts(projectile)
		enableProjectileVfx(projectile, part, fromWanda, WANDA_ACCENT)
		projectile.Parent = workspace
		return projectile, part, model, fromWanda
	end

	local part = Instance.new("Part")
	part.Name = "HexBlastProjectile"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(1.2, 1.2, 1.2)
	part.Material = Enum.Material.Neon
	part.Color = WANDA_ACCENT
	part.Transparency = 0.05
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CFrame = CFrame.new(spawnPos)
	part.CollisionGroup = VISUAL_COLLISION_GROUP
	part.Parent = workspace

	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 28
	emitter.Lifetime = NumberRange.new(0.2, 0.45)
	emitter.Speed = NumberRange.new(1, 4)
	emitter.SpreadAngle = Vector2.new(30, 30)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Color = ColorSequence.new(WANDA_ACCENT)
	emitter.LightEmission = 1
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Parent = part
	emitter:Emit(12)

	return part, part, nil, false
end

local function spawnImpactVfx(impactPos: Vector3)
	local tpl = getImpactTemplate()
	if not tpl then
		return
	end

	local host = Instance.new("Part")
	host.Name = "HexBlastImpactHost"
	host.Size = Vector3.new(0.1, 0.1, 0.1)
	host.Transparency = 1
	host.Anchored = true
	host.CanCollide = false
	host.CanQuery = false
	host.CanTouch = false
	host.CFrame = CFrame.new(impactPos)
	host.Parent = workspace

	local attach = Instance.new("Attachment")
	attach.Parent = host

	local function emitFrom(inst: Instance)
		if inst:IsA("ParticleEmitter") then
			local em = inst:Clone()
			em.Parent = attach
			em.Enabled = true
			em:Emit(BLAST_EMIT_COUNT)
		else
			for _, d in inst:GetDescendants() do
				if d:IsA("ParticleEmitter") then
					local em = d:Clone()
					em.Parent = attach
					em.Enabled = true
					em:Emit(BLAST_EMIT_COUNT)
				end
			end
		end
	end

	emitFrom(tpl)
	Debris:AddItem(host, 2)
end

local function doImpact(
	projectile: Instance,
	part: BasePart,
	char: Model,
	plr: Player,
	impactPos: Vector3,
	damage: number
)
	for _, desc in projectile:GetDescendants() do
		if desc:IsA("ParticleEmitter") then
			desc.Enabled = false
			desc.Rate = 0
		elseif desc:IsA("Trail") then
			desc.Enabled = false
		elseif desc:IsA("Beam") then
			desc.Enabled = false
		end
	end

	spawnImpactVfx(impactPos)

	local overlap = getOverlapParams(char)
	local parts = workspace:GetPartBoundsInRadius(impactPos, C.HEX_BLAST_HIT_RADIUS, overlap)
	local hitModels: { [Model]: boolean } = {}
	local heroId = PlayerStateService.get(plr).HeroId

	for _, hitPart in parts do
		local model = hitPart:FindFirstAncestorOfClass("Model")
		if not model or model == char or hitModels[model] then
			continue
		end
		hitModels[model] = true
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			local finalDamage = CombatService.computeDamage(plr, heroId, damage)
			humanoid:TakeDamage(finalDamage)
		end
	end

	for _, desc in projectile:GetDescendants() do
		if desc:IsA("BasePart") and desc.Transparency < 0.99 then
			TweenService:Create(desc, TweenInfo.new(0.25), { Transparency = 1 }):Play()
		end
	end
	if part.Transparency < 0.99 then
		TweenService:Create(part, TweenInfo.new(0.25), { Transparency = 1 }):Play()
	end
	Debris:AddItem(projectile, 1.5)
end

local hexNextRight: { [Player]: boolean } = {}

local HexBlastProjectile = {}

function HexBlastProjectile.fire(
	plr: Player,
	char: Model,
	aimDirection: Vector3,
	steerToken: string?,
	targetPos: Vector3?
)
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	local useRight = hexNextRight[plr] ~= false
	hexNextRight[plr] = not useRight
	local hand = getHandPart(char, useRight)
	local spawnPos = if hand then hand.Position else (root.Position + Vector3.new(0, 1, 0))

	if hand then
		WandaHandParticlesService.ensure(char)
		WandaHandParticlesService.emit(char, BLAST_EMIT_COUNT)
	end

	local dir = if aimDirection.Magnitude > 0.01 then aimDirection.Unit else root.CFrame.LookVector
	local impactPos = targetPos or (spawnPos + dir * C.HEX_BLAST_RANGE)

	local projectile, part, model = spawnVisual(spawnPos)
	if not projectile or not part then
		return
	end

	if steerToken and steerToken ~= "" then
		ProjectileFlight.registerSteerToken(steerToken, plr.UserId, impactPos)
	end

	ProjectileFlight.runProjectileFlight({
		part = part,
		projectileModel = model,
		spawnPos = spawnPos,
		initialDir = (impactPos - spawnPos).Unit,
		maxRange = C.HEX_BLAST_RANGE,
		speed = C.HEX_BLAST_SPEED,
		casterChar = char,
		steerToken = steerToken,
		curveArcHeight = 0,
		excludeInstances = { char, projectile },
		faceMovement = true,
		spinRadiansPerSec = math.rad(420),
		onStepHit = function(_hitPos: Vector3, hitPart: BasePart?)
			if not hitPart then
				return false
			end
			local hitModel = hitPart:FindFirstAncestorOfClass("Model")
			if not hitModel or hitModel == char then
				return false
			end
			return true
		end,
		onEnd = function(endPos: Vector3)
			doImpact(projectile, part, char, plr, endPos, C.HEX_BLAST_DAMAGE)
		end,
	})
end

return HexBlastProjectile
