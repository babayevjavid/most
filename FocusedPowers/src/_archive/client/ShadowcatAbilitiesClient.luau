--!strict
--[[ Shadowcat abilities client ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local AbilityGateHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityGateHelper"))
local ShadowcatConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ShadowcatConstants"))
local AbilityInputHelper = require(script.Parent:WaitForChild("AbilityInputHelper"))

local C = ShadowcatConstants

local ShadowcatAbilitiesClient = {}

function ShadowcatAbilitiesClient.start(
	phasingRemote: RemoteEvent,
	clawRemote: RemoteEvent,
	pounceRemote: RemoteEvent,
	wallAscensionRemote: RemoteEvent,
	disruptiveTouchRemote: RemoteEvent,
	player: Player,
	setAbilityPressed: ((string, boolean) -> ())?
)
	local mouse = player:GetMouse()
	local fHeld, eWas, cWas, qHeld, tWas = false, false, false, false, false

	RunService.Heartbeat:Connect(function()
		if AbilityGateHelper.getCharacterId(player) ~= "Shadowcat" then
			fHeld, eWas, cWas, qHeld, tWas = false, false, false, false, false
			return
		end
		local char = player.Character
		local cam = workspace.CurrentCamera
		if not char or not cam then
			return
		end
		local look = cam.CFrame.LookVector.Unit

		local fDown = UserInputService:IsKeyDown(Enum.KeyCode.F)
		if fDown and not fHeld then
			if AbilityGateHelper.canUse(player, char, C.Phasing.ABILITY_ID) then
				phasingRemote:FireServer(true)
				if setAbilityPressed then setAbilityPressed("F", true) end
				fHeld = true
			end
		elseif not fDown and fHeld then
			phasingRemote:FireServer(false)
			if setAbilityPressed then setAbilityPressed("F", false) end
			fHeld = false
		end

		local eDown = UserInputService:IsKeyDown(Enum.KeyCode.E)
		if eDown and not eWas then
			if AbilityGateHelper.canUse(player, char, C.ClawRush.ABILITY_ID) then
				clawRemote:FireServer()
				if setAbilityPressed then
					setAbilityPressed("E", true)
					task.delay(0.15, function()
						if setAbilityPressed then setAbilityPressed("E", false) end
					end)
				end
			end
		end
		eWas = eDown

		local cDown = UserInputService:IsKeyDown(Enum.KeyCode.C)
		if cDown and not cWas then
			if AbilityGateHelper.canUse(player, char, C.ShadowPounce.ABILITY_ID) then
				local target = AbilityInputHelper.getPlayerUnderMouse(char, mouse)
				if target then
					pounceRemote:FireServer(target.UserId)
					if setAbilityPressed then
						setAbilityPressed("C", true)
						task.delay(0.15, function()
							if setAbilityPressed then setAbilityPressed("C", false) end
						end)
					end
				end
			end
		end
		cWas = cDown

		local qDown = UserInputService:IsKeyDown(Enum.KeyCode.Q)
		if qDown then
			if not qHeld then
				if AbilityGateHelper.canUse(player, char, C.WallAscension.ABILITY_ID) then
					local right = cam.CFrame.RightVector.Unit
					local w = UserInputService:IsKeyDown(Enum.KeyCode.W)
					local s = UserInputService:IsKeyDown(Enum.KeyCode.S)
					local a = UserInputService:IsKeyDown(Enum.KeyCode.A)
					local d = UserInputService:IsKeyDown(Enum.KeyCode.D)
					local move = look * ((if w then 1 else 0) - (if s then 1 else 0))
						+ right * ((if d then 1 else 0) - (if a then 1 else 0))
					if move.Magnitude > 1 then
						move = move.Unit
					elseif move.Magnitude < 0.01 then
						move = look
					end
					wallAscensionRemote:FireServer(true, look.X, look.Y, look.Z, move.X, move.Y, move.Z)
					if setAbilityPressed then setAbilityPressed("Q", true) end
					qHeld = true
				end
			else
				local right = cam.CFrame.RightVector.Unit
				local w = UserInputService:IsKeyDown(Enum.KeyCode.W)
				local s = UserInputService:IsKeyDown(Enum.KeyCode.S)
				local a = UserInputService:IsKeyDown(Enum.KeyCode.A)
				local d = UserInputService:IsKeyDown(Enum.KeyCode.D)
				local move = look * ((if w then 1 else 0) - (if s then 1 else 0))
					+ right * ((if d then 1 else 0) - (if a then 1 else 0))
				if move.Magnitude > 1 then
					move = move.Unit
				elseif move.Magnitude < 0.01 then
					move = look
				end
				wallAscensionRemote:FireServer(true, look.X, look.Y, look.Z, move.X, move.Y, move.Z)
			end
		elseif not qDown and qHeld then
			wallAscensionRemote:FireServer(false, look.X, look.Y, look.Z, 0, 0, 0)
			if setAbilityPressed then setAbilityPressed("Q", false) end
			qHeld = false
		end

		local tDown = UserInputService:IsKeyDown(Enum.KeyCode.T)
		if tDown and not tWas then
			if AbilityGateHelper.canUse(player, char, C.DisruptiveTouch.ABILITY_ID) then
				disruptiveTouchRemote:FireServer(look.X, look.Y, look.Z)
				if setAbilityPressed then
					setAbilityPressed("T", true)
					task.delay(0.15, function()
						if setAbilityPressed then setAbilityPressed("T", false) end
					end)
				end
			end
		end
		tWas = tDown
	end)
end

return ShadowcatAbilitiesClient
