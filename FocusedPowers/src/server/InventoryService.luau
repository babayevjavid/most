--!strict
--[[
	Server-authoritative inventory with DataStore persistence and attribute replication.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InventoryConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("InventoryConstants"))
local InventoryHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("InventoryHelper"))
local InventoryEquipmentHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("InventoryEquipmentHelper"))

local ATTRIBUTE_NAME = "InventoryData"

local InventoryService = {}

local store = DataStoreService:GetDataStore(InventoryConstants.DATA_STORE_NAME)
local cache: { [Player]: InventoryHelper.InventorySnapshot } = {}
local wornHotbarSlot: { [Player]: number? } = {}

local function syncWornState(plr: Player)
	local char = plr.Character
	if not char then
		return
	end

	local snapshot = cache[plr]
	local wornIndex = wornHotbarSlot[plr]
	local wornItemId: string? = nil

	if wornIndex and snapshot then
		local slot = snapshot.hotbar[wornIndex]
		if
			not InventoryHelper.isSlotEmpty(slot)
			and InventoryEquipmentHelper.canWearItem(plr, slot.itemId, wornIndex)
		then
			wornItemId = slot.itemId
		else
			wornHotbarSlot[plr] = nil
			wornIndex = nil
		end
	end

	char:SetAttribute(InventoryEquipmentHelper.WORN_ITEM_ATTRIBUTE, wornItemId)
	char:SetAttribute(InventoryEquipmentHelper.ACTIVE_HOTBAR_ATTRIBUTE, wornIndex)
end

local function syncPlayer(plr: Player, snapshot: InventoryHelper.InventorySnapshot)
	plr:SetAttribute(ATTRIBUTE_NAME, InventoryHelper.encode(snapshot))
	syncWornState(plr)
end

local function loadInventory(plr: Player): InventoryHelper.InventorySnapshot
	local key = "p_" .. plr.UserId
	local ok, saved = pcall(function()
		return store:GetAsync(key)
	end)

	if ok and typeof(saved) == "string" and saved ~= "" then
		return InventoryHelper.applyStarterItems(InventoryHelper.decode(saved))
	end

	local snapshot = InventoryHelper.createEmpty()
	return InventoryHelper.applyStarterItems(snapshot)
end

local function saveInventory(plr: Player)
	local snapshot = cache[plr]
	if not snapshot then
		return
	end
	local key = "p_" .. plr.UserId
	pcall(function()
		store:SetAsync(key, InventoryHelper.encode(snapshot))
	end)
end

local function swapEntries(a: InventoryHelper.SlotEntry, b: InventoryHelper.SlotEntry)
	local itemId = a.itemId
	local quantity = a.quantity
	a.itemId = b.itemId
	a.quantity = b.quantity
	b.itemId = itemId
	b.quantity = quantity
end

function InventoryService.swapSlots(plr: Player, fromIndex: number, toIndex: number): boolean
	local snapshot = cache[plr]
	if not snapshot then
		return false
	end
	if fromIndex == toIndex then
		return true
	end
	if fromIndex < 1 or fromIndex > InventoryConstants.SLOT_COUNT then
		return false
	end
	if toIndex < 1 or toIndex > InventoryConstants.SLOT_COUNT then
		return false
	end

	swapEntries(snapshot.slots[fromIndex], snapshot.slots[toIndex])
	syncPlayer(plr, snapshot)
	return true
end

function InventoryService.moveBackpackToHotbar(plr: Player, backpackIndex: number, hotbarIndex: number): boolean
	local snapshot = cache[plr]
	if not snapshot then
		return false
	end
	if backpackIndex < 1 or backpackIndex > InventoryConstants.SLOT_COUNT then
		return false
	end
	if hotbarIndex < 1 or hotbarIndex > InventoryConstants.HOTBAR_SLOT_COUNT then
		return false
	end

	local backpackSlot = snapshot.slots[backpackIndex]
	if InventoryHelper.isSlotEmpty(backpackSlot) then
		return false
	end
	if not InventoryEquipmentHelper.canPlaceInHotbar(plr, backpackSlot.itemId, hotbarIndex) then
		return false
	end

	swapEntries(backpackSlot, snapshot.hotbar[hotbarIndex])
	syncPlayer(plr, snapshot)
	return true
end

function InventoryService.moveHotbarToBackpack(plr: Player, hotbarIndex: number, backpackIndex: number?): boolean
	local snapshot = cache[plr]
	if not snapshot then
		return false
	end
	if hotbarIndex < 1 or hotbarIndex > InventoryConstants.HOTBAR_SLOT_COUNT then
		return false
	end

	local hotbarSlot = snapshot.hotbar[hotbarIndex]
	if InventoryHelper.isSlotEmpty(hotbarSlot) then
		return false
	end

	local targetIndex = backpackIndex
	if targetIndex then
		if targetIndex < 1 or targetIndex > InventoryConstants.SLOT_COUNT then
			return false
		end
	else
		for index = 1, InventoryConstants.SLOT_COUNT do
			if InventoryHelper.isSlotEmpty(snapshot.slots[index]) then
				targetIndex = index
				break
			end
		end
	end

	if not targetIndex then
		return false
	end

	if wornHotbarSlot[plr] == hotbarIndex then
		wornHotbarSlot[plr] = nil
	end

	swapEntries(hotbarSlot, snapshot.slots[targetIndex])
	syncPlayer(plr, snapshot)
	return true
