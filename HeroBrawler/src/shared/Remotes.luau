--!strict
--[[ Remotes: creates RemoteEvents/Functions under ReplicatedStorage.Remotes ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {}

local folder: Folder? = nil

local function getFolder(): Folder
	if folder then
		return folder
	end
	local existing = ReplicatedStorage:FindFirstChild("Remotes")
	if existing and existing:IsA("Folder") then
		folder = existing
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = "Remotes"
	created.Parent = ReplicatedStorage
	folder = created
	return created
end

function Remotes.getEvent(name: string): RemoteEvent
	local parent = getFolder()
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	local event = Instance.new("RemoteEvent")
	event.Name = name
	event.Parent = parent
	return event
end

return Remotes
