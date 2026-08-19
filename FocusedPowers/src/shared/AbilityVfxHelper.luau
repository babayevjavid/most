--!strict
--[[
	Generic ability VFX: expanding spheres, ground rings, color flashes.
]]

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AbilityVfxHelper = {}

local ParticleHelper = require(script.Parent:WaitForChild("ParticleHelper"))

function AbilityVfxHelper.spawnExpandingSphere(
	position: Vector3,
	color: Color3,
	startRadius: number,
	endRadius: number,
	duration: number
)
	local anchor = Instance.new("Part")
	anchor.Name = "AbilityVfxSphere"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = workspace

	local core = Instance.new("Part")
	core.Shape = Enum.PartType.Ball
	core.Material = Enum.Material.Neon
	core.Color = color
	core.Anchored = true
	core.CanCollide = false
	core.CanQuery = false
	core.CanTouch = false
	core.Size = Vector3.new(startRadius, startRadius, startRadius)
	core.CFrame = CFrame.new(position)
	core.Parent = anchor

	local endSize = Vector3.new(endRadius * 2, endRadius * 2, endRadius * 2)
	TweenService:Create(
		core,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = endSize, Transparency = 1 }
	):Play()

	Debris:AddItem(anchor, duration + 0.1)
end

function AbilityVfxHelper.spawnGroundRing(
	position: Vector3,
	color: Color3,
	startRadius: number,
	endRadius: number,
	duration: number
)
	local anchor = Instance.new("Part")
	anchor.Name = "AbilityVfxRing"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = workspace

	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Size = Vector3.new(0.15, startRadius * 2, startRadius * 2)
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = anchor

	TweenService:Create(
		ring,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Size = Vector3.new(0.15, endRadius * 2, endRadius * 2),
			Transparency = 1,
		}
	):Play()

	Debris:AddItem(anchor, duration + 0.1)
end

function AbilityVfxHelper.spawnProjectilePart(
	cframe: CFrame,
	color: Color3,
	size: Vector3
): BasePart
	local part = Instance.new("Part")
	part.Name = "AbilityProjectile"
	part.Size = size
	part.Material = Enum.Material.Neon
	part.Color = color
	part.CanCollide = false
	part.CanQuery = true
	part.CanTouch = true
	part.Massless = true
	part.Anchored = false
	part.CFrame = cframe
	part.Parent = workspace
	return part
end

