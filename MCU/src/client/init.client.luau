--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local function disableNoisyLegacyScripts(root: Instance)
	for _, inst in root:GetDescendants() do
		if (inst:IsA("Script") or inst:IsA("LocalScript")) and inst.Name == "Game sounds" then
			inst.Disabled = true
		end
	end
end

disableNoisyLegacyScripts(game)
game.DescendantAdded:Connect(function(inst)
	if (inst:IsA("Script") or inst:IsA("LocalScript")) and inst.Name == "Game sounds" then
		inst.Disabled = true
	end
end)

require(ReplicatedStorage.Shared.SmartBonePatch).install()

local AbilityInput = require(script.AbilityInput)
local CharacterSelectUI = require(script.CharacterSelectUI)
local DeathScreenClient = require(script.DeathScreenClient)
local HexFlightClient = require(script.HexFlightClient)
local PartialShieldClient = require(script.PartialShieldClient)
local RagdollController = require(script.RagdollController)
local AnimationPreload = require(ReplicatedStorage.Shared.AnimationPreload)
local CombatHelper = require(ReplicatedStorage.Shared.CombatHelper)
local GameConstants = require(ReplicatedStorage.Shared.GameConstants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
require(ReplicatedStorage.Shared.VfxHelper)

task.spawn(function()
	AnimationPreload.preload()
end)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

require(script.PlayerDataClient).init(player)

-- Loading overlay: a solid background that stays up until the camera has actually rendered,
-- then fades away smoothly once the world/menu is ready.
do
	local function createLoadingOverlay(gui: PlayerGui): (ScreenGui, Frame)
		local screenGui = Instance.new("ScreenGui")
		screenGui.Name = "McuLoadOverlay"
		screenGui.ResetOnSpawn = false
		screenGui.IgnoreGuiInset = true
		screenGui.DisplayOrder = 5000
		screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		screenGui.Parent = gui

		local frame = Instance.new("Frame")
		frame.Name = "Backdrop"
		frame.Size = UDim2.fromScale(1, 1)
		frame.BackgroundColor3 = Color3.fromRGB(24, 20, 30)
		frame.BorderSizePixel = 0
		frame.Parent = screenGui

		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.AnchorPoint = Vector2.new(0.5, 0.5)
		title.Position = UDim2.fromScale(0.5, 0.44)
		title.Size = UDim2.fromScale(0.82, 0.2)
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.GothamBlack
		title.Text = "ASSEMBLING THE MULTIVERSE"
		title.TextColor3 = Color3.fromRGB(255, 244, 250)
		title.TextScaled = true
		title.TextWrapped = true
		title.Parent = screenGui

		local sub = Instance.new("TextLabel")
		sub.Name = "Sub"
		sub.AnchorPoint = Vector2.new(0.5, 0.5)
		sub.Position = UDim2.fromScale(0.5, 0.61)
		sub.Size = UDim2.fromScale(0.7, 0.1)
		sub.BackgroundTransparency = 1
		sub.Font = Enum.Font.Gotham
		sub.Text = "Loading assets"
		sub.TextColor3 = Color3.fromRGB(214, 202, 220)
		sub.TextScaled = true
		sub.Parent = screenGui

		return screenGui, frame
	end

	task.spawn(function()
		local overlay, frame = createLoadingOverlay(playerGui)
		local spawnedAt = os.clock()

		local ok, camInst = pcall(function()
			return Workspace:WaitForChild("Camera", 30)
		end)
		if not ok or not camInst or not camInst:IsA("Camera") then
			if overlay.Parent then
				overlay:Destroy()
			end
			return
		end

		-- "Camera loaded" = the camera has actually produced a few rendered frames.
		local rendered = 0
		local conn: RBXScriptConnection? = nil
		conn = RunService.RenderStepped:Connect(function()
			rendered += 1
		end)
		local frameDeadline = os.clock() + 10
		while rendered < 3 and os.clock() < frameDeadline do
			task.wait()
		end
		if conn then
			conn:Disconnect()
			conn = nil
		end

		-- Hold at least ~1.2s so it reads as a load, and give the menu/world a beat to set up.
		local minHold = 1.2
		local elapsed = os.clock() - spawnedAt
		if elapsed < minHold then
			task.wait(minHold - elapsed)
		end
		task.wait(0.4)

		if not frame.Parent then
			if overlay.Parent then
				overlay:Destroy()
			end
			return
		end

		-- Smoothly remove the background color.
		local tween = TweenService:Create(frame, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 1,
		})
		tween:Play()
		task.wait(0.6)
		if overlay.Parent then
			overlay:Destroy()
		end
	end)
