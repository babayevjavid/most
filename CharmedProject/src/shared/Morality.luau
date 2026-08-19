-- Server-driven good/evil alignment for witches (not Belthazor). Uses Player.GoodEvil (-1 evil .. +1 good).

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local CharacterConfig = require(script.Parent.CharacterConfig)
local CharacterIdentity = require(script.Parent.CharacterIdentity)
local GameHealth = require(script.Parent.GameHealth)

local BELTHAZOR_TAG = CharacterConfig.BelthazorTagName or "Belthazor"
local WITCH_ROLE: { [string]: boolean } = {}
for _, n in CharacterConfig.Choices do
	if n ~= "Belthazor" then
		WITCH_ROLE[n] = true
	end
end

local CFG = CharacterConfig :: any
local PER_HP = type(CFG.MoralityPerDamagePoint) == "number" and CFG.MoralityPerDamagePoint or 0.004
local PER_FREEZE = type(CFG.MoralityPerFreezeVictim) == "number" and CFG.MoralityPerFreezeVictim or 0.012
local GOOD_IMMUNE = type(CFG.GoodNonWitchFreezeImmuneAbove) == "number" and CFG.GoodNonWitchFreezeImmuneAbove or 0.38
local WITCH_SPAWN_GOOD = type(CFG.WitchSpawnGoodEvil) == "number" and CFG.WitchSpawnGoodEvil or 0.72
local DEMON_SPAWN_EVIL = type(CFG.DemonSpawnGoodEvil) == "number" and CFG.DemonSpawnGoodEvil or -0.82

local started = false

local Morality = {}

local function clampAlign(x: number): number
	return math.clamp(x, -1, 1)
end

function Morality.isWitchRole(name: any): boolean
	return type(name) == "string" and WITCH_ROLE[name] == true
end

function Morality.getVictimAlignment(model: Model): number
	if CollectionService:HasTag(model, BELTHAZOR_TAG) then
		return -1
	end
	local plr = Players:GetPlayerFromCharacter(model)
	local role = CharacterIdentity.getChosenCharacterRole(model)
	if role == "Belthazor" then
		if plr then
			local g = plr:GetAttribute("GoodEvil")
			if type(g) == "number" then
				return clampAlign(g)
			end
		end
		local g = model:GetAttribute("GoodEvil")
		if type(g) == "number" then
			return clampAlign(g)
		end
		return DEMON_SPAWN_EVIL
	end
	if role and Morality.isWitchRole(role) then
		if plr then
			local g = plr:GetAttribute("GoodEvil")
			if type(g) == "number" then
				return clampAlign(g)
			end
		end
		local g = model:GetAttribute("GoodEvil")
		if type(g) == "number" then
			return clampAlign(g)
		end
		-- NPC witch with no GoodEvil yet: treat as spawn-good for freeze/morality
		return WITCH_SPAWN_GOOD
	end
	local g = model:GetAttribute("GoodEvil")
	if type(g) == "number" then
		return clampAlign(g)
	end
	return 0
end

-- Freeze: demons always. Witches with GoodEvil > 0 (good-aligned) cannot be frozen. Evil/neutral witches and NPCs use threshold.
function Morality.shouldMolecularFreezeAffect(_caster: Player, victimModel: Model): boolean
	if CollectionService:HasTag(victimModel, BELTHAZOR_TAG) then
		return true
	end
	local role = CharacterIdentity.getChosenCharacterRole(victimModel)
	if type(role) == "string" and role == "Belthazor" then
		return true
	end
	if Morality.isWitchRole(role) then
		local vp = Players:GetPlayerFromCharacter(victimModel)
		local g = if vp then vp:GetAttribute("GoodEvil") else victimModel:GetAttribute("GoodEvil")
		if type(g) == "number" and g > 0 then
			return false
		end
		return true
	end
	return Morality.getVictimAlignment(victimModel) <= GOOD_IMMUNE
end

function Morality.registerHostileAction(attacker: Player, victimModel: Model, weight: number)
	local aRole = attacker:GetAttribute("ChosenCharacter")
	-- Only Charmed witches shift morality; Belthazor player attacks still count for victim alignment but don't move demon's bar.
	if not Morality.isWitchRole(aRole) then
		return
	end
	local v = Morality.getVictimAlignment(victimModel)
	local cur = attacker:GetAttribute("GoodEvil")
	if type(cur) ~= "number" then
		cur = 0
	end
	local sign = 0
	if v < -0.05 then
		sign = 1
	elseif v > 0.05 then
		sign = -1
	end
	if sign == 0 or weight <= 0 then
		return
	end
	attacker:SetAttribute("GoodEvil", clampAlign(cur + weight * sign))
end

local function onDamage(attacker: Player, hum: Humanoid, amount: number)
	local m = hum.Parent
	if not m or not m:IsA("Model") then
		return
	end
	Morality.registerHostileAction(attacker, m, amount * PER_HP)
end

function Morality.ensurePlayerMorality(player: Player)
	local role = player:GetAttribute("ChosenCharacter")
	if type(role) ~= "string" or role == "" then
		player:SetAttribute("GoodEvil", nil :: any)
		return
	end
	if role == "Belthazor" then
		player:SetAttribute("GoodEvil", DEMON_SPAWN_EVIL)
		return
	end
	if Morality.isWitchRole(role) then
		player:SetAttribute("GoodEvil", WITCH_SPAWN_GOOD)
		return
	end
	player:SetAttribute("GoodEvil", nil :: any)
end

function Morality.onFreezeVictims(caster: Player, victimModels: { Model })
	if not Morality.isWitchRole(caster:GetAttribute("ChosenCharacter")) then
		return
	end
	for _, m in victimModels do
		Morality.registerHostileAction(caster, m, PER_FREEZE)
	end
end

function Morality.start()
	if started then
		return
	end
	started = true
	GameHealth.setDamageAttributionHook(onDamage)
	local function hookPlayer(player: Player)
		player:GetAttributeChangedSignal("ChosenCharacter"):Connect(function()
			Morality.ensurePlayerMorality(player)
		end)
		Morality.ensurePlayerMorality(player)
	end
	Players.PlayerAdded:Connect(hookPlayer)
	for _, plr in Players:GetPlayers() do
		hookPlayer(plr)
	end
end

return Morality
