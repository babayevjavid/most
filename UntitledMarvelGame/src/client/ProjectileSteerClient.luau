--!strict
--[[
	While LMB is held after a steered projectile fires, send mouse aim to the server.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local STEER_INTERVAL = 0.05
local AIM_RANGE = 300

local player = Players.LocalPlayer
local steerRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(Remotes.ProjectileSteerUpdate) :: RemoteEvent

type SteerSession = {
	steerToken: string,
	heartbeatConn: RBXScriptConnection?,
	mouseUpConn: RBXScriptConnection?,
}

local sessionsByToken: { [string]: SteerSession } = {}
local mouseHeld = false

local ProjectileSteerClient = {}

function ProjectileSteerClient.getAimWorldPos(char: Model, maxRange: number?): Vector3?
	local cam = Workspace.CurrentCamera
	if not cam then
		return nil
	end
	local range = maxRange or AIM_RANGE
	local mousePos = UserInputService:GetMouseLocation()
	local ray = cam:ViewportPointToRay(mousePos.X, mousePos.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	params.IgnoreWater = true
	local result = Workspace:Raycast(ray.Origin, ray.Direction.Unit * range, params)
	if result then
		return result.Position
	end
	return ray.Origin + ray.Direction.Unit * range
end

function ProjectileSteerClient.generateSteerToken(): string
	return HttpService:GenerateGUID(false)
end

local lastSteerSendAt = 0
local lastSteerPos: Vector3? = nil

local function sendSteerUpdate(steerToken: string, targetPos: Vector3)
	local now = os.clock()
	if lastSteerPos and (now - lastSteerSendAt) < STEER_INTERVAL then
		if (targetPos - lastSteerPos).Magnitude < 0.5 then
			return
		end
	end
	lastSteerSendAt = now
	lastSteerPos = targetPos
	steerRemote:FireServer(steerToken, targetPos)
end

local function endSession(steerToken: string)
	local session = sessionsByToken[steerToken]
	if not session then
		return
	end
	sessionsByToken[steerToken] = nil
	if session.heartbeatConn then
		session.heartbeatConn:Disconnect()
	end
	if session.mouseUpConn then
		session.mouseUpConn:Disconnect()
	end
end

function ProjectileSteerClient.beginMouseSteerSession(steerToken: string)
	if steerToken == "" then
		return
	end
	endSession(steerToken)
	mouseHeld = true

	local session: SteerSession = {
		steerToken = steerToken,
		heartbeatConn = nil,
		mouseUpConn = nil,
	}
	sessionsByToken[steerToken] = session

	session.mouseUpConn = UserInputService.InputEnded:Connect(function(input, _gameProcessed)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		mouseHeld = false
		endSession(steerToken)
	end)

	session.heartbeatConn = RunService.Heartbeat:Connect(function()
		if not sessionsByToken[steerToken] or not mouseHeld then
			endSession(steerToken)
			return
		end
		local char = player.Character
		if not char or not char.Parent then
			endSession(steerToken)
			return
		end
		local aim = ProjectileSteerClient.getAimWorldPos(char, AIM_RANGE)
		if aim then
			sendSteerUpdate(steerToken, aim)
		end
	end)
end

UserInputService.InputEnded:Connect(function(input, _gameProcessed)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		mouseHeld = false
	end
end)

return ProjectileSteerClient