function AbilityVfxHelper.spawnMagneticRingStack(
	spawnCF: CFrame,
	color: Color3,
	ringCount: number,
	ringSpacing: number,
	outerRadius: number,
	thickness: number,
	innerRadius: number?,
	segments: number?
): BasePart
	local holeRadius = innerRadius or outerRadius * 0.38
	local segmentCount = math.max(8, segments or 14)

	local leader = Instance.new("Part")
	leader.Name = "MagneticPulseLeader"
	leader.Size = Vector3.new(outerRadius * 0.5, outerRadius * 0.5, thickness)
	leader.Transparency = 1
	leader.CanCollide = false
	leader.CanQuery = true
	leader.CanTouch = true
	leader.Massless = true
	leader.Anchored = false
	leader.CFrame = spawnCF
	leader.Parent = workspace

	local ringStyles = {
		{ radiusScale = 1.0, transparency = 0.52, hueShift = 0 },
		{ radiusScale = 0.86, transparency = 0.44, hueShift = 0.06 },
		{ radiusScale = 1.14, transparency = 0.38, hueShift = -0.04 },
		{ radiusScale = 0.94, transparency = 0.48, hueShift = 0.1 },
		{ radiusScale = 1.06, transparency = 0.34, hueShift = -0.08 },
	}

	local function shiftColor(base: Color3, hueShift: number): Color3
		local h, s, v = base:ToHSV()
		return Color3.fromHSV((h + hueShift) % 1, math.clamp(s * 1.05, 0, 1), math.clamp(v * 1.08, 0, 1))
	end

	local function attachDonutRing(ringIndex: number, ringCF: CFrame, style: { radiusScale: number, transparency: number, hueShift: number })
		local scaledOuter = outerRadius * style.radiusScale
		local scaledInner = holeRadius * style.radiusScale
		local midRadius = (scaledOuter + scaledInner) * 0.5
		local tubeRadius = thickness * (0.85 + (ringIndex % 3) * 0.08)
		local arcLength = math.max(0.12, (scaledOuter - scaledInner) * 0.92)
		local ringColor = shiftColor(color, style.hueShift)

		for seg = 0, segmentCount - 1 do
			local angle = (seg / segmentCount) * math.pi * 2
			local x = math.cos(angle) * midRadius
			local y = math.sin(angle) * midRadius
			local tangent = Vector3.new(-math.sin(angle), math.cos(angle), 0)
			local segPos = Vector3.new(x, y, 0)

			local segment = Instance.new("Part")
			segment.Name = "MagneticPulseDonutSegment"
			segment.Shape = Enum.PartType.Cylinder
			segment.Size = Vector3.new(arcLength, tubeRadius * 2, tubeRadius * 2)
			segment.Material = Enum.Material.Neon
			segment.Color = ringColor
			segment.Transparency = style.transparency
			segment.CanCollide = false
			segment.CanQuery = false
			segment.CanTouch = false
			segment.Massless = true
			segment.Anchored = false
			segment.CFrame = ringCF
				* CFrame.lookAt(segPos, segPos + tangent)
				* CFrame.Angles(0, math.rad(90), 0)
			segment.Parent = workspace

			local weld = Instance.new("WeldConstraint")
			weld.Part0 = leader
			weld.Part1 = segment
			weld.Parent = leader
		end
	end

	for i = 1, ringCount do
		local style = ringStyles[((i - 1) % #ringStyles) + 1]
		local ringCF = spawnCF * CFrame.new(0, 0, -(i - 1) * ringSpacing)
		attachDonutRing(i, ringCF, style)
	end

	return leader
end

local function attachSunspotBodyParticles(parent: BasePart)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local sunspot = if assets then assets:FindFirstChild("Sunspot") else nil
	local bodyParticles = if sunspot then sunspot:FindFirstChild("BodyParticles") else nil
	if not bodyParticles then
		return
	end

	for _, childName in { "SolarDots", "Dots" } do
		local template = bodyParticles:FindFirstChild(childName)
		if template then
			ParticleHelper.cloneTemplate(template, parent)
		end
	end
end

--[[ Same collision leader as magnetic pulse rings; visual = solar dot blast. ]]
function AbilityVfxHelper.spawnSolarFlareBolt(
	spawnCF: CFrame,
	outerRadius: number,
	thickness: number,
	blastColor: Color3
): BasePart
	local leader = Instance.new("Part")
	leader.Name = "SolarFlareLeader"
	leader.Size = Vector3.new(outerRadius * 0.5, outerRadius * 0.5, thickness)
	leader.Transparency = 1
	leader.CanCollide = false
	leader.CanQuery = true
	leader.CanTouch = true
	leader.Massless = true
	leader.Anchored = false
	leader.CFrame = spawnCF
	leader.Parent = workspace

	local core = Instance.new("Part")
	core.Name = "SolarFlareCore"
	core.Shape = Enum.PartType.Ball
	core.Material = Enum.Material.Neon
	core.Color = blastColor
	core.Transparency = 0.42
	core.Size = Vector3.new(outerRadius * 1.6, outerRadius * 1.6, outerRadius * 1.6)
	core.CanCollide = false
	core.CanQuery = false
	core.CanTouch = false
	core.Massless = true
	core.Anchored = false
	core.CFrame = spawnCF
	core.Parent = workspace

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = leader
	weld.Part1 = core
	weld.Parent = core

	attachSunspotBodyParticles(leader)
	attachSunspotBodyParticles(core)

	TweenService:Create(
		core,
		TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Transparency = 0.72, Size = core.Size * 1.35 }
	):Play()

	return leader
end

function AbilityVfxHelper.spawnBlackSunOrb(cframe: CFrame, diameter: number): BasePart
	local orb = Instance.new("Part")
	orb.Name = "BlackSunOrb"
	orb.Shape = Enum.PartType.Ball
	orb.Material = Enum.Material.Neon
	orb.Color = Color3.fromRGB(8, 8, 12)
	orb.Transparency = 0
	orb.Size = Vector3.new(diameter, diameter, diameter)
	orb.CanCollide = false
	orb.CanQuery = false
	orb.CanTouch = true
	orb.Massless = true
	orb.Anchored = true
	orb.CFrame = cframe
	orb.Parent = workspace
	attachSunspotBodyParticles(orb)
	return orb
end

function AbilityVfxHelper.setBlackSunOrbDiameter(orb: BasePart, diameter: number)
	orb.Size = Vector3.new(diameter, diameter, diameter)
end

function AbilityVfxHelper.fadeOutBlackSunOrb(orb: BasePart, fadeDuration: number?)
	if not orb.Parent then
		return
	end
	local duration = fadeDuration or 0.6
	ParticleHelper.disableDescendantsAndScheduleDestroy(orb)
	local startSize = orb.Size
	TweenService:Create(
		orb,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Transparency = 1,
			Size = startSize * 0.3,
		}
	):Play()
	Debris:AddItem(orb, duration + 0.2)
