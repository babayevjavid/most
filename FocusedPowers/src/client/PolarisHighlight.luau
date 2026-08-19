--!strict
--[[ Green Highlight overlays for Polaris targets and flight (outline only). ]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PolarisConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PolarisConstants"))

local OUTLINE = PolarisConstants.POLARIS_GREEN_BRIGHT

local PolarisHighlight = {}

local hoverHl: Highlight? = nil
local heldHl: Highlight? = nil
local flightHl: Highlight? = nil
local shardHls: { [Instance]: Highlight } = {}

local function getContainer(): Instance
	local player = Players.LocalPlayer
	local gui = player:FindFirstChildOfClass("PlayerGui")
	if gui then
		local folder = gui:FindFirstChild("PolarisHighlights")
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = "PolarisHighlights"
			folder.Parent = gui
		end
		return folder
	end
	return workspace
end

local function destroyHl(hl: Highlight?)
	if hl and hl.Parent then
		hl:Destroy()
	end
end

local function makeHighlight(adornee: Instance, strong: boolean): Highlight
	local hl = Instance.new("Highlight")
	hl.Adornee = adornee
	hl.FillTransparency = 1
	hl.OutlineColor = OUTLINE
	hl.OutlineTransparency = if strong then 0.1 else 0.35
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Parent = getContainer()
	return hl
end

function PolarisHighlight.setHover(adornee: Instance?)
	destroyHl(hoverHl)
	hoverHl = nil
	if adornee then
		hoverHl = makeHighlight(adornee, false)
	end
end

function PolarisHighlight.setHeld(adornee: Instance?)
	destroyHl(heldHl)
	heldHl = nil
	if adornee then
		heldHl = makeHighlight(adornee, true)
	end
end

function PolarisHighlight.setFlight(character: Model?)
	destroyHl(flightHl)
	flightHl = nil
	if character then
		flightHl = makeHighlight(character, true)
	end
end

function PolarisHighlight.setShard(part: BasePart, enabled: boolean)
	local existing = shardHls[part]
	if existing then
		destroyHl(existing)
		shardHls[part] = nil
	end
	if enabled and part.Parent then
		shardHls[part] = makeHighlight(part, false)
	end
end

function PolarisHighlight.flashHit(adornee: Instance, duration: number?)
	local hl = makeHighlight(adornee, true)
	task.delay(duration or 0.35, function()
		if hl.Parent then
			hl:Destroy()
		end
	end)
end

function PolarisHighlight.clearAll()
	destroyHl(hoverHl)
	destroyHl(heldHl)
	destroyHl(flightHl)
	hoverHl = nil
	heldHl = nil
	flightHl = nil
	for part, hl in shardHls do
		destroyHl(hl)
		shardHls[part] = nil
	end
end

return PolarisHighlight
