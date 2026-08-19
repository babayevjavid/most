--[[ CharacterConfig: roster data for character selection and HUD ability slots. ]]

export type AbilityEntry = {
	id: string,
	name: string,
	key: string,
	description: string?,
	isUltimate: boolean?,
	chargeSeconds: number?,
	cooldownSeconds: number?,
}

export type CharacterEntry = {
	id: string,
	displayName: string,
	subtitle: string,
	bio: string,
	accentColor: Color3,
	locked: boolean?,
	abilities: { AbilityEntry },
}

local function abilities(...: AbilityEntry): { AbilityEntry }
	local list: { AbilityEntry } = {}
	for i = 1, select("#", ...) do
		list[i] = select(i, ...)
	end
	return list
end

local POLARIS: CharacterEntry = {
	id = "Polaris",
	displayName = "Polaris",
	subtitle = "Mistress of Magnetism",
	bio = "A mutant who commands magnetic fields with surgical precision. Polaris bends metal, rides geomagnetic lines, and turns the battlefield into a storm of orbiting shards. Best at controlling space and punishing grouped enemies.",
	accentColor = Color3.fromRGB(80, 220, 120),
	abilities = abilities(
		{
			id = "MagneticFlight",
			name = "Magnetic Flight",
			key = "F",
			description = "Ride magnetic force through the air.",
			cooldownSeconds = 6,
		},
		{
			id = "Ferrokinesis",
			name = "Ferrokinesis",
			key = "E",
			description = "Grab metallic targets, hold them behind you, throw with LMB.",
			cooldownSeconds = 5,
		},
		{
			id = "MagneticPulse",
			name = "Magnetic Pulse",
			key = "C",
			description = "Fire a steerable ring-stack projectile.",
			cooldownSeconds = 3,
		},
		{
			id = "OrbitalStrikes",
			name = "Orbital Strikes",
			key = "Q",
			description = "Orbit metal shards; throw them at your cursor.",
			cooldownSeconds = 10,
		},
		{
			id = "MetalLance",
			name = "Metal Lance",
			key = "T",
			description = "Arm a spike nearby; LMB launches at a target.",
			cooldownSeconds = 8,
		}
	),
}

local HAVOK: CharacterEntry = {
	id = "Havok",
	displayName = "Havok",
	subtitle = "Plasma Conduit",
	bio = "Siphons ambient energy into a charge reservoir, then unleashes it as concussive plasma. Stack charges with Q, detonate with E, and pressure foes with chest beams and kinetic surges.",
	accentColor = Color3.fromRGB(70, 150, 255),
	locked = false,
	abilities = {
		{
			id = "ConcussiveBeam",
			name = "Concussive Beam",
			key = "F",
			description = "Hold to channel a wide plasma beam from your chest; stops on walls.",
			cooldownSeconds = 3,
		},
		{
			id = "EnergyBurst",
			name = "Energy Burst",
			key = "E",
			description = "Detonate around yourself; damage, radius, and push scale with siphon charges (consumes all).",
			cooldownSeconds = 2,
		},
		{
			id = "KineticSurge",
			name = "Kinetic Surge",
			key = "C",
			description = "Rocket-propel yourself in the direction you are aiming.",
			cooldownSeconds = 5.5,
		},
		{
			id = "EnergySiphon",
			name = "Energy Siphon",
			key = "Q",
			description = "Pull in ambient energy; +1 charge (max 5).",
			cooldownSeconds = 5,
		},
		{
			id = "EnergyBlast",
			name = "Energy Blast",
			key = "T",
			description = "Hold to fire a steerable plasma ring-volley toward the cursor.",
			cooldownSeconds = 1.2,
		},
	},
}

