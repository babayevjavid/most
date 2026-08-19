--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local GameConstants = require(ReplicatedStorage.Shared.GameConstants)
local AbilityCooldownHelper = require(ReplicatedStorage.Shared.AbilityCooldownHelper)

local CombatHelper = {}

local shieldDamageHandler: ((Model, number, Vector3?) -> boolean)? = nil

function CombatHelper.setShieldDamageHandler(handler: (Model, number, Vector3?) -> boolean)
	shieldDamageHandler = handler
end

function CombatHelper.getCharacterFromPart(part: BasePart?): Model?
	if not part then
		return nil
	end
	-- Walk up so nested Models (clothing/props) under a character still resolve
	local current: Instance? = part
	while current do
		if current:IsA("Model") then
			if current:GetAttribute("FearVisual") == true or current.Name == "FearClone" then
				return nil
			end
			local hum = current:FindFirstChildOfClass("Humanoid")
			if hum then
				return current
			end
		end
		current = current.Parent
	end
	return nil
end

function CombatHelper.silenceDeathSounds(model: Model?)
	if not model then
		return
	end
	local function mute(sound: Sound)
		sound.Volume = 0
		sound.Playing = false
		pcall(function()
			sound:Stop()
		end)
		pcall(function()
			sound.SoundId = ""
		end)
	end
	for _, desc in model:GetDescendants() do
		if desc:IsA("Sound") then
			local name = string.lower(desc.Name)
			local id = string.lower(desc.SoundId)
			if
				name == "died"
				or name == "death"
				or name == "oof"
				or string.find(name, "died", 1, true)
				or string.find(id, "uuhhh", 1, true)
				or string.find(id, "oof", 1, true)
			then
				mute(desc)
			end
		end
	end
end

--[[ Keep death OOF muted even if Roblox adds the Died sound later. ]]
function CombatHelper.bindSilenceDeathSounds(model: Model?)
	if not model then
		return
	end
	CombatHelper.silenceDeathSounds(model)
	if model:GetAttribute("DeathSoundSilenced") == true then
		return
	end
	model:SetAttribute("DeathSoundSilenced", true)
	model.DescendantAdded:Connect(function(desc)
		if not desc:IsA("Sound") then
			return
		end
		local name = string.lower(desc.Name)
		local id = string.lower(desc.SoundId)
		if
			name == "died"
			or name == "death"
			or name == "oof"
			or string.find(name, "died", 1, true)
			or string.find(id, "uuhhh", 1, true)
			or string.find(id, "oof", 1, true)
		then
			desc.Volume = 0
			desc.Playing = false
			pcall(function()
				desc:Stop()
			end)
			pcall(function()
				desc.SoundId = ""
			end)
		end
	end)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Died:Connect(function()
			CombatHelper.silenceDeathSounds(model)
		end)
	end
end

function CombatHelper.getHumanoid(model: Model?): Humanoid?
	if not model then
		return nil
	end
	return model:FindFirstChildOfClass("Humanoid")
end

function CombatHelper.isCombatEligible(model: Model): boolean
	if model:GetAttribute(GameConstants.MG_ASTRAL_ATTRIBUTE) == true then
		return false
	end
	if model:GetAttribute(GameConstants.PROB_HEX_OBJECT_ATTRIBUTE) == true then
		return false
	end
	local protectedUntil = model:GetAttribute(GameConstants.PROTECTED_UNTIL_ATTRIBUTE)
	if type(protectedUntil) == "number" and protectedUntil > AbilityCooldownHelper.getNow() then
		return false
	end
	local plr = Players:GetPlayerFromCharacter(model)
	if plr then
		local hero = model:GetAttribute(GameConstants.HERO_ATTRIBUTE)
		if type(hero) ~= "string" or hero == "" then
			return false
		end
	end
	return true
end

function CombatHelper.isShielded(character: Model): boolean
	return character:GetAttribute(GameConstants.SHIELD_ACTIVE_ATTRIBUTE) == true
end

function CombatHelper.arePowersDisabled(character: Model): boolean
	if character:GetAttribute(GameConstants.RAGDOLLED_ATTRIBUTE) == true then
		return true
	end
	if character:GetAttribute(GameConstants.TORTURE_LOCKED_ATTRIBUTE) == true then
		return true
	end
	if character:GetAttribute(GameConstants.MG_TK_CONTROLLED_ATTRIBUTE) == true then
		return true
	end
	if character:GetAttribute(GameConstants.MG_SLAM_HELD_ATTRIBUTE) == true then
		return true
	end
	if character:GetAttribute(GameConstants.MG_OVERLOAD_ATTRIBUTE) == true then
		return true
	end
	if character:GetAttribute(GameConstants.MG_WAKING_ATTRIBUTE) == true then
		return true
	end
	if character:GetAttribute(GameConstants.GETTING_UP_ATTRIBUTE) == true then
		return true
	end
	if character:GetAttribute(GameConstants.SW_CONTROL_LOCK_ATTRIBUTE) == true then
		return true
	end
	if character:GetAttribute(GameConstants.PROB_HEX_OBJECT_ATTRIBUTE) == true then
		return true
	end
	local untilTime = character:GetAttribute(GameConstants.POWERS_DISABLED_UNTIL)
	if type(untilTime) ~= "number" then
		return false
	end
	return AbilityCooldownHelper.getNow() < untilTime
