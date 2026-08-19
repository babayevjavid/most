--!strict
--[[ Client-side gameplay settings: screen shake/VFX, ability zoom, graphics quality. ]]

export type GraphicsQuality = "High" | "Low"

local ClientSettings = {}

local screenShakeEnabled = true
local screenVfxEnabled = true
local abilityZoomEnabled = true
local graphicsQuality: GraphicsQuality = "High"
local listeners: { () -> () } = {}

local function notify()
	for _, fn in listeners do
		task.spawn(fn)
	end
end

function ClientSettings.onChanged(fn: () -> ())
	table.insert(listeners, fn)
end

function ClientSettings.isScreenShakeEnabled(): boolean
	return screenShakeEnabled
end

function ClientSettings.setScreenShakeEnabled(on: boolean)
	screenShakeEnabled = on == true
	notify()
end

function ClientSettings.isScreenVfxEnabled(): boolean
	return screenVfxEnabled
end

function ClientSettings.setScreenVfxEnabled(on: boolean)
	screenVfxEnabled = on == true
	notify()
end

function ClientSettings.isAbilityZoomEnabled(): boolean
	return abilityZoomEnabled
end

function ClientSettings.setAbilityZoomEnabled(on: boolean)
	abilityZoomEnabled = on == true
	notify()
end

function ClientSettings.getGraphicsQuality(): GraphicsQuality
	return graphicsQuality
end

function ClientSettings.setGraphicsQuality(quality: GraphicsQuality)
	if quality ~= "High" and quality ~= "Low" then
		return
	end
	graphicsQuality = quality
	notify()
end

function ClientSettings.getParticleMul(): number
	return if graphicsQuality == "Low" then 0.4 else 1
end

function ClientSettings.getVignetteMul(): number
	return if graphicsQuality == "Low" then 0.55 else 1
end

return ClientSettings
