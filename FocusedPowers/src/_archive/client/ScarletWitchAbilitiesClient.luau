--!strict

--[[ Scarlet Witch abilities client ]]



local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RunService = game:GetService("RunService")

local TweenService = game:GetService("TweenService")

local UserInputService = game:GetService("UserInputService")



local AbilityGateHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityGateHelper"))

local ScarletWitchConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ScarletWitchConstants"))

local SteerableBoltClient = require(script.Parent:WaitForChild("SteerableBoltClient"))

local C = ScarletWitchConstants



local ScarletWitchAbilitiesClient = {}



local function getMouseWorldPos(): Vector3?

	local cam = workspace.CurrentCamera

	if not cam then

		return nil

	end

	local mouse = game:GetService("Players").LocalPlayer:GetMouse()

	local ray = cam:ScreenPointToRay(mouse.X, mouse.Y)

	local params = RaycastParams.new()

	params.FilterType = Enum.RaycastFilterType.Exclude

	local char = game:GetService("Players").LocalPlayer.Character

	if char then

		params.FilterDescendantsInstances = { char }

	end

	local hit = workspace:Raycast(ray.Origin, ray.Direction * 200, params)

	return if hit then hit.Position else ray.Origin + ray.Direction * 50

end



function ScarletWitchAbilitiesClient.start(

	teleportRemote: RemoteEvent,

	warpRemote: RemoteEvent,

	hexBoltStart: RemoteEvent,

	hexBoltAim: RemoteEvent,

	hexBoltRelease: RemoteEvent,

	shieldRemote: RemoteEvent,

	waveRemote: RemoteEvent,

	player: Player,

	setAbilityPressed: ((string, boolean) -> ())?,

	setAbilityCharge: ((string, number) -> ())?

)

	SteerableBoltClient.bind(player, {

		abilityId = C.HexBolt.ABILITY_ID,

		keyCode = Enum.KeyCode.C,

		hudKey = "C",

		aimInterval = C.HexBolt.AIM_INTERVAL,

		canUse = function(p, character)

			return AbilityGateHelper.getCharacterId(p) == "ScarletWitch"

				and AbilityGateHelper.canUse(p, character, C.HexBolt.ABILITY_ID)

		end,

		startRemote = hexBoltStart,

		aimRemote = hexBoltAim,

		releaseRemote = hexBoltRelease,

		setAbilityPressed = setAbilityPressed,

	})



	local fHeld, eWas, qHeld = false, false, false

	local fChargeStart = 0

	local tHeld, chargeStart, fired = false, 0, false



	RunService.Heartbeat:Connect(function()

		if AbilityGateHelper.getCharacterId(player) ~= "ScarletWitch" then

			tHeld, fired, qHeld = false, false, false

			if setAbilityCharge then setAbilityCharge("T", 0) end

			return

		end

		local char = player.Character

		if not char then

			return

		end

		local now = tick()



		local fDown = UserInputService:IsKeyDown(Enum.KeyCode.F)

		if fDown and not fHeld then

			if AbilityGateHelper.canUse(player, char, C.Teleportation.ABILITY_ID) then

				fChargeStart = now

				if setAbilityPressed then setAbilityPressed("F", true) end

			end

			fHeld = true

		elseif not fDown and fHeld then

			if fChargeStart > 0 then

				local pos = getMouseWorldPos()

				if pos then

					local alpha = math.clamp((now - fChargeStart) / C.Teleportation.CHARGE_MAX_SEC, 0, 1)

					teleportRemote:FireServer(pos.X, pos.Y, pos.Z, alpha)

				end

			end

			fHeld = false

			fChargeStart = 0

			if setAbilityPressed then setAbilityPressed("F", false) end

		end



		local eDown = UserInputService:IsKeyDown(Enum.KeyCode.E)

		if eDown and not eWas and AbilityGateHelper.canUse(player, char, C.RealityWarp.ABILITY_ID) then

			local pos = getMouseWorldPos()

			if pos then

				warpRemote:FireServer(pos.X, pos.Y, pos.Z)

				if setAbilityPressed then

					setAbilityPressed("E", true)

					task.delay(0.12, function()

						if setAbilityPressed then setAbilityPressed("E", false) end

					end)

				end

			end

		end

		eWas = eDown



		local qDown = UserInputService:IsKeyDown(Enum.KeyCode.Q)

		if qDown and not qHeld then

			if AbilityGateHelper.canUse(player, char, C.ProbabilityShield.ABILITY_ID) then

				shieldRemote:FireServer(true)

				if setAbilityPressed then setAbilityPressed("Q", true) end

				qHeld = true

			end

		elseif not qDown and qHeld then

			shieldRemote:FireServer(false)

			if setAbilityPressed then setAbilityPressed("Q", false) end

			qHeld = false

		end



		local tDown = UserInputService:IsKeyDown(Enum.KeyCode.T)

		if tDown and not tHeld then

			if AbilityGateHelper.canUse(player, char, C.ChaosWave.ABILITY_ID) then

				chargeStart = now

				fired = false

				if setAbilityPressed then setAbilityPressed("T", true) end

			end

			tHeld = true

		elseif not tDown and tHeld then

			if not fired and chargeStart > 0 then

				local alpha = math.clamp((now - chargeStart) / C.ChaosWave.CHARGE_MAX_SEC, 0, 1)

				waveRemote:FireServer(alpha)

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

			if setAbilityPressed then setAbilityPressed("T", false) end

			if setAbilityCharge then setAbilityCharge("T", 0) end

		end

		if tHeld and chargeStart > 0 and not fired then

			local alpha = math.clamp((now - chargeStart) / C.ChaosWave.CHARGE_MAX_SEC, 0, 1)

			if setAbilityCharge then setAbilityCharge("T", alpha) end

			if alpha >= 1 and not fired then

				waveRemote:FireServer(1)

				fired = true

				tHeld = false

				chargeStart = 0

				if setAbilityPressed then setAbilityPressed("T", false) end

				if setAbilityCharge then setAbilityCharge("T", 0) end

			end

		end

	end)

end



return ScarletWitchAbilitiesClient

