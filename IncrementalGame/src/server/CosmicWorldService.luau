local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CosmicConfig = require(Shared:WaitForChild("CosmicConfig"))
local CosmicFormat = require(Shared:WaitForChild("CosmicFormat"))
local WorldStyle = require(Shared:WaitForChild("WorldStyle"))

local CosmicGameService = require(script.Parent:WaitForChild("CosmicGameService"))
local CosmicBaseService = require(script.Parent:WaitForChild("CosmicBaseService"))

local CosmicWorldService = {}

local palette = WorldStyle.Palette
local fonts = WorldStyle.Fonts

local BASE_SLOTS = 8

local BASE_LAYOUT = {
	TrainingRowZ = 22,
	TrainingSpacing = 9,
	TrainingStartX = -18,
	BoostRowX = -24,
	BoostSpacing = 8,
	BoostStartZ = -10,
	AscensionLocal = Vector3.new(20, 0.75, 20),
	StatsBoardLocal = Vector3.new(0, 3.8, -26),
}

local islandFolder: Folder
local touchDebounce: { [Player]: { [string]: number } } = {}
local TOUCH_COOLDOWN = 0.5
local PAD_PRESS_DEPTH = 0.28
local padMotionRest: { [Part]: { plate: CFrame, sign: CFrame? } } = {}
local padAnimating: { [Part]: boolean } = {}

local slotGeneratorPads: { [number]: { [string]: Part } } = {}
local slotMultiplierPads: { [number]: { [string]: Part } } = {}
local slotAscensionPads: { [number]: Part } = {}
local slotStatsLabels: { [number]: TextLabel? } = {}

local function localToWorld(platform: Part, localPos: Vector3): Vector3
	return (platform.CFrame * CFrame.new(localPos)).Position
end

local function getPlayerFromHit(hit: BasePart): Player?
	local character = hit.Parent
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	return game:GetService("Players"):GetPlayerFromCharacter(character)
end

local function canTouch(player: Player, key: string): boolean
	local now = os.clock()
	touchDebounce[player] = touchDebounce[player] or {}
	local lastTouch = touchDebounce[player][key]
	if lastTouch and now - lastTouch < TOUCH_COOLDOWN then
		return false
	end
	touchDebounce[player][key] = now
	return true
end

local function registerPadMotion(plate: Part)
	local model = plate.Parent
	local sign = model and model:FindFirstChild("Sign")
	padMotionRest[plate] = {
		plate = plate.CFrame,
		sign = if sign and sign:IsA("BasePart") then sign.CFrame else nil,
	}
end

local function playPadPress(plate: Part, player: Player)
	if padAnimating[plate] then
		return
	end

	local rest = padMotionRest[plate]
	if not rest then
		return
	end

	padAnimating[plate] = true
	CosmicGameService.FirePadPress(player)

	local model = plate.Parent
	local sign = model and model:FindFirstChild("Sign")
	local signPart = if sign and sign:IsA("BasePart") then sign else nil

	local pressInfo = TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local releaseInfo = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local downDelta = CFrame.new(0, -PAD_PRESS_DEPTH, 0)

	local plateDown = TweenService:Create(plate, pressInfo, { CFrame = rest.plate * downDelta })
	local signDown = if signPart and rest.sign
		then TweenService:Create(signPart, pressInfo, { CFrame = rest.sign * downDelta })
		else nil

	plateDown:Play()
	if signDown then
		signDown:Play()
	end
	plateDown.Completed:Wait()

	local plateUp = TweenService:Create(plate, releaseInfo, { CFrame = rest.plate })
	local signUp = if signPart and rest.sign
		then TweenService:Create(signPart, releaseInfo, { CFrame = rest.sign })
		else nil

	plateUp:Play()
	if signUp then
		signUp:Play()
	end
	plateUp.Completed:Wait()

	padAnimating[plate] = nil
end

local function connectTouch(part: Part, key: string, callback: (Player) -> ())
	part.Touched:Connect(function(hit: BasePart)
		local player = getPlayerFromHit(hit)
		if not player or not canTouch(player, key) then
			return
		end
		task.spawn(playPadPress, part, player)
		callback(player)
	end)
end

