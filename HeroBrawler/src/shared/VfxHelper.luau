--!strict

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local VfxHelper = {}

-- Pale glass / psychic (Monet) — translucent, not saturated purple
local PSYCHIC = Color3.fromRGB(220, 235, 255)

function VfxHelper.psychicColor(): Color3
	return PSYCHIC
end

function VfxHelper.spawnPulseRing(origin: Vector3, radius: number, color: Color3, duration: number?)
	local ring = Instance.new("Part")
	ring.Name = "PulseRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.12, radius * 2, radius * 2)
	ring.CFrame = CFrame.new(origin) * CFrame.Angles(0, 0, math.rad(90))
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Material = Enum.Material.ForceField
	ring.Color = color
	ring.Transparency = 0.55
	ring.Parent = workspace

	local life = duration or 0.45
	TweenService:Create(ring, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.06, radius * 4, radius * 4),
		Transparency = 1,
	}):Play()
	Debris:AddItem(ring, life + 0.05)
end

function VfxHelper.spawnBeamLine(startPos: Vector3, endPos: Vector3, color: Color3, thickness: number?)
	local delta = endPos - startPos
	local length = delta.Magnitude
	if length < 0.1 then
		return
	end
	local beam = Instance.new("Part")
	beam.Name = "PsionicBeam"
	beam.Size = Vector3.new(thickness or 0.35, thickness or 0.35, length)
	beam.CFrame = CFrame.lookAt(startPos + delta * 0.5, endPos)
	beam.Anchored = true
	beam.CanCollide = false
	beam.Material = Enum.Material.ForceField
	beam.Color = color
	beam.Transparency = 0.45
	beam.Parent = workspace
	Debris:AddItem(beam, 0.25)
end

function VfxHelper.spawnTrail(root: BasePart, color: Color3, lifetime: number)
	local trail = Instance.new("Part")
	trail.Name = "AbilityTrail"
	trail.Size = Vector3.new(1.2, 0.2, 1.2)
	trail.CFrame = root.CFrame
	trail.Anchored = true
	trail.CanCollide = false
	trail.Material = Enum.Material.ForceField
	trail.Color = color
	trail.Transparency = 0.65
	trail.Parent = workspace
	TweenService:Create(trail, TweenInfo.new(lifetime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1,
		Size = Vector3.new(0.2, 0.05, 0.2),
	}):Play()
	Debris:AddItem(trail, lifetime + 0.05)
end

function VfxHelper.spawnBurstSparks(origin: Vector3, color: Color3, count: number?)
	local n = count or 8
	for i = 1, n do
		local spark = Instance.new("Part")
		spark.Size = Vector3.new(0.25, 0.25, 0.25)
		spark.Shape = Enum.PartType.Ball
		spark.Material = Enum.Material.ForceField
		spark.Color = color
		spark.Transparency = 0.4
		spark.Anchored = true
		spark.CanCollide = false
		local angle = (i / n) * math.pi * 2
		spark.Position = origin + Vector3.new(math.cos(angle) * 2, 0.6, math.sin(angle) * 2)
		spark.Parent = workspace
		TweenService:Create(spark, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = spark.Position + Vector3.new(math.cos(angle) * 5, 2, math.sin(angle) * 5),
			Transparency = 1,
		}):Play()
		Debris:AddItem(spark, 0.4)
	end
end

function VfxHelper.emitPlaceholder(parent: Instance, color: Color3, name: string)
	if parent:IsA("BasePart") then
		VfxHelper.spawnTrail(parent, color, 0.3)
	else
		VfxHelper.spawnBurstSparks(Vector3.new(0, 5, 0), color, 4)
	end
end

function VfxHelper.pulseAbility(character: Model, abilityId: string)
	character:SetAttribute("MonetVfxPulse", abilityId)
	task.delay(0.05, function()
		if character.Parent then
			character:SetAttribute("MonetVfxPulse", nil)
		end
	end)
end

return VfxHelper
