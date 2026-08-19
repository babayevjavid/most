--!strict
--[[
	Telepathic Outburst server: charged expanding shockwave.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AbilityCooldownHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityCooldownHelper"))
local AbilityVfxHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityVfxHelper"))
local InteractableHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("InteractableHelper"))
local PushHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PushHelper"))
local SmoothMotionHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SmoothMotionHelper"))
local TelepathicOutburstConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TelepathicOutburstConstants"))

local ResourceService = require(script.Parent:WaitForChild("ResourceService"))

local ABILITY_ID = TelepathicOutburstConstants.ABILITY_ID
local COOLDOWN_SEC = TelepathicOutburstConstants.COOLDOWN_SEC

local TelepathicOutburstService = {}

local hitOnce: { [Instance]: boolean } = {}

local function isJeanGrey(plr: Player): boolean
	return plr:GetAttribute("SelectedCharacter") == "JeanGrey"
end

local function getOutburstCost(chargeAlpha: number): number
	return ResourceService.getScaledCost("JeanGrey", ABILITY_ID, chargeAlpha) or 8
end

local function applyWaveHit(
	caster: Model,
	origin: Vector3,
	targetKey: Instance,
	targetModel: Model?,
	targetHum: Humanoid?,
	targetPart: BasePart,
	damage: number,
	pushSpeed: number,
	pushUp: number,
	chargeAlpha: number
)
	if hitOnce[targetKey] then
		return
	end
	hitOnce[targetKey] = true

	local dir = targetPart.Position - origin
	if dir.Magnitude < 0.01 then
		local casterRoot = caster:FindFirstChild("HumanoidRootPart") :: BasePart?
		dir = if casterRoot then casterRoot.CFrame.LookVector else Vector3.new(0, 0, -1)
	end

	if targetHum and targetHum.Health > 0 and targetModel then
		targetHum:TakeDamage(damage)
		PushHelper.applyToModel(targetModel, dir, {
			speed = pushSpeed * (0.5 + chargeAlpha * 0.5),
			upBoost = pushUp,
		})
	elseif targetModel and InteractableHelper.modelIsInteractableProp(targetModel) then
		InteractableHelper.applyDamage(targetModel, damage)
		PushHelper.applyToPart(targetPart, dir, {
			speed = pushSpeed * (0.5 + chargeAlpha * 0.5),
			upBoost = pushUp,
		})
	elseif InteractableHelper.hasInteractableMark(targetPart) then
		InteractableHelper.applyDamage(targetPart, damage)
		PushHelper.applyToPart(targetPart, dir, {
			speed = pushSpeed * (0.5 + chargeAlpha * 0.5),
			upBoost = pushUp,
		})
	end
end

local function processRadiusHits(
	plr: Player,
	char: Model,
	origin: Vector3,
	currentRadius: number,
	damage: number,
	pushSpeed: number,
	pushUp: number,
	chargeAlpha: number
)
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { char }

	for _, part in workspace:GetPartBoundsInRadius(origin, currentRadius, overlap) do
		local model = part:FindFirstAncestorOfClass("Model")
		if model == char then
			continue
		end

		if model then
			local hum = model:FindFirstChildOfClass("Humanoid")
			local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
			if hum and hum.Health > 0 and root then
				local targetPlr = Players:GetPlayerFromCharacter(model)
				if targetPlr == plr then
					continue
				end
				applyWaveHit(char, origin, root, model, hum, root, damage, pushSpeed, pushUp, chargeAlpha)
			elseif InteractableHelper.modelIsInteractableProp(model) then
				local key = model.PrimaryPart or part
				applyWaveHit(char, origin, key, model, nil, part, damage, pushSpeed, pushUp, chargeAlpha)
			end
		elseif InteractableHelper.hasInteractableMark(part) then
			applyWaveHit(char, origin, part, nil, nil, part, damage, pushSpeed, pushUp, chargeAlpha)
		end
	end
end

local function runWave(plr: Player, char: Model, chargeAlpha: number)
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	local origin = root.Position
	local maxRadius = TelepathicOutburstConstants.MIN_RADIUS
		+ (TelepathicOutburstConstants.MAX_RADIUS - TelepathicOutburstConstants.MIN_RADIUS) * chargeAlpha
	local damage = TelepathicOutburstConstants.MIN_DAMAGE
		+ (TelepathicOutburstConstants.MAX_DAMAGE - TelepathicOutburstConstants.MIN_DAMAGE) * chargeAlpha
	local duration = TelepathicOutburstConstants.WAVE_DURATION

	AbilityVfxHelper.spawnExpandingSphere(
		origin,
		TelepathicOutburstConstants.COLOR,
		2,
		maxRadius,
		duration
	)

	table.clear(hitOnce)
	local start = tick()
	while tick() - start < duration do
		local alpha = SmoothMotionHelper.smoothstep((tick() - start) / duration)
		local currentRadius = maxRadius * alpha
		processRadiusHits(
			plr,
			char,
			origin,
			currentRadius,
			damage,
			TelepathicOutburstConstants.PUSH_SPEED,
			TelepathicOutburstConstants.PUSH_UP,
			chargeAlpha
		)
		RunService.Heartbeat:Wait()
	end
end

function TelepathicOutburstService.setup(releaseRemote: RemoteEvent)
	releaseRemote.OnServerEvent:Connect(function(plr: Player, chargeAlpha: unknown)
		if not isJeanGrey(plr) then
			return
		end
		if typeof(chargeAlpha) ~= "number" then
			return
		end

		local char = plr.Character
		if not char or not char.Parent then
			return
		end
		local humanoid = char:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			return
		end
		if char:GetAttribute("IsTelekineticFlying") == true then
			return
		end
		if char:GetAttribute("IsTelekinesisActive") == true or char:GetAttribute("IsTelepathicSenseActive") == true then
			return
		end
		if AbilityCooldownHelper.isOnCooldown(char, ABILITY_ID) then
			return
		end

		local alpha = math.clamp(chargeAlpha, 0, 1)
		local cost = getOutburstCost(alpha)
		if not ResourceService.trySpend(char, cost) then
			return
		end

		AbilityCooldownHelper.apply(char, ABILITY_ID, COOLDOWN_SEC)
		task.spawn(function()
			runWave(plr, char, alpha)
		end)
	end)
end

function TelepathicOutburstService.onPlayerRemoving(_plr: Player) end

return TelepathicOutburstService
