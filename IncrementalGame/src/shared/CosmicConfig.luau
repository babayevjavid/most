export type PlayerState = {
	Power: number,
	LifetimePower: number,
	OwnedGenerators: { [string]: boolean },
	MultiplierLevels: { [string]: number },
	Ascensions: number,
	OwnedPowers: { [string]: boolean },
	EquippedPowers: { string },
	LastSaveUnix: number?,
}

local CosmicConfig = {
	GameName = "Hero Training",
	CurrencyName = "Power",
	OfflineCapSeconds = 28800,
	StartingPower = 0,
	PassiveBaseRate = 1,

	AscensionBaseRequirement = 10000,
	AscensionRequirementScale = 10,
	AscensionBonusPerLevel = 0.25,

	Generators = {
		FocusTraining = {
			DisplayName = "Focus Training",
			BaseRate = 1,
			Cost = 25,
			UnlockAfter = nil,
			Color = Color3.fromRGB(90, 140, 255),
		},
		StrengthDrill = {
			DisplayName = "Strength Drill",
			BaseRate = 4,
			Cost = 150,
			UnlockAfter = "FocusTraining",
			Color = Color3.fromRGB(255, 90, 90),
		},
		SparringArena = {
			DisplayName = "Sparring Arena",
			BaseRate = 15,
			Cost = 800,
			UnlockAfter = "StrengthDrill",
			Color = Color3.fromRGB(255, 200, 70),
		},
		MutationChamber = {
			DisplayName = "Mutation Chamber",
			BaseRate = 60,
			Cost = 5000,
			UnlockAfter = "SparringArena",
			Color = Color3.fromRGB(180, 100, 255),
		},
		OmegaCore = {
			DisplayName = "Omega Core",
			BaseRate = 250,
			Cost = 35000,
			UnlockAfter = "MutationChamber",
			Color = Color3.fromRGB(80, 255, 160),
		},
	},

	GeneratorOrder = { "FocusTraining", "StrengthDrill", "SparringArena", "MutationChamber", "OmegaCore" },

	Multipliers = {
		AdrenalineRush = {
			DisplayName = "Adrenaline Rush",
			BonusPerLevel = 0.12,
			MaxLevel = 5,
			BaseCost = 200,
			CostGrowth = 1.55,
			Color = Color3.fromRGB(255, 100, 80),
		},
		GeneticBoost = {
			DisplayName = "Genetic Boost",
			BonusPerLevel = 0.12,
			MaxLevel = 5,
			BaseCost = 500,
			CostGrowth = 1.6,
			Color = Color3.fromRGB(100, 200, 255),
		},
		LimitBreak = {
			DisplayName = "Limit Break",
			BonusPerLevel = 0.15,
			MaxLevel = 5,
			BaseCost = 1200,
			CostGrowth = 1.65,
			Color = Color3.fromRGB(255, 180, 60),
		},
		UltimateForm = {
			DisplayName = "Ultimate Form",
			BonusPerLevel = 0.18,
			MaxLevel = 5,
			BaseCost = 3000,
			CostGrowth = 1.7,
			Color = Color3.fromRGB(220, 80, 255),
		},
	},

	MultiplierOrder = { "AdrenalineRush", "GeneticBoost", "LimitBreak", "UltimateForm" },
}

function CosmicConfig.GetGeneratorCost(generatorId: string): number
	local generator = CosmicConfig.Generators[generatorId]
	if not generator then
		return math.huge
	end
	return generator.Cost
end

function CosmicConfig.GetMultiplierCost(upgradeId: string, currentLevel: number): number
	local upgrade = CosmicConfig.Multipliers[upgradeId]
	if not upgrade then
		return math.huge
	end
	if currentLevel >= upgrade.MaxLevel then
		return math.huge
	end
	local cost = upgrade.BaseCost * (upgrade.CostGrowth ^ currentLevel)
	return math.max(1, math.floor(cost + 0.5))
end

function CosmicConfig.GetAscensionRequirement(ascensions: number): number
	return math.floor(CosmicConfig.AscensionBaseRequirement * (CosmicConfig.AscensionRequirementScale ^ ascensions))
end

function CosmicConfig.GetAscensionMultiplier(ascensions: number): number
	return 1 + (ascensions * CosmicConfig.AscensionBonusPerLevel)
end

function CosmicConfig.GetBaseRate(state: PlayerState): number
	local total = 0
	for generatorId, owned in state.OwnedGenerators do
		if owned then
			local generator = CosmicConfig.Generators[generatorId]
			if generator then
				total += generator.BaseRate
			end
		end
	end

	local PowerConfig = require(script.Parent:WaitForChild("PowerConfig"))
	local generatorBonus = 1 + PowerConfig.GetGeneratorBonus(state.EquippedPowers or {})
	return total * generatorBonus
end

function CosmicConfig.GetUpgradeMultiplier(state: PlayerState): number
	local multiplier = 1
	for upgradeId, level in state.MultiplierLevels do
		local upgrade = CosmicConfig.Multipliers[upgradeId]
		if upgrade and level > 0 then
			multiplier += level * upgrade.BonusPerLevel
		end
	end

	local PowerConfig = require(script.Parent:WaitForChild("PowerConfig"))
	multiplier += PowerConfig.GetMultiplierBonus(state.EquippedPowers or {})

	return multiplier
end

function CosmicConfig.GetTotalMultiplier(state: PlayerState): number
	return CosmicConfig.GetUpgradeMultiplier(state) * CosmicConfig.GetAscensionMultiplier(state.Ascensions)
end

function CosmicConfig.GetPowerPerSecond(state: PlayerState): number
	local baseRate = CosmicConfig.GetBaseRate(state)
	if baseRate <= 0 then
		baseRate = CosmicConfig.PassiveBaseRate
	end

	local PowerConfig = require(script.Parent:WaitForChild("PowerConfig"))
	local powerBonus = 1 + PowerConfig.GetPowerGainBonus(state.EquippedPowers or {})
	return baseRate * CosmicConfig.GetTotalMultiplier(state) * powerBonus
end

function CosmicConfig.IsGeneratorUnlocked(state: PlayerState, generatorId: string): boolean
	if state.OwnedGenerators[generatorId] then
		return true
	end

	local generator = CosmicConfig.Generators[generatorId]
	if not generator then
		return false
	end

	if generator.UnlockAfter == nil then
		return true
	end

	return state.OwnedGenerators[generator.UnlockAfter] == true
end

function CosmicConfig.HasAnyGenerator(state: PlayerState): boolean
	for _, owned in state.OwnedGenerators do
		if owned then
			return true
		end
	end
	return false
end

function CosmicConfig.CreateDefaultState(): PlayerState
	return {
		Power = CosmicConfig.StartingPower,
		LifetimePower = 0,
		OwnedGenerators = {},
		MultiplierLevels = {},
		Ascensions = 0,
		OwnedPowers = {},
		EquippedPowers = {},
		LastSaveUnix = nil,
	}
end

return CosmicConfig
