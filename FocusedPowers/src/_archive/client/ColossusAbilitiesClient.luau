--!strict
--[[
	Colossus E/C/Q abilities client.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local AbilityGateHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityGateHelper"))
local BulwarkConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BulwarkConstants"))
local PowerPunchConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PowerPunchConstants"))
local SeismicSlamConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SeismicSlamConstants"))

local ColossusAbilitiesClient = {}

function ColossusAbilitiesClient.start(
	punchRemote: RemoteEvent,
	bulwarkRemote: RemoteEvent,
	slamRemote: RemoteEvent,
	player: Player,
	setAbilityPressed: ((key: string, pressed: boolean) -> ())?
)
	local eWas, cWas, qWas = false, false, false
	local bulwarkHeld = false

	RunService.Heartbeat:Connect(function()
		if AbilityGateHelper.getCharacterId(player) ~= "Colossus" then
			eWas, cWas, qWas = false, false, false
			bulwarkHeld = false
			return
		end
		local char = player.Character
		local cam = workspace.CurrentCamera
		if not char or not cam then
			return
		end

		local look = cam.CFrame.LookVector
		if look.Magnitude < 0.01 then
			look = Vector3.new(0, 0, -1)
		else
			look = look.Unit
		end

		local eDown = UserInputService:IsKeyDown(Enum.KeyCode.E)
		if eDown and not eWas then
			if AbilityGateHelper.canUse(player, char, PowerPunchConstants.ABILITY_ID) then
				punchRemote:FireServer(look.X, look.Y, look.Z)
				if setAbilityPressed then
					setAbilityPressed("E", true)
					task.delay(0.12, function()
						if setAbilityPressed then setAbilityPressed("E", false) end
					end)
				end
			end
		end
		eWas = eDown

		local cDown = UserInputService:IsKeyDown(Enum.KeyCode.C)
		if cDown then
			if not bulwarkHeld and cDown and not cWas then
				if AbilityGateHelper.canUse(player, char, BulwarkConstants.ABILITY_ID) then
					bulwarkRemote:FireServer(true, look.X, look.Y, look.Z)
					bulwarkHeld = true
					if setAbilityPressed then setAbilityPressed("C", true) end
				end
			elseif bulwarkHeld then
				bulwarkRemote:FireServer(true, look.X, look.Y, look.Z)
			end
		elseif not cDown and bulwarkHeld then
			bulwarkRemote:FireServer(false, look.X, look.Y, look.Z)
			bulwarkHeld = false
			if setAbilityPressed then setAbilityPressed("C", false) end
		end
		cWas = cDown

		local qDown = UserInputService:IsKeyDown(Enum.KeyCode.Q)
		if qDown and not qWas then
			if AbilityGateHelper.canUse(player, char, SeismicSlamConstants.ABILITY_ID) then
				slamRemote:FireServer()
				if setAbilityPressed then
					setAbilityPressed("Q", true)
					task.delay(0.12, function()
						if setAbilityPressed then setAbilityPressed("Q", false) end
					end)
				end
			end
		end
		qWas = qDown
	end)
end

return ColossusAbilitiesClient
