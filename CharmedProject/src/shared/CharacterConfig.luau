return {
	Choices = { "Piper", "Prue", "Phoebe", "Paige", "Belthazor" },
	CombatMaxHealth = 100,
	-- NPC: tag models with CollectionService using BelthazorTagName (not a playable Charmed sister).
	BelthazorTagName = "Belthazor",
	BelthazorCombatHealth = 400,
	-- All three sisters must chat this phrase (case-insensitive) within VanquishWindowSeconds;
	-- each must be within VanquishRadiusStuds of Belthazor's HumanoidRootPart.
	BelthazorVanquishSubstring = "vanquish belthazor",
	-- Full line shown in Spells UI / sent to chat; must contain BelthazorVanquishSubstring.
	BelthazorVanquishIncantation = "By the Power of Three, we cast you out—harm to none, fate revealed. With this light we vanquish Belthazor.",
	BelthazorVanquishWindowSeconds = 5,
	BelthazorVanquishRadiusStuds = 50,
	BelthazorVanquishTriples = {
		{ "Piper", "Prue", "Phoebe" },
		{ "Piper", "Phoebe", "Paige" },
	},
	-- Belthazor NPC: projectiles spawn from right hand toward nearest player (stand-in for mouse aim); shimmer teleports to ground near target.
	BelthazorAggroRangeStuds = 140,
	BelthazorThinkIntervalSeconds = 0.35,
	BelthazorFireballCooldown = 2,
	BelthazorFireballDamage = 24,
	BelthazorFireballSpeed = 100,
	BelthazorFireballSizeStuds = 3,
	BelthazorFireballLifetime = 5,
	BelthazorEnergyBallCooldown = 5,
	BelthazorEnergyBallDamage = 46,
	BelthazorEnergyBallSpeed = 92,
	BelthazorEnergyBallSizeStuds = 3.5,
	BelthazorEnergyBallLifetime = 5,
	BelthazorShimmerCooldown = 7,
	BelthazorShimmerMaxRangeStuds = 78,
	BelthazorShimmerMinRangeStuds = 10,
	BelthazorShimmerOffsetStuds = 12,
	-- Telekinesis: initial grab range; hold drops if grabbed part goes farther than max hold distance from caster HRP.
	TelekinesisGrabRangeStuds = 50,
	TelekinesisMaxHoldDistanceStuds = 50,
	DefaultEnergy = 100,
	-- Morality: GoodEvil on Player (-1 evil .. +1 good). Witches spawn good; Belthazor spawns evil.
	WitchSpawnGoodEvil = 0.72,
	DemonSpawnGoodEvil = -0.82,
	MoralityPerDamagePoint = 0.004,
	MoralityPerFreezeVictim = 0.012,
	GoodNonWitchFreezeImmuneAbove = 0.38,
	SelectionRemoteName = "CharacterSelected",
	RemotesFolderName = "CharacterRemotes",
	PowerCastRemoteName = "PowerCast",
	SpellCastRemoteName = "SpellCast",
	-- Lines players type in chat for spell flows (must match server spell checks).
	SpellChatLinesById = {
		return_to_sender = "Let the object of objection become but a dream, as I cause the scene to be no more than it seems.",
		powers_exchange = "What's mine is yours, What's yours is mine. I offer up my gift to share, Switch our powers through the air;",
		vanquish_belthazor = "By the Power of Three, we cast you out—harm to none, fate revealed. With this light we vanquish Belthazor.",
	},
	PowersByCharacter = {
		Prue = {
			{ Id = "telekinesis", Name = "Telekinesis", Energy = 9, Cooldown = 2, Targeted = true, Icon = "TK" },
			{ Id = "astral_projection", Name = "Astral Projection", Energy = 15, Cooldown = 6, Targeted = false, Icon = "AP" },
		},
		Paige = {
			{ Id = "orbing", Name = "Orbing", Energy = 10, Cooldown = 2, Targeted = true, Icon = "OR" },
			{ Id = "telekinetic_orbing", Name = "Telekinetic Orbing", Energy = 12, Cooldown = 3, Targeted = true, Icon = "TO" },
			{ Id = "healing", Name = "Healing", Energy = 12, Cooldown = 4, Targeted = false, Icon = "HE" },
		},
		Piper = {
			{ Id = "molecular_freeze", Name = "Molecular Freeze", Energy = 14, Cooldown = 5, Targeted = false, Icon = "FR" },
			{ Id = "molecular_combustion", Name = "Molecular Combustion", Energy = 13, Cooldown = 2, Targeted = true, Icon = "CB" },
		},
		Phoebe = {
			{ Id = "premonition", Name = "Premonition", Energy = 9, Cooldown = 5, Targeted = false, Icon = "PR" },
			{ Id = "levitation", Name = "Levitation", Energy = 8, Cooldown = 2, Targeted = false, Icon = "LV" },
			{
				Id = "empathic_deflection",
				Name = "Empathic Deflection",
				Energy = 18,
				Cooldown = 5,
				Targeted = false,
				Icon = "ED",
			},
		},
		Belthazor = {
			{ Id = "belthazor_fireball", Name = "Fireball", Energy = 11, Cooldown = 2, Targeted = true, Icon = "FB" },
			{ Id = "belthazor_energy_ball", Name = "Energy Ball", Energy = 17, Cooldown = 5, Targeted = true, Icon = "EB" },
			{ Id = "belthazor_shimmer", Name = "Shimmering", Energy = 15, Cooldown = 7, Targeted = true, Icon = "SH" },
		},
	},
}
