--!strict
--[[ Psylocke ability tuning (placeholder kit). ]]

return {
	PSI_PURPLE = Color3.fromRGB(160, 90, 220),
	PSI_PINK = Color3.fromRGB(255, 105, 220),

	PsiBlade = {
		ABILITY_ID = "PsiBlade",
		COOLDOWN_SEC = 4,
		RANGE = 14,
		DAMAGE = 18,
	},

	ButterflyStep = {
		ABILITY_ID = "ButterflyStep",
		COOLDOWN_SEC = 5,
		RANGE = 22,
		DURATION = 0.18,
	},

	PsychicSlash = {
		ABILITY_ID = "PsychicSlash",
		COOLDOWN_SEC = 3,
		RANGE = 16,
		WIDTH = 12,
		HEIGHT = 8,
		DAMAGE = 22,
	},

	FocusField = {
		ABILITY_ID = "FocusField",
		COOLDOWN_SEC = 9,
		RADIUS = 14,
		DURATION = 3,
	},

	AstralAssault = {
		ABILITY_ID = "AstralAssault",
		COOLDOWN_SEC = 12,
		RANGE = 18,
		HITS = 4,
		DAMAGE = 12,
	},
}
