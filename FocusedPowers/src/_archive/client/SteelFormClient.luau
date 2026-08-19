--!strict
--[[
	Steel Form (F): toggle Colossus organic steel transformation.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local AbilityGateHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityGateHelper"))
local SteelFormConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SteelFormConstants"))

local ABILITY_ID = SteelFormConstants.ABILITY_ID

local SteelFormClient = {}

function SteelFormClient.start(
	steelFormToggle: RemoteEvent,
	player: Player,
	setAbilityPressed: ((key: string, pressed: boolean) -> ())?
)
	local fWasDown = false
	local steelActive = false

	RunService.Heartbeat:Connect(function()
		if AbilityGateHelper.getCharacterId(player) ~= "Colossus" then
			fWasDown = false
			steelActive = false
			if setAbilityPressed then
				setAbilityPressed("F", false)
			end
			return
		end

		local char = player.Character
		if not char then
			return
		end

		if char:GetAttribute("IsSteelFormActive") == true then
			steelActive = true
		elseif char:GetAttribute("IsSteelFormActive") == nil then
			steelActive = false
		end

		local fDown = UserInputService:IsKeyDown(Enum.KeyCode.F)
		if fDown and not fWasDown then
			if AbilityGateHelper.canUse(player, char, ABILITY_ID) or steelActive then
				local wantEnabled = not steelActive
				steelFormToggle:FireServer(wantEnabled)
				if setAbilityPressed then
					setAbilityPressed("F", true)
					task.delay(0.12, function()
						if setAbilityPressed then
							setAbilityPressed("F", false)
						end
					end)
				end
			end
		end
		fWasDown = fDown
	end)
end

return SteelFormClient
