local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("Theme"))
local Util = require(Shared:WaitForChild("Util"))

local DecorService = {}

local decorFolder: Folder

local STATION_POSITIONS = {
	Vector3.new(-63, 0.5, -42),
	Vector3.new(63, 0.5, -42),
	Vector3.new(-63, 0.5, 42),
	Vector3.new(63, 0.5, 42),
	Vector3.new(0, 0.5, -78),
	Vector3.new(-93, 0.5, 0),
	Vector3.new(93, 0.5, 0),
	Vector3.new(0, 0.5, 78),
	Vector3.new(-36, 0.5, 0),
	Vector3.new(36, 0.5, 0),
}

local PERIMETER_RADIUS = 110
local MAP_SCATTER_RADIUS = 130

local function addGlow(part: BasePart, color: Color3, brightness: number, range: number)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = brightness * 0.35
	light.Range = range * 0.7
	light.Parent = part
	return light
end

local function addParticles(
	parent: Instance,
	config: {
		color: Color3,
		rate: number,
		lifetime: NumberRange,
		speed: NumberRange,
		size: NumberSequence,
		spread: Vector2?,
	}
)
	local attachment = Instance.new("Attachment")
	attachment.Parent = parent

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(config.color)
	emitter.Rate = config.rate
	emitter.Lifetime = config.lifetime
	emitter.Speed = config.speed
	emitter.Size = config.size
	emitter.SpreadAngle = config.spread or Vector2.new(30, 30)
	emitter.LightEmission = 0.2
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Parent = attachment
	return emitter
end

