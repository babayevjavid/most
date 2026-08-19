--[[ Human Torch ability tuning ]]
return {
	FlameFlight = { ABILITY_ID = "FlameFlight", COOLDOWN_SEC = 6, FLY_SPEED = 42, COOLDOWN_TOGGLE = 6 },
	Fireball = {
		ABILITY_ID = "Fireball",
		COOLDOWN_SEC = 3,
		SPEED = 100,
		DAMAGE = 18,
		RANGE = 150,
		LIFETIME = 2,
		EXPLOSION_RADIUS = 8,
		SIZE = Vector3.new(0.8, 0.8, 0.8),
		PUSH_SPEED = 55,
		PUSH_UP = 14,
		CURVE_STRENGTH = 6,
		AIM_INTERVAL = 0.05,
	},
	NovaBurst = { ABILITY_ID = "NovaBurst", COOLDOWN_SEC = 10, RADIUS = 12, DAMAGE = 24, PUSH_SPEED = 48, PUSH_UP = 20 },
	FireRush = { ABILITY_ID = "FireRush", COOLDOWN_SEC = 7, DASH_DISTANCE = 16, DASH_DURATION = 0.2, DAMAGE = 18, PUSH_SPEED = 50, PUSH_UP = 12 },
	Inferno = { ABILITY_ID = "Inferno", COOLDOWN_SEC = 14, CHARGE_MAX_SEC = 2, MIN_RADIUS = 12, MAX_RADIUS = 30, WAVE_DURATION = 0.5, MIN_DAMAGE = 16, MAX_DAMAGE = 40, PUSH_SPEED = 52, PUSH_UP = 18 },
	COLOR = Color3.fromRGB(255, 120, 30),
}
