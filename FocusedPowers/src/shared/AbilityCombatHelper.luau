--!strict
--[[
	Shared combat: radius hits, raycast hits, damage+push, ragdoll.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InteractableHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("InteractableHelper"))
local PushHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PushHelper"))

export type CombatOpts = {
	damage: number,
	pushSpeed: number,
	pushUp: number?,
	impulseMult: number?,
	excludePlayer: Player?,
}

local AbilityCombatHelper = {}

function AbilityCombatHelper.applyRagdoll(target: Model, duration: number)
	target:SetAttribute("Ragdolled", true)
	task.delay(duration, function()
		if target.Parent then
			target:SetAttribute("Ragdolled", nil)
		end
	end)
end

function AbilityCombatHelper.damageAndPush(
	targetModel: Model,
	targetHum: Humanoid?,
	targetPart: BasePart,
	direction: Vector3,
	opts: CombatOpts
)
	local pushUp = opts.pushUp or 0
	local pushOpts = {
		speed = opts.pushSpeed,
		upBoost = pushUp,
		impulseMult = opts.impulseMult,
	}

	if targetHum and targetHum.Health > 0 and targetModel then
		targetHum:TakeDamage(opts.damage)
		PushHelper.applyToModel(targetModel, direction, pushOpts)
	elseif targetModel and InteractableHelper.modelIsInteractableProp(targetModel) then
		InteractableHelper.applyDamage(targetModel, opts.damage)
		PushHelper.applyToPart(targetPart, direction, pushOpts)
	elseif InteractableHelper.hasInteractableMark(targetPart) then
		InteractableHelper.applyDamage(targetPart, opts.damage)
		PushHelper.applyToPart(targetPart, direction, pushOpts)
	end
end

function AbilityCombatHelper.hitInRadius(
	origin: Vector3,
	radius: number,
	caster: Model,
	opts: CombatOpts,
	sharedHitOnce: { [Instance]: boolean }?
): number
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { caster }

	local hitOnce = sharedHitOnce or {}
	local hits = 0
	for _, part in workspace:GetPartBoundsInRadius(origin, radius, overlap) do
		local key: Instance = part
		if hitOnce[key] then
			continue
		end

		local model = part:FindFirstAncestorOfClass("Model")
		if model == caster then
			continue
		end

		if model then
			local hum = model:FindFirstChildOfClass("Humanoid")
			local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
			key = root or model
			if hitOnce[key] then
				continue
			end

			if hum and hum.Health > 0 then
				if opts.excludePlayer then
					local targetPlr = Players:GetPlayerFromCharacter(model)
					if targetPlr == opts.excludePlayer then
						continue
					end
				end
				hitOnce[key] = true
				local dir = if root then (root.Position - origin) else Vector3.new(0, 0, -1)
				AbilityCombatHelper.damageAndPush(model, hum, part, dir, opts)
				hits += 1
			elseif InteractableHelper.modelIsInteractableProp(model) then
				hitOnce[key] = true
				AbilityCombatHelper.damageAndPush(model, nil, part, Vector3.new(0, 0, -1), opts)
				hits += 1
			end
		elseif InteractableHelper.hasInteractableMark(part) then
			if hitOnce[part] then
				continue
			end
			hitOnce[part] = true
			InteractableHelper.applyDamage(part, opts.damage)
			PushHelper.applyToPart(part, Vector3.new(0, 0, -1), {
				speed = opts.pushSpeed,
				upBoost = opts.pushUp or 0,
			})
			hits += 1
		end
	end
	return hits
end

function AbilityCombatHelper.raycastHit(
	origin: Vector3,
	direction: Vector3,
	range: number,
	caster: Model,
	opts: CombatOpts
): boolean
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { caster }
	params.FilterType = Enum.RaycastFilterType.Exclude

	local hit = workspace:Raycast(origin, direction.Unit * range, params)
	if not hit then
		return false
	end

	local model = hit.Instance:FindFirstAncestorOfClass("Model")
	local hum = if model then model:FindFirstChildOfClass("Humanoid") else nil

	if hum and hum.Health > 0 and model then
		if opts.excludePlayer then
			local targetPlr = Players:GetPlayerFromCharacter(model)
			if targetPlr == opts.excludePlayer then
				return false
			end
		end
		AbilityCombatHelper.damageAndPush(model, hum, hit.Instance, direction, opts)
		return true
	end

	PushHelper.applyFromHit(hit.Instance, direction, {
		speed = opts.pushSpeed,
		upBoost = opts.pushUp or 0,
	}, caster)
	if model and InteractableHelper.modelIsInteractableProp(model) then
		InteractableHelper.applyDamage(model, opts.damage)
	elseif InteractableHelper.hasInteractableMark(hit.Instance) then
		InteractableHelper.applyDamage(hit.Instance, opts.damage)
	end
	return true
end

function AbilityCombatHelper.spherecastHit(
	origin: Vector3,
	direction: Vector3,
	range: number,
	radius: number,
	caster: Model,
	opts: CombatOpts
): number?
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { caster }
	params.FilterType = Enum.RaycastFilterType.Exclude

	local result = workspace:Spherecast(origin, radius, direction.Unit * range, params)
	if not result then
		return nil
	end

	local model = result.Instance:FindFirstAncestorOfClass("Model")
	local hum = if model then model:FindFirstChildOfClass("Humanoid") else nil

	if hum and hum.Health > 0 and model then
		if opts.excludePlayer then
			local targetPlr = Players:GetPlayerFromCharacter(model)
			if targetPlr == opts.excludePlayer then
				return result.Distance
			end
		end
		AbilityCombatHelper.damageAndPush(model, hum, result.Instance, direction, opts)
	elseif model and InteractableHelper.modelIsInteractableProp(model) then
		InteractableHelper.applyDamage(model, opts.damage)
		PushHelper.applyFromHit(result.Instance, direction, {
			speed = opts.pushSpeed,
			upBoost = opts.pushUp or 0,
		}, caster)
	elseif InteractableHelper.hasInteractableMark(result.Instance) then
		InteractableHelper.applyDamage(result.Instance, opts.damage)
		PushHelper.applyFromHit(result.Instance, direction, {
			speed = opts.pushSpeed,
			upBoost = opts.pushUp or 0,
		}, caster)
	end

	return result.Distance
end

function AbilityCombatHelper.hitInForwardBox(
	origin: Vector3,
	lookVector: Vector3,
	forwardDistance: number,
	width: number,
	height: number,
	caster: Model,
	opts: CombatOpts
): number
	local flatLook = Vector3.new(lookVector.X, 0, lookVector.Z)
	if flatLook.Magnitude < 0.01 then
		flatLook = Vector3.new(0, 0, -1)
	else
		flatLook = flatLook.Unit
	end

	local center = origin + flatLook * (forwardDistance * 0.5)
	local boxCFrame = CFrame.lookAt(center, center + flatLook)
	local boxSize = Vector3.new(width, height, forwardDistance)

	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { caster }

	local hits = 0
	local hitOnce: { [Instance]: boolean } = {}
	for _, part in workspace:GetPartBoundsInBox(boxCFrame, boxSize, overlap) do
		local key: Instance = part
		if hitOnce[key] then
			continue
		end

		local model = part:FindFirstAncestorOfClass("Model")
		if model == caster then
			continue
		end

		if model then
			local hum = model:FindFirstChildOfClass("Humanoid")
			local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
			key = root or model
			if hitOnce[key] then
				continue
			end

			if hum and hum.Health > 0 then
				if opts.excludePlayer then
					local targetPlr = Players:GetPlayerFromCharacter(model)
					if targetPlr == opts.excludePlayer then
						continue
					end
				end
				hitOnce[key] = true
				local dir = flatLook
				AbilityCombatHelper.damageAndPush(model, hum, part, dir, opts)
				hits += 1
			elseif InteractableHelper.modelIsInteractableProp(model) then
				hitOnce[key] = true
				AbilityCombatHelper.damageAndPush(model, nil, part, flatLook, opts)
				hits += 1
			end
		elseif InteractableHelper.hasInteractableMark(part) then
			hitOnce[part] = true
			InteractableHelper.applyDamage(part, opts.damage)
			PushHelper.applyToPart(part, flatLook, {
				speed = opts.pushSpeed,
				upBoost = opts.pushUp or 0,
			})
			hits += 1
		end
	end
	return hits
end

function AbilityCombatHelper.hitInDirectedBox(
	origin: Vector3,
	aimVector: Vector3,
	forwardDistance: number,
	width: number,
	height: number,
	caster: Model,
	opts: CombatOpts
): number
	local dir = if aimVector.Magnitude > 0.01 then aimVector.Unit else Vector3.new(0, 0, -1)
	local center = origin + dir * (forwardDistance * 0.5)
	local boxCFrame = CFrame.lookAt(center, center + dir)
	local boxSize = Vector3.new(width, height, forwardDistance)

	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { caster }

	local hits = 0
	local hitOnce: { [Instance]: boolean } = {}
	for _, part in workspace:GetPartBoundsInBox(boxCFrame, boxSize, overlap) do
		local key: Instance = part
		if hitOnce[key] then
			continue
		end

		local model = part:FindFirstAncestorOfClass("Model")
		if model == caster then
			continue
		end

		if model then
			local hum = model:FindFirstChildOfClass("Humanoid")
			local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
			key = root or model
			if hitOnce[key] then
				continue
			end

			if hum and hum.Health > 0 then
				if opts.excludePlayer then
					local targetPlr = Players:GetPlayerFromCharacter(model)
					if targetPlr == opts.excludePlayer then
						continue
					end
				end
				hitOnce[key] = true
				AbilityCombatHelper.damageAndPush(model, hum, part, dir, opts)
				hits += 1
			elseif InteractableHelper.modelIsInteractableProp(model) then
				hitOnce[key] = true
				AbilityCombatHelper.damageAndPush(model, nil, part, dir, opts)
				hits += 1
			end
		elseif InteractableHelper.hasInteractableMark(part) then
			hitOnce[part] = true
			InteractableHelper.applyDamage(part, opts.damage)
			PushHelper.applyToPart(part, dir, {
				speed = opts.pushSpeed,
				upBoost = opts.pushUp or 0,
			})
			hits += 1
		end
	end
	return hits
end

return AbilityCombatHelper
