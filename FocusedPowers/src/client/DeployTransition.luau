--!strict
--[[ DeployTransition: brief full-screen fade when spawning a hero. ]]

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HudConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("HudConstants"))

local deployGui: ScreenGui? = nil
local deployFrame: Frame? = nil
local deployLabel: TextLabel? = nil
local deploySubtitle: TextLabel? = nil
local accentLine: Frame? = nil
local activeToken = 0
local activeToBlackTween: Tween? = nil
local activeFromBlackTween: Tween? = nil
local activeLabelTween: Tween? = nil

local function ensureFrame(playerGui: PlayerGui): (Frame, TextLabel, TextLabel, Frame)
	if deployFrame and deployFrame.Parent and deployLabel and deployLabel.Parent and deploySubtitle and accentLine then
		return deployFrame, deployLabel, deploySubtitle, accentLine
	end
	if deployGui and deployGui.Parent then
		deployGui:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "DeployTransition"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = HudConstants.TRANSITION_DISPLAY_ORDER
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui
	deployGui = gui

	local frame = Instance.new("Frame")
	frame.Name = "CharacterFade"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = HudConstants.SURFACE_BACKDROP
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Active = false
	frame.Parent = gui
	deployFrame = frame

	local line = Instance.new("Frame")
	line.Name = "AccentLine"
	line.AnchorPoint = Vector2.new(0.5, 0.5)
	line.Position = UDim2.fromScale(0.5, 0.5)
	line.Size = UDim2.fromOffset(48, 2)
	line.BackgroundColor3 = HudConstants.COLOR_ACCENT
	line.BackgroundTransparency = 1
	line.BorderSizePixel = 0
	line.Parent = frame
	accentLine = line

	local label = Instance.new("TextLabel")
	label.Name = "HeroName"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.46)
	label.Size = UDim2.fromOffset(480, 40)
	label.BackgroundTransparency = 1
	label.Font = HudConstants.FONT_HEADING
	label.TextColor3 = HudConstants.COLOR_TEXT
	label.TextSize = 28
	label.TextTransparency = 1
	label.Text = ""
	label.Parent = frame
	deployLabel = label

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Deploying"
	subtitle.AnchorPoint = Vector2.new(0.5, 0.5)
	subtitle.Position = UDim2.fromScale(0.5, 0.54)
	subtitle.Size = UDim2.fromOffset(200, 20)
	subtitle.BackgroundTransparency = 1
	subtitle.Font = HudConstants.FONT_BODY
	subtitle.TextColor3 = HudConstants.COLOR_TEXT_SECONDARY
	subtitle.TextSize = 13
	subtitle.TextTransparency = 1
	subtitle.Text = "Deploying"
	subtitle.Parent = frame
	deploySubtitle = subtitle

	return frame, label, subtitle, line
end

local function cancelActiveTweens()
	if activeToBlackTween then
		activeToBlackTween:Cancel()
		activeToBlackTween = nil
	end
	if activeFromBlackTween then
		activeFromBlackTween:Cancel()
		activeFromBlackTween = nil
	end
	if activeLabelTween then
		activeLabelTween:Cancel()
		activeLabelTween = nil
	end
end

local DeployTransition = {}

function DeployTransition.cancel()
	activeToken += 1
	cancelActiveTweens()
	if deployFrame and deployFrame.Parent then
		deployFrame.Visible = false
		deployFrame.BackgroundTransparency = 1
	end
	if deployLabel and deployLabel.Parent then
		deployLabel.TextTransparency = 1
		deployLabel.Text = ""
	end
	if deploySubtitle and deploySubtitle.Parent then
		deploySubtitle.TextTransparency = 1
	end
	if accentLine and accentLine.Parent then
		accentLine.BackgroundTransparency = 1
	end
end

function DeployTransition.play(
	playerGui: PlayerGui,
	heroDisplayName: string?,
	accentColor: Color3?,
	onMidpoint: (() -> ())?
)
	activeToken += 1
	local token = activeToken
	cancelActiveTweens()

	local frame, label, subtitle, line = ensureFrame(playerGui)
	local accent = accentColor or HudConstants.COLOR_ACCENT
	line.BackgroundColor3 = accent
	frame.Visible = true
	frame.BackgroundTransparency = 1
	label.Text = heroDisplayName or ""
	label.TextTransparency = 1
	subtitle.TextTransparency = 1
	line.BackgroundTransparency = 1

	local fadeIn = TweenService:Create(
		frame,
		TweenInfo.new(HudConstants.DEPLOY_FADE_IN, HudConstants.UI_EASING_STYLE, HudConstants.UI_EASING_DIRECTION),
		{ BackgroundTransparency = 0.04 }
	)
	activeToBlackTween = fadeIn
	fadeIn:Play()

	local labelIn = TweenService:Create(
		label,
		TweenInfo.new(HudConstants.DEPLOY_FADE_IN * 0.85, HudConstants.UI_EASING_STYLE, HudConstants.UI_EASING_DIRECTION),
		{ TextTransparency = 0 }
	)
	activeLabelTween = labelIn
	labelIn:Play()

	TweenService:Create(
		subtitle,
		TweenInfo.new(HudConstants.DEPLOY_FADE_IN, HudConstants.UI_EASING_STYLE, HudConstants.UI_EASING_DIRECTION),
		{ TextTransparency = 0 }
	):Play()

	TweenService:Create(
		line,
		TweenInfo.new(HudConstants.DEPLOY_FADE_IN, HudConstants.UI_EASING_STYLE, HudConstants.UI_EASING_DIRECTION),
		{ BackgroundTransparency = 0 }
	):Play()

	fadeIn.Completed:Connect(function(playbackState)
		if playbackState ~= Enum.PlaybackState.Completed or token ~= activeToken then
			return
		end
		activeToBlackTween = nil

		if onMidpoint then
			onMidpoint()
		end

		task.delay(HudConstants.DEPLOY_HOLD, function()
			if token ~= activeToken or not frame.Parent then
				return
			end

			TweenService:Create(
				subtitle,
				TweenInfo.new(HudConstants.DEPLOY_FADE_OUT * 0.5, HudConstants.UI_EASING_STYLE, HudConstants.UI_EASING_DIRECTION),
				{ TextTransparency = 1 }
			):Play()

			TweenService:Create(
				line,
				TweenInfo.new(HudConstants.DEPLOY_FADE_OUT * 0.5, HudConstants.UI_EASING_STYLE, HudConstants.UI_EASING_DIRECTION),
				{ BackgroundTransparency = 1 }
			):Play()

			local labelOut = TweenService:Create(
				label,
				TweenInfo.new(HudConstants.DEPLOY_FADE_OUT * 0.6, HudConstants.UI_EASING_STYLE, HudConstants.UI_EASING_DIRECTION),
				{ TextTransparency = 1 }
			)
			labelOut:Play()

			local fadeOut = TweenService:Create(
				frame,
				TweenInfo.new(HudConstants.DEPLOY_FADE_OUT, HudConstants.UI_EASING_STYLE, HudConstants.UI_EASING_DIRECTION),
				{ BackgroundTransparency = 1 }
			)
			activeFromBlackTween = fadeOut
			fadeOut:Play()
			fadeOut.Completed:Connect(function(fadeOutState)
				if fadeOutState ~= Enum.PlaybackState.Completed or token ~= activeToken then
					return
				end
				activeFromBlackTween = nil
				if frame.Parent then
					frame.Visible = false
				end
				if label.Parent then
					label.Text = ""
				end
			end)
		end)
	end)
end

return DeployTransition
