--!strict
--[[
	Cloak F/E/C/Q abilities client.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local AbilityGateHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityGateHelper"))
local DarkBindingConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DarkBindingConstants"))
local DarkforceStepConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DarkforceStepConstants"))
local ShadowCloakConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ShadowCloakConstants"))
local TerrorVeilConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TerrorVeilConstants"))
local AbilityInputHelper = require(script.Parent:WaitForChild("AbilityInputHelper"))

local CloakAbilitiesClient = {}

function CloakAbilitiesClient.start(
	stepRemote: RemoteEvent,
	veilRemote: RemoteEvent,
	cloakRemote: RemoteEvent,
	bindRemote: RemoteEvent,
	player: Player,
	setAbilityPressed: ((key: string, pressed: boolean) -> ())?
)
	local mouse = player:GetMouse()
	local fWas, eWas, cWas, qWas = false, false, false, false

	RunService.Heartbeat:Connect(function()
		if not AbilityGateHelper.isCloak(player) then
			fWas, eWas, cWas, qWas = false, false, false, false
			return
		end
		local char = player.Character
		local cam = workspace.CurrentCamera
		if not char or not cam then
			return
		end

		local fDown = UserInputService:IsKeyDown(Enum.KeyCode.F)
		if fDown and not fWas then
			if AbilityGateHelper.canUse(player, char, DarkforceStepConstants.ABILITY_ID) then
				local aim = AbilityInputHelper.getAimDirection(char, cam)
				stepRemote:FireServer(aim.X, aim.Y, aim.Z)
				if setAbilityPressed then
					setAbilityPressed("F", true)
					task.delay(0.12, function()
						if setAbilityPressed then setAbilityPressed("F", false) end
					end)
				end
			end
		end
		fWas = fDown

		local eDown = UserInputService:IsKeyDown(Enum.KeyCode.E)
		if eDown and not eWas then
			if AbilityGateHelper.canUse(player, char, TerrorVeilConstants.ABILITY_ID) then
				veilRemote:FireServer()
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
		if cDown and not cWas then
			if AbilityGateHelper.canUse(player, char, ShadowCloakConstants.ABILITY_ID) then
				cloakRemote:FireServer()
				if setAbilityPressed then
					setAbilityPressed("C", true)
					task.delay(0.12, function()
						if setAbilityPressed then setAbilityPressed("C", false) end
					end)
				end
			end
		end
		cWas = cDown

		local qDown = UserInputService:IsKeyDown(Enum.KeyCode.Q)
		if qDown and not qWas then
			if AbilityGateHelper.canUse(player, char, DarkBindingConstants.ABILITY_ID) then
				local target = AbilityInputHelper.getPlayerUnderMouse(char, mouse)
				if target then
					bindRemote:FireServer(target.UserId)
					if setAbilityPressed then
						setAbilityPressed("Q", true)
						task.delay(0.12, function()
							if setAbilityPressed then setAbilityPressed("Q", false) end
						end)
					end
				end
			end
		end
		qWas = qDown
	end)
end

return CloakAbilitiesClient
