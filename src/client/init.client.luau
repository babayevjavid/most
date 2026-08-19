local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local shared = ReplicatedStorage:WaitForChild("Shared", 30)
if not shared then
	warn("[Ragdoll] ReplicatedStorage.Shared missing — sync Rojo.")
	return
end

local ragdollConfigModule = shared:WaitForChild("RagdollConfig", 10)
if not ragdollConfigModule then
	warn("[Ragdoll] RagdollConfig missing in ReplicatedStorage.Shared — add src/shared/RagdollConfig.luau and sync.")
	return
end

local ok, RagdollConfig = pcall(require, ragdollConfigModule)
if not ok or type(RagdollConfig) ~= "table" then
	warn("[Ragdoll] Failed to require RagdollConfig.")
	return
end

local remoteFolder = ReplicatedStorage:WaitForChild("RagdollRemotes", 60)
if not remoteFolder then
	warn("[Ragdoll] RagdollRemotes missing — server should create it; is the server running?")
	return
end

local toggleRemote = remoteFolder:WaitForChild(RagdollConfig.RemoteName, 10)
if not toggleRemote or not toggleRemote:IsA("RemoteEvent") then
	warn("[Ragdoll] RemoteEvent missing: " .. tostring(RagdollConfig.RemoteName))
	return
end

local lastLocalFire = 0.0

local function tryFire()
	local now = os.clock()
	if now - lastLocalFire < RagdollConfig.CooldownSeconds then
		return
	end
	lastLocalFire = now
	local remote = toggleRemote :: RemoteEvent
	remote:FireServer()
end

local function shouldBlockR(): boolean
	return UserInputService:GetFocusedTextBox() ~= nil
end

ContextActionService:BindActionAtPriority(
	"Ragdoll_ToggleR",
	function(_, state)
		if state ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		if shouldBlockR() then
			return Enum.ContextActionResult.Pass
		end
		tryFire()
		return Enum.ContextActionResult.Sink
	end,
	false,
	50000,
	Enum.KeyCode.R
)

print("[Ragdoll] Client loaded — press R to toggle (1s cooldown)")
