--!strict
--[[
	Blinding Flash screen overlay:
	Quick fade-in to ~95% white, hold, then slow fade-out over the remaining duration.
]]

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local GameConstants = require(ReplicatedStorage.Shared.GameConstants)

local BlindFlashClient = {}

function BlindFlashClient.init(localPlayer: Player)
	local playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "MCU_BlindFlash"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 100
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.Parent = playerGui

	local cover = Instance.new("Frame")
	cover.Name = "Cover"
	cover.Size = UDim2.fromScale(1, 1)
	cover.BackgroundColor3 = Color3.new(1, 1, 1)
	cover.BackgroundTransparency = 1
	cover.BorderSizePixel = 0
	cover.Parent = gui

	local token = 0

	Remotes.getEvent("BlindFlash").OnClientEvent:Connect(function(payload: any)
		local duration = GameConstants.DAGGER_FLASH_DURATION
		if type(payload) == "table" and type(payload.duration) == "number" then
			duration = payload.duration
		end
		token += 1
		local myToken = token

		gui.Enabled = true
		cover.BackgroundTransparency = 1

		-- Quick enable (~0.12s) to 95% white (transparency 0.05)
		local fadeIn = TweenService:Create(
			cover,
			TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 0.05 }
		)
		fadeIn:Play()
		fadeIn.Completed:Wait()
		if myToken ~= token then
			return
		end

		local hold = math.max(0, duration - 0.12 - 1.4)
		if hold > 0 then
			task.wait(hold)
		end
		if myToken ~= token then
			return
		end

		-- Slow disable over ~1.4s
		local fadeOut = TweenService:Create(
			cover,
			TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ BackgroundTransparency = 1 }
		)
		fadeOut:Play()
		fadeOut.Completed:Wait()
		if myToken == token then
			gui.Enabled = false
		end
	end)

	localPlayer.CharacterRemoving:Connect(function()
		token += 1
		gui.Enabled = false
		cover.BackgroundTransparency = 1
	end)
end

return BlindFlashClient
