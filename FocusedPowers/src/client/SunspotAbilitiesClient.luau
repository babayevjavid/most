--!strict
--[[ Sunspot client: F flight, E sun uppercut, C photosynthesis, Q solar flare, Z black sun. ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AbilityGateHelper = require(Shared:WaitForChild("AbilityGateHelper"))
local SunspotConstants = require(Shared:WaitForChild("SunspotConstants"))

local SunspotAbilityVfx = require(script.Parent:WaitForChild("SunspotAbilityVfx"))
local SunspotAbilityAnimations = require(script.Parent:WaitForChild("SunspotAbilityAnimations"))

local FLIGHT = SunspotConstants.SolarFlight
local FLARE = SunspotConstants.SolarFlare
local UPPERCUT = SunspotConstants.SunUppercut
local PHOTO = SunspotConstants.Photosynthesis
local BLACK_SUN = SunspotConstants.BlackSun

local MIN_THROW_CHARGE = 0.12

local SunspotAbilitiesClient = {}

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

function SunspotAbilitiesClient.start(
	flightToggle: RemoteEvent,
	flightInput: RemoteEvent,
	sunUppercut: RemoteEvent,
	flareStart: RemoteEvent,
	flareAim: RemoteEvent,
	flareRelease: RemoteEvent,
	photosynthesis: RemoteEvent,
	blackSunCharge: RemoteEvent,
	blackSunThrow: RemoteEvent,
	player: Player,
	setAbilityPressed: ((key: string, pressed: boolean) -> ())?,
	setAbilityCharge: ((key: string, ratio: number) -> ())?
)
	SunspotAbilityVfx.start(player)
	SunspotAbilityAnimations.start(player)

	local lastFToggle = 0
	local fWasDown = false
	local eWasDown = false
	local cWasDown = false
	local qWasDown = false
	local zWasDown = false
	local lmbWasDown = false
	local photoHolding = false
	local photoActive = false
	local blackSunCharging = false
	local blackSunPending = false
	local blackSunPendingUntil = 0
	local flareSteering = false
	local lastFlareAim = 0
	local wasFlying = false
	local lastFlightMove = Vector3.zero
	local lastFlightLook = Vector3.zero
	local mutedFootstepSounds: { Sound } = {}

	local function setFootstepsMuted(character: Model, muted: boolean)
		for _, sound in mutedFootstepSounds do
			if sound.Parent then
				sound.Volume = if muted then 0 else (sound:GetAttribute("SunspotOrigVolume") or 0.5)
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
					if inst:GetAttribute("SunspotOrigVolume") == nil then
						inst:SetAttribute("SunspotOrigVolume", inst.Volume)
					end
					inst.Volume = 0
					table.insert(mutedFootstepSounds, inst)
				end
			end
		end
	end

	local function clearBlackSunLocal()
		blackSunCharging = false
		blackSunPending = false
		if setAbilityPressed then
			setAbilityPressed("Z", false)
		end
		if setAbilityCharge then
			setAbilityCharge("Z", 0)
		end
	end

	local function throwBlackSun(character: Model, camera: Camera)
		local charge = character:GetAttribute("BlackSunCharge")
		local alpha = if typeof(charge) == "number" then charge else 0
		if alpha < MIN_THROW_CHARGE then
			if character:GetAttribute("IsBlackSunCharging") == true or blackSunPending then
				blackSunCharge:FireServer(false)
			end
			clearBlackSunLocal()
			return
		end
		local target = getMouseWorldPoint(camera, character)
		blackSunThrow:FireServer(target.X, target.Y, target.Z)
		clearBlackSunLocal()
	end

	RunService.Heartbeat:Connect(function()
		if not AbilityGateHelper.isSunspot(player) then
			fWasDown = false
			eWasDown = false
			cWasDown = false
			qWasDown = false
			zWasDown = false
			flareSteering = false
			wasFlying = false
			photoActive = false
			photoHolding = false
			blackSunCharging = false
			blackSunPending = false
			return
		end

		local char = player.Character
		local cam = workspace.CurrentCamera
		if not char or not cam then
			return
		end

		local now = tick()
		local flying = char:GetAttribute("IsSolarFlying") == true
		local serverPhoto = char:GetAttribute("IsPhotosynthesisActive") == true
		local serverBlackSun = char:GetAttribute("IsBlackSunCharging") == true
		local lmbDown = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)

		photoActive = serverPhoto or photoHolding

		if serverBlackSun then
			blackSunPending = false
			blackSunCharging = true
			local charge = char:GetAttribute("BlackSunCharge")
			if setAbilityCharge and typeof(charge) == "number" then
				setAbilityCharge("Z", charge)
			end
		elseif blackSunPending and now < blackSunPendingUntil then
			blackSunCharging = true
		elseif blackSunPending and now >= blackSunPendingUntil then
			blackSunPending = false
			if not serverBlackSun then
				clearBlackSunLocal()
			end
		end

		if flying and not wasFlying then
			setFootstepsMuted(char, true)
		elseif not flying and wasFlying then
			setFootstepsMuted(char, false)
		end
		wasFlying = flying

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

		local eDown = UserInputService:IsKeyDown(Enum.KeyCode.E)
		if eDown and not eWasDown and AbilityGateHelper.canUse(player, char, UPPERCUT.ABILITY_ID) then
			local aim = getAimDirection(char, cam)
			SunspotAbilityAnimations.playUppercut()
			sunUppercut:FireServer(aim.X, aim.Y, aim.Z)
			if setAbilityPressed then
				setAbilityPressed("E", true)
				task.delay(0.12, function()
					if setAbilityPressed then
						setAbilityPressed("E", false)
					end
				end)
			end
		end
		eWasDown = eDown

		local cDown = UserInputService:IsKeyDown(Enum.KeyCode.C)
		if cDown and not cWasDown and AbilityGateHelper.canUse(player, char, PHOTO.ABILITY_ID) then
			photoHolding = true
			photosynthesis:FireServer(true)
			if setAbilityPressed then
				setAbilityPressed("C", true)
			end
		elseif not cDown and cWasDown then
			photoHolding = false
			photosynthesis:FireServer(false)
			if setAbilityPressed then
				setAbilityPressed("C", false)
			end
		end
		cWasDown = cDown
		if setAbilityPressed then
			setAbilityPressed("C", photoActive or cDown)
		end

		local qDown = UserInputService:IsKeyDown(Enum.KeyCode.Q)
		if qDown and not qWasDown and AbilityGateHelper.canUse(player, char, FLARE.ABILITY_ID) then
			local aim = getAimDirection(char, cam)
			flareStart:FireServer(aim.X, aim.Y, aim.Z)
			flareSteering = true
			if setAbilityPressed then
				setAbilityPressed("Q", true)
			end
		elseif not qDown and qWasDown and flareSteering then
			flareRelease:FireServer()
			flareSteering = false
			if setAbilityPressed then
				setAbilityPressed("Q", false)
			end
		end
		qWasDown = qDown

		if flareSteering or char:GetAttribute("IsSolarFlareActive") == true then
			if now - lastFlareAim >= FLARE.AIM_INTERVAL then
				lastFlareAim = now
				local aim = getAimDirection(char, cam)
				flareAim:FireServer(aim.X, aim.Y, aim.Z)
			end
			if setAbilityPressed then
				setAbilityPressed("Q", true)
			end
		end

		if flareSteering and not lmbDown and not qDown then
			flareRelease:FireServer()
			flareSteering = false
			if setAbilityPressed then
				setAbilityPressed("Q", false)
			end
		end

		local zDown = UserInputService:IsKeyDown(Enum.KeyCode.Z)
		if zDown and not zWasDown and AbilityGateHelper.canUse(player, char, BLACK_SUN.ABILITY_ID) then
			blackSunCharge:FireServer(true)
			blackSunPending = true
			blackSunPendingUntil = now + 1.5
			blackSunCharging = true
			if setAbilityPressed then
				setAbilityPressed("Z", true)
			end
		elseif not zDown and zWasDown and (blackSunCharging or serverBlackSun) then
			throwBlackSun(char, cam)
		end
		zWasDown = zDown

		if blackSunCharging and lmbDown and not lmbWasDown and (serverBlackSun or blackSunPending) then
			throwBlackSun(char, cam)
		end
		lmbWasDown = lmbDown
	end)
end

return SunspotAbilitiesClient
