--!strict

local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CameraShakeClient = require(script.Parent.CameraShakeClient)
local ScreenFxClient = require(script.Parent.ScreenFxClient)
local AbilityCooldownHelper = require(ReplicatedStorage.Shared.AbilityCooldownHelper)
local GameConstants = require(ReplicatedStorage.Shared.GameConstants)

local InvisibleWomanClient = {}

function InvisibleWomanClient.init(localPlayer: Player)
	local function setShieldFeel(on: boolean)
		CameraShakeClient.setHeldLayer("iw_shield", on, {
			fade = 0.28,
			shake = 0.07,
			fov = -1.4,
			vignette = 0.52,
			shakeRange = 1.05,
			shakeSlow = 0.42,
		})
	end

	local colorFx = Instance.new("ColorCorrectionEffect")
	colorFx.Name = "IwInvisGrade"
	colorFx.Brightness = 0
	colorFx.Contrast = 0
	colorFx.Saturation = 0
	colorFx.TintColor = Color3.fromRGB(255, 255, 255)
	colorFx.Enabled = true
	colorFx.Parent = Lighting

	local function parentGrade()
		local cam = Workspace.CurrentCamera
		if cam then
			colorFx.Parent = cam
		else
			colorFx.Parent = Lighting
		end
	end
	parentGrade()
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(parentGrade)

	local chokeBlur = Instance.new("BlurEffect")
	chokeBlur.Name = "IwChokeBlur"
	chokeBlur.Size = 0
	chokeBlur.Enabled = true
	chokeBlur.Parent = Lighting

	local chokeOn = false
	local chokeTween: Tween? = nil
	local function setChokeBlur(on: boolean)
		if chokeOn == on then
			return
		end
		chokeOn = on
		if chokeTween then
			chokeTween:Cancel()
		end
		chokeTween = TweenService:Create(
			chokeBlur,
			TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = if on then 22 else 0 }
		)
		chokeTween:Play()
	end

	local gradeOn = false
	local gradeTween: Tween? = nil
	local function setInvisGrade(on: boolean)
		if gradeOn == on then
			return
		end
		gradeOn = on
		if gradeTween then
			gradeTween:Cancel()
			gradeTween = nil
		end
		local info = TweenInfo.new(if on then 0.45 else 0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		gradeTween = TweenService:Create(colorFx, info, {
			Brightness = if on then 0.22 else 0,
			Contrast = if on then 0.04 else 0,
			Saturation = if on then 0.06 else 0,
			TintColor = if on then Color3.fromRGB(186, 214, 238) else Color3.fromRGB(255, 255, 255),
		})
		gradeTween:Play()
		CameraShakeClient.setHeldLayer("iw_invis", on, {
			fade = if on then 0.4 else 0.5,
			shake = if on then 0.03 else 0,
			fov = if on then -0.4 else 0,
			vignette = if on then 0.9 else 1,
			shakeRange = 0.9,
			shakeSlow = 0.5,
		})
	end

	local function hook(character: Model)
		local function refresh()
			local on = character:GetAttribute(GameConstants.IW_FORCEFIELD_ATTRIBUTE) == true
				or character:GetAttribute(GameConstants.IW_FLIGHT_SHIELD_ATTRIBUTE) == true
			setShieldFeel(on)
		end
		local function refreshInvis()
			setInvisGrade(
				character:GetAttribute(GameConstants.HERO_ATTRIBUTE) == "invisible_woman"
					and character:GetAttribute(GameConstants.IW_INVIS_ATTRIBUTE) == true
			)
		end
		character:GetAttributeChangedSignal(GameConstants.IW_FORCEFIELD_ATTRIBUTE):Connect(refresh)
		character:GetAttributeChangedSignal(GameConstants.IW_FLIGHT_SHIELD_ATTRIBUTE):Connect(refresh)
		character:GetAttributeChangedSignal(GameConstants.IW_INVIS_ATTRIBUTE):Connect(refreshInvis)
		character:GetAttributeChangedSignal(GameConstants.HERO_ATTRIBUTE):Connect(refreshInvis)
		local function refreshChoke()
			setChokeBlur(character:GetAttribute(GameConstants.IW_CHOKED_ATTRIBUTE) == true)
		end
		local lingerUntil = 0
		local function refreshScreen()
			local hero = character:GetAttribute(GameConstants.HERO_ATTRIBUTE)
			local pushOn = AbilityCooldownHelper.isActive(character, "forcefield_push")
			local projOn = AbilityCooldownHelper.isActive(character, "body_projection")
			if pushOn or projOn then
				lingerUntil = os.clock() + 0.9
			end
			local on = hero == "invisible_woman"
				and (
					character:GetAttribute(GameConstants.IW_FORCEFIELD_ATTRIBUTE) == true
					or character:GetAttribute(GameConstants.IW_FLIGHT_SHIELD_ATTRIBUTE) == true
					or character:GetAttribute(GameConstants.IW_INVIS_ATTRIBUTE) == true
					or character:GetAttribute(GameConstants.IS_FLYING_ATTRIBUTE) == true
					or AbilityCooldownHelper.isAnyActive(character, {
						"iw_forcefield",
						"invisibility",
						"forcefield_area",
						"forcefield_choke",
						"forcefield_crush",
						"forcefield_flight",
						"forcefield_push",
						"disc_throw",
						"body_projection",
						"forcefield_smash",
					})
					or os.clock() < lingerUntil
				)
			ScreenFxClient.setEnabled("invisible_woman", on == true)
			if lingerUntil > os.clock() then
				task.delay(0.95, refreshScreen)
			end
		end
		character:GetAttributeChangedSignal(GameConstants.IW_CHOKED_ATTRIBUTE):Connect(refreshChoke)
		character.AttributeChanged:Connect(function(attr)
			if string.sub(attr, 1, 14) == "AbilityActive_"
				or attr == GameConstants.HERO_ATTRIBUTE
				or attr == GameConstants.IW_FORCEFIELD_ATTRIBUTE
				or attr == GameConstants.IW_FLIGHT_SHIELD_ATTRIBUTE
				or attr == GameConstants.IW_INVIS_ATTRIBUTE
				or attr == GameConstants.IS_FLYING_ATTRIBUTE
			then
				refreshScreen()
			end
		end)
		refresh()
		refreshInvis()
		refreshChoke()
		refreshScreen()
	end

	localPlayer.CharacterAdded:Connect(function(character)
		setInvisGrade(false)
		hook(character)
	end)
	localPlayer.CharacterRemoving:Connect(function()
		setInvisGrade(false)
		setShieldFeel(false)
		setChokeBlur(false)
		ScreenFxClient.setEnabled("invisible_woman", false)
	end)
	if localPlayer.Character then
		hook(localPlayer.Character)
	end
end

return InvisibleWomanClient
