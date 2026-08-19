--!strict
--[[ Day/night cycle tuning — shared for lighting, HUD, and future Sunspot powers. ]]

export type LightingKeyframe = {
	hour: number,
	brightness: number,
	ambient: Color3,
	outdoorAmbient: Color3,
	colorShiftTop: Color3,
	colorShiftBottom: Color3,
}

local KEYFRAMES: { LightingKeyframe } = {
	{
		hour = 0,
		brightness = 0.6,
		ambient = Color3.fromRGB(28, 32, 58),
		outdoorAmbient = Color3.fromRGB(34, 38, 68),
		colorShiftTop = Color3.fromRGB(18, 22, 48),
		colorShiftBottom = Color3.fromRGB(8, 10, 24),
	},
	{
		hour = 5.5,
		brightness = 1.1,
		ambient = Color3.fromRGB(72, 58, 78),
		outdoorAmbient = Color3.fromRGB(98, 72, 88),
		colorShiftTop = Color3.fromRGB(255, 168, 96),
		colorShiftBottom = Color3.fromRGB(120, 72, 56),
	},
	{
		hour = 7.5,
		brightness = 2.2,
		ambient = Color3.fromRGB(150, 152, 168),
		outdoorAmbient = Color3.fromRGB(168, 170, 186),
		colorShiftTop = Color3.fromRGB(255, 220, 180),
		colorShiftBottom = Color3.fromRGB(190, 176, 150),
	},
	{
		hour = 12,
		brightness = 3,
		ambient = Color3.fromRGB(190, 190, 198),
		outdoorAmbient = Color3.fromRGB(205, 205, 212),
		colorShiftTop = Color3.fromRGB(255, 252, 244),
		colorShiftBottom = Color3.fromRGB(210, 214, 226),
	},
	{
		hour = 17.5,
		brightness = 2.4,
		ambient = Color3.fromRGB(168, 148, 138),
		outdoorAmbient = Color3.fromRGB(188, 158, 138),
		colorShiftTop = Color3.fromRGB(255, 176, 108),
		colorShiftBottom = Color3.fromRGB(150, 92, 72),
	},
	{
		hour = 20,
		brightness = 1,
		ambient = Color3.fromRGB(58, 52, 78),
		outdoorAmbient = Color3.fromRGB(72, 64, 96),
		colorShiftTop = Color3.fromRGB(120, 72, 108),
		colorShiftBottom = Color3.fromRGB(48, 36, 58),
	},
	{
		hour = 24,
		brightness = 0.6,
		ambient = Color3.fromRGB(28, 32, 58),
		outdoorAmbient = Color3.fromRGB(34, 38, 68),
		colorShiftTop = Color3.fromRGB(18, 22, 48),
		colorShiftBottom = Color3.fromRGB(8, 10, 24),
	},
}

return {
	CYCLE_DURATION_SEC = 900,
	START_CLOCK_TIME = 8,
	KEYFRAMES = KEYFRAMES,

	WORKSPACE_CLOCK_ATTR = "DayCycleClockTime",
	WORKSPACE_SOLAR_ATTR = "DayCycleSolarIntensity",
	WORKSPACE_PHASE_ATTR = "DayCyclePhase",
	WORKSPACE_PAUSED_ATTR = "DayCyclePaused",
}
