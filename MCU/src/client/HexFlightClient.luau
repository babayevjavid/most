--!strict

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConstants = require(ReplicatedStorage.Shared.GameConstants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local CameraShakeClient = require(script.Parent.CameraShakeClient)

local HexFlightClient = {}

local DEFAULT_FOV = 70
local FLIGHT_FOV_FAST = 80 -- full-speed flight
local FLIGHT_FOV_LERP = 5.5 -- camera follows speed blend
local MAX_CAMERA_ROLL = math.rad(1.2)
local CHAR_ROLL_TO_CAMERA = 0.12

local function getFullCameraMove(controls: any?): (Vector3, Vector3, number)
	local camera = workspace.CurrentCamera
	if not camera then
		return Vector3.zero, Vector3.new(0, 0, -1), 0
	end
	local look = camera.CFrame.LookVector
	local right = camera.CFrame.RightVector

	local w = if UserInputService:IsKeyDown(Enum.KeyCode.W) then 1 else 0
	local s = if UserInputService:IsKeyDown(Enum.KeyCode.S) then 1 else 0
	local a = if UserInputService:IsKeyDown(Enum.KeyCode.A) then 1 else 0
	local d = if UserInputService:IsKeyDown(Enum.KeyCode.D) then 1 else 0

	local sideInput = d - a
	local keyboardMove = look * (w - s) + right * sideInput
	local moveDir = keyboardMove
	if controls and UserInputService.TouchEnabled and keyboardMove.Magnitude < 0.01 then
		local inputMove = controls:GetMoveVector()
		moveDir = right * inputMove.X + look * -inputMove.Z
		sideInput = math.clamp(inputMove.X, -1, 1)
	end
	if moveDir.Magnitude > 1 then
		moveDir = moveDir.Unit
	end
	return moveDir, look, sideInput
end

local function getCharacterRoll(character: Model): number
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return 0
	end
	local _, _, roll = root.CFrame:ToEulerAnglesYXZ()
	return roll
end

local function silenceWalkSounds(character: Model)
	for _, desc in character:GetDescendants() do
		if desc:IsA("Sound") then
			local name = string.lower(desc.Name)
			if name == "running" or name == "climbing" or name:find("run", 1, true) or name:find("walk", 1, true) then
				if desc.Playing or desc.IsPlaying then
					desc:Stop()
				end
				desc.Volume = 0
			end
		end
	end
end

local function findAnimate(character: Model): LocalScript?
	local direct = character:FindFirstChild("Animate")
	if direct and direct:IsA("LocalScript") then
		return direct
	end
	return nil
end

local function getAnimator(humanoid: Humanoid): Animator?
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		return animator
	end
	local created = Instance.new("Animator")
	created.Parent = humanoid
	return created
end

local function loadTrack(animator: Animator, assetId: string): AnimationTrack?
	local anim = Instance.new("Animation")
	anim.AnimationId = assetId
	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	anim:Destroy()
	if ok and track then
		track.Looped = true
		return track
	end
	return nil
end

function HexFlightClient.init(player: Player)
	local flightInput = Remotes.getEvent("FlightInput")
	local controls: any = nil
	pcall(function()
		local playerModule = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
		controls = playerModule:GetControls()
	end)
	local cameraRoll = 0
	local flightFovBlend = 0
	local fovBase = DEFAULT_FOV
	local flightFeelOn = false

	local idleTrack: AnimationTrack? = nil
	local moveTrack: AnimationTrack? = nil
	local currentMode: "none" | "idle" | "move" = "none"
	local boundCharacter: Model? = nil
	local boundLook: any = nil
	local animateWasDisabled: boolean? = nil

	local function stopFlightAnims()
		if idleTrack then
			idleTrack:Stop(0.15)
		end
		if moveTrack then
			moveTrack:Stop(0.15)
		end
		currentMode = "none"
	end

	local function clearTracks()
		stopFlightAnims()
		if idleTrack then
			idleTrack:Destroy()
			idleTrack = nil
		end
		if moveTrack then
			moveTrack:Destroy()
			moveTrack = nil
		end
		boundCharacter = nil
		boundLook = nil
	end

	local function ensureTracks(character: Model)
		local look = character:GetAttribute(GameConstants.LOOK_MODE_ATTRIBUTE)
		if boundCharacter == character and boundLook == look then
			return
		end
		clearTracks()
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			boundCharacter = character
			boundLook = look
			return
		end
		local animator = getAnimator(humanoid)
		if not animator then
			boundCharacter = character
			boundLook = look
			return
		end
		local heroId = character:GetAttribute(GameConstants.HERO_ATTRIBUTE)
		local idleId = GameConstants.FLIGHT_IDLE_ANIM
		local moveId = GameConstants.FLIGHT_MOVE_ANIM
		if heroId == "captain_marvel" then
			idleId = GameConstants.PHOTON_FLIGHT_IDLE_ANIM
			moveId = GameConstants.PHOTON_FLIGHT_MOVE_ANIM
		elseif heroId == "jean_grey" then
			idleId = GameConstants.JEAN_FLIGHT_IDLE_ANIM
			moveId = GameConstants.JEAN_FLIGHT_MOVE_ANIM
		elseif heroId == "invisible_woman" then
			local look = character:GetAttribute(GameConstants.LOOK_MODE_ATTRIBUTE)
			if look == "modern" then
				idleId = GameConstants.MG_FLIGHT_IDLE_ANIM
				moveId = GameConstants.MG_FLIGHT_MOVE_ANIM
			else
				idleId = GameConstants.IW_BASE_FLIGHT_IDLE_ANIM
				moveId = GameConstants.IW_BASE_FLIGHT_MOVE_ANIM
			end
		end
		idleTrack = loadTrack(animator, idleId)
		moveTrack = loadTrack(animator, moveId)
		if idleTrack then
			idleTrack.Priority = Enum.AnimationPriority.Action
		end
		if moveTrack then
			moveTrack.Priority = Enum.AnimationPriority.Action
		end
		boundCharacter = character
		boundLook = look
	end

	local function setFlightAnim(mode: "idle" | "move")
		if currentMode == mode then
			return
		end
		if mode == "idle" then
			if moveTrack and moveTrack.IsPlaying then
				moveTrack:Stop(0.2)
			end
			if idleTrack and not idleTrack.IsPlaying then
				idleTrack:Play(0.2)
			end
		else
			if idleTrack and idleTrack.IsPlaying then
				idleTrack:Stop(0.2)
			end
			if moveTrack and not moveTrack.IsPlaying then
				moveTrack:Play(0.2)
			end
		end
		currentMode = mode
	end

	player.CharacterRemoving:Connect(function(character)
		if animateWasDisabled ~= nil then
			local animate = character:FindFirstChild("Animate")
			if animate and (animate:IsA("LocalScript") or animate:IsA("Script")) then
				animate.Disabled = animateWasDisabled
			end
		end
		clearTracks()
		animateWasDisabled = nil
		cameraRoll = 0
		fovBase = DEFAULT_FOV
		local cam = workspace.CurrentCamera
		if cam then
			cam.FieldOfView = DEFAULT_FOV
		end
	end)

	player.CharacterAdded:Connect(function()
		clearTracks()
		animateWasDisabled = nil
		cameraRoll = 0
		fovBase = DEFAULT_FOV
		local cam = workspace.CurrentCamera
		if cam then
			cam.FieldOfView = DEFAULT_FOV
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		local character = player.Character
		local camera = workspace.CurrentCamera
		if not character or not camera then
			return
		end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end

		-- Marvel Girl astral owns camera/FOV while projected
		if character:GetAttribute(GameConstants.MG_ASTRAL_BODY_ATTRIBUTE) == true then
			return
		end

		local isFlying = character:GetAttribute(GameConstants.IS_FLYING_ATTRIBUTE) == true
		local isIceSliding = character:GetAttribute(GameConstants.ICE_SLIDE_ATTRIBUTE) == true
		if isIceSliding and not isFlying then
			-- Same WASD→camera move stream as flight; IceSlide uses FlightInput on the server
			local moveDir, look, sideInput = getFullCameraMove(controls)
			flightInput:FireServer({
				moveVector = moveDir,
				lookVector = look,
				sideInput = sideInput,
			})
		end
		if isFlying then
			ensureTracks(character)
			silenceWalkSounds(character)

			local animate = findAnimate(character)
			if animate and animateWasDisabled == nil then
				animateWasDisabled = animate.Disabled
				animate.Disabled = true
			end

			local moveDir, look, sideInput = getFullCameraMove(controls)
			flightInput:FireServer({
				moveVector = moveDir,
				lookVector = look,
				sideInput = sideInput,
			})

			-- Switch idle/move as soon as WASD is pressed or released (ignore coasting speed)
			local moving = moveDir.Magnitude > GameConstants.FLIGHT_ANIM_MOVE_THRESHOLD
			setFlightAnim(if moving then "move" else "idle")

			-- FOV follows current flight speed, plus ability punch (barrage / absorb / disintegrate)
			local root = character:FindFirstChild("HumanoidRootPart")
			local heroId = character:GetAttribute(GameConstants.HERO_ATTRIBUTE)
			local alpha = character:GetAttribute(GameConstants.FLIGHT_ALPHA_ATTRIBUTE)
			local speedAlpha = if type(alpha) == "number" then alpha else 0
			local maxSpeed = if heroId == "captain_marvel"
				then GameConstants.PHOTON_FLIGHT_SPEED
				else GameConstants.FLIGHT_SPEED
			local spd = 0
			if root and root:IsA("BasePart") then
				spd = root.AssemblyLinearVelocity.Magnitude
			end
			local speedT = math.clamp(spd / math.max(maxSpeed, 1), 0, 1)
			-- FOV tracks speed only (not idle/move anim). Slow the blend on decel so it eases back to 70.
			local blendRate = if speedT < flightFovBlend then 3.1 else 4.6
			flightFovBlend += (speedT - flightFovBlend) * math.clamp(dt * blendRate, 0, 1)
			local targetFov = DEFAULT_FOV + (FLIGHT_FOV_FAST - DEFAULT_FOV) * flightFovBlend
			local abilityBoost = 0
			if character:GetAttribute("BarrageSpinActive") == true
				or character:GetAttribute("AbsorbActive") == true
				or character:GetAttribute(GameConstants.DISINTEGRATE_ACTIVE_ATTRIBUTE) == true
			then
				abilityBoost = GameConstants.ABILITY_FOV_BOOST
			end
			targetFov += abilityBoost
			if not CameraShakeClient.isAbilityZoomEnabled() then
				targetFov = DEFAULT_FOV
			end
			fovBase += (targetFov - fovBase) * math.clamp(dt * FLIGHT_FOV_LERP, 0, 1)
			camera.FieldOfView = fovBase + CameraShakeClient.getFovPunch()

			if heroId == "jean_grey" or heroId == "scarlet_witch" or heroId == "invisible_woman" then
				flightFeelOn = true
				CameraShakeClient.setHeldLayer("flight", true, {
					fade = 0.05,
					shake = 0.02 + flightFovBlend * 0.08,
					fov = flightFovBlend * 2.4,
					vignette = 0.92 - flightFovBlend * 0.38,
					shakeRange = 1.15,
					shakeSlow = 0.72,
				})
			end

			local charRoll = getCharacterRoll(character)
			local targetRoll = math.clamp(charRoll * CHAR_ROLL_TO_CAMERA, -MAX_CAMERA_ROLL, MAX_CAMERA_ROLL)
			cameraRoll += (targetRoll - cameraRoll) * math.clamp(dt * 4, 0, 1)

			local offsetTarget = Vector3.new(0, 0.04 + speedAlpha * 0.08, 0)
			humanoid.CameraOffset = humanoid.CameraOffset:Lerp(offsetTarget, math.clamp(dt * 5, 0, 1))
		else
			if currentMode ~= "none" then
				stopFlightAnims()
			end
			if flightFeelOn then
				flightFeelOn = false
				CameraShakeClient.setHeldLayer("flight", false, { fade = 0.35 })
			end
			flightFovBlend += (0 - flightFovBlend) * math.clamp(dt * 6, 0, 1)
			if animateWasDisabled ~= nil then
				local animate = findAnimate(character)
				if animate then
					animate.Disabled = animateWasDisabled
				end
				animateWasDisabled = nil
			end
			cameraRoll += (0 - cameraRoll) * math.clamp(dt * 8, 0, 1)
			local groundFov = DEFAULT_FOV
			if CameraShakeClient.isAbilityZoomEnabled() then
				if character:GetAttribute("BarrageSpinActive") == true
					or character:GetAttribute("AbsorbActive") == true
					or character:GetAttribute(GameConstants.DISINTEGRATE_ACTIVE_ATTRIBUTE) == true
				then
					groundFov += GameConstants.ABILITY_FOV_BOOST
				end
			end
			fovBase += (groundFov - fovBase) * math.clamp(dt * 6, 0, 1)
			camera.FieldOfView = fovBase + CameraShakeClient.getFovPunch()
			if humanoid.CameraOffset.Magnitude > 0.01 then
				humanoid.CameraOffset = humanoid.CameraOffset:Lerp(Vector3.zero, math.clamp(dt * 8, 0, 1))
			end
		end
	end)

	RunService:BindToRenderStep("MCU_HexFlightCameraRoll", Enum.RenderPriority.Camera.Value + 1, function()
		if math.abs(cameraRoll) < 0.0001 then
			return
		end
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		camera.CFrame = camera.CFrame * CFrame.Angles(0, 0, cameraRoll)
	end)
end

return HexFlightClient
