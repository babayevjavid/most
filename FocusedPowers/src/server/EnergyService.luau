--!strict
--[[ Polaris resource wrapper around ResourceService. ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ResourceService = require(script.Parent:WaitForChild("ResourceService"))

local EnergyService = {}

function EnergyService.setStopCallbacks(
	flight: (player: Player) -> (),
	ferrokinesis: (player: Player) -> (),
	orbital: (player: Player) -> (),
	lance: (player: Player) -> ()
)
	ResourceService.registerStopCallback("IsMagneticFlying", flight)
	ResourceService.registerStopCallback("IsFerrokinesisActive", ferrokinesis)
	ResourceService.registerStopCallback("IsOrbitalStrikesActive", orbital)
	ResourceService.registerStopCallback("IsMetalLanceActive", lance)
end

function EnergyService.initCharacter(character: Model)
	ResourceService.initCharacter(character, "Polaris")
end

function EnergyService.getEnergy(character: Model): (number, number)
	return ResourceService.getEnergy(character)
end

function EnergyService.hasMinimum(character: Model, abilityId: string): boolean
	return ResourceService.hasMinimum(character, "Polaris", abilityId)
end

function EnergyService.trySpend(character: Model, amount: number): boolean
	return ResourceService.trySpend(character, amount)
end

return EnergyService
