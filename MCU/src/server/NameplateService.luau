--!strict
--[[ Server-replicated head nameplates: player/NPC name, hero name, health bar. ]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local CharacterRegistry = require(ReplicatedStorage.Shared.CharacterRegistry)
local GameConstants = require(ReplicatedStorage.Shared.GameConstants)

local NameplateService = {}

local GUI_NAME = "MCU_Nameplate"
local tracked: { [Model]: {
	gui: BillboardGui,
	titleLabel: TextLabel,
	nameLabel: TextLabel,
	heroLabel: TextLabel,
	healthFill: Frame,
	healthLabel: TextLabel,
	healthConn: RBXScriptConnection?,
	maxHealthConn: RBXScriptConnection?,
	heroConn: RBXScriptConnection?,
	ancestryConn: RBXScriptConnection?,
} } = {}

local function addCorner(parent: GuiObject, radiusScale: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(radiusScale, 0)
	c.Parent = parent
end

local function bracketTitle(text: string): string
	return "[" .. text .. "]"
end

local function resolveDisplayName(model: Model): string
	local player = Players:GetPlayerFromCharacter(model)
	if player then
		return player.DisplayName
	end
	return model.Name
end

local function resolveEliteTitle(model: Model): string?
	local player = Players:GetPlayerFromCharacter(model)
	if player and player:GetAttribute(GameConstants.ELITE_TITLE_ATTRIBUTE) == true then
		return bracketTitle("Elite")
	end
	return nil
end

local function resolveHeroName(model: Model): string?
	local heroId = model:GetAttribute(GameConstants.HERO_ATTRIBUTE)
	if type(heroId) ~= "string" or heroId == "" then
		return nil
	end
	local entry = CharacterRegistry.getById(heroId)
	if entry then
		return entry.displayName
	end
	return heroId
end

local function resolveHeroAccent(model: Model): Color3
	local heroId = model:GetAttribute(GameConstants.HERO_ATTRIBUTE)
	if heroId == "captain_marvel" then
		return Color3.fromRGB(255, 210, 55)
	elseif heroId == "loki" then
		return Color3.fromRGB(55, 200, 110)
	elseif heroId == "dagger" then
		return Color3.fromRGB(255, 255, 255)
	elseif heroId == "jean_grey" then
		local skin = model:GetAttribute(GameConstants.LOOK_MODE_ATTRIBUTE)
		if skin == "marvel_girl" then
			return Color3.fromRGB(255, 90, 185)
		end
		return Color3.fromRGB(65, 81, 253)
	elseif heroId == "iceman" then
		return Color3.fromRGB(129, 184, 255)
	elseif heroId == "invisible_woman" then
		return Color3.fromRGB(77, 71, 255)
	elseif heroId == "scarlet_witch" then
		return Color3.fromRGB(220, 70, 85)
	end
	return Color3.fromRGB(245, 245, 248)
end

local function refreshLabels(model: Model)
	local state = tracked[model]
	if not state or not state.gui.Parent then
		return
	end
	state.nameLabel.Text = resolveDisplayName(model)
	local accent = resolveHeroAccent(model)
	state.nameLabel.TextColor3 = accent
	local eliteTitle = resolveEliteTitle(model)
	if eliteTitle then
		state.titleLabel.Text = eliteTitle
		state.titleLabel.TextColor3 = Color3.fromRGB(255, 215, 80)
		state.titleLabel.Visible = true
	else
		state.titleLabel.Text = ""
		state.titleLabel.Visible = false
	end
	local heroName = resolveHeroName(model)
	if heroName then
		state.heroLabel.Text = heroName
		state.heroLabel.TextColor3 = accent
		state.heroLabel.Visible = true
	else
		state.heroLabel.Text = ""
		state.heroLabel.Visible = false
	end
end

local function refreshHealth(model: Model)
	local state = tracked[model]
	if not state or not state.gui.Parent then
		return
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local maxHp = math.max(humanoid.MaxHealth, 1)
	local hp = math.clamp(humanoid.Health, 0, maxHp)
	local ratio = hp / maxHp
	state.healthFill.Size = UDim2.fromScale(ratio, 1)
	state.healthLabel.Text = string.format("Health: %d/%d", math.floor(hp + 0.5), math.floor(maxHp + 0.5))
end

local function destroyNameplate(model: Model)
	local state = tracked[model]
	if not state then
		return
	end
	if state.healthConn then
		state.healthConn:Disconnect()
	end
	if state.maxHealthConn then
		state.maxHealthConn:Disconnect()
	end
	if state.heroConn then
		state.heroConn:Disconnect()
	end
	if state.ancestryConn then
		state.ancestryConn:Disconnect()
	end
	if state.gui.Parent then
		state.gui:Destroy()
	end
	tracked[model] = nil
end

local function getHead(model: Model): BasePart?
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head
	end
	return nil
end

local function attachNameplate(model: Model)
	if model.Name == "FearClone" or model:GetAttribute("FearVisual") == true then
		return
	end
	if model:GetAttribute(GameConstants.LOKI_INVISIBLE_ATTRIBUTE) == true
		or model:GetAttribute(GameConstants.IW_INVIS_ATTRIBUTE) == true
		or model:GetAttribute(GameConstants.MG_ASTRAL_ATTRIBUTE) == true
		or model:GetAttribute(GameConstants.MG_ASTRAL_BODY_ATTRIBUTE) == true
		or model:GetAttribute(GameConstants.PROB_HEX_OBJECT_ATTRIBUTE) == true
	then
		destroyNameplate(model)
		return
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	local head = getHead(model)
	if not head then
		return
	end

	destroyNameplate(model)

	-- Hide default Roblox nametag / health
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.NameDisplayDistance = 0
	humanoid.HealthDisplayDistance = 0

	-- Parent to character (not Head) so ApplyDescription doesn't wipe it
	local existing = model:FindFirstChild(GUI_NAME)
	if existing then
		existing:Destroy()
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = GUI_NAME
	gui.Adornee = head
	gui.Size = GameConstants.NAMEPLATE_SIZE -- UDim2 scale {5,0},{1,0}
	gui.StudsOffset = GameConstants.NAMEPLATE_OFFSET
	gui.AlwaysOnTop = true
	gui.MaxDistance = GameConstants.NAMEPLATE_MAX_DISTANCE
	gui.LightInfluence = 0
	gui.Enabled = model:GetAttribute(GameConstants.LOKI_INVISIBLE_ATTRIBUTE) ~= true
	gui.Parent = model

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Parent = gui

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0.02, 0)
	layout.Parent = root

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "TitleLabel"
	titleLabel.LayoutOrder = 1
	titleLabel.Size = UDim2.fromScale(1, 0.22)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.Bangers
	titleLabel.TextColor3 = Color3.fromRGB(228, 198, 120)
	titleLabel.TextStrokeTransparency = 0.35
	titleLabel.TextScaled = true
	titleLabel.Visible = false
	titleLabel.Parent = root

	local titleConstraint = Instance.new("UITextSizeConstraint")
	titleConstraint.MaxTextSize = 42
	titleConstraint.MinTextSize = 8
	titleConstraint.Parent = titleLabel

	local heroLabel = Instance.new("TextLabel")
	heroLabel.Name = "HeroLabel"
	heroLabel.LayoutOrder = 2
	heroLabel.Size = UDim2.fromScale(1, 0.24)
	heroLabel.BackgroundTransparency = 1
	heroLabel.Font = Enum.Font.Bangers
	heroLabel.TextColor3 = Color3.fromRGB(220, 120, 130)
	heroLabel.TextStrokeTransparency = 0.4
	heroLabel.TextScaled = true
	heroLabel.Visible = false
	heroLabel.Parent = root

	local heroConstraint = Instance.new("UITextSizeConstraint")
	heroConstraint.MaxTextSize = 48
	heroConstraint.MinTextSize = 8
	heroConstraint.Parent = heroLabel

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.LayoutOrder = 3
	nameLabel.Size = UDim2.fromScale(1, 0.28)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.Bangers
	nameLabel.TextColor3 = Color3.fromRGB(245, 245, 248)
	nameLabel.TextStrokeTransparency = 0.35
	nameLabel.TextScaled = true
	nameLabel.Parent = root

	local nameConstraint = Instance.new("UITextSizeConstraint")
	nameConstraint.MaxTextSize = 64
	nameConstraint.MinTextSize = 10
	nameConstraint.Parent = nameLabel

	local healthRow = Instance.new("Frame")
	healthRow.Name = "HealthRow"
	healthRow.LayoutOrder = 4
	healthRow.Size = UDim2.fromScale(1, 0.3)
	healthRow.BackgroundTransparency = 1
	healthRow.Parent = root

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Size = UDim2.fromScale(1, 1)
	track.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
	track.BorderSizePixel = 0
	track.Parent = healthRow
	addCorner(track, 0.2)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(55, 175, 85)
	fill.BorderSizePixel = 0
	fill.Parent = track
	addCorner(fill, 0.2)

	local healthLabel = Instance.new("TextLabel")
	healthLabel.Name = "HealthLabel"
	healthLabel.Size = UDim2.fromScale(1, 1)
	healthLabel.BackgroundTransparency = 1
	healthLabel.Font = Enum.Font.Bangers
	healthLabel.TextColor3 = Color3.fromRGB(245, 245, 248)
	healthLabel.TextScaled = true
	healthLabel.ZIndex = 2
	healthLabel.Parent = track

	local healthConstraint = Instance.new("UITextSizeConstraint")
	healthConstraint.MaxTextSize = 14
	healthConstraint.MinTextSize = 7
	healthConstraint.Parent = healthLabel

	local healthConn = humanoid.HealthChanged:Connect(function()
		refreshHealth(model)
	end)
	local maxHealthConn = humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
		refreshHealth(model)
	end)

	local heroConn = model:GetAttributeChangedSignal(GameConstants.HERO_ATTRIBUTE):Connect(function()
		refreshLabels(model)
	end)
	model:GetAttributeChangedSignal(GameConstants.LOOK_MODE_ATTRIBUTE):Connect(function()
		refreshLabels(model)
	end)
	local player = Players:GetPlayerFromCharacter(model)
	if player then
		player:GetAttributeChangedSignal(GameConstants.ELITE_TITLE_ATTRIBUTE):Connect(function()
			refreshLabels(model)
		end)
	end
	local invisConn = model:GetAttributeChangedSignal(GameConstants.LOKI_INVISIBLE_ATTRIBUTE):Connect(function()
		local on = model:GetAttribute(GameConstants.LOKI_INVISIBLE_ATTRIBUTE) == true
		if gui.Parent then
			gui.Enabled = not on
		end
	end)

	-- If Head is replaced (ApplyDescription), rebind Adornee
	local ancestryConn = model.ChildAdded:Connect(function(child)
		if child.Name == "Head" and child:IsA("BasePart") and gui.Parent then
			gui.Adornee = child
		end
	end)

	tracked[model] = {
		gui = gui,
		titleLabel = titleLabel,
		nameLabel = nameLabel,
		heroLabel = heroLabel,
		healthFill = fill,
		healthLabel = healthLabel,
		healthConn = healthConn,
		maxHealthConn = maxHealthConn,
		heroConn = heroConn,
		ancestryConn = ancestryConn,
	}

	-- keep invisConn alive with gui
	gui.Destroying:Connect(function()
		invisConn:Disconnect()
	end)

	refreshLabels(model)
	refreshHealth(model)

	model.Destroying:Connect(function()
		destroyNameplate(model)
	end)
	humanoid.Died:Connect(function()
		-- Keep plate in sync at 0 HP (don't leave a stale full bar), then drop it
		refreshHealth(model)
		task.defer(function()
			destroyNameplate(model)
		end)
	end)
end

local function tryAttach(model: Model)
	if not model:IsA("Model") then
		return
	end
	local state = tracked[model]
	if state and state.gui.Parent then
		if model:GetAttribute(GameConstants.MG_ASTRAL_ATTRIBUTE) == true
			or model:GetAttribute(GameConstants.MG_ASTRAL_BODY_ATTRIBUTE) == true
		then
			destroyNameplate(model)
			return
		end
		local head = getHead(model)
		if head then
			state.gui.Adornee = head
		end
		refreshLabels(model)
		refreshHealth(model)
		return
	end
	if state then
		destroyNameplate(model)
	end
	if not model:FindFirstChildOfClass("Humanoid") then
		return
	end
	if model:GetAttribute(GameConstants.MG_ASTRAL_ATTRIBUTE) == true
		or model:GetAttribute(GameConstants.MG_ASTRAL_BODY_ATTRIBUTE) == true
	then
		destroyNameplate(model)
		return
	end

	task.spawn(function()
		if not model.Parent then
			return
		end
		local head = getHead(model)
		if not head then
			local waited = model:WaitForChild("Head", 5)
			if not waited or not waited:IsA("BasePart") then
				return
			end
		end
		if model.Parent and model:FindFirstChildOfClass("Humanoid") then
			attachNameplate(model)
		end
	end)
end

local function fadeBillboard(gui: BillboardGui, hide: boolean, duration: number)
	local fade = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local function fadeInst(inst: Instance)
		if inst:IsA("TextLabel") or inst:IsA("TextButton") then
			TweenService:Create(inst, fade, {
				TextTransparency = if hide then 1 else 0,
				BackgroundTransparency = if hide then 1 else inst.BackgroundTransparency,
			}):Play()
		elseif inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
			TweenService:Create(inst, fade, { ImageTransparency = if hide then 1 else 0 }):Play()
		elseif inst:IsA("Frame") then
			if hide then
				TweenService:Create(inst, fade, { BackgroundTransparency = 1 }):Play()
			end
		end
	end
	fadeInst(gui)
	for _, desc in gui:GetDescendants() do
		fadeInst(desc)
	end
end

function NameplateService.setHidden(model: Model, hidden: boolean, fadeSeconds: number?)
	local dur = fadeSeconds or 0.22
	local state = tracked[model]
	if hidden then
		if state and state.gui.Parent then
			fadeBillboard(state.gui, true, dur)
			task.delay(dur, function()
				if model:GetAttribute(GameConstants.IW_INVIS_ATTRIBUTE) == true
					or model:GetAttribute(GameConstants.MG_ASTRAL_ATTRIBUTE) == true
					or model:GetAttribute(GameConstants.MG_ASTRAL_BODY_ATTRIBUTE) == true
					or model:GetAttribute(GameConstants.PROB_HEX_OBJECT_ATTRIBUTE) == true
				then
					destroyNameplate(model)
				end
			end)
		else
			destroyNameplate(model)
		end
		return
	end
	NameplateService.refresh(model)
end

function NameplateService.refresh(model: Model)
	-- Force rebuild so morph / ApplyDescription can't leave a dead plate
	destroyNameplate(model)
	tryAttach(model)
end

function NameplateService.init()
	local function onCharacter(character: Model)
		-- Delay so morph / ApplyDescription can finish first
		task.delay(0.35, function()
			if character.Parent then
				NameplateService.refresh(character)
			end
		end)
		task.delay(1.0, function()
			if character.Parent then
				NameplateService.refresh(character)
			end
		end)
	end

	for _, player in Players:GetPlayers() do
		player.CharacterAdded:Connect(onCharacter)
		if player.Character then
			onCharacter(player.Character)
		end
	end

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(onCharacter)
	end)

	for _, desc in Workspace:GetDescendants() do
		if desc:IsA("Model") and desc:FindFirstChildOfClass("Humanoid") then
			if not Players:GetPlayerFromCharacter(desc) then
				tryAttach(desc)
			end
		end
	end

	Workspace.DescendantAdded:Connect(function(desc)
		if desc:IsA("Humanoid") then
			local model = desc.Parent
			if model and model:IsA("Model") then
				task.defer(function()
					tryAttach(model)
				end)
			end
		end
	end)

	-- Keep bars honest if HealthChanged is missed during flight lock / morph races
	local RunService = game:GetService("RunService")
	local accum = 0
	RunService.Heartbeat:Connect(function(dt)
		accum += dt
		if accum < 0.2 then
			return
		end
		accum = 0
		for model in tracked do
			if model.Parent then
				refreshHealth(model)
			end
		end
	end)
end

return NameplateService
