--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AbilityConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityConstants"))
local HeroRegistry = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("HeroRegistry"))

local PlayerStateService = require(script.Parent.PlayerStateService)
local TelekinesisService = require(script.Parent.TelekinesisService)
local WandaHandParticlesService = require(script.Parent.WandaHandParticlesService)

local C = AbilityConstants
local SHIELD_PINK = Color3.fromRGB(255, 87, 224)

type ShieldState = {
	active: boolean,
	lastDrainTime: number?,
	originalWalkSpeed: number?,
	originalJumpPower: number?,
	shieldPart: BasePart?,
	healthConn: RBXScriptConnection?,
}

local ShieldService = {}
local stateByPlayer: { [Player]: ShieldState } = {}
local ignoreNextHealthChange: { [Model]: boolean } = {}
local lastHealth: { [Model]: number } = {}
local onStatUpdate: ((player: Player) -> ())? = nil
local onCooldown: ((player: Player, abilityId: string, duration: number) -> ())? = nil

local function getState(plr: Player): ShieldState
	if not stateByPlayer[plr] then
		stateByPlayer[plr] = {
			active = false,
			lastDrainTime = nil,
			originalWalkSpeed = nil,
			originalJumpPower = nil,
			shieldPart = nil,
			healthConn = nil,
		}
	end
	return stateByPlayer[plr]
end

local function canUseShield(plr: Player): boolean
	local state = PlayerStateService.get(plr)
	if not state.HeroId then
		return false
	end
	return HeroRegistry.heroOwnsAbility(state.HeroId, "ChaosShield")
end

local function destroyShieldVisual(st: ShieldState)
	if st.shieldPart and st.shieldPart.Parent then
		st.shieldPart:Destroy()
	end
	st.shieldPart = nil
end

local function createShieldVisual(char: Model, root: BasePart): BasePart
	local bubble = Instance.new("Part")
	bubble.Name = "ChaosShieldBubble"
	bubble.Shape = Enum.PartType.Ball
	bubble.Size = Vector3.new(7, 7, 7)
	bubble.Material = Enum.Material.ForceField
	bubble.Color = SHIELD_PINK
	bubble.Transparency = 0.55
	bubble.CanCollide = false
	bubble.CanQuery = false
	bubble.CanTouch = false
	bubble.Massless = true
	bubble.Anchored = false
	bubble.CFrame = root.CFrame
	bubble.Parent = char

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = bubble
	weld.Parent = bubble

	return bubble
end

local function bindHealthIntercept(char: Model, st: ShieldState)
	if st.healthConn then
		st.healthConn:Disconnect()
		st.healthConn = nil
	end

	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	lastHealth[char] = humanoid.Health

	st.healthConn = humanoid.HealthChanged:Connect(function(newHealth)
		if ignoreNextHealthChange[char] then
			ignoreNextHealthChange[char] = false
			lastHealth[char] = newHealth
			return
		end

		if char:GetAttribute("IsShieldActive") ~= true then
			lastHealth[char] = newHealth
			return
		end

		local shieldHp = char:GetAttribute("ShieldHP")
		if type(shieldHp) ~= "number" or shieldHp <= 0 then
			lastHealth[char] = newHealth
			return
		end

		local prevHealth = lastHealth[char] or humanoid.MaxHealth
		local damage = prevHealth - newHealth
		lastHealth[char] = newHealth
		if damage <= 0 then
			return
		end

		local absorbed = math.min(shieldHp, damage)
		local remaining = shieldHp - absorbed
		char:SetAttribute("ShieldHP", remaining)

		ignoreNextHealthChange[char] = true
		humanoid.Health = newHealth + absorbed
		lastHealth[char] = humanoid.Health

		if remaining <= 0 then
			local plr = game:GetService("Players"):GetPlayerFromCharacter(char)
			if plr then
				ShieldService.turnOff(plr)
			end
		end
	end)
end

