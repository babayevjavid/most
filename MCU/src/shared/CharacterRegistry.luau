--!strict
--[[ Playable roster for Heroes Assemble: Reborn. Abilities filled in as kits are scripted. ]]

export type AbilityDef = {
	id: string,
	name: string,
	description: string,
	key: string,
	cooldown: number,
	energyCost: number,
	hold: boolean?,
	modes: { string }?,
	sideBar: boolean?,
	passive: boolean?,
	icon: string?,
	modeIcons: { [string]: string }?,
	astralOnly: boolean?,
	requiresTarget: boolean?,
}

export type SkinDef = {
	id: string,
	name: string,
	morphName: string,
	blocked: boolean?,
}

export type CharacterEntry = {
	id: string,
	displayName: string,
	alias: string,
	powers: string,
	biography: string,
	tagline: string,
	price: number,
	health: number,
	maxEnergy: number,
	morphName: string,
	skins: { SkinDef },
	abilities: { AbilityDef },
}

local CharacterRegistry = {}

local JEAN_GREY_ABILITIES: { AbilityDef } = {
	{
		id = "psionic_barrier",
		name = "Psionic Barrier",
		description = "Hold: raise a psionic forcefield (100 HP) that absorbs damage.",
		key = "Q",
		cooldown = 10,
		energyCost = 0,
		hold = true,
	},
	{
		id = "psionic_bolt",
		name = "Psionic Bolt",
		description = "Fire a psionic bolt at your cursor.",
		key = "E",
		cooldown = 1.5,
		energyCost = 3,
	},
	{
		id = "psychic_pull",
		name = "Telekinetic Pull",
		description = "Yank a single target toward you with telekinesis.",
		key = "T",
		cooldown = 12,
		energyCost = 5,
		requiresTarget = true,
	},
	{
		id = "telekinesis",
		name = "Telekinesis",
		description = "Hold: lift a target. Click to hurl them up and away.",
		key = "R",
		cooldown = 7,
		energyCost = 1,
		hold = true,
		requiresTarget = true,
	},
	{
		id = "telekinetic_flight",
		name = "Telekinetic Flight",
		description = "Toggle telekinetic flight. WASD follows camera.",
		key = "F",
		cooldown = 2,
		energyCost = 0,
	},
	{
		id = "telekinetic_slam",
		name = "Telekinetic Slam",
		description = "Grab a target, slam them into the ground 3 times, then hurl them toward your cursor.",
		key = "X",
		cooldown = 14,
		energyCost = 6,
		requiresTarget = true,
	},
	{
		id = "telekinetic_debris",
		name = "Telekinetic Debris",
		description = "Hold: rip 5 rocks that follow you. Click to throw each at your cursor (10s).",
		key = "Z",
		cooldown = 5.5,
		energyCost = 3,
		hold = true,
	},
	{
		id = "astral_projection",
		name = "Astral Projection",
		description = "Leave your body as a flying astral copy for 30 seconds. Press H again to return.",
		key = "H",
		cooldown = 20,
		energyCost = 6,
		sideBar = true,
	},
	{
		id = "mind_link",
		name = "Mind Link",
		description = "Open a mind link, then aim and press G to add people (1s add CD, max 5). Close with the chat X (Jean only).",
		key = "G",
		cooldown = 8,
		energyCost = 2,
		sideBar = true,
		requiresTarget = true,
	},
	{
		id = "telepathic_pain",
		name = "Telepathic Pain",
		description = "Hold (astral): pain a nearby mind within 15 studs. Slows your astral form.",
		key = "C",
		cooldown = 8,
		energyCost = 4,
		sideBar = true,
		astralOnly = true,
		hold = true,
		requiresTarget = true,
	},
	{
		id = "telepathic_outburst",
		name = "Telepathic Outburst",
		description = "Astral: freeze, then burst telepathic force in 25 studs and leave astral.",
		key = "B",
		cooldown = 10,
		energyCost = 5,
		sideBar = true,
		astralOnly = true,
	},
}

