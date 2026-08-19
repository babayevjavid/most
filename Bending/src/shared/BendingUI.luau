-- Bending HUD + element pick on each respawn. Layout uses scale (UDim) wherever Roblox allows.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

local PALETTE = {
	bg = Color3.fromRGB(14, 13, 18),
	panel = Color3.fromRGB(26, 24, 32),
	panelEdge = Color3.fromRGB(42, 38, 50),
	ink = Color3.fromRGB(248, 242, 232),
	inkMuted = Color3.fromRGB(190, 182, 172),
	accent = Color3.fromRGB(196, 154, 88),
	health = Color3.fromRGB(72, 210, 128),
	healthTrack = Color3.fromRGB(16, 52, 32),
	chi = Color3.fromRGB(72, 188, 228),
	chiTrack = Color3.fromRGB(18, 42, 52),
	hudBacking = Color3.fromRGB(12, 11, 16),
}

local ELEMENTS = {
	{ id = "water", label = "Water", hue = Color3.fromRGB(62, 136, 168) },
	{ id = "earth", label = "Earth", hue = Color3.fromRGB(122, 98, 62) },
	{ id = "fire", label = "Fire", hue = Color3.fromRGB(196, 86, 54) },
	{ id = "air", label = "Air", hue = Color3.fromRGB(188, 204, 220) },
}

-- Subbendings per element (display labels stored on `BendingSub`).
local SUBBENDINGS: { [string]: { { id: string, label: string } } } = {
	water = {
		{ id = "plant", label = "Plantbending" },
		{ id = "blood", label = "Bloodbending" },
		{ id = "healing", label = "Healing" },
		{ id = "spirit", label = "Spiritbending" },
	},
	earth = {
		{ id = "lava", label = "Lava" },
		{ id = "metal", label = "Metal" },
		{ id = "sand", label = "Sand" },
		{ id = "crystal", label = "Crystal" },
		{ id = "seismic", label = "Seismic Sense" },
	},
	fire = {
		{ id = "combustion", label = "Combustion" },
		{ id = "lightning", label = "Lightning" },
		{ id = "flame_divination", label = "Flame Divination" },
	},
	air = {
		{ id = "flight", label = "Flight" },
		{ id = "sound", label = "Sound" },
		{ id = "projection", label = "Projection" },
	},
}

-- Four combat slots per element (keys `1`–`4`). Subbending does not swap these yet — see ABILITIES.md.
local ABILITIES_BY_ELEMENT: { [string]: { { name: string, key: string } } } = {
	water = {
		{ name = "Brine Surge", key = "1" },
		{ name = "Rimebolt", key = "2" },
		{ name = "Glacier Path", key = "3" },
		{ name = "Tidemend", key = "4" },
	},
	earth = {
		{ name = "Spike Chain", key = "1" },
		{ name = "Shardspire", key = "2" },
		{ name = "Catapult Root", key = "3" },
		{ name = "Faultbreaker", key = "4" },
	},
	fire = {
		{ name = "Inferno Lash", key = "1" },
		{ name = "Dragon's Inhale", key = "2" },
		{ name = "Afterburn Drive", key = "3" },
		{ name = "Cinder Sigil", key = "4" },
	},
	air = {
		{ name = "Galefang", key = "1" },
		{ name = "Shearline", key = "2" },
		{ name = "Nimbus Drift", key = "3" },
		{ name = "Skybreak Column", key = "4" },
	},
}

local SLOT_COUNT = 4
local SLOT_IDLE_BG = Color3.fromRGB(22, 21, 28)
local SLOT_HOVER_BG = Color3.fromRGB(36, 34, 44)

local function stroke(inst: Instance, thickness: number, col: Color3)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.Color = col
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = inst
	return s
end

