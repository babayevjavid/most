--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local AbilityController = require(script.Parent.AbilityController)
local CharacterSelectUI = require(script.Parent.Parent.UI.CharacterSelectUI)
local MainHUD = require(script.Parent.Parent.UI.MainHUD)

local UIController = {}

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local selectHeroRemote = remotesFolder:WaitForChild(Remotes.SelectHero) :: RemoteEvent
local heroConfirmedRemote = remotesFolder:WaitForChild(Remotes.HeroConfirmed) :: RemoteEvent
local requireReselectRemote = remotesFolder:WaitForChild(Remotes.RequireReselect) :: RemoteEvent
local statUpdateRemote = remotesFolder:WaitForChild(Remotes.StatUpdate) :: RemoteEvent
local sprintRemote = remotesFolder:WaitForChild(Remotes.SetSprinting) :: RemoteEvent

local selectUI: CharacterSelectUI.CharacterSelectController
local mainHUD: MainHUD.MainHUDController

function UIController.init()
	local player = Players.LocalPlayer

	selectUI = CharacterSelectUI.create(function(heroId: string)
		selectHeroRemote:FireServer(heroId)
	end)

	mainHUD = MainHUD.create()

	AbilityController.setup(function(abilityId, duration)
		mainHUD:UpdateCooldown(abilityId, duration)
	end)

	heroConfirmedRemote.OnClientEvent:Connect(function(heroId: string, layout: any)
		AbilityController.setHero(heroId, layout)
		selectUI:Hide()
		mainHUD:Show(heroId, layout)
	end)

	requireReselectRemote.OnClientEvent:Connect(function()
		AbilityController.clearHero()
		sprintRemote:FireServer(false)
		mainHUD:Hide()
		selectUI:Show()
	end)

	statUpdateRemote.OnClientEvent:Connect(function(payload: { [string]: any })
		if mainHUD.Gui.Enabled then
			mainHUD:UpdateStats(payload)
		end
	end)

	player.CharacterAdded:Connect(function(_character)
		task.defer(function()
			if mainHUD.Gui.Enabled then
				mainHUD:RefreshAvatar(player)
			end
		end)
	end)

	RunService.RenderStepped:Connect(function()
		if mainHUD.Gui.Enabled then
			mainHUD:TickCooldowns()
		end
	end)

	selectUI:Show()
end

return UIController
