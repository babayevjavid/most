--!strict
--[[ Custom inventory UI: bottom-right equip bar + top-right backpack panel. ]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local HudConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("HudConstants"))
local InventoryConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("InventoryConstants"))
local InventoryHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("InventoryHelper"))
local UiStyle = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UiStyle"))

export type InventoryController = {
	show: () -> (),
	hide: () -> (),
	toggle: () -> (),
	destroy: () -> (),
}

local InventoryUI = {}

type SlotButtonSet = {
	buttons: { TextButton },
	selected: number?,
}

local function paintSlotButton(
	btn: TextButton,
	slot: InventoryHelper.SlotEntry,
	selected: boolean,
	worn: boolean?
)
	local stroke = btn:FindFirstChildOfClass("UIStroke")
	local qtyLabel = btn:FindFirstChild("Quantity") :: TextLabel?
	local nameLabel = btn:FindFirstChild("ItemLabel") :: TextLabel?
	local rarityStripe = btn:FindFirstChild("RarityStripe") :: Frame?

	if slot.itemId and not InventoryHelper.isSlotEmpty(slot) then
		local def = InventoryHelper.getItemDef(slot.itemId)
		btn.BackgroundColor3 = HudConstants.SURFACE_ELEVATED
		btn.BackgroundTransparency = 0
		if rarityStripe and def then
			rarityStripe.BackgroundColor3 = def.rarityColor
			rarityStripe.Visible = true
		elseif rarityStripe then
			rarityStripe.Visible = false
		end
		if nameLabel then
			nameLabel.Text = if def then def.name else slot.itemId
		end
		if qtyLabel then
			local qty = slot.quantity or 1
			qtyLabel.Text = if qty > 1 then tostring(qty) else ""
			qtyLabel.Visible = qty > 1
		end
	else
		btn.BackgroundColor3 = HudConstants.SURFACE_INSET
		btn.BackgroundTransparency = InventoryConstants.SLOT_BG_TRANSPARENCY
		if rarityStripe then
			rarityStripe.Visible = false
		end
		if nameLabel then
			nameLabel.Text = ""
		end
		if qtyLabel then
			qtyLabel.Text = ""
			qtyLabel.Visible = false
		end
	end

	if stroke then
		if worn then
			stroke.Color = HudConstants.COLOR_ACCENT
			stroke.Transparency = 0
			stroke.Thickness = 2
		elseif selected then
			stroke.Color = HudConstants.COLOR_BORDER_LIGHT
			stroke.Transparency = 0
			stroke.Thickness = 2
		else
			stroke.Color = HudConstants.COLOR_BORDER
			stroke.Transparency = 0
			stroke.Thickness = 1
		end
	end
end

