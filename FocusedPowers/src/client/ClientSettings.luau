--!strict
--[[ Client-only gameplay settings (session memory). ]]

local ClientSettings = {}

local lockOnEnabled = true
local abilityScreenEffectsEnabled = true
local lockOnChangedCallbacks: { (enabled: boolean) -> () } = {}
local screenEffectsChangedCallbacks: { (enabled: boolean) -> () } = {}

function ClientSettings.isLockOnEnabled(): boolean
	return lockOnEnabled
end

function ClientSettings.setLockOnEnabled(enabled: boolean)
	if lockOnEnabled == enabled then
		return
	end
	lockOnEnabled = enabled
	for _, callback in lockOnChangedCallbacks do
		callback(enabled)
	end
end

function ClientSettings.isAbilityScreenEffectsEnabled(): boolean
	return abilityScreenEffectsEnabled
end

function ClientSettings.setAbilityScreenEffectsEnabled(enabled: boolean)
	if abilityScreenEffectsEnabled == enabled then
		return
	end
	abilityScreenEffectsEnabled = enabled
	for _, callback in screenEffectsChangedCallbacks do
		callback(enabled)
	end
end

function ClientSettings.onLockOnChanged(callback: (enabled: boolean) -> ())
	table.insert(lockOnChangedCallbacks, callback)
	return function()
		local idx = table.find(lockOnChangedCallbacks, callback)
		if idx then
			table.remove(lockOnChangedCallbacks, idx)
		end
	end
end

function ClientSettings.onAbilityScreenEffectsChanged(callback: (enabled: boolean) -> ())
	table.insert(screenEffectsChangedCallbacks, callback)
	return function()
		local idx = table.find(screenEffectsChangedCallbacks, callback)
		if idx then
			table.remove(screenEffectsChangedCallbacks, idx)
		end
	end
end

return ClientSettings
