--!strict

local HUDTheme = {
	PanelBg = Color3.fromRGB(10, 12, 16),
	PanelBgTransparency = 0.12,
	Stroke = Color3.fromRGB(52, 58, 68),
	StrokeTransparency = 0.25,
	TextPrimary = Color3.fromRGB(245, 247, 250),
	TextMuted = Color3.fromRGB(140, 148, 162),

	Health = Color3.fromRGB(34, 220, 140),
	HealthDark = Color3.fromRGB(12, 148, 88),
	HealthText = Color3.fromRGB(235, 255, 245),
	Stamina = Color3.fromRGB(255, 196, 58),
	StaminaDark = Color3.fromRGB(210, 128, 18),
	StaminaText = Color3.fromRGB(255, 252, 238),
	Energy = Color3.fromRGB(255, 72, 128),
	EnergyDark = Color3.fromRGB(190, 28, 92),
	EnergyText = Color3.fromRGB(255, 236, 246),

	BarTrack = Color3.fromRGB(12, 14, 22),
	BarTrackStroke = Color3.fromRGB(58, 62, 78),

	CurrencyBlue = Color3.fromRGB(60, 160, 255),
	CurrencyYellow = Color3.fromRGB(255, 200, 60),

	CooldownOverlay = Color3.fromRGB(0, 0, 0),
	CooldownOverlayTransparency = 0.55,

	FontTitle = Enum.Font.GothamBold,
	FontBody = Enum.Font.GothamMedium,
	FontLabel = Enum.Font.GothamBold,

	CornerSmall = UDim.new(0, 5),
	CornerMedium = UDim.new(0, 4),
	CornerAbility = UDim.new(0, 6),
	CornerPill = UDim.new(1, 0),

	ViewportPosition = UDim2.fromScale(0, 0),
	ViewportSize = UDim2.fromScale(0.3, 0.3),
	BarsPosition = UDim2.fromScale(0.1, 0),
	BarsSize = UDim2.fromScale(0.15, 0.3),
	BarsAspectRatio = 0.5,
	StatBarSize = UDim2.fromScale(1, 0.25),
	StatBarGapScale = 0.04,

	AbilityBarWidthScale = 0.62,
	AbilityBarHeightScale = 0.13,
	AbilityButtonHeightScale = 0.92,
	AbilityButtonWidthScale = 0.155,

	AbilitySize = 52,
	PassiveSize = 32,
	AvatarViewportSize = 104,

	HeroAccents = {
		Wanda = Color3.fromRGB(200, 35, 55),
		Thor = Color3.fromRGB(70, 130, 220),
		CaptainMarvel = Color3.fromRGB(255, 180, 50),
		Loki = Color3.fromRGB(50, 170, 100),
	},
}

return HUDTheme