local JUBILEE: CharacterEntry = {
	id = "Jubilee",
	displayName = "Jubilee",
	subtitle = "Spark of Light",
	bio = "Projects colorful plasma fireworks that blind, stagger, and chip away at groups. Jubilee thrives in skirmishes where tempo and crowd control matter more than single-target burst.",
	accentColor = Color3.fromRGB(255, 210, 60),
	locked = true,
	abilities = abilities(
		{ id = "SparkStep", name = "Spark Step", key = "F", description = "Quick reposition with sparks.", cooldownSeconds = 4 },
		{ id = "PlasmoidBolt", name = "Plasmoid Bolt", key = "E", description = "Fast plasma bolt.", cooldownSeconds = 3 },
		{ id = "FireworkVolley", name = "Firework Volley", key = "C", description = "Scatter explosive sparks.", cooldownSeconds = 6 },
		{ id = "LightBlind", name = "Light Blind", key = "Q", description = "Flash enemies in a cone.", cooldownSeconds = 8 },
		{ id = "GrandFinale", name = "Grand Finale", key = "T", description = "Charged firework barrage.", cooldownSeconds = 14, isUltimate = true }
	),
}

local MULTIPLE_MAN: CharacterEntry = {
	id = "MultipleMan",
	displayName = "Multiple Man",
	subtitle = "Army of One",
	bio = "Splits into duplicates to overwhelm and confuse opponents. Multiple Man rewards positioning and baiting — each dupe is a threat, but coordination is everything.",
	accentColor = Color3.fromRGB(70, 200, 220),
	locked = true,
	abilities = abilities(
		{ id = "DupeSpawn", name = "Dupe Spawn", key = "F", description = "Create a duplicate.", cooldownSeconds = 6 },
		{ id = "DupeSwarm", name = "Dupe Swarm", key = "E", description = "Send dupes to rush a target.", cooldownSeconds = 5 },
		{ id = "DupeMerge", name = "Dupe Merge", key = "C", description = "Reabsorb dupes for a boost.", cooldownSeconds = 8 },
		{ id = "EchoRush", name = "Echo Rush", key = "Q", description = "Blink between dupes.", cooldownSeconds = 4 },
		{ id = "LegionUlt", name = "Legion", key = "T", description = "Maximum duplicate field.", cooldownSeconds = 16, isUltimate = true }
	),
}

local PSYLOCKE: CharacterEntry = {
	id = "Psylocke",
	displayName = "Psylocke",
	subtitle = "Psychic Blade",
	bio = "A telepath and martial artist who manifests psychic blades and steps through thought. Psylocke is a duelist — precise, mobile, and lethal at close range.",
	accentColor = Color3.fromRGB(160, 90, 220),
	locked = false,
	abilities = abilities(
		{ id = "PsiBlade", name = "Psi Blade", key = "F", description = "Summon a psychic blade.", cooldownSeconds = 4 },
		{ id = "ButterflyStep", name = "Butterfly Step", key = "E", description = "Short-range psionic blink.", cooldownSeconds = 5 },
		{ id = "PsychicSlash", name = "Psychic Slash", key = "C", description = "Arc slash in front.", cooldownSeconds = 3 },
		{ id = "FocusField", name = "Focus Field", key = "Q", description = "Slow enemies in an area.", cooldownSeconds = 9 },
		{ id = "AstralAssault", name = "Astral Assault", key = "T", description = "Rapid blade flurry.", cooldownSeconds = 12, isUltimate = true }
	),
}

local EMMA_FROST: CharacterEntry = {
	id = "EmmaFrost",
	displayName = "Emma Frost",
	subtitle = "Diamond Queen",
	bio = "Transforms into organic diamond and projects devastating psychic force. Emma is a frontline telepath — hard to kill, harder to ignore when she locks onto a mind.",
	accentColor = Color3.fromRGB(200, 230, 255),
	locked = true,
	abilities = abilities(
		{ id = "DiamondForm", name = "Diamond Form", key = "F", description = "Toggle diamond armor.", cooldownSeconds = 8 },
		{ id = "PsychicSpear", name = "Psychic Spear", key = "E", description = "Piercing mental bolt.", cooldownSeconds = 4 },
		{ id = "MentalShackle", name = "Mental Shackle", key = "C", description = "Root a single target.", cooldownSeconds = 7 },
		{ id = "FrostSkin", name = "Frost Skin", key = "Q", description = "Reflect damage briefly.", cooldownSeconds = 10 },
		{ id = "DiamondStorm", name = "Diamond Storm", key = "T", description = "Shard explosion.", cooldownSeconds = 14, isUltimate = true }
	),
}

