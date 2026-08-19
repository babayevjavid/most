--!strict
--[[
	Ability camera feel: tweened shake, colored vignette, FOV dip (quick in, smooth out).
	payload: { intensity: number?, duration: number?, range: number? }
]]

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConstants = require(ReplicatedStorage.Shared.GameConstants)
local AbilityCooldownHelper = require(ReplicatedStorage.Shared.AbilityCooldownHelper)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ClientSettings = require(script.Parent.ClientSettings)

local CameraShakeClient = {}

local VIGNETTE_IMAGE = "rbxassetid://18720640136"
local fovPunch = 0
local heldFov = 0
local speedFov = 0
local heldLayerApply: ((string, boolean, {
	shake: number?,
	fov: number?,
	vignette: number?,
	fade: number?,
	shakeRange: number?,
	shakeSlow: number?,
}?) -> ())? = nil

function CameraShakeClient.isAbilityZoomEnabled(): boolean
	return ClientSettings.isAbilityZoomEnabled()
end

function CameraShakeClient.setAbilityZoomEnabled(on: boolean)
	ClientSettings.setAbilityZoomEnabled(on)
end

function CameraShakeClient.isScreenShakeEnabled(): boolean
	return ClientSettings.isScreenShakeEnabled()
end

function CameraShakeClient.setScreenShakeEnabled(on: boolean)
	ClientSettings.setScreenShakeEnabled(on)
end

function CameraShakeClient.isScreenVfxEnabled(): boolean
	return ClientSettings.isScreenVfxEnabled()
end

function CameraShakeClient.setScreenVfxEnabled(on: boolean)
	ClientSettings.setScreenVfxEnabled(on)
end

function CameraShakeClient.getFovPunch(): number
	if not ClientSettings.isAbilityZoomEnabled() then
		return 0
	end
	return fovPunch + heldFov + speedFov
end

function CameraShakeClient.setHeldLayer(
	name: string,
	enabled: boolean,
	opts: {
		shake: number?,
		fov: number?,
		vignette: number?,
		fade: number?,
		shakeRange: number?,
		shakeSlow: number?,
	}?
)
	if heldLayerApply then
		heldLayerApply(name, enabled, opts)
	end
end

function CameraShakeClient.setHeldVignette(enabled: boolean, fadeSeconds: number?)
	CameraShakeClient.setHeldLayer("astral", enabled, {
		fade = fadeSeconds,
		shake = if enabled then 0.16 else 0,
		fov = if enabled then 2.5 else 0,
		vignette = if enabled then 0.4 else 1,
		shakeRange = 1.35,
		shakeSlow = 0.55,
	})
end

local function vignetteColorFor(character: Model?): Color3
	if not character then
		return Color3.fromRGB(40, 28, 48)
	end
	local heroId = character:GetAttribute(GameConstants.HERO_ATTRIBUTE)
	if heroId == "jean_grey" then
		local skin = character:GetAttribute(GameConstants.LOOK_MODE_ATTRIBUTE)
		if skin == "marvel_girl" then
			return GameConstants.MG_PSI_COLOR_MARVEL_GIRL
		end
		return GameConstants.MG_PSI_COLOR
	elseif heroId == "scarlet_witch" then
		return Color3.fromRGB(190, 55, 90)
	elseif heroId == "captain_marvel" then
		return Color3.fromRGB(255, 196, 72)
	elseif heroId == "iceman" then
		return Color3.fromRGB(129, 184, 255)
	elseif heroId == "invisible_woman" then
		return Color3.fromRGB(77, 71, 255)
	elseif heroId == "dagger" then
		return Color3.fromRGB(240, 236, 210)
	elseif heroId == "loki" then
		return Color3.fromRGB(80, 200, 120)
	end
	return Color3.fromRGB(40, 28, 48)
end

local function parseColor(value: any): Color3?
	if typeof(value) == "Color3" then
		return value
	end
	if type(value) == "table" then
		local r = value.R or value.r or value[1]
		local g = value.G or value.g or value[2]
		local b = value.B or value.b or value[3]
		if type(r) == "number" and type(g) == "number" and type(b) == "number" then
			if r > 1 or g > 1 or b > 1 then
				return Color3.fromRGB(r, g, b)
			end
			return Color3.new(r, g, b)
		end
	end
	return nil
end

