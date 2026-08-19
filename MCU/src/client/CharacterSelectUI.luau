--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterRegistry = require(ReplicatedStorage.Shared.CharacterRegistry)
local AnimationPreload = require(ReplicatedStorage.Shared.AnimationPreload)
local MorphVfxTint = require(ReplicatedStorage.Shared.MorphVfxTint)
local MorphAnimationHelper = require(ReplicatedStorage.Shared.MorphAnimationHelper)
local VfxHelper = require(ReplicatedStorage.Shared.VfxHelper)
local ViewportHelper = require(script.Parent.ViewportHelper)
local PlayerDataClient = require(script.Parent.PlayerDataClient)
local ShopUI = require(script.Parent.ShopUI)
local SettingsUI = require(script.Parent.SettingsUI)
local CoinDisplayClient = require(script.Parent.CoinDisplayClient)
local CoinPurchasePopup = require(script.Parent.CoinPurchasePopup)
local StarterGuiUtil = require(script.Parent.StarterGuiUtil)

export type SelectionController = {
	show: (skipIntro: boolean?) -> (),
	showSelection: () -> (),
	hide: () -> (),
	destroy: () -> (),
	beginDeployWhiteout: () -> (),
	endDeployWhiteout: () -> (),
}

local THEME = Color3.fromHex("238591")
local THEME_DARK = Color3.fromRGB(42, 118, 128)
local THEME_DEEP = Color3.fromRGB(28, 88, 98)
local THEME_MID = Color3.fromRGB(58, 148, 158)
local GLASS = Color3.fromRGB(18, 72, 82)
local CREAM = Color3.fromRGB(245, 252, 252)
local MUTED = Color3.fromRGB(200, 228, 232)
local GOLD = Color3.fromRGB(240, 220, 150)
local GOLD_DIM = Color3.fromRGB(210, 185, 110)
local CIRCLE_IDLE = Color3.fromRGB(28, 92, 102)
local CIRCLE_HOVER = Color3.fromRGB(48, 130, 140)
local DEPLOY_GRAD_FROM = Color3.fromRGB(48, 92, 86)
local CONFIRM_BG = Color3.fromRGB(46, 132, 78)
local CONFIRM_GRAD_FROM = Color3.fromRGB(58, 158, 96)
local CONFIRM_GRAD_TO = Color3.fromRGB(24, 88, 52)
local CLICK_SOUND_ID = "rbxassetid://3848738002"
local DEPLOY_SOUND_ID = "rbxassetid://3785105076"
local CONFIRM_SOUND_ID = "rbxassetid://3785104770"

local TWEEN_IN = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_OUT = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local HOVER = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local WHITE_IN = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local WHITE_OUT = TweenInfo.new(1.85, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
local LOADING_ZOOM = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local LOADING_WHITE_IN = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local ROTATE_SPEED = 1.35
local SELECT_DECO_IMAGE = "rbxassetid://107401688193642"
local DECO_SPIN_SPEED = 34
local SELECT_DECO_SCALE = 1.24

local CharacterSelectUI = {}

local function corner(parent: Instance, scale: number, px: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(scale, px or 0)
	c.Parent = parent
	return c
end

local function stroke(parent: Instance, color: Color3, thickness: number, trans: number): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = trans
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function uiGradient(parent: Instance, from: Color3, to: Color3, rotation: number?): UIGradient
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, from),
		ColorSequenceKeypoint.new(0.55, from:Lerp(to, 0.35)),
		ColorSequenceKeypoint.new(1, to),
	})
	g.Rotation = rotation or 90
	g.Parent = parent
	return g
end

local function applyButtonGradient(parent: Instance, from: Color3, to: Color3)
	local g = parent:FindFirstChildOfClass("UIGradient")
	if not g then
		g = uiGradient(parent, from, to, 95)
		return
	end
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, from),
		ColorSequenceKeypoint.new(0.55, from:Lerp(to, 0.35)),
		ColorSequenceKeypoint.new(1, to),
	})
end

local function addVignette(parent: Instance)
	local dim = Instance.new("Frame")
	dim.Name = "MenuDim"
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.fromRGB(8, 28, 34)
	dim.BackgroundTransparency = 0.72
	dim.BorderSizePixel = 0
	dim.ZIndex = 0
	dim.Parent = parent
	local g = Instance.new("UIGradient")
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(0.4, 0.55),
		NumberSequenceKeypoint.new(0.7, 0.62),
		NumberSequenceKeypoint.new(1, 0.08),
	})
	g.Rotation = 90
	g.Parent = dim
end

local function label(parent: Instance, name: string, text: string, size: UDim2, pos: UDim2): TextLabel
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("TextLabel") then
		return existing
	end
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = pos
	l.Font = Enum.Font.GothamMedium
	l.Text = text
	l.TextColor3 = CREAM
	l.TextScaled = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Top
	l.TextWrapped = true
	l.Parent = parent
	return l
end

local function addLayeredBackground(parent: GuiObject, rotation: number)
	parent.BackgroundColor3 = THEME_DEEP
	local base = Instance.new("UIGradient")
	base.Name = "BaseGrad"
	base.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(28, 88, 98)),
		ColorSequenceKeypoint.new(0.4, THEME_DARK),
		ColorSequenceKeypoint.new(0.75, THEME),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(48, 130, 140)),
	})
	base.Rotation = rotation
	base.Parent = parent

	local wash = Instance.new("Frame")
	wash.Name = "Wash"
	wash.Size = UDim2.fromScale(1, 1)
	wash.BackgroundColor3 = Color3.fromRGB(28, 70, 78)
	wash.BackgroundTransparency = 0.78
	wash.BorderSizePixel = 0
	wash.ZIndex = 0
	wash.Parent = parent
	local washGrad = Instance.new("UIGradient")
	washGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(8, 22, 28)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(36, 82, 90)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(12, 32, 38)),
	})
	washGrad.Rotation = rotation + 70
	washGrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(0.45, 0.7),
		NumberSequenceKeypoint.new(1, 0.3),
	})
	washGrad.Parent = wash

	local stripes = Instance.new("Frame")
	stripes.Name = "Stripes"
	stripes.Size = UDim2.fromScale(1.4, 1.4)
	stripes.AnchorPoint = Vector2.new(0.5, 0.5)
	stripes.Position = UDim2.fromScale(0.5, 0.5)
	stripes.Rotation = 28
	stripes.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	stripes.BackgroundTransparency = 0.92
	stripes.BorderSizePixel = 0
	stripes.ZIndex = 0
	stripes.Parent = parent
	local stripeGrad = Instance.new("UIGradient")
	stripeGrad.Color = ColorSequence.new(CREAM)
	stripeGrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.12, 1),
		NumberSequenceKeypoint.new(0.13, 0.9),
		NumberSequenceKeypoint.new(0.15, 1),
		NumberSequenceKeypoint.new(0.37, 1),
		NumberSequenceKeypoint.new(0.38, 0.92),
		NumberSequenceKeypoint.new(0.4, 1),
		NumberSequenceKeypoint.new(0.62, 1),
		NumberSequenceKeypoint.new(0.63, 0.92),
		NumberSequenceKeypoint.new(0.65, 1),
		NumberSequenceKeypoint.new(0.87, 1),
		NumberSequenceKeypoint.new(0.88, 0.92),
		NumberSequenceKeypoint.new(0.9, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	stripeGrad.Rotation = 90
	stripeGrad.Parent = stripes

	local vignette = Instance.new("Frame")
	vignette.Name = "Vignette"
	vignette.Size = UDim2.fromScale(1, 1)
	vignette.BackgroundColor3 = Color3.fromRGB(0, 40, 48)
	vignette.BackgroundTransparency = 0.78
	vignette.BorderSizePixel = 0
	vignette.ZIndex = 0
	vignette.Parent = parent
	local vigGrad = Instance.new("UIGradient")
	vigGrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(0.35, 0.85),
		NumberSequenceKeypoint.new(0.65, 0.85),
		NumberSequenceKeypoint.new(1, 0.35),
	})
	vigGrad.Rotation = 90
	vigGrad.Parent = vignette

	local rim = Instance.new("Frame")
	rim.Name = "InnerRim"
	rim.AnchorPoint = Vector2.new(0.5, 0.5)
	rim.Position = UDim2.fromScale(0.5, 0.5)
	rim.Size = UDim2.new(1, -18, 1, -18)
	rim.BackgroundTransparency = 1
	rim.ZIndex = 1
	rim.Parent = parent
	stroke(rim, Color3.fromRGB(90, 120, 118), 1, 0.62)
end

local function glassPanel(parent: Instance, name: string): Frame
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Frame") then
		return existing
	end
	local panel = Instance.new("Frame")
	panel.Name = name
	panel.BackgroundColor3 = GLASS
	panel.BackgroundTransparency = 0.08
	panel.BorderSizePixel = 0
	panel.Parent = parent
	corner(panel, 0, 10)
	stroke(panel, Color3.fromRGB(48, 86, 90), 1.2, 0.38)
	uiGradient(panel, Color3.fromRGB(48, 128, 138), Color3.fromRGB(22, 78, 88), 110)
	local shine = Instance.new("Frame")
	shine.Name = "Shine"
	shine.Size = UDim2.new(1, 0, 0.22, 0)
	shine.BackgroundColor3 = Color3.fromRGB(210, 220, 218)
	shine.BackgroundTransparency = 0.94
	shine.BorderSizePixel = 0
	shine.ZIndex = 0
	shine.Parent = panel
	corner(shine, 0, 10)
	uiGradient(shine, Color3.fromRGB(255, 255, 255), Color3.fromRGB(120, 140, 138), 0)
	return panel