end

function AbilityVfxHelper.spawnBlackSunDetonation(position: Vector3, radius: number, duration: number)
	AbilityVfxHelper.spawnExpandingSphere(
		position,
		Color3.fromRGB(18, 16, 28),
		math.max(1.5, radius * 0.2),
		radius,
		duration
	)
	AbilityVfxHelper.spawnExpandingSphere(
		position,
		Color3.fromRGB(255, 180, 50),
		math.max(1, radius * 0.12),
		radius * 0.85,
		duration * 0.85
	)
end

function AbilityVfxHelper.spawnFireRingStack(
	spawnCF: CFrame,
	ringCount: number,
	ringSpacing: number,
	outerRadius: number,
	thickness: number,
	innerRadius: number?,
	segments: number?
): BasePart
	local fireCore = Color3.fromRGB(255, 120, 30)
	local fireHot = Color3.fromRGB(255, 200, 60)
	local leader = AbilityVfxHelper.spawnMagneticRingStack(
		spawnCF,
		fireCore,
		ringCount,
		ringSpacing,
		outerRadius,
		thickness,
		innerRadius,
		segments
	)
	leader.Name = "SolarFlareLeader"

	for _, child in leader:GetDescendants() do
		if child:IsA("BasePart") then
			child.Material = Enum.Material.Neon
			local h, s, v = child.Color:ToHSV()
			child.Color = Color3.fromHSV(h * 0.06, math.clamp(s * 1.1, 0, 1), math.clamp(v * 1.05, 0, 1))
		end
	end

	local flameAtt = Instance.new("Attachment")
	flameAtt.Name = "SolarFlareFlame"
	flameAtt.Parent = leader

	local flame = Instance.new("ParticleEmitter")
	flame.Name = "SolarFlareFire"
	flame.Texture = "rbxasset://textures/particles/fire_main.dds"
	flame.Color = ColorSequence.new(fireHot, fireCore)
	flame.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.8),
		NumberSequenceKeypoint.new(0.5, 1.4),
		NumberSequenceKeypoint.new(1, 0.2),
	})
	flame.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	flame.Lifetime = NumberRange.new(0.25, 0.5)
	flame.Rate = 80
	flame.Speed = NumberRange.new(4, 10)
	flame.SpreadAngle = Vector2.new(18, 18)
	flame.LightEmission = 1
	flame.Parent = flameAtt
	ParticleHelper.enableAndEmit(flame)

	local ember = Instance.new("ParticleEmitter")
	ember.Name = "SolarFlareEmbers"
	ember.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	ember.Color = ColorSequence.new(fireHot)
	ember.Size = NumberSequence.new(0.25, 0.05)
	ember.Transparency = NumberSequence.new(0.2, 1)
	ember.Lifetime = NumberRange.new(0.3, 0.7)
	ember.Rate = 35
	ember.Speed = NumberRange.new(6, 14)
	ember.SpreadAngle = Vector2.new(30, 30)
	ember.LightEmission = 1
	ember.Parent = flameAtt
	ParticleHelper.enableAndEmit(ember)

	return leader
