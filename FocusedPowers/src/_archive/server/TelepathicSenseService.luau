--!strict
--[[
	Telepathic Sense server: validate start/end and apply cooldown.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AbilityCooldownHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityCooldownHelper"))
local TelepathicSenseConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TelepathicSenseConstants"))

local EnergyService = require(script.Parent:WaitForChild("EnergyService"))

local ABILITY_ID = TelepathicSenseConstants.ABILITY_ID
local COOLDOWN_SEC = TelepathicSenseConstants.COOLDOWN_SEC

local activeByPlayer: { [Player]: boolean } = {}

local TelepathicSenseService = {}

local function isJeanGrey(plr: Player): boolean
	return plr:GetAttribute("SelectedCharacter") == "JeanGrey"
end

local function getCharacter(plr: Player): Model?
	return plr.Character
end

function TelepathicSenseService.setup(senseStart: RemoteEvent, senseEnd: RemoteEvent)
	senseStart.OnServerEvent:Connect(function(plr: Player)
		if not isJeanGrey(plr) then
			return
		end
		local char = getCharacter(plr)
		if not char then
			return
		end
		if char:GetAttribute("IsTelekineticFlying") == true then
			return
		end
		if char:GetAttribute("IsTelekinesisActive") == true then
			return
		end
		if char:GetAttribute("Ragdolled") == true then
			return
		end
		if AbilityCooldownHelper.isOnCooldown(char, ABILITY_ID) then
			return
		end
		if not EnergyService.hasMinimum(char, ABILITY_ID) then
			return
		end
		if activeByPlayer[plr] then
			return
		end

		activeByPlayer[plr] = true
		char:SetAttribute("IsTelepathicSenseActive", true)
	end)

	senseEnd.OnServerEvent:Connect(function(plr: Player)
		if not activeByPlayer[plr] then
			return
		end
		activeByPlayer[plr] = nil

		local char = getCharacter(plr)
		if char then
			char:SetAttribute("IsTelepathicSenseActive", nil)
			AbilityCooldownHelper.apply(char, ABILITY_ID, COOLDOWN_SEC)
		end
	end)
end

function TelepathicSenseService.onPlayerRemoving(plr: Player)
	activeByPlayer[plr] = nil
end

function TelepathicSenseService.forceEnd(plr: Player)
	if not activeByPlayer[plr] then
		return
	end
	activeByPlayer[plr] = nil
	local char = getCharacter(plr)
	if char then
		char:SetAttribute("IsTelepathicSenseActive", nil)
	end
end

return TelepathicSenseService
