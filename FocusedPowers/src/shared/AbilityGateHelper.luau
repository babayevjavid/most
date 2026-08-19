--[[ Shared ability gating for character powers. ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AbilityCooldownHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityCooldownHelper"))
local CharacterAbilityRegistry = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CharacterAbilityRegistry"))
local ResourceConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ResourceConstants"))
local SunspotSolarHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SunspotSolarHelper"))

local FLIGHT_ID = "MagneticFlight"
local FERROKINESIS_ID = "Ferrokinesis"
local MAGNETIC_PULSE_ID = "MagneticPulse"
local ORBITAL_ID = "OrbitalStrikes"
local LANCE_ID = "MetalLance"
local HAVOK_BEAM_ID = "ConcussiveBeam"
local HAVOK_BURST_ID = "EnergyBurst"
local HAVOK_SURGE_ID = "KineticSurge"
local HAVOK_BLAST_ID = "EnergyBlast"
local SOLAR_FLIGHT_ID = "SolarFlight"
local SUN_UPPERCUT_ID = "SunUppercut"
local SOLAR_FLARE_ID = "SolarFlare"
local PHOTOSYNTHESIS_ID = "Photosynthesis"
local BLACK_SUN_ID = "BlackSun"

local AbilityGateHelper = {}

local function listHas(list: { string }, id: string): boolean
	for _, entry in list do
		if entry == id then
			return true
		end
	end
	return false
end

local function hasResourceMinimum(character: Model, charId: string, abilityId: string): boolean
	local config = ResourceConstants.CONFIGS[charId]
	if not config then
		return true
	end
	local minCost = config.minToStart[abilityId]
	if not minCost then
		return true
	end
	local energy = character:GetAttribute("Energy")
	local current = if typeof(energy) == "number" then energy else config.max
	return current >= minCost
end

function AbilityGateHelper.getCharacterId(player: Player): string?
	local id = player:GetAttribute("SelectedCharacter")
	if typeof(id) == "string" and id ~= "" then
		return id
	end
	return nil
end

function AbilityGateHelper.isPolaris(player: Player): boolean
	return AbilityGateHelper.getCharacterId(player) == "Polaris"
end

function AbilityGateHelper.isMagneticFlying(character: Model): boolean
	return character:GetAttribute("IsMagneticFlying") == true
end

function AbilityGateHelper.isFerrokinesisActive(character: Model): boolean
	return character:GetAttribute("IsFerrokinesisActive") == true
end

function AbilityGateHelper.isOrbitalStrikesActive(character: Model): boolean
	return character:GetAttribute("IsOrbitalStrikesActive") == true
end

function AbilityGateHelper.isMetalLanceActive(character: Model): boolean
	return character:GetAttribute("IsMetalLanceActive") == true
end

function AbilityGateHelper.isHavok(player: Player): boolean
	return AbilityGateHelper.getCharacterId(player) == "Havok"
end

function AbilityGateHelper.isSunspot(player: Player): boolean
	return AbilityGateHelper.getCharacterId(player) == "Sunspot"
end

function AbilityGateHelper.isPsylocke(player: Player): boolean
	return AbilityGateHelper.getCharacterId(player) == "Psylocke"
end

function AbilityGateHelper.isSolarFlying(character: Model): boolean
	return character:GetAttribute("IsSolarFlying") == true
end

function AbilityGateHelper.isSolarFlareActive(character: Model): boolean
	return character:GetAttribute("IsSolarFlareActive") == true
end

function AbilityGateHelper.isPhotosynthesisActive(character: Model): boolean
	return character:GetAttribute("IsPhotosynthesisActive") == true
end

function AbilityGateHelper.isBlackSunCharging(character: Model): boolean
	return character:GetAttribute("IsBlackSunCharging") == true
end

function AbilityGateHelper.isConcussiveBeamActive(character: Model): boolean
	return character:GetAttribute("IsConcussiveBeamActive") == true
end

function AbilityGateHelper.isKineticSurgeActive(character: Model): boolean
	return character:GetAttribute("IsKineticSurgeActive") == true
end

function AbilityGateHelper.isEnergyBlastActive(character: Model): boolean
	return character:GetAttribute("IsEnergyBlastActive") == true
end

function AbilityGateHelper.isMagneticPulseActive(character: Model): boolean
	return character:GetAttribute("IsMagneticPulseActive") == true
end

function AbilityGateHelper.isHeadLookBlocked(character: Model): boolean
	if character:GetAttribute("Ragdolled") == true then
		return true
	end
	return AbilityGateHelper.isMagneticFlying(character)
		or AbilityGateHelper.isSolarFlying(character)
		or AbilityGateHelper.isFerrokinesisActive(character)
		or AbilityGateHelper.isOrbitalStrikesActive(character)
		or AbilityGateHelper.isMetalLanceActive(character)
		or AbilityGateHelper.isMagneticPulseActive(character)
		or AbilityGateHelper.isEnergyBlastActive(character)
		or AbilityGateHelper.isSolarFlareActive(character)
		or AbilityGateHelper.isPhotosynthesisActive(character)
		or AbilityGateHelper.isBlackSunCharging(character)
		or AbilityGateHelper.isConcussiveBeamActive(character)
		or AbilityGateHelper.isKineticSurgeActive(character)
end

function AbilityGateHelper.isAbilityAllowedForCharacter(charId: string, abilityId: string): boolean
	local list = CharacterAbilityRegistry[charId]
	if not list then
		return false
	end
	return listHas(list, abilityId)
end

function AbilityGateHelper.canUse(player: Player, character: Model?, abilityId: string, now: number?): boolean
	local charId = AbilityGateHelper.getCharacterId(player)
	if not charId or not character or not character.Parent then
		return false
	end
	if not AbilityGateHelper.isAbilityAllowedForCharacter(charId, abilityId) then
		return false
	end
	if AbilityCooldownHelper.isOnCooldown(character, abilityId, now) then
		return false
	end
	if character:GetAttribute("Ragdolled") == true then
		return false
	end

	if charId == "Polaris" then
		if AbilityGateHelper.isFerrokinesisActive(character) and abilityId ~= FERROKINESIS_ID then
			return false
		end
		if AbilityGateHelper.isOrbitalStrikesActive(character) and abilityId ~= ORBITAL_ID then
			return false
		end
		if AbilityGateHelper.isMetalLanceActive(character) and abilityId ~= LANCE_ID then
			return false
		end

		if AbilityGateHelper.isMagneticFlying(character) then
			if abilityId == FLIGHT_ID or abilityId == FERROKINESIS_ID or abilityId == MAGNETIC_PULSE_ID then
				return hasResourceMinimum(character, charId, abilityId)
			end
			return false
		end

		if abilityId == ORBITAL_ID or abilityId == LANCE_ID then
			if AbilityGateHelper.isFerrokinesisActive(character) then
				return false
			end
		end

		return hasResourceMinimum(character, charId, abilityId)
	end

	if charId == "Havok" then
		if AbilityGateHelper.isKineticSurgeActive(character) then
			return false
		end
		if AbilityGateHelper.isEnergyBlastActive(character) and abilityId ~= HAVOK_BLAST_ID then
			return false
		end
		if AbilityGateHelper.isConcussiveBeamActive(character) and abilityId ~= HAVOK_BEAM_ID then
			return false
		end
		if abilityId == HAVOK_BURST_ID then
			local charge = character:GetAttribute("HavokCharge")
			if typeof(charge) ~= "number" or charge < 1 then
				return false
			end
		end
		if abilityId == HAVOK_SURGE_ID or abilityId == HAVOK_BURST_ID then
			if AbilityGateHelper.isConcussiveBeamActive(character) then
				return false
			end
		end
		return hasResourceMinimum(character, charId, abilityId)
	end

	if charId == "Sunspot" then
		if AbilityGateHelper.isPhotosynthesisActive(character) and abilityId ~= PHOTOSYNTHESIS_ID then
			return false
		end
		if AbilityGateHelper.isBlackSunCharging(character) and abilityId ~= BLACK_SUN_ID then
			return false
		end
		if AbilityGateHelper.isSolarFlying(character) then
			if abilityId == SOLAR_FLIGHT_ID or abilityId == SOLAR_FLARE_ID then
				return hasResourceMinimum(character, charId, abilityId)
			end
			return false
		end
		if AbilityGateHelper.isSolarFlareActive(character) and abilityId ~= SOLAR_FLARE_ID then
			return false
		end
		if abilityId == PHOTOSYNTHESIS_ID then
			return SunspotSolarHelper.canStartPhotosynthesis(character)
		end
		if abilityId == BLACK_SUN_ID then
			return SunspotSolarHelper.canStartBlackSun(character)
		end
		return hasResourceMinimum(character, charId, abilityId)
	end

	if charId == "Psylocke" then
		return hasResourceMinimum(character, charId, abilityId)
	end

	return false
end

return AbilityGateHelper
