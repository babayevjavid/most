export type ActiveAbility = {
	DisplayAction: string,
	Cooldown: number,
	Damage: number?,
	Range: number?,
	Heal: number?,
	DashStuds: number?,
}

export type PowerDefinition = {
	Id: string,
	DisplayName: string,
	Description: string,
	Cost: number,
	Category: string,
	Color: Color3,
	Icon: string,
	AllowsTravel: boolean?,
	TerritoryDamage: number?,
	OutOfBaseDamageReduction: number?,
	PowerGainBonus: number?,
	MultiplierBonus: number?,
	GeneratorBonus: number?,
	HomeHealPerTick: number?,
	PowerLeech: number?,
	ActiveAbility: ActiveAbility?,
}

local PowerConfig = {
	MaxEquipped = 5,
	ForeignBaseDamage = 8,
	WildernessDamage = 4,
	DamageTickSeconds = 2,
	HomeHealTickSeconds = 2,

	Powers = {
		PhaseShift = {
			Id = "PhaseShift",
			DisplayName = "Phase Shift",
			Description = "Travel safe. [1-5] Phase Dash forward.",
			Cost = 500,
			Category = "Travel",
			Color = Color3.fromRGB(120, 220, 255),
			Icon = "◎",
			AllowsTravel = true,
			ActiveAbility = {
				DisplayAction = "Phase Dash",
				Cooldown = 4,
				DashStuds = 22,
			},
		},
		VoidStep = {
			Id = "VoidStep",
			DisplayName = "Void Step",
			Description = "No wilderness damage. [1-5] Long blink.",
			Cost = 2200,
			Category = "Travel",
			Color = Color3.fromRGB(90, 70, 180),
			Icon = "◈",
			AllowsTravel = true,
			OutOfBaseDamageReduction = 1,
			ActiveAbility = {
				DisplayAction = "Void Blink",
				Cooldown = 5,
				DashStuds = 38,
			},
		},
		StaticField = {
			Id = "StaticField",
			DisplayName = "Static Field",
			Description = "Territory shock + [1-5] pulse damage.",
			Cost = 800,
			Category = "Territory",
			Color = Color3.fromRGB(255, 230, 80),
			Icon = "⚡",
			TerritoryDamage = 10,
			ActiveAbility = {
				DisplayAction = "Static Pulse",
				Cooldown = 3,
				Damage = 16,
				Range = 14,
			},
		},
		PlasmaRing = {
			Id = "PlasmaRing",
			DisplayName = "Plasma Ring",
			Description = "Territory plasma + [1-5] ring burst.",
			Cost = 1200,
			Category = "Territory",
			Color = Color3.fromRGB(255, 90, 160),
			Icon = "◉",
			TerritoryDamage = 14,
			ActiveAbility = {
				DisplayAction = "Plasma Burst",
				Cooldown = 4,
				Damage = 24,
				Range = 16,
			},
		},
		IronDominion = {
			Id = "IronDominion",
			DisplayName = "Iron Dominion",
			Description = "Heavy territory field + [1-5] slam.",
			Cost = 1800,
			Category = "Territory",
			Color = Color3.fromRGB(180, 190, 210),
			Icon = "⬡",
			TerritoryDamage = 20,
			ActiveAbility = {
				DisplayAction = "Iron Slam",
				Cooldown = 5,
				Damage = 30,
				Range = 12,
			},
		},
		FocusFlow = {
			Id = "FocusFlow",
			DisplayName = "Focus Flow",
			Description = "+15% passive power gain.",
			Cost = 350,
			Category = "Passive",
			Color = Color3.fromRGB(100, 200, 255),
			Icon = "▲",
			PowerGainBonus = 0.15,
		},
		AdrenalCore = {
			Id = "AdrenalCore",
			DisplayName = "Adrenal Core",
			Description = "+18% total multiplier.",
			Cost = 650,
			Category = "Passive",
			Color = Color3.fromRGB(255, 120, 70),
			Icon = "✦",
			MultiplierBonus = 0.18,
		},
		DeepCells = {
			Id = "DeepCells",
			DisplayName = "Deep Cells",
			Description = "+22% generator output.",
			Cost = 950,
			Category = "Passive",
			Color = Color3.fromRGB(80, 255, 170),
			Icon = "❖",
			GeneratorBonus = 0.22,
		},
		IronSkin = {
			Id = "IronSkin",
			DisplayName = "Iron Skin",
			Description = "Half damage outside your base.",
			Cost = 450,
			Category = "Defense",
			Color = Color3.fromRGB(140, 150, 165),
			Icon = "⬢",
			OutOfBaseDamageReduction = 0.5,
		},
		RapidHeal = {
			Id = "RapidHeal",
			DisplayName = "Rapid Heal",
			Description = "Regen on base + [1-5] quick heal.",
			Cost = 700,
			Category = "Defense",
			Color = Color3.fromRGB(90, 255, 140),
			Icon = "+",
			HomeHealPerTick = 8,
			ActiveAbility = {
				DisplayAction = "Quick Heal",
				Cooldown = 6,
				Heal = 22,
			},
		},
		EnergyLeech = {
			Id = "EnergyLeech",
			DisplayName = "Energy Leech",
			Description = "Leech trespassers + [1-5] drain blast.",
			Cost = 1100,
			Category = "Offense",
			Color = Color3.fromRGB(180, 80, 255),
			Icon = "➤",
			TerritoryDamage = 6,
			PowerLeech = 4,
			ActiveAbility = {
				DisplayAction = "Energy Drain",
				Cooldown = 4,
				Damage = 14,
				Range = 14,
			},
		},
		SolarFlare = {
			Id = "SolarFlare",
			DisplayName = "Solar Flare",
			Description = "Burn trespassers + [1-5] solar blast.",
			Cost = 1600,
			Category = "Offense",
			Color = Color3.fromRGB(255, 180, 50),
			Icon = "☀",
			TerritoryDamage = 12,
			PowerGainBonus = 0.08,
			ActiveAbility = {
				DisplayAction = "Solar Blast",
				Cooldown = 4,
				Damage = 28,
				Range = 18,
			},
		},
	} :: { [string]: PowerDefinition },

	PowerOrder = {
		"PhaseShift",
		"VoidStep",
		"StaticField",
		"PlasmaRing",
		"IronDominion",
		"FocusFlow",
		"AdrenalCore",
		"DeepCells",
		"IronSkin",
		"RapidHeal",
		"EnergyLeech",
		"SolarFlare",
	},
}

