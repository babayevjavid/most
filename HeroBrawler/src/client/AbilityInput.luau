--!strict

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MouseHelper = require(script.Parent.MouseHelper)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local MonetConstants = require(ReplicatedStorage.Shared.MonetConstants)

local AbilityInput = {}

local KEY_MAP = {
	[Enum.KeyCode.Q] = "Q",
	[Enum.KeyCode.F] = "F",
	[Enum.KeyCode.R] = "R",
	[Enum.KeyCode.T] = "T",
	[Enum.KeyCode.E] = "E",
}

local fHeld = false
local tHeld = false

local function getCameraFlatMove(): Vector3
	local camera = workspace.CurrentCamera
	if not camera then
		return Vector3.zero
	end

	local look = camera.CFrame.LookVector
	local right = camera.CFrame.RightVector
	look = Vector3.new(look.X, 0, look.Z)
	right = Vector3.new(right.X, 0, right.Z)
	if look.Magnitude > 0.01 then
		look = look.Unit
	else
		look = Vector3.new(0, 0, -1)
	end
	if right.Magnitude > 0.01 then
		right = right.Unit
	else
		right = Vector3.new(1, 0, 0)
	end

	local w = if UserInputService:IsKeyDown(Enum.KeyCode.W) then 1 else 0
	local s = if UserInputService:IsKeyDown(Enum.KeyCode.S) then 1 else 0
	local a = if UserInputService:IsKeyDown(Enum.KeyCode.A) then 1 else 0
	local d = if UserInputService:IsKeyDown(Enum.KeyCode.D) then 1 else 0

	local move = look * (w - s) + right * (d - a)
	if move.Magnitude > 1 then
		return move.Unit
	end
	if move.Magnitude < 0.05 then
		return Vector3.zero
	end
	return move
end

local function isFlying(player: Player): boolean
	local character = player.Character
	return character ~= nil and character:GetAttribute(MonetConstants.IS_FLYING_ATTRIBUTE) == true
end

function AbilityInput.init(player: Player)
	local useAbility = Remotes.getEvent("UseAbility")

	local function send(action: string, moveVector: Vector3?)
		useAbility:FireServer({
			action = action,
			direction = MouseHelper.getWorldDirection(player),
			moveVector = moveVector or getCameraFlatMove(),
		})
	end

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		local key = KEY_MAP[input.KeyCode]
		if not key then
			return
		end

		local flying = isFlying(player)

		if key == "F" then
			if flying then
				return
			end
			fHeld = true
			send("F_down")
		elseif key == "T" then
			if flying then
				return
			end
			tHeld = true
			send("T_down")
		elseif key == "E" then
			send("E")
		elseif key == "R" then
			send("R")
		elseif key == "Q" then
			send("Q")
		end
	end)

	UserInputService.InputEnded:Connect(function(input, _gameProcessed)
		if input.KeyCode == Enum.KeyCode.F and fHeld then
			fHeld = false
			if not isFlying(player) then
				send("F_up")
			end
		elseif input.KeyCode == Enum.KeyCode.T and tHeld then
			tHeld = false
			if not isFlying(player) then
				send("T_up")
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(0.05)
			if fHeld and not isFlying(player) then
				send("F_move", getCameraFlatMove())
			end
		end
	end)
end

return AbilityInput
