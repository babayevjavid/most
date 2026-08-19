local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Powers = require(ReplicatedStorage.Shared.Powers)
-- Modules live under the Rojo folder "Server"; entry script may be parented to SSS or to that folder.
local serverFolder = script.Parent.Name == "Server" and script.Parent or ServerScriptService:WaitForChild("Server")
local CharacterOverhead = require(serverFolder:WaitForChild("CharacterOverhead"))
local LightningEServer = require(serverFolder:WaitForChild("LightningEServer"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local powerSelected = remotes:WaitForChild("PowerSelected") :: RemoteEvent

CharacterOverhead.init()
LightningEServer.init(remotes)

-- Clear power only on respawn (2nd+ CharacterAdded), not on Humanoid.Died — so picker shows after reset, not while dead.
local hadFirstSpawn: { [Player]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function hookPlayerRespawnPowerReset(player: Player)
	player.CharacterAdded:Connect(function()
		if hadFirstSpawn[player] then
			player:SetAttribute("SelectedPower", nil)
		else
			hadFirstSpawn[player] = true
		end
	end)
	if player.Character then
		hadFirstSpawn[player] = true
	end
end

for _, plr in Players:GetPlayers() do
	hookPlayerRespawnPowerReset(plr)
end
Players.PlayerAdded:Connect(hookPlayerRespawnPowerReset)
Players.PlayerRemoving:Connect(function(p)
	hadFirstSpawn[p] = nil
end)

powerSelected.OnServerEvent:Connect(function(player: Player, powerName: unknown)
	if typeof(powerName) ~= "string" or not Powers.isValid(powerName) then
		return
	end
	if player:GetAttribute("SelectedPower") ~= nil then
		return
	end
	player:SetAttribute("SelectedPower", powerName)
	if player.Character then
		CharacterOverhead.attach(player, player.Character)
	end
end)
