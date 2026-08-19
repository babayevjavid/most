--!strict
--[[
	Telekinetic Flight (F): toggle on/off; camera-relative WASD like NewMarvelProject.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local AbilityGateHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityGateHelper"))
local TelekineticFlightConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TelekineticFlightConstants"))

local ABILITY_ID = TelekineticFlightConstants.ABILITY_ID
local TOGGLE_DEBOUNCE = TelekineticFlightConstants.TOGGLE_DEBOUNCE

local TelekineticFlightClient = {}

function TelekineticFlightClient.start(
	flightToggle: RemoteEvent,
	flightInput: RemoteEvent,
	player: Player,
	setAbilityPressed: ((key: string, pressed: boolean) -> ())?
)
	local lastFToggle = 0
	local fWasDown = false

	RunService.Heartbeat:Connect(function()
		if not AbilityGateHelper.isJeanGrey(player) then
			fWasDown = false
			if setAbilityPressed then
				setAbilityPressed("F", false)
			end
			return
		end

		local char = player.Character
		local cam = workspace.CurrentCamera
		if not char or not cam then
			return
		end

		local now = tick()
		local fDown = UserInputService:IsKeyDown(Enum.KeyCode.F)
		local flying = char:GetAttribute("IsTelekineticFlying") == true

		if fDown and not fWasDown and now - lastFToggle >= TOGGLE_DEBOUNCE then
			lastFToggle = now
			if flying then
				flightToggle:FireServer(false)
				if setAbilityPressed then
					setAbilityPressed("F", false)
				end
			elseif AbilityGateHelper.canUse(player, char, ABILITY_ID) then
				flightToggle:FireServer(true)
				if setAbilityPressed then
					setAbilityPressed("F", true)
				end
			end
		end
		fWasDown = fDown

		if not flying then
			return
		end

		if setAbilityPressed then
			setAbilityPressed("F", true)
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

		local wDown = UserInputService:IsKeyDown(Enum.KeyCode.W)
		local sDown = UserInputService:IsKeyDown(Enum.KeyCode.S)
		local aDown = UserInputService:IsKeyDown(Enum.KeyCode.A)
		local dDown = UserInputService:IsKeyDown(Enum.KeyCode.D)
		local moveDir = look * ((if wDown then 1 else 0) - (if sDown then 1 else 0))
			+ right * ((if dDown then 1 else 0) - (if aDown then 1 else 0))
		if moveDir.Magnitude > 1 then
			moveDir = moveDir.Unit
		elseif moveDir.Magnitude < 0.01 then
			moveDir = Vector3.zero
		end

		flightInput:FireServer(moveDir.X, moveDir.Y, moveDir.Z, look.X, look.Y, look.Z, 0)
	end)
end

return TelekineticFlightClient