-- UICorner radius as scale of the shorter box side (Roblox interprets scale on CornerRadius).
local function cornerScale(inst: GuiObject, scale: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(scale, 0)
	c.Parent = inst
	return c
end

local function padScale(inst: GuiObject, top: number, other: number?)
	local o = other or top
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(top, 0)
	p.PaddingBottom = UDim.new(o, 0)
	p.PaddingLeft = UDim.new(o, 0)
	p.PaddingRight = UDim.new(o, 0)
	p.Parent = inst
	return p
end

local function elementLabelFromId(id: string): string
	for _, el in ipairs(ELEMENTS) do
		if el.id == id then
			return el.label
		end
	end
	return id
end

local BendingUI = {}
BendingUI.__index = BendingUI

function BendingUI.new()
	local self = setmetatable({}, BendingUI)

	local playerGui = player:WaitForChild("PlayerGui", 60)
	if not playerGui then
		error("[BendingUI] PlayerGui did not load in time.", 2)
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "BendingUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 50
	gui.Enabled = true
	gui.Parent = playerGui

	-- Screen gameplay HUD: hidden until an element is chosen.
	local mainHud = Instance.new("Frame")
	mainHud.Name = "MainHUD"
	mainHud.BackgroundTransparency = 1
	mainHud.Size = UDim2.fromScale(1, 1)
	mainHud.Visible = false
	mainHud.Parent = gui

	-- Top: compact bar — Health | Chi side by side with horizontal tracks.
	local top = Instance.new("Frame")
	top.Name = "TopBar"
	top.AnchorPoint = Vector2.new(0, 0)
	top.Position = UDim2.new(0.02, 0, 0.02, 0)
	top.Size = UDim2.new(0.38, 0, 0.118, 0)
	top.BackgroundColor3 = PALETTE.hudBacking
	top.BackgroundTransparency = 0.06
	top.BorderSizePixel = 0
	top.Parent = mainHud
	cornerScale(top, 0.05)
	stroke(top, 1, PALETTE.panelEdge)

	local topLayout = Instance.new("UIListLayout")
	topLayout.FillDirection = Enum.FillDirection.Horizontal
	topLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	topLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	topLayout.Padding = UDim.new(0.028, 0)
	topLayout.SortOrder = Enum.SortOrder.LayoutOrder
	topLayout.Parent = top

	padScale(top, 0.038, 0.04)

	self._healthFill = nil :: Frame?
	self._healthText = nil :: TextLabel?
	self._chiFill = nil :: Frame?
	self._chiText = nil :: TextLabel?
	self._healthShimmer = nil :: UIGradient?
	self._chiShimmer = nil :: UIGradient?

	local function makeResourceWide(titleStr: string, color: Color3, trackTint: Color3, layoutOrder: number)
		local wrap = Instance.new("Frame")
		wrap.Name = titleStr
		wrap.BackgroundTransparency = 1
		wrap.LayoutOrder = layoutOrder
		wrap.Size = UDim2.new(0.46, -2, 1, 0)
		wrap.Parent = top

		local wrapV = Instance.new("UIListLayout")
		wrapV.FillDirection = Enum.FillDirection.Vertical
		wrapV.HorizontalAlignment = Enum.HorizontalAlignment.Left
		wrapV.VerticalAlignment = Enum.VerticalAlignment.Top
		wrapV.Padding = UDim.new(0.06, 0)
		wrapV.SortOrder = Enum.SortOrder.LayoutOrder
		wrapV.Parent = wrap

		local titleLbl = Instance.new("TextLabel")
		titleLbl.BackgroundTransparency = 1
		titleLbl.Size = UDim2.new(1, 0, 0.13, 0)
		titleLbl.Font = Enum.Font.GothamBold
		titleLbl.TextScaled = true
		titleLbl.TextSize = 14
		titleLbl.TextXAlignment = Enum.TextXAlignment.Left
		titleLbl.TextColor3 = PALETTE.inkMuted
		titleLbl.Text = string.upper(titleStr)
		titleLbl.LayoutOrder = 1
		titleLbl.Parent = wrap

		local back = Instance.new("Frame")
		back.Name = "Track"
		back.BackgroundColor3 = trackTint
		back.BorderSizePixel = 0
		back.Size = UDim2.new(1, 0, 0.62, 0)
		back.LayoutOrder = 2
		back.Parent = wrap
		cornerScale(back, 0.08)
		local trackStroke = stroke(back, 1, Color3.fromRGB(12, 12, 16))
		trackStroke.Transparency = 0.35

		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.AnchorPoint = Vector2.new(0, 0.5)
		fill.Position = UDim2.new(0.015, 0, 0.5, 0)
		fill.Size = UDim2.new(0.94, 0, 0.8, 0)
		fill.BackgroundColor3 = color
		fill.BorderSizePixel = 0
		fill.Parent = back
		cornerScale(fill, 0.1)

		local fillShimmer = Instance.new("UIGradient")
		fillShimmer.Name = "Shimmer"
		fillShimmer.Rotation = 35
		fillShimmer.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
			ColorSequenceKeypoint.new(0.45, color:Lerp(Color3.new(1, 1, 1), 0.25)),
			ColorSequenceKeypoint.new(1, color),
		})
		fillShimmer.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.5),
			NumberSequenceKeypoint.new(0.5, 0.65),
			NumberSequenceKeypoint.new(1, 0.45),
		})
		fillShimmer.Offset = Vector2.new()
		fillShimmer.Parent = fill

		local val = Instance.new("TextLabel")
		val.BackgroundTransparency = 1
		val.Size = UDim2.new(1, 0, 0.16, 0)
		val.Font = Enum.Font.GothamBold
		val.TextScaled = true
		val.TextSize = 15
		val.TextXAlignment = Enum.TextXAlignment.Left
		val.TextColor3 = PALETTE.ink
		val.Text = "100 / 100"
		val.LayoutOrder = 3
		val.Parent = wrap

		return fill, val, fillShimmer
	end

	self._healthFill, self._healthText, self._healthShimmer =
		makeResourceWide("Health", PALETTE.health, PALETTE.healthTrack, 1)
	self._chiFill, self._chiText, self._chiShimmer = makeResourceWide("Chi", PALETTE.chi, PALETTE.chiTrack, 2)

	-- Bottom: four square (1:1) ability tiles; bar matches top width vibe.
	local bottom = Instance.new("Frame")
	bottom.Name = "AbilityBar"
	bottom.AnchorPoint = Vector2.new(0.5, 1)
	bottom.Position = UDim2.new(0.5, 0, 0.98, 0)
	bottom.Size = UDim2.new(0.72, 0, 0.16, 0)
	bottom.BackgroundTransparency = 1
	bottom.Parent = mainHud

	local strip = Instance.new("Frame")
	strip.Name = "Strip"
	strip.AnchorPoint = Vector2.new(0.5, 1)
	strip.Position = UDim2.fromScale(0.5, 1)
	strip.Size = UDim2.fromScale(1, 1)
	strip.BackgroundColor3 = PALETTE.panel
	strip.BackgroundTransparency = 0.06
	strip.BorderSizePixel = 0
	strip.Parent = bottom
	cornerScale(strip, 0.08)
	stroke(strip, 1, PALETTE.panelEdge)

	padScale(strip, 0.02, 0.015)

	local row = Instance.new("Frame")
	row.Name = "AbilityRow"
	row.Size = UDim2.new(1, 0, 1, 0)
	row.BackgroundTransparency = 1
	row.Parent = strip

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	local SLOT_ROW_PAD = 0.014
	rowLayout.Padding = UDim.new(SLOT_ROW_PAD, 0)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = row

	local slotWidthScale = (1 - SLOT_ROW_PAD * (SLOT_COUNT - 1)) / SLOT_COUNT

	self._abilityLabels = {} :: { TextLabel }
	self._abilityKeys = {} :: { TextLabel }
	self._abilityBindHints = {} :: { TextLabel }
	self._abilityButtons = {} :: TextButton
	self._abilitySlotStrokes = {} :: { UIStroke }
	self._abilitySlotHovered = {} :: { boolean }
	self._abilityFeedbackMode = {} :: { string }
	self._abilityFeedbackPulseConns = {} :: { RBXScriptConnection }
	self._strip = strip
	self._mainHud = mainHud

	for i = 1, SLOT_COUNT do
		local slot = Instance.new("TextButton")
		slot.Name = "Slot_" .. tostring(i)
		-- Explicit width scale: horizontal UIListLayout + DominantAxis height + Width 0 often collapses tiles to invisible.
		slot.Size = UDim2.new(slotWidthScale, -3, 0.9, -4)
		slot.BackgroundColor3 = Color3.fromRGB(22, 21, 28)
		slot.BorderSizePixel = 0
		slot.AutoButtonColor = false
		slot.Text = ""
		slot.TextScaled = true
		slot.LayoutOrder = i
		slot.Parent = row
		cornerScale(slot, 0.12)
		local slotStroke = stroke(slot, 1, PALETTE.panelEdge)
		table.insert(self._abilitySlotStrokes, slotStroke)
		table.insert(self._abilitySlotHovered, false)
		table.insert(self._abilityFeedbackMode, "idle")

		local keyBadge = Instance.new("TextLabel")
		keyBadge.Name = "Key"
		keyBadge.AnchorPoint = Vector2.new(1, 0)
		keyBadge.Size = UDim2.new(0.28, 0, 0.26, 0)
		keyBadge.Position = UDim2.new(0.98, 0, 0.06, 0)
		keyBadge.BackgroundColor3 = PALETTE.panelEdge
		keyBadge.BackgroundTransparency = 0.2
		keyBadge.Font = Enum.Font.GothamBold
		keyBadge.TextScaled = true
		keyBadge.TextSize = 10
		keyBadge.TextColor3 = PALETTE.ink
		keyBadge.Text = tostring(i)
		keyBadge.Parent = slot
		cornerScale(keyBadge, 0.2)
		keyBadge.ZIndex = 2

		local nameLbl = Instance.new("TextLabel")
		nameLbl.Name = "Name"
		nameLbl.BackgroundTransparency = 1
		nameLbl.Size = UDim2.new(0.92, 0, 0.62, 0)
		nameLbl.Position = UDim2.new(0.04, 0, 0.1, 0)
		nameLbl.Font = Enum.Font.GothamMedium
		nameLbl.TextScaled = true
		nameLbl.TextSize = 10
		nameLbl.TextXAlignment = Enum.TextXAlignment.Center
		nameLbl.TextYAlignment = Enum.TextYAlignment.Center
		nameLbl.TextWrapped = true
		nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
		nameLbl.TextColor3 = PALETTE.ink
		nameLbl.Text = "—"
		nameLbl.ZIndex = 2
		nameLbl.Parent = slot

		local sub = Instance.new("TextLabel")
		sub.BackgroundTransparency = 1
		sub.Size = UDim2.new(1, 0, 0.18, 0)
		sub.Position = UDim2.new(0, 0, 0.8, 0)
		sub.Font = Enum.Font.Gotham
		sub.TextScaled = true
		sub.TextSize = 8
		sub.TextXAlignment = Enum.TextXAlignment.Center
		sub.TextColor3 = PALETTE.inkMuted
		sub.Text = ""
		sub.ZIndex = 2
		sub.Visible = false
		sub.Parent = slot

		table.insert(self._abilityLabels, nameLbl)
		table.insert(self._abilityKeys, keyBadge)
		table.insert(self._abilityBindHints, sub)
		table.insert(self._abilityButtons, slot)

		local idx = i
		slot.MouseEnter:Connect(function()
			self._abilitySlotHovered[idx] = true
			self:_applyAbilitySlotPresentation(idx)
		end)
		slot.MouseLeave:Connect(function()
			self._abilitySlotHovered[idx] = false
			self:_applyAbilitySlotPresentation(idx)
		end)
	end

	-- Element picker (scale). Fullscreen blocker, no dim.
	local overlay = Instance.new("TextButton")
	overlay.Name = "ElementPicker"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundTransparency = 1
	overlay.Text = ""
	overlay.TextScaled = true
	overlay.AutoButtonColor = false
	overlay.Modal = true
	overlay.Visible = false
	overlay.ZIndex = 20
	overlay.Active = true
	overlay.Selectable = false
	overlay.Parent = gui

	local modal = Instance.new("Frame")
	modal.Name = "Modal"
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.Position = UDim2.fromScale(0.5, 0.5)
	modal.Size = UDim2.new(0.56, 0, 0.44, 0)
	modal.BackgroundColor3 = PALETTE.panel
	modal.BorderSizePixel = 0
	modal.ZIndex = 21
	modal.Parent = overlay
	cornerScale(modal, 0.04)
	stroke(modal, 1, PALETTE.accent)

	padScale(modal, 0.03, 0.035)

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0.18, 0)
	title.Position = UDim2.new(0, 0, 0, 0)
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.TextSize = 20
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = PALETTE.ink
	title.Text = "Choose your element"
	title.ZIndex = 22
	title.Parent = modal

	local subtitle = Instance.new("TextLabel")
	subtitle.BackgroundTransparency = 1
	subtitle.Size = UDim2.new(1, 0, 0.12, 0)
	subtitle.Position = UDim2.new(0, 0, 0.18, 0)
	subtitle.Font = Enum.Font.GothamMedium
	subtitle.TextScaled = true
	subtitle.TextSize = 13
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.TextColor3 = PALETTE.inkMuted
	subtitle.Text = "Shown again each time you reset."
	subtitle.ZIndex = 22
	subtitle.Parent = modal

	local backBtn = Instance.new("TextButton")
	backBtn.Name = "Back"
	backBtn.AnchorPoint = Vector2.new(1, 0)
	backBtn.Position = UDim2.new(0.98, 0, 0.03, 0)
	backBtn.Size = UDim2.new(0.2, 0, 0.1, 0)
	backBtn.BackgroundColor3 = Color3.fromRGB(32, 30, 40)
	backBtn.AutoButtonColor = false
	backBtn.Text = "Back"
	backBtn.TextScaled = true
	backBtn.Font = Enum.Font.GothamBold
	backBtn.TextColor3 = PALETTE.ink
	backBtn.Visible = false
	backBtn.ZIndex = 24
	backBtn.Parent = modal
	cornerScale(backBtn, 0.15)
	stroke(backBtn, 1, PALETTE.panelEdge)
	backBtn.MouseEnter:Connect(function()
		backBtn.BackgroundColor3 = Color3.fromRGB(44, 40, 54)
	end)
	backBtn.MouseLeave:Connect(function()
		backBtn.BackgroundColor3 = Color3.fromRGB(32, 30, 40)
	end)

	local elRow = Instance.new("Frame")
	elRow.Name = "Elements"
	elRow.Position = UDim2.new(0, 0, 0.3, 0)
	elRow.Size = UDim2.new(1, 0, 0.62, 0)
	elRow.BackgroundTransparency = 1
	elRow.ZIndex = 22
	elRow.Parent = modal

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rowLayout.Padding = UDim.new(0.015, 0)
	rowLayout.Parent = elRow

	local subRow = Instance.new("Frame")
	subRow.Name = "Subbendings"
	subRow.Position = UDim2.new(0, 0, 0.3, 0)
	subRow.Size = UDim2.new(1, 0, 0.62, 0)
	subRow.BackgroundTransparency = 1
	subRow.Visible = false
	subRow.ZIndex = 23
	subRow.Parent = modal

	local subLayout = Instance.new("UIListLayout")
	subLayout.FillDirection = Enum.FillDirection.Horizontal
	subLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	subLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	subLayout.Padding = UDim.new(0.012, 0)
	subLayout.Parent = subRow

	self._overlay = overlay
	self._pickerTitle = title
	self._pickerSubtitle = subtitle
	self._elRow = elRow
	self._subRow = subRow
	self._backBtn = backBtn
	self._pickerCallback = nil :: ((string, string) -> ())?
	self._elementId = "water"
	self._tweenConn = nil :: RBXScriptConnection?
	self._boundCharacter = nil :: Model?
	self._billboard = nil :: BillboardGui?
	self._billboardConns = {} :: { RBXScriptConnection }

	self:_refreshAbilitySlots(self._elementId)

	for _, el in ipairs(ELEMENTS) do
		local btn = Instance.new("TextButton")
		btn.Name = el.id
		btn.Size = UDim2.new(0.2, 0, 0.75, 0)
		btn.Text = ""
		btn.TextScaled = true
		btn.AutoButtonColor = false
		btn.BackgroundColor3 = Color3.fromRGB(22, 21, 28)
		btn.BorderSizePixel = 0
		btn.ZIndex = 22
		btn.Parent = elRow
		cornerScale(btn, 0.08)
		stroke(btn, 1, PALETTE.panelEdge)

		local band = Instance.new("Frame")
		band.Size = UDim2.new(1, 0, 0.08, 0)
		band.Position = UDim2.new(0, 0, 0, 0)
		band.BackgroundColor3 = el.hue
		band.BorderSizePixel = 0
		band.ZIndex = 23
		band.Parent = btn
		cornerScale(band, 0.08)

		local lbl = Instance.new("TextLabel")
		lbl.BackgroundTransparency = 1
		lbl.Size = UDim2.new(0.9, 0, 0.7, 0)
		lbl.Position = UDim2.new(0.05, 0, 0.22, 0)
		lbl.Font = Enum.Font.GothamBold
		lbl.TextScaled = true
		lbl.TextSize = 18
		lbl.TextColor3 = PALETTE.ink
		lbl.Text = el.label
		lbl.ZIndex = 23
		lbl.Parent = btn

		btn.MouseEnter:Connect(function()
			btn.BackgroundColor3 = Color3.fromRGB(32, 30, 40)
		end)
		btn.MouseLeave:Connect(function()
			btn.BackgroundColor3 = Color3.fromRGB(22, 21, 28)
		end)

		btn.MouseButton1Click:Connect(function()
			self:_openSubbendingStep(el.id)
		end)
	end

	backBtn.MouseButton1Click:Connect(function()
		self:_returnToElementStep()
	end)

	self._gui = gui
	self._humanoid = nil :: Humanoid?
	self._chiCurrent = 100
	self._chiMax = 100
	self._chiConn = nil :: RBXScriptConnection?
	self._healthConns = {} :: { RBXScriptConnection }
	self._attrConn = nil :: RBXScriptConnection?
	self._subAttrConn = nil :: RBXScriptConnection?

	self:_startDynamicMotion()

	return self
