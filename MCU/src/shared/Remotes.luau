--!strict
--[[ Remotes: server creates under ReplicatedStorage.Remotes; clients wait for them. ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

local folder: Folder? = nil
local isServer = RunService:IsServer()

local function getFolder(): Folder
	if folder then
		return folder
	end
	if isServer then
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

	local waited = ReplicatedStorage:WaitForChild("Remotes", 30)
	if waited and waited:IsA("Folder") then
		folder = waited
		return waited
	end
	-- Fallback if server hasn't created yet (Studio edge case)
	local created = Instance.new("Folder")
	created.Name = "Remotes"
	created.Parent = ReplicatedStorage
	folder = created
	return created
end

function Remotes.getEvent(name: string): RemoteEvent
	local parent = getFolder()
	if isServer then
		local existing = parent:FindFirstChild(name)
		if existing and existing:IsA("RemoteEvent") then
			return existing
		end
		if existing then
			existing:Destroy()
		end
		local event = Instance.new("RemoteEvent")
		event.Name = name
		event.Parent = parent
		return event
	end

	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	local waited = parent:WaitForChild(name, 30)
	if waited and waited:IsA("RemoteEvent") then
		return waited
	end
	error(`[Remotes] RemoteEvent "{name}" not found`)
end

function Remotes.getUnreliableEvent(name: string): UnreliableRemoteEvent
	local parent = getFolder()
	if isServer then
		local existing = parent:FindFirstChild(name)
		if existing and existing:IsA("UnreliableRemoteEvent") then
			return existing
		end
		if existing then
			existing:Destroy()
		end
		local event = Instance.new("UnreliableRemoteEvent")
		event.Name = name
		event.Parent = parent
		return event
	end

	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("UnreliableRemoteEvent") then
		return existing
	end
	local waited = parent:WaitForChild(name, 30)
	if waited and waited:IsA("UnreliableRemoteEvent") then
		return waited
	end
	error(`[Remotes] UnreliableRemoteEvent "{name}" not found`)
end

-- Call once from server so clients can WaitForChild immediately
function Remotes.init()
	if not isServer then
		return
	end
	Remotes.getEvent("SelectHero")
	Remotes.getEvent("UseAbility")
	Remotes.getEvent("FlightInput")
	Remotes.getEvent("SprintInput")
	Remotes.getEvent("CameraShake")
	Remotes.getEvent("BeamClash")
	Remotes.getEvent("MindLink")
	Remotes.getEvent("HexDisplacementCam")
	Remotes.getEvent("ProbabilityHexResult")
	Remotes.getEvent("PhoenixRevive")
	Remotes.getEvent("PlayerDataSync")
	Remotes.getEvent("PurchaseShopItem")
	Remotes.getEvent("ShopPurchaseResult")
	Remotes.getEvent("RefreshPlayerData")
	Remotes.getUnreliableEvent("ShieldPartialHit")
end

return Remotes