end

local function findTyped(parent: Instance, name: string, className: string, recursive: boolean?): Instance?
	local inst = parent:FindFirstChild(name, recursive == true)
	if inst and inst:IsA(className) then
		return inst
	end
	return nil
end

local function strokeOf(btn: Instance): UIStroke?
	local ring = btn:FindFirstChildWhichIsA("UIStroke")
	if ring and ring:IsA("UIStroke") then
		return ring
	end
	return nil
end

local function hookHover(btn: GuiButton, ring: UIStroke?, isLocked: (() -> boolean)?)
	btn.AutoButtonColor = false
	local existingScale = btn:FindFirstChild("HoverScale")
	local scale: UIScale
	if existingScale and existingScale:IsA("UIScale") then
		scale = existingScale
	else
		scale = Instance.new("UIScale")
		scale.Name = "HoverScale"
		scale.Parent = btn
	end
	local baseColor = ring and ring.Color or THEME
	local baseThick = if ring then ring.Thickness else 1.2
	btn.MouseEnter:Connect(function()
		TweenService:Create(scale, HOVER, { Scale = 1.04 }):Play()
		if ring and not (isLocked and isLocked()) then
			TweenService:Create(ring, HOVER, { Color = GOLD, Thickness = baseThick + 0.6, Transparency = 0.12 }):Play()
		end
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(scale, HOVER, { Scale = 1 }):Play()
		if ring and not (isLocked and isLocked()) then
			TweenService:Create(ring, HOVER, { Color = baseColor, Thickness = baseThick, Transparency = 0.28 }):Play()
		end
	end)
	btn.MouseButton1Down:Connect(function()
		TweenService:Create(scale, HOVER, { Scale = 0.97 }):Play()
	end)
	btn.MouseButton1Up:Connect(function()
		TweenService:Create(scale, HOVER, { Scale = 1.04 }):Play()
	end)
end

