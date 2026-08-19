--!strict
--[[
	Cloak abilities: Darkforce Step, Terror Veil, Shadow Cloak, Dark Binding.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AbilityCooldownHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityCooldownHelper"))
local AbilityVfxHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityVfxHelper"))
local DarkBindingConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DarkBindingConstants"))
local DarkforceStepConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DarkforceStepConstants"))
local ShadowCloakConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ShadowCloakConstants"))
local SmoothMotionHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SmoothMotionHelper"))
local TerrorVeilConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TerrorVeilConstants"))

local CloakAbilitiesService = {}

local bindingTasks: { [Model]: thread } = {}

local function isCloak(plr: Player): boolean
	return plr:GetAttribute("SelectedCharacter") == "Cloak"
end

local function getLookFlat(root: BasePart): Vector3
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.01 then
		return Vector3.new(0, 0, -1)
	end
	return flat.Unit
end

local function darkforceStep(plr: Player, char: Model, dir: Vector3)
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not root or not hum then
		return
	end

	local flat = Vector3.new(dir.X, 0, dir.Z)
	if flat.Magnitude < 0.01 then
		flat = getLookFlat(root)
	else
		flat = flat.Unit
	end
	local endPos = root.Position + flat * DarkforceStepConstants.RANGE

	char:SetAttribute("IsDarkforceDashing", true)
	local oldCollide = root.CanCollide
	root.CanCollide = false
	hum.PlatformStand = true

	AbilityVfxHelper.spawnExpandingSphere(root.Position, DarkforceStepConstants.COLOR, 1, 4, 0.2)
	SmoothMotionHelper.runSmoothTravel(root, root.Position, endPos, DarkforceStepConstants.DURATION, flat)
	AbilityVfxHelper.spawnExpandingSphere(root.Position, DarkforceStepConstants.COLOR, 1, 4, 0.2)

	root.CanCollide = oldCollide
	hum.PlatformStand = false
	char:SetAttribute("IsDarkforceDashing", nil)
end

local function terrorVeil(plr: Player, char: Model)
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local look = getLookFlat(root)
	local origin = root.Position

	for _, other in Players:GetPlayers() do
		if other == plr then
			continue
		end
		local target = other.Character
		if not target then
			continue
		end
		local tRoot = target:FindFirstChild("HumanoidRootPart") :: BasePart?
		local tHum = target:FindFirstChildOfClass("Humanoid")
		if not tRoot or not tHum or tHum.Health <= 0 then
			continue
		end
		local delta = tRoot.Position - origin
		if delta.Magnitude > TerrorVeilConstants.RANGE then
			continue
		end
		local dir = delta.Unit
		local dot = look:Dot(dir)
		local halfAngle = math.cos(math.rad(TerrorVeilConstants.CONE_ANGLE_DEG * 0.5))
		if dot >= halfAngle then
			target:SetAttribute("TerrorVeilSlow", TerrorVeilConstants.SLOW_MULT)
			tHum:TakeDamage(TerrorVeilConstants.DOT_DAMAGE)
			task.delay(TerrorVeilConstants.DURATION_SEC, function()
				if target.Parent then
					target:SetAttribute("TerrorVeilSlow", nil)
				end
			end)
		end
	end
end

local function shadowCloak(char: Model)
	char:SetAttribute("ShadowCloakShield", ShadowCloakConstants.SHIELD_AMOUNT)
	task.delay(ShadowCloakConstants.DURATION_SEC, function()
		if char.Parent and char:GetAttribute("ShadowCloakShield") == ShadowCloakConstants.SHIELD_AMOUNT then
			char:SetAttribute("ShadowCloakShield", nil)
		end
	end)
end

local function clearBinding(target: Model)
	local hum = target:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.PlatformStand = false
		hum.WalkSpeed = 16
	end
	target:SetAttribute("DarkBound", nil)
end

local function darkBinding(plr: Player, char: Model, targetUserId: number?)
	if typeof(targetUserId) ~= "number" then
		return
	end
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	for _, other in Players:GetPlayers() do
		if other.UserId ~= targetUserId or other == plr then
			continue
		end
		local target = other.Character
		if not target then
			return
		end
		local tRoot = target:FindFirstChild("HumanoidRootPart") :: BasePart?
		local tHum = target:FindFirstChildOfClass("Humanoid")
		if not tRoot or not tHum or tHum.Health <= 0 then
			return
		end
		if (tRoot.Position - root.Position).Magnitude > DarkBindingConstants.RANGE then
			return
		end

		local originalSpeed = tHum.WalkSpeed
		target:SetAttribute("DarkBound", true)
		tHum.PlatformStand = true
		tHum.WalkSpeed = 0
		tHum:TakeDamage(DarkBindingConstants.DOT_DAMAGE)

		if bindingTasks[target] then
			task.cancel(bindingTasks[target])
		end
		bindingTasks[target] = task.delay(DarkBindingConstants.ROOT_DURATION, function()
			bindingTasks[target] = nil
			if target.Parent then
				tHum.WalkSpeed = originalSpeed
				clearBinding(target)
			end
		end)
		return
	end
end

function CloakAbilitiesService.setup(stepRemote: RemoteEvent, veilRemote: RemoteEvent, cloakRemote: RemoteEvent, bindRemote: RemoteEvent)
	stepRemote.OnServerEvent:Connect(function(plr: Player, dx: number, dy: number, dz: number)
		if not isCloak(plr) then
			return
		end
		local char = plr.Character
		if not char or AbilityCooldownHelper.isOnCooldown(char, DarkforceStepConstants.ABILITY_ID) then
			return
		end
		AbilityCooldownHelper.apply(char, DarkforceStepConstants.ABILITY_ID, DarkforceStepConstants.COOLDOWN_SEC)
		task.spawn(function()
			darkforceStep(plr, char, Vector3.new(dx, dy, dz))
		end)
	end)

	veilRemote.OnServerEvent:Connect(function(plr: Player)
		if not isCloak(plr) then
			return
		end
		local char = plr.Character
		if not char or AbilityCooldownHelper.isOnCooldown(char, TerrorVeilConstants.ABILITY_ID) then
			return
		end
		AbilityCooldownHelper.apply(char, TerrorVeilConstants.ABILITY_ID, TerrorVeilConstants.COOLDOWN_SEC)
		terrorVeil(plr, char)
	end)

	cloakRemote.OnServerEvent:Connect(function(plr: Player)
		if not isCloak(plr) then
			return
		end
		local char = plr.Character
		if not char or AbilityCooldownHelper.isOnCooldown(char, ShadowCloakConstants.ABILITY_ID) then
			return
		end
		AbilityCooldownHelper.apply(char, ShadowCloakConstants.ABILITY_ID, ShadowCloakConstants.COOLDOWN_SEC)
		shadowCloak(char)
	end)

	bindRemote.OnServerEvent:Connect(function(plr: Player, targetUserId: unknown)
		if not isCloak(plr) then
			return
		end
		local char = plr.Character
		if not char or AbilityCooldownHelper.isOnCooldown(char, DarkBindingConstants.ABILITY_ID) then
			return
		end
		AbilityCooldownHelper.apply(char, DarkBindingConstants.ABILITY_ID, DarkBindingConstants.COOLDOWN_SEC)
		darkBinding(plr, char, if typeof(targetUserId) == "number" then targetUserId else nil)
	end)
end

function CloakAbilitiesService.onPlayerRemoving(_plr: Player) end

return CloakAbilitiesService
