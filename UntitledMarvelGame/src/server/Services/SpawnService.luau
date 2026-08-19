--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))

local SpawnService = {}

local spawnPoints: { BasePart } = {}

local function collectSpawnPoints()
	table.clear(spawnPoints)
	local spawnFolder = workspace:FindFirstChild("SpawnPoints")
	if spawnFolder then
		for _, child in spawnFolder:GetChildren() do
			if child:IsA("BasePart") then
				table.insert(spawnPoints, child)
			elseif child:IsA("SpawnLocation") then
				table.insert(spawnPoints, child)
			end
		end
	end
	for _, child in workspace:GetChildren() do
		if child:IsA("SpawnLocation") then
			table.insert(spawnPoints, child)
		end
	end
end

function SpawnService.init()
	collectSpawnPoints()
	workspace.ChildAdded:Connect(function(child)
		if child:IsA("SpawnLocation") then
			table.insert(spawnPoints, child)
		end
	end)
end

function SpawnService.getSpawnCFrame(): CFrame
	if #spawnPoints == 0 then
		collectSpawnPoints()
	end
	if #spawnPoints > 0 then
		local part = spawnPoints[math.random(1, #spawnPoints)]
		return part.CFrame + Vector3.new(0, 3, 0)
	end
	return CFrame.new(Constants.SPAWN_FALLBACK)
end

function SpawnService.teleportCharacter(character: Model)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	root.CFrame = SpawnService.getSpawnCFrame()
end

return SpawnService
