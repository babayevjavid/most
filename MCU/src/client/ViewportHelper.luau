--!strict

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MorphVfxTint = require(ReplicatedStorage.Shared.MorphVfxTint)
local MorphAnimationHelper = require(ReplicatedStorage.Shared.MorphAnimationHelper)

local ViewportHelper = {}

type Binding = {
	character: Model,
	conn: RBXScriptConnection?,
	retryConn: RBXScriptConnection?,
	idleTrack: AnimationTrack?,
	frameStyle: string?,
}

local bindings: { [ViewportFrame]: Binding } = {}
local FACE_YAW = math.pi
local FIXED_FOV = 40

local function clearBinding(viewport: ViewportFrame)
	local state = bindings[viewport]
	if state then
		if state.conn then
			state.conn:Disconnect()
		end
		if state.retryConn then
			state.retryConn:Disconnect()
		end
		if state.idleTrack then
			state.idleTrack:Stop(0)
			state.idleTrack:Destroy()
		end
		bindings[viewport] = nil
	end
	for _, child in viewport:GetChildren() do
		if not child:IsA("UICorner") and not child:IsA("UIStroke") then
			child:Destroy()
		end
	end
end

local function findIdleAnimId(root: Instance?): string?
	if not root then
		return nil
	end
	local animate = root:FindFirstChild("Animate")
	if not animate then
		return nil
	end
	local folder = animate:FindFirstChild("idle") or animate:FindFirstChild("Idle")
	if not folder then
		return nil
	end
	local preferred = folder:FindFirstChild("Animation1")
	if preferred then
		if preferred:IsA("Animation") and preferred.AnimationId ~= "" then
			return preferred.AnimationId
		end
		if preferred:IsA("StringValue") and preferred.Value ~= "" then
			return preferred.Value
		end
		local nested = preferred:FindFirstChildOfClass("Animation")
		if nested and nested.AnimationId ~= "" then
			return nested.AnimationId
		end
	end
	for _, child in folder:GetChildren() do
		if child:IsA("Animation") and child.AnimationId ~= "" then
			return child.AnimationId
		end
		if child:IsA("StringValue") and child.Value ~= "" then
			return child.Value
		end
		local nested = child:FindFirstChildOfClass("Animation")
		if nested and nested.AnimationId ~= "" then
			return nested.AnimationId
		end
	end
	return nil
end

local function prepareStaticClone(clone: Model, forIdle: boolean)
	local idleId = findIdleAnimId(clone)
	for _, desc in clone:GetDescendants() do
		if desc:IsA("Script") or desc:IsA("LocalScript") or desc:IsA("ModuleScript") then
			desc:Destroy()
		elseif desc:IsA("BasePart") then
			desc.CanCollide = false
			desc.CanQuery = false
			desc.CanTouch = false
			if desc.Name == "HumanoidRootPart" then
				desc.Transparency = 1
				desc.Anchored = true
			else
				desc.Anchored = not forIdle
			end
		elseif desc:IsA("Humanoid") then
			desc.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			desc.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
			desc.PlatformStand = true
		elseif desc:IsA("Animator") and not forIdle then
			for _, track in desc:GetPlayingAnimationTracks() do
				track:Stop(0)
				track:Destroy()
			end
			desc:Destroy()
		end
	end
	return idleId
end

local function frameStaticModel(clone: Model, vpCamera: Camera, yaw: number?, style: string?)
	local hrp = clone:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp and not clone.PrimaryPart then
		clone.PrimaryPart = hrp
	end
	local rot = FACE_YAW + (yaw or 0)
	clone:PivotTo(CFrame.Angles(0, rot, 0))
	local _boxCf, size = clone:GetBoundingBox()
	local height = math.max(size.Y, 3)
	-- Same relative framing for HUD and roster circles
	local lookY = height * 0.58 - 1.25
	local camY = height * 0.54 - 1
	local dist = math.clamp(height * 1.08, 3.2, 7.8) - 2.05
	vpCamera.CFrame = CFrame.lookAt(Vector3.new(0, camY, dist), Vector3.new(0, lookY, 0))
	vpCamera.FieldOfView = FIXED_FOV
end

local function playIdle(clone: Model, idleId: string?): AnimationTrack?
	if not idleId then
		return nil
	end
	local hum = clone:FindFirstChildOfClass("Humanoid")
	if not hum then
		return nil
	end
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = hum
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = idleId
	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	anim:Destroy()
	if not ok or not track then
		return nil
	end
	track.Looped = true
	track.Priority = Enum.AnimationPriority.Idle
	track:Play(0.15)
	return track
end

local function setupViewportShell(viewport: ViewportFrame)
	viewport.Ambient = Color3.fromRGB(160, 200, 208)
	viewport.LightColor = Color3.fromRGB(255, 255, 255)
	viewport.LightDirection = Vector3.new(0.2, -0.65, -1)
	viewport.BackgroundTransparency = 1

	local worldModel = Instance.new("WorldModel")
	worldModel.Name = "WorldModel"
	worldModel.Parent = viewport

	local camera = Instance.new("Camera")
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	return worldModel, camera
end

function ViewportHelper.bindTemplate(viewport: ViewportFrame, template: Model?, yaw: number?, frameStyle: string?): Model?
	return ViewportHelper.bindMorphIdle(viewport, template, yaw, frameStyle)
end

function ViewportHelper.bindMorphIdle(viewport: ViewportFrame, template: Model?, yaw: number?, frameStyle: string?): Model?
	clearBinding(viewport)
	if not template then
		return nil
	end

	local wasArchivable = template.Archivable
	template.Archivable = true
	local ok, clone = pcall(function()
		return template:Clone()
	end)
	template.Archivable = wasArchivable
	if not ok or not clone or not clone:IsA("Model") then
		return nil
	end

	local idleId = prepareStaticClone(clone, true)
	clone.Name = "ViewportMorphIdle"

	-- Skin-specific VFX tint (e.g. X-Men '97 Jean)
	MorphVfxTint.applyToTemplateName(clone, template.Name)
	MorphAnimationHelper.applyToModel(clone, MorphAnimationHelper.idleIdForMorphName(template.Name))
	idleId = findIdleAnimId(clone)

	local _worldModel, camera = setupViewportShell(viewport)
	clone.Parent = _worldModel
	local style = frameStyle or nil
	frameStaticModel(clone, camera, yaw or 0, style)
	local idleTrack = playIdle(clone, idleId)

	bindings[viewport] = {
		character = clone,
		conn = nil,
		retryConn = nil,
		idleTrack = idleTrack,
		frameStyle = style,
	}
	return clone
end

function ViewportHelper.setTemplateYaw(viewport: ViewportFrame, yaw: number)
	local state = bindings[viewport]
	if not state or not state.character.Parent then
		return
	end
	local cam = viewport.CurrentCamera
	if not cam then
		return
	end
	frameStaticModel(state.character, cam, yaw, state.frameStyle)
end

function ViewportHelper.bindCharacter(viewport: ViewportFrame, character: Model?)
	clearBinding(viewport)
	if not character or not character.Parent then
		return
	end
	ViewportHelper.bindMorphIdle(viewport, character, 0)
end

return ViewportHelper