local function connectOwnedTouch(part: Part, slot: number, key: string, callback: (Player) -> ())
	part:SetAttribute("OwnerSlot", slot)
	connectTouch(part, key, function(player: Player)
		if CosmicBaseService.GetPlayerSlot(player) ~= slot then
			CosmicGameService.Notify(player, "Upgrade on your own baseplate", "warn", "fail")
			return
		end
		callback(player)
	end)
end

local function createPart(props: {
	Name: string,
	Size: Vector3,
	CFrame: CFrame,
	Color: Color3,
	Material: Enum.Material,
	Parent: Instance,
	CanCollide: boolean?,
	Transparency: number?,
}): Part
	local part = Instance.new("Part")
	part.Name = props.Name
	part.Size = props.Size
	part.CFrame = props.CFrame
	part.Color = props.Color
	part.Material = props.Material
	part.Anchored = true
	part.CanCollide = if props.CanCollide == nil then true else props.CanCollide
	part.Transparency = props.Transparency or 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = props.Parent
	return part
end

local function colorToHex(color: Color3): string
	return string.format("#%02X%02X%02X", color.R * 255, color.G * 255, color.B * 255)
end

local function setPadLabelText(label: TextLabel, title: string, action: string, detail: string, titleColor: Color3?)
	label.RichText = true
	local hex = colorToHex(titleColor or palette.TextPrimary)
	label.Text = string.format(
		'<font color="%s" size="24"><b>%s</b></font>\n<font size="20">%s</font>\n<font size="18">%s</font>',
		hex,
		title,
		action,
		detail
	)
	label.TextColor3 = palette.TextPrimary
end

local function setPlateTopText(plate: Part, title: string, subtitle: string, titleColor: Color3?)
	local gui = plate:FindFirstChild("PlateTopGui")
	if not gui then
		return
	end
	local bg = gui:FindFirstChild("Background")
	local label = bg and bg:FindFirstChild("Text")
	if label and label:IsA("TextLabel") then
		local hex = colorToHex(titleColor or palette.TextPrimary)
		label.RichText = true
		label.Text = string.format(
			'<font color="%s" size="22"><b>%s</b></font>\n<font size="16">%s</font>',
			hex,
			title,
			subtitle
		)
	end
end

local function createPlateTopLabel(plate: Part): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Name = "PlateTopGui"
	gui.Face = Enum.NormalId.Top
	gui.CanvasSize = Vector2.new(220, 220)
	gui.PixelsPerStud = 45
	gui.LightInfluence = 0
	gui.Parent = plate

	local bg = Instance.new("Frame")
	bg.Name = "Background"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = palette.Panel
	bg.BackgroundTransparency = 0.08
	bg.BorderSizePixel = 0
	bg.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = bg

	local stroke = Instance.new("UIStroke")
	stroke.Color = palette.LaneStripe
	stroke.Thickness = 2
	stroke.Parent = bg

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = fonts.Board
	label.TextSize = 18
	label.TextWrapped = true
	label.RichText = true
	label.TextColor3 = palette.TextPrimary
	label.Parent = bg

	return label
end

local function styleBoardLabel(label: TextLabel, textSize: number)
	label.TextScaled = false
	label.TextSize = textSize
	label.TextWrapped = true
	label.LineHeight = 1.15
	label.Font = fonts.Board
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = label
end

local function setPadPlateVisuals(plate: Part, accent: Color3, owned: boolean, unlocked: boolean)
	plate.Material = Enum.Material.SmoothPlastic
	if owned then
		plate.Color = accent
		plate.Transparency = 0
	elseif unlocked then
		plate.Color = accent:Lerp(Color3.fromRGB(255, 255, 255), 0.18)
		plate.Transparency = 0.05
	else
		plate.Color = palette.Locked
		plate.Transparency = 0.1
	end

	local model = plate.Parent
	if not model then
		return
	end

	local strip = model:FindFirstChild("AccentStrip")
	if strip and strip:IsA("BasePart") then
		strip.Color = accent
		strip.Transparency = if owned then 0.08 elseif unlocked then 0.22 else 0.58
	end

	local buttonRing = model:FindFirstChild("ButtonRing")
	if buttonRing and buttonRing:IsA("BasePart") then
		buttonRing.Color = accent
		buttonRing.Transparency = if owned then 0.1 elseif unlocked then 0.25 else 0.65
	end

	local highlight = plate:FindFirstChildOfClass("Highlight")
	if highlight then
		highlight.OutlineColor = accent
		highlight.OutlineTransparency = if owned then 0.3 elseif unlocked then 0.5 else 0.82
	end
