--!strict

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AbilityConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityConstants"))
local HeroRegistry = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("HeroRegistry"))

local CombatService = require(script.Parent.CombatService)
local HexBlastProjectile = require(script.Parent.HexBlastProjectile)
local InteractionService = require(script.Parent.InteractionService)
local PlayerStateService = require(script.Parent.PlayerStateService)
local ProjectileFlight = require(script.Parent.ProjectileFlight)

local C = AbilityConstants
local CHAOS_COLOR = Color3.fromRGB(220, 60, 180)

local ProjectileService = {}

local function createProjectilePart(size: Vector3, color: Color3): BasePart
	local part = Instance.new("Part")
	part.Name = "ChaosProjectile"
	part.Size = size
	part.Shape = Enum.PartType.Ball
	part.Material = Enum.Material.Neon
	part.Color = color
	part.CanCollide = false
	part.CanQuery = true
	part.CanTouch = true
	part.Anchored = true
	part.CastShadow = false
	return part
end

local function damageHumanoid(attacker: Player, humanoid: Humanoid, baseDamage: number)
	local heroId = PlayerStateService.get(attacker).HeroId
	local damage = CombatService.computeDamage(attacker, heroId, baseDamage)
	humanoid:TakeDamage(damage)
end

local function tryDamageFromHit(attacker: Player, hitPart: BasePart?, casterChar: Model): boolean
	if not hitPart then
		return false
	end
	local hitModel = hitPart:FindFirstAncestorOfClass("Model")
	if not hitModel or hitModel == casterChar then
		return false
	end
	local humanoid = hitModel:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end
	return true
end

local function fireProjectile(
	player: Player,
	character: Model,
	direction: Vector3,
	opts: {
		damage: number,
		speed: number,
		range: number,
		size: Vector3,
		color: Color3,
		steerToken: string?,
	}
)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	local dir = if direction.Magnitude > 0.01 then direction.Unit else root.CFrame.LookVector
	local spawnPos = root.Position + dir * 2 + Vector3.new(0, 1, 0)
	local part = createProjectilePart(opts.size, opts.color)
	part.Parent = workspace

	if opts.steerToken then
		ProjectileFlight.registerSteerToken(opts.steerToken, player.UserId, spawnPos + dir * opts.range)
	end

	local hitTargets: { [Model]: boolean } = {}

	ProjectileFlight.runProjectileFlight({
		part = part,
		spawnPos = spawnPos,
		initialDir = dir,
		maxRange = opts.range,
		speed = opts.speed,
		casterChar = character,
		steerToken = opts.steerToken,
		excludeInstances = { character, part },
		onStepHit = function(_hitPos: Vector3, hitPart: BasePart?)
			if not hitPart then
				return false
			end
			if not tryDamageFromHit(player, hitPart, character) then
				return false
			end
			local hitModel = hitPart:FindFirstAncestorOfClass("Model")
			if not hitModel or hitTargets[hitModel] then
				return false
			end
			hitTargets[hitModel] = true
			local humanoid = hitModel:FindFirstChildOfClass("Humanoid")
			if humanoid then
				damageHumanoid(player, humanoid, opts.damage)
			end
			return true
		end,
		onEnd = function(_endPos: Vector3)
			if part.Parent then
				part:Destroy()
			end
		end,
	})
end

function ProjectileService.fireChaosBlast(player: Player, character: Model, direction: Vector3, steerToken: string?)
	HexBlastProjectile.fire(player, character, direction, steerToken, nil)
end

function ProjectileService.fireChaosBeam(player: Player, character: Model, direction: Vector3, steerToken: string?)
	fireProjectile(player, character, direction, {
		damage = C.CHAOS_BEAM_DAMAGE,
		speed = C.CHAOS_BEAM_SPEED,
		range = C.CHAOS_BEAM_RANGE,
		size = C.CHAOS_BEAM_SIZE,
		color = CHAOS_COLOR,
		steerToken = steerToken,
	})
end

function ProjectileService.parseSteerArgs(aimDirection: Vector3?, steerTokenArg: any): (Vector3?, string?)
	local steerToken: string? = if type(steerTokenArg) == "string" and #steerTokenArg > 0 then steerTokenArg else nil
	return aimDirection, steerToken
end

function ProjectileService.newSteerToken(): string
	return HttpService:GenerateGUID(false)
end

function ProjectileService.executeForcePush(player: Player, character: Model)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	local heroId = PlayerStateService.get(player).HeroId
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { character }

	local parts = workspace:GetPartBoundsInRadius(root.Position, C.FORCE_PUSH_RADIUS, overlap)
	local hitModels: { [Model]: boolean } = {}

	for _, part in parts do
		local model = part:FindFirstAncestorOfClass("Model")
		if not model or hitModels[model] then
			continue
		end
		hitModels[model] = true

		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			local pushDir = (model:GetPivot().Position - root.Position)
			if pushDir.Magnitude > 0.1 then
				pushDir = pushDir.Unit
			else
				pushDir = root.CFrame.LookVector
			end
			damageHumanoid(player, humanoid, C.FORCE_PUSH_DAMAGE)
			InteractionService.pushTarget(model, pushDir, "ForcePush", player)
		elseif part:IsA("BasePart") and part.Parent == workspace then
			local pushDir = (part.Position - root.Position)
			if pushDir.Magnitude > 0.1 then
				part:ApplyImpulse(pushDir.Unit * part.AssemblyMass * 80)
			end
		end
	end
end

function ProjectileService.heroUsesProjectile(heroId: string?, abilityId: string): boolean
	if not heroId then
		return false
	end
	if abilityId == "ChaosBlast" or abilityId == "ChaosBeam" then
		return HeroRegistry.heroOwnsAbility(heroId, abilityId)
	end
	return false
end

return ProjectileService
