--!strict
--[[
	While aiming abilities (TK hold, teleport aim, etc.), freeze camera zoom
	so mouse wheel drives the ability distance — not camera distance.
	Does not Sink the wheel (AbilityInput / TeleportMarkerClient handle it).
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConstants = require(ReplicatedStorage.Shared.GameConstants)

local AbilityCameraGuard = {}

local player: Player? = nil
local frozen = false
local savedMin: number? = nil
local savedMax: number? = nil

local function setZoomRange(plr: Player, minZoom: number, maxZoom: number)
	local lo = math.clamp(minZoom, 0.5, 128)
	local hi = math.clamp(maxZoom, lo, 128)
	if lo > hi then
		lo, hi = hi, lo
	end
	if plr.CameraMinZoomDistance > hi then
		plr.CameraMaxZoomDistance = hi
	end
	plr.CameraMinZoomDistance = lo
	plr.CameraMaxZoomDistance = hi
end

local function currentZoom(): number
	local cam = workspace.CurrentCamera
	if not cam then
		return 12
	end
	local focus = cam.Focus.Position
	return math.clamp((cam.CFrame.Position - focus).Magnitude, 0.5, 128)
end

local function shouldFreeze(character: Model?): boolean
	if not character then
		return false
	end
	if character:GetAttribute(GameConstants.TK_ACTIVE_ATTRIBUTE) == true then
		return true
	end
	if character:GetAttribute(GameConstants.TELEPORT_AIMING_ATTRIBUTE) == true then
		return true
	end
	return false
end

local function freezeZoom()
	local plr = player
	if not plr or frozen then
		return
	end
	local z = currentZoom()
	savedMin = plr.CameraMinZoomDistance
	savedMax = plr.CameraMaxZoomDistance
	setZoomRange(plr, z, z)
	frozen = true
end

local function unfreezeZoom()
	local plr = player
	if not frozen then
		return
	end
	frozen = false
	if plr then
		local restoreMin = if typeof(savedMin) == "number" then savedMin :: number else 0.5
		local restoreMax = if typeof(savedMax) == "number" then savedMax :: number else 128
		setZoomRange(plr, restoreMin, restoreMax)
	end
	savedMin = nil
	savedMax = nil
end

function AbilityCameraGuard.init(localPlayer: Player)
	player = localPlayer

	local function sync()
		local character = localPlayer.Character
		if shouldFreeze(character) then
			if not frozen then
				freezeZoom()
			else
				-- Keep zoom locked even if something else tries to change limits
				local z = math.clamp(currentZoom(), 0.5, 128)
				setZoomRange(localPlayer, z, z)
			end
		else
			unfreezeZoom()
		end
	end

	RunService.RenderStepped:Connect(sync)
	localPlayer.CharacterAdded:Connect(function()
		unfreezeZoom()
	end)
	localPlayer.CharacterRemoving:Connect(function()
		unfreezeZoom()
	end)
end

return AbilityCameraGuard