end

local awaitingDeploy = false
local deathFlowStarted = false
local deathFlowDone = false
-- After death we jump straight to character select (never the main menu) when the blank respawn arrives.
local pendingRespawnSelection = false

local selection = CharacterSelectUI.create(playerGui, function(heroId: string, skinId: string)
	awaitingDeploy = true
	pendingRespawnSelection = false
	Remotes.getEvent("SelectHero"):FireServer(heroId, skinId)
end)

local hudOk, hudOrErr = pcall(function()
	return require(script.GameplayHUD).create(playerGui)
end)
if not hudOk then
	warn("[MCU Client] GameplayHUD failed:", hudOrErr)
	local existing = playerGui:FindFirstChild("GameplayHUD")
	if existing and existing:IsA("ScreenGui") then
		existing.ResetOnSpawn = false
		existing.Enabled = true
	end
end
local hud = if hudOk then hudOrErr else nil

local function safeHudShow(heroId: string, character: Model)
	if not hud then
		return
	end
	hud.show(heroId)
	hud.bindCharacter(character)
end

local function safeHudHide()
	if hud then
		hud.hide()
	end
end

require(script.TeleportMarkerClient).init(player)
AbilityInput.init(player)
require(script.SoftLockClient).init(player)
require(script.ShoulderCamClient).init(player)
require(script.AbilityCameraGuard).init(player)
HexFlightClient.init(player)
PartialShieldClient.init(player)
RagdollController.init(player)
require(script.SprintClient).init(player)
require(script.RunAnimClient).init(player)
require(script.CombatHud).init(player)
require(script.LokiInvisClient).init(player)
require(script.LokiDecoyMarkerClient).init(player)
require(script.BlindFlashClient).init(player)
require(script.MarvelGirlClient).init(player)
require(script.InvisibleWomanClient).init(player)
require(script.ScarletWitchClient).init(player)
require(script.CameraShakeClient).init(player)
do
	local ok, err = pcall(function()
		require(script.BeamClashClient).init(player)
	end)
	if not ok then
		warn("[MCU Client] BeamClashClient failed:", err)
	end
end

local function isDeployedHero(character: Model): boolean
	local heroId = character:GetAttribute(GameConstants.HERO_ATTRIBUTE)
	return type(heroId) == "string" and heroId ~= ""
end

local function isPhoenixJean(character: Model): boolean
	return character:GetAttribute(GameConstants.HERO_ATTRIBUTE) == "jean_grey"
		and character:GetAttribute(GameConstants.LOOK_MODE_ATTRIBUTE) == "phoenix"
end

local function beginDeathFlow(character: Model)
	if deathFlowStarted or deathFlowDone or DeathScreenClient.isActive() then
		return
	end
	if not isDeployedHero(character) then
		return
	end
	deathFlowStarted = true
	deathFlowDone = true
	awaitingDeploy = false
	safeHudHide()
	AbilityInput.setInputBlocked(true)

	local phoenix = isPhoenixJean(character)
	DeathScreenClient.play(character, function()
		deathFlowStarted = false
		AbilityInput.setInputBlocked(false)
		pendingRespawnSelection = true
		selection.showSelection()
	end, {
		isPhoenix = phoenix,
		onRevive = if phoenix
			then function()
				Remotes.getEvent("PhoenixRevive"):FireServer()
			end
			else nil,
	})
