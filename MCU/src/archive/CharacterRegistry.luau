--!strict

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
	-- rbxassetid://… shown in the HUD ability button (1:1). Optional modeIcons override by mode name.
	icon: string?,
	modeIcons: { [string]: string }?,
}

export type CharacterEntry = {
	id: string,
	displayName: string,
	tagline: string,
	price: number,
	health: number,
	maxEnergy: number,
	abilities: { AbilityDef },
}

local CharacterRegistry = {}

-- Shared ability button art (1:1 images)
local ICON = {
	BLAST = "rbxassetid://88834657233251",
	BLAST_BARRAGE = "rbxassetid://93840780903953",
	BEAM = "rbxassetid://102090081611652",
	FLIGHT = "rbxassetid://97557836796969",
	SHIELD = "rbxassetid://71538473086600",
	TELEPORT = "rbxassetid://127381677082299",
	TK_SINGLE = "rbxassetid://84179241764291",
	TK_MULTI = "rbxassetid://108422225553070",
	CHAOS_IMPACT = "rbxassetid://137393039253536",
	REGEN = "rbxassetid://132088481923073",
	SANCTUARY = "rbxassetid://78448309200132",
	DAGGER_THROW = "rbxassetid://89605124987453",
	LOKI_CLONE = "rbxassetid://137416284296732",
	LOKI_REFLECT = "rbxassetid://76685688907082",
	SHAPESHIFT = "rbxassetid://98087785932225",
	PHOTON_DIVE = "rbxassetid://78706422300597",
	ICE_SHARD = "rbxassetid://126820075232210",
	ICE_WALL = "rbxassetid://124223016714635",
	ABSOLUTE_ZERO = "rbxassetid://94565965430849",
	SHATTER = "rbxassetid://72567987528587",
	FLASH_FREEZE = "rbxassetid://90339745057370",
	CRYO_STREAM = "rbxassetid://120700053992839",
}

local SCARLET_WITCH_ABILITIES: { AbilityDef } = {
	{
		id = "hex_blast",
		name = "Hex Blast",
		description = "Single (1s CD): one chaos bolt. Barrage (3s CD): slow expand then accelerate toward cursor.",
		key = "Q",
		cooldown = 1,
		energyCost = 2,
		modes = { "Single", "Barrage" },
		icon = ICON.BLAST,
		modeIcons = {
			Single = ICON.BLAST,
			Barrage = ICON.BLAST_BARRAGE,
		},
	},
	{
		id = "hex_flight",
		name = "Hex Flight",
		description = "Toggle hex flight. WASD follows camera.",
		key = "F",
		cooldown = 2,
		energyCost = 0,
		icon = ICON.FLIGHT,
	},
	{
		id = "telekinesis",
		name = "Telekinesis",
		description = "Hold E to lift. Modes: Single / Multiple / Torture. Scroll = distance. Click throws (not Torture). Torture locks your walk and damages the victim.",
		key = "E",
		cooldown = 7,
		energyCost = 0,
		hold = true,
		modes = { "Single", "Multiple", "Torture" },
		icon = ICON.TK_SINGLE,
		modeIcons = {
			Single = ICON.TK_SINGLE,
			Multiple = ICON.TK_MULTI,
			Torture = ICON.TK_SINGLE,
		},
	},
	{
		id = "hex_beam",
		name = "Hex Beam",
		description = "Hold: beam from right hand toward cursor (stops on first hit). Tip damages in 2x2x2.",
		key = "T",
		cooldown = 6,
		energyCost = 1,
		hold = true,
		icon = ICON.BEAM,
	},
	{
		id = "hex_shield",
		name = "Shield",
		description = "Hold: blocks abilities and absorbs projectiles. Partial shield faces incoming bolts.",
		key = "C",
		cooldown = 10,
		energyCost = 0,
		hold = true,
		icon = ICON.SHIELD,
	},
	{
		id = "ultimate",
		name = "Ultimate",
		description = "Modes share cooldown. Power Absorption: drain a <10% HP target through 3 curving hex beams and heal yourself. Disintegration: dissolve low-HP foes or Interactables.",
		key = "X",
		cooldown = 22,
		energyCost = 5,
		modes = { "Absorption", "Disintegration" },
	},
	{
		id = "teleportation",
		name = "Teleportation",
		description = "Press V to aim (air OK), click to vanish and reappear at the mark.",
		key = "V",
		cooldown = 8,
		energyCost = 2,
		sideBar = true,
		icon = ICON.TELEPORT,
	},
	{
		id = "fear_inducement",
		name = "Fear Inducement",
		description = "Hex-copy haunts the hovered player or NPC. They lose powers for 10s.",
		key = "G",
		cooldown = 30,
		energyCost = 4,
		sideBar = true,
	},
	{
		id = "regeneration",
		name = "Regeneration",
		description = "Hold: drain energy to heal. Works in and out of combat. Chaos particles wrap the body.",
		key = "B",
		cooldown = 8,
		energyCost = 0,
		hold = true,
		sideBar = true,
		icon = ICON.REGEN,
	},
	{
		id = "chaos_impact",
		name = "Chaos Impact",
		description = "Passive: after a high fall (30+), soft-lands then slams — damage, push, 3s ragdoll in 30 studs. 15s cooldown.",
		key = "",
		cooldown = 15,
		energyCost = 0,
		passive = true,
		icon = ICON.CHAOS_IMPACT,
	},
}

