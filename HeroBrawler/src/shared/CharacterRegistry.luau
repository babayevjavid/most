--!strict

export type AbilityDef = {
	id: string,
	name: string,
	description: string,
	key: string,
	cooldown: number,
	energyCost: number,
	form: "Monet" | "Penance" | "Both",
}

export type CharacterEntry = {
	id: string,
	displayName: string,
	tagline: string,
	price: number,
	healthMonet: number,
	healthPenance: number,
	maxEnergy: number,
	abilities: { AbilityDef },
}

local CharacterRegistry = {}

local MONET_ABILITIES: { AbilityDef } = {
	{
		id = "psionic_flight",
		name = "Psionic Flight",
		description = "Toggle flight. WASD follows camera (look up/down to fly vertical). Shift to boost. Only Mind Shatter usable mid-air.",
		key = "Q",
		cooldown = 3,
		energyCost = 8,
		form = "Monet",
	},
	{
		id = "psychic_repulsion",
		name = "Psychic Repulsion",
		description = "Hold F to charge (tight camera). Release to unleash expanding repulsion rings toward cursor.",
		key = "F",
		cooldown = 8,
		energyCost = 18,
		form = "Monet",
	},
	{
		id = "mind_shatter",
		name = "Mind Shatter",
		description = "Psychic fracture beam. Marks, pulls, and disrupts the target. Usable during flight.",
		key = "R",
		cooldown = 12,
		energyCost = 22,
		form = "Monet",
	},
	{
		id = "blood_rush",
		name = "Blood Rush",
		description = "Launch forward as a blazing claw comet toward your cursor.",
		key = "Q",
		cooldown = 6,
		energyCost = 14,
		form = "Penance",
	},
	{
		id = "diamond_curl",
		name = "Diamond Curl",
		description = "Hold F to become a rolling diamond ball. WASD moves like normal walk (no jump). Release to burst.",
		key = "F",
		cooldown = 10,
		energyCost = 16,
		form = "Penance",
	},
	{
		id = "pain_lash",
		name = "Pain Lash",
		description = "Lash a blood-diamond chain toward cursor, impaling and yanking the first enemy hit toward you.",
		key = "R",
		cooldown = 9,
		energyCost = 20,
		form = "Penance",
	},
	{
		id = "astral_dominion",
		name = "Astral Dominion",
		description = "Hold T: carousel enemies in a psychic circle around you, then launch them outward on release. Drains energy while held.",
		key = "T",
		cooldown = 40,
		energyCost = 25,
		form = "Monet",
	},
	{
		id = "crimson_cataclysm",
		name = "Crimson Cataclysm",
		description = "Hold T: vacuum enemies into a crimson vortex, shredding them. Release for a devastating diamond detonation.",
		key = "T",
		cooldown = 40,
		energyCost = 25,
		form = "Penance",
	},
}

local ROSTER: { CharacterEntry } = {
	{
		id = "monet_st_croix",
		displayName = "Monet St. Croix",
		tagline = "Dual form psychic bruiser",
		price = 0,
		healthMonet = 280,
		healthPenance = 350,
		maxEnergy = 100,
		abilities = MONET_ABILITIES,
	},
}

function CharacterRegistry.getRoster(): { CharacterEntry }
	return ROSTER
end

function CharacterRegistry.getById(id: string): CharacterEntry?
	for _, entry in ROSTER do
		if entry.id == id then
			return entry
		end
	end
	return nil
end

function CharacterRegistry.getAbilitiesForForm(characterId: string, form: "Monet" | "Penance"): { AbilityDef }
	local entry = CharacterRegistry.getById(characterId)
	if not entry then
		return {}
	end
	local result: { AbilityDef } = {}
	for _, ability in entry.abilities do
		if ability.form == form or ability.form == "Both" then
			table.insert(result, ability)
		end
	end
	return result
end

function CharacterRegistry.getAbilityByKey(characterId: string, form: "Monet" | "Penance", key: string): AbilityDef?
	for _, ability in CharacterRegistry.getAbilitiesForForm(characterId, form) do
		if ability.key == key then
			return ability
		end
	end
	return nil
end

function CharacterRegistry.getAbilityById(characterId: string, abilityId: string): AbilityDef?
	local entry = CharacterRegistry.getById(characterId)
	if not entry then
		return nil
	end
	for _, ability in entry.abilities do
		if ability.id == abilityId then
			return ability
		end
	end
	return nil
end

return CharacterRegistry
