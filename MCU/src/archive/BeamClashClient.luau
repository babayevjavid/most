--!strict
--[[
	Beam clash: random buttons near screen center.
	Click the glowing prompt before it expires — first to N wins.
]]

local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local GameConstants = require(ReplicatedStorage.Shared.GameConstants)

local BeamClashClient = {}

function BeamClashClient.init(localPlayer: Player)
	local playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui

	local remoteOk, remoteOrErr = pcall(function()
		return Remotes.getEvent("BeamClash")
	end)
	local remote: RemoteEvent? = if remoteOk then remoteOrErr else nil
	if not remoteOk then
		warn("[BeamClashClient] BeamClash remote missing:", remoteOrErr)
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "MCU_BeamClash"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 200
	gui.Enabled = false
	gui.Parent = playerGui

	local dim = Instance.new("Frame")
	dim.Name = "Dim"
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 0.55
	dim.BorderSizePixel = 0
	dim.Active = false
	dim.Parent = gui

	local hud = Instance.new("Frame")
	hud.Name = "Hud"
	hud.AnchorPoint = Vector2.new(0.5, 0)
	hud.Position = UDim2.new(0.5, 0, 0.08, 0)
	hud.Size = UDim2.fromOffset(320, 64)
	hud.BackgroundColor3 = Color3.fromRGB(16, 16, 20)
	hud.BackgroundTransparency = 0.15
	hud.BorderSizePixel = 0
	hud.Parent = gui

	local hudCorner = Instance.new("UICorner")
	hudCorner.CornerRadius = UDim.new(0, 12)
	hudCorner.Parent = hud

	local hudStroke = Instance.new("UIStroke")
	hudStroke.Color = Color3.fromRGB(255, 255, 255)
	hudStroke.Thickness = 1.5
	hudStroke.Transparency = 0.25
	hudStroke.Parent = hud

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(14, 6)
	title.Size = UDim2.new(1, -28, 0, 26)
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 20
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "BEAM CLASH"
	title.Parent = hud

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.BackgroundTransparency = 1
	subtitle.Position = UDim2.fromOffset(14, 34)
	subtitle.Size = UDim2.new(1, -28, 0, 22)
	subtitle.Font = Enum.Font.GothamMedium
	subtitle.TextSize = 14
	subtitle.TextColor3 = Color3.fromRGB(210, 210, 220)
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.Text = "Click the marks — 0 / 5"
	subtitle.Parent = hud

	local promptLayer = Instance.new("Frame")
	promptLayer.Name = "Prompts"
	promptLayer.Size = UDim2.fromScale(1, 1)
	promptLayer.BackgroundTransparency = 1
	promptLayer.Parent = gui

	local activeClashId: string? = nil
	local activePromptId: string? = nil
	local activePromptBtn: TextButton? = nil
	local score = 0
	local need = GameConstants.BEAM_CLASH_PROMPTS_TO_WIN
	local opponentLabel = "Opponent"

	local function clearPromptBtn()
		if activePromptBtn then
			activePromptBtn:Destroy()
			activePromptBtn = nil
		end
		activePromptId = nil
	end

	local function closeUi()
		activeClashId = nil
		clearPromptBtn()
		gui.Enabled = false
	end

	local function openUi(clashId: string?, opponentName: string?, s: number?, n: number?)
		activeClashId = clashId
		score = s or GameConstants.BEAM_CLASH_START_SCORE
		need = n or GameConstants.BEAM_CLASH_PROMPTS_TO_WIN
		opponentLabel = opponentName or "Opponent"
		title.Text = "BEAM CLASH"
		subtitle.Text = string.format("vs %s — %d / %d", opponentLabel, score, need)
		gui.Enabled = true
	end

	local function spawnPrompt(promptId: string, x: number, y: number, life: number)
		clearPromptBtn()
		activePromptId = promptId

		local btn = Instance.new("TextButton")
		btn.Name = "ClashPrompt"
		btn.AnchorPoint = Vector2.new(0.5, 0.5)
		btn.Position = UDim2.fromScale(x, y)
		btn.Size = UDim2.fromOffset(72, 72)
		btn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		btn.BorderSizePixel = 0
		btn.Text = ""
		btn.AutoButtonColor = false
		btn.Parent = promptLayer
		activePromptBtn = btn

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = btn

		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(255, 255, 255)
		stroke.Thickness = 3
		stroke.Parent = btn

		local ring = Instance.new("Frame")
		ring.Name = "Ring"
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.Position = UDim2.fromScale(0.5, 0.5)
		ring.Size = UDim2.fromScale(1.35, 1.35)
		ring.BackgroundTransparency = 1
		ring.Parent = btn

		local ringStroke = Instance.new("UIStroke")
		ringStroke.Color = Color3.fromRGB(255, 255, 255)
		ringStroke.Thickness = 2
		ringStroke.Transparency = 0.2
		ringStroke.Parent = ring

		local ringCorner = Instance.new("UICorner")
		ringCorner.CornerRadius = UDim.new(1, 0)
		ringCorner.Parent = ring

		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.GothamBlack
		label.Text = "●"
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(20, 20, 24)
		label.Parent = btn

		-- Shrink ring as timer
		TweenService:Create(ring, TweenInfo.new(life, Enum.EasingStyle.Linear), {
			Size = UDim2.fromScale(0.2, 0.2),
		}):Play()
		TweenService:Create(ringStroke, TweenInfo.new(life, Enum.EasingStyle.Linear), {
			Transparency = 1,
		}):Play()

		local function hit()
			if activePromptId ~= promptId or not activeClashId or not remote then
				return
			end
			remote:FireServer({
				action = "prompt_hit",
				clashId = activeClashId,
				promptId = promptId,
			})
			btn.BackgroundColor3 = Color3.fromRGB(180, 255, 200)
			clearPromptBtn()
		end

		btn.MouseButton1Click:Connect(hit)
		btn.Activated:Connect(hit)
	end

	if remote then
		remote.OnClientEvent:Connect(function(payload: any)
			if type(payload) ~= "table" then
				return
			end
			local phase = payload.phase
			if phase == "start" then
				openUi(
					if type(payload.clashId) == "string" then payload.clashId else nil,
					if type(payload.opponent) == "string" then payload.opponent else nil,
					if type(payload.score) == "number" then payload.score else GameConstants.BEAM_CLASH_START_SCORE,
					if type(payload.need) == "number" then payload.need else GameConstants.BEAM_CLASH_PROMPTS_TO_WIN
				)
			elseif phase == "score" then
				if type(payload.score) == "number" then
					score = payload.score
				end
				if type(payload.need) == "number" then
					need = payload.need
				end
				if type(payload.opponent) == "string" then
					opponentLabel = payload.opponent
				end
				subtitle.Text = string.format("vs %s — %d / %d", opponentLabel, score, need)
			elseif phase == "prompt" then
				if type(payload.clashId) == "string" then
					activeClashId = payload.clashId
				end
				if not gui.Enabled then
					openUi(
						activeClashId,
						if type(payload.opponent) == "string" then payload.opponent else nil,
						if type(payload.score) == "number" then payload.score else score,
						if type(payload.need) == "number" then payload.need else need
					)
				end
				if type(payload.score) == "number" then
					score = payload.score
				end
				if type(payload.need) == "number" then
					need = payload.need
				end
				if type(payload.opponent) == "string" then
					opponentLabel = payload.opponent
					subtitle.Text = string.format("vs %s — %d / %d", opponentLabel, score, need)
				else
					subtitle.Text = string.format("Click the marks — %d / %d", score, need)
				end
				if type(payload.promptId) == "string" and type(payload.x) == "number" and type(payload.y) == "number" then
					spawnPrompt(payload.promptId, payload.x, payload.y, if type(payload.life) == "number" then payload.life else GameConstants.BEAM_CLASH_PROMPT_LIFE)
				end
			elseif phase == "prompt_miss" then
				clearPromptBtn()
			elseif phase == "retract" then
				clearPromptBtn()
				title.Text = "OUT OF RANGE"
				subtitle.Text = "Beams retracting…"
			elseif phase == "end" then
				clearPromptBtn()
				gui.Enabled = true
				if payload.canceled == true then
					title.Text = "CLASH BROKEN"
					subtitle.Text = "Too far apart"
				elseif payload.tied == true then
					title.Text = "BOTH LOST"
					subtitle.Text = "Clash lasted too long"
				elseif payload.won == true then
					title.Text = "YOU WIN"
					subtitle.Text = "Beam surge!"
				else
					title.Text = "OVERPOWERED"
					subtitle.Text = "Knocked back"
				end
				task.delay(0.9, closeUi)
			end
		end)
	end

	local function hookCharacter(character: Model)
		local function syncFromAttr()
			local active = character:GetAttribute(GameConstants.BEAM_CLASH_ATTRIBUTE) == true
			local clashId = character:GetAttribute("BeamClashId")
			local opp = character:GetAttribute("BeamClashOpponent")
			if active and not gui.Enabled then
				openUi(
					if type(clashId) == "string" then clashId else nil,
					if type(opp) == "string" then opp else "Opponent",
					GameConstants.BEAM_CLASH_START_SCORE,
					GameConstants.BEAM_CLASH_PROMPTS_TO_WIN
				)
			elseif not active and gui.Enabled and title.Text == "BEAM CLASH" and not activePromptId then
				task.delay(0.05, function()
					if character:GetAttribute(GameConstants.BEAM_CLASH_ATTRIBUTE) ~= true and title.Text == "BEAM CLASH" then
						closeUi()
					end
				end)
			end
		end
		character:GetAttributeChangedSignal(GameConstants.BEAM_CLASH_ATTRIBUTE):Connect(syncFromAttr)
		syncFromAttr()
	end

	if localPlayer.Character then
		hookCharacter(localPlayer.Character)
	end
	localPlayer.CharacterAdded:Connect(hookCharacter)
	localPlayer.CharacterRemoving:Connect(closeUi)

	-- Space / click also works if a prompt exists and mouse is over it — button handles clicks.
	UserInputService.InputBegan:Connect(function(input, gp)
		if gp or not gui.Enabled or not activePromptBtn then
			return
		end
		if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.ButtonA then
			-- Don't auto-hit with space — must click the mark (skill)
			return
		end
	end)

	print("[BeamClashClient] prompt UI ready")
end

return BeamClashClient
