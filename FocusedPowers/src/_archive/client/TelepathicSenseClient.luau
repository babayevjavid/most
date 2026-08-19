--!strict
--[[
	Telepathic Sense (C): hold to scan, click to view a target with normal third-person camera.
	Click another target while locked to smoothly jump focus between heads, then free orbit.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")

local AbilityGateHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityGateHelper"))
local EntityStatsHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("EntityStatsHelper"))
local TelepathicSenseConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TelepathicSenseConstants"))
local TelepathicSenseHighlight = require(script.Parent:WaitForChild("TelepathicSenseHighlight"))
local TelepathicSenseTargetUI = require(script.Parent:WaitForChild("TelepathicSenseTargetUI"))

local ABILITY_ID = TelepathicSenseConstants.ABILITY_ID

type CameraPhase = "idle" | "transitioning" | "locked" | "returning"

local TelepathicSenseClient = {}

local function tweenFov(camera: Camera, fov: number, duration: number)
	TweenService:Create(
		camera,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ FieldOfView = fov }
	):Play()
end

local function smoothstep(alpha: number): number
	alpha = math.clamp(alpha, 0, 1)
	return alpha * alpha * (3 - 2 * alpha)
end

local function getHeadFocus(head: BasePart): Vector3
	return head.Position + Vector3.new(0, 0.08, 0)
end

local function flattenLookDir(look: Vector3): Vector3
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.01 then
		return Vector3.new(0, 0, -1)
	end
	return flat.Unit
end

local function getHeadCameraPos(head: BasePart, look: Vector3, zoom: number): Vector3
	local focus = getHeadFocus(head)
	return focus - flattenLookDir(look) * zoom
end

local function getOrbitCameraPos(cam: Camera, head: BasePart, zoom: number): Vector3
	local _, look, _ = extractCameraView(cam.CFrame, getHeadFocus(head))
	return getHeadCameraPos(head, look, zoom)
end

local function cameraFromFocus(focus: Vector3, look: Vector3, zoom: number): CFrame
	local dir = if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1)
	local pos = focus - dir * zoom
	return CFrame.lookAt(pos, focus)
end

local function extractCameraView(cam: CFrame, anchorFocus: Vector3): (Vector3, Vector3, number)
	local look = cam.LookVector
	local toAnchor = anchorFocus - cam.Position
	local zoom = toAnchor:Dot(look)
	if zoom < 0.5 then
		zoom = (cam.Position - anchorFocus).Magnitude
	end
	if zoom < 0.5 then
		zoom = 12
	end
	local focus = cam.Position + look * zoom
	return focus, look, zoom
end

local function collectHumanoidsInRange(origin: Vector3, radius: number, excludeCharacter: Model?): { Model }
	local results: { Model } = {}
	local radiusSq = radius * radius

	for _, inst in workspace:GetDescendants() do
		if inst:IsA("Model") then
			local humanoid = inst:FindFirstChildOfClass("Humanoid")
			local root = EntityStatsHelper.getHeadPart(inst)
			if humanoid and humanoid.Health > 0 and root and inst ~= excludeCharacter then
				local delta = root.Position - origin
				if delta:Dot(delta) <= radiusSq then
					table.insert(results, inst)
				end
			end
		end
		if #results >= 32 then
			break
		end
	end

	return results
end

local function pickTargetFromMouse(highlighted: { Model }, mouse: Mouse): Model?
	if #highlighted == 0 then
		return nil
	end

	local highlightSet: { [Model]: boolean } = {}
	local includeParts: { BasePart } = {}
	for _, model in highlighted do
		highlightSet[model] = true
		for _, desc in model:GetDescendants() do
			if desc:IsA("BasePart") then
				table.insert(includeParts, desc)
			end
		end
	end

	local rayOrigin = mouse.UnitRay.Origin
	local rayDir = mouse.UnitRay.Direction

	if #includeParts > 0 then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = includeParts
		local hit = workspace:Raycast(rayOrigin, rayDir * TelepathicSenseConstants.TARGET_PICK_RAY_DISTANCE, params)
		if hit then
			local model = EntityStatsHelper.getModelFromPart(hit.Instance)
			if model and highlightSet[model] then
				return model
			end
		end
	end

	local bestModel: Model? = nil
	local bestDist = TelepathicSenseConstants.TARGET_PICK_HEAD_RADIUS
	for _, model in highlighted do
		local head = EntityStatsHelper.getHeadPart(model)
		if not head then
			continue
		end
		local toHead = head.Position - rayOrigin
		local proj = rayDir:Dot(toHead)
		if proj <= 0 then
			continue
		end
		local closest = rayOrigin + rayDir * proj
		local dist = (head.Position - closest).Magnitude
		if dist < bestDist then
			bestDist = dist
			bestModel = model
		end
	end

	return bestModel
