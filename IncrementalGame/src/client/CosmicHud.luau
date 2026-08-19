local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CosmicConfig = require(Shared:WaitForChild("CosmicConfig"))
local CosmicFormat = require(Shared:WaitForChild("CosmicFormat"))
local WorldStyle = require(Shared:WaitForChild("WorldStyle"))

local palette = WorldStyle.Palette
local fonts = WorldStyle.Fonts

local CosmicHud = {}

function CosmicHud.Start()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local remotesFolder = ReplicatedStorage:WaitForChild("SuperpowerRemotes", 20)
	if not remotesFolder then
		warn("[CosmicHud] SuperpowerRemotes missing — server may have failed to start.")
		return
	end
	local notifyRemote = remotesFolder:WaitForChild("Notify", 10) :: RemoteEvent
	if not notifyRemote then
		return
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "SuperpowerHud"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGui

	local hudFrame = Instance.new("Frame")
	hudFrame.Name = "Hud"
	hudFrame.Position = UDim2.fromOffset(20, 20)
	hudFrame.Size = UDim2.fromOffset(330, 118)
	hudFrame.BackgroundColor3 = Color3.fromRGB(24, 27, 34)
	hudFrame.BorderSizePixel = 0
	hudFrame.Parent = screenGui

	local outerStroke = Instance.new("UIStroke")
	outerStroke.Color = Color3.fromRGB(58, 62, 72)
	outerStroke.Thickness = 1
	outerStroke.Parent = hudFrame

	local topBar = Instance.new("Frame")
	topBar.Name = "TopBar"
	topBar.Size = UDim2.new(1, 0, 0, 30)
	topBar.BackgroundColor3 = Color3.fromRGB(32, 36, 46)
	topBar.BorderSizePixel = 0
	topBar.Parent = hudFrame

	local topStripe = Instance.new("Frame")
	topStripe.Size = UDim2.new(1, 0, 0, 3)
	topStripe.BackgroundColor3 = palette.LaneStripe
	topStripe.BorderSizePixel = 0
	topStripe.Parent = topBar

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(12, 5)
	title.Size = UDim2.new(1, -24, 1, -5)
	title.Font = fonts.Display
	title.TextSize = 15
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = palette.TextPrimary
	title.Text = string.upper(CosmicConfig.GameName)
	title.Parent = topBar

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(12, 38)
	body.Size = UDim2.new(1, -24, 1, -48)
	body.Parent = hudFrame

	local bodyLayout = Instance.new("UIListLayout")
	bodyLayout.FillDirection = Enum.FillDirection.Horizontal
	bodyLayout.Padding = UDim.new(0, 12)
	bodyLayout.Parent = body

	local powerBlock = Instance.new("Frame")
	powerBlock.Name = "PowerBlock"
	powerBlock.BackgroundTransparency = 1
	powerBlock.Size = UDim2.new(0.46, 0, 1, 0)
	powerBlock.LayoutOrder = 1
	powerBlock.Parent = body

	local powerCaption = Instance.new("TextLabel")
	powerCaption.BackgroundTransparency = 1
	powerCaption.Size = UDim2.new(1, 0, 0, 14)
	powerCaption.Font = fonts.Label
	powerCaption.TextSize = 11
	powerCaption.TextXAlignment = Enum.TextXAlignment.Left
	powerCaption.TextColor3 = palette.TextMuted
	powerCaption.Text = "POWER"
	powerCaption.Parent = powerBlock

	local powerLabel = Instance.new("TextLabel")
	powerLabel.Name = "PowerValue"
	powerLabel.BackgroundTransparency = 1
	powerLabel.Position = UDim2.fromOffset(0, 14)
	powerLabel.Size = UDim2.new(1, 0, 0, 34)
	powerLabel.Font = fonts.Display
	powerLabel.TextSize = 30
	powerLabel.TextXAlignment = Enum.TextXAlignment.Left
	powerLabel.TextColor3 = palette.LaneStripe
	powerLabel.Text = "0"
	powerLabel.Parent = powerBlock

	local statColumn = Instance.new("Frame")
	statColumn.Name = "Stats"
	statColumn.BackgroundTransparency = 1
	statColumn.Size = UDim2.new(0.54, -12, 1, 0)
	statColumn.LayoutOrder = 2
	statColumn.Parent = body

	local statLayout = Instance.new("UIListLayout")
	statLayout.Padding = UDim.new(0, 8)
	statLayout.Parent = statColumn

	local rateRow = Instance.new("Frame")
	rateRow.BackgroundTransparency = 1
	rateRow.Size = UDim2.new(1, 0, 0, 28)
	rateRow.Parent = statColumn

	local rateCaption = Instance.new("TextLabel")
	rateCaption.BackgroundTransparency = 1
	rateCaption.Size = UDim2.new(0.42, 0, 1, 0)
	rateCaption.Font = fonts.Label
	rateCaption.TextSize = 11
	rateCaption.TextXAlignment = Enum.TextXAlignment.Left
	rateCaption.TextColor3 = palette.TextMuted
	rateCaption.Text = "GAIN"
	rateCaption.Parent = rateRow

	local rateLabel = Instance.new("TextLabel")
	rateLabel.Name = "RateValue"
	rateLabel.BackgroundTransparency = 1
	rateLabel.Position = UDim2.fromScale(0.42, 0)
	rateLabel.Size = UDim2.new(0.58, 0, 1, 0)
	rateLabel.Font = fonts.Stat
	rateLabel.TextSize = 18
	rateLabel.TextXAlignment = Enum.TextXAlignment.Left
	rateLabel.TextColor3 = palette.TextPrimary
	rateLabel.Text = "+0/s"
	rateLabel.Parent = rateRow

	local multRow = Instance.new("Frame")
	multRow.BackgroundTransparency = 1
	multRow.Size = UDim2.new(1, 0, 0, 28)
	multRow.Parent = statColumn

	local multCaption = Instance.new("TextLabel")
	multCaption.BackgroundTransparency = 1
	multCaption.Size = UDim2.new(0.42, 0, 1, 0)
	multCaption.Font = fonts.Label
	multCaption.TextSize = 11
	multCaption.TextXAlignment = Enum.TextXAlignment.Left
	multCaption.TextColor3 = palette.TextMuted
	multCaption.Text = "MULT"
	multCaption.Parent = multRow

	local multLabel = Instance.new("TextLabel")
	multLabel.Name = "MultValue"
	multLabel.BackgroundTransparency = 1
	multLabel.Position = UDim2.fromScale(0.42, 0)
	multLabel.Size = UDim2.new(0.58, 0, 1, 0)
	multLabel.Font = fonts.Stat
	multLabel.TextSize = 18
	multLabel.TextXAlignment = Enum.TextXAlignment.Left
	multLabel.TextColor3 = palette.AccentSoft
	multLabel.Text = "x1.00"
	multLabel.Parent = multRow

	local footer = Instance.new("TextLabel")
	footer.BackgroundTransparency = 1
	footer.Position = UDim2.new(0, 12, 1, -18)
	footer.Size = UDim2.new(1, -24, 0, 14)
	footer.Font = fonts.Label
	footer.TextSize = 10
	footer.TextXAlignment = Enum.TextXAlignment.Left
	footer.TextColor3 = palette.TextMuted
	footer.Text = "Upgrade on your base · keys 1-5 use powers"
	footer.Parent = hudFrame

	local toast = Instance.new("Frame")
	toast.Name = "Toast"
	toast.BackgroundColor3 = Color3.fromRGB(24, 27, 34)
	toast.AnchorPoint = Vector2.new(0.5, 0)
	toast.Position = UDim2.new(0.5, 0, 0, 18)
	toast.Size = UDim2.fromOffset(340, 38)
	toast.Visible = false
	toast.Parent = screenGui

	local toastStroke = Instance.new("UIStroke")
	toastStroke.Color = Color3.fromRGB(58, 62, 72)
	toastStroke.Parent = toast

	local toastText = Instance.new("TextLabel")
	toastText.Name = "Message"
	toastText.BackgroundTransparency = 1
	toastText.Size = UDim2.new(1, -16, 1, 0)
	toastText.Position = UDim2.fromOffset(12, 0)
	toastText.Font = fonts.Label
	toastText.TextSize = 14
	toastText.TextXAlignment = Enum.TextXAlignment.Left
	toastText.TextColor3 = palette.TextPrimary
	toastText.TextWrapped = true
	toastText.Parent = toast

	local leaderstats = player:WaitForChild("leaderstats", 30)
	local powerStats = player:WaitForChild("PowerStats", 30)
	if not leaderstats or not powerStats then
		return
	end

	local powerValue = leaderstats:WaitForChild("Power") :: IntValue
	local powerPerSec = powerStats:WaitForChild("PowerPerSec") :: NumberValue
	local totalMultiplier = powerStats:WaitForChild("TotalMultiplier") :: NumberValue

	local function refreshHud()
		powerLabel.Text = CosmicFormat.Number(powerValue.Value)
		rateLabel.Text = ("+%s/s"):format(CosmicFormat.Number(powerPerSec.Value))
		multLabel.Text = CosmicFormat.Multiplier(totalMultiplier.Value)
	end

	powerValue:GetPropertyChangedSignal("Value"):Connect(refreshHud)
	powerPerSec:GetPropertyChangedSignal("Value"):Connect(refreshHud)
	totalMultiplier:GetPropertyChangedSignal("Value"):Connect(refreshHud)
	refreshHud()

	local function showToast(message: string, tone: string?)
		toast.Visible = true
		toastText.TextTransparency = 0
		toastText.Text = message

		if tone == "warn" then
			toastText.TextColor3 = palette.AccentSoft
		elseif tone == "success" then
			toastText.TextColor3 = palette.Success
		else
			toastText.TextColor3 = palette.TextPrimary
		end

		task.delay(1.4, function()
			local tween = TweenService:Create(toastText, TweenInfo.new(0.25), { TextTransparency = 1 })
			tween:Play()
			tween.Completed:Wait()
			toast.Visible = false
		end)
	end

	notifyRemote.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" or type(payload.text) ~= "string" then
			return
		end
		showToast(payload.text, payload.tone)
	end)
end

return CosmicHud
