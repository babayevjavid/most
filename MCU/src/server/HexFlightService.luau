--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AbilityCooldownHelper = require(ReplicatedStorage.Shared.AbilityCooldownHelper)
local CharacterRegistry = require(ReplicatedStorage.Shared.CharacterRegistry)
local CombatHelper = require(ReplicatedStorage.Shared.CombatHelper)
local ConstraintHelper = require(ReplicatedStorage.Shared.ConstraintHelper)
local GameConstants = require(ReplicatedStorage.Shared.GameConstants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local CharacterService = require(script.Parent.CharacterService)
local HandParticleHelper = require(script.Parent.HandParticleHelper)

local HexFlightService = {}

type FlightState = {
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	mover: ConstraintHelper.MoverBundle,
	moveDir: Vector3,
	lookDir: Vector3,
	currentVel: Vector3,
	sideInput: number,
	healthConn: RBXScriptConnection?,
}

type HeroFxHooks = {
	begin: (character: Model) -> (),
	finish: (character: Model) -> (),
}

local flightByPlayer: { [Player]: FlightState } = {}
local heroFxHooks: { [string]: HeroFxHooks } = {}

function HexFlightService.registerHeroFx(heroId: string, hooks: HeroFxHooks)
	heroFxHooks[heroId] = hooks
end

local function flightAbilityIdFor(heroId: any): string?
	if heroId == "jean_grey" then
		return "telekinetic_flight"
	elseif heroId == "scarlet_witch" then
		return "hex_flight"
	elseif heroId == "invisible_woman" then
		return "forcefield_flight"
	end
	return nil
end

local function runHeroFx(character: Model, which: "begin" | "finish")
	local heroId = character:GetAttribute(GameConstants.HERO_ATTRIBUTE)
	if type(heroId) ~= "string" then
		return
	end
	local hooks = heroFxHooks[heroId]
	if not hooks then
		return
	end
	local fn = if which == "begin" then hooks.begin else hooks.finish
	pcall(fn, character)
end

local function normalize(v: Vector3): Vector3
	if v.Magnitude < 0.01 then
		return Vector3.new(0, 0, -1)
	end
	return v.Unit
end

local function powersBlocked(character: Model): boolean
	return CombatHelper.arePowersDisabled(character)
		or character:GetAttribute(GameConstants.SHIELD_ACTIVE_ATTRIBUTE) == true
		or character:GetAttribute(GameConstants.BUSY_ATTRIBUTE) == true
end

local function getBank(direction: Vector3, velocity: Vector3): number
	if direction.Magnitude < 0.01 or velocity.Magnitude < 2 then
		return 0
	end
	local lookVec = (CFrame.new(Vector3.zero, direction) * CFrame.Angles(0, math.rad(90), 0)).LookVector
	local dot = lookVec:Dot(velocity.Unit)
	local len = lookVec.Magnitude * velocity.Magnitude
	if len < 0.0001 then
		return 0
	end
	return math.clamp(90 - math.deg(math.acos(math.clamp(dot / len, -1, 1))), -90, 90)
end

function HexFlightService.isFlying(player: Player): boolean
	return flightByPlayer[player] ~= nil
end

function HexFlightService.endFlight(player: Player, applyCooldown: boolean?)
	local state = flightByPlayer[player]
	flightByPlayer[player] = nil

	local function clearFlightAttrs(char: Model?)
		if not char then
			return
		end
		char:SetAttribute(GameConstants.IS_FLYING_ATTRIBUTE, nil)
		char:SetAttribute(GameConstants.FLIGHT_ALPHA_ATTRIBUTE, nil)
		char:SetAttribute(GameConstants.FLIGHT_BANK_ATTRIBUTE, nil)
		char:SetAttribute(GameConstants.FLIGHT_SIDE_ATTRIBUTE, nil)
		char:SetAttribute("BarrageSpinActive", nil)
		char:SetAttribute("BarrageSpinYaw", nil)
	end

	local function stripFlightConstraints(root: BasePart?)
		if not root or not root.Parent then
			return
		end
		for _, name in { "HeroLinearVelocity", "HeroGravityCancel", "HeroAlignOrientation" } do
			local inst = root:FindFirstChild(name)
			if inst then
				inst:Destroy()
			end
		end
	end

	-- Always clear attrs on current body (reset / morph race)
	clearFlightAttrs(player.Character)

	if not state then
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		stripFlightConstraints(root)
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum and hum:GetAttribute("HeroAbilityLocked") == true then
			ConstraintHelper.unlockHumanoid(hum)
		end
		return
	end

	if state.healthConn then
		state.healthConn:Disconnect()
		state.healthConn = nil
	end

	local char = state.character
	local exitVel = state.currentVel
	local isDead = state.humanoid ~= nil and state.humanoid.Health <= 0
	clearFlightAttrs(char)

	pcall(function()
		ConstraintHelper.destroyMover(state.mover)
	end)
	stripFlightConstraints(state.root)
	if state.humanoid and state.humanoid.Parent then
		ConstraintHelper.unlockHumanoid(state.humanoid)
	end
	if state.root and state.root.Parent then
		state.root.AssemblyLinearVelocity = if isDead then Vector3.zero else exitVel
		state.root.AssemblyAngularVelocity = Vector3.zero
	end
	if isDead and state.humanoid and state.humanoid.Parent then
		state.humanoid.PlatformStand = false
		state.humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, true)
		pcall(function()
			state.humanoid:ChangeState(Enum.HumanoidStateType.Dead)
		end)
	end

	if char and char.Parent then
		HandParticleHelper.setFlightTrails(char, false)
		runHeroFx(char, "finish")
	end

	if applyCooldown and char and char.Parent then
		local heroId = char:GetAttribute(GameConstants.HERO_ATTRIBUTE)
		local flightId = flightAbilityIdFor(heroId) or "hex_flight"
		local entry = CharacterRegistry.getAbilityById(if type(heroId) == "string" then heroId else "scarlet_witch", flightId)
		if entry then
			AbilityCooldownHelper.applyAfterUse(char, entry.id, entry.cooldown)
		end
	end
