--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AbilityCooldownHelper = require(ReplicatedStorage.Shared.AbilityCooldownHelper)
local CharacterRegistry = require(ReplicatedStorage.Shared.CharacterRegistry)
local ConstraintHelper = require(ReplicatedStorage.Shared.ConstraintHelper)
local MonetConstants = require(ReplicatedStorage.Shared.MonetConstants)
local MovementHelper = require(ReplicatedStorage.Shared.MovementHelper)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local VfxHelper = require(ReplicatedStorage.Shared.VfxHelper)

local MonetFlightService = {}

type FlightState = {
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	mover: ConstraintHelper.MoverBundle,
	moveDir: Vector3,
	lookDir: Vector3,
	currentVel: Vector3,
	boosting: boolean,
}

local flightByPlayer: { [Player]: FlightState } = {}

local function normalize(v: Vector3): Vector3
	if v.Magnitude < 0.01 then
		return Vector3.new(0, 0, -1)
	end
	return v.Unit
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

function MonetFlightService.isFlying(player: Player): boolean
	return flightByPlayer[player] ~= nil
end

function MonetFlightService.endFlight(player: Player, applyCooldown: boolean?)
	local state = flightByPlayer[player]
	if not state then
		return
	end
	flightByPlayer[player] = nil

	local char = state.character
	if char and char.Parent then
		char:SetAttribute(MonetConstants.IS_FLYING_ATTRIBUTE, nil)
		char:SetAttribute(MonetConstants.FLIGHT_ALPHA_ATTRIBUTE, nil)
		char:SetAttribute(MonetConstants.FLIGHT_BANK_ATTRIBUTE, nil)
	end

	ConstraintHelper.destroyMover(state.mover)
	if state.humanoid.Parent then
		ConstraintHelper.unlockHumanoid(state.humanoid)
	end

	if applyCooldown and char and char.Parent then
		local entry = CharacterRegistry.getAbilityById("monet_st_croix", "psionic_flight")
		if entry then
			AbilityCooldownHelper.applyAfterUse(char, entry.id, entry.cooldown)
		end
	end
end

function MonetFlightService.startFlight(player: Player): boolean
	if flightByPlayer[player] then
		return false
	end
	local character = player.Character
	if not character then
		return false
	end
	if character:GetAttribute(MonetConstants.HERO_ATTRIBUTE) ~= "monet_st_croix" then
		return false
	end
	if character:GetAttribute(MonetConstants.FORM_ATTRIBUTE) == "Penance" then
		return false
	end

	local entry = CharacterRegistry.getAbilityById("monet_st_croix", "psionic_flight")
	if not entry then
		return false
	end
	if AbilityCooldownHelper.isOnCooldown(character, entry.id) then
		return false
	end

	local energy = character:GetAttribute(MonetConstants.ENERGY_ATTRIBUTE)
	if type(energy) ~= "number" or energy < entry.energyCost then
		return false
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root then
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
		boosting = false,
	}

	character:SetAttribute(MonetConstants.IS_FLYING_ATTRIBUTE, true)
	character:SetAttribute(MonetConstants.FLIGHT_ALPHA_ATTRIBUTE, 0)
	character:SetAttribute(MonetConstants.FLIGHT_BANK_ATTRIBUTE, 0)
	VfxHelper.pulseAbility(character, "psionic_flight")
	VfxHelper.spawnBurstSparks(root.Position, VfxHelper.psychicColor(), 10)
	return true
end

function MonetFlightService.toggleFlight(player: Player)
	if flightByPlayer[player] then
		MonetFlightService.endFlight(player, true)
	else
		MonetFlightService.startFlight(player)
	end
end

function MonetFlightService.setInput(player: Player, moveDir: Vector3, lookDir: Vector3, boosting: boolean)
	local state = flightByPlayer[player]
	if not state then
		return
	end
	state.moveDir = moveDir
	state.lookDir = lookDir
	state.boosting = boosting
end

