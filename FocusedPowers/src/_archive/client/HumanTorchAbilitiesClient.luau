--!strict
--[[ Human Torch abilities client ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local AbilityGateHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityGateHelper"))
local HumanTorchConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("HumanTorchConstants"))
local SteerableBoltClient = require(script.Parent:WaitForChild("SteerableBoltClient"))
local TelekineticFlightConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TelekineticFlightConstants"))

local C = HumanTorchConstants
local TOGGLE_DEBOUNCE = TelekineticFlightConstants.TOGGLE_DEBOUNCE

local HumanTorchAbilitiesClient = {}

function HumanTorchAbilitiesClient.start(
	flightToggle: RemoteEvent,
	flightInput: RemoteEvent,
	fireballStart: RemoteEvent,
	fireballAim: RemoteEvent,
	fireballRelease: RemoteEvent,
	novaRemote: RemoteEvent,
	fireRushRemote: RemoteEvent,
	infernoRemote: RemoteEvent,
	player: Player,
	setAbilityPressed: ((string, boolean) -> ())?,
	setAbilityCharge: ((string, number) -> ())?
)
	SteerableBoltClient.bind(player, {
		abilityId = C.Fireball.ABILITY_ID,
		keyCode = Enum.KeyCode.E,
		hudKey = "E",
		aimInterval = C.Fireball.AIM_INTERVAL,
		canUse = function(p, character)
			return AbilityGateHelper.getCharacterId(p) == "HumanTorch"
				and AbilityGateHelper.canUse(p, character, C.Fireball.ABILITY_ID)
		end,
		startRemote = fireballStart,
		aimRemote = fireballAim,
		releaseRemote = fireballRelease,
		setAbilityPressed = setAbilityPressed,
	})

	local lastFToggle, fWasDown = 0, false
	local cWas, qWas = false, false
	local tHeld, chargeStart, fired = false, 0, false

	RunService.Heartbeat:Connect(function()
		if AbilityGateHelper.getCharacterId(player) ~= "HumanTorch" then
			tHeld, fired = false, false
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
		local flying = char:GetAttribute("IsFlameFlying") == true
		if fDown and not fWasDown and now - lastFToggle >= TOGGLE_DEBOUNCE then
			lastFToggle = now
			if flying then
				flightToggle:FireServer(false)
				if setAbilityPressed then setAbilityPressed("F", false) end
			elseif AbilityGateHelper.canUse(player, char, C.FlameFlight.ABILITY_ID) then
				flightToggle:FireServer(true)
				if setAbilityPressed then setAbilityPressed("F", true) end
			end
		end
		fWasDown = fDown

		if flying then
			if setAbilityPressed then setAbilityPressed("F", true) end
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
				move = Vector3.zero
			end
			flightInput:FireServer(move.X, move.Y, move.Z, look.X, look.Y, look.Z, 0)
		end

		local cDown = UserInputService:IsKeyDown(Enum.KeyCode.C)
		if cDown and not cWas and AbilityGateHelper.canUse(player, char, C.NovaBurst.ABILITY_ID) then
			novaRemote:FireServer()
			if setAbilityPressed then
				setAbilityPressed("C", true)
				task.delay(0.12, function()
					if setAbilityPressed then setAbilityPressed("C", false) end
				end)
			end
		end
		cWas = cDown

		local qDown = UserInputService:IsKeyDown(Enum.KeyCode.Q)
		if qDown and not qWas and AbilityGateHelper.canUse(player, char, C.FireRush.ABILITY_ID) then
			fireRushRemote:FireServer(look.X, look.Y, look.Z)
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
			if AbilityGateHelper.canUse(player, char, C.Inferno.ABILITY_ID) then
				chargeStart = now
				fired = false
				if setAbilityPressed then setAbilityPressed("T", true) end
			end
			tHeld = true
		elseif not tDown and tHeld then
			if not fired and chargeStart > 0 then
				infernoRemote:FireServer(math.clamp((now - chargeStart) / C.Inferno.CHARGE_MAX_SEC, 0, 1))
				fired = true
			end
			tHeld = false
			chargeStart = 0
			if setAbilityPressed then setAbilityPressed("T", false) end
			if setAbilityCharge then setAbilityCharge("T", 0) end
		end
		if tHeld and chargeStart > 0 and not fired then
			local alpha = math.clamp((now - chargeStart) / C.Inferno.CHARGE_MAX_SEC, 0, 1)
			if setAbilityCharge then setAbilityCharge("T", alpha) end
			if alpha >= 1 and not fired then
				infernoRemote:FireServer(1)
				fired = true
				tHeld = false
				chargeStart = 0
				if setAbilityPressed then setAbilityPressed("T", false) end
				if setAbilityCharge then setAbilityCharge("T", 0) end
			end
		end
	end)
end

return HumanTorchAbilitiesClient