end

function BendingUI:_clearBillboardConns()
	for _, c in self._billboardConns do
		c:Disconnect()
	end
	table.clear(self._billboardConns)
end

function BendingUI:_destroyBillboard()
	self:_clearBillboardConns()
	if self._billboard then
		self._billboard:Destroy()
		self._billboard = nil
	end
end

function BendingUI:_mountBillboard(character: Model)
	self:_destroyBillboard()
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		hrp = character:WaitForChild("HumanoidRootPart", 5) :: BasePart?
	end
	if not hrp then
		return
	end

	local bb = Instance.new("BillboardGui")
	bb.Name = "BendingNameplate"
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 55
	bb.Size = UDim2.new(3.2, 0, 0.95, 0)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 2.35, 0)
	bb.Parent = hrp
	self._billboard = bb

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = PALETTE.hudBacking
	root.BackgroundTransparency = 0.05
	root.BorderSizePixel = 0
	root.Parent = bb
	cornerScale(root, 0.06)
	stroke(root, 1, PALETTE.panelEdge)
	padScale(root, 0.04, 0.045)

	local v = Instance.new("UIListLayout")
	v.FillDirection = Enum.FillDirection.Vertical
	v.SortOrder = Enum.SortOrder.LayoutOrder
	v.Padding = UDim.new(0.04, 0)
	v.Parent = root

	local nameLbl = Instance.new("TextLabel")
	nameLbl.Name = "UserName"
	nameLbl.Size = UDim2.new(1, 0, 0.2, 0)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Font = Enum.Font.GothamBold
	nameLbl.TextScaled = true
	nameLbl.TextSize = 18
	nameLbl.TextXAlignment = Enum.TextXAlignment.Left
	nameLbl.TextColor3 = PALETTE.ink
	nameLbl.Text = player.DisplayName ~= "" and player.DisplayName or player.Name
	nameLbl.LayoutOrder = 1
	nameLbl.Parent = root

	local bendLbl = Instance.new("TextLabel")
	bendLbl.Name = "Bending"
	bendLbl.Size = UDim2.new(1, 0, 0.16, 0)
	bendLbl.BackgroundTransparency = 1
	bendLbl.Font = Enum.Font.GothamMedium
	bendLbl.TextScaled = true
	bendLbl.TextSize = 14
	bendLbl.TextXAlignment = Enum.TextXAlignment.Left
	bendLbl.TextColor3 = PALETTE.inkMuted
	bendLbl.Text = "Bending: —"
	bendLbl.LayoutOrder = 2
	bendLbl.Parent = root

	local subLbl = Instance.new("TextLabel")
	subLbl.Name = "Subbending"
	subLbl.Size = UDim2.new(1, 0, 0.16, 0)
	subLbl.BackgroundTransparency = 1
	subLbl.Font = Enum.Font.GothamMedium
	subLbl.TextScaled = true
	subLbl.TextSize = 13
	subLbl.TextXAlignment = Enum.TextXAlignment.Left
	subLbl.TextColor3 = PALETTE.inkMuted
	subLbl.Text = "Subbending: —"
	subLbl.LayoutOrder = 3
	subLbl.Parent = root

	local hpWrap = Instance.new("Frame")
	hpWrap.Name = "HealthOverhead"
	hpWrap.Size = UDim2.new(1, 0, 0.22, 0)
	hpWrap.BackgroundTransparency = 1
	hpWrap.LayoutOrder = 4
	hpWrap.Parent = root

	local hpBack = Instance.new("Frame")
	hpBack.Name = "Track"
	hpBack.Size = UDim2.new(1, 0, 0.55, 0)
	hpBack.Position = UDim2.new(0, 0, 0.22, 0)
	hpBack.BackgroundColor3 = PALETTE.healthTrack
	hpBack.BorderSizePixel = 0
	hpBack.Parent = hpWrap
	cornerScale(hpBack, 0.2)
	stroke(hpBack, 1, Color3.fromRGB(12, 12, 16))

	local hpFill = Instance.new("Frame")
	hpFill.Name = "Fill"
	hpFill.AnchorPoint = Vector2.new(0, 0.5)
	hpFill.Position = UDim2.new(0.02, 0, 0.5, 0)
	hpFill.Size = UDim2.new(0.85, 0, 0.7, 0)
	hpFill.BackgroundColor3 = PALETTE.health
	hpFill.BorderSizePixel = 0
	hpFill.Parent = hpBack
	cornerScale(hpFill, 0.25)

	local hpTxt = Instance.new("TextLabel")
	hpTxt.Name = "HPText"
	hpTxt.Size = UDim2.new(1, 0, 0.45, 0)
	hpTxt.Position = UDim2.new(0, 0, 0, 0)
	hpTxt.BackgroundTransparency = 1
	hpTxt.Font = Enum.Font.GothamBold
	hpTxt.TextScaled = true
	hpTxt.TextSize = 12
	hpTxt.TextXAlignment = Enum.TextXAlignment.Left
	hpTxt.TextColor3 = PALETTE.ink
	hpTxt.Text = "100 / 100"
	hpTxt.Parent = hpWrap

	self._bbName = nameLbl
	self._bbBending = bendLbl
	self._bbSub = subLbl
	self._bbHpFill = hpFill
	self._bbHpText = hpTxt

	local hum = character:FindFirstChildOfClass("Humanoid")
	local function refreshOverhead()
		self:_refreshOverheadHealth(hum, hpFill, hpTxt)
		self:_refreshOverheadLabels(character, bendLbl, subLbl)
	end

	if hum then
		table.insert(self._billboardConns, hum:GetPropertyChangedSignal("Health"):Connect(refreshOverhead))
		table.insert(self._billboardConns, hum:GetPropertyChangedSignal("MaxHealth"):Connect(refreshOverhead))
	end
	table.insert(self._billboardConns, character:GetAttributeChangedSignal("BendingElement"):Connect(refreshOverhead))
	table.insert(self._billboardConns, character:GetAttributeChangedSignal("BendingSub"):Connect(refreshOverhead))

	refreshOverhead()
