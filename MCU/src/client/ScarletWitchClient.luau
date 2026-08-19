--!strict

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CameraShakeClient = require(script.Parent.CameraShakeClient)
local ScreenFxClient = require(script.Parent.ScreenFxClient)
local AbilityCooldownHelper = require(ReplicatedStorage.Shared.AbilityCooldownHelper)
local GameConstants = require(ReplicatedStorage.Shared.GameConstants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local ScarletWitchClient = {}

local TELEPORT_CAM_BIND = "MCU_HexDisplacementCam"

function ScarletWitchClient.init(localPlayer: Player)
	local gui = Instance.new("ScreenGui")
	gui.Name = "SwControlLock"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 80
	gui.Parent = localPlayer:WaitForChild("PlayerGui")

	local dim = Instance.new("Frame")
	dim.Name = "Dim"
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.fromRGB(18, 6, 10)
	dim.BackgroundTransparency = 1
	dim.BorderSizePixel = 0
	dim.Parent = gui

	local message = Instance.new("TextLabel")
	message.Name = "Message"
	message.AnchorPoint = Vector2.new(0.5, 0.5)
	message.Position = UDim2.fromScale(0.5, 0.46)
	message.Size = UDim2.fromScale(0.72, 0.22)
	message.BackgroundTransparency = 1
	message.Font = Enum.Font.GothamMedium
	message.Text =
		"You lost control of your powers due to their complexity and your lack of knowledge over them."
	message.TextColor3 = Color3.fromRGB(255, 210, 220)
	message.TextTransparency = 1
	message.TextWrapped = true
	message.TextScaled = true
	message.Parent = gui

	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = 28
	constraint.MinTextSize = 14
	constraint.Parent = message

	-- Sit above SW mode panels / ability bar so it does not overlap HUD frames.
	local resultPanel = Instance.new("Frame")
	resultPanel.Name = "ProbabilityHexResult"
	resultPanel.AnchorPoint = Vector2.new(0, 1)
	resultPanel.Position = UDim2.new(0, 14, 1, -210)
	resultPanel.Size = UDim2.fromOffset(210, 28)
	resultPanel.BackgroundColor3 = Color3.fromRGB(38, 12, 18)
	resultPanel.BackgroundTransparency = 1
	resultPanel.BorderSizePixel = 0
	resultPanel.ZIndex = 40
	resultPanel.Visible = false
	resultPanel.Parent = gui

	local resultCorner = Instance.new("UICorner")
	resultCorner.CornerRadius = UDim.new(0, 6)
	resultCorner.Parent = resultPanel

	local resultStroke = Instance.new("UIStroke")
	resultStroke.Color = Color3.fromRGB(215, 55, 75)
	resultStroke.Transparency = 1
	resultStroke.Thickness = 1
	resultStroke.Parent = resultPanel

	local resultLabel = Instance.new("TextLabel")
	resultLabel.Name = "Text"
	resultLabel.Position = UDim2.fromOffset(8, 0)
	resultLabel.Size = UDim2.new(1, -16, 1, 0)
	resultLabel.BackgroundTransparency = 1
	resultLabel.Font = Enum.Font.GothamMedium
	resultLabel.TextColor3 = Color3.fromRGB(255, 220, 225)
	resultLabel.TextSize = 12
	resultLabel.TextTransparency = 1
	resultLabel.TextTruncate = Enum.TextTruncate.AtEnd
	resultLabel.TextXAlignment = Enum.TextXAlignment.Left
	resultLabel.ZIndex = 41
	resultLabel.Parent = resultPanel

	local resultToken = 0
	Remotes.getEvent("ProbabilityHexResult").OnClientEvent:Connect(function(payload: any)
		if type(payload) ~= "table" or type(payload.outcome) ~= "string" then
			return
		end
		local targetName = if type(payload.targetName) == "string" then payload.targetName else "Target"
		local duration = if type(payload.duration) == "number" then payload.duration else 10
		if payload.outcome == "object" then
			resultLabel.Text = string.format("%s → object", targetName)
		elseif payload.outcome == "powers_stripped" then
			resultLabel.Text = string.format("%s → no powers (%ds)", targetName, duration)
		else
			return
		end
		resultToken += 1
		local token = resultToken
		resultPanel.Visible = true
		TweenService:Create(resultPanel, TweenInfo.new(0.15), { BackgroundTransparency = 0.18 }):Play()
		TweenService:Create(resultStroke, TweenInfo.new(0.15), { Transparency = 0.25 }):Play()
		TweenService:Create(resultLabel, TweenInfo.new(0.15), { TextTransparency = 0 }):Play()
		task.delay(2.4, function()
			if resultToken ~= token then
				return
			end
			TweenService:Create(resultPanel, TweenInfo.new(0.28), { BackgroundTransparency = 1 }):Play()
			TweenService:Create(resultStroke, TweenInfo.new(0.28), { Transparency = 1 }):Play()
			local fade = TweenService:Create(resultLabel, TweenInfo.new(0.28), { TextTransparency = 1 })
			fade:Play()
			fade.Completed:Once(function()
				if resultToken == token then
					resultPanel.Visible = false
				end
			end)
		end)
	end)

	local shown = false
	local function setLockVisual(on: boolean)
		if shown == on then
			return
		end
		shown = on
		local info = TweenInfo.new(if on then 0.45 else 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(dim, info, { BackgroundTransparency = if on then 0.42 else 1 }):Play()
		TweenService:Create(message, info, { TextTransparency = if on then 0 else 1 }):Play()
		CameraShakeClient.setHeldLayer("swControlLock", on, {
			fade = if on then 0.45 else 0.6,
			shake = if on then 0.12 else 0,
			fov = if on then 2.2 else 0,
			vignette = if on then 0.35 else 1,
			shakeRange = 1.05,
			shakeSlow = 0.48,
		})
	end

	local function hook(character: Model)
		local lingerUntil = 0
		local function anyAbilityActive(model: Model): boolean
			for name, value in model:GetAttributes() do
				if type(name) == "string" and string.sub(name, 1, 14) == "AbilityActive_" and value == true then
					return true
				end
			end
			return false
		end
		local function refreshScreen()
			local hero = character:GetAttribute(GameConstants.HERO_ATTRIBUTE)
			local activeNow = hero == "scarlet_witch"
				and (
					anyAbilityActive(character)
					or character:GetAttribute(GameConstants.TK_ACTIVE_ATTRIBUTE) == true
					or character:GetAttribute(GameConstants.SHIELD_ACTIVE_ATTRIBUTE) == true
					or character:GetAttribute(GameConstants.IS_FLYING_ATTRIBUTE) == true
					or character:GetAttribute(GameConstants.SW_CONTROL_LOCK_ATTRIBUTE) == true
					or character:GetAttribute(GameConstants.BUSY_ATTRIBUTE) == true
					or AbilityCooldownHelper.isAnyActive(character, {
						"telekinesis",
						"hex_beam",
						"hex_bolt",
						"hex_blast",
						"hex_shield",
						"hex_flight",
						"probability_hex",
						"hex_displacement",
						"rune_entrapment",
						"regeneration",
					})
				)
			if activeNow then
				lingerUntil = os.clock() + 1.35
			end
			local showFx = activeNow or os.clock() < lingerUntil
			ScreenFxClient.setEnabled("scarlet_witch", showFx)
			CameraShakeClient.setHeldLayer("swPowers", showFx, {
				fade = if showFx then 0.34 else 0.75,
				shake = if showFx then 0.08 else 0,
				fov = if showFx then -1.55 else 0,
				vignette = if showFx then 0.5 else 1,
				shakeRange = 0.88,
				shakeSlow = 0.42,
			})
			if lingerUntil > os.clock() and not activeNow then
				task.delay(1.4, refreshScreen)
			end
		end
		local function sync()
			local on = character:GetAttribute(GameConstants.HERO_ATTRIBUTE) == "scarlet_witch"
				and character:GetAttribute(GameConstants.SW_CONTROL_LOCK_ATTRIBUTE) == true
			setLockVisual(on)
			refreshScreen()
		end
		character:GetAttributeChangedSignal(GameConstants.SW_CONTROL_LOCK_ATTRIBUTE):Connect(sync)
		character:GetAttributeChangedSignal(GameConstants.HERO_ATTRIBUTE):Connect(sync)
		character:GetAttributeChangedSignal(GameConstants.TK_ACTIVE_ATTRIBUTE):Connect(refreshScreen)
		character:GetAttributeChangedSignal(GameConstants.SHIELD_ACTIVE_ATTRIBUTE):Connect(refreshScreen)
		character:GetAttributeChangedSignal(GameConstants.IS_FLYING_ATTRIBUTE):Connect(refreshScreen)
		character:GetAttributeChangedSignal(GameConstants.BUSY_ATTRIBUTE):Connect(refreshScreen)
		character.AttributeChanged:Connect(function(attr)
			if string.sub(attr, 1, 14) == "AbilityActive_" then
				refreshScreen()
			end
		end)
		sync()
		refreshScreen()
	end

	localPlayer.CharacterAdded:Connect(function(character)
		setLockVisual(false)
		ScreenFxClient.setEnabled("scarlet_witch", false)
		CameraShakeClient.setHeldLayer("swPowers", false, { fade = 0.2 })
		hook(character)
	end)
	localPlayer.CharacterRemoving:Connect(function()
		setLockVisual(false)
		ScreenFxClient.setEnabled("scarlet_witch", false)
		CameraShakeClient.setHeldLayer("swPowers", false, { fade = 0.2 })
	end)
	if localPlayer.Character then
		hook(localPlayer.Character)
	end

	local savedSubject: Instance? = nil
	local savedType: Enum.CameraType? = nil
	local followPart: BasePart? = nil
	local following = false
	local followToken = 0

	local function stopFollowBind()
		pcall(function()
			RunService:UnbindFromRenderStep(TELEPORT_CAM_BIND)
		end)
	end

	local function restoreCam()
		followToken += 1
		local character = localPlayer.Character
		if character then
			character:SetAttribute("SwTeleportCam", nil)
		end
		stopFollowBind()
		if not following then
			followPart = nil
			return
		end
		following = false
		followPart = nil
		local cam = workspace.CurrentCamera
		local hum = character and character:FindFirstChildOfClass("Humanoid")
		if cam then
			cam.CameraType = savedType or Enum.CameraType.Custom
			cam.CameraSubject = hum or savedSubject
		end
		savedSubject = nil
		savedType = nil
	end

	local function beginFollow(part: BasePart)
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		local character = localPlayer.Character
		if character then
			character:SetAttribute("SwTeleportCam", true)
		end
		if not following then
			savedSubject = cam.CameraSubject
			savedType = cam.CameraType
			following = true
		end
		followPart = part
		-- Keep normal camera behavior; only swap the subject to the travel part.
		cam.CameraType = Enum.CameraType.Custom
		cam.CameraSubject = part
		stopFollowBind()
		RunService:BindToRenderStep(TELEPORT_CAM_BIND, Enum.RenderPriority.Camera.Value + 8, function()
			local ride = followPart
			local liveCam = workspace.CurrentCamera
			if not following or not ride or not ride.Parent or not liveCam then
				restoreCam()
				return
			end
			liveCam.CameraType = Enum.CameraType.Custom
			if liveCam.CameraSubject ~= ride then
				liveCam.CameraSubject = ride
			end
		end)
	end

	Remotes.getEvent("HexDisplacementCam").OnClientEvent:Connect(function(subject: any, _dest: any)
		if subject == nil then
			restoreCam()
			return
		end
		if typeof(subject) ~= "Instance" or not subject:IsA("BasePart") then
			return
		end
		local part = subject :: BasePart
		followToken += 1
		local token = followToken
		task.spawn(function()
			local deadline = os.clock() + 2
			while part.Parent == nil and os.clock() < deadline and token == followToken do
				task.wait()
			end
			if token ~= followToken or not part.Parent then
				return
			end
			beginFollow(part)
		end)
	end)
	localPlayer.CharacterRemoving:Connect(restoreCam)
end

return ScarletWitchClient
