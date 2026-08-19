--!strict
--[[ Sunspot VFX: smooth black body tint + solar particles during flight. ]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ParticleHelper = require(Shared:WaitForChild("ParticleHelper"))
local SunspotConstants = require(Shared:WaitForChild("SunspotConstants"))

local BLACK_TARGET = SunspotConstants.BLACK_SOLAR
local UPPERCUT_EMPOWER = SunspotConstants.SunUppercut.EMPOWER_DURATION
local COLOR_LERP_TAU = 0.22
local PARTICLE_FOLDER_NAME = "SunspotFlightParticles"
local UPPERCUT_PARTICLE_FOLDER_NAME = "SunspotUppercutParticles"
local BODY_EMIT_COUNT = 8
local UPPERCUT_EMIT_COUNT = 10
local EMIT_INTERVAL = 0.32
local EMIT_TICK_COUNT = 3

local lastBodyEmitAt = 0
local lastUppercutEmitAt = 0

local RIGHT_ARM_NAMES: { [string]: boolean } = {
	RightUpperArm = true,
	RightLowerArm = true,
	RightHand = true,
	["Right Arm"] = true,
}

local SunspotAbilityVfx = {}

type PartState = {
	originalColor: Color3,
	particleFolder: Folder?,
	emitters: { ParticleEmitter },
}

local partStates: { [BasePart]: PartState } = {}
local uppercutPartStates: { [BasePart]: PartState } = {}
local displayBlend = 0
local trackedCharacter: Model? = nil
local particleTemplates: { Instance }? = nil

local function getParticleTemplates(): { Instance }
	if particleTemplates then
		return particleTemplates
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local sunspot = if assets then assets:FindFirstChild("Sunspot") else nil
	local bodyParticles = if sunspot then sunspot:FindFirstChild("BodyParticles") else nil
	local templates: { Instance } = {}
	if bodyParticles then
		for _, childName in { "SolarDots", "Dots" } do
			local template = bodyParticles:FindFirstChild(childName)
			if template then
				table.insert(templates, template)
			end
		end
	end
	particleTemplates = templates
	return templates
end

local function cloneBurstEmitter(template: ParticleEmitter, parent: Instance, emitCount: number): ParticleEmitter
	local clone = template:Clone()
	clone.Enabled = false
	clone:SetAttribute("SunspotFlightParticle", true)
	clone.Parent = parent
	clone:Emit(emitCount)
	return clone
end

local function cloneBurstTemplate(template: Instance, parent: Instance, emitCount: number): { ParticleEmitter }
	local created: { ParticleEmitter } = {}
	if template:IsA("ParticleEmitter") then
		table.insert(created, cloneBurstEmitter(template, parent, emitCount))
		return created
	end
	for _, descendant in template:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			table.insert(created, cloneBurstEmitter(descendant, parent, emitCount))
		end
	end
	return created
end

local function emitBurstOnState(state: PartState, emitCount: number)
	for _, emitter in state.emitters do
		if emitter.Parent then
			emitter:Emit(emitCount)
		end
	end
end

local function attachBurstParticles(
	part: BasePart,
	state: PartState,
	folderName: string,
	emitCount: number
)
	if #state.emitters > 0 then
		return
	end
	local templates = getParticleTemplates()
	if #templates == 0 then
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = folderName
	folder.Parent = part
	state.particleFolder = folder

	for _, template in templates do
		for _, emitter in cloneBurstTemplate(template, part, emitCount) do
			table.insert(state.emitters, emitter)
		end
	end
end

local function isBodyPart(part: Instance): boolean
	return part:IsA("BasePart") and part.Name ~= "Handle"
end

local function isRightArmPart(part: BasePart): boolean
	return RIGHT_ARM_NAMES[part.Name] == true
end

local function getUppercutBlend(character: Model): number
	local untilTime = character:GetAttribute("SunUppercutEmpowerUntil")
	if typeof(untilTime) ~= "number" then
		return 0
	end
	local remaining = untilTime - tick()
	if remaining <= 0 then
		return 0
	end
	local elapsed = UPPERCUT_EMPOWER - remaining
	if elapsed < 0.1 then
		return math.clamp(elapsed / 0.1, 0, 1)
	end
	if remaining < 0.28 then
		return math.clamp(remaining / 0.28, 0, 1)
	end
	return 1
end

local function attachBodyParticles(part: BasePart, state: PartState)
	attachBurstParticles(part, state, PARTICLE_FOLDER_NAME, BODY_EMIT_COUNT)
end

local function attachUppercutParticles(part: BasePart, state: PartState)
	attachBurstParticles(part, state, UPPERCUT_PARTICLE_FOLDER_NAME, UPPERCUT_EMIT_COUNT)
end

local function removeParticles(_part: BasePart, state: PartState)
	for _, emitter in state.emitters do
		if emitter.Parent then
			ParticleHelper.disableAndScheduleDestroy(emitter)
		end
	end
	table.clear(state.emitters)
	if state.particleFolder then
		task.delay(5, function()
			if state.particleFolder and state.particleFolder.Parent then
				state.particleFolder:Destroy()
			end
		end)
		state.particleFolder = nil
	end
end

local function ensureUppercutPartState(part: BasePart)
	if uppercutPartStates[part] then
		return
	end
	uppercutPartStates[part] = {
		originalColor = part.Color,
		particleFolder = nil,
		emitters = {},
	}
end

local function clearUppercutPartStates()
	for part, state in uppercutPartStates do
		if part.Parent and state.originalColor then
			part.Color = state.originalColor
		end
		removeParticles(part, state)
	end
	table.clear(uppercutPartStates)
end

local function clearPartStates()
	for part, state in partStates do
		if part.Parent and state.originalColor then
			part.Color = state.originalColor
		end
		removeParticles(part, state)
	end
	table.clear(partStates)
	clearUppercutPartStates()
	displayBlend = 0
	trackedCharacter = nil
	lastBodyEmitAt = 0
	lastUppercutEmitAt = 0
end

local function ensurePartState(part: BasePart)
	if partStates[part] then
		return
	end
	partStates[part] = {
		originalColor = part.Color,
		particleFolder = nil,
		emitters = {},
	}
end

local function refreshCharacterParts(character: Model)
	for _, inst in character:GetDescendants() do
		if isBodyPart(inst) then
			ensurePartState(inst :: BasePart)
		end
	end
end

local function refreshUppercutArmParts(character: Model)
	for _, inst in character:GetDescendants() do
		if inst:IsA("BasePart") and isRightArmPart(inst) then
			ensureUppercutPartState(inst)
		end
	end
end

local function applyUppercutArmVisuals(character: Model, blend: number)
	if blend <= 0.001 then
		clearUppercutPartStates()
		return
	end

	refreshUppercutArmParts(character)
	for part, state in uppercutPartStates do
		if not part.Parent then
			continue
		end
		part.Color = state.originalColor:Lerp(BLACK_TARGET, blend)
		if blend > 0.3 and #state.emitters == 0 then
			attachUppercutParticles(part, state)
		elseif blend < 0.15 then
			removeParticles(part, state)
		end
	end
end

function SunspotAbilityVfx.start(player: Player)
	local function bindCharacter(character: Model?)
		clearPartStates()
		if character then
			trackedCharacter = character
			refreshCharacterParts(character)
			character.DescendantAdded:Connect(function(inst)
				if trackedCharacter == character and isBodyPart(inst) then
					ensurePartState(inst :: BasePart)
				end
			end)
		end
	end

	bindCharacter(player.Character)
	player.CharacterAdded:Connect(bindCharacter)
	player.CharacterRemoving:Connect(function()
		clearPartStates()
	end)

	RunService.Heartbeat:Connect(function(dt)
		local character = trackedCharacter
		if not character or not character.Parent then
			if displayBlend > 0.001 then
				displayBlend = math.max(0, displayBlend - dt / COLOR_LERP_TAU)
			end
			return
		end

		if player:GetAttribute("SelectedCharacter") ~= "Sunspot" then
			if displayBlend > 0 then
				local decay = 1 - math.exp(-dt / COLOR_LERP_TAU)
				displayBlend = math.max(0, displayBlend - decay)
			end
		else
			local flying = character:GetAttribute("IsSolarFlying") == true
			local photosynthesis = character:GetAttribute("IsPhotosynthesisActive") == true
			local blackSunCharging = character:GetAttribute("IsBlackSunCharging") == true
			local targetBlend = if flying or photosynthesis or blackSunCharging then 1 else 0
			local alpha = 1 - math.exp(-dt / COLOR_LERP_TAU)
			displayBlend += (targetBlend - displayBlend) * alpha
		end

		refreshCharacterParts(character)
		local uppercutBlend = if player:GetAttribute("SelectedCharacter") == "Sunspot"
			then getUppercutBlend(character)
			else 0

		for part, state in partStates do
			if not part.Parent then
				continue
			end
			if uppercutBlend > 0.01 and isRightArmPart(part) then
				continue
			end
			part.Color = state.originalColor:Lerp(BLACK_TARGET, displayBlend)
			if displayBlend > 0.3 and #state.emitters == 0 then
				attachBodyParticles(part, state)
			elseif displayBlend < 0.15 then
				removeParticles(part, state)
			end
		end

		if displayBlend > 0.3 then
			local now = tick()
			if now - lastBodyEmitAt >= EMIT_INTERVAL then
				lastBodyEmitAt = now
				for _, state in partStates do
					emitBurstOnState(state, EMIT_TICK_COUNT)
				end
			end
		end

		applyUppercutArmVisuals(character, uppercutBlend)

		if uppercutBlend > 0.3 then
			local now = tick()
			if now - lastUppercutEmitAt >= EMIT_INTERVAL then
				lastUppercutEmitAt = now
				for _, state in uppercutPartStates do
					emitBurstOnState(state, EMIT_TICK_COUNT)
				end
			end
		end
	end)
end

return SunspotAbilityVfx