end

local function getPadLabel(plate: Part): TextLabel?
	local billboard = plate:FindFirstChild("StationBillboard")
	local frame = billboard and billboard:FindFirstChild("Background")
	local label = frame and frame:FindFirstChild("Text")
	if label and label:IsA("TextLabel") then
		return label
	end
	return nil
end

local function createStationBillboard(plate: Part): TextLabel
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "StationBillboard"
	billboard.Size = UDim2.fromOffset(180, 72)
	billboard.StudsOffset = Vector3.new(0, 2.8, 0)
	billboard.MaxDistance = 80
	billboard.Parent = plate

	local bg = Instance.new("Frame")
	bg.Name = "Background"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = palette.Panel
	bg.BackgroundTransparency = 0.08
	bg.BorderSizePixel = 0
	bg.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = bg

	local stroke = Instance.new("UIStroke")
	stroke.Color = palette.LaneStripe
	stroke.Thickness = 1.5
	stroke.Parent = bg

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = fonts.Board
	label.TextSize = 14
	label.TextWrapped = true
	label.RichText = true
	label.TextColor3 = palette.TextPrimary
	label.Parent = bg

	return label
end

local function updateGeneratorPad(slot: number, player: Player?, generatorId: string)
	local slotPads = slotGeneratorPads[slot]
	local plate = slotPads and slotPads[generatorId]
	if not plate then
		return
	end

	local generator = CosmicConfig.Generators[generatorId]
	if not generator then
		return
	end

	local label = getPadLabel(plate)
	if not label then
		return
	end

	local state = if player then CosmicGameService.GetState(player) else nil
	local owned = state and state.OwnedGenerators[generatorId] == true
	local unlocked = state and CosmicConfig.IsGeneratorUnlocked(state, generatorId) or generator.UnlockAfter == nil

	setPadPlateVisuals(plate, generator.Color, owned, unlocked)

	if owned then
		setPadLabelText(label, generator.DisplayName, "Unlocked", ("+%d power / sec"):format(generator.BaseRate), generator.Color)
		setPlateTopText(plate, generator.DisplayName, ("+%d/s"):format(generator.BaseRate), generator.Color)
	elseif unlocked then
		setPadLabelText(
			label,
			generator.DisplayName,
			"Touch to unlock",
			("%s power  ·  +%d / sec"):format(CosmicFormat.Number(generator.Cost), generator.BaseRate)
		)
		setPlateTopText(plate, generator.DisplayName, CosmicFormat.Number(generator.Cost), generator.Color)
	else
		setPadLabelText(label, generator.DisplayName, "Locked", "Unlock the previous training first", palette.TextMuted)
		setPlateTopText(plate, generator.DisplayName, "LOCKED", palette.TextMuted)
	end
end

local function updateMultiplierPad(slot: number, upgradeId: string, player: Player?)
	local slotPads = slotMultiplierPads[slot]
	local plate = slotPads and slotPads[upgradeId]
	if not plate then
		return
	end

	local upgrade = CosmicConfig.Multipliers[upgradeId]
	if not upgrade then
		return
	end

	local label = getPadLabel(plate)
	if not label then
		return
	end

	local state = if player then CosmicGameService.GetState(player) else nil
	local level = if state then (state.MultiplierLevels[upgradeId] or 0) else 0
	local hasGenerator = state and CosmicConfig.HasAnyGenerator(state)

	if not hasGenerator then
		setPadPlateVisuals(plate, upgrade.Color, false, false)
		setPadLabelText(label, upgrade.DisplayName, "Locked", "Unlock any training lane first", palette.TextMuted)
		setPlateTopText(plate, upgrade.DisplayName, "LOCKED", palette.TextMuted)
	elseif level >= upgrade.MaxLevel then
		setPadPlateVisuals(plate, upgrade.Color, true, true)
		setPadLabelText(label, upgrade.DisplayName, "Max level", ("Level %d"):format(level), upgrade.Color)
		setPlateTopText(plate, upgrade.DisplayName, ("MAX Lv %d"):format(level), upgrade.Color)
	else
		setPadPlateVisuals(plate, upgrade.Color, false, true)
		local cost = CosmicConfig.GetMultiplierCost(upgradeId, level)
		setPadLabelText(
			label,
			upgrade.DisplayName,
			("Touch to upgrade  Lv %d → %d"):format(level, level + 1),
			("%s power"):format(CosmicFormat.Number(cost))
		)
		setPlateTopText(plate, upgrade.DisplayName, ("Lv %d · %s"):format(level, CosmicFormat.Number(cost)), upgrade.Color)
	end
