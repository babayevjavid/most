local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("Theme"))

local GameService = {}

local remotesFolder: Folder
local satisfactionEvent: RemoteEvent
local interactRequest: RemoteEvent

local playerStats: { [Player]: { satisfaction: number } } = {}

local function getStats(player: Player)
	if not playerStats[player] then
		playerStats[player] = { satisfaction = 0 }
	end
	return playerStats[player]
end

local function findInteractivePart(activityType: string, elementId: string, stationName: string): BasePart?
	local studio = workspace:FindFirstChild("ASMRStudio")
	if not studio then
		return nil
	end

	local station = studio:FindFirstChild(stationName)
	if not station then
		return nil
	end

	for _, descendant in station:GetDescendants() do
		if descendant:IsA("BasePart") then
			if descendant:GetAttribute("ActivityType") == activityType
				and descendant:GetAttribute("ElementId") == elementId
			then
				return descendant
			end
		end
	end

	return nil
end

local function onBalloonPop(balloon: BasePart)
	if balloon:GetAttribute("Popped") then
		return
	end
	balloon:SetAttribute("Popped", true)
	balloon.Transparency = 1

	task.delay(4, function()
		if not balloon.Parent then
			return
		end
		local restPos = balloon:GetAttribute("RestPosition")
		if typeof(restPos) == "Vector3" then
			balloon.Position = restPos
		end
		balloon.Transparency = 0
		balloon:SetAttribute("Popped", false)
	end)
end

local function onBubblePop(bubble: BasePart)
	if bubble:GetAttribute("Popped") then
		return
	end
	bubble:SetAttribute("Popped", true)
	bubble.Transparency = 1
end

local function onSoapSlice(soap: BasePart)
	if soap:GetAttribute("Sliced") then
		return
	end
	soap:SetAttribute("Sliced", true)
	soap.Size = Vector3.new(soap.Size.X, soap.Size.Y * 0.3, soap.Size.Z)
end

local function onSwitchToggle(toggle: BasePart)
	local isOn = toggle:GetAttribute("On")
	toggle:SetAttribute("On", not isOn)
	local restPos = toggle:GetAttribute("RestPosition") :: Vector3
	if isOn then
		toggle.Position = restPos + Vector3.new(0, -1.2 * 1.65, 0)
		toggle.Color = Color3.fromRGB(255, 100, 100)
	else
		toggle.Position = restPos
		toggle.Color = Theme.PastelGreen
	end
end

local function createRemotes()
	remotesFolder = Instance.new("Folder")
	remotesFolder.Name = "ASMRRemotes"
	remotesFolder.Parent = ReplicatedStorage

	satisfactionEvent = Instance.new("RemoteEvent")
	satisfactionEvent.Name = "SatisfactionUpdate"
	satisfactionEvent.Parent = remotesFolder

	interactRequest = Instance.new("RemoteEvent")
	interactRequest.Name = "InteractRequest"
	interactRequest.Parent = remotesFolder
end

function GameService.Init()
	createRemotes()

	satisfactionEvent.OnServerEvent:Connect(function(player: Player, amount: number)
		if typeof(amount) ~= "number" or amount < 0 or amount > 5 then
			return
		end
		local stats = getStats(player)
		stats.satisfaction += math.floor(amount)
		satisfactionEvent:FireClient(player, stats.satisfaction)
	end)

	interactRequest.OnServerEvent:Connect(function(
		player: Player,
		activityType: string,
		elementId: string,
		stationName: string
	)
		if typeof(activityType) ~= "string" or typeof(elementId) ~= "string" or typeof(stationName) ~= "string" then
			return
		end

		local part = findInteractivePart(activityType, elementId, stationName)
		if not part then
			return
		end

		if activityType == "Balloon" then
			onBalloonPop(part)
		elseif activityType == "BubbleWrap" then
			onBubblePop(part)
		elseif activityType == "Soap" then
			onSoapSlice(part)
		elseif activityType == "Switches" then
			onSwitchToggle(part)
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		task.defer(function()
			local stats = getStats(player)
			satisfactionEvent:FireClient(player, stats.satisfaction)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		playerStats[player] = nil
	end)
end

return GameService