local function buildRainbowPaths()
	local paths = Instance.new("Model")
	paths.Name = "RainbowPaths"
	paths.Parent = decorFolder

	local colors = {
		Theme.PastelPink,
		Theme.PastelPeach,
		Theme.PastelYellow,
		Theme.PastelGreen,
		Theme.PastelBlue,
		Theme.PastelPurple,
	}

	local tileHeight = 0.12
	local tileY = Util.groundCenterY(tileHeight)

	local function layPath(from: Vector3, to: Vector3, colorOffset: number)
		local flatFrom = Vector3.new(from.X, tileY, from.Z)
		local flatTo = Vector3.new(to.X, tileY, to.Z)
		local delta = flatTo - flatFrom
		local distance = delta.Magnitude
		if distance < 4 then
			return
		end
		local direction = delta.Unit
		local steps = math.floor(distance / 2.8)

		for step = 1, steps do
			local tile = Util.createPart({
				name = "PathTile",
				size = Vector3.new(2.4, tileHeight, 2.4),
				position = flatFrom + direction * (step * 2.8),
				color = colors[((colorOffset + step) % #colors) + 1],
				material = Enum.Material.SmoothPlastic,
				parent = paths,
				canCollide = true,
			})
			tile.Transparency = 0.42
			if step % 6 == 0 then
				addGlow(tile, tile.Color, 0.25, 6)
			end
		end
	end

	local hub = Vector3.new(0, Util.GROUND_Y, 0)
	for i, target in STATION_POSITIONS do
		layPath(hub, target, i)
	end

	for i = 1, #STATION_POSITIONS do
		local a = STATION_POSITIONS[i]
		local b = STATION_POSITIONS[(i % #STATION_POSITIONS) + 1]
		layPath(a, b, i + 3)
	end

	for i = 0, 23 do
		local angle = (i / 24) * math.pi * 2
		local nextAngle = ((i + 1) / 24) * math.pi * 2
		local a = Vector3.new(math.cos(angle) * PERIMETER_RADIUS, tileY, math.sin(angle) * PERIMETER_RADIUS)
		local b = Vector3.new(math.cos(nextAngle) * PERIMETER_RADIUS, tileY, math.sin(nextAngle) * PERIMETER_RADIUS)
		layPath(a, b, i)
	end
end

local function buildFloatingOrbs()
	local orbs = Instance.new("Model")
	orbs.Name = "FloatingOrbs"
	orbs.Parent = decorFolder

	local index = 0
	for _, ring in { 22, 45, 70, 95, 120 } do
		local count = math.floor(ring / 4)
		for i = 1, count do
			index += 1
			local angle = (i / count) * math.pi * 2 + ring * 0.01
			local height = 6 + (index % 5) * 2.5
			local orb = Util.createPart({
				name = "Orb_" .. index,
				size = Vector3.new(1 + (index % 3) * 0.35, 1 + (index % 3) * 0.35, 1 + (index % 3) * 0.35),
				position = Vector3.new(math.cos(angle) * ring, height, math.sin(angle) * ring),
				color = Theme.BalloonColors[(index % #Theme.BalloonColors) + 1],
				material = Enum.Material.SmoothPlastic,
				shape = Enum.PartType.Ball,
				parent = orbs,
			})
			orb.Transparency = 0.48
			if index % 3 == 0 then
				addGlow(orb, orb.Color, 0.35, 10)
			end

			local startY = orb.Position.Y
			TweenService:Create(
				orb,
				TweenInfo.new(2 + (index % 4), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Position = Vector3.new(orb.Position.X, startY + 2, orb.Position.Z) }
			):Play()
		end
	end

	for _, station in STATION_POSITIONS do
		for i = 1, 3 do
			index += 1
			local orb = Util.createPart({
				name = "StationOrb_" .. index,
				size = Vector3.new(0.9, 0.9, 0.9),
				position = station + Vector3.new(math.cos(i * 2) * 8, 5 + i, math.sin(i * 2) * 8),
				color = Theme.BalloonColors[(index % #Theme.BalloonColors) + 1],
				material = Enum.Material.SmoothPlastic,
				shape = Enum.PartType.Ball,
				parent = orbs,
			})
			orb.Transparency = 0.52
		end
	end
end

local function buildAuroraPillars()
	local aurora = Instance.new("Model")
	aurora.Name = "AuroraPillars"
	aurora.Parent = decorFolder

	local pillarColors = {
		Color3.fromRGB(120, 255, 200),
		Color3.fromRGB(180, 140, 255),
		Color3.fromRGB(255, 160, 220),
		Color3.fromRGB(140, 210, 255),
	}

	local rings = { 50, 85, 120 }
	for _, radius in rings do
		local count = if radius > 100 then 10 else 6
		for i = 1, count do
			local angle = (i / count) * math.pi * 2
			local color = pillarColors[(i % #pillarColors) + 1]
			local pillarHeight = 22 + (i % 3) * 4
			local pillar = Util.createPart({
				name = "AuroraPillar_" .. radius .. "_" .. i,
				size = Vector3.new(2.5, pillarHeight, 2.5),
				position = Vector3.new(math.cos(angle) * radius, Util.groundCenterY(pillarHeight), math.sin(angle) * radius),
				color = color,
				material = Enum.Material.Glass,
				parent = aurora,
				canCollide = true,
			})
			pillar.Transparency = 0.72
			if i % 2 == 0 then
				addGlow(pillar, color, 0.3, 18)
			end

			task.spawn(function()
				local hue = i / count
				while pillar.Parent do
					hue = (hue + 0.0025) % 1
					pillar.Color = Color3.fromHSV(hue, 0.22, 0.85)
					task.wait(0.05)
				end
			end)
		end
	end
end

local function buildCherryBlossomAt(parent: Model, position: Vector3, name: string)
	local tree = Instance.new("Model")
	tree.Name = name
	tree.Parent = parent

	local trunk = Util.createPart({
		name = "Trunk",
		size = Vector3.new(1.6, 7, 1.6),
		position = position + Vector3.new(0, 3.5, 0),
		color = Color3.fromRGB(120, 80, 60),
		material = Enum.Material.Wood,
		parent = tree,
		canCollide = true,
	})

	for i = 1, 5 do
		Util.createPart({
			name = "Canopy_" .. i,
			size = Vector3.new(4, 4, 4),
			position = trunk.Position + Vector3.new(math.cos(i * 1.4) * 2, 4 + (i % 2), math.sin(i * 1.4) * 2),
			color = Color3.fromRGB(255, 180, 210),
			material = Enum.Material.Grass,
			shape = Enum.PartType.Ball,
			parent = tree,
		}).Transparency = 0.12
	end

	local petalAnchor = Util.createPart({
		name = "PetalEmitter",
		size = Vector3.new(1, 1, 1),
		position = trunk.Position + Vector3.new(0, 7, 0),
		color = Theme.PastelPink,
		parent = tree,
	})
	petalAnchor.Transparency = 1

	addParticles(petalAnchor, {
		color = Color3.fromRGB(255, 190, 215),
		rate = 10,
		lifetime = NumberRange.new(2.5, 4.5),
		speed = NumberRange.new(1, 2.5),
		size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.22),
			NumberSequenceKeypoint.new(1, 0),
		}),
		spread = Vector2.new(70, 70),
	})
end

local function buildCherryBlossomTrees()
	local trees = Instance.new("Model")
	trees.Name = "CherryBlossomTrees"
	trees.Parent = decorFolder

	buildCherryBlossomAt(trees, Vector3.new(12, 0, 10), "Tree_Spawn")
	for i, station in STATION_POSITIONS do
		local offset = Vector3.new((i % 2 == 0 and 10 or -10), 0, (i % 3 == 0 and 9 or -9))
		buildCherryBlossomAt(trees, station + offset, "Tree_" .. i)
	end
end

local function buildCrystalFountainAt(parent: Model, position: Vector3, name: string, scale: number)
	local fountain = Instance.new("Model")
	fountain.Name = name
	fountain.Parent = parent

	local baseHeight = 1 * scale
	local base = Util.createPart({
		name = "Base",
		size = Vector3.new(10, baseHeight, 10) * scale,
		position = Util.groundPosition(position.X, baseHeight, position.Z),
		color = Theme.SoftWhite,
		material = Enum.Material.Marble,
		parent = fountain,
		canCollide = true,
	})

	local pool = Util.createPart({
		name = "Pool",
		size = Vector3.new(7, 0.35, 7) * scale,
		position = base.Position + Vector3.new(0, 0.55 * scale, 0),
		color = Color3.fromRGB(120, 200, 255),
		material = Enum.Material.Glass,
		parent = fountain,
	})
	pool.Transparency = 0.5

	for i = 1, 5 do
		local crystal = Util.createPart({
			name = "Crystal_" .. i,
			size = Vector3.new(0.7, 2.5, 0.7) * scale,
			position = pool.Position + Vector3.new(math.cos(i) * 2 * scale, 1.5 * scale, math.sin(i) * 2 * scale),
			color = Theme.PastelBlue:Lerp(Theme.PastelPurple, (i - 1) / 4),
			material = Enum.Material.Glass,
			parent = fountain,
		})
		crystal.Transparency = 0.45
	end

	local splashAnchor = Util.createPart({
		name = "Splash",
		size = Vector3.new(1, 1, 1),
		position = pool.Position + Vector3.new(0, 1.2 * scale, 0),
		color = Color3.fromRGB(180, 220, 255),
		parent = fountain,
	})
	splashAnchor.Transparency = 1

	addParticles(splashAnchor, {
		color = Color3.fromRGB(180, 230, 255),
		rate = 16,
		lifetime = NumberRange.new(0.7, 1.2),
		speed = NumberRange.new(2, 5),
		size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.18),
			NumberSequenceKeypoint.new(1, 0),
		}),
	})
end

local function buildCrystalFountains()
	local fountains = Instance.new("Model")
	fountains.Name = "CrystalFountains"
	fountains.Parent = decorFolder

	buildCrystalFountainAt(fountains, Vector3.new(0, 0, 14), "Fountain_Spawn", 1)
	buildCrystalFountainAt(fountains, Vector3.new(-80, 0, -80), "Fountain_NW", 0.85)
	buildCrystalFountainAt(fountains, Vector3.new(80, 0, -80), "Fountain_NE", 0.85)
	buildCrystalFountainAt(fountains, Vector3.new(-80, 0, 80), "Fountain_SW", 0.85)
	buildCrystalFountainAt(fountains, Vector3.new(80, 0, 80), "Fountain_SE", 0.85)

	for i = 1, #STATION_POSITIONS, 3 do
		local station = STATION_POSITIONS[i]
		buildCrystalFountainAt(fountains, station + Vector3.new(14, 0, 0), "Fountain_Station_" .. i, 0.65)
	end
end

local function buildRotatingHalos()
	local halos = Instance.new("Model")
	halos.Name = "RotatingHalos"
	halos.Parent = decorFolder

	local centers = {
		Vector3.new(0, 0, 0),
		Vector3.new(-70, 0, 0),
		Vector3.new(70, 0, 0),
		Vector3.new(0, 0, -70),
		Vector3.new(0, 0, 70),
	}

	for h, center in centers do
		local ringParts = {}
		local radius = if h == 1 then 10 else 7
		local height = 15

		for i = 1, 12 do
			local angle = (i / 12) * math.pi * 2
			local segment = Util.createPart({
				name = "HaloSegment",
				size = Vector3.new(1.6, 0.35, 1.6),
				position = center + Vector3.new(math.cos(angle) * radius, height, math.sin(angle) * radius),
				color = Theme.BalloonColors[(i % #Theme.BalloonColors) + 1],
				material = Enum.Material.SmoothPlastic,
				parent = halos,
			})
			segment.Transparency = 0.5
			table.insert(ringParts, { segment = segment, baseAngle = angle })
		end

		task.spawn(function()
			local rotation = h * 30
			while halos.Parent do
				rotation += 0.35
				for _, data in ringParts do
					local angle = data.baseAngle + math.rad(rotation)
					data.segment.Position = center
						+ Vector3.new(
							math.cos(angle) * radius,
							height + math.sin(rotation * 0.04) * 0.4,
							math.sin(angle) * radius
						)
				end
				task.wait(0.03)
			end
		end)
	end
end

local function buildZenGardenAt(parent: Model, position: Vector3, name: string)
	local zen = Instance.new("Model")
	zen.Name = name
	zen.Parent = parent

	local sandHeight = 0.25
	local sand = Util.createPart({
		name = "SandCircle",
		size = Vector3.new(14, sandHeight, 14),
		position = Util.groundPosition(position.X, sandHeight, position.Z),
		color = Color3.fromRGB(235, 225, 200),
		material = Enum.Material.Sand,
		parent = zen,
		canCollide = true,
	})

	for i = 1, 3 do
		Util.createPart({
			name = "Stone_" .. i,
			size = Vector3.new(1.2, 0.8, 1.2),
			position = sand.Position + Vector3.new(math.cos(i * 1.5) * 4, sandHeight / 2 + 0.4, math.sin(i * 1.5) * 4),
			color = Color3.fromRGB(90, 95, 105),
			material = Enum.Material.Slate,
			parent = zen,
			canCollide = true,
		})
	end
end

local function buildZenGardens()
	local zen = Instance.new("Model")
	zen.Name = "ZenGardens"
	zen.Parent = decorFolder

	buildZenGardenAt(zen, Vector3.new(-12, 0, 14), "Zen_Spawn")
	for i, station in STATION_POSITIONS do
		if i % 2 == 0 then
			buildZenGardenAt(zen, station + Vector3.new(-12, -0.5, 8), "Zen_" .. i)
		end
	end

	local corners = {
		Vector3.new(-100, 0, -100),
		Vector3.new(100, 0, -100),
		Vector3.new(-100, 0, 100),
		Vector3.new(100, 0, 100),
	}
	for i, corner in corners do
		buildZenGardenAt(zen, corner, "Zen_Corner_" .. i)
	end
end

local function buildFairyLights()
	local lights = Instance.new("Model")
	lights.Name = "FairyLights"
	lights.Parent = decorFolder

	local lightColors = Theme.BalloonColors
	local index = 0

	local function layString(from: Vector3, to: Vector3)
		local mid = (from + to) / 2 + Vector3.new(0, 5, 0)
		local segments = 12
		for step = 0, segments do
			local t = step / segments
			local pos = from:Lerp(mid, t):Lerp(to, t)
			index += 1
			local bulb = Util.createPart({
				name = "Bulb",
				size = Vector3.new(0.32, 0.32, 0.32),
				position = pos,
				color = lightColors[(index % #lightColors) + 1],
				material = Enum.Material.SmoothPlastic,
				shape = Enum.PartType.Ball,
				parent = lights,
			})
			if index % 4 == 0 then
				addGlow(bulb, bulb.Color, 0.2, 4)
			end
			TweenService:Create(
				bulb,
				TweenInfo.new(1 + (index % 4) * 0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Transparency = 0.65 }
			):Play()
		end
	end

	for _, target in STATION_POSITIONS do
		layString(Vector3.new(0, 9, 0), target + Vector3.new(0, 7, 0))
	end

	for i = 0, 11 do
		local angle = (i / 12) * math.pi * 2
		local nextAngle = ((i + 1) / 12) * math.pi * 2
		local a = Vector3.new(math.cos(angle) * PERIMETER_RADIUS, 8, math.sin(angle) * PERIMETER_RADIUS)
		local b = Vector3.new(math.cos(nextAngle) * PERIMETER_RADIUS, 8, math.sin(nextAngle) * PERIMETER_RADIUS)
		layString(a, b)
	end
end

local function buildFireflies()
	local fireflies = Instance.new("Model")
	fireflies.Name = "Fireflies"
	fireflies.Parent = decorFolder

	for i = 1, 28 do
		local angle = (i / 28) * math.pi * 2
		local radius = 25 + (i % 6) * 18
		local anchor = Util.createPart({
			name = "FireflyZone_" .. i,
			size = Vector3.new(1, 1, 1),
			position = Vector3.new(math.cos(angle) * radius, 3.5 + (i % 4), math.sin(angle) * radius),
			color = Color3.fromRGB(255, 255, 180),
			parent = fireflies,
		})
		anchor.Transparency = 1

		addParticles(anchor, {
			color = Color3.fromRGB(255, 255, 160),
			rate = 5,
			lifetime = NumberRange.new(2, 4),
			speed = NumberRange.new(0.4, 1.8),
			size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.12),
				NumberSequenceKeypoint.new(1, 0),
			}),
			spread = Vector2.new(180, 180),
		})
	end
end

local function buildStationGlowPads()
	local pads = Instance.new("Model")
	pads.Name = "StationGlowPads"
	pads.Parent = decorFolder

	for i, pos in STATION_POSITIONS do
		local padHeight = 0.1
		local pad = Util.createPart({
			name = "GlowPad",
			size = Vector3.new(10, padHeight, 10),
			position = Util.groundPosition(pos.X, padHeight, pos.Z),
			color = Theme.BalloonColors[(i % #Theme.BalloonColors) + 1],
			material = Enum.Material.SmoothPlastic,
			parent = pads,
			canCollide = true,
		})
		pad.Transparency = 0.55

		TweenService:Create(
			pad,
			TweenInfo.new(2 + (i % 4) * 0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Transparency = 0.78 }
		):Play()
	end

	for i = 0, 15 do
		local angle = (i / 16) * math.pi * 2
		local ringHeight = 0.08
		local pad = Util.createPart({
			name = "RingPad_" .. i,
			size = Vector3.new(6, ringHeight, 6),
			position = Util.groundPosition(math.cos(angle) * PERIMETER_RADIUS, ringHeight, math.sin(angle) * PERIMETER_RADIUS),
			color = Theme.BalloonColors[(i % #Theme.BalloonColors) + 1],
			material = Enum.Material.SmoothPlastic,
			parent = pads,
			canCollide = true,
		})
		pad.Transparency = 0.6
	end
end

local function buildMapSparkles()
	local sparkles = Instance.new("Model")
	sparkles.Name = "MapSparkles"
	sparkles.Parent = decorFolder

	local colors = Theme.BalloonColors
	for i = 1, 80 do
		local angle = math.random() * math.pi * 2
		local radius = 15 + math.random() * MAP_SCATTER_RADIUS
		local sparkleHeight = 0.08
		local tile = Util.createPart({
			name = "Sparkle",
			size = Vector3.new(0.5, sparkleHeight, 0.5),
			position = Util.groundPosition(math.cos(angle) * radius, sparkleHeight, math.sin(angle) * radius),
			color = colors[(i % #colors) + 1],
			material = Enum.Material.SmoothPlastic,
			parent = sparkles,
			canCollide = false,
		})
		tile.Transparency = 0.55 + (i % 3) * 0.12

		if i % 9 == 0 then
			TweenService:Create(
				tile,
				TweenInfo.new(1.5 + (i % 5) * 0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Transparency = 0.82 }
			):Play()
		end
	end
end

function DecorService.Init()
	decorFolder = Instance.new("Folder")
	decorFolder.Name = "Decor"
	decorFolder.Parent = workspace:WaitForChild("ASMRStudio")

	buildRainbowPaths()
	buildFloatingOrbs()
	buildAuroraPillars()
	buildCherryBlossomTrees()
	buildCrystalFountains()
	buildRotatingHalos()
	buildZenGardens()
	buildFairyLights()
	buildFireflies()
	buildStationGlowPads()
	buildMapSparkles()
end

return DecorService
