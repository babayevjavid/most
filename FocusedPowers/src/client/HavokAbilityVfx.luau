--!strict
--[[ Havok local VFX: chest beam, siphon flash, surge trail, burst pulse. ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local HavokConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("HavokConstants"))

local BLUE = HavokConstants.HAVOK_BLUE
local BLUE_SOFT = HavokConstants.HAVOK_BLUE_SOFT
local BLUE_BRIGHT = HavokConstants.HAVOK_BLUE_BRIGHT
local BEAM = HavokConstants.ConcussiveBeam
local BEAM_RANGE = BEAM.RANGE
local AIM_SMOOTH_TAU = BEAM.AIM_SMOOTH_TAU
local BEAM_ORIGIN_OFFSET = Vector3.new(0, 0.2, -0.55)

type BeamPair = {
	core: BasePart,
	mid: BasePart,
	glow: BasePart,
}

local HavokAbilityVfx = {}

local player: Player
local beamFolder: Folder?
local beamPair: BeamPair?
local beamActive = false
local beamPulseTime = 0
local smoothedAimDir = Vector3.new(0, 0, -1)
local aimConn: RBXScriptConnection?
local pulseConn: RBXScriptConnection?
local boundCharacter: Model?
local baseFov: number? = nil

local function isHavok(): boolean
	return player:GetAttribute("SelectedCharacter") == "Havok"
end

local function getChestPart(character: Model): BasePart?
	return character:FindFirstChild("UpperTorso") :: BasePart?
		or character:FindFirstChild("Torso") :: BasePart?
		or character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function beamRaycast(origin: Vector3, direction: Vector3, character: Model): Vector3
	local unit = if direction.Magnitude > 0.01 then direction.Unit else Vector3.new(0, 0, -1)
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { character, beamFolder :: Instance }
	params.FilterType = Enum.RaycastFilterType.Exclude
	local result = workspace:Spherecast(origin, BEAM.HIT_RADIUS * 0.85, unit * BEAM_RANGE, params)
	if result then
		return result.Position
	end
	return origin + unit * BEAM_RANGE
end

local function ensureBeamFolder()
	if beamFolder then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "HavokBeamVfx"
	folder.Parent = workspace
	beamFolder = folder
end

local function clearBeams()
	if aimConn then
		aimConn:Disconnect()
		aimConn = nil
	end
	if pulseConn then
		pulseConn:Disconnect()
		pulseConn = nil
	end
	if beamPair then
		beamPair.core:Destroy()
		beamPair.mid:Destroy()
		beamPair.glow:Destroy()
		beamPair = nil
	end
	beamActive = false
	beamPulseTime = 0
	boundCharacter = nil

	local cam = workspace.CurrentCamera
	if cam and baseFov then
		cam.FieldOfView = baseFov
		baseFov = nil
	end
end

local function getBeamOrigin(chest: BasePart): Vector3
	return chest.Position + chest.CFrame:VectorToWorldSpace(BEAM_ORIGIN_OFFSET)
end

local function getBeamIntensity(character: Model): number
	local value = character:GetAttribute("HavokBeamIntensity")
	if typeof(value) == "number" then
		return math.clamp(value, 0, 1)
	end
	return 0.35
end

local function layoutBeamParts(origin: Vector3, hitPos: Vector3, pulse: number, intensity: number)
	local delta = hitPos - origin
	local length = delta.Magnitude
	if length < 0.05 or not beamPair then
		return
	end
	local mid = origin + delta * 0.5
	local cf = CFrame.lookAt(mid, hitPos)
	local widthPulse = 1 + math.sin(pulse) * BEAM.WIDTH_PULSE * (0.55 + intensity * 0.45)
	local coreW = BEAM.WIDTH_END * widthPulse
	local midW = (BEAM.WIDTH_END + BEAM.WIDTH_START) * 0.5 * widthPulse
	local glowW = BEAM.WIDTH_START * widthPulse * (1.05 + intensity * 0.25)

	beamPair.core.Size = Vector3.new(coreW, coreW, length)
	beamPair.core.CFrame = cf
	beamPair.core.Transparency = 0.08 + (1 - intensity) * 0.12
	beamPair.core.Color = BLUE:Lerp(BLUE_BRIGHT, intensity)

	beamPair.mid.Size = Vector3.new(midW, midW, length)
	beamPair.mid.CFrame = cf
	beamPair.mid.Transparency = 0.22 + (1 - intensity) * 0.15

	beamPair.glow.Size = Vector3.new(glowW, glowW, length)
	beamPair.glow.CFrame = cf
	beamPair.glow.Transparency = 0.38 + (1 - math.abs(math.sin(pulse * 0.5))) * 0.12
end

local function applyBeamDirection(chest: BasePart, dir: Vector3, character: Model, pulse: number, intensity: number)
	if not beamPair then
		return
	end
	local origin = getBeamOrigin(chest)
	local hitPos = beamRaycast(origin, dir, character)
	layoutBeamParts(origin, hitPos, pulse, intensity)
end

local function createBeamPart(name: string, color: Color3, transparency: number): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = transparency
	part.Parent = beamFolder
	return part
end

local function createBeamPair(chest: BasePart, beamDir: Vector3, character: Model): BeamPair
	ensureBeamFolder()

	local pair = {
		core = createBeamPart("HavokBeamCore", BLUE_BRIGHT, 0.1),
		mid = createBeamPart("HavokBeamMid", BLUE, 0.28),
		glow = createBeamPart("HavokBeamGlow", BLUE_SOFT, 0.42),
	}

	beamPair = pair
	local intensity = getBeamIntensity(character)
	applyBeamDirection(chest, beamDir, character, beamPulseTime, intensity)

	return pair
end

local function startBeamPulseLoop(character: Model)
	if pulseConn then
		pulseConn:Disconnect()
	end
	boundCharacter = character

	local cam = workspace.CurrentCamera
	if cam and not baseFov then
		baseFov = cam.FieldOfView
	end

	pulseConn = RunService.RenderStepped:Connect(function(dt)
		if not beamActive or not beamPair or not boundCharacter or not boundCharacter.Parent then
			return
		end
		local chest = getChestPart(boundCharacter)
		if not chest then
			return
		end

		beamPulseTime += dt * BEAM.PULSE_FREQ * math.pi * 2
		local intensity = getBeamIntensity(boundCharacter)
		applyBeamDirection(chest, smoothedAimDir, boundCharacter, beamPulseTime, intensity)

		if cam and baseFov then
			local fovKick = 0.6 + intensity * 1.1 + math.sin(beamPulseTime * 0.5) * 0.35
			cam.FieldOfView = baseFov + fovKick
		end
	end)
end

function HavokAbilityVfx.setBeamActive(character: Model, active: boolean, aimDir: Vector3?)
	if not isHavok() then
		clearBeams()
		return
	end

	if not active then
		clearBeams()
		return
	end

	local chest = getChestPart(character)
	if not chest then
		return
	end

	local dir = if aimDir and aimDir.Magnitude > 0.01 then aimDir.Unit else chest.CFrame.LookVector
	smoothedAimDir = dir

	if not beamPair then
		createBeamPair(chest, smoothedAimDir, character)
		startBeamPulseLoop(character)
	else
		applyBeamDirection(chest, smoothedAimDir, character, beamPulseTime, getBeamIntensity(character))
	end

	beamActive = true
end

function HavokAbilityVfx.startBeamAimSmoothing(character: Model, getAim: () -> Vector3)
	if aimConn then
		aimConn:Disconnect()
	end
	aimConn = RunService.RenderStepped:Connect(function(dt)
		if not beamActive or not beamPair then
			return
		end
		local chest = getChestPart(character)
		if not chest then
			return
		end
		local goal = getAim()
		if goal.Magnitude > 0.01 then
			local alpha = 1 - math.exp(-dt / AIM_SMOOTH_TAU)
			smoothedAimDir = smoothedAimDir:Lerp(goal.Unit, alpha)
		end
	end)
end

function HavokAbilityVfx.stopBeamAimSmoothing()
	if aimConn then
		aimConn:Disconnect()
		aimConn = nil
	end
end

function HavokAbilityVfx.getSmoothedAimDirection(): Vector3
	return smoothedAimDir
end

function HavokAbilityVfx.onHandCast()
	if not isHavok() then
		return
	end
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local fov = cam.FieldOfView
	TweenService:Create(cam, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FieldOfView = fov + 1.5,
	}):Play()
	task.delay(0.12, function()
		if cam.Parent then
			TweenService:Create(cam, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				FieldOfView = fov,
			}):Play()
		end
	end)
