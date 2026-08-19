--!strict
--[[ Client head/torso look toward camera; pauses during abilities. ]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AbilityGateHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityGateHelper"))

local RENDER_STEP = "HeadLook"
local NETWORK_INTERVAL = 0.05
local SMOOTH_TAU = 0.1

local JOINT_FACTORS: { [string]: { pitch: number, yaw: number } } = {
	Head = { pitch = 0.7, yaw = 0.65 },
	UpperTorso = { pitch = 0.35, yaw = 0.3 },
	Torso = { pitch = 0.25, yaw = 0.2 },
}

type MotorEntry = {
	motor: Motor6D,
	pitchFactor: number,
	yawFactor: number,
}

type CharacterLook = {
	motors: { MotorEntry },
	pitch: number,
	yaw: number,
	goalPitch: number,
	goalYaw: number,
}

local HeadLookClient = {}

local player: Player
local remote: RemoteEvent
local looks: { [Model]: CharacterLook } = {}
local lastSentPitch = 0 / 0
local lastSentYaw = 0 / 0
local lastNetworkSend = 0
local started = false

local function expSmooth(current: number, goal: number, dt: number): number
	local alpha = 1 - math.exp(-dt / SMOOTH_TAU)
	return current + (goal - current) * alpha
end

local function roundInterval(n: number, step: number): number
	return math.floor((n / step) + 0.5) * step
end

local function computeLookAngles(character: Model, lookVector: Vector3): (number, number)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return 0, 0
	end

	local cf = root.CFrame
	local pitch = -cf.RightVector:Dot(lookVector)
	local yaw = lookVector.Y
	local dir = math.clamp(cf.LookVector:Dot(lookVector) * 10, -1, 1)
	return pitch * dir, yaw * dir
end

local function findMotors(character: Model): { MotorEntry }
	local entries: { MotorEntry } = {}
	for _, desc in character:GetDescendants() do
		if desc:IsA("Motor6D") then
			local part1 = desc.Part1
			if part1 then
				local factors = JOINT_FACTORS[part1.Name]
				if factors then
					table.insert(entries, {
						motor = desc,
						pitchFactor = factors.pitch,
						yawFactor = factors.yaw,
					})
				end
			end
		end
	end
	return entries
end

local function bindCharacter(character: Model)
	if looks[character] then
		return
	end
	local motors = findMotors(character)
	if #motors == 0 then
		return
	end
	looks[character] = {
		motors = motors,
		pitch = 0,
		yaw = 0,
		goalPitch = 0,
		goalYaw = 0,
	}
end

local function unbindCharacter(character: Model)
	looks[character] = nil
end

local function applyMotor(entry: MotorEntry, pitch: number, yaw: number)
	local motor = entry.motor
	if not motor.Enabled or not motor.Parent then
		return
	end

	local fPitch = pitch * entry.pitchFactor
	local fYaw = yaw * entry.yawFactor
	motor.Transform = CFrame.Angles(0, fPitch, 0) * CFrame.Angles(fYaw, 0, 0)
end

local function resetMotors(state: CharacterLook)
	for _, entry in state.motors do
		if entry.motor.Parent and entry.motor.Enabled then
			entry.motor.Transform = CFrame.identity
		end
	end
end

local function onAnglesReceived(targetPlayer: Player, pitch: number, yaw: number)
	if targetPlayer == player then
		return
	end
	local character = targetPlayer.Character
	local state = character and looks[character]
	if state then
		state.goalPitch = pitch
		state.goalYaw = yaw
	end
end

local function update(dt: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local now = os.clock()
	local lookVector = camera.CFrame.LookVector

	for character, state in looks do
		if not character.Parent then
			looks[character] = nil
			continue
		end

		local owner = Players:GetPlayerFromCharacter(character)
		local isLocal = owner == player

		if isLocal then
			if AbilityGateHelper.isHeadLookBlocked(character) then
				state.goalPitch = 0
				state.goalYaw = 0
			else
				local pitch, yaw = computeLookAngles(character, lookVector)
				state.goalPitch = pitch
				state.goalYaw = yaw
			end
		elseif owner and owner:DistanceFromCharacter(camera.CFrame.Position) > 40 then
			continue
		end

		state.pitch = expSmooth(state.pitch, state.goalPitch, dt)
		state.yaw = expSmooth(state.yaw, state.goalYaw, dt)

		if math.abs(state.pitch) < 0.001 and math.abs(state.yaw) < 0.001 and math.abs(state.goalPitch) < 0.001 and math.abs(state.goalYaw) < 0.001 then
			resetMotors(state)
		else
			for _, entry in state.motors do
				applyMotor(entry, state.pitch, state.yaw)
			end
		end
	end

	local localChar = player.Character
	local localState = localChar and looks[localChar]
	if localState and now - lastNetworkSend >= NETWORK_INTERVAL then
		local netPitch = roundInterval(localState.goalPitch, 0.01)
		local netYaw = roundInterval(localState.goalYaw, 0.01)
		if netPitch ~= lastSentPitch or netYaw ~= lastSentYaw then
			lastSentPitch = netPitch
			lastSentYaw = netYaw
			lastNetworkSend = now
			remote:FireServer(netPitch, netYaw)
		end
	end
end

local function trackPlayer(plr: Player)
	local function onCharacterAdded(character: Model)
		task.defer(function()
			bindCharacter(character)
		end)
	end

	plr.CharacterAdded:Connect(onCharacterAdded)
	plr.CharacterRemoving:Connect(unbindCharacter)
	if plr.Character then
		onCharacterAdded(plr.Character)
	end
end

function HeadLookClient.start(localPlayer: Player)
	if started then
		return
	end
	started = true
	player = localPlayer

	remote = ReplicatedStorage:WaitForChild("HeadLookAngles") :: RemoteEvent
	remote.OnClientEvent:Connect(onAnglesReceived)

	trackPlayer(localPlayer)
	for _, plr in Players:GetPlayers() do
		if plr ~= localPlayer then
			trackPlayer(plr)
		end
	end
	Players.PlayerAdded:Connect(function(plr)
		if plr ~= localPlayer then
			trackPlayer(plr)
		end
	end)

	RunService:BindToRenderStep(RENDER_STEP, Enum.RenderPriority.Last.Value, update)
end

return HeadLookClient
