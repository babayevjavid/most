--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AbilityCooldownHelper = require(ReplicatedStorage.Shared.AbilityCooldownHelper)
local CharacterRegistry = require(ReplicatedStorage.Shared.CharacterRegistry)
local CombatHelper = require(ReplicatedStorage.Shared.CombatHelper)
local ConstraintHelper = require(ReplicatedStorage.Shared.ConstraintHelper)
local GameConstants = require(ReplicatedStorage.Shared.GameConstants)
local PushHelper = require(ReplicatedStorage.Shared.PushHelper)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local CharacterService = require(script.Parent.CharacterService)
local PhotonParticleHelper = require(script.Parent.PhotonParticleHelper)
local RagdollService = require(script.Parent.RagdollService)

local PhotonFlightService = {}

type FlightState = {
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	mover: ConstraintHelper.MoverBundle,
	moveDir: Vector3,
	lookDir: Vector3,
	currentVel: Vector3,
	sideInput: number,
	knockHits: { [Model]: number },
	diveTarget: Vector3?,
}

local flightByPlayer: { [Player]: FlightState } = {}

local function normalize(v: Vector3): Vector3
	if v.Magnitude < 0.01 then
		return Vector3.new(0, 0, -1)
	end
	return v.Unit
end

local function powersBlocked(character: Model): boolean
	return CombatHelper.arePowersDisabled(character)
		or character:GetAttribute(GameConstants.BUSY_ATTRIBUTE) == true
end

local function getFlightMode(character: Model): string
	local mode = character:GetAttribute(GameConstants.PHOTON_FLIGHT_MODE_ATTRIBUTE)
	if mode == "Accelerated" then
		return "Accelerated"
	end
	return "Normal"
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

local function applyAcceleratedKnock(state: FlightState, now: number)
	local char = state.character
	local speed = state.currentVel.Magnitude
	if speed < 18 then
		return
	end

	local origin = state.root.Position
	local victims = CombatHelper.overlapCharacters(origin, GameConstants.PHOTON_FLIGHT_KNOCK_RADIUS, char)
	local pushDir = if speed > 0.01 then state.currentVel.Unit else normalize(state.lookDir)

	for _, victim in victims do
		if victim == char then
			continue
		end
		local lastHit = state.knockHits[victim]
		if type(lastHit) == "number" and (now - lastHit) < GameConstants.PHOTON_FLIGHT_KNOCK_HIT_COOLDOWN then
			continue
		end
		state.knockHits[victim] = now
		CombatHelper.dealDamage(char, victim, GameConstants.PHOTON_FLIGHT_KNOCK_DAMAGE)
		PushHelper.applyToCharacter(victim, pushDir, {
			speed = GameConstants.PHOTON_FLIGHT_KNOCK_PUSH_SPEED,
			upBoost = GameConstants.PHOTON_FLIGHT_KNOCK_PUSH_UP,
		})
		RagdollService.applyTimed(victim, GameConstants.PHOTON_FLIGHT_KNOCK_RAGDOLL)
	end
end

function PhotonFlightService.isFlying(player: Player): boolean
	return flightByPlayer[player] ~= nil
end

function PhotonFlightService.setDiveTarget(player: Player, target: Vector3?)
	local state = flightByPlayer[player]
	if not state then
		return
	end
	state.diveTarget = target
end

function PhotonFlightService.clearDive(player: Player)
	local state = flightByPlayer[player]
	if state then
		state.diveTarget = nil
	end
end

function PhotonFlightService.getPosition(player: Player): Vector3?
	local state = flightByPlayer[player]
	if not state or not state.root.Parent then
		return nil
	end
	return state.root.Position
end

function PhotonFlightService.endFlight(player: Player, applyCooldown: boolean?)
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

	if char and char.Parent then
		PhotonParticleHelper.endUse(char)
		PhotonParticleHelper.setFlightTrails(char, false)
	end

	if applyCooldown and char and char.Parent then
		local entry = CharacterRegistry.getAbilityById("captain_marvel", "photon_flight")
		if entry then
			AbilityCooldownHelper.applyAfterUse(char, entry.id, entry.cooldown)
		end
	end
end

