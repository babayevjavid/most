local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PowerConfig = require(Shared:WaitForChild("PowerConfig"))

local CosmicPowerVfx = {}

local activeEffects: { Instance } = {}

local function clearEffects()
	for _, effect in activeEffects do
		effect:Destroy()
	end
	table.clear(activeEffects)
end

local function addParticle(root: BasePart, color: Color3, style: string)
	local attachment = Instance.new("Attachment")
	attachment.Name = "PowerVfx_" .. style
	attachment.Parent = root

	local particles = Instance.new("ParticleEmitter")
	particles.Color = ColorSequence.new(color)
	particles.LightEmission = 0.8
	particles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 0),
	})
	particles.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	particles.Lifetime = NumberRange.new(0.4, 0.8)
	particles.Rate = 12
	particles.Speed = NumberRange.new(1, 3)
	particles.SpreadAngle = Vector2.new(360, 360)
	particles.Parent = attachment

	if style == "travel" then
		particles.Rate = 18
		particles.Speed = NumberRange.new(2, 5)
	elseif style == "territory" then
		particles.Rate = 24
		particles.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.5),
			NumberSequenceKeypoint.new(1, 0),
		})
	elseif style == "offense" then
		particles.Rate = 16
		particles.LightEmission = 1
	end

	table.insert(activeEffects, attachment)
end

local function addRing(root: BasePart, color: Color3)
	local ring = Instance.new("Part")
	ring.Name = "PowerRing"
	ring.Anchored = false
	ring.CanCollide = false
	ring.Size = Vector3.new(3.2, 0.08, 3.2)
	ring.Color = color
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.35
	ring.CFrame = root.CFrame * CFrame.new(0, -2.8, 0)
	ring.Parent = root

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = ring
	weld.Parent = ring

	table.insert(activeEffects, ring)
end

local function applyCharacterVfx(character: Model, equipped: { string })
	clearEffects()

	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	local hasTravel = false
	local hasTerritory = false
	local hasOffense = false
	local hasDefense = false
	local hasPassive = false
	local primaryColor = Color3.fromRGB(120, 220, 255)

	for _, powerId in equipped do
		local power = PowerConfig.Powers[powerId]
		if power then
			primaryColor = power.Color
			if power.AllowsTravel then
				hasTravel = true
			end
			if power.TerritoryDamage then
				hasTerritory = true
			end
			if power.Category == "Offense" then
				hasOffense = true
			elseif power.Category == "Defense" then
				hasDefense = true
			elseif power.Category == "Passive" then
				hasPassive = true
			end
		end
	end

	if #equipped == 0 then
		return
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = "PowerHighlight"
	highlight.FillTransparency = 0.85
	highlight.OutlineTransparency = 0.35
	highlight.FillColor = primaryColor
	highlight.OutlineColor = primaryColor
	highlight.Adornee = character
	highlight.Parent = character
	table.insert(activeEffects, highlight)

	if hasTravel then
		addParticle(root, Color3.fromRGB(120, 220, 255), "travel")
	end
	if hasTerritory then
		addRing(root, Color3.fromRGB(255, 220, 80))
		addParticle(root, Color3.fromRGB(255, 220, 80), "territory")
	end
	if hasOffense then
		addParticle(root, Color3.fromRGB(255, 120, 60), "offense")
	end
	if hasDefense then
		addParticle(root, Color3.fromRGB(90, 255, 140), "passive")
	end
	if hasPassive then
		addParticle(root, primaryColor, "passive")
	end
end

function CosmicPowerVfx.Start()
	local player = Players.LocalPlayer
	local remotes = ReplicatedStorage:WaitForChild("SuperpowerRemotes", 20)
	if not remotes then
		return
	end

	local powersSync = remotes:WaitForChild("PowersSync", 10) :: RemoteEvent
	if not powersSync then
		return
	end

	local latestEquipped: { string } = {}

	local function refreshCharacter()
		local character = player.Character
		if character then
			applyCharacterVfx(character, latestEquipped)
		end
	end

	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("HumanoidRootPart", 10)
		task.defer(refreshCharacter)
	end)

	powersSync.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		latestEquipped = payload.equipped or {}
		refreshCharacter()
	end)

	if player.Character then
		refreshCharacter()
	end
end

return CosmicPowerVfx
