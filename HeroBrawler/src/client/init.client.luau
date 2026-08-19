--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AbilityInput = require(script.AbilityInput)
local CharacterSelectUI = require(script.CharacterSelectUI)
local GameplayHUD = require(script.GameplayHUD)
local MonetFlightClient = require(script.MonetFlightClient)
local StatusEffectsHUD = require(script.StatusEffectsHUD)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local MonetConstants = require(ReplicatedStorage.Shared.MonetConstants)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local awaitingDeploy = false

local hud = GameplayHUD.create(playerGui)
local selection = CharacterSelectUI.create(playerGui, function(heroId: string)
	awaitingDeploy = true
	-- CharacterSelectUI already hides itself on button click
	Remotes.getEvent("SelectHero"):FireServer(heroId)
end)

AbilityInput.init(player)
MonetFlightClient.init(player)
StatusEffectsHUD.create(playerGui)

local function bindHeroCharacter(character: Model)
	local heroId = character:GetAttribute(MonetConstants.HERO_ATTRIBUTE)
	if type(heroId) ~= "string" or heroId == "" then
		return false
	end
	if not character.Parent then
		return false
	end

	selection.hide()
	hud.show(heroId)
	hud.bindCharacter(character)
	awaitingDeploy = false
	return true
end

local function onCharacterSpawned(character: Model)
	if awaitingDeploy then
		hud.hide()
	else
		selection.show()
		hud.hide()
	end

	if bindHeroCharacter(character) then
		return
	end

	local attrConn: RBXScriptConnection? = nil
	local destroyConn: RBXScriptConnection? = nil

	attrConn = character:GetAttributeChangedSignal(MonetConstants.HERO_ATTRIBUTE):Connect(function()
		if bindHeroCharacter(character) and attrConn then
			attrConn:Disconnect()
			if destroyConn then
				destroyConn:Disconnect()
			end
		end
	end)

	destroyConn = character.Destroying:Connect(function()
		if attrConn then
			attrConn:Disconnect()
		end
	end)
end

player.CharacterAdded:Connect(onCharacterSpawned)

if player.Character then
	onCharacterSpawned(player.Character)
else
	selection.show()
end