end

function CombatHelper.markInCombat(character: Model)
	local untilTime = AbilityCooldownHelper.getNow() + GameConstants.COMBAT_TIMEOUT
	character:SetAttribute(GameConstants.COMBAT_UNTIL_ATTRIBUTE, untilTime)
	character:SetAttribute(GameConstants.IN_COMBAT_ATTRIBUTE, true)
end

function CombatHelper.isInCombat(character: Model): boolean
	local untilTime = character:GetAttribute(GameConstants.COMBAT_UNTIL_ATTRIBUTE)
	if type(untilTime) ~= "number" then
		return false
	end
	return AbilityCooldownHelper.getNow() < untilTime
end

function CombatHelper.refreshCombatFlag(character: Model)
	if CombatHelper.isInCombat(character) then
		if character:GetAttribute(GameConstants.IN_COMBAT_ATTRIBUTE) ~= true then
			character:SetAttribute(GameConstants.IN_COMBAT_ATTRIBUTE, true)
		end
	elseif character:GetAttribute(GameConstants.IN_COMBAT_ATTRIBUTE) == true then
		character:SetAttribute(GameConstants.IN_COMBAT_ATTRIBUTE, nil)
		character:SetAttribute(GameConstants.COMBAT_UNTIL_ATTRIBUTE, nil)
	end
end

function CombatHelper.getAbsorbChargeMax(_character: Model?): number
	return GameConstants.ABSORB_CHARGE_MAX
end

local function getAbsorbOutgoingMult(character: Model): number
	local charge = character:GetAttribute(GameConstants.ABSORB_CHARGE_ATTRIBUTE)
	if type(charge) ~= "number" then
		return 1
	end
	local t = math.clamp(charge / GameConstants.ABSORB_CHARGE_MAX, 0, 1)
	return 1 + t * (GameConstants.CM_ABSORB_OUTGOING_MULT_MAX - 1)
end

function CombatHelper.getAbsorbOutgoingMult(character: Model): number
	return getAbsorbOutgoingMult(character)
end

--[[ Spend a fraction of max absorb charge (0.1 = 10% of bar). ]]
function CombatHelper.spendAbsorbCharge(character: Model, fractionOfMax: number)
	if character:GetAttribute(GameConstants.HERO_ATTRIBUTE) ~= "captain_marvel" then
		return
	end
	local charge = character:GetAttribute(GameConstants.ABSORB_CHARGE_ATTRIBUTE)
	if type(charge) ~= "number" or charge <= 0 then
		return
	end
	local spend = GameConstants.ABSORB_CHARGE_MAX * math.clamp(fractionOfMax, 0, 1)
	character:SetAttribute(GameConstants.ABSORB_CHARGE_ATTRIBUTE, math.max(0, charge - spend))
end

function CombatHelper.decayAbsorbCharge(character: Model, dt: number)
	if character:GetAttribute(GameConstants.HERO_ATTRIBUTE) ~= "captain_marvel" then
		return
	end
	local charge = character:GetAttribute(GameConstants.ABSORB_CHARGE_ATTRIBUTE)
	if type(charge) ~= "number" or charge <= 0 then
		return
	end
	character:SetAttribute(
		GameConstants.ABSORB_CHARGE_ATTRIBUTE,
		math.max(0, charge - GameConstants.CM_ABSORB_DECAY_PER_SEC * dt)
	)
end

local function applyCaptainMarvelAbsorb(target: Model, absorbed: number)
	if absorbed <= 0 then
		return
	end
	local gainMult = 1
	if target:GetAttribute(GameConstants.BINARY_ACTIVE_ATTRIBUTE) == true then
		gainMult = GameConstants.BINARY_ABSORB_GAIN_MULT
	end
	local energy = target:GetAttribute(GameConstants.ENERGY_ATTRIBUTE)
	local maxEnergy = target:GetAttribute(GameConstants.MAX_ENERGY_ATTRIBUTE)
	if type(energy) == "number" and type(maxEnergy) == "number" then
		target:SetAttribute(
			GameConstants.ENERGY_ATTRIBUTE,
			math.min(maxEnergy, energy + absorbed * GameConstants.CM_ABSORB_TO_ENERGY * gainMult)
		)
	end
	local hum = CombatHelper.getHumanoid(target)
	if hum and hum.Health > 0 then
		hum.Health = math.min(hum.MaxHealth, hum.Health + absorbed * GameConstants.CM_ABSORB_TO_HEALTH * gainMult)
	end
	local charge = target:GetAttribute(GameConstants.ABSORB_CHARGE_ATTRIBUTE)
	if type(charge) ~= "number" then
		charge = 0
	end
	-- Binary: same hit fills the bar twice as fast (1% → 2%)
	target:SetAttribute(
		GameConstants.ABSORB_CHARGE_ATTRIBUTE,
		math.min(
			GameConstants.ABSORB_CHARGE_MAX,
			charge + absorbed * GameConstants.CM_ABSORB_CHARGE_PER_DAMAGE * gainMult
		)
	)