end

local function updateBaseStats(slot: number, player: Player?)
	local label = slotStatsLabels[slot]
	if not label then
		return
	end

	local state = if player then CosmicGameService.GetState(player) else nil
	if not state then
		label.Text = "Loading..."
		return
	end

	local requirement = CosmicConfig.GetAscensionRequirement(state.Ascensions)
	label.Text = string.format(
		"YOUR BASE\nMultiplier %s  ·  Gain %s/s\nAscension %s  ·  Rank %d\nLifetime %s / %s",
		CosmicFormat.Multiplier(CosmicConfig.GetTotalMultiplier(state)),
		CosmicFormat.Number(CosmicConfig.GetPowerPerSecond(state)),
		CosmicFormat.Multiplier(CosmicConfig.GetAscensionMultiplier(state.Ascensions)),
		state.Ascensions,
		CosmicFormat.Number(state.LifetimePower),
		CosmicFormat.Number(requirement)
	)
end

local function updateAscensionPad(slot: number, player: Player?)
	local plate = slotAscensionPads[slot]
	if not plate then
		return
	end

	local label = getPadLabel(plate)
	if label then
		setPadLabelText(label, "Ascension", "Touch when ready", "Resets progress · keeps rank bonus", palette.AccentSoft)
	end
	setPlateTopText(plate, "Ascension", "Touch when ready", palette.AccentSoft)
end

function CosmicWorldService.RefreshPlayer(player: Player)
	local slot = CosmicBaseService.GetPlayerSlot(player)
	if not slot then
		return
	end

	for _, generatorId in CosmicConfig.GeneratorOrder do
		updateGeneratorPad(slot, player, generatorId)
	end
	for _, upgradeId in CosmicConfig.MultiplierOrder do
		updateMultiplierPad(slot, upgradeId, player)
	end
	updateBaseStats(slot, player)
	updateAscensionPad(slot, player)
end

