-- Clones StarterPlayer.StarterCharacter once per entry in CharacterConfig.Choices, placed in a row
-- just beyond the first enabled SpawnLocation so each role has a stand-in body (combat/target tests).
-- Requires a StarterCharacter model in Studio.

local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

local shared = ReplicatedStorage:WaitForChild("Shared", 30)
if not shared then
	warn("[StarterCharacterNpcSpawn] ReplicatedStorage.Shared missing.")
	return
end

local okCfg, CharacterConfig = pcall(require, shared:WaitForChild("CharacterConfig", 10))
if not okCfg or type(CharacterConfig) ~= "table" then
	warn("[StarterCharacterNpcSpawn] Failed to require CharacterConfig.")
	return
end

local okGh, GameHealth = pcall(require, shared:WaitForChild("GameHealth", 10))
if not okGh or type(GameHealth) ~= "table" then
	warn("[StarterCharacterNpcSpawn] Failed to require GameHealth.")
	return
end

local template: Model? = StarterPlayer.StarterCharacter
if not template then
	template = StarterPlayer:FindFirstChild("StarterCharacter") :: Model?
end

if not template or not template:IsA("Model") then
	warn(
		"[StarterCharacterNpcSpawn] No StarterCharacter template — add a Model to StarterPlayer (StarterCharacter) in Studio, or this script does nothing."
	)
	return
end

local base = getSpawnCFrame()
local centerPos = base.Position + base.LookVector * 12
local right = base.RightVector
local choices = CharacterConfig.Choices
local n = #choices
local spread = (n - 1) * 0.5

for i, roleName in ipairs(choices) do
	local clone = template:Clone()
	clone.Name = "Showcase_" .. roleName
	clone.Parent = Workspace
	clone:SetAttribute("NpcFromStarterCharacter", true)
	clone:SetAttribute("NpcShowcase", true)
	-- Plain combat dummies only (no powers, no AI). Belthazor dummy is vanquish-eligible via attribute.
	if roleName == "Belthazor" then
		clone:SetAttribute("BelthazorVanquishTarget", true)
	end

	local ix = (i - 1) - spread
	local pos = centerPos + right * (ix * 6)
	local cf = CFrame.new(pos) * (base - base.Position)
	clone:PivotTo(cf)

	local hum = clone:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.NameDisplayDistance = 0
		hum.WalkSpeed = 0
		hum.JumpPower = 0
		hum.AutoRotate = false
	end

	local maxH = (CharacterConfig :: any).CombatMaxHealth
	if type(maxH) ~= "number" then
		maxH = 100
	end
	if roleName == "Belthazor" then
		local bMax = (CharacterConfig :: any).BelthazorCombatHealth
		if type(bMax) == "number" then
			maxH = bMax
		end
	end
	GameHealth.initCharacter(clone, maxH)
end
