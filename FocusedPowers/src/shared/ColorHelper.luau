--!strict
--[[
	Shared color utilities for character-themed UI.
]]

local ColorHelper = {}

function ColorHelper.blend(base: Color3, accent: Color3, accentWeight: number): Color3
	local weight = math.clamp(accentWeight, 0, 1)
	local baseWeight = 1 - weight
	return Color3.new(
		base.R * baseWeight + accent.R * weight,
		base.G * baseWeight + accent.G * weight,
		base.B * baseWeight + accent.B * weight
	)
end

function ColorHelper.energyGradient(accent: Color3): (Color3, Color3)
	local start = accent
	local finish = Color3.new(
		math.clamp(accent.R * 0.5, 0, 1),
		math.clamp(accent.G * 0.45, 0, 1),
		math.clamp(accent.B * 0.65 + 0.08, 0, 1)
	)
	return start, finish
end

function ColorHelper.selectionCardBackground(accent: Color3): Color3
	return ColorHelper.blend(Color3.fromRGB(20, 18, 32), accent, 0.22)
end

return ColorHelper
