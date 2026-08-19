local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("Theme"))
local Util = require(Shared:WaitForChild("Util"))
local ActivityConfig = require(Shared:WaitForChild("ActivityConfig"))

local WorldService = {}

local studioFolder: Folder

local SPREAD = 1.5
local SCALE = 1.65
local KEY_SCALE = 2.6

local function stationPos(x: number, z: number): Vector3
	return Vector3.new(x * SPREAD, 0.5, z * SPREAD)
end

local function sz(x: number, y: number, z: number, scale: number?): Vector3
	local s = scale or SCALE
	return Vector3.new(x * s, y * s, z * s)
end

local function onPlatform(platformCenter: Vector3, platformHeight: number, partHeight: number, gap: number?): Vector3
	return Util.onTopOf(platformCenter, platformHeight, partHeight, gap)
end

local function createSign(parent: Instance, title: string, subtitle: string)
	local signPart = Util.createPart({
		name = "Sign",
		size = sz(8, 3, 0.4),
		position = parent:GetPivot().Position + Vector3.new(0, 6.5 * SCALE, -8 * SCALE),
		color = Theme.SoftWhite,
		material = Enum.Material.SmoothPlastic,
		parent = parent,
	})

	local surfaceGui = Instance.new("SurfaceGui")
	surfaceGui.Face = Enum.NormalId.Front
	surfaceGui.Parent = signPart

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.new(1, 0, 0.55, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextColor3 = Color3.fromRGB(70, 65, 80)
	titleLabel.TextScaled = true
	titleLabel.Text = title
	titleLabel.Parent = surfaceGui

	local subLabel = Instance.new("TextLabel")
	subLabel.Size = UDim2.new(1, 0, 0.4, 0)
	subLabel.Position = UDim2.new(0, 0, 0.55, 0)
	subLabel.BackgroundTransparency = 1
	subLabel.Font = Enum.Font.Gotham
	subLabel.TextColor3 = Color3.fromRGB(110, 105, 120)
	subLabel.TextScaled = true
	subLabel.Text = subtitle
	subLabel.Parent = surfaceGui
end

local function createPlatform(name: string, position: Vector3, size: Vector3, color: Color3): Model
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = studioFolder

	local platform = Util.createPart({
		name = "Platform",
		size = size,
		position = position,
		color = color,
		material = Enum.Material.Wood,
		parent = model,
		canCollide = true,
	})
	model.PrimaryPart = platform
	Util.addWalkZone(model, size, position)

	return model
end

local function buildWelcomeArea()
	local welcome = Instance.new("Model")
	welcome.Name = "Welcome"
	welcome.Parent = studioFolder

	local arch = Util.createPart({
		name = "Arch",
		size = sz(28, 12, 2),
		position = Vector3.new(0, 6 * SCALE, -18 * SPREAD),
		color = Theme.PastelPurple,
		material = Enum.Material.SmoothPlastic,
		parent = welcome,
		canCollide = true,
	})

	local titleGui = Instance.new("SurfaceGui")
	titleGui.Face = Enum.NormalId.Front
	titleGui.Parent = arch

	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(1, 1)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextScaled = true
	title.Text = "✨ ASMR SATISFACTION ✨"
	title.Parent = titleGui

	for x = -1, 1, 2 do
		Util.createPart({
			name = "Pillar",
			size = sz(2, 14, 2),
			position = Vector3.new(x * 12 * SPREAD, 7 * SCALE, -18 * SPREAD),
			color = Theme.PastelPeach,
			material = Enum.Material.SmoothPlastic,
			parent = welcome,
			canCollide = true,
		})
	end
end

local function buildKeyboardStation()
	local config = ActivityConfig.Keyboard
	local platformSize = sz(28, 1, 18, KEY_SCALE)
	local station = createPlatform("KeyboardStation", stationPos(-42, -28), platformSize, Theme.WoodBrown)
	createSign(station, config.displayName, config.description)

	local deskHeight = 1.1 * KEY_SCALE / SCALE
	local desk = Util.createPart({
		name = "Desk",
		size = Vector3.new(24 * KEY_SCALE / SCALE, deskHeight, 14 * KEY_SCALE / SCALE),
		position = onPlatform(station.PrimaryPart.Position, platformSize.Y, deskHeight),
		color = Theme.DeskGray,
		material = Enum.Material.Metal,
		parent = station,
		canCollide = true,
	})

	local keyLayout = {
		{ "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P" },
		{ "A", "S", "D", "F", "G", "H", "J", "K", "L" },
		{ "Z", "X", "C", "V", "B", "N", "M" },
	}

	local keyWidth = 1.35 * KEY_SCALE
	local keyHeight = 0.35 * KEY_SCALE
	local keyDepth = 1.35 * KEY_SCALE
	local keyGap = 0.18 * KEY_SCALE
	local rowStagger = 0.42 * KEY_SCALE
	local startX = desk.Position.X - keyWidth * 4.6
	local baseZ = desk.Position.Z - keyDepth * 1.85
	local keyRestY = desk.Position.Y + deskHeight / 2 + keyHeight / 2

	for rowIndex, row in keyLayout do
		for colIndex, keyName in row do
			local key = Util.createPart({
				name = "Key_" .. keyName,
				size = Vector3.new(keyWidth, keyHeight, keyDepth),
				position = Vector3.new(
					startX + (colIndex - 1) * (keyWidth + keyGap) + (rowIndex - 1) * rowStagger,
					keyRestY,
					baseZ + (rowIndex - 1) * (keyDepth + keyGap)
				),
				color = Theme.SoftWhite,
				material = Enum.Material.SmoothPlastic,
				anchored = true,
				parent = station,
				canCollide = true,
			})
			key:SetAttribute("RestY", keyRestY)
			key:SetAttribute("TriggerRadius", keyWidth * 1.1)
			Util.tagInteractive(key, config.id, keyName, station.Name)

			local letterGui = Instance.new("SurfaceGui")
			letterGui.Face = Enum.NormalId.Top
			letterGui.Parent = key
			local letter = Instance.new("TextLabel")
			letter.Size = UDim2.fromScale(1, 1)
			letter.BackgroundTransparency = 1
			letter.Font = Enum.Font.GothamBold
			letter.TextColor3 = Color3.fromRGB(50, 50, 55)
			letter.TextScaled = true
			letter.Text = keyName
			letter.Parent = letterGui
		end
	end
end

local function buildBalloonStation()
	local config = ActivityConfig.Balloon
	local station = createPlatform("BalloonStation", stationPos(42, -28), sz(22, 1, 14), Theme.PastelPink)
	createSign(station, config.displayName, config.description)

	local anchor = Util.createPart({
		name = "BalloonAnchor",
		size = sz(14, 0.3, 10),
		position = onPlatform(station.PrimaryPart.Position, 1 * SCALE, 0.3 * SCALE),
		color = Theme.SoftWhite,
		parent = station,
	})

	for i = 1, 15 do
		local row = math.floor((i - 1) / 5)
		local col = (i - 1) % 5
		local x = anchor.Position.X - 4 * SCALE + col * 2 * SCALE
		local z = anchor.Position.Z - 3 * SCALE + row * 2.5 * SCALE
		local y = anchor.Position.Y + 3 * SCALE + (i % 3) * 0.8 * SCALE

		Util.createPart({
			name = "String",
			size = Vector3.new(0.08, 2.5, 0.08) * SCALE,
			position = Vector3.new(x, y - 1.2 * SCALE, z),
			color = Color3.fromRGB(200, 200, 200),
			material = Enum.Material.SmoothPlastic,
			parent = station,
		})

		local balloon = Util.createPart({
			name = "Balloon_" .. i,
			size = sz(1.8, 2.2, 1.8),
			position = Vector3.new(x, y, z),
			color = Theme.BalloonColors[((i - 1) % #Theme.BalloonColors) + 1],
			material = Enum.Material.SmoothPlastic,
			shape = Enum.PartType.Ball,
			parent = station,
		})
		balloon:SetAttribute("RestPosition", balloon.Position)
		balloon:SetAttribute("Popped", false)
		Util.tagInteractive(balloon, config.id, tostring(i), station.Name)
	end
end

local function buildBubbleWrapStation()
	local config = ActivityConfig.BubbleWrap
	local station = createPlatform("BubbleWrapStation", stationPos(-42, 28), sz(22, 1, 14), Theme.PastelBlue)
	createSign(station, config.displayName, config.description)

	local sheet = Util.createPart({
		name = "Sheet",
		size = sz(14, 0.25, 10),
		position = onPlatform(station.PrimaryPart.Position, 1 * SCALE, 0.25 * SCALE),
		color = Color3.fromRGB(230, 235, 240),
		material = Enum.Material.SmoothPlastic,
		parent = station,
	})

	local bubbleIndex = 0
	for row = 0, 5 do
		for col = 0, 7 do
			bubbleIndex += 1
			local bubble = Util.createPart({
				name = "Bubble_" .. bubbleIndex,
				size = sz(1.2, 0.55, 1.2),
				position = sheet.Position
					+ Vector3.new(-5.25 * SCALE + col * 1.5 * SCALE, 0.35 * SCALE, -3.75 * SCALE + row * 1.5 * SCALE),
				color = Color3.fromRGB(200, 220, 255),
				material = Enum.Material.Glass,
				shape = Enum.PartType.Ball,
				parent = station,
			})
			bubble.Transparency = 0.35
			bubble:SetAttribute("Popped", false)
			bubble:SetAttribute("RestSize", bubble.Size)
			Util.tagInteractive(bubble, config.id, tostring(bubbleIndex), station.Name)
		end
	end
end

local function buildSlimeStation()
	local config = ActivityConfig.Slime
	local station = createPlatform("SlimeStation", stationPos(42, 28), sz(20, 1, 14), Theme.PastelGreen)
	createSign(station, config.displayName, config.description)

	local bowl = Util.createPart({
		name = "Bowl",
		size = sz(10, 1.2, 10),
		position = onPlatform(station.PrimaryPart.Position, 1 * SCALE, 1.2 * SCALE),
		color = Theme.SoftWhite,
		material = Enum.Material.SmoothPlastic,
		shape = Enum.PartType.Cylinder,
		parent = station,
	})
	bowl.Orientation = Vector3.new(0, 0, 90)

	for i = 1, 3 do
		local slime = Util.createPart({
			name = "Slime_" .. i,
			size = Vector3.new((3.5 - i * 0.4) * SCALE, 1.8 * SCALE, (3.5 - i * 0.4) * SCALE),
			position = bowl.Position + Vector3.new(0, (0.8 + i * 0.15) * SCALE, 0),
			color = Theme.SlimeGreen:Lerp(Theme.PastelPurple, (i - 1) * 0.25),
			material = Enum.Material.SmoothPlastic,
			shape = Enum.PartType.Ball,
			parent = station,
		})
		slime.Transparency = 0.35
		slime:SetAttribute("RestSize", slime.Size)
		Util.tagInteractive(slime, config.id, tostring(i), station.Name)
	end
end

local function buildSoapStation()
	local config = ActivityConfig.Soap
	local station = createPlatform("SoapStation", stationPos(0, -52), sz(24, 1, 14), Theme.PastelYellow)
	createSign(station, config.displayName, config.description)

	local tablePart = Util.createPart({
		name = "Table",
		size = sz(16, 0.6, 8),
		position = onPlatform(station.PrimaryPart.Position, 1 * SCALE, 0.6 * SCALE),
		color = Theme.WoodBrown,
		material = Enum.Material.Wood,
		parent = station,
	})

	local soapColors = { Theme.PastelPink, Theme.PastelBlue, Theme.PastelGreen, Theme.PastelPurple, Theme.PastelPeach }
	for i = 1, 5 do
		local soap = Util.createPart({
			name = "SoapLayer_" .. i,
			size = sz(10, 0.55, 5),
			position = tablePart.Position + Vector3.new(0, (0.35 + i * 0.5) * SCALE, 0),
			color = soapColors[i],
			material = Enum.Material.SmoothPlastic,
			parent = station,
		})
		soap:SetAttribute("LayerIndex", i)
		soap:SetAttribute("Sliced", false)
		Util.tagInteractive(soap, config.id, tostring(i), station.Name)
	end
end

local function buildFidgetStation()
	local config = ActivityConfig.Fidget
	local station = createPlatform("FidgetStation", stationPos(-62, 0), sz(18, 1, 14), Theme.PastelPurple)
	createSign(station, config.displayName, config.description)

	local cubeSize = 6 * SCALE
	local cube = Util.createPart({
		name = "FidgetCube",
		size = Vector3.new(cubeSize, cubeSize, cubeSize),
		position = onPlatform(station.PrimaryPart.Position, 1 * SCALE, cubeSize),
		color = Theme.DeskGray,
		material = Enum.Material.SmoothPlastic,
		parent = station,
	})

	local buttons = {
		{ Vector3.new(0, 0, 1), "Button1", Theme.PastelPink },
		{ Vector3.new(0, 0, -1), "Button2", Theme.PastelBlue },
		{ Vector3.new(1, 0, 0), "Roller", Theme.PastelGreen },
		{ Vector3.new(-1, 0, 0), "Switch", Theme.PastelYellow },
		{ Vector3.new(0, 1, 0), "TopClick", Theme.PastelPeach },
	}

	local btnReach = cubeSize / 2 + 0.25 * SCALE
	for _, data in buttons do
		local offset, id, color = data[1], data[2], data[3]
		local btn = Util.createPart({
			name = id,
			size = sz(1.4, 0.5, 1.4),
			position = cube.Position + offset * btnReach,
			color = color,
			material = Enum.Material.SmoothPlastic,
			parent = station,
		})
		btn:SetAttribute("RestSize", btn.Size)
		Util.tagInteractive(btn, config.id, id, station.Name)
	end
end

local function buildSwitchStation()
	local config = ActivityConfig.Switches
	local station = createPlatform("SwitchStation", stationPos(62, 0), sz(18, 1, 14), Theme.PastelPeach)
	createSign(station, config.displayName, config.description)

	local panel = Util.createPart({
		name = "Panel",
		size = sz(12, 10, 0.6),
		position = onPlatform(station.PrimaryPart.Position, 1 * SCALE, 10 * SCALE),
		color = Theme.DeskGray,
		material = Enum.Material.Metal,
		parent = station,
	})

	for i = 1, 8 do
		local row = math.floor((i - 1) / 2)
		local col = (i - 1) % 2
		local switchBase = Util.createPart({
			name = "SwitchBase_" .. i,
			size = sz(2.5, 4, 0.8),
			position = panel.Position
				+ Vector3.new(-2.5 * SCALE + col * 5 * SCALE, 2.5 * SCALE - row * 2.2 * SCALE, 0.55 * SCALE),
			color = Color3.fromRGB(40, 40, 45),
			material = Enum.Material.SmoothPlastic,
			parent = station,
		})

		local toggle = Util.createPart({
			name = "Switch_" .. i,
			size = sz(1.8, 0.6, 0.9),
			position = switchBase.Position + Vector3.new(0, 1 * SCALE, 0.2 * SCALE),
			color = Theme.PastelGreen,
			material = Enum.Material.SmoothPlastic,
			parent = station,
		})
		toggle:SetAttribute("On", true)
		toggle:SetAttribute("RestPosition", toggle.Position)
		toggle.Color = Theme.PastelGreen:Lerp(Color3.fromRGB(120, 140, 120), 0.45)
		Util.tagInteractive(toggle, config.id, tostring(i), station.Name)
	end
end

local function buildCrinkleStation()
	local config = ActivityConfig.Crinkle
	local station = createPlatform("CrinkleStation", stationPos(0, 52), sz(20, 1, 14), Theme.PastelBlue)
	createSign(station, config.displayName, config.description)

	local foil = Util.createPart({
		name = "FoilSheet",
		size = sz(14, 0.08, 10),
		position = onPlatform(station.PrimaryPart.Position, 1 * SCALE, 0.08 * SCALE),
		color = Color3.fromRGB(200, 205, 215),
		material = Enum.Material.Foil,
		parent = station,
	})
	Util.tagInteractive(foil, config.id, "sheet", station.Name)

	for i = 1, 6 do
		local strip = Util.createPart({
			name = "Strip_" .. i,
			size = sz(12, 0.06, 1.2),
			position = foil.Position + Vector3.new(0, 0.08 * SCALE, (-3.5 + (i - 1) * 1.4) * SCALE),
			color = Color3.fromRGB(180, 185, 195),
			material = Enum.Material.Foil,
			parent = station,
		})
		Util.tagInteractive(strip, config.id, "strip_" .. i, station.Name)
	end
end

local function buildSandStation()
	local config = ActivityConfig.Sand
	local station = createPlatform("SandStation", stationPos(-24, 0), sz(18, 1, 14), Theme.PastelYellow)
	createSign(station, config.displayName, config.description)

	local tray = Util.createPart({
		name = "Tray",
		size = sz(12, 0.8, 8),
		position = onPlatform(station.PrimaryPart.Position, 1 * SCALE, 0.8 * SCALE),
		color = Theme.WoodBrown,
		material = Enum.Material.Wood,
		parent = station,
	})

	local sand = Util.createPart({
		name = "Sand",
		size = sz(10, 0.5, 6),
		position = tray.Position + Vector3.new(0, 0.55 * SCALE, 0),
		color = Color3.fromRGB(240, 220, 160),
		material = Enum.Material.Sand,
		parent = station,
	})
	Util.tagInteractive(sand, config.id, "sand", station.Name)

	for i = 1, 12 do
		local grain = Util.createPart({
			name = "Grain_" .. i,
			size = sz(0.6, 0.3, 0.6),
			position = sand.Position
				+ Vector3.new(math.random(-40, 40) / 10 * SCALE, 0.35 * SCALE, math.random(-25, 25) / 10 * SCALE),
			color = Color3.fromRGB(230, 210, 150),
			material = Enum.Material.Sand,
			parent = station,
		})
		Util.tagInteractive(grain, config.id, "grain_" .. i, station.Name)
	end
end

local function buildWaterStation()
	local config = ActivityConfig.Water
	local station = createPlatform("WaterStation", stationPos(24, 0), sz(18, 1, 14), Theme.PastelBlue)
	createSign(station, config.displayName, config.description)

	local basin = Util.createPart({
		name = "Basin",
		size = sz(12, 1, 8),
		position = onPlatform(station.PrimaryPart.Position, 1 * SCALE, 1 * SCALE),
		color = Theme.SoftWhite,
		material = Enum.Material.SmoothPlastic,
		parent = station,
	})

	local water = Util.createPart({
		name = "Water",
		size = sz(10, 0.3, 6),
		position = basin.Position + Vector3.new(0, 0.4 * SCALE, 0),
		color = Color3.fromRGB(100, 180, 255),
		material = Enum.Material.Glass,
		parent = station,
	})
	water.Transparency = 0.4

	for i = 1, 10 do
		local drop = Util.createPart({
			name = "Drop_" .. i,
			size = sz(0.5, 0.7, 0.5),
			position = water.Position
				+ Vector3.new(math.random(-35, 35) / 10 * SCALE, (0.5 + (i % 3) * 0.2) * SCALE, math.random(-20, 20) / 10 * SCALE),
			color = Color3.fromRGB(130, 200, 255),
			material = Enum.Material.Glass,
			shape = Enum.PartType.Ball,
			parent = station,
		})
		drop.Transparency = 0.25
		drop:SetAttribute("RestPosition", drop.Position)
		Util.tagInteractive(drop, config.id, tostring(i), station.Name)
	end
end

function WorldService.Init()
	studioFolder = Instance.new("Folder")
	studioFolder.Name = "ASMRStudio"
	studioFolder.Parent = workspace

	buildWelcomeArea()
	buildKeyboardStation()
	buildBalloonStation()
	buildBubbleWrapStation()
	buildSlimeStation()
	buildSoapStation()
	buildFidgetStation()
	buildSwitchStation()
	buildCrinkleStation()
	buildSandStation()
	buildWaterStation()
end

return WorldService
