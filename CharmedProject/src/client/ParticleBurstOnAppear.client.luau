local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local MIN_BURST = 3
local MAX_BURST = 16
local RATE_SCALE = 0.12

local function burstCountFor(emitter: ParticleEmitter): number
	local rate = emitter.Rate
	if rate <= 0 then
		return MIN_BURST
	end
	return math.clamp(math.ceil(rate * RATE_SCALE), MIN_BURST, MAX_BURST)
end

local function tryBurst(emitter: ParticleEmitter)
	task.defer(function()
		if not emitter.Parent then
			return
		end
		pcall(function()
			emitter:Emit(burstCountFor(emitter))
		end)
	end)
end

local function onDescendantAdded(inst: Instance)
	if inst:IsA("ParticleEmitter") then
		tryBurst(inst)
	end
end

Workspace.DescendantAdded:Connect(onDescendantAdded)

local hookedCameras: { [Camera]: boolean } = {}
local function hookCamera(cam: Camera?)
	if not cam or hookedCameras[cam] then
		return
	end
	hookedCameras[cam] = true
	cam.DescendantAdded:Connect(onDescendantAdded)
end

hookCamera(Workspace.CurrentCamera)
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	hookCamera(Workspace.CurrentCamera)
end)

local localPlayer = Players.LocalPlayer
if localPlayer then
	task.defer(function()
		local pg = localPlayer:WaitForChild("PlayerGui", 60)
		if pg then
			pg.DescendantAdded:Connect(onDescendantAdded)
		end
	end)
end
