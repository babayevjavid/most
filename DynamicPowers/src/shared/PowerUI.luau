-- ScreenGui and BillboardGui children use scale only (UDim2.fromScale, UDim.new(scale, 0)).
-- Loaded from ReplicatedStorage so PlayerScripts layout (Rojo vs manual) does not break requires.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Powers = require(script.Parent.Powers)

local player = Players.LocalPlayer

local Z_POWER_SELECT = 1
local Z_HEALTH_SCREEN = 2

-- Shared health UI (screen + overhead): green theme, scale-only layout elsewhere.
local HEALTH_GREEN = Color3.fromRGB(72, 214, 118)
local HEALTH_GREEN_DIM = Color3.fromRGB(48, 160, 95)
local HEALTH_PANEL_BG = Color3.fromRGB(16, 28, 22)
local HEALTH_TEXT = Color3.fromRGB(220, 255, 230)

-- One simple style for all power picker buttons (scale-only layout).
local POWER_BTN_BG = Color3.fromRGB(230, 230, 235)
local POWER_BTN_TEXT = Color3.fromRGB(30, 30, 36)

local function createPowerSelectionGui(
	powerSelectedRemote: RemoteEvent,
	onChosen: (string, ScreenGui) -> ()
): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "PowerSelection"
	gui.Enabled = true
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = Z_POWER_SELECT + 50

	local container = Instance.new("Frame")
	container.Name = "BottomLeft"
	container.BackgroundTransparency = 1
	container.AnchorPoint = Vector2.new(0, 1)
	container.Position = UDim2.fromScale(0.01, 1)
	container.Size = UDim2.fromScale(0.19, 0.34)
	container.Parent = gui

	local pad = Instance.new("UIPadding")
	pad.PaddingBottom = UDim.new(0.02, 0)
	pad.PaddingLeft = UDim.new(0.01, 0)
	pad.Parent = container

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Top
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0.012, 0)
	list.Parent = container

	for i, powerName in Powers.List do
		local btn = Instance.new("TextButton")
		btn.Name = powerName
		btn.AutoButtonColor = true
		btn.BackgroundColor3 = POWER_BTN_BG
		btn.TextColor3 = POWER_BTN_TEXT
		btn.Font = Enum.Font.GothamBold
		btn.TextScaled = true
		btn.Text = powerName
		btn.Size = UDim2.fromScale(1, 0.17)
		btn.LayoutOrder = i

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.08, 0)
		corner.Parent = btn

		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0.05, 0)
		pad.PaddingBottom = UDim.new(0.05, 0)
		pad.PaddingLeft = UDim.new(0.04, 0)
		pad.PaddingRight = UDim.new(0.04, 0)
		pad.Parent = btn

		btn.MouseButton1Click:Connect(function()
			onChosen(powerName, gui)
		end)

		btn.Parent = container
	end

	return gui
end

local function createScreenHealthGui(humanoid: Humanoid): (ScreenGui, () -> ())
	local gui = Instance.new("ScreenGui")
	gui.Name = "HealthScreen"
	gui.Enabled = true
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = Z_HEALTH_SCREEN + 50

	local root = Instance.new("Frame")
	root.Name = "TopLeft"
	root.BackgroundColor3 = HEALTH_PANEL_BG
	root.AnchorPoint = Vector2.new(0, 0)
	root.Position = UDim2.fromScale(0.01, 0.01)
	root.Size = UDim2.fromScale(0.22, 0.042)
	root.Parent = gui

	local rootCorner = Instance.new("UICorner")
	rootCorner.CornerRadius = UDim.new(0.2, 0)
	rootCorner.Parent = root

	local border = Instance.new("UIStroke")
	border.Thickness = 1
	border.Color = HEALTH_GREEN_DIM
	border.Transparency = 0.25
	border.Parent = root

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = HEALTH_GREEN
	fill.BorderSizePixel = 0
	fill.AnchorPoint = Vector2.new(0, 0.5)
	fill.Position = UDim2.fromScale(0, 0.5)
	fill.Size = UDim2.fromScale(1, 1)
	fill.Parent = root

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0.2, 0)
	fillCorner.Parent = fill

	local label = Instance.new("TextLabel")
	label.Name = "Value"
	label.BackgroundTransparency = 1
	label.TextColor3 = HEALTH_TEXT
	label.Font = Enum.Font.GothamMedium
	label.TextScaled = true
	label.Text = ""
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = 2
	label.Parent = root

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.04, 0)
	pad.PaddingRight = UDim.new(0.04, 0)
	pad.Parent = label

	local fillTween: Tween? = nil
	local firstFill = true

	local function update()
		local maxH = humanoid.MaxHealth
		local h = humanoid.Health
		if maxH <= 0 then
			return
		end
		local ratio = math.clamp(h / maxH, 0, 1)
		local targetSize = UDim2.fromScale(ratio, 1)
		if fillTween then
			fillTween:Cancel()
			fillTween = nil
		end
		if firstFill then
			fill.Size = targetSize
			firstFill = false
		else
			fillTween = TweenService:Create(
				fill,
				TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Size = targetSize }
			)
			fillTween:Play()
		end
		label.Text = string.format(
			"Health: %d / %d",
			math.floor(h + 0.5),
			math.floor(maxH + 0.5)
		)
	end

	update()
	local conn1 = humanoid:GetPropertyChangedSignal("Health"):Connect(update)
	local conn2 = humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(update)

	local function cleanup()
		conn1:Disconnect()
		conn2:Disconnect()
		if fillTween then
			fillTween:Cancel()
		end
		if gui.Parent then
			gui:Destroy()
		end
	end

	return gui, cleanup