end

function HexFlightService.startFlight(player: Player): boolean
	if flightByPlayer[player] then
		return false
	end
	local character = player.Character
	if not character then
		return false
	end
	local heroId = character:GetAttribute(GameConstants.HERO_ATTRIBUTE)
	local flightAbilityId = flightAbilityIdFor(heroId)
	if not flightAbilityId then
		return false
	end
	if powersBlocked(character) then
		return false
	end
	if heroId == "invisible_woman" then
		if character:GetAttribute(GameConstants.IW_HYPERSPACE_LOCK_ATTRIBUTE) == true then
			return false
		end
		local hs = character:GetAttribute(GameConstants.IW_HYPERSPACE_ATTRIBUTE)
		local maxHs = character:GetAttribute(GameConstants.IW_HYPERSPACE_MAX_ATTRIBUTE)
		if type(maxHs) ~= "number" or maxHs <= 0 then
			maxHs = GameConstants.IW_HYPERSPACE_MAX
		end
		if type(hs) == "number" and hs >= maxHs then
			return false
		end
	end

	local entry = CharacterRegistry.getAbilityById(heroId :: string, flightAbilityId)
	if not entry then
		return false
	end
	if AbilityCooldownHelper.isOnCooldown(character, entry.id) then
		return false
	end

	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return false
	end

	ConstraintHelper.lockHumanoidForAbility(humanoid)
	local mover = ConstraintHelper.createMover(root, true, true)

	flightByPlayer[player] = {
		character = character,
		humanoid = humanoid,
		root = root,
		mover = mover,
		moveDir = Vector3.zero,
		lookDir = root.CFrame.LookVector,
		currentVel = Vector3.zero,
		sideInput = 0,
		healthConn = humanoid.HealthChanged:Connect(function(hp)
			if hp > 0 then
				return
			end
			HexFlightService.endFlight(player, false)
			if humanoid.Parent and humanoid.Health <= 0 then
				humanoid.PlatformStand = false
				humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, true)
				pcall(function()
					humanoid:ChangeState(Enum.HumanoidStateType.Dead)
				end)
			end
		end),
	}

	character:SetAttribute(GameConstants.IS_FLYING_ATTRIBUTE, true)
	character:SetAttribute(GameConstants.FLIGHT_ALPHA_ATTRIBUTE, 0)
	character:SetAttribute(GameConstants.FLIGHT_BANK_ATTRIBUTE, 0)
	character:SetAttribute(GameConstants.FLIGHT_SIDE_ATTRIBUTE, 0)
	if heroId == "scarlet_witch" then
		HandParticleHelper.setFlightTrails(character, true)
	end
	runHeroFx(character, "begin")
	return true
end

function HexFlightService.toggleFlight(player: Player)
	if flightByPlayer[player] then
		HexFlightService.endFlight(player, true)
	else
		HexFlightService.startFlight(player)
	end
end

function HexFlightService.setInput(
	player: Player,
	moveDir: Vector3,
	lookDir: Vector3,
	sideInput: number?
)
	local state = flightByPlayer[player]
	if not state then
		return
	end
	state.moveDir = moveDir
	state.lookDir = lookDir
	state.sideInput = sideInput or 0
end