function PowerConfig.GetPower(powerId: string): PowerDefinition?
	return PowerConfig.Powers[powerId]
end

function PowerConfig.PlayerHasTravel(equipped: { string }): boolean
	for _, powerId in equipped do
		local power = PowerConfig.Powers[powerId]
		if power and power.AllowsTravel then
			return true
		end
	end
	return false
end

function PowerConfig.GetTerritoryDamage(equipped: { string }): number
	local total = 0
	for _, powerId in equipped do
		local power = PowerConfig.Powers[powerId]
		if power and power.TerritoryDamage then
			total += power.TerritoryDamage
		end
	end
	return total
end

function PowerConfig.GetOutOfBaseReduction(equipped: { string }): number
	local reduction = 0
	for _, powerId in equipped do
		local power = PowerConfig.Powers[powerId]
		if power and power.OutOfBaseDamageReduction then
			reduction = math.max(reduction, power.OutOfBaseDamageReduction)
		end
	end
	return math.clamp(reduction, 0, 1)
end

function PowerConfig.GetPowerGainBonus(equipped: { string }): number
	local bonus = 0
	for _, powerId in equipped do
		local power = PowerConfig.Powers[powerId]
		if power and power.PowerGainBonus then
			bonus += power.PowerGainBonus
		end
	end
	return bonus
end

function PowerConfig.GetMultiplierBonus(equipped: { string }): number
	local bonus = 0
	for _, powerId in equipped do
		local power = PowerConfig.Powers[powerId]
		if power and power.MultiplierBonus then
			bonus += power.MultiplierBonus
		end
	end
	return bonus
end

function PowerConfig.GetGeneratorBonus(equipped: { string }): number
	local bonus = 0
	for _, powerId in equipped do
		local power = PowerConfig.Powers[powerId]
		if power and power.GeneratorBonus then
			bonus += power.GeneratorBonus
		end
	end
	return bonus
end

function PowerConfig.GetHomeHeal(equipped: { string }): number
	local heal = 0
	for _, powerId in equipped do
		local power = PowerConfig.Powers[powerId]
		if power and power.HomeHealPerTick then
			heal += power.HomeHealPerTick
		end
	end
	return heal
end

function PowerConfig.GetPowerLeech(equipped: { string }): number
	local leech = 0
	for _, powerId in equipped do
		local power = PowerConfig.Powers[powerId]
		if power and power.PowerLeech then
			leech += power.PowerLeech
		end
	end
	return leech
end

return PowerConfig
