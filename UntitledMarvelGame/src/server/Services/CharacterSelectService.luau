--!strict



local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")



local HUDTheme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("HUDTheme"))

local HeroRegistry = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("HeroRegistry"))



local AbilityService = require(script.Parent.AbilityService)

local OverheadService = require(script.Parent.OverheadService)

local PlayerStateService = require(script.Parent.PlayerStateService)

local FlightService = require(script.Parent.FlightService)
local BeamService = require(script.Parent.BeamService)
local ProjectileFlight = require(script.Parent.ProjectileFlight)

local RemoteSetup = require(script.Parent.RemoteSetup)

local ShieldService = require(script.Parent.ShieldService)

local SpawnService = require(script.Parent.SpawnService)

local SprintService = require(script.Parent.SprintService)

local TelekinesisService = require(script.Parent.TelekinesisService)



local CharacterSelectService = {}



local remotes: RemoteSetup.RemoteFolder? = nil



local function fireStatUpdate(player: Player)

	if not remotes then

		return

	end

	remotes.StatUpdate:FireClient(player, PlayerStateService.getStatPayload(player))

end



local function fireCooldown(player: Player, abilityId: string, duration: number)

	if not remotes then

		return

	end

	remotes.CooldownUpdate:FireClient(player, abilityId, duration)

end



local function applyPlayerOverhead(player: Player, heroId: string)

	local character = player.Character

	if not character then

		return

	end

	local heroDef = HeroRegistry[heroId]

	if not heroDef then

		return

	end

	local accent = HUDTheme.HeroAccents[heroId]

	OverheadService.setPlayerHero(character, player, heroDef.DisplayName, accent)

end



local function requireReselect(player: Player)

	PlayerStateService.clearHero(player)

	AbilityService.cleanupPlayer(player)

	SprintService.setSprinting(player, false)

	if remotes then

		remotes.RequireReselect:FireClient(player)

	end

end



local function confirmHero(player: Player, heroId: string)

	local layout = HeroRegistry.getAbilityLayout(heroId)

	if not layout then

		return

	end

	PlayerStateService.setHero(player, heroId)

	SprintService.applyWalkSpeed(player)

	applyPlayerOverhead(player, heroId)

	if remotes then

		remotes.HeroConfirmed:FireClient(player, heroId, layout)

		fireStatUpdate(player)

	end

end



local function bindCharacter(player: Player, character: Model)

	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?

	if not humanoid then

		return

	end



	OverheadService.attachPlayer(character, player)



	local state = PlayerStateService.get(player)

	if state.HeroId then

		applyPlayerOverhead(player, state.HeroId)

		SprintService.applyWalkSpeed(player)

	end



	humanoid.Died:Connect(function()

		PlayerStateService.clearHero(player)

		AbilityService.cleanupPlayer(player)

		SprintService.setSprinting(player, false)

		OverheadService.hidePlayerPlate(character)

	end)



	humanoid.HealthChanged:Connect(function()

		PlayerStateService.syncFromCharacter(player)

		fireStatUpdate(player)

	end)

end



local function onPlayerAdded(player: Player)

	PlayerStateService.initPlayer(player)



	player.CharacterAdded:Connect(function(character)

		bindCharacter(player, character)

		SpawnService.teleportCharacter(character)



		local state = PlayerStateService.get(player)

		if not state.HeroId then

			requireReselect(player)

		else

			fireStatUpdate(player)

		end

	end)



	if player.Character then

		bindCharacter(player, player.Character)

	end

end



function CharacterSelectService.setup(remoteFolder: RemoteSetup.RemoteFolder)

	remotes = remoteFolder



	AbilityService.setup({

		onCooldown = fireCooldown,

		onStatUpdate = fireStatUpdate,

	})



	TelekinesisService.setup(

		remoteFolder.TelekinesisRequest,

		remoteFolder.TelekinesisUpdate,

		remoteFolder.TelekinesisThrow,

		remoteFolder.TelekinesisEnd,

		fireStatUpdate,

		fireCooldown

	)

	TelekinesisService.startUpdateLoop()



	ShieldService.setup(remoteFolder.ShieldSetActive, fireStatUpdate, fireCooldown)

	BeamService.setup(remoteFolder.ChaosBeamSetActive, remoteFolder.ChaosBeamLookUpdate, fireStatUpdate, fireCooldown)

	FlightService.setup(remoteFolder.FlightToggle, remoteFolder.FlightInput, fireStatUpdate, fireCooldown)
	FlightService.startUpdateLoop()

	ProjectileFlight.setupSteerRemote(remoteFolder.ProjectileSteerUpdate)



	SprintService.setup(fireStatUpdate)

	SprintService.startLoop()

	OverheadService.init()

	SpawnService.init()



	remoteFolder.SelectHero.OnServerEvent:Connect(function(player: Player, heroId: string)

		if typeof(heroId) ~= "string" then

			return

		end

		if not HeroRegistry[heroId] then

			return

		end

		confirmHero(player, heroId)

	end)



	remoteFolder.UseAbility.OnServerEvent:Connect(function(

		player: Player,

		abilityId: string,

		aimX: number?,

		aimY: number?,

		aimZ: number?,

		steerToken: string?

	)

		if typeof(abilityId) ~= "string" then

			return

		end

		local aimDirection: Vector3? = nil

		if typeof(aimX) == "number" and typeof(aimY) == "number" and typeof(aimZ) == "number" then

			aimDirection = Vector3.new(aimX, aimY, aimZ)

		end

		local token: string? = if type(steerToken) == "string" and #steerToken > 0 then steerToken else nil

		AbilityService.useAbility(player, abilityId, aimDirection, token)

	end)



	remoteFolder.SetSprinting.OnServerEvent:Connect(function(player: Player, isSprinting: boolean)

		if typeof(isSprinting) ~= "boolean" then

			return

		end

		SprintService.setSprinting(player, isSprinting)

	end)



	for _, player in Players:GetPlayers() do

		onPlayerAdded(player)

	end

	Players.PlayerAdded:Connect(onPlayerAdded)

	Players.PlayerRemoving:Connect(function(player)

		AbilityService.cleanupPlayer(player)

		SprintService.clearPlayer(player)

		PlayerStateService.removePlayer(player)

	end)



	PlayerStateService.startRegenLoop(fireStatUpdate)

end



return CharacterSelectService