function ShieldService.turnOff(plr: Player)
	local st = getState(plr)
	if not st.active then
		return
	end
	st.active = false
	st.lastDrainTime = nil

	local char = plr.Character
	if char then
		char:SetAttribute("IsShieldActive", nil)
		char:SetAttribute("ShieldHP", nil)

		local humanoid = char:FindFirstChildOfClass("Humanoid")
		if humanoid then
			if st.originalWalkSpeed ~= nil then
				humanoid.WalkSpeed = st.originalWalkSpeed
			end
			if st.originalJumpPower ~= nil then
				humanoid.JumpPower = st.originalJumpPower
			end
		end

		WandaHandParticlesService.disable(char)
	end

	destroyShieldVisual(st)
	if st.healthConn then
		st.healthConn:Disconnect()
		st.healthConn = nil
	end
end

local function turnOn(plr: Player): boolean
	if not canUseShield(plr) then
		return false
	end
	if PlayerStateService.isOnCooldown(plr, "ChaosShield") then
		return false
	end

	local char = plr.Character
	if not char or not char.Parent then
		return false
	end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root or humanoid.Health <= 0 then
		return false
	end

	local playerState = PlayerStateService.get(plr)
	if playerState.Energy < C.SHIELD_ENERGY_DRAIN then
		return false
	end

	TelekinesisService.cleanupPlayer(plr)

	local st = getState(plr)
	if st.active then
		return true
	end

	st.active = true
	st.lastDrainTime = os.clock()
	st.originalWalkSpeed = humanoid.WalkSpeed
	st.originalJumpPower = humanoid.JumpPower
	humanoid.WalkSpeed = C.SHIELD_WALK_SPEED
	humanoid.JumpPower = 0

	char:SetAttribute("IsShieldActive", true)
	char:SetAttribute("ShieldHP", C.CHAOS_SHIELD_HP)
	st.shieldPart = createShieldVisual(char, root)
	bindHealthIntercept(char, st)

	WandaHandParticlesService.enable(char)
	WandaHandParticlesService.emit(char)

	humanoid.Died:Once(function()
		ShieldService.turnOff(plr)
	end)

	return true
end

local function updateShieldDrain(now: number)
	for plr, st in stateByPlayer do
		if not st.active then
			continue
		end
		local char = plr.Character
		if not char or not char.Parent then
			ShieldService.turnOff(plr)
			continue
		end

		if typeof(st.lastDrainTime) ~= "number" then
			st.lastDrainTime = now
			continue
		end

		if now - st.lastDrainTime >= C.SHIELD_ENERGY_INTERVAL then
			st.lastDrainTime = now
			local state = PlayerStateService.get(plr)
			state.Energy = math.max(0, state.Energy - C.SHIELD_ENERGY_DRAIN)
			PlayerStateService.markResourceUsed(plr)
			if state.Energy <= 0 then
				ShieldService.turnOff(plr)
				PlayerStateService.setCooldown(plr, "ChaosShield", os.clock() + C.SHIELD_COOLDOWN)
				if onCooldown then
					onCooldown(plr, "ChaosShield", C.SHIELD_COOLDOWN)
				end
			end
			if onStatUpdate then
				onStatUpdate(plr)
			end
		end
	end
end

function ShieldService.setup(
	shieldSetActive: RemoteEvent,
	statUpdateCallback: (player: Player) -> (),
	cooldownCallback: (player: Player, abilityId: string, duration: number) -> ()
)
	onStatUpdate = statUpdateCallback
	onCooldown = cooldownCallback

	shieldSetActive.OnServerEvent:Connect(function(plr: Player, holding: boolean)
		if typeof(holding) ~= "boolean" then
			return
		end
		if holding then
			turnOn(plr)
		else
			if getState(plr).active then
				ShieldService.turnOff(plr)
				PlayerStateService.setCooldown(plr, "ChaosShield", os.clock() + C.SHIELD_COOLDOWN)
				if onCooldown then
					onCooldown(plr, "ChaosShield", C.SHIELD_COOLDOWN)
				end
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(0.25)
			updateShieldDrain(os.clock())
		end
	end)
end

function ShieldService.cleanupPlayer(player: Player)
	ShieldService.turnOff(player)
	stateByPlayer[player] = nil
end

return ShieldService