local function createTrainingStation(
	parent: Instance,
	name: string,
	position: Vector3,
	accent: Color3,
	touchKey: string,
	stationKind: string,
	ownerSlot: number,
	onTouch: (Player) -> ()
): Part
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent

	createPart({
		Name = "ZoneTile",
		Size = Vector3.new(6.5, 0.1, 6.5),
		CFrame = CFrame.new(position + Vector3.new(0, 0.08, 0)),
		Color = accent,
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
		CanCollide = false,
		Transparency = 0.55,
	})

	createPart({
		Name = "Pedestal",
		Size = Vector3.new(3.2, 0.35, 3.2),
		CFrame = CFrame.new(position + Vector3.new(0, 0.28, 0)),
		Color = palette.MetalDark,
		Material = Enum.Material.Metal,
		Parent = model,
	})

	local plate = createPart({
		Name = "Plate",
		Size = Vector3.new(2.8, 0.36, 2.8),
		CFrame = CFrame.new(position + Vector3.new(0, 0.58, 0)),
		Color = accent,
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})

	createPart({
		Name = "ButtonRing",
		Size = Vector3.new(3.1, 0.08, 3.1),
		CFrame = plate.CFrame * CFrame.new(0, -0.18, 0),
		Color = accent,
		Material = Enum.Material.Neon,
		Parent = model,
		CanCollide = false,
		Transparency = 0.25,
	})

	createPart({
		Name = "AccentStrip",
		Size = Vector3.new(2.2, 0.06, 0.18),
		CFrame = plate.CFrame * CFrame.new(0, 0.2, -1.35),
		Color = accent,
		Material = Enum.Material.Neon,
		Parent = model,
		CanCollide = false,
		Transparency = 0.2,
	})

	if stationKind == "training" then
		createPart({
			Name = "ConsoleStub",
			Size = Vector3.new(2.4, 1.6, 0.5),
			CFrame = CFrame.new(position + Vector3.new(0, 1.15, -1.6)),
			Color = palette.PanelEdge,
			Material = Enum.Material.Metal,
			Parent = model,
			CanCollide = false,
		})
	elseif stationKind == "boost" then
		createPart({
			Name = "ConsoleStub",
			Size = Vector3.new(2, 1.2, 1.2),
			CFrame = CFrame.new(position + Vector3.new(-1.3, 0.95, 0)),
			Color = palette.PanelEdge,
			Material = Enum.Material.Metal,
			Parent = model,
			CanCollide = false,
		})
	elseif stationKind == "ascension" then
		createPart({
			Name = "AscensionHalo",
			Size = Vector3.new(5.5, 0.08, 5.5),
			CFrame = CFrame.new(position + Vector3.new(0, 0.12, 0)),
			Color = palette.AccentSoft,
			Material = Enum.Material.Neon,
			Parent = model,
			CanCollide = false,
			Transparency = 0.45,
		})
	end

	local highlight = Instance.new("Highlight")
	highlight.FillTransparency = 1
	highlight.OutlineColor = accent
	highlight.OutlineTransparency = 0.55
	highlight.Adornee = plate
	highlight.Parent = plate

	createPlateTopLabel(plate)
	createStationBillboard(plate)
	registerPadMotion(plate)
	connectOwnedTouch(plate, ownerSlot, touchKey, onTouch)
	return plate
end

local function createBaseStatsBoard(baseModel: Model, platform: Part, slot: number)
	local boardPart = createPart({
		Name = "StatsBoard",
		Size = Vector3.new(9.5, 4.2, 0.15),
		CFrame = platform.CFrame * CFrame.new(BASE_LAYOUT.StatsBoardLocal),
		Color = palette.Panel,
		Material = Enum.Material.SmoothPlastic,
		Parent = baseModel,
		CanCollide = false,
	})

	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Front
	surface.CanvasSize = Vector2.new(380, 168)
	surface.LightInfluence = 0
	surface.Parent = boardPart

	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, 0, 0, 28)
	header.BackgroundColor3 = palette.LaneStripe
	header.BorderSizePixel = 0
	header.Parent = surface

	local headerLabel = Instance.new("TextLabel")
	headerLabel.BackgroundTransparency = 1
	headerLabel.Size = UDim2.fromScale(1, 1)
	headerLabel.Font = fonts.Display
	headerLabel.TextSize = 16
	headerLabel.TextColor3 = palette.PanelEdge
	headerLabel.Text = "BASE STATS"
	headerLabel.Parent = header

	local body = Instance.new("TextLabel")
	body.Name = "StatsText"
	body.Size = UDim2.new(1, 0, 1, -28)
	body.Position = UDim2.fromOffset(0, 28)
	body.BackgroundTransparency = 0.05
	body.BackgroundColor3 = palette.Panel
	body.TextColor3 = palette.TextPrimary
	body.Text = ""
	styleBoardLabel(body, 14)
	body.Parent = surface

	slotStatsLabels[slot] = body
end