--[[
	Captain Marvel:
	- Photon Flight / Blast / Beam / Explosion
	- Energy Absorption (passive): 15% projectile/beam → energy, health, absorb charge
	- Absorb charge: up to 1.5x outgoing damage
	- Binary Form: 3x damage / 3x energy + body particles
]]
local CAPTAIN_MARVEL_ABILITIES: { AbilityDef } = {
	{
		id = "photon_blast",
		name = "Photon Blast",
		description = "Fire a photon blast toward your cursor.",
		key = "Q",
		cooldown = 1,
		energyCost = 2,
		icon = ICON.BLAST,
	},
	{
		id = "photon_flight",
		name = "Photon Flight",
		description = "Toggle flight. Modes: Normal / Accelerated (higher energy). Accelerated knocks, damages, and ragdolls (2s) anyone in your path.",
		key = "F",
		cooldown = 2,
		energyCost = 0,
		modes = { "Normal", "Accelerated" },
		icon = ICON.FLIGHT,
	},
	{
		id = "photon_beam",
		name = "Photon Beam",
		description = "Hold: continuous photon beam toward cursor. Wider tip, slightly less damage than Hex Beam.",
		key = "T",
		cooldown = 6,
		energyCost = 1,
		hold = true,
		icon = ICON.BEAM,
	},
	{
		id = "energy_absorption",
		name = "Energy Absorption",
		description = "Passive: absorb 15% of projectile and beam damage into energy, health, and bonus damage charge.",
		key = "",
		cooldown = 0,
		energyCost = 0,
		passive = true,
	},
	{
		id = "photon_explosion",
		name = "Photon Explosion",
		description = "Photon blast that detonates on impact (radius 10): 25 damage, push, and ragdoll.",
		key = "E",
		cooldown = 8,
		energyCost = 4,
		icon = ICON.BLAST,
	},
	{
		id = "photon_dive",
		name = "Photon Dive",
		description = "Flight only: dive to the ground under your cursor, end flight, and slam (10 stud AOE — damage, push, ragdoll).",
		key = "C",
		cooldown = 8,
		energyCost = 4,
		icon = ICON.PHOTON_DIVE,
	},
	{
		id = "binary_form",
		name = "Binary Form",
		description = "Toggle (15s): 1.5x damage and energy cost. Absorbed energy fills the bar 2x faster. Photon particles wrap the body. 45s cooldown after.",
		key = "X",
		cooldown = 45,
		energyCost = 0,
	},
}

--[[
	Loki — trickster kit
]]
local LOKI_ABILITIES: { AbilityDef } = {
	{
		id = "dagger_throw",
		name = "Dagger Throw",
		description = "Throw two daggers (right hand, then left) toward your cursor.",
		key = "Q",
		cooldown = 1,
		energyCost = 2,
		icon = ICON.DAGGER_THROW,
	},
	{
		id = "illusion_decoy",
		name = "Illusion Decoy",
		description = "Hold E, click to place a clone (max 20s). Right panel: Punch / Run / Detonate / Lie of Place. 30s CD after clone ends.",
		key = "E",
		cooldown = 30,
		energyCost = 3,
		hold = true,
		icon = ICON.LOKI_CLONE,
	},
	{
		id = "trickster_dash",
		name = "Trickster Move",
		description = "Dash or Teleport (mode). Teleport: press F to aim, click to go (50 studs).",
		key = "F",
		cooldown = 3,
		energyCost = 1,
		icon = ICON.FLIGHT,
		modeIcons = {
			Dash = ICON.FLIGHT,
			Teleport = ICON.TELEPORT,
		},
	},
	{
		id = "reflect_shield",
		name = "Reflect Shield",
		description = "0.5s: outline highlight. Reflects abilities used on you (not projectiles/beams/explosions).",
		key = "C",
		cooldown = 5,
		energyCost = 2,
		icon = ICON.LOKI_REFLECT,
	},
	{
		id = "shapeshift",
		name = "Shapeshifting",
		description = "Look like the humanoid under your cursor for 10s.",
		key = "V",
		cooldown = 35,
		energyCost = 3,
		sideBar = true,
		icon = ICON.SHAPESHIFT,
	},
	{
		id = "god_of_mischief",
		name = "God of Mischief",
		description = "Turn invisible 10s. Spawn 3 roaming clones. Ult panel: Attack On / Attack Off. Clones blast when Attack is on.",
		key = "X",
		cooldown = 40,
		energyCost = 18,
	},
}

