--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("HUDTheme"))

local AbilityButton = require(script.Parent.Components.AbilityButton)
local AvatarViewport = require(script.Parent.Components.AvatarViewport)
local CurrencyRow = require(script.Parent.Components.CurrencyRow)
local PassiveButton = require(script.Parent.Components.PassiveButton)
local StatBar = require(script.Parent.Components.StatBar)

export type MainHUDController = {
	Gui: ScreenGui,
	AbilityButtons: { [string]: AbilityButton.AbilityButtonHandle },
	Show: (self: MainHUDController, heroId: string, layout: any) -> (),
	Hide: (self: MainHUDController) -> (),
	UpdateStats: (self: MainHUDController, payload: { [string]: any }) -> (),
	UpdateCooldown: (self: MainHUDController, abilityId: string, duration: number) -> (),
	RefreshAvatar: (self: MainHUDController, player: Player) -> (),
	TickCooldowns: (self: MainHUDController) -> (),
}

local MainHUD = {}

function MainHUD.create(): MainHUDController
	local Players = game:GetService("Players")
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "MainHUD"
	screenGui.ResetOnSpawn = false
	screenGui.Enabled = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui

	local topRight = Instance.new("Frame")
	topRight.Name = "TopRightCurrencies"
	topRight.AnchorPoint = Vector2.new(1, 0)
	topRight.BackgroundTransparency = 1
	topRight.Position = UDim2.new(0.985, 0, 0.018, 0)
	topRight.Size = UDim2.new(0.11, 0, 0.065, 0)
	topRight.Parent = screenGui

	local currencyLayout = Instance.new("UIListLayout")
	currencyLayout.FillDirection = Enum.FillDirection.Vertical
	currencyLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	currencyLayout.Padding = UDim.new(0.08, 0)
	currencyLayout.SortOrder = Enum.SortOrder.LayoutOrder
	currencyLayout.Parent = topRight

	local blueCurrency = CurrencyRow.create(topRight, "Blue", Theme.CurrencyBlue)
	blueCurrency.Frame.LayoutOrder = 1

	local yellowCurrency = CurrencyRow.create(topRight, "Yellow", Theme.CurrencyYellow)
	yellowCurrency.Frame.LayoutOrder = 2

	local topLeft = Instance.new("Frame")
	topLeft.Name = "TopLeftCluster"
	topLeft.BackgroundTransparency = 1
	topLeft.AnchorPoint = Vector2.new(0, 0)
	topLeft.Position = UDim2.fromScale(0, 0)
	topLeft.Size = UDim2.fromScale(1, 1)
	topLeft.Parent = screenGui

	local viewportSlot = Instance.new("Frame")
	viewportSlot.Name = "ViewportSlot"
	viewportSlot.BackgroundTransparency = 1
	viewportSlot.AnchorPoint = Vector2.new(0, 0)
	viewportSlot.Position = Theme.ViewportPosition
	viewportSlot.Size = Theme.ViewportSize
	viewportSlot.Parent = topLeft

	local viewportAspect = Instance.new("UIAspectRatioConstraint")
	viewportAspect.AspectRatio = 1
	viewportAspect.DominantAxis = Enum.DominantAxis.Height
	viewportAspect.Parent = viewportSlot

	local viewportSizeConstraint = Instance.new("UISizeConstraint")
	viewportSizeConstraint.MinSize = Vector2.new(0, 0)
	viewportSizeConstraint.Parent = viewportSlot

	local viewport = AvatarViewport.create(viewportSlot)

	local barsContainer = Instance.new("Frame")
	barsContainer.Name = "Bars"
	barsContainer.BackgroundTransparency = 1
	barsContainer.AnchorPoint = Vector2.new(0, 0)
	barsContainer.Position = Theme.BarsPosition
	barsContainer.Size = Theme.BarsSize
	barsContainer.Parent = topLeft

	local barsSizeConstraint = Instance.new("UISizeConstraint")
	barsSizeConstraint.MinSize = Vector2.new(0, 0)
	barsSizeConstraint.Parent = barsContainer

	local barsAspect = Instance.new("UIAspectRatioConstraint")
	barsAspect.AspectRatio = Theme.BarsAspectRatio
	barsAspect.DominantAxis = Enum.DominantAxis.Height
	barsAspect.Parent = barsContainer

	local barsLayout = Instance.new("UIListLayout")
	barsLayout.Padding = UDim.new(Theme.StatBarGapScale, 0)
	barsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	barsLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	barsLayout.Parent = barsContainer

	local healthBar = StatBar.create(barsContainer, "Health", Theme.Health, Theme.HealthDark, Theme.HealthText)
	healthBar.Frame.LayoutOrder = 1
	local staminaBar = StatBar.create(barsContainer, "Stamina", Theme.Stamina, Theme.StaminaDark, Theme.StaminaText)
	staminaBar.Frame.LayoutOrder = 2
	local energyBar = StatBar.create(barsContainer, "Energy", Theme.Energy, Theme.EnergyDark, Theme.EnergyText)
	energyBar.Frame.LayoutOrder = 3

	local bottomBar = Instance.new("Frame")
	bottomBar.Name = "AbilityBarContainer"
	bottomBar.AnchorPoint = Vector2.new(0.5, 1)
	bottomBar.BackgroundTransparency = 1
	bottomBar.Position = UDim2.new(0.5, 0, 0.985, 0)
	bottomBar.Size = UDim2.new(Theme.AbilityBarWidthScale, 0, Theme.AbilityBarHeightScale, 0)
	bottomBar.Parent = screenGui

	local abilityRow = Instance.new("Frame")
	abilityRow.Name = "AbilityRow"
	abilityRow.AnchorPoint = Vector2.new(0.5, 0.5)
	abilityRow.BackgroundTransparency = 1
	abilityRow.Position = UDim2.fromScale(0.5, 0.5)
	abilityRow.Size = UDim2.new(0.88, 0, 0.92, 0)
	abilityRow.Parent = bottomBar

	local abilityLayout = Instance.new("UIListLayout")
	abilityLayout.FillDirection = Enum.FillDirection.Horizontal
	abilityLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	abilityLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	abilityLayout.Padding = UDim.new(0.012, 0)
	abilityLayout.SortOrder = Enum.SortOrder.LayoutOrder
	abilityLayout.Parent = abilityRow

	local passiveSlot = Instance.new("Frame")
	passiveSlot.Name = "PassiveSlot"
	passiveSlot.AnchorPoint = Vector2.new(0, 0.5)
	passiveSlot.BackgroundTransparency = 1
	passiveSlot.Position = UDim2.new(1, 0, 0.5, 0)
	passiveSlot.Size = UDim2.new(0.13, 0, Theme.AbilityButtonHeightScale, 0)
	passiveSlot.Parent = abilityRow

	local passiveAspect = Instance.new("UIAspectRatioConstraint")
	passiveAspect.AspectRatio = 1
	passiveAspect.DominantAxis = Enum.DominantAxis.Height
	passiveAspect.Parent = passiveSlot

	local abilityButtons: { [string]: AbilityButton.AbilityButtonHandle } = {}
	local cooldownEnds: { [string]: { endTime: number, duration: number } } = {}
	local passiveHandle: PassiveButton.PassiveButtonHandle? = nil
	local currentAccent = Theme.Stroke

	local controller: MainHUDController = {
		Gui = screenGui,
		AbilityButtons = abilityButtons,
		Show = function(self, heroId: string, layout: any)
			currentAccent = Theme.HeroAccents[heroId] or Theme.Stroke

			for _, child in abilityRow:GetChildren() do
				if child:IsA("GuiObject") and child.Name ~= "PassiveSlot" and not child:IsA("UIListLayout") and not child:IsA("UIAspectRatioConstraint") then
					child:Destroy()
				end
			end
			if passiveHandle then
				passiveHandle.Frame:Destroy()
				passiveHandle = nil
			end
			table.clear(abilityButtons)
			table.clear(cooldownEnds)

			for index, abilityDef in layout.abilities do
				local btn = AbilityButton.create(abilityRow, abilityDef.Id, abilityDef.DisplayName, abilityDef.Keybind)
				btn.Frame.LayoutOrder = index
				btn:SetAccent(currentAccent)
				abilityButtons[abilityDef.Id] = btn
			end

			local moveDef = layout.movement
			local moveBtn = AbilityButton.create(abilityRow, moveDef.Id, moveDef.DisplayName, moveDef.Keybind)
			moveBtn.Frame.LayoutOrder = 6
			moveBtn:SetAccent(currentAccent)
			abilityButtons[moveDef.Id] = moveBtn

			passiveHandle = PassiveButton.create(passiveSlot, layout.passive.Id, layout.passive.DisplayName)
			passiveHandle:SetAccent(currentAccent)

			screenGui.Enabled = true
			self:RefreshAvatar(player)
		end,
		Hide = function(_self)
			screenGui.Enabled = false
		end,
		UpdateStats = function(_self, payload: { [string]: any })
			healthBar:SetValue(payload.Health or 0, payload.MaxHealth or 100)
			staminaBar:SetValue(payload.Stamina or 0, payload.MaxStamina or 100)
			energyBar:SetValue(payload.Energy or 0, payload.MaxEnergy or 100)
			blueCurrency:SetAmount(payload.Blue or 0)
			yellowCurrency:SetAmount(payload.Yellow or 0)
		end,
		UpdateCooldown = function(_self, abilityId: string, duration: number)
			cooldownEnds[abilityId] = { endTime = os.clock() + duration, duration = duration }
		end,
		RefreshAvatar = function(_self, localPlayer: Player)
			viewport:Refresh(localPlayer)
		end,
		TickCooldowns = function(_self)
			local now = os.clock()
			for abilityId, data in cooldownEnds do
				local remaining = data.endTime - now
				local btn = abilityButtons[abilityId]
				if btn then
					if remaining > 0 then
						btn:SetCooldown(remaining, data.duration)
					else
						btn:SetReady()
						cooldownEnds[abilityId] = nil
					end
				end
			end
		end,
	}

	return controller
end

return MainHUD