function CharacterSelectUI.create(playerGui: PlayerGui, onSelect: (string, string) -> ()): SelectionController
	local roster = CharacterRegistry.getRoster()
	local selectedId: string? = nil
	local selectedSkin: string = "base"
	local awaitingDeployConfirm = false
	local deployLocked = false
	local confirmToken = 0
	local previewYaw = 0
	local page: "initial" | "select" | "shop" | "settings" = "initial"
	local circleRings: { [string]: UIStroke } = {}
	local circleFills: { [string]: TextButton } = {}
	local rosterLocks: { [string]: TextButton } = {}
	local rotateDir = 0
	local rotateConn: RBXScriptConnection? = nil
	local selectCamConn: RBXScriptConnection? = nil
	local camWatchConn: RBXScriptConnection? = nil
	local worldPreview: Model? = nil
	local worldPreviewIdle: AnimationTrack? = nil
	local selectCamActive = false
	local menuCamActive = false
	local selectPageCamActive = false
	local selectCamWarned = false
	local selectCamBound = false
	local savedCamType: Enum.CameraType? = nil
	local savedCamCf: CFrame? = nil
	local localCharHidden = false
	local SELECT_CAM_BIND = "MCU_SelectCamera"
	local MENU_CAM_MARKER = "CameraPosition1"
	local SELECT_CAM_MARKER = "CameraPosition"

	local function getMarkerCFrame(name: string): CFrame?
		local marker = Workspace:FindFirstChild(name)
		if not marker then
			return nil
		end
		if marker:IsA("BasePart") then
			return marker.CFrame
		end
		if marker:IsA("Model") then
			return marker:GetPivot()
		end
		if marker:IsA("Attachment") then
			return marker.WorldCFrame
		end
		return nil
	end

	local function setLocalCharacterHidden(hidden: boolean)
		local char = Players.LocalPlayer.Character
		if not char then
			localCharHidden = false
			return
		end
		localCharHidden = hidden
		for _, desc in char:GetDescendants() do
			if desc:IsA("BasePart") then
				desc.LocalTransparencyModifier = if hidden then 1 else 0
			end
		end
	end

	local function clearWorldPreview()
		if worldPreviewIdle then
			worldPreviewIdle:Stop(0)
			worldPreviewIdle:Destroy()
			worldPreviewIdle = nil
		end
		if worldPreview then
			worldPreview:Destroy()
			worldPreview = nil
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

	local function playWorldIdle(clone: Model, idleId: string?): AnimationTrack?
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

	local function applyWorldPreviewYaw()
		local model = worldPreview
		local spawnCf = getMarkerCFrame("SpawnSelect")
		local camCf = getMarkerCFrame(SELECT_CAM_MARKER)
		if not model or not model.Parent or not spawnCf then
			return
		end
		local pos = spawnCf.Position
		local faceCf: CFrame
		if camCf then
			local lookTarget = Vector3.new(camCf.Position.X, pos.Y, camCf.Position.Z)
			if (lookTarget - pos).Magnitude < 0.05 then
				faceCf = spawnCf
			else
				faceCf = CFrame.lookAt(pos, lookTarget)
			end
		else
			faceCf = spawnCf
		end
		model:PivotTo(faceCf * CFrame.Angles(0, previewYaw, 0))
	end

	local function spawnWorldPreview(template: Model?)
		clearWorldPreview()
		if not template then
			return
		end
		local spawnCf = getMarkerCFrame("SpawnSelect")
		if not spawnCf then
			warn("[CharacterSelect] Missing Workspace.SpawnSelect")
			return
		end
		local wasArchivable = template.Archivable
		template.Archivable = true
		local ok, clone = pcall(function()
			return template:Clone()
		end)
		template.Archivable = wasArchivable
		if not ok or not clone or not clone:IsA("Model") then
			return
		end

		for _, desc in clone:GetDescendants() do
			if desc:IsA("Script") or desc:IsA("LocalScript") or desc:IsA("ModuleScript") then
				if desc.Name ~= "Animate" then
					desc:Destroy()
				end
			elseif desc:IsA("BasePart") then
				desc.CanCollide = false
				desc.CanQuery = false
				desc.CanTouch = false
				if desc.Name == "HumanoidRootPart" then
					desc.Transparency = 1
					desc.Anchored = true
				else
					-- Leave unanchored so Motor6D idle can play
					desc.Anchored = false
				end
			elseif desc:IsA("Humanoid") then
				desc.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
				desc.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
				desc.PlatformStand = false
			end
		end
		MorphVfxTint.applyForSkin(clone, selectedId, selectedSkin, template.Name)
		MorphAnimationHelper.applyToModel(clone, MorphAnimationHelper.idleIdForMorphName(template.Name))
		clone.Name = "SelectPreviewMorph"
		clone.Parent = Workspace
		worldPreview = clone
		applyWorldPreviewYaw()
		local idleId = findIdleAnimId(clone) or MorphAnimationHelper.idleIdForMorphName(template.Name)
		worldPreviewIdle = playWorldIdle(clone, idleId)
		VfxHelper.attachNamedAssetToHrp(clone, "CharacterChooseAttachment")
		local burst = VfxHelper.attachNamedAssetToHrp(clone, "InitialParticleAttachment")
		task.delay(0.1, function()
			for _, inst in burst do
				if inst.Parent then
					VfxHelper.setParticlesEnabled(inst, false)
				end
			end
		end)
	end

	local function applyCameraAt(markerName: string): boolean
		local cam = Workspace.CurrentCamera
		local camCf = getMarkerCFrame(markerName)
		if not cam or not camCf then
			if cam then
				cam.CameraType = Enum.CameraType.Custom
				local character = Players.LocalPlayer.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if humanoid and humanoid.Health > 0 then
					cam.CameraSubject = humanoid
				end
			end
			return false
		end
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = camCf
		return true
	end

	local function applyMenuCamera(): boolean
		return applyCameraAt(MENU_CAM_MARKER)
	end

	local function applySelectPageCamera(): boolean
		return applyCameraAt(SELECT_CAM_MARKER)
	end

	local function ensureMenuCameraBind()
		if selectCamBound then
			return
		end
		selectCamBound = true
		RunService:BindToRenderStep(SELECT_CAM_BIND, Enum.RenderPriority.Last.Value, function()
			if menuCamActive then
				applyMenuCamera()
			elseif selectPageCamActive then
				applySelectPageCamera()
			end
		end)
	end

	local function reapplyActiveCamera()
		if menuCamActive then
			applyMenuCamera()
		elseif selectPageCamActive then
			applySelectPageCamera()
		end
	end

	local function enterMenuCamera()
		local cam = Workspace.CurrentCamera
		if cam and savedCamCf == nil then
			savedCamType = cam.CameraType
			savedCamCf = cam.CFrame
		end
		menuCamActive = true
		selectPageCamActive = false
		selectCamActive = true
		setLocalCharacterHidden(true)
		if not applyMenuCamera() then
			if not selectCamWarned then
				selectCamWarned = true
				warn("[CharacterSelect] Waiting for Workspace.CameraPosition1")
			end
		end
		ensureMenuCameraBind()
		if not camWatchConn then
			camWatchConn = Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
				if menuCamActive or selectPageCamActive then
					task.defer(reapplyActiveCamera)
				end
			end)
		end
		task.spawn(function()
			if not getMarkerCFrame(MENU_CAM_MARKER) then
				Workspace:WaitForChild(MENU_CAM_MARKER, 20)
			end
			if menuCamActive then
				applyMenuCamera()
			end
		end)
	end

	local function enterSelectPageCamera()
		menuCamActive = false
		selectPageCamActive = true
		selectCamActive = true
		setLocalCharacterHidden(true)
		if not applySelectPageCamera() then
			warn("[CharacterSelect] Waiting for Workspace.CameraPosition")
		end
		ensureMenuCameraBind()
		if not camWatchConn then
			camWatchConn = Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
				if menuCamActive or selectPageCamActive then
					task.defer(reapplyActiveCamera)
				end
			end)
		end
		task.spawn(function()
			if not getMarkerCFrame(SELECT_CAM_MARKER) then
				Workspace:WaitForChild(SELECT_CAM_MARKER, 20)
			end
			if selectPageCamActive then
				applySelectPageCamera()
			end
		end)
	end

	local function exitSelectCamera()
		clearWorldPreview()
		setLocalCharacterHidden(false)
		menuCamActive = false
		selectPageCamActive = false
		if selectCamBound then
			pcall(function()
				RunService:UnbindFromRenderStep(SELECT_CAM_BIND)
			end)
			selectCamBound = false
		end
		if camWatchConn then
			camWatchConn:Disconnect()
			camWatchConn = nil
		end
		if selectCamConn then
			selectCamConn:Disconnect()
			selectCamConn = nil
		end
		local cam = Workspace.CurrentCamera
		if cam and selectCamActive then
			cam.CameraType = savedCamType or Enum.CameraType.Custom
			if savedCamCf then
				cam.CFrame = savedCamCf
			end
		end
		selectCamActive = false
		savedCamType = nil
		savedCamCf = nil
	end

	local gui = StarterGuiUtil.createFreshScreenGui(playerGui, "HA_MainMenu", 80)
	local useStarterMenu = false

	local overlayGui = playerGui:FindFirstChild("HA_DeployWhiteout")
	if not overlayGui or not overlayGui:IsA("ScreenGui") then
		overlayGui = Instance.new("ScreenGui")
		overlayGui.Name = "HA_DeployWhiteout"
		overlayGui.ResetOnSpawn = false
		overlayGui.IgnoreGuiInset = true
		overlayGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		overlayGui.DisplayOrder = 200
		overlayGui.Parent = playerGui
	end
	overlayGui.Enabled = false

	Players.LocalPlayer.CharacterAdded:Connect(function()
		if not gui.Enabled then
			return
		end
		if playerGui:FindFirstChild("DeathScreen") then
			return
		end
		local function reapply()
			if not gui.Enabled then
				return
			end
			if playerGui:FindFirstChild("DeathScreen") then
				return
			end
			if menuCamActive then
				enterMenuCamera()
			elseif selectPageCamActive then
				enterSelectPageCamera()
			end
		end
		task.defer(reapply)
		task.delay(0.2, reapply)
		task.delay(0.75, reapply)
	end)

	local whiteout = overlayGui:FindFirstChild("DeployWhiteout")
	if not whiteout or not whiteout:IsA("Frame") then
		whiteout = Instance.new("Frame")
		whiteout.Name = "DeployWhiteout"
		whiteout.Size = UDim2.fromScale(1, 1)
		whiteout.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		whiteout.BackgroundTransparency = 1
		whiteout.BorderSizePixel = 0
		whiteout.ZIndex = 100
		whiteout.Visible = false
		whiteout.Parent = overlayGui
	end

	local protectedChip = overlayGui:FindFirstChild("ProtectedChip")
	if not protectedChip or not protectedChip:IsA("TextLabel") then
		protectedChip = Instance.new("TextLabel")
		protectedChip.Name = "ProtectedChip"
		protectedChip.AnchorPoint = Vector2.new(0.5, 0)
		protectedChip.Position = UDim2.new(0.5, 0, 0.08, 0)
		protectedChip.Size = UDim2.fromScale(0.135, 0.034)
		protectedChip.BackgroundColor3 = Color3.fromRGB(240, 248, 255)
		protectedChip.BackgroundTransparency = 0.12
		protectedChip.Font = Enum.Font.GothamBold
		protectedChip.Text = "Protected"
		protectedChip.TextColor3 = Color3.fromRGB(30, 70, 90)
		protectedChip.TextScaled = true
		protectedChip.Visible = false
		protectedChip.ZIndex = 101
		protectedChip.Parent = overlayGui
		corner(protectedChip, 0, 8)
	end

	local initial: CanvasGroup
	local loadingIntro: CanvasGroup
	local loadingWrap: Frame
	local loadingScale: UIScale
	local loadingBtn: TextLabel
	local playBtn: TextButton
	local shopBtn: TextButton
	local settingsBtn: TextButton
	local clickSound: Sound
	local deploySound: Sound
	local confirmSound: Sound
	local introPlayed = false
	local introPlaying = false
	local coinDisplay: CoinDisplayClient.CoinDisplay
	local coinPopup: { toggle: (anchor: GuiObject) -> (), close: () -> () }
	local layoutCoinBanner: () -> ()

	local function playUiSound(sound: Sound)
		sound.TimePosition = 0
		sound:Play()
	end

	local function playClick()
		playUiSound(clickSound)
	end

	if useStarterMenu then
		initial = StarterGuiUtil.child(gui, "InitialMenu", "CanvasGroup")
		loadingIntro = StarterGuiUtil.child(gui, "LoadingIntro", "CanvasGroup")
		loadingWrap = StarterGuiUtil.child(loadingIntro, "LoadingWrap", "Frame")
		local existingScale = loadingWrap:FindFirstChildOfClass("UIScale")
		if existingScale then
			loadingScale = existingScale
		else
			loadingScale = Instance.new("UIScale")
			loadingScale.Scale = 1
			loadingScale.Parent = loadingWrap
		end
		loadingBtn = StarterGuiUtil.child(loadingWrap, "LoadingAssets", "TextLabel")
		local btnHolder = StarterGuiUtil.child(initial, "Buttons", "Frame")
		playBtn = StarterGuiUtil.child(btnHolder, "Play", "TextButton")
		shopBtn = StarterGuiUtil.child(btnHolder, "Shop", "TextButton")
		settingsBtn = StarterGuiUtil.child(btnHolder, "Settings", "TextButton")
		local function bindMenuHover(btn: GuiButton)
			hookHover(btn, strokeOf(btn))
			btn.MouseButton1Click:Connect(playClick)
		end
		bindMenuHover(playBtn)
		bindMenuHover(shopBtn)
		bindMenuHover(settingsBtn)
		local creditsBtn = btnHolder:FindFirstChild("Credits")
		if creditsBtn and creditsBtn:IsA("GuiButton") then
			bindMenuHover(creditsBtn)
		end

		local function ensureSound(name: string, soundId: string, volume: number): Sound
			local existing = gui:FindFirstChild(name)
			if existing and existing:IsA("Sound") then
				return existing
			end
			local sound = Instance.new("Sound")
			sound.Name = name
			sound.SoundId = soundId
			sound.Volume = volume
			sound.Parent = gui
			return sound
		end
		clickSound = ensureSound("MenuClick", CLICK_SOUND_ID, 0.55)
		deploySound = ensureSound("MenuDeploy", DEPLOY_SOUND_ID, 0.7)
		confirmSound = ensureSound("MenuConfirm", CONFIRM_SOUND_ID, 0.7)

		local existingToken = gui:FindFirstChild("TokenDisplay", true) or gui:FindFirstChild("CoinDisplay", true)
		if existingToken and existingToken:IsA("Frame") then
			local existingPopup = gui:FindFirstChild("CoinPurchasePopup", true)
			coinPopup = if existingPopup and existingPopup:IsA("Frame")
				then CoinPurchasePopup.bind(existingPopup)
				else CoinPurchasePopup.create(gui, 8)
			coinDisplay = CoinDisplayClient.bind(existingToken, {
				onPlusClick = function(anchor)
					coinPopup.toggle(anchor)
				end,
			})
		else
			coinPopup = CoinPurchasePopup.create(gui, 8)
			coinDisplay = CoinDisplayClient.create(gui, {
				zIndex = 6,
				style = {
					background = GLASS,
					backgroundTransparency = 0.06,
					stroke = GOLD_DIM,
					strokeTransparency = 0.45,
					text = GOLD,
					corner = 8,
					height = 30,
				},
				onPlusClick = function(anchor)
					coinPopup.toggle(anchor)
				end,
			})
		end

		layoutCoinBanner = function()
			if page == "select" then
				coinDisplay.setAnchor(Vector2.new(1, 0), UDim2.fromScale(0.843, 0.04), UDim2.fromOffset(167, 33))
				coinDisplay.setVisible(true)
			elseif page == "shop" then
				coinDisplay.setVisible(false)
			else
				coinDisplay.setAnchor(Vector2.new(1, 0), UDim2.fromScale(0.98, 0.035), UDim2.fromOffset(167, 33))
				coinDisplay.setVisible(true)
			end
		end
		layoutCoinBanner()
	else
	initial = Instance.new("CanvasGroup")
	initial.Name = "InitialMenu"
	initial.Size = UDim2.fromScale(1, 1)
	initial.BorderSizePixel = 0
	initial.BackgroundTransparency = 1
	initial.GroupTransparency = 0
	initial.Parent = gui
	-- Transparent so world / CameraPosition1 show through (same as character select)
	addVignette(initial)

	introPlayed = false
	introPlaying = false

	loadingIntro = Instance.new("CanvasGroup")
	loadingIntro.Name = "LoadingIntro"
	loadingIntro.Size = UDim2.fromScale(1, 1)
	loadingIntro.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	loadingIntro.BackgroundTransparency = 0.4
	loadingIntro.BorderSizePixel = 0
	loadingIntro.Visible = false
	loadingIntro.ZIndex = 50
	loadingIntro.Parent = gui

	loadingWrap = Instance.new("Frame")
	loadingWrap.Name = "LoadingWrap"
	loadingWrap.AnchorPoint = Vector2.new(0.5, 0.5)
	loadingWrap.Position = UDim2.fromScale(0.5, 0.5)
	loadingWrap.Size = UDim2.fromScale(0.52, 0.11)
	loadingWrap.BackgroundTransparency = 1
	loadingWrap.ZIndex = 51
	loadingWrap.Parent = loadingIntro

	loadingScale = Instance.new("UIScale")
	loadingScale.Scale = 1
	loadingScale.Parent = loadingWrap

	loadingBtn = Instance.new("TextLabel")
	loadingBtn.Name = "LoadingAssets"
	loadingBtn.Size = UDim2.fromScale(1, 1)
	loadingBtn.BackgroundColor3 = THEME
	loadingBtn.BackgroundTransparency = 0
	loadingBtn.Font = Enum.Font.GothamBlack
	loadingBtn.Text = "LOADING ASSETS"
	loadingBtn.TextColor3 = CREAM
	loadingBtn.TextScaled = true
	loadingBtn.ZIndex = 52
	loadingBtn.Parent = loadingWrap
	corner(loadingBtn, 0, 10)
	uiGradient(loadingBtn, THEME_MID, THEME_DEEP, 95)
	stroke(loadingBtn, GOLD_DIM, 1.2, 0.42)
	local loadingPad = Instance.new("UIPadding")
	loadingPad.PaddingTop = UDim.new(0.14, 0)
	loadingPad.PaddingBottom = UDim.new(0.14, 0)
	loadingPad.PaddingLeft = UDim.new(0.08, 0)
	loadingPad.PaddingRight = UDim.new(0.08, 0)
	loadingPad.Parent = loadingBtn

	local btnHolder = Instance.new("Frame")
	btnHolder.Name = "Buttons"
	btnHolder.AnchorPoint = Vector2.new(0.5, 0.5)
	btnHolder.Position = UDim2.new(0.5, 0, 0.65, 0)
	btnHolder.Size = UDim2.new(0.25, 0, 0.522, 0)
	btnHolder.BackgroundTransparency = 1
	btnHolder.ZIndex = 2
	btnHolder.Parent = initial

	local btnLayout = Instance.new("UIListLayout")
	btnLayout.FillDirection = Enum.FillDirection.Vertical
	btnLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	btnLayout.SortOrder = Enum.SortOrder.LayoutOrder
	btnLayout.Padding = UDim.new(0.045, 0)
	btnLayout.Parent = btnHolder

	clickSound = Instance.new("Sound")
	clickSound.Name = "MenuClick"
	clickSound.SoundId = CLICK_SOUND_ID
	clickSound.Volume = 0.55
	clickSound.Parent = gui

	deploySound = Instance.new("Sound")
	deploySound.Name = "MenuDeploy"
	deploySound.SoundId = DEPLOY_SOUND_ID
	deploySound.Volume = 0.7
	deploySound.Parent = gui

	confirmSound = Instance.new("Sound")
	confirmSound.Name = "MenuConfirm"
	confirmSound.SoundId = CONFIRM_SOUND_ID
	confirmSound.Volume = 0.7
	confirmSound.Parent = gui

	local function menuButton(name: string, text: string, order: number): TextButton
		local btn = Instance.new("TextButton")
		btn.Name = name
		btn.LayoutOrder = order
		btn.Size = UDim2.new(0.82, 0, 0.2, 0)
		btn.BackgroundColor3 = THEME
		btn.BackgroundTransparency = 0
		btn.AutoButtonColor = false
		btn.Font = Enum.Font.GothamBlack
		btn.Text = text
		btn.TextColor3 = CREAM
		btn.TextScaled = true
		btn.TextStrokeTransparency = 1
		btn.ZIndex = 2
		btn.Parent = btnHolder
		corner(btn, 0, 8)
		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0.12, 0)
		pad.PaddingBottom = UDim.new(0.12, 0)
		pad.Parent = btn
		uiGradient(btn, THEME_MID, THEME_DEEP, 95)
		local ring = stroke(btn, GOLD_DIM, 1.2, 0.42)
		hookHover(btn, ring)
		btn.MouseButton1Click:Connect(function()
			playClick()
		end)
		return btn
	end

	playBtn = menuButton("Play", "PLAY", 1)
	shopBtn = menuButton("Shop", "SHOP", 2)
	settingsBtn = menuButton("Settings", "SETTINGS", 3)
	menuButton("Credits", "CREDITS", 4)

	coinPopup = CoinPurchasePopup.create(gui, 8)
	coinDisplay = CoinDisplayClient.create(gui, {
		zIndex = 6,
		style = {
			background = GLASS,
			backgroundTransparency = 0.06,
			stroke = GOLD_DIM,
			strokeTransparency = 0.45,
			text = GOLD,
			corner = 8,
			height = 30,
		},
		onPlusClick = function(anchor)
			coinPopup.toggle(anchor)
		end,
	})

	layoutCoinBanner = function()
		if page == "select" then
			coinDisplay.setAnchor(Vector2.new(1, 0), UDim2.fromScale(0.843, 0.04), UDim2.fromOffset(167, 33))
			coinDisplay.setVisible(true)
		elseif page == "shop" then
			coinDisplay.setVisible(false)
		else
			coinDisplay.setAnchor(Vector2.new(1, 0), UDim2.fromScale(0.98, 0.035), UDim2.fromOffset(167, 33))
			coinDisplay.setVisible(true)
		end
	end

	layoutCoinBanner()
	end

	local decoSpinConn: RBXScriptConnection? = nil

	local function makeBackButton(parent: Instance, zIndex: number): TextButton
		local btn = Instance.new("TextButton")
		btn.Name = "BackToMenu"
		btn.AnchorPoint = Vector2.new(0, 1)
		btn.Position = UDim2.fromScale(0.02, 0.97)
		btn.Size = UDim2.fromOffset(52, 52)
		btn.BackgroundColor3 = GLASS
		btn.BackgroundTransparency = 0.06
		btn.AutoButtonColor = false
		btn.Font = Enum.Font.GothamBlack
		btn.Text = "←"
		btn.TextColor3 = CREAM
		btn.TextScaled = true
		btn.ZIndex = zIndex
		btn.Parent = parent
		corner(btn, 0, 10)
		stroke(btn, GOLD_DIM, 1.2, 0.42)
		return btn
	end

	local function canDeploySelection(): boolean
		if not selectedId then
			return false
		end
		if not PlayerDataClient.isReady() then
			return false
		end
		if not PlayerDataClient.ownsCharacter(selectedId) then
			return false
		end
		return PlayerDataClient.ownsSkin(selectedId, selectedSkin)
	end

	local function ensureDecoSpinLoop()
		if decoSpinConn then
			return
		end
		decoSpinConn = RunService.RenderStepped:Connect(function(dt)
			if not selectedId then
				return
			end
			local btn = circleFills[selectedId]
			local deco = btn and btn:FindFirstChild("SelectedDeco")
			if deco and deco:IsA("ImageLabel") then
				deco.Rotation = (deco.Rotation + DECO_SPIN_SPEED * dt) % 360
			end
		end)
	end

	local shopPage: ShopUI.ShopPage
	local settingsPage: SettingsUI.SettingsPage
	local existingShop = gui:FindFirstChild("ShopPage")
	if existingShop and existingShop:IsA("Frame") and useStarterMenu then
		shopPage = ShopUI.bindPage(existingShop)
	else
		shopPage = ShopUI.createPage(gui)
	end
	local existingSettings = gui:FindFirstChild("SettingsPage")
	if existingSettings and existingSettings:IsA("Frame") and useStarterMenu then
		settingsPage = SettingsUI.bindPage(existingSettings, { showShoulderCam = true })
	else
		settingsPage = SettingsUI.createPage(gui, { showShoulderCam = true })
	end

	if not useStarterMenu then
		addVignette(shopPage.page)
		addVignette(settingsPage.page)
	end

	local shopBackBtn = shopPage.page:FindFirstChild("BackToMenu")
	if shopBackBtn and shopBackBtn:IsA("TextButton") then
		hookHover(shopBackBtn, strokeOf(shopBackBtn))
	else
		shopBackBtn = makeBackButton(shopPage.page, 4)
	end
	local settingsBackBtn = settingsPage.page:FindFirstChild("BackToMenu")
	if settingsBackBtn and settingsBackBtn:IsA("TextButton") then
		hookHover(settingsBackBtn, strokeOf(settingsBackBtn))
	else
		settingsBackBtn = makeBackButton(settingsPage.page, 4)
	end

	local hideSubPages: () -> ()

	if not initial:FindFirstChild("Codes") then
	local codes = Instance.new("Frame")
	codes.Name = "Codes"
	codes.AnchorPoint = Vector2.new(1, 1)
	codes.Position = UDim2.new(0.985, 0, 0.97, 0)
	codes.Size = UDim2.fromScale(0.21, 0.049)
	codes.BackgroundColor3 = GLASS
	codes.BackgroundTransparency = 0.04
	codes.ZIndex = 2
	codes.Parent = initial
	corner(codes, 0, 8)
	stroke(codes, Color3.fromRGB(48, 86, 90), 1.1, 0.42)
	uiGradient(codes, THEME, THEME_DEEP, 0)

	local codeBox = Instance.new("TextBox")
	codeBox.Name = "Input"
	codeBox.AnchorPoint = Vector2.new(0, 0.5)
	codeBox.Position = UDim2.new(0, 10, 0.5, 0)
	codeBox.Size = UDim2.new(0.62, 0, 0.62, 0)
	codeBox.BackgroundColor3 = THEME_DEEP
	codeBox.Font = Enum.Font.Gotham
	codeBox.PlaceholderText = "Enter code"
	codeBox.PlaceholderColor3 = MUTED
	codeBox.Text = ""
	codeBox.TextColor3 = CREAM
	codeBox.TextScaled = true
	codeBox.ClearTextOnFocus = false
	codeBox.ZIndex = 3
	codeBox.Parent = codes
	corner(codeBox, 0, 6)
	stroke(codeBox, Color3.fromRGB(40, 72, 76), 1, 0.5)
	uiGradient(codeBox, THEME_DEEP, Color3.fromRGB(6, 16, 20), 90)

	local redeem = Instance.new("TextButton")
	redeem.Name = "Redeem"
	redeem.AnchorPoint = Vector2.new(1, 0.5)
	redeem.Position = UDim2.new(1, -10, 0.5, 0)
	redeem.Size = UDim2.new(0.32, -4, 0.62, 0)
	redeem.BackgroundColor3 = THEME
	redeem.AutoButtonColor = false
	redeem.Font = Enum.Font.GothamBold
	redeem.Text = "Redeem"
	redeem.TextColor3 = CREAM
	redeem.TextScaled = true
	redeem.TextStrokeTransparency = 1
	redeem.ZIndex = 3
	redeem.Parent = codes
	corner(redeem, 0, 6)
	uiGradient(redeem, THEME_MID, THEME_DEEP, 90)
	local redeemRing = stroke(redeem, GOLD_DIM, 1, 0.5)
	hookHover(redeem, redeemRing)
	redeem.MouseButton1Click:Connect(function()
		playClick()
		TweenService:Create(redeem, HOVER, { BackgroundColor3 = GOLD_DIM }):Play()
		task.delay(0.18, function()
			if redeem.Parent then
				TweenService:Create(redeem, HOVER, { BackgroundColor3 = THEME }):Play()
			end
		end)
	end)
	end

	local selectPage: Frame
	local existingSelect = findTyped(gui, "CharacterSelect", "Frame", true)
	if existingSelect and existingSelect:IsA("Frame") then
		selectPage = existingSelect
	else
		selectPage = Instance.new("Frame")
		selectPage.Name = "CharacterSelect"
		selectPage.BorderSizePixel = 0
		selectPage.Parent = gui
		addVignette(selectPage)
	end
	selectPage.Parent = gui
	selectPage.Size = UDim2.fromScale(1, 1)
	selectPage.Position = UDim2.fromScale(0, 0)
	selectPage.AnchorPoint = Vector2.new(0, 0)
	selectPage.BackgroundTransparency = 1
	selectPage.Visible = false
	selectPage.ZIndex = math.max(selectPage.ZIndex, 3)
	-- Transparent so Workspace.CameraPosition / SpawnSelect morph are visible

	hideSubPages = function()
		selectPage.Visible = false
		shopPage.page.Visible = false
		settingsPage.page.Visible = false
	end

	local selectBackBtn = selectPage:FindFirstChild("BackToMenu")
	if not selectBackBtn or not selectBackBtn:IsA("TextButton") then
		selectBackBtn = makeBackButton(selectPage, 6)
	else
		hookHover(selectBackBtn, strokeOf(selectBackBtn))
	end

	local lockToast: TextLabel
	local existingLockToast = findTyped(gui, "LockToast", "TextLabel", true)
	if existingLockToast and existingLockToast:IsA("TextLabel") then
		lockToast = existingLockToast
	else
		lockToast = Instance.new("TextLabel")
		lockToast.Name = "LockToast"
		lockToast.AnchorPoint = Vector2.new(0.5, 0)
		lockToast.Position = UDim2.fromScale(0.5, 0.05)
		lockToast.Size = UDim2.fromScale(0.42, 0.055)
		lockToast.BackgroundColor3 = Color3.fromRGB(12, 36, 42)
		lockToast.BackgroundTransparency = 0.08
		lockToast.Font = Enum.Font.GothamBold
		lockToast.Text = ""
		lockToast.TextColor3 = CREAM
		lockToast.TextScaled = true
		lockToast.TextWrapped = true
		lockToast.Visible = false
		lockToast.ZIndex = 20
		lockToast.Parent = gui
		corner(lockToast, 0, 10)
		stroke(lockToast, GOLD_DIM, 1, 0.45)
	end

	local toastToken = 0
	local function showLockToast(displayName: string)
		toastToken += 1
		local token = toastToken
		lockToast.Text = string.format("You don't own %s. Purchase it in the Shop.", displayName)
		lockToast.Visible = true
		task.delay(2.8, function()
			if token == toastToken then
				lockToast.Visible = false
			end
		end)
	end

	local function showSkinLockToast(skinName: string)
		toastToken += 1
		local token = toastToken
		lockToast.Text = string.format("You don't own the %s skin. Purchase it in the Shop.", skinName)
		lockToast.Visible = true
		task.delay(2.8, function()
			if token == toastToken then
				lockToast.Visible = false
			end
		end)
	end

	local function showDeployLockToast()
		toastToken += 1
		local token = toastToken
		lockToast.Text = "You don't own this character or skin. Unlock it in the Shop before deploying."
		lockToast.Visible = true
		task.delay(2.8, function()
			if token == toastToken then
				lockToast.Visible = false
			end
		end)
	end

	local function refreshRosterLocks()
		for heroId, btn in circleFills do
			local owned = PlayerDataClient.ownsCharacter(heroId)
			local lock = rosterLocks[heroId]
			if owned then
				if lock then
					lock.Visible = false
					lock.Active = false
				end
				btn.Active = true
			else
				if not lock then
					lock = Instance.new("TextButton")
					lock.Name = "Lock"
					lock.Size = UDim2.fromScale(1, 1)
					lock.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
					lock.BackgroundTransparency = 0.45
					lock.AutoButtonColor = false
					lock.Font = Enum.Font.GothamBlack
					lock.Text = "Locked"
					lock.TextColor3 = GOLD
					lock.TextScaled = true
					lock.ZIndex = 8
					lock.Parent = btn
					corner(lock, 1, 0)
					lock.MouseButton1Click:Connect(function()
						playClick()
						local entry = CharacterRegistry.getById(heroId)
						showLockToast(if entry then entry.displayName else heroId)
					end)
					rosterLocks[heroId] = lock
				end
				lock.Visible = true
				lock.Active = true
				btn.Active = false
			end
		end
	end

	local info = glassPanel(selectPage, "Info")
	info.Position = UDim2.fromScale(0.025, 0.04)
	info.Size = UDim2.fromScale(0.172, 0.412)
	info.ZIndex = 4
	info.Visible = true
	if not info:FindFirstChildWhichIsA("UIPadding") then
		local infoPad = Instance.new("UIPadding")
		infoPad.PaddingTop = UDim.new(0.05, 0)
		infoPad.PaddingBottom = UDim.new(0.05, 0)
		infoPad.PaddingLeft = UDim.new(0.07, 0)
		infoPad.PaddingRight = UDim.new(0.07, 0)
		infoPad.Parent = info
	end

	local nameLabel = label(info, "Name", "Name: —", UDim2.new(1, 0, 0.1, 0), UDim2.fromScale(0, 0))
	nameLabel.Font = Enum.Font.GothamBold
	local aliasLabel = label(info, "Alias", "Alias: —", UDim2.new(1, 0, 0.1, 0), UDim2.fromScale(0, 0.12))
	local powersLabel = label(info, "Powers", "Powers: —", UDim2.new(1, 0, 0.22, 0), UDim2.fromScale(0, 0.24))
	local bioLabel = label(info, "Biography", "Biography: —", UDim2.new(1, 0, 0.5, 0), UDim2.fromScale(0, 0.48))
	bioLabel.TextColor3 = MUTED

	local skins = glassPanel(selectPage, "Skins")
	skins.AnchorPoint = Vector2.new(1, 0)
	skins.Position = UDim2.fromScale(0.975, 0.04)
	skins.Size = UDim2.fromScale(0.124, 0.315)
	skins.ZIndex = 4
	skins.Visible = true

	local skinsTitle = label(skins, "Title", "Skins", UDim2.new(1, -16, 0, 26), UDim2.fromOffset(8, 10))
	skinsTitle.Font = Enum.Font.GothamBold
	skinsTitle.TextXAlignment = Enum.TextXAlignment.Center
	skinsTitle.TextColor3 = GOLD

	local skinsList: ScrollingFrame
	local existingSkinsList = skins:FindFirstChild("List")
	if existingSkinsList and existingSkinsList:IsA("ScrollingFrame") then
		skinsList = existingSkinsList
		for _, child in skinsList:GetChildren() do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end
	else
		skinsList = Instance.new("ScrollingFrame")
		skinsList.Name = "List"
		skinsList.Position = UDim2.fromOffset(8, 42)
		skinsList.Size = UDim2.new(1, -16, 1, -52)
		skinsList.BackgroundTransparency = 1
		skinsList.BorderSizePixel = 0
		skinsList.ScrollBarThickness = 4
		skinsList.CanvasSize = UDim2.new(0, 0, 0, 0)
		skinsList.AutomaticCanvasSize = Enum.AutomaticSize.Y
		skinsList.ZIndex = 2
		skinsList.Parent = skins
	end
	if not skinsList:FindFirstChildWhichIsA("UIListLayout") then
		local skinsLayout = Instance.new("UIListLayout")
		skinsLayout.Padding = UDim.new(0, 8)
		skinsLayout.SortOrder = Enum.SortOrder.LayoutOrder
		skinsLayout.Parent = skinsList
	end

	local previewWrap: Frame
	local existingPreview = selectPage:FindFirstChild("Preview")
	if existingPreview and existingPreview:IsA("Frame") then
		previewWrap = existingPreview
	else
		previewWrap = Instance.new("Frame")
		previewWrap.Name = "Preview"
		previewWrap.Parent = selectPage
	end
	previewWrap.AnchorPoint = Vector2.new(0.5, 0)
	previewWrap.Position = UDim2.new(0.5, 0, 0.04, 0)
	previewWrap.Size = UDim2.fromScale(0.345, 0.412)
	previewWrap.BackgroundTransparency = 1
	previewWrap.ZIndex = 3
	previewWrap.Visible = true

	local previewVp: ViewportFrame
	local existingVp = previewWrap:FindFirstChild("Model")
	if existingVp and existingVp:IsA("ViewportFrame") then
		previewVp = existingVp
	else
		previewVp = Instance.new("ViewportFrame")
		previewVp.Name = "Model"
		previewVp.Parent = previewWrap
		previewVp.AnchorPoint = Vector2.new(0.5, 0.5)
		previewVp.Position = UDim2.fromScale(0.5, 0.5)
		previewVp.Size = UDim2.fromScale(0.72, 0.92)
		previewVp.BackgroundTransparency = 1
		previewVp.BorderSizePixel = 0
		corner(previewVp, 1, 0)
	end
	previewVp.Visible = false
	previewVp.ZIndex = 3

	local leftArrow: TextButton
	local existingLeft = previewWrap:FindFirstChild("RotateLeft")
	if existingLeft and existingLeft:IsA("TextButton") then
		leftArrow = existingLeft
		hookHover(leftArrow, strokeOf(leftArrow))
	else
		leftArrow = Instance.new("TextButton")
		leftArrow.Name = "RotateLeft"
		leftArrow.AnchorPoint = Vector2.new(0, 0.5)
		leftArrow.Position = UDim2.new(0.02, 0, 0.5, 0)
		leftArrow.Size = UDim2.fromScale(0.1, 0.18)
		leftArrow.BackgroundColor3 = THEME_DEEP
		leftArrow.AutoButtonColor = false
		leftArrow.Font = Enum.Font.GothamBlack
		leftArrow.Text = "<"
		leftArrow.TextColor3 = CREAM
		leftArrow.TextScaled = true
		leftArrow.TextStrokeTransparency = 1
		leftArrow.ZIndex = 4
		leftArrow.Parent = previewWrap
		corner(leftArrow, 0, 8)
		uiGradient(leftArrow, THEME, THEME_DEEP, 90)
		hookHover(leftArrow, stroke(leftArrow, GOLD_DIM, 1, 0.5))
	end

	local rightArrow: TextButton
	local existingRight = previewWrap:FindFirstChild("RotateRight")
	if existingRight and existingRight:IsA("TextButton") then
		rightArrow = existingRight
		hookHover(rightArrow, strokeOf(rightArrow))
	else
		rightArrow = Instance.new("TextButton")
		rightArrow.Name = "RotateRight"
		rightArrow.AnchorPoint = Vector2.new(1, 0.5)
		rightArrow.Position = UDim2.new(0.98, 0, 0.5, 0)
		rightArrow.Size = UDim2.fromScale(0.1, 0.18)
		rightArrow.BackgroundColor3 = THEME_DEEP
		rightArrow.AutoButtonColor = false
		rightArrow.Font = Enum.Font.GothamBlack
		rightArrow.Text = ">"
		rightArrow.TextColor3 = CREAM
		rightArrow.TextScaled = true
		rightArrow.TextStrokeTransparency = 1
		rightArrow.ZIndex = 4
		rightArrow.Parent = previewWrap
		corner(rightArrow, 0, 8)
		uiGradient(rightArrow, THEME, THEME_DEEP, 90)
		hookHover(rightArrow, stroke(rightArrow, GOLD_DIM, 1, 0.5))
	end

	local deployStrip: Frame
	local existingStrip = selectPage:FindFirstChild("DeployStrip")
	if existingStrip and existingStrip:IsA("Frame") then
		deployStrip = existingStrip
	else
		deployStrip = Instance.new("Frame")
		deployStrip.Name = "DeployStrip"
		deployStrip.Parent = selectPage
	end
	deployStrip.AnchorPoint = Vector2.new(0.5, 1)
	deployStrip.Position = UDim2.new(0.5, 0, 0.705, -12)
	deployStrip.Size = UDim2.fromScale(0.345, 0.055)
	deployStrip.BackgroundTransparency = 1
	deployStrip.ZIndex = 4
	deployStrip.Visible = true

	local deploy: TextButton
	local existingDeploy = deployStrip:FindFirstChild("Deploy") or selectPage:FindFirstChild("Deploy")
	if existingDeploy and existingDeploy:IsA("TextButton") then
		deploy = existingDeploy
		hookHover(deploy, strokeOf(deploy))
	else
		deploy = Instance.new("TextButton")
		deploy.Name = "Deploy"
		deploy.AnchorPoint = Vector2.new(0.5, 0.5)
		deploy.Position = UDim2.fromScale(0.5, 0.5)
		deploy.Size = UDim2.fromScale(0.55, 0.82)
		deploy.BackgroundColor3 = THEME
		deploy.AutoButtonColor = false
		deploy.Font = Enum.Font.GothamBlack
		deploy.Text = "DEPLOY"
		deploy.TextColor3 = CREAM
		deploy.TextScaled = true
		deploy.TextStrokeTransparency = 1
		deploy.ZIndex = 5
		deploy.Parent = deployStrip
		corner(deploy, 0, 8)
		uiGradient(deploy, DEPLOY_GRAD_FROM, THEME_DEEP, 95)
		hookHover(deploy, stroke(deploy, GOLD, 1.3, 0.32))
	end
	deploy.Visible = false

	local function keepLayoutObject(child: Instance): boolean
		return child:IsA("UIListLayout")
			or child:IsA("UIPadding")
			or child:IsA("UICorner")
			or child:IsA("UIStroke")
			or child:IsA("UIGradient")
			or child:IsA("UIAspectRatioConstraint")
	end

	local rosterBar: ScrollingFrame
	local existingRoster = selectPage:FindFirstChild("Roster")
	if existingRoster and existingRoster:IsA("ScrollingFrame") then
		rosterBar = existingRoster
		for _, child in rosterBar:GetChildren() do
			if not keepLayoutObject(child) then
				child:Destroy()
			end
		end
	else
		rosterBar = Instance.new("ScrollingFrame")
		rosterBar.Name = "Roster"
		rosterBar.BackgroundColor3 = GLASS
		rosterBar.BackgroundTransparency = 0.06
		rosterBar.BorderSizePixel = 0
		rosterBar.ScrollBarThickness = 6
		rosterBar.ScrollingDirection = Enum.ScrollingDirection.X
		rosterBar.CanvasSize = UDim2.new(0, 0, 0, 0)
		rosterBar.AutomaticCanvasSize = Enum.AutomaticSize.X
		rosterBar.Parent = selectPage
		corner(rosterBar, 0, 12)
		stroke(rosterBar, Color3.fromRGB(48, 86, 90), 1.2, 0.4)
		uiGradient(rosterBar, Color3.fromRGB(14, 36, 42), Color3.fromRGB(6, 16, 20), 0)
	end
	rosterBar.AnchorPoint = Vector2.new(0.5, 1)
	rosterBar.Position = UDim2.new(0.5, 0, 0.985, 0)
	rosterBar.Size = UDim2.fromScale(0.78, 0.28)
	rosterBar.ZIndex = 4
	rosterBar.Visible = true

	if not rosterBar:FindFirstChildWhichIsA("UIPadding") then
		local rosterPad = Instance.new("UIPadding")
		rosterPad.PaddingLeft = UDim.new(0, 27)
		rosterPad.PaddingRight = UDim.new(0, 27)
		rosterPad.PaddingTop = UDim.new(0, 9)
		rosterPad.PaddingBottom = UDim.new(0, 9)
		rosterPad.Parent = rosterBar
	end

	if not rosterBar:FindFirstChildWhichIsA("UIListLayout") then
		local rosterLayout = Instance.new("UIListLayout")
		rosterLayout.FillDirection = Enum.FillDirection.Horizontal
		rosterLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		rosterLayout.Padding = UDim.new(0, 12)
		rosterLayout.SortOrder = Enum.SortOrder.LayoutOrder
		rosterLayout.Parent = rosterBar
	end

	local rosterLeftGap = Instance.new("Frame")
	rosterLeftGap.Name = "LeftGap"
	rosterLeftGap.LayoutOrder = -10
	rosterLeftGap.Size = UDim2.fromOffset(28, 1)
	rosterLeftGap.BackgroundTransparency = 1
	rosterLeftGap.Parent = rosterBar

	local function ensureRotateLoop()
		if rotateConn then
			return
		end
		rotateConn = RunService.RenderStepped:Connect(function(dt)
			if rotateDir == 0 or not selectedId then
				return
			end
			previewYaw += rotateDir * ROTATE_SPEED * dt
			applyWorldPreviewYaw()
			if selectPageCamActive then
				applySelectPageCamera()
			elseif menuCamActive then
				applyMenuCamera()
			end
		end)
	end

	local function bindHoldRotate(btn: TextButton, dir: number)
		btn.MouseButton1Down:Connect(function()
			playClick()
			rotateDir = dir
			ensureRotateLoop()
		end)
		btn.MouseButton1Up:Connect(function()
			if rotateDir == dir then
				rotateDir = 0
			end
		end)
		btn.MouseLeave:Connect(function()
			if rotateDir == dir then
				rotateDir = 0
			end
		end)
	end
	bindHoldRotate(leftArrow, -1)
	bindHoldRotate(rightArrow, 1)

	local function setDeployLabel(isConfirm: boolean)
		if isConfirm then
			deploy.Text = "CONFIRM"
			deploy.BackgroundColor3 = CONFIRM_BG
			applyButtonGradient(deploy, CONFIRM_GRAD_FROM, CONFIRM_GRAD_TO)
		else
			deploy.Text = "DEPLOY"
			deploy.BackgroundColor3 = THEME
			applyButtonGradient(deploy, DEPLOY_GRAD_FROM, THEME_DEEP)
		end
	end

	local function refreshPreview()
		if not selectedId then
			deploy.Visible = false
			clearWorldPreview()
			return
		end
		local entry = CharacterRegistry.getById(selectedId)
		if not entry then
			return
		end
		nameLabel.Text = "Name: " .. entry.displayName
		aliasLabel.Text = "Alias: " .. entry.alias
		powersLabel.Text = "Powers: " .. entry.powers
		bioLabel.Text = "Biography: " .. entry.biography
		deploy.Visible = canDeploySelection()
		deploy.Active = deploy.Visible and not deployLocked
		if deploy.Visible and not deployLocked and not awaitingDeployConfirm then
			setDeployLabel(false)
		end
		local template = CharacterRegistry.getMorphTemplate(selectedId, selectedSkin)
		spawnWorldPreview(template)
	end

	local function rebuildSkins()
		for _, child in skinsList:GetChildren() do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end
		if not selectedId then
			return
		end
		local entry = CharacterRegistry.getById(selectedId)
		if not entry then
			return
		end
		if not PlayerDataClient.ownsSkin(selectedId, selectedSkin) then
			for _, skin in entry.skins do
				if not skin.blocked and PlayerDataClient.ownsSkin(selectedId, skin.id) then
					selectedSkin = skin.id
					break
				end
			end
		end
		for i, skin in entry.skins do
			local owned = not skin.blocked and PlayerDataClient.ownsSkin(selectedId, skin.id)
			local btn = Instance.new("TextButton")
			btn.Name = skin.id
			btn.LayoutOrder = i
			btn.Size = UDim2.new(1, 0, 0, 24)
			btn.AutoButtonColor = false
			btn.BackgroundColor3 = THEME_DEEP
			btn.Font = Enum.Font.GothamBold
			btn.Text = if owned then skin.name else (skin.name .. "  ·  Locked")
			btn.TextColor3 = if owned then CREAM else MUTED
			btn.TextScaled = true
			btn.TextStrokeTransparency = 1
			btn.Parent = skinsList
			corner(btn, 0, 6)
			local selected = owned and skin.id == selectedSkin
			uiGradient(btn, if selected then THEME_MID else THEME_DEEP, THEME_DEEP, 90)
			local ring = stroke(btn, if selected then GOLD else Color3.fromRGB(48, 86, 90), if selected then 1.6 else 1, if selected then 0.18 else 0.48)
			if selected then
				btn.BackgroundColor3 = THEME_MID
			end
			if not owned then
				btn.BackgroundTransparency = 0.15
			end
			hookHover(btn, ring, function()
				return selected
			end)
			btn.MouseButton1Click:Connect(function()
				if deployLocked then
					return
				end
				if not owned then
					playClick()
					showSkinLockToast(skin.name)
					return
				end
				playClick()
				selectedSkin = skin.id
				previewYaw = 0
				rebuildSkins()
				refreshPreview()
			end)
		end
	end

	local function paintCircleRings()
		for heroId, ring in circleRings do
			local picked = heroId == selectedId
			ring.Color = if picked then GOLD else THEME
			ring.Thickness = if picked then 2.8 else 1.4
			ring.Transparency = if picked then 0.05 else 0.28
			local btn = circleFills[heroId]
			if btn then
				if not picked then
					btn.BackgroundColor3 = CIRCLE_IDLE
				else
					btn.BackgroundColor3 = THEME_DEEP
				end
				local deco = btn:FindFirstChild("SelectedDeco")
				if picked then
					if not deco or not deco:IsA("ImageLabel") then
						if deco then
							deco:Destroy()
						end
						deco = Instance.new("ImageLabel")
						deco.Name = "SelectedDeco"
						deco.AnchorPoint = Vector2.new(0.5, 0.5)
						deco.Position = UDim2.fromScale(0.5, 0.5)
						deco.Size = UDim2.fromScale(SELECT_DECO_SCALE, SELECT_DECO_SCALE)
						deco.BackgroundTransparency = 1
						deco.Image = SELECT_DECO_IMAGE
						deco.ImageColor3 = Color3.new(1, 1, 1)
						deco.ScaleType = Enum.ScaleType.Stretch
						deco.ZIndex = 5
						deco.Parent = btn
						corner(deco, 1, 0)
					else
						deco.Size = UDim2.fromScale(SELECT_DECO_SCALE, SELECT_DECO_SCALE)
						deco.ImageColor3 = Color3.new(1, 1, 1)
					end
				elseif deco then
					deco:Destroy()
				end
			end
		end
	end

	local function selectHero(heroId: string)
		if deployLocked then
			return
		end
		selectedId = heroId
		selectedSkin = "base"
		previewYaw = 0
		awaitingDeployConfirm = false
		confirmToken += 1
		rebuildSkins()
		refreshPreview()
		paintCircleRings()
	end

	local COL = 2
	local colFrames: { Frame } = {}
	local function columnFor(index: number): Frame
		local colIndex = math.floor((index - 1) / COL) + 1
		local existing = colFrames[colIndex]
		if existing then
			return existing
		end
		local col = Instance.new("Frame")
		col.Name = "Col" .. tostring(colIndex)
		col.LayoutOrder = colIndex
		col.Size = UDim2.new(0, 0, 1, 0)
		col.AutomaticSize = Enum.AutomaticSize.X
		col.BackgroundTransparency = 1
		col.Parent = rosterBar
		local list = Instance.new("UIListLayout")
		list.FillDirection = Enum.FillDirection.Vertical
		list.HorizontalAlignment = Enum.HorizontalAlignment.Center
		list.VerticalAlignment = Enum.VerticalAlignment.Center
		list.Padding = UDim.new(0.04, 0)
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Parent = col
		colFrames[colIndex] = col
		return col
	end

	for index, entry in roster do
		local col = columnFor(index)
		local btn = Instance.new("TextButton")
		btn.Name = entry.id
		btn.LayoutOrder = ((index - 1) % COL) + 1
		btn.Size = UDim2.new(0, 118, 0.52, 0)
		btn.BackgroundColor3 = CIRCLE_IDLE
		btn.Text = ""
		btn.AutoButtonColor = false
		btn.Parent = col
		local aspect = Instance.new("UIAspectRatioConstraint")
		aspect.AspectRatio = 1
		aspect.DominantAxis = Enum.DominantAxis.Height
		aspect.Parent = btn
		corner(btn, 1, 0)
		uiGradient(btn, CIRCLE_HOVER, CIRCLE_IDLE, 120)
		local ring = stroke(btn, THEME, 1.4, 0.28)
		circleRings[entry.id] = ring
		circleFills[entry.id] = btn

		local vp = Instance.new("ViewportFrame")
		vp.Name = "Preview"
		vp.Size = UDim2.fromScale(0.92, 0.92)
		vp.Position = UDim2.fromScale(0.04, 0.04)
		vp.BackgroundTransparency = 1
		vp.BorderSizePixel = 0
		vp.ZIndex = 2
		vp.Parent = btn
		corner(vp, 1, 0)

		local chip = Instance.new("TextLabel")
		chip.Name = "HoverName"
		chip.AnchorPoint = Vector2.new(0.5, 0.5)
		chip.Position = UDim2.fromScale(0.5, 0.5)
		chip.Size = UDim2.fromScale(0.75, 0.75)
		chip.BackgroundColor3 = THEME_DEEP
		chip.BackgroundTransparency = 1
		chip.Font = Enum.Font.GothamBold
		chip.Text = entry.displayName
		chip.TextColor3 = CREAM
		chip.TextScaled = true
		chip.TextTransparency = 1
		chip.ZIndex = 4
		chip.Parent = btn
		corner(chip, 1, 0)
		local chipPad = Instance.new("UIPadding")
		chipPad.PaddingTop = UDim.new(0.28, 0)
		chipPad.PaddingBottom = UDim.new(0.28, 0)
		chipPad.PaddingLeft = UDim.new(0.1, 0)
		chipPad.PaddingRight = UDim.new(0.1, 0)
		chipPad.Parent = chip

		local template = CharacterRegistry.getMorphTemplate(entry.id, "base")
		if template then
			ViewportHelper.bindTemplate(vp, template, 0, "select")
		end

		hookHover(btn, ring, function()
			return selectedId == entry.id
		end)
		btn.MouseEnter:Connect(function()
			if selectedId ~= entry.id then
				TweenService:Create(btn, HOVER, { BackgroundColor3 = CIRCLE_HOVER }):Play()
			end
			TweenService:Create(chip, HOVER, { TextTransparency = 0, BackgroundTransparency = 0.28 }):Play()
		end)
		btn.MouseLeave:Connect(function()
			if selectedId ~= entry.id then
				TweenService:Create(btn, HOVER, { BackgroundColor3 = CIRCLE_IDLE }):Play()
			end
			TweenService:Create(chip, HOVER, { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
		end)
		btn.MouseButton1Click:Connect(function()
			playClick()
			if not PlayerDataClient.ownsCharacter(entry.id) then
				showLockToast(entry.displayName)
				return
			end
			selectHero(entry.id)
		end)
	end

	refreshRosterLocks()

	local function validateSelectionOwnership()
		if selectedId and not PlayerDataClient.ownsCharacter(selectedId) then
			selectedId = nil
			selectedSkin = "base"
			awaitingDeployConfirm = false
			confirmToken += 1
			setDeployLabel(false)
			nameLabel.Text = "Name: —"
			aliasLabel.Text = "Alias: —"
			powersLabel.Text = "Powers: —"
			bioLabel.Text = "Biography: —"
			clearWorldPreview()
			rebuildSkins()
			paintCircleRings()
		end
		refreshPreview()
	end

	PlayerDataClient.onChanged(function()
		refreshRosterLocks()
		validateSelectionOwnership()
	end)

	local whiteoutTween: Tween? = nil

	local function beginDeployWhiteout()
		if whiteoutTween then
			whiteoutTween:Cancel()
			whiteoutTween = nil
		end
		overlayGui.Enabled = true
		whiteout.Visible = true
		whiteout.BackgroundTransparency = 1
		whiteoutTween = TweenService:Create(whiteout, WHITE_IN, { BackgroundTransparency = 0 })
		whiteoutTween:Play()
	end

	local function endDeployWhiteout()
		if whiteoutTween then
			whiteoutTween:Cancel()
			whiteoutTween = nil
		end
		overlayGui.Enabled = true
		local covering = whiteout.BackgroundTransparency < 0.98
		if covering then
			whiteout.Visible = true
			whiteoutTween = TweenService:Create(whiteout, WHITE_OUT, { BackgroundTransparency = 1 })
			whiteoutTween:Play()
			local fadeToken = whiteoutTween
			task.delay(WHITE_OUT.Time, function()
				if whiteout.Parent and whiteoutTween == fadeToken then
					whiteout.Visible = false
					whiteoutTween = nil
					overlayGui.Enabled = false
				end
			end)
		else
			whiteout.Visible = false
			whiteout.BackgroundTransparency = 1
			if whiteout.BackgroundTransparency >= 0.99 then
				overlayGui.Enabled = false
			end
		end
	end

	deploy.MouseButton1Click:Connect(function()
		if deployLocked then
			return
		end
		if not selectedId then
			return
		end
		if not canDeploySelection() then
			showDeployLockToast()
			return
		end
		if not awaitingDeployConfirm then
			awaitingDeployConfirm = true
			setDeployLabel(true)
			playUiSound(deploySound)
			confirmToken += 1
			local token = confirmToken
			task.delay(3, function()
				if token ~= confirmToken or deployLocked or not awaitingDeployConfirm then
					return
				end
				awaitingDeployConfirm = false
				setDeployLabel(false)
			end)
			return
		end
		deployLocked = true
		awaitingDeployConfirm = false
		confirmToken += 1
		deploy.Active = false
		playUiSound(confirmSound)
		beginDeployWhiteout()
		task.delay(0.32, function()
			onSelect(selectedId :: string, selectedSkin)
		end)
	end)

	local function showInitial()
		page = "initial"
		hideSubPages()
		loadingIntro.Visible = false
		enterMenuCamera()
		initial.Visible = true
		initial.GroupTransparency = 0
		selectPage.BackgroundTransparency = 1
		layoutCoinBanner()
	end

	local function playLoadingIntro()
		if introPlaying or introPlayed then
			showInitial()
			return
		end
		introPlaying = true
		gui.Enabled = true
		initial.Visible = false
		hideSubPages()
		selectPage.Visible = false
		shopPage.page.Visible = false
		settingsPage.page.Visible = false
		loadingIntro.Visible = true
		loadingIntro.GroupTransparency = 0
		loadingScale.Scale = 1
		endDeployWhiteout()
		enterMenuCamera()

		local pulseRunning = true
		task.spawn(function()
			while pulseRunning and loadingIntro.Visible do
				local up = TweenService:Create(loadingScale, TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
					Scale = 1.04,
				})
				up:Play()
				up.Completed:Wait()
				if not pulseRunning or not loadingIntro.Visible then
					break
				end
				local down = TweenService:Create(loadingScale, TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
					Scale = 1,
				})
				down:Play()
				down.Completed:Wait()
			end
		end)

		local function finishIntro()
			if not introPlaying then
				return
			end
			pulseRunning = false
			overlayGui.Enabled = true
			whiteout.Visible = true
			whiteout.BackgroundTransparency = 1

			local zoomTween = TweenService:Create(loadingScale, LOADING_ZOOM, { Scale = 14 })
			zoomTween:Play()
			task.delay(0.35, function()
				if introPlaying then
					TweenService:Create(whiteout, LOADING_WHITE_IN, { BackgroundTransparency = 0 }):Play()
				end
			end)
			zoomTween.Completed:Wait()
			task.wait(0.12)

			loadingIntro.Visible = false
			introPlaying = false
			introPlayed = true
			showInitial()
			endDeployWhiteout()
		end

		if AnimationPreload.isReady() then
			finishIntro()
		else
			AnimationPreload.onReady(finishIntro)
		end
	end

	local function showShop()
		page = "shop"
		initial.Visible = false
		initial.GroupTransparency = 0
		hideSubPages()
		shopPage.page.Visible = true
		shopPage.refresh()
		enterMenuCamera()
		layoutCoinBanner()
	end

	local function showSettings()
		page = "settings"
		initial.Visible = false
		initial.GroupTransparency = 0
		hideSubPages()
		settingsPage.page.Visible = true
		settingsPage.refresh()
		enterMenuCamera()
		layoutCoinBanner()
	end

	local function showSelect()
		page = "select"
		hideSubPages()
		loadingIntro.Visible = false
		initial.Visible = false
		initial.GroupTransparency = 0
		selectPage.Visible = true
		selectPage.BackgroundTransparency = 1
		info.Visible = true
		skins.Visible = true
		rosterBar.Visible = true
		layoutCoinBanner()
		enterSelectPageCamera()
		if selectedId then
			refreshPreview()
		end
	end

	ensureDecoSpinLoop()

	playBtn.MouseButton1Click:Connect(function()
		showSelect()
	end)

	shopBtn.MouseButton1Click:Connect(function()
		showShop()
	end)

	settingsBtn.MouseButton1Click:Connect(function()
		showSettings()
	end)

	selectBackBtn.MouseButton1Click:Connect(function()
		playClick()
		showInitial()
	end)

	shopBackBtn.MouseButton1Click:Connect(function()
		playClick()
		showInitial()
	end)

	settingsBackBtn.MouseButton1Click:Connect(function()
		playClick()
		showInitial()
	end)

	return {
		show = function(skipIntro: boolean?)
			selectedId = nil
			selectedSkin = "base"
			previewYaw = 0
			deployLocked = false
			awaitingDeployConfirm = false
			confirmToken += 1
			deploy.Active = true
			deploy.Visible = false
			setDeployLabel(false)
			nameLabel.Text = "Name: —"
			aliasLabel.Text = "Alias: —"
			powersLabel.Text = "Powers: —"
			bioLabel.Text = "Biography: —"
			clearWorldPreview()
			rebuildSkins()
			paintCircleRings()
			hideSubPages()
			endDeployWhiteout()
			if skipIntro == true or introPlayed then
				gui.Enabled = true
				showInitial()
			else
				playLoadingIntro()
			end
		end,
			showSelection = function()
				selectedId = nil
				selectedSkin = "base"
				previewYaw = 0
				deployLocked = false
				awaitingDeployConfirm = false
				confirmToken += 1
				deploy.Active = true
				deploy.Visible = false
				setDeployLabel(false)
				clearWorldPreview()
				rebuildSkins()
				paintCircleRings()
				gui.Enabled = true
				showSelect()
			end,
		hide = function()
			introPlaying = false
			gui.Enabled = false
			loadingIntro.Visible = false
			rotateDir = 0
			exitSelectCamera()
		end,
		destroy = function()
			if rotateConn then
				rotateConn:Disconnect()
			end
			exitSelectCamera()
			gui:Destroy()
			overlayGui:Destroy()
		end,
		beginDeployWhiteout = beginDeployWhiteout,
		endDeployWhiteout = endDeployWhiteout,
	}
end

return CharacterSelectUI
