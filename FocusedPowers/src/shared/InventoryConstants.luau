--[[
	Inventory tuning and item catalog.
]]

export type ItemDefinition = {
	id: string,
	name: string,
	description: string,
	rarityColor: Color3,
	maxStack: number,
	characterId: string?,
	equipSlot: number?,
	visualModelName: string?,
}

return {
	SLOT_COUNT = 20,
	COLUMNS = 5,
	ROWS = 4,

	BACKPACK_IMAGE = "rbxassetid://4814045309",
	BACKPACK_TOP_MARGIN = 10,
	BACKPACK_BUTTON_SIZE = 44,
	BACKPACK_RIGHT_MARGIN = 12,
	BACKPACK_SETTINGS_GAP = 8,
	BACKPACK_SETTINGS_BUTTON_WIDTH = 88,
	BACKPACK_BG_TRANSPARENCY = 0.55,
	PANEL_BG_TRANSPARENCY = 0.42,
	INVENTORY_DISPLAY_ORDER = 60,
	SLOT_SIZE = 56,
	SLOT_PADDING = 6,
	SLOT_BG_TRANSPARENCY = 0.55,

	DATA_STORE_NAME = "FocusedPowersInventory_v3",

	HOTBAR_SLOT_COUNT = 3,
	HOTBAR_BAR_RIGHT_OFFSET = 22,
	HOTBAR_BAR_BOTTOM_OFFSET = 20,
	HOTBAR_SLOT_SIZE = 56,
	HOTBAR_SLOT_PADDING = 6,
	HOTBAR_HOTKEYS = { "1", "2", "3" },

	-- Legacy aliases
	EQUIP_SLOT_COUNT = 3,
	EQUIP_BAR_RIGHT_OFFSET = 22,
	EQUIP_BAR_BOTTOM_OFFSET = 20,
	EQUIP_SLOT_SIZE = 56,
	EQUIP_SLOT_PADDING = 6,
	EQUIP_HOTKEYS = { "1", "2", "3" },

	ITEMS = {
		psionic_shard = {
			id = "psionic_shard",
			name = "Psionic Shard",
			description = "A crystallized fragment of psychic energy. Restores focus when used.",
			rarityColor = Color3.fromRGB(255, 105, 220),
			maxStack = 99,
		},
		hero_token = {
			id = "hero_token",
			name = "Hero Token",
			description = "Currency earned from combat. Trade for upgrades.",
			rarityColor = Color3.fromRGB(255, 200, 80),
			maxStack = 999,
		},
		focus_crystal = {
			id = "focus_crystal",
			name = "Focus Crystal",
			description = "Sharpens telepathic clarity for a short time.",
			rarityColor = Color3.fromRGB(140, 180, 255),
			maxStack = 20,
		},
		teleport_tag = {
			id = "teleport_tag",
			name = "Teleport Tag",
			description = "A bamf-scented marker linked to the astral plane.",
			rarityColor = Color3.fromRGB(90, 70, 220),
			maxStack = 10,
		},
		steel_plating = {
			id = "steel_plating",
			name = "Steel Plating",
			description = "Reinforced organic steel scrap. Heavy but durable.",
			rarityColor = Color3.fromRGB(180, 190, 210),
			maxStack = 50,
		},
		psylocke_katana = {
			id = "psylocke_katana",
			name = "Katana",
			description = "A steel katana. Place in hotbar slot 1, then press 1 to wield on your right arm.",
			rarityColor = Color3.fromRGB(190, 195, 205),
			maxStack = 1,
			characterId = "Psylocke",
			equipSlot = 1,
			visualModelName = "Katana",
		},
	} :: { [string]: ItemDefinition },

	STARTER_ITEMS = {
		{ itemId = "psylocke_katana", quantity = 1 },
	},
}