end

local M = {}

function M.start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
	if not remotes then
		warn("[PowerUI] ReplicatedStorage.Remotes not found (Rojo synced?). UI disabled.")
		return
	end
	local powerEv = remotes:WaitForChild("PowerSelected", 15)
	if not powerEv or not powerEv:IsA("RemoteEvent") then
		warn("[PowerUI] PowerSelected RemoteEvent missing. UI disabled.")
		return
	end
	local powerSelectedRemote = powerEv :: RemoteEvent

	local playerGui = player:WaitForChild("PlayerGui")

	local screenHealthCleanup: (() -> ())? = nil
	local gameplayStarted = false
	local characterConn: RBXScriptConnection? = nil

	local function cleanupOverhead()
		if screenHealthCleanup then
			screenHealthCleanup()
			screenHealthCleanup = nil
		end
	end

	local function hookCharacter(character: Model)
		cleanupOverhead()

		local hum = character:WaitForChild("Humanoid", 10) :: Humanoid?
		if not hum then
			return
		end

		local healthGui, cleanup = createScreenHealthGui(hum)
		healthGui.Parent = playerGui
		screenHealthCleanup = cleanup
	end

	local selectionGui: ScreenGui

	local function returnToPowerPicker()
		cleanupOverhead()
		if characterConn then
			characterConn:Disconnect()
			characterConn = nil
		end
		gameplayStarted = false
		selectionGui.Enabled = true
	end

	local function startGameplay(powerName: string)
		if gameplayStarted then
			return
		end
		gameplayStarted = true

		if player.Character then
			hookCharacter(player.Character)
		end

		if characterConn then
			characterConn:Disconnect()
		end
		characterConn = player.CharacterAdded:Connect(function(char)
			hookCharacter(char)
		end)
	end

	selectionGui = createPowerSelectionGui(powerSelectedRemote, function(powerName: string, pickGui: ScreenGui)
		if not pickGui.Enabled then
			return
		end
		powerSelectedRemote:FireServer(powerName)
		pickGui.Enabled = false
		startGameplay(powerName)
	end)

	selectionGui.Parent = playerGui
	task.defer(function()
		if not selectionGui.Parent then
			return
		end
		local bottom = selectionGui:FindFirstChild("BottomLeft") :: Frame?
		if bottom then
			bottom.Size = UDim2.fromScale(0.19, 0.34)
		end
	end)

	local function onSelectedPowerChanged()
		local v = player:GetAttribute("SelectedPower")
		if v == nil then
			returnToPowerPicker()
			return
		end
		if typeof(v) ~= "string" or not Powers.isValid(v) then
			returnToPowerPicker()
			return
		end
		if selectionGui.Enabled then
			selectionGui.Enabled = false
			if not gameplayStarted then
				startGameplay(v)
			end
		end
	end

	player:GetAttributeChangedSignal("SelectedPower"):Connect(function()
		task.defer(onSelectedPowerChanged)
	end)

	local existing = player:GetAttribute("SelectedPower")
	if typeof(existing) == "string" and Powers.isValid(existing) then
		selectionGui.Enabled = false
		startGameplay(existing)
	end
end

return M