local SCARLET_WITCH_ABILITIES: { AbilityDef } = {
	{
		id = "telekinesis",
		name = "Telekinesis",
		description = "Hold: lift a target. Scroll distance. Click throws.",
		key = "R",
		cooldown = 7,
		energyCost = 1,
		hold = true,
		requiresTarget = true,
	},
	{
		id = "hex_flight",
		name = "Hex Flight",
		description = "Toggle hex flight. WASD follows camera.",
		key = "F",
		cooldown = 2,
		energyCost = 0,
	},
	{
		id = "hex_beam",
		name = "Hex Beam",
		description = "Lock on: hex beam that shoves the target back for up to 2s or 50 studs.",
		key = "T",
		cooldown = 6,
		energyCost = 1,
		requiresTarget = true,
	},
	{
		id = "hex_bolt",
		name = "Hex Bolt",
		description = "Hurl a hex bolt toward your cursor.",
		key = "E",
		cooldown = 1.5,
		energyCost = 3,
	},
	{
		id = "hex_shield",
		name = "Hex Shield",
		description = "Hold: raise a hex shield (150 HP).",
		key = "Q",
		cooldown = 10,
		energyCost = 3,
		hold = true,
	},
	{
		id = "probability_hex",
		name = "Probability Hex",
		description = "Fire a short-range hex beam that either turns the target into a random object (15s cd) or strips their powers for 10s (25s cd).",
		key = "G",
		cooldown = 15,
		energyCost = 4,
		requiresTarget = true,
	},
	{
		id = "hex_displacement",
		name = "Hex Displacement",
		description = "Press V to aim, click to teleport. Press V again to cancel.",
		key = "V",
		cooldown = 8,
		energyCost = 3,
	},
	{
		id = "rune_entrapment",
		name = "Rune Displacement",
		description = "Drop a rune field. Enemies inside get a random fire, lightning, or water hex for 12s.",
		key = "X",
		cooldown = 14,
		energyCost = 5,
	},
}

local INVISIBLE_WOMAN_ABILITIES: { AbilityDef } = {
	{
		id = "iw_forcefield",
		name = "Forcefield",
		description = "Hold: raise a forcefield (300 HP) that absorbs damage.",
		key = "Q",
		cooldown = 10,
		energyCost = 0,
		hold = true,
	},
	{
		id = "disc_throw",
		name = "Disc Throw",
		description = "Throw a forcefield disc that steers toward your cursor.",
		key = "E",
		cooldown = 0.5,
		energyCost = 3,
	},
	{
		id = "forcefield_push",
		name = "Forcefield Push",
		description = "Send a forcefield construct toward your cursor. Hits people, breaks on the ground.",
		key = "R",
		cooldown = 10,
		energyCost = 5,
	},
	{
		id = "invisibility",
		name = "Invisibility",
		description = "Fade out of sight. Lasts until you press T again or energy runs out.",
		key = "T",
		cooldown = 12,
		energyCost = 1,
	},
	{
		id = "forcefield_flight",
		name = "Forcefield Flight",
		description = "Toggle forcefield flight. WASD follows camera.",
		key = "F",
		cooldown = 2,
		energyCost = 0,
	},
	{
		id = "forcefield_area",
		name = "Forcefield Area",
		description = "Place a forcefield zone. Recast to cancel. You cannot move while it is up.",
		key = "X",
		cooldown = 25,
		energyCost = 3,
	},
	{
		id = "forcefield_crush",
		name = "Forcefield Crush",
		description = "Pin a target in place and crush them for 2.5 seconds.",
		key = "Z",
		cooldown = 12,
		energyCost = 3,
		requiresTarget = true,
	},
	{
		id = "crush_execute",
		name = "Crush Finisher",
		description = "Modern look: finish a crushed target at low health.",
		key = "",
		cooldown = 90,
		energyCost = 0,
		passive = true,
	},
	{
		id = "body_projection",
		name = "Body Projection",
		description = "Throw a forcefield projection that detonates in a 10-stud ragdoll burst.",
		key = "G",
		cooldown = 10,
		energyCost = 5,
		sideBar = true,
	},
	{
		id = "forcefield_smash",
		name = "Forcefield Wall Smash",
		description = "Slam two walls into the middle at your cursor, crushing anyone between them.",
		key = "H",
		cooldown = 14,
		energyCost = 6,
		sideBar = true,
	},
	{
		id = "forcefield_choke",
		name = "Choke",
		description = "Hold: choke everyone inside your area forcefield.",
		key = "B",
		cooldown = 3,
		energyCost = 0,
		sideBar = true,
		hold = true,
	},
	{
		id = "forcefield_protect",
		name = "Protect",
		description = "Hold: raise a 25 HP personal forcefield while your area shield is up.",
		key = "C",
		cooldown = 1,
		energyCost = 0,
		sideBar = true,
		hold = true,
	},
}

