--!strict

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function disableNoisyLegacyScripts(root: Instance)
	for _, inst in root:GetDescendants() do
		if (inst:IsA("Script") or inst:IsA("LocalScript")) and inst.Name == "Game sounds" then
			inst.Disabled = true
		end
	end
end

disableNoisyLegacyScripts(game)
game.DescendantAdded:Connect(function(inst)
	if (inst:IsA("Script") or inst:IsA("LocalScript")) and inst.Name == "Game sounds" then
		inst.Disabled = true
	end
end)

local CharacterService = require(script.CharacterService)
local HexFlightService = require(script.HexFlightService)
local PhotonFlightService = require(script.PhotonFlightService)
local ProjectileThrowerService = require(script.ProjectileThrowerService)
local TelekineticThrowerService = require(script.TelekineticThrowerService)
local DamagerService = require(script.DamagerService)
local RagdollService = require(script.RagdollService)
local ScarletWitchService = require(script.ScarletWitchService)
local CaptainMarvelService = require(script.CaptainMarvelService)
local LokiService = require(script.LokiService)
local DaggerService = require(script.DaggerService)
local MarvelGirlService = require(script.MarvelGirlService)
local IcemanService = require(script.IcemanService)
local InvisibleWomanService = require(script.InvisibleWomanService)
local TelekinesisService = require(script.TelekinesisService)
local SprintService = require(script.SprintService)
local NameplateService = require(script.NameplateService)
local CombatService = require(script.CombatService)
local BeamClashService = require(script.BeamClashService)
local FallLandingService = require(script.FallLandingService)
local PlayerDataService = require(script.PlayerDataService)
local EconomyService = require(script.EconomyService)
local GameConstants = require(ReplicatedStorage.Shared.GameConstants)
local ProjectileHelper = require(ReplicatedStorage.Shared.ProjectileHelper)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

Remotes.init()
require(ReplicatedStorage.Shared.VfxHelper)
require(ReplicatedStorage.Shared.SmartBonePatch).install()

PlayerDataService.init()
EconomyService.init()
CharacterService.init()
SprintService.init()
NameplateService.init()
CombatService.init()
RagdollService.init()
FallLandingService.init()
HexFlightService.init()
PhotonFlightService.init()
TelekinesisService.init()
ScarletWitchService.init()
CaptainMarvelService.init()
LokiService.init()
DaggerService.init()
MarvelGirlService.init()
InvisibleWomanService.init()
IcemanService.init()
ProjectileThrowerService.init()
TelekineticThrowerService.init()
DamagerService.init()

-- Interrupt active abilities when the caster is ragdolled (beam clash excluded inside RagdollService)
RagdollService.onAbilityInterrupt(function(player: Player, _character: Model)
	ScarletWitchService.cancelAll(player)
	CaptainMarvelService.cancelAll(player)
	LokiService.cancelAll(player)
	DaggerService.cancelAll(player)
	MarvelGirlService.cancelAll(player)
	InvisibleWomanService.cancelAll(player)
	IcemanService.cancelAll(player)
	HexFlightService.endFlight(player, false)
	PhotonFlightService.endFlight(player, false)
	TelekinesisService.release(player)
end)

do
	local ok, err = pcall(function()
		BeamClashService.init()
		BeamClashService.registerSegmentProvider(ScarletWitchService.getActiveBeamSegments)
		BeamClashService.registerSegmentProvider(CaptainMarvelService.getActiveBeamSegments)
	end)
	if not ok then
		warn("[MCU Server] BeamClashService failed to init:", err)
	end
end

RunService.Heartbeat:Connect(function(dt)
	HexFlightService.update(dt)
	PhotonFlightService.update(dt)
	TelekinesisService.update(dt)
	ScarletWitchService.update(dt)
	CaptainMarvelService.update(dt)
	LokiService.update(dt)
	DaggerService.update(dt)
	MarvelGirlService.update(dt)
	InvisibleWomanService.update(dt)
	ProjectileHelper.update(dt)
	ProjectileThrowerService.update(dt)
	TelekineticThrowerService.update(dt)
	DamagerService.update(dt)
	SprintService.update(dt)
	FallLandingService.update(dt)
	-- After SprintService so high-fall landing lock wins over sprint walk speed
	IcemanService.update(dt)
	CombatService.update()
	pcall(function()
		BeamClashService.update(dt)
	end)

	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character and character:GetAttribute(GameConstants.HERO_ATTRIBUTE) then
			CharacterService.regenEnergy(character, dt)
		end
	end
end)
