--!strict
--[[ Per-character solar exposure: time-of-day + outdoors + sun line-of-sight. ]]

local Lighting = game:GetService("Lighting")

local DayCycleHelper = require(script.Parent:WaitForChild("DayCycleHelper"))
local SunspotConstants = require(script.Parent:WaitForChild("SunspotConstants"))

local CHARGE = SunspotConstants.SolarCharge

local SunspotSolarHelper = {}

local function getClockTime(): number
	local clock = workspace:GetAttribute("DayCycleClockTime")
	if typeof(clock) == "number" then
		return clock
	end
	return Lighting.ClockTime
end

function SunspotSolarHelper.getPhaseIntensity(): number
	local solar = workspace:GetAttribute("DayCycleSolarIntensity")
	if typeof(solar) == "number" then
		return math.clamp(solar, 0, 1)
	end
	return DayCycleHelper.getSolarIntensity(getClockTime())
end

function SunspotSolarHelper.isOutdoors(character: Model): boolean
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }

	local origin = root.Position + Vector3.new(0, 1.5, 0)
	local ceilingHit = workspace:Raycast(origin, Vector3.new(0, 120, 0), params)
	if ceilingHit == nil then
		return true
	end
	return ceilingHit.Distance > 28
end

local function getSunSampleOrigin(character: Model): Vector3?
	local head = character:FindFirstChild("Head") :: BasePart?
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if head then
		return head.Position + Vector3.new(0, 0.5, 0)
	end
	if root then
		return root.Position + Vector3.new(0, 2.5, 0)
	end
	return nil
end

function SunspotSolarHelper.getSunVisibility(character: Model): number
	local phase = SunspotSolarHelper.getPhaseIntensity()
	if phase <= 0.001 then
		return 0
	end

	if not SunspotSolarHelper.isOutdoors(character) then
		return 0.06 * phase
	end

	local origin = getSunSampleOrigin(character)
	if not origin then
		return 0
	end

	local sunDir = Lighting:GetSunDirection()
	if sunDir.Magnitude < 0.01 then
		return math.max(0.75, phase)
	end

	local towardSun = (-sunDir).Unit
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }

	local hit = workspace:Raycast(origin, towardSun * 800, params)
	if hit == nil then
		return 1
	end

	if hit.Distance > 140 then
		return 0.82
	end

	if towardSun.Y > 0.12 and phase > 0.35 then
		return 0.22
	end

	return 0.1
end

function SunspotSolarHelper.getEffectiveStrength(character: Model): number
	local live = SunspotSolarHelper.computeTargetStrength(character)
	local stored = SunspotSolarHelper.getStoredStrength(character)
	return math.max(live, stored)
end

function SunspotSolarHelper.computeTargetStrength(character: Model): number
	local phase = SunspotSolarHelper.getPhaseIntensity()
	if phase <= 0.001 then
		return 0
	end
	return math.clamp(phase * SunspotSolarHelper.getSunVisibility(character), 0, 1)
end

function SunspotSolarHelper.getStoredStrength(character: Model): number
	local value = character:GetAttribute("SunspotStrength")
	if typeof(value) == "number" then
		return math.clamp(value, 0, 1)
	end
	return 0
end

function SunspotSolarHelper.isUnderDirectSun(character: Model): boolean
	if SunspotSolarHelper.getPhaseIntensity() < CHARGE.MIN_PHASE_FOR_FREE then
		return false
	end
	return SunspotSolarHelper.getSunVisibility(character) >= CHARGE.MIN_SUN_VISIBILITY_FOR_FREE
end

function SunspotSolarHelper.hasFreeSolarEnergy(character: Model): boolean
	if SunspotSolarHelper.getStoredStrength(character) < CHARGE.FULL_FREE_ENERGY_THRESHOLD then
		return false
	end
	return SunspotSolarHelper.isUnderDirectSun(character)
end

function SunspotSolarHelper.isInDirectSunlight(character: Model): boolean
	return SunspotSolarHelper.computeTargetStrength(character) >= SunspotConstants.Photosynthesis.MIN_SUN_STRENGTH
end

function SunspotSolarHelper.canStartPhotosynthesis(character: Model): boolean
	if SunspotSolarHelper.isInDirectSunlight(character) then
		return true
	end
	local energy = character:GetAttribute("Energy")
	return typeof(energy) == "number" and energy >= SunspotConstants.Photosynthesis.MIN_ENERGY_TO_START
end

function SunspotSolarHelper.canStartBlackSun(character: Model): boolean
	if SunspotSolarHelper.getPhaseIntensity() < 0.06 then
		return false
	end
	return SunspotSolarHelper.getEffectiveStrength(character) >= SunspotConstants.BlackSun.MIN_START_STRENGTH
end

return SunspotSolarHelper