end

--[[ source: "projectile" | "beam" | nil — CM passive absorb only applies to projectile/beam. ]]
function CombatHelper.dealDamage(
	attacker: Model,
	target: Model,
	amount: number,
	hitFrom: Vector3?,
	source: string?
): boolean
	local humanoid = CombatHelper.getHumanoid(target)
	if not humanoid or humanoid.Health <= 0 then
		return false
	end
	if target == attacker then
		return false
	end
	if not CombatHelper.isCombatEligible(target) then
		return false
	end
	-- Invulnerable while locked in a beam clash
	if target:GetAttribute(GameConstants.BEAM_CLASH_ATTRIBUTE) == true then
		return false
	end
	local protectedUntil = target:GetAttribute(GameConstants.PROTECTED_UNTIL_ATTRIBUTE)
	if type(protectedUntil) == "number" and protectedUntil > AbilityCooldownHelper.getNow() then
		return false
	end
	if target:GetAttribute(GameConstants.MG_ASTRAL_ATTRIBUTE) == true then
		return false
	end

	local finalAmount = amount
	if attacker:GetAttribute(GameConstants.HERO_ATTRIBUTE) == "captain_marvel" then
		finalAmount *= getAbsorbOutgoingMult(attacker)
		if attacker:GetAttribute(GameConstants.BINARY_ACTIVE_ATTRIBUTE) == true then
			finalAmount *= GameConstants.BINARY_DAMAGE_MULT
		end
	end

	local shopBuff = attacker:GetAttribute(GameConstants.SHOP_DAMAGE_BUFF_ATTRIBUTE)
	if type(shopBuff) == "number" and shopBuff > 1 then
		finalAmount *= shopBuff
	end

	if CombatHelper.isShielded(target) then
		if shieldDamageHandler then
			local blocked = shieldDamageHandler(target, finalAmount, hitFrom)
			CombatHelper.markInCombat(target)
			return blocked
		end
		CombatHelper.markInCombat(target)
		return false
	end

	if
		target:GetAttribute(GameConstants.HERO_ATTRIBUTE) == "captain_marvel"
		and (source == "projectile" or source == "beam")
	then
		local absorbed = finalAmount * GameConstants.CM_ABSORB_DAMAGE_FRACTION
		finalAmount = math.max(0, finalAmount - absorbed)
		applyCaptainMarvelAbsorb(target, absorbed)
	end

	humanoid:TakeDamage(finalAmount)
	CombatHelper.markInCombat(target)
	local attackerPlayer = Players:GetPlayerFromCharacter(attacker)
	if attackerPlayer and attacker ~= target then
		target:SetAttribute(GameConstants.LAST_DAMAGER_USER_ID_ATTRIBUTE, attackerPlayer.UserId)
	end
	return true
end

function CombatHelper.heal(target: Model, amount: number): boolean
	local humanoid = CombatHelper.getHumanoid(target)
	if not humanoid or humanoid.Health <= 0 or amount <= 0 then
		return false
	end
	humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + amount)
	return true
end

function CombatHelper.overlapCharacters(origin: Vector3, radius: number, exclude: Model?): { Model }
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if exclude then { exclude } else {}
	local parts = workspace:GetPartBoundsInRadius(origin, radius, params)
	local seen: { [Model]: boolean } = {}
	local results: { Model } = {}
	for _, part in parts do
		local character = CombatHelper.getCharacterFromPart(part)
		if character and not seen[character] then
			seen[character] = true
			local humanoid = CombatHelper.getHumanoid(character)
			if humanoid and humanoid.Health > 0 and CombatHelper.isCombatEligible(character) then
				table.insert(results, character)
			end
		end
	end
	return results
end

function CombatHelper.raycastCharacter(
	origin: Vector3,
	direction: Vector3,
	range: number,
	exclude: Model?
): Model?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if exclude then { exclude } else {}
	local result = workspace:Raycast(origin, direction.Unit * range, params)
	if not result then
		return nil
	end
	local model = CombatHelper.getCharacterFromPart(result.Instance)
	-- Accept any living humanoid (players and NPCs)
	if model then
		local hum = CombatHelper.getHumanoid(model)
		if hum and hum.Health > 0 and CombatHelper.isCombatEligible(model) then
			return model
		end
	end
	return nil
end

function CombatHelper.raycastPoint(
	origin: Vector3,
	direction: Vector3,
	range: number,
	exclude: Model?
): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if exclude then { exclude } else {}
	local result = workspace:Raycast(origin, direction.Unit * range, params)
	if result then
		return result.Position
	end
	return origin + direction.Unit * range
end

return CombatHelper
