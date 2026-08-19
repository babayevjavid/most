local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.LightningEConfig)

local lastCast: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any
local impactFxEvent: RemoteEvent? = nil

local beamBlue = Color3.fromRGB(0, 170, 255)
local beamColorA = Color3.fromRGB(40, 200, 255)
local beamColorB = Color3.fromRGB(0, 120, 210)
local beamTransparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.02),
	NumberSequenceKeypoint.new(0.5, 0.18),
	NumberSequenceKeypoint.new(1, 1),
})

local BEAM_TEXTURE = "rbxassetid://12781800668"

local function beamTravelSeconds(handMid: Vector3, targetPos: Vector3): number
	local dist = (targetPos - handMid).Magnitude
	local raw = dist / Config.BeamSpeedStudsPerSec
	return math.clamp(raw, Config.BeamTravelTimeMin, Config.BeamTravelTimeMax)
end

local function getHands(character: Model): (BasePart?, BasePart?)
	local r = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	local l = character:FindFirstChild("LeftHand") or character:FindFirstChild("Left Arm")
	return r and r :: BasePart?, l and l :: BasePart?
end

local function ensureAttachment(part: BasePart, name: string): Attachment
	local a = part:FindFirstChild(name) :: Attachment?
	if a then
		return a
	end
	a = Instance.new("Attachment")
	a.Name = name
	a.Position = Vector3.new(0, -0.35, -0.15)
	a.Parent = part
	return a
end

local function collectParticleEmitters(root: Instance): { ParticleEmitter }
	local t: { ParticleEmitter } = {}
	for _, d in root:GetDescendants() do
		if d:IsA("ParticleEmitter") then
			table.insert(t, d)
		end
	end
	return t
end

local function enableParticleTree(root: Instance, on: boolean)
	for _, d in root:GetDescendants() do
		if d:IsA("ParticleEmitter") then
			d.Enabled = on
		elseif d:IsA("Beam") then
			d.Enabled = on
		end
	end
end

local function tweenRatesToZero(emitters: { ParticleEmitter }, duration: number)
	if #emitters == 0 then
		return
	end
	if duration <= 0 then
		for _, e in emitters do
			e.Enabled = false
			e.Rate = 0
		end
		return
	end
	local startRates: { [ParticleEmitter]: number } = {}
	for _, e in emitters do
		startRates[e] = e.Rate
	end
	local t0 = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.Heartbeat:Connect(function()
		local a = math.clamp((os.clock() - t0) / duration, 0, 1)
		local w = 1 - a * a
		for _, e in emitters do
			if e.Parent and startRates[e] then
				e.Rate = startRates[e] * w
			end
		end
		if a >= 1 then
			conn:Disconnect()
			for _, e in emitters do
				if e.Parent then
					e.Enabled = false
					e.Rate = 0
				end
			end
		end
	end)
end

local function weldFxToHand(hand: BasePart, template: Instance): Instance?
	local clone = template:Clone()

	local primary: BasePart? = nil
	if clone:IsA("Model") then
		clone.Parent = hand
		primary = clone.PrimaryPart or clone:FindFirstChildWhichIsA("BasePart", true) :: BasePart?
		if primary then
			clone:PivotTo(hand.CFrame)
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = hand
			weld.Part1 = primary
			weld.Parent = primary
		end
	elseif clone:IsA("Accessory") then
		local handle = clone:FindFirstChild("Handle") :: BasePart?
		if not handle then
			clone:Destroy()
			return nil
		end
		clone.Parent = hand.Parent
		handle.CFrame = hand.CFrame
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = hand
		weld.Part1 = handle
		weld.Parent = handle
	elseif clone:IsA("BasePart") then
		clone.Parent = hand
		primary = clone
		clone.CFrame = hand.CFrame
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = hand
		weld.Part1 = clone
		weld.Parent = clone
	else
		clone.Parent = hand
	end

	enableParticleTree(clone, true)
	for _, pe in collectParticleEmitters(clone) do
		local burst = math.clamp(math.floor(pe.Rate * 0.12 + 10), 10, 56)
		pe:Emit(burst)
	end
	return clone
