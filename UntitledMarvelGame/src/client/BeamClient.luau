--!strict

--[[

	Chaos Beam client — Blue Marvel antimatter beam aim pattern (mouse raycast → server look update).

]]



local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RunService = game:GetService("RunService")

local UserInputService = game:GetService("UserInputService")

local Workspace = game:GetService("Workspace")



local AbilityConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityConstants"))

local Keybinds = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Keybinds"))

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))



local AbilityController = require(script.Parent.Controllers.AbilityController)



local BeamClient = {}



local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")

local chaosBeamSetActive = remotesFolder:WaitForChild(Remotes.ChaosBeamSetActive) :: RemoteEvent

local chaosBeamLookUpdate = remotesFolder:WaitForChild(Remotes.ChaosBeamLookUpdate) :: RemoteEvent



local BEAM_KEY = Keybinds.AbilitySlots[4]

local holding = false

local lookConn: RBXScriptConnection? = nil

local lastSendTime = 0



local function getCharacter(): Model?

	return game:GetService("Players").LocalPlayer.Character

end



local function isChaosBeam(): boolean

	return AbilityController.getAbilityIdForSlot(4) == "ChaosBeam"

end



local function getBeamTargetPos(char: Model): Vector3?

	local cam = Workspace.CurrentCamera

	if not cam then

		return nil

	end



	local mouse = UserInputService:GetMouseLocation()

	local ray = cam:ViewportPointToRay(mouse.X, mouse.Y)

	local params = RaycastParams.new()

	params.FilterType = Enum.RaycastFilterType.Exclude

	params.FilterDescendantsInstances = { char }

	params.IgnoreWater = true



	local result = Workspace:Raycast(ray.Origin, ray.Direction * 500, params)

	if result then

		return result.Position

	end

	return ray.Origin + ray.Direction * 500

end



local function disconnectLook()

	if lookConn then

		lookConn:Disconnect()

		lookConn = nil

	end

	lastSendTime = 0

end



local function startLookLoop(char: Model)

	disconnectLook()



	local function fireLookUpdate()

		local curChar = getCharacter()

		if not curChar or curChar ~= char or curChar:GetAttribute("IsChaosBeamActive") ~= true then

			return

		end

		local targetPos = getBeamTargetPos(curChar)

		if not targetPos then

			return

		end

		chaosBeamLookUpdate:FireServer(targetPos.X, targetPos.Y, targetPos.Z)

	end



	fireLookUpdate()

	lookConn = RunService.Heartbeat:Connect(function()

		local curChar = getCharacter()

		if not curChar or curChar ~= char or curChar:GetAttribute("IsChaosBeamActive") ~= true then

			disconnectLook()

			return

		end

		if not holding and not UserInputService:IsKeyDown(BEAM_KEY) then

			return

		end



		local now = os.clock()

		if now - lastSendTime < AbilityConstants.CHAOS_BEAM_LOOK_SEND_INTERVAL then

			return

		end

		lastSendTime = now

		fireLookUpdate()

	end)

end



function BeamClient.setup()

	UserInputService.InputBegan:Connect(function(input, gameProcessed)

		if gameProcessed or not AbilityController.hasHero() or not isChaosBeam() then

			return

		end

		if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == BEAM_KEY then

			if holding then

				return

			end

			holding = true

			local char = getCharacter()

			if char then

				startLookLoop(char)

			end

			chaosBeamSetActive:FireServer(true)

		end

	end)



	UserInputService.InputEnded:Connect(function(input, _gameProcessed)

		if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == BEAM_KEY then

			if not holding then

				return

			end

			holding = false

			disconnectLook()

			chaosBeamSetActive:FireServer(false)

		end

	end)



	local player = game:GetService("Players").LocalPlayer

	player.CharacterAdded:Connect(function(char)

		char:GetAttributeChangedSignal("IsChaosBeamActive"):Connect(function()

			if char:GetAttribute("IsChaosBeamActive") == true and holding then

				startLookLoop(char)

			elseif char:GetAttribute("IsChaosBeamActive") ~= true then

				disconnectLook()

			end

		end)

	end)

end



return BeamClient