end

function TelepathicSenseClient.start(
	senseStart: RemoteEvent,
	senseEnd: RemoteEvent,
	player: Player,
	setAbilityPressed: ((key: string, pressed: boolean) -> ())?
)
	TelepathicSenseTargetUI.init(player:WaitForChild("PlayerGui") :: PlayerGui)
	local senseActive = false
	local lockedTarget: Model? = nil
	local lastScan = 0
	local lastCHeld = false
	local clickPressed = false
	local savedCameraType: Enum.CameraType? = nil
	local savedCameraSubject: Instance? = nil
	local savedMinZoom: number? = nil
	local savedMaxZoom: number? = nil
	local colorCorrection: ColorCorrectionEffect? = nil
	local renderConn: RBXScriptConnection? = nil
	local highlighted: { Model } = {}

	local cameraPhase: CameraPhase = "idle"
	local transitionStart = 0
	local transitionDuration = TelepathicSenseConstants.APPROACH_DURATION
	local transitionStartFocus = Vector3.zero
	local transitionStartPos = Vector3.zero
	local transitionLook = Vector3.new(0, 0, -1)
	local transitionZoom = 12
	local transitionSourceCam: Camera? = nil
	local endingSense = false
	local cameraSettledAt: number? = nil
	local mouse = player:GetMouse()

	local function ensureColorCorrection(): ColorCorrectionEffect
		if colorCorrection and colorCorrection.Parent then
			return colorCorrection
		end
		local existing = Lighting:FindFirstChild("TelepathicSenseCC")
		if existing and existing:IsA("ColorCorrectionEffect") then
			colorCorrection = existing
			return existing
		end
		local cc = Instance.new("ColorCorrectionEffect")
		cc.Name = "TelepathicSenseCC"
		cc.Enabled = false
		cc.Parent = Lighting
		colorCorrection = cc
		return cc
	end

	local function savePlayerCameraDefaults(cam: Camera)
		if savedCameraType == nil then
			savedCameraType = cam.CameraType
			savedCameraSubject = cam.CameraSubject
		end
		if savedMinZoom == nil then
			savedMinZoom = player.CameraMinZoomDistance
			savedMaxZoom = player.CameraMaxZoomDistance
		end
	end

	local function getPlayerZoom(): number
		local maxZoom = savedMaxZoom or player.CameraMaxZoomDistance
		if typeof(maxZoom) ~= "number" or maxZoom <= 0 then
			maxZoom = 12
		end
		return maxZoom
	end

	local function lockCameraDuringTransition()
		player.CameraMinZoomDistance = transitionZoom
		player.CameraMaxZoomDistance = transitionZoom
	end

	local function handoffToTargetCamera(cam: Camera, target: Model)
		savePlayerCameraDefaults(cam)

		local humanoid = target:FindFirstChildOfClass("Humanoid")
		cam.CameraType = Enum.CameraType.Custom
		if humanoid then
			cam.CameraSubject = humanoid
		end
		if savedMinZoom ~= nil then
			player.CameraMinZoomDistance = savedMinZoom
		end
		if savedMaxZoom ~= nil then
			player.CameraMaxZoomDistance = savedMaxZoom
		end
		cameraPhase = "locked"
		cameraSettledAt = tick()
	end

	local function restorePlayerCamera(camera: Camera)
		if savedCameraType then
			camera.CameraType = savedCameraType
		else
			camera.CameraType = Enum.CameraType.Custom
		end
		if savedCameraSubject then
			camera.CameraSubject = savedCameraSubject
		else
			local char = player.Character
			local humanoid = char and char:FindFirstChildOfClass("Humanoid")
			if humanoid then
				camera.CameraSubject = humanoid
			end
		end
		tweenFov(camera, TelepathicSenseConstants.CAMERA_DEFAULT_FOV, TelepathicSenseConstants.CAMERA_TWEEN_OUT)
		if savedMinZoom ~= nil then
			player.CameraMinZoomDistance = savedMinZoom
		end
		if savedMaxZoom ~= nil then
			player.CameraMaxZoomDistance = savedMaxZoom
		end
		savedCameraType = nil
		savedCameraSubject = nil
		savedMinZoom = nil
		savedMaxZoom = nil
		cameraPhase = "idle"
	end

	local function finishSenseCleanup()
		endingSense = false
		if renderConn then
			renderConn:Disconnect()
			renderConn = nil
		end

		local cc = colorCorrection
		if cc then
			cc.Enabled = false
		end

		lockedTarget = nil
		table.clear(highlighted)
		TelepathicSenseHighlight.clearAll()
		TelepathicSenseTargetUI.hide()

		if setAbilityPressed then
			setAbilityPressed("C", false)
		end
	end

	local function canPickNewTarget(): boolean
		if cameraPhase == "returning" or cameraPhase == "transitioning" then
			return false
		end
		if cameraPhase == "idle" and lockedTarget == nil then
			return true
		end
		if cameraPhase == "locked" and lockedTarget ~= nil and cameraSettledAt ~= nil then
			return (tick() - cameraSettledAt) >= TelepathicSenseConstants.SWITCH_DELAY_AFTER_SETTLE
		end
		return false
	end

	local function beginTransitionToTarget(cam: Camera, target: Model, isSwitch: boolean)
		local head = EntityStatsHelper.getHeadPart(target)
		if not head then
			return
		end

		savePlayerCameraDefaults(cam)

		local head = EntityStatsHelper.getHeadPart(target)
		if not head then
			return
		end

		transitionStartPos = cam.CFrame.Position
		local _, look, zoom = extractCameraView(cam.CFrame, getHeadFocus(head))
		transitionLook = flattenLookDir(look)
		transitionZoom = if isSwitch then zoom else getPlayerZoom()
		transitionSourceCam = cam
		transitionDuration = if isSwitch
			then TelepathicSenseConstants.SWITCH_DURATION
			else TelepathicSenseConstants.APPROACH_DURATION
		transitionStart = tick()
		cameraPhase = "transitioning"
		cameraSettledAt = nil
		cam.CameraType = Enum.CameraType.Scriptable
		lockCameraDuringTransition()
	end

	local function beginCameraReturn(camera: Camera)
		local char = player.Character
		local ownHead = char and EntityStatsHelper.getHeadPart(char)
		if not ownHead then
			restorePlayerCamera(camera)
			finishSenseCleanup()
			return
		end

		local anchorFocus: Vector3
		if lockedTarget then
			local targetHead = EntityStatsHelper.getHeadPart(lockedTarget)
			anchorFocus = if targetHead then getHeadFocus(targetHead) else getHeadFocus(ownHead)
		else
			anchorFocus = getHeadFocus(ownHead)
		end

		local focus, look, zoom = extractCameraView(camera.CFrame, anchorFocus)
		transitionStartPos = camera.CFrame.Position
		transitionStartFocus = focus
		transitionLook = flattenLookDir(look)
		transitionZoom = zoom
		transitionDuration = TelepathicSenseConstants.RETURN_DURATION
		transitionStart = tick()
		cameraPhase = "returning"
		camera.CameraType = Enum.CameraType.Scriptable
		lockedTarget = nil
	end

	local function shouldSmoothReturn(camera: Camera?): boolean
		if not camera then
			return false
		end
		return cameraPhase == "locked" or cameraPhase == "transitioning" or cameraPhase == "returning"
			or camera.CameraType == Enum.CameraType.Scriptable
	end

	local function endSense()
		if not senseActive and not endingSense then
			return
		end
		if endingSense then
			return
		end

		senseActive = false
		endingSense = true
		senseEnd:FireServer()

		local camera = workspace.CurrentCamera
		table.clear(highlighted)
		TelepathicSenseHighlight.clearAll()
		TelepathicSenseTargetUI.hide()

		local cc = colorCorrection
		if cc then
			cc.Enabled = false
		end

		if shouldSmoothReturn(camera) and camera then
			beginCameraReturn(camera)
		else
			if camera then
				restorePlayerCamera(camera)
			end
			finishSenseCleanup()
		end
	end

	local function lockOntoTarget(cam: Camera, picked: Model)
		local isSwitch = lockedTarget ~= nil and lockedTarget ~= picked
		lockedTarget = picked
		TelepathicSenseHighlight.setLocked(picked)
		TelepathicSenseTargetUI.show(picked)
		tweenFov(cam, TelepathicSenseConstants.CAMERA_FOLLOW_FOV, TelepathicSenseConstants.CAMERA_TWEEN_IN)
		beginTransitionToTarget(cam, picked, isSwitch)
	end

	local function updateCameraMotion(cam: Camera)
		if cameraPhase == "transitioning" then
			if not lockedTarget or not lockedTarget.Parent then
				return
			end
			local head = EntityStatsHelper.getHeadPart(lockedTarget)
			if not head then
				return
			end

			cam.CameraType = Enum.CameraType.Scriptable
			lockCameraDuringTransition()

			local alpha = smoothstep((tick() - transitionStart) / transitionDuration)
			local endFocus = getHeadFocus(head)
			local endPos = getHeadCameraPos(head, transitionLook, transitionZoom)
			local pos = transitionStartPos:Lerp(endPos, alpha)
			cam.CFrame = CFrame.lookAt(pos, endFocus)

			if alpha >= 1 then
				transitionSourceCam = nil
				handoffToTargetCamera(cam, lockedTarget)
			end
		elseif cameraPhase == "returning" then
			local char = player.Character
			local ownHead = char and EntityStatsHelper.getHeadPart(char)
			if not ownHead then
				restorePlayerCamera(cam)
				finishSenseCleanup()
				return
			end

			local alpha = smoothstep((tick() - transitionStart) / transitionDuration)
			local endFocus = getHeadFocus(ownHead)
			local endPos = getHeadCameraPos(ownHead, transitionLook, transitionZoom)
			local pos = transitionStartPos:Lerp(endPos, alpha)
			cam.CFrame = CFrame.lookAt(pos, endFocus)

			if alpha >= 1 then
				restorePlayerCamera(cam)
				finishSenseCleanup()
			end
		end
	end

	local function beginSense()
		local char = player.Character
		if not char or not AbilityGateHelper.canUse(player, char, ABILITY_ID) then
			return
		end

		senseStart:FireServer()
		senseActive = true
		cameraPhase = "idle"
		lockedTarget = nil
		cameraSettledAt = nil

		local camera = workspace.CurrentCamera
		if camera then
			tweenFov(camera, TelepathicSenseConstants.CAMERA_ACTIVE_FOV, TelepathicSenseConstants.CAMERA_TWEEN_IN)
		end

		local cc = ensureColorCorrection()
		cc.Enabled = true
		cc.TintColor = TelepathicSenseConstants.VIGNETTE_TINT
		cc.Saturation = TelepathicSenseConstants.VIGNETTE_SATURATION
		cc.Contrast = TelepathicSenseConstants.VIGNETTE_CONTRAST

		if renderConn then
			renderConn:Disconnect()
		end
		renderConn = RunService.RenderStepped:Connect(function()
			if not senseActive and not endingSense then
				return
			end
			local cam = workspace.CurrentCamera
			if cam then
				updateCameraMotion(cam)
			end
		end)

		if setAbilityPressed then
			setAbilityPressed("C", true)
		end
	end

	RunService.Heartbeat:Connect(function()
		if not AbilityGateHelper.isJeanGrey(player) then
			if senseActive then
				endSense()
			end
			lastCHeld = false
			return
		end

		local char = player.Character
		local cam = workspace.CurrentCamera
		if not char or not cam then
			return
		end

		local cHeld = UserInputService:IsKeyDown(Enum.KeyCode.C)

		if cHeld and not lastCHeld then
			if not senseActive and not endingSense then
				beginSense()
			end
		elseif not cHeld and lastCHeld and senseActive then
			endSense()
		end

		if senseActive and not endingSense then
			local now = tick()
			if now - lastScan >= TelepathicSenseConstants.SCAN_INTERVAL then
				lastScan = now
				local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root then
					highlighted = collectHumanoidsInRange(root.Position, TelepathicSenseConstants.RADIUS, char)
					TelepathicSenseHighlight.setTargets(highlighted)
					if lockedTarget then
						TelepathicSenseHighlight.setLocked(lockedTarget)
					end
				end
			end

			if canPickNewTarget() then
				local wantClick = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
				if wantClick and not clickPressed then
					clickPressed = true
					local picked = pickTargetFromMouse(highlighted, mouse)
					if picked and picked ~= lockedTarget then
						lockOntoTarget(cam, picked)
					end
				elseif not wantClick then
					clickPressed = false
				end
			else
				clickPressed = false
			end
		end

		lastCHeld = cHeld
	end)

	player.CharacterRemoving:Connect(function()
		endSense()
	end)
end

return TelepathicSenseClient