end

function BendingUI:_refreshOverheadHealth(humanoid: Humanoid?, hpFill: Frame, hpTxt: TextLabel)
	if not humanoid then
		return
	end
	local max = humanoid.MaxHealth > 0 and humanoid.MaxHealth or 100
	local h = math.clamp(humanoid.Health, 0, max)
	local t = h / max
	hpFill.Size = UDim2.new(math.max(t, 0) * 0.96, 0, 0.7, 0)
	hpTxt.Text = string.format("Health %d / %d", math.floor(h + 0.5), math.floor(max + 0.5))
end

function BendingUI:_refreshOverheadLabels(character: Model, bendLbl: TextLabel, subLbl: TextLabel)
	local el = character:GetAttribute("BendingElement")
	local sub = character:GetAttribute("BendingSub")
	bendLbl.Text = "Bending: " .. (typeof(el) == "string" and elementLabelFromId(el) or "—")
	subLbl.Text = "Subbending: " .. (typeof(sub) == "string" and sub or "—")
end

function BendingUI:_showGameplayAfterPick()
	self._mainHud.Visible = true
	if self._boundCharacter then
		self:_mountBillboard(self._boundCharacter)
	end
end

function BendingUI:_hideGameplayForPicker()
	self._mainHud.Visible = false
	self:_destroyBillboard()
