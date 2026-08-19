local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SfxConfig = require(Shared:WaitForChild("SfxConfig"))

local CosmicSfx = {}

local function playSound(soundId: string, volume: number)
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
end

function CosmicSfx.Start()
	local remotes = ReplicatedStorage:WaitForChild("SuperpowerRemotes", 20)
	if not remotes then
		return
	end

	local padFeedback = remotes:WaitForChild("PadFeedback", 10)
	if padFeedback and padFeedback:IsA("RemoteEvent") then
		padFeedback.OnClientEvent:Connect(function(kind: string)
			if kind == "press" then
				playSound(SfxConfig.Press, 0.55)
			end
		end)
	end

	local notify = remotes:WaitForChild("Notify", 10)
	if notify and notify:IsA("RemoteEvent") then
		notify.OnClientEvent:Connect(function(payload: { text: string, tone: string, sfx: string? })
			if payload.sfx == "success" then
				playSound(SfxConfig.Success, 0.48)
			elseif payload.sfx == "fail" then
				playSound(SfxConfig.Fail, 0.42)
			end
		end)
	end
end

return CosmicSfx
