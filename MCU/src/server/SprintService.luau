--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterService = require(script.Parent.CharacterService)
local GameConstants = require(ReplicatedStorage.Shared.GameConstants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local SprintService = {}

local wantSprint: { [Player]: boolean } = {}
local lastSprintStop: { [Player]: number } = {}

function SprintService.update(dt: number)
	local dtClamped = math.clamp(dt, 0.001, 0.1)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if not character or character:GetAttribute(GameConstants.HERO_ATTRIBUTE) == nil then
			continue
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			continue
		end

		local stamina = character:GetAttribute(GameConstants.STAMINA_ATTRIBUTE)
		local maxStamina = character:GetAttribute(GameConstants.MAX_STAMINA_ATTRIBUTE)
		if type(stamina) ~= "number" or type(maxStamina) ~= "number" then
			continue
		end

		local blocked = CharacterService.isSprintBlocked(character)
		local trying = wantSprint[player] == true and not blocked and stamina > 0
		local moving = humanoid.MoveDirection.Magnitude > 0.05

		if trying and moving then
			character:SetAttribute(GameConstants.SPRINTING_ATTRIBUTE, true)
			humanoid.WalkSpeed = GameConstants.SPRINT_WALK_SPEED
			stamina = math.max(0, stamina - GameConstants.STAMINA_DRAIN_PER_SEC * dtClamped)
			character:SetAttribute(GameConstants.STAMINA_ATTRIBUTE, stamina)
			if stamina <= 0 then
				wantSprint[player] = false
				lastSprintStop[player] = os.clock()
			end
		else
			if character:GetAttribute(GameConstants.SPRINTING_ATTRIBUTE) == true then
				character:SetAttribute(GameConstants.SPRINTING_ATTRIBUTE, nil)
				lastSprintStop[player] = os.clock()
			end
			if not blocked then
				humanoid.WalkSpeed = GameConstants.DEFAULT_WALK_SPEED
			end
			local stoppedAt = lastSprintStop[player] or 0
			if (os.clock() - stoppedAt) >= GameConstants.STAMINA_REGEN_DELAY then
				if stamina < maxStamina then
					stamina = math.min(maxStamina, stamina + GameConstants.STAMINA_REGEN_PER_SEC * dtClamped)
					character:SetAttribute(GameConstants.STAMINA_ATTRIBUTE, stamina)
				end
			end
		end
	end
end

function SprintService.init()
	Remotes.getEvent("SprintInput").OnServerEvent:Connect(function(player: Player, payload: any)
		if type(payload) ~= "table" then
			return
		end
		if payload.dash == true then
			local mx = if type(payload.moveX) == "number" then payload.moveX else 0
			local mz = if type(payload.moveZ) == "number" then payload.moveZ else 0
			local move = Vector3.new(mx, 0, mz)
			if move.Magnitude < 0.05 then
				return
			end
			local ok, ScarletWitchService = pcall(function()
				return require(script.Parent.ScarletWitchService)
			end)
			if ok and ScarletWitchService and type(ScarletWitchService.tryHexDash) == "function" then
				ScarletWitchService.tryHexDash(player, move.Unit)
			end
			return
		end
		wantSprint[player] = payload.sprinting == true
		if payload.sprinting ~= true then
			lastSprintStop[player] = os.clock()
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		wantSprint[player] = nil
		lastSprintStop[player] = nil
	end)
end

return SprintService