end

local function bindHeroCharacter(character: Model)
	local heroId = character:GetAttribute(GameConstants.HERO_ATTRIBUTE)
	if type(heroId) ~= "string" or heroId == "" then
		return false
	end
	if not character.Parent then
		return false
	end

	deathFlowStarted = false
	deathFlowDone = false
	DeathScreenClient.cancel()
	selection.hide()
	selection.endDeployWhiteout()
	safeHudShow(heroId, character)
	awaitingDeploy = false
	AbilityInput.setInputBlocked(false)
	return true
end

local function hookDeath(character: Model)
	CombatHelper.bindSilenceDeathSounds(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		local waited = character:WaitForChild("Humanoid", 5)
		if waited and waited:IsA("Humanoid") then
			humanoid = waited
		end
	end
	if not humanoid then
		return
	end
	humanoid.Died:Connect(function()
		CombatHelper.silenceDeathSounds(character)
		beginDeathFlow(character)
	end)
end

local function onCharacterSpawned(character: Model)
	task.spawn(hookDeath, character)

	if DeathScreenClient.isActive() or deathFlowStarted then
		return
	end

	safeHudHide()

	if bindHeroCharacter(character) then
		return
	end

	if not awaitingDeploy then
		if pendingRespawnSelection then
			pendingRespawnSelection = false
			selection.showSelection()
		else
			selection.show(true)
		end
	end

	local attrConn: RBXScriptConnection? = nil
	local destroyConn: RBXScriptConnection? = nil

	local function disconnectAll()
		if attrConn then
			attrConn:Disconnect()
			attrConn = nil
		end
		if destroyConn then
			destroyConn:Disconnect()
			destroyConn = nil
		end
	end

	attrConn = character:GetAttributeChangedSignal(GameConstants.HERO_ATTRIBUTE):Connect(function()
		if bindHeroCharacter(character) then
			disconnectAll()
		end
	end)

	destroyConn = character.Destroying:Connect(disconnectAll)
end

player.CharacterRemoving:Connect(function(character)
	if deathFlowStarted or DeathScreenClient.isActive() then
		DeathScreenClient.notifyBodyGone()
		return
	end
	if deathFlowDone then
		return
	end
	if not isDeployedHero(character) then
		return
	end
	local hum = character:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 and hum:GetState() ~= Enum.HumanoidStateType.Dead then
		return
	end
	beginDeathFlow(character)
	DeathScreenClient.notifyBodyGone()
end)

player.CharacterAdded:Connect(function(character)
	if not DeathScreenClient.isActive() then
		AbilityInput.setInputBlocked(false)
	end
	onCharacterSpawned(character)
end)

task.spawn(function()
	local resetBind = Instance.new("BindableEvent")
	resetBind.Event:Connect(function()
		if DeathScreenClient.isActive() or deathFlowStarted then
			DeathScreenClient.notifyBodyGone()
			return
		end
		local character = player.Character
		if not character or not isDeployedHero(character) then
			return
		end
		local hum = character:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			hum.Health = 0
		end
	end)
	for _ = 1, 30 do
		local ok = pcall(function()
			StarterGui:SetCore("ResetButtonCallback", resetBind)
		end)
		if ok then
			break
		end
		task.wait(0.4)
	end
end)

if player.Character then
	onCharacterSpawned(player.Character)
else
	selection.show()
end

Remotes.getEvent("PhoenixRevive").OnClientEvent:Connect(function(success: any)
	if success == true then
		deathFlowStarted = false
		deathFlowDone = false
		DeathScreenClient.cancel()
		AbilityInput.setInputBlocked(false)
		selection.hide()
		local character = player.Character
		if character and isDeployedHero(character) then
			local heroId = character:GetAttribute(GameConstants.HERO_ATTRIBUTE)
			if type(heroId) == "string" then
				safeHudShow(heroId, character)
			end
		end
	end
end)
