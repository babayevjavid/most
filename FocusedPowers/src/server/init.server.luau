local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CharacterConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CharacterConfig"))
local CharacterAppearanceHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CharacterAppearanceHelper"))
local ResourceConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ResourceConstants"))
local ParticleHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ParticleHelper"))
local CharacterOverheadUI = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CharacterOverheadUI"))

local DeathService = require(script:WaitForChild("DeathService"))
local EnergyService = require(script:WaitForChild("EnergyService"))
local ResourceService = require(script:WaitForChild("ResourceService"))
local InventoryService = require(script:WaitForChild("InventoryService"))
local ProgressionService = require(script:WaitForChild("ProgressionService"))
local SteerableBoltService = require(script:WaitForChild("SteerableBoltService"))
local FerrokinesisService = require(script:WaitForChild("FerrokinesisService"))
local HeadLookService = require(script:WaitForChild("HeadLookService"))
local HavokAbilitiesService = require(script:WaitForChild("HavokAbilitiesService"))
local PolarisAbilitiesService = require(script:WaitForChild("PolarisAbilitiesService"))
local SunspotAbilitiesService = require(script:WaitForChild("SunspotAbilitiesService"))
local PsylockeAbilitiesService = require(script:WaitForChild("PsylockeAbilitiesService"))
local DayCycleService = require(script:WaitForChild("DayCycleService"))
local AdminHelper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AdminHelper"))

local function getOrCreateRemotesFolder(): Folder
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end
	return folder :: Folder
end

local function getOrCreateRemote(name: string): RemoteEvent
	local folder = getOrCreateRemotesFolder()
	local remote = folder:FindFirstChild(name)
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
	end
	return remote :: RemoteEvent
end

local function initResourcesForCharacter(plr: Player, char: Model, characterId: string)
	if ResourceConstants.RESOURCE_CHARACTERS[characterId] then
		ResourceService.initCharacter(char, characterId)
	end
	if characterId == "Havok" then
		HavokAbilitiesService.initCharacter(char)
	elseif characterId == "Sunspot" then
		SunspotAbilitiesService.initCharacter(char)
	elseif characterId == "Psylocke" then
		PsylockeAbilitiesService.initCharacter(char)
	end
	CharacterOverheadUI.bind(char, plr, characterId)
end

local function syncOverheadForPlayer(plr: Player)
	local char = plr.Character
	local charId = plr:GetAttribute("SelectedCharacter")
	if char and typeof(charId) == "string" and charId ~= "" then
		local entry = CharacterConfig.getCharacter(charId)
		if entry and not entry.locked then
			CharacterOverheadUI.bind(char, plr, charId)
			return
		end
	end
	if char then
		CharacterOverheadUI.unbind(char)
	end
end

-- Polaris remotes
local magneticFlightToggle = getOrCreateRemote("MagneticFlightToggle")
local magneticFlightInput = getOrCreateRemote("MagneticFlightInput")
local ferrokinesisRequest = getOrCreateRemote("FerrokinesisRequest")
local ferrokinesisUpdate = getOrCreateRemote("FerrokinesisUpdate")
local ferrokinesisThrow = getOrCreateRemote("FerrokinesisThrow")
local ferrokinesisEnd = getOrCreateRemote("FerrokinesisEnd")
local magneticPulseStart = getOrCreateRemote("MagneticPulseStart")
local magneticPulseAim = getOrCreateRemote("MagneticPulseAim")
local magneticPulseRelease = getOrCreateRemote("MagneticPulseRelease")
local orbitalStrikesToggle = getOrCreateRemote("OrbitalStrikesToggle")
local orbitalStrikesThrow = getOrCreateRemote("OrbitalStrikesThrow")
local orbitalStrikesAim = getOrCreateRemote("OrbitalStrikesAim")
local metalLanceStart = getOrCreateRemote("MetalLanceStart")
local metalLanceLaunch = getOrCreateRemote("MetalLanceLaunch")
local metalLanceEnd = getOrCreateRemote("MetalLanceEnd")

