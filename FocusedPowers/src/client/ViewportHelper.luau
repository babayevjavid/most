--!strict
--[[
	ViewportHelper: player avatar in ViewportFrames (WorldModel + reliable framing).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HudConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("HudConstants"))
local CharacterAppearanceHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CharacterAppearanceHelper"))

export type ViewportOptions = {
	spin: boolean?,
	character: Model?,
	characterId: string?,
	bodyColor: Color3?,
	framePadding: number?,
	fieldOfView: number?,
}

local WORLD_MODEL_NAME = "ViewportWorld"
local IDLE_ANIMATION_ID = "rbxassetid://507766666"
local activeConnections: { [ViewportFrame]: RBXScriptConnection } = {}
local retryConnections: { [ViewportFrame]: RBXScriptConnection } = {}

local ViewportHelper = {}

local function getOrCreateWorldModel(viewportFrame: ViewportFrame): WorldModel
	local existing = viewportFrame:FindFirstChild(WORLD_MODEL_NAME)
	if existing and existing:IsA("WorldModel") then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local world = Instance.new("WorldModel")
	world.Name = WORLD_MODEL_NAME
	world.Parent = viewportFrame
	return world
end

local function clearViewport(viewportFrame: ViewportFrame)
	local conn = activeConnections[viewportFrame]
	if conn then
		conn:Disconnect()
		activeConnections[viewportFrame] = nil
	end
	local retryConn = retryConnections[viewportFrame]
	if retryConn then
		retryConn:Disconnect()
		retryConnections[viewportFrame] = nil
	end
	local world = viewportFrame:FindFirstChild(WORLD_MODEL_NAME)
	if world then
		for _, child in world:GetChildren() do
			child:Destroy()
		end
	end
	for _, child in viewportFrame:GetChildren() do
		if child:IsA("Model") then
			child:Destroy()
		end
	end
end

local function getRootPart(model: Model): BasePart?
	return model:FindFirstChild("HumanoidRootPart") :: BasePart?
		or model:FindFirstChild("Torso") :: BasePart?
		or model:FindFirstChild("LowerTorso") :: BasePart?
		or model.PrimaryPart
end

local function buildFromCharacter(character: Model): Model?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end

	local okDesc, description = pcall(function()
		return humanoid:GetAppliedDescription()
	end)
	if okDesc and description then
		local okModel, fromDesc = pcall(function()
			return Players:CreateHumanoidModelFromDescription(description, humanoid.RigType)
		end)
		if okModel and fromDesc then
			return fromDesc
		end
	end

	if character.Archivable then
		local okClone, clone = pcall(function()
			return character:Clone()
		end)
		if okClone and clone and clone:FindFirstChildOfClass("Humanoid") then
			return clone
		end
		if okClone and clone then
			clone:Destroy()
		end
	end

	return nil
end

local function getAvatarModel(player: Player, character: Model?): Model?
	if character then
		local fromCharacter = buildFromCharacter(character)
		if fromCharacter then
			return fromCharacter
		end
	end

	if player.Character then
		local fromLive = buildFromCharacter(player.Character)
		if fromLive then
			return fromLive
		end
	end

	local okDesc, description = pcall(function()
		return Players:GetHumanoidDescriptionFromUserId(player.UserId)
	end)
	if okDesc and description then
		local okModel, fromDesc = pcall(function()
			return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
		end)
		if okModel and fromDesc then
			return fromDesc
		end
	end

	local okUser, fromUser = pcall(function()
		return Players:CreateHumanoidModelFromUserId(player.UserId)
	end)
	if okUser and fromUser then
		return fromUser
	end

	return nil
end

local function applyBodyColor(model: Model, color: Color3)
	local bodyColors = model:FindFirstChildOfClass("BodyColors")
	if bodyColors then
		bodyColors.HeadColor3 = color
		bodyColors.TorsoColor3 = color
		bodyColors.LeftArmColor3 = color
		bodyColors.RightArmColor3 = color
		bodyColors.LeftLegColor3 = color
		bodyColors.RightLegColor3 = color
	end

	local bodyPartNames = {
		Head = true,
		Torso = true,
		UpperTorso = true,
		LowerTorso = true,
		LeftArm = true,
		RightArm = true,
		LeftLeg = true,
		RightLeg = true,
		LeftUpperArm = true,
		LeftLowerArm = true,
		LeftHand = true,
		RightUpperArm = true,
		RightLowerArm = true,
		RightHand = true,
		LeftUpperLeg = true,
		LeftLowerLeg = true,
		LeftFoot = true,
		RightUpperLeg = true,
		RightLowerLeg = true,
		RightFoot = true,
	}

	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") and bodyPartNames[desc.Name] then
			desc.Color = color
		end
	end
end

local function prepareModel(model: Model)
	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.Anchored = true
			desc.CanCollide = false
			if desc.Name == "HumanoidRootPart" then
				desc.Transparency = 1
			elseif desc.Transparency >= 1 then
				desc.Transparency = 0
			end
		elseif desc:IsA("Decal") or desc:IsA("Texture") then
			if desc.Transparency >= 1 then
				desc.Transparency = 0
			end
		elseif desc:IsA("Script") or desc:IsA("LocalScript") then
			desc:Destroy()
		end
	end
end

local function positionCloneByRoot(clone: Model, rootPosition: Vector3, faceCamera: boolean)
	local rootPart = getRootPart(clone)
	if not rootPart then
		clone:PivotTo(CFrame.new(rootPosition))
		return
	end
	clone.PrimaryPart = rootPart
	local pivot = clone:GetPivot()
	local rootOffset = pivot:PointToObjectSpace(rootPart.Position)
	local rotation = if faceCamera then CFrame.new() else CFrame.Angles(0, math.pi, 0)
	local targetRootCF = CFrame.new(rootPosition) * rotation
	clone:PivotTo(targetRootCF * CFrame.new(-rootOffset))
end

local function playIdleAnimation(clone: Model)
	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = IDLE_ANIMATION_ID
	local ok, track = pcall(function()
		return humanoid:LoadAnimation(animation)
	end)
	if ok and track then
		track.Looped = true
		track:Play(0.1)
	end
end

local function applyViewportLighting(viewportFrame: ViewportFrame)
	viewportFrame.Ambient = Color3.fromRGB(210, 210, 220)
	viewportFrame.LightColor = Color3.fromRGB(255, 255, 255)
	viewportFrame.LightDirection = Vector3.new(-0.5, -1, -0.25)
end

local function positionCamera(model: Model, camera: Camera)
	positionCloneByRoot(model, Vector3.new(0, -1.5, 0), true)
	model:PivotTo(model:GetPivot() * CFrame.Angles(0, math.rad(HudConstants.VIEWPORT_MODEL_YAW_DEG), 0))

	local lookAt = Vector3.new(0, -0.35, 0)
	local distance = HudConstants.VIEWPORT_CAMERA_DISTANCE
	local side = HudConstants.VIEWPORT_CAMERA_SIDE
	local camPos = lookAt + Vector3.new(side, 0.05, -distance)
	camera.CFrame = CFrame.lookAt(camPos, lookAt)
	camera.FieldOfView = 35
end

function ViewportHelper.setupAvatarViewport(viewportFrame: ViewportFrame, player: Player, options: ViewportOptions?)
	clearViewport(viewportFrame)
	applyViewportLighting(viewportFrame)

	local preferredCharacter = if options then options.character else nil

	local function apply()
		local model = getAvatarModel(player, preferredCharacter or player.Character)
		if not model then
			return false
		end

		model.Name = "AvatarPreview"
		prepareModel(model)

		if options and options.characterId then
			CharacterAppearanceHelper.applyHeroAppearance(model, options.characterId)
		elseif options and options.bodyColor then
			applyBodyColor(model, options.bodyColor)
		end

		local world = getOrCreateWorldModel(viewportFrame)
		for _, child in world:GetChildren() do
			child:Destroy()
		end

		local camera = viewportFrame:FindFirstChildOfClass("Camera")
		if not camera then
			camera = Instance.new("Camera")
			camera.Parent = viewportFrame
		end

		model.Parent = world
		viewportFrame.CurrentCamera = camera
		task.defer(function()
			if model.Parent then
				positionCamera(model, camera)
			end
		end)

		task.defer(function()
			if model.Parent then
				playIdleAnimation(model)
			end
		end)

		if options and options.spin then
			local speed = math.rad(45)
			activeConnections[viewportFrame] = RunService.RenderStepped:Connect(function(dt)
				if not model.Parent then
					return
				end
				local pivot = model:GetPivot()
				model:PivotTo(pivot * CFrame.Angles(0, speed * dt, 0))
			end)
		end

		return true
	end

	if apply() then
		return
	end

	local retryConn = retryConnections[viewportFrame]
	if retryConn then
		retryConn:Disconnect()
	end

	retryConnections[viewportFrame] = player.CharacterAdded:Connect(function(character)
		preferredCharacter = character
		character:WaitForChild("Humanoid", 10)
		character:WaitForChild("HumanoidRootPart", 10)
		task.wait(0.25)
		task.spawn(function()
			for _ = 1, 25 do
				if apply() then
					return
				end
				task.wait(0.1)
			end
		end)
	end)

	task.spawn(function()
		if preferredCharacter then
			preferredCharacter:WaitForChild("Humanoid", 10)
			preferredCharacter:WaitForChild("HumanoidRootPart", 10)
			task.wait(0.25)
		end
		for _ = 1, 25 do
			if apply() then
				return
			end
			task.wait(0.1)
		end
	end)
end

function ViewportHelper.applyCircularMask(viewportFrame: ViewportFrame)
	local corner = viewportFrame:FindFirstChildOfClass("UICorner")
	if not corner then
		corner = Instance.new("UICorner")
		corner.Parent = viewportFrame
	end
	corner.CornerRadius = UDim.new(1, 0)
end

function ViewportHelper.clear(viewportFrame: ViewportFrame)
	clearViewport(viewportFrame)
end

return ViewportHelper
