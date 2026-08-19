--!strict
--[[ Psylocke abilities (placeholder kit). ]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AbilityCombatHelper = require(Shared:WaitForChild("AbilityCombatHelper"))
local AbilityCooldownHelper = require(Shared:WaitForChild("AbilityCooldownHelper"))
local AbilityVfxHelper = require(Shared:WaitForChild("AbilityVfxHelper"))
local PsylockeConstants = require(Shared:WaitForChild("PsylockeConstants"))
local ResourceService = require(script.Parent:WaitForChild("ResourceService"))
local ProgressionService = require(script.Parent:WaitForChild("ProgressionService"))

local CHAR_ID = "Psylocke"
local PSI = PsylockeConstants.PSI_PURPLE
local PSI_BLADE = PsylockeConstants.PsiBlade
local BUTTERFLY = PsylockeConstants.ButterflyStep
local SLASH = PsylockeConstants.PsychicSlash
local FIELD = PsylockeConstants.FocusField
local ASTRAL = PsylockeConstants.AstralAssault

local PsylockeAbilitiesService = {}

local function isPsylocke(plr: Player): boolean
	return plr:GetAttribute("SelectedCharacter") == CHAR_ID
end

local function getRoot(char: Model): BasePart?
	return char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function getLookFlat(root: BasePart): Vector3
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.01 then
		return Vector3.new(0, 0, -1)
	end
	return flat.Unit
end

local function trySpend(char: Model, abilityId: string): boolean
	return ResourceService.trySpendForAbility(char, CHAR_ID, abilityId)
end

local function castPsiBlade(plr: Player, char: Model)
	local root = getRoot(char)
	if not root then
		return
	end
	if not trySpend(char, PSI_BLADE.ABILITY_ID) then
		return
	end

	local aim = getLookFlat(root)
	AbilityVfxHelper.spawnExpandingSphere(root.Position + aim * 4, PSI, 1.2, 5, 0.18)
	AbilityCombatHelper.hitInForwardBox(
		root.Position,
		aim,
		PSI_BLADE.RANGE,
		8,
		7,
		char,
		{ damage = PSI_BLADE.DAMAGE, pushSpeed = 28, pushUp = 4, excludePlayer = plr }
	)
	AbilityCooldownHelper.apply(char, PSI_BLADE.ABILITY_ID, PSI_BLADE.COOLDOWN_SEC)
	ProgressionService.grantAbilityXp(plr, PSI_BLADE.ABILITY_ID, "cast")
end

local function castButterflyStep(plr: Player, char: Model, dir: Vector3)
	local root = getRoot(char)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not root or not hum then
		return
	end
	if not trySpend(char, BUTTERFLY.ABILITY_ID) then
		return
	end

	local flat = Vector3.new(dir.X, 0, dir.Z)
	if flat.Magnitude < 0.01 then
		flat = getLookFlat(root)
	else
		flat = flat.Unit
	end

	local endPos = root.Position + flat * BUTTERFLY.RANGE
	AbilityVfxHelper.spawnExpandingSphere(root.Position, PsylockeConstants.PSI_PINK, 0.8, 4, 0.16)
	root.CFrame = CFrame.new(endPos, endPos + flat)
	AbilityVfxHelper.spawnExpandingSphere(endPos, PsylockeConstants.PSI_PINK, 0.8, 4, 0.16)

	AbilityCooldownHelper.apply(char, BUTTERFLY.ABILITY_ID, BUTTERFLY.COOLDOWN_SEC)
	ProgressionService.grantAbilityXp(plr, BUTTERFLY.ABILITY_ID, "cast")
end

local function castPsychicSlash(plr: Player, char: Model)
	local root = getRoot(char)
	if not root then
		return
	end
	if not trySpend(char, SLASH.ABILITY_ID) then
		return
	end

	local aim = getLookFlat(root)
	AbilityVfxHelper.spawnExpandingSphere(root.Position + aim * 6, PSI, 1.6, 7, 0.2)
	AbilityCombatHelper.hitInForwardBox(
		root.Position,
		aim,
		SLASH.RANGE,
		SLASH.WIDTH,
		SLASH.HEIGHT,
		char,
		{ damage = SLASH.DAMAGE, pushSpeed = 34, pushUp = 6, excludePlayer = plr }
	)
	AbilityCooldownHelper.apply(char, SLASH.ABILITY_ID, SLASH.COOLDOWN_SEC)
	ProgressionService.grantAbilityXp(plr, SLASH.ABILITY_ID, "cast")
end

local function castFocusField(plr: Player, char: Model)
	local root = getRoot(char)
	if not root then
		return
	end
	if not trySpend(char, FIELD.ABILITY_ID) then
		return
	end

	AbilityVfxHelper.spawnExpandingSphere(root.Position, PSI, 2.2, FIELD.RADIUS, 0.35)
	AbilityCombatHelper.hitInRadius(
		root.Position,
		FIELD.RADIUS,
		char,
		{ damage = 8, pushSpeed = 12, pushUp = 2, excludePlayer = plr }
	)
	AbilityCooldownHelper.apply(char, FIELD.ABILITY_ID, FIELD.COOLDOWN_SEC)
	ProgressionService.grantAbilityXp(plr, FIELD.ABILITY_ID, "cast")
end

local function castAstralAssault(plr: Player, char: Model)
	local root = getRoot(char)
	if not root then
		return
	end
	if not trySpend(char, ASTRAL.ABILITY_ID) then
		return
	end

	local aim = getLookFlat(root)
	for i = 1, ASTRAL.HITS do
		local offset = aim * (4 + i * 3)
		AbilityVfxHelper.spawnExpandingSphere(root.Position + offset, PsylockeConstants.PSI_PINK, 1, 4.5, 0.12)
		AbilityCombatHelper.hitInRadius(
			root.Position + offset,
			5,
			char,
			{ damage = ASTRAL.DAMAGE, pushSpeed = 24, pushUp = 5, excludePlayer = plr }
		)
	end

	AbilityCooldownHelper.apply(char, ASTRAL.ABILITY_ID, ASTRAL.COOLDOWN_SEC)
	ProgressionService.grantAbilityXp(plr, ASTRAL.ABILITY_ID, "cast")
end

function PsylockeAbilitiesService.initCharacter(_char: Model) end

function PsylockeAbilitiesService.setup(
	psiBladeRemote: RemoteEvent,
	butterflyRemote: RemoteEvent,
	slashRemote: RemoteEvent,
	focusRemote: RemoteEvent,
	astralRemote: RemoteEvent
)
	psiBladeRemote.OnServerEvent:Connect(function(plr: Player)
		if not isPsylocke(plr) then
			return
		end
		local char = plr.Character
		if not char or AbilityCooldownHelper.isOnCooldown(char, PSI_BLADE.ABILITY_ID) then
			return
		end
		if not ResourceService.hasMinimum(char, CHAR_ID, PSI_BLADE.ABILITY_ID) then
			return
		end
		castPsiBlade(plr, char)
	end)

	butterflyRemote.OnServerEvent:Connect(function(plr: Player, dirX: unknown, dirY: unknown, dirZ: unknown)
		if not isPsylocke(plr) then
			return
		end
		local char = plr.Character
		if not char or AbilityCooldownHelper.isOnCooldown(char, BUTTERFLY.ABILITY_ID) then
			return
		end
		if not ResourceService.hasMinimum(char, CHAR_ID, BUTTERFLY.ABILITY_ID) then
			return
		end
		local dir = if typeof(dirX) == "number" and typeof(dirY) == "number" and typeof(dirZ) == "number"
			then Vector3.new(dirX, dirY, dirZ)
			else Vector3.zero
		castButterflyStep(plr, char, dir)
	end)

	slashRemote.OnServerEvent:Connect(function(plr: Player)
		if not isPsylocke(plr) then
			return
		end
		local char = plr.Character
		if not char or AbilityCooldownHelper.isOnCooldown(char, SLASH.ABILITY_ID) then
			return
		end
		if not ResourceService.hasMinimum(char, CHAR_ID, SLASH.ABILITY_ID) then
			return
		end
		castPsychicSlash(plr, char)
	end)

	focusRemote.OnServerEvent:Connect(function(plr: Player)
		if not isPsylocke(plr) then
			return
		end
		local char = plr.Character
		if not char or AbilityCooldownHelper.isOnCooldown(char, FIELD.ABILITY_ID) then
			return
		end
		if not ResourceService.hasMinimum(char, CHAR_ID, FIELD.ABILITY_ID) then
			return
		end
		castFocusField(plr, char)
	end)

	astralRemote.OnServerEvent:Connect(function(plr: Player)
		if not isPsylocke(plr) then
			return
		end
		local char = plr.Character
		if not char or AbilityCooldownHelper.isOnCooldown(char, ASTRAL.ABILITY_ID) then
			return
		end
		if not ResourceService.hasMinimum(char, CHAR_ID, ASTRAL.ABILITY_ID) then
			return
		end
		castAstralAssault(plr, char)
	end)
end

return PsylockeAbilitiesService