local havokSiphon = getOrCreateRemote("HavokSiphon")
local havokBurst = getOrCreateRemote("HavokEnergyBurst")
local havokBeamStart = getOrCreateRemote("HavokBeamStart")
local havokBeamAim = getOrCreateRemote("HavokBeamAim")
local havokBeamEnd = getOrCreateRemote("HavokBeamEnd")
local havokSurge = getOrCreateRemote("HavokKineticSurge")
local havokBlastStart = getOrCreateRemote("HavokEnergyBlastStart")
local havokBlastAim = getOrCreateRemote("HavokEnergyBlastAim")
local havokBlastRelease = getOrCreateRemote("HavokEnergyBlastRelease")
local dayCycleAdmin = getOrCreateRemote("DayCycleAdmin")

local solarFlightToggle = getOrCreateRemote("SolarFlightToggle")
local solarFlightInput = getOrCreateRemote("SolarFlightInput")
local sunUppercut = getOrCreateRemote("SunUppercut")
local solarFlareStart = getOrCreateRemote("SolarFlareStart")
local solarFlareAim = getOrCreateRemote("SolarFlareAim")
local solarFlareRelease = getOrCreateRemote("SolarFlareRelease")
local sunspotPhotosynthesis = getOrCreateRemote("SunspotPhotosynthesis")
local blackSunCharge = getOrCreateRemote("BlackSunCharge")
local blackSunThrow = getOrCreateRemote("BlackSunThrow")

local selectCharacter = getOrCreateRemote("SelectCharacter")
local redeemCode = getOrCreateRemote("RedeemCode")
local inventorySwap = getOrCreateRemote("InventorySwap")
local inventoryEquip = getOrCreateRemote("InventoryEquip")

local psylockePsiBlade = getOrCreateRemote("PsylockePsiBlade")
local psylockeButterflyStep = getOrCreateRemote("PsylockeButterflyStep")
local psylockePsychicSlash = getOrCreateRemote("PsylockePsychicSlash")
local psylockeFocusField = getOrCreateRemote("PsylockeFocusField")
local psylockeAstralAssault = getOrCreateRemote("PsylockeAstralAssault")

ProgressionService.setup(redeemCode)
InventoryService.setup(inventorySwap, inventoryEquip)
DeathService.setup()
HeadLookService.setup()

selectCharacter.OnServerEvent:Connect(function(plr: Player, characterId: unknown)
	if characterId == nil or (typeof(characterId) == "string" and characterId == "") then
		plr:SetAttribute("SelectedCharacter", nil)
		return
	end
	if typeof(characterId) == "string" then
		local entry = CharacterConfig.getCharacter(characterId)
		if not entry or entry.locked then
			return
		end
		plr:SetAttribute("SelectedCharacter", characterId)

		local char = plr.Character
		local needsSpawn = not char
		if char then
			local hum = char:FindFirstChildOfClass("Humanoid")
			needsSpawn = not hum or hum.Health <= 0
		end
		if needsSpawn then
			plr:LoadCharacter()
		else
			CharacterAppearanceHelper.applyHeroAppearance(char :: Model, characterId)
			initResourcesForCharacter(plr, char :: Model, characterId)
		end
	end
end)

FerrokinesisService.setup(ferrokinesisRequest, ferrokinesisUpdate, ferrokinesisThrow, ferrokinesisEnd)
PolarisAbilitiesService.setup(
	magneticFlightToggle,
	magneticFlightInput,
	magneticPulseStart,
	magneticPulseAim,
	magneticPulseRelease,
	orbitalStrikesToggle,
	orbitalStrikesThrow,
	orbitalStrikesAim,
	metalLanceStart,
	metalLanceLaunch,
	metalLanceEnd
)

HavokAbilitiesService.setup(
	havokSiphon,
	havokBurst,
	havokBeamStart,
	havokBeamAim,
	havokBeamEnd,
	havokSurge,
	havokBlastStart,
	havokBlastAim,
	havokBlastRelease
)

