--!strict
--[[ Local Polaris ability visuals: FOV pulses and color flashes. ]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local ClientSettings = require(script.Parent:WaitForChild("ClientSettings"))
local PolarisConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PolarisConstants"))

local GREEN = PolarisConstants.POLARIS_GREEN
local GREEN_BRIGHT = PolarisConstants.POLARIS_GREEN_BRIGHT

local PolarisAbilityVfx = {}

local player: Player
local screenGui: ScreenGui?
local overlay: Frame?
local attributeConns: { RBXScriptConnection } = {}
local baseFov = 70
local activeFovTween: Tween? = nil
local activeOverlayTween: Tween? = nil

local function isPolaris(): boolean
	return player:GetAttribute("SelectedCharacter") == "Polaris"
end

local function ensureOverlay()
	if screenGui and overlay then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "PolarisAbilityVfx"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 240
	gui.Parent = player:WaitForChild("PlayerGui")

	local frame = Instance.new("Frame")
	frame.Name = "TintOverlay"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = GREEN
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Parent = gui

	screenGui = gui
	overlay = frame
end

local function effectsEnabled(): boolean
	return ClientSettings.isAbilityScreenEffectsEnabled()
end

local function tweenFov(targetFov: number, duration: number, reverse: boolean?)
	if not effectsEnabled() then
		return
	end
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	if activeFovTween then
		activeFovTween:Cancel()
		activeFovTween = nil
	end
	local tween = TweenService:Create(
		cam,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ FieldOfView = targetFov }
	)
	activeFovTween = tween
	tween:Play()
	if reverse then
		tween.Completed:Once(function()
			local back = TweenService:Create(
				cam,
				TweenInfo.new(duration * 1.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ FieldOfView = baseFov }
			)
			activeFovTween = back
			back:Play()
		end)
	end
end

local function flashOverlay(color: Color3, peakTransparency: number, duration: number)
	if not effectsEnabled() then
		return
	end
	ensureOverlay()
	if not overlay then
		return
	end
	if activeOverlayTween then
		activeOverlayTween:Cancel()
		activeOverlayTween = nil
	end
	overlay.BackgroundColor3 = color
	overlay.BackgroundTransparency = peakTransparency
	local fade = TweenService:Create(
		overlay,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1 }
	)
	activeOverlayTween = fade
	fade:Play()
end

function PolarisAbilityVfx.onFlightToggle(enabled: boolean)
	if not isPolaris() then
		return
	end
	if enabled then
		tweenFov(baseFov + 2, 0.2, true)
		flashOverlay(GREEN_BRIGHT, 0.96, 0.22)
	else
		tweenFov(baseFov, 0.25, false)
		flashOverlay(GREEN, 0.97, 0.18)
	end
end

function PolarisAbilityVfx.onHandCast()
	if not isPolaris() then
		return
	end
	tweenFov(baseFov + 1.5, 0.1, true)
	flashOverlay(GREEN, 0.96, 0.18)
end

function PolarisAbilityVfx.onFerrokinesisStart()
	if not isPolaris() then
		return
	end
	tweenFov(baseFov + 1.5, 0.14, true)
	flashOverlay(GREEN_BRIGHT, 0.97, 0.2)
end

function PolarisAbilityVfx.onFerrokinesisThrow()
	if not isPolaris() then
		return
	end
	tweenFov(baseFov + 2.5, 0.08, true)
	flashOverlay(GREEN_BRIGHT, 0.95, 0.16)
end

function PolarisAbilityVfx.onLanceHit()
	tweenFov(baseFov + 3, 0.07, true)
	flashOverlay(Color3.fromRGB(210, 90, 100), 0.94, 0.28)
end

local function clearAttributeConns()
	for _, conn in attributeConns do
		conn:Disconnect()
	end
	table.clear(attributeConns)
end

local function bindCharacter(character: Model)
	clearAttributeConns()
	local cam = workspace.CurrentCamera
	if cam then
		baseFov = cam.FieldOfView
	end

	table.insert(attributeConns, character:GetAttributeChangedSignal("MetalLanceHitPulse"):Connect(function()
		if typeof(character:GetAttribute("MetalLanceHitPulse")) == "number" then
			PolarisAbilityVfx.onLanceHit()
		end
	end))

	table.insert(attributeConns, character:GetAttributeChangedSignal("IsFerrokinesisActive"):Connect(function()
		if character:GetAttribute("IsFerrokinesisActive") == true and isPolaris() then
			PolarisAbilityVfx.onFerrokinesisStart()
		end
	end))

	table.insert(attributeConns, character:GetAttributeChangedSignal("IsMagneticFlying"):Connect(function()
		local flying = character:GetAttribute("IsMagneticFlying") == true
		if isPolaris() then
			PolarisAbilityVfx.onFlightToggle(flying)
		end
	end))
end

function PolarisAbilityVfx.start(localPlayer: Player)
	player = localPlayer

	local function onCharacterAdded(character: Model)
		bindCharacter(character)
	end

	if player.Character then
		onCharacterAdded(player.Character)
	end

	player.CharacterAdded:Connect(onCharacterAdded)
	player.CharacterRemoving:Connect(function()
		clearAttributeConns()
	end)
end

return PolarisAbilityVfx
