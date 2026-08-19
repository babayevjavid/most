local Elements = {}

export type ElementDefinition = {
	Name: string,
	Color: Color3,
	Accent: Color3,
	Description: string,
	Trait: string,
	IncomeBonus: number,
}

Elements.List = {
	{
		Name = "Fire",
		Color = Color3.fromRGB(255, 102, 46),
		Accent = Color3.fromRGB(255, 184, 72),
		Description = "Fast, sharp growth with a warm aggressive glow.",
		Trait = "Overheat your income bursts.",
		IncomeBonus = 0.18,
	},
	{
		Name = "Water",
		Color = Color3.fromRGB(56, 154, 255),
		Accent = Color3.fromRGB(139, 226, 255),
		Description = "Smooth, steady production with a calm luminous surface.",
		Trait = "Convert stability into reliable cash flow.",
		IncomeBonus = 0.12,
	},
	{
		Name = "Earth",
		Color = Color3.fromRGB(126, 92, 58),
		Accent = Color3.fromRGB(194, 162, 108),
		Description = "Heavy, grounded, and built for durable expansion.",
		Trait = "Layer defenses while your economy compounds.",
		IncomeBonus = 0.10,
	},
	{
		Name = "Air",
		Color = Color3.fromRGB(187, 231, 255),
		Accent = Color3.fromRGB(255, 255, 255),
		Description = "Light, open, and fast to scale with bright motion.",
		Trait = "Use speed to push your next upgrade sooner.",
		IncomeBonus = 0.14,
	},
	{
		Name = "Wood",
		Color = Color3.fromRGB(77, 170, 94),
		Accent = Color3.fromRGB(149, 215, 119),
		Description = "Organic growth with clean green visuals and layered depth.",
		Trait = "Stack natural growth into stronger branches.",
		IncomeBonus = 0.16,
	},
	{
		Name = "Metal",
		Color = Color3.fromRGB(162, 172, 185),
		Accent = Color3.fromRGB(236, 239, 243),
		Description = "Precise, reflective, and engineered for efficient upgrades.",
		Trait = "Turn sharp timing into higher output.",
		IncomeBonus = 0.15,
	},
	{
		Name = "Darkness",
		Color = Color3.fromRGB(31, 24, 55),
		Accent = Color3.fromRGB(125, 86, 214),
		Description = "Low light, high contrast, and a dramatic premium feel.",
		Trait = "Scale in the shadows with heavy multiplier focus.",
		IncomeBonus = 0.22,
	},
	{
		Name = "Light",
		Color = Color3.fromRGB(255, 238, 174),
		Accent = Color3.fromRGB(255, 255, 255),
		Description = "Clean, bright, and polished with a premium golden edge.",
		Trait = "Lift every upgrade with high clarity and value.",
		IncomeBonus = 0.20,
	},
	{
		Name = "Nature",
		Color = Color3.fromRGB(42, 145, 120),
		Accent = Color3.fromRGB(112, 219, 181),
		Description = "Deep green growth with a living, layered economy.",
		Trait = "Branch income into multiple clean sources.",
		IncomeBonus = 0.17,
	},
	{
		Name = "Death",
		Color = Color3.fromRGB(58, 38, 82),
		Accent = Color3.fromRGB(189, 255, 102),
		Description = "Striking contrast, eerie glow, and a dangerous premium identity.",
		Trait = "Trade intensity for rare high-value bursts.",
		IncomeBonus = 0.24,
	},
}

Elements.ByName = {}

for _, element in ipairs(Elements.List) do
	Elements.ByName[element.Name] = element
end

function Elements.GetByIndex(index: number): ElementDefinition
	local normalizedIndex = ((index - 1) % #Elements.List) + 1
	return Elements.List[normalizedIndex]
end

function Elements.GetByName(name: string): ElementDefinition?
	return Elements.ByName[name]
end

return Elements