end

function BendingUI:_startDynamicMotion()
	if self._tweenConn then
		self._tweenConn:Disconnect()
	end
	local t0 = os.clock()
	self._tweenConn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		local wave = 0.5 + 0.5 * math.sin(t * 2.4)
		local slide = Vector2.new(math.sin(t * 1.1) * 0.08, math.cos(t * 0.9) * 0.05)
		if self._healthShimmer then
			self._healthShimmer.Offset = slide
		end
		if self._chiShimmer then
			self._chiShimmer.Offset = Vector2.new(-slide.X, slide.Y)
		end
		local hum = self._humanoid
		if hum and hum.MaxHealth > 0 then
			local ratio = hum.Health / hum.MaxHealth
			if ratio < 0.35 and self._healthFill then
				local pulse = 0.85 + 0.15 * wave
				self._healthFill.BackgroundColor3 = PALETTE.health:Lerp(Color3.fromRGB(200, 255, 210), 0.18 * pulse)
			elseif self._healthFill then
				self._healthFill.BackgroundColor3 = PALETTE.health
			end
		end
	end)
end

function BendingUI:IsPickerOpen(): boolean
	return self._overlay.Visible
end

function BendingUI:_clearAbilitySlotPulse(index: number)
	local c = self._abilityFeedbackPulseConns[index]
	if c then
		c:Disconnect()
		self._abilityFeedbackPulseConns[index] = nil
	end
