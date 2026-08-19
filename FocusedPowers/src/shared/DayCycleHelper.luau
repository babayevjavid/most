--!strict
--[[ Day cycle math: clock formatting, lighting samples, solar intensity for Sunspot. ]]

local DayCycleConstants = require(script.Parent:WaitForChild("DayCycleConstants"))

export type LightingSample = {
	brightness: number,
	ambient: Color3,
	outdoorAmbient: Color3,
	colorShiftTop: Color3,
	colorShiftBottom: Color3,
}

export type DayPhase = "night" | "dawn" | "day" | "dusk"

local KEYFRAMES = DayCycleConstants.KEYFRAMES

local DayCycleHelper = {}

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function lerpColor(a: Color3, b: Color3, t: number): Color3
	return a:Lerp(b, t)
end

local function wrapClockTime(hour: number): number
	local wrapped = hour % 24
	if wrapped < 0 then
		wrapped += 24
	end
	return wrapped
end

function DayCycleHelper.wrapClockTime(hour: number): number
	return wrapClockTime(hour)
end

function DayCycleHelper.formatClock12(hour24: number): string
	local wrapped = wrapClockTime(hour24)
	local hour = math.floor(wrapped)
	local minute = math.floor((wrapped - hour) * 60 + 0.5)
	if minute >= 60 then
		minute = 0
		hour += 1
	end
	hour = hour % 24

	local period = if hour < 12 then "AM" else "PM"
	local displayHour = hour % 12
	if displayHour == 0 then
		displayHour = 12
	end

	return string.format("%d:%02d %s", displayHour, minute, period)
end

function DayCycleHelper.getPhase(clockTime: number): DayPhase
	local hour = wrapClockTime(clockTime)
	if hour >= 7.5 and hour < 17.5 then
		return "day"
	elseif hour >= 5.5 and hour < 7.5 then
		return "dawn"
	elseif hour >= 17.5 and hour < 20.5 then
		return "dusk"
	end
	return "night"
end

function DayCycleHelper.getPhaseLabel(phase: DayPhase): string
	if phase == "dawn" then
		return "Dawn"
	elseif phase == "day" then
		return "Day"
	elseif phase == "dusk" then
		return "Dusk"
	end
	return "Night"
end

--[[ 0 at deep night, ~1 at solar noon — hook for Sunspot power scaling. ]]
function DayCycleHelper.getSolarIntensity(clockTime: number): number
	local hour = wrapClockTime(clockTime)
	if hour < 5.5 or hour >= 20.5 then
		return 0
	end
	if hour >= 9 and hour <= 15 then
		return 1
	end
	if hour < 9 then
		return (hour - 5.5) / 3.5
	end
	return (20.5 - hour) / 5.5
end

function DayCycleHelper.sampleLighting(clockTime: number): LightingSample
	local hour = wrapClockTime(clockTime)

	for i = 1, #KEYFRAMES - 1 do
		local a = KEYFRAMES[i]
		local b = KEYFRAMES[i + 1]
		if hour >= a.hour and hour <= b.hour then
			local span = b.hour - a.hour
			local alpha = if span > 0 then (hour - a.hour) / span else 0
			return {
				brightness = lerp(a.brightness, b.brightness, alpha),
				ambient = lerpColor(a.ambient, b.ambient, alpha),
				outdoorAmbient = lerpColor(a.outdoorAmbient, b.outdoorAmbient, alpha),
				colorShiftTop = lerpColor(a.colorShiftTop, b.colorShiftTop, alpha),
				colorShiftBottom = lerpColor(a.colorShiftBottom, b.colorShiftBottom, alpha),
			}
		end
	end

	local last = KEYFRAMES[#KEYFRAMES]
	return {
		brightness = last.brightness,
		ambient = last.ambient,
		outdoorAmbient = last.outdoorAmbient,
		colorShiftTop = last.colorShiftTop,
		colorShiftBottom = last.colorShiftBottom,
	}
end

function DayCycleHelper.advanceClockTime(current: number, deltaSec: number, cycleDurationSec: number): number
	local hoursPerSec = 24 / cycleDurationSec
	return wrapClockTime(current + deltaSec * hoursPerSec)
end

return DayCycleHelper
