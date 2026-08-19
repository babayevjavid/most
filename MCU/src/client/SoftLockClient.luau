--!strict
--[[
	Soft lock-on: when enabled, only locks if a living humanoid is inside a
	small screen-space area around the cursor. Otherwise aim follows the mouse.
	OFF by default.
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local GameConstants = require(ReplicatedStorage.Shared.GameConstants)

local SoftLockClient = {}

local ICON_SIZE = 72

local enabled = false
local lockedTarget: Model? = nil
local player: Player? = nil
local playerGui: PlayerGui? = nil
local screenGui: ScreenGui? = nil
local lockImage: ImageLabel? = nil
local started = false

local function getRoot(model: Model): BasePart?
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end
	local torso = model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso")
	if torso and torso:IsA("BasePart") then
		return torso
	end
	if model.PrimaryPart then
		return model.PrimaryPart
	end
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head
	end
	return nil
end

local function getAimCenter(model: Model): Vector3?
	local root = getRoot(model)
	if root then
		return root.Position
	end
	return model:GetPivot().Position
end

local function isValidTarget(model: Model, selfChar: Model?): boolean
	if model == selfChar then
		return false
	end
	if model.Name == "FearClone" or model:GetAttribute("FearVisual") == true then
		return false
	end
	if model:GetAttribute("LokiDecoy") == true or model:GetAttribute("LokiUltClone") == true then
		return false
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return false
	end
	return getRoot(model) ~= nil
end

local function ensureIcon()
	if lockImage and lockImage.Parent and screenGui and screenGui.Parent then
		return
	end
	local parentGui = playerGui
	if not parentGui then
		return
	end

	if screenGui then
		screenGui:Destroy()
		screenGui = nil
		lockImage = nil
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "MCU_SoftLock"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 200
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = true
	gui.Parent = parentGui
	screenGui = gui

	local img = Instance.new("ImageLabel")
	img.Name = "LockIcon"
	img.AnchorPoint = Vector2.new(0.5, 0.5)
	img.Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE)
	img.BackgroundTransparency = 1
	img.BorderSizePixel = 0
	img.Image = GameConstants.SOFT_LOCK_ICON
	img.ImageTransparency = 0
	img.ScaleType = Enum.ScaleType.Fit
	img.Visible = false
	img.ZIndex = 10
	img.Parent = gui
	lockImage = img
end

local function hideIcon()
	if lockImage then
		lockImage.Visible = false
	end
end

local function showIconAt(screenX: number, screenY: number)
	ensureIcon()
	local img = lockImage
	if not img then
		return
	end
	-- IgnoreGuiInset ScreenGui uses full viewport coords (same as WorldToViewportPoint)
	img.Position = UDim2.fromOffset(math.floor(screenX + 0.5), math.floor(screenY + 0.5))
	img.Image = GameConstants.SOFT_LOCK_ICON
	img.Visible = true
end

local function clearLock()
	lockedTarget = nil
	hideIcon()
end

local function getCursorViewport(): Vector2
	local mouse = UserInputService:GetMouseLocation()
	local inset = GuiService:GetGuiInset()
	return Vector2.new(mouse.X - inset.X, mouse.Y - inset.Y)
end

local function screenDistToCursor(camera: Camera, worldPos: Vector3, cursor: Vector2): number?
	local screenPos, onScreen = camera:WorldToViewportPoint(worldPos)
	if screenPos.Z <= 0 then
		return nil
	end
	if not onScreen then
		-- Still allow if the projected point is just outside the viewport but near the cursor.
		local dx = screenPos.X - cursor.X
		local dy = screenPos.Y - cursor.Y
		local dist = math.sqrt(dx * dx + dy * dy)
		if dist > GameConstants.SOFT_LOCK_HOLD_SCREEN_PX then
			return nil
		end
		return dist
	end
	local dx = screenPos.X - cursor.X
	local dy = screenPos.Y - cursor.Y
	return math.sqrt(dx * dx + dy * dy)
end

local function findStickyTarget(selfChar: Model, camera: Camera): Model?
	local selfRoot = getRoot(selfChar)
	local selfPos = if selfRoot then selfRoot.Position else selfChar:GetPivot().Position
	local maxRange = GameConstants.SOFT_LOCK_MAX_RANGE
	local cursor = getCursorViewport()
	local acquirePx = GameConstants.SOFT_LOCK_SCREEN_PX
	local holdPx = GameConstants.SOFT_LOCK_HOLD_SCREEN_PX

	if lockedTarget and lockedTarget.Parent and isValidTarget(lockedTarget, selfChar) then
		local root = getRoot(lockedTarget)
		if root and (root.Position - selfPos).Magnitude <= maxRange then
			local distPx = screenDistToCursor(camera, root.Position, cursor)
			if distPx ~= nil and distPx <= holdPx then
				return lockedTarget
			end
		end
	end

	local best: Model? = nil
	local bestPx = math.huge

	local function consider(model: Model)
		if not isValidTarget(model, selfChar) then
			return
		end
		local root = getRoot(model)
		if not root then
			return
		end
		local dist = (root.Position - selfPos).Magnitude
		if dist > maxRange or dist < 1 then
			return
		end
		local distPx = screenDistToCursor(camera, root.Position, cursor)
		if distPx == nil or distPx > acquirePx then
			return
		end
		if distPx < bestPx then
			bestPx = distPx
			best = model
		end
	end

	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { selfChar }
	local parts = Workspace:GetPartBoundsInRadius(selfPos, maxRange, overlap)
	local seen: { [Model]: boolean } = {}
	for _, part in parts do
		local current: Instance? = part
		while current do
			if current:IsA("Model") and current ~= selfChar then
				local hum = current:FindFirstChildOfClass("Humanoid")
				if hum then
					if not seen[current] then
						seen[current] = true
						consider(current)
					end
					break
				end
			end
			current = current.Parent
		end
	end
	return best
end

function SoftLockClient.isEnabled(): boolean
	return enabled
end

function SoftLockClient.setEnabled(on: boolean)
	enabled = on == true
	if not enabled then
		clearLock()
	end
end

function SoftLockClient.toggle(): boolean
	SoftLockClient.setEnabled(not enabled)
	return enabled
end

function SoftLockClient.getLockedTarget(): Model?
	if not enabled then
		return nil
	end
	return lockedTarget
end

function SoftLockClient.getLockedAimPoint(): Vector3?
	if not enabled or not lockedTarget or not lockedTarget.Parent then
		return nil
	end
	return getAimCenter(lockedTarget)
end

function SoftLockClient.init(localPlayer: Player)
	if started then
		return
	end
	started = true
	player = localPlayer
	playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui
	ensureIcon()

	RunService.RenderStepped:Connect(function()
		if not enabled then
			if lockedTarget then
				clearLock()
			else
				hideIcon()
			end
			return
		end

		local plr = player
		if not plr then
			return
		end
		local character = plr.Character
		local camera = Workspace.CurrentCamera
		if not character or not camera then
			clearLock()
			return
		end

		lockedTarget = findStickyTarget(character, camera)

		if lockedTarget and lockedTarget.Parent then
			local center = getAimCenter(lockedTarget)
			if center then
				local screenPos, onScreen = camera:WorldToViewportPoint(center)
				if onScreen and screenPos.Z > 0 then
					showIconAt(screenPos.X, screenPos.Y)
				else
					hideIcon()
				end
			else
				hideIcon()
			end
		else
			hideIcon()
		end
	end)
end

return SoftLockClient
