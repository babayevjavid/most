--!strict

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConstants = require(ReplicatedStorage.Shared.GameConstants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local SprintClient = {}

function SprintClient.init(player: Player)
	local sprintInput = Remotes.getEvent("SprintInput")
	local sprinting = false
	local dashToken = 0

	local function clearDashBoost(character: Model?)
		if not character then
			return
		end
		local root = character:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") then
			return
		end
		local boost = root:FindFirstChild("HexDashBoost")
		if boost then
			boost:Destroy()
		end
		local att = root:FindFirstChild("HexDashBoostAtt")
		if att then
			att:Destroy()
		end
	end

	--[[
		Soft directional assist: low MaxForce so Humanoid WalkSpeed still wins for steering.
		Client-applied because the local player owns character physics.
	]]
	local function applyDashBoost(dirX: number, dirZ: number, speed: number, duration: number)
		local character = player.Character
		if not character then
			return
		end
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not root or not humanoid or humanoid.Health <= 0 then
			return
		end

		local flat = Vector3.new(dirX, 0, dirZ)
		if flat.Magnitude < 0.05 then
			return
		end
		flat = flat.Unit

		clearDashBoost(character)

		-- Instant kick the client can feel immediately
		local vel = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(vel.X + flat.X * speed, vel.Y, vel.Z + flat.Z * speed)

		local att = Instance.new("Attachment")
		att.Name = "HexDashBoostAtt"
		att.Parent = root

		-- Gentle sustained assist (not a hard lock)
		local lv = Instance.new("LinearVelocity")
		lv.Name = "HexDashBoost"
		lv.Attachment0 = att
		lv.RelativeTo = Enum.ActuatorRelativeTo.World
		lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
		lv.LineDirection = flat
		lv.LineVelocity = speed * 0.55
		lv.MaxForce = 3500
		lv.Parent = root

		dashToken += 1
		local token = dashToken
		task.delay(math.max(0.08, duration * 0.55), function()
			if token ~= dashToken then
				return
			end
			clearDashBoost(player.Character)
		end)
	end

	local function setSprint(on: boolean)
		if sprinting == on then
			return
		end
		sprinting = on
		sprintInput:FireServer({ sprinting = on })
	end

	local function tryWandaDash()
		local character = player.Character
		if not character or character:GetAttribute(GameConstants.HERO_ATTRIBUTE) ~= "scarlet_witch" then
			return
		end
		if character:GetAttribute(GameConstants.IS_FLYING_ATTRIBUTE) == true then
			return
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			return
		end
		local move = humanoid.MoveDirection
		if move.Magnitude < 0.08 then
			return
		end
		sprintInput:FireServer({
			dash = true,
			moveX = move.X,
			moveZ = move.Z,
		})
	end

	sprintInput.OnClientEvent:Connect(function(payload: any)
		if type(payload) ~= "table" then
			return
		end
		if payload.clearDash == true then
			dashToken += 1
			clearDashBoost(player.Character)
			return
		end
		if payload.applyDash == true then
			applyDashBoost(
				if type(payload.dirX) == "number" then payload.dirX else 0,
				if type(payload.dirZ) == "number" then payload.dirZ else 0,
				if type(payload.speed) == "number" then payload.speed else GameConstants.HEX_DASH_SPEED,
				if type(payload.duration) == "number" then payload.duration else GameConstants.HEX_DASH_DURATION
			)
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
			setSprint(true)
		end
		-- Alt dash disabled for now
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
			setSprint(false)
		end
	end)

	player.CharacterRemoving:Connect(function(character)
		dashToken += 1
		clearDashBoost(character)
	end)
end

return SprintClient