SunspotAbilitiesService.setup(
	solarFlightToggle,
	solarFlightInput,
	sunUppercut,
	solarFlareStart,
	solarFlareAim,
	solarFlareRelease,
	sunspotPhotosynthesis,
	blackSunCharge,
	blackSunThrow
)

PsylockeAbilitiesService.setup(
	psylockePsiBlade,
	psylockeButterflyStep,
	psylockePsychicSlash,
	psylockeFocusField,
	psylockeAstralAssault
)

EnergyService.setStopCallbacks(
	function(plr) PolarisAbilitiesService.forceEndFlight(plr) end,
	function(plr) FerrokinesisService.forceEnd(plr) end,
	function(plr) PolarisAbilitiesService.forceEndOrbital(plr) end,
	function(plr) PolarisAbilitiesService.forceEndLance(plr) end
)

ResourceService.registerStopCallback("IsConcussiveBeamActive", function(plr)
	HavokAbilitiesService.forceEndBeam(plr)
end)

ResourceService.registerStopCallback("IsSolarFlying", function(plr)
	SunspotAbilitiesService.forceEndFlight(plr)
end)

ResourceService.registerStopCallback("IsPhotosynthesisActive", function(plr)
	SunspotAbilitiesService.forceEndPhotosynthesis(plr)
end)

ResourceService.registerStopCallback("IsBlackSunCharging", function(plr)
	SunspotAbilitiesService.forceEndBlackSun(plr)
end)

local function hookPlayer(plr: Player)
	plr.CharacterAdded:Connect(function(char)
		local characterId = plr:GetAttribute("SelectedCharacter")
		if typeof(characterId) == "string" and characterId ~= "" then
			CharacterAppearanceHelper.applyHeroAppearance(char, characterId)
			initResourcesForCharacter(plr, char, characterId)
		else
			task.defer(function()
				syncOverheadForPlayer(plr)
			end)
		end
	end)
	plr:GetAttributeChangedSignal("SelectedCharacter"):Connect(function()
		syncOverheadForPlayer(plr)
	end)
	if plr.Character then
		local characterId = plr:GetAttribute("SelectedCharacter")
		if typeof(characterId) == "string" and characterId ~= "" then
			CharacterAppearanceHelper.applyHeroAppearance(plr.Character, characterId)
			initResourcesForCharacter(plr, plr.Character, characterId)
		else
			syncOverheadForPlayer(plr)
		end
	end
end

Players.PlayerAdded:Connect(hookPlayer)
for _, plr in Players:GetPlayers() do
	hookPlayer(plr)
end

DayCycleService.start()
DayCycleService.setup(dayCycleAdmin)

local function hookAdmin(plr: Player)
	AdminHelper.tagPlayer(plr)
end

Players.PlayerAdded:Connect(hookAdmin)
for _, plr in Players:GetPlayers() do
	hookAdmin(plr)
end

RunService.Heartbeat:Connect(function(dt)
	local now = tick()
	FerrokinesisService.update(dt, now)
	PolarisAbilitiesService.update(dt)
	HavokAbilitiesService.update(dt)
	SunspotAbilitiesService.update(dt)
	SteerableBoltService.update(dt)
	DayCycleService.update(dt)
	for _, plr in Players:GetPlayers() do
		ResourceService.update(plr, dt)
	end
end)

Players.PlayerRemoving:Connect(function(plr)
	FerrokinesisService.onPlayerRemoving(plr)
	PolarisAbilitiesService.onPlayerRemoving(plr)
	HavokAbilitiesService.onPlayerRemoving(plr)
	SunspotAbilitiesService.onPlayerRemoving(plr)
	SteerableBoltService.onPlayerRemoving(plr)
end)

workspace.DescendantAdded:Connect(function(inst)
	if inst:IsA("ParticleEmitter") then
		ParticleHelper.enableAndEmit(inst)
	end
end)
