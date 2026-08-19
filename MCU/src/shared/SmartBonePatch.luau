--!strict
--[[ Patches SmartBone Utilities.WaitForChildOfClass (os.clock vs os.clock()). ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SmartBonePatch = {}

local function patchUtilities(utilities: ModuleScript): boolean
	local ok, mod = pcall(require, utilities)
	if not ok or type(mod) ~= "table" or type(mod.WaitForChildOfClass) ~= "function" then
		return false
	end

	mod.WaitForChildOfClass = function(parent: Instance, className: string, timeOut: number?)
		local start = os.clock()
		timeOut = timeOut or 10
		repeat
			task.wait()
		until parent:FindFirstChildOfClass(className) or os.clock() - start > timeOut
		return parent:FindFirstChildOfClass(className)
	end

	return true
end

function SmartBonePatch.apply()
	local smartBone = ReplicatedStorage:FindFirstChild("SmartBone")
	if not smartBone then
		return false
	end
	local deps = smartBone:FindFirstChild("Dependencies")
	if not deps then
		return false
	end
	local utilities = deps:FindFirstChild("Utilities")
	if utilities and utilities:IsA("ModuleScript") then
		return patchUtilities(utilities)
	end
	return false
end

function SmartBonePatch.install()
	if SmartBonePatch.apply() then
		return
	end

	local conn: RBXScriptConnection? = nil
	conn = ReplicatedStorage.ChildAdded:Connect(function(child)
		if child.Name ~= "SmartBone" then
			return
		end
		task.defer(function()
			if SmartBonePatch.apply() and conn then
				conn:Disconnect()
				conn = nil
			end
		end)
	end)
end

return SmartBonePatch
