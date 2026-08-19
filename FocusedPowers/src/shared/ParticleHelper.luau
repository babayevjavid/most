--!strict
--[[ Shared particle attach / disable / delayed destroy. ]]

local ParticleHelper = {}

local DEFAULT_EMIT_COUNT = 10
local DEFAULT_DESTROY_DELAY = 5

local pendingDestroy: { [ParticleEmitter]: thread } = {}

local function cancelPendingDestroy(emitter: ParticleEmitter)
	local thread = pendingDestroy[emitter]
	if thread then
		task.cancel(thread)
		pendingDestroy[emitter] = nil
	end
end

function ParticleHelper.enableAndEmit(emitter: ParticleEmitter, emitCount: number?)
	cancelPendingDestroy(emitter)
	emitter.Enabled = true
	emitter:Emit(emitCount or DEFAULT_EMIT_COUNT)
end

function ParticleHelper.disableAndScheduleDestroy(emitter: ParticleEmitter, destroyDelay: number?)
	if not emitter.Parent then
		return
	end
	cancelPendingDestroy(emitter)
	emitter.Enabled = false
	local delay = destroyDelay or DEFAULT_DESTROY_DELAY
	pendingDestroy[emitter] = task.delay(delay, function()
		pendingDestroy[emitter] = nil
		if emitter.Parent then
			emitter:Destroy()
		end
	end)
end

function ParticleHelper.disableDescendantsAndScheduleDestroy(root: Instance, destroyDelay: number?)
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			ParticleHelper.disableAndScheduleDestroy(descendant, destroyDelay)
		end
	end
	if root:IsA("ParticleEmitter") then
		ParticleHelper.disableAndScheduleDestroy(root, destroyDelay)
	end
end

function ParticleHelper.destroyDescendantsAndSchedule(root: Instance, destroyDelay: number?)
	ParticleHelper.disableDescendantsAndScheduleDestroy(root, destroyDelay)
	if root:IsA("Folder") and #root:GetChildren() == 0 then
		task.delay(destroyDelay or DEFAULT_DESTROY_DELAY, function()
			if root.Parent then
				root:Destroy()
			end
		end)
	end
end

function ParticleHelper.cloneEmitter(template: ParticleEmitter, parent: Instance, emitCount: number?): ParticleEmitter
	local clone = template:Clone()
	clone.Parent = parent
	ParticleHelper.enableAndEmit(clone, emitCount)
	return clone
end

function ParticleHelper.cloneTemplate(template: Instance, parent: Instance, emitCount: number?): { ParticleEmitter }
	local created: { ParticleEmitter } = {}
	if template:IsA("ParticleEmitter") then
		table.insert(created, ParticleHelper.cloneEmitter(template, parent, emitCount))
		return created
	end
	for _, descendant in template:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			table.insert(created, ParticleHelper.cloneEmitter(descendant, parent, emitCount))
		end
	end
	return created
end

function ParticleHelper.parentAddedHook(parent: Instance)
	parent.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("ParticleEmitter") then
			ParticleHelper.enableAndEmit(descendant)
		end
	end)
	for _, descendant in parent:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			ParticleHelper.enableAndEmit(descendant)
		end
	end
end

return ParticleHelper
