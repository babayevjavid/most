-- Resolve playable role (Piper, Prue, Phoebe, Paige, Belthazor) for a character Model.
-- Players: uses Player:GetAttribute("ChosenCharacter") (mirrored on character model from CharacterSelect).
-- NPCs: set Model:SetAttribute("ChosenCharacter", "Piper") (or any name in CharacterConfig.Choices).

local Players = game:GetService("Players")

local CharacterConfig = require(script.Parent.CharacterConfig)

local VALID_ROLE: { [string]: boolean } = {}
for _, name in CharacterConfig.Choices do
	VALID_ROLE[name] = true
end

local CharacterIdentity = {}

function CharacterIdentity.isValidRoleName(name: string): boolean
	return VALID_ROLE[name] == true
end

function CharacterIdentity.getChosenCharacterRole(model: Model): string?
	if not model or not model:IsA("Model") then
		return nil
	end
	local plr = Players:GetPlayerFromCharacter(model)
	if plr then
		local c = plr:GetAttribute("ChosenCharacter")
		if type(c) == "string" and c ~= "" and VALID_ROLE[c] then
			return c
		end
	end
	local c = model:GetAttribute("ChosenCharacter")
	if type(c) == "string" and c ~= "" and VALID_ROLE[c] then
		return c
	end
	return nil
end

return CharacterIdentity