local function createSlotButton(parent: Instance, index: number, size: number, hotkey: string?): TextButton
	local btn = Instance.new("TextButton")
	btn.Name = "Slot" .. index
	btn.LayoutOrder = index
	btn.Size = UDim2.fromOffset(size, size)
	btn.Text = ""
	btn.AutoButtonColor = false
	btn.BackgroundColor3 = HudConstants.SURFACE_INSET
	btn.BackgroundTransparency = InventoryConstants.SLOT_BG_TRANSPARENCY
	btn.BorderSizePixel = 0
	btn.ClipsDescendants = true
	btn.Parent = parent

	UiStyle.addCorner(btn, HudConstants.CORNER_RADIUS_SM)
	UiStyle.addStroke(btn, HudConstants.COLOR_BORDER, 1, 0)

	local rarityStripe = Instance.new("Frame")
	rarityStripe.Name = "RarityStripe"
	rarityStripe.Size = UDim2.new(0, 2, 1, -6)
	rarityStripe.Position = UDim2.fromOffset(0, 3)
	rarityStripe.BackgroundTransparency = 0
	rarityStripe.BorderSizePixel = 0
	rarityStripe.Visible = false
	rarityStripe.Parent = btn

	local itemLabel = Instance.new("TextLabel")
	itemLabel.Name = "ItemLabel"
	itemLabel.Size = UDim2.new(1, -8, 1, -6)
	itemLabel.Position = UDim2.fromOffset(6, 3)
	itemLabel.BackgroundTransparency = 1
	itemLabel.Font = HudConstants.FONT_LABEL
	itemLabel.TextSize = 9
	itemLabel.TextWrapped = true
	itemLabel.TextYAlignment = Enum.TextYAlignment.Center
	itemLabel.TextColor3 = HudConstants.COLOR_TEXT
	itemLabel.Parent = btn

	local qtyLabel = Instance.new("TextLabel")
	qtyLabel.Name = "Quantity"
	qtyLabel.AnchorPoint = Vector2.new(1, 1)
	qtyLabel.Position = UDim2.new(1, -4, 1, -2)
	qtyLabel.Size = UDim2.fromOffset(24, 14)
	qtyLabel.BackgroundTransparency = 1
	qtyLabel.Font = HudConstants.FONT_LABEL
	qtyLabel.TextSize = 10
	qtyLabel.TextXAlignment = Enum.TextXAlignment.Right
	qtyLabel.TextColor3 = HudConstants.COLOR_TEXT_SECONDARY
	qtyLabel.Visible = false
	qtyLabel.Parent = btn

	if hotkey and hotkey ~= "" then
		local keyBadge = Instance.new("TextLabel")
		keyBadge.Name = "Hotkey"
		keyBadge.AnchorPoint = Vector2.new(0, 0)
		keyBadge.Position = UDim2.fromOffset(4, 2)
		keyBadge.Size = UDim2.fromOffset(14, 14)
		keyBadge.BackgroundColor3 = HudConstants.SURFACE_ELEVATED
		keyBadge.BackgroundTransparency = 0.15
		keyBadge.BorderSizePixel = 0
		keyBadge.Font = HudConstants.FONT_KEY
		keyBadge.TextSize = 10
		keyBadge.TextColor3 = HudConstants.COLOR_TEXT_SECONDARY
		keyBadge.Text = hotkey
		keyBadge.ZIndex = 2
		keyBadge.Parent = btn
		UiStyle.addCorner(keyBadge, 4)
	end

	return btn
end

