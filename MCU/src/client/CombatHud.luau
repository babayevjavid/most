--!strict
--[[ Top-center status labels with smooth fade in/out. ]]

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AbilityCooldownHelper = require(ReplicatedStorage.Shared.AbilityCooldownHelper)
local GameConstants = require(ReplicatedStorage.Shared.GameConstants)

local CombatHud = {}

function CombatHud.init(player: Player)
	local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "CombatHud"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 25
	screenGui.Parent = playerGui

	local function makeTopLabel(name: string, text: string, color: Color3, y: number): TextLabel
		local label = Instance.new("TextLabel")
		label.Name = name
		label.AnchorPoint = Vector2.new(0.5, 0)
		label.Position = UDim2.fromScale(0.5, y)
		label.Size = UDim2.fromScale(0.28, 0.045)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.Bangers
		label.Text = text
		label.TextColor3 = color
		label.TextStrokeColor3 = Color3.fromRGB(20, 8, 10)
		label.TextStrokeTransparency = 1
		label.TextScaled = true
		label.TextTransparency = 1
		label.Visible = true
		label.Parent = screenGui

		local textConstraint = Instance.new("UITextSizeConstraint")
		textConstraint.MaxTextSize = 36
		textConstraint.MinTextSize = 14
		textConstraint.Parent = label

		return label
	end

	local combatLabel = makeTopLabel("CombatLabel", "IN COMBAT", Color3.fromRGB(220, 70, 80), 0.09)
	local protectedLabel = makeTopLabel("ProtectedLabel", "PROTECTED", Color3.fromRGB(90, 200, 255), 0.04)

	local function bindFade(label: TextLabel): (boolean) -> ()
		local shown = false
		local activeTween: Tween? = nil
		return function(on: boolean)
			if on == shown then
				return
			end
			shown = on
			if activeTween then
				activeTween:Cancel()
				activeTween = nil
			end
			local goal = { TextTransparency = if on then 0 else 1, TextStrokeTransparency = if on then 0.35 else 1 }
			local info = TweenInfo.new(if on then 0.28 else 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			activeTween = TweenService:Create(label, info, goal)
			activeTween:Play()
		end
	end

	local setCombatVisible = bindFade(combatLabel)
	local setProtectedVisible = bindFade(protectedLabel)

	local function bindCharacter(character: Model)
		local function syncCombat()
			setCombatVisible(character:GetAttribute(GameConstants.IN_COMBAT_ATTRIBUTE) == true)
		end
		local function syncProtected()
			local untilTime = character:GetAttribute(GameConstants.PROTECTED_UNTIL_ATTRIBUTE)
			local on = type(untilTime) == "number" and untilTime > AbilityCooldownHelper.getNow()
			setProtectedVisible(on)
		end
		character:GetAttributeChangedSignal(GameConstants.IN_COMBAT_ATTRIBUTE):Connect(syncCombat)
		character:GetAttributeChangedSignal(GameConstants.PROTECTED_UNTIL_ATTRIBUTE):Connect(syncProtected)
		syncCombat()
		syncProtected()
		task.spawn(function()
			while character.Parent do
				syncProtected()
				task.wait(0.12)
			end
			setProtectedVisible(false)
			setCombatVisible(false)
		end)
	end

	player.CharacterAdded:Connect(bindCharacter)
	if player.Character then
		bindCharacter(player.Character)
	end
end

return CombatHud
