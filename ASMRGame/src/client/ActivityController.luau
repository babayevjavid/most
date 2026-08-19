local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local SoundPlayer = require(script.Parent:WaitForChild("SoundPlayer"))

local ActivityController = {}

local player = Players.LocalPlayer
local satisfactionRemote: RemoteEvent?
local interactRequest: RemoteEvent?

local interactiveParts: { BasePart } = {}
local walkZones: { BasePart } = {}
local lastTriggered: { [BasePart]: number } = {}
local stationScanTimes: { [string]: number } = {}

local COOLDOWNS = {
	Keyboard = 0.1,
	Balloon = 0.05,
	BubbleWrap = 0.08,
	Slime = 0.35,
	Soap = 0.2,
	Fidget = 0.2,
	Switches = 0.45,
	Crinkle = 0.25,
	Sand = 0.15,
	Water = 0.4,
}

local function addSatisfaction(amount: number)
	if satisfactionRemote then
		satisfactionRemote:FireServer(amount)
	end
end

local function requestServerState(part: BasePart)
	if interactRequest then
		interactRequest:FireServer(
			part:GetAttribute("ActivityType"),
			part:GetAttribute("ElementId"),
			part:GetAttribute("StationName")
		)
	end
end

local function spawnPopParticles(position: Vector3, color: Color3)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Position = position
	anchor.Parent = workspace

	local attachment = Instance.new("Attachment")
	attachment.Parent = anchor

	local particles = Instance.new("ParticleEmitter")
	particles.Color = ColorSequence.new(color)
	particles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 0),
	})
	particles.Lifetime = NumberRange.new(0.3, 0.6)
	particles.Speed = NumberRange.new(4, 10)
	particles.SpreadAngle = Vector2.new(180, 180)
	particles.Rate = 0
	particles.Parent = attachment
	particles:Emit(18)
	Debris:AddItem(anchor, 1)
end

