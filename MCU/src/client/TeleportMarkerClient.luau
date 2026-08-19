--!strict
--[[
	Aim mark while teleport aiming:
	- Follows mouse cursor (clamped to scrollable max range)
	- Scarlet Witch: air allowed at cursor hit
	- Loki: ground-snapped disk
	Scroll = how far the pad is allowed to go from the caster.
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConstants = require(ReplicatedStorage.Shared.GameConstants)
local MouseHelper = require(script.Parent.MouseHelper)

local TeleportMarkerClient = {}

local DEFAULT_MIN = 8
local DEFAULT_MAX = 85
local DEFAULT_SCROLL_STEP = 5

local player: Player? = nil
local marker: BasePart? = nil
local aimDistance = 40
local lastAimWorld: Vector3? = nil
local wasAiming = false

local function makeMarker(color: Color3, size: number): BasePart
	local disk = Instance.new("Part")
	disk.Name = "TeleportPlaceMark"
	disk.Shape = Enum.PartType.Cylinder
	disk.Size = Vector3.new(0.14, size, size)
	disk.Material = Enum.Material.Neon
	disk.Color = color
	disk.Transparency = 0.32
	disk.Anchored = true
	disk.CanCollide = false
	disk.CanQuery = false
	disk.CanTouch = false
	disk.CastShadow = false
	disk.Parent = Workspace
	return disk
end

local function hide()
	if marker then
		marker:Destroy()
		marker = nil
	end
	lastAimWorld = nil
end

local function maxRangeForHero(hero: string?): number
	if hero == "loki" then
		local v = GameConstants.LOKI_TELEPORT_RANGE
		return if type(v) == "number" then v else 50
	end
	local v = GameConstants.TELEPORT_RANGE
	return if type(v) == "number" then v else DEFAULT_MAX
end

local function minRange(): number
	local v = GameConstants.TELEPORT_AIM_DIST_MIN
	return if type(v) == "number" then v else DEFAULT_MIN
end

local function scrollStep(): number
	local v = GameConstants.TELEPORT_SCROLL_STEP
	return if type(v) == "number" then v else DEFAULT_SCROLL_STEP
end

local function clampRange(value: number, minV: number, maxV: number): number
	local lo = math.min(minV, maxV)
	local hi = math.max(minV, maxV)
	return math.clamp(value, lo, hi)
end

local function clampToRange(from: Vector3, to: Vector3, range: number): Vector3
	local offset = to - from
	if offset.Magnitude > range then
		return from + offset.Unit * range
	end
	return to
end

local function groundSnap(character: Model, dest: Vector3, rootY: number): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local result = Workspace:Raycast(dest + Vector3.new(0, 6, 0), Vector3.new(0, -80, 0), params)
	if result then
		return result.Position
	end
	return Vector3.new(dest.X, rootY - 3, dest.Z)
end

function TeleportMarkerClient.adjustRange(scrollDelta: number)
	local step = if scrollDelta > 0 then scrollStep() else -scrollStep()
	local plr = player
	local character = plr and plr.Character
	local hero = character and character:GetAttribute(GameConstants.HERO_ATTRIBUTE)
	local maxR = maxRangeForHero(if type(hero) == "string" then hero else nil)
	aimDistance = clampRange(aimDistance + step, minRange(), maxR)
end

function TeleportMarkerClient.getAimWorldPosition(): Vector3?
	return lastAimWorld
end

function TeleportMarkerClient.init(localPlayer: Player)
	player = localPlayer

	RunService.RenderStepped:Connect(function()
		local character = localPlayer.Character
		local aiming = character ~= nil and character:GetAttribute(GameConstants.TELEPORT_AIMING_ATTRIBUTE) == true
		if not aiming then
			if wasAiming then
				hide()
				wasAiming = false
			end
			return
		end

		local hero = character:GetAttribute(GameConstants.HERO_ATTRIBUTE)
		local maxR = maxRangeForHero(if type(hero) == "string" then hero else nil)
		local minR = minRange()
		local color = Color3.fromRGB(210, 70, 90)
		local allowAir = false
		if hero == "loki" then
			color = Color3.fromRGB(90, 255, 130)
		elseif hero == "scarlet_witch" then
			allowAir = true
		else
			hide()
			wasAiming = false
			return
		end

		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			hide()
			return
		end

		if not wasAiming then
			-- Start range at current mouse distance (so pad appears under cursor immediately)
			local seedHit = MouseHelper.getHitPosition(localPlayer, maxR + 40)
			aimDistance = clampRange((seedHit - root.Position).Magnitude, minR, maxR)
			wasAiming = true
		end

		aimDistance = clampRange(aimDistance, minR, maxR)

		-- Wanda: aim wherever the cursor points (clamped to max range). Loki: scrollable range.
		local rangeCap = if allowAir then maxR else aimDistance
		local mouseHit = MouseHelper.getHitPosition(localPlayer, math.max(rangeCap + 40, 160))
		local pos: Vector3
		if allowAir then
			pos = clampToRange(root.Position, mouseHit, rangeCap)
		else
			local flat = clampToRange(
				root.Position,
				Vector3.new(mouseHit.X, root.Position.Y, mouseHit.Z),
				aimDistance
			)
			pos = groundSnap(character, flat, root.Position.Y)
		end
		lastAimWorld = pos

		if not marker or not marker.Parent then
			marker = makeMarker(color, if allowAir then 3.6 else 5.2)
		else
			marker.Color = color
		end
		local mark = marker :: BasePart
		mark.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
	end)

	localPlayer.CharacterRemoving:Connect(function()
		hide()
		wasAiming = false
	end)
end

return TeleportMarkerClient