function HexFlightService.update(dt: number)
	local dtClamped = math.clamp(dt, 0.001, 0.1)
	local velLerpMove = 1 - (1 - GameConstants.FLIGHT_VEL_LERP_MOVE) ^ (dtClamped * 60)
	local velLerpDecay = 1 - (1 - GameConstants.FLIGHT_VEL_LERP_DECAY) ^ (dtClamped * 60)

	for player, state in flightByPlayer do
		local char = state.character
		-- Stale body after reset / morph: current Character is no longer the flying one
		if player.Character ~= char or not char.Parent or not state.humanoid.Parent or not state.root.Parent then
			HexFlightService.endFlight(player, false)
			continue
		end
		if state.humanoid.Health <= 0 then
			HexFlightService.endFlight(player, false)
			continue
		end

		local energy = char:GetAttribute(GameConstants.ENERGY_ATTRIBUTE)
		if type(energy) ~= "number" or energy <= 0 then
			HexFlightService.endFlight(player, true)
			continue
		end
		local heroId = char:GetAttribute(GameConstants.HERO_ATTRIBUTE)
		local drainRate = GameConstants.FLIGHT_ENERGY_PER_SEC
		if heroId == "invisible_woman" then
			drainRate = GameConstants.IW_FLIGHT_ENERGY_PER_SEC
			if char:GetAttribute(GameConstants.LOOK_MODE_ATTRIBUTE) == "modern" then
				drainRate *= 0.75
			end
		end
		char:SetAttribute(
			GameConstants.ENERGY_ATTRIBUTE,
			math.max(0, energy - drainRate * dtClamped)
		)
		CharacterService.markAbilityUse(char)

		if AbilityCooldownHelper.isActive(char, "forcefield_crush") then
			state.moveDir = Vector3.zero
			state.currentVel = Vector3.zero
			state.mover.linearVelocity.VectorVelocity = Vector3.zero
			if state.mover.vectorForce then
				state.mover.vectorForce.Force = Vector3.new(0, state.root.AssemblyMass * workspace.Gravity, 0)
			end
			char:SetAttribute(GameConstants.FLIGHT_ALPHA_ATTRIBUTE, 0)
			continue
		end

		local moveMag = state.moveDir.Magnitude
		local direction = if moveMag > 0.01 then state.moveDir.Unit else normalize(state.lookDir)
		local speed = GameConstants.FLIGHT_SPEED

		local sideLean = math.clamp(state.sideInput, -1, 1)

		local targetVel = if moveMag > 0.01 then direction * speed else Vector3.zero
		local lerpAlpha = if moveMag > 0.01 then velLerpMove else velLerpDecay
		state.currentVel = state.currentVel:Lerp(targetVel, lerpAlpha)
		state.mover.linearVelocity.VectorVelocity = state.currentVel
		if state.mover.vectorForce then
			state.mover.vectorForce.Force = Vector3.new(0, state.root.AssemblyMass * workspace.Gravity, 0)
		end

		local velMag = state.currentVel.Magnitude
		local alphaSpeed = if speed > 0 then velMag / speed else 0
		local leanStrength = math.clamp(alphaSpeed, 0, 1)
		local facingDir = if moveMag > 0.01 then direction else normalize(state.lookDir)
		local bank = 0
		local sideYaw = 0
		local pitchAlpha = 0
		local pitchMax = GameConstants.FLIGHT_PITCH_MAX
		if heroId == "scarlet_witch" then
			pitchMax = GameConstants.SW_FLIGHT_PITCH_MAX
		elseif heroId == "jean_grey" then
			pitchMax = GameConstants.MG_FLIGHT_PITCH_MAX
		elseif heroId == "invisible_woman" then
			local modern = char:GetAttribute(GameConstants.LOOK_MODE_ATTRIBUTE) == "modern"
			pitchMax = if modern then GameConstants.IW_FLIGHT_PITCH_MAX_MODERN else GameConstants.IW_FLIGHT_PITCH_MAX
		end
		if moveMag > 0.01 and velMag > 2 then
			bank = getBank(direction, state.currentVel) * leanStrength * GameConstants.FLIGHT_BANK_SCALE
			bank += sideLean * GameConstants.FLIGHT_BANK_MAX * GameConstants.FLIGHT_SIDE_YIELD * leanStrength
			sideYaw = sideLean * GameConstants.FLIGHT_SIDE_YAW * leanStrength
			pitchAlpha = math.min(1, alphaSpeed) * 1.15
		end
		bank = math.clamp(bank, -GameConstants.FLIGHT_BANK_MAX, GameConstants.FLIGHT_BANK_MAX)
		sideYaw = math.clamp(sideYaw, -GameConstants.FLIGHT_SIDE_YAW, GameConstants.FLIGHT_SIDE_YAW)

		local spinActive = char:GetAttribute("BarrageSpinActive") == true
		local absorbActive = char:GetAttribute("AbsorbActive") == true
		if state.mover.alignOrientation and not spinActive and not absorbActive then
			local baseCf = CFrame.lookAt(state.root.Position, state.root.Position + facingDir)
			-- X pitch, Y yaw (turn), Z roll (shoulders)
			local targetCf = baseCf
				* CFrame.Angles(
					math.rad(-pitchAlpha * pitchMax),
					math.rad(sideYaw),
					math.rad(-bank)
				)
			local rotAlpha = 1 - (1 - GameConstants.FLIGHT_ROTATION_LERP) ^ (dtClamped * 60)
			state.mover.alignOrientation.CFrame = state.mover.alignOrientation.CFrame:Lerp(targetCf, rotAlpha)
		end

		char:SetAttribute(GameConstants.FLIGHT_ALPHA_ATTRIBUTE, math.clamp(alphaSpeed, 0, 1))
		char:SetAttribute(GameConstants.FLIGHT_BANK_ATTRIBUTE, bank)
		char:SetAttribute(GameConstants.FLIGHT_SIDE_ATTRIBUTE, sideLean)
	end
