--!strict
--[[ Server-authoritative day/night cycle: lighting + workspace attributes for HUD / Sunspot. ]]

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AdminHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AdminHelper"))
local DayCycleConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DayCycleConstants"))
local DayCycleHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DayCycleHelper"))

local C = DayCycleConstants

local DayCycleService = {}

local clockTime = C.START_CLOCK_TIME
local started = false
local paused = false

local function publishState()
	Workspace:SetAttribute(C.WORKSPACE_CLOCK_ATTR, clockTime)
	Workspace:SetAttribute(C.WORKSPACE_SOLAR_ATTR, DayCycleHelper.getSolarIntensity(clockTime))
	Workspace:SetAttribute(C.WORKSPACE_PHASE_ATTR, DayCycleHelper.getPhase(clockTime))
	Workspace:SetAttribute(C.WORKSPACE_PAUSED_ATTR, paused)
end

local function applyLighting()
	local sample = DayCycleHelper.sampleLighting(clockTime)
	Lighting.ClockTime = clockTime
	Lighting.Brightness = sample.brightness
	Lighting.Ambient = sample.ambient
	Lighting.OutdoorAmbient = sample.outdoorAmbient
	Lighting.ColorShift_Top = sample.colorShiftTop
	Lighting.ColorShift_Bottom = sample.colorShiftBottom
end

function DayCycleService.getClockTime(): number
	return clockTime
end

function DayCycleService.getSolarIntensity(): number
	return DayCycleHelper.getSolarIntensity(clockTime)
end

function DayCycleService.isPaused(): boolean
	return paused
end

function DayCycleService.setClockTime(hour: number)
	clockTime = DayCycleHelper.wrapClockTime(hour)
	applyLighting()
	publishState()
end

function DayCycleService.setPaused(value: boolean)
	paused = value
	publishState()
end

function DayCycleService.start()
	if started then
		return
	end
	started = true

	Lighting.GeographicLatitude = 35
	applyLighting()
	publishState()
end

function DayCycleService.update(deltaSec: number)
	if not started or paused then
		return
	end

	clockTime = DayCycleHelper.advanceClockTime(clockTime, deltaSec, C.CYCLE_DURATION_SEC)
	applyLighting()
	publishState()
end

function DayCycleService.setup(adminRemote: RemoteEvent)
	adminRemote.OnServerEvent:Connect(function(plr: Player, action: string, value: unknown)
		if not AdminHelper.isAdmin(plr) then
			return
		end

		if action == "SetTime" and typeof(value) == "number" then
			DayCycleService.setClockTime(value)
		elseif action == "SetPaused" and typeof(value) == "boolean" then
			DayCycleService.setPaused(value)
		end
	end)
end

return DayCycleService