end

function BendingUI:_applyAbilitySlotPresentation(index: number)
	local mode = self._abilityFeedbackMode[index]
	local slot = self._abilityButtons[index]
	local s = self._abilitySlotStrokes[index]
	if not slot or not s then
		return
	end
	local hover = self._abilitySlotHovered[index]
	local baseBg = if hover then SLOT_HOVER_BG else SLOT_IDLE_BG
	if mode == "idle" then
		slot.BackgroundColor3 = baseBg
		s.Color = PALETTE.panelEdge
		s.Thickness = 1
		return
	elseif mode == "cast" then
		slot.BackgroundColor3 = baseBg:Lerp(PALETTE.chi, 0.45)
		s.Color = PALETTE.ink:Lerp(PALETTE.chi, 0.85)
		s.Thickness = 3
		return
	end
	if mode == "aim" then
		slot.BackgroundColor3 = baseBg:Lerp(PALETTE.chi, 0.14)
	elseif mode == "armed" then
		slot.BackgroundColor3 = baseBg:Lerp(PALETTE.chi, 0.26)
	end
end

function BendingUI:SetAbilitySlotFeedback(index: number, mode: string)
	assert(index >= 1 and index <= SLOT_COUNT)
	self:_clearAbilitySlotPulse(index)
	self._abilityFeedbackMode[index] = mode
	if mode == "aim" or mode == "armed" then
		local s = self._abilitySlotStrokes[index]
		local speed = if mode == "aim" then 7 else 4.5
		local thickBase = if mode == "aim" then 1.5 else 2.1
		local thickAmp = if mode == "aim" then 0.9 else 1.2
		local t0 = os.clock()
		self._abilityFeedbackPulseConns[index] = RunService.Heartbeat:Connect(function()
			local w = 0.5 + 0.5 * math.sin((os.clock() - t0) * speed)
			s.Color = PALETTE.chi:Lerp(Color3.fromRGB(220, 250, 255), 0.25 * w)
			s.Thickness = thickBase + thickAmp * w
		end)
	end
	self:_applyAbilitySlotPresentation(index)
