--!strict



local ReplicatedStorage = game:GetService("ReplicatedStorage")



local AbilityDefinitions = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityDefinitions"))

local HeroRegistry = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("HeroRegistry"))



local InteractionService = require(script.Parent.InteractionService)

local PlayerStateService = require(script.Parent.PlayerStateService)

local ProjectileService = require(script.Parent.ProjectileService)

local BeamService = require(script.Parent.BeamService)
local FlightService = require(script.Parent.FlightService)
local ShieldService = require(script.Parent.ShieldService)

local TelekinesisService = require(script.Parent.TelekinesisService)
local WandaHandParticlesService = require(script.Parent.WandaHandParticlesService)

local MjolnirFactory = require(script.Parent.Parent.Util.MjolnirFactory)



local AbilityService = {}



export type AbilityCallbacks = {

	onCooldown: (player: Player, abilityId: string, duration: number) -> (),

	onStatUpdate: (player: Player) -> (),

}



local callbacks: AbilityCallbacks? = nil



local HOLD_ABILITIES = {

	Telekinesis = true,

	ChaosShield = true,

	ChaosBeam = true,

	ChaosLevitate = true,

}



function AbilityService.setup(cbs: AbilityCallbacks)

	callbacks = cbs

end



local function getRoot(character: Model): BasePart?

	return character:FindFirstChild("HumanoidRootPart") :: BasePart?

end



local function applyCooldown(player: Player, abilityId: string, duration: number)

	local endTime = os.clock() + duration

	PlayerStateService.setCooldown(player, abilityId, endTime)

	if callbacks then

		callbacks.onCooldown(player, abilityId, duration)

	end

end



local function executeAbility(player: Player, character: Model, abilityId: string, aimDirection: Vector3?, steerToken: string?)

	local root = getRoot(character)

	if not root then

		return

	end



	local direction = if aimDirection and aimDirection.Magnitude > 0 then aimDirection.Unit else root.CFrame.LookVector



	if abilityId == "ChaosBlast" then

		ProjectileService.fireChaosBlast(player, character, direction, steerToken)

	elseif abilityId == "ForcePush" or abilityId == "ThunderClap" then

		if abilityId == "ForcePush" then

			ProjectileService.executeForcePush(player, character)

		else

			InteractionService.pushCone(character, abilityId, 30, 45)

		end

	elseif abilityId == "CosmicPunch" then

		local target = InteractionService.getTargetFromRay(root.Position, direction, 20, { character })

		if target then

			InteractionService.pushTarget(target, direction, abilityId, player)

		end

	elseif abilityId == "MjolnirThrow" then

		MjolnirFactory.throwAndReturn(character, direction)

	elseif abilityId == "MjolnirStrike" or abilityId == "MjolnirFlight" or abilityId == "GodBlast" or abilityId == "LightningStrike" or abilityId == "StormCall" then

		MjolnirFactory.createWieldModel(character)

		if abilityId == "MjolnirFlight" then

			root.AssemblyLinearVelocity = direction * 80 + Vector3.new(0, 40, 0)

		end

	elseif abilityId == "CosmicDash" or abilityId == "ShadowStep" then

		root.AssemblyLinearVelocity = direction * 60 + Vector3.new(0, 35, 0)

	elseif abilityId == "OverwhelmingForce" then

		ProjectileService.executeForcePush(player, character)

		InteractionService.pushCone(character, "ForcePush", 40, 60)

	end

end



function AbilityService.useAbility(player: Player, abilityId: string, aimDirection: Vector3?, steerToken: string?)

	if HOLD_ABILITIES[abilityId] then

		return

	end



	local state = PlayerStateService.get(player)

	if not state.HeroId then

		return

	end

	if not HeroRegistry.heroOwnsAbility(state.HeroId, abilityId) then

		return

	end



	local def = AbilityDefinitions[abilityId]

	if not def then

		return

	end



	if PlayerStateService.isOnCooldown(player, abilityId) then

		return

	end



	local character = player.Character

	if not character then

		return

	end



	if def.EnergyCost > 0 and not PlayerStateService.spendEnergy(player, def.EnergyCost) then

		return

	end



	executeAbility(player, character, abilityId, aimDirection, steerToken)

	if state.HeroId == "Wanda" then
		WandaHandParticlesService.onInstantAbility(character)
	end

	applyCooldown(player, abilityId, def.Cooldown)



	if callbacks then

		callbacks.onStatUpdate(player)

	end

end



function AbilityService.cleanupPlayer(player: Player)

	TelekinesisService.cleanupPlayer(player)

	ShieldService.cleanupPlayer(player)

	BeamService.cleanupPlayer(player)

	FlightService.cleanupPlayer(player)

	WandaHandParticlesService.cleanupPlayer(player)

	local character = player.Character

	if character then

		MjolnirFactory.cleanup(character)

	end

end



return AbilityService

