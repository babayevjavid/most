--!strict
--[[
	Flat ground mark while holding E to place Illusion Decoy.
]]

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConstants = require(ReplicatedStorage.Shared.GameConstants)
local AbilityCooldownHelper = require(ReplicatedStorage.Shared.AbilityCooldownHelper)
local MouseHelper = require(script.Parent.MouseHelper)

local LokiDecoyMarkerClient = {}

local MARK_SIZE = 4.2
local MARK_COLOR = Color3.fromRGB(90, 255, 130)

local function makeMarker(): BasePart
	local disk = Instance.new("Part")
	disk.Name = "LokiDecoyPlaceMark"
	disk.Shape = Enum.PartType.Cylinder
	disk.Size = Vector3.new(0.12, MARK_SIZE, MARK_SIZE)
	disk.Material = Enum.Material.Neon
	disk.Color = MARK_COLOR
	disk.Transparency = 0.35
	disk.Anchored = true
	disk.CanCollide = false
	disk.CanQuery = false
	disk.CanTouch = false
	disk.CastShadow = false
	disk.Parent = Workspace
	return disk
end

local function groundAt(player: Player): Vector3?
	local hit = MouseHelper.getHitPosition(player, 120)
	local char = player.Character
	local origin = hit + Vector3.new(0, 2, 0)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if char then { char } else {}
	local result = Workspace:Raycast(origin, Vector3.new(0, -40, 0), params)
	if result then
		return result.Position
	end
	return Vector3.new(hit.X, hit.Y, hit.Z)
end

function LokiDecoyMarkerClient.init(player: Player)
	local marker: BasePart? = nil

	local function hide()
		if marker then
			marker:Destroy()
			marker = nil
		end
	end

	RunService.RenderStepped:Connect(function()
		local character = player.Character
		if
			not character
			or character:GetAttribute(GameConstants.HERO_ATTRIBUTE) ~= "loki"
			or character:GetAttribute(GameConstants.LOKI_CLONE_ACTIVE_ATTRIBUTE) == true
			or not UserInputService:IsKeyDown(Enum.KeyCode.E)
			or AbilityCooldownHelper.isOnCooldown(character, "illusion_decoy")
		then
			hide()
			return
		end

		local pos = groundAt(player)
		if not pos then
			hide()
			return
		end

		if not marker or not marker.Parent then
			marker = makeMarker()
		end
		local mark = marker :: BasePart
		-- Cylinder default axis is +X; lay flat on ground
		mark.CFrame = CFrame.new(pos + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.rad(90))
	end)
end

return LokiDecoyMarkerClient
