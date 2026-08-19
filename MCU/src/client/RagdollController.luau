--!strict
--[[
	Local visuals for living Ragdolled status (adapted from NewMarvelProject).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConstants = require(ReplicatedStorage.Shared.GameConstants)

local RagdollController = {}

local MOTOR6D_PART_MAP: { [string]: string } = {
	-- R15
	["Neck"] = "Head",
	["LeftShoulder"] = "LeftUpperArm",
	["RightShoulder"] = "RightUpperArm",
	["Waist"] = "LowerTorso",
	["LeftHip"] = "LeftUpperLeg",
	["RightHip"] = "RightUpperLeg",
	["Root"] = "UpperTorso",
	["LeftElbow"] = "LeftLowerArm",
	["RightElbow"] = "RightLowerArm",
	["LeftKnee"] = "LeftLowerLeg",
	["RightKnee"] = "RightLowerLeg",
	["LeftWrist"] = "LeftHand",
	["RightWrist"] = "RightHand",
	["LeftAnkle"] = "LeftFoot",
	["RightAnkle"] = "RightFoot",
	-- R6 / blocky
	["RootJoint"] = "Torso",
	["Left Shoulder"] = "Left Arm",
	["Right Shoulder"] = "Right Arm",
	["Left Hip"] = "Left Leg",
	["Right Hip"] = "Right Leg",
}

local function findAnimateScript(character: Model): LocalScript?
	local direct = character:FindFirstChild("Animate")
	if direct and direct:IsA("LocalScript") then
		return direct
	end
	for _, desc in character:GetDescendants() do
		if desc:IsA("LocalScript") and desc.Name == "Animate" then
			return desc
		end
	end
	return nil
end

local function reconnectDisconnectedMotor6Ds(character: Model)
	for _, desc in character:GetDescendants() do
		if desc:IsA("Motor6D") and not desc.Part1 then
			local motor = desc :: Motor6D
			local targetPartName = MOTOR6D_PART_MAP[motor.Name]
			if targetPartName then
				local targetPart = character:FindFirstChild(targetPartName)
				if targetPart and targetPart:IsA("BasePart") then
					motor.Part1 = targetPart
				end
			end
		end
	end
end

local function disconnectRagdollMotorsLocal(character: Model)
	local folder = character:FindFirstChild("RagdollConstraints")
	local any = false
	if folder then
		for _, constraint in folder:GetChildren() do
			if constraint:IsA("Constraint") then
				local rigidPointer = constraint:FindFirstChild("RigidJoint")
				local rigidJoint = rigidPointer and rigidPointer:IsA("ObjectValue") and rigidPointer.Value
				if rigidJoint and rigidJoint:IsA("Motor6D") and rigidJoint.Part1 ~= nil then
					rigidJoint.Part1 = nil
					any = true
				end
			end
		end
	end
	-- Blocky R15: if constraints missing/empty, still limp the body locally
	if not any then
		for _, desc in character:GetDescendants() do
			if desc:IsA("Motor6D") and desc.Name ~= "Root" and desc.Name ~= "RootJoint" and desc.Part1 ~= nil then
				desc.Part1 = nil
			end
		end
	end
end

local function stopNonAbilityAnimations(humanoid: Humanoid)
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		track:Stop()
	end
end

local function getRagdollCameraPart(character: Model): BasePart?
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head
	end
	return nil
end

function RagdollController.init(player: Player)
	local ragdollConn: RBXScriptConnection? = nil
	local getUpConn: RBXScriptConnection? = nil
	local humanoidStateConn: RBXScriptConnection? = nil
	local ragdollCameraConn: RBXScriptConnection? = nil
	local ragdollMaintainConn: RBXScriptConnection? = nil
	local ragdollCameraSubject: Instance? = nil

	local function stopRagdollMaintain()
		if ragdollMaintainConn then
			ragdollMaintainConn:Disconnect()
			ragdollMaintainConn = nil
		end
	end

	local function startRagdollMaintain(character: Model, humanoid: Humanoid)
		stopRagdollMaintain()
		ragdollMaintainConn = RunService.Heartbeat:Connect(function()
			if not character.Parent or character:GetAttribute("Ragdolled") ~= true then
				stopRagdollMaintain()
				return
			end
			disconnectRagdollMotorsLocal(character)
			local st = humanoid:GetState()
			if st ~= Enum.HumanoidStateType.Physics and st ~= Enum.HumanoidStateType.Dead then
				pcall(function()
					humanoid:ChangeState(Enum.HumanoidStateType.Physics)
				end)
			end
			local animate = findAnimateScript(character)
			if animate and not animate.Disabled then
				animate.Disabled = true
			end
		end)
	end

	local function stopRagdollCameraFollow()
		if ragdollCameraConn then
			ragdollCameraConn:Disconnect()
			ragdollCameraConn = nil
		end
	end

	local function applyRagdollCameraFollow(character: Model, humanoid: Humanoid, enabled: boolean)
		local cam = Workspace.CurrentCamera
		if not cam then
			return
		end
		if enabled then
			local followPart = getRagdollCameraPart(character)
			if not followPart then
				return
			end
			if ragdollCameraSubject == nil then
				ragdollCameraSubject = cam.CameraSubject
			end
			cam.CameraType = Enum.CameraType.Custom
			cam.CameraSubject = followPart
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
			stopRagdollCameraFollow()
			ragdollCameraConn = RunService.RenderStepped:Connect(function()
				if character:GetAttribute("Ragdolled") ~= true or not character.Parent then
					return
				end
				local part = getRagdollCameraPart(character)
				if part and cam.CameraSubject ~= part then
					cam.CameraSubject = part
				end
			end)
		else
			stopRagdollCameraFollow()
			if ragdollCameraSubject ~= nil then
				cam.CameraSubject = ragdollCameraSubject
				ragdollCameraSubject = nil
			elseif humanoid.Health > 0 then
				cam.CameraSubject = humanoid
			end
		end
	end

	local function clearLocalRagdollState(character: Model, humanoid: Humanoid)
		stopRagdollMaintain()
		stopRagdollCameraFollow()
		applyRagdollCameraFollow(character, humanoid, false)

		local animate = findAnimateScript(character)
		if animate then
			animate.Disabled = character:GetAttribute(GameConstants.GETTING_UP_ATTRIBUTE) == true
		end

		local state = humanoid:GetState()
		if state == Enum.HumanoidStateType.Physics or state == Enum.HumanoidStateType.FallingDown then
			if humanoid.Health > 0 then
				humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
				task.defer(function()
					if not humanoid.Parent or not character.Parent then
						return
					end
					if character:GetAttribute("Ragdolled") == true then
						return
					end
					if character:GetAttribute(GameConstants.GETTING_UP_ATTRIBUTE) == true then
						return
					end
					humanoid:ChangeState(Enum.HumanoidStateType.Running)
				end)
			end
		elseif humanoid.Health > 0 and character:GetAttribute(GameConstants.GETTING_UP_ATTRIBUTE) ~= true then
			humanoid:ChangeState(Enum.HumanoidStateType.Running)
		end

		reconnectDisconnectedMotor6Ds(character)
		if character:GetAttribute(GameConstants.GETTING_UP_ATTRIBUTE) ~= true then
			stopNonAbilityAnimations(humanoid)
		end

		local cam = Workspace.CurrentCamera
		if cam and humanoid.Health > 0 then
			cam.CameraType = Enum.CameraType.Custom
			cam.CameraSubject = humanoid
			ragdollCameraSubject = nil
		end
	end

	local function applyLocalRagdollVisual(enabled: boolean)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not character or not humanoid then
			return
		end

		local animate = findAnimateScript(character)
		if enabled then
			humanoid:ChangeState(Enum.HumanoidStateType.Physics)
			stopNonAbilityAnimations(humanoid)
			if animate then
				animate.Disabled = true
			end
			disconnectRagdollMotorsLocal(character)
			applyRagdollCameraFollow(character, humanoid, true)
			startRagdollMaintain(character, humanoid)
		else
			clearLocalRagdollState(character, humanoid)
			if character:GetAttribute(GameConstants.GETTING_UP_ATTRIBUTE) == true then
				local animate = findAnimateScript(character)
				if animate then
					animate.Disabled = true
				end
			end
		end
	end

	local function bindHumanoidStateGuard(character: Model, humanoid: Humanoid)
		if humanoidStateConn then
			humanoidStateConn:Disconnect()
			humanoidStateConn = nil
		end
		humanoidStateConn = humanoid.StateChanged:Connect(function(_, newState)
			if newState == Enum.HumanoidStateType.FallingDown then
				if character:GetAttribute("Ragdolled") == true or humanoid.Health <= 0 then
					return
				end
				humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
			if character:GetAttribute("Ragdolled") ~= true then
				return
			end
			local animate = findAnimateScript(character)
			if not animate then
				return
			end
			if newState ~= Enum.HumanoidStateType.Physics and newState ~= Enum.HumanoidStateType.GettingUp and animate.Disabled then
				humanoid:ChangeState(Enum.HumanoidStateType.Physics)
			end
		end)
	end

	local function onCharacterAdded(character: Model)
		ragdollCameraSubject = nil
		stopRagdollCameraFollow()
		stopRagdollMaintain()
		if ragdollConn then
			ragdollConn:Disconnect()
			ragdollConn = nil
		end
		if getUpConn then
			getUpConn:Disconnect()
			getUpConn = nil
		end

		ragdollConn = character:GetAttributeChangedSignal("Ragdolled"):Connect(function()
			applyLocalRagdollVisual(character:GetAttribute("Ragdolled") == true)
		end)
		getUpConn = character:GetAttributeChangedSignal(GameConstants.GETTING_UP_ATTRIBUTE):Connect(function()
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			local animate = findAnimateScript(character)
			if character:GetAttribute(GameConstants.GETTING_UP_ATTRIBUTE) == true then
				if animate then
					animate.Disabled = true
				end
			else
				if animate then
					animate.Disabled = false
				end
				if humanoid and humanoid.Health > 0 and character:GetAttribute("Ragdolled") ~= true then
					humanoid:ChangeState(Enum.HumanoidStateType.Running)
				end
			end
		end)

		local humanoid = character:WaitForChild("Humanoid", 5) :: Humanoid?
		if not humanoid then
			return
		end
		bindHumanoidStateGuard(character, humanoid)
		applyLocalRagdollVisual(character:GetAttribute("Ragdolled") == true)
	end

	if player.Character then
		onCharacterAdded(player.Character)
	end
	player.CharacterAdded:Connect(onCharacterAdded)
end

return RagdollController