function MonetFlightService.update(dt: number)
	local dtClamped = math.clamp(dt, 0.001, 0.1)
	local velLerpMove = 1 - (1 - MonetConstants.FLIGHT_VEL_LERP_MOVE) ^ (dtClamped * 60)
	local velLerpDecay = 1 - (1 - MonetConstants.FLIGHT_VEL_LERP_DECAY) ^ (dtClamped * 60)

	for player, state in flightByPlayer do
		local char = state.character
		if not char.Parent or not state.humanoid.Parent or not state.root.Parent then
			MonetFlightService.endFlight(player, false)
			continue
		end

		local energy = char:GetAttribute(MonetConstants.ENERGY_ATTRIBUTE)
		if type(energy) ~= "number" or energy <= 0 then
			MonetFlightService.endFlight(player, true)
			continue
		end
		char:SetAttribute(
			MonetConstants.ENERGY_ATTRIBUTE,
			math.max(0, energy - MonetConstants.FLIGHT_ENERGY_PER_SEC * dtClamped)
		)

		local moveMag = state.moveDir.Magnitude
		local direction = if moveMag > 0.01 then state.moveDir.Unit else state.lookDir.Unit
		local speed = if state.boosting then MonetConstants.FLIGHT_BOOST_SPEED else MonetConstants.FLIGHT_SPEED
		local targetVel = if moveMag > 0.01 then direction * speed else Vector3.zero
		local lerpAlpha = if moveMag > 0.01 then velLerpMove else velLerpDecay
		state.currentVel = state.currentVel:Lerp(targetVel, lerpAlpha)
		state.mover.linearVelocity.VectorVelocity = state.currentVel
		if state.mover.vectorForce then
			state.mover.vectorForce.Force = Vector3.new(0, state.root.AssemblyMass * workspace.Gravity, 0)
		end

		local velMag = state.currentVel.Magnitude
		local alphaSpeed = if speed > 0 then velMag / speed else 0
		local facingDir = if moveMag > 0.01 then direction else state.lookDir.Unit
		local bank = 0
		local pitchAlpha = 0
		if moveMag > 0.01 and velMag > 2 then
			bank = getBank(direction, state.currentVel) * math.clamp(alphaSpeed, 0, 1) * MonetConstants.FLIGHT_BANK_SCALE
			pitchAlpha = math.min(1, alphaSpeed)
		end

		if state.mover.alignOrientation then
			local baseCf = CFrame.new(state.root.Position, state.root.Position + facingDir)
			local targetCf = baseCf
				* CFrame.Angles(
					math.rad(-pitchAlpha * MonetConstants.FLIGHT_PITCH_MAX),
					math.rad(math.clamp(bank, -MonetConstants.FLIGHT_BANK_MAX, MonetConstants.FLIGHT_BANK_MAX)),
					math.rad(-bank * 0.35)
				)
			local rotAlpha = 1 - (1 - MonetConstants.FLIGHT_ROTATION_LERP) ^ (dtClamped * 60)
			state.mover.alignOrientation.CFrame = state.mover.alignOrientation.CFrame:Lerp(targetCf, rotAlpha)
		end

		char:SetAttribute(MonetConstants.FLIGHT_ALPHA_ATTRIBUTE, math.clamp(alphaSpeed, 0, 1))
		char:SetAttribute(MonetConstants.FLIGHT_BANK_ATTRIBUTE, bank)

		if velMag > 4 and math.random() < dtClamped * 8 then
			VfxHelper.spawnTrail(state.root, VfxHelper.psychicColor(), 0.2)
		end
	end
end

function MonetFlightService.init()
	Remotes.getEvent("FlightInput").OnServerEvent:Connect(function(player: Player, payload: any)
		if type(payload) ~= "table" then
			return
		end
		local move = if typeof(payload.moveVector) == "Vector3" then payload.moveVector else Vector3.zero
		local look = if typeof(payload.lookVector) == "Vector3" then payload.lookVector else Vector3.new(0, 0, -1)
		local boosting = payload.boosting == true
		MonetFlightService.setInput(player, move, look, boosting)
	end)

	Players.PlayerRemoving:Connect(function(player)
		MonetFlightService.endFlight(player, false)
	end)
end

return MonetFlightService