--[[
	Dagger — living light skirmisher
]]
local DAGGER_ABILITIES: { AbilityDef } = {
	{
		id = "light_daggers",
		name = "Light Daggers",
		description = "Throw one light dagger. Heals allies on your list, damages others. Ricochets up to 2 times.",
		key = "Q",
		cooldown = 1,
		energyCost = 2,
		icon = ICON.BLAST,
	},
	{
		id = "radiant_bomb",
		name = "Radiant Bomb",
		description = "Throw a radiant bomb that detonates on impact: damages foes, heals allies in the blast.",
		key = "E",
		cooldown = 8,
		energyCost = 4,
		icon = ICON.BLAST,
	},
	{
		id = "light_veil",
		name = "Light Veil",
		description = "Fire a light projectile that wraps the hit target in a white veil buff.",
		key = "F",
		cooldown = 12,
		energyCost = 3,
	},
	{
		id = "sanctuary",
		name = "Sanctuary",
		description = "Create a light circle: allies heal, enemies take soft light damage.",
		key = "T",
		cooldown = 18,
		energyCost = 5,
		icon = ICON.SANCTUARY,
	},
	{
		id = "blinding_flash",
		name = "Blinding Flash",
		description = "Flash of light blinds nearby foes (screen whites out). Particles TBD.",
		key = "C",
		cooldown = 16,
		energyCost = 4,
	},
	{
		id = "lumen_barrage",
		name = "Lumen Barrage",
		description = "Fire a barrage of 5 light daggers toward your cursor.",
		key = "X",
		cooldown = 7,
		energyCost = 4,
		icon = ICON.BLAST_BARRAGE,
	},
	{
		id = "purify",
		name = "Purify",
		description = "Cleanse self and nearby allies (ragdoll / power lock). Grants 1.5x speed & jump for 10s. Particles TBD.",
		key = "V",
		cooldown = 14,
		energyCost = 3,
		sideBar = true,
	},
}

--[[
	Marvel Girl — Jean Grey telepath / telekinetic
]]
local MARVEL_GIRL_ABILITIES: { AbilityDef } = {
	{
		id = "psionic_bolt",
		name = "Psionic Bolt",
		description = "Fire 5 psionic bolts. Each shot aims at your current cursor and flies straight.",
		key = "Q",
		cooldown = 2,
		energyCost = 3,
		icon = ICON.BLAST,
	},
	{
		id = "psychic_pull",
		name = "Psychic Pull",
		description = "Yank nearby foes slightly toward you and deal light damage.",
		key = "E",
		cooldown = 12,
		energyCost = 5,
	},
	{
		id = "telekinetic_flight",
		name = "Telekinetic Flight",
		description = "Toggle telekinetic flight. WASD follows camera.",
		key = "F",
		cooldown = 2,
		energyCost = 0,
		icon = ICON.FLIGHT,
	},
	{
		id = "telekinetic_slam",
		name = "Telekinetic Slam",
		description = "Grab a target, slam them into the ground 3 times, then hurl them toward your cursor.",
		key = "T",
		cooldown = 14,
		energyCost = 6,
	},
	{
		id = "telekinetic_debris",
		name = "Telekinetic Debris",
		description = "Rip 3 rocks from nearby ground; they rise then fly toward your cursor (damage + soft push).",
		key = "X",
		cooldown = 5,
		energyCost = 3,
	},
	{
		id = "psionic_barrier",
		name = "Psionic Barrier",
		description = "Hold: raise a psionic forcefield (100 HP) that absorbs damage.",
		key = "C",
		cooldown = 10,
		energyCost = 0,
		hold = true,
		icon = ICON.SHIELD,
	},
	{
		id = "astral_projection",
		name = "Astral Projection",
		description = "Leave your body as a flying astral copy. Hold as long as you have energy; press V again to return.",
		key = "V",
		cooldown = 20,
		energyCost = 6,
		sideBar = true,
	},
	{
		id = "mind_link",
		name = "Mind Link",
		description = "Open a mind link, then aim and press G to add people (5s add CD, max 5). Press G with no target to close.",
		key = "G",
		cooldown = 8,
		energyCost = 2,
		sideBar = true,
	},
}

