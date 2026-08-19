--!strict
--[[
	Top screen UI: cluster bar (settings/codes/coins) on top, level/XP row below. Scale-only layout.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local HudConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("HudConstants"))

export type TopBarController = {
	screenGui: ScreenGui,
	show: () -> (),
	hide: () -> (),
	destroy: () -> (),
}

local function tween(inst: Instance, props: { [string]: any }, duration: number?)
	TweenService:Create(
		inst,
		TweenInfo.new(duration or HudConstants.UI_TWEEN_DURATION, HudConstants.UI_EASING_STYLE, HudConstants.UI_EASING_DIRECTION),
		props
	):Play()
end

local function formatNumber(n: number): string
	local s = tostring(math.floor(n + 0.5))
	local out = ""
	local count = 0
	for i = #s, 1, -1 do
		count += 1
		out = s:sub(i, i) .. out
		if count % 3 == 0 and i > 1 then
			out = "," .. out
		end
	end
	return out
end

local TopBarHUD = {}

function TopBarHUD.create(playerGui: PlayerGui, redeemCodeRemote: RemoteEvent?): TopBarController
	local player = Players.LocalPlayer

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "TopBarHUD"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = HudConstants.TOP_BAR_DISPLAY_ORDER
	screenGui.Enabled = false
	screenGui.Parent = playerGui

	local root = Instance.new("Frame")
	root.Name = "TopBarRoot"
	root.Position = UDim2.fromScale(0, 0)
	root.Size = UDim2.new(1, 0, HudConstants.TOP_BAR_HEIGHT_SCALE, 0)
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Parent = screenGui

	local clusterBar = Instance.new("Frame")
	clusterBar.Name = "ClusterBar"
	clusterBar.Position = UDim2.fromScale(0, 0)
	clusterBar.Size = UDim2.new(1, 0, HudConstants.TOP_BAR_CLUSTER_SHARE, 0)
	clusterBar.BackgroundColor3 = HudConstants.COLOR_PANEL_BG
	clusterBar.BackgroundTransparency = 0.35
	clusterBar.BorderSizePixel = 0
	clusterBar.Parent = root

	local clusterStroke = Instance.new("UIStroke")
	clusterStroke.Color = HudConstants.COLOR_STROKE
	clusterStroke.Thickness = 1
	clusterStroke.Transparency = 0.55
	clusterStroke.Parent = clusterBar

	local clusterPadding = Instance.new("UIPadding")
	clusterPadding.PaddingLeft = UDim.new(HudConstants.TOP_BAR_PADDING_X_SCALE, 0)
	clusterPadding.PaddingRight = UDim.new(HudConstants.TOP_BAR_PADDING_X_SCALE, 0)
	clusterPadding.PaddingTop = UDim.new(HudConstants.TOP_BAR_PADDING_Y_SCALE, 0)
	clusterPadding.PaddingBottom = UDim.new(HudConstants.TOP_BAR_PADDING_Y_SCALE, 0)
	clusterPadding.Parent = clusterBar

	local menuCluster = Instance.new("Frame")
	menuCluster.Name = "MenuCluster"
	menuCluster.AnchorPoint = Vector2.new(0.5, 0.5)
	menuCluster.Position = UDim2.fromScale(0.5, 0.5)
	menuCluster.Size = UDim2.new(HudConstants.TOP_BAR_MENU_WIDTH_SCALE, 0, HudConstants.TOP_BAR_MENU_HEIGHT_SCALE, 0)
	menuCluster.BackgroundTransparency = 1
	menuCluster.Parent = clusterBar

	local menuLayout = Instance.new("UIListLayout")
	menuLayout.FillDirection = Enum.FillDirection.Horizontal
	menuLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	menuLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	menuLayout.Padding = UDim.new(0.04, 0)
	menuLayout.Parent = menuCluster

	local function createMenuButton(name: string, label: string, layoutOrder: number): TextButton
		local btn = Instance.new("TextButton")
		btn.Name = name
		btn.LayoutOrder = layoutOrder
		btn.Size = UDim2.new(HudConstants.TOP_BAR_BUTTON_WIDTH_SHARE, 0, 1, 0)
		btn.BackgroundColor3 = HudConstants.COLOR_PANEL_FRAME
		btn.BackgroundTransparency = 0.25
		btn.BorderSizePixel = 0
		btn.AutoButtonColor = false
		btn.Font = Enum.Font.GothamBold
		btn.Text = label
		btn.TextColor3 = HudConstants.COLOR_TEXT
		btn.TextScaled = true
		btn.Parent = menuCluster

		local textLimit = Instance.new("UITextSizeConstraint")
		textLimit.MaxTextSize = 11
		textLimit.MinTextSize = 8
		textLimit.Parent = btn

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.15, 0)
		corner.Parent = btn

		local stroke = Instance.new("UIStroke")
		stroke.Color = HudConstants.COLOR_STROKE
		stroke.Thickness = 1
		stroke.Transparency = 0.45
		stroke.Parent = btn

		btn.MouseEnter:Connect(function()
			tween(btn, { BackgroundTransparency = 0.08 })
		end)
		btn.MouseLeave:Connect(function()
			tween(btn, { BackgroundTransparency = 0.25 })
		end)

		return btn
	end

	local settingsBtn = createMenuButton("SettingsButton", "Set", 1)
	local codesBtn = createMenuButton("CodesButton", "Code", 2)

	local coinsCluster = Instance.new("Frame")
	coinsCluster.Name = "CoinsCluster"
	coinsCluster.AnchorPoint = Vector2.new(1, 0.5)
	coinsCluster.Position = UDim2.fromScale(1, 0.5)
	coinsCluster.Size = UDim2.new(HudConstants.TOP_BAR_COINS_WIDTH_SCALE, 0, HudConstants.TOP_BAR_COINS_HEIGHT_SCALE, 0)
	coinsCluster.BackgroundColor3 = HudConstants.COLOR_PANEL_FRAME
	coinsCluster.BackgroundTransparency = 0.2
	coinsCluster.BorderSizePixel = 0
	coinsCluster.Parent = clusterBar

	local coinsPadding = Instance.new("UIPadding")
	coinsPadding.PaddingLeft = UDim.new(0.08, 0)
	coinsPadding.PaddingRight = UDim.new(0.08, 0)
	coinsPadding.Parent = coinsCluster

	local coinsLayout = Instance.new("UIListLayout")
	coinsLayout.FillDirection = Enum.FillDirection.Horizontal
	coinsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	coinsLayout.Padding = UDim.new(0.05, 0)
	coinsLayout.Parent = coinsCluster

	local coinsIcon = Instance.new("TextLabel")
	coinsIcon.Name = "Icon"
	coinsIcon.Size = UDim2.new(0.2, 0, 0.8, 0)
	coinsIcon.BackgroundTransparency = 1
	coinsIcon.Font = Enum.Font.GothamBold
	coinsIcon.Text = "C"
	coinsIcon.TextColor3 = Color3.fromRGB(255, 210, 80)
	coinsIcon.TextScaled = true
	coinsIcon.Parent = coinsCluster

	local coinsIconLimit = Instance.new("UITextSizeConstraint")
	coinsIconLimit.MaxTextSize = 14
	coinsIconLimit.MinTextSize = 10
	coinsIconLimit.Parent = coinsIcon

	local coinsLabel = Instance.new("TextLabel")
	coinsLabel.Name = "Amount"
	coinsLabel.Size = UDim2.new(0.8, 0, 0.8, 0)
	coinsLabel.BackgroundTransparency = 1
	coinsLabel.Font = Enum.Font.GothamBold
	coinsLabel.Text = "0"
	coinsLabel.TextColor3 = HudConstants.COLOR_TEXT
	coinsLabel.TextScaled = true
	coinsLabel.TextXAlignment = Enum.TextXAlignment.Left
	coinsLabel.Parent = coinsCluster

	local coinsLabelLimit = Instance.new("UITextSizeConstraint")
	coinsLabelLimit.MaxTextSize = 14
	coinsLabelLimit.MinTextSize = 10
	coinsLabelLimit.Parent = coinsLabel

	local coinsCorner = Instance.new("UICorner")
	coinsCorner.CornerRadius = UDim.new(0.15, 0)
	coinsCorner.Parent = coinsCluster

	local xpRow = Instance.new("Frame")
	xpRow.Name = "XpRow"
	xpRow.Position = UDim2.fromScale(0, HudConstants.TOP_BAR_CLUSTER_SHARE)
	xpRow.Size = UDim2.new(1, 0, HudConstants.TOP_BAR_XP_ROW_SHARE, 0)
	xpRow.BackgroundColor3 = HudConstants.COLOR_PANEL_BG
	xpRow.BackgroundTransparency = 0.42
	xpRow.BorderSizePixel = 0
	xpRow.Parent = root

	local xpRowStroke = Instance.new("UIStroke")
	xpRowStroke.Color = HudConstants.COLOR_STROKE
	xpRowStroke.Thickness = 1
	xpRowStroke.Transparency = 0.62
	xpRowStroke.Parent = xpRow

	local xpPadding = Instance.new("UIPadding")
	xpPadding.PaddingLeft = UDim.new(HudConstants.TOP_BAR_PADDING_X_SCALE, 0)
	xpPadding.PaddingRight = UDim.new(HudConstants.TOP_BAR_PADDING_X_SCALE, 0)
	xpPadding.PaddingTop = UDim.new(0.1, 0)
	xpPadding.PaddingBottom = UDim.new(0.1, 0)
	xpPadding.Parent = xpRow

	local levelBadge = Instance.new("TextLabel")
	levelBadge.Name = "LevelBadge"
	levelBadge.AnchorPoint = Vector2.new(0, 0.5)
	levelBadge.Position = UDim2.fromScale(0, 0.5)
	levelBadge.Size = UDim2.new(HudConstants.TOP_BAR_LEVEL_WIDTH_SCALE, 0, HudConstants.TOP_BAR_LEVEL_HEIGHT_SCALE, 0)
	levelBadge.BackgroundColor3 = HudConstants.COLOR_PRIMARY
	levelBadge.BackgroundTransparency = 0.12
	levelBadge.Font = Enum.Font.GothamBold
	levelBadge.Text = "Lv 1"
	levelBadge.TextColor3 = Color3.new(1, 1, 1)
	levelBadge.TextScaled = true
	levelBadge.Parent = xpRow

	local levelTextLimit = Instance.new("UITextSizeConstraint")
	levelTextLimit.MaxTextSize = 12
	levelTextLimit.MinTextSize = 9
	levelTextLimit.Parent = levelBadge

	local levelCorner = Instance.new("UICorner")
	levelCorner.CornerRadius = UDim.new(0.15, 0)
	levelCorner.Parent = levelBadge

	local xpBlock = Instance.new("Frame")
	xpBlock.Name = "XpBlock"
	xpBlock.Position = UDim2.fromScale(HudConstants.TOP_BAR_XP_BLOCK_X_SCALE, 0)
	xpBlock.Size = UDim2.new(HudConstants.TOP_BAR_XP_BLOCK_WIDTH_SCALE, 0, 1, 0)
	xpBlock.BackgroundTransparency = 1
	xpBlock.Parent = xpRow

	local xpLabel = Instance.new("TextLabel")
	xpLabel.Name = "XpLabel"
	xpLabel.Size = UDim2.new(1, 0, HudConstants.TOP_BAR_XP_LABEL_HEIGHT_SCALE, 0)
	xpLabel.BackgroundTransparency = 1
	xpLabel.Font = Enum.Font.GothamMedium
	xpLabel.Text = "0 / 450 XP"
	xpLabel.TextColor3 = HudConstants.COLOR_TEXT_MUTED
	xpLabel.TextScaled = true
	xpLabel.TextXAlignment = Enum.TextXAlignment.Left
	xpLabel.Parent = xpBlock

	local xpLabelLimit = Instance.new("UITextSizeConstraint")
	xpLabelLimit.MaxTextSize = 10
	xpLabelLimit.MinTextSize = 8
	xpLabelLimit.Parent = xpLabel

	local xpBg = Instance.new("Frame")
	xpBg.Name = "XpBg"
	xpBg.Position = UDim2.fromScale(0, HudConstants.TOP_BAR_XP_BAR_Y_SCALE)
	xpBg.Size = UDim2.new(1, 0, HudConstants.TOP_BAR_XP_BAR_HEIGHT_SCALE, 0)
	xpBg.BackgroundColor3 = HudConstants.COLOR_BAR_BG
	xpBg.BorderSizePixel = 0
	xpBg.Parent = xpBlock

	local xpBgCorner = Instance.new("UICorner")
	xpBgCorner.CornerRadius = UDim.new(0.2, 0)
	xpBgCorner.Parent = xpBg

	local xpFill = Instance.new("Frame")
	xpFill.Name = "XpFill"
	xpFill.Size = UDim2.fromScale(0, 1)
	xpFill.BackgroundColor3 = HudConstants.COLOR_PRIMARY
	xpFill.BorderSizePixel = 0
	xpFill.Parent = xpBg

	local xpFillCorner = Instance.new("UICorner")
	xpFillCorner.CornerRadius = UDim.new(0.2, 0)
	xpFillCorner.Parent = xpFill

	local xpGradient = Instance.new("UIGradient")
	xpGradient.Color = ColorSequence.new(HudConstants.COLOR_PRIMARY, HudConstants.COLOR_SECONDARY)
	xpGradient.Parent = xpFill

	local modal = Instance.new("Frame")
	modal.Name = "Modal"
	modal.Size = UDim2.fromScale(1, 1)
	modal.BackgroundTransparency = 1
	modal.Visible = false
	modal.ZIndex = 20
	modal.Parent = screenGui

	local modalBackdrop = Instance.new("TextButton")
	modalBackdrop.Name = "Backdrop"
	modalBackdrop.Size = UDim2.fromScale(1, 1)
	modalBackdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	modalBackdrop.BackgroundTransparency = 0.45
	modalBackdrop.BorderSizePixel = 0
	modalBackdrop.AutoButtonColor = false
	modalBackdrop.Text = ""
	modalBackdrop.ZIndex = 20
	modalBackdrop.Parent = modal

	local modalPanel = Instance.new("Frame")
	modalPanel.Name = "Panel"
	modalPanel.AnchorPoint = Vector2.new(0.5, 0.5)
	modalPanel.Position = UDim2.fromScale(0.5, 0.5)
	modalPanel.Size = UDim2.fromScale(0.32, 0.28)
	modalPanel.BackgroundColor3 = HudConstants.COLOR_PANEL_BG
	modalPanel.BorderSizePixel = 0
	modalPanel.ZIndex = 21
	modalPanel.Parent = modal

	local modalCorner = Instance.new("UICorner")
	modalCorner.CornerRadius = UDim.new(0.04, 0)
	modalCorner.Parent = modalPanel

	local modalTitle = Instance.new("TextLabel")
	modalTitle.Name = "Title"
	modalTitle.Size = UDim2.new(0.92, 0, 0.18, 0)
	modalTitle.Position = UDim2.fromScale(0.04, 0.06)
	modalTitle.BackgroundTransparency = 1
	modalTitle.Font = Enum.Font.GothamBold
	modalTitle.Text = "Settings"
	modalTitle.TextColor3 = HudConstants.COLOR_TEXT
	modalTitle.TextScaled = true
	modalTitle.TextXAlignment = Enum.TextXAlignment.Left
	modalTitle.ZIndex = 22
	modalTitle.Parent = modalPanel

	local modalBody = Instance.new("TextLabel")
	modalBody.Name = "Body"
	modalBody.Size = UDim2.new(0.92, 0, 0.38, 0)
	modalBody.Position = UDim2.fromScale(0.04, 0.28)
	modalBody.BackgroundTransparency = 1
	modalBody.Font = Enum.Font.Gotham
	modalBody.Text = ""
	modalBody.TextColor3 = HudConstants.COLOR_TEXT_MUTED
	modalBody.TextScaled = true
	modalBody.TextWrapped = true
	modalBody.TextXAlignment = Enum.TextXAlignment.Left
	modalBody.TextYAlignment = Enum.TextYAlignment.Top
	modalBody.ZIndex = 22
	modalBody.Parent = modalPanel

	local codeInput = Instance.new("TextBox")
	codeInput.Name = "CodeInput"
	codeInput.Size = UDim2.new(0.92, 0, 0.18, 0)
	codeInput.Position = UDim2.fromScale(0.04, 0.28)
	codeInput.BackgroundColor3 = HudConstants.COLOR_PANEL_FRAME
	codeInput.BackgroundTransparency = 0.15
	codeInput.BorderSizePixel = 0
	codeInput.Font = Enum.Font.Gotham
	codeInput.PlaceholderText = "Enter code..."
	codeInput.Text = ""
	codeInput.TextColor3 = HudConstants.COLOR_TEXT
	codeInput.TextScaled = true
	codeInput.Visible = false
	codeInput.ClearTextOnFocus = false
	codeInput.ZIndex = 22
	codeInput.Parent = modalPanel

	local codeInputCorner = Instance.new("UICorner")
	codeInputCorner.CornerRadius = UDim.new(0.12, 0)
	codeInputCorner.Parent = codeInput

	local codeStatus = Instance.new("TextLabel")
	codeStatus.Name = "CodeStatus"
	codeStatus.Size = UDim2.new(0.92, 0, 0.12, 0)
	codeStatus.Position = UDim2.fromScale(0.04, 0.5)
	codeStatus.BackgroundTransparency = 1
	codeStatus.Font = Enum.Font.Gotham
	codeStatus.Text = ""
	codeStatus.TextColor3 = HudConstants.COLOR_TEXT_MUTED
	codeStatus.TextScaled = true
	codeStatus.TextXAlignment = Enum.TextXAlignment.Left
	codeStatus.Visible = false
	codeStatus.ZIndex = 22
	codeStatus.Parent = modalPanel

	local modalClose = Instance.new("TextButton")
	modalClose.Name = "Close"
	modalClose.AnchorPoint = Vector2.new(0.5, 1)
	modalClose.Position = UDim2.fromScale(0.5, 0.94)
	modalClose.Size = UDim2.new(0.34, 0, 0.16, 0)
	modalClose.BackgroundColor3 = HudConstants.COLOR_PRIMARY
	modalClose.BackgroundTransparency = 0.1
	modalClose.BorderSizePixel = 0
	modalClose.Font = Enum.Font.GothamBold
	modalClose.Text = "Close"
	modalClose.TextColor3 = Color3.new(1, 1, 1)
	modalClose.TextScaled = true
	modalClose.ZIndex = 22
	modalClose.Parent = modalPanel

	local modalCloseCorner = Instance.new("UICorner")
	modalCloseCorner.CornerRadius = UDim.new(0.15, 0)
	modalCloseCorner.Parent = modalClose

	local attributeConns: { RBXScriptConnection } = {}

	local function syncProgression()
		local level = player:GetAttribute("Level")
		local xp = player:GetAttribute("XP")
		local xpMax = player:GetAttribute("XpToNextLevel")
		local coins = player:GetAttribute("Coins")

		local lvl = if typeof(level) == "number" then math.floor(level) else 1
		local currentXp = if typeof(xp) == "number" then math.max(0, math.floor(xp)) else 0
		local maxXp = if typeof(xpMax) == "number" then math.max(1, math.floor(xpMax)) else 450
		local coinAmt = if typeof(coins) == "number" then math.max(0, math.floor(coins)) else 0

		levelBadge.Text = "Lv " .. tostring(lvl)
		xpLabel.Text = string.format("%s / %s XP", formatNumber(currentXp), formatNumber(maxXp))
		coinsLabel.Text = formatNumber(coinAmt)
		tween(xpFill, { Size = UDim2.fromScale(math.clamp(currentXp / maxXp, 0, 1), 1) }, HudConstants.BAR_TWEEN_DURATION)
	end

	local function closeModal()
		modal.Visible = false
		codeInput.Visible = false
		codeStatus.Visible = false
		modalBody.Visible = true
		codeInput.Text = ""
		codeStatus.Text = ""
	end

	local function openSettingsModal()
		modalTitle.Text = "Settings"
		modalBody.Visible = true
		modalBody.Text = "Audio, controls, and graphics options are coming soon."
		codeInput.Visible = false
		codeStatus.Visible = false
		modalPanel.Size = UDim2.fromScale(0.32, 0.24)
		modal.Visible = true
	end

	local function openCodesModal()
		modalTitle.Text = "Redeem Code"
		modalBody.Visible = false
		codeInput.Visible = true
		codeStatus.Visible = true
		codeStatus.Text = ""
		modalPanel.Size = UDim2.fromScale(0.32, 0.28)
		modal.Visible = true
		codeInput:CaptureFocus()
	end

	settingsBtn.MouseButton1Click:Connect(openSettingsModal)
	codesBtn.MouseButton1Click:Connect(openCodesModal)
	modalClose.MouseButton1Click:Connect(closeModal)
	modalBackdrop.MouseButton1Click:Connect(closeModal)

	codeInput.FocusLost:Connect(function(enterPressed)
		if not enterPressed or not redeemCodeRemote then
			return
		end
		local text = codeInput.Text
		if text ~= "" then
			redeemCodeRemote:FireServer(text)
		end
	end)

	if redeemCodeRemote then
		redeemCodeRemote.OnClientEvent:Connect(function(ok: boolean, message: string)
			codeStatus.Text = message
			codeStatus.TextColor3 = if ok then HudConstants.COLOR_HP else Color3.fromRGB(255, 120, 120)
			if ok then
				codeInput.Text = ""
			end
		end)
	end

	local function bindPlayerAttributes()
		for _, conn in attributeConns do
			conn:Disconnect()
		end
		table.clear(attributeConns)

		syncProgression()
		for _, attr in { "Level", "XP", "XpToNextLevel", "Coins" } do
			table.insert(attributeConns, player:GetAttributeChangedSignal(attr):Connect(syncProgression))
		end
	end

	bindPlayerAttributes()

	local function show()
		screenGui.Enabled = true
		syncProgression()
	end

	local function hide()
		screenGui.Enabled = false
		closeModal()
	end

	local function destroy()
		for _, conn in attributeConns do
			conn:Disconnect()
		end
		screenGui:Destroy()
	end

	return {
		screenGui = screenGui,
		show = show,
		hide = hide,
		destroy = destroy,
	}
end

return TopBarHUD
