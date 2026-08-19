--!strict
--[[
	Shoulder Cam — custom over-shoulder lock (not Roblox Shift Lock).
	Smooth camera offset up + left/right, center crosshair, Ctrl toggle.
	Does not rotate the body during flight or while abilities control orientation.
	(Alt is reserved for Scarlet Witch dash.)
]]

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConstants = require(ReplicatedStorage.Shared.GameConstants)

local ShoulderCamClient = {}

local CROSSHAIR_IMAGE = "rbxassetid://9563788818"
local OFFSET_RIGHT = Vector3.new(1.75, 0.4, 0)
local OFFSET_LEFT = Vector3.new(-1.75, 0.4, 0)
local LERP_SPEED = 11
local ROTATE_SPEED = 14

local player: Player? = nil
local enabled = false
local side: string = "Right" -- "Right" | "Left"
local keybind: string = "Ctrl" -- locked to Ctrl (Alt = hex dash)
local currentOffset = Vector3.zero
local savedAutoRotate: boolean? = nil
local bodyControlActive = false -- true while we currently own AutoRotate / body facing

local crosshairGui: ScreenGui? = nil
local crosshairImage: ImageLabel? = nil

local function getTargetOffset(): Vector3
	return if side == "Left" then OFFSET_LEFT else OFFSET_RIGHT
end

local function isToggleKey(keyCode: Enum.KeyCode): boolean
	return keyCode == Enum.KeyCode.LeftControl or keyCode == Enum.KeyCode.RightControl
end

--[[ Abilities / states that own character orientation — shoulder cam must not fight them. ]]
local function shouldSuspendBodyControl(character: Model): boolean
	if character:GetAttribute(GameConstants.IS_FLYING_ATTRIBUTE) == true then
		return true
	end
	if character:GetAttribute(GameConstants.ICE_SLIDE_ATTRIBUTE) == true then
		return true
	end
	if character:GetAttribute(GameConstants.BUSY_ATTRIBUTE) == true then
		return true
	end
	if character:GetAttribute(GameConstants.RAGDOLLED_ATTRIBUTE) == true then
		return true
	end
	if character:GetAttribute(GameConstants.TK_ACTIVE_ATTRIBUTE) == true then
		return true
	end
	if character:GetAttribute(GameConstants.TELEPORT_AIMING_ATTRIBUTE) == true then
		return true
	end
	if character:GetAttribute(GameConstants.SHIELD_ACTIVE_ATTRIBUTE) == true then
		return true
	end
	if character:GetAttribute("BarrageSpinActive") == true then
		return true
	end
	if character:GetAttribute("AbsorbActive") == true then
		return true
	end
	if character:GetAttribute(GameConstants.DISINTEGRATE_ACTIVE_ATTRIBUTE) == true then
		return true
	end
	if character:GetAttribute(GameConstants.LOKI_SHAPESHIFT_ATTRIBUTE) == true then
		return true
	end
	if character:GetAttribute("AbilityActive_hex_beam") == true then
		return true
	end
	if character:GetAttribute("AbilityActive_forcefield_crush") == true then
		return true
	end
	if character:GetAttribute("AbilityActive_forcefield_smash") == true then
		return true
	end
	return false
end

local function applyMouseLock(on: boolean)
	if on then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		-- Hide default cursor; only the center ImageLabel shows
		UserInputService.MouseIconEnabled = false
		UserInputService.MouseIcon = ""
	else
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
		UserInputService.MouseIcon = ""
	end
end

local function ensureCrosshair(playerGui: PlayerGui)
	if crosshairGui and crosshairGui.Parent then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "MCU_ShoulderCam"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 250
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = true
	gui.Parent = playerGui

	local img = Instance.new("ImageLabel")
	img.Name = "Crosshair"
	img.AnchorPoint = Vector2.new(0.5, 0.5)
	img.Position = UDim2.fromScale(0.5, 0.5)
	img.Size = UDim2.fromOffset(28, 28)
	img.BackgroundTransparency = 1
	img.BorderSizePixel = 0
	img.Image = CROSSHAIR_IMAGE
	img.ImageTransparency = 0
	img.ImageColor3 = Color3.new(1, 1, 1)
	img.ScaleType = Enum.ScaleType.Fit
	img.Visible = false
	img.ZIndex = 100
	img.Parent = gui

	crosshairGui = gui
	crosshairImage = img
end

local function setCrosshairVisible(on: boolean)
	if crosshairImage then
		crosshairImage.Visible = on
		if on then
			crosshairImage.Image = CROSSHAIR_IMAGE
			crosshairImage.ImageTransparency = 0
		end
	end
	if crosshairGui then
		crosshairGui.Enabled = true
	end
