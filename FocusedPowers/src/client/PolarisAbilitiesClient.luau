--!strict
--[[ Polaris client: F flight, E ferrokinesis, C magnetic pulse, Q orbital, T metal lance. ]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AbilityGateHelper = require(Shared:WaitForChild("AbilityGateHelper"))
local PolarisConstants = require(Shared:WaitForChild("PolarisConstants"))

local ClientSettings = require(script.Parent:WaitForChild("ClientSettings"))
local MetallicTargetingHelper = require(script.Parent:WaitForChild("MetallicTargetingHelper"))
local PolarisAbilityAnimations = require(script.Parent:WaitForChild("PolarisAbilityAnimations"))
local PolarisAbilityVfx = require(script.Parent:WaitForChild("PolarisAbilityVfx"))
local PolarisHighlight = require(script.Parent:WaitForChild("PolarisHighlight"))
local PolarisLockOn = require(script.Parent:WaitForChild("PolarisLockOn"))

local FLIGHT = PolarisConstants.MagneticFlight
local FERRO = PolarisConstants.Ferrokinesis
local PULSE = PolarisConstants.MagneticPulse
local ORBITAL = PolarisConstants.OrbitalStrikes
local LANCE = PolarisConstants.MetalLance

local HOVER_INTERVAL = 0.05
local SHARD_HIGHLIGHT_INTERVAL = 0.12
local FLIGHT_INPUT_INTERVAL = 0.033

local PolarisAbilitiesClient = {}

local function getMouseWorldPoint(camera: Camera, character: Model): Vector3
	local mousePos = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)
	local rp = RaycastParams.new()
	rp.FilterDescendantsInstances = { character }
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local result = workspace:Raycast(ray.Origin, ray.Direction * 1000, rp)
	if result then
		return result.Position
	end
	return ray.Origin + ray.Direction * 500
end

local function getBoltOrigin(character: Model): Vector3
	local head = character:FindFirstChild("Head") :: BasePart?
	if head then
		return (head.CFrame * CFrame.new(0, 0, -2)).Position
	end
	return character:GetPivot().Position
end

local function getAimDirection(character: Model, camera: Camera): Vector3
	local origin = getBoltOrigin(character)
	local target = getMouseWorldPoint(camera, character)
	local dir = target - origin
	if dir.Magnitude < 0.01 then
		return camera.CFrame.LookVector.Unit
	end
	return dir.Unit
end

local function setLockOnTarget(adornee: Instance?)
	if not ClientSettings.isLockOnEnabled() then
		PolarisLockOn.clear()
		return
	end
	PolarisLockOn.setTarget(adornee)
end

