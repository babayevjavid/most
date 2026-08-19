--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterRegistry = require(ReplicatedStorage.Shared.CharacterRegistry)
local MonetConstants = require(ReplicatedStorage.Shared.MonetConstants)
local CharacterAppearanceHelper = require(ReplicatedStorage.Shared.CharacterAppearanceHelper)

local CharacterService = {}

local selectedHero: { [Player]: string } = {}
local pendingDeploy: { [Player]: string } = {}

function CharacterService.getSelectedHero(player: Player): string?
	return selectedHero[player]
end

function CharacterService.applyHeroToCharacter(player: Player, character: Model, heroId: string?)
	local resolvedHeroId = heroId or selectedHero[player]
	if not resolvedHeroId then
		return
	end
	local entry = CharacterRegistry.getById(resolvedHeroId)
	if not entry then
		return
	end

	character:SetAttribute(MonetConstants.HERO_ATTRIBUTE, resolvedHeroId)
	character:SetAttribute(MonetConstants.FORM_ATTRIBUTE, "Monet")
	character:SetAttribute(MonetConstants.ENERGY_ATTRIBUTE, entry.maxEnergy)
	character:SetAttribute(MonetConstants.MAX_ENERGY_ATTRIBUTE, entry.maxEnergy)

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.MaxHealth = entry.healthMonet
		humanoid.Health = entry.healthMonet
	end

	task.defer(function()
		if character.Parent then
			CharacterAppearanceHelper.cacheDefaults(character)
			CharacterAppearanceHelper.applyFormAppearance(character, "Monet")
		end
	end)
end

function CharacterService.setHero(player: Player, heroId: string): boolean
	local entry = CharacterRegistry.getById(heroId)
	if not entry then
		return false
	end
	selectedHero[player] = heroId
	pendingDeploy[player] = heroId
	return true
end

function CharacterService.getForm(character: Model): "Monet" | "Penance"
	local form = character:GetAttribute(MonetConstants.FORM_ATTRIBUTE)
	if form == "Penance" then
		return "Penance"
	end
	return "Monet"
end

function CharacterService.toggleForm(character: Model)
	local heroId = character:GetAttribute(MonetConstants.HERO_ATTRIBUTE)
	if heroId ~= "monet_st_croix" then
		return
	end

	local entry = CharacterRegistry.getById("monet_st_croix")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not entry or not humanoid then
		return
	end

	local current = CharacterService.getForm(character)
	if current == "Monet" then
		character:SetAttribute(MonetConstants.FORM_ATTRIBUTE, "Penance")
		humanoid.MaxHealth = entry.healthPenance
		if humanoid.Health > entry.healthPenance then
			humanoid.Health = entry.healthPenance
		end
		CharacterAppearanceHelper.applyFormAppearance(character, "Penance")
	else
		character:SetAttribute(MonetConstants.FORM_ATTRIBUTE, "Monet")
		humanoid.MaxHealth = entry.healthMonet
		if humanoid.Health > entry.healthMonet then
			humanoid.Health = entry.healthMonet
		end
		CharacterAppearanceHelper.applyFormAppearance(character, "Monet")
	end
end

function CharacterService.regenEnergy(character: Model, dt: number)
	local energy = character:GetAttribute(MonetConstants.ENERGY_ATTRIBUTE)
	local maxEnergy = character:GetAttribute(MonetConstants.MAX_ENERGY_ATTRIBUTE)
	if type(energy) ~= "number" or type(maxEnergy) ~= "number" then
		return
	end
	if energy < maxEnergy then
		character:SetAttribute(MonetConstants.ENERGY_ATTRIBUTE, math.min(maxEnergy, energy + 10 * dt))
	end
end

function CharacterService.init()
	local selectHero = require(ReplicatedStorage.Shared.Remotes).getEvent("SelectHero")
	selectHero.OnServerEvent:Connect(function(player: Player, heroId: any)
		if type(heroId) ~= "string" then
			return
		end
		if not CharacterService.setHero(player, heroId) then
			return
		end
		player:LoadCharacter()
	end)

	local function onCharacterAdded(player: Player, character: Model)
		local deployId = pendingDeploy[player]
		if deployId then
			pendingDeploy[player] = nil
			task.defer(function()
				if character.Parent then
					CharacterService.applyHeroToCharacter(player, character, deployId)
				end
			end)
		end
	end

	local function hookPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
		player.CharacterRemoving:Connect(function(character)
			CharacterAppearanceHelper.clearCache(character)
		end)
	end

	Players.PlayerAdded:Connect(hookPlayer)
	for _, player in Players:GetPlayers() do
		hookPlayer(player)
	end
end

return CharacterService
