--!strict
--[[
	Steel Form server: toggle organic steel transformation feet-to-head.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AbilityCooldownHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityCooldownHelper"))
local SteelFormConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SteelFormConstants"))

local ABILITY_ID = SteelFormConstants.ABILITY_ID
local COOLDOWN_SEC = SteelFormConstants.COOLDOWN_SEC

type PartSnapshot = {
	color: Color3,
	material: Enum.Material,
	reflectance: number,
}

type TransformState = {
	active: boolean,
	token: number,
}

type BodySnapshot = {
	maxHealth: number,
	health: number,
}

local SteelFormService = {}

local activeByPlayer: { [Player]: TransformState } = {}
local snapshotsByCharacter: { [Model]: { [BasePart]: PartSnapshot } } = {}
local bodySnapshots: { [Model]: BodySnapshot } = {}

local function isColossus(plr: Player): boolean
	return plr:GetAttribute("SelectedCharacter") == "Colossus"
end

local function getTransformParts(character: Model): { BasePart }
	local parts: { BasePart } = {}
	for _, desc in character:GetDescendants() do
		if desc:IsA("BasePart") and desc.Name ~= "HumanoidRootPart" then
			if desc:FindFirstAncestorOfClass("Accessory") then
				continue
			end
			table.insert(parts, desc)
		end
	end
	table.sort(parts, function(a: BasePart, b: BasePart)
		return a.Position.Y < b.Position.Y
	end)
	return parts
end

local function ensureSnapshots(character: Model, parts: { BasePart })
	local snapshots = snapshotsByCharacter[character]
	if snapshots then
		return snapshots
	end
	snapshots = {}
	for _, part in parts do
		snapshots[part] = {
			color = part.Color,
			material = part.Material,
			reflectance = part.Reflectance,
		}
	end
	snapshotsByCharacter[character] = snapshots
	return snapshots
end

local function applySteel(part: BasePart)
	part.Material = SteelFormConstants.STEEL_MATERIAL
	part.Color = SteelFormConstants.STEEL_COLOR
	part.Reflectance = SteelFormConstants.STEEL_REFLECTANCE
end

local function restorePart(part: BasePart, snapshot: PartSnapshot)
	part.Color = snapshot.color
	part.Material = snapshot.material
	part.Reflectance = snapshot.reflectance
end

local function runWave(
	character: Model,
	parts: { BasePart },
	snapshots: { [BasePart]: PartSnapshot },
	toSteel: boolean,
	token: number,
	plr: Player
)
	if #parts == 0 then
		return
	end

	local minY = parts[1].Position.Y
	local maxY = parts[#parts].Position.Y
	local height = math.max(maxY - minY, 0.01)
	local duration = SteelFormConstants.TRANSFORM_DURATION
	local start = tick()

	character:SetAttribute("IsSteelFormActive", toSteel)

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		if toSteel then
			if not bodySnapshots[character] then
				bodySnapshots[character] = {
					maxHealth = humanoid.MaxHealth,
					health = humanoid.Health,
				}
			end
			humanoid.MaxHealth = SteelFormConstants.STEEL_MAX_HEALTH
			humanoid.Health = SteelFormConstants.STEEL_MAX_HEALTH
		else
			local bodySnap = bodySnapshots[character]
			if bodySnap then
				humanoid.MaxHealth = bodySnap.maxHealth
				humanoid.Health = math.min(bodySnap.health, bodySnap.maxHealth)
				bodySnapshots[character] = nil
			end
		end
	end

	while tick() - start < duration do
		local state = activeByPlayer[plr]
		if not state or state.token ~= token or not character.Parent then
			return
		end

		local alpha = math.clamp((tick() - start) / duration, 0, 1)
		local waveY = if toSteel then minY + height * alpha else maxY - height * alpha

		for _, part in parts do
			if not part.Parent then
				continue
			end
			local snapshot = snapshots[part]
			if not snapshot then
				continue
			end
			local shouldSteel = if toSteel then part.Position.Y <= waveY else part.Position.Y >= waveY
			if shouldSteel then
				if toSteel then
					applySteel(part)
				else
					restorePart(part, snapshot)
				end
			end
		end

		RunService.Heartbeat:Wait()
	end

	for _, part in parts do
		if not part.Parent then
			continue
		end
		local snapshot = snapshots[part]
		if not snapshot then
			continue
		end
		if toSteel then
			applySteel(part)
		else
			restorePart(part, snapshot)
		end
	end
end

local function setSteelForm(plr: Player, enabled: boolean)
	local char = plr.Character
	if not char then
		return
	end

	local parts = getTransformParts(char)
	local snapshots = ensureSnapshots(char, parts)
	local state = activeByPlayer[plr]
	if not state then
		state = { active = false, token = 0 }
		activeByPlayer[plr] = state
	end

	state.token += 1
	local token = state.token
	state.active = enabled

	task.spawn(function()
		runWave(char, parts, snapshots, enabled, token, plr)
		local current = activeByPlayer[plr]
		if current and current.token == token then
			if not enabled then
				char:SetAttribute("IsSteelFormActive", nil)
			end
		end
	end)
end

function SteelFormService.setup(steelFormToggle: RemoteEvent)
	steelFormToggle.OnServerEvent:Connect(function(plr: Player, wantEnabled: unknown)
		if not isColossus(plr) then
			return
		end
		if typeof(wantEnabled) ~= "boolean" then
			return
		end

		local char = plr.Character
		if not char or not char.Parent then
			return
		end
		local humanoid = char:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			return
		end
		if char:GetAttribute("Ragdolled") == true then
			return
		end
		if wantEnabled and AbilityCooldownHelper.isOnCooldown(char, ABILITY_ID) then
			return
		end

		local state = activeByPlayer[plr]
		if state and state.active == wantEnabled then
			return
		end

		setSteelForm(plr, wantEnabled)
		if not wantEnabled then
			AbilityCooldownHelper.apply(char, ABILITY_ID, COOLDOWN_SEC)
		end
	end)
end

function SteelFormService.onPlayerRemoving(plr: Player)
	activeByPlayer[plr] = nil
	local char = plr.Character
	if char then
		snapshotsByCharacter[char] = nil
	end
end

function SteelFormService.onCharacterRemoving(character: Model)
	snapshotsByCharacter[character] = nil
	bodySnapshots[character] = nil
end

return SteelFormService
