--!strict
--[[ Havok ability tuning ]]

export type BurstTier = {
	damage: number,
	radius: number,
	pushSpeed: number,
	pushUp: number,
}

local HAVOK_BLUE = Color3.fromRGB(70, 150, 255)
local HAVOK_BLUE_SOFT = Color3.fromRGB(100, 175, 255)
local HAVOK_BLUE_BRIGHT = Color3.fromRGB(140, 200, 255)

local BURST_TIERS: { BurstTier } = {
	{ damage = 16, radius = 9, pushSpeed = 32, pushUp = 5 },
	{ damage = 24, radius = 12, pushSpeed = 40, pushUp = 6 },
	{ damage = 34, radius = 15, pushSpeed = 48, pushUp = 8 },
	{ damage = 44, radius = 18, pushSpeed = 56, pushUp = 10 },
	{ damage = 58, radius = 24, pushSpeed = 68, pushUp = 13 },
}

return {
	HAVOK_BLUE = HAVOK_BLUE,
	HAVOK_BLUE_SOFT = HAVOK_BLUE_SOFT,
	HAVOK_BLUE_BRIGHT = HAVOK_BLUE_BRIGHT,
	COLOR = HAVOK_BLUE,
	BEAM_TRANSPARENCY = 0.28,

	EnergySiphon = {
		ABILITY_ID = "EnergySiphon",
		MAX_CHARGE = 5,
		COOLDOWN_SEC = 4.5,
	},

	EnergyBurst = {
		ABILITY_ID = "EnergyBurst",
		COOLDOWN_SEC = 2,
		MIN_CHARGE = 1,
		TIERS = BURST_TIERS,
		VFX_DURATION = 0.55,
	},

	ConcussiveBeam = {
		ABILITY_ID = "ConcussiveBeam",
		COOLDOWN_SEC = 3,
		RANGE = 115,
		DAMAGE_PER_TICK = 4,
		TICK_INTERVAL = 0.1,
		BEAM_COUNT = 1,
		AIM_SMOOTH_TAU = 0.12,
		AIM_SEND_INTERVAL = 0.05,
		BODY_ROTATE_TAU = 0.11,
		WIDTH_START = 1.35,
		WIDTH_END = 0.55,
		HIT_RADIUS = 1.1,
		PUSH_SPEED = 18,
		PUSH_UP = 1,
		PULSE_FREQ = 5.5,
		WIDTH_PULSE = 0.42,
		RAMP_SEC = 1.05,
		MIN_DAMAGE_MULT = 0.4,
	},

	EnergyBlast = {
		ABILITY_ID = "EnergyBlast",
		COOLDOWN_SEC = 1.2,
		SPEED = 110,
		DAMAGE = 14,
		RANGE = 160,
		LIFETIME = 2.2,
		SIZE = Vector3.new(0.55, 0.55, 3.5),
		RING_COUNT = 5,
		RING_SPACING = 1.45,
		RING_OUTER_RADIUS = 1.1,
		RING_INNER_RADIUS = 0.42,
		RING_THICKNESS = 0.12,
		RING_SEGMENTS = 14,
		PUSH_SPEED = 38,
		PUSH_UP = 6,
		CURVE_STRENGTH = 14,
		AIM_INTERVAL = 0.05,
		IMPACT_RADIUS = 4,
		IMPACT_DURATION = 0.35,
	},

	KineticSurge = {
		ABILITY_ID = "KineticSurge",
		COOLDOWN_SEC = 5.5,
		BOOST_SPEED = 125,
		ACTIVE_DURATION = 0.38,
	},
}
