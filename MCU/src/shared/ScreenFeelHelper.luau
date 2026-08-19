--!strict
--[[
	Victim / caster screen feel: CameraShake pulses plus held tint / speed-FOV attributes.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConstants = require(script.Parent.GameConstants)
local Remotes = require(script.Parent.Remotes)

local ScreenFeelHelper = {}

export type PulseOpts = {
	intensity: number?,
	duration: number?,
	fovScale: number?,
	vignetteScale: number?,
	tint: Color3?,
	tintDuration: number?,
}

function ScreenFeelHelper.pulsePlayer(player: Player, opts: PulseOpts)
	Remotes.getEvent("CameraShake"):FireClient(player, {
		intensity = opts.intensity or 0.45,
		duration = opts.duration or 0.35,
		fovScale = opts.fovScale,
		vignetteScale = opts.vignetteScale,
		tint = opts.tint,
		tintDuration = opts.tintDuration,
	})
end

function ScreenFeelHelper.pulseCharacter(character: Model, opts: PulseOpts)
	local player = Players:GetPlayerFromCharacter(character)
	if player then
		ScreenFeelHelper.pulsePlayer(player, opts)
	end
end

function ScreenFeelHelper.setTint(character: Model, color: Color3?, duration: number?)
	if not character.Parent then
		return
	end
	if color then
		character:SetAttribute(GameConstants.SCREEN_TINT_ATTRIBUTE, color)
		if type(duration) == "number" and duration > 0 then
			character:SetAttribute(GameConstants.SCREEN_TINT_UNTIL_ATTRIBUTE, Workspace:GetServerTimeNow() + duration)
		else
			character:SetAttribute(GameConstants.SCREEN_TINT_UNTIL_ATTRIBUTE, nil)
		end
	else
		character:SetAttribute(GameConstants.SCREEN_TINT_ATTRIBUTE, nil)
		character:SetAttribute(GameConstants.SCREEN_TINT_UNTIL_ATTRIBUTE, nil)
	end
end

function ScreenFeelHelper.setSpeedFov(character: Model, on: boolean)
	if not character.Parent then
		return
	end
	character:SetAttribute(GameConstants.SCREEN_SPEED_FOV_ATTRIBUTE, if on then true else nil)
end

function ScreenFeelHelper.setShakeHold(character: Model, on: boolean)
	if not character.Parent then
		return
	end
	character:SetAttribute(GameConstants.SCREEN_SHAKE_HOLD_ATTRIBUTE, if on then true else nil)
end

function ScreenFeelHelper.clear(character: Model)
	if not character.Parent then
		return
	end
	character:SetAttribute(GameConstants.SCREEN_TINT_ATTRIBUTE, nil)
	character:SetAttribute(GameConstants.SCREEN_TINT_UNTIL_ATTRIBUTE, nil)
	character:SetAttribute(GameConstants.SCREEN_SPEED_FOV_ATTRIBUTE, nil)
	character:SetAttribute(GameConstants.SCREEN_SHAKE_HOLD_ATTRIBUTE, nil)
end

return ScreenFeelHelper
