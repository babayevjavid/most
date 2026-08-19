--!strict

local ContentProvider = game:GetService("ContentProvider")

local GameConstants = require(script.Parent.GameConstants)

local AnimationPreload = {}

local ready = false
local listeners: { () -> () } = {}

local function notifyReady()
	for _, fn in listeners do
		task.spawn(fn)
	end
	table.clear(listeners)
end

function AnimationPreload.isReady(): boolean
	return ready
end

function AnimationPreload.onReady(fn: () -> ())
	if ready then
		task.spawn(fn)
		return
	end
	table.insert(listeners, fn)
end

local function collectFromConstants(): { Animation }
	local list: { Animation } = {}
	local seen: { [string]: boolean } = {}

	for key, value in GameConstants :: { [string]: any } do
		if type(key) ~= "string" or type(value) ~= "string" then
			continue
		end
		if not string.find(key, "ANIM", 1, true) then
			continue
		end
		if string.sub(value, 1, 13) ~= "rbxassetid://" then
			continue
		end
		if seen[value] then
			continue
		end
		seen[value] = true

		local anim = Instance.new("Animation")
		anim.Name = key
		anim.AnimationId = value
		table.insert(list, anim)
	end

	return list
end

local function collectFromFolder(folder: Instance): { Animation }
	local list: { Animation } = {}
	for _, child in folder:GetChildren() do
		if child:IsA("Animation") then
			table.insert(list, child)
		end
	end
	return list
end

function AnimationPreload.preload()
	if ready then
		return
	end

	local toPreload: { Instance } = {}
	local owned: { Animation } = {}

	local folder = script:FindFirstChild("Animations")
	if folder then
		for _, anim in collectFromFolder(folder) do
			table.insert(toPreload, anim)
		end
	end

	for _, anim in collectFromConstants() do
		table.insert(owned, anim)
		table.insert(toPreload, anim)
	end

	if #toPreload == 0 then
		ready = true
		notifyReady()
		return
	end

	local ok, err = pcall(function()
		ContentProvider:PreloadAsync(toPreload)
	end)
	if not ok then
		warn("[AnimationPreload] Preload failed:", err)
	end

	for _, anim in owned do
		anim:Destroy()
	end

	ready = true
	notifyReady()
end

return AnimationPreload
