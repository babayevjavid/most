--[[
	Energy costs and defaults for Jean Grey abilities.
]]

return {
	DEFAULT_MAX = 100,
	REGEN_PER_SEC = 5,
	REGEN_DELAY_SEC = 3,

	INSTANT = {
		PsionicBolt = 5,
		TelekinesisThrow = 8,
		TelepathicOutburst = 25,
	},

	OUTBURST_MIN_COST = 8,
	OUTBURST_MAX_COST = 25,

	HOLD_PER_SEC = {
		Telekinesis = 3,
		TelepathicSense = 4,
		TelekineticFlightIdle = 2,
		TelekineticFlightMoving = 5,
	},

	MIN_TO_START = {
		Telekinesis = 5,
		TelepathicSense = 8,
		TelekineticFlight = 10,
		PsionicBolt = 5,
		TelepathicOutburst = 8,
	},
}
