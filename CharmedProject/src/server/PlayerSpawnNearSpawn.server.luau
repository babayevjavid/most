-- After each player character loads, move them to the first enabled SpawnLocation (with a small
-- spread) so everyone plays in the same hub where powers/spells are set up.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local function getSpawnCFrame(): CFrame
	local spawns: { SpawnLocation } = {}
	for _, inst in Workspace:GetDescendants() do
		if inst:IsA("SpawnLocation") and inst.Enabled then
			table.insert(spawns, inst :: SpawnLocation)
		end
	end
	if #spawns == 0 then
		return CFrame.new(0, 10, 0)
	end
	table.sort(spawns, function(a, b)
		return a.Name < b.Name
	end)
	local s = spawns[1]
	local topY = s.Position.Y + s.Size.Y * 0.5
	local pos = Vector3.new(s.Position.X, topY + 2.5, s.Position.Z)
	local y = math.rad(s.Orientation.Y)
	return CFrame.new(pos) * CFrame.Angles(0, y, 0)
end

local function offsetForPlayer(player: Player): Vector3
	local u = player.UserId
	local angle = (u % 360) * math.pi / 180
	local r = 4 + (u % 7) * 0.35
	return Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)
end

local function teleportToSpawn(player: Player, character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 12)
	if not root then
		return
	end
	RunService.Heartbeat:Wait()
	local base = getSpawnCFrame()
	local pos = base.Position + offsetForPlayer(player)
	local cf = CFrame.new(pos) * (base - base.Position)
	character:PivotTo(cf)
end

local function onPlayerCharacterAdded(player: Player, character: Model)
	task.spawn(function()
		teleportToSpawn(player, character)
	end)
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		onPlayerCharacterAdded(player, character)
	end)
end)

for _, player in Players:GetPlayers() do
	player.CharacterAdded:Connect(function(character)
		onPlayerCharacterAdded(player, character)
	end)
	local char = player.Character
	if char then
		task.defer(function()
			onPlayerCharacterAdded(player, char)
		end)
	end
end