end

local function releaseBodyControl(humanoid: Humanoid?)
	if not bodyControlActive then
		return
	end
	bodyControlActive = false
	if humanoid then
		if savedAutoRotate ~= nil then
			humanoid.AutoRotate = savedAutoRotate
			savedAutoRotate = nil
		else
			humanoid.AutoRotate = true
		end
	else
		savedAutoRotate = nil
	end
end

local function takeBodyControl(humanoid: Humanoid)
	if bodyControlActive then
		if humanoid.AutoRotate then
			humanoid.AutoRotate = false
		end
		return
	end
	bodyControlActive = true
	if savedAutoRotate == nil then
		savedAutoRotate = humanoid.AutoRotate
	end
	humanoid.AutoRotate = false
end

function ShoulderCamClient.isEnabled(): boolean
	return enabled
end

function ShoulderCamClient.getSide(): string
	return side
end

function ShoulderCamClient.getKeybind(): string
	return keybind
end

function ShoulderCamClient.setSide(newSide: string)
	if newSide == "Left" or newSide == "Right" then
		side = newSide
	end
end

function ShoulderCamClient.setKeybind(newBind: string)
	-- Alt is reserved for Scarlet Witch dash — shoulder lock stays on Ctrl
	if newBind == "Ctrl" then
		keybind = "Ctrl"
	end
end

function ShoulderCamClient.setEnabled(on: boolean)
	local plr = player
	local character = plr and plr.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	enabled = on
	setCrosshairVisible(on)
	applyMouseLock(on)

	if not on then
		releaseBodyControl(humanoid)
		currentOffset = Vector3.zero
	end
end

function ShoulderCamClient.toggle(): boolean
	ShoulderCamClient.setEnabled(not enabled)
	return enabled
end

function ShoulderCamClient.init(localPlayer: Player)
	player = localPlayer
	local playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui
	ensureCrosshair(playerGui)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		if not isToggleKey(input.KeyCode) then
			return
		end
		if UserInputService:GetFocusedTextBox() then
			return
		end
		ShoulderCamClient.toggle()
	end)

	local function hookCharacter(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 5)
		if humanoid and humanoid:IsA("Humanoid") then
			humanoid.Died:Connect(function()
				ShoulderCamClient.setEnabled(false)
			end)
		end
	end

	if localPlayer.Character then
		task.spawn(hookCharacter, localPlayer.Character)
	end
	localPlayer.CharacterAdded:Connect(function(character)
		-- Never keep shoulder cam across death/respawn
		ShoulderCamClient.setEnabled(false)
		hookCharacter(character)
	end)

	localPlayer.CharacterRemoving:Connect(function()
		ShoulderCamClient.setEnabled(false)
	end)

	RunService:BindToRenderStep("MCU_ShoulderCam", Enum.RenderPriority.Camera.Value + 2, function(dt)
		local plr = player
		local character = plr and plr.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local cam = workspace.CurrentCamera

		-- Dead / missing character: force off
		if enabled and (not character or not humanoid or humanoid.Health <= 0) then
			ShoulderCamClient.setEnabled(false)
		end

		local teleportCam = character ~= nil and character:GetAttribute("SwTeleportCam") == true
		local suspendBody = character ~= nil and shouldSuspendBodyControl(character)
		-- Camera offset still applies while enabled (including flight); body facing does not
		local alpha = math.clamp(dt * LERP_SPEED, 0, 1)
		local want = if enabled and not teleportCam then getTargetOffset() else Vector3.zero
		currentOffset = currentOffset:Lerp(want, alpha)

		if cam and currentOffset.Magnitude > 0.001 and not teleportCam then
			cam.CFrame = cam.CFrame * CFrame.new(currentOffset)
		end

		if not enabled then
			if humanoid then
				releaseBodyControl(humanoid)
			end
			return
		end

		if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
			applyMouseLock(true)
		else
			UserInputService.MouseIconEnabled = false
			UserInputService.MouseIcon = ""
		end
		setCrosshairVisible(true)

		if not character or not humanoid or not cam then
			return
		end

		if suspendBody then
			releaseBodyControl(humanoid)
			return
		end

		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			return
		end

		takeBodyControl(humanoid)

		local look = cam.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude < 0.05 then
			return
		end
		flat = flat.Unit
		local targetCf = CFrame.new(root.Position, root.Position + flat)
		root.CFrame = root.CFrame:Lerp(targetCf, math.clamp(dt * ROTATE_SPEED, 0, 1))
	end)
end

return ShoulderCamClient
