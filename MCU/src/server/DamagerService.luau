--!strict
--[[
	Workspace part named "Damager" damages humanoids standing on / overlapping it.
	Optional attributes on the part:
	  DamagePerSecond / DPS (number) — default 25
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatHelper = require(ReplicatedStorage.Shared.CombatHelper)

local DamagerService = {}

local DEFAULT_DPS = 25
local damagers: { [BasePart]: boolean } = {}
local damageAcc: { [Model]: number } = {}

local function getDps(part: BasePart): number
	local a = part:GetAttribute("DamagePerSecond")
	if type(a) ~= "number" then
		a = part:GetAttribute("DPS")
	end
	if type(a) == "number" and a > 0 then
		return a
	end
	return DEFAULT_DPS
end

local function register(inst: Instance)
	if inst:IsA("BasePart") and inst.Name == "Damager" then
		damagers[inst] = true
	end
end

local function unregister(inst: Instance)
	if inst:IsA("BasePart") then
		damagers[inst] = nil
	end
end

function DamagerService.update(dt: number)
	local dtClamped = math.clamp(dt, 0, 0.2)
	local hitThisFrame: { [Model]: number } = {}

	for part in damagers do
		if not part.Parent then
			damagers[part] = nil
			continue
		end
		local dps = getDps(part)
		local params = OverlapParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { part }
		-- Expand slightly upward so standing on the top surface still counts
		local boxCf = part.CFrame * CFrame.new(0, part.Size.Y * 0.35, 0)
		local boxSize = part.Size + Vector3.new(1.5, 4, 1.5)
		local overlapping = Workspace:GetPartBoundsInBox(boxCf, boxSize, params)
		local seen: { [Model]: boolean } = {}
		for _, other in overlapping do
			local model = CombatHelper.getCharacterFromPart(other)
			if model and not seen[model] then
				seen[model] = true
				hitThisFrame[model] = math.max(hitThisFrame[model] or 0, dps)
			end
		end
	end

	for model, dps in hitThisFrame do
		local humanoid = CombatHelper.getHumanoid(model)
		if not humanoid or humanoid.Health <= 0 then
			continue
		end
		local acc = (damageAcc[model] or 0) + dps * dtClamped
		-- Apply in ~1 HP chunks so small DPS still ticks
		if acc >= 1 then
			local amount = math.floor(acc)
			acc -= amount
			humanoid:TakeDamage(amount)
			CombatHelper.markInCombat(model)
		end
		damageAcc[model] = acc
	end

	-- Clear accumulators for anyone who left the pad
	for model in damageAcc do
		if not hitThisFrame[model] then
			damageAcc[model] = nil
		end
	end
end

function DamagerService.init()
	for _, desc in Workspace:GetDescendants() do
		register(desc)
	end
	Workspace.DescendantAdded:Connect(register)
	Workspace.DescendantRemoving:Connect(unregister)

	-- Also watch top-level rename / late spawn
	Workspace.ChildAdded:Connect(register)
end

return DamagerService
