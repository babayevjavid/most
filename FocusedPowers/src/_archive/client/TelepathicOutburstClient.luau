--!strict
--[[
	Telepathic Outburst (T): hold to charge, release expanding shockwave.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local AbilityGateHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityGateHelper"))
local TelepathicOutburstConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TelepathicOutburstConstants"))

local ABILITY_ID = TelepathicOutburstConstants.ABILITY_ID

local TelepathicOutburstClient = {}

function TelepathicOutburstClient.start(
	releaseRemote: RemoteEvent,
	player: Player,
	setAbilityPressed: ((key: string, pressed: boolean) -> ())?,
	setAbilityCharge: ((key: string, ratio: number) -> ())?
)
	local tHeld = false
	local chargeStart = 0
	local fired = false

	RunService.Heartbeat:Connect(function()
		if not AbilityGateHelper.isJeanGrey(player) then
			tHeld = false
			fired = false
			if setAbilityPressed then
				setAbilityPressed("T", false)
			end
			if setAbilityCharge then
				setAbilityCharge("T", 0)
			end
			return
		end

		local char = player.Character
		if not char then
			return
		end

		local isDown = UserInputService:IsKeyDown(Enum.KeyCode.T)
		local now = tick()

		if isDown and not tHeld then
			if AbilityGateHelper.canUse(player, char, ABILITY_ID) then
				chargeStart = now
				fired = false
				if setAbilityPressed then
					setAbilityPressed("T", true)
				end
			end
			tHeld = true
		elseif not isDown and tHeld then
			if not fired and chargeStart > 0 then
				local elapsed = now - chargeStart
				local alpha = math.clamp(elapsed / TelepathicOutburstConstants.CHARGE_MAX_SEC, 0, 1)
				releaseRemote:FireServer(alpha)

				local cam = workspace.CurrentCamera
				if cam then
					local startFov = cam.FieldOfView
					TweenService:Create(
						cam,
						TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
						{ FieldOfView = startFov + 8 + alpha * 6 }
					):Play()
					task.delay(0.25, function()
						if cam.Parent then
							TweenService:Create(
								cam,
								TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
								{ FieldOfView = startFov }
							):Play()
						end
					end)
				end
				fired = true
			end
			tHeld = false
			chargeStart = 0
			if setAbilityPressed then
				setAbilityPressed("T", false)
			end
			if setAbilityCharge then
				setAbilityCharge("T", 0)
			end
		end

		if tHeld and chargeStart > 0 and not fired then
			local elapsed = now - chargeStart
			local alpha = math.clamp(elapsed / TelepathicOutburstConstants.CHARGE_MAX_SEC, 0, 1)
			if setAbilityCharge then
				setAbilityCharge("T", alpha)
			end
			if alpha >= 1 and not fired then
				releaseRemote:FireServer(1)
				fired = true
				if setAbilityPressed then
					setAbilityPressed("T", false)
				end
				if setAbilityCharge then
					setAbilityCharge("T", 0)
				end
				tHeld = false
				chargeStart = 0
			end
		end
	end)
end

return TelepathicOutburstClient
