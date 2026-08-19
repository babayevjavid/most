-- Shared: find nearest Belthazor and vanquish (used by chat + spell commit).

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

-- Vanquish VFX: play on victim, then finish after delay (seconds).
local VANQUISH_ANIMATION_ID = "rbxassetid://72159059286405"
local VANQUISH_KILL_AFTER_SEC = 2

type Config = {
	BelthazorTagName: string?,
	BelthazorVanquishRadiusStuds: number?,
}

local function isAliveBelthazor(model: Model): boolean
	local hum = model:FindFirstChildOfClass("Humanoid")
	local hrp = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or hum.Health <= 0 or not hrp then
		return false
	end
	if model:GetAttribute("Vanquished") == true then
		return false
	end
	return true
end

local function getNearestBelthazorTo(position: Vector3, tag: string): (Model?, BasePart?)
	local bestModel: Model? = nil
	local bestRoot: BasePart? = nil
	local bestDist = math.huge
	local seen: { [Model]: boolean } = {}

	local function consider(model: Model)
		if seen[model] then
			return
		end
		if not isAliveBelthazor(model) then
			return
		end
		seen[model] = true
		local hrp = model:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hrp then
			return
		end
		local d = (hrp.Position - position).Magnitude
		if d < bestDist then
			bestDist = d
			bestModel = model
			bestRoot = hrp
		end
	end

	for _, inst in CollectionService:GetTagged(tag) do
		if inst:IsA("Model") then
			consider(inst)
		end
	end

	for _, inst in Workspace:GetDescendants() do
		if inst:IsA("Model") then
			if inst:GetAttribute("ChosenCharacter") == "Belthazor" or inst:GetAttribute("BelthazorVanquishTarget") == true then
				consider(inst)
			end
		end
	end

	return bestModel, bestRoot
end

local function vanquishModel(model: Model, GameHealth: any)
	if model:GetAttribute("Vanquished") == true then
		return
	end
	model:SetAttribute("Vanquished", true)

	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end

	-- Smooth: show red highlight during vanquish window.
	local hl = model:FindFirstChild("VanquishHighlight")
	if not (hl and hl:IsA("Highlight")) then
		hl = Instance.new("Highlight")
		hl.Name = "VanquishHighlight"
		hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		-- Orangey-red vanquish tint.
		hl.FillColor = Color3.fromRGB(255, 92, 36)
		hl.OutlineColor = Color3.fromRGB(255, 170, 120)
		hl.FillTransparency = 1
		hl.OutlineTransparency = 1
		hl.Parent = model
	end
	pcall(function()
		TweenService:Create(hl, TweenInfo.new(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			-- Fade in from invisible (1) to visible (0).
			FillTransparency = 0,
			OutlineTransparency = 0,
		}):Play()
	end)

	hum.WalkSpeed = 0
	hum.JumpPower = 0
	hum.AutoRotate = false
	hum.PlatformStand = true

	task.defer(function()
		local animator = hum:FindFirstChildOfClass("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = hum
		end
		local anim = Instance.new("Animation")
		anim.AnimationId = VANQUISH_ANIMATION_ID
		local ok, track = pcall(function()
			return animator:LoadAnimation(anim)
		end)
		if ok and track then
			track:Play(0.12, 1, 1)
		end
	end)

	task.delay(VANQUISH_KILL_AFTER_SEC, function()
		if not model.Parent then
			return
		end
		local h = model:FindFirstChildOfClass("Humanoid")
		if h then
			GameHealth.applyDamage(h, 1e6)
		end
		local h2 = model:FindFirstChild("VanquishHighlight")
		if h2 and h2:IsA("Highlight") then
			pcall(function()
				TweenService:Create(h2, TweenInfo.new(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
					FillTransparency = 1,
					OutlineTransparency = 1,
				}):Play()
			end)
			task.delay(0.35, function()
				if h2.Parent then
					h2:Destroy()
				end
			end)
		end
	end)
end

local function tryVanquishFromWitchPlayer(player: Player, CharacterConfig: Config, GameHealth: any): boolean
	local char = player.Character
	local pr = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not pr then
		return false
	end
	local tag = CharacterConfig.BelthazorTagName or "Belthazor"
	local radius = CharacterConfig.BelthazorVanquishRadiusStuds or 50
	local bModel, bRoot = getNearestBelthazorTo(pr.Position, tag)
	if not bModel or not bRoot then
		return false
	end
	if (pr.Position - bRoot.Position).Magnitude > radius then
		return false
	end
	vanquishModel(bModel, GameHealth)
	return true
end

return {
	tryVanquishFromWitchPlayer = tryVanquishFromWitchPlayer,
}
