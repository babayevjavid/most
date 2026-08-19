--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))

local PlayerStateService = require(script.Parent.PlayerStateService)

local SprintService = {}

local sprinting: { [Player]: boolean } = {}
local onStatUpdate: ((player: Player) -> ())? = nil

function SprintService.setup(statCallback: (player: Player) -> ())
	onStatUpdate = statCallback
end

function SprintService.setSprinting(player: Player, wantsSprint: boolean)
	if not PlayerStateService.get(player).HeroId then
		sprinting[player] = false
		SprintService.applyWalkSpeed(player)
		return
	end
	sprinting[player] = wantsSprint
	SprintService.applyWalkSpeed(player)
end

function SprintService.forceStopSprint(player: Player)
	sprinting[player] = false
	SprintService.applyWalkSpeed(player)
end

function SprintService.applyWalkSpeed(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	if character and (character:GetAttribute("IsLevitating") == true or character:GetAttribute("NewFlightActive") == true) then
		return
	end

	local state = PlayerStateService.get(player)
	if not state.HeroId then
		humanoid.WalkSpeed = Constants.WALK_SPEED
		return
	end

	local wantsSprint = sprinting[player] == true
	local canSprint = state.Stamina >= Constants.SPRINT_MIN_STAMINA
	if wantsSprint and canSprint then
		humanoid.WalkSpeed = Constants.SPRINT_SPEED
	else
		humanoid.WalkSpeed = Constants.WALK_SPEED
		if not canSprint then
			sprinting[player] = false
		end
	end
end

function SprintService.clearPlayer(player: Player)
	sprinting[player] = nil
end

function SprintService.startLoop()
	RunService.Heartbeat:Connect(function(dt)
		for player, isSprinting in sprinting do
			if not isSprinting or not player.Parent then
				continue
			end

			local state = PlayerStateService.get(player)
			if not state.HeroId then
				continue
			end

			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if not humanoid or humanoid.Health <= 0 then
				continue
			end

			if character and (character:GetAttribute("IsLevitating") == true or character:GetAttribute("NewFlightActive") == true) then
				sprinting[player] = false
				continue
			end

			if humanoid.MoveDirection.Magnitude <= 0.05 then
				continue
			end

			state.Stamina = math.max(0, state.Stamina - Constants.SPRINT_STAMINA_DRAIN * dt)
			PlayerStateService.markResourceUsed(player)
			if state.Stamina <= 0 then
				sprinting[player] = false
				SprintService.applyWalkSpeed(player)
			end

			if onStatUpdate then
				onStatUpdate(player)
			end
		end
	end)
end

return SprintService
