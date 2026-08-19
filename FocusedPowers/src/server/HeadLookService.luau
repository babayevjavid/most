--!strict
--[[ Relays head look angles between players. ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HeadLookService = {}

local function getOrCreateRemote(): RemoteEvent
	local existing = ReplicatedStorage:FindFirstChild("HeadLookAngles")
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = "HeadLookAngles"
	remote.Archivable = false
	remote.Parent = ReplicatedStorage
	return remote
end

function HeadLookService.setup()
	local remote = getOrCreateRemote()

	remote.OnServerEvent:Connect(function(plr: Player, pitch: number, yaw: number)
		if type(pitch) ~= "number" or pitch ~= pitch or type(yaw) ~= "number" or yaw ~= yaw then
			return
		end
		pitch = math.clamp(pitch, -1, 1)
		yaw = math.clamp(yaw, -1, 1)
		remote:FireAllClients(plr, pitch, yaw)
	end)
end

return HeadLookService