end

function HexFlightService.init()
	Remotes.getEvent("FlightInput").OnServerEvent:Connect(function(player: Player, payload: any)
		if type(payload) ~= "table" then
			return
		end
		if payload.dead == true then
			HexFlightService.endFlight(player, false)
			local char = player.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.PlatformStand = false
				hum:SetStateEnabled(Enum.HumanoidStateType.Dead, true)
				if hum.Health <= 0 then
					pcall(function()
						hum:ChangeState(Enum.HumanoidStateType.Dead)
					end)
				end
			end
			return
		end
		local move = if typeof(payload.moveVector) == "Vector3" then payload.moveVector else Vector3.zero
		local look = if typeof(payload.lookVector) == "Vector3" then payload.lookVector else Vector3.new(0, 0, -1)
		local side = if type(payload.sideInput) == "number" then payload.sideInput else 0
		HexFlightService.setInput(player, move, look, side)
	end)

	local function hookPlayer(player: Player)
		player.CharacterRemoving:Connect(function(character)
			HexFlightService.endFlight(player, false)
			if character then
				character:SetAttribute(GameConstants.IS_FLYING_ATTRIBUTE, nil)
				character:SetAttribute(GameConstants.FLIGHT_ALPHA_ATTRIBUTE, nil)
				character:SetAttribute(GameConstants.FLIGHT_BANK_ATTRIBUTE, nil)
				character:SetAttribute(GameConstants.FLIGHT_SIDE_ATTRIBUTE, nil)
				character:SetAttribute("BarrageSpinActive", nil)
				character:SetAttribute("BarrageSpinYaw", nil)
				local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root then
					for _, name in { "HeroLinearVelocity", "HeroGravityCancel", "HeroAlignOrientation", "HeroMoverAttachment" } do
						local inst = root:FindFirstChild(name)
						if inst then
							inst:Destroy()
						end
					end
				end
			end
		end)
		player.CharacterAdded:Connect(function(character)
			HexFlightService.endFlight(player, false)
			local humanoid = character:WaitForChild("Humanoid", 8)
			if humanoid and humanoid:IsA("Humanoid") then
				humanoid.Died:Connect(function()
					HexFlightService.endFlight(player, false)
					-- Unlock then ragdoll so death isn't stuck in flight pose
					if humanoid.Parent then
						if humanoid:GetAttribute("HeroAbilityLocked") == true then
							ConstraintHelper.unlockHumanoid(humanoid)
						end
						local RagdollService = require(script.Parent.RagdollService)
						RagdollService.apply(character)
					end
				end)
			end
			task.defer(function()
				HexFlightService.endFlight(player, false)
				local hum = character:FindFirstChildOfClass("Humanoid")
				if hum and hum:GetAttribute("HeroAbilityLocked") == true then
					ConstraintHelper.unlockHumanoid(hum)
				end
				local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root then
					for _, name in { "HeroLinearVelocity", "HeroGravityCancel", "HeroAlignOrientation", "HeroMoverAttachment" } do
						local inst = root:FindFirstChild(name)
						if inst then
							inst:Destroy()
						end
					end
				end
				-- Clear stale flying attrs if somehow still set
				if character.Parent then
					character:SetAttribute(GameConstants.IS_FLYING_ATTRIBUTE, nil)
					character:SetAttribute(GameConstants.FLIGHT_ALPHA_ATTRIBUTE, nil)
					character:SetAttribute(GameConstants.FLIGHT_BANK_ATTRIBUTE, nil)
					character:SetAttribute(GameConstants.FLIGHT_SIDE_ATTRIBUTE, nil)
				end
			end)
		end)
	end
	for _, player in Players:GetPlayers() do
		hookPlayer(player)
	end
	Players.PlayerAdded:Connect(hookPlayer)

	Players.PlayerRemoving:Connect(function(player)
		HexFlightService.endFlight(player, false)
	end)
end

return HexFlightService
