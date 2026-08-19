local Lighting = game:GetService("Lighting")

local LightingService = {}

local CYCLE_START = 6
local CYCLE_END = 20
local CYCLE_SECONDS = 16 * 60
local START_TIME = 11.5

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function clamp01(t: number): number
	return math.clamp(t, 0, 1)
end

local function getDayLighting(clockTime: number): {
	brightness: number,
	ambient: Color3,
	outdoorAmbient: Color3,
	exposure: number,
	atmosphereDensity: number,
}
	local hour = clockTime

	if hour < 8 then
		local t = clamp01((hour - CYCLE_START) / 2)
		return {
			brightness = lerp(1.4, 2.3, t),
			ambient = Color3.fromRGB(lerp(95, 130, t), lerp(95, 128, t), lerp(110, 138, t)),
			outdoorAmbient = Color3.fromRGB(lerp(110, 165, t), lerp(110, 162, t), lerp(125, 172, t)),
			exposure = lerp(-0.02, 0.1, t),
			atmosphereDensity = lerp(0.28, 0.22, t),
		}
	elseif hour < 17 then
		return {
			brightness = 2.35,
			ambient = Color3.fromRGB(138, 136, 142),
			outdoorAmbient = Color3.fromRGB(168, 166, 172),
			exposure = 0.1,
			atmosphereDensity = 0.2,
		}
	elseif hour < CYCLE_END then
		local t = clamp01((hour - 17) / (CYCLE_END - 17))
		return {
			brightness = lerp(2.35, 1.5, t),
			ambient = Color3.fromRGB(lerp(138, 100, t), lerp(136, 95, t), lerp(142, 110, t)),
			outdoorAmbient = Color3.fromRGB(lerp(168, 120, t), lerp(166, 105, t), lerp(172, 118, t)),
			exposure = lerp(0.1, -0.05, t),
			atmosphereDensity = lerp(0.2, 0.3, t),
		}
	else
		return {
			brightness = 1.5,
			ambient = Color3.fromRGB(100, 95, 110),
			outdoorAmbient = Color3.fromRGB(120, 105, 118),
			exposure = -0.05,
			atmosphereDensity = 0.3,
		}
	end
end

local function applyTimeOfDay(clockTime: number)
	local settings = getDayLighting(clockTime)
	Lighting.ClockTime = clockTime
	Lighting.Brightness = settings.brightness
	Lighting.Ambient = settings.ambient
	Lighting.OutdoorAmbient = settings.outdoorAmbient
	Lighting.ExposureCompensation = settings.exposure

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		atmosphere.Density = settings.atmosphereDensity
	end
end

function LightingService.Apply()
	Lighting.GeographicLatitude = 35
	Lighting.GlobalShadows = true

	applyTimeOfDay(START_TIME)

	local bloom = Instance.new("BloomEffect")
	bloom.Name = "ASMRBloom"
	bloom.Intensity = 0.18
	bloom.Size = 18
	bloom.Threshold = 1.05
	bloom.Parent = Lighting

	local colorCorrection = Instance.new("ColorCorrectionEffect")
	colorCorrection.Name = "ASMRCorrection"
	colorCorrection.Brightness = 0.03
	colorCorrection.Contrast = 0.04
	colorCorrection.Saturation = 0.06
	colorCorrection.TintColor = Color3.fromRGB(255, 252, 245)
	colorCorrection.Parent = Lighting

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Name = "ASMRAtmosphere"
	atmosphere.Density = 0.2
	atmosphere.Offset = 0.08
	atmosphere.Color = Color3.fromRGB(195, 210, 225)
	atmosphere.Decay = Color3.fromRGB(140, 155, 175)
	atmosphere.Glare = 0.08
	atmosphere.Haze = 0.35
	atmosphere.Parent = Lighting

	local sunRays = Instance.new("SunRaysEffect")
	sunRays.Name = "ASMRSunRays"
	sunRays.Intensity = 0.08
	sunRays.Spread = 0.6
	sunRays.Parent = Lighting
end

function LightingService.StartDayCycle()
	task.spawn(function()
		Lighting.ClockTime = START_TIME

		while true do
			local dt = task.wait(0.4)
			local nextTime = Lighting.ClockTime + ((CYCLE_END - CYCLE_START) / CYCLE_SECONDS) * dt
			if nextTime >= CYCLE_END then
				nextTime = CYCLE_START
			end
			applyTimeOfDay(nextTime)
		end
	end)
end

return LightingService
