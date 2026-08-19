--!strict
--[[ Bottom-left character picker + hero look cycle (starter / clothes / true avatar) ]]

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterRegistry = require(ReplicatedStorage.Shared.CharacterRegistry)

export type LookMode = "starter" | "clothes" | "avatar"

export type SelectionController = {
	show: () -> (),
	hide: () -> (),
	destroy: () -> (),
	getLookMode: () -> LookMode,
}

local LOOK_CYCLE: { LookMode } = { "clothes", "avatar", "starter" }

local CharacterSelectUI = {}

function CharacterSelectUI.create(playerGui: PlayerGui, onSelect: (string, LookMode) -> ()): SelectionController
	local roster = CharacterRegistry.getRoster()
	local lookIndex = 1 -- clothes by default
	local function currentLook(): LookMode
		return LOOK_CYCLE[lookIndex]
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "CharacterSelect"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 20
	screenGui.Enabled = false
	screenGui.Parent = playerGui

	local guiInset = GuiService:GetGuiInset()

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0, 1)
	panel.Position = UDim2.new(0.012, guiInset.X, 0.98, -guiInset.Y)
	panel.Size = UDim2.fromScale(0.17, 0.34)
	panel.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
	panel.BackgroundTransparency = 0.12
	panel.BorderSizePixel = 0
	panel.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.04, 0)
	corner.Parent = panel

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(55, 55, 65)
	stroke.Thickness = 1
	stroke.Transparency = 0.4
	stroke.Parent = panel

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.04, 0)
	padding.PaddingBottom = UDim.new(0.04, 0)
	padding.PaddingLeft = UDim.new(0.06, 0)
	padding.PaddingRight = UDim.new(0.06, 0)
	padding.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0.025, 0)
	layout.Parent = panel

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.LayoutOrder = 0
	title.Size = UDim2.fromScale(1, 0.1)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.Bangers
	title.Text = "Choose hero"
	title.TextColor3 = Color3.fromRGB(210, 210, 220)
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = panel

	local lookToggle = Instance.new("TextButton")
	lookToggle.Name = "LookToggle"
	lookToggle.LayoutOrder = 1
	lookToggle.Size = UDim2.fromScale(1, 0.14)
	lookToggle.BackgroundColor3 = Color3.fromRGB(28, 36, 44)
	lookToggle.AutoButtonColor = true
	lookToggle.Font = Enum.Font.Bangers
	lookToggle.TextScaled = true
	lookToggle.TextColor3 = Color3.fromRGB(200, 220, 240)
	lookToggle.Parent = panel

	local toggleCorner = Instance.new("UICorner")
	toggleCorner.CornerRadius = UDim.new(0.2, 0)
	toggleCorner.Parent = lookToggle

	local function refreshToggle()
		local mode = currentLook()
		if mode == "clothes" then
			lookToggle.Text = "Hero look: My Clothes"
			lookToggle.BackgroundColor3 = Color3.fromRGB(28, 36, 44)
			lookToggle.TextColor3 = Color3.fromRGB(200, 220, 240)
		elseif mode == "avatar" then
			lookToggle.Text = "Hero look: True Avatar"
			lookToggle.BackgroundColor3 = Color3.fromRGB(32, 44, 58)
			lookToggle.TextColor3 = Color3.fromRGB(170, 215, 255)
		else
			lookToggle.Text = "Hero look: Starter Default"
			lookToggle.BackgroundColor3 = Color3.fromRGB(40, 36, 28)
			lookToggle.TextColor3 = Color3.fromRGB(240, 220, 160)
		end
	end
	refreshToggle()

	lookToggle.MouseButton1Click:Connect(function()
		lookIndex = (lookIndex % #LOOK_CYCLE) + 1
		refreshToggle()
	end)

	local heroCount = math.max(#roster, 1)
	local heroHeight = 0.66 / heroCount
	for index, entry in roster do
		local btn = Instance.new("TextButton")
		btn.Name = entry.id
		btn.LayoutOrder = index + 1
		btn.Size = UDim2.fromScale(1, heroHeight)
		btn.BackgroundColor3 = Color3.fromRGB(32, 32, 40)
		btn.AutoButtonColor = true
		btn.Font = Enum.Font.Bangers
		btn.Text = entry.displayName
		btn.TextColor3 = Color3.fromRGB(235, 235, 240)
		btn.TextScaled = true
		btn.Parent = panel

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0.18, 0)
		btnCorner.Parent = btn

		btn.MouseButton1Click:Connect(function()
			onSelect(entry.id, currentLook())
			screenGui.Enabled = false
		end)
	end

	return {
		show = function()
			screenGui.Enabled = true
		end,
		hide = function()
			screenGui.Enabled = false
		end,
		destroy = function()
			screenGui:Destroy()
		end,
		getLookMode = function()
			return currentLook()
		end,
	}
end

return CharacterSelectUI