function PhotonFlightService.startFlight(player: Player): boolean
	if flightByPlayer[player] then
		return false
	end
	local character = player.Character
	if not character then
		return false
	end
	if character:GetAttribute(GameConstants.HERO_ATTRIBUTE) ~= "captain_marvel" then
		return false
	end
	if powersBlocked(character) then
		return false
	end

	local entry = CharacterRegistry.getAbilityById("captain_marvel", "photon_flight")
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
		knockHits = {},
	}

	character:SetAttribute(GameConstants.IS_FLYING_ATTRIBUTE, true)
	character:SetAttribute(GameConstants.FLIGHT_ALPHA_ATTRIBUTE, 0)
	character:SetAttribute(GameConstants.FLIGHT_BANK_ATTRIBUTE, 0)
	character:SetAttribute(GameConstants.FLIGHT_SIDE_ATTRIBUTE, 0)
	if character:GetAttribute(GameConstants.PHOTON_FLIGHT_MODE_ATTRIBUTE) ~= "Accelerated" then
		character:SetAttribute(GameConstants.PHOTON_FLIGHT_MODE_ATTRIBUTE, "Normal")
	end
	PhotonParticleHelper.setFlightTrails(character, true)
	PhotonParticleHelper.beginUse(character)
	return true
end

function PhotonFlightService.toggleFlight(player: Player)
	if flightByPlayer[player] then
		PhotonFlightService.endFlight(player, true)
	else
		PhotonFlightService.startFlight(player)
	end
end

