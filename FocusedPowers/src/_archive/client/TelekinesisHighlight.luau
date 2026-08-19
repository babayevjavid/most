--!strict
--[[
	Pink Highlight instances for telekinesis hover and held targets.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HudConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("HudConstants"))
local TargetingHelper = require(script.Parent:WaitForChild("TargetingHelper"))

local TelekinesisHighlight = {}

local highlights: { [Instance]: Highlight } = {}
local hoverAdornee: Instance? = nil
local heldAdornees: { [Instance]: boolean } = {}

local function removeHighlight(adornee: Instance)
	local highlight = highlights[adornee]
	if highlight then
		highlight:Destroy()
		highlights[adornee] = nil
	end
end

local function getOrCreateHighlight(adornee: Instance): Highlight
	local existing = highlights[adornee]
	if existing and existing.Parent then
		return existing
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = "TelekinesisTarget"
	highlight.FillColor = HudConstants.COLOR_PRIMARY
	highlight.OutlineColor = HudConstants.COLOR_STROKE
	highlight.FillTransparency = 0.65
	highlight.OutlineTransparency = 0.15
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Adornee = adornee
	highlight.Parent = adornee
	highlights[adornee] = highlight
	return highlight
end

local function setHighlightVisible(adornee: Instance, visible: boolean, stronger: boolean)
	if not adornee.Parent then
		removeHighlight(adornee)
		return
	end
	local highlight = getOrCreateHighlight(adornee)
	highlight.Enabled = visible
	if stronger then
		highlight.FillTransparency = 0.45
		highlight.OutlineTransparency = 0
	else
		highlight.FillTransparency = 0.65
		highlight.OutlineTransparency = 0.15
	end
end

local function clearAdornee(adornee: Instance?)
	if not adornee then
		return
	end
	removeHighlight(adornee)
end

function TelekinesisHighlight.setHover(part: BasePart?)
	local newAdornee = if part then TargetingHelper.getHighlightAdornee(part) else nil
	if hoverAdornee == newAdornee then
		if newAdornee and not heldAdornees[newAdornee] then
			setHighlightVisible(newAdornee, true, false)
		end
		return
	end

	clearAdornee(hoverAdornee)
	hoverAdornee = newAdornee
	if hoverAdornee and not heldAdornees[hoverAdornee] then
		setHighlightVisible(hoverAdornee, true, false)
	end
end

function TelekinesisHighlight.setHeld(part: BasePart?)
	TelekinesisHighlight.setHeldMany(if part then { part } else {})
end

function TelekinesisHighlight.setHeldMany(parts: { BasePart })
	local newHeld: { [Instance]: boolean } = {}
	for _, part in parts do
		if part.Parent then
			local adornee = TargetingHelper.getHighlightAdornee(part)
			newHeld[adornee] = true
			setHighlightVisible(adornee, true, true)
		end
	end

	for adornee in heldAdornees do
		if not newHeld[adornee] then
			clearAdornee(adornee)
		end
	end

	heldAdornees = newHeld

	if next(newHeld) ~= nil then
		clearAdornee(hoverAdornee)
		hoverAdornee = nil
	end
end

function TelekinesisHighlight.clearAll()
	for adornee in heldAdornees do
		clearAdornee(adornee)
	end
	table.clear(heldAdornees)
	clearAdornee(hoverAdornee)
	hoverAdornee = nil
end

return TelekinesisHighlight
