--!strict
--[[ Client bootstrap: character selection, deploy transition, gameplay HUD, reset flow. ]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CharacterConfig"))
local ParticleHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ParticleHelper"))
local CharacterSelectionUI = require(script:WaitForChild("CharacterSelectionUI"))
local DeployTransition = require(script:WaitForChild("DeployTransition"))
local DayCycleHUD = require(script:WaitForChild("DayCycleHUD"))
local GameplayHUD = require(script:WaitForChild("GameplayHUD"))
local InventoryUI = require(script:WaitForChild("InventoryUI"))
local InventoryEquipmentClient = require(script:WaitForChild("InventoryEquipmentClient"))
local PolarisAbilitiesClient = require(script:WaitForChild("PolarisAbilitiesClient"))
local HavokAbilitiesClient = require(script:WaitForChild("HavokAbilitiesClient"))
local HeadLookClient = require(script:WaitForChild("HeadLookClient"))
local SettingsUI = require(script:WaitForChild("SettingsUI"))
local StatusEffectsClient = require(script:WaitForChild("StatusEffectsClient"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

local selectedCharacterId: string? = player:GetAttribute("SelectedCharacter") :: string?

local remotes = ReplicatedStorage:WaitForChild("Remotes")

local gameplayHUD = GameplayHUD.create(playerGui)
local dayCycleHUD = DayCycleHUD.create(playerGui)
local inventoryUI = InventoryUI.create(
	playerGui,
	remotes:WaitForChild("InventorySwap") :: RemoteEvent,
	remotes:WaitForChild("InventoryEquip") :: RemoteEvent
)
InventoryEquipmentClient.start(player)
local settingsUI = SettingsUI.create(playerGui, remotes:WaitForChild("DayCycleAdmin") :: RemoteEvent)

local selectionUI: CharacterSelectionUI.SelectionController
local selectionScreenVisible = false
local gameplayUIVisible = false

local function showGameplayUI(characterId: string?)
	if characterId then
		gameplayHUD.show(characterId)
	else
		gameplayHUD.show()
	end
	dayCycleHUD.show()
	inventoryUI.show()
	settingsUI.show()
	gameplayUIVisible = true
end

local function hideGameplayUI()
	gameplayHUD.hide()
	dayCycleHUD.hide()
	inventoryUI.hide()
	settingsUI.hide()
	gameplayUIVisible = false
end

local function clearSelection()
	selectedCharacterId = nil
	player:SetAttribute("SelectedCharacter", nil)
	local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
	if remotesFolder then
		local selectRemote = remotesFolder:FindFirstChild("SelectCharacter")
		if selectRemote and selectRemote:IsA("RemoteEvent") then
			selectRemote:FireServer("")
		end
	end
end

local function closeSelection()
	selectionScreenVisible = false
	selectionUI.hide()
end

local function deployCharacter(characterId: string)
	local entry = CharacterConfig.getCharacter(characterId)
	if not entry or entry.locked then
		return
	end

	DeployTransition.play(playerGui, entry.displayName, entry.accentColor, function()
		selectedCharacterId = characterId
		player:SetAttribute("SelectedCharacter", characterId)
		local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
		if remotesFolder then
			local selectRemote = remotesFolder:FindFirstChild("SelectCharacter")
			if selectRemote and selectRemote:IsA("RemoteEvent") then
				selectRemote:FireServer(characterId)
			end
		end
		closeSelection()
		showGameplayUI(characterId)
		local character = player.Character
		if character then
			gameplayHUD.bindCharacter(character)
		end
	end)
end

selectionUI = CharacterSelectionUI.create({
	playerGui = playerGui,
	onCharacterSelected = deployCharacter,
})

local function openSelection()
	DeployTransition.cancel()
	hideGameplayUI()
	selectionScreenVisible = true
	selectionUI.show()
end

local function onCharacterAdded(character: Model)
	if selectedCharacterId then
		showGameplayUI(selectedCharacterId)
		gameplayHUD.bindCharacter(character)
		closeSelection()
	elseif gameplayUIVisible then
		gameplayHUD.refreshViewport()
	else
		openSelection()
	end
end

local function onCharacterRemoving()
	if selectedCharacterId then
		clearSelection()
	end
	openSelection()
end

player.CharacterAdded:Connect(function(character: Model)
	onCharacterAdded(character)
end)
player.CharacterRemoving:Connect(onCharacterRemoving)

if selectedCharacterId and player.Character then
	closeSelection()
	showGameplayUI(selectedCharacterId)
	gameplayHUD.bindCharacter(player.Character)
elseif player.Character then
	onCharacterAdded(player.Character)
else
	openSelection()
end

local selectRemote = remotes:WaitForChild("SelectCharacter") :: RemoteEvent
if selectedCharacterId then
	selectRemote:FireServer(selectedCharacterId)
end

local setAbilityPressed = function(key: string, pressed: boolean)
	gameplayHUD.setAbilityPressed(key, pressed)
end

local setAbilityCharge = function(key: string, ratio: number)
	gameplayHUD.setAbilityCharge(key, ratio)
end

PolarisAbilitiesClient.start(
	remotes:WaitForChild("MagneticFlightToggle") :: RemoteEvent,
	remotes:WaitForChild("MagneticFlightInput") :: RemoteEvent,
	remotes:WaitForChild("FerrokinesisRequest") :: RemoteEvent,
	remotes:WaitForChild("FerrokinesisUpdate") :: RemoteEvent,
	remotes:WaitForChild("FerrokinesisThrow") :: RemoteEvent,
	remotes:WaitForChild("FerrokinesisEnd") :: RemoteEvent,
	remotes:WaitForChild("MagneticPulseStart") :: RemoteEvent,
	remotes:WaitForChild("MagneticPulseAim") :: RemoteEvent,
	remotes:WaitForChild("MagneticPulseRelease") :: RemoteEvent,
	remotes:WaitForChild("OrbitalStrikesToggle") :: RemoteEvent,
	remotes:WaitForChild("OrbitalStrikesThrow") :: RemoteEvent,
	remotes:WaitForChild("OrbitalStrikesAim") :: RemoteEvent,
	remotes:WaitForChild("MetalLanceStart") :: RemoteEvent,
	remotes:WaitForChild("MetalLanceLaunch") :: RemoteEvent,
	remotes:WaitForChild("MetalLanceEnd") :: RemoteEvent,
	player,
	setAbilityPressed
)

HavokAbilitiesClient.start(
	remotes:WaitForChild("HavokSiphon") :: RemoteEvent,
	remotes:WaitForChild("HavokEnergyBurst") :: RemoteEvent,
	remotes:WaitForChild("HavokBeamStart") :: RemoteEvent,
	remotes:WaitForChild("HavokBeamAim") :: RemoteEvent,
	remotes:WaitForChild("HavokBeamEnd") :: RemoteEvent,
	remotes:WaitForChild("HavokKineticSurge") :: RemoteEvent,
	remotes:WaitForChild("HavokEnergyBlastStart") :: RemoteEvent,
	remotes:WaitForChild("HavokEnergyBlastAim") :: RemoteEvent,
	remotes:WaitForChild("HavokEnergyBlastRelease") :: RemoteEvent,
	player,
	setAbilityPressed
)

local SunspotAbilitiesClient = require(script:WaitForChild("SunspotAbilitiesClient"))
SunspotAbilitiesClient.start(
	remotes:WaitForChild("SolarFlightToggle") :: RemoteEvent,
	remotes:WaitForChild("SolarFlightInput") :: RemoteEvent,
	remotes:WaitForChild("SunUppercut") :: RemoteEvent,
	remotes:WaitForChild("SolarFlareStart") :: RemoteEvent,
	remotes:WaitForChild("SolarFlareAim") :: RemoteEvent,
	remotes:WaitForChild("SolarFlareRelease") :: RemoteEvent,
	remotes:WaitForChild("SunspotPhotosynthesis") :: RemoteEvent,
	remotes:WaitForChild("BlackSunCharge") :: RemoteEvent,
	remotes:WaitForChild("BlackSunThrow") :: RemoteEvent,
	player,
	setAbilityPressed,
	setAbilityCharge
)

local PsylockeAbilitiesClient = require(script:WaitForChild("PsylockeAbilitiesClient"))
PsylockeAbilitiesClient.start(
	remotes:WaitForChild("PsylockePsiBlade") :: RemoteEvent,
	remotes:WaitForChild("PsylockeButterflyStep") :: RemoteEvent,
	remotes:WaitForChild("PsylockePsychicSlash") :: RemoteEvent,
	remotes:WaitForChild("PsylockeFocusField") :: RemoteEvent,
	remotes:WaitForChild("PsylockeAstralAssault") :: RemoteEvent,
	player,
	setAbilityPressed
)

StatusEffectsClient.start(player)
HeadLookClient.start(player)

workspace.DescendantAdded:Connect(function(inst)
	if inst:IsA("ParticleEmitter") then
		if inst:GetAttribute("SunspotFlightParticle") == true then
			return
		end
		ParticleHelper.enableAndEmit(inst)
	end
end)
