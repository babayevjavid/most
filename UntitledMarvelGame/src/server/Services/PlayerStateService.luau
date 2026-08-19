--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))

export type PlayerState = {
	HeroId: string?,
	Health: number,
	Stamina: number,
	Energy: number,
	Currencies: {
		Blue: number,
		Yellow: number,
	},
	Cooldowns: { [string]: number },
	lastResourceUseAt: number?,
}

local PlayerStateService = {}

local states: { [Player]: PlayerState } = {}

local function defaultState(): PlayerState
	return {
		HeroId = nil,
		Health = Constants.MAX_HEALTH,
		Stamina = Constants.MAX_STAMINA,
		Energy = Constants.MAX_ENERGY,
		Currencies = {
			Blue = 0,
			Yellow = 0,
		},
		Cooldowns = {},
		lastResourceUseAt = nil,
	}
end

function PlayerStateService.initPlayer(player: Player)
	states[player] = defaultState()
end

function PlayerStateService.removePlayer(player: Player)
	states[player] = nil
end

function PlayerStateService.get(player: Player): PlayerState
	if not states[player] then
		states[player] = defaultState()
	end
	return states[player]
end

function PlayerStateService.markResourceUsed(player: Player)
	local state = PlayerStateService.get(player)
	state.lastResourceUseAt = os.clock()
end

function PlayerStateService.canRegenResources(player: Player): boolean
	local state = PlayerStateService.get(player)
	if state.lastResourceUseAt == nil then
		return true
	end
	return os.clock() - state.lastResourceUseAt >= Constants.RESOURCE_REGEN_DELAY
end

function PlayerStateService.setHero(player: Player, heroId: string?)
	local state = PlayerStateService.get(player)
	state.HeroId = heroId
	state.Cooldowns = {}
	state.lastResourceUseAt = nil
	if heroId then
		state.Health = Constants.MAX_HEALTH
		state.Stamina = Constants.MAX_STAMINA
		state.Energy = Constants.MAX_ENERGY
	end
end

function PlayerStateService.clearHero(player: Player)
	PlayerStateService.setHero(player, nil)
end

function PlayerStateService.syncFromCharacter(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local state = PlayerStateService.get(player)
	state.Health = humanoid.Health
	state.Stamina = math.clamp(state.Stamina, 0, Constants.MAX_STAMINA)
	state.Energy = math.clamp(state.Energy, 0, Constants.MAX_ENERGY)
end

function PlayerStateService.setCooldown(player: Player, abilityId: string, endTime: number)
	local state = PlayerStateService.get(player)
	state.Cooldowns[abilityId] = endTime
end

function PlayerStateService.isOnCooldown(player: Player, abilityId: string): boolean
	local state = PlayerStateService.get(player)
	local endTime = state.Cooldowns[abilityId]
	return endTime ~= nil and endTime > os.clock()
end

function PlayerStateService.spendEnergy(player: Player, amount: number): boolean
	local state = PlayerStateService.get(player)
	if state.Energy < amount then
		return false
	end
	state.Energy -= amount
	PlayerStateService.markResourceUsed(player)
	return true
end

function PlayerStateService.spendStamina(player: Player, amount: number): boolean
	local state = PlayerStateService.get(player)
	if state.Stamina < amount then
		return false
	end
	state.Stamina -= amount
	PlayerStateService.markResourceUsed(player)
	return true
end

function PlayerStateService.getStatPayload(player: Player): { [string]: any }
	local state = PlayerStateService.get(player)
	PlayerStateService.syncFromCharacter(player)
	return {
		Health = state.Health,
		MaxHealth = Constants.MAX_HEALTH,
		Stamina = state.Stamina,
		MaxStamina = Constants.MAX_STAMINA,
		Energy = state.Energy,
		MaxEnergy = Constants.MAX_ENERGY,
		Blue = state.Currencies.Blue,
		Yellow = state.Currencies.Yellow,
	}
end

function PlayerStateService.startRegenLoop(onStatUpdate: (player: Player) -> ())
	task.spawn(function()
		while true do
			task.wait(0.25)
			for player, state in states do
				if not player.Parent or not state.HeroId then
					continue
				end
				if not PlayerStateService.canRegenResources(player) then
					continue
				end

				local prevStamina = state.Stamina
				local prevEnergy = state.Energy
				state.Stamina = math.min(Constants.MAX_STAMINA, state.Stamina + Constants.STAMINA_REGEN * 0.25)
				state.Energy = math.min(Constants.MAX_ENERGY, state.Energy + Constants.ENERGY_REGEN * 0.25)

				if state.Stamina ~= prevStamina or state.Energy ~= prevEnergy then
					onStatUpdate(player)
				end
			end
		end
	end)
end

return PlayerStateService