function PhotonFlightService.setInput(
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

function PhotonFlightService.update(dt: number)
	local dtClamped = math.clamp(dt, 0.001, 0.1)
	local velLerpMove = 1 - (1 - GameConstants.FLIGHT_VEL_LERP_MOVE) ^ (dtClamped * 60)
	local velLerpDecay = 1 - (1 - GameConstants.FLIGHT_VEL_LERP_DECAY) ^ (dtClamped * 60)
	local now = AbilityCooldownHelper.getNow()

	for player, state in flightByPlayer do
		local char = state.character
		if player.Character ~= char or not char.Parent or not state.humanoid.Parent or not state.root.Parent then
			PhotonFlightService.endFlight(player, false)
			continue
		end
		if state.humanoid.Health <= 0 then
			PhotonFlightService.endFlight(player, false)
			continue
		end

		local mode = getFlightMode(char)
		local accelerated = mode == "Accelerated"
		local energyDrain = if accelerated
			then GameConstants.PHOTON_FLIGHT_ACCEL_ENERGY_PER_SEC
			else GameConstants.PHOTON_FLIGHT_ENERGY_PER_SEC
		if char:GetAttribute(GameConstants.BINARY_ACTIVE_ATTRIBUTE) == true then
			energyDrain *= GameConstants.BINARY_ENERGY_MULT
		end
		local speed = if accelerated
			then GameConstants.PHOTON_FLIGHT_ACCEL_SPEED
			else GameConstants.PHOTON_FLIGHT_SPEED

		local energy = char:GetAttribute(GameConstants.ENERGY_ATTRIBUTE)
		if type(energy) ~= "number" or energy <= 0 then
			PhotonFlightService.endFlight(player, true)
			continue
		end
		char:SetAttribute(
			GameConstants.ENERGY_ATTRIBUTE,
			math.max(0, energy - energyDrain * dtClamped)
		)
		CharacterService.markAbilityUse(char)

		local moveMag = state.moveDir.Magnitude
		local direction = if moveMag > 0.01 then state.moveDir.Unit else normalize(state.lookDir)

		local sideLean = math.clamp(state.sideInput, -1, 1)

		if state.diveTarget then
			local toTarget = state.diveTarget - state.root.Position
			local dist = toTarget.Magnitude
			if dist < 0.05 then
				state.currentVel = Vector3.zero
			else
				state.currentVel = toTarget.Unit * GameConstants.PHOTON_DIVE_SPEED
			end
			state.mover.linearVelocity.VectorVelocity = state.currentVel
			if state.mover.vectorForce then
				state.mover.vectorForce.Force = Vector3.new(0, state.root.AssemblyMass * workspace.Gravity, 0)
			end
			if state.mover.alignOrientation then
				local face = if dist > 0.05 then toTarget.Unit else normalize(state.lookDir)
				state.mover.alignOrientation.CFrame = CFrame.lookAt(state.root.Position, state.root.Position + face)
			end
			char:SetAttribute(GameConstants.FLIGHT_ALPHA_ATTRIBUTE, 1)
			continue
		end

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
		if moveMag > 0.01 and velMag > 2 then
			bank = getBank(direction, state.currentVel) * leanStrength * GameConstants.FLIGHT_BANK_SCALE
			bank += sideLean * GameConstants.FLIGHT_BANK_MAX * GameConstants.FLIGHT_SIDE_YIELD * leanStrength
			sideYaw = sideLean * GameConstants.FLIGHT_SIDE_YAW * leanStrength
			pitchAlpha = math.min(1, alphaSpeed) * 1.15
		end
		bank = math.clamp(bank, -GameConstants.FLIGHT_BANK_MAX, GameConstants.FLIGHT_BANK_MAX)
		sideYaw = math.clamp(sideYaw, -GameConstants.FLIGHT_SIDE_YAW, GameConstants.FLIGHT_SIDE_YAW)

		if state.mover.alignOrientation then
			local baseCf = CFrame.lookAt(state.root.Position, state.root.Position + facingDir)
			local targetCf = baseCf
				* CFrame.Angles(
					math.rad(-pitchAlpha * GameConstants.PHOTON_FLIGHT_PITCH_MAX),
					math.rad(sideYaw),
					math.rad(-bank)
				)
			local rotAlpha = 1 - (1 - GameConstants.FLIGHT_ROTATION_LERP) ^ (dtClamped * 60)
			state.mover.alignOrientation.CFrame = state.mover.alignOrientation.CFrame:Lerp(targetCf, rotAlpha)
		end

		char:SetAttribute(GameConstants.FLIGHT_ALPHA_ATTRIBUTE, math.clamp(alphaSpeed, 0, 1))
		char:SetAttribute(GameConstants.FLIGHT_BANK_ATTRIBUTE, bank)
		char:SetAttribute(GameConstants.FLIGHT_SIDE_ATTRIBUTE, sideLean)

		if accelerated then
			applyAcceleratedKnock(state, now)
		end
	end
end

function PhotonFlightService.init()
	Remotes.getEvent("FlightInput").OnServerEvent:Connect(function(player: Player, payload: any)
		if type(payload) ~= "table" then
			return
		end
		local move = if typeof(payload.moveVector) == "Vector3" then payload.moveVector else Vector3.zero
		local look = if typeof(payload.lookVector) == "Vector3" then payload.lookVector else Vector3.new(0, 0, -1)
		local side = if type(payload.sideInput) == "number" then payload.sideInput else 0
		PhotonFlightService.setInput(player, move, look, side)
	end)

	local function hookPlayer(player: Player)
		player.CharacterRemoving:Connect(function(character)
			PhotonFlightService.endFlight(player, false)
			if character then
				character:SetAttribute(GameConstants.IS_FLYING_ATTRIBUTE, nil)
				character:SetAttribute(GameConstants.FLIGHT_ALPHA_ATTRIBUTE, nil)
				character:SetAttribute(GameConstants.FLIGHT_BANK_ATTRIBUTE, nil)
				character:SetAttribute(GameConstants.FLIGHT_SIDE_ATTRIBUTE, nil)
			end
		end)
		player.CharacterAdded:Connect(function(character)
			PhotonFlightService.endFlight(player, false)
			local humanoid = character:WaitForChild("Humanoid", 8)
			if humanoid and humanoid:IsA("Humanoid") then
				humanoid.Died:Connect(function()
					PhotonFlightService.endFlight(player, false)
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
				PhotonFlightService.endFlight(player, false)
				local hum = character:FindFirstChildOfClass("Humanoid")
				if hum and hum:GetAttribute("HeroAbilityLocked") == true then
					ConstraintHelper.unlockHumanoid(hum)
				end
				local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root then
					for _, name in { "HeroLinearVelocity", "HeroGravityCancel", "HeroAlignOrientation" } do
						local inst = root:FindFirstChild(name)
						if inst then
							inst:Destroy()
						end
					end
				end
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
		PhotonFlightService.endFlight(player, false)
	end)
end

return PhotonFlightService
