local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SoundConfig = require(Shared:WaitForChild("SoundConfig"))

local SoundPlayer = {}

local masterVolume = 0.85

function SoundPlayer.SetVolume(volume: number)
	masterVolume = math.clamp(volume, 0, 1)
end

function SoundPlayer.GetVolume(): number
	return masterVolume
end

local function playSoundId(
	soundId: string,
	volume: number,
	pitch: number,
	parent: Instance,
	rollOffMaxDistance: number?
)
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume
	sound.PlaybackSpeed = math.clamp(pitch, 0.5, 2)
	if rollOffMaxDistance then
		sound.RollOffMaxDistance = rollOffMaxDistance
	end
	sound.Parent = parent
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
		if parent ~= SoundService and parent:IsA("BasePart") then
			parent:Destroy()
		end
	end)
end

function SoundPlayer.Play(
	soundKey: string,
	options: {
		volume: number?,
		pitch: number?,
		pitchVariance: number?,
	}?
)
	local soundId = SoundConfig.pick(soundKey)
	if not soundId then
		return
	end

	local opts = options or {}
	local pitchVariance = opts.pitchVariance or 0.08
	local pitch = (opts.pitch or 1) + (math.random() * 2 - 1) * pitchVariance

	playSoundId(soundId, (opts.volume or 0.6) * masterVolume, pitch, SoundService)
end

function SoundPlayer.PlayAt(
	soundKey: string,
	position: Vector3,
	options: { volume: number?, pitchVariance: number? }?
)
	local soundId = SoundConfig.pick(soundKey)
	if not soundId then
		return
	end

	local opts = options or {}
	local pitchVariance = opts.pitchVariance or 0.1
	local pitch = 1 + (math.random() * 2 - 1) * pitchVariance

	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 1
	part.Size = Vector3.new(0.1, 0.1, 0.1)
	part.Position = position
	part.Parent = workspace

	playSoundId(soundId, (opts.volume or 0.5) * masterVolume, pitch, part, 40)
end

return SoundPlayer