end

function InventoryService.swapHotbar(plr: Player, fromIndex: number, toIndex: number): boolean
	local snapshot = cache[plr]
	if not snapshot then
		return false
	end
	if fromIndex == toIndex then
		return true
	end
	if fromIndex < 1 or fromIndex > InventoryConstants.HOTBAR_SLOT_COUNT then
		return false
	end
	if toIndex < 1 or toIndex > InventoryConstants.HOTBAR_SLOT_COUNT then
		return false
	end

	local fromSlot = snapshot.hotbar[fromIndex]
	local toSlot = snapshot.hotbar[toIndex]
	if not InventoryHelper.isSlotEmpty(fromSlot) and not InventoryEquipmentHelper.canPlaceInHotbar(plr, fromSlot.itemId, toIndex) then
		return false
	end
	if not InventoryHelper.isSlotEmpty(toSlot) and not InventoryEquipmentHelper.canPlaceInHotbar(plr, toSlot.itemId, fromIndex) then
		return false
	end

	swapEntries(snapshot.hotbar[fromIndex], snapshot.hotbar[toIndex])

	if wornHotbarSlot[plr] == fromIndex then
		wornHotbarSlot[plr] = toIndex
	elseif wornHotbarSlot[plr] == toIndex then
		wornHotbarSlot[plr] = fromIndex
	end

	syncPlayer(plr, snapshot)
	return true
end

function InventoryService.wearHotbar(plr: Player, hotbarIndex: number): boolean
	local snapshot = cache[plr]
	if not snapshot then
		return false
	end
	if hotbarIndex < 1 or hotbarIndex > InventoryConstants.HOTBAR_SLOT_COUNT then
		return false
	end

	local hotbarSlot = snapshot.hotbar[hotbarIndex]
	if InventoryHelper.isSlotEmpty(hotbarSlot) then
		return false
	end
	if not InventoryEquipmentHelper.canWearItem(plr, hotbarSlot.itemId, hotbarIndex) then
		return false
	end

	if wornHotbarSlot[plr] == hotbarIndex then
		wornHotbarSlot[plr] = nil
	else
		wornHotbarSlot[plr] = hotbarIndex
	end

	syncWornState(plr)
	return true
end

function InventoryService.setup(inventorySwap: RemoteEvent, inventoryEquip: RemoteEvent)
	inventorySwap.OnServerEvent:Connect(function(plr: Player, fromIndex: unknown, toIndex: unknown)
		if typeof(fromIndex) ~= "number" or typeof(toIndex) ~= "number" then
			return
		end
		InventoryService.swapSlots(plr, math.floor(fromIndex), math.floor(toIndex))
	end)

	inventoryEquip.OnServerEvent:Connect(function(plr: Player, action: unknown, indexA: unknown, indexB: unknown)
		if typeof(action) ~= "string" then
			return
		end
		if typeof(indexA) ~= "number" then
			return
		end
		local a = math.floor(indexA)
		if action == "backpack_equip" or action == "backpack_to_hotbar" then
			if typeof(indexB) ~= "number" then
				return
			end
			InventoryService.moveBackpackToHotbar(plr, a, math.floor(indexB))
		elseif action == "unequip" or action == "hotbar_to_backpack" then
			local backpackIndex = if typeof(indexB) == "number" then math.floor(indexB) else nil
			if backpackIndex == 0 then
				backpackIndex = nil
			end
			InventoryService.moveHotbarToBackpack(plr, a, backpackIndex)
		elseif action == "equip_swap" or action == "hotbar_swap" then
			if typeof(indexB) ~= "number" then
				return
			end
			InventoryService.swapHotbar(plr, a, math.floor(indexB))
		elseif action == "wear_hotbar" then
			InventoryService.wearHotbar(plr, a)
		end
	end)

	Players.PlayerAdded:Connect(function(plr)
		plr.CharacterAdded:Connect(function()
			wornHotbarSlot[plr] = nil
			syncWornState(plr)
		end)

		task.delay(1.5, function()
			if not plr.Parent or cache[plr] then
				return
			end
			cache[plr] = loadInventory(plr)
			syncPlayer(plr, cache[plr])
		end)
	end)

	Players.PlayerRemoving:Connect(function(plr)
		saveInventory(plr)
		cache[plr] = nil
		wornHotbarSlot[plr] = nil
	end)

	for _, plr in Players:GetPlayers() do
		if not cache[plr] then
			task.delay(1.5, function()
				if not plr.Parent or cache[plr] then
					return
				end
				cache[plr] = loadInventory(plr)
				syncPlayer(plr, cache[plr])
			end)
		end
	end

	game:BindToClose(function()
		for plr in pairs(cache) do
			saveInventory(plr)
		end
	end)
end

return InventoryService