local QUENTIN_QUIRE: CharacterEntry = {
	id = "QuentinQuire",
	displayName = "Quentin Quire",
	subtitle = "Kid Omega",
	bio = "An omega-level telepath with ego to match. Quentin overwhelms minds, disrupts formations, and turns arrogance into area denial. High risk, high spectacle.",
	accentColor = Color3.fromRGB(200, 120, 200),
	locked = true,
	abilities = abilities(
		{ id = "MindSpike", name = "Mind Spike", key = "F", description = "Single-target psychic hit.", cooldownSeconds = 3 },
		{ id = "TelepathicPush", name = "Telepathic Push", key = "E", description = "Knockback wave.", cooldownSeconds = 5 },
		{ id = "ChaosRant", name = "Chaos Rant", key = "C", description = "Confuse nearby enemies.", cooldownSeconds = 8 },
		{ id = "EgoField", name = "Ego Field", key = "Q", description = "Damage aura while moving.", cooldownSeconds = 9 },
		{ id = "OmegaRant", name = "Omega Rant", key = "T", description = "Massive psychic burst.", cooldownSeconds = 15, isUltimate = true }
	),
}

local SUNSPOT: CharacterEntry = {
	id = "Sunspot",
	displayName = "Sunspot",
	subtitle = "Solar Powered",
	bio = "Absorbs sunlight to fuel superhuman strength and black solar blasts. Stand in the sun to charge — at peak day you hit hardest; at night you fade.",
	accentColor = Color3.fromRGB(230, 180, 40),
	locked = false,
	abilities = abilities(
		{ id = "SolarFlight", name = "Solar Flight", key = "F", description = "Fly on solar currents. Body turns black with solar particles.", cooldownSeconds = 6 },
		{ id = "SunUppercut", name = "Sun Uppercut", key = "E", description = "Close-range punch that launches your target upward.", cooldownSeconds = 4 },
		{ id = "Photosynthesis", name = "Photosynthesis", key = "C", description = "Hold to heal and regain energy in sunlight; slower heal in shade at an energy cost.", cooldownSeconds = 2 },
		{ id = "SolarFlare", name = "Solar Flare", key = "Q", description = "Steerable solar blast.", cooldownSeconds = 3 },
		{ id = "BlackSun", name = "Black Sun", key = "Z", description = "Hold to grow a dark sun; release or LMB to throw.", cooldownSeconds = 14, chargeSeconds = 1, isUltimate = true }
	),
}

local ROSTER: { CharacterEntry } = {
	POLARIS,
	HAVOK,
	JUBILEE,
	MULTIPLE_MAN,
	PSYLOCKE,
	EMMA_FROST,
	QUENTIN_QUIRE,
	SUNSPOT,
}

local CharacterConfig = {}

function CharacterConfig.getRoster(): { CharacterEntry }
	-- Explicit ordered list so selection UI always receives every hero entry.
	return {
		POLARIS,
		HAVOK,
		JUBILEE,
		MULTIPLE_MAN,
		PSYLOCKE,
		EMMA_FROST,
		QUENTIN_QUIRE,
		SUNSPOT,
	}
end

function CharacterConfig.getCharacter(id: string): CharacterEntry?
	for _, entry in ROSTER do
		if entry.id == id then
			return entry
		end
	end
	return nil
end

function CharacterConfig.getPlayableCharacters(): { CharacterEntry }
	local playable = {}
	for _, entry in ROSTER do
		if not entry.locked then
			table.insert(playable, entry)
		end
	end
	return playable
end

return CharacterConfig
