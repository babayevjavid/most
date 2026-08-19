--!strict
--[[
	Dagger abilities: Light Knives, Holy Strike, Purifying Light, Blinding Flash.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AbilityCooldownHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityCooldownHelper"))
local AbilityVfxHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityVfxHelper"))
local BlindingFlashConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BlindingFlashConstants"))
local HolyStrikeConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("HolyStrikeConstants"))
local LightKnivesConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LightKnivesConstants"))
local PurifyingLightConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PurifyingLightConstants"))
local PushHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PushHelper"))
local SmoothMotionHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SmoothMotionHelper"))

local DaggerAbilitiesService = {}

local flashRemote: RemoteEvent? = nil

local function isDagger(plr: Player): boolean
	return plr:GetAttribute("SelectedCharacter") == "Dagger"
end

local function normalize(v: Vector3): Vector3
	if v.Magnitude < 0.01 then
		return Vector3.new(0, 0, -1)
	end
	return v.Unit
end

local function throwKnife(char: Model, direction: Vector3)
	local head = char:FindFirstChild("Head") :: BasePart? or char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not head then
		return
	end
	local part = Instance.new("Part")
	part.Size = Vector3.new(0.25, 0.25, 1.2)
	part.Material = Enum.Material.Neon
	part.Color = LightKnivesConstants.COLOR
	part.CanCollide = false
	part.Massless = true
	part.CFrame = CFrame.lookAt(head.Position, head.Position + direction)
	part.Parent = workspace
	part.AssemblyLinearVelocity = direction * LightKnivesConstants.BOLT_SPEED
	Debris:AddItem(part, LightKnivesConstants.BOLT_LIFETIME)

	part.Touched:Connect(function(hit)
		if not part.Parent then
			return
		end
		local model = hit:FindFirstAncestorOfClass("Model")
		if model == char then
			return
		end
		local hum = if model then model:FindFirstChildOfClass("Humanoid") else nil
		if hum and hum.Health > 0 then
			hum:TakeDamage(LightKnivesConstants.BOLT_DAMAGE)
		end
		part:Destroy()
	end)
end

local function holyStrike(plr: Player, char: Model, direction: Vector3)
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not root or not hum then
		return
	end
	local dir = normalize(Vector3.new(direction.X, 0, direction.Z))
	local endPos = root.Position + dir * HolyStrikeConstants.DASH_RANGE

	char:SetAttribute("IsHolyStriking", true)
	hum.PlatformStand = true
	SmoothMotionHelper.runSmoothTravel(root, root.Position, endPos, HolyStrikeConstants.DASH_DURATION, dir)
	hum.PlatformStand = false
	char:SetAttribute("IsHolyStriking", nil)

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
		if (tRoot.Position - root.Position).Magnitude <= 8 then
			tHum:TakeDamage(HolyStrikeConstants.DAMAGE)
			hum.Health = math.min(hum.MaxHealth, hum.Health + HolyStrikeConstants.HEAL_ON_HIT)
			PushHelper.applyToModel(target, dir, { speed = 35, upBoost = 6 })
			break
		end
	end
end

local function purifyingLight(plr: Player, char: Model)
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local origin = root.Position
	AbilityVfxHelper.spawnExpandingSphere(origin, PurifyingLightConstants.COLOR, 2, PurifyingLightConstants.RADIUS, 0.35)

	for _, other in Players:GetPlayers() do
		local target = other.Character
		if not target then
			continue
		end
		local tRoot = target:FindFirstChild("HumanoidRootPart") :: BasePart?
		local tHum = target:FindFirstChildOfClass("Humanoid")
		if not tRoot or not tHum then
			continue
		end
		if (tRoot.Position - origin).Magnitude > PurifyingLightConstants.RADIUS then
			continue
		end
		if other == plr then
			tHum.Health = math.min(tHum.MaxHealth, tHum.Health + PurifyingLightConstants.HEAL_ALLY)
		else
			if tHum.Health > 0 then
				tHum:TakeDamage(PurifyingLightConstants.DAMAGE_ENEMY)
			end
		end
	end
end

local function blindingFlash(plr: Player, char: Model)
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local origin = root.Position
	AbilityVfxHelper.spawnExpandingSphere(origin, Color3.new(1, 1, 1), 3, BlindingFlashConstants.RADIUS, 0.25)

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
		if (tRoot.Position - origin).Magnitude <= BlindingFlashConstants.RADIUS then
			target:SetAttribute("BlindingFlashSlow", BlindingFlashConstants.SLOW_MULT)
			if flashRemote then
				flashRemote:FireClient(other, BlindingFlashConstants.DURATION_SEC)
			end
			task.delay(BlindingFlashConstants.DURATION_SEC, function()
				if target.Parent then
					target:SetAttribute("BlindingFlashSlow", nil)
				end
			end)
		end
	end
end

function DaggerAbilitiesService.setup(
	knivesRemote: RemoteEvent,
	strikeRemote: RemoteEvent,
	purifyRemote: RemoteEvent,
	flashRemoteEvent: RemoteEvent
)
	flashRemote = flashRemoteEvent

	knivesRemote.OnServerEvent:Connect(function(plr: Player, dx: number, dy: number, dz: number)
		if not isDagger(plr) then
			return
		end
		local char = plr.Character
		if not char or AbilityCooldownHelper.isOnCooldown(char, LightKnivesConstants.ABILITY_ID) then
			return
		end
		AbilityCooldownHelper.apply(char, LightKnivesConstants.ABILITY_ID, LightKnivesConstants.COOLDOWN_SEC)
		throwKnife(char, normalize(Vector3.new(dx, dy, dz)))
	end)

	strikeRemote.OnServerEvent:Connect(function(plr: Player, dx: number, dy: number, dz: number)
		if not isDagger(plr) then
			return
		end
		local char = plr.Character
		if not char or AbilityCooldownHelper.isOnCooldown(char, HolyStrikeConstants.ABILITY_ID) then
			return
		end
		AbilityCooldownHelper.apply(char, HolyStrikeConstants.ABILITY_ID, HolyStrikeConstants.COOLDOWN_SEC)
		task.spawn(function()
			holyStrike(plr, char, Vector3.new(dx, dy, dz))
		end)
	end)

	purifyRemote.OnServerEvent:Connect(function(plr: Player)
		if not isDagger(plr) then
			return
		end
		local char = plr.Character
		if not char or AbilityCooldownHelper.isOnCooldown(char, PurifyingLightConstants.ABILITY_ID) then
			return
		end
		AbilityCooldownHelper.apply(char, PurifyingLightConstants.ABILITY_ID, PurifyingLightConstants.COOLDOWN_SEC)
		purifyingLight(plr, char)
	end)

	flashRemoteEvent.OnServerEvent:Connect(function(plr: Player)
		if not isDagger(plr) then
			return
		end
		local char = plr.Character
		if not char or AbilityCooldownHelper.isOnCooldown(char, BlindingFlashConstants.ABILITY_ID) then
			return
		end
		AbilityCooldownHelper.apply(char, BlindingFlashConstants.ABILITY_ID, BlindingFlashConstants.COOLDOWN_SEC)
		blindingFlash(plr, char)
	end)
end

function DaggerAbilitiesService.onPlayerRemoving(_plr: Player) end

return DaggerAbilitiesService
