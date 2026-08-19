--!strict
--[[ Client visuals for worn hotbar items on characters. ]]

local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local InventoryEquipmentHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("InventoryEquipmentHelper"))

local InventoryEquipmentClient = {}

local boundCharacters: { [Model]: { RBXScriptConnection } } = {}

local function getPlayerForCharacter(character: Model): Player?
	return Players:GetPlayerFromCharacter(character)
end

local function bindCharacter(character: Model)
	if boundCharacters[character] then
		return
	end

	local connections: { RBXScriptConnection } = {}
	table.insert(
		connections,
		character:GetAttributeChangedSignal(InventoryEquipmentHelper.WORN_ITEM_ATTRIBUTE):Connect(function()
			local player = getPlayerForCharacter(character)
			InventoryEquipmentHelper.syncCharacterVisuals(character, player)
		end)
	)
	table.insert(
		connections,
		character:GetAttributeChangedSignal(InventoryEquipmentHelper.ACTIVE_HOTBAR_ATTRIBUTE):Connect(function()
			local player = getPlayerForCharacter(character)
			InventoryEquipmentHelper.syncCharacterVisuals(character, player)
		end)
	)

	table.insert(
		connections,
		character.AncestryChanged:Connect(function(_, parent)
			if not parent then
				local existing = boundCharacters[character]
				if existing then
					for _, conn in existing do
						conn:Disconnect()
					end
					boundCharacters[character] = nil
				end
			end
		end)
	)

	boundCharacters[character] = connections
	local player = getPlayerForCharacter(character)
	InventoryEquipmentHelper.syncCharacterVisuals(character, player)
end

function InventoryEquipmentClient.start(_localPlayer: Player)
	local function onCharacter(character: Model)
		bindCharacter(character)
	end

	for _, player in Players:GetPlayers() do
		if player.Character then
			onCharacter(player.Character)
		end
		player.CharacterAdded:Connect(onCharacter)
	end

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(onCharacter)
		if player.Character then
			onCharacter(player.Character)
		end
	end)
end

return InventoryEquipmentClient
