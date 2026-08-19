--!strict

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local PlayerDataClient = require(script.Parent.PlayerDataClient)

export type CoinDisplayStyle = {
	background: Color3?,
	backgroundTransparency: number?,
	stroke: Color3?,
	strokeTransparency: number?,
	text: Color3?,
	corner: number?,
	height: number?,
}

export type CoinDisplay = {
	root: Frame,
	setAnchor: (anchorPoint: Vector2, position: UDim2, size: UDim2?) -> (),
	setVisible: (visible: boolean) -> (),
	destroy: () -> (),
}

local CoinDisplayClient = {}

local MAX_TWEEN_SEC = 3

local function formatCoins(n: number): string
	local s = tostring(math.max(0, math.floor(n + 0.5)))
	local result = ""
	local count = 0
	for i = #s, 1, -1 do
		result = s:sub(i, i) .. result
		count += 1
		if count % 3 == 0 and i > 1 then
			result = "," .. result
		end
	end
	return result
end

function CoinDisplayClient.create(
	parent: Instance,
	opts: {
		zIndex: number?,
		style: CoinDisplayStyle?,
		onPlusClick: ((anchor: GuiObject) -> ())?,
	}?
): CoinDisplay
	local style = if opts then opts.style else nil
	local zIndex = if opts and opts.zIndex then opts.zIndex else 30

	local displayed = PlayerDataClient.getCoins()
	local target = displayed
	local tweenConn: RBXScriptConnection? = nil

	local root = Instance.new("Frame")
	root.Name = "TokenDisplay"
	root.AnchorPoint = Vector2.new(1, 0)
	root.Size = UDim2.fromScale(0.072, 0.022)
	root.BackgroundColor3 = if style and style.background then style.background else Color3.fromRGB(18, 36, 42)
	root.BackgroundTransparency = if style and style.backgroundTransparency ~= nil then style.backgroundTransparency else 0.08
	root.BorderSizePixel = 0
	root.ZIndex = zIndex
	root.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.22, 0)
	corner.Parent = root

	local stroke = Instance.new("UIStroke")
	stroke.Color = if style and style.stroke then style.stroke else Color3.fromRGB(228, 198, 120)
	stroke.Thickness = 1
	stroke.Transparency = if style and style.strokeTransparency ~= nil then style.strokeTransparency else 0.35
	stroke.Parent = root

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.05, 0)
	pad.PaddingRight = UDim.new(0.03, 0)
	pad.PaddingTop = UDim.new(0.08, 0)
	pad.PaddingBottom = UDim.new(0.08, 0)
	pad.Parent = root

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0.03, 0)
	layout.Parent = root

	local prefixLabel = Instance.new("TextLabel")
	prefixLabel.Name = "Prefix"
	prefixLabel.LayoutOrder = 1
	prefixLabel.Size = UDim2.fromScale(0.34, 1)
	prefixLabel.BackgroundTransparency = 1
	prefixLabel.Font = Enum.Font.GothamBold
	prefixLabel.Text = "Tokens"
	prefixLabel.TextColor3 = if style and style.text then style.text else Color3.fromRGB(240, 220, 150)
	prefixLabel.TextScaled = true
	prefixLabel.TextXAlignment = Enum.TextXAlignment.Left
	prefixLabel.ZIndex = zIndex + 1
	prefixLabel.Parent = root

	local prefixConstraint = Instance.new("UITextSizeConstraint")
	prefixConstraint.MaxTextSize = 12
	prefixConstraint.MinTextSize = 7
	prefixConstraint.Parent = prefixLabel

	local amountLabel = Instance.new("TextLabel")
	amountLabel.Name = "Amount"
	amountLabel.LayoutOrder = 2
	amountLabel.Size = UDim2.fromScale(0.42, 1)
	amountLabel.BackgroundTransparency = 1
	amountLabel.Font = Enum.Font.GothamBold
	amountLabel.Text = formatCoins(displayed)
	amountLabel.TextColor3 = if style and style.text then style.text else Color3.fromRGB(240, 220, 150)
	amountLabel.TextScaled = true
	amountLabel.TextXAlignment = Enum.TextXAlignment.Left
	amountLabel.ZIndex = zIndex + 1
	amountLabel.Parent = root

	local amountConstraint = Instance.new("UITextSizeConstraint")
	amountConstraint.MaxTextSize = 13
	amountConstraint.MinTextSize = 8
	amountConstraint.Parent = amountLabel

	local plusBtn = Instance.new("TextButton")
	plusBtn.Name = "BuyTokens"
	plusBtn.LayoutOrder = 3
	plusBtn.Size = UDim2.fromScale(0.2, 1)
	plusBtn.BackgroundColor3 = Color3.fromRGB(228, 198, 120)
	plusBtn.BackgroundTransparency = 0.05
	plusBtn.AutoButtonColor = true
	plusBtn.Font = Enum.Font.GothamBlack
	plusBtn.Text = "+"
	plusBtn.TextColor3 = Color3.fromRGB(18, 28, 32)
	plusBtn.TextScaled = true
	plusBtn.ZIndex = zIndex + 2
	plusBtn.Parent = root

	local plusCorner = Instance.new("UICorner")
	plusCorner.CornerRadius = UDim.new(0.22, 0)
	plusCorner.Parent = plusBtn

	local plusAspect = Instance.new("UIAspectRatioConstraint")
	plusAspect.AspectRatio = 1
	plusAspect.DominantAxis = Enum.DominantAxis.Height
	plusAspect.Parent = plusBtn

	local function paintAmount()
		amountLabel.Text = formatCoins(displayed)
	end

	local function stopTween()
		if tweenConn then
			tweenConn:Disconnect()
			tweenConn = nil
		end
	end

	local function animateTo(nextTarget: number)
		target = math.max(0, math.floor(nextTarget))
		stopTween()
		local delta = target - displayed
		if math.abs(delta) < 0.5 then
			displayed = target
			paintAmount()
			return
		end
		local duration = math.clamp(math.abs(delta) / 1200, 0.35, MAX_TWEEN_SEC)
		local start = displayed
		local startClock = os.clock()
		tweenConn = RunService.RenderStepped:Connect(function()
			local t = math.clamp((os.clock() - startClock) / duration, 0, 1)
			local eased = TweenService:GetValue(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			displayed = start + (target - start) * eased
			paintAmount()
			if t >= 1 then
				displayed = target
				paintAmount()
				stopTween()
			end
		end)
	end

	local function onProfileChanged()
		animateTo(PlayerDataClient.getCoins())
	end

	PlayerDataClient.onChanged(onProfileChanged)
	paintAmount()

	if opts and opts.onPlusClick then
		local callback = opts.onPlusClick
		plusBtn.MouseButton1Click:Connect(function()
			callback(root)
		end)
	end

	return {
		root = root,
		setAnchor = function(anchorPoint: Vector2, position: UDim2, size: UDim2?)
			root.AnchorPoint = anchorPoint
			root.Position = position
			if size then
				root.Size = size
			end
		end,
		setVisible = function(visible: boolean)
			root.Visible = visible
		end,
		destroy = function()
			stopTween()
			root:Destroy()
		end,
	}
end

function CoinDisplayClient.bind(
	root: Frame,
	opts: {
		onPlusClick: ((anchor: GuiObject) -> ())?,
	}?
): CoinDisplay
	local displayed = PlayerDataClient.getCoins()
	local target = displayed
	local tweenConn: RBXScriptConnection? = nil

	local amountLabel = root:FindFirstChild("Amount")
	if not amountLabel or not amountLabel:IsA("TextLabel") then
		amountLabel = root:FindFirstChildWhichIsA("TextLabel", true)
	end
	if not amountLabel or not amountLabel:IsA("TextLabel") then
		warn("[CoinDisplayClient] TokenDisplay missing Amount label")
		return {
			root = root,
			setAnchor = function() end,
			setVisible = function(visible: boolean)
				root.Visible = visible
			end,
			destroy = function() end,
		}
	end

	local prefixLabel = root:FindFirstChild("Prefix")
	if prefixLabel and prefixLabel:IsA("TextLabel") then
		prefixLabel.Text = "Tokens"
	end

	local plusBtn = root:FindFirstChild("BuyTokens") or root:FindFirstChild("BuyCoins")
	if plusBtn and plusBtn:IsA("TextButton") then
		plusBtn.Name = "BuyTokens"
	end

	local function paintAmount()
		amountLabel.Text = formatCoins(displayed)
	end

	local function stopTween()
		if tweenConn then
			tweenConn:Disconnect()
			tweenConn = nil
		end
	end

	local function animateTo(nextTarget: number)
		target = math.max(0, math.floor(nextTarget))
		stopTween()
		local delta = target - displayed
		if math.abs(delta) < 0.5 then
			displayed = target
			paintAmount()
			return
		end
		local duration = math.clamp(math.abs(delta) / 1200, 0.35, MAX_TWEEN_SEC)
		local start = displayed
		local startClock = os.clock()
		tweenConn = RunService.RenderStepped:Connect(function()
			local t = math.clamp((os.clock() - startClock) / duration, 0, 1)
			local eased = TweenService:GetValue(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			displayed = start + (target - start) * eased
			paintAmount()
			if t >= 1 then
				displayed = target
				paintAmount()
				stopTween()
			end
		end)
	end

	PlayerDataClient.onChanged(function()
		animateTo(PlayerDataClient.getCoins())
	end)
	paintAmount()

	if opts and opts.onPlusClick and plusBtn and plusBtn:IsA("TextButton") then
		local callback = opts.onPlusClick
		plusBtn.MouseButton1Click:Connect(function()
			callback(root)
		end)
	end

	return {
		root = root,
		setAnchor = function(anchorPoint: Vector2, position: UDim2, size: UDim2?)
			root.AnchorPoint = anchorPoint
			root.Position = position
			if size then
				root.Size = size
			end
		end,
		setVisible = function(visible: boolean)
			root.Visible = visible
		end,
		destroy = function()
			stopTween()
		end,
	}
end

return CoinDisplayClient