local function buildSlotUpgrades(slot: number, baseModel: Model, platform: Part)
	local upgradesFolder = Instance.new("Folder")
	upgradesFolder.Name = "Upgrades"
	upgradesFolder.Parent = baseModel

	slotGeneratorPads[slot] = {}
	slotMultiplierPads[slot] = {}

	for index, generatorId in CosmicConfig.GeneratorOrder do
		local generator = CosmicConfig.Generators[generatorId]
		local localPos = Vector3.new(
			BASE_LAYOUT.TrainingStartX + (index - 1) * BASE_LAYOUT.TrainingSpacing,
			0.75,
			BASE_LAYOUT.TrainingRowZ
		)
		local worldPos = localToWorld(platform, localPos)
		local plate = createTrainingStation(
			upgradesFolder,
			generatorId,
			worldPos,
			generator.Color,
			("gen_%d_%s"):format(slot, generatorId),
			"training",
			slot,
			function(player: Player)
				if CosmicGameService.TryBuyGenerator(player, generatorId) then
					CosmicWorldService.RefreshPlayer(player)
				end
			end
		)
		slotGeneratorPads[slot][generatorId] = plate
	end

	for index, upgradeId in CosmicConfig.MultiplierOrder do
		local upgrade = CosmicConfig.Multipliers[upgradeId]
		local localPos = Vector3.new(
			BASE_LAYOUT.BoostRowX,
			0.75,
			BASE_LAYOUT.BoostStartZ + (index - 1) * BASE_LAYOUT.BoostSpacing
		)
		local worldPos = localToWorld(platform, localPos)
		local plate = createTrainingStation(
			upgradesFolder,
			upgradeId,
			worldPos,
			upgrade.Color,
			("mult_%d_%s"):format(slot, upgradeId),
			"boost",
			slot,
			function(player: Player)
				if CosmicGameService.TryBuyMultiplier(player, upgradeId) then
					CosmicWorldService.RefreshPlayer(player)
				end
			end
		)
		slotMultiplierPads[slot][upgradeId] = plate
	end

	local ascensionPos = localToWorld(platform, BASE_LAYOUT.AscensionLocal)
	slotAscensionPads[slot] = createTrainingStation(
		upgradesFolder,
		"AscensionPad",
		ascensionPos,
		palette.AccentSoft,
		("ascension_%d"):format(slot),
		"ascension",
		slot,
		function(player: Player)
			if CosmicGameService.TryAscension(player) then
				CosmicWorldService.RefreshPlayer(player)
			end
		end
	)

	createBaseStatsBoard(baseModel, platform, slot)

	local function zoneLabel(localPos: Vector3, text: string, color: Color3)
		local marker = createPart({
			Name = text,
			Size = Vector3.new(6, 0.06, 1.4),
			CFrame = platform.CFrame * CFrame.new(localPos),
			Color = color,
			Material = Enum.Material.SmoothPlastic,
			Parent = upgradesFolder,
			CanCollide = false,
			Transparency = 0.15,
		})
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Top
		gui.CanvasSize = Vector2.new(240, 56)
		gui.Parent = marker
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = fonts.Label
		label.TextSize = 14
		label.TextColor3 = palette.TextPrimary
		label.Text = text
		label.Parent = gui
	end

	zoneLabel(Vector3.new(0, 0.12, 16), "TRAINING", palette.LaneStripe)
	zoneLabel(Vector3.new(-18, 0.12, 0), "BOOSTS", palette.Accent)
	zoneLabel(Vector3.new(14, 0.12, 14), "ASCEND", palette.AccentSoft)
end

local function buildAllBaseUpgrades(parent: Instance)
	local basesFolder = parent:WaitForChild("PlayerBases")
	for slot = 1, BASE_SLOTS do
		local baseModel = basesFolder:FindFirstChild(("BaseSlot_%d"):format(slot)) :: Model?
		local platform = baseModel and baseModel:FindFirstChild("Platform") :: Part?
		if baseModel and platform then
			buildSlotUpgrades(slot, baseModel, platform)
		end
	end
end

function CosmicWorldService.Init()
	local existing = Workspace:FindFirstChild("SuperpowerIsland")
	if existing then
		existing:Destroy()
	end

	islandFolder = Instance.new("Folder")
	islandFolder.Name = "SuperpowerIsland"
	islandFolder.Parent = Workspace

	CosmicBaseService.CreateBaseRing(islandFolder)
	buildAllBaseUpgrades(islandFolder)

	CosmicGameService.SetStateChangedCallback(function(player: Player)
		CosmicWorldService.RefreshPlayer(player)
	end)

	local Players = game:GetService("Players")
	Players.PlayerAdded:Connect(function(player: Player)
		task.defer(function()
			CosmicWorldService.RefreshPlayer(player)
		end)
	end)
	for _, player in Players:GetPlayers() do
		CosmicWorldService.RefreshPlayer(player)
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		touchDebounce[player] = nil
	end)
end

return CosmicWorldService