end

function BendingUI:ConnectAbilitySlot(index: number, handler: () -> ())
	assert(index >= 1 and index <= SLOT_COUNT)
	local b = self._abilityButtons[index]
	return b.MouseButton1Click:Connect(handler)
end

function BendingUI:_refreshAbilitySlots(elementId: string)
	local list = ABILITIES_BY_ELEMENT[elementId] or ABILITIES_BY_ELEMENT.water
	for i = 1, SLOT_COUNT do
		local def = list[i]
		local lbl = self._abilityLabels[i]
		local key = self._abilityKeys[i]
		local hint = self._abilityBindHints[i]
		if def and lbl and key then
			lbl.Text = def.name
			key.Text = def.key
			if hint then
				hint.Visible = false
			end
		elseif lbl then
			lbl.Text = "—"
			if key then
				key.Text = "·"
			end
		end
	end
end

function BendingUI:_clearSubbendingButtons()
	for _, ch in self._subRow:GetChildren() do
		if ch:IsA("TextButton") then
			ch:Destroy()
		end
	end
end

function BendingUI:_returnToElementStep()
	self._elRow.Visible = true
	self._subRow.Visible = false
	self._backBtn.Visible = false
	self._pickerTitle.Text = "Choose your element"
	self._pickerSubtitle.Text = "Shown again each time you reset."
	self:_clearSubbendingButtons()
end

function BendingUI:_openSubbendingStep(elementId: string)
	self._pickerTitle.Text = "Choose subbending"
	self._pickerSubtitle.Text = elementLabelFromId(elementId) .. " · pick a specialization"
	self._elRow.Visible = false
	self._subRow.Visible = true
	self._backBtn.Visible = true
	self:_clearSubbendingButtons()

	local subs = SUBBENDINGS[elementId]
	if not subs then
		self:_finalizePickFromPicker(elementId, "—")
		return
	end

	local hue = PALETTE.accent
	for _, el in ipairs(ELEMENTS) do
		if el.id == elementId then
			hue = el.hue
			break
		end
	end

	for _, sub in ipairs(subs) do
		local b = Instance.new("TextButton")
		b.Name = sub.id
		b.Size = UDim2.new(0.16, 0, 0.88, 0)
		b.BackgroundColor3 = Color3.fromRGB(22, 21, 28)
		b.AutoButtonColor = false
		b.Text = ""
		b.TextScaled = true
		b.ZIndex = 23
		b.Parent = self._subRow
		cornerScale(b, 0.1)
		stroke(b, 1, PALETTE.panelEdge)

		local band = Instance.new("Frame")
		band.Size = UDim2.new(1, 0, 0.1, 0)
		band.Position = UDim2.new(0, 0, 0, 0)
		band.BackgroundColor3 = hue
		band.BorderSizePixel = 0
		band.ZIndex = 24
		band.Parent = b
		cornerScale(band, 0.1)

		local lbl = Instance.new("TextLabel")
		lbl.BackgroundTransparency = 1
		lbl.Size = UDim2.new(0.9, 0, 0.72, 0)
		lbl.Position = UDim2.new(0.05, 0, 0.18, 0)
		lbl.Font = Enum.Font.GothamBold
		lbl.TextScaled = true
		lbl.TextSize = 14
		lbl.TextColor3 = PALETTE.ink
		lbl.Text = sub.label
		lbl.ZIndex = 24
		lbl.Parent = b

		b.MouseEnter:Connect(function()
			b.BackgroundColor3 = Color3.fromRGB(36, 34, 44)
		end)
		b.MouseLeave:Connect(function()
			b.BackgroundColor3 = Color3.fromRGB(22, 21, 28)
		end)

		b.MouseButton1Click:Connect(function()
			self:_finalizePickFromPicker(elementId, sub.label)
		end)
	end
end

function BendingUI:_finalizePickFromPicker(elementId: string, subLabel: string)
	self:_applyElementVisual(elementId)
	self._overlay.Visible = false
	self:_returnToElementStep()
	if self._pickerCallback then
		self._pickerCallback(elementId, subLabel)
	end
	self:_showGameplayAfterPick()
end

