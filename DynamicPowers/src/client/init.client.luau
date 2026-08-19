local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PowerUI = require(ReplicatedStorage.Shared:WaitForChild("PowerUI"))
local AbilityHudClient = require(ReplicatedStorage.Shared:WaitForChild("AbilityHudClient"))
local LightningEClient = require(ReplicatedStorage.Shared:WaitForChild("LightningEClient"))

PowerUI.start()
AbilityHudClient.start()
LightningEClient.start()
