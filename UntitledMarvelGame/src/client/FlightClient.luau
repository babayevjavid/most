--!strict

--[[

	Chaos Flight input — ported from NewMarvel NewFlightInputClient.

]]



local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RunService = game:GetService("RunService")

local UserInputService = game:GetService("UserInputService")



local Keybinds = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Keybinds"))

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))



local AbilityController = require(script.Parent.Controllers.AbilityController)



local FlightClient = {}



local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")

local flightToggle = remotesFolder:WaitForChild(Remotes.FlightToggle) :: RemoteEvent

local flightInput = remotesFolder:WaitForChild(Remotes.FlightInput) :: RemoteEvent



local function isChaosLevitate(): boolean

	return AbilityController.getMovementId() == "ChaosLevitate"

end



function FlightClient.setup()

	UserInputService.InputBegan:Connect(function(input, gameProcessed)

		if gameProcessed or not AbilityController.hasHero() or not isChaosLevitate() then

			return

		end

		if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == Keybinds.Movement then

			flightToggle:FireServer()

		end

	end)



	RunService.Heartbeat:Connect(function()

		local player = game:GetService("Players").LocalPlayer

		local char = player.Character

		if not char or char:GetAttribute("NewFlightActive") ~= true then

			return

		end



		local cam = workspace.CurrentCamera

		if not cam then

			return

		end



		local look = cam.CFrame.LookVector

		if look.Magnitude < 0.01 then

			look = Vector3.new(0, 0, -1)

		else

			look = look.Unit

		end



		local right = cam.CFrame.RightVector

		if right.Magnitude < 0.01 then

			right = Vector3.new(1, 0, 0)

		else

			right = right.Unit

		end



		local w = UserInputService:IsKeyDown(Enum.KeyCode.W) and 1 or 0

		local s = UserInputService:IsKeyDown(Enum.KeyCode.S) and 1 or 0

		local a = UserInputService:IsKeyDown(Enum.KeyCode.A) and 1 or 0

		local d = UserInputService:IsKeyDown(Enum.KeyCode.D) and 1 or 0

		local moveDir = look * (w - s) + right * (d - a)

		if moveDir.Magnitude > 1 then

			moveDir = moveDir.Unit

		end



		flightInput:FireServer(moveDir.X, moveDir.Y, moveDir.Z, look.X, look.Y, look.Z)

	end)

end



return FlightClient

