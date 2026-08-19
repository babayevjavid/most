--!strict
--[[ Havok client: T blast, F beam, E burst, C surge, Q siphon. ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AbilityGateHelper = require(Shared:WaitForChild("AbilityGateHelper"))
local HavokConstants = require(Shared:WaitForChild("HavokConstants"))

local HavokAbilityAnimations = require(script.Parent:WaitForChild("HavokAbilityAnimations"))
local HavokAbilityVfx = require(script.Parent:WaitForChild("HavokAbilityVfx"))

local SIPHON = HavokConstants.EnergySiphon
local BURST = HavokConstants.EnergyBurst
local BEAM = HavokConstants.ConcussiveBeam
local BLAST = HavokConstants.EnergyBlast
local SURGE = HavokConstants.KineticSurge

local HavokAbilitiesClient = {}

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

local function getAimDirection(character: Model, camera: Camera): Vector3
	local chest = character:FindFirstChild("UpperTorso") :: BasePart?
		or character:FindFirstChild("Torso") :: BasePart?
		or character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local origin = if chest then chest.Position else character:GetPivot().Position
	local target = getMouseWorldPoint(camera, character)
	local dir = target - origin
	if dir.Magnitude < 0.01 then
		return camera.CFrame.LookVector.Unit
	end
	return dir.Unit
end

local function getBeamDirFromAttributes(character: Model): Vector3?
	local x = character:GetAttribute("HavokBeamDirX")
	local y = character:GetAttribute("HavokBeamDirY")
	local z = character:GetAttribute("HavokBeamDirZ")
	if typeof(x) == "number" and typeof(y) == "number" and typeof(z) == "number" then
		local dir = Vector3.new(x, y, z)
		if dir.Magnitude > 0.01 then
			return dir.Unit
		end
	end
	return nil
end

local function smoothRotateToward(character: Model, aimDir: Vector3, dt: number)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = character:FindFirstChildOfClass("Humanoid")
	if not root or not hum then
		return
	end

	local flatAim = Vector3.new(aimDir.X, 0, aimDir.Z)
	if flatAim.Magnitude < 0.01 then
		return
	end

	hum.AutoRotate = false
	local targetYaw = math.atan2(-flatAim.X, -flatAim.Z)
	local _, currentYaw = root.CFrame:ToEulerAnglesYXZ()
	local delta = ((targetYaw - currentYaw + math.pi) % (2 * math.pi)) - math.pi
	local alpha = 1 - math.exp(-dt / BEAM.BODY_ROTATE_TAU)
	local newYaw = currentYaw + delta * alpha
	root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, newYaw, 0)
end

local function restoreAutoRotate(character: Model)
	local hum = character:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.AutoRotate = true
	end
end

function HavokAbilitiesClient.start(
	siphonRemote: RemoteEvent,
	burstRemote: RemoteEvent,
	beamStartRemote: RemoteEvent,
	beamAimRemote: RemoteEvent,
	beamEndRemote: RemoteEvent,
	surgeRemote: RemoteEvent,
	blastStartRemote: RemoteEvent,
	blastAimRemote: RemoteEvent,
	blastReleaseRemote: RemoteEvent,
	player: Player,
	setAbilityPressed: ((key: string, pressed: boolean) -> ())?
)
	HavokAbilityAnimations.start(player)
	HavokAbilityVfx.start(player)

	local qWasDown = false
	local eWasDown = false
	local cWasDown = false
	local tWasDown = false
	local blastSteering = false
	local lastBlastAim = 0
	local beamActive = false
	local lastBeamAim = 0
	local lastSiphonFlash = 0

	RunService.RenderStepped:Connect(function(dt)
		if not AbilityGateHelper.isHavok(player) then
			if beamActive then
				beamActive = false
				HavokAbilityAnimations.stopBeamChannel()
				HavokAbilityVfx.stopBeamAimSmoothing()
				local char = player.Character
				if char then
					HavokAbilityVfx.setBeamActive(char, false)
					restoreAutoRotate(char)
				end
			end
			if blastSteering then
				blastSteering = false
				blastReleaseRemote:FireServer()
			end
			return
		end

		local char = player.Character
		local cam = workspace.CurrentCamera
		if not char or not cam then
			return
		end

		local now = tick()
		local fKeyDown = UserInputService:IsKeyDown(Enum.KeyCode.F)
		local eDown = UserInputService:IsKeyDown(Enum.KeyCode.E)
		local cDown = UserInputService:IsKeyDown(Enum.KeyCode.C)
		local qDown = UserInputService:IsKeyDown(Enum.KeyCode.Q)
		local tDown = UserInputService:IsKeyDown(Enum.KeyCode.T)

		local surgeActive = char:GetAttribute("IsKineticSurgeActive") == true
		local serverBeam = char:GetAttribute("IsConcussiveBeamActive") == true

		-- T: Energy Blast (hold to steer)
		if tDown and not surgeActive and not beamActive then
			if not blastSteering then
				if AbilityGateHelper.canUse(player, char, BLAST.ABILITY_ID) then
					local aim = getAimDirection(char, cam)
					HavokAbilityAnimations.playHandCast()
					HavokAbilityVfx.playBlastCast(char)
					blastStartRemote:FireServer(aim.X, aim.Y, aim.Z)
					blastSteering = true
					lastBlastAim = now
				end
			elseif now - lastBlastAim >= BLAST.AIM_INTERVAL then
				lastBlastAim = now
				local aim = getAimDirection(char, cam)
				blastAimRemote:FireServer(aim.X, aim.Y, aim.Z)
			end
		elseif blastSteering and not tDown then
			blastReleaseRemote:FireServer()
			blastSteering = false
		end
		tWasDown = tDown
		if setAbilityPressed then
			setAbilityPressed("T", tDown)
		end

		-- Q: Energy Siphon
		if qDown and not qWasDown then
			if AbilityGateHelper.canUse(player, char, SIPHON.ABILITY_ID) then
				local charge = char:GetAttribute("HavokCharge")
				local current = if typeof(charge) == "number" then charge else 0
				if current < SIPHON.MAX_CHARGE then
					siphonRemote:FireServer()
					if now - lastSiphonFlash > 0.15 then
						HavokAbilityVfx.playSiphonFlash(char)
						lastSiphonFlash = now
					end
				end
			end
		end
		qWasDown = qDown
		if setAbilityPressed then
			setAbilityPressed("Q", qDown)
		end

		-- E: Energy Burst (at character; no aim sent)
		if eDown and not eWasDown and not surgeActive and not beamActive then
			local charge = char:GetAttribute("HavokCharge")
			local current = if typeof(charge) == "number" then charge else 0
			if current >= BURST.MIN_CHARGE and AbilityGateHelper.canUse(player, char, BURST.ABILITY_ID) then
				HavokAbilityVfx.playBurstPulse(char)
				burstRemote:FireServer()
			end
		end
		eWasDown = eDown
		if setAbilityPressed then
			setAbilityPressed("E", eDown)
		end

		-- C: Kinetic Surge (3D aim direction)
		if cDown and not cWasDown and not beamActive and not surgeActive then
			if AbilityGateHelper.canUse(player, char, SURGE.ABILITY_ID) then
				local aim = getAimDirection(char, cam)
				HavokAbilityVfx.playSurgeBoost(char, aim)
				surgeRemote:FireServer(aim.X, aim.Y, aim.Z)
			end
		end
		cWasDown = cDown
		if setAbilityPressed then
			setAbilityPressed("C", cDown)
		end

		-- F: Concussive Beam (hold)
		if fKeyDown and not surgeActive then
			if not beamActive then
				if AbilityGateHelper.canUse(player, char, BEAM.ABILITY_ID) then
					local aim = getAimDirection(char, cam)
					beamStartRemote:FireServer(aim.X, aim.Y, aim.Z)
					beamActive = true
					HavokAbilityAnimations.playBeamChannel()
					HavokAbilityVfx.setBeamActive(char, true, aim)
					HavokAbilityVfx.startBeamAimSmoothing(char, function()
						return getAimDirection(char, cam)
					end)
					if setAbilityPressed then
						setAbilityPressed("F", true)
					end
				end
			else
				if now - lastBeamAim >= BEAM.AIM_SEND_INTERVAL then
					lastBeamAim = now
					local aim = HavokAbilityVfx.getSmoothedAimDirection()
					beamAimRemote:FireServer(aim.X, aim.Y, aim.Z)
				end
			end
		elseif beamActive then
			beamEndRemote:FireServer()
			beamActive = false
			HavokAbilityAnimations.stopBeamChannel()
			HavokAbilityVfx.stopBeamAimSmoothing()
			if setAbilityPressed then
				setAbilityPressed("F", false)
			end
		end

		local isBeaming = beamActive or serverBeam
		if isBeaming then
			local aim = if beamActive
				then HavokAbilityVfx.getSmoothedAimDirection()
				else getBeamDirFromAttributes(char) or getAimDirection(char, cam)
			if aim.Magnitude > 0.01 then
				smoothRotateToward(char, aim, dt)
			end
			HavokAbilityVfx.setBeamActive(char, true, aim)
		else
			HavokAbilityVfx.setBeamActive(char, false)
			restoreAutoRotate(char)
		end
	end)
end

return HavokAbilitiesClient