local function tweenPart(part: BasePart, goal: { [string]: any }, duration: number?)
	TweenService:Create(part, TweenInfo.new(duration or 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
end

local function isInsideZone(zone: BasePart, point: Vector3): boolean
	local relative = zone.CFrame:PointToObjectSpace(point)
	local half = zone.Size * 0.5
	return math.abs(relative.X) <= half.X
		and math.abs(relative.Y) <= half.Y
		and math.abs(relative.Z) <= half.Z
end

local function getTriggerRadius(part: BasePart): number
	local custom = part:GetAttribute("TriggerRadius")
	if typeof(custom) == "number" then
		return custom
	end
	return math.max(part.Size.X, part.Size.Y, part.Size.Z) * 0.6 + 3.5
end

local function canTrigger(part: BasePart, activityType: string): boolean
	local now = os.clock()
	local last = lastTriggered[part] or 0
	if now - last < (COOLDOWNS[activityType] or 0.2) then
		return false
	end
	lastTriggered[part] = now
	return true
end

local handlers = {
	Keyboard = function(part: BasePart)
		if part:GetAttribute("Pressed") then
			return false
		end
		part:SetAttribute("Pressed", true)
		local restY = part:GetAttribute("RestY") or part.Position.Y
		tweenPart(part, { Position = Vector3.new(part.Position.X, restY - 0.35, part.Position.Z) })
		SoundPlayer.PlayAt("KeyboardClick", part.Position, { volume = 0.55, pitchVariance = 0.12 })
		addSatisfaction(1)
		task.delay(0.1, function()
			if part.Parent then
				tweenPart(part, { Position = Vector3.new(part.Position.X, restY, part.Position.Z) })
				part:SetAttribute("Pressed", false)
			end
		end)
		return true
	end,

	Balloon = function(part: BasePart)
		if part:GetAttribute("Popped") then
			return false
		end
		SoundPlayer.PlayAt("BalloonPop", part.Position, { volume = 0.7, pitchVariance = 0.15 })
		spawnPopParticles(part.Position, part.Color)
		addSatisfaction(2)
		requestServerState(part)
		return true
	end,

	BubbleWrap = function(part: BasePart)
		if part:GetAttribute("Popped") then
			return false
		end
		SoundPlayer.PlayAt("BubblePop", part.Position, { volume = 0.5, pitchVariance = 0.1 })
		spawnPopParticles(part.Position, Color3.fromRGB(200, 220, 255))
		addSatisfaction(1)
		requestServerState(part)
		return true
	end,

	Slime = function(part: BasePart)
		local restSize = part:GetAttribute("RestSize") or part.Size
		local squished = Vector3.new(restSize.X * 1.35, restSize.Y * 0.55, restSize.Z * 1.35)
		tweenPart(part, { Size = squished }, 0.08)
		SoundPlayer.PlayAt("SlimeSquish", part.Position, { volume = 0.6, pitchVariance = 0.2 })
		addSatisfaction(1)
		task.delay(0.15, function()
			if part.Parent then
				tweenPart(part, { Size = restSize }, 0.25)
			end
		end)
		return true
	end,

	Soap = function(part: BasePart)
		if part:GetAttribute("Sliced") then
			return false
		end
		SoundPlayer.PlayAt("SoapCut", part.Position, { volume = 0.55, pitchVariance = 0.08 })
		spawnPopParticles(part.Position + Vector3.new(0, 0.3, 0), part.Color)
		addSatisfaction(2)
		requestServerState(part)
		return true
	end,

	Fidget = function(part: BasePart)
		local restSize = part:GetAttribute("RestSize") or part.Size
		tweenPart(part, { Size = restSize * Vector3.new(0.85, 0.6, 0.85) }, 0.06)
		SoundPlayer.PlayAt("FidgetClick", part.Position, { volume = 0.5, pitchVariance = 0.15 })
		addSatisfaction(1)
		task.delay(0.08, function()
			if part.Parent then
				tweenPart(part, { Size = restSize }, 0.1)
			end
		end)
		return true
	end,

	Switches = function(part: BasePart)
		SoundPlayer.PlayAt("SwitchToggle", part.Position, { volume = 0.45, pitchVariance = 0.05 })
		addSatisfaction(1)
		requestServerState(part)
		return true
	end,

	Crinkle = function(part: BasePart)
		SoundPlayer.PlayAt("Crinkle", part.Position, { volume = 0.65, pitchVariance = 0.25 })
		local original = part.Size
		tweenPart(part, { Size = original + Vector3.new(0.05, 0, 0.15) }, 0.05)
		task.delay(0.06, function()
			if part.Parent then
				tweenPart(part, { Size = original }, 0.08)
			end
		end)
		addSatisfaction(1)
		return true
	end,

	Sand = function(part: BasePart)
		SoundPlayer.PlayAt("SandPour", part.Position, { volume = 0.35, pitchVariance = 0.2 })
		local offset = Vector3.new((math.random() - 0.5) * 0.3, 0.1, (math.random() - 0.5) * 0.3)
		tweenPart(part, { Position = part.Position + offset }, 0.08)
		addSatisfaction(1)
		return true
	end,

	Water = function(part: BasePart)
		local restPos = part:GetAttribute("RestPosition") or part.Position
		SoundPlayer.PlayAt("WaterDrop", part.Position, { volume = 0.4, pitchVariance = 0.15 })
		tweenPart(part, { Position = restPos + Vector3.new(0, -0.4, 0), Transparency = 0.8 }, 0.15)
		addSatisfaction(1)
		task.delay(0.8, function()
			if part.Parent then
				tweenPart(part, { Position = restPos, Transparency = 0.25 }, 0.3)
			end
		end)
		return true
	end,
}

local function tryTriggerPart(part: BasePart, hrp: BasePart): boolean
	local activityType = part:GetAttribute("ActivityType")
	if not activityType or activityType == "WalkZone" then
		return false
	end

	local handler = handlers[activityType]
	if not handler then
		return false
	end

	local distance = (hrp.Position - part.Position).Magnitude
	if distance > getTriggerRadius(part) then
		return false
	end

	if not canTrigger(part, activityType) then
		return false
	end

	return handler(part)
end

local function getPartsInStation(stationName: string): { BasePart }
	local result = {}
	for _, part in interactiveParts do
		if part:GetAttribute("StationName") == stationName then
			table.insert(result, part)
		end
	end
	return result
end

local function scanStationZone(zone: BasePart, hrp: BasePart)
	local stationName = zone:GetAttribute("StationName")
	if not stationName then
		return
	end

	local now = os.clock()
	local lastScan = stationScanTimes[stationName] or 0
	if now - lastScan < 0.12 then
		return
	end
	stationScanTimes[stationName] = now

	local parts = getPartsInStation(stationName)
	table.sort(parts, function(a, b)
		return (hrp.Position - a.Position).Magnitude < (hrp.Position - b.Position).Magnitude
	end)

	local triggered = 0
	for _, part in parts do
		if tryTriggerPart(part, hrp) then
			triggered += 1
		end
		if triggered >= 3 then
			break
		end
	end
end

local function proximityLoop()
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return
	end

	for _, zone in walkZones do
		if isInsideZone(zone, hrp.Position) then
			scanStationZone(zone, hrp)
		end
	end

	for _, part in interactiveParts do
		tryTriggerPart(part, hrp)
	end
end

local function registerPart(part: BasePart)
	if part:GetAttribute("ZoneType") == "Station" then
		table.insert(walkZones, part)
		return
	end

	local activityType = part:GetAttribute("ActivityType")
	if activityType then
		table.insert(interactiveParts, part)
	end
end

function ActivityController.Start()
	local remotes = ReplicatedStorage:WaitForChild("ASMRRemotes", 30)
	if remotes then
		satisfactionRemote = remotes:WaitForChild("SatisfactionUpdate") :: RemoteEvent
		interactRequest = remotes:WaitForChild("InteractRequest") :: RemoteEvent
	end

	local studio = workspace:WaitForChild("ASMRStudio", 30)
	if not studio then
		return
	end

	for _, descendant in studio:GetDescendants() do
		if descendant:IsA("BasePart") then
			registerPart(descendant)
		end
	end

	studio.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			registerPart(descendant)
		end
	end)

	RunService.Heartbeat:Connect(proximityLoop)
end

return ActivityController