function BendingUI:_applyElementVisual(id: string)
	self._elementId = id
	local hue = PALETTE.accent
	for _, el in ipairs(ELEMENTS) do
		if el.id == id then
			hue = el.hue
			break
		end
	end
	if self._strip then
		local s = self._strip:FindFirstChildOfClass("UIStroke")
		if s then
			s.Color = hue:Lerp(PALETTE.panelEdge, 0.35)
		end
		local goal = hue:Lerp(PALETTE.panel, 0.88)
		TweenService:Create(self._strip, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundColor3 = goal,
		}):Play()
	end
	self:_refreshAbilitySlots(id)
	if self._bbBending and self._bbSub and self._boundCharacter then
		self:_refreshOverheadLabels(self._boundCharacter, self._bbBending, self._bbSub)
	end
end

function BendingUI:SetAbilitySlot(index: number, name: string, keyDisplay: string)
	local lbl = self._abilityLabels[index]
	local key = self._abilityKeys[index]
	if lbl then
		lbl.Text = name
	end
	if key then
		key.Text = keyDisplay
	end
	local hint = self._abilityBindHints[index]
	if hint then
		hint.Text = keyDisplay
	end
end

function BendingUI:SetElementAccent(id: string, subLabel: string?)
	self:_applyElementVisual(id)
	self._overlay.Visible = false
	self:_returnToElementStep()
	self:_showGameplayAfterPick()
	if self._boundCharacter and typeof(subLabel) == "string" then
		self._boundCharacter:SetAttribute("BendingSub", subLabel)
	end
end

function BendingUI:ShowElementPicker(onChosen: (string, string) -> ())
	self._pickerCallback = onChosen
	self:_hideGameplayForPicker()
	self:_returnToElementStep()
	self._overlay.Visible = true
end

function BendingUI:BindCharacter(character: Model)
	if self._chiConn then
		self._chiConn:Disconnect()
		self._chiConn = nil
	end
	if self._attrConn then
		self._attrConn:Disconnect()
		self._attrConn = nil
	end
	if self._subAttrConn then
		self._subAttrConn:Disconnect()
		self._subAttrConn = nil
	end
	for _, c in self._healthConns do
		c:Disconnect()
	end
	table.clear(self._healthConns)

	self:_destroyBillboard()

	self._boundCharacter = character

	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		return
	end
	self._humanoid = humanoid

	local function refreshHealth()
		local fill = self._healthFill
		local txt = self._healthText
		if not fill or not txt then
			return
		end
		local max = humanoid.MaxHealth > 0 and humanoid.MaxHealth or 100
		local h = math.clamp(humanoid.Health, 0, max)
		local t = h / max
		TweenService:Create(fill, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.new(0.94 * math.max(t, 0), 0, 0.8, 0),
		}):Play()
		txt.Text = string.format("%d / %d", math.floor(h + 0.5), math.floor(max + 0.5))
	end

	refreshHealth()
	table.insert(self._healthConns, humanoid:GetPropertyChangedSignal("Health"):Connect(refreshHealth))
	table.insert(self._healthConns, humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(refreshHealth))

	self._chiMax = 100
	self._chiCurrent = self._chiMax

	local function refreshChi(useTween: boolean)
		local fill = self._chiFill
		local txt = self._chiText
		if not fill or not txt then
			return
		end
		local t = self._chiCurrent / self._chiMax
		local size = UDim2.new(0.94 * math.max(t, 0), 0, 0.8, 0)
		if useTween then
			TweenService:Create(fill, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = size,
			}):Play()
		else
			fill.Size = size
		end
		txt.Text = string.format("%d / %d", math.floor(self._chiCurrent + 0.5), self._chiMax)
	end

	refreshChi(true)
	self._chiConn = RunService.RenderStepped:Connect(function(dt)
		if self._overlay.Visible then
			return
		end
		if self._chiCurrent < self._chiMax then
			self._chiCurrent = math.min(self._chiMax, self._chiCurrent + dt * 22)
			refreshChi(false)
		end
	end)

	humanoid.Died:Connect(function()
		if self._chiConn then
			self._chiConn:Disconnect()
			self._chiConn = nil
		end
		if self._attrConn then
			self._attrConn:Disconnect()
			self._attrConn = nil
		end
		if self._subAttrConn then
			self._subAttrConn:Disconnect()
			self._subAttrConn = nil
		end
	end)

	self._attrConn = character:GetAttributeChangedSignal("BendingElement"):Connect(function()
		local el = character:GetAttribute("BendingElement")
		if typeof(el) == "string" then
			self:_applyElementVisual(el)
		end
	end)
	self._subAttrConn = character:GetAttributeChangedSignal("BendingSub"):Connect(function()
		if self._bbSub and self._bbBending and self._boundCharacter then
			self:_refreshOverheadLabels(self._boundCharacter, self._bbBending, self._bbSub)
		end
	end)

	local initialEl = character:GetAttribute("BendingElement")
	if typeof(initialEl) == "string" then
		self:_applyElementVisual(initialEl)
	end
end

function BendingUI:Destroy()
	for i = 1, SLOT_COUNT do
		self:_clearAbilitySlotPulse(i)
	end
	if self._chiConn then
		self._chiConn:Disconnect()
	end
	if self._tweenConn then
		self._tweenConn:Disconnect()
	end
	if self._attrConn then
		self._attrConn:Disconnect()
		self._attrConn = nil
	end
	if self._subAttrConn then
		self._subAttrConn:Disconnect()
		self._subAttrConn = nil
	end
	self:_destroyBillboard()
	self._gui:Destroy()
end

return BendingUI
