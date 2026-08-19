--!strict
--[[ Iceman abilities client ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local AbilityGateHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityGateHelper"))
local IcemanConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("IcemanConstants"))
local SteerableBoltClient = require(script.Parent:WaitForChild("SteerableBoltClient"))

local C = IcemanConstants

local IcemanAbilitiesClient = {}

function IcemanAbilitiesClient.start(
	slideRemote: RemoteEvent,
	frostBoltStart: RemoteEvent,
	frostBoltAim: RemoteEvent,
	frostBoltRelease: RemoteEvent,
	wallRemote: RemoteEvent,
	zeroRemote: RemoteEvent,
	blizzardRemote: RemoteEvent,
	player: Player,
	setAbilityPressed: ((string, boolean) -> ())?,
	setAbilityCharge: ((string, number) -> ())?
)
	SteerableBoltClient.bind(player, {
		abilityId = C.FrostBolt.ABILITY_ID,
		keyCode = Enum.KeyCode.E,
		hudKey = "E",
		aimInterval = C.FrostBolt.AIM_INTERVAL,
		canUse = function(p, character)
			return AbilityGateHelper.getCharacterId(p) == "Iceman"
				and AbilityGateHelper.canUse(p, character, C.FrostBolt.ABILITY_ID)
		end,
		startRemote = frostBoltStart,
		aimRemote = frostBoltAim,
		releaseRemote = frostBoltRelease,
		setAbilityPressed = setAbilityPressed,
	})

	local fHeld, cWas, qWas = false, false, false
	local tHeld, chargeStart, fired = false, 0, false

	RunService.Heartbeat:Connect(function()
		if AbilityGateHelper.getCharacterId(player) ~= "Iceman" then
			fHeld, tHeld, fired = false, false, false
			if setAbilityCharge then setAbilityCharge("T", 0) end
			return
		end
		local char = player.Character
		local cam = workspace.CurrentCamera
		if not char or not cam then
			return
		end
		local now = tick()
		local look = cam.CFrame.LookVector.Unit

		local fDown = UserInputService:IsKeyDown(Enum.KeyCode.F)
		if fDown then
			if not fHeld then
				if AbilityGateHelper.canUse(player, char, C.IceSlide.ABILITY_ID) then
					slideRemote:FireServer(true, look.X, look.Y, look.Z)
					if setAbilityPressed then setAbilityPressed("F", true) end
					fHeld = true
				end
			else
				slideRemote:FireServer(true, look.X, look.Y, look.Z)
			end
		elseif not fDown and fHeld then
			slideRemote:FireServer(false, look.X, look.Y, look.Z)
			if setAbilityPressed then setAbilityPressed("F", false) end
			fHeld = false
		end

		local cDown = UserInputService:IsKeyDown(Enum.KeyCode.C)
		if cDown and not cWas and AbilityGateHelper.canUse(player, char, C.IceWall.ABILITY_ID) then
			wallRemote:FireServer()
			if setAbilityPressed then
				setAbilityPressed("C", true)
				task.delay(0.12, function()
					if setAbilityPressed then setAbilityPressed("C", false) end
				end)
			end
		end
		cWas = cDown

		local qDown = UserInputService:IsKeyDown(Enum.KeyCode.Q)
		if qDown and not qWas and AbilityGateHelper.canUse(player, char, C.AbsoluteZero.ABILITY_ID) then
			zeroRemote:FireServer()
			if setAbilityPressed then
				setAbilityPressed("Q", true)
				task.delay(0.12, function()
					if setAbilityPressed then setAbilityPressed("Q", false) end
				end)
			end
		end
		qWas = qDown

		local tDown = UserInputService:IsKeyDown(Enum.KeyCode.T)
		if tDown and not tHeld then
			if AbilityGateHelper.canUse(player, char, C.Blizzard.ABILITY_ID) then
				chargeStart = now
				fired = false
				if setAbilityPressed then setAbilityPressed("T", true) end
			end
			tHeld = true
		elseif not tDown and tHeld then
			if not fired and chargeStart > 0 then
				blizzardRemote:FireServer(math.clamp((now - chargeStart) / C.Blizzard.CHARGE_MAX_SEC, 0, 1))
				fired = true
			end
			tHeld = false
			chargeStart = 0
			if setAbilityPressed then setAbilityPressed("T", false) end
			if setAbilityCharge then setAbilityCharge("T", 0) end
		end
		if tHeld and chargeStart > 0 and not fired then
			local alpha = math.clamp((now - chargeStart) / C.Blizzard.CHARGE_MAX_SEC, 0, 1)
			if setAbilityCharge then setAbilityCharge("T", alpha) end
			if alpha >= 1 and not fired then
				blizzardRemote:FireServer(1)
				fired = true
				tHeld = false
				chargeStart = 0
				if setAbilityPressed then setAbilityPressed("T", false) end
				if setAbilityCharge then setAbilityCharge("T", 0) end
			end
		end
	end)
end

return IcemanAbilitiesClient