function InventoryUI.create(
	playerGui: PlayerGui,
	inventorySwap: RemoteEvent,
	inventoryEquip: RemoteEvent
): InventoryController
	local player = Players.LocalPlayer
	local open = false
	local backpackState: SlotButtonSet = { buttons = {}, selected = nil }
	local hotbarState: SlotButtonSet = { buttons = {}, selected = nil }
	local attributeConn: RBXScriptConnection? = nil
	local wornAttributeConns: { RBXScriptConnection } = {}

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "InventoryUI"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = HudConstants.TOP_BAR_DISPLAY_ORDER
	screenGui.Enabled = false
	screenGui.Parent = playerGui

	local equipBar = UiStyle.createPanel(screenGui, {
		name = "EquipBar",
		cornerRadius = HudConstants.CORNER_RADIUS_MD,
		bgTransparency = 1,
		borderless = true,
	})
	equipBar.AnchorPoint = Vector2.new(1, 1)
	equipBar.Position = UDim2.new(
		1,
		-InventoryConstants.HOTBAR_BAR_RIGHT_OFFSET,
		1,
		-InventoryConstants.HOTBAR_BAR_BOTTOM_OFFSET
	)
	equipBar.Size = UDim2.fromOffset(
		InventoryConstants.HOTBAR_SLOT_COUNT
			* (InventoryConstants.HOTBAR_SLOT_SIZE + InventoryConstants.HOTBAR_SLOT_PADDING)
			+ 16,
		InventoryConstants.HOTBAR_SLOT_SIZE + 34
	)
	UiStyle.addPadding(equipBar, 8)

	local equipTitle = Instance.new("TextLabel")
	equipTitle.Name = "Title"
	equipTitle.Size = UDim2.new(1, 0, 0, 14)
	equipTitle.BackgroundTransparency = 1
	equipTitle.Font = HudConstants.FONT_LABEL
	equipTitle.TextSize = 11
	equipTitle.TextXAlignment = Enum.TextXAlignment.Right
	equipTitle.TextColor3 = HudConstants.COLOR_TEXT_SECONDARY
	equipTitle.Text = "Hotbar"
	equipTitle.Parent = equipBar

	local equipGrid = Instance.new("Frame")
	equipGrid.Name = "EquipGrid"
	equipGrid.Position = UDim2.fromOffset(0, 18)
	equipGrid.Size = UDim2.new(1, 0, 1, -18)
	equipGrid.BackgroundTransparency = 1
	equipGrid.Parent = equipBar

	local equipLayout = Instance.new("UIListLayout")
	equipLayout.FillDirection = Enum.FillDirection.Horizontal
	equipLayout.SortOrder = Enum.SortOrder.LayoutOrder
	equipLayout.Padding = UDim.new(0, InventoryConstants.HOTBAR_SLOT_PADDING)
	equipLayout.Parent = equipGrid

	local backpackRightOffset = InventoryConstants.BACKPACK_RIGHT_MARGIN
		+ InventoryConstants.BACKPACK_SETTINGS_BUTTON_WIDTH
		+ InventoryConstants.BACKPACK_SETTINGS_GAP

	local backpackButton = Instance.new("ImageButton")
	backpackButton.Name = "BackpackButton"
	backpackButton.AnchorPoint = Vector2.new(1, 0)
	backpackButton.Position = UDim2.new(1, -backpackRightOffset, 0, InventoryConstants.BACKPACK_TOP_MARGIN)
	backpackButton.Size = UDim2.fromOffset(InventoryConstants.BACKPACK_BUTTON_SIZE, InventoryConstants.BACKPACK_BUTTON_SIZE)
	backpackButton.BackgroundColor3 = HudConstants.SURFACE_PANEL
	backpackButton.BackgroundTransparency = 1
	backpackButton.BorderSizePixel = 0
	backpackButton.Image = InventoryConstants.BACKPACK_IMAGE
	backpackButton.ScaleType = Enum.ScaleType.Fit
	backpackButton.AutoButtonColor = false
	backpackButton.Parent = screenGui

	UiStyle.addCorner(backpackButton, HudConstants.CORNER_RADIUS_MD)
	UiStyle.addStroke(backpackButton, HudConstants.COLOR_BORDER, 1, 0)

	local panel = UiStyle.createPanel(screenGui, {
		name = "InventoryPanel",
		cornerRadius = HudConstants.CORNER_RADIUS_LG,
		bgTransparency = 1,
	})
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(440, 380)
	panel.Visible = false
	panel.Parent = screenGui

	UiStyle.addPadding(panel, 14)

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 28)
	header.BackgroundTransparency = 1
	header.Parent = panel

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -36, 1, 0)
	title.BackgroundTransparency = 1
	title.Font = HudConstants.FONT_HEADING
	title.TextSize = 16
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = HudConstants.COLOR_TEXT
	title.Text = "Backpack"
	title.Parent = header

	local closeButton = Instance.new("TextButton")
	closeButton.Name = "Close"
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, 0, 0, 0)
	closeButton.Size = UDim2.fromOffset(28, 28)
	closeButton.BackgroundColor3 = HudConstants.SURFACE_ELEVATED
	closeButton.BorderSizePixel = 0
	closeButton.Font = HudConstants.FONT_LABEL
	closeButton.TextSize = 16
	closeButton.TextColor3 = HudConstants.COLOR_TEXT_SECONDARY
	closeButton.Text = "×"
	closeButton.AutoButtonColor = false
	closeButton.Parent = header
	UiStyle.addCorner(closeButton, HudConstants.CORNER_RADIUS_SM)
	UiStyle.addStroke(closeButton, HudConstants.COLOR_BORDER, 1, 0)

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.Position = UDim2.fromOffset(0, 36)
	body.Size = UDim2.new(1, 0, 1, -36)
	body.BackgroundTransparency = 1
	body.Parent = panel

	local grid = Instance.new("Frame")
	grid.Name = "Grid"
	grid.Size = UDim2.new(0, InventoryConstants.COLUMNS * (InventoryConstants.SLOT_SIZE + InventoryConstants.SLOT_PADDING), 1, -80)
	grid.BackgroundTransparency = 1
	grid.Parent = body

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.fromOffset(InventoryConstants.SLOT_SIZE, InventoryConstants.SLOT_SIZE)
	gridLayout.CellPadding = UDim2.fromOffset(InventoryConstants.SLOT_PADDING, InventoryConstants.SLOT_PADDING)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = grid

	local detail = Instance.new("Frame")
	detail.Name = "Detail"
	detail.AnchorPoint = Vector2.new(0, 1)
	detail.Position = UDim2.new(0, 0, 1, 0)
	detail.Size = UDim2.new(1, 0, 0, 72)
	detail.BackgroundColor3 = HudConstants.SURFACE_INSET
	detail.BorderSizePixel = 0
	detail.Parent = body
	UiStyle.addCorner(detail, HudConstants.CORNER_RADIUS_MD)
	UiStyle.addStroke(detail, HudConstants.COLOR_BORDER, 1, 0.35)
	UiStyle.addPadding(detail, 10)

	local detailName = Instance.new("TextLabel")
	detailName.Name = "ItemName"
	detailName.Size = UDim2.new(1, 0, 0, 18)
	detailName.BackgroundTransparency = 1
	detailName.Font = HudConstants.FONT_LABEL
	detailName.TextSize = 13
	detailName.TextXAlignment = Enum.TextXAlignment.Left
	detailName.TextColor3 = HudConstants.COLOR_TEXT
	detailName.Text = ""
	detailName.Parent = detail

	local detailDesc = Instance.new("TextLabel")
	detailDesc.Name = "ItemDescription"
	detailDesc.Position = UDim2.fromOffset(0, 20)
	detailDesc.Size = UDim2.new(1, 0, 1, -20)
	detailDesc.BackgroundTransparency = 1
	detailDesc.Font = HudConstants.FONT_BODY
	detailDesc.TextSize = 11
	detailDesc.TextWrapped = true
	detailDesc.TextYAlignment = Enum.TextYAlignment.Top
	detailDesc.TextXAlignment = Enum.TextXAlignment.Left
	detailDesc.TextColor3 = HudConstants.COLOR_TEXT_SECONDARY
	detailDesc.Text = ""
	detailDesc.Parent = detail
	detail.Visible = false

	local function clearSelections()
		backpackState.selected = nil
		hotbarState.selected = nil
	end

	local function getActiveHotbarSlot(): number?
		local character = player.Character
		if not character then
			return nil
		end
		local value = character:GetAttribute("ActiveHotbarSlot")
		if typeof(value) == "number" and value >= 1 and value <= InventoryConstants.HOTBAR_SLOT_COUNT then
			return value
		end
		return nil
	end

	local function setDetailLayoutVisible(visible: boolean)
		detail.Visible = visible
		grid.Size = if visible
			then UDim2.new(0, InventoryConstants.COLUMNS * (InventoryConstants.SLOT_SIZE + InventoryConstants.SLOT_PADDING), 1, -80)
			else UDim2.new(0, InventoryConstants.COLUMNS * (InventoryConstants.SLOT_SIZE + InventoryConstants.SLOT_PADDING), 1, 0)
	end

	local function setDetailFromSlot(slot: InventoryHelper.SlotEntry?)
		if not slot or InventoryHelper.isSlotEmpty(slot) then
			setDetailLayoutVisible(false)
			detailName.Text = ""
			detailDesc.Text = ""
			return
		end

		local def = InventoryHelper.getItemDef(slot.itemId)
		if not def then
			setDetailLayoutVisible(true)
			detailName.Text = slot.itemId
			detailDesc.Text = ""
			detailName.TextColor3 = HudConstants.COLOR_TEXT
			return
		end

		setDetailLayoutVisible(true)
		detailName.Text = string.format("%s × %d", def.name, slot.quantity or 1)
		detailDesc.Text = def.description
		detailName.TextColor3 = def.rarityColor
	end

	local function readSnapshot(): InventoryHelper.InventorySnapshot
		return InventoryHelper.decode(player:GetAttribute("InventoryData"))
	end

	local function refresh()
		local snapshot = readSnapshot()
		local activeHotbar = getActiveHotbarSlot()

		for index, btn in backpackState.buttons do
			paintSlotButton(btn, snapshot.slots[index], backpackState.selected == index, false)
		end
		for index, btn in hotbarState.buttons do
			paintSlotButton(
				btn,
				snapshot.hotbar[index],
				hotbarState.selected == index,
				activeHotbar == index
			)
		end

		if backpackState.selected then
			setDetailFromSlot(snapshot.slots[backpackState.selected])
		elseif hotbarState.selected then
			setDetailFromSlot(snapshot.hotbar[hotbarState.selected])
		else
			setDetailFromSlot(nil)
		end
	end

	local function clickHotbarSlot(index: number)
		if backpackState.selected then
			inventoryEquip:FireServer("backpack_to_hotbar", backpackState.selected, index)
			clearSelections()
			return
		end
		if hotbarState.selected then
			if hotbarState.selected == index then
				hotbarState.selected = nil
			else
				inventoryEquip:FireServer("hotbar_swap", hotbarState.selected, index)
				clearSelections()
			end
			refresh()
			return
		end
		hotbarState.selected = index
		backpackState.selected = nil
		refresh()
	end

	local function wearHotbarSlot(index: number)
		inventoryEquip:FireServer("wear_hotbar", index)
	end

	for index = 1, InventoryConstants.HOTBAR_SLOT_COUNT do
		local hotkey = InventoryConstants.HOTBAR_HOTKEYS[index]
		local btn = createSlotButton(equipGrid, index, InventoryConstants.HOTBAR_SLOT_SIZE, hotkey)
		btn.MouseButton1Click:Connect(function()
			clickHotbarSlot(index)
		end)
		table.insert(hotbarState.buttons, btn)
	end

	for index = 1, InventoryConstants.SLOT_COUNT do
		local btn = createSlotButton(grid, index, InventoryConstants.SLOT_SIZE)
		btn.MouseButton1Click:Connect(function()
			if hotbarState.selected then
				local snapshot = readSnapshot()
				local slot = snapshot.slots[index]
				if not InventoryHelper.isSlotEmpty(slot) then
					inventoryEquip:FireServer("backpack_to_hotbar", index, hotbarState.selected)
				else
					inventoryEquip:FireServer("hotbar_to_backpack", hotbarState.selected, index)
				end
				clearSelections()
				return
			end
			if backpackState.selected == nil then
				backpackState.selected = index
				hotbarState.selected = nil
				refresh()
				return
			end
			if backpackState.selected == index then
				backpackState.selected = nil
				refresh()
				return
			end
			inventorySwap:FireServer(backpackState.selected, index)
			clearSelections()
		end)
		table.insert(backpackState.buttons, btn)
	end

	local function setPanelVisible(visible: boolean)
		open = visible
		panel.Visible = visible
		if visible then
			refresh()
		else
			if not hotbarState.selected then
				backpackState.selected = nil
			end
		end
	end

	local function toggle()
		setPanelVisible(not open)
	end

	backpackButton.MouseButton1Click:Connect(toggle)
	closeButton.MouseButton1Click:Connect(function()
		setPanelVisible(false)
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not screenGui.Enabled then
			return
		end
		local slotIndex: number? = nil
		if input.KeyCode == Enum.KeyCode.One then
			slotIndex = 1
		elseif input.KeyCode == Enum.KeyCode.Two then
			slotIndex = 2
		elseif input.KeyCode == Enum.KeyCode.Three then
			slotIndex = 3
		end
		if slotIndex then
			wearHotbarSlot(slotIndex)
			return
		end
		if not open then
			return
		end
		if input.KeyCode == Enum.KeyCode.B or input.KeyCode == Enum.KeyCode.Backspace then
			setPanelVisible(false)
		end
	end)

	local function show()
		screenGui.Enabled = true
		refresh()
	end

	local function hide()
		setPanelVisible(false)
		clearSelections()
		screenGui.Enabled = false
	end

	local function destroy()
		if attributeConn then
			attributeConn:Disconnect()
		end
		for _, conn in wornAttributeConns do
			conn:Disconnect()
		end
		table.clear(wornAttributeConns)
		screenGui:Destroy()
	end

	attributeConn = player:GetAttributeChangedSignal("InventoryData"):Connect(function()
		refresh()
	end)

	local function bindWornAttributes(character: Model)
		for _, conn in wornAttributeConns do
			conn:Disconnect()
		end
		table.clear(wornAttributeConns)
		table.insert(
			wornAttributeConns,
			character:GetAttributeChangedSignal("ActiveHotbarSlot"):Connect(refresh)
		)
		table.insert(
			wornAttributeConns,
			character:GetAttributeChangedSignal("WornItemId"):Connect(refresh)
		)
	end

	player.CharacterAdded:Connect(bindWornAttributes)
	if player.Character then
		bindWornAttributes(player.Character)
	end

	return {
		show = show,
		hide = hide,
		toggle = toggle,
		destroy = destroy,
	}
end

return InventoryUI
