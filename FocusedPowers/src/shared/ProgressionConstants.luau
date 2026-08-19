--[[
	Progression tuning: slow early leveling, ability XP rewards.
]]

local ProgressionConstants = {}

-- XP required to advance FROM `level` TO `level + 1`
function ProgressionConstants.xpToNextLevel(level: number): number
	level = math.max(1, math.floor(level))
	return math.floor(450 * (level ^ 2.05))
end

ProgressionConstants.STARTING_LEVEL = 1
ProgressionConstants.STARTING_XP = 0
ProgressionConstants.STARTING_COINS = 0

ProgressionConstants.ABILITY_XP = {
	Telekinesis = {
		start = 12,
		holdPerSecond = 5,
		throw = 30,
		release = 8,
	},
}

return ProgressionConstants