function CameraShakeClient.init(localPlayer: Player)
	local ampValue = Instance.new("NumberValue")
	ampValue.Name = "ShakeAmp"
	ampValue.Value = 0

	local fovValue = Instance.new("NumberValue")
	fovValue.Name = "FovPunch"
	fovValue.Value = 0

	local vigValue = Instance.new("NumberValue")
	vigValue.Name = "Vignette"
	vigValue.Value = 1

	local heldVigValue = Instance.new("NumberValue")
	heldVigValue.Name = "HeldVignette"
	heldVigValue.Value = 1

	local heldAmpValue = Instance.new("NumberValue")
	heldAmpValue.Name = "HeldShake"
	heldAmpValue.Value = 0

	local heldFovValue = Instance.new("NumberValue")
	heldFovValue.Name = "HeldFov"
	heldFovValue.Value = 0

	local punchTintValue = Instance.new("NumberValue")
	punchTintValue.Name = "PunchTint"
	punchTintValue.Value = 0

	local colorFx = Instance.new("ColorCorrectionEffect")
	colorFx.Name = "MCU_ScreenFeel"
	colorFx.Enabled = true
	colorFx.TintColor = Color3.new(1, 1, 1)
	colorFx.Brightness = 0
	colorFx.Contrast = 0
	colorFx.Saturation = 0

	local punchTintColor: Color3? = nil
	local heldTintColor: Color3? = nil
	local heldTintAmp = 0
	local seed = 1.7
	local currentOffset = Vector3.zero
	local shakeTweens: { Tween } = {}
	local heldTweens: { Tween } = {}
	local bound = false
	local layers: {
		[string]: {
			shake: number,
			fov: number,
			vignette: number,
			shakeRange: number,
			shakeSlow: number,
		},
	} = {}
	local heldShakeRange = 1
	local heldShakeSlow = 1
	local holdConn: RBXScriptConnection? = nil

	local gui = Instance.new("ScreenGui")
	gui.Name = "AbilityFeelVignette"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 8
	gui.Parent = localPlayer:WaitForChild("PlayerGui")

	local vig = Instance.new("ImageLabel")
	vig.Name = "Vignette"
	vig.BackgroundTransparency = 1
	vig.Size = UDim2.fromScale(1, 1)
	vig.Image = VIGNETTE_IMAGE
	vig.ImageColor3 = Color3.fromRGB(40, 28, 48)
	vig.ImageTransparency = 1
	vig.ScaleType = Enum.ScaleType.Stretch
	vig.ZIndex = 1
	vig.Parent = gui

	local function cancelTweens()
		for _, tw in shakeTweens do
			tw:Cancel()
		end
		table.clear(shakeTweens)
	end

	local function cancelHeldTweens()
		for _, tw in heldTweens do
			tw:Cancel()
		end
		table.clear(heldTweens)
	end

	local function playTween(list: { Tween }, inst: Instance, info: TweenInfo, props: { [string]: any })
		local tw = TweenService:Create(inst, info, props)
		table.insert(list, tw)
		tw:Play()
		return tw
	end

	local function refreshVignette()
		if not ClientSettings.isScreenVfxEnabled() then
			vig.ImageTransparency = 1
			return
		end
		local mul = ClientSettings.getVignetteMul()
		vig.ImageTransparency = 1 - (1 - math.min(vigValue.Value, heldVigValue.Value)) * mul
	end

	fovValue.Changed:Connect(function(v)
		fovPunch = v
	end)
	heldFovValue.Changed:Connect(function(v)
		heldFov = v
	end)
	vigValue.Changed:Connect(refreshVignette)
	heldVigValue.Changed:Connect(refreshVignette)

	local function tweenHeldTo(shake: number, fov: number, vig: number, fade: number)
		cancelHeldTweens()
		local info = TweenInfo.new(math.max(0.16, fade * 1.44), Enum.EasingStyle.Cubic, Enum.EasingDirection.Out)
		playTween(heldTweens, heldAmpValue, info, { Value = shake })
		playTween(heldTweens, heldFovValue, info, { Value = fov })
		playTween(heldTweens, heldVigValue, info, { Value = vig })
	end

	heldLayerApply = function(
		name: string,
		enabled: boolean,
		opts: {
			shake: number?,
			fov: number?,
			vignette: number?,
			fade: number?,
			shakeRange: number?,
			shakeSlow: number?,
		}?
	)
		local fade = if opts and type(opts.fade) == "number" then opts.fade else 0.45
		if enabled then
			vig.ImageColor3 = vignetteColorFor(localPlayer.Character)
			layers[name] = {
				shake = if opts and type(opts.shake) == "number" then opts.shake else 0.1,
				fov = if opts and type(opts.fov) == "number" then opts.fov else -2,
				vignette = if opts and type(opts.vignette) == "number" then opts.vignette else 0.5,
				shakeRange = if opts and type(opts.shakeRange) == "number" then opts.shakeRange else 1,
				shakeSlow = if opts and type(opts.shakeSlow) == "number" then opts.shakeSlow else 1,
			}
		else
			layers[name] = nil
		end
		local shake, fov, vigT, range, slow = 0, 0, 1, 1, 1
		for _, layer in layers do
			shake = math.max(shake, layer.shake)
			fov += layer.fov
			vigT = math.min(vigT, layer.vignette)
			range = math.max(range, layer.shakeRange)
			slow = math.min(slow, layer.shakeSlow)
		end
		heldShakeRange = range
		heldShakeSlow = slow
		if fade <= 0.08 then
			cancelHeldTweens()
			heldAmpValue.Value = shake
			heldFovValue.Value = fov
			heldVigValue.Value = vigT
			heldFov = fov
		else
			tweenHeldTo(shake, fov, vigT, fade)
		end
	end

	local lastShakeHold = false
	local lastHeldTintKey = ""

	local function applyColorCorrection()
		if not ClientSettings.isScreenVfxEnabled() then
			colorFx.TintColor = Color3.new(1, 1, 1)
			colorFx.Brightness = 0
			colorFx.Contrast = 0
			colorFx.Saturation = 0
			return
		end
		local punchAmp = punchTintValue.Value * ClientSettings.getVignetteMul()
		local amp = math.max(punchAmp, heldTintAmp * ClientSettings.getVignetteMul())
		local color = if punchAmp >= heldTintAmp then punchTintColor else heldTintColor
		if amp < 0.01 or not color then
			colorFx.TintColor = Color3.new(1, 1, 1)
			colorFx.Brightness = 0
			colorFx.Contrast = 0
			colorFx.Saturation = 0
			return
		end
		local blend = math.clamp(amp, 0, 1)
		colorFx.TintColor = Color3.new(1, 1, 1):Lerp(color, blend)
		colorFx.Brightness = -0.1 * blend
		colorFx.Contrast = 0.16 * blend
		colorFx.Saturation = 0.2 * blend
	end

	local function syncHeldScreenFeel(character: Model?)
		if not character or not character.Parent then
			heldTintColor = nil
			heldTintAmp = 0
			if lastShakeHold then
				lastShakeHold = false
				CameraShakeClient.setHeldLayer("victimHit", false, { fade = 0.28 })
			end
			lastHeldTintKey = ""
			return
		end
		local untilTime = character:GetAttribute(GameConstants.SCREEN_TINT_UNTIL_ATTRIBUTE)
		local tint = parseColor(character:GetAttribute(GameConstants.SCREEN_TINT_ATTRIBUTE))
		if tint and type(untilTime) == "number" and workspace:GetServerTimeNow() >= untilTime then
			tint = nil
		end
		heldTintColor = tint
		heldTintAmp = if tint then 0.72 else 0
		local tintKey = if tint
			then string.format("%.3f,%.3f,%.3f", tint.R, tint.G, tint.B)
			else ""
		lastHeldTintKey = tintKey
		local shakeHold = character:GetAttribute(GameConstants.SCREEN_SHAKE_HOLD_ATTRIBUTE) == true
		if shakeHold ~= lastShakeHold then
			lastShakeHold = shakeHold
			CameraShakeClient.setHeldLayer("victimHit", shakeHold, {
				fade = if shakeHold then 0.12 else 0.28,
				shake = if shakeHold then 0.32 else 0,
				fov = if shakeHold then -3.2 else 0,
				vignette = if shakeHold then 0.42 else 1,
				shakeRange = 1.45,
				shakeSlow = 0.72,
			})
		end
	end

	local function updateSpeedFov(character: Model?, dt: number)
		local target = 0
		if character and character.Parent and character:GetAttribute(GameConstants.SCREEN_SPEED_FOV_ATTRIBUTE) == true then
			local root = character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				target = math.clamp(root.AssemblyLinearVelocity.Magnitude / 68, 0, 1) * 12
			end
		end
		speedFov += (target - speedFov) * math.clamp(dt * 9, 0, 1)
		if math.abs(speedFov) < 0.02 then
			speedFov = 0
		end
	end

	local function tickShake(dt: number)
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		if colorFx.Parent ~= cam then
			colorFx.Parent = cam
		end
		applyColorCorrection()
		updateSpeedFov(localPlayer.Character, dt)
		syncHeldScreenFeel(localPlayer.Character)
		local punchAmp = ampValue.Value
		local heldAmp = heldAmpValue.Value
		local amp = if ClientSettings.isScreenShakeEnabled() then math.max(punchAmp, heldAmp) else 0
		if amp < 0.004 then
			currentOffset = currentOffset:Lerp(Vector3.zero, math.clamp(dt * 16, 0, 1))
			if currentOffset.Magnitude < 0.01 then
				currentOffset = Vector3.zero
			end
			if currentOffset.Magnitude > 0.001 then
				cam.CFrame *= CFrame.new(currentOffset * 0.05)
			end
			return
		end

		local t = os.clock()
		local fast = punchAmp > 0.02
		local slowMul = math.clamp(heldShakeSlow, 0.25, 1.2)
		local rangeMul = math.clamp(heldShakeRange, 0.6, 3)
		local f1 = if fast then 6.2 else (0.92 * slowMul)
		local f2 = if fast then 5.4 else (0.68 * slowMul)
		local f3 = if fast then 4.1 else (0.52 * slowMul)
		local n1 = math.noise(t * f1, seed, 0.2)
		local n2 = math.noise(seed * 0.3, t * f2, 1.1)
		local n3 = math.noise(0.7, seed, t * f3)
		local span = if fast then 1.25 else rangeMul
		local targetOffset = Vector3.new(n1 * amp * 2.55 * span, n2 * amp * 2.15 * span, n3 * amp * 1.2 * span)
		local follow = if fast then 14 else 2.8
		currentOffset = currentOffset:Lerp(targetOffset, math.clamp(dt * follow, 0.05, 1))
		local roll = (if fast then 0.055 else 0.032) * span
		local pitch = (if fast then 0.048 else 0.024) * span
		cam.CFrame = cam.CFrame
			* CFrame.new(currentOffset * (if fast then 0.12 else 0.11 * span))
			* CFrame.Angles(n2 * amp * pitch, 0, n1 * amp * roll)
	end

	local function ensureLoop()
		if bound then
			return
		end
		bound = true
		RunService:BindToRenderStep("MCU_AbilityCameraFeel", Enum.RenderPriority.Camera.Value + 3, function(dt)
			tickShake(math.clamp(dt, 0.001, 0.05))
		end)
	end

	Remotes.getEvent("CameraShake").OnClientEvent:Connect(function(payload: any)
		local intensity = 0.55
		local duration = 0.45
		local rangeScale = 1
		local fovScale = 1
		local vignetteScale = 1
		local tintColor: Color3? = nil
		local tintDuration: number? = nil
		if type(payload) == "table" then
			if type(payload.intensity) == "number" then
				intensity = payload.intensity
			end
			if type(payload.duration) == "number" then
				duration = payload.duration
			end
			if type(payload.range) == "number" then
				rangeScale = math.clamp(payload.range, 0.35, 2.5)
			end
			if type(payload.fovScale) == "number" then
				fovScale = math.clamp(payload.fovScale, 0, 2.5)
			end
			if type(payload.vignetteScale) == "number" then
				vignetteScale = math.clamp(payload.vignetteScale, 0, 2)
			end
			tintColor = parseColor(payload.tint)
			if type(payload.tintDuration) == "number" then
				tintDuration = payload.tintDuration
			end
		end

		local incoming = math.max(0, intensity) * rangeScale * 1.32
		local peak = if ClientSettings.isScreenShakeEnabled() then math.max(ampValue.Value, incoming) else 0
		local dip = if ClientSettings.isAbilityZoomEnabled()
			then -math.clamp((1.6 + incoming * 2.7) * fovScale, 0, 5.6)
			else 0
		local vigPeak = if ClientSettings.isScreenVfxEnabled()
			then math.clamp(1 - (0.38 + incoming * 0.48) * vignetteScale * ClientSettings.getVignetteMul(), 0.1, 1)
			else 1
		local attack = 0.06
		local recover = math.max(0.42, duration * 1.85)
		seed = os.clock() * 13.17 + incoming * 4.1

		local character = localPlayer.Character
		if heldVigValue.Value > 0.92 then
			vig.ImageColor3 = vignetteColorFor(character)
		end

		cancelTweens()
		playTween(shakeTweens, ampValue, TweenInfo.new(attack, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), { Value = peak })
		playTween(shakeTweens, fovValue, TweenInfo.new(attack, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), { Value = dip })
		playTween(shakeTweens, vigValue, TweenInfo.new(attack, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out), { Value = vigPeak })

		task.delay(attack, function()
			playTween(shakeTweens, ampValue, TweenInfo.new(recover, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out), { Value = 0 })
			playTween(shakeTweens, fovValue, TweenInfo.new(recover, Enum.EasingStyle.Circular, Enum.EasingDirection.Out), { Value = 0 })
			playTween(shakeTweens, vigValue, TweenInfo.new(recover * 1.05, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Value = 1 })
		end)

		if tintColor and ClientSettings.isScreenVfxEnabled() then
			punchTintColor = tintColor
			local tintHold = math.max(0.18, tintDuration or (duration * 0.85))
			local tintOut = math.max(0.28, tintHold * 0.9)
			playTween(shakeTweens, punchTintValue, TweenInfo.new(attack, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), { Value = 0.88 })
			task.delay(attack + tintHold * 0.35, function()
				playTween(shakeTweens, punchTintValue, TweenInfo.new(tintOut, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Value = 0 })
			end)
		end

		ensureLoop()
	end)

	ClientSettings.onChanged(function()
		refreshVignette()
		applyColorCorrection()
		if not ClientSettings.isScreenShakeEnabled() then
			cancelTweens()
			cancelHeldTweens()
			ampValue.Value = 0
			heldAmpValue.Value = 0
			currentOffset = Vector3.zero
		end
		if not ClientSettings.isScreenVfxEnabled() then
			vigValue.Value = 1
			heldVigValue.Value = 1
			punchTintValue.Value = 0
		end
	end)

	localPlayer.CharacterRemoving:Connect(function()
		if holdConn then
			holdConn:Disconnect()
			holdConn = nil
		end
		cancelTweens()
		cancelHeldTweens()
		ampValue.Value = 0
		fovValue.Value = 0
		vigValue.Value = 1
		heldVigValue.Value = 1
		heldAmpValue.Value = 0
		heldFovValue.Value = 0
		heldVigValue.Value = 1
		punchTintValue.Value = 0
		heldFov = 0
		speedFov = 0
		punchTintColor = nil
		heldTintColor = nil
		heldTintAmp = 0
		lastShakeHold = false
		lastHeldTintKey = ""
		table.clear(layers)
		fovPunch = 0
		currentOffset = Vector3.zero
		vig.ImageTransparency = 1
		colorFx.TintColor = Color3.new(1, 1, 1)
		colorFx.Brightness = 0
		colorFx.Contrast = 0
		colorFx.Saturation = 0
	end)

	ensureLoop()

	local HOLD_FEEL_IDS: { [string]: boolean } = {
		psionic_barrier = true,
		psionic_bolt = true,
		psychic_pull = true,
		telekinesis = true,
		telekinetic_debris = true,
		telekinetic_slam = true,
		telepathic_pain = true,
		telepathic_outburst = true,
		mind_link = true,
		hex_beam = true,
		hex_bolt = true,
		hex_shield = true,
		hex_displacement = true,
		hex_blast = true,
		probability_hex = true,
		rune_entrapment = true,
		regeneration = true,
		iw_forcefield = true,
		forcefield_crush = true,
		forcefield_area = true,
		forcefield_choke = true,
		forcefield_push = true,
		forcefield_smash = true,
		disc_throw = true,
		body_projection = true,
		invisibility = true,
		astral_projection = true,
	}

	local function syncAbilityHold(character: Model)
		local on = false
		for abilityId, _ in HOLD_FEEL_IDS do
			if AbilityCooldownHelper.isActive(character, abilityId) then
				on = true
				break
			end
		end
		CameraShakeClient.setHeldLayer("abilityHold", on, {
			fade = if on then 0.28 else 0.7,
			shake = if on then 0.08 else 0,
			fov = if on then -2.4 else 0,
			vignette = if on then 0.52 else 1,
			shakeRange = 0.9,
			shakeSlow = 0.4,
		})
	end

	local function hookAbilityHold(character: Model)
		if holdConn then
			holdConn:Disconnect()
			holdConn = nil
		end
		holdConn = character.AttributeChanged:Connect(function(attr)
			if string.sub(attr, 1, 14) == "AbilityActive_" then
				syncAbilityHold(character)
			elseif attr == GameConstants.SCREEN_TINT_ATTRIBUTE
				or attr == GameConstants.SCREEN_TINT_UNTIL_ATTRIBUTE
				or attr == GameConstants.SCREEN_SHAKE_HOLD_ATTRIBUTE
			then
				syncHeldScreenFeel(character)
			end
		end)
		syncAbilityHold(character)
		syncHeldScreenFeel(character)
	end

	if localPlayer.Character then
		hookAbilityHold(localPlayer.Character)
	end
	localPlayer.CharacterAdded:Connect(hookAbilityHold)
end

return CameraShakeClient
