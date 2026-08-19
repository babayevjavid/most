--!strict
--[[ Scarlet Witch abilities server ]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Debris = game:GetService("Debris")
local AbilityCombatHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityCombatHelper"))
local AbilityCooldownHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityCooldownHelper"))
local AbilityVfxHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityVfxHelper"))
local ScarletWitchConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ScarletWitchConstants"))
local SmoothMotionHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SmoothMotionHelper"))

local ResourceService = require(script.Parent:WaitForChild("ResourceService"))
local SteerableBoltService = require(script.Parent:WaitForChild("SteerableBoltService"))

local CHAR_ID = "ScarletWitch"
local C = ScarletWitchConstants
local COLOR = C.COLOR

local shieldTokens: { [Player]: number } = {}
local shieldHealthByPlayer: { [Player]: number } = {}

local ScarletWitchAbilitiesService = {}

local function isWitch(plr: Player): boolean
	return plr:GetAttribute("SelectedCharacter") == CHAR_ID
end

local function hexBoltConfig()
	local cfg = C.HexBolt
	return {
		abilityId = cfg.ABILITY_ID,
		boltName = "HexBolt",
		size = cfg.SIZE,
		color = COLOR,
		speed = cfg.SPEED,
		maxRange = cfg.RANGE,
		lifetime = cfg.LIFETIME,
		damage = cfg.DAMAGE,
		pushSpeed = cfg.PUSH_SPEED,
		pushUp = cfg.PUSH_UP,
		curveStrength = cfg.CURVE_STRENGTH,
		impactRadius = cfg.IMPACT_RADIUS,
		impactDuration = 0.3,
	}
end

local function onHexBoltHit(_plr: Player, hit: BasePart, caster: Model, direction: Vector3)
	local model = hit:FindFirstAncestorOfClass("Model")
	if not model or model == caster then
		return
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 then
		model:SetAttribute("HexSlow", true)
		task.delay(C.HexBolt.HEX_SLOW_DURATION, function()
			if model.Parent then
				model:SetAttribute("HexSlow", nil)
			end
		end)
		AbilityCombatHelper.damageAndPush(model, hum, hit, direction, {
			damage = C.HexBolt.DAMAGE,
			pushSpeed = C.HexBolt.PUSH_SPEED,
			pushUp = C.HexBolt.PUSH_UP,
		})
	end
end

local function startProbabilityShield(plr: Player, char: Model)
	if char:GetAttribute("ProbabilityShieldActive") == true then
		return
	end
	if not ResourceService.hasMinimum(char, CHAR_ID, C.ProbabilityShield.ABILITY_ID) then
		return
	end
	shieldTokens[plr] = (shieldTokens[plr] or 0) + 1
	local token = shieldTokens[plr]
	char:SetAttribute("ProbabilityShieldActive", true)
	char:SetAttribute("ProbabilityShieldHealth", C.ProbabilityShield.START_HP)
	shieldHealthByPlayer[plr] = C.ProbabilityShield.START_HP
	AbilityVfxHelper.spawnCharacterAura(char, COLOR, 4, 999)

	task.spawn(function()
		while shieldTokens[plr] == token and char.Parent and char:GetAttribute("ProbabilityShieldActive") == true do
			local hp = shieldHealthByPlayer[plr] or 0
			hp -= C.ProbabilityShield.DECAY_PER_SEC
			shieldHealthByPlayer[plr] = hp
			char:SetAttribute("ProbabilityShieldHealth", hp)
			if hp <= 0 then
				break
			end
			task.wait(1)
		end
		if shieldTokens[plr] == token and char.Parent and char:GetAttribute("ProbabilityShieldActive") == true then
			char:SetAttribute("ProbabilityShieldActive", nil)
			char:SetAttribute("ProbabilityShieldHealth", nil)
			shieldHealthByPlayer[plr] = nil
			AbilityCooldownHelper.apply(char, C.ProbabilityShield.ABILITY_ID, C.ProbabilityShield.COOLDOWN_SEC)
		end
	end)
end

local function endProbabilityShield(plr: Player, char: Model, applyCooldown: boolean)
	shieldTokens[plr] = (shieldTokens[plr] or 0) + 1
	char:SetAttribute("ProbabilityShieldActive", nil)
	char:SetAttribute("ProbabilityShieldHealth", nil)
	shieldHealthByPlayer[plr] = nil
	if applyCooldown then
		AbilityCooldownHelper.apply(char, C.ProbabilityShield.ABILITY_ID, C.ProbabilityShield.COOLDOWN_SEC)
	end
end

local function teleportCharacter(targetChar: Model, targetPos: Vector3)
	local root = targetChar:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		root.CFrame = CFrame.new(targetPos)
	end
end

local function doTeleportation(plr: Player, char: Model, px: number, py: number, pz: number, alpha: number)
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local target = Vector3.new(px, py, pz)
	local toTarget = target - root.Position
	if toTarget.Magnitude > C.Teleportation.SINGLE_RANGE then
		target = root.Position + toTarget.Unit * C.Teleportation.SINGLE_RANGE
	end

	local isAoE = alpha >= 0.65
	if isAoE then
		for _, other in Players:GetPlayers() do
			local otherChar = other.Character
			if otherChar and otherChar ~= char then
				local oRoot = otherChar:FindFirstChild("HumanoidRootPart") :: BasePart?
				if oRoot and (oRoot.Position - root.Position).Magnitude <= C.Teleportation.AOE_RADIUS then
					local randomOffset = Vector3.new(math.random(-4, 4), 0, math.random(-4, 4))
					teleportCharacter(otherChar, target + randomOffset)
				end
			end
		end
	end
	teleportCharacter(char, target)
	AbilityVfxHelper.spawnExpandingSphere(target, COLOR, 1.6, if isAoE then 8 else 5, 0.25)
end

local function realityWarp(plr: Player, char: Model, worldPos: Vector3)
	local cfg = C.RealityWarp
	AbilityVfxHelper.spawnExpandingSphere(worldPos, COLOR, 1.5, cfg.RADIUS, cfg.PULL_DURATION + 0.2)

	local pullStart = tick()
	while tick() - pullStart < cfg.PULL_DURATION do
		local overlap = OverlapParams.new()
		overlap.FilterType = Enum.RaycastFilterType.Exclude
		overlap.FilterDescendantsInstances = { char }
		for _, part in workspace:GetPartBoundsInRadius(worldPos, cfg.RADIUS, overlap) do
			local model = part:FindFirstAncestorOfClass("Model")
			if model then
				local hum = model:FindFirstChildOfClass("Humanoid")
				local tRoot = model:FindFirstChild("HumanoidRootPart") :: BasePart?
				if hum and hum.Health > 0 and tRoot then
					local targetPlr = Players:GetPlayerFromCharacter(model)
					if targetPlr ~= plr then
						local toCenter = (worldPos - tRoot.Position)
						if toCenter.Magnitude > 0.5 then
							tRoot.AssemblyLinearVelocity = toCenter.Unit * cfg.PULL_SPEED
						end
					end
				end
			end
		end
		RunService.Heartbeat:Wait()
	end

	AbilityVfxHelper.spawnExpandingSphere(worldPos, COLOR, 2, cfg.RADIUS * 1.2, 0.35)
	AbilityCombatHelper.hitInRadius(worldPos, cfg.RADIUS, char, {
		damage = cfg.DAMAGE,
		pushSpeed = cfg.PUSH_SPEED,
		pushUp = cfg.PUSH_UP,
		excludePlayer = plr,
	})
end

local function probabilityShield(plr: Player, char: Model, active: boolean)
	if active then
		startProbabilityShield(plr, char)
	else
		endProbabilityShield(plr, char, true)
	end
end

local function chaosWave(plr: Player, char: Model, alpha: number)
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local cfg = C.ChaosWave
	local origin = root.Position
	local maxR = cfg.MIN_RADIUS + (cfg.MAX_RADIUS - cfg.MIN_RADIUS) * alpha
	local damage = cfg.MIN_DAMAGE + (cfg.MAX_DAMAGE - cfg.MIN_DAMAGE) * alpha
	AbilityVfxHelper.spawnExpandingSphere(origin, COLOR, 2, maxR, cfg.WAVE_DURATION)
	local hitOnce: { [Instance]: boolean } = {}
	local start = tick()
	while tick() - start < cfg.WAVE_DURATION do
		local a = SmoothMotionHelper.smoothstep((tick() - start) / cfg.WAVE_DURATION)
		AbilityCombatHelper.hitInRadius(origin, maxR * a, char, {
			damage = damage,
			pushSpeed = cfg.PUSH_SPEED * (0.5 + alpha * 0.5),
			pushUp = cfg.PUSH_UP,
			excludePlayer = plr,
		}, hitOnce)
		RunService.Heartbeat:Wait()
	end
end

function ScarletWitchAbilitiesService.setup(
	teleportRemote: RemoteEvent,
	warpRemote: RemoteEvent,
	hexBoltStart: RemoteEvent,
	hexBoltAim: RemoteEvent,
	hexBoltRelease: RemoteEvent,
	shieldRemote: RemoteEvent,
	waveRemote: RemoteEvent
)
	ResourceService.registerStopCallback("ProbabilityShieldActive", function(p)
		local c = p.Character
		if c and c:GetAttribute("ProbabilityShieldActive") == true then
			endProbabilityShield(p, c, false)
		end
	end)

	teleportRemote.OnServerEvent:Connect(function(plr: Player, px: unknown, py: unknown, pz: unknown, alpha: unknown)
		if not isWitch(plr) then
			return
		end
		if typeof(px) ~= "number" or typeof(py) ~= "number" or typeof(pz) ~= "number" then
			return
		end
		local charge = if typeof(alpha) == "number" then math.clamp(alpha, 0, 1) else 0
		local char = plr.Character
		if not char then
			return
		end
		if AbilityCooldownHelper.isOnCooldown(char, C.Teleportation.ABILITY_ID) then
			return
		end
		local isAoE = charge >= 0.65
		local cost = if isAoE then 20 else 8
		if not ResourceService.trySpend(char, cost) then
			return
		end
		doTeleportation(plr, char, px, py, pz, charge)
		AbilityCooldownHelper.apply(
			char,
			C.Teleportation.ABILITY_ID,
			if isAoE then C.Teleportation.AOE_COOLDOWN_SEC else C.Teleportation.SINGLE_COOLDOWN_SEC
		)
	end)

	hexBoltStart.OnServerEvent:Connect(function(plr: Player, dx: unknown, dy: unknown, dz: unknown)
		if not isWitch(plr) then
			return
		end
		if typeof(dx) ~= "number" or typeof(dy) ~= "number" or typeof(dz) ~= "number" then
			return
		end
		local char = plr.Character
		if not char or AbilityCooldownHelper.isOnCooldown(char, C.HexBolt.ABILITY_ID) then
			return
		end
		if not ResourceService.trySpend(char, 18) then
			return
		end
		local states = SteerableBoltService.handleStartVolley(
			plr,
			C.HexBolt.ABILITY_ID,
			dx,
			dy,
			dz,
			hexBoltConfig(),
			onHexBoltHit,
			C.HexBolt.SHOT_COUNT,
			C.HexBolt.SPREAD_DEG
		)
		if #states > 0 then
			AbilityCooldownHelper.apply(char, C.HexBolt.ABILITY_ID, C.HexBolt.COOLDOWN_SEC)
		end
	end)

	hexBoltAim.OnServerEvent:Connect(function(plr: Player, dx: unknown, dy: unknown, dz: unknown)
		if not isWitch(plr) or typeof(dx) ~= "number" or typeof(dy) ~= "number" or typeof(dz) ~= "number" then
			return
		end
		SteerableBoltService.handleAim(plr, C.HexBolt.ABILITY_ID, dx, dy, dz)
	end)

	hexBoltRelease.OnServerEvent:Connect(function(plr: Player)
		if not isWitch(plr) then
			return
		end
		SteerableBoltService.handleRelease(plr, C.HexBolt.ABILITY_ID)
	end)

	warpRemote.OnServerEvent:Connect(function(plr, px, py, pz)
		if not isWitch(plr) or typeof(px) ~= "number" then
			return
		end
		local char = plr.Character
		if not char or AbilityCooldownHelper.isOnCooldown(char, C.RealityWarp.ABILITY_ID) then
			return
		end
		if not ResourceService.trySpend(char, 20) then
			return
		end
		AbilityCooldownHelper.apply(char, C.RealityWarp.ABILITY_ID, C.RealityWarp.COOLDOWN_SEC)
		task.spawn(function()
			realityWarp(plr, char, Vector3.new(px, py, pz))
		end)
	end)

	shieldRemote.OnServerEvent:Connect(function(plr, active: unknown)
		if not isWitch(plr) or typeof(active) ~= "boolean" then
			return
		end
		local char = plr.Character
		if not char then
			return
		end
		if active then
			if AbilityCooldownHelper.isOnCooldown(char, C.ProbabilityShield.ABILITY_ID) then
				return
			end
		end
		probabilityShield(plr, char, active)
	end)

	waveRemote.OnServerEvent:Connect(function(plr, alpha: unknown)
		if not isWitch(plr) or typeof(alpha) ~= "number" then
			return
		end
		local char = plr.Character
		if not char or AbilityCooldownHelper.isOnCooldown(char, C.ChaosWave.ABILITY_ID) then
			return
		end
		local a = math.clamp(alpha, 0, 1)
		local cost = ResourceService.getScaledCost(CHAR_ID, C.ChaosWave.ABILITY_ID, a) or 10
		if not ResourceService.trySpend(char, cost) then
			return
		end
		AbilityCooldownHelper.apply(char, C.ChaosWave.ABILITY_ID, C.ChaosWave.COOLDOWN_SEC)
		task.spawn(function()
			chaosWave(plr, char, a)
		end)
	end)
end

function ScarletWitchAbilitiesService.onPlayerRemoving(plr: Player)
	shieldTokens[plr] = nil
	shieldHealthByPlayer[plr] = nil
	local char = plr.Character
	if char and char:GetAttribute("ProbabilityShieldActive") == true then
		char:SetAttribute("ProbabilityShieldActive", nil)
		char:SetAttribute("ProbabilityShieldHealth", nil)
	end
end

return ScarletWitchAbilitiesService
