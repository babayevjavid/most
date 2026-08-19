--!strict
--[[
	Server-authoritative per-hero resource: spend, hold drain, regen, auto-stop at zero.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ResourceConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ResourceConstants"))
local SunspotSolarHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SunspotSolarHelper"))

type StopCallback = (player: Player) -> ()

local ResourceService = {}

local stopCallbacks: { [string]: StopCallback } = {}

local function markUsed(character: Model)
	character:SetAttribute("LastEnergyUseTime", os.clock())
end

local function secondsSinceUse(character: Model): number
	local lastUse = character:GetAttribute("LastEnergyUseTime")
	if typeof(lastUse) ~= "number" then
		return math.huge
	end
	return os.clock() - lastUse
end

function ResourceService.getConfig(characterId: string): ResourceConstants.ResourceConfig?
	return ResourceConstants.CONFIGS[characterId]
end

function ResourceService.hasResourceCharacter(characterId: string): boolean
	return ResourceConstants.RESOURCE_CHARACTERS[characterId] == true
end

function ResourceService.registerStopCallback(attributeName: string, callback: StopCallback)
	stopCallbacks[attributeName] = callback
end

function ResourceService.initCharacter(character: Model, characterId: string)
	local config = ResourceService.getConfig(characterId)
	if not config then
		return
	end
	character:SetAttribute("MaxEnergy", config.max)
	character:SetAttribute("Energy", config.max)
	character:SetAttribute("LastEnergyUseTime", nil)

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and config.maxHealth > 0 then
		humanoid.MaxHealth = config.maxHealth
		humanoid.Health = config.maxHealth
	end
end

function ResourceService.getEnergy(character: Model): (number, number)
	local energy = character:GetAttribute("Energy")
	local maxEnergy = character:GetAttribute("MaxEnergy")
	local current = if typeof(energy) == "number" then energy else 100
	local max = if typeof(maxEnergy) == "number" then maxEnergy else 100
	return current, max
end

function ResourceService.hasMinimum(character: Model, characterId: string, abilityId: string): boolean
	local config = ResourceService.getConfig(characterId)
	if not config then
		return true
	end
	local minCost = config.minToStart[abilityId]
	if not minCost then
		return true
	end
	if characterId == "Sunspot" and ResourceService.shouldSkipSunspotEnergyCost(character) then
		return true
	end
	local current, _ = ResourceService.getEnergy(character)
	return current >= minCost
end

function ResourceService.getScaledCost(characterId: string, abilityId: string, alpha: number): number?
	local config = ResourceService.getConfig(characterId)
	if not config or not config.scaledCosts then
		return nil
	end
	local scaled = config.scaledCosts[abilityId]
	if not scaled then
		return nil
	end
	return scaled.min + (scaled.max - scaled.min) * math.clamp(alpha, 0, 1)
end

function ResourceService.trySpend(character: Model, amount: number): boolean
	if amount <= 0 then
		return true
	end
	local current, _ = ResourceService.getEnergy(character)
	if current < amount then
		return false
	end
	character:SetAttribute("Energy", math.max(0, current - amount))
	markUsed(character)
	return true
end

function ResourceService.shouldSkipSunspotEnergyCost(character: Model): boolean
	return SunspotSolarHelper.hasFreeSolarEnergy(character)
end

function ResourceService.trySpendForAbility(character: Model, characterId: string, abilityId: string): boolean
	local config = ResourceService.getConfig(characterId)
	if not config then
		return true
	end
	local amount = config.instant[abilityId]
	if not amount or amount <= 0 then
		return true
	end
	if characterId == "Sunspot" and ResourceService.shouldSkipSunspotEnergyCost(character) then
		return true
	end
	return ResourceService.trySpend(character, amount)
end

local HOLD_ATTRIBUTE_MAP: { [string]: string } = {
	IsMagneticFlying = "MagneticFlight",
	IsSolarFlying = "SolarFlight",
	IsFerrokinesisActive = "Ferrokinesis",
	IsMetalLanceActive = "MetalLance",
	IsOrbitalStrikesActive = "OrbitalStrikes",
	IsConcussiveBeamActive = "ConcussiveBeam",
}

local function getHoldDrain(character: Model, characterId: string): number
	local config = ResourceService.getConfig(characterId)
	if not config then
		return 0
	end
	local drain = 0

	if character:GetAttribute("IsFerrokinesisActive") == true then
		drain += config.holdPerSec.Ferrokinesis or 0
	end
	if character:GetAttribute("IsMagneticFlying") == true then
		if character:GetAttribute("FlightInputActive") == true then
			drain += config.holdPerSec.MagneticFlightMoving or 0
		else
			drain += config.holdPerSec.MagneticFlightIdle or 0
		end
	end
	if character:GetAttribute("IsSolarFlying") == true then
		if character:GetAttribute("FlightInputActive") == true then
			drain += config.holdPerSec.SolarFlightMoving or 0
		else
			drain += config.holdPerSec.SolarFlightIdle or 0
		end
	end
	if character:GetAttribute("IsMetalLanceActive") == true then
		drain += config.holdPerSec.MetalLance or 0
	end
	if character:GetAttribute("IsConcussiveBeamActive") == true then
		drain += config.holdPerSec.ConcussiveBeam or 0
	end

	if characterId == "Sunspot" and ResourceService.shouldSkipSunspotEnergyCost(character) then
		return 0
	end

	return drain
end

local function isAnyHoldActive(character: Model): boolean
	for attrName in HOLD_ATTRIBUTE_MAP do
		if character:GetAttribute(attrName) == true then
			return true
		end
	end
	return false
end

local function forceStopHolds(player: Player, character: Model)
	for attrName, _ in HOLD_ATTRIBUTE_MAP do
		if character:GetAttribute(attrName) == true then
			local cb = stopCallbacks[attrName]
			if cb then
				cb(player)
			end
		end
	end
end

function ResourceService.update(player: Player, dt: number)
	local character = player.Character
	local characterId = player:GetAttribute("SelectedCharacter")
	if not character or typeof(characterId) ~= "string" then
		return
	end
	if not ResourceService.hasResourceCharacter(characterId) then
		return
	end

	local config = ResourceService.getConfig(characterId)
	if not config then
		return
	end

	local current, max = ResourceService.getEnergy(character)
	if current <= 0 then
		forceStopHolds(player, character)
		current = 0
	end

	local drain = getHoldDrain(character, characterId)
	if drain > 0 then
		local nextEnergy = math.max(0, current - drain * dt)
		character:SetAttribute("Energy", nextEnergy)
		markUsed(character)
		if nextEnergy <= 0 then
			forceStopHolds(player, character)
		end
		return
	end

	if not isAnyHoldActive(character) and current < max then
		if characterId == "Sunspot" then
			if character:GetAttribute("IsPhotosynthesisActive") ~= true then
				local strength = character:GetAttribute("SunspotStrength")
				local solarStrength = if typeof(strength) == "number" then strength else 0
				if solarStrength > 0 then
					local chargeRate = config.solarChargePerSec or 12
					character:SetAttribute("Energy", math.min(max, current + chargeRate * solarStrength * dt))
				end
			end
		elseif secondsSinceUse(character) >= config.regenDelaySec then
			character:SetAttribute("Energy", math.min(max, current + config.regenPerSec * dt))
		end
	end
end

return ResourceService
