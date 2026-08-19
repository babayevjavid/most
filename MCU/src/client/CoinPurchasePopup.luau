--!strict

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ShopCatalog = require(ReplicatedStorage.Shared.ShopCatalog)

local CoinPurchasePopup = {}

local PANEL = Color3.fromRGB(14, 44, 52)
local CARD = Color3.fromRGB(18, 58, 66)
local CARD_HOVER = Color3.fromRGB(24, 72, 82)
local STROKE = Color3.fromRGB(48, 110, 118)
local GOLD = Color3.fromRGB(228, 198, 120)
local HOVER = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function addCorner(parent: GuiObject, scale: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(scale, 0)
	c.Parent = parent
end

local function addStroke(parent: GuiObject, color: Color3, thickness: number, transparency: number)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = transparency
	s.Parent = parent
end

function CoinPurchasePopup.create(parent: Instance, zIndex: number?): { toggle: (anchor: GuiObject) -> (), close: () -> () }
	local player = Players.LocalPlayer
	local layer = zIndex or 40

	local popup = Instance.new("Frame")
	popup.Name = "CoinPurchasePopup"
	popup.AnchorPoint = Vector2.new(1, 0)
	popup.Position = UDim2.fromScale(0.905, 0.07)
	popup.Size = UDim2.fromOffset(248, 196)
	popup.BackgroundColor3 = PANEL
	popup.BorderSizePixel = 0
	popup.Visible = false
	popup.ZIndex = layer
	popup.Parent = parent
	addCorner(popup, 0.04)
	addStroke(popup, STROKE, 1, 0.28)

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -16, 0, 28)
	title.Position = UDim2.fromOffset(10, 8)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.Text = "GET TOKENS"
	title.TextColor3 = Color3.fromRGB(236, 248, 250)
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = layer + 1
	title.Parent = popup

	local grid = Instance.new("Frame")
	grid.Name = "Grid"
	grid.Position = UDim2.fromOffset(10, 42)
	grid.Size = UDim2.new(1, -20, 1, -52)
	grid.BackgroundTransparency = 1
	grid.ZIndex = layer + 1
	grid.Parent = popup

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.fromOffset(108, 62)
	gridLayout.CellPadding = UDim2.fromOffset(8, 8)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = grid

	local function tryPurchase(pack: ShopCatalog.CoinPack)
		if pack.productId <= 0 then
			warn("[CoinPurchasePopup] Set Creator Dashboard dev product ID for", pack.id)
			return
		end
		MarketplaceService:PromptProductPurchase(player, pack.productId)
	end

	for i, pack in ShopCatalog.getCoinPacks() do
		local card = Instance.new("TextButton")
		card.Name = pack.id
		card.LayoutOrder = i
		card.BackgroundColor3 = CARD
		card.AutoButtonColor = false
		card.Text = ""
		card.ZIndex = layer + 2
		card.Parent = grid
		addCorner(card, 0.08)
		addStroke(card, STROKE, 1, 0.35)

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 0.55)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.Text = pack.label
		label.TextColor3 = GOLD
		label.TextScaled = true
		label.ZIndex = layer + 3
		label.Parent = card

		local price = Instance.new("TextLabel")
		price.Size = UDim2.new(1, 0, 0.38, 0)
		price.Position = UDim2.fromScale(0, 0.58)
		price.BackgroundTransparency = 1
		price.Font = Enum.Font.Gotham
		price.Text = if pack.robuxPrice and pack.robuxPrice > 0
			then string.format("R$ %d", pack.robuxPrice)
			else "Dev Product"
		price.TextColor3 = Color3.fromRGB(180, 210, 215)
		price.TextScaled = true
		price.ZIndex = layer + 3
		price.Parent = card

		card.MouseEnter:Connect(function()
			TweenService:Create(card, HOVER, { BackgroundColor3 = CARD_HOVER }):Play()
		end)
		card.MouseLeave:Connect(function()
			TweenService:Create(card, HOVER, { BackgroundColor3 = CARD }):Play()
		end)
		card.MouseButton1Click:Connect(function()
			tryPurchase(pack)
		end)
	end

	MarketplaceService.PromptProductPurchaseFinished:Connect(function(purchasedPlayer, productId, purchased)
		if purchasedPlayer ~= player or not purchased then
			return
		end
		for _, pack in ShopCatalog.getCoinPacks() do
			if pack.productId == productId then
				Remotes.getEvent("RefreshPlayerData"):FireServer()
				break
			end
		end
	end)

	local function close()
		popup.Visible = false
	end

	local function toggle(anchor: GuiObject)
		if popup.Visible then
			close()
			return
		end
		local anchorPos = anchor.AbsolutePosition
		local anchorSize = anchor.AbsoluteSize
		local parentPos = popup.Parent and (popup.Parent :: GuiObject).AbsolutePosition or Vector2.zero
		popup.Position = UDim2.fromOffset(
			anchorPos.X - parentPos.X + anchorSize.X,
			anchorPos.Y - parentPos.Y + anchorSize.Y + 6
		)
		popup.Visible = true
	end

	return {
		toggle = toggle,
		close = close,
	}
end

function CoinPurchasePopup.bind(popup: Frame): { toggle: (anchor: GuiObject) -> (), close: () -> () }
	local player = Players.LocalPlayer
	local grid = popup:FindFirstChild("Grid")
	if not grid or not grid:IsA("Frame") then
		error("[CoinPurchasePopup] Missing Grid frame")
	end

	local function tryPurchase(pack: ShopCatalog.CoinPack)
		if pack.productId <= 0 then
			warn("[CoinPurchasePopup] Set Creator Dashboard dev product ID for", pack.id)
			return
		end
		MarketplaceService:PromptProductPurchase(player, pack.productId)
	end

	for i, pack in ShopCatalog.getCoinPacks() do
		local card = grid:FindFirstChild(pack.id)
		if card and card:IsA("TextButton") then
			card.LayoutOrder = i
			card.MouseButton1Click:Connect(function()
				tryPurchase(pack)
			end)
		end
	end

	local title = popup:FindFirstChildWhichIsA("TextLabel")
	if title then
		title.Text = "GET TOKENS"
	end

	local function close()
		popup.Visible = false
	end

	local function toggle(anchor: GuiObject)
		if popup.Visible then
			close()
			return
		end
		local anchorPos = anchor.AbsolutePosition
		local anchorSize = anchor.AbsoluteSize
		local parentPos = popup.Parent and (popup.Parent :: GuiObject).AbsolutePosition or Vector2.zero
		popup.Position = UDim2.fromOffset(
			anchorPos.X - parentPos.X + anchorSize.X,
			anchorPos.Y - parentPos.Y + anchorSize.Y + 6
		)
		popup.Visible = true
	end

	return {
		toggle = toggle,
		close = close,
	}
end

return CoinPurchasePopup