--[[
	Iceman — Chill / Freeze pressure. Every ice hit stacks Chill (slow); a full
	bar freezes the target solid. Shatter spends the stacks for burst damage.
]]
local ICEMAN_ABILITIES: { AbilityDef } = {
	{
		id = "ice_shards",
		name = "Ice Shards",
		description = "Fire an ice shard toward your cursor. Hits add Chill.",
		key = "Q",
		cooldown = 1,
		energyCost = 2,
		icon = ICON.ICE_SHARD,
	},
	{
		id = "ice_wall",
		name = "Ice Wall",
		description = "Raise a tall ice wall from solid ground in front of you. Blocks movement and projectiles for 10s.",
		key = "E",
		cooldown = 12,
		energyCost = 4,
		icon = ICON.ICE_WALL,
	},
	{
		id = "ice_slide",
		name = "Ice Slide",
		description = "Toggle: continuous forward skate along your camera (slightly upward). Ice path is visual only.",
		key = "F",
		cooldown = 2,
		energyCost = 0,
		icon = ICON.FLIGHT,
	},
	{
		id = "cryo_stream",
		name = "Cryo Stream",
		description = "Hold: chill aura in front of you (25 studs). Slows foes and builds Freeze.",
		key = "T",
		cooldown = 6,
		energyCost = 1,
		hold = true,
		icon = ICON.CRYO_STREAM,
	},
	{
		id = "ice_form",
		name = "Ice Form",
		description = "Toggle (18s): solid ice body — double max HP (current HP scales by %). Nearby foes gain Chill.",
		key = "C",
		cooldown = 20,
		energyCost = 0,
	},
	{
		id = "absolute_zero",
		name = "Absolute Zero",
		description = "Expanding ice circle from you (6s): damage + heavy Chill. Anyone maxed out freezes solid.",
		key = "X",
		cooldown = 45,
		energyCost = 18,
		icon = ICON.ABSOLUTE_ZERO,
	},
	{
		id = "flash_freeze",
		name = "Flash Freeze",
		description = "Fire a freezing shard. On hit: shove the target, then encase them in ice for 15s.",
		key = "V",
		cooldown = 16,
		energyCost = 5,
		sideBar = true,
		icon = ICON.FLASH_FREEZE,
	},
	{
		id = "shatter",
		name = "Shatter",
		description = "Detonate Chill on nearby foes — damage scales with their stacks. Frozen targets take extra.",
		key = "G",
		cooldown = 10,
		energyCost = 3,
		sideBar = true,
		icon = ICON.SHATTER,
	},
	{
		id = "sub_zero_body",
		name = "Sub-Zero Body",
		description = "Passive: immune to Chill and freezing.",
		key = "",
		cooldown = 0,
		energyCost = 0,
		passive = true,
	},
}

local ROSTER: { CharacterEntry } = {
	{
		id = "scarlet_witch",
		displayName = "Scarlet Witch",
		tagline = "Chaos magic reality warper",
		price = 0,
		health = 280,
		maxEnergy = 100,
		abilities = SCARLET_WITCH_ABILITIES,
	},
	{
		id = "captain_marvel",
		displayName = "Captain Marvel",
		tagline = "Photon-powered cosmic fighter",
		price = 0,
		health = 400,
		maxEnergy = 100,
		abilities = CAPTAIN_MARVEL_ABILITIES,
	},
	{
		id = "loki",
		displayName = "Loki",
		tagline = "God of Mischief",
		price = 0,
		health = 300,
		maxEnergy = 100,
		abilities = LOKI_ABILITIES,
	},
	{
		id = "dagger",
		displayName = "Dagger",
		tagline = "Living light of hope",
		price = 0,
		health = 260,
		maxEnergy = 100,
		abilities = DAGGER_ABILITIES,
	},
	{
		id = "marvel_girl",
		displayName = "Marvel Girl",
		tagline = "Telepath & telekinetic",
		price = 0,
		health = 270,
		maxEnergy = 100,
		abilities = MARVEL_GIRL_ABILITIES,
	},
	{
		id = "iceman",
		displayName = "Iceman",
		tagline = "Omega-level cryokinetic",
		price = 0,
		health = 300,
		maxEnergy = 100,
		abilities = ICEMAN_ABILITIES,
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

--[[ Resolve HUD icon for an ability, honoring modeIcons when a mode is active. ]]
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
