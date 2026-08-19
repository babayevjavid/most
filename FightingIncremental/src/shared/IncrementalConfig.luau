local IncrementalConfig = {
	PortalRequirement = 1000,
	RebirthRequirement = 5000,

	StartingCoins = 0,
	StartingWalkSpeed = 6,
	BaseWalkSpeed = 6,
	SpeedPerPoint = 0.75,
	BaseJumpPower = 0,
	JumpPerPoint = 1.8,

	BaseHealth = 100,
	HealthPerDurability = 12,

	CoinClickBase = 1,
	CoinClickFromStrength = 0.08,
	RebirthCoinBonus = 0.18,

	Stats = {
		Strength = {
			BaseCost = 10,
			CostGrowth = 1.12,
		},
		Durability = {
			BaseCost = 14,
			CostGrowth = 1.13,
		},
		Speed = {
			BaseCost = 70,
			CostGrowth = 1.145,
		},
		JumpPower = {
			BaseCost = 95,
			CostGrowth = 1.16,
		},
	},
}

function IncrementalConfig.GetStatCost(statName: string, currentValue: number): number
	local statConfig = IncrementalConfig.Stats[statName]
	if not statConfig then
		return math.huge
	end

	local scaledCost = statConfig.BaseCost * (statConfig.CostGrowth ^ currentValue)
	return math.max(1, math.floor(scaledCost + 0.5))
end

function IncrementalConfig.GetPower(strength: number, durability: number, speed: number, jumpPower: number): number
	return strength + durability + speed + jumpPower
end

return IncrementalConfig
