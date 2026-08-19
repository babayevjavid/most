--!strict

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local CharacterRegistry = require(ReplicatedStorage.Shared.CharacterRegistry)
local PlayerDataClient = require(script.Parent.PlayerDataClient)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ShopCatalog = require(ReplicatedStorage.Shared.ShopCatalog)
local ViewportHelper = require(script.Parent.ViewportHelper)

export type ShopPage = {
	page: Frame,
	refresh: () -> (),
}

local ShopUI = {}

local BG = Color3.fromRGB(8, 28, 34)
local PANEL = Color3.fromRGB(14, 44, 52)
local CARD = Color3.fromRGB(18, 58, 66)
local CARD_HOVER = Color3.fromRGB(24, 72, 82)
local STROKE = Color3.fromRGB(48, 110, 118)
local GOLD = Color3.fromRGB(228, 198, 120)
local OWNED = Color3.fromRGB(52, 128, 88)

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
	return s
end

local function wireShopPage(page: Frame, scroll: ScrollingFrame, coinLabel: TextLabel): () -> ()
	local player = Players.LocalPlayer
	local cards: { GuiObject } = {}

	local function refreshCoins()
		coinLabel.Text = string.format("%s Tokens", tostring(PlayerDataClient.getCoins()))
	end

	local function tryRobuxPurchase(item: any)
		if item.gamepassId and item.gamepassId > 0 then
			MarketplaceService:PromptGamePassPurchase(player, item.gamepassId)
			return
		end
		if item.productId and item.productId > 0 then
			MarketplaceService:PromptProductPurchase(player, item.productId)
		end
	end

	local function purchaseItem(item: any)
		if PlayerDataClient.ownsShopItem(item.id) then
			return
		end
		if item.currency == "coins" then
			Remotes.getEvent("PurchaseShopItem"):FireServer(item.id)
		else
			tryRobuxPurchase(item)
		end
	end

	local function ensureShopSections(): (Frame, Frame)
		local grid = scroll:FindFirstChildWhichIsA("UIGridLayout")
		if grid then
			grid:Destroy()
		end
		local list = scroll:FindFirstChild("SectionList")
		if not list or not list:IsA("UIListLayout") then
			if list then
				list:Destroy()
			end
			local layout = Instance.new("UIListLayout")
			layout.Name = "SectionList"
			layout.FillDirection = Enum.FillDirection.Vertical
			layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
			layout.SortOrder = Enum.SortOrder.LayoutOrder
			layout.Padding = UDim.new(0, 8)
			layout.Parent = scroll
		end

		local function makeGridHost(name: string, order: number): Frame
			local existing = scroll:FindFirstChild(name)
			if existing and existing:IsA("Frame") then
				return existing
			end
			local host = Instance.new("Frame")
			host.Name = name
			host.LayoutOrder = order
			host.BackgroundTransparency = 1
			host.Size = UDim2.new(1, 0, 0, 0)
			host.AutomaticSize = Enum.AutomaticSize.Y
			host.ZIndex = 3
			host.Parent = scroll
			local gridLayout = Instance.new("UIGridLayout")
			gridLayout.CellSize = UDim2.fromOffset(158, 196)
			gridLayout.CellPadding = UDim2.fromOffset(10, 10)
			gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
			gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
			gridLayout.Parent = host
			return host
		end

		local function makeSectionHeader(name: string, text: string, order: number): Frame
			local existing = scroll:FindFirstChild(name)
			if existing and existing:IsA("Frame") then
				return existing
			end
			if existing then
				existing:Destroy()
			end
			local row = Instance.new("Frame")
			row.Name = name
			row.LayoutOrder = order
			row.Size = UDim2.new(1, -16, 0, 32)
			row.BackgroundTransparency = 1
			row.ZIndex = 4
			row.Parent = scroll

			local line = Instance.new("Frame")
			line.AnchorPoint = Vector2.new(0.5, 0.5)
			line.Position = UDim2.fromScale(0.5, 0.5)
			line.Size = UDim2.new(0.92, 0, 0, 2)
			line.BackgroundColor3 = GOLD
			line.BackgroundTransparency = 0.35
			line.BorderSizePixel = 0
			line.ZIndex = 4
			line.Parent = row

			local label = Instance.new("TextLabel")
			label.AnchorPoint = Vector2.new(0.5, 0.5)
			label.Position = UDim2.fromScale(0.5, 0.5)
			label.Size = UDim2.fromOffset(110, 22)
			label.BackgroundColor3 = PANEL
			label.BorderSizePixel = 0
			label.Font = Enum.Font.GothamBold
			label.Text = text
			label.TextColor3 = GOLD
			label.TextScaled = true
			label.ZIndex = 5
			label.Parent = row
			addCorner(label, 0.2)
			return row
		end

		makeSectionHeader("TokensDivider", "TOKENS", 0)
		local coinHost = makeGridHost("CoinItems", 1)
		makeSectionHeader("CurrencyDivider", "ROBUX", 2)
		local robuxHost = makeGridHost("RobuxItems", 3)
		return coinHost, robuxHost
	end

	local function buildCards()
		for _, card in cards do
			card:Destroy()
		end
		table.clear(cards)

		local coinHost, robuxHost = ensureShopSections()
		for _, child in coinHost:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		for _, child in robuxHost:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end

		local coinOrder = 0
		local robuxOrder = 0
		for _, item in ShopCatalog.getItems() do
			local owned = PlayerDataClient.ownsShopItem(item.id)
			local isRobux = item.currency == "robux"
			if isRobux then
				robuxOrder += 1
			else
				coinOrder += 1
			end

			local card = Instance.new("TextButton")
			card.Name = item.id
			card.LayoutOrder = if isRobux then robuxOrder else coinOrder
			card.BackgroundColor3 = CARD
			card.AutoButtonColor = false
			card.Text = ""
			card.ZIndex = 4
			card.Parent = if isRobux then robuxHost else coinHost
			addCorner(card, 0.04)
			local cardStroke = addStroke(card, STROKE, 1, 0.35)
			table.insert(cards, card)

			local nameLabel = Instance.new("TextLabel")
			nameLabel.Size = UDim2.new(1, -12, 0, 22)
			nameLabel.Position = UDim2.fromOffset(6, 6)
			nameLabel.BackgroundTransparency = 1
			nameLabel.Font = Enum.Font.GothamBold
			nameLabel.Text = string.upper(item.name)
			nameLabel.TextColor3 = Color3.fromRGB(236, 246, 248)
			nameLabel.TextScaled = true
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.ZIndex = 5
			nameLabel.Parent = card

			local vpWrap = Instance.new("Frame")
			vpWrap.Name = "Preview"
			vpWrap.AnchorPoint = Vector2.new(0.5, 0.5)
			vpWrap.Position = UDim2.fromScale(0.5, 0.48)
			vpWrap.Size = UDim2.fromOffset(92, 92)
			vpWrap.BackgroundColor3 = Color3.fromRGB(10, 30, 36)
			vpWrap.BorderSizePixel = 0
			vpWrap.ZIndex = 5
			vpWrap.Parent = card
			addCorner(vpWrap, 1)
			addStroke(vpWrap, STROKE, 1, 0.4)

			local vp = Instance.new("ViewportFrame")
			vp.Size = UDim2.fromScale(0.9, 0.9)
			vp.Position = UDim2.fromScale(0.05, 0.05)
			vp.BackgroundTransparency = 1
			vp.BorderSizePixel = 0
			vp.ZIndex = 6
			vp.Parent = vpWrap
			addCorner(vp, 1)

			local heroId, skinId = ShopCatalog.getPreviewMorph(item.id)
			if heroId then
				local template = CharacterRegistry.getMorphTemplate(heroId, skinId or "base")
				if template then
					ViewportHelper.bindTemplate(vp, template, 0, "select")
				end
			end

			local priceLabel = Instance.new("TextLabel")
			priceLabel.AnchorPoint = Vector2.new(0.5, 1)
			priceLabel.Position = UDim2.new(0.5, 0, 1, -6)
			priceLabel.Size = UDim2.new(1, -12, 0, 20)
			priceLabel.BackgroundTransparency = 1
			priceLabel.Font = Enum.Font.GothamBold
			priceLabel.Text = if owned
				then "OWNED"
				else (if item.currency == "coins"
					then string.format("%d Tokens", item.price)
					else string.format("R$ %d", item.price))
			priceLabel.TextColor3 = if owned then OWNED else (if item.currency == "coins" then GOLD else Color3.fromRGB(130, 190, 255))
			priceLabel.TextScaled = true
			priceLabel.ZIndex = 5
			priceLabel.Parent = card

			if owned then
				card.BackgroundColor3 = Color3.fromRGB(16, 48, 42)
				cardStroke.Color = OWNED
				card.Active = false
			else
				card.MouseEnter:Connect(function()
					TweenService:Create(card, HOVER, { BackgroundColor3 = CARD_HOVER }):Play()
				end)
				card.MouseLeave:Connect(function()
					TweenService:Create(card, HOVER, { BackgroundColor3 = CARD }):Play()
				end)
				card.MouseButton1Click:Connect(function()
					purchaseItem(item)
				end)
			end
		end
		refreshCoins()
	end

	Remotes.getEvent("ShopPurchaseResult").OnClientEvent:Connect(function(result: any)
		if type(result) == "table" and result.success == true then
			buildCards()
		end
	end)

	PlayerDataClient.onChanged(function()
		if page.Visible then
			buildCards()
		end
	end)

	local passIds = {
		ShopCatalog.ELITE_GAMEPASS_ID,
		ShopCatalog.PHOENIX_GAMEPASS_ID,
		ShopCatalog.ROGUE_GAMEPASS_ID,
	}
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(_player, gamepassId, wasPurchased)
		if not wasPurchased then
			return
		end
		for _, id in passIds do
			if id > 0 and gamepassId == id then
				Remotes.getEvent("RefreshPlayerData"):FireServer()
				break
			end
		end
	end)

	return buildCards
