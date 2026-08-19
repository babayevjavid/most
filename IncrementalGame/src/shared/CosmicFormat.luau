local CosmicFormat = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

function CosmicFormat.Number(value: number): string
	local absValue = math.abs(value)
	if absValue < 1000 then
		return tostring(math.floor(value + 0.5))
	end

	local tier = math.min(math.floor(math.log10(absValue) / 3), #SUFFIXES - 1)
	local scaled = value / (10 ^ (tier * 3))

	if scaled >= 100 then
		return string.format("%.0f%s", scaled, SUFFIXES[tier + 1])
	end
	if scaled >= 10 then
		return string.format("%.1f%s", scaled, SUFFIXES[tier + 1])
	end
	return string.format("%.2f%s", scaled, SUFFIXES[tier + 1])
end

function CosmicFormat.Multiplier(value: number): string
	return string.format("x%.2f", value)
end

return CosmicFormat