local function skins(morphName: string, extra: { SkinDef }?, baseName: string?): { SkinDef }
	local list: { SkinDef } = {
		{ id = "base", name = baseName or "Base", morphName = morphName },
	}
	if extra then
		for _, skin in extra do
			table.insert(list, skin)
		end
	end
	return list
end

local ROSTER: { CharacterEntry } = {
	{
		id = "scarlet_witch_classic",
		displayName = "Scarlet Witch",
		alias = "Wanda Maximoff",
		powers = "Hex magic, probability manipulation",
		biography = "A Sokovian witch whose hexes twist luck itself. Still learning what every spell costs.",
		tagline = "The hex always comes due",
		price = 0,
		health = 260,
		maxEnergy = 100,
		morphName = "ScarletWitchClassic",
		skins = skins("ScarletWitchClassic"),
		abilities = SCARLET_WITCH_ABILITIES,
	},
	{
		id = "jean_grey",
		displayName = "Jean Grey",
		alias = "Marvel Girl",
		powers = "Telepathy, telekinesis, Phoenix Force",
		biography = "Heart of the X-Men. She can lift a jet or quiet a panicked mind — and the Phoenix waits under every choice.",
		tagline = "The mind that holds the team",
		price = 0,
		health = 270,
		maxEnergy = 100,
		morphName = "JeanGrey",
		skins = skins("JeanGrey", {
			{ id = "marvel_girl", name = "Marvel Girl", morphName = "JeanGreyMarvelGirl" },
			{ id = "phoenix", name = "Phoenix Force", morphName = "JeanGreyPhoenix", blocked = true },
		}, "X-Men '97"),
		abilities = JEAN_GREY_ABILITIES,
	},
	{
		id = "spider_man",
		displayName = "Spider-Man",
		alias = "Peter Parker",
		powers = "Wall-crawling, spider-sense, super strength",
		biography = "Your friendly neighborhood hero. Great power, worse rent, and a quip for every punch.",
		tagline = "With great power…",
		price = 0,
		health = 240,
		maxEnergy = 100,
		morphName = "SpiderMan",
		skins = skins("SpiderMan"),
		abilities = {},
	},
	{
		id = "crystal",
		displayName = "Crystal",
		alias = "Crystalia Amaquelin",
		powers = "Elemental control — earth, air, fire, water",
		biography = "Inhuman princess who commands the elements. Royal, restless, and rarely subtle.",
		tagline = "Four elements, one will",
		price = 0,
		health = 280,
		maxEnergy = 100,
		morphName = "Crystal",
		skins = skins("Crystal"),
		abilities = {},
	},
	{
		id = "storm",
		displayName = "Storm",
		alias = "Ororo Munroe",
		powers = "Weather manipulation, flight, lightning",
		biography = "Goddess to some, X-Man to others. She walks in with the sky already listening.",
		tagline = "The sky answers her",
		price = 0,
		health = 290,
		maxEnergy = 100,
		morphName = "Storm",
		skins = skins("Storm"),
		abilities = {},
	},
	{
		id = "rogue",
		displayName = "Rogue",
		alias = "Anna Marie",
		powers = "Power absorption, stolen flight and strength",
		biography = "A Southern brawler who can't risk a touch. Every gift she borrows leaves a mark.",
		tagline = "Don't touch her — she might keep it",
		price = 0,
		health = 300,
		maxEnergy = 100,
		morphName = "Rogue",
		skins = skins("Rogue"),
		abilities = {},
	},
	{
		id = "cyclops",
		displayName = "Cyclops",
		alias = "Scott Summers",
		powers = "Optic blasts, tactical command",
		biography = "Field leader of the X-Men. The visor stays on; the plan does not.",
		tagline = "Line of fire, line of command",
		price = 0,
		health = 270,
		maxEnergy = 100,
		morphName = "Cyclops",
		skins = skins("Cyclops"),
		abilities = {},
	},
	{
		id = "blue_marvel",
		displayName = "Blue Marvel",
		alias = "Adam Brashear",
		powers = "Anti-matter energy, flight, immense strength",
		biography = "A forgotten legend who could split worlds. He fights so the next generation doesn't have to.",
		tagline = "The man they tried to bury",
		price = 0,
		health = 380,
		maxEnergy = 110,
		morphName = "BlueMarvel",
		skins = skins("BlueMarvel"),
		abilities = {},
	},
	{
		id = "human_torch",
		displayName = "Human Torch",
		alias = "Johnny Storm",
		powers = "Pyrokinesis, flight, nova flame",
		biography = "The Fantastic Four's hottest head. Flame on is easy. Knowing when to cool it is the trick.",
		tagline = "Flame on",
		price = 0,
		health = 250,
		maxEnergy = 100,
		morphName = "HumanTorchClassic",
		skins = skins("HumanTorchClassic", {
			{ id = "modern", name = "Modern", morphName = "HumanTorchModern" },
		}),
		abilities = {},
	},
	{
		id = "invisible_woman",
		displayName = "Invisible Woman",
		alias = "Susan Storm Richards",
		powers = "Invisibility, force fields, constructs",
		biography = "The quiet center of the Fantastic Four. If you can't see her, you're already inside her plan.",
		tagline = "The shield the team forgets",
		price = 0,
		health = 250,
		maxEnergy = 100,
		morphName = "InvisibleWomanClassic",
		skins = skins("InvisibleWomanClassic", {
			{ id = "modern", name = "Modern", morphName = "InvisibleWomanModern" },
		}),
		abilities = INVISIBLE_WOMAN_ABILITIES,
	},
}

