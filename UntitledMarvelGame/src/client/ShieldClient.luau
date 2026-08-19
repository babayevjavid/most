--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Keybinds = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Keybinds"))
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local AbilityController = require(script.Parent.Controllers.AbilityController)

local ShieldClient = {}

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local shieldSetActive = remotesFolder:WaitForChild(Remotes.ShieldSetActive) :: RemoteEvent

local SHIELD_KEY = Keybinds.AbilitySlots[1]
local holding = false

local function isChaosShield(): boolean
	return AbilityController.getAbilityIdForSlot(1) == "ChaosShield"
end

function ShieldClient.setup()
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or not AbilityController.hasHero() or not isChaosShield() then
			return
		end
		if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == SHIELD_KEY then
			if not holding then
				holding = true
				shieldSetActive:FireServer(true)
			end
		end
	end)

	UserInputService.InputEnded:Connect(function(input, _gameProcessed)
		if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == SHIELD_KEY then
			if holding then
				holding = false
				shieldSetActive:FireServer(false)
			end
		end
	end)
end

return ShieldClient
