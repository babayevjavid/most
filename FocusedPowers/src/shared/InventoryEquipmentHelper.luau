--!strict
--[[ Equipped item rules and world attachment helpers. ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InventoryHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("InventoryHelper"))

local InventoryEquipmentHelper = {}

InventoryEquipmentHelper.WORN_ITEM_ATTRIBUTE = "WornItemId"
InventoryEquipmentHelper.ACTIVE_HOTBAR_ATTRIBUTE = "ActiveHotbarSlot"

local RIGHT_ARM_NAMES: { [string]: boolean } = {
	RightHand = true,
	RightLowerArm = true,
	RightUpperArm = true,
	["Right Arm"] = true,
}

function InventoryEquipmentHelper.canPlaceInHotbar(player: Player, itemId: string?, hotbarSlot: number): boolean
	if typeof(itemId) ~= "string" or itemId == "" then
		return false
	end
	local def = InventoryHelper.getItemDef(itemId)
	if not def then
		return true
	end
	if def.characterId and player:GetAttribute("SelectedCharacter") ~= def.characterId then
		return false
	end
	if def.equipSlot and def.equipSlot ~= hotbarSlot then
		return false
	end
	return true
end

function InventoryEquipmentHelper.canWearItem(player: Player, itemId: string?, hotbarSlot: number): boolean
	return InventoryEquipmentHelper.canPlaceInHotbar(player, itemId, hotbarSlot)
end

function InventoryEquipmentHelper.findRightArmPart(character: Model): BasePart?
	for name in RIGHT_ARM_NAMES do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			return part
		end
	end
	return nil
end

local function weldModelToPart(model: Model, attachPart: BasePart, offset: CFrame)
	local primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if not primary then
		return
	end
	model.PrimaryPart = primary
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Massless = true
		end
	end
	model:PivotTo(attachPart.CFrame * offset)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = attachPart
	weld.Part1 = primary
	weld.Parent = primary
end

local function buildProceduralKatana(): Model
	local model = Instance.new("Model")
	model.Name = "Katana"

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.16, 0.16, 1.05)
	handle.Color = Color3.fromRGB(28, 22, 18)
	handle.Material = Enum.Material.Fabric
	handle.Parent = model

	local guard = Instance.new("Part")
	guard.Name = "Guard"
	guard.Size = Vector3.new(0.62, 0.1, 0.62)
	guard.Color = Color3.fromRGB(55, 55, 58)
	guard.Material = Enum.Material.Metal
	guard.Parent = model
	guard.CFrame = handle.CFrame * CFrame.new(0, 0, -0.58)

	local blade = Instance.new("Part")
	blade.Name = "Blade"
	blade.Size = Vector3.new(0.08, 0.34, 3.2)
	blade.Color = Color3.fromRGB(210, 214, 220)
	blade.Material = Enum.Material.Metal
	blade.Parent = model
	blade.CFrame = handle.CFrame * CFrame.new(0, 0, -2.4)

	for _, part in { guard, blade } do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = part
		weld.Parent = handle
	end

	model.PrimaryPart = handle
	return model
end

local function findKatanaTemplate(): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		return nil
	end
	local psylocke = assets:FindFirstChild("Psylocke")
	local fromPsylocke = if psylocke then psylocke:FindFirstChild("Katana") else nil
	if fromPsylocke then
		return fromPsylocke
	end
	local weapons = assets:FindFirstChild("Weapons")
	local fromWeapons = if weapons then weapons:FindFirstChild("Katana") else nil
	if fromWeapons then
		return fromWeapons
	end
	return assets:FindFirstChild("Katana")
end

function InventoryEquipmentHelper.createKatanaModel(): Model
	local template = findKatanaTemplate()
	if template and template:IsA("Model") then
		return template:Clone()
	end
	if template and template:IsA("BasePart") then
		local wrapper = Instance.new("Model")
		wrapper.Name = "Katana"
		local clone = template:Clone()
		clone.Parent = wrapper
		wrapper.PrimaryPart = clone
		return wrapper
	end
	return buildProceduralKatana()
end

function InventoryEquipmentHelper.attachKatanaToCharacter(character: Model)
	local arm = InventoryEquipmentHelper.findRightArmPart(character)
	if not arm then
		return
	end
	local folder = character:FindFirstChild("EquippedVisuals")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "EquippedVisuals"
		folder.Parent = character
	end
	if folder:FindFirstChild("Katana") then
		return
	end

	local katana = InventoryEquipmentHelper.createKatanaModel()
	katana.Name = "Katana"
	katana.Parent = folder
	weldModelToPart(
		katana,
		arm,
		CFrame.new(0, -0.45, -0.15) * CFrame.Angles(math.rad(-100), math.rad(90), 0)
	)
end

function InventoryEquipmentHelper.syncCharacterVisuals(character: Model, player: Player?)
	local folder = character:FindFirstChild("EquippedVisuals")
	if folder then
		for _, child in folder:GetChildren() do
			child:Destroy()
		end
	else
		folder = Instance.new("Folder")
		folder.Name = "EquippedVisuals"
		folder.Parent = character
	end

	local wornItemId = character:GetAttribute(InventoryEquipmentHelper.WORN_ITEM_ATTRIBUTE)
	if typeof(wornItemId) ~= "string" or wornItemId == "" then
		return
	end

	local activeSlot = character:GetAttribute(InventoryEquipmentHelper.ACTIVE_HOTBAR_ATTRIBUTE)
	local hotbarSlot = if typeof(activeSlot) == "number" then activeSlot else 0
	if player and not InventoryEquipmentHelper.canWearItem(player, wornItemId, hotbarSlot) then
		return
	end

	if wornItemId == "psylocke_katana" then
		InventoryEquipmentHelper.attachKatanaToCharacter(character)
	end
end

return InventoryEquipmentHelper