function CharacterRegistry.getRoster(): { CharacterEntry }
	return ROSTER
end

function CharacterRegistry.getById(id: string): CharacterEntry?
	if id == "scarlet_witch" then
		id = "scarlet_witch_classic"
	end
	for _, entry in ROSTER do
		if entry.id == id then
			return entry
		end
	end
	return nil
end

function CharacterRegistry.getSkin(entry: CharacterEntry, skinId: string?): SkinDef
	local wanted = if type(skinId) == "string" and skinId ~= "" then skinId else "base"
	for _, skin in entry.skins do
		if skin.id == wanted then
			if skin.blocked then
				break
			end
			return skin
		end
	end
	for _, skin in entry.skins do
		if not skin.blocked then
			return skin
		end
	end
	return entry.skins[1]
end

function CharacterRegistry.getAvailableSkins(entry: CharacterEntry): { SkinDef }
	local list: { SkinDef } = {}
	for _, skin in entry.skins do
		if not skin.blocked then
			table.insert(list, skin)
		end
	end
	return list
end

function CharacterRegistry.getMorphName(heroId: string, skinId: string?): string?
	local entry = CharacterRegistry.getById(heroId)
	if not entry then
		return nil
	end
	return CharacterRegistry.getSkin(entry, skinId).morphName
end

function CharacterRegistry.getMorphTemplate(heroId: string, skinId: string?): Model?
	local morphName = CharacterRegistry.getMorphName(heroId, skinId)
	if not morphName then
		return nil
	end
	local assets = game:GetService("ReplicatedStorage"):FindFirstChild("Assets")
	local morphs = assets and assets:FindFirstChild("Morphs")
	local template = morphs and morphs:FindFirstChild(morphName)
	if template and template:IsA("Model") then
		return template
	end
	return nil
end

function CharacterRegistry.getAbilities(characterId: string): { AbilityDef }
	local entry = CharacterRegistry.getById(characterId)
	if not entry then
		return {}
	end
	return entry.abilities
end

function CharacterRegistry.getAbilityByKey(characterId: string, key: string): AbilityDef?
	for _, ability in CharacterRegistry.getAbilities(characterId) do
		if ability.key == key then
			return ability
		end
	end
	return nil
end

function CharacterRegistry.getAbilityById(characterId: string, abilityId: string): AbilityDef?
	for _, ability in CharacterRegistry.getAbilities(characterId) do
		if ability.id == abilityId then
			return ability
		end
	end
	return nil
end

function CharacterRegistry.resolveAbilityIcon(ability: AbilityDef, mode: string?): string?
	if mode and ability.modeIcons then
		local byMode = ability.modeIcons[mode]
		if type(byMode) == "string" and byMode ~= "" then
			return byMode
		end
	end
	if type(ability.icon) == "string" and ability.icon ~= "" then
		return ability.icon
	end
	return nil
end

return CharacterRegistry
