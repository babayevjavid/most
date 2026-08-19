--!strict
--[[
	Death handling: ragdoll corpse, default Roblox respawn flow.
]]

local Players = game:GetService("Players")

local DeathService = {}

local function ragdollCharacter(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health > 0 then
		return
	end
	character:SetAttribute("Ragdolled", true)
	humanoid.PlatformStand = true
	pcall(function()
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	end)
end

local function bindCharacter(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	humanoid.BreakJointsOnDeath = false
	humanoid.Died:Once(function()
		ragdollCharacter(character)
	end)
end

function DeathService.setup()
	Players.CharacterAutoLoads = true

	local function onPlayerAdded(plr: Player)
		plr.CharacterAdded:Connect(bindCharacter)
		if plr.Character then
			bindCharacter(plr.Character)
		end
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, plr in Players:GetPlayers() do
		onPlayerAdded(plr)
	end
end

return DeathService
