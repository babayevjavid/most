--!strict
--[[
	Pink highlights for Telepathic Sense targets in range.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HudConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("HudConstants"))

local TelepathicSenseHighlight = {}

local highlights: { [Model]: Highlight } = {}

local function getOrCreateHighlight(model: Model): Highlight
	local existing = highlights[model]
	if existing and existing.Parent then
		return existing
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = "TelepathicSenseTarget"
	highlight.FillColor = HudConstants.COLOR_SECONDARY
	highlight.OutlineColor = HudConstants.COLOR_STROKE
	highlight.FillTransparency = 0.55
	highlight.OutlineTransparency = 0.05
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Adornee = model
	highlight.Parent = model
	highlights[model] = highlight
	return highlight
end

function TelepathicSenseHighlight.setTargets(models: { Model })
	local keep: { [Model]: boolean } = {}
	for _, model in models do
		if model.Parent then
			keep[model] = true
			local highlight = getOrCreateHighlight(model)
			highlight.Enabled = true
		end
	end

	for model, highlight in highlights do
		if not keep[model] then
			highlight.Enabled = false
		end
	end
end

function TelepathicSenseHighlight.clearAll()
	for _, highlight in highlights do
		highlight.Enabled = false
	end
end

function TelepathicSenseHighlight.setLocked(model: Model?)
	for m, highlight in highlights do
		if model and m == model then
			highlight.FillTransparency = 0.25
			highlight.OutlineTransparency = 0
		else
			highlight.FillTransparency = 0.55
			highlight.OutlineTransparency = 0.05
		end
	end
end

return TelepathicSenseHighlight
