--!strict
--[[ Psylocke F/E/C/Q/T abilities client. ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local AbilityGateHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityGateHelper"))
local PsylockeConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PsylockeConstants"))
local AbilityInputHelper = require(script.Parent:WaitForChild("AbilityInputHelper"))

local PSI_BLADE = PsylockeConstants.PsiBlade
local BUTTERFLY = PsylockeConstants.ButterflyStep
local SLASH = PsylockeConstants.PsychicSlash
local FIELD = PsylockeConstants.FocusField
local ASTRAL = PsylockeConstants.AstralAssault

local PsylockeAbilitiesClient = {}

local function pressFeedback(setAbilityPressed: ((key: string, pressed: boolean) -> ())?, key: string)
	if not setAbilityPressed then
		return
	end
	setAbilityPressed(key, true)
	task.delay(0.12, function()
		if setAbilityPressed then
			setAbilityPressed(key, false)
		end
	end)
end

function PsylockeAbilitiesClient.start(
	psiBladeRemote: RemoteEvent,
	butterflyRemote: RemoteEvent,
	slashRemote: RemoteEvent,
	focusRemote: RemoteEvent,
	astralRemote: RemoteEvent,
	player: Player,
	setAbilityPressed: ((key: string, pressed: boolean) -> ())?
)
	local fWas, eWas, cWas, qWas, tWas = false, false, false, false, false

	RunService.Heartbeat:Connect(function()
		if not AbilityGateHelper.isPsylocke(player) then
			fWas, eWas, cWas, qWas, tWas = false, false, false, false, false
			return
		end
		local char = player.Character
		local cam = workspace.CurrentCamera
		if not char or not cam then
			return
		end

		local fDown = UserInputService:IsKeyDown(Enum.KeyCode.F)
		if fDown and not fWas then
			if AbilityGateHelper.canUse(player, char, PSI_BLADE.ABILITY_ID) then
				psiBladeRemote:FireServer()
				pressFeedback(setAbilityPressed, "F")
			end
		end
		fWas = fDown

		local eDown = UserInputService:IsKeyDown(Enum.KeyCode.E)
		if eDown and not eWas then
			if AbilityGateHelper.canUse(player, char, BUTTERFLY.ABILITY_ID) then
				local aim = AbilityInputHelper.getAimDirection(char, cam)
				butterflyRemote:FireServer(aim.X, aim.Y, aim.Z)
				pressFeedback(setAbilityPressed, "E")
			end
		end
		eWas = eDown

		local cDown = UserInputService:IsKeyDown(Enum.KeyCode.C)
		if cDown and not cWas then
			if AbilityGateHelper.canUse(player, char, SLASH.ABILITY_ID) then
				slashRemote:FireServer()
				pressFeedback(setAbilityPressed, "C")
			end
		end
		cWas = cDown

		local qDown = UserInputService:IsKeyDown(Enum.KeyCode.Q)
		if qDown and not qWas then
			if AbilityGateHelper.canUse(player, char, FIELD.ABILITY_ID) then
				focusRemote:FireServer()
				pressFeedback(setAbilityPressed, "Q")
			end
		end
		qWas = qDown

		local tDown = UserInputService:IsKeyDown(Enum.KeyCode.T)
		if tDown and not tWas then
			if AbilityGateHelper.canUse(player, char, ASTRAL.ABILITY_ID) then
				astralRemote:FireServer()
				pressFeedback(setAbilityPressed, "T")
			end
		end
		tWas = tDown
	end)
end

return PsylockeAbilitiesClient