end

function HavokAbilityVfx.playSiphonFlash(character: Model)
	if not isHavok() then
		return
	end
	local chest = getChestPart(character)
	if not chest then
		return
	end

	local flash = Instance.new("Part")
	flash.Shape = Enum.PartType.Ball
	flash.Material = Enum.Material.Neon
	flash.Color = BLUE
	flash.Size = Vector3.new(2.8, 2.8, 2.8)
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.CanTouch = false
	flash.Transparency = 0.45
	flash.CFrame = chest.CFrame
	flash.Parent = workspace

	TweenService:Create(
		flash,
		TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(4.5, 4.5, 4.5), Transparency = 1 }
	):Play()
	task.delay(0.3, function()
		if flash.Parent then
			flash:Destroy()
		end
	end)
end

function HavokAbilityVfx.playBlastCast(character: Model)
	HavokAbilityVfx.onHandCast()
end

function HavokAbilityVfx.playSurgeBoost(character: Model, direction: Vector3)
	if not isHavok() then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local dir = if direction.Magnitude > 0.01 then direction.Unit else root.CFrame.LookVector

	local streak = Instance.new("Part")
	streak.Material = Enum.Material.Neon
	streak.Color = BLUE_SOFT
	streak.Anchored = true
	streak.CanCollide = false
	streak.CanQuery = false
	streak.CanTouch = false
	streak.Transparency = 0.35
	streak.Size = Vector3.new(2.2, 2.2, 5)
	streak.CFrame = CFrame.lookAt(root.Position - dir * 2.5, root.Position)
	streak.Parent = workspace

	TweenService:Create(
		streak,
		TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Transparency = 1, Size = Vector3.new(3.5, 3.5, 8) }
	):Play()
	task.delay(0.4, function()
		if streak.Parent then
			streak:Destroy()
		end
	end)
end

function HavokAbilityVfx.playBurstPulse(character: Model)
	if not isHavok() then
		return
	end
	local chest = getChestPart(character)
	if not chest then
		return
	end
	local pulse = Instance.new("Part")
	pulse.Shape = Enum.PartType.Ball
	pulse.Material = Enum.Material.ForceField
	pulse.Color = BLUE
	pulse.Size = Vector3.new(3, 3, 3)
	pulse.Anchored = true
	pulse.CanCollide = false
	pulse.CanQuery = false
	pulse.CanTouch = false
	pulse.Transparency = 0.25
	pulse.CFrame = chest.CFrame
	pulse.Parent = workspace
	TweenService:Create(
		pulse,
		TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(14, 14, 14), Transparency = 1 }
	):Play()
	task.delay(0.5, function()
		if pulse.Parent then
			pulse:Destroy()
		end
	end)
end

function HavokAbilityVfx.start(localPlayer: Player)
	player = localPlayer
	player.CharacterRemoving:Connect(function()
		clearBeams()
	end)
end

return HavokAbilityVfx
