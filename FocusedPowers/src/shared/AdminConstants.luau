--!strict
--[[ Admin user allowlist — add your Roblox userId below. ]]

return {
	--[[ Studio playtests always grant admin. Published games use CREATOR_IS_ADMIN + USER_IDS. ]]
	STUDIO_GRANTS_ADMIN = true,
	CREATOR_IS_ADMIN = true,
	USER_IDS = {
		1674593944,
	},
}