end

local function makeProbe(startPos: Vector3): (BasePart, Attachment)
	local p = Instance.new("Part")
	p.Name = "LightningBeamProbe"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.Transparency = 1
	p.Size = Vector3.new(0.15, 0.15, 0.15)
	p.CFrame = CFrame.new(startPos)
	p.Parent = workspace
	local att = Instance.new("Attachment")
	att.Name = "ProbeAtt"
	att.Parent = p
	return p, att
end

local function playTwinBeamFromHands(
	rightHand: BasePart,
	leftHand: BasePart,
	targetPos: Vector3,
	beamDuration: number
)
	local attR = ensureAttachment(rightHand, "LightningBeamHandAttR")
	local attL = ensureAttachment(leftHand, "LightningBeamHandAttL")

	local probeR, pAttR = makeProbe(rightHand.Position)
	local probeL, pAttL = makeProbe(leftHand.Position)

	local beamR = Instance.new("Beam")
	beamR.Name = "LightningHandBeamR"
	beamR.Attachment0 = attR
	beamR.Attachment1 = pAttR
	beamR.FaceCamera = true
	beamR.Width0 = 1.05
	beamR.Width1 = 0.48
	beamR.Brightness = 6
	beamR.LightEmission = 1
	beamR.LightInfluence = 0.18
	beamR.Texture = BEAM_TEXTURE
	beamR.TextureLength = 7
	beamR.TextureMode = Enum.TextureMode.Wrap
	beamR.TextureSpeed = 4.5
	beamR.Segments = 12
	beamR.CurveSize0 = 0.42
	beamR.CurveSize1 = -0.34
	beamR.ZOffset = 0.08
	beamR.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, beamColorA),
		ColorSequenceKeypoint.new(0.5, beamBlue),
		ColorSequenceKeypoint.new(1, beamColorB),
	})
	beamR.Transparency = beamTransparency
	beamR.Parent = probeR

	local beamL = Instance.new("Beam")
	beamL.Name = "LightningHandBeamL"
	beamL.Attachment0 = attL
	beamL.Attachment1 = pAttL
	beamL.FaceCamera = true
	beamL.Width0 = 1.05
	beamL.Width1 = 0.48
	beamL.Brightness = 6
	beamL.LightEmission = 1
	beamL.LightInfluence = 0.18
	beamL.Texture = BEAM_TEXTURE
	beamL.TextureLength = 7
	beamL.TextureMode = Enum.TextureMode.Wrap
	beamL.TextureSpeed = 4.5
	beamL.Segments = 12
	beamL.CurveSize0 = -0.38
	beamL.CurveSize1 = 0.32
	beamL.ZOffset = 0.08
	beamL.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, beamColorA),
		ColorSequenceKeypoint.new(0.5, beamBlue),
		ColorSequenceKeypoint.new(1, beamColorB),
	})
	beamL.Transparency = beamTransparency
	beamL.Parent = probeL

	local cfR = CFrame.new(targetPos)
	local cfL = CFrame.new(targetPos)
	local ti = TweenInfo.new(beamDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(probeR, ti, { CFrame = cfR }):Play()
	TweenService:Create(probeL, ti, { CFrame = cfL }):Play()

	task.delay(beamDuration, function()
		if probeR.Parent then
			probeR:Destroy()
		end
		if probeL.Parent then
			probeL:Destroy()
		end
	end)
end

local function spawnEndAttachmentFX(template: Instance, worldPos: Vector3)
	local holder = Instance.new("Part")
	holder.Name = "LightningEndAE"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.Transparency = 1
	holder.Size = Vector3.one * 0.25
	holder.CFrame = CFrame.new(worldPos)
	holder.Parent = workspace

	local clone = template:Clone()
	if clone:IsA("Attachment") then
		clone.Parent = holder
	elseif clone:IsA("Model") then
		clone:PivotTo(holder.CFrame)
		clone.Parent = holder
	else
		clone.Parent = holder
	end

	enableParticleTree(holder, true)

	local emitters = collectParticleEmitters(holder)
	task.delay(Config.EndFxParticleRun, function()
		tweenRatesToZero(emitters, Config.EndFxFadeDuration)
	end)

	task.delay(Config.EndFxDestroyAfter, function()
		if holder.Parent then
			holder:Destroy()
		end
	end)
end

local function attributeInteractableTruthy(inst: Instance): boolean
	local a = inst:GetAttribute("Interactable")
	if a == nil then
		return false
	end
	if a == false or a == 0 or a == "" then
		return false
	end
	if a == true or a == 1 or a == "true" then
		return true
	end
	return true
end

local function valueBaseTruthy(v: ValueBase): boolean
	if v:IsA("BoolValue") then
		return v.Value
	end
	if v:IsA("IntValue") or v:IsA("NumberValue") then
		return v.Value ~= 0
	end
	if v:IsA("StringValue") then
		return v.Value ~= ""
	end
	return true
end

local function objectValueInteractableTruthy(v: ObjectValue): boolean
	return v.Value ~= nil
end

-- Model is "interactable" if the root or any descendant marks it (attribute, value, or ObjectValue).
local function modelHasInteractableValue(model: Model): boolean
	if attributeInteractableTruthy(model) then
		return true
	end
	for _, d in model:GetDescendants() do
		if attributeInteractableTruthy(d) then
			return true
		end
		if d.Name == "Interactable" then
			if d:IsA("ValueBase") and valueBaseTruthy(d) then
				return true
			end
			if d:IsA("ObjectValue") and objectValueInteractableTruthy(d) then
				return true
			end
		end
	end
	return false
end

local function partTopInteractableFlag(part: BasePart): boolean
	if attributeInteractableTruthy(part) then
		return true
	end
	for _, ch in part:GetChildren() do
		if ch.Name == "Interactable" then
			if ch:IsA("ValueBase") and valueBaseTruthy(ch) then
				return true
			end
			if ch:IsA("ObjectValue") and objectValueInteractableTruthy(ch) then
				return true
			end
		end
	end
	return false
end

-- Aim direction (hands → target), same axis as client mouse ray / beam travel.
local function beamPushDirection(handMid: Vector3, targetPos: Vector3, fallbackLook: Vector3): Vector3
	local d = targetPos - handMid
	if d.Magnitude > 0.08 then
		return d.Unit
	end
	local flat = Vector3.new(fallbackLook.X, 0, fallbackLook.Z)
	if flat.Magnitude > 0.05 then
		return flat.Unit
	end
	return Vector3.new(0, 0, -1)
end

local function applyAssemblyKnockback(pushDirUnit: Vector3, part: BasePart, push: number, pushedRoots: { [BasePart]: boolean })
	if part.Anchored then
		return
	end
	local rootP = part:GetRootPart()
	if pushedRoots[rootP] then
		return
	end
	pushedRoots[rootP] = true
	local boost = pushDirUnit * push
	rootP.AssemblyLinearVelocity = rootP.AssemblyLinearVelocity + boost
end

local function applyHitZoneDamageAndKnockback(casterCharacter: Model, center: Vector3, pushDirUnit: Vector3)
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { casterCharacter }

	local radius = Config.HitRadius
	local damage = Config.HitDamage
	local push = Config.KnockbackVelocity

	local parts = workspace:GetPartBoundsInRadius(center, radius, overlap)
	local handledHum: { [Humanoid]: boolean } = {}
	local pushedInteractableModel: { [Model]: boolean } = {}
	local pushedRoots: { [BasePart]: boolean } = {}

	for _, part in parts do
		local model = part:FindFirstAncestorOfClass("Model")

		if model == casterCharacter then
			continue
		end

		if model then
			local hum = model:FindFirstChildWhichIsA("Humanoid", true)
			if hum and hum.Health > 0 then
				if handledHum[hum] then
					continue
				end
				handledHum[hum] = true
				hum:TakeDamage(damage)
				local hrp = model:FindFirstChild("HumanoidRootPart") :: BasePart?
				if hrp then
					applyAssemblyKnockback(pushDirUnit, hrp, push, pushedRoots)
				end
				continue
			end

			if modelHasInteractableValue(model) then
				if pushedInteractableModel[model] then
					continue
				end
				pushedInteractableModel[model] = true
				local prim = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
				if prim then
					applyAssemblyKnockback(pushDirUnit, prim, push, pushedRoots)
				end
			end
		else
			if partTopInteractableFlag(part) then
				applyAssemblyKnockback(pushDirUnit, part, push, pushedRoots)
			end
		end
	end
end

local function playE(player: Player, targetPos: Vector3)
	local character = player.Character
	if not character then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = character:FindFirstChildOfClass("Humanoid")
	if not root or not hum or hum.Health <= 0 then
		return
	end
	if (targetPos - root.Position).Magnitude > Config.MaxRange + 2 then
		return
	end

	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local lightningFolder = assets and assets:FindFirstChild("Lightning")
	local handTemplate = lightningFolder and lightningFolder:FindFirstChild("LightningHand")
	local aeTemplate = lightningFolder and lightningFolder:FindFirstChild("LightningBeamAEAttachment")
	if not handTemplate or not aeTemplate then
		warn("[LightningE] Missing ReplicatedStorage.Assets.Lightning templates (LightningHand / LightningBeamAEAttachment).")
		return
	end

	local rHand, lHand = getHands(character)
	if not rHand or not lHand then
		return
	end

	local handCloneR = weldFxToHand(rHand, handTemplate)
	local handCloneL = weldFxToHand(lHand, handTemplate)

	local handMid = (rHand.Position + lHand.Position) * 0.5
	local beamDuration = beamTravelSeconds(handMid, targetPos)
	local pushDirUnit = beamPushDirection(handMid, targetPos, root.CFrame.LookVector)

	playTwinBeamFromHands(rHand, lHand, targetPos, beamDuration)

	task.delay(beamDuration, function()
		spawnEndAttachmentFX(aeTemplate, targetPos)
		applyHitZoneDamageAndKnockback(character, targetPos, pushDirUnit)
		if impactFxEvent then
			impactFxEvent:FireAllClients(targetPos)
		end
	end)

	local fadeDur = Config.HandParticleFadeDuration
	task.delay(Config.HandParticleFadeStart, function()
		if handCloneR then
			tweenRatesToZero(collectParticleEmitters(handCloneR), fadeDur)
		end
		if handCloneL then
			tweenRatesToZero(collectParticleEmitters(handCloneL), fadeDur)
		end
	end)

	local handDestroyAt = Config.HandParticleFadeStart + Config.HandCloneDestroyAfterFade
	task.delay(handDestroyAt, function()
		if handCloneR and handCloneR.Parent then
			handCloneR:Destroy()
		end
		if handCloneL and handCloneL.Parent then
			handCloneL:Destroy()
		end
	end)
end

local M = {}

function M.init(remotes: Folder)
	local ev = remotes:WaitForChild("LightningTwinBeam") :: RemoteEvent
	impactFxEvent = remotes:WaitForChild("LightningBeamImpact") :: RemoteEvent

	ev.OnServerEvent:Connect(function(plr: Player, target: unknown)
		if plr:GetAttribute("SelectedPower") ~= "Electrokinesis" then
			return
		end
		if typeof(target) ~= "Vector3" then
			return
		end
		local now = os.clock()
		local prev = lastCast[plr]
		if prev and (now - prev) < Config.AbilityCooldown then
			return
		end
		lastCast[plr] = now
		plr:SetAttribute("ElectrokinesisECdUntil", workspace:GetServerTimeNow() + Config.AbilityCooldown)
		playE(plr, target :: Vector3)
	end)

	Players.PlayerRemoving:Connect(function(p)
		lastCast[p] = nil
		p:SetAttribute("ElectrokinesisECdUntil", nil)
	end)
end

return M
