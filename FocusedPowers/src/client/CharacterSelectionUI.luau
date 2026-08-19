--!strict
--[[ CharacterSelectionUI: left roster picker + right hero detail pane. ]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CharacterConfig"))
local HudConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("HudConstants"))
local ViewportHelper = require(script.Parent:WaitForChild("ViewportHelper"))

type CharacterEntry = CharacterConfig.CharacterEntry

export type SelectionController = {
	screenGui: ScreenGui,
	show: () -> (),
	hide: () -> (),
	destroy: () -> (),
}

export type CreateOptions = {
	playerGui: PlayerGui,
	onCharacterSelected: (characterId: string) -> (),
}

local DETAIL_FADE_DURATION = 0.22

local function tween(inst: Instance, props: { [string]: any }, duration: number?)
	TweenService:Create(
		inst,
		TweenInfo.new(duration or HudConstants.UI_TWEEN_DURATION, HudConstants.UI_EASING_STYLE, HudConstants.UI_EASING_DIRECTION),
		props
	):Play()
end

local CharacterSelectionUI = {}

function CharacterSelectionUI.create(options: CreateOptions): SelectionController
	local player = Players.LocalPlayer
	local roster = CharacterConfig.getRoster()
	local cardCount = #roster
	local currentIndex = 1
	local selecting = false
	local scrollTween: Tween? = nil
	local cardByIndex: { [number]: { card: TextButton, stroke: UIStroke } } = {}

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "CharacterSelection"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = HudConstants.SELECTION_DISPLAY_ORDER
	screenGui.Enabled = false
	screenGui.Parent = options.playerGui

	local overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = HudConstants.SURFACE_BACKDROP
	overlay.BackgroundTransparency = HudConstants.SELECTION_OVERLAY_TRANSPARENCY
	overlay.BorderSizePixel = 0
	overlay.Parent = screenGui

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(HudConstants.SELECTION_PANEL_WIDTH_SCALE, HudConstants.SELECTION_PANEL_HEIGHT_SCALE)
	panel.BackgroundColor3 = HudConstants.SURFACE_PANEL
	panel.BackgroundTransparency = HudConstants.SELECTION_PANEL_BG_TRANSPARENCY
	panel.BorderSizePixel = 0
	panel.Parent = screenGui

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, HudConstants.SELECTION_PANEL_CORNER_RADIUS)
	panelCorner.Parent = panel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = HudConstants.COLOR_BORDER
	panelStroke.Thickness = 1
	panelStroke.Transparency = 0.25
	panelStroke.Parent = panel

	local panelPadding = Instance.new("UIPadding")
	panelPadding.PaddingTop = UDim.new(0, 18)
	panelPadding.PaddingBottom = UDim.new(0, 18)
	panelPadding.PaddingLeft = UDim.new(0, 18)
	panelPadding.PaddingRight = UDim.new(0, 18)
	panelPadding.Parent = panel

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 32)
	title.BackgroundTransparency = 1
	title.Font = HudConstants.FONT_HEADING
	title.Text = "Choose Your Hero"
	title.TextColor3 = HudConstants.COLOR_TEXT
	title.TextSize = 24
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = panel

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.Position = UDim2.fromOffset(0, 40)
	body.Size = UDim2.new(1, 0, 1, -40)
	body.BackgroundTransparency = 1
	body.Parent = panel

	local bodyLayout = Instance.new("UIListLayout")
	bodyLayout.FillDirection = Enum.FillDirection.Horizontal
	bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
	bodyLayout.Padding = UDim.new(0, 14)
	bodyLayout.Parent = body

	-- Left picker
	local pickerColumn = Instance.new("Frame")
	pickerColumn.Name = "PickerColumn"
	pickerColumn.LayoutOrder = 1
	pickerColumn.Size = UDim2.new(HudConstants.SELECTION_PICKER_WIDTH_SCALE, -7, 1, 0)
	pickerColumn.BackgroundTransparency = 1
	pickerColumn.Parent = body

	local pickerBg = Instance.new("Frame")
	pickerBg.Name = "PickerBg"
	pickerBg.Size = UDim2.fromScale(1, 1)
	pickerBg.BackgroundColor3 = HudConstants.SURFACE_INSET
	pickerBg.BackgroundTransparency = 0.35
	pickerBg.BorderSizePixel = 0
	pickerBg.Parent = pickerColumn

	local pickerBgCorner = Instance.new("UICorner")
	pickerBgCorner.CornerRadius = UDim.new(0, HudConstants.CORNER_RADIUS_MD)
	pickerBgCorner.Parent = pickerBg

	local pickerList = Instance.new("Frame")
	pickerList.Name = "PickerList"
	pickerList.Size = UDim2.new(1, -12, 1, -28)
	pickerList.Position = UDim2.fromOffset(6, 6)
	pickerList.BackgroundTransparency = 1
	pickerList.Parent = pickerColumn

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "CharacterList"
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.ScrollBarImageColor3 = HudConstants.COLOR_BORDER
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ElasticBehavior = Enum.ElasticBehavior.Never
	scroll.ClipsDescendants = true
	scroll.Parent = pickerList

	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Vertical
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, HudConstants.SELECTION_PICKER_ROW_PADDING)
	listLayout.Parent = scroll

	local listPadding = Instance.new("UIPadding")
	listPadding.PaddingLeft = UDim.new(0, 4)
	listPadding.PaddingRight = UDim.new(0, 4)
	listPadding.PaddingTop = UDim.new(0, 4)
	listPadding.PaddingBottom = UDim.new(0, 4)
	listPadding.Parent = scroll

	local pageIndicator = Instance.new("TextLabel")
	pageIndicator.Name = "PageIndicator"
	pageIndicator.AnchorPoint = Vector2.new(0.5, 1)
	pageIndicator.Position = UDim2.new(0.5, 0, 1, -8)
	pageIndicator.Size = UDim2.new(1, -12, 0, 16)
	pageIndicator.BackgroundTransparency = 1
	pageIndicator.Font = HudConstants.FONT_BODY
	pageIndicator.TextColor3 = HudConstants.COLOR_TEXT_SECONDARY
	pageIndicator.TextSize = 12
	pageIndicator.Visible = cardCount > 0
	pageIndicator.Parent = pickerColumn

	-- Right detail pane
	local detailColumn = Instance.new("Frame")
	detailColumn.Name = "DetailColumn"
	detailColumn.LayoutOrder = 2
	detailColumn.Size = UDim2.new(HudConstants.SELECTION_DETAIL_WIDTH_SCALE, -7, 1, 0)
	detailColumn.BackgroundTransparency = 1
	detailColumn.ClipsDescendants = true
	detailColumn.Parent = body

	local detailPane = Instance.new("CanvasGroup")
	detailPane.Name = "DetailPane"
	detailPane.Size = UDim2.fromScale(1, 1)
	detailPane.BackgroundColor3 = HudConstants.SURFACE_INSET
	detailPane.BackgroundTransparency = 0.35
	detailPane.BorderSizePixel = 0
	detailPane.GroupTransparency = 0
	detailPane.Parent = detailColumn

	local detailCorner = Instance.new("UICorner")
	detailCorner.CornerRadius = UDim.new(0, HudConstants.CORNER_RADIUS_MD)
	detailCorner.Parent = detailPane

	local detailStroke = Instance.new("UIStroke")
	detailStroke.Color = HudConstants.COLOR_BORDER
	detailStroke.Thickness = 1.5
	detailStroke.Transparency = 0.2
	detailStroke.Parent = detailPane

	local detailPadding = Instance.new("UIPadding")
	detailPadding.PaddingTop = UDim.new(0, 14)
	detailPadding.PaddingBottom = UDim.new(0, 14)
	detailPadding.PaddingLeft = UDim.new(0, 14)
	detailPadding.PaddingRight = UDim.new(0, 14)
	detailPadding.Parent = detailPane

	local detailViewport = Instance.new("ViewportFrame")
	detailViewport.Name = "HeroViewport"
	detailViewport.Position = UDim2.fromOffset(0, 0)
	detailViewport.Size = UDim2.fromOffset(HudConstants.SELECTION_DETAIL_VIEWPORT_SIZE, HudConstants.SELECTION_DETAIL_VIEWPORT_SIZE)
	detailViewport.BackgroundColor3 = HudConstants.SURFACE_ELEVATED
	detailViewport.BackgroundTransparency = 0
	detailViewport.BorderSizePixel = 0
	detailViewport.Parent = detailPane
	ViewportHelper.applyCircularMask(detailViewport)

	local detailName = Instance.new("TextLabel")
	detailName.Name = "HeroName"
	detailName.Position = UDim2.fromOffset(HudConstants.SELECTION_DETAIL_VIEWPORT_SIZE + 14, 0)
	detailName.Size = UDim2.new(1, -(HudConstants.SELECTION_DETAIL_VIEWPORT_SIZE + 14), 0, 28)
	detailName.BackgroundTransparency = 1
	detailName.Font = HudConstants.FONT_HEADING
	detailName.Text = ""
	detailName.TextColor3 = HudConstants.COLOR_TEXT
	detailName.TextSize = 22
	detailName.TextXAlignment = Enum.TextXAlignment.Left
	detailName.TextTruncate = Enum.TextTruncate.AtEnd
	detailName.Parent = detailPane

	local detailSubtitle = Instance.new("TextLabel")
	detailSubtitle.Name = "HeroSubtitle"
	detailSubtitle.Position = UDim2.fromOffset(HudConstants.SELECTION_DETAIL_VIEWPORT_SIZE + 14, 30)
	detailSubtitle.Size = UDim2.new(1, -(HudConstants.SELECTION_DETAIL_VIEWPORT_SIZE + 14), 0, 20)
	detailSubtitle.BackgroundTransparency = 1
	detailSubtitle.Font = HudConstants.FONT_BODY
	detailSubtitle.Text = ""
	detailSubtitle.TextColor3 = HudConstants.COLOR_TEXT_SECONDARY
	detailSubtitle.TextSize = 14
	detailSubtitle.TextXAlignment = Enum.TextXAlignment.Left
	detailSubtitle.Parent = detailPane

	local detailBio = Instance.new("TextLabel")
	detailBio.Name = "HeroBio"
	detailBio.Position = UDim2.fromOffset(0, HudConstants.SELECTION_DETAIL_VIEWPORT_SIZE + 10)
	detailBio.Size = UDim2.new(1, 0, 1, -(HudConstants.SELECTION_DETAIL_VIEWPORT_SIZE + 10 + HudConstants.SELECTION_DEPLOY_BUTTON_H + 16))
	detailBio.BackgroundTransparency = 1
	detailBio.Font = HudConstants.FONT_BODY
	detailBio.Text = ""
	detailBio.TextColor3 = HudConstants.COLOR_TEXT_SECONDARY
	detailBio.TextSize = 13
	detailBio.TextWrapped = true
	detailBio.TextXAlignment = Enum.TextXAlignment.Left
	detailBio.TextYAlignment = Enum.TextYAlignment.Top
	detailBio.Parent = detailPane

	local deployBtn = Instance.new("TextButton")
	deployBtn.Name = "DeployButton"
	deployBtn.AnchorPoint = Vector2.new(0.5, 1)
	deployBtn.Position = UDim2.new(0.5, 0, 1, 0)
	deployBtn.Size = UDim2.new(1, 0, 0, HudConstants.SELECTION_DEPLOY_BUTTON_H)
	deployBtn.BackgroundColor3 = HudConstants.SELECTION_DEPLOY_BG
	deployBtn.BackgroundTransparency = 0.08
	deployBtn.BorderSizePixel = 0
	deployBtn.AutoButtonColor = false
	deployBtn.Font = HudConstants.FONT_LABEL
	deployBtn.Text = "Deploy"
	deployBtn.TextColor3 = HudConstants.COLOR_TEXT_SECONDARY
	deployBtn.TextSize = 15
	deployBtn.TextStrokeTransparency = 1
	deployBtn.Parent = detailPane

	local deployCorner = Instance.new("UICorner")
	deployCorner.CornerRadius = UDim.new(0, HudConstants.CORNER_RADIUS_MD)
	deployCorner.Parent = deployBtn

	local deployStroke = Instance.new("UIStroke")
	deployStroke.Color = HudConstants.COLOR_BORDER
	deployStroke.Thickness = 1
	deployStroke.Transparency = 0.35
	deployStroke.Parent = deployBtn

	local function cardStep(): number
		return HudConstants.SELECTION_PICKER_ROW_HEIGHT + HudConstants.SELECTION_PICKER_ROW_PADDING
	end

	local function updatePageIndicator()
		local entry = roster[currentIndex]
		local label = if entry then (entry.displayName or entry.id) else "?"
		pageIndicator.Text = string.format("%s  ·  %d / %d", label, currentIndex, cardCount)
	end

	local function highlightCard(index: number)
		for i, data in cardByIndex do
			local selected = i == index
			local entry = roster[i]
			local locked = entry and entry.locked == true
			local accent = if entry and not locked then entry.accentColor else HudConstants.COLOR_BORDER
			tween(data.stroke, {
				Transparency = if selected then 0.05 else 0.45,
				Color = if selected then accent else HudConstants.COLOR_BORDER,
			}, 0.12)
			tween(data.card, {
				BackgroundTransparency = if selected then 0.04 else if locked then 0.45 else 0.14,
			}, 0.12)
		end
	end

	local function updateDetail(index: number, animated: boolean)
		local entry = roster[index]
		if not entry then
			return
		end

		local locked = entry.locked == true
		local accent = if locked then HudConstants.COLOR_LOCKED else entry.accentColor

		local function applyContent()
			detailName.Text = entry.displayName or entry.id
			detailSubtitle.Text = entry.subtitle or ""
			detailSubtitle.TextColor3 = accent
			detailBio.Text = entry.bio or ""
			detailStroke.Color = accent
			deployBtn.Text = if locked then "Locked" else "Deploy"
			deployBtn.Active = not locked
			deployBtn.AutoButtonColor = false
			deployBtn.BackgroundTransparency = if locked then 0.55 else 0.12
			deployBtn.TextTransparency = if locked then 0.35 else 0
			deployBtn.TextColor3 = if locked
				then HudConstants.COLOR_TEXT_TERTIARY
				else HudConstants.COLOR_TEXT_SECONDARY

			ViewportHelper.setupAvatarViewport(detailViewport, player, { characterId = entry.id })
			highlightCard(index)
		end

		if animated then
			tween(detailPane, { GroupTransparency = 1, Position = UDim2.fromScale(0.02, 0) }, DETAIL_FADE_DURATION * 0.5)
			task.delay(DETAIL_FADE_DURATION * 0.45, function()
				if not detailPane.Parent then
					return
				end
				applyContent()
				detailPane.Position = UDim2.fromScale(-0.02, 0)
				tween(detailPane, { GroupTransparency = 0, Position = UDim2.fromScale(0, 0) }, DETAIL_FADE_DURATION)
			end)
		else
			applyContent()
			detailPane.GroupTransparency = 0
			detailPane.Position = UDim2.fromScale(0, 0)
		end
	end

	local function scrollToIndex(index: number, animated: boolean)
		currentIndex = math.clamp(index, 1, math.max(cardCount, 1))
		local targetY = (currentIndex - 1) * cardStep()

		if scrollTween then
			scrollTween:Cancel()
			scrollTween = nil
		end

		if animated then
			local tw = TweenService:Create(
				scroll,
				TweenInfo.new(
					HudConstants.SELECTION_CAROUSEL_SCROLL_DURATION,
					HudConstants.UI_EASING_STYLE,
					HudConstants.UI_EASING_DIRECTION
				),
				{ CanvasPosition = Vector2.new(0, targetY) }
			)
			scrollTween = tw
			tw:Play()
		else
			scroll.CanvasPosition = Vector2.new(0, targetY)
		end

		updatePageIndicator()
		updateDetail(currentIndex, animated)
	end

	local function selectIndex(index: number, animated: boolean)
		scrollToIndex(index, animated)
	end

	local function createCard(entry: CharacterEntry, layoutOrder: number)
		local locked = entry.locked == true
		local accent = if locked then HudConstants.COLOR_LOCKED else entry.accentColor
		local rowHeight = HudConstants.SELECTION_PICKER_ROW_HEIGHT
		local viewportSize = HudConstants.SELECTION_PICKER_ROW_VIEWPORT

		local card = Instance.new("TextButton")
		card.Name = entry.id
		card.LayoutOrder = layoutOrder
		card.Size = UDim2.new(1, -8, 0, rowHeight)
		card.BackgroundColor3 = HudConstants.SURFACE_ELEVATED
		card.BackgroundTransparency = if locked then 0.45 else 0.14
		card.BorderSizePixel = 0
		card.AutoButtonColor = false
		card.Text = ""
		card.Parent = scroll

		local cardCorner = Instance.new("UICorner")
		cardCorner.CornerRadius = UDim.new(0, 8)
		cardCorner.Parent = card

		local cardStroke = Instance.new("UIStroke")
		cardStroke.Color = HudConstants.COLOR_BORDER
		cardStroke.Thickness = 1.5
		cardStroke.Transparency = 0.45
		cardStroke.Parent = card

		cardByIndex[layoutOrder] = { card = card, stroke = cardStroke }

		local viewport = Instance.new("ViewportFrame")
		viewport.Name = "AvatarViewport"
		viewport.Position = UDim2.fromOffset(8, (rowHeight - viewportSize) * 0.5)
		viewport.Size = UDim2.fromOffset(viewportSize, viewportSize)
		viewport.BackgroundColor3 = HudConstants.SURFACE_ELEVATED
		viewport.BackgroundTransparency = if locked then 0.5 else 0
		viewport.BorderSizePixel = 0
		viewport.Parent = card
		ViewportHelper.applyCircularMask(viewport)

		if not locked then
			ViewportHelper.setupAvatarViewport(viewport, player, { characterId = entry.id })
		else
			local lockIcon = Instance.new("TextLabel")
			lockIcon.Size = UDim2.fromScale(1, 1)
			lockIcon.BackgroundTransparency = 1
			lockIcon.Font = HudConstants.FONT_HEADING
			lockIcon.Text = "?"
			lockIcon.TextColor3 = HudConstants.COLOR_TEXT_TERTIARY
			lockIcon.TextSize = 18
			lockIcon.Parent = viewport
		end

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Position = UDim2.fromOffset(viewportSize + 16, 10)
		nameLabel.Size = UDim2.new(1, -(viewportSize + 24), 0, 20)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = HudConstants.FONT_LABEL
		nameLabel.Text = entry.displayName or entry.id
		nameLabel.TextColor3 = if locked then HudConstants.COLOR_TEXT_SECONDARY else HudConstants.COLOR_TEXT
		nameLabel.TextSize = 14
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		nameLabel.Parent = card

		local tagLabel = Instance.new("TextLabel")
		tagLabel.Position = UDim2.fromOffset(viewportSize + 16, 32)
		tagLabel.Size = UDim2.new(1, -(viewportSize + 24), 0, 18)
		tagLabel.BackgroundTransparency = 1
		tagLabel.Font = HudConstants.FONT_BODY
		tagLabel.Text = if locked then "Locked" else (entry.subtitle or "")
		tagLabel.TextColor3 = if locked then HudConstants.COLOR_LOCKED else accent
		tagLabel.TextSize = 12
		tagLabel.TextXAlignment = Enum.TextXAlignment.Left
		tagLabel.TextTruncate = Enum.TextTruncate.AtEnd
		tagLabel.Parent = card

		card.MouseButton1Click:Connect(function()
			selectIndex(layoutOrder, true)
		end)
	end

	for index, entry in ipairs(roster) do
		createCard(entry, index)
	end

	deployBtn.MouseButton1Click:Connect(function()
		if selecting then
			return
		end
		local entry = roster[currentIndex]
		if not entry or entry.locked then
			return
		end
		selecting = true
		tween(deployBtn, { BackgroundTransparency = 0.08 })
		task.defer(function()
			options.onCharacterSelected(entry.id)
		end)
	end)

	if cardCount > 0 then
		selectIndex(1, false)
	end

	local function show()
		screenGui.Enabled = true
		selecting = false
		selectIndex(1, false)
	end

	local function hide()
		screenGui.Enabled = false
		selecting = false
	end

	local function destroy()
		if scrollTween then
			scrollTween:Cancel()
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

return CharacterSelectionUI
