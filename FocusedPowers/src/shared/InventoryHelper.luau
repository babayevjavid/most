--!strict
--[[
	Encode/decode inventory slot data for replication.
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InventoryConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("InventoryConstants"))

export type SlotEntry = {
	itemId: string?,
	quantity: number?,
}

export type InventorySnapshot = {
	slots: { SlotEntry },
	hotbar: { SlotEntry },
}

local InventoryHelper = {}

local HOTBAR_KEY = "__hotbar"
local HOTBAR_LEGACY_KEY = "__equipped"

local function isSlotEmpty(slot: SlotEntry): boolean
	return not slot.itemId or not slot.quantity or slot.quantity <= 0
end

local function createSlotEntries(count: number): { SlotEntry }
	local entries: { SlotEntry } = {}
	for i = 1, count do
		entries[i] = { itemId = nil, quantity = nil }
	end
	return entries
end

function InventoryHelper.isSlotEmpty(slot: SlotEntry): boolean
	return isSlotEmpty(slot)
end

function InventoryHelper.createEmpty(): InventorySnapshot
	return {
		slots = createSlotEntries(InventoryConstants.SLOT_COUNT),
		hotbar = createSlotEntries(InventoryConstants.HOTBAR_SLOT_COUNT),
	}
end

function InventoryHelper.getItemDef(itemId: string?): InventoryConstants.ItemDefinition?
	if typeof(itemId) ~= "string" or itemId == "" then
		return nil
	end
	return InventoryConstants.ITEMS[itemId]
end

function InventoryHelper.applyStarterItems(snapshot: InventorySnapshot): InventorySnapshot
	local function hasItem(itemId: string): boolean
		for _, slot in snapshot.slots do
			if slot.itemId == itemId then
				return true
			end
		end
		for _, slot in snapshot.hotbar do
			if slot.itemId == itemId then
				return true
			end
		end
		return false
	end

	local nextEmpty = 1
	for _, starter in InventoryConstants.STARTER_ITEMS do
		if hasItem(starter.itemId) then
			continue
		end
		while nextEmpty <= InventoryConstants.SLOT_COUNT do
			local slot = snapshot.slots[nextEmpty]
			if isSlotEmpty(slot) then
				slot.itemId = starter.itemId
				slot.quantity = starter.quantity
				nextEmpty += 1
				break
			end
			nextEmpty += 1
		end
	end
	return snapshot
end

local function decodeHotbarPayload(snapshot: InventorySnapshot, entry: any)
	if typeof(entry) ~= "table" then
		return
	end
	for hotbarKey, hotbarEntry in entry do
		local hotbarIndex = tonumber(hotbarKey)
		if
			hotbarIndex
			and hotbarIndex >= 1
			and hotbarIndex <= InventoryConstants.HOTBAR_SLOT_COUNT
			and typeof(hotbarEntry) == "table"
		then
			local itemId = hotbarEntry.id
			local quantity = hotbarEntry.q
			if typeof(itemId) == "string" and typeof(quantity) == "number" and quantity > 0 then
				snapshot.hotbar[hotbarIndex] = { itemId = itemId, quantity = math.floor(quantity) }
			end
		end
	end
end

function InventoryHelper.encode(snapshot: InventorySnapshot): string
	local payload: { [string]: any } = {}
	for index, slot in snapshot.slots do
		if not isSlotEmpty(slot) then
			payload[tostring(index)] = { id = slot.itemId, q = slot.quantity }
		end
	end

	local hotbarPayload: { [string]: { id: string, q: number } } = {}
	for index, slot in snapshot.hotbar do
		if not isSlotEmpty(slot) then
			hotbarPayload[tostring(index)] = { id = slot.itemId :: string, q = slot.quantity :: number }
		end
	end
	if next(hotbarPayload) ~= nil then
		payload[HOTBAR_KEY] = hotbarPayload
	end

	return HttpService:JSONEncode(payload)
end

function InventoryHelper.decode(raw: unknown): InventorySnapshot
	local snapshot = InventoryHelper.createEmpty()
	if typeof(raw) ~= "string" or raw == "" then
		return snapshot
	end

	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(raw)
	end)
	if not ok or typeof(decoded) ~= "table" then
		return snapshot
	end

	for key, entry in decoded do
		if key == HOTBAR_KEY or key == HOTBAR_LEGACY_KEY then
			decodeHotbarPayload(snapshot, entry)
			continue
		end

		local index = tonumber(key)
		if index and index >= 1 and index <= InventoryConstants.SLOT_COUNT and typeof(entry) == "table" then
			local itemId = entry.id
			local quantity = entry.q
			if typeof(itemId) == "string" and typeof(quantity) == "number" and quantity > 0 then
				snapshot.slots[index] = { itemId = itemId, quantity = math.floor(quantity) }
			end
		end
	end

	return snapshot
end

function InventoryHelper.clone(snapshot: InventorySnapshot): InventorySnapshot
	local copy = InventoryHelper.createEmpty()
	for index, slot in snapshot.slots do
		copy.slots[index] = { itemId = slot.itemId, quantity = slot.quantity }
	end
	for index, slot in snapshot.hotbar do
		copy.hotbar[index] = { itemId = slot.itemId, quantity = slot.quantity }
	end
	return copy
end

return InventoryHelper
