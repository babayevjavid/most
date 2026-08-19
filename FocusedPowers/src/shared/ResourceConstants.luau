--[[ Per-hero resource bar configs. Uses Energy/MaxEnergy attributes on character. ]]

export type ResourceConfig = {
	label: string,
	max: number,
	maxHealth: number,
	regenPerSec: number,
	regenDelaySec: number,
	solarChargePerSec: number?,
	instant: { [string]: number },
	holdPerSec: { [string]: number },
	minToStart: { [string]: number },
	scaledCosts: { [string]: { min: number, max: number } }?,
}

local POLARIS: ResourceConfig = {
	label = "Magnetic Energy",
	max = 100,
	maxHealth = 200,
	regenPerSec = 5,
	regenDelaySec = 2.5,
	instant = {
		MagneticPulse = 2,
		OrbitalThrow = 2,
		FerrokinesisThrow = 3,
	},
	holdPerSec = {
		Ferrokinesis = 0.9,
		MagneticFlightIdle = 0.5,
		MagneticFlightMoving = 1.6,
		MetalLance = 0.9,
	},
	minToStart = {
		MagneticFlight = 4,
		Ferrokinesis = 3,
		MagneticPulse = 2,
		MetalLance = 4,
		OrbitalStrikes = 5,
	},
}

local HAVOK: ResourceConfig = {
	label = "Plasma Energy",
	max = 100,
	maxHealth = 200,
	regenPerSec = 6,
	regenDelaySec = 2,
	instant = {
		EnergyBlast = 2,
		EnergyBurst = 4,
		KineticSurge = 5,
	},
	holdPerSec = {
		ConcussiveBeam = 1.4,
	},
	minToStart = {
		ConcussiveBeam = 3,
		EnergyBurst = 4,
		EnergyBlast = 2,
		KineticSurge = 5,
	},
}

local SUNSPOT: ResourceConfig = {
	label = "Solar Energy",
	max = 100,
	maxHealth = 250,
	regenPerSec = 0,
	regenDelaySec = 0,
	solarChargePerSec = 16,
	instant = {
		SunUppercut = 3,
		SolarFlare = 2,
		BlackSun = 8,
	},
	holdPerSec = {
		SolarFlightIdle = 0.5,
		SolarFlightMoving = 1.6,
	},
	minToStart = {
		SolarFlight = 4,
		SunUppercut = 3,
		SolarFlare = 2,
		BlackSun = 6,
	},
}

local PSYLOCKE: ResourceConfig = {
	label = "Psychic Energy",
	max = 100,
	maxHealth = 200,
	regenPerSec = 5,
	regenDelaySec = 2.5,
	instant = {
		PsiBlade = 2,
		ButterflyStep = 3,
		PsychicSlash = 2,
		FocusField = 5,
		AstralAssault = 8,
	},
	holdPerSec = {},
	minToStart = {
		PsiBlade = 2,
		ButterflyStep = 3,
		PsychicSlash = 2,
		FocusField = 5,
		AstralAssault = 8,
	},
}

return {
	RESOURCE_CHARACTERS = {
		Polaris = true,
		Havok = true,
		Sunspot = true,
		Psylocke = true,
	},
	CONFIGS = {
		Polaris = POLARIS,
		Havok = HAVOK,
		Sunspot = SUNSPOT,
		Psylocke = PSYLOCKE,
	},
}