end

function ShopUI.bindPage(page: Frame): ShopPage
	local panel = page:WaitForChild("ShopPanel") :: Frame
	local header = panel:WaitForChild("Header") :: Frame
	local coinLabel = header:FindFirstChild("Tokens") or header:FindFirstChild("Coins")
	if not coinLabel or not coinLabel:IsA("TextLabel") then
		error("[ShopUI] Shop header missing Tokens label")
	end
	coinLabel.Name = "Tokens"
	local scroll = panel:WaitForChild("Items") :: ScrollingFrame
	return {
		page = page,
		refresh = wireShopPage(page, scroll, coinLabel),
	}
end

function ShopUI.createPage(parent: Instance): ShopPage
	local _player = Players.LocalPlayer

	local page = Instance.new("Frame")
	page.Name = "ShopPage"
	page.Size = UDim2.fromScale(1, 1)
	page.BackgroundTransparency = 1
	page.Visible = false
	page.ZIndex = 2
	page.Parent = parent

	local panel = Instance.new("Frame")
	panel.Name = "ShopPanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.82, 0.72)
	panel.BackgroundColor3 = PANEL
	panel.BorderSizePixel = 0
	panel.ZIndex = 2
	panel.Parent = page
	addCorner(panel, 0.02)
	addStroke(panel, STROKE, 1, 0.3)

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 44)
	header.BackgroundTransparency = 1
	header.ZIndex = 3
	header.Parent = panel

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(0.34, 0, 1, 0)
	title.Position = UDim2.fromOffset(18, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.Text = "SHOP"
	title.TextColor3 = Color3.fromRGB(236, 248, 250)
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 3
	title.Parent = header

	local coinLabel = Instance.new("TextLabel")
	coinLabel.Name = "Tokens"
	coinLabel.AnchorPoint = Vector2.new(1, 0.5)
	coinLabel.Position = UDim2.new(1, -18, 0.5, 0)
	coinLabel.Size = UDim2.fromOffset(200, 32)
	coinLabel.BackgroundTransparency = 1
	coinLabel.Font = Enum.Font.GothamBold
	coinLabel.Text = "0 Tokens"
	coinLabel.TextColor3 = GOLD
	coinLabel.TextScaled = true
	coinLabel.TextXAlignment = Enum.TextXAlignment.Right
	coinLabel.ZIndex = 3
	coinLabel.Parent = header

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Items"
	scroll.Position = UDim2.fromOffset(12, 52)
	scroll.Size = UDim2.new(1, -24, 1, -64)
	scroll.BackgroundColor3 = BG
	scroll.BackgroundTransparency = 0.15
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 5
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ZIndex = 3
	scroll.Parent = panel
	addCorner(scroll, 0.015)

	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(158, 196)
	grid.CellPadding = UDim2.fromOffset(10, 10)
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = scroll

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 12)
	pad.PaddingBottom = UDim.new(0, 12)
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.Parent = scroll

	return {
		page = page,
		refresh = wireShopPage(page, scroll, coinLabel),
	}
end

-- Legacy overlay API (unused by menu navigation)
function ShopUI.create(parent: Instance)
	local shopPage = ShopUI.createPage(parent)
	return {
		show = function()
			shopPage.refresh()
			shopPage.page.Visible = true
		end,
		hide = function()
			shopPage.page.Visible = false
		end,
		toggle = function()
			if shopPage.page.Visible then
				shopPage.page.Visible = false
			else
				shopPage.refresh()
				shopPage.page.Visible = true
			end
		end,
		destroy = function()
			shopPage.page:Destroy()
		end,
	}
end

return ShopUI
