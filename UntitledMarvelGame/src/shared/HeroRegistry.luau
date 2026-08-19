--!strict

local AbilityDefinitions = require(script.Parent.AbilityDefinitions)

export type HeroDef = {
	Id: string,
	DisplayName: string,
	Basic: string,
	Abilities: { string },
	Movement: string,
	Passive: string,
}

local function hero(
	id: string,
	displayName: string,
	basic: string,
	abilities: { string },
	movement: string,
	passive: string
): HeroDef
	return {
		Id = id,
		DisplayName = displayName,
		Basic = basic,
		Abilities = abilities,
		Movement = movement,
		Passive = passive,
	}
end

local HeroRegistry: { [string]: HeroDef } = {
	Wanda = hero(
		"Wanda",
		"Wanda Maximoff",
		"ChaosBlast",
		{ "ChaosShield", "Telekinesis", "ForcePush", "ChaosBeam", "OverwhelmingForce" },
		"ChaosLevitate",
		"UndoneGrief"
	),
	Thor = hero(
		"Thor",
		"Thor",
		"MjolnirStrike",
		{ "MjolnirThrow", "LightningStrike", "ThunderClap", "StormCall", "GodBlast" },
		"MjolnirFlight",
		"Worthy"
	),
	CaptainMarvel = hero(
		"CaptainMarvel",
		"Captain Marvel",
		"PhotonBlast",
		{ "EnergyAbsorption", "CosmicPunch", "BinaryBurst", "EnergyBarrier", "BinaryForm" },
		"CosmicDash",
		"KreeHybrid"
	),
	Loki = hero(
		"Loki",
		"Loki",
		"ScepterStrike",
		{ "IllusionDaggers", "MirrorImage", "MindScepter", "TricksterSwap", "ArmyOfIllusions" },
		"ShadowStep",
		"Trickster"
	),
}

function HeroRegistry.getHeroIds(): { string }
	return { "Wanda", "Thor", "CaptainMarvel", "Loki" }
end

function HeroRegistry.getAbilityLayout(heroId: string): { basic: AbilityDefinitions.AbilityDef, abilities: { AbilityDefinitions.AbilityDef }, movement: AbilityDefinitions.AbilityDef, passive: AbilityDefinitions.AbilityDef }?
	local heroDef = HeroRegistry[heroId]
	if not heroDef then
		return nil
	end

	local basic = AbilityDefinitions[heroDef.Basic]
	local abilities: { AbilityDefinitions.AbilityDef } = {}
	for _, abilityId in heroDef.Abilities do
		local def = AbilityDefinitions[abilityId]
		if def then
			table.insert(abilities, def)
		end
	end
	local movement = AbilityDefinitions[heroDef.Movement]
	local passive = AbilityDefinitions[heroDef.Passive]
	if not basic or not movement or not passive then
		return nil
	end
	return {
		basic = basic,
		abilities = abilities,
		movement = movement,
		passive = passive,
	}
end

function HeroRegistry.heroOwnsAbility(heroId: string, abilityId: string): boolean
	local heroDef = HeroRegistry[heroId]
	if not heroDef then
		return false
	end
	if heroDef.Basic == abilityId or heroDef.Movement == abilityId or heroDef.Passive == abilityId then
		return true
	end
	for _, id in heroDef.Abilities do
		if id == abilityId then
			return true
		end
	end
	return false
end

return HeroRegistry