function PolarisAbilitiesClient.start(
	flightToggle: RemoteEvent,
	flightInput: RemoteEvent,
	ferroRequest: RemoteEvent,
	ferroUpdate: RemoteEvent,
	ferroThrow: RemoteEvent,
	ferroEnd: RemoteEvent,
	pulseStart: RemoteEvent,
	pulseAim: RemoteEvent,
	pulseRelease: RemoteEvent,
	orbitalToggle: RemoteEvent,
	orbitalThrow: RemoteEvent,
	orbitalAim: RemoteEvent,
	lanceStart: RemoteEvent,
	lanceLaunch: RemoteEvent,
	lanceEnd: RemoteEvent,
	player: Player,
	setAbilityPressed: ((key: string, pressed: boolean) -> ())?
)
	PolarisAbilityAnimations.start(player)
	PolarisAbilityVfx.start(player)

	local lastFToggle = 0
	local fWasDown = false
	local lastEState = false
	local lastUpdateSend = 0
	local targetHoldDistance = FERRO.HOLD_DISTANCE_MAX * 0.5
	local throwKeyPressed = false
	local lastQToggle = 0
	local qWasDown = false
	local tWasDown = false
	local lastOrbitalThrow = 0
	local lastOrbitalAim = 0
	local lmbWasDown = false
	local pulseSteering = false
	local lastPulseAim = 0
	local wasFlying = false
	local mutedFootstepSounds: { Sound } = {}
	local lastHoverCheck = 0
	local lastShardHighlight = 0
	local lastFlightInputSend = 0
	local lastFlightMove = Vector3.zero
	local lastFlightLook = Vector3.zero
	local cachedFerroHover: BasePart? = nil
	local cachedLanceHover: Model? = nil

	local function setFootstepsMuted(character: Model, muted: boolean)
		for _, sound in mutedFootstepSounds do
			if sound.Parent then
				sound.Volume = if muted then 0 else (sound:GetAttribute("PolarisOrigVolume") or 0.5)
			end
		end
		table.clear(mutedFootstepSounds)
		if not muted then
			return
		end
		for _, inst in character:GetDescendants() do
			if inst:IsA("Sound") then
				local nameLower = string.lower(inst.Name)
				if nameLower:find("foot") or nameLower == "running" or nameLower:find("walk") then
					if inst:GetAttribute("PolarisOrigVolume") == nil then
						inst:SetAttribute("PolarisOrigVolume", inst.Volume)
					end
					inst.Volume = 0
					table.insert(mutedFootstepSounds, inst)
				end
			end
		end
	end

	local function updateShardHighlights(character: Model, now: number)
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root or now - lastShardHighlight < SHARD_HIGHLIGHT_INTERVAL then
			return
		end
		lastShardHighlight = now
		for _, inst in CollectionService:GetTagged("PolarisMetalShard") do
			if inst:IsA("BasePart") then
				local near = (inst.Position - root.Position).Magnitude <= 60
				PolarisHighlight.setShard(inst, near)
			end
		end
	end

	ClientSettings.onLockOnChanged(function(enabled)
		if not enabled then
			PolarisLockOn.clear()
		end
	end)

	UserInputService.InputChanged:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseWheel then
			return
		end
		local char = player.Character
		if not char or char:GetAttribute("IsFerrokinesisActive") ~= true then
			return
		end
		if char:GetAttribute("FerrokinesisAmbientMode") == true then
			return
		end
		targetHoldDistance = math.clamp(
			targetHoldDistance + input.Position.Z * FERRO.SCROLL_STEP,
			FERRO.HOLD_DISTANCE_MIN,
			FERRO.HOLD_DISTANCE_MAX
		)
		char:SetAttribute("FerrokinesisHoldDistance", targetHoldDistance)
	end)

	RunService.Heartbeat:Connect(function()
		if not AbilityGateHelper.isPolaris(player) then
			PolarisHighlight.clearAll()
			PolarisLockOn.clear()
			fWasDown = false
			lastEState = false
			qWasDown = false
			tWasDown = false
			pulseSteering = false
			wasFlying = false
			cachedFerroHover = nil
			cachedLanceHover = nil
			return
		end

		local char = player.Character
		local cam = workspace.CurrentCamera
		if not char or not cam then
			PolarisHighlight.clearAll()
			PolarisLockOn.clear()
			return
		end

		local now = tick()
		local lmbDown = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
		local cDown = UserInputService:IsKeyDown(Enum.KeyCode.C)
		local flying = char:GetAttribute("IsMagneticFlying") == true
		local isFerroActive = char:GetAttribute("IsFerrokinesisActive") == true
		local orbitalActive = char:GetAttribute("IsOrbitalStrikesActive") == true
		local lanceActive = char:GetAttribute("IsMetalLanceActive") == true
		local lanceArmed = char:GetAttribute("MetalLanceArmed") == true

		if flying and not wasFlying then
			PolarisHighlight.setFlight(char)
			setFootstepsMuted(char, true)
		elseif not flying and wasFlying then
			PolarisHighlight.setFlight(nil)
			setFootstepsMuted(char, false)
		end
		wasFlying = flying

		if orbitalActive or (lanceActive and not flying) then
			updateShardHighlights(char, now)
		end

		-- F: Magnetic Flight
		local fDown = UserInputService:IsKeyDown(Enum.KeyCode.F)
		if fDown and not fWasDown and now - lastFToggle >= FLIGHT.TOGGLE_DEBOUNCE then
			lastFToggle = now
			if flying then
				flightToggle:FireServer(false)
				if setAbilityPressed then
					setAbilityPressed("F", false)
				end
			elseif AbilityGateHelper.canUse(player, char, FLIGHT.ABILITY_ID) then
				flightToggle:FireServer(true)
				if setAbilityPressed then
					setAbilityPressed("F", true)
				end
			end
		end
		fWasDown = fDown

		if flying then
			if setAbilityPressed then
				setAbilityPressed("F", true)
			end
			local look = cam.CFrame.LookVector.Unit
			local right = cam.CFrame.RightVector.Unit
			local wDown = UserInputService:IsKeyDown(Enum.KeyCode.W)
			local sDown = UserInputService:IsKeyDown(Enum.KeyCode.S)
			local aDown = UserInputService:IsKeyDown(Enum.KeyCode.A)
			local dDown = UserInputService:IsKeyDown(Enum.KeyCode.D)
			local moveDir = look * ((if wDown then 1 else 0) - (if sDown then 1 else 0))
				+ right * ((if dDown then 1 else 0) - (if aDown then 1 else 0))
			if moveDir.Magnitude > 1 then
				moveDir = moveDir.Unit
			elseif moveDir.Magnitude < 0.01 then
				moveDir = Vector3.zero
			end
			local changed = (moveDir - lastFlightMove).Magnitude > 0.008
				or (look - lastFlightLook).Magnitude > 0.008
			if changed then
				lastFlightMove = moveDir
				lastFlightLook = look
				flightInput:FireServer(moveDir.X, moveDir.Y, moveDir.Z, look.X, look.Y, look.Z)
			end
		end

		-- E: Ferrokinesis
		local eHeld = UserInputService:IsKeyDown(Enum.KeyCode.E)
		if setAbilityPressed then
			setAbilityPressed("E", eHeld or isFerroActive)
		end

		if eHeld and not lastEState and not isFerroActive then
			if AbilityGateHelper.canUse(player, char, FERRO.ABILITY_ID) then
				local target = MetallicTargetingHelper.getTargetPartAtCursor(char, FERRO.RAYCAST_MAX_DIST)
				ferroRequest:FireServer(target)
			end
		elseif not eHeld and lastEState and isFerroActive then
			ferroEnd:FireServer()
		end
		lastEState = eHeld

		if isFerroActive then
			local aim = getAimDirection(char, cam)
			if now - lastUpdateSend >= FERRO.UPDATE_SEND_INTERVAL then
				lastUpdateSend = now
				ferroUpdate:FireServer(aim.X, aim.Y, aim.Z, targetHoldDistance)
			end
			local isAmbient = char:GetAttribute("FerrokinesisAmbientMode") == true
			if isAmbient then
				PolarisHighlight.setHeld(nil)
			else
				local heldRef = char:FindFirstChild("FerrokinesisHeldRoot")
				if heldRef and heldRef:IsA("ObjectValue") and heldRef.Value and heldRef.Value:IsA("BasePart") then
					PolarisHighlight.setHeld(MetallicTargetingHelper.getHighlightAdornee(heldRef.Value))
				end
			end
			PolarisLockOn.clear()
		else
			if not flying and now - lastHoverCheck >= HOVER_INTERVAL then
				lastHoverCheck = now
				cachedFerroHover = MetallicTargetingHelper.getTargetPartAtCursor(char, FERRO.RAYCAST_MAX_DIST)
				cachedLanceHover = if not flying
					then MetallicTargetingHelper.getHumanoidTargetAtCursor(char, LANCE.TARGET_MAX_DIST)
					else nil
			end

			local ferroHover = cachedFerroHover
			local lanceHover = cachedLanceHover

			if lanceActive and lanceArmed and lanceHover then
				PolarisHighlight.setHover(lanceHover)
				setLockOnTarget(lanceHover)
			elseif ferroHover then
				local adornee = MetallicTargetingHelper.getHighlightAdornee(ferroHover)
				PolarisHighlight.setHover(adornee)
				setLockOnTarget(adornee)
			elseif lanceHover then
				PolarisHighlight.setHover(lanceHover)
				setLockOnTarget(lanceHover)
			else
				PolarisHighlight.setHover(nil)
				if not lanceActive then
					PolarisLockOn.clear()
				end
			end
			if not isFerroActive then
				PolarisHighlight.setHeld(nil)
			end
		end

		if lanceActive and lanceArmed and lmbDown and not lmbWasDown then
			local launchTarget = MetallicTargetingHelper.getHumanoidTargetAtCursor(char, LANCE.TARGET_MAX_DIST)
			if launchTarget then
				PolarisAbilityAnimations.playHandCast()
				PolarisAbilityVfx.onHandCast()
				lanceLaunch:FireServer(launchTarget)
			end
		elseif isFerroActive and lmbDown and not throwKeyPressed then
			PolarisAbilityAnimations.playFerroThrow()
			PolarisAbilityVfx.onFerrokinesisThrow()
			local world = getMouseWorldPoint(cam, char)
			if char:GetAttribute("FerrokinesisAmbientMode") == true then
				ferroThrow:FireServer(world.X, world.Y, world.Z)
			else
				ferroThrow:FireServer()
			end
		end
		throwKeyPressed = lmbDown

		-- C: Magnetic Pulse (hold to fire + steer with mouse)
		local pulseInput = cDown
		local canPulse = AbilityGateHelper.canUse(player, char, PULSE.ABILITY_ID)

		if pulseInput and not pulseSteering and canPulse then
			local aim = getAimDirection(char, cam)
			PolarisAbilityAnimations.playHandCast()
			PolarisAbilityVfx.onHandCast()
			pulseStart:FireServer(aim.X, aim.Y, aim.Z)
			pulseSteering = true
			lastPulseAim = now
			if setAbilityPressed then
				setAbilityPressed("C", true)
			end
		elseif not pulseInput and pulseSteering then
			pulseRelease:FireServer()
			pulseSteering = false
			if setAbilityPressed then
				setAbilityPressed("C", false)
			end
		end

		if pulseSteering and pulseInput and now - lastPulseAim >= PULSE.AIM_INTERVAL then
			lastPulseAim = now
			local aim = getAimDirection(char, cam)
			pulseAim:FireServer(aim.X, aim.Y, aim.Z)
		end

		if not pulseSteering and setAbilityPressed and not cDown then
			setAbilityPressed("C", false)
		end

		-- Q: Orbital Strikes
		local qDown = UserInputService:IsKeyDown(Enum.KeyCode.Q)
		if qDown and not qWasDown and now - lastQToggle >= 0.35 then
			lastQToggle = now
			if orbitalActive or AbilityGateHelper.canUse(player, char, ORBITAL.ABILITY_ID) then
				orbitalToggle:FireServer()
			end
		end
		qWasDown = qDown
		if setAbilityPressed then
			setAbilityPressed("Q", orbitalActive)
		end

		if orbitalActive and not flying then
			local world = getMouseWorldPoint(cam, char)
			if now - lastOrbitalAim >= 0.05 then
				lastOrbitalAim = now
				orbitalAim:FireServer(world.X, world.Y, world.Z)
			end
			if not lanceArmed and lmbDown then
				if not lmbWasDown or now - lastOrbitalThrow >= ORBITAL.THROW_INTERVAL then
					lastOrbitalThrow = now
					PolarisAbilityAnimations.playHandCast()
					PolarisAbilityVfx.onHandCast()
					local world = getMouseWorldPoint(cam, char)
					orbitalThrow:FireServer(world.X, world.Y, world.Z)
				end
			end
		end
		lmbWasDown = lmbDown

		-- T: Metal Lance — press to arm spike nearby, LMB to launch, T again to cancel
		local tDown = UserInputService:IsKeyDown(Enum.KeyCode.T)
		if tDown and not tWasDown and not flying then
			if lanceActive and lanceArmed then
				lanceEnd:FireServer()
				PolarisHighlight.setHeld(nil)
				PolarisLockOn.clear()
				if setAbilityPressed then
					setAbilityPressed("T", false)
				end
			elseif not lanceActive and AbilityGateHelper.canUse(player, char, LANCE.ABILITY_ID) then
				lanceStart:FireServer()
				if setAbilityPressed then
					setAbilityPressed("T", true)
				end
			end
		end

		if lanceActive then
			if setAbilityPressed then
				setAbilityPressed("T", true)
			end
			local targetRef = char:FindFirstChild("MetalLanceTarget")
			if targetRef and targetRef:IsA("ObjectValue") and targetRef.Value and targetRef.Value:IsA("Model") then
				setLockOnTarget(targetRef.Value)
				if lanceArmed then
					PolarisHighlight.setHeld(targetRef.Value)
				end
			end
		end

		tWasDown = tDown
	end)
end

return PolarisAbilitiesClient
