--!strict
--[[
	Dagger F/E/C/Q abilities client.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local AbilityGateHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityGateHelper"))
local BlindingFlashConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BlindingFlashConstants"))
local HolyStrikeConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("HolyStrikeConstants"))
local LightKnivesConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LightKnivesConstants"))
local PurifyingLightConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PurifyingLightConstants"))
local AbilityInputHelper = require(script.Parent:WaitForChild("AbilityInputHelper"))

local DaggerAbilitiesClient = {}

local function ensureBlindGui(player: Player): ScreenGui
	local pg = player:WaitForChild("PlayerGui") :: PlayerGui
	local existing = pg:FindFirstChild("BlindingFlashOverlay")
	if existing and existing:IsA("ScreenGui") then
		return existing
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "BlindingFlashOverlay"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 100
	gui.Enabled = true
	gui.Parent = pg
	local frame = Instance.new("Frame")
	frame.Name = "Flash"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Parent = gui
	return gui
end

function DaggerAbilitiesClient.start(
	knivesRemote: RemoteEvent,
	strikeRemote: RemoteEvent,
	purifyRemote: RemoteEvent,
	flashRemote: RemoteEvent,
	flashNotify: RemoteEvent,
	player: Player,
	setAbilityPressed: ((key: string, pressed: boolean) -> ())?
)
	local fWas, eWas, cWas, qWas = false, false, false, false
	local gui = ensureBlindGui(player)
	local flashFrame = gui:FindFirstChild("Flash") :: Frame?

	flashNotify.OnClientEvent:Connect(function(duration: number)
		if not flashFrame then
			return
		end
		flashFrame.BackgroundTransparency = 0.15
		task.delay(duration, function()
			if flashFrame.Parent then
				flashFrame.BackgroundTransparency = 1
			end
		end)
	end)

	RunService.Heartbeat:Connect(function()
		if not AbilityGateHelper.isDagger(player) then
			fWas, eWas, cWas, qWas = false, false, false, false
			return
		end
		local char = player.Character
		local cam = workspace.CurrentCamera
		if not char or not cam then
			return
		end

		local fDown = UserInputService:IsKeyDown(Enum.KeyCode.F)
		if fDown and not fWas then
			if AbilityGateHelper.canUse(player, char, LightKnivesConstants.ABILITY_ID) then
				local aim = AbilityInputHelper.getAimDirection(char, cam)
				knivesRemote:FireServer(aim.X, aim.Y, aim.Z)
				if setAbilityPressed then
					setAbilityPressed("F", true)
					task.delay(0.12, function()
						if setAbilityPressed then setAbilityPressed("F", false) end
					end)
				end
			end
		end
		fWas = fDown

		local eDown = UserInputService:IsKeyDown(Enum.KeyCode.E)
		if eDown and not eWas then
			if AbilityGateHelper.canUse(player, char, HolyStrikeConstants.ABILITY_ID) then
				local aim = AbilityInputHelper.getAimDirection(char, cam)
				strikeRemote:FireServer(aim.X, aim.Y, aim.Z)
				if setAbilityPressed then
					setAbilityPressed("E", true)
					task.delay(0.12, function()
						if setAbilityPressed then setAbilityPressed("E", false) end
					end)
				end
			end
		end
		eWas = eDown

		local cDown = UserInputService:IsKeyDown(Enum.KeyCode.C)
		if cDown and not cWas then
			if AbilityGateHelper.canUse(player, char, PurifyingLightConstants.ABILITY_ID) then
				purifyRemote:FireServer()
				if setAbilityPressed then
					setAbilityPressed("C", true)
					task.delay(0.12, function()
						if setAbilityPressed then setAbilityPressed("C", false) end
					end)
				end
			end
		end
		cWas = cDown

		local qDown = UserInputService:IsKeyDown(Enum.KeyCode.Q)
		if qDown and not qWas then
			if AbilityGateHelper.canUse(player, char, BlindingFlashConstants.ABILITY_ID) then
				flashRemote:FireServer()
				if setAbilityPressed then
					setAbilityPressed("Q", true)
					task.delay(0.12, function()
						if setAbilityPressed then setAbilityPressed("Q", false) end
					end)
				end
			end
		end
		qWas = qDown
	end)
end

return DaggerAbilitiesClient
