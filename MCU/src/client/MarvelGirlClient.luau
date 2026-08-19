--!strict
--[[
	Marvel Girl client:
	- Mind Link chat (top-right, simple)
	- Astral Projection camera + flight input
	- Live cursor aim while Psionic Bolt fires
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AbilityCooldownHelper = require(ReplicatedStorage.Shared.AbilityCooldownHelper)
local GameConstants = require(ReplicatedStorage.Shared.GameConstants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local MouseHelper = require(script.Parent.MouseHelper)
local CameraShakeClient = require(script.Parent.CameraShakeClient)
local ScreenFxClient = require(script.Parent.ScreenFxClient)

local MarvelGirlClient = {}

function MarvelGirlClient.init(localPlayer: Player)
	local mindRemote = Remotes.getEvent("MindLink")
	local useAbility = Remotes.getEvent("UseAbility")
	local flightInput = Remotes.getEvent("FlightInput")
	local controls: any = nil
	pcall(function()
		local playerModule = require(localPlayer:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
		controls = playerModule:GetControls()
	end)

	local playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui

	local overloadGui = Instance.new("ScreenGui")
	overloadGui.Name = "MCU_JeanOverload"
	overloadGui.ResetOnSpawn = false
	overloadGui.IgnoreGuiInset = true
	overloadGui.DisplayOrder = 120
	overloadGui.Enabled = true
	overloadGui.Parent = playerGui

	local function makeLid(name: string, anchorY: number, posY: number): Frame
		local lid = Instance.new("Frame")
		lid.Name = name
		lid.AnchorPoint = Vector2.new(0.5, anchorY)
		lid.Position = UDim2.fromScale(0.5, posY)
		lid.Size = UDim2.fromScale(1, 0)
		lid.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		lid.BorderSizePixel = 0
		lid.ZIndex = 10
		lid.Parent = overloadGui
		return lid
	end

	local topLid = makeLid("TopLid", 0, 0)
	local botLid = makeLid("BottomLid", 1, 1)

	local restText = Instance.new("TextLabel")
	restText.Name = "RestText"
	restText.AnchorPoint = Vector2.new(0.5, 0.5)
	restText.Position = UDim2.fromScale(0.5, 0.5)
	restText.Size = UDim2.fromScale(0.72, 0.12)
	restText.BackgroundTransparency = 1
	restText.Font = Enum.Font.GothamMedium
	restText.Text = "You overused your powers. You need to rest now... zzz"
	restText.TextColor3 = Color3.fromRGB(210, 220, 255)
	restText.TextScaled = true
	restText.TextTransparency = 1
	restText.ZIndex = 12
	restText.Parent = overloadGui

	local restStroke = Instance.new("UIStroke")
	restStroke.Thickness = 1.2
	restStroke.Color = Color3.fromRGB(40, 50, 110)
	restStroke.Transparency = 1
	restStroke.Parent = restText

	local restConstraint = Instance.new("UITextSizeConstraint")
	restConstraint.MaxTextSize = 28
	restConstraint.MinTextSize = 14
	restConstraint.Parent = restText

	local overloadOpen = false
	local function setOverloadVisual(on: boolean)
		if overloadOpen == on then
			return
		end
		overloadOpen = on
		local info = TweenInfo.new(if on then 0.58 else 0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
		local lidSize = if on then UDim2.fromScale(1, 0.5) else UDim2.fromScale(1, 0)
		TweenService:Create(topLid, info, { Size = lidSize }):Play()
		TweenService:Create(botLid, info, { Size = lidSize }):Play()
		TweenService:Create(restText, info, { TextTransparency = if on then 0 else 1 }):Play()
		TweenService:Create(restStroke, info, { Transparency = if on then 0.35 else 1 }):Play()
		CameraShakeClient.setHeldLayer("jeanOverload", on, {
			fade = if on then 0.5 else 0.75,
			shake = if on then 0.22 else 0,
			fov = if on then 3.4 else 0,
			vignette = if on then 0.2 else 1,
			shakeRange = 1.2,
			shakeSlow = 0.5,
		})
	end

	local function hookOverload(character: Model)
		local function sync()
			local hero = character:GetAttribute(GameConstants.HERO_ATTRIBUTE)
			local on = hero == "jean_grey" and character:GetAttribute(GameConstants.MG_OVERLOAD_ATTRIBUTE) == true
			setOverloadVisual(on)
		end
		character:GetAttributeChangedSignal(GameConstants.MG_OVERLOAD_ATTRIBUTE):Connect(sync)
		character:GetAttributeChangedSignal(GameConstants.HERO_ATTRIBUTE):Connect(sync)
		sync()
	end

	if localPlayer.Character then
		hookOverload(localPlayer.Character)
	end
	localPlayer.CharacterAdded:Connect(hookOverload)

	-- Mind Link chat — top right, below settings, simple
	local gui = Instance.new("ScreenGui")
	gui.Name = "MCU_MindLink"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 60
	gui.Enabled = false
	gui.Parent = playerGui

	local panel = Instance.new("Frame")
	panel.Name = "Chat"
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Position = UDim2.new(1, -12, 0, 88)
	panel.Size = UDim2.fromOffset(260, 220)
	panel.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
	panel.BackgroundTransparency = 0.12
	panel.BorderSizePixel = 0
	panel.Parent = gui
	if UserInputService.TouchEnabled then
		panel.Position = UDim2.new(1, -12, 0, 190)
	end

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = panel

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(65, 81, 253)
	stroke.Thickness = 1
	stroke.Transparency = 0.45
	stroke.Parent = panel

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -40, 0, 22)
	title.Position = UDim2.fromOffset(6, 4)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamMedium
	title.TextSize = 14
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.fromRGB(160, 175, 255)
	title.Text = "Mind Link"
	title.Parent = panel

	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "Close"
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.Position = UDim2.new(1, -6, 0, 4)
	closeBtn.Size = UDim2.fromOffset(22, 22)
	closeBtn.BackgroundColor3 = Color3.fromRGB(40, 28, 36)
	closeBtn.BackgroundTransparency = 0.2
	closeBtn.BorderSizePixel = 0
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 16
	closeBtn.TextColor3 = Color3.fromRGB(255, 170, 200)
	closeBtn.Text = "X"
	closeBtn.AutoButtonColor = true
	closeBtn.Visible = false
	closeBtn.Parent = panel

	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 4)
	closeCorner.Parent = closeBtn

	local isMindLinkHost = false
	closeBtn.MouseButton1Click:Connect(function()
		if not isMindLinkHost or not gui.Enabled then
			return
		end
		mindRemote:FireServer({ action = "close" })
	end)

	local membersLabel = Instance.new("TextLabel")
	membersLabel.Name = "Members"
	membersLabel.Size = UDim2.new(1, -12, 0, 16)
	membersLabel.Position = UDim2.fromOffset(6, 24)
	membersLabel.BackgroundTransparency = 1
	membersLabel.Font = Enum.Font.Gotham
	membersLabel.TextSize = 11
	membersLabel.TextXAlignment = Enum.TextXAlignment.Left
	membersLabel.TextColor3 = Color3.fromRGB(180, 180, 190)
	membersLabel.TextTruncate = Enum.TextTruncate.AtEnd
	membersLabel.Text = ""
	membersLabel.Parent = panel

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Messages"
	scroll.Position = UDim2.fromOffset(6, 44)
	scroll.Size = UDim2.new(1, -12, 1, -78)
	scroll.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
	scroll.BackgroundTransparency = 0.2
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = panel

	local scrollCorner = Instance.new("UICorner")
	scrollCorner.CornerRadius = UDim.new(0, 4)
	scrollCorner.Parent = scroll

	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 3)
	list.Parent = scroll

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 4)
	pad.PaddingLeft = UDim.new(0, 4)
	pad.PaddingRight = UDim.new(0, 4)
	pad.Parent = scroll

	local input = Instance.new("TextBox")
	input.Name = "Input"
	input.AnchorPoint = Vector2.new(0, 1)
	input.Position = UDim2.new(0, 6, 1, -6)
	input.Size = UDim2.new(1, -12, 0, 26)
	input.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
	input.BorderSizePixel = 0
	input.ClearTextOnFocus = false
	input.Font = Enum.Font.Gotham
	input.TextSize = 13
	input.TextColor3 = Color3.fromRGB(240, 240, 245)
	input.PlaceholderText = "Message…"
	input.PlaceholderColor3 = Color3.fromRGB(120, 120, 130)
	input.Text = ""
	input.Parent = panel

	local inputCorner = Instance.new("UICorner")
	inputCorner.CornerRadius = UDim.new(0, 4)
	inputCorner.Parent = input

	local msgOrder = 0
	local lastSend = 0
	local astralActive = false
	local astralReturning = false
	local astralModel: Model? = nil
	local savedCameraSubject: Instance? = nil
	local DEFAULT_FOV = 70
	local FLIGHT_FOV_FAST = 80
	local FLIGHT_FOV_LERP = 5.5
	local astralFovBlend = 0
	local astralFovBase = DEFAULT_FOV
	local idleTrack: AnimationTrack? = nil
	local moveTrack: AnimationTrack? = nil
	local currentAnimMode: "none" | "idle" | "move" = "none"
	local astralVel = Vector3.zero
	local wantedAstralName: string? = nil
	local boundAstral: Model? = nil
	local painTimer = Instance.new("TextLabel")
	painTimer.Name = "AstralPainTimer"
	painTimer.AnchorPoint = Vector2.new(0.5, 0)
	painTimer.Position = UDim2.fromScale(0.5, 0.12)
	painTimer.Size = UDim2.fromOffset(220, 34)
	painTimer.BackgroundTransparency = 1
	painTimer.Font = Enum.Font.GothamBold
	painTimer.TextColor3 = Color3.fromRGB(255, 180, 220)
	painTimer.TextSize = 18
	painTimer.Visible = false
	painTimer.Parent = overloadGui

	local function clearAstralAnims()
		if idleTrack then
			idleTrack:Stop(0.12)
			idleTrack:Destroy()
			idleTrack = nil
		end
		if moveTrack then
			moveTrack:Stop(0.12)
			moveTrack:Destroy()
			moveTrack = nil
		end
		currentAnimMode = "none"
		boundAstral = nil
	end

	local function loadAstralTrack(animator: Animator, assetId: string): AnimationTrack?
		local anim = Instance.new("Animation")
		anim.AnimationId = assetId
		local ok, track = pcall(function()
			return animator:LoadAnimation(anim)
		end)
		anim:Destroy()
		if ok and track then
			track.Priority = Enum.AnimationPriority.Action
			track.Looped = true
			return track
		end
		return nil
	end

	local function ensureAstralAnims(model: Model)
		if boundAstral == model then
			return
		end
		clearAstralAnims()
		boundAstral = model
		local hum = model:FindFirstChildOfClass("Humanoid")
		if not hum then
			return
		end
		local animator = hum:FindFirstChildOfClass("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = hum
		end
		idleTrack = loadAstralTrack(animator, GameConstants.JEAN_FLIGHT_IDLE_ANIM)
		moveTrack = loadAstralTrack(animator, GameConstants.JEAN_FLIGHT_MOVE_ANIM)
		if idleTrack then
			idleTrack.Priority = Enum.AnimationPriority.Action
		end
		if moveTrack then
			moveTrack.Priority = Enum.AnimationPriority.Action
		end
	end

	local function setAstralAnim(mode: "idle" | "move")
		if currentAnimMode == mode then
			return
		end
		if mode == "idle" then
			if moveTrack and moveTrack.IsPlaying then
				moveTrack:Stop(0.18)
			end
			if idleTrack and not idleTrack.IsPlaying then
				idleTrack:Play(0.18)
			end
		else
			if idleTrack and idleTrack.IsPlaying then
				idleTrack:Stop(0.2)
			end
			if moveTrack and not moveTrack.IsPlaying then
				moveTrack:Play(0.2)
			end
		end
		currentAnimMode = mode
	end

	local function clearMessages()
		for _, child in scroll:GetChildren() do
			if child:IsA("TextLabel") then
				child:Destroy()
			end
		end
		msgOrder = 0
	end

	local chatNameHex = "#a0afff"

	local function applyAstralNoclip(model: Model, lockHumanoid: boolean?)
		pcall(function()
			if not PhysicsService:IsCollisionGroupRegistered("MarvelGirlAstral") then
				PhysicsService:RegisterCollisionGroup("MarvelGirlAstral")
			end
			PhysicsService:CollisionGroupSetCollidable("MarvelGirlAstral", "Default", false)
		end)
		for _, desc in model:GetDescendants() do
			if desc:IsA("BasePart") then
				desc.CanCollide = false
				desc.CanQuery = false
				desc.CanTouch = false
				desc.Massless = true
				pcall(function()
					desc.CollisionGroup = "MarvelGirlAstral"
				end)
			end
		end
		if lockHumanoid then
			local hum = model:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.HipHeight = 0
				pcall(function()
					(hum :: any).EvaluateStateMachine = false
				end)
			end
		end
	end

	local function addMessage(fromName: string, text: string)
		msgOrder += 1
		local row = Instance.new("TextLabel")
		row.Name = "Msg" .. tostring(msgOrder)
		row.LayoutOrder = msgOrder
		row.Size = UDim2.new(1, -4, 0, 0)
		row.AutomaticSize = Enum.AutomaticSize.Y
		row.BackgroundTransparency = 1
		row.Font = Enum.Font.Gotham
		row.TextSize = 12
		row.TextColor3 = Color3.fromRGB(230, 230, 235)
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextYAlignment = Enum.TextYAlignment.Top
		row.TextWrapped = true
		row.RichText = true
		row.Text = string.format('<font color="%s">%s</font>: %s', chatNameHex, fromName, text)
		row.Parent = scroll
		task.defer(function()
			scroll.CanvasPosition = Vector2.new(0, scroll.AbsoluteCanvasSize.Y)
		end)
	end

	local function applyMindLinkTheme()
		local char = localPlayer.Character
		local skin = if char then char:GetAttribute(GameConstants.LOOK_MODE_ATTRIBUTE) else nil
		local is97 = skin ~= "marvel_girl"
		local accent = if is97 then Color3.fromRGB(65, 81, 253) else Color3.fromRGB(255, 90, 185)
		local titleCol = if is97 then Color3.fromRGB(160, 175, 255) else Color3.fromRGB(255, 170, 220)
		stroke.Color = accent
		title.TextColor3 = titleCol
		chatNameHex = if is97 then "#a0afff" else "#ff9ad0"
	end

	local function showChat(on: boolean, smooth: boolean?)
		if on then
			applyMindLinkTheme()
			gui.Enabled = true
			panel.BackgroundTransparency = 0.12
			closeBtn.Visible = isMindLinkHost
			return
		end
		isMindLinkHost = false
		closeBtn.Visible = false
		if smooth then
			TweenService:Create(panel, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				BackgroundTransparency = 1,
			}):Play()
			task.delay(0.5, function()
				gui.Enabled = false
				clearMessages()
				input.Text = ""
			end)
		else
			gui.Enabled = false
			clearMessages()
			input.Text = ""
		end
	end

	input.FocusLost:Connect(function(enter)
		if not enter or not gui.Enabled then
			return
		end
		local text = string.gsub(input.Text, "^%s+", "")
		text = string.gsub(text, "%s+$", "")
		if text == "" then
			return
		end
		local now = os.clock()
		if now - lastSend < GameConstants.MG_MIND_LINK_MSG_COOLDOWN then
			return
		end
		lastSend = now
		input.Text = ""
		mindRemote:FireServer({ action = "message", text = text })
	end)

	local function countNames(list: any): number
		if type(list) ~= "table" then
			return 0
		end
		return #list
	end

	local function setMindLinkFeel(on: boolean)
		CameraShakeClient.setHeldLayer("mindlink", on, {
			fade = 0.4,
			shake = 0.07,
			fov = 0,
			vignette = 0.78,
		})
	end

	local function setShieldFeel(on: boolean)
		CameraShakeClient.setHeldLayer("shield", on, {
			fade = 0.4,
			shake = 0.06,
			fov = -1.0,
			vignette = 0.5,
			shakeRange = 1.0,
			shakeSlow = 0.38,
		})
	end

	local function hookJeanFeel(character: Model)
		local function refreshShield()
			setShieldFeel(character:GetAttribute(GameConstants.MG_BARRIER_ATTRIBUTE) == true)
		end
		local debrisAttr = AbilityCooldownHelper.getActiveAttributeName("telekinetic_debris")
		local function refreshDebris()
			CameraShakeClient.setHeldLayer("debris", character:GetAttribute(debrisAttr) == true, {
				fade = 0.3,
				shake = 0.05,
				fov = 0,
				vignette = 0.5,
			})
		end
		local function refreshTk()
			CameraShakeClient.setHeldLayer("telekinesis", character:GetAttribute(GameConstants.TK_ACTIVE_ATTRIBUTE) == true, {
				fade = 0.45,
				shake = 0.035,
				fov = 0,
				vignette = 0.88,
				shakeRange = 0.42,
				shakeSlow = 0.18,
			})
		end
		character:GetAttributeChangedSignal(GameConstants.MG_BARRIER_ATTRIBUTE):Connect(refreshShield)
		character:GetAttributeChangedSignal(debrisAttr):Connect(refreshDebris)
		character:GetAttributeChangedSignal(GameConstants.TK_ACTIVE_ATTRIBUTE):Connect(refreshTk)
		local lingerUntil = 0
		local function anyAbilityActive(model: Model): boolean
			for name, value in model:GetAttributes() do
				if type(name) == "string" and string.sub(name, 1, 14) == "AbilityActive_" and value == true then
					if name == "AbilityActive_jean_hair" then
						continue
					end
					return true
				end
			end
			return false
		end
		local function refreshScreen()
			local hero = character:GetAttribute(GameConstants.HERO_ATTRIBUTE)
			local activeNow = hero == "jean_grey"
				and (
					anyAbilityActive(character)
					or character:GetAttribute(GameConstants.TK_ACTIVE_ATTRIBUTE) == true
					or character:GetAttribute(GameConstants.MG_BARRIER_ATTRIBUTE) == true
					or character:GetAttribute(GameConstants.MG_OVERLOAD_ATTRIBUTE) == true
					or character:GetAttribute(GameConstants.MG_WAKING_ATTRIBUTE) == true
					or character:GetAttribute(GameConstants.IS_FLYING_ATTRIBUTE) == true
					or astralActive
				)
			if activeNow then
				lingerUntil = os.clock() + 1.35
				task.delay(1.4, refreshScreen)
			end
			local fxOn = activeNow or os.clock() < lingerUntil
			local look = character:GetAttribute(GameConstants.LOOK_MODE_ATTRIBUTE)
			if look == "phoenix" then
				ScreenFxClient.setEnabled("jean", false)
				ScreenFxClient.setEnabled("phoenix", fxOn)
			else
				ScreenFxClient.setEnabled("phoenix", false)
				if look == "marvel_girl" then
					ScreenFxClient.setTint("jean", GameConstants.MG_PSI_COLOR_MARVEL_GIRL)
				else
					ScreenFxClient.setTint("jean", GameConstants.MG_PSI_COLOR)
				end
				ScreenFxClient.setEnabled("jean", fxOn)
			end
		end
		character.AttributeChanged:Connect(function(attr)
			if string.sub(attr, 1, 14) == "AbilityActive_"
				or attr == GameConstants.HERO_ATTRIBUTE
				or attr == GameConstants.LOOK_MODE_ATTRIBUTE
				or attr == GameConstants.TK_ACTIVE_ATTRIBUTE
				or attr == GameConstants.MG_BARRIER_ATTRIBUTE
				or attr == GameConstants.IS_FLYING_ATTRIBUTE
				or attr == GameConstants.MG_OVERLOAD_ATTRIBUTE
				or attr == GameConstants.MG_WAKING_ATTRIBUTE
			then
				refreshScreen()
			end
		end)
		refreshShield()
		refreshDebris()
		refreshTk()
		refreshScreen()
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Died:Connect(function()
				showChat(false, false)
				setMindLinkFeel(false)
				isMindLinkHost = false
			end)
		end
	end

	localPlayer.CharacterAdded:Connect(hookJeanFeel)
	localPlayer.CharacterRemoving:Connect(function()
		ScreenFxClient.setEnabled("jean", false)
		ScreenFxClient.setEnabled("phoenix", false)
	end)
	if localPlayer.Character then
		hookJeanFeel(localPlayer.Character)
	end

	local function endAstralCamera()
		astralActive = false
		painTimer.Visible = false
		ScreenFxClient.setEnabled("jean", false)
		astralReturning = false
		astralModel = nil
		wantedAstralName = nil
		astralVel = Vector3.zero
		astralFovBlend = 0
		astralFovBase = DEFAULT_FOV
		clearAstralAnims()
		CameraShakeClient.setHeldVignette(false, 0.55)
		local cam = Workspace.CurrentCamera
		if cam then
			TweenService:Create(cam, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				FieldOfView = DEFAULT_FOV,
			}):Play()
		end
		if cam and localPlayer.Character then
			local hum = localPlayer.Character:FindFirstChildOfClass("Humanoid")
			cam.CameraSubject = hum or savedCameraSubject
		elseif cam and savedCameraSubject then
			cam.CameraSubject = savedCameraSubject
		end
		savedCameraSubject = nil
	end

	local function beginAstralCamera(astralName: string?)
		astralActive = true
		local character = localPlayer.Character
		local look = character and character:GetAttribute(GameConstants.LOOK_MODE_ATTRIBUTE)
		ScreenFxClient.setTint(
			"jean",
			if look == "marvel_girl" then GameConstants.MG_PSI_COLOR_MARVEL_GIRL else GameConstants.MG_PSI_COLOR
		)
		ScreenFxClient.setEnabled("jean", true)
		astralReturning = false
		astralVel = Vector3.zero
		wantedAstralName = if type(astralName) == "string" and astralName ~= "" then astralName else "MarvelGirlAstral"
		CameraShakeClient.setHeldVignette(true, 0.5)
		local cam = Workspace.CurrentCamera
		if cam then
			savedCameraSubject = cam.CameraSubject
			TweenService:Create(cam, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				FieldOfView = DEFAULT_FOV,
			}):Play()
		end
		task.spawn(function()
			for _ = 1, 40 do
				if not astralActive then
					return
				end
				local found = Workspace:FindFirstChild(wantedAstralName :: string)
				if not found then
					found = Workspace:FindFirstChild("MarvelGirlAstral")
				end
				if found and found:IsA("Model") then
					astralModel = found
					applyAstralNoclip(found, true)
					ensureAstralAnims(found)
					local hum = found:FindFirstChildOfClass("Humanoid")
					local liveCam = Workspace.CurrentCamera
					if liveCam and hum then
						liveCam.CameraSubject = hum
					end
					return
				end
				task.wait(0.05)
			end
		end)
	end

	mindRemote.OnClientEvent:Connect(function(payload: any)
		if type(payload) ~= "table" then
			return
		end
		local phase = payload.phase
		if phase == "start" then
			isMindLinkHost = payload.isHost == true
			local names = payload.members
			if type(names) == "table" then
				membersLabel.Text = table.concat(names, ", ")
			else
				membersLabel.Text = ""
			end
			clearMessages()
			showChat(true)
			setMindLinkFeel(isMindLinkHost ~= true or countNames(names) > 1)
		elseif phase == "members" then
			if type(payload.members) == "table" then
				membersLabel.Text = table.concat(payload.members, ", ")
			end
			setMindLinkFeel(countNames(payload.members) > 1)
		elseif phase == "message" then
			if type(payload.from) == "string" and type(payload.text) == "string" then
				addMessage(payload.from, payload.text)
			end
		elseif phase == "end" then
			setMindLinkFeel(false)
			showChat(false, false)
		elseif phase == "end_smooth" then
			setMindLinkFeel(false)
			showChat(false, true)
		elseif phase == "astral_start" then
			beginAstralCamera(if type(payload.astralName) == "string" then payload.astralName else nil)
		elseif phase == "astral_returning" then
			astralReturning = true
			CameraShakeClient.setHeldVignette(false, if type(payload.duration) == "number" then payload.duration else GameConstants.MG_ASTRAL_RETURN_TIME)
			local cam = Workspace.CurrentCamera
			if cam then
				TweenService:Create(cam, TweenInfo.new(
					if type(payload.duration) == "number" then payload.duration else GameConstants.MG_ASTRAL_RETURN_TIME,
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.InOut
				), {
					FieldOfView = DEFAULT_FOV + 2,
				}):Play()
			end
		elseif phase == "astral_end" then
			endAstralCamera()
		end
	end)

	-- Hide mind-link particles/beams unless this player is linked
	local function setMindLinkFxVisible(root: Instance, visible: boolean)
		for _, desc in root:GetDescendants() do
			if desc:IsA("ParticleEmitter") or desc:IsA("Beam") or desc:IsA("Trail") then
				desc.Enabled = visible
			elseif desc:IsA("BasePart") and desc:GetAttribute("MgMindLinkFx") == true then
				desc.LocalTransparencyModifier = if visible then 0 else 1
			end
		end
		if root:GetAttribute("MgMindLinkFx") == true then
			if root:IsA("BasePart") then
				root.LocalTransparencyModifier = if visible then 0 else 1
			end
			for _, desc in root:GetDescendants() do
				if desc:IsA("ParticleEmitter") or desc:IsA("Beam") or desc:IsA("Trail") then
					desc.Enabled = visible
				end
			end
		end
	end

	local function refreshMindLinkVisibility()
		local character = localPlayer.Character
		local linked = character ~= nil and character:GetAttribute(GameConstants.MG_MIND_LINK_ATTRIBUTE) == true
		for _, plr in Players:GetPlayers() do
			local model = plr.Character
			if not model then
				continue
			end
			for _, child in model:GetDescendants() do
				if child.Name == "MgMindLinkJean" or child.Name == "MgMindLinkTarget" or child:GetAttribute("MgMindLinkFx") == true then
					setMindLinkFxVisible(child, linked)
				end
			end
		end
		local linker = Workspace:FindFirstChild("MindLinker")
		if linker then
			for _, child in linker:GetDescendants() do
				if child.Name == "MgMindLinkTarget" or child:GetAttribute("MgMindLinkFx") == true then
					setMindLinkFxVisible(child, linked)
				end
			end
		end
	end

	RunService.Heartbeat:Connect(function()
		refreshMindLinkVisibility()
	end)

	-- Live aim while psionic bolt + astral flight
	local lastAim = 0
	RunService.RenderStepped:Connect(function(dt)
		if not astralActive then
			return
		end
		local cam = Workspace.CurrentCamera
		if not cam then
			return
		end

		-- Keep camera on astral (including during smooth return)
		if astralModel and astralModel.Parent then
			local hum = astralModel:FindFirstChildOfClass("Humanoid")
			if hum and cam.CameraSubject ~= hum then
				cam.CameraSubject = hum
			end
		end

		if astralReturning then
			return
		end

		local body = localPlayer.Character
		local outbursting = body ~= nil
			and AbilityCooldownHelper.isActive(body, "telepathic_outburst")
		local painActive = body ~= nil
			and AbilityCooldownHelper.isActive(body, "telepathic_pain")

		local look = cam.CFrame.LookVector
		local right = cam.CFrame.RightVector
		local w = if UserInputService:IsKeyDown(Enum.KeyCode.W) then 1 else 0
		local s = if UserInputService:IsKeyDown(Enum.KeyCode.S) then 1 else 0
		local a = if UserInputService:IsKeyDown(Enum.KeyCode.A) then 1 else 0
		local d = if UserInputService:IsKeyDown(Enum.KeyCode.D) then 1 else 0
		local sideInput = d - a
		local moveDir = look * (w - s) + right * sideInput
		if controls and UserInputService.TouchEnabled and moveDir.Magnitude < 0.01 then
			local inputMove = controls:GetMoveVector()
			moveDir = right * inputMove.X + look * -inputMove.Z
			sideInput = math.clamp(inputMove.X, -1, 1)
		end
		if outbursting or painActive then
			moveDir = Vector3.zero
			sideInput = 0
			astralVel = Vector3.zero
		elseif moveDir.Magnitude > 1 then
			moveDir = moveDir.Unit
		end

		if astralModel and astralModel.Parent and not astralReturning then
			applyAstralNoclip(astralModel)
			local root = astralModel:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				local lin = root:FindFirstChild("HeroLinearVelocity")
				local align = root:FindFirstChild("HeroAlignOrientation")
				local grav = root:FindFirstChild("HeroGravityCancel")
				if outbursting or painActive then
					if lin and lin:IsA("LinearVelocity") then
						lin.VectorVelocity = Vector3.zero
					else
						root.AssemblyLinearVelocity = Vector3.zero
					end
					root.AssemblyAngularVelocity = Vector3.zero
					if grav and grav:IsA("VectorForce") then
						grav.Force = Vector3.new(0, root.AssemblyMass * Workspace.Gravity, 0)
					end
					if painActive and align and align:IsA("AlignOrientation") then
						local lookAt = body and body:GetAttribute(GameConstants.MG_PAIN_LOOK_ATTRIBUTE)
						if typeof(lookAt) ~= "Vector3" then
							lookAt = astralModel:GetAttribute(GameConstants.MG_PAIN_LOOK_ATTRIBUTE)
						end
						if typeof(lookAt) == "Vector3" then
							local to = lookAt - root.Position
							if to.Magnitude > 0.08 then
								align.CFrame = CFrame.lookAt(root.Position, root.Position + to.Unit)
							end
						end
					end
				else
				local speed = GameConstants.FLIGHT_SPEED
				local moveMag = moveDir.Magnitude
				local direction = if moveMag > 0.01 then moveDir.Unit else (if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1))
				local targetVel = if moveMag > 0.01 then direction * speed else Vector3.zero
				local velLerpMove = 1 - (1 - GameConstants.FLIGHT_VEL_LERP_MOVE) ^ (dt * 60)
				local velLerpDecay = 1 - (1 - GameConstants.FLIGHT_VEL_LERP_DECAY) ^ (dt * 60)
				local lerpAlpha = if moveMag > 0.01 then velLerpMove else velLerpDecay
				astralVel = astralVel:Lerp(targetVel, lerpAlpha)
				if lin and lin:IsA("LinearVelocity") then
					lin.VectorVelocity = astralVel
				else
					root.AssemblyLinearVelocity = astralVel
				end
				if grav and grav:IsA("VectorForce") then
					grav.Force = Vector3.new(0, root.AssemblyMass * Workspace.Gravity, 0)
				end
				if align and align:IsA("AlignOrientation") then
					local velMag = astralVel.Magnitude
					local alphaSpeed = if speed > 0 then velMag / speed else 0
					local facingDir = if moveMag > 0.01 then direction else look
					if facingDir.Magnitude < 0.01 then
						facingDir = Vector3.new(0, 0, -1)
					else
						facingDir = facingDir.Unit
					end
					local pitchAlpha = if moveMag > 0.01 then math.min(1, alphaSpeed) * 1.15 else 0
					local sideYaw = math.clamp(sideInput, -1, 1) * GameConstants.FLIGHT_SIDE_YAW * math.clamp(alphaSpeed, 0, 1)
					local bank = math.clamp(sideInput, -1, 1) * GameConstants.FLIGHT_BANK_MAX * math.clamp(alphaSpeed, 0, 1)
					local baseCf = CFrame.lookAt(root.Position, root.Position + facingDir)
					local targetCf = baseCf * CFrame.Angles(
						math.rad(-pitchAlpha * GameConstants.MG_FLIGHT_PITCH_MAX),
						math.rad(sideYaw),
						math.rad(-bank)
					)
					local rotAlpha = 1 - (1 - GameConstants.FLIGHT_ROTATION_LERP) ^ (dt * 60)
					align.CFrame = align.CFrame:Lerp(targetCf, rotAlpha)
				end
				end
			end
		end

		flightInput:FireServer({
			moveVector = moveDir,
			lookVector = look,
			moveDir = moveDir,
			lookDir = look,
			sideInput = sideInput,
		})
		mindRemote:FireServer({
			action = "astral_input",
			moveDir = moveDir,
			lookDir = look,
			sideInput = sideInput,
		})

		if astralModel and astralModel.Parent then
			ensureAstralAnims(astralModel)
			local moving = moveDir.Magnitude > GameConstants.FLIGHT_ANIM_MOVE_THRESHOLD
			setAstralAnim(if moving then "move" else "idle")

			local spd = astralVel.Magnitude
			local speedT = math.clamp(spd / math.max(GameConstants.MG_ASTRAL_FLIGHT_SPEED, 1), 0, 1)
			local blendRate = if speedT < astralFovBlend then 3.1 else 4.6
			astralFovBlend += (speedT - astralFovBlend) * math.clamp(dt * blendRate, 0, 1)
			local targetFov = DEFAULT_FOV + (FLIGHT_FOV_FAST - DEFAULT_FOV) * astralFovBlend
			if not CameraShakeClient.isAbilityZoomEnabled() then
				targetFov = DEFAULT_FOV
			end
			astralFovBase += (targetFov - astralFovBase) * math.clamp(dt * FLIGHT_FOV_LERP, 0, 1)
			cam.FieldOfView = astralFovBase + CameraShakeClient.getFovPunch()
		end
	end)

	RunService.Heartbeat:Connect(function()
		local character = localPlayer.Character
		if not character then
			return
		end
		if AbilityCooldownHelper.isActive(character, "psionic_bolt") then
			local now = os.clock()
			if now - lastAim >= 0.03 then
				lastAim = now
				useAbility:FireServer({
					action = "E_aim",
					direction = MouseHelper.getWorldDirection(localPlayer),
					aimPoint = MouseHelper.getHitPosition(localPlayer, 200),
				})
			end
		end
	end)

	-- Press V again to end astral (also handled via UseAbility → server toggle)
	UserInputService.InputBegan:Connect(function(input, gp)
		if gp or not astralActive or astralReturning then
			return
		end
		if input.KeyCode == Enum.KeyCode.H or input.KeyCode == Enum.KeyCode.V then
			mindRemote:FireServer({ action = "astral_end" })
		end
	end)

	localPlayer.CharacterRemoving:Connect(function()
		endAstralCamera()
		showChat(false, false)
		setOverloadVisual(false)
	end)
end

return MarvelGirlClient
