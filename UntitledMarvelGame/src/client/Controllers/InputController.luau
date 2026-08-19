--!strict



local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UserInputService = game:GetService("UserInputService")



local Keybinds = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Keybinds"))

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))



local AbilityController = require(script.Parent.AbilityController)

local TelekinesisClient = require(script.Parent.Parent.TelekinesisClient)



local InputController = {}



local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")

local sprintRemote = remotesFolder:WaitForChild(Remotes.SetSprinting) :: RemoteEvent



local HOLD_ABILITIES = {

	Telekinesis = true,

	ChaosShield = true,

	ChaosBeam = true,

}



local function keyCodeToSlot(keyCode: Enum.KeyCode): number?

	for slot, code in Keybinds.AbilitySlots do

		if code == keyCode then

			return slot

		end

	end

	return nil

end



local function setSprint(active: boolean)

	if not AbilityController.hasHero() then

		sprintRemote:FireServer(false)

		return

	end

	sprintRemote:FireServer(active)

end



function InputController.setup()

	UserInputService.InputBegan:Connect(function(input, gameProcessed)

		if gameProcessed then

			return

		end

		if not AbilityController.hasHero() then

			return

		end



		if input.UserInputType == Enum.UserInputType.MouseButton1 then

			if TelekinesisClient.isTelekinesisActive() then

				return

			end

			local basicId = AbilityController.getBasicId()

			if basicId then

				AbilityController.fire(basicId)

			end

			return

		end



		if input.UserInputType ~= Enum.UserInputType.Keyboard then

			return

		end



		if input.KeyCode == Keybinds.Sprint then

			setSprint(true)

			return

		end



		local slot = keyCodeToSlot(input.KeyCode)

		if slot then

			local abilityId = AbilityController.getAbilityIdForSlot(slot)

			if abilityId and not HOLD_ABILITIES[abilityId] then

				AbilityController.fire(abilityId)

			end

			return

		end



		if input.KeyCode == Keybinds.Movement then
			local moveId = AbilityController.getMovementId()
			if moveId and moveId ~= "ChaosLevitate" then
				AbilityController.fire(moveId)
			end
			return
		end

	end)



	UserInputService.InputEnded:Connect(function(input, _gameProcessed)

		if input.UserInputType ~= Enum.UserInputType.Keyboard then

			return

		end

		if input.KeyCode == Keybinds.Sprint then

			setSprint(false)

		end

	end)

end



return InputController