end

function AbilityVfxHelper.spawnDirectionalBurst(
	origin: Vector3,
	direction: Vector3,
	color: Color3,
	length: number,
	duration: number
)
	local dir = if direction.Magnitude > 0.01 then direction.Unit else Vector3.new(0, 0, -1)
	local mid = origin + dir * (length * 0.5)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(mid, mid + dir)
	anchor.Parent = workspace

	local slash = Instance.new("Part")
	slash.Material = Enum.Material.Neon
	slash.Color = color
	slash.Anchored = true
	slash.CanCollide = false
	slash.CanQuery = false
	slash.CanTouch = false
	slash.Size = Vector3.new(0.3, 2.5, length)
	slash.CFrame = anchor.CFrame
	slash.Parent = anchor

	TweenService:Create(
		slash,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Transparency = 1, Size = Vector3.new(0.1, 3.5, length * 1.2) }
	):Play()
	Debris:AddItem(anchor, duration + 0.1)
end

function AbilityVfxHelper.spawnCharacterAura(
	character: Model,
	color: Color3,
	radius: number,
	duration: number
)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local att = Instance.new("Attachment")
	att.Name = "AbilityAuraAttachment"
	att.Parent = root

	local sphere = Instance.new("Part")
	sphere.Shape = Enum.PartType.Ball
	sphere.Material = Enum.Material.ForceField
	sphere.Color = color
	sphere.Anchored = false
	sphere.CanCollide = false
	sphere.CanQuery = false
	sphere.CanTouch = false
	sphere.Massless = true
	sphere.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
	sphere.CFrame = root.CFrame
	sphere.Parent = workspace

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = sphere
	weld.Parent = sphere

	TweenService:Create(
		sphere,
		TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Transparency = 0.55 }
	):Play()

	task.delay(duration, function()
		if sphere.Parent then
			sphere:Destroy()
		end
		if att.Parent then
			att:Destroy()
		end
	end)
end

function AbilityVfxHelper.spawnPersistentField(
	position: Vector3,
	radius: number,
	color: Color3,
	duration: number
): BasePart
	local field = Instance.new("Part")
	field.Name = "AbilityField"
	field.Shape = Enum.PartType.Cylinder
	field.Material = Enum.Material.Neon
	field.Color = color
	field.Anchored = true
	field.CanCollide = false
	field.CanQuery = true
	field.CanTouch = false
	field.Transparency = 0.55
	field.Size = Vector3.new(0.5, radius * 2, radius * 2)
	field.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	field.Parent = workspace
	Debris:AddItem(field, duration)
	return field
end

function AbilityVfxHelper.spawnSpawnedWall(
	cframe: CFrame,
	size: Vector3,
	color: Color3,
	lifetime: number
): BasePart
	local wall = Instance.new("Part")
	wall.Name = "AbilityWall"
	wall.Material = Enum.Material.Glass
	wall.Color = color
	wall.Anchored = true
	wall.CanCollide = true
	wall.CanQuery = true
	wall.CanTouch = true
	wall.Transparency = 0.35
	wall.Size = size
	wall.CFrame = cframe
	wall.Parent = workspace
	Debris:AddItem(wall, lifetime)
	return wall
end

return AbilityVfxHelper
