--!strict

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterService = require(script.CharacterService)
local MonetAbilityService = require(script.MonetAbilityService)
local MonetFlightService = require(script.MonetFlightService)
local MonetConstants = require(ReplicatedStorage.Shared.MonetConstants)

CharacterService.init()
MonetFlightService.init()
MonetAbilityService.init()

RunService.Heartbeat:Connect(function(dt)
	MonetFlightService.update(dt)
	MonetAbilityService.update(dt)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character and character:GetAttribute(MonetConstants.HERO_ATTRIBUTE) then
			CharacterService.regenEnergy(character, dt)
		end
	end
end)
