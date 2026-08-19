--!strict

local Constants = require(script.Parent.Constants)

export type PushProfile = {
	humanoidForce: number,
	propForce: number,
	liftDuration: number?,
}

local InteractionConfig: { [string]: PushProfile } = {
	Telekinesis = {
		humanoidForce = Constants.PUSH_FORCE_HUMANOID,
		propForce = Constants.PUSH_FORCE_MEDIUM,
		liftDuration = 1.2,
	},
	ForcePush = {
		humanoidForce = Constants.PUSH_FORCE_HUMANOID,
		propForce = Constants.PUSH_FORCE_LIGHT,
	},
	ThunderClap = {
		humanoidForce = Constants.PUSH_FORCE_MEDIUM,
		propForce = Constants.PUSH_FORCE_LIGHT,
	},
	CosmicPunch = {
		humanoidForce = Constants.PUSH_FORCE_HEAVY,
		propForce = Constants.PUSH_FORCE_MEDIUM,
	},
}

return InteractionConfig
